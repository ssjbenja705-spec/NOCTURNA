local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
if not UserInputService.TouchEnabled then return end

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("NocturnaHUD")
local button = Instance.new("TextButton")
button.Name = "FlashlightButton"
button.Size = UDim2.fromOffset(64, 64)
button.Position = UDim2.new(1, -90, 1, -190)
button.BackgroundColor3 = Color3.fromRGB(35, 40, 45)
button.TextColor3 = Color3.fromRGB(230, 230, 230)
button.Text = "LUZ"
button.TextScaled = true
button.Parent = gui

button.Activated:Connect(function()
    local current = player:GetAttribute("ToggleFlashlight") or 0
    player:SetAttribute("ToggleFlashlight", current + 1)
end)