--!strict
--[[
    AdminSwitchClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AdminSwitchClient
    Panel del FUNDADOR (solo lo ve el dueño del juego): dos interruptores ON/OFF para los comandos de prueba.
      - "Mis comandos"        -> tus propios comandos (/nivel, /mob, /item...)
      - "Comandos de admins"  -> los de los administradores (zCrulax y los que añadas en AdminList)
    En OFF ese grupo juega normal. El servidor (DevCommands) es quien decide: este panel solo manda la orden y muestra el estado.
    Puedes arrastrar el panel desde su título.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local me = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
if not Modules then
	return
end
local okList, AdminList: any = pcall(function()
	return require(Modules:WaitForChild("AdminList", 10))
end)
if not okList then
	return
end
local entry = AdminList.Get(me)
if not entry or entry.Kind ~= "Owner" then
	return
end

local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local remote = ClientNet.Get("AdminSwitch")
if not remote then
	return
end

local GOLD = Color3.fromRGB(255, 205, 80)
local ON_COLOR = Color3.fromRGB(46, 170, 96)
local OFF_COLOR = Color3.fromRGB(190, 56, 62)

local gui = Instance.new("ScreenGui")
gui.Name = "PanelFundador"
gui.ResetOnSpawn = false
gui.DisplayOrder = 60
gui.Parent = me:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(206, 104)
panel.Position = UDim2.new(0, 10, 0.5, -52)
panel.BackgroundColor3 = Color3.fromRGB(22, 18, 14)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = panel
local stroke = Instance.new("UIStroke")
stroke.Color = GOLD
stroke.Thickness = 1.5
stroke.Parent = panel

local head = Instance.new("TextLabel")
head.Size = UDim2.new(1, 0, 0, 24)
head.BackgroundTransparency = 1
head.Font = Enum.Font.GothamBlack
head.TextSize = 13
head.Text = "PANEL DEL FUNDADOR"
head.TextColor3 = GOLD
head.Parent = panel

local buttons: { [string]: TextButton } = {}
local labels: { [string]: string } = { Owner = "Mis comandos", Admin = "Comandos de admins" }
local function makeButton(key: string, y: number)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -20, 0, 32)
	b.Position = UDim2.fromOffset(10, y)
	b.BackgroundColor3 = ON_COLOR
	b.AutoButtonColor = true
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = labels[key] .. ": ..."
	b.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	b.Activated:Connect(function()
		remote:FireServer(key)
	end)
	buttons[key] = b
end
makeButton("Owner", 28)
makeButton("Admin", 64)

local function show(key: string, on: any)
	local b = buttons[key]
	if not b then
		return
	end
	local isOn = on ~= false
	b.Text = labels[key] .. ": " .. (if isOn then "ON" else "OFF")
	b.BackgroundColor3 = if isOn then ON_COLOR else OFF_COLOR
end

remote.OnClientEvent:Connect(function(ownerOn: any, adminOn: any)
	show("Owner", ownerOn)
	show("Admin", adminOn)
end)
remote:FireServer("Sync")

-- arrastrar desde el título
local dragging = false
local dragStart = Vector2.zero
local startPos = panel.Position
head.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = Vector2.new(input.Position.X, input.Position.Y)
		startPos = panel.Position
	end
end)
UserInputService.InputChanged:Connect(function(input: InputObject)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local d = Vector2.new(input.Position.X, input.Position.Y) - dragStart
		panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)
