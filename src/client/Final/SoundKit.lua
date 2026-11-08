-- Sonidos de la persecución y de los sustos. Usa los grupos de AudioController
-- (música y efectos) para respetar el volumen que eligió el jugador.
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundKit = {}
local MAX_DISTANCE = 140

local function groupFor(name)
    local found = SoundService:FindFirstChild(name)
    if found and found:IsA("SoundGroup") then
        return found
    end
    return nil
end

function SoundKit.Create(name, definition, parent, groupName)
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = definition.Id
    sound.Volume = definition.Volume or 1
    sound.PlaybackSpeed = definition.Speed or 1
    sound.Looped = definition.Looped == true
    sound.SoundGroup = groupFor(groupName or "NocturnaEffects")

    if definition.Reverb then
        local reverb = Instance.new("ReverbSoundEffect")
        reverb.DecayTime = 2.6
        reverb.Density = 0.9
        reverb.WetLevel = -3
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
    sound.Parent = parent or SoundService
    return sound
end

-- Suena una vez: en la cabeza (sin posición) o en un punto del mundo.
-- speed y volume (opcionales) multiplican los de la definición.
function SoundKit.Play(definition, position, speed, volume)
    if not definition then
        return nil
    end
    local parent = SoundService
    local holder = nil
    if typeof(position) == "Vector3" then
        local camera = workspace.CurrentCamera
        if camera and (position - camera.CFrame.Position).Magnitude > MAX_DISTANCE then
            return nil
        end
        holder = Instance.new("Attachment")
        holder.WorldPosition = position
        holder.Parent = workspace.Terrain
        parent = holder
    end
    local sound = SoundKit.Create("NocturnaOneShot", definition, parent)
    sound.PlaybackSpeed = (definition.Speed or 1) * (speed or 1)
    sound.Volume = (definition.Volume or 1) * (volume or 1)
    if holder then
        -- RollOff (opcional): hasta qué distancia suena al máximo.
        sound.RollOffMode = Enum.RollOffMode.InverseTapered
        sound.RollOffMinDistance = definition.RollOff or 10
        sound.RollOffMaxDistance = MAX_DISTANCE
    end
    sound:Play()
    Debris:AddItem(holder or sound, 8)
    return sound
end

return SoundKit
