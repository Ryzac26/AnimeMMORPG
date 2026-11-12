--!strict
--[[
    BetaBannerClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BetaBannerClient
    Cartel que corre por arriba de la pantalla (estilo aviso de servidor): BETA ABIERTA + bienvenida + cómo reportar errores.
    Pasa 3 veces al entrar y luego se esconde; vuelve a pasar una vez cada REPEAT_MINUTES. La X lo cierra hasta la próxima vez.
    Edita MESSAGE para cambiar el texto. Está en KEEP_GUIS de UIReloadClient (no se borra al cambiar de facción).
]]
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local MESSAGE = "★ BETA ABIERTA ★   ¡Bienvenido!   Si encuentras algún error, repórtalo con el botón REPORTAR (borde derecho de la pantalla).   Gracias y ¡disfruta de la beta!   ★"
local PASSES_ON_JOIN = 3
local REPEAT_MINUTES = 20
local SPEED = 120 -- píxeles por segundo
local START_DELAY = 8

local me = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 80)

local gui = Instance.new("ScreenGui")
gui.Name = "BetaBannerGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 150
gui.Parent = me:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, -60)
bar.Size = UDim2.new(0.82, 0, 0, 38)
bar.BackgroundColor3 = Color3.fromRGB(26, 14, 40)
bar.BackgroundTransparency = 0.08
bar.BorderSizePixel = 0
bar.Visible = false
bar.Parent = gui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = bar
local stroke = Instance.new("UIStroke")
stroke.Color = GOLD
stroke.Thickness = 2
stroke.Parent = bar

local badge = Instance.new("TextLabel")
badge.Size = UDim2.fromOffset(112, 38)
badge.BackgroundColor3 = GOLD
badge.Font = Enum.Font.GothamBlack
badge.TextSize = 16
badge.TextColor3 = Color3.fromRGB(40, 22, 10)
badge.Text = "BETA ABIERTA"
badge.ZIndex = 3
badge.Parent = bar
local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(0, 10)
badgeCorner.Parent = badge

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(30, 30)
close.Position = UDim2.new(1, -34, 0, 4)
close.BackgroundColor3 = Color3.fromRGB(190, 56, 62)
close.Font = Enum.Font.GothamBlack
close.TextSize = 16
close.TextColor3 = Color3.new(1, 1, 1)
close.Text = "X"
close.ZIndex = 3
close.Parent = bar
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 8)
closeCorner.Parent = close

local clip = Instance.new("Frame")
clip.Position = UDim2.fromOffset(120, 0)
clip.Size = UDim2.new(1, -160, 1, 0)
clip.BackgroundTransparency = 1
clip.ClipsDescendants = true
clip.Parent = bar

local msg = Instance.new("TextLabel")
msg.BackgroundTransparency = 1
msg.Font = Enum.Font.GothamBold
msg.TextSize = 20
msg.TextColor3 = Color3.fromRGB(255, 240, 200)
msg.TextXAlignment = Enum.TextXAlignment.Left
msg.Text = MESSAGE
msg.Parent = clip
local textW = TextService:GetTextSize(MESSAGE, 20, Enum.Font.GothamBold, Vector2.new(10000, 38)).X + 20
msg.Size = UDim2.fromOffset(textW, 38)

local cancelled = false
close.Activated:Connect(function()
	cancelled = true
end)

local function showPasses(passes: number)
	cancelled = false
	bar.Visible = true
	TweenService:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 8) }):Play()
	for _ = 1, passes do
		if cancelled then
			break
		end
		local w = clip.AbsoluteSize.X
		msg.Position = UDim2.fromOffset(w, 0)
		local dur = (w + textW) / SPEED
		local tw = TweenService:Create(msg, TweenInfo.new(dur, Enum.EasingStyle.Linear), { Position = UDim2.fromOffset(-textW, 0) })
		tw:Play()
		local t0 = os.clock()
		while os.clock() - t0 < dur and not cancelled do
			task.wait(0.1)
		end
		tw:Cancel()
	end
	local out = TweenService:Create(bar, TweenInfo.new(0.35), { Position = UDim2.new(0.5, 0, 0, -60) })
	out:Play()
	out.Completed:Wait()
	bar.Visible = false
end

task.spawn(function()
	task.wait(START_DELAY)
	showPasses(PASSES_ON_JOIN)
	while true do
		task.wait(REPEAT_MINUTES * 60)
		showPasses(1)
	end
end)
