--!strict
--[[
    NpcBuilder (ModuleScript) -> ServerScriptService.Services.NpcBuilder
    Constructor compartido del CUERPO de los NPC de las ciudades. Cada servicio (Mercader, Herrero, Alquimista, Instructor, Mayordomo)
    conserva su puesto (yunque, caldero, cajones...), su cartel y su prompt; el personaje sale de aquí:
        local model, head = NpcBuilder.Person("Herrero", "Pirate", cf)     -- cf = centro del torso (pies a 3 studs por debajo)
    Cada pieza lleva el atributo "Grp" (Head / ArmL / ArmR / Body / LegL / LegR) para que NpcIdleClient la anime en el cliente
    (respiración, brazos, y la cabeza mira a quien se acerca). El modelo se etiqueta "NpcRig".
    Facciones: Saiyan · Shinobi · Pirate · Shinigami. Roles: Mercader · Herrero · Alquimista · Instructor · Mayordomo.
    Los diseños son originales (paleta de cada facción + atuendo del oficio), no copian a ningún personaje concreto.
]]
local CollectionService = game:GetService("CollectionService")

local NpcBuilder = {}

type Look = {
	Skin: Color3,
	Hair: Color3,
	Style: string, -- Spiky | Short | Long | Ponytail | Bun | Bald | Wild | Mohawk
	Brow: string, -- kind | stern | flat
	Main: Color3, -- prenda principal
	Main2: Color3, -- mangas / segunda prenda
	Pants: Color3,
	Accent: Color3,
	Beard: boolean?,
	Hat: string?, -- None | Tricorn | Bandana | Headband | Cap
	Scale: number?,
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local GOLD = c(240, 196, 90)
local LEATHER = c(110, 76, 50)
local DARK = c(36, 34, 42)
local WHITE = c(240, 240, 244)

local SKIN_A, SKIN_B, SKIN_C, SKIN_D = c(240, 205, 175), c(224, 178, 140), c(196, 148, 108), c(150, 106, 76)

-- LOOKS[rol][facción]
local LOOKS: { [string]: { [string]: Look } } = {
	Mercader = {
		Saiyan = { Skin = SKIN_B, Hair = c(48, 38, 34), Style = "Short", Brow = "kind", Main = c(214, 128, 52), Main2 = c(236, 226, 205), Pants = c(70, 82, 118), Accent = GOLD, Hat = "Cap" },
		Shinobi = { Skin = SKIN_A, Hair = c(60, 44, 38), Style = "Ponytail", Brow = "kind", Main = c(74, 104, 86), Main2 = c(226, 220, 200), Pants = c(46, 56, 76), Accent = c(210, 170, 90), Hat = "Headband" },
		Pirate = { Skin = SKIN_C, Hair = c(30, 26, 28), Style = "Short", Brow = "kind", Main = c(150, 40, 48), Main2 = c(236, 228, 210), Pants = c(60, 52, 60), Accent = GOLD, Hat = "Tricorn", Beard = true },
		Shinigami = { Skin = SKIN_A, Hair = c(50, 40, 46), Style = "Short", Brow = "kind", Main = c(84, 72, 120), Main2 = c(230, 226, 238), Pants = c(40, 38, 54), Accent = c(190, 170, 220), Hat = "None" },
	},
	Herrero = {
		Saiyan = { Skin = SKIN_B, Hair = c(40, 40, 52), Style = "Wild", Brow = "stern", Main = c(236, 238, 244), Main2 = c(70, 90, 140), Pants = c(70, 90, 140), Accent = c(120, 190, 235), Beard = true },
		Shinobi = { Skin = SKIN_A, Hair = c(70, 46, 34), Style = "Bun", Brow = "stern", Main = c(190, 62, 84), Main2 = c(226, 214, 196), Pants = c(66, 58, 56), Accent = c(230, 190, 100) },
		Pirate = { Skin = SKIN_C, Hair = c(60, 150, 210), Style = "Mohawk", Brow = "stern", Main = c(40, 150, 200), Main2 = c(236, 236, 240), Pants = c(35, 70, 140), Accent = c(235, 90, 90), Beard = false },
		Shinigami = { Skin = SKIN_A, Hair = c(214, 210, 200), Style = "Wild", Brow = "stern", Main = c(236, 236, 244), Main2 = c(46, 46, 60), Pants = c(30, 30, 42), Accent = c(200, 60, 70), Beard = true },
	},
	Alquimista = {
		Saiyan = { Skin = SKIN_A, Hair = c(100, 200, 200), Style = "Long", Brow = "kind", Main = WHITE, Main2 = c(100, 150, 210), Pants = c(70, 110, 170), Accent = c(110, 230, 220) },
		Shinobi = { Skin = SKIN_A, Hair = c(40, 34, 40), Style = "Short", Brow = "kind", Main = c(44, 50, 66), Main2 = c(240, 236, 232), Pants = c(40, 44, 58), Accent = c(150, 230, 170) },
		Pirate = { Skin = SKIN_D, Hair = c(110, 70, 50), Style = "Bun", Brow = "kind", Main = c(235, 96, 116), Main2 = c(250, 240, 232), Pants = c(150, 60, 70), Accent = c(255, 210, 120), Hat = "Cap" },
		Shinigami = { Skin = SKIN_B, Hair = c(240, 222, 100), Style = "Spiky", Brow = "stern", Main = WHITE, Main2 = c(34, 34, 46), Pants = c(34, 34, 46), Accent = c(220, 120, 255) },
	},
	Instructor = {
		Saiyan = { Skin = SKIN_B, Hair = c(240, 240, 240), Style = "Wild", Brow = "stern", Main = c(234, 130, 42), Main2 = c(236, 130, 42), Pants = c(60, 90, 160), Accent = c(60, 90, 160), Beard = true },
		Shinobi = { Skin = SKIN_A, Hair = c(70, 46, 36), Style = "Ponytail", Brow = "stern", Main = c(64, 92, 74), Main2 = c(56, 80, 66), Pants = c(40, 50, 90), Accent = c(220, 210, 190), Hat = "Headband" },
		Pirate = { Skin = SKIN_C, Hair = c(232, 228, 212), Style = "Long", Brow = "stern", Main = c(236, 236, 240), Main2 = c(236, 236, 240), Pants = c(60, 60, 78), Accent = GOLD, Beard = true },
		Shinigami = { Skin = SKIN_B, Hair = c(236, 236, 236), Style = "Wild", Brow = "stern", Main = c(30, 30, 40), Main2 = c(30, 30, 40), Pants = c(30, 30, 40), Accent = WHITE, Beard = true },
	},
	Mayordomo = {
		Saiyan = { Skin = SKIN_A, Hair = c(46, 40, 40), Style = "Short", Brow = "kind", Main = c(110, 40, 70), Main2 = c(110, 40, 70), Pants = c(40, 34, 44), Accent = GOLD },
		Shinobi = { Skin = SKIN_A, Hair = c(46, 40, 40), Style = "Short", Brow = "kind", Main = c(110, 40, 70), Main2 = c(110, 40, 70), Pants = c(40, 34, 44), Accent = GOLD },
		Pirate = { Skin = SKIN_A, Hair = c(46, 40, 40), Style = "Short", Brow = "kind", Main = c(110, 40, 70), Main2 = c(110, 40, 70), Pants = c(40, 34, 44), Accent = GOLD },
		Shinigami = { Skin = SKIN_A, Hair = c(46, 40, 40), Style = "Short", Brow = "kind", Main = c(110, 40, 70), Main2 = c(110, 40, 70), Pants = c(40, 34, 44), Accent = GOLD },
	},
}

function NpcBuilder.Person(role: string, faction: string, cf: CFrame): (Model, Part)
	local look: Look = (LOOKS[role] or LOOKS.Mercader)[faction] or LOOKS.Mercader.Saiyan
	local model = Instance.new("Model")
	model.Name = "Npc"
	CollectionService:AddTag(model, "NpcRig")

	local function make(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material?, grp: string?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.CFrame = cf * off
		p.Color = color
		p.Material = mat or Enum.Material.SmoothPlastic
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		if shape then
			p.Shape = shape
		end
		p:SetAttribute("Grp", grp or "Body")
		p.Parent = model
		return p
	end
	local function C(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end
	local function R(x: number, y: number, z: number): CFrame
		return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	local function emitter(p: BasePart, color: Color3, rate: number, speed: number, size: number, life: number, accel: Vector3?)
		local e = Instance.new("ParticleEmitter")
		e.Rate = rate
		e.Lifetime = NumberRange.new(life * 0.7, life)
		e.Speed = NumberRange.new(speed * 0.6, speed)
		e.SpreadAngle = Vector2.new(35, 35)
		e.Size = NumberSequence.new(size, 0)
		e.Color = ColorSequence.new(color)
		e.LightEmission = 0.8
		e.Transparency = NumberSequence.new(0.1, 1)
		e.Acceleration = accel or Vector3.new(0, 2, 0)
		e.Parent = p
	end

	-- RAÍZ (invisible, con colisión: el prompt y la posición cuelgan de ella)
	local root = make("HumanoidRootPart", Vector3.new(2, 2, 1), C(0, 0, 0), look.Main, nil, "Body")
	root.Transparency = 1
	root.CanCollide = true
	model.PrimaryPart = root

	local isKimono = faction == "Shinigami"
	local isCoat = faction == "Pirate"

	-- TORSO y piernas
	make("Torso", Vector3.new(2, 2, 1), C(0, 0, 0), look.Main, if role == "Alquimista" then Enum.Material.Fabric else Enum.Material.Fabric, "Body")
	local legColor = look.Pants
	if isKimono and role ~= "Alquimista" then
		-- hakama: pernera ancha
		make("PiernaIzq", Vector3.new(1.15, 2, 1.15), C(-0.55, -2, 0), legColor, Enum.Material.Fabric, "LegL")
		make("PiernaDer", Vector3.new(1.15, 2, 1.15), C(0.55, -2, 0), legColor, Enum.Material.Fabric, "LegR")
	else
		make("PiernaIzq", Vector3.new(1, 2, 1), C(-0.5, -2, 0), legColor, Enum.Material.Fabric, "LegL")
		make("PiernaDer", Vector3.new(1, 2, 1), C(0.5, -2, 0), legColor, Enum.Material.Fabric, "LegR")
	end
	-- botas / sandalias
	local bootColor = if faction == "Shinobi" then c(40, 40, 52) elseif faction == "Pirate" then c(60, 40, 30) elseif faction == "Saiyan" then c(190, 70, 56) else c(236, 232, 224)
	local bootH = if faction == "Pirate" or faction == "Saiyan" then 1.2 else 0.5
	make("BotaIzq", Vector3.new(1.1, bootH, 1.25), C(-0.5, -3 + bootH / 2, -0.07), bootColor, Enum.Material.Leather, "LegL")
	make("BotaDer", Vector3.new(1.1, bootH, 1.25), C(0.5, -3 + bootH / 2, -0.07), bootColor, Enum.Material.Leather, "LegR")
	if faction == "Pirate" then
		make("PunoBotaI", Vector3.new(1.25, 0.35, 1.35), C(-0.5, -1.75, -0.05), look.Accent, Enum.Material.Leather, "LegL")
		make("PunoBotaD", Vector3.new(1.25, 0.35, 1.35), C(0.5, -1.75, -0.05), look.Accent, Enum.Material.Leather, "LegR")
	elseif faction == "Saiyan" then
		make("BotaOroI", Vector3.new(1.15, 0.25, 1.3), C(-0.5, -1.85, -0.07), GOLD, Enum.Material.Metal, "LegL")
		make("BotaOroD", Vector3.new(1.15, 0.25, 1.3), C(0.5, -1.85, -0.07), GOLD, Enum.Material.Metal, "LegR")
	end

	-- FALDA / KIMONO
	if isKimono then
		make("FaldaKimono", Vector3.new(2.3, 2.5, 1.4), C(0, -1.9, 0), look.Main, Enum.Material.Fabric, "Body")
		make("Obi", Vector3.new(2.15, 0.65, 1.15), C(0, -0.7, 0), look.Accent, Enum.Material.Fabric, "Body")
		make("ObiNudo", Vector3.new(0.9, 0.7, 0.35), C(0, -0.7, 0.7), look.Accent, Enum.Material.Fabric, "Body")
		-- cuello en V del kimono interior
		make("CuelloI", Vector3.new(0.4, 1.5, 0.12), C(-0.28, 0.35, -0.55) * R(0, 0, -18), WHITE, Enum.Material.Fabric, "Body")
		make("CuelloD", Vector3.new(0.4, 1.5, 0.12), C(0.28, 0.35, -0.55) * R(0, 0, 18), WHITE, Enum.Material.Fabric, "Body")
	end

	-- CUELLO DEL ABRIGO + CAPA (piratas) / CHALECO (shinobi) / PETO (saiyan)
	if faction == "Pirate" then
		make("AbrigoEspalda", Vector3.new(2.3, 3.2, 0.25), C(0, -0.9, 0.62) * R(-4, 0, 0), look.Accent, Enum.Material.Fabric, "Body")
		make("SolapaI", Vector3.new(0.55, 1.8, 0.15), C(-0.7, 0.1, -0.55) * R(0, 0, 8), look.Accent, Enum.Material.Fabric, "Body")
		make("SolapaD", Vector3.new(0.55, 1.8, 0.15), C(0.7, 0.1, -0.55) * R(0, 0, -8), look.Accent, Enum.Material.Fabric, "Body")
		make("Cinto", Vector3.new(2.2, 0.38, 1.15), C(0, -0.75, 0), c(38, 28, 24), Enum.Material.Leather, "Body")
		make("Hebilla", Vector3.new(0.55, 0.45, 0.12), C(0, -0.75, -0.6), GOLD, Enum.Material.Metal, "Body")
		make("Faja", Vector3.new(2.15, 0.5, 1.1), C(0, -0.35, 0), c(200, 60, 56), Enum.Material.Fabric, "Body")
	elseif faction == "Shinobi" then
		make("Chaleco", Vector3.new(2.15, 1.75, 1.12), C(0, 0.1, 0), c(70, 86, 74), Enum.Material.Fabric, "Body")
		for _, sx in ipairs({ -0.62, 0.62 }) do
			make("Bolsillo", Vector3.new(0.6, 0.55, 0.18), C(sx, -0.1, -0.6), c(54, 68, 58), Enum.Material.Fabric, "Body")
		end
		make("Cinta", Vector3.new(2.15, 0.3, 1.14), C(0, -0.8, 0), c(36, 36, 48), Enum.Material.Fabric, "Body")
		make("Cuello", Vector3.new(1.9, 0.35, 1.1), C(0, 0.95, 0), c(54, 68, 58), Enum.Material.Fabric, "Body")
	elseif faction == "Saiyan" then
		make("Peto", Vector3.new(2.15, 1.45, 1.15), C(0, 0.22, 0), look.Main2, Enum.Material.Metal, "Body")
		make("PetoBorde", Vector3.new(2.25, 0.2, 1.22), C(0, 0.95, 0), GOLD, Enum.Material.Metal, "Body")
		make("PetoEmblema", Vector3.new(0.6, 0.6, 0.1), C(0, 0.35, -0.6), look.Accent, Enum.Material.Neon, "Body")
		make("Cinto", Vector3.new(2.2, 0.4, 1.12), C(0, -0.75, 0), c(40, 36, 44), Enum.Material.Leather, "Body")
		make("TelaCintura", Vector3.new(0.9, 1.1, 0.18), C(0.6, -1.3, -0.58), look.Accent, Enum.Material.Fabric, "Body")
	end

	-- BRAZOS: origen en el hombro; geometría hacia abajo. pose = inclinación hacia adelante (grados)
	local function arm(side: number, pitch: number, roll: number)
		local grp = if side < 0 then "ArmL" else "ArmR"
		local base = C(side * 1.5, 1, 0) * R(pitch, 0, roll)
		local sleeveWide = isKimono and role ~= "Alquimista"
		local sleeveColor = if role == "Alquimista" or role == "Mayordomo" or role == "Instructor" or sleeveWide or isCoat then look.Main2 else look.Skin
		if faction == "Saiyan" or faction == "Shinobi" then
			sleeveColor = if role == "Herrero" then look.Skin else look.Skin
		end
		if role == "Alquimista" or role == "Mayordomo" or (role == "Instructor" and faction ~= "Saiyan") then
			sleeveColor = look.Main2
		end
		if sleeveWide then
			make("BrazoManga", Vector3.new(1.55, 1.5, 1.3), base * C(0, -0.85, 0), look.Main, Enum.Material.Fabric, grp)
			make("BrazoMangaBorde", Vector3.new(1.6, 0.2, 1.35), base * C(0, -1.55, 0), WHITE, Enum.Material.Fabric, grp)
		else
			local thick = if role == "Herrero" then 1.18 else 1
			local nm = if side < 0 then "BrazoIzq" else "BrazoDer"
			make(nm, Vector3.new(thick, 1.75, thick), base * C(0, -0.95, 0), sleeveColor, Enum.Material.Fabric, grp)
		end
		-- mano
		make(if side < 0 then "ManoIzq" else "ManoDer", Vector3.new(0.9, 0.55, 0.9), base * C(0, -1.88, 0), look.Skin, nil, grp)
		-- adornos de brazo por facción
		if faction == "Saiyan" then
			make("Muneca", Vector3.new(1.1, 0.3, 1.1), base * C(0, -1.55, 0), look.Accent, Enum.Material.Fabric, grp)
			make("Hombrera", Vector3.new(1.5, 0.5, 1.4), base * C(side * 0.1, 0.1, 0), look.Main2, Enum.Material.Metal, grp)
			make("HombreraOro", Vector3.new(1.55, 0.14, 1.45), base * C(side * 0.1, 0.38, 0), GOLD, Enum.Material.Metal, grp)
		elseif faction == "Shinobi" then
			make("Venda", Vector3.new(1.08, 0.7, 1.08), base * C(0, -1.4, 0), c(232, 226, 210), Enum.Material.Fabric, grp)
		elseif faction == "Pirate" then
			make("PunoCamisa", Vector3.new(1.15, 0.4, 1.15), base * C(0, -1.55, 0), WHITE, Enum.Material.Fabric, grp)
		end
	end

	-- CABEZA
	local head = make("Head", Vector3.new(1.3, 1.3, 1.3), C(0, 1.65, 0), look.Skin, nil, "Head")
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	make("Cuello", Vector3.new(0.7, 0.3, 0.7), C(0, 1.1, 0), look.Skin, nil, "Head")
	-- cejas (dan carácter)
	local tilt = if look.Brow == "stern" then 14 elseif look.Brow == "kind" then -10 else 0
	local browColor = if look.Hair.R > 0.8 and look.Hair.G > 0.8 then c(200, 196, 190) else look.Hair
	make("CejaI", Vector3.new(0.42, 0.11, 0.1), C(-0.28, 2.0, -0.66) * R(0, 0, -tilt), browColor, nil, "Head")
	make("CejaD", Vector3.new(0.42, 0.11, 0.1), C(0.28, 2.0, -0.66) * R(0, 0, tilt), browColor, nil, "Head")
	if look.Beard then
		make("Barba", Vector3.new(1.1, 0.65, 0.4), C(0, 1.25, -0.5), look.Hair, Enum.Material.Fabric, "Head")
		make("Bigote", Vector3.new(0.9, 0.18, 0.3), C(0, 1.52, -0.66), look.Hair, Enum.Material.Fabric, "Head")
	end

	-- PEINADO
	local hc = look.Hair
	local style = look.Style
	if style ~= "Bald" then
		make("PeloBase", Vector3.new(1.42, 0.5, 1.42), C(0, 2.28, 0.04), hc, Enum.Material.Fabric, "Head")
		make("PeloAtras", Vector3.new(1.42, 0.9, 0.3), C(0, 1.95, 0.62), hc, Enum.Material.Fabric, "Head")
		make("PeloIzq", Vector3.new(0.18, 0.7, 1.2), C(-0.7, 2.0, 0.1), hc, Enum.Material.Fabric, "Head")
		make("PeloDer", Vector3.new(0.18, 0.7, 1.2), C(0.7, 2.0, 0.1), hc, Enum.Material.Fabric, "Head")
	end
	if style == "Spiky" then
		for i, a in ipairs({ -40, -20, 0, 20, 40 }) do
			make("Pincho", Vector3.new(0.38, 1.1 + (if i == 3 then 0.4 else 0), 0.38), C(a / 55, 2.85, 0.05) * R(0, 0, -a * 0.6), hc, Enum.Material.Fabric, "Head")
		end
		make("Flequillo", Vector3.new(1.0, 0.35, 0.3), C(0.1, 2.12, -0.68) * R(0, 0, -8), hc, Enum.Material.Fabric, "Head")
	elseif style == "Short" then
		make("Flequillo", Vector3.new(1.3, 0.3, 0.28), C(0, 2.12, -0.68), hc, Enum.Material.Fabric, "Head")
	elseif style == "Long" then
		make("Melena", Vector3.new(1.5, 2.6, 0.35), C(0, 1.0, 0.7), hc, Enum.Material.Fabric, "Head")
		make("MechonI", Vector3.new(0.3, 1.6, 0.4), C(-0.75, 1.5, -0.35), hc, Enum.Material.Fabric, "Head")
		make("MechonD", Vector3.new(0.3, 1.6, 0.4), C(0.75, 1.5, -0.35), hc, Enum.Material.Fabric, "Head")
		make("Flequillo", Vector3.new(1.3, 0.3, 0.28), C(0, 2.12, -0.68) * R(0, 0, 6), hc, Enum.Material.Fabric, "Head")
	elseif style == "Ponytail" then
		make("Coleta", Vector3.new(0.55, 1.9, 0.55), C(0, 1.6, 0.95) * R(-14, 0, 0), hc, Enum.Material.Fabric, "Head")
		make("Liga", Vector3.new(0.65, 0.2, 0.65), C(0, 2.3, 0.78) * R(-14, 0, 0), look.Accent, Enum.Material.Fabric, "Head")
		make("Flequillo", Vector3.new(1.2, 0.3, 0.28), C(0.05, 2.12, -0.68), hc, Enum.Material.Fabric, "Head")
	elseif style == "Bun" then
		make("Mono", Vector3.new(0.85, 0.85, 0.85), C(0, 2.95, 0.15), hc, Enum.Material.Fabric, "Head", Enum.PartType.Ball)
		make("Palillo", Vector3.new(0.12, 0.12, 1.5), C(0, 2.95, 0.15) * R(0, 0, 25), GOLD, Enum.Material.Metal, "Head")
		make("Flequillo", Vector3.new(1.3, 0.3, 0.28), C(0, 2.12, -0.68), hc, Enum.Material.Fabric, "Head")
	elseif style == "Wild" then
		make("Melena", Vector3.new(1.7, 0.6, 1.7), C(0, 2.45, 0.1), hc, Enum.Material.Fabric, "Head")
		make("PatillaI", Vector3.new(0.35, 1.1, 0.7), C(-0.82, 1.6, -0.1), hc, Enum.Material.Fabric, "Head")
		make("PatillaD", Vector3.new(0.35, 1.1, 0.7), C(0.82, 1.6, -0.1), hc, Enum.Material.Fabric, "Head")
		make("MechonA", Vector3.new(0.4, 0.8, 0.4), C(-0.3, 2.95, 0), hc, Enum.Material.Fabric, "Head")
		make("MechonB", Vector3.new(0.4, 0.9, 0.4), C(0.3, 2.95, 0.1) * R(0, 0, -12), hc, Enum.Material.Fabric, "Head")
	elseif style == "Mohawk" then
		make("Cresta", Vector3.new(0.5, 1.2, 1.7), C(0, 2.7, 0.05), hc, Enum.Material.Fabric, "Head")
		make("CrestaPunta", Vector3.new(0.4, 0.6, 1.2), C(0, 3.4, 0.1) * R(-8, 0, 0), hc, Enum.Material.Fabric, "Head")
	end

	-- SOMBREROS / CINTAS
	if look.Hat == "Tricorn" then
		make("TricornioBase", Vector3.new(2.2, 0.2, 2.2), C(0, 2.6, 0), c(40, 30, 28), Enum.Material.Leather, "Head")
		make("TricornioCopa", Vector3.new(1.5, 0.7, 1.5), C(0, 3.0, 0), c(52, 40, 36), Enum.Material.Leather, "Head")
		make("TricornioFrente", Vector3.new(1.9, 0.45, 0.2), C(0, 2.95, -1.1) * R(25, 0, 0), c(52, 40, 36), Enum.Material.Leather, "Head")
		make("TricornioPluma", Vector3.new(0.18, 1.1, 0.35), C(0.7, 3.3, 0.2) * R(0, 0, -25), look.Accent, Enum.Material.Fabric, "Head")
		make("TricornioCinta", Vector3.new(1.55, 0.18, 1.55), C(0, 2.78, 0), GOLD, Enum.Material.Metal, "Head")
	elseif look.Hat == "Bandana" then
		make("Bandana", Vector3.new(1.5, 0.4, 1.5), C(0, 2.2, 0), look.Accent, Enum.Material.Fabric, "Head")
	elseif look.Hat == "Headband" then
		make("Banda", Vector3.new(1.48, 0.38, 1.48), C(0, 2.1, 0), c(40, 56, 96), Enum.Material.Fabric, "Head")
		make("BandaPlaca", Vector3.new(0.9, 0.34, 0.12), C(0, 2.1, -0.76), c(190, 198, 210), Enum.Material.Metal, "Head")
		make("BandaNudo", Vector3.new(0.3, 0.9, 0.2), C(0.2, 1.7, 0.78) * R(0, 0, 14), c(40, 56, 96), Enum.Material.Fabric, "Head")
	elseif look.Hat == "Cap" then
		make("Gorra", Vector3.new(1.5, 0.5, 1.5), C(0, 2.4, 0), look.Accent, Enum.Material.Fabric, "Head")
		make("GorraVisera", Vector3.new(1.3, 0.12, 0.6), C(0, 2.2, -0.95), look.Accent, Enum.Material.Fabric, "Head")
	end

	-- ======= ROLES =======
	if role == "Mercader" then
		arm(-1, 0, -4)
		arm(1, 0, 4)
		-- mochila enorme con rollo de dormir, farolillo y bolsa de monedas
		make("Mochila", Vector3.new(2.2, 2.6, 1.1), C(0, -0.1, 1.15), LEATHER, Enum.Material.Leather, "Body")
		make("MochilaTapa", Vector3.new(2.3, 0.6, 1.2), C(0, 1.3, 1.15), c(140, 100, 62), Enum.Material.Leather, "Body")
		make("Rollo", Vector3.new(2.6, 0.9, 0.9), C(0, 1.85, 1.2), look.Main2, Enum.Material.Fabric, "Body", Enum.PartType.Cylinder)
		make("CorreaI", Vector3.new(0.3, 2.4, 0.15), C(-0.7, 0.2, -0.55), LEATHER, Enum.Material.Leather, "Body")
		make("CorreaD", Vector3.new(0.3, 2.4, 0.15), C(0.7, 0.2, -0.55), LEATHER, Enum.Material.Leather, "Body")
		local lamp = make("Farolillo", Vector3.new(0.6, 0.8, 0.6), C(1.35, -1.2, 1.4), c(255, 214, 120), Enum.Material.Neon, "Body")
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Color = 14, 1, c(255, 214, 140)
		pl.Parent = lamp
		make("BolsaMonedas", Vector3.new(0.8, 0.9, 0.7), C(0.9, -1.15, -0.72), c(200, 170, 70), Enum.Material.Fabric, "Body")
		make("BolsaNudo", Vector3.new(0.4, 0.25, 0.4), C(0.9, -0.65, -0.72), c(120, 90, 40), Enum.Material.Fabric, "Body")
		make("CadenaOro", Vector3.new(1.3, 0.14, 0.14), C(0, 0.55, -0.55), GOLD, Enum.Material.Metal, "Body")
		make("Colgante", Vector3.new(0.35, 0.35, 0.12), C(0, 0.3, -0.58), look.Accent, Enum.Material.Metal, "Body")
	elseif role == "Herrero" then
		arm(-1, 0, -4)
		arm(1, -48, 6)
		-- delantal de cuero con manchas de hollín
		make("Delantal", Vector3.new(1.85, 2.5, 0.2), C(0, -0.3, -0.62), c(86, 60, 44), Enum.Material.Leather, "Body")
		make("DelantalPechera", Vector3.new(1.2, 0.9, 0.2), C(0, 1.0, -0.62), c(86, 60, 44), Enum.Material.Leather, "Body")
		make("Hollin", Vector3.new(0.7, 0.5, 0.05), C(-0.3, -0.2, -0.74), c(30, 26, 26), Enum.Material.Fabric, "Body")
		make("Herramientas", Vector3.new(1.4, 0.35, 0.2), C(0, -1.3, -0.74), c(64, 64, 72), Enum.Material.Metal, "Body")
		-- gafas de fragua sobre la frente
		make("GafaBanda", Vector3.new(1.4, 0.2, 1.4), C(0, 2.12, 0), LEATHER, Enum.Material.Leather, "Head")
		for _, sx in ipairs({ -0.33, 0.33 }) do
			local lens = make("GafaLente", Vector3.new(0.2, 0.55, 0.55), C(sx, 2.3, -0.75), c(255, 190, 90), Enum.Material.Glass, "Head", Enum.PartType.Cylinder)
			lens.CFrame = cf * C(sx, 2.3, -0.75) * R(0, 90, 0)
		end
		-- martillo en la mano derecha (brazo adelantado)
		local base = C(1.5, 1, 0) * R(-48, 0, 6)
		make("MartilloMango", Vector3.new(0.28, 2.6, 0.28), base * C(0, -1.9, -1.0) * R(90, 0, 0), c(120, 82, 50), Enum.Material.Wood, "ArmR")
		local mh = make("MartilloCabeza", Vector3.new(1.5, 0.9, 0.9), base * C(0, -1.9, -2.4), c(70, 72, 82), Enum.Material.Metal, "ArmR")
		emitter(mh, c(255, 150, 60), 6, 4, 0.2, 1, Vector3.new(0, -3, 0))
	elseif role == "Alquimista" then
		arm(-1, -38, -4)
		arm(1, 0, 4)
		-- bata larga + bandolera de viales + guantes
		make("BataE", Vector3.new(2.3, 3.4, 0.25), C(0, -1.0, 0.62), look.Main, Enum.Material.Fabric, "Body")
		make("BataI", Vector3.new(0.7, 3.0, 0.2), C(-0.85, -0.7, -0.6), look.Main, Enum.Material.Fabric, "Body")
		make("BataD", Vector3.new(0.7, 3.0, 0.2), C(0.85, -0.7, -0.6), look.Main, Enum.Material.Fabric, "Body")
		make("Bandolera", Vector3.new(0.35, 2.6, 0.18), C(0, 0.0, -0.64) * R(0, 0, 38), LEATHER, Enum.Material.Leather, "Body")
		local vialColors = { c(90, 160, 255), c(235, 80, 100), c(120, 255, 150) }
		for i, vc in ipairs(vialColors) do
			make("Vial", Vector3.new(0.34, 0.7, 0.34), C(-0.7 + (i - 1) * 0.62, 0.62 - (i - 1) * 0.6, -0.78), vc, Enum.Material.Glass, "Body")
		end
		-- gafas redondas en la frente
		make("GafaBanda", Vector3.new(1.4, 0.2, 1.4), C(0, 2.12, 0), look.Accent, Enum.Material.Metal, "Head")
		for _, sx in ipairs({ -0.33, 0.33 }) do
			local ring = make("GafaAro", Vector3.new(0.18, 0.6, 0.6), C(sx, 2.32, -0.75), look.Accent, Enum.Material.Metal, "Head", Enum.PartType.Cylinder)
			ring.CFrame = cf * C(sx, 2.32, -0.75) * R(0, 90, 0)
			local lens = make("GafaLente", Vector3.new(0.22, 0.45, 0.45), C(sx, 2.32, -0.77), c(160, 230, 255), Enum.Material.Glass, "Head", Enum.PartType.Cylinder)
			lens.CFrame = cf * C(sx, 2.32, -0.77) * R(0, 90, 0)
		end
		-- matraz burbujeante en la mano izquierda
		local base = C(-1.5, 1, 0) * R(-38, 0, -4)
		make("MatrazCuerpo", Vector3.new(1.0, 1.0, 1.0), base * C(0, -2.2, -0.5), look.Accent, Enum.Material.Glass, "ArmL", Enum.PartType.Ball)
		make("MatrazCuello", Vector3.new(0.4, 0.8, 0.4), base * C(0, -1.6, -0.5), c(220, 235, 240), Enum.Material.Glass, "ArmL")
		local liquid = make("MatrazLiquido", Vector3.new(0.8, 0.8, 0.8), base * C(0, -2.25, -0.5), look.Accent, Enum.Material.Neon, "ArmL", Enum.PartType.Ball)
		liquid.Transparency = 0.2
		emitter(liquid, look.Accent, 5, 2, 0.25, 1.6, Vector3.new(0, 3, 0))
	elseif role == "Instructor" then
		arm(-1, 0, -4)
		arm(1, -6, 6)
		-- cinturón de rango, bufanda y arma de entrenamiento según facción
		make("Cinturon", Vector3.new(2.15, 0.42, 1.12), C(0, -0.8, 0), c(30, 30, 34), Enum.Material.Leather, "Body")
		make("CinturonRango", Vector3.new(0.7, 0.5, 0.12), C(0, -0.8, -0.6), look.Accent, Enum.Material.Metal, "Body")
		if faction == "Pirate" or faction == "Shinigami" then
			-- capa/haori hasta las rodillas con borde
			make("Haori", Vector3.new(2.5, 3.4, 0.22), C(0, -0.7, 0.66), if faction == "Pirate" then c(46, 40, 70) else WHITE, Enum.Material.Fabric, "Body")
			make("HaoriBorde", Vector3.new(2.6, 0.22, 0.28), C(0, -2.4, 0.66), if faction == "Pirate" then GOLD else c(60, 60, 70), Enum.Material.Fabric, "Body")
			make("HaoriHombro", Vector3.new(2.5, 0.35, 1.2), C(0, 1.05, 0.1), if faction == "Pirate" then c(46, 40, 70) else WHITE, Enum.Material.Fabric, "Body")
		else
			make("Bufanda", Vector3.new(1.9, 0.5, 1.2), C(0, 1.0, 0), look.Accent, Enum.Material.Fabric, "Body")
			make("BufandaCola", Vector3.new(0.5, 1.8, 0.2), C(-0.5, 0.1, 0.66) * R(6, 0, 4), look.Accent, Enum.Material.Fabric, "Body")
		end
		-- arma al cinto (katana / sable / báculo)
		if faction == "Saiyan" then
			local base = C(1.5, 1, 0) * R(-6, 0, 6)
			make("Baston", Vector3.new(0.3, 6.6, 0.3), base * C(0.15, -1.2, -0.45), c(120, 80, 44), Enum.Material.Wood, "ArmR")
			local orb = make("BastonOrbe", Vector3.new(0.8, 0.8, 0.8), base * C(0.15, 2.1, -0.45), c(255, 214, 90), Enum.Material.Neon, "ArmR", Enum.PartType.Ball)
			emitter(orb, c(255, 220, 110), 6, 2, 0.25, 1.4)
		elseif faction == "Shinobi" then
			make("Vaina", Vector3.new(0.3, 3.4, 0.3), C(-1.3, -1.2, 0.2) * R(0, 0, 70), c(36, 36, 44), Enum.Material.Wood, "Body")
			make("Empunadura", Vector3.new(0.34, 1.0, 0.34), C(-0.2, -0.1, 0.2) * R(0, 0, 70), c(200, 190, 170), Enum.Material.Fabric, "Body")
			make("Pergamino", Vector3.new(1.6, 0.5, 0.5), C(0, 0.4, 0.9) * R(0, 0, 35), c(236, 226, 196), Enum.Material.Fabric, "Body", Enum.PartType.Cylinder)
		elseif faction == "Pirate" then
			make("Sable", Vector3.new(0.28, 3.6, 0.28), C(-1.35, -1.4, 0.15) * R(0, 0, 62), c(200, 206, 216), Enum.Material.Metal, "Body")
			make("SableGuarda", Vector3.new(0.9, 0.2, 0.9), C(-0.1, -0.05, 0.15) * R(0, 0, 62), GOLD, Enum.Material.Metal, "Body")
		else
			make("Katana", Vector3.new(0.28, 3.8, 0.28), C(-1.35, -1.4, 0.15) * R(0, 0, 66), c(30, 30, 38), Enum.Material.Wood, "Body")
			make("KatanaGuarda", Vector3.new(0.6, 0.18, 0.6), C(-0.15, -0.05, 0.15) * R(0, 0, 66), GOLD, Enum.Material.Metal, "Body")
		end
	elseif role == "Mayordomo" then
		arm(-1, 0, -4)
		arm(1, -42, 6)
		-- levita con vueltas doradas, pajarita, guantes y chaleco
		make("LevitaE", Vector3.new(2.3, 3.0, 0.25), C(0, -1.2, 0.62), look.Main, Enum.Material.Fabric, "Body")
		make("LevitaColaI", Vector3.new(0.9, 1.6, 0.2), C(-0.55, -2.8, 0.66), look.Main, Enum.Material.Fabric, "Body")
		make("LevitaColaD", Vector3.new(0.9, 1.6, 0.2), C(0.55, -2.8, 0.66), look.Main, Enum.Material.Fabric, "Body")
		make("Chaleco", Vector3.new(1.5, 1.7, 0.15), C(0, 0.1, -0.58), c(240, 232, 214), Enum.Material.Fabric, "Body")
		for i = 0, 2 do
			make("BotonOro", Vector3.new(0.18, 0.18, 0.1), C(0, 0.6 - i * 0.55, -0.68), GOLD, Enum.Material.Metal, "Body")
		end
		make("VueltaI", Vector3.new(0.55, 2.0, 0.14), C(-0.85, 0.1, -0.56) * R(0, 0, 6), GOLD, Enum.Material.Metal, "Body")
		make("VueltaD", Vector3.new(0.55, 2.0, 0.14), C(0.85, 0.1, -0.56) * R(0, 0, -6), GOLD, Enum.Material.Metal, "Body")
		make("PajaritaA", Vector3.new(0.55, 0.4, 0.2), C(-0.35, 0.92, -0.62), c(200, 50, 70), Enum.Material.Fabric, "Body")
		make("PajaritaB", Vector3.new(0.55, 0.4, 0.2), C(0.35, 0.92, -0.62), c(200, 50, 70), Enum.Material.Fabric, "Body")
		make("PajaritaN", Vector3.new(0.25, 0.25, 0.22), C(0, 0.92, -0.64), c(150, 30, 50), Enum.Material.Fabric, "Body")
		make("Faja", Vector3.new(2.15, 0.4, 1.1), C(0, -0.8, 0), GOLD, Enum.Material.Metal, "Body")
		-- sombrero de copa ladeado con ribete de oro y monóculo
		make("CopaBase", Vector3.new(1.9, 0.18, 1.9), C(0, 2.55, 0), look.Main, Enum.Material.Fabric, "Head")
		make("CopaTubo", Vector3.new(1.4, 1.3, 1.4), C(0, 3.2, 0), look.Main, Enum.Material.Fabric, "Head")
		make("CopaRibete", Vector3.new(1.46, 0.28, 1.46), C(0, 2.8, 0), GOLD, Enum.Material.Metal, "Head")
		local mon = make("Monoculo", Vector3.new(0.14, 0.5, 0.5), C(0.3, 1.78, -0.7), c(200, 230, 255), Enum.Material.Glass, "Head", Enum.PartType.Cylinder)
		mon.CFrame = cf * C(0.3, 1.78, -0.7) * R(0, 90, 0)
		make("MonoculoCadena", Vector3.new(0.06, 0.9, 0.06), C(0.45, 1.3, -0.66) * R(0, 0, -8), GOLD, Enum.Material.Metal, "Head")
		-- pergamino desplegado en la mano derecha, con destellos
		local base = C(1.5, 1, 0) * R(-42, 0, 6)
		local scroll = make("Pergamino", Vector3.new(1.5, 1.9, 0.12), base * C(0, -2.0, -0.7), c(246, 236, 206), Enum.Material.Fabric, "ArmR")
		make("PergaminoVaraA", Vector3.new(1.7, 0.18, 0.18), base * C(0, -1.05, -0.7), c(150, 100, 60), Enum.Material.Wood, "ArmR")
		make("PergaminoVaraB", Vector3.new(1.7, 0.18, 0.18), base * C(0, -2.95, -0.7), c(150, 100, 60), Enum.Material.Wood, "ArmR")
		for i = 0, 3 do
			make("Linea", Vector3.new(1.1, 0.07, 0.04), base * C(0, -1.4 - i * 0.4, -0.78), c(120, 90, 70), Enum.Material.Fabric, "ArmR")
		end
		emitter(scroll, GOLD, 4, 1.5, 0.2, 1.8)
	else
		arm(-1, 0, -4)
		arm(1, 0, 4)
	end

	-- ESCALA (pequeñas variaciones de estatura)
	if look.Scale and look.Scale ~= 1 then
		model:ScaleTo(look.Scale)
	end
	return model, head
end

return NpcBuilder
