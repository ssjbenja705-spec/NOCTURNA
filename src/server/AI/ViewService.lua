-- Hacia dónde mira cada jugador con su cámara. El cliente lo informa unas pocas
-- veces por segundo (CameraLook) y acá se valida: tipos, números finitos, una
-- dirección de largo razonable y un origen pegado a su cabeza (nadie puede
-- "mirar" desde otra punta del mapa). Lo usa El Quieto para saber si lo miran.
--
-- Si el informe falta o es viejo, la IA usa la cabeza y el frente del cuerpo.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

local MonsterController = require(script.Parent.MonsterController)

local ViewService = {}

-- Informes por segundo que se atienden por jugador (el cliente manda ~6).
ViewService.RATE = 8
-- Distancia máxima entre la cámara y la cabeza (primera persona, con margen
-- para el balanceo, agacharse y el escondite).
ViewService.MAX_OFFSET = 8
-- Un informe más viejo que esto ya no cuenta.
ViewService.STALE = 1.5

local views = {}

local function finite(vector)
    return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
        and math.abs(vector.X) < 1e6 and math.abs(vector.Y) < 1e6 and math.abs(vector.Z) < 1e6
end

-- Devuelve origen y dirección unitaria si el informe es creíble; nil si no.
function ViewService.Validate(origin, look, headPosition)
    if typeof(origin) ~= "Vector3" or typeof(look) ~= "Vector3" or typeof(headPosition) ~= "Vector3" then
        return nil
    end
    if not finite(origin) or not finite(look) then
        return nil
    end
    local length = look.Magnitude
    if length < 0.5 or length > 1.5 then
        return nil
    end
    if (origin - headPosition).Magnitude > ViewService.MAX_OFFSET then
        return nil
    end
    return origin, look / length
end

function ViewService.Report(player, origin, look, headPosition, now)
    local validOrigin, validLook = ViewService.Validate(origin, look, headPosition)
    if not validOrigin then
        return false
    end
    local view = views[player]
    if not view then
        view = {}
        views[player] = view
    end
    view.Origin = validOrigin
    view.Look = validLook
    view.Time = now
    return true
end

-- La mirada vigente de un jugador, o nil si no informó hace poco.
function ViewService.Get(player, now)
    local view = views[player]
    if not view then
        return nil
    end
    if (now or os.clock()) - view.Time > ViewService.STALE then
        return nil
    end
    return view
end

function ViewService.Forget(player)
    views[player] = nil
end

local function headOf(player)
    local character = player.Character
    if not character then
        return nil
    end
    local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
    return head and head.Position or nil
end

function ViewService.Start()
    Remotes.OnServer("CameraLook", ViewService.RATE, function(player, origin, look)
        local head = headOf(player)
        if head then
            ViewService.Report(player, origin, look, head, os.clock())
        end
    end)
    Players.PlayerRemoving:Connect(ViewService.Forget)
    MonsterController.SetViewProvider(function(player)
        return ViewService.Get(player)
    end)
end

return ViewService
