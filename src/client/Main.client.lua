-- NOCTURNA: único punto de entrada del cliente.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Roblox copia PlayerScripts de a poco: este script puede correr antes de que
-- existan sus módulos hermanos. Se espera cada uno antes de cargar nada.
local root = script.Parent

local MODULES = {
    {"Core", "ClientState"},
    {"UI", "Theme"},
    {"UI", "HUD"},
    {"UI", "StoryUI"},
    {"UI", "SettingsUI"},
    {"UI", "InventoryUI"},
    {"UI", "JournalUI"},
    {"UI", "LobbyUI"},
    {"UI", "StatusUI"},
    {"UI", "EndingUI"},
    {"UI", "CutsceneUI"},
    {"UI", "AdminUI"},
    {"Movement", "MovementInput"},
    {"UI", "MobileControls"},
    {"Camera", "FirstPerson"},
    {"Effects", "AudioController"},
    {"Effects", "HorrorEffects"},
    {"Effects", "MonsterAnimator"},
    {"Effects", "QualityController"},
}

local function waitForModule(folderName, moduleName)
    return root:WaitForChild(folderName):WaitForChild(moduleName)
end

for _, path in ipairs(MODULES) do
    waitForModule(path[1], path[2])
end

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Modules"):WaitForChild("RemoteHelper"))

local ClientState = require(waitForModule("Core", "ClientState"))
ClientState.Connect()

for index = 3, #MODULES do
    local path = MODULES[index]
    require(waitForModule(path[1], path[2])).Start()
end

Remotes.FireServer("LobbyAction", "RequestUpdate")
print("[NOCTURNA] Cliente iniciado.")
