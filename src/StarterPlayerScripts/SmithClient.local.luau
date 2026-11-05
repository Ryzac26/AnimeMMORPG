--!strict
--[[
    SmithClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > SmithClient
    Ventana del HERRERO. Se abre al hablar con el herrero de tu ciudad (botón "Hablar").
      Izquierda: estantes con tu equipo mejorable (lo que llevas puesto primero, luego lo de la mochila).
      Derecha: YUNQUE con la pieza elegida (+N), huecos de gema y pergamino, estadísticas antes -> después, barra de probabilidad,
      avisos de caída/rotura, costo en oro y el botón "Mejorar". Estilo por facción: NpcKit.
    Todo lo decide el servidor (HerreroService); esta ventana solo muestra y pide. Se puede mover arrastrando el título.
    Se cierra sola si te alejas del herrero.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local EnhanceCatalog = require(Modules:WaitForChild("EnhanceCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local GearView = require(script.Parent:WaitForChild("GearView", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))

local CLOSE_DISTANCE = 32 -- studs: más lejos del herrero y la ventana se cierra

local openRemote = ClientNet.Get("SmithOpen")
local actionRemote = ClientNet.Get("SmithAction")
local resultRemote = ClientNet.Get("SmithResult")

local gui = Instance.new("ScreenGui")
gui.Name = "SmithGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"

type Entry = { Kind: string, Key: any, Id: string, Plus: number, Worn: boolean }
local theme = UITheme.For(player:GetAttribute("Faction"))
local win: Frame
local listScroll: ScrollingFrame
local detail: TextLabel
local resultLabel: TextLabel
local goButton: TextButton
local scrollButton: TextButton
local useScroll = false
local forgeSlot: Frame
local forgeStroke: UIStroke
local forgeName: TextLabel
local plusLabel: TextLabel
local whereLabel: TextLabel
local rateFill: Frame
local rateText: TextLabel
local rateBack: Frame
local warnLabel: TextLabel
local costLabel: TextLabel
local gemCount: TextLabel
local gemStroke: UIStroke
local scrollCount: TextLabel
local scrollStroke: UIStroke
local selected: { Kind: string, Key: any }? = nil
local smithPosition: Vector3? = nil
local smithName, smithTitle = "Herrero", ""

-- colores de texto sobre los paneles claros (pergamino Shinobi) u oscuros del resto
local function tone(name: string): string
	if NpcKit.Key(theme) == "Shinobi" then
		if name == "green" then
			return "#1f6b2e"
		elseif name == "red" then
			return "#a01818"
		elseif name == "gold" then
			return "#7a4e00"
		end
		return "#5c4a30"
	end
	if name == "green" then
		return GREEN
	elseif name == "red" then
		return RED
	elseif name == "gold" then
		return GOLD
	end
	return GRAY
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function gemsOwned(): number
	local n = 0
	for _, st in pairs(Store.Bag) do
		if st.Id == EnhanceCatalog.GemItem then
			n += st.Count
		end
	end
	return n
end

local function scrollsOwned(): number
	local n = 0
	for _, st in pairs(Store.Bag) do
		if st.Id == EnhanceCatalog.ScrollItem then
			n += st.Count
		end
	end
	return n
end

local function entries(): { Entry }
	local out: { Entry } = {}
	for _, slot in ipairs(ItemCatalog.EquipSlots) do
		local id = Store.Equip[slot]
		local item = if id then (ItemCatalog.Items :: any)[id] else nil
		if id and EnhanceCatalog.CanEnhance(item) then
			table.insert(out, { Kind = "Equip", Key = slot, Id = id, Plus = Store.EquipPlus[slot] or 0, Worn = true })
		end
	end
	local indexes = {}
	for i in pairs(Store.Bag) do
		table.insert(indexes, i)
	end
	table.sort(indexes)
	for _, i in ipairs(indexes) do
		local st = Store.Bag[i]
		local item = (ItemCatalog.Items :: any)[st.Id]
		if EnhanceCatalog.CanEnhance(item) then
			table.insert(out, { Kind = "Bag", Key = i, Id = st.Id, Plus = st.Plus, Worn = false })
		end
	end
	return out
end

local function currentEntry(): Entry?
	if not selected then
		return nil
	end
	for _, e in ipairs(entries()) do
		if e.Kind == selected.Kind and e.Key == selected.Key then
			return e
		end
	end
	return nil
end

local function refreshDetail()
	local pal = NpcKit.Palette(theme)
	local e = currentEntry()
	local gemsHave = gemsOwned()
	local scrolls = scrollsOwned()
	detail.TextColor3 = pal.Text
	warnLabel.TextColor3 = pal.Muted
	if not e then
		forgeName.Text = "Elige una pieza"
		forgeName.TextColor3 = Color3.fromRGB(170, 170, 185)
		plusLabel.Text = ""
		whereLabel.Text = "Pon una pieza sobre el yunque"
		forgeStroke.Color = theme.Secondary
		detail.Text = "Las piezas que llevas puestas y las de tu mochila aparecen en los estantes. Elige una para ver cuánto mejora y cuánto cuesta."
		warnLabel.Text = ""
		costLabel.Text = ""
		rateBack.Visible = false
		gemCount.Text = string.format("x%d", gemsHave)
		gemCount.TextColor3 = Color3.fromRGB(170, 170, 185)
		gemStroke.Color = Color3.fromRGB(90, 90, 110)
		scrollCount.Text = string.format("x%d", scrolls)
		scrollCount.TextColor3 = Color3.fromRGB(170, 170, 185)
		scrollStroke.Color = Color3.fromRGB(90, 90, 110)
		goButton.Visible = false
		scrollButton.Visible = false
		return
	end
	local item: any = (ItemCatalog.Items :: any)[e.Id]
	local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
	forgeName.Text = GearView.DisplayName(item, e.Plus)
	forgeName.TextColor3 = col
	forgeStroke.Color = col
	plusLabel.Text = if e.Plus > 0 then string.format("+%d", e.Plus) else "+0"
	plusLabel.TextColor3 = if e.Plus >= EnhanceCatalog.MaxPlus then Color3.fromRGB(255, 214, 90) else Color3.new(1, 1, 1)
	whereLabel.Text = if e.Worn then "Puesto en " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot) else "En la mochila · " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot)
	if e.Plus >= EnhanceCatalog.MaxPlus then
		detail.Text = string.format('<font color="%s">Esta pieza ya está al máximo (+%d).</font>', tone("green"), EnhanceCatalog.MaxPlus)
		warnLabel.Text = ""
		costLabel.Text = ""
		rateBack.Visible = false
		gemCount.Text = string.format("x%d", gemsHave)
		gemCount.TextColor3 = Color3.fromRGB(170, 170, 185)
		gemStroke.Color = Color3.fromRGB(90, 90, 110)
		scrollCount.Text = string.format("x%d", scrolls)
		scrollCount.TextColor3 = Color3.fromRGB(170, 170, 185)
		scrollStroke.Color = Color3.fromRGB(90, 90, 110)
		goButton.Visible = false
		scrollButton.Visible = false
		return
	end
	local target = e.Plus + 1
	local lines = { string.format('<font color="%s">+%d  →  +%d</font>', tone("gold"), e.Plus, target) }
	local now = GearView.Effects(item, e.Plus) or {}
	local after = GearView.Effects(item, target) or {}
	for _, stat in ipairs(GearView.StatOrder) do
		if now[stat] then
			table.insert(lines, string.format('%s: %s  <font color="%s">→ %s</font>', GearView.StatName[stat], GearView.Format(stat, now[stat]), tone("green"), GearView.Format(stat, after[stat] or 0)))
		end
	end
	detail.Text = table.concat(lines, "\n")

	-- probabilidad: barra de color + avisos de caída / rotura
	local rate = EnhanceCatalog.SuccessRate[target] or 0
	local pct = math.floor(rate * 100 + 0.5)
	local drop = EnhanceCatalog.FailDrop[target] or 0
	rateBack.Visible = true
	rateFill.Size = UDim2.fromScale(math.clamp(rate, 0.02, 1), 1)
	rateFill.BackgroundColor3 = if rate >= 0.9 then Color3.fromRGB(80, 200, 100) elseif rate >= 0.4 then Color3.fromRGB(230, 200, 60) elseif rate >= 0.15 then Color3.fromRGB(235, 140, 50) else Color3.fromRGB(220, 60, 60)
	rateText.Text = string.format("Éxito %d%%", pct)
	local notes: { string } = {}
	if rate < 1 then
		local brk = EnhanceCatalog.BreakChance[target] or 0
		local failText = if drop > 0 then string.format("Si falla, baja a +%d", math.max(0, e.Plus - drop)) else "Si falla, no pierdes el nivel"
		if brk > 0 then
			table.insert(notes, string.format('%s, o <font color="%s">SE ROMPE (%d%% de los fallos)</font>', failText, tone("red"), math.floor(brk * 100 + 0.5)))
		else
			table.insert(notes, failText .. " (el objeto no se rompe)")
		end
	end
	scrollButton.Visible = drop > 0
	goButton.Size = if drop > 0 then UDim2.fromOffset(286, 40) else UDim2.fromOffset(416, 40)
	if drop > 0 then
		if scrolls < 1 then
			useScroll = false
		end
		scrollButton.Text = if useScroll then "🛡 Pergamino: SÍ" else string.format("🛡 Pergamino (%d)", scrolls)
		scrollButton.BackgroundColor3 = if useScroll then Color3.fromRGB(150, 90, 190) elseif scrolls > 0 then Color3.fromRGB(70, 70, 100) else Color3.fromRGB(60, 55, 60)
		table.insert(notes, "Pergamino: si falla, la pieza NO baja ni se rompe. Solo se gasta si falla.")
	end
	warnLabel.Text = table.concat(notes, "\n")

	-- coste: oro (en la barra de abajo) y gemas (en su casilla)
	local goldCost = EnhanceCatalog.GoldCost(item, target)
	local gems = EnhanceCatalog.Gems[target]
	local goldNow = player:GetAttribute("Gold")
	local haveGold = if typeof(goldNow) == "number" then goldNow else 0
	costLabel.Text = string.format('Oro: <font color="%s">%s</font> / %s', if haveGold >= goldCost then GREEN else RED, withCommas(haveGold), withCommas(goldCost))
	gemCount.Text = string.format("%d / %d", gemsHave, gems)
	gemCount.TextColor3 = if gemsHave >= gems then Color3.fromRGB(111, 220, 127) else Color3.fromRGB(255, 107, 107)
	gemStroke.Color = if gemsHave >= gems then Color3.fromRGB(111, 220, 127) else Color3.fromRGB(255, 107, 107)
	scrollCount.Text = if drop > 0 then (if useScroll then "ACTIVO" else string.format("x%d", scrolls)) else "—"
	scrollCount.TextColor3 = if useScroll and drop > 0 then Color3.fromRGB(200, 150, 255) else Color3.fromRGB(170, 170, 185)
	scrollStroke.Color = if useScroll and drop > 0 then Color3.fromRGB(200, 150, 255) else Color3.fromRGB(90, 90, 110)
	goButton.Visible = true
	goButton.Text = if rate >= 1 then "Mejorar" else "Intentar mejora"
end

local function refreshList()
	for _, c in ipairs(listScroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local list = entries()
	if #list == 0 then
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(1, -6, 0, 70)
		t.TextWrapped = true
		t.Font = Enum.Font.Gotham
		t.TextSize = 13
		t.TextColor3 = NpcKit.Palette(theme).Muted
		t.Text = "EQUIPADOS (0)\nEN LA MOCHILA (0)\n\nNo tienes equipo para mejorar. Consigue armas, armaduras o joyas y vuelve."
		t.Parent = listScroll
		return
	end
	local order = 0
	local function header(text: string, count: number)
		order += 1
		local h = Instance.new("TextLabel")
		h.LayoutOrder = order
		h.Size = UDim2.new(1, -6, 0, 22)
		h.BackgroundTransparency = 1
		h.Font = UITheme.Font
		h.TextSize = 13
		h.TextColor3 = if NpcKit.Key(theme) == "Shinobi" then NpcKit.Palette(theme).Edge else theme.Primary
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Text = string.format("%s (%d)", text, count)
		h.Parent = listScroll
		if count == 0 then
			order += 1
			local none = Instance.new("TextLabel")
			none.LayoutOrder = order
			none.Size = UDim2.new(1, -6, 0, 20)
			none.BackgroundTransparency = 1
			none.Font = Enum.Font.Gotham
			none.TextSize = 11
			none.TextColor3 = NpcKit.Palette(theme).Muted
			none.TextXAlignment = Enum.TextXAlignment.Left
			none.Text = "  (nada mejorable aquí)"
			none.Parent = listScroll
		end
	end
	local worn, bagged = 0, 0
	for _, e in ipairs(list) do
		if e.Worn then
			worn += 1
		else
			bagged += 1
		end
	end
	local lastGroup: boolean? = nil
	if worn == 0 then
		header("EQUIPADOS", 0)
	end
	for _, e in ipairs(list) do
		if lastGroup ~= e.Worn then
			if e.Worn then
				header("EQUIPADOS", worn)
			else
				header("EN LA MOCHILA", bagged)
			end
			lastGroup = e.Worn
		end
		local item: any = (ItemCatalog.Items :: any)[e.Id]
		local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
		order += 1
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.Size = UDim2.new(1, -6, 0, 38)
		b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.75)
		b.AutoButtonColor = true
		b.Text = ""
		b.Parent = listScroll
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke")
		local isSel = selected ~= nil and selected.Kind == e.Kind and selected.Key == e.Key
		st.Color = if isSel then theme.Primary else col
		st.Thickness = if isSel then 3 else 1
		st.Parent = b
		local ic = ItemIcon.Build(b, item, 30, col)
		ic.AnchorPoint = Vector2.zero
		ic.Position = UDim2.fromOffset(4, 4)
		local name = UITheme.Text(b, GearView.DisplayName(item, e.Plus), 12, col, UDim2.fromOffset(42, 2), UDim2.new(1, -50, 0, 18))
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local sub = if e.Worn then "Puesto · " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot) else "Mochila · " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot)
		UITheme.Text(b, sub, 10, NpcKit.Palette(theme).Muted, UDim2.fromOffset(42, 20), UDim2.new(1, -50, 0, 14))
		b.Activated:Connect(function()
			selected = { Kind = e.Kind, Key = e.Key }
			resultLabel.Text = ""
			refreshList()
			refreshDetail()
		end)
	end
	if bagged == 0 and worn > 0 then
		header("EN LA MOCHILA", 0)
	end
end

local function refreshAll()
	if not gui.Enabled then
		return
	end
	-- si lo seleccionado ya no existe (lo vendiste, lo moviste...), se deselecciona
	if selected and not currentEntry() then
		selected = nil
	end
	refreshList()
	refreshDetail()
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	local W = 700
	win = NpcKit.Window(gui, theme, UDim2.fromOffset(W, 520), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), smithName, (if smithTitle ~= "" then smithTitle .. "  ·  " else "") .. "Fragua de mejoras  ·  arrastra el rótulo para mover", "⚒", function()
		gui.Enabled = false
	end)
	WindowDrag.Attach(win, "Smith", 60, 50)


	-- ESTANTES (izquierda): tu equipo mejorable
	local shelves = NpcKit.Panel(win, theme, UDim2.fromOffset(240, 430), UDim2.fromOffset(16, 70), "inset")
	listScroll = Instance.new("ScrollingFrame")
	listScroll.Position = UDim2.fromOffset(4, 4)
	listScroll.Size = UDim2.fromOffset(232, 422)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 5
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.fromOffset(0, 0)
	listScroll.ZIndex = 3
	listScroll.Parent = shelves
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 6), UDim.new(0, 4)
	pad.Parent = listScroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listScroll

	-- YUNQUE (derecha, arriba): pieza elegida al centro, gemas a la izquierda, pergamino a la derecha
	local stage = NpcKit.Panel(win, theme, UDim2.fromOffset(416, 180), UDim2.fromOffset(268, 70), "plate")
	local function slotBox(x: number, caption: string, icon: string): (TextLabel, UIStroke)
		UITheme.Text(stage, caption, 10, NpcKit.Palette(theme).Muted, UDim2.fromOffset(x, 8), UDim2.fromOffset(84, 12), Enum.TextXAlignment.Center)
		local sb = Instance.new("Frame")
		sb.Position = UDim2.fromOffset(x, 24)
		sb.Size = UDim2.fromOffset(84, 84)
		sb.BackgroundColor3 = Color3.fromRGB(18, 16, 24)
		sb.BorderSizePixel = 0
		sb.Parent = stage
		Instance.new("UICorner", sb).CornerRadius = UDim.new(0, if NpcKit.Key(theme) == "Saiyan" then 3 else 10)
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = Color3.fromRGB(90, 90, 110)
		st.Parent = sb
		UITheme.Text(sb, icon, 30, Color3.new(1, 1, 1), UDim2.fromOffset(0, 8), UDim2.fromOffset(84, 38), Enum.TextXAlignment.Center)
		local cnt = UITheme.Text(sb, "", 14, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(0, 56), UDim2.fromOffset(84, 20), Enum.TextXAlignment.Center)
		return cnt, st
	end
	gemCount, gemStroke = slotBox(14, "GEMAS", "💎")
	scrollCount, scrollStroke = slotBox(318, "PERGAMINO", "🛡")

	forgeSlot = Instance.new("Frame")
	forgeSlot.Position = UDim2.fromOffset(108, 10)
	forgeSlot.Size = UDim2.fromOffset(200, 98)
	forgeSlot.BackgroundColor3 = Color3.fromRGB(20, 18, 26)
	forgeSlot.BorderSizePixel = 0
	forgeSlot.Parent = stage
	Instance.new("UICorner", forgeSlot).CornerRadius = UDim.new(0, if NpcKit.Key(theme) == "Saiyan" then 3 else 8)
	forgeStroke = Instance.new("UIStroke")
	forgeStroke.Thickness = 2
	forgeStroke.Color = theme.Secondary
	forgeStroke.Parent = forgeSlot
	forgeName = UITheme.Text(forgeSlot, "Elige una pieza", 13, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(8, 4), UDim2.fromOffset(184, 34), Enum.TextXAlignment.Center)
	forgeName.TextWrapped = true
	forgeName.TextTruncate = Enum.TextTruncate.AtEnd
	plusLabel = UITheme.Text(forgeSlot, "", 38, Color3.new(1, 1, 1), UDim2.fromOffset(0, 40), UDim2.fromOffset(200, 52), Enum.TextXAlignment.Center)
	plusLabel.TextStrokeTransparency = 0.2
	-- el yunque (hierro): cara, cintura y base
	local function iron(x: number, y: number, w: number, h: number, c1: Color3, c2: Color3)
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundColor3 = c1
		f.BorderSizePixel = 0
		f.Parent = stage
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 3)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(c1, c2)
		g.Rotation = 90
		g.Parent = f
	end
	iron(78, 114, 260, 12, Color3.fromRGB(150, 150, 168), Color3.fromRGB(70, 70, 84)) -- cara
	iron(58, 114, 28, 8, Color3.fromRGB(130, 130, 148), Color3.fromRGB(70, 70, 84)) -- cuerno
	iron(140, 126, 136, 12, Color3.fromRGB(86, 86, 100), Color3.fromRGB(52, 52, 64)) -- cintura
	iron(112, 138, 192, 12, Color3.fromRGB(70, 70, 84), Color3.fromRGB(40, 40, 50)) -- base
	whereLabel = UITheme.Text(stage, "", 12, NpcKit.Palette(theme).Muted, UDim2.fromOffset(0, 156), UDim2.fromOffset(416, 16), Enum.TextXAlignment.Center)

	-- DATOS: estadísticas antes -> después, barra de éxito y avisos
	local info = NpcKit.Panel(win, theme, UDim2.fromOffset(416, 144), UDim2.fromOffset(268, 254), "inset")
	detail = UITheme.Text(info, "", 13, nil, UDim2.fromOffset(12, 6), UDim2.fromOffset(392, 80))
	detail.TextWrapped = true
	detail.RichText = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	rateBack = Instance.new("Frame")
	rateBack.Position = UDim2.fromOffset(12, 90)
	rateBack.Size = UDim2.fromOffset(392, 16)
	rateBack.BackgroundColor3 = Color3.fromRGB(14, 12, 18)
	rateBack.BorderSizePixel = 0
	rateBack.Visible = false
	rateBack.Parent = info
	Instance.new("UICorner", rateBack).CornerRadius = UDim.new(0, 6)
	rateFill = Instance.new("Frame")
	rateFill.Size = UDim2.fromScale(0, 1)
	rateFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	rateFill.BorderSizePixel = 0
	rateFill.Parent = rateBack
	Instance.new("UICorner", rateFill).CornerRadius = UDim.new(0, 6)
	rateText = UITheme.Text(rateBack, "", 11, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
	rateText.ZIndex = 3
	warnLabel = UITheme.Text(info, "", 11, nil, UDim2.fromOffset(12, 110), UDim2.fromOffset(392, 32))
	warnLabel.TextWrapped = true
	warnLabel.RichText = true
	warnLabel.TextYAlignment = Enum.TextYAlignment.Top

	costLabel = UITheme.Text(win, "", 14, nil, UDim2.fromOffset(268, 402), UDim2.fromOffset(416, 18), Enum.TextXAlignment.Center)
	costLabel.RichText = true
	resultLabel = UITheme.Text(win, "", 14, nil, UDim2.fromOffset(268, 422), UDim2.fromOffset(416, 34))
	resultLabel.TextWrapped = true
	resultLabel.RichText = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center

	goButton = NpcKit.Button(win, theme, "Mejorar", UDim2.fromOffset(416, 40), UDim2.fromOffset(268, 460), "action", nil)
	goButton.TextSize = 16
	goButton.Visible = false
	goButton.Activated:Connect(function()
		local e = currentEntry()
		if e and actionRemote then
			actionRemote:FireServer("Enhance", e.Kind, e.Key, useScroll)
		end
	end)
	scrollButton = NpcKit.Button(win, theme, "", UDim2.fromOffset(124, 40), UDim2.fromOffset(560, 460), "neutral", nil)
	scrollButton.TextSize = 12
	local sg = scrollButton:FindFirstChildOfClass("UIGradient")
	if sg then
		sg:Destroy() -- el color del botón lo cambia refreshDetail
	end
	scrollButton.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
	scrollButton.Visible = false
	scrollButton.Activated:Connect(function()
		if scrollsOwned() < 1 then
			resultLabel.Text = string.format('<font color="%s">No tienes Pergaminos de Protección (Tienda > Objetos).</font>', RED)
			return
		end
		useScroll = not useScroll
		refreshDetail()
	end)
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(name: any, title: any, _faction: any)
		smithName = if typeof(name) == "string" then name else "Herrero"
		smithTitle = if typeof(title) == "string" then title else ""
		local ok, err = pcall(function()
			build()
			selected = nil
			gui.Enabled = true
			-- el herrero está cerca: se guarda su posición para cerrar la ventana si te alejas
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			smithPosition = if root then root.Position else nil
			refreshAll()
		end)
		if not ok then
			warn("[SmithClient] No se pudo abrir la ventana del herrero: " .. tostring(err))
		end
	end)
else
	warn("[SmithClient] No existe el remote SmithOpen: actualiza Services/Net y HerreroService en el servidor.")
end

if resultRemote then
	resultRemote.OnClientEvent:Connect(function(ok: any, text: any, _plus: any)
		if not gui.Enabled or not resultLabel then
			return
		end
		resultLabel.Text = string.format('<font color="%s"><b>%s</b></font>', if ok == true then GREEN else RED, tostring(text))
	end)
end

Store.Changed:Connect(refreshAll)
player:GetAttributeChangedSignal("Gold"):Connect(refreshAll)

-- cerrar al alejarse del lugar donde hablaste con el herrero
task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled and smithPosition then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - smithPosition).Magnitude > CLOSE_DISTANCE then
				gui.Enabled = false
			end
		end
	end
end)

print("[SmithClient] listo")
