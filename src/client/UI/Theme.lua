-- Estilo común de la interfaz: negros profundos, paneles gastados, sangre seca y
-- ámbar enfermo, letra de máquina de escribir. También ubica cada pantalla dentro
-- del área segura, para que nada quede debajo de los botones de Roblox.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local Theme = {}

Theme.Colors = {
    Panel = Color3.fromRGB(11, 9, 9),
    PanelLight = Color3.fromRGB(30, 24, 22),
    Button = Color3.fromRGB(33, 25, 23),
    ButtonActive = Color3.fromRGB(118, 26, 22),
    Text = Color3.fromRGB(228, 218, 198),
    TextDim = Color3.fromRGB(162, 150, 132),
    Accent = Color3.fromRGB(208, 154, 66),
    Health = Color3.fromRGB(158, 30, 26),
    Stamina = Color3.fromRGB(140, 160, 120),
    Battery = Color3.fromRGB(208, 154, 66),
    Danger = Color3.fromRGB(206, 46, 36),
    Paper = Color3.fromRGB(214, 200, 168),
    Ink = Color3.fromRGB(38, 28, 22),
    Blood = Color3.fromRGB(122, 20, 18),
    Stroke = Color3.fromRGB(88, 30, 24),
    Grime = Color3.fromRGB(72, 52, 32),
    Track = Color3.fromRGB(19, 15, 14),
    Black = Color3.fromRGB(0, 0, 0),
    Radio = Color3.fromRGB(150, 194, 140),
    Exit = Color3.fromRGB(104, 180, 118),
    Blueprint = Color3.fromRGB(15, 20, 25),
    BlueprintFloor = Color3.fromRGB(46, 62, 68),
    BlueprintLine = Color3.fromRGB(180, 198, 190),
}

-- Creepster sólo para títulos grandes; el resto, máquina de escribir.
Theme.Fonts = {
    Display = Enum.Font.Creepster,
    Title = Enum.Font.SpecialElite,
    Body = Enum.Font.SpecialElite,
    Mono = Enum.Font.RobotoMono,
}

Theme.IsTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Con la escala de un teléfono (~0,72) esto deja el texto más chico en unos 10 pt.
Theme.MinTextSize = Theme.IsTouch and 14 or 12

-- Las pantallas viejas pedían Gotham: se traducen a la tipografía del juego.
local LEGACY_FONTS = {
    Gotham = Theme.Fonts.Body,
    GothamMedium = Theme.Fonts.Body,
    GothamBold = Theme.Fonts.Title,
    GothamBlack = Theme.Fonts.Title,
}

local ACCENTS = {
    ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ", ["ü"] = "Ü",
}

local DESIGN_WIDTH = 1000
local DESIGN_HEIGHT = 520

local random = Random.new()
local lowQuality = false

-- string.upper no conoce las tildes: "Capítulo" quedaba "CAPíTULO".
function Theme.Upper(text)
    local result = string.upper(tostring(text or ""))
    for lower, upper in pairs(ACCENTS) do
        result = string.gsub(result, lower, upper)
    end
    return result
end

-- Escapa un texto para usarlo dentro de RichText.
function Theme.Escape(text)
    local result = string.gsub(tostring(text or ""), "&", "&amp;")
    result = string.gsub(result, "<", "&lt;")
    result = string.gsub(result, ">", "&gt;")
    return result
end

-- Crea una instancia aplicando propiedades.
function Theme.New(className, properties, parent)
    local instance = Instance.new(className)
    for key, value in pairs(properties or {}) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

function Theme.Tween(instance, seconds, goal, style, direction, repeatCount)
    local info = TweenInfo.new(
        seconds,
        style or Enum.EasingStyle.Quad,
        direction or Enum.EasingDirection.Out,
        repeatCount or 0
    )
    local tween = TweenService:Create(instance, info, goal)
    tween:Play()
    return tween
end

-- Escala y área segura ---------------------------------------------------------

local scaleFactor = 1
local safeSize = Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
local fullSize = Vector2.new(DESIGN_WIDTH, DESIGN_HEIGHT)
local screens = {}
local layoutListeners = {}
local watching = false
local cameraConnection = nil

local function computeScale(viewport)
    return math.clamp(math.min(viewport.X / DESIGN_WIDTH, viewport.Y / DESIGN_HEIGHT), 0.62, 1.35)
end

-- Lo que ocupan los botones de Roblox arriba (y abajo, si hubiera algo).
local function guiInsets()
    local success, topLeft, bottomRight = pcall(function()
        return GuiService:GetGuiInset()
    end)
    if success and typeof(topLeft) == "Vector2" and typeof(bottomRight) == "Vector2" then
        return topLeft, bottomRight
    end
    return Vector2.new(0, 0), Vector2.new(0, 0)
end

local function refresh()
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    local viewport = camera.ViewportSize
    if viewport.X < 2 or viewport.Y < 2 then
        return
    end

    scaleFactor = computeScale(viewport)
    local topLeft, bottomRight = guiInsets()
    fullSize = Vector2.new(viewport.X / scaleFactor, viewport.Y / scaleFactor)
    safeSize = Vector2.new(
        math.max(1, viewport.X - topLeft.X - bottomRight.X) / scaleFactor,
        math.max(1, viewport.Y - topLeft.Y - bottomRight.Y) / scaleFactor
    )

    for _, screen in ipairs(screens) do
        screen.Scale.Scale = scaleFactor
        screen.Root.Size = UDim2.fromScale(1 / scaleFactor, 1 / scaleFactor)
    end
    for _, listener in ipairs(layoutListeners) do
        task.spawn(listener, safeSize, fullSize)
    end
end

local function watchCamera()
    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
    local camera = workspace.CurrentCamera
    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
    end
    refresh()
end

local function ensureWatching()
    if watching then
        return
    end
    watching = true
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
    watchCamera()
end

-- Tamaño útil en unidades de diseño: sin la barra de Roblox ni los bordes inseguros.
function Theme.SafeSize()
    ensureWatching()
    return safeSize
end

function Theme.FullSize()
    ensureWatching()
    return fullSize
end

-- Llama de inmediato y cada vez que cambia el tamaño de la pantalla.
function Theme.OnLayout(listener)
    ensureWatching()
    table.insert(layoutListeners, listener)
    listener(safeSize, fullSize)
end

-- Cada pantalla tiene una raíz cuyo tamaño compensa el UIScale, de modo que los
-- anclajes a las esquinas se mantienen en cualquier resolución. Las pantallas
-- comunes viven dentro del área segura: nada queda debajo del logo, el menú, el
-- chat o el micrófono de Roblox ni de los recortes del teléfono. Las capas de
-- pantalla completa (cortinas, párpados, grano) piden fullscreen.
function Theme.Screen(name, displayOrder, fullscreen)
    local gui = Theme.New("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        IgnoreGuiInset = fullscreen == true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = displayOrder or 0,
    })
    if fullscreen then
        gui.ScreenInsets = Enum.ScreenInsets.None
        gui.ClipToDeviceSafeArea = false
    else
        gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    end
    gui.Parent = player:WaitForChild("PlayerGui")

    local root = Theme.New("Frame", {
        Name = "Root",
        BackgroundTransparency = 1,
    }, gui)
    local scale = Theme.New("UIScale", {}, root)

    table.insert(screens, {Root = root, Scale = scale})
    ensureWatching()
    scale.Scale = scaleFactor
    root.Size = UDim2.fromScale(1 / scaleFactor, 1 / scaleFactor)

    return root, gui
end

-- Piezas básicas ------------------------------------------------------------------

function Theme.Corner(parent, radius)
    return Theme.New("UICorner", {CornerRadius = UDim.new(0, radius or 3)}, parent)
end

-- Borde (no contorno de letras: en botones y textos el modo por defecto pinta el texto).
function Theme.Stroke(parent, color, thickness, transparency)
    return Theme.New("UIStroke", {
        Color = color or Theme.Colors.Stroke,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Miter,
    }, parent)
end

local function seedFrom(text)
    local value = 7
    for index = 1, #text do
        value = (value * 31 + string.byte(text, index)) % 2147483647
    end
    return value
end

-- Manchas, pintura saltada y remaches. Con la misma semilla queda siempre igual.
function Theme.Wear(frame, seedText, stains)
    local rng = Random.new(seedFrom(seedText or frame.Name))
    local colors = Theme.Colors

    for index = 1, stains or 2 do
        local width = rng:NextInteger(34, 90)
        local stain = Theme.New("Frame", {
            Name = "Stain",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(rng:NextNumber(0.18, 0.82), rng:NextNumber(0.25, 0.85)),
            Size = UDim2.fromOffset(width, math.floor(width * rng:NextNumber(0.5, 0.85))),
            BackgroundColor3 = index % 2 == 0 and colors.Grime or colors.Blood,
            BackgroundTransparency = rng:NextNumber(0.88, 0.94),
            BorderSizePixel = 0,
            Rotation = rng:NextInteger(-35, 35),
        }, frame)
        Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, stain)
    end

    -- Pintura saltada sobre el borde.
    for index = 1, 3 do
        local onTop = index ~= 2
        Theme.New("Frame", {
            Name = "Chip",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(rng:NextNumber(0.1, 0.9), onTop and 0 or 1),
            Size = UDim2.fromOffset(rng:NextInteger(4, 14), rng:NextInteger(2, 3)),
            BackgroundColor3 = colors.Black,
            BackgroundTransparency = 0.15,
            BorderSizePixel = 0,
        }, frame)
    end

    -- Remaches en las esquinas, como una chapa vieja.
    for _, corner in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
        Theme.New("Frame", {
            Name = "Rivet",
            AnchorPoint = Vector2.new(corner[1], corner[2]),
            Position = UDim2.new(corner[1], corner[1] == 0 and 5 or -5, corner[2], corner[2] == 0 and 5 or -5),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = colors.Grime,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
        }, frame)
    end
end

-- Panel gastado: negro sucio, más oscuro abajo, borde de sangre seca y manchas.
-- plain = true lo deja sin manchas ni remaches (para piezas chicas).
function Theme.Panel(parent, properties, plain)
    local merged = {
        BackgroundColor3 = Theme.Colors.Panel,
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end

    local panel = Theme.New("Frame", merged, parent)
    Theme.Corner(panel, 3)
    Theme.Stroke(panel, Theme.Colors.Stroke, 1, 0.15)
    Theme.New("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(255, 240, 232), Color3.fromRGB(120, 108, 104)),
    }, panel)
    if not plain then
        Theme.Wear(panel, merged.Name or "Panel")
    end
    return panel
end

local function normalizeText(merged)
    local font = merged.Font
    if font and LEGACY_FONTS[font.Name] then
        merged.Font = LEGACY_FONTS[font.Name]
    end
    if merged.Font ~= Theme.Fonts.Display and (merged.TextSize or 0) < Theme.MinTextSize then
        merged.TextSize = Theme.MinTextSize
    end
end

function Theme.Label(parent, properties)
    local merged = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Colors.Text,
        Font = Theme.Fonts.Body,
        TextSize = 15,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Text = "",
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    normalizeText(merged)
    return Theme.New("TextLabel", merged, parent)
end

function Theme.Button(parent, text, properties)
    local merged = {
        BackgroundColor3 = Theme.Colors.Button,
        BackgroundTransparency = 0.04,
        TextColor3 = Theme.Colors.Text,
        Font = Theme.Fonts.Title,
        TextSize = 15,
        Text = text,
        AutoButtonColor = true,
        BorderSizePixel = 0,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    normalizeText(merged)

    local button = Theme.New("TextButton", merged, parent)
    Theme.Corner(button, 3)
    Theme.Stroke(button, Theme.Colors.Stroke, 1, 0.1)
    return button
end

-- Título grande con la letra de terror y un parpadeo de tubo viejo.
function Theme.Title(parent, properties)
    local merged = {
        Font = Theme.Fonts.Display,
        TextSize = 48,
        TextColor3 = Theme.Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    local label = Theme.Label(parent, merged)
    Theme.Flicker(label)
    return label
end

-- Línea divisoria irregular, como un trazo de tinta roja que se corta.
function Theme.Rule(parent, position, size, color)
    local holder = Theme.New("Frame", {
        Name = "Rule",
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
    }, parent)
    local fade = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.12, 0.15),
        NumberSequenceKeypoint.new(0.7, 0.3),
        NumberSequenceKeypoint.new(1, 1),
    })
    local main = Theme.New("Frame", {
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = color or Theme.Colors.Blood,
        BorderSizePixel = 0,
    }, holder)
    Theme.New("UIGradient", {Transparency = fade}, main)
    local echo = Theme.New("Frame", {
        Position = UDim2.new(0.08, 0, 0, 4),
        Size = UDim2.new(0.55, 0, 0, 1),
        BackgroundColor3 = color or Theme.Colors.Blood,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
    }, holder)
    Theme.New("UIGradient", {Transparency = fade}, echo)
    return holder
end

function Theme.CloseButton(parent, properties)
    local size = Theme.IsTouch and 46 or 40
    local merged = {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Theme.Colors.Track,
        TextColor3 = Theme.Colors.Danger,
        TextSize = 20,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    return Theme.Button(parent, "X", merged)
end

-- Ventana de menú centrada: panel gastado, título, trazo rojo y botón de cierre.
-- El tamaño se recorta al área segura, así nunca queda debajo de la barra de Roblox.
function Theme.Window(root, name, titleText, width, height, properties)
    local merged = {
        Name = name,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        BackgroundTransparency = 0.04,
        Visible = false,
    }
    for key, value in pairs(properties or {}) do
        merged[key] = value
    end
    local panel = Theme.Panel(root, merged)

    local heading = Theme.Label(panel, {
        Name = "Heading",
        Position = UDim2.fromOffset(18, 12),
        Size = UDim2.new(1, -90, 0, 28),
        Font = Theme.Fonts.Title,
        TextSize = 21,
        TextColor3 = Theme.Colors.Text,
        TextYAlignment = Enum.TextYAlignment.Center,
        Text = titleText or "",
    })
    Theme.Rule(panel, UDim2.fromOffset(14, 46), UDim2.new(1, -28, 0, 6))
    local close = Theme.CloseButton(panel)

    Theme.OnLayout(function(safe)
        panel.Size = UDim2.fromOffset(
            math.floor(math.min(width, safe.X - 16)),
            math.floor(math.min(height, safe.Y - 12))
        )
    end)

    return panel, heading, close
end

-- Escribe un texto letra por letra, como una máquina de escribir.
local typing = setmetatable({}, {__mode = "k"})

function Theme.Typewrite(label, text, charactersPerSecond)
    local token = (typing[label] or 0) + 1
    typing[label] = token
    label.Text = text
    local total = utf8.len(text) or #text
    local speed = charactersPerSecond or 40
    if total <= 0 then
        label.MaxVisibleGraphemes = -1
        return 0
    end

    label.MaxVisibleGraphemes = 0
    task.spawn(function()
        local shown = 0
        local step = math.max(1, math.floor(speed / 20))
        while shown < total and typing[label] == token do
            task.wait(step / speed)
            shown = math.min(total, shown + step)
            if typing[label] == token then
                label.MaxVisibleGraphemes = shown >= total and -1 or shown
            end
        end
    end)
    return total / speed
end

-- Corta una escritura en curso y muestra el texto completo.
function Theme.StopTyping(label)
    typing[label] = (typing[label] or 0) + 1
    label.MaxVisibleGraphemes = -1
end

-- Parpadeo y grano de película ---------------------------------------------------

local flickers = {}
local grains = {}
local updaterRunning = false
local grainClock = 0
local GRAIN_INTERVAL = 1 / 12
local LOW_GRAIN_INTERVAL = 1 / 6
local LOW_GRAIN_SPECKS = 5

local function dimColor(color)
    return Color3.new(color.R * 0.35, color.G * 0.35, color.B * 0.35)
end

local function updateFlickers(now)
    for index = #flickers, 1, -1 do
        local entry = flickers[index]
        local label = entry.Label
        if label.Parent == nil then
            table.remove(flickers, index)
        elseif now >= entry.Next then
            if entry.Off then
                label.TextColor3 = entry.Color
                entry.Off = false
                entry.Burst -= 1
                entry.Next = now + (entry.Burst > 0 and random:NextNumber(0.04, 0.12) or random:NextNumber(2, 6))
            else
                if entry.Burst <= 0 then
                    entry.Burst = random:NextInteger(1, 3)
                end
                label.TextColor3 = entry.Dim
                entry.Off = true
                entry.Next = now + random:NextNumber(0.04, 0.09)
            end
        end
    end
end

local function updateGrains()
    local animated = lowQuality and LOW_GRAIN_SPECKS or math.huge
    for index = #grains, 1, -1 do
        local entry = grains[index]
        local holder = entry.Holder
        if holder.Parent == nil then
            table.remove(grains, index)
        else
            local active = entry.IsActive == nil or entry.IsActive()
            if holder.Visible ~= active then
                holder.Visible = active
            end
            if active then
                for speckIndex, speck in ipairs(entry.Specks) do
                    if speckIndex > animated then
                        speck.BackgroundTransparency = 1
                    elseif speck.Name == "Scratch" then
                        speck.Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(-0.2, 0.5))
                        speck.BackgroundTransparency = random:NextNumber() < 0.5 and 1 or random:NextNumber(0.78, 0.92)
                    else
                        local size = random:NextInteger(1, 3)
                        speck.Size = UDim2.fromOffset(size, size)
                        speck.Position = UDim2.fromScale(random:NextNumber(0, 1), random:NextNumber(0, 1))
                        speck.BackgroundTransparency = random:NextNumber(0.35, 0.85)
                    end
                end
            end
        end
    end
end

-- Un único Heartbeat para todos los títulos y granos: nada se crea por cuadro.
local function startUpdater()
    if updaterRunning then
        return
    end
    updaterRunning = true
    RunService.Heartbeat:Connect(function(deltaTime)
        if #flickers > 0 then
            updateFlickers(os.clock())
        end
        if #grains > 0 then
            grainClock += deltaTime
            if grainClock >= (lowQuality and LOW_GRAIN_INTERVAL or GRAIN_INTERVAL) then
                grainClock = 0
                updateGrains()
            end
        end
    end)
end

function Theme.Flicker(label, color)
    local base = color or label.TextColor3
    table.insert(flickers, {
        Label = label,
        Color = base,
        Dim = dimColor(base),
        Next = os.clock() + random:NextNumber(0.8, 3),
        Burst = 0,
        Off = false,
    })
    startUpdater()
end

-- Grano de película: motas y rayas que saltan de lugar a 12 cuadros por segundo.
-- isActive (opcional) decide cuándo animarlo; si devuelve false se oculta.
function Theme.Grain(parent, count, isActive)
    local holder = Theme.New("Frame", {
        Name = "Grain",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 20,
    }, parent)

    local specks = {}
    for index = 1, count or 14 do
        local scratch = index <= 2
        specks[index] = Theme.New("Frame", {
            Name = scratch and "Scratch" or "Speck",
            Size = scratch and UDim2.new(0, 1, random:NextNumber(0.3, 0.8), 0) or UDim2.fromOffset(2, 2),
            BackgroundColor3 = (scratch or index % 3 == 0) and Theme.Colors.Text or Theme.Colors.Black,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 20,
        }, holder)
    end

    table.insert(grains, {Holder = holder, Specks = specks, IsActive = isActive})
    startUpdater()
    return holder
end

function Theme.SetLowQuality(enabled)
    lowQuality = enabled == true
end

function Theme.IsLowQuality()
    return lowQuality
end

-- Con cámara en primera persona el mouse está bloqueado: un botón Modal lo libera
-- mientras haya algún menú abierto.
local modalHolders = {}
local modalButton = nil

local function refreshModal()
    if not modalButton then
        local _, gui = Theme.Screen("NocturnaModal", -10)
        modalButton = Theme.New("TextButton", {
            Name = "Modal",
            Size = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Text = "",
            Modal = true,
            Visible = false,
        }, gui)
    end
    modalButton.Visible = next(modalHolders) ~= nil
end

function Theme.SetModal(key, enabled)
    modalHolders[key] = enabled and true or nil
    refreshModal()
end

return Theme
