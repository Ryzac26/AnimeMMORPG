--!strict
--[[
    AbilityService (ModuleScript) -> ServerScriptService.Services.AbilityService
    HABILIDADES 3 (utilidad) y 4 (definitiva) de los 18 personajes. Los datos viven en ReplicatedStorage.Modules.AbilityCatalog;
    aquí solo está la ejecución, un "manejador" por tipo de efecto (Kind).
      - Remote UseAbility(slot 3|4, objetivoMarcado)  cliente -> servidor (el servidor valida TODO: recarga, ki, rango, estado)
      - Remote AbilityCooldown(slot, segundos)        servidor -> cliente (0 = recarga reiniciada)
      - En la ARENA (ZonePvP) se usan CdPvp y los cambios "V" del catálogo (PvP más flojo y con más recarga).
      - Todo daño/cura/control pasa por DamageService; los efectos (buffs, marcas, provocación...) son ATRIBUTOS con caducidad
        que DamageService, MobBrain y CombatService ya leen:
          OutDmg, OutDebuff, InDmg, Lifesteal, Reflect, BurnFrac, RangeMult, SpeedMult, MarkedBy/MarkMult,
          GuardBy/GuardPct, TauntBy/TauntUntil, BlindUntil, SilencedUntil, ShieldPoints.
    Simplificaciones: clones de Naruto = copias visuales que golpean una vez; el revivir de Bulma depende de que el cuerpo
    siga ahí (el aliado cae y reaparece en ~5 s); los mobs sufren "silencio" como aturdimiento.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Catalog = require(ReplicatedStorage.Modules.AbilityCatalog)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local DamageService = require(Services.DamageService)
local ArenaService = require(Services.ArenaService)
local EnergyRegenService = require(Services.EnergyRegenService)
local PassiveService = require(Services.PassiveService)
local AttackAnimator = require(Services.AttackAnimator)
local AutoAttack = require(Services.AutoAttackService)

local DEBUG = false
local CooldownRemote = Net.Get("AbilityCooldown")
local UseRemote = Net.Get("UseAbility")
local NotifyRemote = Net.Get("Notify")
local FloatingRemote = Net.Get("Floating")

local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 200, 60),
	Shinobi = Color3.fromRGB(130, 220, 120),
	Pirate = Color3.fromRGB(80, 170, 255),
	Shinigami = Color3.fromRGB(165, 140, 255),
}

type Ctx = {
	Player: Player,
	Char: Model,
	Root: BasePart,
	Hum: Humanoid,
	Class: any,
	Ab: Catalog.Ability,
	P: { [string]: any },
	Dur: number,
	Pvp: boolean,
	Hint: any,
	Slot: number,
	Color: Color3,
	SetCooldown: (seconds: number) -> (),
}

local AbilityService = {}
local cooldowns: { [Player]: { [number]: number } } = {}
local reviveLock: { [Player]: number } = {}
local pendingRevive: { [Player]: { CF: CFrame, Hp: number, Protect: number } } = {}
local tokenCounter = 0

local function nextToken(): number
	tokenCounter += 1
	return tokenCounter
end

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------
local function notify(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

local function liveParts(m: Model?): (Humanoid?, BasePart?)
	if not m or not m.Parent then
		return nil, nil
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	local r = m:FindFirstChild("HumanoidRootPart")
	if h and h.Health > 0 and r and r:IsA("BasePart") then
		return h, r
	end
	return nil, nil
end

-- jefes gigantes: el alcance se mide desde su superficie, no desde su centro (atributo HitRadius)
local function hitR(m: Instance?): number
	local v = if m then m:GetAttribute("HitRadius") else nil
	return if typeof(v) == "number" then v else 0
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function flatLook(root: BasePart): Vector3
	local l = root.CFrame.LookVector
	local f = Vector3.new(l.X, 0, l.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- Atributo con caducidad (si se vuelve a poner antes de que caduque, gana el último)
local function timedAttr(m: Instance, name: string, value: any, duration: number)
	local tk = nextToken()
	m:SetAttribute(name, value)
	m:SetAttribute(name .. "_tk", tk)
	task.delay(duration, function()
		if m.Parent and m:GetAttribute(name .. "_tk") == tk then
			m:SetAttribute(name, nil)
		end
	end)
end

local function applySpeed(m: Model, mult: number, duration: number)
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if m:GetAttribute("BaseWalkSpeed") == nil then
		m:SetAttribute("BaseWalkSpeed", hum.WalkSpeed)
	end
	local base = m:GetAttribute("BaseWalkSpeed") :: number
	timedAttr(m, "SpeedMult", mult, duration)
	if not DamageService.IsStunned(m) then
		hum.WalkSpeed = base * mult
	end
	local tk = m:GetAttribute("SpeedMult_tk")
	task.delay(duration, function()
		if hum.Parent and m:GetAttribute("SpeedMult_tk") == tk and not DamageService.IsStunned(m) then
			hum.WalkSpeed = base
		end
	end)
end

local function clearSpeed(m: Model)
	local hum = m:FindFirstChildOfClass("Humanoid")
	local base = m:GetAttribute("BaseWalkSpeed")
	m:SetAttribute("SpeedMult", nil)
	m:SetAttribute("SpeedMult_tk", nil)
	if hum and typeof(base) == "number" and not DamageService.IsStunned(m) then
		hum.WalkSpeed = base
	end
end

local function shieldPct(target: Model, pct: number, duration: number): number
	local hum = target:FindFirstChildOfClass("Humanoid")
	if not hum then
		return 0
	end
	local pts = math.floor(hum.MaxHealth * pct)
	local tk = os.clock()
	target:SetAttribute("ShieldPoints", pts)
	target:SetAttribute("ShieldToken", tk)
	task.delay(duration, function()
		if target.Parent and target:GetAttribute("ShieldToken") == tk then
			target:SetAttribute("ShieldPoints", 0)
		end
	end)
	return pts
end

local function floatText(pos: Vector3, text: string, color: Color3)
	FloatingRemote:FireAllClients(pos + Vector3.new(0, 6, 0), text, color)
end

local function makeFx(shape: Enum.PartType, cf: CFrame, size: Vector3, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.25
	p.Size = size
	p.CFrame = cf
	p.Parent = Workspace
	return p
end

local function fade(p: Part, goalSize: Vector3, life: number)
	TweenService:Create(p, TweenInfo.new(life), { Size = goalSize, Transparency = 1 }):Play()
	Debris:AddItem(p, life + 0.1)
end

local function ring(pos: Vector3, radius: number, color: Color3, life: number)
	local p = makeFx(Enum.PartType.Cylinder, CFrame.new(pos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.5, 2, 2), color)
	fade(p, Vector3.new(0.5, radius * 2, radius * 2), life)
end

local function burst(pos: Vector3, radius: number, color: Color3, life: number)
	local p = makeFx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(3, 3, 3), color)
	fade(p, Vector3.new(radius * 2, radius * 2, radius * 2), life)
end

local function beam(from: Vector3, dir: Vector3, length: number, width: number, color: Color3, life: number)
	local mid = from + dir * (length / 2)
	local p = makeFx(Enum.PartType.Block, CFrame.lookAt(mid, mid + dir), Vector3.new(width, width, length), color, 0.15)
	fade(p, Vector3.new(width * 0.2, width * 0.2, length), life)
end

local function highlight(m: Model, color: Color3, duration: number)
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = 0.6
	hl.OutlineColor = color
	hl.Parent = m
	Debris:AddItem(hl, duration)
end

local function bubble(m: Model, color: Color3, duration: number)
	local root = m:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(9, 9, 9)
	b.Material = Enum.Material.ForceField
	b.Color = color
	b.Transparency = 0.3
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Massless = true
	b.CastShadow = false
	b.CFrame = root.CFrame
	b.Parent = m
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = b
	w.Parent = b
	Debris:AddItem(b, duration)
end

---------------------------------------------------------------------
-- OBJETIVOS
---------------------------------------------------------------------
local function candidates(): { Model }
	local seen: { [Model]: boolean } = {}
	local list: { Model } = {}
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and not seen[inst] then
			seen[inst] = true
			table.insert(list, inst)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		if c and not seen[c] then
			seen[c] = true
			table.insert(list, c)
		end
	end
	return list
end

local function isHostile(c: Ctx, m: Model): boolean
	if m == c.Char then
		return false
	end
	local pl = Players:GetPlayerFromCharacter(m)
	if pl then
		return ArenaService.PvpAllowed(c.Player, pl)
	end
	return CollectionService:HasTag(m, "Targetable")
end

local function isAlly(c: Ctx, m: Model): boolean
	local pl = Players:GetPlayerFromCharacter(m)
	return pl ~= nil and pl ~= c.Player and pl:GetAttribute("Faction") == c.Player:GetAttribute("Faction")
end

local function hostilesIn(c: Ctx, center: Vector3, radius: number): { Model }
	local out: { Model } = {}
	for _, m in ipairs(candidates()) do
		local _, r = liveParts(m)
		if r and isHostile(c, m) and flatDist(r.Position, center) - hitR(m) <= radius + 2 and math.abs(r.Position.Y - center.Y) <= 30 then
			table.insert(out, m)
		end
	end
	return out
end

local function alliesIn(c: Ctx, center: Vector3, radius: number, includeSelf: boolean): { Model }
	local out: { Model } = {}
	if includeSelf then
		table.insert(out, c.Char)
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local m = pl.Character
		local _, r = liveParts(m)
		if m and r and isAlly(c, m) and (r.Position - center).Magnitude <= radius + 2 then
			table.insert(out, m)
		end
	end
	return out
end

local function hostilesInLine(c: Ctx, origin: Vector3, dir: Vector3, length: number, width: number): { Model }
	local out: { Model } = {}
	for _, m in ipairs(hostilesIn(c, origin, length + width)) do
		local _, r = liveParts(m)
		if r then
			local rel = Vector3.new(r.Position.X - origin.X, 0, r.Position.Z - origin.Z)
			local along = rel:Dot(dir)
			local side = (rel - dir * along).Magnitude
			if along >= -2 and along <= length + 2 and side <= width / 2 + 2 then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- mode: "hostile" | "ally" | "any". Usa el objetivo marcado si es válido; si no, el más cercano al frente.
local function resolveTarget(c: Ctx, range: number, mode: string): Model?
	local origin = c.Root.Position
	local look = flatLook(c.Root)
	local function valid(m: Model): boolean
		if m == c.Char then
			return false
		end
		if mode == "hostile" then
			return isHostile(c, m)
		elseif mode == "ally" then
			return isAlly(c, m)
		end
		return isHostile(c, m) or isAlly(c, m)
	end
	local hint = c.Hint
	if typeof(hint) == "Instance" and hint:IsA("Model") then
		local _, r = liveParts(hint)
		if r and valid(hint) and flatDist(r.Position, origin) - hitR(hint) <= range + 3 and math.abs(r.Position.Y - origin.Y) <= 30 then
			return hint
		end
	end
	local best: Model? = nil
	local bestD = math.huge
	for _, m in ipairs(candidates()) do
		local _, r = liveParts(m)
		if r and valid(m) then
			local d = math.max(0, flatDist(r.Position, origin) - hitR(m))
			if d <= range + 3 and math.abs(r.Position.Y - origin.Y) <= 30 and d < bestD then
				local flat = Vector3.new(r.Position.X - origin.X, 0, r.Position.Z - origin.Z)
				if d < 0.5 or flat.Unit:Dot(look) >= 0.3 then
					best = m
					bestD = d
				end
			end
		end
	end
	return best
end

local function dirTowards(c: Ctx, target: Model?): Vector3
	local _, r = liveParts(target)
	if r then
		local d = Vector3.new(r.Position.X - c.Root.Position.X, 0, r.Position.Z - c.Root.Position.Z)
		if d.Magnitude > 0.05 then
			return d.Unit
		end
	end
	return flatLook(c.Root)
end

-- Centro de un efecto en área: el objetivo (marcado o más cercano) o un punto al frente
local function areaCenter(c: Ctx): Vector3
	local t = resolveTarget(c, c.Ab.Range, "hostile")
	local _, r = liveParts(t)
	if r then
		return r.Position
	end
	return c.Root.Position + flatLook(c.Root) * (c.Ab.Range * 0.6)
end

local function refDamage(c: Ctx, ref: any): number
	local skill = if ref == 1 then c.Class.PrimarySkill else c.Class.SecondarySkill
	return skill.BaseValue
end

local function moveRoot(root: BasePart, pos: Vector3)
	root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
end

-- carrera corta (no atraviesa paredes: lanza un rayo)
local function clampDash(c: Ctx, dir: Vector3, dist: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c.Char }
	local hit = Workspace:Raycast(c.Root.Position, dir * dist, params)
	if hit then
		return math.max(0, hit.Distance - 3)
	end
	return dist
end

local function dashAlong(c: Ctx, dir: Vector3, dist: number, time: number)
	local root = c.Root
	local start = root.Position
	local goal = start + dir * dist
	local rot = CFrame.lookAt(Vector3.zero, dir)
	local t = 0
	while t < time do
		t += RunService.Heartbeat:Wait()
		if not root.Parent then
			return
		end
		local a = math.min(1, t / time)
		root.CFrame = CFrame.new(start:Lerp(goal, a)) * rot.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Espera interrumpible. Devuelve false si se canceló (golpe recibido con cancelOnHit, aturdimiento/silencio o muerte)
local function channel(c: Ctx, duration: number, cancelOnHit: boolean): boolean
	local cancelled = false
	local last = c.Hum.Health
	local conn = c.Hum.HealthChanged:Connect(function(h)
		if cancelOnHit and h < last - 0.5 then
			cancelled = true
		end
		last = h
	end)
	local t = 0
	while t < duration and not cancelled do
		t += task.wait(0.05)
		if c.Hum.Health <= 0 or not c.Char.Parent or DamageService.IsStunned(c.Char) or DamageService.IsSilenced(c.Char) then
			cancelled = true
		end
	end
	conn:Disconnect()
	return not cancelled
end

---------------------------------------------------------------------
-- MANEJADORES POR TIPO (devuelven true si la habilidad se lanzó; false = sin coste ni recarga)
---------------------------------------------------------------------
local H: { [string]: (Ctx) -> boolean } = {}

-- Piccolo 3: provoca a los enemigos cercanos
H.Taunt = function(c)
	local P = c.P
	for _, m in ipairs(hostilesIn(c, c.Root.Position, c.Ab.Radius)) do
		if Players:GetPlayerFromCharacter(m) then
			if P.NoTaunt then
				timedAttr(m, "OutDebuff", P.OutDebuff or 0.8, c.Dur)
			end
		else
			timedAttr(m, "TauntBy", c.Char.Name, c.Dur)
			timedAttr(m, "TauntUntil", os.clock() + c.Dur, c.Dur)
			highlight(m, Color3.fromRGB(255, 80, 80), c.Dur)
		end
	end
	timedAttr(c.Char, "InDmg", P.InDmg or 0.7, c.Dur)
	ring(c.Root.Position, c.Ab.Radius, Color3.fromRGB(255, 90, 90), 0.6)
	floatText(c.Root.Position, "¡Provocación!", Color3.fromRGB(255, 120, 120))
	return true
end

-- Piccolo 4 / Chopper 3: escudo (% de vida máx.) al lanzador y aliados
H.ShieldGroup = function(c)
	local P = c.P
	local list = alliesIn(c, c.Root.Position, c.Ab.Radius, true)
	for i = #list, (P.Count or 3) + 1, -1 do
		table.remove(list, i)
	end
	for _, m in ipairs(list) do
		shieldPct(m, P.Pct or 0.08, c.Dur)
		bubble(m, c.Color, c.Dur)
		if P.Regen then
			local hum = m:FindFirstChildOfClass("Humanoid")
			task.spawn(function()
				for _ = 1, math.floor(c.Dur) do
					task.wait(1)
					if not hum or hum.Health <= 0 then
						return
					end
					hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * P.Regen)
				end
			end)
		end
	end
	ring(c.Root.Position, c.Ab.Radius, c.Color, 0.6)
	return true
end

-- Goku 3 / Sasuke 3 (teletransporte detrás) y Luffy 3 (se lanza a un aliado o enemigo)
H.Blink = function(c)
	local P = c.P
	local mode = P.Mode
	local target = resolveTarget(c, c.Ab.Range, if mode == "Rush" then "any" else "hostile")
	local _, tr = liveParts(target)
	if not target or not tr then
		notify(c.Player, "Sin objetivo al alcance")
		return false
	end
	local dir = dirTowards(c, target)
	local dest: Vector3
	if mode == "Teleport" then
		local behind = tr.CFrame.LookVector * -1
		behind = Vector3.new(behind.X, 0, behind.Z)
		-- detrás del objetivo (si el mob mira hacia otro lado igualmente queda pegado)
		dest = tr.Position - behind.Unit * 4
		burst(c.Root.Position, 5, c.Color, 0.3)
		c.Root.CFrame = CFrame.lookAt(dest, Vector3.new(tr.Position.X, dest.Y, tr.Position.Z))
		c.Root.AssemblyLinearVelocity = Vector3.zero
		burst(dest, 6, c.Color, 0.35)
	else
		dest = tr.Position - dir * 4
		task.spawn(function()
			dashAlong(c, dir, math.max(0, flatDist(tr.Position, c.Root.Position) - 4 - hitR(tr.Parent)), 0.18)
		end)
	end
	if isHostile(c, target) then
		task.delay(if mode == "Rush" then 0.2 else 0, function()
			local dealt = DamageService.Deal(c.Char, target, refDamage(c, P.Ref) * (P.Frac or 1), nil)
			if dealt > 0 then
				burst(tr.Position, 5, c.Color, 0.25)
			end
		end)
	end
	return true
end

-- Vegeta 3 (carrera con invulnerabilidad) / Zoro 3 (carrera que corta en línea)
H.Dash = function(c)
	local P = c.P
	local target = resolveTarget(c, c.Ab.Range + 10, "hostile")
	local dir = dirTowards(c, target)
	local dist = clampDash(c, dir, P.Dist or 20)
	if dist < 2 then
		notify(c.Player, "No hay espacio para avanzar")
		return false
	end
	local origin = c.Root.Position
	if P.ImmuneFor then
		timedAttr(c.Char, "Immune", true, P.ImmuneFor)
	end
	task.spawn(function()
		dashAlong(c, dir, dist, 0.18)
		if P.Hit then
			for _, m in ipairs(hostilesInLine(c, origin, dir, dist, 7)) do
				local dealt = DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Frac or 1), nil)
				if dealt > 0 then
					local _, r = liveParts(m)
					if r then
						burst(r.Position, 4, c.Color, 0.25)
					end
				end
			end
			beam(origin, dir, dist, 3, c.Color, 0.3)
		end
	end)
	return true
end

-- Vegeta 4: explosión alrededor; queda con poca vida
H.SelfBlast = function(c)
	local P = c.P
	burst(c.Root.Position, c.Ab.Radius * 1.2, c.Color, 0.6)
	ring(c.Root.Position, c.Ab.Radius, Color3.fromRGB(255, 255, 255), 0.5)
	for _, m in ipairs(hostilesIn(c, c.Root.Position, c.Ab.Radius)) do
		local dealt = DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Mult or 1), nil)
		if dealt > 0 and P.FragStacks and Players:GetPlayerFromCharacter(m) then
			DamageService.AddFragility(m, P.FragStacks)
		end
	end
	local limit = c.Hum.MaxHealth * (P.LeaveHpPct or 0.2)
	if c.Hum.Health > limit then
		c.Hum.Health = limit
	end
	return true
end

-- Trunks 3: tajo en línea con ralentización
H.LineSlow = function(c)
	local P = c.P
	local target = resolveTarget(c, c.Ab.Range, "hostile")
	local dir = dirTowards(c, target)
	beam(c.Root.Position, dir, c.Ab.Range, 4, c.Color, 0.35)
	for _, m in ipairs(hostilesInLine(c, c.Root.Position, dir, c.Ab.Range, 6)) do
		DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Frac or 1), { Slow = c.Dur, SlowAmount = P.Slow })
	end
	return true
end

-- Trunks 4 (carga y disparo único) / Gohan 4 (canaliza y rayo ancho)
H.Channel = function(c)
	local P = c.P
	if P.Mode == "Single" then
		local target = resolveTarget(c, c.Ab.Range, "hostile")
		if not target then
			notify(c.Player, "Sin objetivo al alcance")
			return false
		end
		local charge = makeFx(Enum.PartType.Ball, CFrame.new(c.Root.Position + flatLook(c.Root) * 3), Vector3.new(1, 1, 1), c.Color)
		fade(charge, Vector3.new(7, 7, 7), c.Dur)
		task.spawn(function()
			if not channel(c, c.Dur, true) then
				charge:Destroy()
				c.SetCooldown((if c.Pvp then c.Ab.CdPvp else c.Ab.CdPve) * 0.5)
				notify(c.Player, "Carga cancelada")
				return
			end
			local _, tr = liveParts(target)
			if tr and (tr.Position - c.Root.Position).Magnitude <= c.Ab.Range + 8 then
				local dir = dirTowards(c, target)
				beam(c.Root.Position, dir, (tr.Position - c.Root.Position).Magnitude, 4, c.Color, 0.4)
				local dealt = DamageService.Deal(c.Char, target, refDamage(c, P.Ref) * (P.Mult or 1), nil)
				if dealt > 0 then
					burst(tr.Position, 8, c.Color, 0.4)
				end
			end
		end)
		return true
	end
	-- rayo ancho (Gohan)
	applySpeed(c.Char, P.Walk or 0.4, c.Dur + 0.2)
	local charge = makeFx(Enum.PartType.Ball, CFrame.new(c.Root.Position + flatLook(c.Root) * 3), Vector3.new(1, 1, 1), c.Color)
	fade(charge, Vector3.new(9, 9, 9), c.Dur)
	task.spawn(function()
		local ok = channel(c, c.Dur, false)
		clearSpeed(c.Char)
		if not ok then
			charge:Destroy()
			return
		end
		local target = resolveTarget(c, c.Ab.Range, "hostile")
		local dir = if typeof(c.Hint) == "Instance" and target then dirTowards(c, target) else flatLook(c.Root)
		beam(c.Root.Position, dir, c.Ab.Range, c.Ab.Radius, c.Color, 0.6)
		for _, m in ipairs(hostilesInLine(c, c.Root.Position, dir, c.Ab.Range, c.Ab.Radius)) do
			DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Mult or 1), nil)
		end
	end)
	return true
end

-- Gohan 3: zona que debilita enemigos y acelera aliados
H.Aura = function(c)
	local P = c.P
	local zone = makeFx(Enum.PartType.Cylinder, CFrame.new(c.Root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.4, c.Ab.Radius * 2, c.Ab.Radius * 2), c.Color, 0.7)
	task.spawn(function()
		local t = 0
		while t < c.Dur and c.Hum.Health > 0 and c.Root.Parent do
			zone.CFrame = CFrame.new(c.Root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90))
			for _, m in ipairs(hostilesIn(c, c.Root.Position, c.Ab.Radius)) do
				timedAttr(m, "OutDebuff", P.EnemyOut or 0.85, 0.7)
			end
			if P.AllySpeed then
				for _, m in ipairs(alliesIn(c, c.Root.Position, c.Ab.Radius, true)) do
					applySpeed(m, P.AllySpeed, 0.7)
				end
			end
			task.wait(0.5)
			t += 0.5
		end
		zone:Destroy()
	end)
	return true
end

-- Cura instantánea. Bulma 3 / Sakura 3: los N aliados más heridos. Chopper 4 ("Area"): todos los del área.
H.HealGroup = function(c)
	local P = c.P
	local list: { Model }
	if P.Mode == "Area" then
		list = alliesIn(c, c.Root.Position, c.Ab.Radius, true)
	else
		list = alliesIn(c, c.Root.Position, c.Ab.Range, true)
		table.sort(list, function(a, b)
			local ha, hb = a:FindFirstChildOfClass("Humanoid"), b:FindFirstChildOfClass("Humanoid")
			return (ha and ha.Health / ha.MaxHealth or 1) < (hb and hb.Health / hb.MaxHealth or 1)
		end)
		for i = #list, (P.Count or 3) + 1, -1 do
			table.remove(list, i)
		end
	end
	local amount = refDamage(c, P.Ref) * (P.Frac or 1)
	for _, m in ipairs(list) do
		local got = DamageService.Heal(c.Char, m, if m == c.Char then amount * 0.5 else amount)
		if P.Cleanse then
			DamageService.Cleanse(m)
		end
		if P.Speed then
			applySpeed(m, P.Speed, c.Dur)
		end
		local _, r = liveParts(m)
		if r then
			floatText(r.Position, "+" .. got, Color3.fromRGB(90, 235, 130))
			burst(r.Position, 5, Color3.fromRGB(90, 235, 130), 0.4)
		end
	end
	ring(c.Root.Position, if P.Mode == "Area" then c.Ab.Radius else 8, Color3.fromRGB(90, 235, 130), 0.5)
	return true
end

-- Sakura 4: cura repartida en el tiempo a varios aliados
H.HealOverTime = function(c)
	local P = c.P
	local list = alliesIn(c, c.Root.Position, c.Ab.Range, true)
	table.sort(list, function(a, b)
		local ha, hb = a:FindFirstChildOfClass("Humanoid"), b:FindFirstChildOfClass("Humanoid")
		return (ha and ha.Health / ha.MaxHealth or 1) < (hb and hb.Health / hb.MaxHealth or 1)
	end)
	for i = #list, (P.Count or 5) + 1, -1 do
		table.remove(list, i)
	end
	local ticks = math.max(1, math.floor(c.Dur))
	local total = refDamage(c, P.Ref) * (P.Total or 1)
	for _, m in ipairs(list) do
		local per = total / ticks * (if m == c.Char then 0.5 else 1)
		burst(m:GetPivot().Position, 6, Color3.fromRGB(200, 255, 220), 0.5)
		task.spawn(function()
			for _ = 1, ticks do
				if not liveParts(m) then
					return
				end
				DamageService.Heal(c.Char, m, per)
				local _, r = liveParts(m)
				if r then
					ring(r.Position, 4, Color3.fromRGB(150, 255, 190), 0.4)
				end
				task.wait(1)
			end
		end)
	end
	return true
end

-- Bulma 4: revive a un aliado caído
H.Revive = function(c)
	local P = c.P
	local best: Player? = nil
	local bestD = c.Ab.Range + 3
	for _, pl in ipairs(Players:GetPlayers()) do
		local m = pl.Character
		local h = m and m:FindFirstChildOfClass("Humanoid")
		local r = m and m:FindFirstChild("HumanoidRootPart")
		if pl ~= c.Player and h and h.Health <= 0 and r and r:IsA("BasePart") and pl:GetAttribute("Faction") == c.Player:GetAttribute("Faction") then
			local d = (r.Position - c.Root.Position).Magnitude
			if d <= bestD then
				best = pl
				bestD = d
			end
		end
	end
	if not best then
		notify(c.Player, "No hay aliados caídos cerca")
		return false
	end
	local now = os.clock()
	if (reviveLock[best] or 0) > now then
		notify(c.Player, best.Name .. " ya fue revivido hace poco")
		return false
	end
	reviveLock[best] = now + (P.Lockout or 60)
	local body = (best.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
	pendingRevive[best] = { CF = body.CFrame + Vector3.new(0, 2, 0), Hp = P.Hp or 0.3, Protect = P.Protect or 3 }
	burst(body.Position, 9, Color3.fromRGB(255, 190, 60), 0.7)
	beam(body.Position, Vector3.new(0, 1, 0), 40, 5, Color3.fromRGB(255, 200, 80), 0.8)
	best:LoadCharacter()
	notify(best, c.Player.Name .. " te revivió")
	return true
end

-- Gaara 4 (muro de arena) / Jinbe 3 (muro de agua): bloquean proyectiles de mobs
H.Wall = function(c)
	local P = c.P
	local target = resolveTarget(c, c.Ab.Range + 10, "hostile")
	local dir = dirTowards(c, target)
	local isWater = P.Kind2 == "Water"
	local height = if isWater then 12 else 14
	local width = c.Ab.Radius * 2
	local pos = c.Root.Position + dir * c.Ab.Range - Vector3.new(0, 3 - height / 2, 0)
	local wall = Instance.new("Part")
	wall.Name = if isWater then "ParedDeAgua" else "MuroDeArena"
	wall.Anchored = true
	wall.CanCollide = true
	wall.CastShadow = false
	wall.Size = Vector3.new(width, height, 3)
	wall.CFrame = CFrame.lookAt(pos, pos + dir)
	wall.Material = if isWater then Enum.Material.Glass else Enum.Material.Sand
	wall.Color = if isWater then Color3.fromRGB(80, 160, 255) else Color3.fromRGB(214, 180, 112)
	wall.Transparency = if isWater then 0.35 else 0.1
	wall.Parent = Workspace
	CollectionService:AddTag(wall, "BlockProjectile")
	Debris:AddItem(wall, c.Dur)
	wall.Size = Vector3.new(width, 0.5, 3)
	TweenService:Create(wall, TweenInfo.new(0.25), { Size = Vector3.new(width, height, 3) }):Play()
	if P.Push then
		for _, m in ipairs(hostilesIn(c, pos, c.Ab.Radius)) do
			local _, r = liveParts(m)
			if r and not r.Anchored then
				r.AssemblyLinearVelocity = dir * P.Push + Vector3.new(0, 18, 0)
			end
		end
	end
	return true
end

-- Naruto 3: clones de sombra
H.Clones = function(c)
	local P = c.P
	local target = resolveTarget(c, 40, "hostile")
	local count = P.Count or 2
	local clones: { Model } = {}
	c.Char.Archivable = true
	for i = 1, count do
		local clone = c.Char:Clone()
		if clone then
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("ForceField") or d:IsA("BillboardGui") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					if d.Name ~= "HumanoidRootPart" then
						d.Transparency = math.max(d.Transparency, 0.15)
					end
				end
			end
			for _, tag in ipairs(CollectionService:GetTags(clone)) do
				CollectionService:RemoveTag(clone, tag)
			end
			clone.Name = "CloneDeSombra"
			local side = if i % 2 == 1 then 1 else -1
			clone:PivotTo(c.Root.CFrame * CFrame.new(side * 5, 0, 2))
			clone.Parent = Workspace
			burst(clone:GetPivot().Position, 4, Color3.fromRGB(235, 235, 235), 0.3)
			table.insert(clones, clone)
			Debris:AddItem(clone, c.Dur)
		end
	end
	shieldPct(c.Char, (P.Absorb or 0.08) * count, c.Dur)
	bubble(c.Char, c.Color, c.Dur)
	task.spawn(function()
		task.wait(0.7)
		for i, clone in ipairs(clones) do
			if not clone.Parent then
				continue
			end
			local _, tr = liveParts(target)
			if tr then
				clone:PivotTo(CFrame.lookAt(tr.Position + Vector3.new(i % 2 == 1 and 4 or -4, 0, 3), tr.Position))
				burst(tr.Position, 4, c.Color, 0.25)
				DamageService.Deal(c.Char, target :: Model, refDamage(c, P.Ref) * (P.Frac or 0.4), nil)
			end
			task.wait(0.25)
		end
	end)
	return true
end

-- Buffs con atributos: Super Saiyan, Modo Kurama, Gear Cuarto, Armadura de Arena, Susanoo, Diable Jambe
H.Buff = function(c)
	local P = c.P
	local char = c.Char
	local names: { string } = {}
	local function put(name: string, v: any)
		timedAttr(char, name, v, c.Dur)
		table.insert(names, name)
	end
	if P.OutDmg then put("OutDmg", P.OutDmg) end
	if P.InDmg then put("InDmg", P.InDmg) end
	if P.Reflect and P.Reflect > 0 then put("Reflect", P.Reflect) end
	if P.Lifesteal then put("Lifesteal", P.Lifesteal) end
	if P.Burn then put("BurnFrac", P.Burn) end
	if P.RangeMult then put("RangeMult", P.RangeMult) end
	if P.Speed then applySpeed(char, P.Speed, c.Dur) end
	if P.ShieldPct then
		shieldPct(char, P.ShieldPct, c.Dur)
	end
	bubble(char, c.Color, math.min(c.Dur, 2))
	ring(c.Root.Position, 8, c.Color, 0.6)
	local tk = nextToken()
	char:SetAttribute("Buff" .. c.Slot, tk)
	task.spawn(function()
		local t = 0
		while t < c.Dur and char.Parent and c.Hum.Health > 0 and char:GetAttribute("Buff" .. c.Slot) == tk do
			task.wait(1)
			t += 1
			if P.DrainPct then
				local _, max = EnergyRegenService.GetEnergy(c.Player)
				if not EnergyRegenService.ConsumeEnergy(c.Player, max * P.DrainPct, true) then
					for _, n in ipairs(names) do
						char:SetAttribute(n, nil)
						char:SetAttribute(n .. "_tk", nil)
					end
					clearSpeed(char)
					notify(c.Player, c.Ab.Name .. ": sin ki, el efecto terminó")
					return
				end
			end
		end
	end)
	return true
end

-- Sasuke 4: marca de ejecución
H.Mark = function(c)
	local P = c.P
	local target = resolveTarget(c, c.Ab.Range, "hostile")
	local hum = if target then target:FindFirstChildOfClass("Humanoid") else nil
	if not target or not hum then
		notify(c.Player, "Sin objetivo al alcance")
		return false
	end
	timedAttr(target, "MarkedBy", c.Char.Name, c.Dur)
	timedAttr(target, "MarkMult", P.Mult or 1.4, c.Dur)
	highlight(target, Color3.fromRGB(255, 40, 60), c.Dur)
	local untilT = os.clock() + c.Dur
	if P.Reset then
		hum.Died:Once(function()
			if os.clock() <= untilT and target:GetAttribute("LastHitBy") == c.Char.Name then
				cooldowns[c.Player] = cooldowns[c.Player] or {}
				cooldowns[c.Player][3] = nil
				local ok, combat = pcall(function()
					return require(Services.CombatService)
				end)
				if ok and typeof(combat) == "table" and (combat :: any).ResetCooldowns then
					(combat :: any).ResetCooldowns(c.Player)
				end
				for s = 1, 3 do
					CooldownRemote:FireClient(c.Player, s, 0)
				end
				notify(c.Player, "¡Ejecución! Recargas reiniciadas")
			end
		end)
	end
	return true
end

-- Itachi 3: Tsukuyomi
H.Silence = function(c)
	local target = resolveTarget(c, c.Ab.Range, "hostile")
	if not target then
		notify(c.Player, "Sin objetivo al alcance")
		return false
	end
	DamageService.ApplySilence(target, c.Dur)
	highlight(target, Color3.fromRGB(190, 20, 40), c.Dur)
	local _, r = liveParts(target)
	if r then
		burst(r.Position, 6, Color3.fromRGB(190, 20, 40), 0.5)
		floatText(r.Position, "Ilusión de Luna", Color3.fromRGB(230, 60, 80))
	end
	return true
end

-- Kakashi 3 / Usopp 4: inmoviliza en área (y luego daña si trae Mult)
H.RootArea = function(c)
	local P = c.P
	local center = areaCenter(c)
	ring(center, c.Ab.Radius, c.Color, c.Dur)
	local victims = hostilesIn(c, center, c.Ab.Radius)
	for _, m in ipairs(victims) do
		DamageService.ApplyStun(m, c.Dur)
		highlight(m, c.Color, c.Dur)
	end
	if P.Mult then
		task.delay(c.Dur, function()
			for _, m in ipairs(victims) do
				if liveParts(m) then
					DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * P.Mult, nil)
				end
			end
			burst(center, c.Ab.Radius, c.Color, 0.5)
		end)
	end
	return true
end

-- Kakashi 4: Kamui, atrae al centro y daña
H.Pull = function(c)
	local P = c.P
	local center = areaCenter(c)
	burst(center + Vector3.new(0, 3, 0), c.Ab.Radius * 0.7, Color3.fromRGB(150, 60, 220), 0.8)
	for _, m in ipairs(hostilesIn(c, center, c.Ab.Radius)) do
		local _, r = liveParts(m)
		if r then
			local flat = Vector3.new(center.X, r.Position.Y, center.Z)
			moveRoot(r, r.Position:Lerp(flat, P.Pull or 1))
			DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Mult or 1), nil)
		end
	end
	return true
end

-- Usopp 3: humo
H.Smoke = function(c)
	local P = c.P
	local center = areaCenter(c)
	local cloud = makeFx(Enum.PartType.Ball, CFrame.new(center), Vector3.new(2, 2, 2), Color3.fromRGB(150, 150, 155), 0.45)
	cloud.Material = Enum.Material.SmoothPlastic
	TweenService:Create(cloud, TweenInfo.new(0.4), { Size = Vector3.new(c.Ab.Radius * 2, c.Ab.Radius * 2, c.Ab.Radius * 2) }):Play()
	Debris:AddItem(cloud, c.Dur)
	for _, m in ipairs(hostilesIn(c, center, c.Ab.Radius)) do
		if not Players:GetPlayerFromCharacter(m) then
			timedAttr(m, "BlindUntil", os.clock() + c.Dur, c.Dur)
		end
		DamageService.ApplySlow(m, c.Dur, P.Slow or 0.3)
	end
	return true
end

-- Jinbe 4: parte del daño de aliados pasa a Jinbe
H.Guard = function(c)
	local P = c.P
	local list = alliesIn(c, c.Root.Position, c.Ab.Radius, false)
	for i = #list, (P.Count or 3) + 1, -1 do
		table.remove(list, i)
	end
	for _, m in ipairs(list) do
		timedAttr(m, "GuardBy", c.Char.Name, c.Dur)
		timedAttr(m, "GuardPct", P.Pct or 0.3, c.Dur)
		bubble(m, c.Color, 1.5)
	end
	timedAttr(c.Char, "InDmg", P.Self or 0.85, c.Dur)
	bubble(c.Char, c.Color, 1.5)
	ring(c.Root.Position, c.Ab.Radius, c.Color, 0.6)
	return true
end

-- Zoro 4: 5 cortes seguidos
H.MultiHit = function(c)
	local P = c.P
	local target = resolveTarget(c, c.Ab.Range, "hostile")
	local _, tr = liveParts(target)
	if not target or not tr then
		notify(c.Player, "Sin objetivo al alcance")
		return false
	end
	local dir = dirTowards(c, target)
	if flatDist(tr.Position, c.Root.Position) > 5 then
		c.Root.CFrame = CFrame.lookAt(tr.Position - dir * 4, Vector3.new(tr.Position.X, tr.Position.Y, tr.Position.Z))
	end
	applySpeed(c.Char, 0, c.Dur + 0.2)
	local hits = P.Hits or 5
	local per = refDamage(c, P.Ref) * (P.Total or 3.5) / hits
	task.spawn(function()
		for i = 1, hits do
			task.wait(c.Dur / hits)
			local _, r = liveParts(target)
			if not r or c.Hum.Health <= 0 or DamageService.IsStunned(c.Char) then
				break
			end
			DamageService.Deal(c.Char, target, per, nil)
			local angle = math.rad(i * 72)
			beam(r.Position - Vector3.new(math.cos(angle) * 4, -2 + math.sin(angle) * 2, 0), Vector3.new(math.cos(angle), math.sin(angle), 0), 8, 0.6, c.Color, 0.2)
		end
		clearSpeed(c.Char)
	end)
	return true
end

-- Sanji 4: fuego negro
H.AoeBurn = function(c)
	local P = c.P
	local center = areaCenter(c)
	local fire = Color3.fromRGB(70, 20, 110)
	burst(center, c.Ab.Radius, fire, 0.7)
	ring(center, c.Ab.Radius, Color3.fromRGB(255, 120, 40), 0.7)
	for _, m in ipairs(hostilesIn(c, center, c.Ab.Radius)) do
		local dealt = DamageService.Deal(c.Char, m, refDamage(c, P.Ref) * (P.Mult or 1), nil)
		if dealt > 0 then
			DamageService.AddBurn(c.Char, m, dealt * (P.BurnTotal or 0.4), c.Dur)
			highlight(m, Color3.fromRGB(255, 120, 40), c.Dur)
		end
	end
	return true
end

---------------------------------------------------------------------
-- LANZAMIENTO
---------------------------------------------------------------------
-- PODER 7 (todas las clases): curación propia. % de la vida máxima por rol, enfriamiento corto.
local SELF_HEAL: { [string]: number } = { Curador = 0.20, Mago = 0.09, Tirador = 0.07, Asesino = 0.06, Guerrero = 0.05, Tanque = 0.04 }
local SELF_HEAL_COST, SELF_HEAL_CD, SELF_HEAL_ALLY = 15, 25, 0.5 -- ki, segundos, fracción para aliados (solo Curador)
AbilityService.SelfHealInfo = { Name = "Primeros Auxilios", Cost = SELF_HEAL_COST }

local function selfHeal(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if DamageService.IsStunned(char) or DamageService.IsSilenced(char) then
		return
	end
	local mine = cooldowns[player]
	if not mine then
		mine = {}
		cooldowns[player] = mine
	end
	if os.clock() < (mine[7] or 0) then
		return
	end
	if EnergyRegenService.GetEnergy(player) < EnergyRegenService.Cost(player, SELF_HEAL_COST) then
		notify(player, "Ki insuficiente")
		return
	end
	local class = PlayerClass.Get(player)
	local pct = SELF_HEAL[class.Role] or 0.05
	local function heal(h: Humanoid, r: BasePart, p: number)
		local amt = math.floor(h.MaxHealth * p)
		h.Health = math.min(h.MaxHealth, h.Health + amt)
		floatText(r.Position, "+" .. amt, Color3.fromRGB(110, 255, 140))
	end
	heal(hum, root, pct)
	if class.Role == "Curador" then
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if pl ~= player and ch and h and h.Health > 0 and r and r:IsA("BasePart") and (r.Position - root.Position).Magnitude <= 25 then
				local ok, c2 = pcall(PlayerClass.Get, pl)
				if ok and c2.Faction == class.Faction then
					heal(h, r, pct * SELF_HEAL_ALLY)
				end
			end
		end
	end
	EnergyRegenService.ConsumeEnergy(player, SELF_HEAL_COST)
	mine[7] = os.clock() + SELF_HEAL_CD
	CooldownRemote:FireClient(player, 7, SELF_HEAL_CD)
	AttackAnimator.Play(char, "Cast", 0.7, 0.4)
end

local function cast(player: Player, slot: number, hint: any)
	if slot == 7 then
		selfHeal(player)
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if DamageService.IsStunned(char) or DamageService.IsSilenced(char) then
		return
	end
	local class = PlayerClass.Get(player)
	local set = Catalog[class.CharacterName]
	local ab = if set then set[slot] else nil
	if not ab then
		return
	end
	local mine = cooldowns[player]
	if not mine then
		mine = {}
		cooldowns[player] = mine
	end
	local now = os.clock()
	if now < (mine[slot] or 0) then
		return
	end
	local cur = EnergyRegenService.GetEnergy(player)
	if cur < EnergyRegenService.Cost(player, ab.Cost) then
		notify(player, "Ki insuficiente")
		return
	end
	local handler = H[ab.Kind]
	if not handler then
		warn("[AbilityService] Sin manejador para Kind=" .. ab.Kind)
		return
	end

	hint = AutoAttack.AimAt(player, hint) or hint -- apunta al objetivo marcado

	local pvp = ArenaService.IsInArena(root.Position)
	local P: { [string]: any } = table.clone(ab.P)
	if pvp then
		for k, v in pairs(ab.V) do
			P[k] = v
		end
	end
	local dur = (if pvp and ab.V.Duration then ab.V.Duration else ab.Duration) :: number
	local cd = if pvp then ab.CdPvp else ab.CdPve
	local color = FACTION_COLOR[class.Faction] or Color3.new(1, 1, 1)

	-- bono de set completo: Tirador/Curador +alcance, Mago +radio (copia del poder; el catálogo no se toca)
	local setR, setA = char:GetAttribute("SetRange"), char:GetAttribute("SetRadius")
	local abx = ab
	if (typeof(setR) == "number" and setR > 1) or (typeof(setA) == "number" and setA > 1) then
		abx = table.clone(ab)
		abx.Range = ab.Range * (if typeof(setR) == "number" and setR > 1 then setR else 1)
		abx.Radius = ab.Radius * (if typeof(setA) == "number" and setA > 1 then setA else 1)
	end
	local ctx: Ctx = {
		Player = player, Char = char, Root = root, Hum = hum, Class = class, Ab = abx, P = P, Dur = dur,
		Pvp = pvp, Hint = hint, Slot = slot, Color = color,
		SetCooldown = function(seconds: number)
			mine[slot] = os.clock() + seconds
			CooldownRemote:FireClient(player, slot, seconds)
		end,
	}
	local ok, result = pcall(handler, ctx)
	if not ok then
		warn("[AbilityService] Error en " .. ab.Name .. ": " .. tostring(result))
		return
	end
	if result ~= true then
		return
	end
	EnergyRegenService.ConsumeEnergy(player, ab.Cost)
	ctx.SetCooldown(cd)
	PassiveService.OnCast(player, function(mult: number, secs: number)
		applySpeed(char, mult, secs)
	end)
	if not pvp then
		-- apoyo de grupo (aporte para el reparto de XP/botín): fracción de la vida máxima del lanzador
		local SUPPORT_VALUE: { [string]: number } = { Aura = 0.25, Guard = 0.35, Taunt = 0.3, Wall = 0.25, Smoke = 0.15, Revive = 0.5, RootArea = 0.1, Silence = 0.1 }
		local v = SUPPORT_VALUE[ab.Kind]
		if v then
			require(script.Parent.ContributionService).Support(player, hum.MaxHealth * v)
		end
	end
	local POWER = { Buff = true, ShieldGroup = true, Aura = true, Taunt = true, Guard = true, Wall = true }
	local CASTING = { HealGroup = true, HealOverTime = true, Revive = true, Silence = true, Mark = true, RootArea = true, Pull = true, Smoke = true, AoeBurn = true, Channel = true, Clones = true, SelfBlast = true }
	local style = if POWER[ab.Kind] then "Power" elseif CASTING[ab.Kind] then "Cast" else AttackAnimator.StyleFor(player, false)
	AttackAnimator.Play(char, style, if ab.Kind == "Channel" then math.max(ab.Duration, 0.6) + 0.4 else 0.7, if ab.Kind == "Channel" then 0.8 else 0.4)
	if DEBUG then
		print(string.format("[AbilityService] %s usó '%s' (%s)", player.Name, ab.Name, if pvp then "PvP" else "PvE"))
	end
end

UseRemote.OnServerEvent:Connect(function(player: Player, slot: any, hint: any)
	if typeof(slot) ~= "number" or slot < 3 or slot > 7 or slot % 1 ~= 0 then
		return
	end
	cast(player, slot :: number, hint)
end)

---------------------------------------------------------------------
-- CICLO DE VIDA
---------------------------------------------------------------------
local function onCharacter(player: Player, char: Model)
	cooldowns[player] = nil -- al reaparecer, recargas limpias
	local pending = pendingRevive[player]
	if pending then
		pendingRevive[player] = nil
		local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
		local root = char:WaitForChild("HumanoidRootPart", 5)
		if hum and root then
			task.wait()
			char:PivotTo(pending.CF)
			hum.Health = hum.MaxHealth * pending.Hp
			local ff = Instance.new("ForceField")
			ff.Parent = char
			Debris:AddItem(ff, pending.Protect)
		end
	end
end

Players.PlayerAdded:Connect(function(pl)
	pl.CharacterAdded:Connect(function(c)
		onCharacter(pl, c)
	end)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	pl.CharacterAdded:Connect(function(c)
		onCharacter(pl, c)
	end)
end
Players.PlayerRemoving:Connect(function(pl)
	cooldowns[pl] = nil
	reviveLock[pl] = nil
	pendingRevive[pl] = nil
end)

-- API para el Auto-farm (misma validación que el jugador a mano)
function AbilityService.Info(player: Player, slot: number): Catalog.Ability?
	if slot == 7 then
		return nil -- el poder 7 (curación propia) lo maneja el Auto-farm por su cuenta
	end
	local set = Catalog[PlayerClass.Get(player).CharacterName]
	return if set then set[slot] else nil
end

function AbilityService.Ready(player: Player, slot: number): boolean
	local ab = AbilityService.Info(player, slot)
	if not ab then
		return false
	end
	local mine = cooldowns[player]
	if mine and os.clock() < (mine[slot] or 0) then
		return false
	end
	return EnergyRegenService.GetEnergy(player) >= EnergyRegenService.Cost(player, ab.Cost)
end

function AbilityService.SelfHealReady(player: Player): boolean
	local mine = cooldowns[player]
	if mine and os.clock() < (mine[7] or 0) then
		return false
	end
	return EnergyRegenService.GetEnergy(player) >= EnergyRegenService.Cost(player, SELF_HEAL_COST)
end

AbilityService.Cast = cast

print("[AbilityService] Listo: habilidades 3 y 4 de los 18 personajes.")
return AbilityService
