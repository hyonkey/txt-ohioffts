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
        loadstring(game:HttpGet('https://raw.githubusercontent.com/hyonkey/txt-ohioffts/refs/heads/main/ohiottaf.lua'))()
    ]])
end)

local function getServers()
    local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
    local success, response = pcall(function()
        return game:HttpGet(url)
    end)
    if success then
        if not response or response == "" then
            return
        end
        local success2, data = pcall(function()
            return HttpService:JSONDecode(response)
        end)
        if success2 then
            return data
        end
    end
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

local function manageItemPickupsTable(newItem)
    table.insert(ItemPickups, newItem)
    if #ItemPickups > 6000 then
        table.remove(ItemPickups, 1)
    end
end

for _, des in ipairs(workspace.Game.Entities.ItemPickup:GetDescendants()) do
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

workspace.Game.Entities.ItemPickup.DescendantAdded:Connect(function(des)
    if des:IsA("ProximityPrompt") then
        des.MaxActivationDistance = 0
        task.spawn(function()
            for attempt = 1, 50 do
                if des and des.Parent and des.ObjectText and des.ObjectText ~= "" then
                    manageItemPickupsTable(des)
                    return
                end
                task.wait(0.01)
            end
            if des and des.Parent then
                table.insert(PendingItems, des)
            end
        end)
    elseif des:IsA("ClickDetector") then
        manageItemPickupsTable(des)
    end
end)

task.spawn(function()
    while task.wait(0.01) do
        for i = #PendingItems, 1, -1 do
            local item = PendingItems[i]
            if not (item and item.Parent) then
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
    ReplicatedStorage.devv.shared.Indicies.v3items.bin.Holdable,
    ReplicatedStorage.devv.shared.Indicies.v3items.bin.Droppable,
    ReplicatedStorage.devv.shared.Indicies.v3items.bin.Melee,
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
    while task.wait(0.02) do
        if HumanoidRootPart and Humanoid then
            local foundValidPermanent = false
            local validPickups = {}
            for i, v in pairs(ItemPickups) do
                if v and v.Parent and v:IsA("ProximityPrompt") then
                    local objectText = v.ObjectText
                    if objectText and table.find(Permanent, objectText) then
                        if objectText ~= "Candy Cane" then
                            foundValidPermanent = true
                            table.insert(validPickups, v)
                        end
                    end
                end
            end
            
            for _, prompt in pairs(validPickups) do
                if prompt and prompt.Parent and HumanoidRootPart and Humanoid then
                    pcall(function()
                        HumanoidRootPart.CFrame = prompt.Parent.CFrame
                        fireproximityprompt(prompt)
                        Humanoid:MoveTo(HumanoidRootPart.Position + Vector3.new(10, 0, 0))
                    end)
                    task.wait(0.02)
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

while task.wait(0.1) do
    timer = os.time()
    if (itemdone or (timer - otimer) >= getgenv().maxwaittime) and #Serverlist > 0 then
        local targetServer = Serverlist[math.random(1, #Serverlist)]
        TeleportService:TeleportToPlaceInstance(game.PlaceId, targetServer)
        break
    end
end
