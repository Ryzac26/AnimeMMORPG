--!strict
--[[
    GlobalRankClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > GlobalRankClient
    Parte tuya del ranking global (GlobalRankService):
      - Aviso "TU PUESTO: #N" arriba de la pantalla cuando estás cerca del cartel del ranking (solo lo ves tú).
      - Ventana con el Top 100 completo (se abre con E en el cartel) y tu puesto arriba.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local me = Players.LocalPlayer
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local remote = ClientNet.Get("GlobalRank")
if not remote then
	return
end

local BOARD_TAG = "GlobalRankBoard"
local NEAR = 90
local FACTION_NAME: { [string]: string } = { Saiyan = "Élite", Shinobi = "Sigilo", Pirate = "Navegantes", Shinigami = "Espíritu" }
local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 190, 90),
	Shinobi = Color3.fromRGB(130, 230, 160),
	Pirate = Color3.fromRGB(255, 120, 110),
	Shinigami = Color3.fromRGB(160, 170, 255),
}
local GOLD = Color3.fromRGB(255, 205, 80)
local MEDAL = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(214, 220, 232), Color3.fromRGB(214, 144, 96) }

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local gui = Instance.new("ScreenGui")
gui.Name = "GlobalRankGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = me:WaitForChild("PlayerGui")

local function addCorner(o: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function text(parent: Instance, t: string, size: number, color: Color3, font: Enum.Font, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = t
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font
	l.Position = pos
	l.Size = dim
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = parent
	return l
end

---------------------------------------------------------------------
-- aviso "Tu puesto"
---------------------------------------------------------------------
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 14)
banner.Size = UDim2.fromOffset(420, 48)
banner.BackgroundColor3 = Color3.fromRGB(20, 22, 36)
banner.BackgroundTransparency = 0.08
banner.BorderSizePixel = 0
banner.Visible = false
banner.Parent = gui
addCorner(banner, 10)
local bStroke = Instance.new("UIStroke")
bStroke.Color = GOLD
bStroke.Thickness = 2
bStroke.Parent = banner
local bText = text(banner, "", 20, Color3.new(1, 1, 1), Enum.Font.GothamBlack, UDim2.fromOffset(14, 0), UDim2.new(1, -28, 1, 0), Enum.TextXAlignment.Center)

local meData: any = nil

local function meLine(d: any): string
	if not d then
		return "Cargando tu puesto..."
	end
	local f = if typeof(d.Faction) == "string" then (FACTION_NAME[d.Faction] or d.Faction) else "-"
	local lv = if typeof(d.Level) == "number" then d.Level else 0
	if typeof(d.Rank) == "number" then
		return string.format("TU PUESTO: #%s  ·  Nv. %d  ·  %s", fmt(d.Rank), lv, f)
	end
	return string.format("TU PUESTO: fuera del Top %s  ·  Nv. %d  ·  %s", fmt(if typeof(d.Max) == "number" then d.Max else 3000), lv, f)
end

local function refreshBanner()
	bText.Text = meLine(meData)
end

local function nearBoard(): boolean
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	for _, p in ipairs(CollectionService:GetTagged(BOARD_TAG)) do
		if p:IsA("BasePart") and (p.Position - root.Position).Magnitude <= NEAR then
			return true
		end
	end
	return false
end

task.spawn(function()
	while true do
		banner.Visible = nearBoard()
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------
-- ventana Top 100
---------------------------------------------------------------------
local win = Instance.new("Frame")
win.AnchorPoint = Vector2.new(0.5, 0.5)
win.Position = UDim2.fromScale(0.5, 0.5)
win.Size = UDim2.fromOffset(620, 540)
win.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
win.BorderSizePixel = 0
win.Visible = false
win.Parent = gui
addCorner(win, 12)
local wStroke = Instance.new("UIStroke")
wStroke.Color = GOLD
wStroke.Thickness = 2
wStroke.Parent = win

text(win, "🏆 RANKING GLOBAL · TOP 100", 22, GOLD, Enum.Font.GothamBlack, UDim2.fromOffset(16, 8), UDim2.new(1, -70, 0, 30))
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(32, 32)
close.Position = UDim2.new(1, -44, 0, 8)
close.BackgroundColor3 = Color3.fromRGB(190, 56, 62)
close.Text = "X"
close.Font = Enum.Font.GothamBlack
close.TextSize = 18
close.TextColor3 = Color3.new(1, 1, 1)
close.Parent = win
addCorner(close, 8)
close.Activated:Connect(function()
	win.Visible = false
end)

local meCard = Instance.new("Frame")
meCard.Position = UDim2.fromOffset(14, 46)
meCard.Size = UDim2.new(1, -28, 0, 40)
meCard.BackgroundColor3 = Color3.fromRGB(40, 36, 20)
meCard.BorderSizePixel = 0
meCard.Parent = win
addCorner(meCard, 8)
local meLabel = text(meCard, "", 18, Color3.fromRGB(255, 232, 160), Enum.Font.GothamBlack, UDim2.fromOffset(12, 0), UDim2.new(1, -24, 1, 0), Enum.TextXAlignment.Center)

local headers = Instance.new("Frame")
headers.Position = UDim2.fromOffset(14, 92)
headers.Size = UDim2.new(1, -28, 0, 22)
headers.BackgroundTransparency = 1
headers.Parent = win
local hc = Color3.fromRGB(170, 176, 200)
text(headers, "#", 14, hc, Enum.Font.GothamBold, UDim2.fromOffset(8, 0), UDim2.fromOffset(50, 22))
text(headers, "JUGADOR", 14, hc, Enum.Font.GothamBold, UDim2.fromOffset(64, 0), UDim2.fromOffset(240, 22))
text(headers, "FACCIÓN", 14, hc, Enum.Font.GothamBold, UDim2.fromOffset(320, 0), UDim2.fromOffset(150, 22))
text(headers, "NIVEL", 14, hc, Enum.Font.GothamBold, UDim2.new(1, -110, 0, 0), UDim2.fromOffset(100, 22), Enum.TextXAlignment.Right)

local list = Instance.new("ScrollingFrame")
list.Position = UDim2.fromOffset(14, 118)
list.Size = UDim2.new(1, -28, 1, -132)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 6
list.CanvasSize = UDim2.fromOffset(0, 0)
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Parent = win
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 3)
layout.Parent = list

local function fill(data: any)
	for _, ch in ipairs(list:GetChildren()) do
		if not ch:IsA("UIListLayout") then
			ch:Destroy()
		end
	end
	local top = if typeof(data) == "table" and typeof(data.Top) == "table" then data.Top else {}
	for i, e in ipairs(top :: { any }) do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 34)
		row.BackgroundColor3 = if e.UserId == me.UserId then Color3.fromRGB(58, 52, 26) elseif i % 2 == 0 then Color3.fromRGB(28, 32, 50) else Color3.fromRGB(22, 25, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = list
		addCorner(row, 6)
		local col = if i <= 3 then MEDAL[i] else Color3.fromRGB(235, 238, 245)
		text(row, tostring(i), 18, if i <= 3 then MEDAL[i] else hc, Enum.Font.GothamBlack, UDim2.fromOffset(8, 0), UDim2.fromOffset(50, 34))
		text(row, tostring(e.Name), 17, col, Enum.Font.GothamBold, UDim2.fromOffset(64, 0), UDim2.fromOffset(250, 34))
		text(row, string.upper(FACTION_NAME[e.Faction] or tostring(e.Faction)), 14, FACTION_COLOR[e.Faction] or Color3.new(1, 1, 1), Enum.Font.GothamBlack, UDim2.fromOffset(320, 0), UDim2.fromOffset(160, 34))
		text(row, "Nv. " .. tostring(e.Level), 17, GOLD, Enum.Font.GothamBlack, UDim2.new(1, -118, 0, 0), UDim2.fromOffset(110, 34), Enum.TextXAlignment.Right)
	end
	if #top == 0 then
		text(list, "Todavía no hay datos del ranking. Vuelve en un minuto.", 16, hc, Enum.Font.Gotham, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 30), Enum.TextXAlignment.Center)
	end
end

remote.OnClientEvent:Connect(function(kind: any, data: any)
	if kind == "Me" then
		meData = data
		refreshBanner()
		meLabel.Text = meLine(meData)
	elseif kind == "Open" then
		if typeof(data) == "table" then
			meData = data.Me
			refreshBanner()
			meLabel.Text = meLine(meData)
			fill(data)
		end
		win.Visible = true
	end
end)

refreshBanner()
remote:FireServer("Sync")
