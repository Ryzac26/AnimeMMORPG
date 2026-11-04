--!strict
--[[
    NpcKit (ModuleScript) -> StarterPlayer > StarterPlayerScripts > NpcKit
    Piezas visuales compartidas por las ventanas de NPC (Tienda, Mercader, Herrero, Alquimia, Instructor...) para que cada una
    se vea como lo que es y cada FACCIÓN tenga su propio estilo, sin imágenes (solo código):
      Saiyan    -> panel tecnológico tipo scouter: acero oscuro, franjas naranjas en diagonal, esquinas cortadas
      Shinobi   -> pergamino: papel envejecido, varillas enrolladas, tinta oscura
      Pirate    -> madera de barco: tablones, latón, cuerda
      Shinigami -> tinta y espíritu: negro profundo, líneas finas pálidas, cinta vertical
    API:
      NpcKit.Header(win, theme, width, title, subtitle, icon) -> Frame   cabecera/rótulo de 56 px (poner la X de cerrar encima, ZIndex 30)
      NpcKit.Awning(win, theme, width, y)                       -> Frame   toldo de tienda (rayas + festón) de 22 px
      NpcKit.Panel(parent, theme, size, pos, kind)              -> Frame   panel/tarjeta con el material de la facción (kind: "card" | "inset" | "plate")
      NpcKit.Button(parent, theme, text, size, pos, kind, cb)   -> TextButton  (kind: "buy" | "sell" | "action" | "neutral" | "danger")
      NpcKit.Shelf(parent, theme, pos, width)                   -> Frame   tabla de estantería (madera/metal/papel según facción)
      NpcKit.Tab(parent, theme, text, size, pos, active, cb)    -> TextButton  pestaña vertical u horizontal
      NpcKit.Chip(parent, text, color, pos, size)               -> TextLabel  etiqueta redonda (precio, "AHORRAS", "ELEGIDO")
      NpcKit.Palette(theme)                                     -> { Ink, Paper, Edge, Soft, Text, Muted }
]]
local NpcKit = {}

local function key(theme: any): string
	local f = theme.Faction
	if f == "Imperio Saiyan" then
		return "Saiyan"
	elseif f == "Alianza Shinobi" then
		return "Shinobi"
	elseif f == "Flota Pirata" then
		return "Pirate"
	end
	return "Shinigami"
end
NpcKit.Key = key

local PALETTE: { [string]: { [string]: Color3 } } = {
	Saiyan = { Ink = Color3.fromRGB(22, 20, 26), Paper = Color3.fromRGB(34, 30, 38), Edge = Color3.fromRGB(255, 150, 50), Soft = Color3.fromRGB(58, 44, 36), Text = Color3.fromRGB(255, 240, 220), Muted = Color3.fromRGB(190, 170, 150) },
	Shinobi = { Ink = Color3.fromRGB(40, 30, 20), Paper = Color3.fromRGB(214, 196, 150), Edge = Color3.fromRGB(110, 80, 40), Soft = Color3.fromRGB(190, 170, 124), Text = Color3.fromRGB(46, 32, 18), Muted = Color3.fromRGB(104, 84, 56) },
	Pirate = { Ink = Color3.fromRGB(30, 20, 12), Paper = Color3.fromRGB(96, 64, 38), Edge = Color3.fromRGB(226, 184, 100), Soft = Color3.fromRGB(122, 84, 50), Text = Color3.fromRGB(255, 240, 205), Muted = Color3.fromRGB(214, 184, 140) },
	Shinigami = { Ink = Color3.fromRGB(8, 6, 14), Paper = Color3.fromRGB(18, 14, 30), Edge = Color3.fromRGB(190, 175, 255), Soft = Color3.fromRGB(32, 26, 54), Text = Color3.fromRGB(240, 236, 255), Muted = Color3.fromRGB(160, 150, 200) },
}
function NpcKit.Palette(theme: any): { [string]: Color3 }
	return PALETTE[key(theme)]
end

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function stroke(inst: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function gradient(inst: Instance, a: Color3, b: Color3, rot: number)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rot
	g.Parent = inst
	return g
end

local function box(parent: Instance, pos: UDim2, size: UDim2, color: Color3, transparency: number?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?, z: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.Position = pos
	t.Size = dim
	t.ZIndex = z or 2
	t.Parent = parent
	return t
end

---------------------------------------------------------------------
-- CABECERA / RÓTULO
---------------------------------------------------------------------
function NpcKit.Header(win: Frame, theme: any, width: number, title: string, subtitle: string?, icon: string?): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local h = Instance.new("Frame")
	h.Name = "Cabecera"
	h.Position = UDim2.fromOffset(8, 8)
	h.Size = UDim2.fromOffset(width - 16, 52)
	h.BorderSizePixel = 0
	h.ClipsDescendants = true
	h.ZIndex = 2
	h.Parent = win
	local titleColor = p.Text
	if k == "Saiyan" then
		h.BackgroundColor3 = p.Ink
		gradient(h, Color3.fromRGB(60, 38, 22), Color3.fromRGB(20, 18, 24), 0)
		corner(h, 3)
		stroke(h, p.Edge, 1.5, 0.2)
		for i = 0, 14 do -- franjas diagonales naranjas (zona de scouter)
			local s = box(h, UDim2.fromOffset(width - 150 + i * 14, -6), UDim2.fromOffset(6, 80), p.Edge, 0.7 + (i % 3) * 0.08, 3)
			s.Rotation = 24
		end
		box(h, UDim2.fromOffset(0, 49), UDim2.new(1, 0, 0, 3), p.Edge, 0.1, 3)
	elseif k == "Shinobi" then
		h.BackgroundColor3 = p.Paper
		gradient(h, Color3.fromRGB(228, 212, 168), Color3.fromRGB(196, 176, 130), 90)
		corner(h, 6)
		stroke(h, p.Edge, 2)
		for _, x in ipairs({ 0, width - 16 - 14 }) do -- varillas del pergamino
			local rod = box(h, UDim2.fromOffset(x, 0), UDim2.fromOffset(14, 52), Color3.fromRGB(96, 62, 30), 0, 3)
			gradient(rod, Color3.fromRGB(140, 96, 52), Color3.fromRGB(70, 44, 20), 0)
		end
		titleColor = p.Text
	elseif k == "Pirate" then
		h.BackgroundColor3 = p.Paper
		gradient(h, Color3.fromRGB(122, 84, 50), Color3.fromRGB(78, 50, 28), 90)
		corner(h, 5)
		stroke(h, p.Edge, 2)
		for i = 1, 3 do -- tablones
			box(h, UDim2.fromOffset(0, i * 13), UDim2.new(1, 0, 0, 1), Color3.fromRGB(40, 24, 12), 0.35, 3)
		end
		for _, x in ipairs({ 10, width - 16 - 14 }) do -- remaches de latón
			local r = box(h, UDim2.fromOffset(x, 8), UDim2.fromOffset(6, 6), p.Edge, 0, 4)
			corner(r, 3)
			local r2 = box(h, UDim2.fromOffset(x, 38), UDim2.fromOffset(6, 6), p.Edge, 0, 4)
			corner(r2, 3)
		end
	else
		h.BackgroundColor3 = p.Ink
		gradient(h, Color3.fromRGB(34, 26, 58), Color3.fromRGB(8, 6, 14), 0)
		corner(h, 4)
		stroke(h, p.Edge, 1, 0.45)
		box(h, UDim2.fromOffset(0, 25), UDim2.new(1, 0, 0, 1), p.Edge, 0.7, 3)
		box(h, UDim2.fromOffset(70, 0), UDim2.fromOffset(2, 52), p.Edge, 0.55, 3)
		box(h, UDim2.fromOffset(width - 16 - 40, 0), UDim2.fromOffset(1, 52), p.Edge, 0.7, 3)
	end
	-- icono en medallón
	local medal = box(h, UDim2.fromOffset(12, 6), UDim2.fromOffset(40, 40), if k == "Shinobi" then Color3.fromRGB(150, 40, 36) else theme.Primary, 0, 4)
	corner(medal, if k == "Saiyan" then 4 else 20)
	stroke(medal, if k == "Shinobi" then Color3.fromRGB(70, 20, 18) else p.Edge, 2)
	label(medal, icon or theme.Emblem, 22, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center, 5)
	label(h, string.upper(title), 22, if k == "Shinobi" then p.Text elseif k == "Pirate" then Color3.fromRGB(255, 232, 170) else theme.Primary, UDim2.fromOffset(62, 4), UDim2.new(1, -140, 0, 28), nil, 5)
	if subtitle then
		label(h, subtitle, 12, if k == "Shinobi" then p.Muted else p.Muted, UDim2.fromOffset(62, 30), UDim2.new(1, -140, 0, 16), nil, 5)
	end
	return h
end

---------------------------------------------------------------------
-- TOLDO DE TIENDA
---------------------------------------------------------------------
function NpcKit.Awning(win: Frame, theme: any, width: number, y: number): Frame
	local k = key(theme)
	local holder = Instance.new("Frame")
	holder.Name = "Toldo"
	holder.Position = UDim2.fromOffset(8, y)
	holder.Size = UDim2.fromOffset(width - 16, 22)
	holder.BackgroundTransparency = 1
	holder.ClipsDescendants = false
	holder.ZIndex = 3
	holder.Parent = win
	local a, b = theme.Primary, theme.Secondary
	if k == "Shinobi" then
		a, b = Color3.fromRGB(150, 40, 36), Color3.fromRGB(226, 208, 160)
	elseif k == "Shinigami" then
		a, b = Color3.fromRGB(34, 26, 58), Color3.fromRGB(190, 175, 255)
	elseif k == "Pirate" then
		a, b = Color3.fromRGB(190, 50, 50), Color3.fromRGB(236, 222, 190)
	end
	local stripe = 26
	local n = math.ceil((width - 16) / stripe)
	for i = 0, n - 1 do
		local c = if i % 2 == 0 then a else b
		local s = box(holder, UDim2.fromOffset(i * stripe, 0), UDim2.fromOffset(stripe, 14), c, 0, 3)
		local scallop = box(s, UDim2.fromOffset(0, 8), UDim2.fromOffset(stripe, stripe), c, 0, 3)
		corner(scallop, stripe / 2)
		scallop.Size = UDim2.fromOffset(stripe, 14)
	end
	return holder
end

---------------------------------------------------------------------
-- PANELES
---------------------------------------------------------------------
function NpcKit.Panel(parent: Instance, theme: any, size: UDim2, pos: UDim2, kind: string?): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	f.Parent = parent
	local inset = kind == "inset"
	local plate = kind == "plate"
	if k == "Saiyan" then
		f.BackgroundColor3 = if inset then Color3.fromRGB(14, 13, 18) else p.Paper
		gradient(f, if inset then Color3.fromRGB(18, 16, 22) else Color3.fromRGB(46, 38, 44), if inset then Color3.fromRGB(10, 10, 14) else Color3.fromRGB(26, 24, 30), 90)
		corner(f, 3)
		stroke(f, p.Edge, if plate then 2 else 1, if inset then 0.6 else 0.35)
		if not inset then
			box(f, UDim2.fromOffset(0, 0), UDim2.new(0, 36, 0, 2), p.Edge, 0.05, 3) -- marca de esquina
			box(f, UDim2.new(1, -36, 1, -2), UDim2.new(0, 36, 0, 2), p.Edge, 0.05, 3)
		end
	elseif k == "Shinobi" then
		f.BackgroundColor3 = if inset then Color3.fromRGB(176, 156, 112) else p.Paper
		gradient(f, if inset then Color3.fromRGB(184, 164, 120) else Color3.fromRGB(226, 210, 166), if inset then Color3.fromRGB(160, 140, 98) else Color3.fromRGB(200, 180, 134), 90)
		corner(f, 6)
		stroke(f, p.Edge, if plate then 2 else 1.2, if inset then 0.3 else 0)
	elseif k == "Pirate" then
		f.BackgroundColor3 = if inset then Color3.fromRGB(58, 38, 22) else p.Paper
		gradient(f, if inset then Color3.fromRGB(66, 44, 26) else Color3.fromRGB(120, 82, 48), if inset then Color3.fromRGB(46, 30, 16) else Color3.fromRGB(86, 56, 32), 90)
		corner(f, 5)
		stroke(f, if inset then Color3.fromRGB(30, 18, 8) else p.Edge, if plate then 2 else 1.2, if inset then 0.2 else 0.15)
	else
		f.BackgroundColor3 = if inset then Color3.fromRGB(6, 4, 12) else p.Paper
		gradient(f, if inset then Color3.fromRGB(10, 8, 18) else Color3.fromRGB(28, 22, 46), if inset then Color3.fromRGB(4, 3, 8) else Color3.fromRGB(12, 9, 22), 90)
		corner(f, 4)
		stroke(f, p.Edge, if plate then 1.6 else 1, if inset then 0.7 else 0.5)
	end
	return f
end

---------------------------------------------------------------------
-- BOTONES / PESTAÑAS / ETIQUETAS
---------------------------------------------------------------------
local BTN: { [string]: { Color3 } } = {
	buy = { Color3.fromRGB(110, 210, 120), Color3.fromRGB(40, 130, 66) },
	sell = { Color3.fromRGB(235, 190, 80), Color3.fromRGB(160, 100, 24) },
	action = { Color3.fromRGB(110, 170, 255), Color3.fromRGB(44, 90, 180) },
	neutral = { Color3.fromRGB(100, 100, 120), Color3.fromRGB(56, 56, 72) },
	danger = { Color3.fromRGB(235, 100, 90), Color3.fromRGB(150, 40, 40) },
}

function NpcKit.Button(parent: Instance, theme: any, text: string, size: UDim2, pos: UDim2, kind: string?, cb: (() -> ())?): TextButton
	local k = key(theme)
	local colors = BTN[kind or "neutral"] or BTN.neutral
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = colors[2]
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.ZIndex = 10
	b.TextStrokeTransparency = 0.5
	b.Parent = parent
	corner(b, if k == "Saiyan" then 3 elseif k == "Shinigami" then 4 else 8)
	gradient(b, colors[1], colors[2], 90)
	stroke(b, colors[1]:Lerp(Color3.new(1, 1, 1), 0.3), 1.2, 0.35)
	if cb then
		b.Activated:Connect(cb)
	end
	return b
end

function NpcKit.Tab(parent: Instance, theme: any, text: string, size: UDim2, pos: UDim2, active: boolean, cb: (() -> ())?): TextButton
	local k = key(theme)
	local p = PALETTE[k]
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	b.ZIndex = 10
	b.Parent = parent
	corner(b, if k == "Saiyan" then 2 else 7)
	if active then
		b.BackgroundColor3 = theme.Primary
		b.TextColor3 = if k == "Shinobi" then Color3.fromRGB(30, 20, 10) else Color3.fromRGB(20, 14, 8)
		stroke(b, p.Edge, 2)
	else
		b.BackgroundColor3 = if k == "Shinobi" then Color3.fromRGB(176, 156, 112) else p.Soft
		b.TextColor3 = if k == "Shinobi" then p.Text else p.Muted
		stroke(b, p.Edge, 1, 0.65)
	end
	if cb then
		b.Activated:Connect(cb)
	end
	return b
end

function NpcKit.Chip(parent: Instance, text: string, color: Color3, pos: UDim2, size: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.Position = pos
	t.Size = size
	t.BackgroundColor3 = color
	t.TextColor3 = if color.R * 0.3 + color.G * 0.6 + color.B * 0.1 > 0.55 then Color3.fromRGB(40, 24, 4) else Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold
	t.TextSize = 11
	t.Text = text
	t.BorderSizePixel = 0
	t.ZIndex = 8
	t.Parent = parent
	corner(t, 9)
	return t
end

function NpcKit.Shelf(parent: Instance, theme: any, pos: UDim2, width: number): Frame
	local k = key(theme)
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = UDim2.fromOffset(width, 10)
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.Parent = parent
	if k == "Pirate" then
		f.BackgroundColor3 = Color3.fromRGB(104, 70, 40)
		gradient(f, Color3.fromRGB(140, 96, 56), Color3.fromRGB(70, 44, 24), 90)
	elseif k == "Saiyan" then
		f.BackgroundColor3 = Color3.fromRGB(70, 66, 78)
		gradient(f, Color3.fromRGB(110, 104, 120), Color3.fromRGB(44, 42, 52), 90)
		box(f, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 2), Color3.fromRGB(255, 150, 50), 0.3, 3)
	elseif k == "Shinobi" then
		f.BackgroundColor3 = Color3.fromRGB(110, 80, 44)
		gradient(f, Color3.fromRGB(140, 104, 60), Color3.fromRGB(86, 60, 30), 90)
	else
		f.BackgroundColor3 = Color3.fromRGB(40, 32, 66)
		gradient(f, Color3.fromRGB(70, 58, 112), Color3.fromRGB(22, 18, 40), 90)
		box(f, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), Color3.fromRGB(190, 175, 255), 0.4, 3)
	end
	corner(f, 3)
	return f
end

return NpcKit
