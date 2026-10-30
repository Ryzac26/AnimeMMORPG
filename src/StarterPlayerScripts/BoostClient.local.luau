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

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(1, 0)
holder.Position = UDim2.new(1, -14, 0, 122) -- justo debajo de los chips de Evento / Vidas de arena
holder.Size = UDim2.fromOffset(240, 10)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Visible = false
holder.Parent = gui
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
