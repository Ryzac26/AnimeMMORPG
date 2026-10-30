--!strict
--[[
    ClassSelectClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ClassSelectClient
    PANTALLA DE SELECCIÓN: paso 1 = elegir facción, paso 2 = elegir rol (personaje), confirmar -> el servidor te manda a tu ciudad.
    Solo aparece si el servidor marca ClassChosen = false (jugador nuevo). El cliente solo PIDE; el servidor valida.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local FactionClasses = require(Modules:WaitForChild("FactionClassesModule", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local chooseRemote = Remotes:WaitForChild("ChooseClass", 10) :: RemoteEvent

local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
local ROLE_HINT: { [string]: string } = {
	Tanque = "Aguanta el daño y protege al grupo",
	Guerrero = "Daño equilibrado cuerpo a cuerpo",
	Asesino = "Mucho daño, poca vida, muy veloz",
	Tirador = "Daño a larga distancia",
	Mago = "Daño en área",
	Curador = "Cura y apoya al equipo",
}
local ANIME: { [string]: string } = { Saiyan = "Dragon Ball", Shinobi = "Naruto", Pirate = "One Piece", Shinigami = "Bleach" }

local gui = Instance.new("ScreenGui")
gui.Name = "ClassSelectGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

local selectedFaction: string? = nil
local selectedRole: string? = nil
local root: Frame? = nil

local function clear()
	if root then
		root:Destroy()
	end
	local r = Instance.new("Frame")
	r.Size = UDim2.fromScale(1, 1)
	r.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
	r.BackgroundTransparency = 0.05
	r.BorderSizePixel = 0
	r.Active = true -- bloquea clics al mundo
	r.Parent = gui
	root = r
	return r
end

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.BackgroundColor3 = color
	b.Text = text
	b.Font = UITheme.Font
	b.TextSize = 20
	b.TextColor3 = Color3.new(1, 1, 1)
	b.AutoButtonColor = true
	b.Parent = parent
	Instance.new("UICorner", b)
	return b
end

local showFactions: () -> ()
local showRoles: () -> ()

local function waiting()
	local r = clear()
	UITheme.Text(r, "Viajando a tu ciudad...", 30, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.45), UDim2.fromScale(1, 0.1), Enum.TextXAlignment.Center)
end

showFactions = function()
	local r = clear()
	UITheme.Text(r, "ELIGE TU FACCIÓN", 40, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.06), UDim2.fromScale(1, 0.1), Enum.TextXAlignment.Center)
	UITheme.Text(r, "Defenderás a tu nación en las franjas PvE y en la Arena Central", 18, Color3.fromRGB(170, 170, 185), UDim2.fromScale(0, 0.15), UDim2.fromScale(1, 0.05), Enum.TextXAlignment.Center)
	for i, f in ipairs(FACTIONS) do
		local theme = UITheme.For(f)
		local card = Instance.new("TextButton")
		card.AnchorPoint = Vector2.new(0.5, 0)
		card.Position = UDim2.fromScale(0.14 + (i - 1) * 0.24, 0.25)
		card.Size = UDim2.fromScale(0.22, 0.55)
		card.BackgroundColor3 = theme.Dark
		card.Text = ""
		card.AutoButtonColor = true
		card.Parent = r
		Instance.new("UICorner", card)
		UITheme.Border(card, theme, 3)
		UITheme.Text(card, theme.Emblem, 90, theme.Primary, UDim2.fromScale(0, 0.06), UDim2.fromScale(1, 0.4), Enum.TextXAlignment.Center)
		UITheme.Text(card, string.upper(theme.Faction), 26, theme.Primary, UDim2.fromScale(0, 0.5), UDim2.fromScale(1, 0.1), Enum.TextXAlignment.Center)
		UITheme.Text(card, ANIME[f], 18, Color3.fromRGB(190, 190, 205), UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.08), Enum.TextXAlignment.Center)
		UITheme.Text(card, "Recurso: " .. theme.Resource, 16, theme.ResourceColor, UDim2.fromScale(0, 0.72), UDim2.fromScale(1, 0.08), Enum.TextXAlignment.Center)
		card.Activated:Connect(function()
			selectedFaction = f
			selectedRole = nil
			showRoles()
		end)
	end
end

showRoles = function()
	local faction = selectedFaction
	if not faction then
		return
	end
	local theme = UITheme.For(faction)
	local r = clear()
	UITheme.Text(r, string.upper(theme.Faction) .. " — ELIGE TU ROL", 34, theme.Primary, UDim2.fromScale(0, 0.04), UDim2.fromScale(1, 0.09), Enum.TextXAlignment.Center)

	local confirm: TextButton
	local cards: { [string]: TextButton } = {}
	local detail = UITheme.Text(r, "Elige un personaje para ver sus datos", 18, Color3.fromRGB(200, 200, 215), UDim2.fromScale(0.1, 0.72), UDim2.fromScale(0.8, 0.12), Enum.TextXAlignment.Center)
	detail.TextWrapped = true
	detail.RichText = true

	for i, role in ipairs(ROLES) do
		local class = FactionClasses.FindClass(faction, role)
		if class then
			local col = (i - 1) % 3
			local row = math.floor((i - 1) / 3)
			local card = Instance.new("TextButton")
			card.AnchorPoint = Vector2.new(0.5, 0)
			card.Position = UDim2.fromScale(0.2 + col * 0.3, 0.15 + row * 0.28)
			card.Size = UDim2.fromScale(0.26, 0.25)
			card.BackgroundColor3 = theme.Dark
			card.Text = ""
			card.AutoButtonColor = true
			card.Parent = r
			Instance.new("UICorner", card)
			local stroke = UITheme.Border(card, theme, 2)
			UITheme.Text(card, class.CharacterName, 28, theme.Primary, UDim2.fromScale(0, 0.08), UDim2.fromScale(1, 0.3), Enum.TextXAlignment.Center)
			UITheme.Text(card, string.upper(role), 18, Color3.new(1, 1, 1), UDim2.fromScale(0, 0.38), UDim2.fromScale(1, 0.2), Enum.TextXAlignment.Center)
			local hint = UITheme.Text(card, ROLE_HINT[role] or "", 14, Color3.fromRGB(170, 170, 185), UDim2.fromScale(0.05, 0.6), UDim2.fromScale(0.9, 0.34), Enum.TextXAlignment.Center)
			hint.TextWrapped = true
			cards[role] = card
			card.Activated:Connect(function()
				selectedRole = role
				for rn, c in pairs(cards) do
					c.BackgroundColor3 = if rn == role then theme.Secondary else theme.Dark
				end
				detail.Text = string.format(
					"<b>%s</b> (%s) — Vida %d · %s %d · Defensa %d · Velocidad %d\n%s: %s",
					class.CharacterName, class.AnimeSource, class.BaseHP, theme.Resource, class.BaseEnergy,
					class.BaseDefense, class.WalkSpeed, class.PrimarySkill.Name, class.PrimarySkill.Description
				)
				confirm.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
				confirm.Active = true
				stroke.Enabled = true
			end)
		end
	end

	local back = button(r, "← Volver", UDim2.fromScale(0.3, 0.88), UDim2.fromScale(0.18, 0.07), Color3.fromRGB(60, 60, 75))
	back.Activated:Connect(function()
		showFactions()
	end)
	confirm = button(r, "CONFIRMAR Y VIAJAR", UDim2.fromScale(0.65, 0.88), UDim2.fromScale(0.3, 0.07), Color3.fromRGB(70, 70, 80))
	confirm.Active = false
	confirm.Activated:Connect(function()
		local f, ro = selectedFaction, selectedRole
		if not f or not ro then
			return
		end
		chooseRemote:FireServer(f, ro)
		waiting()
	end)
end

local function refresh()
	local chosen = player:GetAttribute("ClassChosen")
	if chosen == false then
		if not gui.Enabled then
			gui.Enabled = true
			showFactions()
		end
	elseif chosen == true then
		if gui.Enabled then
			-- el servidor ya aceptó la elección: espera a que reaparezca en su ciudad y cierra
			task.delay(1.5, function()
				if player:GetAttribute("ClassChosen") == true then
					gui.Enabled = false
				end
			end)
		end
	end
end

player:GetAttributeChangedSignal("ClassChosen"):Connect(refresh)
refresh()
