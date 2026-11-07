-- Votación del final: cada jugador elige qué hacer con Alma.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local OPTION_HEIGHT = 92

local EndingUI = {}

function EndingUI.Start()
    local root = Theme.Screen("NocturnaEnding", 30)

    local panel, heading, close = Theme.Window(root, "EndingVote", "", 580, 430)
    close.Visible = false
    heading.Font = Theme.Fonts.Display
    heading.TextSize = 32
    heading.TextColor3 = Colors.Danger
    heading.Text = "¿QUÉ VAS A HACER?"
    Theme.Flicker(heading)

    local question = Theme.Label(panel, {
        Name = "Question",
        Position = UDim2.fromOffset(20, 58),
        Size = UDim2.new(1, -40, 0, 26),
        Text = "Alma no te reconoce. El Núcleo late.",
        TextSize = 17,
        TextColor3 = Colors.TextDim,
    })

    local countdown = Theme.Label(panel, {
        Name = "Countdown",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -10),
        Size = UDim2.new(1, -40, 0, 20),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local buttons = {}
    local deadline = 0
    local chosen = nil
    local shownSeconds = -1

    local function clearButtons()
        for _, entry in pairs(buttons) do
            entry.Button:Destroy()
        end
        table.clear(buttons)
        chosen = nil
    end

    local function paint()
        for id, entry in pairs(buttons) do
            local selected = id == chosen
            entry.Button.BackgroundColor3 = selected and Colors.ButtonActive or Colors.Button
            entry.Stroke.Color = selected and Colors.Accent or Colors.Stroke
            entry.Mine.Visible = selected
        end
    end

    Remotes.OnClient("EndingPrompt", function(data)
        clearButtons()
        deadline = os.clock() + data.Duration
        shownSeconds = -1
        Theme.Typewrite(question, "Alma no te reconoce. El Núcleo late.", 40)

        for index, option in ipairs(data.Options) do
            local button = Theme.Button(panel, "", {
                Name = "Option",
                Position = UDim2.fromOffset(20, 92 + (index - 1) * (OPTION_HEIGHT + 8)),
                Size = UDim2.new(1, -40, 0, OPTION_HEIGHT),
            })
            Theme.Label(button, {
                Name = "Choice",
                Position = UDim2.fromOffset(14, 8),
                Size = UDim2.new(1, -110, 0, 22),
                Text = option.Option,
                TextSize = 18,
                TextWrapped = false,
            })
            Theme.Label(button, {
                Name = "Description",
                Position = UDim2.fromOffset(14, 34),
                Size = UDim2.new(1, -28, 1, -40),
                Text = option.Description,
                TextSize = 14,
                TextColor3 = Colors.TextDim,
            })
            local votes = Theme.Label(button, {
                Name = "Votes",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, 8),
                Size = UDim2.fromOffset(90, 22),
                Text = "",
                TextSize = 14,
                TextColor3 = Colors.Accent,
                TextXAlignment = Enum.TextXAlignment.Right,
            })
            local mine = Theme.Label(button, {
                Name = "Mine",
                AnchorPoint = Vector2.new(1, 1),
                Position = UDim2.new(1, -12, 1, -6),
                Size = UDim2.fromOffset(110, 18),
                Text = "TU VOTO",
                TextSize = 13,
                TextColor3 = Colors.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                Visible = false,
            })
            buttons[option.Id] = {
                Button = button,
                Option = option,
                Votes = votes,
                Mine = mine,
                Stroke = button:FindFirstChildOfClass("UIStroke"),
            }

            button.Activated:Connect(function()
                Remotes.FireServer("EndingVote", option.Id)
                chosen = option.Id
                paint()
            end)
        end

        panel.Visible = true
        Theme.SetModal("Ending", true)
    end)

    Remotes.OnClient("EndingVotes", function(counts)
        for id, entry in pairs(buttons) do
            local votes = counts[id] or 0
            entry.Votes.Text = votes == 1 and "1 voto" or string.format("%d votos", votes)
        end
    end)

    Remotes.OnClient("Cutscene", function()
        panel.Visible = false
        Theme.SetModal("Ending", false)
    end)

    RunService.Heartbeat:Connect(function()
        if not panel.Visible then
            return
        end
        local seconds = math.max(0, math.ceil(deadline - os.clock()))
        if seconds ~= shownSeconds then
            shownSeconds = seconds
            countdown.Text = string.format("Decisión en %d s", seconds)
        end
    end)
end

return EndingUI
