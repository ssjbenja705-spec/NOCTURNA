-- Linterna local inicial: tecla F en PC y botón táctil en móvil.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local enabled = false
local light

local function findOrCreateLight()
    local character = player.Character
    if not character then return end

    local head = character:FindFirstChild("Head")
    if not head then return end

    local attachment = head:FindFirstChild("NocturnaFlashlightAttachment")
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "NocturnaFlashlightAttachment"
        attachment.Parent = head
    end

    light = attachment:FindFirstChild("NocturnaFlashlight")
    if not light then
        light = Instance.new("SpotLight")
        light.Name = "NocturnaFlashlight"
        light.Face = Enum.NormalId.Front
        light.Brightness = Config.Flashlight.Brightness
        light.Range = Config.Flashlight.Range
        light.Angle = Config.Flashlight.Angle
        light.Shadows = true
        light.Enabled = false
        light.Parent = attachment
    end
end

local function toggle()
    if not light then findOrCreateLight() end
    if not light then return end
    enabled = not enabled
    light.Enabled = enabled
end

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaMobileControls"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local button = Instance.new("TextButton")
button.Name = "FlashlightButton"
button.Size = UDim2.fromOffset(64, 64)
button.Position = UDim2.new(1, -88, 1, -190)
button.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
button.BackgroundTransparency = 0.18
button.TextColor3 = Color3.fromRGB(235, 238, 242)
button.Text = "LUZ"
button.TextScaled = true
button.Font = Enum.Font.GothamBold
button.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = button

button.Activated:Connect(toggle)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Config.Flashlight.ToggleKey then
        toggle()
    end
end)

player.CharacterAdded:Connect(function()
    enabled = false
    light = nil
    task.wait(0.25)
    findOrCreateLight()
end)

if player.Character then
    findOrCreateLight()
end
