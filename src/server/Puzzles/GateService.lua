-- Compuertas que abre el servidor cuando el grupo resuelve una prueba (se activa
-- su RequiresFlag). Mientras están cerradas traban la navegación de las criaturas.
-- Sólo se abren: nunca vuelven a cerrarse sobre nadie.
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local PuzzleProps = require(script.Parent.PuzzleProps)

local OPEN_TIME = 1.8
local TWEEN = TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local GateService = {}
local gates = {}
local started = false

local function liftParts(gate)
    local lift = Vector3.new(0, GameConfig.Map.OpeningHeight - 0.4, 0)
    local moving = {gate.Shutter}
    for _, descendant in ipairs(gate.Shutter:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(moving, descendant)
        end
    end
    for _, item in ipairs(moving) do
        TweenService:Create(item, TWEEN, {Position = item.Position + lift}):Play()
    end
end

local function open(gate, player)
    if gate.Opened then
        return
    end
    gate.Opened = true

    local spec = gate.Spec
    if GameState.Nav then
        GameState.Nav:Unblock(spec.A, spec.B)
    end
    PuzzleProps.SetLamp(gate.Lamp, PuzzleProps.DoneColor)
    Remotes.FireAll("PlaySound", "MachineStart", gate.Closed)
    liftParts(gate)

    local shutter = gate.Shutter
    task.delay(OPEN_TIME * 0.6, function()
        if shutter.Parent then
            shutter.CanCollide = false
        end
    end)

    Remotes.FireAll("StoryNotice", "Se abrió: " .. (spec.Label or "una compuerta"))
    EventBus.Emit("GateOpened", spec, player)
end

function GateService.Populate(plan, folder)
    table.clear(gates)
    for _, spec in ipairs(plan.Gates or {}) do
        local _, shutter, light = PuzzleProps.Gate(folder, plan.Layout, spec)
        local gate = {
            Spec = spec,
            Shutter = shutter,
            Lamp = light,
            Closed = shutter.Position,
            Opened = false,
        }
        table.insert(gates, gate)
        if GameState.Nav then
            GameState.Nav:Block(spec.A, spec.B)
        end
        if spec.RequiresFlag and GameState.HasFlag(spec.RequiresFlag) then
            open(gate, nil)
        end
    end
end

function GateService.Clear()
    table.clear(gates)
end

function GateService.OpenByFlag(flag, player)
    for _, gate in ipairs(gates) do
        if gate.Spec.RequiresFlag == flag then
            open(gate, player)
        end
    end
end

function GateService.IsOpen(gateId)
    for _, gate in ipairs(gates) do
        if gate.Spec.Id == gateId then
            return gate.Opened
        end
    end
    return false
end

function GateService.PositionOf(gateId)
    for _, gate in ipairs(gates) do
        if gate.Spec.Id == gateId then
            return gate.Closed
        end
    end
    return nil
end

function GateService.Start()
    if started then
        return
    end
    started = true
    EventBus.On("FlagSet", function(flag, player)
        GateService.OpenByFlag(flag, player)
    end)
end

return GateService
