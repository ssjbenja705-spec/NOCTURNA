-- NOCTURNA: Document Progression Hook

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local eventFolder = ServerScriptService:WaitForChild(
    "NocturnaProgressionEvents"
)

local documentEvent = eventFolder:WaitForChild("DocumentCollected")

local debounce = {}

local function onPromptTriggered(prompt, player)
    if not player or not player:IsA("Player") then
        return
    end

    local isDocument =
        CollectionService:HasTag(prompt, "NocturnaDocument")
        or prompt:GetAttribute("IsNocturnaDocument") == true

    if not isDocument then
        return
    end

    local documentId = prompt:GetAttribute("DocumentId")

    if typeof(documentId) ~= "string" or documentId == "" then
        warn("[NOCTURNA] Documento sin atributo DocumentId:", prompt:GetFullName())
        return
    end

    local key = tostring(player.UserId) .. ":" .. documentId

    if debounce[key] then
        return
    end

    debounce[key] = true
    documentEvent:Fire(player, documentId)

    print("[NOCTURNA] Documento registrado:", player.Name, documentId)
end

ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

Players.PlayerRemoving:Connect(function(player)
    local prefix = tostring(player.UserId) .. ":"

    for key in pairs(debounce) do
        if string.sub(key, 1, #prefix) == prefix then
            debounce[key] = nil
        end
    end
end)

print("[NOCTURNA] Sistema de documentos conectado.")
