--!strict
--[[
    CityLifeService (ModuleScript) -> ServerScriptService > Services > CityLifeService
    VIDA EN LAS CIUDADES: al fondo de cada comercio de las 4 facciones (se aplica solo, usando el marco de cada edificio):
      · Dojo del Instructor  : tatami de combate con cuerdas, 2 luchadores entrenando SIEMPRE (golpes, bloqueos y destello al impactar),
                               maniquíes de madera, estantes de bokken, estandarte y faroles.
      · Forja del Herrero    : 3 herreros forjando una espada sobre su yunque (al golpear saltan CHISPAS), horno con fuego,
                               barril de temple, espadas colgadas en la pared.
      · Bazar del Mercader   : góndolas de pociones al fondo (estantes en la pared + 2 islas de doble cara) con frascos de colores.
      · Pabellón VIP         : gente elegante charlando en 2 corrillos con copas, mesas, sofás, alfombra, lámpara de araña y GLOBOS DE CHARLA.
      · Laboratorio Alquimista: científicos con calderos burbujeantes, un frasco que revisan, destilador de cristal, estantes de pociones y tubos.
    Los personajes salen de NpcBuilder (diseños originales por facción). Sus movimientos (Act = Hammer / Spar / Mix / Hold / Chat)
    y las chispas los hace NpcIdleClient en cada cliente; aquí solo se construye el decorado y se anima el texto de los globos.
    Todo va dentro de una carpeta "Vida" del modelo de cada edificio (se borra y se rehace sola si se vuelve a correr).
    Para apagarlo: ENABLED = false.
]]
local Workspace = game:GetService("Workspace")

local NpcBuilder = require(script.Parent:WaitForChild("NpcBuilder"))

local ENABLED = true
local MAP_NAME = "Map_WC3_Style"

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

-- medidas de cada edificio (copia de BUILDINGS en ProjectBootstrapper)
local SPEC: { [number]: { Kind: string, W: number, D: number, H: number, Base: number } } = {
	[1] = { Kind = "dojo", W = 70, D = 50, H = 12, Base = 0 },
	[2] = { Kind = "forge", W = 50, D = 50, H = 12, Base = 0 },
	[3] = { Kind = "lab", W = 40, D = 40, H = 22, Base = 0 },
	[4] = { Kind = "bazaar", W = 40, D = 40, H = 10, Base = 0 },
	[6] = { Kind = "vip", W = 40, D = 40, H = 14, Base = 6 },
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

type Pal = { Wood: Color3, Dark: Color3, Glow: Color3, Cloth: Color3, Metal: Color3, Word: string }
local PAL: { [string]: Pal } = {
	Saiyan = { Wood = c(150, 110, 70), Dark = c(40, 48, 70), Glow = c(255, 170, 60), Cloth = c(214, 110, 40), Metal = c(150, 190, 235), Word = "SUPERA TUS LÍMITES" },
	Shinobi = { Wood = c(120, 85, 55), Dark = c(44, 52, 44), Glow = c(150, 230, 150), Cloth = c(80, 110, 80), Metal = c(205, 210, 215), Word = "DISCIPLINA" },
	Pirate = { Wood = c(110, 76, 50), Dark = c(52, 40, 36), Glow = c(255, 200, 90), Cloth = c(160, 45, 50), Metal = c(220, 190, 110), Word = "LIBERTAD" },
	Shinigami = { Wood = c(90, 80, 100), Dark = c(30, 32, 48), Glow = c(170, 160, 255), Cloth = c(70, 60, 110), Metal = c(205, 195, 235), Word = "HONOR" },
}

local POTION_COLORS = {
	c(255, 90, 110), c(90, 200, 255), c(120, 255, 150), c(255, 210, 90), c(200, 120, 255), c(255, 150, 70), c(90, 255, 230), c(255, 120, 200),
}

local LINES_VIP = {
	"¡Qué gala tan espléndida!", "El té de hoy es de primera.", "Dicen que el jefe del bosque cayó otra vez...", "¿Viste esa armadura legendaria?",
	"Mi mascota ya es legendaria.", "Aquí se respira otro nivel.", "Brindemos por los héroes.", "Los héroes de hoy ya no son como antes.",
	"Qué vista tan agradable.", "He oído que subes de nivel muy rápido.", "El oro fluye mejor aquí.", "Encantado de conocerle.",
}
local LINES_DOJO = { "¡Hyaa!", "¡Guardia arriba!", "Otra vez.", "Más rápido.", "¡Bien bloqueado!", "Respira y golpea.", "¡Eso es!" }
local LINES_FORGE = { "¡Más fuerte!", "Esa hoja quedará perfecta.", "¡Cuidado, está al rojo!", "Un golpe más...", "Buen acero, este.", "¡Qué chispas!" }
local LINES_LAB = { "¡Cuidado, hierve!", "Un poco más de espíritu...", "Esto huele a éxito.", "Anota la fórmula.", "¿Dos gotas o tres?", "¡Está burbujeando!" }

---------------------------------------------------------------------
-- Contexto de un edificio
---------------------------------------------------------------------
type Ctx = { Model: Model, F: CFrame, Fy: number, Folder: Folder, Pal: Pal, Faction: string, W: number, D: number, H: number, Rng: Random, N: number }

local function partCF(ctx: Ctx, name: string, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.CastShadow = size.Magnitude > 2.5
	p.CFrame = cf
	p.Parent = ctx.Folder
	return p
end

-- pos en coordenadas del edificio: x ancho, y sobre el piso, z profundidad (frente = -Z)
local function part(ctx: Ctx, name: string, pos: Vector3, size: Vector3, color: Color3, mat: Enum.Material, rot: CFrame?, shape: Enum.PartType?): Part
	return partCF(ctx, name, ctx.F * CFrame.new(pos.X, ctx.Fy + pos.Y, pos.Z) * (rot or CFrame.identity), size, color, mat, shape)
end

-- cilindro VERTICAL (altura h, diámetro d)
local function cyl(ctx: Ctx, name: string, pos: Vector3, h: number, d: number, color: Color3, mat: Enum.Material): Part
	return part(ctx, name, pos, Vector3.new(h, d, d), color, mat, CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
end

local function ball(ctx: Ctx, name: string, pos: Vector3, d: number, color: Color3, mat: Enum.Material): Part
	return part(ctx, name, pos, Vector3.one * d, color, mat, nil, Enum.PartType.Ball)
end

local function pointLight(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = p
end

local function sign(ctx: Ctx, pos: Vector3, size: Vector3, text: string, bg: Color3, fg: Color3, textSize: number)
	local p = part(ctx, "Cartel", pos, size, bg, Enum.Material.Fabric)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.Text = text
	t.TextColor3 = fg
	t.TextScaled = true
	t.Parent = gui
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = textSize
	limit.Parent = t
end

---------------------------------------------------------------------
-- Personajes
---------------------------------------------------------------------
local function tool(model: Model, cf: CFrame, grp: string, off: CFrame, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = "Herramienta"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.CFrame = cf * off
	p:SetAttribute("Grp", grp)
	p.Parent = model
	return p
end

-- crea un personaje de NpcBuilder y lo deja listo para NpcIdleClient (Act/Phase/Period). yaw en grados (0 = mira al frente del edificio)
local function actor(ctx: Ctx, role: string, lx: number, lz: number, yawDeg: number, act: string, phase: number, period: number): (Model, CFrame, Part)
	local cf = ctx.F * CFrame.new(lx, ctx.Fy + 3, lz) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local model, head = NpcBuilder.Person(role, ctx.Faction, cf)
	ctx.N += 1
	model.Name = string.format("Vida_%s_%d", act, ctx.N)
	model:SetAttribute("Act", act)
	model:SetAttribute("Phase", phase)
	model:SetAttribute("Period", period)
	local root = model.PrimaryPart
	if root then
		root.CanCollide = false
	end
	model.Parent = ctx.Folder
	return model, cf, head
end

-- globos de charla: cada tanto habla uno del grupo (texto distinto cada vez)
local function runChat(models: { Model }, heads: { Part }, lines: { string }, gap: number)
	local boxes: { { Bb: BillboardGui, Label: TextLabel } } = {}
	for _, head in ipairs(heads) do
		local bb = Instance.new("BillboardGui")
		bb.Name = "Globo"
		bb.Adornee = head
		bb.Size = UDim2.fromOffset(230, 54)
		bb.StudsOffset = Vector3.new(0, 2.6, 0)
		bb.MaxDistance = 65
		bb.LightInfluence = 0
		bb.Enabled = false
		bb.Parent = head
		local fr = Instance.new("Frame")
		fr.Size = UDim2.fromScale(1, 1)
		fr.BackgroundColor3 = Color3.fromRGB(252, 250, 244)
		fr.BackgroundTransparency = 0.08
		fr.Parent = bb
		local cr = Instance.new("UICorner")
		cr.CornerRadius = UDim.new(0, 12)
		cr.Parent = fr
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(60, 56, 70)
		st.Thickness = 1.5
		st.Parent = fr
		local lb = Instance.new("TextLabel")
		lb.BackgroundTransparency = 1
		lb.Size = UDim2.new(1, -14, 1, -8)
		lb.Position = UDim2.fromOffset(7, 4)
		lb.Font = Enum.Font.GothamMedium
		lb.TextColor3 = Color3.fromRGB(40, 36, 52)
		lb.TextScaled = true
		lb.TextWrapped = true
		lb.Text = ""
		lb.Parent = fr
		local lim = Instance.new("UITextSizeConstraint")
		lim.MaxTextSize = 18
		lim.Parent = lb
		table.insert(boxes, { Bb = bb, Label = lb })
	end
	task.spawn(function()
		local rng = Random.new()
		local last = 0
		task.wait(rng:NextNumber(0, 5))
		while models[1] and models[1].Parent do
			local idx = rng:NextInteger(1, #boxes)
			if idx == last and #boxes > 1 then
				idx = idx % #boxes + 1
			end
			last = idx
			local box = boxes[idx]
			box.Label.Text = lines[rng:NextInteger(1, #lines)]
			box.Bb.Enabled = true
			task.wait(gap * 0.7)
			box.Bb.Enabled = false
			task.wait(gap * 0.3 + rng:NextNumber(0.3, 1.5))
		end
	end)
end

---------------------------------------------------------------------
-- Piezas repetidas
---------------------------------------------------------------------
-- estante de pared o isla: ancho w a lo largo de X, tiers de frascos
local function shelfUnit(ctx: Ctx, cx: number, cz: number, w: number, tiers: number, rot: CFrame?, doubleSided: boolean)
	local depth = if doubleSided then 2.2 else 1.4
	local rr = rot or CFrame.identity
	local function lp(x: number, y: number, z: number): CFrame
		return ctx.F * CFrame.new(cx, ctx.Fy, cz) * rr * CFrame.new(x, y, z)
	end
	local height = 1.4 + tiers * 1.9
	for _, sx in ipairs({ -1, 1 }) do
		local post = partCF(ctx, "PosteEstante", lp(sx * (w / 2 - 0.2), height / 2, 0), Vector3.new(0.4, height, depth), ctx.Pal.Wood, Enum.Material.WoodPlanks)
		post.CanCollide = true
	end
	local backing = partCF(ctx, "FondoEstante", lp(0, height / 2, 0), Vector3.new(w, height, 0.2), ctx.Pal.Dark, Enum.Material.Wood)
	backing.CanCollide = not doubleSided
	for t = 1, tiers do
		local y = 0.9 + (t - 1) * 1.9
		partCF(ctx, "Tabla", lp(0, y, 0), Vector3.new(w, 0.25, depth), ctx.Pal.Wood, Enum.Material.WoodPlanks)
		local n = math.floor((w - 1.4) / 1.2)
		for k = 1, n do
			local x = -w / 2 + 1 + (k - 0.5) * ((w - 2) / n)
			local sides = if doubleSided then { -0.55, 0.55 } else { 0.25 }
			for si, zz in ipairs(sides) do
				local cf = lp(x, y + 0.125, zz)
				local col = POTION_COLORS[ctx.Rng:NextInteger(1, #POTION_COLORS)]
				local h = ctx.Rng:NextNumber(0.9, 1.5)
				local round = (k + t + si) % 3 == 0
				local b = partCF(
					ctx, "Frasco", cf * CFrame.new(0, (if round then 0.5 else h / 2), 0), if round then Vector3.one * 0.95 else Vector3.new(0.65, h, 0.65), col,
					if (k + t) % 4 == 0 then Enum.Material.Neon else Enum.Material.Glass, if round then Enum.PartType.Ball else nil
				)
				b.Transparency = if b.Material == Enum.Material.Glass then 0.25 else 0.1
			end
		end
	end
	partCF(ctx, "RemateEstante", lp(0, height + 0.15, 0), Vector3.new(w + 0.6, 0.3, depth + 0.3), ctx.Pal.Cloth, Enum.Material.Fabric)
end

local function glassCup(model: Model, cf: CFrame, grp: string, liquid: Color3, tiltComp: number)
	-- copa que queda recta en la pose final del brazo (se compensa la inclinación)
	local rest = cf * CFrame.new(-1.5, -0.88, 0) * CFrame.Angles(-tiltComp, 0, 0)
	local cup = tool(model, rest, grp, CFrame.new(0, 0.2, -0.35), Vector3.new(0.5, 0.7, 0.5), Color3.fromRGB(235, 245, 255), Enum.Material.Glass)
	cup.Transparency = 0.45
	tool(model, rest, grp, CFrame.new(0, 0.12, -0.35), Vector3.new(0.4, 0.4, 0.4), liquid, Enum.Material.Neon)
end

---------------------------------------------------------------------
-- DOJO
---------------------------------------------------------------------
local function buildDojo(ctx: Ctx)
	local p = ctx.Pal
	local mat = part(ctx, "MatCombate", Vector3.new(0, 0.17, 8), Vector3.new(18, 0.1, 13), p.Dark, Enum.Material.Fabric)
	mat.CanCollide = false
	for _, sx in ipairs({ -9, 9 }) do
		for _, sz in ipairs({ 1.5, 14.5 }) do
			part(ctx, "PosteRing", Vector3.new(sx, 1.2, sz), Vector3.new(0.5, 2.4, 0.5), p.Wood, Enum.Material.WoodPlanks)
		end
	end
	for _, yy in ipairs({ 0.9, 1.7 }) do
		part(ctx, "Cuerda", Vector3.new(0, yy, 1.5), Vector3.new(18, 0.16, 0.16), p.Cloth, Enum.Material.Fabric)
		part(ctx, "Cuerda", Vector3.new(0, yy, 14.5), Vector3.new(18, 0.16, 0.16), p.Cloth, Enum.Material.Fabric)
		for _, sx in ipairs({ -9, 9 }) do
			part(ctx, "Cuerda", Vector3.new(sx, yy, 8), Vector3.new(0.16, 0.16, 13), p.Cloth, Enum.Material.Fabric)
		end
	end
	-- los dos luchadores (uno ataca mientras el otro bloquea, y al revés)
	local m1, _, h1 = actor(ctx, "Instructor", 2, 8, 90, "Spar", 0, 3)
	local m2, _, h2 = actor(ctx, "Herrero", -2, 8, -90, "Spar", 0.5, 3)
	runChat({ m1, m2 }, { h1, h2 }, LINES_DOJO, 4)
	-- estandarte en la pared del fondo
	sign(ctx, Vector3.new(0, 7.5, ctx.D / 2 - 1.6), Vector3.new(18, 6, 0.2), p.Word, p.Cloth, Color3.fromRGB(250, 240, 220), 64)
	for _, sx in ipairs({ -9.4, 9.4 }) do
		part(ctx, "VaraEstandarte", Vector3.new(sx, 7.5, ctx.D / 2 - 1.6), Vector3.new(0.3, 7, 0.3), p.Wood, Enum.Material.WoodPlanks)
	end
	-- estantes de bokken y maniquíes a los lados
	for _, sx in ipairs({ -1, 1 }) do
		local rx = sx * 26
		for _, px in ipairs({ -2.6, 2.6 }) do
			part(ctx, "PosteRack", Vector3.new(rx + px, 2.2, ctx.D / 2 - 2.6), Vector3.new(0.4, 4.4, 0.4), p.Wood, Enum.Material.WoodPlanks)
		end
		for _, yy in ipairs({ 1.6, 3.4 }) do
			part(ctx, "RielRack", Vector3.new(rx, yy, ctx.D / 2 - 2.6), Vector3.new(5.6, 0.3, 0.3), p.Wood, Enum.Material.WoodPlanks)
		end
		for k = -2, 2 do
			part(ctx, "Bokken", Vector3.new(rx + k * 0.95, 2.6, ctx.D / 2 - 3), Vector3.new(0.3, 4.6, 0.3), p.Wood:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Wood, CFrame.Angles(math.rad(-6), 0, 0))
		end
		-- maniquí de entrenamiento
		local dx = sx * 24
		part(ctx, "BaseManiqui", Vector3.new(dx, 0.3, 4), Vector3.new(3.2, 0.5, 3.2), p.Wood, Enum.Material.WoodPlanks)
		part(ctx, "TroncoManiqui", Vector3.new(dx, 2.8, 4), Vector3.new(1.5, 5, 1.5), p.Wood:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Wood)
		part(ctx, "BrazosManiqui", Vector3.new(dx, 3.9, 4), Vector3.new(4.2, 0.7, 0.7), p.Wood, Enum.Material.Wood)
		part(ctx, "CabezaManiqui", Vector3.new(dx, 6, 4), Vector3.one * 1.4, p.Wood:Lerp(Color3.new(1, 1, 1), 0.1), Enum.Material.Wood, nil, Enum.PartType.Ball)
		part(ctx, "VendaManiqui", Vector3.new(dx, 2.6, 4), Vector3.new(1.7, 0.45, 1.7), p.Cloth, Enum.Material.Fabric)
	end
	-- faroles de papel
	for _, pos in ipairs({ Vector3.new(-28, 9, -5), Vector3.new(28, 9, -5), Vector3.new(-28, 9, 18), Vector3.new(28, 9, 18), Vector3.new(0, 10, 1) }) do
		local l = ball(ctx, "Farol", pos, 2, p.Glow, Enum.Material.Neon)
		l.Transparency = 0.15
		pointLight(l, p.Glow, 18, 0.9)
		part(ctx, "CuerdaFarol", pos + Vector3.new(0, 2.2, 0), Vector3.new(0.12, 2.4, 0.12), p.Dark, Enum.Material.Fabric)
	end
end

---------------------------------------------------------------------
-- FORJA
---------------------------------------------------------------------
local function swordProp(ctx: Ctx, x: number, y: number, z: number, len: number)
	local p = ctx.Pal
	part(ctx, "HojaColgada", Vector3.new(x, y, z), Vector3.new(0.5, len, 0.14), p.Metal, Enum.Material.Metal)
	part(ctx, "FiloColgado", Vector3.new(x, y + 0.2, z - 0.09), Vector3.new(0.12, len - 0.6, 0.06), Color3.new(1, 1, 1), Enum.Material.Neon).Transparency = 0.5
	part(ctx, "Guarda", Vector3.new(x, y - len / 2 - 0.1, z), Vector3.new(1.7, 0.3, 0.35), p.Glow:Lerp(p.Dark, 0.4), Enum.Material.Metal)
	part(ctx, "Empuñadura", Vector3.new(x, y - len / 2 - 1.1, z), Vector3.new(0.3, 1.5, 0.3), p.Cloth, Enum.Material.Leather)
end

local function buildForge(ctx: Ctx)
	local p = ctx.Pal
	local models: { Model } = {}
	local heads: { Part } = {}
	-- 3 herreros, cada uno con su yunque a la derecha-adelante (el martillo cae justo sobre la hoja al rojo)
	for i, x in ipairs({ -6, 4, 13 }) do
		local m, cf, h = actor(ctx, if i == 2 then "Instructor" else "Herrero", x, 17, 0, "Hammer", (i - 1) * 0.31, 1.25 + (i - 2) * 0.12)
		table.insert(models, m)
		table.insert(heads, h)
		-- martillo (mano derecha) y tenazas (mano izquierda)
		tool(m, cf, "ArmR", CFrame.new(1.5, -0.88, -0.9), Vector3.new(0.28, 0.28, 2.1), p.Wood, Enum.Material.Wood)
		tool(m, cf, "ArmR", CFrame.new(1.5, -0.88, -1.9), Vector3.new(1.4, 0.8, 0.8), Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
		tool(m, cf, "ArmL", CFrame.new(-1.5, -0.88, -0.8), Vector3.new(0.2, 0.2, 1.9), Color3.fromRGB(60, 60, 66), Enum.Material.Metal)
		-- yunque y espada incandescente
		local floorCF = cf * CFrame.new(1.5, -3, -2.66)
		partCF(ctx, "YunqueBase", floorCF * CFrame.new(0, 0.6, 0), Vector3.new(1.8, 1.2, 1.4), Color3.fromRGB(45, 45, 52), Enum.Material.Metal)
		partCF(ctx, "YunqueCintura", floorCF * CFrame.new(0, 1.55, 0), Vector3.new(1.2, 0.7, 1.0), Color3.fromRGB(55, 55, 62), Enum.Material.Metal)
		local top = partCF(ctx, "YunqueTope", floorCF * CFrame.new(0, 2.15, 0), Vector3.new(3.6, 0.5, 1.6), Color3.fromRGB(70, 70, 78), Enum.Material.Metal)
		top.CanCollide = true
		local blade = partCF(ctx, "HojaAlRojo", floorCF * CFrame.new(0.2, 2.46, 0), Vector3.new(3.2, 0.12, 0.42), Color3.fromRGB(255, 120, 40), Enum.Material.Neon)
		blade.Transparency = 0.05
		partCF(ctx, "EmpuñaduraForja", floorCF * CFrame.new(-1.9, 2.46, 0), Vector3.new(0.9, 0.2, 0.2), p.Wood, Enum.Material.Wood)
		pointLight(blade, Color3.fromRGB(255, 150, 60), 9, 1.2)
	end
	runChat(models, heads, LINES_FORGE, 4.5)
	-- horno con fuego de verdad
	local fp = part(ctx, "FuegoHorno", Vector3.new(-17, 7, 19), Vector3.new(4, 1, 3), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	fp.Transparency = 1
	local fire = Instance.new("Fire")
	fire.Size = 7
	fire.Heat = 9
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = fp
	pointLight(fp, Color3.fromRGB(255, 140, 50), 28, 1.8)
	-- barril de temple
	cyl(ctx, "BarrilTemple", Vector3.new(-9, 1.3, 21), 2.6, 3.2, Color3.fromRGB(110, 78, 50), Enum.Material.Wood).CanCollide = true
	local water = cyl(ctx, "AguaTemple", Vector3.new(-9, 2.5, 21), 0.12, 2.6, Color3.fromRGB(80, 150, 230), Enum.Material.Neon)
	water.Transparency = 0.35
	-- espadas colgadas en la pared
	part(ctx, "TableroEspadas", Vector3.new(1, 6, ctx.D / 2 - 1.4), Vector3.new(22, 6.5, 0.3), p.Wood, Enum.Material.WoodPlanks)
	for k = 0, 5 do
		swordProp(ctx, -8 + k * 3.6, 6.2, ctx.D / 2 - 1.75, 3.2 + (k % 3) * 0.5)
	end
	-- carbón junto al horno
	for k = 1, 5 do
		part(ctx, "Carbon", Vector3.new(-9 + k * 0.7, 0.5, 17.6 + (k % 2) * 0.8), Vector3.new(1, 0.8, 1), Color3.fromRGB(28, 28, 32), Enum.Material.Slate, CFrame.Angles(0, k, k * 0.4))
	end
end

---------------------------------------------------------------------
-- LABORATORIO
---------------------------------------------------------------------
local function cauldron(ctx: Ctx, cf: CFrame, color: Color3, diam: number)
	-- el caldero queda delante del científico (a su derecha) justo donde llega la cuchara
	local floorCF = cf * CFrame.new(1.5, -3, -3.5)
	local body = partCF(ctx, "Caldero", floorCF * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(2.6, diam, diam), Color3.fromRGB(38, 38, 46), Enum.Material.Metal, Enum.PartType.Cylinder)
	body.CanCollide = true
	local liquid = partCF(ctx, "Pocion", floorCF * CFrame.new(0, 2.15, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(0.2, diam - 0.6, diam - 0.6), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.Rate = 14
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(1.5, 3.5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = 1
	e.Acceleration = Vector3.new(0, 2, 0)
	e.EmissionDirection = Enum.NormalId.Right -- el cilindro está girado: su "derecha" apunta hacia arriba
	e.Parent = liquid
	pointLight(liquid, color, 14, 1.4)
	-- patas / fuego bajo el caldero
	for _, dx in ipairs({ -1, 1 }) do
		partCF(ctx, "PataCaldero", floorCF * CFrame.new(dx * (diam / 2 - 0.5), 0.3, 0), Vector3.new(0.5, 0.6, 0.5), Color3.fromRGB(30, 30, 36), Enum.Material.Metal)
	end
end

local function labBench(ctx: Ctx, x: number, z: number, w: number)
	local p = ctx.Pal
	part(ctx, "Mesa", Vector3.new(x, 2.6, z), Vector3.new(w, 0.4, 2.4), p.Wood, Enum.Material.WoodPlanks).CanCollide = true
	for _, dx in ipairs({ -1, 1 }) do
		part(ctx, "PataMesa", Vector3.new(x + dx * (w / 2 - 0.4), 1.2, z), Vector3.new(0.4, 2.4, 2), p.Wood, Enum.Material.WoodPlanks)
	end
	for k = 1, math.floor(w / 1.6) do
		local col = POTION_COLORS[(k + ctx.N) % #POTION_COLORS + 1]
		local bx = x - w / 2 + k * (w / (math.floor(w / 1.6) + 1))
		local b = part(ctx, "Matraz", Vector3.new(bx, 3.5, z + (k % 2) * 0.5 - 0.25), Vector3.new(0.9, 1.4, 0.9), col, Enum.Material.Glass)
		b.Transparency = 0.25
		local inner = part(ctx, "Liquido", Vector3.new(bx, 3.3, z + (k % 2) * 0.5 - 0.25), Vector3.new(0.6, 0.7, 0.6), col, Enum.Material.Neon)
		inner.Transparency = 0.1
	end
end

local function buildLab(ctx: Ctx)
	local p = ctx.Pal
	local models: { Model } = {}
	local heads: { Part } = {}
	-- científico 1: remueve el caldero grande
	local m1, cf1, h1 = actor(ctx, "Alquimista", 0, 14.5, 0, "Mix", 0, 1.7)
	table.insert(models, m1)
	table.insert(heads, h1)
	tool(m1, cf1, "ArmR", CFrame.new(1.5, 1, 0) * CFrame.new(0, -3.1, 0), Vector3.new(0.22, 2.5, 0.22), p.Wood, Enum.Material.Wood)
	cauldron(ctx, cf1, Color3.fromRGB(90, 255, 140), 4.2)
	-- científico 3: otro caldero, otra poción
	local m3, cf3, h3 = actor(ctx, "Alquimista", 11, 14.5, 0, "Mix", 0.4, 2.1)
	table.insert(models, m3)
	table.insert(heads, h3)
	tool(m3, cf3, "ArmR", CFrame.new(1.5, 1, 0) * CFrame.new(0, -3.1, 0), Vector3.new(0.22, 2.5, 0.22), p.Wood, Enum.Material.Wood)
	cauldron(ctx, cf3, Color3.fromRGB(200, 110, 255), 3.6)
	-- científico 2: revisa un frasco a contraluz sobre su mesa
	local m2, cf2, h2 = actor(ctx, "Alquimista", -11, 14.5, 0, "Hold", 0.2, 3.2)
	table.insert(models, m2)
	table.insert(heads, h2)
	local rest = cf2 * CFrame.new(1.5, -0.88, 0) * CFrame.Angles(-1.6, 0, 0)
	local flask = tool(m2, rest, "ArmR", CFrame.new(0, 0.25, -0.35), Vector3.new(0.7, 1.0, 0.7), Color3.fromRGB(235, 245, 255), Enum.Material.Glass)
	flask.Transparency = 0.4
	tool(m2, rest, "ArmR", CFrame.new(0, 0.1, -0.35), Vector3.new(0.5, 0.55, 0.5), Color3.fromRGB(255, 200, 80), Enum.Material.Neon)
	labBench(ctx, -9.5, 10.2, 7)
	runChat(models, heads, LINES_LAB, 4.5)
	-- banco largo al fondo con matraces
	labBench(ctx, 0, 18.4, 20)
	-- destilador de cristal (torre con burbujas)
	local tube = cyl(ctx, "TuboCristal", Vector3.new(-15.5, 5, 17), 10, 2.4, Color3.fromRGB(200, 235, 255), Enum.Material.Glass)
	tube.Transparency = 0.6
	tube.CanCollide = true
	local fluid = cyl(ctx, "TuboLiquido", Vector3.new(-15.5, 3.4, 17), 6.4, 1.9, Color3.fromRGB(120, 255, 220), Enum.Material.Neon)
	fluid.Transparency = 0.25
	pointLight(fluid, Color3.fromRGB(120, 255, 220), 14, 1.2)
	local bub = Instance.new("ParticleEmitter")
	bub.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bub.Color = ColorSequence.new(Color3.fromRGB(180, 255, 240))
	bub.Rate = 10
	bub.Lifetime = NumberRange.new(1, 1.8)
	bub.Speed = NumberRange.new(2, 4)
	bub.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	bub.LightEmission = 1
	bub.EmissionDirection = Enum.NormalId.Right
	bub.Parent = fluid
	part(ctx, "TuboTapa", Vector3.new(-15.5, 10.4, 17), Vector3.new(3, 0.8, 3), p.Dark, Enum.Material.Metal)
	-- estantes con frascos en las paredes laterales
	shelfUnit(ctx, -ctx.W / 2 + 2.6, 4, 10, 3, CFrame.Angles(0, math.rad(90), 0), false)
	shelfUnit(ctx, ctx.W / 2 - 2.6, 4, 10, 3, CFrame.Angles(0, math.rad(-90), 0), false)
	-- tubos de luz en el techo
	for _, x in ipairs({ -12, 0, 12 }) do
		local tb = part(ctx, "TuboLuz", Vector3.new(x, ctx.H - 1.5, 6), Vector3.new(0.5, 0.5, 22), p.Glow, Enum.Material.Neon)
		pointLight(tb, p.Glow, 20, 0.7)
	end
end

---------------------------------------------------------------------
-- BAZAR
---------------------------------------------------------------------
local function buildBazaar(ctx: Ctx)
	local p = ctx.Pal
	-- 3 góndolas contra la pared del fondo
	for _, x in ipairs({ -13, 0, 13 }) do
		shelfUnit(ctx, x, ctx.D / 2 - 1.2, 10.5, 4, CFrame.Angles(0, math.rad(180), 0), false)
	end
	-- 2 islas de doble cara a los lados del pasillo central
	for _, x in ipairs({ -9, 9 }) do
		shelfUnit(ctx, x, 8, 10, 3, CFrame.Angles(0, math.rad(90), 0), true)
	end
	sign(ctx, Vector3.new(0, 10.5, ctx.D / 2 - 1.5), Vector3.new(14, 1.8, 0.2), "ELIXIRES · POCIONES", p.Dark, p.Glow, 40)
	-- cajas y barril de reserva
	for k = 0, 2 do
		part(ctx, "CajaReserva", Vector3.new(-ctx.W / 2 + 3 + k * 2.6, 1.1, ctx.D / 2 - 9), Vector3.new(2.2, 2.2, 2.2), p.Wood, Enum.Material.WoodPlanks, CFrame.Angles(0, k, 0)).CanCollide = true
	end
	cyl(ctx, "BarrilReserva", Vector3.new(ctx.W / 2 - 3, 1.5, ctx.D / 2 - 9), 3, 2.6, p.Wood, Enum.Material.Wood).CanCollide = true
	-- faroles de colores
	for k, x in ipairs({ -14, 0, 14 }) do
		local l = ball(ctx, "FarolBazar", Vector3.new(x, ctx.H - 2.5, 4), 1.6, POTION_COLORS[k * 2], Enum.Material.Neon)
		pointLight(l, POTION_COLORS[k * 2], 16, 0.8)
	end
end

---------------------------------------------------------------------
-- PABELLÓN VIP
---------------------------------------------------------------------
local function table2(ctx: Ctx, x: number, z: number, d: number)
	local p = ctx.Pal
	cyl(ctx, "MesaVIP", Vector3.new(x, 1.9, z), 0.35, d, Color3.fromRGB(245, 240, 230), Enum.Material.Marble).CanCollide = true
	cyl(ctx, "PieMesaVIP", Vector3.new(x, 0.95, z), 1.9, 0.6, p.Glow, Enum.Material.Metal)
	cyl(ctx, "BaseMesaVIP", Vector3.new(x, 0.1, z), 0.2, d * 0.5, p.Glow, Enum.Material.Metal)
	for k = 1, 3 do
		local a = k * 2.1
		local cup = part(ctx, "CopaMesa", Vector3.new(x + math.cos(a) * d * 0.28, 2.5, z + math.sin(a) * d * 0.28), Vector3.new(0.45, 0.7, 0.45), Color3.fromRGB(235, 245, 255), Enum.Material.Glass)
		cup.Transparency = 0.4
	end
end

local function buildVip(ctx: Ctx)
	local p = ctx.Pal
	-- alfombra roja hasta el fondo
	part(ctx, "Alfombra", Vector3.new(0, 0.08, 0), Vector3.new(7, 0.12, ctx.D - 4), Color3.fromRGB(150, 26, 44), Enum.Material.Fabric)
	part(ctx, "AlfombraBorde", Vector3.new(0, 0.1, 0), Vector3.new(7.8, 0.08, ctx.D - 3.4), p.Glow, Enum.Material.Fabric)
	-- corrillo A: 3 personas alrededor de una mesa
	local models: { Model } = {}
	local heads: { Part } = {}
	local cxA, czA, r = -9, 12, 3.4
	local roles = { "Mayordomo", "Mercader", "Alquimista" }
	for k = 1, 3 do
		local a = math.rad(90 + (k - 1) * 120)
		local nx, nz = cxA + math.cos(a) * r, czA + math.sin(a) * r
		local dx, dz = cxA - nx, czA - nz
		local yaw = math.deg(math.atan2(-dx, -dz))
		local m, cf, h = actor(ctx, roles[k], nx, nz, yaw, "Chat", (k - 1) * 0.33, 1)
		glassCup(m, cf, "ArmL", Color3.fromRGB(255, 215, 120), 1.15)
		table.insert(models, m)
		table.insert(heads, h)
	end
	table2(ctx, cxA, czA, 3.2)
	runChat(models, heads, LINES_VIP, 4.8)
	-- corrillo B: pareja frente a frente
	local cxB, czB = 9, 13
	local mB1, cfB1, hB1 = actor(ctx, "Alquimista", cxB + 2.2, czB, 90, "Chat", 0.1, 1)
	local mB2, cfB2, hB2 = actor(ctx, "Mayordomo", cxB - 2.2, czB, -90, "Chat", 0.6, 1)
	glassCup(mB1, cfB1, "ArmL", Color3.fromRGB(255, 120, 160), 1.15)
	glassCup(mB2, cfB2, "ArmL", Color3.fromRGB(255, 215, 120), 1.15)
	table2(ctx, cxB, czB, 2.2)
	runChat({ mB1, mB2 }, { hB1, hB2 }, LINES_VIP, 5.2)
	-- sofás contra la pared del fondo
	for _, x in ipairs({ -13, 13 }) do
		part(ctx, "SofaAsiento", Vector3.new(x, 1.2, ctx.D / 2 - 3.4), Vector3.new(8, 1.2, 3), p.Cloth, Enum.Material.Fabric).CanCollide = true
		part(ctx, "SofaRespaldo", Vector3.new(x, 2.8, ctx.D / 2 - 4.7), Vector3.new(8, 2.6, 0.7), p.Cloth, Enum.Material.Fabric)
		for _, dx in ipairs({ -4, 4 }) do
			part(ctx, "SofaBrazo", Vector3.new(x + dx, 1.8, ctx.D / 2 - 3.4), Vector3.new(0.7, 2.2, 3), p.Cloth:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
		end
	end
	-- lámpara de araña
	local cy = ctx.H - 3
	part(ctx, "CadenaAraña", Vector3.new(0, cy + 1.6, 8), Vector3.new(0.2, 3.2, 0.2), p.Glow, Enum.Material.Metal)
	cyl(ctx, "AroAraña", Vector3.new(0, cy, 8), 0.3, 6, p.Glow, Enum.Material.Metal)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local bulb = ball(ctx, "LuzAraña", Vector3.new(math.cos(a) * 2.8, cy + 0.6, 8 + math.sin(a) * 2.8), 0.7, Color3.fromRGB(255, 244, 200), Enum.Material.Neon)
		if k % 4 == 0 then
			pointLight(bulb, Color3.fromRGB(255, 232, 170), 26, 1.1)
		end
	end
	-- macetas con plantas
	for _, x in ipairs({ -17, 17 }) do
		cyl(ctx, "Maceta", Vector3.new(x, 1, 6), 2, 2.4, p.Dark, Enum.Material.Slate)
		ball(ctx, "Planta", Vector3.new(x, 3.2, 6), 3.2, Color3.fromRGB(70, 160, 90), Enum.Material.Grass)
	end
end

---------------------------------------------------------------------
-- Aplicar a un edificio / arranque
---------------------------------------------------------------------
local BUILDERS: { [string]: (Ctx) -> () } = {
	dojo = buildDojo, forge = buildForge, lab = buildLab, bazaar = buildBazaar, vip = buildVip,
}

local function decorate(model: Model, faction: string)
	local slot = model:GetAttribute("Slot")
	local spec = if typeof(slot) == "number" then SPEC[slot] else nil
	local lot = model:FindFirstChild("Parcela")
	if not spec or not lot or not lot:IsA("BasePart") then
		return
	end
	local old = model:FindFirstChild("Vida")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Vida"
	local ctx: Ctx = {
		Model = model,
		F = lot.CFrame * CFrame.new(0, -0.15, 0), -- origen = piso del edificio (parcela de 0,3 de alto, centrada en y = 0,15)
		Fy = if spec.Base > 0 then spec.Base else 0.3,
		Folder = folder, Pal = PAL[faction], Faction = faction,
		W = spec.W, D = spec.D, H = spec.H, Rng = Random.new((slot :: number) * 101 + #faction), N = 0,
	}
	BUILDERS[spec.Kind](ctx)
	folder.Parent = model
end

local function run()
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	waited = 0
	while Workspace:GetAttribute("CityStyleDone") ~= true and waited < 30 do
		task.wait(0.25) -- que CityStyler termine antes (no se pisan, pero así el orden es siempre el mismo)
		waited += 0.25
	end
	local map = Workspace:WaitForChild(MAP_NAME, 60)
	if not map then
		warn("[CityLifeService] No existe " .. MAP_NAME)
		return
	end
	local done = 0
	for _, biome in ipairs(map:GetChildren()) do
		local faction = BIOME_FACTION[biome.Name]
		if faction then
			for _, d in ipairs(biome:GetDescendants()) do
				if d:IsA("Model") and d:GetAttribute("Slot") ~= nil and d:GetAttribute("Role") ~= nil and d:FindFirstChild("Parcela") then
					local ok, err = pcall(decorate, d, faction)
					if ok then
						done += 1
					else
						warn("[CityLifeService] " .. d.Name .. " (" .. faction .. "): " .. tostring(err))
					end
				end
			end
		end
	end
	Workspace:SetAttribute("CityLifeDone", true)
	print(string.format("[CityLifeService] Vida añadida a %d comercios.", done))
end

if ENABLED then
	task.spawn(run)
end

return {}
