--!strict
--[[
    AutoFarmService (ModuleScript) -> ServerScriptService.Services.AutoFarmService
    AUTO-FARM (solo PvE): el personaje elige objetivo y lanza sus poderes solo, con criterio.
    El jugador lo prende/apaga desde el cartel del HUD (o con la tecla Z). En la Arena (PvP) NO funciona: ahí todo es manual.

    MODOS
      Semi      : el jugador mueve el personaje; el auto-farm elige objetivo y lanza poderes + auto-ataque.
      Metin     : ataca la piedra Metin y sus oleadas (camina solo hasta ella).
      Jefe      : ataca al jefe mundial y a sus súbditos (camina solo hasta él).
      (Los modos "Quieto" y "Perseguir" se eliminaron: el caminado automático por las franjas no era fluido.)

    CRITERIO DE PODERES (usa los MISMOS chequeos que a mano: recarga, ki, silencio, aturdimiento)
      1. Curas / defensas cuando la vida o la de un aliado baja.
      2. Provocación y buffs al empezar una pelea grande o contra un élite.
      3. Poderes de área solo si hay 3+ mobs agrupados (2+ si hay un élite) y apuntados al mejor grupo.
      4. Poderes de un objetivo sobre el objetivo; marcas / silencios solo contra élites.
      Reserva de ki: no gasta los poderes normales con menos de 20% de ki. NUNCA se apaga por vida/ki bajos (apagarse = morir):
      se cura temprano (con 75% de vida), usa escudos/defensas y, si hay Poción de Vida / de Energía configurada, la toma sola.
      Esquiva las zonas rojas de los poderes en área y en línea de los enemigos (tag "MobTelegraph").
      Pociones: ajustes del jugador por atributos AF_HpPct / AF_EnPct (0 = apagado) y AF_HpItem / AF_EnItem ("" = detectar sola).

    Cliente -> servidor: remote "AutoFarm" ("Set", encendido: boolean, modo: string)
    Servidor -> cliente: atributos del Player: AutoFarm (bool) · AutoFarmMode · AutoFarmStatus (texto)
                          y remote "AutoFarmMove"(Vector3?) con el punto o el objetivo al que debe caminar (modos Metin y Jefe).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PathfindingService = game:GetService("PathfindingService")
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local PartyService = require(ServerScriptService.Services.PartyService)
local AutoAttack = require(Services.AutoAttackService)
local AbilityService = require(Services.AbilityService)
local CombatService = require(Services.CombatService)
local ArenaService = require(Services.ArenaService)
local EnergyRegenService = require(Services.EnergyRegenService)
local DamageService = require(Services.DamageService)
local Inventory = require(Services.InventoryService)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local AlchemyCatalog = require(ReplicatedStorage.Modules.AlchemyCatalog)

local SetRemote = Net.Get("AutoFarm")
local MoveRemote = Net.Get("AutoFarmMove")
local NotifyRemote = Net.Get("Notify")

local MODES = { Semi = true, Metin = true, Jefe = true }
local STRIP_EDGE_U = 40 -- margen contra inicio/fondo de la franja al caminar
local STRIP_EDGE_V = 60 -- margen contra las diagonales laterales (muro invisible)
local CHASE_EDGE_U = 12 -- al PERSEGUIR un mob se acerca hasta cerca del borde (antes quedaba parado a 40-60 studs de los mobs de los bordes)
local CHASE_EDGE_V = 18
local PATH_EVERY = 1.5
local TICK = 0.3
local MIN_CAST_GAP = 0.5 -- segundos entre poderes (deja que se vea la animación)
local SCAN_SEMI = 42 -- en Semi (el jugador se mueve) busca cerca de él
local AOE_MIN = 3
local KI_RESERVE = 0.2
local DODGE_TICK = 0.1
local DODGE_MARGIN = 3
local POTION_GAP = 1.0 -- segundos mínimos entre pociones

type Strip = { Biome: string, Index: number, Start: Vector3, Dir: Vector3, C: number, K: number, U0: number, U1: number, Y: number }
type State = {
	Enabled: boolean, Mode: string, Origin: Vector3, Next: number, LastCast: number,
	Strip: Strip?, Patrol: Vector3?, PatrolAt: number, Path: { Vector3 }?, PathGoal: Vector3?, PathAt: number, PathBusy: boolean,
	Close: boolean, DodgeUntil: number, Ignore: { [Model]: number }, TgtModel: Model?, TgtHp: number, TgtSince: number, PotionAt: { [string]: number }, LastPos: Vector3, LastPosAt: number,
}
local states: { [Player]: State } = {}

-- Categorías de los poderes 3 y 4 (por Kind del catálogo)
local CAT: { [string]: string } = {
	Taunt = "taunt", ShieldGroup = "shield", Blink = "gap", Dash = "move", SelfBlast = "aoe_self", LineSlow = "line",
	Channel = "aoe_self", Aura = "buff", HealGroup = "heal", HealOverTime = "heal", Revive = "never", Wall = "defense",
	Clones = "offense_buff", Buff = "buff", Mark = "mark", Silence = "silence", RootArea = "aoe_target", Pull = "aoe_self",
	Smoke = "defense", Guard = "buff", MultiHit = "single", AoeBurn = "aoe_target",
}
local SKILLTYPE_CAT: { [string]: string } = { Damage = "single", AoE_Damage = "aoe_target", Healing = "heal", Shield = "shield", CrowdControl = "cc" }
local PRIORITY: { [string]: number } = {
	heal = 1, heal7 = 1, defense = 2, shield = 3, taunt = 4, buff = 5, offense_buff = 6, aoe_self = 7, aoe_target = 7, line = 8, cc = 9,
	mark = 10, silence = 11, single = 12, gap = 13,
}

type Mob = { Model: Model, Root: BasePart, Dist: number, Boss: boolean }
type Skill = { Sys: string, Slot: number, Cat: string, Range: number, Radius: number, Cost: number }

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function status(player: Player, text: string)
	if player:GetAttribute("AutoFarmStatus") ~= text then
		player:SetAttribute("AutoFarmStatus", text)
	end
end

local function disable(player: Player, reason: string?)
	local st = states[player]
	if st then
		st.Enabled = false
	end
	player:SetAttribute("AutoFarm", false)
	status(player, "")
	MoveRemote:FireClient(player, nil)
	if reason then
		NotifyRemote:FireClient(player, reason)
	end
end

---------------------------------------------------------------------
-- FRANJA: geometría (la dejan las losas "ZonePvE" de ProjectBootstrapper: LaneStart/LaneDir/FanC/FanK/UStart/UEnd)
---------------------------------------------------------------------
local function stripAt(pos: Vector3): Strip?
	for _, inst in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if inst:IsA("BasePart") then
			local l = inst.CFrame:PointToObjectSpace(pos)
			local h = inst.Size / 2
			if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z then
				local ls, ld = inst:GetAttribute("LaneStart"), inst:GetAttribute("LaneDir")
				local c, k = inst:GetAttribute("FanC"), inst:GetAttribute("FanK")
				local u0, u1, idx, biome = inst:GetAttribute("UStart"), inst:GetAttribute("UEnd"), inst:GetAttribute("Strip"), inst:GetAttribute("Biome")
				if typeof(ls) == "Vector3" and typeof(ld) == "Vector3" and typeof(c) == "number" and typeof(k) == "number"
					and typeof(u0) == "number" and typeof(u1) == "number" and typeof(idx) == "number" and typeof(biome) == "string" then
					return { Biome = biome, Index = idx, Start = ls, Dir = ld, C = c, K = k, U0 = u0, U1 = u1, Y = inst.Position.Y + inst.Size.Y / 2 }
				end
			end
		end
	end
	return nil
end

local function stripUV(st: Strip, pos: Vector3): (number, number)
	local rel = pos - st.Start
	return rel:Dot(st.Dir), rel:Dot(Vector3.new(-st.Dir.Z, 0, st.Dir.X))
end

-- ¿el punto está dentro de la franja (con margen hacia adentro; margen negativo = tolerancia)?
local function inStrip(st: Strip, pos: Vector3, margin: number): boolean
	local u, v = stripUV(st, pos)
	return u >= st.U0 + margin and u <= st.U1 - margin and math.abs(v) <= st.C + st.K * u - margin
end

local function stripPoint(st: Strip, u: number, v: number): Vector3
	local side = Vector3.new(-st.Dir.Z, 0, st.Dir.X)
	local p = st.Start + st.Dir * u + side * v
	return Vector3.new(p.X, st.Y + 3, p.Z)
end

-- Lleva cualquier punto al interior seguro de la franja
local function clampToStrip(st: Strip, pos: Vector3): Vector3
	local u, v = stripUV(st, pos)
	u = math.clamp(u, st.U0 + STRIP_EDGE_U, st.U1 - STRIP_EDGE_U)
	local half = math.max(10, st.C + st.K * u - STRIP_EDGE_V)
	return stripPoint(st, u, math.clamp(v, -half, half))
end

-- Punto alcanzable al perseguir: como clampToStrip pero con márgenes pequeños
local function clampChase(st: Strip, pos: Vector3): Vector3
	local u, v = stripUV(st, pos)
	u = math.clamp(u, st.U0 + CHASE_EDGE_U, st.U1 - CHASE_EDGE_U)
	local half = math.max(10, st.C + st.K * u - CHASE_EDGE_V)
	return stripPoint(st, u, math.clamp(v, -half, half))
end

local function randomPatrolPoint(st: Strip, near: Vector3): Vector3
	local u0 = stripUV(st, near)
	local u = math.clamp(u0 + (math.random() * 2 - 1) * 160, st.U0 + STRIP_EDGE_U, st.U1 - STRIP_EDGE_U)
	local half = math.max(10, st.C + st.K * u - STRIP_EDGE_V)
	return stripPoint(st, u, (math.random() * 2 - 1) * half)
end

local function liveMobs(origin: Vector3, radius: number, around: Strip?, ignore: { [Model]: number }?): { Mob }
	local out: { Mob } = {}
	local now = os.clock()
	for _, inst in ipairs(CollectionService:GetTagged("Mob")) do
		if inst:IsA("Model") then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") and inst:GetAttribute("Immune") ~= true and inst:GetAttribute("Hidden") ~= true and not (ignore and (ignore[inst] or 0) > now) then
				local d = flatDist(root.Position, origin)
				if d <= radius and math.abs(root.Position.Y - origin.Y) <= 30 and (not around or inStrip(around, root.Position, 0)) then
					table.insert(out, { Model = inst, Root = root, Dist = d, Boss = inst:GetAttribute("Boss") == true })
				end
			end
		end
	end
	return out
end

local function countNear(mobs: { Mob }, center: Vector3, radius: number): number
	local n = 0
	for _, m in ipairs(mobs) do
		if flatDist(m.Root.Position, center) <= radius then
			n += 1
		end
	end
	return n
end

-- Aliado a curar: compañeros de grupo (hasta 60 studs) o de la misma facción (hasta 40). Devuelve el de menos vida bajo el umbral.
local function alliesHurt(player: Player, root: BasePart): (boolean, BasePart?)
	if player:GetAttribute("AF_AllyHeal") == false then
		return false, nil
	end
	local thr = player:GetAttribute("AF_AllyPct")
	local limit = if typeof(thr) == "number" then thr else 0.7
	local worst: BasePart? = nil
	local worstPct = limit
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("Faction") == player:GetAttribute("Faction") then
			local c = other.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if h and r and r:IsA("BasePart") and h.Health > 0 then
				local d = flatDist(r.Position, root.Position)
				local maxD = if PartyService.SameParty(player, other) then 60 else 40
				local pct = h.Health / h.MaxHealth
				if d <= maxD and pct < worstPct then
					worstPct, worst = pct, r
				end
			end
		end
	end
	return worst ~= nil, worst
end

-- Elige el objetivo: cerca, rodeado de otros mobs, élites con prioridad y sin cambiar sin motivo
local function pickTarget(mobs: { Mob }, current: Model?, maxDist: number): Model?
	local best: Model? = nil
	local bestScore = -math.huge
	for _, m in ipairs(mobs) do
		if m.Dist <= maxDist then
			local score = -m.Dist + countNear(mobs, m.Root.Position, 12) * 6 + (if m.Boss then 15 else 0) + (if m.Model == current then 12 else 0)
			if score > bestScore then
				bestScore = score
				best = m.Model
			end
		end
	end
	return best
end

-- multiplicador de alcance real del personaje: poder temporal (RangeMult) x bono de set completo (SetRange)
local function rangeMultOf(char: Model): number
	local rm, sr = char:GetAttribute("RangeMult"), char:GetAttribute("SetRange")
	return (if typeof(rm) == "number" then rm else 1) * (if typeof(sr) == "number" then sr else 1)
end

local function skillsOf(player: Player, rangeMult: number): { Skill }
	local list: { Skill } = {}
	local class = PlayerClass.Get(player)
	for slot = 1, 2 do
		local sk = if slot == 1 then class.PrimarySkill else class.SecondarySkill
		if CombatService.Ready(player, slot) then
			table.insert(list, { Sys = "C", Slot = slot, Cat = SKILLTYPE_CAT[sk.SkillType] or "single", Range = sk.Range * rangeMult, Radius = sk.AoERadius or 0, Cost = sk.EnergyCost })
		end
	end
	for slot = 3, 6 do
		local ab = AbilityService.Info(player, slot)
		if ab and AbilityService.Ready(player, slot) then
			local cat = CAT[ab.Kind] or "never"
			local radius = ab.Radius
			if cat == "aoe_self" and radius <= 0 then
				cat = "single"
			end
			table.insert(list, { Sys = "A", Slot = slot, Cat = cat, Range = math.max(ab.Range, radius), Radius = radius, Cost = ab.Cost })
		end
	end
	if AbilityService.SelfHealReady(player) then
		table.insert(list, { Sys = "A", Slot = 7, Cat = "heal7", Range = 0, Radius = 0, Cost = 15 })
	end
	table.sort(list, function(a, b)
		local pa, pb = PRIORITY[a.Cat] or 99, PRIORITY[b.Cat] or 99
		if pa ~= pb then
			return pa < pb
		end
		return a.Cost > b.Cost
	end)
	return list
end

type Ctx = {
	Mode: string, HpPct: number, KiFrac: number, Root: BasePart, Mobs: { Mob }, Target: Mob?, TargetBoss: boolean,
	Boss: boolean, Engaged: boolean, AllyHurt: boolean, AllyDist: number, Near30: number,
}

-- ¿Conviene lanzar este poder ahora? Devuelve (sí/no, objetivo al que apuntar)
local function decide(sk: Skill, ctx: Ctx): (boolean, Model?)
	local cat = sk.Cat
	local t = ctx.Target
	if cat == "heal7" then
		return ctx.HpPct < 0.6, nil -- curación propia (poder 7): se usa antes de quedar en peligro
	end
	if cat == "heal" then
		-- se cura TEMPRANO. Al aliado herido cuando está dentro del ALCANCE REAL del poder:
		--   poderes con alcance (cura a 3 aliados, cura repartida...: Range 30-40) -> usa el alcance; el servidor elige solo a los más heridos
		--   poderes 1-2 de cura (centrados en ti) y curas de área -> usa su radio
		local reach = if sk.Sys == "A" then math.max(sk.Range, sk.Radius, 10) else math.max(sk.Radius, 10)
		return ctx.HpPct < 0.75 or (ctx.AllyHurt and ctx.AllyDist <= reach - 1), nil
	elseif cat == "defense" then
		return ctx.Engaged and ctx.HpPct < 0.7, nil
	elseif cat == "shield" then
		return ctx.Engaged and (ctx.HpPct < 0.95 or ctx.Boss or ctx.Near30 >= 2), nil
	elseif cat == "taunt" then
		return countNear(ctx.Mobs, ctx.Root.Position, math.max(sk.Radius, 18)) >= AOE_MIN or (ctx.Boss and ctx.Engaged), nil
	elseif cat == "buff" then
		return ctx.Engaged and (ctx.Boss or ctx.Near30 >= AOE_MIN) and ctx.KiFrac > 0.4, nil
	elseif cat == "offense_buff" then
		return ctx.Near30 >= 2 or ctx.Boss, if t then t.Model else nil
	elseif cat == "aoe_self" then
		local n = countNear(ctx.Mobs, ctx.Root.Position, math.max(sk.Radius, 8))
		-- usa el área si conviene: 2+ enemigos, o incluso contra 1 si hay ki de sobra (no mide cuántos rivales hay)
		return (n >= 2 or (n >= 1 and ctx.KiFrac > 0.5) or ctx.Boss) and ctx.KiFrac > KI_RESERVE, if t then t.Model else nil
	elseif cat == "aoe_target" then
		-- mejor grupo: el mob dentro del alcance con más mobs a su alrededor
		local bestN, bestM = 0, nil :: Model?
		for _, m in ipairs(ctx.Mobs) do
			if m.Dist <= sk.Range + 2 then
				local n = countNear(ctx.Mobs, m.Root.Position, math.max(sk.Radius, 8))
				if n > bestN then
					bestN, bestM = n, m.Model
				end
			end
		end
		return (bestN >= 2 or (bestN >= 1 and ctx.KiFrac > 0.5) or (ctx.Boss and bestN >= 1)) and ctx.KiFrac > KI_RESERVE, bestM
	elseif cat == "line" then
		return t ~= nil and t.Dist <= sk.Range and ctx.KiFrac > KI_RESERVE, if t then t.Model else nil
	elseif cat == "cc" then
		return countNear(ctx.Mobs, ctx.Root.Position, 15) >= 2 or (ctx.Boss and ctx.Engaged), if t then t.Model else nil
	elseif cat == "mark" or cat == "silence" then
		return t ~= nil and ctx.TargetBoss and t.Dist <= sk.Range, if t then t.Model else nil
	elseif cat == "single" then
		return t ~= nil and t.Dist <= sk.Range and (ctx.KiFrac > KI_RESERVE or ctx.TargetBoss), if t then t.Model else nil
	elseif cat == "gap" then
		return ctx.Mode ~= "Semi" and t ~= nil and t.Dist > 14 and t.Dist <= sk.Range, if t then t.Model else nil
	end
	return false, nil
end

-- ¿está el punto dentro de una zona segura (ciudad/fuerte)? Piezas con tag ZoneSafe; X/Z dentro de la pieza, Y holgada
local function inSafeZone(pos: Vector3): boolean
	for _, inst in ipairs(CollectionService:GetTagged("ZoneSafe")) do
		if inst:IsA("BasePart") then
			local l = inst.CFrame:PointToObjectSpace(pos)
			local h = inst.Size / 2
			if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z and l.Y >= -h.Y - 5 and l.Y <= h.Y + 80 then
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------------
-- CAMINO: línea recta si está libre; si algo (árbol, roca, muro) la bloquea, calcula una ruta que lo rodea
---------------------------------------------------------------------
local function lineClear(char: Model, from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { char }
	for _, m in ipairs(CollectionService:GetTagged("Mob")) do
		table.insert(ignore, m)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(ignore, pl.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local a = from + Vector3.new(0, 1.5, 0)
	local b = Vector3.new(to.X, a.Y, to.Z)
	return Workspace:Raycast(a, b - a, params) == nil
end

local function dispatchMove(player: Player, st: State, root: BasePart, goal: Vector3?, now: number, chase: Model?, stop: number?)
	-- PERSECUCIÓN EN VIVO: con el objetivo a la vista (sin obstáculos) el cliente lo sigue cada frame hasta quedar a "stop" studs.
	-- (antes el servidor mandaba un punto fijo cada 0,3 s y el personaje llegaba a puntos viejos o se detenía entre órdenes)
	if chase and stop then
		local tr = chase:FindFirstChild("HumanoidRootPart")
		local c0 = player.Character
		if tr and tr:IsA("BasePart") and c0 and lineClear(c0, root.Position, tr.Position) then
			st.Path = nil
			MoveRemote:FireClient(player, { Chase = chase, Stop = stop })
			return
		end
	end
	if not goal then
		st.Path = nil
		MoveRemote:FireClient(player, nil)
		return
	end
	local char = player.Character
	if not char or lineClear(char, root.Position, goal) then
		st.Path = nil
		MoveRemote:FireClient(player, { goal })
		return
	end
	-- bloqueado: ruta con PathfindingService (se recalcula si la meta cambió mucho o pasó un rato)
	local needNew = st.Path == nil or st.PathGoal == nil or (st.PathGoal - goal).Magnitude > 12
	if (needNew or now - st.PathAt > PATH_EVERY * 4) and not st.PathBusy and now - st.PathAt > PATH_EVERY then
		st.PathBusy = true
		st.PathAt = now
		local from = root.Position
		task.spawn(function()
			local path = PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5.5, AgentCanJump = true, WaypointSpacing = 8 })
			local ok = pcall(function()
				path:ComputeAsync(from, goal)
			end)
			st.PathBusy = false
			if ok and path.Status == Enum.PathStatus.Success then
				local pts: { Vector3 } = {}
				for _, w in ipairs(path:GetWaypoints()) do
					table.insert(pts, w.Position)
				end
				st.Path = pts
				st.PathGoal = goal
			else
				st.Path = nil -- sin ruta: el cliente intenta directo y avisa si se atasca
				st.PathGoal = goal
				st.Patrol = nil -- y cambia de meta
			end
		end)
	end
	MoveRemote:FireClient(player, st.Path or { goal })
end

---------------------------------------------------------------------
-- ESQUIVA: los poderes en área (círculo) y en línea (rectángulo) de los enemigos avisan con una zona roja (tag "MobTelegraph")
---------------------------------------------------------------------
local usePotions: (Player, State, Humanoid, number) -> ()

local function dodgeGoal(pos: Vector3, strip: Strip?): Vector3?
	for _, p in ipairs(CollectionService:GetTagged("MobTelegraph")) do
		if p:IsA("BasePart") and p.Parent then
			local kind = p:GetAttribute("TgKind")
			local goal: Vector3? = nil
			if kind == "circle" then
				local c, r = p:GetAttribute("TgCenter"), p:GetAttribute("TgRadius")
				if typeof(c) == "Vector3" and typeof(r) == "number" then
					local off = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
					if off.Magnitude < r + DODGE_MARGIN then
						local dir = if off.Magnitude > 0.5 then off.Unit else Vector3.new(1, 0, 0)
						goal = Vector3.new(c.X, pos.Y, c.Z) + dir * (r + DODGE_MARGIN + 4)
					end
				end
			elseif kind == "box" then
				local l = p.CFrame:PointToObjectSpace(pos)
				local h = p.Size / 2
				if math.abs(l.X) <= h.X + DODGE_MARGIN and math.abs(l.Z) <= h.Z + DODGE_MARGIN then
					local side = if l.X >= 0 then 1 else -1 -- sale por el costado más cercano
					local world = p.CFrame:PointToWorldSpace(Vector3.new(side * (h.X + DODGE_MARGIN + 4), 0, math.clamp(l.Z, -h.Z, h.Z)))
					goal = Vector3.new(world.X, pos.Y, world.Z)
				end
			end
			if goal then
				return if strip then clampToStrip(strip, goal) else goal
			end
		end
	end
	return nil
end

---------------------------------------------------------------------
-- POCIONES (se configuran en la ventana del Auto-farm). % = umbral: por debajo se toma una; 0 = apagado.
---------------------------------------------------------------------
local function findPotion(player: Player, kind: string): string?
	local want = player:GetAttribute(if kind == "Hp" then "AF_HpItem" else "AF_EnItem")
	local field = if kind == "Hp" then "HealPct" else "EnergyPct"
	-- pase "Cinturón de Pociones": con él el auto-farm usa pociones Mayor/Suprema; sin él, solo las base (AlchemyCatalog)
	local belt = player:GetAttribute("Pass_Belt") == true
	if typeof(want) == "string" and want ~= "" and AlchemyCatalog.PotionAllowed(want, belt) then
		local it = ItemCatalog.Items[want]
		if it and it.Use and (it.Use :: any)[field] and Inventory.Count(player, want) > 0 then
			return want
		end
	end
	local ids: { string } = {}
	for id, it in pairs(ItemCatalog.Items) do
		if it.Use and (it.Use :: any)[field] and AlchemyCatalog.PotionAllowed(id, belt) then
			table.insert(ids, id)
		end
	end
	-- "Auto": sin pase = la base (orden alfabético, como siempre); con pase = la MEJOR que tengas
	table.sort(ids, function(a, b)
		if belt and AlchemyCatalog.PotionAllowed(a, true) then
			local pa = (ItemCatalog.Items[a].Use :: any)[field] or 0
			local pb = (ItemCatalog.Items[b].Use :: any)[field] or 0
			if pa ~= pb then
				return pa > pb
			end
		end
		return a < b
	end)
	for _, id in ipairs(ids) do
		if Inventory.Count(player, id) > 0 then
			return id
		end
	end
	return nil
end

local function drink(player: Player, st: State, kind: string, hum: Humanoid, now: number)
	if now < (st.PotionAt[kind] or 0) or now - (st.PotionAt.Any or 0) < POTION_GAP then
		return
	end
	local id = findPotion(player, kind)
	if not id then
		return
	end
	local use = (ItemCatalog.Items[id] :: any).Use
	if not Inventory.Consume(player, id, 1) then
		return
	end
	if kind == "Hp" then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * (use.HealPct or 0))
	else
		local _, mx = EnergyRegenService.GetEnergy(player)
		EnergyRegenService.Gain(player, mx * (use.EnergyPct or 0))
	end
	st.PotionAt[kind] = now + (use.Cooldown or 8)
	st.PotionAt.Any = now
	NotifyRemote:FireClient(player, "Auto-farm usó: " .. (ItemCatalog.Items[id] :: any).Name)
end

usePotions = function(player: Player, st: State, hum: Humanoid, now: number)
	local hp = player:GetAttribute("AF_HpPct")
	if typeof(hp) == "number" and hp > 0 and hum.Health / hum.MaxHealth < hp and now >= (st.PotionAt.Hp or 0) then
		drink(player, st, "Hp", hum, now)
	end
	local en = player:GetAttribute("AF_EnPct")
	if typeof(en) == "number" and en > 0 then
		local cur, mx = EnergyRegenService.GetEnergy(player)
		if mx > 0 and cur / mx < en and now >= (st.PotionAt.En or 0) then
			drink(player, st, "En", hum, now)
		end
	end
end

-- ¿hay jugadores de OTRA facción cerca? (el PvP es siempre a mano: el auto-Metin / auto-Jefe se apagan)
local BOSS_MINION_RADIUS = 75
local BOSS_ENEMY_RADIUS = 110
local BOSS_HIT_WINDOW = 6
local function enemyPlayerNear(player: Player, origin: Vector3): boolean
	local mine = player:GetAttribute("Faction")
	for _, pl in ipairs(Players:GetPlayers()) do
		local other = pl:GetAttribute("Faction")
		if pl ~= player and other ~= nil and other ~= mine then
			local c = pl.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if h and h.Health > 0 and r and r:IsA("BasePart") and flatDist(r.Position, origin) <= BOSS_ENEMY_RADIUS then
				return true
			end
		end
	end
	return false
end

-- AUTO-METIN: primero las oleadas que salen de la piedra; si no hay, la piedra más cercana.
-- Si otra facción golpea la piedra, se apaga solo (el PvP es siempre a mano).
local METIN_SCAN = 700
local METIN_WAVE_NEAR = 90
local FOREIGN_HIT_WINDOW = 8
local function metinTargets(player: Player, origin: Vector3, now: number): ({ Mob }, string?)
	local mine = tostring(player:GetAttribute("Faction"))
	if enemyPlayerNear(player, origin) then
		return {}, "Auto-Metin apagado: hay jugadores de otra facción cerca (el PvP es a mano)"
	end
	local stones: { Mob } = {}
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and inst:GetAttribute("Metin") == true then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				local d = flatDist(root.Position, origin)
				if d <= METIN_SCAN then
					for attr, v in pairs(inst:GetAttributes()) do
						if string.sub(attr, 1, 4) == "Hit_" and attr ~= "Hit_" .. mine and attr ~= "Hit_nil" and typeof(v) == "number" and now - v < FOREIGN_HIT_WINDOW and d < 200 then
							return {}, "Auto-Metin apagado: otra facción atacó la piedra (el PvP es a mano)"
						end
					end
					table.insert(stones, { Model = inst, Root = root, Dist = d, Boss = false })
				end
			end
		end
	end
	table.sort(stones, function(a, b)
		return a.Dist < b.Dist
	end)
	local waves: { Mob } = {}
	for _, inst in ipairs(CollectionService:GetTagged("Mob")) do
		if inst:IsA("Model") and inst:GetAttribute("MetinWave") == true then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				local d = flatDist(root.Position, origin)
				if d <= METIN_WAVE_NEAR then
					table.insert(waves, { Model = inst, Root = root, Dist = d, Boss = inst:GetAttribute("Boss") == true })
				end
			end
		end
	end
	if #waves > 0 then
		return waves, nil
	end
	if stones[1] then
		return { stones[1] }, nil
	end
	return {}, nil
end

-- AUTO-JEFE: ataca solo al jefe mundial; si salen súbditos, se enfoca en ellos y luego vuelve al jefe.
-- Se apaga solo si hay jugadores de otra facción cerca o si uno te ataca (el PvP es siempre a mano) o si el jefe ya no está.
local function bossTargets(player: Player, origin: Vector3, now: number): ({ Mob }, string?)
	local char = player.Character
	if char then
		local byPlayer, at = char:GetAttribute("LastHitByPlayer"), char:GetAttribute("LastHitAt")
		if byPlayer == true and typeof(at) == "number" and now - at < BOSS_HIT_WINDOW then
			return {}, "Auto-Jefe apagado: te atacó un jugador (el PvP es a mano)"
		end
	end
	if enemyPlayerNear(player, origin) then
		return {}, "Auto-Jefe apagado: hay enemigos cerca (el PvP es a mano)"
	end
	local boss: Mob? = nil
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and inst:GetAttribute("WorldBoss") == true then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				local hr = inst:GetAttribute("HitRadius")
				boss = { Model = inst, Root = root, Dist = math.max(0, flatDist(root.Position, origin) - (if typeof(hr) == "number" then hr else 0)), Boss = true }
				break
			end
		end
	end
	if not boss then
		return {}, "Auto-Jefe apagado: no hay jefe"
	end
	-- súbditos del jefe: cualquier monstruo vivo cerca (antes solo contaba el marcado como oleada de Metin y casi nunca atacaba a los súbditos)
	local minions = liveMobs(origin, BOSS_MINION_RADIUS, nil, nil)
	if #minions > 0 then
		return minions, nil
	end
	return { boss }, nil
end

local function step(player: Player, st: State, now: number)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (char and hum and root and root:IsA("BasePart")) then
		return
	end
	if hum.Health <= 0 then
		disable(player, "Auto-farm apagado: caíste")
		return
	end
	if ArenaService.IsInArena(root.Position) and st.Mode ~= "Metin" and st.Mode ~= "Jefe" then
		disable(player, "Auto-farm apagado: en la Arena todo es manual")
		return
	end
	if inSafeZone(root.Position) then
		disable(player, "Auto-farm apagado: zona segura")
		return
	end
	usePotions(player, st, hum, now) -- (nunca se apaga por vida/energía baja: toma pociones y se cura sola)
	if DamageService.IsStunned(char) then
		status(player, "Aturdido")
		return
	end

	local mode = st.Mode
	local autoRange = AutoAttack.RangeFor(player)
	local scanR = if mode == "Metin" or mode == "Jefe" then 900 else SCAN_SEMI
	local healerRole = PlayerClass.Get(player).Role == "Curador"
	local anyHurt, hurtRoot = alliesHurt(player, root)
	local mobs: { Mob }
	if mode == "Metin" then
		local why: string?
		mobs, why = metinTargets(player, root.Position, now)
		if why then
			disable(player, why)
			return
		end
	elseif mode == "Jefe" then
		local why: string?
		mobs, why = bossTargets(player, root.Position, now)
		if why then
			disable(player, why)
			return
		end
	else
		mobs = liveMobs(root.Position, scanR, nil, st.Ignore)
	end

	local current = AutoAttack.GetTarget(player)
	local target = pickTarget(mobs, current, scanR)
	if target ~= current then
		AutoAttack.SetTarget(player, target)
	end

	-- Movimiento (Metin y Jefe; en Semi mueve el jugador)
	if mode == "Metin" or mode == "Jefe" then
		local strip = st.Strip
		local goal: Vector3? = nil
		local chaseModel: Model? = nil
		local chaseStop = 0
		if strip and not inStrip(strip, root.Position, -25) then
			goal = clampToStrip(strip, root.Position) -- se salió de su franja: vuelve adentro
			target = nil
			AutoAttack.SetTarget(player, nil)
		elseif target then
			local tr = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if tr then
				local d = flatDist(tr.Position, root.Position)
				-- cuerpo a cuerpo (alcance corto): se pega al enemigo; a distancia: se queda a ~60% de su alcance
				-- cuerpo a cuerpo: SIEMPRE hasta el contacto (como el ataque básico), sin importar el alcance de sus poderes;
				-- a distancia: se queda a ~60% de su alcance
				local stand = if autoRange <= 14 then 2.8 else math.clamp(autoRange * 0.6, 4.5, 24)
				if st.Close then
					stand = 2.2
				end
				local hr = target:GetAttribute("HitRadius") -- jefe gigante: se queda junto a su superficie, no en su centro
				if typeof(hr) == "number" then
					stand += hr
				end
				chaseModel, chaseStop = target, stand
				if d > stand + 1.5 then
					local dir = Vector3.new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z).Unit
					goal = tr.Position - dir * stand
					if strip then
						goal = clampChase(strip, goal)
					end
				end
				-- ENCADENAR: los de distancia, con el objetivo casi muerto, ya avanzan hacia el siguiente grupo sin esperar a rematar
				if goal == nil and autoRange > 14 then
					local th0 = target:FindFirstChildOfClass("Humanoid")
					if th0 and th0.MaxHealth > 0 and th0.Health / th0.MaxHealth < 0.3 then
						local nxt: Mob? = nil
						local nd = math.huge
						for _, m in ipairs(mobs) do
							if m.Model ~= target and m.Dist < nd and m.Dist <= 70 then
								nxt, nd = m, m.Dist
							end
						end
						if nxt then
							local standN = math.clamp(autoRange * 0.6, 4.5, 24)
							if nd > standN + 2 then
								local dn = Vector3.new(nxt.Root.Position.X - root.Position.X, 0, nxt.Root.Position.Z - root.Position.Z).Unit
								local g2 = nxt.Root.Position - dn * standN
								goal = if strip then clampChase(strip, g2) else g2
								chaseModel = nil
							end
						end
					end
				end
			end
			st.Patrol = nil
		elseif strip then
			-- sin mobs a la vista: patrulla la franja (al acercarse a zonas nuevas los grupos despiertan)
			if not st.Patrol or now - st.PatrolAt > 20 or flatDist(root.Position, st.Patrol) < 8 then
				st.Patrol = randomPatrolPoint(strip, root.Position)
				st.PatrolAt = now
				st.Path = nil
			end
			goal = st.Patrol
		end
		-- Vigilante: si el objetivo no pierde vida (fuera de alcance real, atascado, inalcanzable) se acerca más y, si sigue igual, lo descarta un rato
		if target then
			local th = target:FindFirstChildOfClass("Humanoid")
			if th then
				if st.TgtModel ~= target or th.Health < st.TgtHp - 0.5 then
					st.TgtModel, st.TgtHp, st.TgtSince, st.Close = target, th.Health, now, false
				else
					st.TgtHp = math.max(st.TgtHp, th.Health)
					local stuckFor = now - st.TgtSince
					if stuckFor > 2.5 then
						st.Close = true
					end
					if stuckFor > 5 then
						st.Ignore[target] = now + 12
						st.TgtModel, st.Close = nil, false
						AutoAttack.SetTarget(player, nil)
						target = nil
						st.Patrol = nil
					end
				end
			end
		else
			st.TgtModel, st.Close = nil, false
		end
		-- Curador: si hay un aliado herido fuera del alcance de la cura, va hacia él (la cura es prioridad)
		if healerRole and hurtRoot and flatDist(hurtRoot.Position, root.Position) > 14 then
			local dir = Vector3.new(hurtRoot.Position.X - root.Position.X, 0, hurtRoot.Position.Z - root.Position.Z).Unit
			goal = hurtRoot.Position - dir * 7
			chaseModel = nil
			if strip then
				goal = clampToStrip(strip, goal)
			end
			st.Patrol = nil
		end
		-- Antibloqueo: con una meta y sin avanzar 3 s (atascado, ruta imposible, objetivo inalcanzable) cambia de meta
		if goal then
			if (root.Position - st.LastPos).Magnitude > 2.5 then
				st.LastPos, st.LastPosAt = root.Position, now
			elseif now - st.LastPosAt > 2.5 then
				st.LastPosAt = now
				st.Path, st.PathAt, st.Patrol = nil, 0, nil
				if target then
					st.Ignore[target] = now + 10
					AutoAttack.SetTarget(player, nil)
					target = nil
				end
				if strip then
					goal = randomPatrolPoint(strip, root.Position)
					st.Patrol, st.PatrolAt = goal, now
				end
			end
		else
			st.LastPos, st.LastPosAt = root.Position, now
		end
		-- Esquiva (zonas rojas de poderes en área / en línea): tiene prioridad sobre ir al objetivo
		local dg = dodgeGoal(root.Position, strip)
		if dg then
			goal = dg
			chaseModel = nil
			st.DodgeUntil = now + 0.7
			status(player, "Esquivando")
		end
		if now >= st.DodgeUntil or dg then
			-- con la meta cumplida (objetivo al alcance) se sigue mandando la persecución: el cliente ajusta el contacto solo
			dispatchMove(player, st, root, goal, now, chaseModel, chaseStop)
		end
	end

	if not target then
		status(player, if mode == "Metin" then "Esperando un Metin..." elseif mode == "Jefe" then "Buscando al jefe..." else "Esperando mobs")
	end

	-- Poderes
	local cur, max = EnergyRegenService.GetEnergy(player)
	local tMob: Mob? = nil
	local boss = false
	local near30 = 0
	for _, m in ipairs(mobs) do
		if m.Model == target then
			tMob = m
		end
		if m.Boss and m.Dist <= 50 then
			boss = true
		end
		if m.Dist <= 30 then
			near30 += 1
		end
	end
	if target then
		status(player, (if tMob and tMob.Boss then "Atacando élite" else "Atacando") .. (if tMob then string.format(" · %dm", math.floor(tMob.Dist + 0.5)) else ""))
	end
	if now - st.LastCast < MIN_CAST_GAP or DamageService.IsSilenced(char) then
		return
	end
	local rm = rangeMultOf(char)
	local ctx: Ctx = {
		Mode = mode, HpPct = hum.Health / hum.MaxHealth, KiFrac = if max > 0 then cur / max else 0, Root = root, Mobs = mobs,
		Target = tMob, TargetBoss = tMob ~= nil and tMob.Boss, Boss = boss, Engaged = near30 > 0, AllyHurt = anyHurt, AllyDist = if hurtRoot then flatDist(hurtRoot.Position, root.Position) else math.huge, Near30 = near30,
	}
	for _, sk in ipairs(skillsOf(player, if typeof(rm) == "number" then rm else 1)) do
		local ok, hint = false, nil :: Model?
		if target or sk.Cat == "heal" or sk.Cat == "heal7" then -- sin enemigos a la vista solo se cura (nada de gastar poderes al aire)
			ok, hint = decide(sk, ctx)
		end
		if ok then
			st.LastCast = now
			if sk.Sys == "A" then
				AbilityService.Cast(player, sk.Slot, hint)
			else
				CombatService.Cast(player, tostring(sk.Slot), hint)
			end
			return
		end
	end
end

SetRemote.OnServerEvent:Connect(function(player: Player, action: any, on: any, mode: any, extra: any)
	local st = states[player]
	if not st then
		return
	end
	if action == "Potion" then
		-- ("Potion", "Hp"|"En", umbral 0-0.95 (0 = apagado), idObjeto o "" = detectar sola)
		if on ~= "Hp" and on ~= "En" then
			return
		end
		if typeof(mode) == "number" then
			player:SetAttribute(if on == "Hp" then "AF_HpPct" else "AF_EnPct", math.clamp(math.floor(mode * 100 + 0.5) / 100, 0, 0.95))
		end
		if typeof(extra) == "string" then
			local field = if on == "Hp" then "HealPct" else "EnergyPct"
			local it = ItemCatalog.Items[extra]
			if extra == "" or (it and it.Use and (it.Use :: any)[field] and AlchemyCatalog.PotionAllowed(extra, player:GetAttribute("Pass_Belt") == true)) then
				player:SetAttribute(if on == "Hp" then "AF_HpItem" else "AF_EnItem", extra)
			end
		end
		return
	end
	if action == "AllyHeal" then
		player:SetAttribute("AF_AllyHeal", on == true)
		return
	end
	if action == "Stuck" then
		-- el cliente se atascó: fuerza ruta nueva y otra meta de patrulla
		st.Path, st.Patrol, st.PathAt = nil, nil, 0
		return
	end
	if action ~= "Set" then
		return
	end
	if typeof(mode) == "string" and MODES[mode] then
		st.Mode = mode
		player:SetAttribute("AutoFarmMode", mode)
	end
	if on == true then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		if ArenaService.IsInArena(root.Position) and st.Mode ~= "Metin" and st.Mode ~= "Jefe" then
			NotifyRemote:FireClient(player, "En la Arena solo funcionan los modos Metin y Jefe (el PvP es a mano)")
			return
		end
		if inSafeZone(root.Position) then
			NotifyRemote:FireClient(player, "El Auto-farm no funciona en zona segura (ciudad)")
			return
		end
		st.Origin = root.Position
		st.Strip = nil
		st.Patrol, st.Path = nil, nil
		if st.Mode == "Metin" then
			NotifyRemote:FireClient(player, "Auto-Metin: ataca la piedra y sus oleadas")
		elseif st.Mode == "Jefe" then
			if Workspace:GetAttribute("BossActive") ~= true then
				NotifyRemote:FireClient(player, "No hay jefe mundial en este momento")
				return
			end
			NotifyRemote:FireClient(player, "Auto-Jefe: ataca al jefe y a sus súbditos. Se apaga si hay enemigos o te atacan")
		end
		st.Enabled = true
		st.LastCast = 0
		player:SetAttribute("AutoFarm", true)
	elseif on == false then
		disable(player, nil)
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < TICK then
		return
	end
	acc = 0
	local now = os.clock()
	for player, st in pairs(states) do
		if st.Enabled and player.Parent then
			local ok, err = pcall(step, player, st, now)
			if not ok then
				warn("[AutoFarmService] " .. tostring(err))
			end
		end
	end
end)

-- Esquiva rápida (cada 0.1 s): reacciona a las zonas rojas aunque el ciclo principal (0.3 s) aún no haya corrido
local dodgeAcc = 0
RunService.Heartbeat:Connect(function(dt)
	dodgeAcc += dt
	if dodgeAcc < DODGE_TICK then
		return
	end
	dodgeAcc = 0
	local now = os.clock()
	for player, st in pairs(states) do
		if st.Enabled and st.Mode ~= "Semi" and player.Parent then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local g = dodgeGoal(root.Position, st.Strip)
				if g then
					st.DodgeUntil = now + 0.7
					MoveRemote:FireClient(player, { g })
				end
			end
		end
	end
end)

-- AUTO-CURAR ALIADOS independiente: funciona aunque el Auto-farm esté apagado (también en la Arena / zona PvP).
-- Si un aliado de tu facción (o de tu grupo) baja del umbral y está dentro del área de tu poder de curación, lo lanza solo.
local healAcc = 0
RunService.Heartbeat:Connect(function(dt)
	healAcc += dt
	if healAcc < 0.5 then
		return
	end
	healAcc = 0
	local now = os.clock()
	for player, st in pairs(states) do
		if not st.Enabled and player.Parent and player:GetAttribute("AF_AllyHeal") ~= false and now - st.LastCast >= MIN_CAST_GAP then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if char and hum and hum.Health > 0 and root and root:IsA("BasePart") and not DamageService.IsSilenced(char) and not DamageService.IsStunned(char) then
				local anyHurt, hurtRoot = alliesHurt(player, root)
				if anyHurt and hurtRoot then
					local dist = flatDist(hurtRoot.Position, root.Position)
					local rm = rangeMultOf(char)
					for _, sk in ipairs(skillsOf(player, if typeof(rm) == "number" then rm else 1)) do
						if sk.Cat == "heal" and sk.Radius > 0 and dist <= sk.Radius + 1 then
							st.LastCast = now
							if sk.Sys == "A" then
								AbilityService.Cast(player, sk.Slot, nil)
							else
								CombatService.Cast(player, tostring(sk.Slot), nil)
							end
							break
						end
					end
				end
			end
		end
	end
end)

local function register(player: Player)
	states[player] = { Enabled = false, Mode = "Semi", Origin = Vector3.zero, Next = 0, LastCast = 0, Strip = nil, Patrol = nil, PatrolAt = 0, Path = nil, PathGoal = nil, PathAt = 0, PathBusy = false, Close = false, DodgeUntil = 0, Ignore = {}, TgtModel = nil, TgtHp = 0, TgtSince = 0, PotionAt = {}, LastPos = Vector3.zero, LastPosAt = 0 }
	player:SetAttribute("AutoFarm", false)
	player:SetAttribute("AutoFarmMode", "Semi")
	player:SetAttribute("AutoFarmStatus", "")
	player:SetAttribute("AF_HpPct", 0.5) -- poción de vida al bajar de 50% (0 = apagado)
	player:SetAttribute("AF_EnPct", 0.3) -- poción de energía al bajar de 30%
	player:SetAttribute("AF_AllyHeal", true) -- cura aliados / grupo automáticamente
	player:SetAttribute("AF_AllyPct", 0.7)
	player:SetAttribute("AF_HpItem", "")
	player:SetAttribute("AF_EnItem", "")
	-- si muere, cambia de clase o reaparece, se apaga
	player.CharacterAdded:Connect(function()
		if states[player] and states[player].Enabled then
			disable(player, nil)
		end
	end)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		if states[player] and states[player].Enabled then
			disable(player, nil)
		end
	end)
end

Players.PlayerAdded:Connect(register)
for _, p in ipairs(Players:GetPlayers()) do
	register(p)
end
Players.PlayerRemoving:Connect(function(p)
	states[p] = nil
end)

print("[AutoFarmService] Listo: modos Semi / Metin / Jefe.")
return {}
