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
local GearView = require(script.Parent:WaitForChild("GearView", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "CharacterGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local theme = UITheme.For(player:GetAttribute("Faction"))
local win: Frame
local viewport: ViewportFrame
local statsScroll: ScrollingFrame
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
			label.Text = GearView.DisplayName(item, Store.EquipPlus[name])
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

local GREEN, RED, GRAY = Color3.fromRGB(111, 220, 127), Color3.fromRGB(255, 107, 107), Color3.fromRGB(150, 150, 165)

-- Filas del panel de estadísticas (se reconstruyen cuando algo cambia)
local rowOrder = 0
local function addRow(height: number): Frame
	rowOrder += 1
	local f = Instance.new("Frame")
	f.LayoutOrder = rowOrder
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height)
	f.Parent = statsScroll
	return f
end

local function addHeader(text: string)
	local f = addRow(24)
	UITheme.Text(f, text, 14, theme.Primary, UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 18))
	local line = Instance.new("Frame")
	line.BackgroundColor3 = theme.Secondary
	line.BorderSizePixel = 0
	line.Position = UDim2.new(0, 0, 1, -2)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Parent = f
end

-- "Nombre ......... valor   +x%"
local function addStat(name: string, value: string, bonus: string?, bonusColor: Color3?)
	local f = addRow(20)
	UITheme.Text(f, name, 13, Color3.fromRGB(215, 215, 225), UDim2.fromOffset(0, 0), UDim2.new(0.44, 0, 1, 0))
	UITheme.Text(f, value, 13, nil, UDim2.new(0.44, 0, 0, 0), UDim2.new(0.24, 0, 1, 0), Enum.TextXAlignment.Right)
	if bonus then
		UITheme.Text(f, bonus, 13, bonusColor or GREEN, UDim2.new(0.68, 0, 0, 0), UDim2.new(0.32, -2, 1, 0), Enum.TextXAlignment.Right)
	end
end

local function addNote(text: string, color: Color3?)
	rowOrder += 1
	local t = Instance.new("TextLabel")
	t.LayoutOrder = rowOrder
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Font = Enum.Font.Gotham
	t.TextSize = 11
	t.TextColor3 = color or GRAY
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = text
	t.Parent = statsScroll
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function refreshStats()
	if not statsScroll then
		return
	end
	for _, c in ipairs(statsScroll:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	rowOrder = 0

	local class = PlayerClass.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local level = (player:GetAttribute("Level") :: number?) or 1
	local br = GearView.Breakdown()
	local total = br.Total

	addHeader(string.format("%s  ·  Nivel %d", class.CharacterName, level))
	addNote(string.format("%s · %s", theme.Faction, class.Role))

	addHeader("Atributos")
	addStat("Vida", tostring(if hum then math.floor(hum.MaxHealth) else 0), if total.Vida then GearView.Format("Vida", total.Vida) else nil)
	addStat(theme.Resource, tostring(class.BaseEnergy))
	local gold, points = player:GetAttribute("Gold"), player:GetAttribute("FactionPoints")
	addStat("Oro", withCommas(if typeof(gold) == "number" then gold else 0))
	addStat("Pts. de facción", withCommas(if typeof(points) == "number" then points else 0))
	local power = math.floor(class.PrimarySkill.BaseValue * GB.PlayerDamageMult(level) * (1 + (total.Ataque or 0)))
	addStat("Poder básico", tostring(power), if total.Ataque then GearView.Format("Ataque", total.Ataque) else nil)
	addStat("Defensa base", tostring(class.BaseDefense))
	addStat("Velocidad", tostring(if hum then math.floor(hum.WalkSpeed) else 0))

	-- HISTORIAL DE ORO: de dónde viene y en qué se gastó (WalletService publica GoldIn_<motivo> / GoldOut_<motivo>)
	local earned, spent = {}, {}
	local totalIn, totalOut = 0, 0
	for name, value in pairs(player:GetAttributes()) do
		if typeof(value) == "number" then
			if string.sub(name, 1, 7) == "GoldIn_" then
				table.insert(earned, { string.sub(name, 8), value })
				totalIn += value
			elseif string.sub(name, 1, 8) == "GoldOut_" then
				table.insert(spent, { string.sub(name, 9), value })
				totalOut += value
			end
		end
	end
	if totalIn > 0 or totalOut > 0 then
		addHeader("Historial de oro")
		table.sort(earned, function(a, b) return a[2] > b[2] end)
		table.sort(spent, function(a, b) return a[2] > b[2] end)
		for _, e in ipairs(earned) do
			addStat(e[1], "", "+" .. withCommas(e[2]))
		end
		for _, e in ipairs(spent) do
			addStat(e[1], "", "-" .. withCommas(e[2]), RED)
		end
		addNote(string.format("Total obtenido %s · gastado %s", withCommas(totalIn), withCommas(totalOut)))
	end

	addHeader("Bonos del equipo")
	for _, stat in ipairs(GearView.StatOrder) do
		local v = total[stat]
		local name = GearView.StatName[stat]
		if v and v > 0 then
			local tag = if br.Capped[stat] then GearView.Format(stat, v) .. " (tope)" else GearView.Format(stat, v)
			addStat(name, "", tag)
			local parts = {}
			for _, s in ipairs(br.Sources[stat] or {}) do
				table.insert(parts, string.format("%s %s", s.Label, GearView.Format(stat, s.Value)))
			end
			addNote("   " .. table.concat(parts, "  ·  "))
		else
			addStat(name, "", "—", GRAY)
		end
	end
	if br.SetPieces >= 2 then
		addNote(string.format("Bono de set activo: %d/4 piezas de tu rol (+%d%% al equipo).", br.SetPieces, math.floor(br.SetBonus * 100 + 0.5)), GREEN)
	elseif br.SetPieces == 0 then
		addNote("Equipa piezas del set de tu rol: 2 dan +5%, 4 dan +15%.")
	else
		addNote("1 pieza de set: con 2 piezas se activa +5%.")
	end
	if #br.Ignored > 0 then
		addNote("Sin efecto (no puedes usarlos): " .. table.concat(br.Ignored, ", "), RED)
	end
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
	WindowDrag.Attach(win, "Character", 40, 50)
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

	-- panel de estadísticas (con scroll por si hay muchas filas)
	local statsBox = Instance.new("Frame")
	statsBox.Position = UDim2.fromOffset(388, 46)
	statsBox.Size = UDim2.fromOffset(296, 330)
	statsBox.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
	statsBox.BorderSizePixel = 0
	statsBox.Parent = win
	Instance.new("UICorner", statsBox)
	UITheme.Border(statsBox, theme, 2)
	statsScroll = Instance.new("ScrollingFrame")
	statsScroll.Position = UDim2.fromOffset(10, 8)
	statsScroll.Size = UDim2.fromOffset(276, 314)
	statsScroll.BackgroundTransparency = 1
	statsScroll.BorderSizePixel = 0
	statsScroll.ScrollBarThickness = 4
	local statsPad = Instance.new("UIPadding")
	statsPad.PaddingRight = UDim.new(0, 12)
	statsPad.Parent = statsScroll
	statsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	statsScroll.CanvasSize = UDim2.fromOffset(0, 0)
	statsScroll.Parent = statsBox
	local statsList = Instance.new("UIListLayout")
	statsList.SortOrder = Enum.SortOrder.LayoutOrder
	statsList.Padding = UDim.new(0, 2)
	statsList.Parent = statsScroll
	UITheme.Text(win, "Clic en una ranura para desequiparla.  Equipa desde la mochila (B).  Arrastra el título para mover la ventana.", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 466), UDim2.fromOffset(660, 20))

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
player.AttributeChanged:Connect(function(name: string)
	local isGold = name == "Gold" or name == "FactionPoints" or string.sub(name, 1, 7) == "GoldIn_" or string.sub(name, 1, 8) == "GoldOut_"
	if gui.Enabled and (isGold or string.sub(name, 1, 10) == "EquipPlus_") then
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
