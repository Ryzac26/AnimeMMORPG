--!strict
--[[
    NpcIdleClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > NpcIdleClient
    Da vida a los NPC de las ciudades (modelos con la etiqueta "NpcRig", hechos por NpcBuilder; cada pieza trae el atributo "Grp"):
      · respiran (sube y baja el torso un poco), balancean los brazos y la cabeza se mueve suavemente;
      · si te acercas (menos de 22 studs) giran la cabeza y la mirada hacia ti.
    Solo anima los que están cerca de la cámara. Todo es local: no toca al servidor. No lleva pantalla (no va en RELOAD).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local VIEW = 80
local LOOK_RANGE = 22

type Piece = { Part: BasePart, Rel: CFrame, Grp: string }
type Rig = { Model: Model, Root: BasePart, Pieces: { Piece }, Seed: number, Yaw: number, Pitch: number, Count: number, Check: number }
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
		local rig: Rig = { Model = model, Root = root, Pieces = {}, Seed = math.random() * 10, Yaw = 0, Pitch = 0, Count = 0, Check = 0 }
		collect(model, rig)
		rigs[model] = rig
	end)
end

CollectionService:GetInstanceAddedSignal("NpcRig"):Connect(add)
CollectionService:GetInstanceRemovedSignal("NpcRig"):Connect(function(m)
	rigs[m :: Model] = nil
end)
for _, m in ipairs(CollectionService:GetTagged("NpcRig")) do
	add(m)
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
		local headRot = CFrame.Angles(-rig.Pitch, rig.Yaw + headIdle, 0)
		local armL = CFrame.Angles(sway * 0.05 + breath, 0, math.sin(t * 1.7 + s) * 0.03)
		local armR = CFrame.Angles(-sway * 0.05 + breath, 0, -math.sin(t * 1.7 + s) * 0.03)
		local lift = CFrame.new(0, breath, 0)
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
				else
					part.CFrame = base
				end
			end
		end
	end
end)
print("[NpcIdleClient] listo")
