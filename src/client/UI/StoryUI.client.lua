local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local missionRemote = remotes:WaitForChild("MissionUpdate")
local storyRemote = remotes:WaitForChild("StoryUpdate")
local dialogueRemote = remotes:WaitForChild("StoryDialogue")
local noticeRemote = remotes:WaitForChild("StoryNotice")

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaStoryUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "MissionPanel"
panel.Size = UDim2.new(0.34, 0, 0, 112)
panel.Position = UDim2.new(0.025, 0, 0.13, 0)
panel.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel

local function label(name, position, size, textSize, bold)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Position = position
    item.Size = size
    item.BackgroundTransparency = 1
    item.TextColor3 = Color3.fromRGB(220, 225, 230)
    item.TextSize = textSize
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    item.Parent = panel
    return item
end

local chapterLabel = label("Chapter", UDim2.fromOffset(10, 7), UDim2.new(1, -20, 0, 28), 16, true)
chapterLabel.Text = "NOCTURNA"
local objectiveLabel = label("Objective", UDim2.fromOffset(10, 37), UDim2.new(1, -20, 0, 43), 14, false)
objectiveLabel.Text = "Preparando la misión..."
local progressLabel = label("Progress", UDim2.fromOffset(10, 83), UDim2.new(1, -20, 0, 20), 12, false)

local message = Instance.new("TextLabel")
message.Name = "DialogueMessage"
message.AnchorPoint = Vector2.new(0.5, 0.5)
message.Position = UDim2.fromScale(0.5, 0.78)
message.Size = UDim2.new(0.78, 0, 0, 72)
message.BackgroundColor3 = Color3.fromRGB(7, 9, 13)
message.BackgroundTransparency = 1
message.TextColor3 = Color3.fromRGB(240, 240, 245)
message.TextTransparency = 1
message.TextWrapped = true
message.TextSize = 19
message.Font = Enum.Font.GothamMedium
message.Parent = gui

local token = 0
local function showMessage(value)
    token += 1
    local current = token
    message.Text = tostring(value)
    message.BackgroundTransparency = 0.18
    message.TextTransparency = 0
    task.delay(3.5, function()
        if token ~= current then return end
        TweenService:Create(message, TweenInfo.new(0.5), {
            BackgroundTransparency = 1,
            TextTransparency = 1,
        }):Play()
    end)
end

local function renderMission(data)
    if typeof(data) ~= "table" then return end
    local chapterNumber = tonumber(string.match(tostring(data.missionId or ""), "^CHAPTER_(%d+)$")) or 1
    chapterLabel.Text = "CAPÍTULO " .. chapterNumber
    if data.finished then
        objectiveLabel.Text = "Capítulo completado. Busca la siguiente zona."
    else
        local nextObjective
        for id, isDone in pairs(data.objectives or {}) do
            if not isDone then
                nextObjective = id
                break
            end
        end
        objectiveLabel.Text = nextObjective and ("Objetivo: " .. nextObjective) or "Continúa explorando..."
    end
    progressLabel.Text = string.format("%d / %d objetivos", data.completed or 0, data.total or 0)
end

missionRemote.OnClientEvent:Connect(renderMission)
storyRemote.OnClientEvent:Connect(function(data)
    if typeof(data) == "table" and data.Chapter then
        chapterLabel.Text = "CAPÍTULO " .. tostring(data.Chapter) .. " — " .. tostring(data.ChapterName or "")
    end
end)
dialogueRemote.OnClientEvent:Connect(showMessage)
noticeRemote.OnClientEvent:Connect(showMessage)
