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
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "InventoryGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local theme = UITheme.For(player:GetAttribute("Faction"))
local selected: number? = nil

local win = UITheme.Frame(gui, theme, UDim2.fromOffset(380, 500), UDim2.new(1, -20, 0.5, 0), Vector2.new(1, 0.5))
UITheme.Text(win, "MOCHILA", 20, theme.Primary, UDim2.fromOffset(16, 8), UDim2.fromOffset(200, 28))
local capLabel = UITheme.Text(win, "", 13, Color3.fromRGB(200, 200, 210), UDim2.fromOffset(180, 12), UDim2.fromOffset(184, 20), Enum.TextXAlignment.Right)
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
scroll.Position = UDim2.fromOffset(14, 44)
scroll.Size = UDim2.fromOffset(352, 340)
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
button("Tirar", 138, Color3.fromRGB(150, 50, 50), function()
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

local function render()
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
	capLabel.Text = string.format("%d / %d casillas", used, Store.Capacity)
	for i = 1, Store.Capacity do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.AutoButtonColor = true
		b.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
		b.Text = ""
		b.Parent = scroll
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
			if stack.Count > 1 then
				UITheme.Text(b, tostring(stack.Count), 12, nil, UDim2.fromScale(0.5, 0.7), UDim2.fromScale(0.48, 0.28), Enum.TextXAlignment.Right)
			end
		end
		b.Activated:Connect(function()
			if selected and selected ~= i then
				Store.Action("Move", selected, i)
				selected = nil
			else
				selected = if stack then i else nil
			end
			render()
			describe(selected)
		end)
	end
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
