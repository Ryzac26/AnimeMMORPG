--!strict
--[[
    DungeonPanelClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DungeonPanelClient
    Ventana "CUEVAS" (botón "Cuevas" del menú; evento de MenuBus "Dungeons"): las 4 franjas con su nivel mínimo, las entradas que te quedan hoy
    (x de N), cuenta atrás hasta que se renuevan, el estado de cada una (Disponible / Te falta nivel / Sin entradas / Cueva abierta) y,
    si tienes una cueva abierta, en qué franja y cuánto falta para que se cierre. Abajo, un resumen de cómo funciona el grupo.
    Todos los datos los publica DungeonService como atributos (Workspace: DungeonPerDay_n, DungeonMinLevel_n, DungeonMaxGroup, ... ;
    Jugador: DungeonLeft_n, DungeonFree, DungeonCave, DungeonCaveEnd, Level). Aquí no hay ningún número copiado del servidor.
    La ventana se adapta sola a celular (MobileClient escala toda ventana llamada "Ventana"). IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

local STRIPS = 4
local WIN_W = 640
local ROW_W = WIN_W - 28
local GREEN = Color3.fromRGB(70, 185, 105)
local RED = Color3.fromRGB(200, 75, 70)
local ORANGE = Color3.fromRGB(225, 150, 55)
local BLUE = Color3.fromRGB(90, 150, 235)
local GRAY = Color3.fromRGB(130, 130, 145)
local FALLBACK_MIN_LEVEL = { 1, 751, 1501, 2251 } -- solo por si el servidor todavía no publicó los datos

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonPanelGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 13
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local resetLabel: TextLabel? = nil
local caveLabel: TextLabel? = nil
local lastRemain = 0

---------------------------------------------------------------------
-- LECTURA DE DATOS
---------------------------------------------------------------------
local function wsNumber(name: string, default: number): number
	local v = Workspace:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function perDay(strip: number): number
	return math.floor(wsNumber("DungeonPerDay_" .. strip, 3))
end

local function minLevel(strip: number): number
	return math.floor(wsNumber("DungeonMinLevel_" .. strip, FALLBACK_MIN_LEVEL[strip] or 1))
end

local function entriesLeft(strip: number): number? -- nil = el perfil todavía no cargó
	local v = player:GetAttribute("DungeonLeft_" .. strip)
	return if typeof(v) == "number" then v else nil
end

local function myLevel(): number
	local v = player:GetAttribute("Level")
	return if typeof(v) == "number" then v else 1
end

local function secondsToReset(): number
	local shifted = Workspace:GetServerTimeNow() + wsNumber("DungeonResetOffset", 0) * 3600
	return (math.floor(shifted / 86400) + 1) * 86400 - shifted
end

local function caveStrip(): number?
	local v = player:GetAttribute("DungeonCave")
	return if typeof(v) == "number" then v else nil
end

local function caveSecondsLeft(): number
	local v = player:GetAttribute("DungeonCaveEnd")
	return if typeof(v) == "number" then math.max(0, v - Workspace:GetServerTimeNow()) else 0
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	local s = sec % 60
	return if h > 0 then string.format("%d:%02d:%02d", h, m, s) else string.format("%02d:%02d", m, s)
end

local function pct(x: number): string
	return string.format("%d %%", math.floor(x * 100 + 0.5))
end

-- texto y color del estado de una franja
local function statusOf(strip: number, free: boolean): (string, Color3)
	if Workspace:GetAttribute("DungeonOpen") == false then
		return "Próximamente", GRAY
	end
	if caveStrip() == strip then
		return "Cueva abierta", BLUE
	end
	local left = entriesLeft(strip)
	if left == nil then
		return "Cargando…", GRAY
	end
	if free then
		return "Disponible (prueba)", GREEN
	end
	if myLevel() < minLevel(strip) then
		return string.format("Te falta nivel (%d)", minLevel(strip)), ORANGE
	end
	if left <= 0 then
		return "Sin entradas hoy", RED
	end
	return "Disponible", GREEN
end

---------------------------------------------------------------------
-- VENTANA
---------------------------------------------------------------------
local function text(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

local function build()
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	if win then
		win:Destroy()
	end
	resetLabel, caveLabel = nil, nil

	local free = player:GetAttribute("DungeonFree") == true
	local level = myLevel()
	local inCave = caveStrip()
	local current = 1 -- tu franja = la más alta cuyo nivel mínimo ya cumples
	for s = 1, STRIPS do
		if level >= minLevel(s) then
			current = s
		end
	end

	-- alto de la ventana según tenga o no el aviso de cueva abierta
	local y0 = 80
	local bannerH = if inCave then 56 else 0
	local rowsY = y0 + 28 + bannerH
	local rowH, rowGap = 74, 6
	local footerY = rowsY + STRIPS * (rowH + rowGap) + 2
	local footerH = 128
	local winH = footerY + footerH + 18

	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WIN_W, winH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5),
		"Cuevas", "Entradas de hoy · se renuevan todos los días", "🕳️", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Dungeons", 40, 50)

	-- línea superior: cuenta atrás y nivel
	resetLabel = text(w, "", 14, pal.FText, UDim2.fromOffset(18, y0), UDim2.fromOffset(400, 20))
	text(w, string.format("Tu nivel: %d", level), 14, pal.FText, UDim2.fromOffset(WIN_W - 218, y0), UDim2.fromOffset(200, 20), Enum.TextXAlignment.Right)

	-- aviso de cueva abierta
	if inCave then
		local b = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, bannerH - 6), UDim2.fromOffset(14, y0 + 26), "inset")
		caveLabel = text(b, "", 14, pal.Text, UDim2.fromOffset(14, 6), UDim2.fromOffset(ROW_W - 28, 20))
		text(b, "Vuelve por el portal de esa franja: no gasta otra entrada.", 12, pal.Muted, UDim2.fromOffset(14, 28), UDim2.fromOffset(ROW_W - 28, 18))
	end

	-- una tarjeta por franja
	for strip = 1, STRIPS do
		local y = rowsY + (strip - 1) * (rowH + rowGap)
		local row = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, rowH), UDim2.fromOffset(14, y), "card")
		local need = minLevel(strip)
		local okLevel = free or level >= need
		local isCurrent = strip == current
		text(row, string.format("Franja %d", strip), 18, if isCurrent then pal.Accent else pal.Text, UDim2.fromOffset(16, 8), UDim2.fromOffset(140, 24))
		local needText = if need > 1 then string.format("Nivel %d+", need) else "Desde el nivel 1"
		text(row, needText, 12, if okLevel then GREEN else ORANGE, UDim2.fromOffset(16, 34), UDim2.fromOffset(140, 16))
		if isCurrent then
			text(row, "★ tu franja", 11, pal.Muted, UDim2.fromOffset(16, 51), UDim2.fromOffset(140, 14))
		end

		-- entradas: círculos llenos = te quedan, vacíos = ya usadas
		local total = perDay(strip)
		local left = entriesLeft(strip)
		if free then
			text(row, "∞  Entradas libres (modo prueba)", 13, pal.Text, UDim2.fromOffset(180, 24), UDim2.fromOffset(260, 20))
		elseif left == nil then
			text(row, "Cargando tus entradas…", 13, pal.Muted, UDim2.fromOffset(180, 24), UDim2.fromOffset(260, 20))
		else
			local shown = math.min(total, 10)
			for i = 1, shown do
				local pip = Instance.new("Frame")
				pip.Position = UDim2.fromOffset(180 + (i - 1) * 26, 14)
				pip.Size = UDim2.fromOffset(20, 20)
				pip.BackgroundColor3 = if i <= left then pal.Accent else pal.Inset
				pip.BorderSizePixel = 0
				pip.Parent = row
				Instance.new("UICorner", pip).CornerRadius = UDim.new(1, 0)
				local ps = Instance.new("UIStroke")
				ps.Color = pal.Edge2
				ps.Thickness = 1
				ps.Parent = pip
			end
			local leftText = string.format("Te quedan %d de %d hoy", math.min(left, total), total)
			text(row, leftText, 12, if left > 0 then pal.Text else pal.Muted, UDim2.fromOffset(180, 42), UDim2.fromOffset(260, 16))
		end

		local label, color = statusOf(strip, free)
		NpcKit.Chip(row, label, color, UDim2.new(1, -196, 0, 24), UDim2.fromOffset(180, 26))
	end

	-- cómo funciona
	local f = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, footerH), UDim2.fromOffset(14, footerY), "inset")
	text(f, "CÓMO FUNCIONA", 13, pal.Accent, UDim2.fromOffset(14, 8), UDim2.fromOffset(300, 18))
	local maxGroup = math.floor(wsNumber("DungeonMaxGroup", 5))
	local hpX, dmgX = pct(wsNumber("DungeonHpExtra", 0.3)), pct(wsNumber("DungeonDmgExtra", 0.12))
	local xpX, rwX = pct(wsNumber("DungeonXpExtra", 0.6)), pct(wsNumber("DungeonRewardExtra", 0.15))
	local lines = table.concat({
		string.format("• Entras solo o en grupo: hasta %d jugadores del mismo grupo, cerca del portal de cueva de la franja.", maxGroup),
		"• Cada integrante gasta una entrada de su contador. Si vuelves a tu cueva abierta, no gasta otra.",
		string.format("• Por cada jugador extra: +%s vida y +%s daño de los monstruos, +%s XP y +%s de premios.", hpX, dmgX, xpX, rwX),
		"• Las entradas se renuevan a la vez para todos (cuenta atrás arriba).",
	}, "\n")
	local body = text(f, lines, 12, pal.Muted, UDim2.fromOffset(14, 30), UDim2.fromOffset(ROW_W - 28, footerH - 38))
	body.TextWrapped = true
	body.TextYAlignment = Enum.TextYAlignment.Top
end

-- actualiza solo las cuentas atrás (cada segundo mientras la ventana está abierta)
local function tick()
	local remain = secondsToReset()
	if resetLabel then
		resetLabel.Text = "Las entradas se renuevan en  " .. clock(remain)
	end
	if caveLabel then
		local s = caveStrip()
		caveLabel.Text = if s then string.format("🕳️ Cueva abierta en la Franja %d · se cierra en %s", s, clock(caveSecondsLeft())) else ""
	end
	if remain > lastRemain + 60 and lastRemain > 0 then
		-- cruzó la hora de reinicio: se reconstruye (el servidor renueva los contadores enseguida)
		lastRemain = remain
		task.delay(2, function()
			if gui.Enabled then
				build()
				tick()
			end
		end)
		return
	end
	lastRemain = remain
end

local pending = false
local function requestRefresh()
	if pending or not gui.Enabled then
		return
	end
	pending = true
	task.defer(function()
		pending = false
		if gui.Enabled then
			build()
			tick()
		end
	end)
end

player.AttributeChanged:Connect(function(attr: string)
	if attr == "Level" or attr == "Faction" or (string.find(attr, "^Dungeon") ~= nil and attr ~= "DungeonCaveEnd") then
		requestRefresh()
	end
end)
Workspace.AttributeChanged:Connect(function(attr: string)
	if string.find(attr, "^Dungeon") ~= nil then
		requestRefresh()
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name == "Dungeons" then
		if gui.Enabled then
			gui.Enabled = false
		else
			build()
			lastRemain = 0
			tick()
			gui.Enabled = true
		end
	end
end)

task.spawn(function()
	while gui.Parent do
		task.wait(1)
		if gui.Enabled then
			tick()
		end
	end
end)

print("[DungeonPanelClient] listo")
