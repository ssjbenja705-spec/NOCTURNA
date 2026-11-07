local Config = {}

Config.GameName = "NOCTURNA: EL ÚLTIMO RECUERDO"
Config.Version = "1.0.0"
Config.MaxPlayers = 4
Config.MinPlayers = 1
Config.FirstPerson = true

-- Equilibrio de velocidades (ver MonsterConfig): corriendo se deja atrás a
-- cualquier criatura (su persecución es el 75-90 % del sprint) y caminando no,
-- así que correr importa. El AIRE alcanza para unos 9 s de carrera.
Config.Player = {
    MaxHealth = 100,
    WalkSpeed = 11,
    SprintSpeed = 19,
    CrouchSpeed = 6,
    MaxStamina = 100,
    StaminaDrain = 11,
    StaminaRecovery = 14,
    ExhaustedRecovery = 8,
    ExhaustedUnlock = 25,
    -- Pausa antes de recuperar aire después de correr.
    RecoveryDelay = 0.6,
    FieldOfView = 78,
    SprintFieldOfView = 86,
}

Config.Flashlight = {
    Enabled = true,
    Range = 38,
    Brightness = 2.4,
    Angle = 62,
    BatterySeconds = 240,
    BatteryRecharge = 60,
    LowBattery = 15,
}

-- Radio (en studs) del ruido que oyen los monstruos.
Config.Noise = {
    Walk = 22,
    Sprint = 60,
    Crouch = 4,
    Door = 40,
    Item = 16,
    Machine = 70,
    Lifetime = 3,
}

Config.Match = {
    RespawnDelay = 6,
    LivesPerChapter = 3,
    LivesPerExtraPlayer = 1,
    FirstMonsterDelay = 25,
    SummaryDuration = 7,
    FailureAutoRetry = 25,
    EndingVoteDuration = 45,
    MaxDocuments = 15,
}

Config.Difficulties = {
    Normal = {
        DisplayName = "Normal",
        MonsterSpeed = 1,
        MonsterSenses = 1,
        MonsterDamage = 1,
        ExtraLives = 0,
        BatteryDrain = 1,
        ShowCompass = true,
    },
    Pesadilla = {
        DisplayName = "Pesadilla",
        -- Más cerca del sprint (hasta el 90 %), pero siempre se puede escapar.
        MonsterSpeed = 1.06,
        MonsterSenses = 1.15,
        MonsterDamage = 1.4,
        ExtraLives = -2,
        BatteryDrain = 1.4,
        ShowCompass = false,
    },
}
Config.DefaultDifficulty = "Normal"

Config.Map = {
    CellSize = 40,
    WallHeight = 13,
    WallThickness = 2,
    FloorThickness = 2,
    CorridorWidth = 10,
    OpeningHeight = 9,
    SlotInset = 6,
    LobbyOrigin = {X = 0, Y = 0, Z = -1200},
}

Config.Inventory = {
    MaxSlots = 8,
}

Config.Chapters = {
    "El Descenso",
    "Los que escuchan",
    "El Organismo",
    "Lo que no debía existir",
    "Ella",
}

return Config
