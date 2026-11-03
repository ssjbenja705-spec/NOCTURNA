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

local AudioController = {}
local musicGroup = nil
local effectsGroup = nil
local music = {}
local effects = {}
local musicTargets = {}
local heartClock = 0
local breathClock = 0

local function applyDefinition(sound, definition)
    sound.SoundId = definition.Id
    sound.Volume = definition.Volume or 1
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
    if sound then
        sound.TimePosition = 0
        sound:Play()
    end
end

-- Sonido en un punto del mundo, con atenuación por distancia.
function AudioController.PlayAt(name, position)
    local definition = AudioConfig.Sfx[name]
    if not definition then
        return
    end

    local emitter = Instance.new("Attachment")
    emitter.WorldPosition = position
    emitter.Parent = workspace.Terrain

    local sound = createSound(name, definition, effectsGroup, emitter)
    sound.RollOffMode = Enum.RollOffMode.InverseTapered
    sound.RollOffMinDistance = 12
    sound.RollOffMaxDistance = 120
    sound:Play()
    Debris:AddItem(emitter, 8)
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
    setMusicTarget("ChaseDrone", chased and definitions.ChaseDrone.Volume or 0)
    setMusicTarget("ChasePulse", chased and definitions.ChasePulse.Volume or 0)
end

local function updateBody(deltaTime)
    local threat = player:GetAttribute("NocturnaThreat") or 0
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

    musicGroup = Instance.new("SoundGroup")
    musicGroup.Name = "NocturnaMusic"
    musicGroup.Parent = SoundService

    effectsGroup = Instance.new("SoundGroup")
    effectsGroup.Name = "NocturnaEffects"
    effectsGroup.Parent = SoundService

    for name, definition in pairs(AudioConfig.Music) do
        music[name] = createSound(name, definition, musicGroup, SoundService)
        music[name].Volume = 0
    end
    for name, definition in pairs(AudioConfig.Sfx) do
        effects[name] = createSound(name, definition, effectsGroup, SoundService)
    end

    SettingsUI.OnChanged(function(settings)
        musicGroup.Volume = settings.MusicVolume
        effectsGroup.Volume = settings.EffectsVolume
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
end

return AudioController
