--!strict
--[[
    TalentClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TalentClient
    Ventana del ÁRBOL DE TALENTOS: 5 ramas (Defensa, Ofensiva, Soporte, Utilidad, Ascendencia), 3 builds en pestañas
    (la 1 gratis; la 2 y 3 con pases), nodos con rangos 1-5, talentos CLAVE, detalle del nodo y resumen de bonos.
    Datos: TalentState / TalentAction (TalentService) + TalentCatalog. Se abre con MenuBus "Talents" (menú del HUD y Ajustes).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local Catalog: any = require(Modules:WaitForChild("TalentCatalog", 10))
local TalentIcons = require(Modules:WaitForChild("TalentIcons", 10))

local stateRemote = ClientNet.Get("TalentState")
local actionRemote = ClientNet.Get("TalentAction")

local gui = Instance.new("ScreenGui")
gui.Name = "TalentGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

type SlotState = { R: { [string]: number }, Role: string?, F: number, Owned: boolean, Spent: number }
local state: { Active: number, Slots: { SlotState }, Points: number, RespecCost: number }? = nil
local win: Frame? = nil
local branchId = "Defensa"
local viewSlot = 0 -- 0 = la activa
local selected: string? = nil
local glowConn: RBXScriptConnection? = nil

local function pct(v: number): string
	local s = string.format("%.1f", math.abs(v) * 100):gsub("%.0$", "")
	return (if v < 0 then "−" else "+") .. s:gsub("%.", ",") .. "%"
end

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local function statsText(stats: { [string]: number }): string
	local parts: { string } = {}
	for st, v in pairs(stats) do
		table.insert(parts, string.format("%s %s", pct(v), Catalog.StatName[st] or st))
	end
	table.sort(parts)
	return table.concat(parts, "  ·  ")
end

local function levelNow(): number
	local v = player:GetAttribute("Level")
	return if typeof(v) == "number" then v else 1
end

local function spentIn(ranks: { [string]: number }, branch: string): number
	local sum = 0
	for id, r in pairs(ranks) do
		local n = Catalog.ById[id]
		if n and n.Branch == branch then
			sum += Catalog.TotalCost(n, r)
		end
	end
	return sum
end

local function keystoneCount(ranks: { [string]: number }): number
	local c = 0
	for id, r in pairs(ranks) do
		local n = Catalog.ById[id]
		if n and n.Key and r > 0 then
			c += 1
		end
	end
	return c
end

local function build()
	if glowConn then
		glowConn:Disconnect()
		glowConn = nil
	end
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local faction = player:GetAttribute("Faction")
	local WW, HH = 1040, 680
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Árbol de talentos",
		"Elige tu camino: cada punto cuenta", "🌳", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Talents", 40, 50)
	if not state then
		local l = UITheme.Text(w, "Cargando…", 14, pal.Text, UDim2.fromOffset(20, NpcKit.TOP + 20), UDim2.fromOffset(300, 20))
		l.TextStrokeTransparency = 1
		return
	end
	local st = state
	local slotN = if viewSlot >= 1 then viewSlot else st.Active
	local slot = st.Slots[slotN]
	local ranks = slot.R
	local level = levelNow()
	local spentTotal = slot.Spent
	local left = st.Points - spentTotal

	-- RAMAS (columna izquierda)
	local sideW = 178
	local branchDef: any = nil
	for i, b in ipairs(Catalog.Branches) do
		if b.Id == branchId then
			branchDef = b
		end
		local sp = spentIn(ranks, b.Id)
		local lockedAsc = b.Id == "Ascendencia" and level < Catalog.ASCENDENCIA_LEVEL
		local t = NpcKit.Tab(w, theme, string.format("%s  %s", b.Icon, b.Name), UDim2.fromOffset(sideW - 12, 44), UDim2.fromOffset(12, NpcKit.TOP + (i - 1) * 52), branchId == b.Id, function()
			branchId = b.Id
			selected = nil
			build()
		end)
		local sub = UITheme.Text(w, if lockedAsc then string.format("🔒 Nivel %d", Catalog.ASCENDENCIA_LEVEL) else string.format("%d puntos gastados", sp), 10, if lockedAsc then Color3.fromRGB(190, 160, 160) else pal.Muted, UDim2.fromOffset(24, NpcKit.TOP + (i - 1) * 52 + 28), UDim2.fromOffset(sideW - 40, 12))
		sub.TextStrokeTransparency = 1
		sub.ZIndex = t.ZIndex + 1
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(4, 30)
		bar.Position = UDim2.fromOffset(6, NpcKit.TOP + (i - 1) * 52 + 7)
		bar.BackgroundColor3 = b.Color
		bar.BorderSizePixel = 0
		bar.ZIndex = t.ZIndex + 1
		Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 2)
		bar.Parent = w
	end
	local bcol: Color3 = branchDef.Color

	-- PESTAÑAS DE BUILD (arriba)
	local x0 = sideW + 18
	for i = 1, Catalog.SLOTS do
		local s = st.Slots[i]
		local label = string.format("Build %d%s%s", i, if s.Owned then "" else "  🔒", if st.Active == i then "  ✔" else "")
		NpcKit.Tab(w, theme, label, UDim2.fromOffset(150, 32), UDim2.fromOffset(x0 + (i - 1) * 158, NpcKit.TOP), slotN == i, function()
			viewSlot = i
			selected = nil
			build()
		end)
	end
	local ptsColor = if left > 0 then Color3.fromRGB(255, 220, 110) else pal.Muted
	local pts = UITheme.Text(w, string.format("Puntos libres: %d / %d", left, st.Points), 16, ptsColor, UDim2.fromOffset(WW - 300, NpcKit.TOP + 2), UDim2.fromOffset(280, 26), Enum.TextXAlignment.Right)
	pts.Font = Enum.Font.GothamBold
	pts.TextStrokeTransparency = 1

	-- barra de acciones de la build
	local ay = NpcKit.TOP + 38
	local ax = x0
	if not slot.Owned then
		local lk = UITheme.Text(w, string.format("🔒 La Build %d viene con el pase \"Talentos %s\" de la Tienda. Mientras tanto puedes mirar el árbol.", slotN, if slotN == 2 then "II" else "III"), 12, Color3.fromRGB(255, 200, 120), UDim2.fromOffset(ax, ay + 2), UDim2.fromOffset(WW - sideW - 40, 20))
		lk.TextStrokeTransparency = 1
	else
		if st.Active ~= slotN then
			NpcKit.Button(w, theme, "▶ Activar esta build", UDim2.fromOffset(160, 26), UDim2.fromOffset(ax, ay), "buy", function()
				actionRemote:FireServer("Slot", slotN)
			end)
			ax += 168
		else
			local on = UITheme.Text(w, "✔ Build activa", 13, Color3.fromRGB(120, 220, 140), UDim2.fromOffset(ax + 4, ay + 2), UDim2.fromOffset(120, 22))
			on.TextStrokeTransparency = 1
			ax += 126
		end
		local myRole = tostring(player:GetAttribute("Role") or "")
		local linked = slot.Role ~= nil
		NpcKit.Button(w, theme, if linked then string.format("🔗 Rol: %s · Quitar", slot.Role) else string.format("🔗 Vincular a mi rol (%s)", myRole), UDim2.fromOffset(250, 26), UDim2.fromOffset(ax, ay), if linked then "danger" else "buy", function()
			actionRemote:FireServer("Link", slotN, if linked then "" else myRole)
		end)
		ax += 258
		local costTxt = if slot.F > 0 then "gratis" else thousands(st.RespecCost) .. " 🪙"
		NpcKit.Button(w, theme, string.format("♻ Reiniciar (%s)", costTxt), UDim2.fromOffset(190, 26), UDim2.fromOffset(ax, ay), "danger", function()
			actionRemote:FireServer("Reset", slotN)
		end)
	end

	-- ÁRBOL (centro)
	local treeX, treeY = sideW + 12, NpcKit.TOP + 72
	local detailW = 250
	local treeW, treeH = WW - treeX - detailW - 24, HH - treeY - 74
	local tree = NpcKit.Panel(w, theme, UDim2.fromOffset(treeW, treeH), UDim2.fromOffset(treeX, treeY), "inset")
	tree.ClipsDescendants = true
	-- fondo: degradado suave del color de la rama + título
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new(bcol:Lerp(Color3.new(0, 0, 0), 0.82), Color3.new(0.04, 0.04, 0.06))
	bg.Rotation = 90
	bg.Parent = tree
	local title = UITheme.Text(tree, branchDef.Icon .. "  " .. branchDef.Name:upper(), 20, bcol, UDim2.fromOffset(16, 8), UDim2.fromOffset(treeW - 32, 26), Enum.TextXAlignment.Left)
	title.Font = Enum.Font.GothamBlack
	title.TextStrokeTransparency = 0.6
	local desc = UITheme.Text(tree, branchDef.Desc, 12, pal.Muted, UDim2.fromOffset(16, 34), UDim2.fromOffset(treeW - 32, 16), Enum.TextXAlignment.Left)
	desc.TextStrokeTransparency = 1

	-- nodos de esta rama (y de mi facción)
	local nodes: { any } = {}
	local rowsPresent: { [number]: boolean } = {}
	for _, n in ipairs(Catalog.List) do
		if n.Branch == branchId and (not n.Faction or n.Faction == faction) then
			table.insert(nodes, n)
			rowsPresent[n.Row] = true
		end
	end
	local rowList: { number } = {}
	for r in pairs(rowsPresent) do
		table.insert(rowList, r)
	end
	table.sort(rowList)
	local rowIndex: { [number]: number } = {}
	for i, r in ipairs(rowList) do
		rowIndex[r] = i
	end
	local top, rowGap = 78, (treeH - 78 - 70) / math.max(1, #rowList - 1)
	local function posOf(n: any): Vector2
		local cols = 4
		local cx = (n.Col - 0.5) / cols * (treeW - 60) + 30
		local cy = top + (rowIndex[n.Row] - 1) * rowGap + 32
		return Vector2.new(cx, cy)
	end
	local spentBranch = spentIn(ranks, branchId)
	local keys = keystoneCount(ranks)

	-- etiquetas de tier a la izquierda y líneas de conexión
	local tierLabel: { [number]: string } = {
		[1] = string.format("Nv %d", Catalog.TierLevel[1]),
		[2] = string.format("Nv %d · %d pts", Catalog.TierLevel[2], Catalog.TierSpent[2]),
		[3] = string.format("Nv %d · %d pts", Catalog.TierLevel[3], Catalog.TierSpent[3]),
		[4] = "CLAVE",
	}
	for _, n in ipairs(nodes) do
		-- línea hacia el nodo de arriba en la misma columna (o el central, para las claves)
		local p = posOf(n)
		for _, m in ipairs(nodes) do
			if m.Row < n.Row and (m.Col == n.Col or n.Key) and rowIndex[m.Row] == rowIndex[n.Row] - 1 and (n.Key == true and m.Col == 2 or m.Col == n.Col) then
				local q = posOf(m)
				local line = Instance.new("Frame")
				line.AnchorPoint = Vector2.new(0.5, 0)
				line.Position = UDim2.fromOffset(q.X, q.Y + 26)
				local dx, dy = p.X - q.X, (p.Y - 26) - (q.Y + 26)
				local len = math.sqrt(dx * dx + dy * dy)
				line.Size = UDim2.fromOffset(3, len)
				line.Rotation = math.deg(math.atan2(-dx, dy))
				line.BackgroundColor3 = bcol
				line.BackgroundTransparency = if (ranks[m.Id] or 0) > 0 then 0.35 else 0.85
				line.BorderSizePixel = 0
				line.Parent = tree
			end
		end
	end
	local tierShown: { [number]: boolean } = {}
	for _, n in ipairs(nodes) do
		if not tierShown[n.Row] then
			tierShown[n.Row] = true
			local tl = UITheme.Text(tree, tierLabel[n.Row] or "", 10, pal.Muted, UDim2.fromOffset(6, posOf(n).Y - 6), UDim2.fromOffset(70, 12), Enum.TextXAlignment.Left)
			tl.TextStrokeTransparency = 1
		end
	end

	local glowing: { UIStroke } = {}
	local ascLocked = branchId == "Ascendencia" and level < Catalog.ASCENDENCIA_LEVEL
	for _, n in ipairs(nodes) do
		local rank = ranks[n.Id] or 0
		local maxR = Catalog.MaxRankOf(n)
		local ok, why = Catalog.Requirement(n, level, spentBranch)
		local canBuy = ok and rank < maxR and slot.Owned and (left >= Catalog.CostOf(n, rank + 1)) and not (n.Key and keys >= Catalog.MAX_KEYSTONES and rank == 0)
		local size = if n.Key then 70 else 58
		local p = posOf(n)
		local btn = Instance.new("TextButton")
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromOffset(p.X, p.Y)
		btn.Size = UDim2.fromOffset(size, size)
		local lit = rank > 0
		btn.BackgroundColor3 = if lit then bcol:Lerp(Color3.new(0, 0, 0), 0.35) elseif ok then Color3.fromRGB(34, 36, 48) else Color3.fromRGB(22, 22, 28)
		btn.BorderSizePixel = 0
		btn.Parent = tree
		local cr = Instance.new("UICorner")
		cr.CornerRadius = if n.Key then UDim.new(0.5, 0) else UDim.new(0, 14)
		cr.Parent = btn
		local sk = Instance.new("UIStroke")
		sk.Thickness = if selected == n.Id then 3.5 else 2.2
		sk.Color = if rank >= maxR then Color3.fromRGB(255, 214, 90) elseif lit or canBuy then bcol else Color3.fromRGB(70, 72, 86)
		sk.Transparency = if ok or lit then 0 else 0.4
		sk.Parent = btn
		if canBuy then
			table.insert(glowing, sk)
		end
		local ic = UITheme.Text(btn, n.Icon, if n.Key then 32 else 28, Color3.new(1, 1, 1), UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		ic.TextStrokeTransparency = 1
		ic.TextTransparency = if ok or lit then 0 else 0.6
		local art = TalentIcons.Make(btn, n.Id)
		if art then
			-- icono real encima del emoji: el emoji solo se oculta cuando la imagen YA cargó (si falla, se sigue viendo el emoji)
			art.ImageTransparency = if ok or lit then 0 else 0.55
			art.ImageColor3 = if ok or lit then Color3.new(1, 1, 1) else Color3.fromRGB(150, 150, 160)
			task.spawn(function()
				for _ = 1, 40 do
					if art.IsLoaded then
						ic.Visible = false
						btn.BackgroundTransparency = 1
						return
					end
					task.wait(0.1)
				end
			end)
		end
		-- rango
		local rk = UITheme.Text(tree, if n.Key then (if rank > 0 then "ACTIVA" else "CLAVE") else string.format("%d/%d", rank, maxR), 11, if rank >= maxR then Color3.fromRGB(255, 214, 90) elseif lit then bcol else pal.Muted, UDim2.fromOffset(p.X - 40, p.Y + size / 2 + 2), UDim2.fromOffset(80, 14), Enum.TextXAlignment.Center)
		rk.Font = Enum.Font.GothamBold
		rk.TextStrokeTransparency = 1
		if not ok and rank == 0 then
			local lock = UITheme.Text(btn, "🔒", 14, Color3.new(1, 1, 1), UDim2.new(1, -18, 1, -18), UDim2.fromOffset(18, 18), Enum.TextXAlignment.Center)
			lock.TextStrokeTransparency = 1
			lock.ZIndex = 5
		end
		btn.MouseButton1Click:Connect(function()
			selected = n.Id
			build()
		end)
		btn.MouseButton2Click:Connect(function() -- clic derecho: sube un rango directo
			if canBuy then
				actionRemote:FireServer("Upgrade", slotN, n.Id)
			end
		end)
		if ascLocked then
			btn.Active = true
		end
	end
	if #glowing > 0 then
		local t0 = os.clock()
		glowConn = RunService.Heartbeat:Connect(function()
			local a = 0.5 + 0.5 * math.sin((os.clock() - t0) * 3.2)
			for _, s in ipairs(glowing) do
				s.Transparency = 0.55 * (1 - a)
			end
		end)
	end

	-- DETALLE (derecha)
	local det = NpcKit.Panel(w, theme, UDim2.fromOffset(detailW, treeH), UDim2.fromOffset(WW - detailW - 14, treeY), "card")
	local sel = if selected then Catalog.ById[selected] else nil
	if not sel then
		local h = UITheme.Text(det, "Toca un talento para ver su detalle.\n\nBrillante = puedes subirlo.\n🔒 = te falta nivel o puntos en la rama.\nClic derecho sube un rango directo.", 12, pal.Muted, UDim2.fromOffset(14, 14), UDim2.fromOffset(detailW - 28, 140), Enum.TextXAlignment.Left)
		h.TextWrapped = true
		h.TextYAlignment = Enum.TextYAlignment.Top
		h.TextStrokeTransparency = 1
		local rules = UITheme.Text(det, string.format("Puntos: 1 cada 10 niveles y +4 cada 250.\nRangos: cuestan 1, 1, 2, 3 y 5.\nCLAVE: máximo %d activas a la vez.", Catalog.MAX_KEYSTONES), 11, pal.Muted, UDim2.fromOffset(14, treeH - 100), UDim2.fromOffset(detailW - 28, 90), Enum.TextXAlignment.Left)
		rules.TextWrapped = true
		rules.TextYAlignment = Enum.TextYAlignment.Top
		rules.TextStrokeTransparency = 1
	else
		local rank = ranks[sel.Id] or 0
		local maxR = Catalog.MaxRankOf(sel)
		local detArt: Frame? = nil
		if TalentIcons.Has(sel.Id) then
			local holder = Instance.new("Frame")
			holder.BackgroundTransparency = 1
			holder.Position = UDim2.fromOffset(14, 8)
			holder.Size = UDim2.fromOffset(48, 48)
			holder.Parent = det
			TalentIcons.Make(holder, sel.Id)
			detArt = holder
		end
		local nm = UITheme.Text(det, if detArt then sel.Name else sel.Icon .. "  " .. sel.Name, 17, bcol, UDim2.fromOffset(if detArt then 70 else 14, 12), UDim2.fromOffset(detailW - (if detArt then 84 else 28), 44), Enum.TextXAlignment.Left)
		nm.Font = Enum.Font.GothamBold
		nm.TextWrapped = true
		nm.TextYAlignment = Enum.TextYAlignment.Top
		nm.TextStrokeTransparency = 1
		local ds = UITheme.Text(det, sel.Desc, 12, pal.Text, UDim2.fromOffset(14, 62), UDim2.fromOffset(detailW - 28, 70), Enum.TextXAlignment.Left)
		ds.TextWrapped = true
		ds.TextYAlignment = Enum.TextYAlignment.Top
		ds.TextStrokeTransparency = 1
		local y = 138
		local function line(text: string, color: Color3?)
			local l = UITheme.Text(det, text, 12, color or pal.FText, UDim2.fromOffset(14, y), UDim2.fromOffset(detailW - 28, 32), Enum.TextXAlignment.Left)
			l.TextWrapped = true
			l.TextYAlignment = Enum.TextYAlignment.Top
			l.TextStrokeTransparency = 1
			y += 18 + 14 * math.floor(#text / 34)
		end
		if sel.Stats then
			local one: { [string]: number } = {}
			for k, v in pairs(sel.Stats) do
				one[k] = v
			end
			line((if sel.Key then "Efecto: " else "Por rango: ") .. statsText(one), Color3.fromRGB(150, 230, 170))
		end
		if sel.Aura then
			line("Aura al grupo cercano: " .. statsText(sel.Aura) .. (if sel.Key then "" else " por rango"), Color3.fromRGB(150, 200, 255))
		end
		if not sel.Key then
			line(string.format("Rango %d/%d  ·  costos: 1, 1, 2, 3, 5", rank, maxR))
		end
		local ok, why = Catalog.Requirement(sel, level, spentBranch)
		if not ok then
			line("🔒 Requisito: " .. (why or ""), Color3.fromRGB(255, 170, 130))
		end
		if sel.Key and keys >= Catalog.MAX_KEYSTONES and rank == 0 then
			line(string.format("Ya tienes %d talentos CLAVE activos.", keys), Color3.fromRGB(255, 170, 130))
		end
		if rank >= maxR then
			local mx = UITheme.Text(det, "✔ Al máximo", 14, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(14, treeH - 46), UDim2.fromOffset(detailW - 28, 28), Enum.TextXAlignment.Center)
			mx.Font = Enum.Font.GothamBold
			mx.TextStrokeTransparency = 1
		else
			local cost = Catalog.CostOf(sel, rank + 1)
			local can = ok and slot.Owned and left >= cost and not (sel.Key and keys >= Catalog.MAX_KEYSTONES)
			NpcKit.Button(det, theme, string.format("%s  (%d pts)", if rank == 0 then "Aprender" else "Subir rango", cost), UDim2.fromOffset(detailW - 28, 34), UDim2.fromOffset(14, treeH - 50), if can then "buy" else "danger", function()
				if can then
					actionRemote:FireServer("Upgrade", slotN, sel.Id)
				end
			end)
		end
	end

	-- RESUMEN DE BONOS (abajo)
	local sumP = NpcKit.Panel(w, theme, UDim2.fromOffset(WW - 28, 56), UDim2.fromOffset(14, HH - 66), "card")
	local total, aura = Catalog.Evaluate(ranks)
	local t1 = UITheme.Text(sumP, "Bonos de esta build: " .. (if next(total) then statsText(total) else "ninguno todavía"), 12, pal.FText, UDim2.fromOffset(12, 6), UDim2.fromOffset(WW - 56, 20), Enum.TextXAlignment.Left)
	t1.TextStrokeTransparency = 1
	t1.TextTruncate = Enum.TextTruncate.AtEnd
	local t2 = UITheme.Text(sumP, "Aura a tu grupo cercano: " .. (if next(aura) then statsText(aura) else "ninguna") .. string.format("   ·   Claves: %d/%d", keys, Catalog.MAX_KEYSTONES), 12, Color3.fromRGB(150, 200, 255), UDim2.fromOffset(12, 28), UDim2.fromOffset(WW - 56, 20), Enum.TextXAlignment.Left)
	t2.TextStrokeTransparency = 1
	t2.TextTruncate = Enum.TextTruncate.AtEnd
end

stateRemote.OnClientEvent:Connect(function(s: any)
	state = s
	if gui.Enabled then
		build()
	end
end)
player:GetAttributeChangedSignal("Level"):Connect(function()
	if gui.Enabled then
		build()
	end
end)

MenuBus.Event:Connect(function(name: string)
	if name == "Talents" then
		if gui.Enabled then
			gui.Enabled = false
		else
			actionRemote:FireServer("State")
			build()
			gui.Enabled = true
		end
	end
end)

actionRemote:FireServer("State")
