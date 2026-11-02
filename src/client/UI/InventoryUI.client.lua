local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local inventoryUpdate = remotes:WaitForChild("InventoryUpdate")
local itemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ItemConfig"))

local gui = Instance.new("ScreenGui")
gui.Name = "NocturnaInventory"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "InventoryPanel"
panel.Size = UDim2.fromOffset(230, 150)
panel.Position = UDim2.new(1, -245, 0, 20)
panel.BackgroundColor3 = Color3.fromRGB(12, 14, 19)
panel.BackgroundTransparency = 0.15
panel.Parent = gui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.Text = "INVENTARIO"
title.TextColor3 = Color3.fromRGB(220, 220, 220)
title.TextSize = 18
title.Font = Enum.Font.GothamBold
title.Parent = panel

local content = Instance.new("TextLabel")
content.Position = UDim2.fromOffset(10, 35)
content.Size = UDim2.new(1, -20, 1, -45)
content.BackgroundTransparency = 1
content.TextColor3 = Color3.fromRGB(190, 200, 210)
content.TextSize = 14
content.TextXAlignment = Enum.TextXAlignment.Left
content.TextYAlignment = Enum.TextYAlignment.Top
content.Font = Enum.Font.Gotham
content.Text = "Todavía no tienes objetos."
content.Parent = panel

inventoryUpdate.OnClientEvent:Connect(function(items)
    local lines = {}
    if type(items) == "table" then
        for _, slot in ipairs(items) do
            if type(slot) == "table" and type(slot.Id) == "string" and type(slot.Amount) == "number" then
                local definition = itemConfig[slot.Id]
                local itemName = definition and definition.DisplayName or slot.Id
                table.insert(lines, tostring(itemName) .. " x" .. tostring(slot.Amount))
            end
        end
    end

    table.sort(lines)
    content.Text = #lines > 0
        and table.concat(lines, "\n")
        or "Todavía no tienes objetos."
end)
