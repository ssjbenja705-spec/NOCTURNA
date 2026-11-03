-- Linterna local con batería, para PC y dispositivos táctiles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameSettings"))
local settings = Config.Flashlight
local battery = 100
local light
local button
local enabled = settings.Enabled == true

player:SetAttribute("FlashlightEnabled", false)
player:SetAttribute("FlashlightBattery", battery)

local function updateButton()
    if button then
        button.Text = "LUZ\n" .. tostring(math.ceil(battery)) .. "%"
        button.BackgroundColor3 = enabled and Color3.fromRGB(75, 85, 95) or Color3.fromRGB(20, 24, 30)
    end
end

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
        light.Brightness = settings.Brightness
        light.Range = settings.Range
        light.Angle = settings.Angle
        light.Shadows = true
        light.Parent = attachment
    end
    light.Enabled = enabled and battery > 0
end

local function toggle()
    if battery <= 0 then
        enabled = false
    else
        enabled = not enabled
    end
    player:SetAttribute("FlashlightEnabled", enabled)
    if light then light.Enabled = enabled end
    updateButton()
end

UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == (settings.ToggleKey or Enum.KeyCode.F) then
        toggle()
    end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaFlashlightControls"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

button = Instance.new("TextButton")
button.Name = "FlashlightButton"
button.Size = UDim2.fromOffset(68, 64)
button.Position = UDim2.new(1, -90, 1, -190)
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

RunService.Heartbeat:Connect(function(deltaTime)
    if enabled then
        battery = math.max(0, battery - deltaTime * 0.35)
        if battery <= 0 then
            enabled = false
            player:SetAttribute("FlashlightEnabled", false)
            if light then light.Enabled = false end
        end
        player:SetAttribute("FlashlightBattery", math.floor(battery))
        updateButton()
    end
end)

player.CharacterAdded:Connect(function()
    light = nil
    task.wait(0.25)
    findOrCreateLight()
end)
if player.Character then findOrCreateLight() end
updateButton()
