return {
    [1] = {
        Name = "El Descenso",
        Description = "Entrá en la instalación y descubrí qué ocurrió.",
        Monster = "ElOyente",
        Dialogue = {
            "La entrada está detrás de nosotros.",
            "No hay señal. No hay nadie respondiendo.",
            "Tenemos que encontrar otra salida."
        },
        Objectives = {
            {Id = "C1_ENTRY", Name = "Encontrar la entrada"},
            {Id = "C1_POWER", Name = "Restablecer la energía"},
            {Id = "C1_ELEVATOR", Name = "Activar el ascensor"}
        }
    },

    [2] = {
        Name = "Los que escuchan",
        Description = "Algo está siguiendo cada sonido que hacés.",
        Monster = "ElImitador",
        Dialogue = {
            "¿Escuchaste eso?",
            "Esa voz no puede ser real.",
            "No respondas. No importa quién te llame."
        },
        Objectives = {
            {Id = "C2_RADIO", Name = "Encontrar la radio"},
            {Id = "C2_RECORDING", Name = "Escuchar la grabación"},
            {Id = "C2_EXIT", Name = "Llegar al sector de investigación"}
        }
    },

    [3] = {
        Name = "El Organismo",
        Description = "La instalación esconde algo que sigue vivo.",
        Monster = "ElTrepador",
        Dialogue = {
            "Las paredes están cambiando.",
            "Esto no es una instalación abandonada.",
            "Tenemos que llegar al laboratorio central."
        },
        Objectives = {
            {Id = "C3_SAMPLE", Name = "Recoger una muestra"},
            {Id = "C3_LAB", Name = "Abrir el laboratorio"},
            {Id = "C3_ESCAPE", Name = "Escapar del organismo"}
        }
    },

    [4] = {
        Name = "Lo que no debía existir",
        Description = "Descubrí qué estaban intentando crear.",
        Monster = "ElColoso",
        Dialogue = {
            "Encontré los archivos del proyecto.",
            "No estaban intentando curar a nadie.",
            "Tenemos que destruir el núcleo."
        },
        Objectives = {
            {Id = "C4_FILES", Name = "Encontrar los archivos"},
            {Id = "C4_CORE", Name = "Localizar el núcleo"},
            {Id = "C4_DESTROY", Name = "Desactivar el núcleo"}
        }
    },

    [5] = {
        Name = "Ella",
        Description = "La verdad sobre tu hermana está al final.",
        Monster = "ElQuieto",
        Dialogue = {
            "Sé que estás ahí.",
            "Después de todo este tiempo...",
            "No voy a dejarte atrás."
        },
        Objectives = {
            {Id = "C5_DOOR", Name = "Abrir la última puerta"},
            {Id = "C5_FIND", Name = "Encontrar a tu hermana"},
            {Id = "C5_END", Name = "Descubrir la verdad"}
        }
    }
}
