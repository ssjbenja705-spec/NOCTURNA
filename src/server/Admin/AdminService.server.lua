local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("AdminConfig"))
local messageEvent = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("AdminMessage")
local admins = {}
for _, userId in ipairs(Config.AdminUserIds) do
    if typeof(userId) == "number" and userId > 0 then
        admins[userId] = true
    end
end

local function announce(message)
    messageEvent:FireAllClients(tostring(message):sub(1, 180))
end

local function handleCommand(player, message)
    if not admins[player.UserId] or message:sub(1, 1) ~= "!" then return end
    local args = string.split(message:sub(2), " ")
    local command = string.lower(args[1] or "")

    if command == "announce" then
        table.remove(args, 1)
        announce(table.concat(args, " "))
    elseif command == "heal" then
        local target = Players:FindFirstChild(args[2] or player.Name)
        local humanoid = target and target.Character and target.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.Health = humanoid.MaxHealth end
    elseif command == "setchapter" then
        local chapter = tonumber(args[2])
        local setChapter = _G.NocturnaSetChapter
        if chapter and setChapter then
            setChapter(chapter)
        end
    elseif command == "kick" then
        local target = Players:FindFirstChild(args[2] or "")
        if target and target ~= player then
            target:Kick("Expulsado por un administrador.")
        end
    end
end

local function setupPlayer(player)
    player.Chatted:Connect(function(message)
        handleCommand(player, message)
    end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

print("[NOCTURNA] Administracion preparada. Configura los UserId.")