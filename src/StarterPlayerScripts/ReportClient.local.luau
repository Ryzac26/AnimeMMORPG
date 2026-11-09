--!nonstrict
--[[
    ReportClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ReportClient
    Botón "REPORTAR" (borde derecho de la pantalla) -> ventana para escribir el problema y enviarlo (ver ReportService).
    Si eres el dueño del juego (o admin) aparece también "Ver reportes": cada reporte muestra solo quién lo mandó, motivo y descripción, en bloques
    (cada bloque tiene su botón "Seleccionar" y luego Ctrl+C). No hay tope de caracteres en el formulario (el servidor guarda hasta 4000).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local LogService = game:GetService("LogService")
local player = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
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
	WindowDrag.Attach(f, "Report_" .. title, 44, 50)
	return f
end

-- botón flotante: arriba a la derecha (bajo los avisos de evento) y se puede ARRASTRAR; un toque corto abre el formulario
local open = button(gui, "REPORTAR", UDim2.new(1, -92, 0, 172), UDim2.fromOffset(84, 28), ACCENT)
open.TextSize = 12
open.BackgroundTransparency = 0.15
local onOpen = function() end
do
	local dragging, moved, startPos, startMouse = false, false, nil, nil
	open.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			startPos, startMouse = open.Position, input.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startMouse
			if d.Magnitude > 6 then
				moved = true
			end
			if moved then
				local view = gui.AbsoluteSize
				local sx = startPos.X.Scale * view.X + startPos.X.Offset + d.X
				local sy = startPos.Y.Scale * view.Y + startPos.Y.Offset + d.Y
				sx = math.clamp(sx, 0, view.X - open.AbsoluteSize.X)
				sy = math.clamp(sy, 0, view.Y - open.AbsoluteSize.Y)
				open.Position = UDim2.fromOffset(sx, sy)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if not moved then
				onOpen()
			end
		end
	end)
end

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
box.PlaceholderText = "Cuéntanos con detalle: qué pasó, dónde estabas, qué esperabas que pasara, o tu idea para mejorar el juego."
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

onOpen = function()
	form.Visible = not form.Visible
	status.Text = ""
end

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

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 10)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = scroll
local listPad = Instance.new("UIPadding")
listPad.PaddingLeft, listPad.PaddingTop, listPad.PaddingRight, listPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 6)
listPad.Parent = scroll

local blocks: { Instance } = {}
local function clearBlocks()
	for _, b in ipairs(blocks) do
		b:Destroy()
	end
	table.clear(blocks)
end

local function info(text: string)
	clearBlocks()
	local l = label(scroll, text, 14, UDim2.new(), UDim2.new(1, 0, 0, 24), Color3.fromRGB(190, 190, 205))
	table.insert(blocks, l)
end

-- Cada bloque es una caja de solo lectura (Roblox corta una caja a ~16000 caracteres, por eso se reparte en bloques de <12000)
local BLOCK_CHARS = 12000
local function render(items: { string })
	clearBlocks()
	if #items == 0 then
		info("No hay reportes.")
		return
	end
	local idx, blockNo = 1, 0
	while idx <= #items do
		local first, parts, len = idx, {}, 0
		while idx <= #items and (len == 0 or len + #items[idx] < BLOCK_CHARS) do
			table.insert(parts, items[idx])
			len += #items[idx] + 2
			idx += 1
		end
		blockNo += 1
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.Size = UDim2.new(1, 0, 0, 0)
		holder.AutomaticSize = Enum.AutomaticSize.Y
		holder.LayoutOrder = blockNo
		holder.Parent = scroll
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 4)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = holder
		local text = table.concat(parts, "\n\n")
		local sel = button(holder, ("Seleccionar reportes %d a %d (luego Ctrl+C)"):format(first, idx - 1), UDim2.new(), UDim2.fromOffset(330, 28), ACCENT)
		sel.LayoutOrder = 1
		local box2 = Instance.new("TextBox")
		box2.Size = UDim2.new(1, 0, 0, 0)
		box2.AutomaticSize = Enum.AutomaticSize.Y
		box2.BackgroundTransparency = 1
		box2.TextColor3 = TXT
		box2.Font = Enum.Font.Code
		box2.TextSize = 14
		box2.TextWrapped = true
		box2.MultiLine = true
		box2.ClearTextOnFocus = false
		box2.TextXAlignment = Enum.TextXAlignment.Left
		box2.TextYAlignment = Enum.TextYAlignment.Top
		box2.Text = text
		box2.LayoutOrder = 2
		box2.Parent = holder
		-- solo lectura: si se edita vuelve al texto original (así se puede seleccionar y copiar)
		box2:GetPropertyChangedSignal("Text"):Connect(function()
			if box2.Text ~= text then
				box2.Text = text
			end
		end)
		sel.Activated:Connect(function()
			box2:CaptureFocus()
			box2.CursorPosition = 1
			box2.SelectionStart = #box2.Text + 1
		end)
		table.insert(blocks, holder)
	end
end

local refresh = button(admin, "Actualizar", UDim2.fromOffset(16, 470 - 46), UDim2.fromOffset(100, 32), PANEL)
local clear = button(admin, "Borrar todos", UDim2.new(1, -126, 1, -46), UDim2.fromOffset(110, 32), Color3.fromRGB(120, 50, 50))

refresh.Activated:Connect(function()
	info("Cargando...")
	adminR:FireServer("list")
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
	info("Borrando...")
	adminR:FireServer("clear")
end)
adminR.OnClientEvent:Connect(function(kind, text, n)
	if kind == "list" then
		render(if typeof(text) == "table" then text else {})
		countLbl.Text = tostring(n) .. " reporte(s) · los más nuevos primero"
	end
end)

viewBtn.Activated:Connect(function()
	form.Visible = false
	admin.Visible = true
	info("Cargando...")
	adminR:FireServer("list")
end)

local function checkAdmin()
	viewBtn.Visible = player:GetAttribute("ReportAdmin") == true
end
player:GetAttributeChangedSignal("ReportAdmin"):Connect(checkAdmin)
checkAdmin()
