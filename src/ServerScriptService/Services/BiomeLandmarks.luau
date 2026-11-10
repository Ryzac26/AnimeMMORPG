--!strict
--[[
    BiomeLandmarks (ModuleScript) -> ServerScriptService.Services.BiomeLandmarks
    HITOS TEMÁTICOS: un monumento grande por franja (16 en total) que se ve de lejos y le da identidad a cada zona:
      SAIYAN    1 Campamento Red Ribbon · 2 Árbol gigante de Namek · 3 Arena del Cell Games · 4 Torre de caramelo (Buu)
      SHINOBI   1 Puente inacabado (Olas) · 2 Torres de la Lluvia · 3 Puerta de Suna · 4 Estatuas del Valle del Fin
      PIRATA    1 Faro de East Blue · 2 Puerta del Tiburón (Arlong Park) · 3 Torre de la Justicia (Enies Lobby) · 4 Plataforma de Marineford
      SHINIGAMI 1 Puerta de Rukongai · 2 Árbol blanco de Hueco Mundo · 3 Cúpula de Las Noches · 4 Pagoda del Seireitei
    Van pegados a un borde de la franja (alternando lado), nunca en el centro; son decoración SIN colisión y un cartel con su nombre
    (visible a ~220 studs). Se generan solos sobre las losas "ZonePvE" igual que BiomeDetails y se rehacen si el mapa se reconstruye.
    Para quitar o mover uno: tabla LANDMARKS (Name, U = posición a lo largo de la franja 0-1, Side = 1 o -1).
]]
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local MAP_NAME = "Map_WC3_Style"
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}
local EDGE_INSET = 46 -- distancia del centro del monumento al muro lateral

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local M = Enum.Material

type Lane = { Biome: string, Faction: string, Strip: number, Start: Vector3, Dir: Vector3, FanC: number, FanK: number, U0: number, U1: number, FloorY: number }

---------------------------------------------------------------------
-- Piezas (todas sin colisión). "at" = punto en el suelo; su -Z mira al centro de la franja.
---------------------------------------------------------------------
local function piece(f: Instance, name: string, size: Vector3, cf: CFrame, col: Color3, mat: Enum.Material, shape: Enum.PartType?, tr: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = col
	p.Material = mat
	p.Transparency = tr or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = f
	return p
end

local function blk(f: Instance, size: Vector3, cf: CFrame, col: Color3, mat: Enum.Material?, tr: number?): Part
	return piece(f, "Bloque", size, cf, col, mat or M.SmoothPlastic, nil, tr)
end
local function ball(f: Instance, d: number, cf: CFrame, col: Color3, mat: Enum.Material?, tr: number?): Part
	return piece(f, "Esfera", Vector3.one * d, cf, col, mat or M.SmoothPlastic, Enum.PartType.Ball, tr)
end
-- cilindro VERTICAL (el de Roblox tiene el eje en X: se gira)
local function vcyl(f: Instance, d: number, h: number, cf: CFrame, col: Color3, mat: Enum.Material?, tr: number?): Part
	return piece(f, "Cilindro", Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), col, mat or M.SmoothPlastic, Enum.PartType.Cylinder, tr)
end
-- disco ACOSTADO en el suelo (charcos, marcas)
local function disc(f: Instance, d: number, thick: number, cf: CFrame, col: Color3, mat: Enum.Material?, tr: number?): Part
	return piece(f, "Disco", Vector3.new(thick, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), col, mat or M.SmoothPlastic, Enum.PartType.Cylinder, tr)
end
-- disco en un plano vertical que mira hacia -Z (para lunas, anillos, hélices)
local function ring(f: Instance, d: number, thick: number, cf: CFrame, col: Color3, mat: Enum.Material?, tr: number?): Part
	return piece(f, "Anillo", Vector3.new(thick, d, d), cf * CFrame.Angles(0, math.pi / 2, 0), col, mat or M.SmoothPlastic, Enum.PartType.Cylinder, tr)
end
local function light(p: BasePart, col: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = col
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

---------------------------------------------------------------------
-- Los 16 monumentos
---------------------------------------------------------------------
local function at(a: CFrame, x: number, y: number, z: number, ry: number?): CFrame
	return a * CFrame.new(x, y, z) * CFrame.Angles(0, ry or 0, 0)
end

local BUILD: { [string]: (Instance, CFrame) -> number } = {}
-- cada función devuelve la altura (para colocar el cartel)

BUILD.Saiyan_1 = function(f, a) -- Campamento Red Ribbon
	local red, olive = C(200, 40, 40), C(92, 104, 70)
	for i, x in ipairs({ -16, 0, 16 }) do
		blk(f, Vector3.new(11, 0.5, 9), at(a, x - 3, 4.2, 6) * CFrame.Angles(0, 0, -0.9), olive, M.Fabric)
		blk(f, Vector3.new(11, 0.5, 9), at(a, x + 3, 4.2, 6) * CFrame.Angles(0, 0, 0.9), olive:Lerp(C(60, 70, 45), 0.3), M.Fabric)
		blk(f, Vector3.new(12, 0.4, 9), at(a, x, 0.2, 6), C(70, 64, 56), M.Slate)
		if i == 2 then
			blk(f, Vector3.new(3, 4, 0.3), at(a, x, 1.8, 1.4), red, M.Fabric)
		end
	end
	for _, s in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -1, 1 }) do
			blk(f, Vector3.new(1.2, 22, 1.2), at(a, 14 + s * 4, 11, -10 + z * 4) , C(80, 76, 70), M.Metal)
		end
	end
	blk(f, Vector3.new(11, 1, 11), at(a, 14, 22, -10), C(70, 66, 60), M.Metal)
	blk(f, Vector3.new(8, 5, 8), at(a, 14, 25, -10), olive, M.Metal)
	blk(f, Vector3.new(9, 1, 9), at(a, 14, 28, -10), red, M.Metal)
	vcyl(f, 0.6, 14, at(a, 14, 35, -10), C(200, 200, 200), M.Metal)
	local lamp = ball(f, 1.6, at(a, 14, 42.6, -10), C(255, 60, 60), M.Neon)
	light(lamp, C(255, 70, 70), 24, 1.4)
	vcyl(f, 0.6, 26, at(a, -22, 13, -6), C(200, 200, 200), M.Metal)
	blk(f, Vector3.new(11, 7, 0.4), at(a, -17, 22, -6), red, M.Fabric)
	blk(f, Vector3.new(11, 1.4, 0.45), at(a, -17, 22, -6), C(255, 255, 255), M.Fabric)
	ball(f, 7, at(a, -2, 7.5, -12), C(190, 195, 200), M.Metal, 0)
	vcyl(f, 1.2, 8, at(a, -2, 3, -12), C(120, 120, 125), M.Metal)
	return 44
end

BUILD.Saiyan_2 = function(f, a) -- Árbol gigante de Namek
	vcyl(f, 6, 36, at(a, 0, 18, 0), C(96, 120, 80), M.Wood)
	vcyl(f, 9, 6, at(a, 0, 3, 0), C(88, 110, 74), M.Wood)
	local leaf = C(60, 190, 150)
	for _, o in ipairs({ { 0, 42, 0, 26 }, { -13, 38, 4, 18 }, { 13, 39, -3, 19 }, { 3, 36, 12, 16 }, { -4, 37, -12, 17 } }) do
		ball(f, o[4], at(a, o[1], o[2], o[3]), leaf:Lerp(C(110, 230, 170), (o[2] - 36) / 12), M.Grass)
	end
	for _, o in ipairs({ { -22, 0 }, { 24, 6 }, { 6, 22 } }) do
		ball(f, 12, at(a, o[1], 0, o[2]), C(210, 235, 225), M.Marble)
		blk(f, Vector3.new(3, 4.5, 0.6), at(a, o[1], 2.2, o[2] - 5.6), C(40, 60, 70), M.Slate)
	end
	return 56
end

BUILD.Saiyan_3 = function(f, a) -- Arena del Cell Games
	local tile = C(215, 212, 205)
	blk(f, Vector3.new(50, 1.2, 50), at(a, 0, 0.6, 0), tile, M.Marble)
	blk(f, Vector3.new(50.6, 0.4, 50.6), at(a, 0, 1.3, 0), C(150, 146, 138), M.Slate, 0.5)
	for i, c in ipairs({ { -25, -25 }, { 25, -25 }, { -25, 25 }, { 25, 25 } }) do
		local h = ({ 16, 9, 12, 5 })[i]
		blk(f, Vector3.new(4, h, 4), at(a, c[1], h / 2, c[2]) * CFrame.Angles(0.1 * (i - 2), 0, 0.08 * (3 - i)), C(160, 150, 138), M.Concrete)
		blk(f, Vector3.new(5, 1, 5), at(a, c[1], h + 0.3, c[2]) * CFrame.Angles(0.3, 0.4, 0.2), C(180, 170, 158), M.Concrete)
	end
	for k = 1, 7 do
		blk(f, Vector3.new(1, 0.15, 14 + k), at(a, -18 + k * 5.5, 1.6, 0, k * 0.5), C(40, 36, 34), M.Slate)
	end
	local m = disc(f, 12, 0.2, at(a, 0, 1.4, 0), C(255, 176, 80), M.Neon, 0.35)
	m.Name = "Marca"
	return 20
end

BUILD.Saiyan_4 = function(f, a) -- Torre de caramelo (dimensión de Buu)
	local pink, yellow, white = C(255, 140, 195), C(255, 224, 110), C(255, 245, 250)
	for i = 0, 9 do
		vcyl(f, 22 - i * 1.8, 3, at(a, 0, 1.5 + i * 3, 0), if i % 2 == 0 then pink else yellow, M.Neon, 0.1)
	end
	local top = ball(f, 7, at(a, 0, 34, 0), white, M.Neon)
	light(top, pink, 40, 1.4)
	for i, o in ipairs({ { -22, 8 }, { 24, 12 }, { -12, 22 } }) do
		vcyl(f, 1.2, 14, at(a, o[1], 7, o[2]), white, M.SmoothPlastic)
		local d = ring(f, 9, 0.6, at(a, o[1], 15.5, o[2]), if i % 2 == 0 then yellow else pink, M.Neon)
		d.Name = "Chupete"
		ring(f, 5.4, 0.7, at(a, o[1], 15.5, o[2]), white, M.Neon)
	end
	return 42
end

BUILD.Shinobi_1 = function(f, a) -- Puente inacabado (País de las Olas)
	local wood = C(140, 104, 66)
	blk(f, Vector3.new(11, 1, 52), at(a, 0, 8, 0), wood, M.WoodPlanks)
	for _, z in ipairs({ -22, -11, 0, 11, 22 }) do
		for _, s in ipairs({ -1, 1 }) do
			blk(f, Vector3.new(1.3, 9, 1.3), at(a, s * 5, 4, z), C(96, 70, 44), M.Wood)
		end
		blk(f, Vector3.new(12, 0.8, 1), at(a, 0, 7.4, z), C(96, 70, 44), M.Wood)
	end
	for _, s in ipairs({ -1, 1 }) do
		blk(f, Vector3.new(0.5, 0.5, 52), at(a, s * 5, 11, 0), C(200, 190, 170), M.Fabric)
	end
	for i = 1, 5 do
		blk(f, Vector3.new(11, 0.4, 2.2), at(a, 0, 8.6 + i * 0.4, 28 + i * 3, 0.15 * i) * CFrame.Angles(-0.2 - i * 0.12, 0, 0), wood, M.WoodPlanks)
	end
	blk(f, Vector3.new(2.5, 4, 2.5), at(a, 11, 2, -10), C(110, 90, 70), M.Wood)
	blk(f, Vector3.new(3, 3, 3), at(a, 12, 1.5, -6), C(120, 100, 76), M.Wood)
	return 15
end

BUILD.Shinobi_2 = function(f, a) -- Torres de la Lluvia
	local steel = C(112, 126, 140)
	for i, o in ipairs({ { -12, 0, 40 }, { 12, 6, 32 }, { 0, -12, 26 } }) do
		vcyl(f, 6, o[3], at(a, o[1], o[3] / 2, o[2]), steel, M.Metal)
		for y = 6, o[3] - 4, 9 do
			vcyl(f, 7.4, 1.2, at(a, o[1], y, o[2]), C(70, 82, 96), M.Metal)
		end
		vcyl(f, 0.5, 12, at(a, o[1], o[3] + 6, o[2]), C(190, 200, 210), M.Metal)
		local l = ball(f, 1.5, at(a, o[1], o[3] + 12.5, o[2]), C(255, 70, 70), M.Neon)
		if i == 1 then
			light(l, C(255, 70, 70), 30, 1.2)
		end
	end
	blk(f, Vector3.new(24, 1.6, 1.6), at(a, 0, 22, 3), C(70, 82, 96), M.Metal)
	vcyl(f, 1.4, 14, at(a, 0, 26, 6) * CFrame.Angles(0, 0, math.pi / 2), steel, M.Metal)
	return 54
end

BUILD.Shinobi_3 = function(f, a) -- Puerta de Suna
	local sand, dark = C(205, 160, 105), C(160, 120, 78)
	for _, s in ipairs({ -1, 1 }) do
		blk(f, Vector3.new(8, 30, 8), at(a, s * 13, 15, 0), sand, M.Sandstone)
		blk(f, Vector3.new(10, 3, 10), at(a, s * 13, 31, 0), dark, M.Sandstone)
		blk(f, Vector3.new(8.4, 1, 8.4), at(a, s * 13, 2, 0), dark, M.Sandstone)
	end
	blk(f, Vector3.new(34, 6, 9), at(a, 0, 28, 0), sand, M.Sandstone)
	blk(f, Vector3.new(36, 2, 10), at(a, 0, 32, 0), dark, M.Sandstone)
	blk(f, Vector3.new(10, 9, 0.4), at(a, 0, 24, -4.7), C(196, 60, 52), M.Fabric)
	ball(f, 4, at(a, 0, 25, -5), C(255, 235, 200), M.Neon, 0.1)
	for i = 0, 3 do
		blk(f, Vector3.new(30 - i * 6, 3, 30 - i * 6), at(a, 0, 1.5 + i * 3, 30), sand:Lerp(dark, i * 0.15), M.Sandstone)
	end
	for _, s in ipairs({ -1, 1 }) do
		blk(f, Vector3.new(0.5, 11, 4), at(a, s * 8, 14, -4.6), C(200, 70, 50), M.Fabric)
	end
	return 36
end

BUILD.Shinobi_4 = function(f, a) -- Estatuas del Valle del Fin
	local stone = C(96, 92, 100)
	for _, s in ipairs({ -1, 1 }) do
		local b = at(a, s * 20, 0, 0, s * math.rad(60))
		blk(f, Vector3.new(16, 4, 14), at(b, 0, 2, 0), C(70, 66, 74), M.Slate)
		blk(f, Vector3.new(9, 18, 7), at(b, 0, 13, 0), stone, M.Slate)
		ball(f, 7.5, at(b, 0, 24.5, 0), stone, M.Slate)
		blk(f, Vector3.new(3, 12, 3.4), at(b, -s * 6, 18, -3) * CFrame.Angles(0, 0, s * 0.5), stone, M.Slate)
		blk(f, Vector3.new(3, 9, 3.4), at(b, s * 6, 12, -1), stone, M.Slate)
	end
	blk(f, Vector3.new(7, 38, 1.5), at(a, 0, 19, 12), C(235, 245, 255), M.Glass, 0.45)
	local pool = disc(f, 22, 0.5, at(a, 0, 0.5, -3), C(110, 170, 220), M.Glass, 0.3)
	pool.Name = "Poza"
	return 40
end

BUILD.Pirate_1 = function(f, a) -- Faro de East Blue
	local white, red = C(245, 244, 240), C(210, 60, 55)
	for i = 0, 3 do
		vcyl(f, 10 - i * 1.5, 7, at(a, 0, 3.5 + i * 7, 0), if i % 2 == 0 then white else red, M.Concrete)
	end
	vcyl(f, 8, 1.4, at(a, 0, 29, 0), C(60, 60, 66), M.Metal)
	local lamp = ball(f, 5.5, at(a, 0, 32, 0), C(255, 236, 150), M.Neon)
	light(lamp, C(255, 236, 160), 46, 2)
	blk(f, Vector3.new(8, 1, 8), at(a, 0, 35.5, 0), red, M.Metal)
	blk(f, Vector3.new(14, 0.8, 30), at(a, 0, 0.9, -22), C(150, 112, 72), M.WoodPlanks)
	for i = 0, 3 do
		vcyl(f, 2.6, 3.4, at(a, -9 + (i % 2) * 18, 1.7, -14 - math.floor(i / 2) * 10), C(125, 86, 52), M.Wood)
	end
	blk(f, Vector3.new(5, 2, 11), at(a, 12, 1, -26, 0.4), C(140, 96, 60), M.Wood)
	vcyl(f, 0.4, 10, at(a, 12, 7, -26), C(110, 80, 50), M.Wood)
	blk(f, Vector3.new(4.4, 3, 0.2), at(a, 14.2, 10, -26), C(30, 30, 34), M.Fabric)
	return 40
end

BUILD.Pirate_2 = function(f, a) -- Puerta del Tiburón (Arlong Park)
	local blue = C(60, 130, 190)
	for _, s in ipairs({ -1, 1 }) do
		blk(f, Vector3.new(9, 24, 9), at(a, s * 14, 12, 0), blue, M.Cobblestone)
		blk(f, Vector3.new(10, 1.4, 10), at(a, s * 14, 24.7, 0), C(40, 96, 150), M.Cobblestone)
	end
	blk(f, Vector3.new(38, 8, 9), at(a, 0, 26, 0), blue, M.Cobblestone)
	for i = -7, 7 do
		blk(f, Vector3.new(1.6, 4, 1.6), at(a, i * 2.4, 20, -3.6) * CFrame.Angles(0, 0, math.pi / 4 * 0), C(250, 250, 245), M.SmoothPlastic)
	end
	for i = -5, 5 do
		blk(f, Vector3.new(1.4, 3.2, 1.4), at(a, i * 3, 4, -3.6), C(250, 250, 245), M.SmoothPlastic)
	end
	blk(f, Vector3.new(6, 12, 1.2), at(a, 0, 36, 0), C(40, 96, 150), M.Cobblestone) -- aleta
	ball(f, 4, at(a, -6, 28, -4.8), C(255, 255, 255), M.SmoothPlastic)
	ball(f, 2, at(a, -6, 28, -6.4), C(20, 20, 24), M.SmoothPlastic)
	ball(f, 4, at(a, 6, 28, -4.8), C(255, 255, 255), M.SmoothPlastic)
	ball(f, 2, at(a, 6, 28, -6.4), C(20, 20, 24), M.SmoothPlastic)
	return 44
end

BUILD.Pirate_3 = function(f, a) -- Torre de la Justicia (Enies Lobby)
	local marble, gold = C(238, 238, 232), C(240, 200, 90)
	blk(f, Vector3.new(26, 14, 26), at(a, 0, 7, 0), marble, M.Marble)
	blk(f, Vector3.new(20, 14, 20), at(a, 0, 21, 0), marble, M.Marble)
	blk(f, Vector3.new(14, 14, 14), at(a, 0, 35, 0), marble, M.Marble)
	for i, y in ipairs({ 14.4, 28.4, 42.4 }) do
		blk(f, Vector3.new(28 - (i - 1) * 6, 1.2, 28 - (i - 1) * 6), at(a, 0, y, 0), gold, M.Metal)
	end
	local dome = ball(f, 14, at(a, 0, 42, 0), gold, M.Metal)
	light(dome, gold, 40, 1.2)
	vcyl(f, 0.6, 10, at(a, 0, 52, 0), gold, M.Metal)
	blk(f, Vector3.new(8, 12, 0.6), at(a, 0, 6, -13.2), C(60, 52, 40), M.Wood)
	for _, s in ipairs({ -1, 1 }) do
		for _, y in ipairs({ 8, 22, 36 }) do
			blk(f, Vector3.new(2.6, 5, 0.5), at(a, s * 6, y, -(13.2 - (y - 8) / 14 * 3)), C(70, 100, 150), M.Glass, 0.3)
		end
	end
	return 58
end

BUILD.Pirate_4 = function(f, a) -- Plataforma de Marineford
	local stone = C(196, 200, 206)
	blk(f, Vector3.new(40, 6, 26), at(a, 0, 3, 0), stone, M.Concrete)
	for i = 0, 3 do
		blk(f, Vector3.new(14, 1.5, 4), at(a, 0, 0.75 + i * 1.5, -14 - i * 2 + 6), stone:Lerp(C(150, 154, 160), i * 0.1), M.Concrete)
	end
	blk(f, Vector3.new(40, 4, 2), at(a, 0, 8, 12), C(90, 94, 100), M.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		local x = s * 24
		vcyl(f, 1.6, 20, at(a, x, 10, -4), C(70, 76, 86), M.Metal)
		blk(f, Vector3.new(12, 1.6, 1.6), at(a, x, 3.5, -4), C(70, 76, 86), M.Metal)
		ring(f, 6, 1, at(a, x, 21, -4), C(70, 76, 86), M.Metal)
		for _, t in ipairs({ -1, 1 }) do
			vcyl(f, 2.6, 5, at(a, s * 14 + t * 5, 7.4, -20) * CFrame.Angles(0, 0, 0), C(40, 40, 46), M.Metal)
		end
	end
	vcyl(f, 0.7, 30, at(a, 0, 21, 8), C(110, 90, 66), M.Wood)
	blk(f, Vector3.new(9, 6, 0.2), at(a, 4.5, 33, 8), C(250, 250, 250), M.Fabric)
	local fire = ball(f, 2, at(a, 0, 12, 12), C(255, 120, 50), M.Neon, 0.2)
	light(fire, C(255, 130, 60), 26, 1.2)
	return 38
end

BUILD.Shinigami_1 = function(f, a) -- Puerta de Rukongai
	local wood, roof = C(120, 84, 56), C(80, 74, 70)
	for i, o in ipairs({ { -22, 4 }, { 22, 6 }, { 0, 24 } }) do
		blk(f, Vector3.new(14, 7, 11), at(a, o[1], 3.5, o[2]), C(178, 156, 124), M.Wood)
		blk(f, Vector3.new(17, 0.8, 7.4), at(a, o[1], 8.4, o[2] - 3.2) * CFrame.Angles(0.55, 0, 0), roof, M.Slate)
		blk(f, Vector3.new(17, 0.8, 7.4), at(a, o[1], 8.4, o[2] + 3.2) * CFrame.Angles(-0.55, 0, 0), roof, M.Slate)
		local l = ball(f, 1.4, at(a, o[1] + 5, 5.4, o[2] - 6), C(255, 160, 70), M.Neon)
		if i == 1 then
			light(l, C(255, 160, 70), 22, 1)
		end
	end
	local red = C(190, 40, 44)
	for _, s in ipairs({ -1, 1 }) do
		vcyl(f, 2.4, 20, at(a, s * 7, 10, -12), red, M.Wood)
	end
	blk(f, Vector3.new(22, 2, 3), at(a, 0, 20.5, -12), red, M.Wood)
	blk(f, Vector3.new(26, 1.4, 4), at(a, 0, 23, -12), C(40, 36, 36), M.Wood)
	return 26
end

BUILD.Shinigami_2 = function(f, a) -- Árbol blanco de Hueco Mundo
	local bone = C(238, 234, 222)
	vcyl(f, 4.4, 24, at(a, 0, 12, 0), bone, M.Marble)
	vcyl(f, 7, 4, at(a, 0, 2, 0), bone, M.Marble)
	for i, o in ipairs({ { -7, 26, 0.9 }, { 7, 28, -0.8 }, { 0, 31, 0.1 }, { -3, 24, -1.3 }, { 4, 22, 1.2 } }) do
		blk(f, Vector3.new(1.4, 16, 1.4), at(a, o[1], o[2], 0) * CFrame.Angles(0, i, o[3]), bone, M.Marble)
	end
	for i, o in ipairs({ { -20, 8, 0.2 }, { 21, 14, -0.15 }, { -10, 30, 0.1 }, { 14, -20, 0.25 } }) do
		local c = blk(f, Vector3.new(3.4, 15 + i * 2, 3.4), at(a, o[1], (15 + i * 2) / 2, o[2]) * CFrame.Angles(o[3], i, o[3]), C(190, 196, 255), M.Glass, 0.35)
		if i == 1 then
			light(c, C(190, 196, 255), 26, 1)
		end
	end
	return 42
end

BUILD.Shinigami_3 = function(f, a) -- Cúpula de Las Noches
	local white = C(240, 242, 248)
	vcyl(f, 36, 10, at(a, 0, 5, 0), white, M.Concrete)
	ball(f, 34, at(a, 0, 10, 0), white, M.Concrete)
	for k = 0, 3 do
		local ang = k * math.pi / 2 + math.pi / 4
		local x, z = math.cos(ang) * 22, math.sin(ang) * 22
		vcyl(f, 5, 32 + (k % 2) * 6, at(a, x, 16 + (k % 2) * 3, z), white, M.Concrete)
		ball(f, 5, at(a, x, 33 + (k % 2) * 6, z), C(200, 208, 255), M.Neon, 0.2)
	end
	local moon = ring(f, 12, 0.6, at(a, 0, 30, -10), C(190, 200, 255), M.Neon)
	moon.Name = "Luna"
	local cut = ring(f, 12, 0.8, at(a, 3, 31, -10.4), C(30, 32, 52), M.SmoothPlastic)
	cut.Name = "LunaSombra"
	light(moon, C(190, 200, 255), 34, 1.4)
	return 46
end

BUILD.Shinigami_4 = function(f, a) -- Pagoda del Seireitei
	local wall, roof = C(246, 242, 234), C(70, 64, 66)
	local y = 0
	for i = 0, 3 do
		local w = 18 - i * 3.2
		blk(f, Vector3.new(w, 6, w), at(a, 0, y + 3, 0), wall, M.Concrete)
		blk(f, Vector3.new(w + 6, 1, w + 6), at(a, 0, y + 6.5, 0), roof, M.Slate)
		blk(f, Vector3.new(w + 6.6, 0.5, w + 6.6), at(a, 0, y + 7.2, 0), C(255, 176, 96), M.Metal)
		for _, s in ipairs({ -1, 1 }) do
			local l = ball(f, 1.2, at(a, s * (w / 2 + 2.6), y + 5, -(w / 2 + 2.6)), C(255, 170, 90), M.Neon)
			if i == 0 and s == 1 then
				light(l, C(255, 170, 90), 24, 1)
			end
		end
		y += 8
	end
	vcyl(f, 0.8, 9, at(a, 0, y + 4, 0), C(255, 176, 96), M.Metal)
	ball(f, 2, at(a, 0, y + 9, 0), C(255, 176, 96), M.Metal)
	return y + 12
end

local LANDMARKS: { [string]: { Name: string, U: number, Side: number, Accent: Color3 } } = {
	Saiyan_1 = { Name = "CAMPAMENTO CARMESÍ", U = 0.22, Side = 1, Accent = C(255, 120, 110) },
	Saiyan_2 = { Name = "ÁRBOL GIGANTE ESMERALDA", U = 0.22, Side = -1, Accent = C(126, 240, 184) },
	Saiyan_3 = { Name = "ARENA DEL BIOMONSTRUO", U = 0.22, Side = 1, Accent = C(255, 176, 80) },
	Saiyan_4 = { Name = "TORRE DE CARAMELO", U = 0.22, Side = -1, Accent = C(255, 190, 225) },
	Shinobi_1 = { Name = "PUENTE INACABADO", U = 0.22, Side = 1, Accent = C(210, 190, 150) },
	Shinobi_2 = { Name = "TORRES DE LA LLUVIA", U = 0.22, Side = -1, Accent = C(140, 216, 255) },
	Shinobi_3 = { Name = "PUERTA DEL DESIERTO", U = 0.22, Side = 1, Accent = C(255, 208, 112) },
	Shinobi_4 = { Name = "ESTATUAS DEL VALLE FINAL", U = 0.22, Side = -1, Accent = C(255, 120, 100) },
	Pirate_1 = { Name = "FARO DEL MAR AZUL", U = 0.22, Side = 1, Accent = C(255, 236, 160) },
	Pirate_2 = { Name = "PUERTA DEL TIBURÓN", U = 0.22, Side = -1, Accent = C(138, 232, 255) },
	Pirate_3 = { Name = "TORRE DE LA JUSTICIA", U = 0.22, Side = 1, Accent = C(255, 216, 112) },
	Pirate_4 = { Name = "PLATAFORMA DEL ALMIRANTAZGO", U = 0.22, Side = -1, Accent = C(255, 150, 90) },
	Shinigami_1 = { Name = "PUERTA DEL ARRABAL", U = 0.22, Side = 1, Accent = C(255, 160, 100) },
	Shinigami_2 = { Name = "ÁRBOL BLANCO DEL PÁRAMO VACÍO", U = 0.22, Side = -1, Accent = C(200, 206, 255) },
	Shinigami_3 = { Name = "CÚPULA DEL ECLIPSE", U = 0.22, Side = 1, Accent = C(190, 200, 255) },
	Shinigami_4 = { Name = "PAGODA DEL BASTIÓN BLANCO", U = 0.22, Side = -1, Accent = C(255, 176, 96) },
}

---------------------------------------------------------------------
-- Lectura de losas y construcción
---------------------------------------------------------------------
local folder: Folder? = nil
local token = 0

local function readLanes(map: Instance): { Lane }
	local found: { [string]: Lane } = {}
	for _, p in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if p:IsA("BasePart") and p:IsDescendantOf(map) then
			local biome, strip = p:GetAttribute("Biome"), p:GetAttribute("Strip")
			local ls, ld = p:GetAttribute("LaneStart"), p:GetAttribute("LaneDir")
			local fc, fk = p:GetAttribute("FanC"), p:GetAttribute("FanK")
			local u0, u1 = p:GetAttribute("UStart"), p:GetAttribute("UEnd")
			if typeof(biome) == "string" and typeof(strip) == "number" and BIOME_FACTION[biome] and typeof(ls) == "Vector3" and typeof(ld) == "Vector3"
				and typeof(fc) == "number" and typeof(fk) == "number" and typeof(u0) == "number" and typeof(u1) == "number" then
				local key = biome .. "_" .. strip
				if not found[key] then
					found[key] = { Biome = biome, Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld, FanC = fc, FanK = fk, U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2 }
				end
			end
		end
	end
	local out: { Lane } = {}
	for _, l in pairs(found) do
		table.insert(out, l)
	end
	table.sort(out, function(x, y)
		if x.Faction ~= y.Faction then
			return x.Faction < y.Faction
		end
		return x.Strip < y.Strip
	end)
	return out
end

local function buildLane(l: Lane, root: Folder)
	local key = l.Faction .. "_" .. l.Strip
	local def, fn = LANDMARKS[key], BUILD[key]
	if not def or not fn then
		return
	end
	local u = l.U0 + (l.U1 - l.U0) * def.U
	local half = l.FanC + l.FanK * u
	local v = def.Side * math.max(half - EDGE_INSET, half * 0.6)
	local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
	local p = l.Start + l.Dir * u + side * v
	local pos = Vector3.new(p.X, l.FloorY, p.Z)
	local toCenter = -side * def.Side
	local a = CFrame.lookAt(pos, pos + toCenter)

	local f = Instance.new("Folder")
	f.Name = "Hito_" .. key
	f.Parent = root
	local height = fn(f, a)

	-- cartel con el nombre
	local anchor = Instance.new("Part")
	anchor.Name = "Cartel"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = a * CFrame.new(0, height + 6, 0)
	anchor.Parent = f
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 34)
	bb.MaxDistance = 230
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextSize = 17
	t.TextColor3 = def.Accent
	t.TextStrokeTransparency = 0.3
	t.Text = def.Name
	t.Parent = bb
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("BasePart") then
			CollectionService:AddTag(d, "Landmark")
		end
	end
end

local function build()
	token += 1
	local mine = token
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		return
	end
	local lanes = readLanes(map)
	if #lanes == 0 then
		return
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	-- copias viejas guardadas en el lugar (si alguna vez se generó en Edit y se guardó): se borran para no duplicar
	for _, stale in ipairs(Workspace:GetChildren()) do
		if stale.Name == "HitosZona" then
			stale:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "HitosZona"
	root.Parent = Workspace
	folder = root
	for _, l in ipairs(lanes) do
		if token ~= mine then
			return
		end
		local ok, err = pcall(buildLane, l, root)
		if not ok then
			warn(string.format("[BiomeLandmarks] Error en %s franja %d: %s", l.Faction, l.Strip, tostring(err)))
		end
		task.wait()
	end
	print("[BiomeLandmarks] Hitos temáticos listos.")
end

task.spawn(function()
	local t = 0
	while (not Workspace:FindFirstChild(MAP_NAME) or Workspace:GetAttribute("MapBuilt") ~= true) and t < 90 do
		task.wait(1)
		t += 1
	end
	task.wait(5)
	build()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == MAP_NAME then
		local mine = token
		task.delay(13, function()
			if token == mine and Workspace:FindFirstChild(MAP_NAME) then
				build()
			end
		end)
	end
end)

local BiomeLandmarks = {}
BiomeLandmarks.Rebuild = build

return BiomeLandmarks
