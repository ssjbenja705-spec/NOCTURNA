-- Entrada de movimiento y linterna. Unifica teclado, mando y táctil: sólo se envían
-- pedidos al servidor, que es quien decide velocidad y batería.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)

local player = Players.LocalPlayer

local MovementInput = {}
local sprinting = false
local crouching = false

function MovementInput.SetSprinting(value)
    if sprinting == value then
        return
    end
    sprinting = value
    if value then
        crouching = false
    end
    Remotes.FireServer("SprintRequest", value)
end

function MovementInput.SetCrouching(value)
    if crouching == value then
        return
    end
    crouching = value
    Remotes.FireServer("CrouchRequest", value)
end

function MovementInput.ToggleCrouch()
    MovementInput.SetCrouching(not crouching)
    return crouching
end

-- Acción contextual (persecución final): mientras hay un manejador, Espacio y C
-- (o A y B en el mando) pueden ser saltar y agacharse en vez de sigilo. El
-- manejador devuelve true si usó la tecla.
local actionHandler = nil

function MovementInput.SetActionHandler(handler)
    actionHandler = handler
end

function MovementInput.Start()
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end

        local key = input.KeyCode
        if actionHandler and actionHandler(key) then
            return
        end
        if key == Enum.KeyCode.LeftShift or key == Enum.KeyCode.ButtonL3 then
            MovementInput.SetSprinting(true)
        elseif key == Enum.KeyCode.LeftControl or key == Enum.KeyCode.C or key == Enum.KeyCode.ButtonR3 then
            MovementInput.ToggleCrouch()
        elseif key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonX then
            Remotes.FireServer("FlashlightToggle")
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL3 then
            MovementInput.SetSprinting(false)
        end
    end)

    UserInputService.WindowFocusReleased:Connect(function()
        MovementInput.SetSprinting(false)
    end)

    player.CharacterAdded:Connect(function()
        sprinting = false
        crouching = false
    end)
end

return MovementInput
