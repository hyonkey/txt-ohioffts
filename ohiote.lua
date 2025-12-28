if not game:IsLoaded() then
    game.Loaded:Wait()
end

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

LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    HumanoidRootPart = char:WaitForChild("HumanoidRootPart")
    Humanoid = char:WaitForChild("Humanoid")
end)

LocalPlayer.OnTeleport:Connect(function(state)
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
        loadstring(game:HttpGet('https://raw.githubusercontent.com/hyonkey/txt-ohioffts/refs/heads/main/ohiote.lua'))()
    ]])
end)

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
                return data
            end
        end
        if attempt < 3 then
            task.wait(0.5 * attempt)
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
local Permanent = {}
local PendingItems = {}
local lastServerRefresh = os.time()
local absoluteTimeout = 450

local tableLock = false
local function safeTableInsert(tbl, item)
    while tableLock do
        task.wait(0.001)
    end
    tableLock = true
    local success, err = pcall(function()
        table.insert(tbl, item)
    end)
    tableLock = false
    if not success then
        warn("表格插入失败: " .. tostring(err))
    end
end

local function safeTableRemove(tbl, index)
    while tableLock do
        task.wait(0.001)
    end
    tableLock = true
    local success, err = pcall(function()
        table.remove(tbl, index)
    end)
    tableLock = false
    if not success then
        warn("表格移除失败: " .. tostring(err))
    end
end

local function manageItemPickupsTable(newItem)
    safeTableInsert(ItemPickups, newItem)
    if #ItemPickups > 6000 then
        safeTableRemove(ItemPickups, 1)
    end
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
                        des.MaxActivationDistance = 0
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
                itemPickupFolder.DescendantAdded:Connect(function(des)
                    if des:IsA("ProximityPrompt") then
                        des.MaxActivationDistance = 0
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
                end)
            end
        end
    end
end

setupItemPickupListener()

task.spawn(function()
    while task.wait(0.5) do
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
                        table.insert(Permanent, module.name)
                    end
                end
            end
        end
    end
end

task.spawn(function()
    while task.wait(0.01) do
        if HumanoidRootPart and Humanoid and Humanoid.Health > 0 then
            local foundValidPermanent = false
            local validPickups = {}
            for i, v in pairs(ItemPickups) do
                if v and v.Parent then
                    local objectText
                    if v:IsA("ProximityPrompt") then
                        objectText = v.ObjectText
                    elseif v:IsA("ClickDetector") then
                        local parent = v.Parent
                        if parent and parent:FindFirstChild("ItemName") then
                            objectText = parent.ItemName.Value
                        end
                    end
                    if objectText and table.find(Permanent, objectText) then
                        if objectText ~= "Candy Cane" then
                            foundValidPermanent = true
                            table.insert(validPickups, v)
                        end
                    end
                end
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
                        Humanoid:MoveTo(HumanoidRootPart.Position + Vector3.new(15, 0, 15))
                    end)
                    if not success then
                        warn("拾取物品错误: " .. tostring(err))
                    end
                    task.wait(0.01)
                end
            end
            
            if not foundValidPermanent then
                itemdone = true
            end
        end
    end
end)

local otimer = os.time()
local timer = otimer
local teleportAttempts = 0

while task.wait(0.1) do
    timer = os.time()
    
    if os.time() - lastServerRefresh > 60 then
        servers = getServers()
        if servers and servers.data then
            Serverlist = {}
            for _, server in ipairs(servers.data) do
                if server.id ~= game.JobId and server.playing < server.maxPlayers then
                    table.insert(Serverlist, server.id)
                end
            end
            lastServerRefresh = os.time()
        end
    end
    
    if timer - otimer >= absoluteTimeout then
        warn("达到绝对超时，强制跳服")
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
                warn("跳服失败，尝试次数：" .. teleportAttempts)
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
                    warn("多次跳服失败，尝试直接跳转到游戏")
                    TeleportService:Teleport(game.PlaceId)
                    break
                end
            end
        else
            warn("无可用服务器，尝试直接跳转")
            TeleportService:Teleport(game.PlaceId)
            break
        end
    end
end
