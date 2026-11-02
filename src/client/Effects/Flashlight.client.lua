local Players = game:GetService("Players")
local player = Players.LocalPlayer

local enabled = false
local light

local function createLight(character)
    local head = character:WaitForChild("Head")
    light = head:FindFirstChild("NocturnaFlashlight")
    if not light then
        light = Instance.new("SpotLight")
        light.Name = "NocturnaFlashlight"
        light.Angle = 65
        light.Range = 32
        light.Brightness = 2
        light.Shadows = true
        light.Enabled = false
        light.Parent = head
    end
    enabled = player:GetAttribute("FlashlightEnabled") == true
    light.Enabled = enabled
end

if player.Character then createLight(player.Character) end
player.CharacterAdded:Connect(createLight)

player:GetAttributeChangedSignal("FlashlightEnabled"):Connect(function()
    enabled = player:GetAttribute("FlashlightEnabled") == true
    if light then light.Enabled = enabled end
end)
