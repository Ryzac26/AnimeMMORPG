--!strict
--[[
    AdminTagClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AdminTagClient
    Cartel de ADMINISTRADOR sobre la cabeza de cada admin (placa + emblema + cargo + nombre), visible para todos.
    Lee los atributos AdminTitle / AdminKind que publica AdminTagService en el jugador. Se revisa cada segundo, así que si otro script
    reemplaza la cabeza o limpia el cartel, se vuelve a dibujar solo.
    Ajustes: OFFSET_Y (altura; la placa del título equipado va a 3.7, esta va encima), MAX_DISTANCE.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local AdminKit: any = require(Modules:WaitForChild("AdminKit", 10))
local AdminList: any = require(Modules:WaitForChild("AdminList", 10))

local OFFSET_Y = 6.2
local MAX_DISTANCE = 140
local TAG_NAME = "AdminPlaca"

local function build(pl: Player, head: BasePart)
	local kind = pl:GetAttribute("AdminKind")
	local kit = if kind == "Owner" then AdminKit.Owner else AdminKit.Admin
	local title = pl:GetAttribute("AdminTitle")
	local color = if kind == "Owner" then AdminList.Owner.Color else Color3.fromRGB(110, 210, 255)

	local bb = Instance.new("BillboardGui")
	bb.Name = TAG_NAME
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(340, 112)
	bb.StudsOffsetWorldSpace = Vector3.new(0, OFFSET_Y, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = MAX_DISTANCE
	bb.ResetOnSpawn = false
	bb.Parent = head

	local plate = Instance.new("ImageLabel")
	plate.BackgroundTransparency = 1
	plate.Image = kit.Plate
	plate.Position = UDim2.fromOffset(34, 30)
	plate.Size = UDim2.fromOffset(300, 75)
	plate.ZIndex = 1
	plate.Parent = bb

	local emblem = Instance.new("ImageLabel")
	emblem.BackgroundTransparency = 1
	emblem.Image = kit.Emblem
	emblem.Position = UDim2.fromOffset(0, 2)
	emblem.Size = UDim2.fromOffset(94, 94)
	emblem.ZIndex = 3
	emblem.Parent = bb

	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(104, 40)
	t.Size = UDim2.fromOffset(216, 28)
	t.Font = Enum.Font.GothamBlack
	t.TextSize = 18
	t.TextScaled = false
	t.Text = string.upper(if typeof(title) == "string" then title else "ADMIN")
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.TextStrokeColor3 = Color3.fromRGB(20, 12, 4)
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 4
	t.Parent = bb

	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.fromOffset(104, 66)
	n.Size = UDim2.fromOffset(216, 24)
	n.Font = Enum.Font.GothamBold
	n.TextSize = 17
	n.Text = pl.Name
	n.TextColor3 = Color3.new(1, 1, 1)
	n.TextStrokeTransparency = 0.35
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.ZIndex = 4
	n.Parent = bb
end

local function ensure(pl: Player)
	if pl:GetAttribute("AdminTitle") == nil then
		return
	end
	local char = pl.Character
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local cur = head:FindFirstChild(TAG_NAME)
	if cur and cur:IsA("BillboardGui") and cur.Adornee == head then
		return
	end
	if cur then
		cur:Destroy()
	end
	build(pl, head)
end

task.spawn(function()
	while true do
		for _, pl in ipairs(Players:GetPlayers()) do
			ensure(pl)
		end
		task.wait(1)
	end
end)

print("[AdminTagClient] listo")
