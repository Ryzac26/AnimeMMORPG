--!strict
--[[
    HouseClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HouseClient
    Ventana de la CASA VIP (HouseService la abre al usar el baúl o el tablón de invitados dentro de tu casa):
      Baúl        tu mochila (derecha) y el baúl privado (izquierda); clic en un objeto = lo pasa al otro lado.
      Invitados   jugadores del servidor: invitar / quitar invitación (los invitados solo pueden entrar y mirar).
      Decorar     catálogo de muebles: se colocan con vista previa; cuadros y pantallas muestran tu imagen por ID.
      Suscripción beneficios de la Suscripción Imperial (mensual) y botón de compra.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local ItemCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemCatalog"))
local HouseFurniture = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("HouseFurniture"))

local openRemote = ClientNet.Get("HouseOpen")
local stateRemote = ClientNet.Get("HouseState")
local actionRemote = ClientNet.Get("HouseAction")

local gui = Instance.new("ScreenGui")
gui.Name = "HouseGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 13
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local state: any = nil
local tab = "Baul"
local hover: TextLabel? = nil

local TABS_HOME = { { "Baul", "🧰 Baúl" }, { "Animals", "🐾 Animales" }, { "Decor", "🛋 Decorar" }, { "Guests", "👥 Invitados" }, { "Sub", "👑 Suscripción" } }
local TABS_MAIL = { { "Mail", "📮 Buzón" } }
local mailMode = false -- true = abierta desde el buzón de la ciudad (solo esa pestaña)

local function text(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

local function slotGrid(parent: Instance, theme: any, pal: any, list: { any }, count: number, cols: number, pos: UDim2, onClick: (any) -> ())
	local CELL, GAP = 52, 5
	local bySlot: { [number]: any } = {}
	for _, e in ipairs(list) do
		bySlot[e.Slot] = e
	end
	local panel = NpcKit.Panel(parent, theme, UDim2.fromOffset(cols * (CELL + GAP) + GAP, math.ceil(count / cols) * (CELL + GAP) + GAP), pos, "inset")
	for i = 1, count do
		local x = GAP + ((i - 1) % cols) * (CELL + GAP)
		local y = GAP + math.floor((i - 1) / cols) * (CELL + GAP)
		local e = bySlot[i]
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, y)
		b.Size = UDim2.fromOffset(CELL, CELL)
		b.BackgroundColor3 = pal.Slot
		b.BorderSizePixel = 0
		b.Text = ""
		b.AutoButtonColor = e ~= nil
		b.ZIndex = 5
		b.Parent = panel
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		local st = Instance.new("UIStroke")
		st.Color = pal.Edge2
		st.Parent = b
		if e then
			local item: any = (ItemCatalog.Items :: any)[e.Id]
			if item then
				local col = ItemCatalog.RarityColor[item.Rarity] or Color3.new(1, 1, 1)
				st.Color = col
				ItemIcon.Build(b, item, 40, col)
				if e.Count > 1 then
					local c = UITheme.Text(b, "x" .. e.Count, 11, Color3.new(1, 1, 1), UDim2.fromOffset(2, CELL - 16), UDim2.fromOffset(CELL - 6, 14), Enum.TextXAlignment.Right)
					c.ZIndex = 8
				end
				if e.Plus and e.Plus > 0 and not item.Pet then
					local c = UITheme.Text(b, "+" .. e.Plus, 11, Color3.fromRGB(255, 220, 90), UDim2.fromOffset(4, 2), UDim2.fromOffset(30, 14))
					c.ZIndex = 8
				end
				b.MouseEnter:Connect(function()
					if hover then
						hover.Text = string.format("%s%s", item.Name, if e.Plus and e.Plus > 0 and not item.Pet then " +" .. e.Plus else "")
					end
				end)
			end
			b.Activated:Connect(function()
				onClick(e)
			end)
		end
	end
end

---------------------------------------------------------------------
-- MODO COLOCAR: vista previa del mueble que sigue al cursor / toque
---------------------------------------------------------------------
local draftImg: { [number]: string } = {}
type Placing = { Type: string, Idx: number?, Rot: number, X: number, Z: number, Ghost: Model?, Conns: { RBXScriptConnection }, Gui: ScreenGui, Hl: Highlight }
local placing: Placing? = nil
local build: () -> ()

local function stopPlace()
	local pl = placing
	if not pl then
		return
	end
	placing = nil
	for _, c in ipairs(pl.Conns) do
		c:Disconnect()
	end
	if pl.Ghost then
		pl.Ghost:Destroy()
	end
	pl.Gui:Destroy()
	tab = "Decor"
	build()
	gui.Enabled = true
end

local function refreshGhost()
	local pl = placing
	if not pl or not state or not state.Origin then
		return
	end
	local origin: Vector3 = state.Origin
	if pl.Ghost then
		pl.Ghost:PivotTo(CFrame.new(origin + Vector3.new(pl.X, HouseFurniture.FloorY, pl.Z)) * CFrame.Angles(0, math.rad(pl.Rot), 0))
	end
	pl.Hl.FillColor = if HouseFurniture.Valid(pl.X, pl.Z) then Color3.fromRGB(90, 230, 120) else Color3.fromRGB(235, 80, 80)
end

local function confirmPlace()
	local pl = placing
	if not pl or not HouseFurniture.Valid(pl.X, pl.Z) then
		return
	end
	actionRemote:FireServer("Place", { T = pl.Type, X = pl.X, Z = pl.Z, R = pl.Rot, Idx = pl.Idx })
	if pl.Idx then
		stopPlace()
	end
end

local function startPlace(typeId: string, idx: number?, rot: number?)
	if placing or not state or not state.Origin then
		return
	end
	local origin: Vector3 = state.Origin
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local px, pz = 0, -20
	if root and root:IsA("BasePart") then
		px, pz = root.Position.X - origin.X, root.Position.Z - origin.Z
		pz += 10
		if pz > 6 and pz < 18 then
			pz = -20
		end
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "HousePlaceGui"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 14
	sg.Parent = player:WaitForChild("PlayerGui")
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local bar = NpcKit.Panel(sg, theme, UDim2.fromOffset(520, 96), UDim2.new(0.5, -260, 1, -190), "inset")
	local def = HouseFurniture.ById[typeId]
	text(bar, (if def then def.Icon .. " " .. def.Name else typeId) .. " — toca o haz clic donde quieres ponerlo", 14, pal.Text, UDim2.fromOffset(12, 6), UDim2.fromOffset(496, 20))
	text(bar, "R girar · Enter colocar · X cancelar · verde = se puede, rojo = no", 12, pal.FMuted, UDim2.fromOffset(12, 26), UDim2.fromOffset(496, 16))
	local ghost = HouseFurniture.Build(typeId, Workspace, CFrame.new(origin), { Ghost = true })
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.5
	hl.OutlineTransparency = 0.2
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = ghost
	local pl: Placing = { Type = typeId, Idx = idx, Rot = rot or 0, X = math.floor(px), Z = math.floor(pz), Ghost = ghost, Conns = {}, Gui = sg, Hl = hl }
	placing = pl
	NpcKit.Button(bar, theme, "✔ Colocar", UDim2.fromOffset(150, 34), UDim2.fromOffset(12, 50), "buy", confirmPlace)
	NpcKit.Button(bar, theme, "↻ Girar", UDim2.fromOffset(150, 34), UDim2.fromOffset(184, 50), "buy", function()
		pl.Rot = (pl.Rot + 45) % 360
		refreshGhost()
	end)
	NpcKit.Button(bar, theme, "✖ Terminar", UDim2.fromOffset(150, 34), UDim2.fromOffset(356, 50), "danger", stopPlace)
	gui.Enabled = false

	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local function updateFrom(sx: number, sy: number)
		local cam = Workspace.CurrentCamera
		if not cam or not state or not state.Origin then
			return
		end
		rp.FilterDescendantsInstances = { player.Character :: Instance, ghost :: Instance }
		local ray = cam:ScreenPointToRay(sx, sy)
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * 400, rp)
		if hit then
			local o: Vector3 = state.Origin
			pl.X = math.floor(hit.Position.X - o.X + 0.5)
			pl.Z = math.floor(hit.Position.Z - o.Z + 0.5)
			refreshGhost()
		end
	end
	table.insert(pl.Conns, UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			updateFrom(input.Position.X, input.Position.Y)
		elseif input.KeyCode == Enum.KeyCode.R then
			pl.Rot = (pl.Rot + 45) % 360
			refreshGhost()
		elseif input.KeyCode == Enum.KeyCode.Return then
			confirmPlace()
		elseif input.KeyCode == Enum.KeyCode.X then
			stopPlace()
		end
	end))
	table.insert(pl.Conns, UserInputService.InputChanged:Connect(function(input: InputObject, gp: boolean)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			updateFrom(input.Position.X, input.Position.Y)
		end
	end))
	-- si sales de la casa (o te sacan) se cancela
	table.insert(pl.Conns, player:GetAttributeChangedSignal("InHouse"):Connect(function()
		if player:GetAttribute("InHouse") ~= true then
			stopPlace()
		end
	end))
	refreshGhost()
end

build = function()
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	if win then
		win:Destroy()
	end
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(780, 600), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Casa VIP", "Pabellón Imperial · solo tú puedes tocar lo que hay aquí", "🏠", function()
		gui.Enabled = false
	end)
	win = w
	WindowDrag.Attach(w, "House", 40, 50)
	for i, t in ipairs(if mailMode then TABS_MAIL else TABS_HOME) do
		NpcKit.Tab(w, theme, t[2], UDim2.fromOffset(144, 28), UDim2.fromOffset(14 + (i - 1) * 150, 72), tab == t[1], function()
			tab = t[1]
			build()
		end)
	end
	local top = 108
	if not state then
		text(w, "Cargando…", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(300, 20))
		return
	end
	if tab == "Mail" then
		text(w, "BUZÓN DE LA CIUDAD: lo que no cupo en tu baúl está a salvo aquí hasta que lo recojas.", 13, pal.FMuted, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 18))
		local count = #state.Mail
		if count == 0 then
			text(w, "No tienes nada en el buzón.", 14, pal.FText, UDim2.fromOffset(18, top + 36), UDim2.fromOffset(500, 20))
		else
			slotGrid(w, theme, pal, state.Mail, math.max(count, 24), 12, UDim2.fromOffset(14, top + 28), function(e: any)
				actionRemote:FireServer("MailClaim", e.Slot)
			end)
			NpcKit.Button(w, theme, "Recoger todo", UDim2.fromOffset(200, 34), UDim2.fromOffset(14, 540), "buy", function()
				actionRemote:FireServer("MailClaim", "all")
			end)
			hover = text(w, "Clic en un objeto para pasarlo a tu mochila.", 13, pal.FMuted, UDim2.fromOffset(230, 548), UDim2.fromOffset(500, 20))
		end
		return
	end
	if not state.HasPass then
		if state.Lapsed then
			text(w, "Tu Casa VIP venció porque la suscripción no se renovó. Tu baúl está a salvo en el buzón de la ciudad. Para volver a tener la casa hay que pagar de nuevo el Pabellón Imperial (si todavía quedan casas).", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 60)).TextWrapped = true
			NpcKit.Button(w, theme, "Recomprar Pabellón Imperial · 599 R$", UDim2.fromOffset(360, 38), UDim2.fromOffset(18, top + 80), "buy", function()
				actionRemote:FireServer("Rebuy")
			end)
		else
			text(w, "Necesitas el pase Pabellón Imperial para usar el baúl y los invitados (Tienda > Pases).", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 40)).TextWrapped = true
		end
		return
	end
	if tab == "Baul" then
		text(w, string.format("BAÚL PRIVADO  %d / %d", #state.Vault, state.Cap), 13, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(300, 18))
		text(w, "TU MOCHILA", 13, pal.FText, UDim2.fromOffset(402, top), UDim2.fromOffset(300, 18))
		slotGrid(w, theme, pal, state.Vault, state.Cap, 6, UDim2.fromOffset(14, top + 24), function(e: any)
			actionRemote:FireServer("Withdraw", e.Slot)
		end)
		local cap = 0
		for _, e in ipairs(state.Bag) do
			cap = math.max(cap, e.Slot)
		end
		slotGrid(w, theme, pal, state.Bag, math.max(cap, 30), 6, UDim2.fromOffset(398, top + 24), function(e: any)
			actionRemote:FireServer("Deposit", e.Slot)
		end)
		hover = text(w, "Clic en un objeto para pasarlo al otro lado.", 13, pal.FMuted, UDim2.fromOffset(18, 566), UDim2.fromOffset(740, 20))
	elseif tab == "Animals" then
		text(w, "Elige qué animales quedan sueltos en el jardín. Sus bonus siguen activos. Cada uno queda como lo soltaste: puedes soltar varios y cambiar de montura. Agárralos aquí o con F en el portal de la ciudad.", 12, pal.FMuted, UDim2.fromOffset(18, top), UDim2.fromOffset(748, 34)).TextWrapped = true
		if #state.Animals == 0 then
			text(w, "No tienes mascotas ni montura equipadas.", 14, pal.FText, UDim2.fromOffset(18, top + 44), UDim2.fromOffset(500, 20))
		end
		for i, a in ipairs(state.Animals) do
			local y = top + 44 + (i - 1) * 44
			local row = NpcKit.Panel(w, theme, UDim2.fromOffset(748, 38), UDim2.fromOffset(14, y), "inset")
			text(row, (if string.sub(a.Key, 1, 6) == "Mount:" then "🐎  " else "🐾  ") .. tostring(a.Name) .. (if a.Released then "   (suelto en el jardín)" else ""), 14, pal.Text, UDim2.fromOffset(12, 9), UDim2.fromOffset(500, 20))
			NpcKit.Button(row, theme, if a.Released then "Agarrar" else "Soltar", UDim2.fromOffset(170, 28), UDim2.fromOffset(570, 5), if a.Released then "danger" else "buy", function()
				actionRemote:FireServer("Release", a.Key, not a.Released)
			end)
		end
	elseif tab == "Decor" then
		local inHome = state.Origin ~= nil
		text(w, if inHome then "Elige un mueble y colócalo donde quieras. Cuadros y pantallas: pega el ID de tu imagen y se genera al instante." else "Entra a tu casa para decorar (usa la mesa de diseño del salón).", 12, pal.FMuted, UDim2.fromOffset(18, top), UDim2.fromOffset(748, 30)).TextWrapped = true
		text(w, "Paredes:", 13, pal.Text, UDim2.fromOffset(18, top + 38), UDim2.fromOffset(70, 20))
		for i, wc in ipairs(HouseFurniture.WallColors) do
			local sw = Instance.new("TextButton")
			sw.Position = UDim2.fromOffset(92 + (i - 1) * 54, top + 33)
			sw.Size = UDim2.fromOffset(48, 28)
			sw.BackgroundColor3 = wc.Color
			sw.BorderSizePixel = 0
			sw.Text = ""
			sw.ZIndex = 5
			sw.Parent = w
			Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 6)
			local st = Instance.new("UIStroke")
			st.Color = if state.WallColor == i then Color3.fromRGB(255, 255, 255) else pal.Edge2
			st.Thickness = if state.WallColor == i then 3 else 1
			st.Parent = sw
			sw.Activated:Connect(function()
				if inHome then
					actionRemote:FireServer("WallColor", i)
				end
			end)
		end
		for i, d in ipairs(HouseFurniture.Catalog) do
			local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
			NpcKit.Button(w, theme, d.Icon .. " " .. d.Name, UDim2.fromOffset(180, 32), UDim2.fromOffset(18 + col * 186, top + 68 + row * 36), "buy", function()
				if inHome then
					startPlace(d.Id)
				end
			end)
		end
		local listTop = top + 68 + math.ceil(#HouseFurniture.Catalog / 4) * 36 + 4
		text(w, string.format("Colocados: %d / %d", #state.Decor, state.DecorMax), 14, pal.Text, UDim2.fromOffset(18, listTop), UDim2.fromOffset(300, 20))
		local sc = Instance.new("ScrollingFrame")
		sc.BackgroundTransparency = 1
		sc.BorderSizePixel = 0
		sc.Position = UDim2.fromOffset(14, listTop + 24)
		sc.Size = UDim2.fromOffset(752, 596 - (listTop + 24))
		sc.CanvasSize = UDim2.fromOffset(0, #state.Decor * 40)
		sc.ScrollBarThickness = 6
		sc.ZIndex = 3
		sc.Parent = w
		for i, it in ipairs(state.Decor) do
			local def = HouseFurniture.ById[it.T]
			local row = NpcKit.Panel(sc, theme, UDim2.fromOffset(734, 36), UDim2.fromOffset(0, (i - 1) * 40), "inset")
			text(row, (if def then def.Icon .. " " .. def.Name else it.T), 13, pal.Text, UDim2.fromOffset(10, 8), UDim2.fromOffset(170, 20))
			if def and def.Image then
				local box = Instance.new("TextBox")
				box.Position = UDim2.fromOffset(184, 5)
				box.Size = UDim2.fromOffset(192, 26)
				box.BackgroundColor3 = pal.Slot
				box.BorderSizePixel = 0
				box.PlaceholderText = "Pega el ID de tu imagen"
				box.Text = draftImg[it.Idx] or it.I or ""
				box.TextColor3 = Color3.new(1, 1, 1)
				box.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
				box.TextSize = 12
				box.Font = Enum.Font.Gotham
				box.ClearTextOnFocus = false
				box.ZIndex = 6
				box.Parent = row
				Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
				box:GetPropertyChangedSignal("Text"):Connect(function()
					draftImg[it.Idx] = box.Text
				end)
				NpcKit.Button(row, theme, "Aplicar", UDim2.fromOffset(86, 26), UDim2.fromOffset(382, 5), "buy", function()
					actionRemote:FireServer("SetImage", it.Idx, box.Text)
				end)
			end
			NpcKit.Button(row, theme, "Ver", UDim2.fromOffset(60, 26), UDim2.fromOffset(478, 5), "buy", function()
				-- resalta el mueble en la casa unos segundos
				local house = Workspace:FindFirstChild("CasaVIP_" .. player.UserId)
				local folder = house and house:FindFirstChild("Placed")
				local mdl = folder and folder:GetChildren()[it.Idx]
				if mdl then
					local hl = Instance.new("Highlight")
					hl.FillColor = Color3.fromRGB(255, 220, 90)
					hl.OutlineColor = Color3.new(1, 1, 1)
					hl.FillTransparency = 0.35
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = mdl
					task.delay(2.5, function()
						hl:Destroy()
					end)
				end
			end)
			NpcKit.Button(row, theme, "Mover", UDim2.fromOffset(88, 26), UDim2.fromOffset(544, 5), "buy", function()
				if inHome then
					startPlace(it.T, it.Idx)
				end
			end)
			NpcKit.Button(row, theme, "Quitar", UDim2.fromOffset(88, 26), UDim2.fromOffset(638, 5), "danger", function()
				draftImg[it.Idx] = nil
				actionRemote:FireServer("RemoveDecor", it.Idx)
			end)
		end
	elseif tab == "Guests" then
		text(w, string.format("Invitados: pueden entrar a tu casa, mirar y salir. No pueden abrir ni tocar nada. (máx. %d)", state.MaxGuests), 12, pal.FMuted, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 18))
		if #state.People == 0 then
			text(w, "No hay otros jugadores en este servidor.", 14, pal.FText, UDim2.fromOffset(18, top + 36), UDim2.fromOffset(500, 20))
		end
		for i, p in ipairs(state.People) do
			if i > 12 then
				break
			end
			local y = top + 28 + (i - 1) * 36
			local row = NpcKit.Panel(w, theme, UDim2.fromOffset(748, 32), UDim2.fromOffset(14, y), "inset")
			text(row, tostring(p.Name) .. (if p.Inside then "   (dentro)" else ""), 14, pal.Text, UDim2.fromOffset(12, 6), UDim2.fromOffset(460, 20))
			NpcKit.Button(row, theme, if p.Invited then "Quitar invitación" else "Invitar", UDim2.fromOffset(170, 26), UDim2.fromOffset(570, 3), if p.Invited then "danger" else "buy", function()
				actionRemote:FireServer(if p.Invited then "Uninvite" else "Invite", p.UserId)
			end)
		end
	else
		text(w, "SUSCRIPCIÓN IMPERIAL", 16, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(500, 22))
		local perks = {
			"• El primer mes (30 días) va incluido en el pago de 599 R$. Después, esta suscripción es el costo mensual para seguir usando tu casa",
			"• Se renueva sola cada mes; puedes cancelarla cuando quieras",
			"• Si no se renueva, la casa vence: tu baúl pasa al buzón de la ciudad (no se borra nada)",
			"• Para volver a tener la casa hay que pagar de nuevo el Pabellón (599 R$), si aún quedan casas",
		}
		text(w, table.concat(perks, "\n"), 14, pal.Text, UDim2.fromOffset(18, top + 34), UDim2.fromOffset(740, 110)).TextYAlignment = Enum.TextYAlignment.Top
		if state.Sub then
			text(w, "✔ Suscripción activa. ¡Gracias por apoyar el juego!", 15, Color3.fromRGB(110, 210, 140), UDim2.fromOffset(18, top + 160), UDim2.fromOffset(600, 22))
		else
			if state.TimeLeft then
				local days = math.ceil(state.TimeLeft / 86400)
				if state.TimeLeft > 0 then
					text(w, string.format("Mes incluido en tu compra: te quedan %d días. Suscríbete antes para no perder la casa.", days), 14, Color3.fromRGB(240, 190, 70), UDim2.fromOffset(18, top + 124), UDim2.fromOffset(740, 22))
				else
					text(w, string.format("⚠ Tu mes terminó: la casa vence en %d h si no te suscribes.", math.max(0, math.ceil((state.TimeLeft + state.Grace) / 3600))), 14, Color3.fromRGB(235, 140, 90), UDim2.fromOffset(18, top + 124), UDim2.fromOffset(740, 22))
				end
			end
			NpcKit.Button(w, theme, "Suscribirme · " .. tostring(state.SubPrice), UDim2.fromOffset(300, 38), UDim2.fromOffset(18, top + 156), "buy", function()
				actionRemote:FireServer("BuySub")
			end)
		end
	end
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(kind: any)
		mailMode = kind == "Mail"
		tab = if kind == "Guests" then "Guests" elseif kind == "Animals" then "Animals" elseif kind == "Decor" then "Decor" elseif kind == "Mail" then "Mail" else "Baul"
		build()
		gui.Enabled = true
	end)
end
if stateRemote then
	stateRemote.OnClientEvent:Connect(function(s: any)
		if typeof(s) == "table" then
			state = s
			if gui.Enabled then
				build()
			end
		end
	end)
end
if actionRemote then
	actionRemote:FireServer("State")
end
print("[HouseClient] listo")
