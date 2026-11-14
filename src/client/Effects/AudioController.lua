-- Paisaje sonoro: música por capas según la fase y la amenaza, efectos y audio 3D.
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local AudioConfig = require(Shared.Config.AudioConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local SettingsUI = require(script.Parent.Parent.UI.SettingsUI)

local player = Players.LocalPlayer
local SFX_MAX_DISTANCE = 120

local AudioController = {}
-- Un SoundGroup por categoría (AudioConfig.Categories), todos bajo uno maestro.
local groups = {}
local settingsNow = nil
local duckLevel, duckUntil = 1, 0
local silenceLevel = 1
local nextSilence, silenceEnds = 0, 0
local lastPlayed = {}
local activeVoices = {}
local random = Random.new()

local function ruleOf(name)
    return AudioConfig.Rules[name] or {Category = "Horror", Cooldown = 0, Voices = 2, Variance = 0}
end

local function groupOf(category)
    return groups[category] or groups.Horror
end

-- Volumen de cada grupo = perilla de AJUSTES x atenuación por golpe x silencio.
local function applyGroupVolumes()
    if not settingsNow then
        return
    end
    for category, setting in pairs(AudioConfig.Categories) do
        local group = groups[category]
        if group then
            local volume = settingsNow[setting] or 0.8
            if category == "Music" or category == "Ambient" or category == "Chase" then
                volume *= duckLevel
            end
            if category == "Ambient" then
                volume *= silenceLevel
            end
            group.Volume = volume
        end
    end
end

-- Cooldown: el mismo sonido no se repite antes de tiempo. Devuelve false si se omite.
local function allow(name)
    local rule = ruleOf(name)
    local now = os.clock()
    if now - (lastPlayed[name] or -math.huge) < rule.Cooldown then
        return false
    end
    lastPlayed[name] = now
    return true
end
AudioController.Allow = allow

local function duckFor(name)
    local rule = ruleOf(name)
    if AudioConfig.Duck.Sounds[name] or AudioConfig.Duck.Categories[rule.Category] and rule.Cooldown >= 1 then
        duckLevel = AudioConfig.Duck.Level
        duckUntil = os.clock() + AudioConfig.Duck.Time
        applyGroupVolumes()
    end
end

local function varied(definition, name)
    local variance = ruleOf(name).Variance
    local speed = definition.Speed or 1
    if variance > 0 then
        speed *= 1 + random:NextNumber(-variance, variance)
    end
    return speed
end
local music = {}
local effects = {}
local musicTargets = {}
local heartClock = 0
local breathClock = 0

local function applyDefinition(sound, definition)
    sound.SoundId = definition.Id
    sound.Volume = math.min(definition.Volume or 1, AudioConfig.MaxVolume or 1.5)
    sound.PlaybackSpeed = definition.Speed or 1
    sound.Looped = definition.Looped == true

    if definition.Reverb then
        local reverb = Instance.new("ReverbSoundEffect")
        reverb.DecayTime = 2.8
        reverb.Density = 0.9
        reverb.WetLevel = -2
        reverb.Parent = sound
    end
    if definition.Distort then
        local distortion = Instance.new("DistortionSoundEffect")
        distortion.Level = definition.Distort
        distortion.Parent = sound
    end
    if definition.Chorus then
        local chorus = Instance.new("ChorusSoundEffect")
        chorus.Depth = 0.45
        chorus.Mix = 0.6
        chorus.Rate = 1.4
        chorus.Parent = sound
    end
end

local function createSound(name, definition, group, parent)
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundGroup = group
    applyDefinition(sound, definition)
    sound.Parent = parent
    return sound
end

function AudioController.Play(name)
    local sound = effects[name]
    if sound and allow(name) then
        sound.PlaybackSpeed = varied(AudioConfig.Sfx[name], name)
        sound.TimePosition = 0
        sound:Play()
        duckFor(name)
    end
end

-- Sonido en un punto del mundo, con atenuación por distancia.
function AudioController.PlayAt(name, position)
    local definition = AudioConfig.Sfx[name]
    if not definition or typeof(position) ~= "Vector3" then
        return
    end

    -- Más allá de donde se apaga no se oye: no se crea nada (ahorra en celulares).
    -- RollOff / MaxDistance (opcionales en AudioConfig): hasta dónde suena al
    -- máximo y dónde se apaga (los retumbes lejanos llegan más lejos).
    local maxDistance = definition.MaxDistance or SFX_MAX_DISTANCE
    local camera = workspace.CurrentCamera
    if camera and (position - camera.CFrame.Position).Magnitude > maxDistance then
        return
    end
    -- Pocas voces a la vez del mismo sonido y respetando su tiempo mínimo.
    local rule = ruleOf(name)
    if (activeVoices[name] or 0) >= rule.Voices or not allow(name) then
        return
    end
    activeVoices[name] = (activeVoices[name] or 0) + 1
    task.delay(math.max(1, 6 / math.max(definition.Speed or 1, 0.2)), function()
        activeVoices[name] = math.max(0, (activeVoices[name] or 1) - 1)
    end)

    local emitter = Instance.new("Attachment")
    emitter.WorldPosition = position
    emitter.Parent = workspace.Terrain

    local sound = createSound(name, definition, groupOf(rule.Category), emitter)
    sound.PlaybackSpeed = varied(definition, name)
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = definition.RollOff or 12
    sound.RollOffMaxDistance = maxDistance
    sound:Play()
    duckFor(name)
    Debris:AddItem(emitter, 8)
    return sound
end

local function setMusicTarget(name, volume)
    local sound = music[name]
    if not sound or musicTargets[name] == volume then
        return
    end

    musicTargets[name] = volume
    if volume > 0 and not sound.IsPlaying then
        sound:Play()
    end

    local tween = TweenService:Create(sound, TweenInfo.new(1.6), {Volume = volume})
    tween:Play()
    if volume == 0 then
        tween.Completed:Connect(function()
            if musicTargets[name] == 0 then
                sound:Stop()
            end
        end)
    end
end

local function updateMusic()
    local state = ClientState.Get("Game")
    local threat = player:GetAttribute("NocturnaThreat") or 0
    local phase = state.Phase
    local inMatch = phase == "Playing" or phase == "Cutscene"
    local isMemory = state.Chapter == 5
    local chased = inMatch and threat >= 0.6

    local definitions = AudioConfig.Music
    setMusicTarget("LobbyWind", phase == "Lobby" and definitions.LobbyWind.Volume or 0)
    setMusicTarget("AmbientDrone", inMatch and not isMemory and definitions.AmbientDrone.Volume or 0)
    setMusicTarget("AmbientLow", inMatch and definitions.AmbientLow.Volume or 0)
    setMusicTarget("MemoryTone", (inMatch or phase == "Ending") and isMemory and definitions.MemoryTone.Volume or 0)
    -- La persecución crece con la amenaza: entra suave y sube a medida que se acerca.
    local intensity = chased and math.clamp(0.4 + (threat - 0.6) * 1.5, 0.4, 1) or 0
    setMusicTarget("ChaseDrone", chased and definitions.ChaseDrone.Volume * intensity or 0)
    setMusicTarget("ChasePulse", chased and threat >= 0.75 and definitions.ChasePulse.Volume * intensity or 0)
    AudioController.Chased = chased
    AudioController.InMatch = phase == "Playing"
end

-- Atenuación por golpe y momentos de silencio del ambiente.
local function updateMix()
    local now = os.clock()
    local wantedDuck = now < duckUntil and AudioConfig.Duck.Level or 1
    duckLevel += (wantedDuck - duckLevel) * (wantedDuck < duckLevel and 0.5 or 0.04)

    local silence = AudioConfig.Silence
    if not AudioController.InMatch or AudioController.Chased then
        silenceEnds = 0
        if nextSilence < now then
            nextSilence = now + random:NextNumber(silence.Every[1], silence.Every[2])
        end
    elseif now >= nextSilence and silenceEnds == 0 then
        silenceEnds = now + random:NextNumber(silence.Duration[1], silence.Duration[2])
    end
    if silenceEnds > 0 and now >= silenceEnds then
        silenceEnds = 0
        nextSilence = now + random:NextNumber(silence.Every[1], silence.Every[2])
    end
    local wantedSilence = silenceEnds > 0 and silence.Level or 1
    silenceLevel += (wantedSilence - silenceLevel) * 0.02
    applyGroupVolumes()
end
AudioController.UpdateMix = updateMix
AudioController.Groups = groups

local function updateBody(deltaTime)
    local threat = player:GetAttribute("NocturnaThreat") or 0
    -- Con poca vida el corazón late aunque no haya nada cerca.
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 and humanoid.MaxHealth > 0 then
        local ratio = humanoid.Health / humanoid.MaxHealth
        if ratio <= 0.35 then
            threat = math.max(threat, 0.3 + (0.35 - ratio) * 1.5)
        end
    end
    if threat >= 0.3 then
        heartClock += deltaTime
        if heartClock >= 1.1 - threat * 0.6 then
            heartClock = 0
            AudioController.Play("Heartbeat")
        end
    end

    if (player:GetAttribute("Stamina") or 100) < 25 then
        breathClock += deltaTime
        if breathClock >= 1.5 then
            breathClock = 0
            AudioController.Play("Breath")
        end
    end
end

function AudioController.Start()
    SoundService.AmbientReverb = Enum.ReverbType.Cave
    SoundService.RespectFilteringEnabled = true

    for category in pairs(AudioConfig.Categories) do
        local group = Instance.new("SoundGroup")
        group.Name = "Nocturna" .. category
        group.Parent = SoundService
        groups[category] = group
    end

    for name, definition in pairs(AudioConfig.Music) do
        local category = AudioConfig.MusicCategory[name] or "Music"
        music[name] = createSound(name, definition, groupOf(category), SoundService)
        music[name].Volume = 0
    end
    for name, definition in pairs(AudioConfig.Sfx) do
        effects[name] = createSound(name, definition, groupOf(ruleOf(name).Category), SoundService)
    end

    SettingsUI.OnChanged(function(settings)
        settingsNow = settings
        applyGroupVolumes()
    end)

    Remotes.OnClient("PlaySound", function(name, position)
        if typeof(position) == "Vector3" then
            AudioController.PlayAt(name, position)
        else
            AudioController.Play(name)
        end
    end)

    ClientState.Subscribe("Game", updateMusic)
    player:GetAttributeChangedSignal("NocturnaThreat"):Connect(updateMusic)

    player:GetAttributeChangedSignal("FlashlightEnabled"):Connect(function()
        AudioController.Play("Flashlight")
    end)

    RunService.Heartbeat:Connect(updateBody)
    local mixClock = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        mixClock += deltaTime
        if mixClock >= 0.1 then
            mixClock = 0
            updateMix()
        end
    end)
end

return AudioController
