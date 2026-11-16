--!strict
--[[
    AfkClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AfkClient
    Interfaz del CAMPO DE ENTRENAMIENTO (zona de farmeo AFK; la lógica está en ServerScriptService/Services/AfkZoneService):
      1) VENTANA DEL PORTAL (se abre con el portal de la plaza de tu ciudad: tecla E / tocar): tu franja, XP y botín (%), tiempo que te queda hoy,
         cápsulas libres y los botones [Entrar solo] / [Entrar en grupo] (solo el líder) / [Unirse a mi grupo].
      2) INVITACIÓN DEL LÍDER (a cada miembro del grupo): [Entrar] [Salir del grupo] con cuenta atrás. Sin responder te quedas en el grupo y no entras.
      3) ESPERA DEL LÍDER: quién aceptó, quién salió del grupo, [Entrar ya] y [Cancelar].
      4) CHIP DENTRO DEL CAMPO: franja, XP/botín, bajas, tiempo que te queda hoy, [Auto-farm] y [Salir].
      5) Al llegar enciende el Auto-farm (modo Semi) y, mientras estás dentro, evita la expulsión por inactividad de Roblox (20 min sin tocar nada).
    Todos los números salen de atributos que publica el servidor (Workspace: AfkXpPct, AfkLootPct, AfkDaily; Jugador: InAfk, AfkLeft, AfkKills, AfkStart).
    Las ventanas se llaman "Ventana" (MobileClient las escala en el celular). Está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))

local gotRemote = ClientNet.Get("Afk")
if not gotRemote then
	warn("[AfkClient] no existe el remoto 'Afk': ¿está AfkZoneService en el servidor y requerido en GameServerMain?")
	return
end
local remote: RemoteEvent = gotRemote
local farmRemote: RemoteEvent? = ClientNet.Get("AutoFarm")

local GREEN = Color3.fromRGB(70, 185, 105)
local RED = Color3.fromRGB(215, 85, 78)
local ORANGE = Color3.fromRGB(225, 150, 55)
local BLUE = Color3.fromRGB(90, 150, 235)

local gui = Instance.new("ScreenGui")
gui.Name = "AfkGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------
local function wsNumber(name: string, default: number): number
	local v = Workspace:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	local s = sec % 60
	return if h > 0 then string.format("%d:%02d:%02d", h, m, s) else string.format("%02d:%02d", m, s)
end

local function hoursText(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d h %02d min", sec // 3600, (sec % 3600) // 60)
end

local function text(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

local function wrapped(l: TextLabel): TextLabel
	l.TextWrapped = true
	l.TextYAlignment = Enum.TextYAlignment.Top
	return l
end

local function inAfk(): boolean
	return player:GetAttribute("InAfk") ~= nil
end

-- segundos que te quedan hoy (entre avisos del servidor, que llegan cada 5 s, sigue corriendo solo mientras estás dentro)
local leftValue = 0
local leftAt = os.clock()
local function readLeft()
	local v = player:GetAttribute("AfkLeft")
	if typeof(v) == "number" then
		leftValue = v
		leftAt = os.clock()
	end
end
readLeft()
player:GetAttributeChangedSignal("AfkLeft"):Connect(readLeft)

local function currentLeft(): number
	if inAfk() then
		return math.max(0, leftValue - (os.clock() - leftAt))
	end
	return leftValue
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

---------------------------------------------------------------------
-- 1) VENTANA DEL PORTAL
---------------------------------------------------------------------
local portalWin: Frame? = nil
local portalBar: ((number, number, string?) -> ())? = nil
local portalDaily = 8 * 3600

local function closePortal()
	if portalWin then
		portalWin:Destroy()
		portalWin = nil
	end
	portalBar = nil
end

local function openPortal(info: any)
	closePortal()
	if typeof(info) ~= "table" then
		return
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W, H = 520, 410
	local ROW_W = W - 28
	local daily = if typeof(info.Daily) == "number" then info.Daily else wsNumber("AfkDaily", 8 * 3600)
	portalDaily = daily
	local left = if typeof(info.Left) == "number" then info.Left else 0
	leftValue, leftAt = left, os.clock()
	local party = if typeof(info.Party) == "number" then info.Party else 1
	local isLeader = info.IsLeader == true
	local maxGroup = if typeof(info.MaxGroup) == "number" then info.MaxGroup else 5

	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5),
		"Campo de Entrenamiento", tostring(info.Title or "Zona de farmeo AFK"), "🏕️", function()
			closePortal()
		end)
	portalWin = w
	WindowDrag.Attach(w, "Afk", 40, 50)

	-- resumen
	local y0 = 80
	local box = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, 104), UDim2.fromOffset(14, y0), "inset")
	text(box, string.format("Tu franja: %s   ·   Nivel %s", tostring(info.Tier or "?"), tostring(info.Level or "?")), 16, pal.Text, UDim2.fromOffset(14, 8), UDim2.fromOffset(ROW_W - 28, 22))
	text(box, string.format("XP al %s %%   ·   Botín al %s %%", tostring(info.XpPct or "?"), tostring(info.LootPct or "?")), 15, pal.Accent, UDim2.fromOffset(14, 34), UDim2.fromOffset(ROW_W - 28, 20))
	local note = text(box, "Entras a una cápsula cerrada con monstruos de tu franja. Se pelea sola con el Auto-farm. Sin PvP. Si no matas nada por 10 minutos, te saca.", 12, pal.Muted, UDim2.fromOffset(14, 58), UDim2.fromOffset(ROW_W - 28, 40))
	wrapped(note)

	-- tiempo de hoy
	local tbox = NpcKit.Panel(w, theme, UDim2.fromOffset(ROW_W, 70), UDim2.fromOffset(14, y0 + 112), "inset")
	text(tbox, "Tiempo disponible hoy", 13, pal.Accent, UDim2.fromOffset(14, 6), UDim2.fromOffset(240, 18))
	text(tbox, string.format("Cápsulas libres: %s", tostring(info.Free or 0)), 12, pal.Muted, UDim2.fromOffset(ROW_W - 214, 7), UDim2.fromOffset(200, 16), Enum.TextXAlignment.Right)
	local _, setBar = UITheme.Bar(tbox, UDim2.fromOffset(14, 32), UDim2.fromOffset(ROW_W - 28, 24), if left > 0 then GREEN else RED, "", 13, pal.Edge2)
	portalBar = setBar
	setBar(left, daily, string.format("%s de %s", hoursText(left), hoursText(daily)))

	-- grupo
	local groupText: string
	if party >= 2 then
		groupText = if isLeader
			then string.format("Eres el líder de un grupo de %d. Si entras en grupo, a los demás les sale una invitación (máx. %d).", party, maxGroup)
			else string.format("Estás en un grupo de %d. Entra solo el líder; si ya entraron, puedes unirte.", party)
	else
		groupText = "No tienes grupo: entra solo, o invita a alguien antes para entrar en grupo."
	end
	wrapped(text(w, groupText, 12, pal.Muted, UDim2.fromOffset(18, y0 + 190), UDim2.fromOffset(ROW_W - 8, 34)))

	-- botones
	local by = y0 + 232
	if left <= 0 then
		NpcKit.Chip(w, "Ya usaste tu tiempo de hoy: vuelve mañana", RED, UDim2.fromOffset(14, by + 4), UDim2.fromOffset(ROW_W, 30))
	else
		local bw = if party >= 2 then (ROW_W - 12) // 2 else ROW_W
		NpcKit.Button(w, theme, "Entrar solo", UDim2.fromOffset(bw, 44), UDim2.fromOffset(14, by), "action", function()
			remote:FireServer("Solo")
			closePortal()
		end)
		if party >= 2 then
			if isLeader then
				NpcKit.Button(w, theme, "Entrar en grupo", UDim2.fromOffset(bw, 44), UDim2.fromOffset(14 + bw + 12, by), "buy", function()
					remote:FireServer("Group")
					closePortal()
				end)
			elseif info.CanJoin == true then
				NpcKit.Button(w, theme, "Unirse a mi grupo", UDim2.fromOffset(bw, 44), UDim2.fromOffset(14 + bw + 12, by), "buy", function()
					remote:FireServer("Join")
					closePortal()
				end)
			else
				NpcKit.Chip(w, "El líder decide cuándo entrar", ORANGE, UDim2.fromOffset(14 + bw + 12, by + 7), UDim2.fromOffset(bw, 30))
			end
		end
	end
end

---------------------------------------------------------------------
-- 2) INVITACIÓN DEL LÍDER (miembros)
---------------------------------------------------------------------
local askWin: Frame? = nil
local askBar: ((number, number, string?) -> ())? = nil
local askDeadline = 0

local function closeAsk()
	if askWin then
		askWin:Destroy()
		askWin = nil
	end
	askBar = nil
end

local function showAsk(info: any)
	closeAsk()
	if typeof(info) ~= "table" then
		return
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W, H = 450, 270
	local ROW_W = W - 28
	askDeadline = if typeof(info.Deadline) == "number" then info.Deadline else serverNow() + wsNumber("AfkAsk", 20)
	local total = math.max(1, askDeadline - serverNow())
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.3), Vector2.new(0.5, 0.5),
		"Campo de Entrenamiento", "Invitación del líder", "⚔️", function()
			closeAsk() -- cerrar sin responder = te quedas en el grupo y no entras
		end)
	askWin = w
	local y0 = 82
	wrapped(text(w, string.format("★ %s quiere entrar al Campo de Entrenamiento.", tostring(info.Leader or "El líder")), 16, pal.Text, UDim2.fromOffset(18, y0), UDim2.fromOffset(ROW_W - 8, 44)))
	text(w, string.format("%s · Franja %s · XP al %d %% · Botín al %d %%", tostring(info.Title or "Campo"), tostring(info.Tier or "?"), wsNumber("AfkXpPct", 0), wsNumber("AfkLootPct", 0)), 12, pal.Muted, UDim2.fromOffset(18, y0 + 46), UDim2.fromOffset(ROW_W - 8, 18))
	local _, setBar = UITheme.Bar(w, UDim2.fromOffset(18, y0 + 72), UDim2.fromOffset(ROW_W - 8, 20), BLUE, "", 12, pal.Edge2)
	askBar = function(v: number, m: number, t: string?)
		setBar(v, m, t)
	end
	setBar(total, total, string.format("%d s para responder", math.ceil(total)))
	local bw = (ROW_W - 8 - 12) // 2
	NpcKit.Button(w, theme, "Entrar", UDim2.fromOffset(bw, 44), UDim2.fromOffset(18, y0 + 104), "buy", function()
		remote:FireServer("Answer", "yes")
		closeAsk()
	end)
	NpcKit.Button(w, theme, "Salir del grupo", UDim2.fromOffset(bw, 44), UDim2.fromOffset(18 + bw + 12, y0 + 104), "danger", function()
		remote:FireServer("Answer", "leave")
		closeAsk()
	end)
	text(w, "Si no respondes te quedas en el grupo, pero no entras.", 11, pal.Muted, UDim2.fromOffset(18, y0 + 156), UDim2.fromOffset(ROW_W - 8, 16))
end

---------------------------------------------------------------------
-- 3) ESPERA DEL LÍDER
---------------------------------------------------------------------
local waitWin: Frame? = nil
local waitLabel: TextLabel? = nil
local waitDeadline = 0

local function closeWait()
	if waitWin then
		waitWin:Destroy()
		waitWin = nil
	end
	waitLabel = nil
end

local STATE_TEXT: { [string]: { string } } = {
	wait = { "… pensando", "" },
	yes = { "✔ entra", "" },
	left = { "✘ salió del grupo", "" },
	stay = { "— no respondió", "" },
	busy = { "✘ no puede entrar ahora", "" },
}

local function showWait(info: any)
	if typeof(info) ~= "table" or typeof(info.Members) ~= "table" then
		return
	end
	closeWait()
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local members: { any } = info.Members
	local W = 450
	local ROW_W = W - 28
	local rowH = 26
	local H = 82 + #members * rowH + 8 + 28 + 14 + 44 + 18
	waitDeadline = if typeof(info.Deadline) == "number" then info.Deadline else serverNow()
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.3), Vector2.new(0.5, 0.5),
		"Campo de Entrenamiento", "Esperando a tu grupo", "👥", function()
			remote:FireServer("Cancel")
			closeWait()
		end)
	waitWin = w
	local y = 82
	for _, m in ipairs(members) do
		local st = if typeof(m.State) == "string" then m.State else "wait"
		local info2 = STATE_TEXT[st] or STATE_TEXT.wait
		local name = (if m.Leader == true then "★ " else "") .. tostring(m.Name)
		text(w, name, 14, pal.Text, UDim2.fromOffset(18, y), UDim2.fromOffset(240, rowH))
		local color = if st == "yes" then GREEN elseif st == "wait" then ORANGE else RED
		local label = if m.Leader == true then "✔ líder" else info2[1]
		text(w, label, 13, if m.Leader == true then GREEN else color, UDim2.fromOffset(W - 18 - 190, y), UDim2.fromOffset(190, rowH), Enum.TextXAlignment.Right)
		y += rowH
	end
	waitLabel = text(w, "", 12, pal.Muted, UDim2.fromOffset(18, y + 8), UDim2.fromOffset(ROW_W - 8, 20))
	local by = y + 8 + 28 + 6
	local bw = (ROW_W - 8 - 12) // 2
	NpcKit.Button(w, theme, "Entrar ya", UDim2.fromOffset(bw, 44), UDim2.fromOffset(18, by), "buy", function()
		remote:FireServer("Start")
	end)
	NpcKit.Button(w, theme, "Cancelar", UDim2.fromOffset(bw, 44), UDim2.fromOffset(18 + bw + 12, by), "neutral", function()
		remote:FireServer("Cancel")
		closeWait()
	end)
end

---------------------------------------------------------------------
-- 4) CHIP DENTRO DEL CAMPO
---------------------------------------------------------------------
local hud: Frame? = nil
local hudLine: TextLabel? = nil
local hudWarn: TextLabel? = nil
local hudFarmBtn: TextButton? = nil
local hudFarmText = ""

local function farmOn(): boolean
	return player:GetAttribute("AutoFarm") == true
end

local function destroyHud()
	if hud then
		hud:Destroy()
		hud = nil
	end
	hudLine, hudWarn, hudFarmBtn = nil, nil, nil
	hudFarmText = ""
end

local function buildHud()
	destroyHud()
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local W, H = 320, 112
	local f = NpcKit.Panel(gui, theme, UDim2.fromOffset(W, H), UDim2.new(0.5, -W // 2, 0, 66), "card")
	f.Name = "AfkHud"
	hud = f
	local tier = player:GetAttribute("InAfk")
	text(f, string.format("🏕️ CAMPO · Franja %s · XP %d %% · Botín %d %%", tostring(tier), wsNumber("AfkXpPct", 0), wsNumber("AfkLootPct", 0)), 12, pal.Accent, UDim2.fromOffset(12, 6), UDim2.fromOffset(W - 24, 16))
	hudLine = text(f, "", 12, pal.Text, UDim2.fromOffset(12, 24), UDim2.fromOffset(W - 24, 16))
	hudWarn = text(f, "", 11, RED, UDim2.fromOffset(12, 41), UDim2.fromOffset(W - 24, 14))
	local fb = NpcKit.Button(f, theme, "Auto-farm", UDim2.fromOffset(190, 36), UDim2.fromOffset(12, 62), "action", function()
		if farmRemote then
			farmRemote:FireServer("Set", not farmOn(), "Semi")
		end
	end)
	hudFarmBtn = fb
	NpcKit.Button(f, theme, "Salir", UDim2.fromOffset(W - 24 - 190 - 10, 36), UDim2.fromOffset(12 + 190 + 10, 62), "danger", function()
		remote:FireServer("Leave")
	end)
end

local function updateHud()
	local kills = player:GetAttribute("AfkKills")
	local start = player:GetAttribute("AfkStart")
	local inside = if typeof(start) == "number" then serverNow() - start else 0
	if hudLine then
		hudLine.Text = string.format("Bajas %d  ·  En el Campo %s  ·  Hoy quedan %s", if typeof(kills) == "number" then kills else 0, clock(inside), clock(currentLeft()))
	end
	local on = farmOn()
	if hudWarn then
		hudWarn.Text = if on then "" else "⚠ Auto-farm apagado: nadie pelea y la sesión se cierra sola"
	end
	if hudFarmBtn then
		local want = if on then "Auto-farm: ENCENDIDO" else "Auto-farm: APAGADO"
		if hudFarmText ~= want then
			hudFarmText = want
			hudFarmBtn.Text = want
		end
	end
end

-- al llegar al Campo: enciende el Auto-farm en modo Semi (los monstruos vienen a ti)
local arrival = 0
local function onEnter()
	arrival += 1
	local mine = arrival
	buildHud()
	updateHud()
	task.spawn(function()
		task.wait(1) -- deja que aparezca el atributo del traslado
		local t0 = os.clock()
		while mine == arrival and os.clock() - t0 < 15 and (player:GetAttribute("DungeonTransit") ~= nil or player:GetAttribute("DungeonCover") ~= nil) do
			task.wait(0.25)
		end
		task.wait(1.5)
		local farm = farmRemote
		if not farm then
			return
		end
		for _ = 1, 3 do
			if mine ~= arrival or not inAfk() or farmOn() then
				return
			end
			farm:FireServer("Set", true, "Semi")
			task.wait(2.5)
		end
	end)
end

local function onLeave()
	arrival += 1
	destroyHud()
end

player:GetAttributeChangedSignal("InAfk"):Connect(function()
	if inAfk() then
		closePortal()
		closeAsk()
		closeWait()
		onEnter()
	else
		onLeave()
	end
end)
if inAfk() then
	onEnter()
end

-- Roblox expulsa a los 20 min sin tocar nada: dentro del Campo se simula una pulsación cuando salta el aviso de inactividad
player.Idled:Connect(function()
	if inAfk() then
		pcall(function()
			local vu = game:GetService("VirtualUser")
			vu:CaptureController()
			vu:ClickButton2(Vector2.new())
		end)
	end
end)

---------------------------------------------------------------------
-- MENSAJES DEL SERVIDOR + RELOJ
---------------------------------------------------------------------
remote.OnClientEvent:Connect(function(action: any, payload: any)
	if action == "Open" then
		openPortal(payload)
	elseif action == "Ask" then
		showAsk(payload)
	elseif action == "AskClose" then
		closeAsk()
	elseif action == "Wait" then
		showWait(payload)
	elseif action == "WaitClose" then
		closeWait()
	elseif action == "Close" then
		closePortal()
	end
end)

task.spawn(function()
	while gui.Parent do
		task.wait(0.25)
		local pb = portalBar
		if pb then
			local left = currentLeft()
			pb(left, portalDaily, string.format("%s de %s", hoursText(left), hoursText(portalDaily)))
		end
		local ab = askBar
		if ab and askWin then
			local remain = askDeadline - serverNow()
			if remain <= 0 then
				closeAsk()
			else
				local total = math.max(1, wsNumber("AfkAsk", 20))
				ab(remain, total, string.format("%d s para responder", math.ceil(remain)))
			end
		end
		if waitLabel and waitWin then
			local remain = waitDeadline - serverNow()
			waitLabel.Text = if remain > 0 then string.format("Entran los que acepten en %d s, o toca «Entrar ya».", math.ceil(remain)) else "Entrando…"
		end
		if hud then
			updateHud()
		end
	end
end)

print("[AfkClient] listo")
