local DamageService = {}

function DamageService.ApplyDamage(player, amount)
    if not player or typeof(amount) ~= "number" then
        return false
    end

    if amount <= 0 or amount > 100 then
        return false
    end

    local character = player.Character
    if not character then return false end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false
    end

    humanoid:TakeDamage(amount)
    return true
end

function DamageService.Heal(player, amount)
    if not player or typeof(amount) ~= "number" or amount <= 0 or amount > 100 then
        return false
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    if humanoid.Health >= humanoid.MaxHealth then return false end

    humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
    return true
end

return DamageService
