--!strict
--[[
    AuraClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AuraClient
    MOTOR de auras: lee la "receta" (capas) de ReplicatedStorage.Modules.AuraSpecs y la dibuja alrededor de cada jugador
    (el atributo "Aura" lo publica LevelMilestoneService). Texturas: ReplicatedStorage.Modules.AuraTextures.
    Todo es local (cero costo de servidor). Solo se dibujan las MAX_ACTIVE auras más cercanas (la tuya siempre) dentro de VIEW_RANGE studs.
    Alpha en capas ground/back/glow = TRANSPARENCIA (0 = sólido). En "emit" Alpha = { transparencia inicial, final }.
    NO está en la lista RELOAD de UIReloadClient (no es UI).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local Milestones: any = require(Modules:WaitForChild("LevelMilestones", 10))
local Specs: { [string]: { any } } = require(Modules:WaitForChild("AuraSpecs", 10)) :: any
local Textures: any = require(Modules:WaitForChild("AuraTextures", 10))

local LP = Players.LocalPlayer
local VIEW_RANGE = 140
local MAX_ACTIVE = 8
local FLOOR = -3 -- el piso respecto al centro del HumanoidRootPart
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.fromRGB(12, 10, 18)

local fxRoot = Workspace:FindFirstChild("AuraFx") :: Folder?
if not fxRoot then
	fxRoot = Instance.new("Folder")
	fxRoot.Name = "AuraFx"
	fxRoot.Parent = Workspace
end
local FX: Folder = fxRoot :: Folder

type Upd = (number, number, CFrame) -> ()
type Live = {
	Folder: Folder, Root: BasePart, Char: Model, AuraId: string, Upd: { Upd }, Emitters: { ParticleEmitter },
	Extra: { Instance }, Hl: Highlight?, HlBase: number, Light: PointLight?, LightBase: number, Flicker: number,
	Visible: boolean, Bloom: BloomEffect?, Dist: number,
}
local live: { [Player]: Live } = {}
local rng = Random.new()
local camLook = Vector3.new(0, 0, -1)

-- ───────── colores ─────────
local function rainbowSeq(): ColorSequence
	local k = {}
	for i = 0, 6 do
		table.insert(k, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 0.55, 1)))
	end
	return ColorSequence.new(k)
end
local RAINBOW = rainbowSeq()

local function solid(spec: any, a: Color3, b: Color3, hue: number): Color3
	if typeof(spec) == "Color3" then
		return spec
	end
	if spec == "A" then
		return a
	elseif spec == "B" then
		return b
	elseif spec == "AB" then
		return a:Lerp(b, 0.5)
	elseif spec == "W" then
		return WHITE
	elseif spec == "WA" then
		return WHITE:Lerp(a, 0.55)
	elseif spec == "WB" then
		return WHITE:Lerp(b, 0.55)
	elseif spec == "dark" then
		return b:Lerp(BLACK, 0.7)
	elseif spec == "rainbow" then
		return Color3.fromHSV(hue % 1, 0.55, 1)
	end
	return a
end

local function seqOf(spec: any, a: Color3, b: Color3): ColorSequence
	if typeof(spec) == "Color3" then
		return ColorSequence.new(spec)
	end
	if spec == "AB" then
		return ColorSequence.new(a, b)
	elseif spec == "WA" then
		return ColorSequence.new(WHITE, a)
	elseif spec == "WB" then
		return ColorSequence.new(WHITE, b)
	elseif spec == "dark" then
		return ColorSequence.new(b:Lerp(BLACK, 0.55), BLACK)
	elseif spec == "rainbow" then
		return RAINBOW
	end
	return ColorSequence.new(solid(spec, a, b, 0))
end

local function range(v: any, d: number): NumberRange
	if type(v) == "table" then
		return NumberRange.new(v[1], v[2] or v[1])
	elseif type(v) == "number" then
		return NumberRange.new(v)
	end
	return NumberRange.new(d)
end

local function pair(v: any, d1: number, d2: number): NumberSequence
	if type(v) == "table" then
		return NumberSequence.new(v[1], v[2] or v[1])
	end
	return NumberSequence.new(d1, d2)
end

-- ───────── piezas base ─────────
local function fxPart(parent: Instance, size: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = parent
	return p
end

local function decal(p: Part, face: Enum.NormalId, tex: string, transp: number, col: Color3)
	local d = Instance.new("Decal")
	d.Face = face
	d.Texture = tex
	d.Transparency = transp
	d.Color3 = col
	d.Parent = p
end

local function sprite(parent: Instance, adornee: BasePart, tex: string, size: number, col: Color3, transp: number): (BillboardGui, ImageLabel)
	local g = Instance.new("BillboardGui")
	g.Adornee = adornee
	g.Size = UDim2.fromScale(size, size)
	g.LightInfluence = 0
	g.AlwaysOnTop = false
	g.ResetOnSpawn = false
	g.Parent = parent
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.AnchorPoint = Vector2.new(0.5, 0.5)
	im.Position = UDim2.fromScale(0.5, 0.5)
	im.Size = UDim2.fromScale(1, 1)
	im.Image = tex
	im.ImageColor3 = col
	im.ImageTransparency = transp
	im.Parent = g
	return g, im
end

type Ctx = { L: Live, A: Color3, B: Color3, Idx: number }

-- ───────── capas ─────────
local function layerGround(c: Ctx, s: any, back: boolean)
	local size: number = s.Size or 6
	local p = if back then fxPart(c.L.Folder, Vector3.new(size, size, 0.05)) else fxPart(c.L.Folder, Vector3.new(size, 0.05, size))
	local tr: number = s.Alpha or 0.4
	local tex = Textures.Get(s.Tex)
	local col = solid(s.C, c.A, c.B, 0)
	if back then
		decal(p, Enum.NormalId.Front, tex, tr, col)
		decal(p, Enum.NormalId.Back, tex, tr, col)
	else
		decal(p, Enum.NormalId.Top, tex, tr, col)
		decal(p, Enum.NormalId.Bottom, tex, tr, col)
	end
	local spin: number = s.Spin or 0
	local y: number = s.Y or (if back then 0.4 else 0.1)
	local tilt: Vector3 = s.Tilt or Vector3.zero
	local pulse: number = s.Pulse or 0
	local ph = rng:NextNumber(0, 6)
	local rb = s.C == "rainbow"
	local idx = c.Idx
	table.insert(c.L.Upd, function(t, _dt, base)
		local rot = CFrame.Angles(tilt.X, tilt.Y, tilt.Z)
		if back then
			p.CFrame = base * CFrame.new(0, y, 1.1) * rot * CFrame.Angles(0, 0, t * spin)
		else
			p.CFrame = base * CFrame.new(0, FLOOR + y, 0) * rot * CFrame.Angles(0, t * spin, 0)
		end
		for _, d in ipairs(p:GetChildren()) do
			if d:IsA("Decal") then
				d.Transparency = math.clamp(tr + math.sin(t * 2.4 + ph) * pulse * 3, 0, 1)
				if rb then
					d.Color3 = solid("rainbow", c.A, c.B, t * 0.15 + idx * 0.13)
				end
			end
		end
	end)
end

local function layerGlow(c: Ctx, s: any)
	local size: number = s.Size or 8
	local anchor = fxPart(c.L.Folder, Vector3.one * 0.2)
	local _, im = sprite(c.L.Folder, anchor, Textures.Get(s.Tex), size, solid(s.C, c.A, c.B, 0), s.Alpha or 0.7)
	local g = im.Parent :: BillboardGui
	local pulse: number = s.Pulse or 0
	local y: number = s.Y or 0
	local rb = s.C == "rainbow"
	local idx = c.Idx
	table.insert(c.L.Upd, function(t, _dt, base)
		anchor.Position = base.Position + Vector3.new(0, y, 0) + camLook * 2.2 -- detrás del cuerpo, sin cruzarse con él
		local k = 1 + math.sin(t * 2.6 + idx) * pulse * 2
		g.Size = UDim2.fromScale(size * k, size * k)
		if rb then
			im.ImageColor3 = solid("rainbow", c.A, c.B, t * 0.15 + idx * 0.13)
		end
	end)
end

local function host(c: Ctx, kind: string, hosts: { [string]: Part }): Part
	local h = hosts[kind]
	if h then
		return h
	end
	local size = if kind == "feet" then Vector3.new(2.6, 0.2, 2.6) elseif kind == "head" then Vector3.new(1.8, 0.4, 1.8) elseif kind == "around" then Vector3.new(5, 6, 5) else Vector3.new(2, 4, 1)
	h = fxPart(c.L.Folder, size)
	hosts[kind] = h
	table.insert(c.L.Upd, function(_t, _dt, base)
		local off = if kind == "feet" then FLOOR + 0.2 elseif kind == "head" then 2.6 else 0
		(h :: Part).CFrame = base * CFrame.new(0, off, 0)
	end)
	return h :: Part
end

local LIMBS = { "LeftHand", "RightHand", "LeftFoot", "RightFoot", "LeftLowerArm", "RightLowerArm", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function layerEmit(c: Ctx, s: any, hosts: { [string]: Part })
	local texs: { any } = if type(s.Tex) == "table" then s.Tex else { s.Tex }
	local where: string = s.Where or "around"
	local parents: { Instance } = {}
	if where == "limbs" then
		for _, n in ipairs(LIMBS) do
			local lp = c.L.Char:FindFirstChild(n)
			if lp and lp:IsA("BasePart") then
				table.insert(parents, lp)
			end
		end
		if #parents == 0 then
			table.insert(parents, host(c, "root", hosts))
		end
	else
		table.insert(parents, host(c, where, hosts))
	end
	local per = (s.Rate or 10) / (#texs * #parents)
	for _, pr in ipairs(parents) do
		for _, name in ipairs(texs) do
			local e = Instance.new("ParticleEmitter")
			e.Texture = Textures.Get(name)
			e.Rate = per
			e.Lifetime = range(s.Life, 1)
			e.Speed = range(s.Speed, 1)
			e.SpreadAngle = Vector2.new(s.Spread or 180, s.Spread or 180)
			e.Color = seqOf(s.C, c.A, c.B)
			e.Size = pair(s.Size, 1, 0)
			e.Transparency = pair(s.Alpha, 0.1, 1)
			e.LightEmission = s.Light or 1
			e.LightInfluence = 0
			e.Drag = 1
			e.Acceleration = s.Accel or Vector3.zero
			e.Rotation = NumberRange.new(0, 360)
			local sp: number = s.Spin or 40
			e.RotSpeed = NumberRange.new(-sp, sp)
			if s.Dir == "Bottom" then
				e.EmissionDirection = Enum.NormalId.Bottom
			elseif s.Dir == "Top" then
				e.EmissionDirection = Enum.NormalId.Top
			end
			if s.Orient == "VelocityParallel" then
				e.Orientation = Enum.ParticleOrientation.VelocityParallel
			end
			if pr == hosts.around or pr == hosts.head or pr == hosts.feet then
				e.Shape = Enum.ParticleEmitterShape.Box
				e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			end
			e.Parent = pr
			table.insert(c.L.Emitters, e)
		end
	end
end

local function layerOrbit(c: Ctx, s: any)
	local n: number = s.N or 5
	local kind: string = s.Kind or "orb"
	local radius: number = s.Radius or 4
	local speed: number = s.Speed or 1
	local size: number = s.Size or 1
	local tilts: { Vector3 } = s.Tilts or { Vector3.zero }
	local rb = s.C == "rainbow"
	for i = 1, n do
		local tilt = tilts[(i - 1) % #tilts + 1]
		local rot = CFrame.Angles(tilt.X, tilt.Y, tilt.Z)
		local ang = (i / n) * math.pi * 2
		local bob = rng:NextNumber(0, 6)
		local hue0 = i / n
		local col = if s.C == "AB" then c.A:Lerp(c.B, hue0) else solid(s.C or "A", c.A, c.B, hue0)
		local part: Part
		local im: ImageLabel? = nil
		local spin = rng:NextNumber(-3, 3)
		if kind == "orb" then
			part = fxPart(c.L.Folder, Vector3.one * size)
			part.Shape = Enum.PartType.Ball
			part.Material = Enum.Material.Neon
			part.Color = col
			part.Transparency = 0
			if s.Trail then
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, size * 0.45, 0)
				a0.Parent = part
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -size * 0.45, 0)
				a1.Parent = part
				local tr = Instance.new("Trail")
				tr.Attachment0 = a0
				tr.Attachment1 = a1
				tr.Lifetime = 0.7
				tr.LightEmission = 1
				tr.Color = ColorSequence.new(col, c.B)
				tr.Transparency = NumberSequence.new(0.1, 1)
				tr.WidthScale = NumberSequence.new(1, 0)
				tr.Parent = part
			end
		elseif kind == "rock" then
			part = fxPart(c.L.Folder, Vector3.new(rng:NextNumber(0.6, 1.1), rng:NextNumber(0.6, 1.2), rng:NextNumber(0.6, 1.1)) * size)
			part.Material = Enum.Material.Slate
			part.Color = c.A:Lerp(Color3.fromRGB(70, 65, 70), 0.55)
			part.Transparency = 0
		else
			part = fxPart(c.L.Folder, Vector3.one * 0.2)
			local _, lab = sprite(c.L.Folder, part, Textures.Get(s.Tex or ""), size, col, 0)
			im = lab
		end
		table.insert(c.L.Upd, function(t, dt, base)
			ang += speed * dt
			local v = rot * Vector3.new(math.cos(ang) * radius, 0, math.sin(ang) * radius)
			local y = math.sin(t * 1.8 + bob) * 0.35
			local pos = base.Position + Vector3.new(v.X, v.Y + y, v.Z)
			if kind == "rock" then
				part.CFrame = CFrame.new(pos) * CFrame.Angles(t * spin, t * spin * 0.7, bob)
			else
				part.Position = pos
			end
			if im then
				if kind == "butterfly" then
					im.Size = UDim2.fromScale(0.25 + 0.75 * math.abs(math.cos(t * 8 + bob)), 1)
				elseif kind == "leaf" then
					im.Rotation = (t * 160 * (if spin > 0 then 1 else -1) + bob * 60) % 360
				elseif kind == "shard" then
					im.Rotation = bob * 25 + math.sin(t * 1.4 + bob) * 25
				elseif kind == "wave" then
					im.Rotation = math.deg(-ang) % 360 + 90
				end
				if rb then
					im.ImageColor3 = solid("rainbow", c.A, c.B, t * 0.15 + hue0)
				end
			elseif rb and kind == "orb" then
				part.Color = solid("rainbow", c.A, c.B, t * 0.15 + hue0)
			end
		end)
	end
end

local function layerArcs(c: Ctx, s: any)
	for _ = 1, s.N or 5 do
		local src = fxPart(c.L.Folder, Vector3.one * 0.2)
		local dst = fxPart(c.L.Folder, Vector3.one * 0.2)
		local a0 = Instance.new("Attachment")
		a0.Parent = src
		local a1 = Instance.new("Attachment")
		a1.Parent = dst
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.FaceCamera = true
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Segments = 10
		bm.Width0 = 0.5
		bm.Width1 = 0.12
		bm.Color = ColorSequence.new(WHITE, c.A)
		bm.Transparency = NumberSequence.new(0.05, 0.4)
		bm.Enabled = false
		bm.Parent = src
		local nxt = 0.0
		table.insert(c.L.Upd, function(t, _dt, base)
			if t >= nxt then
				nxt = t + rng:NextNumber(0.05, 0.14)
				local ang = rng:NextNumber(0, math.pi * 2)
				local r2 = rng:NextNumber(2.8, 4.6)
				local p = base.Position
				src.Position = p + Vector3.new(rng:NextNumber(-0.6, 0.6), rng:NextNumber(-1.5, 2), rng:NextNumber(-0.6, 0.6))
				dst.Position = p + Vector3.new(math.cos(ang) * r2, rng:NextNumber(-2.6, 3.4), math.sin(ang) * r2)
				bm.CurveSize0 = rng:NextNumber(-1.8, 1.8)
				bm.CurveSize1 = rng:NextNumber(-1.8, 1.8)
				bm.Enabled = rng:NextNumber() < 0.85
			end
		end)
	end
end

local function layerWings(c: Ctx, s: any)
	local texs: { any } = s.Tex or { "Pluma-A" }
	local count: number = s.Count or 6
	local scale: number = s.Scale or 1
	for side = -1, 1, 2 do
		for i = 0, count - 1 do
			local f = i / math.max(count - 1, 1)
			local len = scale * (3 + math.sin(f * math.pi * 0.9 + 0.2) * 2.4)
			local p = fxPart(c.L.Folder, Vector3.new(len * 0.42, len, 0.05))
			local tex = Textures.Get(texs[(i % #texs) + 1])
			local col = solid(s.C or "WA", c.A, c.B, 0):Lerp(c.B, f * 0.5)
			decal(p, Enum.NormalId.Front, tex, 0.08, col)
			decal(p, Enum.NormalId.Back, tex, 0.08, col)
			local lean0 = 0.15 + f * 1.55
			table.insert(c.L.Upd, function(t, _dt, base)
				local flap = math.sin(t * 1.5 + f) * 0.07 + math.sin(t * 0.7) * 0.05
				p.CFrame = base * CFrame.new(side * 0.6, 0.8, 0.9) * CFrame.Angles(0.35, 0, 0) * CFrame.Angles(0, 0, -side * (lean0 + flap)) * CFrame.new(0, len / 2, 0)
			end)
		end
	end
end

local function layerPillar(c: Ctx, s: any)
	local col = solid(s.C or "A", c.A, c.B, 0)
	local cyl = fxPart(c.L.Folder, Vector3.new(36, 3, 3))
	cyl.Shape = Enum.PartType.Cylinder
	cyl.Material = Enum.Material.Neon
	cyl.Color = col
	cyl.Transparency = 0.9
	local anchor = fxPart(c.L.Folder, Vector3.one * 0.2)
	local _, im = sprite(c.L.Folder, anchor, Textures.Get("Columna-luz"), 1, col, 0.35)
	local g = im.Parent :: BillboardGui
	g.Size = UDim2.fromScale(7, 40)
	table.insert(c.L.Upd, function(t, _dt, base)
		cyl.CFrame = base * CFrame.new(0, 15, 0) * CFrame.Angles(0, 0, math.pi / 2)
		cyl.Transparency = 0.88 + math.sin(t * 2.2) * 0.05
		anchor.Position = base.Position + Vector3.new(0, 16, 0)
		im.ImageTransparency = 0.4 + math.sin(t * 1.7) * 0.12
	end)
end

-- ───────── ciclo de vida ─────────
local function setVisible(l: Live, v: boolean)
	if l.Visible == v then
		return
	end
	l.Visible = v
	l.Folder.Parent = if v then FX else nil
	for _, e in ipairs(l.Emitters) do
		e.Enabled = v
	end
	if l.Hl then
		l.Hl.Enabled = v
	end
	if l.Light then
		l.Light.Enabled = v
	end
end

local function clear(pl: Player)
	local l = live[pl]
	if not l then
		return
	end
	live[pl] = nil
	for _, e in ipairs(l.Emitters) do
		e:Destroy()
	end
	if l.Hl then
		l.Hl:Destroy()
	end
	if l.Bloom then
		l.Bloom:Destroy()
	end
	l.Folder:Destroy()
end

local function build(pl: Player, root: BasePart, def: any): Live
	local char = root.Parent :: Model
	local folder = Instance.new("Folder")
	folder.Name = "Aura_" .. pl.Name
	folder.Parent = FX
	local l: Live = {
		Folder = folder, Root = root, Char = char, AuraId = def.Id, Upd = {}, Emitters = {}, Extra = {},
		Hl = nil, HlBase = 0.8, Light = nil, LightBase = 1, Flicker = 0, Visible = true, Bloom = nil, Dist = 0,
	}
	local c: Ctx = { L = l, A = def.A, B = def.B, Idx = 0 }
	local hosts: { [string]: Part } = {}
	local spec = Specs[def.Style] or Specs[def.Id] or {}
	for i, s in ipairs(spec) do
		c.Idx = i
		local ok, err = pcall(function()
			local t: string = s.T
			if t == "ground" then
				layerGround(c, s, false)
			elseif t == "back" then
				layerGround(c, s, true)
			elseif t == "glow" then
				layerGlow(c, s)
			elseif t == "emit" then
				layerEmit(c, s, hosts)
			elseif t == "orbit" then
				layerOrbit(c, s)
			elseif t == "arcs" then
				layerArcs(c, s)
			elseif t == "wings" then
				layerWings(c, s)
			elseif t == "pillar" then
				layerPillar(c, s)
			elseif t == "hl" then
				local h = Instance.new("Highlight")
				h.Adornee = char
				h.FillColor = def.A
				h.OutlineColor = def.B
				h.FillTransparency = s.Fill or 0.85
				h.OutlineTransparency = s.Out or 0.4
				h.DepthMode = Enum.HighlightDepthMode.Occluded
				h.Parent = folder
				l.Hl = h
				l.HlBase = s.Fill or 0.85
			elseif t == "light" then
				local pt = Instance.new("PointLight")
				pt.Color = def.A
				pt.Range = s.Range or 10
				pt.Brightness = s.Bright or 1
				pt.Shadows = false
				pt.Parent = root
				l.Light = pt
				l.LightBase = s.Bright or 1
				l.Flicker = s.Flicker or 0
				table.insert(l.Extra, pt)
			elseif t == "bloom" and pl == LP then
				local b = Instance.new("BloomEffect")
				b.Name = "AuraBloom"
				b.Intensity = 0.45
				b.Size = 22
				b.Threshold = 1.05
				b.Parent = Lighting
				l.Bloom = b
			end
		end)
		if not ok then
			warn("[AuraClient] capa " .. tostring(i) .. " de " .. tostring(def.Id) .. ": " .. tostring(err))
		end
	end
	return l
end

local function clearExtra(l: Live)
	for _, x in ipairs(l.Extra) do
		x:Destroy()
	end
end

local function refresh(pl: Player)
	local id = pl:GetAttribute("Aura")
	local def: any = if type(id) == "string" then Milestones.AuraById[id] else nil
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cur = live[pl]
	if cur and (not def or cur.AuraId ~= def.Id or not root or cur.Root ~= root) then
		clearExtra(cur)
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
		local l = live[pl]
		if l then
			clearExtra(l)
		end
		clear(pl)
		task.wait(0.5)
		refresh(pl)
	end)
	pl.CharacterRemoving:Connect(function()
		local l = live[pl]
		if l then
			clearExtra(l)
		end
		clear(pl)
	end)
	task.spawn(refresh, pl)
end

for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerAdded:Connect(watch)
Players.PlayerRemoving:Connect(function(pl)
	local l = live[pl]
	if l then
		clearExtra(l)
	end
	clear(pl)
end)

local nextRank = 0.0
RunService.RenderStepped:Connect(function(dt)
	local cam = Workspace.CurrentCamera
	local t = os.clock()
	if cam then
		camLook = cam.CFrame.LookVector
	end
	-- LOD: solo las MAX_ACTIVE más cercanas (la tuya siempre)
	if t >= nextRank then
		nextRank = t + 0.4
		local list: { Live } = {}
		for pl, l in pairs(live) do
			if not l.Root.Parent then
				continue
			end
			l.Dist = if pl == LP then -1 else (if cam then (cam.CFrame.Position - l.Root.Position).Magnitude else 0)
			table.insert(list, l)
		end
		table.sort(list, function(a, b)
			return a.Dist < b.Dist
		end)
		for i, l in ipairs(list) do
			setVisible(l, i <= MAX_ACTIVE and l.Dist <= VIEW_RANGE)
		end
	end
	for pl, l in pairs(live) do
		if not l.Root.Parent then
			clearExtra(l)
			clear(pl)
			continue
		end
		if not l.Visible then
			continue
		end
		local look = l.Root.CFrame.LookVector
		local base = CFrame.new(l.Root.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
		for _, u in ipairs(l.Upd) do
			u(t, dt, base)
		end
		if l.Light and l.Flicker > 0 then
			l.Light.Brightness = l.LightBase * (1 + (rng:NextNumber() - 0.5) * l.Flicker)
		end
		if l.Hl then
			l.Hl.FillTransparency = l.HlBase + math.sin(t * 2.2) * 0.06
		end
	end
end)
