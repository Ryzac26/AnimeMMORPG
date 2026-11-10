--!strict
--[[
    TiendaClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TiendaClient
    TIENDA (botón "Tienda" de la barra de menú). Hoy: Boost de XP, Paquetes de horas y Combos. Más adelante: pases, pergaminos, etc.
    Muestra: precio, cuántas compras llevas hoy, boost activo, cuánto falta para el reinicio diario y por qué algo está bloqueado.
    Todo lo decide el servidor (PurchaseService); esta ventana solo muestra y pide. Se mueve arrastrando el título.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local GB = require(Modules:WaitForChild("GameBalance", 10))
local ProductCatalog = require(Modules:WaitForChild("ProductCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))

local stateRemote = ClientNet.Get("TiendaState")
local actionRemote = ClientNet.Get("TiendaAction")
local resultRemote = ClientNet.Get("TiendaResult")

local gui = Instance.new("ScreenGui")
gui.Name = "TiendaGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local GREEN, RED, GRAY, GOLD = "#2f9a47", "#c23b3b", "#8a8a96", "#c8960a"
local theme = UITheme.For(player:GetAttribute("Faction"))
local win: Frame
local scroll: ScrollingFrame
local boostPill: TextLabel
local resetLabel: TextLabel
local footer: TextLabel
local resultLabel: TextLabel
local state: any = nil
local resultText = ""

-- color de cada tipo de producto
local ACCENT: { [string]: Color3 } = {
	Boost = Color3.fromRGB(70, 200, 120),
	Hours = Color3.fromRGB(80, 150, 255),
	Combo = Color3.fromRGB(235, 100, 190),
	Pass = Color3.fromRGB(255, 190, 60),
	Item = Color3.fromRGB(165, 105, 235),
	Blessing = Color3.fromRGB(240, 190, 70),
}
local FALLBACK_TEXT: { [string]: string } = {
	Boost4h = "+50%", Horas3 = "3 H", Horas5 = "5 H", Horas8 = "8 H", Horas12 = "12 H",
	ComboDespegue = "COMBO", ComboMaraton = "COMBO", Pergamino1 = "🛡 x1", Pergamino5 = "🛡 x5",
	BlessXp3 = "📖 3H", BlessXp5 = "📖 5H", BlessXp8 = "📖 8H", BlessOro4 = "💰 4H", BlessSuerte4 = "🔎 4H", BlessTotal4 = "✨ 4H",
}

-- Iconos: el de cada Developer Product (el que subiste en Creator Hub) o ProductCatalog.Icon si lo pones a mano.
local iconCache: { [string]: string | boolean } = {} -- clave -> "rbxassetid://..." | false (no tiene)
local iconTargets: { [string]: { Image: ImageLabel, Fallback: TextLabel } } = {}

local function applyIcon(key: string)
	local target = iconTargets[key]
	local v = iconCache[key]
	if target and typeof(v) == "string" and target.Image.Parent then
		target.Image.Image = v
		target.Image.Visible = true
		target.Fallback.Visible = false
	end
end

-- key: clave de caché ("Boost4h", "pass_Belt"...) · assetId: ID del Developer Product o del Game Pass · infoType: Product | GamePass
local failedInfo: { string } = {}
local function loadIcon(key: string, assetId: number, override: string?, infoType: Enum.InfoType)
	if iconCache[key] ~= nil then
		applyIcon(key)
		return
	end
	if override and override ~= "" then
		iconCache[key] = override
		applyIcon(key)
		return
	end
	if assetId <= 0 then
		iconCache[key] = false
		return
	end
	iconCache[key] = false -- evita pedirlo dos veces mientras llega
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(assetId, infoType)
		end)
		if ok and typeof(info) == "table" then
			local id = (info :: any).IconImageAssetId
			if typeof(id) == "number" and id > 0 then
				iconCache[key] = "rbxassetid://" .. tostring(math.floor(id))
				applyIcon(key)
			else
				-- Roblox a veces no devuelve el icono de un Developer Product: pon ProductCatalog.Icon = "rbxassetid://ID" (imagen subida como Decal/Imagen)
				warn(string.format("[TiendaClient] %s (id %d): Roblox no devolvió icono (IconImageAssetId = %s). Usa el campo Icon del catálogo.", key, assetId, tostring(id)))
			end
		else
			-- varios productos fallan a la vez cuando los ids no existen en este universo: un solo aviso resumen
			failedInfo[#failedInfo + 1] = string.format("%s (%d)", key, assetId)
			if #failedInfo == 1 then
				task.delay(4, function()
					warn(string.format("[TiendaClient] %d productos sin información en este universo (¿ids de otro lugar o sin publicar?): %s", #failedInfo, table.concat(failedInfo, ", ")))
				end)
			end
		end
	end)
end

local function hms(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	return if h > 0 then string.format("%d h %02d min", h, m) else string.format("%d min", m)
end

local function thousands(n: number): string
	local str = tostring(math.floor(n))
	local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return out
end

local function level(): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function updateTexts()
	local boostLeft = if state then state.BoostLeft else 0
	boostPill.Text = if boostLeft > 0
		then string.format('<font color="%s"><b>BOOST ACTIVO  +50%% XP</b></font>  ·  quedan %s', GREEN, hms(boostLeft))
		else string.format('<font color="%s">Sin boost activo</font>', GRAY)
	local resetIn = if state then state.ResetIn else 0
	resetLabel.Text = string.format("Reinicio diario en %s", hms(resetIn))
	resultLabel.Text = resultText
end

local function gradient(obj: GuiObject, a: Color3, b: Color3, rot: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(a, b)
	g.Rotation = rot or 90
	g.Parent = obj
end

local activeTab = "Progreso"
local tabNote: TextLabel
local tabButtons: { [string]: TextButton } = {}
local grid: UIGridLayout

local TABS = {
	{ Id = "Progreso", Text = "⚡ Progreso", Note = "Boost de XP (+50%), paquetes de horas y combos. Elige UNO por día entre paquetes y combos; el boost se combina con todo." },
	{ Id = "Objetos", Text = "🎒 Objetos", Note = "Pergaminos de Protección: tu equipo no baja ni se rompe al fallar +7, +8 o +9. Llegan directo a tu mochila." },
	{ Id = "Gremio", Text = "🏰 Bendiciones", Note = "Bendición para TODA tu facción en este servidor mientras haya jugadores de ella. Si el servidor se cierra con gente dentro, te devolvemos el tiempo sobrante como bendición personal." },
	{ Id = "Pases", Text = "👑 Pases", Note = "Se compran una sola vez y son tuyos para siempre." },
}

local function render()
	if not win or not gui.Enabled then
		return
	end
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	table.clear(iconTargets)
	updateTexts()
	local pal = NpcKit.Palette(theme)
	for _, t in ipairs(TABS) do
		if t.Id == activeTab then
			tabNote.Text = t.Note
		end
	end
	local order = 0

	local function iconBox(parent: Instance, pos: UDim2, size: number, accent: Color3, fbText: string, fbSize: number, cacheKey: string, assetId: number, override: string?, infoType: Enum.InfoType)
		local box = Instance.new("Frame")
		box.Position = pos
		box.Size = UDim2.fromOffset(size, size)
		box.BackgroundColor3 = accent
		box.BorderSizePixel = 0
		box.Parent = parent
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
		gradient(box, accent:Lerp(Color3.new(1, 1, 1), 0.25), accent:Lerp(Color3.new(0, 0, 0), 0.45))
		local bst = Instance.new("UIStroke")
		bst.Color = accent:Lerp(Color3.new(1, 1, 1), 0.4)
		bst.Thickness = 2
		bst.Parent = box
		local fb = UITheme.Text(box, fbText, fbSize, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		fb.TextStrokeTransparency = 0.3
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Visible = false
		img.Parent = box
		Instance.new("UICorner", img).CornerRadius = UDim.new(0, 12)
		iconTargets[cacheKey] = { Image = img, Fallback = fb }
		loadIcon(cacheKey, assetId, override, infoType)
	end

	local function textLine(parent: Instance, text: string, size: number, color: Color3, pos: UDim2, dim: UDim2, wrap: boolean?): TextLabel
		local t = UITheme.Text(parent, text, size, color, pos, dim, Enum.TextXAlignment.Center)
		t.TextStrokeTransparency = 1
		t.TextWrapped = wrap == true
		t.TextYAlignment = Enum.TextYAlignment.Top
		t.RichText = true
		return t
	end

	local function card(p: ProductCatalog.Product)
		order += 1
		local info = if state then state.Items[p.Key] else nil
		local bought = if info then info.Bought else 0
		local ok = info ~= nil and info.Ok == true
		local chosen = state ~= nil and state.Path == p.Key
		local accent = ACCENT[p.Kind] or theme.Primary
		local f = NpcKit.Panel(scroll, theme, UDim2.fromOffset(170, 238), UDim2.fromOffset(0, 0), "card")
		f.LayoutOrder = order
		local st = f:FindFirstChildOfClass("UIStroke")
		if st and chosen then
			st.Color = Color3.fromRGB(255, 212, 94)
			st.Thickness = 2.5
			st.Transparency = 0
		elseif st and ok then
			st.Color = accent
			st.Transparency = 0.2
		end
		iconBox(f, UDim2.fromOffset(45, 14), 80, accent, FALLBACK_TEXT[p.Key] or "★", 22, p.Key, p.ProductId, p.Icon, Enum.InfoType.Product)
		local nameColor = if ok or chosen then pal.Text else pal.Muted
		textLine(f, p.Name, 13, nameColor, UDim2.fromOffset(6, 98), UDim2.new(1, -12, 0, 34), true)
		textLine(f, p.Desc, 10, pal.Muted, UDim2.fromOffset(8, 132), UDim2.new(1, -16, 0, 40), true)
		local extra = ""
		if p.Hours then
			local xp, lvls, capped = ProductCatalog.HoursXp(GB, p.Hours, level(), 0)
			extra = string.format("Hoy: +%s XP ≈ %.1f niv.%s", thousands(xp), lvls, if capped then " (tope)" else "")
		elseif p.Items then
			extra = "Directo a tu mochila"
		elseif p.BlessGroup then
			local g = ProductCatalog.BlessGroups[p.BlessGroup]
			extra = if g then g.Short else ""
		elseif p.Seconds then
			extra = "Se suma al tiempo (máx. 12 h)"
		end
		textLine(f, extra, 10, Color3.fromRGB(110, 190, 235), UDim2.fromOffset(6, 174), UDim2.new(1, -12, 0, 14))
		local why = if info and info.Why then info.Why else ""
		local line = textLine(f, string.format("Hoy %d/%d%s", bought, p.DailyLimit, if why ~= "" then "  🔒 " .. why else ""), 10, if ok or chosen then pal.Muted else Color3.fromRGB(235, 120, 100), UDim2.fromOffset(6, 189), UDim2.new(1, -12, 0, 14))
		line.TextTruncate = Enum.TextTruncate.AtEnd
		local original, saved = ProductCatalog.Savings(p)
		local buy = NpcKit.Button(f, theme, if ok then p.PriceText else "🔒 " .. p.PriceText, UDim2.new(1, -20, 0, 28), UDim2.fromOffset(10, 204), if ok then "buy" else "neutral", function()
			if ok and actionRemote then
				actionRemote:FireServer("Buy", p.Key)
			end
		end)
		buy.AutoButtonColor = ok
		if saved > 0 then
			NpcKit.Chip(f, string.format("¡AHORRAS %d R$!", saved), Color3.fromRGB(255, 200, 60), UDim2.fromOffset(6, 5), UDim2.fromOffset(86, 16)).TextSize = 10
			local old = UITheme.Text(f, string.format("<s>%d R$</s>", original), 11, pal.Muted, UDim2.fromOffset(100, 6), UDim2.fromOffset(64, 14), Enum.TextXAlignment.Right)
			old.RichText = true
			old.TextStrokeTransparency = 1
		end
		if chosen then
			NpcKit.Chip(f, "✔ ELEGIDO HOY", Color3.fromRGB(255, 212, 94), UDim2.new(1, -92, 0, 5), UDim2.fromOffset(86, 16)).TextSize = 10
		end
	end

	local function passCard(ps: any)
		order += 1
		local has = state ~= nil and state.Passes ~= nil and state.Passes[ps.Key] == true
		local f = NpcKit.Panel(scroll, theme, UDim2.fromOffset(280, 250), UDim2.fromOffset(0, 0), "plate")
		f.LayoutOrder = order
		local st = f:FindFirstChildOfClass("UIStroke")
		if st then
			st.Color = if has then Color3.fromRGB(111, 220, 127) else Color3.fromRGB(255, 212, 94)
			st.Transparency = 0
			st.Thickness = 2
		end
		iconBox(f, UDim2.fromOffset(12, 14), 72, ACCENT.Pass, "👑", 30, "pass_" .. ps.Key, ps.PassId, ps.Icon, Enum.InfoType.GamePass)
		local nm = UITheme.Text(f, ps.Name, 15, if has then Color3.fromRGB(150, 235, 170) else Color3.fromRGB(255, 214, 110), UDim2.fromOffset(96, 12), UDim2.new(1, -106, 0, 40))
		nm.TextWrapped = true
		nm.TextYAlignment = Enum.TextYAlignment.Top
		nm.TextStrokeTransparency = 1
		local d = UITheme.Text(f, ps.Desc, 11, pal.Muted, UDim2.fromOffset(96, 52), UDim2.new(1, -106, 0, 44))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		d.TextStrokeTransparency = 1
		local perks = UITheme.Text(f, "• " .. table.concat(ps.Perks, "\n• "), 11, Color3.fromRGB(110, 200, 140), UDim2.fromOffset(14, 100), UDim2.new(1, -28, 0, 100))
		perks.TextWrapped = true
		perks.TextYAlignment = Enum.TextYAlignment.Top
		perks.TextStrokeTransparency = 1
		local capLeft = workspace:GetAttribute("VipHousesLeft")
		if ps.Key == "VipHouse" and typeof(capLeft) == "number" and not has then
			local cl = UITheme.Text(f, string.format("🏠 Quedan %d de %d casas", capLeft, (workspace:GetAttribute("VipHousesCap") :: any) or 0), 12, if capLeft > 0 then Color3.fromRGB(255, 214, 110) else Color3.fromRGB(235, 120, 100), UDim2.fromOffset(14, 188), UDim2.new(1, -28, 0, 16))
			cl.TextStrokeTransparency = 1
		end
		NpcKit.Button(f, theme, if has then "✔ ADQUIRIDO" else ps.PriceText, UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 206), if has then "neutral" else "buy", function()
			if not has and actionRemote then
				actionRemote:FireServer("BuyPass", ps.Key)
			end
		end).AutoButtonColor = not has
	end

	if activeTab == "Progreso" then
		grid.CellSize = UDim2.fromOffset(170, 238)
		for _, kind in ipairs({ "Boost", "Hours", "Combo" }) do
			for _, p in ipairs(ProductCatalog.Products) do
				if p.Kind == kind and (kind ~= "Hours" or p.Lane == "Horas") then
					card(p)
				end
			end
		end
	elseif activeTab == "Gremio" then
		grid.CellSize = UDim2.fromOffset(170, 238)
		for _, p in ipairs(ProductCatalog.Products) do
			if p.Kind == "Blessing" then
				card(p)
			end
		end
	elseif activeTab == "Objetos" then
		grid.CellSize = UDim2.fromOffset(170, 238)
		for _, p in ipairs(ProductCatalog.Products) do
			if p.Kind == "Item" then
				card(p)
			end
		end
	else
		grid.CellSize = UDim2.fromOffset(280, 250)
		for _, ps in ipairs(ProductCatalog.Passes) do
			passCard(ps)
		end
	end
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	local W = 760
	win = NpcKit.Window(gui, theme, UDim2.fromOffset(W, 610), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Tienda", "Boosts, paquetes, objetos y pases", "🛒", function()
		gui.Enabled = false
	end)
	WindowDrag.Attach(win, "Tienda", 40, 50)
	-- columna de secciones (como los pasillos de la tienda)
	table.clear(tabButtons)
	for i, t in ipairs(TABS) do
		tabButtons[t.Id] = NpcKit.Tab(win, theme, t.Text, UDim2.fromOffset(126, 40), UDim2.fromOffset(14, 96 + (i - 1) * 48), t.Id == activeTab, function()
			activeTab = t.Id
			build()
			render()
		end)
	end
	-- barra de estado: boost activo + reinicio
	local bar = NpcKit.Panel(win, theme, UDim2.fromOffset(594, 28), UDim2.fromOffset(154, 94), "inset")
	local pal = NpcKit.Palette(theme)
	boostPill = UITheme.Text(bar, "", 13, pal.Text, UDim2.fromOffset(12, 0), UDim2.fromOffset(390, 28))
	boostPill.RichText = true
	boostPill.TextStrokeTransparency = 1
	resetLabel = UITheme.Text(bar, "", 12, pal.Muted, UDim2.new(1, -190, 0, 0), UDim2.fromOffset(180, 28), Enum.TextXAlignment.Right)
	resetLabel.TextStrokeTransparency = 1
	tabNote = UITheme.Text(win, "", 11, pal.FMuted, UDim2.fromOffset(156, 126), UDim2.fromOffset(590, 30))
	tabNote.TextWrapped = true
	tabNote.TextYAlignment = Enum.TextYAlignment.Top
	tabNote.TextStrokeTransparency = 1
	local showcase = NpcKit.Panel(win, theme, UDim2.fromOffset(594, 380), UDim2.fromOffset(154, 158), "inset")
	scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(0, 0)
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = showcase
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingBottom, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = scroll
	grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(170, 238)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	resultLabel = UITheme.Text(win, "", 13, pal.Text, UDim2.fromOffset(154, 542), UDim2.fromOffset(594, 22))
	resultLabel.RichText = true
	resultLabel.TextWrapped = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	footer = UITheme.Text(win, "Precios en Robux. El boost se combina con todo.", 11, pal.FMuted, UDim2.fromOffset(154, 574), UDim2.fromOffset(594, 24))
	footer.TextWrapped = true
	footer.TextYAlignment = Enum.TextYAlignment.Top
end

local function open()
	local ok, err = pcall(function()
		if not win then
			build()
		end
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			resultText = ""
			if actionRemote then
				actionRemote:FireServer("State")
			end
			render()
		end
	end)
	if not ok then
		warn("[TiendaClient] No se pudo abrir la tienda: " .. tostring(err))
	end
end

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(s: any)
		state = s
		render()
	end)
end
if resultRemote then
	resultRemote.OnClientEvent:Connect(function(ok: any, text: any)
		resultText = string.format('<font color="%s"><b>%s</b></font>', if ok == true then GREEN else RED, tostring(text))
		render()
	end)
end
player:GetAttributeChangedSignal("Level"):Connect(render)

MenuBus.Event:Connect(function(name: string)
	if name == "Tienda" then
		open()
	end
end)

-- cuenta atrás visual del boost y del reinicio (el servidor manda el estado exacto; esto solo resta 1 s por segundo)
task.spawn(function()
	while true do
		task.wait(1)
		if state and gui.Enabled then
			state.BoostLeft = math.max(0, (state.BoostLeft or 0) - (if (state.BoostLeft or 0) > 0 then 1 else 0))
			state.ResetIn = math.max(0, (state.ResetIn or 0) - 1)
			updateTexts() -- solo los textos: reconstruir las tarjetas cada segundo haría perder clics
		end
	end
end)

print("[TiendaClient] listo")
