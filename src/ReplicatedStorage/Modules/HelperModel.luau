--!strict
--[[
    HelperModel (ModuleScript) -> ReplicatedStorage.Modules.HelperModel
    Cuerpo de los AYUDANTES DE COMBATE: un mini personaje (cabeza grande, ~55% del tamaño de un jugador) hecho solo con bloques, sin descargar nada.
    Se construye en el CLIENTE (HelperFollowClient lo mueve; HelperClient/RecruitClient lo muestran en un ViewportFrame).
      - Aspecto por facción (HelperCatalog.Look: piel, pelo, ropa, peinado) y por rol (arma/escudo/arco/bastón en la mano).
      - Rareza: Raro chispas · Épico capa y luz · Legendario halo · Mítico alas. Un poco más grande cuanto más rara.
      - Rango (por nivel): 2 pañuelo · 4 hombreras · 6 anillo de aura a los pies · 8 emblema flotante de la facción · 10 partículas de aura.
        Ascensión: una esfera orbita su cintura por escalón. El color del aura sale de HelperCatalog.AuraColor (de facción, oro, cian... o Prisma, que cambia de color).
      - Raíz anclada (Root); el resto va pegado con Weld y los brazos/piernas se animan cambiando el C0 de cada Weld (HelperModel.Animate).
    API:
      HelperModel.Build(parsed, opts) -> Built       opts: { Scale, Tag = { Name, Sub?, MaxDistance? }?, Rank (1..13), Aura (índice de HelperCatalog.Auras), Asc (0..3) }
      HelperModel.Animate(b, t, speed, attack, cheer)  speed 0..1 (caminar) · attack -1 (nada) o 0..1 (progreso del golpe) · cheer 0..1 (celebración)
      HelperModel.SetTag(b, name, sub)                 cambia el cartel
      HelperModel.Burst(b)                             estallido de chispas (celebrar un rango, una ascensión o una rama)
    El frente del modelo es -Z. b.Feet = distancia (studs) de la raíz a los pies: apoya la raíz a b.Feet sobre el suelo.
]]
local HelperCatalog = require(script.Parent:WaitForChild("HelperCatalog"))

local HelperModel = {}

export type Limb = { Joint: CFrame, Parts: { { Weld: Weld, Off: CFrame } } }
export type Built = {
	Model: Model,
	Root: Part,
	Scale: number,
	Feet: number,
	Top: number,
	Role: string,
	Rarity: string,
	Phase: number,
	ArmL: Limb,
	ArmR: Limb,
	LegL: Limb,
	LegR: Limb,
	Cape: Limb?,
	WingL: Limb?,
	WingR: Limb?,
	Halo: Weld?,
	HaloY: number,
	Scarf: Limb?,
	Ring: Weld?, -- anillo de aura a los pies
	RingY: number,
	Emblem: Weld?, -- emblema flotante tras la espalda
	EmblemBase: Vector3,
	EmblemRot: CFrame,
	Orbs: { Weld }, -- una esfera por escalón de ascensión
	OrbRadius: number,
	OrbY: number,
	Tinted: { Part }, -- partes que toman el color del aura
	Prism: boolean,
	Aura: Color3,
	Emitters: { ParticleEmitter },
	Tag: BillboardGui?,
	NameLabel: TextLabel?,
	SubLabel: TextLabel?,
}

HelperModel.BaseScale = 0.55 -- un jugador mide ~5,5 studs; el ayudante, ~3
local RARITY_SCALE = { Comun = 1.0, Raro = 1.04, Epico = 1.08, Legendario = 1.12, Mitico = 1.18 } :: { [string]: number }

local function mk(model: Model, root: Part, shape: Enum.PartType, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?, transparency: number?): (Part, Weld)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p, w
end

local function darker(c: Color3, k: number): Color3
	return Color3.new(c.R * k, c.G * k, c.B * k)
end

export type BuildOpts = {
	Scale: number?,
	Tag: { Name: string, Sub: string?, MaxDistance: number? }?,
	Rank: number?,
	Aura: number?,
	Asc: number?,
}

function HelperModel.Build(parsed: HelperCatalog.Parsed, opts: BuildOpts?): Built
	local look = HelperCatalog.Look[parsed.Faction]
	local rarityIdx = HelperCatalog.RarityIndex[parsed.Rarity] or 1
	local rarityColor = HelperCatalog.RarityColor[parsed.Rarity] or Color3.new(1, 1, 1)
	local s = (if opts and opts.Scale then opts.Scale else HelperModel.BaseScale) * (RARITY_SCALE[parsed.Rarity] or 1)

	local model = Instance.new("Model")
	model.Name = "Ayudante"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local B, K, C = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	local V = Vector3.new
	local skin, hair, primary, secondary, accent = look.Skin, look.Hair, look.Primary, look.Secondary, look.Accent
	local dark = Color3.fromRGB(28, 24, 32)

	local function add(shape: Enum.PartType, size: Vector3, color: Color3, pos: Vector3, rot: CFrame?, mat: Enum.Material?, tr: number?): (Part, Weld)
		return mk(model, root, shape, size * s, color, CFrame.new(pos * s) * (rot or CFrame.identity), mat, tr)
	end
	local function newLimb(joint: Vector3): Limb
		return { Joint = CFrame.new(joint * s), Parts = {} }
	end
	local function limbPart(l: Limb, shape: Enum.PartType, size: Vector3, color: Color3, pos: Vector3, rot: CFrame?, mat: Enum.Material?, tr: number?): Part
		local off = CFrame.new(pos * s) * (rot or CFrame.identity)
		local p, w = mk(model, root, shape, size * s, color, l.Joint * off, mat, tr)
		table.insert(l.Parts, { Weld = w, Off = off })
		return p
	end

	-- piernas (articulación en la cadera) y zapatos
	local legL, legR = newLimb(V(-0.42, 0, 0)), newLimb(V(0.42, 0, 0))
	for _, leg in ipairs({ legL, legR }) do
		limbPart(leg, K, V(0.7, 1.05, 0.75), secondary, V(0, -0.55, 0))
		limbPart(leg, K, V(0.76, 0.38, 0.98), darker(secondary, 0.55), V(0, -1.2, -0.1), nil, Enum.Material.Leather)
	end
	-- torso, cinturón y emblema
	add(K, V(1.6, 1.7, 0.95), primary, V(0, 0.95, 0))
	add(K, V(1.66, 0.28, 1.0), accent, V(0, 0.2, 0), nil, Enum.Material.Metal)
	add(K, V(0.5, 0.5, 0.08), accent, V(0, 1.2, -0.5), nil, Enum.Material.Metal)
	add(K, V(1.0, 0.22, 0.98), darker(primary, 0.7), V(0, 1.78, 0)) -- cuello de la prenda
	-- cabeza, ojos, boca
	add(B, V(2.0, 2.0, 2.0), skin, V(0, 2.75, 0))
	for _, ex in ipairs({ -0.42, 0.42 }) do
		add(K, V(0.26, 0.44, 0.1), dark, V(ex, 2.7, -0.95))
		add(K, V(0.09, 0.12, 0.05), Color3.new(1, 1, 1), V(ex + 0.05, 2.82, -0.99))
	end
	add(K, V(0.4, 0.08, 0.06), dark, V(0, 2.28, -0.97))

	-- peinado / adorno de cabeza según la facción
	local style = look.HairStyle
	add(B, V(2.18, 2.1, 2.18), hair, V(0, 2.98, 0.32)) -- pelo (gorro)
	if style == "Spiky" then
		for i, a in ipairs({ -50, -25, 0, 25, 50 }) do
			add(K, V(0.5, 1.25, 0.5), hair, V(math.sin(math.rad(a)) * 0.95, 3.85, 0.25 + (if i % 2 == 0 then 0.1 else 0)), CFrame.Angles(0, 0, math.rad(-a * 0.8)))
		end
	elseif style == "Band" then
		add(C, V(0.42, 2.14, 2.14), accent, V(0, 3.05, 0), CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Fabric)
		add(K, V(0.9, 0.5, 0.1), Color3.fromRGB(205, 210, 222), V(0, 3.05, -1.08), nil, Enum.Material.Metal)
		add(K, V(0.35, 0.18, 0.9), accent, V(0.5, 3.0, 1.2), CFrame.Angles(0, math.rad(-25), 0), Enum.Material.Fabric)
	elseif style == "Bandana" then
		add(C, V(0.5, 2.16, 2.16), primary, V(0, 3.1, 0), CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Fabric)
		add(K, V(0.5, 0.5, 0.45), primary, V(0.4, 3.0, 1.15), nil, Enum.Material.Fabric)
		add(K, V(0.3, 0.9, 0.12), primary, V(0.55, 2.6, 1.25), CFrame.Angles(0, 0, math.rad(12)), Enum.Material.Fabric)
	elseif style == "Long" then
		add(K, V(1.9, 2.4, 0.5), hair, V(0, 2.25, 0.95))
		add(K, V(2.0, 0.5, 0.4), hair, V(0, 3.45, -0.72))
	end

	-- brazos (articulación en el hombro) y manos; el frente es -Z
	local armL, armR = newLimb(V(-1.1, 1.65, 0)), newLimb(V(1.1, 1.65, 0))
	for _, arm in ipairs({ armL, armR }) do
		limbPart(arm, K, V(0.55, 1.2, 0.6), primary, V(0, -0.55, 0))
		limbPart(arm, K, V(0.58, 0.3, 0.64), accent, V(0, -0.2, 0), nil, Enum.Material.Metal) -- brazalete
		limbPart(arm, B, V(0.56, 0.56, 0.56), skin, V(0, -1.2, 0))
	end

	-- arma del rol (se extiende hacia delante, -Z, desde la mano)
	local role = parsed.Role
	local steel = Color3.fromRGB(205, 212, 224)
	if role == "Guerrero" then
		limbPart(armR, K, V(0.15, 0.36, 2.3), steel, V(0, -1.2, -1.5), nil, Enum.Material.Metal)
		limbPart(armR, K, V(0.95, 0.2, 0.2), accent, V(0, -1.2, -0.45), nil, Enum.Material.Metal)
	elseif role == "Tanque" then
		limbPart(armR, K, V(0.2, 0.3, 1.4), steel, V(0, -1.2, -1.0), nil, Enum.Material.Metal)
		limbPart(armL, K, V(0.28, 2.0, 1.7), darker(secondary, 0.8), V(-0.55, -0.95, -0.3), nil, Enum.Material.Metal)
		limbPart(armL, K, V(0.34, 1.2, 1.0), accent, V(-0.62, -0.95, -0.3), nil, Enum.Material.Metal)
	elseif role == "Asesino" then
		for _, arm in ipairs({ armR, armL }) do
			limbPart(arm, K, V(0.1, 0.28, 1.3), Color3.fromRGB(60, 62, 76), V(0, -1.2, -0.95), nil, Enum.Material.Metal)
			limbPart(arm, K, V(0.12, 0.1, 1.0), accent, V(0, -1.08, -0.95), nil, Enum.Material.Neon)
		end
	elseif role == "Tirador" then
		limbPart(armL, K, V(0.16, 1.5, 0.16), Color3.fromRGB(110, 76, 44), V(0, -1.2, -0.9), CFrame.Angles(0, 0, 0), Enum.Material.Wood)
		limbPart(armL, K, V(0.16, 0.95, 0.16), Color3.fromRGB(110, 76, 44), V(0, -0.55, -0.62), CFrame.Angles(math.rad(-28), 0, 0), Enum.Material.Wood)
		limbPart(armL, K, V(0.16, 0.95, 0.16), Color3.fromRGB(110, 76, 44), V(0, -1.85, -0.62), CFrame.Angles(math.rad(28), 0, 0), Enum.Material.Wood)
		limbPart(armL, K, V(0.04, 2.5, 0.04), Color3.fromRGB(235, 235, 235), V(0, -1.2, -0.38))
		add(C, V(1.5, 0.55, 0.55), Color3.fromRGB(110, 76, 44), V(0.35, 1.2, 0.75), CFrame.Angles(math.rad(25), 0, math.rad(90)), Enum.Material.Leather) -- carcaj
		add(K, V(0.12, 0.5, 0.12), accent, V(0.3, 2.0, 0.85), CFrame.Angles(math.rad(25), 0, 0))
	elseif role == "Mago" then
		limbPart(armR, K, V(0.17, 3.0, 0.17), Color3.fromRGB(110, 76, 44), V(0, -1.0, -0.25), nil, Enum.Material.Wood)
		local orb = limbPart(armR, B, V(0.8, 0.8, 0.8), accent, V(0, 0.65, -0.25), nil, Enum.Material.Neon, 0.1)
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness = accent, 8, 1
		l.Parent = orb
	elseif role == "Curador" then
		limbPart(armR, K, V(0.17, 2.6, 0.17), Color3.fromRGB(235, 232, 220), V(0, -1.0, -0.25), nil, Enum.Material.Wood)
		limbPart(armR, K, V(0.7, 0.2, 0.2), Color3.fromRGB(255, 150, 200), V(0, 0.4, -0.25), nil, Enum.Material.Neon)
		limbPart(armR, K, V(0.2, 0.7, 0.2), Color3.fromRGB(255, 150, 200), V(0, 0.4, -0.25), nil, Enum.Material.Neon)
		add(K, V(0.9, 0.7, 0.45), Color3.fromRGB(110, 76, 44), V(-0.9, 0.35, 0.2), nil, Enum.Material.Leather) -- bolso
	end

	-- RAREZA
	local cape: Limb? = nil
	local wingL: Limb?, wingR: Limb? = nil, nil
	local haloWeld: Weld? = nil
	local haloY = 4.3 * s
	if rarityIdx >= 3 then
		cape = newLimb(V(0, 1.8, 0.55))
		limbPart(cape :: Limb, K, V(1.5, 2.0, 0.12), rarityColor, V(0, -1.0, 0.05), nil, Enum.Material.Fabric)
		limbPart(cape :: Limb, K, V(1.54, 0.2, 0.16), accent, V(0, -2.0, 0.05), nil, Enum.Material.Metal)
	end
	if rarityIdx >= 4 then
		local halo, w = add(C, V(0.14, 2.3, 2.3), rarityColor, V(0, 4.3, 0), CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Neon, 0.1)
		halo.Name = "Halo"
		haloWeld = w
	end
	if rarityIdx >= 5 then
		wingL, wingR = newLimb(V(-0.4, 1.7, 0.6)), newLimb(V(0.4, 1.7, 0.6))
		limbPart(wingL :: Limb, K, V(1.7, 1.9, 0.08), rarityColor, V(-0.9, 0.1, 0.2), CFrame.Angles(0, 0, math.rad(-18)), Enum.Material.Neon, 0.35)
		limbPart(wingR :: Limb, K, V(1.7, 1.9, 0.08), rarityColor, V(0.9, 0.1, 0.2), CFrame.Angles(0, 0, math.rad(18)), Enum.Material.Neon, 0.35)
	end
	if rarityIdx >= 2 then
		local em = Instance.new("ParticleEmitter")
		em.Rate = 2 + rarityIdx * 2
		em.Lifetime = NumberRange.new(0.8, 1.4)
		em.Speed = NumberRange.new(0.5, 1.5)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28 * s * 2), NumberSequenceKeypoint.new(1, 0) })
		em.LightEmission = 1
		em.Color = ColorSequence.new(rarityColor)
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		em.SpreadAngle = Vector2.new(180, 180)
		em.Parent = root
	end
	if rarityIdx >= 3 then
		local l = Instance.new("PointLight")
		l.Color = rarityColor
		l.Range = 6 + rarityIdx * 2
		l.Brightness = 0.7
		l.Parent = root
	end

	-- PROGRESO: rango, aura y ascensión
	local rank = if opts and opts.Rank then math.clamp(math.floor(opts.Rank), 1, HelperCatalog.MaxRank) else 1
	local auraIdx = if opts and opts.Aura then opts.Aura else 1
	local asc = if opts and opts.Asc then math.clamp(math.floor(opts.Asc), 0, HelperCatalog.MaxAsc) else 0
	local auraInfo = HelperCatalog.Auras[auraIdx] or HelperCatalog.Auras[1]
	local auraColor = HelperCatalog.AuraColor(auraIdx, parsed.Faction, 0)
	local tinted: { Part } = {}
	local emitters: { ParticleEmitter } = {}
	local scarf: Limb? = nil
	local ringWeld: Weld? = nil
	local emblemWeld: Weld? = nil
	local emblemRot = CFrame.identity
	local orbs: { Weld } = {}
	local ringY = -1.37 * s
	local emblemBase = V(0, 2.2, 1.4) * s

	if rank >= 2 then
		add(K, V(1.3, 0.3, 1.2), accent, V(0, 1.92, 0), nil, Enum.Material.Fabric)
		scarf = newLimb(V(0, 1.9, 0.55))
		limbPart(scarf :: Limb, K, V(0.4, 1.3, 0.12), accent, V(0.4, -0.55, 0.12), CFrame.Angles(0, 0, math.rad(6)), Enum.Material.Fabric)
		limbPart(scarf :: Limb, K, V(0.4, 0.2, 0.14), darker(accent, 0.6), V(0.4, -1.15, 0.12), CFrame.Angles(0, 0, math.rad(6)), Enum.Material.Fabric)
	end
	if rank >= 4 then
		for _, sx in ipairs({ -1.12, 1.12 }) do
			add(B, V(0.95, 0.7, 0.95), darker(primary, 0.55), V(sx, 1.82, 0), nil, Enum.Material.Metal)
			add(K, V(0.5, 0.12, 0.5), accent, V(sx, 2.12, 0), CFrame.Angles(0, math.rad(45), 0), Enum.Material.Metal)
		end
	end
	if rank >= 6 then
		local ring, rw = add(C, V(0.07, 3.6, 3.6), auraColor, V(0, ringY / s, 0), CFrame.Angles(0, 0, math.rad(90)), Enum.Material.Neon, 0.25)
		ring.Name = "AuraRing"
		ringWeld = rw
		table.insert(tinted, ring)
		local inner = mk(model, ring, C, V(0.05, 2.5, 2.5) * s, auraColor, CFrame.new(0.03 * s, 0, 0), Enum.Material.Neon, 0.55)
		table.insert(tinted, inner)
	end
	if rank >= 8 then
		-- emblema flotante: cada facción con su silueta; gira y se mece detrás de la espalda
		local shape: Part
		local w: Weld
		if parsed.Faction == "Saiyan" then
			emblemRot = CFrame.Angles(0, 0, math.rad(45))
			shape, w = add(K, V(0.8, 0.8, 0.14), auraColor, emblemBase / s, emblemRot, Enum.Material.Neon, 0.1)
		elseif parsed.Faction == "Shinobi" then
			emblemRot = CFrame.Angles(0, 0, math.rad(90))
			shape, w = add(C, V(0.12, 1.0, 1.0), auraColor, emblemBase / s, emblemRot, Enum.Material.Neon, 0.1)
			table.insert(tinted, (mk(model, shape, B, V(0.34, 0.34, 0.34) * s, auraColor, CFrame.identity, Enum.Material.Neon, 0)))
		elseif parsed.Faction == "Pirate" then
			emblemRot = CFrame.Angles(0, 0, math.rad(45))
			shape, w = add(K, V(0.22, 1.05, 0.14), auraColor, emblemBase / s, emblemRot, Enum.Material.Neon, 0.1)
			table.insert(tinted, (mk(model, shape, K, V(1.05, 0.22, 0.14) * s, auraColor, CFrame.identity, Enum.Material.Neon, 0.1)))
		else
			shape, w = add(B, V(0.7, 0.9, 0.7), auraColor, emblemBase / s, nil, Enum.Material.Neon, 0.2)
			table.insert(tinted, (mk(model, shape, B, V(0.34, 0.5, 0.34) * s, auraColor, CFrame.new(0, 0.55 * s, 0), Enum.Material.Neon, 0.2)))
		end
		shape.Name = "Emblema"
		table.insert(tinted, shape)
		emblemWeld = w
	end
	if rank >= 10 then
		local em = Instance.new("ParticleEmitter")
		em.Rate = 10 + (rank - 10) * 4
		em.Lifetime = NumberRange.new(1.0, 1.8)
		em.Speed = NumberRange.new(1.5, 3)
		em.Acceleration = Vector3.new(0, 2, 0)
		em.EmissionDirection = Enum.NormalId.Top
		em.SpreadAngle = Vector2.new(30, 30)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34 * s * 2), NumberSequenceKeypoint.new(1, 0) })
		em.LightEmission = 1
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		em.Color = ColorSequence.new(auraColor)
		em.Parent = root
		table.insert(emitters, em)
	end
	for i = 1, asc do
		local orb, ow = add(B, V(0.34, 0.34, 0.34), rarityColor:Lerp(Color3.new(1, 1, 1), 0.35), V(0, 1.0, 0), nil, Enum.Material.Neon, 0.05)
		orb.Name = "AscOrb" .. i
		table.insert(orbs, ow)
	end

	local built: Built = {
		Model = model,
		Root = root,
		Scale = s,
		Feet = 1.39 * s,
		Top = 3.95 * s,
		Role = role,
		Rarity = parsed.Rarity,
		Phase = math.random() * 6.28,
		ArmL = armL,
		ArmR = armR,
		LegL = legL,
		LegR = legR,
		Cape = cape,
		WingL = wingL,
		WingR = wingR,
		Halo = haloWeld,
		HaloY = haloY,
		Scarf = scarf,
		Ring = ringWeld,
		RingY = ringY,
		Emblem = emblemWeld,
		EmblemBase = emblemBase,
		EmblemRot = emblemRot,
		Orbs = orbs,
		OrbRadius = 1.9 * s,
		OrbY = 1.0 * s,
		Tinted = tinted,
		Prism = auraInfo.Prism == true,
		Aura = auraColor,
		Emitters = emitters,
		Tag = nil,
		NameLabel = nil,
		SubLabel = nil,
	}

	if opts and opts.Tag then
		local bb = Instance.new("BillboardGui")
		bb.Name = "Cartel"
		bb.Size = UDim2.fromOffset(240, 36)
		bb.StudsOffset = Vector3.new(0, built.Top + 1.0 * s + (if rarityIdx >= 4 then 0.6 else 0.3), 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = opts.Tag.MaxDistance or 45
		bb.Adornee = root
		bb.Parent = root
		local n = Instance.new("TextLabel")
		n.BackgroundTransparency = 1
		n.Size = UDim2.new(1, 0, 0.58, 0)
		n.Font = Enum.Font.GothamBold
		n.TextSize = 15
		n.TextColor3 = rarityColor
		n.TextStrokeTransparency = 0.35
		n.Text = opts.Tag.Name
		n.Parent = bb
		local sub = Instance.new("TextLabel")
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0, 0.58)
		sub.Size = UDim2.new(1, 0, 0.42, 0)
		sub.Font = Enum.Font.Gotham
		sub.TextSize = 11
		sub.TextColor3 = Color3.fromRGB(235, 235, 240)
		sub.TextStrokeTransparency = 0.5
		sub.Text = opts.Tag.Sub or ""
		sub.Parent = bb
		built.Tag, built.NameLabel, built.SubLabel = bb, n, sub
	end

	HelperModel.Animate(built, 0, 0, -1, 0)
	return built
end

local function pose(l: Limb, rot: CFrame)
	for _, e in ipairs(l.Parts) do
		e.Weld.C0 = l.Joint * rot * e.Off
	end
end

-- speed: 0..1 caminando · attack: -1 sin golpe, 0..1 progreso · cheer: 0..1 celebrando
function HelperModel.Animate(b: Built, t: number, speed: number, attack: number, cheer: number)
	local ph = b.Phase
	local swing = math.sin(t * 10 + ph) * 0.9 * speed
	local breathe = math.sin(t * 1.8 + ph) * 0.05 * (1 - speed)
	local staff = b.Role == "Mago" or b.Role == "Curador"
	local armBase = if staff then -0.18 else -0.5
	local rx = armBase + breathe - swing * 0.5
	local lx = (if b.Role == "Tirador" then -0.7 else -0.1) + breathe + swing * 0.5
	local rz, lz = 0.05, -0.05
	if attack >= 0 then
		local k = math.clamp(attack, 0, 1)
		rx = armBase - 1.9 * math.sin(k * math.pi)
		if b.Role == "Asesino" then
			lx = -0.1 - 1.6 * math.sin(math.clamp(k + 0.25, 0, 1) * math.pi)
		end
	end
	if cheer > 0 then
		local w = math.sin(t * 9 + ph) * 0.25
		rx = rx * (1 - cheer) + (-2.9 + w) * cheer
		lx = lx * (1 - cheer) + (-2.9 - w) * cheer
		rz, lz = rz * (1 - cheer) + 0.25 * cheer, lz * (1 - cheer) - 0.25 * cheer
	end
	pose(b.ArmR, CFrame.Angles(rx, 0, rz))
	pose(b.ArmL, CFrame.Angles(lx, 0, lz))
	pose(b.LegR, CFrame.Angles(swing, 0, 0))
	pose(b.LegL, CFrame.Angles(-swing, 0, 0))
	if b.Cape then
		pose(b.Cape, CFrame.Angles(0.12 + speed * 0.5 + math.sin(t * 2.4 + ph) * 0.07, 0, 0))
	end
	if b.WingL and b.WingR then
		local flap = math.sin(t * 5 + ph) * 0.25
		pose(b.WingL, CFrame.Angles(0, -(0.45 + flap), 0))
		pose(b.WingR, CFrame.Angles(0, 0.45 + flap, 0))
	end
	if b.Halo then
		b.Halo.C0 = CFrame.new(0, b.HaloY + math.sin(t * 2 + ph) * 0.08, 0) * CFrame.Angles(0, t * 2, math.pi / 2)
	end
	if b.Scarf then
		pose(b.Scarf, CFrame.Angles(0.2 + speed * 0.7 + math.sin(t * 3 + ph) * 0.09, math.sin(t * 2 + ph) * 0.08, 0))
	end
	if b.Ring then
		b.Ring.C0 = CFrame.new(0, b.RingY, 0) * CFrame.Angles(0, t * 1.1 + ph, math.pi / 2)
	end
	if b.Emblem then
		local bob = math.sin(t * 1.7 + ph) * 0.12 * b.Scale
		b.Emblem.C0 = CFrame.new(b.EmblemBase + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * 1.6, 0) * b.EmblemRot
	end
	local nOrbs = #b.Orbs
	for i, w in ipairs(b.Orbs) do
		local a = t * 1.7 + ph + (i - 1) * (2 * math.pi / math.max(1, nOrbs))
		w.C0 = CFrame.new(math.cos(a) * b.OrbRadius, b.OrbY + math.sin(a * 2) * 0.08 * b.Scale, math.sin(a) * b.OrbRadius)
	end
	if b.Prism then
		local c = Color3.fromHSV((t * 0.12 + ph) % 1, 0.55, 1)
		for _, p in ipairs(b.Tinted) do
			p.Color = c
		end
		for _, em in ipairs(b.Emitters) do
			em.Color = ColorSequence.new(c)
		end
	end
end

-- Estallido de chispas (una sola vez) alrededor del ayudante
function HelperModel.Burst(b: Built)
	local em = Instance.new("ParticleEmitter")
	em.Enabled = false
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.7, 1.4)
	em.Speed = NumberRange.new(5, 11)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * b.Scale * 2), NumberSequenceKeypoint.new(1, 0) })
	em.LightEmission = 1
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, b.Aura), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
	em.Parent = b.Root
	em:Emit(36)
	task.delay(2, function()
		em:Destroy()
	end)
end

function HelperModel.SetTag(b: Built, name: string, sub: string?)
	if b.NameLabel then
		b.NameLabel.Text = name
	end
	if b.SubLabel then
		b.SubLabel.Text = sub or ""
	end
end

return HelperModel
