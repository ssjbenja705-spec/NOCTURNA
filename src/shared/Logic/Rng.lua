-- Generador xorshift32 determinista: la misma semilla produce el mismo mapa
-- en el servidor y en las pruebas fuera de Roblox.
local Rng = {}
Rng.__index = Rng

function Rng.new(seed)
    local state = bit32.bxor(math.floor(seed or 0) % 4294967296, 0x9E3779B9)
    if state == 0 then
        state = 0x6D2B79F5
    end

    local self = setmetatable({State = state}, Rng)
    for _ = 1, 8 do
        self:NextUInt()
    end
    return self
end

function Rng:NextUInt()
    local x = self.State
    x = bit32.bxor(x, bit32.lshift(x, 13))
    x = bit32.bxor(x, bit32.rshift(x, 17))
    x = bit32.bxor(x, bit32.lshift(x, 5))
    self.State = x
    return x
end

function Rng:Float()
    return self:NextUInt() / 4294967296
end

function Rng:Int(min, max)
    return min + self:NextUInt() % (max - min + 1)
end

function Rng:Chance(probability)
    return self:Float() < probability
end

function Rng:Pick(list)
    return list[self:Int(1, #list)]
end

function Rng:Shuffle(list)
    for index = #list, 2, -1 do
        local other = self:Int(1, index)
        list[index], list[other] = list[other], list[index]
    end
    return list
end

return Rng
