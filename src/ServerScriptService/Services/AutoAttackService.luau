--!strict
--[[
    AutoAttackService (ModuleScript) -> ServerScriptService.Services.AutoAttackService
    AUTO-ATAQUE: el ataque principal continuo. Al marcar un objetivo (clic) el personaje lo golpea solo mientras esté en rango,
    sin gastar energía (y recuperando un poco por golpe), mientras tú usas los poderes 1-4 entre medias.
      - Rango y velocidad según el ROL: Tanque/Guerrero/Asesino cuerpo a cuerpo, Tirador/Mago/Curador a distancia.
      - Daño = fracción del daño del poder 1 (PrimarySkill.BaseValue) -> pasa por DamageService (nivel, PvP, aliados, inmunidad).
      - Remote AutoAttack desde el cliente: ("Target", modelo) · ("Clear") · ("Toggle")
      - Atributo de jugador "AutoAttack" (true/false) para el HUD.
    El servidor valida rango, objetivo vivo y velocidad de ataque: el cliente no puede acelerarlo.
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local ClassStats = require(ReplicatedStorage.Modules.ClassStats)
local Net = require(Services.Net)
local DamageService = require(Services.DamageService)
local EnergyRegenService = require(Services.EnergyRegenService)
local AttackAnimator = require(Services.AttackAnimator)

type RoleCfg = { Range: number, Interval: number, Fraction: number, Ranged: boolean }
local ROLES: { [string]: RoleCfg } = {
	-- Interval = segundos entre golpes básicos; Fraction = % del daño del poder 1 por golpe. (El ritmo se subió ~35%; el daño por golpe bajó un poco: el DPS total sube ~20%)
	Tanque = { Range = 9, Interval = 1.0, Fraction = 0.20, Ranged = false },
	Guerrero = { Range = 9, Interval = 0.8, Fraction = 0.19, Ranged = false },
	Asesino = { Range = 8, Interval = 0.55, Fraction = 0.14, Ranged = false },
	Tirador = { Range = 42, Interval = 0.7, Fraction = 0.17, Ranged = true },
	Mago = { Range = 34, Interval = 0.95, Fraction = 0.18, Ranged = true },
	Curador = { Range = 28, Interval = 1.05, Fraction = 0.14, Ranged = true },
}
local DEFAULT: RoleCfg = ROLES.Guerrero
local ENERGY_GAIN_PCT = 0.015 -- % de la energía máxima que devuelve cada golpe
local DROP_DISTANCE = 90 -- si el objetivo se aleja tanto, se suelta

type State = { Target: Model?, Enabled: boolean, Next: number }
local states: { [Player]: State } = {}

local AutoAttack = {}

-- ObjectValue "CombatTarget" en el Player: el cliente lo lee para girar al personaje hacia su objetivo
local function setTargetValue(player: Player, m: Model?)
	local found = player:FindFirstChild("CombatTarget")
	local v: ObjectValue
	if found and found:IsA("ObjectValue") then
		v = found
	else
		v = Instance.new("ObjectValue")
		v.Name = "CombatTarget"
		v.Parent = player
	end
	v.Value = m
end

local function setFlag(player: Player, st: State)
	player:SetAttribute("AutoAttack", st.Enabled and st.Target ~= nil)
	setTargetValue(player, st.Target)
end

local AIM_MAX = 120 -- más lejos que esto no se gira hacia el objetivo

-- Gira (solo en el plano) al personaje de la raíz hacia un punto
local function faceTowards(root: BasePart, point: Vector3)
	local flat = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
	local pl = Players:GetPlayerFromCharacter(root.Parent)
	if pl and pl:GetAttribute("AutoFarm") == true then
		return -- el Auto-farm camina: girar desde el servidor lo haría rebotar hacia atrás (el cliente ya mira al objetivo)
	end
	if flat.Magnitude > 0.5 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	end
end

local function validTarget(player: Player, m: Model): boolean
	if not m.Parent or not CollectionService:HasTag(m, "Targetable") then
		return false
	end
	if m == player.Character then
		return false
	end
	local busy = m:GetAttribute("HallBusyBy") -- maniquí de entrenamiento ocupado por otro jugador
	if typeof(busy) == "string" and busy ~= player.Name then
		return false
	end
	local other = Players:GetPlayerFromCharacter(m)
	if other and other:GetAttribute("Faction") == player:GetAttribute("Faction") then
		return false -- aliados no
	end
	return true
end

-- API: alcance del auto-ataque de este jugador (según su rol y modificadores)
function AutoAttack.RangeFor(player: Player): number
	local class = PlayerClass.Get(player)
	local cfg = ROLES[class.Role] or DEFAULT
	local char = player.Character
	local rm = if char then char:GetAttribute("RangeMult") else nil
	local setR = if char then char:GetAttribute("SetRange") else nil
	return cfg.Range * (if typeof(rm) == "number" then rm else 1) * (if typeof(setR) == "number" then setR else 1)
end

-- API: fija (o limpia con nil) el objetivo del auto-ataque, como si el jugador hubiera hecho clic
function AutoAttack.SetTarget(player: Player, m: Model?)
	local st = states[player]
	if not st then
		return
	end
	if m then
		if validTarget(player, m) then
			st.Target = m
			st.Enabled = true
		end
	else
		st.Target = nil
	end
	setFlag(player, st)
end

-- API: objetivo actual del auto-ataque (o nil)
function AutoAttack.GetTarget(player: Player): Model?
	local st = states[player]
	local t = if st then st.Target else nil
	if t and t.Parent then
		return t
	end
	return nil
end

-- API para habilidades: elige el objetivo (el que manda el cliente si es válido; si no, el del auto-ataque),
-- gira al jugador hacia él y lo devuelve. Así los poderes van al objetivo y no hacia donde mira la cámara.
function AutoAttack.AimAt(player: Player, hint: any): Model?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not root or not root:IsA("BasePart") then
		return nil
	end
	local target: Model? = nil
	if typeof(hint) == "Instance" and hint:IsA("Model") and hint ~= char and hint.Parent and CollectionService:HasTag(hint, "Targetable") then
		target = hint
	else
		target = AutoAttack.GetTarget(player)
	end
	if not target then
		return nil
	end
	local tRoot = target:FindFirstChild("HumanoidRootPart")
	local tHum = target:FindFirstChildOfClass("Humanoid")
	if not (tRoot and tRoot:IsA("BasePart") and tHum and tHum.Health > 0) then
		return nil
	end
	if (tRoot.Position - root.Position).Magnitude > AIM_MAX then
		return target
	end
	faceTowards(root, tRoot.Position)
	return target
end

Net.Get("AutoAttack").OnServerEvent:Connect(function(player: Player, action: any, model: any)
	local st = states[player]
	if not st then
		return
	end
	if action == "Target" and typeof(model) == "Instance" and model:IsA("Model") and validTarget(player, model) then
		st.Target = model
		st.Enabled = true
	elseif action == "Clear" then
		st.Target = nil
	elseif action == "Toggle" then
		st.Enabled = true -- el auto-ataque ya no se pausa: siempre sigue al objetivo marcado
	end
	setFlag(player, st)
end)

local function legacyFx(from: Vector3, to: Vector3, ranged: boolean, color: Color3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	if ranged then
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(1.4, 1.4, 1.4)
		p.Position = from
		p.Parent = workspace
		TweenService:Create(p, TweenInfo.new(0.15, Enum.EasingStyle.Linear), { Position = to }):Play()
		Debris:AddItem(p, 0.2)
	else
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(2, 2, 2)
		p.Position = to
		p.Parent = workspace
		TweenService:Create(p, TweenInfo.new(0.2), { Size = Vector3.new(5, 5, 5), Transparency = 1 }):Play()
		Debris:AddItem(p, 0.25)
	end
end

-- EFECTOS DEL ATAQUE BÁSICO SEGÚN EL ARMA (estilo de animación): arco = flecha, pistola = bala, báculo = bola de poder,
-- espada = tajo, daga = doble tajo rápido, hacha = golpe pesado con onda, puños = golpe con onda.
local function fxPart(size: Vector3, color: Color3, cf: CFrame, neon: boolean, ball: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	if ball then
		p.Shape = Enum.PartType.Ball
	end
	p.Size = size
	p.CFrame = cf
	return p
end

local function fadeOut(p: Part, life: number, goal: { [string]: any })
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(p, life + 0.05)
end

local function spark(at: Vector3, color: Color3, size: number)
	local s = fxPart(Vector3.one * size * 0.5, color:Lerp(Color3.new(1, 1, 1), 0.6), CFrame.new(at), true, true)
	fadeOut(s, 0.18, { Size = Vector3.one * size * 1.6, Transparency = 1 })
end

local function ring(at: Vector3, color: Color3, diameter: number)
	local r = fxPart(Vector3.new(0.15, 1, 1), color, CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2), true)
	r.Shape = Enum.PartType.Cylinder
	r.Transparency = 0.2
	fadeOut(r, 0.28, { Size = Vector3.new(0.1, diameter, diameter), Transparency = 1 })
end

local function slashLine(at: Vector3, from: Vector3, color: Color3, length: number, thick: number, tilt: number)
	local face = CFrame.lookAt(at, Vector3.new(from.X, at.Y, from.Z))
	local p = fxPart(Vector3.new(thick, length, thick * 0.5), color:Lerp(Color3.new(1, 1, 1), 0.55), face * CFrame.Angles(0, 0, math.rad(tilt)), true)
	p.Transparency = 0.05
	fadeOut(p, 0.2, { Size = Vector3.new(thick * 0.3, length * 1.5, thick * 0.15), Transparency = 1 })
end

local function arrowFx(from: Vector3, to: Vector3, color: Color3)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 0.5 then
		return
	end
	local look = dir.Unit
	local m = Instance.new("Model")
	m.Name = "ArrowFx"
	local shaft = fxPart(Vector3.new(0.14, 0.14, 2.4), Color3.fromRGB(205, 176, 128), CFrame.new(), false)
	local tip = fxPart(Vector3.new(0.22, 0.22, 0.55), Color3.fromRGB(225, 228, 238), CFrame.new(0, 0, -1.45), false)
	local f1 = fxPart(Vector3.new(0.5, 0.04, 0.55), color, CFrame.new(0, 0, 0.95), true)
	local f2 = fxPart(Vector3.new(0.04, 0.5, 0.55), color, CFrame.new(0, 0, 0.95), true)
	for _, part in ipairs({ shaft, tip, f1, f2 }) do
		part.Parent = m
	end
	m.PrimaryPart = shaft
	m.Parent = workspace
	m:PivotTo(CFrame.lookAt(from, from + look))
	local dur = math.clamp(dist / 110, 0.08, 0.4)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local a = math.min(1, (os.clock() - t0) / dur)
		if not m.Parent then
			conn:Disconnect()
			return
		end
		local pos = from:Lerp(to, a)
		m:PivotTo(CFrame.lookAt(pos, pos + look))
		if a >= 1 then
			conn:Disconnect()
			m:Destroy()
			spark(to, color, 1.1)
		end
	end)
end

local function weaponFx(style: string?, from: Vector3, to: Vector3, ranged: boolean, color: Color3)
	local dir = (to - from)
	local fwd = if dir.Magnitude > 0.1 then dir.Unit else Vector3.new(0, 0, -1)
	local muzzle = from + fwd * 1.8
	if style == "Bow" then
		arrowFx(muzzle, to, color)
	elseif style == "Shoot" then
		local mid = (muzzle + to) / 2
		local len = (to - muzzle).Magnitude
		local tracer = fxPart(Vector3.new(0.12, 0.12, len), Color3.fromRGB(255, 236, 160), CFrame.lookAt(mid, to), true)
		fadeOut(tracer, 0.12, { Transparency = 1, Size = Vector3.new(0.02, 0.02, len) })
		spark(muzzle, Color3.fromRGB(255, 220, 120), 1.2)
		spark(to, Color3.fromRGB(255, 220, 120), 0.9)
	elseif style == "Slash" then
		slashLine(to, from, color, 4, 0.34, 35)
		spark(to, color, 1.4)
	elseif style == "Stab" then
		slashLine(to, from, color, 2.6, 0.2, 40)
		task.delay(0.05, function()
			slashLine(to, from, color, 2.6, 0.2, -40)
		end)
		spark(to, color, 1)
	elseif style == "Slam" then
		slashLine(to, from, color, 5, 0.55, 0)
		ring(to - Vector3.new(0, 2.6, 0), color, 8)
		spark(to, color, 1.8)
	elseif style == "Punch" then
		spark(to, color, 1.8)
		ring(to - Vector3.new(0, 1, 0), color, 5)
	else
		legacyFx(from, to, ranged, color) -- báculo y resto: bola de poder
	end
end

local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 190, 70),
	Shinobi = Color3.fromRGB(130, 220, 120),
	Pirate = Color3.fromRGB(110, 180, 245),
	Shinigami = Color3.fromRGB(180, 160, 255),
}

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.1 then
		return
	end
	acc = 0
	local now = os.clock()
	for player, st in pairs(states) do
		local target = st.Target
		if target and st.Enabled then
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local tHum = target:FindFirstChildOfClass("Humanoid")
			local tRoot = target:FindFirstChild("HumanoidRootPart")
			if not (char and hum and hum.Health > 0 and root and root:IsA("BasePart") and tHum and tHum.Health > 0 and tRoot and tRoot:IsA("BasePart") and target.Parent) then
				st.Target = nil
				setFlag(player, st)
			else
				local hr = target:GetAttribute("HitRadius")
				local dist = math.max(0, (tRoot.Position - root.Position).Magnitude - (if typeof(hr) == "number" then hr else 0))
				local class = PlayerClass.Get(player)
				local cfg = ROLES[class.Role] or DEFAULT
				if dist > DROP_DISTANCE then
					st.Target = nil
					setFlag(player, st)
				elseif dist <= cfg.Range * ((char:GetAttribute("RangeMult") :: number?) or 1) * ((char:GetAttribute("SetRange") :: number?) or 1) and now >= st.Next and not DamageService.IsStunned(char) and not DamageService.IsSilenced(char) and not target:GetAttribute("Immune") then
					local spd = char:GetAttribute("AtkSpeed") -- (futuro: buffs/equipo de velocidad de ataque; 1 = normal)
					st.Next = now + cfg.Interval / ((if typeof(spd) == "number" and spd > 0.2 then spd else 1) * ClassStats.AttackSpeed(class.Role)) -- Destreza
					faceTowards(root, tRoot.Position)
					local animStyle = AttackAnimator.StyleFor(player, cfg.Ranged)
					AttackAnimator.Play(char, animStyle, math.min(cfg.Interval * 0.8, 0.55), 0.4)
					local dealt = DamageService.Deal(char, target, class.PrimarySkill.BaseValue * cfg.Fraction, nil)
					if dealt > 0 then
						local max = select(2, EnergyRegenService.GetEnergy(player))
						EnergyRegenService.Gain(player, max * ENERGY_GAIN_PCT)
						weaponFx(animStyle, root.Position + Vector3.new(0, 1, 0), tRoot.Position, cfg.Ranged, FACTION_COLOR[class.Faction] or Color3.new(1, 1, 1))
					end
				end
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(p)
	states[p] = { Target = nil, Enabled = true, Next = 0 }
	p:SetAttribute("AutoAttack", false)
end)
for _, p in ipairs(Players:GetPlayers()) do
	states[p] = states[p] or { Target = nil, Enabled = true, Next = 0 }
end
Players.PlayerRemoving:Connect(function(p)
	states[p] = nil
end)

return AutoAttack
