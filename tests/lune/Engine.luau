--!nocheck
-- Motor simulado para probar el juego sin Roblox: reloj virtual, instancias, señales,
-- remotos, personajes y DataStore en memoria. Cada instancia guarda una copia real
-- de Lune, por lo que asignar una propiedad inexistente o de tipo incorrecto falla
-- igual que fallaría en el motor. Lo que NO simula: física, render y red real.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Engine = {}

local reflection = roblox.getReflectionDatabase()

local realTypeof = typeof
local MockMeta = {}
local clockValue = 0
local scheduled = {}
local sequence = 0
local failures = {}
local warnings = {}

local function isMock(value)
    return type(value) == "table" and getmetatable(value) == MockMeta
end

local function mockTypeof(value)
    if isMock(value) then
        return "Instance"
    end
    return realTypeof(value)
end

-- Planificador virtual -------------------------------------------------------

local function schedule(at, thread, ...)
    sequence += 1
    table.insert(scheduled, {At = at, Sequence = sequence, Thread = thread, Args = table.pack(...)})
end

local function reportError(thread, message)
    table.insert(failures, tostring(message) .. "\n" .. debug.traceback(thread))
end

local function resume(thread, ...)
    if coroutine.status(thread) == "dead" then
        return
    end
    local ok, message = coroutine.resume(thread, ...)
    if not ok then
        reportError(thread, message)
    end
end

local taskLibrary = {}

function taskLibrary.wait(seconds)
    local started = clockValue
    schedule(clockValue + (seconds or 0.03), coroutine.running())
    coroutine.yield()
    return clockValue - started
end

function taskLibrary.spawn(callback, ...)
    local thread = type(callback) == "thread" and callback or coroutine.create(callback)
    resume(thread, ...)
    return thread
end

function taskLibrary.defer(callback, ...)
    local thread = type(callback) == "thread" and callback or coroutine.create(callback)
    schedule(clockValue, thread, ...)
    return thread
end

function taskLibrary.delay(seconds, callback, ...)
    local thread = type(callback) == "thread" and callback or coroutine.create(callback)
    schedule(clockValue + (seconds or 0), thread, ...)
    return thread
end

function taskLibrary.cancel() end

-- Señales ---------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({Listeners = {}, Waiting = {}}, Signal)
end

function Signal:Connect(callback)
    local listeners = self.Listeners
    table.insert(listeners, callback)
    return {
        Connected = true,
        Disconnect = function()
            local index = table.find(listeners, callback)
            if index then
                table.remove(listeners, index)
            end
        end,
    }
end

Signal.Once = Signal.Connect

function Signal:Wait()
    table.insert(self.Waiting, coroutine.running())
    return coroutine.yield()
end

function Signal:Fire(...)
    for _, callback in ipairs(table.clone(self.Listeners)) do
        taskLibrary.spawn(callback, ...)
    end
    local waiting = self.Waiting
    self.Waiting = {}
    for _, thread in ipairs(waiting) do
        resume(thread, ...)
    end
end

Engine.Signal = Signal

-- Instancias ------------------------------------------------------------------

local EVENT_NAMES = {
    Changed = true, Touched = true, Triggered = true, OnServerEvent = true, OnClientEvent = true,
    Activated = true, InputBegan = true, InputEnded = true, Heartbeat = true, RenderStepped = true,
    Stepped = true, PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true,
    CharacterRemoving = true, Died = true, HealthChanged = true, Chatted = true, Completed = true,
    Event = true, WindowFocusReleased = true, Loaded = true, ChildAdded = true, DescendantAdded = true,
    DescendantRemoving = true,
    PromptTriggered = true, MouseButton1Click = true, FocusLost = true,
    TeleportInitFailed = true, PromptProductPurchaseFinished = true,
    InputChanged = true,
}

local INSTANCE_PROPERTIES = {
    Parent = true, PrimaryPart = true, SoundGroup = true, CameraSubject = true, Part0 = true,
    Part1 = true, CurrentCamera = true, Character = true, LocalPlayer = true, Adornee = true,
}

-- Clases que Lune no puede instanciar o que sólo existen en este simulador.
local VIRTUAL_CLASSES = {
    DataModel = true, Player = true, DataStoreService = true, AnalyticsService = true,
    CollectionService = true, TweenService = true, RunService = true, Debris = true,
    TextService = true, UserInputService = true, GlobalDataStore = true, Tween = true,
    TeleportService = true, MarketplaceService = true,
    GuiService = true,
}

local function classChain(className)
    local chain = {}
    local current = className
    while current and current ~= "" do
        chain[current] = true
        local class = reflection:GetClass(current)
        current = class and class.Superclass or nil
    end
    return chain
end

local chainCache = {}

local function mockNew(className, name)
    local real = nil
    if not VIRTUAL_CLASSES[className] then
        real = roblox.Instance.new(className)
    end

    chainCache[className] = chainCache[className] or classChain(className)

    local self = setmetatable({}, MockMeta)
    rawset(self, "__data", {
        ClassName = className,
        Name = name or className,
        Children = {},
        Attributes = {},
        Signals = {},
        PropertySignals = {},
        AttributeSignals = {},
        -- Lune no lee propiedades Content (MeshId, TextureID): se simulan vacías.
        Values = className == "Sound" and {IsPlaying = false}
            or className == "MeshPart" and {MeshId = "", TextureID = ""}
            or {},
        Real = real,
        Destroyed = false,
    })
    return self
end

Engine.New = mockNew

local function dataOf(instance)
    return rawget(instance, "__data")
end

local function signalFor(data, key)
    data.Signals[key] = data.Signals[key] or Signal.new()
    return data.Signals[key]
end

local function firePropertyChanged(data, key)
    local signal = data.PropertySignals[key]
    if signal then
        signal:Fire()
    end
end

local Methods = {}

function Methods:GetChildren()
    return table.clone(dataOf(self).Children)
end

function Methods:GetDescendants()
    local result = {}
    local function walk(instance)
        for _, child in ipairs(dataOf(instance).Children) do
            table.insert(result, child)
            walk(child)
        end
    end
    walk(self)
    return result
end

function Methods:FindFirstChild(name, recursive)
    for _, child in ipairs(dataOf(self).Children) do
        if dataOf(child).Name == name then
            return child
        end
    end
    if recursive then
        for _, child in ipairs(dataOf(self).Children) do
            local found = child:FindFirstChild(name, true)
            if found then
                return found
            end
        end
    end
    return nil
end

function Methods:FindFirstChildOfClass(className)
    for _, child in ipairs(dataOf(self).Children) do
        if dataOf(child).ClassName == className then
            return child
        end
    end
    return nil
end

function Methods:FindFirstChildWhichIsA(className)
    for _, child in ipairs(dataOf(self).Children) do
        if child:IsA(className) then
            return child
        end
    end
    return nil
end

function Methods:FindFirstAncestor(name)
    local current = dataOf(self).Values.Parent
    while current do
        if dataOf(current).Name == name then
            return current
        end
        current = dataOf(current).Values.Parent
    end
    return nil
end

function Methods:FindFirstAncestorOfClass(className)
    local current = dataOf(self).Values.Parent
    while current do
        if dataOf(current).ClassName == className then
            return current
        end
        current = dataOf(current).Values.Parent
    end
    return nil
end

function Methods:WaitForChild(name, timeout)
    local found = self:FindFirstChild(name)
    if found then
        return found
    end

    local deadline = clockValue + (timeout or 30)
    while clockValue < deadline do
        taskLibrary.wait(0.1)
        found = self:FindFirstChild(name)
        if found then
            return found
        end
    end
    if timeout == nil then
        error("WaitForChild agotó el tiempo: " .. tostring(name) .. " en " .. self:GetFullName())
    end
    return nil
end

function Methods:IsA(className)
    local data = dataOf(self)
    chainCache[data.ClassName] = chainCache[data.ClassName] or classChain(data.ClassName)
    return chainCache[data.ClassName][className] == true
end

function Methods:IsDescendantOf(ancestor)
    local current = dataOf(self).Values.Parent
    while current do
        if current == ancestor then
            return true
        end
        current = dataOf(current).Values.Parent
    end
    return false
end

function Methods:GetFullName()
    local names = {}
    local current = self
    while current do
        table.insert(names, 1, dataOf(current).Name)
        current = dataOf(current).Values.Parent
    end
    return table.concat(names, ".")
end

function Methods:Destroy()
    local data = dataOf(self)
    data.Destroyed = true
    self.Parent = nil
    for _, child in ipairs(table.clone(data.Children)) do
        child:Destroy()
    end
    if Engine.CollectionService then
        Engine.CollectionService:_forget(self)
    end
end

-- Copia propiedades, atributos e hijos. Las referencias a otras instancias
-- (Part0, PrimaryPart...) no se copian: el juego sólo clona plantillas sueltas.
function Methods:Clone()
    local data = dataOf(self)
    local copy = mockNew(data.ClassName, data.Name)
    for key, value in pairs(data.Values) do
        if not isMock(value) and not INSTANCE_PROPERTIES[key] then
            copy[key] = value
        end
    end
    for name, value in pairs(data.Attributes) do
        copy:SetAttribute(name, value)
    end
    for _, child in ipairs(data.Children) do
        child:Clone().Parent = copy
    end
    return copy
end

function Methods:ClearAllChildren()
    for _, child in ipairs(table.clone(dataOf(self).Children)) do
        child:Destroy()
    end
end

function Methods:SetAttribute(name, value)
    local data = dataOf(self)
    if value ~= nil then
        local kind = realTypeof(value)
        if kind == "table" or kind == "function" or kind == "thread" or isMock(value) then
            error("Atributo de tipo no admitido en Roblox: " .. name .. " = " .. kind)
        end
    end
    if data.Attributes[name] == value then
        return
    end
    data.Attributes[name] = value
    local signal = data.AttributeSignals[name]
    if signal then
        signal:Fire()
    end
end

function Methods:GetAttribute(name)
    return dataOf(self).Attributes[name]
end

function Methods:GetAttributeChangedSignal(name)
    local data = dataOf(self)
    data.AttributeSignals[name] = data.AttributeSignals[name] or Signal.new()
    return data.AttributeSignals[name]
end

function Methods:GetPropertyChangedSignal(name)
    local data = dataOf(self)
    data.PropertySignals[name] = data.PropertySignals[name] or Signal.new()
    return data.PropertySignals[name]
end

-- Part / Model ----------------------------------------------------------------

function Methods:PivotTo(cframe)
    local root = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
    if root then
        root.CFrame = cframe
    end
end

function Methods:GetPivot()
    local root = self.PrimaryPart or self:FindFirstChild("HumanoidRootPart")
    return root and root.CFrame or roblox.CFrame.new()
end

-- Humanoid --------------------------------------------------------------------

function Methods:TakeDamage(amount)
    self.Health = math.max(0, self.Health - amount)
end

function Methods:MoveTo(position)
    dataOf(self).MoveTarget = position
end

-- Animator: devuelve una pista simulada y anota qué se reprodujo.
function Methods:LoadAnimation(animation)
    local id = animation.AnimationId
    local track = {Animation = animation, Looped = false, IsPlaying = false, Speed = 1, Length = 2}
    function track.Play(this)
        this.IsPlaying = true
        table.insert(Engine.AnimationLog, id)
    end
    function track.Stop(this)
        this.IsPlaying = false
    end
    function track.AdjustSpeed(this, speed)
        this.Speed = speed
    end
    function track.AdjustWeight() end
    return track
end

-- ParticleEmitter: cuenta las partículas emitidas.
function Methods:Emit(count)
    local data = dataOf(self)
    data.Emitted = (data.Emitted or 0) + (count or 16)
end

function Engine.MoveTarget(humanoid)
    return dataOf(humanoid).MoveTarget
end

function Engine.Emitted(emitter)
    return dataOf(emitter).Emitted or 0
end

-- Sound -----------------------------------------------------------------------

function Methods:Play()
    dataOf(self).Values.IsPlaying = true
end

function Methods:Stop()
    dataOf(self).Values.IsPlaying = false
end

-- Prompt: disparo simulado, como hace el motor cuando el jugador completa la acción.
function Methods:Fire(...)
    signalFor(dataOf(self), "Triggered"):Fire(...)
end

-- RemoteEvent -----------------------------------------------------------------

function Methods:FireServer(...)
    Engine.CountRemote(dataOf(self).Name)
    signalFor(dataOf(self), "OnServerEvent"):Fire(Engine.LocalPlayer, ...)
end

function Methods:FireClient(player, ...)
    Engine.RecordRemote(dataOf(self).Name, player, ...)
    if player == Engine.LocalPlayer then
        signalFor(dataOf(self), "OnClientEvent"):Fire(...)
    end
end

function Methods:FireAllClients(...)
    Engine.RecordRemote(dataOf(self).Name, nil, ...)
    if Engine.LocalPlayer then
        signalFor(dataOf(self), "OnClientEvent"):Fire(...)
    end
end

-- Player ----------------------------------------------------------------------

function Methods:LoadCharacter()
    if self.Character then
        self.Character:Destroy()
    end
    Engine.CreateCharacter(self)
end

function Methods:Kick(reason)
    Engine.Kicked[self.UserId] = reason or ""
    Engine.RemovePlayer(self)
end

function Methods:GetRankInGroup()
    return 0
end

-- Datos con los que llegó el jugador (TeleportData de un viaje entre servidores).
function Methods:GetJoinData()
    return dataOf(self).JoinData or {}
end

-- TeleportOptions ------------------------------------------------------------

function Methods:SetTeleportData(value)
    dataOf(self).TeleportData = value
end

function Methods:GetTeleportData()
    return dataOf(self).TeleportData
end

-- DescendantAdded / DescendantRemoving: como en Roblox, cada ancestro que escucha
-- recibe la instancia y cada una de sus descendientes. Sólo se recorre el árbol
-- si alguien escucha.
local function notifyAncestors(start, eventName, instance)
    local signals = nil
    local current = start
    while current do
        local signal = dataOf(current).Signals[eventName]
        if signal and #signal.Listeners > 0 then
            signals = signals or {}
            table.insert(signals, signal)
        end
        current = dataOf(current).Values.Parent
    end
    if not signals then
        return
    end
    local items = instance:GetDescendants()
    table.insert(items, 1, instance)
    for _, signal in ipairs(signals) do
        for _, item in ipairs(items) do
            signal:Fire(item)
        end
    end
end

local function assignParent(self, data, parent)
    local old = data.Values.Parent
    if old == parent then
        return
    end
    if old then
        notifyAncestors(old, "DescendantRemoving", self)
        local children = dataOf(old).Children
        local index = table.find(children, self)
        if index then
            table.remove(children, index)
        end
    end
    data.Values.Parent = parent
    if parent then
        table.insert(dataOf(parent).Children, self)
        notifyAncestors(parent, "DescendantAdded", self)
    end
end

function MockMeta.__index(self, key)
    local data = rawget(self, "__data")

    if key == "Name" or key == "ClassName" then
        return data[key]
    end

    local value = data.Values[key]
    if value ~= nil then
        return value
    end

    if EVENT_NAMES[key] then
        return signalFor(data, key)
    end

    if Methods[key] then
        return Methods[key]
    end

    if INSTANCE_PROPERTIES[key] then
        return nil
    end

    local real = data.Real
    if real then
        local ok, result = pcall(function()
            return real[key]
        end)
        if ok then
            return result
        end
    end

    -- Position es un alias de CFrame que Lune no expone por sí sola.
    if key == "Position" and self:IsA("BasePart") then
        return self.CFrame.Position
    end

    local child = self:FindFirstChild(key)
    if child then
        return child
    end

    if real then
        error(string.format("%s no es miembro válido de %s (%s)", tostring(key), data.ClassName, self:GetFullName()), 2)
    end
    return nil
end

function MockMeta.__newindex(self, key, value)
    local data = rawget(self, "__data")

    if key == "Parent" then
        assignParent(self, data, value)
        return
    end
    if key == "Name" then
        data.Name = value
        return
    end

    if isMock(value) or INSTANCE_PROPERTIES[key] then
        data.Values[key] = value
        firePropertyChanged(data, key)
        return
    end

    local real = data.Real
    if real then
        local ok, message = pcall(function()
            real[key] = value
        end)
        if not ok then
            error(string.format("Propiedad inválida %s.%s = %s: %s", data.ClassName, tostring(key), tostring(value), tostring(message)), 2)
        end
    end

    data.Values[key] = value

    if key == "CFrame" and self:IsA("BasePart") then
        data.Values.Position = value.Position
    elseif key == "Position" and self:IsA("BasePart") then
        local cframe = data.Values.CFrame
        if cframe then
            data.Values.CFrame = cframe - cframe.Position + value
        else
            data.Values.CFrame = roblox.CFrame.new(value)
        end
    elseif key == "Health" and data.ClassName == "Humanoid" then
        signalFor(data, "HealthChanged"):Fire(value)
        if value <= 0 and not data.DiedFired then
            data.DiedFired = true
            signalFor(data, "Died"):Fire()
        end
    end

    firePropertyChanged(data, key)
end

MockMeta.__tostring = function(self)
    return rawget(self, "__data").Name
end

-- Servicios -------------------------------------------------------------------

local function createCollectionService()
    local service = mockNew("CollectionService")
    local tags = {}
    local added = {}
    local removed = {}

    local function bucket(tag)
        tags[tag] = tags[tag] or {}
        return tags[tag]
    end

    function service:AddTag(instance, tag)
        local list = bucket(tag)
        if not table.find(list, instance) then
            table.insert(list, instance)
            if added[tag] then
                added[tag]:Fire(instance)
            end
        end
    end

    rawset(service, "AddTag", service.AddTag)
    return service, tags, added, removed, bucket
end

local TweenStub = {}
TweenStub.__index = TweenStub

function TweenStub:Play()
    for key, value in pairs(self.Goal) do
        self.Target[key] = value
    end
    self.Completed:Fire(Enum and nil)
end

function TweenStub:Cancel() end
function TweenStub:Pause() end

local function makeEnvironment(realm, moduleInstance)
    return {
        script = moduleInstance,
        game = Engine.Game,
        workspace = Engine.Workspace,
        task = taskLibrary,
        typeof = mockTypeof,
        require = function(target)
            return Engine.Require(target, realm)
        end,
        warn = function(...)
            local parts = {}
            for index = 1, select("#", ...) do
                table.insert(parts, tostring((select(index, ...))))
            end
            table.insert(warnings, table.concat(parts, " "))
        end,
        print = function() end,
        os = {
            clock = function()
                return clockValue
            end,
            time = function()
                return math.floor(1800000000 + clockValue)
            end,
            date = os.date,
            difftime = os.difftime,
        },
        Instance = {new = function(className)
            return mockNew(className)
        end},
        Vector3 = roblox.Vector3,
        Vector2 = roblox.Vector2,
        CFrame = roblox.CFrame,
        Color3 = roblox.Color3,
        UDim = roblox.UDim,
        UDim2 = roblox.UDim2,
        Enum = roblox.Enum,
        NumberSequence = roblox.NumberSequence,
        NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
        NumberRange = roblox.NumberRange,
        ColorSequence = roblox.ColorSequence,
        ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
        Random = Engine.RandomClass,
        TweenInfo = {new = function(...)
            return {...}
        end},
        RaycastParams = {new = function()
            return {}
        end},
        UserSettings = function()
            return {GameSettings = {SavedQualityLevel = {Value = 10}}}
        end,
        math = math, string = string, table = table, bit32 = bit32, coroutine = coroutine,
        ipairs = ipairs, pairs = pairs, next = next, select = select, type = type,
        tostring = tostring, tonumber = tonumber, assert = assert, error = error,
        pcall = pcall, xpcall = xpcall, setmetatable = setmetatable, getmetatable = getmetatable,
        rawget = rawget, rawset = rawset, rawequal = rawequal, unpack = unpack, debug = debug,
        utf8 = utf8,
    }
end

Engine.RandomClass = {
    new = function(seed)
        local state = (seed or Engine.NextSeed()) % 2147483647
        if state <= 0 then
            state += 2147483646
        end
        local function nextValue()
            state = (state * 48271) % 2147483647
            return state / 2147483647
        end
        return {
            NextNumber = function(_, minimum, maximum)
                minimum = minimum or 0
                maximum = maximum or 1
                return minimum + nextValue() * (maximum - minimum)
            end,
            NextInteger = function(_, minimum, maximum)
                return minimum + math.floor(nextValue() * (maximum - minimum + 1))
            end,
        }
    end,
}

local seedCounter = 1

function Engine.NextSeed()
    seedCounter += 7919
    return seedCounter
end

function Engine.SetSeed(seed)
    seedCounter = seed
end

local function runChunk(source, chunkName, environment)
    local bytecode = luau.compile(source, {optimizationLevel = 1, debugLevel = 2})
    local loaded = luau.load(bytecode, {debugName = chunkName, environment = environment})
    return loaded
end

function Engine.Require(target, realm)
    if not isMock(target) then
        error("require recibió algo que no es un ModuleScript: " .. tostring(target), 2)
    end

    local data = dataOf(target)
    assert(data.ClassName == "ModuleScript", "require de algo que no es ModuleScript: " .. target:GetFullName())

    local cache = Engine.ModuleCache[realm]
    local entry = cache[target]
    if entry then
        return entry.Value
    end

    local chunk = runChunk(data.Source, target:GetFullName(), makeEnvironment(realm, target))
    local value = chunk()
    assert(value ~= nil, "El módulo no devolvió un valor: " .. target:GetFullName())
    cache[target] = {Value = value}
    return value
end

-- Carga del árbol del proyecto, con las mismas reglas de nombres que Rojo --------

local function classifyFile(fileName)
    local base = string.match(fileName, "^(.*)%.server%.luau?$")
    if base then
        return "Script", base
    end
    base = string.match(fileName, "^(.*)%.client%.luau?$")
    if base then
        return "LocalScript", base
    end
    base = string.match(fileName, "^(.*)%.luau?$")
    if base then
        return "ModuleScript", base
    end
    return nil, nil
end

local function mountDirectory(path, parent)
    local entries = fs.readDir(path)
    table.sort(entries)

    for _, entry in ipairs(entries) do
        local full = path .. "/" .. entry
        if fs.isDir(full) then
            local folder = mockNew("Folder", entry)
            folder.Parent = parent
            mountDirectory(full, folder)
        else
            local className, base = classifyFile(entry)
            if className then
                if parent:FindFirstChild(base) then
                    error("Dos archivos producen la misma instancia: " .. full)
                end
                local instance = mockNew(className, base)
                dataOf(instance).Source = fs.readFile(full)
                instance.Parent = parent
            end
        end
    end
end

function Engine.Reset(options)
    options = options or {}
    clockValue = 0
    table.clear(scheduled)
    table.clear(failures)
    table.clear(warnings)

    Engine.ModuleCache = {Server = {}, Client = {}}
    Engine.Kicked = {}
    Engine.LocalPlayer = nil
    Engine.Remotes = {}
    Engine.Sent = {}
    Engine.Options = options

    local gameRoot = mockNew("DataModel", "game")
    Engine.Game = gameRoot
    Engine.Services = {}

    local function service(className)
        local instance = Engine.Services[className]
        if not instance then
            instance = mockNew(className)
            instance.Parent = gameRoot
            Engine.Services[className] = instance
        end
        return instance
    end

    Engine.Workspace = service("Workspace")
    local runService = service("RunService")
    local players = service("Players")
    local collection = service("CollectionService")
    local tweenService = service("TweenService")
    local dataStores = service("DataStoreService")
    local analytics = service("AnalyticsService")
    local debris = service("Debris")
    local textService = service("TextService")
    local teleportService = service("TeleportService")
    local marketplace = service("MarketplaceService")
    Engine.UserInput = service("UserInputService")
    service("ReplicatedStorage")
    service("ServerScriptService")
    service("ServerStorage")
    service("StarterPlayer")
    service("Lighting")
    service("SoundService")
    local starterGui = service("StarterGui")

    -- Interfaz: la barra de Roblox ocupa 58 px arriba; la precarga avanza de a poco
    -- (o no termina nunca, con PreloadHang, para probar que la carga se va sola).
    local guiService = service("GuiService")
    rawset(guiService, "GetGuiInset", function()
        return roblox.Vector2.new(0, options.TopInset or 58), roblox.Vector2.new(0, 0)
    end)
    local contentProvider = service("ContentProvider")
    rawset(contentProvider, "PreloadAsync", function(_, list, callback)
        for _, item in ipairs(list) do
            taskLibrary.wait(options.PreloadHang and 1e6 or 0.05)
            if callback then
                callback(isMock(item) and item:GetFullName() or tostring(item), roblox.Enum.AssetFetchStatus.Success)
            end
        end
    end)
    service("Teams")
    service("ProximityPromptService")

    Engine.CoreSettings = {}
    rawset(starterGui, "SetCore", function(_, name, value)
        Engine.CoreSettings[name] = value
    end)

    Engine.Workspace.Terrain = mockNew("Terrain", "Terrain")
    Engine.Workspace.CurrentCamera = mockNew("Camera", "Camera")
    dataOf(Engine.Workspace.CurrentCamera).Values.ViewportSize = options.Viewport or roblox.Vector2.new(1280, 720)
    dataOf(Engine.UserInput).Values.TouchEnabled = options.Touch == true
    dataOf(Engine.UserInput).Values.KeyboardEnabled = options.Touch ~= true

    rawset(gameRoot, "GetService", function(_, name)
        return Engine.Services[name] or error("Servicio no simulado: " .. tostring(name))
    end)
    rawset(gameRoot, "IsLoaded", function()
        return true
    end)
    rawset(gameRoot, "BindToClose", function(_, callback)
        Engine.CloseHandlers = Engine.CloseHandlers or {}
        table.insert(Engine.CloseHandlers, callback)
    end)
    dataOf(gameRoot).Values.CreatorId = options.CreatorId or 1000
    dataOf(gameRoot).Values.CreatorType = roblox.Enum.CreatorType.User
    -- Sin PlaceId (como en Studio sin publicar) no hay viajes entre servidores.
    dataOf(gameRoot).Values.PlaceId = options.PlaceId or 0
    dataOf(gameRoot).Values.JobId = options.JobId or "job-local"
    dataOf(gameRoot).Values.PrivateServerId = options.PrivateServerId or ""
    dataOf(gameRoot).Values.PrivateServerOwnerId = options.PrivateServerOwnerId or 0

    rawset(Engine.Workspace, "GetServerTimeNow", function()
        return 1800000000 + clockValue
    end)
    rawset(Engine.Workspace, "Raycast", function(_, origin, direction, params)
        if Engine.RaycastOverride then
            return Engine.RaycastOverride(origin, direction, params)
        end
        return nil
    end)

    rawset(runService, "IsServer", function()
        return true
    end)
    rawset(runService, "IsClient", function()
        return false
    end)
    rawset(runService, "IsStudio", function()
        return options.Studio == true
    end)
    local renderBindings = {}
    rawset(runService, "BindToRenderStep", function(_, name, _, callback)
        local connection = signalFor(dataOf(runService), "RenderStepped"):Connect(callback)
        if renderBindings[name] then
            renderBindings[name].Disconnect()
        end
        renderBindings[name] = connection
    end)
    rawset(runService, "UnbindFromRenderStep", function(_, name)
        local connection = renderBindings[name]
        if connection then
            connection.Disconnect()
            renderBindings[name] = nil
        end
    end)
    Engine.RenderBindings = renderBindings

    rawset(players, "GetPlayers", function()
        return players:GetChildren()
    end)
    -- Avatar R15 mínimo (cabeza con cara, torso, brazos y piernas con sus
    -- articulaciones). Con AvatarOffline falla como sin conexión.
    Engine.AnimationLog = {}
    rawset(players, "CreateHumanoidModelFromDescription", function(_, description, rigType)
        if Engine.Options.AvatarOffline then
            error("HTTP 403 (Forbidden)")
        end
        assert(isMock(description) and description:IsA("HumanoidDescription"), "se esperaba una HumanoidDescription")
        assert(rigType == roblox.Enum.HumanoidRigType.R15, "se esperaba R15")
        local scale = description.HeightScale
        local rig = mockNew("Model", "Player")
        local function piece(name, size, parent0, c0, c1)
            local part = mockNew("MeshPart", name)
            part.Size = size * scale
            part.Parent = rig
            if parent0 then
                local motor = mockNew("Motor6D", name == "LowerTorso" and "Root" or name .. "Joint")
                motor.Part0 = parent0
                motor.Part1 = part
                motor.C0 = c0
                motor.C1 = c1
                motor.Parent = part
            end
            return part
        end
        local root = piece("HumanoidRootPart", roblox.Vector3.new(2, 2, 1))
        root.Transparency = 1
        local lower = piece("LowerTorso", roblox.Vector3.new(2, 0.4, 1), root, roblox.CFrame.new(), roblox.CFrame.new())
        local upper = piece("UpperTorso", roblox.Vector3.new(2, 1.6, 1), lower, roblox.CFrame.new(0, 0.2, 0), roblox.CFrame.new(0, -0.8, 0))
        local head = piece("Head", roblox.Vector3.new(1.2, 1.2, 1.2) * description.HeadScale, upper, roblox.CFrame.new(0, 0.8, 0), roblox.CFrame.new(0, -0.6, 0))
        mockNew("Decal", "face").Parent = head
        for _, side in ipairs({"Left", "Right"}) do
            local x = side == "Left" and -1 or 1
            piece(side .. "UpperArm", roblox.Vector3.new(1, 1.2, 1), upper, roblox.CFrame.new(x * 1.5, 0.5, 0), roblox.CFrame.new(0, 0.4, 0))
            piece(side .. "UpperLeg", roblox.Vector3.new(1, 1.2, 1), lower, roblox.CFrame.new(x * 0.5, -0.2, 0), roblox.CFrame.new(0, 0.6, 0))
        end
        local humanoid = mockNew("Humanoid", "Humanoid")
        humanoid.HipHeight = 2 * scale
        humanoid.Parent = rig
        mockNew("Animator", "Animator").Parent = humanoid
        rig.PrimaryPart = root
        return rig
    end)

    rawset(players, "GetPlayerByUserId", function(_, userId)
        for _, player in ipairs(players:GetChildren()) do
            if player.UserId == userId then
                return player
            end
        end
        return nil
    end)

    local tags = {}
    local addedSignals = {}
    local removedSignals = {}
    Engine.CollectionService = collection

    rawset(collection, "AddTag", function(_, instance, tag)
        tags[tag] = tags[tag] or {}
        if not table.find(tags[tag], instance) then
            table.insert(tags[tag], instance)
            if addedSignals[tag] then
                addedSignals[tag]:Fire(instance)
            end
        end
    end)
    rawset(collection, "HasTag", function(_, instance, tag)
        return tags[tag] ~= nil and table.find(tags[tag], instance) ~= nil
    end)
    rawset(collection, "GetTagged", function(_, tag)
        return table.clone(tags[tag] or {})
    end)
    rawset(collection, "GetInstanceAddedSignal", function(_, tag)
        addedSignals[tag] = addedSignals[tag] or Signal.new()
        return addedSignals[tag]
    end)
    rawset(collection, "GetInstanceRemovedSignal", function(_, tag)
        removedSignals[tag] = removedSignals[tag] or Signal.new()
        return removedSignals[tag]
    end)
    rawset(collection, "_forget", function(_, instance)
        for tag, list in pairs(tags) do
            local index = table.find(list, instance)
            if index then
                table.remove(list, index)
                if removedSignals[tag] then
                    removedSignals[tag]:Fire(instance)
                end
            end
        end
    end)

    rawset(tweenService, "Create", function(_, target, _, goal)
        return setmetatable({Target = target, Goal = goal, Completed = Signal.new()}, TweenStub)
    end)

    Engine.Stores = options.Stores or {}

    -- FailStore = {[nombre] = cantidad}: las próximas llamadas a ese almacén fallan.
    local function failing(name)
        local fails = Engine.Options.FailStore
        if fails and fails[name] and fails[name] > 0 then
            fails[name] -= 1
            error("502: API Services rejected request (" .. name .. ")")
        end
    end

    rawset(dataStores, "GetDataStore", function(_, name)
        if Engine.Options.DataStoreOffline then
            error("You must publish this place to the web to access DataStore.")
        end

        Engine.Stores[name] = Engine.Stores[name] or {}
        local contents = Engine.Stores[name]
        return {
            GetAsync = function(_, key)
                failing(name)
                local isProfile = string.sub(key, 1, 7) == "PLAYER_"
                if isProfile and Engine.Options.DataStoreFailures and Engine.Options.DataStoreFailures > 0 then
                    Engine.Options.DataStoreFailures -= 1
                    error("502: API Services rejected request")
                end
                return contents[key]
            end,
            SetAsync = function(_, key, value)
                failing(name)
                contents[key] = value
            end,
            RemoveAsync = function(_, key)
                failing(name)
                contents[key] = nil
            end,
            -- Como en Roblox, si la función devuelve nil no se escribe nada.
            UpdateAsync = function(_, key, transform)
                failing(name)
                local value = transform(contents[key])
                if value == nil then
                    return nil
                end
                contents[key] = value
                return value
            end,
        }
    end)

    rawset(dataStores, "GetOrderedDataStore", function(_, name)
        if Engine.Options.DataStoreOffline then
            error("You must publish this place to the web to access DataStore.")
        end

        Engine.Stores[name] = Engine.Stores[name] or {}
        local contents = Engine.Stores[name]
        local function checkValue(value)
            if type(value) ~= "number" or value % 1 ~= 0 then
                error("OrderedDataStore sólo guarda números enteros: " .. tostring(value))
            end
        end
        return {
            GetAsync = function(_, key)
                failing(name)
                return contents[key]
            end,
            SetAsync = function(_, key, value)
                failing(name)
                assert(type(key) == "string", "La clave de un OrderedDataStore es un texto")
                checkValue(value)
                contents[key] = value
            end,
            IncrementAsync = function(_, key, delta)
                failing(name)
                contents[key] = (contents[key] or 0) + (delta or 1)
                return contents[key]
            end,
            -- Como en Roblox, si la función devuelve nil no se escribe nada.
            UpdateAsync = function(_, key, transform)
                failing(name)
                assert(type(key) == "string", "La clave de un OrderedDataStore es un texto")
                local value = transform(contents[key])
                if value == nil then
                    return nil
                end
                checkValue(value)
                contents[key] = value
                return value
            end,
            RemoveAsync = function(_, key)
                failing(name)
                contents[key] = nil
            end,
            GetSortedAsync = function(_, ascending, pageSize)
                failing(name)
                assert(type(pageSize) == "number" and pageSize >= 1 and pageSize <= 100, "pageSize entre 1 y 100")
                local entries = {}
                for key, value in pairs(contents) do
                    table.insert(entries, {key = key, value = value})
                end
                table.sort(entries, function(a, b)
                    if a.value == b.value then
                        return a.key < b.key
                    end
                    if ascending then
                        return a.value < b.value
                    end
                    return a.value > b.value
                end)
                local page = {}
                for index = 1, math.min(pageSize, #entries) do
                    page[index] = entries[index]
                end
                return {
                    IsFinished = #entries <= pageSize,
                    GetCurrentPage = function()
                        return page
                    end,
                    AdvanceToNextPageAsync = function() end,
                }
            end,
        }
    end)

    -- Viajes entre servidores: se registran en Engine.Teleports y, salvo que la
    -- prueba pida lo contrario, los viajeros dejan el servidor un segundo después.
    Engine.Teleports = {}
    Engine.Reserved = {}
    local reserveCounter = 0
    rawset(teleportService, "ReserveServer", function(_, placeId)
        assert(type(placeId) == "number" and placeId > 0, "ReserveServer necesita un PlaceId publicado")
        if Engine.Options.ReserveFailures and Engine.Options.ReserveFailures > 0 then
            Engine.Options.ReserveFailures -= 1
            error("HTTP 503 (ReserveServer)")
        end
        reserveCounter += 1
        local code = "access-" .. reserveCounter
        table.insert(Engine.Reserved, code)
        return code, "reserved-" .. reserveCounter
    end)
    rawset(teleportService, "TeleportAsync", function(_, placeId, travellers, teleportOptions)
        assert(type(placeId) == "number" and placeId > 0, "TeleportAsync necesita un PlaceId publicado")
        assert(type(travellers) == "table" and #travellers > 0 and #travellers <= 50, "TeleportAsync necesita de 1 a 50 jugadores")
        if teleportOptions ~= nil then
            assert(isMock(teleportOptions) and teleportOptions.ClassName == "TeleportOptions", "Las opciones tienen que ser TeleportOptions")
        end
        if Engine.Options.TeleportFailures and Engine.Options.TeleportFailures > 0 then
            Engine.Options.TeleportFailures -= 1
            error("Teleport failed: HTTP 500")
        end

        local entry = {
            PlaceId = placeId,
            Players = table.clone(travellers),
            AccessCode = teleportOptions and teleportOptions.ReservedServerAccessCode or "",
            Data = teleportOptions and teleportOptions:GetTeleportData() or nil,
        }
        table.insert(Engine.Teleports, entry)
        if not Engine.Options.TeleportStays then
            for _, traveller in ipairs(travellers) do
                taskLibrary.delay(1, function()
                    if traveller.Parent == players then
                        Engine.RemovePlayer(traveller)
                    end
                end)
            end
        end
        return {PrivateServerId = "", ReservedServerAccessCode = entry.AccessCode}
    end)

    Engine.PurchasePrompts = {}
    rawset(marketplace, "PromptProductPurchase", function(_, player, productId)
        assert(type(productId) == "number" and productId > 0, "PromptProductPurchase con un id inválido")
        table.insert(Engine.PurchasePrompts, {Player = player, ProductId = productId})
    end)

    Engine.UserNames = options.UserNames or {}
    rawset(players, "GetNameFromUserIdAsync", function(_, userId)
        return Engine.UserNames[userId] or ("Usuario" .. tostring(userId))
    end)
    rawset(players, "CreateHumanoidModelFromUserId", function(_, userId)
        if Engine.Options.AvatarFailures then
            error("HTTP 500 (avatar)")
        end
        local model = mockNew("Model", "Avatar" .. tostring(userId))
        local humanoid = mockNew("Humanoid", "Humanoid")
        humanoid.Parent = model
        local root = mockNew("Part", "HumanoidRootPart")
        root.Size = roblox.Vector3.new(2, 2, 1)
        root.Parent = model
        for _, name in ipairs({"Head", "UpperTorso", "LowerTorso"}) do
            mockNew("Part", name).Parent = model
        end
        mockNew("LocalScript", "Animate").Parent = model
        model.PrimaryPart = root
        return model
    end)

    rawset(analytics, "LogCustomEvent", function(_, player, name)
        Engine.AnalyticsLog = Engine.AnalyticsLog or {}
        table.insert(Engine.AnalyticsLog, {Player = player, Name = name})
    end)
    Engine.AnalyticsLog = {}

    rawset(debris, "AddItem", function() end)
    rawset(textService, "FilterStringAsync", function(_, text)
        return {GetNonChatStringForBroadcastAsync = function()
            return text
        end}
    end)

    mountDirectory("src/shared", (function()
        local folder = mockNew("Folder", "Shared")
        folder.Parent = Engine.Services.ReplicatedStorage
        return folder
    end)())

    local serverFolder = mockNew("Folder", "Server")
    serverFolder.Parent = Engine.Services.ServerScriptService
    mountDirectory("src/server", serverFolder)

    local clientFolder = mockNew("Folder", "StarterPlayerScripts")
    clientFolder.Parent = Engine.Services.StarterPlayer
    mountDirectory("src/client", clientFolder)

    Engine.ServerFolder = serverFolder
    Engine.ClientFolder = clientFolder
    Engine.SharedFolder = Engine.Services.ReplicatedStorage:FindFirstChild("Shared")
end

function Engine.CountRemote(name)
    Engine.Remotes[name] = (Engine.Remotes[name] or 0) + 1
end

-- Guarda lo enviado a los clientes para que las pruebas lo inspeccionen.
function Engine.RecordRemote(name, player, ...)
    Engine.CountRemote(name)
    table.insert(Engine.Sent, {Name = name, Player = player, Args = table.pack(...)})
end

function Engine.LastSent(name, player)
    for index = #Engine.Sent, 1, -1 do
        local entry = Engine.Sent[index]
        if entry.Name == name and (entry.Player == nil or player == nil or entry.Player == player) then
            return entry.Args
        end
    end
    return nil
end

function Engine.StartServer()
    local main = Engine.ServerFolder:FindFirstChild("Main")
    local chunk = runChunk(dataOf(main).Source, "Server.Main", makeEnvironment("Server", main))
    taskLibrary.spawn(chunk)
end

function Engine.RequireServer(path)
    local current = Engine.ServerFolder
    for _, name in ipairs(string.split(path, ".")) do
        current = current:FindFirstChild(name)
        assert(current, "Módulo inexistente: " .. path)
    end
    return Engine.Require(current, "Server")
end

function Engine.RequireShared(path)
    local current = Engine.SharedFolder
    for _, name in ipairs(string.split(path, ".")) do
        current = current:FindFirstChild(name)
        assert(current, "Módulo inexistente: " .. path)
    end
    return Engine.Require(current, "Server")
end

function Engine.StartClient(player)
    Engine.LocalPlayer = player
    local players = Engine.Services.Players
    dataOf(players).Values.LocalPlayer = player

    local gui = mockNew("PlayerGui", "PlayerGui")
    gui.Parent = player

    local main = Engine.ClientFolder:FindFirstChild("Main")
    local chunk = runChunk(dataOf(main).Source, "Client.Main", makeEnvironment("Client", main))
    taskLibrary.spawn(chunk)
end

local userCounter = 1000

-- joinData simula lo que devuelve Player:GetJoinData() (por ejemplo TeleportData).
function Engine.AddPlayer(name, userId, joinData)
    userCounter += 1
    local player = mockNew("Player", name)
    dataOf(player).JoinData = joinData
    local values = dataOf(player).Values
    values.UserId = userId or userCounter
    values.DisplayName = name
    values.CameraMode = nil
    player.Parent = Engine.Services.Players
    signalFor(dataOf(Engine.Services.Players), "PlayerAdded"):Fire(player)
    return player
end

function Engine.RemovePlayer(player)
    signalFor(dataOf(Engine.Services.Players), "PlayerRemoving"):Fire(player)
    player.Parent = nil
end

function Engine.CreateCharacter(player)
    local character = mockNew("Model", dataOf(player).Name)
    local humanoid = mockNew("Humanoid", "Humanoid")
    humanoid.Parent = character
    dataOf(humanoid).Values.MoveDirection = roblox.Vector3.zero
    dataOf(humanoid).Values.CameraOffset = roblox.Vector3.zero
    dataOf(humanoid).Values.MaxHealth = 100
    dataOf(humanoid).Values.Health = 100

    local root = mockNew("Part", "HumanoidRootPart")
    root.Size = roblox.Vector3.new(2, 2, 1)
    root.CFrame = roblox.CFrame.new(0, 3, 0)
    root.Parent = character
    dataOf(root).Values.AssemblyLinearVelocity = roblox.Vector3.zero

    local head = mockNew("Part", "Head")
    head.Parent = character

    local regeneration = mockNew("Script", "Health")
    regeneration.Parent = character

    character.PrimaryPart = root
    character.Parent = Engine.Workspace
    dataOf(player).Values.Character = character
    signalFor(dataOf(player), "CharacterAdded"):Fire(character)
    return character
end

-- Avance del reloj ------------------------------------------------------------

local function runDue()
    local guard = 0
    while true do
        table.sort(scheduled, function(a, b)
            if a.At == b.At then
                return a.Sequence < b.Sequence
            end
            return a.At < b.At
        end)
        local first = scheduled[1]
        if not first or first.At > clockValue then
            return
        end
        table.remove(scheduled, 1)
        resume(first.Thread, table.unpack(first.Args, 1, first.Args.n))

        guard += 1
        if guard > 200000 then
            error("Bucle infinito en el planificador simulado")
        end
    end
end

function Engine.Step(deltaTime)
    clockValue += deltaTime
    runDue()
    local run = dataOf(Engine.Services.RunService)
    signalFor(run, "Heartbeat"):Fire(deltaTime)
    signalFor(run, "RenderStepped"):Fire(deltaTime)
end

function Engine.Run(seconds, step)
    step = step or 0.1
    local target = clockValue + seconds
    while clockValue < target do
        Engine.Step(step)
    end
end

-- Avanza hasta que se cumpla la condición; devuelve false si se agota el tiempo.
function Engine.RunUntil(condition, timeout, step)
    step = step or 0.1
    local deadline = clockValue + timeout
    while clockValue < deadline do
        Engine.Step(step)
        if condition() then
            return true
        end
    end
    return false
end

function Engine.Clock()
    return clockValue
end

-- Simula una tecla o un toque tal como los entrega UserInputService.
function Engine.Input(signalName, input)
    signalFor(dataOf(Engine.UserInput), signalName):Fire(input, false)
end

function Engine.GuiInput(button, signalName, input)
    signalFor(dataOf(button), signalName):Fire(input)
end

function Engine.Failures()
    return failures
end

-- Roblox entrega cada compra a MarketplaceService.ProcessReceipt; acá se llama igual.
function Engine.ProcessReceipt(receipt)
    local callback = dataOf(Engine.Services.MarketplaceService).Values.ProcessReceipt
    assert(type(callback) == "function", "MarketplaceService.ProcessReceipt no está definido")
    return callback(receipt)
end

function Engine.Warnings()
    return warnings
end

function Engine.IsMock(value)
    return isMock(value)
end

function Engine.Exit(code)
    process.exit(code)
end

Engine.Roblox = roblox

return Engine
