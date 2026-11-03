--!strict
--[[
    =================================================================================
    SCRIPT: CombatService.luau  (v4 - usa FactionClassesModule + DamageService)
    UBICACIÓN: ServerScriptService.Services.CombatService (ModuleScript/Script de Servidor)
    DESCRIPCIÓN: Ejecuta las habilidades REALES de la clase del jugador.
      Tecla/slot 1 = PrimarySkill, 2 = SecondarySkill (de FactionClassesModule).
      Nombre, daño/curación (BaseValue), cooldown, energía, rango, radio y tiempo de
      casteo salen del módulo; aquí no se inventa ningún poder ni número.

      Comportamiento según SkillType:
        Damage        -> daño al objetivo; si trae AoERadius, daño en área en el impacto
        AoE_Damage    -> daño en área centrada en el objetivo (o a Range si no hay)
        CrowdControl  -> daño + aturdimiento en área
        Healing       -> cura al lanzador (con AoERadius: también aliados cercanos)
        Shield        -> escudo en el atributo "ShieldPoints" del personaje
      Rango >= 25 studs se dibuja como proyectil; menos, como golpe cercano.

      Objetivos válidos: modelos con tag "Targetable".
      El cliente manda (slot, modeloMarcado); el servidor valida todo.
    =================================================================================
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DealDamageEvent = Remotes:WaitForChild("DealDamageEvent") :: RemoteEvent
local CooldownRemote = Remotes:WaitForChild("AbilityCooldown") :: RemoteEvent

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FactionClassesModule = require(Modules:WaitForChild("FactionClassesModule"))
local PlayerClass = require(Modules:WaitForChild("PlayerClass"))

local Services = ServerScriptService:WaitForChild("Services")
local EnergyRegenService = require(Services:WaitForChild("EnergyRegenService"))
local DamageService = require(Services:WaitForChild("DamageService"))
local AutoAttack = require(Services:WaitForChild("AutoAttackService"))
local AttackAnimator = require(Services:WaitForChild("AttackAnimator")) -- v4: todo daño/cura/escudo/stun pasa por aquí

type SkillData = FactionClassesModule.SkillData
type ClassData = FactionClassesModule.ClassData

local TARGET_TAG = "Targetable"

-- Ajustes (valores que NO existen en el módulo de clases)
local PROJECTILE_MIN_RANGE = 25 -- desde este rango el ataque se dibuja como proyectil
local PROJECTILE_SPEED = 120
local STUN_DURATION = 2
local SHIELD_DURATION = 6
-- Balance: el Curador se cura a sí mismo con la mitad (los aliados reciben el valor completo).
-- El Índice de Poder del módulo asume cura a terceros; sin esto el Curador sería inmortal en solitario.
local SELF_HEAL_FACTOR = 0.5

-- DIAGNÓSTICO: imprime en el Output del SERVIDOR por qué se acepta o se rechaza cada habilidad
local DEBUG = true
-- Solo para pruebas: true = no consume energía
local DEBUG_IGNORE_ENERGY = false

local function dbg(msg: string)
	if DEBUG then
		print("[CombatService][DEBUG] " .. msg)
	end
end

local SLOT_ALIASES: { [string]: string } = {
	["1"] = "PrimarySkill",
	["2"] = "SecondarySkill",
	Primary = "PrimarySkill",
	Secondary = "SecondarySkill",
	PrimarySkill = "PrimarySkill",
	SecondarySkill = "SecondarySkill",
}

local FACTION_COLORS: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 200, 60),
	Shinobi = Color3.fromRGB(130, 220, 120),
	Pirate = Color3.fromRGB(80, 170, 255),
	Shinigami = Color3.fromRGB(165, 140, 255),
}

local function skillColor(skill: SkillData, faction: string): Color3
	if skill.SkillType == "Healing" then
		return Color3.fromRGB(80, 230, 120)
	elseif skill.SkillType == "Shield" then
		return Color3.fromRGB(120, 200, 255)
	elseif skill.SkillType == "CrowdControl" then
		return Color3.fromRGB(255, 230, 80)
	end
	return FACTION_COLORS[faction] or Color3.new(1, 1, 1)
end

---------------------------------------------------------------------
-- EFECTOS VISUALES / REACCIÓN
---------------------------------------------------------------------
local function makeFx(shape: Enum.PartType, cf: CFrame, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.Size = size
	p.CFrame = cf
	p.Parent = Workspace
	return p
end

local function fadeFx(p: Part, goalSize: Vector3, life: number)
	TweenService:Create(p, TweenInfo.new(life), { Size = goalSize, Transparency = 1 }):Play()
	Debris:AddItem(p, life + 0.1)
end

local function spawnFloatingText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = position + Vector3.new((math.random() - 0.5) * 4, 0, (math.random() - 0.5) * 4)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(140, 40)
	bb.AlwaysOnTop = true
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 24
	label.Parent = bb

	anchor.Parent = Workspace
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, 7, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

-- Retroceso: físico si no está anclado, animado si está anclado (dummy)
local function recoil(model: Model, root: BasePart, dir: Vector3)
	if not root.Anchored then
		root.AssemblyLinearVelocity = dir * 45 + Vector3.new(0, 20, 0)
		return
	end
	if model:GetAttribute("Recoiling") == true then
		return
	end
	model:SetAttribute("Recoiling", true)

	local homeAttr = model:GetAttribute("HomeCFrame")
	local home: CFrame
	if typeof(homeAttr) == "CFrame" then
		home = homeAttr
	else
		home = model:GetPivot()
		model:SetAttribute("HomeCFrame", home)
	end

	task.spawn(function()
		for i = 1, 4 do
			model:PivotTo(home + dir * (i * 0.8))
			task.wait()
		end
		for i = 3, 0, -1 do
			model:PivotTo(home + dir * (i * 0.8))
			task.wait()
		end
		model:PivotTo(home)
		model:SetAttribute("Recoiling", nil)
	end)
end

local function reactToHit(model: Model, root: BasePart, fromPos: Vector3, damage: number, color: Color3)
	local hl = Instance.new("Highlight")
	hl.FillColor = color
	hl.FillTransparency = 0.25
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.Parent = model
	Debris:AddItem(hl, 0.15)

	local away = Vector3.new(root.Position.X - fromPos.X, 0, root.Position.Z - fromPos.Z)
	local dir = if away.Magnitude > 0.01 then away.Unit else Vector3.new(0, 0, 1)
	recoil(model, root, dir)

	local impact = makeFx(Enum.PartType.Ball, CFrame.new(root.Position), Vector3.new(3, 3, 3), color)
	fadeFx(impact, Vector3.new(10, 10, 10), 0.25)
	spawnFloatingText(root.Position + Vector3.new(0, 6, 0), tostring(math.floor(damage)), color)
end

---------------------------------------------------------------------
-- OBJETIVOS
---------------------------------------------------------------------
type Candidate = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Dist: number, -- distancia horizontal al punto de referencia
}

local function toCandidate(inst: Instance, reference: Vector3): Candidate?
	if not inst:IsA("Model") then
		return nil
	end
	local hum = inst:FindFirstChildOfClass("Humanoid")
	local hrp = inst:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and hrp and hrp:IsA("BasePart") then
		local offset = hrp.Position - reference
		return {
			Model = inst,
			Humanoid = hum,
			Root = hrp,
			Dist = Vector3.new(offset.X, 0, offset.Z).Magnitude,
		}
	end
	return nil
end

-- Objetivo principal: el marcado por el jugador (si está en rango) o el más cercano al frente
local function findPrimaryTarget(origin: Vector3, look: Vector3, range: number, hint: any, selfChar: Model): Candidate?
	if typeof(hint) == "Instance" and hint ~= selfChar and CollectionService:HasTag(hint, TARGET_TAG) then
		local c = toCandidate(hint, origin)
		if c and c.Dist <= range + 3 and math.abs(c.Root.Position.Y - origin.Y) <= 30 then
			return c
		end
	end

	local best: Candidate? = nil
	for _, inst in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if inst ~= selfChar then
			local c = toCandidate(inst, origin)
			if c and c.Dist <= range + 3 and math.abs(c.Root.Position.Y - origin.Y) <= 30 then
				local flat = Vector3.new(c.Root.Position.X - origin.X, 0, c.Root.Position.Z - origin.Z)
				if c.Dist < 0.5 or flat.Unit:Dot(look) >= 0.5 then
					if not best or c.Dist < best.Dist then
						best = c
					end
				end
			end
		end
	end
	return best
end

local function victimsInRadius(center: Vector3, radius: number, selfChar: Model): { Candidate }
	local list: { Candidate } = {}
	for _, inst in ipairs(CollectionService:GetTagged(TARGET_TAG)) do
		if inst ~= selfChar then
			local c = toCandidate(inst, center)
			if c and c.Dist <= radius + 2 and math.abs(c.Root.Position.Y - center.Y) <= 30 then
				table.insert(list, c)
			end
		end
	end
	return list
end

local function flatLook(root: BasePart): Vector3
	local l = root.CFrame.LookVector
	local f = Vector3.new(l.X, 0, l.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function applyStunFx(c: Candidate, duration: number) -- v4: solo el efecto visual; el control lo aplica DamageService
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 240, 80)
	hl.Parent = c.Model
	Debris:AddItem(hl, duration)

end

---------------------------------------------------------------------
-- TIPOS DE HABILIDAD
---------------------------------------------------------------------
local function castOffense(player: Player, skill: SkillData, char: Model, root: BasePart, targetHint: any, color: Color3)
	local origin = root.Position
	local look = flatLook(root)
	local aoe = skill.AoERadius or 0
	local isAoE = aoe > 0

	local primary = findPrimaryTarget(origin, look, skill.Range, targetHint, char)
	if primary then
		local toTarget = Vector3.new(primary.Root.Position.X - origin.X, 0, primary.Root.Position.Z - origin.Z)
		if toTarget.Magnitude > 0.01 then
			look = toTarget.Unit
		end
	end

	local impactPos = if primary then primary.Root.Position else origin + look * skill.Range
	local startPos = origin + look * 3 + Vector3.new(0, 1, 0)

	if skill.Range >= PROJECTILE_MIN_RANGE then
		local travel = math.max(0.05, (impactPos - startPos).Magnitude / PROJECTILE_SPEED)
		local orb = makeFx(Enum.PartType.Ball, CFrame.new(startPos), Vector3.new(4, 4, 4), color)
		orb.Transparency = 0
		TweenService:Create(orb, TweenInfo.new(travel, Enum.EasingStyle.Linear), { Position = impactPos }):Play()
		Debris:AddItem(orb, travel + 0.05)
		task.wait(travel)
	else
		local swing = makeFx(Enum.PartType.Ball, CFrame.new(origin + look * 5), Vector3.new(6, 6, 6), color)
		fadeFx(swing, Vector3.new(11, 11, 11), 0.2)
	end

	-- Impacto
	local burstRadius = if isAoE then aoe else 3
	local burst = makeFx(Enum.PartType.Ball, CFrame.new(impactPos), Vector3.new(3, 3, 3), color)
	fadeFx(burst, Vector3.new(burstRadius * 2, burstRadius * 2, burstRadius * 2), 0.35)

	local victims: { Candidate } = {}
	if isAoE then
		victims = victimsInRadius(impactPos, aoe, char)
	elseif primary and primary.Humanoid.Health > 0 then
		victims = { primary }
	end

	for _, c in ipairs(victims) do
		if c.Humanoid.Health > 0 then
			-- v4: DamageService decide si el golpe es válido (mob, PvP solo en arena, aliados no) y escala por nivel
			local dealt = DamageService.Deal(char, c.Model, skill.BaseValue, {
				Stun = if skill.SkillType == "CrowdControl" then STUN_DURATION else nil,
			})
			if dealt > 0 then
				reactToHit(c.Model, c.Root, origin, dealt, color)
				if skill.SkillType == "CrowdControl" then
					applyStunFx(c, STUN_DURATION)
				end
			end
		end
	end

	dbg(string.format(
		"%s usó '%s' (%s) | objetivo principal: %s | golpeó a %d | daño %d",
		player.Name, skill.Name, skill.SkillType, if primary then primary.Model.Name else "ninguno", #victims, skill.BaseValue
		))
end

local function castHeal(player: Player, skill: SkillData, char: Model, root: BasePart, color: Color3)
	local aoe = skill.AoERadius or 0
	local recipients: { Player } = { player }

	if aoe > 0 then
		local myFaction = player:GetAttribute("Faction")
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				local oc = other.Character
				local orp = oc and oc:FindFirstChild("HumanoidRootPart")
				if orp and orp:IsA("BasePart") and (orp.Position - root.Position).Magnitude <= aoe then
					local otherFaction = other:GetAttribute("Faction")
					if myFaction == nil or otherFaction == nil or myFaction == otherFaction then
						table.insert(recipients, other)
					end
				end
			end
		end
		local ring = makeFx(
			Enum.PartType.Cylinder,
			CFrame.new(root.Position - Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Vector3.new(0.6, 2, 2),
			color
		)
		fadeFx(ring, Vector3.new(0.6, aoe * 2, aoe * 2), 0.5)
	else
		local glow = makeFx(Enum.PartType.Ball, CFrame.new(root.Position), Vector3.new(4, 4, 4), color)
		fadeFx(glow, Vector3.new(9, 9, 9), 0.4)
	end

	for _, target in ipairs(recipients) do
		local tc = target.Character
		local hum = tc and tc:FindFirstChildOfClass("Humanoid")
		local trp = tc and tc:FindFirstChild("HumanoidRootPart")
		if hum and hum.Health > 0 then
			local factor = if target == player then SELF_HEAL_FACTOR else 1
			local amount = DamageService.Heal(player.Character :: Model, tc :: Model, skill.BaseValue * factor)
			if trp and trp:IsA("BasePart") then
				spawnFloatingText(trp.Position + Vector3.new(0, 5, 0), "+" .. math.floor(amount), color)
			end
		end
	end

	dbg(string.format("%s usó '%s' (Healing) | curó a %d jugador(es) por %d", player.Name, skill.Name, #recipients, skill.BaseValue))
end

local function castShield(player: Player, skill: SkillData, char: Model, root: BasePart, color: Color3)
	local shieldPoints = DamageService.AddShield(char, char, skill.BaseValue, SHIELD_DURATION)
	local token = os.clock()

	local bubble = Instance.new("Part")
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(9, 9, 9)
	bubble.Material = Enum.Material.ForceField
	bubble.Color = color
	bubble.Transparency = 0.3
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.Massless = true
	bubble.CastShadow = false
	bubble.CFrame = root.CFrame
	bubble.Parent = char

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = bubble
	weld.Parent = bubble
	Debris:AddItem(bubble, SHIELD_DURATION)

	spawnFloatingText(root.Position + Vector3.new(0, 6, 0), "Escudo " .. math.floor(shieldPoints), color)
	dbg(string.format("%s usó '%s' (Shield) | ShieldPoints=%d por %ds", player.Name, skill.Name, skill.BaseValue, SHIELD_DURATION))
end

local function castSkill(player: Player, class: ClassData, skill: SkillData, char: Model, root: BasePart, targetHint: any)
	local color = skillColor(skill, class.Faction)
	do -- animación según arma/rol (la dibuja el cliente)
		local ranged = skill.Range >= PROJECTILE_MIN_RANGE or skill.SkillType == "Healing" or skill.SkillType == "Shield"
		local style = if skill.SkillType == "Healing" or skill.SkillType == "Shield" then "Cast" else AttackAnimator.StyleFor(player, ranged)
		local total = skill.CastTime + 0.45
		AttackAnimator.Play(char, style, total, math.clamp(skill.CastTime / total, 0.3, 0.8))
	end

	-- Tiempo de casteo del módulo
	if skill.CastTime > 0 then
		local windup = makeFx(Enum.PartType.Ball, CFrame.new(root.Position + flatLook(root) * 3), Vector3.new(1, 1, 1), color)
		fadeFx(windup, Vector3.new(5, 5, 5), skill.CastTime)
		task.wait(skill.CastTime)
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not root:IsDescendantOf(Workspace) then
		return
	end

	if skill.SkillType == "Healing" then
		castHeal(player, skill, char, root, color)
	elseif skill.SkillType == "Shield" then
		castShield(player, skill, char, root, color)
	else
		castOffense(player, skill, char, root, targetHint, color)
	end
end

---------------------------------------------------------------------
-- REMOTE
---------------------------------------------------------------------
local cooldowns: { [Player]: { [string]: number } } = {}

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
end)

local function handleCast(player: Player, skillKey: any, targetHint: any)
	dbg(string.format("Evento recibido de %s | skillKey=%s (%s) | objetivo=%s", player.Name, tostring(skillKey), typeof(skillKey), tostring(targetHint)))

	if typeof(skillKey) ~= "string" and typeof(skillKey) ~= "number" then
		warn("[CombatService] skillKey con tipo inválido: " .. typeof(skillKey))
		return
	end
	local slot: string? = SLOT_ALIASES[tostring(skillKey)]
	if not slot then
		warn("[CombatService] Slot sin definir en FactionClassesModule: '" .. tostring(skillKey) .. "' (el módulo solo tiene Primary=1 y Secondary=2)")
		return
	end

	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		dbg(player.Name .. " sin personaje/Humanoid/HumanoidRootPart válido o está muerto")
		return
	end

	if DamageService.IsSilenced(char) or DamageService.IsStunned(char) then
		return -- silenciado (Tsukuyomi) o aturdido: no puede usar habilidades
	end

	local class = PlayerClass.Get(player)
	local skill = if slot == "PrimarySkill" then class.PrimarySkill else class.SecondarySkill
	local rm = char:GetAttribute("RangeMult") -- Susanoo: +30% de alcance
	local setR, setA = char:GetAttribute("SetRange"), char:GetAttribute("SetRadius") -- bono de set completo (Tirador/Curador: alcance · Mago: radio)
	local rangeMult = (if typeof(rm) == "number" and rm > 1 then rm else 1) * (if typeof(setR) == "number" and setR > 1 then setR else 1)
	local radiusMult = if typeof(setA) == "number" and setA > 1 then setA else 1
	if rangeMult > 1 or radiusMult > 1 then
		skill = table.clone(skill)
		skill.Range = skill.Range * rangeMult
		if skill.AoERadius then
			skill.AoERadius = skill.AoERadius * radiusMult
		end
	end

	-- Cooldown (del módulo)
	local now = os.clock()
	local playerCooldowns = cooldowns[player]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldowns[player] = playerCooldowns
	end
	local last = playerCooldowns[slot] or -math.huge
	if now - last < skill.Cooldown then
		return
	end

	-- Energía (del módulo)
	if not DEBUG_IGNORE_ENERGY and not EnergyRegenService.ConsumeEnergy(player, skill.EnergyCost) then
		warn(string.format("[CombatService] %s: ConsumeEnergy devolvió false para '%s' (costo %d)", player.Name, skill.Name, skill.EnergyCost))
		return
	end
	playerCooldowns[slot] = now
	targetHint = AutoAttack.AimAt(player, targetHint) or targetHint -- gira hacia el objetivo marcado

	dbg(string.format("%s [%s/%s] lanza '%s'", player.Name, class.Faction, class.CharacterName, skill.Name))
	CooldownRemote:FireClient(player, if slot == "PrimarySkill" then 1 else 2, skill.Cooldown) -- el HUD refleja también los poderes lanzados por el Auto-farm
	task.spawn(castSkill, player, class, skill, char, root, targetHint)
end
DealDamageEvent.OnServerEvent:Connect(handleCast)

print("[CombatService] Listo: habilidades tomadas de FactionClassesModule (slots 1 y 2).")

local CombatService = {}
-- Sasuke (Marca de Ejecución): reinicia las recargas de 1 y 2 en el servidor (el HUD se avisa desde AbilityService)
function CombatService.ResetCooldowns(player: Player)
	cooldowns[player] = nil
end
-- API para el Auto-farm
CombatService.Cast = handleCast
function CombatService.Ready(player: Player, slotKey: any): boolean
	local slot = SLOT_ALIASES[tostring(slotKey)]
	if not slot then
		return false
	end
	local class = PlayerClass.Get(player)
	local skill = if slot == "PrimarySkill" then class.PrimarySkill else class.SecondarySkill
	local mine = cooldowns[player]
	if mine and os.clock() - (mine[slot] or -math.huge) < skill.Cooldown then
		return false
	end
	return EnergyRegenService.GetEnergy(player) >= EnergyRegenService.Cost(player, skill.EnergyCost)
end
return CombatService
