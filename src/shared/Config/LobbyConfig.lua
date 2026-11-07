-- Lobby caminable: ascensores para armar grupos, viajes a servidores propios y donaciones.
return {
    -- Segundos con las puertas cerrándose antes de viajar.
    Countdown = 6,
    -- Si el viaje no se completa en este tiempo, el ascensor se vuelve a abrir.
    LaunchTimeout = 30,
    -- Cada cuánto se revisa quién está dentro de cada ascensor.
    ZoneCheckInterval = 0.25,
    -- Jugadores por servidor de lobby. No puede superar el máximo del lugar en Creator Hub.
    LobbyCapacity = 12,

    Teleport = {
        -- En false todas las partidas se juegan en el mismo servidor, como en Studio.
        Enabled = true,
        Attempts = 3,
        RetryDelay = 2,
        -- Lo que espera el servidor de la partida a que llegue todo el grupo.
        PartyWait = 45,
        -- Durante este tiempo quien se desconecta puede volver a su partida desde el lobby.
        RejoinHours = 3,
    },

    Donations = {
        RefreshInterval = 60,
        PromptDistance = 10,
    },
}
