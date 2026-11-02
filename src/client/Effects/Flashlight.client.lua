local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local enabled = false
local light

local function setupCharacter(character)
    local head = character:WaitForChild("Head")

    light = head:FindFirstChild("NocturnaFlashlight")
    if not light then
        light = Instance.new("SpotLight")
        light.Name = "NocturnaFlashlight"
        light.Angle = 65
        light.Range = 32
        light.Brightness = 2
        light.Enabled = false
        light.Parent = head
    end

    light.Enabled = enabled
end

local function setEnabled(value)
    enabled = value == true
    player:SetAttribute("FlashlightEnabled", enabled)

    if light then
        light.Enabled = enabled
    end
end

player:GetAttributeChangedSignal("FlashlightEnabled"):Connect(function()
    enabled = player:GetAttribute("FlashlightEnabled") == true
    if light then
        light.Enabled = enabled
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == Enum.KeyCode.F then
        setEnabled(not enabled)
    end
end)

player.CharacterAdded:Connect(setupCharacter)

if player.Character then
    setupCharacter(player.Character)
end
