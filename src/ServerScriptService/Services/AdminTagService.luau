--!strict
--[[
    AdminTagService (ModuleScript) -> ServerScriptService.Services.AdminTagService
    Cartel de ADMINISTRADOR sobre la cabeza (cargo + nombre, con el color del cargo) para los jugadores de AdminList, y atributo "AdminTitle"
    en el jugador (lo usa DevChatClient para registrar los comandos solo a los admins).
    Ajustes: OFFSET_Y (altura del cartel; el cartel de título equipado va a 3.7, este va encima).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminList = require(ReplicatedStorage.Modules.AdminList)

local OFFSET_Y = 5.6

local function addTag(player: Player, character: Model, entry: AdminList.Entry)
	local head = character:WaitForChild("Head", 10)
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("AdminTag")
	if old then
		old:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "AdminTag"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(220, 44)
	bb.StudsOffsetWorldSpace = Vector3.new(0, OFFSET_Y, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 140
	bb.ResetOnSpawn = false
	bb.Parent = head

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 22)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 17
	title.Text = "✦ " .. string.upper(entry.Title) .. " ✦"
	title.TextColor3 = entry.Color
	title.TextStrokeTransparency = 0.25
	title.TextStrokeColor3 = Color3.fromRGB(20, 12, 4)
	title.Parent = bb

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Position = UDim2.fromOffset(0, 21)
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Enum.Font.GothamBold
	name.TextSize = 15
	name.Text = player.Name
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeTransparency = 0.35
	name.Parent = bb
end

local function setup(player: Player)
	local entry = AdminList.Get(player)
	if not entry then
		return
	end
	player:SetAttribute("AdminTitle", entry.Title)
	print(string.format("[Admin] %s (%s) UserId=%d", player.Name, entry.Title, player.UserId))
	player.CharacterAdded:Connect(function(ch)
		addTag(player, ch, entry)
	end)
	if player.Character then
		task.spawn(addTag, player, player.Character, entry)
	end
end

Players.PlayerAdded:Connect(setup)
for _, p in ipairs(Players:GetPlayers()) do
	setup(p)
end

if RunService:IsStudio() then
	print("[AdminTagService] listo")
end

return {}
