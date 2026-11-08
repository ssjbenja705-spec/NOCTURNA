-- Cómo se mueve cada criatura: números del paso, la inercia, la cabeza y las
-- poses de cada estado. MonsterAnimator mezcla estas poses con pesos suaves, así
-- ningún cambio de estado es un corte seco.
--
-- Canales de pose (se suman ponderados por el peso de cada estado):
--   Lean      inclinación del torso hacia adelante (rad)
--   Crouch    altura de la cadera (studs, negativo = más baja)
--   ArmsFwd   brazos hacia adelante (rad; negativo = hacia atrás)
--   ArmsOut   brazos abiertos hacia los costados (rad)
--   HeadPitch cabeza hacia arriba (rad)
--   HeadRoll  cabeza ladeada (rad)
--   Jaw       boca abierta (0..1, se limita según la pieza disponible)
--   Spread    patas abiertas hacia los costados (rad)
--
-- Paso: el ciclo mide StrideWalk..StrideRun largos de pierna y la fase avanza con
-- la velocidad real medida, así el pie apoyado no patina (ver CreatureMotion).
local CreatureStyles = {}

CreatureStyles.Channels = {"Lean", "Crouch", "ArmsFwd", "ArmsOut", "HeadPitch", "HeadRoll", "Jaw", "Spread"}

-- Todos los estados públicos que anima el cliente.
CreatureStyles.States = {
    "Idle", "Patrol", "Investigate", "Search", "Chase", "Attack", "Ambush", "Flee",
    "Settle", "Frozen", "Stunned", "Recover", "Capture",
}

local DEFAULT = {
    -- Paso
    StrideWalk = 1.7, StrideRun = 2.7, WalkDuty = 0.62, RunDuty = 0.42,
    WalkSpeed = 7, RunSpeed = 15, Clearance = 0.08, TurnStep = 1.2,
    RunBounce = 0.12, ImpactDip = 0, Heavy = false, Quadruped = false,
    -- Inercia del cuerpo
    Follow = 4.5, TurnFreq = 2, TurnDamp = 0.85, AccelLean = 0.012, Bank = 0.012,
    Lean = 0.3, Sway = 0.12, Twist = 0.14, Splay = 0,
    -- Brazos (péndulo) y cabeza (resorte)
    ArmSwing = 0.35, ArmFreq = 2, ArmDamp = 0.55,
    HeadFreq = 2.5, HeadDamp = 0.8, SnapFreq = 6, SnapDamp = 0.5,
    HeadYawLimit = 1.2, HeadStabilize = 0,
    -- Respiración y tics
    Breath = 2.6, BreathAmount = 0.05, TwitchEvery = {2, 5}, TwitchSize = 0.2,
    -- Aturdido
    StunCrouch = -0.45,
    -- Boca: apertura máxima con la pieza cortada del modelo y con una mandíbula propia.
    JawCut = 0.3, JawHinged = 1,
    States = {
        Investigate = {Lean = 0.08, HeadPitch = -0.05},
        Search = {Lean = 0.12, Crouch = -0.1, HeadPitch = -0.08},
        Chase = {Lean = 0.22, Crouch = -0.15, ArmsOut = 0.12},
        Ambush = {Lean = 0.25, Crouch = -0.35, ArmsOut = 0.2},
        Flee = {Lean = 0.15, Crouch = -0.1},
        Stunned = {Lean = 0.22, ArmsOut = 0.1, HeadPitch = -0.3},
        Recover = {Lean = 0.1},
        Capture = {Crouch = -0.2, ArmsOut = 0.35},
    },
    -- Ataque: anticipación (Windup), estocada (Strike), vuelta (Recover) y error (Miss).
    Attack = {
        Windup = {Lean = -0.28, ArmsFwd = -0.9, ArmsOut = 0.35, Crouch = -0.18, Jaw = 0.35, HeadPitch = 0.1},
        Strike = {Lean = 0.5, ArmsFwd = 1.7, ArmsOut = 0.1, Crouch = -0.05, Jaw = 0.9, HeadPitch = -0.1},
        Recover = {Lean = 0.18, ArmsFwd = 0.5, ArmsOut = 0.05, Jaw = 0.2},
        Miss = {Lean = 0.45, ArmsFwd = 0.2, ArmsOut = 0.25, Crouch = -0.25, Jaw = 0.1, HeadPitch = -0.2},
    },
}

local STYLES = {
    -- Ciego, alto, brazos larguísimos que cuelgan. Paso irregular (rengueo), la
    -- cabeza manda: gira de golpe hacia cada ruido y se ladea para escuchar.
    ElOyente = {
        StrideWalk = 1.6, StrideRun = 2.9, WalkDuty = 0.64, RunDuty = 0.4,
        WalkSpeed = 6, RunSpeed = 15, Clearance = 0.07,
        TurnFreq = 1.8, TurnDamp = 0.75, Lean = 0.45, Sway = 0.16, Twist = 0.16,
        ArmSwing = 0.28, ArmFreq = 1.4, ArmDamp = 0.32,
        HeadFreq = 2.2, HeadDamp = 0.7, SnapFreq = 9, SnapDamp = 0.42, HeadYawLimit = 1.4,
        Breath = 2.6, BreathAmount = 0.05, TwitchEvery = {2, 5}, TwitchSize = 0.22,
        -- Rengueo: una pierna apoya más tiempo y el ritmo no es parejo.
        Limp = 0.07, PhaseLag = 0.06,
        States = {
            Idle = {HeadPitch = 0.1},
            Investigate = {Lean = 0.15, HeadPitch = 0.08, ArmsOut = 0.08},
            Search = {Lean = 0.2, Crouch = -0.15, HeadPitch = 0.12},
            -- Corre encorvado, la cabeza adelante y los brazos abiertos atrás.
            Chase = {Lean = 0.5, Crouch = -0.35, ArmsFwd = -0.35, ArmsOut = 0.45, HeadPitch = 0.25},
        },
        Attack = {
            Windup = {Lean = -0.1, ArmsFwd = 0.4, ArmsOut = 0.9, Crouch = -0.3, HeadPitch = 0.2},
            Strike = {Lean = 0.65, ArmsFwd = 1.9, ArmsOut = 0.05, Crouch = -0.2, HeadPitch = 0.1},
            Recover = {Lean = 0.3, ArmsFwd = 0.6, ArmsOut = 0.2, Crouch = -0.1},
            Miss = {Lean = 0.6, ArmsFwd = 0.4, ArmsOut = 0.4, Crouch = -0.35, HeadPitch = -0.15},
        },
    },
    -- Negro, boca roja. Fluido pero antinatural: la cabeza queda fija mientras el
    -- cuerpo ondula, se ladea demasiado y cambia de postura al perseguir.
    ElImitador = {
        StrideWalk = 1.7, StrideRun = 2.8, WalkDuty = 0.6, RunDuty = 0.42,
        WalkSpeed = 7, RunSpeed = 16, Clearance = 0.09,
        TurnFreq = 2.2, TurnDamp = 0.55, Lean = 0.3, Sway = 0.1, Twist = 0.22,
        ArmSwing = 0.45, ArmFreq = 1.8, ArmDamp = 0.45,
        HeadFreq = 1.6, HeadDamp = 0.55, SnapFreq = 7, SnapDamp = 0.5,
        HeadYawLimit = 1.9, HeadStabilize = 0.85,
        Breath = 2, BreathAmount = 0.045, TwitchEvery = {1.5, 3.5}, TwitchSize = 0.3,
        -- Encorvado a cuatro patas al perseguir (se mezcla con la postura erguida).
        Hunch = {Lean = 0.8, Crouch = -0.75, ArmsFwd = 0.75, ArmsOut = 0.35, HeadPitch = 0.75},
        States = {
            Chase = {Lean = 0.25, Crouch = -0.15, ArmsOut = 0.2},
            Ambush = {Lean = 0.4, Crouch = -0.5, ArmsOut = 0.3, HeadPitch = 0.3},
        },
        Attack = {
            -- La cabeza se va hacia atrás y la boca se abre de más.
            Windup = {Lean = -0.35, ArmsFwd = -0.6, ArmsOut = 0.6, Crouch = -0.25, Jaw = 0.8, HeadPitch = 0.65},
            Strike = {Lean = 0.6, ArmsFwd = 1.8, ArmsOut = 0.15, Crouch = -0.1, Jaw = 1, HeadPitch = -0.15},
            Recover = {Lean = 0.2, ArmsFwd = 0.5, Jaw = 0.4, HeadPitch = 0.1},
            Miss = {Lean = 0.5, ArmsFwd = 0.3, ArmsOut = 0.3, Crouch = -0.3, Jaw = 0.3, HeadPitch = -0.2},
        },
    },
    -- Maniquí: no respira; el torso y los brazos casi no se mueven al caminar, la
    -- cabeza queda clavada en su presa. Rápido y liso cuando nadie lo mira.
    ElQuieto = {
        StrideWalk = 1.8, StrideRun = 3, WalkDuty = 0.6, RunDuty = 0.45,
        WalkSpeed = 6, RunSpeed = 16, Clearance = 0.05, RunBounce = 0.04,
        Follow = 5, TurnFreq = 3, TurnDamp = 1, Lean = 0.12, Sway = 0.03, Twist = 0.02,
        ArmSwing = 0.08, ArmFreq = 3.5, ArmDamp = 0.9,
        HeadFreq = 4, HeadDamp = 1, SnapFreq = 8, SnapDamp = 1, HeadYawLimit = 1.6,
        Breath = 0, BreathAmount = 0, TwitchEvery = {5, 9}, TwitchSize = 0.12,
        StunCrouch = -0.3,
        States = {
            Chase = {Lean = 0.18, ArmsFwd = 0.35, ArmsOut = 0.05, HeadRoll = 0.22, HeadPitch = -0.05},
            Search = {Lean = 0.05, HeadRoll = 0.15},
        },
        Attack = {
            Windup = {Lean = 0.1, ArmsFwd = 0.9, ArmsOut = 0.25, HeadRoll = 0.4},
            Strike = {Lean = 0.4, ArmsFwd = 1.6, ArmsOut = -0.05, HeadRoll = 0.2, HeadPitch = -0.1},
            Recover = {Lean = 0.15, ArmsFwd = 1.1, HeadRoll = 0.3},
            Miss = {Lean = 0.35, ArmsFwd = 0.8, Crouch = -0.15, HeadRoll = 0.5},
        },
    },
    -- Cuatro patas largas (los brazos son las delanteras), andar de araña con fases
    -- propias pero coordinadas, temblor constante; cae del techo y vuelve a subir.
    ElTrepador = {
        StrideWalk = 1.6, StrideRun = 2.6, WalkDuty = 0.62, RunDuty = 0.48,
        WalkSpeed = 9, RunSpeed = 15.5, Clearance = 0.12, RunBounce = 0.06,
        Quadruped = true, Splay = 0.14,
        Follow = 5.5, TurnFreq = 2.6, TurnDamp = 0.6, Lean = 0.12, Sway = 0.05, Twist = 0.12,
        HeadFreq = 3.5, HeadDamp = 0.6, SnapFreq = 9, SnapDamp = 0.5, HeadYawLimit = 1.3,
        Breath = 1.4, BreathAmount = 0.035, TwitchEvery = {1, 3}, TwitchSize = 0.25,
        Tremor = 0.035, StunCrouch = -0.6,
        -- Fase de cada pata (en ciclos): pares diagonales con un desfase de araña.
        LegPhase = {ArmLeft = 0, ArmRight = 0.5, LegLeft = 0.58, LegRight = 0.08},
        States = {
            Patrol = {Crouch = -0.15, Spread = 0.1},
            Chase = {Lean = 0.15, Crouch = -0.4, Spread = 0.25, HeadPitch = 0.2},
            Flee = {Crouch = -0.3, Spread = 0.3},
            Stunned = {Crouch = -0.2, Spread = 0.45},
        },
        Attack = {
            Windup = {Lean = -0.4, ArmsFwd = 0.9, ArmsOut = 0.7, Crouch = -0.5, Spread = 0.4, HeadPitch = 0.3},
            Strike = {Lean = 0.5, ArmsFwd = 1.5, ArmsOut = 0.1, Crouch = -0.15, Spread = 0.2},
            Recover = {Lean = 0.15, ArmsFwd = 0.4, ArmsOut = 0.3, Crouch = -0.3, Spread = 0.3},
            Miss = {Lean = 0.4, ArmsFwd = 0.3, ArmsOut = 0.5, Crouch = -0.55, Spread = 0.5},
        },
    },
    -- Gigante acorazado: pasos pesados con impacto, cadera que se hunde, peso que
    -- pasa de una pierna a la otra, brazos que cuelgan con retraso, placas que se
    -- acomodan y respiración honda. Gira y arranca despacio.
    ElColoso = {
        StrideWalk = 1.7, StrideRun = 2.4, WalkDuty = 0.68, RunDuty = 0.55,
        WalkSpeed = 7, RunSpeed = 14, Clearance = 0.06, RunBounce = 0.02,
        ImpactDip = 0.32, Heavy = true,
        Follow = 3.2, TurnFreq = 0.9, TurnDamp = 0.8, AccelLean = 0.02, Bank = 0.02,
        Lean = 0.18, Sway = 0.28, Twist = 0.1,
        ArmSwing = 0.22, ArmFreq = 1.1, ArmDamp = 0.45,
        HeadFreq = 0.8, HeadDamp = 0.9, SnapFreq = 2, SnapDamp = 0.8, HeadYawLimit = 0.7,
        Breath = 3.4, BreathAmount = 0.09, TwitchEvery = {4, 9}, TwitchSize = 0.1,
        StunCrouch = -0.9,
        States = {
            Chase = {Lean = 0.22, Crouch = -0.3, ArmsOut = 0.12, HeadPitch = -0.08},
            Stunned = {Lean = 0.35, ArmsOut = 0.15, HeadPitch = -0.4},
        },
        Attack = {
            -- Aplastamiento: los dos brazos arriba, después abajo con todo el peso.
            Windup = {Lean = -0.3, ArmsFwd = 2.7, ArmsOut = 0.25, Crouch = 0.1, HeadPitch = 0.3},
            Strike = {Lean = 0.6, ArmsFwd = 0.6, ArmsOut = 0.05, Crouch = -0.9, HeadPitch = -0.2},
            Recover = {Lean = 0.35, ArmsFwd = 0.5, Crouch = -0.5},
            Miss = {Lean = 0.65, ArmsFwd = 0.35, ArmsOut = 0.2, Crouch = -1.1, HeadPitch = -0.3},
        },
    },
}

-- Completa cada estilo con los valores por defecto (también las tablas de poses).
local function merge(base, override)
    local result = {}
    for key, value in pairs(base) do
        result[key] = value
    end
    for key, value in pairs(override) do
        if type(value) == "table" and type(base[key]) == "table" and (key == "States" or key == "Attack") then
            local nested = {}
            for name, pose in pairs(base[key]) do
                nested[name] = pose
            end
            for name, pose in pairs(value) do
                nested[name] = pose
            end
            result[key] = nested
        else
            result[key] = value
        end
    end
    return result
end

local cache = {}

function CreatureStyles.Get(kind)
    if not cache[kind] then
        cache[kind] = merge(DEFAULT, STYLES[kind] or {})
    end
    return cache[kind]
end

return CreatureStyles
