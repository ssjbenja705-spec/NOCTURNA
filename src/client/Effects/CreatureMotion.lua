-- Matemática de la animación procedural de las criaturas: resortes, ciclo del
-- paso, amplitud de la zancada según la velocidad real, fuerza de los pisotones
-- y la solución de dos huesos para las piernas con rodilla. Funciones puras, sin
-- tablas nuevas por cuadro (se usan muchas veces por cuadro en celulares).
local CreatureMotion = {}

local TAU = math.pi * 2
-- Paso máximo de integración de los resortes: estable aunque el cuadro sea largo.
local SPRING_STEP = 1 / 60
local MAX_SUBSTEPS = 16

function CreatureMotion.Approach(current, goal, rate, deltaTime)
    return current + (goal - current) * (1 - math.exp(-rate * deltaTime))
end

function CreatureMotion.Smoothstep(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

-- Ángulo en [-π, π].
function CreatureMotion.Wrap(angle)
    return (angle + math.pi) % TAU - math.pi
end

-- Resorte amortiguado: frequency en Hz, damping 1 = crítico (sin rebote),
-- menor que 1 = con rebote (peso, inercia). Devuelve posición y velocidad.
function CreatureMotion.Spring(position, velocity, goal, frequency, damping, deltaTime)
    local omega = TAU * frequency
    local steps = math.clamp(math.ceil(deltaTime / SPRING_STEP), 1, MAX_SUBSTEPS)
    local h = deltaTime / steps
    for _ = 1, steps do
        local acceleration = omega * omega * (goal - position) - 2 * damping * omega * velocity
        velocity += acceleration * h
        position += velocity * h
    end
    return position, velocity
end

-- Igual que Spring pero para ángulos: va por el camino corto.
function CreatureMotion.AngleSpring(angle, velocity, goal, frequency, damping, deltaTime)
    local unwrapped = angle + CreatureMotion.Wrap(goal - angle)
    local position, speed = CreatureMotion.Spring(angle, velocity, unwrapped, frequency, damping, deltaTime)
    return CreatureMotion.Wrap(position), speed
end

-- Un ciclo del paso para una pata. u en [0, 1); duty = fracción apoyada.
-- Devuelve s (+1 adelante, -1 atrás) y lift (0 apoyada, 1 en lo más alto).
-- Apoyada, el pie va hacia atrás a velocidad constante (no patina); en el aire
-- vuelve adelante con arranque y llegada suaves.
function CreatureMotion.Cycle(u, duty)
    u %= 1
    if u < duty then
        return 1 - 2 * u / duty, 0
    end
    local v = (u - duty) / (1 - duty)
    return -1 + 2 * (v * v * (3 - 2 * v)), math.sin(v * math.pi)
end

-- Amplitud (radianes desde la cadera) para que el pie apoyado recorra justo lo
-- que avanza el cuerpo: en un ciclo de `cycle` studs el pie apoya duty*cycle.
function CreatureMotion.StrideAmplitude(cycle, duty, length)
    if length <= 0 then
        return 0
    end
    return math.asin(math.clamp(cycle * duty / (2 * length), 0, 0.9))
end

-- Cuánto baja la cadera para que la pata inclinada siga tocando el piso.
function CreatureMotion.HipDrop(angle, length)
    return length * (1 - math.cos(angle))
end

-- Fuerza (0..1) del temblor de cámara por un pisotón a `distance` studs: fuerte
-- muy cerca, se apaga con suavidad y es cero desde `far`.
function CreatureMotion.StompPower(distance, near, far)
    near = near or 8
    far = far or 60
    if distance >= far then
        return 0
    end
    local alpha = 1 - math.clamp((distance - near) / (far - near), 0, 1)
    return alpha * alpha
end

-- Dos huesos (muslo y pantorrilla) que tienen que llegar a `reach` studs desde la
-- cadera. Devuelve cuánto adelantar el muslo y cuánto doblar la rodilla (rad).
function CreatureMotion.TwoBone(upper, lower, reach)
    reach = math.clamp(reach, math.abs(upper - lower) + 1e-3, upper + lower - 1e-3)
    local hip = math.acos(math.clamp((upper * upper + reach * reach - lower * lower) / (2 * upper * reach), -1, 1))
    local knee = math.pi - math.acos(math.clamp((upper * upper + lower * lower - reach * reach) / (2 * upper * lower), -1, 1))
    return hip, knee
end

return CreatureMotion
