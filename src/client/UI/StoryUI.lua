-- Subtítulos de diálogo, avisos breves y anuncios de administración.
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local SPEAKER_COLORS = {
    Vos = Color3.fromRGB(200, 214, 224),
    Radio = Color3.fromRGB(150, 200, 170),
    Alma = Color3.fromRGB(240, 196, 150),
    ["Dra. Vega"] = Color3.fromRGB(180, 180, 230),
}

local StoryUI = {}
local subtitlesEnabled = true
local displayLine = nil

local function fader(label, background)
    local token = 0
    return function(text, duration)
        token += 1
        local current = token
        label.Text = text
        label.TextTransparency = 0
        if background then
            background.BackgroundTransparency = 0.25
            background.Visible = true
        end

        task.delay(duration, function()
            if current ~= token then
                return
            end
            local info = TweenInfo.new(0.5)
            TweenService:Create(label, info, {TextTransparency = 1}):Play()
            if background then
                TweenService:Create(background, info, {BackgroundTransparency = 1}):Play()
            end
        end)
    end
end

function StoryUI.ShowLine(data)
    if not subtitlesEnabled or typeof(data) ~= "table" or not displayLine then
        return
    end
    local color = SPEAKER_COLORS[data.Speaker] or Colors.Accent
    local hex = color:ToHex()
    displayLine(string.format('<font color="#%s"><b>%s:</b></font> %s', hex, data.Speaker or "", data.Text or ""), 3.4)
end

function StoryUI.Start()
    local root = Theme.Screen("NocturnaStory", 5)

    local box = Theme.Panel(root, {
        Name = "Dialogue",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, Theme.IsTouch and -110 or -28),
        Size = UDim2.fromOffset(600, 66),
        BackgroundTransparency = 1,
        Visible = false,
    })
    local line = Theme.Label(box, {
        RichText = true,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -28, 1, -16),
        TextSize = 17,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = 1,
    })
    displayLine = fader(line, box)

    local notice = Theme.Label(root, {
        Name = "Notice",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 112),
        Size = UDim2.fromOffset(520, 44),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTransparency = 1,
    })
    local showNotice = fader(notice)

    Remotes.OnClient("StoryDialogue", StoryUI.ShowLine)
    Remotes.OnClient("StoryNotice", function(text)
        showNotice(tostring(text), 3)
    end)
    Remotes.OnClient("AdminMessage", function(text)
        showNotice("[ANUNCIO] " .. tostring(text), 5)
    end)

    ClientState.Subscribe("Profile", function(profile)
        subtitlesEnabled = profile.Settings.Subtitles
    end)
end

return StoryUI
