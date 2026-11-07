-- Pantalla de carga: es lo primero que ve el jugador. Precarga las fuentes y los
-- sonidos, muestra un consejo y se va sola cuando el cliente terminó de iniciar
-- (o, si la red se traba, a los pocos segundos igual). También se puede saltar.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))

local Colors = Theme.Colors

local MIN_TIME = 2.5
local MAX_TIME = 14
local ASSET_SHARE = 0.65
local FADE_TIME = 0.8
local FAST_FADE_TIME = 0.3

local TIPS = {
    "«Contá hasta cinco conmigo. A los cinco, la oscuridad se va.»",
    "Si algo te llama con la voz de alguien que querés, no contestes.",
    "El Oyente no ve: escucha. Cerca de él, andá agachado y en silencio.",
    "Los casilleros salvan vidas, pero sólo si nadie te ve entrar.",
    "La linterna se gasta. Guardá las baterías para cuando haga falta.",
    "¿Te perdiste? Abrí el MAPA: muestra lo que tu grupo ya recorrió.",
    "Lo que lleva uno sirve para todos: fusibles y llaves se comparten.",
    "Correr hace ruido. Y el ruido atrae.",
    "Leé los documentos: los quince juntos cambian el final.",
}

local LoadingScreen = {}

local gui = nil
local fading = {}
local fill = nil
local status = nil
local skip = nil
local connection = nil

local shown = false
local finished = false
local startedAt = 0
local assetsDone = 0
local assetsTotal = 0
local preloadDone = false
local bootProgress = 0
local displayed = 0
local shownPercent = -1

local function statusText(progress)
    if progress >= 1 then
        return "Listo."
    elseif progress >= 0.66 then
        return "Contando hasta cinco..."
    elseif progress >= 0.3 then
        return "Despertando recuerdos..."
    end
    return "Buscando la señal..."
end

-- Fuentes de la pantalla (vienen con sus textos) y todos los sonidos del juego.
local function collectAssets()
    local list = {gui}
    local shared = ReplicatedStorage:WaitForChild("Shared", 20)
    local config = shared and shared:WaitForChild("Config", 10)
    local module = config and config:WaitForChild("AudioConfig", 10)
    if module then
        local success, audio = pcall(require, module)
        if success and typeof(audio) == "table" then
            local seen = {}
            for _, group in ipairs({audio.Music or {}, audio.Sfx or {}}) do
                for _, definition in pairs(group) do
                    local id = definition.Id
                    if typeof(id) == "string" and not seen[id] then
                        seen[id] = true
                        table.insert(list, id)
                    end
                end
            end
        end
    end
    return list
end

local function preload()
    local list = collectAssets()
    assetsTotal = #list
    local success, err = pcall(function()
        ContentProvider:PreloadAsync(list, function()
            assetsDone = math.min(assetsTotal, assetsDone + 1)
        end)
    end)
    if not success then
        warn("[NOCTURNA] La precarga no terminó: " .. tostring(err))
    end
    assetsDone = assetsTotal
    preloadDone = true
end

local function update(deltaTime)
    if finished then
        return
    end
    local elapsed = os.clock() - startedAt
    local assetProgress = preloadDone and 1 or (assetsTotal > 0 and assetsDone / assetsTotal or 0)
    local target = assetProgress * ASSET_SHARE + bootProgress * (1 - ASSET_SHARE)

    displayed += (target - displayed) * math.min(1, deltaTime * 5)
    if target >= 1 and displayed > 0.985 then
        displayed = 1
    end

    local percent = math.floor(displayed * 100)
    if percent ~= shownPercent then
        shownPercent = percent
        fill.Size = UDim2.fromScale(displayed, 1)
        status.Text = string.format("%s  %d%%", statusText(displayed), percent)
    end

    if (displayed >= 1 and elapsed >= MIN_TIME) or elapsed >= MAX_TIME then
        LoadingScreen.Finish(false)
    end
end

local function build()
    local root
    root, gui = Theme.Screen("NocturnaLoading", 100, true)

    local background = Theme.New("Frame", {
        Name = "Background",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Colors.Black,
        BorderSizePixel = 0,
    }, root)
    table.insert(fading, {background, "BackgroundTransparency"})

    local glow = Theme.New("Frame", {
        Name = "Glow",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.fromScale(0.9, 0.5),
        BackgroundColor3 = Colors.Blood,
        BackgroundTransparency = 0.86,
        BorderSizePixel = 0,
    }, background)
    Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, glow)
    Theme.New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, glow)
    table.insert(fading, {glow, "BackgroundTransparency"})

    local title = Theme.Title(background, {
        Name = "Title",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.34),
        Size = UDim2.new(0.9, 0, 0, 110),
        Text = "NOCTURNA",
        TextSize = 96,
        TextStrokeColor3 = Colors.Black,
        TextStrokeTransparency = 0.3,
    })
    table.insert(fading, {title, "TextTransparency"})
    table.insert(fading, {title, "TextStrokeTransparency"})

    local subtitle = Theme.Label(background, {
        Name = "Subtitle",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.46),
        Size = UDim2.new(0.8, 0, 0, 26),
        Text = "EL ÚLTIMO RECUERDO",
        TextSize = 20,
        TextColor3 = Colors.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    table.insert(fading, {subtitle, "TextTransparency"})

    local rule = Theme.Rule(background, UDim2.new(0.34, 0, 0.46, 32), UDim2.new(0.32, 0, 0, 6))
    for _, line in ipairs(rule:GetChildren()) do
        table.insert(fading, {line, "BackgroundTransparency"})
    end

    local tip = Theme.Label(background, {
        Name = "Tip",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.58),
        Size = UDim2.new(0.7, 0, 0, 56),
        Text = TIPS[Random.new():NextInteger(1, #TIPS)],
        TextSize = 17,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    table.insert(fading, {tip, "TextTransparency"})

    local track = Theme.New("Frame", {
        Name = "Progress",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.76),
        Size = UDim2.new(0.46, 0, 0, 6),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, background)
    Theme.Stroke(track, Colors.Stroke, 1, 0.2)
    table.insert(fading, {track, "BackgroundTransparency"})

    fill = Theme.New("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Colors.Danger,
        BorderSizePixel = 0,
    }, track)
    table.insert(fading, {fill, "BackgroundTransparency"})

    status = Theme.Label(background, {
        Name = "Status",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0.76, 12),
        Size = UDim2.new(0.46, 0, 0, 20),
        TextSize = 14,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = statusText(0),
    })
    table.insert(fading, {status, "TextTransparency"})

    skip = Theme.Button(background, "SALTAR", {
        Name = "Skip",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -28, 1, -24),
        Size = UDim2.fromOffset(150, Theme.IsTouch and 52 or 46),
        TextSize = 17,
        BackgroundColor3 = Colors.Panel,
    })
    skip.Activated:Connect(function()
        LoadingScreen.Finish(true)
    end)

    Theme.Grain(background, 18, function()
        return not finished
    end)
end

function LoadingScreen.Show()
    if shown then
        return
    end
    shown = true
    startedAt = os.clock()
    build()
    Theme.SetModal("Loading", true)
    connection = RunService.Heartbeat:Connect(update)
    task.spawn(preload)
end

function LoadingScreen.Start()
    LoadingScreen.Show()
end

-- Main.client avisa cuánto del cliente ya arrancó (0 a 1).
function LoadingScreen.SetBootProgress(fraction)
    bootProgress = math.clamp(fraction, bootProgress, 1)
end

function LoadingScreen.MarkReady()
    bootProgress = 1
end

function LoadingScreen.IsActive()
    return shown and not finished
end

function LoadingScreen.Finish(fast)
    if finished or not shown then
        return
    end
    finished = true
    if connection then
        connection:Disconnect()
        connection = nil
    end
    Theme.SetModal("Loading", false)
    skip.Visible = false

    local fade = fast and FAST_FADE_TIME or FADE_TIME
    for _, entry in ipairs(fading) do
        Theme.Tween(entry[1], fade, {[entry[2]] = 1})
    end
    task.delay(fade + 0.05, function()
        gui:Destroy()
    end)
end

return LoadingScreen
