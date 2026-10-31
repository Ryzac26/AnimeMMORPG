--!strict
--[[
    ArenaStyler (ModuleScript) -> ServerScriptService > Services > ArenaStyler
    Diseño de la ARENA CENTRAL (se aplica encima de lo que crea ProjectBootstrapper; no lo modifica).

    FIJO (siempre):
      - 4 campamentos de facción detrás de cada puente (cristal que cura 1,5% de vida y energía cada 0,5 s a los de esa facción).
      - 8 altares bajos bajo las piedras Metin (planos: no tocan la piedra ni su spawn).
      - Anillos y obeliscos alrededor de la plataforma del jefe (planos: no tocan el spawn del jefe).
      - 4 SANTUARIOS de poder en las diagonales: se capturan quedándose cerca 8 s (si hay dos facciones, queda disputado).
        Con el evento abierto, la facción dueña recibe EN LA ARENA:
          Santuario de Fuerza   +8% de daño          (atributo de jugador ShrineDmg,    lo lee DamageService)
          Santuario de Vigor    +10% de vida máxima  (se aplica aquí mismo al Humanoid)
          Santuario de Aliento  +40% regeneración de energía (ShrineEnergy, lo lee EnergyRegenService)
          Santuario de Fortuna  +15% de XP           (ShrineXp,     lo lee RewardService)
        Al cerrarse el evento o salir de la arena, los bonus se quitan solos.
      - Dibujo del suelo opcional (CityAssets: Arena_floor).

    TEMAS (rotan uno por cada jefe mundial que aparece; el primero depende de la hora, igual en todos los servidores):
      1 Coliseo de las Cuatro Naciones · 2 Ruinas del Torneo · 3 Isla Flotante (cascadas, roca y nubes bajo la arena)
    Prueba: /boss cambia al siguiente tema · /tema 1|2|3 lo fuerza.
    ENABLED = false lo apaga y deja la arena como estaba (los temas quitan lo que pusieron).
]]
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local ENABLED = true
local MAP_NAME = "Map_WC3_Style"

local Services = script.Parent
local Net = require(Services:WaitForChild("Net"))
local CityAssets = require(Services:WaitForChild("CityAssets"))
local NotifyRemote = Net.Get("Notify")

local FLOOR_TOP = 12
local ARENA_HALF = 750
local CAMP_DIST = 660 -- centro del campamento respecto al centro de la arena
local CAMP_RADIUS = 26
local SHRINE_RADIUS = 18
local CAPTURE_SECONDS = 8
local SHRINE_POS = 396 -- las 4 diagonales: (±396, ±396)
local THEME_SECONDS = 6 * 3600

local BUFF_DMG = 1.08
local BUFF_HP = 1.10
local BUFF_ENERGY = 1.40
local BUFF_XP = 1.15

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------
type LaneDef = { Faction: string, Out: Vector3, Kanji: string, Base: Color3, Glow: Color3, Cloth: Color3, Name: string }
local LANES: { LaneDef } = {
	{ Faction = "Saiyan", Out = Vector3.new(0, 0, -1), Kanji = "龍", Base = C(46, 59, 82), Glow = C(79, 209, 255), Cloth = C(255, 138, 31), Name = "SAIYAN" },
	{ Faction = "Shinobi", Out = Vector3.new(-1, 0, 0), Kanji = "忍", Base = C(122, 82, 50), Glow = C(232, 166, 64), Cloth = C(96, 160, 86), Name = "SHINOBI" },
	{ Faction = "Pirate", Out = Vector3.new(1, 0, 0), Kanji = "海", Base = C(91, 65, 48), Glow = C(255, 190, 90), Cloth = C(60, 120, 190), Name = "PIRATA" },
	{ Faction = "Shinigami", Out = Vector3.new(0, 0, 1), Kanji = "死", Base = C(200, 204, 214), Glow = C(126, 200, 255), Cloth = C(140, 110, 220), Name = "SHINIGAMI" },
}
local FACTION_COLOR: { [string]: Color3 } = {}
for _, l in ipairs(LANES) do
	FACTION_COLOR[l.Faction] = l.Cloth
end

type ShrineDef = { Id: string, Name: string, Color: Color3, Text: string, X: number, Z: number }
local SHRINES: { ShrineDef } = {
	{ Id = "Fuerza", Name = "Santuario de Fuerza", Color = C(255, 90, 60), Text = "+8% daño", X = -SHRINE_POS, Z = -SHRINE_POS },
	{ Id = "Vigor", Name = "Santuario de Vigor", Color = C(90, 230, 120), Text = "+10% vida máx.", X = SHRINE_POS, Z = -SHRINE_POS },
	{ Id = "Aliento", Name = "Santuario de Aliento", Color = C(90, 180, 255), Text = "+40% energía", X = -SHRINE_POS, Z = SHRINE_POS },
	{ Id = "Fortuna", Name = "Santuario de Fortuna", Color = C(255, 215, 90), Text = "+15% XP", X = SHRINE_POS, Z = SHRINE_POS },
}

local THEME_NAMES = { "Coliseo de las Cuatro Naciones", "Ruinas del Torneo", "Isla Flotante" }

---------------------------------------------------------------------
-- Helpers de partes
---------------------------------------------------------------------
local built = 0
local function breathe()
	built += 1
	if built % 60 == 0 then
		task.wait()
	end
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.Parent = parent
	breathe()
	return p
end

-- cilindro vertical: pos = centro
local function cylV(parent: Instance, name: string, pos: Vector3, h: number, d: number, color: Color3, mat: Enum.Material, solid: boolean?): Part
	local p = part(parent, name, Vector3.new(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, mat, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, pos: Vector3, d: number, color: Color3, mat: Enum.Material): Part
	local p = part(parent, name, Vector3.new(d, d, d), CFrame.new(pos), color, mat, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function folder(name: string, parent: Instance): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local function emitter(p: BasePart, color: Color3, rate: number, speed: number, life: number, size: number, accel: Vector3, spread: number, emission: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Size = NumberSequence.new(size)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = emission
	e.Acceleration = accel
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Parent = p
end

local function billboard(p: BasePart, text: string, color: Color3, offsetY: number, width: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 56)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 320
	gui.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0.3
	tl.Font = Enum.Font.GothamBold
	tl.TextSize = 17
	tl.TextWrapped = true
	tl.Parent = gui
	return tl
end

local function kanjiSign(p: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Font = Enum.Font.GothamBlack
	tl.Parent = sg
end

local function notifyAll(text: string)
	NotifyRemote:FireAllClients(text)
end

---------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------
type Camp = { Faction: string, Pos: Vector3 }
type Shrine = {
	Def: ShrineDef, Pos: Vector3, Owner: string?, Challenger: string?, Progress: number,
	Ring: Part, Crystal: Part, Label: TextLabel, Shown: string,
}
local camps: { Camp } = {}
local shrines: { Shrine } = {}
local arenaFolder: Instance? = nil
local styleRoot: Folder? = nil
local themeFolder: Folder? = nil
local themeCleanup: (() -> ())? = nil

---------------------------------------------------------------------
-- FIJO 1: campamentos
---------------------------------------------------------------------
local function buildCamp(parent: Instance, lane: LaneDef)
	local dir = -lane.Out
	local c = lane.Out * CAMP_DIST + Vector3.new(0, FLOOR_TOP, 0)
	local cf0 = CFrame.lookAt(c, c + dir)
	local function at(lx: number, ly: number, lz: number): CFrame
		return cf0 * CFrame.new(lx, ly, lz)
	end
	local f = Instance.new("Folder")
	f.Name = "Campamento_" .. lane.Faction
	f.Parent = parent

	local pad = part(f, "Base", Vector3.new(130, 0.6, 76), at(0, 0.3, 0), lane.Base, Enum.Material.Slate, true)
	pad.Name = "Base"
	cylV(f, "Emblema", cf0.Position + Vector3.new(0, 0.7, 0) + cf0.LookVector * 14, 0.2, 44, lane.Glow, Enum.Material.Neon).Transparency = 0.45

	-- cristal que cura
	local crystalPos = (cf0 * CFrame.new(0, 0, 0)).Position + Vector3.new(0, 0, 0)
	cylV(f, "Pedestal", crystalPos + Vector3.new(0, 2.2, 0), 3, 9, lane.Base:Lerp(C(255, 255, 255), 0.25), Enum.Material.Marble, true)
	local crystal = ball(f, "Cristal_Curacion", crystalPos + Vector3.new(0, 8.5, 0), 5.5, lane.Glow, Enum.Material.Neon)
	crystal.Transparency = 0.15
	light(crystal, lane.Glow, 34, 1.4)
	emitter(crystal, lane.Glow, 8, 5, 2.5, 0.5, Vector3.new(0, 2, 0), 180, 0.8)
	billboard(crystal, "CAMPAMENTO " .. lane.Name, lane.Cloth:Lerp(C(255, 255, 255), 0.35), 4.5, 240)
	table.insert(camps, { Faction = lane.Faction, Pos = crystalPos })

	-- banderas
	for _, sx in ipairs({ -1, 1 }) do
		local pole = part(f, "Asta", Vector3.new(1.2, 26, 1.2), at(sx * 52, 13.6, -6), C(60, 60, 68), Enum.Material.Metal, true)
		pole.Name = "Asta"
		local cloth = part(f, "Bandera", Vector3.new(0.4, 9, 13), at(sx * 52 + sx * 0.7, 21, -6), lane.Cloth, Enum.Material.Fabric, false)
		cloth.Name = "Bandera"
		kanjiSign(cloth, Enum.NormalId.Right, lane.Kanji, C(255, 255, 255))
		kanjiSign(cloth, Enum.NormalId.Left, lane.Kanji, C(255, 255, 255))
		ball(f, "Remate", at(sx * 52, 27.2, -6).Position, 2, lane.Glow, Enum.Material.Neon)
	end
	-- toldo al fondo (lado del puente)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(f, "Poste_Toldo", Vector3.new(1, 10, 1), at(sx * 30, 5.6, 22 + sz * 8), lane.Base:Lerp(C(0, 0, 0), 0.25), Enum.Material.Wood, true)
		end
		part(f, "Toldo", Vector3.new(26, 0.8, 22), at(sx * 30, 10.6, 22), lane.Cloth, Enum.Material.Fabric, false)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "Caja", Vector3.new(4, 4, 4), at(sx * 30, 2.6, 22), lane.Base:Lerp(C(120, 90, 60), 0.5), Enum.Material.WoodPlanks, true)
	end
end

---------------------------------------------------------------------
-- FIJO 2: altares Metin, jefe, suelo
---------------------------------------------------------------------
local function buildAltars(parent: Instance)
	local f = Instance.new("Folder")
	f.Name = "Altares_Metin"
	f.Parent = parent
	for _, m in ipairs(CollectionService:GetTagged("MetinStoneSpawn")) do
		if m:IsA("BasePart") then
			local p = Vector3.new(m.Position.X, FLOOR_TOP, m.Position.Z)
			cylV(f, "Altar_Base", p + Vector3.new(0, 0.3, 0), 0.6, 26, C(88, 92, 108), Enum.Material.Slate, false)
			cylV(f, "Altar_Anillo", p + Vector3.new(0, 0.72, 0), 0.16, 22, C(79, 209, 255), Enum.Material.Neon, false).Transparency = 0.3
			for k = 0, 3 do
				local a = k * math.pi / 2 + math.pi / 4
				local tp = p + Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12)
				cylV(f, "Antorcha_Poste", tp + Vector3.new(0, 3.6, 0), 7.2, 0.9, C(70, 66, 60), Enum.Material.Wood, true)
				local fl = ball(f, "Antorcha_Fuego", tp + Vector3.new(0, 7.8, 0), 2.2, C(255, 150, 50), Enum.Material.Neon)
				light(fl, C(255, 170, 80), 16, 0.9)
			end
		end
	end
end

local function buildBossDecor(parent: Instance)
	local f = Instance.new("Folder")
	f.Name = "Plataforma_Titan"
	f.Parent = parent
	cylV(f, "Anillo_Oro_1", Vector3.new(0, FLOOR_TOP + 0.2, 0), 0.16, 276, C(224, 176, 74), Enum.Material.Neon, false).Transparency = 0.45
	cylV(f, "Anillo_Oro_2", Vector3.new(0, FLOOR_TOP + 0.22, 0), 0.16, 246, C(255, 120, 80), Enum.Material.Neon, false).Transparency = 0.55
	for k = 0, 7 do
		local a = k * math.pi / 4 + math.pi / 8
		local p = Vector3.new(math.cos(a) * 138, FLOOR_TOP, math.sin(a) * 138)
		local ob = part(f, "Obelisco", Vector3.new(4, 12, 4), CFrame.new(p + Vector3.new(0, 6, 0)) * CFrame.Angles(0, a, 0), C(70, 72, 90), Enum.Material.Basalt, true)
		ob.Name = "Obelisco"
		part(f, "Obelisco_Runa", Vector3.new(0.5, 7, 1.4), CFrame.new(p + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.05), C(255, 120, 80), Enum.Material.Neon, false)
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = Vector3.new(math.cos(a) * 158, FLOOR_TOP, math.sin(a) * 158)
		part(f, "Brasero_Base", Vector3.new(5, 3, 5), CFrame.new(p + Vector3.new(0, 1.5, 0)), C(60, 58, 66), Enum.Material.Granite, true)
		local fl = ball(f, "Brasero_Fuego", p + Vector3.new(0, 4.2, 0), 3.4, C(255, 110, 60), Enum.Material.Neon)
		light(fl, C(255, 130, 70), 26, 1.1)
		emitter(fl, C(255, 150, 70), 10, 6, 1.6, 1, Vector3.new(0, 8, 0), 25, 0.9)
	end
end

local function buildFloorDecor(parent: Instance, arenaPart: BasePart?)
	local f = Instance.new("Folder")
	f.Name = "Suelo"
	f.Parent = parent
	-- diagonales doradas
	for _, s in ipairs({ 1, -1 }) do
		part(f, "Diagonal", Vector3.new(26, 0.12, 2000), CFrame.new(0, FLOOR_TOP + 0.14, 0) * CFrame.Angles(0, math.rad(45 * s), 0), C(224, 176, 74), Enum.Material.Neon, false).Transparency = 0.72
	end
	-- dibujo del suelo (opcional)
	local img = CityAssets.Get("Arena", "floor")
	if img and arenaPart then
		local old = arenaPart:FindFirstChild("Arena_Dibujo")
		if old then
			old:Destroy()
		end
		local d = Instance.new("Decal")
		d.Name = "Arena_Dibujo"
		d.Face = Enum.NormalId.Top
		d.Texture = img
		d.Parent = arenaPart
	end
end

---------------------------------------------------------------------
-- FIJO 3: santuarios
---------------------------------------------------------------------
local function buildShrine(parent: Instance, def: ShrineDef)
	local f = Instance.new("Folder")
	f.Name = "Santuario_" .. def.Id
	f.Parent = parent
	local base = Vector3.new(def.X, FLOOR_TOP, def.Z)
	cylV(f, "Plataforma", base + Vector3.new(0, 0.4, 0), 0.8, 40, C(70, 72, 90), Enum.Material.Basalt, true)
	local ring = cylV(f, "Anillo", base + Vector3.new(0, 0.9, 0), 0.16, 36, C(150, 150, 160), Enum.Material.Neon, false)
	ring.Transparency = 0.35
	cylV(f, "Anillo_Interior", base + Vector3.new(0, 0.95, 0), 0.12, 20, def.Color, Enum.Material.Neon, false).Transparency = 0.6
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = base + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15)
		cylV(f, "Pilar", p + Vector3.new(0, 5.4, 0), 9, 2.4, C(96, 98, 118), Enum.Material.Granite, true)
		ball(f, "Pilar_Luz", p + Vector3.new(0, 10.4, 0), 2, def.Color, Enum.Material.Neon)
	end
	cylV(f, "Pedestal", base + Vector3.new(0, 2.2, 0), 3, 6, C(110, 112, 130), Enum.Material.Marble, true)
	local crystal = ball(f, "Cristal", base + Vector3.new(0, 9, 0), 5.5, def.Color, Enum.Material.Neon)
	crystal.Transparency = 0.1
	light(crystal, def.Color, 40, 1.3)
	emitter(crystal, def.Color, 6, 4, 2.5, 0.5, Vector3.new(0, 2, 0), 180, 0.8)
	local label = billboard(crystal, def.Name .. "\n" .. def.Text .. " · Libre", C(255, 255, 255), 6, 260)
	table.insert(shrines, {
		Def = def, Pos = base, Owner = nil, Challenger = nil, Progress = 0,
		Ring = ring, Crystal = crystal, Label = label, Shown = "",
	})
end

---------------------------------------------------------------------
-- TEMAS
---------------------------------------------------------------------
local function standsGeometry(parent: Instance, rng: Random, broken: boolean)
	local sides: { { Out: Vector3, Along: Vector3, Lane: LaneDef } } = {}
	for _, l in ipairs(LANES) do
		table.insert(sides, { Out = l.Out, Along = Vector3.new(-l.Out.Z, 0, l.Out.X), Lane = l })
	end
	local ranges = { { -ARENA_HALF - 40, -84 }, { 84, ARENA_HALF + 40 } }
	for _, s in ipairs(sides) do
		for tier = 1, 3 do
			local dist0 = ARENA_HALF + 16 + (tier - 1) * 18
			local topY = FLOOR_TOP + tier * 8
			for _, r in ipairs(ranges) do
				local chunk = if broken then 70 else (r[2] - r[1])
				local n = math.max(1, math.floor((r[2] - r[1]) / chunk + 0.5))
				local seg = (r[2] - r[1]) / n
				for i = 0, n - 1 do
					local skip = broken and rng:NextNumber() < (if tier == 1 then 0.1 else 0.3)
					if not skip then
						local mid = r[1] + seg * (i + 0.5)
						local drop = if broken then rng:NextNumber(0, 5) else 0
						local h = topY - drop + 6
						local center = s.Out * (dist0 + 9) + s.Along * mid
						local color = if broken then C(150, 148, 138):Lerp(C(96, 120, 90), rng:NextNumber(0, 0.5)) else C(196, 192, 182)
						part(parent, "Grada", Vector3.new(seg, h, 18), CFrame.lookAt(Vector3.new(center.X, (topY - drop - 6) / 2, center.Z), Vector3.new(center.X, (topY - drop - 6) / 2, center.Z) + s.Out), color, if broken then Enum.Material.Cobblestone else Enum.Material.Marble, true)
						if tier == 3 and not broken then
							part(parent, "Grada_Franja", Vector3.new(seg, 0.8, 18.4), CFrame.lookAt(Vector3.new(center.X, topY + 0.4, center.Z), Vector3.new(center.X, topY + 0.4, center.Z) + s.Out), s.Lane.Cloth, Enum.Material.SmoothPlastic, false)
						end
					end
				end
				-- banderas sobre la grada alta
				if not broken then
					local x = r[1] + 60
					while x <= r[2] - 40 do
						local base = s.Out * (dist0 + 9 + 36) + s.Along * x
						local py = FLOOR_TOP + 24 + 11
						part(parent, "Asta", Vector3.new(1.2, 22, 1.2), CFrame.new(base.X, py - 2, base.Z), C(70, 70, 80), Enum.Material.Metal, false)
						part(parent, "Bandera", Vector3.new(10, 8, 0.4), CFrame.lookAt(Vector3.new(base.X, py + 4, base.Z) + s.Along * 5.6, Vector3.new(base.X, py + 4, base.Z) + s.Along * 5.6 + s.Out), s.Lane.Cloth, Enum.Material.Fabric, false)
						x += 140
					end
				end
			end
		end
	end
end

local function lanterns(parent: Instance, rng: Random, count: number, radius: number, y0: number, y1: number)
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(150, radius)
		local l = ball(parent, "Farolillo", Vector3.new(math.cos(a) * r, rng:NextNumber(y0, y1), math.sin(a) * r), rng:NextNumber(2.5, 4), C(255, 205, 110), Enum.Material.Neon)
		if rng:NextNumber() < 0.3 then
			light(l, C(255, 205, 110), 28, 0.9)
		end
	end
end

local function themeColiseo(parent: Folder)
	local rng = Random.new(1001)
	standsGeometry(parent, rng, false)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = Vector3.new(sx * 800, 0, sz * 800)
			part(parent, "Torre_Esquina", Vector3.new(38, 76, 38), CFrame.new(p.X, 32, p.Z), C(176, 172, 164), Enum.Material.Marble, true)
			part(parent, "Torre_Remate", Vector3.new(44, 4, 44), CFrame.new(p.X, 72, p.Z), C(224, 176, 74), Enum.Material.Metal, true)
			local fl = ball(parent, "Torre_Fuego", p + Vector3.new(0, 80, 0), 8, C(255, 130, 60), Enum.Material.Neon)
			light(fl, C(255, 150, 80), 60, 1.3)
		end
	end
	-- anillo de energía en el cielo
	local n = 40
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local p = Vector3.new(math.cos(a) * 980, 240, math.sin(a) * 980)
		part(parent, "Anillo_Cielo", Vector3.new(120, 4, 5), CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), C(255, 210, 90), Enum.Material.Neon, false).Transparency = 0.35
	end
	lanterns(parent, rng, 26, 700, 40, 80)
end

local function ruinPiece(parent: Instance, rng: Random, x: number, z: number)
	local kind = rng:NextInteger(1, 4)
	local stone = C(150, 148, 138):Lerp(C(100, 124, 94), rng:NextNumber(0, 0.5))
	local yaw = rng:NextNumber(0, math.pi * 2)
	if kind == 1 then
		local h = rng:NextNumber(10, 24)
		cylV(parent, "Pilar", Vector3.new(x, FLOOR_TOP + h / 2, z), h, rng:NextNumber(3.6, 5), stone, Enum.Material.Cobblestone, true)
		if rng:NextNumber() < 0.6 then
			ball(parent, "Enredadera", Vector3.new(x, FLOOR_TOP + 1.5, z), rng:NextNumber(5, 8), C(70, 130, 70), Enum.Material.Grass)
		end
	elseif kind == 2 then
		local len = rng:NextNumber(16, 28)
		local p = cylV(parent, "Pilar_Caido", Vector3.new(x, FLOOR_TOP + 2, z), len, 4, stone, Enum.Material.Cobblestone, true)
		p.CFrame = CFrame.new(x, FLOOR_TOP + 2, z) * CFrame.Angles(0, yaw, 0)
	elseif kind == 3 then
		local mono = part(parent, "Monolito", Vector3.new(6, rng:NextNumber(14, 22), 3), CFrame.new(x, FLOOR_TOP + 9, z) * CFrame.Angles(0, yaw, 0), C(60, 64, 82), Enum.Material.Basalt, true)
		part(parent, "Monolito_Runa", Vector3.new(0.5, 8, 1.4), mono.CFrame * CFrame.new(0, 1, -1.6), C(79, 209, 255), Enum.Material.Neon, false)
	else
		local cfA = CFrame.new(x, FLOOR_TOP, z) * CFrame.Angles(0, yaw, 0)
		for _, sx in ipairs({ -1, 1 }) do
			cylV(parent, "Arco_Pilar", (cfA * CFrame.new(sx * 8, 9, 0)).Position, 18, 3.6, stone, Enum.Material.Cobblestone, true)
		end
		part(parent, "Arco_Dintel", Vector3.new(11, 3, 4), cfA * CFrame.new(-4.5, 19, 0), stone, Enum.Material.Cobblestone, true)
		ball(parent, "Enredadera", (cfA * CFrame.new(8, 2, 0)).Position, 6, C(70, 130, 70), Enum.Material.Grass)
	end
end

local function themeRuinas(parent: Folder)
	local rng = Random.new(2002)
	standsGeometry(parent, rng, true)
	local metin: { Vector3 } = {}
	for _, m in ipairs(CollectionService:GetTagged("MetinStoneSpawn")) do
		if m:IsA("BasePart") then
			table.insert(metin, m.Position)
		end
	end
	local placed = 0
	local tries = 0
	while placed < 40 and tries < 600 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(200, 650)
		local x, z = math.cos(a) * r, math.sin(a) * r
		local ok = math.abs(x) > 60 and math.abs(z) > 60
		for _, mp in ipairs(metin) do
			if (Vector3.new(x, 0, z) - Vector3.new(mp.X, 0, mp.Z)).Magnitude < 48 then
				ok = false
			end
		end
		for _, s in ipairs(SHRINES) do
			if (Vector3.new(x, 0, z) - Vector3.new(s.X, 0, s.Z)).Magnitude < 56 then
				ok = false
			end
		end
		for _, l in ipairs(LANES) do
			if (Vector3.new(x, 0, z) - l.Out * CAMP_DIST).Magnitude < 90 then
				ok = false
			end
		end
		if ok then
			placed += 1
			ruinPiece(parent, rng, x, z)
		end
	end
	-- niebla baja
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		local anchor = part(parent, "Niebla", Vector3.new(2, 2, 2), CFrame.new(math.cos(a) * 420, FLOOR_TOP + 3, math.sin(a) * 420), C(255, 255, 255), Enum.Material.SmoothPlastic, false)
		anchor.Transparency = 1
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(C(200, 210, 220))
		e.Rate = 3
		e.Lifetime = NumberRange.new(7, 10)
		e.Speed = NumberRange.new(1, 3)
		e.Size = NumberSequence.new(26)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) })
		e.SpreadAngle = Vector2.new(180, 20)
		e.Parent = anchor
	end
	lanterns(parent, rng, 14, 600, 25, 55)
end

local function themeIsla(parent: Folder)
	local rng = Random.new(3003)
	local map = Workspace:FindFirstChild(MAP_NAME)
	local removed: { BasePart } = {}
	local oceanFolder = if map then map:FindFirstChild("Oceano") else nil
	if oceanFolder then
		for _, t in ipairs(oceanFolder:GetChildren()) do
			if t:IsA("BasePart") and math.abs(t.Position.X) <= t.Size.X / 2 and math.abs(t.Position.Z) <= t.Size.Z / 2 then
				t.Parent = nil
				table.insert(removed, t)
			end
		end
	end
	themeCleanup = function()
		if oceanFolder then
			for _, t in ipairs(removed) do
				t.Parent = oceanFolder
			end
		end
	end

	-- roca bajo la arena
	local layers = {
		{ 1420, 8, 44 }, { 1250, -36, 56 }, { 1000, -92, 70 }, { 720, -162, 80 }, { 440, -242, 90 }, { 200, -332, 90 },
	}
	for i, l in ipairs(layers) do
		local w, y0, h = l[1], l[2], l[3]
		local col = C(96, 90, 104):Lerp(C(38, 34, 46), (i - 1) / #layers)
		part(parent, "Roca_" .. i, Vector3.new(w, h, w), CFrame.new(0, y0 - h / 2, 0), col, Enum.Material.Slate, false)
		for _ = 1, 6 do
			local side = rng:NextInteger(1, 4)
			local off = rng:NextNumber(-w / 2, w / 2)
			local px = if side == 1 then w / 2 elseif side == 2 then -w / 2 else off
			local pz = if side == 3 then w / 2 elseif side == 4 then -w / 2 else off
			local s = rng:NextNumber(50, 130)
			part(parent, "Roca_Bulto", Vector3.new(s, s * 0.8, s), CFrame.new(px, y0 - h / 2, pz) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 3), rng:NextNumber(0, 1)), col:Lerp(C(130, 120, 140), rng:NextNumber(0, 0.3)), Enum.Material.Slate, false)
		end
	end
	-- borde de hierba bajo el piso
	part(parent, "Borde_Hierba", Vector3.new(1500, 3, 1500), CFrame.new(0, 7.2, 0), C(88, 150, 90), Enum.Material.Grass, false)

	-- nubes
	for _ = 1, 46 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(300, 1500)
		local cx, cy, cz = math.cos(a) * r, rng:NextNumber(-210, -110), math.sin(a) * r
		for _ = 1, 3 do
			local b = ball(parent, "Nube", Vector3.new(cx + rng:NextNumber(-50, 50), cy + rng:NextNumber(-8, 8), cz + rng:NextNumber(-50, 50)), rng:NextNumber(70, 170), C(244, 236, 250), Enum.Material.SmoothPlastic)
			b.Transparency = 0.12
		end
	end

	-- cascadas en los bordes (2 por lado, entre el puente y la esquina)
	local sheets: { Part } = {}
	for _, l in ipairs(LANES) do
		local o = l.Out
		local along = Vector3.new(-o.Z, 0, o.X)
		for _, t in ipairs({ -400, 400 }) do
			local top = o * 782 + along * t
			part(parent, "Canal", Vector3.new(34, 5, 36), CFrame.lookAt(Vector3.new(top.X, 9.5, top.Z), Vector3.new(top.X, 9.5, top.Z) + o), C(120, 118, 130), Enum.Material.Slate, true)
			part(parent, "Canal_Labio", Vector3.new(38, 3, 4), CFrame.lookAt(Vector3.new(top.X, 11.5, top.Z) + o * 15, Vector3.new(top.X, 11.5, top.Z) + o * 15 + o), C(150, 146, 160), Enum.Material.Slate, true)
			local fall = o * 800 + along * t
			local sheet = part(parent, "Cascada", Vector3.new(26, 160, 3), CFrame.lookAt(Vector3.new(fall.X, -72, fall.Z), Vector3.new(fall.X, -72, fall.Z) + o), C(150, 215, 255), Enum.Material.Neon, false)
			sheet.Transparency = 0.5
			table.insert(sheets, sheet)
			local spray = part(parent, "Cascada_Espuma", Vector3.new(24, 1, 1), CFrame.new(fall.X, 8, fall.Z) + o * 2, C(255, 255, 255), Enum.Material.SmoothPlastic, false)
			spray.Transparency = 1
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(C(235, 250, 255))
			e.Rate = 70
			e.Lifetime = NumberRange.new(3, 3.6)
			e.Speed = NumberRange.new(30, 42)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 1.5) })
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			e.LightEmission = 0.6
			e.Acceleration = Vector3.new(0, -40, 0)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.SpreadAngle = Vector2.new(5, 5)
			e.Parent = spray
			local mist = part(parent, "Cascada_Niebla", Vector3.new(30, 2, 30), CFrame.new(fall.X, -150, fall.Z) + o * 6, C(255, 255, 255), Enum.Material.SmoothPlastic, false)
			mist.Transparency = 1
			local m = Instance.new("ParticleEmitter")
			m.Texture = "rbxasset://textures/particles/smoke_main.dds"
			m.Color = ColorSequence.new(C(245, 235, 255))
			m.Rate = 6
			m.Lifetime = NumberRange.new(5, 7)
			m.Speed = NumberRange.new(2, 6)
			m.Size = NumberSequence.new(34)
			m.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 1) })
			m.SpreadAngle = Vector2.new(180, 40)
			m.Parent = mist
		end
	end
	for _, s in ipairs(sheets) do
		TweenService:Create(s, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.68 }):Play()
	end

	-- rocas flotantes pequeñas y farolillos
	for _ = 1, 8 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(950, 1350)
		local p = Vector3.new(math.cos(a) * r, rng:NextNumber(40, 120), math.sin(a) * r)
		local d = rng:NextNumber(24, 50)
		local rock = ball(parent, "Roca_Flotante", p, d, C(90, 86, 100), Enum.Material.Slate)
		ball(parent, "Roca_Hierba", p + Vector3.new(0, d * 0.32, 0), d * 0.7, C(88, 150, 90), Enum.Material.Grass)
		rock.Name = "Roca_Flotante"
	end
	lanterns(parent, rng, 30, 700, 30, 90)
end

local themeBuilders: { (Folder) -> () } = { themeColiseo, themeRuinas, themeIsla }

---------------------------------------------------------------------
-- Aplicar tema (uno a la vez)
---------------------------------------------------------------------
local currentTheme = 0
local applying = false
local pendingTheme: number? = nil

local function applyTheme(idx: number, announce: boolean)
	if applying then
		pendingTheme = idx
		return
	end
	applying = true
	local root = styleRoot
	if root then
		if themeCleanup then
			themeCleanup()
			themeCleanup = nil
		end
		local tf = folder("Tema", root)
		themeFolder = tf
		local ok, err = pcall(themeBuilders[idx], tf)
		if not ok then
			warn("[ArenaStyler] Error en el tema " .. idx .. ": " .. tostring(err))
		end
		currentTheme = idx
		Workspace:SetAttribute("ArenaTheme", THEME_NAMES[idx])
		if announce then
			notifyAll("La Arena cambió: " .. THEME_NAMES[idx])
		end
		print("[ArenaStyler] Tema " .. idx .. ": " .. THEME_NAMES[idx])
	end
	applying = false
	local nxt = pendingTheme
	pendingTheme = nil
	if nxt and nxt ~= currentTheme then
		applyTheme(nxt, announce)
	end
end

---------------------------------------------------------------------
-- Santuarios, bonus y campamentos (bucle cada 0,5 s)
---------------------------------------------------------------------
local ArenaServiceMod: any = nil
local EnergyMod: any = nil
local function arenaService(): any
	if ArenaServiceMod == nil then
		local ok, m = pcall(require, Services:WaitForChild("ArenaService"))
		ArenaServiceMod = if ok then m else false
	end
	return ArenaServiceMod
end
local function energyService(): any
	if EnergyMod == nil then
		local ok, m = pcall(require, Services:WaitForChild("EnergyRegenService"))
		EnergyMod = if ok then m else false
	end
	return EnergyMod
end

local function rootOf(pl: Player): (BasePart?, Humanoid?)
	local ch = pl.Character
	if not ch then
		return nil, nil
	end
	local r = ch:FindFirstChild("HumanoidRootPart")
	local h = ch:FindFirstChildOfClass("Humanoid")
	if r and r:IsA("BasePart") and h and h.Health > 0 then
		return r, h
	end
	return nil, nil
end

local function setHpBuff(pl: Player, hum: Humanoid, mult: number)
	local ch = pl.Character
	if not ch then
		return
	end
	local base = ch:GetAttribute("ShrineHpBase") :: number?
	local applied = ch:GetAttribute("ShrineHpApplied") :: number?
	if mult > 1 then
		if base == nil or applied == nil or hum.MaxHealth ~= applied then
			base = hum.MaxHealth -- StatService pudo cambiarla (nivel): partimos de la actual
		end
		local newMax = math.floor((base :: number) * mult)
		if hum.MaxHealth ~= newMax then
			local ratio = hum.Health / math.max(1, hum.MaxHealth)
			hum.MaxHealth = newMax
			hum.Health = newMax * ratio
		end
		ch:SetAttribute("ShrineHpBase", base)
		ch:SetAttribute("ShrineHpApplied", newMax)
	elseif base ~= nil and applied ~= nil then
		if hum.MaxHealth == applied then
			hum.MaxHealth = base
			hum.Health = math.min(hum.Health, base)
		end
		ch:SetAttribute("ShrineHpBase", nil)
		ch:SetAttribute("ShrineHpApplied", nil)
	end
end

local function clearBuffs(pl: Player)
	pl:SetAttribute("ShrineDmg", nil)
	pl:SetAttribute("ShrineEnergy", nil)
	pl:SetAttribute("ShrineXp", nil)
	local _, hum = rootOf(pl)
	if hum then
		setHpBuff(pl, hum, 1)
	end
end

local function updateShrineVisual(s: Shrine)
	local state = (s.Owner or "-") .. "|" .. (s.Challenger or "-") .. "|" .. tostring(math.floor(s.Progress * 10))
	if state == s.Shown then
		return
	end
	s.Shown = state
	local col = if s.Owner then FACTION_COLOR[s.Owner] or C(255, 255, 255) else C(150, 150, 160)
	s.Ring.Color = if s.Challenger then FACTION_COLOR[s.Challenger] or col else col
	local txt = s.Def.Name .. "\n" .. s.Def.Text .. " · "
	if s.Challenger and s.Progress > 0 then
		txt ..= "Capturando " .. s.Challenger .. " " .. math.floor(s.Progress * 100) .. "%"
	elseif s.Owner then
		txt ..= s.Owner
	else
		txt ..= "Libre"
	end
	s.Label.Text = txt
end

local function tick(dt: number)
	local open = Workspace:GetAttribute("EventState") == "Open"
	local list = Players:GetPlayers()

	-- campamentos: curan a su facción
	for _, camp in ipairs(camps) do
		for _, pl in ipairs(list) do
			if pl:GetAttribute("Faction") == camp.Faction then
				local root, hum = rootOf(pl)
				if root and hum and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(camp.Pos.X, 0, camp.Pos.Z)).Magnitude <= CAMP_RADIUS and math.abs(root.Position.Y - camp.Pos.Y) < 20 then
					if hum.Health < hum.MaxHealth then
						hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.03 * dt)
					end
					local en = energyService()
					if en and en.GetEnergy then
						local cur, mx = en.GetEnergy(pl)
						if mx > 0 and cur < mx then
							en.Gain(pl, mx * 0.03 * dt)
						end
					end
				end
			end
		end
	end

	-- santuarios
	local owned: { [string]: { [string]: boolean } } = {}
	for _, s in ipairs(shrines) do
		if not open then
			if s.Owner or s.Challenger or s.Progress > 0 then
				s.Owner, s.Challenger, s.Progress = nil, nil, 0
			end
		else
			local present: { [string]: number } = {}
			for _, pl in ipairs(list) do
				local f = pl:GetAttribute("Faction")
				local root = rootOf(pl)
				if typeof(f) == "string" and root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(s.Pos.X, 0, s.Pos.Z)).Magnitude <= SHRINE_RADIUS then
					present[f] = (present[f] or 0) + 1
				end
			end
			local count, only = 0, nil :: string?
			for f, _ in pairs(present) do
				count += 1
				only = f
			end
			if count == 1 and only then
				if only == s.Owner then
					s.Progress = math.max(0, s.Progress - dt / CAPTURE_SECONDS * 2)
					s.Challenger = nil
				else
					if s.Challenger ~= only then
						s.Challenger = only
						s.Progress = 0
					end
					s.Progress += dt / CAPTURE_SECONDS
					if s.Progress >= 1 then
						s.Owner, s.Challenger, s.Progress = only, nil, 0
						notifyAll("¡" .. only .. " capturó el " .. s.Def.Name .. "! (" .. s.Def.Text .. ")")
					end
				end
			elseif count == 0 then
				s.Progress = math.max(0, s.Progress - dt / CAPTURE_SECONDS * 0.5)
				if s.Progress == 0 then
					s.Challenger = nil
				end
			end
			-- count > 1: disputado, no avanza
		end
		if s.Owner then
			owned[s.Owner] = owned[s.Owner] or {}
			owned[s.Owner][s.Def.Id] = true
		end
		updateShrineVisual(s)
	end

	-- bonus para quienes estén en la arena
	local arena = arenaService()
	for _, pl in ipairs(list) do
		local f = pl:GetAttribute("Faction")
		local root, hum = rootOf(pl)
		local mine = if typeof(f) == "string" then owned[f] else nil
		if open and mine and root and hum and arena and arena.IsInArena and arena.IsInArena(root.Position) then
			pl:SetAttribute("ShrineDmg", if mine.Fuerza then BUFF_DMG else nil)
			pl:SetAttribute("ShrineEnergy", if mine.Aliento then BUFF_ENERGY else nil)
			pl:SetAttribute("ShrineXp", if mine.Fortuna then BUFF_XP else nil)
			setHpBuff(pl, hum, if mine.Vigor then BUFF_HP else 1)
		elseif pl:GetAttribute("ShrineDmg") ~= nil or pl:GetAttribute("ShrineEnergy") ~= nil or pl:GetAttribute("ShrineXp") ~= nil
			or (pl.Character and pl.Character:GetAttribute("ShrineHpBase") ~= nil) then
			clearBuffs(pl)
		end
	end
end

---------------------------------------------------------------------
-- Arranque
---------------------------------------------------------------------
local ArenaStyler = {}

function ArenaStyler.SetTheme(idx: number)
	if idx >= 1 and idx <= #themeBuilders then
		task.spawn(applyTheme, idx, true)
	end
end

local function run()
	local map = Workspace:WaitForChild(MAP_NAME, 60)
	local arena = map and map:WaitForChild("Arena_Central", 30)
	if not map or not arena then
		warn("[ArenaStyler] No existe la Arena Central")
		return
	end
	arenaFolder = arena
	for _ = 1, 20 do
		if #CollectionService:GetTagged("MetinStoneSpawn") >= 8 then
			break
		end
		task.wait(0.5)
	end
	local root = folder("Estilo", arena)
	styleRoot = root
	camps, shrines = {}, {}
	local coliseo = arena:FindFirstChild("Coliseo_Central")
	local ok, err = pcall(function()
		buildFloorDecor(root, if coliseo and coliseo:IsA("BasePart") then coliseo else nil)
		buildBossDecor(root)
		buildAltars(root)
		for _, l in ipairs(LANES) do
			buildCamp(root, l)
		end
		for _, def in ipairs(SHRINES) do
			buildShrine(root, def)
		end
	end)
	if not ok then
		warn("[ArenaStyler] Error en lo fijo: " .. tostring(err))
	end

	currentTheme = 0
	local idx = (math.floor(os.time() / THEME_SECONDS) % #themeBuilders) + 1
	applyTheme(idx, false)

	Workspace:GetAttributeChangedSignal("BossActive"):Connect(function()
		if Workspace:GetAttribute("BossActive") == true then
			local nxt = currentTheme % #themeBuilders + 1
			task.spawn(applyTheme, nxt, true)
		end
	end)
	Workspace:GetAttributeChangedSignal("ArenaThemeForce"):Connect(function()
		local v = Workspace:GetAttribute("ArenaThemeForce")
		if typeof(v) == "number" then
			Workspace:SetAttribute("ArenaThemeForce", nil)
			ArenaStyler.SetTheme(math.floor(v))
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		local step = acc
		acc = 0
		local good, e = pcall(tick, step)
		if not good then
			warn("[ArenaStyler] tick: " .. tostring(e))
		end
	end)
	Players.PlayerRemoving:Connect(function(pl)
		pl:SetAttribute("ShrineDmg", nil)
	end)
	print("[ArenaStyler] Arena lista: 4 campamentos, 8 altares, 4 santuarios y tema rotativo.")
end

if ENABLED then
	task.spawn(run)
end

return ArenaStyler
