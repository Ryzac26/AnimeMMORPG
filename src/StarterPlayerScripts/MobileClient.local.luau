--!strict
--[[
    MobileClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MobileClient
    Interfaz de CELULAR / TABLET (solo si Platform.IsMobile(): pantalla táctil sin teclado). En la PC no hace nada.
    Para probarla en Studio: Workspace > atributo ForceMobileUI (booleano) = true  (o el emulador de dispositivos).

    Distribución (pantalla horizontal, referencia 844x390; se escala sola):
      Arriba izq.   retrato, nivel, barras de vida / energía / XP        (el grupo de PartyClient queda debajo)
      Arriba centro 4 menús: Personaje · Mochila · Grupo · AutoFarm (pulsación larga = modos de AutoFarm), y debajo el objetivo
      Arriba der.   chip de arena/evento + vidas  (el cuadro de Boost de BoostClient queda debajo, pequeño)
      Izq. abajo    joystick de Roblox (libre)
      Der. abajo    salto de Roblox; habilidad 1 grande; 2-4 en arco; 5-7 en una fila pequeña; AUTO y "siguiente objetivo" a la izquierda
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
gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- respeta la barra superior de Roblox (menú/chat) y las muescas
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

-- botón redondo anclado a la esquina inferior derecha (ox, oy = desplazamiento del CENTRO respecto al salto de Roblox)
local function cornerButton(ox: number, oy: number, size: number, border: Color3, text: string): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.new(1, -64 + ox, 1, -60 + oy)
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.12
	b.AutoButtonColor = false
	b.Text = text
	b.Font = UITheme.Font
	b.TextSize = if size >= 60 then 18 else 15
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = stage
	round(b)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = border
	st.Thickness = if size >= 60 then 3 else 2
	st.Parent = b
	return b
end

local function squareButton(parent: Instance, icon: string, label: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(48, 48)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = false
	b.Text = icon
	b.Font = UITheme.Font
	b.TextScaled = true
	b.TextWrapped = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	b.Name = label
	b.LayoutOrder = order
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5), UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = b
	local tc = Instance.new("UITextSizeConstraint")
	tc.MinTextSize = 8
	tc.MaxTextSize = 13
	tc.Parent = b
	round(b, 12)
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = theme.Primary
	st.Thickness = 2
	st.Parent = b
	return b
end

---------------------------------------------------------------------
-- ARRIBA IZQUIERDA: retrato y barras
---------------------------------------------------------------------
local topLeft = Instance.new("Frame")
topLeft.BackgroundTransparency = 1
topLeft.Position = UDim2.fromOffset(12, 6)
topLeft.Size = UDim2.fromOffset(210, 62)
topLeft.Parent = stage

pcall(function()
	PortraitKit.Mount(topLeft, UDim2.fromOffset(0, 4), UDim2.fromOffset(54, 54), theme, class.CharacterName)
end)
local levelLabel = UITheme.Text(topLeft, "Nv. 1", 12, theme.Primary, UDim2.fromOffset(62, 0), UDim2.fromOffset(140, 14))
local _, setHp = UITheme.Bar(topLeft, UDim2.fromOffset(62, 16), UDim2.fromOffset(132, 13), Color3.fromRGB(220, 60, 60), nil, 10, theme.Primary)
local _, setEnergy = UITheme.Bar(topLeft, UDim2.fromOffset(62, 32), UDim2.fromOffset(132, 11), theme.ResourceColor, nil, 9, theme.Primary)
local _, setXp = UITheme.Bar(topLeft, UDim2.fromOffset(62, 47), UDim2.fromOffset(132, 8), theme.Primary, nil, 8, theme.Primary)

local ClientXp = ClientNet.Get("XPChanged")
if ClientXp then
	ClientXp.OnClientEvent:Connect(function(level: any, xp: any, need: any)
		if typeof(level) == "number" and typeof(xp) == "number" and typeof(need) == "number" then
			levelLabel.Text = string.format("Nv. %d  %s", level, class.Role)
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
local menuRow = Instance.new("Frame")
menuRow.BackgroundTransparency = 1
menuRow.AnchorPoint = Vector2.new(0.5, 0)
menuRow.Position = UDim2.new(0.5, 0, 0, 8)
menuRow.Size = UDim2.fromOffset(170, 46)
menuRow.Parent = stage
local menuLayout = Instance.new("UIListLayout")
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.FillDirection = Enum.FillDirection.Horizontal
menuLayout.Padding = UDim.new(0, 12)
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
menuLayout.Parent = menuRow

local bMenu = squareButton(menuRow, "", "Menu", 1)
bMenu.Size = UDim2.fromOffset(96, 46)
for k = 0, 2 do -- las 3 líneas
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(14, 13 + k * 8)
	bar.Size = UDim2.fromOffset(22, 3)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = bMenu
	round(bar)
end
local menuText = Instance.new("TextLabel")
menuText.BackgroundTransparency = 1
menuText.Position = UDim2.fromOffset(42, 0)
menuText.Size = UDim2.new(1, -46, 1, 0)
menuText.Font = UITheme.Font
menuText.TextSize = 14
menuText.TextColor3 = Color3.new(1, 1, 1)
menuText.Text = "MENÚ"
menuText.Parent = bMenu

local bFarm = squareButton(menuRow, "AUTO FARM", "AutoFarm", 2)
bFarm.Size = UDim2.fromOffset(54, 46)
local autoFarmRemote = ClientNet.Get("AutoFarm")
local function farmToggle()
	if autoFarmRemote then
		autoFarmRemote:FireServer("Set", player:GetAttribute("AutoFarm") ~= true, nil)
	end
end
bFarm.Activated:Connect(farmToggle)

-- DESPLEGABLE
local drawer = Instance.new("Frame")
drawer.AnchorPoint = Vector2.new(0.5, 0)
drawer.Position = UDim2.new(0.5, 0, 0, 60)
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

-- sección 1: toda la barra de la PC (Perfil, Mochila, Habilidades, Misiones, Mapa, Facción, Ajustes) + Grupo
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
	{ "Perfil", "Character" }, { "Mochila", "Inventory" }, { "Grupo", "Party" }, { "Habilidades", "" },
	{ "Misiones", "" }, { "Mapa", "" }, { "Facción", "" }, { "Ajustes", "" },
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
eventChip.Position = UDim2.new(1, -12, 0, 10)
eventChip.Size = UDim2.fromOffset(190, 28)
eventChip.BackgroundColor3 = theme.Dark
eventChip.BackgroundTransparency = 0.2
eventChip.Font = UITheme.Font
eventChip.TextSize = 12
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
targetPanel.Position = UDim2.new(0.5, 0, 0, 64)
targetPanel.Size = UDim2.fromOffset(210, 46)
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
	local num = UITheme.Text(b, tostring(i), 11, Color3.fromRGB(255, 255, 255), UDim2.fromOffset(6, 3), UDim2.fromOffset(14, 14))
	num.ZIndex = 4
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
makeSlot(1, -54, -54, 76)
makeSlot(2, -148, 0, 58)
makeSlot(3, -105, -105, 58)
makeSlot(4, 0, -148, 58)
makeSlot(5, -118, -208, 44)
makeSlot(6, -62, -208, 44)
makeSlot(7, -6, -208, 44)

-- AUTO (activar/pausar auto-ataque, como la tecla Q) y siguiente objetivo
local autoBtn = cornerButton(-232, 0, 50, Color3.fromRGB(111, 207, 106), "AUTO")
autoBtn.TextSize = 12
autoBtn.TextStrokeTransparency = 1
autoBtn.Activated:Connect(function()
	local had = aliveHum(target) ~= nil
	ensureTarget() -- sin objetivo: marca el más cercano y el auto-ataque ya arranca solo
	if had and AutoAttackRemote then
		AutoAttackRemote:FireServer("Toggle") -- con objetivo: pausa / reanuda (como la tecla Q)
	end
end)
local nextBtn = cornerButton(-232, -58, 50, Color3.fromRGB(235, 235, 240), "OBJ")
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
	farmOnBtn.Text = if farmOn then "ON" else "OFF"
	farmOnBtn.TextColor3 = if farmOn then Color3.fromRGB(155, 240, 154) else Color3.fromRGB(190, 190, 200)
	local curMode = player:GetAttribute("AutoFarmMode")
	for m, b in pairs(modeBtns) do
		b.BackgroundColor3 = if m == curMode or (curMode == nil and m == "Semi") then theme.Secondary else Color3.fromRGB(30, 34, 54)
	end

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
		levelLabel.Text = string.format("Nv. %d  %s", lvl, class.Role)
	end
end)
do
	local lvl = player:GetAttribute("Level")
	if typeof(lvl) == "number" then
		levelLabel.Text = string.format("Nv. %d  %s", lvl, class.Role)
	end
	local sync = ClientNet.Get("RequestSync")
	if sync then
		sync:FireServer() -- pide nivel / XP / vidas actuales
	end
end
