--!nonstrict
--[[
    UpdateNoticeClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > UpdateNoticeClient
    CARTEL DE ACTUALIZACIÓN: una franja delgada y discreta arriba de la pantalla (se puede cerrar con ×).
      · Reinicio programado (Creator Hub > Servidor > Reiniciar con demora): "Actualización disponible: el servidor se reinicia en 08:42".
      · Versión nueva sin reinicio: "Hay una versión nueva del juego".
    El botón "Cambiar de servidor" guarda tu progreso y te manda a un servidor con la versión nueva (lo hace UpdateNotice en el servidor).
    Lee los atributos de Workspace: UpdateRestartAt (hora del reinicio, segundos), UpdateMsg (mensaje opcional) y UpdateNewVersion (true).
    El mensaje que escribes al programar el reinicio se desplaza como un LETRERO (marquesina) de forma continua hasta que se completa el cambio;
    el texto fijo (cuenta atrás) queda a la izquierda y el botón "Cambiar de servidor" a la derecha.
    Ajustes: BAR_POS (posición de la franja), BAR_WIDTH (ancho), SCROLL_SPEED (píxeles/seg) y SCROLL_DIR (-1 = el texto avanza hacia la izquierda, 1 = hacia la derecha).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local switchR = ClientNet.Get("UpdateSwitch")
if not switchR then
	return
end

local BAR_POS = UDim2.new(0.5, 0, 0, 6) -- arriba al centro
local BAR_WIDTH = 680
local SCROLL_SPEED = 70
local SCROLL_DIR = -1
local BG, TXT = Color3.fromRGB(28, 30, 44), Color3.fromRGB(235, 235, 240)
local WARN, OK = Color3.fromRGB(235, 175, 60), Color3.fromRGB(60, 150, 80)

local gui = Instance.new("ScreenGui")
gui.Name = "UpdateNoticeGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 45
gui.Parent = player:WaitForChild("PlayerGui", 10)

local bar = Instance.new("Frame")
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = BAR_POS
bar.Size = UDim2.fromOffset(BAR_WIDTH, 30)
bar.BackgroundColor3 = BG
bar.BackgroundTransparency = 0.12
bar.Visible = false
bar.Parent = gui
local c = Instance.new("UICorner")
c.CornerRadius = UDim.new(0, 8)
c.Parent = bar
local stroke = Instance.new("UIStroke")
stroke.Color = WARN
stroke.Thickness = 1
stroke.Transparency = 0.2
stroke.Parent = bar

-- texto fijo (izquierda)
local msg = Instance.new("TextLabel")
msg.BackgroundTransparency = 1
msg.Position = UDim2.fromOffset(10, 0)
msg.Size = UDim2.new(0, 0, 1, 0)
msg.AutomaticSize = Enum.AutomaticSize.X
msg.Font = Enum.Font.GothamBold
msg.TextSize = 12
msg.TextColor3 = TXT
msg.TextXAlignment = Enum.TextXAlignment.Left
msg.Parent = bar

-- letrero que se desplaza (mensaje de la descripción)
local tickerClip = Instance.new("Frame")
tickerClip.BackgroundTransparency = 1
tickerClip.ClipsDescendants = true
tickerClip.Position = UDim2.fromOffset(10, 0)
tickerClip.Size = UDim2.new(1, -190, 1, 0)
tickerClip.Parent = bar
local ticker = Instance.new("TextLabel")
ticker.BackgroundTransparency = 1
ticker.Size = UDim2.new(0, 0, 1, 0)
ticker.AutomaticSize = Enum.AutomaticSize.X
ticker.Font = Enum.Font.GothamMedium
ticker.TextSize = 12
ticker.TextColor3 = TXT
ticker.TextXAlignment = Enum.TextXAlignment.Left
ticker.Text = ""
ticker.Parent = tickerClip
local tickerX = 0
local tickerText = ""

local go = Instance.new("TextButton")
go.Text = "Cambiar de servidor"
go.Font = Enum.Font.GothamBold
go.TextSize = 12
go.TextColor3 = Color3.new(1, 1, 1)
go.BackgroundColor3 = OK
go.AnchorPoint = Vector2.new(1, 0.5)
go.Position = UDim2.new(1, -38, 0.5, 0)
go.Size = UDim2.fromOffset(138, 22)
go.Parent = bar
local gc = Instance.new("UICorner")
gc.CornerRadius = UDim.new(0, 6)
gc.Parent = go

local close = Instance.new("TextButton")
close.Text = "×"
close.Font = Enum.Font.GothamBold
close.TextSize = 16
close.TextColor3 = TXT
close.BackgroundTransparency = 1
close.AnchorPoint = Vector2.new(1, 0.5)
close.Position = UDim2.new(1, -8, 0.5, 0)
close.Size = UDim2.fromOffset(24, 24)
close.Parent = bar

local dismissedKey: string? = nil -- qué aviso se cerró (si cambia el aviso, vuelve a salir)
local function stateKey(): string?
	local at = Workspace:GetAttribute("UpdateRestartAt")
	if typeof(at) == "number" and at > 0 then
		return "r" .. at
	end
	if Workspace:GetAttribute("UpdateNewVersion") == true then
		return "v"
	end
	return nil
end

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local function refresh()
	local key = stateKey()
	if not key then
		bar.Visible = false
		return
	end
	local at = Workspace:GetAttribute("UpdateRestartAt")
	local left = if typeof(at) == "number" and at > 0 then at - Workspace:GetServerTimeNow() else nil
	-- cerrado por el jugador: solo vuelve a salir en el último minuto antes del reinicio
	if dismissedKey == key and not (left and left <= 60) then
		bar.Visible = false
		return
	end
	bar.Visible = true
	local extra = Workspace:GetAttribute("UpdateMsg")
	local fixed, scroll
	if left then
		fixed = string.format("⚠ Actualización: el servidor se reinicia en %s", fmt(left))
		scroll = if typeof(extra) == "string" then extra else ""
	else
		fixed = "⚠ Hay una versión nueva del juego: cambia de servidor para actualizar"
		scroll = ""
	end
	msg.Text = fixed
	-- el letrero ocupa el espacio que deja el texto fijo
	local used = if scroll ~= "" then msg.AbsoluteSize.X + 18 else 0
	tickerClip.Position = UDim2.fromOffset(10 + used, 0)
	tickerClip.Size = UDim2.new(1, -(190 + used), 1, 0)
	if scroll ~= tickerText then
		tickerText = scroll
		ticker.Text = scroll
		tickerX = tickerClip.AbsoluteSize.X
	end
end

-- animación continua del letrero (solo se mueve si no cabe; si cabe, queda fijo)
RunService.RenderStepped:Connect(function(dt)
	if not bar.Visible or tickerText == "" then
		return
	end
	local w = ticker.AbsoluteSize.X
	local area = tickerClip.AbsoluteSize.X
	if w <= area then
		ticker.Position = UDim2.fromOffset(0, 0)
		return
	end
	tickerX += SCROLL_DIR * SCROLL_SPEED * dt
	if SCROLL_DIR < 0 and tickerX < -w then
		tickerX = area
	elseif SCROLL_DIR > 0 and tickerX > area then
		tickerX = -w
	end
	ticker.Position = UDim2.fromOffset(math.floor(tickerX), 0)
end)

go.Activated:Connect(function()
	go.Active = false
	go.Text = "Viajando..."
	switchR:FireServer()
	task.delay(8, function()
		go.Active = true
		go.Text = "Cambiar de servidor"
	end)
end)
close.Activated:Connect(function()
	dismissedKey = stateKey()
	refresh()
end)
Workspace:GetAttributeChangedSignal("UpdateRestartAt"):Connect(refresh)
Workspace:GetAttributeChangedSignal("UpdateNewVersion"):Connect(refresh)
Workspace:GetAttributeChangedSignal("UpdateMsg"):Connect(refresh)
task.spawn(function()
	while gui.Parent do
		refresh()
		task.wait(1)
	end
end)
refresh()
