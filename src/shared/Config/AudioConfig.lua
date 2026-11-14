-- Todos los sonidos del juego. Se usan solamente los archivos que Roblox incluye
-- en el cliente, deformados con velocidad y efectos para crear el paisaje sonoro.
-- Para usar audio propio alcanza con reemplazar Id por "rbxassetid://...".

local FALLING = "rbxasset://sounds/action_falling.ogg"
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local GET_UP = "rbxasset://sounds/action_get_up.mp3"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local EXPLOSION = "rbxasset://sounds/impact_explosion_03.mp3"
local WATER = "rbxasset://sounds/impact_water.mp3"
local OOF = "rbxasset://sounds/oof.ogg"
local OUCH = "rbxasset://sounds/ouch.ogg"
local CLICK = "rbxasset://sounds/volume_slider.ogg"

local Audio = {
    Music = {
        AmbientDrone = {Id = FALLING, Volume = 0.55, Speed = 0.22, Looped = true, Reverb = true},
        AmbientLow = {Id = SWIM, Volume = 0.3, Speed = 0.18, Looped = true, Reverb = true},
        ChaseDrone = {Id = FALLING, Volume = 0.55, Speed = 0.42, Looped = true, Distort = 0.45},
        ChasePulse = {Id = LAND, Volume = 0.6, Speed = 0.4, Looped = true, Reverb = true},
        LobbyWind = {Id = FALLING, Volume = 0.35, Speed = 0.5, Looped = true},
        MemoryTone = {Id = SWIM, Volume = 0.4, Speed = 0.32, Looped = true, Reverb = true, Chorus = true},
    },
    Sfx = {
        UiClick = {Id = CLICK, Volume = 0.5, Speed = 1},
        Pickup = {Id = CLICK, Volume = 0.7, Speed = 0.7},
        ObjectiveDone = {Id = GET_UP, Volume = 0.7, Speed = 0.6, Reverb = true},
        DocumentOpen = {Id = STEP, Volume = 0.5, Speed = 1.6},
        Flashlight = {Id = CLICK, Volume = 0.8, Speed = 0.55},
        Hurt = {Id = OUCH, Volume = 0.8, Speed = 0.8},
        Death = {Id = OOF, Volume = 1, Speed = 0.45, Reverb = true},
        Heartbeat = {Id = LAND, Volume = 0.6, Speed = 0.55},
        Jumpscare = {Id = EXPLOSION, Volume = 0.8, Speed = 1.6, Distort = 0.45},
        Stinger = {Id = EXPLOSION, Volume = 0.6, Speed = 0.35, Reverb = true},
        DoorOpen = {Id = GET_UP, Volume = 0.8, Speed = 0.42, Spatial = true},
        DoorSlam = {Id = EXPLOSION, Volume = 0.7, Speed = 0.9, Spatial = true, Reverb = true},
        DoorLocked = {Id = CLICK, Volume = 1, Speed = 0.3, Spatial = true},
        MachineStart = {Id = EXPLOSION, Volume = 0.8, Speed = 0.3, Spatial = true, Reverb = true},
        Metal = {Id = EXPLOSION, Volume = 0.45, Speed = 1.25, Spatial = true, Reverb = true},
        Distant = {Id = EXPLOSION, Volume = 0.35, Speed = 0.28, Reverb = true},
        Whisper = {Id = SWIM, Volume = 0.7, Speed = 1.7, Reverb = true, Chorus = true},
        Radio = {Id = FALLING, Volume = 0.35, Speed = 2.4, Distort = 0.8},
        OyenteClick = {Id = CLICK, Volume = 1, Speed = 0.42, Spatial = true, Reverb = true},
        ImitatorVoice = {Id = SWIM, Volume = 0.9, Speed = 1.2, Spatial = true, Reverb = true, Chorus = true},
        ImitatorScream = {Id = OUCH, Volume = 0.85, Speed = 0.5, Spatial = true, Distort = 0.45, Reverb = true},
        QuietoScrape = {Id = STEP, Volume = 0.9, Speed = 0.35, Spatial = true, Reverb = true},
        TrepadorSkitter = {Id = STEP, Volume = 0.9, Speed = 2.1, Spatial = true, Reverb = true},
        TrepadorDrop = {Id = LAND, Volume = 1, Speed = 0.7, Spatial = true},
        -- Pisada de El Coloso en capas (ColosoFootsteps): el golpe (audible también
        -- en parlantes de celular: no tan grave), el retumbe del piso de cerca, el
        -- crujido de escombros y el retumbe lejano que avisa que viene.
        ColosoStep = {Id = EXPLOSION, Volume = 1.4, Speed = 0.45, Spatial = true, Reverb = true, RollOff = 18, MaxDistance = 130},
        ColosoBoom = {Id = LAND, Volume = 1.5, Speed = 0.32, Spatial = true, Reverb = true, RollOff = 14, MaxDistance = 80},
        ColosoDebris = {Id = STEP, Volume = 1.2, Speed = 0.55, Spatial = true, Distort = 0.3, RollOff = 10, MaxDistance = 50},
        ColosoRumble = {Id = EXPLOSION, Volume = 1.3, Speed = 0.2, Spatial = true, Reverb = true, RollOff = 45, MaxDistance = 220},
        ColosoRoar = {Id = FALLING, Volume = 1, Speed = 0.3, Spatial = true, Distort = 0.8, Reverb = true},
        Collapse = {Id = EXPLOSION, Volume = 1, Speed = 0.55, Spatial = true, Reverb = true},
        WaterDrop = {Id = WATER, Volume = 0.25, Speed = 1.8, Reverb = true},
        Breath = {Id = SWIM, Volume = 0.45, Speed = 0.6},
        Land = {Id = JUMP, Volume = 0.3, Speed = 0.5},
        -- Captura y forcejeo (sonidos de la biblioteca de Roblox deformados; sin
        -- voces grabadas ni sonidos propios).
        CaptureGrab = {Id = EXPLOSION, Volume = 0.75, Speed = 0.75, Distort = 0.6, Reverb = true},
        StruggleEffort = {Id = GET_UP, Volume = 0.55, Speed = 1.7},
        StruggleMiss = {Id = OUCH, Volume = 0.55, Speed = 1.15},
        StruggleTick = {Id = CLICK, Volume = 0.6, Speed = 1.6},
        WetBreath = {Id = SWIM, Volume = 0.8, Speed = 0.4, Spatial = true, Reverb = true, Distort = 0.35},
        Drool = {Id = WATER, Volume = 0.45, Speed = 0.55, Spatial = true},
        CaptureSqueeze = {Id = STEP, Volume = 0.9, Speed = 0.25, Spatial = true, Distort = 0.5},
        CaptureHit = {Id = LAND, Volume = 1, Speed = 1.35, Distort = 0.4},
        CaptureDevour = {Id = OUCH, Volume = 1, Speed = 0.32, Distort = 0.8, Reverb = true},
    },
}

-- Mezcla: cada sonido pertenece a una categoría con su propio volumen (y su perilla
-- en AJUSTES). Las reglas evitan el ruido: Cooldown (segundos mínimos entre dos
-- veces el mismo sonido), Voices (cuántos a la vez en el mundo) y Variance
-- (variación de tono para que los pasos no suenen todos iguales).
Audio.Categories = {
    -- Categoría -> perilla de AJUSTES que la controla.
    Ambient = "AmbientVolume",
    Music = "MusicVolume",
    Chase = "MusicVolume",
    Monsters = "MonsterVolume",
    Footsteps = "EffectsVolume",
    Interaction = "EffectsVolume",
    Horror = "EffectsVolume",
    Cinematic = "EffectsVolume",
    UI = "UiVolume",
}

Audio.MusicCategory = {
    AmbientDrone = "Ambient",
    AmbientLow = "Ambient",
    LobbyWind = "Ambient",
    MemoryTone = "Music",
    ChaseDrone = "Chase",
    ChasePulse = "Chase",
}

local function rule(category, cooldown, voices, variance)
    return {Category = category, Cooldown = cooldown or 0, Voices = voices or 2, Variance = variance or 0}
end

Audio.Rules = {
    UiClick = rule("UI", 0.05),
    Pickup = rule("UI", 0.2),
    ObjectiveDone = rule("UI", 1),
    DocumentOpen = rule("UI", 0.3),
    Flashlight = rule("UI", 0.15),

    DoorOpen = rule("Interaction", 0.3, 2, 0.05),
    DoorLocked = rule("Interaction", 0.8, 1),
    MachineStart = rule("Interaction", 1.5, 1),
    Metal = rule("Interaction", 1.5, 2, 0.08),

    Hurt = rule("Horror", 0.6, 1, 0.06),
    Death = rule("Horror", 3, 1),
    Jumpscare = rule("Horror", 8, 1),
    Stinger = rule("Horror", 12, 1),
    Distant = rule("Horror", 20, 1, 0.1),
    Whisper = rule("Horror", 25, 1, 0.08),
    Radio = rule("Horror", 2, 1),
    DoorSlam = rule("Horror", 4, 1),
    Collapse = rule("Horror", 5, 1),
    WaterDrop = rule("Ambient", 6, 1, 0.15),

    Heartbeat = rule("Footsteps", 0.45, 1),
    Breath = rule("Footsteps", 1.2, 1, 0.08),
    Land = rule("Footsteps", 0.3, 1, 0.1),

    OyenteClick = rule("Monsters", 0.8, 2, 0.06),
    ImitatorVoice = rule("Monsters", 4, 1, 0.05),
    ImitatorScream = rule("Monsters", 6, 1),
    QuietoScrape = rule("Monsters", 1.5, 2, 0.08),
    TrepadorSkitter = rule("Monsters", 0.6, 2, 0.1),
    TrepadorDrop = rule("Monsters", 3, 1),
    ColosoStep = rule("Monsters", 0.25, 3, 0.06),
    ColosoBoom = rule("Monsters", 0.4, 2, 0.05),
    ColosoDebris = rule("Monsters", 0.6, 2, 0.12),
    ColosoRumble = rule("Monsters", 1.5, 1),
    ColosoRoar = rule("Monsters", 6, 1),
    WetBreath = rule("Monsters", 2, 1, 0.08),
    Drool = rule("Monsters", 1.5, 1, 0.1),
    CaptureSqueeze = rule("Monsters", 1, 1),

    CaptureGrab = rule("Cinematic", 1, 1),
    StruggleEffort = rule("Cinematic", 0.12, 1, 0.08),
    StruggleMiss = rule("Cinematic", 0.2, 1),
    StruggleTick = rule("Cinematic", 0.1, 1),
    CaptureHit = rule("Cinematic", 1, 1),
    CaptureDevour = rule("Cinematic", 2, 1),
}

-- Los sonidos fuertes bajan la música y el ambiente un momento (no compiten).
Audio.Duck = {
    Categories = {Horror = true, Cinematic = true},
    Sounds = {Jumpscare = true, Stinger = true, CaptureGrab = true, CaptureDevour = true, ColosoRoar = true, Death = true},
    Level = 0.35,
    Time = 2.5,
}

-- Silencio: de vez en cuando el ambiente casi desaparece unos segundos (la tensión
-- también es no escuchar nada). Nunca durante una persecución.
Audio.Silence = {
    Every = {70, 140},
    Duration = {9, 15},
    Level = 0.12,
}

-- Ningún sonido suelto pasa de este volumen (antes había golpes de 2 y más).
Audio.MaxVolume = 1.5

return Audio
