--!strict
--[[
    GlobalRankService (ModuleScript) -> ServerScriptService.Services.GlobalRankService
    RANKING GLOBAL DE NIVEL de las 4 facciones (Top 100) + "tu puesto" (solo lo ve el propio jugador).
      - Datos: los mismos OrderedDataStore de nivel que ya usa HallService ("HallLevel_v2_<Facción>"): no hay nada nuevo que migrar.
        Cada 2 min se leen los 100 mejores de cada facción y se mezclan; cada 10 min se lee más profundo (hasta PUESTO_MAX) para saber el puesto de cada jugador.
        Los jugadores conectados cuentan con su nivel actual (no esperan al guardado).
      - Cartel grande en la ciudad: 10 filas, cambia de página solo (1-10, 11-20 ... 91-100) cada pocos segundos. Se coloca con /rankpos (admins).
      - Aviso "Tu puesto: #N" arriba de tu pantalla cuando estás cerca del cartel y ventana con el Top 100 completo (tecla E en el cartel).
    Remote: GlobalRank  (servidor -> cliente: "Me", datos | "Open", datos)   (cliente -> servidor: "Sync" | "Open")
    Para fijar el cartel en su sitio definitivo: pon el CFrame que imprime /rankpos en SPOTS (abajo).
]]
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local DataVersion = require(Services.DataVersion)
local StatService = require(Services.StatService)

local TOP_N = 100
local PAGE_ROWS = 10
local PAGE_SECONDS = 7 -- cada cuánto cambia de página el cartel
local TOP_FETCH_SECONDS = 180
local DEEP_FETCH_SECONDS = 900
local DEEP_PER_FACTION = 300 -- hasta qué puesto se mira en cada facción para calcular "tu puesto" (4 x 300 = 1200); sube si hace falta, gasta más cuota de DataStore
local PAGE_WAIT = 5 -- pausa entre lecturas del DataStore (cuota baja de GetSortedAsync)
local ME_PUSH_SECONDS = 30
local BOARD_TAG = "GlobalRankBoard"

-- Posiciones fijas del cartel por facción (la ciudad de esa facción). Pega aquí lo que imprime /rankpos:
--   SPOTS.Saiyan = CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x2, y, z2))
local SPOTS: { [string]: CFrame? } = {
	Saiyan = CFrame.lookAt(Vector3.new(-145.9, 12.0, -1481.2), Vector3.new(-145.1, 12.0, -1481.8)),
	Shinobi = CFrame.lookAt(Vector3.new(-1484.5, 12.0, 141.3), Vector3.new(-1485.0, 12.0, 140.5)),
	Pirate = CFrame.lookAt(Vector3.new(1484.3, 12.0, -145.1), Vector3.new(1484.9, 12.0, -144.3)),
	Shinigami = CFrame.lookAt(Vector3.new(159.0, 12.0, 1476.4), Vector3.new(158.2, 12.0, 1476.9)),
}

local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local FACTION_NAME: { [string]: string } = { Saiyan = "Élite", Shinobi = "Sigilo", Pirate = "Navegantes", Shinigami = "Espíritu" }
local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 190, 90),
	Shinobi = Color3.fromRGB(130, 230, 160),
	Pirate = Color3.fromRGB(255, 120, 110),
	Shinigami = Color3.fromRGB(160, 170, 255),
}
local GOLD = Color3.fromRGB(240, 196, 90)
local MEDAL = { Color3.fromRGB(255, 215, 90), Color3.fromRGB(214, 220, 232), Color3.fromRGB(214, 144, 96) }

local GlobalRankService = {}

-- MODO FANTASMA: el dueño del juego (Fundador) no cuenta en ningún ranking. Ponlo en false para volver a aparecer.
local GHOST_OWNER = true
function GlobalRankService.IsGhostId(userId: number): boolean
	return GHOST_OWNER and game.CreatorType == Enum.CreatorType.User and game.CreatorId > 0 and userId == game.CreatorId
end

type Entry = { UserId: number, Name: string, Level: number, Faction: string }

local stores: { [string]: OrderedDataStore? } = {}
for _, f in ipairs(FACTIONS) do
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore(DataVersion.Name("HallLevel_v2_" .. f))
	end)
	stores[f] = if ok then s else nil
end

local remote = Net.Get("GlobalRank")
local nameCache: { [number]: string } = {}
local topCache: { Entry } = {} -- lo último leído de los DataStore (sin jugadores conectados)
local deepCache: { Entry } = {}
local merged: { Entry } = {} -- mezcla con jugadores conectados, ordenada
local rankOf: { [number]: number } = {}

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

-- lee hasta "pages" páginas de 100 de la tabla de una facción
local function fetchFaction(faction: string, pages: number): { Entry }
	local out: { Entry } = {}
	local store = stores[faction]
	if not store then
		return out
	end
	local ok, pageObj = pcall(function()
		return store:GetSortedAsync(false, 100)
	end)
	if not ok or not pageObj then
		return out
	end
	for p = 1, pages do
		local okP, items = pcall(function()
			return (pageObj :: any):GetCurrentPage()
		end)
		if not okP then
			break
		end
		for _, item in ipairs(items :: any) do
			local uid = tonumber(item.key)
			if uid and typeof(item.value) == "number" and item.value > 0 and not GlobalRankService.IsGhostId(uid) then
				table.insert(out, { UserId = uid, Name = "", Level = item.value, Faction = faction })
			end
		end
		if (pageObj :: any).IsFinished or p == pages then
			break
		end
		task.wait(PAGE_WAIT)
		local okA = pcall(function()
			(pageObj :: any):AdvanceToNextPageAsync()
		end)
		if not okA then
			break
		end
	end
	return out
end

local function sortEntries(list: { Entry })
	table.sort(list, function(a, b)
		if a.Level ~= b.Level then
			return a.Level > b.Level
		end
		return a.UserId < b.UserId
	end)
end

-- mezcla lo leído con los jugadores conectados (su nivel actual manda) y recalcula los puestos
local function rebuild()
	local byId: { [number]: Entry } = {}
	for _, e in ipairs(deepCache) do
		byId[e.UserId] = { UserId = e.UserId, Name = e.Name, Level = e.Level, Faction = e.Faction }
	end
	for _, e in ipairs(topCache) do
		local cur = byId[e.UserId]
		if not cur or e.Level > cur.Level then
			byId[e.UserId] = { UserId = e.UserId, Name = e.Name, Level = e.Level, Faction = e.Faction }
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local f = pl:GetAttribute("Faction")
		if typeof(f) == "string" and FACTION_NAME[f] and pl:GetAttribute("ClassChosen") ~= false and not GlobalRankService.IsGhostId(pl.UserId) then
			local lv = StatService.GetLevel(pl)
			if lv > 0 then
				byId[pl.UserId] = { UserId = pl.UserId, Name = pl.DisplayName, Level = lv, Faction = f }
				nameCache[pl.UserId] = pl.DisplayName
			end
		end
	end
	local arr: { Entry } = {}
	for _, e in pairs(byId) do
		table.insert(arr, e)
	end
	sortEntries(arr)
	local ranks: { [number]: number } = {}
	for i, e in ipairs(arr) do
		ranks[e.UserId] = i
	end
	merged = arr
	rankOf = ranks
end

local function top100(): { Entry }
	local out: { Entry } = {}
	for i = 1, math.min(TOP_N, #merged) do
		local e = merged[i]
		table.insert(out, { UserId = e.UserId, Name = nameOf(e.UserId), Level = e.Level, Faction = e.Faction })
	end
	return out
end

local function myData(pl: Player): any
	local rank = rankOf[pl.UserId]
	local f = pl:GetAttribute("Faction")
	return {
		Ghost = GlobalRankService.IsGhostId(pl.UserId),
		Rank = rank, -- nil = fuera de los puestos que se miden
		Max = DEEP_PER_FACTION * #FACTIONS,
		Level = StatService.GetLevel(pl),
		Faction = if typeof(f) == "string" then f else nil,
	}
end

local function pushMe(pl: Player)
	remote:FireClient(pl, "Me", myData(pl))
end

---------------------------------------------------------------------
-- CARTEL FÍSICO
---------------------------------------------------------------------
local CANVAS_W, CANVAS_H = 1500, 1000
type Row = { Rank: TextLabel, Name: TextLabel, Faction: TextLabel, Level: TextLabel, Bar: Frame }
type Board = { Folder: Folder, Rows: { Row }, PageLabel: TextLabel, Page: number }
local boards: { [string]: Board } = {}

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

local function label(parent: Instance, text: string, size: UDim2, pos: UDim2, font: Enum.Font, color: Color3, align: Enum.TextXAlignment?, fixed: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = pos
	l.Font = font
	l.Text = text
	l.TextColor3 = color
	l.TextScaled = fixed == nil
	if fixed then
		l.TextSize = fixed
		l.TextTruncate = Enum.TextTruncate.AtEnd
	end
	l.TextWrapped = false
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function paintBoard(b: Board)
	local pages = math.max(1, math.ceil(math.min(TOP_N, #merged) / PAGE_ROWS))
	if b.Page > pages then
		b.Page = 1
	end
	local first = (b.Page - 1) * PAGE_ROWS
	for i, r in ipairs(b.Rows) do
		local idx = first + i
		local e = merged[idx]
		if e and idx <= TOP_N then
			r.Rank.Text = tostring(idx)
			r.Name.Text = nameOf(e.UserId)
			r.Faction.Text = string.upper(FACTION_NAME[e.Faction] or e.Faction)
			r.Faction.TextColor3 = FACTION_COLOR[e.Faction] or Color3.new(1, 1, 1)
			r.Level.Text = "Nv. " .. tostring(e.Level)
			r.Name.TextColor3 = if idx <= 3 then MEDAL[idx] else Color3.fromRGB(235, 238, 245)
			r.Rank.TextColor3 = if idx <= 3 then MEDAL[idx] else Color3.fromRGB(170, 176, 196)
			r.Bar.BackgroundColor3 = FACTION_COLOR[e.Faction] or GOLD
			r.Bar.Visible = true
		else
			r.Rank.Text = tostring(idx)
			r.Name.Text = "—"
			r.Faction.Text = ""
			r.Level.Text = ""
			r.Name.TextColor3 = Color3.fromRGB(110, 116, 136)
			r.Rank.TextColor3 = Color3.fromRGB(110, 116, 136)
			r.Bar.Visible = false
		end
	end
	b.PageLabel.Text = string.format("PUESTOS %d - %d   ·   PÁGINA %d / %d", first + 1, first + PAGE_ROWS, b.Page, pages)
end

local function buildBoard(faction: string, base: CFrame): Board
	local old = Workspace:FindFirstChild("RankingGlobal_" .. faction)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "RankingGlobal_" .. faction
	folder.Parent = Workspace
	local BW = 44
	local pw = BW - 1.6
	local ph = pw * CANVAS_H / CANVAS_W
	local cy = ph / 2 + 5 -- centro del cartel (5 studs de patas)
	local function at(dx: number, dy: number, dz: number): CFrame
		return base * CFrame.new(dx, dy, dz)
	end
	for _, sx in ipairs({ -1, 1 }) do
		newPart(folder, "Pata", Vector3.new(3, cy + ph / 2 + 1, 3), at(sx * (BW / 2 - 1), (cy + ph / 2 + 1) / 2, 0.2), Color3.fromRGB(46, 44, 56), Enum.Material.Slate, true)
		newPart(folder, "PataOro", Vector3.new(3.4, 0.6, 3.4), at(sx * (BW / 2 - 1), 0.3, 0.2), GOLD, Enum.Material.Metal, true)
	end
	newPart(folder, "Marco", Vector3.new(BW, ph + 1.6, 0.8), at(0, cy, 0.15), GOLD, Enum.Material.Metal)
	newPart(folder, "MarcoInt", Vector3.new(pw + 0.7, ph + 0.7, 0.9), at(0, cy, 0.05), Color3.fromRGB(34, 38, 66), Enum.Material.Metal)
	local panel = newPart(folder, "Panel", Vector3.new(pw, ph, 1), at(0, cy, -0.05), Color3.fromRGB(16, 18, 28), Enum.Material.SmoothPlastic)
	local neon = newPart(folder, "Neon", Vector3.new(BW + 0.4, 0.35, 0.35), at(0, cy + ph / 2 + 1.1, -0.3), Color3.fromRGB(150, 210, 255), Enum.Material.Neon)
	neon.Transparency = 0.2
	local l1 = Instance.new("PointLight")
	l1.Color, l1.Range, l1.Brightness = Color3.fromRGB(150, 210, 255), 26, 0.5
	l1.Parent = neon
	local neon2 = newPart(folder, "Neon", Vector3.new(BW + 0.4, 0.35, 0.35), at(0, cy - ph / 2 - 1.1, -0.3), Color3.fromRGB(150, 210, 255), Enum.Material.Neon)
	neon2.Transparency = 0.2
	CollectionService:AddTag(panel, BOARD_TAG)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(CANVAS_W, CANVAS_H)
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = panel
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(30, 34, 58), Color3.fromRGB(12, 14, 22))
	grad.Parent = bg
	label(bg, "🏆 RANKING GLOBAL DE NIVEL", UDim2.fromOffset(1460, 96), UDim2.fromOffset(20, 8), Enum.Font.Fantasy, Color3.fromRGB(255, 226, 150))
	local pageLabel = label(bg, "", UDim2.fromOffset(1460, 34), UDim2.fromOffset(20, 108), Enum.Font.GothamBold, Color3.fromRGB(190, 196, 220), nil, 28)
	local line = Instance.new("Frame")
	line.Size = UDim2.fromOffset(1440, 4)
	line.Position = UDim2.fromOffset(30, 150)
	line.BackgroundColor3 = GOLD
	line.BorderSizePixel = 0
	line.Parent = bg
	local hc = Color3.fromRGB(170, 176, 200)
	label(bg, "#", UDim2.fromOffset(110, 30), UDim2.fromOffset(40, 158), Enum.Font.GothamBold, hc, nil, 24)
	label(bg, "JUGADOR", UDim2.fromOffset(600, 30), UDim2.fromOffset(170, 158), Enum.Font.GothamBold, hc, Enum.TextXAlignment.Left, 24)
	label(bg, "FACCIÓN", UDim2.fromOffset(380, 30), UDim2.fromOffset(800, 158), Enum.Font.GothamBold, hc, Enum.TextXAlignment.Left, 24)
	label(bg, "NIVEL", UDim2.fromOffset(280, 30), UDim2.fromOffset(1090, 158), Enum.Font.GothamBold, hc, Enum.TextXAlignment.Right, 24)
	local rows: { Row } = {}
	for i = 1, PAGE_ROWS do
		local rowY = 194 + (i - 1) * 74
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(25, rowY)
		row.Size = UDim2.fromOffset(1400, 68)
		row.BackgroundColor3 = if i % 2 == 0 then Color3.fromRGB(26, 30, 48) else Color3.fromRGB(20, 23, 38)
		row.BorderSizePixel = 0
		row.Parent = bg
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(10, 68)
		bar.BackgroundColor3 = GOLD
		bar.BorderSizePixel = 0
		bar.Parent = row
		local rk = label(row, tostring(i), UDim2.fromOffset(110, 68), UDim2.fromOffset(15, 0), Enum.Font.GothamBlack, hc, nil, 48)
		local nm = label(row, "—", UDim2.fromOffset(620, 68), UDim2.fromOffset(145, 0), Enum.Font.GothamBlack, hc, Enum.TextXAlignment.Left, 46)
		local fc = label(row, "", UDim2.fromOffset(380, 68), UDim2.fromOffset(775, 0), Enum.Font.GothamBlack, hc, Enum.TextXAlignment.Left, 36)
		local lv = label(row, "", UDim2.fromOffset(280, 68), UDim2.fromOffset(1065, 0), Enum.Font.GothamBlack, Color3.fromRGB(255, 226, 150), Enum.TextXAlignment.Right, 46)
		table.insert(rows, { Rank = rk, Name = nm, Faction = fc, Level = lv, Bar = bar })
	end
	label(bg, "Las 4 facciones · se actualiza cada 2 minutos · acércate y pulsa E para ver el Top 100 completo", UDim2.fromOffset(1460, 30), UDim2.fromOffset(20, 950), Enum.Font.Gotham, Color3.fromRGB(140, 146, 170), nil, 24)

	local promptPart = newPart(folder, "Prompt", Vector3.new(6, 4, 3), at(0, 2, -6), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	promptPart.Transparency = 1
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Ver Top 100"
	pp.ObjectText = "Ranking global"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 30
	pp.RequiresLineOfSight = false
	pp.Parent = promptPart
	pp.Triggered:Connect(function(pl: Player)
		remote:FireClient(pl, "Open", { Top = top100(), Me = myData(pl) })
	end)

	local b: Board = { Folder = folder, Rows = rows, PageLabel = pageLabel, Page = 1 }
	paintBoard(b)
	return b
end

-- Coloca (o recoloca) el cartel de la ciudad de esa facción. base = CFrame en el suelo; el frente del cartel mira hacia -Z de base.
function GlobalRankService.PlaceAt(faction: string, base: CFrame)
	if not FACTION_NAME[faction] then
		return
	end
	boards[faction] = buildBoard(faction, base)
end

---------------------------------------------------------------------
-- BUCLES
---------------------------------------------------------------------
local function fetchTop()
	local all: { Entry } = {}
	for _, f in ipairs(FACTIONS) do
		for _, e in ipairs(fetchFaction(f, 1)) do
			table.insert(all, e)
		end
		task.wait(PAGE_WAIT)
	end
	if #all > 0 then
		topCache = all
	end
end

local function fetchDeep()
	local all: { Entry } = {}
	for _, f in ipairs(FACTIONS) do
		for _, e in ipairs(fetchFaction(f, math.ceil(DEEP_PER_FACTION / 100))) do
			table.insert(all, e)
		end
		task.wait(PAGE_WAIT)
	end
	if #all > 0 then
		deepCache = all
	end
end

local function repaintAll()
	rebuild()
	for _, b in pairs(boards) do
		paintBoard(b)
	end
end

task.spawn(function()
	task.wait(75) -- que no coincida con las lecturas de arranque del salón (cuota baja de GetSortedAsync)
	while true do
		fetchTop()
		repaintAll()
		task.wait(TOP_FETCH_SECONDS)
	end
end)
task.spawn(function()
	task.wait(240)
	while true do
		fetchDeep()
		repaintAll()
		task.wait(DEEP_FETCH_SECONDS)
	end
end)
-- páginas del cartel
task.spawn(function()
	while true do
		task.wait(PAGE_SECONDS)
		for _, b in pairs(boards) do
			b.Page += 1
			paintBoard(b)
		end
	end
end)
-- "tu puesto" para cada jugador (con su nivel actual) y repintado con los niveles en vivo
task.spawn(function()
	while true do
		task.wait(ME_PUSH_SECONDS)
		repaintAll()
		for _, pl in ipairs(Players:GetPlayers()) do
			pushMe(pl)
		end
	end
end)

remote.OnServerEvent:Connect(function(pl: Player, what: any)
	if what == "Sync" then
		rebuild()
		pushMe(pl)
	elseif what == "Open" then
		remote:FireClient(pl, "Open", { Top = top100(), Me = myData(pl) })
	end
end)

-- posiciones fijas guardadas en SPOTS
task.spawn(function()
	task.wait(3)
	for faction, cf in pairs(SPOTS) do
		if cf then
			GlobalRankService.PlaceAt(faction, cf)
		end
	end
end)

print("[GlobalRankService] listo (cartel: /rankpos)")

return GlobalRankService
