--!strict
--[[
    InventoryClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > InventoryClient
    MOCHILA (tecla B). Cuadrícula de 5 columnas que CRECE sola: cuando llenas todas las casillas aparece otra fila.
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
local BagCatalog = require(ReplicatedStorage.Modules.BagCatalog)
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local theme = UITheme.For(player:GetAttribute("Faction"))
local selected: number? = nil
local currentPage = 1

local win = UITheme.Frame(gui, theme, UDim2.fromOffset(380, 500), UDim2.new(1, -20, 0.5, 0), Vector2.new(1, 0.5))
UITheme.Text(win, "MOCHILA", 20, theme.Primary, UDim2.fromOffset(16, 8), UDim2.fromOffset(200, 28))
local capLabel = UITheme.Text(win, "", 12, Color3.fromRGB(200, 200, 210), UDim2.fromOffset(268, 12), UDim2.fromOffset(72, 20), Enum.TextXAlignment.Right)
local bestBtn = Instance.new("TextButton")
bestBtn.Position = UDim2.fromOffset(112, 9)
bestBtn.Size = UDim2.fromOffset(84, 24)
bestBtn.BackgroundColor3 = Color3.fromRGB(60, 100, 160)
bestBtn.TextColor3 = Color3.new(1, 1, 1)
bestBtn.Font = UITheme.Font
bestBtn.TextSize = 12
bestBtn.Text = "★ Mejor set"
bestBtn.ZIndex = 30 -- por encima de la barra de arrastre (ZIndex 20), si no se traga los clics
bestBtn.Parent = win
Instance.new("UICorner", bestBtn)
local sortBtn = Instance.new("TextButton")
sortBtn.Position = UDim2.fromOffset(200, 9)
sortBtn.Size = UDim2.fromOffset(64, 24)
sortBtn.BackgroundColor3 = Color3.fromRGB(90, 80, 130)
sortBtn.TextColor3 = Color3.new(1, 1, 1)
sortBtn.Font = UITheme.Font
sortBtn.TextSize = 12
sortBtn.Text = "Ordenar"
sortBtn.ZIndex = 30 -- por encima de la barra de arrastre (ZIndex 20), si no se traga los clics
sortBtn.Parent = win
Instance.new("UICorner", sortBtn)
sortBtn.Activated:Connect(function()
	selected = nil
	Store.Action("Sort") -- junta lo apilable y ordena por rareza
end)
bestBtn.Activated:Connect(function()
	Store.Action("EquipBest")
end)
local close = UITheme.Text(win, "X", 18, Color3.fromRGB(255, 120, 120), UDim2.new(1, -34, 0, 8), UDim2.fromOffset(24, 24), Enum.TextXAlignment.Center)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromScale(1, 1)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = ""
closeBtn.Parent = close
closeBtn.Activated:Connect(function()
	gui.Enabled = false
end)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(14, 76)
scroll.Size = UDim2.fromOffset(352, 308)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.Parent = win
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.fromOffset(62, 62)
grid.CellPadding = UDim2.fromOffset(8, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = scroll

WindowDrag.Attach(win, "Inventory", 40, 50) -- arrastra el título para mover la mochila
UITheme.Text(win, "arrastra el título para mover", 10, Color3.fromRGB(130, 130, 145), UDim2.fromOffset(16, 487), UDim2.fromOffset(348, 12))

-- Panel de COMPARACIÓN (a un costado de la mochila): objeto seleccionado vs lo que llevas puesto
local cmp = Instance.new("Frame")
cmp.Name = "Compare"
cmp.Size = UDim2.fromOffset(276, 10)
cmp.AutomaticSize = Enum.AutomaticSize.Y
cmp.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
cmp.BorderSizePixel = 0
cmp.Visible = false
cmp.Parent = win
Instance.new("UICorner", cmp)
UITheme.Border(cmp, theme, 2)
local cmpPad = Instance.new("UIPadding")
cmpPad.PaddingTop, cmpPad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
cmpPad.PaddingLeft, cmpPad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
cmpPad.Parent = cmp
local cmpList = Instance.new("UIListLayout")
cmpList.Padding = UDim.new(0, 6)
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
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextWrapped = true
	t.RichText = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = ""
	t.Parent = cmp
	return t
end
local cmpVerdict = cmpLabel(1, 16)
local cmpBody = cmpLabel(2, 13)

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
	-- el panel va a la izquierda de la mochila; si no cabe, a la derecha
	cmp.Position = if win.AbsolutePosition.X > 300 then UDim2.new(0, -284, 0, 0) else UDim2.new(1, 8, 0, 0)

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
		body ..= string.format('\n\n<font size="11" color="%s">Set de %s: con 2 piezas +5%%, con 4 piezas +15%%.</font>', GRAY, tostring(c.Item.Set))
	end
	cmpBody.Text = body
	cmp.Visible = true
end

local info = UITheme.Text(win, "Selecciona un objeto", 14, nil, UDim2.fromOffset(16, 392), UDim2.fromOffset(348, 56))
info.TextWrapped = true
info.TextYAlignment = Enum.TextYAlignment.Top
info.RichText = true

local deselectBtn = Instance.new("TextButton")
deselectBtn.Position = UDim2.fromOffset(342, 390)
deselectBtn.Size = UDim2.fromOffset(24, 24)
deselectBtn.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
deselectBtn.TextColor3 = Color3.fromRGB(255, 140, 140)
deselectBtn.Font = UITheme.Font
deselectBtn.TextSize = 14
deselectBtn.Text = "X"
deselectBtn.Visible = false
deselectBtn.Parent = win
Instance.new("UICorner", deselectBtn)

local lockBtn = Instance.new("TextButton")
lockBtn.Position = UDim2.fromOffset(312, 390)
lockBtn.Size = UDim2.fromOffset(26, 24)
lockBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
lockBtn.TextColor3 = Color3.new(1, 1, 1)
lockBtn.Font = UITheme.Font
lockBtn.TextSize = 13
lockBtn.Text = "🔓"
lockBtn.Visible = false
lockBtn.Parent = win
Instance.new("UICorner", lockBtn)
lockBtn.Activated:Connect(function()
	if selected then
		Store.Action("Lock", selected) -- candado: no se vende ni se tira
	end
end)

local function button(text: string, x: number, color: Color3, fn: () -> ())
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, 456)
	b.Size = UDim2.fromOffset(110, 30)
	b.BackgroundColor3 = color
	b.Text = text
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = UITheme.Font
	b.TextSize = 14
	b.Parent = win
	Instance.new("UICorner", b)
	b.Activated:Connect(fn)
end
button("Equipar", 16, Color3.fromRGB(50, 130, 70), function()
	if selected then
		Store.Action("Equip", selected)
		selected = nil
	end
end)
local lockBtn: TextButton
button("Tirar", 138, Color3.fromRGB(150, 50, 50), function()
	if selected and Store.Bag[selected] and Store.Bag[selected].Locked then
		return -- bloqueado: no se tira (el servidor también lo rechaza)
	end
	if selected then
		Store.Action("Drop", selected)
		selected = nil
	end
end)

-- ORO acumulado (a la derecha de los botones). Cada vez que sube aparece un "+N" verde que se desvanece.
local goldLabel = Instance.new("TextLabel")
goldLabel.BackgroundTransparency = 1
goldLabel.Position = UDim2.fromOffset(256, 454)
goldLabel.Size = UDim2.fromOffset(110, 32)
goldLabel.Font = UITheme.Font
goldLabel.TextSize = 15
goldLabel.RichText = true
goldLabel.TextColor3 = Color3.fromRGB(255, 214, 90)
goldLabel.TextXAlignment = Enum.TextXAlignment.Right
goldLabel.TextYAlignment = Enum.TextYAlignment.Center
goldLabel.Parent = win
local goldGain = UITheme.Text(win, "", 13, Color3.fromRGB(111, 220, 127), UDim2.fromOffset(258, 455), UDim2.fromOffset(70, 14), Enum.TextXAlignment.Left)
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
	goldLabel.Text = string.format('<font size="10" color="#aaaab8">ORO</font>\n%s', withCommas(gold))
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
	local t = Instance.new("TextButton")
	t.Position = UDim2.fromOffset(14 + (p - 1) * 71, 46)
	t.Size = UDim2.fromOffset(66, 24)
	t.Font = UITheme.Font
	t.TextSize = 13
	t.Text = tostring(p)
	t.Parent = win
	Instance.new("UICorner", t)
	pageTabs[p] = t
end
local buyBar = Instance.new("Frame")
buyBar.Position = UDim2.fromOffset(14, 76)
buyBar.Size = UDim2.fromOffset(352, 308)
buyBar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
buyBar.BorderSizePixel = 0
buyBar.Visible = false
buyBar.Parent = win
Instance.new("UICorner", buyBar)
local buyText = UITheme.Text(buyBar, "", 16, Color3.new(1, 1, 1), UDim2.fromOffset(16, 90), UDim2.fromOffset(320, 60), Enum.TextXAlignment.Center)
buyText.TextWrapped = true
local buyButton = Instance.new("TextButton")
buyButton.Position = UDim2.fromOffset(76, 170)
buyButton.Size = UDim2.fromOffset(200, 40)
buyButton.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
buyButton.TextColor3 = Color3.new(1, 1, 1)
buyButton.Font = UITheme.Font
buyButton.TextSize = 16
buyButton.Parent = buyBar
Instance.new("UICorner", buyButton)
buyButton.Activated:Connect(function()
	Store.Action("BuyPage")
end)

-- arrastrar y soltar
local slotButtons: { [number]: TextButton } = {}
local pressed: { Slot: number, Start: Vector2 }? = nil
local dragging: { Slot: number, Ghost: Frame }? = nil
local suppressUntil = 0

local function render()
	table.clear(slotButtons)
	theme = UITheme.For(player:GetAttribute("Faction"))
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
		tab.BackgroundColor3 = if p == currentPage then theme.Primary else (if open then Color3.fromRGB(40, 40, 54) else Color3.fromRGB(60, 40, 40))
		tab.TextColor3 = if p == currentPage then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
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
		b.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
		b.Text = ""
		b.Parent = scroll
		slotButtons[i] = b
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke")
		st.Thickness = if selected == i then 3 else 1
		st.Color = if selected == i then theme.Primary else Color3.fromRGB(70, 70, 85)
		st.Parent = b
		local stack = Store.Bag[i]
		local item = stack and ItemCatalog.Items[stack.Id]
		if stack and item then
			local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
			b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.7)
			st.Color = col
			local t = UITheme.Text(b, GearView.DisplayName(item, stack.Plus), 11, col, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.8), Enum.TextXAlignment.Center)
			t.TextWrapped = true
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
			ghost.Parent = gui
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
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not gui.Enabled then
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

local lastToggle = 0
local function toggle()
	if os.clock() - lastToggle < 0.2 then
		return -- evita doble apertura si dos métodos detectan la misma pulsación
	end
	lastToggle = os.clock()
	gui.Enabled = not gui.Enabled
end

-- Tecla B. Prioridad ALTA para que ningún otro script o UI se la quede.
ContextActionService:BindActionAtPriority("ToggleInventory", function(_, state)
	if state == Enum.UserInputState.Begin then
		toggle()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value + 100, Enum.KeyCode.B)

-- Respaldo: también por UserInputService (ignora "gameProcessed")
UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.B then
		toggle()
	end
end)

-- Botón "Mochila" de la barra de menú
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
MenuBus.Event:Connect(function(name: string)
	if name == "Inventory" then
		toggle()
	end
end)
print("[InventoryClient] listo (tecla B o botón Mochila)")
