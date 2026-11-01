local Players = game:GetService("Players")
local player = Players.LocalPlayer

player.CameraMode = Enum.CameraMode.LockFirstPerson

local function configure(character)
    local humanoid = character:WaitForChild("Humanoid")
    humanoid.CameraOffset = Vector3.new(0, 0, 0)
end

if player.Character then configure(player.Character) end
player.CharacterAdded:Connect(configure)
