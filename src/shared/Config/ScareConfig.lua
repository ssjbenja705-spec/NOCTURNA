-- Sustos al azar de cada mapa: 3 o 4 por capítulo, en lugares distintos y
-- separados, cada uno una sola vez. Son sólo imagen y sonido en el cliente: no
-- hacen ruido para las criaturas ni cambian nada de la partida.
--
-- Shared = true: lo ven todos los que están cerca (un portazo, una sombra que
-- cruza). Shared = false: es de un solo jugador (pasos detrás de él, una figura a
-- su espalda) y prefiere a quien anda solo.
local ScareConfig = {}

ScareConfig.Kinds = {
    SHADOW_CROSS = {Shared = true, Visual = true},
    ROOM_SILHOUETTE = {Shared = true, Visual = true},
    DOOR_SLAM = {Shared = true, Visual = false},
    OBJECT_FALL = {Shared = true, Visual = true},
    LIGHT_REVEAL = {Shared = true, Visual = true},
    WINDOW_FACE = {Shared = true, Visual = true},
    FIGURE_BEHIND = {Shared = false, Visual = false},
    FOOTSTEPS_BEHIND = {Shared = false, Visual = false},
    DARK_SILHOUETTE = {Shared = false, Visual = true},
}

-- Orden fijo para que la misma semilla dé siempre el mismo plan.
ScareConfig.Order = {
    "SHADOW_CROSS", "ROOM_SILHOUETTE", "DOOR_SLAM", "OBJECT_FALL", "LIGHT_REVEAL",
    "WINDOW_FACE", "FIGURE_BEHIND", "FOOTSTEPS_BEHIND", "DARK_SILHOUETTE",
}

ScareConfig.MinCount = 3
ScareConfig.MaxCount = 4
-- Separación mínima entre los lugares de dos sustos (pasos de celda, en manhattan).
ScareConfig.MinCellSpacing = 2

ScareConfig.Timing = {
    -- Nada en el primer tramo del capítulo.
    FirstDelay = 45,
    -- Entre un susto y el siguiente: al azar entre estos dos valores.
    MinInterval = 50,
    MaxInterval = 95,
    -- Respiro después de un golpe, una captura, una cinemática o un susto guionado.
    AfterHit = 20,
    AfterCinematic = 8,
    AfterScripted = 15,
    CheckInterval = 0.5,
}

ScareConfig.Trigger = {
    -- Distancia al punto del susto para que se dispare (studs).
    MinDistance = 14,
    MaxDistance = 46,
    -- Si pasó mucho sin ningún susto, se acepta desde más lejos.
    RelaxAfter = 150,
    RelaxedDistance = 70,
    -- Para los visuales, el punto tiene que quedar delante del jugador.
    FacingDot = 0.35,
    -- Nada si hay una criatura cerca o persiguiendo (no se mezcla con la IA).
    MonsterClearance = 40,
    MaxThreat = 0.2,
    -- Los compartidos llegan a quienes están a esta distancia.
    SharedRange = 110,
    -- Quien anda solo (sin compañeros a esta distancia) tiene prioridad.
    AloneDistance = 30,
}

-- Sonidos del cliente de Roblox, deformados. Para usar audio propio alcanza con
-- reemplazar Id por "rbxassetid://...".
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local EXPLOSION = "rbxasset://sounds/impact_explosion_03.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local FALLING = "rbxasset://sounds/action_falling.ogg"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local CLICK = "rbxasset://sounds/volume_slider.ogg"

ScareConfig.Audio = {
    Step = {Id = STEP, Volume = 0.9, Speed = 0.8, Reverb = true},
    Slam = {Id = EXPLOSION, Volume = 0.8, Speed = 0.95, Reverb = true},
    Fall = {Id = LAND, Volume = 1, Speed = 0.8, Reverb = true},
    Clatter = {Id = EXPLOSION, Volume = 0.5, Speed = 1.4, Reverb = true},
    Whisper = {Id = SWIM, Volume = 0.6, Speed = 1.8, Reverb = true, Chorus = true},
    Sting = {Id = EXPLOSION, Volume = 0.55, Speed = 0.33, Reverb = true, Distort = 0.4},
    Breath = {Id = FALLING, Volume = 0.35, Speed = 1.6, Reverb = true},
    Buzz = {Id = CLICK, Volume = 0.7, Speed = 0.25, Reverb = true},
}

return ScareConfig
