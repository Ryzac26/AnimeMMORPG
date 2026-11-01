--!strict
--[[
    ShrineClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ShrineClient
    Panel de SANTUARIOS (lado derecho): aparece en la arena con el evento abierto y muestra, para cada santuario,
    quién lo tiene, el % de captura en curso y el bonus que da. Abajo: tus bonus activos.
    Cuando tu facción captura (o pierde) un santuario sale una tarjeta con el % ganado.
    Lee los atributos que publica ArenaStyler: Workspace "Shrine_<Id>" = "dueño|retador|progreso%" y jugador "ShrineBuffs".
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local MOBILE = require(script.Parent:WaitForChild("Platform", 10)).IsMobile()
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local theme = UITheme.For(player:GetAttribute("Faction"))
player:GetAttributeChangedSignal("Faction"):Connect(function()
	theme = UITheme.For(player:GetAttribute("Faction"))
end)

type Def = { Id: string, Name: string, Text: string, Color: Color3 }
local DEFS: { Def } = {
	{ Id = "Fuerza", Name = "Fuerza", Text = "+8% daño", Color = Color3.fromRGB(255, 90, 60) },
	{ Id = "Vigor", Name = "Vigor", Text = "+10% vida máx.", Color = Color3.fromRGB(90, 230, 120) },
	{ Id = "Aliento", Name = "Aliento", Text = "+40% regen. energía", Color = Color3.fromRGB(90, 180, 255) },
	{ Id = "Fortuna", Name = "Fortuna", Text = "+15% XP", Color = Color3.fromRGB(255, 215, 90) },
}
local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 138, 31),
	Shinobi = Color3.fromRGB(96, 160, 86),
	Pirate = Color3.fromRGB(60, 120, 190),
	Shinigami = Color3.fromRGB(140, 110, 220),
}

local gui = Instance.new("ScreenGui")
gui.Name = "ShrineGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui", 10)

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -14, 0.45, 0) -- derecha, entre los chips/Boost (arriba) y el AutoFarm (abajo)
panel.Size = UDim2.fromOffset(240, 10)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = theme.Dark
panel.BackgroundTransparency = 0.15
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
UITheme.Border(panel, theme, 1)
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local function label(parent: Instance, text: string, size: number, color: Color3, order: number, h: number): TextLabel
	local t = Instance.new("TextLabel")
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, h)
	t.BackgroundTransparency = 1
	t.Font = UITheme.Font
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = parent
	return t
end

local header = label(panel, "SANTUARIOS", 13, theme.Primary, 1, 16)

type Row = { Status: TextLabel, Fill: Frame }
local rows: { [string]: Row } = {}
for i, d in ipairs(DEFS) do
	local r = Instance.new("Frame")
	r.LayoutOrder = 1 + i
	r.Size = UDim2.new(1, 0, 0, 34)
	r.BackgroundTransparency = 1
	r.Parent = panel
	local name = label(r, d.Name .. "  " .. d.Text, 12, d.Color, 1, 15)
	name.Size = UDim2.new(0.62, 0, 0, 15)
	local status = label(r, "Libre", 12, Color3.fromRGB(200, 200, 205), 2, 15)
	status.Size = UDim2.new(0.38, 0, 0, 15)
	status.Position = UDim2.new(0.62, 0, 0, 0)
	status.TextXAlignment = Enum.TextXAlignment.Right
	local bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 0, 0, 21)
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	bar.BorderSizePixel = 0
	bar.Parent = r
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = d.Color
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
	rows[d.Id] = { Status = status, Fill = fill }
end

local mine = label(panel, "Tus bonus: ninguno", 12, Color3.fromRGB(235, 235, 240), 10, 30)

-- CELULAR: el panel arranca plegado (solo el título) y se abre al tocarlo; se pliega solo a los 6 s
if MOBILE then
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 116)
	panel.Size = UDim2.fromOffset(230, 10)
	local collapsed = true
	local token = 0
	local function setCollapsed(c: boolean)
		collapsed = c
		header.Text = if c then "SANTUARIOS  ▸" else "SANTUARIOS  ▾"
		for _, ch in ipairs(panel:GetChildren()) do
			if ch:IsA("GuiObject") and ch ~= header then
				ch.Visible = not c
			end
		end
	end
	local tap = Instance.new("TextButton")
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.Parent = header
	header.Size = UDim2.new(1, 0, 0, 26)
	tap.Activated:Connect(function()
		setCollapsed(not collapsed)
		token += 1
		local my = token
		if not collapsed then
			task.delay(6, function()
				if my == token then
					setCollapsed(true)
				end
			end)
		end
	end)
	setCollapsed(true)
end
mine.TextWrapped = true
mine.TextTruncate = Enum.TextTruncate.None
mine.TextYAlignment = Enum.TextYAlignment.Top

-- tarjeta de captura
local toast = Instance.new("Frame")
toast.AnchorPoint = if MOBILE then Vector2.new(0.5, 0) else Vector2.new(0.5, 1)
toast.Position = if MOBILE then UDim2.new(0.5, 0, 0, -120) else UDim2.new(0.5, 0, 1, 90) -- PC: sobre la barra de habilidades; celular: arriba al centro
toast.Size = UDim2.fromOffset(340, 64)
toast.BackgroundColor3 = theme.Dark
toast.BackgroundTransparency = 0.1
toast.Parent = gui
Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)
local toastStroke = Instance.new("UIStroke")
toastStroke.Thickness = 2
toastStroke.Parent = toast
local toastTitle = label(toast, "", 16, Color3.new(1, 1, 1), 1, 24)
toastTitle.Position = UDim2.fromOffset(12, 8)
toastTitle.Size = UDim2.new(1, -24, 0, 24)
toastTitle.TextXAlignment = Enum.TextXAlignment.Center
local toastSub = label(toast, "", 14, Color3.fromRGB(230, 230, 235), 2, 20)
toastSub.Position = UDim2.fromOffset(12, 34)
toastSub.Size = UDim2.new(1, -24, 0, 22)
toastSub.TextXAlignment = Enum.TextXAlignment.Center
local toastToken = 0
local function showToast(title: string, sub: string, color: Color3)
	toastToken += 1
	local my = toastToken
	toastTitle.Text = title
	toastSub.Text = sub
	toastStroke.Color = color
	TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = if MOBILE then UDim2.new(0.5, 0, 0, 150) else UDim2.new(0.5, 0, 1, -190) }):Play()
	task.delay(6, function()
		if my == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.3), { Position = if MOBILE then UDim2.new(0.5, 0, 0, -120) else UDim2.new(0.5, 0, 1, 90) }):Play()
		end
	end)
end

local function parse(v: any): (string?, string?, number, number)
	if typeof(v) ~= "string" then
		return nil, nil, 0, 0
	end
	local o, c, p, h = string.match(v, "^([^|]*)|([^|]*)|(%d+)|(%d+)$")
	return (if o ~= "-" then o else nil), (if c ~= "-" then c else nil), tonumber(p) or 0, tonumber(h) or 0
end

local lastOwner: { [string]: string? } = {}
for _, d in ipairs(DEFS) do
	local attr = "Shrine_" .. d.Id
	local function refresh()
		local o, c, p, hp = parse(Workspace:GetAttribute(attr))
		local row = rows[d.Id]
		if o and hp > 0 then
			row.Status.Text = o .. " · campo " .. hp .. "%"
			row.Status.TextColor3 = FACTION_COLOR[o] or Color3.new(1, 1, 1)
			row.Fill.BackgroundColor3 = FACTION_COLOR[o] or d.Color
			row.Fill.Size = UDim2.fromScale(math.clamp(hp / 100, 0, 1), 1)
		elseif c and p > 0 then
			row.Status.Text = c .. " " .. p .. "%"
			row.Status.TextColor3 = FACTION_COLOR[c] or Color3.new(1, 1, 1)
			row.Fill.BackgroundColor3 = FACTION_COLOR[c] or d.Color
			row.Fill.Size = UDim2.fromScale(math.clamp(p / 100, 0, 1), 1)
		elseif o then
			row.Status.Text = o
			row.Status.TextColor3 = FACTION_COLOR[o] or Color3.new(1, 1, 1)
			row.Fill.BackgroundColor3 = FACTION_COLOR[o] or d.Color
			row.Fill.Size = UDim2.fromScale(1, 1)
		else
			row.Status.Text = "Libre"
			row.Status.TextColor3 = Color3.fromRGB(200, 200, 205)
			row.Fill.Size = UDim2.fromScale(0, 1)
		end
		local f = player:GetAttribute("Faction")
		if o ~= lastOwner[d.Id] then
			local before = lastOwner[d.Id]
			lastOwner[d.Id] = o
			if typeof(f) == "string" and Workspace:GetAttribute("EventState") == "Open" then
				if o == f then
					showToast("¡SANTUARIO DE " .. string.upper(d.Name) .. " CAPTURADO!", "Tu facción gana " .. d.Text .. " dentro de la arena. Defiende el campo", d.Color)
				elseif before == f and o == nil then
					showToast("¡Rompieron tu campo de " .. d.Name .. "!", "Perdiste " .. d.Text .. ". Recupéralo capturándolo de nuevo", Color3.fromRGB(255, 90, 90))
				elseif before ~= nil and before ~= f and o == nil then
					showToast("Campo de " .. d.Name .. " roto", "Está libre: ¡captúralo para tu facción!", d.Color)
				end
			end
		end
	end
	Workspace:GetAttributeChangedSignal(attr):Connect(refresh)
	refresh()
end

local function refreshMine()
	local b = player:GetAttribute("ShrineBuffs")
	if typeof(b) ~= "string" or b == "" then
		mine.Text = "Tus bonus: ninguno (captura santuarios para tu facción)"
		return
	end
	local parts: { string } = {}
	for _, d in ipairs(DEFS) do
		if string.find("," .. b .. ",", "," .. d.Id .. ",", 1, true) then
			table.insert(parts, d.Text .. " " .. d.Name)
		end
	end
	mine.Text = "Tus bonus activos: " .. table.concat(parts, " · ")
end
player:GetAttributeChangedSignal("ShrineBuffs"):Connect(refreshMine)
refreshMine()

-- visible solo dentro de la arena con el evento abierto
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.3 then
		return
	end
	acc = 0
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local show = false
	if root and root:IsA("BasePart") and Workspace:GetAttribute("EventState") == "Open" then
		local p = root.Position
		show = math.abs(p.X) <= 780 and math.abs(p.Z) <= 780
	end
	panel.Visible = show
end)
