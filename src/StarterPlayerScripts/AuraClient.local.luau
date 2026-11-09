--!strict
--[[
    AuraClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AuraClient
    Dibuja las AURAS de nivel alrededor de cada jugador (el atributo "Aura" lo publica LevelMilestoneService).
    Cada aura mezcla capas: resplandor del cuerpo (Highlight), círculos en el piso, partículas, esferas con estela, rayos y (Corona) alas y pilar de luz.
    Todo es local, así que no cuesta nada al servidor. Se ven las auras dentro de VIEW_RANGE studs.
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

type Orbiter = { Part: Part, Angle: number, Radius: number, Speed: number, Height: number, Bob: number, Tilt: Vector3 }
type RingInfo = { Part: Part, Spin: number, Y: number, Pulse: number, Base: number, Flat: boolean }
type Feather = { Part: Part, Side: number, Idx: number, Len: number }
type Arc = { Beam: Beam, Src: Part, Dst: Part, Next: number }
type Live = {
	Folder: Folder, Root: BasePart, Orbs: { Orbiter }, Rings: { RingInfo }, Feathers: { Feather }, Arcs: { Arc },
	AuraId: string, Light: PointLight?, Hl: Highlight?, Pillar: Part?, LightBase: number, Flicker: number, HlBase: number,
}
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

local function fx(p: Part)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

local function orb(folder: Folder, a: Color3, b: Color3, size: number, trail: boolean): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Material = Enum.Material.Neon
	p.Color = a
	fx(p)
	p.Parent = folder
	if trail then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, size * 0.5, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -size * 0.5, 0)
		a1.Parent = p
		local t = Instance.new("Trail")
		t.Attachment0, t.Attachment1 = a0, a1
		t.Lifetime = 0.7
		t.LightEmission = 1
		t.Color = seq(a, b)
		t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
		t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
		t.FaceCamera = true
		t.Parent = p
	end
	return p
end

local function ring(folder: Folder, color: Color3, diameter: number, thick: number, transp: number): Part
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Size = Vector3.new(thick, diameter, diameter)
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Transparency = transp
	fx(r)
	r.Parent = folder
	return r
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
	local L: Live = { Folder = folder, Root = root, Orbs = {}, Rings = {}, Feathers = {}, Arcs = {}, AuraId = def.Id, LightBase = 0, Flicker = 0, HlBase = 0.85 }
	local style = def.Style

	local function addRing(diam: number, thick: number, transp: number, spin: number, y: number, color: Color3?, pulse: number?)
		local r = ring(folder, color or a, diam, thick, transp)
		table.insert(L.Rings, { Part = r, Spin = spin, Y = y, Pulse = pulse or 0.12, Base = transp, Flat = true })
	end
	local function addOrbs(n: number, size: number, radius: number, speed: number, tilts: { Vector3 }, trail: boolean)
		for i = 1, n do
			local tilt = tilts[(i - 1) % #tilts + 1]
			table.insert(L.Orbs, { Part = orb(folder, a:Lerp(b, (i - 1) / math.max(1, n - 1)), b, size, trail), Angle = (i / n) * math.pi * 2, Radius = radius, Speed = speed, Height = 0, Bob = i, Tilt = tilt })
		end
	end
	local function light(range: number, brightness: number)
		local l = Instance.new("PointLight")
		l.Color = a
		l.Range = range
		l.Brightness = brightness
		l.Parent = root
		L.Light = l
		L.LightBase = brightness
	end
	local function highlight(fill: number, outline: number)
		local ch = pl.Character
		if ch then
			local h = Instance.new("Highlight")
			h.Name = "AuraGlow"
			h.FillColor = a
			h.OutlineColor = b
			h.FillTransparency = fill
			h.OutlineTransparency = outline
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = ch
			h.Parent = folder
			L.Hl = h
			L.HlBase = fill
		end
	end
	-- disco de luz bajo los pies (todas las auras)
	local disc = ring(folder, a, 7.5 + (if style == "corona" then 2 else 0), 0.08, 0.82)
	table.insert(L.Rings, { Part = disc, Spin = 0, Y = -2.88, Pulse = 0.06, Base = 0.82, Flat = true })

	if style == "brillo" then
		addRing(7, 0.14, 0.45, 0.5, -2.85)
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 30, Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 3, 0), EmissionDirection = Enum.NormalId.Top })
		emitter(at, { Texture = TEX_SPARK, Color = seq(Color3.new(1, 1, 1), a), Rate = 5, Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(0.5, 1), LightEmission = 0.6,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.2), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) }), RotSpeed = NumberRange.new(-20, 20) })
		highlight(0.9, 0.55)
		light(10, 0.8)
	elseif style == "llama" then
		addRing(8, 0.18, 0.4, -0.7, -2.85, a)
		emitter(at, { Texture = TEX_FIRE, Color = seq(a, b), Rate = 55, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(22, 22),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.4), NumberSequenceKeypoint.new(1, 0.4) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 8, 0), EmissionDirection = Enum.NormalId.Top })
		emitter(at, { Texture = TEX_SPARK, Color = seq(Color3.fromRGB(255, 240, 160), b), Rate = 22, Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(6, 11), SpreadAngle = Vector2.new(40, 40),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0, 1), Acceleration = Vector3.new(0, 9, 0), EmissionDirection = Enum.NormalId.Top })
		emitter(at, { Texture = TEX_SMOKE, Color = seq(Color3.fromRGB(70, 24, 24), Color3.fromRGB(20, 20, 20)), Rate = 8, Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(1.5, 3), LightEmission = 0.05,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 3.4) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.65), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 5, 0), EmissionDirection = Enum.NormalId.Top })
		highlight(0.78, 0.2)
		light(15, 2)
		L.Flicker = 0.5
	elseif style == "rayos" then
		addRing(8, 0.14, 0.35, 2.2, -2.85)
		addRing(5.6, 0.1, 0.4, -3.2, -2.8, b)
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 60, Lifetime = NumberRange.new(0.25, 0.55), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new(0), Drag = 3, Acceleration = Vector3.new(0, 1, 0) })
		for i = 1, 4 do
			local src = Instance.new("Part")
			src.Size = Vector3.one * 0.2
			src.Transparency = 1
			fx(src)
			src.Parent = folder
			local dst = src:Clone()
			dst.Parent = folder
			local a0 = Instance.new("Attachment")
			a0.Parent = src
			local a1 = Instance.new("Attachment")
			a1.Parent = dst
			local bm = Instance.new("Beam")
			bm.Attachment0, bm.Attachment1 = a0, a1
			bm.Color = seq(Color3.new(1, 1, 1), a)
			bm.LightEmission = 1
			bm.Width0, bm.Width1 = 0.35, 0.12
			bm.Segments = 10
			bm.FaceCamera = true
			bm.Transparency = NumberSequence.new(0.05)
			bm.Parent = src
			table.insert(L.Arcs, { Beam = bm, Src = src, Dst = dst, Next = 0 })
		end
		highlight(0.82, 0.25)
		light(14, 2)
		L.Flicker = 1
	elseif style == "orbita" then
		addRing(8, 0.14, 0.4, 1, -2.85)
		addRing(5.4, 0.1, 0.5, -1.6, -2.8, b)
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 14, Lifetime = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(0.5, 1.8), SpreadAngle = Vector2.new(180, 180),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) })
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 4, Lifetime = NumberRange.new(1.6, 2.2), Speed = NumberRange.new(0.4, 0.8), LightEmission = 0.7,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.6), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.78), NumberSequenceKeypoint.new(1, 1) }) })
		addOrbs(6, 0.8, 4.2, 1.7, { Vector3.new(0, 0, 0), Vector3.new(0.9, 0, 0.5), Vector3.new(-0.9, 0, 0.5) }, true)
		highlight(0.84, 0.3)
		light(12, 1.3)
	elseif style == "corona" then
		-- pilar de luz + chispas y llamas doradas + anillos (piso y halo) + alas de luz + 10 esferas con estela
		local pillar = Instance.new("Part")
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(40, 6.2, 6.2)
		pillar.Material = Enum.Material.Neon
		pillar.Color = a
		pillar.Transparency = 0.86
		fx(pillar)
		pillar.Parent = folder
		L.Pillar = pillar
		addRing(9.5, 0.2, 0.3, 0.8, -2.85)
		addRing(6.4, 0.14, 0.4, -1.4, -2.8, b)
		addRing(3.4, 0.14, 0.2, 2.4, 3.6, a, 0.1) -- halo sobre la cabeza
		emitter(at, { Texture = TEX_SPARK, Color = seq(a, b), Rate = 45, Lifetime = NumberRange.new(1.8, 2.8), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(10, 10),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 6, 0), EmissionDirection = Enum.NormalId.Top, Drag = 0 })
		emitter(at, { Texture = TEX_FIRE, Color = seq(a, b), Rate = 26, Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(30, 30),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0.4) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }),
			Acceleration = Vector3.new(0, 5, 0), EmissionDirection = Enum.NormalId.Top })
		emitter(at, { Texture = TEX_SPARK, Color = seq(Color3.new(1, 1, 1), a), Rate = 8, Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(0.5, 1), LightEmission = 0.8,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4.5), NumberSequenceKeypoint.new(1, 0) }), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }) })
		addOrbs(10, 0.7, 4.3, -1.3, { Vector3.new(0, 0, 0), Vector3.new(0.55, 0, 0.35), Vector3.new(-0.55, 0, 0.35) }, true)
		for side = -1, 1, 2 do
			for i = 1, 5 do
				local len = 4.4 - i * 0.45
				local f = Instance.new("Part")
				f.Size = Vector3.new(0.14, len, 0.9)
				f.Material = Enum.Material.Neon
				f.Color = a:Lerp(b, (i - 1) / 4)
				f.Transparency = 0.25
				fx(f)
				f.Parent = folder
				table.insert(L.Feathers, { Part = f, Side = side, Idx = i, Len = len })
			end
		end
		highlight(0.7, 0.1)
		light(22, 2.6)
	end
	return L
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

local rng = Random.new()

RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	local t = os.clock()
	for pl, l in pairs(live) do
		if not l.Root.Parent then
			clear(pl)
			continue
		end
		local near = not cam or (cam.CFrame.Position - l.Root.Position).Magnitude <= VIEW_RANGE
		local base = CFrame.new(l.Root.Position) * CFrame.Angles(0, math.atan2(-l.Root.CFrame.LookVector.X, -l.Root.CFrame.LookVector.Z), 0)
		for _, o in ipairs(l.Orbs) do
			o.Angle += o.Speed * dt
			local y = o.Height + math.sin(t * 2 + o.Bob) * 0.3
			local v = CFrame.Angles(o.Tilt.X, o.Tilt.Y, o.Tilt.Z) * Vector3.new(math.cos(o.Angle) * o.Radius, 0, math.sin(o.Angle) * o.Radius)
			o.Part.Position = base.Position + Vector3.new(v.X, v.Y + y - 0.2, v.Z)
			o.Part.Transparency = if near then 0 else 1
		end
		for _, r in ipairs(l.Rings) do
			r.Part.CFrame = base * CFrame.new(0, r.Y, 0) * CFrame.Angles(0, t * r.Spin, 0) * CFrame.Angles(0, 0, math.pi / 2)
			r.Part.Transparency = if near then math.clamp(r.Base + math.sin(t * 3 + r.Y) * r.Pulse, 0, 1) else 1
		end
		if l.Pillar then
			l.Pillar.CFrame = base * CFrame.new(0, 17, 0) * CFrame.Angles(0, 0, math.pi / 2)
			l.Pillar.Transparency = if near then 0.86 + math.sin(t * 2.2) * 0.05 else 1
		end
		for _, f in ipairs(l.Feathers) do
			-- alas: cada pluma sale del hombro y se abre en abanico; baten despacio
			local flap = math.sin(t * 1.6) * 0.12
			local lean = f.Side * (0.45 + 0.3 * f.Idx + flap)
			f.Part.CFrame = base * CFrame.new(f.Side * 0.8, 0.8, 0.8) * CFrame.Angles(0.25, 0, lean) * CFrame.new(0, f.Len / 2, 0)
			f.Part.Transparency = if near then 0.2 + 0.08 * math.sin(t * 2 + f.Idx) else 1
		end
		for _, arc in ipairs(l.Arcs) do
			if t >= arc.Next then
				arc.Next = t + rng:NextNumber(0.05, 0.14)
				local ang = rng:NextNumber(0, math.pi * 2)
				local r2 = rng:NextNumber(2.8, 4.4)
				arc.Src.Position = base.Position + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1.5, 2), rng:NextNumber(-0.6, 0.6))
				arc.Dst.Position = base.Position + Vector3.new(math.cos(ang) * r2, rng:NextNumber(-2.6, 3.4), math.sin(ang) * r2)
				arc.Beam.CurveSize0 = rng:NextNumber(-1.8, 1.8)
				arc.Beam.CurveSize1 = rng:NextNumber(-1.8, 1.8)
				arc.Beam.Enabled = near and rng:NextNumber() < 0.85
			end
		end
		if l.Light then
			l.Light.Enabled = near
			if l.Flicker > 0 then
				l.Light.Brightness = l.LightBase * (1 + (rng:NextNumber() - 0.5) * l.Flicker)
			end
		end
		if l.Hl then
			l.Hl.Enabled = near
			l.Hl.FillTransparency = l.HlBase + math.sin(t * 2.2) * 0.06
		end
	end
end)
