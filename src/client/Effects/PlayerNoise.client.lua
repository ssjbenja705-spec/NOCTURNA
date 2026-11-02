local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("PlayerNoise")
local elapsed = 0

RunService.Heartbeat:Connect(function(deltaTime)
    elapsed += deltaTime
    if elapsed < 0.5 then return end
    elapsed = 0

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return end
    if humanoid.MoveDirection.Magnitude < 0.1 then return end

    local intensity = humanoid.WalkSpeed >= 15 and 85 or 35
    remote:FireServer(root.Position, intensity)
end)
