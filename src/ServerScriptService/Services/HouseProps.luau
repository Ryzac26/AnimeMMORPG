--!strict
--[[
    HouseProps (ModuleScript) -> ServerScriptService.Services.HouseProps
    Piezas grandes de la Casa VIP con diseño propio (solo geometría; los prompts los pone HouseService):
      Chest(m, o)    cofre del tesoro sobre un estrado, con antorchas, tapiz y monedas  -> devuelve la pieza del prompt
      Board(m, o)    tablón de invitados pegado a la pared este, con papeles y farolillos   -> idem
      Hut(m, o, gz)  caseta de mascotas con tejado a dos aguas, heno, cuencos y letrero    -> idem (mostrador)
      Switch(m, o, x, y, z, faceZ) interruptor de pared; devuelve (placa, bombilla)
]]
local HouseProps = {}

local GOLD = Color3.fromRGB(240, 196, 90)
local IRON = Color3.fromRGB(52, 54, 62)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?, collide: boolean?): Part
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

local function light(p: BasePart, range: number, bright: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range, l.Brightness, l.Color = range, bright, color
	l.Parent = p
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, font: Enum.Font?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = font or Enum.Font.Fantasy
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.Parent = gui
end

local function torch(m: Instance, pos: Vector3)
	part(m, "AntorchaPie", Vector3.new(1.4, 0.8, 1.4), CFrame.new(pos + Vector3.new(0, 0.4, 0)), IRON, Enum.Material.Metal)
	part(m, "AntorchaPoste", Vector3.new(0.6, 7, 0.6), CFrame.new(pos + Vector3.new(0, 4, 0)), IRON, Enum.Material.Metal)
	part(m, "AntorchaCopa", Vector3.new(1.6, 0.9, 1.6), CFrame.new(pos + Vector3.new(0, 7.7, 0)), GOLD, Enum.Material.Metal)
	local f = part(m, "AntorchaFuego", Vector3.new(1, 1, 1), CFrame.new(pos + Vector3.new(0, 8.4, 0)), Color3.fromRGB(255, 150, 50), Enum.Material.Neon, nil, false)
	f.Transparency = 0.4
	local fire = Instance.new("Fire")
	fire.Size, fire.Heat = 5, 7
	fire.Parent = f
	light(f, 26, 1.2, Color3.fromRGB(255, 170, 90))
end

-- COFRE DEL TESORO (pared oeste, de cara al este)
function HouseProps.Chest(m: Instance, o: Vector3): Part
	local cx, cz = -58, -30
	local function A(x: number, y: number, z: number): CFrame
		return CFrame.new(o + Vector3.new(cx + x, y, cz + z))
	end
	local stone = Color3.fromRGB(176, 168, 156)
	local wood = Color3.fromRGB(104, 66, 38)
	local darkWood = Color3.fromRGB(78, 48, 28)
	-- estrado de piedra con dos escalones y alfombra
	part(m, "CofreEscalon", Vector3.new(18, 0.6, 20), A(0, 1.5, 0), stone, Enum.Material.Cobblestone)
	part(m, "CofreEstrado", Vector3.new(14, 0.8, 16), A(-1, 2.0, 0), Color3.fromRGB(196, 188, 174), Enum.Material.Marble)
	part(m, "CofreAlfombra", Vector3.new(10, 0.15, 12), A(-0.5, 2.45, 0), Color3.fromRGB(120, 30, 50), Enum.Material.Fabric, nil, false)
	-- cuerpo del cofre (largo en Z)
	local body = part(m, "Baul", Vector3.new(6, 4.4, 10), A(-1.5, 4.7, 0), wood, Enum.Material.WoodPlanks)
	part(m, "BaulBase", Vector3.new(6.4, 0.6, 10.4), A(-1.5, 2.8, 0), IRON, Enum.Material.Metal)
	-- tapa curva (medio cilindro: el cilindro cruza el cuerpo y la mitad de abajo queda dentro)
	local lid = part(m, "BaulTapa", Vector3.new(10, 6, 6), A(-1.5, 6.9, 0) * CFrame.Angles(0, math.rad(90), 0), darkWood, Enum.Material.WoodPlanks, Enum.PartType.Cylinder, false)
	lid.Name = "BaulTapa"
	-- cintas de hierro alrededor del cuerpo y la tapa
	for _, dz in ipairs({ -3.6, 0, 3.6 }) do
		part(m, "BaulCinta", Vector3.new(6.3, 4.5, 0.7), A(-1.5, 4.7, dz), IRON, Enum.Material.Metal)
		part(m, "BaulCintaTapa", Vector3.new(0.7, 6.3, 6.3), A(-1.5, 6.9, dz) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal, Enum.PartType.Cylinder, false)
	end
	-- esquineras y remaches dorados
	for _, dz in ipairs({ -5, 5 }) do
		for _, dx in ipairs({ -3, 3 }) do
			part(m, "BaulEsquina", Vector3.new(0.9, 4.6, 0.9), A(-1.5 + dx, 4.7, dz), GOLD, Enum.Material.Metal)
		end
	end
	-- cerradura dorada con gema
	part(m, "BaulCerradura", Vector3.new(0.5, 2.2, 2.2), A(1.55, 6.3, 0), GOLD, Enum.Material.Metal, nil, false)
	local gem = part(m, "BaulGema", Vector3.new(0.6, 1.1, 1.1), A(1.8, 6.3, 0), Color3.fromRGB(120, 220, 255), Enum.Material.Neon, nil, false)
	light(gem, 22, 1.4, Color3.fromRGB(150, 225, 255))
	-- resplandor dorado que se escapa por la tapa y destellos
	local glow = part(m, "BaulBrillo", Vector3.new(5, 0.3, 9), A(-1.5, 9.8, 0), GOLD, Enum.Material.Neon, nil, false)
	glow.Transparency = 1
	light(glow, 30, 1.4, Color3.fromRGB(255, 214, 120))
	local sp = Instance.new("ParticleEmitter")
	sp.Rate = 10
	sp.Lifetime = NumberRange.new(1.5, 2.5)
	sp.Speed = NumberRange.new(2, 4)
	sp.SpreadAngle = Vector2.new(30, 30)
	sp.Size = NumberSequence.new(0.35, 0)
	sp.Color = ColorSequence.new(GOLD)
	sp.LightEmission = 1
	sp.Transparency = NumberSequence.new(0.1, 1)
	sp.Acceleration = Vector3.new(0, 1.5, 0)
	sp.Parent = glow
	-- montones de monedas y gemas
	for i = 0, 6 do
		part(m, "Moneda", Vector3.new(0.25, 1.6, 1.6), A(-5 + (i % 3) * 0.6, 2.55 + math.floor(i / 3) * 0.28, -6 + (i % 2) * 0.3), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder, false)
	end
	for i = 0, 3 do
		local colors = { Color3.fromRGB(235, 70, 90), Color3.fromRGB(90, 200, 255), Color3.fromRGB(120, 255, 150), Color3.fromRGB(220, 140, 255) }
		part(m, "Gema", Vector3.new(0.8, 0.8, 0.8), A(-4.5 + i * 0.9, 2.85, 6.3 - (i % 2) * 0.5) * CFrame.Angles(math.rad(45), math.rad(30 * i), math.rad(45)), colors[i + 1], Enum.Material.Neon, nil, false)
	end
	-- tapiz del gremio en la pared y antorchas a los lados
	local wallX = -69
	part(m, "CofreTapizVara", Vector3.new(0.4, 0.5, 14), CFrame.new(o + Vector3.new(wallX + 1, 22, cz)), GOLD, Enum.Material.Metal, nil, false)
	local tap = part(m, "CofreTapiz", Vector3.new(0.3, 12, 12), CFrame.new(o + Vector3.new(wallX + 1, 16, cz)), Color3.fromRGB(110, 28, 52), Enum.Material.Fabric, nil, false)
	label(tap, Enum.NormalId.Right, "⚜", GOLD, Enum.Font.GothamBold)
	part(m, "CofreTapizOro", Vector3.new(0.4, 0.6, 12.4), CFrame.new(o + Vector3.new(wallX + 1.05, 10.2, cz)), GOLD, Enum.Material.Metal, nil, false)
	torch(m, o + Vector3.new(cx - 3, 2.4, cz - 10.5))
	torch(m, o + Vector3.new(cx - 3, 2.4, cz + 10.5))
	return body
end

-- TABLÓN DE INVITADOS (pared este, mira al oeste)
function HouseProps.Board(m: Instance, o: Vector3): Part
	local bx, bz = 67.6, -30
	local wood = Color3.fromRGB(104, 70, 44)
	local function A(x: number, y: number, z: number): CFrame
		return CFrame.new(o + Vector3.new(bx + x, y, bz + z))
	end
	local back = part(m, "Tablon", Vector3.new(1.2, 9, 15), A(0, 8, 0), wood, Enum.Material.WoodPlanks, nil, false)
	part(m, "TablonCorcho", Vector3.new(0.4, 7, 13), A(-0.7, 7.6, 0), Color3.fromRGB(176, 130, 82), Enum.Material.Wood, nil, false)
	-- marco dorado
	part(m, "TablonMarcoSup", Vector3.new(1.6, 0.8, 15.8), A(-0.2, 12.4, 0), GOLD, Enum.Material.Metal, nil, false)
	part(m, "TablonMarcoInf", Vector3.new(1.6, 0.8, 15.8), A(-0.2, 3.6, 0), GOLD, Enum.Material.Metal, nil, false)
	for _, dz in ipairs({ -7.7, 7.7 }) do
		part(m, "TablonMarcoLado", Vector3.new(1.6, 9, 0.8), A(-0.2, 8, dz), GOLD, Enum.Material.Metal, nil, false)
	end
	-- tejadillo
	local roof = part(m, "TablonTecho", Vector3.new(3.2, 0.7, 17), A(-1, 13.4, 0) * CFrame.Angles(0, 0, math.rad(-18)), Color3.fromRGB(120, 40, 50), Enum.Material.Slate, nil, false)
	roof.Name = "TablonTecho"
	-- letrero superior
	local head = part(m, "TablonRotulo", Vector3.new(0.6, 2.2, 10), A(-1, 11.1, 0), Color3.fromRGB(46, 34, 30), Enum.Material.Wood, nil, false)
	label(head, Enum.NormalId.Left, "👥 INVITADOS", GOLD)
	-- papeles clavados y sello
	local paper = Color3.fromRGB(240, 230, 200)
	local specs = { { -4.6, 8.6, 3.3, -6 }, { -1.4, 9.2, 2.6, 5 }, { 2.2, 8.2, 3.2, -3 }, { 5.2, 9, 2.4, 7 }, { -3.2, 5.6, 2.8, 4 }, { 1.0, 5.4, 3.4, -5 }, { 4.8, 5.8, 2.6, 2 } }
	for i, sp in ipairs(specs) do
		local pp = part(m, "Papel" .. i, Vector3.new(0.12, sp[3], sp[3] * 0.78), A(-0.95, sp[2], sp[1]) * CFrame.Angles(math.rad(sp[4]), 0, 0), paper, Enum.Material.Fabric, nil, false)
		pp.Name = "Papel"
		part(m, "Clavo", Vector3.new(0.2, 0.3, 0.3), A(-1.08, sp[2] + sp[3] / 2 - 0.3, sp[1]), GOLD, Enum.Material.Metal, Enum.PartType.Ball, false)
	end
	part(m, "SelloCera", Vector3.new(0.25, 1.1, 1.1), A(-1.05, 4.6, 6.2), Color3.fromRGB(190, 40, 50), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, false)
	-- farolillos a los lados
	for _, dz in ipairs({ -10, 10 }) do
		part(m, "FarolilloBrazo", Vector3.new(2.2, 0.3, 0.3), A(-0.6, 10.5, dz), IRON, Enum.Material.Metal, nil, false)
		local lamp = part(m, "Farolillo", Vector3.new(1.1, 1.5, 1.1), A(-1.6, 10, dz), Color3.fromRGB(255, 220, 140), Enum.Material.Neon, nil, false)
		light(lamp, 22, 1, Color3.fromRGB(255, 220, 150))
	end
	-- banco y pluma
	part(m, "TablonRepisa", Vector3.new(2.4, 0.5, 11), A(-1.2, 2.8, 0), wood, Enum.Material.Wood, nil, false)
	return back
end

-- CASETA DE MASCOTAS (jardín, de cara al sur)
function HouseProps.Hut(m: Instance, o: Vector3, gz: number): Part
	local hx, hz = 38, gz + 2
	local function A(x: number, y: number, z: number): CFrame
		return CFrame.new(o + Vector3.new(hx + x, y, hz + z))
	end
	local plank = Color3.fromRGB(150, 104, 62)
	local post = Color3.fromRGB(98, 66, 40)
	local tile = Color3.fromRGB(170, 66, 56)
	-- suelo de madera con bordes
	part(m, "CasetaSuelo", Vector3.new(20, 0.6, 16), A(0, 1.7, 0), plank, Enum.Material.WoodPlanks)
	-- paredes: fondo y laterales a media altura, frente abierto con mostrador
	part(m, "CasetaFondo", Vector3.new(20, 7, 0.8), A(0, 5.2, 7.6), plank, Enum.Material.WoodPlanks)
	for _, dx in ipairs({ -9.6, 9.6 }) do
		part(m, "CasetaLado", Vector3.new(0.8, 7, 16), A(dx, 5.2, 0), plank, Enum.Material.WoodPlanks)
	end
	for _, dx in ipairs({ -9.6, 9.6 }) do
		for _, dz in ipairs({ -7.6, 7.6 }) do
			part(m, "CasetaPoste", Vector3.new(1.2, 10.5, 1.2), A(dx, 6.9, dz), post, Enum.Material.Wood)
		end
	end
	-- tejado a dos aguas (cumbrera a lo largo de X)
	local ridgeY = 13
	for _, side in ipairs({ -1, 1 }) do
		local slab = part(m, "CasetaTecho", Vector3.new(23, 0.8, 11.4), A(0, 11, side * 4.9) * CFrame.Angles(math.rad(side * 28), 0, 0), tile, Enum.Material.Slate, nil, false)
		slab.Name = "CasetaTecho"
		part(m, "CasetaTechoBorde", Vector3.new(23.2, 0.4, 0.6), A(0, 8.5, side * 9.9) * CFrame.Angles(math.rad(side * 28), 0, 0), GOLD, Enum.Material.Metal, nil, false)
	end
	part(m, "CasetaCumbrera", Vector3.new(23.6, 0.8, 1), A(0, ridgeY + 0.3, 0), post, Enum.Material.Wood, nil, false)
	-- frontón triangular (tres tablas) para tapar los lados del tejado
	for _, dx in ipairs({ -10.4, 10.4 }) do
		part(m, "CasetaFronton", Vector3.new(0.6, 2.6, 7), A(dx, 10.4, 0), plank, Enum.Material.WoodPlanks, nil, false)
		part(m, "CasetaFronton", Vector3.new(0.6, 1.4, 3.6), A(dx, 12.4, 0), plank, Enum.Material.WoodPlanks, nil, false)
	end
	-- mostrador al frente (aquí va el prompt)
	local counter = part(m, "Caseta", Vector3.new(11, 3.2, 1.6), A(0, 3.8, -6.8), post, Enum.Material.Wood)
	part(m, "CasetaMostradorTapa", Vector3.new(12, 0.5, 2.4), A(0, 5.6, -6.8), GOLD, Enum.Material.Wood, nil, false)
	-- letrero colgante
	local rot = part(m, "CasetaRotulo", Vector3.new(12, 2.6, 0.5), A(0, 9.6, -8), Color3.fromRGB(70, 46, 30), Enum.Material.Wood, nil, false)
	label(rot, Enum.NormalId.Front, "🐾 CASETA DE MASCOTAS", Color3.fromRGB(190, 255, 200))
	for _, dx in ipairs({ -5.5, 5.5 }) do
		part(m, "RotuloCadena", Vector3.new(0.15, 1.6, 0.15), A(dx, 11.2, -8), IRON, Enum.Material.Metal, nil, false)
	end
	-- farolillo colgante
	part(m, "CasetaCuerda", Vector3.new(0.12, 2.6, 0.12), A(-7.5, 10.2, -5), IRON, Enum.Material.Metal, nil, false)
	local lamp = part(m, "CasetaFarol", Vector3.new(1.3, 1.6, 1.3), A(-7.5, 8.4, -5), Color3.fromRGB(255, 214, 130), Enum.Material.Neon, nil, false)
	light(lamp, 24, 1, Color3.fromRGB(255, 214, 140))
	-- interior: camas redondas, cuencos y heno
	for i, dx in ipairs({ -5, 0, 5 }) do
		local bed = part(m, "Cama" .. i, Vector3.new(0.7, 4, 4), A(dx, 2.3, 3), Color3.fromRGB(100 + i * 30, 60, 90), Enum.Material.Fabric, Enum.PartType.Cylinder, false)
		bed.CFrame = A(dx, 2.3, 3) * CFrame.Angles(0, 0, math.rad(90))
		bed.Name = "Cama"
	end
	local food = part(m, "CuencoComida", Vector3.new(0.6, 2, 2), A(-8, 2.3, -3), Color3.fromRGB(190, 70, 56), Enum.Material.Metal, Enum.PartType.Cylinder, false)
	food.CFrame = A(-8, 2.3, -3) * CFrame.Angles(0, 0, math.rad(90))
	local water = part(m, "CuencoAgua", Vector3.new(0.6, 2, 2), A(-8, 2.3, -6), Color3.fromRGB(70, 150, 220), Enum.Material.Glass, Enum.PartType.Cylinder, false)
	water.CFrame = A(-8, 2.3, -6) * CFrame.Angles(0, 0, math.rad(90))
	for i, dz in ipairs({ -1, 2 }) do
		part(m, "Heno", Vector3.new(4.4, 2.6, 2.8), A(12.5, 2.9, dz * 3 - 2) * CFrame.Angles(0, math.rad(i * 8), 0), Color3.fromRGB(226, 190, 90), Enum.Material.Grass)
		part(m, "HenoAtadura", Vector3.new(0.4, 2.7, 2.9), A(12.5, 2.9, dz * 3 - 2) * CFrame.Angles(0, math.rad(i * 8), 0), post, Enum.Material.Wood, nil, false)
	end
	-- huellas decorativas en el camino
	for i = 0, 3 do
		part(m, "Huella", Vector3.new(0.12, 1.4, 1.1), CFrame.new(o + Vector3.new(hx - 3 + (i % 2) * 2.4, 1.48, hz - 12 - i * 2.8)), Color3.fromRGB(130, 100, 70), Enum.Material.Ground, nil, false)
	end
	return counter
end

-- INTERRUPTOR de pared: placa, palanca y bombilla (la bombilla cambia de color con el estado)
function HouseProps.Switch(m: Instance, o: Vector3, x: number, y: number, z: number, faceZ: number): (Part, Part)
	local function A(dx: number, dy: number, dz: number): CFrame
		return CFrame.new(o + Vector3.new(x + dx, y + dy, z + dz * faceZ))
	end
	local plate = part(m, "Interruptor", Vector3.new(3.2, 4.6, 0.6), A(0, 0, 0), Color3.fromRGB(60, 52, 48), Enum.Material.Wood, nil, false)
	part(m, "InterruptorMarco", Vector3.new(3.8, 5.2, 0.4), A(0, 0, -0.1), GOLD, Enum.Material.Metal, nil, false)
	part(m, "InterruptorRiel", Vector3.new(0.5, 2.2, 0.3), A(0, -0.6, 0.5), IRON, Enum.Material.Metal, nil, false)
	part(m, "InterruptorPalanca", Vector3.new(0.35, 1.5, 0.35), A(0, -0.1, 0.8) * CFrame.Angles(math.rad(-30 * faceZ), 0, 0), Color3.fromRGB(200, 60, 56), Enum.Material.Metal, nil, false)
	part(m, "InterruptorBola", Vector3.new(0.8, 0.8, 0.8), A(0, 0.55, 1.1), Color3.fromRGB(200, 60, 56), Enum.Material.Metal, Enum.PartType.Ball, false)
	local bulb = part(m, "InterruptorBombilla", Vector3.new(1.2, 1.2, 0.5), A(0, 1.7, 0.4), Color3.fromRGB(255, 226, 120), Enum.Material.Neon, Enum.PartType.Ball, false)
	return plate, bulb
end

return HouseProps
