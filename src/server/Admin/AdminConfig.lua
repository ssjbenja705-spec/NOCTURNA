-- Quién puede usar las herramientas de moderación. Vive en el servidor: el cliente
-- no necesita ni debe conocer esta lista.
return {
    -- UserId de Roblox de cada administrador.
    AdminUserIds = {},
    -- El dueño de la experiencia (o el grupo dueño, con rango 255) es administrador.
    AllowCreator = true,
    -- Rango mínimo de grupo que cuenta como administrador. nil = sólo el dueño.
    MinimumGroupRank = nil,
    -- En Studio todos son administradores, para poder probar.
    AllowInStudio = true,
    MaxBanDays = 365,
    MaxLogEntries = 100,
}
