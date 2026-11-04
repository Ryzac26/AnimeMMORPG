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
	local height = 62 + 14
	for _, sec in ipairs(SETTINGS) do
		height += 26 + #sec.Items * 94
	end
	local w = UITheme.Frame(gui, theme, UDim2.fromOffset(380, height), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	win = w
	WindowDrag.Attach(w, "Settings", 52, 50)
	UITheme.Text(w, "AJUSTES", 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(300, 26))
	UITheme.Text(w, "Se guardan en tu perfil", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 30), UDim2.fromOffset(300, 16))
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.Parent = w
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	local y = 62
	for _, sec in ipairs(SETTINGS) do
		UITheme.Text(w, sec.Section, 13, theme.Primary, UDim2.fromOffset(18, y), UDim2.fromOffset(344, 18))
		y += 26
		for _, item in ipairs(sec.Items) do
			UITheme.Text(w, item.Label, 15, Color3.new(1, 1, 1), UDim2.fromOffset(18, y), UDim2.fromOffset(344, 20))
			local hint = UITheme.Text(w, item.Hint, 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(18, y + 20), UDim2.fromOffset(344, 28))
			hint.TextWrapped = true
			hint.TextYAlignment = Enum.TextYAlignment.Top
			y += 50
			local n = #item.Options
			local gap = 6
			local bw = math.floor((344 - gap * (n - 1)) / n)
			local buttons: { [string]: TextButton } = {}
			for i, opt in ipairs(item.Options) do
				local b = Instance.new("TextButton")
				b.Position = UDim2.fromOffset(18 + (i - 1) * (bw + gap), y)
				b.Size = UDim2.fromOffset(bw, 32)
				b.Text = opt[2]
				b.Font = UITheme.Font
				b.TextSize = 13
				b.AutoButtonColor = true
				b.Parent = w
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
				buttons[opt[1]] = b
				b.Activated:Connect(function()
					player:SetAttribute("Setting_" .. item.Key, opt[1]) -- respuesta inmediata; el servidor lo confirma y guarda
					setRemote:FireServer(item.Key, opt[1])
				end)
			end
			local function refresh()
				local cur = current(item.Key)
				for value, b in pairs(buttons) do
					local on = value == cur
					b.BackgroundColor3 = if on then theme.Primary else theme.Dark
					b.TextColor3 = if on then Color3.fromRGB(20, 17, 10) else Color3.fromRGB(200, 204, 220)
				end
			end
			refresh()
			table.insert(refreshers, refresh)
			player:GetAttributeChangedSignal("Setting_" .. item.Key):Connect(refresh)
			y += 44
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
