-- Ajuste automático para equipos modestos. Celulares y gráficos bajos empiezan en
-- bajo consumo; el jugador puede cambiarlo desde Ajustes.
--
-- En bajo consumo (todo local, no cambia nada para el resto del grupo):
--  * sólo quedan prendidas las luces de techo más cercanas;
--  * se apagan las lucecitas de utilería (tanques, pantallas);
--  * sin sombras globales ni sombras de las linternas;
--  * sin profundidad de campo y con menos resplandor.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

-- Cada luz dinámica es la carga más pesada para la placa de video de un celular.
local MAX_NEAR_LIGHTS = 8
local CULL_INTERVAL = 0.5
local LOW_BLOOM = 0.25

local QualityController = {}
local lowQuality = false
local bloomNormal = nil

local function isDark(fixture)
    return fixture:GetAttribute("Dark") == true
end

local function cullLights()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local origin = camera.CFrame.Position
    local entries = {}
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        local light = fixture:FindFirstChildOfClass("PointLight")
        if light and not isDark(fixture) then
            table.insert(entries, {Light = light, Distance = (fixture.Position - origin).Magnitude})
        end
    end

    table.sort(entries, function(a, b)
        return a.Distance < b.Distance
    end)

    for index, entry in ipairs(entries) do
        local wanted = index <= MAX_NEAR_LIGHTS
        if entry.Light.Enabled ~= wanted then
            entry.Light.Enabled = wanted
        end
    end
end

local function setDecorLights(enabled)
    for _, host in ipairs(CollectionService:GetTagged("NocturnaDecorLight")) do
        local light = host:FindFirstChildOfClass("PointLight")
        if light and light.Enabled ~= enabled then
            light.Enabled = enabled
        end
    end
end

-- Las linternas de todos: con sombras en calidad normal, sin sombras en bajo consumo.
local function setFlashlightShadows(enabled)
    for _, other in ipairs(Players:GetPlayers()) do
        local head = other.Character and other.Character:FindFirstChild("Head")
        local attachment = head and head:FindFirstChild("NocturnaFlashlightAttachment")
        local beam = attachment and attachment:FindFirstChild("NocturnaFlashlight")
        if beam and beam.Shadows ~= enabled then
            beam.Shadows = enabled
        end
    end
end

local function applyPostEffects(low)
    local depth = Lighting:FindFirstChild("NocturnaDepth")
    if depth and depth:IsA("DepthOfFieldEffect") then
        depth.Enabled = not low
    end
    local bloom = Lighting:FindFirstChild("NocturnaBloom")
    if not (bloom and bloom:IsA("BloomEffect")) then
        return
    end
    -- Si el servidor cambió el valor (otro capítulo), ése pasa a ser el normal.
    if low then
        if bloom.Intensity ~= LOW_BLOOM then
            bloomNormal = bloom.Intensity
            bloom.Intensity = LOW_BLOOM
        end
    elseif bloomNormal and bloom.Intensity == LOW_BLOOM then
        bloom.Intensity = bloomNormal
        bloomNormal = nil
    end
end

-- Al volver a calidad normal se prenden todas las que el servidor no apagó.
local function restoreLights()
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        local light = fixture:FindFirstChildOfClass("PointLight")
        if light and not isDark(fixture) then
            light.Enabled = true
        end
    end
    setDecorLights(true)
end

local function autoLowQuality()
    if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
        return true
    end

    local success, level = pcall(function()
        return UserSettings().GameSettings.SavedQualityLevel.Value
    end)
    return success and level > 0 and level <= 3
end

function QualityController.IsLow()
    return lowQuality
end

function QualityController.Start()
    local automatic = autoLowQuality()

    SettingsUI.OnChanged(function(settings)
        local low = settings.LowQuality or automatic
        Lighting.GlobalShadows = not low
        if lowQuality and not low then
            restoreLights()
        end
        lowQuality = low
        applyPostEffects(low)
        setFlashlightShadows(not low)
    end)

    task.spawn(function()
        while true do
            task.wait(CULL_INTERVAL)
            -- El servidor recrea efectos y luces al cambiar de capítulo: se reaplica.
            applyPostEffects(lowQuality)
            setFlashlightShadows(not lowQuality)
            if lowQuality then
                cullLights()
                setDecorLights(false)
            end
        end
    end)
end

return QualityController
