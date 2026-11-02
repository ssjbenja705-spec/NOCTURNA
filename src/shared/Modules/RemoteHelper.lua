local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteHelper = {}

local function getFolder()
    return ReplicatedStorage:WaitForChild("NocturnaRemotes")
end

function RemoteHelper.Get(name)
    return getFolder():WaitForChild(name)
end

function RemoteHelper.FireServer(name, ...)
    RemoteHelper.Get(name):FireServer(...)
end

function RemoteHelper.FireClient(name, player, ...)
    RemoteHelper.Get(name):FireClient(player, ...)
end

function RemoteHelper.FireAll(name, ...)
    RemoteHelper.Get(name):FireAllClients(...)
end

return RemoteHelper
