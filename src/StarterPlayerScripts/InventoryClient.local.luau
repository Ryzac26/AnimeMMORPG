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

local player = Players.LocalPlayer
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))

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

local function describe(slotIndex: number?)
	local stack = slotIndex and Store.Bag[slotIndex]
	local item = stack and ItemCatalog.Items[stack.Id]
	if not stack or not item then
		info.Text = "Selecciona un objeto"
		return
	end
	local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
	local statsText = ""
	if item.Stats then
		for k, v in pairs(item.Stats) do
			statsText ..= string.format("  +%d %s", v, k)
		end
	end
	info.Text = string.format('<font color="#%s">%s</font> x%d  [%s]%s\n%s', col:ToHex(), item.Name, stack.Count, item.Rarity, statsText, item.Desc or (if item.Slot then "Equipa en: " .. item.Slot else ""))
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
			local t = UITheme.Text(b, item.Name, 11, col, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.8), Enum.TextXAlignment.Center)
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
