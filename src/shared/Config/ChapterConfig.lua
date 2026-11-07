-- Historia y contenido jugable de los cinco capítulos.
-- Tipos de objetivo: Reach, Collect, Activate, Unlock y Read.
--
-- Voces: "Vos" (quien juega), "Radio" (la cuenta entre estática: la Alma real,
-- que sólo puede contar), "Alma" (la voz que guía por la radio... y no es ella)
-- y "Dra. Vega" (grabaciones). Radio = true suma estática a la línea.
--
-- Pruebas (Kind = "Puzzle"): Wires, Breakers, Valves, Keypad, Power, Simon,
-- Memory y Levers. Cada capítulo combina tipos distintos. Una puerta con
-- Gate = true es una compuerta que se abre sola, con cinemática, cuando el
-- grupo activa su RequiresFlag.

local Chapters = {}

Chapters.Prologue = {
    "Hace tres años enterramos a mi hermana Alma. El cajón vino sellado.",
    "La Fundación Leteo habló de un accidente. Nunca nos dejaron verla.",
    "Anoche, a las 3:15, la radio vieja de casa se prendió sola.",
    "Era su voz: «Contá hasta cinco conmigo. A los cinco, la oscuridad se va.»",
    "Y después, otra cosa: «No me enterraron a mí. Bajá a buscarme.»",
    "Esa misma noche bajamos a la vieja sede de Leteo. No le avisamos a nadie.",
}

Chapters[1] = {
    Name = "El Descenso",
    Count = "Uno",
    Description = "La señal de la radio viene de abajo de la vieja sede de la Fundación Leteo.",
    Theme = "Tunnels",
    Monster = "ElOyente",
    Monsters = {"ElOyente"},
    Puzzles = {"Breakers", "Wires"},
    Intro = {
        {Speaker = "Vos", Text = "La reja se cerró sola detrás de nosotros. Ni una raya de señal."},
        {Speaker = "Alma", Radio = true, Text = "Viniste. Sabía que ibas a venir. El ascensor de servicio baja hasta donde estoy."},
        {Speaker = "Vos", Text = "Tres años llorándote, Alma. Y ahora me hablás por una radio."},
    },
    Outro = {
        {Speaker = "Vos", Text = "Esa cosa del túnel no ve. Escucha. Y nos escuchó todo el tiempo."},
        {Speaker = "Radio", Text = "...uno..."},
    },
    Objectives = {
        {
            Id = "C1_ENTRY", Type = "Reach", Target = "ENTRY_HALL",
            Name = "Cruzá el vestíbulo de la instalación",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Alma", Radio = true, Text = "El ascensor no tiene energía. El generador está muerto: buscá fusibles."},
                },
                Horror = "DISTANT_SOUND",
            },
        },
        {
            Id = "C1_FUSES", Type = "Collect", Target = "Fuse", Count = 3,
            Name = "Reuní 3 fusibles",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Con esto alcanza. Arrancar el generador va a hacer ruido. Mucho ruido."},
                },
            },
        },
        {
            Id = "C1_POWER", Type = "Activate", Target = "GEN_MAIN",
            Name = "Restablecé la energía en el generador",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Radio", Text = "...no hagas ruido... te escucha..."},
                    {Speaker = "Alma", Radio = true, Text = "Ahora el tablero. Subí las térmicas como quieras, el orden no importa."},
                },
                Horror = "LIGHTS_FLICKER",
            },
        },
        {
            Id = "C1_BREAKERS", Type = "Activate", Target = "BREAKERS_C1",
            Name = "Rearmá el tablero de disyuntores",
            Hint = "La bitácora de mantenimiento anota el orden.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "El orden sí importaba. Tenía razón la bitácora, no la voz de la radio."},
                },
            },
        },
        {
            Id = "C1_WIRES", Type = "Activate", Target = "WIRES_C1",
            Name = "Empalmá los cables del ascensor",
            Hint = "Cada cable va al borne de su color.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "¡La compuerta del ascensor se abre! Vamos, antes de que esa cosa vuelva."},
                },
            },
        },
        {
            Id = "C1_ELEVATOR", Type = "Activate", Target = "ELEVATOR",
            Name = "Activá el ascensor de servicio",
        },
    },
    Layout = {
        Width = 5, Depth = 5, LoopChance = 0.16, NarrowChance = 0.3,
        Zones = {{Id = "ENTRY_HALL", PathFraction = 0.3}},
        Exit = {
            Id = "ELEVATOR", Prompt = "Activar ascensor", Hold = 2, RequiresFlag = "POWER", DeniedText = "No hay energía.",
            Door = {Id = "ELEVATOR_GATE", Gate = true, RequiresFlag = "LIFT_POWER", Label = "Compuerta del ascensor", DeniedText = "La compuerta no tiene corriente."},
        },
        Features = {
            {Kind = "Generator", Id = "GEN_MAIN", Fuses = 3, Flag = "POWER", Label = "Generador principal"},
            {
                Kind = "Puzzle", Puzzle = "Breakers", Id = "BREAKERS_C1", Sequence = {3, 1, 4, 2},
                Prompt = "Rearmar tablero", Label = "Tablero de disyuntores",
                RequiresFlag = "POWER", DeniedText = "El tablero no tiene corriente. Primero el generador.",
                Clue = {Document = "DOC_1B", Hint = "La bitácora de mantenimiento anota el orden."},
            },
            {
                Kind = "Puzzle", Puzzle = "Wires", Id = "WIRES_C1", Flag = "LIFT_POWER",
                Prompt = "Empalmar cables", Label = "Caja de empalmes del ascensor",
                RequiresObjective = "C1_BREAKERS", DeniedText = "Sin el tablero rearmado, los cables no tienen corriente.",
            },
        },
        Items = {{Item = "Fuse", Count = 3}, {Item = "Battery", Count = 3}, {Item = "Medkit", Count = 1}},
        Documents = {"DOC_1A", "DOC_1B", "DOC_1C"},
        Hides = 5,
        Doors = 5,
    },
}

Chapters[2] = {
    Name = "Los que escuchan",
    Count = "Dos",
    Description = "Algo aprendió a hablar con las voces de los que ya no están.",
    Theme = "Offices",
    Monster = "ElImitador",
    Monsters = {"ElImitador"},
    Puzzles = {"Keypad", "Simon"},
    Intro = {
        {Speaker = "Vos", Text = "Consultorios, camillas, sillas con correas. Esto era un hospital."},
        {Speaker = "Alma", Radio = true, Text = "Buscá una radio portátil. Vega dejó una grabación que te va a servir."},
        {Speaker = "Vos", Text = "Alma, ¿cuánto falta para los cinco? ...¿Alma? No contesta."},
    },
    Outro = {
        {Speaker = "Vos", Text = "Vega dijo que no confiemos en la radio. Entonces... ¿quién nos viene guiando?"},
        {Speaker = "Radio", Text = "...dos..."},
    },
    Objectives = {
        {
            Id = "C2_RADIO", Type = "Collect", Target = "Radio",
            Name = "Encontrá una radio portátil",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "La grabación está en el consultorio de Vega. Tiene clave... y acá todos anotan las claves en las paredes."},
                },
            },
        },
        {
            Id = "C2_CODE", Type = "Activate", Target = "KEYPAD_C2",
            Name = "Abrí el consultorio de la Dra. Vega",
            Hint = "La clave está pintada en una pared. Uno lee, otro marca.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Adentro hay un terminal de audio. Para reproducir la grabación pide repetir una señal."},
                },
            },
        },
        {
            Id = "C2_RECORDING", Type = "Activate", Target = "TERM_RECORD",
            Name = "Sintonizá la grabación de la Dra. Vega",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Dra. Vega", Text = "Si alguien escucha esto: lo que les sacamos a los pacientes no se destruyó. Aprendió a hablar."},
                    {Speaker = "Dra. Vega", Text = "No respondan a voces conocidas. Y no confíen en la radio. Mi tarjeta abre investigación."},
                },
                Horror = "FALSE_ALARM",
            },
        },
        {
            Id = "C2_KEYCARD", Type = "Collect", Target = "Keycard",
            Name = "Encontrá la tarjeta de la Dra. Vega",
        },
        {
            Id = "C2_DOOR", Type = "Unlock", Target = "RESEARCH_DOOR",
            Name = "Abrí la puerta del sector de investigación",
        },
        {
            Id = "C2_EXIT", Type = "Activate", Target = "RESEARCH_LIFT",
            Name = "Bajá al sector de investigación",
        },
    },
    Layout = {
        Width = 6, Depth = 5, LoopChance = 0.2, NarrowChance = 0.3,
        Exit = {
            Id = "RESEARCH_LIFT", Prompt = "Bajar", Hold = 1.5,
            Door = {Id = "RESEARCH_DOOR", RequiredItem = "Keycard", Amount = 1, Label = "Sector de investigación"},
        },
        LockedRooms = {
            {
                Id = "VEGA_OFFICE",
                Door = {Id = "VEGA_GATE", Gate = true, RequiresFlag = "VEGA_OPEN", Label = "Consultorio de la Dra. Vega", DeniedText = "Cerrado con clave."},
                Features = {
                    {
                        Kind = "Puzzle", Puzzle = "Simon", Id = "TERM_RECORD",
                        Prompt = "Sintonizar grabación", Label = "Terminal de audio",
                        RequiredItem = "Radio", DeniedText = "Necesitás la radio para reproducirla.",
                    },
                },
            },
        },
        Features = {
            {
                Kind = "Puzzle", Puzzle = "Keypad", Id = "KEYPAD_C2", Flag = "VEGA_OPEN",
                Prompt = "Marcar clave", Label = "Panel de seguridad del consultorio",
                Clue = {Hint = "La clave está pintada en alguna pared del sector."},
            },
            {Kind = "Clue", Id = "CLUE_C2", For = "KEYPAD_C2", Label = "Números pintados en la pared"},
        },
        Items = {{Item = "Radio", Count = 1}, {Item = "Keycard", Count = 1}, {Item = "Battery", Count = 3}, {Item = "Medkit", Count = 1}},
        Documents = {"DOC_2A", "DOC_2B", "DOC_2C"},
        Hides = 6,
        Doors = 6,
    },
}

Chapters[3] = {
    Name = "El Organismo",
    Count = "Tres",
    Description = "La instalación esconde algo que sigue vivo. Y tiene hambre.",
    Theme = "Organism",
    Monster = "ElTrepador",
    Monsters = {"ElTrepador"},
    Puzzles = {"Valves", "Levers"},
    Reinforcements = {{Monster = "ElOyente", AfterObjective = "C3_PRESSURE", MinPlayers = 2}},
    Intro = {
        {Speaker = "Vos", Text = "Las paredes laten. Esto no es una instalación: es algo vivo."},
        {Speaker = "Radio", Text = "...mirá... para... arriba..."},
        {Speaker = "Alma", Radio = true, Text = "No mires arriba. Mirá el piso y seguí derecho. Te espero en el laboratorio."},
    },
    Outro = {
        {Speaker = "Vos", Text = "Era tejido hecho con lo que le sacaron a la gente. Y hablaba con la voz de Alma."},
        {Speaker = "Radio", Text = "...tres..."},
    },
    Objectives = {
        {
            Id = "C3_SAMPLE", Type = "Collect", Target = "Sample", Count = 3,
            Name = "Recogé 3 muestras del organismo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "El laboratorio está sellado. Hay que igualar la presión de los tanques para abrirlo."},
                },
            },
        },
        {
            Id = "C3_PRESSURE", Type = "Activate", Target = "VALVES_C3",
            Name = "Equilibrá la presión de los tanques",
            Hint = "Los tres manómetros tienen que quedar en la marca verde.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "La presión se igualó. ¡El laboratorio se abre!"},
                },
            },
        },
        {
            Id = "C3_ANALYZE", Type = "Activate", Target = "TERM_LAB",
            Name = "Analizá las muestras en el laboratorio",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Dra. Vega", Text = "Secuencia de purga lista. Dos palancas, bajadas al mismo tiempo. Nunca una sola."},
                },
            },
        },
        {
            Id = "C3_PURGE", Type = "Activate", Target = "LEVERS_C3",
            Name = "Bajen las 2 palancas de purga a la vez",
            Hint = "En grupo: cuenten juntos. Solo: tenés unos segundos para correr a la otra.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "¡La purga está sellando el sector! ¡Corran a la salida!"},
                },
                Horror = "BLACKOUT",
            },
        },
        {
            Id = "C3_ESCAPE", Type = "Activate", Target = "ORGANISM_EXIT", TimeLimit = 150,
            Name = "¡Escapá antes de que el organismo selle el sector!",
        },
    },
    Layout = {
        Width = 6, Depth = 6, LoopChance = 0.2, NarrowChance = 0.35,
        Exit = {Id = "ORGANISM_EXIT", Prompt = "Escapar", Hold = 1},
        LockedRooms = {
            {
                Id = "LAB",
                Door = {Id = "LAB_GATE", Gate = true, RequiresFlag = "LAB_OPEN", Label = "Laboratorio central", DeniedText = "Sellado por presión."},
                Features = {
                    {
                        Kind = "Terminal", Id = "TERM_LAB", Prompt = "Analizar muestras", Hold = 3,
                        RequiredItem = "Sample", RequiredAmount = 3, Label = "Analizador",
                        DeniedText = "Faltan muestras.",
                    },
                },
            },
        },
        Features = {
            {
                Kind = "Puzzle", Puzzle = "Valves", Id = "VALVES_C3", Flag = "LAB_OPEN",
                Prompt = "Ajustar válvulas", Label = "Válvulas de los tanques",
            },
            {
                Kind = "Puzzle", Puzzle = "Levers", Id = "LEVER_C3_A", Link = "LEVERS_C3", Group = "LEVERS_C3", Lever = 1,
                Prompt = "Bajar palanca", Label = "Palanca de purga A",
                RequiresObjective = "C3_ANALYZE", DeniedText = "La purga está trabada desde el laboratorio.",
            },
            {
                Kind = "Puzzle", Puzzle = "Levers", Id = "LEVER_C3_B", Link = "LEVERS_C3", Group = "LEVERS_C3", Lever = 2,
                Prompt = "Bajar palanca", Label = "Palanca de purga B",
                RequiresObjective = "C3_ANALYZE", DeniedText = "La purga está trabada desde el laboratorio.",
            },
        },
        Items = {{Item = "Sample", Count = 3}, {Item = "Battery", Count = 4}, {Item = "Medkit", Count = 2}},
        Documents = {"DOC_3A", "DOC_3B", "DOC_3C"},
        Hides = 7,
        Doors = 6,
    },
}

Chapters[4] = {
    Name = "Lo que no debía existir",
    Count = "Cuatro",
    Description = "Lo que estaban fabricando nunca fue una cura.",
    Theme = "Archive",
    Monster = "ElColoso",
    Monsters = {"ElColoso"},
    Puzzles = {"Power", "Keypad"},
    Intro = {
        {Speaker = "Vos", Text = "El archivo de Leteo. Si hay una verdad, está en estos expedientes."},
        {Speaker = "Alma", Radio = true, Text = "No pierdas tiempo leyendo. Llevá la corriente al Núcleo y vení conmigo."},
        {Speaker = "Radio", Text = "...no... vengas..."},
    },
    Outro = {
        {Speaker = "Vos", Text = "No la encerraron. Entró sola, para que nada de esto subiera. Y contaba para guiarnos."},
        {Speaker = "Radio", Text = "...cuatro..."},
    },
    Objectives = {
        {
            Id = "C4_FILES", Type = "Read", Target = "ARCHIVE", Count = 3,
            Name = "Leé los 3 expedientes del archivo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "La voz de la radio no es Alma. Es el Organismo, usándola de carnada."},
                    {Speaker = "Vos", Text = "Necesita un ancla nueva: alguien con los mismos recuerdos que ella. Por eso me llamó a mí."},
                },
            },
        },
        {
            Id = "C4_ROUTE", Type = "Activate", Target = "ROUTE_C4",
            Name = "Llevá la corriente hasta el acceso al Núcleo",
            Hint = "Girá las piezas hasta unir la entrada con la salida.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Llegó la corriente. ¡Se abre el acceso al Núcleo! Y eso de abajo nos escuchó."},
                },
                Horror = "QUAKE",
            },
        },
        {
            Id = "C4_CORE", Type = "Reach", Target = "CORE_ROOM",
            Name = "Llegá a la sala del Núcleo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "La contención pide una clave. Alma la cambió por la hora del apagón: está en su carta."},
                },
            },
        },
        {
            Id = "C4_UNLOCK", Type = "Activate", Target = "CORE_LOCK",
            Name = "Ingresá la clave de la contención",
            Hint = "Alma la dejó en su última carta.",
        },
        {
            Id = "C4_DESTROY", Type = "Activate", Target = "CORE_PANEL",
            Name = "Desactivá la contención del Núcleo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Radio", Text = "...falta... uno... ahora sí... vení..."},
                    {Speaker = "Vos", Text = "¡Esa cuenta sí es ella! ¡Hay un acceso más abajo! ¡Corran!"},
                },
                Horror = "BLACKOUT",
                MonsterRage = true,
            },
        },
        {
            Id = "C4_ESCAPE", Type = "Activate", Target = "CORE_LIFT", TimeLimit = 120,
            Name = "¡Llegá al acceso inferior antes de que colapse!",
        },
    },
    Layout = {
        Width = 6, Depth = 6, LoopChance = 0.26, NarrowChance = 0.3,
        Exit = {Id = "CORE_LIFT", Prompt = "Descender", Hold = 1},
        LockedRooms = {
            {
                Id = "CORE_ROOM", Zone = "CORE_ROOM",
                Door = {Id = "CORE_GATE", Gate = true, RequiresFlag = "CORE_POWER", Label = "Acceso al Núcleo", DeniedText = "El acceso no tiene corriente."},
                Features = {
                    {
                        Kind = "Puzzle", Puzzle = "Keypad", Id = "CORE_LOCK", Code = "0315",
                        Prompt = "Marcar clave", Label = "Cerradura de la contención",
                        Clue = {Document = "DOC_4C", Hint = "Alma la dejó en su última carta."},
                    },
                    {
                        Kind = "Core", Id = "CORE_PANEL", Prompt = "Desactivar contención", Hold = 6, Label = "Panel del Núcleo",
                        RequiresObjective = "C4_UNLOCK", DeniedText = "La contención pide la clave primero.",
                    },
                },
            },
        },
        Features = {
            {
                Kind = "Puzzle", Puzzle = "Power", Id = "ROUTE_C4", Flag = "CORE_POWER",
                Prompt = "Redirigir corriente", Label = "Tablero de distribución",
            },
        },
        Items = {{Item = "Battery", Count = 4}, {Item = "Medkit", Count = 2}},
        Documents = {"DOC_4A", "DOC_4B", "DOC_4C"},
        DocumentGroup = "ARCHIVE",
        Hides = 7,
        Doors = 8,
    },
}

Chapters[5] = {
    Name = "Ella",
    Count = "Cinco",
    Description = "La verdad sobre tu hermana está al final. Y te está esperando.",
    Theme = "Memory",
    Monster = "ElQuieto",
    Monsters = {"ElQuieto"},
    Puzzles = {"Memory", "Levers"},
    Reinforcements = {{Monster = "ElImitador", AfterObjective = "C5_SHARDS", MinPlayers = 1}},
    Intro = {
        {Speaker = "Vos", Text = "No puede ser. Es nuestra casa. El empapelado, el pasillo, todo igual."},
        {Speaker = "Alma", Text = "Sé que estás ahí. Juntá los pedazos de la foto. Ya casi."},
        {Speaker = "Vos", Text = "Hay alguien parado al fondo. No se mueve. No le saquen la luz de encima."},
    },
    Objectives = {
        {
            Id = "C5_SHARDS", Type = "Collect", Target = "MemoryShard", Count = 3,
            Name = "Reuní los 3 fragmentos de la foto",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Alma", Text = "¿Cuánto falta para los cinco?"},
                    {Speaker = "Vos", Text = "Esa pregunta es nuestra. Ahora sí es ella."},
                },
            },
        },
        {
            Id = "C5_PHOTO", Type = "Activate", Target = "MEMORY_C5",
            Name = "Ordená los recuerdos de la caja de zapatos",
            Hint = "Encontrá los pares de fotos.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Somos nosotros, con la linterna de plástico. En los apagones prendíamos las dos lámparas juntos."},
                },
            },
        },
        {
            Id = "C5_DOOR", Type = "Activate", Target = "LAMPS_C5",
            Name = "Prendan las dos lámparas al mismo tiempo",
            Hint = "En grupo: cuenten hasta cinco y a la vez. Solo: corré de una a la otra.",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "La puerta del cuarto de Alma se abre sola. Como cuando éramos chicos."},
                },
            },
        },
        {
            Id = "C5_FIND", Type = "Reach", Target = "ALMA_ROOM",
            Name = "Encontrá a tu hermana",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Alma... Soy yo. Vine."},
                },
            },
        },
        {
            Id = "C5_END", Type = "Activate", Target = "ALMA",
            Name = "Descubrí la verdad",
        },
    },
    Layout = {
        Width = 5, Depth = 5, LoopChance = 0.22, NarrowChance = 0.25,
        Exit = {
            Id = "ALMA", Kind = "Sister", Prompt = "Tomarle la mano", Hold = 2, Zone = "ALMA_ROOM",
            Door = {Id = "LAST_GATE", Gate = true, RequiresFlag = "LAMPS_ON", Label = "El cuarto de Alma", DeniedText = "La puerta no se mueve."},
        },
        Features = {
            {
                Kind = "Puzzle", Puzzle = "Memory", Id = "MEMORY_C5",
                Prompt = "Ordenar fotos", Label = "Caja de zapatos",
                RequiredItem = "MemoryShard", RequiredAmount = 3, DeniedText = "Faltan pedazos de la foto.",
            },
            {
                Kind = "Puzzle", Puzzle = "Levers", Id = "LAMP_C5_A", Link = "LAMPS_C5", Group = "LAMPS_C5", Lever = 1, Flag = "LAMPS_ON",
                Prompt = "Prender lámpara", Label = "Interruptor de la lámpara del pasillo",
                RequiresObjective = "C5_PHOTO", DeniedText = "Todavía no. Falta ordenar la foto.",
            },
            {
                Kind = "Puzzle", Puzzle = "Levers", Id = "LAMP_C5_B", Link = "LAMPS_C5", Group = "LAMPS_C5", Lever = 2, Flag = "LAMPS_ON",
                Prompt = "Prender lámpara", Label = "Interruptor de la lámpara del living",
                RequiresObjective = "C5_PHOTO", DeniedText = "Todavía no. Falta ordenar la foto.",
            },
        },
        Items = {{Item = "MemoryShard", Count = 3}, {Item = "Battery", Count = 5}, {Item = "Medkit", Count = 2}},
        Documents = {"DOC_5A", "DOC_5B", "DOC_5C"},
        Mannequins = 8,
        Hides = 5,
        Doors = 4,
    },
}

Chapters.Endings = {
    Release = {
        Title = "A los cinco",
        Option = "Dejarla ir",
        Description = "Apagar el Núcleo. Todo termina, también ella.",
        Lines = {
            "Alma te mira sin saber quién sos. Pero te aprieta la mano igual.",
            "Sabés lo que hay que hacer. Ella también, en algún lugar.",
            "Cuentan juntos. Uno. Dos. Tres. Cuatro.",
            "Cinco.",
            "La oscuridad se va. Se lleva al Organismo, la voz que robó, y a ella.",
            "Afuera amanece. Vas a contar su historia, para que nadie la vuelva a usar de carnada.",
        },
    },
    Rescue = {
        Title = "Desconocidos",
        Option = "Sacarla del Núcleo",
        Description = "Llevártela con vos, aunque no quede nada de lo que fue.",
        Lines = {
            "Desconectás a Alma del Núcleo. El Organismo grita con mil voces. Una es la tuya.",
            "La cargás escaleras arriba mientras la instalación se sella detrás de ustedes.",
            "Tres meses después, ella toma mate en la cocina de casa y te sonríe, educada.",
            "—Disculpá —te dice—. Me dijeron que somos familia. ¿Cómo era yo?",
            "Esa noche, a las 3:15, la radio vieja de la cocina se prende sola.",
            "Le acercás una silla a Alma y apagás la radio. —Vas a ver —le decís—. Es una historia larga.",
        },
    },
    Remember = {
        Title = "El último recuerdo",
        Option = "Contarle todo",
        Description = "Leerle sus propias cartas y devolverle lo que le quitaron.",
        Lines = {
            "Sacás las cartas. Todas. Y empezás a leer en voz alta, como ella te pidió.",
            "La casa. La linterna de plástico. Mamá. El dibujo del sol. Los apagones.",
            "El Organismo se detiene a escuchar. Cada recuerdo contado deja de ser suyo.",
            "Alma parpadea. Te mira de verdad. —¿Cuánto falta para los cinco? —pregunta.",
            "—Ya está —le decís—. Llegamos.",
            "Afuera amanece. Ella es quien te toma de la mano ahora. —Contá vos esta vez.",
        },
    },
}

return Chapters
