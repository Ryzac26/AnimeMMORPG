--!strict
--[[
    TiendaClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TiendaClient
    TIENDA (botón "Tienda" de la barra de menú). Hoy: Boost de XP y Paquetes de horas. Más adelante: pases, pergaminos, etc.
    Muestra: precio, cuántas compras llevas hoy, boost activo, cuánto falta para el reinicio diario y por qué algo está bloqueado.
    Todo lo decide el servidor (PurchaseService); esta ventana solo muestra y pide. Se mueve arrastrando el título.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
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
local header: TextLabel
local footer: TextLabel
local resultLabel: TextLabel
local state: any = nil
local resultText = ""

local function hms(seconds: number): string
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	return if h > 0 then string.format("%d h %02d min", h, m) else string.format("%d min", m)
end

local function level(): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function updateTexts()
	local boostLeft = if state then state.BoostLeft else 0
	header.Text = if boostLeft > 0
		then string.format('<font color="%s">Boost de XP activo:</font> +50%% · quedan %s', GREEN, hms(boostLeft))
		else string.format('<font color="%s">Sin boost activo</font>', GRAY)
	local resetIn = if state then state.ResetIn else 0
	footer.Text = string.format("Las compras diarias se reinician en %s. Por día solo puedes elegir UNA opción de progreso.", hms(resetIn))
	resultLabel.Text = resultText
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
	updateTexts()
	local order = 0
	local function section(text: string)
		order += 1
		local t = Instance.new("TextLabel")
		t.LayoutOrder = order
		t.Size = UDim2.new(1, -8, 0, 22)
		t.BackgroundTransparency = 1
		t.Font = UITheme.Font
		t.TextSize = 14
		t.TextColor3 = theme.Primary
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Text = text
		t.Parent = scroll
	end
	section("BOOSTS Y PROGRESO")
	for _, p in ipairs(ProductCatalog.Products) do
		order += 1
		local info = if state then state.Items[p.Key] else nil
		local bought = if info then info.Bought else 0
		local ok = info ~= nil and info.Ok == true
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, -8, 0, 92)
		card.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
		card.BorderSizePixel = 0
		card.Parent = scroll
		Instance.new("UICorner", card)
		local st = Instance.new("UIStroke")
		st.Color = if ok then theme.Primary else Color3.fromRGB(70, 70, 85)
		st.Parent = card
		UITheme.Text(card, p.Name, 15, if ok then Color3.new(1, 1, 1) else Color3.fromRGB(150, 150, 165), UDim2.fromOffset(12, 6), UDim2.fromOffset(330, 20))
		local desc = p.Desc
		if p.Kind == "Hours" then
			local lv = level()
			local xp, lvls = ProductCatalog.HoursXp(GB, p.Hours or 0, lv, 0)
			desc = string.format("%s\nAhora: +%s XP (≈ %.2f niveles)", p.Desc, tostring(xp), lvls)
		end
		local d = UITheme.Text(card, desc, 12, Color3.fromRGB(180, 180, 195), UDim2.fromOffset(12, 28), UDim2.fromOffset(330, 40))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
		local why = if info and info.Why then info.Why else ""
		UITheme.Text(card, string.format("Hoy: %d/%d%s", bought, p.DailyLimit, if why ~= "" then "  ·  " .. why else ""), 11, if ok then Color3.fromRGB(150, 150, 165) else Color3.fromRGB(255, 140, 120), UDim2.fromOffset(12, 70), UDim2.fromOffset(340, 16))
		local buy = Instance.new("TextButton")
		buy.Position = UDim2.new(1, -118, 0.5, -20)
		buy.Size = UDim2.fromOffset(106, 40)
		buy.BackgroundColor3 = if ok then Color3.fromRGB(50, 130, 70) else Color3.fromRGB(60, 60, 70)
		buy.TextColor3 = Color3.new(1, 1, 1)
		buy.Font = UITheme.Font
		buy.TextSize = 14
		buy.Text = p.PriceText
		buy.AutoButtonColor = ok
		buy.Parent = card
		Instance.new("UICorner", buy)
		buy.Activated:Connect(function()
			if ok and actionRemote then
				actionRemote:FireServer("Buy", p.Key)
			end
		end)
	end
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	win = UITheme.Frame(gui, theme, UDim2.fromOffset(520, 500), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	WindowDrag.Attach(win, "Tienda", 40, 50)
	UITheme.Text(win, "TIENDA", 20, theme.Primary, UDim2.fromOffset(18, 8), UDim2.fromOffset(200, 26))
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
	header = UITheme.Text(win, "", 13, Color3.new(1, 1, 1), UDim2.fromOffset(18, 44), UDim2.fromOffset(484, 18))
	header.RichText = true
	scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, 70)
	scroll.Size = UDim2.fromOffset(492, 340)
	scroll.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = win
	Instance.new("UICorner", scroll)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = scroll
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	resultLabel = UITheme.Text(win, "", 13, Color3.new(1, 1, 1), UDim2.fromOffset(18, 416), UDim2.fromOffset(484, 36))
	resultLabel.RichText = true
	resultLabel.TextWrapped = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top
	footer = UITheme.Text(win, "", 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(18, 456), UDim2.fromOffset(484, 34))
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
