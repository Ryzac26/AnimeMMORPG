--!strict
--[[
    MilestoneClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MilestoneClient
    Ventana "HITOS DE NIVEL": 60 recompensas (una cada 50 niveles) y las 5 AURAS que rodean al personaje.
    Datos: MilestoneState / MilestoneAction (LevelMilestoneService) + LevelMilestones. Se abre con MenuBus "Milestones" (botón en Ajustes).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local Milestones: any = require(Modules:WaitForChild("LevelMilestones", 10))
local LootTables: any = require(Modules:WaitForChild("LootTables", 10))

local stateRemote = ClientNet.Get("MilestoneState")
local actionRemote = ClientNet.Get("MilestoneAction")

local gui = Instance.new("ScreenGui")
gui.Name = "MilestoneGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local state: { Claimed: { [number]: boolean }, Aura: string? }? = nil
local tab = "Recompensas"

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	return (out:gsub("^%.", ""))
end

local function myLevel(): number
	local v = player:GetAttribute("Level")
	return if typeof(v) == "number" then v else 1
end

local function rewardText(r: any): string
	local parts = { thousands(r.Gold) .. " de oro" }
	if r.Mat then
		local info = LootTables.Materials[r.Mat]
		table.insert(parts, string.format("%dx %s", r.MatCount, if info then info.Name else r.Mat))
	end
	if r.Scroll > 0 then
		table.insert(parts, string.format("%dx Pergamino de Protección", r.Scroll))
	end
	return table.concat(parts, "  ·  ")
end

local function build()
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local WW, HH = 760, 600
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Hitos de nivel",
		"Una recompensa cada 50 niveles y auras que te rodean", "🎁", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Milestones", 40, 50)

	for i, name in ipairs({ "Recompensas", "Auras" }) do
		NpcKit.Tab(w, theme, name, UDim2.fromOffset(150, 32), UDim2.fromOffset(14 + (i - 1) * 158, NpcKit.TOP), tab == name, function()
			tab = name
			build()
		end)
	end

	local lvl = myLevel()
	local claimed = if state then state.Claimed else {}
	local ready, done = 0, 0
	for i = 1, Milestones.COUNT do
		if claimed[i] then
			done += 1
		elseif lvl >= Milestones.LevelOf(i) then
			ready += 1
		end
	end
	local nextIdx = math.min(Milestones.COUNT, lvl // Milestones.STEP + 1)
	local sumText = string.format("Tu nivel: %d   ·   Reclamadas: %d / %d   ·   Listas: %d", lvl, done, Milestones.COUNT, ready)
	if lvl < 3000 then
		sumText ..= string.format("   ·   Próxima: nivel %d", Milestones.LevelOf(nextIdx))
	end
	local sum = UITheme.Text(w, sumText, 13, pal.FText, UDim2.fromOffset(16, NpcKit.TOP + 40), UDim2.fromOffset(WW - 190, 20))
	sum.TextStrokeTransparency = 1

	local top = NpcKit.TOP + 66
	local holder = NpcKit.Panel(w, theme, UDim2.fromOffset(WW - 28, HH - top - 16), UDim2.fromOffset(14, top), "card")
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(4, 4)
	scroll.Size = UDim2.new(1, -8, 1, -8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = pal.Edge
	scroll.Parent = holder
	if not state then
		local l = UITheme.Text(scroll, "Cargando…", 14, pal.Text, UDim2.fromOffset(12, 12), UDim2.fromOffset(300, 20))
		l.TextStrokeTransparency = 1
		return
	end
	local innerW = WW - 28 - 8 - 14

	if tab == "Recompensas" then
		if ready > 0 then
			NpcKit.Button(w, theme, string.format("Reclamar todo (%d)", ready), UDim2.fromOffset(160, 26), UDim2.fromOffset(WW - 176, NpcKit.TOP + 38), "buy", function()
				actionRemote:FireServer("ClaimAll")
			end)
		end
		local rowH = 46
		-- las reclamables primero, luego las próximas por orden
		local order: { number } = {}
		for i = 1, Milestones.COUNT do
			table.insert(order, i)
		end
		table.sort(order, function(a: number, b: number)
			local ra = if claimed[a] then 2 elseif lvl >= Milestones.LevelOf(a) then 0 else 1
			local rb = if claimed[b] then 2 elseif lvl >= Milestones.LevelOf(b) then 0 else 1
			if ra ~= rb then
				return ra < rb
			end
			return a < b
		end)
		for row, i in ipairs(order) do
			local level = Milestones.LevelOf(i)
			local can = lvl >= level and not claimed[i]
			local card = NpcKit.Panel(scroll, theme, UDim2.fromOffset(innerW - 8, rowH - 4), UDim2.fromOffset(4, 4 + (row - 1) * rowH), "inset")
			local big = level % 250 == 0
			local head = UITheme.Text(card, (if big then "★ " else "") .. "Nivel " .. level, 15, if can then pal.FText else pal.Text, UDim2.fromOffset(12, 0), UDim2.fromOffset(120, rowH - 4), Enum.TextXAlignment.Left)
			head.TextStrokeTransparency = 1
			head.Font = Enum.Font.GothamBold
			local info = UITheme.Text(card, rewardText(Milestones.Reward(i)), 12, pal.Muted, UDim2.fromOffset(136, 0), UDim2.fromOffset(innerW - 136 - 150, rowH - 4), Enum.TextXAlignment.Left)
			info.TextStrokeTransparency = 1
			info.TextTruncate = Enum.TextTruncate.AtEnd
			if claimed[i] then
				local ok = UITheme.Text(card, "✔ Reclamada", 12, Color3.fromRGB(120, 220, 140), UDim2.new(1, -130, 0, 0), UDim2.fromOffset(120, rowH - 4), Enum.TextXAlignment.Center)
				ok.TextStrokeTransparency = 1
			elseif can then
				NpcKit.Button(card, theme, "Reclamar", UDim2.fromOffset(118, 28), UDim2.new(1, -130, 0, 7), "buy", function()
					actionRemote:FireServer("Claim", i)
				end)
			else
				local lk = UITheme.Text(card, string.format("🔒 faltan %d niv.", level - lvl), 12, Color3.fromRGB(165, 165, 180), UDim2.new(1, -130, 0, 0), UDim2.fromOffset(120, rowH - 4), Enum.TextXAlignment.Center)
				lk.TextStrokeTransparency = 1
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, 8 + Milestones.COUNT * rowH)
	else
		local cardH = 96
		local myFaction = Players.LocalPlayer:GetAttribute("Faction")
		local shown = {}
		for _, a in ipairs(Milestones.Auras) do
			if a.Faction == nil or a.Faction == myFaction then
				table.insert(shown, a)
			end
		end
		for i, a in ipairs(shown) do
			local unlocked = lvl >= a.Need
			local equipped = state.Aura == a.Id
			local card = NpcKit.Panel(scroll, theme, UDim2.fromOffset(innerW - 8, cardH - 6), UDim2.fromOffset(4, 4 + (i - 1) * cardH), "inset")
			-- cuadro de color con el icono del aura
			local sw = Instance.new("Frame")
			sw.Size = UDim2.fromOffset(64, 64)
			sw.Position = UDim2.fromOffset(12, 12)
			sw.BackgroundColor3 = Color3.new(1, 1, 1)
			sw.BorderSizePixel = 0
			Instance.new("UICorner", sw).CornerRadius = UDim.new(0, 12)
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(a.A, a.B)
			g.Rotation = 45
			g.Parent = sw
			sw.Parent = card
			local ic = UITheme.Text(sw, a.Icon, 30, Color3.new(1, 1, 1), UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
			ic.TextStrokeTransparency = 1
			if not unlocked then
				sw.BackgroundTransparency = 0.55
			end
			local nm = UITheme.Text(card, a.Name, 16, if unlocked then pal.FText else pal.Text, UDim2.fromOffset(90, 12), UDim2.fromOffset(innerW - 270, 20), Enum.TextXAlignment.Left)
			nm.TextStrokeTransparency = 1
			nm.Font = Enum.Font.GothamBold
			local ds = UITheme.Text(card, a.Desc, 12, pal.Muted, UDim2.fromOffset(90, 34), UDim2.fromOffset(innerW - 270, 32), Enum.TextXAlignment.Left)
			ds.TextWrapped = true
			ds.TextYAlignment = Enum.TextYAlignment.Top
			ds.TextStrokeTransparency = 1
			if unlocked then
				NpcKit.Button(card, theme, if equipped then "✔ Activa · Quitar" else "Activar", UDim2.fromOffset(150, 30), UDim2.new(1, -164, 0, 28), if equipped then "danger" else "buy", function()
					actionRemote:FireServer("Aura", if equipped then "" else a.Id)
				end)
			else
				local lk = UITheme.Text(card, string.format("🔒 Nivel %d", a.Need), 13, Color3.fromRGB(165, 165, 180), UDim2.new(1, -164, 0, 28), UDim2.fromOffset(150, 30), Enum.TextXAlignment.Center)
				lk.TextStrokeTransparency = 1
			end
		end
		scroll.CanvasSize = UDim2.fromOffset(0, 8 + #shown * cardH)
	end
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
	if name == "Milestones" then
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
build()
