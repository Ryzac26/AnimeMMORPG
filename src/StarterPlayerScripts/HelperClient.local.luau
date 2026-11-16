--!strict
--[[
    HelperClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HelperClient
    Ventana de AYUDANTES DE COMBATE (estilo "C"): se abre desde los 3 PERFILES de la barra de menú (donde antes estaba «Mascota»),
    desde el menú móvil, o con el tablón de la Cabaña de ayudantes de tu casa.
      - Arriba: tus 3 ranuras (retrato, nombre, nivel y estrellas). La 1 es gratis; la 2 y la 3 las abre el pase. Todas desde el nivel 1.
      - Pestaña «Ayudante»: el ayudante de la ranura (cuerpo entero), nivel y XP (recibe el 10% de la tuya, sin quitártela), lo que aporta,
        su PODER de combate (solo contra monstruos) y sus 4 piezas de equipo (Arma, Casco, Armadura, Botas) del set de su rol, sacadas de tu mochila.
      - Pestaña «Colección»: álbum de tu facción (6 roles x 5 rarezas); elige uno y equípalo en la ranura. Los repetidos suben estrellas (máx. 5).
      - Los ayudantes ayudan en PvE; contra jugadores no atacan y sus bonos valen el 50%.
    El servidor (HelperService) valida todo. MenuBus: "Helpers" (abre/cierra) y "Helpers:1|2|3" (abre esa ranura).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local HelperCatalog = require(Modules:WaitForChild("HelperCatalog", 10))
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local Inv = require(script.Parent:WaitForChild("InventoryStore", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local Store = require(script.Parent:WaitForChild("HelperStore", 10))
local HelperPortrait = require(script.Parent:WaitForChild("HelperPortrait", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "HelperGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local W, H = 660, 604
local win: Frame? = nil
local selectedSlot = 1
local tab = "Ayudante" -- "Ayudante" | "Coleccion"
local pickedId: string? = nil -- ayudante elegido en el álbum
local gearSlot = "Arma" -- hueco de equipo elegido

local ROLE_ICON = HelperCatalog.RoleIcon
local STAR_ON, STAR_OFF = "★", "☆"

local function state(): any
	return Store.State
end

local function stars(n: number): string
	return string.rep(STAR_ON, n) .. string.rep(STAR_OFF, HelperCatalog.MaxStars - n)
end

local function slotId(st: any, i: number): string?
	local id = st.Slots and st.Slots[i]
	if typeof(id) == "string" and id ~= "" and st.Owned[id] then
		return id
	end
	return nil
end

local function effectsOf(st: any, id: string): { [string]: number }
	local parsed = HelperCatalog.Parse(id)
	local e = st.Owned[id]
	if not parsed or not e then
		return {}
	end
	return HelperCatalog.Effects(parsed, e.S, e.L, st.Level or 1, e.Gp or 0)
end

-- suma de los que de verdad cuentan: ranura abierta y sin repetir rol (igual que el servidor)
local function totalEffects(st: any): { [string]: number }
	local list: { { [string]: number } } = {}
	local seen: { [string]: boolean } = {}
	for i = 1, HelperCatalog.MaxSlots do
		local id = slotId(st, i)
		local parsed = if id then HelperCatalog.Parse(id) else nil
		if id and parsed and st.Open[i] and not seen[parsed.Role] then
			seen[parsed.Role] = true
			table.insert(list, effectsOf(st, id))
		end
	end
	return HelperCatalog.Total(list)
end

local function label(parent: Instance, text: string, size: number, color: Color3?, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, text, size, color, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), align)
	l.TextStrokeTransparency = 1
	return l
end

local function close()
	gui.Enabled = false
	Store.Action("Close")
end

local build: () -> ()

local function candidates(role: string, slotName: string): { { Index: number, Id: string, Plus: number, Item: any } }
	local out: { { Index: number, Id: string, Plus: number, Item: any } } = {}
	for index, stack in pairs(Inv.Bag) do
		local item: any = (ItemCatalog.Items :: any)[stack.Id]
		if item and item.Kind == "Set" and item.Slot == slotName and item.Role == role then
			table.insert(out, { Index = index, Id = stack.Id, Plus = stack.Plus or 0, Item = item })
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = HelperCatalog.RarityIndex[a.Item.Rarity] or 0, HelperCatalog.RarityIndex[b.Item.Rarity] or 0
		if ra ~= rb then
			return ra > rb
		end
		if a.Plus ~= b.Plus then
			return a.Plus > b.Plus
		end
		return (a.Item.ReqLevel or 0) > (b.Item.ReqLevel or 0)
	end)
	return out
end

---------------------------------------------------------------------
-- Pestaña «Ayudante»: el de la ranura elegida
---------------------------------------------------------------------
local function drawEquipped(w: Frame, theme: any, pal: { [string]: Color3 }, st: any, id: string)
	local parsed = HelperCatalog.Parse(id) :: HelperCatalog.Parsed
	local e = st.Owned[id]
	local col = HelperCatalog.RarityColor[parsed.Rarity]
	local cap = math.min(st.Level or 1, HelperCatalog.MaxLevel)

	-- izquierda: cuerpo entero, nombre, nivel y XP
	local left = NpcKit.Panel(w, theme, UDim2.fromOffset(220, 410), UDim2.fromOffset(14, 184), "inset")
	HelperPortrait.Build(left, parsed, UDim2.fromOffset(220, 236), UDim2.fromOffset(0, 0), { Full = true, Animate = true, Spin = true })
	label(left, HelperCatalog.FullName(parsed), 15, col, 6, 238, 208, 20, Enum.TextXAlignment.Center).TextTruncate = Enum.TextTruncate.AtEnd
	label(left, string.format("%s %s · %s · %s", ROLE_ICON[parsed.Role] or "", parsed.Role, HelperCatalog.FactionName[parsed.Faction] or parsed.Faction, HelperCatalog.RarityName[parsed.Rarity]), 11, pal.FMuted, 6, 260, 208, 16, Enum.TextXAlignment.Center)
	label(left, string.format("Nivel %d  (tu nivel: %d)", e.L, st.Level or 1), 12, pal.FText, 6, 282, 208, 16, Enum.TextXAlignment.Center)
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(14, 304)
	bar.Size = UDim2.fromOffset(192, 10)
	bar.BackgroundColor3 = pal.Slot
	bar.BorderSizePixel = 0
	bar.Parent = left
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 5)
	local atCap = e.L >= cap
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(if atCap then 1 else math.clamp(e.X / math.max(1, e.N), 0, 1), 1)
	fill.BackgroundColor3 = col
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
	label(left, if atCap then "Alcanzó tu nivel: sube de nivel para que siga creciendo" else string.format("XP %d / %d  (recibe el %d%% de la tuya)", e.X, e.N, math.floor(HelperCatalog.XpShare * 100 + 0.5)), 10, pal.FMuted, 6, 318, 208, 14, Enum.TextXAlignment.Center).TextWrapped = true
	label(left, stars(e.S), 18, pal.Accent, 6, 338, 208, 22, Enum.TextXAlignment.Center)
	local rest = NpcKit.Button(left, theme, "Descansar (liberar ranura)", UDim2.fromOffset(196, 30), UDim2.fromOffset(12, 368), "neutral", function()
		Store.Action("Unequip", selectedSlot)
	end)
	rest.TextSize = 12

	-- derecha: equipo
	label(w, string.format("EQUIPO  ·  set de %s", parsed.Role), 13, pal.Accent, 246, 184, 215, 18).TextTruncate = Enum.TextTruncate.AtEnd
	-- AUTOEQUIPAR: pone solo lo mejor de tu mochila (reemplaza únicamente si es mejor que lo que lleva); "Todos" = los ayudantes de tus ranuras
	local autoOne = NpcKit.Button(w, theme, "★ Autoequipar", UDim2.fromOffset(112, 22), UDim2.fromOffset(466, 181), "action", function()
		Store.Action("GearAuto", id)
	end)
	autoOne.TextSize = 11
	local autoAll = NpcKit.Button(w, theme, "★ Todos", UDim2.fromOffset(62, 22), UDim2.fromOffset(584, 181), "neutral", function()
		Store.Action("GearAuto", "all")
	end)
	autoAll.TextSize = 11
	local slots = HelperCatalog.GearSlots
	for i, slotName in ipairs(slots) do
		local card = NpcKit.Panel(w, theme, UDim2.fromOffset(94, 88), UDim2.fromOffset(246 + (i - 1) * 102, 206), "card")
		local on = slotName == gearSlot
		local piece = e.G and e.G[slotName]
		local item: any = if piece then (ItemCatalog.Items :: any)[piece.Id] else nil
		label(card, HelperCatalog.GearSlotName[slotName], 11, pal.FMuted, 0, 4, 94, 14, Enum.TextXAlignment.Center)
		if item then
			local ic = ItemIcon.Build(card, item, 40, HelperCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1))
			ic.AnchorPoint = Vector2.new(0.5, 0)
			ic.Position = UDim2.new(0.5, 0, 0, 20)
			label(card, if piece.Plus > 0 then "+" .. piece.Plus else "", 11, pal.Accent, 0, 64, 94, 14, Enum.TextXAlignment.Center)
		else
			label(card, "+", 28, pal.FMuted, 0, 24, 94, 34, Enum.TextXAlignment.Center)
			label(card, "vacío", 10, pal.FMuted, 0, 66, 94, 14, Enum.TextXAlignment.Center)
		end
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.ZIndex = 12
		b.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = if on then pal.Accent else pal.Edge
		stroke.Thickness = if on then 3 else 1
		stroke.Transparency = if on then 0 else 0.5
		stroke.Parent = b
		b.Activated:Connect(function()
			gearSlot = slotName
			build()
		end)
	end

	-- lista de piezas de la mochila para el hueco elegido
	local pick = NpcKit.Panel(w, theme, UDim2.fromOffset(400, 170), UDim2.fromOffset(246, 302), "inset")
	local equippedPiece = e.G and e.G[gearSlot]
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(4, 4)
	scroll.Size = UDim2.new(1, -8, 1, -8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = pick
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local order = 0
	local function row(): Frame
		order += 1
		local f = Instance.new("Frame")
		f.Size = UDim2.new(1, -6, 0, 30)
		f.BackgroundColor3 = pal.Slot
		f.BorderSizePixel = 0
		f.LayoutOrder = order
		f.Parent = scroll
		Instance.new("UICorner", f).CornerRadius = UDim.new(0, 5)
		return f
	end
	if equippedPiece then
		local f = row()
		local item: any = (ItemCatalog.Items :: any)[equippedPiece.Id]
		label(f, "Puesta: " .. (if item then item.Name else equippedPiece.Id), 11, pal.FText, 8, 7, 280, 16).TextTruncate = Enum.TextTruncate.AtEnd
		local rm = NpcKit.Button(f, theme, "Quitar", UDim2.fromOffset(70, 22), UDim2.new(1, -76, 0, 4), "danger", function()
			Store.Action("GearUnequip", id, gearSlot)
		end)
		rm.TextSize = 11
	end
	local list = candidates(parsed.Role, gearSlot)
	if #list == 0 then
		local f = Instance.new("TextLabel")
		f.Size = UDim2.new(1, -6, 0, 70)
		f.BackgroundTransparency = 1
		f.Font = Enum.Font.Gotham
		f.TextSize = 12
		f.TextWrapped = true
		f.TextColor3 = pal.FMuted
		f.LayoutOrder = order + 1
		f.Text = string.format("No tienes %s de rol %s en la mochila.\nCaen de los monstruos; con ayudantes equipados, cada pieza tiene un %d%% extra de traer otra para ellos.", string.lower(HelperCatalog.GearSlotName[gearSlot]), parsed.Role, math.floor(HelperCatalog.BonusGearChance * 100 + 0.5))
		f.Parent = scroll
	end
	for _, c in ipairs(list) do
		local f = row()
		local ic = ItemIcon.Build(f, c.Item, 24, HelperCatalog.RarityColor[c.Item.Rarity] or Color3.new(1, 1, 1))
		ic.Position = UDim2.fromOffset(4, 3)
		local lvTooHigh = typeof(c.Item.ReqLevel) == "number" and c.Item.ReqLevel > (st.Level or 1)
		label(f, string.format("[%s] %s%s", HelperCatalog.RarityName[c.Item.Rarity] or c.Item.Rarity, c.Item.Name, if c.Plus > 0 then " +" .. c.Plus else ""), 11, if lvTooHigh then Color3.fromRGB(230, 110, 100) else pal.FText, 34, 7, 250, 16).TextTruncate = Enum.TextTruncate.AtEnd
		local put = NpcKit.Button(f, theme, if lvTooHigh then "Nv." .. tostring(c.Item.ReqLevel) else "Poner", UDim2.fromOffset(70, 22), UDim2.new(1, -76, 0, 4), if lvTooHigh then "neutral" else "buy", function()
			if lvTooHigh then
				return
			end
			Store.Action("GearEquip", id, gearSlot, c.Index)
		end)
		put.TextSize = 11
	end

	-- efectos y poder
	local dupRole = false
	for i = 1, HelperCatalog.MaxSlots do
		local other = slotId(st, i)
		local op = if other and i ~= selectedSlot then HelperCatalog.Parse(other) else nil
		if op and op.Role == parsed.Role then
			dupRole = true
		end
	end
	local eff = HelperCatalog.EffectText(effectsOf(st, id))
	label(w, if dupRole then "APORTA A TU PERSONAJE   ⚠ no se suma: ya hay otro de su rol" else "APORTA A TU PERSONAJE", 13, if dupRole then Color3.fromRGB(230, 170, 90) else pal.Accent, 246, 480, 400, 18)
	local effLabel = label(w, if eff ~= "" then eff else "—", 13, pal.FText, 246, 498, 400, 18)
	effLabel.TextTruncate = Enum.TextTruncate.AtEnd
	local power = HelperCatalog.Powers[parsed.Role]
	label(w, string.format("PODER  ·  %s  (solo contra monstruos)", power and power.Name or ""), 13, pal.Accent, 246, 520, 400, 18)
	local pt = label(w, HelperCatalog.PowerText(parsed.Role, parsed.Rarity), 11, pal.FText, 246, 538, 400, 44)
	pt.TextWrapped = true
	pt.TextYAlignment = Enum.TextYAlignment.Top
end

---------------------------------------------------------------------
-- Pestaña «Colección»: álbum de la facción
---------------------------------------------------------------------
local function drawCollection(w: Frame, theme: any, pal: { [string]: Color3 }, st: any)
	local faction = player:GetAttribute("Faction")
	local fk = if typeof(faction) == "string" and HelperCatalog.Roster[faction] then faction else "Saiyan"
	local owned, total = 0, #HelperCatalog.Roles * #HelperCatalog.Rarities
	for _, role in ipairs(HelperCatalog.Roles) do
		for _, rarity in ipairs(HelperCatalog.Rarities) do
			if st.Owned[HelperCatalog.Id(fk, role, rarity)] then
				owned += 1
			end
		end
	end
	if not pickedId or not HelperCatalog.Parse(pickedId) then
		pickedId = slotId(st, selectedSlot) or HelperCatalog.Id(fk, HelperCatalog.Roles[1], HelperCatalog.Rarities[1])
	end
	label(w, string.format("ÁLBUM · %s   %d / %d", HelperCatalog.FactionName[fk] or fk, owned, total), 13, pal.Accent, 14, 184, 300, 18)

	local grid = NpcKit.Panel(w, theme, UDim2.fromOffset(304, 330), UDim2.fromOffset(14, 206), "inset")
	for c, rarity in ipairs(HelperCatalog.Rarities) do
		label(grid, HelperCatalog.RarityName[rarity], 10, HelperCatalog.RarityColor[rarity], 64 + (c - 1) * 46, 6, 46, 14, Enum.TextXAlignment.Center)
	end
	for r, role in ipairs(HelperCatalog.Roles) do
		local y = 26 + (r - 1) * 50
		label(grid, role, 11, pal.FText, 6, y + 14, 60, 16)
		for c, rarity in ipairs(HelperCatalog.Rarities) do
			local id = HelperCatalog.Id(fk, role, rarity)
			local e = st.Owned[id]
			local rc = HelperCatalog.RarityColor[rarity]
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(66 + (c - 1) * 46, y)
			b.Size = UDim2.fromOffset(42, 44)
			b.BackgroundColor3 = if e then rc:Lerp(Color3.new(0, 0, 0), 0.55) else pal.Slot
			b.BorderSizePixel = 0
			b.Font = UITheme.Font
			b.TextSize = 18
			b.TextColor3 = if e then Color3.new(1, 1, 1) else pal.FMuted
			b.Text = if e then (ROLE_ICON[role] or "★") else "?"
			b.AutoButtonColor = true
			b.Parent = grid
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
			local on = id == pickedId
			local stroke = Instance.new("UIStroke")
			stroke.Color = if on then pal.Accent else rc
			stroke.Thickness = if on then 3 else 1
			stroke.Transparency = if on then 0 else (if e then 0.2 else 0.75)
			stroke.Parent = b
			if e then
				local s = label(b, STAR_ON .. e.S, 9, rc, 0, 30, 42, 12, Enum.TextXAlignment.Center)
				s.ZIndex = 3
			end
			for i = 1, HelperCatalog.MaxSlots do
				if slotId(st, i) == id then
					local chip = NpcKit.Chip(b, tostring(i), pal.Accent, UDim2.fromOffset(2, 2), UDim2.fromOffset(14, 14))
					chip.TextSize = 9
				end
			end
			b.Activated:Connect(function()
				pickedId = id
				build()
			end)
		end
	end

	-- derecha: el elegido
	local id = pickedId :: string
	local parsed = HelperCatalog.Parse(id) :: HelperCatalog.Parsed
	local e = st.Owned[id]
	local col = HelperCatalog.RarityColor[parsed.Rarity]
	local right = NpcKit.Panel(w, theme, UDim2.fromOffset(318, 352), UDim2.fromOffset(328, 184), "inset")
	HelperPortrait.Build(right, parsed, UDim2.fromOffset(120, 150), UDim2.fromOffset(6, 6), { Full = true, Animate = e ~= nil, Dim = e == nil })
	label(right, if e then HelperCatalog.FullName(parsed) else "???", 15, if e then col else pal.FMuted, 130, 10, 184, 38).TextWrapped = true
	label(right, string.format("%s %s\n%s", ROLE_ICON[parsed.Role] or "", parsed.Role, HelperCatalog.RarityName[parsed.Rarity]), 11, pal.FMuted, 130, 52, 184, 30).TextWrapped = true
	if e then
		label(right, string.format("Nivel %d", e.L), 12, pal.FText, 130, 88, 184, 16)
		label(right, stars(e.S), 16, pal.Accent, 130, 106, 184, 20)
	else
		label(right, "Aún no lo tienes", 12, pal.FMuted, 130, 88, 184, 16)
	end
	local power = HelperCatalog.Powers[parsed.Role]
	local base = HelperCatalog.Effects(parsed, if e then e.S else 1, if e then e.L else (st.Level or 1), st.Level or 1, if e then (e.Gp or 0) else 0)
	label(right, "APORTA", 12, pal.Accent, 10, 164, 298, 16)
	label(right, HelperCatalog.EffectText(base), 12, pal.FText, 10, 182, 298, 16).TextTruncate = Enum.TextTruncate.AtEnd
	label(right, string.format("PODER · %s", power and power.Name or ""), 12, pal.Accent, 10, 206, 298, 16)
	local pt = label(right, HelperCatalog.PowerText(parsed.Role, parsed.Rarity), 11, pal.FText, 10, 224, 298, 56)
	pt.TextWrapped = true
	pt.TextYAlignment = Enum.TextYAlignment.Top

	local open = st.Open[selectedSlot] == true
	local equippedHere = slotId(st, selectedSlot) == id
	local btnText: string
	local kind = "buy"
	if not e then
		btnText = "Consíguelo en el Reclutador"
		kind = "neutral"
	elseif not open then
		btnText = "Ranura bloqueada (pase de ranuras)"
		kind = "neutral"
	elseif equippedHere then
		btnText = "Equipado en la ranura " .. selectedSlot
		kind = "neutral"
	else
		btnText = "Equipar en la ranura " .. selectedSlot
	end
	local btn = NpcKit.Button(right, theme, btnText, UDim2.fromOffset(298, 36), UDim2.fromOffset(10, 296), kind, function()
		if not e then
			return
		end
		if not open then
			MenuBus.Fire("Tienda")
			return
		end
		if not equippedHere then
			Store.Action("Equip", id, selectedSlot)
		end
	end)
	btn.TextSize = 13
	label(w, "Los repetidos suben las estrellas (máx. 5); después dan oro.", 10, pal.FMuted, 14, 540, 304, 28).TextWrapped = true
end

---------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------
build = function()
	if win then
		win:Destroy()
		win = nil
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Ayudantes de combate", "Hasta 3 · reciben el 10% de tu XP (sin quitártela) · ayudan en PvE", "🤝", close)
	win = w
	WindowDrag.Attach(w, "Helpers", 52, 50)

	local st = state()
	if not st then
		label(w, "Cargando tus ayudantes...", 14, pal.FMuted, 14, 100, W - 28, 20, Enum.TextXAlignment.Center)
		return
	end

	-- ranuras (perfiles)
	for i = 1, HelperCatalog.MaxSlots do
		local card = NpcKit.Panel(w, theme, UDim2.fromOffset(204, 64), UDim2.fromOffset(14 + (i - 1) * 212, 76), "card")
		local id = slotId(st, i)
		local open = st.Open[i] == true
		local parsed = if id then HelperCatalog.Parse(id) else nil
		local on = i == selectedSlot
		if id and parsed and open then
			HelperPortrait.Build(card, parsed, UDim2.fromOffset(56, 56), UDim2.fromOffset(4, 4), {})
			local e = st.Owned[id]
			label(card, HelperCatalog.NameOf(parsed), 14, HelperCatalog.RarityColor[parsed.Rarity], 64, 6, 134, 18).TextTruncate = Enum.TextTruncate.AtEnd
			label(card, string.format("%s %s", ROLE_ICON[parsed.Role] or "", parsed.Role), 11, pal.FMuted, 64, 24, 134, 14)
			label(card, string.format("Nv.%d  %s", e.L, stars(e.S)), 11, pal.Accent, 64, 40, 134, 16)
		elseif not open then
			label(card, "🔒", 24, pal.FMuted, 8, 14, 44, 34, Enum.TextXAlignment.Center)
			label(card, "Ranura " .. i, 13, pal.FText, 64, 8, 134, 18)
			label(card, "Se abre con el pase de ranuras", 10, pal.FMuted, 64, 28, 134, 28).TextWrapped = true
		else
			label(card, "＋", 26, pal.FMuted, 8, 14, 44, 34, Enum.TextXAlignment.Center)
			label(card, "Ranura " .. i .. " libre", 13, pal.FText, 64, 8, 134, 18)
			label(card, "Elige uno en la Colección", 10, pal.FMuted, 64, 28, 134, 28).TextWrapped = true
		end
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.ZIndex = 12
		b.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = if on then pal.Accent else pal.Edge
		stroke.Thickness = if on then 3 else 1
		stroke.Transparency = if on then 0 else 0.5
		stroke.Parent = b
		b.Activated:Connect(function()
			selectedSlot = i
			pickedId = nil
			build()
		end)
	end

	-- pestañas + total
	NpcKit.Tab(w, theme, "Ayudante", UDim2.fromOffset(120, 28), UDim2.fromOffset(14, 148), tab == "Ayudante", function()
		tab = "Ayudante"
		build()
	end)
	NpcKit.Tab(w, theme, "Colección", UDim2.fromOffset(120, 28), UDim2.fromOffset(140, 148), tab == "Coleccion", function()
		tab = "Coleccion"
		build()
	end)
	local total = HelperCatalog.EffectText(totalEffects(st))
	local tl = label(w, "Total: " .. (if total ~= "" then total else "sin ayudantes"), 11, pal.FText, 270, 154, 376, 16, Enum.TextXAlignment.Right)
	tl.TextTruncate = Enum.TextTruncate.AtEnd

	if tab == "Coleccion" then
		drawCollection(w, theme, pal, st)
		return
	end
	-- pestaña Ayudante
	local open = st.Open[selectedSlot] == true
	local id = if open then slotId(st, selectedSlot) else nil
	if not open then
		label(w, "🔒", 40, pal.FMuted, 14, 230, W - 28, 50, Enum.TextXAlignment.Center)
		label(w, "Esta ranura se abre con el pase de ranuras de ayudante (tienda > Pases).", 14, pal.FText, 40, 290, W - 80, 40, Enum.TextXAlignment.Center).TextWrapped = true
		NpcKit.Button(w, theme, "Ver el pase en la tienda", UDim2.fromOffset(240, 38), UDim2.fromOffset((W - 240) / 2, 346), "buy", function()
			MenuBus.Fire("Tienda")
		end)
	elseif not id then
		label(w, "Ranura libre", 20, pal.FText, 14, 240, W - 28, 28, Enum.TextXAlignment.Center)
		label(w, "Elige a quién quieres en esta ranura desde tu Colección.\nLos ayudantes se consiguen con cupones en el Reclutador de tu ciudad.", 13, pal.FMuted, 40, 276, W - 80, 44, Enum.TextXAlignment.Center).TextWrapped = true
		NpcKit.Button(w, theme, "Ir a la Colección", UDim2.fromOffset(220, 38), UDim2.fromOffset((W - 220) / 2, 340), "buy", function()
			tab = "Coleccion"
			build()
		end)
	else
		drawEquipped(w, theme, pal, st, id)
	end
end

local function openWindow(slot: number?)
	if slot then
		selectedSlot = math.clamp(slot, 1, HelperCatalog.MaxSlots)
		pickedId = nil
		tab = "Ayudante"
	end
	Store.Action("State")
	build()
	gui.Enabled = true
end

local rebuildQueued = false
local function refresh()
	if not gui.Enabled or rebuildQueued then
		return
	end
	rebuildQueued = true
	task.delay(0.15, function()
		rebuildQueued = false
		if gui.Enabled then
			build()
		end
	end)
end
Store.Changed:Connect(refresh)
Inv.Changed:Connect(refresh)

MenuBus.Event:Connect(function(name: string)
	if name == "Helpers" then
		if gui.Enabled then
			close()
		else
			openWindow(nil)
		end
	elseif string.sub(name, 1, 8) == "Helpers:" then
		local n = tonumber(string.sub(name, 9))
		if n then
			if gui.Enabled and selectedSlot == n and tab == "Ayudante" then
				close()
			else
				openWindow(n)
			end
		end
	end
end)

-- atajo de teclado (por defecto H, se cambia en Ajustes > Atajos)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and KeyBinds.Matches(input, "Ayudantes") then
		MenuBus.Fire("Helpers")
	end
end)

print("[HelperClient] listo")
