local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("NocturnaHUD")

local objective = Instance.new("TextLabel")
objective.Name = "ObjectiveLabel"
objective.Size = UDim2.fromScale(0.42, 0.08)
objective.Position = UDim2.fromScale(0.04, 0.78)
objective.BackgroundTransparency = 0.35
objective.BackgroundColor3 = Color3.fromRGB(10, 12, 15)
objective.TextColor3 = Color3.fromRGB(220, 225, 225)
objective.TextWrapped = true
objective.TextScaled = true
objective.Font = Enum.Font.Gotham
objective.Text = "Buscando objetivo..."
objective.Parent = gui

remotes:WaitForChild("ObjectiveUpdate").OnClientEvent:Connect(function(data)
    if type(data) ~= "table" then return end
    local objectives = data.Objectives or {}
    local current = data.Current or 1
    local text = data.Chapter or "NOCTURNA"
    if objectives[current] then
        text ..= "\n" .. objectives[current]
    else
        text ..= "\nCapitulo completado"
    end
    objective.Text = text
end)

remotes:WaitForChild("AdminMessage").OnClientEvent:Connect(function(message)
    objective.Text = tostring(message)
end)