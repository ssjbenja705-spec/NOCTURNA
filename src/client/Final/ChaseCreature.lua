-- El Organismo, tal como se ve en la persecución: una masa enorme de carne y
-- placas que casi llena la galería, con seis brazos que se arrastran hacia
-- adelante, racimos de ojos y una boca que brilla. Existe sólo en el cliente y se
-- anima por código (galope, brazos que se clavan en el piso, rugidos): el
-- servidor sólo dice dónde está.
local ChaseCreature = {}
ChaseCreature.__index = ChaseCreature

local FLESH = Color3.fromRGB(46, 26, 28)
local PLATE = Color3.fromRGB(70, 60, 56)
local TISSUE = Color3.fromRGB(96, 22, 28)
local EYE = Color3.fromRGB(255, 170, 60)
local MOUTH = Color3.fromRGB(200, 30, 24)
local STRIDE = 11

local function piece(model, name, size, color, material, shape)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Color = color
    part.Material = material or Enum.Material.SmoothPlastic
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    if shape then
        part.Shape = shape
    end
    part.Parent = model
    return part
end

-- origin: posición del piso en S = 0 (FinalChaseConfig.Arena.Origin).
function ChaseCreature.new(parent, origin, scale)
    local model = Instance.new("Model")
    model.Name = "ElOrganismo"
    local size = scale or 1
    local self = setmetatable({
        Model = model,
        Origin = origin,
        Scale = size,
        Phase = 0,
        Roar = 0,
        Lunge = 0,
        Parts = {},
        Arms = {},
        Tendrils = {},
        LastStepSign = 1,
        OnStep = nil,
    }, ChaseCreature)

    local parts = self.Parts
    parts.Body = piece(model, "Body", Vector3.new(14, 10, 13) * size, FLESH, Enum.Material.Slate)
    parts.Hump = piece(model, "Hump", Vector3.new(11, 7, 9) * size, PLATE, Enum.Material.CorrodedMetal)
    parts.Head = piece(model, "Head", Vector3.new(8, 5, 6) * size, PLATE, Enum.Material.Slate)
    parts.Jaw = piece(model, "Jaw", Vector3.new(7, 1.6, 5) * size, FLESH, Enum.Material.Slate)
    parts.Mouth = piece(model, "Mouth", Vector3.new(5.5, 1.2, 1) * size, MOUTH, Enum.Material.Neon)
    local glow = Instance.new("PointLight")
    glow.Color = MOUTH
    glow.Range = 20
    glow.Brightness = 2
    glow.Shadows = false
    glow.Parent = parts.Mouth
    self.Glow = glow

    self.Eyes = {}
    for index = 1, 6 do
        local eye = piece(model, "Eye", Vector3.new(0.7, 0.5, 0.4) * size, EYE, Enum.Material.Neon)
        self.Eyes[index] = {Part = eye, Offset = Vector3.new((index - 3.5) * 1.05, 1.2 + (index % 2) * 0.6, -3.05) * size}
    end

    for index = 1, 3 do
        for _, side in ipairs({-1, 1}) do
            local upper = piece(model, "Arm", Vector3.new(1.8, 11, 1.8) * size, FLESH, Enum.Material.Slate)
            local lower = piece(model, "Forearm", Vector3.new(1.4, 10, 1.4) * size, PLATE, Enum.Material.Slate)
            local claw = piece(model, "Claw", Vector3.new(2.2, 0.6, 2.6) * size, Color3.fromRGB(30, 26, 24), Enum.Material.Slate)
            table.insert(self.Arms, {
                Upper = upper,
                Lower = lower,
                Claw = claw,
                Side = side,
                Row = index,
                Phase = (index - 1) * 2.1 + (side > 0 and math.pi or 0),
            })
        end
    end

    for index = 1, 4 do
        local tendril = piece(model, "Tendril", Vector3.new(0.9, 0.9, 12) * size, TISSUE, Enum.Material.SmoothPlastic)
        table.insert(self.Tendrils, {Part = tendril, Lateral = (index - 2.5) * 3 * size, Phase = index * 1.3})
    end
    for index = 1, 4 do
        local blob = piece(model, "Tissue", Vector3.new(3.5, 3.5, 3.5) * size, TISSUE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
        parts["Blob" .. index] = blob
    end

    model.Parent = parent
    return self
end

function ChaseCreature:SetVisible(visible)
    for _, descendant in ipairs(self.Model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.LocalTransparencyModifier = visible and 0 or 1
        end
    end
    self.Glow.Enabled = visible
end

function ChaseCreature:StartRoar(duration)
    self.Roar = math.max(self.Roar, duration or 1.4)
end

function ChaseCreature:StartLunge()
    self.Lunge = 0.5
end

-- Ubica y anima la criatura en la posición s de la galería.
function ChaseCreature:Update(s, speed, deltaTime)
    local size = self.Scale
    self.Phase += (speed or 0) * deltaTime / STRIDE * math.pi * 2
    self.Roar = math.max(0, self.Roar - deltaTime)
    self.Lunge = math.max(0, self.Lunge - deltaTime)

    -- Pasos: cada medio ciclo de galope pega contra el piso.
    local stepSign = math.sin(self.Phase) >= 0 and 1 or -1
    if stepSign ~= self.LastStepSign then
        self.LastStepSign = stepSign
        if self.OnStep and (speed or 0) > 1 then
            self.OnStep(self:Position(s))
        end
    end

    local roaring = self.Roar > 0
    local bob = math.abs(math.sin(self.Phase)) * 0.9 * size
    local sway = math.sin(self.Phase * 0.5) * 1.2 * size
    -- Ángulo positivo: se echa hacia atrás (ruge); negativo: se inclina para correr.
    local lean = roaring and 0.35 or -(0.12 + math.min(speed or 0, 30) / 30 * 0.15)
    local lunge = self.Lunge > 0 and math.sin(self.Lunge / 0.5 * math.pi) * 3 * size or 0

    local origin = self.Origin
    local base = CFrame.new(origin.X + sway, origin.Y + 9 * size + bob, origin.Z + s + lunge)
        * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(lean, 0, math.sin(self.Phase * 0.5) * 0.05)

    local parts = self.Parts
    parts.Body.CFrame = base
    parts.Hump.CFrame = base * CFrame.new(0, 5.5 * size, 1.5 * size) * CFrame.Angles(0.25, 0, 0)
    local headLift = roaring and 0.55 or math.sin(self.Phase) * 0.06
    local head = base * CFrame.new(0, -1 * size, -7.5 * size) * CFrame.Angles(headLift, math.sin(self.Phase * 0.5) * 0.12, 0)
    parts.Head.CFrame = head
    local jawOpen = roaring and 0.75 or 0.18 + math.abs(math.sin(self.Phase * 1.5)) * 0.12
    parts.Jaw.CFrame = head * CFrame.new(0, -2.6 * size, -0.4 * size) * CFrame.Angles(-jawOpen, 0, 0)
    parts.Mouth.CFrame = head * CFrame.new(0, -1.9 * size, -2.6 * size)
    self.Glow.Brightness = roaring and 4 or 1.6 + math.sin(os.clock() * 7) * 0.3
    for _, eye in ipairs(self.Eyes) do
        eye.Part.CFrame = head * CFrame.new(eye.Offset)
    end

    -- Brazos: se estiran hacia adelante y se clavan en el piso por turnos.
    for _, arm in ipairs(self.Arms) do
        local swing = math.sin(self.Phase + arm.Phase)
        local reach = roaring and 1.3 or 0.55 + swing * 0.6
        local shoulder = base * CFrame.new(arm.Side * 7 * size, 1 * size, (-4 + arm.Row * 3) * size)
        local upper = shoulder * CFrame.Angles(reach, 0, arm.Side * (0.55 + arm.Row * 0.08)) * CFrame.new(0, -5.5 * size, 0)
        arm.Upper.CFrame = upper
        local elbow = upper * CFrame.new(0, -5.5 * size, 0)
        local lower = elbow * CFrame.Angles(0.9 + swing * 0.35, 0, -arm.Side * 0.35) * CFrame.new(0, -5 * size, 0)
        arm.Lower.CFrame = lower
        arm.Claw.CFrame = lower * CFrame.new(0, -5 * size, -0.6 * size)
    end

    -- Tejido que se arrastra detrás.
    for _, tendril in ipairs(self.Tendrils) do
        local wave = math.sin(self.Phase * 0.7 + tendril.Phase) * 0.25
        tendril.Part.CFrame = base * CFrame.new(tendril.Lateral, -4 * size, 10 * size) * CFrame.Angles(0.35 + wave, wave, 0)
    end
    parts.Blob1.CFrame = base * CFrame.new(-5 * size, 3 * size, 2 * size)
    parts.Blob2.CFrame = base * CFrame.new(5.5 * size, 2 * size, -1 * size)
    parts.Blob3.CFrame = base * CFrame.new(-3 * size, -3 * size, 4 * size)
    parts.Blob4.CFrame = base * CFrame.new(3 * size, 6 * size, 3 * size)
end

function ChaseCreature:Position(s)
    local origin = self.Origin
    return Vector3.new(origin.X, origin.Y + 4, origin.Z + s)
end

function ChaseCreature:Destroy()
    self.Model:Destroy()
end

return ChaseCreature
