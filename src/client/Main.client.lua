-- NOCTURNA: único punto de entrada del cliente.
local MODULE_TIMEOUT = 30

-- Roblox copia PlayerScripts de a poco: este script puede correr antes de que
-- existan sus módulos hermanos. Se espera cada uno antes de cargar nada.
local root = script.Parent

local function waitForModule(folderName, moduleName)
    local folder = root:WaitForChild(folderName, MODULE_TIMEOUT)
    return folder and folder:WaitForChild(moduleName, MODULE_TIMEOUT)
end

-- Lo primero que ve el jugador es la pantalla de carga, antes incluso de que
-- termine de llegar el resto del juego.
local loadingScreen = nil
do
    local module = waitForModule("UI", "LoadingScreen")
    if module then
        local success, result = pcall(function()
            local screen = require(module)
            screen.Show()
            return screen
        end)
        if success then
            loadingScreen = result
        else
            warn("[NOCTURNA] No se pudo mostrar la pantalla de carga: " .. tostring(result))
        end
    end
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local MODULES = {
    {"Core", "ClientState"},
    {"UI", "Theme"},
    {"UI", "LoadingScreen"},
    {"UI", "HUD"},
    {"UI", "StoryUI"},
    {"UI", "SettingsUI"},
    {"UI", "InventoryUI"},
    {"UI", "JournalUI"},
    {"UI", "MapUI"},
    {"UI", "LobbyUI"},
    {"UI", "DonationUI"},
    {"UI", "StatusUI"},
    {"UI", "EndingUI"},
    {"UI", "WakeUp"},
    {"UI", "CutsceneUI"},
    {"UI", "AdminUI"},
    {"UI", "PuzzleUI"},
    {"Movement", "MovementInput"},
    {"UI", "MobileControls"},
    {"Camera", "FirstPerson"},
    {"Effects", "AudioController"},
    {"Effects", "HorrorEffects"},
    {"Effects", "MonsterAnimator"},
    {"Effects", "QualityController"},
    {"Lobby", "LobbyAmbience"},
    {"Effects", "Cinematics"},
}

for _, path in ipairs(MODULES) do
    if not waitForModule(path[1], path[2]) then
        warn("[NOCTURNA] Falta el módulo del cliente " .. path[1] .. "/" .. path[2])
    end
end

-- Sin botón de reinicio nadie gasta, por error o a propósito, las vidas
-- compartidas del grupo. SetCore falla hasta que Roblox carga su interfaz.
task.spawn(function()
    local StarterGui = game:GetService("StarterGui")
    for _ = 1, 10 do
        local success = pcall(function()
            StarterGui:SetCore("ResetButtonCallback", false)
        end)
        if success then
            return
        end
        task.wait(1)
    end
end)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Modules"):WaitForChild("RemoteHelper"))

local ClientState = require(waitForModule("Core", "ClientState"))
ClientState.Connect()

-- Un módulo que falla no deja al jugador sin el resto de la interfaz ni los controles.
local failed = {}
for index = 3, #MODULES do
    local path = MODULES[index]
    local success, err = xpcall(function()
        local module = waitForModule(path[1], path[2])
        if not module then
            error("módulo no encontrado", 0)
        end
        require(module).Start()
    end, debug.traceback)
    if not success then
        table.insert(failed, path[2])
        warn("[NOCTURNA] El módulo " .. path[2] .. " no pudo iniciar:\n" .. tostring(err))
    end
    if loadingScreen then
        loadingScreen.SetBootProgress((index - 2) / (#MODULES - 2))
    end
end

Remotes.FireServer("LobbyAction", "RequestUpdate")
if loadingScreen then
    loadingScreen.MarkReady()
end
if #failed > 0 then
    warn("[NOCTURNA] Cliente iniciado con fallas en: " .. table.concat(failed, ", "))
else
    print("[NOCTURNA] Cliente iniciado.")
end
