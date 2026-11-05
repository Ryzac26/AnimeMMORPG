--!strict
--[[
    SettingsClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > SettingsClient
    Ventana de AJUSTES (botón "Ajustes" de la barra de menú, también en el menú del celular). Se mueve arrastrando el título.
    Cada ajuste es una fila de la lista SETTINGS; el valor se guarda en el perfil (SettingsService) y viaja como atributo "Setting_<Clave>".
    Primer ajuste: "Mostrar mascotas" (Todas / Solo la mía / Ninguna) para dejar la pantalla lo más limpia posible.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local KeyBindCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("KeyBindCatalog"))
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

type Setting = { Key: string, Label: string, Hint: string, Options: { { string } } } -- Options: { valor, texto }
local SETTINGS: { { Section: string, Items: { Setting } } } = {
	{
		Section = "MASCOTAS",
		Items = {
			{
				Key = "PetsMode", Label = "Mostrar mascotas", Hint = "Oculta las mascotas para ver menos cosas en pantalla.",
				Options = { { "all", "Todas" }, { "mine", "Solo la mía" }, { "none", "Ninguna" } },
			},
		},
	},
}
local DEFAULTS: { [string]: string } = { PetsMode = "all" }

local setRemote = ClientNet.Get("SetSetting")

local gui = Instance.new("ScreenGui")
gui.Name = "SettingsGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local openKeyboard: () -> () = function() end
local refreshers: { () -> () } = {}

local function current(key: string): string
	local v = player:GetAttribute("Setting_" .. key)
	return if typeof(v) == "string" then v else (DEFAULTS[key] or "")
end

local function build()
	if win then
		win:Destroy()
	end
	table.clear(refreshers)
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W = 420
	local height = NpcKit.TOP + 14
	for _, sec in ipairs(SETTINGS) do
		height += 28 + #sec.Items * 112
	end
	height += 28 + 70
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, height), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Ajustes", "Se guardan en tu perfil", "⚙", function()
		gui.Enabled = false
	end)
	win = w
	WindowDrag.Attach(w, "Settings", 40, 50)

	local y = NpcKit.TOP
	for _, sec in ipairs(SETTINGS) do
		local head = UITheme.Text(w, sec.Section, 13, pal.FText, UDim2.fromOffset(18, y), UDim2.fromOffset(W - 36, 18))
		head.TextStrokeTransparency = 1
		y += 28
		for _, item in ipairs(sec.Items) do
			local card = NpcKit.Panel(w, theme, UDim2.fromOffset(W - 28, 102), UDim2.fromOffset(14, y), "card")
			local lbl = UITheme.Text(card, item.Label, 15, pal.Text, UDim2.fromOffset(12, 8), UDim2.new(1, -24, 0, 20))
			lbl.TextStrokeTransparency = 1
			local hint = UITheme.Text(card, item.Hint, 11, pal.Muted, UDim2.fromOffset(12, 28), UDim2.new(1, -24, 0, 28))
			hint.TextWrapped = true
			hint.TextYAlignment = Enum.TextYAlignment.Top
			hint.TextStrokeTransparency = 1
			local n = #item.Options
			local gap = 6
			local inner = W - 28 - 24
			local bw = math.floor((inner - gap * (n - 1)) / n)
			local buttons: { [string]: TextButton } = {}
			local strokes: { [string]: UIStroke } = {}
			for i, opt in ipairs(item.Options) do
				local b = NpcKit.Tab(card, theme, opt[2], UDim2.fromOffset(bw, 34), UDim2.fromOffset(12 + (i - 1) * (bw + gap), 60), false, function()
					player:SetAttribute("Setting_" .. item.Key, opt[1]) -- respuesta inmediata; el servidor lo confirma y guarda
					setRemote:FireServer(item.Key, opt[1])
				end)
				buttons[opt[1]] = b
				strokes[opt[1]] = b:FindFirstChildOfClass("UIStroke") :: UIStroke
			end
			local function refresh()
				local cur = current(item.Key)
				for value, b in pairs(buttons) do
					local on = value == cur
					b.BackgroundColor3 = if on then pal.TabOn else pal.TabOff
					b.TextColor3 = if on then pal.TabOnText else pal.TabOffText
					local st = strokes[value]
					st.Color = if on then pal.Edge else pal.Edge2
					st.Thickness = if on then 2 else 1
				end
			end
			refresh()
			table.insert(refreshers, refresh)
			player:GetAttributeChangedSignal("Setting_" .. item.Key):Connect(refresh)
			y += 112
		end
	end
	-- ATAJOS DE TECLADO
	local head = UITheme.Text(w, "ATAJOS DE TECLADO", 13, pal.FText, UDim2.fromOffset(18, y), UDim2.fromOffset(W - 36, 18))
	head.TextStrokeTransparency = 1
	y += 28
	local card = NpcKit.Panel(w, theme, UDim2.fromOffset(W - 28, 60), UDim2.fromOffset(14, y), "card")
	local hint = UITheme.Text(card, "Cambia las teclas de Perfil, Mochila, poderes y más.", 11, pal.Muted, UDim2.fromOffset(12, 6), UDim2.new(1, -24, 0, 16))
	hint.TextStrokeTransparency = 1
	NpcKit.Button(card, theme, "⌨  Abrir teclado de atajos", UDim2.fromOffset(W - 52, 28), UDim2.fromOffset(12, 26), "buy", function()
		openKeyboard()
	end)
end

---------------------------------------------------------------------
-- TECLADO DE ATAJOS (ventana aparte): teclado visual + lista de acciones. Clic en una acción y pulsa la tecla nueva.
---------------------------------------------------------------------
local kbGui = Instance.new("ScreenGui")
kbGui.Name = "KeybindsGui"
kbGui.ResetOnSpawn = false
kbGui.Enabled = false
kbGui.DisplayOrder = 14
kbGui.Parent = player:WaitForChild("PlayerGui", 10)

local kbWin: Frame? = nil
local listening: string? = nil
local kbMessage = ""
local renderKeyboard: () -> () = function() end

local function stopListening()
	listening = nil
	ContextActionService:UnbindAction("KeyCapture")
end

local function captureKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not listening then
		return Enum.ContextActionResult.Sink
	end
	local id = listening
	if input.KeyCode == Enum.KeyCode.Escape then
		kbMessage = "Cancelado."
	else
		local name = input.KeyCode.Name
		if KeyBindCatalog.Reserved[name] then
			kbMessage = string.format("%s está reservada (%s).", name, string.lower(KeyBindCatalog.Reserved[name]))
		elseif KeyBindCatalog.IsAllowedKey(name) then
			KeyBinds.Set(id, name)
			kbMessage = string.format("%s → %s", KeyBindCatalog.ById[id].Label, KeyBindCatalog.Display(name))
		else
			kbMessage = "Esa tecla no se puede usar."
		end
	end
	stopListening()
	task.defer(renderKeyboard)
	return Enum.ContextActionResult.Sink
end

local function startListening(id: string)
	stopListening()
	listening = id
	kbMessage = string.format("Pulsa la tecla nueva para «%s» (Esc cancela)…", KeyBindCatalog.ById[id].Label)
	local codes: { Enum.KeyCode } = { Enum.KeyCode.Escape }
	for _, row in ipairs(KeyBindCatalog.Rows) do
		for _, k in ipairs(row) do
			table.insert(codes, (Enum.KeyCode :: any)[k])
		end
	end
	ContextActionService:BindActionAtPriority("KeyCapture", captureKey, false, Enum.ContextActionPriority.High.Value + 900, table.unpack(codes))
	renderKeyboard()
end

renderKeyboard = function()
	if kbWin then
		kbWin:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local w = NpcKit.Window(kbGui, theme, UDim2.fromOffset(780, 640), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Atajos de teclado",
		"Haz clic en una acción y pulsa la tecla nueva · si la tecla ya se usa, se intercambian", "⌨", function()
			stopListening()
			kbGui.Enabled = false
		end)
	kbWin = w
	WindowDrag.Attach(w, "Keybinds", 40, 50)

	-- qué acción usa cada tecla
	local byKey: { [string]: string } = {}
	for _, a in ipairs(KeyBindCatalog.Actions) do
		byKey[KeyBinds.Name(a.Id)] = a.Id
	end

	-- teclado visual
	local board = NpcKit.Panel(w, theme, UDim2.fromOffset(752, 262), UDim2.fromOffset(14, NpcKit.TOP), "card")
	local KS, KG = 62, 8
	for r, row in ipairs(KeyBindCatalog.Rows) do
		for c, keyName in ipairs(row) do
			local id = byKey[keyName]
			local reserved = KeyBindCatalog.Reserved[keyName]
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(24 + (r - 1) * 22 + (c - 1) * (KS + KG), 14 + (r - 1) * (KS + KG - 2))
			b.Size = UDim2.fromOffset(KS, KS)
			b.AutoButtonColor = true
			b.Font = Enum.Font.GothamBold
			b.TextSize = 18
			b.Text = KeyBindCatalog.Display(keyName)
			b.ZIndex = 5
			b.BorderSizePixel = 0
			if id then
				b.BackgroundColor3 = if id == listening then pal.Accent else pal.TabOn
				b.TextColor3 = pal.TabOnText
				b.TextYAlignment = Enum.TextYAlignment.Top
				local tag = UITheme.Text(b, KeyBindCatalog.ById[id].Short, 9, pal.TabOnText, UDim2.fromOffset(2, KS - 22), UDim2.fromOffset(KS - 4, 18), Enum.TextXAlignment.Center)
				tag.TextStrokeTransparency = 1
				tag.TextWrapped = true
				tag.ZIndex = 6
			elseif reserved then
				b.BackgroundColor3 = pal.Slot
				b.TextColor3 = pal.Muted
				b.TextTransparency = 0.4
				b.TextYAlignment = Enum.TextYAlignment.Top
				local tag = UITheme.Text(b, reserved, 9, pal.Muted, UDim2.fromOffset(2, KS - 22), UDim2.fromOffset(KS - 4, 18), Enum.TextXAlignment.Center)
				tag.TextStrokeTransparency = 1
				tag.ZIndex = 6
				b.AutoButtonColor = false
			else
				b.BackgroundColor3 = pal.TabOff
				b.TextColor3 = pal.TabOffText
			end
			b.Parent = board
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
			local st = Instance.new("UIStroke")
			st.Color = if id then pal.Edge else pal.Edge2
			st.Thickness = if id then 2 else 1
			st.Parent = b
			b.Activated:Connect(function()
				if reserved then
					return
				end
				if listening then
					-- asigna la tecla pulsada en el teclado visual a la acción que se está cambiando
					local target = listening
					stopListening()
					KeyBinds.Set(target, keyName)
					kbMessage = string.format("%s → %s", KeyBindCatalog.ById[target].Label, KeyBindCatalog.Display(keyName))
					task.defer(renderKeyboard)
				elseif id then
					startListening(id)
				end
			end)
		end
	end
	UITheme.Text(board, "Teclas en color = ya tienen una acción. W A S D y E están reservadas.", 11, pal.Muted, UDim2.fromOffset(24, 238), UDim2.fromOffset(700, 16)).TextStrokeTransparency = 1

	-- lista de acciones (2 columnas)
	local listBox = NpcKit.Panel(w, theme, UDim2.fromOffset(752, 240), UDim2.fromOffset(14, NpcKit.TOP + 274), "card")
	local groups: { string } = {}
	local perGroup: { [string]: { any } } = {}
	for _, a in ipairs(KeyBindCatalog.Actions) do
		if not perGroup[a.Group] then
			perGroup[a.Group] = {}
			table.insert(groups, a.Group)
		end
		table.insert(perGroup[a.Group], a)
	end
	local col, y = 0, 8
	local rowsPerCol = 8
	local n = 0
	for _, g in ipairs(groups) do
		for _, a in ipairs(perGroup[g]) do
			if n == rowsPerCol then
				col, y, n = 1, 8, 0
			end
			local x = 12 + col * 372
			UITheme.Text(listBox, a.Label, 13, pal.Text, UDim2.fromOffset(x, y + 3), UDim2.fromOffset(250, 20)).TextStrokeTransparency = 1
			local isL = listening == a.Id
			local kb = NpcKit.Tab(listBox, theme, if isL then "…" else KeyBinds.Label(a.Id), UDim2.fromOffset(90, 26), UDim2.fromOffset(x + 262, y), isL, function()
				startListening(a.Id)
			end)
			kb.TextSize = 14
			y += 28
			n += 1
		end
	end
	local msg = UITheme.Text(w, kbMessage, 13, pal.FText, UDim2.fromOffset(18, NpcKit.TOP + 522), UDim2.fromOffset(560, 20))
	msg.TextStrokeTransparency = 1
	NpcKit.Button(w, theme, "Restablecer todo", UDim2.fromOffset(160, 30), UDim2.fromOffset(606, NpcKit.TOP + 520), "danger", function()
		stopListening()
		KeyBinds.Reset()
		kbMessage = "Atajos restablecidos."
		task.defer(renderKeyboard)
	end)
end

openKeyboard = function()
	kbMessage = ""
	stopListening()
	renderKeyboard()
	kbGui.Enabled = true
end

KeyBinds.Changed:Connect(function()
	if kbGui.Enabled and not listening then
		renderKeyboard()
	end
end)

build()

MenuBus.Event:Connect(function(name: string)
	if name == "Settings" then
		if gui.Enabled then
			gui.Enabled = false
		else
			build() -- refresca colores si cambió de facción
			gui.Enabled = true
		end
	end
end)
