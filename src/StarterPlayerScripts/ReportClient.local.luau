--!nonstrict
--[[
    ReportClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ReportClient
    Botón "REPORTAR" (borde derecho de la pantalla) -> ventana para escribir el problema y enviarlo (ver ReportService).
    Si eres el dueño del juego (o admin) aparece también "Ver reportes": una caja con todos los reportes; pulsa "Seleccionar todo" y Ctrl+C para copiarlos.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local submitR = ClientNet.Get("ReportSubmit")
local adminR = ClientNet.Get("ReportAdmin")
if not submitR or not adminR then
	return
end

-- últimos errores del cliente (se mandan con el reporte)
local clientLog: { string } = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
		table.insert(clientLog, (if kind == Enum.MessageType.MessageError then "[E] " else "[W] ") .. string.sub(msg, 1, 220))
		if #clientLog > 10 then
			table.remove(clientLog, 1)
		end
	end
end)

local BG, PANEL, ACCENT, TXT = Color3.fromRGB(24, 24, 34), Color3.fromRGB(38, 38, 52), Color3.fromRGB(220, 90, 70), Color3.fromRGB(235, 235, 240)

local gui = Instance.new("ScreenGui")
gui.Name = "ReportGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 40
gui.Parent = player:WaitForChild("PlayerGui", 10)

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = o
end

local function label(parent, text, size, pos, dim, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
	l.TextSize = size
	l.TextColor3 = color or TXT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Position = pos
	l.Size = dim
	l.Parent = parent
	return l
end

local function button(parent, text, pos, dim, color)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color or PANEL
	b.AutoButtonColor = true
	b.Position = pos
	b.Size = dim
	b.Parent = parent
	corner(b, 8)
	return b
end

local function window(w, h, title)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = BG
	f.Visible = false
	f.Parent = gui
	corner(f, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = ACCENT
	stroke.Thickness = 1.5
	stroke.Parent = f
	label(f, title, 18, UDim2.fromOffset(16, 10), UDim2.new(1, -60, 0, 26), TXT, true)
	local x = button(f, "X", UDim2.new(1, -42, 0, 10), UDim2.fromOffset(30, 26), PANEL)
	x.Activated:Connect(function()
		f.Visible = false
	end)
	return f
end

-- botón flotante
local open = button(gui, "REPORTAR", UDim2.new(1, -92, 0.5, 90), UDim2.fromOffset(84, 28), ACCENT)
open.TextSize = 12
open.BackgroundTransparency = 0.15

---------------------------------------------------------------------
-- formulario
---------------------------------------------------------------------
local form = window(440, 372, "Reportar un problema")
local cats = { { "Error", "Error" }, { "Visual", "Se ve mal" }, { "Balance", "Balance" }, { "Idea", "Idea" } }
local chosen = "Error"
local catBtns = {}
for i, c in ipairs(cats) do
	local b = button(form, c[2], UDim2.fromOffset(16 + (i - 1) * 102, 46), UDim2.fromOffset(98, 28), PANEL)
	catBtns[c[1]] = b
	b.Activated:Connect(function()
		chosen = c[1]
		for k, o in pairs(catBtns) do
			o.BackgroundColor3 = if k == chosen then ACCENT else PANEL
		end
	end)
end
catBtns.Error.BackgroundColor3 = ACCENT

local box = Instance.new("TextBox")
box.Position = UDim2.fromOffset(16, 84)
box.Size = UDim2.new(1, -32, 0, 170)
box.BackgroundColor3 = PANEL
box.TextColor3 = TXT
box.PlaceholderColor3 = Color3.fromRGB(150, 150, 165)
box.PlaceholderText = "Qué pasó, dónde estabas y qué esperabas que pasara."
box.Font = Enum.Font.Gotham
box.TextSize = 15
box.TextWrapped = true
box.MultiLine = true
box.ClearTextOnFocus = false
box.TextXAlignment = Enum.TextXAlignment.Left
box.TextYAlignment = Enum.TextYAlignment.Top
box.Text = ""
box.Parent = form
corner(box, 8)
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingTop, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 6), UDim.new(0, 8)
pad.Parent = box
box:GetPropertyChangedSignal("Text"):Connect(function()
	if #box.Text > 600 then
		box.Text = string.sub(box.Text, 1, 600)
	end
end)

label(form, "Se adjuntan solos: personaje, nivel, posición y errores recientes.", 12, UDim2.fromOffset(16, 260), UDim2.new(1, -32, 0, 30), Color3.fromRGB(165, 165, 180))
local status = label(form, "", 13, UDim2.fromOffset(16, 292), UDim2.new(1, -32, 0, 20), Color3.fromRGB(255, 220, 120))
local send = button(form, "Enviar", UDim2.new(1, -126, 1, -44), UDim2.fromOffset(110, 32), ACCENT)
local viewBtn = button(form, "Ver reportes", UDim2.fromOffset(16, 372 - 44), UDim2.fromOffset(120, 32), PANEL)
viewBtn.Visible = false

send.Activated:Connect(function()
	if #box.Text < 5 then
		status.Text = "Escribe al menos unas palabras."
		return
	end
	submitR:FireServer(chosen, box.Text, clientLog)
	status.Text = "Enviando..."
end)

submitR.OnClientEvent:Connect(function(result, extra)
	if result == "ok" then
		status.Text = "¡Enviado! Gracias."
		box.Text = ""
		task.delay(1.5, function()
			if status.Text == "¡Enviado! Gracias." then
				form.Visible = false
				status.Text = ""
			end
		end)
	elseif result == "wait" then
		status.Text = "Espera " .. tostring(extra) .. " s para enviar otro."
	elseif result == "short" then
		status.Text = "Escribe al menos unas palabras."
	end
end)

open.Activated:Connect(function()
	form.Visible = not form.Visible
	status.Text = ""
end)

---------------------------------------------------------------------
-- ventana de reportes (solo dueño / admins)
---------------------------------------------------------------------
local admin = window(660, 470, "Reportes recibidos")
local countLbl = label(admin, "", 13, UDim2.fromOffset(190, 14), UDim2.new(1, -250, 0, 20), Color3.fromRGB(165, 165, 180))
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(16, 46)
scroll.Size = UDim2.new(1, -32, 1, -100)
scroll.BackgroundColor3 = PANEL
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 8
scroll.Parent = admin
corner(scroll, 8)

local shown = ""
local all = Instance.new("TextBox")
all.Size = UDim2.new(1, -12, 0, 0)
all.AutomaticSize = Enum.AutomaticSize.Y
all.BackgroundTransparency = 1
all.TextColor3 = TXT
all.Font = Enum.Font.Code
all.TextSize = 13
all.TextWrapped = true
all.MultiLine = true
all.ClearTextOnFocus = false
all.TextXAlignment = Enum.TextXAlignment.Left
all.TextYAlignment = Enum.TextYAlignment.Top
all.Text = "Cargando..."
all.Parent = scroll
-- solo lectura: si se edita, vuelve al texto original (así se puede seleccionar y copiar con Ctrl+C)
all:GetPropertyChangedSignal("Text"):Connect(function()
	if all.Text ~= shown then
		all.Text = shown
	end
end)

local refresh = button(admin, "Actualizar", UDim2.fromOffset(16, 470 - 46), UDim2.fromOffset(100, 32), PANEL)
local selectAll = button(admin, "Seleccionar todo (luego Ctrl+C)", UDim2.fromOffset(126, 470 - 46), UDim2.fromOffset(250, 32), ACCENT)
local clear = button(admin, "Borrar todos", UDim2.new(1, -126, 1, -46), UDim2.fromOffset(110, 32), Color3.fromRGB(120, 50, 50))

local function setText(t)
	shown = t
	all.Text = t
end

refresh.Activated:Connect(function()
	setText("Cargando...")
	adminR:FireServer("list")
end)
selectAll.Activated:Connect(function()
	all:CaptureFocus()
	all.CursorPosition = 1
	all.SelectionStart = #all.Text + 1
end)
local armed = false
clear.Activated:Connect(function()
	if not armed then
		armed = true
		clear.Text = "¿Seguro? Pulsa otra vez"
		task.delay(3, function()
			armed = false
			clear.Text = "Borrar todos"
		end)
		return
	end
	armed = false
	clear.Text = "Borrar todos"
	setText("Borrando...")
	adminR:FireServer("clear")
end)
adminR.OnClientEvent:Connect(function(kind, text, n)
	if kind == "list" then
		setText(text)
		countLbl.Text = n .. " reporte(s) (los " .. "más nuevos primero)"
	end
end)

viewBtn.Activated:Connect(function()
	form.Visible = false
	admin.Visible = true
	setText("Cargando...")
	adminR:FireServer("list")
end)

local function checkAdmin()
	viewBtn.Visible = player:GetAttribute("ReportAdmin") == true
end
player:GetAttributeChangedSignal("ReportAdmin"):Connect(checkAdmin)
checkAdmin()
