local function setupPrompt(prompt)
    if not prompt:IsA("ProximityPrompt") or prompt:GetAttribute("NocturnaConnected") then
        return
    end

    prompt:SetAttribute("NocturnaConnected", true)
    prompt.Triggered:Connect(function(player)
        local itemId = prompt:GetAttribute("ItemId")
        local inventory = _G.NocturnaInventory
        if typeof(itemId) ~= "string" or not inventory then return end

        if inventory.AddItem(player, itemId, 1) then
            local itemObject = prompt:FindFirstAncestorOfClass("Model") or prompt.Parent
            if itemObject and itemObject:GetAttribute("DestroyOnPickup") == true then
                itemObject:Destroy()
            end
        end
    end)
end

for _, object in ipairs(workspace:GetDescendants()) do
    setupPrompt(object)
end
workspace.DescendantAdded:Connect(setupPrompt)

print("[NOCTURNA] Interacciones preparadas.")