local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("NocturnaHUD")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = playerGui

local objective = Instance.new("TextLabel")
objective.Name = "Objective"
objective.AnchorPoint = Vector2.new(0.5, 0)
objective.Position = UDim2.fromScale(0.5, 0.035)
objective.Size = UDim2.new(0.7, 0, 0, 42)
objective.BackgroundColor3 = Color3.fromRGB(5, 7, 10)
objective.BackgroundTransparency = 0.3
objective.BorderSizePixel = 0
objective.Text = "NOCTURNA  •  Encuentra una salida"
objective.TextColor3 = Color3.fromRGB(220, 225, 225)
objective.TextScaled = true
objective.Font = Enum.Font.GothamMedium
objective.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = objective

local chapter = Instance.new("TextLabel")
chapter.Name = "ChapterLabel"
chapter.AnchorPoint = Vector2.new(0, 1)
chapter.Position = UDim2.new(0.025, 0, 0.965, 0)
chapter.Size = UDim2.new(0.42, 0, 0, 30)
chapter.BackgroundTransparency = 1
chapter.Text = "CAPÍTULO 1"
chapter.TextColor3 = Color3.fromRGB(190, 195, 200)
chapter.TextXAlignment = Enum.TextXAlignment.Left
chapter.TextScaled = true
chapter.Font = Enum.Font.Gotham
chapter.Parent = gui

player:GetAttributeChangedSignal("LastChapter"):Connect(function()
    chapter.Text = "CAPÍTULO " .. tostring(player:GetAttribute("LastChapter") or 1)
end)
chapter.Text = "CAPÍTULO " .. tostring(player:GetAttribute("LastChapter") or 1)
