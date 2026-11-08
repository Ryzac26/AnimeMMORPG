--!strict
--[[
    CharacterAnimClient (LocalScript) -> StarterPlayer.StarterPlayerScripts.CharacterAnimClient
    Animación PROCEDURAL fluida (en el cliente, 60 fps) de rigs R6:
      - MOBS: caminar/correr (balanceo de brazos y piernas según su velocidad real) + respiración parada + ataques.
      - TODOS los personajes (tú y otros jugadores): animación de ATAQUE superpuesta cuando el servidor lo ordena.
    El servidor solo publica atributos del modelo (AnimStyle, AnimAt, AnimLen, AnimStrike, AnimAlt); ver AttackAnimator.
    Ángulos de hombros/caderas = DesiredAngle R6 (hombro derecho + = brazo adelante/arriba; izquierdo - = adelante/arriba).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local MAX_DIST = 220

-- R6: hombros/caderas giran en Z (derecho +adelante, izquierdo -adelante). R15: giran en X (+adelante en ambos) y hay codos, rodillas y cintura.
-- (en los cuerpos R15 nuevos las articulaciones son AnimationConstraint; en R6 son Motor6D: ambas tienen .Transform)
type Joint = any
type Joints = { R15: boolean, RS: Joint, LS: Joint, RH: Joint, LH: Joint, Root: BasePart, RE: Joint?, LE: Joint?, RK: Joint?, LK: Joint?, Waist: Joint? }
type Pose = { RS: { number }?, LS: { number }?, RH: { number }?, LH: { number }? } -- {preparación, golpe}

-- {preparación (brazo levantado/atrás), golpe}. Las alternadas (Punch/Stab) usan la mano principal y la espejan.
local STYLES: { [string]: { Pose: Pose, Alt: boolean?, Hold: Pose? } } = {
	Slash = { Pose = { RS = { 2.7, 0.9 }, LS = { -0.5, -0.2 }, RH = { 0.35, -0.3 }, LH = { -0.35, 0.3 } } },
	Slam = { Pose = { RS = { 3.1, 0.5 }, LS = { -3.1, -0.5 }, RH = { 0.3, -0.35 }, LH = { -0.3, 0.35 } } },
	Stab = { Alt = true, Pose = { RS = { -0.5, 1.55 }, LS = { -0.6, -0.9 }, RH = { 0.3, -0.35 }, LH = { -0.3, 0.35 } } },
	Punch = { Alt = true, Pose = { RS = { -0.7, 1.5 }, LS = { -1.1, -1.0 }, RH = { 0.3, -0.4 }, LH = { -0.3, 0.4 } } },
	Cast = { Pose = { RS = { 2.5, 1.45 }, LS = { -2.5, -1.45 }, RH = { 0.15, 0.15 }, LH = { -0.15, -0.15 } } },
	Power = { Pose = { RS = { 2.1, 2.1 }, LS = { -2.1, -2.1 }, RH = { 0.25, 0.25 }, LH = { -0.25, -0.25 } } },
	Shoot = { Pose = { RS = { 1.2, 1.55 }, LS = { -0.4, -0.5 }, RH = { 0.2, 0.2 }, LH = { -0.2, -0.2 } } },
	Throw = { Pose = { RS = { 2.7, 0.3 }, LS = { -0.8, -0.3 }, RH = { 0.3, -0.3 }, LH = { -0.3, 0.3 } } },
	Bow = { Pose = { RS = { 1.55, 0.35 }, LS = { -1.55, -1.55 }, RH = { 0.15, 0.15 }, LH = { -0.15, -0.15 } } },
}

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ángulo en el instante p (0..1) del ataque: preparación -> golpe -> recuperación
local function atkAngle(pair: { number }, p: number, strike: number): number
	local rest = 0
	if p < strike then
		return lerp(rest, pair[1], ease(p / strike))
	elseif p < strike + 0.22 then
		return lerp(pair[1], pair[2], ease((p - strike) / 0.22))
	end
	local r = math.clamp((p - strike - 0.22) / math.max(0.01, 1 - strike - 0.22), 0, 1)
	return lerp(pair[2], rest, ease(r))
end

local jointCache: { [Model]: Joints? } = setmetatable({}, { __mode = "k" }) :: any

local function motorIn(m: Model, part: string, joint: string): Joint?
	local p = m:FindFirstChild(part)
	local j = if p then p:FindFirstChild(joint) else nil
	return if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then j else nil
end

local function jointsOf(m: Model): Joints?
	local c = jointCache[m]
	if c ~= nil then
		return c
	end
	local root = m:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local torso = m:FindFirstChild("Torso")
	if torso then -- R6
		local rs, ls, rh, lh = torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder"), torso:FindFirstChild("Right Hip"), torso:FindFirstChild("Left Hip")
		if rs and ls and rh and lh and rs:IsA("Motor6D") and ls:IsA("Motor6D") and rh:IsA("Motor6D") and lh:IsA("Motor6D") then
			local j: Joints = { R15 = false, RS = rs, LS = ls, RH = rh, LH = lh, Root = root }
			jointCache[m] = j
			return j
		end
		return nil
	end
	local rs, ls = motorIn(m, "RightUpperArm", "RightShoulder"), motorIn(m, "LeftUpperArm", "LeftShoulder")
	local rh, lh = motorIn(m, "RightUpperLeg", "RightHip"), motorIn(m, "LeftUpperLeg", "LeftHip")
	if rs and ls and rh and lh then -- R15
		local j: Joints = {
			R15 = true, RS = rs, LS = ls, RH = rh, LH = lh, Root = root,
			RE = motorIn(m, "RightLowerArm", "RightElbow"), LE = motorIn(m, "LeftLowerArm", "LeftElbow"),
			RK = motorIn(m, "RightLowerLeg", "RightKnee"), LK = motorIn(m, "LeftLowerLeg", "LeftKnee"),
			Waist = motorIn(m, "UpperTorso", "Waist"),
		}
		jointCache[m] = j
		return j
	end
	return nil
end

-- Ángulos en convención R6: RS/RH + = adelante; LS/LH - = adelante. En R15 se convierte (izquierdos al revés) y giran en X.
local function setArm(j: Joints, left: boolean, a: number)
	if j.R15 then
		local fwd = if left then -a else a
		local shoulder = if left then j.LS else j.RS
		shoulder.Transform = CFrame.Angles(fwd, 0, 0)
		local elbow = if left then j.LE else j.RE
		if elbow then
			elbow.Transform = CFrame.Angles(math.clamp(fwd, 0, 3) * 0.55, 0, 0) -- el antebrazo se dobla al levantar el brazo
		end
	else
		local shoulder = if left then j.LS else j.RS
		shoulder.Transform = CFrame.Angles(0, 0, a)
	end
end

local function setLeg(j: Joints, left: boolean, a: number)
	if j.R15 then
		local fwd = if left then -a else a
		local hip = if left then j.LH else j.RH
		hip.Transform = CFrame.Angles(fwd, 0, 0)
		local knee = if left then j.LK else j.RK
		if knee then
			knee.Transform = CFrame.Angles(math.min(0, fwd) * 1.1, 0, 0) -- rodilla doblada cuando la pierna va atrás
		end
	else
		local hip = if left then j.LH else j.RH
		hip.Transform = CFrame.Angles(0, 0, a)
	end
end

-- ¿ataque en curso? devuelve estilo, progreso, strike, alterna
local function attackOf(m: Model): (string?, number, number, boolean)
	local style = m:GetAttribute("AnimStyle")
	local at = m:GetAttribute("AnimAt")
	local len = m:GetAttribute("AnimLen")
	if typeof(style) == "string" and typeof(at) == "number" and typeof(len) == "number" then
		local age = Workspace:GetServerTimeNow() - at
		if age >= -0.05 and age < len then
			local strike = m:GetAttribute("AnimStrike")
			return style, math.clamp(age / len, 0, 1), if typeof(strike) == "number" then strike else 0.45, m:GetAttribute("AnimAlt") == true
		end
	end
	return nil, 0, 0.45, false
end

local phases: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local lastPos: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local DEBUG = true -- imprime un diagnóstico en el Output del cliente durante los primeros segundos

local function applyAttack(j: Joints, style: string, p: number, strike: number, alt: boolean)
	local def = STYLES[style]
	if not def then
		return
	end
	local pose = def.Pose
	local mirror = def.Alt and alt
	local rs, ls = pose.RS, pose.LS
	local rh, lh = pose.RH, pose.LH
	if mirror then
		rs, ls = ls, rs
		rh, lh = lh, rh
	end
	if rs then
		setArm(j, false, atkAngle(if mirror then { -(rs :: { number })[1], -(rs :: { number })[2] } else rs, p, strike))
	end
	if ls then
		setArm(j, true, atkAngle(if mirror then { -(ls :: { number })[1], -(ls :: { number })[2] } else ls, p, strike))
	end
	if rh then
		setLeg(j, false, atkAngle(if mirror then { -(rh :: { number })[1], -(rh :: { number })[2] } else rh, p, strike))
	end
	if lh then
		setLeg(j, true, atkAngle(if mirror then { -(lh :: { number })[1], -(lh :: { number })[2] } else lh, p, strike))
	end
end

local function applyLocomotion(m: Model, j: Joints, dt: number, now: number)
	local v = j.Root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local prev = lastPos[m]
	local pos = j.Root.Position
	lastPos[m] = pos
	if prev and dt > 0 then
		local d = Vector3.new(pos.X - prev.X, 0, pos.Z - prev.Z).Magnitude / dt
		if d < 80 and d > speed then
			speed = d -- la posición replicada manda si la velocidad llega en 0
		end
	end
	local amp = math.clamp(speed / 12, 0, 1)
	local ph = (phases[m] or math.random() * 6) + dt * (2.5 + speed * 0.5) * (if amp > 0.05 then 1 else 0.15)
	phases[m] = ph
	local sway = math.sin(now * 1.8 + ph * 0.0) * 0.05 * (1 - amp) -- respiración al estar parado
	local arms = math.sin(ph) * 1.15 * amp
	local legs = math.sin(ph) * 0.95 * amp
	if j.Waist then
		j.Waist.Transform = CFrame.Angles(-0.14 * amp, 0, 0) -- inclinación al correr (R15)
	end
	setArm(j, false, arms + sway)
	setArm(j, true, arms - sway)
	setLeg(j, false, -legs)
	setLeg(j, true, -legs)
end

-- POSTURA DE ARMA EN LA MANO (jugadores): mientras no se ataca, los brazos que sostienen arma/arco/báculo quedan en la postura que publica
-- AttackAnimator (atributos HoldR / HoldL), así el arma no apunta al frente a ras de cadera. Se suaviza al volver de un ataque.
local holdState: { [Model]: { R: number, L: number } } = setmetatable({}, { __mode = "k" }) :: any

local function applyHold(m: Model, j: Joints, dt: number, hr: any, hl: any)
	local st = holdState[m]
	if not st then
		st = { R = 0, L = 0 }
		holdState[m] = st
	end
	local k = math.min(1, dt * 10)
	if typeof(hr) == "number" then
		st.R += (hr - st.R) * k
		setArm(j, false, st.R)
	end
	if typeof(hl) == "number" then
		st.L += (hl - st.L) * k
		setArm(j, true, st.L)
	end
end

local cam = Workspace.CurrentCamera
local diagUntil = os.clock() + 45
local diagNext = 0

local function diagnose(camPos: Vector3)
	if not DEBUG or os.clock() > diagUntil or os.clock() < diagNext then
		return
	end
	diagNext = os.clock() + 4
	local best: Model? = nil
	local bestD = math.huge
	local count = 0
	for _, inst in ipairs(CollectionService:GetTagged("Mob")) do
		if inst:IsA("Model") then
			count += 1
			local r = inst:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				local d = (r.Position - camPos).Magnitude
				if d < bestD then
					bestD = d
					best = inst
				end
			end
		end
	end
	if not best then
		print(string.format("[AnimDIAG] mobs con tag 'Mob': %d (ninguno con HumanoidRootPart cerca)", count))
		return
	end
	local m = best :: Model
	local j = jointsOf(m)
	local rig = if m:FindFirstChild("Torso") then "R6" elseif m:FindFirstChild("UpperTorso") then "R15" else "?"
	local rs = if j then j.RS.Transform else nil
	local hum = m:FindFirstChildOfClass("Humanoid")
	print(string.format("[AnimDIAG] mobs=%d | cercano=%s dist=%.0f rig=%s joints=%s vida=%s | RS.Transform=%s | AnimStyle=%s",
		count, m.Name, bestD, rig, tostring(j ~= nil), hum and tostring(math.floor(hum.Health)) or "sin humanoid", tostring(rs and rs.Rotation or "n/a"), tostring(m:GetAttribute("AnimStyle"))))
	if not j and rig == "R15" then
		local rua = m:FindFirstChild("RightUpperArm")
		print("[AnimDIAG] RightUpperArm existe=" .. tostring(rua ~= nil) .. " hijos=" .. (if rua then table.concat((function() local t = {} for _, c in ipairs(rua:GetChildren()) do table.insert(t, c.Name .. ":" .. c.ClassName) end return t end)(), ",") else "-"))
	end
end

local function step(dt: number)
	cam = Workspace.CurrentCamera or cam
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local now = os.clock()
	diagnose(camPos)

	-- mobs: locomoción + ataques
	for _, inst in ipairs(CollectionService:GetTagged("Mob")) do
		if inst:IsA("Model") and inst.Parent then
			local j = jointsOf(inst)
			local hum = inst:FindFirstChildOfClass("Humanoid")
			if j and hum and hum.Health > 0 and (j.Root.Position - camPos).Magnitude <= MAX_DIST then
				local style, p, strike, alt = attackOf(inst)
				if style then
					applyAttack(j, style, p, strike, alt)
				else
					applyLocomotion(inst, j, dt, now)
				end
			end
		end
	end

	-- jugadores: solo ataques (el caminar lo hace el Animate de Roblox)
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		if c then
			local style, p, strike, alt = attackOf(c)
			if style then
				local j = jointsOf(c)
				if j then
					holdState[c] = nil
					applyAttack(j, style, p, strike, alt)
				end
			else
				local hr, hl = c:GetAttribute("HoldR"), c:GetAttribute("HoldL")
				if typeof(hr) == "number" or typeof(hl) == "number" then
					local j = jointsOf(c)
					local hum = c:FindFirstChildOfClass("Humanoid")
					if j and hum and hum.Health > 0 and not hum.Sit and (j.Root.Position - camPos).Magnitude <= MAX_DIST then
						applyHold(c, j, dt, hr, hl)
					end
				else
					holdState[c] = nil
				end
			end
		end
	end
end

-- prioridad "Last": se aplica después del Animator de Roblox y sobrescribe sus Transform mientras dura el ataque
RunService:BindToRenderStep("CharacterAnimClient", Enum.RenderPriority.Last.Value, step)
print("[CharacterAnimClient] Animación de mobs y ataques lista.")
