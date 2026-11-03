-- NOCTURNA: único punto de entrada del servidor. Los remotos se crean antes que nada
-- y cada servicio arranca una sola vez, en un orden fijo.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

-- El servidor decide cuándo y dónde aparece cada personaje.
Players.CharacterAutoLoads = false
Remotes.Setup()

local SERVICES = {
    require(script.Parent.Analytics.Analytics),
    require(script.Parent.Security.AntiCheat),
    require(script.Parent.Data.ProgressionService),
    require(script.Parent.Data.HealthService),
    require(script.Parent.Data.StaminaService),
    require(script.Parent.Data.FlashlightService),
    require(script.Parent.Inventory.InventoryService),
    require(script.Parent.AI.NoiseService),
    require(script.Parent.World.WorldService),
    require(script.Parent.World.InteractionService),
    require(script.Parent.World.HidingService),
    require(script.Parent.Monsters.MonsterService),
    require(script.Parent.Story.StoryService),
    require(script.Parent.Story.EndingService),
    require(script.Parent.Multiplayer.LobbyService),
    require(script.Parent.Multiplayer.MatchService),
    require(script.Parent.Phases.TerrorDirector),
    require(script.Parent.Admin.AdminService),
}

for _, service in ipairs(SERVICES) do
    service.Start()
end

print("[NOCTURNA] Servidor iniciado.")
