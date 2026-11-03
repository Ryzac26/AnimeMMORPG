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

local stateRemote = ClientNet.Get("TiendaState")
local actionRemote = ClientNet.Get("TiendaAction")
local resultRemote = ClientNet.Get("TiendaResult")

local gui = Instance.new("ScreenGui")
gui.Name = "TiendaGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"
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
}
local FALLBACK_TEXT: { [string]: string } = {
	Boost4h = "+50%", Horas3 = "3 H", Horas5 = "5 H", Horas8 = "8 H", Horas12 = "12 H",
	ComboDespegue = "COMBO", ComboMaraton = "COMBO",
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
	local order = 0

	local function section(title: string, sub: string, color: Color3)
		order += 1
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.Size = UDim2.new(1, -8, 0, 34)
		f.BackgroundTransparency = 1
		f.Parent = scroll
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(4, 26)
		bar.Position = UDim2.fromOffset(2, 4)
		bar.BackgroundColor3 = color
		bar.BorderSizePixel = 0
		bar.Parent = f
		Instance.new("UICorner", bar)
		UITheme.Text(f, title, 16, color, UDim2.fromOffset(14, 0), UDim2.fromOffset(300, 18))
		local t = UITheme.Text(f, sub, 11, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(14, 18), UDim2.new(1, -20, 0, 14))
		t.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local function notice(text: string)
		order += 1
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.Size = UDim2.new(1, -8, 0, 44)
		f.BackgroundColor3 = Color3.fromRGB(44, 36, 14)
		f.BorderSizePixel = 0
		f.Parent = scroll
		Instance.new("UICorner", f)
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(255, 212, 94)
		st.Transparency = 0.35
		st.Parent = f
		local t = UITheme.Text(f, text, 12, Color3.fromRGB(255, 232, 160), UDim2.fromOffset(12, 3), UDim2.new(1, -24, 1, -6))
		t.RichText = true
		t.TextWrapped = true
		t.TextYAlignment = Enum.TextYAlignment.Center
	end

	local function card(p: ProductCatalog.Product)
		order += 1
		local info = if state then state.Items[p.Key] else nil
		local bought = if info then info.Bought else 0
		local ok = info ~= nil and info.Ok == true
		local chosen = state ~= nil and state.Path == p.Key
		local accent = ACCENT[p.Kind] or theme.Primary
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.Size = UDim2.new(1, -8, 0, 112)
		f.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
		f.BorderSizePixel = 0
		f.Parent = scroll
		Instance.new("UICorner", f)
		gradient(f, Color3.fromRGB(34, 34, 48), Color3.fromRGB(20, 20, 28), 0)
		local st = Instance.new("UIStroke")
		st.Thickness = if chosen then 2 else 1
		st.Color = if chosen then Color3.fromRGB(255, 212, 94) elseif ok then accent else Color3.fromRGB(70, 70, 85)
		st.Parent = f

		-- caja del icono
		local box = Instance.new("Frame")
		box.Position = UDim2.fromOffset(10, 14)
		box.Size = UDim2.fromOffset(84, 84)
		box.BackgroundColor3 = accent
		box.BorderSizePixel = 0
		box.Parent = f
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
		gradient(box, accent:Lerp(Color3.new(1, 1, 1), 0.25), accent:Lerp(Color3.new(0, 0, 0), 0.45))
		local bst = Instance.new("UIStroke")
		bst.Color = accent:Lerp(Color3.new(1, 1, 1), 0.4)
		bst.Thickness = 2
		bst.Parent = box
		local fb = UITheme.Text(box, FALLBACK_TEXT[p.Key] or "★", 24, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		fb.TextStrokeTransparency = 0.3
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Visible = false
		img.Parent = box
		Instance.new("UICorner", img).CornerRadius = UDim.new(0, 12)
		iconTargets[p.Key] = { Image = img, Fallback = fb }
		loadIcon(p.Key, p.ProductId, p.Icon, Enum.InfoType.Product)

		-- textos
		UITheme.Text(f, p.Name, 16, if ok or chosen then Color3.new(1, 1, 1) else Color3.fromRGB(160, 160, 175), UDim2.fromOffset(106, 8), UDim2.fromOffset(300, 20))
		local d = UITheme.Text(f, p.Desc, 12, Color3.fromRGB(180, 180, 195), UDim2.fromOffset(106, 30), UDim2.fromOffset(290, 30))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		if p.Hours then
			local xp, lvls, capped = ProductCatalog.HoursXp(GB, p.Hours, level(), 0)
			local chip = UITheme.Text(f, string.format("Hoy te daría +%s XP  ≈ %.1f niveles%s", thousands(xp), lvls, if capped then "  (tope por compra)" else ""), 12, Color3.fromRGB(150, 220, 255), UDim2.fromOffset(106, 62), UDim2.fromOffset(300, 16))
			chip.TextWrapped = false
		elseif p.Seconds then
			UITheme.Text(f, "Se suma al tiempo que ya tengas (máx. 12 h)", 12, Color3.fromRGB(150, 235, 170), UDim2.fromOffset(106, 62), UDim2.fromOffset(300, 16))
		end
		local why = if info and info.Why then info.Why else ""
		local line = UITheme.Text(f, string.format("Hoy: %d/%d%s", bought, p.DailyLimit, if why ~= "" then "  ·  🔒 " .. why else ""), 11, if ok or chosen then Color3.fromRGB(150, 150, 165) else Color3.fromRGB(255, 140, 120), UDim2.fromOffset(106, 88), UDim2.fromOffset(300, 16))
		line.TextWrapped = false

		-- precio / comprar
		local original, saved = ProductCatalog.Savings(p)
		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0)
		buy.Position = UDim2.new(1, -10, 0, if saved > 0 then 30 else 38)
		buy.Size = UDim2.fromOffset(104, 38)
		buy.BackgroundColor3 = if ok then Color3.fromRGB(60, 160, 85) else Color3.fromRGB(60, 60, 72)
		buy.TextColor3 = Color3.new(1, 1, 1)
		buy.Font = UITheme.Font
		buy.TextSize = 15
		buy.Text = if ok then p.PriceText else "🔒 " .. p.PriceText
		buy.AutoButtonColor = ok
		buy.Parent = f
		Instance.new("UICorner", buy)
		if ok then
			gradient(buy, Color3.fromRGB(95, 205, 120), Color3.fromRGB(40, 125, 65))
		end
		buy.Activated:Connect(function()
			if ok and actionRemote then
				actionRemote:FireServer("Buy", p.Key)
			end
		end)
		if saved > 0 then
			local old = UITheme.Text(f, string.format("<s>%d R$</s>", original), 12, Color3.fromRGB(160, 160, 175), UDim2.new(1, -114, 0, 72), UDim2.fromOffset(104, 14), Enum.TextXAlignment.Center)
			old.RichText = true
			local tag = Instance.new("TextLabel")
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -10, 0, 8)
			tag.Size = UDim2.fromOffset(104, 18)
			tag.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
			tag.TextColor3 = Color3.fromRGB(60, 35, 0)
			tag.Font = UITheme.Font
			tag.TextSize = 12
			tag.Text = string.format("¡AHORRAS %d R$!", saved)
			tag.Parent = f
			Instance.new("UICorner", tag).CornerRadius = UDim.new(0, 9)
		end
		if chosen then
			local c = Instance.new("TextLabel")
			c.Size = UDim2.fromOffset(84, 16)
			c.Position = UDim2.fromOffset(10, 96)
			c.BackgroundColor3 = Color3.fromRGB(255, 212, 94)
			c.TextColor3 = Color3.fromRGB(60, 35, 0)
			c.Font = UITheme.Font
			c.TextSize = 11
			c.Text = "✔ ELEGIDO HOY"
			c.Parent = f
			Instance.new("UICorner", c).CornerRadius = UDim.new(0, 8)
		end
	end

	section("BOOST DE XP", "+50% de experiencia mientras juegas. Se combina con cualquier paquete.", ACCENT.Boost)
	for _, p in ipairs(ProductCatalog.Products) do
		if p.Lane == "Boost" then
			card(p)
		end
	end
	section("PAQUETES DE HORAS", "Recibes la XP que ganarías jugando esas horas, sin jugarlas (desde nivel 20).", ACCENT.Hours)
	notice('<b>Elige UNO por día:</b> al comprar un paquete o combo, los demás se bloquean hasta mañana. Puedes repetir el que elegiste hasta su límite diario.')
	for _, p in ipairs(ProductCatalog.Products) do
		if p.Lane == "Horas" and p.Kind == "Hours" then
			card(p)
		end
	end
	section("COMBOS", "Boost + paquete en una sola compra, más barato que por separado.", ACCENT.Combo)
	for _, p in ipairs(ProductCatalog.Products) do
		if p.Kind == "Combo" then
			card(p)
		end
	end

	-- PASES de una sola compra
	section("PASES", "Se compran una sola vez y son tuyos para siempre.", ACCENT.Pass)
	for _, ps in ipairs(ProductCatalog.Passes) do
		order += 1
		local has = state ~= nil and state.Passes ~= nil and state.Passes[ps.Key] == true
		local f = Instance.new("Frame")
		f.LayoutOrder = order
		f.Size = UDim2.new(1, -8, 0, 128)
		f.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
		f.BorderSizePixel = 0
		f.Parent = scroll
		Instance.new("UICorner", f)
		gradient(f, Color3.fromRGB(44, 38, 20), Color3.fromRGB(22, 20, 16), 0)
		local st = Instance.new("UIStroke")
		st.Thickness = 2
		st.Color = if has then Color3.fromRGB(111, 220, 127) else Color3.fromRGB(255, 212, 94)
		st.Parent = f
		local box = Instance.new("Frame")
		box.Position = UDim2.fromOffset(10, 22)
		box.Size = UDim2.fromOffset(84, 84)
		box.BackgroundColor3 = ACCENT.Pass
		box.BorderSizePixel = 0
		box.Parent = f
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
		gradient(box, ACCENT.Pass:Lerp(Color3.new(1, 1, 1), 0.25), ACCENT.Pass:Lerp(Color3.new(0, 0, 0), 0.45))
		local fb = UITheme.Text(box, "🧪", 34, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Fit
		img.Visible = false
		img.Parent = box
		Instance.new("UICorner", img).CornerRadius = UDim.new(0, 12)
		iconTargets["pass_" .. ps.Key] = { Image = img, Fallback = fb }
		loadIcon("pass_" .. ps.Key, ps.PassId, ps.Icon, Enum.InfoType.GamePass)
		UITheme.Text(f, ps.Name, 17, Color3.fromRGB(255, 226, 140), UDim2.fromOffset(106, 8), UDim2.fromOffset(300, 22))
		local d = UITheme.Text(f, ps.Desc, 12, Color3.fromRGB(200, 200, 212), UDim2.fromOffset(106, 30), UDim2.fromOffset(290, 30))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		local perks = UITheme.Text(f, "• " .. table.concat(ps.Perks, "\n• "), 11, Color3.fromRGB(150, 235, 170), UDim2.fromOffset(106, 62), UDim2.fromOffset(290, 60))
		perks.TextWrapped = true
		perks.TextYAlignment = Enum.TextYAlignment.Top
		local buy = Instance.new("TextButton")
		buy.AnchorPoint = Vector2.new(1, 0)
		buy.Position = UDim2.new(1, -10, 0, 40)
		buy.Size = UDim2.fromOffset(104, 38)
		buy.BackgroundColor3 = if has then Color3.fromRGB(60, 60, 72) else Color3.fromRGB(60, 160, 85)
		buy.TextColor3 = Color3.new(1, 1, 1)
		buy.Font = UITheme.Font
		buy.TextSize = if has then 13 else 15
		buy.Text = if has then "✔ ADQUIRIDO" else ps.PriceText
		buy.AutoButtonColor = not has
		buy.Parent = f
		Instance.new("UICorner", buy)
		if not has then
			gradient(buy, Color3.fromRGB(95, 205, 120), Color3.fromRGB(40, 125, 65))
		end
		buy.Activated:Connect(function()
			if not has and actionRemote then
				actionRemote:FireServer("BuyPass", ps.Key)
			end
		end)
	end
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	win = UITheme.Frame(gui, theme, UDim2.fromOffset(600, 590), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	WindowDrag.Attach(win, "Tienda", 40, 50)
	UITheme.Text(win, "TIENDA", 22, theme.Primary, UDim2.fromOffset(18, 8), UDim2.fromOffset(200, 28))
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.ZIndex = 30
	close.Parent = win
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	-- barra de estado: boost activo + reinicio
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(14, 44)
	bar.Size = UDim2.fromOffset(572, 28)
	bar.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
	bar.BorderSizePixel = 0
	bar.Parent = win
	Instance.new("UICorner", bar)
	boostPill = UITheme.Text(bar, "", 13, Color3.new(1, 1, 1), UDim2.fromOffset(12, 0), UDim2.fromOffset(380, 28))
	boostPill.RichText = true
	resetLabel = UITheme.Text(bar, "", 12, Color3.fromRGB(170, 170, 185), UDim2.new(1, -180, 0, 0), UDim2.fromOffset(170, 28), Enum.TextXAlignment.Right)
	scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, 80)
	scroll.Size = UDim2.fromOffset(572, 410)
	scroll.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = win
	Instance.new("UICorner", scroll)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	resultLabel = UITheme.Text(win, "", 13, Color3.new(1, 1, 1), UDim2.fromOffset(18, 496), UDim2.fromOffset(564, 36))
	resultLabel.RichText = true
	resultLabel.TextWrapped = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	footer = UITheme.Text(win, "Los precios son en Robux. Los paquetes y combos se bloquean entre sí: elige UNO por día. El boost se combina con todo.", 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(18, 538), UDim2.fromOffset(564, 40))
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
