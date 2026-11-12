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
local NestService = require(Services.NestService)
local MountCatalog = require(Modules.MountCatalog)
local CampArt = require(Modules.CampArt)

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
	Saiyan = { Accent = Color3.fromRGB(255, 170, 60), Dark = Color3.fromRGB(40, 48, 66), Title = "Comandante", Camp = "Campamento de Élite" },
	Shinobi = { Accent = Color3.fromRGB(255, 120, 70), Dark = Color3.fromRGB(58, 46, 40), Title = "Líder", Camp = "Campamento del Sigilo" },
	Pirate = { Accent = Color3.fromRGB(255, 200, 80), Dark = Color3.fromRGB(70, 48, 32), Title = "Capitán", Camp = "Campamento de Navegantes" },
	Shinigami = { Accent = Color3.fromRGB(150, 200, 255), Dark = Color3.fromRGB(190, 195, 205), Title = "Teniente", Camp = "Campamento Espiritual" },
}

-- Color de las llamas (braseros) por facción: principal y secundario
local FLAME: { [string]: { Color3 } } = {
	Saiyan = { Color3.fromRGB(110, 190, 255), Color3.fromRGB(40, 90, 220) },
	Shinobi = { Color3.fromRGB(130, 235, 140), Color3.fromRGB(30, 120, 60) },
	Pirate = { Color3.fromRGB(255, 210, 90), Color3.fromRGB(210, 90, 20) },
	Shinigami = { Color3.fromRGB(196, 140, 255), Color3.fromRGB(90, 40, 170) },
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

-- animación en el cliente (FxAnimClient): atributos + tag
local function fx(p: BasePart, a: { [string]: any })
	for k, v in pairs(a) do
		p:SetAttribute(k, v)
	end
	CollectionService:AddTag(p, "FxAnim")
end

-- emisor de partículas (chispas, brasas, motas)
local function sparks(p: BasePart, color: Color3, rate: number, life: number, speed: number, size: number, up: number?)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Acceleration = Vector3.new(0, up or 1.5, 0)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = p
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
		-- cápsula de aterrizaje (imagen) con colisión invisible
		local p = at(-14, -17, 0)
		local hull = mk(parent, "Capsula", Vector3.new(9, 8, 9), CFrame.new(p + Vector3.new(0, 4, 0)), Color3.fromRGB(235, 240, 248), Enum.Material.SmoothPlastic, nil, true)
		hull.Transparency = 1
		local propId = CampArt.Prop.Saiyan
		if propId then
			CampArt.Sprite(hull, "Arte", propId, 13, 10.4, 0.6, 160)
		end
		local lamp = mk(parent, "LuzCapsula", Vector3.new(1, 1, 1), CFrame.new(p + Vector3.new(0, 7, 0)), Color3.fromRGB(110, 190, 255), Enum.Material.Neon, Enum.PartType.Ball)
		lamp.Transparency = 1
		glow(lamp, Color3.fromRGB(110, 190, 255), 18, 1.2)
		fx(lamp, { FxPulse = 0.4 })
		-- radar
		local rp = at(-10, 18, 0)
		cyl(parent, "RadarMastil", 1.2, 14, rp + Vector3.new(0, 7, 0), Color3.fromRGB(120, 130, 145), Enum.Material.Metal, true)
		mk(parent, "RadarPlato", Vector3.new(1, 8, 8), CFrame.new(rp + Vector3.new(0, 14.5, 0)) * CFrame.Angles(math.rad(25), 0, math.pi / 2), Color3.fromRGB(235, 235, 240), Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif faction == "Shinobi" then
		-- tienda ninja (imagen) con colisión invisible + cartelera de pergaminos
		local p = at(-14, -17, 0)
		local tent = mk(parent, "Tienda", Vector3.new(11, 7, 9), CFrame.new(p + Vector3.new(0, 3.5, 0)), Color3.fromRGB(190, 170, 130), Enum.Material.Fabric, nil, true)
		tent.Transparency = 1
		local propId = CampArt.Prop.Shinobi
		if propId then
			CampArt.Sprite(tent, "Arte", propId, 13, 10.4, 0.6, 160)
		end
		local rack = at(-10, 18, 0)
		mk(parent, "CarteleraPoste", Vector3.new(1, 10, 1), CFrame.new(rack + Vector3.new(-3, 5, 0)), Color3.fromRGB(110, 78, 50), Enum.Material.Wood, nil, true)
		mk(parent, "CarteleraPoste", Vector3.new(1, 10, 1), CFrame.new(rack + Vector3.new(3, 5, 0)), Color3.fromRGB(110, 78, 50), Enum.Material.Wood, nil, true)
		mk(parent, "Pergaminos", Vector3.new(8, 5, 0.5), lookCF(rack + Vector3.new(0, 6.5, 0)), Color3.fromRGB(235, 225, 195), Enum.Material.Fabric)
	elseif faction == "Pirate" then
		-- toldo de vela con barriles y cañón (imagen) con colisión invisible, cajas y bandera
		local tp = at(-12, -17, 0)
		local canopy = mk(parent, "Toldo", Vector3.new(10, 7, 7), CFrame.new(tp + Vector3.new(0, 3.5, 0)), Color3.fromRGB(235, 225, 195), Enum.Material.Fabric, nil, true)
		canopy.Transparency = 1
		local propId = CampArt.Prop.Pirate
		if propId then
			CampArt.Sprite(canopy, "Arte", propId, 13, 10.4, 0.6, 160)
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

-- Vida del campamento: dummy de entrenamiento, rack de armas, sacos y cajas, camastros, luces colgantes,
-- espíritus que orbitan, motas flotando y el emblema de la facción girando.
local function buildCampLife(f: Folder, center: Vector3, dir: Vector3, style: { Accent: Color3, Dark: Color3, Title: string, Camp: string }, faction: string)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local function at(fw: number, r: number, y: number?): Vector3
		return center + dir * fw + right * r + Vector3.new(0, y or 0, 0)
	end
	local WOOD = Color3.fromRGB(104, 72, 46)
	local look = function(pos: Vector3, toward: Vector3): CFrame
		return CFrame.lookAt(pos, pos + toward)
	end
	-- dummy de entrenamiento
	local dp = at(16, -18)
	mk(f, "DummyPoste", Vector3.new(1.2, 7, 1.2), CFrame.new(dp + Vector3.new(0, 3.5, 0)), WOOD, Enum.Material.Wood, nil, true)
	mk(f, "DummyBrazo", Vector3.new(5.6, 0.9, 0.9), CFrame.new(dp + Vector3.new(0, 5.4, 0)) * CFrame.Angles(0, math.atan2(-dir.X, -dir.Z), 0), WOOD, Enum.Material.Wood)
	local body = mk(f, "DummySaco", Vector3.new(3, 3.6, 2.2), CFrame.new(dp + Vector3.new(0, 4.4, 0)), Color3.fromRGB(196, 170, 120), Enum.Material.Fabric, nil, true)
	mk(f, "DummyCabeza", Vector3.new(1.9, 1.9, 1.9), CFrame.new(dp + Vector3.new(0, 7.3, 0)), Color3.fromRGB(196, 170, 120), Enum.Material.Fabric, Enum.PartType.Ball)
	local target = mk(f, "DummyDiana", Vector3.new(1.9, 1.9, 0.3), look(dp + Vector3.new(0, 4.5, 0) + dir * 1.2, dir), style.Accent, Enum.Material.Neon, Enum.PartType.Cylinder)
	target.Transparency = 0.2
	local _ = body

	-- rack de armas
	local rp = at(14, 20)
	mk(f, "RackPoste", Vector3.new(0.9, 6, 0.9), CFrame.new(rp + right * -3.2 + Vector3.new(0, 3, 0)), WOOD, Enum.Material.Wood, nil, true)
	mk(f, "RackPoste", Vector3.new(0.9, 6, 0.9), CFrame.new(rp + right * 3.2 + Vector3.new(0, 3, 0)), WOOD, Enum.Material.Wood, nil, true)
	mk(f, "RackBarra", Vector3.new(7.6, 0.7, 0.7), CFrame.new(rp + Vector3.new(0, 4.4, 0)) * CFrame.Angles(0, math.atan2(-right.X, -right.Z) + math.pi / 2, 0), WOOD, Enum.Material.Wood)
	for k = -1, 1 do
		local w = mk(f, "RackArma", Vector3.new(0.35, 5.4, 0.35), CFrame.new(rp + right * (k * 1.7) + Vector3.new(0, 3.2, 0.1)) * CFrame.Angles(0, 0, math.rad(k * 9)), Color3.fromRGB(200, 205, 214), Enum.Material.Metal)
		w.Name = "RackArma"
		mk(f, "RackPunta", Vector3.new(0.6, 0.6, 0.6), CFrame.new(rp + right * (k * 1.7 + k * 0.4) + Vector3.new(0, 6, 0.1)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball).Transparency = 0.3
	end

	-- sacos y cajas de suministros
	local sp = at(-4, 22)
	for k = 0, 2 do
		mk(f, "Caja", Vector3.new(3.4, 3.4, 3.4), CFrame.new(sp + right * (k * 3.6) + Vector3.new(0, 1.8, 0)) * CFrame.Angles(0, math.rad(k * 17), 0), Color3.fromRGB(128, 92, 56), Enum.Material.WoodPlanks, nil, true)
	end
	mk(f, "Caja", Vector3.new(3, 3, 3), CFrame.new(sp + right * 3.6 + Vector3.new(0, 4.8, 0)) * CFrame.Angles(0, math.rad(40), 0), Color3.fromRGB(150, 110, 66), Enum.Material.WoodPlanks, nil, true)
	for k = 0, 2 do
		local sack = mk(f, "Saco", Vector3.new(2.4, 2.8, 2.4), CFrame.new(sp + right * (-4 - k * 2.2) + dir * (k % 2) + Vector3.new(0, 1.4, 0)), Color3.fromRGB(190, 168, 122), Enum.Material.Fabric, Enum.PartType.Ball, true)
		sack.Name = "Saco"
	end

	-- camastros alrededor de la hoguera
	for k = 0, 1 do
		local a = math.rad(200 + k * 110)
		local bp = center + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15)
		local face = (center - bp) * Vector3.new(1, 0, 1)
		mk(f, "Camastro", Vector3.new(3, 0.6, 6.4), CFrame.lookAt(bp + Vector3.new(0, 0.8, 0), bp + Vector3.new(0, 0.8, 0) + face), style.Accent:Lerp(style.Dark, 0.55), Enum.Material.Fabric)
		mk(f, "Almohada", Vector3.new(2.4, 0.9, 1.4), CFrame.lookAt(bp + Vector3.new(0, 1.3, 0) - face.Unit * 2.4, bp + Vector3.new(0, 1.3, 0)), Color3.fromRGB(230, 225, 215), Enum.Material.Fabric)
	end

	-- cuerdas de luces entre los mástiles (esquinas a radio CAMP_RADIUS - 3, altura 12)
	local R = CAMP_RADIUS - 3
	for i = 1, 4 do
		local a1 = i * math.pi / 2 + math.pi / 4
		local a2 = (i + 1) * math.pi / 2 + math.pi / 4
		local p1 = center + Vector3.new(math.cos(a1) * R, 11.4, math.sin(a1) * R)
		local p2 = center + Vector3.new(math.cos(a2) * R, 11.4, math.sin(a2) * R)
		local mid = (p1 + p2) / 2
		local cable = mk(f, "Cuerda", Vector3.new(0.12, 0.12, (p2 - p1).Magnitude), CFrame.lookAt(mid, p2), Color3.fromRGB(40, 36, 34), Enum.Material.Fabric)
		cable.Name = "Cuerda"
		for k = 1, 6 do
			local t = k / 7
			local lp = p1:Lerp(p2, t) + Vector3.new(0, -1.1, 0)
			local bulb = mk(f, "Farolillo", Vector3.new(0.9, 1.2, 0.9), CFrame.new(lp), style.Accent:Lerp(Color3.new(1, 0.9, 0.7), 0.4), Enum.Material.Neon, Enum.PartType.Ball)
			bulb.Transparency = 0.1
			fx(bulb, { FxBob = 0.15, FxBobSpeed = 1.2 + k * 0.2 })
		end
	end

	-- espíritus/luciérnagas que orbitan alrededor de la hoguera
	for k = 0, 5 do
		local w = mk(f, "Espiritu", Vector3.new(1, 1, 1), CFrame.new(center), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		w.Transparency = 0.15
		fx(w, { FxCenter = center, FxOrbitR = 19 + (k % 2) * 3, FxOrbitSpeed = if k % 2 == 0 then 14 else -11, FxOrbitPhase = k * 60, FxOrbitY = 5 + (k % 3) * 1.6, FxBob = 0.8, FxBobSpeed = 1.4 + k * 0.15 })
		if k % 2 == 0 then
			glow(w, style.Accent, 10, 0.5)
		end
	end
	local motes = mk(f, "Motas", Vector3.new(46, 10, 46), CFrame.new(center + Vector3.new(0, 6, 0)), style.Accent, Enum.Material.SmoothPlastic)
	motes.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(style.Accent:Lerp(Color3.new(1, 1, 1), 0.3))
	e.LightEmission = 1
	e.Rate = 5
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(0.4, 1.2)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Acceleration = Vector3.new(0, 0.3, 0)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Parent = motes

	-- reliquia de la facción sobre un pedestal, flotando y girando
	local relic = CampArt.Relic[faction]
	if relic then
		local rp2 = at(5, 21)
		local fc = FLAME[faction] or { style.Accent, style.Accent }
		cyl(f, "ReliquiaBase", 6, 1.2, rp2 + Vector3.new(0, 0.6, 0), style.Dark, Enum.Material.Marble, true)
		cyl(f, "ReliquiaBase2", 4, 1.6, rp2 + Vector3.new(0, 2, 0), style.Dark:Lerp(Color3.new(0.1, 0.1, 0.12), 0.3), Enum.Material.Marble, true)
		local aroR = cyl(f, "ReliquiaAro", 6.6, 0.25, rp2 + Vector3.new(0, 1.25, 0), fc[1], Enum.Material.Neon, false)
		fx(aroR, { FxFade = 0.2 })
		local panel = mk(f, "Reliquia", Vector3.new(0.3, 8, 8), CFrame.new(rp2 + Vector3.new(0, 7.2, 0)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		panel.Transparency = 1
		CampArt.Panel(panel, Enum.NormalId.Right, relic, "CaraA")
		CampArt.Panel(panel, Enum.NormalId.Left, relic, "CaraB")
		fx(panel, { FxSpin = 22, FxBob = 0.5, FxBobSpeed = 1.5 })
		local lampR = mk(f, "ReliquiaLuz", Vector3.new(1, 1, 1), CFrame.new(rp2 + Vector3.new(0, 7, 0)), fc[1], Enum.Material.Neon, Enum.PartType.Ball)
		lampR.Transparency = 1
		glow(lampR, fc[1], 24, 1)
		lampR:SetAttribute("FxPulse", 0.3)
		CollectionService:AddTag(lampR, "FxAnim")
		sparks(lampR, fc[1], 8, 2.8, 3, 0.5, 2)
	end

	-- emblema de la facción, flotando y girando (dos caras)
	local emblem = CampArt.Floor[faction]
	if emblem then
		local ep = at(-20, 0, 9.5)
		local disc = mk(f, "EmblemaFlotante", Vector3.new(0.3, 8, 8), CFrame.new(ep), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		disc.Transparency = 1
		CampArt.Panel(disc, Enum.NormalId.Right, emblem, "CaraA")
		CampArt.Panel(disc, Enum.NormalId.Left, emblem, "CaraB")
		fx(disc, { FxSpin = 28, FxBob = 0.6, FxBobSpeed = 1.3 })
		local halo = mk(f, "EmblemaLuz", Vector3.new(1, 1, 1), CFrame.new(ep + Vector3.new(0, -4.8, 0)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		halo.Transparency = 0.5
		glow(halo, style.Accent, 22, 0.9)
		mk(f, "EmblemaSoporte", Vector3.new(0.8, 5, 0.8), CFrame.new(at(-20, 0, 2.5)), Color3.fromRGB(70, 66, 74), Enum.Material.Metal, nil, true)
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
	local suelo = cyl(f, "Suelo", CAMP_RADIUS * 1.7, 0.5, center + Vector3.new(0, 0.25, 0), style.Dark:Lerp(Color3.new(0.2, 0.2, 0.2), 0.3), Enum.Material.Cobblestone, false)
	local floorId = CampArt.Floor[l.Faction]
	if floorId then
		CampArt.Decal(suelo, Enum.NormalId.Right, floorId, "Medallon")
	end
	cyl(f, "AroSuelo", CAMP_RADIUS * 1.7 + 1.4, 0.4, center + Vector3.new(0, 0.2, 0), style.Accent, Enum.Material.Neon, false)

	-- hoguera central
	-- hogar: piso con foso de piedras, troncos y asientos (imagen cenital) + colisión invisible de la hoguera
	local fire = cyl(f, "Hoguera", 5, 1.2, center + Vector3.new(0, 0.9, 0), Color3.fromRGB(70, 60, 55), Enum.Material.Slate, true)
	fire.Transparency = 1
	local hearthId = CampArt.Hearth[l.Faction]
	if hearthId then
		local hearth = cyl(f, "Hogar", 22, 0.1, center + Vector3.new(0, 0.56, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
		hearth.Transparency = 1
		CampArt.Panel(hearth, Enum.NormalId.Right, hearthId, "Hogar", 40)
	end
	-- llama viva: carteles de imagen que parpadean (FxAnimClient) + luz + chispas + humo
	local flame = mk(f, "Llama", Vector3.new(2, 2, 2), CFrame.new(center + Vector3.new(0, 1.6, 0)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
	flame.Transparency = 1
	local flameId = CampArt.Flame[l.Faction]
	if flameId then
		CampArt.Sprite(flame, "Llama1", flameId, 4.4, 6.6, 2.9, 160)
		CampArt.Sprite(flame, "Llama2", flameId, 3, 4.6, 2.0, 160)
	end
	glow(flame, style.Accent, 38, 1.6)
	fx(flame, { FxPulse = 0.5, FxFlicker = 1 })
	sparks(flame, Color3.fromRGB(255, 190, 90), 14, 2.4, 6, 0.45, 6)
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(120, 120, 128)
	smoke.Opacity = 0.18
	smoke.RiseVelocity = 5
	smoke.Size = 4
	smoke.Parent = flame

	-- antorchas / mástiles en las 4 esquinas del campamento
	for i = 1, 4 do
		local a = i * math.pi / 2 + math.pi / 4
		local pp = center + Vector3.new(math.cos(a) * (CAMP_RADIUS - 3), 0, math.sin(a) * (CAMP_RADIUS - 3))
		cyl(f, "Mastil", 1, 12, pp + Vector3.new(0, 6, 0), style.Dark, Enum.Material.Wood, true)
		local lamp = mk(f, "Antorcha", Vector3.new(2, 2.4, 2), CFrame.new(pp + Vector3.new(0, 12.8, 0)), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		glow(lamp, style.Accent, 22, 1.1)
		-- estandarte de la facción colgado hacia el centro
		local bannerId = CampArt.Banner[l.Faction]
		if bannerId then
			local inward = (center - pp) * Vector3.new(1, 0, 1)
			if inward.Magnitude > 0.1 then
				local bp = pp + inward.Unit * 2.4 + Vector3.new(0, 6.6, 0)
				local ban = mk(f, "Estandarte", Vector3.new(4.2, 9.8, 0.2), CFrame.lookAt(bp, bp + inward.Unit), Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic)
				ban.Transparency = 1
				CampArt.Panel(ban, Enum.NormalId.Front, bannerId, "Frente")
				CampArt.Panel(ban, Enum.NormalId.Back, bannerId, "Dorso")
				mk(f, "EstandarteBrazo", Vector3.new(0.5, 0.5, 2.6), CFrame.lookAt(pp + Vector3.new(0, 11.4, 0) + inward.Unit * 1.2, pp + Vector3.new(0, 11.4, 0) + inward.Unit * 2.4), style.Dark, Enum.Material.Wood)
			end
		end
	end

	buildFactionProps(f, l.Faction, center, style, dir)
	buildCampLife(f, center, dir, style, l.Faction)

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
local function altarBase(parent: Folder, name: string, pos: Vector3, style: { Accent: Color3, Dark: Color3, Title: string, Camp: string }, tint: Color3, artId: number?, kind: string, faction: string): (Part, Part)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	local fire = kind == "desafio"
	local dark2 = style.Dark:Lerp(Color3.new(0.08, 0.08, 0.1), 0.45)

	-- medallón de suelo con la imagen del altar
	local medal = cyl(f, "Medallon", 32, 0.4, pos + Vector3.new(0, 0.2, 0), style.Dark, Enum.Material.Slate, true)
	if artId then
		CampArt.Decal(medal, Enum.NormalId.Right, artId, "Arte")
	end
	local aro = cyl(f, "BaseAro", 32.8, 0.3, pos + Vector3.new(0, 0.15, 0), tint, Enum.Material.Neon, false)
	fx(aro, { FxFade = 0.18 })
	-- aro con el color de la facción
	local aroF = cyl(f, "AroFaccion", 33.8, 0.2, pos + Vector3.new(0, 0.1, 0), style.Accent, Enum.Material.Neon, false)
	aroF.Transparency = 0.35

	-- plinto escalonado + pedestal
	cyl(f, "Base", 9.6, 1.0, pos + Vector3.new(0, 0.9, 0), style.Dark, Enum.Material.Slate, true)
	local aroP = cyl(f, "BaseAro2", 9.9, 0.25, pos + Vector3.new(0, 1.42, 0), tint, Enum.Material.Neon, false)
	fx(aroP, { FxFade = 0.2 })
	cyl(f, "Base2", 7, 1.0, pos + Vector3.new(0, 1.9, 0), dark2, Enum.Material.Marble, true)
	cyl(f, "Pedestal", 3.6, 3.4, pos + Vector3.new(0, 4.1, 0), style.Dark:Lerp(Color3.new(0.1, 0.1, 0.12), 0.35), Enum.Material.Marble, true)

	-- núcleo flotante: gira y respira
	local cpos = pos + Vector3.new(0, 9, 0)
	local core = mk(f, "Nucleo", Vector3.new(3.6, 3.6, 3.6), CFrame.new(cpos) * CFrame.Angles(math.rad(45), math.rad(45), 0), tint, Enum.Material.Neon)
	core.Transparency = 0.1
	fx(core, { FxSpin = 55, FxBob = 0.7, FxBobSpeed = 1.6 })
	glow(core, tint, 34, 1.4)
	core:SetAttribute("FxPulse", 0.3)
	sparks(core, tint, 10, 2.6, 3, 0.5, 2)

	if fire then
		-- espadas cruzadas flotando sobre el núcleo
		for k = -1, 1, 2 do
			local blade = mk(f, "Espada", Vector3.new(0.5, 7.5, 0.9), CFrame.new(cpos + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(40 * k)), Color3.fromRGB(215, 220, 232), Enum.Material.Metal)
			fx(blade, { FxSpin = 55, FxBob = 0.7, FxBobSpeed = 1.6 })
			local edge = mk(f, "EspadaFilo", Vector3.new(0.2, 7.2, 0.3), CFrame.new(cpos + Vector3.new(0, 4.6, 0)) * CFrame.Angles(0, 0, math.rad(40 * k)), tint, Enum.Material.Neon)
			edge.Transparency = 0.35
			fx(edge, { FxSpin = 55, FxBob = 0.7, FxBobSpeed = 1.6 })
		end
	end

	-- cuentas con el color de la facción que orbitan el núcleo
	for k = 0, 7 do
		local bead = mk(f, "Cuenta", Vector3.new(0.8, 0.8, 0.8), CFrame.new(cpos), style.Accent, Enum.Material.Neon, Enum.PartType.Ball)
		fx(bead, { FxCenter = cpos, FxOrbitR = 5.6, FxOrbitSpeed = if fire then -45 else 38, FxOrbitPhase = k * 45, FxOrbitY = 0.3 * math.sin(k) })
	end
	for k = 0, 2 do
		local orb = mk(f, "Orbe", Vector3.new(1.5, 1.5, 1.5), CFrame.new(cpos), tint, Enum.Material.Neon, Enum.PartType.Ball)
		orb.Transparency = 0.2
		fx(orb, { FxCenter = cpos, FxOrbitR = 8.4, FxOrbitSpeed = if fire then 62 else -52, FxOrbitPhase = k * 120, FxOrbitY = 2.2 + k * 0.8, FxBob = 0.5, FxBobSpeed = 2 })
		glow(orb, tint, 9, 0.6)
	end

	-- rayo de luz tenue + motas que suben por todo el medallón
	local ray = cyl(f, "Rayo", 2.6, 26, pos + Vector3.new(0, 14, 0), tint, Enum.Material.Neon, false)
	ray.Transparency = 0.82
	fx(ray, { FxFade = 0.08 })
	local motes = mk(f, "Motas", Vector3.new(26, 1, 26), CFrame.new(pos + Vector3.new(0, 1, 0)), tint, Enum.Material.SmoothPlastic)
	motes.Transparency = 1
	sparks(motes, if fire then Color3.fromRGB(255, 140, 60) else tint:Lerp(Color3.new(1, 1, 1), 0.35), 9, 3.2, 4, 0.55, 2.5)

	-- 4 pilares: de ofrenda con cristal flotante, de desafío con brasero
	for i = 1, 4 do
		local a = i * math.pi / 2 + math.pi / 4
		local pp = pos + Vector3.new(math.cos(a) * 11.5, 0, math.sin(a) * 11.5)
		mk(f, "PilarBase", Vector3.new(3, 1.2, 3), CFrame.new(pp + Vector3.new(0, 1, 0)), dark2, Enum.Material.Marble, nil, true)
		mk(f, "Pilar", Vector3.new(1.8, 9.5, 1.8), CFrame.new(pp + Vector3.new(0, 6.3, 0)), style.Dark, Enum.Material.Marble, nil, true)
		mk(f, "PilarAnillo", Vector3.new(2.4, 0.35, 2.4), CFrame.new(pp + Vector3.new(0, 8.6, 0)), tint, Enum.Material.Neon)
		mk(f, "PilarCapitel", Vector3.new(2.8, 0.9, 2.8), CFrame.new(pp + Vector3.new(0, 11.4, 0)), dark2, Enum.Material.Marble)
		if fire then
			local fl = mk(f, "Brasero", Vector3.new(1.6, 1.6, 1.6), CFrame.new(pp + Vector3.new(0, 12.5, 0)), tint, Enum.Material.Neon, Enum.PartType.Ball)
			fl.Transparency = 0.5
			local fi = Instance.new("Fire")
			fi.Heat = 8
			fi.Size = 5
			local fc = FLAME[faction] or { Color3.fromRGB(255, 120, 50), Color3.fromRGB(200, 30, 30) }
			fi.Color = fc[1]
			fi.SecondaryColor = fc[2]
			fi.Parent = fl
			fl.Color = fc[1]
			glow(fl, fc[1], 18, 1)
			fl:SetAttribute("FxPulse", 0.4)
			CollectionService:AddTag(fl, "FxAnim")
		else
			local gem = mk(f, "PilarGema", Vector3.new(1.7, 1.7, 1.7), CFrame.new(pp + Vector3.new(0, 13.2, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0), tint, Enum.Material.Neon)
			gem.Transparency = 0.15
			fx(gem, { FxSpin = 80, FxBob = 0.45, FxBobSpeed = 2 + i * 0.3 })
			glow(gem, tint, 12, 0.7)
		end
	end
	return core, f:FindFirstChild("Pedestal") :: Part
end

local function buildOffering(l: Lane, root: Folder, pos: Vector3, idx: number?)
	local style = FACTION_STYLE[l.Faction]
	local tint = Color3.fromRGB(190, 120, 255)
	local core, pedestal = altarBase(root, "AltarOfrenda_" .. l.Faction .. "_" .. l.Strip .. (if idx then "_" .. idx else ""), pos, style, tint, CampArt.OfferingBy[l.Faction] or CampArt.Offering, "ofrenda", l.Faction)
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
		if DailyLimits.Remaining(player, "Offering", l.Strip) <= 0 then
			notify(player, string.format("Ofrenda: ya hiciste tus %d de hoy en la Franja %d. Vuelve mañana", DailyLimits.Limit("Offering", l.Strip), l.Strip))
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
			DailyLimits.Use(player, "Offering", l.Strip)
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
	local core, pedestal = altarBase(root, "AltarDesafio_" .. l.Faction .. "_" .. l.Strip .. (if idx then "_" .. idx else ""), pos, style, tint, CampArt.ChallengeBy[l.Faction] or CampArt.Challenge, "desafio", l.Faction)
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
	body.Transparency = 1
	local closedId = CampArt.ChestClosed[l.Faction]
	local openId = CampArt.ChestOpen[l.Faction]
	local chestImg: ImageLabel? = nil
	if closedId then
		local g = CampArt.Sprite(body, "Cofre", closedId, 7.5, 7.5, 1.3, 140)
		chestImg = g:FindFirstChild("Img") :: ImageLabel?
	end
	local latch = mk(f, "Cierre", Vector3.new(0.8, 1, 0.5), base * CFrame.new(0, 2.7, -1.7), Color3.fromRGB(255, 225, 120), Enum.Material.Neon)
	latch.Transparency = 1
	glow(latch, Color3.fromRGB(255, 220, 120), 16, 1.2)
	fx(latch, { FxPulse = 0.35 })
	local _ = style
	local busy = false
	local keyId = "Key_" .. l.Strip
	local pp = prompt(body, "Abrir cofre (usa 1 llave)", "Cofre sellado · Franja " .. l.Strip, 1.2, Enum.KeyCode.E)
	label(body, "COFRE SELLADO", Color3.fromRGB(255, 225, 120), 6.2, UDim2.fromOffset(150, 24))
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
		if chestImg and openId then
			chestImg.Image = CampArt.Url(openId)
		end
		task.delay(LootTables.MapChest.AnimSeconds, function()
			if chestImg and closedId and chestImg.Parent then
				chestImg.Image = CampArt.Url(closedId)
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
	local sprites: { BillboardGui } = {}
	local artId = (CampArt.Resource[l.Strip] or {})[l.Faction]
	local mainPart = mk(f, "Nodo", Vector3.new(3, 3, 3), CFrame.new(pos + Vector3.new(0, 3, 0)), color, Enum.Material.Neon, Enum.PartType.Ball)
	mainPart.Transparency = 1
	if artId then
		table.insert(sprites, CampArt.Sprite(mainPart, "Recurso", artId, 8, 8, 0, 130))
	end
	sparks(mainPart, color:Lerp(Color3.new(1, 1, 1), 0.4), 4, 2.4, 1.5, 0.35, 1)
	glow(mainPart, color, 14, 1)
	fx(mainPart, { FxPulse = 0.3 })
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
		for _, g in ipairs(sprites) do
			g.Enabled = false
		end
		local lgt = mainPart:FindFirstChildOfClass("PointLight")
		if lgt then
			lgt.Enabled = false
		end
		-- REAPARICIÓN SEGÚN JUGADORES EN LA FRANJA: con 1 jugador tarda lo de siempre (RespawnSeconds); por cada jugador extra en la franja
		-- avanza más rápido (PlayerSpeedup), hasta MaxSpeedup veces. Se recalcula cada segundo, así que si llegan más jugadores acelera.
		-- (opcional: LootTables.Gathering.PlayerSpeedup / MaxSpeedup / MinSeconds para ajustarlo desde ahí)
		local zoneKey = l.Faction .. "_" .. l.Strip
		task.spawn(function()
			local per = (G :: any).PlayerSpeedup or 0.6
			local maxSpeed = (G :: any).MaxSpeedup or 8
			local minSeconds = (G :: any).MinSeconds or 12
			local progress = 0
			local elapsed = 0
			while f.Parent and progress < 1 do
				task.wait(1)
				elapsed += 1
				local n = 0
				for _, pl in ipairs(Players:GetPlayers()) do
					if pl:GetAttribute("BiomeZone") == zoneKey then
						n += 1
					end
				end
				local speed = math.min(maxSpeed, 1 + math.max(0, n - 1) * per)
				progress += speed / G.RespawnSeconds
				if elapsed >= G.RespawnSeconds then
					break -- nunca tarda más que antes
				end
				if elapsed < minSeconds and progress >= 1 then
					progress = 0.999 -- tiempo mínimo para que no reaparezca al instante
				end
			end
			if f.Parent then
				for _, g in ipairs(sprites) do
					g.Enabled = true
				end
				if lgt then
					lgt.Enabled = true
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
	local RED = Color3.fromRGB(255, 70, 60)
	local OBS = Color3.fromRGB(34, 26, 30)
	local lairDisc = cyl(f, "Guarida", 28, 0.4, pos + Vector3.new(0, 0.2, 0), OBS, Enum.Material.Slate, false)
	local lairArt = CampArt.LairBy[l.Faction]
	if lairArt then
		CampArt.Decal(lairDisc, Enum.NormalId.Right, lairArt, "Arte")
	end
	local aro = cyl(f, "GuaridaAro", 29.2, 0.3, pos + Vector3.new(0, 0.15, 0), RED, Enum.Material.Neon, false)
	fx(aro, { FxFade = 0.2 })
	local aroF = cyl(f, "GuaridaAroFaccion", 30.4, 0.2, pos + Vector3.new(0, 0.1, 0), style.Accent, Enum.Material.Neon, false)
	aroF.Transparency = 0.4
	for k = 0, 5 do -- cuentas rojas que orbitan al ras del suelo
		local b = mk(f, "GuaridaCuenta", Vector3.new(0.9, 0.9, 0.9), CFrame.new(pos), RED, Enum.Material.Neon, Enum.PartType.Ball)
		fx(b, { FxCenter = pos, FxOrbitR = 9.4, FxOrbitSpeed = -30, FxOrbitPhase = k * 60, FxOrbitY = 0.9, FxBob = 0.25, FxBobSpeed = 2.4 })
	end
	-- garras de obsidiana alrededor (6), tres con fuego
	for i = 1, 6 do
		local a = i * math.pi / 3
		local dirOut = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = pos + dirOut * 13.4
		local claw = mk(f, "Garra", Vector3.new(1.5, 11, 1.5), CFrame.new(base + Vector3.new(0, 5, 0) + dirOut * 0.9) * CFrame.Angles(math.sin(a) * math.rad(14), 0, -math.cos(a) * math.rad(14)), Color3.fromRGB(44, 36, 42), Enum.Material.Basalt, nil, true)
		local tip = mk(f, "GarraPunta", Vector3.new(1.1, 1.1, 1.1), CFrame.new(base + Vector3.new(0, 10.3, 0) + dirOut * 2.2), RED, Enum.Material.Neon, Enum.PartType.Ball)
		tip.Transparency = 0.2
		mk(f, "GarraVeta", Vector3.new(0.25, 6, 0.25), claw.CFrame * CFrame.new(0, 0, -0.78), RED, Enum.Material.Neon).Transparency = 0.3
		if i % 2 == 1 then
			local fi = Instance.new("Fire")
			fi.Heat = 9
			fi.Size = 6
			local fc = FLAME[l.Faction] or { Color3.fromRGB(255, 90, 40), Color3.fromRGB(120, 10, 20) }
			fi.Color = fc[1]
			fi.SecondaryColor = fc[2]
			tip.Color = fc[1]
			fi.Parent = tip
			glow(tip, RED, 16, 1)
			tip:SetAttribute("FxPulse", 0.5)
			CollectionService:AddTag(tip, "FxAnim")
		end
	end
	-- brasas que suben y bruma roja baja
	local em = mk(f, "GuaridaBrasas", Vector3.new(24, 1, 24), CFrame.new(pos + Vector3.new(0, 0.8, 0)), RED, Enum.Material.SmoothPlastic)
	em.Transparency = 1
	sparks(em, Color3.fromRGB(255, 120, 60), 12, 3.2, 5, 0.6, 3)
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(150, 20, 30))
	mist.LightEmission = 0.4
	mist.Rate = 3
	mist.Lifetime = NumberRange.new(4, 6)
	mist.Speed = NumberRange.new(0.5, 1.2)
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 11) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 0.88), NumberSequenceKeypoint.new(1, 1) })
	mist.Acceleration = Vector3.new(0, 0.6, 0)
	mist.Parent = em
	glow(em, RED, 28, 0.9)
	em:SetAttribute("FxPulse", 0.35)
	CollectionService:AddTag(em, "FxAnim")
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
	-- nidos de huevos de montura (vigilados por monstruos de la franja)
	local nestDefs = normalsOf(l)
	for i = 1, MountCatalog.Nest.PerStrip[l.Strip] or 1 do
		local p = pick(0.1, 0.94, 110)
		if p then
			table.insert(placed, p)
			NestService.Build(root, p, l.Strip, i, nestDefs)
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
	NestService.Clear()
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
