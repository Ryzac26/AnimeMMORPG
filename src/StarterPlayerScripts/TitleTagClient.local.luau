--!strict
--[[
    TitleTagClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TitleTagClient
    Dibuja sobre la cabeza de CADA jugador la placa de su título equipado (TitleBadge): marco = su marco de perfil, fondo animado según el título.
    Lee los atributos TitleEquipped y ProfileFrame que publica el servidor (TitleService / MissionService).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local TitleBadge: any = require(Modules:WaitForChild("TitleBadge", 10))
local TitleCatalog: any = require(Modules:WaitForChild("TitleCatalog", 10))

local HEIGHT = 52
local TITLE_FULL_DIST = 14 -- hasta esta distancia de la cámara la placa va a tamaño completo; más lejos se encoge (si no, tapa al personaje)
local TITLE_MIN_SCALE = 0.32
local titleScales: { [UIScale]: BasePart } = {}
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
	local root = Instance.new("Frame")
	root.Name = "Raiz"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = bb
	local us = Instance.new("UIScale")
	us.Parent = root
	titleScales[us] = head
	TitleBadge.Build(root, def, {
		Width = w, Height = HEIGHT, Position = UDim2.fromOffset(mg.H, mg.V),
		Static = pl ~= Players.LocalPlayer and #Players:GetPlayers() > MANY,
		Frame = if typeof(frame) == "string" and frame ~= "" then frame else nil,
	})
end

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cp = cam.CFrame.Position
	for us, head in pairs(titleScales) do
		if us.Parent == nil or head.Parent == nil then
			titleScales[us] = nil
		else
			us.Scale = math.clamp(TITLE_FULL_DIST / math.max((head.Position - cp).Magnitude, 1), TITLE_MIN_SCALE, 1)
		end
	end
end)

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

---------------------------------------------------------------------
-- CARTEL DE ADMINISTRADOR (placa + emblema + cargo + nombre) sobre la cabeza de cada admin.
-- Va dentro de este script (que ya corre seguro) y se revisa cada segundo: si otro script cambia la cabeza o borra el cartel, se vuelve a crear.
-- Decide quién es admin con AdminList (la misma lista que usa el servidor). Ajustes: OFFSET_Y (altura), MAX_DISTANCE.
---------------------------------------------------------------------
do
	local okKit, AdminKit: any = pcall(function()
		return require(Modules:WaitForChild("AdminKit", 10))
	end)
	local okList, AdminList: any = pcall(function()
		return require(Modules:WaitForChild("AdminList", 10))
	end)
	if not (okKit and okList) then
		warn("[TitleTagClient] No se pudo cargar AdminKit/AdminList: no habrá cartel de admin")
	else
		local OFFSET_Y = 6.2
		local MAX_DISTANCE = 140
		local TAG_NAME = "AdminPlaca"
		local FULL_DIST = 14 -- hasta esta distancia de la cámara el cartel va a tamaño completo; más lejos se encoge (si no, tapa al personaje)
		local MIN_SCALE = 0.32
		local scales: { [UIScale]: BasePart } = {}

		local function build(pl: Player, head: BasePart)
			local entry = AdminList.Get(pl)
			local kind = if entry then entry.Kind else "Admin"
			local kit = if kind == "Owner" then AdminKit.Owner else AdminKit.Admin
			local title = if entry then entry.Title else "Admin"
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

			-- todo el cartel va dentro de un marco con UIScale para poder encogerlo según la distancia
			local root = Instance.new("Frame")
			root.Name = "Raiz"
			root.BackgroundTransparency = 1
			root.AnchorPoint = Vector2.new(0.5, 0.5)
			root.Position = UDim2.fromScale(0.5, 0.5)
			root.Size = UDim2.fromScale(1, 1)
			root.Parent = bb
			local us = Instance.new("UIScale")
			us.Parent = root
			scales[us] = head

			local plate = Instance.new("ImageLabel")
			plate.BackgroundTransparency = 1
			plate.Image = kit.Plate
			plate.Position = UDim2.fromOffset(34, 30)
			plate.Size = UDim2.fromOffset(300, 75)
			plate.ZIndex = 1
			plate.Parent = root

			local emblem = Instance.new("ImageLabel")
			emblem.BackgroundTransparency = 1
			emblem.Image = kit.Emblem
			emblem.Position = UDim2.fromOffset(0, 2)
			emblem.Size = UDim2.fromOffset(94, 94)
			emblem.ZIndex = 3
			emblem.Parent = root

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
			t.Parent = root

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
			n.Parent = root
		end

		RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			if not cam then
				return
			end
			local cp = cam.CFrame.Position
			for us, head in pairs(scales) do
				if us.Parent == nil or head.Parent == nil then
					scales[us] = nil
				else
					local d = (head.Position - cp).Magnitude
					us.Scale = math.clamp(FULL_DIST / math.max(d, 1), MIN_SCALE, 1)
				end
			end
		end)

		local function ensure(pl: Player)
			if AdminList.Get(pl) == nil then -- la lista es la misma en cliente y servidor: no depende de atributos
				return
			end
			local char = pl.Character
			local head = char and char:FindFirstChild("Head")
			if not head or not head:IsA("BasePart") then
				return
			end
			-- interruptor del Fundador en OFF (atributo AdminCmds que pone DevCommands): el cartel desaparece
			if pl:GetAttribute("AdminCmds") == false then
				local old = head:FindFirstChild(TAG_NAME)
				if old then
					old:Destroy()
				end
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


		print("[TitleTagClient] cartel de admin listo")
	end
end
