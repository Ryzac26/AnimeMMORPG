--!strict
--[[
    HelperModel (ModuleScript) -> ReplicatedStorage.Modules.HelperModel
    Cuerpo de los AYUDANTES DE COMBATE. Se construye en el CLIENTE (HelperFollowClient lo mueve; HelperClient/RecruitClient lo muestran en un ViewportFrame).
      - CUERPO = COPIA DEL DUEÑO: se clona el personaje del invocador (cuerpo, ropa, accesorios, cara) y se escala (~55%, un poco más grande cuanto más
        rara). Se le quitan scripts, armas, efectos y cualquier cosa que no sea cuerpo. Todo queda anclado y las poses se resuelven a mano
        (cinemática por cada articulación: funciona igual en el mundo y en un ViewportFrame, con articulaciones Motor6D o AnimationConstraint).
      - ARMAS = las de cada clase (arma principal + pieza secundaria: escudo, segunda daga, carcaj, orbe, libro), construidas por el servidor
        (HelperProps) con las mismas funciones que los personajes y escaladas aquí al tamaño del ayudante. opts.Props = "<claveArma>|<clavePieza>".
      - Las mejoras visuales ya NO son capa/halo/alas/hombreras: ahora cada rareza tiene su AURA (la dibuja AuraClient a escala del ayudante).
      - Si no se puede copiar el cuerpo (el personaje del dueño aún no cargó), se usa un mini personaje de bloques de respaldo.
    API:
      HelperModel.Build(parsed, opts) -> Built    opts: { Scale, Tag = { Name, Sub?, MaxDistance? }?, Owner = Player?, Props = string? }
      HelperModel.Animate(b, t, speed, attack, cheer)  speed 0..1 (caminar) · attack -1 (nada) o 0..1 (progreso del golpe) · cheer 0..1 (celebración)
      HelperModel.SetTag(b, name, sub)                 cambia el cartel
      HelperModel.Burst(b)                             estallido de chispas (celebrar un rango, una ascensión o una rama)
      HelperModel.Pose(b)                              coloca cada pieza (necesario en un ViewportFrame: ahí no hay física)
      HelperModel.PropsSignature(props) -> string      cambia cuando una plantilla de armas termina de cargar (para rehacer al ayudante)
      HelperModel.AvatarReady(owner) -> boolean        ¿ya se puede copiar el personaje del dueño?
    El frente del modelo es -Z. b.Feet = distancia (studs) de la raíz a los pies: apoya la raíz a b.Feet sobre el suelo. b.AuraK = escala del aura.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local HelperCatalog = require(script.Parent:WaitForChild("HelperCatalog"))

local HelperModel = {}

export type Limb = { Joint: CFrame, Parts: { { Weld: Weld, Off: CFrame } } }
type Edge = { From: BasePart, To: BasePart, Inst: Instance, C0: CFrame, C1: CFrame, Fwd: boolean }
export type Rig = {
	IsR15: boolean,
	Root: BasePart,
	Edges: { Edge },
	Tf: { [Instance]: CFrame }, -- Transform actual de cada articulación
	J: { [string]: Instance }, -- RS LS RH LH RE LE RK LK Waist
	Cf: { [BasePart]: CFrame },
}
export type Built = {
	Model: Model,
	Root: BasePart,
	Scale: number,
	AuraK: number,
	Feet: number,
	Top: number,
	Role: string,
	Rarity: string,
	Phase: number,
	IsAvatar: boolean,
	Rig: Rig?,
	AtkStyle: string, -- animación de ataque (Slash, Stab, Slam, Thrust, Cast, Bow, Throw, Punch)
	Hold: { R: number?, L: number? }?, -- postura de los brazos con el arma en la mano
	AtkWas: boolean,
	AtkAlt: boolean,
	-- respaldo de bloques
	ArmL: Limb?,
	ArmR: Limb?,
	LegL: Limb?,
	LegR: Limb?,
	Tag: BillboardGui?,
	NameLabel: TextLabel?,
	SubLabel: TextLabel?,
}

HelperModel.BaseScale = 0.55 -- un jugador mide ~5,5 studs; el ayudante, ~3
local RARITY_SCALE = { Comun = 1.0, Raro = 1.04, Epico = 1.08, Legendario = 1.12, Mitico = 1.18 } :: { [string]: number }

---------------------------------------------------------------------
-- Animaciones de ataque (mismos ángulos que CharacterAnimClient: hombro derecho + = brazo adelante/arriba; izquierdo - = adelante/arriba)
---------------------------------------------------------------------
type Pair = { number }
type Pose = { RS: Pair?, LS: Pair?, RH: Pair?, LH: Pair? } -- {preparación, golpe}
local STYLES: { [string]: { Pose: Pose, Alt: boolean? } } = {
	Slash = { Pose = { RS = { 2.7, 0.9 }, LS = { -0.5, -0.2 }, RH = { 0.35, -0.3 }, LH = { -0.35, 0.3 } } },
	Slam = { Pose = { RS = { 3.1, 0.5 }, LS = { -3.1, -0.5 }, RH = { 0.3, -0.35 }, LH = { -0.3, 0.35 } } },
	Stab = { Alt = true, Pose = { RS = { -0.5, 1.55 }, LS = { -0.6, -0.9 }, RH = { 0.3, -0.35 }, LH = { -0.3, 0.35 } } },
	Thrust = { Pose = { RS = { 0.4, 1.7 }, LS = { -0.3, -1.3 }, RH = { 0.25, -0.3 }, LH = { -0.25, 0.3 } } },
	Punch = { Alt = true, Pose = { RS = { -0.7, 1.5 }, LS = { -1.1, -1.0 }, RH = { 0.3, -0.4 }, LH = { -0.3, 0.4 } } },
	Cast = { Pose = { RS = { 2.5, 1.45 }, LS = { -2.5, -1.45 }, RH = { 0.15, 0.15 }, LH = { -0.15, -0.15 } } },
	Throw = { Pose = { RS = { 2.7, 0.3 }, LS = { -0.8, -0.3 }, RH = { 0.3, -0.3 }, LH = { -0.3, 0.3 } } },
	Bow = { Pose = { RS = { 1.55, 0.35 }, LS = { -1.55, -1.55 }, RH = { 0.15, 0.15 }, LH = { -0.15, -0.15 } } },
}
local STRIKE = 0.45

-- Postura de "arma en la mano" mientras no ataca (igual que AttackAnimator.HOLD)
local HOLD: { [string]: { R: number?, L: number? } } = {
	Sword = { R = 0.9 }, Dagger = { R = 0.7 }, Axe = { R = 1.0 }, Spear = { R = 1.0 }, Staff = { R = 1.3, L = -0.4 }, Bow = { R = 0.35 },
}
local WEAPON_STYLE: { [string]: string } = { Sword = "Slash", Dagger = "Stab", Axe = "Slam", Spear = "Thrust", Bow = "Bow", Staff = "Cast" }

local function attackStyleOf(role: string, weapon: string?): string
	if role == "Mago" or role == "Curador" then
		return "Cast"
	elseif role == "Tirador" then
		return if weapon == "Bow" then "Bow" elseif weapon == "Dagger" then "Throw" else "Cast"
	end
	return WEAPON_STYLE[weapon or ""] or "Punch"
end

local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- ángulo en el instante p (0..1) del ataque: preparación -> golpe -> recuperación
local function atkAngle(pair: Pair, p: number, strike: number): number
	if p < strike then
		return lerp(0, pair[1], ease(p / strike))
	elseif p < strike + 0.22 then
		return lerp(pair[1], pair[2], ease((p - strike) / 0.22))
	end
	local r = math.clamp((p - strike - 0.22) / math.max(0.01, 1 - strike - 0.22), 0, 1)
	return lerp(pair[2], 0, ease(r))
end

---------------------------------------------------------------------
-- Copia del personaje del dueño
---------------------------------------------------------------------
local BODY: { [string]: boolean } = {
	Head = true, UpperTorso = true, LowerTorso = true, HumanoidRootPart = true,
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true, RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
	Torso = true, ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
}
local DROP_CLASSES = {
	"BaseScript", "ForceField", "Tool", "Animator", "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "PointLight", "SpotLight",
	"SurfaceLight", "Highlight", "BillboardGui", "SurfaceGui", "Sound", "ProximityPrompt", "ClickDetector",
}

type Template = { Model: Model, IsR15: boolean, HrpY: number }
local templates: { [Model]: Template } = setmetatable({}, { __mode = "k" }) :: any

local function avatarSource(owner: Player): Model?
	local char = owner.Character
	if not char or not char.Parent then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart") and char:FindFirstChild("Head") and char:FindFirstChildOfClass("Humanoid")) then
		return nil
	end
	local ok, loaded = pcall(function()
		return owner:HasAppearanceLoaded()
	end)
	if ok and not loaded then
		return nil
	end
	return char
end

function HelperModel.AvatarReady(owner: Player?): boolean
	return owner ~= nil and avatarSource(owner) ~= nil
end

-- Copia limpia (sin escalar) del personaje del dueño; se guarda una por personaje y se clona para cada ayudante
local function templateFor(owner: Player): Template?
	local char = avatarSource(owner)
	if not char then
		return nil
	end
	local cached = templates[char]
	if cached then
		return cached
	end
	local okClone, clone = pcall(function()
		return char:Clone()
	end)
	if not okClone or not clone then
		return nil
	end
	-- 1) solo cuerpo, ropa y accesorios (se va todo lo demás: carpetas de armas, burbujas, scripts...)
	for _, c in ipairs(clone:GetChildren()) do
		if c:IsA("BasePart") then
			if not BODY[c.Name] then
				c:Destroy()
			end
		elseif not (c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") or c:IsA("CharacterMesh") or c:IsA("BodyColors") or c:IsA("Humanoid")) then
			c:Destroy()
		end
	end
	-- 2) fuera efectos, scripts y sonidos en cualquier parte; sin etiquetas (para que nada del juego lo trate como jugador o monstruo)
	for _, d in ipairs(clone:GetDescendants()) do
		local drop = false
		for _, cls in ipairs(DROP_CLASSES) do
			if d:IsA(cls) then
				drop = true
				break
			end
		end
		if drop then
			d:Destroy()
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		for _, tag in ipairs(CollectionService:GetTags(d)) do
			d:RemoveTag(tag)
		end
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
		end
	end
	for _, tag in ipairs(CollectionService:GetTags(clone)) do
		clone:RemoveTag(tag)
	end
	for name in pairs(clone:GetAttributes()) do
		clone:SetAttribute(name, nil)
	end
	-- 3) humanoide inerte: solo sirve para que se dibuje la ropa; sin cartel, sin estados, sin física
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		pcall(function()
			(hum :: any).EvaluateStateMachine = false
		end)
	end
	local hrp = clone:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		clone:Destroy()
		return nil
	end
	clone.Name = "AyudanteCuerpo"
	local tpl: Template = { Model = clone, IsR15 = clone:FindFirstChild("UpperTorso") ~= nil, HrpY = hrp.Size.Y }
	templates[char] = tpl
	return tpl
end

-- Cinemática: grafo de piezas unidas por articulaciones (Motor6D, Weld, AnimationConstraint, WeldConstraint) a partir de la raíz
local function jointIn(model: Model, part: string, joint: string): Instance?
	local p = model:FindFirstChild(part)
	local j = if p then p:FindFirstChild(joint) else nil
	if j and (j:IsA("JointInstance") or j.ClassName == "AnimationConstraint") then
		return j
	end
	return nil
end

type Adj = { P0: BasePart, P1: BasePart, Inst: Instance, C0: CFrame, C1: CFrame }

local function buildRig(model: Model, root: BasePart, isR15: boolean): Rig
	local adj: { [BasePart]: { Adj } } = {}
	local function add(inst: Instance, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
		local e: Adj = { P0 = p0, P1 = p1, Inst = inst, C0 = c0, C1 = c1 }
		adj[p0] = adj[p0] or {}
		adj[p1] = adj[p1] or {}
		table.insert(adj[p0], e)
		table.insert(adj[p1], e)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") then
			local j = d :: JointInstance
			if j.Part0 and j.Part1 then
				add(d, j.Part0, j.Part1, j.C0, j.C1)
			end
		elseif d.ClassName == "AnimationConstraint" then
			local ac = d :: any
			local a0: Attachment? = ac.Attachment0
			local a1: Attachment? = ac.Attachment1
			local p0 = if a0 then a0.Parent else nil
			local p1 = if a1 then a1.Parent else nil
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				add(d, p0, p1, a0.CFrame, a1.CFrame)
			end
		elseif d:IsA("WeldConstraint") then
			local wc = d :: WeldConstraint
			if wc.Part0 and wc.Part1 then
				add(d, wc.Part0, wc.Part1, wc.Part0.CFrame:Inverse() * wc.Part1.CFrame, CFrame.identity)
			end
		end
	end
	local edges: { Edge } = {}
	local seen: { [BasePart]: boolean } = { [root] = true }
	local queue: { BasePart } = { root }
	local qi = 1
	while qi <= #queue do
		local a: BasePart = queue[qi]
		qi += 1
		local around: { Adj } = adj[a] or {}
		for _, e in ipairs(around) do
			local other = if e.P0 == a then e.P1 else e.P0
			if not seen[other] then
				seen[other] = true
				table.insert(edges, { From = a, To = other, Inst = e.Inst, C0 = e.C0, C1 = e.C1, Fwd = e.P0 == a })
				table.insert(queue, other)
			end
		end
	end
	-- piezas sueltas que no cuelgan de nada (se quedarían en el origen)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and not seen[d] then
			d:Destroy()
		end
	end
	local j: { [string]: Instance } = {}
	local function reg(key: string, inst: Instance?)
		if inst then
			j[key] = inst
		end
	end
	if isR15 then
		reg("RS", jointIn(model, "RightUpperArm", "RightShoulder"))
		reg("LS", jointIn(model, "LeftUpperArm", "LeftShoulder"))
		reg("RH", jointIn(model, "RightUpperLeg", "RightHip"))
		reg("LH", jointIn(model, "LeftUpperLeg", "LeftHip"))
		reg("RE", jointIn(model, "RightLowerArm", "RightElbow"))
		reg("LE", jointIn(model, "LeftLowerArm", "LeftElbow"))
		reg("RK", jointIn(model, "RightLowerLeg", "RightKnee"))
		reg("LK", jointIn(model, "LeftLowerLeg", "LeftKnee"))
		reg("Waist", jointIn(model, "UpperTorso", "Waist"))
	else
		reg("RS", jointIn(model, "Torso", "Right Shoulder"))
		reg("LS", jointIn(model, "Torso", "Left Shoulder"))
		reg("RH", jointIn(model, "Torso", "Right Hip"))
		reg("LH", jointIn(model, "Torso", "Left Hip"))
	end
	return { IsR15 = isR15, Root = root, Edges = edges, Tf = {}, J = j, Cf = {} }
end

-- Coloca todas las piezas a partir del CFrame de la raíz y las Transform actuales
local function solve(rig: Rig, rootCf: CFrame)
	local cf = rig.Cf
	cf[rig.Root] = rootCf
	rig.Root.CFrame = rootCf
	local tf = rig.Tf
	for _, e in ipairs(rig.Edges) do
		local base = cf[e.From]
		local t = tf[e.Inst] or CFrame.identity
		local result = if e.Fwd then base * (e.C0 * t * e.C1:Inverse()) else base * (e.C1 * t:Inverse() * e.C0:Inverse())
		cf[e.To] = result
		e.To.CFrame = result
	end
end

local function setArm(rig: Rig, left: boolean, a: number)
	local sh = rig.J[if left then "LS" else "RS"]
	if rig.IsR15 then
		local fwd = if left then -a else a
		if sh then
			rig.Tf[sh] = CFrame.Angles(fwd, 0, 0)
		end
		local el = rig.J[if left then "LE" else "RE"]
		if el then
			rig.Tf[el] = CFrame.Angles(math.clamp(fwd, 0, 3) * 0.55, 0, 0)
		end
	elseif sh then
		rig.Tf[sh] = CFrame.Angles(0, 0, a)
	end
end

local function setLeg(rig: Rig, left: boolean, a: number)
	local hip = rig.J[if left then "LH" else "RH"]
	if rig.IsR15 then
		local fwd = if left then -a else a
		if hip then
			rig.Tf[hip] = CFrame.Angles(fwd, 0, 0)
		end
		local knee = rig.J[if left then "LK" else "RK"]
		if knee then
			rig.Tf[knee] = CFrame.Angles(math.min(0, fwd) * 1.1, 0, 0)
		end
	elseif hip then
		rig.Tf[hip] = CFrame.Angles(0, 0, a)
	end
end

local function mirrorPair(p: Pair): Pair
	return { -p[1], -p[2] }
end

-- Altura de pies y cabeza (respecto a la raíz) con la pose de reposo; no cuenta las armas
local function extents(rig: Rig, model: Model): (number, number)
	solve(rig, CFrame.identity)
	local lo, hi = math.huge, -math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "WeaponPart" and d ~= rig.Root then
			local c, sz = d.CFrame, d.Size / 2
			local ext = math.abs(c.RightVector.Y) * sz.X + math.abs(c.UpVector.Y) * sz.Y + math.abs(c.LookVector.Y) * sz.Z
			lo = math.min(lo, c.Position.Y - ext)
			hi = math.max(hi, c.Position.Y + ext)
		end
	end
	if lo == math.huge then
		return 3, 3
	end
	return -lo, hi
end

---------------------------------------------------------------------
-- Armas (plantillas de HelperProps)
---------------------------------------------------------------------
local function propsFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("HelperProps")
end

function HelperModel.PropsSignature(props: string?): string
	if not props or props == "" then
		return ""
	end
	local folder = propsFolder()
	local out: { string } = {}
	for key in string.gmatch(props, "[^|]+") do
		local tpl = if folder then folder:FindFirstChild(key) else nil
		table.insert(out, key .. ":" .. (if tpl then tostring(tpl:GetAttribute("Rev")) else "x"))
	end
	return table.concat(out, "|")
end

-- Clona las piezas de cada plantilla sobre las manos/espalda del cuerpo y las escala a `k`
local function attachProps(model: Model, isR15: boolean, props: string?, k: number)
	local folder = propsFolder()
	if not props or props == "" or not folder then
		return
	end
	for key in string.gmatch(props, "[^|]+") do
		local tpl = folder:FindFirstChild(key)
		local variant = if tpl then tpl:FindFirstChild(if isR15 then "R15" else "R6") else nil
		if variant then
			local c = variant:Clone()
			local pieces = c:FindFirstChild("Pieces")
			if pieces then
				for _, d in ipairs(pieces:GetDescendants()) do
					if d:IsA("Weld") then
						local p0, p1 = d.Part0, d.Part1
						local real = if p0 then model:FindFirstChild(p0.Name, true) else nil
						if real and real:IsA("BasePart") and p1 then
							d.Part0 = real
							d.C0 = CFrame.new(d.C0.Position * k) * d.C0.Rotation
							d.C1 = CFrame.new(d.C1.Position * k) * d.C1.Rotation
							p1.Size = p1.Size * k
							for _, m in ipairs(p1:GetChildren()) do
								if m:IsA("SpecialMesh") then
									m.Scale = m.Scale * k
								end
							end
						elseif p1 then
							p1:Destroy()
						end
					end
				end
				for _, d in ipairs(pieces:GetDescendants()) do
					if d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.CastShadow = false
						d.Massless = true
					end
				end
				pieces.Name = "Props_" .. key
				pieces.Parent = model
			end
			c:Destroy()
		end
	end
end

local function weaponStyleOf(props: string?): string?
	if not props then
		return nil
	end
	local main = string.match(props, "^([^|]*)")
	return if main and main ~= "" then string.match(main, "^W_(%a+)_") else nil
end

---------------------------------------------------------------------
-- Cartel
---------------------------------------------------------------------
local function addTag(built: Built, opts: { Name: string, Sub: string?, MaxDistance: number? }, rarityColor: Color3, offset: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Cartel"
	bb.Size = UDim2.fromOffset(240, 36)
	bb.StudsOffset = Vector3.new(0, offset, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = opts.MaxDistance or 45
	bb.Adornee = built.Root
	bb.Parent = built.Root
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0.58, 0)
	n.Font = Enum.Font.GothamBold
	n.TextSize = 15
	n.TextColor3 = rarityColor
	n.TextStrokeTransparency = 0.35
	n.Text = opts.Name
	n.Parent = bb
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 11
	sub.TextColor3 = Color3.fromRGB(235, 235, 240)
	sub.TextStrokeTransparency = 0.5
	sub.Text = opts.Sub or ""
	sub.Parent = bb
	built.Tag, built.NameLabel, built.SubLabel = bb, n, sub
end

export type BuildOpts = {
	Scale: number?,
	Tag: { Name: string, Sub: string?, MaxDistance: number? }?,
	Owner: Player?,
	Props: string?,
}

---------------------------------------------------------------------
-- Cuerpo copiado del dueño
---------------------------------------------------------------------
local function buildAvatar(parsed: HelperCatalog.Parsed, opts: BuildOpts?, s: number): Built?
	local owner = if opts then opts.Owner else nil
	if not owner then
		return nil
	end
	local tpl = templateFor(owner)
	if not tpl then
		return nil
	end
	local model = tpl.Model:Clone()
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		model:Destroy()
		return nil
	end
	local okScale = pcall(function()
		model:ScaleTo(s)
	end)
	if not okScale or math.abs(hrp.Size.Y - tpl.HrpY * s) > math.max(0.05, tpl.HrpY * s * 0.1) then
		model:Destroy()
		return nil
	end
	local props = if opts then opts.Props else nil
	attachProps(model, tpl.IsR15, props, s)
	model.PrimaryPart = hrp
	local rig = buildRig(model, hrp, tpl.IsR15)
	local feet, top = extents(rig, model)
	local weapon = weaponStyleOf(props)
	local hold = if weapon then HOLD[weapon] else nil
	local built: Built = {
		Model = model,
		Root = hrp,
		Scale = s,
		AuraK = s,
		Feet = feet,
		Top = top,
		Role = parsed.Role,
		Rarity = parsed.Rarity,
		Phase = math.random() * 6.28,
		IsAvatar = true,
		Rig = rig,
		AtkStyle = attackStyleOf(parsed.Role, weapon),
		Hold = hold,
		AtkWas = false,
		AtkAlt = false,
		ArmL = nil,
		ArmR = nil,
		LegL = nil,
		LegR = nil,
		Tag = nil,
		NameLabel = nil,
		SubLabel = nil,
	}
	model.Name = "Ayudante"
	if opts and opts.Tag then
		addTag(built, opts.Tag, HelperCatalog.RarityColor[parsed.Rarity] or Color3.new(1, 1, 1), top + 0.7)
	end
	HelperModel.Animate(built, 0, 0, -1, 0)
	return built
end

---------------------------------------------------------------------
-- Respaldo: mini personaje de bloques
---------------------------------------------------------------------
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

local function buildBlock(parsed: HelperCatalog.Parsed, opts: BuildOpts?, s: number): Built
	local look = HelperCatalog.Look[parsed.Faction]
	local rarityColor = HelperCatalog.RarityColor[parsed.Rarity] or Color3.new(1, 1, 1)

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
		limbPart(armR, B, V(0.8, 0.8, 0.8), accent, V(0, 0.65, -0.25), nil, Enum.Material.Neon, 0.1)
	elseif role == "Curador" then
		limbPart(armR, K, V(0.17, 2.6, 0.17), Color3.fromRGB(235, 232, 220), V(0, -1.0, -0.25), nil, Enum.Material.Wood)
		limbPart(armR, K, V(0.7, 0.2, 0.2), Color3.fromRGB(255, 150, 200), V(0, 0.4, -0.25), nil, Enum.Material.Neon)
		limbPart(armR, K, V(0.2, 0.7, 0.2), Color3.fromRGB(255, 150, 200), V(0, 0.4, -0.25), nil, Enum.Material.Neon)
		add(K, V(0.9, 0.7, 0.45), Color3.fromRGB(110, 76, 44), V(-0.9, 0.35, 0.2), nil, Enum.Material.Leather) -- bolso
	end

	local built: Built = {
		Model = model,
		Root = root,
		Scale = s,
		AuraK = s,
		Feet = 1.39 * s,
		Top = 3.95 * s,
		Role = role,
		Rarity = parsed.Rarity,
		Phase = math.random() * 6.28,
		IsAvatar = false,
		Rig = nil,
		AtkStyle = "Slash",
		Hold = nil,
		AtkWas = false,
		AtkAlt = false,
		ArmL = armL,
		ArmR = armR,
		LegL = legL,
		LegR = legR,
		Tag = nil,
		NameLabel = nil,
		SubLabel = nil,
	}
	if opts and opts.Tag then
		addTag(built, opts.Tag, rarityColor, built.Top + 1.3 * s)
	end
	HelperModel.Animate(built, 0, 0, -1, 0)
	return built
end

function HelperModel.Build(parsed: HelperCatalog.Parsed, opts: BuildOpts?): Built
	local s = (if opts and opts.Scale then opts.Scale else HelperModel.BaseScale) * (RARITY_SCALE[parsed.Rarity] or 1)
	local ok, built = pcall(buildAvatar, parsed, opts, s)
	if ok and built then
		return built :: Built
	end
	if not ok then
		warn("[HelperModel] no se pudo copiar el cuerpo del dueño, se usa el de bloques: " .. tostring(built))
	end
	return buildBlock(parsed, opts, s)
end

---------------------------------------------------------------------
-- Animación
---------------------------------------------------------------------
local function poseLimb(l: Limb, rot: CFrame)
	for _, e in ipairs(l.Parts) do
		e.Weld.C0 = l.Joint * rot * e.Off
	end
end

-- Bloques: speed 0..1 caminando · attack -1 sin golpe, 0..1 progreso · cheer 0..1 celebrando
local function animateBlock(b: Built, t: number, speed: number, attack: number, cheer: number)
	local armL, armR, legL, legR = b.ArmL, b.ArmR, b.LegL, b.LegR
	if not (armL and armR and legL and legR) then
		return
	end
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
	poseLimb(armR, CFrame.Angles(rx, 0, rz))
	poseLimb(armL, CFrame.Angles(lx, 0, lz))
	poseLimb(legR, CFrame.Angles(swing, 0, 0))
	poseLimb(legL, CFrame.Angles(-swing, 0, 0))
end

-- Cuerpo copiado: mismas convenciones de ángulos que CharacterAnimClient
local function animateAvatar(b: Built, t: number, speed: number, attack: number, cheer: number)
	local rig = b.Rig
	if not rig then
		return
	end
	local ph = b.Phase
	local swing = math.sin(t * 10 + ph)
	local sway = math.sin(t * 1.8 + ph) * 0.05 * (1 - speed)
	local arms = swing * speed
	local legs = swing * 0.95 * speed
	local waist = rig.J.Waist
	if waist then
		rig.Tf[waist] = CFrame.Angles(-0.14 * speed, 0, 0)
	end
	-- brazos: con arma en la mano van en la postura de la clase (como los jugadores); sin arma, vaivén normal
	local armR = arms + sway
	local armL = arms - sway
	local hold = b.Hold
	if hold then
		if hold.R then
			armR = hold.R + arms * 0.25 + sway
		end
		if hold.L then
			armL = hold.L + arms * 0.25 - sway
		end
	end
	local rh, lh = -legs, -legs
	if attack >= 0 then
		if not b.AtkWas then
			b.AtkAlt = not b.AtkAlt
		end
		local def = STYLES[b.AtkStyle] or STYLES.Slash
		local mirror = def.Alt == true and b.AtkAlt
		local pose = def.Pose
		local function ang(pair: Pair?, fallback: number): number
			if not pair then
				return fallback
			end
			return atkAngle(if mirror then mirrorPair(pair) else pair, attack, STRIKE)
		end
		local rs, ls, rhp, lhp = pose.RS, pose.LS, pose.RH, pose.LH
		if mirror then
			rs, ls = ls, rs
			rhp, lhp = lhp, rhp
		end
		armR = ang(rs, armR)
		armL = ang(ls, armL)
		rh = ang(rhp, rh)
		lh = ang(lhp, lh)
	end
	b.AtkWas = attack >= 0
	if cheer > 0 then
		local w = math.sin(t * 9 + ph) * 0.25
		armR = armR * (1 - cheer) + (2.9 + w) * cheer
		armL = armL * (1 - cheer) + (-2.9 - w) * cheer
	end
	setArm(rig, false, armR)
	setArm(rig, true, armL)
	setLeg(rig, false, rh)
	setLeg(rig, true, lh)
	solve(rig, b.Root.CFrame)
end

function HelperModel.Animate(b: Built, t: number, speed: number, attack: number, cheer: number)
	if b.Rig then
		animateAvatar(b, t, speed, attack, cheer)
	else
		animateBlock(b, t, speed, attack, cheer)
	end
end

-- Soluciona los Weld a mano (cuerpo de bloques): cada pieza = Part0 * C0 * C1:Inverse(). Primero las pegadas a la raíz, luego las hijas de otras piezas.
local weldOrder: { [Model]: { Weld } } = setmetatable({}, { __mode = "k" }) :: any
function HelperModel.Pose(b: Built)
	if b.Rig then
		solve(b.Rig, b.Root.CFrame)
		return
	end
	local cached = weldOrder[b.Model]
	local list: { Weld } = cached or {}
	if not cached then
		local deferred: { Weld } = {}
		for _, d in ipairs(b.Model:GetDescendants()) do
			if d:IsA("Weld") then
				if d.Part0 == b.Root then
					table.insert(list, d)
				else
					table.insert(deferred, d)
				end
			end
		end
		for _, d in ipairs(deferred) do
			table.insert(list, d)
		end
		weldOrder[b.Model] = list
	end
	for _, w in ipairs(list) do
		local p0, p1 = w.Part0, w.Part1
		if p0 and p1 then
			p1.CFrame = p0.CFrame * w.C0 * w.C1:Inverse()
		end
	end
end

-- Estallido de chispas (una sola vez) alrededor del ayudante
function HelperModel.Burst(b: Built)
	local color = HelperCatalog.RarityColor[b.Rarity] or Color3.new(1, 1, 1)
	local em = Instance.new("ParticleEmitter")
	em.Enabled = false
	em.Rate = 0
	em.Lifetime = NumberRange.new(0.7, 1.4)
	em.Speed = NumberRange.new(5, 11)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * b.Scale * 2), NumberSequenceKeypoint.new(1, 0) })
	em.LightEmission = 1
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
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
