-- NOCTURNA: controles táctiles de sprint.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage
    :WaitForChild("NocturnaRemotes")
    :WaitForChild("SprintRequest")

local ACTION_NAME = "NocturnaMobileSprint"
local sprinting = false

local function setSprint(enabled)
    if sprinting == enabled then
        return
    end

    sprinting = enabled
    remote:FireServer(enabled)
end

local function handleSprint(_, inputState)
    if inputState == Enum.UserInputState.Begin then
        setSprint(true)
    elseif inputState == Enum.UserInputState.End
        or inputState == Enum.UserInputState.Cancel then
        setSprint(false)
    end

    return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(
    ACTION_NAME,
    handleSprint,
    true,
    Enum.KeyCode.ButtonL3
)

ContextActionService:SetTitle(ACTION_NAME, "CORRER")
ContextActionService:SetPosition(
    ACTION_NAME,
    UDim2.new(0.78, 0, 0.62, 0)
)

player.CharacterAdded:Connect(function()
    setSprint(false)
end)

player.CharacterRemoving:Connect(function()
    setSprint(false)
end)
