--!strict
--[[
    HallClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HallClient
    El Secretario del Gremio (Salón de Honor) abre la ventana del Gremio.
]]
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

ClientNet.Get("HallOpen").OnClientEvent:Connect(function()
	MenuBus.Fire("Guild")
end)
