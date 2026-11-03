-- NOCTURNA: único punto de entrada del cliente.
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)

local ClientState = require(script.Parent.Core.ClientState)
ClientState.Connect()

local CONTROLLERS = {
    require(script.Parent.UI.HUD),
    require(script.Parent.UI.StoryUI),
    require(script.Parent.UI.SettingsUI),
    require(script.Parent.UI.InventoryUI),
    require(script.Parent.UI.JournalUI),
    require(script.Parent.UI.LobbyUI),
    require(script.Parent.UI.StatusUI),
    require(script.Parent.UI.EndingUI),
    require(script.Parent.UI.CutsceneUI),
    require(script.Parent.UI.AdminUI),
    require(script.Parent.Movement.MovementInput),
    require(script.Parent.UI.MobileControls),
    require(script.Parent.Camera.FirstPerson),
    require(script.Parent.Effects.AudioController),
    require(script.Parent.Effects.HorrorEffects),
    require(script.Parent.Effects.MonsterAnimator),
    require(script.Parent.Effects.QualityController),
}

for _, controller in ipairs(CONTROLLERS) do
    controller.Start()
end

Remotes.FireServer("LobbyAction", "RequestUpdate")
print("[NOCTURNA] Cliente iniciado.")
