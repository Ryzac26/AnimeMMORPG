--!strict
--[[
    ClassChangeClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ClassChangeClient
    Ventana del INSTRUCTOR (botón "Cambiar de clase"): lista los 6 roles de TU facción; eliges uno y confirmas. Gratis.
    El servidor (ClassSelectService) valida el permiso del Instructor; tu personaje reaparece con el rol nuevo.
    Después de cambiar, abre la mochila (B) y pulsa "★ Mejor set" para ponerte el equipo de tu nueva clase.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local FactionClasses = require(Modules:WaitForChild("FactionClassesModule", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))

local ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
local HINT: { [string]: string } = {
	Tanque = "Aguanta el daño y protege al grupo",
	Guerrero = "Daño equilibrado cuerpo a cuerpo",
	Asesino = "Mucho daño, poca vida, muy veloz",
	Tirador = "Daño a larga distancia",
	Mago = "Daño en área",
	Curador = "Cura y apoya al equipo",
}
local ICON: { [string]: string } = { Tanque = "🛡", Guerrero = "⚔", Asesino = "🗡", Tirador = "🏹", Mago = "🔮", Curador = "✚" }
local CLOSE_DISTANCE = 32

local openRemote = ClientNet.Get("ClassChangeOpen")
local chooseRemote = ClientNet.Get("ChooseClass")

local gui = Instance.new("ScreenGui")
gui.Name = "ClassChangeGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local openPos: Vector3? = nil
local picked: string? = nil

local function build(name: string, title: string)
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local faction = player:GetAttribute("Faction")
	local current = player:GetAttribute("Role")
	local W = 436
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, 504), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), name, title .. "  ·  cambio de clase GRATIS", "🎓", function()
		gui.Enabled = false
	end)
	win = w
	WindowDrag.Attach(w, "ClassChange", 40, 50)
	local pal = NpcKit.Palette(theme)

	local confirm = NpcKit.Button(w, theme, "Elige un rol", UDim2.fromOffset(W - 28, 40), UDim2.fromOffset(14, 452), "buy", nil)
	confirm.TextSize = 16
	confirm.AutoButtonColor = false

	local buttons: { [string]: TextButton } = {}
	local function paint()
		for role, b in pairs(buttons) do
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if role == picked then pal.Accent else pal.Edge
				st.Thickness = if role == picked then 3 else 1
				st.Transparency = if role == picked then 0 else 0.5
			end
		end
		confirm.Text = if picked then "Cambiar a " .. picked else "Elige un rol"
		confirm.AutoButtonColor = picked ~= nil
	end
	-- tarjetas de rol 2 x 3 (retrato = emblema del rol)
	for i, role in ipairs(ROLES) do
		local data = if typeof(faction) == "string" then FactionClasses.FindClass(faction, role) else nil
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local card = NpcKit.Panel(w, theme, UDim2.fromOffset(196, 124), UDim2.fromOffset(14 + col * 208, 74 + row * 126), "card")
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.ZIndex = 12
		b.Parent = card
		local st = Instance.new("UIStroke")
		st.Color = pal.Edge
		st.Transparency = 0.5
		st.Parent = b
		local isCurrent = role == current
		local medal = Instance.new("Frame")
		medal.Position = UDim2.fromOffset(10, 10)
		medal.Size = UDim2.fromOffset(46, 46)
		medal.BackgroundColor3 = pal.Accent
		medal.BorderSizePixel = 0
		medal.Parent = card
		Instance.new("UICorner", medal).CornerRadius = UDim.new(1, 0)
		local ms = Instance.new("UIStroke")
		ms.Color = pal.Edge
		ms.Thickness = 2
		ms.Parent = medal
		local ic = UITheme.Text(medal, ICON[role] or "★", 24, pal.BtnText, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		ic.TextStrokeTransparency = 1
		local n1 = UITheme.Text(card, role, 16, if isCurrent then pal.Accent else pal.Text, UDim2.fromOffset(64, 10), UDim2.fromOffset(126, 20))
		n1.TextStrokeTransparency = 1
		local n2 = UITheme.Text(card, if data then data.CharacterName else "?", 12, pal.Muted, UDim2.fromOffset(64, 32), UDim2.fromOffset(126, 16))
		n2.TextStrokeTransparency = 1
		n2.TextTruncate = Enum.TextTruncate.AtEnd
		local hint = UITheme.Text(card, HINT[role] or "", 11, pal.Muted, UDim2.fromOffset(10, 66), UDim2.fromOffset(176, 36))
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
		hint.TextStrokeTransparency = 1
		if isCurrent then
			NpcKit.Chip(card, "ACTUAL", pal.Accent, UDim2.fromOffset(122, 100), UDim2.fromOffset(66, 16))
		else
			b.Activated:Connect(function()
				picked = role
				paint()
			end)
		end
		buttons[role] = b
	end
	paint()
	confirm.Activated:Connect(function()
		if picked and chooseRemote and typeof(faction) == "string" then
			chooseRemote:FireServer(faction, picked)
			gui.Enabled = false
		end
	end)
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(name: any, title: any, _faction: any)
		local ok, err = pcall(function()
			picked = nil
			build(if typeof(name) == "string" then name else "Instructor", if typeof(title) == "string" then title else "")
			gui.Enabled = true
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			openPos = if root then root.Position else nil
		end)
		if not ok then
			warn("[ClassChangeClient] No se pudo abrir la ventana: " .. tostring(err))
		end
	end)
end

task.spawn(function()
	while true do
		task.wait(1)
		if gui.Enabled and openPos then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or (root.Position - openPos).Magnitude > CLOSE_DISTANCE then
				gui.Enabled = false
			end
		end
	end
end)

print("[ClassChangeClient] listo")
