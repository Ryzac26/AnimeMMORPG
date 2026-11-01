--!strict
--[[
    BiomeStyler (ModuleScript) -> ServerScriptService > Services > BiomeStyler
    Diseño de los BIOMAS PvE (las 4 franjas de cada facción). Se aplica encima del mapa que crea
    ProjectBootstrapper (no lo modifica), igual que CityStyler y ArenaStyler.

    Qué hace en cada franja (16 en total):
      - Cambia el material y el color del suelo (y pone la textura de BiomeAssets si hay ID).
      - Muro visible a cada lado, pegado a la diagonal, con el estilo del anime (valla, bambú, acero, mármol...).
      - Río / lava / canal opcional junto al muro: el agua no se puede pisar (hay una pared invisible en la orilla).
      - Árboles, rocas, torres, columnas, barcos, etc. pegados al muro (con colisión SOLO en el tronco/base).
      - Banderas con el emblema de la facción en las franjas 1 y 4.
      - Escenografía gigante DETRÁS del muro (mesetas, montañas, torres, estatuas...). No tiene colisión.
      - Cada segundo mide en qué franja está cada jugador y pone el atributo de jugador "BiomeZone"
        (por ejemplo "Saiyan_2"); BiomeAmbientClient lo usa para cambiar luz, niebla y cielo.
      - Red de seguridad anti-atasco: si alguien queda dentro de una barrera dos revisiones seguidas,
        lo mueve al centro de su franja.

    REGLAS QUE EVITAN ATASCOS
      - Todo lo que tiene colisión toca el muro de la diagonal (queda pegado), así no hay rincones cerrados.
      - Las copas, ramas, hojas y adornos no tienen colisión.
      - El centro de cada franja (mínimo 400 studs de ancho) queda totalmente libre.
    ENABLED = false lo apaga y deja el mapa como estaba.
]]
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BiomeAssets"))

local ENABLED = true
local MAP_NAME = "Map_WC3_Style"

local FLOOR_TOP = 12
local CITY_SIZE = 800
local STRIP_DEPTH = 625
local STRIP_COUNT = 4
local GATE_MARGIN = 4 -- el muro llega hasta el muro de entre franjas
local PROP_MARGIN = 16 -- los objetos no se ponen pegados a los arcos entre franjas
local WALL_T = 4
local RIVER_W = 16

local C = Color3.fromRGB
local M = Enum.Material

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local BANNER_TEXT: { [string]: string } = { Saiyan = "龍", Shinobi = "忍", Pirate = "海賊", Shinigami = "死神" }
local BANNER_COLOR: { [string]: Color3 } = {
	Saiyan = C(216, 100, 26), Shinobi = C(58, 106, 52), Pirate = C(20, 36, 62), Shinigami = C(232, 230, 242),
}
local BANNER_INK: { [string]: Color3 } = {
	Saiyan = C(255, 224, 138), Shinobi = C(232, 244, 208), Pirate = C(244, 240, 224), Shinigami = C(26, 28, 44),
}

---------------------------------------------------------------------
-- TEMAS (uno por franja)
---------------------------------------------------------------------
type River = { Col: Color3, Mat: Enum.Material, Neon: boolean, W: number? }
type Theme = {
	FloorMat: Enum.Material, FloorCol: Color3,
	WallMat: Enum.Material, WallCol: Color3, WallH: number, Cap: string, CapCol: Color3,
	Props: { string }, Spacing: number,
	River: River?, Scatter: string?, Banner: boolean,
	Back: string, BackCol: Color3, BackMat: Enum.Material,
	Rock: Color3, RockMat: Enum.Material,
}

local THEMES: { [string]: Theme } = {
	-- SAIYAN: Red Ribbon -> Namek -> Ruinas / Cell Games -> Dimensión de Buu
	Saiyan_1 = { FloorMat = M.Grass, FloorCol = C(79, 122, 58), WallMat = M.Concrete, WallCol = C(122, 127, 138), WallH = 34, Cap = "wire", CapCol = C(192, 40, 42),
		Props = { "pine" }, Spacing = 13, River = nil, Scatter = "rock", Banner = true,
		Back = "hills", BackCol = C(61, 90, 78), BackMat = M.Grass, Rock = C(120, 118, 112), RockMat = M.Slate },
	Saiyan_2 = { FloorMat = M.Grass, FloorCol = C(107, 191, 138), WallMat = M.Slate, WallCol = C(70, 150, 150), WallH = 50, Cap = "trim", CapCol = C(138, 208, 176),
		Props = { "ajisa" }, Spacing = 20, River = { Col = C(60, 140, 215), Mat = M.Glass, Neon = false }, Scatter = "mesa", Banner = false,
		Back = "mesas", BackCol = C(76, 157, 134), BackMat = M.Slate, Rock = C(90, 170, 150), RockMat = M.Slate },
	Saiyan_3 = { FloorMat = M.Slate, FloorCol = C(140, 122, 94), WallMat = M.Concrete, WallCol = C(110, 100, 90), WallH = 44, Cap = "trim", CapCol = C(80, 72, 66),
		Props = { "ruin", "rock" }, Spacing = 28, River = nil, Scatter = "rock", Banner = false,
		Back = "skyline", BackCol = C(92, 80, 72), BackMat = M.Concrete, Rock = C(106, 96, 84), RockMat = M.Concrete },
	Saiyan_4 = { FloorMat = M.Mud, FloorCol = C(194, 106, 152), WallMat = M.Sandstone, WallCol = C(242, 160, 196), WallH = 50, Cap = "spikes", CapCol = C(255, 210, 230),
		Props = { "spire" }, Spacing = 24, River = nil, Scatter = "spire", Banner = true,
		Back = "spires", BackCol = C(200, 100, 160), BackMat = M.Sandstone, Rock = C(230, 130, 180), RockMat = M.Sandstone },
	-- SHINOBI: País de las Olas -> Lluvia/Sonido -> Suna -> Valle del Fin
	Shinobi_1 = { FloorMat = M.Mud, FloorCol = C(80, 110, 90), WallMat = M.Wood, WallCol = C(184, 162, 106), WallH = 30, Cap = "posts", CapCol = C(120, 96, 56),
		Props = { "bamboo" }, Spacing = 13, River = { Col = C(110, 150, 165), Mat = M.Glass, Neon = false }, Scatter = "rock", Banner = true,
		Back = "hills", BackCol = C(110, 140, 135), BackMat = M.Grass, Rock = C(100, 110, 104), RockMat = M.Slate },
	Shinobi_2 = { FloorMat = M.Concrete, FloorCol = C(74, 85, 96), WallMat = M.Metal, WallCol = C(138, 151, 166), WallH = 56, Cap = "pipes", CapCol = C(90, 100, 114),
		Props = { "steelTower" }, Spacing = 34, River = { Col = C(70, 95, 130), Mat = M.Glass, Neon = false }, Scatter = "rock", Banner = false,
		Back = "towers", BackCol = C(70, 80, 94), BackMat = M.Metal, Rock = C(100, 110, 122), RockMat = M.Concrete },
	Shinobi_3 = { FloorMat = M.Sand, FloorCol = C(216, 184, 120), WallMat = M.Sandstone, WallCol = C(168, 116, 60), WallH = 50, Cap = "trim", CapCol = C(210, 160, 96),
		Props = { "mesa", "cactus" }, Spacing = 28, River = nil, Scatter = "rock", Banner = false,
		Back = "mesas", BackCol = C(185, 133, 74), BackMat = M.Sandstone, Rock = C(196, 150, 90), RockMat = M.Sandstone },
	Shinobi_4 = { FloorMat = M.Slate, FloorCol = C(58, 47, 58), WallMat = M.Slate, WallCol = C(50, 36, 42), WallH = 54, Cap = "trim", CapCol = C(192, 57, 43),
		Props = { "giantTree" }, Spacing = 38, River = { Col = C(120, 170, 210), Mat = M.Glass, Neon = false, W = 10 }, Scatter = "rock", Banner = true,
		Back = "statues", BackCol = C(150, 150, 146), BackMat = M.Slate, Rock = C(70, 58, 66), RockMat = M.Slate },
	-- PIRATA: East Blue -> Baroque/Arlong -> Enies Lobby -> Marineford
	Pirate_1 = { FloorMat = M.Sand, FloorCol = C(217, 197, 138), WallMat = M.Wood, WallCol = C(168, 104, 58), WallH = 28, Cap = "posts", CapCol = C(122, 26, 26),
		Props = { "palm" }, Spacing = 17, River = { Col = C(47, 143, 196), Mat = M.Glass, Neon = false }, Scatter = "rock", Banner = true,
		Back = "hills", BackCol = C(70, 140, 80), BackMat = M.Grass, Rock = C(150, 140, 120), RockMat = M.Slate },
	Pirate_2 = { FloorMat = M.Sand, FloorCol = C(216, 176, 112), WallMat = M.Cobblestone, WallCol = C(58, 120, 180), WallH = 38, Cap = "teeth", CapCol = C(235, 240, 245),
		Props = { "cactus" }, Spacing = 24, River = { Col = C(60, 170, 170), Mat = M.Glass, Neon = false }, Scatter = "rock", Banner = false,
		Back = "dunes", BackCol = C(216, 176, 112), BackMat = M.Sand, Rock = C(190, 150, 96), RockMat = M.Sandstone },
	Pirate_3 = { FloorMat = M.Marble, FloorCol = C(232, 230, 223), WallMat = M.Marble, WallCol = C(240, 240, 236), WallH = 60, Cap = "merlon", CapCol = C(216, 176, 80),
		Props = { "column" }, Spacing = 30, River = { Col = C(110, 190, 230), Mat = M.Glass, Neon = false }, Scatter = nil, Banner = false,
		Back = "whiteRoof", BackCol = C(240, 240, 236), BackMat = M.Marble, Rock = C(236, 236, 230), RockMat = M.Marble },
	Pirate_4 = { FloorMat = M.Basalt, FloorCol = C(74, 64, 56), WallMat = M.Concrete, WallCol = C(200, 205, 210), WallH = 52, Cap = "merlon", CapCol = C(232, 106, 42),
		Props = { "wreck", "iceSpire", "lavaRock" }, Spacing = 26, River = { Col = C(255, 110, 30), Mat = M.Neon, Neon = true, W = 10 }, Scatter = "lavaRock", Banner = true,
		Back = "iceLava", BackCol = C(150, 200, 235), BackMat = M.Ice, Rock = C(50, 42, 38), RockMat = M.Basalt },
	-- SHINIGAMI: Rukongai -> Hueco Mundo -> Las Noches -> Seireitei
	Shinigami_1 = { FloorMat = M.Ground, FloorCol = C(138, 122, 100), WallMat = M.Wood, WallCol = C(122, 82, 50), WallH = 30, Cap = "roof", CapCol = C(58, 62, 76),
		Props = { "bamboo", "lantern" }, Spacing = 14, River = { Col = C(110, 140, 150), Mat = M.Glass, Neon = false }, Scatter = "rock", Banner = true,
		Back = "hills", BackCol = C(90, 70, 60), BackMat = M.Grass, Rock = C(110, 98, 82), RockMat = M.Slate },
	Shinigami_2 = { FloorMat = M.Sand, FloorCol = C(236, 232, 215), WallMat = M.Marble, WallCol = C(240, 239, 232), WallH = 48, Cap = "trim", CapCol = C(200, 205, 225),
		Props = { "deadTree", "spire" }, Spacing = 26, River = nil, Scatter = "spire", Banner = false,
		Back = "dunes", BackCol = C(215, 212, 196), BackMat = M.Sand, Rock = C(236, 236, 240), RockMat = M.Glass },
	Shinigami_3 = { FloorMat = M.Marble, FloorCol = C(216, 218, 224), WallMat = M.Concrete, WallCol = C(236, 238, 244), WallH = 62, Cap = "merlon", CapCol = C(150, 156, 180),
		Props = { "column" }, Spacing = 32, River = nil, Scatter = nil, Banner = false,
		Back = "whiteDome", BackCol = C(240, 242, 248), BackMat = M.Concrete, Rock = C(236, 238, 244), RockMat = M.Marble },
	Shinigami_4 = { FloorMat = M.Slate, FloorCol = C(190, 196, 204), WallMat = M.Concrete, WallCol = C(245, 242, 236), WallH = 46, Cap = "roof", CapCol = C(58, 58, 74),
		Props = { "column" }, Spacing = 34, River = nil, Scatter = "rock", Banner = true,
		Back = "whiteRoof", BackCol = C(240, 236, 228), BackMat = M.Concrete, Rock = C(206, 208, 214), RockMat = M.Slate },
}

---------------------------------------------------------------------
-- GEOMETRÍA
---------------------------------------------------------------------
type Lane = {
	Faction: string, Start: Vector3, Dir: Vector3, Side: Vector3, FanC: number, FanK: number,
	Barrier: Folder, Deco: Folder,
}
type Ctx = { Barrier: Folder, Deco: Folder, Far: boolean }

local lanes: { Lane } = {}
local partCount = 0

local function hw(lane: Lane, u: number): number
	return lane.FanC + lane.FanK * u
end

local function lp(lane: Lane, u: number, v: number, y: number): Vector3
	local p = lane.Start + lane.Dir * u + lane.Side * v
	return Vector3.new(p.X, y, p.Z)
end

-- tangente de la diagonal y normal hacia el centro del abanico
local function edgeFrame(lane: Lane, s: number): (Vector3, Vector3)
	local t = (lane.Dir + lane.Side * (s * lane.FanK)).Unit
	local n = Vector3.new(-t.Z, 0, t.X)
	if n:Dot(lane.Side * -s) < 0 then
		n = -n
	end
	return t, n
end

-- punto de la franja a distancia perpendicular "inset" de la diagonal (hacia adentro; negativo = afuera)
local function edgePoint(lane: Lane, s: number, u: number, inset: number, n: Vector3): Vector3
	return lp(lane, u, s * hw(lane, u), FLOOR_TOP) + n * inset
end

---------------------------------------------------------------------
-- PARTES
---------------------------------------------------------------------
local function breathe()
	partCount += 1
	if partCount % 90 == 0 then
		task.wait()
	end
end

local function mk(c: Ctx, shape: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, transp: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	if shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	elseif shape == "Cyl" then
		p.Shape = Enum.PartType.Cylinder
	end
	p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.Surface.Smooth
	p.BottomSurface = Enum.Surface.Smooth
	if transp then
		p.Transparency = transp
	end
	local real = collide and not c.Far
	p.CanCollide = real
	if not real then
		p.CanQuery = false
		p.CanTouch = false
	end
	p.CastShadow = real
	p.Parent = if real then c.Barrier else c.Deco
	breathe()
	return p
end

local function blk(c: Ctx, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, transp: number?): Part
	return mk(c, "Block", size, cf, color, mat, collide, transp)
end

-- cilindro vertical con la base en "base" (rot gira/inclina desde la base)
local function cylV(c: Ctx, base: Vector3, r: number, h: number, color: Color3, mat: Enum.Material, collide: boolean, rot: CFrame?): Part
	local cf = CFrame.new(base) * (rot or CFrame.identity) * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
	return mk(c, "Cyl", Vector3.new(h, r * 2, r * 2), cf, color, mat, collide)
end

local function ball(c: Ctx, center: Vector3, d: number, color: Color3, mat: Enum.Material, collide: boolean): Part
	return mk(c, "Ball", Vector3.new(d, d, d), CFrame.new(center), color, mat, collide)
end

local function ellipsoid(c: Ctx, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material): Part
	local p = blk(c, size, cf, color, mat, false)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function shade(col: Color3, k: number): Color3
	return Color3.new(math.clamp(col.R * k, 0, 1), math.clamp(col.G * k, 0, 1), math.clamp(col.B * k, 0, 1))
end

local Y = Vector3.new(0, 1, 0)

---------------------------------------------------------------------
-- OBJETOS PEGADOS AL MURO (collide = solo tronco/base)
---------------------------------------------------------------------
type PropFn = (c: Ctx, p: Vector3, rng: Random, th: Theme) -> ()
local PROPS: { [string]: { R: number, F: PropFn } } = {}

PROPS.pine = { R = 2.2, F = function(c, p, rng, th)
	local s = 0.9 + rng:NextNumber() * 0.45
	cylV(c, p, 1.5 * s, 12 * s, C(92, 64, 44), M.Wood, true)
	for k = 0, 3 do
		cylV(c, p + Y * ((5 + k * 5) * s), (9 - k * 2.1) * s, 6 * s, shade(C(36, 72, 46), 0.9 + rng:NextNumber() * 0.25), M.Grass, false)
	end
end }

PROPS.ajisa = { R = 2.2, F = function(c, p, rng, th)
	local h = 20 + rng:NextNumber() * 8
	cylV(c, p, 1.8, h, C(168, 128, 84), M.Wood, true)
	ball(c, p + Y * (h + 6), 28 + rng:NextNumber() * 6, C(70, 160, 98), M.Grass, false)
	ball(c, p + Y * (h + 1) + Vector3.new(7, 0, 4), 14, C(54, 140, 86), M.Grass, false)
end }

PROPS.bamboo = { R = 3.2, F = function(c, p, rng, th)
	for k = 1, 3 do
		local o = Vector3.new(rng:NextNumber() * 4 - 2, 0, rng:NextNumber() * 4 - 2)
		local h = 30 + rng:NextNumber() * 16
		local col = shade(C(110, 170, 70), 0.85 + rng:NextNumber() * 0.3)
		cylV(c, p + o, 0.8, h, col, M.Wood, true)
		cylV(c, p + o + Y * (h * 0.35), 1.05, 0.5, shade(col, 0.7), M.Wood, false)
		cylV(c, p + o + Y * (h * 0.7), 1.05, 0.5, shade(col, 0.7), M.Wood, false)
		ball(c, p + o + Y * h, 7, shade(col, 1.1), M.Grass, false)
	end
end }

PROPS.palm = { R = 2, F = function(c, p, rng, th)
	local rot = CFrame.Angles(math.rad(rng:NextNumber() * 14 - 7), rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 14 - 7))
	local h = 18 + rng:NextNumber() * 5
	cylV(c, p, 1.3, h, C(150, 108, 70), M.Wood, true, rot)
	local top = (CFrame.new(p) * rot * CFrame.new(0, h, 0)).Position
	for k = 1, 6 do
		local cf = CFrame.new(top) * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.Angles(0, 0, -math.rad(22)) * CFrame.new(7.5, 0, 0)
		blk(c, Vector3.new(15, 0.4, 4), cf, C(52, 130, 62), M.Grass, false)
	end
	ball(c, top - Y * 1.2, 2.6, C(110, 78, 46), M.Wood, false)
end }

PROPS.rock = { R = 6, F = function(c, p, rng, th)
	local sz = Vector3.new(10 + rng:NextNumber() * 5, 8 + rng:NextNumber() * 6, 10 + rng:NextNumber() * 5)
	local cf = CFrame.new(p + Y * (sz.Y / 2 - 1)) * CFrame.Angles(math.rad(rng:NextNumber() * 8), rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 8))
	blk(c, sz, cf, shade(th.Rock, 0.9 + rng:NextNumber() * 0.2), th.RockMat, true)
	blk(c, sz * 0.45, cf * CFrame.new(sz.X * 0.5, -sz.Y * 0.2, 0), shade(th.Rock, 1.1), th.RockMat, false)
end }

PROPS.mesa = { R = 13, F = function(c, p, rng, th)
	local h = 22 + rng:NextNumber() * 8
	cylV(c, p, 13, h, th.Rock, th.RockMat, true)
	cylV(c, p + Y * 7, 14.5, 3, shade(th.Rock, 0.85), th.RockMat, false)
	cylV(c, p + Y * h, 11.5, 2, shade(th.Rock, 1.15), th.RockMat, false)
end }

PROPS.spire = { R = 4, F = function(c, p, rng, th)
	local h = 10 + rng:NextNumber() * 5
	cylV(c, p, 4, h, th.Rock, th.RockMat, true)
	cylV(c, p + Y * h, 3, h * 0.9, shade(th.Rock, 1.05), th.RockMat, false)
	cylV(c, p + Y * h * 1.9, 2, h * 0.8, shade(th.Rock, 1.1), th.RockMat, false)
	cylV(c, p + Y * h * 2.7, 1, h * 0.7, shade(th.Rock, 1.2), th.RockMat, false)
end }

PROPS.ruin = { R = 7.5, F = function(c, p, rng, th)
	local h = 30 + rng:NextNumber() * 28
	local yaw = rng:NextNumber() * 6.28
	local rot = CFrame.Angles(0, yaw, math.rad(rng:NextNumber() * 8 - 4))
	local cf = CFrame.new(p) * rot * CFrame.new(0, h / 2 - 1, 0)
	blk(c, Vector3.new(14, h, 14), cf, shade(th.Rock, 0.85 + rng:NextNumber() * 0.3), th.RockMat, true)
	for k = 1, 4 do
		local y = -h / 2 + 8 + k * (h - 12) / 5
		blk(c, Vector3.new(5, 4, 0.4), cf * CFrame.new((k % 2) * 4 - 2, y, -7.1), C(26, 24, 28), M.SmoothPlastic, false)
	end
	blk(c, Vector3.new(9, 4, 8), CFrame.new(p) * CFrame.Angles(0, yaw + 0.6, 0) * CFrame.new(11, 1, 0), shade(th.Rock, 0.8), th.RockMat, false)
end }

PROPS.steelTower = { R = 5.2, F = function(c, p, rng, th)
	local h = 60 + rng:NextNumber() * 26
	cylV(c, p, 5, h, C(112, 124, 138), M.Metal, true)
	for k = 1, 5 do
		cylV(c, p + Y * (k * h / 6), 5.7, 1.2, C(78, 88, 100), M.Metal, false)
	end
	cylV(c, p + Y * h, 0.6, 22, C(160, 168, 178), M.Metal, false)
	ball(c, p + Y * (h + 22), 2.2, C(255, 70, 70), M.Neon, false)
end }

PROPS.cactus = { R = 2.4, F = function(c, p, rng, th)
	local h = 12 + rng:NextNumber() * 5
	local g = C(84, 140, 76)
	cylV(c, p, 2, h, g, M.Grass, true)
	for _, sgn in ipairs({ -1, 1 }) do
		local ay = h * (0.4 + rng:NextNumber() * 0.2)
		blk(c, Vector3.new(5, 1.8, 1.8), CFrame.new(p + Vector3.new(sgn * 3.4, ay, 0)), g, M.Grass, false)
		cylV(c, p + Vector3.new(sgn * 5.6, ay, 0), 0.9, 5, g, M.Grass, false)
	end
end }

PROPS.deadTree = { R = 2.4, F = function(c, p, rng, th)
	local h = 26 + rng:NextNumber() * 8
	local col = C(240, 238, 228)
	cylV(c, p, 1.8, h, col, M.Sandstone, true)
	for k = 1, 4 do
		local rot = CFrame.Angles(0, k * 1.57 + rng:NextNumber(), math.rad(35 + rng:NextNumber() * 20))
		cylV(c, p + Y * (h * (0.55 + k * 0.1)), 0.7, 12, col, M.Sandstone, false, rot)
	end
end }

PROPS.column = { R = 4.6, F = function(c, p, rng, th)
	local h = 38 + rng:NextNumber() * 8
	blk(c, Vector3.new(9, 2.5, 9), CFrame.new(p + Y * 1.2), shade(th.Rock, 0.92), th.RockMat, true)
	cylV(c, p + Y * 2.5, 3, h, th.Rock, th.RockMat, true)
	blk(c, Vector3.new(9, 3, 9), CFrame.new(p + Y * (h + 4)), shade(th.Rock, 0.92), th.RockMat, false)
	blk(c, Vector3.new(11, 1.5, 11), CFrame.new(p + Y * (h + 6.2)), shade(th.Rock, 0.85), th.RockMat, false)
end }

PROPS.iceSpire = { R = 4, F = function(c, p, rng, th)
	local h = 30 + rng:NextNumber() * 14
	local cf = CFrame.new(p + Y * (h / 2 - 1)) * CFrame.Angles(math.rad(rng:NextNumber() * 8 - 4), rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 10 - 5))
	blk(c, Vector3.new(6, h, 6), cf, C(160, 215, 245), M.Ice, true, 0.1)
	blk(c, Vector3.new(3.5, h * 0.7, 3.5), cf * CFrame.new(5, -h * 0.12, 1) * CFrame.Angles(0, 0.4, 0.15), C(190, 232, 252), M.Ice, false, 0.1)
end }

PROPS.wreck = { R = 9, F = function(c, p, rng, th)
	local yaw = rng:NextNumber() * 6.28
	local base = CFrame.new(p) * CFrame.Angles(0, yaw, 0)
	blk(c, Vector3.new(24, 9, 10), base * CFrame.new(0, 3.2, 0) * CFrame.Angles(0, 0, math.rad(16)), C(96, 66, 44), M.Wood, true)
	blk(c, Vector3.new(20, 0.8, 8), base * CFrame.new(0, 6.6, 0) * CFrame.Angles(0, 0, math.rad(16)), C(130, 92, 60), M.WoodPlanks, false)
	cylV(c, p + base:VectorToWorldSpace(Vector3.new(-2, 6, 0)), 0.9, 30, C(80, 56, 38), M.Wood, false, CFrame.Angles(0, yaw, math.rad(-18)))
	blk(c, Vector3.new(0.4, 16, 11), base * CFrame.new(-8, 20, 0) * CFrame.Angles(0, 0, math.rad(-18)), C(232, 232, 224), M.Fabric, false)
end }

PROPS.lavaRock = { R = 6, F = function(c, p, rng, th)
	local sz = Vector3.new(10 + rng:NextNumber() * 4, 9 + rng:NextNumber() * 5, 10 + rng:NextNumber() * 4)
	local cf = CFrame.new(p + Y * (sz.Y / 2 - 1)) * CFrame.Angles(0, rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 8))
	blk(c, sz, cf, C(42, 34, 30), M.Basalt, true)
	blk(c, Vector3.new(sz.X * 0.8, 0.6, 1.4), cf * CFrame.new(0, sz.Y / 2 + 0.1, 0), C(255, 110, 30), M.Neon, false)
end }

PROPS.lantern = { R = 1.2, F = function(c, p, rng, th)
	cylV(c, p, 0.7, 11, C(86, 60, 40), M.Wood, true)
	blk(c, Vector3.new(2.6, 3.2, 2.6), CFrame.new(p + Y * 12.4), C(255, 190, 110), M.Neon, false)
	blk(c, Vector3.new(4, 0.8, 4), CFrame.new(p + Y * 14.4), C(50, 40, 40), M.Wood, false)
end }

PROPS.giantTree = { R = 9, F = function(c, p, rng, th)
	local h = 44 + rng:NextNumber() * 10
	cylV(c, p, 8, h, C(88, 62, 44), M.Wood, true)
	ball(c, p + Y * (h + 14), 52 + rng:NextNumber() * 10, C(46, 100, 56), M.Grass, false)
	ball(c, p + Y * (h + 2) + Vector3.new(14, 0, 8), 30, C(40, 90, 50), M.Grass, false)
	ball(c, p + Y * (h + 4) + Vector3.new(-12, 0, -6), 26, C(52, 108, 60), M.Grass, false)
end }

---------------------------------------------------------------------
-- ESCENOGRAFÍA DE FONDO (sin colisión, afuera del muro)
---------------------------------------------------------------------
type BackFn = (c: Ctx, p: Vector3, n: Vector3, rng: Random, th: Theme) -> ()
local BACK: { [string]: BackFn } = {}
local LOW = FLOOR_TOP - 45

BACK.mesas = function(c, p, n, rng, th)
	local r = 28 + rng:NextNumber() * 28
	local h = 130 + rng:NextNumber() * 100
	cylV(c, Vector3.new(p.X, LOW, p.Z), r, h + 45, th.BackCol, th.BackMat, false)
	cylV(c, Vector3.new(p.X, LOW + h * 0.45, p.Z), r * 1.12, 8, shade(th.BackCol, 0.8), th.BackMat, false)
	cylV(c, Vector3.new(p.X, LOW + h + 45, p.Z), r * 0.95, 4, shade(th.BackCol, 1.2), th.BackMat, false)
end

BACK.hills = function(c, p, n, rng, th)
	local s = Vector3.new(160 + rng:NextNumber() * 120, 70 + rng:NextNumber() * 70, 160 + rng:NextNumber() * 120)
	ellipsoid(c, CFrame.new(p.X, FLOOR_TOP + 4, p.Z) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), s, shade(th.BackCol, 0.9 + rng:NextNumber() * 0.25), th.BackMat)
end

BACK.dunes = function(c, p, n, rng, th)
	local s = Vector3.new(220 + rng:NextNumber() * 160, 40 + rng:NextNumber() * 40, 160 + rng:NextNumber() * 100)
	ellipsoid(c, CFrame.new(p.X, FLOOR_TOP, p.Z) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), s, shade(th.BackCol, 0.92 + rng:NextNumber() * 0.15), th.BackMat)
end

BACK.towers = function(c, p, n, rng, th)
	local r = 8 + rng:NextNumber() * 6
	local h = 150 + rng:NextNumber() * 110
	cylV(c, Vector3.new(p.X, LOW, p.Z), r, h + 45, th.BackCol, th.BackMat, false)
	for k = 1, 6 do
		cylV(c, Vector3.new(p.X, LOW + k * (h + 45) / 7, p.Z), r * 1.2, 2, shade(th.BackCol, 0.7), th.BackMat, false)
	end
	cylV(c, Vector3.new(p.X, LOW + h + 45, p.Z), 1, 40, shade(th.BackCol, 1.4), th.BackMat, false)
	ball(c, Vector3.new(p.X, LOW + h + 85, p.Z), 4, C(255, 70, 70), M.Neon, false)
end

BACK.skyline = function(c, p, n, rng, th)
	local w = 30 + rng:NextNumber() * 24
	local h = 100 + rng:NextNumber() * 120
	local cf = CFrame.new(p.X, LOW + (h + 45) / 2, p.Z) * CFrame.Angles(math.rad(rng:NextNumber() * 8 - 4), rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 8 - 4))
	blk(c, Vector3.new(w, h + 45, w), cf, shade(th.BackCol, 0.85 + rng:NextNumber() * 0.3), th.BackMat, false)
	for k = 1, 4 do
		blk(c, Vector3.new(6, 5, 0.5), cf * CFrame.new((k % 2) * 8 - 4, h / 2 - 10 - k * 14, -w / 2 - 0.2), C(255, 205, 110), M.Neon, false)
	end
end

BACK.spires = function(c, p, n, rng, th)
	local r = 14 + rng:NextNumber() * 10
	local h = 80 + rng:NextNumber() * 60
	for k = 0, 3 do
		cylV(c, Vector3.new(p.X, LOW + k * (h + 45) / 3.2, p.Z), r * (1 - k * 0.22), (h + 45) / 3.2 + 2, shade(th.BackCol, 0.9 + k * 0.08), th.BackMat, false)
	end
	ball(c, Vector3.new(p.X, LOW + h + 52, p.Z), 6, C(255, 220, 240), M.Neon, false)
end

BACK.whiteDome = function(c, p, n, rng, th)
	local w = 40 + rng:NextNumber() * 30
	local h = 90 + rng:NextNumber() * 90
	blk(c, Vector3.new(w, h + 45, w), CFrame.new(p.X, LOW + (h + 45) / 2, p.Z), th.BackCol, th.BackMat, false)
	blk(c, Vector3.new(w + 2, 6, w + 2), CFrame.new(p.X, LOW + h * 0.6, p.Z), C(30, 32, 44), M.Slate, false)
	ellipsoid(c, CFrame.new(p.X, LOW + h + 45, p.Z), Vector3.new(w * 0.9, w * 0.7, w * 0.9), shade(th.BackCol, 0.95), th.BackMat)
end

BACK.whiteRoof = function(c, p, n, rng, th)
	local w = 40 + rng:NextNumber() * 30
	local h = 90 + rng:NextNumber() * 80
	blk(c, Vector3.new(w, h + 45, w), CFrame.new(p.X, LOW + (h + 45) / 2, p.Z), th.BackCol, th.BackMat, false)
	blk(c, Vector3.new(w + 10, 5, w + 10), CFrame.new(p.X, LOW + h + 47, p.Z), C(52, 54, 68), M.Slate, false)
	blk(c, Vector3.new(w - 6, 5, w - 6), CFrame.new(p.X, LOW + h + 52, p.Z), C(40, 42, 56), M.Slate, false)
	for k = 1, 3 do
		blk(c, Vector3.new(7, 14, 0.5), CFrame.new(p.X + (k - 2) * w * 0.26, LOW + h * 0.5, p.Z) , C(40, 52, 80), M.Glass, false)
	end
end

BACK.iceLava = function(c, p, n, rng, th)
	local h = 90 + rng:NextNumber() * 80
	local cf = CFrame.new(p.X, LOW + (h + 45) / 2, p.Z) * CFrame.Angles(math.rad(rng:NextNumber() * 10 - 5), rng:NextNumber() * 6.28, math.rad(rng:NextNumber() * 10 - 5))
	blk(c, Vector3.new(26 + rng:NextNumber() * 16, h + 45, 26 + rng:NextNumber() * 16), cf, th.BackCol, M.Ice, false, 0.1)
	blk(c, Vector3.new(60, 8, 60), CFrame.new(p.X, FLOOR_TOP - 4, p.Z), C(255, 110, 30), M.Neon, false)
end

BACK.statues = function(c, p, n, rng, th)
	-- un mismo estilo de montaña lejana; las estatuas gigantes se ponen aparte (ver buildStatues)
	local s = Vector3.new(180 + rng:NextNumber() * 100, 90 + rng:NextNumber() * 70, 160 + rng:NextNumber() * 80)
	ellipsoid(c, CFrame.new(p.X, FLOOR_TOP + 2, p.Z) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), s, C(72, 56, 66), M.Slate)
end

local function buildStatue(c: Ctx, base: Vector3, n: Vector3, col: Color3)
	-- figura sentada de ~120 studs que mira hacia el centro de la franja (el Valle del Fin)
	local look = CFrame.lookAt(Vector3.new(base.X, 0, base.Z), Vector3.new(base.X, 0, base.Z) + n)
	local function at(x: number, y: number, z: number): CFrame
		return look * CFrame.new(x, y, z)
	end
	blk(c, Vector3.new(60, 40, 60), at(0, LOW + 20, 0), shade(col, 0.8), M.Slate, false)
	blk(c, Vector3.new(44, 40, 30), at(0, LOW + 60, 6), col, M.Slate, false)
	blk(c, Vector3.new(34, 60, 22), at(0, LOW + 110, 8), col, M.Slate, false)
	ellipsoid(c, at(0, LOW + 156, 8), Vector3.new(26, 30, 26), shade(col, 1.05), M.Slate)
	blk(c, Vector3.new(10, 50, 10), at(-24, LOW + 120, -6) * CFrame.Angles(math.rad(-50), 0, 0), col, M.Slate, false)
	blk(c, Vector3.new(10, 50, 10), at(24, LOW + 118, -6) * CFrame.Angles(math.rad(-70), 0, 0), col, M.Slate, false)
	blk(c, Vector3.new(8, 90, 8), at(0, LOW + 44, -26), C(235, 245, 255), M.Neon, false, 0.55) -- cascada
end

---------------------------------------------------------------------
-- MURO, TOPE, RÍO, BANDERAS
---------------------------------------------------------------------
local function wallFace(cf: CFrame, n: Vector3): Enum.NormalId
	if cf.RightVector:Dot(n) > 0 then
		return Enum.NormalId.Right
	end
	return Enum.NormalId.Left
end

local function addTexture(part: BasePart, key: string, face: Enum.NormalId, tile: number, tileV: number)
	local id = BiomeAssets.Get(key)
	if not id then
		return
	end
	local tex = Instance.new("Texture")
	tex.Texture = id
	tex.Face = face
	tex.StudsPerTileU = tile
	tex.StudsPerTileV = tileV
	tex.Parent = part
end

local function buildCap(c: Ctx, th: Theme, a: Vector3, t: Vector3, len: number, H: number)
	local top = a + Y * H
	local function along(d: number): Vector3
		return top + t * d
	end
	local function look(pos: Vector3): CFrame
		return CFrame.lookAt(pos, pos + t)
	end
	-- remate base en todos los estilos
	blk(c, Vector3.new(WALL_T + 1.2, 1.6, len), look(top + t * (len / 2) + Y * 0.8), th.CapCol, th.WallMat, false)
	local cap = th.Cap
	if cap == "merlon" then
		local d = 4
		while d < len - 4 do
			blk(c, Vector3.new(WALL_T + 0.6, 5, 7), look(along(d) + Y * 4.1), th.WallCol, th.WallMat, false)
			d += 16
		end
	elseif cap == "roof" then
		blk(c, Vector3.new(WALL_T + 7, 2.5, len), look(top + t * (len / 2) + Y * 2.8), th.CapCol, M.Slate, false)
		blk(c, Vector3.new(WALL_T + 2.5, 2, len), look(top + t * (len / 2) + Y * 4.8), shade(th.CapCol, 0.8), M.Slate, false)
	elseif cap == "posts" then
		local d = 6
		while d < len - 4 do
			cylV(c, along(d), 1.1, 9, th.CapCol, M.Wood, false)
			d += 20
		end
	elseif cap == "wire" then
		local d = 6
		while d < len - 4 do
			cylV(c, along(d), 0.4, 7, C(60, 62, 70), M.Metal, false)
			d += 24
		end
		blk(c, Vector3.new(0.3, 0.3, len), look(top + t * (len / 2) + Y * 6), C(40, 40, 46), M.Metal, false)
		blk(c, Vector3.new(0.3, 0.3, len), look(top + t * (len / 2) + Y * 4), C(40, 40, 46), M.Metal, false)
	elseif cap == "spikes" then
		local d = 5
		while d < len - 4 do
			blk(c, Vector3.new(1.6, 11, 1.6), look(along(d) + Y * 7) * CFrame.Angles(0, 0, math.rad(8)), th.CapCol, th.WallMat, false)
			d += 14
		end
	elseif cap == "teeth" then
		local d = 5
		while d < len - 4 do
			blk(c, Vector3.new(3.6, 3.6, 5), look(along(d) + Y * 3.4) * CFrame.Angles(0, 0, math.rad(45)), th.CapCol, M.Marble, false)
			d += 10
		end
	elseif cap == "pipes" then
		for _, off in ipairs({ -1.2, 1.2 }) do
			local pos = top + t * (len / 2) + Y * 2.6
			mk(c, "Cyl", Vector3.new(len, 1.6, 1.6), CFrame.lookAt(pos, pos + t) * CFrame.new(off, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), C(96, 106, 120), M.Metal, false)
		end
	end
end

local function makeBanner(c: Ctx, faction: string, base: Vector3, n: Vector3)
	cylV(c, base, 0.8, 46, C(74, 60, 48), M.Wood, true)
	local cfCloth = CFrame.lookAt(base + Y * 31 + n * 1.6, base + Y * 31 + n * 8)
	local cloth = blk(c, Vector3.new(14, 26, 0.5), cfCloth, BANNER_COLOR[faction], M.Fabric, false)
	local id = BiomeAssets.Get(faction .. "_banner")
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		if id then
			local d = Instance.new("Decal")
			d.Texture = id
			d.Face = face
			d.Parent = cloth
		else
			local sg = Instance.new("SurfaceGui")
			sg.Face = face
			sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			sg.PixelsPerStud = 30
			sg.Parent = cloth
			local tl = Instance.new("TextLabel")
			tl.Size = UDim2.fromScale(1, 1)
			tl.BackgroundTransparency = 1
			tl.Text = BANNER_TEXT[faction]
			tl.TextScaled = true
			tl.TextColor3 = BANNER_INK[faction]
			tl.Font = Enum.Font.GothamBold
			tl.Parent = sg
		end
	end
	blk(c, Vector3.new(15, 0.8, 0.8), CFrame.lookAt(base + Y * 44.8 + n * 1.6, base + Y * 44.8 + n * 8), C(74, 60, 48), M.Wood, false)
end

local function buildSide(lane: Lane, faction: string, strip: number, s: number, th: Theme, folderParent: Folder)
	local key = faction .. "_" .. strip
	local rng = Random.new(strip * 977 + (if s > 0 then 31 else 7) + #faction * 101)
	local c: Ctx = { Barrier = lane.Barrier, Deco = lane.Deco, Far = false }
	local t, n = edgeFrame(lane, s)
	local u0 = CITY_SIZE + (strip - 1) * STRIP_DEPTH
	local u1 = u0 + STRIP_DEPTH
	local ua, ub = u0 + GATE_MARGIN, u1 - GATE_MARGIN

	-- MURO visible (colisión real; detrás está el muro invisible de la diagonal)
	local a = edgePoint(lane, s, ua, WALL_T / 2 + 0.15, n)
	local b = edgePoint(lane, s, ub, WALL_T / 2 + 0.15, n)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2 + Y * (th.WallH / 2)
	local wcf = CFrame.lookAt(mid, mid + t)
	local wall = blk(c, Vector3.new(WALL_T, th.WallH, len), wcf, th.WallCol, th.WallMat, true)
	wall.Name = "Muro_" .. key
	addTexture(wall, key .. "_wall", wallFace(wcf, n), 36, 36)
	buildCap(c, th, a, t, len, th.WallH)

	-- RÍO / LAVA junto al muro
	local baseInset = WALL_T + 0.4
	local river = th.River
	if river then
		local rw = river.W or RIVER_W
		local ri = baseInset
		local rp = edgePoint(lane, s, (ua + ub) / 2, ri + rw / 2, n)
		local water = blk(c, Vector3.new(rw, 0.6, len), CFrame.lookAt(rp + Y * 0.4, rp + Y * 0.4 + t), river.Col, river.Mat, false, if river.Neon then 0 else 0.25)
		water.Name = "Rio_" .. key
		-- orilla: pared invisible que no deja entrar al agua
		local bp = edgePoint(lane, s, (ua + ub) / 2, ri + rw + 1, n)
		local bank = blk(c, Vector3.new(2, 40, len), CFrame.lookAt(bp + Y * 20, bp + Y * 20 + t), Color3.new(1, 1, 1), M.SmoothPlastic, true, 1)
		bank.CanQuery = false
		bank.CanTouch = false
		bank.CastShadow = false
		bank.Name = "OrillaInvisible_" .. key
		-- piedras de la orilla (decoración)
		local d = ua + 10
		while d < ub - 10 do
			local pos = edgePoint(lane, s, d, ri + rw + 2.5, n)
			blk(c, Vector3.new(4 + rng:NextNumber() * 3, 2, 3 + rng:NextNumber() * 3), CFrame.new(pos + Y * 1) * CFrame.Angles(0, rng:NextNumber() * 6.28, 0), shade(th.Rock, 0.9), th.RockMat, false)
			d += 18 + rng:NextNumber() * 12
		end
		baseInset = ri + rw + 3.5
	end

	-- OBJETOS pegados al muro (o a la orilla)
	local u = ua + PROP_MARGIN
	local idx = 0
	while u < ub - PROP_MARGIN do
		idx += 1
		local kind = th.Props[(idx - 1) % #th.Props + 1]
		local def = PROPS[kind]
		if def then
			local pos = edgePoint(lane, s, u, baseInset + def.R, n)
			def.F(c, pos, rng, th)
		end
		u += th.Spacing * (0.85 + rng:NextNumber() * 0.3)
	end

	-- OBJETOS sueltos (rocas aisladas): nunca más allá de 34 studs del borde, para no tapar el spawn de enemigos (nacen a 45+)
	if th.Scatter and PROPS[th.Scatter] then
		local def = PROPS[th.Scatter]
		local room = 34 - (baseInset + 2 * def.R + 4)
		if room > 0 then
			local su = ua + 60 + rng:NextNumber() * 40
			while su < ub - 60 do
				local pos = edgePoint(lane, s, su, baseInset + def.R + 4 + rng:NextNumber() * room, n)
				def.F(c, pos, rng, th)
				su += 90 + rng:NextNumber() * 70
			end
		end
	end

	-- BANDERAS
	if th.Banner then
		local bu = ua + 70
		while bu < ub - 40 do
			makeBanner(c, faction, edgePoint(lane, s, bu, baseInset + 1.6, n), n)
			bu += 110
		end
	end

	-- ESCENOGRAFÍA lejana, afuera del muro (sin colisión)
	local far: Ctx = { Barrier = lane.Barrier, Deco = lane.Deco, Far = true }
	local backFn = BACK[th.Back]
	if backFn then
		local bu = ua + 30
		while bu < ub - 20 do
			local out = -(20 + rng:NextNumber() * 70)
			backFn(far, edgePoint(lane, s, bu, out, n), n, rng, th)
			bu += 70 + rng:NextNumber() * 50
		end
	end

	-- Valle del Fin: dos estatuas gigantes frente a frente, una a cada lado, a la mitad de la franja 4
	if th.Back == "statues" then
		buildStatue(far, edgePoint(lane, s, (u0 + u1) / 2, -90, n), n, th.BackCol)
	end
end

---------------------------------------------------------------------
-- SUELO
---------------------------------------------------------------------
local function styleFloor(biome: Instance, faction: string)
	local fan = biome:FindFirstChild("Abanico")
	local piso = fan and fan:FindFirstChild("Piso")
	if not piso then
		return
	end
	for _, zone in ipairs(piso:GetChildren()) do
		local idx = tonumber(string.match(zone.Name, "Franja(%d)"))
		local th = idx and THEMES[faction .. "_" .. idx]
		if th then
			local id = BiomeAssets.Get(faction .. "_" .. idx .. "_floor")
			for _, part in ipairs(zone:GetChildren()) do
				if part:IsA("BasePart") then
					part.Material = th.FloorMat
					part.Color = th.FloorCol
					if id then
						local tex = Instance.new("Texture")
						tex.Texture = id
						tex.Face = Enum.NormalId.Top
						tex.StudsPerTileU = 64
						tex.StudsPerTileV = 64
						tex.Parent = part
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- LANES
---------------------------------------------------------------------
local function readLane(biome: Instance, faction: string): Lane?
	local fan = biome:FindFirstChild("Abanico")
	local piso = fan and fan:FindFirstChild("Piso")
	local sample: BasePart? = nil
	if piso then
		for _, d in ipairs(piso:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("LaneStart") then
				sample = d
				break
			end
		end
	end
	if not sample then
		return nil
	end
	local start = sample:GetAttribute("LaneStart") :: Vector3
	local dir = sample:GetAttribute("LaneDir") :: Vector3
	local old = biome:FindFirstChild("Biomas")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Biomas"
	local barrier = Instance.new("Folder")
	barrier.Name = "Barreras"
	barrier.Parent = root
	local deco = Instance.new("Folder")
	deco.Name = "Decoracion"
	deco.Parent = root
	root.Parent = biome
	return {
		Faction = faction, Start = start, Dir = dir, Side = Vector3.new(-dir.Z, 0, dir.X),
		FanC = sample:GetAttribute("FanC") :: number, FanK = sample:GetAttribute("FanK") :: number,
		Barrier = barrier, Deco = deco,
	}
end

local function styleBiome(biome: Instance, faction: string)
	styleFloor(biome, faction)
	local lane = readLane(biome, faction)
	if not lane then
		warn("[BiomeStyler] Sin datos de carril en " .. biome.Name)
		return
	end
	table.insert(lanes, lane)
	for strip = 1, STRIP_COUNT do
		local th = THEMES[faction .. "_" .. strip]
		if th then
			for _, s in ipairs({ -1, 1 }) do
				local ok, err = pcall(buildSide, lane, faction, strip, s, th, lane.Deco)
				if not ok then
					warn(string.format("[BiomeStyler] %s_%d lado %d: %s", faction, strip, s, tostring(err)))
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- ZONA DEL JUGADOR + ANTI-ATASCO
---------------------------------------------------------------------
local function zoneOf(pos: Vector3): (string?, Lane?, number, number)
	for _, lane in ipairs(lanes) do
		local rel = pos - lane.Start
		local u = rel:Dot(lane.Dir)
		if u >= CITY_SIZE - 20 and u <= CITY_SIZE + STRIP_DEPTH * STRIP_COUNT then
			local v = rel:Dot(lane.Side)
			if math.abs(v) <= hw(lane, u) + 10 then
				local i = math.clamp(math.floor((u - CITY_SIZE) / STRIP_DEPTH) + 1, 1, STRIP_COUNT)
				return lane.Faction .. "_" .. i, lane, u, v
			end
		end
	end
	return nil, nil, 0, 0
end

local function startWatcher()
	local strikes: { [Player]: number } = {}
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local folders: { Instance } = {}
	for _, lane in ipairs(lanes) do
		table.insert(folders, lane.Barrier)
	end
	params.FilterDescendantsInstances = folders
	params.RespectCanCollide = true
	task.spawn(function()
		while true do
			task.wait(1)
			for _, pl in ipairs(Players:GetPlayers()) do
				local char = pl.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local zone, lane, u, v = zoneOf(hrp.Position)
					local name = zone or ""
					if pl:GetAttribute("BiomeZone") ~= name then
						pl:SetAttribute("BiomeZone", name)
					end
					local stuck = false
					if lane and hrp.Position.Y < FLOOR_TOP + 60 then
						local hits = Workspace:GetPartBoundsInBox(CFrame.new(hrp.Position), Vector3.new(1.4, 3.5, 1.4), params)
						stuck = #hits > 0
					end
					if stuck and lane then
						strikes[pl] = (strikes[pl] or 0) + 1
						if strikes[pl] >= 2 then
							strikes[pl] = 0
							local target = lp(lane, u, 0, FLOOR_TOP + 4)
							pcall(function()
								(char :: Model):PivotTo(CFrame.new(target))
							end)
							warn(string.format("[BiomeStyler] %s estaba atascado en %s: movido al centro de la franja.", pl.Name, tostring(zone)))
						end
					else
						strikes[pl] = 0
					end
				end
			end
		end
	end)
end

local function run()
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	local map = Workspace:WaitForChild(MAP_NAME, 60)
	if not map then
		warn("[BiomeStyler] No existe " .. MAP_NAME)
		Workspace:SetAttribute("BiomeStyleDone", true)
		return
	end
	local done, failed = 0, 0
	for _, biome in ipairs(map:GetChildren()) do
		local faction = BIOME_FACTION[biome.Name]
		if faction then
			local ok, err = pcall(styleBiome, biome, faction)
			if ok then
				done += 1
			else
				failed += 1
				warn("[BiomeStyler] Error en " .. biome.Name .. ": " .. tostring(err))
			end
		end
	end
	startWatcher()
	Workspace:SetAttribute("BiomeStyleStatus", string.format("%d biomas con estilo, %d con error, %d partes", done, failed, partCount))
	Workspace:SetAttribute("BiomeStyleDone", true)
	print(string.format("[BiomeStyler] Biomas listos: %d facciones, %d partes.", done, partCount))
end

local BiomeStyler = {}
BiomeStyler.Run = run

if ENABLED then
	task.spawn(run)
end

return BiomeStyler
