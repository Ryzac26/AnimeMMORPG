--!strict
--[[
    TitleTagClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TitleTagClient
    Dibuja sobre la cabeza de CADA jugador la placa de su título equipado (TitleBadge): marco = su marco de perfil, fondo animado según el título.
    Lee los atributos TitleEquipped y ProfileFrame que publica el servidor (TitleService / MissionService).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local TitleBadge: any = require(Modules:WaitForChild("TitleBadge", 10))
local TitleCatalog: any = require(Modules:WaitForChild("TitleCatalog", 10))

local HEIGHT = 52
local MANY = 10 -- con más jugadores que esto, las placas de los DEMÁS salen sin animación (la tuya siempre animada)

local function refresh(pl: Player)
	local char = pl.Character
	local head = char and char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("TituloPlaca")
	if old then
		old:Destroy()
	end
	local id = pl:GetAttribute("TitleEquipped")
	local def = if typeof(id) == "string" then TitleCatalog.ById[id] else nil
	if not def then
		return
	end
	local frame = pl:GetAttribute("ProfileFrame")
	local w = TitleBadge.SizeFor(def, HEIGHT)
	local mg = TitleBadge.Margins(def, HEIGHT) -- espacio para alas, remolino y adorno (simétrico: la placa queda centrada)
	local bb = Instance.new("BillboardGui")
	bb.Name = "TituloPlaca"
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(w + mg.H * 2, HEIGHT + mg.V * 2)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 3.7, 0)
	bb.MaxDistance = 70
	bb.AlwaysOnTop = false
	bb.ResetOnSpawn = false
	bb.Parent = head
	TitleBadge.Build(bb, def, {
		Width = w, Height = HEIGHT, Position = UDim2.fromOffset(mg.H, mg.V),
		Static = pl ~= Players.LocalPlayer and #Players:GetPlayers() > MANY,
		Frame = if typeof(frame) == "string" and frame ~= "" then frame else nil,
	})
end

local function watch(pl: Player)
	local pending = false
	local function queue()
		if pending then
			return
		end
		pending = true
		task.delay(0.2, function()
			pending = false
			refresh(pl)
		end)
	end
	pl:GetAttributeChangedSignal("TitleEquipped"):Connect(queue)
	pl:GetAttributeChangedSignal("ProfileFrame"):Connect(queue)
	pl.CharacterAdded:Connect(function()
		task.wait(1.2)
		refresh(pl)
	end)
	queue()
end

Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
