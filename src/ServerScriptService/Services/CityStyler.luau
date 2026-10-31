--!strict
--[[
    CityStyler (ModuleScript) -> ServerScriptService > Services > CityStyler
    Viste anime para las 4 ciudades. Se aplica ENCIMA del mapa que crea ProjectBootstrapper (no lo modifica):
      1. Recolorea piso, plaza, caminos, murallas, torres y los 6 comercios con los materiales de cada facción.
      2. Agrega decorado en una carpeta "Estilo" dentro de cada Ciudad (se borra y se rehace sola si se vuelve a correr):
         coronación de murallas, techos de torres, arcos sobre los 2 portones con cartel, monumento en la plaza,
         faroles, y en cada comercio techos/cúpulas/velas + letrero con su nombre.
      3. Si CityAssets tiene IDs de imagen, los usa (carteles de portón, fondo de letreros, dibujo de la plaza).
    Se ejecuta solo al hacer require (lo llama GameServerMain). Para apagarlo: ENABLED = false.
    Medidas: copia de las de ProjectBootstrapper (ciudad 800x800, muralla 40 de alto, plaza 200).
]]
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local ENABLED = true
local MAP_NAME = "Map_WC3_Style"

local CityAssets = require(script.Parent:WaitForChild("CityAssets"))

local CITY_SIZE = 800
local CITY_HALF = 400
local WALL_H = 40 -- alto de muralla sobre el piso
local WALL_T = 6
local TOWER_H = 52
local PLAZA_U = 400
local BRIDGE_GATE_HALF = 58 -- portón del puente (u = 0)
local EXIT_GATE_HALF = 100 -- salida trasera (u = 800)
local GATE_TOWER = 24

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

type Theme = {
	Faction: string,
	Emblem: string,
	Floor: Color3, FloorMat: Enum.Material,
	Plaza: Color3, PlazaMat: Enum.Material,
	Road: Color3, RoadMat: Enum.Material,
	Wall: Color3, WallMat: Enum.Material,
	Tower: Color3, TowerMat: Enum.Material,
	ShopWall: Color3, ShopWallMat: Enum.Material,
	Roof: Color3, RoofMat: Enum.Material,
	Trim: Color3, TrimMat: Enum.Material,
	Glow: Color3,
	Shops: { string },
}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local THEMES: { [string]: Theme } = {
	Saiyan = {
		Faction = "Saiyan", Emblem = "龍",
		Floor = C(46, 59, 82), FloorMat = Enum.Material.SmoothPlastic,
		Plaza = C(60, 78, 110), PlazaMat = Enum.Material.SmoothPlastic,
		Road = C(36, 46, 64), RoadMat = Enum.Material.Metal,
		Wall = C(223, 232, 242), WallMat = Enum.Material.Concrete,
		Tower = C(238, 243, 249), TowerMat = Enum.Material.Concrete,
		ShopWall = C(232, 238, 246), ShopWallMat = Enum.Material.SmoothPlastic,
		Roof = C(42, 111, 192), RoofMat = Enum.Material.Metal,
		Trim = C(255, 138, 31), TrimMat = Enum.Material.Metal,
		Glow = C(79, 209, 255),
		Shops = { "Cámara de Gravedad", "Taller de Armaduras", "Laboratorio de Cápsulas", "Tienda de Cápsulas", "Sala del Consejo", "Terraza Orbital" },
	},
	Shinobi = {
		Faction = "Shinobi", Emblem = "忍",
		Floor = C(180, 154, 115), FloorMat = Enum.Material.Ground,
		Plaza = C(200, 185, 150), PlazaMat = Enum.Material.Cobblestone,
		Road = C(138, 122, 99), RoadMat = Enum.Material.Cobblestone,
		Wall = C(122, 82, 50), WallMat = Enum.Material.WoodPlanks,
		Tower = C(233, 220, 192), TowerMat = Enum.Material.Concrete,
		ShopWall = C(233, 220, 192), ShopWallMat = Enum.Material.Concrete,
		Roof = C(168, 64, 47), RoofMat = Enum.Material.Slate,
		Trim = C(122, 82, 50), TrimMat = Enum.Material.WoodPlanks,
		Glow = C(232, 166, 64),
		Shops = { "Academia Ninja", "Herrería de Kunai", "Casa de Hierbas", "Tienda Ninja", "Torre del Líder", "Pabellón de Té" },
	},
	Pirate = {
		Faction = "Pirate", Emblem = "海",
		Floor = C(123, 90, 58), FloorMat = Enum.Material.WoodPlanks,
		Plaza = C(140, 104, 66), PlazaMat = Enum.Material.WoodPlanks,
		Road = C(91, 65, 48), RoadMat = Enum.Material.WoodPlanks,
		Wall = C(107, 111, 116), WallMat = Enum.Material.Cobblestone,
		Tower = C(91, 65, 48), TowerMat = Enum.Material.Wood,
		ShopWall = C(91, 65, 48), ShopWallMat = Enum.Material.Wood,
		Roof = C(122, 47, 42), RoofMat = Enum.Material.WoodPlanks,
		Trim = C(201, 162, 74), TrimMat = Enum.Material.Metal,
		Glow = C(255, 190, 90),
		Shops = { "Salón de Esgrima", "Fragua del Astillero", "Botica del Cirujano", "Mercado del Muelle", "Gremio de Tripulaciones", "Camarote del Capitán" },
	},
	Shinigami = {
		Faction = "Shinigami", Emblem = "死",
		Floor = C(207, 210, 216), FloorMat = Enum.Material.Slate,
		Plaza = C(225, 227, 232), PlazaMat = Enum.Material.Marble,
		Road = C(120, 128, 150), RoadMat = Enum.Material.Slate,
		Wall = C(241, 241, 243), WallMat = Enum.Material.Concrete,
		Tower = C(241, 241, 243), TowerMat = Enum.Material.Concrete,
		ShopWall = C(241, 241, 243), ShopWallMat = Enum.Material.Concrete,
		Roof = C(43, 58, 85), RoofMat = Enum.Material.Slate,
		Trim = C(22, 22, 28), TrimMat = Enum.Material.Metal,
		Glow = C(126, 200, 255),
		Shops = { "Escuela de Zanjutsu", "Forja de Espadas", "División de Investigación", "Tienda de Provisiones", "Cuartel de Divisiones", "Pabellón Noble" },
	},
}

---------------------------------------------------------------------
-- MARCO DE LA CIUDAD (u = hacia afuera de la arena, v = lateral) y helpers de partes
---------------------------------------------------------------------
type Frame = { Center: Vector3, Dir: Vector3, Side: Vector3, Floor: number }

local function pt(f: Frame, u: number, v: number, y: number): Vector3
	local p = f.Center + f.Dir * (u - PLAZA_U) + f.Side * v
	return Vector3.new(p.X, y, p.Z)
end

local function mk(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Caja alineada a la ciudad: u0..u1 (largo), v0..v1 (ancho), y0 sobre el piso, h alto
local function box(f: Frame, parent: Instance, name: string, u0: number, u1: number, v0: number, v1: number, y0: number, h: number, color: Color3, mat: Enum.Material): Part
	local pos = pt(f, (u0 + u1) / 2, (v0 + v1) / 2, f.Floor + y0 + h / 2)
	return mk(name, Vector3.new(v1 - v0, h, u1 - u0), CFrame.lookAt(pos, pos + f.Dir), color, mat, parent)
end

-- Cilindro vertical
local function cyl(f: Frame, parent: Instance, name: string, u: number, v: number, y0: number, h: number, d: number, color: Color3, mat: Enum.Material): Part
	local pos = pt(f, u, v, f.Floor + y0 + h / 2)
	local p = mk(name, Vector3.new(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, mat, parent)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(f: Frame, parent: Instance, name: string, u: number, v: number, yCenter: number, d: number, color: Color3, mat: Enum.Material): Part
	local p = mk(name, Vector3.new(d, d, d), CFrame.new(pt(f, u, v, f.Floor + yCenter)), color, mat, parent)
	p.Shape = Enum.PartType.Ball
	return p
end

local function folder(name: string, parent: Instance): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local fo = Instance.new("Folder")
	fo.Name = name
	fo.Parent = parent
	return fo
end

local function recolor(inst: Instance, color: Color3, mat: Enum.Material)
	if inst:IsA("BasePart") then
		inst.Color = color
		inst.Material = mat
	end
end

local function startsWith(s: string, p: string): boolean
	return string.sub(s, 1, #p) == p
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local function emitter(p: BasePart, color: Color3, rate: number, speed: number, life: number, size: number, accel: Vector3)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Size = NumberSequence.new(size)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 0.8
	e.Acceleration = accel
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = p
end

-- Cartel con texto (y fondo de imagen opcional) en las caras indicadas
local function addSign(p: BasePart, text: string, textColor: Color3, bg: Color3, image: string?, faces: { Enum.NormalId }, showText: boolean)
	for _, face in ipairs(faces) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.LightInfluence = 0
		sg.Parent = p
		if image then
			local img = Instance.new("ImageLabel")
			img.Size = UDim2.fromScale(1, 1)
			img.BackgroundTransparency = 1
			img.Image = image
			img.ScaleType = Enum.ScaleType.Stretch
			img.Parent = sg
		else
			local fr = Instance.new("Frame")
			fr.Size = UDim2.fromScale(1, 1)
			fr.BackgroundColor3 = bg
			fr.BorderSizePixel = 0
			fr.Parent = sg
		end
		if showText then
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(0.64, 0.7)
			tl.Position = UDim2.fromScale(0.18, 0.15)
			tl.BackgroundTransparency = 1
			tl.Text = text
			tl.TextScaled = true
			tl.TextColor3 = textColor
			tl.Font = Enum.Font.GothamBlack
			tl.TextStrokeTransparency = 0.5
			tl.Parent = sg
		end
	end
end

---------------------------------------------------------------------
-- 1) RECOLOR de lo que ya existe
---------------------------------------------------------------------
local function recolorCity(city: Instance, th: Theme)
	local floorF = city:FindFirstChild("Piso")
	if floorF then
		for _, p in ipairs(floorF:GetChildren()) do
			if startsWith(p.Name, "Z1_Ciudad") then
				recolor(p, th.Floor, th.FloorMat)
			elseif startsWith(p.Name, "Plaza_Central") then
				recolor(p, th.Plaza, th.PlazaMat)
			elseif startsWith(p.Name, "Camino_") then
				recolor(p, th.Road, th.RoadMat)
			end
		end
	end
	local walls = city:FindFirstChild("Murallas")
	if walls then
		for _, p in ipairs(walls:GetChildren()) do
			if startsWith(p.Name, "Muralla_") then
				recolor(p, th.Wall, th.WallMat)
			elseif startsWith(p.Name, "Torre_") then
				recolor(p, th.Tower, th.TowerMat)
			end
		end
	end
end

local function recolorShop(model: Model, th: Theme)
	for _, p in ipairs(model:GetChildren()) do
		local n = p.Name
		if n == "Parcela" then
			recolor(p, th.Floor:Lerp(C(120, 120, 125), 0.35), th.FloorMat)
		elseif startsWith(n, "Pared") or startsWith(n, "Frente") or startsWith(n, "Plataforma") or startsWith(n, "Escalon")
			or startsWith(n, "Pilar") or n == "Frontis" or n == "Torre" then
			recolor(p, th.ShopWall, th.ShopWallMat)
		elseif n == "Techo" or n == "Torre_Techo" or n == "Toldo" then
			recolor(p, th.Roof, th.RoofMat)
		elseif n == "Mostrador" or startsWith(n, "Columna") or startsWith(n, "Poste") or startsWith(n, "Caja") then
			recolor(p, th.Trim, th.TrimMat)
		end
	end
end

---------------------------------------------------------------------
-- 2) DECORADO
---------------------------------------------------------------------
-- Cúpula escalonada (4 discos que se achican + esfera) sobre un punto
local function steppedDome(f: Frame, parent: Instance, u: number, v: number, y0: number, d: number, th: Theme)
	for i = 1, 4 do
		local dd = d * (1 - 0.2 * (i - 1))
		cyl(f, parent, "Cupula_" .. i, u, v, y0 + (i - 1) * 2.2, 2.2, dd, th.Roof, th.RoofMat)
	end
	local top = y0 + 4 * 2.2
	cyl(f, parent, "Cupula_Aro", u, v, y0 + 0.2, 0.5, d * 1.02, th.Glow, Enum.Material.Neon)
	ball(f, parent, "Cupula_Luz", u, v, top + 1.5, 3, th.Glow, Enum.Material.Neon)
end

-- Techo escalonado tipo pagoda (partes alineadas con la ciudad)
local function pagodaRoof(f: Frame, parent: Instance, u: number, v: number, y0: number, su: number, sv: number, tiers: number, th: Theme)
	for i = 1, tiers do
		local k = 1 - (i - 1) * 0.28
		local a, b = su * k / 2, sv * k / 2
		box(f, parent, "Techo_Nivel_" .. i, u - a, u + a, v - b, v + b, y0 + (i - 1) * 2.6, 2.6, th.Roof, th.RoofMat)
	end
	local top = y0 + tiers * 2.6
	box(f, parent, "Techo_Remate", u - 1, u + 1, v - 1, v + 1, top, 3.5, th.Trim, th.TrimMat)
end

local function wallCrown(f: Frame, parent: Instance, th: Theme)
	-- segmentos de muralla: u0, u1, v0, v1
	local segs: { { number } } = {
		{ 0, CITY_SIZE, -CITY_HALF, -CITY_HALF + WALL_T },
		{ 0, CITY_SIZE, CITY_HALF - WALL_T, CITY_HALF },
		{ 0, WALL_T, -CITY_HALF, -BRIDGE_GATE_HALF - GATE_TOWER },
		{ 0, WALL_T, BRIDGE_GATE_HALF + GATE_TOWER, CITY_HALF },
		{ CITY_SIZE - WALL_T, CITY_SIZE, -CITY_HALF, -EXIT_GATE_HALF - GATE_TOWER },
		{ CITY_SIZE - WALL_T, CITY_SIZE, EXIT_GATE_HALF + GATE_TOWER, CITY_HALF },
	}
	for i, s in ipairs(segs) do
		local u0, u1, v0, v1 = s[1], s[2], s[3], s[4]
		local f1 = th.Faction
		if f1 == "Saiyan" then
			box(f, parent, "Franja_Luz_Alta_" .. i, u0, u1, v0 - 0.4, v1 + 0.4, WALL_H - 3, 0.8, th.Glow, Enum.Material.Neon)
			box(f, parent, "Franja_Luz_Baja_" .. i, u0, u1, v0 - 0.4, v1 + 0.4, WALL_H * 0.45, 0.8, th.Glow, Enum.Material.Neon)
			box(f, parent, "Cornisa_" .. i, u0, u1, v0 - 1, v1 + 1, WALL_H, 1.5, th.Roof, th.RoofMat)
		elseif f1 == "Shinobi" then
			box(f, parent, "Alero_" .. i, u0, u1, v0 - 3, v1 + 3, WALL_H, 2.5, th.Roof, th.RoofMat)
			box(f, parent, "Alero_Borde_" .. i, u0, u1, v0 - 3.4, v1 + 3.4, WALL_H + 2.5, 0.8, th.Trim, th.TrimMat)
			box(f, parent, "Viga_" .. i, u0, u1, v0 - 0.5, v1 + 0.5, WALL_H * 0.6, 1.4, C(168, 64, 47), Enum.Material.WoodPlanks)
		elseif f1 == "Pirate" then
			local alongU = (u1 - u0) >= (v1 - v0)
			local len = if alongU then (u1 - u0) else (v1 - v0)
			local count = math.floor((len - 56) / 14)
			for k = 0, math.max(0, count) do
				local off = 28 + k * 14
				if alongU then
					box(f, parent, "Almena", u0 + off, u0 + off + 7, v0 - 0.5, v1 + 0.5, WALL_H, 6, th.Wall, th.WallMat)
				else
					box(f, parent, "Almena", u0 - 0.5, u1 + 0.5, v0 + off, v0 + off + 7, WALL_H, 6, th.Wall, th.WallMat)
				end
			end
			box(f, parent, "Cinta_Laton_" .. i, u0, u1, v0 - 0.3, v1 + 0.3, WALL_H * 0.55, 0.7, th.Trim, th.TrimMat)
		else
			box(f, parent, "Cornisa_" .. i, u0, u1, v0 - 2.5, v1 + 2.5, WALL_H, 2, th.Roof, th.RoofMat)
			box(f, parent, "Teja_Cumbrera_" .. i, u0, u1, v0 - 1.4, v1 + 1.4, WALL_H + 2, 1.2, C(31, 43, 66), Enum.Material.Slate)
			box(f, parent, "Franja_Blanca_" .. i, u0, u1, v0 - 0.3, v1 + 0.3, WALL_H * 0.5, 0.6, C(207, 210, 216), th.WallMat)
		end
	end
end

local function towerRoofs(city: Instance, f: Frame, parent: Instance, th: Theme)
	local walls = city:FindFirstChild("Murallas")
	if not walls then
		return
	end
	for _, tw in ipairs(walls:GetChildren()) do
		if startsWith(tw.Name, "Torre_") and tw:IsA("BasePart") then
			local s = tw.Size
			local top = tw.Position.Y + s.Y / 2
			local base = Vector3.new(tw.Position.X, top, tw.Position.Z)
			local rel = base - Vector3.new(f.Center.X, top, f.Center.Z)
			local u = PLAZA_U + rel:Dot(f.Dir)
			local v = rel:Dot(f.Side)
			local y0 = top - f.Floor
			local wide = math.max(s.X, s.Z)
			if th.Faction == "Saiyan" then
				steppedDome(f, parent, u, v, y0, wide * 1.05, th)
			elseif th.Faction == "Shinobi" or th.Faction == "Shinigami" then
				box(f, parent, "Torre_Alero", u - wide / 2 - 4, u + wide / 2 + 4, v - wide / 2 - 4, v + wide / 2 + 4, y0, 2.2, th.Roof, th.RoofMat)
				pagodaRoof(f, parent, u, v, y0 + 2.2, wide + 4, wide + 4, 3, th)
			else
				box(f, parent, "Torre_Aro", u - wide / 2 - 1.5, u + wide / 2 + 1.5, v - wide / 2 - 1.5, v + wide / 2 + 1.5, y0, 2, th.Trim, th.TrimMat)
				for _, cu in ipairs({ -1, 1 }) do
					for _, cv in ipairs({ -1, 1 }) do
						box(f, parent, "Torre_Almena", u + cu * (wide / 2 - 2.5) - 2.5, u + cu * (wide / 2 - 2.5) + 2.5, v + cv * (wide / 2 - 2.5) - 2.5, v + cv * (wide / 2 - 2.5) + 2.5, y0 + 2, 5, th.Wall, th.WallMat)
					end
				end
				box(f, parent, "Torre_Asta", u - 0.5, u + 0.5, v - 0.5, v + 0.5, y0 + 2, 22, C(61, 42, 30), Enum.Material.Wood)
				box(f, parent, "Torre_Bandera", u - 0.2, u + 0.2, v + 0.5, v + 9, y0 + 16, 6, C(34, 34, 40), Enum.Material.Fabric)
				ball(f, parent, "Torre_Farol", u, v, y0 + 4, 3.5, th.Glow, Enum.Material.Neon)
			end
		end
	end
end

local function gateArch(f: Frame, parent: Instance, th: Theme, u: number, half: number, label: string)
	local span = half + GATE_TOWER
	local u0, u1 = u - 4, u + 4
	local faces = { Enum.NormalId.Front, Enum.NormalId.Back }
	if th.Faction == "Saiyan" then
		box(f, parent, "Arco_Viga", u0, u1, -span, span, WALL_H, 8, th.Roof, th.RoofMat)
		box(f, parent, "Arco_Luz", u0 - 0.4, u1 + 0.4, -span, span, WALL_H - 0.8, 0.8, th.Trim, Enum.Material.Neon)
	elseif th.Faction == "Shinobi" then
		box(f, parent, "Torii_Viga_Baja", u0 + 0.5, u1 - 0.5, -span, span, WALL_H, 2.4, C(183, 53, 42), Enum.Material.WoodPlanks)
		box(f, parent, "Torii_Viga_Alta", u0 - 1, u1 + 1, -span - 6, span + 6, WALL_H + 5.5, 3, C(183, 53, 42), Enum.Material.WoodPlanks)
		for _, sgn in ipairs({ -1, 1 }) do
			local pos = pt(f, u, sgn * (span + 5.5), f.Floor + WALL_H + 7.6)
			mk("Torii_Punta", Vector3.new(6, 3, 10), CFrame.lookAt(pos, pos + f.Dir) * CFrame.Angles(0, 0, math.rad(sgn * -14)), C(183, 53, 42), Enum.Material.WoodPlanks, parent)
		end
	elseif th.Faction == "Pirate" then
		box(f, parent, "Arco_Viga", u0, u1, -span, span, WALL_H, 6, C(91, 65, 48), Enum.Material.WoodPlanks)
		box(f, parent, "Arco_Laton", u0 - 0.4, u1 + 0.4, -span, span, WALL_H + 6, 1, th.Trim, th.TrimMat)
		for _, sgn in ipairs({ -1, 1 }) do
			local lamp = ball(f, parent, "Arco_Farol", u, sgn * (half + 4), WALL_H - 3, 3, th.Glow, Enum.Material.Neon)
			light(lamp, th.Glow, 24, 1.2)
		end
	else
		box(f, parent, "Arco_Alero", u0 - 1.5, u1 + 1.5, -span - 4, span + 4, WALL_H, 2.2, th.Roof, th.RoofMat)
		box(f, parent, "Arco_Viga", u0, u1, -span, span, WALL_H + 2.2, 5, C(241, 241, 243), th.WallMat)
		box(f, parent, "Arco_Cumbrera", u0 - 0.8, u1 + 0.8, -span - 2, span + 2, WALL_H + 7.2, 1.6, C(31, 43, 66), Enum.Material.Slate)
	end
	-- cartel central con el emblema (se ve de los dos lados)
	local sign = box(f, parent, "Arco_Cartel", u - 5, u + 5, -17, 17, WALL_H + 1, 6, th.Faction == "Pirate" and C(61, 42, 30) or C(20, 24, 36), Enum.Material.SmoothPlastic)
	local img = CityAssets.Get(th.Faction, "gate")
	addSign(sign, th.Emblem .. "  " .. label, th.Glow, C(20, 24, 36), img, faces, img == nil)
end

local function lamp(f: Frame, parent: Instance, u: number, v: number, th: Theme)
	cyl(f, parent, "Farol_Poste", u, v, 0, 9, 1, th.Trim, th.TrimMat)
	local head: Part
	if th.Faction == "Saiyan" then
		head = ball(f, parent, "Farol_Luz", u, v, 10.5, 3.2, th.Glow, Enum.Material.Neon)
	elseif th.Faction == "Shinobi" then
		head = ball(f, parent, "Farol_Luz", u, v, 10.5, 3.6, th.Glow, Enum.Material.Neon)
	elseif th.Faction == "Pirate" then
		head = box(f, parent, "Farol_Luz", u - 1.2, u + 1.2, v - 1.2, v + 1.2, 9, 3, th.Glow, Enum.Material.Neon)
	else
		head = ball(f, parent, "Farol_Luz", u, v, 10.5, 3.4, th.Glow, Enum.Material.Neon)
	end
	light(head, th.Glow, 26, 1.1)
end

local function plazaMonument(f: Frame, parent: Instance, th: Theme)
	local u, v = PLAZA_U, 0
	if th.Faction == "Saiyan" then
		cyl(f, parent, "Base", u, v, 0, 1.2, 44, C(30, 40, 60), Enum.Material.Metal)
		cyl(f, parent, "Anillo", u, v, 1.2, 0.3, 38, th.Glow, Enum.Material.Neon)
		cyl(f, parent, "Pilar", u, v, 1.2, 14, 4, th.ShopWall, th.ShopWallMat)
		-- Bola de Dragón de 4 estrellas (igual que el cartel del puente) y girando (tag SpinEmblem -> SpinEmblemClient)
		local model = Instance.new("Model")
		model.Name = "Bola_de_Dragon"
		model.Parent = parent
		local orb = ball(f, model, "DragonBall", u, v, 23.5, 16, C(255, 150, 20), Enum.Material.Neon)
		orb.Transparency = 0.15
		for _, side in ipairs({ -1, 1 }) do
			for _, o in ipairs({ Vector2.new(-2.1, 2.1), Vector2.new(2.1, 2.1), Vector2.new(-2.1, -2.1), Vector2.new(2.1, -2.1) }) do
				ball(f, model, "Star", u + side * 7.5, v + o.X, 23.5 + o.Y, 2.1, C(200, 30, 30), Enum.Material.Neon)
			end
		end
		CollectionService:AddTag(model, "SpinEmblem")
		light(orb, C(255, 170, 60), 40, 1.4)
		emitter(orb, th.Glow, 12, 6, 2.5, 0.6, Vector3.new(0, 2, 0))
	elseif th.Faction == "Shinobi" then
		cyl(f, parent, "Base", u, v, 0, 1.2, 34, C(150, 140, 120), Enum.Material.Cobblestone)
		cyl(f, parent, "Tronco", u, v, 1.2, 18, 4.5, C(98, 66, 40), Enum.Material.Wood)
		local l1 = ball(f, parent, "Hojas_1", u, v, 24, 22, C(86, 140, 70), Enum.Material.Grass)
		ball(f, parent, "Hojas_2", u + 7, v + 5, 20, 15, C(104, 160, 82), Enum.Material.Grass)
		ball(f, parent, "Hojas_3", u - 6, v - 6, 21, 14, C(72, 124, 60), Enum.Material.Grass)
		emitter(l1, C(150, 200, 110), 5, 3, 5, 0.7, Vector3.new(0, -3, 0))
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local bu, bv = u + math.cos(a) * 19, v + math.sin(a) * 19
			box(f, parent, "Banco", bu - 4, bu + 4, bv - 1.5, bv + 1.5, 1.2, 1.2, th.Trim, th.TrimMat)
			box(f, parent, "Banco_Pata", bu - 3.5, bu - 2.5, bv - 1, bv + 1, 1.2, 1.6, th.Trim, th.TrimMat)
			box(f, parent, "Banco_Pata", bu + 2.5, bu + 3.5, bv - 1, bv + 1, 1.2, 1.6, th.Trim, th.TrimMat)
		end
	elseif th.Faction == "Pirate" then
		cyl(f, parent, "Base", u, v, 0, 1.2, 32, C(110, 78, 50), Enum.Material.WoodPlanks)
		local iron = C(52, 54, 60)
		box(f, parent, "Ancla_Caña", u - 1, u + 1, v - 1, v + 1, 1.2, 24, iron, Enum.Material.Metal)
		box(f, parent, "Ancla_Cepo", u - 1, u + 1, v - 7, v + 7, 19, 2, iron, Enum.Material.Metal)
		for _, sgn in ipairs({ -1, 1 }) do
			local pos = pt(f, u, v + sgn * 5.5, f.Floor + 4.4)
			mk("Ancla_Brazo", Vector3.new(11, 2, 2), CFrame.lookAt(pos, pos + f.Dir) * CFrame.Angles(0, 0, math.rad(sgn * 32)), iron, Enum.Material.Metal, parent)
		end
		cyl(f, parent, "Ancla_Argolla", u, v, 25, 1.2, 6, th.Trim, th.TrimMat)
		local glow = ball(f, parent, "Ancla_Luz", u, v, 28, 3, th.Glow, Enum.Material.Neon)
		light(glow, th.Glow, 30, 1)
	else
		cyl(f, parent, "Base", u, v, 0, 1.5, 34, C(190, 194, 204), Enum.Material.Slate)
		cyl(f, parent, "Base_Alta", u, v, 1.5, 1.2, 14, C(225, 227, 232), Enum.Material.Marble)
		box(f, parent, "Hoja", u - 0.4, u + 0.4, v - 1.6, v + 1.6, 2.7, 28, C(232, 238, 248), Enum.Material.Metal)
		box(f, parent, "Guarda", u - 1, u + 1, v - 6, v + 6, 30, 1.6, th.Trim, th.TrimMat)
		box(f, parent, "Empunadura", u - 0.8, u + 0.8, v - 0.8, v + 0.8, 31.6, 7, C(20, 22, 30), Enum.Material.Fabric)
		local pom = ball(f, parent, "Pomo", u, v, 40, 2.4, th.Glow, Enum.Material.Neon)
		light(pom, th.Glow, 36, 1.3)
		emitter(pom, th.Glow, 10, 5, 3, 0.5, Vector3.new(0, 1.5, 0))
	end
end

---------------------------------------------------------------------
-- Comercios
---------------------------------------------------------------------
local function decorateShop(model: Model, th: Theme, floorY: number)
	local roof = model:FindFirstChild("Techo")
	if not roof or not roof:IsA("BasePart") then
		return
	end
	local slot = (model:GetAttribute("Slot") :: number?) or 0
	local name = th.Shops[slot]
	local W, D = roof.Size.X - 4, roof.Size.Z - 4
	local rf = roof.CFrame
	local roofH = roof.Position.Y - floorY -- altura del centro del techo sobre el piso
	local fo = folder("Estilo", model)

	local function rb(n: string, lx: number, ly: number, lz: number, sx: number, sy: number, sz: number, color: Color3, mat: Enum.Material): Part
		return mk(n, Vector3.new(sx, sy, sz), rf * CFrame.new(lx, ly, lz), color, mat, fo)
	end

	-- nombre en el cartel flotante existente
	if name then
		for _, d in ipairs(roof:GetDescendants()) do
			if d:IsA("TextLabel") then
				d.Text = name
			end
		end
	end

	-- letrero sobre el borde delantero del techo (frente = -Z)
	if name then
		local sw = math.min(W * 0.7, 30)
		local sign = rb("Letrero", 0, 3.4, -(D + 4) / 2 + 0.6, sw, 4, 0.7, C(20, 24, 36), Enum.Material.SmoothPlastic)
		local img = CityAssets.Get(th.Faction, "sign")
		addSign(sign, name, th.Glow, if th.Faction == "Shinigami" then C(31, 43, 66) else C(30, 30, 40), img, { Enum.NormalId.Front }, true)
	end

	if th.Faction == "Saiyan" then
		rb("Neon_Frente", 0, 0.9, -(D + 4) / 2, W + 4, 0.5, 0.5, th.Glow, Enum.Material.Neon)
		rb("Neon_Fondo", 0, 0.9, (D + 4) / 2, W + 4, 0.5, 0.5, th.Glow, Enum.Material.Neon)
		rb("Neon_Izq", -(W + 4) / 2, 0.9, 0, 0.5, 0.5, D + 4, th.Glow, Enum.Material.Neon)
		rb("Neon_Der", (W + 4) / 2, 0.9, 0, 0.5, 0.5, D + 4, th.Glow, Enum.Material.Neon)
		if slot == 1 or slot == 5 or slot == 6 then
			for i = 1, 4 do
				local d = math.min(W, D) * 0.8 * (1 - 0.2 * (i - 1))
				local c = rb("Cupula_" .. i, 0, 0.6 + 1.1 + (i - 1) * 2.2 + 0, 4, 2.2, d, d, th.Roof, th.RoofMat)
				c.Shape = Enum.PartType.Cylinder
				c.CFrame = rf * CFrame.new(0, 1.7 + (i - 1) * 2.2, 4) * CFrame.Angles(0, 0, math.rad(90))
			end
			local orb = rb("Cupula_Luz", 0, 1.7 + 4 * 2.2 + 1, 4, 3, 3, 3, th.Glow, Enum.Material.Neon)
			orb.Shape = Enum.PartType.Ball
		elseif slot == 2 then
			local pipe = rb("Escape", W / 2 - 4, 6, D / 2 - 4, 3, 12, 3, C(80, 90, 110), Enum.Material.Metal)
			pipe.Shape = Enum.PartType.Cylinder
			pipe.CFrame = rf * CFrame.new(W / 2 - 4, 6, D / 2 - 4) * CFrame.Angles(0, 0, math.rad(90))
			rb("Escape_Luz", W / 2 - 4, 12.3, D / 2 - 4, 3.2, 0.4, 3.2, th.Trim, Enum.Material.Neon)
		elseif slot == 4 then
			rb("Toldo_Luz", 0, -1.8, -D / 2 - 7.6, W + 4, 0.4, 0.4, th.Trim, Enum.Material.Neon)
		end
	elseif th.Faction == "Shinobi" or th.Faction == "Shinigami" then
		local tiers = if slot == 5 then 3 elseif slot == 3 then 2 else 2
		for i = 1, tiers do
			local k = 1 - (i - 1) * 0.3
			rb("Techo_Nivel_" .. i, 0, 0.6 + 1.3 + (i - 1) * 2.6, 0, (W + 4) * k * 0.92, 2.6, (D + 4) * k * 0.92, th.Roof, th.RoofMat)
		end
		rb("Techo_Remate", 0, 0.6 + tiers * 2.6 + 1.8, 0, 2, 3.6, 2, th.Trim, th.TrimMat)
		-- alero con borde
		rb("Alero_Frente", 0, 0.3, -(D + 4) / 2 - 1, W + 6, 0.8, 1.6, th.Roof:Lerp(C(0, 0, 0), 0.25), th.RoofMat)
		-- linternas en el frente
		for _, sx in ipairs({ -1, 1 }) do
			local lp = rb("Linterna", sx * (W / 2 - 3), -3.4, -D / 2 - 1.6, 2.4, 3, 2.4, th.Glow, Enum.Material.Neon)
			lp.Shape = Enum.PartType.Ball
			light(lp, th.Glow, 14, 0.9)
			rb("Linterna_Cuerda", sx * (W / 2 - 3), -1.2, -D / 2 - 1.6, 0.3, 2.4, 0.3, th.Trim, th.TrimMat)
		end
	else -- Pirate
		if slot ~= 6 then
			for _, sx in ipairs({ -1, 1 }) do
				local barrel = rb("Barril", sx * (W / 2 - 3), -roofH + 2.4, -D / 2 - 6, 4, 3.6, 3.6, C(122, 86, 52), Enum.Material.Wood)
				barrel.Shape = Enum.PartType.Cylinder
				barrel.CFrame = rf * CFrame.new(sx * (W / 2 - 3), -roofH + 2.4, -D / 2 - 6) * CFrame.Angles(0, 0, math.rad(90))
			end
		end
		if slot == 1 or slot == 4 or slot == 5 then
			rb("Mastil", 0, 8, D / 4, 1.2, 16, 1.2, C(61, 42, 30), Enum.Material.Wood)
			rb("Vela", 6, 9, D / 4, 10, 9, 0.4, C(232, 223, 200), Enum.Material.Fabric)
			rb("Vela_Borde", 6, 13.7, D / 4, 10, 0.5, 0.6, th.Trim, th.TrimMat)
			local lamp1 = rb("Farol_Mastil", 0, 16.8, D / 4, 2, 2, 2, th.Glow, Enum.Material.Neon)
			lamp1.Shape = Enum.PartType.Ball
			light(lamp1, th.Glow, 22, 1)
		end
		rb("Cuerda", 0, 0.2, -(D + 4) / 2 - 0.4, W + 5, 0.7, 0.7, C(217, 192, 138), Enum.Material.Fabric)
		for _, sx in ipairs({ -1, 1 }) do
			local lp = rb("Linterna", sx * (W / 2 - 3), -3.4, -D / 2 - 1.6, 2.2, 2.8, 2.2, th.Glow, Enum.Material.Neon)
			light(lp, th.Glow, 14, 0.9)
			rb("Linterna_Cuerda", sx * (W / 2 - 3), -1.2, -D / 2 - 1.6, 0.3, 2.4, 0.3, th.Trim, th.TrimMat)
		end
	end
end

---------------------------------------------------------------------
-- Aplicar a una ciudad
---------------------------------------------------------------------
local function styleCity(biome: Instance, faction: string)
	local th = THEMES[faction]
	local city = biome:FindFirstChild("Ciudad")
	if not th or not city then
		return
	end
	local floorF = city:FindFirstChild("Piso")
	local plaza = floorF and floorF:FindFirstChild("Plaza_Central")
	if not plaza or not plaza:IsA("BasePart") then
		warn("[CityStyler] " .. biome.Name .. ": no hay Plaza_Central")
		return
	end
	local f: Frame = {
		Center = plaza.Position,
		Dir = plaza.CFrame.LookVector,
		Side = plaza.CFrame.RightVector,
		Floor = plaza.Position.Y - 0.2,
	}

	recolorCity(city, th)
	local fo = folder("Estilo", city)

	wallCrown(f, fo, th)
	towerRoofs(city, f, fo, th)
	gateArch(f, fo, th, 3, BRIDGE_GATE_HALF, "PUENTE")
	gateArch(f, fo, th, CITY_SIZE - 3, EXIT_GATE_HALF, "FRANJAS")
	plazaMonument(f, fo, th)

	-- imagen del suelo de la plaza
	local plazaImg = CityAssets.Get(faction, "plaza")
	if plazaImg then
		local d = Instance.new("Decal")
		d.Name = "Plaza_Dibujo"
		d.Face = Enum.NormalId.Top
		d.Texture = plazaImg
		d.Parent = plaza
	end

	-- faroles: esquinas de la plaza y a lo largo de los dos caminos
	for _, su in ipairs({ -1, 1 }) do
		for _, sv in ipairs({ -1, 1 }) do
			lamp(f, fo, PLAZA_U + su * 94, sv * 94, th)
		end
	end
	for _, u in ipairs({ 60, 140, 220, 580, 660, 740 }) do
		lamp(f, fo, u, -36, th)
		lamp(f, fo, u, 36, th)
	end

	-- comercios
	local quarter = city:FindFirstChild("Barrio_Comercial")
	if quarter then
		for _, m in ipairs(quarter:GetChildren()) do
			if m:IsA("Model") then
				recolorShop(m, th)
				decorateShop(m, th, f.Floor)
			end
		end
	end
end

local function run()
	-- espera a que ProjectBootstrapper termine el mapa NUEVO (no el viejo que pudiera venir guardado en el lugar)
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	local map = Workspace:WaitForChild(MAP_NAME, 60)
	if not map then
		warn("[CityStyler] No existe " .. MAP_NAME)
		Workspace:SetAttribute("CityStyleDone", true) -- no bloquear WorldReady
		return
	end
	local done = 0
	local failed = 0
	for _, biome in ipairs(map:GetChildren()) do
		local faction = BIOME_FACTION[biome.Name]
		if faction then
			local ok, err = pcall(styleCity, biome, faction)
			if ok then
				done += 1
			else
				failed += 1
				warn("[CityStyler] Error en " .. biome.Name .. ": " .. tostring(err))
			end
		end
	end
	-- el cliente lee este atributo (CityStyleCheck) para confirmar en la consola F9 que el estilo llegó
	Workspace:SetAttribute("CityStyleStatus", string.format("%d ciudades con estilo, %d con error", done, failed))
	Workspace:SetAttribute("CityStyleDone", true)
	print("[CityStyler] Estilo anime aplicado a las 4 ciudades.")
end

local CityStyler = {}
CityStyler.Run = run

if ENABLED then
	task.spawn(run)
end

return CityStyler
