local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local event = remotes:WaitForChild("TeamObjectiveUpdate")

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaObjectives"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Size = UDim2.fromOffset(380, 65)
label.Position = UDim2.new(0, 20, 0, 20)
label.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
label.BackgroundTransparency = 0.2
label.TextColor3 = Color3.fromRGB(230, 230, 230)
label.TextSize = 16
label.Font = Enum.Font.GothamMedium
label.TextWrapped = true
label.Parent = gui

event.OnClientEvent:Connect(function(number, objective)
    label.Text = "OBJETIVO " .. tostring(number) .. "\n" .. tostring(objective)
end)
