local SoundService = game:GetService("SoundService")

local folder = SoundService:FindFirstChild("NocturnaAudio")

if not folder then
    folder = Instance.new("Folder")
    folder.Name = "NocturnaAudio"
    folder.Parent = SoundService
end

local function createSound(name, soundId, volume, looped)
    local sound = folder:FindFirstChild(name)

    if not sound then
        sound = Instance.new("Sound")
        sound.Name = name
        sound.Parent = folder
    end

    sound.SoundId = soundId or ""
    sound.Volume = volume or 0.5
    sound.Looped = looped or false

    return sound
end

createSound("Ambient", "", 0.3, true)
createSound("MonsterBreath", "", 0.8, false)
createSound("MetalImpact", "", 0.7, false)
createSound("Heartbeat", "", 0.5, true)

print("[NOCTURNA] Estructura de audio preparada.")
