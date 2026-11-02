local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")

local objectiveEvent = remotes:FindFirstChild("TeamObjectiveUpdate")
if not objectiveEvent then
    objectiveEvent = Instance.new("RemoteEvent")
    objectiveEvent.Name = "TeamObjectiveUpdate"
    objectiveEvent.Parent = remotes
end

local objectives = {
    "Encontrar la entrada de la instalación",
    "Restablecer la energía",
    "Encontrar una tarjeta de acceso",
    "Abrir el laboratorio",
    "Encontrar pistas sobre la hermana"
}

local currentObjective = 1

local function broadcast()
    objectiveEvent:FireAllClients(
        currentObjective,
        objectives[currentObjective] or "Capítulo completado"
    )
end

_G.NocturnaNextObjective = function()
    currentObjective += 1
    broadcast()
end

Players.PlayerAdded:Connect(function()
    task.wait(2)
    broadcast()
end)

broadcast()
