--!strict
--[[
    PassiveService (ModuleScript) -> ServerScriptService.Services.PassiveService
    PASIVAS DE ROL (3 por rol, todas con porcentajes pequeños: ayudan, no rompen el balance ni la emoción).
    Las aplican los mismos para los 24 personajes según su Role. Todo se ajusta en la tabla P de abajo.

      TANQUE    Piel de acero  : -2% de daño recibido por cada enemigo extra cerca (máx -8%)
                Presencia      : los enemigos a 30 studs prefieren atacarlo a él antes que a sus compañeros (65% cada 2 s)
                Voluntad       : 1 vez cada 120 s sobrevive a un golpe mortal con 10% de vida y 2 s de inmunidad
      GUERRERO  Sed de combate : +2% de daño por golpe seguido al mismo enemigo (máx +10%)
                Segundo aire   : al matar un enemigo recupera 2% de su vida máxima
                Furia          : con menos de 35% de vida hace +10% de daño
      ASESINO   Puñalada       : +12% de daño si golpea por la espalda
                Evasión        : 6% de probabilidad de esquivar un golpe
                Remate         : +10% de daño a enemigos con menos de 30% de vida
      TIRADOR   Ojo de halcón  : +8% de daño si el objetivo está a 25 studs o más
                Disparo encadenado: cada 5.º impacto hace +25%
                Retirada       : +8% de velocidad durante 3 s tras usar un poder
      MAGO      Maestría elemental: 10% de probabilidad de quemar (30% del daño en 4 s)
                Flujo de energía : +10% de regeneración de energía
                Eco            : 6% de probabilidad de repetir el golpe con 50% de daño
      CURADOR   Aura de vida   : cada 2 s cura 0.8% de vida máx. a los aliados a 25 studs
                Sobrecura      : 40% de la cura que sobra se vuelve escudo (máx 8% de vida máx.)
                Última esperanza: +12% de cura a aliados con menos de 35% de vida
    DamageService / AbilityService / MobBrain llaman a las funciones de aquí.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local Net = require(script.Parent.Net)
local FloatingRemote = Net.Get("Floating")

-- TODOS los porcentajes (0.02 = 2%)
local P = {
	Tanque = { PerExtraEnemy = 0.02, MaxReduction = 0.08, ExtraRadius = 25, AggroRadius = 30, AggroChance = 0.65, WillCooldown = 120, WillHp = 0.10, WillImmune = 2 },
	Guerrero = { StackDmg = 0.02, MaxStacks = 5, StackWindow = 4, KillHeal = 0.02, FuryBelow = 0.35, FuryDmg = 0.10 },
	Asesino = { BackDmg = 0.12, Dodge = 0.06, ExecuteBelow = 0.30, ExecuteDmg = 0.10 },
	Tirador = { FarDist = 25, FarDmg = 0.08, EveryHit = 5, EveryDmg = 0.25, RetreatSpeed = 1.08, RetreatTime = 3 },
	Mago = { BurnChance = 0.10, BurnFrac = 0.30, EnergyRegen = 1.10, EchoChance = 0.06, EchoFrac = 0.5 },
	Curador = { AuraHeal = 0.008, AuraRadius = 25, AuraEvery = 2, OverShield = 0.40, MaxShield = 0.08, LowHp = 0.35, LowBonus = 0.12 },
}

local PassiveService = {}
type DS = { [string]: any }
local DS: DS? = nil
function PassiveService.Bind(damageService: DS)
	DS = damageService
end

local function roleOf(m: Model): string?
	local pl = Players:GetPlayerFromCharacter(m)
	if not pl then
		return nil
	end
	local ok, class = pcall(PlayerClass.Get, pl)
	return if ok then class.Role else nil
end

local function rootOf(m: Model): BasePart?
	local r = m:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function hpOf(m: Model): (number, number)
	local h = m:FindFirstChildOfClass("Humanoid")
	return if h then h.Health else 0, if h then h.MaxHealth else 1
end

local function floatText(m: Model, text: string, color: Color3)
	local r = rootOf(m)
	if r then
		FloatingRemote:FireAllClients(r.Position + Vector3.new(0, 7, 0), text, color)
	end
end

-- estado por jugador
local combo: { [Model]: { Target: Model?, Stacks: number, At: number } } = {}
local shots: { [Model]: number } = {}
local willReady: { [Model]: number } = {}

---------------------------------------------------------------------
-- DAÑO QUE HACE EL JUGADOR (atacante con pasivas -> daño modificado)
---------------------------------------------------------------------
function PassiveService.Outgoing(attacker: Model, victim: Model, damage: number): number
	local role = roleOf(attacker)
	if not role or damage <= 0 then
		return damage
	end
	local aRoot, vRoot = rootOf(attacker), rootOf(victim)
	local vHp, vMax = hpOf(victim)
	if role == "Guerrero" then
		local c = P.Guerrero
		local s = combo[attacker]
		if not s then
			s = { Target = nil, Stacks = 0, At = 0 }
			combo[attacker] = s
		end
		local now = os.clock()
		if s.Target == victim and now - s.At <= c.StackWindow then
			s.Stacks = math.min(c.MaxStacks, s.Stacks + 1)
		else
			s.Target, s.Stacks = victim, 0
		end
		s.At = now
		damage *= 1 + c.StackDmg * s.Stacks
		local aHp, aMax = hpOf(attacker)
		if aHp / aMax < c.FuryBelow then
			damage *= 1 + c.FuryDmg
		end
	elseif role == "Asesino" then
		local c = P.Asesino
		if aRoot and vRoot then
			local toAttacker = (aRoot.Position - vRoot.Position) * Vector3.new(1, 0, 1)
			if toAttacker.Magnitude > 0.1 and vRoot.CFrame.LookVector:Dot(toAttacker.Unit) < -0.25 then
				damage *= 1 + c.BackDmg
				floatText(victim, "¡Espalda!", Color3.fromRGB(255, 170, 60))
			end
		end
		if vHp / vMax < c.ExecuteBelow then
			damage *= 1 + c.ExecuteDmg
		end
	elseif role == "Tirador" then
		local c = P.Tirador
		if aRoot and vRoot and (aRoot.Position - vRoot.Position).Magnitude >= c.FarDist then
			damage *= 1 + c.FarDmg
		end
		shots[attacker] = (shots[attacker] or 0) + 1
		if shots[attacker] % c.EveryHit == 0 then
			damage *= 1 + c.EveryDmg
			floatText(victim, "¡Encadenado!", Color3.fromRGB(120, 220, 255))
		end
	end
	return damage
end

-- Efectos que ocurren DESPUÉS de dañar (quemadura, eco). Devuelve daño extra ya aplicado.
function PassiveService.AfterHit(attacker: Model, victim: Model, damage: number)
	if roleOf(attacker) ~= "Mago" or damage <= 0 or not DS then
		return
	end
	local c = P.Mago
	local d = DS :: DS
	if math.random() < c.BurnChance then
		d.AddBurn(attacker, victim, damage * c.BurnFrac, 4)
	end
	if math.random() < c.EchoChance then
		task.delay(0.35, function()
			local vh = victim:FindFirstChildOfClass("Humanoid")
			if vh and vh.Health > 0 then
				vh:TakeDamage(math.floor(damage * c.EchoFrac))
				floatText(victim, "Eco", Color3.fromRGB(190, 150, 255))
			end
		end)
	end
end

---------------------------------------------------------------------
-- DAÑO QUE RECIBE EL JUGADOR
---------------------------------------------------------------------
function PassiveService.Incoming(attacker: Model, victim: Model, damage: number): number
	local role = roleOf(victim)
	if not role or damage <= 0 then
		return damage
	end
	if role == "Asesino" and math.random() < P.Asesino.Dodge then
		floatText(victim, "¡Esquiva!", Color3.fromRGB(255, 255, 255))
		return 0
	elseif role == "Tanque" then
		local c = P.Tanque
		local vRoot = rootOf(victim)
		if vRoot then
			local near = 0
			for _, m in ipairs(CollectionService:GetTagged("Mob")) do
				local r = if m:IsA("Model") then rootOf(m) else nil
				if r and (r.Position - vRoot.Position).Magnitude <= c.ExtraRadius then
					local h = (m :: Model):FindFirstChildOfClass("Humanoid")
					if h and h.Health > 0 then
						near += 1
					end
				end
			end
			local extra = math.clamp(near - 1, 0, 99)
			damage *= 1 - math.min(c.MaxReduction, extra * c.PerExtraEnemy)
		end
	end
	return damage
end

-- Antes de aplicar el daño: ¿es mortal? (Voluntad del tanque). Devuelve el daño final.
function PassiveService.PreLethal(victim: Model, damage: number, hum: Humanoid): number
	if damage < hum.Health or roleOf(victim) ~= "Tanque" then
		return damage
	end
	local c = P.Tanque
	local now = os.clock()
	if now < (willReady[victim] or 0) then
		return damage
	end
	willReady[victim] = now + c.WillCooldown
	hum.Health = math.max(1, hum.MaxHealth * c.WillHp)
	victim:SetAttribute("Immune", true)
	task.delay(c.WillImmune, function()
		victim:SetAttribute("Immune", nil)
	end)
	floatText(victim, "¡Voluntad!", Color3.fromRGB(255, 220, 90))
	return 0
end

function PassiveService.OnKill(attacker: Model)
	if roleOf(attacker) ~= "Guerrero" then
		return
	end
	local h = attacker:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then
		h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * P.Guerrero.KillHeal)
	end
end

-- Tirador: velocidad tras usar un poder. speedFn(mult, segundos) lo pasa AbilityService (usa su sistema de velocidad)
function PassiveService.OnCast(player: Player, speedFn: (number, number) -> ())
	local char = player.Character
	if char and roleOf(char) == "Tirador" then
		speedFn(P.Tirador.RetreatSpeed, P.Tirador.RetreatTime)
	end
end

---------------------------------------------------------------------
-- CURACIÓN (la llama DamageService.Heal)
---------------------------------------------------------------------
function PassiveService.HealAmount(caster: Model, target: Model, amount: number): number
	if roleOf(caster) ~= "Curador" then
		return amount
	end
	local hp, mx = hpOf(target)
	if hp / mx < P.Curador.LowHp then
		amount *= 1 + P.Curador.LowBonus
	end
	return amount
end

function PassiveService.Overheal(caster: Model, target: Model, overflow: number)
	if roleOf(caster) ~= "Curador" or overflow <= 0 then
		return
	end
	local c = P.Curador
	local _, mx = hpOf(target)
	local cur = target:GetAttribute("ShieldPoints")
	local points = math.min(mx * c.MaxShield, (if typeof(cur) == "number" then cur else 0) + overflow * c.OverShield)
	target:SetAttribute("ShieldPoints", points)
	local token = os.clock()
	target:SetAttribute("ShieldToken", token)
	task.delay(6, function()
		if target:GetAttribute("ShieldToken") == token then
			target:SetAttribute("ShieldPoints", 0)
		end
	end)
end

---------------------------------------------------------------------
-- TANQUE: presencia (la lee MobBrain). Devuelve un tanque cercano al que el mob debería atacar, o nil.
---------------------------------------------------------------------
function PassiveService.PreferredTank(mobPos: Vector3, current: Model?): Model?
	local c = P.Tanque
	local best: Model?, bestD = nil, c.AggroRadius
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local r = ch and rootOf(ch)
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		if ch and r and h and h.Health > 0 and roleOf(ch) == "Tanque" then
			local d = (r.Position - mobPos).Magnitude
			if d < bestD then
				best, bestD = ch, d
			end
		end
	end
	if best and best ~= current and math.random() < c.AggroChance then
		return best
	end
	return nil
end

---------------------------------------------------------------------
-- BUCLE LENTO: aura del curador y flujo de energía del mago
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(P.Curador.AuraEvery)
		for _, pl in ipairs(Players:GetPlayers()) do
			local ch = pl.Character
			local r = ch and rootOf(ch)
			local h = ch and ch:FindFirstChildOfClass("Humanoid")
			if ch and r and h and h.Health > 0 then
				local role = roleOf(ch)
				pl:SetAttribute("EnergyRegenMult", if role == "Mago" then P.Mago.EnergyRegen else 1)
				if role == "Curador" then
					for _, ally in ipairs(Players:GetPlayers()) do
						local ac = ally.Character
						local ar = ac and rootOf(ac)
						local ah = ac and ac:FindFirstChildOfClass("Humanoid")
						if ac and ar and ah and ah.Health > 0 and ah.Health < ah.MaxHealth and (ar.Position - r.Position).Magnitude <= P.Curador.AuraRadius then
							ah.Health = math.min(ah.MaxHealth, ah.Health + ah.MaxHealth * P.Curador.AuraHeal)
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	local ch = pl.Character
	if ch then
		combo[ch], shots[ch], willReady[ch] = nil, nil, nil
	end
end)

return PassiveService
