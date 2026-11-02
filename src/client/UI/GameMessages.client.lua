local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local gui = player:WaitForChild("PlayerGui"):WaitForChild("NocturnaHUD")

local message = Instance.new("TextLabel")
message.Name = "AdminMessageLabel"
message.Size = UDim2.new(0.7, 0, 0, 42)
message.Position = UDim2.new(0.15, 0, 0.88, 0)
message.BackgroundColor3 = Color3.fromRGB(10, 12, 15)
message.BackgroundTransparency = 1
message.TextColor3 = Color3.fromRGB(220, 225, 225)
message.TextTransparency = 1
message.TextWrapped = true
message.TextScaled = true
message.Font = Enum.Font.Gotham
message.Parent = gui

local messageToken = 0
remotes:WaitForChild("AdminMessage").OnClientEvent:Connect(function(text)
    messageToken += 1
    local token = messageToken
    message.Text = tostring(text)
    message.BackgroundTransparency = 0.35
    message.TextTransparency = 0

    task.delay(3.5, function()
        if token ~= messageToken then return end
        TweenService:Create(message, TweenInfo.new(0.6), {
            BackgroundTransparency = 1,
            TextTransparency = 1,
        }):Play()
    end)
end)
