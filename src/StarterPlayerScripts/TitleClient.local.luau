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
local TitleBadge: any = require(Modules:WaitForChild("TitleBadge", 10))

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
	elseif kind == "Mission" then
		local v = player:GetAttribute("MissionsDone")
		return if typeof(v) == "number" then v else 0
	elseif kind == "Hito" then
		local v = player:GetAttribute("HitosClaimed")
		return if typeof(v) == "number" then v else 0
	end
	return if state then (state.Counters[kind] or 0) else 0
end

local UNIT: { [string]: string } = { Level = "Nv.", Kill = "kills", Metin = "Metin", Boss = "jefes", Min = "min", Dmg = "daño", Forja9 = "piezas +9", Mission = "misiones", Hito = "hitos" }

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

	-- una columna: cada título se muestra como vitrina (las alas, el remolino y el adorno necesitan espacio alrededor de la placa)
	local innerW = WW - sideW - 28 - 8 - 14
	local cardW = innerW - 12
	local PH = 56
	local myFrame = player:GetAttribute("ProfileFrame")
	local curY = 6
	for _, t in ipairs(list) do
		local unlocked = state.Unlocked[t.Id] == true
		local equipped = state.Equipped == t.Id
		local mg = TitleBadge.Margins(t, PH)
		local cols = TitleCatalog.RarityColors[t.Rarity] or TitleCatalog.RarityColors.Comun
		local plaqueBottom = mg.V + PH
		local infoY = plaqueBottom + math.floor(mg.V * 0.85) + 4
		local cardH = infoY + 54
		local card = NpcKit.Panel(scroll, theme, UDim2.fromOffset(cardW, cardH), UDim2.fromOffset(6, curY), "inset")
		curY += cardH + 8
		-- la placa tal como se verá sobre tu personaje (con tu marco de perfil); bloqueada: sin movimiento y oscurecida
		local bw = math.min(TitleBadge.SizeFor(t, PH), cardW - mg.H * 2 - 8)
		local badge = TitleBadge.Build(card, t, {
			Width = bw, Height = PH, Static = not unlocked, Locked = not unlocked,
			Frame = if typeof(myFrame) == "string" and myFrame ~= "" then myFrame else nil,
			Position = UDim2.fromOffset(math.floor((cardW - bw) / 2), mg.V),
		})
		if not unlocked then
			local lock = UITheme.Text(badge, "🔒", 20, Color3.new(1, 1, 1), UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
			lock.ZIndex = 20
			lock.TextStrokeTransparency = 0.4
		end
		local rar = UITheme.Text(card, (TitleCatalog.RarityName[t.Rarity] or "") .. " · " .. t.Cat, 12, cols[2], UDim2.fromOffset(12, infoY), UDim2.fromOffset(cardW - 200, 16))
		rar.TextStrokeTransparency = 1
		rar.Font = Enum.Font.GothamBold
		local desc = UITheme.Text(card, t.Desc, 12, pal.Muted, UDim2.fromOffset(12, infoY + 18), UDim2.fromOffset(cardW - 200, 32))
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		desc.TextStrokeTransparency = 1
		local bx, bwid = cardW - 178, 166
		if unlocked then
			NpcKit.Button(card, theme, if equipped then "✔ Equipado · Quitar" else "Equipar", UDim2.fromOffset(bwid, 32), UDim2.fromOffset(bx, infoY + 8), if equipped then "danger" else "buy", function()
				actionRemote:FireServer("Equip", if equipped then "" else t.Id)
			end)
		elseif t.Kind ~= "Grant" and t.Value then
			local cur = math.min(current(t.Kind), t.Value)
			local txt = string.format("%s / %s %s", thousands(cur), thousands(t.Value), UNIT[t.Kind] or "")
			local back = Instance.new("Frame")
			back.Position = UDim2.fromOffset(bx - 20, infoY + 12)
			back.Size = UDim2.fromOffset(bwid + 20, 22)
			back.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
			back.BorderSizePixel = 0
			back.Parent = card
			Instance.new("UICorner", back).CornerRadius = UDim.new(0, 6)
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(math.clamp(cur / t.Value, 0, 1), 1)
			fill.BackgroundColor3 = cols[2]
			fill.BorderSizePixel = 0
			fill.Parent = back
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
			local pt = UITheme.Text(back, txt, 11, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
			pt.ZIndex = 3
		else
			local lk = UITheme.Text(card, "Título especial: " .. (if t.Cat == "VIP" then "Tienda VIP del Mes" else "se consigue por un logro"), 11, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(bx - 20, infoY + 14), UDim2.fromOffset(bwid + 20, 28))
			lk.TextWrapped = true
			lk.TextStrokeTransparency = 1
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, curY + 8)
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
