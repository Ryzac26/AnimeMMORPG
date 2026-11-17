--!strict
--[[
    MobileClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MobileClient        (v2.0 · parche 6.108)
    Interfaz de CELULAR / TABLET (solo si Platform.IsMobile(): pantalla táctil sin teclado). En la PC no hace nada.
    Para probarla en Studio: Workspace > atributo ForceMobileUI (booleano) = true  (o el emulador de dispositivos).

    Distribución (pantalla horizontal, referencia 844x380; se escala sola). Arriba a la izquierda queda libre: ahí Roblox pone su menú.
      Arriba centro  retrato con nivel + barras de vida / energía / XP; debajo, el objetivo (baja si hay barra de jefe)
      Arriba der.    íconos Grupo · Misiones · Mochila · Menú, y debajo el chip de arena/evento
      Izq. abajo     joystick de Roblox (libre)
      Abajo centro   BARRA DE MANDO: Ayudantes · FARM (muestra su modo; ▴ abre Semi/Metin/Boss) · AUTO · OBJ, y 🐎 si tienes montura equipada
      Der. abajo     salto de Roblox; poder 1 grande; 2-4 en arco interior; 5-7 en arco exterior (abanico para el pulgar)
    PODERES: anillo dorado = ataque básico (late mientras el auto-ataque está encendido); color de tu facción = técnicas; naranja = poderes mayores
      (recarga de 45 s o más, brillan cuando están listos); verde = Primeros Auxilios. Cada uno muestra su costo de energía, se apaga si no te
      alcanza (vibra y avisa si lo tocas), se vacía de arriba abajo mientras recarga y lanza un destello cuando vuelve a estar listo.
    MENÚ (☰): mosaicos con íconos, se cierra tocando fuera. Incluye "Ocultar HUD" (para capturas y videos; vuelves con el 👁) y Pociones.
    PANTALLA LIMPIA: si pasan 6 s sin tocar nada y sin objetivo, los íconos de arriba y la barra de mando se atenúan (los poderes nunca).
    MIRA: esquinas rojas que laten sobre el enemigo marcado. Con vida baja (menos de 25 %) el borde de la pantalla late en rojo.
    Toca un enemigo para marcarlo. Si usas un poder sin objetivo, marca solo al enemigo más cercano (apuntado automático).
    Cada botón hace lo mismo que su tecla de PC (1-7 / Q / C / B / P / Z / H) hablando con los mismos remotes que HudClient.
    Los botones de PC que otros scripts dibujan (REPORTAR, Maestría, Mercader, carta) se guardan dentro del menú, en "ACCESOS".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
local MountActionRemote = ClientNet.Get("MountAction")

local theme = UITheme.For(player:GetAttribute("Faction"))
local class = PlayerClass.Get(player)

local REF_W, REF_H = 844, 380
local TARGET_RANGE = 70 -- studs: apuntado automático
local IDLE_FADE_AFTER = 6 -- segundos sin tocar nada para atenuar la parte secundaria
local ULT_COOLDOWN = 45 -- recarga (s) desde la cual un poder cuenta como "mayor" (naranja, brilla al estar listo)

local GOLD = Color3.fromRGB(255, 210, 90)
local ULT = Color3.fromRGB(255, 123, 58)
local HEAL = Color3.fromRGB(95, 208, 122)
local OK = Color3.fromRGB(155, 240, 154)
local OK_BG = Color3.fromRGB(24, 60, 30)
local LOW_RING = Color3.fromRGB(100, 112, 140)
local MUTED = Color3.fromRGB(175, 178, 195)

local playerGui = player:WaitForChild("PlayerGui", 10) :: PlayerGui
do
	local old = playerGui:FindFirstChild("MobileMira") -- la mira de una versión anterior de este script (al recargar la interfaz)
	if old then
		old:Destroy()
	end
end

---------------------------------------------------------------------
-- Pantalla y escala
---------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "MobileGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 5
gui.IgnoreGuiInset = false
gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- solo respeta muescas / barra de gestos: arriba al centro y a la derecha Roblox no pone nada, y su menú queda arriba a la izquierda (zona libre)
gui.Parent = playerGui

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

-- todo el HUD cuelga de "hud" (así "Ocultar HUD" lo apaga de una vez); el menú y el botón 👁 cuelgan directo del escenario
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.BackgroundTransparency = 1
hud.Size = UDim2.fromScale(1, 1)
hud.Parent = stage

---------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------
local function round(inst: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if r then UDim.new(0, r) else UDim.new(1, 0)
	c.Parent = inst
end

local function outline(inst: GuiObject, color: Color3, thickness: number, transparency: number?): UIStroke
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = color
	st.Thickness = thickness
	st.Transparency = transparency or 0
	st.Parent = inst
	return st
end

-- botón que se "hunde" al tocarlo (necesita AnchorPoint 0.5, 0.5 para encogerse desde el centro)
local PRESS_IN = TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local function pressable(b: GuiButton, down: number)
	local sc = Instance.new("UIScale")
	sc.Name = "Hundir"
	sc.Parent = b
	b.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			TweenService:Create(sc, PRESS_IN, { Scale = down }):Play()
		end
	end)
	b.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			TweenService:Create(sc, PRESS_OUT, { Scale = 1 }):Play()
		end
	end)
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
	b.Parent = hud
	round(b)
	local gr = Instance.new("UIGradient") -- brillo suave arriba, más oscuro abajo
	gr.Rotation = 90
	gr.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
	gr.Parent = b
	local st = Instance.new("UIStroke")
	st.Name = "Anillo"
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Color = border
	st.Thickness = if size >= 60 then 3 else 2.5
	st.Transparency = 0.05
	st.Parent = b
	return b
end

-- botón cuadrado con emoji (íconos de arriba a la derecha)
local function squareButton(parent: Instance, icon: string, label: string, order: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(40, 40)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.12
	b.AutoButtonColor = false
	b.Text = icon
	b.Font = UITheme.Font
	b.TextSize = 19
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Parent = parent
	b.Name = label
	b.LayoutOrder = order
	round(b, 12)
	local gr = Instance.new("UIGradient")
	gr.Rotation = 90
	gr.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160))
	gr.Parent = b
	outline(b, theme.Primary, 1.5, 0.15)
	return b
end

-- aviso corto sobre la barra de mando ("Sin KI", etc.)
local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(1, -447, 1, -156)
toast.Size = UDim2.fromOffset(170, 24)
toast.BackgroundColor3 = theme.Dark
toast.BackgroundTransparency = 0.1
toast.Font = UITheme.Font
toast.TextSize = 12
toast.TextColor3 = Color3.fromRGB(255, 190, 120)
toast.Text = ""
toast.Visible = false
toast.ZIndex = 12
toast.Parent = hud
round(toast, 12)
outline(toast, Color3.fromRGB(255, 150, 80), 1.5, 0.2)
local toastToken = 0
local function showToast(text: string)
	toastToken += 1
	local my = toastToken
	toast.Text = text
	toast.Visible = true
	task.delay(1.3, function()
		if my == toastToken then
			toast.Visible = false
		end
	end)
end

-- sacudida corta de un botón (poder sin energía)
local homePos: { [GuiObject]: UDim2 } = {}
local shaking: { [GuiObject]: boolean } = {}
local function shake(b: GuiObject)
	if shaking[b] then
		return
	end
	shaking[b] = true
	local home = homePos[b] or b.Position
	task.spawn(function()
		for k = 1, 4 do
			b.Position = home + UDim2.fromOffset(if k % 2 == 1 then -5 else 5, 0)
			task.wait(0.04)
		end
		b.Position = home
		shaking[b] = nil
	end)
end

---------------------------------------------------------------------
-- ARRIBA CENTRO: retrato y barras
---------------------------------------------------------------------
local topLeft = Instance.new("Frame")
topLeft.BackgroundTransparency = 1
topLeft.AnchorPoint = Vector2.new(0.5, 0)
topLeft.Position = UDim2.new(0.5, 0, 0, 8)
topLeft.Size = UDim2.fromOffset(300, 56)
topLeft.Parent = hud

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

-- borde rojo que late cuando te queda poca vida
local vignette = Instance.new("Frame")
vignette.Name = "VidaBaja"
vignette.BackgroundTransparency = 1
vignette.Position = UDim2.fromOffset(14, 14)
vignette.Size = UDim2.new(1, -28, 1, -28)
vignette.Active = false
vignette.Parent = hud
round(vignette, 26)
local vignetteStroke = Instance.new("UIStroke")
vignetteStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
vignetteStroke.Color = Color3.fromRGB(225, 30, 30)
vignetteStroke.Thickness = 20
vignetteStroke.Transparency = 1
vignetteStroke.Parent = vignette

---------------------------------------------------------------------
-- ARRIBA DERECHA: íconos (Grupo · Misiones · Mochila · Menú) y chip de evento. Grupo canvas = se atenúa solo.
---------------------------------------------------------------------
local autoFarmRemote = ClientNet.Get("AutoFarm")
local function farmToggle()
	if autoFarmRemote then
		autoFarmRemote:FireServer("Set", player:GetAttribute("AutoFarm") ~= true, nil)
	end
end

local topGroup = Instance.new("CanvasGroup")
topGroup.BackgroundTransparency = 1
topGroup.AnchorPoint = Vector2.new(1, 0)
topGroup.Position = UDim2.new(1, -9, 0, 5)
topGroup.Size = UDim2.fromOffset(184, 82)
topGroup.Parent = hud

local menuRow = Instance.new("Frame")
menuRow.BackgroundTransparency = 1
menuRow.Position = UDim2.fromOffset(3, 3)
menuRow.Size = UDim2.fromOffset(178, 40)
menuRow.Parent = topGroup
local menuLayout = Instance.new("UIListLayout")
menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
menuLayout.FillDirection = Enum.FillDirection.Horizontal
menuLayout.Padding = UDim.new(0, 6)
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
menuLayout.Parent = menuRow

local eventChip = Instance.new("TextLabel")
eventChip.Position = UDim2.fromOffset(3, 49)
eventChip.Size = UDim2.fromOffset(178, 24)
eventChip.BackgroundColor3 = theme.Dark
eventChip.BackgroundTransparency = 0.2
eventChip.Font = UITheme.Font
eventChip.TextSize = 11
eventChip.TextColor3 = Color3.new(1, 1, 1)
eventChip.Text = "Evento --"
eventChip.Parent = topGroup
round(eventChip, 12)
local eventStroke = outline(eventChip, Color3.fromRGB(110, 110, 125), 1)

---------------------------------------------------------------------
-- MENÚ (☰): mosaicos con íconos. Cuelga del escenario (no de "hud") para poder abrirse siempre.
---------------------------------------------------------------------
local launcher = Instance.new("Frame")
launcher.Name = "Menu"
launcher.BackgroundTransparency = 1
launcher.Size = UDim2.fromScale(1, 1)
launcher.Visible = false
launcher.ZIndex = 30
launcher.Parent = stage

local backdrop = Instance.new("TextButton")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.45
backdrop.AutoButtonColor = false
backdrop.Text = ""
backdrop.ZIndex = 30
backdrop.Parent = launcher

local SHEET_W, SHEET_H = 720, 300
local sheet = Instance.new("Frame")
sheet.AnchorPoint = Vector2.new(0.5, 0.5)
sheet.Position = UDim2.fromScale(0.5, 0.5)
sheet.Size = UDim2.fromOffset(SHEET_W, SHEET_H)
sheet.BackgroundColor3 = theme.Dark
sheet.BackgroundTransparency = 0.03
sheet.Active = true -- las pulsaciones sobre la hoja no llegan al fondo (que cierra el menú)
sheet.ZIndex = 31
sheet.Parent = launcher
round(sheet, 16)
outline(sheet, theme.Primary, 2)

local sheetTitle = UITheme.Text(sheet, "MENÚ", 17, theme.Primary, UDim2.fromOffset(18, 12), UDim2.fromOffset(200, 24))
sheetTitle.ZIndex = 32
local sheetSub = UITheme.Text(sheet, string.format("%s · %s", (class :: any).DisplayName, (class :: any).Role), 11, MUTED, UDim2.fromOffset(18, 34), UDim2.fromOffset(300, 16))
sheetSub.ZIndex = 32
sheetSub.TextStrokeTransparency = 1
local sheetClose = Instance.new("TextButton")
sheetClose.AnchorPoint = Vector2.new(1, 0)
sheetClose.Position = UDim2.new(1, -10, 0, 8)
sheetClose.Size = UDim2.fromOffset(40, 40)
sheetClose.BackgroundColor3 = Color3.fromRGB(150, 40, 45)
sheetClose.Text = "✕"
sheetClose.TextColor3 = Color3.new(1, 1, 1)
sheetClose.TextSize = 18
sheetClose.Font = Enum.Font.GothamBold
sheetClose.AutoButtonColor = false
sheetClose.ZIndex = 33
sheetClose.Parent = sheet
round(sheetClose, 12)

local function setLauncher(open: boolean)
	launcher.Visible = open
end
backdrop.Activated:Connect(function()
	setLauncher(false)
end)
sheetClose.Activated:Connect(function()
	setLauncher(false)
end)

local grid = Instance.new("Frame")
grid.BackgroundTransparency = 1
grid.Position = UDim2.fromOffset(16, 58)
grid.Size = UDim2.fromOffset(SHEET_W - 32, 160)
grid.ZIndex = 32
grid.Parent = sheet
local gl = Instance.new("UIGridLayout")
gl.CellSize = UDim2.fromOffset(80, 74)
gl.CellPadding = UDim2.fromOffset(6, 8)
gl.SortOrder = Enum.SortOrder.LayoutOrder
gl.Parent = grid

local function tile(order: number, icon: string, label: string, onUse: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.BackgroundColor3 = theme.Dark:Lerp(Color3.new(1, 1, 1), 0.1)
	b.AutoButtonColor = false
	b.Text = ""
	b.ZIndex = 32
	b.Parent = grid
	round(b, 12)
	outline(b, theme.Primary, 1.5, 0.45)
	local ic = UITheme.Text(b, icon, 26, Color3.new(1, 1, 1), UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 32), Enum.TextXAlignment.Center)
	ic.ZIndex = 33
	ic.TextStrokeTransparency = 1
	local lb = UITheme.Text(b, label, 11, Color3.fromRGB(235, 235, 245), UDim2.fromOffset(2, 42), UDim2.new(1, -4, 0, 26), Enum.TextXAlignment.Center)
	lb.ZIndex = 33
	lb.TextStrokeTransparency = 1
	lb.TextWrapped = true
	lb.TextScaled = true
	local lc = Instance.new("UITextSizeConstraint")
	lc.MaxTextSize = 11
	lc.MinTextSize = 7
	lc.Parent = lb
	b.Activated:Connect(onUse)
	return b
end

local hudHidden = false
local restoreBtn = Instance.new("TextButton") -- 👁: vuelve a mostrar el HUD
restoreBtn.AnchorPoint = Vector2.new(1, 0)
restoreBtn.Position = UDim2.new(1, -12, 0, 8)
restoreBtn.Size = UDim2.fromOffset(40, 40)
restoreBtn.BackgroundColor3 = theme.Dark
restoreBtn.BackgroundTransparency = 0.5
restoreBtn.Text = "👁"
restoreBtn.TextSize = 19
restoreBtn.Font = UITheme.Font
restoreBtn.TextTransparency = 0.3
restoreBtn.AutoButtonColor = false
restoreBtn.Visible = false
restoreBtn.ZIndex = 10
restoreBtn.Parent = stage
round(restoreBtn, 12)
local function setHudHidden(hidden: boolean)
	hudHidden = hidden
	hud.Visible = not hidden
	restoreBtn.Visible = hidden
end
restoreBtn.Activated:Connect(function()
	setHudHidden(false)
end)

-- { ícono, texto, evento de MenuBus }  (misma lista que el menú de HudClient; súmale aquí los nuevos)
local TILES: { { string } } = {
	{ "👤", "Perfil", "Character" }, { "🎒", "Mochila", "Inventory" }, { "⚔️", "Habilidades", "Skills" }, { "🌟", "Talentos", "Talents" },
	{ "📜", "Misiones", "Quests" }, { "👥", "Grupo", "Party" }, { "🏯", "Facción", "Guild" }, { "🐾", "Ayudantes", "Helpers" },
	{ "🐎", "Monturas", "Mounts" }, { "🕳️", "Cuevas", "Dungeons" }, { "🛒", "Tienda", "Tienda" }, { "📊", "Analizador", "Hunt" },
	{ "🧪", "Pociones", "AutoFarmMode" }, { "⚙️", "Ajustes", "Settings" },
}
for k, t in ipairs(TILES) do
	local ev = t[3]
	tile(k, t[1], t[2], function()
		setLauncher(false)
		MenuBus.Fire(ev)
	end)
end
tile(#TILES + 1, "👁", "Ocultar HUD", function()
	setLauncher(false)
	setHudHidden(true)
end)

-- botones de PC que dibujan otros scripts (REPORTAR, Maestría, Mercader, carta): se guardan aquí
local otherTitle = Instance.new("TextLabel")
otherTitle.BackgroundTransparency = 1
otherTitle.Position = UDim2.fromOffset(18, 228)
otherTitle.Size = UDim2.fromOffset(200, 16)
otherTitle.Font = UITheme.Font
otherTitle.TextSize = 12
otherTitle.TextColor3 = theme.Primary
otherTitle.TextXAlignment = Enum.TextXAlignment.Left
otherTitle.Text = "ACCESOS"
otherTitle.Visible = false
otherTitle.ZIndex = 32
otherTitle.Parent = sheet
local otherGrid = Instance.new("Frame")
otherGrid.BackgroundTransparency = 1
otherGrid.Position = UDim2.fromOffset(16, 248)
otherGrid.Size = UDim2.fromOffset(SHEET_W - 32, 40)
otherGrid.ZIndex = 32
otherGrid.Parent = sheet
local og = Instance.new("UIGridLayout")
og.CellSize = UDim2.fromOffset(160, 38)
og.CellPadding = UDim2.fromOffset(8, 6)
og.SortOrder = Enum.SortOrder.LayoutOrder
og.Parent = otherGrid
local function refreshAccess()
	local n = 0
	for _, c in ipairs(otherGrid:GetChildren()) do
		if c:IsA("GuiButton") then
			n += 1
		end
	end
	otherTitle.Visible = n > 0
end
otherGrid.ChildAdded:Connect(refreshAccess)
otherGrid.ChildRemoved:Connect(refreshAccess)

-- íconos de arriba: Grupo · Misiones · Mochila (atajos) y ☰
for i, it in ipairs({ { "👥", "Grupo", "Party" }, { "📜", "Misiones", "Quests" }, { "🎒", "Mochila", "Inventory" } }) do
	local b = squareButton(menuRow, it[1], it[2], i)
	b.Activated:Connect(function()
		setLauncher(false)
		MenuBus.Fire(it[3])
	end)
end
local bMenu = squareButton(menuRow, "", "Menu", 5)
bMenu.BackgroundColor3 = theme.Secondary
bMenu.BackgroundTransparency = 0.05
for k = 0, 2 do -- las 3 líneas
	local bar = Instance.new("Frame")
	bar.Position = UDim2.fromOffset(9, 11 + k * 8)
	bar.Size = UDim2.fromOffset(22, 3)
	bar.BackgroundColor3 = Color3.new(1, 1, 1)
	bar.BorderSizePixel = 0
	bar.Parent = bMenu
	round(bar)
end
bMenu.Activated:Connect(function()
	setLauncher(not launcher.Visible)
end)

---------------------------------------------------------------------
-- OBJETIVO
---------------------------------------------------------------------
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
highlight.Parent = gui

local TARGET_Y, TARGET_Y_BOSS = 68, 118 -- con barra de jefe visible (BossBarClient la pone justo debajo de tu tarjeta) el objetivo baja
local targetPanel = Instance.new("Frame")
targetPanel.AnchorPoint = Vector2.new(0.5, 0)
targetPanel.Position = UDim2.new(0.5, 0, 0, TARGET_Y)
targetPanel.Size = UDim2.fromOffset(220, 46)
targetPanel.BackgroundColor3 = theme.Dark
targetPanel.BackgroundTransparency = 0.2
targetPanel.Visible = false
targetPanel.Parent = hud
round(targetPanel, 12)
outline(targetPanel, Color3.fromRGB(200, 70, 70), 1.5, 0.35)
local tName = UITheme.Text(targetPanel, "", 12, Color3.new(1, 1, 1), UDim2.fromOffset(10, 4), UDim2.fromOffset(160, 16))
tName.TextTruncate = Enum.TextTruncate.AtEnd
local _, setTarget = UITheme.Bar(targetPanel, UDim2.fromOffset(10, 24), UDim2.fromOffset(190, 14), Color3.fromRGB(220, 60, 60), nil, 10)
local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.fromOffset(30, 30)
clearBtn.Position = UDim2.new(1, -34, 0, 0)
clearBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 45)
clearBtn.Text = "✕"
clearBtn.TextColor3 = Color3.new(1, 1, 1)
clearBtn.TextSize = 13
clearBtn.Font = Enum.Font.GothamBold
clearBtn.Parent = targetPanel
round(clearBtn)

-- MIRA: cuatro esquinas rojas sobre el enemigo marcado (BillboardGui: tamaño en píxeles, se ajusta cada cuadro)
local reticle = Instance.new("BillboardGui")
reticle.Name = "MobileMira"
reticle.AlwaysOnTop = true
reticle.LightInfluence = 0
reticle.Size = UDim2.fromOffset(80, 80)
reticle.ResetOnSpawn = false
reticle.Enabled = false
reticle.Parent = playerGui
script.Destroying:Connect(function()
	reticle:Destroy()
end)
local reticleBox = Instance.new("Frame")
reticleBox.AnchorPoint = Vector2.new(0.5, 0.5)
reticleBox.Position = UDim2.fromScale(0.5, 0.5)
reticleBox.Size = UDim2.fromScale(1, 1)
reticleBox.BackgroundTransparency = 1
reticleBox.Parent = reticle
for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
	local ax, ay = c[1], c[2]
	local hBar = Instance.new("Frame")
	hBar.AnchorPoint = Vector2.new(ax, ay)
	hBar.Position = UDim2.fromScale(ax, ay)
	hBar.Size = UDim2.new(0.3, 0, 0, 3)
	hBar.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	hBar.BorderSizePixel = 0
	hBar.Parent = reticleBox
	local vBar = Instance.new("Frame")
	vBar.AnchorPoint = Vector2.new(ax, ay)
	vBar.Position = UDim2.fromScale(ax, ay)
	vBar.Size = UDim2.new(0, 3, 0.3, 0)
	vBar.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
	vBar.BorderSizePixel = 0
	vBar.Parent = reticleBox
end

local target: Model? = nil

local function aliveHum(m: Model?): Humanoid?
	local h = if m and m.Parent then m:FindFirstChildOfClass("Humanoid") else nil
	return if h and h.Health > 0 then h else nil
end

local function clearTarget()
	target = nil
	highlight.Adornee = nil
	targetPanel.Visible = false
	reticle.Enabled = false
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

local function rootPart(m: Model): BasePart?
	local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
	return if r and r:IsA("BasePart") then r else nil
end

local function rootPos(m: Model): Vector3?
	local r = rootPart(m)
	return if r then r.Position else nil
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
-- DERECHA ABAJO: poderes 1-7 en abanico
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

-- costo de energía y recarga de cada ranura (los poderes 1-2 vienen de la clase; 3-6 del catálogo; 7 fijo)
local function costOf(i: number): number
	local s: any = skillOf(i)
	if not s then
		return 0
	end
	local c = if i <= 2 then s.EnergyCost else s.Cost
	return if typeof(c) == "number" then c else 0
end
local function cooldownOf(i: number): number
	local s: any = skillOf(i)
	if not s then
		return 0
	end
	local c = if i <= 2 then s.Cooldown elseif i == 7 then 25 else s.CdPve
	return if typeof(c) == "number" then c else 0
end

type SlotUi = {
	Button: TextButton,
	Ring: UIStroke,
	RingColor: Color3,
	Art: ImageLabel?,
	Cool: Frame,
	Drain: UIGradient,
	CoolText: TextLabel,
	CostChip: Frame?,
	CostText: TextLabel?,
	Ping: Frame,
	PingStroke: UIStroke,
	Glow: Frame?,
	GlowStroke: UIStroke?,
	CostN: number,
	IsUlt: boolean,
	Low: boolean,
	Cooling: boolean,
	LastRem: number,
}
local slotUi: { [number]: SlotUi } = {}

local function useSlot(i: number)
	if os.clock() < (cooldownEnd[i] or 0) then
		return
	end
	local ui = slotUi[i]
	local cost = costOf(i)
	local e = player:GetAttribute("Energy")
	local low = cost > 0 and typeof(e) == "number" and e < cost
	if low and ui then -- sin energía: vibra y avisa (igual se lo pedimos al servidor, que decide)
		shake(ui.Button)
		showToast("Sin " .. theme.Resource)
	end
	-- el poder 7 es una cura propia: no marca enemigos solo por usarlo
	local h: Model? = if i == 7 then (if aliveHum(target) then target else nil) else ensureTarget() -- apuntado automático si no hay objetivo
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
	if not low then
		cooldownEnd[i] = os.clock() + skill.Cooldown
		cooldownLen[i] = skill.Cooldown
	end
	if DealDamageEvent then
		DealDamageEvent:FireServer(tostring(i), h)
	end
end

-- el relleno oscuro de la recarga se vacía de arriba abajo: "rem" = fracción oscura que queda (0..1)
local CLEAR_SEQ = NumberSequence.new(1)
local DARK_SEQ = NumberSequence.new(0.28)
local function setDrain(g: UIGradient, rem: number)
	if rem <= 0.004 then
		g.Transparency = CLEAR_SEQ
	elseif rem >= 0.996 then
		g.Transparency = DARK_SEQ
	else
		local edge = 1 - rem
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(edge, 1),
			NumberSequenceKeypoint.new(math.min(edge + 0.003, 0.999), 0.28),
			NumberSequenceKeypoint.new(1, 0.28),
		})
	end
end

local PING_INFO = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local function readyPing(s: SlotUi)
	s.Ping.Size = UDim2.fromScale(1, 1)
	s.Ping.Visible = true
	s.PingStroke.Transparency = 0.05
	TweenService:Create(s.Ping, PING_INFO, { Size = UDim2.fromScale(1.5, 1.5) }):Play()
	TweenService:Create(s.PingStroke, PING_INFO, { Transparency = 1 }):Play()
end

local function applyLow(s: SlotUi)
	if s.Low then
		s.Ring.Color = LOW_RING
		s.Button.BackgroundTransparency = 0.45
		if s.Art then
			s.Art.ImageTransparency = 0.5
		end
		if s.CostChip then
			s.CostChip.BackgroundColor3 = Color3.fromRGB(70, 18, 22)
		end
		if s.CostText then
			s.CostText.TextColor3 = Color3.fromRGB(255, 150, 150)
		end
	else
		s.Ring.Color = s.RingColor
		s.Button.BackgroundTransparency = 0.12
		if s.Art then
			s.Art.ImageTransparency = 0
		end
		if s.CostChip then
			s.CostChip.BackgroundColor3 = Color3.fromRGB(12, 26, 52)
		end
		if s.CostText then
			s.CostText.TextColor3 = Color3.fromRGB(150, 215, 255)
		end
	end
end

local function makeSlot(i: number, ox: number, oy: number, size: number)
	local skill = skillOf(i)
	local cost = costOf(i)
	local isUlt = i >= 3 and i <= 6 and cooldownOf(i) >= ULT_COOLDOWN
	local ringColor = if i == 1 then GOLD elseif i == 7 then HEAL elseif not skill then Color3.fromRGB(95, 95, 110) elseif isUlt then ULT else theme.Primary
	local shown = if skill then skill.Name else "—"
	local b = cornerButton(ox, oy, size, ringColor, "")
	homePos[b] = b.Position
	pressable(b, 0.9)
	local ring = b:FindFirstChild("Anillo") :: UIStroke

	-- brillo de fondo: ataque básico mientras el auto-ataque está encendido; poderes mayores listos
	local glow: Frame? = nil
	local glowStroke: UIStroke? = nil
	if i == 1 or isUlt then
		local g = Instance.new("Frame")
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		g.Size = UDim2.fromScale(1.17, 1.17)
		g.BackgroundTransparency = 1
		g.Visible = false
		g.Parent = b
		round(g)
		glowStroke = outline(g, ringColor, 3, 0.5)
		glow = g
	end

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

	-- recarga: velo oscuro que se vacía de arriba abajo
	local cool = Instance.new("Frame")
	cool.Size = UDim2.fromScale(1, 1)
	cool.BackgroundColor3 = Color3.new(0, 0, 0)
	cool.BackgroundTransparency = 0
	cool.BorderSizePixel = 0
	cool.Visible = false
	cool.ZIndex = 5
	cool.Parent = b
	round(cool)
	local drain = Instance.new("UIGradient")
	drain.Rotation = 90
	drain.Transparency = DARK_SEQ
	drain.Parent = cool
	local ct = UITheme.Text(b, "", 16, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.25), UDim2.fromScale(1, 0.5), Enum.TextXAlignment.Center)
	ct.ZIndex = 6

	-- costo de energía (chip abajo)
	local chip: Frame? = nil
	local chipText: TextLabel? = nil
	if cost > 0 then
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 1)
		c.Position = UDim2.new(0.5, 0, 1, 2)
		c.Size = UDim2.fromOffset(if size >= 60 then 32 else 26, 13)
		c.BackgroundColor3 = Color3.fromRGB(12, 26, 52)
		c.BorderSizePixel = 0
		c.ZIndex = 7
		c.Parent = b
		round(c, 7)
		outline(c, Color3.fromRGB(74, 122, 176), 1, 0.2)
		local t = UITheme.Text(c, tostring(math.floor(cost)), 9, Color3.fromRGB(150, 215, 255), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		t.ZIndex = 8
		t.TextStrokeTransparency = 1
		chip, chipText = c, t
	end

	-- destello al volver a estar listo
	local ping = Instance.new("Frame")
	ping.AnchorPoint = Vector2.new(0.5, 0.5)
	ping.Position = UDim2.fromScale(0.5, 0.5)
	ping.Size = UDim2.fromScale(1, 1)
	ping.BackgroundTransparency = 1
	ping.Visible = false
	ping.ZIndex = 9
	ping.Parent = b
	round(ping)
	local pingStroke = outline(ping, ringColor:Lerp(Color3.new(1, 1, 1), 0.4), 3, 1)

	if not skill then
		b.BackgroundTransparency = 0.5
	end
	b.Activated:Connect(function()
		useSlot(i)
	end)
	slotUi[i] = {
		Button = b,
		Ring = ring,
		RingColor = ringColor,
		Art = art,
		Cool = cool,
		Drain = drain,
		CoolText = ct,
		CostChip = chip,
		CostText = chipText,
		Ping = ping,
		PingStroke = pingStroke,
		Glow = glow,
		GlowStroke = glowStroke,
		CostN = cost,
		IsUlt = isUlt,
		Low = false,
		Cooling = false,
		LastRem = -1,
	}
end

-- poder 1 grande (básico), 2-4 en arco interior, 5-7 en arco exterior
makeSlot(1, 0, 0, 88)
makeSlot(2, -86, 0, 56)
makeSlot(3, -61, -61, 56)
makeSlot(4, 0, -86, 56)
makeSlot(5, -131, 54, 48)
makeSlot(6, -131, -54, 48)
makeSlot(7, -54, -131, 48)

---------------------------------------------------------------------
-- ABAJO CENTRO: barra de mando  Ayudantes · FARM · AUTO · OBJ  (+ 🐎 con montura equipada)
---------------------------------------------------------------------
local DOCK_X = -447 -- centro de la barra, medido desde el borde derecho (entre el joystick y las habilidades)
local dockGroup = Instance.new("CanvasGroup") -- grupo con lienzo: se atenúa entero cuando no haces nada
dockGroup.BackgroundTransparency = 1
dockGroup.AnchorPoint = Vector2.new(0.5, 1)
dockGroup.Position = UDim2.new(1, DOCK_X, 1, -6)
dockGroup.Size = UDim2.fromOffset(376, 90)
dockGroup.Parent = hud

local dock = Instance.new("Frame")
dock.Position = UDim2.fromOffset(63, 29)
dock.Size = UDim2.fromOffset(250, 58)
dock.BackgroundColor3 = theme.Dark
dock.BackgroundTransparency = 0.12
dock.Parent = dockGroup
round(dock, 29)
outline(dock, theme.Primary, 2, 0.1)

local DOCK_BTN = theme.Dark:Lerp(Color3.new(1, 1, 1), 0.1)
local function dockButton(x: number, w: number, icon: string, label: string): (TextButton, TextLabel, TextLabel)
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromOffset(x + w / 2, 29)
	b.Size = UDim2.fromOffset(w, 46)
	b.BackgroundColor3 = DOCK_BTN
	b.AutoButtonColor = false
	b.Text = ""
	b.Parent = dock
	round(b, 23)
	outline(b, theme.Primary, 1.5, 0.3)
	pressable(b, 0.92)
	local ic = UITheme.Text(b, icon, 18, Color3.new(1, 1, 1), UDim2.fromOffset(0, 3), UDim2.new(1, 0, 0, 22), Enum.TextXAlignment.Center)
	ic.TextStrokeTransparency = 1
	local lb = UITheme.Text(b, label, 9, Color3.fromRGB(225, 225, 235), UDim2.fromOffset(0, 27), UDim2.new(1, 0, 0, 14), Enum.TextXAlignment.Center)
	lb.TextStrokeTransparency = 1
	return b, ic, lb
end

local bHelpers = dockButton(11, 46, "🐾", "AYUD")
bHelpers.Activated:Connect(function()
	MenuBus.Fire("Helpers") -- abre la ventana de ayudantes de combate
end)
local bFarm, _, farmLabel = dockButton(65, 66, "⚔️", "FARM · SEMI")
bFarm.Activated:Connect(farmToggle)
local bAuto, _, _ = dockButton(139, 46, "🎯", "AUTO")
bAuto.Activated:Connect(function()
	local had = aliveHum(target) ~= nil
	ensureTarget() -- sin objetivo: marca el más cercano y el auto-ataque ya arranca solo
	if had and AutoAttackRemote then
		AutoAttackRemote:FireServer("Toggle") -- con objetivo: pausa / reanuda (como la tecla Q)
	end
end)
local bNext = dockButton(193, 46, "🔄", "OBJ")
bNext.Activated:Connect(function()
	local list = candidates()
	if #list == 0 then
		return
	end
	local idx = table.find(list, target :: any)
	setTargetModel(list[((idx or 0) % #list) + 1])
end)

-- montura (la tecla H de la PC): solo aparece con una montura equipada
local bMount = Instance.new("TextButton")
bMount.AnchorPoint = Vector2.new(0.5, 0.5)
bMount.Position = UDim2.fromOffset(31, 58)
bMount.Size = UDim2.fromOffset(44, 44)
bMount.BackgroundColor3 = theme.Dark
bMount.BackgroundTransparency = 0.12
bMount.AutoButtonColor = false
bMount.Text = "🐎"
bMount.TextSize = 20
bMount.Font = UITheme.Font
bMount.Visible = false
bMount.Parent = dockGroup
round(bMount)
local mountStroke = outline(bMount, theme.Primary, 2, 0.15)
pressable(bMount, 0.92)
bMount.Activated:Connect(function()
	if MountActionRemote then
		MountActionRemote:FireServer("Toggle")
	end
end)

-- modos de AutoFarm: se abren con la pestaña MODO ▴ y se cierran solos (5 s) o al elegir uno
local farmStatus = Instance.new("TextLabel")
farmStatus.Position = UDim2.fromOffset(196, 9)
farmStatus.Size = UDim2.fromOffset(118, 18)
farmStatus.BackgroundTransparency = 1
farmStatus.Font = UITheme.Font
farmStatus.TextSize = 10
farmStatus.TextColor3 = OK
farmStatus.TextXAlignment = Enum.TextXAlignment.Left
farmStatus.TextTruncate = Enum.TextTruncate.AtEnd
farmStatus.TextStrokeTransparency = 0.4
farmStatus.Text = ""
farmStatus.Parent = dockGroup

local modeTab = Instance.new("TextButton")
modeTab.Position = UDim2.fromOffset(133, 6)
modeTab.Size = UDim2.fromOffset(58, 22)
modeTab.BackgroundColor3 = theme.Dark
modeTab.BackgroundTransparency = 0.15
modeTab.AutoButtonColor = false
modeTab.Font = UITheme.Font
modeTab.TextSize = 10
modeTab.TextColor3 = theme.Primary
modeTab.Text = "MODO ▴"
modeTab.Parent = dockGroup
round(modeTab, 11)
outline(modeTab, theme.Primary, 1.5, 0.35)

local modePop = Instance.new("Frame")
modePop.AnchorPoint = Vector2.new(0.5, 1)
modePop.Position = UDim2.new(1, DOCK_X - 27, 1, -102)
modePop.Size = UDim2.fromOffset(216, 46)
modePop.BackgroundColor3 = theme.Dark
modePop.BackgroundTransparency = 0.06
modePop.Visible = false
modePop.ZIndex = 11
modePop.Parent = hud
round(modePop, 16)
outline(modePop, theme.Primary, 2, 0.1)
local popLayout = Instance.new("UIListLayout")
popLayout.FillDirection = Enum.FillDirection.Horizontal
popLayout.SortOrder = Enum.SortOrder.LayoutOrder
popLayout.Padding = UDim.new(0, 6)
popLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
popLayout.VerticalAlignment = Enum.VerticalAlignment.Center
popLayout.Parent = modePop
local popToken = 0
local function setModePop(open: boolean)
	popToken += 1
	modePop.Visible = open
	modeTab.Text = if open then "MODO ▾" else "MODO ▴"
	if open then
		local my = popToken
		task.delay(5, function()
			if my == popToken then
				modePop.Visible = false
				modeTab.Text = "MODO ▴"
			end
		end)
	end
end
modeTab.Activated:Connect(function()
	setModePop(not modePop.Visible)
end)
local modeChips: { [string]: TextButton } = {}
for k, def in ipairs({ { "Semi", "SEMI" }, { "Metin", "METIN" }, { "Jefe", "BOSS" } }) do
	local mode, label = def[1], def[2]
	local chip = Instance.new("TextButton")
	chip.LayoutOrder = k
	chip.Size = UDim2.fromOffset(62, 34)
	chip.BackgroundColor3 = theme.Dark
	chip.BackgroundTransparency = 0.12
	chip.AutoButtonColor = false
	chip.Font = UITheme.Font
	chip.TextSize = 12
	chip.TextColor3 = Color3.new(1, 1, 1)
	chip.Text = label
	chip.ZIndex = 12
	chip.Parent = modePop
	round(chip, 12)
	local cst = outline(chip, theme.Primary, 1.5, 0.5)
	cst.Name = "Borde"
	chip.Activated:Connect(function()
		if autoFarmRemote then
			autoFarmRemote:FireServer("Set", "keep", mode) -- cambia de modo sin apagar / encender (igual que el panel de la PC)
		end
		setModePop(false)
	end)
	modeChips[mode] = chip
end

---------------------------------------------------------------------
-- AJUSTES PARA CELULAR DE LO QUE DIBUJAN OTROS SCRIPTS
--  1) Los botones flotantes de PC (REPORTAR, Maestría [N], Mercader [V], Carta) se guardan dentro del Menú (ACCESOS).
--  2) Toda ventana "Ventana" (NpcKit.Window) se encoge para caber en la pantalla y su X se agranda para el dedo.
---------------------------------------------------------------------
local PC_BUTTONS = { "REPORTAR", "Maestría", "Mercader", "✉" }
local function adopt(b: TextButton)
	b.Parent = otherGrid
	b.AnchorPoint = Vector2.zero
	b.ZIndex = 33
	b.TextSize = 13
	b.Text = string.gsub(b.Text, "%s*%[%a%]", "")
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 34
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

-- la barra de jefe (BossBarClient) cuelga de su propia pantalla; si está a la vista, el panel del objetivo baja un poco
local bossPanel: Frame? = nil
local function bossVisible(): boolean
	if not bossPanel or not bossPanel.Parent then
		local g = playerGui:FindFirstChild("BossBarGui")
		bossPanel = if g then g:FindFirstChildOfClass("Frame") else nil
	end
	return bossPanel ~= nil and bossPanel.Visible
end

-- pantalla limpia: cualquier toque reinicia el reloj
local lastActive = os.clock()
UserInputService.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		lastActive = os.clock()
	end
end)
local fade = 0
local targetPanelY = TARGET_Y

RunService.RenderStepped:Connect(function(dt: number)
	local now = os.clock()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		setHp(hum.Health, hum.MaxHealth)
		local frac = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
		if hum.Health > 0 and frac < 0.25 then
			vignetteStroke.Transparency = 0.8 + 0.12 * math.sin(now * 5)
		else
			vignetteStroke.Transparency = 1
		end
	end
	local e, me = player:GetAttribute("Energy"), player:GetAttribute("MaxEnergy")
	if typeof(e) == "number" and typeof(me) == "number" then
		setEnergy(e, me)
	end

	-- poderes
	local autoOn = player:GetAttribute("AutoAttack") == true
	for i, s in pairs(slotUi) do
		local left = (cooldownEnd[i] or 0) - now
		if left > 0 then
			if not s.Cooling then
				s.Cooling = true
				s.Cool.Visible = true
				s.LastRem = -1
			end
			local rem = math.clamp(left / (cooldownLen[i] or 1), 0, 1)
			if math.abs(rem - s.LastRem) > 0.008 then
				s.LastRem = rem
				setDrain(s.Drain, rem)
			end
			s.CoolText.Text = if left >= 10 then string.format("%d", left) else string.format("%.1f", left)
		elseif s.Cooling then
			s.Cooling = false
			s.Cool.Visible = false
			s.CoolText.Text = ""
			readyPing(s)
		end
		local low = s.CostN > 0 and typeof(e) == "number" and e < s.CostN
		if low ~= s.Low then
			s.Low = low
			applyLow(s)
		end
		local g, gs = s.Glow, s.GlowStroke
		if g and gs then
			local want = if i == 1 then autoOn else (s.IsUlt and not s.Cooling and not s.Low)
			g.Visible = want
			if want then
				gs.Transparency = 0.35 + 0.3 * math.sin(now * 4 + i)
			end
		end
	end

	-- objetivo + mira
	local th = aliveHum(target)
	if th and target then
		targetPanel.Visible = true
		tName.Text = tostring(target:GetAttribute("DisplayName") or target.Name)
		setTarget(th.Health, th.MaxHealth)
		local wantY = if bossVisible() then TARGET_Y_BOSS else TARGET_Y
		if wantY ~= targetPanelY then
			targetPanelY = wantY
			targetPanel.Position = UDim2.new(0.5, 0, 0, wantY)
		end
		local root = rootPart(target)
		local cam = Workspace.CurrentCamera
		if root and cam and not hudHidden then
			if reticle.Adornee ~= root then
				reticle.Adornee = root
			end
			local dist = math.max((cam.CFrame.Position - root.Position).Magnitude, 1)
			local ext = target:GetExtentsSize()
			local px = cam.ViewportSize.Y / (2 * math.tan(math.rad(cam.FieldOfView) / 2) * dist) * math.max(ext.X, ext.Y, 2)
			px = math.clamp(px * 1.15, 60, 170)
			reticle.Size = UDim2.fromOffset(px, px)
			local k = 1 + 0.07 * math.sin(now * 6)
			reticleBox.Size = UDim2.fromScale(k, k)
			reticle.Enabled = true
		else
			reticle.Enabled = false
		end
	elseif target then
		clearTarget()
	else
		reticle.Enabled = false
	end

	-- barra de mando
	local farmOn = player:GetAttribute("AutoFarm") == true
	bAuto.BackgroundColor3 = if autoOn then OK_BG else DOCK_BTN
	bFarm.BackgroundColor3 = if farmOn then OK_BG else DOCK_BTN
	local curMode = player:GetAttribute("AutoFarmMode")
	local modeName = if typeof(curMode) == "string" then curMode else "Semi"
	local modeText = if modeName == "Jefe" then "BOSS" else string.upper(modeName)
	farmLabel.Text = "FARM · " .. modeText
	farmLabel.TextColor3 = if farmOn then OK else Color3.fromRGB(225, 225, 235)
	for m, chip in pairs(modeChips) do
		local sel = m == modeName
		chip.BackgroundColor3 = if sel then theme.Secondary else theme.Dark
		chip.BackgroundTransparency = if sel then 0.02 else 0.18
		chip.TextColor3 = if sel then Color3.new(1, 1, 1) else Color3.fromRGB(190, 192, 205)
		local cs = chip:FindFirstChild("Borde")
		if cs and cs:IsA("UIStroke") then
			cs.Transparency = if sel then 0 else 0.55
		end
	end
	local fst = player:GetAttribute("AutoFarmStatus")
	farmStatus.Text = if farmOn then (modeText .. (if typeof(fst) == "string" and fst ~= "" then " · " .. fst else "")) else ""

	-- montura
	local eq = player:GetAttribute("MountEquipped")
	bMount.Visible = typeof(eq) == "string" and eq ~= ""
	mountStroke.Color = if player:GetAttribute("Mounted") == true then OK else theme.Primary

	-- pantalla limpia: se atenúan los íconos de arriba y la barra de mando si llevas 6 s sin tocar y sin objetivo
	local calm = (now - lastActive) > IDLE_FADE_AFTER and th == nil and not launcher.Visible
	local goal = if calm then 0.55 else 0
	if math.abs(goal - fade) > 0.005 then
		fade += (goal - fade) * math.min(1, dt * 6)
		topGroup.GroupTransparency = fade
		dockGroup.GroupTransparency = fade
	end

	local state = Workspace:GetAttribute("EventState")
	local cd = Workspace:GetAttribute("EventCountdown")
	if typeof(cd) == "number" then
		if state == "Open" then
			local lives = player:GetAttribute("ArenaLives")
			eventChip.Text = string.format("ARENA %s  ·  Vidas %s", fmtTime(cd), tostring(if typeof(lives) == "number" then lives else "-"))
			eventChip.TextColor3 = OK
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
