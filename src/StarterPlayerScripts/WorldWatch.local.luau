--!strict
--[[
    WorldWatch (LocalScript) -> StarterPlayer > StarterPlayerScripts > WorldWatch
    DIAGNÓSTICO de la carga del mundo: escribe en la consola (F9 > Client) qué ve TU pantalla a los 2, 5, 10, 20 y 40 s:
    si existe el mapa, cuántas carpetas "Estilo" tiene y qué dice el servidor (WorldReady, construcciones del mapa...).
    Si el estilo desaparece entre una línea y otra, el mapa fue reemplazado en el servidor (mira también su consola: [WorldReadyService]).
]]
local Workspace = game:GetService("Workspace")

local started = os.clock()
for _, delaySeconds in ipairs({ 2, 5, 10, 20, 40 }) do
	task.delay(delaySeconds, function()
		local map = Workspace:FindFirstChild("Map_WC3_Style")
		local folders, parts = 0, 0
		if map then
			for _, d in ipairs(map:GetDescendants()) do
				if d:IsA("Folder") and d.Name == "Estilo" then
					folders += 1
					parts += #d:GetDescendants()
				end
			end
		end
		print(string.format(
			"[WorldWatch] t=%.0fs mapa=%s hijos=%d · Estilo=%d (%d partes) · servidor: WorldReady=%s esperaba=%s construcciones=%s",
			os.clock() - started, tostring(map ~= nil), if map then #map:GetChildren() else 0, folders, parts,
			tostring(Workspace:GetAttribute("WorldReady")), tostring(Workspace:GetAttribute("WorldStyleFolders")), tostring(Workspace:GetAttribute("MapBuildCount"))
			))
	end)
end
