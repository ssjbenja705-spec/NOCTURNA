local Players = game:GetService("Players")
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local title = Instance.new("TextLabel")
title.Name = "ChapterLabel"
title.Size = UDim2.fromScale(0.42, 0.06)
title.Position = UDim2.fromScale(0.29, 0.035)
title.BackgroundTransparency = 1
title.Text = "NOCTURNA"
title.TextColor3 = Color3.fromRGB(210, 220, 220)
title.TextScaled = true
title.Font = Enum.Font.GothamMedium
title.Parent = gui

local staminaBack = Instance.new("Frame")
staminaBack.Size = UDim2.fromScale(0.22, 0.018)
staminaBack.Position = UDim2.fromScale(0.04, 0.93)
staminaBack.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
staminaBack.BorderSizePixel = 0
staminaBack.Parent = gui

local staminaFill = Instance.new("Frame")
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = Color3.fromRGB(170, 190, 185)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBack

player:GetAttributeChangedSignal("Stamina"):Connect(function()
    local value = player:GetAttribute("Stamina") or 100
    staminaFill.Size = UDim2.fromScale(math.clamp(value / 100, 0, 1), 1)
end)
