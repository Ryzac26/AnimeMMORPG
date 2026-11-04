--!strict
--[[
    SmithClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > SmithClient
    Ventana del HERRERO. Se abre al hablar con el herrero de tu ciudad (botón "Hablar").
      Izquierda: tu equipo mejorable (lo que llevas puesto primero, luego lo de la mochila).
      Derecha: estadísticas ahora -> después de la mejora, probabilidad, costo en oro y gemas, y el botón "Mejorar".
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
local titleLabel: TextLabel
local subtitleLabel: TextLabel
local selected: { Kind: string, Key: any }? = nil
local smithPosition: Vector3? = nil
local smithName, smithTitle = "Herrero", ""

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
	local e = currentEntry()
	if not e then
		forgeName.Text = "Elige una pieza a la izquierda"
		forgeName.TextColor3 = Color3.fromRGB(170, 170, 185)
		forgeStroke.Color = theme.Secondary
		detail.Text = "Las piezas que llevas puestas y las de tu mochila aparecen en la lista. Elige una para ver cuánto mejora y cuánto cuesta."
		goButton.Visible = false
		scrollButton.Visible = false
		return
	end
	local item: any = (ItemCatalog.Items :: any)[e.Id]
	local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
	forgeName.Text = GearView.DisplayName(item, e.Plus)
	forgeName.TextColor3 = col
	forgeStroke.Color = col
	local lines = { string.format('<font size="12" color="%s">%s</font>', GRAY, if e.Worn then "Puesto en " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot) else "En la mochila") }
	if e.Plus >= EnhanceCatalog.MaxPlus then
		table.insert(lines, string.format('<font color="%s">Esta pieza ya está al máximo (+%d).</font>', GREEN, EnhanceCatalog.MaxPlus))
		detail.Text = table.concat(lines, "\n")
		goButton.Visible = false
		scrollButton.Visible = false
		return
	end
	local target = e.Plus + 1
	table.insert(lines, string.format('<font color="%s">+%d  →  +%d</font>', GOLD, e.Plus, target))
	table.insert(lines, "")
	local now = GearView.Effects(item, e.Plus) or {}
	local after = GearView.Effects(item, target) or {}
	for _, stat in ipairs(GearView.StatOrder) do
		if now[stat] then
			table.insert(lines, string.format('%s: %s  <font color="%s">→ %s</font>', GearView.StatName[stat], GearView.Format(stat, now[stat]), GREEN, GearView.Format(stat, after[stat] or 0)))
		end
	end
	table.insert(lines, "")
	local rate = EnhanceCatalog.SuccessRate[target] or 0
	table.insert(lines, string.format("Probabilidad de éxito: <b>%d%%</b>", math.floor(rate * 100 + 0.5)))
	local drop = EnhanceCatalog.FailDrop[target] or 0
	if rate < 1 then
		local brk = EnhanceCatalog.BreakChance[target] or 0
		local failText = if drop > 0 then string.format("si falla, baja a +%d", math.max(0, e.Plus - drop)) else "si falla, no pierdes el nivel"
		if brk > 0 then
			table.insert(lines, string.format('<font size="12" color="%s">%s, o <font color="%s">SE ROMPE (%d%% de los fallos)</font></font>', GRAY, failText, RED, math.floor(brk * 100 + 0.5)))
		else
			table.insert(lines, string.format('<font size="12" color="%s">%s (el objeto no se rompe)</font>', GRAY, failText))
		end
	end
	table.insert(lines, "")
	local goldCost = EnhanceCatalog.GoldCost(item, target)
	local gems = EnhanceCatalog.Gems[target]
	local goldNow = player:GetAttribute("Gold")
	local haveGold = if typeof(goldNow) == "number" then goldNow else 0
	local haveGems = gemsOwned()
	table.insert(lines, string.format('Oro: <font color="%s">%s</font> / %s', if haveGold >= goldCost then GREEN else RED, withCommas(haveGold), withCommas(goldCost)))
	table.insert(lines, string.format('Gemas de Mejora: <font color="%s">%d</font> / %d', if haveGems >= gems then GREEN else RED, haveGems, gems))
	detail.Text = table.concat(lines, "\n")
	goButton.Visible = true
	goButton.Text = if rate >= 1 then "Mejorar" else "Intentar mejora"
	-- Pergamino de Protección: solo tiene sentido si fallar baja la pieza (+8 y +9)
	local scrolls = scrollsOwned()
	scrollButton.Visible = drop > 0
	goButton.Size = if drop > 0 then UDim2.fromOffset(196, 38) else UDim2.fromOffset(318, 38)
	if drop > 0 then
		if scrolls < 1 then
			useScroll = false
		end
		scrollButton.Text = if useScroll then "🛡 Pergamino: SÍ" else string.format("🛡 Pergamino (%d)", scrolls)
		scrollButton.BackgroundColor3 = if useScroll then Color3.fromRGB(150, 90, 190) elseif scrolls > 0 then Color3.fromRGB(70, 70, 100) else Color3.fromRGB(60, 55, 60)
		table.insert(lines, string.format('<font size="12" color="%s">Pergamino de Protección: si falla, la pieza NO baja ni se rompe (tienes %d). Solo se gasta si el intento falla.</font>', GRAY, scrolls))
		detail.Text = table.concat(lines, "\n")
	end
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
		t.TextColor3 = Color3.fromRGB(170, 170, 185)
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
		h.TextColor3 = theme.Primary
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
			none.TextColor3 = Color3.fromRGB(130, 130, 145)
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
		local name = UITheme.Text(b, GearView.DisplayName(item, e.Plus), 12, col, UDim2.fromOffset(8, 2), UDim2.new(1, -16, 0, 18))
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local sub = if e.Worn then "Puesto · " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot) else "Mochila · " .. (ItemCatalog.SlotDisplay[item.Slot] or item.Slot)
		UITheme.Text(b, sub, 10, Color3.fromRGB(160, 160, 175), UDim2.fromOffset(8, 20), UDim2.new(1, -16, 0, 14))
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
	win = UITheme.Frame(gui, theme, UDim2.fromOffset(640, 460), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	WindowDrag.Attach(win, "Smith", 52, 50)
	titleLabel = UITheme.Text(win, smithName, 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(500, 26))
	subtitleLabel = UITheme.Text(win, smithTitle .. "  ·  arrastra el título para mover", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 30), UDim2.fromOffset(580, 16))

	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.Parent = win
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	listScroll = Instance.new("ScrollingFrame")
	listScroll.Position = UDim2.fromOffset(16, 62)
	listScroll.Size = UDim2.fromOffset(250, 384)
	listScroll.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 5
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.fromOffset(0, 0)
	listScroll.Parent = win
	Instance.new("UICorner", listScroll)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = listScroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listScroll

	local box = Instance.new("Frame")
	box.Position = UDim2.fromOffset(278, 62)
	box.Size = UDim2.fromOffset(346, 384)
	box.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	box.BorderSizePixel = 0
	box.Parent = win
	Instance.new("UICorner", box)
	UITheme.Border(box, theme, 2)

	-- RANURA DE FORJA: aquí queda la pieza elegida
	forgeSlot = Instance.new("Frame")
	forgeSlot.Position = UDim2.fromOffset(14, 10)
	forgeSlot.Size = UDim2.fromOffset(318, 50)
	forgeSlot.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
	forgeSlot.BorderSizePixel = 0
	forgeSlot.Parent = box
	Instance.new("UICorner", forgeSlot)
	forgeStroke = Instance.new("UIStroke")
	forgeStroke.Thickness = 2
	forgeStroke.Color = theme.Secondary
	forgeStroke.Parent = forgeSlot
	UITheme.Text(forgeSlot, "FORJA", 10, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(10, 3), UDim2.fromOffset(100, 12))
	forgeName = UITheme.Text(forgeSlot, "Elige una pieza a la izquierda", 15, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(10, 18), UDim2.fromOffset(298, 28))
	forgeName.TextTruncate = Enum.TextTruncate.AtEnd

	detail = UITheme.Text(box, "", 14, nil, UDim2.fromOffset(14, 70), UDim2.fromOffset(318, 216))
	detail.TextWrapped = true
	detail.RichText = true
	detail.TextYAlignment = Enum.TextYAlignment.Top

	resultLabel = UITheme.Text(box, "", 14, nil, UDim2.fromOffset(14, 290), UDim2.fromOffset(318, 42))
	resultLabel.TextWrapped = true
	resultLabel.RichText = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top

	goButton = Instance.new("TextButton")
	goButton.Position = UDim2.fromOffset(14, 336)
	goButton.Size = UDim2.fromOffset(318, 38)
	goButton.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
	goButton.TextColor3 = Color3.new(1, 1, 1)
	goButton.Font = UITheme.Font
	goButton.TextSize = 16
	goButton.Text = "Mejorar"
	goButton.Visible = false
	goButton.Parent = box
	Instance.new("UICorner", goButton)
	goButton.Activated:Connect(function()
		local e = currentEntry()
		if e and actionRemote then
			actionRemote:FireServer("Enhance", e.Kind, e.Key, useScroll)
		end
	end)
	scrollButton = Instance.new("TextButton")
	scrollButton.Position = UDim2.fromOffset(218, 336)
	scrollButton.Size = UDim2.fromOffset(114, 38)
	scrollButton.BackgroundColor3 = Color3.fromRGB(70, 70, 100)
	scrollButton.TextColor3 = Color3.new(1, 1, 1)
	scrollButton.Font = UITheme.Font
	scrollButton.TextSize = 12
	scrollButton.TextWrapped = true
	scrollButton.Visible = false
	scrollButton.Parent = box
	Instance.new("UICorner", scrollButton)
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
