--!strict
--[[
    ClientNet (ModuleScript) -> StarterPlayer > StarterPlayerScripts > ClientNet
    Busca un RemoteEvent del servidor SIN avisos de "Infinite yield":
      1) espera (máx. 10 s) la marca ReplicatedStorage:GetAttribute("RemotesReady") que pone Net al crear todo
      2) busca el remote con tiempo límite; si no existe devuelve nil y avisa UNA vez (el script que lo pide decide qué hacer)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientNet = {}
local warned: { [string]: boolean } = {}

local function waitReady()
	local t = 0
	while not ReplicatedStorage:GetAttribute("RemotesReady") and t < 10 do
		task.wait(0.1)
		t += 0.1
	end
end

function ClientNet.Get(name: string): RemoteEvent?
	waitReady()
	local folder = ReplicatedStorage:WaitForChild("Remotes", 10)
	local r = folder and folder:WaitForChild(name, 10)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	if not warned[name] then
		warned[name] = true
		warn("[ClientNet] No se encontró el RemoteEvent '" .. name .. "' (¿está actualizado Services/Net en el servidor?)")
	end
	return nil
end

return ClientNet
