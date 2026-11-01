--!strict
--[[
    CityStyleCheck (LocalScript) -> StarterPlayer > StarterPlayerScripts > CityStyleCheck
    Diagnóstico del estilo de ciudades y Arena. Muestra 20 s un cartel en pantalla y lo escribe en la consola (F9 > Client).
      · "Servidor v6.55" + carpetas Estilo > 0  -> todo cargó bien.
      · "SERVIDOR SIN ESTILO" -> la partida web corre una versión VIEJA del juego: falta PUBLICAR el lugar
        (Studio: File > Publish to Roblox) o los scripts nuevos no están en ese lugar. No es un error de código.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

task.delay(12, function()
	local map = Workspace:FindFirstChild("Map_WC3_Style")
	local estilos, partes, gradas = 0, 0, 0
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("Folder") and d.Name == "Estilo" then
				estilos += 1
				partes += #d:GetDescendants()
			elseif d:IsA("Folder") and d.Name == "Gradas" then
				gradas += 1
			end
		end
	end
	local ver = Workspace:GetAttribute("StyleVersion")
	local ciudad = Workspace:GetAttribute("CityStyleStatus")
	local texto = string.format(
		"[CityStyleCheck] mapa=%s · Estilo=%d · partes=%d · gradas=%d · servidor: %s · ciudades: %s · arena: %s · streaming=%s",
		tostring(map ~= nil), estilos, partes, gradas, tostring(ver), tostring(ciudad),
		tostring(Workspace:GetAttribute("ArenaTheme")), tostring(Workspace.StreamingEnabled)
	)
	print(texto)

	local ok = ver ~= nil and estilos > 0
	local gui = Instance.new("ScreenGui")
	gui.Name = "CityStyleCheckGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 1)
	l.Position = UDim2.new(0.5, 0, 1, -8)
	l.Size = UDim2.fromOffset(520, 40)
	l.BackgroundColor3 = if ok then Color3.fromRGB(20, 70, 30) else Color3.fromRGB(110, 25, 25)
	l.BackgroundTransparency = 0.15
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 13
	l.TextWrapped = true
	l.Text = if ok
		then string.format("Servidor v%s · estilo cargado (%d zonas, %d partes, %d gradas)", tostring(ver), estilos, partes, gradas)
		else "SERVIDOR SIN ESTILO NUEVO: esta partida corre una versión vieja (falta publicar el lugar) o el estilo no se generó. Revisa F9 > Server."
	l.Parent = gui
	Instance.new("UICorner", l).CornerRadius = UDim.new(0, 8)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	task.delay(20, function()
		gui:Destroy()
	end)
end)
