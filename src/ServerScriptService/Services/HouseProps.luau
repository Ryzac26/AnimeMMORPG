--!strict
--[[
    HouseProps (ModuleScript) -> ServerScriptService.Services.HouseProps
    Piezas grandes de la Casa VIP con diseño propio (solo geometría; los prompts los pone HouseService):
      Chest(m, o)    cofre del tesoro sobre un estrado, con antorchas, tapiz y monedas  -> devuelve la pieza del prompt
      Board(m, o)    tablón de invitados pegado a la pared este, con papeles y farolillos   -> idem
      Hut(m, o, gz)  CABAÑA DE AYUDANTES: troncos, porche, hoguera con 3 tocones y banderines  -> (tablón del prompt, 3 posiciones de descanso)
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
	l.TextWrapped = false
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

-- CABAÑA DE AYUDANTES (jardín, de cara al sur): cabaña de troncos con porche, tejado azul-verdoso, hoguera con tres tocones y banderines
-- donde descansan los ayudantes de combate cuando el dueño está en su casa. Devuelve (tablón para el prompt, 3 posiciones de descanso en el mundo).
function HouseProps.Hut(m: Instance, o: Vector3, gz: number): (Part, { Vector3 })
	local hx, hz = 38, gz + 2
	local function A(x: number, y: number, z: number): CFrame
		return CFrame.new(o + Vector3.new(hx + x, y, hz + z))
	end
	local log = Color3.fromRGB(128, 84, 50)
	local logDark = Color3.fromRGB(90, 58, 36)
	local plank = Color3.fromRGB(160, 114, 70)
	local stone = Color3.fromRGB(150, 146, 140)
	local tile = Color3.fromRGB(52, 98, 112)
	local cloth = { Color3.fromRGB(240, 196, 90), Color3.fromRGB(90, 160, 240), Color3.fromRGB(220, 110, 200) }

	-- cimientos de piedra y suelo
	part(m, "CabanaBase", Vector3.new(23, 0.9, 19), A(0, 1.85, 0), stone, Enum.Material.Cobblestone)
	part(m, "CabanaSuelo", Vector3.new(20, 0.3, 16), A(0, 2.45, 0), plank, Enum.Material.WoodPlanks)
	-- paredes de troncos: fondo y laterales
	local function logWall(name: string, cx: number, cz: number, alongX: boolean, length: number)
		for i = 0, 5 do
			local y = 3.3 + i * 1.1
			-- el cilindro de Roblox tiene su eje en X: Size.X = largo del tronco; para paredes a lo largo de Z se gira 90°
			local lg = part(m, name, Vector3.new(length, 1.1, 1.1), A(cx, y, cz), if i % 2 == 0 then log else logDark, Enum.Material.Wood, Enum.PartType.Cylinder)
			if not alongX then
				lg.CFrame = A(cx, y, cz) * CFrame.Angles(0, math.rad(90), 0)
			end
		end
	end
	logWall("CabanaTroncoFondo", 0, 7.6, true, 20)
	logWall("CabanaTroncoLado", -9.6, 0, false, 16)
	logWall("CabanaTroncoLado", 9.6, 0, false, 16)
	-- frente con puerta ancha: dos tramos y un dintel
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 5 do
			local y = 3.3 + i * 1.1
			part(m, "CabanaTroncoFrente", Vector3.new(6.2, 1.1, 1.1), A(sx * 6.9, y, -7.6), if i % 2 == 0 then log else logDark, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end
	part(m, "CabanaDintel", Vector3.new(8, 1.6, 1.3), A(0, 8.6, -7.6), logDark, Enum.Material.Wood)
	-- esquineros
	for _, dx in ipairs({ -10, 10 }) do
		for _, dz in ipairs({ -8, 8 }) do
			part(m, "CabanaEsquinero", Vector3.new(1.5, 8.2, 1.5), A(dx, 6.4, dz), logDark, Enum.Material.Wood)
		end
	end
	-- ventanas con luz cálida en los laterales
	for _, dx in ipairs({ -10.2, 10.2 }) do
		local w = part(m, "CabanaVentana", Vector3.new(0.3, 2.6, 3.4), A(dx, 5.6, 0), Color3.fromRGB(255, 218, 140), Enum.Material.Neon, nil, false)
		w.Transparency = 0.25
		part(m, "CabanaVentanaMarco", Vector3.new(0.5, 3.0, 0.4), A(dx, 5.6, 0), logDark, Enum.Material.Wood, nil, false)
	end
	-- tejado a dos aguas azul-verdoso con cumbrera dorada
	for _, side in ipairs({ -1, 1 }) do
		local slab = part(m, "CabanaTecho", Vector3.new(24, 0.8, 11.4), A(0, 11.6, side * 4.9) * CFrame.Angles(math.rad(side * 28), 0, 0), tile, Enum.Material.Slate, nil, false)
		slab.Name = "CabanaTecho"
		part(m, "CabanaTechoBorde", Vector3.new(24.2, 0.4, 0.6), A(0, 9.1, side * 9.9) * CFrame.Angles(math.rad(side * 28), 0, 0), GOLD, Enum.Material.Metal, nil, false)
	end
	part(m, "CabanaCumbrera", Vector3.new(24.6, 0.8, 1), A(0, 13.7, 0), GOLD, Enum.Material.Metal, nil, false)
	for _, dx in ipairs({ -10.6, 10.6 }) do
		part(m, "CabanaFronton", Vector3.new(0.6, 2.6, 7), A(dx, 10.9, 0), plank, Enum.Material.WoodPlanks, nil, false)
		part(m, "CabanaFronton", Vector3.new(0.6, 1.4, 3.6), A(dx, 12.9, 0), plank, Enum.Material.WoodPlanks, nil, false)
	end
	-- chimenea de piedra con humo
	part(m, "CabanaChimenea", Vector3.new(2.6, 8, 2.6), A(6.5, 12.5, 5), stone, Enum.Material.Cobblestone, nil, false)
	local smoke = part(m, "CabanaHumo", Vector3.new(1, 1, 1), A(6.5, 16.8, 5), stone, Enum.Material.SmoothPlastic, nil, false)
	smoke.Transparency = 1
	local sm = Instance.new("ParticleEmitter")
	sm.Rate, sm.Lifetime, sm.Speed = 6, NumberRange.new(3, 4.5), NumberRange.new(3, 4)
	sm.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) })
	sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	sm.Color = ColorSequence.new(Color3.fromRGB(200, 200, 205))
	sm.EmissionDirection = Enum.NormalId.Top
	sm.Parent = smoke
	-- porche: suelo, dos postes y tejadillo
	part(m, "CabanaPorche", Vector3.new(16, 0.4, 4.4), A(0, 2.5, -10.2), plank, Enum.Material.WoodPlanks)
	for _, dx in ipairs({ -7, 7 }) do
		part(m, "CabanaPoste", Vector3.new(1.1, 8, 1.1), A(dx, 6.4, -11.8), logDark, Enum.Material.Wood)
	end
	local porchRoof = part(m, "CabanaTechoPorche", Vector3.new(17, 0.6, 5.6), A(0, 10.3, -10.4) * CFrame.Angles(math.rad(-14), 0, 0), tile, Enum.Material.Slate, nil, false)
	porchRoof.Name = "CabanaTechoPorche"
	-- letrero colgante sobre la puerta
	local rot = part(m, "CabanaRotulo", Vector3.new(12, 2.6, 0.5), A(0, 9.2, -12.2), Color3.fromRGB(56, 40, 30), Enum.Material.Wood, nil, false)
	label(rot, Enum.NormalId.Front, "🛡 CABAÑA DE AYUDANTES", Color3.fromRGB(190, 235, 255))
	for _, dx in ipairs({ -5.5, 5.5 }) do
		part(m, "RotuloCadena", Vector3.new(0.15, 1.2, 0.15), A(dx, 10.8, -12.2), IRON, Enum.Material.Metal, nil, false)
	end
	local lamp = part(m, "CabanaFarol", Vector3.new(1.3, 1.6, 1.3), A(-7, 8.2, -12.9), Color3.fromRGB(255, 214, 130), Enum.Material.Neon, nil, false)
	light(lamp, 26, 1, Color3.fromRGB(255, 214, 140))
	-- interior: tres literas (una por ayudante), estante con escudos, mesa y farol
	for i, dx in ipairs({ -6, 0, 6 }) do
		part(m, "CabanaCama", Vector3.new(4.2, 0.6, 6.4), A(dx, 3.1, 3.6), logDark, Enum.Material.Wood, nil, false)
		part(m, "CabanaManta", Vector3.new(4, 0.5, 4.2), A(dx, 3.6, 4.6), cloth[i], Enum.Material.Fabric, nil, false)
		part(m, "CabanaAlmohada", Vector3.new(3, 0.5, 1.4), A(dx, 3.7, 1.6), Color3.fromRGB(240, 236, 224), Enum.Material.Fabric, nil, false)
	end
	for i, dx in ipairs({ -7, -3.5, 3.5, 7 }) do
		local sh = part(m, "CabanaEscudo", Vector3.new(0.4, 2.6, 2.4), A(dx, 7.2, 7.0), cloth[(i % 3) + 1], Enum.Material.Metal, nil, false)
		sh.Name = "CabanaEscudo"
	end
	part(m, "CabanaMesa", Vector3.new(4.2, 0.5, 2.6), A(0, 4.4, -2.6), plank, Enum.Material.WoodPlanks, nil, false)
	part(m, "CabanaMesaPata", Vector3.new(0.6, 1.9, 0.6), A(0, 3.4, -2.6), logDark, Enum.Material.Wood, nil, false)
	-- tablón de ayudantes en el porche: aquí va el prompt
	local board = part(m, "CabanaTablon", Vector3.new(3.4, 4.2, 0.5), A(-11.8, 5.2, -9.0), Color3.fromRGB(70, 48, 32), Enum.Material.Wood, nil, false)
	part(m, "CabanaTablonPoste", Vector3.new(0.6, 5.2, 0.6), A(-13.2, 4.2, -9.0), logDark, Enum.Material.Wood, nil, false)
	part(m, "CabanaTablonPoste", Vector3.new(0.6, 5.2, 0.6), A(-10.4, 4.2, -9.0), logDark, Enum.Material.Wood, nil, false)
	label(board, Enum.NormalId.Front, "AYUDANTES", Color3.fromRGB(190, 235, 255))
	-- hoguera con piedras y troncos; tres tocones con banderín (donde descansa cada ayudante)
	local fireAt = Vector3.new(0, 1.5, -16)
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		part(m, "HogueraPiedra", Vector3.new(1.3, 0.9, 1.3), A(fireAt.X + math.cos(ang) * 2.1, 1.8, fireAt.Z + math.sin(ang) * 2.1), stone, Enum.Material.Rock, Enum.PartType.Ball, false)
	end
	for i = 0, 2 do
		local lg = part(m, "HogueraTronco", Vector3.new(3.4, 0.7, 0.7), A(fireAt.X, 1.9, fireAt.Z), logDark, Enum.Material.Wood, Enum.PartType.Cylinder, false)
		lg.CFrame = A(fireAt.X, 1.9, fireAt.Z) * CFrame.Angles(0, math.rad(i * 60), math.rad(12))
	end
	local flame = part(m, "HogueraFuego", Vector3.new(1.4, 1.4, 1.4), A(fireAt.X, 2.7, fireAt.Z), Color3.fromRGB(255, 150, 50), Enum.Material.Neon, nil, false)
	flame.Transparency = 0.45
	local fire = Instance.new("Fire")
	fire.Size, fire.Heat = 6, 8
	fire.Parent = flame
	light(flame, 28, 1.3, Color3.fromRGB(255, 170, 90))
	local spots: { Vector3 } = {}
	local offs = { Vector3.new(-5.2, 1.5, -15.2), Vector3.new(5.2, 1.5, -15.2), Vector3.new(0, 1.5, -21) }
	for i, off in ipairs(offs) do
		-- disco de color en el suelo (marca dónde descansa cada ayudante) y banderín a su lado
		local disc = part(m, "CabanaMarca", Vector3.new(0.25, 4.4, 4.4), A(off.X, 1.5, off.Z), cloth[i], Enum.Material.Fabric, Enum.PartType.Cylinder, false)
		disc.CFrame = A(off.X, 1.52, off.Z) * CFrame.Angles(0, 0, math.rad(90))
		disc.CanQuery = false
		local side = if off.X < 0 then -3.4 else 3.4
		part(m, "CabanaBanderinPoste", Vector3.new(0.3, 6, 0.3), A(off.X + side, 4.4, off.Z), IRON, Enum.Material.Metal, nil, false)
		part(m, "CabanaBanderin", Vector3.new(2.4, 1.8, 0.15), A(off.X + side + (if side < 0 then 1.3 else -1.3), 6.6, off.Z), cloth[i], Enum.Material.Fabric, nil, false)
		table.insert(spots, o + Vector3.new(hx + off.X, off.Y, hz + off.Z))
	end
	-- muñeco de entrenamiento y estante de armas a un lado
	part(m, "MunecoPoste", Vector3.new(0.7, 5.4, 0.7), A(15, 4.1, -8), logDark, Enum.Material.Wood, nil, false)
	part(m, "MunecoBrazos", Vector3.new(4.2, 0.6, 0.6), A(15, 5.6, -8), logDark, Enum.Material.Wood, nil, false)
	part(m, "MunecoCabeza", Vector3.new(1.5, 1.5, 1.5), A(15, 7.2, -8), Color3.fromRGB(226, 190, 90), Enum.Material.Grass, Enum.PartType.Ball, false)
	part(m, "MunecoCuerpo", Vector3.new(2.2, 2.8, 1.4), A(15, 4.6, -8), Color3.fromRGB(226, 190, 90), Enum.Material.Grass, nil, false)
	-- huellas decorativas en el camino
	for i = 0, 3 do
		part(m, "Huella", Vector3.new(0.12, 1.4, 1.1), CFrame.new(o + Vector3.new(hx - 3 + (i % 2) * 2.4, 1.48, hz - 24 - i * 2.8)), Color3.fromRGB(130, 100, 70), Enum.Material.Ground, nil, false)
	end
	return board, spots
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
