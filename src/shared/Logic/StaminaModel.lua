-- Resistencia del sprint. Lógica pura compartida por servidor y pruebas.
local StaminaModel = {}

function StaminaModel.new(config)
    return {
        Stamina = config.MaxStamina,
        Sprinting = false,
        Exhausted = false,
    }
end

function StaminaModel.Request(state, wantsSprint)
    state.Sprinting = wantsSprint == true and state.Stamina > 0 and not state.Exhausted
    return state.Sprinting
end

function StaminaModel.Step(state, deltaTime, moving, config)
    if state.Sprinting and moving and not state.Exhausted then
        state.Stamina = math.max(0, state.Stamina - config.StaminaDrain * deltaTime)
        if state.Stamina <= 0 then
            state.Exhausted = true
            state.Sprinting = false
        end
    else
        local recovery = state.Exhausted and config.ExhaustedRecovery or config.StaminaRecovery
        state.Stamina = math.min(config.MaxStamina, state.Stamina + recovery * deltaTime)
        if state.Stamina >= config.ExhaustedUnlock then
            state.Exhausted = false
        end
    end

    return state
end

function StaminaModel.Speed(state, crouching, config)
    if crouching then
        return config.CrouchSpeed
    end
    return state.Sprinting and config.SprintSpeed or config.WalkSpeed
end

return StaminaModel
