--!nonstrict
--[[
    MountClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MountClient
    TODO lo de monturas en el cliente:
      1) INCUBADORA (se abre al interactuar con la cúpula de la ciudad): tus huevos, probabilidades, garantías, huevo del día,
         iniciar incubación, ACELERAR (Robux) y abrir el huevo. La pantalla de ECLOSIÓN revela especie y rareza.
      2) MIS MONTURAS (botón "Monturas" del menú): colección 12 especies x 5 rarezas, equipar y montar/bajar.
      3) MONTAR con la tecla "Montura" (por defecto H, se cambia en Ajustes > Atajos) (o el botón de la ventana). Todos ven la montura de los jugadores cercanos (se dibuja aquí con piezas, ver MountModels).
         El personaje va SENTADO sobre la montura (el servidor ajusta su altura y MountClient dobla piernas y pone los brazos en las riendas); se puede atacar montado. Las flotantes solo flotan.
    Atributos que lee: Mounted / MountEquipped (jugador), Mounted / MountKey (personaje). Datos: remote MountState.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local MountCatalog = require(Modules:WaitForChild("MountCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local MountModels = require(script.Parent:WaitForChild("MountModels", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))

local stateRemote = ClientNet.Get("MountState")
local actionRemote = ClientNet.Get("MountAction")
local hatchRemote = ClientNet.Get("MountHatch")
local openRemote = ClientNet.Get("MountOpen")

local state = nil -- último MountState
local clockOffset = 0 -- reloj del servidor - reloj local

local function serverNow(): number
	return os.time() + clockOffset
end

local function fmtTime(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

---------------------------------------------------------------------
-- Vista previa 3D (ViewportFrame)
---------------------------------------------------------------------
local function preview(parent, size, pos, species, rarity)
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.Position = pos
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 250, 240)
	vp.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.Parent = vp
	vp.CurrentCamera = cam
	local rig = MountModels.Build(species, rarity)
	rig.Model.Parent = vp
	local hover = if rig.Float then MountModels.FloatHover else 0
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not vp.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock() - t0
		MountModels.Animate(rig, CFrame.new(0, hover + math.sin(t * 2) * 0.12 * (if rig.Float then 1 else 0), 0) * CFrame.Angles(0, t * 0.6, 0), t, 3)
		cam.CFrame = CFrame.lookAt(Vector3.new(0, rig.Top + 2.2, -11), Vector3.new(0, rig.Top * 0.55 + hover, 0))
	end)
	return vp
end

---------------------------------------------------------------------
-- Ventanas
---------------------------------------------------------------------
local function newGui(name: string, order: number)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.Enabled = false
	g.DisplayOrder = order
	g.IgnoreGuiInset = true
	g.Parent = player:WaitForChild("PlayerGui", 10)
	return g
end

local incGui = newGui("MountIncubatorGui", 12)
local colGui = newGui("MountCollectionGui", 12)
local hatchGui = newGui("MountHatchGui", 30)

local function text(parent, str, size, color, pos, dim, align)
	local l = UITheme.Text(parent, str, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

-- Las pestañas de NpcKit tienen ZIndex 10: lo que se les pone dentro debe quedar por encima
local function lift(root)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 12
		end
	end
end

local function disable(btn: TextButton, off: boolean)
	btn.Active = not off
	btn.AutoButtonColor = not off
	btn.BackgroundTransparency = if off then 0.55 else 0
	btn.TextTransparency = if off then 0.5 else 0
end

local function rarityChip(parent, rarity, pos, size)
	return NpcKit.Chip(parent, string.upper(MountCatalog.RarityName[rarity]), MountCatalog.RarityColor[rarity], pos, size)
end

-- ============ INCUBADORA ============
local incWin = nil
local incSel = 1
local timerLabel, timerBar, timerOpenBtn = nil, nil, nil

local function oddsRows(parent, theme, tier, x, y, w)
	local pal = NpcKit.Palette(theme)
	local egg = MountCatalog.Eggs[tier]
	for i, rar in ipairs(MountCatalog.Rarities) do
		local pct = egg.Odds[i]
		local col = MountCatalog.RarityColor[rar]
		text(parent, MountCatalog.RarityName[rar], 14, col, UDim2.fromOffset(x, y), UDim2.fromOffset(96, 18))
		local bg = Instance.new("Frame")
		bg.Position = UDim2.fromOffset(x + 100, y + 4)
		bg.Size = UDim2.fromOffset(w - 170, 10)
		bg.BackgroundColor3 = pal.Slot
		bg.BorderSizePixel = 0
		bg.Parent = parent
		Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 5)
		if pct > 0 then
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(math.max(pct, 2) / 100, 1)
			fill.BackgroundColor3 = col
			fill.BorderSizePixel = 0
			fill.Parent = bg
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 5)
		end
		local pt = text(parent, if pct > 0 then (string.format("%g%%", pct)) else "—", 14, pal.Text, UDim2.fromOffset(x + w - 66, y), UDim2.fromOffset(66, 18), Enum.TextXAlignment.Right)
		pt.Font = UITheme.Font
		y += 22
	end
	return y
end

local function updateTimers()
	if not incWin or not state then
		return
	end
	local inc = state.Incub
	if timerLabel then
		if not inc then
			timerLabel.Text = "Libre"
			if timerBar then
				timerBar.Size = UDim2.fromScale(0, 1)
			end
		else
			local left = inc.EndsAt - serverNow()
			local total = MountCatalog.IncubationSeconds(inc.Tier)
			if left <= 0 then
				timerLabel.Text = "¡Lista para abrir!"
				if timerBar then
					timerBar.Size = UDim2.fromScale(1, 1)
				end
			else
				timerLabel.Text = "Faltan " .. fmtTime(left)
				if timerBar then
					timerBar.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
				end
			end
			if timerOpenBtn then
				disable(timerOpenBtn, left > 0)
			end
		end
	end
end

local function buildIncubator()
	if incWin then
		incWin:Destroy()
		incWin = nil
	end
	timerLabel, timerBar, timerOpenBtn = nil, nil, nil
	if not state then
		return
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W, H = 760, 540
	local w = NpcKit.Window(incGui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Incubadora", "Un huevo al día: del nido, de un mini jefe o de la Tienda", "🥚", function()
		incGui.Enabled = false
	end)
	incWin = w
	WindowDrag.Attach(w, "MountIncubator", 40, 50)

	-- izquierda: huevos
	local left = NpcKit.Panel(w, theme, UDim2.fromOffset(250, H - NpcKit.TOP - 14), UDim2.fromOffset(14, NpcKit.TOP), "card")
	text(left, "HUEVOS EN LA MOCHILA", 13, pal.FText, UDim2.fromOffset(12, 8), UDim2.fromOffset(226, 18))
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(8, 30)
	list.Size = UDim2.new(1, -16, 1, -128)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = left
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 6)
	ll.Parent = list
	local eggs = state.Eggs
	if #eggs == 0 then
		local e = text(list, "No tienes huevos.\nBusca un nido en las franjas o derrota a un mini jefe.", 13, pal.Muted, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 60))
		e.TextWrapped = true
		e.TextYAlignment = Enum.TextYAlignment.Top
	end
	incSel = math.clamp(incSel, 1, math.max(1, #eggs))
	for i, e in ipairs(eggs) do
		local def = MountCatalog.Eggs[e.Tier]
		local on = i == incSel
		local row = NpcKit.Tab(list, theme, "", UDim2.new(1, -4, 0, 52), UDim2.new(), on, function()
			incSel = i
			buildIncubator()
		end)
		row.LayoutOrder = i
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(26, 32)
		dot.Position = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = MountCatalog.RarityColor[def.Rarity]
		dot.BorderSizePixel = 0
		dot.Parent = row
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		local n = text(row, def.Name, 15, if on then pal.TabOnText else pal.TabOffText, UDim2.fromOffset(46, 7), UDim2.new(1, -52, 0, 20), Enum.TextXAlignment.Left)
		n.Font = UITheme.Font
		text(row, string.format("Franja %d · %d h de incubación", e.Tier, def.Hours), 11, if on then pal.TabOnText else pal.Muted, UDim2.fromOffset(46, 28), UDim2.new(1, -52, 0, 16), Enum.TextXAlignment.Left)
		lift(row)
	end
	-- huevo del día
	local daily = NpcKit.Panel(left, theme, UDim2.new(1, -16, 0, 86), UDim2.new(0, 8, 1, -94), "inset")
	text(daily, "HUEVO DEL DÍA", 12, pal.FText, UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 16))
	local dtxt
	if state.Claimed then
		dtxt = "Ya tomaste el de hoy.\nNuevo huevo en " .. fmtTime(state.ResetAt - serverNow())
	else
		dtxt = "¡Disponible! Tómalo de un nido o derrota a un mini jefe."
	end
	local dl = text(daily, dtxt, 13, pal.Text, UDim2.fromOffset(10, 24), UDim2.new(1, -20, 0, 56))
	dl.TextWrapped = true
	dl.TextYAlignment = Enum.TextYAlignment.Top

	-- derecha: detalle y estado
	local rx = 278
	local right = NpcKit.Panel(w, theme, UDim2.fromOffset(W - rx - 14, H - NpcKit.TOP - 14), UDim2.fromOffset(rx, NpcKit.TOP), "card")
	local rw = W - rx - 14
	local egg = eggs[incSel]
	if egg then
		local def = MountCatalog.Eggs[egg.Tier]
		local col = MountCatalog.RarityColor[def.Rarity]
		local nm = text(right, def.Name .. " · Franja " .. egg.Tier, 22, col, UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 28))
		nm.Font = UITheme.Font
		text(right, string.format("Incubación: %d horas (corre aunque estés desconectado)", def.Hours), 13, pal.Text, UDim2.fromOffset(16, 40), UDim2.new(1, -32, 0, 18))
		text(right, "Dentro hay una montura de esa franja o de tu facción.", 12, pal.Muted, UDim2.fromOffset(16, 58), UDim2.new(1, -32, 0, 16))
		text(right, "PROBABILIDADES", 12, pal.FText, UDim2.fromOffset(16, 84), UDim2.new(1, -32, 0, 16))
		local y = oddsRows(right, theme, egg.Tier, 16, 104, rw - 32)
		local P = MountCatalog.Pity
		local pl = text(right, string.format("Garantía: Raro en %d · Épico en %d · Legendario en %d huevos", P.Raro - state.Pity.Raro, P.Epico - state.Pity.Epico, P.Legendario - state.Pity.Legendario), 12, pal.Muted, UDim2.fromOffset(16, y + 2), UDim2.new(1, -32, 0, 18))
		pl.TextWrapped = true
	else
		local t = text(right, "Selecciona un huevo de tu mochila para ver sus probabilidades.", 14, pal.Muted, UDim2.fromOffset(16, 16), UDim2.new(1, -32, 0, 40))
		t.TextWrapped = true
		t.TextYAlignment = Enum.TextYAlignment.Top
		local P = MountCatalog.Pity
		text(right, string.format("Garantía: Raro en %d · Épico en %d · Legendario en %d huevos", P.Raro - state.Pity.Raro, P.Epico - state.Pity.Epico, P.Legendario - state.Pity.Legendario), 12, pal.Muted, UDim2.fromOffset(16, 70), UDim2.new(1, -32, 0, 18))
	end

	-- estado de la incubadora
	local box = NpcKit.Panel(right, theme, UDim2.new(1, -24, 0, 150), UDim2.new(0, 12, 1, -162), "inset")
	text(box, "ESTADO DE LA INCUBADORA", 12, pal.FText, UDim2.fromOffset(12, 8), UDim2.new(1, -150, 0, 16))
	timerLabel = text(box, "Libre", 15, pal.Text, UDim2.new(1, -170, 0, 8), UDim2.fromOffset(158, 18), Enum.TextXAlignment.Right)
	timerLabel.Font = UITheme.Font
	local barBg = Instance.new("Frame")
	barBg.Position = UDim2.fromOffset(12, 34)
	barBg.Size = UDim2.new(1, -24, 0, 12)
	barBg.BackgroundColor3 = pal.Slot
	barBg.BorderSizePixel = 0
	barBg.Parent = box
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 6)
	timerBar = Instance.new("Frame")
	timerBar.Size = UDim2.fromScale(0, 1)
	timerBar.BackgroundColor3 = pal.Accent
	timerBar.BorderSizePixel = 0
	timerBar.Parent = barBg
	Instance.new("UICorner", timerBar).CornerRadius = UDim.new(0, 6)

	local inc = state.Incub
	local busy = inc ~= nil
	local ready = busy and inc.EndsAt <= serverNow()
	local bw = math.floor((rw - 24 - 24 - 12) / 2)
	local startBtn = NpcKit.Button(box, theme, if busy then "INCUBANDO…" else "INICIAR INCUBACIÓN", UDim2.fromOffset(bw, 38), UDim2.fromOffset(12, 56), "action", function()
		if not busy and eggs[incSel] then
			actionRemote:FireServer("Start", incSel)
		end
	end)
	disable(startBtn, busy or not eggs[incSel])
	local price = MountCatalog.Accelerate.PriceText
	local accBtn = NpcKit.Button(box, theme, "ACELERAR · " .. price, UDim2.fromOffset(bw, 38), UDim2.new(1, -12 - bw, 0, 56), "buy", function()
		if busy and not ready then
			actionRemote:FireServer("Accelerate")
		end
	end)
	disable(accBtn, not busy or ready)
	timerOpenBtn = NpcKit.Button(box, theme, "ABRIR HUEVO", UDim2.new(1, -24, 0, 38), UDim2.fromOffset(12, 100), "sell", function()
		if busy then
			actionRemote:FireServer("Open")
		end
	end)
	disable(timerOpenBtn, not ready)
	updateTimers()
end

-- ============ COLECCIÓN ============
local colWin = nil
local colTab = "Todas"
local selSpecies = nil
local selRarity = nil

local function bestOwned(spId: string): string?
	for i = #MountCatalog.Rarities, 1, -1 do
		local r = MountCatalog.Rarities[i]
		if state.Owned[MountCatalog.Key(spId, r)] then
			return r
		end
	end
	return nil
end

local function buildCollection()
	if colWin then
		colWin:Destroy()
		colWin = nil
	end
	if not state then
		return
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W, H = 860, 540
	local owned = 0
	for _ in pairs(state.Owned) do
		owned += 1
	end
	local w = NpcKit.Window(colGui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Monturas", string.format("Descubiertas %d / %d · Tecla " .. KeyBinds.Label("Montura") .. " para montar o bajar", owned, #MountCatalog.Species * 5), "🐎", function()
		colGui.Enabled = false
	end)
	colWin = w
	WindowDrag.Attach(w, "MountCollection", 40, 50)

	-- pestañas
	local tabs = { "Todas", "Terrestres", "Flotantes" }
	for i, t in ipairs(tabs) do
		NpcKit.Tab(w, theme, t, UDim2.fromOffset(110, 30), UDim2.fromOffset(14 + (i - 1) * 116, NpcKit.TOP), colTab == t, function()
			colTab = t
			buildCollection()
		end)
	end

	-- rejilla de especies
	local gridTop = NpcKit.TOP + 38
	local grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(14, gridTop)
	grid.Size = UDim2.fromOffset(W - 340 - 28, H - gridTop - 14)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.Parent = w
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(122, 112)
	gl.CellPadding = UDim2.fromOffset(8, 8)
	gl.Parent = grid

	local list = {}
	for _, sp in ipairs(MountCatalog.Species) do
		if colTab == "Todas" or (colTab == "Flotantes") == sp.Float then
			table.insert(list, sp)
		end
	end
	if not selSpecies or not MountCatalog.ById[selSpecies] then
		selSpecies = (state.Equipped and MountCatalog.Parse(state.Equipped) and MountCatalog.Parse(state.Equipped).Id) or MountCatalog.Species[1].Id
	end
	if not selRarity or not state.Owned[MountCatalog.Key(selSpecies, selRarity)] then
		selRarity = bestOwned(selSpecies) or "Comun"
	end
	for i, sp in ipairs(list) do
		local best = bestOwned(sp.Id)
		local card = NpcKit.Tab(grid, theme, "", UDim2.fromOffset(122, 112), UDim2.new(), sp.Id == selSpecies, function()
			selSpecies = sp.Id
			selRarity = nil
			buildCollection()
		end)
		card.LayoutOrder = i
		local icon = Instance.new("Frame")
		icon.Size = UDim2.fromOffset(46, 36)
		icon.Position = UDim2.fromOffset(38, 10)
		icon.BackgroundColor3 = if best then sp.Color else pal.Slot
		icon.BorderSizePixel = 0
		icon.Parent = card
		Instance.new("UICorner", icon).CornerRadius = UDim.new(0, if sp.Float then 18 else 8)
		if sp.Float then
			local f = text(card, "FLOTANTE", 9, pal.Accent, UDim2.fromOffset(0, 48), UDim2.new(1, 0, 0, 12), Enum.TextXAlignment.Center)
			f.Font = UITheme.Font
		end
		local sel = sp.Id == selSpecies
		local nm = text(card, if best then sp.Name else "???", 12, if sel then pal.TabOnText else pal.TabOffText, UDim2.fromOffset(4, 62), UDim2.new(1, -8, 0, 16), Enum.TextXAlignment.Center)
		nm.Font = UITheme.Font
		-- cinco puntos de rareza (encendidos los que tienes)
		for k, r in ipairs(MountCatalog.Rarities) do
			local d = Instance.new("Frame")
			d.Size = UDim2.fromOffset(12, 12)
			d.Position = UDim2.fromOffset(15 + (k - 1) * 18, 88)
			local has = state.Owned[MountCatalog.Key(sp.Id, r)] ~= nil
			d.BackgroundColor3 = if has then MountCatalog.RarityColor[r] else pal.Slot
			d.BorderSizePixel = 0
			d.Parent = card
			Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0)
		end
		lift(card)
	end

	-- detalle
	local dx = W - 340
	local det = NpcKit.Panel(w, theme, UDim2.fromOffset(326, H - NpcKit.TOP - 14), UDim2.fromOffset(dx, NpcKit.TOP), "card")
	local sp = MountCatalog.ById[selSpecies]
	local key = MountCatalog.Key(selSpecies, selRarity)
	local level = state.Owned[key]
	local have = level ~= nil
	local rcol = MountCatalog.RarityColor[selRarity]
	local pv = preview(det, UDim2.fromOffset(302, 150), UDim2.fromOffset(12, 8), sp, selRarity)
	if not have then
		pv.ImageTransparency = 0.7
		local lk = text(det, "Aún no la tienes", 14, pal.Muted, UDim2.fromOffset(12, 70), UDim2.fromOffset(302, 20), Enum.TextXAlignment.Center)
		lk.ZIndex = 5
	end
	local nm = text(det, sp.Name, 22, rcol, UDim2.fromOffset(14, 162), UDim2.fromOffset(298, 26))
	nm.Font = UITheme.Font
	text(det, string.format("%s · %s · Franja %d", MountCatalog.RarityName[selRarity], if sp.Float then "Flotante" else "Terrestre", sp.Strip), 12, pal.Muted, UDim2.fromOffset(14, 188), UDim2.fromOffset(298, 16))
	-- selector de rareza
	for k, r in ipairs(MountCatalog.Rarities) do
		local has = state.Owned[MountCatalog.Key(selSpecies, r)] ~= nil
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(14 + (k - 1) * 59, 208)
		b.Size = UDim2.fromOffset(55, 22)
		b.BackgroundColor3 = if r == selRarity then MountCatalog.RarityColor[r] else pal.Slot
		b.BackgroundTransparency = if has or r == selRarity then 0 else 0.5
		b.Text = ({ "Común", "Raro", "Épico", "Leg.", "Mít." })[k]
		b.TextColor3 = if r == selRarity then Color3.fromRGB(20, 17, 10) else MountCatalog.RarityColor[r]
		b.Font = UITheme.Font
		b.TextSize = 11
		b.Parent = det
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		b.Activated:Connect(function()
			selRarity = r
			buildCollection()
		end)
	end
	local lv = level or 1
	local sy = 238
	text(det, string.format("Velocidad  +%d%%", MountCatalog.SpeedPct(selRarity, lv)), 15, pal.Text, UDim2.fromOffset(14, sy), UDim2.fromOffset(180, 20)).Font = UITheme.Font
	text(det, string.format("Nivel %d / %d", lv, MountCatalog.MaxLevel), 15, pal.Text, UDim2.fromOffset(190, sy), UDim2.fromOffset(122, 20), Enum.TextXAlignment.Right).Font = UITheme.Font
	sy += 26
	local passives = MountCatalog.PassivesOf(sp, selRarity, lv)
	for _, p in ipairs(passives) do
		local def = MountCatalog.Passives[p.Kind]
		local pn = text(det, string.format("%s  %.1f %s", def.Name, p.Value, def.Unit), 13, pal.Text, UDim2.fromOffset(14, sy), UDim2.fromOffset(298, 16))
		pn.Font = UITheme.Font
		local pd = text(det, def.Desc, 11, pal.Muted, UDim2.fromOffset(14, sy + 16), UDim2.fromOffset(298, 28))
		pd.TextWrapped = true
		pd.TextYAlignment = Enum.TextYAlignment.Top
		sy += 46
	end
	if MountCatalog.RarityIndex[selRarity] < 4 then
		local lockedLine = text(det, "Segunda pasiva: desde Legendario.", 11, pal.Muted, UDim2.fromOffset(14, sy), UDim2.fromOffset(298, 16))
		lockedLine.TextWrapped = true
		sy += 18
	end
	local mountedNow = player:GetAttribute("Mounted") == true
	local isEq = state.Equipped == key
	local eq = NpcKit.Button(det, theme, if isEq then "EQUIPADA" else "EQUIPAR", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -92), "action", function()
		if have and not isEq then
			actionRemote:FireServer("Equip", key)
		end
	end)
	disable(eq, not have or isEq)
	local ride = NpcKit.Button(det, theme, if mountedNow then "BAJAR  [" .. KeyBinds.Label("Montura") .. "]" else "MONTAR  [" .. KeyBinds.Label("Montura") .. "]", UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -50), "sell", function()
		actionRemote:FireServer("Toggle")
	end)
	disable(ride, state.Equipped == nil)
end

-- ============ ECLOSIÓN ============
local hatchFrame = nil
local function showHatch(res)
	local sp = MountCatalog.ById[res.Species]
	if not sp then
		return
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	if hatchFrame then
		hatchFrame:Destroy()
	end
	local col = MountCatalog.RarityColor[res.Rarity]
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(6, 7, 14)
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	f.Parent = hatchGui
	hatchFrame = f
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.42)
	glow.Size = UDim2.fromOffset(520, 520)
	glow.BackgroundColor3 = col
	glow.BackgroundTransparency = 0.82
	glow.BorderSizePixel = 0
	glow.Parent = f
	Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)

	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.new(0.5, 0, 0, 56)
	top.Size = UDim2.fromOffset(500, 30)
	top.Text = "E C L O S I Ó N"
	top.TextColor3 = Color3.fromRGB(190, 195, 215)
	top.Font = UITheme.Font
	top.TextSize = 22
	top.Parent = f

	local chip = Instance.new("TextLabel")
	chip.AnchorPoint = Vector2.new(0.5, 0)
	chip.Position = UDim2.new(0.5, 0, 0, 100)
	chip.Size = UDim2.fromOffset(190, 30)
	chip.BackgroundColor3 = col
	chip.Text = string.upper(MountCatalog.RarityName[res.Rarity])
	chip.TextColor3 = Color3.fromRGB(20, 17, 10)
	chip.Font = UITheme.Font
	chip.TextSize = 18
	chip.Parent = f
	Instance.new("UICorner", chip).CornerRadius = UDim.new(1, 0)

	local vp = preview(f, UDim2.fromOffset(460, 300), UDim2.new(0.5, -230, 0, 140), sp, res.Rarity)

	local nm = Instance.new("TextLabel")
	nm.BackgroundTransparency = 1
	nm.AnchorPoint = Vector2.new(0.5, 0)
	nm.Position = UDim2.new(0.5, 0, 0, 446)
	nm.Size = UDim2.fromOffset(700, 48)
	nm.Text = sp.Name
	nm.TextColor3 = Color3.new(1, 1, 1)
	nm.Font = UITheme.Font
	nm.TextSize = 40
	nm.Parent = f

	local lvl = res.Level or 1
	local info = Instance.new("TextLabel")
	info.BackgroundTransparency = 1
	info.AnchorPoint = Vector2.new(0.5, 0)
	info.Position = UDim2.new(0.5, 0, 0, 498)
	info.Size = UDim2.fromOffset(700, 24)
	local line
	if res.New then
		line = string.format("¡Montura nueva! Velocidad +%d%%", MountCatalog.SpeedPct(res.Rarity, lvl))
	elseif res.Gold and res.Gold > 0 then
		line = string.format("Repetida en nivel máximo: +%d de oro", res.Gold)
	else
		line = string.format("Repetida: sube a nivel %d / %d (velocidad +%d%%)", lvl, MountCatalog.MaxLevel, MountCatalog.SpeedPct(res.Rarity, lvl))
	end
	info.Text = line
	info.TextColor3 = col
	info.Font = UITheme.Font
	info.TextSize = 18
	info.Parent = f

	local close = NpcKit.Button(f, theme, "CONTINUAR", UDim2.fromOffset(220, 44), UDim2.new(0.5, -110, 0, 540), "action", function()
		hatchGui.Enabled = false
		f:Destroy()
		hatchFrame = nil
	end)
	f.ZIndex = 19
	for _, d in ipairs(f:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = 20
		end
	end
	hatchGui.Enabled = true
	local _ = pal
	local _v = vp
end

---------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------
stateRemote.OnClientEvent:Connect(function(s)
	state = s
	clockOffset = s.Now - os.time()
	if incGui.Enabled then
		buildIncubator()
	end
	if colGui.Enabled then
		buildCollection()
	end
end)

hatchRemote.OnClientEvent:Connect(function(res)
	incGui.Enabled = false
	showHatch(res)
end)

openRemote.OnClientEvent:Connect(function(what)
	if what == "Incubator" then
		colGui.Enabled = false
		buildIncubator()
		incGui.Enabled = true
	end
end)

MenuBus.Event:Connect(function(name)
	if name == "Mounts" then
		if colGui.Enabled then
			colGui.Enabled = false
		else
			incGui.Enabled = false
			actionRemote:FireServer("Sync")
			buildCollection()
			colGui.Enabled = true
		end
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= 0.5 then
		acc = 0
		if incGui.Enabled then
			updateTimers()
		end
	end
end)

player:GetAttributeChangedSignal("Mounted"):Connect(function()
	if colGui.Enabled then
		buildCollection()
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if KeyBinds.Matches(input, "Montura") then
		actionRemote:FireServer("Toggle")
	end
end)

actionRemote:FireServer("Sync")

---------------------------------------------------------------------
-- Monturas en el mundo (de todos los jugadores cercanos)
---------------------------------------------------------------------
local VIEW_RANGE = 160
local fxFolder = Workspace:FindFirstChild("MountsFx")
if fxFolder then
	fxFolder:Destroy() -- si el script se recarga, se borran las copias viejas
end
fxFolder = Instance.new("Folder")
fxFolder.Name = "MountsFx"
fxFolder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local rigs = {} -- jugador -> { Key, Rig, Yaw }

-- MONTURA SUELTA en la Casa VIP (atributo de jugador "MountHome" = centro del jardín): pasea sola por allí aunque el dueño no esté
local homeRigs: { [string]: any } = {} -- "userId;clave" -> rig (cada montura suelta es una instantánea propia)
local function removeHome(id: string)
	local r = homeRigs[id]
	if r then
		r.Rig.Model:Destroy()
		homeRigs[id] = nil
	end
end

local function removeRig(pl)
	local r = rigs[pl]
	if r then
		r.Rig.Model:Destroy()
		rigs[pl] = nil
	end
end

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local ignore = { fxFolder, Workspace:FindFirstChild("PetsFx") or fxFolder, fxFolder }
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local key = char and char:GetAttribute("Mounted") == true and char:GetAttribute("MountKey") or nil
		local show = key ~= nil and root ~= nil and (root.Position - camPos).Magnitude < VIEW_RANGE
		if not show then
			removeRig(pl)
		else
			local cur = rigs[pl]
			if cur and cur.Key ~= key then
				removeRig(pl)
				cur = nil
			end
			if not cur then
				local sp, rar = MountCatalog.Parse(key)
				if sp then
					local rig = MountModels.Build(sp, rar)
					rig.Model.Parent = fxFolder
					cur = { Key = key, Rig = rig, Yaw = 0, LastPos = root.Position, Speed = 0 }
					rigs[pl] = cur
				end
			end
			if cur then
				local pos = root.Position
				local dt = 1 / 60
				local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(cur.LastPos.X, 0, cur.LastPos.Z)).Magnitude
				cur.Speed = cur.Speed + (d / dt - cur.Speed) * 0.2
				cur.LastPos = pos
				ignore[3] = char
				rayParams.FilterDescendantsInstances = ignore
				local hit = Workspace:Raycast(pos, Vector3.new(0, -24, 0), rayParams)
				local groundY = if hit then hit.Position.Y else pos.Y - 5
				local look = root.CFrame.LookVector
				local cf = CFrame.lookAt(Vector3.new(pos.X, groundY, pos.Z), Vector3.new(pos.X + look.X, groundY, pos.Z + look.Z))
				if cur.Rig.Float then
					cf = cf * CFrame.new(0, MountModels.FloatHover + math.sin(t * 2 + pl.UserId % 7) * 0.15, 0)
				end
				MountModels.Animate(cur.Rig, cf, t, cur.Speed)
			end
		end
	end
	for pl in pairs(rigs) do
		if not pl.Parent then
			removeRig(pl)
		end
	end
	-- monturas sueltas (lista "MountHomeKeys", independiente de la que lleve equipada)
	local want: { [string]: { Pl: Player, Key: string, Home: Vector3 } } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local home = pl:GetAttribute("MountHome")
		local raw = pl:GetAttribute("MountHomeKeys")
		if typeof(home) == "Vector3" and typeof(raw) == "string" and (home - camPos).Magnitude <= VIEW_RANGE then
			for key in string.gmatch(raw, "[^;]+") do
				want[pl.UserId .. ";" .. key] = { Pl = pl, Key = key, Home = home }
			end
		end
	end
	for id in pairs(homeRigs) do
		if not want[id] then
			removeHome(id)
		end
	end
	for id, w in pairs(want) do
		local pl, key, home = w.Pl, w.Key, w.Home
		local cur = homeRigs[id]
		if not cur then
			local sp, rar = MountCatalog.Parse(key)
			if sp then
				local rig = MountModels.Build(sp, rar)
				rig.Model.Parent = fxFolder
				cur = { Rig = rig, Pos = home + Vector3.new((math.random() * 2 - 1) * 10, 0, (math.random() * 2 - 1) * 8), Target = home, NextAt = 0, Yaw = 0, Speed = 0, Seed = math.random() * 7 }
				homeRigs[id] = cur
			end
		end
		if cur then
			if t > cur.NextAt or (cur.Home :: Vector3?) ~= home then
				cur.Home = home
				cur.Target = home + Vector3.new((math.random() * 2 - 1) * 46, 0, (math.random() * 2 - 1) * 38)
				cur.NextAt = t + 4 + math.random() * 6
			end
			local flat = Vector3.new(cur.Target.X - cur.Pos.X, 0, cur.Target.Z - cur.Pos.Z)
			local dt = 1 / 60
			local moving = flat.Magnitude > 1.5
			if moving then
				local stepV = flat.Unit * math.min(flat.Magnitude, 5 * dt)
				cur.Pos = cur.Pos + stepV
				cur.Yaw = math.atan2(-flat.X, -flat.Z)
			end
			cur.Speed = cur.Speed + ((if moving then 5 else 0) - cur.Speed) * 0.2
			rayParams.FilterDescendantsInstances = { fxFolder, Workspace:FindFirstChild("PetsFx") or fxFolder }
			local hit = Workspace:Raycast(cur.Pos + Vector3.new(0, 12, 0), Vector3.new(0, -40, 0), rayParams)
			local gy = if hit then hit.Position.Y else home.Y
			local cf = CFrame.new(Vector3.new(cur.Pos.X, gy, cur.Pos.Z)) * CFrame.Angles(0, cur.Yaw, 0)
			if cur.Rig.Float then
				cf = cf * CFrame.new(0, MountModels.FloatHover + math.sin(t * 2 + cur.Seed) * 0.15, 0)
			end
			MountModels.Animate(cur.Rig, cf, t, cur.Speed)
		end
	end
end)

---------------------------------------------------------------------
-- POSE SENTADO (todos los jugadores montados, R6 y R15). Se aplica después de CharacterAnimClient (prioridad Last + 1).
-- Piernas dobladas hacia adelante y brazos en las riendas; mientras dura un ataque no se tocan los brazos (los mueve CharacterAnimClient).
---------------------------------------------------------------------
local SIT_HIP = 1.45 -- muslo casi horizontal hacia adelante (R15)
local SIT_KNEE = -2.5 -- rodilla muy doblada: la pierna queda recogida sobre el lomo, no cuelga
local SIT_HIP_R6 = 1.1
local REIN_ARM = 0.75
local sitCache = setmetatable({}, { __mode = "k" })

local function joint(m, part, name)
	local p = m:FindFirstChild(part)
	local j = p and p:FindFirstChild(name)
	if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return j
	end
	return nil
end

local function sitJoints(m)
	local c = sitCache[m]
	if c ~= nil then
		return c or nil
	end
	local torso = m:FindFirstChild("Torso")
	local j = nil
	if torso then
		local rs, ls, rh, lh = torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder"), torso:FindFirstChild("Right Hip"), torso:FindFirstChild("Left Hip")
		if rs and ls and rh and lh then
			j = { R15 = false, RS = rs, LS = ls, RH = rh, LH = lh }
		end
	else
		local rh, lh = joint(m, "RightUpperLeg", "RightHip"), joint(m, "LeftUpperLeg", "LeftHip")
		if rh and lh then
			j = {
				R15 = true, RH = rh, LH = lh,
				RK = joint(m, "RightLowerLeg", "RightKnee"), LK = joint(m, "LeftLowerLeg", "LeftKnee"),
				RS = joint(m, "RightUpperArm", "RightShoulder"), LS = joint(m, "LeftUpperArm", "LeftShoulder"),
				RE = joint(m, "RightLowerArm", "RightElbow"), LE = joint(m, "LeftLowerArm", "LeftElbow"),
			}
		end
	end
	sitCache[m] = j or false
	return j
end

local function attacking(m)
	local at, len = m:GetAttribute("AnimAt"), m:GetAttribute("AnimLen")
	if typeof(at) == "number" and typeof(len) == "number" then
		local age = Workspace:GetServerTimeNow() - at
		return age >= -0.05 and age < len
	end
	return false
end

local function applySit(m)
	local j = sitJoints(m)
	if not j then
		return
	end
	local arms = not attacking(m)
	if j.R15 then
		j.RH.Transform = CFrame.Angles(SIT_HIP, 0, 0)
		j.LH.Transform = CFrame.Angles(SIT_HIP, 0, 0)
		if j.RK then
			j.RK.Transform = CFrame.Angles(SIT_KNEE, 0, 0)
		end
		if j.LK then
			j.LK.Transform = CFrame.Angles(SIT_KNEE, 0, 0)
		end
		if arms then
			if j.RS then
				j.RS.Transform = CFrame.Angles(REIN_ARM, 0, 0)
			end
			if j.LS then
				j.LS.Transform = CFrame.Angles(REIN_ARM, 0, 0)
			end
			if j.RE then
				j.RE.Transform = CFrame.Angles(0.6, 0, 0)
			end
			if j.LE then
				j.LE.Transform = CFrame.Angles(0.6, 0, 0)
			end
		end
	else
		j.RH.Transform = CFrame.Angles(0, 0, SIT_HIP_R6)
		j.LH.Transform = CFrame.Angles(0, 0, -SIT_HIP_R6)
		if arms then
			j.RS.Transform = CFrame.Angles(0, 0, REIN_ARM)
			j.LS.Transform = CFrame.Angles(0, 0, -REIN_ARM)
		end
	end
end

-- Mientras se va montado, las animaciones de Roblox (correr/caminar/saltar/caer) se dejan con peso ~0 para que no peleen con la pose.
-- No se paran (así al bajar vuelven solas): se guarda el peso original y se restaura al desmontar.
local dimmed: { [AnimationTrack]: { Char: Model, W: number } } = {}

local function dimTracks(char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
		local d = dimmed[tr]
		if not d then
			dimmed[tr] = { Char = char, W = if tr.WeightTarget > 0.01 then tr.WeightTarget else 1 }
			tr:AdjustWeight(0.001, 0)
		elseif tr.WeightTarget > 0.01 then
			tr:AdjustWeight(0.001, 0) -- Animate lo volvió a subir
		end
	end
end

local function restoreTracks()
	for tr, d in pairs(dimmed) do
		if not d.Char.Parent or d.Char:GetAttribute("Mounted") ~= true or not tr.IsPlaying then
			dimmed[tr] = nil
			if tr.IsPlaying then
				tr:AdjustWeight(d.W, 0.15)
			end
		end
	end
end

RunService:BindToRenderStep("MountSitPose", Enum.RenderPriority.Last.Value + 1, function()
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or Vector3.zero
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if char and root and char:GetAttribute("Mounted") == true and (root.Position - camPos).Magnitude < VIEW_RANGE then
			dimTracks(char)
			applySit(char)
		end
	end
	restoreTracks()
end)
script.Destroying:Connect(function()
	pcall(function()
		RunService:UnbindFromRenderStep("MountSitPose")
	end)
end)
