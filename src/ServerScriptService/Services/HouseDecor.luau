--!strict
-- Decoración fija de la Casa VIP (salón, vestíbulo y jardín). Solo estética: nada de esto tiene prompts.
-- Build(model, origen, ancho, alto, GZ, colorFacción, nombreDueño)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HouseFurniture = require(ReplicatedStorage.Modules.HouseFurniture)

local HouseDecor = {}

local GOLD = Color3.fromRGB(240, 196, 90)
local STONE = Color3.fromRGB(214, 204, 186)
local WOOD = Color3.fromRGB(96, 66, 42)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanCollide = collide ~= false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

function HouseDecor.Build(m: Model, o: Vector3, W: number, H: number, GZ: number, accent: Color3, ownerName: string)
	local deco = Instance.new("Folder")
	deco.Name = "Decor"
	deco.Parent = m
	local function at(x: number, y: number, z: number, ry: number?): CFrame
		return CFrame.new(o + Vector3.new(x, y, z)) * CFrame.Angles(0, math.rad(ry or 0), 0)
	end
	local function light(p: BasePart, range: number, bright: number, color: Color3)
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color = range, bright, color
		l.Parent = p
	end

	-- SUELO DE AJEDREZ en el vestíbulo
	for ix = -3, 3 do
		for iz = 0, 3 do
			local dark = (ix + iz) % 2 == 0
			part(deco, "Baldosa", Vector3.new(8, 0.12, 8), at(ix * 8, 1.32, -66 + iz * 8 + 4), if dark then Color3.fromRGB(40, 40, 52) else Color3.fromRGB(238, 232, 218), Enum.Material.Marble, false)
		end
	end

	-- PÓRTICO DE SALIDA: arco dorado con velo luminoso
	for _, sx in ipairs({ -7, 7 }) do
		part(deco, "ArcoPilar", Vector3.new(2.4, 16, 2.4), at(sx, 9, -64), GOLD, Enum.Material.Metal)
	end
	part(deco, "ArcoDintel", Vector3.new(18, 2.4, 3), at(0, 17.5, -64), GOLD, Enum.Material.Metal)
	local gem = part(deco, "ArcoGema", Vector3.new(2.6, 2.6, 2.6), at(0, 20.2, -64) * CFrame.Angles(math.rad(45), 0, math.rad(45)), accent, Enum.Material.Neon, false)
	light(gem, 30, 1.5, accent)
	local veil = part(deco, "Velo", Vector3.new(12, 15, 0.4), at(0, 9, -64.5), Color3.fromRGB(255, 255, 255), Enum.Material.ForceField, false)
	veil.Transparency = 0.55

	-- PLACA con el nombre del dueño sobre el arco de entrada al jardín
	local plaque = part(deco, "Placa", Vector3.new(30, 5, 1), at(0, 20, 9.2), WOOD, Enum.Material.Wood, false)
	part(deco, "PlacaOro", Vector3.new(31.4, 6.4, 0.6), at(0, 20, 9.6), GOLD, Enum.Material.Metal, false)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = plaque
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "🏠 Casa de " .. ownerName
	lbl.Font = Enum.Font.Fantasy
	lbl.TextScaled = true
	lbl.TextColor3 = GOLD
	lbl.Parent = gui
	-- pilares dorados del hueco de la división
	for _, sx in ipairs({ -14.5, 14.5 }) do
		part(deco, "PilarDivision", Vector3.new(3, 16, 3), at(sx, 8, 10), GOLD, Enum.Material.Metal)
	end

	-- SALONES: sofás con mesita a cada lado de la alfombra
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 26
		part(deco, "SofaBase", Vector3.new(6, 2, 14), at(x + side * 3, 2.3, -44, 0), Color3.fromRGB(120, 36, 52), Enum.Material.Fabric)
		part(deco, "SofaRespaldo", Vector3.new(1.6, 4, 14), at(x + side * 5.6, 4.2, -44, 0), Color3.fromRGB(120, 36, 52), Enum.Material.Fabric)
		for _, dz in ipairs({ -6.8, 6.8 }) do
			part(deco, "SofaBrazo", Vector3.new(6, 3.4, 1.4), at(x + side * 3, 3.2, -44 + dz, 0), Color3.fromRGB(100, 28, 44), Enum.Material.Fabric)
		end
		for _, dz in ipairs({ -47.5, -40.5 }) do
			local sp = o + Vector3.new(x + side * 3, 3.9, dz)
			HouseFurniture.MakeSeat(deco, CFrame.lookAt(sp, sp + Vector3.new(-side, 0, 0)))
		end
		part(deco, "MesitaTapa", Vector3.new(6, 0.5, 6), at(x - side * 2, 3.4, -44, 0), WOOD, Enum.Material.Wood)
		part(deco, "MesitaPata", Vector3.new(1, 2.2, 1), at(x - side * 2, 2.2, -44, 0), GOLD, Enum.Material.Metal)
		part(deco, "Vela", Vector3.new(0.5, 1.2, 0.5), at(x - side * 2, 4.2, -44, 0), Color3.fromRGB(255, 245, 220), Enum.Material.SmoothPlastic, false)
		local fl = part(deco, "Llama", Vector3.new(0.5, 0.7, 0.5), at(x - side * 2, 5.1, -44, 0), Color3.fromRGB(255, 190, 80), Enum.Material.Neon, false)
		light(fl, 14, 1.2, Color3.fromRGB(255, 190, 110))

		-- BIBLIOTECA contra el muro lateral
		local wx = side * (W / 2 - 3)
		part(deco, "EstanteFondo", Vector3.new(3, 14, 22), at(wx, 8, -18), WOOD, Enum.Material.Wood)
		for row = 0, 3 do
			part(deco, "Balda", Vector3.new(3.4, 0.5, 22), at(wx - side * 0.2, 2.5 + row * 3.4, -18), GOLD, Enum.Material.Wood, false)
			for k = 0, 8 do
				local c = Color3.fromHSV((row * 0.13 + k * 0.071) % 1, 0.55, 0.8)
				part(deco, "Libro", Vector3.new(2, 2.4, 1.2), at(wx - side * 1.6, 3.9 + row * 3.4, -27 + k * 2.1), c, Enum.Material.SmoothPlastic, false)
			end
		end

		-- ESTANDARTES de la facción entre las columnas
		for _, dz in ipairs({ -45, -15 }) do
			local bx = side * (W / 2 - 1.6)
			part(deco, "VaraEstandarte", Vector3.new(0.4, 0.4, 6), at(bx, 26, dz), GOLD, Enum.Material.Metal, false)
			part(deco, "Estandarte", Vector3.new(0.3, 14, 5), at(bx, 19, dz), accent, Enum.Material.Fabric, false)
			part(deco, "EstandarteBorde", Vector3.new(0.4, 1.2, 5.4), at(bx, 12, dz), GOLD, Enum.Material.Metal, false)
		end
		-- VENTANALES con luz de atardecer
		for _, dz in ipairs({ -52, -6 }) do
			local win = part(deco, "Ventana", Vector3.new(0.6, 12, 8), at(side * (W / 2 - 0.8), 16, dz), Color3.fromRGB(255, 214, 150), Enum.Material.Neon, false)
			win.Transparency = 0.35
			part(deco, "VentanaMarco", Vector3.new(0.9, 13, 1), at(side * (W / 2 - 0.9), 16, dz - 4), GOLD, Enum.Material.Metal, false)
			part(deco, "VentanaMarco", Vector3.new(0.9, 13, 1), at(side * (W / 2 - 0.9), 16, dz + 4), GOLD, Enum.Material.Metal, false)
		end
		-- MACETAS grandes junto a las columnas
		for _, dz in ipairs({ -58, -2 }) do
			local px = side * 26
			part(deco, "Maceta", Vector3.new(3.6, 3, 3.6), at(px, 2.8, dz), Color3.fromRGB(176, 92, 60), Enum.Material.Slate, true, Enum.PartType.Cylinder).CFrame = at(px, 2.8, dz) * CFrame.Angles(0, 0, math.rad(90))
			part(deco, "Planta", Vector3.new(5, 5, 5), at(px, 6.2, dz), Color3.fromRGB(64, 150, 70), Enum.Material.Grass, false, Enum.PartType.Ball)
		end
	end

	-- CHIMENEA en el muro sur, a la izquierda del portal
	local fx, fz = 0, -68.2
	part(deco, "ChimeneaMarco", Vector3.new(16, 11, 2), at(fx - 26, 6.5, fz), Color3.fromRGB(120, 108, 96), Enum.Material.Brick, false)
	part(deco, "ChimeneaHueco", Vector3.new(9, 6.5, 2.2), at(fx - 26, 4.6, fz + 0.1), Color3.fromRGB(26, 22, 22), Enum.Material.Slate, false)
	part(deco, "ChimeneaRepisa", Vector3.new(18, 1, 3), at(fx - 26, 12.4, fz + 0.5), GOLD, Enum.Material.Wood, false)
	local fire = part(deco, "Fuego", Vector3.new(3, 1, 1.4), at(fx - 26, 2.4, fz + 0.8), Color3.fromRGB(255, 130, 40), Enum.Material.Neon, false)
	local f = Instance.new("Fire")
	f.Size, f.Heat = 6, 8
	f.Parent = fire
	light(fire, 28, 1.6, Color3.fromRGB(255, 150, 80))

	-- LÁMPARA: aro de velas alrededor del candelabro central
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part(deco, "AroVela", Vector3.new(0.7, 1.6, 0.7), at(math.cos(a) * 7, H - 5, -30 + math.sin(a) * 7), Color3.fromRGB(255, 240, 210), Enum.Material.SmoothPlastic, false)
		part(deco, "AroLlama", Vector3.new(0.5, 0.7, 0.5), at(math.cos(a) * 7, H - 3.8, -30 + math.sin(a) * 7), Color3.fromRGB(255, 200, 100), Enum.Material.Neon, false)
	end
	part(deco, "AroOro", Vector3.new(14.6, 0.6, 14.6), at(0, H - 5.9, -30), GOLD, Enum.Material.Metal, false, Enum.PartType.Cylinder).CFrame = at(0, H - 5.9, -30) * CFrame.Angles(0, 0, math.rad(90))

	-- JARDÍN: sendero de piedra desde el arco hasta la fuente
	for i = 0, 5 do
		part(deco, "Sendero", Vector3.new(7, 0.2, 6), at(math.sin(i * 0.8) * 2, 1.5, 16 + i * 6), Color3.fromRGB(176, 170, 160), Enum.Material.Cobblestone, false)
	end
	for i = 0, 3 do
		for _, side in ipairs({ -1, 1 }) do
			local z = 18 + i * 10
			part(deco, "FarolPoste", Vector3.new(0.8, 7, 0.8), at(side * 7, 5, z), Color3.fromRGB(40, 40, 48), Enum.Material.Metal)
			local lamp = part(deco, "FarolLuz", Vector3.new(1.8, 1.8, 1.8), at(side * 7, 9, z), Color3.fromRGB(255, 226, 150), Enum.Material.Neon, false)
			light(lamp, 24, 1.3, Color3.fromRGB(255, 226, 160))
		end
	end

	-- FUENTE central con agua
	local fcx, fcz = 0, GZ + 14
	part(deco, "FuenteBase", Vector3.new(1.6, 14, 14), at(fcx, 2.4, fcz), Color3.fromRGB(190, 184, 172), Enum.Material.Marble, true, Enum.PartType.Cylinder).CFrame = at(fcx, 2.4, fcz) * CFrame.Angles(0, 0, math.rad(90))
	local water = part(deco, "FuenteAgua", Vector3.new(0.4, 12, 12), at(fcx, 3.3, fcz), Color3.fromRGB(80, 170, 230), Enum.Material.Glass, false, Enum.PartType.Cylinder)
	water.CFrame = at(fcx, 3.3, fcz) * CFrame.Angles(0, 0, math.rad(90))
	water.Transparency = 0.35
	part(deco, "FuentePilar", Vector3.new(6, 2.4, 2.4), at(fcx, 5.5, fcz), STONE, Enum.Material.Marble, true, Enum.PartType.Cylinder).CFrame = at(fcx, 5.5, fcz) * CFrame.Angles(0, 0, math.rad(90))
	part(deco, "FuenteCopa", Vector3.new(0.6, 6, 6), at(fcx, 8.6, fcz), STONE, Enum.Material.Marble, false, Enum.PartType.Cylinder).CFrame = at(fcx, 8.6, fcz) * CFrame.Angles(0, 0, math.rad(90))
	local spout = part(deco, "FuenteChorro", Vector3.new(1, 1, 1), at(fcx, 9.2, fcz), Color3.fromRGB(255, 255, 255), Enum.Material.Glass, false)
	spout.Transparency = 1
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 60
	pe.Lifetime = NumberRange.new(1.2, 1.8)
	pe.Speed = NumberRange.new(12, 15)
	pe.SpreadAngle = Vector2.new(22, 22)
	pe.Acceleration = Vector3.new(0, -30, 0)
	pe.Size = NumberSequence.new(0.5, 0.15)
	pe.Color = ColorSequence.new(Color3.fromRGB(180, 225, 255))
	pe.Transparency = NumberSequence.new(0.2, 1)
	pe.LightEmission = 0.5
	pe.Parent = spout

	-- PARTERRES de flores a los costados del sendero
	local cols = { Color3.fromRGB(255, 120, 150), Color3.fromRGB(255, 220, 90), Color3.fromRGB(190, 130, 255), Color3.fromRGB(255, 255, 255) }
	for _, side in ipairs({ -1, 1 }) do
		local bx = side * 13
		part(deco, "ParterreBorde", Vector3.new(14, 1, 20), at(bx, 1.8, GZ - 3), Color3.fromRGB(140, 110, 80), Enum.Material.Wood, false)
		part(deco, "ParterreTierra", Vector3.new(12.4, 1.2, 18.4), at(bx, 2, GZ - 3), Color3.fromRGB(76, 52, 36), Enum.Material.Ground, false)
		for i = 0, 17 do
			local fx2 = bx + ((i % 3) - 1) * 3.4
			local fz2 = GZ - 3 - 7.5 + math.floor(i / 3) * 3
			part(deco, "Tallo", Vector3.new(0.2, 1.6, 0.2), at(fx2, 3, fz2), Color3.fromRGB(60, 140, 60), Enum.Material.Grass, false)
			part(deco, "Flor", Vector3.new(1.2, 1.2, 1.2), at(fx2, 4, fz2), cols[(i % #cols) + 1], Enum.Material.SmoothPlastic, false, Enum.PartType.Ball)
		end
	end

	-- BANCOS junto a la fuente
	for _, side in ipairs({ -1, 1 }) do
		part(deco, "BancoAsiento", Vector3.new(10, 0.8, 3), at(side * 14, 2.8, fcz + 12, 0), WOOD, Enum.Material.Wood)
		for _, dx in ipairs({ -2.5, 2.5 }) do
			local sp = o + Vector3.new(side * 14 + dx, 3.7, fcz + 12)
			HouseFurniture.MakeSeat(deco, CFrame.lookAt(sp, sp + Vector3.new(0, 0, -1)))
		end
		part(deco, "BancoRespaldo", Vector3.new(10, 3, 0.6), at(side * 14, 4.6, fcz + 13.6, 0), WOOD, Enum.Material.Wood)
		for _, dx in ipairs({ -4, 4 }) do
			part(deco, "BancoPata", Vector3.new(0.8, 2.4, 2.4), at(side * 14 + dx, 1.9, fcz + 12), GOLD, Enum.Material.Metal, false)
		end
	end

	-- ÁRBOLES en las esquinas del jardín
	for _, c in ipairs({ { -56, GZ + 16 }, { 56, GZ + 16 }, { -56, GZ - 8 }, { 56, GZ - 8 } }) do
		part(deco, "Tronco", Vector3.new(3, 14, 3), at(c[1], 8, c[2]), Color3.fromRGB(104, 72, 46), Enum.Material.Wood)
		local crown = part(deco, "Copa", Vector3.new(16, 14, 16), at(c[1], 19, c[2]), Color3.fromRGB(80, 168, 90), Enum.Material.Grass, false, Enum.PartType.Ball)
		crown.Color = Color3.fromRGB(255, 170, 190)
		part(deco, "CopaVerde", Vector3.new(12, 10, 12), at(c[1], 21, c[2]), Color3.fromRGB(70, 156, 84), Enum.Material.Grass, false, Enum.PartType.Ball)
	end

	-- LUCIÉRNAGAS por todo el jardín
	local flies = part(deco, "Luciernagas", Vector3.new(120, 14, 46), at(0, 9, 45), Color3.fromRGB(255, 255, 160), Enum.Material.SmoothPlastic, false)
	flies.Transparency = 1
	local fe = Instance.new("ParticleEmitter")
	fe.Rate = 14
	fe.Lifetime = NumberRange.new(5, 8)
	fe.Speed = NumberRange.new(0.5, 1.5)
	fe.SpreadAngle = Vector2.new(180, 180)
	fe.Size = NumberSequence.new(0.35)
	fe.Color = ColorSequence.new(Color3.fromRGB(255, 250, 150))
	fe.LightEmission = 1
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 1) })
	fe.EmitterShape = Enum.ParticleEmitterShape.Box
	fe.Parent = flies

	-- LÍRIOS en el estanque
	for i = 0, 5 do
		part(deco, "Nenufar", Vector3.new(0.2, 3, 3), at(-30 + (i % 3 - 1) * 6, 1.65, GZ + 14 + (math.floor(i / 3) - 0.5) * 6), Color3.fromRGB(70, 160, 80), Enum.Material.Grass, false, Enum.PartType.Cylinder).CFrame = at(-30 + (i % 3 - 1) * 6, 1.65, GZ + 14 + (math.floor(i / 3) - 0.5) * 6) * CFrame.Angles(0, 0, math.rad(90))
	end
	return deco
end

return HouseDecor
