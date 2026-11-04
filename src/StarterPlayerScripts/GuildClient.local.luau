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
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local GuildCatalog = require(Modules:WaitForChild("GuildCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

local stateRemote = ClientNet.Get("GuildState")
local actionRemote = ClientNet.Get("GuildAction")
local resultRemote = ClientNet.Get("GuildResult")

local GREEN, RED = "#6fdc7f", "#ff6b6b"
local theme = UITheme.For(player:GetAttribute("Faction"))
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

local function button(parent: Instance, text: string, pos: UDim2, size: UDim2, color: Color3, cb: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Position = pos
	b.Size = size
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = UITheme.Font
	b.TextSize = 12
	b.TextWrapped = true
	b.Text = text
	b.ZIndex = 30
	b.Parent = parent
	Instance.new("UICorner", b)
	b.Activated:Connect(cb)
	return b
end

local function bar(parent: Instance, pos: UDim2, size: UDim2, frac: number, color: Color3)
	local bg = Instance.new("Frame")
	bg.Position = pos
	bg.Size = size
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
	bg.BorderSizePixel = 0
	bg.Parent = parent
	Instance.new("UICorner", bg)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = bg
	Instance.new("UICorner", fill)
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
-- Pestañas
---------------------------------------------------------------------
local function tabResumen(b: Frame)
	local s = state
	UITheme.Text(b, string.format("Gremio %s", tostring(s.Faction)), 18, theme.Primary, UDim2.fromOffset(8, 4), UDim2.fromOffset(400, 24))
	local t = UITheme.Text(b, "Todos los jugadores de tu facción forman parte. Las bendiciones se financian con aportes y valen para todos, en todos los servidores.", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(8, 30), UDim2.fromOffset(500, 34))
	t.TextWrapped = true
	t.TextYAlignment = Enum.TextYAlignment.Top
	local function stat(y: number, label: string, value: string)
		UITheme.Text(b, label, 13, Color3.fromRGB(190, 190, 205), UDim2.fromOffset(8, y), UDim2.fromOffset(240, 18))
		UITheme.Text(b, value, 14, Color3.new(1, 1, 1), UDim2.fromOffset(250, y), UDim2.fromOffset(250, 18), Enum.TextXAlignment.Right)
	end
	stat(76, "Nivel del gremio (suma de bendiciones)", string.format("%d / %d", s.TotalLevels, s.MaxTotal))
	bar(b, UDim2.fromOffset(8, 98), UDim2.fromOffset(492, 8), s.TotalLevels / math.max(s.MaxTotal, 1), theme.Primary)
	stat(116, "Miembros conectados (tu facción)", tostring(s.Online))
	stat(138, "Tu aporte esta semana", withDots(s.MineWeek) .. " PA")
	stat(160, "Tu aporte total", withDots(s.MineTotal) .. " PA")
	stat(182, "Tu límite de hoy", string.format("%s / %s PA", withDots(s.DailyUsed), withDots(s.DailyCap)))
	bar(b, UDim2.fromOffset(8, 204), UDim2.fromOffset(492, 8), s.DailyUsed / math.max(s.DailyCap, 1), Color3.fromRGB(255, 190, 80))
	UITheme.Text(b, "Bendiciones activas", 14, theme.Primary, UDim2.fromOffset(8, 226), UDim2.fromOffset(300, 20))
	local any = false
	for i, p in ipairs(s.Passives) do
		local def = GuildCatalog.ById[p.Id]
		local col = (i - 1) % 2
		local row = math.floor((i - 1) / 2)
		local txt = if p.Level > 0 then string.format("%s %s Nv.%d · %s", def.Icon, def.Name, p.Level, effectText(def, p.Level)) else string.format("%s %s · sin nivel todavía", def.Icon, def.Name)
		any = any or p.Level > 0
		UITheme.Text(b, txt, 12, if p.Level > 0 then Color3.new(1, 1, 1) else Color3.fromRGB(130, 130, 145), UDim2.fromOffset(8 + col * 250, 250 + row * 22), UDim2.fromOffset(246, 18))
	end
	local note = UITheme.Text(b, if s.Shared then "Los aportes se sincronizan con todos los servidores cada ~40 s." else "⚠ Sin DataStore (Studio): el gremio solo existe en este servidor.", 11, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(8, 330), UDim2.fromOffset(500, 16))
	note.TextWrapped = true
	UITheme.Text(b, "PA = puntos de aporte: 1 oro = 1 PA; los materiales valen más según su rareza.", 11, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(8, 348), UDim2.fromOffset(500, 16))
end

local function tabBendiciones(b: Frame)
	local s = state
	-- lista izquierda
	for i, p in ipairs(s.Passives) do
		local def = GuildCatalog.ById[p.Id]
		local y = 4 + (i - 1) * 54
		local isSel = p.Id == selected
		local row = Instance.new("TextButton")
		row.Position = UDim2.fromOffset(4, y)
		row.Size = UDim2.fromOffset(236, 50)
		row.BackgroundColor3 = if isSel then Color3.fromRGB(34, 34, 48) else Color3.fromRGB(22, 22, 30)
		row.Text = ""
		row.AutoButtonColor = false
		row.ZIndex = 20
		row.Parent = b
		Instance.new("UICorner", row)
		local st = Instance.new("UIStroke")
		st.Color = if isSel then def.Color else Color3.fromRGB(60, 60, 75)
		st.Thickness = if isSel then 2 else 1
		st.Parent = row
		UITheme.Text(row, string.format("%s %s", def.Icon, def.Name), 14, Color3.new(1, 1, 1), UDim2.fromOffset(8, 3), UDim2.fromOffset(150, 18))
		UITheme.Text(row, string.format("Nv. %d/%d", p.Level, GuildCatalog.MAX_LEVEL), 12, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(150, 4), UDim2.fromOffset(80, 16), Enum.TextXAlignment.Right)
		bar(row, UDim2.fromOffset(8, 28), UDim2.fromOffset(220, 7), if p.Need > 0 then p.Progress / p.Need else 1, def.Color)
		UITheme.Text(row, if p.Need > 0 then string.format("%s / %s", short(p.Progress), short(p.Need)) else "MÁXIMO", 10, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(8, 35), UDim2.fromOffset(220, 12))
		row.Activated:Connect(function()
			selected = p.Id
			build()
		end)
	end
	-- panel derecho
	local p = passiveInfo(selected)
	local def = GuildCatalog.ById[selected]
	if not p or not def then
		return
	end
	local x = 252
	UITheme.Text(b, string.format("%s %s", def.Icon, def.Name), 18, def.Color, UDim2.fromOffset(x, 2), UDim2.fromOffset(240, 24))
	UITheme.Text(b, def.Desc, 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(x, 26), UDim2.fromOffset(240, 16))
	UITheme.Text(b, "Ahora: " .. (if p.Level > 0 then effectText(def, p.Level) else "—"), 12, Color3.fromRGB(165, 220, 175), UDim2.fromOffset(x, 46), UDim2.fromOffset(240, 16))
	if p.Level < GuildCatalog.MAX_LEVEL then
		UITheme.Text(b, "Siguiente: " .. effectText(def, p.Level + 1), 12, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(x, 64), UDim2.fromOffset(240, 16))
		UITheme.Text(b, string.format("Faltan %s PA para el nivel %d", withDots(p.Need - p.Progress), p.Level + 1), 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(x, 82), UDim2.fromOffset(240, 14))
	else
		UITheme.Text(b, "Bendición al máximo", 12, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(x, 64), UDim2.fromOffset(240, 16))
		return
	end
	local left = math.max(0, s.DailyCap - s.DailyUsed)
	UITheme.Text(b, string.format("Tu límite de hoy: quedan %s PA", withDots(left)), 11, Color3.fromRGB(255, 190, 80), UDim2.fromOffset(x, 102), UDim2.fromOffset(240, 14))
	UITheme.Text(b, string.format("Oro (tienes %s)", withDots(s.Gold)), 12, Color3.new(1, 1, 1), UDim2.fromOffset(x, 122), UDim2.fromOffset(240, 16))
	local amounts = { 1000, 10000, 100000 }
	for i, a in ipairs(amounts) do
		button(b, "+" .. short(a), UDim2.fromOffset(x + (i - 1) * 80, 140), UDim2.fromOffset(74, 26), Color3.fromRGB(170, 130, 40), function()
			donate("Gold", a)
		end)
	end
	UITheme.Text(b, "Materiales", 12, Color3.new(1, 1, 1), UDim2.fromOffset(x, 174), UDim2.fromOffset(240, 16))
	if #s.Mats == 0 then
		UITheme.Text(b, "No tienes materiales aportables.", 11, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(x, 194), UDim2.fromOffset(240, 14))
	end
	for i, m in ipairs(s.Mats) do
		if i > 5 then
			break
		end
		local y = 192 + (i - 1) * 30
		UITheme.Text(b, string.format("%s x%d", m.Name, m.Have), 11, Color3.new(1, 1, 1), UDim2.fromOffset(x, y), UDim2.fromOffset(118, 14))
		UITheme.Text(b, string.format("%d PA c/u", m.PA), 10, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(x, y + 13), UDim2.fromOffset(118, 12))
		button(b, "+1", UDim2.fromOffset(x + 120, y), UDim2.fromOffset(34, 24), Color3.fromRGB(50, 110, 160), function()
			donate(m.Id, 1)
		end)
		button(b, "+10", UDim2.fromOffset(x + 158, y), UDim2.fromOffset(38, 24), Color3.fromRGB(50, 110, 160), function()
			donate(m.Id, 10)
		end)
		button(b, "Todo", UDim2.fromOffset(x + 200, y), UDim2.fromOffset(40, 24), Color3.fromRGB(50, 130, 70), function()
			donate(m.Id, m.Have)
		end)
	end
end

local function tabRanking(b: Frame)
	button(b, "Semana", UDim2.fromOffset(8, 2), UDim2.fromOffset(90, 26), if rankWeekly then Color3.fromRGB(70, 110, 180) else Color3.fromRGB(45, 45, 60), function()
		rankWeekly = true
		build()
	end)
	button(b, "Total", UDim2.fromOffset(104, 2), UDim2.fromOffset(90, 26), if not rankWeekly then Color3.fromRGB(70, 110, 180) else Color3.fromRGB(45, 45, 60), function()
		rankWeekly = false
		build()
	end)
	UITheme.Text(b, if rankWeekly then "Se reinicia cada semana (lunes UTC)" else "Desde que existe el gremio", 11, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(210, 8), UDim2.fromOffset(290, 16), Enum.TextXAlignment.Right)
	local list = if rankWeekly then state.Top else state.TopAll
	if #list == 0 then
		UITheme.Text(b, "Aún nadie ha aportado. ¡Sé el primero!", 13, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(8, 50), UDim2.fromOffset(400, 20))
	end
	for i, r in ipairs(list) do
		local y = 36 + (i - 1) * 30
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(4, y)
		row.Size = UDim2.fromOffset(496, 26)
		row.BackgroundColor3 = if r.Mine then Color3.fromRGB(40, 50, 70) else Color3.fromRGB(22, 22, 30)
		row.BorderSizePixel = 0
		row.Parent = b
		Instance.new("UICorner", row)
		local medal = if i == 1 then "🥇" elseif i == 2 then "🥈" elseif i == 3 then "🥉" else tostring(i) .. "."
		UITheme.Text(row, medal, 13, Color3.new(1, 1, 1), UDim2.fromOffset(8, 4), UDim2.fromOffset(36, 18))
		UITheme.Text(row, tostring(r.Name), 13, if r.Mine then Color3.fromRGB(255, 214, 90) else Color3.new(1, 1, 1), UDim2.fromOffset(48, 4), UDim2.fromOffset(280, 18))
		UITheme.Text(row, withDots(r.Value) .. " PA", 13, Color3.fromRGB(150, 220, 255), UDim2.fromOffset(300, 4), UDim2.fromOffset(190, 18), Enum.TextXAlignment.Right)
	end
end

local function tabRegistro(b: Frame)
	if #state.Log == 0 then
		UITheme.Text(b, "Todavía no hay actividad. Los aportes grandes y las subidas de nivel aparecen aquí.", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(8, 6), UDim2.fromOffset(490, 34)).TextWrapped = true
		return
	end
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 5
	scroll.CanvasSize = UDim2.fromOffset(0, #state.Log * 30)
	scroll.Parent = b
	for i, e in ipairs(state.Log) do
		local ago = math.max(0, (state.Now or 0) - e.t)
		local when = if ago < 3600 then string.format("hace %d min", math.floor(ago / 60)) elseif ago < 86400 then string.format("hace %d h", math.floor(ago / 3600)) else string.format("hace %d d", math.floor(ago / 86400))
		local l = UITheme.Text(scroll, string.format("%s  ·  %s", tostring(e.m), when), 12, Color3.fromRGB(220, 220, 232), UDim2.fromOffset(6, (i - 1) * 30), UDim2.fromOffset(480, 26))
		l.TextWrapped = true
	end
end

---------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------
build = function()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	local w = UITheme.Frame(gui, theme, UDim2.fromOffset(540, 520), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	win = w
	WindowDrag.Attach(w, "Guild", 52, 50)
	UITheme.Text(w, "Gremio de Facción", 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(340, 26))
	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.ZIndex = 30
	close.Parent = w
	close.Activated:Connect(function()
		gui.Enabled = false
	end)
	for i, name in ipairs(TABS) do
		button(w, name, UDim2.fromOffset(18 + (i - 1) * 126, 38), UDim2.fromOffset(120, 28), if tab == name then theme.Primary else Color3.fromRGB(45, 45, 60), function()
			tab = name
			build()
		end)
	end
	if not state then
		UITheme.Text(w, "Cargando… (elige una facción para unirte al gremio)", 13, Color3.new(1, 1, 1), UDim2.fromOffset(18, 80), UDim2.fromOffset(480, 20))
		return
	end
	local b = Instance.new("Frame")
	b.Position = UDim2.fromOffset(18, 76)
	b.Size = UDim2.fromOffset(504, 366)
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
	resultLabel = UITheme.Text(w, "", 13, nil, UDim2.fromOffset(18, 450), UDim2.fromOffset(504, 20))
	resultLabel.RichText = true
	local f = UITheme.Text(w, "Límite diario por jugador: " .. withDots(GuildCatalog.DailyCap(player:GetAttribute("Level") :: any or 1)) .. " PA · las bendiciones suben con el esfuerzo de toda la facción.", 11, Color3.fromRGB(140, 140, 155), UDim2.fromOffset(18, 478), UDim2.fromOffset(504, 30))
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
	if not processed and input.KeyCode == Enum.KeyCode.G then
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
