-- Ajuste automático para equipos modestos. Celulares y gráficos bajos empiezan en
-- bajo consumo; el jugador puede cambiarlo desde Ajustes.
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

local QualityController = {}

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
    end)
end

return QualityController
