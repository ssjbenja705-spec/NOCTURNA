-- Detalles locales de la luz del jugador:
--  * Vista acostumbrada a la oscuridad: una luz muy tenue, sólo visible para uno,
--    deja distinguir formas cerca aunque la linterna esté apagada o sin batería.
--  * Con la batería baja, el haz titila de verdad (sólo en esta pantalla).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ClientState = require(script.Parent.Parent.Core.ClientState)

local player = Players.LocalPlayer

local NIGHT_EYES = {
    Name = "NocturnaNightEyes",
    Color = Color3.fromRGB(150, 162, 186),
    Brightness = 0.28,
    Range = 16,
}
local FLICKER_CHANCE = 0.05

local FlashlightVisuals = {}
local playing = false
local random = Random.new()

local function nightEyes(character)
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return nil
    end
    local light = root:FindFirstChild(NIGHT_EYES.Name)
    if not light then
        light = Instance.new("PointLight")
        light.Name = NIGHT_EYES.Name
        light.Color = NIGHT_EYES.Color
        light.Brightness = NIGHT_EYES.Brightness
        light.Range = NIGHT_EYES.Range
        light.Shadows = false
        light.Parent = root
    end
    return light
end

local function flashlight(character)
    local head = character and character:FindFirstChild("Head")
    local attachment = head and head:FindFirstChild("NocturnaFlashlightAttachment")
    return attachment and attachment:FindFirstChild("NocturnaFlashlight")
end

local baseBrightness = nil

local function update()
    local character = player.Character
    local eyes = nightEyes(character)
    local beamOn = player:GetAttribute("FlashlightEnabled") == true
    if eyes then
        -- Con la linterna prendida no hace falta; escondido tampoco (ya hay exposición).
        eyes.Enabled = playing and not beamOn and player:GetAttribute("Hidden") ~= true
    end

    local beam = flashlight(character)
    if beam then
        baseBrightness = baseBrightness or beam.Brightness
        local battery = player:GetAttribute("FlashlightBattery") or 100
        local low = beamOn and battery <= GameConfig.Flashlight.LowBattery
        if low and random:NextNumber() < FLICKER_CHANCE then
            beam.Brightness = baseBrightness * random:NextNumber(0.15, 0.6)
        else
            beam.Brightness = baseBrightness
        end
    end
end

function FlashlightVisuals.Start()
    ClientState.Subscribe("Game", function(data)
        playing = data.Phase == "Playing"
    end)

    player.CharacterAdded:Connect(function()
        baseBrightness = nil
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= 0.1 then
            elapsed = 0
            update()
        end
    end)
end

return FlashlightVisuals
