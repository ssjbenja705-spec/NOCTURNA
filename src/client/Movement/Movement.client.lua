local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local stamina = Config.Player.MaxStamina
local sprinting = false
local humanoid

local function setupCharacter(character)
    humanoid = character:WaitForChild("Humanoid")
    humanoid.WalkSpeed = Config.Player.WalkSpeed
end

if player.Character then setupCharacter(player.Character) end
player.CharacterAdded:Connect(setupCharacter)

local function setSprint(value)
    sprinting = value and stamina > 1
    if humanoid then
        humanoid.WalkSpeed = sprinting and Config.Player.SprintSpeed or Config.Player.WalkSpeed
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.LeftShift then setSprint(true) end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then setSprint(false) end
end)

RunService.Heartbeat:Connect(function(dt)
    if sprinting and humanoid and humanoid.MoveDirection.Magnitude > 0 then
        stamina = math.max(0, stamina - Config.Player.StaminaDrain * dt)
        if stamina <= 0 then setSprint(false) end
    else
        stamina = math.min(Config.Player.MaxStamina, stamina + Config.Player.StaminaRecovery * dt)
    end
end)

player:SetAttribute("Stamina", stamina)
RunService.Heartbeat:Connect(function()
    player:SetAttribute("Stamina", stamina)
end)
