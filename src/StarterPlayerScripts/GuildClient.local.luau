--!strict
--[[
    GuildClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > GuildClient
    Ventana del GREMIO DE FACCIÓN (botón "Facción [G]" de la barra de menú, o tecla G; la misma tecla/botón la cierra). Pestañas:
      Resumen · Bendiciones (aportar oro/materiales) · Ranking (semanal / total) · Registro.
    Datos: GuildState (servidor). Acciones: GuildAction ("State" | "Donate", bendición, "Gold"|idMaterial, cantidad). Resultado: GuildResult.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local GuildCatalog = require(Modules:WaitForChild("GuildCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

local stateRemote = ClientNet.Get("GuildState")
local actionRemote = ClientNet.Get("GuildAction")
local resultRemote = ClientNet.Get("GuildResult")

local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local GREEN, RED = "#3fae55", "#d04545"
local theme = UITheme.For(player:GetAttribute("Faction"))
local pal = NpcKit.Palette(theme)
local TABS = { "Resumen", "Bendiciones", "Ranking", "Registro" }

local gui = Instance.new("ScreenGui")
gui.Name = "GuildGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local state: any = nil
local tab = "Resumen"
local rankWeekly = true
local selected = "Fortuna"
local win: Frame? = nil
local body: Frame? = nil
local resultLabel: TextLabel? = nil

local function withDots(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	return out
end

local function short(n: number): string
	if n >= 1000000 then
		return string.format("%.2fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(math.floor(n))
end

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2, kind: string, cb: () -> ()): TextButton
	local b = NpcKit.Button(parent, theme, text, size, pos, kind, cb)
	b.TextSize = 12
	return b
end

local function bar(parent: Instance, pos: UDim2, size: UDim2, frac: number, color: Color3)
	local bg = Instance.new("Frame")
	bg.Position = pos
	bg.Size = size
	bg.BackgroundColor3 = pal.Slot
	bg.BorderSizePixel = 0
	bg.ZIndex = 4
	bg.Parent = parent
	Instance.new("UICorner", bg)
	local st = Instance.new("UIStroke")
	st.Color = pal.Edge2
	st.Thickness = 1
	st.Parent = bg
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = 5
	fill.Parent = bg
	Instance.new("UICorner", fill)
end

local function txt(parent: Instance, text: string, size: number, color: Color3, pos: UDim2, sz: UDim2, align: Enum.TextXAlignment?): TextLabel
	local t = UITheme.Text(parent, text, size, color, pos, sz, align)
	t.TextStrokeTransparency = 1
	t.ZIndex = 6
	return t
end

local function passiveInfo(id: string): any
	if state then
		for _, p in ipairs(state.Passives) do
			if p.Id == id then
				return p
			end
		end
	end
	return nil
end

local function effectText(def: any, level: number): string
	return string.format("+%.1f%% %s", def.PerLevel * level * 100, def.Desc:lower())
end

local build: () -> ()

local function donate(kind: string, qty: number)
	actionRemote:FireServer("Donate", selected, kind, qty)
end

---------------------------------------------------------------------
-- Pestañas (área de contenido: 852 x 470)
---------------------------------------------------------------------
local function tabResumen(b: Frame)
	local s = state
	local left = NpcKit.Panel(b, theme, UDim2.fromOffset(420, 300), UDim2.fromOffset(0, 0), "card")
	txt(left, string.format("Gremio %s", tostring(s.Faction)), 18, pal.FText, UDim2.fromOffset(14, 8), UDim2.fromOffset(380, 24))
	local t = txt(left, "Todos los jugadores de tu facción forman parte. Las bendiciones se financian con aportes y valen para todos, en todos los servidores.", 12, pal.FMuted, UDim2.fromOffset(14, 34), UDim2.fromOffset(392, 34))
	t.TextWrapped = true
	t.TextYAlignment = Enum.TextYAlignment.Top
	local function stat(y: number, label: string, value: string)
		txt(left, label, 13, pal.FMuted, UDim2.fromOffset(14, y), UDim2.fromOffset(240, 18))
		txt(left, value, 14, pal.FText, UDim2.fromOffset(200, y), UDim2.fromOffset(206, 18), Enum.TextXAlignment.Right)
	end
	stat(78, "Nivel del gremio", string.format("%d / %d", s.TotalLevels, s.MaxTotal))
	bar(left, UDim2.fromOffset(14, 100), UDim2.fromOffset(392, 10), s.TotalLevels / math.max(s.MaxTotal, 1), pal.Accent)
	stat(124, "Conectados (tu facción)", tostring(s.Online))
	stat(148, "Tu aporte esta semana", withDots(s.MineWeek) .. " PA")
	stat(172, "Tu aporte total", withDots(s.MineTotal) .. " PA")
	stat(196, "Tu límite de hoy", string.format("%s / %s PA", withDots(s.DailyUsed), withDots(s.DailyCap)))
	bar(left, UDim2.fromOffset(14, 218), UDim2.fromOffset(392, 10), s.DailyUsed / math.max(s.DailyCap, 1), Color3.fromRGB(230, 160, 50))
	local note = txt(left, if s.Shared then "Los aportes se sincronizan con todos los servidores cada ~40 s." else "⚠ Sin DataStore (Studio): el gremio solo existe en este servidor.", 11, pal.FMuted, UDim2.fromOffset(14, 246), UDim2.fromOffset(392, 16))
	note.TextWrapped = true
	txt(left, "PA = puntos de aporte: 1 oro = 1 PA; los materiales valen más según su rareza.", 11, pal.FMuted, UDim2.fromOffset(14, 268), UDim2.fromOffset(392, 16))

	-- tarjetas de pasivas activas
	local right = NpcKit.Panel(b, theme, UDim2.fromOffset(424, 300), UDim2.fromOffset(428, 0), "card")
	txt(right, "Bendiciones activas", 16, pal.FText, UDim2.fromOffset(14, 8), UDim2.fromOffset(300, 22))
	for i, p in ipairs(s.Passives) do
		local def = GuildCatalog.ById[p.Id]
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local card = NpcKit.Panel(right, theme, UDim2.fromOffset(196, 78), UDim2.fromOffset(14 + col * 204, 38 + row * 86), "inset")
		txt(card, string.format("%s %s", def.Icon, def.Name), 13, pal.Text, UDim2.fromOffset(8, 5), UDim2.fromOffset(120, 18))
		txt(card, string.format("Nv. %d/%d", p.Level, GuildCatalog.MAX_LEVEL), 12, pal.Accent, UDim2.fromOffset(110, 5), UDim2.fromOffset(78, 18), Enum.TextXAlignment.Right)
		local e = txt(card, if p.Level > 0 then effectText(def, p.Level) else "sin nivel todavía", 11, if p.Level > 0 then pal.Text else pal.Muted, UDim2.fromOffset(8, 26), UDim2.fromOffset(180, 30))
		e.TextWrapped = true
		e.TextYAlignment = Enum.TextYAlignment.Top
		bar(card, UDim2.fromOffset(8, 62), UDim2.fromOffset(180, 7), if p.Need > 0 then p.Progress / p.Need else 1, def.Color)
	end
	-- mejores aportantes (vista rápida)
	local top = NpcKit.Panel(b, theme, UDim2.fromOffset(852, 160), UDim2.fromOffset(0, 308), "card")
	txt(top, "Mejores aportantes de la semana", 14, pal.FText, UDim2.fromOffset(14, 6), UDim2.fromOffset(400, 20))
	if #s.Top == 0 then
		txt(top, "Aún nadie ha aportado esta semana. ¡Sé el primero!", 12, pal.FMuted, UDim2.fromOffset(14, 36), UDim2.fromOffset(500, 18))
	end
	for i, r in ipairs(s.Top) do
		if i > 5 then
			break
		end
		local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else tostring(i) .. "."
		local y = 30 + (i - 1) * 25
		txt(top, medal, 13, pal.FText, UDim2.fromOffset(14, y), UDim2.fromOffset(34, 18))
		txt(top, tostring(r.Name), 13, if r.Mine then pal.Accent else pal.FText, UDim2.fromOffset(52, y), UDim2.fromOffset(300, 18))
		txt(top, withDots(r.Value) .. " PA", 13, pal.FText, UDim2.fromOffset(620, y), UDim2.fromOffset(212, 18), Enum.TextXAlignment.Right)
	end
end

local function tabBendiciones(b: Frame)
	local s = state
	-- lista izquierda de pasivas
	local listBox = NpcKit.Panel(b, theme, UDim2.fromOffset(330, 466), UDim2.fromOffset(0, 0), "card")
	for i, p in ipairs(s.Passives) do
		local def = GuildCatalog.ById[p.Id]
		local y = 8 + (i - 1) * 76
		local isSel = p.Id == selected
		local row = Instance.new("TextButton")
		row.Position = UDim2.fromOffset(8, y)
		row.Size = UDim2.fromOffset(314, 70)
		row.BackgroundColor3 = if isSel then pal.TabOn else pal.Inset
		row.Text = ""
		row.AutoButtonColor = false
		row.ZIndex = 5
		row.Parent = listBox
		Instance.new("UICorner", row)
		local st = Instance.new("UIStroke")
		st.Color = if isSel then pal.Accent else pal.Edge2
		st.Thickness = if isSel then 2 else 1
		st.Parent = row
		local nameCol = if isSel then pal.TabOnText else pal.Text
		txt(row, string.format("%s %s", def.Icon, def.Name), 15, nameCol, UDim2.fromOffset(10, 6), UDim2.fromOffset(170, 20))
		txt(row, string.format("Nv. %d/%d", p.Level, GuildCatalog.MAX_LEVEL), 13, if isSel then pal.TabOnText else pal.Accent, UDim2.fromOffset(200, 7), UDim2.fromOffset(104, 18), Enum.TextXAlignment.Right)
		-- pips de nivel (10)
		for n = 1, GuildCatalog.MAX_LEVEL do
			local pip = Instance.new("Frame")
			pip.Position = UDim2.fromOffset(10 + (n - 1) * 29, 30)
			pip.Size = UDim2.fromOffset(25, 7)
			pip.BackgroundColor3 = if n <= p.Level then def.Color else pal.Slot
			pip.BorderSizePixel = 0
			pip.ZIndex = 6
			pip.Parent = row
			Instance.new("UICorner", pip)
		end
		bar(row, UDim2.fromOffset(10, 44), UDim2.fromOffset(294, 6), if p.Need > 0 then p.Progress / p.Need else 1, def.Color)
		txt(row, if p.Need > 0 then string.format("%s / %s PA", short(p.Progress), short(p.Need)) else "MÁXIMO", 10, if isSel then pal.TabOnText else pal.Muted, UDim2.fromOffset(10, 52), UDim2.fromOffset(294, 14))
		row.Activated:Connect(function()
			selected = p.Id
			build()
		end)
	end
	-- panel derecho: detalle + aportes
	local detail = NpcKit.Panel(b, theme, UDim2.fromOffset(514, 466), UDim2.fromOffset(338, 0), "card")
	local p = passiveInfo(selected)
	local def = GuildCatalog.ById[selected]
	if not p or not def then
		return
	end
	txt(detail, string.format("%s %s", def.Icon, def.Name), 20, pal.FText, UDim2.fromOffset(16, 10), UDim2.fromOffset(300, 26))
	txt(detail, def.Desc, 13, pal.FMuted, UDim2.fromOffset(16, 38), UDim2.fromOffset(480, 18))
	local cur = NpcKit.Panel(detail, theme, UDim2.fromOffset(482, 64), UDim2.fromOffset(16, 64), "inset")
	txt(cur, "Ahora: " .. (if p.Level > 0 then effectText(def, p.Level) else "—"), 13, pal.Text, UDim2.fromOffset(12, 6), UDim2.fromOffset(460, 18))
	if p.Level < GuildCatalog.MAX_LEVEL then
		txt(cur, "Siguiente: " .. effectText(def, p.Level + 1), 13, pal.Accent, UDim2.fromOffset(12, 24), UDim2.fromOffset(460, 18))
		txt(cur, string.format("Faltan %s PA para el nivel %d", withDots(p.Need - p.Progress), p.Level + 1), 11, pal.Muted, UDim2.fromOffset(12, 44), UDim2.fromOffset(460, 14))
	else
		txt(cur, "Bendición al máximo", 13, pal.Accent, UDim2.fromOffset(12, 24), UDim2.fromOffset(460, 18))
		return
	end
	local left = math.max(0, s.DailyCap - s.DailyUsed)
	txt(detail, string.format("Tu límite de hoy: quedan %s PA", withDots(left)), 12, pal.FText, UDim2.fromOffset(16, 142), UDim2.fromOffset(480, 16))
	txt(detail, string.format("ORO  (tienes %s)", withDots(s.Gold)), 13, pal.FText, UDim2.fromOffset(16, 170), UDim2.fromOffset(300, 18))
	-- el oro se aporta como % del límite diario que te queda (limitado por tu oro)
	local function goldFor(frac: number): number
		return math.max(1, math.floor(math.min(s.Gold, left * frac)))
	end
	local pcts = { { "10%", 0.10 }, { "25%", 0.25 }, { "Máx", 1 } }
	for i, pc in ipairs(pcts) do
		local amount = goldFor(pc[2])
		button(detail, string.format("%s  (%s)", pc[1], short(amount)), UDim2.fromOffset(16 + (i - 1) * 124, 192), UDim2.fromOffset(118, 30), "buy", function()
			if s.Gold > 0 and left > 0 then
				donate("Gold", amount)
			end
		end)
	end
	txt(detail, "MATERIALES", 13, pal.FText, UDim2.fromOffset(16, 238), UDim2.fromOffset(300, 18))
	if #s.Mats == 0 then
		txt(detail, "No tienes materiales aportables.", 12, pal.FMuted, UDim2.fromOffset(16, 262), UDim2.fromOffset(400, 16))
	end
	for i, m in ipairs(s.Mats) do
		if i > 5 then
			break
		end
		local y = 260 + (i - 1) * 40
		txt(detail, string.format("%s x%d", m.Name, m.Have), 13, pal.FText, UDim2.fromOffset(16, y), UDim2.fromOffset(240, 16))
		txt(detail, string.format("%d PA c/u", m.PA), 11, pal.FMuted, UDim2.fromOffset(16, y + 17), UDim2.fromOffset(240, 14))
		button(detail, "+1", UDim2.fromOffset(300, y), UDim2.fromOffset(60, 28), "action", function()
			donate(m.Id, 1)
		end)
		button(detail, "+10", UDim2.fromOffset(366, y), UDim2.fromOffset(60, 28), "action", function()
			donate(m.Id, math.min(10, m.Have))
		end)
		button(detail, "Todo", UDim2.fromOffset(432, y), UDim2.fromOffset(70, 28), "buy", function()
			donate(m.Id, m.Have)
		end)
	end
end

local function tabRanking(b: Frame)
	local box = NpcKit.Panel(b, theme, UDim2.fromOffset(852, 466), UDim2.fromOffset(0, 0), "card")
	button(box, "Semana", UDim2.fromOffset(14, 10), UDim2.fromOffset(100, 28), if rankWeekly then "buy" else "neutral", function()
		rankWeekly = true
		build()
	end)
	button(box, "Total", UDim2.fromOffset(120, 10), UDim2.fromOffset(100, 28), if not rankWeekly then "buy" else "neutral", function()
		rankWeekly = false
		build()
	end)
	txt(box, if rankWeekly then "Se reinicia cada semana (lunes UTC)" else "Desde que existe el gremio", 12, pal.FMuted, UDim2.fromOffset(300, 16), UDim2.fromOffset(536, 16), Enum.TextXAlignment.Right)
	-- cabecera de columnas
	txt(box, "#", 11, pal.FMuted, UDim2.fromOffset(20, 46), UDim2.fromOffset(40, 14))
	txt(box, "JUGADOR", 11, pal.FMuted, UDim2.fromOffset(70, 46), UDim2.fromOffset(300, 14))
	txt(box, "NIVEL", 11, pal.FMuted, UDim2.fromOffset(420, 46), UDim2.fromOffset(70, 14))
	txt(box, "CLASE", 11, pal.FMuted, UDim2.fromOffset(500, 46), UDim2.fromOffset(150, 14))
	txt(box, "APORTE", 11, pal.FMuted, UDim2.fromOffset(640, 46), UDim2.fromOffset(196, 14), Enum.TextXAlignment.Right)
	local list = if rankWeekly then state.Top else state.TopAll
	if #list == 0 then
		txt(box, "Aún nadie ha aportado. ¡Sé el primero!", 14, pal.FMuted, UDim2.fromOffset(20, 76), UDim2.fromOffset(500, 20))
	end
	for i, r in ipairs(list) do
		local y = 64 + (i - 1) * 39
		local row = NpcKit.Panel(box, theme, UDim2.fromOffset(824, 34), UDim2.fromOffset(14, y), if r.Mine then "plate" else "inset")
		local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else tostring(i) .. "."
		local tc = if r.Mine then pal.FText else pal.Text
		txt(row, medal, 14, tc, UDim2.fromOffset(8, 8), UDim2.fromOffset(40, 18))
		txt(row, tostring(r.Name), 14, tc, UDim2.fromOffset(56, 8), UDim2.fromOffset(340, 18))
		txt(row, if r.Lv then tostring(r.Lv) else "—", 14, tc, UDim2.fromOffset(406, 8), UDim2.fromOffset(70, 18))
		txt(row, if r.Role then tostring(r.Role) else "—", 14, tc, UDim2.fromOffset(486, 8), UDim2.fromOffset(150, 18))
		txt(row, withDots(r.Value) .. " PA", 14, tc, UDim2.fromOffset(626, 8), UDim2.fromOffset(188, 18), Enum.TextXAlignment.Right)
	end
end

local function tabRegistro(b: Frame)
	local box = NpcKit.Panel(b, theme, UDim2.fromOffset(852, 466), UDim2.fromOffset(0, 0), "card")
	if #state.Log == 0 then
		txt(box, "Todavía no hay actividad. Los aportes grandes y las subidas de nivel aparecen aquí.", 13, pal.FMuted, UDim2.fromOffset(16, 14), UDim2.fromOffset(800, 20))
		return
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(8, 8)
	scroll.Size = UDim2.fromOffset(836, 450)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.ZIndex = 4
	scroll.CanvasSize = UDim2.fromOffset(0, #state.Log * 32)
	scroll.Parent = box
	for i, e in ipairs(state.Log) do
		local ago = math.max(0, (state.Now or 0) - e.t)
		local when = if ago < 3600 then string.format("hace %d min", math.floor(ago / 60)) elseif ago < 86400 then string.format("hace %d h", math.floor(ago / 3600)) else string.format("hace %d d", math.floor(ago / 86400))
		local l = txt(scroll, string.format("%s  ·  %s", tostring(e.m), when), 13, pal.FText, UDim2.fromOffset(8, (i - 1) * 32 + 4), UDim2.fromOffset(800, 26))
		l.TextWrapped = true
	end
end

---------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------
build = function()
	theme = UITheme.For(player:GetAttribute("Faction"))
	pal = NpcKit.Palette(theme)
	if win then
		win:Destroy()
	end
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(880, 640), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Gremio de Facción",
		"Bendiciones compartidas por toda la facción · aporta oro y materiales", "⚑", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Guild", 52, 50)
	for i, name in ipairs(TABS) do
		NpcKit.Tab(w, theme, name, UDim2.fromOffset(140, 28), UDim2.fromOffset(14 + (i - 1) * 146, 72), tab == name, function()
			tab = name
			build()
		end)
	end
	if not state then
		txt(w, "Cargando… (elige una facción para unirte al gremio)", 14, pal.FText, UDim2.fromOffset(18, 120), UDim2.fromOffset(480, 20))
		return
	end
	local b = Instance.new("Frame")
	b.Position = UDim2.fromOffset(14, 108)
	b.Size = UDim2.fromOffset(852, 470)
	b.BackgroundTransparency = 1
	b.Parent = w
	body = b
	if tab == "Resumen" then
		tabResumen(b)
	elseif tab == "Bendiciones" then
		tabBendiciones(b)
	elseif tab == "Ranking" then
		tabRanking(b)
	else
		tabRegistro(b)
	end
	resultLabel = txt(w, "", 13, pal.FText, UDim2.fromOffset(18, 584), UDim2.fromOffset(840, 20))
	resultLabel.RichText = true
	local f = txt(w, "Límite diario por jugador: " .. withDots(GuildCatalog.DailyCap(player:GetAttribute("Level") :: any or 1)) .. " PA · las bendiciones suben con el esfuerzo de toda la facción.", 11, pal.FMuted, UDim2.fromOffset(18, 610), UDim2.fromOffset(840, 20))
	f.TextWrapped = true
	f.TextYAlignment = Enum.TextYAlignment.Top
end

local function open()
	if gui.Enabled then
		gui.Enabled = false
		return
	end
	build()
	gui.Enabled = true
	actionRemote:FireServer("State")
end

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(s: any)
		if typeof(s) == "table" and typeof(s.Passives) == "table" then
			state = s
			if gui.Enabled then
				build()
			end
		end
	end)
end
if resultRemote then
	resultRemote.OnClientEvent:Connect(function(ok: any, text: any)
		if resultLabel and gui.Enabled then
			resultLabel.Text = string.format('<font color="%s"><b>%s</b></font>', if ok == true then GREEN else RED, tostring(text))
		end
	end)
end

-- se abre/cierra desde el botón "Facción [G]" de la barra de menú (MenuBus "Guild") y con la tecla G
MenuBus.Event:Connect(function(name: string)
	if name == "Guild" then
		open()
	end
end)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and KeyBinds.Matches(input, "Faccion") then
		open()
	end
end)

task.spawn(function()
	while true do
		task.wait(8)
		if gui.Enabled then
			actionRemote:FireServer("State")
		end
	end
end)

actionRemote:FireServer("State")
print("[GuildClient] listo")
