-- NOCTURNA: Sprint Controls

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NocturnaRemotes")
    :WaitForChild("SprintRequest")

local sprinting = false

local function setSprinting(value)
    if sprinting == value then return end

    sprinting = value
    remote:FireServer(value)
end

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.LeftShift then
        setSprinting(true)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.LeftShift then
        setSprinting(false)
    end
end)

UserInputService.WindowFocusReleased:Connect(function()
    setSprinting(false)
end)

player.CharacterAdded:Connect(function()
    sprinting = false
    remote:FireServer(false)
end)

print("[NOCTURNA] Controles de resistencia preparados.")
