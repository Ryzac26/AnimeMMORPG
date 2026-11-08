--!strict
--[[
    VipShopClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > VipShopClient
    TIENDA VIP DEL MES: vitrina de 6 artículos cosméticos que cambia cada mes, pagados con Sellos Imperiales (solo suscriptores).
    Arriba explica cómo funciona en 4 pasos. Datos: VipShopState / VipShopAction (VipShopService) + VipShopCatalog.
    Se abre desde el Mayordomo Imperial (pestaña "Tienda VIP") con MenuBus "VipShop". Está en la lista RELOAD de UIReloadClient.
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
local VipShopCatalog: any = require(Modules:WaitForChild("VipShopCatalog", 10))
local TitleCatalog: any = require(Modules:WaitForChild("TitleCatalog", 10))

local stateRemote = ClientNet.Get("VipShopState")
local actionRemote = ClientNet.Get("VipShopAction")

local gui = Instance.new("ScreenGui")
gui.Name = "VipShopGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local state: any = nil

local function txt(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d, h = sec // 86400, (sec % 86400) // 3600
	return if d > 0 then string.format("%d días %d h", d, h) else string.format("%d h", h)
end

local function build()
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local WW, HH = 900, 660
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Tienda VIP del Mes",
		"Solo cosméticos · la vitrina cambia cada mes", "🛍", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "VipShop", 40, 50)
	local top = NpcKit.TOP

	if not state then
		txt(w, "Cargando…", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(300, 20))
		return
	end

	-- CÓMO FUNCIONA (4 pasos)
	txt(w, "¿CÓMO FUNCIONA?", 13, pal.FText, UDim2.fromOffset(18, top - 6), UDim2.fromOffset(300, 18)).Font = Enum.Font.GothamBold
	local E = VipShopCatalog.Earn
	local steps = {
		{ "1", "Suscríbete", "Con la Suscripción Imperial ganas y gastas Sellos." },
		{ "2", "Gana Sellos", string.format("+%d por entrar cada día · +%d por misión diaria · +%d por misión semanal.", E.Login, E.Daily, E.Weekly) },
		{ "3", "Compra", "Elige entre los 6 artículos del mes. Lo que compras es tuyo para siempre." },
		{ "4", "Úsalo", "Títulos: Ajustes → Mis títulos. Muebles: Casa VIP → Decorar. Auras: botón aquí." },
	}
	local stepW = math.floor((WW - 28 - 3 * 8) / 4)
	for i, s in ipairs(steps) do
		local card = NpcKit.Panel(w, theme, UDim2.fromOffset(stepW, 92), UDim2.fromOffset(14 + (i - 1) * (stepW + 8), top + 16), "card")
		local badge = txt(card, s[1], 16, pal.TabOnText, UDim2.fromOffset(8, 8), UDim2.fromOffset(24, 24), Enum.TextXAlignment.Center)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = pal.TabOn
		badge.Font = Enum.Font.GothamBlack
		Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
		txt(card, s[2], 14, pal.Text, UDim2.fromOffset(38, 9), UDim2.fromOffset(stepW - 46, 20)).Font = Enum.Font.GothamBold
		local d = txt(card, s[3], 11, pal.Muted, UDim2.fromOffset(10, 36), UDim2.fromOffset(stepW - 20, 52))
		d.TextWrapped = true
		d.TextYAlignment = Enum.TextYAlignment.Top
	end

	-- sellos y cuenta atrás
	local barY = top + 118
	local bar = NpcKit.Panel(w, theme, UDim2.fromOffset(WW - 28, 40), UDim2.fromOffset(14, barY), "inset")
	txt(bar, string.format("🎖 Tus Sellos Imperiales: %d", state.Points), 18, pal.Accent, UDim2.fromOffset(14, 0), UDim2.fromOffset(380, 40)).Font = Enum.Font.GothamBlack
	txt(bar, "La vitrina cambia en " .. clock(state.SecondsLeft), 13, pal.Muted, UDim2.fromOffset(WW - 28 - 280, 0), UDim2.fromOffset(266, 40), Enum.TextXAlignment.Right)
	local y0 = barY + 48
	if not state.Sub then
		local warn = txt(w, "⚠ Sin Suscripción Imperial activa: puedes mirar la vitrina, pero no ganar ni gastar Sellos.", 13, Color3.fromRGB(255, 190, 90), UDim2.fromOffset(18, y0), UDim2.fromOffset(WW - 36, 20))
		warn.Font = Enum.Font.GothamBold
		y0 += 24
	end

	-- vitrina 3 x 2
	local cols = 3
	local cardW = math.floor((WW - 28 - (cols - 1) * 10) / cols)
	local cardH = math.floor((HH - y0 - 22 - 10) / 2)
	for i, entry in ipairs(state.Items) do
		local it = VipShopCatalog.ById[entry.Id]
		if it then
			local owned = entry.Owned == true
			local cl = TitleCatalog.RarityColors[it.Rarity] or TitleCatalog.RarityColors.Comun
			local col, row = (i - 1) % cols, (i - 1) // cols
			local card = NpcKit.Panel(w, theme, UDim2.fromOffset(cardW, cardH), UDim2.fromOffset(14 + col * (cardW + 10), y0 + row * (cardH + 10)), "card")
			local stripe = Instance.new("Frame")
			stripe.Size = UDim2.new(1, 0, 0, 5)
			stripe.BackgroundColor3 = cl[2]
			stripe.BorderSizePixel = 0
			stripe.Parent = card
			local ico = txt(card, it.Icon, 40, cl[1], UDim2.fromOffset(0, 12), UDim2.fromOffset(cardW, 50), Enum.TextXAlignment.Center)
			ico.Font = Enum.Font.GothamBlack
			local nm = txt(card, it.Name, 14, pal.Text, UDim2.fromOffset(10, 64), UDim2.fromOffset(cardW - 20, 34), Enum.TextXAlignment.Center)
			nm.Font = Enum.Font.GothamBlack
			nm.TextWrapped = true
			local rr = txt(card, (TitleCatalog.RarityName[it.Rarity] or "") .. " · " .. (if it.Kind == "Title" then "Título" elseif it.Kind == "Furniture" then "Mueble" else "Aura"), 11, cl[2], UDim2.fromOffset(10, 98), UDim2.fromOffset(cardW - 20, 14), Enum.TextXAlignment.Center)
			rr.Font = Enum.Font.GothamBold
			local ds = txt(card, it.Desc, 11, pal.Muted, UDim2.fromOffset(12, 116), UDim2.fromOffset(cardW - 24, cardH - 116 - 44), Enum.TextXAlignment.Center)
			ds.TextWrapped = true
			ds.TextYAlignment = Enum.TextYAlignment.Top
			local bw, by = cardW - 24, cardH - 36
			if owned and it.Kind == "Aura" then
				local active = state.Aura == it.Ref
				NpcKit.Button(card, theme, if active then "✔ Activa · Quitar" else "Activar aura", UDim2.fromOffset(bw, 28), UDim2.fromOffset(12, by), if active then "danger" else "buy", function()
					actionRemote:FireServer("Aura", if active then "" else it.Ref)
				end)
			elseif owned then
				NpcKit.Button(card, theme, "✔ Ya es tuyo", UDim2.fromOffset(bw, 28), UDim2.fromOffset(12, by), "neutral", function() end)
			else
				local missing = it.Price - state.Points
				local can = state.Sub and missing <= 0
				local label = if not state.Sub then string.format("🔒 %d Sellos", it.Price) elseif can then string.format("Comprar · %d Sellos", it.Price) else string.format("Faltan %d Sellos", missing)
				NpcKit.Button(card, theme, label, UDim2.fromOffset(bw, 28), UDim2.fromOffset(12, by), if can then "buy" else "neutral", function()
					if can then
						actionRemote:FireServer("Buy", it.Id)
					end
				end)
			end
		end
	end
end

stateRemote.OnClientEvent:Connect(function(s: any)
	if typeof(s) == "table" then
		state = s
		if gui.Enabled then
			build()
		end
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name == "VipShop" then
		actionRemote:FireServer("State")
		build()
		gui.Enabled = true
	end
end)

actionRemote:FireServer("State")
build()
