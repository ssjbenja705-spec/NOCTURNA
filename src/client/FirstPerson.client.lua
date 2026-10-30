-- NOCTURNA: primera persona y movimiento inicial.
-- Roblox gestiona el control táctil estándar; este script no reemplaza el joystick.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local sprinting = false

local function applyCharacter(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then return end

    player.CameraMode = Enum.CameraMode.LockFirstPerson
    player.CameraMinZoomDistance = 0.5
    player.CameraMaxZoomDistance = 0.5

    local camera = workspace.CurrentCamera
    if camera then
        camera.FieldOfView = Config.Camera.FieldOfView
    end

    humanoid.WalkSpeed = Config.Movement.WalkSpeed
end

local function setSprinting(enabled)
    sprinting = enabled
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = enabled and Config.Movement.SprintSpeed or Config.Movement.WalkSpeed
    end
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        setSprinting(true)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
        setSprinting(false)
    end
end)

player.CharacterAdded:Connect(applyCharacter)
if player.Character then
    task.spawn(applyCharacter, player.Character)
end
