--!strict
--[[
    MissionClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MissionClient
    Ventana del NPC del Pabellón VIP (Mayordomo Imperial): MISIONES diarias y semanales (gratis y VIP por igual) y MARCOS de perfil.
    Datos: MissionState / MissionOpen / MissionAction (MissionService). IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local MissionCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MissionCatalog"))

local openRemote = ClientNet.Get("MissionOpen")
local stateRemote = ClientNet.Get("MissionState")
local actionRemote = ClientNet.Get("MissionAction")

local gui = Instance.new("ScreenGui")
gui.Name = "MissionGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 13
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local state: any = nil
local tab = "Misiones"
local viewLog = false -- true = "Diario" abierto desde el botón Misiones del menú (solo las aceptadas)

local function text(parent: Instance, t: string, size: number, color: Color3, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, t, size, color, pos, dim, align)
	l.TextStrokeTransparency = 1
	return l
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d = sec // 86400
	local h = (sec % 86400) // 3600
	local m = (sec % 3600) // 60
	return if d > 0 then string.format("%d d %d h", d, h) else string.format("%d h %d min", h, m)
end

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local function build()
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	if win then
		win:Destroy()
	end
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(780, 620), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5),
		if viewLog then "Diario de misiones" else "Pabellón Imperial",
		if viewLog then "Las misiones que aceptaste · se aceptan con el Mayordomo Imperial del Pabellón VIP" else "Acepta las misiones que quieras · el Pabellón privado es el pase VIP", "📜", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Missions", 40, 50)
	if viewLog then
		tab = "Misiones"
	end
	for i, t in ipairs(if viewLog then {} else { { "Misiones", "📜 Misiones" }, { "Marcos", "🖼 Marcos" }, { "Tienda", "🛍 Tienda VIP del Mes" }, { "Titulos", "🏷 Títulos" } }) do
		NpcKit.Tab(w, theme, t[2], UDim2.fromOffset(if i == 3 then 200 else 150, 28), UDim2.fromOffset(({ 14, 170, 326, 532 })[i], 72), tab == t[1], function()
			if t[1] == "Tienda" then
				gui.Enabled = false
				MenuBus.Fire("VipShop")
				return
			elseif t[1] == "Titulos" then
				gui.Enabled = false
				MenuBus.Fire("Titles")
				return
			end
			tab = t[1]
			build()
		end)
	end
	local top = if viewLog then 80 else 110
	if not state then
		text(w, "Cargando…", 14, pal.FText, UDim2.fromOffset(18, top), UDim2.fromOffset(300, 20))
		return
	end
	if tab == "Misiones" then
		local y = top
		local shown = 0
		if not viewLog then
			local pending = false
			for _, src in ipairs({ state.Daily, state.Weekly }) do
				for _, m in ipairs(src) do
					if not m.Accepted and not m.Claimed then
						pending = true
					end
				end
			end
			if pending then
				NpcKit.Button(w, theme, "Aceptar todas", UDim2.fromOffset(150, 28), UDim2.fromOffset(616, 72), "buy", function()
					actionRemote:FireServer("Accept", "ALL")
				end)
			end
		end
		local function section(title: string, reset: string, list: { any })
			local any = false
			for _, m in ipairs(list) do
				if not viewLog or m.Accepted then
					any = true
				end
			end
			if not any then
				return
			end
			text(w, title, 14, pal.FText, UDim2.fromOffset(18, y), UDim2.fromOffset(300, 18))
			text(w, reset, 12, pal.FMuted, UDim2.fromOffset(420, y), UDim2.fromOffset(340, 18), Enum.TextXAlignment.Right)
			y += 24
			for _, m in ipairs(list) do
				if viewLog and not m.Accepted then
					continue
				end
				shown += 1
				local row = NpcKit.Panel(w, theme, UDim2.fromOffset(748, 62), UDim2.fromOffset(14, y), "card")
				local tier = MissionCatalog.Tiers[tostring(m.Tier)]
				if tier then
					text(row, "[" .. tier.Name .. "]", 12, tier.Color, UDim2.fromOffset(12, 7), UDim2.fromOffset(62, 18))
				end
				text(row, tostring(m.Text), 14, pal.Text, UDim2.fromOffset(if tier then 76 else 12, 6), UDim2.fromOffset(if tier then 456 else 520, 20))
				text(row, string.format("%s / %s", thousands(m.P), thousands(m.Goal)), 12, pal.Muted, UDim2.fromOffset(12, 36), UDim2.fromOffset(160, 18))
				local bar = Instance.new("Frame")
				bar.Position = UDim2.fromOffset(120, 41)
				bar.Size = UDim2.fromOffset(300, 8)
				bar.BackgroundColor3 = pal.Inset
				bar.BorderSizePixel = 0
				bar.Parent = row
				Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
				local fill = Instance.new("Frame")
				fill.Size = UDim2.fromScale(math.clamp(m.P / math.max(m.Goal, 1), 0, 1), 1)
				fill.BackgroundColor3 = pal.Accent
				fill.BorderSizePixel = 0
				fill.Parent = bar
				Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
				text(row, "+" .. thousands(m.Gold) .. " oro", 13, Color3.fromRGB(240, 190, 70), UDim2.fromOffset(440, 34), UDim2.fromOffset(150, 20))
				local done = m.P >= m.Goal
				local label = if m.Claimed then "✔ Reclamada" elseif not m.Accepted then "Aceptar" elseif done then "Reclamar" else "En curso"
				NpcKit.Button(row, theme, label, UDim2.fromOffset(130, 34), UDim2.fromOffset(606, 14), if (not m.Accepted and not m.Claimed) or (done and not m.Claimed) then "buy" else "neutral", function()
					if m.Claimed then
						return
					elseif not m.Accepted then
						actionRemote:FireServer("Accept", m.Id)
					elseif done then
						actionRemote:FireServer("Claim", m.Id)
					end
				end)
				y += 68
			end
			y += 6
		end
		section("MISIONES DE HOY" .. (if state.BonusDone then "  ✔ bono del día cobrado" else "  · completa todas = bono x2 + 1 misión extra"), "Se renuevan en " .. clock(state.DailyReset), state.Daily)
		section("MISIONES DE LA SEMANA", "Se renuevan en " .. clock(state.WeeklyReset), state.Weekly)
		if viewLog and shown == 0 then
			local e = text(w, "No tienes misiones activas.\nHabla con el Mayordomo Imperial del Pabellón VIP de tu ciudad y acepta las que quieras: aparecerán aquí con su progreso.", 15, pal.FMuted, UDim2.fromOffset(40, 200), UDim2.fromOffset(700, 100), Enum.TextXAlignment.Center)
			e.TextWrapped = true
		end
		text(w, string.format("Misiones completadas: %d · los marcos se desbloquean con ellas", state.Total), 12, pal.FMuted, UDim2.fromOffset(18, 586), UDim2.fromOffset(740, 18))
	else
		text(w, string.format("Misiones completadas: %d. Los marcos rodean tu retrato. Son iguales para todos los jugadores.", state.Total), 13, pal.FMuted, UDim2.fromOffset(18, top), UDim2.fromOffset(740, 18))
		local y = top + 28
		local function row(name: string, need: number, color: Color3?, id: string, passive: any?)
			local unlocked = state.Total >= need
			local equipped = (state.Frame or "") == id
			local r = NpcKit.Panel(w, theme, UDim2.fromOffset(748, 60), UDim2.fromOffset(14, y), "card")
			local sw = Instance.new("Frame")
			sw.Position = UDim2.fromOffset(12, 8)
			sw.Size = UDim2.fromOffset(44, 44)
			sw.BackgroundColor3 = pal.Inset
			sw.BorderSizePixel = 0
			sw.Parent = r
			Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 8)
			if color then
				local st = Instance.new("UIStroke")
				st.Color = color
				st.Thickness = 3.5
				st.Parent = sw
			end
			text(r, name, 15, if unlocked then pal.Text else pal.Muted, UDim2.fromOffset(72, 8), UDim2.fromOffset(480, 20))
			local sub = if need == 0 then "Sin marco" else (if unlocked then "Desbloqueado" else string.format("Faltan %d misiones", need - state.Total))
			if passive then
				sub ..= " · ✨ " .. passive.Name .. ": " .. passive.Text
			end
			text(r, sub, 12, if passive then Color3.fromRGB(240, 190, 70) else pal.Muted, UDim2.fromOffset(72, 32), UDim2.fromOffset(490, 18))
			NpcKit.Button(r, theme, if equipped then "✔ Equipado" elseif unlocked then "Equipar" else "🔒 " .. need .. " misiones", UDim2.fromOffset(170, 34), UDim2.fromOffset(566, 13), if unlocked and not equipped then "buy" else "neutral", function()
				if unlocked and not equipped then
					actionRemote:FireServer("Frame", id)
				end
			end)
			y += 66
		end
		row("Sin marco", 0, nil, "")
		for _, f in ipairs(MissionCatalog.Frames) do
			row(f.Name, f.Need, f.Color, f.Id, f.Passive)
		end
	end
end

MenuBus.Event:Connect(function(name: string)
	if name == "Quests" then
		if gui.Enabled and viewLog then
			gui.Enabled = false
			return
		end
		viewLog = true
		actionRemote:FireServer("State")
		build()
		gui.Enabled = true
	end
end)

if openRemote then
	openRemote.OnClientEvent:Connect(function()
		viewLog = false
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
print("[MissionClient] listo")
