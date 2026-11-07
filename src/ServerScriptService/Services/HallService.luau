--!strict
--[[
    HallService (ModuleScript) -> ServerScriptService.Services.HallService
    SALÓN DE HONOR del edificio principal de cada ciudad (Ayuntamiento / Sala del Consejo / Torre del Líder / Gremio de Tripulaciones /
    Cuartel de Divisiones: el NPCSlot con Role "Clanes").
      - Decora el interior (alfombra, columnas, lámparas, estandartes, braseros) y pone un SECRETARIO NPC que abre la ventana del Gremio.
      - Dos CARTELES de ranking GLOBAL de todos los jugadores de esa facción (no solo del servidor):
          · NIVEL  -> OrderedDataStore "HallLevel_v1_<Facción>" (se actualiza al salir y cada pocos minutos).
          · DAÑO   -> OrderedDataStore "HallDmg_v1_<Facción>" (mejor prueba de 30 s en un maniquí). Récord personal en el perfil ("Hall").
        Se leen cada ~60 s y se mezclan con los jugadores conectados para que se vea en vivo.
      - 4 MANIQUÍES DE ENTRENAMIENTO por salón: el primer golpe abre una prueba de 30 s; al terminar muestra el daño total y los DPS.
        Los maniquíes son objetivos normales (tag Targetable, IsMob) con vida enorme que se rellena: nunca mueren ni dan recompensas.
    Remote: HallOpen (servidor -> cliente): abre la ventana del Gremio (HallClient). Sin acceso a DataStore (Studio) funciona solo con los
    jugadores conectados y avisa por consola.
]]
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local DamageService = require(Services.DamageService)
local StatService = require(Services.StatService)
local NpcBuilder = require(Services.NpcBuilder)

local OpenRemote = Net.Get("HallOpen")
local NotifyRemote = Net.Get("Notify")

local TEST_SECONDS = 30
local COOLDOWN = 2
local REFRESH_SECONDS = 60
local LEVEL_FLUSH_SECONDS = 180
local TOP = 10
local USE_DISTANCE = 16

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

type Theme = { Primary: Color3, Secondary: Color3, Glow: Color3, Emblem: string, Name: string }
local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local THEMES: { [string]: Theme } = {
	Saiyan = { Primary = c(214, 128, 52), Secondary = c(30, 40, 90), Glow = c(255, 220, 120), Emblem = "⭐", Name = "Imperio Saiyan" },
	Shinobi = { Primary = c(74, 130, 96), Secondary = c(34, 40, 60), Glow = c(150, 235, 170), Emblem = "🍃", Name = "Alianza Shinobi" },
	Pirate = { Primary = c(160, 44, 52), Secondary = c(60, 44, 34), Glow = c(255, 200, 100), Emblem = "☠️", Name = "Flota Pirata" },
	Shinigami = { Primary = c(96, 80, 170), Secondary = c(24, 24, 36), Glow = c(170, 200, 255), Emblem = "⚔️", Name = "Corte Shinigami" },
}
local GOLD = c(240, 196, 90)

local HallService = {}

---------------------------------------------------------------------
-- DATOS: ranking global
---------------------------------------------------------------------
type Entry = { UserId: number, Name: string, Value: number }
type Rows = { { Rank: TextLabel, Name: TextLabel, Value: TextLabel } }
type Hall = { Faction: string, LevelRows: Rows, DmgRows: Rows, Podium: ({ Entry }) -> () }

local halls: { [string]: Hall } = {}
local levelStores: { [string]: OrderedDataStore? } = {}
local dmgStores: { [string]: OrderedDataStore? } = {}
local nameCache: { [number]: string } = {}
local best: { [Player]: number } = {}
local lastLevelWritten: { [Player]: number } = {}
local lastDmgWritten: { [Player]: number } = {}
local warnedNoStore = false

for faction in pairs(THEMES) do
	local okL, sL = pcall(function()
		return DataStoreService:GetOrderedDataStore("HallLevel_v1_" .. faction)
	end)
	local okD, sD = pcall(function()
		return DataStoreService:GetOrderedDataStore("HallDmg_v1_" .. faction)
	end)
	levelStores[faction] = if okL then sL else nil
	dmgStores[faction] = if okD then sD else nil
end

local function nameOf(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local pl = Players:GetPlayerByUserId(userId)
	if pl then
		nameCache[userId] = pl.DisplayName
		return pl.DisplayName
	end
	local ok, n = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(n) == "string" then n else ("Jugador " .. tostring(userId))
	nameCache[userId] = name
	return name
end

local function fetchTop(store: OrderedDataStore?): { Entry }
	local out: { Entry } = {}
	if not store then
		return out
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, TOP):GetCurrentPage()
	end)
	if not ok then
		if not warnedNoStore then
			warnedNoStore = true
			warn("[HallService] Sin acceso a DataStore: el ranking global solo muestra a los jugadores conectados.")
		end
		return out
	end
	for _, item in ipairs(page :: any) do
		local uid = tonumber(item.key)
		if uid and typeof(item.value) == "number" then
			table.insert(out, { UserId = uid, Name = "", Value = item.value })
		end
	end
	return out
end

local function merge(list: { Entry }, live: { [number]: number }): { Entry }
	local byId: { [number]: Entry } = {}
	for _, e in ipairs(list) do
		byId[e.UserId] = e
	end
	for uid, v in pairs(live) do
		local e = byId[uid]
		if e then
			if v > e.Value or live[uid] ~= nil then
				e.Value = math.max(v, 0)
			end
		else
			byId[uid] = { UserId = uid, Name = "", Value = v }
		end
	end
	local arr: { Entry } = {}
	for _, e in pairs(byId) do
		if e.Value > 0 then
			table.insert(arr, e)
		end
	end
	table.sort(arr, function(a, b)
		if a.Value ~= b.Value then
			return a.Value > b.Value
		end
		return a.UserId < b.UserId
	end)
	while #arr > TOP do
		table.remove(arr)
	end
	for _, e in ipairs(arr) do
		e.Name = nameOf(e.UserId)
	end
	return arr
end

local MEDAL = { c(255, 215, 90), c(214, 220, 232), c(214, 144, 96) }
local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function paint(rows: Rows, list: { Entry }, asDamage: boolean)
	for i, r in ipairs(rows) do
		local e = list[i]
		if e then
			r.Rank.Text = tostring(i)
			r.Name.Text = e.Name
			r.Value.Text = if asDamage then fmt(e.Value) else ("Nv. " .. tostring(e.Value))
			r.Name.TextColor3 = if i <= 3 then MEDAL[i] else c(235, 238, 245)
			r.Rank.TextColor3 = if i <= 3 then MEDAL[i] else c(170, 176, 196)
		else
			r.Rank.Text = tostring(i)
			r.Name.Text = "—"
			r.Value.Text = ""
			r.Name.TextColor3 = c(110, 116, 136)
			r.Rank.TextColor3 = c(110, 116, 136)
		end
	end
end

local function refreshFaction(faction: string)
	local hall = halls[faction]
	if not hall then
		return
	end
	local liveLevel: { [number]: number } = {}
	local liveDmg: { [number]: number } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl:GetAttribute("Faction") == faction then
			liveLevel[pl.UserId] = StatService.GetLevel(pl)
			local b = best[pl]
			if b and b > 0 then
				liveDmg[pl.UserId] = b
			end
		end
	end
	paint(hall.LevelRows, merge(fetchTop(levelStores[faction]), liveLevel), false)
	local dmgList = merge(fetchTop(dmgStores[faction]), liveDmg)
	paint(hall.DmgRows, dmgList, true)
	hall.Podium(dmgList)
end

local function writeLevel(pl: Player)
	local f = pl:GetAttribute("Faction")
	local store = if typeof(f) == "string" then levelStores[f] else nil
	if not store then
		return
	end
	local lv = StatService.GetLevel(pl)
	if lv <= 0 or lastLevelWritten[pl] == lv then
		return
	end
	local ok = pcall(function()
		store:SetAsync(tostring(pl.UserId), lv)
	end)
	if ok then
		lastLevelWritten[pl] = lv
	end
end

local function writeDmg(pl: Player)
	local f = pl:GetAttribute("Faction")
	local store = if typeof(f) == "string" then dmgStores[f] else nil
	local b = best[pl]
	if not store or not b or b <= 0 or lastDmgWritten[pl] == b then
		return
	end
	local ok = pcall(function()
		store:SetAsync(tostring(pl.UserId), math.floor(b))
	end)
	if ok then
		lastDmgWritten[pl] = b
	end
end

---------------------------------------------------------------------
-- MANIQUÍES: pruebas de 30 s
---------------------------------------------------------------------
type Session = { Dummy: Model, Start: number, Total: number }
local sessions: { [Player]: Session } = {}
local cooldown: { [Player]: number } = {}
type DummyUi = { Title: TextLabel, Sub: TextLabel, Reset: number }
local dummyUi: { [Model]: DummyUi } = {}

local function notify(pl: Player, text: string)
	NotifyRemote:FireClient(pl, text)
end

local function setIdle(ui: DummyUi)
	ui.Title.Text = "🎯 MANIQUÍ DE ENTRENAMIENTO"
	ui.Sub.Text = "Golpéame: prueba de " .. TEST_SECONDS .. " s"
	ui.Title.TextColor3 = c(255, 236, 170)
end

local function finish(pl: Player)
	local s = sessions[pl]
	if not s then
		return
	end
	sessions[pl] = nil
	cooldown[pl] = os.clock() + COOLDOWN
	local total = math.floor(s.Total)
	local dps = math.floor(total / TEST_SECONDS)
	local ui = dummyUi[s.Dummy]
	local record = total > (best[pl] or 0)
	if record then
		best[pl] = total
		task.spawn(writeDmg, pl)
	end
	notify(pl, string.format("🎯 Prueba terminada: %s de daño en %d s (%s DPS)%s", fmt(total), TEST_SECONDS, fmt(dps), if record then " · ¡NUEVO RÉCORD!" else ""))
	if ui then
		ui.Title.Text = (if record then "🏆 RÉCORD de " else "Resultado de ") .. pl.DisplayName
		ui.Title.TextColor3 = if record then GOLD else c(190, 255, 200)
		ui.Sub.Text = fmt(total) .. " · " .. fmt(dps) .. " DPS"
		ui.Reset = os.clock() + 7
	end
end

DamageService.AddDamageListener(function(mob: Model, player: Player, amount: number)
	if mob:GetAttribute("HallDummy") ~= true then
		return
	end
	local hum = mob:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth
	end
	local now = os.clock()
	local s = sessions[player]
	if s and now - s.Start >= TEST_SECONDS then
		finish(player)
		s = nil
	end
	if not s then
		if (cooldown[player] or 0) > now then
			return
		end
		local ui = dummyUi[mob]
		if ui and ui.Reset > now and ui.Sub.Text ~= "" and ui.Title.Text:find("Prueba") == nil then
			-- se está mostrando un resultado: se pisa con la nueva prueba
			ui.Reset = 0
		end
		s = { Dummy = mob, Start = now, Total = 0 }
		sessions[player] = s
		notify(player, "🎯 ¡Prueba iniciada! Tienes " .. TEST_SECONDS .. " s: pega con todo.")
	end
	if (s :: Session).Dummy ~= mob then
		return
	end
	(s :: Session).Total += amount
end)

task.spawn(function()
	while true do
		task.wait(0.25)
		local now = os.clock()
		for pl, s in pairs(sessions) do
			if not pl.Parent then
				sessions[pl] = nil
			elseif now - s.Start >= TEST_SECONDS then
				finish(pl)
			else
				local ui = dummyUi[s.Dummy]
				if ui then
					ui.Title.Text = string.format("⏱ %d s · %s", math.ceil(TEST_SECONDS - (now - s.Start)), pl.DisplayName)
					ui.Title.TextColor3 = c(255, 236, 170)
					ui.Sub.Text = "💥 " .. fmt(s.Total) .. " de daño"
				end
			end
		end
		for mob, ui in pairs(dummyUi) do
			if ui.Reset > 0 and now >= ui.Reset then
				ui.Reset = 0
				local busy = false
				for _, s in pairs(sessions) do
					if s.Dummy == mob then
						busy = true
					end
				end
				if not busy then
					setIdle(ui)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- CONSTRUCCIÓN DEL SALÓN
---------------------------------------------------------------------
local function newPart(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CanCollide = collide == true
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function addLight(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Parent = p
end

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, font: Enum.Font, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = true
	l.TextWrapped = false
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

-- cartel de ranking: marco, panel oscuro y 10 filas (BW = ancho del marco en studs)
local CANVAS_W, CANVAS_H = 910, 710
local function buildBoard(parent: Instance, bcf: CFrame, x: number, y: number, z: number, BW: number, th: Theme, title: string, subtitle: string, valueHeader: string): (Rows, number)
	local pw = BW - 1.4
	local ph = pw * CANVAS_H / CANVAS_W
	local function at(dx: number, dy: number, dz: number): CFrame
		return bcf * CFrame.new(x + dx, y + dy, z + dz)
	end
	newPart(parent, "CartelMarco", Vector3.new(BW, ph + 1.4, 0.7), at(0, 0, 0.1), GOLD, Enum.Material.Metal)
	newPart(parent, "CartelMarcoInt", Vector3.new(pw + 0.6, ph + 0.6, 0.8), at(0, 0, 0), th.Primary, Enum.Material.Metal)
	local panel = newPart(parent, "CartelPanel", Vector3.new(pw, ph, 0.9), at(0, 0, -0.05), c(16, 18, 28), Enum.Material.SmoothPlastic)
	local glow = newPart(parent, "CartelNeon", Vector3.new(BW + 0.4, 0.3, 0.3), at(0, ph / 2 + 0.95, -0.3), th.Glow, Enum.Material.Neon)
	glow.Transparency = 0.25
	addLight(glow, th.Glow, 18, 0.35)
	local glow2 = newPart(parent, "CartelNeon", Vector3.new(BW + 0.4, 0.3, 0.3), at(0, -ph / 2 - 0.95, -0.3), th.Glow, Enum.Material.Neon)
	glow2.Transparency = 0.25
	for _, sx in ipairs({ -BW / 2, BW / 2 }) do
		for _, sy in ipairs({ -ph / 2 - 0.7, ph / 2 + 0.7 }) do
			newPart(parent, "CartelEsquina", Vector3.new(1.2, 1.2, 1), at(sx, sy, -0.3), GOLD, Enum.Material.Metal, false, Enum.PartType.Ball)
		end
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS_W, CANVAS_H)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = panel
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = c(14, 16, 26)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(c(30, 34, 54), c(12, 14, 22))
	grad.Parent = bg
	label(bg, title, UDim2.fromOffset(880, 70), UDim2.fromOffset(15, 6), Enum.Font.Fantasy, th.Glow)
	label(bg, subtitle, UDim2.fromOffset(880, 26), UDim2.fromOffset(15, 74), Enum.Font.GothamBold, c(190, 196, 220))
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(860, 3)
	line.Position = UDim2.fromOffset(25, 104)
	line.BackgroundColor3 = GOLD
	line.BorderSizePixel = 0
	line.Parent = bg
	label(bg, "#", UDim2.fromOffset(70, 26), UDim2.fromOffset(25, 110), Enum.Font.GothamBold, c(170, 176, 200))
	label(bg, "JUGADOR", UDim2.fromOffset(420, 26), UDim2.fromOffset(110, 110), Enum.Font.GothamBold, c(170, 176, 200), Enum.TextXAlignment.Left)
	label(bg, valueHeader, UDim2.fromOffset(300, 26), UDim2.fromOffset(590, 110), Enum.Font.GothamBold, c(170, 176, 200), Enum.TextXAlignment.Right)
	local rows: Rows = {}
	for i = 1, TOP do
		local rowY = 140 + (i - 1) * 54
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(20, rowY)
		row.Size = UDim2.fromOffset(870, 50)
		row.BackgroundColor3 = if i % 2 == 0 then c(26, 30, 46) else c(20, 23, 36)
		row.BorderSizePixel = 0
		row.Parent = bg
		if i <= 3 then
			local bar = Instance.new("Frame")
			bar.Size = UDim2.fromOffset(8, 50)
			bar.BackgroundColor3 = MEDAL[i]
			bar.BorderSizePixel = 0
			bar.Parent = row
		end
		local rk = label(row, tostring(i), UDim2.fromOffset(70, 44), UDim2.fromOffset(10, 3), Enum.Font.GothamBlack, c(170, 176, 196))
		local nm = label(row, "—", UDim2.fromOffset(470, 44), UDim2.fromOffset(95, 3), Enum.Font.GothamBlack, c(110, 116, 136), Enum.TextXAlignment.Left)
		local vl = label(row, "", UDim2.fromOffset(280, 44), UDim2.fromOffset(575, 3), Enum.Font.GothamBlack, th.Glow, Enum.TextXAlignment.Right)
		table.insert(rows, { Rank = rk, Name = nm, Value = vl })
	end
	label(bg, "Ranking global de toda la facción · se actualiza cada minuto", UDim2.fromOffset(880, 22), UDim2.fromOffset(15, 684), Enum.Font.Gotham, c(140, 146, 170))
	return rows, ph
end

local function buildDummy(parent: Instance, bcf: CFrame, x: number, z: number, th: Theme, index: number): Model
	local m = Instance.new("Model")
	m.Name = "ManiquiEntrenamiento" .. index
	local function at(dx: number, dy: number, dz: number): CFrame
		return bcf * CFrame.new(x + dx, dy, z + dz)
	end
	local straw = c(222, 188, 120)
	local wood = c(110, 76, 46)
	local root = newPart(m, "HumanoidRootPart", Vector3.new(3.6, 9, 3.2), at(0, 5.1, 0), th.Primary, Enum.Material.SmoothPlastic, true)
	root.Transparency = 1
	m.PrimaryPart = root
	-- base de piedra con anillo luminoso
	newPart(m, "Base", Vector3.new(0.7, 7.4, 7.4), at(0, 0.65, 0) * CFrame.Angles(0, 0, math.rad(90)), c(70, 68, 78), Enum.Material.Slate, false, Enum.PartType.Cylinder)
	local ring = newPart(m, "Anillo", Vector3.new(0.2, 7.8, 7.8), at(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)), th.Glow, Enum.Material.Neon, false, Enum.PartType.Cylinder)
	ring.Transparency = 0.35
	-- poste, brazos de madera, saco relleno, cabeza
	newPart(m, "Poste", Vector3.new(1.3, 8, 1.3), at(0, 5, 0.9), wood, Enum.Material.Wood)
	newPart(m, "Brazos", Vector3.new(6.4, 0.9, 1), at(0, 6.3, 0.2), wood, Enum.Material.Wood)
	newPart(m, "Saco", Vector3.new(3.2, 4, 2.2), at(0, 4.9, 0), straw, Enum.Material.Fabric)
	newPart(m, "Cinturon", Vector3.new(3.4, 0.5, 2.4), at(0, 3.4, 0), th.Primary, Enum.Material.Fabric)
	newPart(m, "Cabeza", Vector3.new(2.5, 2.5, 2.5), at(0, 8, 0), straw, Enum.Material.Fabric, false, Enum.PartType.Ball)
	newPart(m, "Pañuelo", Vector3.new(2.7, 0.6, 2.7), at(0, 7.4, 0), th.Primary, Enum.Material.Fabric)
	-- diana en el pecho (anillos concéntricos)
	local function disc(name: string, d: number, dz: number, color: Color3, mat: Enum.Material)
		newPart(m, name, Vector3.new(0.18, d, d), at(0, 5.2, -1.12 - dz) * CFrame.Angles(0, math.rad(90), 0), color, mat, false, Enum.PartType.Cylinder)
	end
	disc("DianaA", 2.8, 0, c(240, 240, 240), Enum.Material.SmoothPlastic)
	disc("DianaB", 2.0, 0.05, c(214, 50, 56), Enum.Material.SmoothPlastic)
	disc("DianaC", 1.2, 0.1, c(240, 240, 240), Enum.Material.SmoothPlastic)
	disc("DianaD", 0.5, 0.15, c(214, 50, 56), Enum.Material.Neon)
	-- cuerda y cartel
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 1e9
	hum.Health = 1e9
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = m
	hum.HealthChanged:Connect(function(h)
		if h < hum.MaxHealth then
			hum.Health = hum.MaxHealth
		end
	end)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(250, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 7.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 70
	bb.Parent = m
	local title = label(bb, "", UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, c(255, 236, 170))
	title.TextStrokeTransparency = 0.3
	local sub = label(bb, "", UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), Enum.Font.GothamBold, c(255, 255, 255))
	sub.TextStrokeTransparency = 0.4
	local ui: DummyUi = { Title = title, Sub = sub, Reset = 0 }
	dummyUi[m] = ui
	setIdle(ui)
	m:SetAttribute("IsMob", true)
	m:SetAttribute("HallDummy", true)
	m:SetAttribute("Level", 1)
	m:SetAttribute("DisplayName", "Maniquí de entrenamiento")
	m:SetAttribute("MaxHp", 1e9)
	m:SetAttribute("Boss", false)
	CollectionService:AddTag(m, "Targetable")
	m.Parent = parent
	return m
end

local function buildSecretary(model: Model, marker: BasePart, bcf: CFrame, faction: string, th: Theme, floorY: number)
	local pos = Vector3.new(marker.Position.X, floorY + 0.3 + 3.05, marker.Position.Z)
	local look = bcf.LookVector
	local rig, head = NpcBuilder.Person("Mayordomo", faction, CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
	rig.Name = "SecretarioGremio_" .. faction
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(280, 46)
	gui.StudsOffset = Vector3.new(0, 5.4, 0)
	gui.MaxDistance = 70
	gui.Parent = head
	local n = label(gui, "Secretario del Gremio", UDim2.fromScale(1, 0.55), UDim2.fromScale(0, 0), Enum.Font.GothamBold, th.Glow)
	n.TextStrokeTransparency = 0.4
	local t = label(gui, th.Emblem .. " " .. th.Name .. " · Bendiciones y honor", UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0.55), Enum.Font.Gotham, Color3.new(1, 1, 1))
	t.TextStrokeTransparency = 0.5
	rig.Parent = model
	local root = rig.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Abrir el Gremio"
	prompt.ObjectText = "Secretario del Gremio"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		local pr = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pr or (pr.Position - root.Position).Magnitude > USE_DISTANCE then
			return
		end
		OpenRemote:FireClient(player)
	end)
end

local function makeFigure(userId: number): Model?
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromUserId(userId)
	end)
	if not ok or not m then
		return nil
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	return m
end

-- PODIO: figuras (avatares reales) de los 3 mejores de DAÑO, con su nombre
local function buildPodium(folder: Instance, bcf: CFrame, z: number, th: Theme): ({ Entry }) -> ()
	local dais = newPart(folder, "PodioBase", Vector3.new(0.8, 22, 22), bcf * CFrame.new(0, 0.8, z) * CFrame.Angles(0, 0, math.rad(90)), c(30, 30, 40), Enum.Material.Marble, true, Enum.PartType.Cylinder)
	local ringD = newPart(folder, "PodioAro", Vector3.new(0.3, 22.8, 22.8), bcf * CFrame.new(0, 1.25, z) * CFrame.Angles(0, 0, math.rad(90)), th.Glow, Enum.Material.Neon, false, Enum.PartType.Cylinder)
	ringD.Transparency = 0.3
	addLight(dais, th.Glow, 22, 0.5)
	local spots = {
		{ X = 0, H = 4.2, Color = MEDAL[1], Medal = "🥇" },
		{ X = -6.4, H = 2.8, Color = MEDAL[2], Medal = "🥈" },
		{ X = 6.4, H = 1.8, Color = MEDAL[3], Medal = "🥉" },
	}
	local nameLabels: { TextLabel } = {}
	local valueLabels: { TextLabel } = {}
	local figures: { Model? } = {}
	for i, sp in ipairs(spots) do
		local top = 1.2 + sp.H
		local block = newPart(folder, "PodioPuesto" .. i, Vector3.new(5.4, sp.H, 5.4), bcf * CFrame.new(sp.X, 1.2 + sp.H / 2, z), sp.Color, Enum.Material.Metal, true)
		newPart(folder, "PodioBorde" .. i, Vector3.new(5.8, 0.3, 5.8), bcf * CFrame.new(sp.X, top, z), GOLD, Enum.Material.Metal, false)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.Parent = block
		label(sg, tostring(i), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, c(30, 30, 40))
		local anchor = newPart(folder, "PodioAncla" .. i, Vector3.new(1, 1, 1), bcf * CFrame.new(sp.X, top + 8.6, z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		anchor.Transparency = 1
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(300, 70)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 90
		bb.Adornee = anchor
		bb.Parent = anchor
		local nm = label(bb, sp.Medal .. " —", UDim2.fromScale(1, 0.58), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, sp.Color)
		nm.TextStrokeTransparency = 0.2
		local vl = label(bb, "", UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0.58), Enum.Font.GothamBold, Color3.new(1, 1, 1))
		vl.TextStrokeTransparency = 0.3
		nameLabels[i] = nm
		valueLabels[i] = vl
	end
	local curKey = ""
	return function(list: { Entry })
		local ids: { string } = {}
		for i = 1, 3 do
			table.insert(ids, if list[i] then tostring(list[i].UserId) .. ":" .. tostring(list[i].Value) else "-")
		end
		local key = table.concat(ids, ",")
		if key == curKey then
			return
		end
		curKey = key
		for i, sp in ipairs(spots) do
			local e = list[i]
			nameLabels[i].Text = sp.Medal .. " " .. (if e then e.Name else "—")
			valueLabels[i].Text = if e then fmt(e.Value) .. " de daño" else ""
			local old = figures[i]
			if old then
				old:Destroy()
				figures[i] = nil
			end
			if e then
				local uid = e.UserId
				task.spawn(function()
					local f = makeFigure(uid)
					if not f then
						return
					end
					if curKey ~= key or figures[i] then
						f:Destroy()
						return
					end
					f.Name = "PodioFigura" .. i
					f.Parent = folder
					f:PivotTo(bcf * CFrame.new(sp.X, 1.2 + sp.H + 4, z))
					local bbCf, bbSize = f:GetBoundingBox()
					local bottom = bbCf.Position.Y - bbSize.Y / 2
					f:PivotTo(f:GetPivot() + Vector3.new(0, bcf.Position.Y + 1.2 + sp.H + 0.15 - bottom, 0))
					figures[i] = f
				end)
			end
		end
	end
end

local function buildHall(model: Model, marker: BasePart, faction: string)
	local th = THEMES[faction]
	if not th or halls[faction] then
		return
	end
	local roof = model:FindFirstChild("Techo")
	local lot = model:FindFirstChild("Parcela")
	local bcf: CFrame
	local floorY: number
	local W, D, H: number
	if roof and roof:IsA("BasePart") and lot and lot:IsA("BasePart") then
		floorY = lot.Position.Y - 0.15
		local rcf = roof.CFrame
		bcf = CFrame.fromMatrix(Vector3.new(rcf.Position.X, floorY, rcf.Position.Z), rcf.XVector, rcf.YVector, rcf.ZVector)
		W, D = roof.Size.X - 4, roof.Size.Z - 4
		H = roof.Position.Y - floorY - 0.6
	else
		-- respaldo: marco derivado del marcador del NPC (z local = -D/2 + 10.5 = -25.5) y tamaño de la pared trasera
		local back = model:FindFirstChild("Pared_Trasera")
		if not back or not back:IsA("BasePart") then
			warn("[HallService] Sin Techo/Parcela ni Pared_Trasera en " .. model.Name)
			return
		end
		floorY = marker.Position.Y
		bcf = marker.CFrame * CFrame.new(0, 0, 25.5)
		W, H = back.Size.X, back.Size.Y
		D = 72
	end
	local backZ = D / 2 - 3.6
	local halfW = W / 2 - 1.5
	local folder = Instance.new("Folder")
	folder.Name = "SalonDeHonor"
	folder.Parent = model
	local function at(x: number, y: number, z: number): CFrame
		return bcf * CFrame.new(x, y, z)
	end
	local dark = th.Secondary:Lerp(Color3.new(0, 0, 0), 0.35)
	local wallMat = if faction == "Pirate" then Enum.Material.WoodPlanks else Enum.Material.Slate

	-- PAREDES OSCURAS por dentro y techo oscuro (evita el blanco brillante)
	local sideLen = 22
	local fl = model:FindFirstChild("Frente_Izquierdo")
	if fl and fl:IsA("BasePart") then
		sideLen = fl.Size.X
	end
	local op = W - 2 * sideLen
	newPart(folder, "RevestimientoIzq", Vector3.new(0.8, H - 0.6, D - 3), at(-halfW + 0.4, H / 2 + 0.1, 0), dark, wallMat)
	newPart(folder, "RevestimientoDer", Vector3.new(0.8, H - 0.6, D - 3), at(halfW - 0.4, H / 2 + 0.1, 0), dark, wallMat)
	newPart(folder, "RevestimientoFondo", Vector3.new(W - 3, H - 0.6, 0.8), at(0, H / 2 + 0.1, D / 2 - 1.9), dark, wallMat)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(folder, "RevestimientoFrente", Vector3.new(sideLen - 1.5, H - 0.6, 0.8), at(sx * (op / 2 + (sideLen - 1.5) / 2), H / 2 + 0.1, -D / 2 + 1.9), dark, wallMat)
	end
	newPart(folder, "RevestimientoDintel", Vector3.new(op, H - H * 0.62 - 0.6, 0.8), at(0, H * 0.62 + (H - H * 0.62) / 2 - 0.2, -D / 2 + 1.9), dark, wallMat)
	newPart(folder, "Cielorraso", Vector3.new(W - 3, 0.6, D - 3), at(0, H - 0.3, 0), dark:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(folder, "ZocaloOro", Vector3.new(0.5, 0.8, D - 3), at(sx * (halfW - 0.9), 1.2, 0), GOLD, Enum.Material.Metal)
		newPart(folder, "FrisoOro", Vector3.new(0.5, 0.5, D - 3), at(sx * (halfW - 0.9), H - 2.2, 0), GOLD, Enum.Material.Metal)
	end
	newPart(folder, "ZocaloFondo", Vector3.new(W - 3, 0.8, 0.5), at(0, 1.2, D / 2 - 2.3), GOLD, Enum.Material.Metal)
	newPart(folder, "FrisoFondo", Vector3.new(W - 3, 0.5, 0.5), at(0, H - 2.2, D / 2 - 2.3), GOLD, Enum.Material.Metal)

	-- SUELO y ALFOMBRA
	newPart(folder, "Suelo", Vector3.new(W - 4, 0.2, D - 4), at(0, 0.42, 0), th.Secondary:Lerp(c(120, 120, 130), 0.2), Enum.Material.Marble)
	newPart(folder, "AlfombraBorde", Vector3.new(12.4, 0.14, D - 6), at(0, 0.54, 0), GOLD, Enum.Material.Fabric)
	newPart(folder, "Alfombra", Vector3.new(11, 0.2, D - 7), at(0, 0.58, 0), th.Primary, Enum.Material.Fabric)
	local medal = newPart(folder, "AlfombraEmblema", Vector3.new(9, 0.12, 9), at(0, 0.7, 6), th.Primary:Lerp(Color3.new(1, 1, 1), 0.15), Enum.Material.Fabric)
	local eg = Instance.new("SurfaceGui")
	eg.Face = Enum.NormalId.Top
	eg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	eg.PixelsPerStud = 40
	eg.Parent = medal
	label(eg, th.Emblem, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBlack, Color3.new(1, 1, 1))

	-- CARTELES de ranking (grandes) a los lados del podio
	local BW = 23
	local boardY = 13.2
	local levelRows, ph = buildBoard(folder, bcf, -22, boardY, backZ, BW, th, "🏅 RANKING DE NIVEL", th.Name .. " · los más fuertes de la facción", "NIVEL")
	local dmgRows = buildBoard(folder, bcf, 22, boardY, backZ, BW, th, "💥 RANKING DE DAÑO", "Mejor prueba de " .. TEST_SECONDS .. " s en el maniquí", "DAÑO TOTAL")

	-- PLACA central sobre el podio
	newPart(folder, "PlacaOro", Vector3.new(15.4, 4.6, 0.7), at(0, H - 5.4, backZ), GOLD, Enum.Material.Metal)
	local plate = newPart(folder, "Placa", Vector3.new(14.8, 4, 0.8), at(0, H - 5.4, backZ - 0.05), c(18, 20, 30), Enum.Material.SmoothPlastic)
	local pg = Instance.new("SurfaceGui")
	pg.Face = Enum.NormalId.Front
	pg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	pg.PixelsPerStud = 50
	pg.LightInfluence = 0
	pg.Parent = plate
	label(pg, th.Emblem .. " SALÓN DE HONOR", UDim2.new(1, 0, 0.6, 0), UDim2.fromScale(0, 0.04), Enum.Font.Fantasy, th.Glow)
	label(pg, string.upper(th.Name), UDim2.new(1, 0, 0.28, 0), UDim2.fromScale(0, 0.67), Enum.Font.GothamBold, c(220, 224, 236))

	-- COLUMNAS con aro de luz tenue
	for _, sx in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -22, -8, 6, 20 }) do
			local cx = sx * (halfW - 3.2)
			newPart(folder, "Columna", Vector3.new(2.6, H - 1.5, 2.6), at(cx, (H - 1.5) / 2 + 0.4, z), c(70, 70, 82), Enum.Material.Marble, true)
			newPart(folder, "ColumnaBase", Vector3.new(3.6, 1.2, 3.6), at(cx, 1, z), GOLD, Enum.Material.Metal)
			newPart(folder, "ColumnaCapitel", Vector3.new(3.6, 1.2, 3.6), at(cx, H - 1.6, z), GOLD, Enum.Material.Metal)
			local ringL = newPart(folder, "ColumnaAro", Vector3.new(0.4, 3.2, 3.2), at(cx, 15, z) * CFrame.Angles(0, 0, math.rad(90)), th.Glow, Enum.Material.Neon, false, Enum.PartType.Cylinder)
			ringL.Transparency = 0.45
		end
		-- estandartes en la pared lateral
		for _, z in ipairs({ -15, -1, 13 }) do
			local wx = sx * (halfW - 0.9)
			newPart(folder, "EstandarteVara", Vector3.new(0.4, 0.4, 6.4), at(wx, 19.4, z), GOLD, Enum.Material.Metal)
			newPart(folder, "Estandarte", Vector3.new(0.3, 11, 5.2), at(wx, 13.6, z), th.Primary, Enum.Material.Fabric)
			newPart(folder, "EstandarteBorde", Vector3.new(0.4, 0.8, 5.6), at(wx, 7.9, z), GOLD, Enum.Material.Metal)
			local eb = newPart(folder, "EstandarteEmblema", Vector3.new(0.4, 3.2, 3.2), at(wx - sx * 0.1, 14.6, z), th.Glow, Enum.Material.Neon)
			eb.Transparency = 0.55
		end
		-- braseros junto al podio y a la entrada
		for _, bz in ipairs({ -29, 27 }) do
			local bx = sx * (if bz > 0 then 14.5 else 17)
			newPart(folder, "BraseroPie", Vector3.new(0.8, 3, 3), at(bx, 2, bz) * CFrame.Angles(0, 0, math.rad(90)), c(50, 50, 58), Enum.Material.Metal, false, Enum.PartType.Cylinder)
			newPart(folder, "BraseroCuenco", Vector3.new(1.2, 4, 4), at(bx, 3.8, bz) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, false, Enum.PartType.Cylinder)
			local fireP = newPart(folder, "BraseroFuego", Vector3.new(2, 1, 2), at(bx, 4.6, bz), c(255, 150, 60), Enum.Material.Neon)
			fireP.Transparency = 0.5
			local fire = Instance.new("Fire")
			fire.Size, fire.Heat = 5, 7
			fire.Parent = fireP
			addLight(fireP, c(255, 160, 80), 20, 0.7)
		end
	end

	-- LÁMPARAS colgantes (luz cálida y tenue)
	for _, z in ipairs({ -20, 0, 20 }) do
		for _, dx in ipairs({ -3, 3 }) do
			newPart(folder, "LamparaCadena", Vector3.new(0.2, 4, 0.2), at(dx, H - 2.6, z), c(70, 70, 78), Enum.Material.Metal)
		end
		local ringP = newPart(folder, "LamparaAro", Vector3.new(0.6, 8, 8), at(0, H - 5, z) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, false, Enum.PartType.Cylinder)
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			local fl2 = newPart(folder, "LamparaLlama", Vector3.new(0.7, 0.9, 0.7), at(math.cos(a) * 3.8, H - 4.4, z + math.sin(a) * 3.8), c(255, 214, 140), Enum.Material.Neon, false, Enum.PartType.Ball)
			fl2.Transparency = 0.2
		end
		addLight(ringP, c(255, 220, 160), 34, 0.55)
	end

	-- MANIQUÍES de entrenamiento
	for i, x in ipairs({ -28, -14, 14, 28 }) do
		buildDummy(folder, bcf, x, -6, th, i)
	end
	local trainSign = newPart(folder, "ZonaPrueba", Vector3.new(16, 1.8, 0.4), at(0, 2.8, -12), c(20, 22, 32), Enum.Material.SmoothPlastic)
	local tsg = Instance.new("SurfaceGui")
	tsg.Face = Enum.NormalId.Front
	tsg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tsg.PixelsPerStud = 50
	tsg.Parent = trainSign
	label(tsg, "🎯 ZONA DE PRUEBA DE DAÑO · 30 s", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Enum.Font.GothamBold, th.Glow)
	for _, sx in ipairs({ -1, 1 }) do
		newPart(folder, "ZonaPruebaPata", Vector3.new(0.5, 2.6, 0.5), at(sx * 7.6, 1.6, -12), GOLD, Enum.Material.Metal)
	end

	-- PODIO con los 3 mejores de daño
	local podium = buildPodium(folder, bcf, backZ - 12.5, th)

	-- SECRETARIO NPC
	local okS, errS = pcall(buildSecretary, model, marker, bcf, faction, th, floorY)
	if not okS then
		warn("[HallService] Secretario de " .. faction .. " falló: " .. tostring(errS))
	end

	halls[faction] = { Faction = faction, LevelRows = levelRows, DmgRows = dmgRows, Podium = podium }
	paint(levelRows, {}, false)
	paint(dmgRows, {}, true)
	print("[HallService] Salón de Honor construido: " .. faction)
	task.spawn(refreshFaction, faction)
end

---------------------------------------------------------------------
-- Detección de los edificios (NPCSlot con Role "Clanes")
---------------------------------------------------------------------
local function tryBuild(inst: Instance)
	if not inst:IsA("BasePart") or inst:GetAttribute("Role") ~= "Clanes" then
		return
	end
	local biome = inst:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local model = inst.Parent
	if not faction or not model or not model:IsA("Model") then
		return
	end
	local ok, err = pcall(buildHall, model, inst, faction)
	if not ok then
		warn("[HallService] No se pudo construir el salón de " .. faction .. ": " .. tostring(err))
	end
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		tryBuild(inst)
	end
end
CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	task.defer(tryBuild, inst)
end)
task.spawn(function()
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	scan()
	for _ = 1, 12 do
		task.wait(10)
		scan()
	end
end)

---------------------------------------------------------------------
-- Jugadores y refresco
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Hall", function(player: Player): any?
	local b = best[player]
	if b and b > 0 then
		return { Dmg = math.floor(b) }
	end
	return nil
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = (saved :: any).Hall
	if typeof(raw) == "table" and typeof(raw.Dmg) == "number" and raw.Dmg > 0 then
		best[player] = raw.Dmg
		task.spawn(writeDmg, player)
	end
	task.wait(5)
	writeLevel(player)
end

local function leave(player: Player)
	writeLevel(player)
	sessions[player] = nil
	cooldown[player] = nil
	best[player] = nil
	lastLevelWritten[player] = nil
	lastDmgWritten[player] = nil
end

Players.PlayerAdded:Connect(function(p)
	task.spawn(init, p)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(init, p)
end
Players.PlayerRemoving:Connect(leave)

task.spawn(function()
	while true do
		task.wait(REFRESH_SECONDS)
		for faction in pairs(halls) do
			task.spawn(refreshFaction, faction)
		end
	end
end)
task.spawn(function()
	while true do
		task.wait(LEVEL_FLUSH_SECONDS)
		for _, pl in ipairs(Players:GetPlayers()) do
			task.spawn(writeLevel, pl)
		end
	end
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		writeLevel(pl)
	end
end)

print("[HallService] Listo: salones de honor, rankings y maniquíes.")

return HallService
