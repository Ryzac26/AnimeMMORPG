--!strict
--[[
    HudClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HudClient
    HUD principal con estilo por facción:
      - Panel del jugador (arriba-izquierda): foto, nombre, nivel, rol/personaje, barra de VIDA y barra de KI/CHAKRA/HAKI
      - Barra de XP inferior
      - Barra de PODERES 1-4 con borde de la facción y cooldown; se usan con las teclas 1, 2, 3, 4
        (1 y 2 = habilidades actuales; 3 y 4 = "Próximamente" hasta implementar AbilityService)
      - Panel del OBJETIVO (clic sobre un enemigo lo marca) con nombre, nivel y vida
      - Vidas de arena, cuenta atrás del evento, fragilidad, avisos y números de daño flotantes
    El cliente SOLO muestra y pide acciones; el servidor decide todo.
    IMPORTANTE: desactiva la UI/entrada del HUDManager antiguo para no duplicar.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local PlayerClass = require(Modules:WaitForChild("PlayerClass", 10))
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local PortraitKit = require(script.Parent:WaitForChild("PortraitKit", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local DealDamageEvent = ClientNet.Get("DealDamageEvent")
local AutoAttackRemote = ClientNet.Get("AutoAttack")
local UseAbilityRemote = ClientNet.Get("UseAbility")
local AbilityCatalog = require(Modules:WaitForChild("AbilityCatalog", 10))
local AbilityIcons = require(Modules:WaitForChild("AbilityIcons", 10))
local MOBILE = require(script.Parent:WaitForChild("Platform", 10)).IsMobile() -- en celular la interfaz la dibuja MobileClient

local function listen(name: string, fn: (...any) -> ())
	local r = ClientNet.Get(name)
	if r then
		r.OnClientEvent:Connect(fn)
	end
end

local gui = Instance.new("ScreenGui")
gui.Name = "MainHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local theme = UITheme.For(player:GetAttribute("Faction"))
local root = Instance.new("Frame") -- contenedor que se reconstruye si cambia la facción
root.Size = UDim2.fromScale(1, 1)
root.BackgroundTransparency = 1
root.Visible = not MOBILE -- (panel del jugador y barra de poderes de la PC)
root.Parent = gui

-- referencias actualizables
local setHp: (number, number, string?) -> () = function() end
local setEnergy: (number, number, string?) -> () = function() end
local setXp: (number, number, string?) -> () = function() end
local nameLabel: TextLabel, levelLabel: TextLabel, roleLabel: TextLabel
local slotFrames: { [number]: { Frame: Frame, Cool: Frame, CoolText: TextLabel, Name: TextLabel } } = {}
local cooldownEnd: { [number]: number } = {}
local cooldownLen: { [number]: number } = {}

local currentLevel, currentXp, currentNeed = 1, 0, 1

local function build()
	root:ClearAllChildren()
	theme = UITheme.For(player:GetAttribute("Faction"))
	local class = PlayerClass.Get(player)

	-- PANEL DEL JUGADOR
	-- Zona útil por facción: los marcos con rollos (Shinobi) y cuerdas (Pirata) tapan los bordes, así que el contenido se ajusta al "papel".
	local fk = UITheme.Key(theme)
	local L = {
		PortX = 14, PortY = 14, PortS = 78, LvlY = 94, LvlS = 13,
		NameY = 9, NameS = 19, RoleY = 30, RoleS = 12,
		BarX = 104, BarW = 250, HpY = 48, HpH = 18, EnY = 70, EnH = 18, XpY = 94, XpH = 16,
	}
	if fk == "Shinobi" then
		L = {
			PortX = 20, PortY = 25, PortS = 62, LvlY = 87, LvlS = 11,
			NameY = 20, NameS = 17, RoleY = 38, RoleS = 11,
			BarX = 100, BarW = 244, HpY = 53, HpH = 14, EnY = 69, EnH = 14, XpY = 85, XpH = 14,
		}
	elseif fk == "Pirate" then
		L = {
			PortX = 20, PortY = 18, PortS = 70, LvlY = 91, LvlS = 12,
			NameY = 14, NameS = 18, RoleY = 33, RoleS = 11,
			BarX = 102, BarW = 246, HpY = 50, HpH = 16, EnY = 69, EnH = 16, XpY = 88, XpH = 14,
		}
	end
	local panel = UITheme.Frame(root, theme, UDim2.fromOffset(370, 122), UDim2.fromOffset(14, 14), nil, "panel")
	local accent = UITheme.Accent(theme)
	PortraitKit.Mount(panel, UDim2.fromOffset(L.PortX, L.PortY), UDim2.fromOffset(L.PortS, L.PortS), theme, class.CharacterName)

	-- nivel bajo el retrato
	levelLabel = UITheme.Text(panel, "NIVEL 1", L.LvlS, accent, UDim2.fromOffset(L.PortX, L.LvlY), UDim2.fromOffset(L.PortS, 16), Enum.TextXAlignment.Center)

	-- nombre + personaje y rol
	nameLabel = UITheme.Text(panel, player.DisplayName, L.NameS, accent, UDim2.fromOffset(L.BarX, L.NameY), UDim2.fromOffset(L.BarW, L.NameS + 3))
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	roleLabel = UITheme.Text(panel, string.format("%s · %s", class.CharacterName, class.Role), L.RoleS, Color3.fromRGB(215, 215, 225), UDim2.fromOffset(L.BarX, L.RoleY), UDim2.fromOffset(L.BarW, 14))

	-- barras: vida / energía / XP (bordeadas con el color de la facción)
	local _, hp = UITheme.Bar(panel, UDim2.fromOffset(L.BarX, L.HpY), UDim2.fromOffset(L.BarW, L.HpH), Color3.fromRGB(220, 60, 60), nil, if L.HpH < 16 then 11 else 12, theme.Primary)
	setHp = hp
	local _, en = UITheme.Bar(panel, UDim2.fromOffset(L.BarX, L.EnY), UDim2.fromOffset(L.BarW, L.EnH), theme.ResourceColor, nil, if L.EnH < 16 then 11 else 12, theme.Primary)
	setEnergy = en
	UITheme.Text(panel, theme.Resource, 10, Color3.fromRGB(255, 255, 255), UDim2.fromOffset(L.BarX + 6, L.EnY), UDim2.fromOffset(60, L.EnH)).ZIndex = 5
	local _, xp = UITheme.Bar(panel, UDim2.fromOffset(L.BarX, L.XpY), UDim2.fromOffset(L.BarW, L.XpH), theme.Primary, nil, 11, theme.Primary)
	setXp = xp

	-- BARRA DE PODERES 1-6
	local slotSize, gap = 46, 8
	local totalW = slotSize * 7 + gap * 6
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -60)
	bar.Size = UDim2.fromOffset(totalW + 24, slotSize + 30)
	bar.BackgroundTransparency = 1
	bar.Parent = root
	table.clear(slotFrames)
	for i = 1, 7 do
		local skill: any = if i == 1 then class.PrimarySkill elseif i == 2 then class.SecondarySkill else nil
		if i >= 3 then
			local set = AbilityCatalog[class.CharacterName]
			skill = if set then set[i] else nil -- habilidades 3 y 4 (AbilityCatalog): solo usamos .Name
		end
		if i == 7 then
			skill = { Name = "Primeros Auxilios" }
		end
		local f = Instance.new("Frame")
		f.Position = UDim2.fromOffset(12 + (i - 1) * (slotSize + gap), 0)
		f.Size = UDim2.fromOffset(slotSize, slotSize)
		f.BackgroundColor3 = theme.Dark
		f.BorderSizePixel = 0
		f.Parent = bar
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = f
		UITheme.Border(f, theme, 3)
		local icon = UITheme.Text(f, if skill then string.sub(skill.Name, 1, 2):upper() else "🔒", 15, theme.Primary, UDim2.fromScale(0, 0.1), UDim2.fromScale(1, 0.6), Enum.TextXAlignment.Center)
		icon.TextStrokeTransparency = 0.3
		-- icono real del poder (láminas de AbilityIcons); si aún no hay ID, quedan las 2 letras
		local art = AbilityIcons.Make(f, if i == 7 then "General/7" else class.CharacterName .. "/" .. i)
		if art then
			icon.Visible = false
			Instance.new("UICorner", art).CornerRadius = UDim.new(0, 10)
		end
		local num = UITheme.Text(f, KeyBinds.Label("Poder" .. i), 12, Color3.new(1, 1, 1), UDim2.fromOffset(4, 1), UDim2.fromOffset(14, 14))
		num.ZIndex = 4
		KeyBinds.Changed:Connect(function(id: string)
			if id == "Poder" .. i then
				num.Text = KeyBinds.Label(id)
			end
		end)
		local nm = UITheme.Text(bar, if skill then skill.Name else "Próximamente", 10, Color3.fromRGB(230, 230, 235), UDim2.fromOffset(12 + (i - 1) * (slotSize + gap) - 6, slotSize + 2), UDim2.fromOffset(slotSize + 12, 26), Enum.TextXAlignment.Center)
		nm.TextWrapped = true
		nm.TextYAlignment = Enum.TextYAlignment.Top
		local cool = Instance.new("Frame")
		cool.Size = UDim2.fromScale(1, 0)
		cool.BackgroundColor3 = Color3.new(0, 0, 0)
		cool.BackgroundTransparency = 0.35
		cool.BorderSizePixel = 0
		cool.ZIndex = 5
		cool.Parent = f
		local cc = Instance.new("UICorner")
		cc.CornerRadius = UDim.new(0, 10)
		cc.Parent = cool
		local ct = UITheme.Text(f, "", 15, nil, UDim2.fromScale(0, 0.25), UDim2.fromScale(1, 0.5), Enum.TextXAlignment.Center)
		ct.ZIndex = 6
		slotFrames[i] = { Frame = f, Cool = cool, CoolText = ct, Name = nm }
		if not skill then
			f.BackgroundTransparency = 0.5
		end
	end
end
build()

---------------------------------------------------------------------
-- BARRA DE MENÚ (abajo): clic en una opción abre su ventana
---------------------------------------------------------------------
local say: (string) -> () = function() end -- se define más abajo
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local pal = NpcKit.Palette(theme)
local MENU = {
	{ "Perfil", "Perfil", "Character" }, { "Mochila", "Mochila", "Inventory" }, { "Tienda", "", "Tienda" }, { "Habilidades", "", "Skills" }, { "Misiones", "", "Quests" },
	{ "Facción", "Faccion", "Guild" }, { "Mascota", "", "Pets" }, { "Talentos", "", "Talents" }, { "Monturas", "", "Mounts" }, { "Ajustes", "", "Settings" },
}
local BTN_W, BTN_H, GAP = 88, 30, 6
local BAR_W = #MENU * BTN_W + (#MENU - 1) * GAP + 24
-- contenedor que se desliza hacia abajo (la flecha de arriba queda siempre a la vista)
local menuHolder = Instance.new("Frame")
menuHolder.Name = "MenuHolder"
menuHolder.AnchorPoint = Vector2.new(0.5, 1)
menuHolder.Position = UDim2.new(0.5, 0, 1, -8)
menuHolder.Size = UDim2.fromOffset(BAR_W, 46)
menuHolder.BackgroundTransparency = 1
menuHolder.Visible = not MOBILE
menuHolder.Parent = gui
local menuBar = Instance.new("Frame")
menuBar.Name = "MenuBar"
menuBar.Size = UDim2.fromScale(1, 1)
menuBar.BackgroundColor3 = pal.Bg
menuBar.BorderSizePixel = 0
menuBar.ZIndex = 9
menuBar.Parent = menuHolder
Instance.new("UICorner", menuBar).CornerRadius = UDim.new(0, 8)
local barStroke = Instance.new("UIStroke")
barStroke.Color = pal.Edge
barStroke.Thickness = 2
barStroke.Parent = menuBar
local menuRow = Instance.new("Frame")
menuRow.Name = "Botones"
menuRow.BackgroundTransparency = 1
menuRow.Size = UDim2.fromScale(1, 1)
menuRow.ZIndex = 10
menuRow.Parent = menuBar
local menuLayout = Instance.new("UIListLayout")
menuLayout.FillDirection = Enum.FillDirection.Horizontal
menuLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
menuLayout.VerticalAlignment = Enum.VerticalAlignment.Center
menuLayout.Padding = UDim.new(0, GAP)
menuLayout.Parent = menuRow
for _, m in ipairs(MENU) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(BTN_W, BTN_H)
	b.BackgroundColor3 = pal.TabOff
	local function setText()
		b.Text = if m[2] ~= "" then string.format("%s [%s]", m[1], KeyBinds.Label(m[2])) else m[1]
	end
	setText()
	KeyBinds.Changed:Connect(function(id: string)
		if id == m[2] then
			setText()
		end
	end)
	b.TextColor3 = pal.TabOffText
	b.TextTransparency = if m[3] ~= "" then 0 else 0.45
	b.Font = UITheme.Font
	b.TextSize = 12
	b.AutoButtonColor = true
	b.ZIndex = 11
	b.Parent = menuRow
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	local bs = Instance.new("UIStroke")
	bs.Color = pal.Edge2
	bs.Transparency = if m[3] ~= "" then 0.1 else 0.55
	bs.Thickness = 1
	bs.Parent = b
	b.Activated:Connect(function()
		if m[3] ~= "" then
			MenuBus.Fire(m[3])
		else
			say(m[1] .. ": próximamente")
		end
	end)
end
-- flecha central: oculta / muestra la barra
local arrow = Instance.new("TextButton")
arrow.Name = "Flecha"
arrow.AnchorPoint = Vector2.new(0.5, 1)
arrow.Position = UDim2.new(0.5, 0, 0, -2)
arrow.Size = UDim2.fromOffset(54, 18)
arrow.BackgroundColor3 = pal.Bg
arrow.BorderSizePixel = 0
arrow.Text = "▼"
arrow.TextColor3 = pal.Accent
arrow.Font = UITheme.Font
arrow.TextSize = 12
arrow.ZIndex = 12
arrow.Parent = menuHolder
Instance.new("UICorner", arrow).CornerRadius = UDim.new(0, 6)
local arrowStroke = Instance.new("UIStroke")
arrowStroke.Color = pal.Edge
arrowStroke.Thickness = 2
arrowStroke.Parent = arrow
local barHidden = false
arrow.Activated:Connect(function()
	barHidden = not barHidden
	arrow.Text = if barHidden then "▲" else "▼"
	TweenService:Create(menuHolder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = if barHidden then UDim2.new(0.5, 0, 1, 46) else UDim2.new(0.5, 0, 1, -8),
	}):Play()
end)

---------------------------------------------------------------------
-- OBJETIVO (clic en un enemigo)
---------------------------------------------------------------------
local target: Model? = nil
local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
highlight.Parent = gui

local targetPanel = UITheme.Frame(gui, theme, UDim2.fromOffset(300, 56), UDim2.new(0.5, 0, 0, 14), Vector2.new(0.5, 0))
targetPanel.Visible = false
local tName = UITheme.Text(targetPanel, "", 15, nil, UDim2.fromOffset(12, 5), UDim2.fromOffset(276, 20), Enum.TextXAlignment.Center)
local _, setTarget = UITheme.Bar(targetPanel, UDim2.fromOffset(12, 28), UDim2.fromOffset(276, 18), Color3.fromRGB(220, 60, 60))

-- X: quita el objetivo (también apaga el auto-ataque hacia él)
local clearBtn = Instance.new("TextButton")
clearBtn.Name = "QuitarObjetivo"
clearBtn.Size = UDim2.fromOffset(20, 20)
clearBtn.Position = UDim2.new(1, -24, 0, 4)
clearBtn.BackgroundColor3 = Color3.fromRGB(150, 40, 45)
clearBtn.Text = "✕"
clearBtn.TextColor3 = Color3.new(1, 1, 1)
clearBtn.TextSize = 13
clearBtn.Font = Enum.Font.GothamBold
clearBtn.AutoButtonColor = true
clearBtn.ZIndex = 20
clearBtn.Parent = targetPanel
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(1, 0)
local function clearTarget()
	target = nil
	highlight.Adornee = nil
	targetPanel.Visible = false
	if AutoAttackRemote then
		AutoAttackRemote:FireServer("Clear")
	end
end
clearBtn.Activated:Connect(clearTarget)

local function modelFromPart(part: Instance?): Model?
	local m = if part then part:FindFirstAncestorOfClass("Model") else nil
	while m and not CollectionService:HasTag(m, "Targetable") do
		m = m:FindFirstAncestorOfClass("Model")
	end
	return m
end

local mouse = player:GetMouse()

-- Elige el objetivo bajo el cursor. Si algo invisible (efectos, adornos) tapa al enemigo y el clic no lo alcanza,
-- se busca el enemigo "Targetable" más cercano a la cámara cuyo cuerpo cae bajo el cursor en pantalla.
local function pickTarget(): Model?
	local direct = modelFromPart(mouse.Target)
	if direct and direct ~= player.Character and not direct:GetAttribute("Boss") then
		return direct
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return direct
	end
	-- si el clic cayó en el cuerpo gigante del jefe, cualquier enemigo más pequeño bajo el cursor tiene prioridad
	local best: Model? = direct
	local bestDepth = math.huge
	local cursor = Vector2.new(mouse.X, mouse.Y)
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and inst ~= player.Character and inst ~= direct then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst.PrimaryPart or inst:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				local depth = (cam.CFrame.Position - root.Position).Magnitude
				if depth < bestDepth and depth < 250 and not inst:GetAttribute("Boss") then
					local screen, onScreen = cam:WorldToViewportPoint(root.Position)
					if onScreen and screen.Z > 0 then
						local size = inst:GetExtentsSize()
						local radius = math.max(26, (math.max(size.X, size.Z) * 0.5) * (cam.ViewportSize.Y / (2 * screen.Z * math.tan(math.rad(cam.FieldOfView) / 2))))
						if (Vector2.new(screen.X, screen.Y) - cursor).Magnitude <= radius then
							best, bestDepth = inst, depth
						end
					end
				end
			end
		end
	end
	return best
end
listen("AbilityCooldown", function(slot: any, seconds: any)
	if typeof(slot) == "number" and typeof(seconds) == "number" then
		cooldownEnd[slot] = if seconds > 0 then os.clock() + seconds else 0
		cooldownLen[slot] = math.max(seconds, 1)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local m = pickTarget()
		if m and m ~= player.Character then
			target = m
			highlight.Adornee = m
			if AutoAttackRemote then
				AutoAttackRemote:FireServer("Target", m) -- empieza el auto-ataque
			end
		end
	end
end)

---------------------------------------------------------------------
-- PODERES 1-4
---------------------------------------------------------------------
local function slotOf(input: InputObject): number?
	for i = 1, 7 do
		if KeyBinds.Matches(input, "Poder" .. i) then
			return i
		end
	end
	return nil
end

local function useSlot(i: number)
	if i > 2 then
		if os.clock() < (cooldownEnd[i] or 0) then
			return
		end
		local h = target
		if not h or not h.Parent then
			h = pickTarget()
		end
		if UseAbilityRemote then
			UseAbilityRemote:FireServer(i, h) -- el servidor valida y responde con AbilityCooldown
		end
		return
	end
	local class = PlayerClass.Get(player)
	local skill = if i == 1 then class.PrimarySkill else class.SecondarySkill
	local now = os.clock()
	if now < (cooldownEnd[i] or 0) then
		return
	end
	local hint = target
	if not hint or not hint.Parent then
		hint = pickTarget()
	end
	cooldownEnd[i] = now + skill.Cooldown
	cooldownLen[i] = skill.Cooldown
	if DealDamageEvent then
		DealDamageEvent:FireServer(tostring(i), hint)
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if KeyBinds.Matches(input, "AutoAtaque") and AutoAttackRemote then
		AutoAttackRemote:FireServer("Toggle") -- pausa / reanuda el auto-ataque
		return
	end
	local slot = slotOf(input)
	if slot then
		useSlot(slot)
	end
end)

---------------------------------------------------------------------
-- ESTADO DEL EVENTO / ARENA / AVISOS
---------------------------------------------------------------------
local topRight = Instance.new("Frame")
topRight.AnchorPoint = Vector2.new(1, 0)
topRight.Position = UDim2.new(1, -14, 0, 14)
topRight.Size = UDim2.fromOffset(240, 96)
topRight.BackgroundTransparency = 1
topRight.Visible = not MOBILE
topRight.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
layout.Parent = topRight

local function chip(): TextLabel
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromOffset(240, 28)
	t.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	t.BackgroundTransparency = 0.2
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = UITheme.Font
	t.TextSize = 14
	t.Parent = topRight
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = t
	UITheme.Border(t, theme, 2)
	return t
end
local eventChip, arenaChip, fragChip = chip(), chip(), chip()
fragChip.Visible = false
eventChip.Text = "Evento: --"
arenaChip.Text = "Vidas de arena: 3"

-- AVISOS: pila de mensajes (hasta 4 a la vez). Los repetidos se juntan con "x2". Los de equipo Épico o mejor duran más y llevan su color.
local noticeStack = Instance.new("Frame")
noticeStack.AnchorPoint = Vector2.new(0.5, 0)
noticeStack.Position = if MOBILE then UDim2.new(0.5, 0, 0.3, 0) else UDim2.new(0.5, 0, 0, 84)
noticeStack.Size = UDim2.fromOffset(if MOBILE then 340 else 480, 10)
noticeStack.AutomaticSize = Enum.AutomaticSize.Y
noticeStack.BackgroundTransparency = 1
noticeStack.Parent = gui
local noticeList = Instance.new("UIListLayout")
noticeList.Padding = UDim.new(0, 4)
noticeList.SortOrder = Enum.SortOrder.LayoutOrder
noticeList.HorizontalAlignment = Enum.HorizontalAlignment.Center
noticeList.Parent = noticeStack

local NOTICE_MAX = 4
local noticeOrder = 0
local liveNotices: { { Label: TextLabel, Base: string, Count: number, Token: number } } = {}

-- Color del aviso según lo que dice (rareza del objeto, llaves, cofres, nivel)
local function noticeAccent(text: string): (Color3?, number)
	for _, rarity in ipairs({ "Mitico", "Legendario", "Epico" }) do
		local shown = ({ Mitico = "Mítico", Legendario = "Legendario", Epico = "Épico" })[rarity]
		if string.find(text, "[" .. shown .. "]", 1, true) then
			return (ItemCatalog.RarityColor :: any)[rarity], 7
		end
	end
	if string.find(text, "Llave", 1, true) or string.find(text, "MEJORADO", 1, true) then
		return Color3.fromRGB(255, 215, 90), 6
	end
	if string.find(text, "Subiste", 1, true) then
		return Color3.fromRGB(120, 230, 140), 5
	end
	if string.find(text, "[Raro]", 1, true) then
		return (ItemCatalog.RarityColor :: any).Raro, 5
	end
	return nil, 4
end

local function dropNotice(entry: { Label: TextLabel, Base: string, Count: number, Token: number })
	local i = table.find(liveNotices, entry)
	if i then
		table.remove(liveNotices, i)
	end
	local lbl = entry.Label
	if lbl.Parent then
		TweenService:Create(lbl, TweenInfo.new(0.25), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.delay(0.28, function()
			lbl:Destroy()
		end)
	end
end

say = function(text: string)
	-- repetido: se suma y se renueva el tiempo
	for _, e in ipairs(liveNotices) do
		if e.Base == text then
			e.Count += 1
			e.Token += 1
			e.Label.Text = string.format("%s  (x%d)", text, e.Count)
			local mine = e.Token
			local _, secs = noticeAccent(text)
			task.delay(secs, function()
				if e.Token == mine then
					dropNotice(e)
				end
			end)
			return
		end
	end
	local accent, secs = noticeAccent(text)
	noticeOrder += 1
	local lbl = Instance.new("TextLabel")
	lbl.LayoutOrder = noticeOrder
	lbl.AutomaticSize = Enum.AutomaticSize.X
	lbl.Size = UDim2.fromOffset(0, if MOBILE then 28 else 32)
	lbl.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	lbl.BackgroundTransparency = 0.2
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.Font = UITheme.Font
	lbl.TextSize = if MOBILE then 14 else 16
	lbl.Text = text
	lbl.TextWrapped = false
	lbl.Parent = noticeStack
	Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = lbl
	if accent then
		local st = Instance.new("UIStroke")
		st.Color = accent
		st.Thickness = 2
		st.Parent = lbl
		lbl.TextColor3 = accent:Lerp(Color3.new(1, 1, 1), 0.35)
	end
	local entry = { Label = lbl, Base = text, Count = 1, Token = 0 }
	table.insert(liveNotices, entry)
	while #liveNotices > NOTICE_MAX do
		dropNotice(liveNotices[1])
	end
	task.delay(secs, function()
		if entry.Token == 0 then
			dropNotice(entry)
		end
	end)
end

listen("XPChanged", function(level: number, xp: number, need: number)
	currentLevel, currentXp, currentNeed = level, xp, need
	levelLabel.Text = "NIVEL " .. level
	if need == math.huge then
		setXp(1, 1, "XP  MÁXIMO · 100%")
	else
		setXp(xp, need, string.format("XP  %.1f%%   (%d / %d)", xp / need * 100, xp, need))
	end
end)
listen("ArenaLives", function(n: number)
	arenaChip.Text = "Vidas de arena: " .. n
end)
listen("Fragility", function(n: number)
	fragChip.Visible = n > 0
	fragChip.Text = string.format("Fragilidad x%d  (+%d%% daño recibido)", n, n * 5)
end)
listen("Notify", say)
listen("LevelUp", function(level: number)
	say("¡Subiste al nivel " .. level .. "!")
end)
listen("Floating", function(pos: Vector3, text: string, color: Color3)
	-- pequeña dispersión para que los golpes seguidos no se encimen
	local jitter = Vector3.new((math.random() - 0.5) * 3, 0, (math.random() - 0.5) * 3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos + jitter
	p.Parent = Workspace
	local b = Instance.new("BillboardGui")
	b.Size = UDim2.fromOffset(110, 40)
	b.AlwaysOnTop = true
	b.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(0.6, 0.6)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Parent = b
	-- "pop": crece de golpe y se asienta; luego sube y se desvanece
	TweenService:Create(t, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1.1, 1.1) }):Play()
	task.delay(0.12, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 1) }):Play()
		end
	end)
	TweenService:Create(p, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos + jitter + Vector3.new(0, 4.5, 0) }):Play()
	task.delay(0.55, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.45), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Debris:AddItem(p, 1.05)
end)

local sync = ClientNet.Get("RequestSync")
if sync then
	sync:FireServer() -- ya escuchamos todo: pide nivel/XP/vidas actuales
end

player:GetAttributeChangedSignal("Faction"):Connect(build)
player:GetAttributeChangedSignal("Role"):Connect(build)

---------------------------------------------------------------------
-- ACTUALIZACIÓN POR FRAME (vida, energía, cooldowns, objetivo, evento)
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
	local maxE = player:GetAttribute("MaxEnergy")
	local curE = player:GetAttribute("Energy")
	if typeof(maxE) == "number" and typeof(curE) == "number" then
		setEnergy(curE, maxE)
	else
		local c = PlayerClass.Get(player)
		setEnergy(c.BaseEnergy, c.BaseEnergy)
	end

	local now = os.clock()
	for i = 1, 7 do
		local s = slotFrames[i]
		if s then
			local left = (cooldownEnd[i] or 0) - now
			local len = cooldownLen[i] or 1
			if left > 0 then
				s.Cool.Size = UDim2.fromScale(1, math.clamp(left / len, 0, 1))
				s.CoolText.Text = string.format("%.1f", left)
			else
				s.Cool.Size = UDim2.fromScale(1, 0)
				s.CoolText.Text = ""
			end
		end
	end

	local t = target
	if t and t.Parent then
		local th = t:FindFirstChildOfClass("Humanoid")
		if th and th.Health > 0 then
			targetPanel.Visible = true
			tName.Text = (t:GetAttribute("DisplayName") or t.Name) .. (if player:GetAttribute("AutoAttack") == true then "   ⚔ AUTO" else "")
			setTarget(th.Health, th.MaxHealth)
		else
			target = nil
			highlight.Adornee = nil
			targetPanel.Visible = false
			if AutoAttackRemote then
				AutoAttackRemote:FireServer("Clear")
			end
		end
	else
		target = nil
		highlight.Adornee = nil
		targetPanel.Visible = false
	end

	local state = Workspace:GetAttribute("EventState")
	local cd = Workspace:GetAttribute("EventCountdown")
	if typeof(cd) == "number" then
		eventChip.Text = if state == "Open" then "ARENA ABIERTA  " .. fmtTime(cd) else "Próximo evento  " .. fmtTime(cd)
	end
end)
