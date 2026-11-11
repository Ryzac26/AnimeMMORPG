--!strict
--[[
    InventoryClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > InventoryClient
    MOCHILA (unida al Perfil, tecla C). Cuadrícula de 5 columnas que CRECE sola: cuando llenas todas las casillas aparece otra fila.
    Clic en un objeto = seleccionarlo (ver detalle abajo). Clic en otra casilla = mover/intercambiar.
    Botones: Equipar (si tiene ranura) y Tirar.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))
local GearView = require(script.Parent:WaitForChild("GearView", 10))
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local BagCatalog = require(ReplicatedStorage.Modules.BagCatalog)
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local BagDock = require(script.Parent:WaitForChild("BagDock", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

-- La mochila ya NO es una ventana propia: es un panel (528x594) que se acopla dentro de "Equipo y Mochila" (CharacterClient).
local pgui = player:WaitForChild("PlayerGui", 10)
local ghostGui = Instance.new("ScreenGui") -- solo para el objeto que arrastras
ghostGui.Name = "InventoryGhost"
ghostGui.ResetOnSpawn = false
ghostGui.IgnoreGuiInset = true
ghostGui.DisplayOrder = 200
ghostGui.Parent = pgui

local theme = UITheme.For(player:GetAttribute("Faction"))
local pal = NpcKit.Palette(theme)
local selected: number? = nil
local currentPage = 1

local win = Instance.new("Frame") -- panel acoplable
win.Name = "BagPanel"
win.Size = UDim2.fromOffset(528, 594)
win.BackgroundTransparency = 1
win.BorderSizePixel = 0

local DARK = Color3.fromRGB(22, 20, 28)
local LIGHT = Color3.fromRGB(235, 232, 240)

local capLabel = UITheme.Text(win, "", 12, pal.Muted, UDim2.fromOffset(448, 10), UDim2.fromOffset(78, 20), Enum.TextXAlignment.Right)
capLabel.ZIndex = 5
local bestBtn = NpcKit.Button(win, theme, "★ Mejor set", UDim2.fromOffset(84, 24), UDim2.fromOffset(268, 6), "action", function()
	Store.Action("EquipBest")
end)
bestBtn.TextSize = 12
local sortBtn = NpcKit.Button(win, theme, "Ordenar", UDim2.fromOffset(70, 24), UDim2.fromOffset(358, 6), "neutral", function()
	selected = nil
	Store.Action("Sort") -- junta lo apilable y ordena por rareza
end)
sortBtn.TextSize = 12

local gridBox = NpcKit.Panel(win, theme, UDim2.fromOffset(528, 304), UDim2.fromOffset(0, 36), "inset")
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(8, 8)
scroll.Size = UDim2.fromOffset(512, 288)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ZIndex = 3
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.Parent = gridBox
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(56, 56)
grid.CellPadding = UDim2.fromOffset(6, 6)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

-- Panel de COMPARACIÓN: objeto seleccionado vs lo que llevas puesto (siempre oscuro para que se lea en todas las facciones)
local cmp = Instance.new("ScrollingFrame")
cmp.Name = "Compare"
cmp.Position = UDim2.fromOffset(0, 392)
cmp.Size = UDim2.fromOffset(528, 154)
cmp.BackgroundColor3 = DARK
cmp.BorderSizePixel = 0
cmp.ScrollBarThickness = 4
cmp.AutomaticCanvasSize = Enum.AutomaticSize.Y
cmp.CanvasSize = UDim2.fromOffset(0, 0)
cmp.Visible = false
cmp.ZIndex = 3
cmp.Parent = win
Instance.new("UICorner", cmp).CornerRadius = UDim.new(0, 6)
local cmpStroke = Instance.new("UIStroke")
cmpStroke.Color = pal.Edge2
cmpStroke.Thickness = 1.5
cmpStroke.Parent = cmp
local cmpPad = Instance.new("UIPadding")
cmpPad.PaddingTop, cmpPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
cmpPad.PaddingLeft, cmpPad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
cmpPad.Parent = cmp
local cmpList = Instance.new("UIListLayout")
cmpList.Padding = UDim.new(0, 5)
cmpList.SortOrder = Enum.SortOrder.LayoutOrder
cmpList.Parent = cmp

local function cmpLabel(order: number, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Font = UITheme.Font
	t.TextSize = size
	t.TextColor3 = LIGHT
	t.TextWrapped = true
	t.RichText = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = ""
	t.ZIndex = 4
	t.Parent = cmp
	return t
end
local cmpVerdict = cmpLabel(1, 15)
local cmpBody = cmpLabel(2, 12)

local GREEN, RED, GRAY, YELLOW = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"

local function statLines(effects: { [string]: number }?, versus: { [string]: number }?, showDelta: boolean): string
	local out = {}
	for _, stat in ipairs(GearView.StatOrder) do
		local v = if effects then effects[stat] else nil
		local other = if versus then versus[stat] else nil
		if v or (showDelta and other) then
			local line = string.format("%s: %s", GearView.StatName[stat], if v then GearView.Format(stat, v) else "—")
			if showDelta and versus then
				local d = (v or 0) - (other or 0)
				if math.abs(d) > 0.00001 then
					line ..= string.format(' <font color="%s">(%s)</font>', if d > 0 then GREEN else RED, GearView.Format(stat, d))
				end
			end
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

local function updateCompare(slotIndex: number?)
	local stack = slotIndex and Store.Bag[slotIndex]
	local c = if stack then GearView.Compare(stack.Id, stack.Plus) else nil
	if not c then
		cmp.Visible = false
		return
	end

	local slotName = ItemCatalog.SlotDisplay[c.Slot] or c.Slot
	local v = c.Verdict
	local head
	if not c.Usable then
		head = string.format('<font color="%s">No puedes equiparlo</font>\n<font size="12" color="%s">%s</font>', RED, GRAY, c.Reason or "")
	elseif v == "Better" then
		head = string.format('<font color="%s">MEJOR que tu %s</font>  <font size="13">(%+.1f%% de poder)</font>', GREEN, slotName:lower(), c.Gain * 100)
	elseif v == "Worse" then
		head = string.format('<font color="%s">PEOR que tu %s</font>  <font size="13">(%+.1f%% de poder)</font>', RED, slotName:lower(), c.Gain * 100)
	elseif v == "Same" then
		head = string.format('<font color="%s">Igual que tu %s</font>', YELLOW, slotName:lower())
	elseif v == "Different" then
		head = string.format('<font color="%s">Distinto a tu %s</font>\n<font size="12" color="%s">Compara los valores de abajo</font>', YELLOW, slotName:lower(), GRAY)
	else
		head = string.format('<font color="%s">Ranura de %s vacía: ¡equípalo!</font>', GREEN, slotName:lower())
	end
	cmpVerdict.Text = head

	local col = ItemCatalog.RarityColor[c.Item.Rarity] or Color3.new(1, 1, 1)
	local body = string.format('<b>Seleccionado</b>  <font color="#%s">%s</font>\n%s', col:ToHex(), GearView.DisplayName(c.Item, c.Plus), statLines(c.Effects, c.EquippedEffects, c.EquippedEffects ~= nil))
	local eq = c.EquippedItem
	if eq then
		local ecol = ItemCatalog.RarityColor[eq.Rarity] or Color3.new(1, 1, 1)
		local eqText = if c.EquippedEffects then statLines(c.EquippedEffects, nil, false) else "(sin efecto para tu personaje)"
		body ..= string.format('\n\n<b>Equipado</b>  <font color="#%s">%s</font>\n%s', ecol:ToHex(), GearView.DisplayName(eq, c.EquippedPlus), eqText)
	end
	if c.Item.Set and c.Item.Set ~= "" then
		body ..= string.format('\n\n<font size="11" color="%s">Set de %s: 2 piezas +5%%, 4 piezas +15%%, 7 piezas +22%% y efecto maestro.</font>', GRAY, tostring(c.Item.Set))
	end
	if c.Item.Theme then
		local th = GearCatalog.ThemeById[c.Item.Theme]
		if th then
			body ..= string.format('\n<font size="11" color="%s">Tema %s (%s · %s): 2/4/7 piezas = +4%%/+10%%/+18%%.</font>', GRAY, th.Name, GearCatalog.WeightName[th.Weight] or "", th.Elem)
		end
	end
	cmpBody.Text = body
	cmp.Visible = true
end

local infoBox = Instance.new("Frame")
infoBox.Position = UDim2.fromOffset(0, 346)
infoBox.Size = UDim2.fromOffset(528, 42)
infoBox.BackgroundColor3 = DARK
infoBox.BorderSizePixel = 0
infoBox.ZIndex = 3
infoBox.Parent = win
Instance.new("UICorner", infoBox).CornerRadius = UDim.new(0, 6)
local infoStroke = Instance.new("UIStroke")
infoStroke.Color = pal.Edge2
infoStroke.Thickness = 1.5
infoStroke.Parent = infoBox
local info = UITheme.Text(infoBox, "Selecciona un objeto", 13, LIGHT, UDim2.fromOffset(10, 3), UDim2.fromOffset(450, 36))
info.TextWrapped = true
info.TextYAlignment = Enum.TextYAlignment.Center
info.RichText = true
info.ZIndex = 5

local deselectBtn = NpcKit.Button(infoBox, theme, "X", UDim2.fromOffset(24, 24), UDim2.fromOffset(498, 9), "danger", function()
	selected = nil
	-- render/describe se asignan abajo
	if _G.__bagRefresh then
		_G.__bagRefresh()
	end
end)
deselectBtn.Visible = false
deselectBtn.ZIndex = 6
local lockBtn = NpcKit.Button(infoBox, theme, "🔓", UDim2.fromOffset(26, 24), UDim2.fromOffset(468, 9), "neutral", function()
	if selected then
		Store.Action("Lock", selected) -- candado: no se vende ni se tira
	end
end)
lockBtn.Visible = false
lockBtn.ZIndex = 6

local equipBtn = NpcKit.Button(win, theme, "Equipar", UDim2.fromOffset(110, 30), UDim2.fromOffset(0, 556), "buy", function()
	if selected then
		Store.Action("Equip", selected)
		selected = nil
	end
end)
local dropBtn = NpcKit.Button(win, theme, "Tirar", UDim2.fromOffset(110, 30), UDim2.fromOffset(120, 556), "danger", function()
	if selected and Store.Bag[selected] and Store.Bag[selected].Locked then
		return -- bloqueado: no se tira (el servidor también lo rechaza)
	end
	if selected then
		Store.Action("Drop", selected)
		selected = nil
	end
end)

-- ORO acumulado. Cada vez que sube aparece un "+N" verde que se desvanece.
local goldBox = NpcKit.Panel(win, theme, UDim2.fromOffset(180, 30), UDim2.fromOffset(348, 556), "plate")
local goldLabel = Instance.new("TextLabel")
goldLabel.BackgroundTransparency = 1
goldLabel.Position = UDim2.fromOffset(8, 0)
goldLabel.Size = UDim2.fromOffset(164, 30)
goldLabel.Font = UITheme.Font
goldLabel.TextSize = 14
goldLabel.RichText = true
goldLabel.TextColor3 = pal.FText
goldLabel.TextXAlignment = Enum.TextXAlignment.Right
goldLabel.ZIndex = 5
goldLabel.Parent = goldBox
local goldGain = UITheme.Text(goldBox, "", 13, Color3.fromRGB(60, 190, 90), UDim2.fromOffset(8, 0), UDim2.fromOffset(70, 30), Enum.TextXAlignment.Left)
goldGain.ZIndex = 6
local lastGold = -1

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function updateGold()
	local g = player:GetAttribute("Gold")
	local gold = if typeof(g) == "number" then g else 0
	goldLabel.Text = string.format('ORO  <b>%s</b>', withCommas(gold))
	if lastGold >= 0 and gold > lastGold then
		goldGain.Text = "+" .. withCommas(gold - lastGold)
		goldGain.TextTransparency = 0
		goldGain.TextStrokeTransparency = 0.6
		TweenService:Create(goldGain, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	lastGold = gold
end
player:GetAttributeChangedSignal("Gold"):Connect(updateGold)
updateGold()

local function describe(slotIndex: number?)
	local stack = slotIndex and Store.Bag[slotIndex]
	local item = stack and ItemCatalog.Items[stack.Id]
	updateCompare(slotIndex)
	deselectBtn.Visible = stack ~= nil
	lockBtn.Visible = stack ~= nil
	lockBtn.Text = if stack and stack.Locked then "🔒" else "🔓"
	if not stack or not item then
		info.Text = "Selecciona un objeto"
		return
	end
	local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
	local statsText = ""
	if item.Stats then
		for k, v in pairs(item.Stats) do
			statsText ..= string.format("  +%s %s", tostring(v), k)
		end
	end
	info.Text = string.format('<font color="#%s">%s</font> x%d  [%s]%s\n%s', col:ToHex(), GearView.DisplayName(item, stack.Plus), stack.Count, item.Rarity, statsText, item.Desc or (if item.Slot then "Equipa en: " .. item.Slot else ""))
end

local pageTabs: { TextButton } = {}
for p = 1, #BagCatalog.PageSizes do
	local t = NpcKit.Tab(win, theme, tostring(p), UDim2.fromOffset(40, 24), UDim2.fromOffset((p - 1) * 44, 6), p == 1, nil)
	t.TextSize = 12
	pageTabs[p] = t
end
local buyBar = NpcKit.Panel(win, theme, UDim2.fromOffset(528, 304), UDim2.fromOffset(0, 36), "card")
buyBar.Visible = false
buyBar.ZIndex = 6
local buyText = UITheme.Text(buyBar, "", 16, pal.Text, UDim2.fromOffset(24, 90), UDim2.fromOffset(480, 70), Enum.TextXAlignment.Center)
buyText.TextWrapped = true
buyText.ZIndex = 7
local buyButton = NpcKit.Button(buyBar, theme, "", UDim2.fromOffset(240, 40), UDim2.fromOffset(144, 180), "buy", function()
	Store.Action("BuyPage")
end)
buyButton.ZIndex = 7

-- arrastrar y soltar
local slotButtons: { [number]: TextButton } = {}
local pressed: { Slot: number, Start: Vector2 }? = nil
local dragging: { Slot: number, Ghost: Frame }? = nil
local suppressUntil = 0

local function render()
	table.clear(slotButtons)
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local used = 0
	for _ in pairs(Store.Bag) do
		used += 1
	end
	local unlocked = BagCatalog.FreePages + Store.Pages
	local totalCap = BagCatalog.Capacity(Store.Pages)
	capLabel.Text = string.format("%d/%d", used, math.max(totalCap, Store.Capacity))
	if currentPage > #BagCatalog.PageSizes then
		currentPage = 1
	end
	-- pestañas de páginas: las bloqueadas llevan candado
	for p, tab in ipairs(pageTabs) do
		local open = p <= unlocked
		tab.Text = if open then tostring(p) else "🔒" .. tostring(p)
		tab.BackgroundColor3 = if p == currentPage then pal.TabOn else pal.TabOff
		tab.TextColor3 = if p == currentPage then pal.TabOnText else pal.TabOffText
		tab.TextTransparency = if open then 0 else 0.35
	end
	local lockedPage = currentPage > unlocked
	buyBar.Visible = lockedPage
	scroll.Visible = not lockedPage
	if lockedPage then
		local nextPaid = currentPage - BagCatalog.FreePages
		local size = BagCatalog.PageSizes[currentPage]
		local ready = nextPaid == Store.Pages + 1
		buyText.Text = string.format("Página %d · %d casillas más\n%s", currentPage, size, if ready then "Se desbloquea con Robux" else "Primero desbloquea la página anterior") .. "\nPrecio: " .. (BagCatalog.PriceText[nextPaid] or "?")
		buyButton.Visible = ready
		buyButton.Text = "Desbloquear  " .. (BagCatalog.PriceText[nextPaid] or "")
		return
	end
	local firstSlot, lastSlot = BagCatalog.PageRange(currentPage)
	for i = firstSlot, math.min(lastSlot, math.max(totalCap, Store.Capacity)) do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.AutoButtonColor = true
		b.BackgroundColor3 = pal.Slot
		b.Text = ""
		b.ZIndex = 4
		b.Parent = scroll
		slotButtons[i] = b
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke")
		st.Thickness = if selected == i then 3 else 1
		st.Color = if selected == i then pal.Accent else pal.Edge2
		st.Parent = b
		local stack = Store.Bag[i]
		local item = stack and ItemCatalog.Items[stack.Id]
		if stack and item then
			local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
			b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.7)
			st.Color = col
			ItemIcon.Build(b, item, 30, col)
			local t = UITheme.Text(b, GearView.DisplayName(item, stack.Plus), 9, col, UDim2.fromOffset(1, 35), UDim2.new(1, -2, 0, 20), Enum.TextXAlignment.Center)
			t.TextWrapped = true
			t.TextYAlignment = Enum.TextYAlignment.Top
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.ZIndex = 8
			if stack.Locked then
				UITheme.Text(b, "🔒", 12, nil, UDim2.fromScale(0.02, 0.02), UDim2.fromScale(0.5, 0.3), Enum.TextXAlignment.Left)
			end
			if stack.Count > 1 then
				UITheme.Text(b, tostring(stack.Count), 12, nil, UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.48, 0.28), Enum.TextXAlignment.Right)
			end
		end
		b.InputBegan:Connect(function(input)
			if stack and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				pressed = { Slot = i, Start = Vector2.new(input.Position.X, input.Position.Y) }
			end
		end)
		b.Activated:Connect(function()
			if os.clock() < suppressUntil then
				return -- fue un arrastre, no un clic
			end
			if selected and selected ~= i then
				Store.Action("Move", selected, i)
				selected = nil
			else
				selected = if stack and selected ~= i then i else nil -- clic otra vez en el mismo = deseleccionar
			end
			render()
			describe(selected)
		end)
	end
end

deselectBtn.Activated:Connect(function()
	selected = nil
	render()
	describe(nil)
end)

-- qué hay bajo el puntero: casilla (número) o pestaña de página (letra "P"+n)
local function hitAt(pos: Vector2): (number?, number?)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil, nil
	end
	for _, obj in ipairs(pg:GetGuiObjectsAtPosition(pos.X, pos.Y)) do
		for i, b in pairs(slotButtons) do
			if obj == b or obj:IsDescendantOf(b) then
				return i, nil
			end
		end
		for n, t in ipairs(pageTabs) do
			if obj == t then
				return nil, n
			end
		end
	end
	return nil, nil
end

local hoverTab: number? = nil
local hoverSince = 0

local function endDrag(pos: Vector2?)
	local d = dragging
	pressed = nil
	if not d then
		return
	end
	dragging = nil
	d.Ghost:Destroy()
	suppressUntil = os.clock() + 0.15
	if not pos then
		return
	end
	local slot, tab = hitAt(pos)
	if tab and tab <= BagCatalog.FreePages + Store.Pages then
		-- soltado sobre una pestaña: va a la primera casilla libre de esa página
		local first, last = BagCatalog.PageRange(tab)
		for i = first, last do
			if not Store.Bag[i] then
				Store.Action("Move", d.Slot, i)
				break
			end
		end
	elseif slot and slot ~= d.Slot then
		Store.Action("Move", d.Slot, slot)
	end
	selected = nil
	render()
	describe(nil)
end

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local pos = Vector2.new(input.Position.X, input.Position.Y)
	if pressed and not dragging and (pos - pressed.Start).Magnitude > 8 then
		local stack = Store.Bag[pressed.Slot]
		local item = stack and ItemCatalog.Items[stack.Id]
		if stack and item then
			local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
			local ghost = Instance.new("Frame")
			ghost.AnchorPoint = Vector2.new(0.5, 0.5)
			ghost.Size = UDim2.fromOffset(58, 58)
			ghost.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.5)
			ghost.BackgroundTransparency = 0.15
			ghost.ZIndex = 50
			ghost.Active = false
			ghost.Parent = ghostGui
			Instance.new("UICorner", ghost)
			local gs = Instance.new("UIStroke")
			gs.Color = col
			gs.Thickness = 2
			gs.Parent = ghost
			local gt = UITheme.Text(ghost, GearView.DisplayName(item, stack.Plus), 10, col, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.8), Enum.TextXAlignment.Center)
			gt.TextWrapped = true
			gt.ZIndex = 51
			dragging = { Slot = pressed.Slot, Ghost = ghost }
		end
	end
	if dragging then
		dragging.Ghost.Position = UDim2.fromOffset(pos.X, pos.Y)
		-- mantener sobre una pestaña medio segundo = cambiar a esa página (para soltar en una casilla concreta)
		local _, tab = hitAt(pos)
		if tab ~= hoverTab then
			hoverTab, hoverSince = tab, os.clock()
		elseif tab and tab ~= currentPage and tab <= BagCatalog.FreePages + Store.Pages and os.clock() - hoverSince > 0.5 then
			currentPage = tab
			render()
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		if dragging then
			endDrag(Vector2.new(input.Position.X, input.Position.Y))
		end
		pressed = nil
	end
end)
win.AncestryChanged:Connect(function()
	if not win:IsDescendantOf(game) then
		endDrag(nil)
	end
end)

for p, tab in ipairs(pageTabs) do
	tab.Activated:Connect(function()
		currentPage = p
		render()
	end)
end

Store.Changed:Connect(function()
	render()
	describe(selected)
end)
render()

_G.__bagRefresh = function()
	render()
	describe(selected)
end
BagDock.Register(win)

-- La mochila va unida al Perfil (tecla C, ver KeyBindCatalog "Perfil"): ya no tiene tecla propia. Otros scripts pueden abrirla con MenuBus "Inventory".
local lastToggle = 0
local function toggle()
	if os.clock() - lastToggle < 0.2 then
		return -- evita doble apertura si dos métodos detectan la misma pulsación
	end
	lastToggle = os.clock()
	MenuBus.Fire("Character")
end

MenuBus.Event:Connect(function(name: string)
	if name == "Inventory" then
		toggle()
	end
end)
print("[InventoryClient] listo (la mochila se abre con Perfil [C])")
