-- Animación procedural de las criaturas. Corre sólo en el cliente y sólo para las
-- que están cerca, así no hay tráfico de red ni costo en equipos modestos.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local UPDATE_RANGE = 110
local LOW_RATE_RANGE = 45
local LOW_RATE = 1 / 15

local MonsterAnimator = {}
local rigs = {}

local AXES = {
    X = function(angle)
        return CFrame.Angles(angle, 0, 0)
    end,
    Y = function(angle)
        return CFrame.Angles(0, angle, 0)
    end,
    Z = function(angle)
        return CFrame.Angles(0, 0, angle)
    end,
}

local function addRig(model)
    local root = model:WaitForChild("HumanoidRootPart", 5)
    if not root or rigs[model] then
        return
    end

    local joints = {}
    for _, joint in ipairs(model:GetDescendants()) do
        if joint:IsA("Motor6D") and joint:GetAttribute("SwingAmount") then
            table.insert(joints, {
                Joint = joint,
                Base = joint.C0,
                Amount = joint:GetAttribute("SwingAmount"),
                Phase = joint:GetAttribute("SwingPhase") or 0,
                Rotate = AXES[joint:GetAttribute("SwingAxis") or "X"],
            })
        end
    end

    rigs[model] = {Root = root, Joints = joints, Clock = 0, Elapsed = 0}
end

local function animate(rig, deltaTime, model)
    local speed = model:GetAttribute("MoveSpeed") or 0
    rig.Clock += deltaTime * (speed > 0 and 2 + speed * 0.5 or 1)
    local strength = speed > 0 and 1 or 0.12

    for _, entry in ipairs(rig.Joints) do
        local angle = math.sin(rig.Clock + entry.Phase) * entry.Amount * strength
        entry.Joint.C0 = entry.Base * entry.Rotate(angle)
    end
end

function MonsterAnimator.Start()
    CollectionService:GetInstanceAddedSignal("NocturnaMonster"):Connect(function(model)
        task.spawn(addRig, model)
    end)
    CollectionService:GetInstanceRemovedSignal("NocturnaMonster"):Connect(function(model)
        rigs[model] = nil
    end)
    for _, model in ipairs(CollectionService:GetTagged("NocturnaMonster")) do
        task.spawn(addRig, model)
    end

    RunService.RenderStepped:Connect(function(deltaTime)
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end

        local origin = camera.CFrame.Position
        for model, rig in pairs(rigs) do
            local distance = (rig.Root.Position - origin).Magnitude
            if distance <= UPDATE_RANGE then
                rig.Elapsed += deltaTime
                if distance <= LOW_RATE_RANGE or rig.Elapsed >= LOW_RATE then
                    animate(rig, rig.Elapsed, model)
                    rig.Elapsed = 0
                end
            end
        end
    end)
end

return MonsterAnimator
