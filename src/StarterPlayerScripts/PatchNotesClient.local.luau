--!strict
--[[
    PatchNotesClient (LocalScript) -> StarterPlayer.StarterPlayerScripts
    Al entrar al juego muestra el cartel de NOVEDADES (texto de ReplicatedStorage.Modules.PatchNotes) con botón para cerrar.
    Tecla N = volver a abrirlo. Los jugadores no pueden cambiar el contenido (se edita solo desde Studio).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Notes = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PatchNotes"))
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "PatchNotes"
gui.ResetOnSpawn = false
gui.DisplayOrder = 200
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Active = true
dim.Parent = gui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.new(0.5, 0, 0.7, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
panel.BorderSizePixel = 0
panel.Parent = dim
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local limit = Instance.new("UISizeConstraint")
limit.MinSize = Vector2.new(320, 300)
limit.MaxSize = Vector2.new(760, 640)
limit.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(165, 140, 255)
stroke.Thickness = 2
stroke.Parent = panel

local head = Instance.new("TextLabel")
head.BackgroundTransparency = 1
head.Position = UDim2.fromOffset(20, 12)
head.Size = UDim2.new(1, -90, 0, 34)
head.Font = Enum.Font.GothamBlack
head.TextSize = 24
head.TextXAlignment = Enum.TextXAlignment.Left
head.TextColor3 = Color3.fromRGB(235, 228, 255)
head.Text = "NOVEDADES"
head.Parent = panel

local close = Instance.new("TextButton")
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -14, 0, 12)
close.Size = UDim2.fromOffset(60, 34)
close.BackgroundColor3 = Color3.fromRGB(150, 60, 70)
close.Font = Enum.Font.GothamBold
close.TextSize = 16
close.TextColor3 = Color3.new(1, 1, 1)
close.Text = "Cerrar"
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(16, 58)
scroll.Size = UDim2.new(1, -32, 1, -112)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.Parent = panel
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 6)
list.Parent = scroll

local function label(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font, order: number)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, -8, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.LayoutOrder = order
	l.Parent = parent
end

-- Cada versión es un bloque que se abre/cierra al tocar su título. La más nueva viene abierta; las anteriores quedan
-- guardadas debajo (hay que bajar con la rueda) para que el jugador pueda leerlas cuando quiera.
for index, entry in ipairs(Notes) do
	local block = Instance.new("Frame")
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, -8, 0, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.LayoutOrder = index
	block.Parent = scroll
	local blockList = Instance.new("UIListLayout")
	blockList.Padding = UDim.new(0, 4)
	blockList.SortOrder = Enum.SortOrder.LayoutOrder
	blockList.Parent = block

	local open = index == 1
	local headerBtn = Instance.new("TextButton")
	headerBtn.LayoutOrder = 0
	headerBtn.Size = UDim2.new(1, 0, 0, 32)
	headerBtn.BackgroundColor3 = Color3.fromRGB(38, 32, 62)
	headerBtn.BorderSizePixel = 0
	headerBtn.Font = Enum.Font.GothamBold
	headerBtn.TextSize = if index == 1 then 17 else 15
	headerBtn.TextColor3 = Color3.fromRGB(205, 190, 255)
	headerBtn.TextXAlignment = Enum.TextXAlignment.Left
	headerBtn.Parent = block
	Instance.new("UICorner", headerBtn).CornerRadius = UDim.new(0, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.Parent = headerBtn

	local body = Instance.new("Frame")
	body.LayoutOrder = 1
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Visible = open
	body.Parent = block
	local bodyList = Instance.new("UIListLayout")
	bodyList.Padding = UDim.new(0, 4)
	bodyList.SortOrder = Enum.SortOrder.LayoutOrder
	bodyList.Parent = body

	local function refreshHeader()
		headerBtn.Text = string.format("%s  v%s  ·  %s  ·  %s", if body.Visible then "▼" else "▶", entry.Version, entry.Date, entry.Title)
	end
	refreshHeader()
	headerBtn.Activated:Connect(function()
		body.Visible = not body.Visible
		refreshHeader()
	end)

	local order = 0
	for _, sec in ipairs(entry.Sections) do
		order += 1
		label(body, sec.Header, 16, Color3.fromRGB(150, 230, 255), Enum.Font.GothamBold, order)
		for _, item in ipairs(sec.Items) do
			order += 1
			label(body, "•  " .. item, 14, Color3.fromRGB(225, 225, 235), Enum.Font.Gotham, order)
		end
	end
end

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -10)
hint.Size = UDim2.new(1, -32, 0, 24)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.Gotham
hint.TextSize = 13
hint.TextColor3 = Color3.fromRGB(150, 150, 170)
hint.Text = "Toca una versión para abrirla o cerrarla  ·  Pulsa N para volver a ver las novedades"
hint.Parent = panel

close.Activated:Connect(function()
	gui.Enabled = false
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.N then
		gui.Enabled = not gui.Enabled
	end
end)

task.delay(3, function()
	gui.Enabled = true
end)
