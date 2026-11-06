--!strict
--[[
    HouseClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HouseClient
    Ventana de la CASA VIP (HouseService la abre al usar el baúl o el tablón de invitados dentro de tu casa):
      Baúl        tu mochila (derecha) y el baúl privado (izquierda); clic en un objeto = lo pasa al otro lado.
      Invitados   jugadores del servidor: invitar / quitar invitación (los invitados solo pueden entrar y mirar).
      Suscripción beneficios de la Suscripción Imperial (mensual) y botón de compra.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local ItemIcon = require(script.Parent:WaitForChild("ItemIcon", 10))
local ItemCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemCatalog"))

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

local TABS = { { "Baul", "🧰 Baúl" }, { "Guests", "👥 Invitados" }, { "Sub", "👑 Suscripción" } }

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

local function build()
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
	for i, t in ipairs(TABS) do
		NpcKit.Tab(w, theme, t[2], UDim2.fromOffset(150, 28), UDim2.fromOffset(14 + (i - 1) * 156, 72), tab == t[1], function()
			tab = t[1]
			build()
		end)
	end
	local top = 108
	if not state then
		text(w, "Cargando…", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(300, 20))
		return
	end
	if not state.HasPass then
		text(w, "Necesitas el pase Pabellón Imperial para usar el baúl y los invitados (Tienda > Pases).", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 40)).TextWrapped = true
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
		if not state.Sub then
			text(w, "Con la Suscripción Imperial el baúl sube a 60 casillas.", 12, pal.FMuted, UDim2.fromOffset(18, 546), UDim2.fromOffset(500, 16))
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
			"• Baúl privado de 60 casillas (en vez de 30)",
			"• Se renueva sola cada mes; puedes cancelarla cuando quieras",
			"• Nada de lo que guardaste se borra si termina",
			"• Próximamente: misiones del Pabellón, tienda VIP del mes, títulos y decoración",
		}
		text(w, table.concat(perks, "\n"), 14, pal.Text, UDim2.fromOffset(18, top + 34), UDim2.fromOffset(740, 110)).TextYAlignment = Enum.TextYAlignment.Top
		if state.Sub then
			text(w, "✔ Suscripción activa. ¡Gracias por apoyar el juego!", 15, Color3.fromRGB(110, 210, 140), UDim2.fromOffset(18, top + 160), UDim2.fromOffset(600, 22))
		else
			NpcKit.Button(w, theme, "Suscribirme · " .. tostring(state.SubPrice), UDim2.fromOffset(300, 38), UDim2.fromOffset(18, top + 156), "buy", function()
				actionRemote:FireServer("BuySub")
			end)
		end
	end
end

if openRemote then
	openRemote.OnClientEvent:Connect(function(kind: any)
		tab = if kind == "Guests" then "Guests" else "Baul"
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
