--!strict
--[[
    DeathScreenClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DeathScreenClient
    PANTALLA DE MUERTE: al morir el jugador local, oscurece el borde de la pantalla y muestra
    "HAS CAÍDO", quién lo derrotó, la XP perdida, dónde reaparecerá (ciudad o campamento) y una cuenta atrás.
    Solo muestra: los datos los pone el servidor como atributos del jugador (DeathKiller, DeathXpLoss, DeathPlace).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
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
box.Size = UDim2.fromOffset(if MOBILE then 300 else 420, if MOBILE then 170 else 200)
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
local countL = label("", if MOBILE then 18 else 22, if MOBILE then 130 else 148, 34, Color3.new(1, 1, 1), Enum.Font.GothamBlack)

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
	placeL.Text = "Reaparecerás en: " .. (if typeof(place) == "string" and place ~= "" then place else "tu ciudad")
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
	task.spawn(function()
		local untilT = os.clock() + Players.RespawnTime
		task.wait(0.35) -- el servidor termina de poner killer / XP / lugar
		while token == my and gui.Enabled do
			refreshTexts()
			local left = math.max(0, untilT - os.clock())
			countL.Text = if left > 0.05 then string.format("Reapareciendo en %.1f s", left) else "Reapareciendo…"
			task.wait(0.1)
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
