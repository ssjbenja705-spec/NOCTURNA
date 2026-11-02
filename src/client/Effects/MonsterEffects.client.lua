local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local remote = ReplicatedStorage:WaitForChild("NocturnaRemotes"):WaitForChild("MonsterEffect")
local blur = Lighting:FindFirstChild("MonsterBlur")

if not blur then
    blur = Instance.new("BlurEffect")
    blur.Name = "MonsterBlur"
    blur.Size = 0
    blur.Parent = Lighting
end

remote.OnClientEvent:Connect(function(effectName)
    if effectName == "COLOSSUS_NEAR" then
        blur.Size = 8
        task.wait(1.2)
        blur.Size = 0
    elseif effectName == "IMITATOR_CALL" then
        blur.Size = 4
        task.wait(0.7)
        blur.Size = 0
    end
end)
