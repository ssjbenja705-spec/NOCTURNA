-- NOCTURNA: único punto de entrada del servidor. Los remotos se crean antes que nada
-- y cada servicio arranca una sola vez, en un orden fijo.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

-- El servidor decide cuándo y dónde aparece cada personaje.
Players.CharacterAutoLoads = false
Remotes.Setup()

local SERVICES = {
    script.Parent.Analytics.Analytics,
    script.Parent.Security.AntiCheat,
    script.Parent.Data.ProgressionService,
    script.Parent.Data.HealthService,
    script.Parent.Data.StaminaService,
    script.Parent.Data.FlashlightService,
    script.Parent.Inventory.InventoryService,
    script.Parent.AI.NoiseService,
    script.Parent.World.WorldService,
    script.Parent.World.MapService,
    script.Parent.World.InteractionService,
    script.Parent.World.HidingService,
    script.Parent.Monsters.MonsterService,
    script.Parent.Story.StoryService,
    script.Parent.Story.EndingService,
    script.Parent.Multiplayer.LobbyService,
    script.Parent.Multiplayer.MatchService,
    script.Parent.Lobby.MatchTeleport,
    script.Parent.Lobby.MatchServerService,
    script.Parent.Lobby.QueueService,
    script.Parent.Lobby.DonationService,
    script.Parent.Phases.TerrorDirector,
    script.Parent.Admin.AdminService,
}

-- Un servicio que falla no frena a los demás: se avisa con su nombre y el
-- resto del juego arranca igual.
local failed = {}
for _, module in ipairs(SERVICES) do
    local success, err = xpcall(function()
        require(module).Start()
    end, debug.traceback)
    if not success then
        table.insert(failed, module.Name)
        warn("[NOCTURNA] El servicio " .. module.Name .. " no pudo iniciar:\n" .. tostring(err))
    end
end

if #failed > 0 then
    warn("[NOCTURNA] Servidor iniciado con fallas en: " .. table.concat(failed, ", "))
else
    print("[NOCTURNA] Servidor iniciado.")
end
