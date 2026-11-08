-- Sustos de cada mapa: 3 o 4 por capítulo, en lugares distintos, cada uno una sola
-- vez, y GARANTIZADOS: el primero llega a los ~20-30 s de juego y los demás se
-- reparten para que todos pasen dentro de un capítulo normal. Si al jugador no se
-- le ocurre pasar por el lugar planeado a tiempo, el susto se muda adelante suyo
-- (o, si ahí no puede, cambia por uno que no necesita lugar, como pasos detrás).
-- Son sólo imagen y sonido en el cliente: no hacen ruido para las criaturas ni
-- cambian nada de la partida.
--
-- Shared = true: lo ven todos los que están cerca (un portazo, una sombra que
-- cruza). Shared = false: es de un solo jugador (pasos detrás de él, una figura a
-- su espalda, una cara que se le tira encima) y prefiere a quien anda solo.
-- Visual = true: necesita que el lugar quede delante del jugador.
-- Jumpscare = true: susto de golpe a pantalla completa (no necesita lugar: se
-- dispara al entrar a la zona o cuando le toca).
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
    -- Una cara pálida que se tira contra la cámara.
    FACE_LUNGE = {Shared = false, Visual = false, Jumpscare = true},
    -- Una criatura oscura que aparece de la nada y se abalanza con la boca abierta.
    CREATURE_LUNGE = {Shared = false, Visual = false, Jumpscare = true},
}

-- Orden fijo para que la misma semilla dé siempre el mismo plan.
ScareConfig.Order = {
    "SHADOW_CROSS", "ROOM_SILHOUETTE", "DOOR_SLAM", "OBJECT_FALL", "LIGHT_REVEAL",
    "WINDOW_FACE", "FIGURE_BEHIND", "FOOTSTEPS_BEHIND", "DARK_SILHOUETTE",
    "FACE_LUNGE", "CREATURE_LUNGE",
}

-- Si hay que cambiar un susto que no puede pasar donde está el jugador, por cuál
-- (en este orden, el primero que el mapa todavía no usó).
ScareConfig.Fallbacks = {"FOOTSTEPS_BEHIND", "FIGURE_BEHIND", "DOOR_SLAM"}

ScareConfig.MinCount = 3
ScareConfig.MaxCount = 4
-- Sustos de golpe por mapa según la cantidad (nunca el primero del mapa).
ScareConfig.Jumpscares = {[3] = 1, [4] = 2}
-- Separación mínima entre los lugares de dos sustos (pasos de celda, en manhattan).
ScareConfig.MinCellSpacing = 2

ScareConfig.Timing = {
    -- Tiempo de juego (sin contar escenas ni la persecución final) desde el que
    -- puede pasar el primero si alguien pasa por su lugar, y en el que se fuerza.
    FirstDelay = 18,
    FirstDue = 28,
    -- Después de cada susto: espera mínima hasta el próximo si alguien pasa por su
    -- lugar, y cuándo se fuerza (al azar entre estos dos valores).
    MinGap = 30,
    MinInterval = 50,
    MaxInterval = 70,
    -- Respiro después de un golpe, una captura, una cinemática o un susto guionado.
    AfterHit = 20,
    AfterCinematic = 8,
    AfterScripted = 15,
    CheckInterval = 0.5,
}

ScareConfig.Trigger = {
    -- Distancia al punto del susto para que se dispare solo (studs).
    MinDistance = 10,
    MaxDistance = 55,
    -- Los sustos de golpe se disparan al entrar a esta distancia de su zona.
    JumpscareRadius = 20,
    -- Para los visuales, el punto tiene que quedar delante del jugador.
    FacingDot = 0.2,
    -- Al mudar un susto visual: a esta distancia adelante del jugador.
    RelocateDistance = 18,
    -- Nada si hay una criatura cerca o persiguiendo (no se mezcla con la IA).
    MonsterClearance = 40,
    MaxThreat = 0.2,
    -- Los compartidos llegan a quienes están a esta distancia.
    SharedRange = 110,
    -- Quien anda solo (sin compañeros a esta distancia) tiene prioridad.
    AloneDistance = 30,
}

-- Sonidos del cliente de Roblox, deformados (los mismos archivos que AudioConfig).
-- Volumen alto a propósito: el grupo de efectos y la opción del jugador lo bajan.
-- RollOff: distancia hasta la que suena al máximo (más lejos se atenúa).
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local EXPLOSION = "rbxasset://sounds/impact_explosion_03.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local FALLING = "rbxasset://sounds/action_falling.ogg"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local CLICK = "rbxasset://sounds/volume_slider.ogg"
local OUCH = "rbxasset://sounds/ouch.ogg"

ScareConfig.Audio = {
    Step = {Id = STEP, Volume = 2, Speed = 0.75, Reverb = true, RollOff = 24},
    Slam = {Id = EXPLOSION, Volume = 2.6, Speed = 0.9, Reverb = true, RollOff = 40},
    Fall = {Id = LAND, Volume = 2.4, Speed = 0.75, Reverb = true, RollOff = 30},
    Clatter = {Id = EXPLOSION, Volume = 1.4, Speed = 1.4, Reverb = true, RollOff = 30},
    Whisper = {Id = SWIM, Volume = 1.8, Speed = 1.8, Reverb = true, Chorus = true, RollOff = 24},
    Sting = {Id = EXPLOSION, Volume = 2.4, Speed = 0.33, Reverb = true, Distort = 0.5},
    Breath = {Id = FALLING, Volume = 1.4, Speed = 1.6, Reverb = true, RollOff = 16},
    Buzz = {Id = CLICK, Volume = 1.8, Speed = 0.25, Reverb = true, RollOff = 30},
    -- Golpe del susto de golpe: estallido agudo distorsionado + grito grave.
    Jumpscare = {Id = EXPLOSION, Volume = 3.2, Speed = 1.25, Distort = 0.8},
    Shriek = {Id = OUCH, Volume = 2.8, Speed = 0.55, Distort = 0.65, Reverb = true},
    Screech = {Id = FALLING, Volume = 2.4, Speed = 2.8, Distort = 0.7},
    Thud = {Id = LAND, Volume = 2.6, Speed = 0.5, Reverb = true},
}

return ScareConfig
