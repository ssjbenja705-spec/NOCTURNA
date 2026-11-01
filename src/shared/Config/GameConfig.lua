local Config = {}

Config.GameName = "NOCTURNA: EL ÚLTIMO RECUERDO"
Config.Version = "0.1.0"
Config.MaxPlayers = 4
Config.FirstPerson = true

Config.Player = {
    WalkSpeed = 10,
    SprintSpeed = 17,
    MaxStamina = 100,
    StaminaDrain = 22,
    StaminaRecovery = 16,
}

Config.Flashlight = {
    Enabled = true,
    Range = 32,
    Brightness = 2,
    BatterySeconds = 240,
}

Config.Monsters = {
    Oyente = {DisplayName = "El Oyente", DetectsSound = true},
    Imitador = {DisplayName = "El Imitador", CopiesVoices = true},
    Quieto = {DisplayName = "El Quieto", MovesWhenUnobserved = true},
    Trepador = {DisplayName = "El Trepador", WallMovement = true},
    Coloso = {DisplayName = "El Coloso", ChangesEnvironment = true},
}

Config.Chapters = {
    "El Descenso",
    "Los que escuchan",
    "El Organismo",
    "Lo que no debía existir",
    "Ella",
}

return Config
