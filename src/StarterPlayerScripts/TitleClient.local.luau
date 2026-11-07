--!strict
--[[
    TitleClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TitleClient
    Ventana de TÍTULOS: colección con categorías, progreso de los bloqueados y botón para equipar/quitar.
    Datos: TitleState / TitleAction (TitleService) + TitleCatalog. Se abre con MenuBus "Titles" (botón en Ajustes).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local TitleCatalog: any = require(Modules:WaitForChild("TitleCatalog", 10))

local stateRemote = ClientNet.Get("TitleState")
local actionRemote = ClientNet.Get("TitleAction")

local gui = Instance.new("ScreenGui")
gui.Name = "TitleGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local state: { Unlocked: { [string]: boolean }, Equipped: string?, Counters: { [string]: number } }? = nil
local cat = "Todos"

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local function current(kind: string): number
	if kind == "Level" then
		local v = player:GetAttribute("Level")
		return if typeof(v) == "number" then v else 0
	elseif kind == "Dmg" then
		local v = player:GetAttribute("HallBest")
		return if typeof(v) == "number" then v else 0
	elseif kind == "Forja9" then
		local v = player:GetAttribute("Forja9")
		return if typeof(v) == "number" then v else 0
	end
	return if state then (state.Counters[kind] or 0) else 0
end

local UNIT: { [string]: string } = { Level = "Nv.", Kill = "kills", Metin = "Metin", Boss = "jefes", Min = "min", Dmg = "daño", Forja9 = "piezas +9" }

local function build()
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local WW, HH = 900, 620
	local faction = player:GetAttribute("Faction")
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Títulos",
		"Únicos de verdad: equipa uno y se ve sobre tu personaje", "🏷", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Titles", 40, 50)

	-- categorías
	local cats = { "Todos" }
	for _, c in ipairs(TitleCatalog.Categories) do
		table.insert(cats, c)
	end
	local sideW = 160
	for i, c in ipairs(cats) do
		NpcKit.Tab(w, theme, c, UDim2.fromOffset(sideW - 12, 32), UDim2.fromOffset(12, NpcKit.TOP + (i - 1) * 38), cat == c, function()
			cat = c
			build()
		end)
	end

	-- resumen
	local list: { any } = {}
	local owned, total = 0, 0
	for _, t in ipairs(TitleCatalog.List) do
		if not t.Faction or t.Faction == faction then
			total += 1
			if state and state.Unlocked[t.Id] then
				owned += 1
			end
			if cat == "Todos" or t.Cat == cat then
				table.insert(list, t)
			end
		end
	end
	local eq = if state and state.Equipped then TitleCatalog.ById[state.Equipped] else nil
	local sum = UITheme.Text(w, string.format("Colección: %d / %d   ·   Equipado: %s", owned, total, if eq then eq.Name else "ninguno"), 13, pal.FText, UDim2.fromOffset(sideW + 14, NpcKit.TOP - 4), UDim2.fromOffset(WW - sideW - 40, 20))
	sum.TextStrokeTransparency = 1
	if eq then
		NpcKit.Button(w, theme, "Quitar título", UDim2.fromOffset(120, 24), UDim2.fromOffset(WW - 136, NpcKit.TOP - 6), "danger", function()
			actionRemote:FireServer("Equip", "")
		end)
	end

	local holder = NpcKit.Panel(w, theme, UDim2.fromOffset(WW - sideW - 28, HH - NpcKit.TOP - 28), UDim2.fromOffset(sideW + 12, NpcKit.TOP + 24), "card")
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(4, 4)
	scroll.Size = UDim2.new(1, -8, 1, -8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = pal.Edge
	scroll.Parent = holder
	if not state then
		local l = UITheme.Text(scroll, "Cargando…", 14, pal.Text, UDim2.fromOffset(12, 12), UDim2.fromOffset(300, 20))
		l.TextStrokeTransparency = 1
		return
	end

	-- primero los desbloqueados, luego por rareza
	local rank: { [string]: number } = {}
	for i, r in ipairs(TitleCatalog.Rarities) do
		rank[r] = i
	end
	table.sort(list, function(a: any, b: any)
		local ua, ub = state.Unlocked[a.Id] == true, state.Unlocked[b.Id] == true
		if ua ~= ub then
			return ua
		end
		if rank[a.Rarity] ~= rank[b.Rarity] then
			return rank[a.Rarity] > rank[b.Rarity]
		end
		return a.Name < b.Name
	end)

	local innerW = WW - sideW - 28 - 8 - 14
	local cardW = math.floor((innerW - 10) / 2)
	local cardH = 92
	for i, t in ipairs(list) do
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local unlocked = state.Unlocked[t.Id] == true
		local equipped = state.Equipped == t.Id
		local card = NpcKit.Panel(scroll, theme, UDim2.fromOffset(cardW, cardH), UDim2.fromOffset(6 + col * (cardW + 10), 6 + row * (cardH + 8)), "inset")
		local cols = TitleCatalog.RarityColors[t.Rarity] or TitleCatalog.RarityColors.Comun
		-- franja de rareza
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(5, cardH)
		bar.BackgroundColor3 = cols[2]
		bar.BackgroundTransparency = if unlocked then 0 else 0.6
		bar.BorderSizePixel = 0
		bar.Parent = card
		local icon = UITheme.Text(card, t.Icon or "✦", 28, if unlocked then cols[1] else Color3.fromRGB(120, 120, 130), UDim2.fromOffset(12, 8), UDim2.fromOffset(40, 40), Enum.TextXAlignment.Center)
		icon.TextStrokeTransparency = 1
		local name = UITheme.Text(card, t.Name, 16, Color3.new(1, 1, 1), UDim2.fromOffset(58, 6), UDim2.fromOffset(cardW - 70, 22))
		name.Font = Enum.Font.GothamBlack
		name.TextStrokeTransparency = 1
		name.TextTruncate = Enum.TextTruncate.AtEnd
		if unlocked then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(cols[1], cols[2])
			g.Rotation = 90
			g.Parent = name
		else
			name.TextColor3 = Color3.fromRGB(125, 125, 138)
		end
		local rar = UITheme.Text(card, TitleCatalog.RarityName[t.Rarity] or "", 10, cols[2], UDim2.fromOffset(58, 27), UDim2.fromOffset(cardW - 70, 12))
		rar.TextStrokeTransparency = 1
		local desc = UITheme.Text(card, t.Desc, 11, pal.Muted, UDim2.fromOffset(58, 40), UDim2.fromOffset(cardW - 70, 28))
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextStrokeTransparency = 1
		if unlocked then
			NpcKit.Button(card, theme, if equipped then "✔ Equipado" else "Equipar", UDim2.fromOffset(110, 20), UDim2.fromOffset(cardW - 120, cardH - 26), if equipped then "danger" else "buy", function()
				actionRemote:FireServer("Equip", if equipped then "" else t.Id)
			end)
		elseif t.Kind ~= "Grant" and t.Value then
			local cur = math.min(current(t.Kind), t.Value)
			local txt = string.format("%s / %s %s", thousands(cur), thousands(t.Value), UNIT[t.Kind] or "")
			local back = Instance.new("Frame")
			back.Position = UDim2.fromOffset(58, cardH - 24)
			back.Size = UDim2.fromOffset(cardW - 72, 14)
			back.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
			back.BorderSizePixel = 0
			back.Parent = card
			Instance.new("UICorner", back).CornerRadius = UDim.new(0, 4)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(math.clamp(cur / t.Value, 0, 1), 1)
			fill.BackgroundColor3 = cols[2]
			fill.BorderSizePixel = 0
			fill.Parent = back
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
			local pt = UITheme.Text(back, txt, 10, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
			pt.ZIndex = 3
		else
			local lk = UITheme.Text(card, "🔒 Título especial", 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(58, cardH - 24), UDim2.fromOffset(cardW - 70, 16))
			lk.TextStrokeTransparency = 1
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, 12 + math.ceil(#list / 2) * (cardH + 8))
end

stateRemote.OnClientEvent:Connect(function(s: any)
	state = s
	if gui.Enabled then
		build()
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name == "Titles" then
		if gui.Enabled then
			gui.Enabled = false
		else
			actionRemote:FireServer("State")
			build()
			gui.Enabled = true
		end
	end
end)

actionRemote:FireServer("State")
build()
