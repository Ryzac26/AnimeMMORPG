--!strict
--[[
    MobBrain (ModuleScript) -> ServerScriptService.Services.Mobs.MobBrain
    IA de UN enemigo. MobService la llama ~10 veces por segundo para cada mob ACTIVO (cerca de jugadores).
    Estados: Idle -> Chase/Combat -> Return (vuelve a su punto y se cura) ; Flee (pasivo "Flee").
      - Pasivos ("Aggressive=false") solo atacan si les pegan; agresivos detectan jugadores a AGGRO_RANGE.
      - Elige una skill lista (cooldown) y en rango; si no hay, ataque básico cuerpo a cuerpo.
      - Passives del catálogo: Flee, CallHelp, Dodge, Transform, Regen, Absorb.
    No hace daño por sí mismo: todo pasa por MobSkills -> DamageService.
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local MobsFolder = ServerScriptService.Services.Mobs
local MobSkills = require(MobsFolder.MobSkills)
local MobBuilder = require(MobsFolder.MobBuilder)
local DamageService = require(ServerScriptService.Services.DamageService)
local PassiveService = require(ServerScriptService.Services.PassiveService)
-- CUEVAS (DungeonService): los monstruos de una cueva no ven a través de las paredes y, si te pierden de vista, siguen el laberinto
-- celda por celda. Si el módulo DungeonNav no existe, todo funciona como antes.
local navModule = ServerScriptService.Services:FindFirstChild("DungeonNav")
local DungeonNav: any = if navModule and navModule:IsA("ModuleScript") then require(navModule) else nil

local function caveId(model: Model): number?
	local id = model:GetAttribute("Dungeon")
	return if DungeonNav and typeof(id) == "number" then id else nil
end

local function canSee(model: Model, from: Vector3, to: Vector3): boolean
	local id = caveId(model)
	if not id then
		return true
	end
	return DungeonNav.CanSee(id, from + Vector3.new(0, 2.5, 0), to + Vector3.new(0, 1.5, 0))
end
local function chasePoint(model: Model, from: Vector3, to: Vector3): Vector3
	local id = caveId(model)
	if not id then
		return to
	end
	return DungeonNav.Waypoint(id, from, to) or to
end

local AGGRO_RANGE = 55
local LEASH_RANGE = 80 -- si se aleja tanto de su punto, abandona la persecución y regresa
local LEASH_RANGE_HURT = 130 -- correa ampliada mientras el jugador le está pegando: perseguir a un jefe que se aleja ya no lo reinicia
local HURT_WINDOW = 8 -- s desde el último golpe recibido en los que cuenta la correa ampliada
local KITE_LIMIT = 28 -- los mobs a distancia solo retroceden mientras estén a menos de esto de su punto (jefes: KITE_LIMIT_BOSS)
local KITE_LIMIT_BOSS = 36
local KITE_STEP = 6 -- cuánto retroceden por paso (antes 8)
local LOSE_DISTANCE = 65 -- objetivo más lejos que esto = "lo perdió de vista"
local LOSE_TARGET_AFTER = 4 -- s seguidos fuera de alcance antes de rendirse
local RETURN_HEAL_PER_SEC = 0.25 -- % de vida máxima que recupera por segundo mientras vuelve (inmune)
local BASIC_RANGE = 7
local BASIC_COOLDOWN = 1.6
local RANGED_BASIC = { Kind = "Projectile", Name = "Disparo", Range = 45, Mult = 0.45, Speed = 70, Size = 1.6, Windup = 0.3 }
local RANGED_COOLDOWN = 2.2
local BASIC_SKILL = { Kind = "Melee", Name = "Golpe", Range = 7, Mult = 0.8, Windup = 0.3 }

export type Mob = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Def: any,
	Level: number,
	Home: Vector3,
	Target: Model?,
	Provoked: boolean,
	Busy: boolean,
	Cooldowns: { number },
	BasicReady: number,
	LastSeen: number,
	LastHealth: number,
	Transformed: boolean,
	Fled: boolean,
	FleeUntil: number,
	DodgeReady: number,
	Passives: { [string]: boolean },
	Ctx: MobSkills.Ctx,
	Summons: number,
	NextTankLook: number?,
	Returning: boolean,
	ReturnSince: number,
	OutOfReach: number,
	LastHurtAt: number?,
}

local MobBrain = {}

function MobBrain.New(model: Model, def: any, level: number, summonFn: (string, number) -> (), aura: Color3?): Mob
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local passives: { [string]: boolean } = {}
	for _, p in ipairs(def.Passives) do
		passives[p] = true
	end
	local mob: Mob
	mob = {
		Model = model, Root = root, Humanoid = hum, Def = def, Level = level,
		Home = root.Position, Target = nil, Provoked = false, Busy = false,
		Cooldowns = table.create(#def.Skills, 0), BasicReady = 0, LastSeen = os.clock(),
		LastHealth = hum.Health, Transformed = false, Fled = false, FleeUntil = 0, DodgeReady = 0,
		Passives = passives, Summons = 0, Returning = false, ReturnSince = 0, OutOfReach = 0,
		Ctx = {
			Model = model, Root = root, Humanoid = hum, Level = level,
			Alive = function()
				return hum.Health > 0 and model.Parent ~= nil
			end,
			Summon = function(id: string, count: number)
				summonFn(id, count)
			end,
			Color = aura or Color3.fromRGB(255, 220, 120),
		},
	}
	if passives.Absorb then
		model:SetAttribute("DamageReduction", 0.15)
	end
	return mob
end

local function liveTarget(t: Model?): (Humanoid?, BasePart?)
	if not t or not t.Parent then
		return nil, nil
	end
	local h = t:FindFirstChildOfClass("Humanoid")
	local r = t:FindFirstChild("HumanoidRootPart")
	if h and h.Health > 0 and r and r:IsA("BasePart") and not t:FindFirstChildOfClass("ForceField") then
		return h, r
	end
	return nil, nil
end

-- ¿está el punto dentro de una zona segura? (los mobs pierden de vista a quien se refugia en ella)
local function inSafe(pos: Vector3): boolean
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

local function nearestPlayer(pos: Vector3, range: number, viewer: Model?): Model?
	local best: Model? = nil
	local bestD = range
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		local _, r = liveTarget(c)
		if c and r and not inSafe(r.Position) then
			local d = (r.Position - pos).Magnitude
			-- los Invisible/ocultos no cambian objetivo; el ForceField (protección) los hace ignorar
			if d < bestD and (not viewer or canSee(viewer, pos, r.Position)) then
				bestD = d
				best = c
			end
		end
	end
	return best
end

-- Llamado por MobService cuando la vida del mob cambia
function MobBrain.OnDamaged(mob: Mob, newHealth: number)
	local lost = mob.LastHealth - newHealth
	mob.LastHealth = newHealth
	if lost <= 0 then
		return
	end
	mob.Provoked = true
	local now = os.clock()
	mob.LastHurtAt = now
	local attackerName = mob.Model:GetAttribute("LastHitBy")
	if typeof(attackerName) == "string" and not mob.Target then
		local pl = Players:FindFirstChild(attackerName)
		if pl and pl:IsA("Player") and pl.Character then
			mob.Target = pl.Character
		end
	end
	mob.LastSeen = now

	local maxHp = mob.Humanoid.MaxHealth
	-- Aviso al grupo: los compañeros de grupo (mismo GroupId) siempre acuden; con CallHelp también los mobs a 60 studs
	if not mob.Model:GetAttribute("CalledHelp") then
		mob.Model:SetAttribute("CalledHelp", true)
		local gid = mob.Model:GetAttribute("GroupId")
		for _, m in ipairs(CollectionService:GetTagged("Mob")) do
			local r = m:IsA("Model") and m:FindFirstChild("HumanoidRootPart")
			if m ~= mob.Model and r and r:IsA("BasePart") then
				local sameGroup = typeof(gid) == "number" and gid ~= 0 and m:GetAttribute("GroupId") == gid
				local near = mob.Passives.CallHelp and (r.Position - mob.Root.Position).Magnitude <= 60
				if sameGroup or near then
					m:SetAttribute("Alerted", mob.Target and mob.Target.Name or "")
				end
			end
		end
	end
	-- Transform (50% vida): más daño y más grande
	if mob.Passives.Transform and not mob.Transformed and newHealth <= maxHp * 0.5 then
		mob.Transformed = true
		local baseBuff = mob.Model:GetAttribute("BaseBuff") -- en una cueva ya trae el aumento por grupo: se multiplica, no se pisa
		local transformed = (if typeof(baseBuff) == "number" then baseBuff else 1) * 1.3
		mob.Model:SetAttribute("DmgBuff", transformed)
		mob.Model:SetAttribute("BaseBuff", transformed)
		mob.Model:ScaleTo(mob.Model:GetScale() * 1.12)
	end
	-- Flee (20% vida): huye una vez hacia su punto
	if mob.Passives.Flee and not mob.Fled and newHealth <= maxHp * 0.2 then
		mob.Fled = true
		mob.FleeUntil = now + 4
		mob.Target = nil
	end
	-- Dodge: pequeño salto lateral cada 6 s
	if mob.Passives.Dodge and now >= mob.DodgeReady and not mob.Busy then
		mob.DodgeReady = now + 6
		local side = if math.random() < 0.5 then -1 else 1
		local from = mob.Root.Position
		mob.Root.CFrame = mob.Root.CFrame + mob.Root.CFrame.RightVector * side * 8
		MobSkills.DodgeFx(mob.Model, from, mob.Root.Position, mob.Def.Faction)
	end
end

local function resetToHome(mob: Mob)
	mob.Target = nil
	mob.Provoked = false
	mob.Summons = 0
	mob.Model:SetAttribute("CalledHelp", nil)
	mob.Model:SetAttribute("Alerted", nil)
	mob.Humanoid.Health = mob.Humanoid.MaxHealth
	mob.LastHealth = mob.Humanoid.Health
end

-- Regreso a casa: mientras vuelve es INMUNE y se cura rápido. Evita el abuso de "pegar de lejos y huir" con clases a distancia.
local function startReturn(mob: Mob, now: number)
	mob.Returning = true
	mob.ReturnSince = now
	mob.Target = nil
	mob.Provoked = false
	mob.OutOfReach = 0
	mob.Model:SetAttribute("Immune", true)
	mob.Model:SetAttribute("CalledHelp", nil)
	mob.Model:SetAttribute("Alerted", nil)
end

local function chooseSkill(mob: Mob, dist: number, now: number): (any?, number?)
	local order: { number } = {}
	for i = 1, #mob.Def.Skills do
		table.insert(order, i)
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	for _, i in ipairs(order) do
		local s = mob.Def.Skills[i]
		if now >= mob.Cooldowns[i] then
			local k = s.Kind
			local ok = false
			if k == "Summon" then
				ok = mob.Summons < 6
			elseif k == "Barrier" then
				ok = mob.Humanoid.Health < mob.Humanoid.MaxHealth * 0.85
			elseif k == "Invisible" then
				ok = dist > 15
			elseif k == "Teleport" then
				ok = dist > 14
			elseif k == "Buff" then
				ok = true
			elseif k == "Dash" then
				ok = dist > 5 and dist <= s.Range + 3
			else
				ok = dist <= MobSkills.EffectiveRange(s) + 2
			end
			if ok then
				return s, i
			end
		end
	end
	return nil, nil
end

-- distancia a la que le gusta pelear (los de rango se quedan lejos)
local function preferredDistance(mob: Mob): number
	local best = BASIC_RANGE - 2
	for _, s in ipairs(mob.Def.Skills) do
		if s.Kind == "Projectile" or s.Kind == "Line" then
			best = math.max(best, math.min(s.Range * 0.55, 30))
		end
	end
	return best
end

function MobBrain.Step(mob: Mob, dt: number, now: number): boolean
	local hum, root = mob.Humanoid, mob.Root
	if hum.Health <= 0 then
		return false
	end

	-- (la animación de caminar/atacar la dibuja el cliente: CharacterAnimClient)

	if mob.Busy then
		return true
	end
	if mob.Returning then
		hum.WalkSpeed = mob.Def.Speed * 1.4
		hum:MoveTo(mob.Home)
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * RETURN_HEAL_PER_SEC * dt)
		mob.LastHealth = hum.Health
		local d = (root.Position - mob.Home).Magnitude
		if d <= 6 or now - mob.ReturnSince > 20 then
			if d > 6 then
				root.CFrame = CFrame.new(mob.Home)
			end
			mob.Returning = false
			mob.Model:SetAttribute("Immune", nil)
			resetToHome(mob)
		end
		return true
	end
	if DamageService.IsStunned(mob.Model) then
		hum:Move(Vector3.zero)
		hum.WalkSpeed = 0
		return true
	end
	local slowed = mob.Model:GetAttribute("SlowedUntil")
	local slowAmt = mob.Model:GetAttribute("SlowAmount")
	hum.WalkSpeed = if typeof(slowed) == "number" and now < slowed then mob.Def.Speed * (1 - (if typeof(slowAmt) == "number" then slowAmt else 0.5)) else mob.Def.Speed

	-- Regen pasiva (en combate)
	if mob.Passives.Regen and mob.Target then
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.008 * dt)
		mob.LastHealth = hum.Health
	end

	-- alerta de otro mob (CallHelp)
	if not mob.Target then
		local alert = mob.Model:GetAttribute("Alerted")
		if typeof(alert) == "string" and alert ~= "" then
			local pl = Players:FindFirstChild(alert)
			if pl and pl:IsA("Player") and pl.Character then
				mob.Target = pl.Character
				mob.Provoked = true
				mob.LastSeen = now
			end
			mob.Model:SetAttribute("Alerted", nil)
		end
	end

	-- huida
	if now < mob.FleeUntil then
		hum:MoveTo(mob.Home)
		return true
	end

	-- Habilidades de jugador: humo (pierde el objetivo) y provocación (obliga a atacar al provocador)
	local blind = mob.Model:GetAttribute("BlindUntil")
	local blinded = typeof(blind) == "number" and now < blind
	if blinded then
		mob.Target = nil
	else
		local tauntUntil = mob.Model:GetAttribute("TauntUntil")
		local tauntBy = mob.Model:GetAttribute("TauntBy")
		if typeof(tauntUntil) == "number" and now < tauntUntil and typeof(tauntBy) == "string" then
			local tp = Players:FindFirstChild(tauntBy)
			local tc = if tp and tp:IsA("Player") then tp.Character else nil
			if tc and liveTarget(tc) then
				mob.Target = tc
				mob.Provoked = true
			end
		end
	end

	-- Pasiva del tanque (Presencia): cada ~2 s, los mobs cercanos a un tanque prefieren atacarlo a él
	if mob.Target and now >= (mob.NextTankLook or 0) then
		mob.NextTankLook = now + 2
		local tank = PassiveService.PreferredTank(root.Position, mob.Target)
		if tank and liveTarget(tank) then
			mob.Target = tank
			mob.Provoked = true
		end
	end

	-- objetivo
	local thum, troot = liveTarget(mob.Target)
	if not thum then
		mob.Target = nil
	end
	if not blinded and not mob.Target and (mob.Def.Aggressive or mob.Provoked) then
		local found = nearestPlayer(root.Position, AGGRO_RANGE, mob.Model)
		if found then
			mob.Target = found
			mob.LastSeen = now
			thum, troot = liveTarget(found)
		end
	end

	if troot and inSafe(troot.Position) then
		-- el objetivo entró a la zona segura: lo pierde de vista, se cura y vuelve a su lugar
		mob.Target = nil
		mob.Provoked = false
		startReturn(mob, now)
		return true
	end

	local homeDist = (root.Position - mob.Home).Magnitude
	if not mob.Target or not troot then
		if mob.Humanoid.Health < mob.Humanoid.MaxHealth and now - mob.LastSeen > 2 then
			startReturn(mob, now) -- perdió al objetivo: vuelve inmune y se cura
		elseif homeDist > 6 then
			hum:MoveTo(mob.Home)
		end
		return true
	end

	mob.LastSeen = now
	local dist = (troot.Position - root.Position).Magnitude
	-- correa / perdió de vista: demasiado lejos de su punto, o el objetivo se mantiene fuera de alcance
	if dist > LOSE_DISTANCE then
		if mob.OutOfReach == 0 then
			mob.OutOfReach = now
		end
	else
		mob.OutOfReach = 0
	end
	local leash = if now - (mob.LastHurtAt or -100) < HURT_WINDOW then LEASH_RANGE_HURT else LEASH_RANGE
	if homeDist > leash or (mob.OutOfReach > 0 and now - mob.OutOfReach > LOSE_TARGET_AFTER) then
		startReturn(mob, now)
		return true
	end
	
	-- cueva: con una pared de por medio no ataca; sigue el camino del laberinto hasta volver a verte
	if not canSee(mob.Model, root.Position, troot.Position) then
		hum:MoveTo(chasePoint(mob.Model, root.Position, troot.Position))
		return true
	end
	
	local skill, idx = chooseSkill(mob, dist, now)
	if skill and idx then
		mob.Cooldowns[idx] = now + (skill.Cd or 8)
		mob.Busy = true
		hum:Move(Vector3.zero)
		hum:MoveTo(root.Position)
		local target = mob.Target :: Model
		task.spawn(function()
			MobSkills.Run(mob.Ctx, skill, target)
			if skill.Kind == "Summon" then
				mob.Summons += (skill.Count or 2)
			end
			task.wait(0.25)
			mob.Busy = false
		end)
		return true
	end

	-- ataque básico cuerpo a cuerpo
	if dist <= BASIC_RANGE and now >= mob.BasicReady then
		mob.BasicReady = now + BASIC_COOLDOWN
		mob.Busy = true
		hum:MoveTo(root.Position)
		local target = mob.Target :: Model
		task.spawn(function()
			MobSkills.Run(mob.Ctx, BASIC_SKILL, target)
			task.wait(0.2)
			mob.Busy = false
		end)
		return true
	end

	-- auto-ataque a distancia (mobs de proyectil/línea): disparo básico entre poderes
	local prefDist = preferredDistance(mob)
	if prefDist > BASIC_RANGE and dist > BASIC_RANGE and dist <= math.min(prefDist * 1.8, 40) and now >= mob.BasicReady then
		mob.BasicReady = now + RANGED_COOLDOWN
		mob.Busy = true
		hum:MoveTo(root.Position)
		local target = mob.Target :: Model
		task.spawn(function()
			MobSkills.Run(mob.Ctx, RANGED_BASIC, target)
			task.wait(0.2)
			mob.Busy = false
		end)
		return true
	end

	-- movimiento
	local pref = preferredDistance(mob)
	if dist > pref then
		hum:MoveTo(troot.Position)
	elseif dist < pref * 0.5 and pref > 10 then
		-- retrocede para mantener la distancia, pero solo dentro de su zona: si ya se alejó demasiado de su punto, aguanta y pelea
		-- (así quien ataca cuerpo a cuerpo lo alcanza y el jefe no se reinicia a mitad de pelea)
		local kiteLimit = if mob.Def.Boss then KITE_LIMIT_BOSS else KITE_LIMIT
		local away = (root.Position - troot.Position) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 and homeDist < kiteLimit then
			hum:MoveTo(root.Position + away.Unit * KITE_STEP)
		else
			hum:MoveTo(root.Position)
		end
	else
		hum:MoveTo(root.Position)
	end
	return true
end

return MobBrain
