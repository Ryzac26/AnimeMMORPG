--!strict
--[[
    PatchNotesClient (LocalScript) -> StarterPlayer.StarterPlayerScripts
    NOVEDADES (rediseño): lista de versiones a la izquierda y el detalle de la elegida a la derecha
    (texto de ReplicatedStorage.Modules.PatchNotes), con el color de tu facción. La más nueva viene abierta.
    Al entrar al juego se muestra a los 3 s. Botón ENTENDIDO / ✕ para cerrar. Tecla N = abrir o cerrar.
    Los jugadores no pueden cambiar el contenido (se edita solo desde Studio).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Notes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PatchNotes"))
local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
local MOBILE = Platform.IsMobile()

local DEFAULT_ACCENT = Color3.fromRGB(165, 140, 255)
local DEFAULT_DARK = Color3.fromRGB(20, 16, 34)
local GREY = Color3.fromRGB(170, 176, 198)
local INK = Color3.fromRGB(20, 17, 10)
local LINE = Color3.fromRGB(74, 79, 108)

local function palette(): (Color3, Color3)
	local f = player:GetAttribute("Faction")
	if typeof(f) == "string" and UITheme.Themes[f] then
		local th = UITheme.For(f)
		return th.Primary, th.Dark
	end
	return DEFAULT_ACCENT, DEFAULT_DARK
end

local gui = Instance.new("ScreenGui")
gui.Name = "PatchNotes"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.38
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = if MOBILE then UDim2.fromScale(0.96, 0.92) else UDim2.fromScale(0.72, 0.8)
panel.BackgroundColor3 = Color3.fromRGB(17, 18, 27)
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = dim
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local limit = Instance.new("UISizeConstraint")
limit.MinSize = Vector2.new(320, 300)
limit.MaxSize = Vector2.new(920, 620)
limit.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Parent = panel

-- cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, if MOBILE then 46 else 60)
header.BorderSizePixel = 0
header.BackgroundColor3 = Color3.new(1, 1, 1)
header.Parent = panel
local headerGrad = Instance.new("UIGradient")
headerGrad.Parent = header

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(18, 0)
title.Size = UDim2.new(0, 220, 1, 0)
title.Font = Enum.Font.GothamBlack
title.TextSize = if MOBILE then 20 else 28
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "NOVEDADES"
title.Parent = header

local chip = Instance.new("TextLabel")
chip.AnchorPoint = Vector2.new(0, 0.5)
chip.Position = UDim2.new(0, if MOBILE then 140 else 200, 0.5, 0)
chip.Size = UDim2.fromOffset(if MOBILE then 56 else 70, if MOBILE then 18 else 22)
chip.Font = Enum.Font.GothamBold
chip.TextSize = if MOBILE then 10 else 12
chip.TextColor3 = INK
chip.Text = "ÚLTIMA"
chip.Parent = header
Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 11)

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0.5)
close.Position = UDim2.new(1, -14, 0.5, 0)
close.Size = UDim2.fromOffset(34, 34)
close.BackgroundTransparency = 1
close.Font = Enum.Font.GothamBold
close.TextSize = 18
close.TextColor3 = Color3.fromRGB(214, 218, 234)
close.Text = "✕"
close.Parent = header
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)
local closeStroke = Instance.new("UIStroke")
closeStroke.Color = LINE
closeStroke.Thickness = 2
closeStroke.Parent = close

-- pie
local footer = Instance.new("Frame")
footer.AnchorPoint = Vector2.new(0, 1)
footer.Position = UDim2.fromScale(0, 1)
footer.Size = UDim2.new(1, 0, 0, if MOBILE then 52 else 66)
footer.BackgroundTransparency = 1
footer.Parent = panel
local footLine = Instance.new("Frame")
footLine.Size = UDim2.new(1, 0, 0, 1)
footLine.BackgroundColor3 = Color3.new(1, 1, 1)
footLine.BackgroundTransparency = 0.88
footLine.BorderSizePixel = 0
footLine.Parent = footer
local hint = Instance.new("TextLabel")
hint.BackgroundTransparency = 1
hint.Position = UDim2.fromOffset(18, 0)
hint.Size = UDim2.new(1, -230, 1, 0)
hint.Font = Enum.Font.Gotham
hint.TextSize = if MOBILE then 11 else 14
hint.TextColor3 = GREY
hint.TextWrapped = true
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = if MOBILE then "Toca una versión para leerla" else "Toca una versión para leerla  ·  Pulsa N para abrir o cerrar las novedades"
hint.Parent = footer
local ok = Instance.new("TextButton")
ok.AnchorPoint = Vector2.new(1, 0.5)
ok.Position = UDim2.new(1, -18, 0.5, 0)
ok.Size = UDim2.fromOffset(if MOBILE then 130 else 190, if MOBILE then 36 else 44)
ok.Font = Enum.Font.GothamBold
ok.TextSize = if MOBILE then 15 else 20
ok.TextColor3 = INK
ok.Text = "ENTENDIDO"
ok.Parent = footer
Instance.new("UICorner", ok).CornerRadius = UDim.new(0, 8)

-- cuerpo: lista a la izquierda, detalle a la derecha
local bodyTop = if MOBILE then 46 else 60
local bodyBottom = if MOBILE then 52 else 66
local listW = if MOBILE then 118 else 240

local listFrame = Instance.new("ScrollingFrame")
listFrame.Position = UDim2.fromOffset(0, bodyTop)
listFrame.Size = UDim2.new(0, listW, 1, -(bodyTop + bodyBottom))
listFrame.BackgroundColor3 = Color3.new(1, 1, 1)
listFrame.BackgroundTransparency = 0.97
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 4
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.CanvasSize = UDim2.new()
listFrame.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = listFrame
local listPad = Instance.new("UIPadding")
listPad.PaddingTop, listPad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
listPad.PaddingLeft, listPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
listPad.Parent = listFrame

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(listW, bodyTop)
divider.Size = UDim2.new(0, 1, 1, -(bodyTop + bodyBottom))
divider.BackgroundColor3 = Color3.new(1, 1, 1)
divider.BackgroundTransparency = 0.9
divider.BorderSizePixel = 0
divider.Parent = panel

local detail = Instance.new("ScrollingFrame")
detail.Position = UDim2.fromOffset(listW + 1, bodyTop)
detail.Size = UDim2.new(1, -(listW + 1), 1, -(bodyTop + bodyBottom))
detail.BackgroundTransparency = 1
detail.BorderSizePixel = 0
detail.ScrollBarThickness = 5
detail.AutomaticCanvasSize = Enum.AutomaticSize.Y
detail.CanvasSize = UDim2.new()
detail.Parent = panel
local detailLayout = Instance.new("UIListLayout")
detailLayout.Padding = UDim.new(0, 8)
detailLayout.SortOrder = Enum.SortOrder.LayoutOrder
detailLayout.Parent = detail
local detailPad = Instance.new("UIPadding")
detailPad.PaddingTop, detailPad.PaddingBottom = UDim.new(0, 14), UDim.new(0, 14)
detailPad.PaddingLeft, detailPad.PaddingRight = UDim.new(0, if MOBILE then 12 else 24), UDim.new(0, if MOBILE then 12 else 24)
detailPad.Parent = detail

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
	return l
end

local selected = 1
local buttons: { { Btn: TextButton, Stroke: UIStroke, Num: TextLabel } } = {}
local accentMarks: { Frame } = {}
local accentTexts: { TextLabel } = {}

local function renderDetail()
	for _, c in ipairs(detail:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	accentMarks, accentTexts = {}, {}
	local accent = palette()
	local entry = Notes[selected]
	if not entry then
		return
	end
	local order = 0
	order += 1
	local top = Instance.new("Frame")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 0)
	top.AutomaticSize = Enum.AutomaticSize.Y
	top.LayoutOrder = order
	top.Parent = detail
	local tl = Instance.new("UIListLayout")
	tl.Padding = UDim.new(0, 2)
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Parent = top
	local v = label(top, string.format("v%s   ·   %s", entry.Version, entry.Date), if MOBILE then 13 else 16, accent, Enum.Font.GothamBold, 1)
	table.insert(accentTexts, v)
	label(top, entry.Title, if MOBILE then 20 else 28, Color3.new(1, 1, 1), Enum.Font.GothamBlack, 2)
	for _, sec in ipairs(entry.Sections) do
		order += 1
		local block = Instance.new("Frame")
		block.BackgroundTransparency = 1
		block.Size = UDim2.new(1, 0, 0, 0)
		block.AutomaticSize = Enum.AutomaticSize.Y
		block.LayoutOrder = order
		block.Parent = detail
		local bl = Instance.new("UIListLayout")
		bl.Padding = UDim.new(0, 4)
		bl.SortOrder = Enum.SortOrder.LayoutOrder
		bl.Parent = block
		local head = Instance.new("Frame")
		head.BackgroundTransparency = 1
		head.Size = UDim2.new(1, 0, 0, if MOBILE then 22 else 26)
		head.LayoutOrder = 1
		head.Parent = block
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0, 0.5)
		bar.Position = UDim2.fromScale(0, 0.5)
		bar.Size = UDim2.fromOffset(4, if MOBILE then 16 else 20)
		bar.BackgroundColor3 = accent
		bar.BorderSizePixel = 0
		bar.Parent = head
		table.insert(accentMarks, bar)
		local hl = label(head, string.upper(sec.Header), if MOBILE then 15 else 19, Color3.new(1, 1, 1), Enum.Font.GothamBold, 1)
		hl.Position = UDim2.fromOffset(12, 0)
		hl.Size = UDim2.new(1, -12, 1, 0)
		hl.AutomaticSize = Enum.AutomaticSize.None
		hl.TextYAlignment = Enum.TextYAlignment.Center
		for i, item in ipairs(sec.Items) do
			local l = label(block, "•  " .. item, if MOBILE then 13 else 16, Color3.fromRGB(211, 216, 232), Enum.Font.Gotham, 1 + i)
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 10)
			pad.Parent = l
		end
	end
	detail.CanvasPosition = Vector2.zero
end

local function recolor()
	local accent, dark = palette()
	stroke.Color = accent
	headerGrad.Color = ColorSequence.new(dark, Color3.fromRGB(17, 18, 27))
	title.TextColor3 = accent
	chip.BackgroundColor3 = accent
	ok.BackgroundColor3 = accent
	for i, b in ipairs(buttons) do
		local on = i == selected
		b.Btn.BackgroundColor3 = accent
		b.Btn.BackgroundTransparency = if on then 0.88 else 1
		b.Stroke.Color = accent
		b.Stroke.Transparency = if on then 0 else 1
		b.Num.TextColor3 = if on then accent else Color3.fromRGB(228, 231, 242)
	end
	chip.Visible = selected == 1
end

local function selectVersion(i: number)
	selected = i
	renderDetail()
	recolor()
end

for index, entry in ipairs(Notes) do
	local b = Instance.new("TextButton")
	b.LayoutOrder = index
	b.Size = UDim2.new(1, 0, 0, if MOBILE then 48 else 56)
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.Parent = listFrame
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local st = Instance.new("UIStroke")
	st.Thickness = 1
	st.Parent = b
	local num = label(b, "v" .. entry.Version, if MOBILE then 14 else 17, Color3.new(1, 1, 1), Enum.Font.GothamBold, 0)
	num.Position = UDim2.fromOffset(10, 5)
	num.Size = UDim2.new(1, -16, 0, 18)
	num.AutomaticSize = Enum.AutomaticSize.None
	local sub = label(b, entry.Title, if MOBILE then 10 else 12, Color3.fromRGB(182, 188, 208), Enum.Font.Gotham, 0)
	sub.Position = UDim2.fromOffset(10, if MOBILE then 22 else 25)
	sub.Size = UDim2.new(1, -16, 0, if MOBILE then 24 else 28)
	sub.AutomaticSize = Enum.AutomaticSize.None
	sub.TextTruncate = Enum.TextTruncate.AtEnd
	buttons[index] = { Btn = b, Stroke = st, Num = num }
	b.Activated:Connect(function()
		selectVersion(index)
	end)
end

close.Activated:Connect(function()
	gui.Enabled = false
end)
ok.Activated:Connect(function()
	gui.Enabled = false
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.N then
		gui.Enabled = not gui.Enabled
	end
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	renderDetail()
	recolor()
end)

selectVersion(1)

task.delay(3, function()
	gui.Enabled = true
end)
