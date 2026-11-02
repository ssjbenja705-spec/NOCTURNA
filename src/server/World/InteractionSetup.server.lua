local CollectionService = game:GetService("CollectionService")

local function setup(object)
    if not object:IsA("BasePart") then return end
    if not object:GetAttribute("Interactable") then return end
    if object:FindFirstChildOfClass("ProximityPrompt") then return end

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = object:GetAttribute("ActionText") or "Interactuar"
    prompt.ObjectText = object:GetAttribute("DisplayName") or object.Name
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.HoldDuration = 0.5
    prompt.MaxActivationDistance = 10
    prompt.Parent = object
end

for _, object in ipairs(CollectionService:GetTagged("Interactable")) do
    setup(object)
end

CollectionService:GetInstanceAddedSignal("Interactable"):Connect(setup)
