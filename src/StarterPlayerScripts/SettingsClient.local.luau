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
end

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
