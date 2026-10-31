--!strict
--[[
    CityStyleCheck (LocalScript) -> StarterPlayer > StarterPlayerScripts > CityStyleCheck
    Diagnóstico: a los 12 s de entrar escribe en la consola (F9 > Client) si el estilo de las ciudades y de la Arena llegó
    al cliente y cuántos adornos hay cargados. Si dice 0, el mapa no se replicó (o el servidor es una versión vieja).
]]
local Workspace = game:GetService("Workspace")

task.delay(12, function()
	local map = Workspace:FindFirstChild("Map_WC3_Style")
	local estilos = 0
	local partes = 0
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("Folder") and d.Name == "Estilo" then
				estilos += 1
				partes += #d:GetDescendants()
			end
		end
	end
	print(string.format(
		"[CityStyleCheck] mapa=%s · carpetas Estilo=%d · partes de estilo cargadas=%d · servidor dice: %s · tema arena: %s · streaming=%s",
		tostring(map ~= nil), estilos, partes, tostring(Workspace:GetAttribute("CityStyleStatus")),
		tostring(Workspace:GetAttribute("ArenaTheme")), tostring(Workspace.StreamingEnabled)
		))
end)
