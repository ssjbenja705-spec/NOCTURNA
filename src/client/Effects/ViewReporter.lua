-- Informa al servidor hacia dónde mira la cámara (El Quieto se congela cuando lo
-- miran de verdad, no cuando el cuerpo apunta para su lado). Pocas veces por
-- segundo y sólo si la mirada cambió; cada tanto, aunque no cambie, para que el
-- informe no quede viejo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Modules"):WaitForChild("RemoteHelper"))

local INTERVAL = 0.16
local REFRESH = 0.8
-- Cambios menores que esto (≈2,5° o medio stud) no se informan.
local MIN_DOT = 0.999
local MIN_MOVE = 0.5

local ViewReporter = {}
local player = Players.LocalPlayer
local elapsed = 0
local sinceSent = math.huge
local lastOrigin = nil
local lastLook = nil

-- Devuelve true si mandó un informe.
function ViewReporter.Step(deltaTime, cameraCFrame)
    elapsed += deltaTime
    sinceSent += deltaTime
    if elapsed < INTERVAL then
        return false
    end
    elapsed = 0

    local character = player and player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return false
    end

    local origin = cameraCFrame.Position
    local look = cameraCFrame.LookVector
    local changed = lastLook == nil
        or look:Dot(lastLook) < MIN_DOT
        or (origin - lastOrigin).Magnitude > MIN_MOVE
    if not changed and sinceSent < REFRESH then
        return false
    end

    lastOrigin, lastLook = origin, look
    sinceSent = 0
    Remotes.FireServer("CameraLook", origin, look)
    return true
end

function ViewReporter.Start()
    RunService.Heartbeat:Connect(function(deltaTime)
        local camera = workspace.CurrentCamera
        if camera then
            ViewReporter.Step(deltaTime, camera.CFrame)
        end
    end)
end

return ViewReporter
