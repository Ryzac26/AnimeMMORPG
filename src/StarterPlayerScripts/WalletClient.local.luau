--!strict
--[[
    WalletClient (LocalScript) -> StarterPlayer > StarterPlayerScripts
    Muestra tu ORO y tus PUNTOS DE FACCIÓN en un panel pequeño. Los datos llegan como atributos del jugador
    (Gold y FactionPoints, los pone WalletService), así que no necesita remotes.
    Para moverlo: cambia POSITION / ANCHOR aquí abajo.
]]
local Players = game:GetService("Players")

local UserInputService = game:GetService("UserInputService")
local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local TOP_Y = if MOBILE then 12 else 72 -- en PC va debajo de los contadores de arriba
local POSITION = UDim2.new(1, -14, 0, TOP_Y) -- esquina superior derecha, justo debajo de los contadores de evento / arena
local ANCHOR = Vector2.new(1, 0)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "WalletHud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "Panel"
frame.AnchorPoint = ANCHOR
frame.Position = POSITION
frame.Size = UDim2.fromOffset(190, 46)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
frame.BackgroundTransparency = 0.3
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = frame

local function makeLabel(y: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(10, y)
	label.Size = UDim2.new(1, -20, 0, 20)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = frame
	return label
end

-- botón para esconder / mostrar el panel de oro y puntos
local hideBtn = Instance.new("TextButton")
hideBtn.Name = "Ocultar"
hideBtn.AnchorPoint = Vector2.new(1, 0)
hideBtn.Position = UDim2.new(1, -14 - 196, 0, TOP_Y)
hideBtn.Size = UDim2.fromOffset(24, 24)
hideBtn.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
hideBtn.BackgroundTransparency = 0.3
hideBtn.TextColor3 = Color3.new(1, 1, 1)
hideBtn.Font = Enum.Font.GothamMedium
hideBtn.TextSize = 13
hideBtn.Text = "▲"
hideBtn.Parent = gui
Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 6)
hideBtn.Activated:Connect(function()
	frame.Visible = not frame.Visible
	hideBtn.Text = if frame.Visible then "▲" else "▼"
end)

local goldLabel = makeLabel(3, Color3.fromRGB(255, 214, 90))
local pointsLabel = makeLabel(23, Color3.fromRGB(150, 200, 255))

-- 1234567 -> "1,234,567"
local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function update()
	local gold = player:GetAttribute("Gold")
	local points = player:GetAttribute("FactionPoints")
	goldLabel.Text = "Oro: " .. withCommas(if typeof(gold) == "number" then gold else 0)
	pointsLabel.Text = "Pts. de facción: " .. withCommas(if typeof(points) == "number" then points else 0)
end

player:GetAttributeChangedSignal("Gold"):Connect(update)
player:GetAttributeChangedSignal("FactionPoints"):Connect(update)
update()
