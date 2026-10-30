--!strict
--[[
    AutoFarmClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > AutoFarmClient
    Cartel discreto del AUTO-FARM en el borde derecho de la pantalla (no tapa nada del HUD):
      - Pastilla "AUTO-FARM  ON/OFF" (clic o tecla Z).
      - Botón MODO: Semi (tú caminas, los poderes y el ataque básico solos) · Metin · Jefe.
      - Línea de estado ("Atacando", "Buscando mobs...") cuando está encendido.
    En la Arena (PvP) el servidor lo apaga: ahí todo es manual.
    También camina hacia el objetivo cuando el servidor lo pide (modos Metin y Jefe); si tocas WASD/flechas, tú mandas 1 s.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local setRemote = Remotes:WaitForChild("AutoFarm", 10) :: RemoteEvent
local moveRemote = Remotes:WaitForChild("AutoFarmMove", 10) :: RemoteEvent

local MODES = { "Semi", "Metin", "Jefe" }
local MODE_HINT: { [string]: string } = {
	Semi = "Tú caminas",
	Metin = "Piedra y oleadas",
	Jefe = "Jefe y súbditos",
}
local ON_COLOR = Color3.fromRGB(80, 220, 120)
local OFF_COLOR = Color3.fromRGB(150, 150, 165)

local theme = UITheme.For(player:GetAttribute("Faction"))
local ItemCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemCatalog"))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "AutoFarmGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 4
gui.Parent = player:WaitForChild("PlayerGui", 10)

local holder = Instance.new("Frame")
holder.AnchorPoint = Vector2.new(1, 0.5)
holder.Position = UDim2.new(1, -10, 0.62, 0)
holder.Size = UDim2.fromOffset(172, 10)
holder.AutomaticSize = Enum.AutomaticSize.Y
holder.BackgroundTransparency = 1
holder.Parent = gui
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.HorizontalAlignment = Enum.HorizontalAlignment.Right
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = holder

-- Pastilla principal
local pill = UITheme.Frame(holder, theme, UDim2.fromOffset(172, 36), UDim2.new(), nil)
pill.LayoutOrder = 1
local dot = Instance.new("Frame")
dot.AnchorPoint = Vector2.new(0, 0.5)
dot.Position = UDim2.new(0, 12, 0.5, 0)
dot.Size = UDim2.fromOffset(12, 12)
dot.BackgroundColor3 = OFF_COLOR
dot.BorderSizePixel = 0
dot.Parent = pill
Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
local title = UITheme.Text(pill, "AUTO-FARM", 14, Color3.new(1, 1, 1), UDim2.fromOffset(32, 0), UDim2.new(1, -90, 1, 0))
title.TextXAlignment = Enum.TextXAlignment.Left
local badge = UITheme.Text(pill, "OFF", 14, OFF_COLOR, UDim2.new(1, -52, 0, 0), UDim2.fromOffset(44, 36), Enum.TextXAlignment.Center)
local click = Instance.new("TextButton")
click.Size = UDim2.fromScale(1, 1)
click.BackgroundTransparency = 1
click.Text = ""
click.Parent = pill

-- Fila de estado + botón de modo
local row = Instance.new("Frame")
row.LayoutOrder = 2
row.Size = UDim2.fromOffset(172, 22)
row.BackgroundTransparency = 1
row.Parent = holder
local statusLabel = UITheme.Text(row, "", 11, Color3.fromRGB(200, 200, 215), UDim2.fromOffset(2, 0), UDim2.new(1, -66, 1, 0))
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextTransparency = 0.1
local modeBtn = Instance.new("TextButton")
modeBtn.AnchorPoint = Vector2.new(1, 0.5)
modeBtn.Position = UDim2.new(1, 0, 0.5, 0)
modeBtn.Size = UDim2.fromOffset(60, 22)
modeBtn.BackgroundColor3 = theme.Dark
modeBtn.BackgroundTransparency = 0.12
modeBtn.Text = "MODO"
modeBtn.Font = UITheme.Font
modeBtn.TextSize = 11
modeBtn.TextColor3 = theme.Primary
modeBtn.Parent = row
Instance.new("UICorner", modeBtn).CornerRadius = UDim.new(0, 6)
UITheme.Border(modeBtn, theme, 1)

-- Panel de modos (se abre con MODO)
local panel = UITheme.Frame(holder, theme, UDim2.fromOffset(172, #MODES * 32 + 8), UDim2.new(), nil)
panel.LayoutOrder = 3
panel.Visible = false
local modeButtons: { [string]: TextButton } = {}
for i, m in ipairs(MODES) do
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(6, 4 + (i - 1) * 32)
	b.Size = UDim2.new(1, -12, 0, 28)
	b.BackgroundColor3 = theme.Dark
	b.BackgroundTransparency = 0.3
	b.Text = ""
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	local t = UITheme.Text(b, m, 13, Color3.new(1, 1, 1), UDim2.fromOffset(10, 0), UDim2.new(0.5, 0, 1, 0))
	t.TextXAlignment = Enum.TextXAlignment.Left
	local h = UITheme.Text(b, MODE_HINT[m], 10, Color3.fromRGB(180, 180, 195), UDim2.new(0.42, 0, 0, 0), UDim2.new(0.58, -8, 1, 0), Enum.TextXAlignment.Right)
	h.TextTransparency = 0.15
	modeButtons[m] = b
	b.Activated:Connect(function()
		setRemote:FireServer("Set", "keep", m)
	end)
end

---------------------------------------------------------------------
-- POCIONES: 2 cuadros (vida y energía). Toca el cuadro para elegir la poción (Auto = la detecta sola del inventario);
-- − / + cambian el % por debajo del cual el Auto-farm la toma (0% = apagado).
---------------------------------------------------------------------
local potionRow = UITheme.Frame(holder, theme, UDim2.fromOffset(172, 56), UDim2.new(), nil)
potionRow.LayoutOrder = 5
-- cabecera para minimizar / expandir la sección de pociones
local potionHead = Instance.new("TextButton")
potionHead.LayoutOrder = 4
potionHead.Size = UDim2.fromOffset(172, 20)
potionHead.BackgroundColor3 = theme.Dark
potionHead.BackgroundTransparency = 0.25
potionHead.Font = UITheme.Font
potionHead.TextSize = 11
potionHead.TextColor3 = theme.Primary
potionHead.Parent = holder
Instance.new("UICorner", potionHead).CornerRadius = UDim.new(0, 6)
local function syncPotionHead()
	potionHead.Text = if potionRow.Visible then "POCIONES  ▲" else "POCIONES  ▼"
end
-- interruptor: curar aliados / grupo automáticamente
local allyBtn = Instance.new("TextButton")
allyBtn.LayoutOrder = 6
allyBtn.Size = UDim2.fromOffset(172, 22)
allyBtn.BackgroundColor3 = theme.Dark
allyBtn.BackgroundTransparency = 0.25
allyBtn.Font = UITheme.Font
allyBtn.TextSize = 11
allyBtn.Parent = holder
Instance.new("UICorner", allyBtn).CornerRadius = UDim.new(0, 6)
local function syncAlly()
	local on = player:GetAttribute("AF_AllyHeal") ~= false
	allyBtn.Text = if on then "AUTO CURAR ALIADOS: ON" else "AUTO CURAR ALIADOS: OFF"
	allyBtn.TextColor3 = if on then Color3.fromRGB(80, 220, 120) else Color3.fromRGB(150, 150, 165)
end
allyBtn.Activated:Connect(function()
	setRemote:FireServer("AllyHeal", player:GetAttribute("AF_AllyHeal") == false)
end)
player:GetAttributeChangedSignal("AF_AllyHeal"):Connect(syncAlly)
syncAlly()
potionHead.Activated:Connect(function()
	potionRow.Visible = not potionRow.Visible
	syncPotionHead()
end)
syncPotionHead()
local potionUI: { [string]: { Count: TextLabel, Pct: TextLabel, Name: TextLabel, Square: TextButton } } = {}
local KINDS = {
	{ Kind = "Hp", Field = "HealPct", Label = "VIDA", Color = Color3.fromRGB(235, 80, 90), PctAttr = "AF_HpPct", ItemAttr = "AF_HpItem" },
	{ Kind = "En", Field = "EnergyPct", Label = theme.Resource, Color = theme.ResourceColor, PctAttr = "AF_EnPct", ItemAttr = "AF_EnItem" },
}
local function bagCount(id: string): number
	local n = 0
	for _, stack in pairs(Store.Bag) do
		if stack.Id == id then
			n += stack.Count
		end
	end
	return n
end
local function candidates(field: string): { string }
	local out: { string } = {}
	for id, it in pairs(ItemCatalog.Items) do
		local use: any = it.Use
		if use and use[field] and bagCount(id) > 0 then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end
local function currentPct(attr: string): number
	local v = player:GetAttribute(attr)
	return if typeof(v) == "number" then v else 0
end

for i, k in ipairs(KINDS) do
	local x = 6 + (i - 1) * 82
	local sq = Instance.new("TextButton")
	sq.Position = UDim2.fromOffset(x, 6)
	sq.Size = UDim2.fromOffset(36, 36)
	sq.BackgroundColor3 = theme.Dark
	sq.BackgroundTransparency = 0.1
	sq.Text = ""
	sq.Parent = potionRow
	Instance.new("UICorner", sq).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = k.Color
	stroke.Thickness = 2
	stroke.Parent = sq
	local lbl = UITheme.Text(sq, k.Label, 10, k.Color, UDim2.fromOffset(0, 2), UDim2.new(1, 0, 0, 16), Enum.TextXAlignment.Center)
	lbl.TextStrokeTransparency = 0.5
	local cnt = UITheme.Text(sq, "0", 14, Color3.new(1, 1, 1), UDim2.fromOffset(0, 16), UDim2.new(1, 0, 0, 18), Enum.TextXAlignment.Center)
	local nm = UITheme.Text(potionRow, "Auto", 9, Color3.fromRGB(190, 190, 205), UDim2.fromOffset(x - 2, 43), UDim2.fromOffset(80, 12), Enum.TextXAlignment.Left)
	local pct = UITheme.Text(potionRow, "0%", 13, Color3.new(1, 1, 1), UDim2.fromOffset(x + 40, 4), UDim2.fromOffset(34, 16), Enum.TextXAlignment.Center)
	local function stepBtn(text: string, dy: number, delta: number)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x + 40, 22 + dy)
		b.Size = UDim2.fromOffset(34, 14)
		b.BackgroundColor3 = theme.Dark
		b.BackgroundTransparency = 0.2
		b.Text = text
		b.Font = UITheme.Font
		b.TextSize = 12
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Parent = potionRow
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 4)
		b.Activated:Connect(function()
			local v = math.clamp(math.floor((currentPct(k.PctAttr) + delta) * 100 + 0.5) / 100, 0, 0.95)
			setRemote:FireServer("Potion", k.Kind, v) -- sin objeto: no cambia la poción elegida
		end)
	end
	stepBtn("+", 0, 0.05)
	stepBtn("−", 15, -0.05)
	sq.Activated:Connect(function()
		-- rota: Auto -> cada poción disponible -> Auto
		local list = candidates(k.Field)
		local cur = player:GetAttribute(k.ItemAttr)
		local nextId = ""
		if typeof(cur) ~= "string" or cur == "" then
			nextId = list[1] or ""
		else
			for idx, id in ipairs(list) do
				if id == cur then
					nextId = list[idx + 1] or ""
				end
			end
		end
		setRemote:FireServer("Potion", k.Kind, currentPct(k.PctAttr), nextId)
	end)
	potionUI[k.Kind] = { Count = cnt, Pct = pct, Name = nm, Square = sq }
end

local function refreshPotions()
	for _, k in ipairs(KINDS) do
		local ui = potionUI[k.Kind]
		local want = player:GetAttribute(k.ItemAttr)
		local id: string? = nil
		if typeof(want) == "string" and want ~= "" and ItemCatalog.Items[want] then
			id = want
		else
			id = candidates(k.Field)[1]
		end
		ui.Count.Text = tostring(if id then bagCount(id) else 0)
		ui.Name.Text = if typeof(want) == "string" and want ~= "" then (ItemCatalog.Items[want] and ItemCatalog.Items[want].Name or "Auto") else "Auto" .. (if id then (": " .. ItemCatalog.Items[id].Name) else " (sin poción)")
		local p = currentPct(k.PctAttr)
		ui.Pct.Text = if p <= 0 then "OFF" else string.format("%d%%", math.floor(p * 100 + 0.5))
		ui.Square.BackgroundTransparency = if id and bagCount(id) > 0 then 0.1 else 0.5
	end
end
for _, a in ipairs({ "AF_HpPct", "AF_EnPct", "AF_HpItem", "AF_EnItem" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshPotions)
end
Store.Changed:Connect(refreshPotions)
refreshPotions()

local pulse: Tween? = nil
local function refresh()
	local on = player:GetAttribute("AutoFarm") == true
	local mode = player:GetAttribute("AutoFarmMode")
	local mname = if typeof(mode) == "string" and (mode == "Semi" or mode == "Metin" or mode == "Jefe") then mode else "Semi"
	badge.Text = if on then "ON" else "OFF"
	badge.TextColor3 = if on then ON_COLOR else OFF_COLOR
	dot.BackgroundColor3 = if on then ON_COLOR else OFF_COLOR
	local st = player:GetAttribute("AutoFarmStatus")
	statusLabel.Text = if on then (mname .. (if typeof(st) == "string" and st ~= "" then " · " .. st else "")) else mname
	for m, b in pairs(modeButtons) do
		b.BackgroundColor3 = if m == mname then theme.Secondary else theme.Dark
		b.BackgroundTransparency = if m == mname then 0.1 else 0.3
	end
	if pulse then
		pulse:Cancel()
		pulse = nil
	end
	dot.BackgroundTransparency = 0
	if on then
		local tw = TweenService:Create(dot, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.6 })
		pulse = tw
		tw:Play()
	end
end

local function toggle()
	local on = player:GetAttribute("AutoFarm") == true
	setRemote:FireServer("Set", not on, nil)
end

click.Activated:Connect(toggle)
modeBtn.Activated:Connect(function()
	panel.Visible = not panel.Visible
end)
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Z then
		toggle()
	end
end)
for _, a in ipairs({ "AutoFarm", "AutoFarmMode", "AutoFarmStatus" }) do
	player:GetAttributeChangedSignal(a):Connect(refresh)
end
refresh()

---------------------------------------------------------------------
-- CAMINAR (modos Metin y Jefe): el servidor manda el punto; el cliente mueve su propio personaje
---------------------------------------------------------------------
local waypoints: { Vector3 }? = nil
local chase: { Model: Model, Stop: number }? = nil -- persecución en vivo: sigue al objetivo cada frame
local chasing = false
local wpIndex = 1
local manualUntil = 0
local lastPos = Vector3.zero
local lastMoveCheck = 0
local stuckCount = 0
moveRemote.OnClientEvent:Connect(function(g: any)
	if typeof(g) == "table" and typeof((g :: any).Chase) == "Instance" and typeof((g :: any).Stop) == "number" then
		local m = (g :: any).Chase :: Instance
		if m:IsA("Model") then
			if not chase or chase.Model ~= m then
				chasing = true
			end
			chase = { Model = m, Stop = (g :: any).Stop :: number }
			waypoints = nil
		end
		return
	end
	chase = nil
	if typeof(g) == "table" then
		local list: { Vector3 } = {}
		for _, p in ipairs(g :: { any }) do
			if typeof(p) == "Vector3" then
				table.insert(list, p)
			end
		end
		-- misma ruta que ya seguimos: no reiniciar el avance
		local cur = waypoints
		local same = cur ~= nil and #cur == #list and #list > 0 and (cur[#cur] - list[#list]).Magnitude < 6 and (cur[1] - list[1]).Magnitude < 6
		if not same then
			waypoints = if #list > 0 then list else nil
			wpIndex = 1
		end
	elseif typeof(g) == "Vector3" then
		waypoints = { g }
		wpIndex = 1
	else
		waypoints = nil
	end
end)

local function manualKeys(): boolean
	local k = Enum.KeyCode
	for _, key in ipairs({ k.W, k.A, k.S, k.D, k.Up, k.Down, k.Left, k.Right }) do
		if UserInputService:IsKeyDown(key) then
			return true
		end
	end
	return false
end

RunService.Heartbeat:Connect(function()
	if player:GetAttribute("AutoFarm") ~= true or player:GetAttribute("AutoFarmMode") == "Semi" then
		waypoints = nil
		chase = nil
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not (hum and root and root:IsA("BasePart") and hum.Health > 0) then
		return
	end
	if manualKeys() then
		manualUntil = os.clock() + 1
		return
	end
	-- PERSECUCIÓN EN VIVO: se acerca al objetivo cada frame hasta el contacto/alcance y ajusta si el enemigo se mueve
	local ch = chase
	if ch and os.clock() >= manualUntil then
		local tr = ch.Model:FindFirstChild("HumanoidRootPart")
		if ch.Model.Parent and tr and tr:IsA("BasePart") then
			local off = Vector3.new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z)
			local d = off.Magnitude
			if d > ch.Stop + 1.2 then
				chasing = true -- arranca a acercarse
			elseif d <= ch.Stop then
				chasing = false -- ya está a distancia de combate: se queda
			end
			if chasing and d > 0.1 then
				hum:MoveTo(tr.Position - off.Unit * (ch.Stop * 0.85))
			else
				hum:MoveTo(root.Position)
			end
			local now2 = os.clock()
			if now2 - lastMoveCheck > 0.8 then
				if chasing and (root.Position - lastPos).Magnitude < 0.4 and d > ch.Stop + 4 then
					hum.Jump = true
					stuckCount += 1
					if stuckCount >= 3 then
						stuckCount = 0
						setRemote:FireServer("Stuck")
					end
				else
					stuckCount = 0
				end
				lastPos = root.Position
				lastMoveCheck = now2
			end
			return
		end
		chase = nil
	end
	local list = waypoints
	if not list or os.clock() < manualUntil then
		return
	end
	-- avanza al siguiente punto de la ruta cuando llega al actual
	while wpIndex < #list and Vector3.new(list[wpIndex].X - root.Position.X, 0, list[wpIndex].Z - root.Position.Z).Magnitude < 4 do
		wpIndex += 1
	end
	local g = list[math.min(wpIndex, #list)]
	hum:MoveTo(g)
	-- si se atasca contra algo: salta; si sigue atascado, pide al servidor otra ruta
	local now = os.clock()
	if now - lastMoveCheck > 0.8 then
		if (root.Position - lastPos).Magnitude < 0.4 and (Vector3.new(g.X, root.Position.Y, g.Z) - root.Position).Magnitude > 6 then
			hum.Jump = true
			stuckCount += 1
			if stuckCount >= 3 then
				stuckCount = 0
				setRemote:FireServer("Stuck")
			end
		else
			stuckCount = 0
		end
		lastPos = root.Position
		lastMoveCheck = now
	end
end)
