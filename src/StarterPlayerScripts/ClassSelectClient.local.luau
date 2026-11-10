--!strict
--[[
    ClassSelectClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ClassSelectClient
    PANTALLA DE SELECCIÓN (rediseño): paso 1 = elegir facción (tarjeta + CONTINUAR), paso 2 = elegir rol (personaje),
    confirmar -> el servidor te manda a tu ciudad.
    Solo aparece si el servidor marca ClassChosen = false (jugador nuevo). El cliente solo PIDE; el servidor valida.
    Mismo flujo y mismo mensaje al servidor que antes: ChooseClass(facción, rol).
    En móvil: facciones 2x2 y roles en 2 columnas.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local FactionClasses = require(Modules:WaitForChild("FactionClassesModule", 10))
local ClassStats = require(Modules:WaitForChild("ClassStats", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local chooseRemote = Remotes:WaitForChild("ChooseClass", 10) :: RemoteEvent
local WindowKit = require(script.Parent:WaitForChild("WindowKit"))
local MOBILE = Platform.IsMobile()
-- el pergamino de Shinobi es claro y el texto de estas pantallas es claro: se oscurece a verde para que se lea
local function tintFor(faction: string, col: Color3): Color3
	if faction == "Shinobi" then
		return Color3.new(col.R * 0.55, col.G * 0.7, col.B * 0.55)
	end
	return col
end
local Workspace = game:GetService("Workspace")

local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
local ROLE_HINT: { [string]: string } = {
	Tanque = "Aguanta el daño y protege al grupo",
	Guerrero = "Daño equilibrado cuerpo a cuerpo",
	Asesino = "Mucho daño, poca vida, muy veloz",
	Tirador = "Daño a larga distancia",
	Mago = "Daño en área",
	Curador = "Cura y apoya al equipo",
}
local ROLE_GLYPH: { [string]: string } = { Tanque = "盾", Guerrero = "剣", Asesino = "影", Tirador = "弓", Mago = "魔", Curador = "癒" }
local ANIME: { [string]: string } = { Saiyan = "GUERREROS DE ÉLITE", Shinobi = "SHINOBI DEL SIGILO", Pirate = "NAVEGANTES DE LOS MARES", Shinigami = "GUARDIANES ESPIRITUALES" }

local DEFAULT_ACCENT = Color3.fromRGB(255, 190, 70)
local BG_TOP = Color3.fromRGB(26, 28, 46)
local BG_BOTTOM = Color3.fromRGB(11, 12, 20)
local GREY = Color3.fromRGB(170, 176, 198)
local INK = Color3.fromRGB(20, 17, 10)
local LINE = Color3.fromRGB(74, 79, 108)

local gui = Instance.new("ScreenGui")
gui.Name = "ClassSelectGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local selectedFaction: string? = nil
local selectedRole: string? = nil
local root: Frame? = nil

local function clear(): Frame
	if root then
		root:Destroy()
	end
	local r = Instance.new("Frame")
	r.Size = UDim2.fromScale(1, 1)
	r.BackgroundColor3 = Color3.new(1, 1, 1)
	r.BorderSizePixel = 0
	r.Active = true -- bloquea clics al mundo
	r.Parent = gui
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(BG_TOP, BG_BOTTOM)
	g.Rotation = 90
	g.Parent = r
	root = r
	return r
end

local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3, anchor: Vector2?, radius: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = anchor or Vector2.zero
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	if radius then
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, radius)
	end
	return f
end

local function text(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?, font: Enum.Font?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align or Enum.TextXAlignment.Center)
	l.Font = font or UITheme.Font
	l.TextTruncate = Enum.TextTruncate.AtEnd
	return l
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- botón grande (relleno de color, texto oscuro) o de contorno
local function bigButton(parent: Instance, label: string, pos: UDim2, size: UDim2, color: Color3, outline: boolean?): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = pos
	b.Size = size
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = if MOBILE then 16 else 22
	b.Text = label
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	if outline then
		b.BackgroundTransparency = 1
		b.TextColor3 = Color3.fromRGB(214, 218, 234)
		stroke(b, LINE, 2)
	else
		b.BackgroundColor3 = color
		b.TextColor3 = INK
	end
	return b
end

-- indicador de pasos: 1 FACCIÓN — 2 ROL
local function stepBar(parent: Instance, step: number, accent: Color3, y: number)
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, y, 0)
	row.Size = UDim2.fromOffset(if MOBILE then 230 else 300, 30)
	row.BackgroundTransparency = 1
	row.Parent = parent
	local function dot(x: number, n: string, state: string)
		local d = frame(row, UDim2.fromOffset(x, 0), UDim2.fromOffset(28, 28), accent, nil, 14)
		if state == "now" then
			d.BackgroundColor3 = accent
		else
			d.BackgroundTransparency = 1
			stroke(d, if state == "done" then accent else LINE, 2)
		end
		local l = text(d, n, 16, if state == "now" then INK else (if state == "done" then accent else GREY), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
		l.TextStrokeTransparency = 1
		l.Font = Enum.Font.GothamBold
	end
	dot(0, "1", if step == 1 then "now" else "done")
	text(row, "FACCIÓN", 14, if step == 1 then Color3.new(1, 1, 1) else GREY, UDim2.fromOffset(34, 0), UDim2.fromOffset(80, 28), Enum.TextXAlignment.Left).TextStrokeTransparency = 1
	frame(row, UDim2.fromOffset(if MOBILE then 118 else 124, 13), UDim2.fromOffset(if MOBILE then 24 else 40, 2), if step == 2 then accent else LINE)
	local x2 = if MOBILE then 148 else 172
	dot(x2, "2", if step == 2 then "now" else "idle")
	text(row, "ROL", 14, if step == 2 then Color3.new(1, 1, 1) else GREY, UDim2.fromOffset(x2 + 34, 0), UDim2.fromOffset(60, 28), Enum.TextXAlignment.Left).TextStrokeTransparency = 1
end

local showFactions: () -> ()
local showRoles: () -> ()

local function waiting()
	local r = clear()
	text(r, "Viajando a tu ciudad...", 30, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.45), UDim2.fromScale(1, 0.1))
end

---------------------------------------------------------------------
-- PASO 1: FACCIÓN
---------------------------------------------------------------------
showFactions = function()
	local r = clear()
	local picked = selectedFaction
	local accent = if picked then UITheme.For(picked).Primary else DEFAULT_ACCENT
	stepBar(r, 1, accent, 0.035)
	text(r, "ELIGE TU FACCIÓN", if MOBILE then 28 else 46, Color3.new(1, 1, 1), UDim2.fromScale(0, if MOBILE then 0.1 else 0.09), UDim2.fromScale(1, 0.09), nil, Enum.Font.GothamBlack)
	local sub = text(r, "Defenderás a tu nación en las franjas PvE y en la Arena Central", if MOBILE then 13 else 18, GREY, UDim2.fromScale(0.05, if MOBILE then 0.185 else 0.185), UDim2.fromScale(0.9, 0.05))
	sub.TextStrokeTransparency = 1

	local cards: { [string]: { Card: TextButton, Stroke: UIStroke, Badge: Frame, Base: UDim2 } } = {}
	local countLabels: { [string]: TextLabel } = {}
	-- cupo por facción en este servidor (FactionBalance publica FactionCap y FactionCount_<facción> en Workspace; cap 0 = sin tope)
	local function isFull(f: string): boolean
		local cap = Workspace:GetAttribute("FactionCap")
		local n = Workspace:GetAttribute("FactionCount_" .. f)
		return typeof(cap) == "number" and cap > 0 and typeof(n) == "number" and n >= cap
	end
	local function refreshCounts()
		local cap = Workspace:GetAttribute("FactionCap")
		for f, lbl in pairs(countLabels) do
			local n = Workspace:GetAttribute("FactionCount_" .. f)
			if typeof(cap) == "number" and cap > 0 and typeof(n) == "number" then
				lbl.Text = if n >= cap then string.format("LLENA  %d/%d", n, cap) else string.format("Jugadores  %d/%d", n, cap)
				lbl.TextColor3 = if n >= cap then Color3.fromRGB(255, 110, 110) else Color3.fromRGB(170, 176, 200)
			else
				lbl.Text = ""
			end
		end
	end
	local cont: TextButton
	local pickedLabel: TextLabel

	local function applySelection()
		local f = selectedFaction
		for id, c in pairs(cards) do
			local on = id == f
			local theme = UITheme.For(id)
			c.Stroke.Color = if on then theme.Primary else Color3.fromRGB(70, 74, 98)
			c.Stroke.Thickness = if on then 3 else 2
			c.Badge.Visible = on
			if c.Img then
				c.Img.ImageColor3 = tintFor(id, if f == nil or on then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 130))
			else
				c.Card.BackgroundTransparency = if f == nil or on then 0 else 0.25
			end
			TweenService:Create(c.Card, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Position = c.Base - UDim2.fromOffset(0, if on then 8 else 0) }):Play()
		end
		if f then
			local th = UITheme.For(f)
			cont.BackgroundColor3 = th.Primary
			cont.TextColor3 = INK
			cont.Active = true
			pickedLabel.Text = "Elegida: " .. th.Faction
			pickedLabel.TextColor3 = th.Primary
		else
			cont.BackgroundColor3 = Color3.fromRGB(60, 62, 80)
			cont.TextColor3 = Color3.fromRGB(150, 154, 176)
			cont.Active = false
			pickedLabel.Text = "Toca una facción para elegirla"
			pickedLabel.TextColor3 = GREY
		end
	end

	local cols = if MOBILE then 2 else 4
	local cw = if MOBILE then 0.44 else 0.215
	local ch = if MOBILE then 0.3 else 0.5
	local top = if MOBILE then 0.25 else 0.27
	for i, f in ipairs(FACTIONS) do
		local theme = UITheme.For(f)
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local base = UDim2.fromScale(0.5 + (col - (cols - 1) / 2) * (cw + 0.02), top + row * (ch + 0.02))
		local card = Instance.new("TextButton")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = base
		card.Size = UDim2.fromScale(cw, ch)
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.Text = ""
		card.AutoButtonColor = false
		card.Parent = r
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(theme.Dark, Color3.fromRGB(13, 14, 24))
		g.Rotation = 90
		g.Parent = card
		local st = stroke(card, Color3.fromRGB(70, 74, 98), 2)
		local kit = WindowKit.Get(f)
		local cardImg: ImageLabel? = nil
		if kit then
			-- tarjeta alta con el marco de la facción + emblema que flota y respira
			card.BackgroundTransparency = 1
			g:Destroy()
			st.Transparency = 1
			local ci = Instance.new("ImageLabel")
			ci.Name = "Marco"
			ci.BackgroundTransparency = 1
			ci.Image = kit.cardTall
			ci.ScaleType = Enum.ScaleType.Slice
			ci.SliceCenter = Rect.new(100, 100, 412, 668)
			ci.SliceScale = if MOBILE then 0.3 else 0.45
			ci.Size = UDim2.fromScale(1, 1)
			ci.ZIndex = 0
			ci.Parent = card
			ci.ImageColor3 = tintFor(f, Color3.new(1, 1, 1))
			cardImg = ci
			local em = Instance.new("ImageLabel")
			em.Name = "Emblema"
			em.BackgroundTransparency = 1
			em.Image = kit.emblem
			em.AnchorPoint = Vector2.new(0.5, 0.5)
			em.Position = UDim2.fromScale(0.5, if MOBILE then 0.3 else 0.3)
			em.Size = UDim2.fromScale(if MOBILE then 0.62 else 0.66, 0)
			local ar = Instance.new("UIAspectRatioConstraint")
			ar.AspectRatio = 1
			ar.Parent = em
			em.Size = UDim2.fromScale(if MOBILE then 0.62 else 0.66, 0.66)
			em.ZIndex = 2
			em.Parent = card
			TweenService:Create(em, TweenInfo.new(2.6 + i * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.5, 0.3 - 0.018), Rotation = 4 }):Play()
			TweenService:Create(em, TweenInfo.new(1.8 + i * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { ImageTransparency = 0.25 }):Play()
		end

		local badge = frame(card, UDim2.fromScale(0.5, 0.035), UDim2.fromOffset(if MOBILE then 78 else 100, if MOBILE then 18 else 24), theme.Primary, Vector2.new(0.5, 0), 12)
		local bl = text(badge, "ELEGIDA", if MOBILE then 11 else 14, INK, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), nil, Enum.Font.GothamBold)
		bl.TextStrokeTransparency = 1
		badge.Visible = false

		local kanji = text(card, if kit then "" else theme.Emblem, if MOBILE then 56 else 110, theme.Primary, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, if MOBILE then 0.4 else 0.4), nil, Enum.Font.GothamBlack)
		kanji.TextStrokeColor3 = theme.Secondary
		kanji.TextStrokeTransparency = 0.7
		kanji.TextTruncate = Enum.TextTruncate.None
		text(card, string.upper(theme.Faction), if MOBILE then 15 else 24, theme.Primary, UDim2.fromScale(0.02, 0.52), UDim2.fromScale(0.96, 0.12), nil, Enum.Font.GothamBlack)
		local chip = frame(card, UDim2.fromScale(0.5, 0.66), UDim2.fromScale(0.7, 0.1), Color3.new(0, 0, 0), Vector2.new(0.5, 0), 5)
		chip.BackgroundTransparency = 0.6
		stroke(chip, Color3.fromRGB(70, 74, 98), 1)
		local al = text(chip, ANIME[f], if MOBILE then 11 else 14, Color3.fromRGB(200, 205, 222), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1))
		al.TextStrokeTransparency = 1
		local div = frame(card, UDim2.fromScale(0.1, 0.8), UDim2.new(0.8, 0, 0, 1), Color3.new(1, 1, 1))
		div.BackgroundTransparency = 0.85
		local en = text(card, "ENERGÍA  " .. theme.Resource, if MOBILE then 12 else 16, theme.ResourceColor, UDim2.fromScale(0, 0.84), UDim2.fromScale(1, 0.1))
		en.Font = Enum.Font.GothamBold

		local cnt = text(card, "", if MOBILE then 11 else 14, GREY, UDim2.fromScale(0, 0.93), UDim2.fromScale(1, 0.06))
		cnt.Font = Enum.Font.GothamBold
		cnt.TextStrokeTransparency = 1
		countLabels[f] = cnt
		cards[f] = { Card = card, Stroke = st, Badge = badge, Base = base, Img = cardImg }
		card.Activated:Connect(function()
			if isFull(f) then
				pickedLabel.Text = f .. " está llena en este servidor"
				pickedLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
				return
			end
			selectedFaction = f
			selectedRole = nil
			applySelection()
		end)
	end

	refreshCounts()
	local conn: RBXScriptConnection
	conn = Workspace.AttributeChanged:Connect(function()
		if cont and cont.Parent then
			refreshCounts()
		else
			conn:Disconnect()
		end
	end)
	local bottomY = if MOBILE then 0.9 else 0.88
	pickedLabel = text(r, "", if MOBILE then 14 else 18, GREY, UDim2.fromScale(0.08, bottomY), UDim2.fromScale(if MOBILE then 0.4 else 0.35, 0.07), Enum.TextXAlignment.Left)
	pickedLabel.TextStrokeTransparency = 1
	pickedLabel.Font = Enum.Font.GothamBold
	cont = bigButton(r, "CONTINUAR  ›", UDim2.fromScale(if MOBILE then 0.76 else 0.7, bottomY), UDim2.fromScale(if MOBILE then 0.36 else 0.24, 0.07), Color3.fromRGB(60, 62, 80))
	cont.Activated:Connect(function()
		if selectedFaction then
			showRoles()
		end
	end)
	applySelection()
end

---------------------------------------------------------------------
-- PASO 2: ROL
---------------------------------------------------------------------
showRoles = function()
	local faction = selectedFaction
	if not faction then
		return
	end
	local theme = UITheme.For(faction)
	local accent = theme.Primary
	local r = clear()

	-- panel de la facción (solo en pantallas grandes)
	local gridLeft = 0.04
	if not MOBILE then
		local side = frame(r, UDim2.fromScale(0.04, 0.07), UDim2.fromScale(0.22, 0.8), Color3.new(1, 1, 1), nil, 14)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(theme.Dark, Color3.fromRGB(13, 14, 24))
		g.Rotation = 90
		g.Parent = side
		stroke(side, accent, 2)
		text(side, "TU FACCIÓN", 14, GREY, UDim2.fromScale(0, 0.04), UDim2.fromScale(1, 0.06))
		local k = text(side, theme.Emblem, 120, accent, UDim2.fromScale(0, 0.12), UDim2.fromScale(1, 0.38), nil, Enum.Font.GothamBlack)
		k.TextStrokeColor3 = theme.Secondary
		k.TextStrokeTransparency = 0.7
		k.TextTruncate = Enum.TextTruncate.None
		text(side, string.upper(theme.Faction), 22, accent, UDim2.fromScale(0.02, 0.52), UDim2.fromScale(0.96, 0.08), nil, Enum.Font.GothamBlack)
		text(side, ANIME[faction], 14, Color3.fromRGB(200, 205, 222), UDim2.fromScale(0, 0.61), UDim2.fromScale(1, 0.06))
		text(side, "ENERGÍA  " .. theme.Resource, 15, theme.ResourceColor, UDim2.fromScale(0, 0.69), UDim2.fromScale(1, 0.06))
		local back = bigButton(side, "‹  CAMBIAR FACCIÓN", UDim2.fromScale(0.5, 0.84), UDim2.fromScale(0.88, 0.09), accent, true)
		back.TextSize = 15
		back.Activated:Connect(function()
			showFactions()
		end)
		gridLeft = 0.3
	end

	local gridW = 1 - gridLeft - 0.04
	stepBar(r, 2, accent, 0.03)
	text(r, if MOBILE then string.upper(theme.Faction) .. " — ELIGE TU ROL" else "ELIGE TU ROL", if MOBILE then 22 else 42, Color3.new(1, 1, 1), UDim2.fromScale(gridLeft, if MOBILE then 0.09 else 0.1), UDim2.fromScale(gridW, 0.08), if MOBILE then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left, Enum.Font.GothamBlack)
	if not MOBILE then
		local sub = text(r, "Tu rol decide cómo peleas y qué habilidades usarás.", 17, GREY, UDim2.fromScale(gridLeft, 0.18), UDim2.fromScale(gridW, 0.05), Enum.TextXAlignment.Left)
		sub.TextStrokeTransparency = 1
	end

	local detail = Instance.new("TextLabel")
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromScale(gridLeft, if MOBILE then 0.78 else 0.745)
	detail.Size = UDim2.fromScale(gridW, if MOBILE then 0.09 else 0.1)
	detail.Font = Enum.Font.Gotham
	detail.TextSize = if MOBILE then 12 else 16
	detail.TextColor3 = Color3.fromRGB(205, 210, 228)
	detail.TextWrapped = true
	detail.RichText = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.Text = "Toca un personaje para ver sus datos"
	detail.Parent = r

	local confirm: TextButton
	local cards: { [string]: { Card: TextButton, Stroke: UIStroke, Glyph: TextLabel, Name: TextLabel } } = {}
	local cols = if MOBILE then 2 else 3
	local rows = math.ceil(#ROLES / cols)
	local top = if MOBILE then 0.17 else 0.255
	local areaH = if MOBILE then 0.58 else 0.47
	local gap = 0.015
	local cw = (gridW - gap * (cols - 1)) / cols
	local chh = (areaH - gap * (rows - 1)) / rows

	for i, role in ipairs(ROLES) do
		local class = FactionClasses.FindClass(faction, role)
		if class then
			local col = (i - 1) % cols
			local row = math.floor((i - 1) / cols)
			local card = Instance.new("TextButton")
			card.Position = UDim2.fromScale(gridLeft + col * (cw + gap), top + row * (chh + gap))
			card.Size = UDim2.fromScale(cw, chh)
			card.BackgroundColor3 = Color3.fromRGB(26, 28, 40)
			card.Text = ""
			card.AutoButtonColor = false
			card.Parent = r
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)
			local st = stroke(card, Color3.fromRGB(70, 74, 98), 2)
			local rkit = WindowKit.Get(faction)
			local rimg: ImageLabel? = nil
			if rkit then
				card.BackgroundTransparency = 1
				st.Transparency = 1
				local ri = Instance.new("ImageLabel")
				ri.BackgroundTransparency = 1
				ri.Image = rkit.card
				ri.ScaleType = Enum.ScaleType.Slice
				ri.SliceCenter = Rect.new(48, 48, 208, 208)
				ri.SliceScale = 0.4
				ri.Size = UDim2.fromScale(1, 1)
				ri.ImageColor3 = tintFor(faction, Color3.fromRGB(170, 170, 180))
				ri.ZIndex = 0
				ri.Parent = card
				rimg = ri
			end
			local glyph = text(card, ROLE_GLYPH[role] or "?", if MOBILE then 34 else 46, GREY, UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.3, 0.45), Enum.TextXAlignment.Left, Enum.Font.GothamBlack)
			glyph.TextTruncate = Enum.TextTruncate.None
			glyph.TextStrokeTransparency = 1
			local nameL = text(card, string.upper(role), if MOBILE then 16 else 24, Color3.new(1, 1, 1), UDim2.fromScale(0.34, 0.08), UDim2.fromScale(0.62, 0.3), Enum.TextXAlignment.Left, Enum.Font.GothamBlack)
			nameL.TextStrokeTransparency = 1
			local who = text(card, class.DisplayName, if MOBILE then 12 else 15, accent, UDim2.fromScale(0.34, 0.34), UDim2.fromScale(0.62, 0.2), Enum.TextXAlignment.Left)
			who.TextStrokeTransparency = 1
			local hint = text(card, ROLE_HINT[role] or "", if MOBILE then 11 else 15, Color3.fromRGB(182, 188, 208), UDim2.fromScale(0.05, 0.58), UDim2.fromScale(0.9, 0.38), Enum.TextXAlignment.Left)
			hint.TextWrapped = true
			hint.TextTruncate = Enum.TextTruncate.None
			hint.TextYAlignment = Enum.TextYAlignment.Top
			hint.TextStrokeTransparency = 1
			cards[role] = { Card = card, Stroke = st, Glyph = glyph, Name = nameL, Img = rimg }
			card.Activated:Connect(function()
				selectedRole = role
				for rn, c in pairs(cards) do
					local on = rn == role
					if c.Img then
						c.Img.ImageColor3 = tintFor(faction, if on then Color3.new(1, 1, 1) else Color3.fromRGB(170, 170, 180))
					else
						c.Card.BackgroundColor3 = if on then theme.Dark else Color3.fromRGB(26, 28, 40)
					end
					c.Stroke.Color = if on then accent else Color3.fromRGB(70, 74, 98)
					c.Stroke.Thickness = if on then 3 else 2
					c.Glyph.TextColor3 = if on then accent else GREY
					c.Name.TextColor3 = if on then accent else Color3.new(1, 1, 1)
				end
				detail.Text = string.format(
					"<b>%s</b> (%s) — Vida %d · %s %d · Reducción de daño %d%% · Velocidad %d\n<b>Atributos:</b> FUE %d · DES %d · INT %d · VIT %d · ESP %d  (principal: %s)\n<b>%s:</b> %s",
					class.DisplayName, class.AnimeSource, ClassStats.BaseHp(class.Role), theme.Resource, class.BaseEnergy,
					math.floor(ClassStats.Mitigation(class.Role) * 100 + 0.5), class.WalkSpeed,
					ClassStats.Get(class.Role).FUE, ClassStats.Get(class.Role).DES, ClassStats.Get(class.Role).INT, ClassStats.Get(class.Role).VIT, ClassStats.Get(class.Role).ESP,
					ClassStats.Names[ClassStats.Main(class.Role)], class.PrimarySkill.Name, class.PrimarySkill.Description
				)
				confirm.BackgroundColor3 = accent
				confirm.TextColor3 = INK
				confirm.Active = true
				confirm.Text = string.format("CONFIRMAR: %s", string.upper(role))
			end)
		end
	end

	local bottomY = if MOBILE then 0.9 else 0.88
	local backBtn: TextButton? = nil
	if MOBILE then
		backBtn = bigButton(r, "‹ VOLVER", UDim2.fromScale(0.24, bottomY), UDim2.fromScale(0.36, 0.07), accent, true)
	else
		local who = text(r, "Elige un rol para continuar", 18, GREY, UDim2.fromScale(gridLeft, bottomY), UDim2.fromScale(0.35, 0.07), Enum.TextXAlignment.Left)
		who.TextStrokeTransparency = 1
		who.Name = "Hint"
	end
	if backBtn then
		backBtn.Activated:Connect(function()
			showFactions()
		end)
	end
	confirm = bigButton(r, "CONFIRMAR Y ENTRAR", UDim2.fromScale(if MOBILE then 0.7 else 0.8, bottomY), UDim2.fromScale(if MOBILE then 0.5 else 0.3, 0.07), Color3.fromRGB(60, 62, 80))
	confirm.TextColor3 = Color3.fromRGB(150, 154, 176)
	confirm.Active = false
	confirm.Activated:Connect(function()
		local f, ro = selectedFaction, selectedRole
		if not f or not ro then
			return
		end
		chooseRemote:FireServer(f, ro)
		waiting()
	end)
end

local function refresh()
	local chosen = player:GetAttribute("ClassChosen")
	if chosen == false then
		if not gui.Enabled then
			gui.Enabled = true
			showFactions()
		end
	elseif chosen == true then
		if gui.Enabled then
			-- el servidor ya aceptó la elección: espera a que reaparezca en su ciudad y cierra
			task.delay(1.5, function()
				if player:GetAttribute("ClassChosen") == true then
					gui.Enabled = false
				end
			end)
		end
	end
end

player:GetAttributeChangedSignal("ClassChosen"):Connect(refresh)
refresh()
