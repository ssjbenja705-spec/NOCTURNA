-- Ajuste automático para equipos modestos. Celulares y gráficos bajos empiezan en
-- bajo consumo; el jugador puede cambiarlo desde Ajustes.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

-- En bajo consumo sólo quedan prendidas las luces de techo más cercanas: cada
-- luz dinámica es la carga más pesada para la placa de video de un celular.
local MAX_NEAR_LIGHTS = 8
local CULL_INTERVAL = 0.5

local QualityController = {}
local lowQuality = false

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

-- Al volver a calidad normal se prenden todas las que el servidor no apagó.
local function restoreLights()
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        local light = fixture:FindFirstChildOfClass("PointLight")
        if light and not isDark(fixture) then
            light.Enabled = true
        end
    end
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

function QualityController.Start()
    local automatic = autoLowQuality()

    SettingsUI.OnChanged(function(settings)
        local low = settings.LowQuality or automatic
        Lighting.GlobalShadows = not low
        if lowQuality and not low then
            restoreLights()
        end
        lowQuality = low
    end)

    task.spawn(function()
        while true do
            task.wait(CULL_INTERVAL)
            if lowQuality then
                cullLights()
            end
        end
    end)
end

return QualityController
