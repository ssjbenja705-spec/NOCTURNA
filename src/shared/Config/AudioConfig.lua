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

return {
    Music = {
        AmbientDrone = {Id = FALLING, Volume = 0.55, Speed = 0.22, Looped = true, Reverb = true},
        AmbientLow = {Id = SWIM, Volume = 0.3, Speed = 0.18, Looped = true, Reverb = true},
        ChaseDrone = {Id = FALLING, Volume = 0.75, Speed = 0.42, Looped = true, Distort = 0.45},
        ChasePulse = {Id = LAND, Volume = 0.9, Speed = 0.4, Looped = true, Reverb = true},
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
        Heartbeat = {Id = LAND, Volume = 0.9, Speed = 0.55},
        Jumpscare = {Id = EXPLOSION, Volume = 1, Speed = 1.6, Distort = 0.7},
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
        ImitatorScream = {Id = OUCH, Volume = 1, Speed = 0.5, Spatial = true, Distort = 0.6, Reverb = true},
        QuietoScrape = {Id = STEP, Volume = 0.9, Speed = 0.35, Spatial = true, Reverb = true},
        TrepadorSkitter = {Id = STEP, Volume = 0.9, Speed = 2.1, Spatial = true, Reverb = true},
        TrepadorDrop = {Id = LAND, Volume = 1, Speed = 0.7, Spatial = true},
        ColosoStep = {Id = EXPLOSION, Volume = 0.8, Speed = 0.25, Spatial = true, Reverb = true},
        ColosoRoar = {Id = FALLING, Volume = 1, Speed = 0.3, Spatial = true, Distort = 0.8, Reverb = true},
        Collapse = {Id = EXPLOSION, Volume = 1, Speed = 0.55, Spatial = true, Reverb = true},
        WaterDrop = {Id = WATER, Volume = 0.25, Speed = 1.8, Reverb = true},
        Breath = {Id = SWIM, Volume = 0.45, Speed = 0.6},
        Land = {Id = JUMP, Volume = 0.3, Speed = 0.5},
        -- Captura y forcejeo (sonidos de la biblioteca de Roblox deformados; sin
        -- voces grabadas ni sonidos propios).
        CaptureGrab = {Id = EXPLOSION, Volume = 0.9, Speed = 0.75, Distort = 0.6, Reverb = true},
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
