--!strict
--[[
    PartyClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > PartyClient
    Panel de GRUPO (izquierda de la pantalla): vida y energía en % de cada miembro, botón "+" para invitar a jugadores de tu facción,
    "Salir", y la ventana de invitación (Aceptar / Rechazar). Se minimiza con ▲/▼. Atajo: P abre/cierra la lista de invitables.
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

local function bar(parent: Instance, y: number, frac: number, color: Color3, text: string)
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(6, y)
	back.Size = UDim2.new(1, -12, 0, 9)
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
	local t = UITheme.Text(back, text, 8, Color3.new(1, 1, 1), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
	t.ZIndex = 3
end

local function render()
	for _, c in ipairs(body:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	head.Text = (if #members > 0 then string.format("GRUPO (%d)", #members) else "GRUPO") .. (if expanded then "  ▲" else "  ▼")
	body.Visible = expanded
	if not expanded then
		return
	end
	for i, m in ipairs(members) do
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.Size = UDim2.fromOffset(190, 46)
		card.BackgroundColor3 = theme.Dark
		card.BackgroundTransparency = 0.2
		card.BorderSizePixel = 0
		card.Parent = body
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
		UITheme.Text(card, (if m.Leader then "★ " else "") .. m.Name, 11, Color3.new(1, 1, 1), UDim2.fromOffset(6, 2), UDim2.new(1, -12, 0, 14))
		bar(card, 18, m.Hp / 100, Color3.fromRGB(235, 80, 90), string.format("VIDA %d%%", m.Hp))
		bar(card, 31, m.En / 100, theme.ResourceColor, string.format("%s %d%%", theme.Resource, m.En))
	end
	local row = Instance.new("Frame")
	row.LayoutOrder = 100
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
			local b = button(body, label, 200 + n, 190)
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
			UITheme.Text(body, "No hay otros jugadores conectados", 10, Color3.fromRGB(190, 190, 205), UDim2.new(), UDim2.fromOffset(190, 18)).LayoutOrder = 201
		end
	end
end

-- la lista de invitables se mantiene al día mientras está abierta (entran/salen jugadores, cambian de facción)
task.spawn(function()
	while gui.Parent do
		task.wait(2)
		if invitesOpen and expanded then
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
		render()
	elseif kind == "Clear" then
		members = {}
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
