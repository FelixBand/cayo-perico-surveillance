Config = Config or {}

-- Load configuration
Citizen.CreateThread(function()
    while not Config.SurveillancePeds do
        Wait(100)
    end

    local isHost = false

    RegisterNetEvent('guardHost:SetHost')
    AddEventHandler('guardHost:SetHost', function(status)
        isHost = status
        print(string.format("^6[CLIENT] You are %s host", isHost and "NOW" or "NOT"))
    end)
    
    local surveillancePeds = Config.SurveillancePeds

    local spawnedGuards = {}
    
    -- Cayo Perico Dispatch Toggle (No cops on the island)
    Citizen.CreateThread(function()
        local player = PlayerId()
    
        while true do
            Citizen.Wait(3000)
    
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
    
            -- Cayo Perico bounds
            local isInCayo = coords.x >= 3500 and coords.x <= 5800 and coords.y <= -4000 and coords.y >= -6200
    
            -- Toggle cop dispatch accordingly
            SetDispatchCopsForPlayer(player, not isInCayo)
        end
    end)    

    -- Initialize relationship groups
    Citizen.CreateThread(function()
        AddRelationshipGroup("HOSTILE_GUARDS")
        SetRelationshipBetweenGroups(5, GetHashKey("HOSTILE_GUARDS"), GetHashKey("PLAYER"))
        SetRelationshipBetweenGroups(5, GetHashKey("PLAYER"), GetHashKey("HOSTILE_GUARDS"))
    end)

    -- Coordinate and status updates
    Citizen.CreateThread(function()
        while true do
            local playerPed = PlayerPedId()
            if DoesEntityExist(playerPed) then
                local coords = GetEntityCoords(playerPed)
                if coords then
                    TriggerServerEvent('updatePlayerCoords', coords)
                    
                    -- Update status for all spawned guards
                    for guardIndex, guardData in pairs(spawnedGuards) do
                        if guardData.ped and DoesEntityExist(guardData.ped) then
                            TriggerServerEvent('updateGuardStatus', guardIndex, not IsEntityDead(guardData.ped))
                    
                            -- Send current position of the guard
                            local guardPos = GetEntityCoords(guardData.ped)
                            TriggerServerEvent('updateGuardCoords', guardIndex, guardPos)
                        end
                    end
                end
            end
            Wait(2500)
        end
    end)

    -- Spawn handler with relationship setup
    RegisterNetEvent('spawnGuard')
    AddEventHandler('spawnGuard', function(guardIndex)
        if not isHost then return end
        local config = surveillancePeds[guardIndex]
        if not config then return end
        
        if not spawnedGuards[guardIndex] or not DoesEntityExist(spawnedGuards[guardIndex].ped) then
            -- Load ped model
            RequestModel(config.model)
            while not HasModelLoaded(config.model) do
                Wait(10)
            end

            local ped, vehicle = nil, nil

            -- Create vehicle if specified
            if config.vehicle then
                RequestModel(config.vehicle)
                while not HasModelLoaded(config.vehicle) do
                    Wait(10)
                end

                vehicle = CreateVehicle(GetHashKey(config.vehicle), config.coords.x, config.coords.y, config.coords.z, config.heading, true, false)
                ped = CreatePedInsideVehicle(vehicle, 4, GetHashKey(config.model), -1, true, false)
                
                SetVehicleEngineOn(vehicle, true, true, false)
                SetVehicleDoorsLocked(vehicle, 0)
            else
                ped = CreatePed(4, GetHashKey(config.model), config.coords.x, config.coords.y, config.coords.z, config.heading, true, true)
            end

            if DoesEntityExist(ped) then
                -- Basic setup
                SetEntityAsMissionEntity(ped, true, true)
                -- In the spawnGuard event, modify the weapon giving section:
                GiveWeaponToPed(ped, GetHashKey(config.weapon), 9999, true, true)

                -- Combat attributes
                SetPedCombatAttributes(ped, 46, true) -- Ped is allowed to fight armed peds when not armed
                SetPedCombatAttributes(ped, 8, true) -- "CA_PLAY_REACTION_ANIMS"
                SetPedCombatAttributes(ped, 15, true) -- Ped can use a radio to call for backup (happens after a reaction)
                SetPedCombatAttributes(ped, 22, true) -- Ped can drag injured peds to safety
                SetPedCombatAttributes(ped, 39, true) -- Allows ped to bust the player
                SetPedFleeAttributes(ped, 0, false)
                SetPedAsEnemy(ped, true)
                SetPedCombatRange(ped, 1) -- 0=Near, 1=Medium, 2=Far
                SetPedCombatMovement(ped, 1) -- 0=Stationary, 1=Defensive, 2=Offensive
                SetPedCombatAbility(ped, 1) -- 0=Poor, 1=Average, 2=Professional
                SetPedAccuracy(ped, 40) -- 0-100
                
                -- Relationship setup
                SetPedRelationshipGroupHash(ped, GetHashKey("HOSTILE_GUARDS"))
                SetPedAlertness(ped, 2) -- Maximum alertness
                SetPedSeeingRange(ped, 45.0)
                SetPedHearingRange(ped, 80.0)

                if config.vehicle then
                    TaskVehicleDriveWander(ped, vehicle, 15.0, 786468)
                    SetPedCombatAttributes(ped, 1, true) -- Can use Vehicles
                    SetPedCombatAttributes(ped, 2, true) -- Can do drive-bys
                    SetPedCombatAttributes(ped, 3, true) -- Can leave vehicle if driving/spawned in one
                elseif config.behavior == "sniper" then
                    SetPedCombatRange(ped, 2) -- Long range combat
                    SetPedCombatMovement(ped, 0) -- Stationary
                    SetPedCombatAbility(ped, 2) -- Professional
                    
                    SetPedAccuracy(ped, 25) -- 0-100
                    SetPedSeeingRange(ped, 150.0) -- Increased vision range
                    SetPedHearingRange(ped, 150.0)
                    
                    -- Sniper behavior
                    TaskCombatHatedTargetsAroundPed(ped, 100.0, 0)
                    SetPedKeepTask(ped, true)
                    
                    SetPedPathCanUseClimbovers(ped, false)
                    SetPedPathCanDropFromHeight(ped, false)
                    SetPedPathCanUseLadders(ped, false)
                elseif config.behavior == "stand" then
                    TaskStandGuard(ped, config.coords.x, config.coords.y, config.coords.z, config.heading, "WORLD_HUMAN_GUARD_STAND", false)
                elseif config.behavior == "wander" then
                    TaskWanderStandard(ped, 10.0, 10)
                elseif config.behavior == "compound_wander" then
                    TaskWanderStandard(ped, 10.0, 10)

                    SetPedSeeingRange(ped, 18.0)
                    SetPedHearingRange(ped, 80.0)
                    SetPedCombatMovement(ped, 1) -- Defensive
                    SetPedCombatRange(ped, 0) -- Near
                elseif config.behavior == "compound_stand" then
                    TaskStandGuard(ped, config.coords.x, config.coords.y, config.coords.z, config.heading, "WORLD_HUMAN_GUARD_STAND", false)

                    SetPedSeeingRange(ped, 18.0)
                    SetPedHearingRange(ped, 80.0)
                    SetPedCombatMovement(ped, 1) -- Defensive
                    SetPedCombatRange(ped, 0) -- Near
                elseif config.behavior == "tank" then -- This is the compound juggernaut's behavior
                    SetPedSeeingRange(ped, 15.0)
                    SetPedHearingRange(ped, 70.0)
                    SetPedCombatMovement(ped, 1) -- Defensive
                    SetPedCombatRange(ped, 0) -- Near

                    TaskWanderStandard(ped, 10.0, 10)
                    SetEntityMaxHealth(ped, 500)
                    SetEntityHealth(ped, 500)
                    SetPedArmour(ped, 500)
            
                    -- Disable ragdoll
                    SetPedCanRagdoll(ped, false)
                    SetPedRagdollBlockingFlags(ped, 1)
                    SetPedCanRagdollFromPlayerImpact(ped, false)
            
                    -- Extra toughness
                    SetPedSuffersCriticalHits(ped, false)
            
                    -- Optional: immune to knock-offs on a vehicle
                    SetPedCanBeKnockedOffVehicle(ped, 1)
                end

                -- Store reference
                spawnedGuards[guardIndex] = {
                    ped = ped,
                    vehicle = vehicle,
                    alive = true
                }
                
                print(string.format("^2CLIENT: Spawned hostile guard %d (%s)%s", guardIndex, config.model, config.vehicle and " in vehicle "..config.vehicle or ""))
            else
                if vehicle and DoesEntityExist(vehicle) then
                    DeleteEntity(vehicle)
                end
            end
        end
    end)

    -- Enhanced despawn handler with vehicle cleanup
    RegisterNetEvent('deleteGuard')
    AddEventHandler('deleteGuard', function(guardIndex)
        if not isHost then return end
        if spawnedGuards[guardIndex] then
            local guardData = spawnedGuards[guardIndex]
            
            -- Delete ped
            if guardData.ped and DoesEntityExist(guardData.ped) then
                -- Network cleanup
                if NetworkGetEntityIsNetworked(guardData.ped) then
                    NetworkRequestControlOfEntity(guardData.ped)
                    local timeout = 100
                    while not NetworkHasControlOfEntity(guardData.ped) and timeout > 0 do
                        Wait(10)
                        timeout = timeout - 1
                    end
                end
                
                SetEntityAsMissionEntity(guardData.ped, false, true)
                DeleteEntity(guardData.ped)
            end
            
            -- Delete vehicle
            if guardData.vehicle and DoesEntityExist(guardData.vehicle) then
                -- Check if any player is in the vehicle
                local canDelete = true
                for _, player in ipairs(GetActivePlayers()) do
                    local playerPed = GetPlayerPed(player)
                    if IsPedInVehicle(playerPed, guardData.vehicle, false) then
                        canDelete = false
                        break
                    end
                end
                
                if canDelete then
                    if NetworkGetEntityIsNetworked(guardData.vehicle) then
                        NetworkRequestControlOfEntity(guardData.vehicle)
                        local timeout = 100
                        while not NetworkHasControlOfEntity(guardData.vehicle) and timeout > 0 do
                            Wait(10)
                            timeout = timeout - 1
                        end
                    end
                    SetEntityAsMissionEntity(guardData.vehicle, false, true)
                    DeleteEntity(guardData.vehicle)
                end
            end
            
            spawnedGuards[guardIndex] = nil
            print(string.format("^2CLIENT: Despawned guard %d", guardIndex))
        end
    end)

    -- Enhanced debug command
    RegisterCommand("guardinfo", function()
        local playerCoords = GetEntityCoords(PlayerPedId())
        print("===== GUARD INFO =====")
        for i, config in ipairs(surveillancePeds) do
            local distance = #(playerCoords - config.coords)
            local status = "NOT SPAWNED"
            if spawnedGuards[i] then
                status = spawnedGuards[i].alive and "ALIVE" or "DEAD"
                if not DoesEntityExist(spawnedGuards[i].ped) then
                    status = status.." (ENTITY MISSING)"
                end
                if spawnedGuards[i].vehicle then
                    status = status.." IN VEHICLE"
                    if not DoesEntityExist(spawnedGuards[i].vehicle) then
                        status = status.." (VEHICLE MISSING)"
                    end
                end
            end
            print(string.format("Guard %d: %s | Distance: %.1f | Status: %s | Vehicle: %s", 
                i, config.model, distance, status, config.vehicle or "NONE"))
        end
    end)

end)