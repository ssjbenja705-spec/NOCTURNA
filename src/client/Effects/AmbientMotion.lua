-- Movimiento del ambiente, todo local y barato (no manda nada por la red):
--  * los haces de luz, el polvo y las goteras se ven sólo cerca y con la lámpara
--    prendida; en bajo consumo se apagan;
--  * las lámparas marcadas con Flicker titilan de vez en cuando;
--  * los charcos cercanos tiemblan apenas (el reflejo de las lámparas se mueve) y
--    a veces se oye una gota;
--  * las colitas de Alma se balancean cuando camina, salta o festeja.
-- Lo arranca QualityController, que decide la calidad.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local AmbientMotion = {}

local FX_TAG = "NocturnaAtmosFx"
local PUDDLE_TAG = "NocturnaPuddle"
local HAIR_TAG = "NocturnaHairSway"

local FX_INTERVAL = 0.4
local FX_RANGE = {Beam = 150, Dust = 110, Drips = 60}
local PUDDLE_RANGE = 45
local MAX_PUDDLES = 6
local FLICKER_RANGE = 90
local HAIR_RANGE = 70

local isLow = function()
    return false
end
local started = false

local function cameraPosition()
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame.Position or nil
end

local function positionOf(instance)
    local parent = instance.Parent
    if parent and parent:IsA("Attachment") then
        return parent.WorldPosition
    end
    if parent and parent:IsA("BasePart") then
        return parent.Position
    end
    return nil
end

-- La lámpara de la que sale un haz: prendida y no oscurecida por el servidor.
local function fixtureLit(fixture)
    if not fixture or fixture:GetAttribute("Dark") == true then
        return false
    end
    local light = fixture:FindFirstChildOfClass("PointLight")
    return light ~= nil and light.Enabled
end

-- Efectos de atmósfera -------------------------------------------------------------

local function syncFx(origin)
    local low = isLow()
    for _, fx in ipairs(CollectionService:GetTagged(FX_TAG)) do
        local wanted = false
        local position = positionOf(fx)
        if not low and position and origin then
            local distance = (position - origin).Magnitude
            if fx:IsA("Beam") then
                wanted = distance <= FX_RANGE.Beam and fixtureLit(fx.Parent)
            elseif fx.Name == "Drips" then
                wanted = distance <= FX_RANGE.Drips
            else
                -- El polvo cae de un techo de 40 x 40: se mide al centro de la sala.
                wanted = distance <= FX_RANGE.Dust
            end
        end
        if fx.Enabled ~= wanted then
            fx.Enabled = wanted
        end
    end
end

-- Lámparas que titilan ---------------------------------------------------------------

local flickering = {}

local function flicker(fixture, random)
    if flickering[fixture] then
        return
    end
    flickering[fixture] = true
    -- Se baja el brillo (no Enabled): el bajo consumo y el servidor mandan sobre
    -- Enabled, y así nunca se pisan. Si el servidor cambia el brillo en el medio,
    -- gana el valor del servidor.
    task.spawn(function()
        local light = fixture:FindFirstChildOfClass("PointLight")
        local material = fixture.Material
        for _ = 1, random:NextInteger(2, 6) do
            local before = light and light.Brightness
            local dimmed = before and before * 0.08
            if light then
                light.Brightness = dimmed
            end
            fixture.Material = Enum.Material.Glass
            task.wait(random:NextNumber(0.03, 0.12))
            if fixture.Parent == nil then
                break
            end
            if light and light.Brightness == dimmed then
                light.Brightness = before
            end
            fixture.Material = material
            task.wait(random:NextNumber(0.04, 0.3))
        end
        flickering[fixture] = nil
    end)
end

local function tickFlicker(origin, random)
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture:GetAttribute("Flicker") == true and fixture:IsA("BasePart")
            and (fixture.Position - origin).Magnitude <= FLICKER_RANGE and random:NextNumber() < 0.08 then
            flicker(fixture, random)
        end
    end
end

-- Charcos ---------------------------------------------------------------------------

local puddleBase = {}

local function restorePuddle(water)
    local base = puddleBase[water]
    if base then
        if water.Parent then
            water.CFrame = base.CFrame
            water.Reflectance = base.Reflectance
        end
        puddleBase[water] = nil
    end
end

local function nearPuddles(origin)
    local list = {}
    for _, water in ipairs(CollectionService:GetTagged(PUDDLE_TAG)) do
        if water:IsA("BasePart") then
            local distance = (water.Position - origin).Magnitude
            if distance <= PUDDLE_RANGE then
                table.insert(list, {Water = water, Distance = distance})
            elseif puddleBase[water] then
                restorePuddle(water)
            end
        end
    end
    table.sort(list, function(a, b)
        return a.Distance < b.Distance
    end)
    return list
end

local function wobblePuddles(list, now)
    for index, entry in ipairs(list) do
        local water = entry.Water
        if index > MAX_PUDDLES or isLow() then
            restorePuddle(water)
        else
            local base = puddleBase[water]
            if not base then
                base = {CFrame = water.CFrame, Reflectance = water.Reflectance, Phase = (water.Position.X + water.Position.Z) % 6}
                puddleBase[water] = base
            end
            -- El disco está acostado (su X apunta arriba): inclinarlo un cuarto de
            -- grado mueve el brillo de las lámparas como agua quieta que tiembla.
            local t = now * 1.7 + base.Phase
            water.CFrame = base.CFrame * CFrame.Angles(0, math.rad(math.sin(t) * 0.25), math.rad(math.cos(t * 1.3) * 0.25))
            water.Reflectance = base.Reflectance + math.sin(t * 2.1) * 0.04
        end
    end
end

-- Pelo de Alma ----------------------------------------------------------------------

local hair = {}

local function hairState(joint)
    local state = hair[joint]
    if not state then
        state = {Base = joint.C0, AngleX = 0, AngleZ = 0, SpeedX = 0, SpeedZ = 0}
        hair[joint] = state
    end
    return state
end

local function swayHair(origin, deltaTime, now)
    for joint, state in pairs(hair) do
        if not joint.Parent then
            hair[joint] = nil
        else
            -- Quien no está cerca vuelve a su lugar y deja de calcularse.
            local head = joint.Part0
            if not head or (head.Position - origin).Magnitude > HAIR_RANGE or isLow() then
                joint.C0 = state.Base
                hair[joint] = nil
            end
        end
    end
    if isLow() then
        return
    end

    for _, joint in ipairs(CollectionService:GetTagged(HAIR_TAG)) do
        local head = joint:IsA("Weld") and joint.Part0
        if head and head.Parent and (head.Position - origin).Magnitude <= HAIR_RANGE then
            local state = hairState(joint)
            local rig = head.Parent
            local root = rig:FindFirstChild("HumanoidRootPart")
            local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
            local localVelocity = head.CFrame:VectorToObjectSpace(velocity)
            local side = joint:GetAttribute("Side") or 1
            -- Resorte: se mueve al revés de la marcha, rebota al saltar y vuelve.
            local idle = math.sin(now * 2.2 + side) * 0.04
            local targetX = math.clamp(localVelocity.Z * 0.03 + localVelocity.Y * 0.025, -0.6, 0.6) + idle
            local targetZ = math.clamp(-localVelocity.X * 0.03, -0.5, 0.5) + side * math.abs(localVelocity.Y) * 0.015
            local stiffness, damping = 60, 7
            state.SpeedX += ((targetX - state.AngleX) * stiffness - state.SpeedX * damping) * deltaTime
            state.SpeedZ += ((targetZ - state.AngleZ) * stiffness - state.SpeedZ * damping) * deltaTime
            state.AngleX = math.clamp(state.AngleX + state.SpeedX * deltaTime, -0.7, 0.7)
            state.AngleZ = math.clamp(state.AngleZ + state.SpeedZ * deltaTime, -0.6, 0.6)
            joint.C0 = state.Base * CFrame.Angles(state.AngleX, 0, state.AngleZ)
        end
    end
end

-- Arranque --------------------------------------------------------------------------

function AmbientMotion.Start(lowQuality)
    if started then
        return
    end
    started = true
    if type(lowQuality) == "function" then
        isLow = lowQuality
    end

    local random = Random.new()
    local fxElapsed = 0
    local motionElapsed = 0
    local nextDrop = 4
    local puddles = {}
    RunService.Heartbeat:Connect(function(deltaTime)
        local origin = cameraPosition()
        if not origin then
            return
        end
        local now = os.clock()

        fxElapsed += deltaTime
        if fxElapsed >= FX_INTERVAL then
            fxElapsed = 0
            syncFx(origin)
            if not isLow() then
                tickFlicker(origin, random)
            end
            puddles = nearPuddles(origin)

            -- Una gota de vez en cuando cerca de un charco con gotera.
            nextDrop -= FX_INTERVAL
            if nextDrop <= 0 then
                nextDrop = random:NextNumber(3, 8)
                local first = puddles[1]
                if first and first.Distance < 25 and first.Water:GetAttribute("Drips") then
                    local ok, AudioController = pcall(require, script.Parent:FindFirstChild("AudioController"))
                    if ok and type(AudioController) == "table" and AudioController.PlayAt then
                        pcall(AudioController.PlayAt, "WaterDrop", first.Water.Position)
                    end
                end
            end
        end

        -- Charcos y pelo a 20 cuadros por segundo: alcanza para que se vea suave.
        motionElapsed += deltaTime
        if motionElapsed >= 0.05 then
            local step = motionElapsed
            motionElapsed = 0
            wobblePuddles(puddles, now)
            swayHair(origin, step, now)
        end
    end)
end

return AmbientMotion
