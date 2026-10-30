--!strict
--[[
    CharacterClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > CharacterClient
    PERFIL DEL PERSONAJE (tecla C), inspirado en la ventana de equipo de Metin2:
      - Centro: miniatura 3D del personaje con TODO lo que lleva puesto (se gira arrastrando)
      - Ranuras alrededor: Casco, Armadura, Arma, Escudo, Zapatos, Cinturón | Collar, Pendientes, Brazalete, Anillo, 2 accesorios
      - Fila inferior: Capa, Alas, Montura, Traje (skin)
      - Derecha: estadísticas (nivel, vida, energía, daño, defensa, velocidad, bonus del equipo)
    Clic en una ranura ocupada = desequipar (vuelve a la mochila).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local GB = require(Modules:WaitForChild("GameBalance", 10))
local PlayerClass = require(Modules:WaitForChild("PlayerClass", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "CharacterGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local theme = UITheme.For(player:GetAttribute("Faction"))
local win: Frame
local viewport: ViewportFrame
local statsLabel: TextLabel
local title: TextLabel
local slotButtons: { [string]: TextButton } = {}
local angle = 0
local dragging = false
local clone: Model? = nil

local LEFT = { "Casco", "Armadura", "Arma", "Escudo", "Zapatos", "Cinturon" }
local RIGHT = { "Collar", "Pendientes", "Brazalete", "Anillo", "Accesorio1", "Accesorio2" }
local BOTTOM = { "Capa", "Alas", "Montura", "Traje" }

local function makeSlot(slotName: string, pos: UDim2, size: UDim2)
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
	b.Text = ""
	b.AutoButtonColor = true
	b.Parent = win
	Instance.new("UICorner", b)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = theme.Secondary
	st.Parent = b
	local label = UITheme.Text(b, ItemCatalog.SlotDisplay[slotName] or slotName, 11, Color3.fromRGB(140, 140, 155), UDim2.fromScale(0, 0.15), UDim2.fromScale(1, 0.7), Enum.TextXAlignment.Center)
	label.Name = "Label"
	label.TextWrapped = true
	b.Activated:Connect(function()
		if Store.Equip[slotName] then
			Store.Action("Unequip", slotName)
		end
	end)
	slotButtons[slotName] = b
end

local function refreshSlots()
	for name, b in pairs(slotButtons) do
		local id = Store.Equip[name]
		local item = id and ItemCatalog.Items[id]
		local label = b:FindFirstChild("Label") :: TextLabel
		local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		if item then
			local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
			label.Text = item.Name
			label.TextColor3 = col
			stroke.Color = col
			b.BackgroundColor3 = col:Lerp(Color3.new(0, 0, 0), 0.75)
		else
			label.Text = ItemCatalog.SlotDisplay[name] or name
			label.TextColor3 = Color3.fromRGB(140, 140, 155)
			stroke.Color = theme.Secondary
			b.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
		end
	end
end

local ROLE_INFO: { [string]: { Desc: string, Pasivas: { string } } } = {
	Tanque = { Desc = "Primera línea: aguanta, llama la atención de los enemigos y protege al grupo.", Pasivas = {
		"Piel de acero: -2% de daño recibido por cada enemigo extra cerca (máx -8%).",
		"Presencia: los enemigos a 30 studs lo prefieren a él (65% cada 2 s).",
		"Voluntad: 1 vez cada 120 s sobrevive a un golpe mortal con 10% de vida y 2 s de inmunidad." } },
	Guerrero = { Desc = "Combatiente cuerpo a cuerpo equilibrado: daño sostenido y resistencia.", Pasivas = {
		"Sed de combate: +2% de daño por golpe seguido al mismo enemigo (máx +10%).",
		"Segundo aire: al matar un enemigo recupera 2% de su vida máxima.",
		"Furia: con menos de 35% de vida hace +10% de daño." } },
	Asesino = { Desc = "Daño explosivo y movilidad: golpea por la espalda y remata.", Pasivas = {
		"Puñalada: +12% de daño si golpea por la espalda.",
		"Evasión: 6% de probabilidad de esquivar un golpe.",
		"Remate: +10% de daño a enemigos con menos de 30% de vida." } },
	Tirador = { Desc = "Daño a distancia: mantiene la posición y castiga desde lejos.", Pasivas = {
		"Ojo de halcón: +8% de daño si el objetivo está a 25 studs o más.",
		"Disparo encadenado: cada 5.º impacto hace +25%.",
		"Retirada: +8% de velocidad durante 3 s tras usar un poder." } },
	Mago = { Desc = "Daño en área y control con poderes de gran alcance.", Pasivas = {
		"Maestría elemental: 10% de probabilidad de quemar (30% del daño en 4 s).",
		"Flujo de energía: +10% de regeneración de energía.",
		"Eco: 6% de probabilidad de repetir el golpe con 50% de daño." } },
	Curador = { Desc = "Soporte: cura, protege y revive; también tiene poderes de daño.", Pasivas = {
		"Aura de vida: cada 2 s cura 0,8% de la vida máx. a los aliados a 25 studs.",
		"Sobrecura: 40% de la cura sobrante se vuelve escudo (máx 8% de vida).",
		"Última esperanza: +12% de cura a aliados con menos de 35% de vida." } },
}
local passiveLabel: TextLabel? = nil

local function refreshStats()
	local class = PlayerClass.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local level = (player:GetAttribute("Level") :: number?) or 1
	local bonus: { [string]: number } = {}
	for _, id in pairs(Store.Equip) do
		local it = ItemCatalog.Items[id]
		if it and it.Stats then
			for k, v in pairs(it.Stats) do
				bonus[k] = (bonus[k] or 0) + v
			end
		end
	end
	local lines = {
		string.format("<b>%s</b>", class.CharacterName),
		string.format("%s · %s", theme.Faction, class.Role),
		"",
		string.format("Nivel: %d", level),
		string.format("Vida: %d", if hum then math.floor(hum.MaxHealth) else 0),
		string.format("%s: %d", theme.Resource, class.BaseEnergy),
		string.format("Daño (x nivel): %.2f", GB.PlayerDamageMult(level)),
		string.format("Poder básico: %d", math.floor(class.PrimarySkill.BaseValue * GB.PlayerDamageMult(level))),
		string.format("Defensa: %d", class.BaseDefense),
		string.format("Velocidad: %d", if hum then math.floor(hum.WalkSpeed) else 0),
		"",
		"<b>Bonus de equipo</b>",
	}
	local any = false
	for k, v in pairs(bonus) do
		table.insert(lines, string.format("+%d %s", v, k))
		any = true
	end
	if not any then
		table.insert(lines, "(sin equipo)")
	end
	statsLabel.Text = table.concat(lines, "\n")
end

local function refreshModel()
	if clone then
		clone:Destroy()
		clone = nil
	end
	local char = player.Character
	if not char then
		return
	end
	char.Archivable = true
	local c = char:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") or d:IsA("Highlight") then
			d:Destroy()
		end
	end
	local hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		c:Destroy()
		return
	end
	c:PivotTo(CFrame.new(0, 0, 0))
	c.Parent = viewport
	clone = c
end

local function updateCamera()
	local cam = viewport.CurrentCamera
	if not cam then
		cam = Instance.new("Camera")
		viewport.CurrentCamera = cam
		cam.Parent = viewport
	end
	local c = angle
	cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(c) * 9, 1.5, math.cos(c) * 9), Vector3.new(0, 0.5, 0))
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
		table.clear(slotButtons)
	end
	win = UITheme.Frame(gui, theme, UDim2.fromOffset(700, 700), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	title = UITheme.Text(win, "PERFIL DEL PERSONAJE", 20, theme.Primary, UDim2.fromOffset(18, 8), UDim2.fromOffset(300, 28))
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.Parent = win
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	-- ranuras izquierda / derecha (6 c/u)
	for i, n in ipairs(LEFT) do
		makeSlot(n, UDim2.fromOffset(18, 46 + (i - 1) * 56), UDim2.fromOffset(70, 50))
	end
	for i, n in ipairs(RIGHT) do
		makeSlot(n, UDim2.fromOffset(310, 46 + (i - 1) * 56), UDim2.fromOffset(70, 50))
	end
	-- fila inferior
	for i, n in ipairs(BOTTOM) do
		makeSlot(n, UDim2.fromOffset(18 + (i - 1) * 94, 392), UDim2.fromOffset(86, 60))
	end

	-- miniatura 3D
	viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.fromOffset(96, 46)
	viewport.Size = UDim2.fromOffset(206, 330)
	viewport.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.Parent = win
	Instance.new("UICorner", viewport)
	UITheme.Border(viewport, theme, 2)
	UITheme.Text(viewport, "arrastra para girar", 10, Color3.fromRGB(150, 150, 165), UDim2.fromScale(0, 0.94), UDim2.fromScale(1, 0.06), Enum.TextXAlignment.Center)
	viewport.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			angle += i.Delta.X * 0.015
		end
	end)

	-- panel de estadísticas
	local statsBox = Instance.new("Frame")
	statsBox.Position = UDim2.fromOffset(398, 46)
	statsBox.Size = UDim2.fromOffset(284, 330)
	statsBox.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	statsBox.BorderSizePixel = 0
	statsBox.Parent = win
	Instance.new("UICorner", statsBox)
	UITheme.Border(statsBox, theme, 2)
	statsLabel = UITheme.Text(statsBox, "", 15, nil, UDim2.fromOffset(14, 10), UDim2.fromOffset(256, 310))
	statsLabel.TextYAlignment = Enum.TextYAlignment.Top
	statsLabel.RichText = true
	UITheme.Text(win, "Clic en una ranura para desequiparla.  Equipa desde la mochila (I).", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 466), UDim2.fromOffset(660, 20))

	-- descripción del personaje y pasivas
	local pBox = Instance.new("Frame")
	pBox.Position = UDim2.fromOffset(18, 494)
	pBox.Size = UDim2.fromOffset(664, 184)
	pBox.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	pBox.BorderSizePixel = 0
	pBox.Parent = win
	Instance.new("UICorner", pBox)
	UITheme.Border(pBox, theme, 2)
	local pl = UITheme.Text(pBox, "", 13, nil, UDim2.fromOffset(14, 8), UDim2.fromOffset(636, 168))
	pl.TextYAlignment = Enum.TextYAlignment.Top
	pl.TextWrapped = true
	pl.RichText = true
	passiveLabel = pl
	local cls = PlayerClass.Get(player)
	local info = ROLE_INFO[cls.Role]
	local out = { string.format("<b>%s</b> · %s", cls.CharacterName, cls.Role) }
	if info then
		table.insert(out, info.Desc)
		table.insert(out, "")
		table.insert(out, "<b>Pasivas</b>")
		for _, t in ipairs(info.Pasivas) do
			table.insert(out, "• " .. t)
		end
		table.insert(out, "")
		table.insert(out, "<b>Poder 7 · Primeros Auxilios</b>: curación propia cada 25 s (tecla 7).")
	end
	pl.Text = table.concat(out, "\n")

	refreshSlots()
	refreshStats()
end

local function open()
	gui.Enabled = true
	build()
	refreshModel()
end

Store.Changed:Connect(function()
	if gui.Enabled then
		refreshSlots()
		refreshStats()
		refreshModel()
	end
end)
player.CharacterAdded:Connect(function()
	if gui.Enabled then
		task.wait(1)
		refreshModel()
	end
end)
player:GetAttributeChangedSignal("Level"):Connect(function()
	if gui.Enabled then
		refreshStats()
	end
end)
RunService.RenderStepped:Connect(function()
	if gui.Enabled and viewport then
		if not dragging then
			angle += 0.01
		end
		updateCamera()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.C then
		if gui.Enabled then
			gui.Enabled = false
		else
			open()
		end
	end
end)

-- Botón "Perfil" de la barra de menú
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
MenuBus.Event:Connect(function(name: string)
	if name == "Character" then
		if gui.Enabled then
			gui.Enabled = false
		else
			open()
		end
	end
end)
