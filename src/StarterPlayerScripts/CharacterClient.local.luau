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
local GearCatalog = require(Modules:WaitForChild("GearCatalog", 10))
local MasteryCatalog = require(Modules:WaitForChild("MasteryCatalog", 10))
local LootTables = require(Modules:WaitForChild("LootTables", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local BagDock = require(script.Parent:WaitForChild("BagDock", 10))

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
local viewRole: string? = nil -- pestaña de rol que se está viendo (nil = el rol actual)
local tabButtons: { [string]: TextButton } = {}
local switchHint: TextLabel? = nil
local angle = 0
local dragging = false
local clone: Model? = nil

local LEFT = { "Casco", "Armadura", "Arma", "Escudo", "Zapatos", "Cinturon" }
local RIGHT = { "Collar", "Pendientes", "Brazalete", "Anillo", "Accesorio1", "Accesorio2" }
local BOTTOM = { "Capa", "Alas", "Montura", "Traje", "Anillo2", "Accesorio3" }

local function makeSlot(slotName: string, pos: UDim2, size: UDim2, parent: Instance)
	local pal = NpcKit.Palette(theme)
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = pal.Slot
	b.Text = ""
	b.AutoButtonColor = true
	b.ZIndex = 5
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = pal.Edge2
	st.Parent = b
	local label = UITheme.Text(b, ItemCatalog.SlotDisplay[slotName] or slotName, 10, pal.Muted, UDim2.fromScale(0, 0.06), UDim2.fromScale(1, 0.88), Enum.TextXAlignment.Center)
	label.Name = "Label"
	label.TextWrapped = true
	label.TextStrokeTransparency = 1
	label.ZIndex = 6
	b.Activated:Connect(function()
		local cur = PlayerClass.Get(player).Role
		if (viewRole == nil or viewRole == cur) and Store.Equip[slotName] then
			Store.Action("Unequip", slotName)
		elseif slotName == "Accesorio3" and player:GetAttribute("Pass_PetSlot") ~= true then
			MenuBus.Fire("Tienda") -- ranura de pase: lleva a la Tienda
		end
	end)
	slotButtons[slotName] = b
end

local function refreshSlots()
	local cls = PlayerClass.Get(player)
	local showing = viewRole or cls.Role
	local other = showing ~= cls.Role
	local level = player:GetAttribute("Level")
	local pal = NpcKit.Palette(theme)
	local light = NpcKit.Key(theme) == "Shinobi"
	for name, b in pairs(slotButtons) do
		local id = Store.Equip[name]
		local plus = Store.EquipPlus[name]
		local shared = false
		if other then
			-- pestaña de otro rol: su pieza guardada; si no tiene, lo que llevas puesto solo se ve si ese rol también lo puede usar (compartido)
			local rec = Store.RoleGear[showing] and Store.RoleGear[showing][name]
			if rec then
				id, plus = rec.Id, rec.Plus
			else
				local curItem: any = if id then ItemCatalog.Items[id] else nil
				if curItem and curItem.Gear and not curItem.Pet and GearCatalog.CanUse(curItem, cls.Faction, showing, if typeof(level) == "number" then level else 1) then
					shared = true
				else
					id, plus = nil, nil
				end
			end
		end
		local item = id and ItemCatalog.Items[id]
		local label = b:FindFirstChild("Label") :: TextLabel
		local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
		if item then
			local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
			label.Text = GearView.DisplayName(item, plus) .. (if shared then "\n(compartido)" else "")
			label.TextColor3 = if light then pal.Text else col
			label.Position = UDim2.new(0, 0, 1, -22)
			label.Size = UDim2.new(1, 0, 0, 20)
			label.TextSize = 8
			label.TextTruncate = Enum.TextTruncate.AtEnd
			label.ZIndex = 9
			local oldIcon = b:FindFirstChild("ItemIcon")
			if oldIcon then
				oldIcon:Destroy()
			end
			local ic = ItemIcon.Build(b, item, 24, col)
			ic.Position = UDim2.new(0.5, 0, 0, 2)
			stroke.Color = col
			b.BackgroundColor3 = col:Lerp(pal.Slot, if light then 0.8 else 0.75)
		else
			label.Text = ItemCatalog.SlotDisplay[name] or name
			label.Position = UDim2.fromScale(0, 0.06)
			label.Size = UDim2.fromScale(1, 0.88)
			label.TextSize = 10
			label.ZIndex = 6
			local oldIcon = b:FindFirstChild("ItemIcon")
			if oldIcon then
				oldIcon:Destroy()
			end
			local passAttr = ItemCatalog.SlotPass[name]
			if passAttr and player:GetAttribute(passAttr) ~= true then
				label.Text ..= "\n🔒 Pase"
			end
			label.TextColor3 = pal.Muted
			stroke.Color = pal.Edge2
			b.BackgroundColor3 = pal.Slot
		end
	end
	local sh = switchHint
	if sh then
		sh.Visible = other and player:GetAttribute("Pass_Multiclass") == true
		sh.Text = "Cambiar a " .. showing
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
local keysResetLabel: TextLabel? = nil

local GREEN, RED, GRAY = Color3.fromRGB(111, 220, 127), Color3.fromRGB(255, 107, 107), Color3.fromRGB(150, 150, 165)
local function applyPalette()
	local pal = NpcKit.Palette(theme)
	if NpcKit.Key(theme) == "Shinobi" then
		GREEN, RED, GRAY = Color3.fromRGB(38, 122, 52), Color3.fromRGB(168, 50, 45), pal.Muted
	else
		GREEN, RED, GRAY = Color3.fromRGB(111, 220, 127), Color3.fromRGB(255, 107, 107), pal.Muted
	end
end
local infoTab = "Stats" -- "Stats" | "Set"

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
	local pal = NpcKit.Palette(theme)
	local h = UITheme.Text(f, text, 14, pal.Accent, UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 18))
	h.TextStrokeTransparency = 1
	local line = Instance.new("Frame")
	line.BackgroundColor3 = pal.Edge2
	line.BorderSizePixel = 0
	line.Position = UDim2.new(0, 0, 1, -2)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Parent = f
end

-- "Nombre ......... valor   +x%"
local function addStat(name: string, value: string, bonus: string?, bonusColor: Color3?)
	local f = addRow(20)
	local pal = NpcKit.Palette(theme)
	UITheme.Text(f, name, 13, pal.Text, UDim2.fromOffset(0, 0), UDim2.new(0.44, 0, 1, 0)).TextStrokeTransparency = 1
	UITheme.Text(f, value, 13, pal.Text, UDim2.new(0.44, 0, 0, 0), UDim2.new(0.24, 0, 1, 0), Enum.TextXAlignment.Right).TextStrokeTransparency = 1
	if bonus then
		UITheme.Text(f, bonus, 13, bonusColor or GREEN, UDim2.new(0.68, 0, 0, 0), UDim2.new(0.32, -2, 1, 0), Enum.TextXAlignment.Right).TextStrokeTransparency = 1
	end
end

local function addNote(text: string, color: Color3?): TextLabel
	rowOrder += 1
	local t = Instance.new("TextLabel")
	t.LayoutOrder = rowOrder
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.Font = Enum.Font.Gotham
	t.TextSize = 11
	t.TextColor3 = color or GRAY
	t.TextSize = 12
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	t.Text = text
	t.Parent = statsScroll
	return t
end

-- "Se reinician en 05:12:33": cuenta atrás hasta la medianoche del juego (DailyLimits publica DailyResetAt)
local function updateKeysReset()
	local lbl = keysResetLabel
	if not lbl or not lbl.Parent then
		return
	end
	local at = player:GetAttribute("DailyResetAt")
	if typeof(at) ~= "number" then
		lbl.Text = ""
		return
	end
	local left = math.max(0, math.floor(at - workspace:GetServerTimeNow()))
	lbl.Text = string.format("Tope diario de llaves por franja. Se reinicia en %02d:%02d:%02d y las llaves que sobren caducan.", left // 3600, (left % 3600) // 60, left % 60)
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
	applyPalette()

	if infoTab == "Set" then
		local role = PlayerClass.Get(player).Role
		local br0 = GearView.Breakdown()
		local full: any = (GearCatalog.SetFull :: any)[role]
		addHeader(string.format("Set de %s  ·  %d/4 piezas", role, math.min(br0.SetPieces, 4)))
		local count = 0
		for _, slotName in ipairs(ItemCatalog.EquipSlots) do
			local id = Store.Equip[slotName]
			local it: any = if id then ItemCatalog.Items[id] else nil
			if it and it.Set == role then
				count += 1
				addStat((if count <= 4 then "✔ " else "• ") .. GearView.DisplayName(it, Store.EquipPlus[slotName]), "", ItemCatalog.SlotDisplay[slotName] or slotName, GRAY)
			end
		end
		if count == 0 then
			addNote("No llevas piezas del set de tu rol.")
		end
		addStat("2 piezas", "", "+5% al equipo", if br0.SetPieces >= 2 then GREEN else GRAY)
		addStat("4 piezas", "", "+15% al equipo", if br0.SetPieces >= 4 then GREEN else GRAY)
		if full then
			addNote((if br0.SetPieces >= 4 then "✔ Set completo: " else "Set completo (4/4): ") .. full.Text, if br0.SetPieces >= 4 then GREEN else GRAY)
		end
		local info2 = ROLE_INFO[role]
		if info2 then
			addHeader("Pasivas de " .. role)
			addNote(info2.Desc)
			for _, t in ipairs(info2.Pasivas) do
				addNote("• " .. t, GRAY)
			end
			addNote("Poder 7 · Primeros Auxilios: curación propia cada 25 s (tecla 7).", GRAY)
		end
		return
	end

	local class = PlayerClass.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local level = (player:GetAttribute("Level") :: number?) or 1
	local br = GearView.Breakdown()
	local total = br.Total

	addHeader(string.format("%s  ·  Nivel %d", class.CharacterName, level))
	addNote(string.format("%s · %s", theme.Faction, class.Role))
	local forgeTitle = player:GetAttribute("TitleForja")
	if typeof(forgeTitle) == "string" then
		local n = player:GetAttribute("Forja9")
		addNote(string.format("★ Título: %s%s", forgeTitle, if typeof(n) == "number" and n > 1 then string.format(" (x%d piezas +9)", n) else ""), Color3.fromRGB(255, 205, 80))
	end

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

	-- LLAVES DEL DÍA: cuántas llaves de cofre cayeron hoy en cada franja (tope diario) y cuánto falta para el reinicio
	addHeader("Llaves del día")
	local keyLimits = LootTables.Daily.Keys
	for strip = 1, 4 do
		local used = player:GetAttribute("KeysUsed_" .. strip)
		local lim = keyLimits[strip] or 0
		local u = if typeof(used) == "number" then used else 0
		local held = 0
		for _, st in pairs(Store.Bag) do
			if st.Id == "Key_" .. strip then
				held += st.Count
			end
		end
		addStat("Franja " .. strip, string.format("%d / %d", u, lim), if held > 0 then string.format("%d en mochila", held) else nil, if u >= lim then GRAY else nil)
	end
	local resetLabel = addNote("")
	keysResetLabel = resetLabel
	updateKeysReset()

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
		local full: any = (GearCatalog.SetFull :: any)[PlayerClass.Get(player).Role]
		if br.SetPieces >= 4 and full then
			addNote("Set completo: " .. full.Text, GREEN)
		end
	elseif br.SetPieces == 0 then
		local fullHint: any = (GearCatalog.SetFull :: any)[PlayerClass.Get(player).Role]
		addNote("Equipa piezas del set de tu rol: 2 dan +5%, 4 dan +15%" .. (if fullHint then " y " .. string.lower(string.sub(fullHint.Text, 1, 1)) .. string.sub(fullHint.Text, 2) else "") .. ".")
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
	applyPalette()
	BagDock.Detach() -- la mochila no debe destruirse con esta ventana
	if win then
		win:Destroy()
		table.clear(slotButtons)
	end
	local cls = PlayerClass.Get(player)
	local lvl = player:GetAttribute("Level")
	win = NpcKit.Window(gui, theme, UDim2.fromOffset(1040, 680), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Equipo y Mochila",
		string.format("%s · Nivel %d · %s  ·  clic en una ranura para desequiparla · cada rol guarda su equipo", cls.CharacterName, if typeof(lvl) == "number" then lvl else 1, cls.Role), "🎒", function()
			gui.Enabled = false
		end)
	WindowDrag.Attach(win, "Character", 40, 50)
	title = Instance.new("TextLabel")
	local pal = NpcKit.Palette(theme)

	-- pestañas de ROL (equipo propio por rol; el cambio de rol lo hace la Maestría Multiclase y cada rol conserva su set)
	table.clear(tabButtons)
	local curRole = cls.Role
	if viewRole == nil then
		viewRole = curRole
	end
	local function paintTabs()
		for r, tb in pairs(tabButtons) do
			local on = r == viewRole
			tb.BackgroundColor3 = if on then pal.TabOn else pal.TabOff
			tb.TextColor3 = if on then pal.TabOnText else pal.TabOffText
		end
	end
	for i, role in ipairs(MasteryCatalog.ROLES) do
		local tb = NpcKit.Tab(win, theme, role, UDim2.fromOffset(75, 28), UDim2.fromOffset(14 + (i - 1) * 79, 72), role == viewRole, function()
			viewRole = role
			paintTabs()
			refreshSlots()
		end)
		tb.TextSize = 12
		if role == curRole then
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(7, 7)
			dot.Position = UDim2.new(1, -11, 0, 3)
			dot.BackgroundColor3 = Color3.fromRGB(80, 210, 100)
			dot.BorderSizePixel = 0
			dot.ZIndex = 12
			dot.Parent = tb
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		end
		tabButtons[role] = tb
	end

	-- panel de equipo: ranuras izquierda / miniatura 3D / ranuras derecha
	local main = NpcKit.Panel(win, theme, UDim2.fromOffset(470, 322), UDim2.fromOffset(14, 106), "card")
	for i, n in ipairs(LEFT) do
		makeSlot(n, UDim2.fromOffset(12, 13 + (i - 1) * 50), UDim2.fromOffset(58, 46), main)
	end
	for i, n in ipairs(RIGHT) do
		makeSlot(n, UDim2.fromOffset(400, 13 + (i - 1) * 50), UDim2.fromOffset(58, 46), main)
	end
	-- fila inferior (6 ranuras: Capa, Alas, Montura, Traje, Anillo 2, Mascota 2)
	for i, n in ipairs(BOTTOM) do
		makeSlot(n, UDim2.fromOffset(14 + (i - 1) * 79, 434), UDim2.fromOffset(75, 44), win)
	end

	viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.fromOffset(78, 12)
	viewport.Size = UDim2.fromOffset(314, 298)
	viewport.BackgroundColor3 = pal.Inset
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.ZIndex = 3
	viewport.Parent = main
	Instance.new("UICorner", viewport)
	local vs = Instance.new("UIStroke")
	vs.Color = pal.Edge2
	vs.Thickness = 1
	vs.Parent = viewport
	UITheme.Text(viewport, "arrastra para girar", 10, pal.Muted, UDim2.fromScale(0, 0.94), UDim2.fromScale(1, 0.06), Enum.TextXAlignment.Center).TextStrokeTransparency = 1
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

	-- pestañas inferiores: Estadísticas | Set y pasivas
	local function tabBtn(text: string, id: string, x: number)
		local tb = NpcKit.Tab(win, theme, text, UDim2.fromOffset(130, 26), UDim2.fromOffset(x, 486), infoTab == id, function()
			infoTab = id
			build()
			refreshModel()
		end)
		tb.TextSize = 12
	end
	tabBtn("Estadísticas", "Stats", 14)
	tabBtn("Set y pasivas", "Set", 148)
	local cambiar = NpcKit.Button(win, theme, "", UDim2.fromOffset(190, 26), UDim2.fromOffset(294, 486), "buy", function()
		if viewRole and viewRole ~= PlayerClass.Get(player).Role and player:GetAttribute("Pass_Multiclass") == true then
			local remote = ClientNet.Get("MasteryAction")
			if remote then
				remote:FireServer("Switch", viewRole)
			end
		end
	end)
	cambiar.TextSize = 12
	cambiar.Visible = false
	switchHint = cambiar

	local statsBox = NpcKit.Panel(win, theme, UDim2.fromOffset(470, 148), UDim2.fromOffset(14, 518), "inset")
	statsScroll = Instance.new("ScrollingFrame")
	statsScroll.Position = UDim2.fromOffset(8, 6)
	statsScroll.Size = UDim2.fromOffset(454, 136)
	statsScroll.BackgroundTransparency = 1
	statsScroll.BorderSizePixel = 0
	statsScroll.ScrollBarThickness = 4
	statsScroll.ZIndex = 3
	local statsPad = Instance.new("UIPadding")
	statsPad.PaddingRight = UDim.new(0, 10)
	statsPad.Parent = statsScroll
	statsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	statsScroll.CanvasSize = UDim2.fromOffset(0, 0)
	statsScroll.Parent = statsBox
	local statsList = Instance.new("UIListLayout")
	statsList.SortOrder = Enum.SortOrder.LayoutOrder
	statsList.Padding = UDim.new(0, 2)
	statsList.Parent = statsScroll

	-- hueco de la MOCHILA (a la derecha): el panel de InventoryClient se acopla aquí
	local host = Instance.new("Frame")
	host.Name = "MochilaHost"
	host.Position = UDim2.fromOffset(498, 72)
	host.Size = UDim2.fromOffset(528, 594)
	host.BackgroundTransparency = 1
	host.Parent = win
	BagDock.Attach(host)

	refreshSlots()
	refreshStats()
end

local function open()
	gui.Enabled = true
	viewRole = nil
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
player:GetAttributeChangedSignal("Role"):Connect(function()
	if gui.Enabled then
		task.wait(1.5) -- deja que termine el cambio de rol (reaparece el personaje)
		viewRole = nil
		build()
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
	if gui.Enabled and (isGold or string.sub(name, 1, 10) == "EquipPlus_" or string.sub(name, 1, 9) == "KeysUsed_" or name == "Pass_PetSlot") then
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
MenuBus.Event:Connect(function(name: string)
	if name == "Character" then
		if gui.Enabled then
			gui.Enabled = false
		else
			open()
		end
	end
end)

-- reloj de las llaves: se actualiza cada segundo mientras el perfil está abierto
task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled then
			updateKeysReset()
		end
	end
end)
