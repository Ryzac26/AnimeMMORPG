--!nonstrict
--[[
    BlessMailClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BlessMailClient
    CARTA de bendiciones por reclamar: aparece debajo del botón REPORTAR solo cuando el jugador tiene tiempo de bendición de facción
    que se le devolvió al cerrarse un servidor (atributo del jugador "BlessMail", lo pone BlessingService). Al abrirla, cada bendición
    tiene su botón RECLAMAR: el tiempo vuelve a ser una bendición de toda su facción. Si no queda nada, la carta desaparece.
    Si la misma bendición ya está activa en su facción, el servidor le avisa que espere a que termine.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local claimR = ClientNet.Get("BlessClaim")
if not claimR then
	return
end
local houseR = ClientNet.Get("HouseAction") -- para "Suscribirme" desde la carta del Pabellón

local BG, PANEL, ACCENT, TXT, GREY = Color3.fromRGB(24, 24, 34), Color3.fromRGB(38, 38, 52), Color3.fromRGB(235, 175, 60), Color3.fromRGB(235, 235, 240), Color3.fromRGB(160, 164, 184)
local LETTER_POS = UDim2.new(1, -92, 0, 206) -- debajo del botón REPORTAR (que está en 1,-92 / 0,172)

local gui = Instance.new("ScreenGui")
gui.Name = "BlessMailGui"
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
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color or PANEL
	b.Position = pos
	b.Size = dim
	b.Parent = parent
	corner(b, 8)
	return b
end

-- botón de la carta
local letter = button(gui, "✉ CARTA", LETTER_POS, UDim2.fromOffset(84, 28), ACCENT)
letter.TextSize = 12
letter.TextColor3 = Color3.fromRGB(40, 28, 6)
letter.Visible = false

-- ventana
local win = Instance.new("Frame")
win.AnchorPoint = Vector2.new(0.5, 0.5)
win.Position = UDim2.fromScale(0.5, 0.5)
win.Size = UDim2.fromOffset(440, 250)
win.BackgroundColor3 = BG
win.Visible = false
win.Parent = gui
corner(win, 12)
local st = Instance.new("UIStroke")
st.Color = ACCENT
st.Thickness = 1.5
st.Parent = win
label(win, "✉ Cartas", 18, UDim2.fromOffset(16, 10), UDim2.new(1, -60, 0, 26), TXT, true)
local x = button(win, "X", UDim2.new(1, -42, 0, 10), UDim2.fromOffset(30, 26), PANEL)
x.Activated:Connect(function()
	win.Visible = false
end)
WindowDrag.Attach(win, "BlessMail", 44, 50)
local intro = label(win, "", 12, UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 48), GREY)

local list = Instance.new("Frame")
list.BackgroundTransparency = 1
list.Position = UDim2.fromOffset(16, 94)
list.Size = UDim2.new(1, -32, 1, -104)
list.Parent = win
local lay = Instance.new("UIListLayout")
lay.Padding = UDim.new(0, 6)
lay.Parent = list

local function fmtTime(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	if h > 0 then
		return string.format("%d h %02d min", h, m)
	end
	return string.format("%d min", m)
end

local function render()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local raw = player:GetAttribute("BlessMail")
	local data = {}
	if typeof(raw) == "string" and raw ~= "" then
		local ok, dec = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if ok and typeof(dec) == "table" then
			data = dec
		end
	end
	-- carta del Pabellón Imperial (recordatorio de suscripción)
	local house
	local hraw = player:GetAttribute("HouseSubMail")
	if typeof(hraw) == "string" and hraw ~= "" then
		local ok, dec = pcall(function()
			return HttpService:JSONDecode(hraw)
		end)
		if ok and typeof(dec) == "table" and typeof(dec.u) == "number" then
			house = dec
		end
	end
	letter.Visible = #data > 0 or house ~= nil
	if #data == 0 and not house then
		win.Visible = false
		return
	end
	intro.Text = if #data > 0
		then "El servidor se cerró y te quedó tiempo de bendición de facción. Al reclamarlo vuelve a activarse para toda tu facción. Si tu facción ya tiene esa misma bendición activa, espera a que termine."
		else "Tienes un aviso de tu Casa VIP."
	intro.Size = if #data > 0 then UDim2.new(1, -32, 0, 48) else UDim2.new(1, -32, 0, 20)
	list.Position = if #data > 0 then UDim2.fromOffset(16, 94) else UDim2.fromOffset(16, 66)
	win.Size = UDim2.fromOffset(440, (if #data > 0 then 110 else 82) + 64 * (#data + (if house then 1 else 0)))
	if house then
		local row = Instance.new("Frame")
		row.BackgroundColor3 = PANEL
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = 0
		row.Parent = list
		corner(row, 8)
		label(row, "👑 Pabellón Imperial: suscríbete", 14, UDim2.fromOffset(10, 4), UDim2.new(1, -120, 0, 20), TXT, true)
		local now = os.time()
		local daysIncluded = math.ceil(((house.l or 0) - now) / 86400)
		local detail
		if daysIncluded > 0 then
			detail = string.format("Tu mes incluido termina en %d día(s). Suscríbete (%s) para conservar tu casa.", daysIncluded, tostring(house.p or ""))
		else
			detail = string.format("Tu mes terminó: la casa vence en %d h si no te suscribes (%s).", math.max(0, math.ceil(((house.u or 0) - now) / 3600)), tostring(house.p or ""))
		end
		label(row, detail, 11, UDim2.fromOffset(10, 26), UDim2.new(1, -120, 0, 28), GREY)
		local sub = button(row, "SUSCRIBIRME", UDim2.new(1, -104, 0.5, -16), UDim2.fromOffset(94, 32), Color3.fromRGB(150, 110, 40))
		sub.TextSize = 11
		sub.Activated:Connect(function()
			if houseR then
				houseR:FireServer("BuySub")
			end
		end)
	end
	for i, e in ipairs(data) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = PANEL
		row.Size = UDim2.new(1, 0, 0, 58)
		row.LayoutOrder = i
		row.Parent = list
		corner(row, 8)
		label(row, e.n, 14, UDim2.fromOffset(10, 4), UDim2.new(1, -120, 0, 20), TXT, true)
		local days = math.max(0, math.ceil(((e.exp or 0) - Workspace:GetServerTimeNow()) / 86400))
		label(row, string.format("%s · quedan %s · vence en %d día(s)", e.s, fmtTime(e.sec or 0), days), 11, UDim2.fromOffset(10, 26), UDim2.new(1, -120, 0, 28), GREY)
		local claim = button(row, "RECLAMAR", UDim2.new(1, -104, 0.5, -16), UDim2.fromOffset(94, 32), Color3.fromRGB(60, 150, 80))
		claim.Activated:Connect(function()
			claim.Active = false
			claim.Text = "..."
			claimR:FireServer(e.g)
			task.delay(2, function()
				if claim.Parent then
					claim.Active = true
					claim.Text = "RECLAMAR"
				end
			end)
		end)
	end
end

letter.Activated:Connect(function()
	win.Visible = not win.Visible
	if win.Visible then
		render()
	end
end)
player:GetAttributeChangedSignal("BlessMail"):Connect(render)
player:GetAttributeChangedSignal("HouseSubMail"):Connect(render)
render()
