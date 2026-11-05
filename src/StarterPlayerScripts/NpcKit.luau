--!strict
--[[
    NpcKit (ModuleScript) -> StarterPlayer > StarterPlayerScripts > NpcKit
    ESTILO ÚNICO de las ventanas dentro del juego (mochila/perfil, gremio, tienda, mercader, herrero, alquimia, mascota, ajustes, instructor...).
    Todo con fondo OPACO y un look propio por facción (solo código, sin imágenes):
      Saiyan    -> acero oscuro con franjas naranjas
      Shinobi   -> marco verde oscuro con bambú; paneles de pergamino con letra de tinta; cabecera de pergamino con letra oscura
      Pirate    -> madera de barco con tablones y latón
      Shinigami -> negro violáceo con resplandor y líneas pálidas
    API:
      NpcKit.Window(parent, theme, size, pos, anchor, title, subtitle, icon, onClose) -> Frame   ventana completa (fondo, marco doble, cabecera y X). Contenido desde y = NpcKit.TOP
      NpcKit.Header(win, theme, width, title, subtitle, icon)   cabecera suelta (la usa Window)
      NpcKit.Awning(win, theme, width, y)                       toldo de tienda
      NpcKit.Panel(parent, theme, size, pos, kind)              "card" | "inset" | "plate"
      NpcKit.Slot(parent, theme, size, pos)                     casilla de objeto
      NpcKit.Button(parent, theme, text, size, pos, kind, cb)   "buy" | "sell" | "action" | "neutral" | "danger"
      NpcKit.Tab(parent, theme, text, size, pos, active, cb)
      NpcKit.Chip(parent, text, color, pos, size)
      NpcKit.Shelf(parent, theme, pos, width)
      NpcKit.Palette(theme) -> { Bg, Panel, Inset, Slot, Edge, Edge2, Accent, FText, FMuted, Text, Muted, TabOn, TabOnText, TabOff, TabOffText,
                                 BtnA, BtnB, BtnText, Ink, Paper, Soft }   (Ink/Paper/Soft = nombres antiguos)
]]
local NpcKit = {}
NpcKit.TOP = 72 -- y donde empieza el contenido (debajo de la cabecera)

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

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local PALETTE: { [string]: { [string]: Color3 } } = {
	Saiyan = {
		Bg = c(23, 18, 15), Panel = c(36, 28, 22), Inset = c(16, 12, 9), Slot = c(23, 17, 9), Edge = c(255, 154, 46), Edge2 = c(120, 76, 30),
		Accent = c(255, 193, 90), FText = c(255, 241, 220), FMuted = c(196, 169, 138), Text = c(255, 241, 220), Muted = c(196, 169, 138),
		TabOn = c(255, 176, 74), TabOnText = c(36, 18, 4), TabOff = c(43, 33, 24), TabOffText = c(196, 169, 138),
		BtnA = c(255, 180, 84), BtnB = c(192, 90, 12), BtnText = c(42, 18, 4), Head = c(58, 34, 18), Head2 = c(24, 19, 14),
	},
	Shinobi = {
		Bg = c(31, 43, 28), Panel = c(217, 200, 159), Inset = c(195, 175, 128), Slot = c(235, 223, 186), Edge = c(122, 84, 38), Edge2 = c(150, 122, 78),
		Accent = c(177, 58, 50), FText = c(243, 231, 196), FMuted = c(185, 195, 160), Text = c(46, 33, 18), Muted = c(98, 80, 48),
		TabOn = c(177, 58, 50), TabOnText = c(255, 243, 214), TabOff = c(195, 175, 128), TabOffText = c(66, 50, 26),
		BtnA = c(200, 71, 61), BtnB = c(138, 36, 32), BtnText = c(255, 243, 214), Head = c(226, 209, 166), Head2 = c(201, 180, 136),
		HText = c(46, 33, 18), HMuted = c(98, 80, 48),
	},
	Pirate = {
		Bg = c(44, 28, 16), Panel = c(78, 51, 29), Inset = c(51, 32, 15), Slot = c(42, 26, 13), Edge = c(226, 184, 100), Edge2 = c(140, 108, 58),
		Accent = c(240, 200, 112), FText = c(255, 237, 200), FMuted = c(210, 184, 138), Text = c(255, 237, 200), Muted = c(210, 184, 138),
		TabOn = c(226, 184, 100), TabOnText = c(42, 22, 4), TabOff = c(62, 41, 21), TabOffText = c(210, 184, 138),
		BtnA = c(240, 200, 112), BtnB = c(184, 131, 44), BtnText = c(42, 22, 4), Head = c(122, 82, 48), Head2 = c(74, 47, 24),
	},
	Shinigami = {
		Bg = c(14, 10, 26), Panel = c(26, 20, 48), Inset = c(10, 7, 18), Slot = c(18, 13, 34), Edge = c(185, 168, 255), Edge2 = c(78, 68, 120),
		Accent = c(165, 140, 255), FText = c(240, 236, 255), FMuted = c(167, 155, 214), Text = c(240, 236, 255), Muted = c(167, 155, 214),
		TabOn = c(165, 140, 255), TabOnText = c(18, 10, 42), TabOff = c(29, 22, 54), TabOffText = c(167, 155, 214),
		BtnA = c(185, 162, 255), BtnB = c(106, 79, 208), BtnText = c(18, 10, 42), Head = c(43, 33, 80), Head2 = c(14, 10, 26),
	},
}
for _, p in pairs(PALETTE) do
	p.Ink, p.Paper, p.Soft = p.Bg, p.Panel, p.Inset
	p.HText = p.HText or p.FText
	p.HMuted = p.HMuted or p.FMuted
end
function NpcKit.Palette(theme: any): { [string]: Color3 }
	return PALETTE[key(theme)]
end

local RADIUS: { [string]: { number } } = { Saiyan = { 4, 3 }, Shinobi = { 6, 5 }, Pirate = { 6, 4 }, Shinigami = { 4, 3 } }

local function corner(inst: Instance, r: number)
	local cr = Instance.new("UICorner")
	cr.CornerRadius = UDim.new(0, r)
	cr.Parent = inst
end

local function stroke(inst: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
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
-- CABECERA
---------------------------------------------------------------------
function NpcKit.Header(win: Frame, theme: any, width: number, title: string, subtitle: string?, icon: string?): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local r = RADIUS[k]
	local h = Instance.new("Frame")
	h.Name = "Cabecera"
	h.Position = UDim2.fromOffset(12, 12)
	h.Size = UDim2.fromOffset(width - 24, 52)
	h.BorderSizePixel = 0
	h.ClipsDescendants = true
	h.BackgroundColor3 = p.Head
	h.ZIndex = 2
	h.Parent = win
	gradient(h, p.Head, p.Head2, if k == "Saiyan" or k == "Shinigami" then 0 else 90)
	corner(h, r[2])
	stroke(h, p.Edge, 1.5, 0.15)
	local w = width - 24
	if k == "Saiyan" then
		for i = 0, 11 do
			local s = box(h, UDim2.fromOffset(w - 190 + i * 16, -8), UDim2.fromOffset(6, 80), p.Edge, 0.72 + (i % 3) * 0.06, 3)
			s.Rotation = 24
		end
	elseif k == "Shinobi" then
		for _, x in ipairs({ 0, w - 12 }) do
			local rod = box(h, UDim2.fromOffset(x, 0), UDim2.fromOffset(12, 52), c(110, 74, 34), 0, 3)
			gradient(rod, c(150, 104, 56), c(70, 44, 20), 0)
		end
	elseif k == "Pirate" then
		for i = 1, 3 do
			box(h, UDim2.fromOffset(0, i * 13), UDim2.new(1, 0, 0, 1), c(40, 24, 12), 0.45, 3)
		end
		for _, x in ipairs({ 6, w - 12 }) do
			corner(box(h, UDim2.fromOffset(x, 7), UDim2.fromOffset(6, 6), p.Edge, 0, 4), 3)
			corner(box(h, UDim2.fromOffset(x, 39), UDim2.fromOffset(6, 6), p.Edge, 0, 4), 3)
		end
	else
		box(h, UDim2.fromOffset(78, 0), UDim2.fromOffset(1, 52), p.Edge, 0.5, 3)
		box(h, UDim2.fromOffset(0, 26), UDim2.new(1, 0, 0, 1), p.Edge, 0.82, 3)
	end
	local medal = box(h, UDim2.fromOffset(if k == "Shinobi" then 18 else 12, 6), UDim2.fromOffset(40, 40), if k == "Shinobi" then c(150, 40, 36) else p.Accent, 0, 4)
	corner(medal, if k == "Saiyan" then 4 else 20)
	stroke(medal, if k == "Shinobi" then c(70, 20, 18) else p.Edge, 2)
	label(medal, icon or theme.Emblem, 21, if k == "Shinobi" or k == "Saiyan" or k == "Pirate" then c(255, 255, 255) else p.BtnText, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center, 5)
	local tx = if k == "Shinobi" then 68 else 62
	local tt = label(h, string.upper(title), 21, p.HText, UDim2.fromOffset(tx, 4), UDim2.new(1, -(tx + 90), 0, 28), nil, 5)
	tt.TextTruncate = Enum.TextTruncate.AtEnd
	if subtitle then
		local st = label(h, subtitle, 12, p.HMuted, UDim2.fromOffset(tx, 30), UDim2.new(1, -(tx + 90), 0, 16), nil, 5)
		st.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return h
end

---------------------------------------------------------------------
-- VENTANA COMPLETA (fondo opaco + marco doble + cabecera + X)
---------------------------------------------------------------------
function NpcKit.Window(parent: Instance, theme: any, size: UDim2, pos: UDim2, anchor: Vector2?, title: string, subtitle: string?, icon: string?, onClose: (() -> ())?): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local r = RADIUS[k]
	local win = Instance.new("Frame")
	win.Name = "Ventana"
	win.Size = size
	win.Position = pos
	win.AnchorPoint = anchor or Vector2.zero
	win.BackgroundColor3 = p.Bg
	win.BackgroundTransparency = 0
	win.BorderSizePixel = 0
	win.Parent = parent
	corner(win, r[1])
	stroke(win, p.Edge, 2)
	local w = size.X.Offset
	local h = size.Y.Offset
	-- textura del fondo
	local pat = Instance.new("Frame")
	pat.Name = "Textura"
	pat.Size = UDim2.fromScale(1, 1)
	pat.BackgroundTransparency = 1
	pat.ClipsDescendants = true
	pat.ZIndex = 1
	pat.Parent = win
	corner(pat, r[1])
	if k == "Shinobi" and w > 0 then
		for x = 20, w, 26 do
			box(pat, UDim2.fromOffset(x, 0), UDim2.new(0, 3, 1, 0), c(0, 0, 0), 0.86, 1)
		end
	elseif k == "Pirate" and h > 0 then
		for y = 14, h, 15 do
			box(pat, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, 1), c(0, 0, 0), 0.78, 1)
		end
	elseif k == "Saiyan" and w > 0 then
		for x = -h, w, 28 do
			local s = box(pat, UDim2.fromOffset(x, -20), UDim2.fromOffset(2, h + 80), p.Edge, 0.94, 1)
			s.Rotation = -30
		end
	else
		local glow = box(pat, UDim2.fromScale(-0.1, -0.35), UDim2.fromScale(0.8, 0.8), p.Accent, 0.9, 1)
		corner(glow, 400)
	end
	-- marco interior fino
	local inner = Instance.new("Frame")
	inner.Name = "MarcoInterior"
	inner.Position = UDim2.fromOffset(5, 5)
	inner.Size = UDim2.new(1, -10, 1, -10)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 1
	inner.Parent = win
	corner(inner, math.max(r[1] - 2, 2))
	stroke(inner, p.Edge2, 1, 0.2)
	NpcKit.Header(win, theme, w, title, subtitle, icon)
	local close = Instance.new("TextButton")
	close.Name = "Cerrar"
	close.Position = UDim2.new(1, -46, 0, 18)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundColor3 = p.Slot
	close.TextColor3 = c(255, 122, 122)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.ZIndex = 30
	close.Parent = win
	corner(close, r[2])
	stroke(close, p.Edge, 1)
	if onClose then
		close.Activated:Connect(onClose)
	end
	return win
end

---------------------------------------------------------------------
-- TOLDO DE TIENDA
---------------------------------------------------------------------
function NpcKit.Awning(win: Frame, theme: any, width: number, y: number): Frame
	local k = key(theme)
	local holder = Instance.new("Frame")
	holder.Name = "Toldo"
	holder.Position = UDim2.fromOffset(12, y)
	holder.Size = UDim2.fromOffset(width - 24, 22)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 3
	holder.Parent = win
	local a, b = c(255, 154, 46), c(42, 26, 16)
	if k == "Shinobi" then
		a, b = c(168, 50, 45), c(234, 223, 189)
	elseif k == "Shinigami" then
		a, b = c(58, 45, 112), c(185, 168, 255)
	elseif k == "Pirate" then
		a, b = c(192, 57, 43), c(239, 227, 198)
	end
	local stripe = 26
	for i = 0, math.ceil((width - 24) / stripe) - 1 do
		local col = if i % 2 == 0 then a else b
		local s = box(holder, UDim2.fromOffset(i * stripe, 0), UDim2.fromOffset(stripe, 12), col, 0, 3)
		local scallop = box(s, UDim2.fromOffset(0, 5), UDim2.fromOffset(stripe, 14), col, 0, 3)
		corner(scallop, stripe / 2)
	end
	return holder
end

---------------------------------------------------------------------
-- PANELES / CASILLAS
---------------------------------------------------------------------
function NpcKit.Panel(parent: Instance, theme: any, size: UDim2, pos: UDim2, kind: string?): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local r = RADIUS[k]
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BorderSizePixel = 0
	f.BackgroundColor3 = if kind == "inset" then p.Inset else p.Panel
	f.Parent = parent
	corner(f, r[2])
	local plate = kind == "plate"
	stroke(f, if kind == "inset" then p.Edge2 else p.Edge, if plate then 2 else 1, if kind == "inset" then 0.2 else if plate then 0 else 0.45)
	return f
end

function NpcKit.Slot(parent: Instance, theme: any, size: UDim2, pos: UDim2): Frame
	local k = key(theme)
	local p = PALETTE[k]
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = p.Slot
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, RADIUS[k][2])
	stroke(f, p.Edge2, 2, 0.1)
	return f
end

---------------------------------------------------------------------
-- BOTONES / PESTAÑAS / ETIQUETAS
---------------------------------------------------------------------
local BTN: { [string]: { Color3 } } = {
	buy = { c(110, 210, 120), c(40, 130, 66) },
	sell = { c(235, 190, 80), c(160, 100, 24) },
	action = { c(110, 170, 255), c(44, 90, 180) },
	neutral = { c(110, 110, 130), c(60, 60, 78) },
	danger = { c(235, 100, 90), c(150, 40, 40) },
}

function NpcKit.Button(parent: Instance, theme: any, text: string, size: UDim2, pos: UDim2, kind: string?, cb: (() -> ())?): TextButton
	local k = key(theme)
	local p = PALETTE[k]
	local colors: { Color3 } = if kind == nil or kind == "action" or kind == "primary" then { p.BtnA, p.BtnB } else (BTN[kind] or BTN.neutral)
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = colors[2]
	b.TextColor3 = if colors[1] == p.BtnA then p.BtnText else Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.ZIndex = 10
	b.Parent = parent
	corner(b, RADIUS[k][2])
	gradient(b, colors[1], colors[2], 90)
	stroke(b, colors[1]:Lerp(Color3.new(1, 1, 1), 0.3), 1.2, 0.4)
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
	corner(b, RADIUS[k][2])
	if active then
		b.BackgroundColor3 = p.TabOn
		b.TextColor3 = p.TabOnText
		stroke(b, p.Edge, 2)
	else
		b.BackgroundColor3 = p.TabOff
		b.TextColor3 = p.TabOffText
		stroke(b, p.Edge2, 1, 0.3)
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
	t.TextColor3 = if color.R * 0.3 + color.G * 0.6 + color.B * 0.1 > 0.55 then c(40, 24, 4) else Color3.new(1, 1, 1)
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
	local p = PALETTE[k]
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = UDim2.fromOffset(width, 8)
	f.BorderSizePixel = 0
	f.ZIndex = 2
	f.BackgroundColor3 = p.Edge2
	f.Parent = parent
	gradient(f, p.Edge, p.Edge2, 90)
	corner(f, 3)
	return f
end

return NpcKit
