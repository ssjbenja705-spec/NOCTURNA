local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("PlayerLook")
local elapsed = 0

RunService.RenderStepped:Connect(function(deltaTime)
    elapsed += deltaTime
    if elapsed < 0.15 then return end
    elapsed = 0

    local camera = workspace.CurrentCamera
    if camera then
        remote:FireServer(camera.CFrame.LookVector)
    end
end)
