--!strict
--[[
    AuraClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AuraClient
    Dibuja las AURAS de nivel alrededor de cada jugador (el atributo "Aura" lo publica LevelMilestoneService).
    Todo es local (partículas, luz y esferas), así que no cuesta nada al servidor. Se ven las auras dentro de VIEW_RANGE studs.
    Catálogo: ReplicatedStorage.Modules.LevelMilestones.Auras.   NO está en la lista RELOAD de UIReloadClient (no es UI).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Milestones: any = require(ReplicatedStorage:WaitForChild("Modules", 10):WaitForChild("LevelMilestones", 10))

local VIEW_RANGE = 140
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type Orbiter = { Part: Part, Angle: number, Radius: number, Speed: number, Height: number, Bob: number }
type Live = { Folder: Folder, Root: BasePart, Orbs: { Orbiter }, Ring: Part?, AuraId: string, Light: PointLight? }
local live: { [Player]: Live } = {}

local function seq(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Drag = 1
	for k, v in pairs(props) do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function orb(folder: Folder, color: Color3, size: number): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = folder
	return p
end

local function build(pl: Player, root: BasePart, def: any): Live
	local folder = Instance.new("Folder")
	folder.Name = "AuraFx"
	folder.Parent = Workspace:FindFirstChild("AuraFolder") or (function()
		local f = Instance.new("Folder")
		f.Name = "AuraFolder"
		f.Parent = Workspace
		return f
	end)()
	local at = Instance.new("Attachment")
	at.Name = "AuraAttachment"
	at.Position = Vector3.new(0, -0.5, 0)
	at.Parent = root
	local a, b = def.A :: Color3, def.B :: Color3
	local orbs: { Orbiter } = {}
	local ring: Part? = nil
	local light: PointLight? = nil
	local style = def.Style
	if style == "brillo" then
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 14, Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 2.5, 0), EmissionDirection = Enum.NormalId.Top })
	elseif style == "llama" then
		emitter(at, { Texture = TEX_FIRE, Color = seq(a, b), Rate = 26, Lifetime = NumberRange.new(0.7, 1.2), Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(25, 25),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.2) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 6, 0), EmissionDirection = Enum.NormalId.Top })
		emitter(at, { Texture = TEX_SMOKE, Color = seq(Color3.fromRGB(60, 20, 20), Color3.fromRGB(20, 20, 20)), Rate = 5, Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(1, 2), LightEmission = 0.1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 4, 0), EmissionDirection = Enum.NormalId.Top })
	elseif style == "rayos" then
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 38, Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0), Drag = 3,
			Acceleration = Vector3.new(0, 1, 0) })
		light = Instance.new("PointLight")
		light.Color = a
		light.Range = 12
		light.Brightness = 1.2
		light.Parent = root
	elseif style == "orbita" then
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 8, Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
		for i = 1, 5 do
			table.insert(orbs, { Part = orb(folder, a:Lerp(b, (i - 1) / 4), 0.65), Angle = (i / 5) * math.pi * 2, Radius = 3.6, Speed = 1.6, Height = -1 + (i % 3) * 1.4, Bob = i })
		end
		light = Instance.new("PointLight")
		light.Color = b
		light.Range = 10
		light.Brightness = 0.9
		light.Parent = root
	elseif style == "corona" then
		-- pilar de chispas doradas + llamas suaves + anillo de luz + 8 esferas + luz cálida
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 30, Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(8, 8),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 5, 0), EmissionDirection = Enum.NormalId.Top, Drag = 0 })
		emitter(at, { Texture = TEX_FIRE, Color = seq(a, b), Rate = 14, Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(35, 35),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.3) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 4, 0), EmissionDirection = Enum.NormalId.Top })
		ring = Instance.new("Part")
		local r = ring :: Part
		r.Shape = Enum.PartType.Cylinder
		r.Size = Vector3.new(0.18, 7.4, 7.4)
		r.Material = Enum.Material.Neon
		r.Color = a
		r.Transparency = 0.35
		r.Anchored = true
		r.CanCollide = false
		r.CanQuery = false
		r.CanTouch = false
		r.CastShadow = false
		r.Parent = folder
		for i = 1, 8 do
			table.insert(orbs, { Part = orb(folder, if i % 2 == 0 then a else b, 0.55), Angle = (i / 8) * math.pi * 2, Radius = 3.7, Speed = -1.2, Height = 0.5 + math.sin(i) * 0.9, Bob = i })
		end
		light = Instance.new("PointLight")
		light.Color = a
		light.Range = 16
		light.Brightness = 1.6
		light.Parent = root
	end
	return { Folder = folder, Root = root, Orbs = orbs, Ring = ring, AuraId = def.Id, Light = light }
end

local function clear(pl: Player)
	local l = live[pl]
	if not l then
		return
	end
	live[pl] = nil
	l.Folder:Destroy()
	if l.Root.Parent then
		local at = l.Root:FindFirstChild("AuraAttachment")
		if at then
			at:Destroy()
		end
	end
	if l.Light then
		l.Light:Destroy()
	end
end

local function refresh(pl: Player)
	local id = pl:GetAttribute("Aura")
	local def = if typeof(id) == "string" then Milestones.AuraById[id] else nil
	local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
	local cur = live[pl]
	if cur and (not def or cur.AuraId ~= (def :: any).Id or not root or cur.Root ~= root) then
		clear(pl)
	end
	if def and root and root:IsA("BasePart") and not live[pl] then
		live[pl] = build(pl, root, def)
	end
end

local function watch(pl: Player)
	pl:GetAttributeChangedSignal("Aura"):Connect(function()
		refresh(pl)
	end)
	pl.CharacterAdded:Connect(function()
		clear(pl)
		task.wait(0.5)
		refresh(pl)
	end)
	pl.CharacterRemoving:Connect(function()
		clear(pl)
	end)
	task.spawn(refresh, pl)
end

for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(clear)

RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	local t = os.clock()
	for pl, l in pairs(live) do
		if not l.Root.Parent then
			clear(pl)
			continue
		end
		local near = not cam or (cam.CFrame.Position - l.Root.Position).Magnitude <= VIEW_RANGE
		local base = l.Root.CFrame
		for _, o in ipairs(l.Orbs) do
			o.Angle += o.Speed * dt
			local y = o.Height + math.sin(t * 2 + o.Bob) * 0.25
			o.Part.CFrame = base * CFrame.new(math.cos(o.Angle) * o.Radius, y - 0.6, math.sin(o.Angle) * o.Radius)
			o.Part.Transparency = if near then 0 else 1
		end
		if l.Ring then
			-- anillo horizontal a los pies que gira y late
			l.Ring.CFrame = base * CFrame.new(0, -2.8, 0) * CFrame.Angles(0, t * 0.8, math.pi / 2)
			l.Ring.Transparency = if near then 0.35 + math.sin(t * 3) * 0.15 else 1
		end
		if l.Light then
			l.Light.Enabled = near
		end
	end
end)
