-- Partitura de la persecución, armada en vivo con los sonidos del cliente de
-- Roblox: un zumbido grave que sube de tono, "cuerdas" agudas, aire en los
-- conductos, percusión de suspenso cuyo tempo sube con la cercanía de la criatura,
-- golpes al comienzo de cada compás y la respiración de quien corre.
--
-- intensity va de 0 (lejos, inquietante) a 1 (encima). Si FinalChaseConfig.Audio
-- trae MusicTrack, suena esa pista y las capas procedurales quedan de fondo.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FinalChaseConfig = require(Shared.Config.FinalChaseConfig)
local SoundKit = require(script.Parent.SoundKit)

local AUDIO = FinalChaseConfig.Audio
local BEATS_PER_BAR = 4

local ChaseScore = {}
local layers = {}
local track = nil
local running = false
local intensity = 0
local shown = 0
local beatClock = 0
local beat = 0
local breathClock = 0
local fade = 0

function ChaseScore.IsRunning()
    return running
end

function ChaseScore.Intensity()
    return shown
end

function ChaseScore.Start()
    if running then
        return
    end
    running = true
    fade = 0
    beat = 0
    beatClock = 0
    for name, definition in pairs(AUDIO.Layers) do
        local sound = SoundKit.Create("Chase" .. name, definition, nil, "NocturnaMusic")
        sound.Volume = 0
        sound:Play()
        layers[name] = {Sound = sound, Definition = definition}
    end
    if AUDIO.MusicTrack then
        track = SoundKit.Create("ChaseTrack", {Id = AUDIO.MusicTrack, Volume = 0.8, Looped = true}, nil, "NocturnaMusic")
        track:Play()
    end
end

function ChaseScore.Stop()
    running = false
    for _, layer in pairs(layers) do
        layer.Sound:Stop()
        layer.Sound:Destroy()
    end
    table.clear(layers)
    if track then
        track:Stop()
        track:Destroy()
        track = nil
    end
end

function ChaseScore.SetIntensity(value)
    intensity = math.clamp(value or 0, 0, 1)
end

-- Golpe sincronizado con un evento (salto, compuerta, derrumbe, captura).
function ChaseScore.Hit(name, position, speed, volume)
    return SoundKit.Play(AUDIO[name], position, speed, volume)
end

local function pulse()
    local definition = AUDIO.Pulse
    local accent = beat % BEATS_PER_BAR == 0
    SoundKit.Play({
        Id = definition.Id,
        Volume = definition.Volume * (accent and 1 or 0.55) * (0.4 + shown * 0.6),
        Speed = accent and definition.AccentSpeed or definition.Speed,
    })
    -- Con la criatura encima, un golpe grave marca cada compás.
    if accent and shown >= 0.55 then
        SoundKit.Play(AUDIO.Hit, nil, 1, 0.5 + shown * 0.5)
    end
    beat += 1
end

function ChaseScore.Update(deltaTime)
    if not running then
        return
    end
    -- Entra de a poco y la intensidad se suaviza para que nada salte.
    fade = math.min(1, fade + deltaTime / 2.5)
    shown += (intensity - shown) * math.min(1, deltaTime * 1.5)
    local background = track and 0.35 or 1

    for name, layer in pairs(layers) do
        local definition = layer.Definition
        local level
        if name == "Strings" then
            level = math.clamp((shown - 0.35) / 0.65, 0, 1)
        elseif name == "Air" then
            level = 1 - shown * 0.5
        else
            level = 0.45 + shown * 0.55
        end
        layer.Sound.Volume = definition.Volume * level * fade * background
        layer.Sound.PlaybackSpeed = definition.Speed + ((definition.MaxSpeed or definition.Speed) - definition.Speed) * shown
    end

    local bpm = AUDIO.Pulse.MinBpm + (AUDIO.Pulse.MaxBpm - AUDIO.Pulse.MinBpm) * shown
    beatClock += deltaTime
    if beatClock >= 60 / bpm then
        beatClock = 0
        pulse()
    end

    -- La respiración se acelera con el miedo.
    breathClock += deltaTime
    if breathClock >= 1.6 - shown * 0.9 then
        breathClock = 0
        SoundKit.Play(AUDIO.Breath, nil, 1 + shown * 0.25, 0.6 + shown * 0.4)
    end
end

return ChaseScore
