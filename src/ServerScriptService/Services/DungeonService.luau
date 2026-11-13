--!strict
--[[
    DungeonService v3 (ModuleScript) -> ServerScriptService.Services.DungeonService
    CUEVAS por franja, inspiradas en las mazmorras aleatorias de Albion Online.

    ENTRADA: un ARCO de piedra con portal brillante (runas, braseros, círculo de luz) en cada franja de cada facción.
    PRUEBAS (CONFIG.TEST_ONLY = true): solo el dueño de la experiencia (Soberano de AdminList) puede entrar; el resto ve "PRÓXIMAMENTE".
      El dueño no gasta entradas ni necesita nivel mientras TEST_FREE_ENTRY = true. Para abrirlo a todos: TEST_ONLY = false.
      CONFIG.TEST_SIM_GROUP = 3 genera la cueva como si entraran 3 jugadores (para ver el aumento de dificultad y premios sin grupo).

    ESTRUCTURA: cada cueva es PRIVADA (instancia propia, lejos del mapa) y tiene 2 PISOS. Cada piso es un LABERINTO de galerías:
      - se genera con una semilla al azar (nunca dos iguales); el camino hasta la salida es largo y la SALIDA queda LEJOS del inicio;
      - galerías de roca irregular, estalactitas, cristales, antorchas (camino principal) y cristales (ramales), escombros, huesos,
        cajas, hongos, charcos, columnas rotas, raíces y polvo en el aire;
      - 3 SALAS al azar dentro del recorrido (Lago subterráneo, Sala de columnas, Cámara de cristales);
      - RAMALES sin salida con COFRE: los 2 más lejanos son cofres RAROS custodiados, el resto cofres comunes (CONFIG.CHESTS_PER_FLOOR);
      - MANADAS de monstruos a lo largo del camino (con algún campeón). Aparecen cuando estás a pocas celdas POR EL CAMINO;
      - al fondo del piso 1: la cámara del GUARDIÁN. Al vencerlo se abre el portal al piso 2 y aparece el COFRE DEL GUARDIÁN;
      - al fondo del piso 2: la cámara del JEFE de la franja. Al vencerlo se abre la salida y aparece el TESORO DEL JEFE (cofre épico).
    MONSTRUOS: no te ven a través de las paredes y, si te pierden de vista, siguen el laberinto (módulo DungeonNav + 6 cambios cortos en MobBrain).
    SOLO / GRUPO: sin grupo = dificultad normal. Con grupo (máx. MAX_GROUP) entran juntos los que estén cerca del portal a UNA cueva solo suya;
      cada extra sube vida (+30 %), daño (+12 %) y manadas, la XP sube más que la vida (+60 %) y los PREMIOS suben +15 % por extra.
      Dos grupos seguidos reciben cuevas distintas. Si alguien del grupo no puede entrar se avisa a TODO el grupo con su nombre.
    PREMIOS: cada cofre da botín PERSONAL a cada miembro cercano (ver REWARD): oro, material de la franja, fragmentos, gemas, pociones,
      equipo y, en los cofres grandes, mejora y mascota. El jefe además da su botín normal de jefe de franja.
    ENTRADAS DIARIAS por franja (perfil, sección "Dungeon"). Muerte: reapareces fuera y vuelves a entrar gratis mientras tu cueva siga abierta.
    Ambiente: mientras estás dentro el jugador lleva el atributo InDungeon = franja (DungeonAmbientClient oscurece la luz y apaga el clima).
    Conexión: require(Services:WaitForChild("DungeonService")) en GameServerMain. Requiere el módulo DungeonNav. Todo se ajusta en CONFIG / REWARD.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local LootTables = require(ReplicatedStorage.Modules.LootTables)
local AdminList = require(ReplicatedStorage.Modules.AdminList)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local LevelGap = require(ReplicatedStorage.Modules.LevelGap)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local LevelService = require(Services.LevelService)
local PartyService = require(Services.PartyService)
local MobService = require(Services.Mobs.MobService)
local DungeonNav = require(Services.DungeonNav)
local Wallet = require(Services.WalletService)
local Inventory = require(Services.InventoryService)
local GearService = require(Services.GearService)

local CONFIG = {
	-- PRUEBAS
	TEST_ONLY = true, -- true: solo el dueño entra; los demás ven "PRÓXIMAMENTE"
	TEST_ALLOW_ADMINS = false, -- true: también entran los admins de AdminList
	TEST_FREE_ENTRY = true, -- en pruebas el dueño no gasta entradas ni necesita nivel
	TEST_SIM_GROUP = 0, -- en pruebas: genera la cueva como si entraran tantos jugadores (0 = el tamaño real del grupo). Ej.: 3 para ver el aumento

	-- ENTRADA
	ENTRIES_PER_DAY = { 3, 3, 3, 3 },
	MIN_LEVEL = { 1, 751, 1501, 2251 },
	MAX_GROUP = 5,
	PARTY_RADIUS = 60,

	-- DIFICULTAD POR JUGADOR EXTRA (n-1)
	HP_PER_EXTRA = 0.30,
	DMG_PER_EXTRA = 0.12,
	XP_PER_EXTRA = 0.60,
	PACK_EXTRA_PER_PLAYER = 0.6, -- monstruos extra por manada y jugador extra

	-- LABERINTO
	CELL = 36, -- tamaño de cada celda (studs)
	WALL = 6, -- grosor de muro
	HEIGHT = 34, -- altura del techo
	GRID = { { 8, 8 }, { 9, 9 } }, -- celdas del piso 1 y del piso 2
	MIN_PATH = { 34, 42 }, -- celdas mínimas del camino hasta la salida (se regenera si sale corto)
	BRAID = 0.04, -- % de muros extra abiertos (bucles)
	ROOMS_PER_FLOOR = 3,

	-- MONSTRUOS
	PACK_EVERY = 4, -- una manada cada N celdas del camino principal
	PACK_SIZE = { 3, 4 }, -- monstruos por manada (piso 1, piso 2) jugando solo
	CHAMPION_HP = 2.5,
	CHAMPION_SCALE = 1.2,
	CHAMPION_XP = 1.6,
	GUARDIAN_HP = 4,
	GUARDIAN_SCALE = 1.5,
	GUARDIAN_XP = 4,
	BOSS_HP_FACTOR = 0.6, -- el jefe de la cueva es el jefe élite de la franja con esta fracción de su vida
	ACTIVATE_CELLS = 4, -- las manadas aparecen cuando alguien está a esta cantidad de celdas POR EL CAMINO (una pared no cuenta)
	ACTIVATE_CELLS_BOSS = 3, -- lo mismo para el guardián y el jefe: solo aparecen cuando te acercas a su cámara

	-- COFRES (los premios están en REWARD, más abajo)
	CHESTS_PER_FLOOR = 5, -- ramales sin salida con cofre por piso (los más lejanos del inicio)
	RARE_CHESTS_PER_FLOOR = 2, -- de esos, los más lejanos son "raros" y están custodiados
	CHEST_RADIUS = 55, -- reciben premio los miembros a menos de esta distancia del cofre
	CHEST_RADIUS_BIG = 90, -- ídem para el cofre del guardián y el del jefe (están en una cámara grande)

	-- LUZ: todo el brillo de la cueva con dos números
	LIGHT_SCALE = 0.65, -- multiplica la fuerza de TODAS las luces (1 = como antes; menos = más tenue)
	GLOW = 0.7, -- menos = el neón (portales, cristales, lago, runas) se ve más transparente

	-- CICLO DE VIDA
	TTL = 50 * 60,
	EXPIRE_AFTER_BOSS = 5 * 60,
	EMPTY_CLOSE = 180,
	ORIGIN = Vector3.new(-40000, 500, 40000), -- MUY lejos del mapa y de las casas VIP (+40000)
	SLOT_COLS = 6,
	SLOT_DX = 500,
	SLOT_DZ = 1000,
	SLOT_COUNT = 36,
	FLOOR2_DZ = 480,
}

-- Mapas con rareza (pendiente del ítem): multiplican vida/daño/XP/premios. Valores de Albion Online.
local RARITY: { [string]: { Hp: number, Dmg: number, Xp: number, Loot: number } } = {
	Normal = { Hp = 1, Dmg = 1, Xp = 1, Loot = 1 },
	Poco = { Hp = 1.16, Dmg = 1.08, Xp = 1.2, Loot = 1.15 },
	Raro = { Hp = 1.36, Dmg = 1.18, Xp = 1.5, Loot = 1.35 },
	Excepcional = { Hp = 1.58, Dmg = 1.3, Xp = 1.9, Loot = 1.6 },
}

-- PREMIOS DE LOS COFRES. Son PERSONALES: cada jugador a menos de CHEST_RADIUS del cofre tira por su cuenta.
--   Gold = multiplicador del oro de un monstruo del tope de la franja (nv. 750/1500/2250/3000). Strip/Frag/Gem = rangos {min, max}.
--   Gear = probabilidad de equipo (1 = garantizado); MobGear = usa las rarezas de un monstruo normal (si no, las del cofre del mapa).
--   Upgraded = veces la probabilidad de "cofre MEJORADO" del mapa (el equipo sube una rareza y trae mejora). Pet = prob. de mascota.
-- Con grupo todo sube: oro y cantidades x(1 + PER_EXTRA por jugador extra) y las probabilidades x(1 + 0,7 de ese aumento).
-- Comparación con el resto del juego (oro x): mini jefe 5 · cofre del mapa 6 · desafío 7 · jefe de franja 12 · jefe mundial 40.
type Tier = {
	Gold: number, Strip: { number }, Frag: { number }, GemChance: number, Gem: { number }, Potion: number,
	Gear: number, MobGear: boolean, Upgraded: number, Pet: number, Points: number, ExtraGear: number,
}
local REWARD = {
	PER_EXTRA = 0.15, -- +15 % de premio por jugador extra
	LEVEL_GAP = true, -- quien está muy por encima de la franja recibe menos (igual que en el resto del juego). En pruebas del dueño no se aplica
	Tiers = {
		Comun = { Gold = 4, Strip = { 1, 2 }, Frag = { 0, 1 }, GemChance = 0.20, Gem = { 1, 1 }, Potion = 0.40, Gear = 0.03, MobGear = true, Upgraded = 0, Pet = 0, Points = 0, ExtraGear = 0 },
		Raro = { Gold = 8, Strip = { 2, 4 }, Frag = { 1, 2 }, GemChance = 0.45, Gem = { 1, 2 }, Potion = 0.60, Gear = 0.18, MobGear = false, Upgraded = 1, Pet = 0.003, Points = 3, ExtraGear = 0 },
		Guardian = { Gold = 10, Strip = { 2, 4 }, Frag = { 1, 3 }, GemChance = 0.60, Gem = { 1, 2 }, Potion = 0.60, Gear = 0.30, MobGear = false, Upgraded = 1.5, Pet = 0.004, Points = 6, ExtraGear = 0 },
		Final = { Gold = 20, Strip = { 3, 6 }, Frag = { 2, 4 }, GemChance = 0.80, Gem = { 1, 3 }, Potion = 0.80, Gear = 1, MobGear = false, Upgraded = 3, Pet = 0.015, Points = 15, ExtraGear = 0.10 },
	} :: { [string]: Tier },
}

local NotifyRemote = Net.Get("Notify")

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}
local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 190, 70),
	Shinobi = Color3.fromRGB(110, 220, 120),
	Pirate = Color3.fromRGB(90, 170, 255),
	Shinigami = Color3.fromRGB(190, 130, 255),
}

type Palette = { Floor: Color3, Wall: Color3, Crystal: Color3, Lake: Color3 }
local PALETTE: { [number]: Palette } = {
	[1] = { Floor = Color3.fromRGB(96, 88, 78), Wall = Color3.fromRGB(64, 58, 54), Crystal = Color3.fromRGB(120, 220, 255), Lake = Color3.fromRGB(60, 170, 230) },
	[2] = { Floor = Color3.fromRGB(74, 80, 96), Wall = Color3.fromRGB(46, 52, 68), Crystal = Color3.fromRGB(130, 255, 190), Lake = Color3.fromRGB(70, 210, 170) },
	[3] = { Floor = Color3.fromRGB(82, 66, 98), Wall = Color3.fromRGB(50, 38, 64), Crystal = Color3.fromRGB(215, 125, 255), Lake = Color3.fromRGB(190, 90, 255) },
	[4] = { Floor = Color3.fromRGB(78, 52, 50), Wall = Color3.fromRGB(46, 28, 28), Crystal = Color3.fromRGB(255, 125, 70), Lake = Color3.fromRGB(255, 100, 30) },
}

type Portal = { Membrane: { BasePart }, Prompt: ProximityPrompt, Label: TextLabel, Light: PointLight, Emitter: ParticleEmitter, Color: Color3, Set: (boolean, string) -> () }
type Spawn = { Pos: Vector3, Def: MobCatalog.MobDef, Level: number?, HpF: number, Scale: number, XpF: number, Kind: string }
type Group = { Center: Vector3, Spawns: { Spawn }, Floor: number, Done: boolean, Reach: number }
type Floor = { Index: number, Origin: Vector3, Arrive: CFrame, BackCF: CFrame, ExitCF: CFrame, ArenaCenter: Vector3, PathLen: number, Rooms: { string }, Folder: Folder, Nav: DungeonNav.FloorData }
type Inst = {
	Id: number,
	Slot: number,
	Strip: number,
	Faction: string,
	N: number,
	Members: { [Player]: boolean },
	Folder: Folder,
	Origin: Vector3,
	ExitCF: CFrame,
	F1: Floor?,
	F2: Floor?,
	Rng: Random,
	HpMult: number,
	DmgMult: number,
	XpMult: number,
	RewardMult: number,
	Simulated: boolean,
	Mobs: { Model },
	Groups: { Group },
	GuardianDead: boolean,
	Floor2Open: boolean,
	BossDead: boolean,
	P1Exit: Portal?,
	P2Exit: Portal?,
	ExpireAt: number,
	EmptySince: number?,
	Warned: boolean,
	Closed: boolean,
	Chests: number,
	ChestsOpened: number,
}

local DungeonService = {}
local instances: { [number]: Inst } = {}
local slotUsed: { [number]: boolean } = {}
local instOf: { [Player]: Inst } = {}
local entering: { [Player]: boolean } = {}
local nextId = 0

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------
local function notify(p: Player, text: string)
	NotifyRemote:FireClient(p, text)
end

local function notifyAll(list: { Player }, text: string)
	for _, p in ipairs(list) do
		if p.Parent then
			notify(p, text)
		end
	end
end

local function rootOf(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function moveTo(p: Player, cf: CFrame)
	task.spawn(function()
		pcall(function()
			p:RequestStreamAroundAsync(cf.Position, 3)
		end)
		local r = rootOf(p)
		if r then
			r.AssemblyLinearVelocity = Vector3.zero
			r.CFrame = cf
		end
	end)
end

-- cede el turno cada cierto número de piezas para no congelar el servidor al construir una cueva
local built = 0
local function pace()
	built += 1
	if built % 300 == 0 then
		RunService.Heartbeat:Wait()
	end
end

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	pace()
	return p
end

-- cilindro vertical (el de Roblox tiene el eje en X)
local function cyl(parent: Instance, name: string, diameter: number, height: number, pos: Vector3, color: Color3, mat: Enum.Material, collide: boolean): Part
	return mk(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, mat, collide, Enum.PartType.Cylinder)
end

local function addLight(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness * CONFIG.LIGHT_SCALE
	l.Shadows = false
	l.Parent = parent
	return l
end

-- neón más tenue: transparencia efectiva = 1 - (1 - t) * GLOW
local function glow(p: BasePart, t: number)
	p.Transparency = 1 - (1 - t) * CONFIG.GLOW
end

local function memberList(inst: Inst): { Player }
	local out: { Player } = {}
	for p in pairs(inst.Members) do
		if p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

local function testAllowed(p: Player): boolean
	if not CONFIG.TEST_ONLY then
		return true
	end
	local e = AdminList.Get(p)
	if not e then
		return false
	end
	return e.Kind == "Owner" or CONFIG.TEST_ALLOW_ADMINS
end

local function freeEntry(p: Player): boolean
	return CONFIG.TEST_ONLY and CONFIG.TEST_FREE_ENTRY and testAllowed(p)
end

---------------------------------------------------------------------
-- ENTRADAS DIARIAS (perfil, sección "Dungeon")
---------------------------------------------------------------------
type Daily = { Day: string, Used: { [string]: number } }
local daily: { [Player]: Daily } = {}

local function today(): string
	return os.date("!%Y-%m-%d", os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600) :: string
end

local function dailyOf(p: Player): Daily?
	local d = daily[p]
	if not d then
		return nil
	end
	local t = today()
	if d.Day ~= t then
		d.Day, d.Used = t, {}
	end
	return d
end

local function entriesLeft(p: Player, strip: number): number
	local d = dailyOf(p)
	if not d then
		return 0 -- el perfil aún no cargó
	end
	return math.max(0, CONFIG.ENTRIES_PER_DAY[strip] - (d.Used[tostring(strip)] or 0))
end

local function useEntry(p: Player, strip: number)
	local d = dailyOf(p)
	if d then
		d.Used[tostring(strip)] = (d.Used[tostring(strip)] or 0) + 1
	end
	p:SetAttribute("DungeonLeft_" .. strip, entriesLeft(p, strip))
end

PlayerData.RegisterSerializer("Dungeon", function(p: Player): any?
	local d = daily[p]
	if not d then
		return nil
	end
	return { Day = d.Day, Used = table.clone(d.Used) }
end)

local function loadDaily(p: Player)
	local saved = PlayerData.WaitForData(p)
	if not saved or p.Parent == nil then
		return
	end
	local d: Daily = { Day = today(), Used = {} }
	local raw: any = (saved :: any).Dungeon
	if typeof(raw) == "table" and typeof(raw.Day) == "string" then
		d.Day = raw.Day
		if typeof(raw.Used) == "table" then
			for k, v in pairs(raw.Used) do
				if typeof(k) == "string" and typeof(v) == "number" then
					d.Used[k] = math.max(0, math.floor(v))
				end
			end
		end
	end
	daily[p] = d
	for strip = 1, 4 do
		p:SetAttribute("DungeonLeft_" .. strip, entriesLeft(p, strip))
	end
end

PlayerData.Releasing:Connect(function(p: Player)
	daily[p] = nil
end)
Players.PlayerAdded:Connect(function(p)
	task.spawn(loadDaily, p)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadDaily, p)
end

---------------------------------------------------------------------
-- PIEZAS DE ESCENOGRAFÍA
---------------------------------------------------------------------
local function spike(parent: Instance, base: Vector3, up: boolean, h: number, r: number, color: Color3, rng: Random)
	local dir = if up then 1 else -1
	local yaw = rng:NextNumber() * math.pi * 2
	for i = 0, 1 do
		local k = 1 - i * 0.45
		local seg = h / 2
		local sz = Vector3.new(r * 2 * k, seg + 0.4, r * 2 * k)
		local cf = CFrame.new(base + Vector3.new(0, dir * seg * (i + 0.5), 0)) * CFrame.Angles(0, yaw + i * 0.5, 0)
		mk(parent, "Roca", sz, cf, color, Enum.Material.Slate, false)
	end
end

local function crystal(parent: Instance, pos: Vector3, color: Color3, rng: Random, big: boolean, withLight: boolean)
	local h = (if big then 6 else 3) + rng:NextNumber() * (if big then 8 else 4)
	local w = if big then 2.2 else 1.2
	local p = mk(parent, "Cristal", Vector3.new(w, h, w), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles((rng:NextNumber() - 0.5) * 0.5, rng:NextNumber() * 6, (rng:NextNumber() - 0.5) * 0.5), color, Enum.Material.Neon, false)
	glow(p, 0.15)
	if withLight then
		addLight(p, color, if big then 34 else 20, if big then 1.8 else 1.1)
	end
end

local function brazier(parent: Instance, pos: Vector3, scale: number)
	cyl(parent, "Poste", 0.9 * scale, 4.2 * scale, pos + Vector3.new(0, 2.1 * scale, 0), Color3.fromRGB(70, 50, 38), Enum.Material.Wood, false)
	local bowl = cyl(parent, "Cuenco", 2.8 * scale, 0.9 * scale, pos + Vector3.new(0, 4.4 * scale, 0), Color3.fromRGB(40, 38, 40), Enum.Material.Metal, false)
	local fire = Instance.new("Fire")
	fire.Size = 5 * scale
	fire.Heat = 8
	fire.Color = Color3.fromRGB(255, 150, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = bowl
	addLight(bowl, Color3.fromRGB(255, 170, 90), 48, 1.6)
end

-- escombros, huesos, cajas, hongos, charcos, columnas rotas, raíces, polvo, estandartes y tarima (decoración; casi todo sin colisión)
local function rubble(parent: Instance, pos: Vector3, rng: Random, color: Color3)
	for _ = 1, 4 do
		local sz = 0.8 + rng:NextNumber() * 2
		local cf = CFrame.new(pos + Vector3.new((rng:NextNumber() - 0.5) * 5, sz * 0.35, (rng:NextNumber() - 0.5) * 5)) * CFrame.Angles(rng:NextNumber() * 3, rng:NextNumber() * 3, rng:NextNumber() * 3)
		mk(parent, "Escombro", Vector3.new(sz * 1.4, sz, sz * 1.2), cf, color:Lerp(Color3.new(0, 0, 0), rng:NextNumber() * 0.3), Enum.Material.Rock, false)
	end
end

local function bones(parent: Instance, pos: Vector3, rng: Random)
	local bone = Color3.fromRGB(214, 206, 188)
	mk(parent, "Calavera", Vector3.new(1.5, 1.4, 1.6), CFrame.new(pos + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber() * 6, 0), bone, Enum.Material.Marble, false, Enum.PartType.Ball)
	for _ = 1, 3 do
		local a = rng:NextNumber() * math.pi * 2
		mk(parent, "Hueso", Vector3.new(0.35, 0.35, 2.6 + rng:NextNumber()), CFrame.new(pos + Vector3.new(math.cos(a) * 2, 0.25, math.sin(a) * 2)) * CFrame.Angles(0, a + 1, 0), bone, Enum.Material.Marble, false)
	end
end

local function crateStack(parent: Instance, pos: Vector3, rng: Random)
	local wood = Color3.fromRGB(104, 76, 48)
	local dark = Color3.fromRGB(70, 50, 34)
	for i = 1, 2 do
		local sz = 2.4 + rng:NextNumber() * 0.8
		mk(parent, "Caja", Vector3.new(sz, sz, sz), CFrame.new(pos + Vector3.new(i * 1.2 - 1.8, sz / 2, (rng:NextNumber() - 0.5) * 2)) * CFrame.Angles(0, rng:NextNumber() * 1.2, 0), wood:Lerp(dark, rng:NextNumber() * 0.5), Enum.Material.Wood, true)
	end
	cyl(parent, "Barril", 2.4, 3.2, pos + Vector3.new(2.6, 1.6, 1.2), Color3.fromRGB(92, 62, 38), Enum.Material.Wood, true)
	cyl(parent, "AroBarril", 2.55, 0.25, pos + Vector3.new(2.6, 2.4, 1.2), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, false)
	cyl(parent, "AroBarril", 2.55, 0.25, pos + Vector3.new(2.6, 0.8, 1.2), Color3.fromRGB(60, 60, 64), Enum.Material.Metal, false)
end

local function mushrooms(parent: Instance, pos: Vector3, color: Color3, rng: Random)
	for i = 1, 3 + rng:NextInteger(0, 2) do
		local h = 1 + rng:NextNumber() * 2.2
		local p = pos + Vector3.new((rng:NextNumber() - 0.5) * 5, 0, (rng:NextNumber() - 0.5) * 5)
		cyl(parent, "Tallo", 0.5, h, p + Vector3.new(0, h / 2, 0), Color3.fromRGB(190, 180, 160), Enum.Material.SmoothPlastic, false)
		local cap = mk(parent, "Sombrero", Vector3.new(h * 1.3, h * 0.55, h * 1.3), CFrame.new(p + Vector3.new(0, h, 0)), color, Enum.Material.Neon, false, Enum.PartType.Ball)
		glow(cap, 0.25)
		if i == 1 then
			addLight(cap, color, 12, 0.7)
		end
	end
end

local function puddle(parent: Instance, pos: Vector3, color: Color3, rng: Random)
	local d = 5 + rng:NextNumber() * 6
	local p = cyl(parent, "Charco", d, 0.1, pos + Vector3.new(0, 0.1, 0), color:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Glass, false)
	p.Reflectance = 0.25
	p.Transparency = 0.25
end

local function brokenColumn(parent: Instance, pos: Vector3, color: Color3, rng: Random)
	local h = 7 + rng:NextNumber() * 9
	cyl(parent, "ColumnaRota", 4.2, h, pos + Vector3.new(0, h / 2, 0), color, Enum.Material.Basalt, true)
	local fh = 5 + rng:NextNumber() * 4
	mk(parent, "Fuste", Vector3.new(fh, 3.6, 3.6), CFrame.new(pos + Vector3.new(5.5, 1.8, (rng:NextNumber() - 0.5) * 4)) * CFrame.Angles(0, rng:NextNumber() * 1.2, 0), color, Enum.Material.Basalt, true, Enum.PartType.Cylinder)
	rubble(parent, pos, rng, color)
end

local function roots(parent: Instance, pos: Vector3, ceilY: number, rng: Random)
	for _ = 1, 3 do
		local len = 5 + rng:NextNumber() * 10
		local p = pos + Vector3.new((rng:NextNumber() - 0.5) * 8, ceilY - len / 2, (rng:NextNumber() - 0.5) * 8)
		cyl(parent, "Raiz", 0.35 + rng:NextNumber() * 0.4, len, p, Color3.fromRGB(70, 50, 34), Enum.Material.Wood, false)
	end
end

local function dust(parent: Instance, pos: Vector3, height: number)
	local a = Instance.new("Part")
	a.Name = "Polvo"
	a.Anchored = true
	a.CanCollide = false
	a.CanQuery = false
	a.CanTouch = false
	a.CastShadow = false
	a.Transparency = 1
	a.Size = Vector3.new(26, height * 0.7, 26)
	a.CFrame = CFrame.new(pos + Vector3.new(0, height * 0.4, 0))
	a.Parent = parent
	local e = Instance.new("ParticleEmitter")
	e.Rate = 3
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(0.2, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.25)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
	e.LightEmission = 0.1
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Parent = a
end

local function banner(parent: Instance, pos: Vector3, lookAt: Vector3, color: Color3, height: number)
	local h = 13
	local top = Vector3.new(pos.X, pos.Y + height - 3, pos.Z)
	local face = Vector3.new(lookAt.X, top.Y, lookAt.Z)
	mk(parent, "Estandarte", Vector3.new(4.2, h, 0.4), CFrame.lookAt(top - Vector3.new(0, h / 2, 0), face), color, Enum.Material.Fabric, false)
	mk(parent, "Remate", Vector3.new(5, 0.5, 0.7), CFrame.lookAt(top, face), Color3.fromRGB(200, 160, 70), Enum.Material.Metal, false)
end

-- tarima de la cámara final: dos escalones bajos de piedra (se sube andando)
local function dais(parent: Instance, c: Vector3, color: Color3, k: number)
	cyl(parent, "Tarima", 56 * k, 0.4, c + Vector3.new(0, 0.2, 0), color, Enum.Material.Cobblestone, true)
	cyl(parent, "Tarima", 38 * k, 0.8, c + Vector3.new(0, 0.4, 0), color:Lerp(Color3.new(1, 1, 1), 0.06), Enum.Material.Cobblestone, true)
end

-- ARCO DE PIEDRA CON PORTAL (cf: base en el suelo, el eje del portal es el lookVector; las runas y el cartel se ven por ambos lados)
local function makeArch(parent: Instance, name: string, cf: CFrame, color: Color3, s: number, title: string, action: string, objectText: string, onUse: (Player) -> ()): Portal
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local stone = Color3.fromRGB(88, 82, 78)
	local dark = Color3.fromRGB(56, 52, 52)
	local function part(n: string, size: Vector3, localCf: CFrame, col: Color3, mat: Enum.Material, collide: boolean): Part
		return mk(model, n, size, cf * localCf, col, mat, collide)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part("Pilar", Vector3.new(4 * s, 12 * s, 6 * s), CFrame.new(sx * 9 * s, 6 * s, 0), stone, Enum.Material.Cobblestone, true)
		part("Base", Vector3.new(6.4 * s, 1.4 * s, 8 * s), CFrame.new(sx * 9 * s, 0.7 * s, 0), dark, Enum.Material.Slate, true)
		part("Runa", Vector3.new(0.7 * s, 8 * s, 0.4 * s), CFrame.new(sx * 9 * s, 6.5 * s, 3.1 * s), color, Enum.Material.Neon, false)
		part("Runa", Vector3.new(0.7 * s, 8 * s, 0.4 * s), CFrame.new(sx * 9 * s, 6.5 * s, -3.1 * s), color, Enum.Material.Neon, false)
		brazier(model, (cf * CFrame.new(sx * 15.5 * s, 0, 0)).Position, s)
	end
	-- medio arco de piedra
	local N = 12
	for i = 0, N do
		local ang = i / N * math.pi
		part("Arco", Vector3.new(4 * s, 3.4 * s, 6 * s), CFrame.new(0, 12 * s, 0) * CFrame.Angles(0, 0, ang) * CFrame.new(9 * s, 0, 0), stone, Enum.Material.Cobblestone, true)
	end
	local gem = part("Gema", Vector3.new(2.6 * s, 2.6 * s, 2.6 * s), CFrame.new(0, 21.6 * s, 0), color, Enum.Material.Neon, false)
	gem.Shape = Enum.PartType.Ball
	-- membrana del portal (rectángulo + remate redondeado con tiras)
	local membrane: { BasePart } = {}
	local base = part("Portal", Vector3.new(14 * s, 12 * s, 0.5 * s), CFrame.new(0, 6 * s, 0), color, Enum.Material.Neon, false)
	glow(base, 0.45)
	table.insert(membrane, base)
	local SL = 10
	for i = 1, SL do
		local x = -7 + (i - 0.5) * 14 / SL
		local h = math.sqrt(math.max(0.01, 49 - x * x)) * s
		local slat = part("Portal", Vector3.new(14 / SL * s + 0.05, h, 0.5 * s), CFrame.new(x * s, 12 * s + h / 2, 0), color, Enum.Material.Neon, false)
		glow(slat, 0.45)
		table.insert(membrane, slat)
	end
	-- tarima de piedra y círculo de luz tenue en el suelo
	cyl(model, "Tarima", 24 * s, 0.5, cf.Position + Vector3.new(0, 0.25, 0), dark, Enum.Material.Slate, false)
	local ring = cyl(model, "Circulo", 20 * s, 0.2, cf.Position + Vector3.new(0, 0.55, 0), color, Enum.Material.Neon, false)
	glow(ring, 0.78)
	-- partículas
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = 16
	emitter.Lifetime = NumberRange.new(1.5, 2.6)
	emitter.Speed = NumberRange.new(0.5, 2)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7 * s), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = base
	local light = addLight(base, color, 34 * s, 2.4)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(280, 56)
	bb.StudsOffset = Vector3.new(0, 19 * s, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 130
	bb.Parent = base
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextWrapped = true
	label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	label.TextStrokeTransparency = 0.4
	label.Text = title
	label.Parent = bb

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.6
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = base
	pp.Triggered:Connect(onUse)

	return {
		Membrane = membrane,
		Prompt = pp,
		Label = label,
		Light = light,
		Emitter = emitter,
		Color = color,
		Set = function(open: boolean, text: string)
			label.Text = text
			pp.Enabled = open
			for _, m in ipairs(membrane) do
				m.Color = if open then color else Color3.fromRGB(70, 70, 82)
				glow(m, if open then 0.45 else 0.72)
			end
			emitter.Enabled = open
			light.Color = if open then color else Color3.fromRGB(120, 120, 135)
			light.Brightness = (if open then 2.4 else 0.6) * CONFIG.LIGHT_SCALE
		end,
	}
end

-- COFRES: el primero que lo abre reparte premios PERSONALES a todos los del grupo que estén cerca (ver REWARD)
local lootRng = Random.new()

local function itemLabel(id: string, count: number, plus: number?): string
	local item = (ItemCatalog.Items :: any)[id]
	if not item then
		return id
	end
	local text: string = item.Name
	if item.Gear or item.Pet then
		text = string.format("[%s] %s", GearCatalog.RarityName[item.Rarity] or item.Rarity, item.Name)
		if plus and plus > 0 then
			text ..= " +" .. plus
		end
	end
	if count > 1 then
		text ..= " x" .. count
	end
	return text
end

-- cantidad en un rango, escalada con decimales al azar (1,4 = 1 y 40 % de que sea 2)
local function countOf(range: { number }, mult: number): number
	local base = lootRng:NextInteger(range[1], range[2]) * mult
	local whole = math.floor(base)
	if lootRng:NextNumber() < base - whole then
		whole += 1
	end
	return whole
end

local function grantChest(pl: Player, inst: Inst, tier: string, title: string)
	if not pl.Parent then
		return
	end
	local T = REWARD.Tiers[tier] or REWARD.Tiers.Comun
	local strip = inst.Strip
	local level = strip * 750 -- tope de la franja en la escala de niveles actual (750 / 1500 / 2250 / 3000)
	local gap = 1
	if REWARD.LEVEL_GAP and not freeEntry(pl) then
		gap = LevelGap.Mult(LevelService.GetLevel(pl), level)
	end
	local mult = inst.RewardMult
	local luck = (1 + GearService.Luck(pl)) * gap - 1
	local function chance(p: number): number
		return math.min(0.95, p * (1 + luck) * (1 + (mult - 1) * 0.7))
	end
	local class = PlayerClass.Get(pl)
	local faction, role = class.Faction, class.Role
	local parts: { string } = {}
	local notable = false
	local allAdded = true
	local function give(id: string?, count: number, plus: number?, important: boolean)
		if not id or count <= 0 then
			return
		end
		if Inventory.Add(pl, id, count, plus) then
			table.insert(parts, itemLabel(id, count, plus))
			if important then
				notable = true
			end
		else
			allAdded = false
		end
	end

	local gold = Wallet.AddGold(pl, math.floor(LootTables.GoldFor(level, T.Gold * mult, lootRng) * GearService.GoldMult(pl) * gap), "Cofres")
	if gold > 0 then
		table.insert(parts, string.format("+%d oro", gold))
	end
	if T.Points > 0 then
		local pts = Wallet.AddFactionPoints(pl, math.floor(T.Points * mult))
		if pts > 0 then
			table.insert(parts, string.format("+%d pts de facción", pts))
		end
	end
	give(LootTables.StripMaterial[strip], countOf(T.Strip, mult), nil, false)
	give("Mat_FragArmadura", countOf(T.Frag, mult), nil, false)
	if lootRng:NextNumber() < chance(T.GemChance) then
		give("Mat_GemaMenor", countOf(T.Gem, mult), nil, false)
	end
	if lootRng:NextNumber() < chance(T.Potion) then
		give(if lootRng:NextNumber() < 0.6 then "Pocion_Vida" else "Pocion_Energia", lootRng:NextInteger(1, 3), nil, false)
	end
	-- equipo (resuelto al rol y a la facción de quien lo recibe)
	local gearW = if T.MobGear then LootTables.Mob.GearRarityByStrip[strip] else LootTables.MapChest.GearRarity[strip]
	local function rollGear()
		local upgraded = T.Upgraded > 0 and lootRng:NextNumber() < chance(LootTables.MapChest.UpgradedChance[strip] * T.Upgraded)
		local id = LootTables.RollGear(faction, role, level, gearW, lootRng, nil, upgraded)
		if id then
			give(id, 1, if upgraded then LootTables.Count(LootTables.MapChest.UpgradedPlus, lootRng) else nil, true)
			if upgraded then
				notify(pl, "✨ ¡Cofre MEJORADO! El equipo subió de rareza y viene con mejora")
			end
		end
	end
	if T.Gear >= 1 or lootRng:NextNumber() < chance(T.Gear) then
		rollGear()
	end
	if T.ExtraGear > 0 and lootRng:NextNumber() < chance(T.ExtraGear) then
		rollGear()
	end
	if T.Pet > 0 and lootRng:NextNumber() < chance(T.Pet) then
		give(LootTables.RollPet(if tier == "Final" then LootTables.EliteBoss.PetRarity else LootTables.MiniBoss.PetRarity, lootRng, faction), 1, nil, true)
	end

	local head = "🎁 " .. title
	if mult > 1.001 then
		head ..= string.format(" (premio +%d%% por grupo)", math.floor((mult - 1) * 100 + 0.5))
	end
	notify(pl, head .. ": " .. (if #parts > 0 then table.concat(parts, " · ") else "vacío"))
	if not allAdded then
		notify(pl, "⚠ Tu inventario está lleno: parte del premio no cupo. Haz espacio antes de abrir el próximo cofre.")
	end
	if notable then
		PlayerData.Save(pl) -- un premio importante no debe esperar al autoguardado
	end
end

type ChestLook = { Scale: number, Wood: Color3, Band: Color3, Gem: Color3, Name: string }
local CHEST_LOOK: { [string]: ChestLook } = {
	Comun = { Scale = 1, Wood = Color3.fromRGB(112, 72, 40), Band = Color3.fromRGB(150, 150, 156), Gem = Color3.fromRGB(255, 190, 90), Name = "Cofre del tesoro" },
	Raro = { Scale = 1.15, Wood = Color3.fromRGB(52, 58, 76), Band = Color3.fromRGB(170, 190, 215), Gem = Color3.fromRGB(110, 190, 255), Name = "Cofre reforzado" },
	Guardian = { Scale = 1.3, Wood = Color3.fromRGB(86, 40, 40), Band = Color3.fromRGB(210, 170, 70), Gem = Color3.fromRGB(255, 120, 90), Name = "Cofre del Guardián" },
	Final = { Scale = 1.5, Wood = Color3.fromRGB(70, 40, 24), Band = Color3.fromRGB(255, 205, 90), Gem = Color3.fromRGB(255, 240, 160), Name = "Tesoro del Jefe" },
}

local function buildChest(inst: Inst, parent: Instance, pos: Vector3, faceTo: Vector3, tier: string)
	local look = CHEST_LOOK[tier] or CHEST_LOOK.Comun
	local k = look.Scale
	local model = Instance.new("Model")
	model.Name = "Cofre_" .. tier
	model.Parent = parent
	local flat = Vector3.new(faceTo.X, pos.Y, faceTo.Z)
	if (flat - pos).Magnitude < 0.1 then
		flat = pos + Vector3.new(0, 0, -1)
	end
	local cf = CFrame.lookAt(pos, flat)
	local body = mk(model, "Cuerpo", Vector3.new(5, 2.6, 3.4) * k, cf * CFrame.new(0, 1.3 * k, 0), look.Wood, Enum.Material.Wood, true)
	local lidParts: { BasePart } = {}
	table.insert(lidParts, mk(model, "Tapa", Vector3.new(5.2, 3.4, 3.4) * k, cf * CFrame.new(0, 2.6 * k, 0), look.Wood, Enum.Material.Wood, false, Enum.PartType.Cylinder))
	for _, x in ipairs({ -1.7, 1.7 }) do
		mk(model, "Banda", Vector3.new(0.5, 2.7, 3.6) * k, cf * CFrame.new(x * k, 1.35 * k, 0), look.Band, Enum.Material.Metal, false)
		table.insert(lidParts, mk(model, "BandaTapa", Vector3.new(0.5, 3.7, 3.7) * k, cf * CFrame.new(x * k, 2.6 * k, 0), look.Band, Enum.Material.Metal, false, Enum.PartType.Cylinder))
	end
	if tier == "Guardian" or tier == "Final" then
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				mk(model, "Esquina", Vector3.new(0.8, 0.8, 0.8) * k, cf * CFrame.new(sx * 2.5 * k, 0.4 * k, sz * 1.7 * k), look.Band, Enum.Material.Metal, false)
			end
		end
	end
	local gem = mk(model, "Cerradura", Vector3.new(0.9, 0.9, 0.5) * k, cf * CFrame.new(0, 2.3 * k, -1.75 * k), look.Gem, Enum.Material.Neon, false)
	glow(gem, 0.1)
	addLight(gem, look.Gem, 14 + 10 * k, 1.1)
	local halo = cyl(model, "BrilloCofre", 9 * k, 0.15, pos + Vector3.new(0, 0.1, 0), look.Gem, Enum.Material.Neon, false)
	glow(halo, 0.82)

	local sparkle: ParticleEmitter? = nil
	if tier == "Guardian" or tier == "Final" then
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(look.Gem)
		e.LightEmission = 0.6
		e.Rate = 6
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = body
		sparkle = e
	end
	if tier ~= "Comun" then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(220, 34)
		bb.StudsOffset = Vector3.new(0, 5.5 * k, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 70
		bb.Parent = body
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Font = Enum.Font.GothamBold
		tl.TextSize = 15
		tl.TextColor3 = look.Gem
		tl.TextStrokeTransparency = 0.4
		tl.Text = (if tier == "Final" then "👑 " elseif tier == "Guardian" then "💎 " else "") .. look.Name
		tl.Parent = bb
	end

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Abrir"
	pp.ObjectText = look.Name
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.8
	pp.MaxActivationDistance = 11 * k
	pp.RequiresLineOfSight = false
	pp.Parent = body
	local opened = false
	local radius = if tier == "Guardian" or tier == "Final" then CONFIG.CHEST_RADIUS_BIG else CONFIG.CHEST_RADIUS
	pp.Triggered:Connect(function(pl: Player)
		if opened or inst.Closed or instOf[pl] ~= inst then
			return
		end
		opened = true
		pp.Enabled = false
		local hinge = cf * CFrame.new(0, 2.6 * k, 1.7 * k)
		local swing = hinge * CFrame.Angles(math.rad(70), 0, 0) * hinge:Inverse()
		for _, lp in ipairs(lidParts) do
			lp.CFrame = swing * lp.CFrame
		end
		gem.Color = Color3.new(1, 1, 1)
		if sparkle then
			sparkle:Emit(40)
			sparkle.Enabled = false
		end
		inst.ChestsOpened += 1
		local near: { Player } = {}
		for _, m in ipairs(memberList(inst)) do
			local r = rootOf(m)
			if r and (r.Position - pos).Magnitude <= radius then
				table.insert(near, m)
			else
				notify(m, "Se abrió un cofre y no estabas cerca: sin premio para ti (acércate al abrir)")
			end
		end
		if #near == 0 then
			near = { pl }
		end
		for _, m in ipairs(near) do
			task.spawn(function()
				local ok, err = pcall(grantChest, m, inst, tier, look.Name)
				if not ok then
					warn("[DungeonService] Error al dar el premio del cofre: " .. tostring(err))
					notify(m, "⚠ Error al entregar el premio del cofre (avisa al desarrollador).")
				end
			end)
		end
	end)
end

---------------------------------------------------------------------
-- LABERINTO
---------------------------------------------------------------------
type Maze = { W: number, H: number, HE: { [number]: { [number]: boolean } }, VS: { [number]: { [number]: boolean } } }
local DX = { 0, 1, 0, -1 } -- 1 = norte (-Z), 2 = este (+X), 3 = sur (+Z), 4 = oeste (-X)
local DY = { -1, 0, 1, 0 }
local DIRV = { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }

local function passage(m: Maze, cx: number, cy: number, d: number): boolean
	if d == 1 then
		return cy > 0 and m.VS[cy - 1][cx]
	elseif d == 2 then
		return cx < m.W - 1 and m.HE[cy][cx]
	elseif d == 3 then
		return cy < m.H - 1 and m.VS[cy][cx]
	end
	return cx > 0 and m.HE[cy][cx - 1]
end

local function setPassage(m: Maze, cx: number, cy: number, d: number, v: boolean)
	if d == 1 then
		m.VS[cy - 1][cx] = v
	elseif d == 2 then
		m.HE[cy][cx] = v
	elseif d == 3 then
		m.VS[cy][cx] = v
	else
		m.HE[cy][cx - 1] = v
	end
end

-- laberinto perfecto (galerías largas con pocas bifurcaciones) + algunos bucles. Empieza en la fila sur.
local function genMaze(W: number, H: number, rng: Random): (Maze, number, number)
	local m: Maze = { W = W, H = H, HE = {}, VS = {} }
	local visited: { [number]: { [number]: boolean } } = {}
	for cy = 0, H - 1 do
		m.HE[cy], m.VS[cy], visited[cy] = {}, {}, {}
		for cx = 0, W - 1 do
			m.HE[cy][cx], m.VS[cy][cx], visited[cy][cx] = false, false, false
		end
	end
	local sx, sy = rng:NextInteger(0, W - 1), H - 1
	local stack: { { number } } = { { sx, sy } }
	visited[sy][sx] = true
	while #stack > 0 do
		local top = stack[#stack]
		local cx, cy = top[1], top[2]
		local dirs: { number } = {}
		for d = 1, 4 do
			local nx, ny = cx + DX[d], cy + DY[d]
			if nx >= 0 and nx < W and ny >= 0 and ny < H and not visited[ny][nx] then
				table.insert(dirs, d)
			end
		end
		if #dirs == 0 then
			table.remove(stack)
		else
			local d = dirs[rng:NextInteger(1, #dirs)]
			setPassage(m, cx, cy, d, true)
			local nx, ny = cx + DX[d], cy + DY[d]
			visited[ny][nx] = true
			table.insert(stack, { nx, ny })
		end
	end
	-- bucles
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do
			if cx < W - 1 and not m.HE[cy][cx] and rng:NextNumber() < CONFIG.BRAID then
				m.HE[cy][cx] = true
			end
			if cy < H - 1 and not m.VS[cy][cx] and rng:NextNumber() < CONFIG.BRAID then
				m.VS[cy][cx] = true
			end
		end
	end
	return m, sx, sy
end

local function bfs(m: Maze, sx: number, sy: number): ({ [number]: number }, { [number]: number })
	local dist: { [number]: number } = {}
	local parent: { [number]: number } = {}
	local startId = sy * m.W + sx
	dist[startId] = 0
	local queue: { number } = { startId }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		local cx, cy = id % m.W, id // m.W
		for d = 1, 4 do
			if passage(m, cx, cy, d) then
				local nid = (cy + DY[d]) * m.W + (cx + DX[d])
				if dist[nid] == nil then
					dist[nid] = dist[id] + 1
					parent[nid] = id
					table.insert(queue, nid)
				end
			end
		end
	end
	return dist, parent
end

local function degree(m: Maze, cx: number, cy: number): number
	local n = 0
	for d = 1, 4 do
		if passage(m, cx, cy, d) then
			n += 1
		end
	end
	return n
end

-- abre los 4 muros interiores de un bloque 2x2 (sala grande). Devuelve lo que abrió para poder deshacerlo.
local function mergeBlock(m: Maze, bx: number, by: number): { { number } }
	local changed: { { number } } = {}
	local function openEdge(cx: number, cy: number, d: number)
		if not passage(m, cx, cy, d) then
			setPassage(m, cx, cy, d, true)
			table.insert(changed, { cx, cy, d })
		end
	end
	openEdge(bx, by, 2)
	openEdge(bx, by + 1, 2)
	openEdge(bx, by, 3)
	openEdge(bx + 1, by, 3)
	return changed
end

local function undoEdges(m: Maze, changed: { { number } })
	for _, c in ipairs(changed) do
		setPassage(m, c[1], c[2], c[3], false)
	end
end

---------------------------------------------------------------------
-- MONSTRUOS
---------------------------------------------------------------------
local function stripDefs(faction: string, strip: number): ({ MobCatalog.MobDef }, MobCatalog.MobDef?)
	local normals: { MobCatalog.MobDef } = {}
	local boss: MobCatalog.MobDef? = nil
	for _, d in ipairs(MobCatalog.All) do
		if d.Faction == faction and d.Strip == strip then
			if d.Boss then
				boss = boss or d
			else
				table.insert(normals, d)
			end
		end
	end
	table.sort(normals, function(a, b)
		return a.MinLevel < b.MinLevel
	end)
	return normals, boss
end

-- piso 1: niveles bajos y medios de la franja; piso 2: medios y altos. t = avance (0..1) por el recorrido.
local function pickDef(normals: { MobCatalog.MobDef }, floorIdx: number, t: number, rng: Random): MobCatalog.MobDef?
	if #normals == 0 then
		return nil
	end
	local lo = if floorIdx == 1 then 1 else 2
	local hi = if floorIdx == 1 then 2 else 3
	local x = lo + (hi - lo) * t + (rng:NextNumber() - 0.5) * 0.9
	local idx = math.clamp(math.floor(x + 0.5), lo, hi)
	return normals[math.min(idx, #normals)]
end

local function onSpawnDied(inst: Inst, kind: string)
	if inst.Closed then
		return
	end
	if kind == "guard" then
		inst.GuardianDead = true
		inst.Floor2Open = true
		if inst.P1Exit then
			inst.P1Exit.Set(true, "🌀 PISO 2 — portal abierto")
		end
		notifyAll(memberList(inst), "¡Guardián derrotado! El portal al piso 2 se abrió.")
	elseif kind == "boss" then
		inst.BossDead = true
		inst.ExpireAt = math.min(inst.ExpireAt, os.clock() + CONFIG.EXPIRE_AFTER_BOSS)
		if inst.P2Exit then
			inst.P2Exit.Set(true, "🌀 SALIDA — jefe derrotado")
		end
		notifyAll(memberList(inst), "¡Jefe de la cueva derrotado! La salida está abierta (la cueva se cierra en 5 min).")
	end
	-- el guardián y el jefe dejan su cofre en el centro de la cámara
	local f = if kind == "guard" then inst.F1 elseif kind == "boss" then inst.F2 else nil
	if f then
		local tier = if kind == "guard" then "Guardian" else "Final"
		task.delay(1.5, function()
			if inst.Closed then
				return
			end
			inst.Chests += 1
			buildChest(inst, f.Folder, f.ArenaCenter + Vector3.new(0, 0.8, 0), f.ExitCF.Position, tier)
			notifyAll(memberList(inst), if kind == "guard" then "💎 Apareció el COFRE DEL GUARDIÁN en el centro de la cámara. ¡Ábranlo juntos!" else "👑 Apareció el TESORO DEL JEFE en el centro de la cámara. ¡Ábranlo juntos!")
		end)
	end
end

local function spawnGroup(inst: Inst, g: Group)
	g.Done = true
	for _, sp in ipairs(g.Spawns) do
		local model = MobService.SpawnAt(sp.Def.Id, CFrame.new(sp.Pos), sp.Level)
		if model then
			if sp.Scale ~= 1 then
				model:ScaleTo(model:GetScale() * sp.Scale)
				model:PivotTo(model:GetPivot() + Vector3.new(0, 2, 0))
			end
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				local hp = math.max(1, math.floor(hum.MaxHealth * inst.HpMult * sp.HpF))
				hum.MaxHealth = hp
				hum.Health = hp
				model:SetAttribute("MaxHp", hp)
				if sp.Kind == "guard" or sp.Kind == "boss" then
					hum.Died:Once(function()
						onSpawnDied(inst, sp.Kind)
					end)
				end
			end
			model:SetAttribute("DmgBuff", inst.DmgMult)
			model:SetAttribute("BaseBuff", inst.DmgMult)
			model:SetAttribute("XpMult", inst.XpMult * sp.XpF)
			model:SetAttribute("Dungeon", inst.Id)
			table.insert(inst.Mobs, model)
		end
	end
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN DE UN PISO
---------------------------------------------------------------------
local function buildFloor(inst: Inst, idx: number, folder: Folder, o: Vector3, pal: Palette, rng: Random, normals: { MobCatalog.MobDef }, boss: MobCatalog.MobDef?): Floor
	local S, T, Hh = CONFIG.CELL, CONFIG.WALL, CONFIG.HEIGHT
	local W, H = CONFIG.GRID[idx][1], CONFIG.GRID[idx][2]
	local function cc(cx: number, cy: number): Vector3
		return o + Vector3.new((cx - (W - 1) / 2) * S, 0, (cy - (H - 1) / 2) * S)
	end

	-- 1) laberinto: se prueban varios y se queda el de mejor puntuación = camino largo + salida LEJOS del inicio en línea recta
	local maze: Maze? = nil
	local sx, sy, bestLen, bestScore, bestExit = 0, 0, -1, -1, 0
	for _ = 1, 12 do
		local m, x, y = genMaze(W, H, rng)
		local dist = bfs(m, x, y)
		local far = 0
		for _, d in pairs(dist) do
			far = math.max(far, d)
		end
		-- salida: entre las celdas casi tan lejanas como la más lejana, la más alejada del inicio en línea recta
		local pick, pickD = -1, -1
		for id, d in pairs(dist) do
			if d >= far * 0.9 then
				local straight = math.sqrt(((id % W) - x) ^ 2 + ((id // W) - y) ^ 2)
				if straight > pickD or (straight == pickD and id < pick) then
					pick, pickD = id, straight
				end
			end
		end
		local pathLen = dist[pick] or far
		local score = pathLen + pickD * 3
		if score > bestScore then
			maze, sx, sy, bestLen, bestScore, bestExit = m, x, y, pathLen, score, pick
		end
		if far >= CONFIG.MIN_PATH[idx] and pickD >= W * 0.6 then
			break
		end
	end
	local m = maze :: Maze
	local dist, parent = bfs(m, sx, sy)
	local startId = sy * W + sx
	local exitId = bestExit
	local ex, ey = exitId % W, exitId // W
	local path: { number } = {}
	do
		local id: number? = exitId
		while id ~= nil do
			table.insert(path, 1, id)
			id = parent[id]
		end
	end
	local onPath: { [number]: boolean } = {}
	for _, id in ipairs(path) do
		onPath[id] = true
	end
	local taken: { [number]: boolean } = { [startId] = true }
	local noPillar: { [number]: boolean } = {}
	local function blockOK(bx: number, by: number): boolean
		if bx < 0 or by < 0 or bx + 1 > W - 1 or by + 1 > H - 1 then
			return false
		end
		for dy = 0, 1 do
			for dx = 0, 1 do
				if taken[(by + dy) * W + bx + dx] then
					return false
				end
			end
		end
		return true
	end
	local function claim(bx: number, by: number)
		for dy = 0, 1 do
			for dx = 0, 1 do
				taken[(by + dy) * W + bx + dx] = true
			end
		end
		noPillar[(by + 1) * (W + 1) + (bx + 1)] = true
	end
	local function blockCenter(bx: number, by: number): Vector3
		return o + Vector3.new((bx + 1 - W / 2) * S, 0, (by + 1 - H / 2) * S)
	end

	-- 2) cámara final (guardián / jefe): bloque 2x2 que contiene la salida
	local arenaCenter = cc(ex, ey)
	local arenaBlock: { number }? = nil
	do
		local cands: { { number } } = {}
		for _, c in ipairs({ { ex, ey }, { ex - 1, ey }, { ex, ey - 1 }, { ex - 1, ey - 1 } }) do
			if blockOK(c[1], c[2]) then
				table.insert(cands, c)
			end
		end
		if #cands > 0 then
			local c = cands[rng:NextInteger(1, #cands)]
			mergeBlock(m, c[1], c[2])
			claim(c[1], c[2])
			arenaBlock = c
			arenaCenter = blockCenter(c[1], c[2])
		else
			taken[exitId] = true
		end
	end

	-- 3) salas al azar a lo largo del camino (se deshacen si acortan demasiado el recorrido)
	type Room = { Center: Vector3, Theme: string, T: number }
	local rooms: { Room } = {}
	local themes = { "lago", "columnas", "cristales" }
	local origLen = bestLen
	for r = 1, CONFIG.ROOMS_PER_FLOOR do
		local frac = r / (CONFIG.ROOMS_PER_FLOOR + 1)
		local base = math.floor(frac * #path) + 1
		local placed = false
		for _, off in ipairs({ 0, 1, -1, 2, -2, 3, -3, 4, -4 }) do
			local pid = path[math.clamp(base + off, 1, #path)]
			local px, py = pid % W, pid // W
			for _, c in ipairs({ { px, py }, { px - 1, py }, { px, py - 1 }, { px - 1, py - 1 } }) do
				if blockOK(c[1], c[2]) then
					local changed = mergeBlock(m, c[1], c[2])
					local d2 = bfs(m, sx, sy)
					if (d2[exitId] or 0) >= origLen * 0.8 then
						claim(c[1], c[2])
						table.insert(rooms, { Center = blockCenter(c[1], c[2]), Theme = themes[(r + rng:NextInteger(0, 2)) % 3 + 1], T = frac })
						placed = true
						break
					else
						undoEdges(m, changed)
					end
				end
			end
			if placed then
				break
			end
		end
	end
	local roomNames: { string } = {}
	for _, rm in ipairs(rooms) do
		table.insert(roomNames, rm.Theme)
	end

	-- ramales sin salida: los más lejanos del inicio llevan cofre (los más lejanos de todos son "raros")
	local fd = bfs(m, sx, sy)
	type Dead = { Id: number, Cx: number, Cy: number, Dir: number, D: number }
	local dead: { Dead } = {}
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do
			local id = cy * W + cx
			if not taken[id] and id ~= startId and id ~= exitId and degree(m, cx, cy) == 1 then
				local pd = 1
				for d = 1, 4 do
					if passage(m, cx, cy, d) then
						pd = d
					end
				end
				table.insert(dead, { Id = id, Cx = cx, Cy = cy, Dir = pd, D = fd[id] or 0 })
			end
		end
	end
	table.sort(dead, function(a: Dead, b: Dead): boolean
		if a.D ~= b.D then
			return a.D > b.D
		end
		return a.Id < b.Id
	end)
	local chestTier: { [number]: string } = {}
	for rank, dd in ipairs(dead) do
		if rank > CONFIG.CHESTS_PER_FLOOR then
			break
		end
		chestTier[dd.Id] = if rank <= CONFIG.RARE_CHESTS_PER_FLOOR then "Raro" else "Comun"
	end

	-- 4) geometría: suelo, techo, muros irregulares, pilares
	local FW, FH = W * S + T + 6, H * S + T + 6
	mk(folder, "Suelo", Vector3.new(FW, 2, FH), CFrame.new(o + Vector3.new(0, -1, 0)), pal.Floor, Enum.Material.Slate, true)
	local ceiling = mk(folder, "Techo", Vector3.new(FW, 3, FH), CFrame.new(o + Vector3.new(0, Hh + 1.5, 0)), pal.Wall, Enum.Material.Slate, true)
	ceiling.CastShadow = true -- el sol no atraviesa el techo (con el ambiente de cueva ya es de noche, esto es un seguro)
	local function chunks(slabPos: Vector3, alongX: boolean)
		for _ = 1, 4 do
			local w = 7 + rng:NextNumber() * 6
			local h = Hh * (0.35 + rng:NextNumber() * 0.65)
			local d = 3 + rng:NextNumber() * 2.5
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local along = (rng:NextNumber() - 0.5) * (S - T - w)
			local off = side * (T / 2 + d / 2 - 1)
			local p = if alongX then slabPos + Vector3.new(along, 0, off) else slabPos + Vector3.new(off, 0, along)
			local size = if alongX then Vector3.new(w, h, d) else Vector3.new(d, h, w)
			local cf = CFrame.new(p.X, o.Y + h / 2, p.Z) * CFrame.Angles((rng:NextNumber() - 0.5) * 0.12, (rng:NextNumber() - 0.5) * 0.5, (rng:NextNumber() - 0.5) * 0.12)
			mk(folder, "Roca", size, cf, pal.Wall:Lerp(pal.Floor, rng:NextNumber() * 0.45), Enum.Material.Rock, true)
		end
	end
	for cy = 0, H - 1 do -- muros verticales (a lo largo de Z)
		for vx = 0, W do
			if vx == 0 or vx == W or not m.HE[cy][vx - 1] then
				local pos = o + Vector3.new((vx - W / 2) * S, Hh / 2, (cy - (H - 1) / 2) * S)
				mk(folder, "Muro", Vector3.new(T, Hh + 6, S - T + 1), CFrame.new(pos), pal.Wall:Lerp(pal.Floor, rng:NextNumber() * 0.18), Enum.Material.Slate, true)
				chunks(Vector3.new(pos.X, o.Y, pos.Z), false)
			end
		end
	end
	for vy = 0, H do -- muros horizontales (a lo largo de X)
		for cx = 0, W - 1 do
			if vy == 0 or vy == H or not m.VS[vy - 1][cx] then
				local pos = o + Vector3.new((cx - (W - 1) / 2) * S, Hh / 2, (vy - H / 2) * S)
				mk(folder, "Muro", Vector3.new(S - T + 1, Hh + 6, T), CFrame.new(pos), pal.Wall:Lerp(pal.Floor, rng:NextNumber() * 0.18), Enum.Material.Slate, true)
				chunks(Vector3.new(pos.X, o.Y, pos.Z), true)
			end
		end
	end
	for vy = 0, H do
		for vx = 0, W do
			if not noPillar[vy * (W + 1) + vx] then
				mk(folder, "Pilar", Vector3.new(T, Hh + 6, T), CFrame.new(o + Vector3.new((vx - W / 2) * S, Hh / 2, (vy - H / 2) * S)), pal.Wall, Enum.Material.Slate, true)
			end
		end
	end

	-- 5) detalle de cada celda: manchas de suelo, estalagmitas, estalactitas; antorchas en el camino, cristales en las ramas;
	--    escombros, huesos, cajas, hongos, charcos, columnas rotas, raíces y polvo en el aire
	local nonPathCount = 0
	local wallMid = pal.Wall:Lerp(pal.Floor, 0.5)
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do
			local id = cy * W + cx
			local c = cc(cx, cy)
			local patch = cyl(folder, "Mancha", 10 + rng:NextNumber() * 12, 0.12, c + Vector3.new((rng:NextNumber() - 0.5) * 14, 0.07, (rng:NextNumber() - 0.5) * 14), pal.Floor:Lerp(Color3.new(0, 0, 0), 0.12 + rng:NextNumber() * 0.25), Enum.Material.Mud, false)
			patch.CanQuery = false
			spike(folder, c + Vector3.new((rng:NextNumber() - 0.5) * 20, 0, (rng:NextNumber() - 0.5) * 20), true, 4 + rng:NextNumber() * 6, 1.4 + rng:NextNumber() * 1.6, wallMid, rng)
			spike(folder, c + Vector3.new((rng:NextNumber() - 0.5) * 20, Hh - 1, (rng:NextNumber() - 0.5) * 20), false, 6 + rng:NextNumber() * 9, 1.6 + rng:NextNumber() * 2, pal.Wall, rng)
			if not taken[id] or id == startId then
				if onPath[id] then
					if cx % 2 == cy % 2 then
						local sxg = if rng:NextNumber() < 0.5 then -1 else 1
						local szg = if rng:NextNumber() < 0.5 then -1 else 1
						brazier(folder, c + Vector3.new(sxg * 11, 0, szg * 11), 1)
					end
				else
					nonPathCount += 1
					if nonPathCount % 2 == 0 then
						crystal(folder, c + Vector3.new((rng:NextNumber() - 0.5) * 22, 0, (rng:NextNumber() - 0.5) * 22), pal.Crystal, rng, false, nonPathCount % 4 == 0)
					end
				end
				if not taken[id] and not chestTier[id] then
					local r = rng:NextNumber()
					local rp = c + Vector3.new((rng:NextNumber() - 0.5) * 16, 0, (rng:NextNumber() - 0.5) * 16)
					if r < 0.06 then
						rubble(folder, rp, rng, wallMid)
					elseif r < 0.11 then
						bones(folder, rp, rng)
					elseif r < 0.15 and not onPath[id] then
						crateStack(folder, rp, rng)
					elseif r < 0.23 and not onPath[id] then
						mushrooms(folder, rp, pal.Crystal, rng)
					elseif r < 0.29 then
						puddle(folder, rp, pal.Lake, rng)
					elseif r < 0.33 then
						brokenColumn(folder, rp, pal.Wall:Lerp(pal.Floor, 0.3), rng)
					end
					if rng:NextNumber() < 0.12 then
						roots(folder, c, Hh, rng)
					end
				end
			end
			if (cx + cy) % 2 == 0 then
				dust(folder, c, Hh)
			end
		end
	end

	-- 6) decoración de las salas y de la cámara final
	for _, rm in ipairs(rooms) do
		local c = rm.Center
		if rm.Theme == "lago" then
			local lake = cyl(folder, "Lago", 30, 0.3, c + Vector3.new(0, 0.2, 0), pal.Lake:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.Glass, false)
			lake.Transparency = 0.3
			lake.Reflectance = 0.2
			addLight(lake, pal.Lake, 40, 1.1)
			local rim = cyl(folder, "OrillaLago", 31.5, 0.12, c + Vector3.new(0, 0.1, 0), pal.Lake, Enum.Material.Neon, false)
			glow(rim, 0.5)
			for i = 0, 9 do
				local a = i / 10 * math.pi * 2
				local rh = 4 + rng:NextNumber() * 5
				mk(folder, "Roca", Vector3.new(7, rh, 5), CFrame.lookAt(c + Vector3.new(math.cos(a) * 18, rh / 2, math.sin(a) * 18), c + Vector3.new(0, rh / 2, 0)), pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Rock, true)
			end
		elseif rm.Theme == "columnas" then
			for _, sxg in ipairs({ -1, 1 }) do
				for _, szg in ipairs({ -1, 1 }) do
					cyl(folder, "Columna", 5, Hh, c + Vector3.new(sxg * 14, Hh / 2, szg * 14), pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Basalt, true)
					crystal(folder, c + Vector3.new(sxg * 14, 0, szg * 14 + szg * 4), pal.Crystal, rng, false, true)
				end
			end
		else
			for i = 1, 7 do
				local a = rng:NextNumber() * math.pi * 2
				local r = 3 + rng:NextNumber() * 9
				crystal(folder, c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r), pal.Crystal, rng, true, i % 3 == 0)
			end
		end
	end
	local arenaColor = pal.Crystal
	do -- cámara final: tarima de piedra con anillos de runas tenues
		local c = arenaCenter
		local k = if arenaBlock then 1 else 0.5
		dais(folder, c, pal.Floor:Lerp(pal.Wall, 0.25), k)
		local ring = cyl(folder, "Runas", 46 * k, 0.2, c + Vector3.new(0, 0.45, 0), arenaColor, Enum.Material.Neon, false)
		glow(ring, 0.6)
		local ring2 = cyl(folder, "Runas", 30 * k, 0.2, c + Vector3.new(0, 0.85, 0), arenaColor, Enum.Material.Neon, false)
		glow(ring2, 0.72)
	end

	-- 7) manadas, campeones, cofres, guardián / jefe (aparecen cuando alguien se acerca POR EL CAMINO del laberinto)
	local extra = math.floor((inst.N - 1) * CONFIG.PACK_EXTRA_PER_PLAYER + 0.5)
	local function addGroup(center: Vector3, spawns: { Spawn }, reach: number?)
		if #spawns > 0 then
			table.insert(inst.Groups, { Center = center, Spawns = spawns, Floor = idx, Done = false, Reach = reach or CONFIG.ACTIVATE_CELLS })
		end
	end
	local function packAt(center: Vector3, size: number, t: number, champion: boolean)
		local spawns: { Spawn } = {}
		for i = 1, size do
			local def = pickDef(normals, idx, t, rng)
			if def then
				local ang = rng:NextNumber() * math.pi * 2
				local r = 2 + rng:NextNumber() * 6
				local champ = champion and i == 1
				table.insert(spawns, {
					Pos = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r),
					Def = def,
					Level = rng:NextInteger(def.MinLevel, def.MaxLevel),
					HpF = if champ then CONFIG.CHAMPION_HP else 1,
					Scale = if champ then CONFIG.CHAMPION_SCALE else 1,
					XpF = if champ then CONFIG.CHAMPION_XP else 1,
					Kind = "mob",
				})
			end
		end
		addGroup(center, spawns)
	end
	local packCount = 0
	local i = 4
	while i <= #path - 3 do
		local id = path[i]
		if not taken[id] then
			packCount += 1
			local c = cc(id % W, id // W) + Vector3.new((rng:NextNumber() - 0.5) * 10, 0, (rng:NextNumber() - 0.5) * 10)
			packAt(c, CONFIG.PACK_SIZE[idx] + extra, i / #path, packCount % 3 == 0)
		end
		i += CONFIG.PACK_EVERY
	end
	for _, rm in ipairs(rooms) do
		packAt(rm.Center + Vector3.new(0, 0, 0), CONFIG.PACK_SIZE[idx] + 2 + extra, rm.T, true)
	end
	-- cofres en los ramales sin salida (los raros siempre con un campeón y su manada; los comunes a veces) y manadas sueltas
	local chestCount = 0
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do
			local id = cy * W + cx
			local tier = chestTier[id]
			local c = cc(cx, cy)
			if tier then
				local pd = 1
				for d = 1, 4 do
					if passage(m, cx, cy, d) then
						pd = d
					end
				end
				chestCount += 1
				buildChest(inst, folder, c - DIRV[pd] * 9, c + DIRV[pd] * 20, tier)
				if tier == "Raro" or rng:NextNumber() < 0.35 then
					packAt(c + DIRV[pd] * 5, 3 + extra, 0.7, true)
				end
			elseif not taken[id] and id ~= startId and id ~= exitId and not onPath[id] and rng:NextNumber() < 0.12 then
				packAt(c, 2 + extra, 0.5, false)
			end
		end
	end
	inst.Chests += chestCount
	-- guardián (piso 1) o jefe (piso 2) en la cámara final: solo aparecen cuando te acercas a ella
	local guardDef = normals[#normals]
	local arenaSpawn = arenaCenter + Vector3.new(0, 1, 0)
	if idx == 1 and guardDef then
		addGroup(arenaCenter, { { Pos = arenaSpawn, Def = guardDef, Level = guardDef.MaxLevel, HpF = CONFIG.GUARDIAN_HP, Scale = CONFIG.GUARDIAN_SCALE, XpF = CONFIG.GUARDIAN_XP, Kind = "guard" } }, CONFIG.ACTIVATE_CELLS_BOSS)
	elseif idx == 2 then
		local bd = boss or guardDef
		if bd then
			addGroup(arenaCenter, { { Pos = arenaSpawn, Def = bd, Level = nil, HpF = if boss then CONFIG.BOSS_HP_FACTOR else CONFIG.GUARDIAN_HP, Scale = 1, XpF = 1, Kind = "boss" } }, CONFIG.ACTIVATE_CELLS_BOSS)
		end
	end

	-- 8) portales: entrada (pared sur de la celda de inicio) y salida (pared cerrada de la cámara final)
	local startC = cc(sx, sy)
	local backPos = startC + Vector3.new(0, 0, S / 2 - T / 2 - 10)
	local backCF = CFrame.lookAt(backPos, backPos + Vector3.new(0, 0, -1))
	local arrive = CFrame.lookAt(startC + Vector3.new(0, 4, -5), startC + Vector3.new(0, 4, -15))
	local exitCF = CFrame.lookAt(arenaCenter + Vector3.new(0, 0, -(S / 2)), arenaCenter + Vector3.new(0, 0, 0))
	do
		local cands: { { any } } = {}
		local cells: { { number } } = { { ex, ey } }
		if arenaBlock then
			cells = { { arenaBlock[1], arenaBlock[2] }, { arenaBlock[1] + 1, arenaBlock[2] }, { arenaBlock[1], arenaBlock[2] + 1 }, { arenaBlock[1] + 1, arenaBlock[2] + 1 } }
		end
		local inBlock: { [number]: boolean } = {}
		for _, cell in ipairs(cells) do
			inBlock[cell[2] * W + cell[1]] = true
		end
		for _, cell in ipairs(cells) do
			for d = 1, 4 do
				local nx, ny = cell[1] + DX[d], cell[2] + DY[d]
				local outside = not inBlock[ny * W + nx] or nx < 0 or ny < 0 or nx >= W or ny >= H
				if outside and not passage(m, cell[1], cell[2], d) then
					table.insert(cands, { cell[1], cell[2], d })
				end
			end
		end
		if #cands > 0 then
			local pick = cands[rng:NextInteger(1, #cands)]
			local c = cc(pick[1] :: number, pick[2] :: number)
			local d = pick[3] :: number
			local pos = c + DIRV[d] * (S / 2 - T / 2 - 10)
			exitCF = CFrame.lookAt(pos, pos - DIRV[d])
		end
	end
	-- columnas y estandartes de la cámara final (sin tapar el arco de salida)
	if arenaBlock then
		local banCol = (FACTION_COLOR[inst.Faction] or Color3.fromRGB(200, 60, 60)):Lerp(Color3.new(0, 0, 0), 0.5)
		for i2 = 0, 7 do
			local a = i2 / 8 * math.pi * 2 + math.pi / 8
			local cp = arenaCenter + Vector3.new(math.cos(a) * 27, Hh / 2, math.sin(a) * 27)
			local flat = Vector3.new(cp.X - exitCF.Position.X, 0, cp.Z - exitCF.Position.Z)
			if flat.Magnitude > 16 then
				cyl(folder, "Columna", 4, Hh, cp, pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Basalt, true)
				banner(folder, arenaCenter + Vector3.new(math.cos(a) * 24.4, 0, math.sin(a) * 24.4), arenaCenter, banCol, Hh)
			end
		end
	end
	-- datos del laberinto para los monstruos (línea de visión y camino por celdas, ver DungeonNav)
	local adj: { [number]: { boolean } } = {}
	for cy = 0, H - 1 do
		for cx = 0, W - 1 do
			adj[cy * W + cx] = { passage(m, cx, cy, 1), passage(m, cx, cy, 2), passage(m, cx, cy, 3), passage(m, cx, cy, 4) }
		end
	end
	-- longitud real del recorrido (después de abrir las salas)
	local finalDist = bfs(m, sx, sy)
	local realLen = (finalDist[exitId] or #path - 1) + 1
	return {
		Index = idx, Origin = o, Arrive = arrive, BackCF = backCF, ExitCF = exitCF, ArenaCenter = arenaCenter, PathLen = realLen, Rooms = roomNames,
		Folder = folder, Nav = { Origin = o, W = W, H = H, S = S, Adj = adj },
	}
end

---------------------------------------------------------------------
-- INSTANCIA
---------------------------------------------------------------------
local function insideBounds(inst: Inst, pos: Vector3): boolean
	local o = inst.Origin
	return math.abs(pos.X - o.X) <= 240 and pos.Z >= o.Z - 240 and pos.Z <= o.Z + CONFIG.FLOOR2_DZ + 240 and pos.Y >= o.Y - 40 and pos.Y <= o.Y + 140
end

local function closeInstance(inst: Inst, reason: string)
	if inst.Closed then
		return
	end
	inst.Closed = true
	for p in pairs(inst.Members) do
		if p.Parent then
			local r = rootOf(p)
			if r and insideBounds(inst, r.Position) then
				moveTo(p, inst.ExitCF)
			end
			p:SetAttribute("InDungeon", nil)
			notify(p, reason)
		end
		if instOf[p] == inst then
			instOf[p] = nil
		end
	end
	for _, m in ipairs(inst.Mobs) do
		if m.Parent then
			MobService.Despawn(m)
		end
	end
	inst.Folder:Destroy()
	slotUsed[inst.Slot] = nil
	DungeonNav.Unregister(inst.Id)
	instances[inst.Id] = nil
end

local function difficultyText(n: number, hp: number, dmg: number, xp: number, loot: number, simulated: boolean): string
	local tag = if simulated then "[PRUEBA: grupo simulado] " else ""
	if n <= 1 then
		return tag .. "Dificultad normal (en solitario)"
	end
	return string.format("%sGrupo de %d: monstruos +%d%% vida, +%d%% daño, manadas más grandes · XP x%.1f · premios +%d%%", tag, n, math.floor((hp - 1) * 100 + 0.5), math.floor((dmg - 1) * 100 + 0.5), xp, math.floor((loot - 1) * 100 + 0.5))
end

local function createInstance(strip: number, faction: string, group: { Player }, exitCF: CFrame, rarityName: string?): Inst?
	local slot: number? = nil
	for i = 0, CONFIG.SLOT_COUNT - 1 do
		if not slotUsed[i] then
			slot = i
			break
		end
	end
	if not slot then
		return nil
	end
	slotUsed[slot] = true
	nextId += 1
	local rar = RARITY[rarityName or "Normal"] or RARITY.Normal
	local n = if CONFIG.TEST_ONLY and CONFIG.TEST_SIM_GROUP > #group then CONFIG.TEST_SIM_GROUP else #group -- en pruebas se puede simular un grupo
	local o = CONFIG.ORIGIN + Vector3.new((slot % CONFIG.SLOT_COLS) * CONFIG.SLOT_DX, 0, math.floor(slot / CONFIG.SLOT_COLS) * CONFIG.SLOT_DZ)
	local rng = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "Cueva_" .. nextId
	folder:SetAttribute("Strip", strip)
	folder:SetAttribute("Faction", faction)
	folder.Parent = Workspace

	local inst: Inst = {
		Id = nextId, Slot = slot, Strip = strip, Faction = faction, N = n, Members = {}, Folder = folder, Origin = o, ExitCF = exitCF,
		F1 = nil, F2 = nil, Rng = rng,
		HpMult = (1 + CONFIG.HP_PER_EXTRA * (n - 1)) * rar.Hp,
		DmgMult = (1 + CONFIG.DMG_PER_EXTRA * (n - 1)) * rar.Dmg,
		XpMult = (1 + CONFIG.XP_PER_EXTRA * (n - 1)) * rar.Xp,
		RewardMult = (1 + REWARD.PER_EXTRA * (n - 1)) * rar.Loot,
		Simulated = n ~= #group,
		Mobs = {}, Groups = {}, GuardianDead = false, Floor2Open = false, BossDead = false, P1Exit = nil, P2Exit = nil,
		ExpireAt = os.clock() + CONFIG.TTL, EmptySince = nil, Warned = false, Closed = false, Chests = 0, ChestsOpened = 0,
	}
	instances[inst.Id] = inst
	-- los miembros se anotan ya (antes de construir) para que nadie vuelva a entrar mientras se arma la cueva
	for _, m in ipairs(group) do
		inst.Members[m] = true
		instOf[m] = inst
	end

	local pal = PALETTE[strip] or PALETTE[1]
	local normals, boss = stripDefs(faction, strip)
	local floor1 = Instance.new("Folder")
	floor1.Name = "Piso1"
	floor1.Parent = folder
	local floor2 = Instance.new("Folder")
	floor2.Name = "Piso2"
	floor2.Parent = folder
	local f1 = buildFloor(inst, 1, floor1, o, pal, rng, normals, boss)
	local f2 = buildFloor(inst, 2, floor2, o + Vector3.new(0, 0, CONFIG.FLOOR2_DZ), pal, rng, normals, boss)
	inst.F1, inst.F2 = f1, f2
	DungeonNav.Register(inst.Id, folder, { f1.Nav, f2.Nav })
	local color = FACTION_COLOR[faction] or Color3.fromRGB(255, 255, 255)

	local function memberOnly(p: Player): boolean
		if instOf[p] ~= inst or inst.Closed then
			notify(p, "Este portal es de otra cueva")
			return false
		end
		return true
	end
	makeArch(floor1, "Portal_Salida_P1", f1.BackCF, Color3.fromRGB(255, 220, 140), 0.8, "🏠 SALIR DE LA CUEVA", "Salir", "Volver a la franja", function(p)
		if memberOnly(p) then
			moveTo(p, inst.ExitCF)
		end
	end).Set(true, "🏠 SALIR DE LA CUEVA")
	local p1 = makeArch(floor1, "Portal_Piso2", f1.ExitCF, color, 0.85, "", "Bajar", "Piso 2", function(p)
		if memberOnly(p) and inst.Floor2Open then
			moveTo(p, f2.Arrive)
		end
	end)
	p1.Set(false, "🔒 PISO 2 — derrota al Guardián")
	inst.P1Exit = p1
	makeArch(floor2, "Portal_Piso1", f2.BackCF, Color3.fromRGB(180, 200, 255), 0.8, "⬆ VOLVER AL PISO 1", "Subir", "Piso 1", function(p)
		if memberOnly(p) then
			moveTo(p, CFrame.new(f1.ExitCF.Position + f1.ExitCF.LookVector * 14 + Vector3.new(0, 4, 0)))
		end
	end).Set(true, "⬆ VOLVER AL PISO 1")
	local p2 = makeArch(floor2, "Portal_Salida_P2", f2.ExitCF, Color3.fromRGB(255, 220, 140), 0.85, "", "Salir", "Cueva completada", function(p)
		if memberOnly(p) and inst.BossDead then
			instOf[p] = nil -- cueva completada: ya no se puede volver a entrar
			inst.Members[p] = nil
			p:SetAttribute("InDungeon", nil)
			moveTo(p, inst.ExitCF)
		end
	end)
	p2.Set(false, "🔒 SALIDA — derrota al jefe")
	inst.P2Exit = p2
	return inst
end

---------------------------------------------------------------------
-- ENTRAR
---------------------------------------------------------------------
local function tryEnter(player: Player, strip: number, faction: string, portalPos: Vector3, exitCF: CFrame)
	if entering[player] then
		return
	end
	if not testAllowed(player) then
		notify(player, "🕳️ Las cuevas llegan PRÓXIMAMENTE")
		return
	end
	-- ¿ya tiene una cueva abierta? vuelve a entrar gratis
	local existing = instOf[player]
	if existing and not existing.Closed then
		local ef1, ef2 = existing.F1, existing.F2
		if not ef1 or not ef2 then
			return -- todavía se está construyendo
		end
		local r = rootOf(player)
		if r and insideBounds(existing, r.Position) then
			return
		end
		moveTo(player, if existing.Floor2Open then ef2.Arrive else ef1.Arrive)
		notify(player, "Volviste a tu cueva (no gastas otra entrada)")
		return
	end
	if player:GetAttribute("Faction") ~= faction then
		notify(player, "Este portal es de la facción " .. faction)
		return
	end
	-- grupo: miembros del party cerca del portal
	local party = PartyService.MembersOf(player)
	local group: { Player } = {}
	local near = Vector3.new(portalPos.X, 0, portalPos.Z)
	for _, m in ipairs(party) do
		local r = rootOf(m)
		if m.Parent and r and not instOf[m] and not entering[m] and (Vector3.new(r.Position.X, 0, r.Position.Z) - near).Magnitude <= CONFIG.PARTY_RADIUS then
			table.insert(group, m)
		end
	end
	if not table.find(group, player) then
		table.insert(group, player)
	end
	-- comprobaciones: se avisa a TODO el grupo con el nombre de quien no puede
	local blockers: { string } = {}
	for _, m in ipairs(group) do
		if not testAllowed(m) then
			table.insert(blockers, string.format("%s: cuevas PRÓXIMAMENTE", m.DisplayName))
		elseif not freeEntry(m) then
			if LevelService.GetLevel(m) < CONFIG.MIN_LEVEL[strip] then
				table.insert(blockers, string.format("%s no llega al nivel %d", m.DisplayName, CONFIG.MIN_LEVEL[strip]))
			elseif entriesLeft(m, strip) <= 0 then
				table.insert(blockers, string.format("%s ya usó las entradas diarias de la Franja %d", m.DisplayName, strip))
			end
		end
	end
	if #blockers > 0 then
		notifyAll(party, "⛔ No pueden entrar: " .. table.concat(blockers, " · "))
		if #party > 1 then
			notifyAll(party, "Saquen del grupo a esa persona o entren sin ella.")
		end
		return
	end
	if #group > CONFIG.MAX_GROUP then
		notifyAll(party, string.format("Máximo %d jugadores por cueva (están %d cerca del portal). Que algunos se alejen del portal.", CONFIG.MAX_GROUP, #group))
		return
	end
	for _, m in ipairs(group) do
		entering[m] = true
	end
	notifyAll(group, "Se abre la cueva… (se está generando)")
	local ok, res = pcall(createInstance, strip, faction, group, exitCF, nil)
	local inst: Inst? = if ok then (res :: Inst?) else nil
	if not ok then
		warn("[DungeonService] Error al crear la cueva: " .. tostring(res))
		for _, m in ipairs(group) do
			local broken = instOf[m]
			if broken then
				closeInstance(broken, "No se pudo crear la cueva (error). Mira la consola Output y avisa.")
			end
		end
	end
	if not inst or not inst.F1 then
		for _, m in ipairs(group) do
			entering[m] = nil
		end
		if ok then
			notifyAll(group, "Todas las cuevas están ocupadas. Inténtalo en un momento.")
		end
		return
	end
	local f1 = inst.F1 :: Floor
	for _, m in ipairs(group) do
		if not freeEntry(m) then
			useEntry(m, strip)
		end
		entering[m] = nil
	end
	local text = difficultyText(inst.N, inst.HpMult, inst.DmgMult, inst.XpMult, inst.RewardMult, inst.Simulated)
	for _, m in ipairs(group) do
		notify(m, string.format("Cueva de la Franja %d · %d manadas · 2 pisos de %d y %d galerías hasta el fondo · entradas restantes hoy: %d", strip, #inst.Groups, f1.PathLen, if inst.F2 then (inst.F2 :: Floor).PathLen else 0, entriesLeft(m, strip)))
		notify(m, text)
		moveTo(m, f1.Arrive)
	end
end

---------------------------------------------------------------------
-- PORTALES DE ENTRADA EN EL MUNDO (un arco por facción y franja)
---------------------------------------------------------------------
type Lane = { Faction: string, Strip: number, Start: Vector3, Dir: Vector3, FanC: number, FanK: number, U0: number, U1: number, FloorY: number }

local function readLanes(): { Lane }
	local found: { [string]: Lane } = {}
	for _, p in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if p:IsA("BasePart") then
			local biome, strip = p:GetAttribute("Biome"), p:GetAttribute("Strip")
			local ls, ld = p:GetAttribute("LaneStart"), p:GetAttribute("LaneDir")
			local fc, fk = p:GetAttribute("FanC"), p:GetAttribute("FanK")
			local u0, u1 = p:GetAttribute("UStart"), p:GetAttribute("UEnd")
			if typeof(biome) == "string" and typeof(strip) == "number" and BIOME_FACTION[biome] and typeof(ls) == "Vector3" and typeof(ld) == "Vector3"
				and typeof(fc) == "number" and typeof(fk) == "number" and typeof(u0) == "number" and typeof(u1) == "number" then
				local key = biome .. "_" .. strip
				if not found[key] then
					found[key] = { Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld, FanC = fc, FanK = fk, U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2 }
				end
			end
		end
	end
	local out: { Lane } = {}
	for _, l in pairs(found) do
		table.insert(out, l)
	end
	table.sort(out, function(a, b)
		if a.Faction ~= b.Faction then
			return a.Faction < b.Faction
		end
		return a.Strip < b.Strip
	end)
	return out
end

local function buildEntrances(): boolean
	local lanes = readLanes()
	if #lanes == 0 then
		return false
	end
	local old = Workspace:FindFirstChild("PortalesCueva")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "PortalesCueva"
	root.Parent = Workspace
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { root }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	for _, l in ipairs(lanes) do
		local u = l.U0 + (l.U1 - l.U0) * 0.07
		local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
		local half = math.max(14, l.FanC + l.FanK * u - 22)
		local v = half * 0.5
		local p = l.Start + l.Dir * u + side * v
		local hit = Workspace:Raycast(Vector3.new(p.X, l.FloorY + 60, p.Z), Vector3.new(0, -140, 0), rayParams)
		local pos = Vector3.new(p.X, if hit then hit.Position.Y else l.FloorY, p.Z)
		local exitCF = CFrame.lookAt(pos + l.Dir * 16 + Vector3.new(0, 4, 0), pos + l.Dir * 30 + Vector3.new(0, 4, 0))
		local color = FACTION_COLOR[l.Faction] or Color3.new(1, 1, 1)
		local strip, faction = l.Strip, l.Faction
		local title = if CONFIG.TEST_ONLY then string.format("🕳️ CUEVA — FRANJA %d\n🔒 PRÓXIMAMENTE", strip) else string.format("🕳️ CUEVA — FRANJA %d", strip)
		makeArch(root, string.format("Portal_Cueva_%s_%d", faction, strip), CFrame.lookAt(pos, pos + l.Dir), color, 1, title, "Entrar", string.format("Cueva · Franja %d (solo o en grupo)", strip), function(pl)
			tryEnter(pl, strip, faction, pos, exitCF)
		end)
		local ns = Instance.new("Part") -- nadie nace encima del portal
		ns.Name = "SinMobs"
		ns.Anchored, ns.CanCollide, ns.CanQuery, ns.CanTouch = true, false, false, false
		ns.Transparency = 1
		ns.Size = Vector3.new(44, 20, 44)
		ns.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
		ns.Parent = root
		CollectionService:AddTag(ns, "MobNoSpawn")
	end
	print(string.format("[DungeonService] %d portales de cueva creados.", #lanes))
	return true
end

task.spawn(function()
	for _ = 1, 180 do
		if buildEntrances() then
			return
		end
		task.wait(1)
	end
	warn("[DungeonService] No se encontraron las losas ZonePvE: no se crearon los portales de cueva.")
end)

---------------------------------------------------------------------
-- CICLO DE VIDA
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, inst in pairs(table.clone(instances)) do
			if inst.Closed or not inst.F1 then
				continue
			end
			local insideCount = 0
			local rootsIn: { Vector3 } = {}
			for p in pairs(inst.Members) do
				local r = if p.Parent then rootOf(p) else nil
				local inside = r ~= nil and insideBounds(inst, (r :: BasePart).Position)
				if p.Parent then
					p:SetAttribute("InDungeon", if inside then inst.Strip else nil)
				end
				if inside and r then
					insideCount += 1
					table.insert(rootsIn, r.Position)
				end
			end
			-- aparecen las manadas cercanas a alguien
			for _, g in ipairs(inst.Groups) do
				if not g.Done then
					for _, pos in ipairs(rootsIn) do
						local steps = DungeonNav.CellDistance(inst.Id, pos, g.Center)
						if steps ~= nil and steps <= g.Reach then
							g.Done = true
							task.spawn(spawnGroup, inst, g)
							break
						end
					end
				end
			end
			if insideCount > 0 then
				inst.EmptySince = nil
			else
				inst.EmptySince = inst.EmptySince or now
				if now - (inst.EmptySince :: number) >= CONFIG.EMPTY_CLOSE then
					closeInstance(inst, "Tu cueva se cerró por estar vacía")
					continue
				end
			end
			if now >= inst.ExpireAt then
				closeInstance(inst, "La cueva se desvaneció")
			elseif not inst.Warned and inst.ExpireAt - now <= 120 then
				inst.Warned = true
				notifyAll(memberList(inst), "La cueva se cierra en 2 minutos")
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	entering[p] = nil
	local inst = instOf[p]
	instOf[p] = nil
	if inst then
		inst.Members[p] = nil
	end
end)

-- API
function DungeonService.EntriesLeft(player: Player, strip: number): number
	return entriesLeft(player, strip)
end

DungeonService.Config = CONFIG
DungeonService.Rarity = RARITY

print("[DungeonService] Listo: cuevas-laberinto por franja (2 pisos, 3 salas, cofres, manadas).")
return DungeonService
