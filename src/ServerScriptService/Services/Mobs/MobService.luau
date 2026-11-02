--!strict
--[[
    MobService (ModuleScript) -> ServerScriptService.Services.Mobs.MobService
    CICLO DE VIDA de los enemigos de las 12 franjas (3 naciones × 4 franjas):
      1. Lee el mapa (partes con tag "ZonePvE" + atributos Biome/Strip) y genera PUNTOS DE SPAWN durmientes:
         GRUPOS de 1 a 4 enemigos repartidos según el ÁREA de cada franja (evita zonas con tag "MobNoSpawn") + 1 punto de jefe al fondo.
      2. Un bucle (1 s) ACTIVA los puntos con jugadores cerca (ACTIVATE_RADIUS) y DESACTIVA los que quedan lejos.
         Así puede haber cientos de puntos pero solo existen unos pocos mobs a la vez.
      3. Un bucle central (10 Hz) ejecuta MobBrain.Step de los mobs activos. (Un solo Heartbeat, no uno por mob.)
      4. Al morir: RewardService reparte XP/botín, el cadáver desaparece y el punto reaparece (normal 20 s, jefe 5 min).
    API: SpawnAt(defId, cframe, level?) para pruebas/eventos, ActiveCount(), ClearAll(), SpawnMini / Despawn (mini jefes de franja).
    Zonas con tag "ZoneCamp" (campamentos): ahí no nace ningún grupo.
    Cualquier enemigo propio (Metin, jefe mundial) puede usar DamageService siempre que tenga atributos IsMob=true y Level.
]]
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local Services = ServerScriptService.Services
local MobsFolder = Services.Mobs
local MobLooks = require(MobsFolder.MobLooks)
local MobBuilder = require(MobsFolder.MobBuilder)
local MobBrain = require(MobsFolder.MobBrain)
local DamageService = require(Services.DamageService)
local RewardService = require(Services.RewardService)

-- Ajustes
local MAP_NAME = "Map_WC3_Style"
local GROUP_AREA = 9000 -- 1 grupo de enemigos por cada ~9000 studs² de franja
local MAX_GROUPS_PER_STRIP = 200
local GROUP_SPACING = 45 -- distancia mínima entre grupos (franjas 1 y 2)
-- Franjas 3 y 4 (difíciles): grupos muy separados para pelear y moverte sin que te agarre un segundo grupo
-- (AGGRO 55 + aviso de grupo 60 + persecución 80 -> 150 de separación entre centros)
local HARD_GROUP_SPACING = 150
local HARD_GROUP_AREA = 30000
local EDGE_STRIP = 35 -- margen contra el inicio/fin de la franja
local EDGE_BAND = 20 -- margen entre sub-bandas de nivel dentro de la franja
local EDGE_SIDE = 45 -- margen contra la diagonal lateral (muro invisible): nadie nace al borde
local GROUP_RADIUS = 9 -- radio del grupo (los miembros nacen juntos)
local GROUP_SIZES = { 2, 2, 3, 3, 3 } -- tamaño al azar de cada grupo: 2 o 3 enemigos
local NOSPAWN_MARGIN = 10
local ACTIVATE_RADIUS = 170
local DEACTIVATE_RADIUS = 260
local RESPAWN_NORMAL = 20
local RESPAWN_BOSS = 300
local SUMMON_LIFETIME = 60

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

type Point = {
	Pos: Vector3,
	Def: MobCatalog.MobDef,
	Mob: Mob?,
	RespawnAt: number,
	Cell: string,
	Group: number,
}
type Mob = MobBrain.Mob

local MobService = {}

local points: { Point } = {}
local active: { [Model]: Mob } = {}
local activeCount = 0
local mobsFolder = Instance.new("Folder")
mobsFolder.Name = "Mobs"
mobsFolder.Parent = Workspace

---------------------------------------------------------------------
-- CREACIÓN
---------------------------------------------------------------------
local function pickLevel(def: MobCatalog.MobDef): number
	if def.Boss then
		return def.MaxLevel
	end
	return math.random(def.MinLevel, def.MaxLevel)
end

-- Al morir el cuerpo se vuelve intangible y se desvanece: no empuja ni hace rebotar al jugador, y no se puede marcar
local function fadeCorpse(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			if d.Transparency < 1 then
				game:GetService("TweenService"):Create(d, TweenInfo.new(0.45), { Transparency = 1 }):Play()
			end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			d.Transparency = 1
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Fire") then
			d.Enabled = false
		end
	end
end

-- Opciones de un mini jefe (PveZoneService): más vida, más grande, más daño, XP y botín propios
type MiniOpts = { HpMult: number, DmgMult: number, Scale: number, Title: string, XpMult: number, OnDied: ((Model) -> ())? }

local function create(def: MobCatalog.MobDef, cf: CFrame, level: number, summoned: boolean, point: Point?, mini: MiniOpts?): Mob?
	local look = MobLooks[def.Id]
	if not look then
		warn("[MobService] Sin Look para " .. def.Id)
		return nil
	end
	local model = MobBuilder.Build(look, if mini then string.format("Nv.%d %s", level, mini.Title) else string.format("Nv.%d %s", level, def.Name))
	if mini then
		model:ScaleTo(model:GetScale() * mini.Scale)
		model:SetAttribute("Mini", true)
		model:SetAttribute("DmgBuff", mini.DmgMult)
		model:SetAttribute("BaseBuff", mini.DmgMult)
	end
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local hp = math.floor(GB.MobHp(level) * (if mini then mini.HpMult elseif def.Boss then GB.EliteHpMult(def.Strip) else 1))
	hum.MaxHealth = hp
	hum.Health = hp
	hum.WalkSpeed = def.Speed
	model:SetAttribute("IsMob", true)
	model:SetAttribute("MobId", def.Id)
	model:SetAttribute("Level", level)
	model:SetAttribute("Boss", def.Boss)
	model:SetAttribute("MaxHp", hp)
	model:SetAttribute("Summoned", summoned)
	model:SetAttribute("GroupId", if point then point.Group else 0)
	model:SetAttribute("Faction", def.Faction) -- facción "dueña" del mob (solo informativo)
	CollectionService:AddTag(model, "Mob")
	CollectionService:AddTag(model, "Targetable")

	-- colocar sobre el piso
	model:PivotTo(cf + Vector3.new(0, 3.2 * model:GetScale(), 0))
	model.Parent = mobsFolder
	local root = model.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil) -- el servidor controla la física: nadie del cliente puede manipular al mob
	end)

	local summonFn = function(id: string, count: number)
		MobService.SummonAround(model, id, count)
	end
	local mob = MobBrain.New(model, def, level, summonFn, look.Aura)
	active[model] = mob
	activeCount += 1

	hum.HealthChanged:Connect(function(h)
		MobBrain.OnDamaged(mob, h)
	end)
	hum.Died:Once(function()
		fadeCorpse(model)
		RewardService.OnMobKilled(model, if mini then "Mini|" .. def.Id else def.Id, level, def.Boss, summoned, if mini then mini.XpMult else nil)
		if mini and mini.OnDied then
			task.spawn(mini.OnDied, model)
		end
		active[model] = nil
		activeCount -= 1
		DamageService.Forget(model)
		if point then
			point.Mob = nil
			if def.Boss or point.Group == 0 then
				point.RespawnAt = os.clock() + (if def.Boss then RESPAWN_BOSS else RESPAWN_NORMAL)
			else
				-- Grupo: el cupo queda en espera hasta que muera el ÚLTIMO del grupo; entonces todos renacen juntos
				point.RespawnAt = math.huge
			end
		end
		task.delay(3, function()
			model:Destroy()
		end)
	end)
	if summoned then
		Debris:AddItem(model, SUMMON_LIFETIME)
	end
	return mob
end

function MobService.SpawnAt(defId: string, cf: CFrame, level: number?): Model?
	local def = MobCatalog.ById[defId]
	if not def then
		return nil
	end
	local mob = create(def, cf, level or pickLevel(def), false, nil)
	return if mob then mob.Model else nil
end

-- Monstruo de oleada (Metin): como uno normal (da XP) pero nace ya provocado contra un objetivo
function MobService.SpawnWave(defId: string, cf: CFrame, level: number, target: Model?): Model?
	local def = MobCatalog.ById[defId]
	if not def then
		return nil
	end
	local mob = create(def, cf, level, false, nil)
	if not mob then
		return nil
	end
	mob.Provoked = true
	mob.Target = target
	return mob.Model
end

-- Mini jefe de franja: un mob normal reforzado (vida x HpMult, más grande, XP y botín propios). onDied avisa a PveZoneService.
function MobService.SpawnMini(defId: string, cf: CFrame, level: number, opts: MiniOpts): Model?
	local def = MobCatalog.ById[defId]
	if not def then
		return nil
	end
	local mob = create(def, cf, level, false, nil, opts)
	return if mob then mob.Model else nil
end

-- Retira un mob sin matarlo (sin XP ni botín): lo usa PveZoneService cuando no hay jugadores cerca del mini jefe
function MobService.Despawn(model: Model)
	if active[model] then
		active[model] = nil
		activeCount -= 1
	end
	DamageService.Forget(model)
	RewardService.Forget(model)
	model:Destroy()
end

function MobService.SummonAround(owner: Model, defId: string, count: number)
	local def = MobCatalog.ById[defId]
	local root = owner.PrimaryPart
	if not def or not root then
		return
	end
	local ownerLevel = (owner:GetAttribute("Level") :: number?) or 1
	local lvl = math.clamp(ownerLevel - 3, def.MinLevel, def.MaxLevel)
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local pos = root.Position + Vector3.new(math.cos(a) * 8, -3, math.sin(a) * 8)
		local m = create(def, CFrame.new(pos), lvl, true, nil)
		if m then
			m.Provoked = true
			m.Target = (owner:GetAttribute("LastHitBy") and Players:FindFirstChild(owner:GetAttribute("LastHitBy") :: string) and (Players:FindFirstChild(owner:GetAttribute("LastHitBy") :: string) :: Player).Character) or nil
		end
	end
end

function MobService.ActiveCount(): number
	return activeCount
end

function MobService.ClearAll()
	for model, _ in pairs(active) do
		model:Destroy()
	end
	table.clear(active)
	activeCount = 0
	for _, p in ipairs(points) do
		p.Mob = nil
	end
end

---------------------------------------------------------------------
-- GENERACIÓN DE PUNTOS (a partir del mapa)
---------------------------------------------------------------------
local function cellKey(pos: Vector3): string
	return string.format("%d,%d", math.floor(pos.X / 128), math.floor(pos.Z / 128))
end

local function randomPointIn(part: BasePart): Vector3
	local s = part.Size
	local x = (math.random() - 0.5) * (s.X - 12)
	local z = (math.random() - 0.5) * (s.Z - 12)
	local worldTop = part.CFrame:PointToWorldSpace(Vector3.new(x, s.Y / 2, z))
	return worldTop
end

-- ¿La posición cae dentro de una zona reservada? Pon el tag "MobNoSpawn" a cualquier Part (río, bosque, lago, plaza...)
-- y ningún grupo de enemigos nacerá encima. Útil para el diseño futuro del ambiente.
local function blocked(pos: Vector3): boolean
	for _, z in ipairs(CollectionService:GetTagged("MobNoSpawn")) do
		if z:IsA("BasePart") then
			local l = z.CFrame:PointToObjectSpace(pos)
			if math.abs(l.X) <= z.Size.X / 2 + NOSPAWN_MARGIN and math.abs(l.Z) <= z.Size.Z / 2 + NOSPAWN_MARGIN then
				return true
			end
		end
	end
	return false
end

local function buildPoints()
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		warn("[MobService] No existe " .. MAP_NAME .. ": ¿corrió ProjectBootstrapper?")
		return
	end
	local slices: { [string]: { [number]: { BasePart } } } = {}
	for _, p in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if p:IsA("BasePart") and p:IsDescendantOf(map) then
			local biome = p:GetAttribute("Biome")
			local strip = p:GetAttribute("Strip")
			if typeof(biome) == "string" and typeof(strip) == "number" then
				slices[biome] = slices[biome] or {}
				slices[biome][strip] = slices[biome][strip] or {}
				table.insert(slices[biome][strip], p)
			end
		end
	end

	local total, groupId = 0, 0
	for biome, faction in pairs(BIOME_FACTION) do
		for strip = 1, 4 do
			local parts = slices[biome] and slices[biome][strip]
			if not parts or #parts == 0 then
				warn(string.format("[MobService] Sin partes ZonePvE para %s franja %d", biome, strip))
				continue
			end
			local defs = MobCatalog.ForStrip(faction, strip)
			local normals: { MobCatalog.MobDef } = {}
			local boss: MobCatalog.MobDef? = nil
			for _, d in ipairs(defs) do
				if d.Boss then
					boss = d
				else
					table.insert(normals, d)
				end
			end

			-- la densidad depende del ÁREA real de la franja (las franjas 3 y 4 son más anchas -> más grupos)
			local area, farthest = 0, parts[1]
			local weights: { number } = {}
			for _, p in ipairs(parts) do
				local a = p.Size.X * p.Size.Z
				area += a
				table.insert(weights, a)
				if ((p:GetAttribute("UEnd") :: number?) or 0) > ((farthest:GetAttribute("UEnd") :: number?) or 0) then
					farthest = p
				end
			end
			local hard = strip >= 3
			local spacing = if hard then HARD_GROUP_SPACING else GROUP_SPACING
			local groups = math.clamp(math.floor(area / (if hard then HARD_GROUP_AREA else GROUP_AREA)), 8, MAX_GROUPS_PER_STRIP)
			local centers: { Vector3 } = {}

			-- Geometría del carril (la deja ProjectBootstrapper en cada losa). Con ella cada tipo de enemigo nace en su
			-- SUB-BANDA de la franja (ordenados por nivel: el de nivel más bajo cerca de la entrada, el más alto al fondo)
			-- y siempre a EDGE_* studs de los bordes.
			local p1 = parts[1]
			local laneStart = p1:GetAttribute("LaneStart")
			local laneDir = p1:GetAttribute("LaneDir")
			local fanC, fanK = p1:GetAttribute("FanC"), p1:GetAttribute("FanK")
			local u0, u1 = p1:GetAttribute("UStart"), p1:GetAttribute("UEnd")
			local hasLane = typeof(laneStart) == "Vector3" and typeof(laneDir) == "Vector3" and typeof(fanC) == "number" and typeof(fanK) == "number"
				and typeof(u0) == "number" and typeof(u1) == "number"
			local floorY = p1.Position.Y + p1.Size.Y / 2
			table.sort(normals, function(a, b)
				return a.MinLevel < b.MinLevel
			end)
			local function lanePoint(u: number, v: number): Vector3
				local d = laneDir :: Vector3
				local side = Vector3.new(-d.Z, 0, d.X)
				local p = (laneStart :: Vector3) + d * u + side * v
				return Vector3.new(p.X, floorY, p.Z)
			end
			local function pickPart(): BasePart
				local r = math.random() * area
				for k, p in ipairs(parts) do
					r -= weights[k]
					if r <= 0 then
						return p
					end
				end
				return parts[#parts]
			end

			local function pointFor(typeIndex: number): Vector3
				if not hasLane then
					return randomPointIn(pickPart())
				end
				local a, b = u0 :: number, u1 :: number
				local band = (b - a) / math.max(1, #normals)
				local lo = a + (typeIndex - 1) * band + (if typeIndex == 1 then EDGE_STRIP else EDGE_BAND)
				local hi = a + typeIndex * band - (if typeIndex == #normals then EDGE_STRIP else EDGE_BAND)
				local u = lo + math.random() * math.max(1, hi - lo)
				local half = (fanC :: number) + (fanK :: number) * u - EDGE_SIDE
				return lanePoint(u, (math.random() * 2 - 1) * math.max(10, half))
			end

			local made, tries = 0, 0
			while made < groups and tries < groups * (if hard then 80 else 25) do
				tries += 1
				local typeIndex = (made) % math.max(1, #normals) + 1
				local center = pointFor(typeIndex)
				local ok = not blocked(center)
				if ok then
					for _, c in ipairs(centers) do
						if (c - center).Magnitude < spacing then
							ok = false
							break
						end
					end
				end
				if ok and #normals > 0 then
					table.insert(centers, center)
					made += 1
					groupId += 1
					local def = normals[(made - 1) % #normals + 1] -- reparte los tipos de enemigo por igual
					local size = GROUP_SIZES[math.random(1, #GROUP_SIZES)]
					for k = 1, size do
						local ang = (k / size) * math.pi * 2 + math.random() * 0.5
						local off = if size == 1 then Vector3.zero else Vector3.new(math.cos(ang), 0, math.sin(ang)) * GROUP_RADIUS
						table.insert(points, { Pos = center + off, Def = def, Mob = nil, RespawnAt = 0, Cell = cellKey(center), Group = groupId })
						total += 1
					end
				end
			end
			if boss then
				local bossPos = if hasLane then lanePoint((u1 :: number) - 120, 0) else farthest.CFrame:PointToWorldSpace(Vector3.new(0, farthest.Size.Y / 2, 0))
				table.insert(points, { Pos = bossPos, Def = boss, Mob = nil, RespawnAt = 0, Cell = "boss", Group = 0 })
				total += 1
			end
			print(string.format("[MobService] %s franja %d: %d grupos (área %d)", faction, strip, made, math.floor(area)))
		end
	end
	print(string.format("[MobService] %d puntos de spawn generados (durmientes).", total))
end

---------------------------------------------------------------------
-- ACTIVACIÓN POR PROXIMIDAD (cada 1 s)
---------------------------------------------------------------------
local function playerPositions(): { Vector3 }
	local out: { Vector3 } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			table.insert(out, r.Position)
		end
	end
	return out
end

local function nearest(pos: Vector3, list: { Vector3 }): number
	local best = math.huge
	for _, p in ipairs(list) do
		local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
		if d < best then
			best = d
		end
	end
	return best
end

-- Campamentos (tag "ZoneCamp"): ningún grupo nace dentro ni pegado a ellos
local CAMP_MARGIN = 16
local function campParts(): { BasePart }
	local out: { BasePart } = {}
	for _, z in ipairs(CollectionService:GetTagged("ZoneCamp")) do
		if z:IsA("BasePart") then
			table.insert(out, z)
		end
	end
	return out
end

local function inCamp(pos: Vector3, camps: { BasePart }): boolean
	for _, z in ipairs(camps) do
		local l = z.CFrame:PointToObjectSpace(pos)
		if math.abs(l.X) <= z.Size.X / 2 + CAMP_MARGIN and math.abs(l.Z) <= z.Size.Z / 2 + CAMP_MARGIN then
			return true
		end
	end
	return false
end

local function refresh()
	local ppos = playerPositions()
	local camps = campParts()
	local now = os.clock()
	-- Renacimiento por grupo: si ya no queda ningún miembro vivo, arranca la cuenta para TODO el grupo
	local groups: { [number]: { alive: boolean, waiting: boolean } } = {}
	for _, pt in ipairs(points) do
		if pt.Group ~= 0 then
			local g = groups[pt.Group]
			if not g then
				g = { alive = false, waiting = false }
				groups[pt.Group] = g
			end
			if pt.Mob ~= nil then
				g.alive = true
			elseif pt.RespawnAt == math.huge then
				g.waiting = true
			end
		end
	end
	for _, pt in ipairs(points) do
		local g = groups[pt.Group]
		if g and g.waiting and not g.alive and pt.RespawnAt == math.huge then
			pt.RespawnAt = now + RESPAWN_NORMAL
		end
	end
	for _, pt in ipairs(points) do
		local d = nearest(pt.Pos, ppos)
		if pt.Mob == nil then
			if d <= ACTIVATE_RADIUS and now >= pt.RespawnAt and not inCamp(pt.Pos, camps) then
				local mob = create(pt.Def, CFrame.new(pt.Pos), pickLevel(pt.Def), false, pt)
				pt.Mob = mob
			end
		else
			local mob = pt.Mob :: Mob
			if d > DEACTIVATE_RADIUS and mob.Target == nil and mob.Humanoid.Health >= mob.Humanoid.MaxHealth then
				active[mob.Model] = nil
				activeCount -= 1
				mob.Model:Destroy()
				pt.Mob = nil
			end
		end
	end
end

---------------------------------------------------------------------
-- BUCLE CENTRAL
---------------------------------------------------------------------
local acc = 0
local acc2 = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	acc2 += dt
	if acc >= 0.1 then
		local step = acc
		acc = 0
		local now = os.clock()
		for model, mob in pairs(active) do
			if model.Parent then
				MobBrain.Step(mob, step, now)
			end
		end
	end
	if acc2 >= 1 then
		acc2 = 0
		refresh()
	end
end)

task.spawn(function()
	local t = 0
	while (not Workspace:FindFirstChild(MAP_NAME) or Workspace:GetAttribute("MapBuilt") ~= true) and t < 60 do
		task.wait(1)
		t += 1
	end
	task.wait(1) -- deja que el Bootstrapper termine de etiquetar
	buildPoints()
end)

return MobService
