--!strict
--[[
    DamageRankClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DamageRankClient
    VENTANA "RANKING DE DAÑO": aparece sola cuando golpeas a un jefe mundial, jefe de franja, mini jefe o piedra Metin
    y desaparece cuando el mob muere (o tras 25 s sin golpearlo). No sale con mobs normales.
    Muestra: vida del mob, % de daño por FACCIÓN, ranking de jugadores (top 8), tu puesto y el % de tu GRUPO.
    Se arrastra por la barra de título y se minimiza con el botón "–" (queda solo la barra con tu %).
    Va en el lado derecho, debajo de los chips de evento/boosts, para no taparlos; si estorba, muévela.
    El servidor manda los datos (remote DmgRank). IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MOBILE = Platform.IsMobile()
local theme = UITheme.For(player:GetAttribute("Faction"))

local Remote = ClientNet.Get("DmgRank")

local WIDTH = if MOBILE then 196 else 252
local ROW = if MOBILE then 16 else 19
local TS = if MOBILE then 11 else 13
local KIND = {
	World = { Name = "JEFE MUNDIAL", Color = Color3.fromRGB(255, 205, 70) },
	Boss = { Name = "JEFE DE FRANJA", Color = Color3.fromRGB(230, 70, 70) },
	Mini = { Name = "MINI JEFE", Color = Color3.fromRGB(255, 150, 50) },
	Metin = { Name = "PIEDRA METIN", Color = Color3.fromRGB(180, 120, 255) },
} :: { [string]: { Name: string, Color: Color3 } }
local FACTION_NAME: { [string]: string } = { Saiyan = "Saiyan", Shinobi = "Shinobi", Pirate = "Pirata", Shinigami = "Shinigami" }

local gui = Instance.new("ScreenGui")
gui.Name = "DamageRankGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win = Instance.new("Frame")
win.Name = "Win"
win.AnchorPoint = Vector2.new(1, 0)
win.Position = if MOBILE then UDim2.new(1, -10, 0.3, 0) else UDim2.new(1, -14, 0.27, 0)
win.Size = UDim2.fromOffset(WIDTH, 0)
win.AutomaticSize = Enum.AutomaticSize.Y
win.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
win.BackgroundTransparency = 0.18
win.BorderSizePixel = 0
win.Parent = gui
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 10)
local stroke = UITheme.Border(win, theme, 2)
-- contenedor con la lista (WindowDrag pone su manija directamente en "win", que no debe tener UIListLayout)
local content = Instance.new("Frame")
content.Size = UDim2.new(1, 0, 0, 0)
content.AutomaticSize = Enum.AutomaticSize.Y
content.BackgroundTransparency = 1
content.Parent = win
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = content

-- barra de título
local titleBar = Instance.new("Frame")
titleBar.LayoutOrder = 1
titleBar.Size = UDim2.new(1, 0, 0, if MOBILE then 26 else 30)
titleBar.BackgroundTransparency = 1
titleBar.Parent = content
local titleL = Instance.new("TextLabel")
titleL.BackgroundTransparency = 1
titleL.Position = UDim2.fromOffset(10, 0)
titleL.Size = UDim2.new(1, -44, 1, 0)
titleL.Font = Enum.Font.GothamBlack
titleL.TextSize = TS
titleL.TextXAlignment = Enum.TextXAlignment.Left
titleL.TextTruncate = Enum.TextTruncate.AtEnd
titleL.TextColor3 = Color3.new(1, 1, 1)
titleL.Text = "RANKING DE DAÑO"
titleL.Parent = titleBar
local minBtn = Instance.new("TextButton")
minBtn.AnchorPoint = Vector2.new(1, 0.5)
minBtn.Position = UDim2.new(1, -6, 0.5, 0)
minBtn.Size = UDim2.fromOffset(26, 22)
minBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
minBtn.BorderSizePixel = 0
minBtn.Font = Enum.Font.GothamBlack
minBtn.TextSize = 16
minBtn.TextColor3 = Color3.new(1, 1, 1)
minBtn.Text = "–"
minBtn.ZIndex = 30
minBtn.Parent = titleBar
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)

-- cuerpo
local body = Instance.new("Frame")
body.LayoutOrder = 2
body.Size = UDim2.new(1, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.BackgroundTransparency = 1
body.Parent = content
local bl = Instance.new("UIListLayout")
bl.SortOrder = Enum.SortOrder.LayoutOrder
bl.Padding = UDim.new(0, 2)
bl.Parent = body
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
pad.PaddingBottom = UDim.new(0, 8)
pad.Parent = body

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function text(parent: Instance, t: string, color: Color3, size: number?, bold: boolean?, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, ROW)
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size or TS
	l.TextColor3 = color
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = t
	l.LayoutOrder = nextOrder()
	l.Parent = parent
	return l
end

local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	return out
end

local function factionColor(f: string): Color3
	local ok, c = pcall(function()
		return UITheme.Accent(UITheme.For(f))
	end)
	return if ok and typeof(c) == "Color3" then c else Color3.fromRGB(200, 200, 200)
end

-- barra con etiqueta: nombre a la izquierda, texto a la derecha
local function barRow(frac: number, color: Color3, left: string, right: string, bold: boolean?): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW)
	row.BackgroundColor3 = Color3.fromRGB(30, 30, 42)
	row.BackgroundTransparency = 0.2
	row.BorderSizePixel = 0
	row.LayoutOrder = nextOrder()
	row.Parent = body
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0.02, 1), 1)
	fill.BackgroundColor3 = color
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.Parent = row
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(6, 0)
	l.Size = UDim2.new(0.62, -6, 1, 0)
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = TS - 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	l.Text = left
	l.ZIndex = 2
	l.Parent = row
	local r = Instance.new("TextLabel")
	r.BackgroundTransparency = 1
	r.AnchorPoint = Vector2.new(1, 0)
	r.Position = UDim2.new(1, -6, 0, 0)
	r.Size = UDim2.new(0.38, 0, 1, 0)
	r.Font = Enum.Font.GothamBold
	r.TextSize = TS - 1
	r.TextXAlignment = Enum.TextXAlignment.Right
	r.TextColor3 = Color3.new(1, 1, 1)
	r.TextStrokeTransparency = 0.6
	r.Text = right
	r.ZIndex = 2
	r.Parent = row
	return row
end

type Data = { [string]: any }
local active: { [number]: Data } = {}
local stamp: { [number]: number } = {}
local shownId = 0
local minimized = false

local function pct(part: number, total: number): string
	return string.format("%.1f%%", if total > 0 then part / total * 100 else 0)
end

local function clearBody()
	order = 0
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function render(d: Data)
	local k = KIND[d.kind] or KIND.Boss
	stroke.Color = k.Color
	titleL.Text = string.format("%s · %s", k.Name, tostring(d.name))
	titleL.TextColor3 = k.Color
	local total: number = d.total
	local mine: number = d.mine or 0
	if minimized then
		titleL.Text = string.format("%s · Tú %s", k.Name, pct(mine, total))
	end
	clearBody()
	-- vida del mob
	barRow(d.hp, k.Color, "Vida", string.format("%d%%", math.ceil(d.hp * 100)), true)
	-- facciones
	text(body, "FACCIONES", Color3.fromRGB(170, 170, 190), TS - 2, true)
	local facs: { { any } } = d.factions
	local topF = if facs[1] then (facs[1][2] :: number) else 1
	for i, f in ipairs(facs) do
		if i > 4 then
			break
		end
		local id = tostring(f[1])
		barRow((f[2] :: number) / math.max(1, topF), factionColor(id), FACTION_NAME[id] or id, pct(f[2], total), id == tostring(player:GetAttribute("Faction")))
	end
	-- jugadores
	text(body, "JUGADORES", Color3.fromRGB(170, 170, 190), TS - 2, true)
	local top: { { any } } = d.top
	local topD = if top[1] then (top[1][3] :: number) else 1
	local meShown = false
	for i, e in ipairs(top) do
		local isMe = e[4] == player.UserId
		if isMe then
			meShown = true
		end
		barRow((e[3] :: number) / math.max(1, topD), factionColor(tostring(e[2])), string.format("%d. %s", i, tostring(e[1])), pct(e[3], total), isMe)
	end
	if not meShown and d.pos and d.pos > 0 then
		barRow(mine / math.max(1, topD), factionColor(tostring(player:GetAttribute("Faction"))), string.format("%d. Tú", d.pos), pct(mine, total), true)
	end
	-- resumen
	local party: number = d.party or 0
	local summary = string.format("Tú: %s (%s)", fmt(mine), pct(mine, total))
	if party > 0 then
		summary ..= string.format("  ·  Grupo: %s", pct(party, total))
	end
	text(body, summary, Color3.fromRGB(255, 230, 140), TS - 1, true)
end

local function pickLatest(): number
	local best, bestT = 0, -1
	for id, t in pairs(stamp) do
		if active[id] and t > bestT then
			best, bestT = id, t
		end
	end
	return best
end

local function refresh()
	shownId = pickLatest()
	if shownId == 0 then
		gui.Enabled = false
		return
	end
	if not gui.Enabled then
		gui.Enabled = true
	end
	render(active[shownId])
end

minBtn.MouseButton1Click:Connect(function()
	minimized = not minimized
	body.Visible = not minimized
	minBtn.Text = if minimized then "+" else "–"
	if shownId ~= 0 and active[shownId] then
		render(active[shownId])
	end
end)

if Remote then
	Remote.OnClientEvent:Connect(function(d: any)
		if typeof(d) ~= "table" or typeof(d.id) ~= "number" then
			return
		end
		if d.closed then
			active[d.id] = nil
			stamp[d.id] = nil
		else
			active[d.id] = d
			stamp[d.id] = os.clock()
		end
		refresh()
	end)
end

WindowDrag.Attach(win, "DamageRank", if MOBILE then 26 else 30, 44)

-- si mueres o reapareces, se mantiene; si cambias de personaje no hace falta limpiar nada (el servidor cierra al morir el mob)
