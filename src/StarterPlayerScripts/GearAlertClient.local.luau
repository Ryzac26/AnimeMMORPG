--!strict
--[[
    GearAlertClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > GearAlertClient
    AVISO DE "MEJOR OBJETO": cuando recibes un objeto que tu personaje puede usar y es MEJOR que lo que llevas en esa ranura
    (o la ranura está vacía), aparece una tarjeta a un costado con el objeto, cuánto mejora y el botón "Equipar ahora".
    La tarjeta desaparece sola pasados COOLDOWN segundos (o al pulsar Ignorar / equipar / si ya no es mejor).
    Ajustes: COOLDOWN, MAX_CARDS, POSITION.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local COOLDOWN = 12 -- segundos que dura cada tarjeta
local MAX_CARDS = 3 -- tarjetas a la vez (la más vieja se quita)
local POSITION = UDim2.new(0, 16, 0.5, 0) -- lado izquierdo, centrado
local ARM_DELAY = 4 -- s tras entrar: el inventario inicial no genera avisos

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))
local GearView = require(script.Parent:WaitForChild("GearView", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "GearAlertGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 15
gui.Parent = player:WaitForChild("PlayerGui", 10)

local holder = Instance.new("Frame")
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0, 0.5)
holder.Position = POSITION
holder.Size = UDim2.fromOffset(270, 10)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 8)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Parent = holder

type Card = { Frame: Frame, Id: string, Slot: string, Gain: number, Dead: boolean }
local cards: { Card } = {}
local order = 0

local function remove(card: Card)
	if card.Dead then
		return
	end
	card.Dead = true
	local i = table.find(cards, card)
	if i then
		table.remove(cards, i)
	end
	card.Frame:Destroy()
end

local function bagSlotOf(id: string): number?
	for i = 1, Store.Capacity do
		local st = Store.Bag[i]
		if st and st.Id == id then
			return i
		end
	end
	return nil
end

local function worthAlert(c: GearView.Comparison?): boolean
	return c ~= nil and c.Usable and (c.Verdict == "Better" or c.Verdict == "New")
end

local function show(id: string)
	local c = GearView.Compare(id)
	if not c or not worthAlert(c) then
		return
	end
	-- una sola tarjeta por ranura: se queda la mejor
	for _, other in ipairs(table.clone(cards)) do
		if other.Slot == c.Slot then
			if other.Gain >= c.Gain and other.Id ~= id then
				return
			end
			remove(other)
		end
	end
	while #cards >= MAX_CARDS do
		remove(cards[1])
	end

	local theme = UITheme.For(player:GetAttribute("Faction"))
	local item = c.Item
	local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
	local slotName = ItemCatalog.SlotDisplay[c.Slot] or c.Slot

	order += 1
	local f = Instance.new("Frame")
	f.LayoutOrder = order
	f.Size = UDim2.fromOffset(270, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Parent = holder
	Instance.new("UICorner", f)
	local stroke = Instance.new("UIStroke")
	stroke.Color = col
	stroke.Thickness = 2
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 10)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = f
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 5)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = f

	local function label(text: string, size: number, o: number): TextLabel
		local t = Instance.new("TextLabel")
		t.LayoutOrder = o
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
		t.Text = text
		t.Parent = f
		return t
	end

	local green = "#6fdc7f"
	local title = if c.Verdict == "New" then string.format("¡Nuevo para tu ranura de %s!", slotName:lower()) else string.format("¡Mejor %s!", slotName:lower())
	label(string.format('<font color="%s">%s</font>', green, title), 14, 1)
	label(string.format('<font color="#%s">%s</font>', col:ToHex(), item.Name), 15, 2)

	local lines = {}
	for _, stat in ipairs(GearView.StatOrder) do
		local v = c.Effects[stat]
		if v then
			local line = string.format("%s %s", GearView.StatName[stat], GearView.Format(stat, v))
			local d = c.Delta[stat]
			if c.EquippedEffects and d and math.abs(d) > 0.00001 then
				line ..= string.format(' <font color="%s">(%s)</font>', if d > 0 then green else "#ff6b6b", GearView.Format(stat, d))
			end
			table.insert(lines, line)
		end
	end
	local body = label(table.concat(lines, "\n"), 12, 3)
	body.Font = Enum.Font.Gotham
	if c.Verdict == "Better" and c.EquippedItem then
		local note = label(string.format('<font color="%s">+%.1f%% de poder</font> sobre %s', green, c.Gain * 100, c.EquippedItem.Name), 12, 4)
		note.Font = Enum.Font.Gotham
	end

	local buttons = Instance.new("Frame")
	buttons.LayoutOrder = 5
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 30)
	buttons.Parent = f

	local card: Card = { Frame = f, Id = id, Slot = c.Slot, Gain = c.Gain, Dead = false }
	table.insert(cards, card)

	local function mkButton(text: string, x: number, w: number, color: Color3, fn: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.new(x, 0, 0, 0)
		b.Size = UDim2.new(w, -4, 1, 0)
		b.BackgroundColor3 = color
		b.Text = text
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = UITheme.Font
		b.TextSize = 13
		b.Parent = buttons
		Instance.new("UICorner", b)
		b.Activated:Connect(fn)
	end
	mkButton("Equipar ahora", 0, 0.62, Color3.fromRGB(50, 130, 70), function()
		local slotIndex = bagSlotOf(id)
		if slotIndex then
			Store.Action("Equip", slotIndex)
		end
		remove(card)
	end)
	mkButton("Ignorar", 0.62, 0.38, Color3.fromRGB(80, 80, 95), function()
		remove(card)
	end)

	-- barra de tiempo: se vacía en COOLDOWN segundos y la tarjeta desaparece
	local bar = Instance.new("Frame")
	bar.LayoutOrder = 6
	bar.BackgroundColor3 = theme.Primary
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(1, 0, 0, 3)
	bar.Parent = f
	TweenService:Create(bar, TweenInfo.new(COOLDOWN, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 3) }):Play()
	task.delay(COOLDOWN, function()
		remove(card)
	end)
end

-- ¿Sigue siendo válida cada tarjeta? (si ya lo equipaste, lo tiraste o equipaste algo mejor, se quita)
local function recheck()
	for _, card in ipairs(table.clone(cards)) do
		if not bagSlotOf(card.Id) or not worthAlert(GearView.Compare(card.Id)) then
			remove(card)
		end
	end
end

local function bagCounts(): { [string]: number }
	local out: { [string]: number } = {}
	for _, st in pairs(Store.Bag) do
		out[st.Id] = (out[st.Id] or 0) + st.Count
	end
	return out
end

local armed = false
local prevCounts: { [string]: number } = {}
local prevEquip: { [string]: string } = {}

task.delay(ARM_DELAY, function()
	prevCounts = bagCounts()
	prevEquip = table.clone(Store.Equip)
	armed = true
end)

Store.Changed:Connect(function()
	recheck()
	if not armed then
		return
	end
	local now = bagCounts()
	-- lo que acabas de DESEQUIPAR vuelve a la mochila: no cuenta como botín nuevo
	local justUnequipped: { [string]: boolean } = {}
	for slot, id in pairs(prevEquip) do
		if Store.Equip[slot] ~= id then
			justUnequipped[id] = true
		end
	end
	local gained: { string } = {}
	for id, n in pairs(now) do
		if n > (prevCounts[id] or 0) and not justUnequipped[id] then
			table.insert(gained, id)
		end
	end
	prevCounts = now
	prevEquip = table.clone(Store.Equip)
	for _, id in ipairs(gained) do
		show(id)
	end
end)

print("[GearAlertClient] listo")
