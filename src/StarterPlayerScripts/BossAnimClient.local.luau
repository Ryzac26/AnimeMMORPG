--!strict
--[[
    BossAnimClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BossAnimClient
    Movimiento POR CÓDIGO del jefe mundial con modelo propio (BossBeaconService marca el modelo con BossRig = true).
    Las animaciones del modelo original no cargan (son de otro creador), así que se mueven sus Motor6D cada fotograma:
      - Reposo: respiración, cola que ondula, cuello que mira alrededor, mandíbula que se abre a veces, bigotes y patas que se balancean.
      - Giro: mira al jugador que indica el servidor (provocación > tanque > más cercano), girando todo el modelo en el cliente.
      - Mordida: el servidor escribe AttackAt (hora del servidor); el jefe echa atrás el cuello, abre la boca, se lanza y vuelve.
    Cada rotación se calcula en el eje del MUNDO (arriba / derecha / adelante del jefe) convertido al marco de cada articulación,
    así funciona aunque los huesos del modelo tengan ejes raros.
    Huesos esperados (Abomination): Torso1-3, Neck, Head, LowerHeadRot (mandíbula), Tail1-4, Whisker.L/R, patas FrontLeg*/BackLeg*. Los que falten se ignoran.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BITE_DURATION = 1.1
local TURN_SPEED = 1.4 -- rad/s con que el jefe gira hacia su objetivo (BossTarget = UserId, lo elige BossService)

type JointInfo = { Joint: Motor6D, Up: Vector3, Right: Vector3, Fwd: Vector3 }

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function setup(model: Model)
	local head = model:WaitForChild("Head", 15)
	local tail1 = model:WaitForChild("Tail1", 15)
	if not head or not tail1 or not head:IsA("BasePart") or not tail1:IsA("BasePart") then
		return
	end
	task.wait(0.5) -- que termine de colocarse (el servidor lo apoya en el piso al crearlo)

	-- dirección "adelante" del jefe: de la cola a la cabeza, en horizontal
	local fwd = Vector3.new(head.Position.X - tail1.Position.X, 0, head.Position.Z - tail1.Position.Z)
	if fwd.Magnitude < 0.01 then
		fwd = Vector3.new(0, 0, -1)
	end
	fwd = fwd.Unit
	local up = Vector3.yAxis
	local right = fwd:Cross(up) -- (adelante x arriba) = derecha

	local a0 = math.atan2(-fwd.X, -fwd.Z) -- ángulo del frente inicial (CFrame.Angles(0, a, 0) * -Z = (-sin a, -cos a))
	local pivotCF0 = model:GetPivot()
	local yaw = 0

	local joints: { [string]: JointInfo } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			local frame = d.Part0.CFrame * d.C0 -- marco de la articulación en reposo
			joints[d.Name] = {
				Joint = d,
				Up = frame:VectorToObjectSpace(up),
				Right = frame:VectorToObjectSpace(right),
				Fwd = frame:VectorToObjectSpace(fwd),
			}
		end
	end
	local length = model:GetAttribute("BossLength")
	local L = if typeof(length) == "number" then length else 170

	-- acumula el movimiento de este fotograma: pitch (+ = nariz arriba), yaw, roll y desplazamiento (arriba, adelante)
	local acc: { [string]: { P: number, Y: number, R: number, Up: number, Fw: number } } = {}
	local function add(name: string, pitch: number?, yaw: number?, roll: number?, lift: number?, fw: number?)
		local a = acc[name]
		if not a then
			a = { P = 0, Y = 0, R = 0, Up = 0, Fw = 0 }
			acc[name] = a
		end
		a.P += pitch or 0
		a.Y += yaw or 0
		a.R += roll or 0
		a.Up += lift or 0
		a.Fw += fw or 0
	end

	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not model.Parent then
			conn:Disconnect()
			return
		end

		-- GIRO hacia el objetivo
		local tid = model:GetAttribute("BossTarget")
		if typeof(tid) == "number" and tid ~= 0 then
			local pl = Players:GetPlayerByUserId(tid)
			local hrp = pl and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local pos = pivotCF0.Position
				local d = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
				if d.Magnitude > 1 then
					local want = math.atan2(-d.X, -d.Z) - a0
					local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
					local step = math.clamp(diff, -TURN_SPEED * dt, TURN_SPEED * dt)
					if math.abs(step) > 1e-4 then
						yaw += step
						model:PivotTo(pivotCF0 * CFrame.Angles(0, yaw, 0))
					end
				end
			end
		end
		local t = os.clock()
		table.clear(acc)

		-- REPOSO ------------------------------------------------------
		local breath = math.sin(t * 1.1)
		add("Torso2", 0.012 * math.sin(t * 0.9 + 1), nil, nil, L * 0.006 * (0.5 + 0.5 * math.sin(t * 0.9))) -- solo sube (nunca se hunde)
		add("Torso1", 0.03 * breath)
		add("Torso3", nil, 0.05 * math.sin(t * 1.2))
		local tailAmp = { 0.16, 0.24, 0.32, 0.40 }
		for i = 1, 4 do
			local ph = t * 1.5 - i * 0.8
			add("Tail" .. i, 0.04 * math.sin(ph + 1.5), tailAmp[i] * math.sin(ph))
		end
		add("Neck", 0.04 * math.sin(t * 0.7), 0.18 * math.sin(t * 0.5))
		add("Head", 0.03 * math.sin(t * 0.6 + 0.5), 0.10 * math.sin(t * 0.5 + 1))
		-- mandíbula: respira entreabierta y cada ~7 s ruge
		local roar = (t % 7) / 7
		local jaw = 0.03 * (0.5 + 0.5 * math.sin(t * 0.8))
		if roar < 0.25 then
			jaw += 0.38 * math.sin(math.pi * roar / 0.25)
		end
		add("LowerHeadRot", -jaw)
		local wh = 0.15 * math.sin(t * 2.2)
		add("Whisker.L", nil, wh)
		add("Whisker.R", nil, -wh)
		local leg = 0.06 * math.sin(t * 0.9)
		add("FrontLegUpper.L", leg)
		add("FrontLegUpper.R", -leg)
		add("BackLegUpper.L", -leg)
		add("BackLegUpper.R", leg)
		add("FrontLegLower.L", -leg * 0.8)
		add("FrontLegLower.R", leg * 0.8)
		add("BackLegLower.L", leg * 0.8)
		add("BackLegLower.R", -leg * 0.8)

		-- MORDIDA -----------------------------------------------------
		local at = model:GetAttribute("AttackAt")
		if typeof(at) == "number" then
			local ph = (Workspace:GetServerTimeNow() - at) / BITE_DURATION
			if ph >= 0 and ph <= 1 then
				local neck, torso, jawOpen, lunge = 0, 0, 0, 0
				if ph < 0.35 then -- echa atrás el cuello y abre la boca
					local w = ease(ph / 0.35)
					neck, torso, jawOpen = 0.40 * w, 0.06 * w, 0.75 * w
				elseif ph < 0.55 then -- se lanza hacia adelante y muerde
					local s = ease((ph - 0.35) / 0.2)
					neck = 0.40 * (1 - s) - 0.50 * s
					torso = 0.06 * (1 - s) - 0.12 * s
					jawOpen = 0.75 * (1 - ease((ph - 0.48) / 0.07))
					lunge = s
				else -- vuelve a su sitio
					local r = ease((ph - 0.55) / 0.45)
					neck, torso, jawOpen, lunge = -0.50 * (1 - r), -0.12 * (1 - r), 0, 1 - r
				end
				add("Neck", neck)
				add("Torso1", torso)
				add("LowerHeadRot", -jawOpen)
				add("Torso2", nil, nil, nil, nil, L * 0.035 * lunge)
			end
		end

		-- aplicar: rotación sobre los ejes del mundo (convertidos al marco de cada articulación) + desplazamiento
		for name, a in pairs(acc) do
			local j = joints[name]
			if j then
				local rot = CFrame.fromAxisAngle(j.Right, a.P) * CFrame.fromAxisAngle(j.Up, a.Y) * CFrame.fromAxisAngle(j.Fwd, a.R)
				local move = j.Up * a.Up + j.Fwd * a.Fw
				j.Joint.Transform = CFrame.new(move) * rot
			end
		end
	end)
end

local function consider(inst: Instance)
	if inst:IsA("Model") and inst.Name == "Maqueta_Jefe" then
		task.spawn(function()
			-- BossRig se escribe antes de colocar el modelo en Workspace, pero se replica con él: se espera por si acaso
			for _ = 1, 40 do
				if inst:GetAttribute("BossRig") == true then
					setup(inst)
					return
				end
				if not inst.Parent then
					return
				end
				task.wait(0.25)
			end
		end)
	end
end

Workspace.ChildAdded:Connect(consider)
for _, c in ipairs(Workspace:GetChildren()) do
	consider(c)
end
