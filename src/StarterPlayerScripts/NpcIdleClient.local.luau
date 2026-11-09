--!strict
--[[
    NpcIdleClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > NpcIdleClient
    Da vida a los NPC de las ciudades (modelos con la etiqueta "NpcRig", hechos por NpcBuilder; cada pieza trae el atributo "Grp"):
      · respiran (sube y baja el torso un poco), balancean los brazos y la cabeza se mueve suavemente;
      · si te acercas (menos de 22 studs) giran la cabeza y la mirada hacia ti.
    Solo anima los que están cerca de la cámara. Todo es local: no toca al servidor. No lleva pantalla (no va en RELOAD).
    VIDA DE LA CIUDAD: si el modelo trae el atributo "Act" (lo pone CityLifeService) hace una escena en bucle:
        Hammer = forja (al golpear salta chispa) · Spar = combate de entrenamiento en pareja · Mix = remueve un caldero
        Hold = revisa un frasco · Chat = charla con gestos (copa en la mano). Atributos opcionales: Phase (0..1), Period (s).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local VIEW = 80
local LOOK_RANGE = 22

type Piece = { Part: BasePart, Rel: CFrame, Grp: string }
type Fx = { Part: Part, Emitter: ParticleEmitter, Light: PointLight }
type Rig = { Model: Model, Root: BasePart, Pieces: { Piece }, Seed: number, Yaw: number, Pitch: number, Count: number, Check: number, Act: string?, BiasL: number, BiasR: number, Phase: number, Period: number, PrevU: number, Fx: { [string]: Fx } }
local rigs: { [Model]: Rig } = {}

local function collect(model: Model, rig: Rig)
	local root = rig.Root
	rig.Pieces = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			table.insert(rig.Pieces, { Part = d, Rel = root.CFrame:ToObjectSpace(d.CFrame), Grp = tostring(d:GetAttribute("Grp") or "Static") })
		end
	end
	rig.Count = #rig.Pieces
end

local function add(model: Instance)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10)
		if not root or not root:IsA("BasePart") or not model.Parent then
			return
		end
		task.wait(0.5) -- deja que lleguen las piezas
		local act = model:GetAttribute("Act")
		local rig: Rig = {
			Model = model, Root = root, Pieces = {}, Seed = math.random() * 10, Yaw = 0, Pitch = 0, Count = 0, Check = 0,
			Act = if typeof(act) == "string" then act else nil,
			BiasL = (model:GetAttribute("BiasL") :: number?) or 0,
			BiasR = (model:GetAttribute("BiasR") :: number?) or 0,
			Phase = (model:GetAttribute("Phase") :: number?) or 0,
			Period = (model:GetAttribute("Period") :: number?) or 1.2,
			PrevU = 0, Fx = {},
		}
		collect(model, rig)
		rigs[model] = rig
	end)
end

CollectionService:GetInstanceAddedSignal("NpcRig"):Connect(add)
CollectionService:GetInstanceRemovedSignal("NpcRig"):Connect(function(m)
	local rig = rigs[m :: Model]
	if rig then
		for _, fx in pairs(rig.Fx) do
			fx.Part:Destroy()
		end
	end
	rigs[m :: Model] = nil
end)
for _, m in ipairs(CollectionService:GetTagged("NpcRig")) do
	add(m)
end

-- ===== ESCENAS DE LA CIUDAD (Act) =====
local fxFolder = Instance.new("Folder")
fxFolder.Name = "CityLifeFx"
fxFolder.Parent = Workspace

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- sube y baja entre a y c (pico en b), 0 fuera
local function bump(u: number, a: number, b: number, c: number): number
	if u <= a or u >= c then
		return 0
	end
	if u < b then
		return smooth((u - a) / (b - a))
	end
	return 1 - smooth((u - b) / (c - b))
end

local function burst(rig: Rig, kind: string, offset: Vector3)
	local fx = rig.Fx[kind]
	if not fx then
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Transparency = 1
		p.Size = Vector3.new(0.3, 0.3, 0.3)
		p.Parent = fxFolder
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.LightEmission = 1
		e.Transparency = NumberSequence.new(0, 1)
		local l = Instance.new("PointLight")
		l.Brightness = 0
		l.Range = 12
		if kind == "Spark" then
			e.Lifetime = NumberRange.new(0.25, 0.65)
			e.Speed = NumberRange.new(10, 26)
			e.SpreadAngle = Vector2.new(75, 75)
			e.Acceleration = Vector3.new(0, -55, 0)
			e.Size = NumberSequence.new(0.28, 0)
			e.Color = ColorSequence.new(Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 110, 30))
			l.Color = Color3.fromRGB(255, 160, 60)
		else
			e.Lifetime = NumberRange.new(0.18, 0.35)
			e.Speed = NumberRange.new(6, 13)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Acceleration = Vector3.zero
			e.Size = NumberSequence.new(0.55, 0)
			e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 220, 120))
			l.Color = Color3.fromRGB(255, 240, 200)
		end
		e.Parent = p
		l.Parent = p
		fx = { Part = p, Emitter = e, Light = l }
		rig.Fx[kind] = fx
	end
	fx.Part.CFrame = rig.Root.CFrame * CFrame.new(offset)
	fx.Emitter:Emit(if kind == "Spark" then 18 else 8)
	fx.Light.Brightness = 3
	TweenService:Create(fx.Light, TweenInfo.new(0.3), { Brightness = 0 }):Play()
end

-- devuelve brazoI, brazoD, desplazamiento del cuerpo, inclinación extra de cabeza, vaivén de piernas
local function scene(rig: Rig, t: number): (CFrame, CFrame, Vector3, number, number)
	local act = rig.Act
	local s = rig.Seed
	local u = (t / rig.Period + rig.Phase) % 1
	local armL, armR = CFrame.identity, CFrame.identity
	local shift, headAdd, leg = Vector3.zero, 0, 0
	if act == "Hammer" then
		local th
		if u < 0.55 then
			th = 0.75 + (2.2 - 0.75) * smooth(u / 0.55)
		elseif u < 0.68 then
			local k = (u - 0.55) / 0.13
			th = 2.2 + (0.7 - 2.2) * k * k
		else
			th = 0.7 + 0.08 * math.sin((u - 0.68) / 0.32 * math.pi)
		end
		if rig.PrevU < 0.68 and u >= 0.68 and u - rig.PrevU < 0.5 then
			burst(rig, "Spark", Vector3.new(1.5, -0.6, -2.66))
		end
		armR = CFrame.Angles(th, 0, 0)
		armL = CFrame.Angles(0.75 + 0.05 * math.sin(t * 2 + s), 0, 0.12)
		shift = Vector3.new(0, 0, -0.3 * (1 - math.clamp((th - 0.7) / 1.5, 0, 1)))
		headAdd = -0.3
	elseif act == "Spar" then
		local r = bump(u, 0.02, 0.1, 0.2)
		local l = bump(u, 0.26, 0.34, 0.44)
		armR = CFrame.Angles(1.1 + 0.45 * r, 0, -0.45 * (1 - r))
		armL = CFrame.Angles(1.1 + 0.45 * l, 0, 0.45 * (1 - l))
		local ut = (u + 0.5) % 1 -- el rival ataca medio ciclo después
		local flinch = math.max(bump(ut, 0.1, 0.14, 0.22), bump(ut, 0.34, 0.38, 0.46))
		shift = Vector3.new(0, 0, -0.6 * math.max(r, l) + 0.4 * flinch)
		leg = 0.22 * math.sin(t * 5 + rig.Phase * 6.28)
		if (rig.PrevU < 0.1 and u >= 0.1 or rig.PrevU < 0.34 and u >= 0.34) and u - rig.PrevU < 0.2 then
			burst(rig, "Hit", Vector3.new(if u < 0.2 then 1.5 else -1.5, 0.9, -2.35))
		end
	elseif act == "Mix" then
		local w = t * 6.2832 / rig.Period + rig.Phase * 6.28
		armR = CFrame.Angles(0.95 + 0.12 * math.cos(w), 0, 0.25 * math.sin(w))
		armL = CFrame.Angles(0.9, 0, 0.35)
		headAdd = -0.3
	elseif act == "Hold" then
		local w = t * 6.2832 / rig.Period + rig.Phase * 6.28
		armR = CFrame.Angles(1.6 + 0.1 * math.sin(w * 0.5), 0, 0.14 * math.sin(w))
		armL = CFrame.Angles(0.3, 0, 0.1)
		headAdd = 0.12
	elseif act == "Chat" then
		local g = math.max(0, math.sin(t * 0.8 + rig.Phase * 6.28 + s)) ^ 2
		armR = CFrame.Angles(0.45 + 0.8 * g, 0, -0.25 * g)
		armL = CFrame.Angles(1.15, 0, 0.3)
		headAdd = 0.07 * math.sin(t * 2.4 + s) * g
	end
	rig.PrevU = u
	return armL, armR, shift, headAdd, leg
end

local SHOULDER_L = CFrame.new(-1.5, 1, 0)
local SHOULDER_R = CFrame.new(1.5, 1, 0)
local NECK = CFrame.new(0, 1.05, 0)

RunService.RenderStepped:Connect(function(dt: number)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = os.clock()
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for model, rig in pairs(rigs) do
		local root = rig.Root
		if not model.Parent or not root.Parent then
			rigs[model] = nil
			continue
		end
		if (root.Position - camPos).Magnitude > VIEW then
			continue
		end
		-- piezas que llegaron tarde (streaming)
		if t - rig.Check > 1.5 then
			rig.Check = t
			local live = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					live += 1
				end
			end
			if live - 1 ~= rig.Count then
				collect(model, rig)
			end
		end
		local rcf = root.CFrame
		-- ¿a quién mira? (el jugador local si está cerca)
		local targetYaw, targetPitch = 0, 0
		if myRoot and myRoot:IsA("BasePart") then
			local d = myRoot.Position - root.Position
			if d.Magnitude < LOOK_RANGE then
				local localDir = rcf:VectorToObjectSpace(d)
				targetYaw = math.clamp(math.atan2(-localDir.X, -localDir.Z), -1.1, 1.1)
				targetPitch = math.clamp(math.atan2(localDir.Y - 1.5, math.max(0.5, Vector3.new(localDir.X, 0, localDir.Z).Magnitude)), -0.45, 0.45)
			end
		end
		local a = 1 - math.exp(-6 * dt)
		rig.Yaw += (targetYaw - rig.Yaw) * a
		rig.Pitch += (targetPitch - rig.Pitch) * a
		local s = rig.Seed
		local breath = math.sin(t * 1.7 + s) * 0.05
		local sway = math.sin(t * 1.2 + s)
		local headIdle = math.sin(t * 0.7 + s) * 0.06
		local headAdd, leg = 0, 0
		local armL = CFrame.Angles(sway * 0.05 + breath, 0, math.sin(t * 1.7 + s) * 0.03)
		local armR = CFrame.Angles(-sway * 0.05 + breath, 0, -math.sin(t * 1.7 + s) * 0.03)
		local lift = CFrame.new(0, breath, 0)
		if rig.Act then
			local aL, aR, sh, ha, lg = scene(rig, t)
			-- los brazos de algunos oficios nacen ya inclinados (mazo, pergamino...): se resta ese reposo para que la pose sea la pedida
			armL, armR, headAdd, leg = CFrame.Angles(-rig.BiasL, 0, 0) * aL, CFrame.Angles(-rig.BiasR, 0, 0) * aR, ha, lg
			lift = CFrame.new(sh.X, breath + sh.Y, sh.Z)
		end
		local headRot = CFrame.Angles(-rig.Pitch + headAdd, rig.Yaw + headIdle, 0)
		for _, pc in ipairs(rig.Pieces) do
			local part = pc.Part
			if part.Parent then
				local base = rcf * pc.Rel
				local g = pc.Grp
				if g == "Head" then
					local pivot = rcf * lift * NECK
					part.CFrame = pivot * headRot * (rcf * NECK):ToObjectSpace(base)
				elseif g == "ArmL" then
					local pivot = rcf * lift * SHOULDER_L
					part.CFrame = pivot * armL * (rcf * SHOULDER_L):ToObjectSpace(base)
				elseif g == "ArmR" then
					local pivot = rcf * lift * SHOULDER_R
					part.CFrame = pivot * armR * (rcf * SHOULDER_R):ToObjectSpace(base)
				elseif g == "Body" then
					part.CFrame = lift * base
				elseif leg ~= 0 and (g == "LegL" or g == "LegR") then
					local hip = rcf * CFrame.new(if g == "LegL" then -0.5 else 0.5, -1, 0)
					part.CFrame = hip * CFrame.Angles(if g == "LegL" then leg else -leg, 0, 0) * hip:ToObjectSpace(base)
				else
					part.CFrame = base
				end
			end
		end
	end
end)
print("[NpcIdleClient] listo")
