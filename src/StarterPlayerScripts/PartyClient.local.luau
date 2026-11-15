--!strict
--[[
    PartyClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > PartyClient
    Panel de GRUPO (izquierda de la pantalla): vida y energía en % de cada miembro, botón "+" para invitar a jugadores de tu facción,
    "Salir", y la ventana de invitación (Aceptar / Rechazar). Se minimiza con ▲/▼. Atajo: P abre/cierra la lista de invitables.
    LÍDER: toca la tarjeta de otro miembro y aparecen "★ Hacer líder" y "✕ Expulsar" (Expulsar pide una segunda pulsación para confirmar).
    El panel solo se reconstruye cuando cambia la estructura (entra/sale alguien, cambia el líder, abres una lista...); la vida y la energía
    se actualizan en el sitio. Antes se reconstruía cada segundo y un clic podía perderse justo cuando se rehacía el botón.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local remote = ReplicatedStorage:WaitForChild("Remotes", 10):WaitForChild("Party", 10) :: RemoteEvent
local theme = UITheme.For(player:GetAttribute("Faction"))
local MOBILE = require(script.Parent:WaitForChild("Platform", 10)).IsMobile()

local gui = Instance.new("ScreenGui")
gui.Name = "PartyGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui", 10)

local holder = Instance.new("Frame")
holder.Position = if MOBILE then UDim2.new(0, 12, 0, 76) else UDim2.new(0, 14, 0, 200)
holder.Size = UDim2.fromOffset(190, 10)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Parent = gui
require(script.Parent:WaitForChild("SideCollapse", 10)).Attach(gui, holder, "Left", "Party", 190)
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = holder

local head = Instance.new("TextButton")
head.LayoutOrder = 1
head.Size = UDim2.fromOffset(190, 24)
head.BackgroundColor3 = theme.Dark
head.BackgroundTransparency = 0.15
head.Font = UITheme.Font
head.TextSize = 12
head.TextColor3 = theme.Primary
head.Parent = holder
Instance.new("UICorner", head).CornerRadius = UDim.new(0, 6)
UITheme.Border(head, theme, 1)

local body = Instance.new("Frame")
body.LayoutOrder = 2
body.Size = UDim2.fromOffset(190, 10)
body.AutomaticSize = Enum.AutomaticSize.Y
body.BackgroundTransparency = 1
body.Parent = holder
local bl = Instance.new("UIListLayout")
bl.Padding = UDim.new(0, 3)
bl.SortOrder = Enum.SortOrder.LayoutOrder
bl.Parent = body

local expanded = true
local members: { any } = {}
local invitesOpen = false
local selected: string? = nil -- (solo líder) miembro que tocaste: muestra "Hacer líder" / "Expulsar"
local kickArmed: string? = nil -- "Expulsar" pulsado una vez: la segunda pulsación (dentro de 4 s) confirma
local armToken = 0
local lastSig = ""

type CardRef = { HpFill: Frame, HpText: TextLabel?, EnFill: Frame, EnText: TextLabel? }
local refs: { [string]: CardRef } = {}

local function button(parent: Instance, text: string, order: number, w: number): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(w, 22)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.2
	b.Font = UITheme.Font
	b.TextSize = 11
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

-- barra de vida / energía. Devuelve el relleno y (si lleva texto) la etiqueta, para poder actualizarlos sin reconstruir
local function bar(parent: Instance, y: number, frac: number, color: Color3, text: string, x: number?, w: number?, h: number?): (Frame, TextLabel?)
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(x or 6, y)
	back.Size = if w then UDim2.fromOffset(w, h or 9) else UDim2.new(1, -12, 0, h or 9)
	back.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	back.BorderSizePixel = 0
	back.Parent = parent
	Instance.new("UICorner", back).CornerRadius = UDim.new(0, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
	local label: TextLabel? = nil
	if text ~= "" then
		local t = UITheme.Text(back, text, 8, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		t.ZIndex = 3
		label = t
	end
	return fill, label
end

local function amLeader(): boolean
	for _, m in ipairs(members) do
		if m.Name == player.Name and m.Leader == true then
			return true
		end
	end
	return false
end

-- firma de lo que hay en pantalla: si no cambia, no se reconstruye (solo se actualizan las barras)
local function signature(): string
	local parts: { string } = { tostring(expanded), tostring(invitesOpen), tostring(selected), tostring(kickArmed) }
	for _, m in ipairs(members) do
		table.insert(parts, (if m.Leader then "*" else "") .. tostring(m.Name))
	end
	if invitesOpen then
		for _, p in ipairs(Players:GetPlayers()) do
			table.insert(parts, p.Name .. ":" .. tostring(p:GetAttribute("Faction")))
		end
	end
	return table.concat(parts, "|")
end

local function render()
	lastSig = signature()
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	refs = {}
	head.Text = (if #members > 0 then string.format("GRUPO (%d)", #members) else "GRUPO") .. (if expanded then "  ▲" else "  ▼")
	body.Visible = expanded
	if not expanded then
		return
	end
	local leader = amLeader()
	local compact = #members > 5 -- grupos grandes (hasta 15): tarjetas de una sola línea para que quepan en pantalla
	for i, m in ipairs(members) do
		local name = tostring(m.Name)
		local clickable = leader and name ~= player.Name
		local isSel = clickable and selected == name
		local card: GuiObject
		if clickable then
			local cb = Instance.new("TextButton")
			cb.Text = ""
			cb.AutoButtonColor = false
			cb.Activated:Connect(function()
				selected = if selected == name then nil else name
				kickArmed = nil
				render()
			end)
			card = cb
		else
			card = Instance.new("Frame")
		end
		card.LayoutOrder = i * 10
		card.Size = UDim2.fromOffset(190, if compact then 24 else 46)
		card.BackgroundColor3 = if isSel then theme.Primary:Lerp(theme.Dark, 0.65) else theme.Dark
		card.BackgroundTransparency = 0.2
		card.BorderSizePixel = 0
		card.Parent = body
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
		if isSel then
			local st = Instance.new("UIStroke")
			st.Color = theme.Primary
			st.Thickness = 1
			st.Parent = card
		end
		if compact then
			local nm = UITheme.Text(card, (if m.Leader then "★ " else "") .. name, 10, Color3.new(1, 1, 1), UDim2.fromOffset(6, 0), UDim2.fromOffset(88, 24))
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			local hf, ht = bar(card, 4, m.Hp / 100, Color3.fromRGB(235, 80, 90), "", 98, 86, 7)
			local ef, et = bar(card, 13, m.En / 100, theme.ResourceColor, "", 98, 86, 7)
			refs[name] = { HpFill = hf, HpText = ht, EnFill = ef, EnText = et }
		else
			local nm = UITheme.Text(card, (if m.Leader then "★ " else "") .. name, 11, Color3.new(1, 1, 1), UDim2.fromOffset(6, 2), UDim2.new(1, -30, 0, 14))
			nm.TextTruncate = Enum.TextTruncate.AtEnd
			if clickable then
				UITheme.Text(card, if isSel then "▴" else "▾", 11, Color3.fromRGB(190, 190, 205), UDim2.fromOffset(170, 2), UDim2.fromOffset(14, 14), Enum.TextXAlignment.Center)
			end
			local hf, ht = bar(card, 18, m.Hp / 100, Color3.fromRGB(235, 80, 90), string.format("VIDA %d%%", m.Hp))
			local ef, et = bar(card, 31, m.En / 100, theme.ResourceColor, string.format("%s %d%%", theme.Resource, m.En))
			refs[name] = { HpFill = hf, HpText = ht, EnFill = ef, EnText = et }
		end
		-- acciones del líder sobre el miembro elegido
		if isSel then
			local act = Instance.new("Frame")
			act.LayoutOrder = i * 10 + 1
			act.Size = UDim2.fromOffset(190, 24)
			act.BackgroundTransparency = 1
			act.Parent = body
			local al = Instance.new("UIListLayout")
			al.FillDirection = Enum.FillDirection.Horizontal
			al.Padding = UDim.new(0, 4)
			al.Parent = act
			local promote = button(act, "★ Hacer líder", 1, 92)
			promote.TextColor3 = theme.Primary
			promote.Activated:Connect(function()
				remote:FireServer("Promote", name)
				selected = nil
				kickArmed = nil
				render()
			end)
			local armed = kickArmed == name
			local kick = button(act, if armed then "¿Seguro? ✕" else "✕ Expulsar", 2, 94)
			kick.BackgroundColor3 = if armed then Color3.fromRGB(170, 40, 50) else Color3.fromRGB(110, 32, 38)
			kick.BackgroundTransparency = 0.1
			kick.Activated:Connect(function()
				if kickArmed ~= name then
					kickArmed = name
					armToken += 1
					local tk = armToken
					render()
					task.delay(4, function() -- si no confirmas a tiempo, se desarma
						if armToken == tk and kickArmed == name then
							kickArmed = nil
							render()
						end
					end)
					return
				end
				remote:FireServer("Kick", name)
				selected = nil
				kickArmed = nil
				armToken += 1
				render()
			end)
		end
	end
	local row = Instance.new("Frame")
	row.LayoutOrder = 1000
	row.Size = UDim2.fromOffset(190, 24)
	row.BackgroundTransparency = 1
	row.Parent = body
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 4)
	rl.Parent = row
	local inv = button(row, "+ Invitar", 1, 92)
	inv.Activated:Connect(function()
		invitesOpen = not invitesOpen
		render()
	end)
	if #members > 0 then
		local lv = button(row, "Salir", 2, 60)
		lv.Activated:Connect(function()
			remote:FireServer("Leave")
		end)
	end
	if leader and #members > 1 then
		local hint = UITheme.Text(body, "Toca a un miembro para hacerlo líder o expulsarlo", 9, Color3.fromRGB(170, 170, 185), UDim2.new(), UDim2.fromOffset(190, 24))
		hint.LayoutOrder = 1001
		hint.TextWrapped = true
		hint.TextYAlignment = Enum.TextYAlignment.Top
	end
	if invitesOpen then
		-- jugadores conectados: los de tu facción se pueden invitar; los demás aparecen apagados (así ves a quién detecta)
		local mine = player:GetAttribute("Faction")
		local n = 0
		local others: { Player } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				table.insert(others, p)
			end
		end
		table.sort(others, function(a: Player, b: Player)
			local sa = a:GetAttribute("Faction") == mine
			local sb = b:GetAttribute("Faction") == mine
			if sa ~= sb then
				return sa
			end
			return a.Name < b.Name
		end)
		for _, p in ipairs(others) do
			n += 1
			local same = p:GetAttribute("Faction") == mine
			local inParty = false
			for _, m in ipairs(members) do
				if m.Name == p.Name then
					inParty = true
				end
			end
			local label = p.Name
			if inParty then
				label ..= "  (en grupo)"
			elseif not same then
				label ..= "  ·  otra facción"
			end
			local b = button(body, label, 2000 + n, 190)
			b.TextTruncate = Enum.TextTruncate.AtEnd
			if same and not inParty then
				b.TextColor3 = theme.Primary
				b.Activated:Connect(function()
					remote:FireServer("Invite", p.Name)
					invitesOpen = false
					render()
				end)
			else
				b.TextColor3 = Color3.fromRGB(130, 130, 145)
				b.AutoButtonColor = false
			end
		end
		if n == 0 then
			UITheme.Text(body, "No hay otros jugadores conectados", 10, Color3.fromRGB(190, 190, 205), UDim2.new(), UDim2.fromOffset(190, 18)).LayoutOrder = 2001
		end
	end
end

-- vida y energía en el sitio (sin destruir los botones)
local function updateBars()
	for _, m in ipairs(members) do
		local r = refs[tostring(m.Name)]
		if r then
			r.HpFill.Size = UDim2.fromScale(math.clamp(m.Hp / 100, 0, 1), 1)
			r.EnFill.Size = UDim2.fromScale(math.clamp(m.En / 100, 0, 1), 1)
			if r.HpText then
				r.HpText.Text = string.format("VIDA %d%%", m.Hp)
			end
			if r.EnText then
				r.EnText.Text = string.format("%s %d%%", theme.Resource, m.En)
			end
		end
	end
end

-- la lista de invitables se mantiene al día mientras está abierta (entran/salen jugadores, cambian de facción),
-- pero solo se reconstruye si realmente cambió algo
task.spawn(function()
	while gui.Parent do
		task.wait(2)
		if invitesOpen and expanded and signature() ~= lastSig then
			render()
		end
	end
end)

if MOBILE then
	local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
	MenuBus.Event:Connect(function(name: string)
		if name == "Party" then -- botón Grupo del celular = la tecla P
			expanded = true
			invitesOpen = not invitesOpen
			render()
		end
	end)
end
head.Activated:Connect(function()
	expanded = not expanded
	render()
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and KeyBinds.Matches(input, "Grupo") then
		expanded = true
		invitesOpen = not invitesOpen
		render()
	end
end)

-- ventana de invitación
local popup = UITheme.Frame(gui, theme, UDim2.fromOffset(260, 80), UDim2.new(0.5, 0, 0, 90), Vector2.new(0.5, 0))
popup.Visible = false
local popText = UITheme.Text(popup, "", 13, Color3.new(1, 1, 1), UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 32), Enum.TextXAlignment.Center)
popText.TextWrapped = true
local yes = button(popup, "Aceptar", 1, 110)
yes.Position = UDim2.fromOffset(14, 48)
local no = button(popup, "Rechazar", 2, 110)
no.Position = UDim2.fromOffset(136, 48)
local inviteToken = 0
yes.Activated:Connect(function()
	popup.Visible = false
	remote:FireServer("Accept")
end)
no.Activated:Connect(function()
	popup.Visible = false
	remote:FireServer("Decline")
end)

remote.OnClientEvent:Connect(function(kind: any, data: any)
	if kind == "State" and typeof(data) == "table" then
		members = data
		-- el elegido ya no está en el grupo, o dejaste de ser líder: se limpia la selección
		if selected then
			local still = false
			for _, m in ipairs(members) do
				if m.Name == selected then
					still = true
				end
			end
			if not still or not amLeader() then
				selected = nil
				kickArmed = nil
			end
		end
		if signature() ~= lastSig then
			render()
		else
			updateBars()
		end
	elseif kind == "Clear" then
		members = {}
		selected = nil
		kickArmed = nil
		render()
	elseif kind == "Invite" and typeof(data) == "string" then
		popText.Text = data .. " te invita a su grupo"
		popup.Visible = true
		inviteToken += 1
		local tk = inviteToken
		task.delay(30, function()
			if inviteToken == tk then
				popup.Visible = false
			end
		end)
	end
end)

render()
