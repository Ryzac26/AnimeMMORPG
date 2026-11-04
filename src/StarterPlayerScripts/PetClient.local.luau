--!strict
--[[
    PetClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > PetClient
    Ventana de MASCOTAS (botón "Mascota" del menú): elige una mascota (la puesta o las de la mochila) y ALIMÉNTALA para subirla de nivel (1..10).
    Cada nivel mejora sus efectos y la hace más grande; en los niveles 4, 7 y 10 evoluciona (más brillo, luz y halo).
    El servidor (PetService) cobra los recursos y sube el nivel. Se mueve arrastrando el título.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local PetCatalog = require(Modules:WaitForChild("PetCatalog", 10))
local LootTables = require(Modules:WaitForChild("LootTables", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))

local RARITY_COLOR: { [string]: Color3 } = {
	Comun = Color3.fromRGB(200, 200, 200), Raro = Color3.fromRGB(80, 160, 255), Epico = Color3.fromRGB(180, 90, 255),
	Legendario = Color3.fromRGB(255, 170, 40), Mitico = Color3.fromRGB(255, 70, 110),
}
local feedRemote = ClientNet.Get("PetFeed")

local gui = Instance.new("ScreenGui")
gui.Name = "PetGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

type Target = { Kind: string, Key: any, Id: string, Plus: number }
local win: Frame? = nil
local selectedKey: string? = nil -- "Equip" o "Bag:<casilla>"
local lastFeed = 0

local function keyOf(t: Target): string
	return if t.Kind == "Equip" then "Equip" else "Bag:" .. tostring(t.Key)
end

local function listTargets(): { Target }
	local out: { Target } = {}
	local eq = Store.Equip["Accesorio2"]
	if eq and (ItemCatalog.Items :: any)[eq] and (ItemCatalog.Items :: any)[eq].Pet then
		table.insert(out, { Kind = "Equip", Key = "Accesorio2", Id = eq, Plus = Store.EquipPlus["Accesorio2"] or 0 })
	end
	local slots: { number } = {}
	for slot in pairs(Store.Bag) do
		table.insert(slots, slot)
	end
	table.sort(slots)
	for _, slot in ipairs(slots) do
		local st = Store.Bag[slot]
		local item: any = (ItemCatalog.Items :: any)[st.Id]
		if item and item.Pet then
			table.insert(out, { Kind = "Bag", Key = slot, Id = st.Id, Plus = st.Plus or 0 })
		end
	end
	return out
end

local function haveOf(id: string): number
	local n = 0
	for _, st in pairs(Store.Bag) do
		if st.Id == id then
			n += st.Count
		end
	end
	return n
end

local function effectLines(item: any, plus: number, nextPlus: number?): string
	local cur = PetCatalog.LevelMult(plus)
	local nxt = if nextPlus then PetCatalog.LevelMult(nextPlus) else nil
	local lines: { string } = {}
	for _, stat in ipairs(PetCatalog.EffectOrder) do
		local base = item.Pet.Effects[stat]
		if base then
			local text = PetCatalog.EffectText[stat] or stat
			local l = string.format("%s  %.1f%%", text, base * cur * 100)
			if nxt then
				l ..= string.format("  →  %.1f%%", base * nxt * 100)
			end
			table.insert(lines, l)
		end
	end
	return table.concat(lines, "\n")
end

local function build()
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local w = UITheme.Frame(gui, theme, UDim2.fromOffset(400, 590), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	win = w
	WindowDrag.Attach(w, "Pets", 52, 50)
	UITheme.Text(w, "MASCOTAS", 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(300, 26))
	UITheme.Text(w, "Aliméntalas para subirlas de nivel (1 a 10)", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 30), UDim2.fromOffset(340, 16))
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.Parent = w
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	local targets = listTargets()
	-- lista de mascotas
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Position = UDim2.fromOffset(18, 58)
	listFrame.Size = UDim2.fromOffset(364, 112)
	listFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	listFrame.BackgroundTransparency = 0.3
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 4
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = w
	Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 6)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = listFrame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.Parent = listFrame

	local chosen: Target? = nil
	for _, t in ipairs(targets) do
		if selectedKey == keyOf(t) then
			chosen = t
		end
	end
	if not chosen and #targets > 0 then
		chosen = targets[1]
		selectedKey = keyOf(targets[1])
	end

	if #targets == 0 then
		local empty = UITheme.Text(w, "No tienes mascotas todavía.\nCaen de monstruos, jefes, cofres y Metin.", 14, Color3.fromRGB(190, 190, 205), UDim2.fromOffset(18, 190), UDim2.fromOffset(364, 60))
		empty.TextWrapped = true
		return
	end

	for i, t in ipairs(targets) do
		local item: any = (ItemCatalog.Items :: any)[t.Id]
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(1, -4, 0, 26)
		b.LayoutOrder = i
		b.AutoButtonColor = true
		local on = chosen ~= nil and keyOf(t) == keyOf(chosen)
		b.BackgroundColor3 = if on then theme.Primary else theme.Dark
		b.BackgroundTransparency = if on then 0.15 else 0.2
		b.TextColor3 = if on then Color3.fromRGB(20, 17, 10) else (RARITY_COLOR[item.Rarity] or Color3.new(1, 1, 1))
		b.Font = UITheme.Font
		b.TextSize = 12
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Text = string.format("  Nv.%d  %s%s", PetCatalog.LevelOf(t.Plus), item.Name, if t.Kind == "Equip" then "   [puesta]" else "")
		b.Parent = listFrame
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		b.Activated:Connect(function()
			selectedKey = keyOf(t)
			build()
		end)
	end

	local t = chosen :: Target
	local item: any = (ItemCatalog.Items :: any)[t.Id]
	local level = PetCatalog.LevelOf(t.Plus)
	local col = RARITY_COLOR[item.Rarity] or Color3.new(1, 1, 1)
	local stage = PetCatalog.Stage(level)

	UITheme.Text(w, item.Name, 20, col, UDim2.fromOffset(18, 184), UDim2.fromOffset(364, 26))
	local sub = if item.Faction then "Mascota de facción" else "Mascota · todas las clases"
	UITheme.Text(w, string.format("%s  ·  Nivel %d / %d  ·  Evolución %d / %d", sub, level, PetCatalog.MaxLevel, stage, #PetCatalog.EVOLVE_AT), 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 210), UDim2.fromOffset(364, 16))

	-- barra de nivel
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(18, 232)
	bar.Size = UDim2.fromOffset(364, 10)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	bar.BorderSizePixel = 0
	bar.Parent = w
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale((level - 1) / (PetCatalog.MaxLevel - 1), 1)
	fill.BackgroundColor3 = col
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)

	local maxed = level >= PetCatalog.MaxLevel
	UITheme.Text(w, if maxed then "EFECTOS (nivel máximo)" else "EFECTOS  (ahora  →  nivel " .. (level + 1) .. ")", 13, theme.Primary, UDim2.fromOffset(18, 254), UDim2.fromOffset(364, 18))
	local eff = UITheme.Text(w, effectLines(item, t.Plus, if maxed then nil else t.Plus + 1), 14, Color3.new(1, 1, 1), UDim2.fromOffset(18, 274), UDim2.fromOffset(364, 80))
	eff.TextYAlignment = Enum.TextYAlignment.Top

	-- evolución
	local nextEvo: number? = nil
	for _, at in ipairs(PetCatalog.EVOLVE_AT) do
		if level < at then
			nextEvo = at
			break
		end
	end
	local evoText = if nextEvo then string.format("Evoluciona en el nivel %d: más brillo y tamaño.", nextEvo) else "¡Forma final! Brilla con halo."
	UITheme.Text(w, evoText, 12, Color3.fromRGB(190, 190, 205), UDim2.fromOffset(18, 362), UDim2.fromOffset(364, 18))

	-- poder (desde Épico)
	local family: string = item.Pet.Family
	local pName, pText, pTier = PetCatalog.PowerInfo(family, item.Rarity)
	if pName and pText then
		UITheme.Text(w, string.format("PODER  ·  %s  (%d/3)", pName, pTier :: number), 14, theme.Primary, UDim2.fromOffset(18, 388), UDim2.fromOffset(364, 18))
		local pt = UITheme.Text(w, pText, 12, Color3.fromRGB(215, 218, 230), UDim2.fromOffset(18, 408), UDim2.fromOffset(364, 44))
		pt.TextWrapped = true
		pt.TextYAlignment = Enum.TextYAlignment.Top
	else
		local why = if item.Faction then "Esta mascota de facción da energía; no tiene poder." else "El poder se desbloquea desde la rareza Épica."
		UITheme.Text(w, why, 12, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(18, 388), UDim2.fromOffset(364, 18))
	end

	-- costo y botón
	local feedBtn = Instance.new("TextButton")
	feedBtn.Position = UDim2.fromOffset(18, 524)
	feedBtn.Size = UDim2.fromOffset(364, 44)
	feedBtn.Font = UITheme.Font
	feedBtn.TextSize = 16
	feedBtn.AutoButtonColor = false
	feedBtn.Parent = w
	Instance.new("UICorner", feedBtn)
	if maxed then
		feedBtn.Text = "Nivel máximo"
		feedBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 80)
		feedBtn.TextColor3 = Color3.fromRGB(190, 190, 200)
	else
		local res, count = PetCatalog.FeedCost(item.Rarity, level + 1)
		local have = haveOf(res)
		local resName = (LootTables.Materials :: any)[res].Name
		local ok = have >= count
		local costLabel = UITheme.Text(w, string.format("Alimento: %d × %s  (tienes %d)", count, resName, have), 14, if ok then Color3.fromRGB(150, 235, 150) else Color3.fromRGB(255, 130, 130), UDim2.fromOffset(18, 468), UDim2.fromOffset(364, 20))
		costLabel.TextXAlignment = Enum.TextXAlignment.Left
		UITheme.Text(w, "Los recursos se recolectan en los nodos de cada franja.", 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(18, 490), UDim2.fromOffset(364, 16))
		feedBtn.Text = "ALIMENTAR  →  Nivel " .. (level + 1)
		feedBtn.BackgroundColor3 = if ok then Color3.fromRGB(50, 130, 70) else Color3.fromRGB(70, 70, 80)
		feedBtn.TextColor3 = if ok then Color3.new(1, 1, 1) else Color3.fromRGB(190, 190, 200)
		feedBtn.Activated:Connect(function()
			if os.clock() - lastFeed < 0.3 then
				return
			end
			lastFeed = os.clock()
			feedRemote:FireServer(t.Kind, t.Key)
		end)
	end
end

Store.Changed:Connect(function()
	if gui.Enabled then
		build()
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name == "Pets" then
		if gui.Enabled then
			gui.Enabled = false
		else
			build()
			gui.Enabled = true
		end
	end
end)
