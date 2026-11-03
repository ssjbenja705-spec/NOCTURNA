-- Votación del final: cada jugador elige qué hacer con Alma.
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors

local EndingUI = {}

function EndingUI.Start()
    local root = Theme.Screen("NocturnaEnding", 30)

    local panel = Theme.Panel(root, {
        Name = "EndingVote",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(540, 390),
        BackgroundTransparency = 0.02,
        Visible = false,
    })

    Theme.Label(panel, {
        Position = UDim2.fromOffset(20, 16),
        Size = UDim2.new(1, -40, 0, 56),
        Text = "Alma no te reconoce. El Núcleo late. ¿Qué vas a hacer?",
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local countdown = Theme.Label(panel, {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -10),
        Size = UDim2.new(1, -40, 0, 18),
        TextSize = 12,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    local buttons = {}
    local deadline = 0

    local function clearButtons()
        for _, entry in pairs(buttons) do
            entry.Button:Destroy()
        end
        table.clear(buttons)
    end

    Remotes.OnClient("EndingPrompt", function(data)
        clearButtons()
        deadline = os.clock() + data.Duration

        for index, option in ipairs(data.Options) do
            local button = Theme.Button(panel, "", {
                Position = UDim2.fromOffset(20, 76 + (index - 1) * 92),
                Size = UDim2.new(1, -40, 0, 84),
                TextSize = 14,
                TextWrapped = true,
            })
            buttons[option.Id] = {Button = button, Option = option}
            button.Text = option.Option .. "\n" .. option.Description

            button.Activated:Connect(function()
                Remotes.FireServer("EndingVote", option.Id)
                for id, entry in pairs(buttons) do
                    entry.Button.BackgroundColor3 = id == option.Id and Colors.ButtonActive or Colors.Button
                end
            end)
        end

        panel.Visible = true
        Theme.SetModal("Ending", true)
    end)

    Remotes.OnClient("EndingVotes", function(counts)
        for id, entry in pairs(buttons) do
            local votes = counts[id] or 0
            entry.Button.Text = string.format("%s  (%d)\n%s", entry.Option.Option, votes, entry.Option.Description)
        end
    end)

    Remotes.OnClient("Cutscene", function()
        panel.Visible = false
        Theme.SetModal("Ending", false)
    end)

    RunService.Heartbeat:Connect(function()
        if panel.Visible then
            countdown.Text = string.format("Decisión en %d s", math.max(0, math.ceil(deadline - os.clock())))
        end
    end)
end

return EndingUI
