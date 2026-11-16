--!strict
--[[
    HuntClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HuntClient
    ANALIZADOR DE CAZA (botón "Analizador" del menú; evento de MenuBus "Hunt"). Ventana estilo Tibia con lo que ganas mientras matas monstruos:
    tiempo activo, bajas y bajas/min, XP ganada y XP/hora, niveles ganados, XP que falta y TIEMPO ESTIMADO para el siguiente nivel, ritmo frente al
    paquete de horas (para calibrar), oro y oro/hora, y la lista del botín. Los datos los cuenta el servidor (HuntStats); aquí solo se muestran.
    Se reinicia sola al entrar/salir del Campo de Entrenamiento (modo Campo/Mundo) y con el botón [Reiniciar].
    PARA ENVIARME LOS DATOS: abre la ventana, juega unos minutos y mándame una captura de pantalla.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local GB = require(ReplicatedStorage.Modules.GameBalance)
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))

local gotRemote = ClientNet.Get("Hunt")
if not gotRemote then
	warn("[HuntClient] no existe el remoto 'Hunt': ¿está HuntStats en el servidor (lo requieren RewardService y LootService)?")
	return
end
local remote: RemoteEvent = gotRemote

local WIN_W = 470
local ROW_W = WIN_W - 28
local SHOW_ITEMS = 10

local gui = Instance.new("ScreenGui")
gui.Name = "HuntGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 13
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui", 10)

---------------------------------------------------------------------
-- FORMATO
---------------------------------------------------------------------
local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s
	while true do
		local r, k = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1.%2")
		out = r
		if k == 0 then
			break
		end
	end
	return out
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function eta(hours: number): string
	if hours ~= hours or hours == math.huge then
		return "—"
	end
	local totalMin = hours * 60
	if totalMin < 1 then
		return "menos de 1 min"
	end
	if hours < 48 then
		return string.format("%d h %02d min", math.floor(hours), math.floor(totalMin % 60))
	end
	local days = hours / 24
	return string.format("%d d %d h", math.floor(days), math.floor(hours % 24))
end

---------------------------------------------------------------------
-- VENTANA
---------------------------------------------------------------------
local win: Frame? = nil
local valueLabels: { [string]: TextLabel } = {}
local lootLabel: TextLabel? = nil
local last: any = nil

local ROWS: { { string } } = {
	{ "Mode", "Modo" },
	{ "Time", "Tiempo activo" },
	{ "Kills", "Bajas" },
	{ "Xp", "XP ganada" },
	{ "XpH", "XP por hora" },
	{ "Level", "Nivel" },
	{ "Need", "Falta para el siguiente nivel" },
	{ "Eta", "Tiempo estimado" },
	{ "Pack", "Ritmo vs paquete de 1 h" },
	{ "Gold", "Oro" },
}

local function render()
	local s: any = last
	if not win or not s then
		return
	end
	local level = player:GetAttribute("Level")
	local xp = player:GetAttribute("XP")
	level = if typeof(level) == "number" then level else s.StartLevel
	xp = if typeof(xp) == "number" then xp else 0
	local active = if typeof(s.Active) == "number" then s.Active else 0
	local enough = active >= 10
	local xph = if enough then s.Xp / active * 3600 else 0
	local goldh = if enough then s.Gold / active * 3600 else 0
	local kpm = if enough then s.Kills / active * 60 else 0
	local v = valueLabels
	local modeText = if s.Mode == "Campo" then "Campo de Entrenamiento (AFK)" else "Mundo"
	v.Mode.Text = modeText
	v.Time.Text = string.format("%s  (total %s)", clock(active), clock(s.Total))
	v.Kills.Text = if enough then string.format("%s  ·  %.1f por minuto", fmt(s.Kills), kpm) else fmt(s.Kills)
	v.Xp.Text = fmt(s.Xp)
	v.XpH.Text = if enough then fmt(xph) else "—  (mata unos segundos)"
	local gained = level - s.StartLevel
	v.Level.Text = string.format("%s  (+%d desde el inicio)", fmt(level), math.max(gained, 0))
	if level >= GB.MAX_LEVEL then
		v.Need.Text = "nivel máximo"
		v.Eta.Text = "—"
	else
		local need = math.max(GB.XpToNext(level) - xp, 0)
		v.Need.Text = fmt(need) .. " XP"
		v.Eta.Text = if enough and xph > 0 then eta(need / xph) else "—"
	end
	local model = GB.KILLS_PER_HOUR * GB.MobXp(level) * GB.XpCalib(level)
	v.Pack.Text = if enough and model > 0 then string.format("%d %%  (incluye tus boosts)", math.floor(xph / model * 100 + 0.5)) else "—"
	v.Gold.Text = if enough then string.format("%s  ·  %s por hora", fmt(s.Gold), fmt(goldh)) else fmt(s.Gold)
	local lines: { string } = {}
	local items: { any } = if typeof(s.Items) == "table" then s.Items else {}
	for i = 1, math.min(#items, SHOW_ITEMS) do
		local it = items[i]
		table.insert(lines, string.format("%s%s", tostring(it.Name), if it.Count > 1 then "  x" .. fmt(it.Count) else ""))
	end
	local extra = math.max(#items - SHOW_ITEMS, 0) + (if typeof(s.More) == "number" then s.More else 0)
	if extra > 0 then
		table.insert(lines, string.format("… y %d más", extra))
	end
	if #lines == 0 then
		lines[1] = "(todavía sin botín)"
	end
	if lootLabel then
		lootLabel.Text = table.concat(lines, "\n")
	end
end

local function close()
	gui.Enabled = false
	remote:FireServer("Close")
end

local function build()
	if win then
		win:Destroy()
		win = nil
	end
	table.clear(valueLabels)
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local rowH = 22
	local lootH = (SHOW_ITEMS + 1) * 16 + 8
	local H = 80 + #ROWS * rowH + 14 + 22 + lootH + 12 + 44 + 34
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WIN_W, H), UDim2.new(0, 24, 0.5, 0), Vector2.new(0, 0.5),
		"Analizador de caza", "Lo que ganas mientras matas", "📊", close)
	win = w
	WindowDrag.Attach(w, "Hunt", 40, 50)
	local y = 80
	local box = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, #ROWS * rowH + 12), UDim2.fromOffset(14, y), "inset")
	for i, row in ipairs(ROWS) do
		local ry = 6 + (i - 1) * rowH
		UITheme.Text(box, row[2], 13, pal.Muted, UDim2.fromOffset(12, ry), UDim2.fromOffset(190, rowH))
		local val = UITheme.Text(box, "—", 14, pal.Text, UDim2.fromOffset(206, ry), UDim2.fromOffset(ROW_W - 218, rowH), Enum.TextXAlignment.Right)
		val.TextStrokeTransparency = 1
		valueLabels[row[1]] = val
	end
	y += #ROWS * rowH + 12 + 8
	UITheme.Text(w, "Botín conseguido", 14, pal.Accent, UDim2.fromOffset(18, y), UDim2.fromOffset(ROW_W, 22))
	y += 22
	local lbox = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, lootH), UDim2.fromOffset(14, y), "inset")
	local ll = UITheme.Text(lbox, "(todavía sin botín)", 12, pal.Text, UDim2.fromOffset(12, 6), UDim2.fromOffset(ROW_W - 24, lootH - 12))
	ll.TextWrapped = true
	ll.TextYAlignment = Enum.TextYAlignment.Top
	ll.TextStrokeTransparency = 1
	lootLabel = ll
	y += lootH + 10
	NpcKit.Button(w, theme, "Reiniciar", UDim2.fromOffset(150, 36), UDim2.fromOffset(14, y), "neutral", function()
		remote:FireServer("Reset")
	end)
	UITheme.Text(w, "Tómale una captura y mándala para ajustar el juego.", 11, pal.Muted, UDim2.fromOffset(172, y + 9), UDim2.fromOffset(ROW_W - 160, 18))
	render()
end

remote.OnClientEvent:Connect(function(action: any, payload: any)
	if action == "Snap" and typeof(payload) == "table" then
		last = payload
		render()
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name ~= "Hunt" then
		return
	end
	if gui.Enabled then
		close()
	else
		if not win then
			build()
		end
		gui.Enabled = true
		remote:FireServer("Open")
	end
end)

-- el nivel y la XP cambian entre envíos del servidor: se refresca el cálculo del siguiente nivel cada segundo
task.spawn(function()
	while gui.Parent do
		task.wait(1)
		if gui.Enabled then
			render()
		end
	end
end)

print("[HuntClient] listo")
