if not game:IsLoaded() then
    game.Loaded:Wait()
end

local scriptId = "auto_collector_final"
local maxRetryAttempts = 3
local scriptActive = false

local function initializeScript()
    if scriptActive then
        return false
    end

    local now = os.time()
    local existingMarker = getgenv()[scriptId]
    
    local canTakeOver = true
    if existingMarker then
        if type(existingMarker) == "table" then
            if existingMarker.alive and now - existingMarker.lastHeartbeat <= 1.5 then
                canTakeOver = false
            end
        else
            if now - existingMarker <= 2 then
                canTakeOver = false
            end
        end
    end
    
    if not canTakeOver then
        return false
    end

    local ownerToken = tostring(math.random(1000000000, 9999999999)) .. "_" .. tostring(now)
    local currentGeneration = (existingMarker and type(existingMarker) == "table" and existingMarker.generation or 0) + 1
    
    getgenv()[scriptId] = {
        owner = ownerToken,
        generation = currentGeneration,
        lastHeartbeat = now,
        alive = true,
        progressCount = 0,
        lastProgressTime = now
    }
    scriptActive = true

    local connections = {}
    local heartbeatTask
    local progressTracker = {
        lastItemCount = 0,
        lastPendingCount = 0,
        lastServerRefresh = 0
    }
    local PermanentSet = {}

    local function updateProgress()
        local marker = getgenv()[scriptId]
        if marker and type(marker) == "table" and marker.owner == ownerToken and marker.generation == currentGeneration then
            marker.progressCount = marker.progressCount + 1
            marker.lastProgressTime = os.time()
        end
    end

    local function cleanup()
        scriptActive = false
        local marker = getgenv()[scriptId]
        if marker and type(marker) == "table" and marker.owner == ownerToken and marker.generation == currentGeneration then
            getgenv()[scriptId] = nil
        end
        
        if heartbeatTask then
            pcall(function()
                task.cancel(heartbeatTask)
            end)
        end
        
        for _, conn in ipairs(connections) do
            if conn then
                pcall(function()
                    conn:Disconnect()
                end)
            end
        end
        connections = {}
    end

    local function checkOwnership()
        local marker = getgenv()[scriptId]
        if not marker or type(marker) ~= "table" then
            return false
        end
        if marker.owner ~= ownerToken or marker.generation ~= currentGeneration then
            return false
        end
        return true
    end

    local function updateHeartbeat()
        if not checkOwnership() then
            cleanup()
            return false
        end
        
        local marker = getgenv()[scriptId]
        local now = os.time()
        
        if now - marker.lastProgressTime > 30 then
            warn("Progress stalled for more than 30 seconds, cleaning up")
            cleanup()
            return false
        end
        
        marker.lastHeartbeat = now
        return true
    end

    heartbeatTask = task.spawn(function()
        local lastCheck = os.time()
        while task.wait(1) do
            if not updateHeartbeat() then
                break
            end
            
            local now = os.time()
            if now - lastCheck >= 10 then
                local marker = getgenv()[scriptId]
                if marker and marker.progressCount == 0 and now - marker.lastProgressTime > 20 then
                    warn("No progress for a long time, restarting")
                    cleanup()
                    break
                end
                lastCheck = now
            end
        end
    end)

    local function trackConnection(conn)
        table.insert(connections, conn)
        return conn
    end

    local success, err = pcall(function()
        if not getgenv() then 
            getgenv = function() 
                return _G 
            end 
        end
        if not getgenv().maxwaittime then
            getgenv().maxwaittime = 300
        end

        local Players = cloneref(game:GetService("Players"))
        local HttpService = cloneref(game:GetService("HttpService"))
        local TeleportService = cloneref(game:GetService("TeleportService"))
        local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
        local LocalPlayer = Players.LocalPlayer
        local Character
        local HumanoidRootPart
        local Humanoid

        if not LocalPlayer.Character then
            LocalPlayer.CharacterAdded:Wait()
        end
        Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
        Humanoid = Character:WaitForChild("Humanoid")

        trackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
            Character = char
            HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
            Humanoid = char:WaitForChild("Humanoid")
        end))

        trackConnection(LocalPlayer.OnTeleport:Connect(function(state)
            queue_on_teleport([[
                if not game:IsLoaded() then game.Loaded:Wait() end
                local Players = cloneref(game:GetService("Players"))
                local LocalPlayer = Players.LocalPlayer
                local Character
                local HumanoidRootPart
                local Humanoid
                Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
                HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
                Humanoid = Character:WaitForChild("Humanoid")
                loadstring(game:HttpGet('https://raw.githubusercontent.com/hyonkey/txt-ohioffts/refs/heads/main/ohiorose.lua'))()
            ]])
        end))

        local function getServers()
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
            for attempt = 1, 3 do
                local success, response = pcall(function()
                    return game:HttpGet(url)
                end)
                if success and response and response ~= "" then
                    local success2, data = pcall(function()
                        return HttpService:JSONDecode(response)
                    end)
                    if success2 then
                        updateProgress()
                        return data
                    end
                end
                if attempt < 4 then
                    task.wait(0.35 * attempt)
                end
            end
            return nil
        end

        local servers = getServers()
        local Serverlist = {}
        if servers and servers.data then
            for _, server in ipairs(servers.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    table.insert(Serverlist, server.id)
                end
            end
        end

        local itemdone = false
        local ItemPickups = {}
        local PendingItems = {}
        local lastServerRefresh = os.time()
        local absoluteTimeout = 450
        local startTime = os.time()

        local tableLock = false
        local function withLock(fn)
            while tableLock do
                task.wait(0.001)
            end
            tableLock = true
            local ok, result = pcall(fn)
            tableLock = false
            if not ok then
                warn("Table operation error: " .. tostring(result))
            end
            return ok, result
        end

        local function safeTableInsert(tbl, item)
            return withLock(function()
                table.insert(tbl, item)
            end)
        end

        local function safeTableRemove(tbl, index)
            return withLock(function()
                table.remove(tbl, index)
            end)
        end

        local function manageItemPickupsTable(newItem)
            local success = safeTableInsert(ItemPickups, newItem)
            if success then
                if #ItemPickups > 6000 then
                    safeTableRemove(ItemPickups, 1)
                end
                updateProgress()
            end
        end

        local function isValidPickup(obj)
            if not obj then return false end
            if not obj.Parent then return false end
            if obj:IsA("ProximityPrompt") then
                return obj.ObjectText ~= nil and obj.ObjectText ~= ""
            elseif obj:IsA("ClickDetector") then
                return true
            end
            return false
        end

        local function processExistingPickups()
            local itemPickupFolder = workspace:FindFirstChild("Game")
            if itemPickupFolder then
                itemPickupFolder = itemPickupFolder:FindFirstChild("Entities")
                if itemPickupFolder then
                    itemPickupFolder = itemPickupFolder:FindFirstChild("ItemPickup")
                    if itemPickupFolder then
                        for _, des in ipairs(itemPickupFolder:GetDescendants()) do
                            if des:IsA("ProximityPrompt") then
                                pcall(function() des.MaxActivationDistance = 0 end)
                                if des.ObjectText and des.ObjectText ~= "" then
                                    manageItemPickupsTable(des)
                                else
                                    table.insert(PendingItems, des)
                                end
                            elseif des:IsA("ClickDetector") then
                                manageItemPickupsTable(des)
                            end
                        end
                    end
                end
            end
        end

        processExistingPickups()

        local function setupItemPickupListener()
            local itemPickupFolder = workspace:FindFirstChild("Game")
            if itemPickupFolder then
                itemPickupFolder = itemPickupFolder:FindFirstChild("Entities")
                if itemPickupFolder then
                    itemPickupFolder = itemPickupFolder:FindFirstChild("ItemPickup")
                    if itemPickupFolder then
                        trackConnection(itemPickupFolder.DescendantAdded:Connect(function(des)
                            if des:IsA("ProximityPrompt") then
                                pcall(function() des.MaxActivationDistance = 0 end)
                                task.spawn(function()
                                    for attempt = 1, 300 do
                                        if not (des and des.Parent) then
                                            return
                                        end
                                        if des.ObjectText and des.ObjectText ~= "" then
                                            manageItemPickupsTable(des)
                                            return
                                        end
                                        task.wait(0.002)
                                    end
                                    for attempt = 1, 200 do
                                        if not (des and des.Parent) then
                                            return
                                        end
                                        if des.ObjectText and des.ObjectText ~= "" then
                                            manageItemPickupsTable(des)
                                            return
                                        end
                                        task.wait(0.005)
                                    end
                                    while des and des.Parent do
                                        if des.ObjectText and des.ObjectText ~= "" then
                                            manageItemPickupsTable(des)
                                            return
                                        end
                                        task.wait(0.01)
                                    end
                                end)
                            elseif des:IsA("ClickDetector") then
                                manageItemPickupsTable(des)
                            end
                        end))
                    end
                end
            end
        end

        setupItemPickupListener()

        local pendingCleanupTask
        pendingCleanupTask = task.spawn(function()
            local lastCleanup = os.time()
            while task.wait(0.5) do
                if not updateHeartbeat() then
                    break
                end
                
                local now = os.time()
                if now - lastCleanup >= 5 then
                    for i = #PendingItems, 1, -1 do
                        local item = PendingItems[i]
                        if not item or not item.Parent then
                            table.remove(PendingItems, i)
                        elseif item:IsA("ProximityPrompt") then
                            if item.ObjectText and item.ObjectText ~= "" then
                                manageItemPickupsTable(item)
                                table.remove(PendingItems, i)
                            end
                        else
                            table.remove(PendingItems, i)
                        end
                    end
                    lastCleanup = now
                end
            end
        end)

        for _, folder in pairs({
            ReplicatedStorage:FindFirstChild("devv") and ReplicatedStorage.devv:FindFirstChild("shared") and ReplicatedStorage.devv.shared:FindFirstChild("Indicies") and ReplicatedStorage.devv.shared.Indicies:FindFirstChild("v3items") and ReplicatedStorage.devv.shared.Indicies.v3items:FindFirstChild("bin") and ReplicatedStorage.devv.shared.Indicies.v3items.bin:FindFirstChild("Holdable"),
            ReplicatedStorage:FindFirstChild("devv") and ReplicatedStorage.devv:FindFirstChild("shared") and ReplicatedStorage.devv.shared:FindFirstChild("Indicies") and ReplicatedStorage.devv.shared.Indicies:FindFirstChild("v3items") and ReplicatedStorage.devv.shared.Indicies.v3items:FindFirstChild("bin") and ReplicatedStorage.devv.shared.Indicies.v3items.bin:FindFirstChild("Droppable"),
            ReplicatedStorage:FindFirstChild("devv") and ReplicatedStorage.devv:FindFirstChild("shared") and ReplicatedStorage.devv.shared:FindFirstChild("Indicies") and ReplicatedStorage.devv.shared.Indicies:FindFirstChild("v3items") and ReplicatedStorage.devv.shared.Indicies.v3items:FindFirstChild("bin") and ReplicatedStorage.devv.shared.Indicies.v3items.bin:FindFirstChild("Melee"),
        }) do
            if folder then
                for _, child in pairs(folder:GetChildren()) do
                    if child and child:IsA("ModuleScript") then
                        local success, module = pcall(require, child)
                        if success and module then
                            if module.permanent and module.name then
                                PermanentSet[module.name] = true
                            end
                        end
                    end
                end
            end
        end

        local pickupTask
        pickupTask = task.spawn(function()
            local lastScan = os.time()
            while task.wait(0.01) do
                if not updateHeartbeat() then
                    break
                end
                
                if HumanoidRootPart and Humanoid and Humanoid.Health > 0 then
                    local now = os.time()
                    if now - lastScan >= 0.5 then
                        local foundValidPermanent = false
                        local validPickups = {}
                        local itemCount = 0

                        for i, v in pairs(ItemPickups) do
                            if isValidPickup(v) then
                                itemCount = itemCount + 1
                                local objectText
                                if v:IsA("ProximityPrompt") then
                                    objectText = v.ObjectText
                                elseif v:IsA("ClickDetector") then
                                    local parent = v.Parent
                                    if parent and parent:FindFirstChild("ItemName") then
                                        objectText = parent.ItemName.Value
                                    end
                                end
                                if objectText and PermanentSet[objectText] then
                                    if objectText ~= "Candy Cane" then
                                        foundValidPermanent = true
                                        table.insert(validPickups, v)
                                    end
                                end
                            end
                        end

                        if progressTracker.lastItemCount ~= itemCount then
                            updateProgress()
                            progressTracker.lastItemCount = itemCount
                        end

                        for _, pickup in pairs(validPickups) do
                            if pickup and pickup.Parent and HumanoidRootPart and Humanoid then
                                local success, err = pcall(function()
                                    if pickup:IsA("ProximityPrompt") then
                                        HumanoidRootPart.CFrame = pickup.Parent.CFrame
                                        fireproximityprompt(pickup)
                                    elseif pickup:IsA("ClickDetector") then
                                        HumanoidRootPart.CFrame = pickup.Parent.CFrame
                                        fireclickdetector(pickup)
                                    end
                                    Humanoid:MoveTo(HumanoidRootPart.Position + Vector3.new(15, 0, 0))
                                    updateProgress()
                                end)
                                if not success then
                                    warn("Item pickup error: " .. tostring(err))
                                end
                                task.wait(0.01)
                            end
                        end

                        if not foundValidPermanent then
                            itemdone = true
                        end
                        lastScan = now
                    end
                end
            end
        end)

        local otimer = os.time()
        local teleportAttempts = 0

        while task.wait(0.1) do
            if not updateHeartbeat() then
                break
            end
            
            local timer = os.time()

            if os.time() - lastServerRefresh > 20 then
                servers = getServers()
                if servers and servers.data then
                    Serverlist = {}
                    for _, server in ipairs(servers.data) do
                        if server.id ~= game.JobId and server.playing < server.maxPlayers then
                            table.insert(Serverlist, server.id)
                        end
                    end
                    lastServerRefresh = os.time()
                    updateProgress()
                end
            end

            if timer - startTime >= absoluteTimeout then
                warn("Reached absolute timeout, forcing server switch")
                itemdone = true
            end

            if (itemdone or (timer - otimer) >= getgenv().maxwaittime) then
                if #Serverlist > 0 then
                    local targetServer = Serverlist[math.random(1, #Serverlist)]
                    local success = pcall(function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer)
                    end)
                    if success then
                        break
                    else
                        teleportAttempts = teleportAttempts + 1
                        warn("Server switch failed, attempts: " .. teleportAttempts)
                        itemdone = false
                        otimer = os.time()
                        servers = getServers()
                        Serverlist = {}
                        if servers and servers.data then
                            for _, server in ipairs(servers.data) do
                                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                                    table.insert(Serverlist, server.id)
                                end
                            end
                        end
                        if teleportAttempts >= 3 then
                            warn("Multiple server switch failures, trying to teleport directly to game")
                            TeleportService:Teleport(game.PlaceId)
                            break
                        end
                    end
                else
                    warn("No available servers, trying direct teleport")
                    TeleportService:Teleport(game.PlaceId)
                    break
                end
            end
        end
    end)

    if not success then
        cleanup()
        return false
    end

    return true
end

local guardianTask = task.spawn(function()
    local guardianRetryDelay = 10
    local lastRetryTime = os.time()
    
    while true do
        task.wait(5)
        
        if scriptActive then
            lastRetryTime = os.time()
        else
            local now = os.time()
            if now - lastRetryTime >= guardianRetryDelay then
                if initializeScript() then
                    lastRetryTime = now
                else
                    lastRetryTime = now - (guardianRetryDelay / 2)
                end
            end
        end
    end
end)
