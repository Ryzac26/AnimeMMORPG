--!strict
--[[
    =================================================================================
    SCRIPT: ProjectBootstrapper.luau  (Mapa v4 - Abanico Radial + Ciudad Fortificada)
    UBICACIÓN: ServerScriptService.Services.ProjectBootstrapper (Script de Servidor)
    REEMPLAZA a la versión anterior de este script y a MapBuilder.luau (los dos construyen
    "Map_WC3_Style"; deja UN solo script activo). La API pública es la misma de siempre:
    SetBridges, GetNpcSlotCFrame, PlaceNPC, y además SetEventOpen / EjectPlayersFromEventArea.

    GEOMETRÍA (studs; piso plano con tope a Y = 12)

        La ARENA NEUTRAL (1500x1500) está en el centro global. De ella salen 3 puentes de
        100x400 (uno por facción) hasta el portón de cada Ciudad Fortificada, y desde la ciudad
        el biome se abre HACIA AFUERA en un abanico de 60 grados totales (30 por lado) hasta
        los límites del mapa. Disposición: Saiyan al norte (-Z), Shinobi al oeste, Pirate al
        este y Shinigami al sur (+Z).
        "u" = distancia desde el portón de la ciudad (que mira a la arena) hacia el fondo del mapa.

        ARENA ==PUENTE 100x400==> u=0 ..... 800 ....... 1425 ....... 2050 ....... 2675 ....... 3300
                                  [ CIUDAD  ][ FRANJA 1 ][ FRANJA 2 ][ FRANJA 3 ][ FRANJA 4    ] fondo
                                   800x800    Nvl 1-25    Nvl 26-50   Nvl 51-75   Nvl 76-100
                                   ZoneSafe   ~850 ancho  ~1570       ~2290       ~3015 (ÉLITE)

        - CIUDAD FORTIFICADA 800x800: murallas de 40 studs con 4 torres de esquina y DOS salidas:
          el portón del puente (lado de la arena, compuerta dinámica de evento) y la salida
          trasera hacia la Franja 1 (200 de ancho, cerrada por el FactionBarrier, que bloquea
          solo a otras facciones). Plaza Central social de 200x200 y, alrededor, el Barrio
          Comercial con 6 parcelas.
        - 6 ESTRUCTURAS greybox (cada una con techo, paredes y mostrador, y un Part invisible
          "NPCSpawnPoint" detrás del mostrador para el NPC):
              Slot 1  Dojo del Instructor          70x50  abierto al frente
              Slot 2  Forja del Herrero            50x50  yunque + chimenea
              Slot 3  Laboratorio del Alquimista   40x40  torre cerrada
              Slot 4  Bazar del Mercader           40x40  puesto abierto con mostrador
              Slot 5  Ayuntamiento de Clanes       60x50  edificio principal
              Slot 6  Pabellón VIP                 40x40  plataforma elevada con escalones
        - FRANJAS de 625 de profundidad. El ancho crece en línea recta: cada lado del abanico es
          una diagonal con 30 grados de apertura (ver FAN_NEAR_WIDTH / FAN_HALF_ANGLE_DEG).
          El piso del abanico se arma con losas de ~30 studs de profundidad.
        - MUROS INVISIBLES de colisión (40 studs de alto) a lo largo de las dos diagonales del
          abanico de 60 grados y de TODO el borde posterior de la franja 4 (~3400 studs, en dos
          mitades), más las murallas visibles de la ciudad: no hay forma de caerse al vacío
          en todo el perímetro exterior.
        - PUENTES DE EVENTO 100x400 desde el portón de cada ciudad hasta la Arena Central.
          Barreras dinámicas (grupo "Event_Bridges": portón de la ciudad, compuertas de la
          arena y puentes) cerradas hasta que el temporizador llega a cero.
        - ARENA CENTRAL 1500x1500 (tag "ZoneBoss"), idéntica a la versión anterior:
          marcador "WorldBossSpawn" al centro y 8 "MetinStoneSpawn" en anillo.

    LO QUE NO CAMBIA (toda la lógica anterior sigue igual)
        Tags: ZoneSafe, ZonePvE, ZonePvP (SOLO Arena Central), ZoneBoss, FactionBarrier, NPCSlot,
              DummySpawnPoint, WorldBossSpawn, MetinStoneSpawn, MapNPC.
        Atributos de franja: Biome, Strip, MinLevel, MaxLevel, UStart, UEnd (+ Elite/PvP en la 4).
        Temporizador en Workspace: EventState ("Closed"|"Open") y EventCountdown (segundos).
        FactionBarrier por grupos de colisión (atributo de jugador Faction), spawn por facción,
        teletransporte al elegir facción y expulsión de la arena al cerrarse el evento.
        NPCs: cada NPCSpawnPoint tiene atributos Slot / Role / Biome. Para colocar un NPC:
            MapBuilder.PlaceNPC(modelo, "Imperio_Saiyan", 1)
        o ponle al modelo el tag "MapNPC" + atributos Biome (string) y Slot (número).

    NOTAS
        - Una parte de Roblox no puede medir más de 2048 studs: las losas anchas se parten solas.
        - Con un mapa de ~9700 studs de lado conviene activar StreamingEnabled en Workspace.
        - HUDManager: para mostrar "Frontera PvP", agrega { Tag = "ZonePvP", ... } ANTES de
          ZonePvE en la lista ZONES del HUD.
    =================================================================================
]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local PhysicsService = game:GetService("PhysicsService")

local MAP_NAME = "Map_WC3_Style"

---------------------------------------------------------------------
-- MEDIDAS (cámbialas aquí; todo el mapa se recalcula)
---------------------------------------------------------------------
local FLOOR_Y = 10
local FLOOR_THICKNESS = 4
local FLOOR_TOP = FLOOR_Y + FLOOR_THICKNESS / 2 -- 12: todo el piso queda a esta altura

-- Ciudad fortificada
local CITY_SIZE = 800
local CITY_HALF = CITY_SIZE / 2
local CITY_WALL_HEIGHT = 40
local CITY_WALL_THICKNESS = 6
local CITY_GATE_WIDTH = 200
local CITY_TOWER_SIZE = 26
local CITY_TOWER_HEIGHT = 52
local PLAZA_SIZE = 200
local PLAZA_U = CITY_SIZE / 2 -- centro de la plaza (u)
local BUILDING_RING_RADIUS = 200

-- Franjas en abanico
local STRIP_DEPTH = 625
local STRIP_COUNT = 4
local TOTAL_LENGTH = CITY_SIZE + STRIP_DEPTH * STRIP_COUNT -- 3300
-- Ancho del abanico justo detrás de la ciudad y apertura de cada diagonal lateral.
-- Con 490 y 30 grados los anchos promedio de las franjas son ~851 / 1573 / 2294 / 3016.
local FAN_NEAR_WIDTH = 490
local FAN_HALF_ANGLE_DEG = 30
local FAN_SLICE_DEPTH = 30 -- profundidad de cada losa del piso (más chico = borde menos dentado)

-- Arena y puentes
local ARENA_SIZE = 1500
local ARENA_HALF = ARENA_SIZE / 2
local BRIDGE_WIDTH = 100
local BRIDGE_LENGTH = 400
local BRIDGE_ARENA_OVERLAP = 60 -- el puente se mete bajo el piso de la arena (sin huecos)
local BRIDGE_VISIBLE_TRANSPARENCY = 0 -- puente opaco (antes 0.15 con neón: se veía blanco brillante)

-- Muros
local WALL_HEIGHT = 40
local WALL_THICKNESS = 2
local WALL_TRANSPARENCY = 0.85
local INVISIBLE_WALL_THICKNESS = 6
local GATE_MARGIN = 16 -- holgura extra de las compuertas respecto al puente

local MAX_PART_LENGTH = 2000 -- límite de Roblox: 2048

local OCEAN_TILE = 2000
local OCEAN_TILES_PER_SIDE = 7 -- 7 x 2000 = 14000 studs de océano (el mapa llega a ~4850 del centro)
local OCEAN_Y = -6

local METIN_COUNT = 8
local METIN_RING_RADIUS = 450

-- Temporizador de evento (segundos)
local AUTO_EVENT_TIMER = true
local EVENT_INTERVAL_SECONDS = 1800 -- tiempo con los puentes cerrados
local EVENT_OPEN_SECONDS = 600 -- tiempo con los puentes abiertos
local EVENT_GROUP = "Event_Bridges"

-- Al elegir facción (atributo Faction) el jugador es llevado a su ciudad
local TELEPORT_ON_FACTION_CHANGE = true

type Strip = { Id: string, MinLevel: number, MaxLevel: number }

local STRIPS: { Strip } = {
	{ Id = "Franja1", MinLevel = 1, MaxLevel = 25 },
	{ Id = "Franja2", MinLevel = 26, MaxLevel = 50 },
	{ Id = "Franja3", MinLevel = 51, MaxLevel = 75 },
	{ Id = "Franja4", MinLevel = 76, MaxLevel = 100 },
}

type BiomeDef = {
	Id: string,
	Faction: string,
	Display: string,
	OutDir: Vector3, -- dirección desde el centro del mapa hacia la ciudad
	SafeColor: Color3,
	PveColor: Color3,
	WallColor: Color3,
}

local BIOMES: { BiomeDef } = {
	{
		Id = "Imperio_Saiyan", Faction = "Saiyan", Display = "Imperio Saiyan",
		OutDir = Vector3.new(0, 0, -1),
		SafeColor = Color3.fromRGB(240, 170, 60), PveColor = Color3.fromRGB(135, 85, 50),
		WallColor = Color3.fromRGB(255, 160, 60),
	},
	{
		Id = "Alianza_Shinobi", Faction = "Shinobi", Display = "Alianza Shinobi",
		OutDir = Vector3.new(-1, 0, 0), -- v6.5: salida RECTA hacia el oeste
		SafeColor = Color3.fromRGB(120, 200, 110), PveColor = Color3.fromRGB(60, 105, 60),
		WallColor = Color3.fromRGB(90, 220, 110),
	},
	{
		Id = "Flota_Pirata", Faction = "Pirate", Display = "Flota Pirata",
		OutDir = Vector3.new(1, 0, 0), -- v6.5: salida RECTA hacia el este
		SafeColor = Color3.fromRGB(70, 150, 220), PveColor = Color3.fromRGB(125, 100, 75),
		WallColor = Color3.fromRGB(80, 170, 255),
	},
	{
		Id = "Corte_Shinigami", Faction = "Shinigami", Display = "Corte Shinigami",
		OutDir = Vector3.new(0, 0, 1), -- v6.37: salida RECTA hacia el sur (el hueco libre junto a la arena)
		SafeColor = Color3.fromRGB(190, 175, 235), PveColor = Color3.fromRGB(95, 85, 120),
		WallColor = Color3.fromRGB(165, 140, 255),
	},
}

local FACTION_TO_BIOME: { [string]: string } = {}
for _, def in ipairs(BIOMES) do
	FACTION_TO_BIOME[def.Faction] = def.Id
end

local FACTION_ALIASES: { [string]: string } = {
	saiyan = "Saiyan", saiyajin = "Saiyan",
	shinobi = "Shinobi",
	pirate = "Pirate", pirata = "Pirate", pirates = "Pirate",
	shinigami = "Shinigami", bleach = "Shinigami",
}

local DEFAULT_FACTION = "Saiyan"

---------------------------------------------------------------------
-- ESTRUCTURAS DEL BARRIO COMERCIAL (greybox)
---------------------------------------------------------------------
type BuildingSpec = {
	Slot: number,
	Kind: string, -- "dojo" | "forge" | "lab" | "bazaar" | "hall" | "vip"
	ModelName: string,
	Display: string,
	Role: string,
	Width: number,
	Depth: number,
	WallHeight: number,
	Base: number, -- altura de la plataforma (0 = a ras de piso)
	Left: number, -- fracción de la profundidad que cubre la pared izquierda (0..1)
	Right: number, -- ídem derecha
	FrontOpening: number?, -- si existe: pared frontal con una abertura de este ancho
	FrontPosts: boolean,
	WallColor: Color3,
	RoofColor: Color3,
	Accent: Color3,
	RingAngle: number, -- ángulo (grados) alrededor de la plaza
}

local BUILDINGS: { BuildingSpec } = {
	{
		Slot = 1, Kind = "dojo", ModelName = "Dojo_del_Instructor", Display = "Dojo del Instructor", Role = "Instructor",
		Width = 70, Depth = 50, WallHeight = 12, Base = 0, Left = 1, Right = 1, FrontOpening = nil, FrontPosts = true,
		WallColor = Color3.fromRGB(176, 150, 120), RoofColor = Color3.fromRGB(110, 60, 55), Accent = Color3.fromRGB(120, 85, 55),
		RingAngle = 150,
	},
	{
		Slot = 2, Kind = "forge", ModelName = "Forja_del_Herrero", Display = "Forja del Herrero", Role = "Herrero",
		Width = 50, Depth = 50, WallHeight = 12, Base = 0, Left = 1, Right = 0.5, FrontOpening = nil, FrontPosts = true,
		WallColor = Color3.fromRGB(110, 110, 118), RoofColor = Color3.fromRGB(60, 60, 68), Accent = Color3.fromRGB(95, 70, 50),
		RingAngle = 90,
	},
	{
		Slot = 3, Kind = "lab", ModelName = "Laboratorio_del_Alquimista", Display = "Laboratorio del Alquimista", Role = "Alquimista",
		Width = 40, Depth = 40, WallHeight = 22, Base = 0, Left = 1, Right = 1, FrontOpening = 22, FrontPosts = false,
		WallColor = Color3.fromRGB(120, 95, 150), RoofColor = Color3.fromRGB(70, 50, 100), Accent = Color3.fromRGB(95, 70, 50),
		RingAngle = 270,
	},
	{
		Slot = 4, Kind = "bazaar", ModelName = "Bazar_del_Mercader", Display = "Bazar del Mercader", Role = "Mercader",
		Width = 40, Depth = 40, WallHeight = 10, Base = 0, Left = 0, Right = 0, FrontOpening = nil, FrontPosts = true,
		WallColor = Color3.fromRGB(190, 160, 110), RoofColor = Color3.fromRGB(190, 70, 60), Accent = Color3.fromRGB(125, 90, 55),
		RingAngle = 30,
	},
	{
		Slot = 5, Kind = "hall", ModelName = "Ayuntamiento_de_Clanes", Display = "Ayuntamiento de Clanes", Role = "Clanes",
		Width = 60, Depth = 50, WallHeight = 20, Base = 0, Left = 1, Right = 1, FrontOpening = 30, FrontPosts = false,
		WallColor = Color3.fromRGB(200, 195, 185), RoofColor = Color3.fromRGB(90, 100, 130), Accent = Color3.fromRGB(120, 85, 55),
		RingAngle = 210,
	},
	{
		Slot = 6, Kind = "vip", ModelName = "Pabellon_VIP", Display = "Pabellón VIP", Role = "VIP",
		Width = 40, Depth = 40, WallHeight = 14, Base = 6, Left = 0, Right = 0, FrontOpening = nil, FrontPosts = true,
		WallColor = Color3.fromRGB(235, 225, 200), RoofColor = Color3.fromRGB(60, 40, 90), Accent = Color3.fromRGB(230, 190, 70),
		RingAngle = 330,
	},
}

---------------------------------------------------------------------
-- GEOMETRÍA DE CARRIL / ABANICO
---------------------------------------------------------------------
type Lane = {
	Def: BiomeDef,
	Out: Vector3, -- hacia afuera (centro -> ciudad)
	Dir: Vector3, -- hacia afuera (ciudad -> límites del mapa); es el sentido en que crece u
	Side: Vector3,
	Hit: number, -- distancia centro -> borde de la arena siguiendo el eje del carril
	Start: Vector3, -- punto medio del portón de la ciudad que mira a la arena (u = 0), Y = 0
	End: Vector3, -- punto medio del borde posterior de la franja 4 (u = TOTAL_LENGTH), Y = 0
}

local FAN_SLOPE = math.tan(math.rad(FAN_HALF_ANGLE_DEG)) -- crecimiento lateral por stud, de cada lado

local function computeLane(def: BiomeDef): Lane
	local out = def.OutDir.Unit
	local hit = ARENA_HALF / math.max(math.abs(out.X), math.abs(out.Z))
	return {
		Def = def,
		Out = out,
		Dir = out,
		Side = Vector3.new(-out.Z, 0, out.X),
		Hit = hit,
		-- Arena (centro) -> borde de la arena (hit) -> puente (400) -> portón de la ciudad (u = 0) -> ... -> fondo del mapa
		Start = out * (hit + BRIDGE_LENGTH),
		End = out * (hit + BRIDGE_LENGTH + TOTAL_LENGTH),
	}
end

local function lanePos(lane: Lane, u: number, v: number, y: number): Vector3
	local p = lane.Start + lane.Dir * u + lane.Side * v
	return Vector3.new(p.X, y, p.Z)
end

-- Medio ancho del abanico a la distancia u (válido desde u = CITY_SIZE)
local function fanHalfWidth(u: number): number
	return FAN_NEAR_WIDTH / 2 + FAN_SLOPE * (u - CITY_SIZE)
end

---------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------
local function newPart(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cf
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newMarker(name: string, position: Vector3, parent: Instance): Part
	local marker = Instance.new("Part")
	marker.Name = name
	marker.Anchored = true
	marker.Size = Vector3.new(1, 1, 1)
	marker.Position = position
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Parent = parent
	return marker
end

local function newFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function addLabel(parent: BasePart, text: string, offsetY: number, width: number, textSize: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 50)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 600
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.Parent = gui
end

-- Caja alineada al carril: u (largo, de u0 a u1) y v (ancho, de v0 a v1). Se parte sola si el largo pasa de 2000.
local function laneBox(
	name: string, lane: Lane, u0: number, u1: number, v0: number, v1: number,
	centerY: number, height: number, color: Color3, material: Enum.Material, parent: Instance
): { Part }
	local parts: { Part } = {}
	local total = u1 - u0
	local count = math.max(1, math.ceil(total / MAX_PART_LENGTH))
	local seg = total / count
	for i = 1, count do
		local a = u0 + (i - 1) * seg
		local b = a + seg
		local mid = lanePos(lane, (a + b) / 2, (v0 + v1) / 2, centerY)
		local partName = if count > 1 then string.format("%s_%d", name, i) else name
		local part = newPart(
			partName,
			Vector3.new(v1 - v0, height, seg),
			CFrame.lookAt(mid, mid + lane.Dir),
			color, material, parent
		)
		table.insert(parts, part)
	end
	return parts
end

-- Muro de colisión que no se ve ni bloquea clics/rayos (protección contra caídas)
local function makeInvisibleWall(part: Part)
	part.Transparency = 1
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part:SetAttribute("InvisibleWall", true)
end

local function styleEventWall(part: Part, color: Color3)
	part.Transparency = WALL_TRANSPARENCY
	part.Color = color
	part.Material = Enum.Material.Neon
	part.CastShadow = false
end

---------------------------------------------------------------------
-- FACCIONES: grupos de colisión para el FactionBarrier
---------------------------------------------------------------------
local function setupCollisionGroups()
	local factions: { string } = {}
	for _, def in ipairs(BIOMES) do
		table.insert(factions, def.Faction)
	end

	for _, f in ipairs(factions) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Barrier_" .. f)
		end)
		pcall(function()
			PhysicsService:RegisterCollisionGroup("Player_" .. f)
		end)
	end

	for _, barrierFaction in ipairs(factions) do
		local barrierGroup = "Barrier_" .. barrierFaction
		-- La barrera no choca con nada "normal" (NPCs, dummies, jugadores sin facción) ni con otras barreras
		PhysicsService:CollisionGroupSetCollidable(barrierGroup, "Default", false)
		for _, other in ipairs(factions) do
			PhysicsService:CollisionGroupSetCollidable(barrierGroup, "Barrier_" .. other, false)
			-- Solo choca con jugadores de OTRA facción
			PhysicsService:CollisionGroupSetCollidable(barrierGroup, "Player_" .. other, other ~= barrierFaction)
		end
	end
end

local function normalizeFaction(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	local key = (value :: string):lower()
	return FACTION_ALIASES[key]
end

---------------------------------------------------------------------
-- BARRERAS DE LA ARENA (cuadrado con compuertas donde llegan los puentes)
---------------------------------------------------------------------
type Gate = { Side: string, Offset: number, Width: number, Group: string }

local function buildArenaBarrier(center: Vector3, half: number, baseTop: number, gates: { Gate }, color: Color3, parent: Instance)
	local wallY = baseTop + WALL_HEIGHT / 2

	for _, side in ipairs({ "PX", "NX", "PZ", "NZ" }) do
		local isX = side == "PX" or side == "NX"
		local sign = if side == "PX" or side == "PZ" then 1 else -1

		local sideGates: { Gate } = {}
		for _, g in ipairs(gates) do
			if g.Side == side then
				table.insert(sideGates, g)
			end
		end
		table.sort(sideGates, function(a: Gate, b: Gate)
			return a.Offset < b.Offset
		end)

		local function addPiece(name: string, from: number, to: number, group: string?)
			local len = to - from
			if len < 0.5 then
				return
			end
			local mid = (from + to) / 2
			local fixed = sign * (half - WALL_THICKNESS / 2)
			local pos = if isX
				then Vector3.new(center.X + fixed, wallY, center.Z + mid)
				else Vector3.new(center.X + mid, wallY, center.Z + fixed)
			local size = if isX
				then Vector3.new(WALL_THICKNESS, WALL_HEIGHT, len)
				else Vector3.new(len, WALL_HEIGHT, WALL_THICKNESS)
			local piece = newPart(name, size, CFrame.new(pos), color, Enum.Material.Neon, parent)
			styleEventWall(piece, color)
			if group then
				piece:SetAttribute("GateGroup", group)
			end
		end

		local cursor = -half
		local n = 0
		for _, g in ipairs(sideGates) do
			local halfGate = g.Width / 2
			local off = math.clamp(g.Offset, -half + halfGate + 1, half - halfGate - 1)
			n += 1
			addPiece(string.format("Arena_%s_Muro%d", side, n), cursor, off - halfGate, nil)
			addPiece(string.format("Arena_%s_Compuerta%d", side, n), off - halfGate, off + halfGate, g.Group)
			cursor = off + halfGate
		end
		addPiece(string.format("Arena_%s_Muro%d", side, n + 1), cursor, half, nil)
	end
end

---------------------------------------------------------------------
-- ESTRUCTURA GREYBOX (casa/tienda con paredes, techo, mostrador y NPCSpawnPoint)
---------------------------------------------------------------------
local WALL_T = 1.5 -- grosor de las paredes de los edificios

local function buildStructure(spec: BuildingSpec, lane: Lane, def: BiomeDef, parent: Instance)
	local angle = math.rad(spec.RingAngle)
	local origin = lanePos(
		lane,
		PLAZA_U + math.cos(angle) * BUILDING_RING_RADIUS,
		math.sin(angle) * BUILDING_RING_RADIUS,
		FLOOR_TOP
	)
	local plazaCenter = lanePos(lane, PLAZA_U, 0, FLOOR_TOP)
	local front = (plazaCenter - origin).Unit -- el frente mira a la plaza
	local bcf = CFrame.lookAt(origin, origin + front)

	-- Marco local: X = a lo ancho, Y = arriba (0 = piso), Z = profundidad (el frente está en -Z)
	local model = Instance.new("Model")
	model.Name = spec.ModelName
	model:SetAttribute("Slot", spec.Slot)
	model:SetAttribute("Role", spec.Role)
	model:SetAttribute("Biome", def.Id)
	model.Parent = parent

	local function bp(name: string, lx: number, ly: number, lz: number, sx: number, sy: number, sz: number, color: Color3, material: Enum.Material): Part
		return newPart(name, Vector3.new(sx, sy, sz), bcf * CFrame.new(lx, ly, lz), color, material, model)
	end

	local W, D, H, base = spec.Width, spec.Depth, spec.WallHeight, spec.Base
	local yWall = base + H / 2

	-- Parcela (terreno de la estructura)
	local lot = bp("Parcela", 0, 0.15, 0, W + 16, 0.3, D + 16, Color3.fromRGB(150, 150, 155), Enum.Material.Concrete)
	lot.CanCollide = false

	-- Plataforma + escalones (solo si está elevada)
	if base > 0 then
		bp("Plataforma", 0, base / 2, 0, W, base, D, spec.WallColor, Enum.Material.Marble)
		for i = 1, 3 do
			bp(
				"Escalon_" .. i, 0, base * i / 3 / 2, -D / 2 - 1.5 - (3 - i) * 3,
				16, base * i / 3, 3, spec.WallColor, Enum.Material.Marble
			)
		end
	end

	-- Paredes
	bp("Pared_Trasera", 0, yWall, D / 2 - WALL_T / 2, W, H, WALL_T, spec.WallColor, Enum.Material.Concrete)
	if spec.Left > 0 then
		local len = D * spec.Left
		bp("Pared_Izquierda", -(W / 2 - WALL_T / 2), yWall, D / 2 - len / 2, WALL_T, H, len, spec.WallColor, Enum.Material.Concrete)
	end
	if spec.Right > 0 then
		local len = D * spec.Right
		bp("Pared_Derecha", W / 2 - WALL_T / 2, yWall, D / 2 - len / 2, WALL_T, H, len, spec.WallColor, Enum.Material.Concrete)
	end

	-- Pared frontal con abertura (estructuras cerradas)
	if spec.FrontOpening then
		local op = spec.FrontOpening
		local openingHeight = H * 0.62
		local sideLen = (W - op) / 2
		local fz = -D / 2 + WALL_T / 2
		bp("Frente_Izquierdo", -(op / 2 + sideLen / 2), yWall, fz, sideLen, H, WALL_T, spec.WallColor, Enum.Material.Concrete)
		bp("Frente_Derecho", op / 2 + sideLen / 2, yWall, fz, sideLen, H, WALL_T, spec.WallColor, Enum.Material.Concrete)
		bp("Frente_Dintel", 0, base + openingHeight + (H - openingHeight) / 2, fz, op, H - openingHeight, WALL_T, spec.WallColor, Enum.Material.Concrete)
	end

	-- Columnas frontales (estructuras abiertas)
	if spec.FrontPosts then
		for _, sx in ipairs({ -1, 1 }) do
			bp("Columna_Frontal_" .. (if sx < 0 then "Izq" else "Der"), sx * (W / 2 - 1.5), base + H / 2, -D / 2 + 1.5, 2, H, 2, spec.Accent, Enum.Material.WoodPlanks)
		end
	end

	-- Techo
	local roof = bp("Techo", 0, base + H + 0.6, 0, W + 4, 1.2, D + 4, spec.RoofColor, Enum.Material.Slate)
	addLabel(roof, spec.Display, 8, 280, 16)

	-- Mostrador y punto del NPC (detrás del mostrador, mirando al frente)
	local counterZ = -D / 2 + 6
	local counterWidth = math.min(W * 0.5, 24)
	bp("Mostrador", 0, base + 1.75, counterZ, counterWidth, 3.5, 3, spec.Accent, Enum.Material.WoodPlanks)

	local npcPoint = newMarker("NPCSpawnPoint", origin, model)
	npcPoint.CFrame = bcf * CFrame.new(0, base, counterZ + 4.5)
	npcPoint:SetAttribute("Slot", spec.Slot)
	npcPoint:SetAttribute("Role", spec.Role)
	npcPoint:SetAttribute("Display", spec.Display)
	npcPoint:SetAttribute("Biome", def.Id)
	CollectionService:AddTag(npcPoint, "NPCSlot")

	-- Detalles propios de cada estructura
	local kind = spec.Kind
	if kind == "dojo" then
		local tatami = bp("Tatami", 0, 0.2, 4, W - 8, 0.4, D - 22, Color3.fromRGB(215, 195, 150), Enum.Material.SmoothPlastic)
		tatami.CanCollide = false
		bp("Poste_Entrenamiento_1", -18, 5, 14, 2, 10, 2, spec.Accent, Enum.Material.WoodPlanks)
		bp("Poste_Entrenamiento_2", 18, 5, 14, 2, 10, 2, spec.Accent, Enum.Material.WoodPlanks)
	elseif kind == "forge" then
		local stone = Color3.fromRGB(80, 80, 88)
		bp("Chimenea", W / 2 - 5, base + (H + 16) / 2, D / 2 - 5, 5, H + 16, 5, stone, Enum.Material.Brick)
		bp("Horno", -W / 2 + 8, base + 3, D / 2 - 6, 9, 6, 6, stone, Enum.Material.Brick)
		bp("Brasas", -W / 2 + 8, base + 6.25, D / 2 - 6, 7, 0.5, 4, Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		bp("Yunque_Base", -W / 2 + 9, base + 1, -4, 3, 2, 2.5, Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
		bp("Yunque_Tope", -W / 2 + 9, base + 2.5, -4, 5, 1, 2, Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
	elseif kind == "lab" then
		bp("Torre", 0, base + H + 1.2 + 9, 6, W * 0.5, 18, D * 0.5, spec.WallColor, Enum.Material.Concrete)
		bp("Torre_Techo", 0, base + H + 1.2 + 18 + 0.6, 6, W * 0.5 + 3, 1.2, D * 0.5 + 3, spec.RoofColor, Enum.Material.Slate)
		local orb = bp("Esfera_Alquimia", 0, base + H + 1.2 + 18 + 5, 6, 5, 5, 5, Color3.fromRGB(90, 255, 140), Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
		bp("Frasco_Mostrador", 6, base + 4.5, counterZ, 1.6, 1.6, 1.6, Color3.fromRGB(90, 255, 140), Enum.Material.Neon)
	elseif kind == "bazaar" then
		bp("Toldo", 0, base + H - 1, -D / 2 - 3, W + 4, 0.8, 10, spec.RoofColor, Enum.Material.Fabric)
		bp("Caja_1", -W / 2 + 4, 2, -D / 2 - 6, 4, 4, 4, spec.Accent, Enum.Material.WoodPlanks)
		bp("Caja_2", -W / 2 + 9, 1.5, -D / 2 - 6, 3, 3, 3, spec.Accent, Enum.Material.WoodPlanks)
		bp("Caja_3", W / 2 - 5, 2, -D / 2 - 6, 4, 4, 4, spec.Accent, Enum.Material.WoodPlanks)
	elseif kind == "hall" then
		local opening = spec.FrontOpening or 30
		for _, sx in ipairs({ -1, 1 }) do
			bp("Pilar_" .. (if sx < 0 then "Izq" else "Der"), sx * (opening / 2 + 5), (H + 2) / 2, -D / 2 - 2, 3, H + 2, 3, spec.WallColor, Enum.Material.Marble)
		end
		bp("Frontis", 0, H + 4.2, -D / 2 - 1, W * 0.6, 6, 3, spec.WallColor, Enum.Material.Marble)
		bp("Asta_Bandera", W / 2 - 3, H + 12, D / 2 - 3, 1, 24, 1, Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
		bp("Bandera", W / 2, H + 20, D / 2 - 3, 6, 4, 0.4, def.WallColor, Enum.Material.Neon)
	elseif kind == "vip" then
		local gold = spec.Accent
		for _, sx in ipairs({ -1, 1 }) do
			bp("Columna_Trasera_" .. (if sx < 0 then "Izq" else "Der"), sx * (W / 2 - 1.5), base + H / 2, D / 2 - 1.5, 2, H, 2, gold, Enum.Material.Marble)
		end
		bp("Borde_Dorado_Frente", 0, base + H + 1.5, -D / 2 - 2, W + 4, 0.6, 0.6, gold, Enum.Material.Neon)
		bp("Borde_Dorado_Fondo", 0, base + H + 1.5, D / 2 + 2, W + 4, 0.6, 0.6, gold, Enum.Material.Neon)
		bp("Borde_Dorado_Izq", -(W / 2 + 2), base + H + 1.5, 0, 0.6, 0.6, D + 4, gold, Enum.Material.Neon)
		bp("Borde_Dorado_Der", W / 2 + 2, base + H + 1.5, 0, 0.6, 0.6, D + 4, gold, Enum.Material.Neon)
		local orb = bp("Orbe_VIP", 0, base + H + 5, 0, 4, 4, 4, gold, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
	end
end

---------------------------------------------------------------------
-- CIUDAD FORTIFICADA
---------------------------------------------------------------------
local function buildCity(lane: Lane, folder: Folder)
	local def = lane.Def
	local cityFolder = newFolder("Ciudad", folder)
	local floorFolder = newFolder("Piso", cityFolder)
	local wallFolder = newFolder("Murallas", cityFolder)
	local quarter = newFolder("Barrio_Comercial", cityFolder)

	local stone = Color3.fromRGB(128, 122, 116)
	local wallY = FLOOR_TOP + CITY_WALL_HEIGHT / 2

	-- Piso de la ciudad (ZoneSafe)
	local safeParts = laneBox(
		"Z1_Ciudad", lane, 0, CITY_SIZE, -CITY_HALF, CITY_HALF,
		FLOOR_Y, FLOOR_THICKNESS, def.SafeColor, Enum.Material.Marble, floorFolder
	)
	for _, p in ipairs(safeParts) do
		CollectionService:AddTag(p, "ZoneSafe")
		p:SetAttribute("Biome", def.Id)
	end

	-- Plaza Central (social) + camino hacia la puerta + fuente
	local plaza = laneBox(
		"Plaza_Central", lane, PLAZA_U - PLAZA_SIZE / 2, PLAZA_U + PLAZA_SIZE / 2, -PLAZA_SIZE / 2, PLAZA_SIZE / 2,
		FLOOR_TOP + 0.2, 0.4, def.SafeColor:Lerp(Color3.new(1, 1, 1), 0.55), Enum.Material.Marble, floorFolder
	)
	plaza[1].CanCollide = false
	local roadToArena = laneBox(
		"Camino_a_la_Arena", lane, 0, PLAZA_U - PLAZA_SIZE / 2, -30, 30,
		FLOOR_TOP + 0.2, 0.4, Color3.fromRGB(150, 150, 155), Enum.Material.Concrete, floorFolder
	)
	roadToArena[1].CanCollide = false
	local roadToFields = laneBox(
		"Camino_a_las_Franjas", lane, PLAZA_U + PLAZA_SIZE / 2, CITY_SIZE, -30, 30,
		FLOOR_TOP + 0.2, 0.4, Color3.fromRGB(150, 150, 155), Enum.Material.Concrete, floorFolder
	)
	roadToFields[1].CanCollide = false

	local fountainPos = lanePos(lane, PLAZA_U - 40, 0, FLOOR_TOP + 1.5)
	local fountain = newPart(
		"Fuente_Plaza", Vector3.new(3, 30, 30),
		CFrame.new(fountainPos) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(190, 190, 200), Enum.Material.Marble, floorFolder
	)
	fountain.Shape = Enum.PartType.Cylinder
	local fountainWater = newPart(
		"Fuente_Agua", Vector3.new(0.4, 22, 22),
		CFrame.new(fountainPos + Vector3.new(0, 1.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(80, 170, 255), Enum.Material.Neon, floorFolder
	)
	fountainWater.Shape = Enum.PartType.Cylinder
	fountainWater.CanCollide = false
	fountainWater.Transparency = 0.35

	local plazaAnchor = newMarker("Plaza_Cartel", lanePos(lane, PLAZA_U, 0, FLOOR_TOP + 1), floorFolder)
	addLabel(plazaAnchor, def.Display .. " - Plaza Central", 34, 320, 18)

	-- SpawnLocation en la plaza
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn_" .. def.Id
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Position = lanePos(lane, PLAZA_U + 45, 0, FLOOR_TOP + 0.5)
	spawn.Material = Enum.Material.Neon
	spawn.Transparency = 0.4
	spawn:SetAttribute("Biome", def.Id)
	spawn.Parent = folder

	-- Murallas. La ciudad tiene DOS salidas:
	--   * Portón del puente (u = 0, mira a la Arena Central): compuerta dinámica de evento.
	--   * Salida trasera (u = 800, hacia la Franja 1): cerrada a otras facciones por el FactionBarrier.
	local function wall(name: string, u0: number, u1: number, v0: number, v1: number)
		for _, p in ipairs(laneBox(name, lane, u0, u1, v0, v1, wallY, CITY_WALL_HEIGHT, stone, Enum.Material.Brick, wallFolder)) do
			p:SetAttribute("Biome", def.Id)
		end
	end
	local t = CITY_WALL_THICKNESS
	local gateHalf = CITY_GATE_WIDTH / 2 -- salida trasera (hacia las franjas)
	local bridgeGateHalf = (BRIDGE_WIDTH + GATE_MARGIN) / 2 -- portón del puente
	wall("Muralla_Izquierda", 0, CITY_SIZE, -CITY_HALF, -CITY_HALF + t)
	wall("Muralla_Derecha", 0, CITY_SIZE, CITY_HALF - t, CITY_HALF)
	-- Lado de la arena (u = 0): muro con el portón del puente en el centro
	wall("Muralla_Arena_A", 0, t, -CITY_HALF, -bridgeGateHalf)
	wall("Muralla_Arena_B", 0, t, bridgeGateHalf, CITY_HALF)
	for _, p in ipairs(laneBox("Porton_Puente", lane, 0, t, -bridgeGateHalf, bridgeGateHalf, wallY, CITY_WALL_HEIGHT, def.WallColor, Enum.Material.Neon, wallFolder)) do
		styleEventWall(p, Color3.fromRGB(255, 90, 90))
		p:SetAttribute("GateGroup", EVENT_GROUP)
		p:SetAttribute("Biome", def.Id)
	end
	-- Lado de las franjas (u = 800): muro con la salida trasera
	wall("Muralla_Trasera_A", CITY_SIZE - t, CITY_SIZE, -CITY_HALF, -gateHalf)
	wall("Muralla_Trasera_B", CITY_SIZE - t, CITY_SIZE, gateHalf, CITY_HALF)

	-- Torres: 4 esquinas + 2 en cada puerta
	local towerY = FLOOR_TOP + CITY_TOWER_HEIGHT / 2
	local function tower(name: string, u0: number, u1: number, v0: number, v1: number)
		for _, p in ipairs(laneBox(name, lane, u0, u1, v0, v1, towerY, CITY_TOWER_HEIGHT, Color3.fromRGB(105, 100, 96), Enum.Material.Brick, wallFolder)) do
			p:SetAttribute("Biome", def.Id)
		end
	end
	local ts = CITY_TOWER_SIZE
	tower("Torre_Esquina_1", 0, ts, -CITY_HALF, -CITY_HALF + ts)
	tower("Torre_Esquina_2", 0, ts, CITY_HALF - ts, CITY_HALF)
	tower("Torre_Esquina_3", CITY_SIZE - ts, CITY_SIZE, -CITY_HALF, -CITY_HALF + ts)
	tower("Torre_Esquina_4", CITY_SIZE - ts, CITY_SIZE, CITY_HALF - ts, CITY_HALF)
	tower("Torre_Porton_A", 0, 24, -bridgeGateHalf - 24, -bridgeGateHalf)
	tower("Torre_Porton_B", 0, 24, bridgeGateHalf, bridgeGateHalf + 24)
	tower("Torre_Salida_A", CITY_SIZE - 24, CITY_SIZE, -gateHalf - 24, -gateHalf)
	tower("Torre_Salida_B", CITY_SIZE - 24, CITY_SIZE, gateHalf, gateHalf + 24)

	-- FactionBarrier: cierra la salida trasera solo a jugadores de otras facciones
	local barrierColor = def.SafeColor:Lerp(Color3.new(1, 1, 1), 0.2)
	local barrier = laneBox(
		"FactionBarrier_" .. def.Faction, lane, CITY_SIZE - 4, CITY_SIZE - 2, -gateHalf, gateHalf,
		wallY, CITY_WALL_HEIGHT, barrierColor, Enum.Material.ForceField, wallFolder
	)
	for _, p in ipairs(barrier) do
		p.Transparency = 0.5
		p.CastShadow = false
		p.CanQuery = false
		p.CollisionGroup = "Barrier_" .. def.Faction
		p:SetAttribute("Faction", def.Faction)
		p:SetAttribute("Biome", def.Id)
		CollectionService:AddTag(p, "FactionBarrier")
	end

	-- Barrio Comercial: las 6 estructuras alrededor de la plaza
	for _, spec in ipairs(BUILDINGS) do
		buildStructure(spec, lane, def, quarter)
	end
end

---------------------------------------------------------------------
-- BIOMA COMPLETO (ciudad + abanico de 4 franjas + muros invisibles)
---------------------------------------------------------------------
local function diagonalWall(name: string, lane: Lane, side: number, parent: Instance)
	local u0, u1 = CITY_SIZE, TOTAL_LENGTH
	local h0, h1 = fanHalfWidth(u0), fanHalfWidth(u1)
	local totalLen = math.sqrt((u1 - u0) ^ 2 + (h1 - h0) ^ 2)
	local count = math.max(1, math.ceil(totalLen / MAX_PART_LENGTH))
	for i = 1, count do
		local t0, t1 = (i - 1) / count, i / count
		local a = lanePos(lane, u0 + (u1 - u0) * t0, side * (h0 + (h1 - h0) * t0), 0)
		local b = lanePos(lane, u0 + (u1 - u0) * t1, side * (h0 + (h1 - h0) * t1), 0)
		local delta = b - a
		local dir = delta.Unit
		local mid = (a + b) / 2
		-- normal horizontal apuntando hacia AFUERA del abanico (lejos del eje central)
		local axisPoint = lanePos(lane, u0 + (u1 - u0) * (t0 + t1) / 2, 0, 0)
		local normal = Vector3.new(-dir.Z, 0, dir.X)
		if normal:Dot(mid - axisPoint) < 0 then
			normal = -normal
		end
		local pos = mid + normal * (INVISIBLE_WALL_THICKNESS / 2) + Vector3.new(0, FLOOR_TOP + WALL_HEIGHT / 2, 0)
		local piece = newPart(
			string.format("%s_%d", name, i),
			Vector3.new(INVISIBLE_WALL_THICKNESS, WALL_HEIGHT, delta.Magnitude + 1),
			CFrame.lookAt(pos, pos + dir),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, parent
		)
		makeInvisibleWall(piece)
	end
end

-- v6.44: MUROS ENTRE FRANJAS con 3 arcos gigantes (varias entradas a la siguiente franja) y un holograma con el nombre y los niveles
local GATE_COUNT_OFFSETS = { -0.55, 0, 0.55 } -- posición de cada arco (fracción del semiancho de la franja)
local GATE_WIDTH = 90
local GATE_WALL_HEIGHT = 46
local GATE_CLEAR_HEIGHT = 32
local GATE_WALL_THICKNESS = 8

local function buildStripGates(lane: Lane, parent: Instance)
	local def = lane.Def
	local folder = newFolder("Puertas_de_Franja", parent)
	for k = 1, #STRIPS - 1 do
		local u = CITY_SIZE + k * STRIP_DEPTH
		local nextStrip = STRIPS[k + 1]
		local half = fanHalfWidth(u) + 4
		local u0, u1 = u - GATE_WALL_THICKNESS / 2, u + GATE_WALL_THICKNESS / 2
		local gateFolder = newFolder(string.format("Puerta_Franja%d", k + 1), folder)
		local stoneColor = Color3.fromRGB(70, 66, 72):Lerp(def.WallColor, 0.15)
		local wallY = FLOOR_TOP + GATE_WALL_HEIGHT / 2
		-- tramos de muro entre arcos
		local edges: { number } = { -half }
		for _, f in ipairs(GATE_COUNT_OFFSETS) do
			local c = f * (half - 4)
			table.insert(edges, c - GATE_WIDTH / 2)
			table.insert(edges, c + GATE_WIDTH / 2)
		end
		table.insert(edges, half)
		for s = 1, #edges, 2 do
			local a, b = edges[s], edges[s + 1]
			if b - a > 1 then
				laneBox(string.format("Muro_%d", (s + 1) / 2), lane, u0, u1, a, b, wallY, GATE_WALL_HEIGHT, stoneColor, Enum.Material.Concrete, gateFolder)
			end
		end
		-- arcos
		for i, f in ipairs(GATE_COUNT_OFFSETS) do
			local c = f * (half - 4)
			local arch = newFolder("Arco_" .. i, gateFolder)
			-- dintel sobre el hueco
			laneBox("Dintel", lane, u0 - 2, u1 + 2, c - GATE_WIDTH / 2 - 6, c + GATE_WIDTH / 2 + 6, FLOOR_TOP + GATE_CLEAR_HEIGHT + (GATE_WALL_HEIGHT - GATE_CLEAR_HEIGHT) / 2 + 4, GATE_WALL_HEIGHT - GATE_CLEAR_HEIGHT + 8, stoneColor:Lerp(def.WallColor, 0.2), Enum.Material.Concrete, arch)
			-- pilares con franja de luz
			for _, side in ipairs({ -1, 1 }) do
				local pv = c + side * (GATE_WIDTH / 2 + 3)
				laneBox("Pilar", lane, u0 - 3, u1 + 3, pv - 6, pv + 6, FLOOR_TOP + 30, 60, stoneColor, Enum.Material.Concrete, arch)
				for _, p in ipairs(laneBox("Luz", lane, u0 - 3.5, u1 + 3.5, pv - 1.5, pv + 1.5, FLOOR_TOP + 30, 52, def.WallColor, Enum.Material.Neon, arch)) do
					p.CanCollide = false
				end
			end
		end

		-- UN SOLO holograma grande sobre el arco del medio: gira de izquierda a derecha, con el fondo de la facción (como los de los puentes)
		local signW, signH = 84, 26
		local signPos = lanePos(lane, u, 0, FLOOR_TOP + GATE_WALL_HEIGHT + 38)
		local label = string.format("FRANJA %d", k + 1)
		local range = string.format("Niveles %d-%d%s", nextStrip.MinLevel, nextStrip.MaxLevel, if k + 1 == #STRIPS then " · ÉLITE" else "")
		local holo = Instance.new("Model")
		holo.Name = "Holograma"
		holo.Parent = gateFolder
		local svc = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local kitMod = svc and svc:FindFirstChild("SignKit")
		local okKit, kit = false, nil
		if kitMod and kitMod:IsA("ModuleScript") then
			okKit, kit = pcall(require, kitMod)
		end
		local look = if okKit and kit then kit.LOOKS[def.Id] else nil
		local board = newPart("Cartel", Vector3.new(signW, signH, 1.6), CFrame.lookAt(signPos, signPos + lane.Dir), if look then look.Board else def.WallColor, Enum.Material.SmoothPlastic, holo)
		board.CanCollide = false
		board.CanQuery = false
		board.CanTouch = false
		board.CastShadow = false
		if look and kit then
			kit.Design(board, Enum.NormalId.Front, def.Id, look, signW, signH, label, range)
			kit.Design(board, Enum.NormalId.Back, def.Id, look, signW, signH, label, range)
		else
			addLabel(board, label .. "\n" .. range, 0, 260, 22)
		end
		for _, dy in ipairs({ -signH / 2 - 0.6, signH / 2 + 0.6 }) do
			local trim = newPart("Borde", Vector3.new(signW + 2, 1.2, 2.4), CFrame.lookAt(signPos + Vector3.new(0, dy, 0), signPos + Vector3.new(0, dy, 0) + lane.Dir), if look then look.Trim else def.WallColor, Enum.Material.Metal, holo)
			trim.CanCollide = false
			trim.CanQuery = false
			trim.CanTouch = false
			trim.CastShadow = false
		end
		local glow = Instance.new("PointLight")
		glow.Color = if look then look.Trim else def.WallColor
		glow.Range = 70
		glow.Brightness = 1.5
		glow.Parent = board
		holo.WorldPivot = CFrame.new(signPos) -- eje vertical del mundo: gira de izquierda a derecha
		CollectionService:AddTag(holo, "SpinEmblem") -- SpinEmblemClient lo hace girar (igual que los emblemas de los puentes)
		-- poste de soporte (no gira) desde el dintel del arco del medio
		local postH = (signPos.Y - signH / 2) - (FLOOR_TOP + GATE_WALL_HEIGHT)
		if postH > 1 then
			local post = newPart("Soporte", Vector3.new(3, postH, 3), CFrame.new(signPos.X, FLOOR_TOP + GATE_WALL_HEIGHT + postH / 2, signPos.Z), stoneColor, Enum.Material.Concrete, gateFolder)
			post.CanCollide = false
			post.CanQuery = false
			post.CanTouch = false
		end
	end
end

local function buildLane(lane: Lane, map: Folder)
	local def = lane.Def
	local folder = newFolder(def.Id, map)

	buildCity(lane, folder)

	local fanFolder = newFolder("Abanico", folder)
	local floorFolder = newFolder("Piso", fanFolder)

	-- Franjas: losas de ~30 studs. Cada losa usa el ancho del abanico en su borde lejano,
	-- así el piso siempre cubre hasta la diagonal (lo que sobra queda tras el muro invisible).
	local sliceCount = math.max(1, math.round(STRIP_DEPTH / FAN_SLICE_DEPTH))
	local sliceDepth = STRIP_DEPTH / sliceCount

	for i, strip in ipairs(STRIPS) do
		local u0 = CITY_SIZE + (i - 1) * STRIP_DEPTH
		local u1 = u0 + STRIP_DEPTH
		local t = (i - 1) / (#STRIPS - 1)
		local color = def.PveColor:Lerp(Color3.fromRGB(150, 40, 45), t * 0.55)

		local stripFolder = newFolder(string.format("Z%d_%s", i + 1, strip.Id), floorFolder)

		local function tagSlice(p: Part)
			CollectionService:AddTag(p, "ZonePvE")
			p:SetAttribute("Biome", def.Id)
			p:SetAttribute("Strip", i)
			p:SetAttribute("MinLevel", strip.MinLevel)
			p:SetAttribute("MaxLevel", strip.MaxLevel)
			p:SetAttribute("UStart", u0)
			p:SetAttribute("UEnd", u1)
			-- v6.38: geometría del carril para que MobService ubique a los enemigos por franja y lejos de los bordes
			p:SetAttribute("LaneStart", lane.Start)
			p:SetAttribute("LaneDir", lane.Dir)
			p:SetAttribute("FanC", FAN_NEAR_WIDTH / 2 - FAN_SLOPE * CITY_SIZE) -- semiancho(u) = FanC + FanK * u
			p:SetAttribute("FanK", FAN_SLOPE)
			-- v6: las franjas de las ciudades son 100% PvE entre aliados (el PvP vive solo en la Arena Central)
		end

		for k = 1, sliceCount do
			local a = u0 + (k - 1) * sliceDepth
			local b = a + sliceDepth
			local half = fanHalfWidth(b) + 1
			local name = string.format("Losa_%02d", k)
			if half * 2 > MAX_PART_LENGTH then
				-- Demasiado ancha para una sola parte: se parte en mitad izquierda y derecha
				for _, p in ipairs(laneBox(name .. "_I", lane, a, b, -half, 0, FLOOR_Y, FLOOR_THICKNESS, color, Enum.Material.Ground, stripFolder)) do
					tagSlice(p)
				end
				for _, p in ipairs(laneBox(name .. "_D", lane, a, b, 0, half, FLOOR_Y, FLOOR_THICKNESS, color, Enum.Material.Ground, stripFolder)) do
					tagSlice(p)
				end
			else
				for _, p in ipairs(laneBox(name, lane, a, b, -half, half, FLOOR_Y, FLOOR_THICKNESS, color, Enum.Material.Ground, stripFolder)) do
					tagSlice(p)
				end
			end
		end

		-- Cartel de la franja (en el centro del carril)
		local avgWidth = (fanHalfWidth(u0) + fanHalfWidth(u1))
		local anchor = newMarker(strip.Id .. "_Cartel", lanePos(lane, (u0 + u1) / 2, 0, FLOOR_TOP + 1), stripFolder)
		local label = if i == #STRIPS
			then string.format("Franja %d - Nvl %d-%d (ÉLITE)", i, strip.MinLevel, strip.MaxLevel)
			else string.format("Franja %d - Nvl %d-%d", i, strip.MinLevel, strip.MaxLevel)
		addLabel(anchor, label, 30, 380, 16)
		anchor:SetAttribute("AverageWidth", math.round(avgWidth))
	end

	buildStripGates(lane, fanFolder)

	-- Muros invisibles de colisión: las dos diagonales laterales
	local invisibleFolder = newFolder("Muros_Invisibles", fanFolder)
	diagonalWall("Diagonal_Izquierda", lane, -1, invisibleFolder)
	diagonalWall("Diagonal_Derecha", lane, 1, invisibleFolder)

	-- Borde posterior de la franja 4 (el fondo del mapa): un muro invisible continuo de punta a punta.
	-- Mide ~3400 studs, así que se parte en dos mitades (una parte no puede pasar de 2048).
	local backHalf = fanHalfWidth(TOTAL_LENGTH) + INVISIBLE_WALL_THICKNESS + 2
	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	local backU0 = TOTAL_LENGTH - INVISIBLE_WALL_THICKNESS
	for _, p in ipairs(laneBox("Borde_Posterior_I", lane, backU0, TOTAL_LENGTH, -backHalf, 0, wallY, WALL_HEIGHT, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, invisibleFolder)) do
		makeInvisibleWall(p)
	end
	for _, p in ipairs(laneBox("Borde_Posterior_D", lane, backU0, TOTAL_LENGTH, 0, backHalf, wallY, WALL_HEIGHT, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, invisibleFolder)) do
		makeInvisibleWall(p)
	end

	-- Dummies de entrenamiento: justo afuera de la salida trasera de la ciudad, en la franja 1
	local dummyFolder = newFolder("DummySpawns", folder)
	for i, v in ipairs({ -70, 70 }) do
		local pos = lanePos(lane, CITY_SIZE + 60, v, FLOOR_TOP + 2)
		local marker = newMarker("DummySpawn_" .. i, pos, dummyFolder)
		marker:SetAttribute("DummyName", string.format("Dummy %s %d", def.Display, i))
		CollectionService:AddTag(marker, "DummySpawnPoint")
	end
end

---------------------------------------------------------------------
-- ARENA CENTRAL Y PUENTES
---------------------------------------------------------------------
local function buildArena(lanes: { Lane }, map: Folder)
	local arenaFolder = newFolder("Arena_Central", map)

	local arena = newPart(
		"Coliseo_Central", Vector3.new(ARENA_SIZE, FLOOR_THICKNESS, ARENA_SIZE), CFrame.new(0, FLOOR_Y, 0),
		Color3.fromRGB(70, 70, 80), Enum.Material.Concrete, arenaFolder
	)
	CollectionService:AddTag(arena, "ZoneBoss")
	CollectionService:AddTag(arena, "ZonePvP") -- v6: único lugar donde hay PvP entre naciones
	addLabel(arena, "Arena Central - Evento de Facciones", 60, 420, 22)

	-- Decoración (sin colisión, apenas sobre el piso)
	local function disk(name: string, diameter: number, color: Color3, transparency: number)
		local d = newPart(
			name, Vector3.new(0.2, diameter, diameter),
			CFrame.new(0, FLOOR_TOP + 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color, Enum.Material.Neon, arenaFolder
		)
		d.Shape = Enum.PartType.Cylinder
		d.CanCollide = false
		d.CanQuery = false
		d.Transparency = transparency
		d.CastShadow = false
	end
	disk("Deco_Anillo_Exterior", METIN_RING_RADIUS * 2 + 120, Color3.fromRGB(90, 90, 110), 0.7)
	disk("Deco_Anillo_Medio", METIN_RING_RADIUS * 2 - 120, Color3.fromRGB(70, 70, 85), 0.6)
	disk("Deco_Plataforma_Boss", 260, Color3.fromRGB(190, 50, 50), 0.35)

	-- Marcadores de eventos
	local spawnFolder = newFolder("Arena_Spawns", arenaFolder)
	local boss = newMarker("WorldBossSpawn", Vector3.new(0, FLOOR_TOP + 3, 0), spawnFolder)
	CollectionService:AddTag(boss, "WorldBossSpawn")
	for i = 1, METIN_COUNT do
		local angle = math.rad((i - 1) * (360 / METIN_COUNT) + 360 / METIN_COUNT / 2)
		local pos = Vector3.new(math.cos(angle) * METIN_RING_RADIUS, FLOOR_TOP + 3, math.sin(angle) * METIN_RING_RADIUS)
		local marker = newMarker("MetinStoneSpawn_" .. i, pos, spawnFolder)
		marker:SetAttribute("Index", i)
		CollectionService:AddTag(marker, "MetinStoneSpawn")
	end

	-- Compuertas de la arena: una por puente, ancho ajustado al ángulo de llegada
	local gates: { Gate } = {}
	for _, lane in ipairs(lanes) do
		local edge = lane.Out * lane.Hit
		local dominant = math.max(math.abs(lane.Out.X), math.abs(lane.Out.Z))
		local width = BRIDGE_WIDTH / dominant + GATE_MARGIN
		if math.abs(lane.Out.X) >= math.abs(lane.Out.Z) then
			table.insert(gates, { Side = if lane.Out.X > 0 then "PX" else "NX", Offset = edge.Z, Width = width, Group = EVENT_GROUP })
		else
			table.insert(gates, { Side = if lane.Out.Z > 0 then "PZ" else "NZ", Offset = edge.X, Width = width, Group = EVENT_GROUP })
		end
	end
	local wallFolder = newFolder("Barreras_Arena", arenaFolder)
	buildArenaBarrier(Vector3.new(0, 0, 0), ARENA_HALF, FLOOR_TOP, gates, Color3.fromRGB(255, 80, 80), wallFolder)

	-- Puentes de evento (ocultos y sin colisión hasta que se abren)
	local bridgeFolder = newFolder(EVENT_GROUP, map)
	local bridgeLength = BRIDGE_LENGTH + BRIDGE_ARENA_OVERLAP
	for _, lane in ipairs(lanes) do
		-- Desde el portón de la ciudad (lane.Start) hacia el centro; se mete 60 studs bajo el piso de la arena
		local mid = lane.Start - lane.Dir * (bridgeLength / 2)
		local center = Vector3.new(mid.X, FLOOR_Y - 0.05, mid.Z)
		local bridge = newPart(
			"Bridge_" .. lane.Def.Id .. "_Arena",
			Vector3.new(BRIDGE_WIDTH, FLOOR_THICKNESS, bridgeLength),
			CFrame.lookAt(center, center + lane.Dir),
			Color3.fromRGB(118, 100, 84), Enum.Material.Slate, bridgeFolder
		)
		bridge.Transparency = 1
		bridge.CanCollide = false
		bridge.CanQuery = false
		bridge:SetAttribute("Biome", lane.Def.Id)
	end
end

---------------------------------------------------------------------
-- MAPA COMPLETO
---------------------------------------------------------------------
local function build(): Folder
	Workspace:SetAttribute("MapBuildCount", ((Workspace:GetAttribute("MapBuildCount") :: number?) or 0) + 1)
	local existing = Workspace:FindFirstChild(MAP_NAME)
	if existing then
		existing:Destroy()
	end

	local map = Instance.new("Folder")
	map.Name = MAP_NAME

	-- Océano en baldosas (una parte no puede medir más de 2048)
	local oceanFolder = newFolder("Oceano", map)
	local firstTile = -(OCEAN_TILES_PER_SIDE - 1) / 2
	for ix = 0, OCEAN_TILES_PER_SIDE - 1 do
		for iz = 0, OCEAN_TILES_PER_SIDE - 1 do
			newPart(
				string.format("Oceano_%d_%d", ix + 1, iz + 1),
				Vector3.new(OCEAN_TILE, 6, OCEAN_TILE),
				CFrame.new((firstTile + ix) * OCEAN_TILE, OCEAN_Y, (firstTile + iz) * OCEAN_TILE),
				Color3.fromRGB(20, 80, 150), Enum.Material.SmoothPlastic, oceanFolder
			)
		end
	end

	local lanes: { Lane } = {}
	for _, def in ipairs(BIOMES) do
		table.insert(lanes, computeLane(def))
	end

	for _, lane in ipairs(lanes) do
		buildLane(lane, map)
	end
	buildArena(lanes, map)

	map.Parent = Workspace
	return map
end

---------------------------------------------------------------------
-- UTILIDADES DE JUGADOR
---------------------------------------------------------------------
local function getMap(): Instance?
	return Workspace:FindFirstChild(MAP_NAME)
end

local function factionOf(player: Player): string
	return normalizeFaction(player:GetAttribute("Faction")) or DEFAULT_FACTION
end

local function getSpawnPart(faction: string): SpawnLocation?
	local map = getMap()
	local biomeId = FACTION_TO_BIOME[faction]
	local biome = if map and biomeId then map:FindFirstChild(biomeId) else nil
	local spawn = if biome then biome:FindFirstChild("Spawn_" .. (biomeId :: string)) else nil
	if spawn and spawn:IsA("SpawnLocation") then
		return spawn
	end
	return nil
end

local function playerCollisionGroup(player: Player): string
	local faction = normalizeFaction(player:GetAttribute("Faction"))
	if faction then
		return "Player_" .. faction
	end
	return "Default"
end

local function applyGroupToCharacter(player: Player, character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = playerCollisionGroup(player)
		end
	end
end

local lastFaction: { [Player]: string } = {}

local function sendToSanctuary(player: Player)
	local spawn = getSpawnPart(factionOf(player))
	local character = player.Character
	if spawn and character then
		character:PivotTo(spawn.CFrame + Vector3.new(0, 4, 0))
	end
end

local function hookPlayer(player: Player)
	local function onCharacter(character: Model)
		applyGroupToCharacter(player, character)
		character.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("BasePart") then
				d.CollisionGroup = playerCollisionGroup(player)
			end
		end)
	end

	local function updateRespawn()
		local spawn = getSpawnPart(factionOf(player))
		if spawn then
			player.RespawnLocation = spawn
		end
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
	updateRespawn()
	lastFaction[player] = normalizeFaction(player:GetAttribute("Faction")) or ""

	player:GetAttributeChangedSignal("Faction"):Connect(function()
		local faction = normalizeFaction(player:GetAttribute("Faction")) or ""
		if faction == lastFaction[player] then
			return
		end
		lastFaction[player] = faction
		updateRespawn()
		if player.Character then
			applyGroupToCharacter(player, player.Character)
		end
		if TELEPORT_ON_FACTION_CHANGE and faction ~= "" then
			sendToSanctuary(player)
		end
	end)
end

---------------------------------------------------------------------
-- API PÚBLICA
---------------------------------------------------------------------
local MapBuilder = {}

local GROUP_ALIASES: { [string]: string } = {
	WorldBoss_Bridges = EVENT_GROUP,
	Metin_Bridges = EVENT_GROUP,
}

-- Abre/cierra los puentes de un grupo junto con sus compuertas
function MapBuilder.SetBridges(groupName: string, active: boolean)
	local map = getMap()
	if not map then
		return
	end
	groupName = GROUP_ALIASES[groupName] or groupName
	if groupName == EVENT_GROUP then
		-- el diseño por nación (barandas, arco, barreras) lo hace ArenaGate; así el temporizador y /arena dan el mismo puente
		local svc = game:GetService("ServerScriptService"):FindFirstChild("Services")
		local gateMod = svc and svc:FindFirstChild("ArenaGate")
		if gateMod and gateMod:IsA("ModuleScript") then
			local ok, gate = pcall(require, gateMod)
			if ok and type(gate) == "table" and gate.SetOpen then
				gate.SetOpen(active)
				return
			end
		end
	end
	local group = map:FindFirstChild(groupName)
	if not group then
		warn("[ProjectBootstrapper] Grupo de puentes no encontrado: " .. groupName)
		return
	end

	for _, child in ipairs(group:GetChildren()) do
		if child:IsA("BasePart") then
			if active then
				child.CanCollide = child:GetAttribute("NoCollide") ~= true
				child.CanQuery = true
				TweenService:Create(child, TweenInfo.new(1.5), { Transparency = BRIDGE_VISIBLE_TRANSPARENCY }):Play()
			else
				local tween = TweenService:Create(child, TweenInfo.new(1.5), { Transparency = 1 })
				tween.Completed:Once(function()
					if child.Transparency >= 1 then
						child.CanCollide = false
						child.CanQuery = false
					end
				end)
				tween:Play()
			end
		end
	end

	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("GateGroup") == groupName then
			d.CanCollide = not active
			TweenService:Create(d, TweenInfo.new(1), { Transparency = if active then 1 else WALL_TRANSPARENCY }):Play()
		end
	end
end

-- ¿Está la posición sobre la arena o sobre algún puente de evento?
local function isInEventArea(position: Vector3): boolean
	local margin = 6
	if math.abs(position.X) <= ARENA_HALF + margin and math.abs(position.Z) <= ARENA_HALF + margin then
		return true
	end
	local map = getMap()
	local group = if map then map:FindFirstChild(EVENT_GROUP) else nil
	if group then
		for _, bridge in ipairs(group:GetChildren()) do
			if bridge:IsA("BasePart") then
				local localPos = bridge.CFrame:PointToObjectSpace(position)
				if math.abs(localPos.X) <= bridge.Size.X / 2 + margin and math.abs(localPos.Z) <= bridge.Size.Z / 2 + margin then
					return true
				end
			end
		end
	end
	return false
end

-- Lleva a su ciudad a los jugadores que estén en la arena o en los puentes
function MapBuilder.EjectPlayersFromEventArea()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") and isInEventArea(root.Position) then
			sendToSanctuary(player)
		end
	end
end

-- Abre o cierra el evento (puentes + compuertas) y actualiza los atributos del HUD
function MapBuilder.SetEventOpen(open: boolean)
	MapBuilder.SetBridges(EVENT_GROUP, open)
	Workspace:SetAttribute("EventState", if open then "Open" else "Closed")
	if open then
		Workspace:SetAttribute("EventCountdown", EVENT_OPEN_SECONDS)
	else
		Workspace:SetAttribute("EventCountdown", EVENT_INTERVAL_SECONDS)
		MapBuilder.EjectPlayersFromEventArea()
	end
end

-- CFrame del NPCSpawnPoint de un slot (posición a la altura de los pies, mirando al frente de la tienda)
function MapBuilder.GetNpcSlotCFrame(biomeId: string, slot: number): CFrame?
	local map = getMap()
	local biome = if map then map:FindFirstChild(biomeId) else nil
	if biome then
		for _, d in ipairs(biome:GetDescendants()) do
			if d.Name == "NPCSpawnPoint" and d:IsA("BasePart") and d:GetAttribute("Slot") == slot then
				return d.CFrame
			end
		end
	end
	return nil
end

-- Coloca un modelo NPC en su NPCSpawnPoint, con los pies sobre el piso
function MapBuilder.PlaceNPC(model: Model, biomeId: string, slot: number): boolean
	local target = MapBuilder.GetNpcSlotCFrame(biomeId, slot)
	if not target then
		warn(string.format("[ProjectBootstrapper] NPCSpawnPoint no encontrado: %s #%d", biomeId, slot))
		return false
	end
	local pivot = model:GetPivot()
	local boxCf, boxSize = model:GetBoundingBox()
	local feetOffset = pivot.Position.Y - (boxCf.Position.Y - boxSize.Y / 2)
	model:PivotTo(target + Vector3.new(0, feetOffset, 0))
	return true
end

---------------------------------------------------------------------
-- ARRANQUE
---------------------------------------------------------------------
setupCollisionGroups()
build()
-- Marca para los demás servicios (CityStyler, ArenaStyler, MobService, WorldReadyService): el mapa NUEVO ya existe completo.
-- Así ninguno estiliza un mapa viejo guardado en el lugar ni arranca antes de tiempo.
Workspace:SetAttribute("MapBuilt", true)

-- NPCs con tag "MapNPC" + atributos Biome/Slot se acomodan solos
local function snapNpc(inst: Instance)
	if inst:IsA("Model") then
		local biome = inst:GetAttribute("Biome")
		local slot = inst:GetAttribute("Slot")
		if typeof(biome) == "string" and typeof(slot) == "number" then
			MapBuilder.PlaceNPC(inst, biome, slot)
		end
	end
end
CollectionService:GetInstanceAddedSignal("MapNPC"):Connect(snapNpc)
for _, inst in ipairs(CollectionService:GetTagged("MapNPC")) do
	snapNpc(inst)
end

-- Jugadores (los que ya estaban y los que entren después)
Players.PlayerAdded:Connect(hookPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end
Players.PlayerRemoving:Connect(function(player: Player)
	lastFaction[player] = nil
end)

-- Temporizador de evento
Workspace:SetAttribute("EventState", "Closed")
Workspace:SetAttribute("EventCountdown", EVENT_INTERVAL_SECONDS)
if AUTO_EVENT_TIMER then
	task.spawn(function()
		while true do
			task.wait(1)
			local remaining = (Workspace:GetAttribute("EventCountdown") :: number) - 1
			if remaining <= 0 then
				local isOpen = Workspace:GetAttribute("EventState") == "Open"
				MapBuilder.SetEventOpen(not isOpen)
			else
				Workspace:SetAttribute("EventCountdown", remaining)
			end
		end
	end)
end

-- v6: permite abrir/cerrar el evento desde otro script o desde el comando /arena de pruebas:
--   workspace:SetAttribute("EventForce", "Open")  /  "Closed"
Workspace:GetAttributeChangedSignal("EventForce"):Connect(function()
	local v = Workspace:GetAttribute("EventForce")
	if v == "Open" or v == "Closed" then
		Workspace:SetAttribute("EventForce", nil)
		MapBuilder.SetEventOpen(v == "Open")
	end
end)

print("[ProjectBootstrapper] Mapa " .. MAP_NAME .. " construido: 3 ciudades 800x800 con abanico de 4 franjas, puentes de evento y Arena Central 1500x1500.")

return MapBuilder