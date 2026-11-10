--!strict
--[[
    SignKit (ModuleScript) -> ServerScriptService.Services.SignKit
    Piezas compartidas de los carteles: textos/diseños por facción (Élite, Sigilo, Navegantes, Guardianes) y el emblema giratorio.
    Lo usan BridgeSigns (cartel de las torres) y ArenaGate (arco del puente).
    Los emblemas son Models con el tag "SpinEmblem": SpinEmblemClient los hace girar sin parar en cada cliente.
]]
local CollectionService = game:GetService("CollectionService")

type Look = { Title: string, Sub: string, Board: Color3, Trim: Color3, Text: Color3 }
local LOOKS: { [string]: Look } = {
	Imperio_Saiyan = { Title = "IMPERIO DE ÉLITE", Sub = "Orgullo de élite  ·  龍", Board = Color3.fromRGB(22, 28, 64), Trim = Color3.fromRGB(240, 180, 50), Text = Color3.fromRGB(255, 210, 90) },
	Alianza_Shinobi = { Title = "ALIANZA DEL SIGILO", Sub = "La llama que guía  ·  忍", Board = Color3.fromRGB(18, 44, 30), Trim = Color3.fromRGB(120, 220, 120), Text = Color3.fromRGB(190, 255, 190) },
	Flota_Pirata = { Title = "FLOTA DE NAVEGANTES", Sub = "Libertad en alta mar  ·  海", Board = Color3.fromRGB(20, 40, 78), Trim = Color3.fromRGB(230, 200, 120), Text = Color3.fromRGB(255, 240, 200) },
	Corte_Shinigami = { Title = "CORTE ESPIRITUAL", Sub = "Protege las almas  ·  死", Board = Color3.fromRGB(20, 16, 40), Trim = Color3.fromRGB(190, 170, 255), Text = Color3.fromRGB(235, 228, 255) },
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Cartel de la cara de la ARENA: fondo con diseño del anime + nombre grande. (La cara de la ciudad queda lisa.)
local function box(parent: Instance, pos: UDim2, size: UDim2, color: Color3, transp: number, rot: number?, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transp
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	if round then
		Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	end
	f.Parent = parent
	return f
end

local function glyph(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, transp: number, rot: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Text = text
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = color
	t.TextTransparency = transp
	t.Rotation = rot or 0
	t.Parent = parent
	return t
end

local function gradient(f: GuiObject, a: Color3, b: Color3, rot: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rot
	g.Parent = f
end

local function designFace(board: Part, face: Enum.NormalId, biome: string, look: Look, width: number, height: number, titleText: string?, subText: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(width * 10, height * 10)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.ClipsDescendants = true
	gui.Parent = board
	local H = height * 10
	local bg = box(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), look.Board, 0)
	if biome == "Imperio_Saiyan" then
		-- cielo de noche con aura naranja (rayos), Bola de Dragón gigante tras el texto y 7 estrellas
		gradient(bg, Color3.fromRGB(10, 14, 40), Color3.fromRGB(70, 36, 20), 90)
		for i = -5, 5 do
			box(gui, UDim2.new(0.5, i * H * 0.55, 1, 0), UDim2.fromOffset(H * 0.16, H * 1.6), Color3.fromRGB(255, 150, 40), 0.55 + math.abs(i) * 0.05, i * 7)
		end
		box(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(H * 1.05, H * 1.05), Color3.fromRGB(255, 160, 30), 0.55, 0, true)
		for k = 1, 7 do
			glyph(gui, "★", UDim2.new(0.5, (k - 4) * H * 0.2, 0.86, 0), UDim2.fromOffset(H * 0.16, H * 0.16), Color3.fromRGB(255, 80, 60), 0)
		end
	elseif biome == "Alianza_Shinobi" then
		-- bosque verde con niebla, espirales de la Hoja a los lados, kanji enorme de fondo y kunais cruzados
		gradient(bg, Color3.fromRGB(10, 40, 26), Color3.fromRGB(34, 86, 52), 90)
		glyph(gui, "忍", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(H * 1.25, H * 1.25), Color3.fromRGB(150, 235, 150), 0.82)
		for _, sx in ipairs({ 0.1, 0.9 }) do
			for r = 1, 4 do
				local d = H * (0.22 * r)
				local ring = box(gui, UDim2.fromScale(sx, 0.5), UDim2.fromOffset(d, d), Color3.fromRGB(120, 220, 120), 1, 0, true)
				local st = Instance.new("UIStroke")
				st.Color = Color3.fromRGB(150, 240, 150)
				st.Thickness = 5
				st.Transparency = 0.3 + r * 0.1
				st.Parent = ring
			end
		end
		for _, rot in ipairs({ 35, -35 }) do
			box(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(width * 10 * 0.55, H * 0.035), Color3.fromRGB(190, 200, 210), 0.45, rot)
		end
		box(gui, UDim2.fromScale(0.5, 0.93), UDim2.fromScale(1, 0.14), Color3.fromRGB(220, 240, 220), 0.8)
	elseif biome == "Corte_Shinigami" then
		-- noche violeta con luna llena enorme, destellos de reiatsu, kanji 死 y franja de cintas blancas
		gradient(bg, Color3.fromRGB(10, 8, 28), Color3.fromRGB(70, 48, 120), 90)
		box(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(H * 1.15, H * 1.15), Color3.fromRGB(235, 232, 255), 0.7, 0, true)
		box(gui, UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(H * 0.8, H * 0.8), Color3.fromRGB(245, 242, 255), 0.6, 0, true)
		glyph(gui, "死", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(H * 1.2, H * 1.2), Color3.fromRGB(190, 170, 255), 0.84)
		for i = -5, 5 do
			box(gui, UDim2.new(0.5, i * H * 0.5, 1, 0), UDim2.fromOffset(H * 0.07, H * 1.4), Color3.fromRGB(150, 230, 255), 0.65 + math.abs(i) * 0.04, i * 6)
		end
		box(gui, UDim2.fromScale(0.5, 0.025), UDim2.fromScale(1, 0.05), Color3.fromRGB(235, 235, 245), 0)
		box(gui, UDim2.fromScale(0.5, 0.975), UDim2.fromScale(1, 0.05), Color3.fromRGB(235, 235, 245), 0)
	else
		-- mar al atardecer: olas, cuerdas, brújula/calavera de fondo
		gradient(bg, Color3.fromRGB(14, 60, 120), Color3.fromRGB(230, 150, 70), 90)
		glyph(gui, "☠", UDim2.fromScale(0.5, 0.48), UDim2.fromOffset(H * 1.1, H * 1.1), Color3.fromRGB(255, 245, 225), 0.8)
		for row = 0, 2 do
			for k = -9, 9 do
				box(gui, UDim2.new(0.5, k * H * 0.5 + row * H * 0.25, 1, -row * H * 0.07), UDim2.fromOffset(H * 0.5, H * 0.3), Color3.fromRGB(30 + row * 25, 100 + row * 30, 170 + row * 20), 0.15, 0, true)
			end
		end
		box(gui, UDim2.fromScale(0.5, 0.025), UDim2.fromScale(1, 0.05), Color3.fromRGB(210, 180, 120), 0)
		box(gui, UDim2.fromScale(0.5, 0.975), UDim2.fromScale(1, 0.05), Color3.fromRGB(210, 180, 120), 0)
	end
	-- nombre grande con contorno y subtítulo
	local title = glyph(gui, titleText or look.Title, UDim2.fromScale(0.5, 0.4), UDim2.fromScale(0.82, 0.46), look.Text, 0)
	title.TextStrokeTransparency = 0
	title.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0.5, 0.7)
	sub.Size = UDim2.fromScale(0.6, 0.14)
	sub.Text = subText or look.Sub
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.TextStrokeTransparency = 0.3
	sub.Parent = gui
end

-- Emblema de cada nación, centrado sobre el tablero (visible por los dos lados)
local function emblem(biome: string, folder: Instance, at: CFrame, look: Look)
	local function rel(x: number, y: number, z: number): CFrame
		return at * CFrame.new(x, y, z)
	end
	local Ball, Cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
	if biome == "Imperio_Saiyan" then
		-- Corona solar: anillo dorado con 8 rayos y un cristal azul al centro
		local gold = Color3.fromRGB(240, 190, 70)
		local ring = part(folder, "SunRing", Vector3.new(2.4, 22, 22), rel(0, 8, 0), gold, Enum.Material.Metal, Cyl)
		ring.Transparency = 0.05
		part(folder, "SunDisc", Vector3.new(1.4, 17, 17), rel(0, 8, 0), Color3.fromRGB(20, 30, 70), Enum.Material.SmoothPlastic, Cyl)
		for i = 0, 7 do
			local a = math.rad(i * 45)
			local cf = at * CFrame.new(math.cos(a) * 17, 8 + math.sin(a) * 17, 0) * CFrame.Angles(0, 0, a)
			part(folder, "Ray", Vector3.new(11, 2.6, 2.2), cf, gold, Enum.Material.Neon)
		end
		part(folder, "Crystal", Vector3.new(9, 9, 9), rel(0, 8, 0), Color3.fromRGB(90, 190, 255), Enum.Material.Neon, Ball).Transparency = 0.15
		for _, sx in ipairs({ -1, 1 }) do
			part(folder, "Flame", Vector3.new(6, 6, 6), rel(sx * 20, 3, 0), Color3.fromRGB(255, 190, 60), Enum.Material.Neon, Ball).Transparency = 0.3
		end
	elseif biome == "Alianza_Shinobi" then
		-- Gran estrella de cuatro filos de metal con anillo de espiral verde (kanji 忍)
		local steel = Color3.fromRGB(200, 205, 215)
		for _, a in ipairs({ 0, 90 }) do
			local cf = at * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(a))
			part(folder, "Blade", Vector3.new(34, 5, 1.6), cf, steel, Enum.Material.Metal)
			part(folder, "BladeTip", Vector3.new(34, 2, 1.2), cf * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(150, 155, 168), Enum.Material.Metal)
		end
		local hub = part(folder, "Hub", Vector3.new(2.4, 12, 12), rel(0, 8, 0), Color3.fromRGB(70, 76, 90), Enum.Material.Metal, Cyl)
		for _, face in ipairs({ Enum.NormalId.Right, Enum.NormalId.Left }) do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.CanvasSize = Vector2.new(200, 200)
			gui.LightInfluence = 0.4
			gui.Parent = hub
			local k = Instance.new("TextLabel")
			k.BackgroundTransparency = 1
			k.Size = UDim2.fromScale(1, 1)
			k.Text = "忍"
			k.Font = Enum.Font.GothamBlack
			k.TextScaled = true
			k.TextColor3 = Color3.fromRGB(120, 220, 120)
			k.Parent = gui
		end
		part(folder, "Spiral", Vector3.new(1.2, 8, 8), rel(-26, 8, 0), Color3.fromRGB(120, 220, 120), Enum.Material.Neon, Cyl).Transparency = 0.4
		part(folder, "Spiral", Vector3.new(1.2, 8, 8), rel(26, 8, 0), Color3.fromRGB(120, 220, 120), Enum.Material.Neon, Cyl).Transparency = 0.4
	elseif biome == "Corte_Shinigami" then
		-- Luna blanca rodeada de llamas espirituales, con dos lanzas de guardián cruzadas
		local white, glow = Color3.fromRGB(244, 244, 252), Color3.fromRGB(150, 130, 255)
		for _, a in ipairs({ 35, -35 }) do
			local cf = at * CFrame.new(0, 5, 0) * CFrame.Angles(0, 0, math.rad(a))
			part(folder, "Shaft", Vector3.new(44, 1.4, 1.4), cf, Color3.fromRGB(60, 50, 100), Enum.Material.Metal)
			part(folder, "SpearHead", Vector3.new(7, 3.2, 0.8), cf * CFrame.new(23, 0, 0), Color3.fromRGB(215, 220, 235), Enum.Material.Metal)
		end
		part(folder, "Moon", Vector3.new(3, 18, 18), rel(0, 8, 0), white, Enum.Material.Neon, Cyl)
		part(folder, "MoonShade", Vector3.new(3.6, 15, 15), rel(3.4, 10, 0), Color3.fromRGB(20, 16, 40), Enum.Material.SmoothPlastic, Cyl)
		for i = 0, 5 do
			local a = math.rad(i * 60 + 20)
			local w = part(folder, "Wisp", Vector3.new(3.4, 5.5, 3.4), rel(math.cos(a) * 15, 8 + math.sin(a) * 15, 0), glow, Enum.Material.Neon, Ball)
			w.Transparency = 0.35
		end
	else
		-- Calavera + huesos cruzados + tricornio de capitán
		local bone = Color3.fromRGB(235, 230, 215)
		for _, a in ipairs({ 35, -35 }) do
			part(folder, "Bone", Vector3.new(34, 2.2, 2.2), at * CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(a)), bone, Enum.Material.SmoothPlastic)
			for _, e in ipairs({ -1, 1 }) do
				local dx = math.cos(math.rad(a)) * 17 * e
				local dy = math.sin(math.rad(a)) * 17 * e
				part(folder, "BoneEnd", Vector3.new(3.6, 3.6, 3.6), at * CFrame.new(dx, 3 + dy, 0), bone, Enum.Material.SmoothPlastic, Ball)
			end
		end
		part(folder, "Skull", Vector3.new(14, 13, 12), rel(0, 8, 0), bone, Enum.Material.SmoothPlastic, Ball)
		part(folder, "Jaw", Vector3.new(8, 4, 8), rel(0, 1.5, 0), bone, Enum.Material.SmoothPlastic)
		for _, side in ipairs({ -1, 1 }) do
			for _, sx in ipairs({ -3, 3 }) do
				part(folder, "Eye", Vector3.new(3.4, 3.4, 3.4), rel(sx, 8.5, side * 5.2), Color3.fromRGB(15, 15, 20), Enum.Material.SmoothPlastic, Ball)
			end
			part(folder, "Nose", Vector3.new(1.6, 2.4, 1.6), rel(0, 6, side * 5.6), Color3.fromRGB(15, 15, 20), Enum.Material.SmoothPlastic)
		end
		local hat, trim = Color3.fromRGB(28, 30, 44), Color3.fromRGB(230, 190, 80)
		part(folder, "HatBrim", Vector3.new(1.6, 22, 22), at * CFrame.new(0, 15, 0) * CFrame.Angles(0, 0, math.rad(90)), hat, Enum.Material.Fabric, Cyl)
		part(folder, "HatTop", Vector3.new(6, 11, 11), at * CFrame.new(0, 18.5, 0) * CFrame.Angles(0, 0, math.rad(90)), hat, Enum.Material.Fabric, Cyl)
		part(folder, "HatTrim", Vector3.new(0.8, 22.8, 22.8), at * CFrame.new(0, 15, 0) * CFrame.Angles(0, 0, math.rad(90)), trim, Enum.Material.Metal, Cyl)
		part(folder, "HatBand", Vector3.new(1.6, 11.6, 11.6), at * CFrame.new(0, 16.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 30, 40), Enum.Material.Fabric, Cyl)
	end
	local glow = Instance.new("PointLight")
	glow.Color = look.Trim
	glow.Range = 60
	glow.Brightness = 1.2
	glow.Parent = folder:FindFirstChildWhichIsA("BasePart")
end


-- Emblema giratorio (Model con tag). at = centro de la base; scale reduce todo (el del arco va a ~0.5)
local function spinningEmblem(biome: string, parent: Instance, at: CFrame, look: Look, scale: number): Model
	local m = Instance.new("Model")
	m.Name = "Emblema"
	emblem(biome, m, at, look)
	m.Parent = parent
	-- pivote en el centro de la caja y SIN rotación: así gira de izquierda a derecha (eje vertical) aunque la primera pieza esté inclinada
	local bbox = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(bbox.Position)
	if scale ~= 1 then
		m:ScaleTo(scale)
	end
	CollectionService:AddTag(m, "SpinEmblem")
	return m
end

return {
	LOOKS = LOOKS,
	Part = part,
	Design = designFace,
	SpinningEmblem = spinningEmblem,
}
