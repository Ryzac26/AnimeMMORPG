--!strict
--[[
    DamageService (ModuleScript) -> ServerScriptService.Services.DamageService
    ÚNICO lugar donde se hace daño, curación, escudo y control (aturdir/ralentizar).
    Todo lo demás (CombatService, MobSkills) llama aquí. Así las reglas viven en un solo sitio.

    Deal(atacante, víctima, base, opts?) -> daño real aplicado
      - jugador -> mob   : base × PlayerDamageMult(nivel atacante)        (reduce DamageReduction del mob)
      - mob -> jugador   : base(=Mult de la skill) × MobHit(nivel mob) × buffs
      - jugador -> jugador: SOLO en la Arena, naciones distintas -> ×0.27, brecha de nivel al 40%, Fragilidad
      - cualquier otro caso (aliados, mob->mob, PvP en ciudad/franjas) -> 0
    opts: { Stun: number?, Slow: number?, Push: Vector3? (dirección+fuerza), Heal: number? }
    Escudo ("ShieldPoints") absorbe antes que la vida. ForceField (protección de reaparición) bloquea todo.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local StatService = require(Services.StatService)
local ArenaService = require(Services.ArenaService)
local PassiveService = require(Services.PassiveService)
local GearService = require(Services.GearService)

local FragilityRemote = Net.Get("Fragility")
local FloatingRemote = Net.Get("Floating")

local DamageService = {}

-- (PassiveService necesita DamageService.AddBurn; se le pasa aquí para evitar la dependencia circular)
task.defer(function()
	PassiveService.Bind(DamageService :: any)
end)

-- RewardService se inyecta (evita dependencia circular): recibe el daño que los jugadores hacen a mobs
local damageListener: ((mob: Model, player: Player, amount: number) -> ())? = nil
function DamageService.SetDamageListener(fn: (Model, Player, number) -> ())
	damageListener = fn
end

-- Oyentes extra del daño de jugadores a mobs (DamageRankService: ranking de daño en jefes y Metin)
local extraListeners: { (Model, Player, number) -> () } = {}
function DamageService.AddDamageListener(fn: (Model, Player, number) -> ())
	table.insert(extraListeners, fn)
end

-- Compuerta de ataque (PveZoneService): decide si un jugador puede dañar a un mob (campamento = zona segura, mini jefe agotado)
local attackGate: ((Player, Model) -> boolean)? = nil
function DamageService.SetAttackGate(fn: (Player, Model) -> boolean)
	attackGate = fn
end

type Opts = { Stun: number?, Slow: number?, SlowAmount: number?, Push: Vector3? }

local function humanoidOf(m: Model): Humanoid?
	local h = m:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local function rootOf(m: Model): BasePart?
	local r = m:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function isMob(m: Model): boolean
	return m:GetAttribute("IsMob") == true
end

---------------------------------------------------------------------
-- CONTROL
---------------------------------------------------------------------
local ccState: { [Model]: { Count: number, Last: number } } = {}

function DamageService.IsStunned(m: Model): boolean
	local u = m:GetAttribute("StunnedUntil")
	return typeof(u) == "number" and os.clock() < u
end

-- Rendimientos decrecientes del control (aturdir, silenciar, inmovilizar comparten contador)
local function ccDuration(victim: Model, duration: number): number
	local now = os.clock()
	local st = ccState[victim]
	if not st or now - st.Last > GB.CC_DR_WINDOW then
		st = { Count = 0, Last = now }
		ccState[victim] = st
	end
	st.Count += 1
	st.Last = now
	if st.Count >= 4 then
		return 0
	end
	return duration * (0.5 ^ (st.Count - 1)) -- 1ª completa, 2ª mitad, 3ª cuarta parte...
end

local ApplyStunFwd: (Model, number) -> number
-- Silencio: no puede atacar ni usar habilidades (sí moverse). Los mobs lo sufren como aturdimiento.
function DamageService.IsSilenced(m: Model): boolean
	local u = m:GetAttribute("SilencedUntil")
	return typeof(u) == "number" and os.clock() < u
end

function DamageService.ApplySilence(victim: Model, duration: number): number
	if not humanoidOf(victim) or duration <= 0 then
		return 0
	end
	if isMob(victim) then
		return ApplyStunFwd(victim, duration)
	end
	local applied = ccDuration(victim, duration)
	if applied > 0 then
		victim:SetAttribute("SilencedUntil", os.clock() + applied)
	end
	return applied
end

function DamageService.ApplyStun(victim: Model, duration: number): number
	local hum = humanoidOf(victim)
	if not hum or duration <= 0 then
		return 0
	end
	local now = os.clock()
	local applied = ccDuration(victim, duration)
	if applied <= 0 then
		return 0
	end
	local prev = victim:GetAttribute("StunnedUntil")
	victim:SetAttribute("StunnedUntil", math.max(typeof(prev) == "number" and prev or 0, now + applied))
	if not isMob(victim) then
		local speed = hum.WalkSpeed
		if speed > 0 and victim:GetAttribute("BaseWalkSpeed") == nil then
			victim:SetAttribute("BaseWalkSpeed", speed)
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		task.delay(applied, function()
			if hum.Parent and not DamageService.IsStunned(victim) then
				hum.WalkSpeed = ((victim:GetAttribute("BaseWalkSpeed") :: number?) or 16) * ((victim:GetAttribute("SpeedMult") :: number?) or 1)
				hum.JumpPower = 50
			end
		end)
	end
	return applied
end
ApplyStunFwd = DamageService.ApplyStun

function DamageService.ApplySlow(victim: Model, duration: number, amount: number?)
	local hum = humanoidOf(victim)
	if not hum or duration <= 0 then
		return
	end
	local lost = amount or 0.5 -- fracción de velocidad que pierde
	victim:SetAttribute("SlowedUntil", os.clock() + duration)
	victim:SetAttribute("SlowAmount", lost)
	if not isMob(victim) then
		if victim:GetAttribute("BaseWalkSpeed") == nil then
			victim:SetAttribute("BaseWalkSpeed", hum.WalkSpeed)
		end
		hum.WalkSpeed = (victim:GetAttribute("BaseWalkSpeed") :: number) * (1 - lost) * ((victim:GetAttribute("SpeedMult") :: number?) or 1)
		task.delay(duration, function()
			local u = victim:GetAttribute("SlowedUntil")
			if hum.Parent and typeof(u) == "number" and os.clock() >= u and not DamageService.IsStunned(victim) then
				hum.WalkSpeed = (victim:GetAttribute("BaseWalkSpeed") :: number) * ((victim:GetAttribute("SpeedMult") :: number?) or 1)
			end
		end)
	end
end

---------------------------------------------------------------------
-- FRAGILIDAD (solo PvP): +5% daño recibido por golpe, máx 10, caduca 8 s tras el último
---------------------------------------------------------------------
local function addFragility(victim: Model, player: Player)
	local stacks = math.min(GB.FRAGILITY_MAX_STACKS, ((victim:GetAttribute("Fragility") :: number?) or 0) + 1)
	victim:SetAttribute("Fragility", stacks)
	local token = os.clock()
	victim:SetAttribute("FragilityToken", token)
	FragilityRemote:FireClient(player, stacks)
	task.delay(GB.FRAGILITY_DURATION, function()
		if victim:GetAttribute("FragilityToken") == token then
			victim:SetAttribute("Fragility", 0)
			FragilityRemote:FireClient(player, 0)
		end
	end)
end

function DamageService.AddFragility(victim: Model, stacks: number)
	local pl = Players:GetPlayerFromCharacter(victim)
	if pl then
		for _ = 1, stacks do
			addFragility(victim, pl)
		end
	end
end

-- Quita 1 debuff típico + Fragilidad (Bulma / Sakura)
function DamageService.Cleanse(m: Model)
	m:SetAttribute("Fragility", 0)
	m:SetAttribute("FragilityToken", nil)
	m:SetAttribute("SilencedUntil", nil)
	m:SetAttribute("OutDebuff", nil)
	m:SetAttribute("SlowedUntil", nil)
	local hum = m:FindFirstChildOfClass("Humanoid")
	local base = m:GetAttribute("BaseWalkSpeed")
	if hum and typeof(base) == "number" and not DamageService.IsStunned(m) then
		hum.WalkSpeed = base * ((m:GetAttribute("SpeedMult") :: number?) or 1)
	end
	local pl = Players:GetPlayerFromCharacter(m)
	if pl then
		FragilityRemote:FireClient(pl, 0)
	end
end

-- Quemadura: daño directo repartido en ticks de 1 s (los créditos de XP siguen al atacante)
function DamageService.AddBurn(attacker: Model, victim: Model, total: number, duration: number)
	if total < 1 or duration <= 0 then
		return
	end
	local aPlayer = Players:GetPlayerFromCharacter(attacker)
	local ticks = math.max(1, math.floor(duration))
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(1)
			local h = humanoidOf(victim)
			if not h or victim:FindFirstChildOfClass("ForceField") or victim:GetAttribute("Immune") == true then
				return
			end
			local amt = math.floor(total / ticks)
			if amt > 0 then
				victim:SetAttribute("LastHitBy", attacker.Name)
				victim:SetAttribute("LastHitByPlayer", aPlayer ~= nil)
				victim:SetAttribute("LastHitAt", os.clock())
				h:TakeDamage(amt)
				local r = rootOf(victim)
				if r then
					FloatingRemote:FireAllClients(r.Position + Vector3.new(0, 5, 0), tostring(amt), Color3.fromRGB(255, 140, 60))
				end
				if aPlayer and isMob(victim) and damageListener then
					damageListener(victim, aPlayer, amt)
				end
			end
		end
	end)
end

---------------------------------------------------------------------
-- DAÑO
---------------------------------------------------------------------
-- Daño extra DIRECTO de un jugador a un mob (poderes de mascota: Zarpazo, Aliento de fuego, Instinto cazador).
-- No vuelve a aplicar equipo ni pasivas (ya vienen en el golpe que lo originó), pero respeta compuertas e inmunidades,
-- cuenta para el ranking de daño y el reparto de botín, y muestra su número. Devuelve el daño hecho.
function DamageService.TrueDamage(attacker: Model, victim: Model, amount: number): number
	local aPlayer = Players:GetPlayerFromCharacter(attacker)
	local vHum = humanoidOf(victim)
	if not aPlayer or not vHum or not isMob(victim) or victim:FindFirstChildOfClass("ForceField") or victim:GetAttribute("Immune") == true then
		return 0
	end
	if victim:GetAttribute("ShrineField") == true or (attackGate and not attackGate(aPlayer, victim)) then
		return 0
	end
	local red = victim:GetAttribute("DamageReduction")
	local damage = math.floor(amount * (if typeof(red) == "number" then (1 - red) else 1))
	if damage <= 0 then
		return 0
	end
	victim:SetAttribute("LastHitBy", attacker.Name)
	victim:SetAttribute("LastHitByPlayer", true)
	victim:SetAttribute("LastHitAt", os.clock())
	vHum:TakeDamage(damage)
	local root = rootOf(victim)
	if root then
		FloatingRemote:FireAllClients(root.Position + Vector3.new(0, 5, 0), tostring(damage), Color3.fromRGB(255, 170, 80))
	end
	if damageListener then
		damageListener(victim, aPlayer, damage)
	end
	for _, fn in ipairs(extraListeners) do
		fn(victim, aPlayer, damage)
	end
	return damage
end

function DamageService.Deal(attacker: Model, victim: Model, base: number, opts: Opts?): number
	local vHum = humanoidOf(victim)
	if not vHum or attacker == victim or victim:FindFirstChildOfClass("ForceField") or victim:GetAttribute("Immune") == true then
		return 0
	end
	local aPlayer = Players:GetPlayerFromCharacter(attacker)
	local vPlayer = Players:GetPlayerFromCharacter(victim)
	local aMob, vMob = isMob(attacker), isMob(victim)
	local damage = 0

	-- sin daño amigo: jamás se dañan jugadores de la misma facción (ni en PvE ni en PvP)
	if aPlayer and vPlayer and aPlayer:GetAttribute("Faction") == vPlayer:GetAttribute("Faction") then
		return 0
	end
	-- Metin: recuerda qué facción lo golpeó por última vez (el Auto-Metin se apaga si lo ataca otra facción)
	if aPlayer and victim:GetAttribute("Metin") == true then
		victim:SetAttribute("Hit_" .. tostring(aPlayer:GetAttribute("Faction")), os.clock())
	end
	-- Campo protector de un santuario (ArenaStyler): solo lo daña una facción distinta a la dueña
	if aPlayer and victim:GetAttribute("ShrineField") == true then
		local fa = aPlayer:GetAttribute("Faction")
		if fa == victim:GetAttribute("ShrineOwner") then
			return 0
		end
		victim:SetAttribute("LastHitFaction", fa)
	end

	if aPlayer and vMob and attackGate and not attackGate(aPlayer, victim) then
		return 0
	end

	if aPlayer and vMob then
		damage = base * GB.PlayerDamageMult(StatService.GetLevel(aPlayer))
		damage = GearService.Outgoing(aPlayer, damage, false) -- Ataque y Crítico del equipo
		local red = victim:GetAttribute("DamageReduction")
		if typeof(red) == "number" then
			damage *= (1 - red)
		end
	elseif aMob and vPlayer then
		local buff = attacker:GetAttribute("DmgBuff")
		damage = base * GB.MobHit(StatService.GetLevel(attacker)) * (if typeof(buff) == "number" then buff else 1)
		damage = GearService.Incoming(vPlayer, damage, false) -- Defensa del equipo
	elseif aPlayer and vPlayer then
		if not ArenaService.PvpAllowed(aPlayer, vPlayer) then
			return 0
		end
		damage = base * GB.PvpDamageMult(StatService.GetLevel(aPlayer), StatService.GetLevel(vPlayer))
		damage = GearService.Incoming(vPlayer, GearService.Outgoing(aPlayer, damage, true), true) -- equipo en PvP (cuenta la mitad)
		local frag = victim:GetAttribute("Fragility")
		if typeof(frag) == "number" and frag > 0 then
			damage *= 1 + GB.FRAGILITY_PER_HIT * frag
		end
		addFragility(victim, vPlayer)
	else
		return 0
	end

	-- Santuarios de la arena (ArenaStyler): bonus de daño de la facción dueña, solo dentro de la arena
	if aPlayer then
		local shrine = aPlayer:GetAttribute("ShrineDmg")
		if typeof(shrine) == "number" then
			damage *= shrine
		end
	end

	-- Habilidades 3/4: modificadores por atributos (los pone AbilityService y caducan solos)
	local function num(m: Model, name: string): number
		local v = m:GetAttribute(name)
		return if typeof(v) == "number" then v else 1
	end
	damage *= num(attacker, "OutDmg") * num(attacker, "OutDebuff") * num(victim, "InDmg")
	local markedBy = victim:GetAttribute("MarkedBy")
	if markedBy == attacker.Name then
		damage *= num(victim, "MarkMult")
	end
	-- Juramento de Jinbe: parte del daño pasa al guardián
	local guardName = victim:GetAttribute("GuardBy")
	if typeof(guardName) == "string" and damage > 0 then
		local gp = Players:FindFirstChild(guardName)
		local gc = if gp and gp:IsA("Player") then gp.Character else nil
		local gh = if gc then humanoidOf(gc) else nil
		local gr = if gc then rootOf(gc) else nil
		local vr = rootOf(victim)
		if gc and gh and gr and vr and gc ~= victim and (gr.Position - vr.Position).Magnitude <= 45 then
			local share = damage * num(victim, "GuardPct")
			damage -= share
			gh:TakeDamage(math.floor(share * num(gc, "InDmg")))
		end
	end

	-- Pasivas de rol (Services/PassiveService): daño del atacante y defensa de la víctima
	if aPlayer and damage > 0 then
		damage = PassiveService.Outgoing(attacker, victim, damage)
	end
	if vPlayer and damage > 0 then
		damage = PassiveService.Incoming(attacker, victim, damage)
	end

	-- Escudo
	local shield = victim:GetAttribute("ShieldPoints")
	if typeof(shield) == "number" and shield > 0 then
		local absorbed = math.min(shield, damage)
		victim:SetAttribute("ShieldPoints", shield - absorbed)
		damage -= absorbed
	end

	damage = math.floor(damage)
	if damage > 0 then
		-- (antes del daño: la IA del mob lee quién lo golpeó dentro del evento HealthChanged para avisar a su grupo)
		victim:SetAttribute("LastHitBy", attacker.Name)
		victim:SetAttribute("LastHitByPlayer", aPlayer ~= nil)
		victim:SetAttribute("LastHitAt", os.clock())
		if vPlayer then
			damage = math.floor(PassiveService.PreLethal(victim, damage, vHum))
		end
		vHum:TakeDamage(damage)
		if damage > 0 and vHum.Health <= 0 and aPlayer then
			PassiveService.OnKill(attacker)
		end
		if aPlayer then
			PassiveService.AfterHit(attacker, victim, damage)
		end
		local root = rootOf(victim)
		if root then
			FloatingRemote:FireAllClients(root.Position + Vector3.new(0, 5, 0), tostring(damage), if vPlayer then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(255, 230, 120))
		end
		if aPlayer and vMob then
			if damageListener then
				damageListener(victim, aPlayer, damage)
			end
			for _, fn in ipairs(extraListeners) do
				fn(victim, aPlayer, damage)
			end
		end
		-- Robo de vida (Modo Kurama)
		local ls = attacker:GetAttribute("Lifesteal")
		local setLs = attacker:GetAttribute("SetLifesteal") -- bono de set completo del Guerrero
		local aHum = humanoidOf(attacker)
		local lsTotal = (if typeof(ls) == "number" then ls else 0) + (if typeof(setLs) == "number" then setLs else 0)
		if lsTotal > 0 and aHum then
			aHum.Health = math.min(aHum.MaxHealth, aHum.Health + damage * lsTotal)
		end
		-- Reflejo cuerpo a cuerpo (Armadura de Arena)
		local reflBase, setRefl = victim:GetAttribute("Reflect"), victim:GetAttribute("SetReflect") -- SetReflect: bono de set completo del Tanque
		local refl = (if typeof(reflBase) == "number" then reflBase else 0) + (if typeof(setRefl) == "number" then setRefl else 0)
		local aRoot, vRoot = rootOf(attacker), rootOf(victim)
		if refl > 0 and aHum and aRoot and vRoot and (aRoot.Position - vRoot.Position).Magnitude <= 14 then
			aHum:TakeDamage(math.floor(damage * refl))
		end
		-- Quemadura (Diable Jambe)
		local burn = attacker:GetAttribute("BurnFrac")
		if typeof(burn) == "number" and burn > 0 then
			DamageService.AddBurn(attacker, victim, damage * burn, 4)
		end
	end

	if opts then
		if opts.Stun and opts.Stun > 0 then
			DamageService.ApplyStun(victim, opts.Stun)
		end
		if opts.Slow and opts.Slow > 0 then
			DamageService.ApplySlow(victim, opts.Slow, opts.SlowAmount)
		end
		local root = rootOf(victim)
		if opts.Push and root and not root.Anchored then
			root.AssemblyLinearVelocity = opts.Push
		end
	end
	return damage
end

---------------------------------------------------------------------
-- CURACIÓN / ESCUDO (escalan con la vida del nivel del lanzador)
---------------------------------------------------------------------
function DamageService.Heal(caster: Model, target: Model, base: number): number
	local hum = humanoidOf(target)
	if not hum then
		return 0
	end
	local healMult = GearService.HealMult(Players:GetPlayerFromCharacter(caster)) -- Curación del equipo
	local amount = math.floor(PassiveService.HealAmount(caster, target, base * GB.PlayerHpMult(StatService.GetLevel(caster)) * healMult))
	local overflow = hum.Health + amount - hum.MaxHealth
	hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	if overflow > 0 then
		PassiveService.Overheal(caster, target, overflow)
	end
	return amount
end

function DamageService.AddShield(caster: Model, target: Model, base: number, duration: number)
	local points = math.floor(base * GB.PlayerHpMult(StatService.GetLevel(caster)))
	local token = os.clock()
	target:SetAttribute("ShieldPoints", points)
	target:SetAttribute("ShieldToken", token)
	task.delay(duration, function()
		if target:GetAttribute("ShieldToken") == token then
			target:SetAttribute("ShieldPoints", 0)
		end
	end)
	return points
end

function DamageService.Forget(m: Model)
	ccState[m] = nil
end

Players.PlayerRemoving:Connect(function(pl)
	if pl.Character then
		ccState[pl.Character] = nil
	end
end)

return DamageService
