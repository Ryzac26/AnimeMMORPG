--!strict
--[[
    DeathScreenClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DeathScreenClient
    PANTALLA DE MUERTE: al morir el jugador local, oscurece el borde de la pantalla y muestra
    "HAS CAÍDO", quién lo derrotó, la XP perdida y DOS BOTONES: "Ir a la ciudad" / "Ir al campamento" (solo si tiene uno fijado en esa franja).
    No reaparece solo: hasta que pulse un botón queda en la pantalla donde murió (así, si no está presente, su personaje no sigue jugando).
    Los datos los pone el servidor como atributos del jugador (DeathKiller, DeathXpLoss, DeathPlace); el botón avisa al servidor con DeathRespawn.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local respawnRemote = ClientNet.Get("DeathRespawn")
local MOBILE = Platform.IsMobile()
local theme = UITheme.For(player:GetAttribute("Faction"))
local accent = UITheme.Accent(theme)
local RED = Color3.fromRGB(215, 55, 55)

local gui = Instance.new("ScreenGui")
gui.Name = "DeathScreenGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

-- velo rojo oscuro con el centro más despejado
local veil = Instance.new("Frame")
veil.Size = UDim2.fromScale(1, 1)
veil.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
veil.BackgroundTransparency = 1
veil.BorderSizePixel = 0
veil.Parent = gui
local vg = Instance.new("UIGradient")
vg.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(0.5, 0.75),
	NumberSequenceKeypoint.new(1, 0.2),
})
vg.Rotation = 90
vg.Parent = veil

local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.fromScale(0.5, 0.42)
box.Size = UDim2.fromOffset(if MOBILE then 320 else 440, if MOBILE then 230 else 262)
box.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
box.BackgroundTransparency = 1
box.BorderSizePixel = 0
box.Parent = gui
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 12)
local stroke = UITheme.Border(box, theme, 2)
stroke.Color = RED
stroke.Transparency = 1

local function label(text: string, size: number, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.new(0, 12, 0, y)
	l.Size = UDim2.new(1, -24, 0, h)
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextTransparency = 1
	l.Text = text
	l.TextWrapped = true
	l.Parent = box
	return l
end

local title = label("HAS CAÍDO", if MOBILE then 30 else 38, 12, if MOBILE then 38 else 46, RED, Enum.Font.GothamBlack)
local killerL = label("", if MOBILE then 14 else 16, if MOBILE then 56 else 66, 22, Color3.new(1, 1, 1), UITheme.Font)
local lossL = label("", if MOBILE then 13 else 15, if MOBILE then 80 else 92, 20, Color3.fromRGB(255, 190, 90), UITheme.Font)
local placeL = label("", if MOBILE then 13 else 15, if MOBILE then 102 else 116, 20, accent, UITheme.Font)
local countL = label("Elige dónde reaparecer", if MOBILE then 15 else 17, if MOBILE then 128 else 146, 26, Color3.new(1, 1, 1), Enum.Font.GothamBold)

local function actionButton(text: string, x: number, color: Color3, choice: string): TextButton
	local b = Instance.new("TextButton")
	b.AnchorPoint = Vector2.new(0, 0)
	b.Position = UDim2.new(x, if x == 0 then 12 else 4, 0, if MOBILE then 164 else 184)
	b.Size = UDim2.new(0.5, -16, 0, if MOBILE then 52 else 60)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = UITheme.Font
	b.TextSize = if MOBILE then 15 else 18
	b.TextWrapped = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = box
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 10)
	b.Activated:Connect(function()
		if respawnRemote then
			respawnRemote:FireServer(choice)
		end
		b.Active = false
		b.Text = "Reapareciendo…"
	end)
	return b
end
local cityButton = actionButton("🏙 Ir a la ciudad", 0, Color3.fromRGB(50, 110, 190), "City")
local campButton = actionButton("⛺ Ir al campamento", 0.5, Color3.fromRGB(60, 150, 85), "Camp")

local fadeLabels = { title, killerL, lossL, placeL, countL }
local token = 0

local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	return out
end

local function refreshTexts()
	local killer = player:GetAttribute("DeathKiller")
	killerL.Text = if typeof(killer) == "string" and killer ~= "" then ("Te derrotó: " .. killer) else "Caíste en combate"
	local loss = player:GetAttribute("DeathXpLoss")
	lossL.Text = if typeof(loss) == "number" and loss > 0 then ("XP perdida: -" .. fmt(loss)) else "No perdiste XP"
	local place = player:GetAttribute("DeathPlace")
	local hasCamp = typeof(place) == "string" and place ~= ""
	placeL.Text = if hasCamp then ("Tu campamento: " .. (place :: string):gsub("^Campamento · ", "")) else "Sin campamento fijado en esta franja"
	campButton.Visible = hasCamp
	cityButton.Position = if hasCamp then UDim2.new(0, 12, 0, if MOBILE then 164 else 184) else UDim2.new(0.25, 0, 0, if MOBILE then 164 else 184)
	cityButton.Size = UDim2.new(0.5, -16, 0, if MOBILE then 52 else 60)
end

local function hide()
	token += 1
	gui.Enabled = false
end

local function show()
	token += 1
	local my = token
	refreshTexts()
	gui.Enabled = true
	veil.BackgroundTransparency = 1
	box.BackgroundTransparency = 1
	stroke.Transparency = 1
	for _, l in ipairs(fadeLabels) do
		l.TextTransparency = 1
	end
	local info = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
	TweenService:Create(veil, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(box, info, { BackgroundTransparency = 0.2 }):Play()
	TweenService:Create(stroke, info, { Transparency = 0 }):Play()
	for _, l in ipairs(fadeLabels) do
		TweenService:Create(l, info, { TextTransparency = 0 }):Play()
	end
	cityButton.Active = true
	cityButton.Text = "🏙 Ir a la ciudad"
	campButton.Active = true
	campButton.Text = "⛺ Ir al campamento"
	task.spawn(function()
		task.wait(0.35) -- el servidor termina de poner killer / XP / lugar
		while token == my and gui.Enabled do
			refreshTexts()
			task.wait(0.5)
		end
	end)
end

local function hook(char: Model)
	hide() -- cargó un personaje nuevo: ya reapareció
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Once(show)
	end
end

player.CharacterAdded:Connect(hook)
if player.Character then
	task.spawn(hook, player.Character)
end
