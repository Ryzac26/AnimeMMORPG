--!strict
--[[
    MobileClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MobileClient
    Interfaz de CELULAR / TABLET (solo si Platform.IsMobile(): pantalla táctil sin teclado). En la PC no hace nada.
    Para probarla en Studio: Workspace > atributo ForceMobileUI (booleano) = true  (o el emulador de dispositivos).

    Distribución (pantalla horizontal, referencia 844x380; se escala sola). Arriba a la izquierda queda libre: ahí Roblox pone su menú.
      Arriba centro  retrato con nivel + barras de vida / energía / XP, y debajo el objetivo
      Arriba der.    Perfil · Mochila · Grupo · Misiones · Menú (el Menú trae todo lo demás y los modos de AutoFarm), y debajo el chip de arena/evento
      Izq. abajo     joystick de Roblox (libre)
      Abajo centro   Montura · FARM (AutoFarm) · AUTO (auto-ataque) · OBJ (siguiente objetivo)
      Der. abajo     salto de Roblox; habilidad 1 grande; 2-4 en arco interior; 5-7 en arco exterior
    Toca un enemigo para marcarlo. Si usas una habilidad sin objetivo, marca solo al enemigo más cercano (apuntado automático).
    Cada botón hace lo mismo que su tecla de PC (1-7 / Q / C / B / P / Z) hablando con los mismos remotes que HudClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Platform = require(script.Parent:WaitForChild("Platform", 10))
if not Platform.IsMobile() then
	return
end

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local PlayerClass = require(Modules:WaitForChild("PlayerClass", 10))
local AbilityCatalog = require(Modules:WaitForChild("AbilityCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local PortraitKit = require(script.Parent:WaitForChild("PortraitKit", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local AbilityIcons = require(Modules:WaitForChild("AbilityIcons", 10))

local DealDamageEvent = ClientNet.Get("DealDamageEvent")
local AutoAttackRemote = ClientNet.Get("AutoAttack")
local UseAbilityRemote = ClientNet.Get("UseAbility")

local theme = UITheme.For(player:GetAttribute("Faction"))
local class = PlayerClass.Get(player)

local REF_W, REF_H = 844, 380
local TARGET_RANGE = 70 -- studs: apuntado automático

---------------------------------------------------------------------
-- Pantalla y escala
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MobileGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- solo respeta muescas / barra de gestos: arriba al centro y a la derecha Roblox no pone nada, y su menú queda arriba a la izquierda (zona libre)
gui.Parent = player:WaitForChild("PlayerGui", 10)

local stage = Instance.new("Frame")
stage.BackgroundTransparency = 1
stage.Parent = gui
local uiScale = Instance.new("UIScale")
uiScale.Parent = stage

local function rescale()
	local size = gui.AbsoluteSize
	if size.X < 10 or size.Y < 10 then
		return
	end
	local s = math.clamp(math.min(size.X / REF_W, size.Y / REF_H), 0.7, 1.25)
	uiScale.Scale = s
	stage.Size = UDim2.new(1 / s, 0, 1 / s, 0)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
rescale()

---------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------
local function round(inst: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0)
	c.Parent = inst
end

-- botón redondo anclado a la esquina inferior derecha (ox, oy = desplazamiento del CENTRO respecto al centro de la rueda de habilidades;
-- la rueda queda a WHEEL_X px del borde derecho y WHEEL_Y px del inferior, alejada del salto de Roblox)
local WHEEL_X, WHEEL_Y = 150, 142
local function cornerButton(ox: number, oy: number, size: number, border: Color3, text: string): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(1, -WHEEL_X + ox, 1, -WHEEL_Y + oy)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.12
	b.AutoButtonColor = false
	b.Text = text
	b.Font = UITheme.Font
	b.TextSize = if size >= 60 then 18 elseif size >= 50 then 15 else 11
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = stage
	round(b)
	local gr = Instance.new("UIGradient") -- brillo suave arriba, más oscuro abajo
	gr.Rotation = 90
	gr.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
	gr.Parent = b
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = border
	st.Thickness = if size >= 60 then 3 else 2
	st.Transparency = 0.1
	st.Parent = b
	return b
end

local function squareButton(parent: Instance, icon: string, label: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(44, 44)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = false
	b.Text = icon
	b.Font = UITheme.Font
	b.TextSize = 11
	b.TextWrapped = false
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	b.Name = label
	b.LayoutOrder = order
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2), UDim.new(0, 2), UDim.new(0, 2)
	pad.Parent = b
	round(b, 12)
	local gr = Instance.new("UIGradient")
	gr.Rotation = 90
	gr.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
	gr.Parent = b
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = theme.Primary
	st.Thickness = 1.5
	st.Transparency = 0.15
	st.Parent = b
	return b
end

---------------------------------------------------------------------
-- ARRIBA IZQUIERDA: retrato y barras
---------------------------------------------------------------------
local topLeft = Instance.new("Frame")
topLeft.BackgroundTransparency = 1
topLeft.AnchorPoint = Vector2.new(0.5, 0)
topLeft.Position = UDim2.new(0.5, 0, 0, 8)
topLeft.Size = UDim2.fromOffset(300, 56)
topLeft.Parent = stage

pcall(function()
	PortraitKit.Mount(topLeft, UDim2.fromOffset(0, 2), UDim2.fromOffset(52, 52), theme, class.CharacterName)
end)
-- insignia con el nivel sobre el retrato
local levelLabel = Instance.new("TextLabel")
levelLabel.AnchorPoint = Vector2.new(0.5, 0.5)
levelLabel.Position = UDim2.fromOffset(40, 50)
levelLabel.Size = UDim2.fromOffset(28, 16)
levelLabel.BackgroundColor3 = theme.Primary
levelLabel.Font = UITheme.Font
levelLabel.TextSize = 11
levelLabel.TextColor3 = Color3.fromRGB(16, 19, 26)
levelLabel.Text = "1"
levelLabel.ZIndex = 8
levelLabel.Parent = topLeft
round(levelLabel, 8)
local _, setHp = UITheme.Bar(topLeft, UDim2.fromOffset(62, 2), UDim2.fromOffset(238, 18), Color3.fromRGB(220, 60, 60), nil, 11, theme.Primary)
local _, setEnergy = UITheme.Bar(topLeft, UDim2.fromOffset(62, 23), UDim2.fromOffset(238, 14), theme.ResourceColor, nil, 10, theme.Primary)
local _, setXp = UITheme.Bar(topLeft, UDim2.fromOffset(62, 40), UDim2.fromOffset(238, 6), theme.Primary, nil, 8, theme.Primary)

local ClientXp = ClientNet.Get("XPChanged")
if ClientXp then
	ClientXp.OnClientEvent:Connect(function(level: any, xp: any, need: any)
		if typeof(level) == "number" and typeof(xp) == "number" and typeof(need) == "number" then
			levelLabel.Text = tostring(level)
			if need == math.huge then
				setXp(1, 1)
			else
				setXp(xp, need)
			end
		end
	end)
end

---------------------------------------------------------------------
-- ARRIBA CENTRO: botón MENÚ (3 líneas) + AutoFarm rápido. El menú desplegable trae TODA la barra de la PC.
---------------------------------------------------------------------
local autoFarmRemote = ClientNet.Get("AutoFarm")
local function farmToggle()
	if autoFarmRemote then
		autoFarmRemote:FireServer("Set", player:GetAttribute("AutoFarm") ~= true, nil)
	end
end

local menuRow = Instance.new("Frame")
menuRow.BackgroundTransparency = 1
menuRow.AnchorPoint = Vector2.new(1, 0)
menuRow.Position = UDim2.new(1, -12, 0, 8)
menuRow.Size = UDim2.fromOffset(204, 44)
menuRow.Parent = stage
local menuLayout = Instance.new("UIListLayout")
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.FillDirection = Enum.FillDirection.Horizontal
menuLayout.Padding = UDim.new(0, 8)
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
menuLayout.Parent = menuRow

local bMenu = squareButton(menuRow, "", "Menu", 5)
bMenu.BackgroundColor3 = theme.Secondary
for k = 0, 2 do -- las 3 líneas
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(11, 13 + k * 8)
	bar.Size = UDim2.fromOffset(22, 3)
	bar.BackgroundColor3 = theme.Primary
	bar.BorderSizePixel = 0
	bar.Parent = bMenu
	round(bar)
end

-- DESPLEGABLE
local drawer = Instance.new("Frame")
drawer.AnchorPoint = Vector2.new(1, 0)
drawer.Position = UDim2.new(1, -12, 0, 56)
drawer.Size = UDim2.fromOffset(336, 292)
drawer.BackgroundColor3 = theme.Dark
drawer.BackgroundTransparency = 0.04
drawer.Visible = false
drawer.ZIndex = 20
drawer.Parent = stage
round(drawer, 14)
local drawerStroke = Instance.new("UIStroke")
drawerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
drawerStroke.Color = theme.Primary
drawerStroke.Thickness = 2
drawerStroke.Parent = drawer
local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(8, 8)
scroll.Size = UDim2.new(1, -16, 1, -16)
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.ZIndex = 21
scroll.Parent = drawer
local sList = Instance.new("UIListLayout")
sList.SortOrder = Enum.SortOrder.LayoutOrder
sList.Padding = UDim.new(0, 8)
sList.Parent = scroll

local drawerTitle = Instance.new("TextLabel")
drawerTitle.LayoutOrder = 1
drawerTitle.BackgroundTransparency = 1
drawerTitle.Size = UDim2.new(1, -6, 0, 18)
drawerTitle.Font = UITheme.Font
drawerTitle.TextSize = 13
drawerTitle.TextColor3 = theme.Primary
drawerTitle.TextXAlignment = Enum.TextXAlignment.Left
drawerTitle.Text = "MENÚ"
drawerTitle.ZIndex = 22
drawerTitle.Parent = scroll

local function setDrawer(open: boolean)
	drawer.Visible = open
end
bMenu.Activated:Connect(function()
	setDrawer(not drawer.Visible)
end)
-- accesos directos (los mismos eventos que el menú)
for i, it in ipairs({ { "Perfil", "Character" }, { "Grupo", "Party" }, { "Misiones", "Quests" } }) do
	local b = squareButton(menuRow, it[1], it[1], i)
	b.Activated:Connect(function()
		setDrawer(false)
		MenuBus.Fire(it[2])
	end)
end

local titleToken = 0
local function flashTitle(text: string)
	titleToken += 1
	local my = titleToken
	drawerTitle.Text = text
	task.delay(2, function()
		if my == titleToken then
			drawerTitle.Text = "MENÚ"
		end
	end)
end

local function drawerButton(parent: Instance, text: string, enabled: boolean, onUse: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = if enabled then Color3.fromRGB(30, 34, 54) else Color3.fromRGB(22, 24, 36)
	b.AutoButtonColor = false
	b.Text = text
	b.Font = UITheme.Font
	b.TextSize = 13
	b.TextColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromRGB(135, 138, 155)
	b.TextWrapped = true
	b.ZIndex = 22
	b.Parent = parent
	round(b, 10)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = if enabled then theme.Primary else Color3.fromRGB(70, 72, 90)
	st.Thickness = 1.5
	st.Parent = b
	b.Activated:Connect(onUse)
	return b
end

-- sección 1: toda la barra de la PC (Perfil, Mochila, Habilidades, Misiones, Facción, Ajustes) + Grupo
local grid = Instance.new("Frame")
grid.LayoutOrder = 2
grid.BackgroundTransparency = 1
grid.Size = UDim2.new(1, -6, 0, 0)
grid.AutomaticSize = Enum.AutomaticSize.Y
grid.ZIndex = 21
grid.Parent = scroll
local gl = Instance.new("UIGridLayout")
gl.CellSize = UDim2.fromOffset(152, 40)
gl.CellPadding = UDim2.fromOffset(8, 6)
gl.SortOrder = Enum.SortOrder.LayoutOrder
gl.Parent = grid
-- { texto, evento de MenuBus ("" = todavía no existe) }  (misma lista que el menú de HudClient; súmale las nuevas aquí)
local ITEMS: { { string } } = {
	{ "Perfil", "Character" }, { "Mochila", "Inventory" }, { "Grupo", "Party" }, { "Habilidades", "Skills" },
	{ "Misiones", "Quests" }, { "Facción", "Guild" }, { "Mascota", "Pets" }, { "Monturas", "Mounts" }, { "Ajustes", "Settings" },
}
for _, it in ipairs(ITEMS) do
	local label, ev = it[1], it[2]
	local b = drawerButton(grid, if ev ~= "" then label else label .. "  (pronto)", ev ~= "", function()
		if ev ~= "" then
			setDrawer(false)
			MenuBus.Fire(ev)
		else
			flashTitle(label .. ": próximamente")
		end
	end)
	b.Parent = grid
end

-- sección 2: AutoFarm (activar y modos Semi / Metin / Jefe)
local farmTitle = Instance.new("TextLabel")
farmTitle.LayoutOrder = 3
farmTitle.BackgroundTransparency = 1
farmTitle.Size = UDim2.new(1, -6, 0, 18)
farmTitle.Font = UITheme.Font
farmTitle.TextSize = 13
farmTitle.TextColor3 = theme.Primary
farmTitle.TextXAlignment = Enum.TextXAlignment.Left
farmTitle.Text = "AUTOFARM"
farmTitle.ZIndex = 22
farmTitle.Parent = scroll
local farmRow = Instance.new("Frame")
farmRow.LayoutOrder = 4
farmRow.BackgroundTransparency = 1
farmRow.Size = UDim2.new(1, -6, 0, 40)
farmRow.ZIndex = 21
farmRow.Parent = scroll
local fl = Instance.new("UIGridLayout")
fl.CellSize = UDim2.fromOffset(74, 40)
fl.CellPadding = UDim2.fromOffset(5, 0)
fl.SortOrder = Enum.SortOrder.LayoutOrder
fl.Parent = farmRow
local farmOnBtn = drawerButton(farmRow, "OFF", true, farmToggle)
farmOnBtn.LayoutOrder = 1
local modeBtns: { [string]: TextButton } = {}
for k, m in ipairs({ "Semi", "Metin", "Jefe" }) do
	local b = drawerButton(farmRow, m, true, function()
		if autoFarmRemote then
			autoFarmRemote:FireServer("Set", "keep", m) -- cambia de modo sin apagar / encender (igual que el panel de la PC)
		end
	end)
	b.LayoutOrder = k + 1
	modeBtns[m] = b
end
local farmMore = drawerButton(scroll, "Pociones y más ajustes de AutoFarm", true, function()
	setDrawer(false)
	MenuBus.Fire("AutoFarmMode")
end)
farmMore.LayoutOrder = 5
farmMore.Size = UDim2.new(1, -6, 0, 36)
local farmHint = Instance.new("TextLabel")
farmHint.LayoutOrder = 6
farmHint.BackgroundTransparency = 1
farmHint.Size = UDim2.new(1, -6, 0, 30)
farmHint.Font = Enum.Font.Gotham
farmHint.TextSize = 11
farmHint.TextWrapped = true
farmHint.TextColor3 = Color3.fromRGB(175, 178, 195)
farmHint.TextXAlignment = Enum.TextXAlignment.Left
farmHint.TextYAlignment = Enum.TextYAlignment.Top
farmHint.Text = "Semi: tú caminas · Metin: piedra y oleadas · Jefe: jefe y súbditos"
farmHint.ZIndex = 22
farmHint.Parent = scroll

---------------------------------------------------------------------
-- ARRIBA DERECHA: evento y vidas de arena
---------------------------------------------------------------------
local eventChip = Instance.new("TextLabel")
eventChip.AnchorPoint = Vector2.new(1, 0)
eventChip.Position = UDim2.new(1, -12, 0, 56)
eventChip.Size = UDim2.fromOffset(190, 26)
eventChip.BackgroundColor3 = theme.Dark
eventChip.BackgroundTransparency = 0.2
eventChip.Font = UITheme.Font
eventChip.TextSize = 11
eventChip.TextColor3 = Color3.new(1, 1, 1)
eventChip.Text = "Evento --"
eventChip.Parent = stage
round(eventChip, 14)
local eventStroke = Instance.new("UIStroke")
eventStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
eventStroke.Color = Color3.fromRGB(110, 110, 125)
eventStroke.Thickness = 1
eventStroke.Parent = eventChip

---------------------------------------------------------------------
-- OBJETIVO
---------------------------------------------------------------------
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
highlight.Parent = gui

local targetPanel = Instance.new("Frame")
targetPanel.AnchorPoint = Vector2.new(0.5, 0)
targetPanel.Position = UDim2.new(0.5, 0, 0, 68)
targetPanel.Size = UDim2.fromOffset(220, 46)
targetPanel.BackgroundColor3 = theme.Dark
targetPanel.BackgroundTransparency = 0.2
targetPanel.Visible = false
targetPanel.Parent = stage
round(targetPanel, 12)
local tName = UITheme.Text(targetPanel, "", 12, Color3.new(1, 1, 1), UDim2.fromOffset(10, 4), UDim2.fromOffset(160, 16))
tName.TextTruncate = Enum.TextTruncate.AtEnd
local _, setTarget = UITheme.Bar(targetPanel, UDim2.fromOffset(10, 24), UDim2.fromOffset(190, 14), Color3.fromRGB(220, 60, 60), nil, 10)
local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.fromOffset(24, 24)
clearBtn.Position = UDim2.new(1, -28, 0, 2)
clearBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 45)
clearBtn.Text = "X"
clearBtn.TextColor3 = Color3.new(1, 1, 1)
clearBtn.TextSize = 12
clearBtn.Font = Enum.Font.GothamBold
clearBtn.Parent = targetPanel
round(clearBtn)

local target: Model? = nil

local function aliveHum(m: Model?): Humanoid?
	local h = if m and m.Parent then m:FindFirstChildOfClass("Humanoid") else nil
	return if h and h.Health > 0 then h else nil
end

local function clearTarget()
	target = nil
	highlight.Adornee = nil
	targetPanel.Visible = false
	if AutoAttackRemote then
		AutoAttackRemote:FireServer("Clear")
	end
end
clearBtn.Activated:Connect(clearTarget)

local function setTargetModel(m: Model)
	target = m
	highlight.Adornee = m
	if AutoAttackRemote then
		AutoAttackRemote:FireServer("Target", m) -- empieza el auto-ataque, igual que el clic en PC
	end
end

local function modelFromPart(part: Instance?): Model?
	local m = if part then part:FindFirstAncestorOfClass("Model") else nil
	while m and not CollectionService:HasTag(m, "Targetable") do
		m = m:FindFirstAncestorOfClass("Model")
	end
	return m
end

local function rootPos(m: Model): Vector3?
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	return if r and r:IsA("BasePart") then r.Position else nil
end

-- lista de enemigos cercanos ordenados por distancia (sin campos de santuario de tu propia facción)
local function candidates(): { Model }
	local char = player.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not myRoot or not myRoot:IsA("BasePart") then
		return {}
	end
	local out: { { M: Model, D: number } } = {}
	local myFaction = player:GetAttribute("Faction")
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and inst ~= char and aliveHum(inst) then
			local ownField = inst:GetAttribute("ShrineField") == true and inst:GetAttribute("ShrineOwner") == myFaction
			local pos = rootPos(inst)
			if pos and not ownField then
				local d = (pos - myRoot.Position).Magnitude
				if d <= TARGET_RANGE then
					table.insert(out, { M = inst, D = d })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.D < b.D
	end)
	local list: { Model } = {}
	for _, e in ipairs(out) do
		table.insert(list, e.M)
	end
	return list
end

local function ensureTarget(): Model?
	if aliveHum(target) then
		return target
	end
	local list = candidates()
	if list[1] then
		setTargetModel(list[1])
		return list[1]
	end
	return nil
end

-- tocar un enemigo lo marca
UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
	if processed then
		return
	end
	local cam = Workspace.CurrentCamera
	local p = positions[1]
	if not cam or not p then
		return
	end
	local ray = cam:ViewportPointToRay(p.X, p.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, params)
	if hit then
		local m = modelFromPart(hit.Instance)
		if m and m ~= player.Character then
			setTargetModel(m)
		end
	end
end)

---------------------------------------------------------------------
-- DERECHA ABAJO: habilidades 1-7, AUTO y siguiente objetivo
---------------------------------------------------------------------
local cooldownEnd: { [number]: number } = {}
local cooldownLen: { [number]: number } = {}
local ability = ClientNet.Get("AbilityCooldown")
if ability then
	ability.OnClientEvent:Connect(function(slot: any, seconds: any)
		if typeof(slot) == "number" and typeof(seconds) == "number" then
			cooldownEnd[slot] = if seconds > 0 then os.clock() + seconds else 0
			cooldownLen[slot] = math.max(seconds, 1)
		end
	end)
end

local function skillOf(i: number): any
	if i == 1 then
		return class.PrimarySkill
	elseif i == 2 then
		return class.SecondarySkill
	elseif i == 7 then
		return { Name = "Primeros Auxilios" }
	end
	local set = (AbilityCatalog :: any)[class.CharacterName]
	return if set then set[i] else nil
end

local function useSlot(i: number)
	if os.clock() < (cooldownEnd[i] or 0) then
		return
	end
	local h = ensureTarget() -- apuntado automático si no hay objetivo
	if i > 2 then
		if UseAbilityRemote then
			UseAbilityRemote:FireServer(i, h) -- el servidor valida y responde con AbilityCooldown
		end
		return
	end
	local skill = skillOf(i)
	if not skill then
		return
	end
	cooldownEnd[i] = os.clock() + skill.Cooldown
	cooldownLen[i] = skill.Cooldown
	if DealDamageEvent then
		DealDamageEvent:FireServer(tostring(i), h)
	end
end

type SlotUi = { Button: TextButton, Cool: Frame, CoolText: TextLabel }
local slotUi: { [number]: SlotUi } = {}

local function makeSlot(i: number, ox: number, oy: number, size: number)
	local skill = skillOf(i)
	local border = if i == 1 then Color3.fromRGB(255, 210, 90) elseif skill then theme.Primary else Color3.fromRGB(95, 95, 110)
	local shown = if skill then skill.Name else "—"
	local b = cornerButton(ox, oy, size, border, "")
	local num = UITheme.Text(b, tostring(i), 10, Color3.fromRGB(255, 255, 255), UDim2.fromOffset(2, 0), UDim2.fromOffset(16, 16), Enum.TextXAlignment.Center)
	num.BackgroundTransparency = 0.25
	num.BackgroundColor3 = Color3.fromRGB(10, 12, 20)
	round(num)
	num.ZIndex = 7
	local art = AbilityIcons.Make(b, if i == 7 then "General/7" else class.CharacterName .. "/" .. i)
	local ab = UITheme.Text(b, shown, 12, if skill then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 135), UDim2.fromScale(0.1, 0.22), UDim2.fromScale(0.8, 0.62), Enum.TextXAlignment.Center)
	ab.ZIndex = 3
	ab.TextScaled = true
	ab.TextWrapped = true
	ab.TextTruncate = Enum.TextTruncate.None
	ab.TextStrokeTransparency = 0.4
	local sc = Instance.new("UITextSizeConstraint")
	sc.MinTextSize = 7
	sc.MaxTextSize = if size >= 60 then 15 else 12
	sc.Parent = ab
	if art then -- icono del poder (proporción reducida, centrado); sin icono queda el nombre
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(if i == 1 then 0.8 else 0.74, if i == 1 then 0.8 else 0.74)
		art.ZIndex = 3
		round(art)
		ab.Visible = false
	end
	local cool = Instance.new("Frame")
	cool.Size = UDim2.fromScale(1, 1)
	cool.BackgroundColor3 = Color3.new(0, 0, 0)
	cool.BackgroundTransparency = 1
	cool.BorderSizePixel = 0
	cool.ZIndex = 5
	cool.Parent = b
	round(cool)
	local ct = UITheme.Text(b, "", 16, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.25), UDim2.fromScale(1, 0.5), Enum.TextXAlignment.Center)
	ct.ZIndex = 6
	if not skill then
		b.BackgroundTransparency = 0.5
	end
	b.Activated:Connect(function()
		useSlot(i)
	end)
	slotUi[i] = { Button = b, Cool = cool, CoolText = ct }
end

-- habilidad 1 grande (la principal), 2-4 en arco, 5-7 fila pequeña
makeSlot(1, 0, 0, 88)
makeSlot(2, -86, 0, 54)
makeSlot(3, -61, -61, 54)
makeSlot(4, 0, -86, 54)
makeSlot(5, -131, 54, 46)
makeSlot(6, -131, -54, 46)
makeSlot(7, -54, -131, 46)

-- fila de accesos rápidos (abajo centro): Montura · FARM · AUTO · OBJ
local mountRemote = ClientNet.Get("MountAction")
local bMount = cornerButton(-375, 78, 46, Color3.fromRGB(235, 235, 240), "MONT")
bMount.TextStrokeTransparency = 1
bMount.Activated:Connect(function()
	if mountRemote then
		mountRemote:FireServer("Toggle") -- igual que la tecla de montura de la PC
	end
end)
local bFarm = cornerButton(-321, 78, 46, theme.Primary, "FARM")
bFarm.TextStrokeTransparency = 1
bFarm.Activated:Connect(farmToggle)

-- MODOS DE AUTOFARM a la vista (encima de FARM / AUTO): SEMI · METIN · BOSS. Un toque elige el modo sin apagar ni encender el farm.
local farmModes = Instance.new("Frame")
farmModes.AnchorPoint = Vector2.new(0.5, 1)
farmModes.Position = UDim2.new(1, -444, 1, -95)
farmModes.Size = UDim2.fromOffset(164, 40)
farmModes.BackgroundTransparency = 1
farmModes.Parent = stage
local fmLayout = Instance.new("UIListLayout")
fmLayout.FillDirection = Enum.FillDirection.Horizontal
fmLayout.Padding = UDim.new(0, 4)
fmLayout.SortOrder = Enum.SortOrder.LayoutOrder
fmLayout.Parent = farmModes
local modeChips: { [string]: TextButton } = {}
for k, def in ipairs({ { "Semi", "SEMI" }, { "Metin", "METIN" }, { "Jefe", "BOSS" } }) do
	local mode, label = def[1], def[2]
	local chip = Instance.new("TextButton")
	chip.LayoutOrder = k
	chip.Size = UDim2.fromOffset(52, 40)
	chip.BackgroundColor3 = theme.Dark
	chip.BackgroundTransparency = 0.12
	chip.AutoButtonColor = false
	chip.Font = UITheme.Font
	chip.TextSize = 11
	chip.TextColor3 = Color3.new(1, 1, 1)
	chip.Text = label
	chip.Parent = farmModes
	round(chip, 10)
	local cst = Instance.new("UIStroke")
	cst.Name = "Borde"
	cst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cst.Color = theme.Primary
	cst.Thickness = 1.5
	cst.Transparency = 0.5
	cst.Parent = chip
	chip.Activated:Connect(function()
		if autoFarmRemote then
			autoFarmRemote:FireServer("Set", "keep", mode)
		end
	end)
	modeChips[mode] = chip
end
local farmStatus = Instance.new("TextLabel")
farmStatus.AnchorPoint = Vector2.new(0.5, 1)
farmStatus.Position = UDim2.new(1, -444, 1, -138)
farmStatus.Size = UDim2.fromOffset(190, 16)
farmStatus.BackgroundTransparency = 1
farmStatus.Font = UITheme.Font
farmStatus.TextSize = 11
farmStatus.TextColor3 = Color3.fromRGB(155, 240, 154)
farmStatus.TextStrokeTransparency = 0.4
farmStatus.Text = ""
farmStatus.Parent = stage

-- AUTO (activar/pausar auto-ataque, como la tecla Q) y siguiente objetivo
local autoBtn = cornerButton(-267, 78, 46, Color3.fromRGB(111, 207, 106), "AUTO")
autoBtn.TextStrokeTransparency = 1
autoBtn.Activated:Connect(function()
	local had = aliveHum(target) ~= nil
	ensureTarget() -- sin objetivo: marca el más cercano y el auto-ataque ya arranca solo
	if had and AutoAttackRemote then
		AutoAttackRemote:FireServer("Toggle") -- con objetivo: pausa / reanuda (como la tecla Q)
	end
end)
local nextBtn = cornerButton(-213, 78, 46, Color3.fromRGB(235, 235, 240), "OBJ")
nextBtn.TextScaled = true
local nPad = Instance.new("UIPadding")
nPad.PaddingLeft, nPad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
nPad.Parent = nextBtn
local nCons = Instance.new("UITextSizeConstraint")
nCons.MaxTextSize = 11
nCons.MinTextSize = 7
nCons.Parent = nextBtn
nextBtn.TextStrokeTransparency = 1
nextBtn.Activated:Connect(function()
	local list = candidates()
	if #list == 0 then
		return
	end
	local idx = table.find(list, target :: any)
	setTargetModel(list[((idx or 0) % #list) + 1])
end)

---------------------------------------------------------------------
-- AJUSTES PARA CELULAR DE LO QUE DIBUJAN OTROS SCRIPTS
--  1) Los botones flotantes de PC (REPORTAR, Maestría [N], Mercader [V], Carta) se guardan dentro del Menú.
--  2) Toda ventana "Ventana" (NpcKit.Window) se encoge para caber en la pantalla y su X se agranda para el dedo.
---------------------------------------------------------------------
local otherTitle = Instance.new("TextLabel")
otherTitle.LayoutOrder = 7
otherTitle.BackgroundTransparency = 1
otherTitle.Size = UDim2.new(1, -6, 0, 18)
otherTitle.Font = UITheme.Font
otherTitle.TextSize = 13
otherTitle.TextColor3 = theme.Primary
otherTitle.TextXAlignment = Enum.TextXAlignment.Left
otherTitle.Text = "ACCESOS"
otherTitle.ZIndex = 22
otherTitle.Parent = scroll
local otherGrid = Instance.new("Frame")
otherGrid.LayoutOrder = 8
otherGrid.BackgroundTransparency = 1
otherGrid.Size = UDim2.new(1, -6, 0, 0)
otherGrid.AutomaticSize = Enum.AutomaticSize.Y
otherGrid.ZIndex = 21
otherGrid.Parent = scroll
local og = Instance.new("UIGridLayout")
og.CellSize = UDim2.fromOffset(152, 40)
og.CellPadding = UDim2.fromOffset(8, 6)
og.SortOrder = Enum.SortOrder.LayoutOrder
og.Parent = otherGrid

local PC_BUTTONS = { "REPORTAR", "Maestría", "Mercader", "✉" }
local function adopt(b: TextButton)
	b.Parent = otherGrid
	b.AnchorPoint = Vector2.zero
	b.ZIndex = 22
	b.TextSize = 13
	b.Text = string.gsub(b.Text, "%s*%[%a%]", "")
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 23
		end
	end
	b:GetPropertyChangedSignal("Parent"):Connect(function()
		if b.Parent ~= otherGrid and b.Parent ~= nil then
			b.Parent = otherGrid -- otro script lo movió: vuelve al Menú
		end
	end)
	b:GetPropertyChangedSignal("AnchorPoint"):Connect(function()
		b.AnchorPoint = Vector2.zero
	end)
end

local playerGui = player:WaitForChild("PlayerGui", 10) :: PlayerGui
local adopted: { [Instance]: boolean } = {}
local function scanButtons()
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d:IsA("TextButton") and not adopted[d] and d.Parent and d.Parent:IsA("ScreenGui") and d.Parent.Name ~= "MobileGui" then
			for _, key in ipairs(PC_BUTTONS) do
				if string.find(d.Text, key, 1, true) == 1 or (key ~= "✉" and string.find(d.Text, key, 1, true) and string.find(d.Text, "[", 1, true)) then
					adopted[d] = true
					adopt(d)
					break
				end
			end
		end
	end
end
task.spawn(function()
	for _ = 1, 40 do -- los demás scripts crean sus botones poco a poco
		scanButtons()
		task.wait(1)
	end
end)

local function fitWindow(win: Frame)
	if win:FindFirstChild("MovilEscala") or win.Size.X.Scale ~= 0 or win.Size.Y.Scale ~= 0 then
		return
	end
	local sc = Instance.new("UIScale")
	sc.Name = "MovilEscala"
	sc.Parent = win
	local close = win:FindFirstChild("Cerrar")
	local function update()
		local g = win:FindFirstAncestorOfClass("ScreenGui")
		local view = if g and g.AbsoluteSize.X > 10 then g.AbsoluteSize else (Workspace.CurrentCamera :: Camera).ViewportSize
		local w, h = win.Size.X.Offset, win.Size.Y.Offset
		if w <= 0 or h <= 0 then
			return
		end
		local k = math.clamp(math.min(1, (view.X - 24) / w, (view.Y - 16) / h), 0.3, 1)
		sc.Scale = k
		if close and close:IsA("GuiObject") then
			local d = math.clamp(44 / k, 30, 80) -- la X siempre mide ~44 px en pantalla
			close.AnchorPoint = Vector2.new(1, 0)
			close.Size = UDim2.fromOffset(d, d)
			close.Position = UDim2.new(1, -6, 0, 6)
		end
		if win.AnchorPoint ~= Vector2.new(0.5, 0.5) then
			win.AnchorPoint = Vector2.new(0.5, 0.5)
			win.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
	update()
	win:GetPropertyChangedSignal("Size"):Connect(update)
	local g = win:FindFirstAncestorOfClass("ScreenGui")
	if g then
		g:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	end
end
local function watchWindow(d: Instance)
	if d:IsA("Frame") and d.Name == "Ventana" and d:FindFirstAncestor("MobileGui") == nil then
		local nested = d.Parent and d.Parent:FindFirstAncestor("Ventana")
		if not nested then
			task.defer(fitWindow, d)
		end
	end
end
for _, d in ipairs(playerGui:GetDescendants()) do
	watchWindow(d)
end
playerGui.DescendantAdded:Connect(watchWindow)

---------------------------------------------------------------------
-- Actualización por frame
---------------------------------------------------------------------
local function fmtTime(s: number): string
	return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

RunService.RenderStepped:Connect(function()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		setHp(hum.Health, hum.MaxHealth)
	end
	local e, me = player:GetAttribute("Energy"), player:GetAttribute("MaxEnergy")
	if typeof(e) == "number" and typeof(me) == "number" then
		setEnergy(e, me)
	end

	local now = os.clock()
	for i, s in pairs(slotUi) do
		local left = (cooldownEnd[i] or 0) - now
		if left > 0 then
			s.Cool.BackgroundTransparency = 0.35
			s.CoolText.Text = if left >= 10 then string.format("%d", left) else string.format("%.1f", left)
		else
			s.Cool.BackgroundTransparency = 1
			s.CoolText.Text = ""
		end
	end

	local th = aliveHum(target)
	if th and target then
		targetPanel.Visible = true
		tName.Text = tostring(target:GetAttribute("DisplayName") or target.Name)
		setTarget(th.Health, th.MaxHealth)
	elseif target then
		clearTarget()
	end

	local autoOn = player:GetAttribute("AutoAttack") == true
	autoBtn.TextColor3 = if autoOn then Color3.fromRGB(155, 240, 154) else Color3.new(1, 1, 1)
	autoBtn.BackgroundColor3 = if autoOn then Color3.fromRGB(24, 60, 30) else theme.Dark
	local farmOn = player:GetAttribute("AutoFarm") == true
	bFarm.TextColor3 = if farmOn then Color3.fromRGB(155, 240, 154) else Color3.new(1, 1, 1)
	bFarm.BackgroundColor3 = if farmOn then Color3.fromRGB(24, 60, 30) else theme.Dark
	bMount.BackgroundColor3 = if player:GetAttribute("Mounted") == true then Color3.fromRGB(60, 50, 24) else theme.Dark
	farmOnBtn.Text = if farmOn then "ON" else "OFF"
	farmOnBtn.TextColor3 = if farmOn then Color3.fromRGB(155, 240, 154) else Color3.fromRGB(190, 190, 200)
	local curMode = player:GetAttribute("AutoFarmMode")
	for m, b in pairs(modeBtns) do
		b.BackgroundColor3 = if m == curMode or (curMode == nil and m == "Semi") then theme.Secondary else Color3.fromRGB(30, 34, 54)
	end
	for m, chip in pairs(modeChips) do
		local sel = m == curMode or (curMode == nil and m == "Semi")
		chip.BackgroundColor3 = if sel then theme.Secondary else theme.Dark
		chip.BackgroundTransparency = if sel then 0.02 else 0.18
		chip.TextColor3 = if sel then Color3.new(1, 1, 1) else Color3.fromRGB(190, 192, 205)
		local cs = chip:FindFirstChild("Borde")
		if cs and cs:IsA("UIStroke") then
			cs.Transparency = if sel then 0 else 0.55
		end
	end
	local fst = player:GetAttribute("AutoFarmStatus")
	farmStatus.Text = if farmOn then ((if typeof(curMode) == "string" then string.upper(curMode == "Jefe" and "BOSS" or curMode) else "SEMI") .. (if typeof(fst) == "string" and fst ~= "" then " · " .. fst else "")) else ""

	local state = Workspace:GetAttribute("EventState")
	local cd = Workspace:GetAttribute("EventCountdown")
	if typeof(cd) == "number" then
		if state == "Open" then
			local lives = player:GetAttribute("ArenaLives")
			eventChip.Text = string.format("ARENA %s  ·  Vidas %s", fmtTime(cd), tostring(if typeof(lives) == "number" then lives else "-"))
			eventChip.TextColor3 = Color3.fromRGB(155, 240, 154)
			eventStroke.Color = Color3.fromRGB(111, 207, 106)
		else
			eventChip.Text = "Próximo evento  " .. fmtTime(cd)
			eventChip.TextColor3 = Color3.new(1, 1, 1)
			eventStroke.Color = Color3.fromRGB(110, 110, 125)
		end
	end
end)

player:GetAttributeChangedSignal("Level"):Connect(function()
	local lvl = player:GetAttribute("Level")
	if typeof(lvl) == "number" then
		levelLabel.Text = tostring(lvl)
	end
end)
do
	local lvl = player:GetAttribute("Level")
	if typeof(lvl) == "number" then
		levelLabel.Text = tostring(lvl)
	end
	local sync = ClientNet.Get("RequestSync")
	if sync then
		sync:FireServer() -- pide nivel / XP / vidas actuales
	end
end
