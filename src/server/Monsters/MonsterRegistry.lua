local Registry = {}

Registry.Monsters = {
    Oyente = {Name = "El Oyente", Behavior = "Investiga sonidos"},
    Imitador = {Name = "El Imitador", Behavior = "Atrae con voces falsas"},
    Quieto = {Name = "El Quieto", Behavior = "Acecha cuando no lo miran"},
    Trepador = {Name = "El Trepador", Behavior = "Se desplaza por superficies"},
    Coloso = {Name = "El Coloso", Behavior = "Provoca persecuciones y cambios del entorno"},
}

function Registry.Get(name)
    return Registry.Monsters[name]
end

return Registry
