print("[ULC]: Stage Controls Loaded")

Lights = false
local activeButtons = {}
local showingHelp = false
local waitingForLoad = true

-- if IsPedInAnyVehicle(startPed) then
--   TriggerServerEvent('baseevents:enteredVehicle')
-- end

-------------------------
--------- SOUND ---------
-------------------------

function PlayBeep(highPitched)
  if highPitched then
    PlaySoundFrontend(-1, "5_SEC_WARNING", "HUD_MINI_GAME_SOUNDSET", 1)
  else
    PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", 1)
  end
end

------------------
------ HELP ------
------------------

function ShowHelp()
  CreateThread(function()
    if not showingHelp then
      -- show help
      showingHelp = true
      for k, v in ipairs(activeButtons) do
        print('Showing help for button: ' .. k .. ' : ' .. v.key)
        SendNUIMessage({
          type = 'showHelp',
          button = k,
          key = v.key,
        })
      end
      Wait(3000)
      -- hide help
      showingHelp = false
      for k, v in ipairs(activeButtons) do
        SendNUIMessage({
          type = 'hideHelp',
          button = k,
          label = v.label,
        })
      end
    end
  end)
end

------------------------------------
------------------------------------
------- LIGHTS STATE HANDLER -------
------------------------------------
------------------------------------

-- These 2 events need to be received from Luxart, the ones currently below are from luxart v1, need to update
-- From what I can see so far, there is no longer an event for this in luxart v3
-- we can just check every 250 frames or something, and leave this in for anyone using old version i guess?

-- Going with loop method for now.
AddEventHandler('ulc:lightsOn', function()
  --print("Lights On")
  -- set Lights on
  Lights = true
  -- check if parked or driving for park patterns
  TriggerEvent('ulc:checkParkState', GetVehiclePedIsIn(PlayerPedId()), false)
  SendNUIMessage({
    type = 'toggleIndicator',
    state = Lights
  })

  if not Config.muteBeepForLights then
    PlayBeep(true)
  end

end)

AddEventHandler('ulc:lightsOff', function()
  --print("Lights Off")
  Lights = false
  SendNUIMessage({
    type = 'toggleIndicator',
    state = Lights
  })

  if not Config.muteBeepForLights then
    PlayBeep(false)
  end

end)

-- check if lights are on 10 times a second;
-- used to trigger above events
CreateThread(function()
  while true do
    Wait(100)
    if IsVehicleSirenOn(GetVehiclePedIsIn(PlayerPedId())) then
      if not Lights then
        TriggerEvent('ulc:lightsOn')
      end
    else
      if Lights then
        TriggerEvent('ulc:lightsOff')
      end
    end
  end
end)

---------------------------
---------------------------
-------- MAIN CODE --------
---------------------------
---------------------------

-- this event is called whenever player enters vehicle
RegisterNetEvent('ulc:checkVehicle')
AddEventHandler('ulc:checkVehicle', function()
  CreateThread(function()
    while waitingForLoad do
      print("ULC: Waiting for load.")
      Wait(100)
    end
    print("Checking for vehicle configuration")
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped)
    local passed, vehicleConfig = GetVehicleFromConfig(vehicle)

    print(passed, vehicleCOnfig)

    if passed then
      --print("Found vehicle.")
      -- clear any existing buttons from hud
      SendNUIMessage({
        type = 'clearButtons',
      })

      activeButtons = {}

      -- if i am driver
      if ped == GetPedInVehicleSeat(vehicle, -1) then
        -- for each configured button on this vehicle
        for k, v in pairs(vehicleConfig.buttons) do
          -- determine state of button's extra
          local extraState = 1
          if IsVehicleExtraTurnedOn(vehicle, v.extra) then
            extraState = 0
          end 
          -- add/show and configure the button
          print("Adding button: " .. v.label)
          table.insert(activeButtons, v)
          SendNUIMessage({
            type = 'addButton',
            label = v.label,
            extra = v.extra,
            state = extraState
          })
        end

        if vehicleConfig.parkConfig.usePark then
          SendNUIMessage({
            type = 'showParkIndicator',
          })
        end

        if vehicleConfig.brakeConfig.useBrakes then
          SendNUIMessage({
            type = 'showBrakeIndicator',
          })
        end

        ShowHelp()

        -- when done
        -- show hud
        SendNUIMessage({
          type = 'showLightsHUD',
        })

        TriggerEvent('ulc:checkLightTime')
        TriggerEvent('ulc:checkParkState', true)
      end
    end
  end)
end)

-- used to hide the hud
RegisterNetEvent('ulc:cleanupHUD')
AddEventHandler('ulc:cleanupHUD', function()
  -- hide hud
  SendNUIMessage({
    type = 'hideLightsHUD',
  })
end)
-----------------
--- NEW STUFF ---
-----------------

-- Get the extra associated with a key in vehicle configuration
function GetExtraForVehicleKey(vehicle, key)
  local passed, vehicleConfig = GetVehicleFromConfig(vehicle)
  if passed then
    for k, v in pairs(vehicleConfig.buttons) do
      if v.key == key then
        return v.extra
      end
    end
  end
end

-- get whether the specified extra is bound to any key in vehicle configuration
function IsExtraUsedByAnyVehicleKey(extra)
  local veh = GetVehiclePedIsIn(PlayerPedId())
  local passed, vehicleConfig = GetVehicleFromConfig(veh)
  if passed then
    for k, v in pairs(vehicleConfig.buttons) do
      if v.extra == extra then
        return true
      end
    end
  end
end

-- Change stage by extra;
-- This is the main "do the thing" function
function SetStageByExtra(extra, newState, playSound)
  local veh = GetVehiclePedIsIn(PlayerPedId())
  -- print("Setting button for extra " .. extra .. " to " .. newState)
  -- toggle extra
  SetVehicleExtra(veh, extra, newState)

  if IsExtraUsedByAnyVehicleKey(extra) then

    if playSound then
      if newState == 0 then
        PlayBeep(true)
      else
        PlayBeep(false)
      end
    end
    -- send message to JS to update HUD
    SendNUIMessage({
      type = 'setButton',
      extra = extra,
      state = newState
    })
  end
end

-- Sets the stage of the vehicle, 0 enables, 1 disables, 2 toggles; 
-- This is just a pass through, does some checks and then calls SetStageByExtra() function;
-- Note this is called by key, while other function is called by Extra
AddEventHandler('ulc:setStage', function(key, action, playSound)

  local vehicle = GetVehiclePedIsIn(PlayerPedId())
  local extra = GetExtraForVehicleKey(vehicle, key)


  if AreVehicleDoorsClosed(vehicle) and IsVehicleHealthy(vehicle) then

    local state = IsVehicleExtraTurnedOn(vehicle, extra) -- returns true if enabled
    -- new stage state as extra disable (1 is disable, 0 is enable)
    local newState = null

    -- stage is on
    if state then
	--print("[ulc:setStage] Stage is on")
      if action == 1 or action == 2 then
        newState = 1
        SetStageByExtra(extra, newState, playSound)
      end
    -- stage is off
    else
	--print("[ulc:setStage] Stage is off")
      if action == 0 or action == 2 then
        newState = 0
        SetStageByExtra(extra, newState, playSound)
      end
    end
  end
end)

RegisterNetEvent('UpdateVehicleConfigs', function(newData)
  print("Updating Vehicle Table")
  Config.Vehicles = newData
  waitingForLoad = false
end)

-----------------------
-----------------------
------ KEYBINDS -------
-----------------------
-----------------------

for i = 1, 9, 1 do
  RegisterKeyMapping('ulc:num' .. i, 'Toggle ULC Slot ' .. i , 'keyboard', 'NUMPAD' .. i)
  RegisterCommand('ulc:num' .. i, function()
    TriggerEvent('ulc:setStage', i, 2, true)
  end)
end

-- i guess this is for when you are in a vehicle and immediately spawn a new one with a menu?
-- not sure, this was a while ago and i didn't comment it : )
CreateThread(function()
  local lastVehicle = nil
  while true do Wait(500)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped) then
      local vehicle = GetVehiclePedIsIn(ped)
      if vehicle ~= lastVehicle then
        TriggerServerEvent('baseevents:enteredVehicle')
      end
      lastVehicle = GetVehiclePedIsIn(ped)
    end
  end
end)