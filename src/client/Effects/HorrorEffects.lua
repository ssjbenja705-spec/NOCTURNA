-- Efectos locales de terror: parpadeos, temblores, voces falsas, sustos y viñeta.
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local FirstPerson = require(script.Parent.Parent.Camera.FirstPerson)
local StoryUI = require(script.Parent.Parent.UI.StoryUI)
local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)

local player = Players.LocalPlayer

local HorrorEffects = {}
local blur = nil
local color = nil
local vignette = nil
local flash = nil
local lowQuality = false

local function nearbyLights(range)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return {}
    end

    local result = {}
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if (fixture.Position - root.Position).Magnitude <= range then
            local light = fixture:FindFirstChildOfClass("PointLight")
            if light then
                table.insert(result, light)
            end
        end
    end
    return result
end

-- Cada luz vuelve a como estaba: las que el servidor dejó a oscuras siguen apagadas.
local function flicker(times)
    local lights = nearbyLights(70)
    local original = {}
    for index, light in ipairs(lights) do
        original[index] = light.Enabled
    end

    for _ = 1, times do
        for _, light in ipairs(lights) do
            light.Enabled = false
        end
        task.wait(0.07)
        for index, light in ipairs(lights) do
            local fixture = light.Parent
            light.Enabled = original[index] and fixture ~= nil and fixture:GetAttribute("Dark") ~= true
        end
        task.wait(0.11)
    end
end

-- El desenfoque sólo está activo mientras dura un pulso: apagado no cuesta nada.
local blurToken = 0
local function pulseBlur(size, duration)
    if lowQuality then
        return
    end
    blurToken += 1
    local token = blurToken
    blur.Enabled = true
    blur.Size = size
    local tween = TweenService:Create(blur, TweenInfo.new(duration), {Size = 0})
    tween.Completed:Connect(function()
        if token == blurToken then
            blur.Enabled = false
        end
    end)
    tween:Play()
end

local function redFlash(strength)
    flash.BackgroundTransparency = 1 - strength
    TweenService:Create(flash, TweenInfo.new(0.7), {BackgroundTransparency = 1}):Play()
end

local HORROR = {}

function HORROR.LIGHTS_FLICKER()
    AudioController.Play("Stinger")
    flicker(5)
end

function HORROR.DISTANT_SOUND()
    AudioController.Play("Distant")
    pulseBlur(5, 1.5)
end

function HORROR.FALSE_ALARM()
    AudioController.Play("Radio")
    pulseBlur(10, 0.8)
    flicker(2)
end

function HORROR.ENVIRONMENT_WARNING()
    AudioController.Play("Metal")
    FirstPerson.Shake(1, 1.2)
end

function HORROR.WHISPER()
    AudioController.Play("Whisper")
    StoryUI.ShowLine({Speaker = "???", Text = "...contá..."})
end

function HORROR.BLACKOUT()
    AudioController.Play("Stinger")
    FirstPerson.Shake(1.5, 1)
end

function HORROR.ZONE_DARK()
    AudioController.Play("Distant")
end

local MONSTER = {}

function MONSTER.OyenteClick(data)
    AudioController.PlayAt("OyenteClick", data.Position)
end

function MONSTER.ImitatorVoice(data)
    AudioController.PlayAt("ImitatorVoice", data.Position)
    StoryUI.ShowLine({Speaker = data.Speaker, Text = data.Text})
end

function MONSTER.ImitatorScream(data)
    AudioController.PlayAt("ImitatorScream", data.Position)
end

function MONSTER.TrepadorSkitter(data)
    AudioController.PlayAt("TrepadorSkitter", data.Position)
end

function MONSTER.TrepadorDrop(data)
    AudioController.PlayAt("TrepadorDrop", data.Position)
    FirstPerson.Shake(2, 0.5)
end

local function shakeByDistance(data, strength, range)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        local power = 1 - math.clamp((root.Position - data.Position).Magnitude / range, 0, 1)
        if power > 0 then
            FirstPerson.Shake(strength * power, 0.6)
        end
    end
end

function MONSTER.ColosoStep(data)
    AudioController.PlayAt("ColosoStep", data.Position)
    shakeByDistance(data, 2, 60)
end

function MONSTER.ColosoRoar(data)
    AudioController.PlayAt("ColosoRoar", data.Position)
    shakeByDistance(data, 4, 90)
end

function MONSTER.Quake(data)
    AudioController.Play("Distant")
    shakeByDistance(data, 6, 140)
end

function MONSTER.Jumpscare()
    AudioController.Play("Jumpscare")
    AudioController.Play("Hurt")
    redFlash(0.65)
    pulseBlur(18, 0.6)
    FirstPerson.Shake(6, 0.7)
end

-- Bordes oscuros de la imagen: cuatro degradés (la interfaz no tiene degradé radial).
local EDGES = {
    {Anchor = Vector2.new(0, 0), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.22), Rotation = 90},
    {Anchor = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.22), Rotation = -90},
    {Anchor = Vector2.new(0, 0), Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.16, 1), Rotation = 0},
    {Anchor = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.16, 1), Rotation = 180},
}

local rollBar = nil

-- Capa de película debajo del HUD (así no tapa ni el HUD ni el botón para salir
-- del escondite): viñeta, grano, una franja que baja como en una cinta vieja,
-- el rojo de la vida baja, el destello del susto y las rendijas del casillero.
local function buildVignette()
    local root = Theme.Screen("NocturnaVignette", 0, true)

    for _, edge in ipairs(EDGES) do
        local frame = Theme.New("Frame", {
            Name = "Edge",
            AnchorPoint = edge.Anchor,
            Position = edge.Position,
            Size = edge.Size,
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
        }, root)
        Theme.New("UIGradient", {
            Rotation = edge.Rotation,
            Transparency = NumberSequence.new(0, 1),
        }, frame)
    end

    rollBar = Theme.New("Frame", {
        Name = "RollBar",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 0.07),
        BackgroundColor3 = Color3.fromRGB(230, 220, 200),
        BackgroundTransparency = 0.965,
        BorderSizePixel = 0,
    }, root)
    Theme.New("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, rollBar)
    Theme.Tween(rollBar, 9, {Position = UDim2.fromScale(0, 1.07)}, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1)

    Theme.Grain(root, 12)

    vignette = Theme.New("Frame", {
        Name = "Vignette",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(80, 0, 0),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
    }, root)

    Theme.New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.3, 1),
            NumberSequenceKeypoint.new(0.7, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
    }, vignette)
    vignette.Visible = false

    flash = Theme.New("Frame", {
        Name = "Flash",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(140, 8, 8),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, root)

    -- Desde el casillero sólo se ve lo que entra por las rendijas de la puerta.
    local slits = {}
    for _, anchor in ipairs({0, 1}) do
        table.insert(slits, Theme.New("Frame", {
            Name = "LockerSlit",
            AnchorPoint = Vector2.new(0, anchor),
            Position = UDim2.fromScale(0, anchor),
            Size = UDim2.fromScale(1, 0.42),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            Visible = false,
        }, root))
    end

    Remotes.OnClient("HideState", function(hidden)
        for _, slit in ipairs(slits) do
            slit.Visible = hidden
        end
    end)
end

local function watchHealth(character)
    local humanoid = character:WaitForChild("Humanoid", 10)
    if not humanoid then
        return
    end

    humanoid.HealthChanged:Connect(function(health)
        vignette.Visible = health > 0 and health <= GameConfig.Player.MaxHealth * 0.35
    end)
    vignette.Visible = false

    humanoid.Died:Connect(function()
        AudioController.Play("Death")
    end)
end

function HorrorEffects.Start()
    blur = Instance.new("BlurEffect")
    blur.Name = "NocturnaBlur"
    blur.Size = 0
    blur.Enabled = false
    blur.Parent = Lighting

    color = Instance.new("ColorCorrectionEffect")
    color.Name = "NocturnaColor"
    color.Contrast = 0.14
    color.Saturation = -0.2
    color.TintColor = Color3.fromRGB(215, 222, 235)
    color.Parent = Lighting

    buildVignette()

    SettingsUI.OnChanged(function(settings)
        color.Brightness = (settings.Brightness - 0.5) * 0.36
        lowQuality = settings.LowQuality
        Theme.SetLowQuality(settings.LowQuality)
        rollBar.Visible = not settings.LowQuality
    end)

    Remotes.OnClient("HorrorEvent", function(name, payload)
        local handler = HORROR[name]
        if handler then
            task.spawn(handler, payload)
        end
    end)

    Remotes.OnClient("MonsterEffect", function(name, payload)
        local handler = MONSTER[name]
        if handler then
            task.spawn(handler, payload)
        end
    end)

    player.CharacterAdded:Connect(watchHealth)
    if player.Character then
        task.spawn(watchHealth, player.Character)
    end
end

return HorrorEffects
