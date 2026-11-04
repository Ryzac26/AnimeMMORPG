--!strict
--[[
    AlquimiaClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AlquimiaClient
    Ventana del ALQUIMISTA (botón "Hablar"). Tres pestañas:
      POCIONES : recetas de Vida/Energía en 3 grados. Eliges la cantidad: x1 / x10 / x50 / x100 / Máx (todo lo que alcance).
      ELIXIRES : efecto temporal de 30 min (oro, suerte, daño, vida, regeneración). Fabricas y bebes aquí; también se beben en la mochila (Equipar).
      DESMONTAR: equipo de tu mochila (sin candado) -> materiales de su franja + fragmentos. "Desmontar todo el equipo Común" de una vez.
                 Lo Épico o mejor (o mejorado) pide confirmar con un segundo clic.
    Todo lo valida el servidor (AlquimistaService). Se mueve arrastrando el título y se cierra sola si te alejas.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local ShopCatalog = require(Modules:WaitForChild("ShopCatalog", 10))
local AlchemyCatalog = require(Modules:WaitForChild("AlchemyCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local GearView = require(script.Parent:WaitForChild("GearView", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local RarityPicker = require(script.Parent:WaitForChild("RarityPicker", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))

local CLOSE_DISTANCE = 32
local openRemote = ClientNet.Get("AlquimiaOpen")
local actionRemote = ClientNet.Get("AlquimiaAction")
local resultRemote = ClientNet.Get("AlquimiaResult")

local gui = Instance.new("ScreenGui")
gui.Name = "AlquimiaGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"

local theme = UITheme.For(player:GetAttribute("Faction"))
local pal = NpcKit.Palette(theme)
local win: Frame
local ingBox: Frame -- caldero: casillas de ingredientes de la receta elegida
local canLine: TextLabel
local prepLabel: TextLabel
local tabsHolder: Frame
local listScroll: ScrollingFrame
local detail: TextLabel
local resultLabel: TextLabel
local actionBox: Frame
local commonsButton: TextButton
local picker: any = nil
local confirmBulk = false
local goldLabel: TextLabel
local tabCraft: TextButton
local tabDismantle: TextButton
local tabElixir: TextButton
local mode = "Craft" -- "Craft" | "Elixir" | "Dismantle"
local selectedRecipe: string? = nil
local selectedSlot: number? = nil
local confirmSlot: number? = nil
local npcName, npcTitle = "Alquimista", ""
local openPosition: Vector3? = nil

-- colores de texto legibles según el material de la facción (el pergamino Shinobi es claro)
local function applyPalette()
	pal = NpcKit.Palette(theme)
	if NpcKit.Key(theme) == "Shinobi" then
		GREEN, RED, GRAY, GOLD = "#1f6e2c", "#9a1c1c", "#6a5638", "#8a5a00"
	else
		GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"
	end
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function myGold(): number
	local g = player:GetAttribute("Gold")
	return if typeof(g) == "number" then g else 0
end

local function owned(id: string): number
	local n = 0
	for _, st in pairs(Store.Bag) do
		if st.Id == id then
			n += st.Count
		end
	end
	return n
end

local function itemName(id: string): string
	local it: any = (ItemCatalog.Items :: any)[id]
	return if it then it.Name else id
end

local function hasBelt(): boolean
	return player:GetAttribute("Pass_Belt") == true
end

local function maxCraft(r: AlchemyCatalog.Recipe): number
	if not AlchemyCatalog.CanCraft(r, hasBelt()) then
		return 0
	end
	return AlchemyCatalog.MaxCraft(r, owned, myGold())
end

-- equipo de la mochila que se puede desmontar (sin candado, no mascotas)
local function gearList(): { { Slot: number, Id: string, Count: number, Plus: number } }
	local out = {}
	local idx = {}
	for i in pairs(Store.Bag) do
		table.insert(idx, i)
	end
	table.sort(idx)
	for _, i in ipairs(idx) do
		local st = Store.Bag[i]
		local item = (ItemCatalog.Items :: any)[st.Id]
		if item and not item.Pet and (item.Gear or item.Slot) and not st.Locked then
			table.insert(out, { Slot = i, Id = st.Id, Count = st.Count, Plus = st.Plus or 0 })
		end
	end
	return out
end

local function yieldText(item: any, plus: number): string
	local req = if typeof(item.ReqLevel) == "number" then item.ReqLevel else 1
	local matId, mMin, mMax, frag, gem = AlchemyCatalog.DismantleYield(req, item.Rarity, plus)
	local parts = { string.format("%d-%d %s", mMin, mMax, itemName(matId)) }
	if frag > 0 then
		table.insert(parts, string.format("%d %s", frag, itemName("Mat_FragArmadura")))
	end
	if gem > 0 then
		table.insert(parts, string.format("%d%% de %s", math.floor(gem * 100 + 0.5), itemName("Mat_Gema")))
	end
	return table.concat(parts, "\n")
end

local function refreshDetail()
	for _, c in ipairs(actionBox:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local function button(text: string, x: number, w: number, kind: string, fn: () -> (), y: number?)
		NpcKit.Button(actionBox, theme, text, UDim2.fromOffset(w, 38), UDim2.fromOffset(x, y or 0), kind, fn)
	end
	ingBox.Visible = false
	prepLabel.Visible = false
	canLine.Text = ""
	detail.Size = UDim2.fromOffset(318, 190)
	for _, c in ipairs(ingBox:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	commonsButton.Visible = mode == "Dismantle"
	actionBox.Position = if mode ~= "Dismantle" then UDim2.fromOffset(14, 262) else UDim2.fromOffset(14, 164)
	if picker then
		picker.Holder.Visible = mode == "Dismantle"
	end
	if mode == "Dismantle" and picker then
		local pieces = 0
		for _, st in pairs(Store.Bag) do
			local item: any = (ItemCatalog.Items :: any)[st.Id]
			if item and not item.Pet and (item.Gear or item.Slot) and not st.Locked and picker:Matches(item, st.Plus or 0) then
				pieces += st.Count
			end
		end
		local asking = confirmBulk and picker:Dangerous()
		commonsButton.Text = if pieces == 0 then "Nada que desmontar con esa selección" elseif asking then string.format("¿Seguro? Desmontar %d piezas", pieces) else string.format("Desmontar %d piezas", pieces)
		commonsButton.BackgroundColor3 = if pieces == 0 then Color3.fromRGB(70, 60, 60) elseif asking then Color3.fromRGB(190, 70, 50) else Color3.fromRGB(140, 100, 40)
	end
	if mode ~= "Dismantle" then
		local r = if selectedRecipe then AlchemyCatalog.ById[selectedRecipe] else nil
		if r and (r.Kind == "Elixir") ~= (mode == "Elixir") then
			r = nil
		end
		if not r and mode == "Elixir" then
			local aid = player:GetAttribute("ElixirId")
			local aleft = player:GetAttribute("ElixirLeft")
			local cur = if typeof(aid) == "string" and typeof(aleft) == "number" and AlchemyCatalog.Elixirs[aid] then string.format('<font color="%s">Activo: %s (%d:%02d)</font>', GREEN, AlchemyCatalog.Elixirs[aid].Name, aleft // 60, aleft % 60) else "Ningún elixir activo."
			detail.Text = cur .. "\n\nElige un elixir a la izquierda.\n\n<font size=\"12\" color=\"" .. GRAY .. "\">Duran 30 min (solo corre conectado) y solo uno activo a la vez: beber otro reemplaza al actual. No dan experiencia.</font>"
			return
		end
		if not r then
			detail.Text = "Elige una poción a la izquierda.\n\n<font size=\"12\" color=\"" .. GRAY .. "\">Los recursos (Hierba, Cristal, Reliquia...) se recolectan en los nodos del mapa; los materiales salen de los monstruos.</font>"
			return
		end
		local item: any = (ItemCatalog.Items :: any)[r.Id]
		detail.Size = UDim2.fromOffset(318, 74)
		local lines = { string.format('<b>%s</b>\n<font size="12" color="%s">%s</font>', item.Name, GRAY, if r.Kind == "Elixir" then AlchemyCatalog.Elixirs[r.Id].Short .. " · 30 min" else (item.Desc or "")) }
		local mats: { string } = {}
		for id in pairs(r.Cost) do
			table.insert(mats, id)
		end
		table.sort(mats)
		-- caldero: una casilla por ingrediente (tienes / necesitas) + el oro
		ingBox.Visible = true
		local nSlots = #mats + 1
		local sw = math.min(60, math.floor((306 - (nSlots - 1) * 4) / nSlots))
		local function socket(index: number, top: string, mid: string, midColor: Color3, bottom: string)
			local f = Instance.new("Frame")
			f.Position = UDim2.fromOffset(6 + (index - 1) * (sw + 4), 18)
			f.Size = UDim2.fromOffset(sw, 62)
			f.BackgroundColor3 = Color3.fromRGB(20, 16, 14)
			f.BorderSizePixel = 0
			f.ZIndex = 5
			f.Parent = ingBox
			Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
			local st = Instance.new("UIStroke")
			st.Color = midColor
			st.Thickness = 1.5
			st.Transparency = 0.25
			st.Parent = f
			local t = UITheme.Text(f, top, 9, Color3.fromRGB(215, 205, 190), UDim2.fromOffset(1, 2), UDim2.new(1, -2, 0, 22), Enum.TextXAlignment.Center)
			t.TextWrapped = true
			t.ZIndex = 6
			local m = UITheme.Text(f, mid, 15, midColor, UDim2.fromOffset(0, 24), UDim2.new(1, 0, 0, 18), Enum.TextXAlignment.Center)
			m.ZIndex = 6
			local b = UITheme.Text(f, bottom, 9, Color3.fromRGB(170, 160, 150), UDim2.fromOffset(0, 45), UDim2.new(1, 0, 0, 14), Enum.TextXAlignment.Center)
			b.ZIndex = 6
		end
		local OKC, BADC = Color3.fromRGB(111, 220, 127), Color3.fromRGB(255, 107, 107)
		for k2, id in ipairs(mats) do
			local need, have = r.Cost[id], owned(id)
			socket(k2, itemName(id), tostring(need), if have >= need then OKC else BADC, string.format("tienes %d", have))
		end
		socket(nSlots, "Oro 💰", withCommas(r.Gold), if myGold() >= r.Gold then Color3.fromRGB(255, 212, 94) else BADC, "tienes " .. withCommas(myGold()))
		local locked = not AlchemyCatalog.CanCraft(r, hasBelt())
		local most = maxCraft(r)
		canLine.Text = if locked then string.format('<font color="%s">🔒 Requiere el pase Cinturón de Pociones (Tienda > Pases)</font>', RED) else string.format('Ahora puedes fabricar: <font color="%s"><b>%d</b></font>', if most > 0 then GREEN else RED, most)
		prepLabel.Visible = true
		prepLabel.Text = if r.Kind == "Elixir" then "FABRICAR / BEBER" else "PREPARAR"
		detail.Text = table.concat(lines, "\n")
		local opts: { number } = {}
		for _, n in ipairs(AlchemyCatalog.QTY_OPTIONS) do
			table.insert(opts, n)
		end
		for k, n in ipairs(opts) do
			button("x" .. n, (k - 1) * 65, 58, if most >= n then "buy" else "neutral", function()
				actionRemote:FireServer("Craft", r.Id, n)
			end)
		end
		button("Máx", #opts * 65, 58, if most > 0 then "action" else "neutral", function()
			actionRemote:FireServer("Craft", r.Id, "max")
		end)
		if r.Kind == "Elixir" then
			local have = owned(r.Id)
			local aid = player:GetAttribute("ElixirId")
			local aleft = player:GetAttribute("ElixirLeft")
			local cur = if typeof(aid) == "string" and typeof(aleft) == "number" and AlchemyCatalog.Elixirs[aid] then string.format('<font color="%s">Activo: %s (%d:%02d)</font>', GREEN, AlchemyCatalog.Elixirs[aid].Name, aleft // 60, aleft % 60) else "Ningún elixir activo."
			canLine.Text = string.format('%s  <font color="%s">(tienes %d)</font>\nPuedes fabricar: <font color="%s"><b>%d</b></font>', cur, GRAY, have, if most > 0 then GREEN else RED, most)
			button(if have > 0 then "Beber (30 min)" else "No tienes este elixir", 0, 318, if have > 0 then "action" else "neutral", function()
				actionRemote:FireServer("Drink", r.Id)
			end, 46)
		end
	else
		local row
		for _, g in ipairs(gearList()) do
			if g.Slot == selectedSlot then
				row = g
			end
		end
		if not row then
			selectedSlot = nil
			detail.Text = "Elige a la izquierda la pieza que quieres desmontar.\n\n<font size=\"12\" color=\"" .. GRAY .. "\">Lo que tiene candado 🔒 y lo que llevas puesto no se desmonta. Las piezas se destruyen.</font>"
			return
		end
		local item: any = (ItemCatalog.Items :: any)[row.Id]
		detail.Text = string.format('<b>%s</b>\n\nAl desmontarla recibes:\n<font color="%s">%s</font>', GearView.DisplayName(item, row.Plus), GREEN, yieldText(item, row.Plus))
		local needs = ShopCatalog.NeedsConfirm(item, row.Plus)
		local asking = needs and confirmSlot == row.Slot
		button(if asking then "¿Seguro? Desmontar" else "Desmontar", 0, 318, if asking then "danger" else "buy", function()
			if needs and confirmSlot ~= row.Slot then
				confirmSlot = row.Slot
				refreshDetail()
				return
			end
			confirmSlot = nil
			actionRemote:FireServer("Dismantle", row.Slot)
		end)
	end
end

local function refreshList()
	for _, c in ipairs(listScroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local order = 0
	local function entry(id: string, plus: number, subText: string, selected: boolean, onClick: () -> ())
		local item: any = (ItemCatalog.Items :: any)[id]
		local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
		order += 1
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.Size = UDim2.new(1, -6, 0, 38)
		b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.75)
		b.Text = ""
		b.Parent = listScroll
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke")
		st.Color = if selected then theme.Primary else col
		st.Thickness = if selected then 3 else 1
		st.Parent = b
		local name = UITheme.Text(b, GearView.DisplayName(item, plus), 12, col, UDim2.fromOffset(8, 2), UDim2.new(1, -16, 0, 18))
		name.TextTruncate = Enum.TextTruncate.AtEnd
		UITheme.Text(b, subText, 10, Color3.fromRGB(160, 160, 175), UDim2.fromOffset(8, 20), UDim2.new(1, -16, 0, 14))
		b.Activated:Connect(onClick)
	end
	if mode ~= "Dismantle" then
		for _, r in ipairs(AlchemyCatalog.Recipes) do
			if (r.Kind == "Elixir") ~= (mode == "Elixir") then
				continue
			end
			local most = maxCraft(r)
			entry(r.Id, 0, if not AlchemyCatalog.CanCraft(r, hasBelt()) then "🔒 Requiere Cinturón de Pociones" elseif most > 0 then string.format("Puedes fabricar %d", most) else "Faltan materiales", selectedRecipe == r.Id, function()
				selectedRecipe = r.Id
				resultLabel.Text = ""
				refreshList()
				refreshDetail()
			end)
		end
	else
		local list = gearList()
		if #list == 0 then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, -6, 0, 60)
			t.TextWrapped = true
			t.Font = Enum.Font.Gotham
			t.TextSize = 13
			t.TextColor3 = Color3.fromRGB(170, 170, 185)
			t.Text = "No tienes equipo para desmontar."
			t.Parent = listScroll
		end
		for _, g in ipairs(list) do
			entry(g.Id, g.Plus, if g.Count > 1 then "x" .. g.Count else "Equipo", selectedSlot == g.Slot, function()
				selectedSlot = g.Slot
				confirmSlot = nil
				resultLabel.Text = ""
				refreshList()
				refreshDetail()
			end)
		end
	end
end

local refreshAll: () -> ()

local function buildTabs()
	for _, c in ipairs(tabsHolder:GetChildren()) do
		c:Destroy()
	end
	local function tab(text: string, x: number, m: string): TextButton
		return NpcKit.Tab(tabsHolder, theme, text, UDim2.fromOffset(124, 28), UDim2.fromOffset(x, 0), mode == m, function()
			mode = m
			selectedRecipe = nil
			confirmSlot = nil
			resultLabel.Text = ""
			refreshAll()
		end)
	end
	tabCraft = tab("🧪 Pociones", 0, "Craft")
	tabElixir = tab("✨ Elixires", 130, "Elixir")
	tabDismantle = tab("🔨 Desmontar", 260, "Dismantle")
end

refreshAll = function()
	if not gui.Enabled or not win then
		return
	end
	goldLabel.Text = string.format('Oro: <font color="%s">%s</font>', GOLD, withCommas(myGold()))
	buildTabs()
	refreshList()
	refreshDetail()
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	applyPalette()
	if win then
		win:Destroy()
	end
	win = UITheme.Frame(gui, theme, UDim2.fromOffset(640, 486), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	WindowDrag.Attach(win, "Alquimia", 52, 50)
	NpcKit.Header(win, theme, 640, npcName, if npcTitle ~= "" then npcTitle .. "  ·  mesa de alquimia" else "Mesa de alquimia", "⚗")
	goldLabel = UITheme.Text(win, "", 15, Color3.new(1, 1, 1), UDim2.fromOffset(420, 24), UDim2.fromOffset(170, 22))
	goldLabel.RichText = true
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel.ZIndex = 30
	goldLabel.TextColor3 = if NpcKit.Key(theme) == "Shinobi" then Color3.fromRGB(255, 232, 170) else Color3.new(1, 1, 1)

	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.ZIndex = 30
	close.Parent = win
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	tabsHolder = Instance.new("Frame")
	tabsHolder.BackgroundTransparency = 1
	tabsHolder.Position = UDim2.fromOffset(16, 68)
	tabsHolder.Size = UDim2.fromOffset(400, 28)
	tabsHolder.ZIndex = 30
	tabsHolder.Parent = win

	-- libro de recetas (izquierda)
	NpcKit.Panel(win, theme, UDim2.fromOffset(250, 372), UDim2.fromOffset(16, 104), "inset")
	listScroll = Instance.new("ScrollingFrame")
	listScroll.Position = UDim2.fromOffset(16, 104)
	listScroll.Size = UDim2.fromOffset(250, 372)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 5
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.fromOffset(0, 0)
	listScroll.ZIndex = 3
	listScroll.Parent = win
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = listScroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listScroll

	-- mesa / caldero (derecha)
	local box = NpcKit.Panel(win, theme, UDim2.fromOffset(346, 372), UDim2.fromOffset(278, 104), "card")
	local textColor = pal.Text

	detail = UITheme.Text(box, "", 14, textColor, UDim2.fromOffset(14, 8), UDim2.fromOffset(318, 190))
	detail.TextWrapped = true
	detail.RichText = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextStrokeTransparency = 1
	detail.ZIndex = 4

	-- caldero con las casillas de ingredientes
	ingBox = NpcKit.Panel(box, theme, UDim2.fromOffset(318, 86), UDim2.fromOffset(14, 84), "inset")
	ingBox.Visible = false
	ingBox.ZIndex = 4
	local ingTitle = UITheme.Text(ingBox, "⚗ CALDERO · INGREDIENTES", 10, pal.Muted, UDim2.fromOffset(8, 2), UDim2.fromOffset(300, 14))
	ingTitle.TextStrokeTransparency = 1
	ingTitle.ZIndex = 6

	canLine = UITheme.Text(box, "", 12, textColor, UDim2.fromOffset(14, 174), UDim2.fromOffset(318, 34))
	canLine.TextWrapped = true
	canLine.RichText = true
	canLine.TextYAlignment = Enum.TextYAlignment.Top
	canLine.TextStrokeTransparency = 1
	canLine.ZIndex = 4

	resultLabel = UITheme.Text(box, "", 13, textColor, UDim2.fromOffset(14, 210), UDim2.fromOffset(318, 34))
	resultLabel.TextWrapped = true
	resultLabel.RichText = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	resultLabel.TextStrokeTransparency = 1
	resultLabel.ZIndex = 4

	prepLabel = UITheme.Text(box, "PREPARAR", 10, pal.Muted, UDim2.fromOffset(14, 246), UDim2.fromOffset(318, 14))
	prepLabel.TextStrokeTransparency = 1
	prepLabel.Visible = false
	prepLabel.ZIndex = 4

	actionBox = Instance.new("Frame")
	actionBox.BackgroundTransparency = 1
	actionBox.Position = UDim2.fromOffset(14, 262)
	actionBox.Size = UDim2.fromOffset(318, 38)
	actionBox.ZIndex = 4
	actionBox.Parent = box

	commonsButton = Instance.new("TextButton")
	commonsButton.Position = UDim2.fromOffset(14, 318)
	commonsButton.Size = UDim2.fromOffset(318, 30)
	commonsButton.BackgroundColor3 = Color3.fromRGB(140, 100, 40)
	commonsButton.TextColor3 = Color3.new(1, 1, 1)
	commonsButton.Font = UITheme.Font
	commonsButton.TextSize = 14
	commonsButton.Text = "Desmontar"
	commonsButton.Visible = false
	commonsButton.ZIndex = 10
	commonsButton.Parent = box
	Instance.new("UICorner", commonsButton)
	picker = RarityPicker.new(box, UDim2.fromOffset(14, 248), function()
		confirmBulk = false
		refreshDetail()
	end)
	commonsButton.Activated:Connect(function()
		if picker:Dangerous() and not confirmBulk then
			confirmBulk = true
			refreshDetail()
			return
		end
		confirmBulk = false
		actionRemote:FireServer("DismantleRarity", picker:List(), picker:IncludePlus())
	end)
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(name: any, title: any, _faction: any)
		npcName = if typeof(name) == "string" then name else "Alquimista"
		npcTitle = if typeof(title) == "string" then title else ""
		local ok, err = pcall(function()
			build()
			mode, selectedRecipe, selectedSlot, confirmSlot = "Craft", nil, nil, nil
			gui.Enabled = true
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			openPosition = if root then root.Position else nil
			refreshAll()
		end)
		if not ok then
			warn("[AlquimiaClient] No se pudo abrir la ventana del alquimista: " .. tostring(err))
		end
	end)
else
	warn("[AlquimiaClient] No existe el remote AlquimiaOpen: actualiza Services/Net y AlquimistaService en el servidor.")
end

if resultRemote then
	resultRemote.OnClientEvent:Connect(function(ok: any, text: any)
		if not gui.Enabled or not resultLabel then
			return
		end
		resultLabel.Text = string.format('<font color="%s"><b>%s</b></font>', if ok == true then GREEN else RED, tostring(text))
	end)
end

Store.Changed:Connect(refreshAll)
player:GetAttributeChangedSignal("Gold"):Connect(refreshAll)
player:GetAttributeChangedSignal("Pass_Belt"):Connect(refreshAll)
player:GetAttributeChangedSignal("ElixirLeft"):Connect(function()
	if gui.Enabled and mode == "Elixir" and win then
		refreshDetail()
	end
end)

task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled and openPosition then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - openPosition).Magnitude > CLOSE_DISTANCE then
				gui.Enabled = false
			end
		end
	end
end)

print("[AlquimiaClient] listo")
