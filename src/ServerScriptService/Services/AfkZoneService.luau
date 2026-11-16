--!strict
--[[
    AfkZoneService (ModuleScript) -> ServerScriptService > Services > AfkZoneService
    CAMPO DE ENTRENAMIENTO (zona de farmeo AFK): un portal en la plaza de cada ciudad, junto al punto de aparición, lleva a una CÁPSULA
    segura (un círculo cerrado, lejos del mapa) donde los monstruos de tu franja salen de unas puertas y caminan hacia ti. El Auto-farm
    (AfkClient lo enciende al llegar) pelea solo. Menos XP y botín que el farmeo normal, con un tope de horas por día. Sin PvP.

    ARQUITECTURA: CÁPSULAS PREFABRICADAS. Al arrancar el servidor se construyen PODS_PER_THEME cápsulas por facción (tema distinto),
    una sola vez (no se construye nada al entrar: con StreamingEnabled apagado cada pieza nueva viaja a TODOS los clientes). Una sesión
    (solo o grupo de hasta MAX_GROUP) ocupa una cápsula libre de SU facción; al terminar, la cápsula se libera.

    SOLO / GRUPO
      - Solo: cualquiera puede entrar solo (aunque esté en un grupo).
      - En grupo: SOLO EL LÍDER pulsa "Entrar en grupo". A cada miembro le sale una ventana con [Entrar] [Salir del grupo] y ASK_SECONDS segundos.
        "Salir del grupo" lo saca del grupo en el acto; sin responder se queda en el grupo pero no entra. El líder ve quién aceptó y puede
        "Entrar ya". Entran el líder y los que aceptaron (máx. MAX_GROUP). Quien no entró puede unirse después ("Unirse a mi grupo") si hay cupo.
      - La franja de la cápsula = la del miembro de MENOR nivel (nadie queda con monstruos de otra liga).

    RECOMPENSAS (perillas en CONFIG): XP_MULT por baja (atributo XpMult del monstruo, ya lo lee RewardService) y LOOT_MULT al oro y a las
    probabilidades de botín (atributo del jugador AfkLootMult, que lee LootService). DAILY_SECONDS = tiempo máximo por día (perfil, sección "Afk").
      Más jugadores = más monstruos vivos y +GROUP_XP_BONUS de XP por jugador extra (la XP se reparte entre quienes pegan).

    SALIDA: botón Salir (HUD), portal de salida de la cápsula, se agota el tiempo del día, mueres (reapareces en la ciudad) o llevas
    IDLE_EJECT segundos sin ninguna baja (no peleas: no se ocupa una cápsula). Traslados: DungeonService.MoveTo (el mismo traslado en dos tiempos de las cuevas).

    ATRIBUTOS que publica (los lee AfkClient): Workspace: AfkXpPct, AfkLootPct, AfkDaily, AfkMaxGroup, AfkAsk.
      Jugador: AfkLeft (segundos que le quedan hoy), InAfk (franja de la sesión; nil = fuera), AfkKills, AfkStart (GetServerTimeNow), AfkLootMult.
    REMOTO "Afk": cliente -> servidor ("Solo") ("Group") ("Answer", "yes"|"leave") ("Start") ("Cancel") ("Join") ("Leave")
                  servidor -> cliente ("Open", info) ("Ask", {...}) ("AskClose") ("Wait", {...}) ("WaitClose") ("Close")
    Conexión: require(Services:WaitForChild("AfkZoneService")) en GameServerMain, DESPUÉS de DungeonService. Necesita FactionZoneService del 6.104
      (a más de 20.000 studs no hay territorio) y PartyService con Remove / LeaderOf.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local LootTables = require(ReplicatedStorage.Modules.LootTables)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local LevelService = require(Services.LevelService)
local PartyService = require(Services.PartyService)
local MobService = require(Services.Mobs.MobService)
local DungeonService = require(Services.DungeonService)

---------------------------------------------------------------------
-- AJUSTES
---------------------------------------------------------------------
local CONFIG = {
	-- RECOMPENSAS (las perillas principales)
	XP_MULT = 0.5, -- XP de cada baja respecto al farmeo normal
	LOOT_MULT = 0.5, -- oro y probabilidad de cada botín respecto al farmeo normal (LootService)
	GROUP_XP_BONUS = 0.15, -- por jugador extra: sube la XP por baja (se reparte entre los que pegan)
	DAILY_SECONDS = 8 * 3600, -- tiempo máximo por día dentro del Campo
	IDLE_EJECT = 600, -- segundos sin ninguna baja en la sesión: se saca a todos
	-- MONSTRUOS
	ALIVE_BASE = 5, -- monstruos vivos a la vez (1 jugador)
	ALIVE_PER_EXTRA = 2, -- más por cada jugador extra
	SPAWN_EVERY = 3.5, -- segundos entre apariciones (1 jugador; con grupo es más rápido)
	MOB_DMG = 0.5, -- multiplicador del daño de los monstruos (para que el personaje aguante horas)
	MOB_HP = 0.8, -- multiplicador de su vida
	GLOBAL_MOB_CAP = 350, -- si ya hay tantos monstruos en el servidor, no aparecen más aquí
	HEARTH_REGEN = 0.02, -- fracción de vida máxima que cura la hoguera por segundo (a quien esté cerca del centro)
	-- GRUPO
	MAX_GROUP = 5,
	ASK_SECONDS = 20,
	-- CÁPSULAS
	PODS_PER_THEME = 8,
	ORIGIN = Vector3.new(-40000, 500, -40000), -- lejos del mapa, de las cuevas (-40000,+40000) y de las casas VIP (+40000)
	POD_SPACING = 200,
	POD_RADIUS = 60,
	WALL_SEGMENTS = 20,
	WALL_HEIGHT = 30,
	DOORS = 7,
	DOOR_RADIUS = 54,
	BUILD_PACE = 150, -- piezas por fotograma al construir
	-- PORTAL
	PORTAL_SIDE = 34, -- studs al costado del punto de aparición (spawn) de la ciudad
	PORTAL_REACH = 45, -- distancia máxima al portal para pedir entrar
	DEBUG = true,
}

local BIOME_OF: { [string]: string } = {
	Saiyan = "Imperio_Saiyan",
	Shinobi = "Alianza_Shinobi",
	Pirate = "Flota_Pirata",
	Shinigami = "Corte_Shinigami",
}
local OUT_DIR: { [string]: Vector3 } = { -- sentido en que se aleja cada ciudad de la arena (ProjectBootstrapper)
	Saiyan = Vector3.new(0, 0, -1),
	Shinobi = Vector3.new(-1, 0, 0),
	Pirate = Vector3.new(1, 0, 0),
	Shinigami = Vector3.new(0, 0, 1),
}
local THEME_ORDER = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }

type Theme = {
	Title: string,
	Floor: Color3,
	FloorMat: Enum.Material,
	Wall: Color3,
	WallMat: Enum.Material,
	Accent: Color3,
	Prop: Color3,
	PropMat: Enum.Material,
	Shape: string,
}
local THEMES: { [string]: Theme } = {
	Saiyan = { Title = "Cámara de Gravedad", Floor = Color3.fromRGB(92, 70, 62), FloorMat = Enum.Material.Basalt, Wall = Color3.fromRGB(60, 52, 54), WallMat = Enum.Material.Slate, Accent = Color3.fromRGB(255, 150, 60), Prop = Color3.fromRGB(116, 94, 84), PropMat = Enum.Material.Rock, Shape = "rock" },
	Shinobi = { Title = "Claro de Entrenamiento", Floor = Color3.fromRGB(78, 120, 66), FloorMat = Enum.Material.Grass, Wall = Color3.fromRGB(104, 76, 48), WallMat = Enum.Material.Wood, Accent = Color3.fromRGB(120, 220, 120), Prop = Color3.fromRGB(64, 132, 66), PropMat = Enum.Material.Grass, Shape = "tree" },
	Pirate = { Title = "Isla de Entrenamiento", Floor = Color3.fromRGB(214, 190, 138), FloorMat = Enum.Material.Sand, Wall = Color3.fromRGB(122, 86, 52), WallMat = Enum.Material.WoodPlanks, Accent = Color3.fromRGB(70, 200, 230), Prop = Color3.fromRGB(130, 92, 56), PropMat = Enum.Material.Wood, Shape = "barrel" },
	Shinigami = { Title = "Valle de Almas", Floor = Color3.fromRGB(60, 62, 84), FloorMat = Enum.Material.Slate, Wall = Color3.fromRGB(40, 40, 58), WallMat = Enum.Material.Basalt, Accent = Color3.fromRGB(170, 120, 255), Prop = Color3.fromRGB(200, 210, 240), PropMat = Enum.Material.Marble, Shape = "lantern" },
}

---------------------------------------------------------------------
-- TIPOS Y ESTADO
---------------------------------------------------------------------
type Pod = { Id: string, Theme: string, Center: Vector3, Doors: { Vector3 }, ExitCF: CFrame, Busy: boolean }
type Session = {
	Id: number,
	Pod: Pod,
	Faction: string,
	Tier: number,
	Level: number,
	Members: { Player },
	Mobs: { Model },
	Kills: number,
	StartedAt: number,
	LastKill: number,
	NextSpawn: number,
	Closed: boolean,
}
type Req = {
	Leader: Player,
	Order: { Player },
	State: { [Player]: string }, -- wait | yes | left | stay | busy
	Deadline: number, -- GetServerTimeNow()
	Done: boolean,
}

local Remote = Net.Get("Afk")
local NotifyRemote = Net.Get("Notify")
local pods: { [string]: { Pod } } = {}
local portalPos: { [string]: Vector3 } = {}
local portalExit: { [string]: CFrame } = {}
local sessions: { [number]: Session } = {}
local sessionOf: { [Player]: Session } = {}
local reqOf: { [Player]: Req } = {} -- líder y miembros -> petición de grupo en curso
local diedConn: { [Player]: RBXScriptConnection } = {}
local lastAct: { [Player]: number } = {}
local sessionCounter = 0
local rng = Random.new()

local function notify(p: Player, text: string)
	if p.Parent then
		NotifyRemote:FireClient(p, text)
	end
end

local function rootOf(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function factionOf(p: Player): string
	local f = PlayerClass.Get(p).Faction
	return if typeof(f) == "string" and THEMES[f] then f else "Saiyan"
end

local function dprint(...: any)
	if CONFIG.DEBUG then
		print("[AfkZoneService]", ...)
	end
end

---------------------------------------------------------------------
-- TIEMPO DIARIO (perfil, sección "Afk")
---------------------------------------------------------------------
type AfkData = { Day: string, Seconds: number }
local data: { [Player]: AfkData } = {}

local function today(): string
	return os.date("!%Y-%m-%d", os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600) :: string
end

local function dataOf(p: Player): AfkData?
	local d = data[p]
	if not d then
		return nil
	end
	local t = today()
	if d.Day ~= t then
		d.Day, d.Seconds = t, 0
	end
	return d
end

local function leftOf(p: Player): number
	local d = dataOf(p)
	if not d then
		return 0
	end
	return math.max(0, CONFIG.DAILY_SECONDS - d.Seconds)
end

local function publishLeft(p: Player)
	p:SetAttribute("AfkLeft", math.floor(leftOf(p)))
end

PlayerData.RegisterSerializer("Afk", function(p: Player): any?
	local d = data[p]
	if not d then
		return nil
	end
	return { Day = d.Day, Seconds = math.floor(d.Seconds) }
end)

local function loadData(p: Player)
	local saved = PlayerData.WaitForData(p)
	if not saved or p.Parent == nil then
		return
	end
	local d: AfkData = { Day = today(), Seconds = 0 }
	local raw: any = (saved :: any).Afk
	if typeof(raw) == "table" and typeof(raw.Day) == "string" and typeof(raw.Seconds) == "number" then
		d.Day = raw.Day
		d.Seconds = math.max(0, raw.Seconds)
	end
	data[p] = d
	publishLeft(p)
end

PlayerData.Releasing:Connect(function(p: Player)
	data[p] = nil
end)

---------------------------------------------------------------------
-- MONSTRUOS POR FRANJA
---------------------------------------------------------------------
local normals: { [string]: { [number]: { MobCatalog.MobDef } } } = {}
local stripMin: { [string]: { [number]: number } } = {}
local FALLBACK_MIN = { 1, 751, 1501, 2251 }

do
	for _, f in ipairs(THEME_ORDER) do
		normals[f], stripMin[f] = {}, {}
		for s = 1, 4 do
			local list: { MobCatalog.MobDef } = {}
			for _, d in ipairs(MobCatalog.All :: { MobCatalog.MobDef }) do
				if d.Faction == f and d.Strip == s and not d.Boss then
					table.insert(list, d)
				end
			end
			table.sort(list, function(a, b)
				return a.MinLevel < b.MinLevel
			end)
			normals[f][s] = list
			stripMin[f][s] = if #list > 0 then list[1].MinLevel else FALLBACK_MIN[s]
		end
	end
end

local function tierOf(faction: string, level: number): number
	local tier = 1
	for s = 1, 4 do
		if #normals[faction][s] > 0 and level >= stripMin[faction][s] then
			tier = s
		end
	end
	return tier
end

local function defFor(faction: string, tier: number, level: number): MobCatalog.MobDef?
	local list = normals[faction][tier]
	if not list or #list == 0 then
		return nil
	end
	local idx = #list
	for i, d in ipairs(list) do
		if level <= d.MaxLevel then
			idx = i
			break
		end
	end
	if idx > 1 and rng:NextNumber() < 0.25 then
		idx -= 1 -- algo de variedad: a veces el monstruo del tramo anterior
	end
	return list[idx]
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN DE LAS CÁPSULAS
---------------------------------------------------------------------
local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.CanCollide = collide
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function disc(parent: Instance, name: string, diameter: number, thick: number, center: Vector3, color: Color3, mat: Enum.Material, collide: boolean): Part
	local p = mk(parent, name, Vector3.new(thick, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2), color, mat, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function glow(p: BasePart, transparency: number)
	p.Transparency = transparency
	p.CastShadow = false
end

local function addLight(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

local function leaveSession(p: Player, teleport: boolean, reason: string?) end -- (se define más abajo)

local builtParts = 0
local function pace()
	builtParts += 1
	if builtParts % CONFIG.BUILD_PACE == 0 then
		task.wait()
	end
end

local function buildProp(folder: Folder, theme: Theme, pos: Vector3, rotY: number)
	local cf = CFrame.new(pos) * CFrame.Angles(0, rotY, 0)
	if theme.Shape == "tree" then
		mk(folder, "Tronco", Vector3.new(2.4, 11, 2.4), cf * CFrame.new(0, 5.5, 0), Color3.fromRGB(96, 68, 44), Enum.Material.Wood, true)
		local crown = mk(folder, "Copa", Vector3.new(11, 9, 11), cf * CFrame.new(0, 13, 0), theme.Prop, theme.PropMat, false)
		crown.Shape = Enum.PartType.Ball
		pace()
	elseif theme.Shape == "barrel" then
		local b = mk(folder, "Barril", Vector3.new(5, 4, 4), cf * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0, math.pi / 2), theme.Prop, theme.PropMat, true)
		b.Shape = Enum.PartType.Cylinder
	elseif theme.Shape == "lantern" then
		mk(folder, "Poste", Vector3.new(1, 9, 1), cf * CFrame.new(0, 4.5, 0), theme.Wall, Enum.Material.Basalt, true)
		local g = mk(folder, "Farol", Vector3.new(2.6, 2.6, 2.6), cf * CFrame.new(0, 10, 0), theme.Accent, Enum.Material.Neon, false)
		g.Shape = Enum.PartType.Ball
		addLight(g, theme.Accent, 22, 1.2)
		pace()
	else -- rock
		local r = mk(folder, "Roca", Vector3.new(7, 8, 6), cf * CFrame.new(0, 3.5, 0) * CFrame.Angles(0.2, 0.4, 0.15), theme.Prop, theme.PropMat, true)
		r.Shape = Enum.PartType.Block
	end
end

local function buildPod(themeName: string, index: number, center: Vector3): Pod
	local theme = THEMES[themeName]
	local R = CONFIG.POD_RADIUS
	local folder = Instance.new("Folder")
	folder.Name = string.format("Capsula_%s_%d", themeName, index)
	folder.Parent = Workspace:FindFirstChild("AfkField")
	-- suelo, anillo y plataforma central
	disc(folder, "Suelo", (R + 4) * 2, 2, center - Vector3.new(0, 1, 0), theme.Floor, theme.FloorMat, true)
	local ring = disc(folder, "Anillo", 80, 0.2, center + Vector3.new(0, 0.1, 0), theme.Accent, Enum.Material.Neon, false)
	glow(ring, 0.82)
	disc(folder, "Plataforma", 36, 0.6, center + Vector3.new(0, 0.3, 0), theme.Floor:Lerp(Color3.new(1, 1, 1), 0.18), Enum.Material.Marble, true)
	-- hoguera (cura a quien está cerca)
	local fireBase = disc(folder, "HogueraBase", 4, 0.8, center + Vector3.new(0, 1, 0), Color3.fromRGB(60, 52, 48), Enum.Material.Slate, true)
	local flame = mk(folder, "Llama", Vector3.new(2.4, 2.4, 2.4), CFrame.new(center + Vector3.new(0, 2.6, 0)), theme.Accent, Enum.Material.Neon, false)
	flame.Shape = Enum.PartType.Ball
	addLight(flame, theme.Accent, 30, 1.6)
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 4
	fire.Color = theme.Accent
	fire.SecondaryColor = Color3.fromRGB(255, 230, 160)
	fire.Parent = fireBase
	-- muro circular
	local N = CONFIG.WALL_SEGMENTS
	local segLen = 2 * math.pi * R / N + 1.2
	for i = 0, N - 1 do
		local a = i / N * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * R, CONFIG.WALL_HEIGHT / 2, math.sin(a) * R)
		mk(folder, "Muro", Vector3.new(segLen, CONFIG.WALL_HEIGHT, 3), CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)), theme.Wall, theme.WallMat, true)
		pace()
	end
	-- puertas de aparición: repartidas por la circunferencia, saltando el lado de la salida (ángulo π/2)
	local exitAngle = math.pi / 2
	local doors: { Vector3 } = {}
	for i = 1, CONFIG.DOORS do
		local a = exitAngle + i / (CONFIG.DOORS + 1) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pos = center + dir * (R - 1.5)
		local base = CFrame.lookAt(pos, center)
		for _, sx in ipairs({ -1, 1 }) do
			mk(folder, "PilarPuerta", Vector3.new(2.6, 11, 2.6), base * CFrame.new(sx * 4.2, 5.5, 0), theme.Wall, theme.WallMat, true)
		end
		local lintel = mk(folder, "DinteL", Vector3.new(11, 2.4, 2.6), base * CFrame.new(0, 11.6, 0), theme.Accent, Enum.Material.Neon, false)
		glow(lintel, 0.35)
		table.insert(doors, center + dir * (R - 7) + Vector3.new(0, 3, 0))
		pace()
	end
	-- adornos entre puertas (cerca del muro, nunca en el camino al centro)
	local theta0 = rng:NextNumber() * math.pi * 2
	for i = 1, 6 do
		local a = theta0 + i / 6 * math.pi * 2 + (rng:NextNumber() - 0.5) * 0.25
		buildProp(folder, theme, center + Vector3.new(math.cos(a) * 49, 0, math.sin(a) * 49), rng:NextNumber() * math.pi * 2)
	end
	-- portal de salida
	local exitDir = Vector3.new(math.cos(exitAngle), 0, math.sin(exitAngle))
	local epos = center + exitDir * (R - 8)
	local ecf = CFrame.lookAt(epos, center)
	for _, sx in ipairs({ -1, 1 }) do
		mk(folder, "PilarSalida", Vector3.new(3, 12, 3), ecf * CFrame.new(sx * 6, 6, 0), theme.Wall, theme.WallMat, true)
	end
	mk(folder, "VigaSalida", Vector3.new(15, 2.6, 3), ecf * CFrame.new(0, 13, 0), theme.Wall, theme.WallMat, true)
	local mem = mk(folder, "PortalSalida", Vector3.new(9, 11, 0.4), ecf * CFrame.new(0, 5.6, 0), Color3.fromRGB(90, 220, 160), Enum.Material.Neon, false)
	glow(mem, 0.4)
	addLight(mem, Color3.fromRGB(90, 220, 160), 26, 1.6)
	local pod: Pod = { Id = folder.Name, Theme = themeName, Center = center, Doors = doors, ExitCF = ecf, Busy = false }
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Salir del Campo"
	pp.ObjectText = "Volver a la ciudad"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.5
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = mem
	pp.Triggered:Connect(function(p: Player)
		if sessionOf[p] and sessionOf[p].Pod == pod then
			leaveSession(p, true, nil)
		end
	end)
	pace()
	return pod
end

local function buildAllPods()
	local t0 = os.clock()
	local field = Instance.new("Folder")
	field.Name = "AfkField"
	field.Parent = Workspace
	for ti, themeName in ipairs(THEME_ORDER) do
		pods[themeName] = {}
		for i = 1, CONFIG.PODS_PER_THEME do
			local center = CONFIG.ORIGIN + Vector3.new((i - 1) * CONFIG.POD_SPACING, 0, (ti - 1) * CONFIG.POD_SPACING)
			table.insert(pods[themeName], buildPod(themeName, i, center))
		end
	end
	dprint(string.format("%d cápsulas construidas en %.2f s (%d piezas aprox.)", CONFIG.PODS_PER_THEME * #THEME_ORDER, os.clock() - t0, builtParts))
end

---------------------------------------------------------------------
-- PORTAL EN LA CIUDAD
---------------------------------------------------------------------
local openWindow: (Player) -> () = function(_p: Player) end -- (se define más abajo)

local function buildPortal(faction: string)
	local theme = THEMES[faction]
	local biomeId = BIOME_OF[faction]
	local sp: Instance? = nil
	for _ = 1, 120 do
		sp = Workspace:FindFirstChild("Spawn_" .. biomeId, true)
		if sp then
			break
		end
		task.wait(1)
	end
	if not (sp and sp:IsA("BasePart")) then
		warn("[AfkZoneService] no encontré el punto de aparición Spawn_" .. biomeId .. ": no hay portal AFK en la ciudad de " .. faction)
		return
	end
	local pad: BasePart = sp
	-- eje de la ciudad = dirección del punto de aparición respecto al centro del mapa (igual que FactionZoneService); el portal va al costado
	local horiz = Vector3.new(pad.Position.X, 0, pad.Position.Z)
	local out = if horiz.Magnitude > 1 then horiz.Unit else OUT_DIR[faction]
	local side = Vector3.new(-out.Z, 0, out.X)
	local floorY = pad.Position.Y - pad.Size.Y / 2
	local pos = Vector3.new(pad.Position.X, floorY, pad.Position.Z) + side * CONFIG.PORTAL_SIDE
	local look = Vector3.new(pad.Position.X, floorY, pad.Position.Z)
	local cf = CFrame.lookAt(pos, look)
	local model = Instance.new("Model")
	model.Name = "PortalAFK_" .. faction
	model.Parent = Workspace:FindFirstChild("AfkField")
	local stone = Color3.fromRGB(88, 82, 78)
	for _, sx in ipairs({ -1, 1 }) do
		mk(model, "Pilar", Vector3.new(4, 15, 4), cf * CFrame.new(sx * 9, 7.5, 0), stone, Enum.Material.Cobblestone, true)
		local rune = mk(model, "Runa", Vector3.new(0.6, 9, 0.4), cf * CFrame.new(sx * 9, 7.5, 2.1), theme.Accent, Enum.Material.Neon, false)
		glow(rune, 0.1)
	end
	mk(model, "Viga", Vector3.new(22, 3, 4), cf * CFrame.new(0, 16.5, 0), stone, Enum.Material.Cobblestone, true)
	local gem = mk(model, "Gema", Vector3.new(3, 3, 3), cf * CFrame.new(0, 20.5, 0), theme.Accent, Enum.Material.Neon, false)
	gem.Shape = Enum.PartType.Ball
	local mem = mk(model, "Portal", Vector3.new(14, 14, 0.5), cf * CFrame.new(0, 8, 0), theme.Accent, Enum.Material.Neon, false)
	glow(mem, 0.45)
	local base = disc(model, "Tarima", 26, 0.5, pos + Vector3.new(0, 0.25, 0), Color3.fromRGB(56, 52, 52), Enum.Material.Slate, false)
	base.CanCollide = false
	local ringL = disc(model, "Circulo", 22, 0.2, pos + Vector3.new(0, 0.55, 0), theme.Accent, Enum.Material.Neon, false)
	glow(ringL, 0.78)
	addLight(mem, theme.Accent, 36, 2.2)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(theme.Accent)
	emitter.LightEmission = 1
	emitter.Rate = 14
	emitter.Lifetime = NumberRange.new(1.5, 2.6)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = mem
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(300, 60)
	bb.StudsOffset = Vector3.new(0, 20, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.Parent = mem
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextWrapped = true
	label.TextColor3 = theme.Accent:Lerp(Color3.new(1, 1, 1), 0.5)
	label.TextStrokeTransparency = 0.4
	label.Text = "CAMPO DE ENTRENAMIENTO\nfarmeo AFK · solo o en grupo"
	label.Parent = bb
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Entrar"
	pp.ObjectText = "Campo de Entrenamiento (AFK)"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = mem
	pp.Triggered:Connect(function(p: Player)
		if factionOf(p) == faction then
			openWindow(p)
		else
			notify(p, "Este es el Campo de Entrenamiento de otra facción: usa el de tu ciudad")
		end
	end)
	portalPos[faction] = pos
	local exitPos = pos + (look - pos).Unit * 11 + Vector3.new(0, 3.5, 0)
	portalExit[faction] = CFrame.lookAt(exitPos, exitPos + (look - pos).Unit * 20)
	dprint(string.format("portal de %s en (%.0f, %.0f, %.0f) · a %d studs al costado de tu punto de aparición", faction, pos.X, pos.Y, pos.Z, CONFIG.PORTAL_SIDE))
end

local function nearPortal(p: Player): boolean
	local pos = portalPos[factionOf(p)]
	local r = rootOf(p)
	return pos ~= nil and r ~= nil and (r.Position - pos).Magnitude <= CONFIG.PORTAL_REACH
end

---------------------------------------------------------------------
-- SESIONES
---------------------------------------------------------------------
local function eligible(p: Player): (boolean, string?)
	if not p.Parent then
		return false, "no está conectado"
	end
	if not dataOf(p) then
		return false, "su perfil todavía está cargando"
	end
	if sessionOf[p] then
		return false, "ya está en el Campo"
	end
	if leftOf(p) <= 0 then
		return false, "ya usó sus " .. string.format("%d h", CONFIG.DAILY_SECONDS // 3600) .. " de hoy"
	end
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not rootOf(p) then
		return false, "está caído"
	end
	if p:GetAttribute("InDungeon") ~= nil or p:GetAttribute("DungeonTransit") ~= nil then
		return false, "está en una cueva o viajando"
	end
	return true, nil
end

local function freePod(faction: string): Pod?
	for _, pod in ipairs(pods[faction] or {}) do
		if not pod.Busy then
			return pod
		end
	end
	return nil
end

local function freeCount(faction: string): number
	local n = 0
	for _, pod in ipairs(pods[faction] or {}) do
		if not pod.Busy then
			n += 1
		end
	end
	return n
end

local function slotCF(pod: Pod, i: number, n: number): CFrame
	local a = (i - 1) / math.max(n, 1) * math.pi * 2 + math.pi / 2
	local pos = pod.Center + Vector3.new(math.cos(a) * 5, 3.6, math.sin(a) * 5)
	return CFrame.lookAt(pos, pos + Vector3.new(math.cos(a), 0, math.sin(a)) * 20)
end

local function addToSession(s: Session, p: Player, slot: number)
	table.insert(s.Members, p)
	sessionOf[p] = s
	p:SetAttribute("InAfk", s.Tier)
	p:SetAttribute("AfkLootMult", CONFIG.LOOT_MULT)
	p:SetAttribute("AfkKills", s.Kills)
	p:SetAttribute("AfkStart", Workspace:GetServerTimeNow())
	publishLeft(p)
	DungeonService.MoveTo(p, slotCF(s.Pod, slot, CONFIG.MAX_GROUP), "⚔️ Entrando al Campo de Entrenamiento…")
	-- si mueres, reapareces en la ciudad: la sesión termina para ti (sin teletransporte)
	local old = diedConn[p]
	if old then
		old:Disconnect()
	end
	diedConn[p] = p.CharacterAdded:Connect(function()
		if sessionOf[p] == s then
			leaveSession(p, false, "Caíste: la sesión del Campo terminó")
		end
	end)
end

local function startSession(members: { Player }, faction: string): Session?
	local pod = freePod(faction)
	if not pod then
		for _, m in ipairs(members) do
			notify(m, "Todas las cápsulas del Campo están ocupadas: prueba en un momento")
		end
		return nil
	end
	local level = math.huge
	for _, m in ipairs(members) do
		level = math.min(level, LevelService.GetLevel(m))
	end
	if level == math.huge then
		level = 1
	end
	sessionCounter += 1
	local now = os.clock()
	local s: Session = {
		Id = sessionCounter,
		Pod = pod,
		Faction = faction,
		Tier = tierOf(faction, level),
		Level = level,
		Members = {},
		Mobs = {},
		Kills = 0,
		StartedAt = now,
		LastKill = now,
		NextSpawn = now + 4, -- tiempo para que lleguen y se destape la pantalla
		Closed = false,
	}
	pod.Busy = true
	sessions[s.Id] = s
	for i, m in ipairs(members) do
		addToSession(s, m, i)
		notify(m, string.format("⚔️ Campo de Entrenamiento · Franja %d · XP al %d %% y botín al %d %%", s.Tier, math.floor(CONFIG.XP_MULT * 100 + 0.5), math.floor(CONFIG.LOOT_MULT * 100 + 0.5)))
	end
	dprint(string.format("sesión #%d (%s, franja %d, nivel %d) abierta en %s con %d jugador(es)", s.Id, faction, s.Tier, level, pod.Id, #members))
	return s
end

local function closeSession(s: Session)
	if s.Closed then
		return
	end
	s.Closed = true
	for _, m in ipairs(s.Mobs) do
		if m.Parent then
			MobService.Despawn(m)
		end
	end
	table.clear(s.Mobs)
	s.Pod.Busy = false
	sessions[s.Id] = nil
	local secs = os.clock() - s.StartedAt
	dprint(string.format("sesión #%d cerrada: %d bajas en %.1f min (%.1f bajas/min)", s.Id, s.Kills, secs / 60, s.Kills / math.max(secs / 60, 0.01)))
end

leaveSession = function(p: Player, teleport: boolean, reason: string?)
	local s = sessionOf[p]
	if not s then
		return
	end
	sessionOf[p] = nil
	local i = table.find(s.Members, p)
	if i then
		table.remove(s.Members, i)
	end
	local c = diedConn[p]
	if c then
		c:Disconnect()
		diedConn[p] = nil
	end
	if p.Parent then
		p:SetAttribute("InAfk", nil)
		p:SetAttribute("AfkLootMult", nil)
		p:SetAttribute("AfkKills", nil)
		p:SetAttribute("AfkStart", nil)
		publishLeft(p)
		if reason then
			notify(p, reason)
		end
		if teleport and rootOf(p) then
			DungeonService.MoveTo(p, portalExit[factionOf(p)] or CFrame.new(0, 10, 0), "🏠 Volviendo a la ciudad…")
		end
	end
	if #s.Members == 0 then
		closeSession(s)
	end
end

local function onMobDied(s: Session)
	if s.Closed then
		return
	end
	s.Kills += 1
	s.LastKill = os.clock()
	for _, m in ipairs(s.Members) do
		m:SetAttribute("AfkKills", s.Kills)
	end
end

local function spawnOne(s: Session)
	local alive = 0
	for i = #s.Mobs, 1, -1 do
		local m = s.Mobs[i]
		local h = if m.Parent then m:FindFirstChildOfClass("Humanoid") else nil
		if h and h.Health > 0 then
			alive += 1
		else
			table.remove(s.Mobs, i)
		end
	end
	local n = #s.Members
	if alive >= CONFIG.ALIVE_BASE + CONFIG.ALIVE_PER_EXTRA * (n - 1) then
		return
	end
	if MobService.ActiveCount() >= CONFIG.GLOBAL_MOB_CAP then
		return
	end
	local def = defFor(s.Faction, s.Tier, s.Level)
	if not def then
		return
	end
	local target: Model? = nil
	local candidates: { Model } = {}
	for _, m in ipairs(s.Members) do
		local ch = m.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if ch and hum and hum.Health > 0 then
			table.insert(candidates, ch)
		end
	end
	if #candidates == 0 then
		return
	end
	target = candidates[rng:NextInteger(1, #candidates)]
	local door = s.Pod.Doors[rng:NextInteger(1, #s.Pod.Doors)]
	local lvl = math.clamp(s.Level, def.MinLevel, def.MaxLevel)
	local model = MobService.SpawnWave(def.Id, CFrame.lookAt(door, Vector3.new(s.Pod.Center.X, door.Y, s.Pod.Center.Z)), lvl, target)
	if not model then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		local hp = math.max(1, math.floor(hum.MaxHealth * CONFIG.MOB_HP))
		hum.MaxHealth = hp
		hum.Health = hp
		model:SetAttribute("MaxHp", hp)
		hum.Died:Once(function()
			onMobDied(s)
		end)
	end
	model:SetAttribute("DmgBuff", CONFIG.MOB_DMG)
	model:SetAttribute("BaseBuff", CONFIG.MOB_DMG)
	model:SetAttribute("XpMult", CONFIG.XP_MULT * (1 + CONFIG.GROUP_XP_BONUS * (n - 1)))
	model:SetAttribute("AfkZone", s.Id)
	table.insert(s.Mobs, model)
end

-- bucle de las sesiones: apariciones (cada 0,5 s), tiempo diario, hoguera, inactividad
task.spawn(function()
	local last = os.clock()
	local leftTick = 0
	while true do
		task.wait(0.5)
		local now = os.clock()
		local dt = now - last
		last = now
		leftTick += dt
		local publish = leftTick >= 5
		if publish then
			leftTick = 0
		end
		for _, s in pairs(table.clone(sessions)) do
			if s.Closed then
				continue
			end
			local n = #s.Members
			-- apariciones: con más jugadores aparecen más rápido
			if now >= s.NextSpawn then
				spawnOne(s)
				s.NextSpawn = now + CONFIG.SPAWN_EVERY / (1 + 0.6 * (n - 1))
			end
			for _, m in ipairs(table.clone(s.Members)) do
				local d = dataOf(m)
				if d then
					d.Seconds += dt
					if leftOf(m) <= 0 then
						leaveSession(m, true, "⌛ Agotaste tus " .. string.format("%d h", CONFIG.DAILY_SECONDS // 3600) .. " del Campo de hoy")
						continue
					end
					if publish then
						publishLeft(m)
					end
				end
				-- hoguera
				local r = rootOf(m)
				local hum = m.Character and m.Character:FindFirstChildOfClass("Humanoid")
				if r and hum and hum.Health > 0 and hum.Health < hum.MaxHealth and (r.Position - s.Pod.Center).Magnitude <= 26 then
					hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * CONFIG.HEARTH_REGEN * dt)
				end
			end
			-- inactividad: nadie mata nada
			if not s.Closed and #s.Members > 0 and now - s.LastKill > CONFIG.IDLE_EJECT then
				for _, m in ipairs(table.clone(s.Members)) do
					leaveSession(m, true, "😴 Llevabas mucho sin ninguna baja: saliste del Campo (¿está encendido el Auto-farm?)")
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- GRUPO: PETICIÓN, RESPUESTAS Y ENTRADA
---------------------------------------------------------------------
local function sendWait(req: Req)
	if not req.Leader.Parent then
		return
	end
	local list: { any } = {}
	for _, m in ipairs(req.Order) do
		table.insert(list, { Name = m.Name, State = req.State[m] or "wait", Leader = m == req.Leader })
	end
	Remote:FireClient(req.Leader, "Wait", { Members = list, Deadline = req.Deadline })
end

local function closeRequest(req: Req)
	req.Done = true
	for _, m in ipairs(req.Order) do
		if reqOf[m] == req then
			reqOf[m] = nil
			if m ~= req.Leader and m.Parent then
				Remote:FireClient(m, "AskClose")
			end
		end
	end
	if reqOf[req.Leader] == req then
		reqOf[req.Leader] = nil
	end
	if req.Leader.Parent then
		Remote:FireClient(req.Leader, "WaitClose")
	end
end

local function finishRequest(req: Req)
	if req.Done then
		return
	end
	local leader = req.Leader
	-- si todos los demás salieron del grupo (el grupo se disolvió), el líder entra solo; si otro pasó a ser líder, no se entra en grupo
	local nowLeader = PartyService.LeaderOf(leader)
	local ok = leader.Parent ~= nil and (nowLeader == leader or nowLeader == nil) and not sessionOf[leader]
	local list: { Player } = {}
	if ok then
		for _, m in ipairs(req.Order) do
			local st = req.State[m]
			if m == leader or st == "yes" then
				local e, why = eligible(m)
				if e and (m == leader or PartyService.SameParty(m, leader)) then
					if #list < CONFIG.MAX_GROUP then
						table.insert(list, m)
					else
						notify(m, "El grupo del Campo está lleno (máx. " .. CONFIG.MAX_GROUP .. ")")
					end
				elseif m ~= leader then
					notify(leader, m.Name .. " no pudo entrar: " .. (why or "ya no está en tu grupo"))
					notify(m, "No pudiste entrar al Campo: " .. (why or "ya no estás en el grupo"))
				end
			elseif st == "stay" and m.Parent then
				notify(m, "No respondiste: te quedas en el grupo (puedes unirte después desde el portal)")
			end
		end
	end
	closeRequest(req)
	if ok and #list > 0 and list[1] == leader then
		startSession(list, factionOf(leader))
	elseif leader.Parent then
		notify(leader, "No se pudo entrar al Campo en grupo")
	end
end

local function allAnswered(req: Req): boolean
	for _, m in ipairs(req.Order) do
		if req.State[m] == "wait" then
			return false
		end
	end
	return true
end

local function startGroupRequest(leader: Player)
	if reqOf[leader] or sessionOf[leader] then
		return
	end
	local members = PartyService.MembersOf(leader)
	if #members < 2 then
		notify(leader, "No tienes grupo: invita a alguien o entra solo")
		return
	end
	if PartyService.LeaderOf(leader) ~= leader then
		notify(leader, "Solo el líder del grupo puede entrar en grupo")
		return
	end
	local okL, whyL = eligible(leader)
	if not okL then
		notify(leader, "No puedes entrar ahora: " .. (whyL or ""))
		return
	end
	local faction = factionOf(leader)
	if not freePod(faction) then
		notify(leader, "Todas las cápsulas del Campo están ocupadas: prueba en un momento")
		return
	end
	local level = math.huge
	for _, m in ipairs(members) do
		level = math.min(level, LevelService.GetLevel(m))
	end
	local req: Req = { Leader = leader, Order = {}, State = {}, Deadline = Workspace:GetServerTimeNow() + CONFIG.ASK_SECONDS, Done = false }
	-- el líder primero
	table.insert(req.Order, leader)
	req.State[leader] = "yes"
	reqOf[leader] = req
	for _, m in ipairs(members) do
		if m ~= leader then
			table.insert(req.Order, m)
			local e, why = eligible(m)
			if e and not reqOf[m] then
				req.State[m] = "wait"
				reqOf[m] = req
				Remote:FireClient(m, "Ask", {
					Leader = leader.Name,
					Deadline = req.Deadline,
					Tier = tierOf(faction, level),
					Title = THEMES[faction].Title,
				})
			else
				req.State[m] = "busy"
				notify(leader, m.Name .. " no puede entrar ahora: " .. (why or "tiene otra petición"))
			end
		end
	end
	sendWait(req)
	if allAnswered(req) then
		finishRequest(req)
	end
end

local function answer(p: Player, choice: any)
	local req = reqOf[p]
	if not req or req.Done or req.State[p] ~= "wait" then
		return
	end
	if choice == "yes" then
		req.State[p] = "yes"
	elseif choice == "leave" then
		req.State[p] = "left"
		PartyService.Remove(p)
	else
		return
	end
	Remote:FireClient(p, "AskClose")
	sendWait(req)
	if allAnswered(req) then
		finishRequest(req)
	end
end

local function startNow(leader: Player)
	local req = reqOf[leader]
	if req and req.Leader == leader and not req.Done then
		for _, m in ipairs(req.Order) do
			if req.State[m] == "wait" then
				req.State[m] = "stay"
			end
		end
		finishRequest(req)
	end
end

local function cancelRequest(leader: Player)
	local req = reqOf[leader]
	if req and req.Leader == leader and not req.Done then
		for _, m in ipairs(req.Order) do
			if m ~= leader and m.Parent and req.State[m] == "wait" then
				notify(m, "El líder canceló la entrada al Campo")
			end
		end
		closeRequest(req)
	end
end

-- tiempos de espera de las peticiones
task.spawn(function()
	while true do
		task.wait(0.5)
		local seen: { [Req]: boolean } = {}
		for _, req in pairs(table.clone(reqOf)) do
			if not seen[req] then
				seen[req] = true
				if not req.Done then
					local lead = PartyService.LeaderOf(req.Leader)
					if not req.Leader.Parent or (lead ~= nil and lead ~= req.Leader) then
						closeRequest(req)
					elseif Workspace:GetServerTimeNow() >= req.Deadline then
						for _, m in ipairs(req.Order) do
							if req.State[m] == "wait" then
								req.State[m] = "stay"
							end
						end
						finishRequest(req)
					end
				end
			end
		end
	end
end)

local function enterSolo(p: Player)
	if reqOf[p] then
		return
	end
	local ok, why = eligible(p)
	if not ok then
		notify(p, "No puedes entrar ahora: " .. (why or ""))
		return
	end
	startSession({ p }, factionOf(p))
end

-- unirse a la sesión de alguien de tu grupo
local function joinParty(p: Player)
	local ok, why = eligible(p)
	if not ok then
		notify(p, "No puedes entrar ahora: " .. (why or ""))
		return
	end
	local target: Session? = nil
	for _, m in ipairs(PartyService.MembersOf(p)) do
		local s = sessionOf[m]
		if m ~= p and s and not s.Closed then
			target = s
			break
		end
	end
	if not target then
		notify(p, "Nadie de tu grupo está en el Campo")
		return
	end
	if #target.Members >= CONFIG.MAX_GROUP then
		notify(p, "El grupo del Campo está lleno")
		return
	end
	if LevelService.GetLevel(p) < stripMin[target.Faction][target.Tier] then
		notify(p, "Tu nivel es muy bajo para la franja de ese grupo")
		return
	end
	addToSession(target, p, #target.Members + 1)
	for _, m in ipairs(target.Members) do
		if m ~= p then
			notify(m, p.Name .. " se unió al Campo")
		end
	end
end

---------------------------------------------------------------------
-- VENTANA DEL PORTAL
---------------------------------------------------------------------
openWindow = function(p: Player)
	local faction = factionOf(p)
	local level = LevelService.GetLevel(p)
	local members = PartyService.MembersOf(p)
	local leader = PartyService.LeaderOf(p)
	local canJoin = false
	for _, m in ipairs(members) do
		local s = sessionOf[m]
		if m ~= p and s and not s.Closed and #s.Members < CONFIG.MAX_GROUP then
			canJoin = true
		end
	end
	Remote:FireClient(p, "Open", {
		Title = THEMES[faction].Title,
		Tier = tierOf(faction, level),
		Level = level,
		Left = math.floor(leftOf(p)),
		Daily = CONFIG.DAILY_SECONDS,
		XpPct = math.floor(CONFIG.XP_MULT * 100 + 0.5),
		LootPct = math.floor(CONFIG.LOOT_MULT * 100 + 0.5),
		Free = freeCount(faction),
		Party = #members,
		IsLeader = leader == p,
		CanJoin = canJoin,
		MaxGroup = CONFIG.MAX_GROUP,
	})
end

Remote.OnServerEvent:Connect(function(p: Player, action: any, arg: any)
	local now = os.clock()
	if now - (lastAct[p] or 0) < 0.3 then
		return
	end
	lastAct[p] = now
	if action == "Solo" and nearPortal(p) then
		enterSolo(p)
	elseif action == "Group" and nearPortal(p) then
		startGroupRequest(p)
	elseif action == "Join" and nearPortal(p) then
		joinParty(p)
	elseif action == "Answer" then
		answer(p, arg)
	elseif action == "Start" then
		startNow(p)
	elseif action == "Cancel" then
		cancelRequest(p)
	elseif action == "Leave" then
		if sessionOf[p] then
			leaveSession(p, true, nil)
		end
	end
end)

Players.PlayerAdded:Connect(function(p)
	task.spawn(loadData, p)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadData, p)
end

Players.PlayerRemoving:Connect(function(p)
	local req = reqOf[p]
	if req then
		if req.Leader == p then
			closeRequest(req)
		else
			req.State[p] = "left"
			reqOf[p] = nil
			sendWait(req)
			if allAnswered(req) then
				finishRequest(req)
			end
		end
	end
	leaveSession(p, false, nil)
	lastAct[p] = nil
end)

---------------------------------------------------------------------
-- ARRANQUE
---------------------------------------------------------------------
Workspace:SetAttribute("AfkXpPct", math.floor(CONFIG.XP_MULT * 100 + 0.5))
Workspace:SetAttribute("AfkLootPct", math.floor(CONFIG.LOOT_MULT * 100 + 0.5))
Workspace:SetAttribute("AfkDaily", CONFIG.DAILY_SECONDS)
Workspace:SetAttribute("AfkMaxGroup", CONFIG.MAX_GROUP)
Workspace:SetAttribute("AfkAsk", CONFIG.ASK_SECONDS)

task.spawn(function()
	buildAllPods()
	for _, f in ipairs(THEME_ORDER) do
		task.spawn(buildPortal, f)
	end
end)

local AfkZoneService = {}

function AfkZoneService.InZone(p: Player): boolean
	return sessionOf[p] ~= nil
end

AfkZoneService.Config = CONFIG

print(string.format("[AfkZoneService] Listo: Campo de Entrenamiento · XP %d %% · botín %d %% · %d h/día · %d cápsulas por facción.", math.floor(CONFIG.XP_MULT * 100 + 0.5), math.floor(CONFIG.LOOT_MULT * 100 + 0.5), CONFIG.DAILY_SECONDS // 3600, CONFIG.PODS_PER_THEME))
return AfkZoneService
