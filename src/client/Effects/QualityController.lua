-- Ajuste automático para equipos modestos. Celulares y gráficos bajos empiezan en
-- bajo consumo; el jugador puede cambiarlo desde Ajustes.
--
-- En bajo consumo (todo local, no cambia nada para el resto del grupo):
--  * de todas las luces del mapa (techo, objetos, máquinas, pruebas, Alma y las
--    linternas de los demás) sólo quedan prendidas las más cercanas; la linterna
--    y la vista nocturna propias no se tocan;
--  * se apagan las lucecitas de utilería (tanques, pantallas);
--  * sin sombras globales ni sombras de las linternas;
--  * menos resplandor.
-- Siempre: las linternas de los demás no calculan sombras en esta pantalla (sólo
-- la propia, en calidad normal) y en pantallas táctiles no hay profundidad de campo.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

local player = Players.LocalPlayer

-- Cada luz dinámica es la carga más pesada para la placa de video de un celular.
local MAX_NEAR_LIGHTS = 8
local CULL_INTERVAL = 1
local LOW_BLOOM = {Intensity = 0.25, Size = 12}
local FLASHLIGHT_NAMES = {NocturnaFlashlight = true, NocturnaFlashlightSpill = true}

local QualityController = {}
local lowQuality = false
local bloomNormal = {}
-- Todas las luces del mapa, al día por señales (sin recorrer el workspace cada vez).
local lights = {}
-- Las que apagó este cliente para ahorrar: sólo éstas se vuelven a prender.
local culled = {}

local function track(instance)
    if instance:IsA("Light") then
        lights[instance] = true
    end
end

local function untrack(instance)
    lights[instance] = nil
    culled[instance] = nil
end

local function isDark(fixture)
    return fixture:GetAttribute("Dark") == true
end

local function ownerOf(light)
    for _, other in ipairs(Players:GetPlayers()) do
        if other.Character and light:IsDescendantOf(other.Character) then
            return other
        end
    end
    return nil
end

-- Lo que quiere el servidor para esa luz: una lámpara que dejó a oscuras o la
-- linterna apagada de otro jugador no se prenden desde acá.
local function serverAllows(light)
    local parent = light.Parent
    if not parent or isDark(parent) then
        return false
    end
    if FLASHLIGHT_NAMES[light.Name] then
        local owner = ownerOf(light)
        return owner ~= nil and owner:GetAttribute("FlashlightEnabled") == true
            and (owner:GetAttribute("FlashlightBattery") or 0) > 0
    end
    return true
end

local function positionOf(light)
    local parent = light.Parent
    if parent and parent:IsA("Attachment") then
        parent = parent.Parent
    end
    if parent and parent:IsA("BasePart") then
        return parent.Position
    end
    return nil
end

local function isDecor(light)
    local parent = light.Parent
    return parent ~= nil and CollectionService:HasTag(parent, "NocturnaDecorLight")
end

local function setCulled(light)
    if light.Enabled then
        light.Enabled = false
    end
    culled[light] = true
end

local function cullLights()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local origin = camera.CFrame.Position
    local character = player.Character
    local entries = {}
    for light in pairs(lights) do
        local position = positionOf(light)
        local own = character ~= nil and light:IsDescendantOf(character)
        if position and not own and (light.Enabled or culled[light]) then
            if isDecor(light) then
                setCulled(light)
            elseif serverAllows(light) then
                table.insert(entries, {Light = light, Distance = (position - origin).Magnitude})
            end
        end
    end

    table.sort(entries, function(a, b)
        return a.Distance < b.Distance
    end)

    for index, entry in ipairs(entries) do
        local light = entry.Light
        if index <= MAX_NEAR_LIGHTS then
            if not light.Enabled then
                light.Enabled = true
            end
            culled[light] = nil
        else
            setCulled(light)
        end
    end
end

-- Al volver a calidad normal se prenden las que apagó este cliente, salvo las que
-- el servidor quiere apagadas.
local function restoreLights()
    for light in pairs(culled) do
        if light.Parent and serverAllows(light) then
            light.Enabled = true
        end
    end
    table.clear(culled)
end

-- Sombras del haz: sólo la linterna propia y sólo en calidad normal. Las de los
-- demás nunca, en esta pantalla (es una propiedad local).
local function setFlashlightShadows(low)
    for _, other in ipairs(Players:GetPlayers()) do
        local head = other.Character and other.Character:FindFirstChild("Head")
        local attachment = head and head:FindFirstChild("NocturnaFlashlightAttachment")
        local beam = attachment and attachment:FindFirstChild("NocturnaFlashlight")
        local wanted = other == player and not low
        if beam and beam.Shadows ~= wanted then
            beam.Shadows = wanted
        end
    end
end

local function applyPostEffects(low)
    local depth = Lighting:FindFirstChild("NocturnaDepth")
    if depth and depth:IsA("DepthOfFieldEffect") then
        depth.Enabled = not low and not UserInputService.TouchEnabled
    end
    local bloom = Lighting:FindFirstChild("NocturnaBloom")
    if not (bloom and bloom:IsA("BloomEffect")) then
        return
    end
    -- Si el servidor cambió el valor (otro capítulo), ése pasa a ser el normal.
    for property, lowValue in pairs(LOW_BLOOM) do
        if low then
            if bloom[property] ~= lowValue then
                bloomNormal[property] = bloom[property]
                bloom[property] = lowValue
            end
        elseif bloomNormal[property] ~= nil and bloom[property] == lowValue then
            bloom[property] = bloomNormal[property]
            bloomNormal[property] = nil
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

function QualityController.IsLow()
    return lowQuality
end

function QualityController.Start()
    local automatic = autoLowQuality()

    for _, descendant in ipairs(workspace:GetDescendants()) do
        track(descendant)
    end
    workspace.DescendantAdded:Connect(track)
    workspace.DescendantRemoving:Connect(untrack)

    SettingsUI.OnChanged(function(settings)
        local low = settings.LowQuality or automatic
        Lighting.GlobalShadows = not low
        if lowQuality and not low then
            restoreLights()
        end
        lowQuality = low
        applyPostEffects(low)
        setFlashlightShadows(low)
    end)

    task.spawn(function()
        while true do
            task.wait(CULL_INTERVAL)
            -- El servidor recrea efectos y luces al cambiar de capítulo: se reaplica.
            applyPostEffects(lowQuality)
            setFlashlightShadows(lowQuality)
            if lowQuality then
                cullLights()
            end
        end
    end)
end

return QualityController
