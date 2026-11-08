-- Golpe de El Organismo a un jugador. Respeta las reglas de daño y muerte del juego:
-- si existe el sistema de captura (ServerScriptService.Server.Capture) se le pasa
-- el golpe; si no está o no lo toma, se aplica con DamageService como cualquier
-- ataque de criatura.
--
-- Contrato esperado del módulo de captura (cualquiera de las dos funciones):
--   Capture.Hit(player, info) o Capture.Capture(player, info) -> true si lo tomó.
--   info = {Source = "FinalChase", Kind = "ElOrganismo", Damage = n, Position = Vector3}
local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local DamageService = require(script.Parent.Parent.Data.DamageService)

local ChaseHit = {}
local cached = nil

local function captureModule()
    if cached ~= nil then
        return cached or nil
    end
    local server = script.Parent.Parent
    local entry = server:FindFirstChild("Capture")
    local module = nil
    if entry and entry:IsA("ModuleScript") then
        module = entry
    elseif entry then
        module = entry:FindFirstChild("CaptureService") or entry:FindFirstChildWhichIsA("ModuleScript")
    end
    cached = false
    if module then
        local ok, result = pcall(require, module)
        if ok and type(result) == "table" then
            cached = result
        end
    end
    return cached or nil
end

local function tryCapture(player, info)
    local capture = captureModule()
    if not capture then
        return false
    end
    for _, name in ipairs({"Hit", "Capture"}) do
        local handler = capture[name]
        if type(handler) == "function" then
            local ok, handled = pcall(handler, player, info)
            if ok and handled then
                return true
            end
        end
    end
    return false
end

function ChaseHit.Apply(player, amount, position, kind)
    local info = {
        Source = "FinalChase",
        Kind = kind or "ElOrganismo",
        Damage = amount,
        Position = position,
    }
    local applied = tryCapture(player, info)
    if not applied then
        applied = DamageService.ApplyDamage(player, math.clamp(math.floor(amount), 1, 100))
        if applied then
            Remotes.FireClient("MonsterEffect", player, "Jumpscare", {Kind = info.Kind})
        end
    end
    if applied then
        EventBus.Emit("PlayerHit", player, info.Kind)
    end
    return applied
end

-- Para pruebas: vuelve a buscar el módulo de captura.
function ChaseHit.Reset()
    cached = nil
end

return ChaseHit
