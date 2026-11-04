--!strict
--[[
    PveZoneService (ModuleScript) -> ServerScriptService.Services.PveZoneService
    PUNTOS DE INTERÉS de las 16 franjas PvE (4 por facción). Se construye solo sobre las losas del mapa (tag "ZonePvE"):
      CAMPAMENTO (franjas 2, 3 y 4, a mitad de la franja; la franja 1 no lo necesita: está pegada a la ciudad y la ciudad también regenera): zona segura (los mobs te pierden de vista y no nace ningún grupo dentro),
          regenera vida y energía, hoguera para FIJAR el punto de reaparición (si mueres en esa franja vuelves al campamento
          y no a la ciudad) y olla de ALQUIMIA (abre la misma ventana del Alquimista: pociones x1/x10/x50/x100/Máx con los recursos). Dentro del campamento NO se puede atacar. Aquí NO hay mercader.
      ALTAR DE OFRENDA: entregas recursos + material de la franja + oro y recibes una tirada de equipo mejor que la de un mob. Enfriamiento por jugador.
      ALTAR DE DESAFÍO: 3 oleadas de monstruos de la franja; premio personal para todos los que estén cerca al terminar. Enfriamiento del altar,
          tope diario por jugador y por franja, y si alguien de tu grupo tiene un desafío en curso no puedes iniciar otro hasta que termine.
      COFRES (3 por franja): están sellados: se abren con una LLAVE de su franja, que cae de los monstruos de esa franja con tope diario por jugador
          (LootTables.Daily.Keys; las llaves sobrantes caducan al cambiar el día, no se venden ni se intercambian). Rara vez salen "mejorados".
      MINI JEFE (1 por franja): un mob fuerte de la zona (vida x3 a x5, más grande), botín propio. Reaparece a los 8 min.
          Tope diario por jugador y por franja: al agotarlo no puedes ni pegarle, y si se muere no te da nada.
      NODOS DE RECOLECCIÓN (10 por franja): dan el recurso de la franja (Hierba, Cristal, Reliquia, Corazón) que sirve para cocinar y para la ofrenda.
    Todos los números (probabilidades, costos, tiempos) están en ReplicatedStorage.Modules.LootTables (MiniBoss, MapChest, Offering, Challenge, Gathering, Daily, KeyDrop).
    El botín lo entrega LootService.Grant. Si el mapa se vuelve a construir, todo se rehace solo.
    Lee la geometría de cada carril de los atributos que deja ProjectBootstrapper en las losas (LaneStart, LaneDir, FanC, FanK, UStart, UEnd).
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local LootTables = require(Modules.LootTables)
local MobCatalog = require(Modules.MobCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local Inventory = require(Services.InventoryService)
local Wallet = require(Services.WalletService)
local LootService = require(Services.LootService)
local Energy = require(Services.EnergyRegenService)
local MobService = require(Services.Mobs.MobService)
local DamageService = require(Services.DamageService)
local DailyLimits = require(Services.DailyLimits)
local PartyService = require(Services.PartyService)
local Alchemist = require(Services.AlquimistaService)

local NotifyRemote = Net.Get("Notify")
local MAP_NAME = "Map_WC3_Style"
local STRIP_COUNT = 4

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

-- Colores y nombres por facción (decoración del campamento)
local FACTION_STYLE: { [string]: { Accent: Color3, Dark: Color3, Title: string, Camp: string } } = {
	Saiyan = { Accent = Color3.fromRGB(255, 170, 60), Dark = Color3.fromRGB(40, 48, 66), Title = "Comandante", Camp = "Campamento Saiyan" },
	Shinobi = { Accent = Color3.fromRGB(255, 120, 70), Dark = Color3.fromRGB(58, 46, 40), Title = "Líder", Camp = "Campamento Shinobi" },
	Pirate = { Accent = Color3.fromRGB(255, 200, 80), Dark = Color3.fromRGB(70, 48, 32), Title = "Capitán", Camp = "Campamento Pirata" },
	Shinigami = { Accent = Color3.fromRGB(150, 200, 255), Dark = Color3.fromRGB(190, 195, 205), Title = "Teniente", Camp = "Campamento Shinigami" },
}

-- Recurso de cada franja: color y forma del nodo
local NODE_COLOR: { Color3 } = {
	Color3.fromRGB(110, 220, 120),
	Color3.fromRGB(110, 190, 255),
	Color3.fromRGB(255, 200, 90),
	Color3.fromRGB(255, 90, 140),
}

-- Ajustes de colocación
local CAMP_U = 0.5 -- el campamento a mitad de la franja
local CAMP_FROM_STRIP = 2 -- la franja 1 no tiene campamento (está pegada a la ciudad)
local CAMP_RADIUS = 30 -- radio de la zona segura
local SAFE_BOX = 64
local EDGE_MARGIN = 62 -- distancia mínima a los muros laterales
local OBJECT_SPACING = 42
local EXTRA_OFFERINGS: { [number]: number } = { [3] = 2, [4] = 3 } -- altares de ofrenda ADICIONALES por franja (además del 1 de siempre)
local EXTRA_CHALLENGES: { [number]: number } = { [3] = 1, [4] = 2 } -- altares de desafío ADICIONALES por franja
local USE_DISTANCE = 26
local REGEN_PCT = 0.05 -- % de vida y energía por segundo dentro del campamento
local REST_COOLDOWN = 20

---------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------
type Lane = {
	Biome: string,
	Faction: string,
	Strip: number,
	Start: Vector3,
	Dir: Vector3,
	FanC: number,
	FanK: number,
	U0: number,
	U1: number,
	FloorY: number,
}

type Camp = { Key: string, Faction: string, Strip: number, Pos: Vector3, Respawn: CFrame }
type MiniSpot = { Lane: Lane, Pos: Vector3, Model: Model?, RespawnAt: number, Key: string }

local rng = Random.new()
local folder: Folder? = nil
local camps: { Camp } = {}
local minis: { MiniSpot } = {}
local campOf: { [Player]: { [string]: Camp } } = {} -- jugador -> franja -> campamento fijado
local lastRest: { [Player]: number } = {}
local offerCd: { [string]: number } = {} -- "<userId>|<altar>" -> hasta cuándo
local pendingRespawn: { [Player]: Camp } = {}
local buildToken = 0

local function notify(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

---------------------------------------------------------------------
-- Geometría del carril
---------------------------------------------------------------------
local function lanePoint(l: Lane, u: number, v: number): Vector3
	local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
	local p = l.Start + l.Dir * u + side * v
	return Vector3.new(p.X, l.FloorY, p.Z)
end

local function halfWidth(l: Lane, u: number): number
	return l.FanC + l.FanK * u
end

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
					found[key] = {
						Biome = biome, Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld,
						FanC = fc, FanK = fk, U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2,
					}
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

---------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------
local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = collide == true
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
	return p
end

local function cyl(parent: Instance, name: string, diameter: number, height: number, pos: Vector3, color: Color3, mat: Enum.Material, collide: boolean?): Part
	-- el cilindro de Roblox tiene su eje en X: se gira para dejarlo vertical
	return mk(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, mat, Enum.PartType.Cylinder, collide)
end

local function label(parent: BasePart, text: string, color: Color3, height: number, size: UDim2?)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Letrero"
	bb.Size = size or UDim2.fromOffset(220, 38)
	bb.StudsOffset = Vector3.new(0, height, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.35
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Parent = bb
	bb.Parent = parent
end

local function glow(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function prompt(parent: BasePart, action: string, object: string, hold: number, key: Enum.KeyCode?): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = 12
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = key or Enum.KeyCode.E
	pp.Parent = parent
	return pp
end

local function nearEnough(player: Player, pos: Vector3, dist: number): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and (root.Position - pos).Magnitude <= dist
end

local function itemName(id: string): string
	local m = (LootTables.Materials :: any)[id]
	return if m then m.Name else id
end

---------------------------------------------------------------------
-- CAMPAMENTO
---------------------------------------------------------------------
local function buildFactionProps(parent: Folder, faction: string, center: Vector3, style: { Accent: Color3, Dark: Color3, Title: string, Camp: string }, dir: Vector3)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local function at(f: number, r: number, y: number?): Vector3
		return center + dir * f + right * r + Vector3.new(0, y or 0, 0)
	end
	local lookCF = function(pos: Vector3): CFrame
		return CFrame.lookAt(pos, pos + dir)
	end
	if faction == "Saiyan" then
		-- cápsula Saiyan aterrizada (esfera blanca con escotilla y luz azul)
		local p = at(-14, -17, 7)
		mk(parent, "Capsula", Vector3.new(15, 15, 15), CFrame.new(p), Color3.fromRGB(235, 240, 248), Enum.Material.SmoothPlastic, Enum.PartType.Ball, true)
		mk(parent, "Escotilla", Vector3.new(7, 9, 0.8), CFrame.lookAt(p + dir * 6.6, p + dir * 12), Color3.fromRGB(90, 120, 160), Enum.Material.Glass)
		local lamp = mk(parent, "LuzCapsula", Vector3.new(2, 2, 2), CFrame.new(p + Vector3.new(0, 8.4, 0)), Color3.fromRGB(110, 190, 255), Enum.Material.Neon, Enum.PartType.Ball)
		glow(lamp, Color3.fromRGB(110, 190, 255), 18, 1.2)
		-- radar
		local rp = at(-10, 18, 0)
		cyl(parent, "RadarMastil", 1.2, 14, rp + Vector3.new(0, 7, 0), Color3.fromRGB(120, 130, 145), Enum.Material.Metal, true)
		mk(parent, "RadarPlato", Vector3.new(1, 8, 8), CFrame.new(rp + Vector3.new(0, 14.5, 0)) * CFrame.Angles(math.rad(25), 0, math.pi / 2), Color3.fromRGB(235, 235, 240), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif faction == "Shinobi" then
		-- tienda de campaña + cartelera de pergaminos
		local p = at(-14, -17, 0)
		local tent = Instance.new("WedgePart")
		tent.Name = "TiendaA"
		tent.Anchored = true
		tent.CanCollide = true
		tent.Size = Vector3.new(14, 9, 8)
		tent.CFrame = CFrame.lookAt(p + Vector3.new(0, 4.5, -4), p + Vector3.new(0, 4.5, -4) + dir) * CFrame.Angles(0, 0, 0)
		tent.Color = Color3.fromRGB(190, 170, 130)
		tent.Material = Enum.Material.Fabric
		tent.Parent = parent
		local tent2 = tent:Clone()
		tent2.Name = "TiendaB"
		tent2.CFrame = CFrame.lookAt(p + Vector3.new(0, 4.5, 4), p + Vector3.new(0, 4.5, 4) - dir) * CFrame.Angles(0, 0, 0)
		tent2.Parent = parent
		local rack = at(-10, 18, 0)
		mk(parent, "CarteleraPoste", Vector3.new(1, 10, 1), CFrame.new(rack + Vector3.new(-3, 5, 0)), Color3.fromRGB(110, 78, 50), Enum.Material.Wood, nil, true)
		mk(parent, "CarteleraPoste", Vector3.new(1, 10, 1), CFrame.new(rack + Vector3.new(3, 5, 0)), Color3.fromRGB(110, 78, 50), Enum.Material.Wood, nil, true)
		mk(parent, "Pergaminos", Vector3.new(8, 5, 0.5), lookCF(rack + Vector3.new(0, 6.5, 0)), Color3.fromRGB(235, 225, 195), Enum.Material.Fabric)
	elseif faction == "Pirate" then
		-- barriles, cajas y bandera
		for i = 0, 2 do
			local bp = at(-12 - i * 2, -16 + i * 4, 0)
			cyl(parent, "Barril", 4.2, 5, bp + Vector3.new(0, 2.5, 0), Color3.fromRGB(122, 80, 44), Enum.Material.Wood, true)
		end
		mk(parent, "Caja", Vector3.new(5, 5, 5), lookCF(at(-9, 17, 2.5)), Color3.fromRGB(140, 98, 58), Enum.Material.Wood, nil, true)
		mk(parent, "Caja", Vector3.new(4, 4, 4), lookCF(at(-12, 22, 2)), Color3.fromRGB(120, 84, 50), Enum.Material.Wood, nil, true)
		local fp = at(-14, 14, 0)
		cyl(parent, "MastilBandera", 0.9, 22, fp + Vector3.new(0, 11, 0), Color3.fromRGB(80, 56, 36), Enum.Material.Wood, true)
		mk(parent, "Bandera", Vector3.new(9, 6, 0.3), lookCF(fp + Vector3.new(4.6, 18, 0)), Color3.fromRGB(20, 20, 24), Enum.Material.Fabric)
		mk(parent, "Calavera", Vector3.new(2.6, 2.6, 0.4), lookCF(fp + Vector3.new(4.6, 18, 0.2)), Color3.fromRGB(240, 240, 240), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	else
		-- linterna de piedra + pequeño torii blanco
		local lp = at(-14, -17, 0)
		cyl(parent, "LinternaBase", 3, 5, lp + Vector3.new(0, 2.5, 0), Color3.fromRGB(205, 208, 215), Enum.Material.Slate, true)
		local lamp = mk(parent, "LinternaLuz", Vector3.new(3.4, 3.4, 3.4), CFrame.new(lp + Vector3.new(0, 6.6, 0)), Color3.fromRGB(160, 215, 255), Enum.Material.Neon)
		glow(lamp, Color3.fromRGB(160, 215, 255), 20, 1.4)
		mk(parent, "LinternaTecho", Vector3.new(6.6, 1.4, 6.6), CFrame.new(lp + Vector3.new(0, 8.8, 0)), Color3.fromRGB(190, 194, 202), Enum.Material.Slate, nil, true)
		local tp = at(-12, 18, 0)
		mk(parent, "ToriiPilar", Vector3.new(1.6, 14, 1.6), CFrame.new(tp + Vector3.new(0, 7, -6) + right * 0), Color3.fromRGB(240, 240, 244), Enum.Material.Marble, nil, true)
		mk(parent, "ToriiPilar", Vector3.new(1.6, 14, 1.6), CFrame.new(tp + Vector3.new(0, 7, 6)), Color3.fromRGB(240, 240, 244), Enum.Material.Marble, nil, true)
		mk(parent, "ToriiDintel", Vector3.new(2.2, 1.6, 16), CFrame.new(tp + Vector3.new(0, 14.2, 0)), Color3.fromRGB(240, 240, 244), Enum.Material.Marble)
		mk(parent, "ToriiBarra", Vector3.new(1.4, 1.1, 13), CFrame.new(tp + Vector3.new(0, 11.5, 0)), Color3.fromRGB(200, 205, 214), Enum.Material.Marble)
	end
end

local function buildCamp(l: Lane, root: Folder): Camp
	local style = FACTION_STYLE[l.Faction]
	local u = l.U0 + (l.U1 - l.U0) * CAMP_U
	local center = lanePoint(l, u, 0)
	local key = l.Faction .. "_" .. l.Strip
	local f = Instance.new("Folder")
	f.Name = "Campamento_" .. key
	f.Parent = root
	local dir = l.Dir

	-- suelo del campamento (disco ligeramente elevado)
	cyl(f, "Suelo", CAMP_RADIUS * 1.7, 0.5, center + Vector3.new(0, 0.25, 0), style.Dark:Lerp(Color3.new(0.2, 0.2, 0.2), 0.3), Enum.Material.Cobblestone, false)
	cyl(f, "AroSuelo", CAMP_RADIUS * 1.7 + 1.4, 0.4, center + Vector3.new(0, 0.2, 0), style.Accent, Enum.Material.Neon, false)

	-- hoguera central
	local fire = cyl(f, "Hoguera", 5, 1.2, center + Vector3.new(0, 0.9, 0), Color3.fromRGB(70, 60, 55), Enum.Material.Slate, true)
	for i = 1, 3 do
		local a = i * math.pi * 2 / 3
		mk(f, "Leño", Vector3.new(1.2, 1.2, 6), CFrame.new(center + Vector3.new(math.cos(a) * 1.3, 1.9, math.sin(a) * 1.3)) * CFrame.Angles(math.rad(20), a, 0), Color3.fromRGB(96, 62, 38), Enum.Material.Wood)
	end
	local flame = mk(f, "Llama", Vector3.new(3, 3, 3), CFrame.new(center + Vector3.new(0, 3.2, 0)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	flame.Transparency = 0.6
	local fx = Instance.new("Fire")
	fx.Heat = 8
	fx.Size = 7
	fx.Color = style.Accent
	fx.SecondaryColor = Color3.fromRGB(255, 80, 30)
	fx.Parent = flame
	glow(flame, style.Accent, 38, 1.6)
	for i = 1, 4 do -- asientos de troncos
		local a = i * math.pi / 2 + math.pi / 4
		mk(f, "Asiento", Vector3.new(5.5, 1.8, 1.8), CFrame.new(center + Vector3.new(math.cos(a) * 8.5, 1.1, math.sin(a) * 8.5)) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(110, 76, 48), Enum.Material.Wood, nil, true)
	end

	-- antorchas / mástiles en las 4 esquinas del campamento
	for i = 1, 4 do
		local a = i * math.pi / 2 + math.pi / 4
		local pp = center + Vector3.new(math.cos(a) * (CAMP_RADIUS - 3), 0, math.sin(a) * (CAMP_RADIUS - 3))
		cyl(f, "Mastil", 1, 12, pp + Vector3.new(0, 6, 0), style.Dark, Enum.Material.Wood, true)
		local lamp = mk(f, "Antorcha", Vector3.new(2, 2.4, 2), CFrame.new(pp + Vector3.new(0, 12.8, 0)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		glow(lamp, style.Accent, 22, 1.1)
	end

	buildFactionProps(f, l.Faction, center, style, dir)

	-- olla para cocinar
	local potPos = center + Vector3.new(0, 0, 0) + Vector3.new(dir.X, 0, dir.Z) * 13
	local pot = cyl(f, "Olla", 4, 3, potPos + Vector3.new(0, 1.9, 0), Color3.fromRGB(45, 45, 52), Enum.Material.Metal, true)
	cyl(f, "OllaCaldo", 3.4, 0.3, potPos + Vector3.new(0, 3.3, 0), Color3.fromRGB(120, 200, 110), Enum.Material.Neon, false)
	local potPrompt = prompt(pot, "Cocinar pociones", "Olla del campamento", 0.5, Enum.KeyCode.E)
	Alchemist.RegisterStation(pot)

	-- rótulo
	label(fire, string.format("%s · FRANJA %d", style.Camp, l.Strip), style.Accent, 11, UDim2.fromOffset(320, 40))
	label(pot, "Alquimia", Color3.new(1, 1, 1), 4, UDim2.fromOffset(140, 26))

	-- zona segura (los mobs te pierden de vista) y exclusión de nacimientos
	local safe = Instance.new("Part")
	safe.Name = "ZonaSegura"
	safe.Anchored = true
	safe.CanCollide = false
	safe.CanQuery = false
	safe.CanTouch = false
	safe.Transparency = 1
	safe.Size = Vector3.new(SAFE_BOX, 24, SAFE_BOX)
	safe.CFrame = CFrame.new(center + Vector3.new(0, 10, 0))
	safe:SetAttribute("Camp", key)
	safe.Parent = f
	CollectionService:AddTag(safe, "ZoneSafe")
	CollectionService:AddTag(safe, "ZoneCamp")

	local camp: Camp = { Key = key, Faction = l.Faction, Strip = l.Strip, Pos = center, Respawn = CFrame.lookAt(center + dir * 6 + Vector3.new(0, 4, 0), center + dir * 20 + Vector3.new(0, 4, 0)) }

	-- hoguera: fijar punto de reaparición + recuperación completa
	local rest = prompt(fire, "Descansar y fijar campamento", style.Camp, 1.2, Enum.KeyCode.E)
	rest.MaxActivationDistance = 14
	rest.Triggered:Connect(function(player: Player)
		if not nearEnough(player, center, CAMP_RADIUS + 10) then
			return
		end
		local now = os.clock()
		if (lastRest[player] or 0) + REST_COOLDOWN > now then
			notify(player, "Acabas de descansar: espera unos segundos")
			return
		end
		lastRest[player] = now
		campOf[player] = campOf[player] or {}
		;(campOf[player] :: any)[key] = camp
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = hum.MaxHealth
		end
		Energy.Refill(player)
		notify(player, string.format("Campamento fijado. Si mueres en la franja %d, reaparecerás aquí", l.Strip))
	end)

	-- olla: abre la ventana del Alquimista (pociones con los recursos; el servidor valida que estés cerca de la olla)
	potPrompt.Triggered:Connect(function(player: Player)
		if not nearEnough(player, potPos, USE_DISTANCE) then
			return
		end
		Alchemist.OpenAt(player, "Olla del campamento", "Cocina de campaña", l.Faction)
	end)

	table.insert(camps, camp)
	return camp
end

---------------------------------------------------------------------
-- ALTAR DE OFRENDA
---------------------------------------------------------------------
local function altarBase(parent: Folder, name: string, pos: Vector3, style: { Accent: Color3, Dark: Color3, Title: string, Camp: string }, tint: Color3): (Part, Part)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	cyl(f, "Base", 17, 1.4, pos + Vector3.new(0, 0.7, 0), style.Dark, Enum.Material.Slate, true)
	cyl(f, "BaseAro", 17.8, 0.5, pos + Vector3.new(0, 0.3, 0), tint, Enum.Material.Neon, false)
	cyl(f, "Pedestal", 5, 4.5, pos + Vector3.new(0, 3.6, 0), style.Dark:Lerp(Color3.new(0.1, 0.1, 0.12), 0.35), Enum.Material.Marble, true)
	local core = mk(f, "Nucleo", Vector3.new(3, 3, 3), CFrame.new(pos + Vector3.new(0, 7, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0), tint, Enum.Material.Neon)
	glow(core, tint, 30, 1.4)
	for i = 1, 4 do -- pilares
		local a = i * math.pi / 2 + math.pi / 4
		local pp = pos + Vector3.new(math.cos(a) * 7, 0, math.sin(a) * 7)
		mk(f, "Pilar", Vector3.new(1.8, 9, 1.8), CFrame.new(pp + Vector3.new(0, 5.2, 0)), style.Dark, Enum.Material.Marble, nil, true)
		mk(f, "PilarLuz", Vector3.new(2.2, 0.5, 2.2), CFrame.new(pp + Vector3.new(0, 9.9, 0)), tint, Enum.Material.Neon)
	end
	return core, f:FindFirstChild("Pedestal") :: Part
end

local function buildOffering(l: Lane, root: Folder, pos: Vector3, idx: number?)
	local style = FACTION_STYLE[l.Faction]
	local tint = Color3.fromRGB(190, 120, 255)
	local core, pedestal = altarBase(root, "AltarOfrenda_" .. l.Faction .. "_" .. l.Strip .. (if idx then "_" .. idx else ""), pos, style, tint)
	local O = LootTables.Offering
	local rid, mid = LootTables.StripResource[l.Strip], LootTables.StripMaterial[l.Strip]
	local rc, mc = O.ResourceCost[l.Strip], O.MaterialCost[l.Strip]
	local gold = math.floor(LootTables.GoldBase * LootTables.GoldGrowth ^ (l.Strip * 25 - 1) * O.GoldCostMult)
	label(core, "ALTAR DE OFRENDA", tint, 5, UDim2.fromOffset(260, 36))
	local pp = prompt(pedestal, string.format("Ofrenda: %d %s · %d %s · %d oro", rc, itemName(rid), mc, itemName(mid), gold), "Altar de Ofrenda", 1.5, Enum.KeyCode.E)
	pp.MaxActivationDistance = 14
	local altarKey = l.Faction .. "_" .. l.Strip
	pp.Triggered:Connect(function(player: Player)
		if not nearEnough(player, pos, USE_DISTANCE) then
			return
		end
		local cdKey = player.UserId .. "|" .. altarKey
		local now = os.clock()
		if (offerCd[cdKey] or 0) > now then
			notify(player, string.format("El altar descansa: vuelve en %d s", math.ceil((offerCd[cdKey] :: number) - now)))
			return
		end
		if Inventory.Count(player, rid) < rc or Inventory.Count(player, mid) < mc then
			notify(player, string.format("Ofrenda: necesitas %d %s, %d %s y %d de oro", rc, itemName(rid), mc, itemName(mid), gold))
			return
		end
		if not Wallet.TrySpendGold(player, gold, "Ofrenda") then
			notify(player, string.format("Ofrenda: necesitas %d de oro", gold))
			return
		end
		Inventory.Consume(player, rid, rc)
		Inventory.Consume(player, mid, mc)
		if LootService.Grant(player, "Offering", l.Strip) then
			offerCd[cdKey] = now + O.CooldownSeconds
		else
			-- la mochila no tenía lugar: se devuelve todo
			Inventory.Add(player, rid, rc)
			Inventory.Add(player, mid, mc)
			Wallet.AddGold(player, gold, "Ofrenda")
			notify(player, "Libera espacio en la mochila y vuelve a intentarlo (se devolvió tu ofrenda)")
		end
	end)
end

---------------------------------------------------------------------
-- ALTAR DE DESAFÍO
---------------------------------------------------------------------
-- Desafíos en curso: jugadores que participan ahora. Si alguien de tu grupo está en uno, tú no puedes iniciar otro (evita abrir varios a la vez)
local challengeBusy: { [Player]: boolean } = {}
local function groupInChallenge(player: Player): boolean
	for q in pairs(challengeBusy) do
		if q == player or (q.Parent ~= nil and PartyService.SameParty(player, q)) then
			return true
		end
	end
	return false
end

local function buildChallenge(l: Lane, root: Folder, pos: Vector3, idx: number?)
	local style = FACTION_STYLE[l.Faction]
	local tint = Color3.fromRGB(255, 80, 70)
	local core, pedestal = altarBase(root, "AltarDesafio_" .. l.Faction .. "_" .. l.Strip .. (if idx then "_" .. idx else ""), pos, style, tint)
	local X = LootTables.Challenge
	label(core, "ALTAR DE DESAFÍO", tint, 5, UDim2.fromOffset(260, 36))
	local state = { Busy = false, CooldownUntil = 0 }
	local pp = prompt(pedestal, "Iniciar desafío (3 oleadas)", "Altar de Desafío", 1.5, Enum.KeyCode.E)
	pp.MaxActivationDistance = 14

	local defs: { MobCatalog.MobDef } = {}
	for _, d in ipairs(MobCatalog.ForStrip(l.Faction, l.Strip)) do
		if not d.Boss then
			table.insert(defs, d)
		end
	end
	table.sort(defs, function(a, b)
		return a.MinLevel < b.MinLevel
	end)

	local function playersNear(): { Player }
		local out: { Player } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and nearEnough(p, pos, X.Radius) then
				table.insert(out, p)
			end
		end
		return out
	end

	local marked: { Player } = {} -- quienes participan en este desafío (se liberan al terminar)
	local function run()
		local alive: { Model } = {}
		local function cleanup()
			for _, m in ipairs(alive) do
				if m.Parent then
					MobService.Despawn(m)
				end
			end
			table.clear(alive)
		end
		local startedAt = os.clock()
		local failed = false
		for wave = 1, #X.WaveSizes do
			local def = defs[math.min(wave, #defs)]
			if not def then
				break
			end
			local who = playersNear()
			if #who == 0 then
				failed = true
				break
			end
			for _, p in ipairs(who) do
				challengeBusy[p] = true -- tú y tu grupo no pueden iniciar otro desafío hasta que este termine
				table.insert(marked, p)
				notify(p, string.format("Desafío: oleada %d de %d", wave, #X.WaveSizes))
			end
			local remaining = 0
			for i = 1, X.WaveSizes[wave] do
				local a = (i / X.WaveSizes[wave]) * math.pi * 2 + rng:NextNumber()
				local sp = pos + Vector3.new(math.cos(a) * 26, 0, math.sin(a) * 26)
				local target = who[(i - 1) % #who + 1].Character
				local m = MobService.SpawnWave(def.Id, CFrame.new(sp), def.MaxLevel, target)
				if m then
					table.insert(alive, m)
					remaining += 1
					local hum = m:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.Died:Once(function()
							remaining -= 1
						end)
					else
						remaining -= 1
					end
				end
			end
			while remaining > 0 do
				task.wait(1)
				if os.clock() - startedAt > X.TimeLimit or #playersNear() == 0 then
					failed = true
					break
				end
			end
			if failed then
				break
			end
			task.wait(2.5)
		end
		cleanup()
		if failed then
			for _, p in ipairs(Players:GetPlayers()) do
				if nearEnough(p, pos, X.Radius + 30) then
					notify(p, "Desafío fallido: el altar se apagó")
				end
			end
		else
			for _, p in ipairs(playersNear()) do
				LootService.Grant(p, "Challenge", l.Strip)
			end
		end
		state.CooldownUntil = os.clock() + X.CooldownSeconds
		state.Busy = false
	end

	local function runSafe(starter: Player)
		challengeBusy[starter] = true
		table.insert(marked, starter)
		local ok, err = pcall(run)
		if not ok then
			warn("[PveZoneService] desafío: " .. tostring(err))
			state.Busy = false
		end
		for _, p in ipairs(marked) do
			challengeBusy[p] = nil -- se libera a los que participaron en este desafío
		end
		table.clear(marked)
	end

	pp.Triggered:Connect(function(player: Player)
		if not nearEnough(player, pos, USE_DISTANCE) then
			return
		end
		if state.Busy then
			notify(player, "El desafío ya está en marcha")
			return
		end
		local now = os.clock()
		if state.CooldownUntil > now then
			notify(player, string.format("El altar se está recargando: %d s", math.ceil(state.CooldownUntil - now)))
			return
		end
		if #defs == 0 then
			return
		end
		if DailyLimits.Remaining(player, "Challenge", l.Strip) <= 0 then
			notify(player, string.format("Ya usaste tus %d desafíos de hoy en la Franja %d", DailyLimits.Limit("Challenge", l.Strip), l.Strip))
			return
		end
		if groupInChallenge(player) then
			notify(player, "Tu grupo ya tiene un desafío en curso: espera a que termine")
			return
		end
		state.Busy = true
		task.spawn(runSafe, player)
	end)
end

---------------------------------------------------------------------
-- COFRES
---------------------------------------------------------------------
local function buildChest(l: Lane, root: Folder, pos: Vector3, index: number)
	local style = FACTION_STYLE[l.Faction]
	local f = Instance.new("Folder")
	f.Name = string.format("Cofre_%s_%d_%d", l.Faction, l.Strip, index)
	f.Parent = root
	local yaw = rng:NextNumber() * math.pi * 2
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local body = mk(f, "Cuerpo", Vector3.new(5, 2.8, 3.2), base * CFrame.new(0, 1.4, 0), Color3.fromRGB(122, 78, 40), Enum.Material.Wood, nil, true)
	mk(f, "Banda", Vector3.new(5.2, 0.5, 3.4), base * CFrame.new(0, 2.4, 0), style.Accent, Enum.Material.Metal)
	mk(f, "BandaB", Vector3.new(0.6, 2.9, 3.4), base * CFrame.new(1.6, 1.4, 0), style.Accent, Enum.Material.Metal)
	mk(f, "BandaC", Vector3.new(0.6, 2.9, 3.4), base * CFrame.new(-1.6, 1.4, 0), style.Accent, Enum.Material.Metal)
	local lidClosed = base * CFrame.new(0, 3.1, 0)
	local lid = mk(f, "Tapa", Vector3.new(5, 0.9, 3.2), lidClosed, Color3.fromRGB(138, 90, 46), Enum.Material.Wood)
	local latch = mk(f, "Cierre", Vector3.new(0.8, 1, 0.5), base * CFrame.new(0, 2.7, -1.7), Color3.fromRGB(255, 225, 120), Enum.Material.Neon)
	glow(latch, Color3.fromRGB(255, 220, 120), 16, 1.2)
	local busy = false
	local keyId = "Key_" .. l.Strip
	local pp = prompt(body, "Abrir cofre (usa 1 llave)", "Cofre sellado · Franja " .. l.Strip, 1.2, Enum.KeyCode.E)
	label(body, "COFRE SELLADO", Color3.fromRGB(255, 225, 120), 4.2, UDim2.fromOffset(150, 24))
	pp.Triggered:Connect(function(player: Player)
		if busy or not nearEnough(player, pos, USE_DISTANCE) then
			return
		end
		if Inventory.Count(player, keyId) < 1 then
			local more = DailyLimits.Remaining(player, "Keys", l.Strip)
			notify(player, string.format("Cofre sellado: necesitas una Llave de la Franja %d. Cae de los monstruos de esta franja (hoy te pueden caer %d más)", l.Strip, more))
			return
		end
		busy = true
		if not Inventory.Consume(player, keyId, 1) then
			busy = false
			return
		end
		if not LootService.Grant(player, "MapChest", l.Strip) then
			Inventory.Add(player, keyId, 1) -- mochila llena: se devuelve la llave
			busy = false
			return
		end
		lid.CFrame = lidClosed * CFrame.new(0, 0.6, 1.5) * CFrame.Angles(math.rad(-70), 0, 0)
		latch.Transparency = 1
		task.delay(LootTables.MapChest.AnimSeconds, function()
			if lid.Parent then
				lid.CFrame = lidClosed
				latch.Transparency = 0
			end
			busy = false
		end)
	end)
end

---------------------------------------------------------------------
-- NODOS DE RECOLECCIÓN
---------------------------------------------------------------------
local function buildNode(l: Lane, root: Folder, pos: Vector3, index: number)
	local f = Instance.new("Folder")
	f.Name = string.format("Nodo_%s_%d_%d", l.Faction, l.Strip, index)
	f.Parent = root
	local color = NODE_COLOR[l.Strip]
	local parts: { Part } = {}
	local mainPart: Part
	if l.Strip == 1 then -- hierba espiritual: mata de brotes con luz
		mainPart = mk(f, "Mata", Vector3.new(4, 3, 4), CFrame.new(pos + Vector3.new(0, 1.4, 0)), Color3.fromRGB(70, 150, 80), Enum.Material.Grass, Enum.PartType.Ball)
		table.insert(parts, mainPart)
		for k = 1, 4 do
			local a = k * math.pi / 2
			table.insert(parts, mk(f, "Brote", Vector3.new(0.7, 3.6, 0.7), CFrame.new(pos + Vector3.new(math.cos(a) * 1.4, 2.4, math.sin(a) * 1.4)) * CFrame.Angles(math.rad(10), 0, math.rad(8)), color, Enum.Material.Neon))
		end
	elseif l.Strip == 2 then -- cristal: racimo de prismas
		mainPart = mk(f, "Cristal", Vector3.new(1.8, 5, 1.8), CFrame.new(pos + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0.4, math.rad(8)), color, Enum.Material.Neon)
		table.insert(parts, mainPart)
		table.insert(parts, mk(f, "CristalB", Vector3.new(1.2, 3.2, 1.2), CFrame.new(pos + Vector3.new(1.5, 1.6, 0.4)) * CFrame.Angles(0, 0.9, math.rad(-22)), color, Enum.Material.Neon))
		table.insert(parts, mk(f, "CristalC", Vector3.new(1, 2.6, 1), CFrame.new(pos + Vector3.new(-1.4, 1.3, -0.6)) * CFrame.Angles(0, 0.2, math.rad(26)), color, Enum.Material.Neon))
	elseif l.Strip == 3 then -- reliquia: monolito con aro
		mainPart = mk(f, "Monolito", Vector3.new(2.6, 5.5, 1.4), CFrame.new(pos + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, rng:NextNumber() * 3, 0), Color3.fromRGB(86, 80, 74), Enum.Material.Slate)
		table.insert(parts, mainPart)
		table.insert(parts, mk(f, "Glifo", Vector3.new(1.4, 1.4, 1.6), mainPart.CFrame * CFrame.new(0, 0.6, 0), color, Enum.Material.Neon, Enum.PartType.Ball))
	else -- corazón de poder: núcleo latiendo
		mainPart = mk(f, "Corazon", Vector3.new(3.4, 3.4, 3.4), CFrame.new(pos + Vector3.new(0, 3.4, 0)), color, Enum.Material.Neon, Enum.PartType.Ball)
		table.insert(parts, mainPart)
		table.insert(parts, mk(f, "Anillo", Vector3.new(0.4, 6, 6), CFrame.new(pos + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, 0, math.rad(20)), color, Enum.Material.Neon, Enum.PartType.Cylinder))
	end
	glow(mainPart, color, 14, 1)
	local rid = LootTables.StripResource[l.Strip]
	local pp = prompt(mainPart, "Recolectar", itemName(rid), 1.2, Enum.KeyCode.E)
	pp.MaxActivationDistance = 11
	local ready = true
	pp.Triggered:Connect(function(player: Player)
		if not ready or not nearEnough(player, pos, USE_DISTANCE) then
			return
		end
		local G = LootTables.Gathering
		local n = LootTables.Count(G.Count, rng)
		if not Inventory.Add(player, rid, n) then
			return -- mochila llena: el nodo no se gasta
		end
		local msg = string.format("Recolectaste %d %s", n, itemName(rid))
		if rng:NextNumber() < G.BonusMatChance then
			local mid = LootTables.StripMaterial[l.Strip]
			if Inventory.Add(player, mid, 1) then
				msg ..= string.format(" · +1 %s", itemName(mid))
			end
		end
		notify(player, msg)
		ready = false
		pp.Enabled = false
		for _, p in ipairs(parts) do
			p.Transparency = 1
			local lgt = p:FindFirstChildOfClass("PointLight")
			if lgt then
				lgt.Enabled = false
			end
		end
		task.delay(G.RespawnSeconds, function()
			if f.Parent then
				for _, p in ipairs(parts) do
					p.Transparency = 0
					local lgt = p:FindFirstChildOfClass("PointLight")
					if lgt then
						lgt.Enabled = true
					end
				end
				ready = true
				pp.Enabled = true
			end
		end)
	end)
end

---------------------------------------------------------------------
-- MINI JEFE
---------------------------------------------------------------------
local function buildMiniLair(l: Lane, root: Folder, pos: Vector3): MiniSpot
	local style = FACTION_STYLE[l.Faction]
	local f = Instance.new("Folder")
	f.Name = "Guarida_" .. l.Faction .. "_" .. l.Strip
	f.Parent = root
	cyl(f, "Guarida", 22, 0.4, pos + Vector3.new(0, 0.2, 0), Color3.fromRGB(34, 26, 28), Enum.Material.Slate, false)
	cyl(f, "GuaridaAro", 23, 0.3, pos + Vector3.new(0, 0.15, 0), Color3.fromRGB(255, 70, 60), Enum.Material.Neon, false)
	for i = 1, 3 do -- tres estacas con luz roja
		local a = i * math.pi * 2 / 3
		local pp = pos + Vector3.new(math.cos(a) * 11.5, 0, math.sin(a) * 11.5)
		mk(f, "Estaca", Vector3.new(1.1, 8, 1.1), CFrame.new(pp + Vector3.new(0, 4, 0)), Color3.fromRGB(60, 48, 46), Enum.Material.Wood, nil, true)
		local top = mk(f, "EstacaLuz", Vector3.new(1.6, 1.6, 1.6), CFrame.new(pp + Vector3.new(0, 8.4, 0)), Color3.fromRGB(255, 70, 60), Enum.Material.Neon, Enum.PartType.Ball)
		glow(top, Color3.fromRGB(255, 70, 60), 14, 0.9)
	end
	local _ = style
	return { Lane = l, Pos = pos, Model = nil, RespawnAt = 0, Key = l.Faction .. "_" .. l.Strip }
end

local function normalsOf(l: Lane): { MobCatalog.MobDef }
	local out: { MobCatalog.MobDef } = {}
	for _, d in ipairs(MobCatalog.ForStrip(l.Faction, l.Strip)) do
		if not d.Boss then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a, b)
		return a.MinLevel < b.MinLevel
	end)
	return out
end

local function anyPlayerWithin(pos: Vector3, dist: number): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if nearEnough(p, pos, dist) then
			return true
		end
	end
	return false
end

local function miniStep()
	local X = LootTables.MiniBoss
	for _, m in ipairs(minis) do
		local l = m.Lane
		if m.Model and not m.Model.Parent then
			m.Model = nil
		end
		if m.Model == nil then
			if os.clock() >= m.RespawnAt and anyPlayerWithin(m.Pos, 230) then
				local defs = normalsOf(l)
				local def = defs[#defs]
				if def then
					local style = FACTION_STYLE[l.Faction]
					local model = MobService.SpawnMini(def.Id, CFrame.new(m.Pos), def.MaxLevel, {
						HpMult = X.HpMult[l.Strip],
						DmgMult = X.DmgMult,
						Scale = X.Scale,
						Title = style.Title .. " " .. def.Name,
						XpMult = X.XpKills,
						OnDied = function(_)
							m.Model = nil
							m.RespawnAt = os.clock() + X.RespawnSeconds
						end,
					})
					m.Model = model
				end
			end
		else
			local model = m.Model :: Model
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health >= hum.MaxHealth and not anyPlayerWithin(m.Pos, 420) then
				m.Model = nil
				MobService.Despawn(model) -- nadie cerca: se retira sin gastar el reaparecer
			end
		end
	end
end

---------------------------------------------------------------------
-- CONSTRUCCIÓN
---------------------------------------------------------------------
local function sideOf(i: number): number
	return if i % 2 == 0 then 1 else -1
end

local function farFromAll(p: Vector3, placed: { Vector3 }, dist: number): boolean
	for _, q in ipairs(placed) do
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(q.X, 0, q.Z)).Magnitude < dist then
			return false
		end
	end
	return true
end

-- ¿Hay piso bajo este punto y alrededor? (evita poner altares/jefes donde el mapa tiene huecos o el borde)
local function hasGround(p: Vector3, radius: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		return true
	end
	params.FilterDescendantsInstances = { map }
	local offsets = { Vector3.zero }
	for k = 0, 7 do
		local a = k * math.pi / 4
		table.insert(offsets, Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius))
	end
	for _, o in ipairs(offsets) do
		local origin = p + o + Vector3.new(0, 25, 0)
		local hit = Workspace:Raycast(origin, Vector3.new(0, -60, 0), params)
		if not hit or math.abs(hit.Position.Y - p.Y) > 6 then
			return false
		end
	end
	return true
end

local function buildLane(l: Lane, root: Folder)
	local len = l.U1 - l.U0
	local placed: { Vector3 } = {}
	if l.Strip >= CAMP_FROM_STRIP then
		placed[1] = buildCamp(l, root).Pos
	end
	local function pick(uFrom: number, uTo: number, minDist: number?, preferSide: number?): Vector3?
		for _ = 1, 60 do
			local u = l.U0 + len * (uFrom + (uTo - uFrom) * rng:NextNumber())
			local half = math.max(10, halfWidth(l, u) - EDGE_MARGIN)
			local v = (rng:NextNumber() * 2 - 1) * half
			if preferSide then
				v = math.abs(v) * preferSide
			end
			local p = lanePoint(l, u, v)
			if farFromAll(p, placed, minDist or OBJECT_SPACING) and hasGround(p, 22) then
				return p
			end
		end
		return nil
	end

	-- altares: uno antes y otro después del campamento, a un lado cada uno
	local offer = pick(0.18, 0.34, 70, sideOf(l.Strip))
	if offer then
		table.insert(placed, offer)
		buildOffering(l, root, offer)
	end
	local chal = pick(0.62, 0.8, 70, -sideOf(l.Strip))
	if chal then
		table.insert(placed, chal)
		buildChallenge(l, root, chal)
	end
	-- Franjas 3 y 4 son enormes (hasta ~3000 studs de ancho): más altares para no recorrer todo el mapa buscando uno.
	-- El premio no cambia: la ofrenda comparte su enfriamiento por franja y los desafíos comparten el límite diario por franja.
	local extraOffer = EXTRA_OFFERINGS[l.Strip] or 0
	local extraChal = EXTRA_CHALLENGES[l.Strip] or 0
	for k = 1, extraOffer do
		local p = pick(0.08, 0.95, 280, if k % 2 == 0 then 1 else -1)
		if p then
			table.insert(placed, p)
			buildOffering(l, root, p, k + 1)
		end
	end
	for k = 1, extraChal do
		local p = pick(0.1, 0.95, 280, if k % 2 == 0 then -1 else 1)
		if p then
			table.insert(placed, p)
			buildChallenge(l, root, p, k + 1)
		end
	end
	-- mini jefe al fondo-medio
	local lair = pick(0.72, 0.9, 70, sideOf(l.Strip + 1))
	if lair then
		table.insert(placed, lair)
		table.insert(minis, buildMiniLair(l, root, lair))
	end
	-- cofres
	local ranges = { { 0.08, 0.3 }, { 0.36, 0.6 }, { 0.78, 0.95 } }
	for i, r in ipairs(ranges) do
		local p = pick(r[1], r[2], 55, sideOf(i + l.Strip))
		if p then
			table.insert(placed, p)
			buildChest(l, root, p, i)
		end
	end
	-- nodos
	for i = 1, LootTables.Gathering.NodesPerStrip do
		local p = pick(0.05, 0.96, 38)
		if p then
			table.insert(placed, p)
			buildNode(l, root, p, i)
		end
	end
end

local function clearAll()
	for _, m in ipairs(minis) do
		if m.Model and m.Model.Parent then
			MobService.Despawn(m.Model)
		end
	end
	table.clear(minis)
	table.clear(camps)
	if folder then
		folder:Destroy()
		folder = nil
	end
end

local function build()
	buildToken += 1
	local token = buildToken
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		return
	end
	local lanes = readLanes(map)
	if #lanes == 0 then
		warn("[PveZoneService] No hay losas ZonePvE con geometría: ¿corrió ProjectBootstrapper?")
		return
	end
	clearAll()
	if token ~= buildToken then
		return
	end
	-- copias viejas guardadas en el lugar (si alguna vez se generó en Edit y se guardó): se borran para no duplicar
	for _, stale in ipairs(Workspace:GetChildren()) do
		if stale.Name == "PuntosDeInteres" then
			stale:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "PuntosDeInteres"
	root.Parent = Workspace
	folder = root
	rng = Random.new(20261101) -- mismas posiciones en cada arranque
	for _, l in ipairs(lanes) do
		local ok, err = pcall(buildLane, l, root)
		if not ok then
			warn(string.format("[PveZoneService] Error en %s franja %d: %s", l.Faction, l.Strip, tostring(err)))
		end
	end
	print(string.format("[PveZoneService] %d campamentos y puntos de interés creados.", #camps))
end

---------------------------------------------------------------------
-- REGENERACIÓN EN CAMPAMENTO, REAPARICIÓN Y BUCLES
---------------------------------------------------------------------
local function campNear(pos: Vector3): Camp?
	for _, c in ipairs(camps) do
		local d = Vector3.new(pos.X - c.Pos.X, 0, pos.Z - c.Pos.Z).Magnitude
		if d <= CAMP_RADIUS and math.abs(pos.Y - c.Pos.Y) < 30 then
			return c
		end
	end
	return nil
end

-- ¿Está la posición dentro de una zona segura (ciudad, fuerte o campamento)? Piezas con tag "ZoneSafe"
local function inSafeZone(pos: Vector3, zones: { BasePart }): boolean
	for _, z in ipairs(zones) do
		local l = z.CFrame:PointToObjectSpace(pos)
		local h = z.Size / 2
		if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z and l.Y >= -h.Y - 5 and l.Y <= h.Y + 80 then
			return true
		end
	end
	return false
end

-- Vida y energía rápidas en la ciudad, en los fuertes y en los campamentos
local function regenStep()
	local zones: { BasePart } = {}
	for _, z in ipairs(CollectionService:GetTagged("ZoneSafe")) do
		if z:IsA("BasePart") then
			table.insert(zones, z)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 and inSafeZone(root.Position, zones) then
			if hum.Health < hum.MaxHealth then
				hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * REGEN_PCT)
			end
			local cur, max = Energy.GetEnergy(p)
			if max > 0 and cur < max then
				Energy.Gain(p, max * REGEN_PCT)
			end
		end
	end
end

-- COMPUERTA DE ATAQUE (DamageService): dentro del campamento no se puede atacar; un mini jefe con tope diario agotado no se puede dañar
local lastGateMsg: { [Player]: number } = {}
local function gateMessage(player: Player, text: string)
	local now = os.clock()
	if now - (lastGateMsg[player] or 0) > 3 then
		lastGateMsg[player] = now
		notify(player, text)
	end
end

DamageService.SetAttackGate(function(player: Player, victim: Model): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and campNear(root.Position) then
		gateMessage(player, "Dentro del campamento no se puede atacar")
		return false
	end
	if victim:GetAttribute("Mini") == true then
		local strip = victim:GetAttribute("Strip")
		if typeof(strip) == "number" and DailyLimits.Remaining(player, "MiniBoss", strip) <= 0 then
			gateMessage(player, string.format("Ya agotaste tus mini jefes de hoy en la Franja %d: no puedes atacarlo", strip))
			return false
		end
	end
	return true
end)

local function hookPlayer(player: Player)
	local function onChar(char: Model)
		if pendingRespawn[player] and player:GetAttribute("DeathChoice") ~= "Camp" then
			pendingRespawn[player] = nil -- eligió la ciudad (o lo revivió un aliado): no va al campamento
		end
		if pendingRespawn[player] then
			local camp = pendingRespawn[player]
			pendingRespawn[player] = nil
			task.spawn(function()
				-- otros scripts (reaparecer en la ciudad, pantalla de carga) también mueven al jugador: se reintenta ~4 s hasta que quede en el campamento
				char:WaitForChild("HumanoidRootPart", 10)
				local deadline = os.clock() + 4
				local placed = false
				task.wait(0.5)
				while player.Character == char and char.Parent and os.clock() < deadline do
					local root = char:FindFirstChild("HumanoidRootPart")
					if root and root:IsA("BasePart") then
						local d = Vector3.new(root.Position.X - camp.Pos.X, 0, root.Position.Z - camp.Pos.Z).Magnitude
						if d > 40 then
							char:PivotTo(camp.Respawn)
							placed = true
						elseif placed then
							break
						else
							placed = true
							break
						end
					end
					task.wait(0.4)
				end
				if placed and player.Character == char then
					notify(player, "Reapareciste en tu campamento")
				end
			end)
		end
		local hum = char:WaitForChild("Humanoid", 10)
		if hum and hum:IsA("Humanoid") then
			hum.Died:Once(function()
				local mine = campOf[player]
				if not mine then
					return
				end
				local root = char:FindFirstChild("HumanoidRootPart")
				local zone = player:GetAttribute("BiomeZone") -- "<Facción>_<franja>" (lo pone BiomeStyler)
				local chosen: Camp? = nil
				if typeof(zone) == "string" and mine[zone] then
					chosen = mine[zone] -- murió en una franja con campamento fijado: sin límite de distancia (las franjas son largas)
				elseif root and root:IsA("BasePart") then
					-- sin franja (borde del mapa): el campamento fijado más cercano, si está razonablemente cerca
					local best = 700
					for _, c in pairs(mine) do
						local d = Vector3.new(root.Position.X - c.Pos.X, 0, root.Position.Z - c.Pos.Z).Magnitude
						if d <= best then
							best, chosen = d, c
						end
					end
				end
				if chosen then
					pendingRespawn[player] = chosen
					player:SetAttribute("DeathPlace", string.format("Campamento · Franja %d", chosen.Strip))
				end
			end)
		end
	end
	player.CharacterAdded:Connect(onChar)
	if player.Character then
		task.spawn(onChar, player.Character)
	end
end

Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do
	hookPlayer(p)
end
Players.PlayerRemoving:Connect(function(p)
	campOf[p] = nil
	lastRest[p] = nil
	pendingRespawn[p] = nil
	lastGateMsg[p] = nil
	challengeBusy[p] = nil
end)

task.spawn(function()
	while true do
		task.wait(1)
		local ok, err = pcall(regenStep)
		if not ok then
			warn("[PveZoneService] regen: " .. tostring(err))
		end
		local ok2, err2 = pcall(miniStep)
		if not ok2 then
			warn("[PveZoneService] mini jefes: " .. tostring(err2))
		end
	end
end)

-- Arranque: espera el mapa (y a que BiomeStyler termine) y construye; si el mapa se vuelve a construir, rehace todo
task.spawn(function()
	local t = 0
	while (not Workspace:FindFirstChild(MAP_NAME) or Workspace:GetAttribute("MapBuilt") ~= true) and t < 90 do
		task.wait(1)
		t += 1
	end
	task.wait(3)
	build()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == MAP_NAME then
		local mine = buildToken
		task.delay(10, function()
			if buildToken == mine and Workspace:FindFirstChild(MAP_NAME) then
				build()
			end
		end)
	end
end)

local PveZone = {}
PveZone.Rebuild = build

return PveZone
