-- Persecución final del capítulo 5: la galería del Núcleo y El Organismo.
-- Todo lo ajustable vive acá. Las distancias van en studs sobre el eje de la
-- galería: S = 0 en la largada y crece hacia la compuerta del Núcleo (+Z).
--
-- Velocidades de referencia (GameConfig.Player): caminar 11, correr 19 (unos 9 s
-- de AIRE). El ritmo de la criatura queda entre las dos: corriendo se le gana
-- distancia, caminando o tropezando se la pierde.
local FinalChaseConfig = {}

FinalChaseConfig.Id = "FINAL_CHASE"

-- Galería ancha y recta, lejos del laberinto (que va de 0 a ~200 en X y Z) y del
-- lobby (Z = -1200). El piso queda en Y = 0, como el del laberinto, así el
-- antitrampas mide la altura igual que siempre.
FinalChaseConfig.Arena = {
    Origin = Vector3.new(-900, 0, 0),
    Width = 34,
    Height = 24,
    SegmentLength = 40,
    -- Desde dónde se construye (detrás de la largada: ahí irrumpe la criatura).
    BackS = -80,
    StartS = 6,
    FinishS = 520,
    Length = 580,
    -- Se arma por tramos: lo que está muy atrás se borra y lo de adelante se
    -- construye a tiempo. Así en un celular nunca hay más de ~6 tramos vivos.
    BuildAhead = 170,
    KeepBehind = 50,
    FogColor = Color3.fromRGB(22, 14, 14),
    FogStart = 8,
    FogEnd = 165,
    Ambient = Color3.fromRGB(26, 18, 18),
}

FinalChaseConfig.Creature = {
    Kind = "ElOrganismo",
    DisplayName = "El Organismo",
    -- Distancia al último jugador cuando irrumpe.
    StartGap = 40,
    -- A esta distancia o menos alcanza al jugador.
    CatchDistance = 5,
    -- Nunca pasa al último jugador ni queda más lejos que esto (si el último cae,
    -- se acerca a toda velocidad por detrás de la niebla, sin aparecer de golpe).
    MinGap = 2,
    MaxGap = 60,
    -- Ritmo base al comienzo y al final de la galería (se multiplica por la
    -- dificultad) y la distancia que intenta sostener detrás del último.
    PaceStart = 13.5,
    PaceEnd = 16.8,
    GapStart = 26,
    GapEnd = 12,
    -- Elástico: studs/s que suma o resta por cada stud de diferencia con esa distancia.
    BandGain = 0.5,
    MinSpeed = 6,
    MaxSpeed = 30,
    -- Sin saltos de velocidad: acelera y frena de a poco.
    Acceleration = 14,
    Deceleration = 30,
    -- Después de alcanzar a alguien ruge y se frena: la víctima tiene con qué escapar.
    RecoilTime = 1.2,
    CatchCooldown = 2.4,
    Damage = 34,
    Height = 17,
}

FinalChaseConfig.Obstacles = {
    FirstS = 72,
    -- Separación entre obstáculos: amplia al principio, apretada al final.
    SpacingStart = 52,
    SpacingEnd = 27,
    -- Respiro extra después de una compuerta o un derrumbe.
    RecoverySpacing = 6,
    LastBefore = 34,
    -- Cada tipo aparece primero solo, en este orden, y después se mezclan.
    Intro = {"Vault", "Slide", "Debris", "Door"},
    Pool = {"Vault", "Slide", "Debris", "Vault", "Slide", "Door"},
    -- Ventana de la acción: desde ActionReach studs antes del obstáculo hasta
    -- ActionLate después (la posición que ve el servidor llega un poco atrasada).
    ActionReach = 11,
    ActionLate = 2,
    -- Cuánto dura el permiso de una acción hecha antes de cruzar.
    TokenTime = 1.4,
    -- Quien cruza sin acción tiene este margen para que llegue su pedido (latencia).
    LateGrace = 0.3,
    StumbleDamage = 12,
    StumbleSlow = 0.35,
    StumbleTime = 1.1,
    -- Derrumbes: se disparan cuando el primero llega a DebrisLead studs y caen
    -- DebrisWarn segundos después sobre una franja de la galería.
    DebrisLead = 24,
    DebrisWarn = 1.3,
    DebrisHalfDepth = 5,
    DebrisDamage = 22,
    -- Compuertas: se embisten desde esta distancia y se rompen para todos.
    DoorReach = 10,
    VaultHeight = 3,
    SlideClearance = 4.2,
}

-- Qué pide cada obstáculo: "Jump" (Espacio / botón) o "Duck" (C / botón).
FinalChaseConfig.Actions = {
    Vault = "Jump",
    Door = "Jump",
    Slide = "Duck",
}

-- Textos en pantalla según la acción que pide el obstáculo que viene.
FinalChaseConfig.Prompts = {
    Vault = {Touch = "SALTAR", Key = "[ESPACIO] SALTAR"},
    Slide = {Touch = "AGACHARSE", Key = "[C] AGACHARSE"},
    Door = {Touch = "EMBESTIR", Key = "[ESPACIO] EMBESTIR"},
    Debris = {Touch = "¡ESQUIVÁ!", Key = "¡ESQUIVÁ!"},
}

-- Tiempos de la entrada y la salida (segundos).
FinalChaseConfig.Timing = {
    -- Espera a que termine la cinemática de la puerta del cuarto de Alma.
    GateCinematic = 3.6,
    FadeOut = 1.2,
    -- Pantalla negra con los textos de la transición (el grupo ya está en la galería).
    Arrive = 3.4,
    Reveal = 2.4,
    Countdown = 1.4,
    FinishFade = 1.6,
    CleanupAfter = 3,
    TickRate = 8,
}

-- Lo que se ve y se oye. Sólo se usan los sonidos que trae el cliente de Roblox,
-- deformados con velocidad, distorsión y eco (no hay archivos de audio propios).
-- MusicTrack queda libre para una pista original: con un "rbxassetid://..." la
-- partitura procedural baja y suena esa pista.
local FALLING = "rbxasset://sounds/action_falling.ogg"
local STEP = "rbxasset://sounds/action_footsteps_plastic.mp3"
local JUMP = "rbxasset://sounds/action_jump.mp3"
local LAND = "rbxasset://sounds/action_jump_land.mp3"
local SWIM = "rbxasset://sounds/action_swim.mp3"
local EXPLOSION = "rbxasset://sounds/impact_explosion_03.mp3"
local OUCH = "rbxasset://sounds/ouch.ogg"
local GET_UP = "rbxasset://sounds/action_get_up.mp3"

FinalChaseConfig.Audio = {
    MusicTrack = nil,
    Layers = {
        -- Zumbido grave que sube de tono con la cercanía.
        Drone = {Id = FALLING, Volume = 0.55, Speed = 0.17, MaxSpeed = 0.3, Looped = true, Distort = 0.35, Reverb = true},
        -- Tensión aguda (un roce estirado, como cuerdas) que entra con el peligro.
        Strings = {Id = SWIM, Volume = 0.4, Speed = 2.2, MaxSpeed = 2.9, Looped = true, Chorus = true, Reverb = true},
        -- Ambiente de la galería: aire que corre por los conductos.
        Air = {Id = FALLING, Volume = 0.3, Speed = 0.5, MaxSpeed = 0.55, Looped = true},
    },
    -- Percusión de suspenso: golpes graves cuyo tempo sube de 70 a 160 por minuto.
    Pulse = {Id = LAND, Volume = 0.9, Speed = 0.38, AccentSpeed = 0.3, MinBpm = 70, MaxBpm = 160},
    -- Golpe orquestal (explosión muy lenta) al empezar cada compás cuando aprieta.
    Hit = {Id = EXPLOSION, Volume = 0.55, Speed = 0.3, Reverb = true},
    Breath = {Id = SWIM, Volume = 0.45, Speed = 0.62},
    CreatureStep = {Id = EXPLOSION, Volume = 0.9, Speed = 0.21, Reverb = true},
    CreatureRoar = {Id = FALLING, Volume = 1, Speed = 0.26, Distort = 0.85, Reverb = true},
    Vault = {Id = JUMP, Volume = 0.6, Speed = 0.85},
    Land = {Id = LAND, Volume = 0.7, Speed = 0.7},
    Slide = {Id = STEP, Volume = 0.8, Speed = 0.45, Distort = 0.3},
    Stumble = {Id = OUCH, Volume = 0.8, Speed = 0.75},
    DoorBurst = {Id = EXPLOSION, Volume = 0.9, Speed = 0.75, Reverb = true},
    DebrisWarn = {Id = GET_UP, Volume = 0.8, Speed = 0.3, Reverb = true},
    DebrisImpact = {Id = EXPLOSION, Volume = 1, Speed = 0.5, Reverb = true},
    Stinger = {Id = EXPLOSION, Volume = 0.8, Speed = 0.35, Distort = 0.5, Reverb = true},
    Slam = {Id = EXPLOSION, Volume = 1, Speed = 0.4, Reverb = true},
}

return FinalChaseConfig
