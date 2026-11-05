--!strict
--[[
    BoostClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BoostClient
    Cuadro "BOOST ACTIVO" (esquina superior derecha, debajo de los carteles de evento/arena). Lista TODOS los boosts activos del
    jugador (hoy: Hermandad de franja, +% de XP). Se minimiza/maximiza con su botón y se oculta solo si no hay ningún boost.
    Datos: remote "Boosts" (BoostService) -> { { Name, Text, XpPct } }.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local remote = ReplicatedStorage:WaitForChild("Remotes", 10):WaitForChild("Boosts", 10) :: RemoteEvent
local theme = UITheme.For(player:GetAttribute("Faction"))

local gui = Instance.new("ScreenGui")
gui.Name = "BoostGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 3
gui.Parent = player:WaitForChild("PlayerGui", 10)

-- columna que apila los cuadros: BOOST ACTIVO y, debajo, BENDICIÓN DE FACCIÓN (solo cuando hay una activa)
local stack = Instance.new("Frame")
stack.AnchorPoint = Vector2.new(1, 0)
stack.Position = UDim2.new(1, -14, 0, 122) -- justo debajo de los chips de Evento / Vidas de arena
stack.Size = UDim2.fromOffset(240, 10)
stack.AutomaticSize = Enum.AutomaticSize.Y
stack.BackgroundTransparency = 1
stack.Parent = gui
local stackList = Instance.new("UIListLayout")
stackList.Padding = UDim.new(0, 6)
stackList.SortOrder = Enum.SortOrder.LayoutOrder
stackList.Parent = stack
if require(script.Parent:WaitForChild("Platform", 10)).IsMobile() then
	-- en celular: más pequeño y pegado al chip de evento (no tapa los botones)
	stack.Position = UDim2.new(1, -12, 0, 42)
	Instance.new("UIScale", stack).Scale = 0.6
end
local holder = Instance.new("Frame")
holder.LayoutOrder = 1
holder.Size = UDim2.fromOffset(240, 10)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = stack
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 3)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = holder

local head = Instance.new("TextButton")
head.LayoutOrder = 0
head.Size = UDim2.fromOffset(240, 26)
head.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
head.BackgroundTransparency = 0.2
head.Font = UITheme.Font
head.TextSize = 13
head.TextColor3 = Color3.fromRGB(120, 235, 150)
head.Parent = holder
Instance.new("UICorner", head).CornerRadius = UDim.new(0, 8)
UITheme.Border(head, theme, 1)

local body = Instance.new("Frame")
body.LayoutOrder = 1
body.Size = UDim2.fromOffset(240, 10)
body.AutomaticSize = Enum.AutomaticSize.Y
body.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
body.BackgroundTransparency = 0.25
body.Parent = holder
Instance.new("UICorner", body).CornerRadius = UDim.new(0, 8)
local bodyList = Instance.new("UIListLayout")
bodyList.Padding = UDim.new(0, 2)
bodyList.Parent = body
local bodyPad = Instance.new("UIPadding")
bodyPad.PaddingTop, bodyPad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
bodyPad.PaddingLeft, bodyPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
bodyPad.Parent = body

local expanded = true
local count = 0
local function refreshHead()
	head.Text = string.format("BOOST ACTIVO (%d)  %s", count, if expanded then "▲" else "▼")
	body.Visible = expanded
end
head.Activated:Connect(function()
	expanded = not expanded
	refreshHead()
end)

local function line(text: string, size: number, color: Color3, order: number, font: Enum.Font?)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = font or Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = body
end

remote.OnClientEvent:Connect(function(boosts: any)
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	count = 0
	if typeof(boosts) == "table" then
		for i, b in ipairs(boosts :: { any }) do
			count += 1
			line(string.format("+%d%% XP  ·  %s", math.floor((b.XpPct or 0) * 100 + 0.5), tostring(b.Name)), 13, Color3.fromRGB(120, 235, 150), i * 2 - 1, Enum.Font.GothamBold)
			line(tostring(b.Text), 11, Color3.fromRGB(190, 190, 205), i * 2)
		end
	end
	holder.Visible = count > 0
	refreshHead()
end)
refreshHead()

---------------------------------------------------------------------
-- BENDICIÓN DE FACCIÓN: cuadro aparte, solo cuando hay alguna activa (atributo "BlessJson" de BlessingService)
---------------------------------------------------------------------
local HttpService = game:GetService("HttpService")
local bless = Instance.new("Frame")
bless.LayoutOrder = 2
bless.Size = UDim2.fromOffset(240, 10)
bless.AutomaticSize = Enum.AutomaticSize.Y
bless.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
bless.BackgroundTransparency = 0.2
bless.Visible = false
bless.Parent = stack
Instance.new("UICorner", bless).CornerRadius = UDim.new(0, 8)
UITheme.Border(bless, theme, 1)
local blessList = Instance.new("UIListLayout")
blessList.Padding = UDim.new(0, 2)
blessList.SortOrder = Enum.SortOrder.LayoutOrder
blessList.Parent = bless
local blessPad = Instance.new("UIPadding")
blessPad.PaddingTop, blessPad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
blessPad.PaddingLeft, blessPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
blessPad.Parent = bless

local entries: { any } = {}
local receivedAt = os.clock()
local rows: { { Time: TextLabel, Left: number } } = {}

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function blessLabel(text: string, size: number, color: Color3, order: number, bold: boolean): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = bless
	return l
end

local function rebuildBless()
	for _, c in ipairs(bless:GetChildren()) do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	table.clear(rows)
	local raw = player:GetAttribute("BlessJson")
	entries = {}
	if typeof(raw) == "string" and raw ~= "" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok and typeof(data) == "table" then
			entries = data
		end
	end
	receivedAt = os.clock()
	bless.Visible = #entries > 0
	if #entries == 0 then
		return
	end
	blessLabel("✨ BENDICIÓN DE FACCIÓN", 12, Color3.fromRGB(255, 214, 110), 0, true)
	for i, e in ipairs(entries) do
		blessLabel(string.format("%s%s", tostring(e.n), if e.p then " (devuelta)" else ""), 12, Color3.fromRGB(240, 240, 250), i * 3 - 2, true)
		local sub = if e.p then tostring(e.s) else string.format("%s · de %s", tostring(e.s), tostring(e.by or "?"))
		blessLabel(sub, 10, Color3.fromRGB(190, 190, 205), i * 3 - 1, false)
		local t = blessLabel(fmt(e.l), 13, Color3.fromRGB(120, 235, 150), i * 3, true)
		table.insert(rows, { Time = t, Left = e.l })
	end
end

player:GetAttributeChangedSignal("BlessJson"):Connect(rebuildBless)
rebuildBless()
task.spawn(function()
	while true do
		task.wait(1)
		if bless.Visible then
			local el = os.clock() - receivedAt
			for _, r in ipairs(rows) do
				r.Time.Text = fmt(r.Left - el)
			end
		end
	end
end)
