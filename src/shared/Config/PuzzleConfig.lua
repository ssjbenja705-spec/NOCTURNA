-- Pruebas interactivas: textos, colores y ajustes de cada tipo. Las respuestas
-- nunca viven acá: las genera y las valida el servidor.
local PuzzleConfig = {}

-- Jugadas por segundo que el servidor atiende de cada jugador.
PuzzleConfig.ActionsPerSecond = 10

-- Interface = false: la prueba se resuelve con los prompts del mapa, sin panel.
PuzzleConfig.Types = {
    Wires = {
        Title = "Caja de empalmes",
        Instructions = "Uní cada cable con el borne de su mismo color. Arrastralo, o tocá el cable y después el borne.",
        Interface = true,
    },
    Breakers = {
        Title = "Tablero de disyuntores",
        Instructions = "Subí las térmicas en el orden correcto. Si te equivocás, salta todo y hace ruido.",
        Interface = true,
    },
    Valves = {
        Title = "Válvulas de presión",
        Instructions = "Girá las válvulas hasta que los tres manómetros queden en la marca verde.",
        Interface = true,
    },
    Keypad = {
        Title = "Cerradura con clave",
        Instructions = "Ingresá el código de cuatro números.",
        Interface = true,
    },
    Power = {
        Title = "Tablero de distribución",
        Instructions = "Tocá cada pieza para girarla y llevá la corriente de la entrada a la salida.",
        Interface = true,
    },
    Simon = {
        Title = "Señal de acceso",
        Instructions = "Escuchá la señal y repetila en el mismo orden.",
        Interface = true,
    },
    Memory = {
        Title = "Recuerdos",
        Instructions = "Das vuelta dos fotos por vez. Encontrá todos los pares.",
        Interface = true,
    },
    Levers = {
        Title = "Palancas",
        Instructions = "Las dos palancas tienen que estar bajas al mismo tiempo.",
        Interface = false,
    },
}

-- Cables, en el orden en que se usan. La letra ayuda a quien no distingue colores.
PuzzleConfig.WireColors = {
    {Name = "Rojo", Letter = "R", Color = Color3.fromRGB(196, 52, 46)},
    {Name = "Azul", Letter = "A", Color = Color3.fromRGB(52, 104, 210)},
    {Name = "Amarillo", Letter = "Y", Color = Color3.fromRGB(226, 194, 52)},
    {Name = "Verde", Letter = "V", Color = Color3.fromRGB(58, 168, 82)},
    {Name = "Blanco", Letter = "B", Color = Color3.fromRGB(226, 226, 220)},
}

PuzzleConfig.Wires = {Count = 4}

PuzzleConfig.Breakers = {Count = 4}

-- Cada válvula sube un manómetro y baja otro. Effects[v][m] = cambio del manómetro m.
PuzzleConfig.Valves = {
    Count = 3,
    Max = 8,
    Target = 4,
    Scramble = 5,
    Names = {"A", "B", "C"},
    Effects = {
        {2, -1, 0},
        {0, 2, -1},
        {-1, 0, 2},
    },
}

-- Lockout: lo que espera quien se equivoca de clave la primera vez (después crece,
-- ver PuzzleConfig.Lockout).
PuzzleConfig.Keypad = {Length = 4, Lockout = 2.5}

-- Errores de cada jugador en cada prueba. Al juntar Strikes errores queda
-- bloqueado él solo (los demás siguen jugando) Base segundos; cada bloqueo nuevo
-- dura Growth veces más, hasta Max. Sin errores durante Forget segundos se olvida
-- todo. La clave, los disyuntores y los cables bloquean desde el primer error: así
-- no se pueden adivinar probando. El ruido del error suena, como mucho, una vez
-- cada PenaltyInterval segundos por prueba.
PuzzleConfig.Lockout = {
    Strikes = {Keypad = 1, Breakers = 1, Wires = 1, Default = 3},
    Base = {Keypad = PuzzleConfig.Keypad.Lockout, Default = 2},
    Growth = 2,
    Max = 60,
    Forget = 90,
    PenaltyInterval = 2,
}

-- Piezas del tablero: lados abiertos sin girar (1 norte, 2 este, 3 sur, 4 oeste).
-- Cada giro suma un lado en sentido horario.
PuzzleConfig.Power = {
    Columns = 4,
    Rows = 3,
    Pieces = {I = {1, 3}, L = {1, 2}, T = {1, 2, 3}},
}

PuzzleConfig.Simon = {
    Rounds = {3, 4, 5},
    Buttons = {
        {Name = "Rojo", Color = Color3.fromRGB(190, 48, 44)},
        {Name = "Verde", Color = Color3.fromRGB(52, 160, 78)},
        {Name = "Azul", Color = Color3.fromRGB(48, 96, 200)},
        {Name = "Amarillo", Color = Color3.fromRGB(220, 186, 50)},
    },
}

-- Las fotos de la caja de zapatos de Alma.
PuzzleConfig.Memory = {
    Pairs = 6,
    Symbols = {"LINTERNA", "SOL", "RADIO", "MATE", "CASA", "CINCO", "MAMÁ", "LLUVIA"},
}

-- Ventana para bajar las dos palancas: corta con compañeros, larga para quien juega
-- solo. Si el grupo no lo logra en TeamGrace segundos (alguien ausente, por ejemplo),
-- el mecanismo cede y pasa a la ventana larga: nadie queda trabado.
PuzzleConfig.Levers = {TeamWindow = 2, SoloWindow = 30, TeamGrace = 45, Hold = 1}

-- Cinemática al abrirse una compuerta o puerta por una prueba u objetivo.
PuzzleConfig.Cinematic = {Duration = 2.8, Range = 150}

return PuzzleConfig
