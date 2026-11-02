local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local updateRemote = remotes:WaitForChild("StoryUpdate")
local dialogueRemote = remotes:WaitForChild("StoryDialogue")
local noticeRemote = remotes:WaitForChild("StoryNotice")

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaStoryUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "MissionPanel"
panel.Size = UDim2.fromOffset(340, 112)
panel.Position = UDim2.new(0, 18, 0, 95)
panel.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Parent = gui

local chapterLabel = Instance.new("TextLabel")
chapterLabel.Size = UDim2.new(1, -20, 0, 28)
chapterLabel.Position = UDim2.fromOffset(10, 8)
chapterLabel.BackgroundTransparency = 1
chapterLabel.Font = Enum.Font.GothamBold
chapterLabel.TextSize = 17
chapterLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
chapterLabel.TextXAlignment = Enum.TextXAlignment.Left
chapterLabel.Text = "NOCTURNA"
chapterLabel.Parent = panel

local objectiveLabel = Instance.new("TextLabel")
objectiveLabel.Size = UDim2.new(1, -20, 0, 42)
objectiveLabel.Position = UDim2.fromOffset(10, 38)
objectiveLabel.BackgroundTransparency = 1
objectiveLabel.Font = Enum.Font.Gotham
objectiveLabel.TextSize = 14
objectiveLabel.TextWrapped = true
objectiveLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
objectiveLabel.TextXAlignment = Enum.TextXAlignment.Left
objectiveLabel.TextYAlignment = Enum.TextYAlignment.Top
objectiveLabel.Text = "Esperando misión..."
objectiveLabel.Parent = panel

local progressLabel = Instance.new("TextLabel")
progressLabel.Size = UDim2.new(1, -20, 0, 20)
progressLabel.Position = UDim2.fromOffset(10, 84)
progressLabel.BackgroundTransparency = 1
progressLabel.Font = Enum.Font.Gotham
progressLabel.TextSize = 12
progressLabel.TextColor3 = Color3.fromRGB(130, 145, 165)
progressLabel.TextXAlignment = Enum.TextXAlignment.Left
progressLabel.Text = ""
progressLabel.Parent = panel

local message = Instance.new("TextLabel")
message.Size = UDim2.new(0.8, 0, 0, 70)
message.Position = UDim2.new(0.1, 0, 0.72, 0)
message.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
message.BackgroundTransparency = 1
message.TextTransparency = 1
message.TextColor3 = Color3.fromRGB(235, 235, 240)
message.TextWrapped = true
message.Font = Enum.Font.GothamMedium
message.TextSize = 19
message.Parent = gui

local messageToken = 0

local function showMessage(text)
    messageToken += 1
    local token = messageToken
    message.Text = tostring(text)
    message.BackgroundTransparency = 0.2
    message.TextTransparency = 0

    task.delay(3.5, function()
        if token ~= messageToken then return end

        TweenService:Create(message, TweenInfo.new(0.6), {
            TextTransparency = 1,
            BackgroundTransparency = 1,
        }):Play()
    end)
end

updateRemote.OnClientEvent:Connect(function(data)
    if typeof(data) ~= "table" then return end

    chapterLabel.Text = "CAPÍTULO " .. tostring(data.Chapter)
        .. " — " .. tostring(data.ChapterName)
    objectiveLabel.Text = data.Finished
        and "Has llegado al final de la historia."
        or tostring(data.Objective)
    progressLabel.Text = data.Finished
        and "CAMPAÑA COMPLETADA"
        or ("OBJETIVO " .. tostring(data.ObjectiveNumber)
            .. " / " .. tostring(data.TotalObjectives))
end)

dialogueRemote.OnClientEvent:Connect(showMessage)
noticeRemote.OnClientEvent:Connect(showMessage)
