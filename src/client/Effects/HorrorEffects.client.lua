local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local event = remotes:WaitForChild("HorrorEvent")

local effect = Lighting:FindFirstChild("NocturnaBlur")

if not effect then
    effect = Instance.new("BlurEffect")
    effect.Name = "NocturnaBlur"
    effect.Size = 0
    effect.Parent = Lighting
end

event.OnClientEvent:Connect(function(eventName)
    if eventName == "LIGHTS_FLICKER" then
        local original = Lighting.Brightness

        for _ = 1, 5 do
            Lighting.Brightness = 0
            task.wait(0.08)
            Lighting.Brightness = original
            task.wait(0.1)
        end

    elseif eventName == "DISTANT_SOUND" then
        effect.Size = 8
        task.wait(1.5)
        effect.Size = 0

    elseif eventName == "FALSE_ALARM" then
        effect.Size = 12
        task.wait(0.8)
        effect.Size = 0

    elseif eventName == "ENVIRONMENT_WARNING" then
        effect.Size = 5
        task.wait(2)
        effect.Size = 0
    end
end)
