-- Historia y contenido jugable de los cinco capítulos.
-- Tipos de objetivo: Reach, Collect, Activate, Unlock y Read.

local Chapters = {}

Chapters.Prologue = {
    "Hace tres años, mi hermana Alma desapareció.",
    "La Fundación Leteo habló de un accidente. Nos dieron un cajón cerrado y un certificado.",
    "Anoche, la radio vieja de casa se encendió sola.",
    "Era su voz. Decía lo mismo que me decía de chicos, cuando se cortaba la luz:",
    "«Contá hasta cinco conmigo. A los cinco, la oscuridad se va.»",
}

Chapters[1] = {
    Name = "El Descenso",
    Count = "Uno",
    Description = "La señal viene de abajo de la vieja sede de la Fundación Leteo.",
    Theme = "Tunnels",
    Monster = "ElOyente",
    Monsters = {"ElOyente"},
    Intro = {
        {Speaker = "Vos", Text = "La entrada se cerró detrás de nosotros. No hay señal."},
        {Speaker = "Radio", Text = "...contá... hasta... cinco..."},
        {Speaker = "Vos", Text = "Es ella. Viene de más abajo. Tengo que encontrar cómo bajar."},
    },
    Outro = {
        {Speaker = "Vos", Text = "El ascensor funciona. No sé qué era esa cosa, pero nos estuvo escuchando todo el tiempo."},
        {Speaker = "Radio", Text = "...uno..."},
    },
    Objectives = {
        {
            Id = "C1_ENTRY", Type = "Reach", Target = "ENTRY_HALL",
            Name = "Cruzá el vestíbulo de la instalación",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Sin energía el ascensor no sirve. El generador necesita fusibles."},
                },
                Horror = "DISTANT_SOUND",
            },
        },
        {
            Id = "C1_FUSES", Type = "Collect", Target = "Fuse", Count = 3,
            Name = "Reuní 3 fusibles",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Con esto alcanza. Encender el generador va a hacer ruido. Mucho ruido."},
                },
            },
        },
        {
            Id = "C1_POWER", Type = "Activate", Target = "GEN_MAIN",
            Name = "Restablecé la energía en el generador",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Radio", Text = "...no le hables... no te ve... te escucha..."},
                },
                Horror = "LIGHTS_FLICKER",
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
        Exit = {Id = "ELEVATOR", Prompt = "Activar ascensor", Hold = 2, RequiresFlag = "POWER", DeniedText = "No hay energía."},
        Features = {
            {Kind = "Generator", Id = "GEN_MAIN", Fuses = 3, Flag = "POWER", Label = "Generador principal"},
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
    Intro = {
        {Speaker = "Vos", Text = "Oficinas. Consultorios. Como si esto hubiera sido un hospital."},
        {Speaker = "Alma", Text = "¿Hola? ¿Estás ahí? Vení..."},
        {Speaker = "Vos", Text = "No. La carta decía que no respondiera. Esa voz no puede ser real."},
    },
    Outro = {
        {Speaker = "Vos", Text = "Si me llama de nuevo, le voy a preguntar cuánto falta para los cinco."},
        {Speaker = "Radio", Text = "...dos..."},
    },
    Objectives = {
        {
            Id = "C2_RADIO", Type = "Collect", Target = "Radio",
            Name = "Encontrá una radio portátil",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Tiene una grabación a medias. Necesito un terminal para escucharla."},
                },
            },
        },
        {
            Id = "C2_RECORDING", Type = "Activate", Target = "TERM_RECORD",
            Name = "Escuchá la grabación en el terminal",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Dra. Vega", Text = "Si alguien escucha esto: lo que sacamos de los pacientes no se destruyó."},
                    {Speaker = "Dra. Vega", Text = "Aprendió a hablar. Dejé mi tarjeta en el consultorio. Bajen por investigación. No respondan."},
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
        Features = {
            {
                Kind = "Terminal", Id = "TERM_RECORD", Prompt = "Escuchar grabación", Hold = 2.5,
                RequiredItem = "Radio", KeepItem = true, Label = "Terminal de audio",
                DeniedText = "Necesitás la radio para reproducirla.",
            },
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
    Description = "La instalación esconde algo que sigue vivo.",
    Theme = "Organism",
    Monster = "ElTrepador",
    Monsters = {"ElTrepador"},
    Reinforcements = {{Monster = "ElOyente", AfterObjective = "C3_LAB", MinPlayers = 2}},
    Intro = {
        {Speaker = "Vos", Text = "Las paredes están cambiando. Esto respira."},
        {Speaker = "Radio", Text = "...mirá... para... arriba..."},
        {Speaker = "Vos", Text = "Esto no es una instalación abandonada. Hay que llegar al laboratorio y purgar el sector."},
    },
    Outro = {
        {Speaker = "Vos", Text = "Era tejido. Tejido hecho de lo que le sacaron a la gente."},
        {Speaker = "Radio", Text = "...tres..."},
    },
    Objectives = {
        {
            Id = "C3_SAMPLE", Type = "Collect", Target = "Sample", Count = 3,
            Name = "Recogé 3 muestras del organismo",
        },
        {
            Id = "C3_KEY", Type = "Collect", Target = "Keycard",
            Name = "Encontrá la tarjeta del laboratorio",
        },
        {
            Id = "C3_LAB", Type = "Unlock", Target = "LAB_DOOR",
            Name = "Abrí el laboratorio central",
        },
        {
            Id = "C3_ANALYZE", Type = "Activate", Target = "TERM_LAB",
            Name = "Analizá las muestras en el laboratorio",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Dra. Vega", Text = "Secuencia de purga disponible. Cierren las dos válvulas del sector."},
                },
            },
        },
        {
            Id = "C3_VALVES", Type = "Activate", Target = "VALVE", Count = 2,
            Name = "Cerrá las 2 válvulas de contención",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "¡Está sellando el sector! ¡Corran hacia la salida!"},
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
                Id = "LAB", Door = {Id = "LAB_DOOR", RequiredItem = "Keycard", Amount = 1, Label = "Laboratorio central"},
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
            {Kind = "Valve", Id = "VALVE_A", Group = "VALVE", Prompt = "Cerrar válvula", Hold = 2.5, RequiresObjective = "C3_ANALYZE", DeniedText = "La válvula está trabada desde el laboratorio."},
            {Kind = "Valve", Id = "VALVE_B", Group = "VALVE", Prompt = "Cerrar válvula", Hold = 2.5, RequiresObjective = "C3_ANALYZE", DeniedText = "La válvula está trabada desde el laboratorio."},
        },
        Items = {{Item = "Sample", Count = 3}, {Item = "Keycard", Count = 1}, {Item = "Battery", Count = 4}, {Item = "Medkit", Count = 2}},
        Documents = {"DOC_3A", "DOC_3B", "DOC_3C"},
        Hides = 7,
        Doors = 6,
    },
}

Chapters[4] = {
    Name = "Lo que no debía existir",
    Count = "Cuatro",
    Description = "Lo que estaban creando nunca fue una cura.",
    Theme = "Archive",
    Monster = "ElColoso",
    Monsters = {"ElColoso"},
    Intro = {
        {Speaker = "Vos", Text = "El archivo de la Fundación. Si Alma dejó algo, está acá."},
        {Speaker = "Radio", Text = "...no vengas... no... vengas..."},
        {Speaker = "Vos", Text = "El piso tiembla. Hay algo muy grande caminando abajo."},
    },
    Outro = {
        {Speaker = "Vos", Text = "No la encerraron. Entró sola. Para que nada de esto saliera."},
        {Speaker = "Radio", Text = "...cuatro..."},
    },
    Objectives = {
        {
            Id = "C4_FILES", Type = "Read", Target = "ARCHIVE", Count = 3,
            Name = "Leé los 3 expedientes del archivo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "No estaban intentando curar a nadie. El Núcleo necesita energía para abrirse."},
                    {Speaker = "Vos", Text = "Los generadores auxiliares no tienen fusibles. Hay que buscarlos."},
                },
            },
        },
        {
            Id = "C4_FUSES", Type = "Collect", Target = "Fuse", Count = 4,
            Name = "Reuní 4 fusibles para los generadores",
        },
        {
            Id = "C4_GENERATORS", Type = "Activate", Target = "GENERATOR", Count = 2,
            Name = "Encendé los 2 generadores auxiliares",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Vos", Text = "Se abrió el acceso al Núcleo. Y eso de ahí abajo nos escuchó."},
                },
                Horror = "QUAKE",
            },
        },
        {
            Id = "C4_CORE", Type = "Reach", Target = "CORE_ROOM",
            Name = "Llegá a la sala del Núcleo",
        },
        {
            Id = "C4_DESTROY", Type = "Activate", Target = "CORE_PANEL",
            Name = "Desactivá la contención del Núcleo",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Alma", Text = "...cuatro. Falta uno. Vení. Por favor, vení."},
                    {Speaker = "Vos", Text = "¡Esa sí es ella! ¡Hay un acceso más abajo! ¡Corran!"},
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
                Door = {Id = "CORE_DOOR", RequiresFlag = "CORE_POWER", Label = "Acceso al Núcleo", DeniedText = "El acceso no tiene energía."},
                Features = {
                    {Kind = "Core", Id = "CORE_PANEL", Prompt = "Desactivar contención", Hold = 6, Label = "Panel del Núcleo"},
                },
            },
        },
        Features = {
            {Kind = "Generator", Id = "GEN_A", Group = "GENERATOR", Fuses = 2, CountFlag = {Name = "CORE_POWER", Needed = 2}, Label = "Generador auxiliar A"},
            {Kind = "Generator", Id = "GEN_B", Group = "GENERATOR", Fuses = 2, CountFlag = {Name = "CORE_POWER", Needed = 2}, Label = "Generador auxiliar B"},
        },
        Items = {{Item = "Fuse", Count = 4}, {Item = "Battery", Count = 4}, {Item = "Medkit", Count = 2}},
        Documents = {"DOC_4A", "DOC_4B", "DOC_4C"},
        DocumentGroup = "ARCHIVE",
        Hides = 7,
        Doors = 8,
    },
}

Chapters[5] = {
    Name = "Ella",
    Count = "Cinco",
    Description = "La verdad sobre tu hermana está al final.",
    Theme = "Memory",
    Monster = "ElQuieto",
    Monsters = {"ElQuieto"},
    Reinforcements = {{Monster = "ElImitador", AfterObjective = "C5_SHARDS", MinPlayers = 1}},
    Intro = {
        {Speaker = "Vos", Text = "No puede ser. Esta es nuestra casa. El empapelado, el pasillo, todo."},
        {Speaker = "Alma", Text = "Sé que estás ahí."},
        {Speaker = "Vos", Text = "Hay alguien parado en el fondo. No se mueve. No le saques la luz de encima."},
    },
    Objectives = {
        {
            Id = "C5_SHARDS", Type = "Collect", Target = "MemoryShard", Count = 3,
            Name = "Reuní los 3 fragmentos de la foto",
            OnComplete = {
                Dialogue = {
                    {Speaker = "Alma", Text = "Ya casi... ¿cuánto falta para los cinco?"},
                },
            },
        },
        {
            Id = "C5_DOOR", Type = "Unlock", Target = "LAST_DOOR",
            Name = "Abrí la puerta del cuarto de Alma",
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
            Door = {Id = "LAST_DOOR", RequiredItem = "MemoryShard", Amount = 3, Label = "El cuarto de Alma"},
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
            "Contás juntos. Uno. Dos. Tres. Cuatro.",
            "Cinco.",
            "La oscuridad se va. Se lleva todo lo que vivía abajo. Se la lleva a ella.",
            "Afuera está amaneciendo. Vas a seguir contando su historia, para que alguien la recuerde.",
        },
    },
    Rescue = {
        Title = "Desconocidos",
        Option = "Sacarla del Núcleo",
        Description = "Llevártela con vos, aunque no quede nada de lo que fue.",
        Lines = {
            "Desconectás a Alma del Núcleo. El Organismo grita con mil voces.",
            "La cargás escaleras arriba mientras la instalación se sella detrás de ustedes.",
            "Tres meses después, ella toma mate en la cocina de casa y te sonríe, educada.",
            "—Disculpá —te dice—. Me dijeron que somos familia. ¿Cómo era yo?",
            "Abajo, sin ancla, algo empieza a despertarse.",
            "Le acercás una silla. —Vas a ver —le decís—. Es una historia larga.",
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
