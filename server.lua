Config = Config or {}

-- Load configuration
Citizen.CreateThread(function()
    print("Gonna load config...")
    while not Config.SurveillancePeds do
        Wait(100)
    end
    
    print("Loaded Config!")

    local surveillancePeds = Config.SurveillancePeds
    local defaultSpawnRadius = 400.0
    local defaultMaxSpawnDistance = 1000.0
    local defaultDespawnRadiusAlive = 600.0
    local defaultDespawnRadiusDead = 300.0

    local pendingSpawns = {}
    local spawnedPeds = {}
    local playerCoords = {}
    local guardCoords = {}

    local currentHost = nil
    -- Utility: Get a new host from the current players
    function GetNewHost()
        for player, _ in pairs(playerCoords) do
            -- print(player)
            return player -- Just return the first one
        end
        return nil
    end

    -- Assign a new host if needed
    function AssignHost()
        local newHost = GetNewHost()
        if newHost ~= currentHost then
            currentHost = newHost
            if currentHost then
                print(string.format("^5[HOST SYSTEM] Assigned new host: %s (ID: %d)", GetPlayerName(currentHost) or "Unknown", currentHost))
                TriggerClientEvent('guardHost:SetHost', currentHost, true)
            else
                print("^5[HOST SYSTEM] No players available to be host.")
            end
            -- Notify others they're not the host
            for player, _ in pairs(playerCoords) do
                if player ~= currentHost then
                    TriggerClientEvent('guardHost:SetHost', player, false)
                end
            end
        end
    end

    -- Initialize spawnedPeds table
    for i = 1, #surveillancePeds do
        spawnedPeds[i] = { spawned = false, alive = true }
    end

    -- Host control loop — runs every 7 seconds
    Citizen.CreateThread(function()
        while true do
            Wait(7000)

            -- Check if there are any players online
            if next(playerCoords) then
                -- If no current host, assign one
                if not currentHost then
                    print("^5[HOST SYSTEM] No host currently, assigning one...")
                    AssignHost()

                -- If host left, assign a new one
                elseif not playerCoords[currentHost] then
                    print(string.format("^5[HOST SYSTEM] Current host (ID: %d) missing, reassigning...", currentHost))
                    AssignHost()
                end
            else
                -- No players online, clear host
                if currentHost then
                    print("^5[HOST SYSTEM] No players online — clearing host.")
                    currentHost = nil
                end
            end
        end
    end)


    -- Update player coordinates
    RegisterNetEvent('updatePlayerCoords')
    AddEventHandler('updatePlayerCoords', function(coords)
        if coords and type(coords) == 'vector3' then
            playerCoords[source] = coords
            -- print('Player Coords updated')
        end
    end)

    RegisterNetEvent('updateGuardCoords')
    AddEventHandler('updateGuardCoords', function(guardIndex, coords)
        if guardIndex and coords and type(coords) == 'vector3' then
            guardCoords[guardIndex] = coords
        end
    end)

    -- Guard status update
    RegisterNetEvent('updateGuardStatus')
    AddEventHandler('updateGuardStatus', function(guardIndex, alive)
        if spawnedPeds[guardIndex] then
            spawnedPeds[guardIndex].alive = alive
        end
    end)

    -- Check conditions for all guards
    function CheckAllGuards()
        -- Don't proceed if no players are connected
        if not next(playerCoords) then
            for i = 1, #surveillancePeds do
                if spawnedPeds[i].spawned then
                    if currentHost then
                        TriggerClientEvent('deleteGuard', currentHost, i)
                    end                    
                    spawnedPeds[i].spawned = false
                end
            end
            return
        end
    
        for i, guardConfig in ipairs(surveillancePeds) do
            -- Skip if already pending spawn
            if pendingSpawns[i] then
                if spawnedPeds[i].spawned then
                    pendingSpawns[i] = nil
                end
                goto continue
            end
    
            local currentState = spawnedPeds[i]
            local spawnRadius = guardConfig.spawnRadius or defaultSpawnRadius
            local maxSpawnDistance = guardConfig.maxSpawnDistance or defaultMaxSpawnDistance
            local despawnRadiusAlive = guardConfig.despawnRadiusAlive or defaultDespawnRadiusAlive
            local despawnRadiusDead = guardConfig.despawnRadiusDead or defaultDespawnRadiusDead
    
            local currentDespawnRadius = currentState.alive and despawnRadiusAlive or despawnRadiusDead
    
            local spawnCoords = guardConfig.coords
            local currentGuardCoords = currentState.spawned and guardCoords[i] or spawnCoords
    
            local allPlayersBeyondSpawn = true
            local anyPlayerWithinMaxDistance = false
            local anyPlayerWithinDespawn = false

            -- Log guard info
            print(string.format("^3[GUARD CHECK] Guard %d: Spawned=%s, Alive=%s",
            i, tostring(currentState.spawned), tostring(currentState.alive)))

            -- Print guard coords
            print(string.format("^3[GUARD CHECK] Guard %d position: x=%.2f, y=%.2f, z=%.2f",
                i, guardConfig.coords.x, guardConfig.coords.y, guardConfig.coords.z))
    
            for _, coords in pairs(playerCoords) do
                -- Print player position
                print(string.format("^2[PLAYER POS] Player %d: x=%.2f, y=%.2f, z=%.2f",
                playerId, coords.x, coords.y, coords.z))
                if coords then
                    local distanceToSpawn = #(coords - spawnCoords)
                    local distanceToGuard = #(coords - currentGuardCoords)
    
                    if distanceToSpawn <= spawnRadius then
                        allPlayersBeyondSpawn = false
                    end
                    if distanceToSpawn <= maxSpawnDistance then
                        anyPlayerWithinMaxDistance = true
                    end
                    if distanceToGuard <= currentDespawnRadius then
                        anyPlayerWithinDespawn = true
                    end
                end
            end
    
            -- Handle despawning
            if currentState.spawned and not anyPlayerWithinDespawn then
                TriggerClientEvent('deleteGuard', -1, i)
                spawnedPeds[i].spawned = false
                print(string.format("^3SERVER: Despawned guard %d (no players within %.1f units)", i, currentDespawnRadius))
    
            -- Handle spawning with additional checks
            elseif not currentState.spawned and allPlayersBeyondSpawn and anyPlayerWithinMaxDistance then
                pendingSpawns[i] = true
                spawnedPeds[i].spawned = true
                spawnedPeds[i].alive = true
                if currentHost then
                    TriggerClientEvent('spawnGuard', currentHost, i)
                end                
                -print(string.format("^3SERVER: Spawned guard %d (players between %.1f-%.1f units)", i, spawnRadius, maxSpawnDistance))
            end
    
            ::continue::
        end
    end

    -- Main control loop
    Citizen.CreateThread(function()
        while true do
            CheckAllGuards()
            Wait(2000)
        end
    end)

end)