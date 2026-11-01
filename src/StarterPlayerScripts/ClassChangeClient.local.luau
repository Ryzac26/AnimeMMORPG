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

local ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
local HINT: { [string]: string } = {
	Tanque = "Aguanta el daño y protege al grupo",
	Guerrero = "Daño equilibrado cuerpo a cuerpo",
	Asesino = "Mucho daño, poca vida, muy veloz",
	Tirador = "Daño a larga distancia",
	Mago = "Daño en área",
	Curador = "Cura y apoya al equipo",
}
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
	local w = UITheme.Frame(gui, theme, UDim2.fromOffset(420, 470), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	win = w
	WindowDrag.Attach(w, "ClassChange", 52, 50)
	UITheme.Text(w, name, 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(340, 26))
	UITheme.Text(w, title .. "  ·  cambio de clase GRATIS", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 30), UDim2.fromOffset(380, 16))
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

	local confirm = Instance.new("TextButton")
	confirm.Position = UDim2.fromOffset(18, 418)
	confirm.Size = UDim2.fromOffset(384, 40)
	confirm.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
	confirm.TextColor3 = Color3.new(1, 1, 1)
	confirm.Font = UITheme.Font
	confirm.TextSize = 16
	confirm.Text = "Elige un rol"
	confirm.AutoButtonColor = false
	confirm.Parent = w
	Instance.new("UICorner", confirm)

	local buttons: { [string]: TextButton } = {}
	local function paint()
		for role, b in pairs(buttons) do
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if role == picked then theme.Primary else Color3.fromRGB(70, 70, 85)
				st.Thickness = if role == picked then 3 else 1
			end
		end
		confirm.Text = if picked then "Cambiar a " .. picked else "Elige un rol"
		confirm.BackgroundColor3 = if picked then Color3.fromRGB(50, 130, 70) else Color3.fromRGB(60, 60, 70)
	end
	for i, role in ipairs(ROLES) do
		local data = if typeof(faction) == "string" then FactionClasses.FindClass(faction, role) else nil
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(18, 58 + (i - 1) * 59)
		b.Size = UDim2.fromOffset(384, 54)
		b.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
		b.Text = ""
		b.AutoButtonColor = true
		b.Parent = w
		Instance.new("UICorner", b)
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(70, 70, 85)
		st.Parent = b
		local isCurrent = role == current
		UITheme.Text(b, string.format("%s  ·  %s", role, if data then data.CharacterName else "?"), 15, if isCurrent then Color3.fromRGB(255, 214, 90) else Color3.new(1, 1, 1), UDim2.fromOffset(10, 5), UDim2.fromOffset(300, 22))
		UITheme.Text(b, HINT[role] or "", 12, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(10, 28), UDim2.fromOffset(364, 18))
		if isCurrent then
			UITheme.Text(b, "ACTUAL", 11, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(300, 7), UDim2.fromOffset(74, 16), Enum.TextXAlignment.Right)
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
