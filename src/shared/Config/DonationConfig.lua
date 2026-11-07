-- Donaciones: un producto de desarrollador por monto (100 R$, y de 200 a 10000 R$ de
-- 200 en 200). Cada uno se crea en Creator Hub y su id se pega acá (ver
-- docs/DONACIONES.md). Un monto con id 0 no aparece en el juego.
local DonationConfig = {}

DonationConfig.Products = {
    {Robux = 100, ProductId = 3729365183},
    {Robux = 200, ProductId = 3729365740},
    {Robux = 400, ProductId = 3729365854},
    {Robux = 600, ProductId = 3729365859},
    {Robux = 800, ProductId = 3729365867},
    {Robux = 1000, ProductId = 3729365870},
    {Robux = 1200, ProductId = 3729365876},
    {Robux = 1400, ProductId = 3729365883},
    {Robux = 1600, ProductId = 3729365894},
    {Robux = 1800, ProductId = 3729365900},
    {Robux = 2000, ProductId = 3729365908},
    {Robux = 2200, ProductId = 3729365917},
    {Robux = 2400, ProductId = 3729365927},
    {Robux = 2600, ProductId = 3729365934},
    {Robux = 2800, ProductId = 3729365938},
    {Robux = 3000, ProductId = 3729365942},
    {Robux = 3200, ProductId = 3729365951},
    {Robux = 3400, ProductId = 3729365958},
    {Robux = 3600, ProductId = 3729365967},
    {Robux = 3800, ProductId = 3729365978},
    {Robux = 4000, ProductId = 3729365985},
    {Robux = 4200, ProductId = 3729365993},
    {Robux = 4400, ProductId = 3729366005},
    {Robux = 4600, ProductId = 3729366011},
    {Robux = 4800, ProductId = 3729366017},
    {Robux = 5000, ProductId = 3729366021},
    {Robux = 5200, ProductId = 3729366033},
    {Robux = 5400, ProductId = 3729366048},
    {Robux = 5600, ProductId = 3729366057},
    {Robux = 5800, ProductId = 3729366067},
    {Robux = 6000, ProductId = 3729366075},
    {Robux = 6200, ProductId = 3729366086},
    {Robux = 6400, ProductId = 3729366098},
    {Robux = 6600, ProductId = 3729366105},
    {Robux = 6800, ProductId = 3729366115},
    {Robux = 7000, ProductId = 3729366125},
    {Robux = 7200, ProductId = 3729366134},
    {Robux = 7400, ProductId = 3729366141},
    {Robux = 7600, ProductId = 3729366149},
    {Robux = 7800, ProductId = 3729366159},
    {Robux = 8000, ProductId = 3729366164},
    {Robux = 8200, ProductId = 3729366171},
    {Robux = 8400, ProductId = 3729366175},
    {Robux = 8600, ProductId = 3729366183},
    {Robux = 8800, ProductId = 3729366192},
    {Robux = 9000, ProductId = 3729366201},
    {Robux = 9200, ProductId = 3729366213},
    {Robux = 9400, ProductId = 3729366223},
    {Robux = 9600, ProductId = 3729366229},
    {Robux = 9800, ProductId = 3729366239},
    {Robux = 10000, ProductId = 3729366252},
}

local function isValidId(productId)
    return type(productId) == "number" and productId > 0 and productId % 1 == 0
end

-- Montos que el jugador puede elegir: sólo los que ya tienen su producto creado.
function DonationConfig.Visible()
    local visible = {}
    for _, product in ipairs(DonationConfig.Products) do
        if isValidId(product.ProductId) then
            table.insert(visible, product)
        end
    end
    return visible
end

-- El monto se toma siempre de esta tabla, nunca de lo que diga el cliente.
function DonationConfig.FindByProductId(productId)
    if not isValidId(productId) then
        return nil
    end
    for _, product in ipairs(DonationConfig.Products) do
        if product.ProductId == productId then
            return product
        end
    end
    return nil
end

-- 12400 -> "12.400"
function DonationConfig.FormatRobux(amount)
    local text = tostring(math.floor(tonumber(amount) or 0))
    local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1.")))
    if string.sub(formatted, 1, 1) == "." then
        formatted = string.sub(formatted, 2)
    end
    return formatted
end

return DonationConfig
