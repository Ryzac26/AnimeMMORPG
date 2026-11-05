--!strict
--[[
    ShopClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ShopClient
    Ventana del MERCADER (botón "Comerciar"). Dos pestañas:
      COMPRAR: pociones (precio según tu nivel) con cantidad 1 / 5 / 10.
      VENDER:  lo que está en tu mochila con su precio; "Vender" la casilla elegida o "Vender equipo Común" de una vez.
               Lo Épico o mejor (o mejorado) pide confirmar con un segundo clic.
    Todo lo valida el servidor (MercaderService). Se mueve arrastrando el título y se cierra sola si te alejas.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local ShopCatalog = require(Modules:WaitForChild("ShopCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local GearView = require(script.Parent:WaitForChild("GearView", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local RarityPicker = require(script.Parent:WaitForChild("RarityPicker", 10))

local CLOSE_DISTANCE = 32
local openRemote = ClientNet.Get("ShopOpen")
local actionRemote = ClientNet.Get("ShopAction")
local resultRemote = ClientNet.Get("ShopResult")

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"
local TEXT = Color3.new(1, 1, 1) -- color de texto principal según el material del panel (oscuro sobre pergamino)
local shelfInner: Frame? = nil -- estantes que se desplazan con la lista
local SHELF_PITCH = 84 -- alto de una fila de casillas + su estante

local theme = UITheme.For(player:GetAttribute("Faction"))
local win: Frame
local listScroll: ScrollingFrame
local detail: TextLabel
local resultLabel: TextLabel
local actionBox: Frame
local commonsButton: TextButton
local picker: any = nil
local confirmBulk = false
local goldLabel: TextLabel
local tabBuy: TextButton
local tabSell: TextButton
local mode = "Buy" -- "Buy" | "Sell"
local selectedId: string? = nil -- compra: itemId
local selectedSlot: number? = nil -- venta: casilla
local confirmSlot: number? = nil
local npcName, npcTitle = "Mercader", ""
local openPosition: Vector3? = nil

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
local function myLevel(): number
	local l = player:GetAttribute("Level")
	return if typeof(l) == "number" then l else 1
end

local function sellList(): { { Slot: number, Id: string, Count: number, Plus: number, Unit: number } }
	local out = {}
	local idx = {}
	for i in pairs(Store.Bag) do
		table.insert(idx, i)
	end
	table.sort(idx)
	for _, i in ipairs(idx) do
		local st = Store.Bag[i]
		local item = (ItemCatalog.Items :: any)[st.Id]
		local unit = ShopCatalog.SellPrice(st.Id, item, st.Plus)
		if unit and not st.Locked then
			table.insert(out, { Slot = i, Id = st.Id, Count = st.Count, Plus = st.Plus or 0, Unit = unit })
		end
	end
	return out
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

local function sendBuy(n: number)
	if selectedId and actionRemote then
		actionRemote:FireServer("Buy", selectedId, n)
	end
end

local function refreshDetail()
	for _, c in ipairs(actionBox:GetChildren()) do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local function button(text: string, x: number, w: number, color: Color3, fn: () -> ())
		local kind = if color == Color3.fromRGB(50, 130, 70) then "buy" elseif color == Color3.fromRGB(190, 70, 50) then "danger" elseif color == Color3.fromRGB(60, 100, 150) then "action" else "neutral"
		local b = NpcKit.Button(actionBox, theme, text, UDim2.fromOffset(w, 38), UDim2.fromOffset(x, 0), if mode == "Sell" and kind == "buy" then "sell" else kind, fn)
		b.TextSize = 13
	end
	commonsButton.Visible = mode == "Sell"
	if picker then
		picker.Holder.Visible = mode == "Sell"
	end
	if mode == "Sell" and picker then
		local pieces, total = 0, 0
		for _, st in pairs(Store.Bag) do
			local item: any = (ItemCatalog.Items :: any)[st.Id]
			if item and not item.Pet and (item.Gear or item.Slot) and not st.Locked and picker:Matches(item, st.Plus or 0) then
				local unit = ShopCatalog.SellPrice(st.Id, item, st.Plus or 0)
				if unit then
					pieces += st.Count
					total += unit * st.Count
				end
			end
		end
		local asking = confirmBulk and picker:Dangerous()
		commonsButton.Text = if pieces == 0 then "Nada que vender con esa selección" elseif asking then string.format("¿Seguro? Vender %d piezas (%s)", pieces, withCommas(total)) else string.format("Vender %d piezas · %s de oro", pieces, withCommas(total))
		commonsButton.BackgroundColor3 = if pieces == 0 then Color3.fromRGB(70, 60, 60) elseif asking then Color3.fromRGB(190, 70, 50) else Color3.fromRGB(140, 100, 40)
	end
	if mode == "Buy" then
		local item: any = if selectedId then (ItemCatalog.Items :: any)[selectedId] else nil
		if not item or not selectedId then
			detail.Text = "Elige un objeto a la izquierda."
			return
		end
		local price = ShopCatalog.BuyPrice(myLevel())
		detail.Text = string.format('<b>%s</b>\n<font size="12" color="%s">%s</font>\n\nPrecio: <font color="%s">%s</font> de oro c/u\nTienes: <font color="%s">%s</font> de oro · en mochila: %d', item.Name, GRAY, item.Desc or "", GOLD, withCommas(price), GOLD, withCommas(myGold()), owned(selectedId))
		for k, n in ipairs({ 1, 5, 10 }) do
			local cost = price * n
			button(string.format("x%d  (%s)", n, withCommas(cost)), (k - 1) * 108, 102, if myGold() >= cost then Color3.fromRGB(50, 130, 70) else Color3.fromRGB(90, 60, 60), function()
				sendBuy(n)
			end)
		end
	else
		local row
		for _, r in ipairs(sellList()) do
			if r.Slot == selectedSlot then
				row = r
			end
		end
		if not row then
			selectedSlot = nil
			detail.Text = "Elige a la izquierda lo que quieres vender.\n\n<font size=\"12\" color=\"" .. GRAY .. "\">Gemas de Mejora, mascotas y lo que llevas puesto no se venden.</font>"
			return
		end
		local item: any = (ItemCatalog.Items :: any)[row.Id]
		detail.Text = string.format('<b>%s</b>  x%d\n\nTe paga: <font color="%s">%s</font> de oro c/u\nTodas las unidades: <font color="%s">%s</font>', GearView.DisplayName(item, row.Plus), row.Count, GOLD, withCommas(row.Unit), GOLD, withCommas(row.Unit * row.Count))
		local needs = ShopCatalog.NeedsConfirm(item, row.Plus)
		local label = if needs and confirmSlot == row.Slot then "¿Seguro? Vender" elseif row.Count > 1 then "Vender todo" else "Vender"
		button(label, 0, if row.Count > 1 then 150 else 318, if needs and confirmSlot == row.Slot then Color3.fromRGB(190, 70, 50) else Color3.fromRGB(50, 130, 70), function()
			if needs and confirmSlot ~= row.Slot then
				confirmSlot = row.Slot
				refreshDetail()
				return
			end
			confirmSlot = nil
			actionRemote:FireServer("Sell", row.Slot, row.Count)
		end)
		if row.Count > 1 then
			button("Vender 1", 160, 158, Color3.fromRGB(60, 100, 150), function()
				if needs and confirmSlot ~= row.Slot then
					confirmSlot = row.Slot
					refreshDetail()
					return
				end
				confirmSlot = nil
				actionRemote:FireServer("Sell", row.Slot, 1)
			end)
		end
	end
end

local function refreshList()
	for _, c in ipairs(listScroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local order = 0
	local COLS = 3
	local function entry(id: string, plus: number, subText: string, selected: boolean, onClick: () -> ())
		local item: any = (ItemCatalog.Items :: any)[id]
		local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
		order += 1
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.ZIndex = 3
		b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.75)
		b.Text = ""
		b.AutoButtonColor = true
		b.BorderSizePixel = 0
		b.Parent = listScroll
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		local st = Instance.new("UIStroke")
		st.Color = if selected then theme.Primary else col
		st.Thickness = if selected then 3 else 1
		st.Parent = b
		local ic = ItemIcon.Build(b, item, 28, col)
		ic.AnchorPoint = Vector2.zero
		ic.Position = UDim2.fromOffset(4, 4)
		local name = UITheme.Text(b, GearView.DisplayName(item, plus), 10, col, UDim2.fromOffset(36, 3), UDim2.new(1, -40, 0, 40))
		name.TextWrapped = true
		name.TextYAlignment = Enum.TextYAlignment.Top
		name.ZIndex = 4
		local sub = UITheme.Text(b, subText, 10, Color3.fromRGB(235, 220, 160), UDim2.new(0, 5, 1, -18), UDim2.new(1, -10, 0, 14))
		sub.ZIndex = 4
		sub.TextTruncate = Enum.TextTruncate.AtEnd
		b.Activated:Connect(onClick)
	end
	if mode == "Buy" then
		local price = ShopCatalog.BuyPrice(myLevel())
		for _, id in ipairs(ShopCatalog.Stock) do
			entry(id, 0, withCommas(price) .. " de oro", selectedId == id, function()
				selectedId = id
				resultLabel.Text = ""
				refreshList()
				refreshDetail()
			end)
		end
	else
		local list = sellList()
		if #list == 0 then
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, -6, 0, 60)
			t.TextWrapped = true
			t.Font = Enum.Font.Gotham
			t.TextSize = 11
			t.TextColor3 = TEXT
			t.Text = "No tienes nada que el mercader compre."
			t.Parent = listScroll
		end
		for _, r in ipairs(list) do
			entry(r.Id, r.Plus, string.format("x%d · %s c/u", r.Count, withCommas(r.Unit)), selectedSlot == r.Slot, function()
				selectedSlot = r.Slot
				confirmSlot = nil
				resultLabel.Text = ""
				refreshList()
				refreshDetail()
			end)
		end
	end
	-- estantes: una tabla bajo cada fila de casillas (van detrás de la lista y se mueven con ella)
	if shelfInner then
		shelfInner:ClearAllChildren()
		local rows = math.max(1, math.ceil(order / COLS))
		for r = 0, rows - 1 do
			NpcKit.Shelf(shelfInner, theme, UDim2.fromOffset(4, 6 + r * SHELF_PITCH + 68), 326)
		end
		shelfInner.Size = UDim2.fromOffset(340, rows * SHELF_PITCH + 12)
	end
end

local function refreshAll()
	if not gui.Enabled or not win then
		return
	end
	goldLabel.Text = string.format('Oro: <font color="%s">%s</font>', GOLD, withCommas(myGold()))
	-- pestañas: se recrean para marcar la activa
	for _, t in ipairs({ tabBuy, tabSell }) do
		if t then
			t:Destroy()
		end
	end
	local function tab(text: string, x: number, m: string): TextButton
		return NpcKit.Tab(win, theme, text, UDim2.fromOffset(122, 28), UDim2.fromOffset(x, 68), mode == m, function()
			mode = m
			confirmSlot = nil
			resultLabel.Text = ""
			refreshAll()
		end)
	end
	tabBuy = tab("Comprar", 16, "Buy")
	tabSell = tab("Vender", 144, "Sell")
	refreshList()
	refreshDetail()
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	local W = 730
	win = NpcKit.Window(gui, theme, UDim2.fromOffset(W, 500), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), npcName, if npcTitle ~= "" then npcTitle else "Mercader", "🛒", function()
		gui.Enabled = false
	end)
	WindowDrag.Attach(win, "Shop", 66, 50)
	local pal = NpcKit.Palette(theme)
	local shinobi = NpcKit.Key(theme) == "Shinobi"
	TEXT = if shinobi then pal.Text else Color3.new(1, 1, 1)
	if shinobi then -- sobre pergamino los colores claros no se leen
		GREEN, RED, GRAY, GOLD = "#2f7a3a", "#a82020", "#6a5434", "#8a4b00"
	else
		GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"
	end
	goldLabel = UITheme.Text(win, "", 15, Color3.fromRGB(255, 226, 140), UDim2.fromOffset(W - 260, 20), UDim2.fromOffset(190, 22))
	goldLabel.RichText = true
	goldLabel.TextXAlignment = Enum.TextXAlignment.Right
	goldLabel.ZIndex = 8
	if shinobi then
		goldLabel.TextColor3 = Color3.fromRGB(40, 28, 14)
	end


	-- (las pestañas Comprar/Vender las crea refreshAll para marcar la activa)

	-- estantería (panel hundido con las casillas encima de los estantes)
	local shelfPanel = NpcKit.Panel(win, theme, UDim2.fromOffset(340, 394), UDim2.fromOffset(16, 102), "inset")
	local clip = Instance.new("Frame")
	clip.BackgroundTransparency = 1
	clip.Size = UDim2.fromScale(1, 1)
	clip.ClipsDescendants = true
	clip.ZIndex = 1
	clip.Parent = shelfPanel
	local si = Instance.new("Frame")
	si.BackgroundTransparency = 1
	si.Size = UDim2.fromOffset(340, 400)
	si.Parent = clip
	shelfInner = si

	listScroll = Instance.new("ScrollingFrame")
	listScroll.Size = UDim2.fromScale(1, 1)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 5
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.fromOffset(0, 0)
	listScroll.ZIndex = 2
	listScroll.Parent = shelfPanel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = listScroll
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(100, 72)
	grid.CellPadding = UDim2.fromOffset(6, SHELF_PITCH - 72)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = listScroll
	listScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		si.Position = UDim2.fromOffset(0, -listScroll.CanvasPosition.Y)
	end)

	-- panel de detalle (cartel del mostrador)
	local box = NpcKit.Panel(win, theme, UDim2.fromOffset(346, 394), UDim2.fromOffset(368, 102), "card")

	detail = UITheme.Text(box, "", 14, TEXT, UDim2.fromOffset(14, 10), UDim2.fromOffset(318, 120))
	detail.TextWrapped = true
	detail.RichText = true
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextStrokeTransparency = 1
	detail.ZIndex = 5

	resultLabel = UITheme.Text(box, "", 13, TEXT, UDim2.fromOffset(14, 132), UDim2.fromOffset(318, 40))
	resultLabel.TextWrapped = true
	resultLabel.RichText = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	resultLabel.TextStrokeTransparency = 1
	resultLabel.ZIndex = 5

	actionBox = Instance.new("Frame")
	actionBox.BackgroundTransparency = 1
	actionBox.Position = UDim2.fromOffset(14, 178)
	actionBox.Size = UDim2.fromOffset(318, 38)
	actionBox.ZIndex = 5
	actionBox.Parent = box

	commonsButton = NpcKit.Button(box, theme, "Vender", UDim2.fromOffset(318, 30), UDim2.fromOffset(14, 352), "sell", nil)
	commonsButton.Visible = false
	picker = RarityPicker.new(box, UDim2.fromOffset(14, 262), function()
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
		actionRemote:FireServer("SellRarity", picker:List(), picker:IncludePlus())
	end)
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(name: any, title: any, _faction: any, portable: any)
		npcName = if typeof(name) == "string" then name else "Mercader"
		npcTitle = if typeof(title) == "string" then title else ""
		local ok, err = pcall(function()
			build()
			mode, selectedId, selectedSlot, confirmSlot = "Buy", nil, nil, nil
			gui.Enabled = true
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			openPosition = if root and portable ~= true then root.Position else nil -- el Mercader Portátil no se cierra al alejarte
			refreshAll()
		end)
		if not ok then
			warn("[ShopClient] No se pudo abrir la ventana del mercader: " .. tostring(err))
		end
	end)
else
	warn("[ShopClient] No existe el remote ShopOpen: actualiza Services/Net y MercaderService en el servidor.")
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

print("[ShopClient] listo")

---------------------------------------------------------------------
-- MERCADER PORTÁTIL (pase): botón 🛒 y tecla V abren el mercader desde cualquier lugar
---------------------------------------------------------------------
do
	local UserInputService = game:GetService("UserInputService")
	local portableGui = Instance.new("ScreenGui")
	portableGui.Name = "MercaderPortatilGui"
	portableGui.ResetOnSpawn = false
	portableGui.DisplayOrder = 8
	portableGui.Parent = player:WaitForChild("PlayerGui", 10)
	local pb = Instance.new("TextButton")
	pb.AnchorPoint = Vector2.new(0, 0.5)
	pb.Position = UDim2.new(0, 10, 0.62, 0)
	pb.Size = UDim2.fromOffset(112, 34)
	pb.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
	pb.TextColor3 = Color3.new(1, 1, 1)
	pb.Font = UITheme.Font
	pb.TextSize = 13
	pb.Text = "🛒 Mercader [V]"
	pb.Parent = portableGui
	Instance.new("UICorner", pb)
	local function sync()
		pb.Visible = player:GetAttribute("Pass_Merchant") == true
	end
	sync()
	player:GetAttributeChangedSignal("Pass_Merchant"):Connect(sync)
	local function openPortable()
		if gui.Enabled then
			gui.Enabled = false -- el mismo botón/tecla cierra la ventana
			return
		end
		if player:GetAttribute("Pass_Merchant") == true then
			actionRemote:FireServer("OpenPortable")
		end
	end
	pb.Activated:Connect(openPortable)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.V then
			openPortable()
		end
	end)
end
