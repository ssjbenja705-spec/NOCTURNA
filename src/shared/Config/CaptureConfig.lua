-- Captura cinemática, forcejeo (QTE) y contragolpe. Lo comparten el servidor (que
-- decide todo) y el cliente (que sólo muestra y manda las teclas).
--
-- Fases de una captura:
--   Grab      la criatura agarra al jugador, lo acomoda y arranca su animación.
--   Struggle  el jugador aprieta la secuencia en orden antes de que se acabe el tiempo.
--   Release   ganó: lo suelta, el jugador le pega y la criatura queda aturdida.
--   Fail      perdió: remate de la criatura y daño según la dificultad.
return {
    -- Teclas lógicas de la secuencia. El servidor sólo acepta estos nombres.
    Keys = {"Q", "E", "R", "F", "Space"},

    -- Cómo se muestra cada tecla en cada dispositivo, y su color (el mismo en
    -- todos lados, así el botón táctil y la secuencia se reconocen de un vistazo).
    Display = {
        Q = {Keyboard = "Q", Gamepad = "X", Touch = "1", Color = Color3.fromRGB(206, 64, 52)},
        E = {Keyboard = "E", Gamepad = "Y", Touch = "2", Color = Color3.fromRGB(214, 168, 62)},
        R = {Keyboard = "R", Gamepad = "B", Touch = "3", Color = Color3.fromRGB(96, 168, 110)},
        F = {Keyboard = "F", Gamepad = "RB", Touch = "4", Color = Color3.fromRGB(86, 140, 206)},
        Space = {Keyboard = "ESPACIO", Gamepad = "A", Touch = "5", Color = Color3.fromRGB(176, 104, 196)},
    },

    -- Tiempos del servidor (segundos).
    PullTime = 0.35,
    ReleaseTime = 0.5,
    FailTime = 1.1,
    -- Aturdimiento tras el contragolpe: exacto, medido por el servidor.
    StunTime = 5,
    RecoverTime = 1,
    -- Tras zafar (o tras el remate) nadie lo puede volver a agarrar enseguida.
    EscapeImmunity = 3,
    FailImmunity = 2.5,
    -- Entre dos teclas aceptadas: más rápido que esto no lo hace una mano.
    MinPressInterval = 0.06,
    -- Cuánto empuja el contragolpe al jugador hacia atrás.
    ShoveDistance = 1.5,

    -- Secuencia por dificultad: largo, tiempo y castigo por error (segundos).
    Difficulty = {
        Normal = {Length = 6, Time = 6, MistakeTime = 0.5},
        Pesadilla = {Length = 8, Time = 6, MistakeTime = 0.8},
    },

    -- Cada criatura agarra a su manera. Hold: dónde queda el jugador respecto de la
    -- criatura (adelante, de costado y cuánto lo levanta). Camera: encuadre de la
    -- víctima (Back detrás de ella, Side al costado, Up de altura, Bias hacia la
    -- cabeza de la criatura). Mouth: "Jaw" (boca que se abre: pieza propia),
    -- "Sealed" (boca tallada en la cabeza: no se abre) o nil (sin boca).
    Creatures = {
        ElOyente = {
            Verb = "te tiene pegado contra su cara",
            GrabTime = 1.3, ExtraLength = 0, ExtraTime = 0,
            Hold = {Forward = 2.2, Side = 0, Lift = 0.5, Pitch = 0},
            Camera = {Back = 3.2, Side = 2.2, Up = 1.2, Bias = 0.7, Fov = 60},
            Mouth = "Sealed",
        },
        ElImitador = {
            Verb = "abre la boca frente a vos",
            GrabTime = 1.4, ExtraLength = 1, ExtraTime = 0.5,
            Hold = {Forward = 2.3, Side = 0, Lift = 0.8, Pitch = 0},
            Camera = {Back = 2.6, Side = 1.7, Up = 0.9, Bias = 0.8, Fov = 55},
            Mouth = "Jaw",
        },
        ElQuieto = {
            Verb = "te aprieta el cuello con sus manos de maniquí",
            GrabTime = 1.2, ExtraLength = 1, ExtraTime = 0.5,
            Hold = {Forward = 2, Side = 0, Lift = 0, Pitch = 0},
            Camera = {Back = 3.4, Side = -2.4, Up = 1.4, Bias = 0.65, Fov = 62},
        },
        ElTrepador = {
            Verb = "te levanta desde arriba",
            GrabTime = 1.5, ExtraLength = 1, ExtraTime = 0.5,
            Hold = {Forward = 1.8, Side = 0, Lift = 2.4, Pitch = 0.35},
            Camera = {Back = 4, Side = 2.6, Up = -0.6, Bias = 0.6, Fov = 66},
        },
        ElColoso = {
            Verb = "te aplasta en su puño",
            GrabTime = 1.6, ExtraLength = 2, ExtraTime = 1,
            Hold = {Forward = 3.2, Side = 0, Lift = 2.2, Pitch = 0.1},
            Camera = {Back = 6, Side = 3.4, Up = 1, Bias = 0.6, Fov = 68},
        },
    },
}
