--!strict
--[[
    GuildService (ModuleScript) -> ServerScriptService.Services.GuildService
    GREMIO DE FACCIÓN (catálogo y números: ReplicatedStorage.Modules.GuildCatalog).
      - Un gremio por facción (Saiyan, Shinobi, Pirate, Shinigami); cada jugador pertenece al de su facción automáticamente.
      - Los jugadores APORTAN oro y materiales a las BENDICIONES (6, hasta nivel 10): pasivas para todos los de la facción.
        Límite diario por jugador (GuildCatalog.DailyCap). Cada aporte suma "puntos de aporte" (PA) a la bendición elegida.
      - El estado del gremio es COMPARTIDO entre todos los servidores: DataStore "FactionGuild_v1" (clave = facción). Los aportes se
        acumulan y se envían cada FLUSH_SECONDS con UpdateAsync (suma segura aunque varios servidores escriban a la vez) y de ahí se lee el
        estado real. Sin acceso a DataStore (Studio sin API) funciona solo en memoria de este servidor y avisa por consola.
      - Las bendiciones entran como fuente "Guild" de GearService (Oro, Xp, Vida, Ataque, Defensa, Suerte).
      - Remotes: GuildAction (cliente -> servidor: "State" | "Donate", bendición, "Gold" | idMaterial, cantidad) · GuildState · GuildResult.
      - Guardado por jugador (sección "Guild" de PlayerData): { Day, Given } = PA aportados hoy (UTC).
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GuildCatalog = require(ReplicatedStorage.Modules.GuildCatalog)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Inventory = require(Services.InventoryService)
local Wallet = require(Services.WalletService)
local GearService = require(Services.GearService)

local StateRemote = Net.Get("GuildState")
local ActionRemote = Net.Get("GuildAction")
local ResultRemote = Net.Get("GuildResult")
local NotifyRemote = Net.Get("Notify")

local FLUSH_SECONDS = 40
local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local STORE_NAME = "FactionGuild_v1"

local GuildService = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result :: DataStore
	end
end

local cache: { [string]: GuildCatalog.State } = {}
local pending: { [string]: GuildCatalog.Delta } = {}
local given: { [Player]: { Day: string, Given: number } } = {}
local lastAction: { [Player]: number } = {}
local lastDonate: { [Player]: number } = {}
local lastPush: { [string]: number } = {}
local warnedNoStore = false

for _, f in ipairs(FACTIONS) do
	cache[f] = GuildCatalog.NewState()
	pending[f] = GuildCatalog.NewDelta()
end

local function today(): string
	return os.date("!%Y-%m-%d") :: string
end

local function factionOf(player: Player): string?
	local f = player:GetAttribute("Faction")
	if typeof(f) == "string" and cache[f] then
		return f
	end
	return nil
end

local function levelOf(player: Player): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

---------------------------------------------------------------------
-- Bendiciones -> estadísticas
---------------------------------------------------------------------
local function applyPassives(player: Player)
	local f = factionOf(player)
	if f then
		local stats = GuildCatalog.StatsFor(cache[f])
		GearService.SetTemp(player, if next(stats) then stats else nil, "Guild")
	end
end

local function applyFaction(f: string)
	for _, pl in ipairs(Players:GetPlayers()) do
		if factionOf(pl) == f then
			applyPassives(pl)
		end
	end
end

---------------------------------------------------------------------
-- Estado hacia los clientes
---------------------------------------------------------------------
local function buildState(player: Player, f: string): any
	local s = cache[f]
	local now = os.time()
	local passives = {}
	for _, p in ipairs(GuildCatalog.Passives) do
		local ps = s.Passives[p.Id]
		local need = if ps.L >= GuildCatalog.MAX_LEVEL then 0 else GuildCatalog.LEVEL_COST[ps.L + 1]
		table.insert(passives, { Id = p.Id, Level = ps.L, Progress = math.floor(ps.P), Need = need })
	end
	local uid = tostring(player.UserId)
	local mine = s.Contrib[uid]
	local wk = GuildCatalog.WeekId(now)
	local g = given[player]
	local usedToday = if g and g.Day == today() then g.Given else 0
	local online = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if factionOf(pl) == f then
			online += 1
		end
	end
	local top = {}
	for _, r in ipairs(GuildCatalog.Ranking(s, true, now, 10)) do
		table.insert(top, { Name = r.Name, Value = r.Week, Mine = r.Uid == uid, Lv = r.Lv, Role = r.Role })
	end
	local topAll = {}
	for _, r in ipairs(GuildCatalog.Ranking(s, false, now, 10)) do
		table.insert(topAll, { Name = r.Name, Value = r.Total, Mine = r.Uid == uid, Lv = r.Lv, Role = r.Role })
	end
	local log = {}
	for i = #s.Log, 1, -1 do
		table.insert(log, { t = s.Log[i].t, m = s.Log[i].m })
	end
	local total = 0
	for _, ps in pairs(s.Passives) do
		total += ps.L
	end
	local mats = {}
	for _, id in ipairs(GuildCatalog.MaterialOrder) do
		local have = Inventory.Count(player, id)
		if have > 0 then
			local it: any = (ItemCatalog.Items :: any)[id]
			table.insert(mats, { Id = id, Name = if it then it.Name else id, Have = have, PA = GuildCatalog.Value[id] })
		end
	end
	return {
		Mats = mats,
		Gold = (player:GetAttribute("Gold") :: any) or 0,
		Faction = f,
		Passives = passives,
		TotalLevels = total,
		MaxTotal = GuildCatalog.MAX_LEVEL * #GuildCatalog.Passives,
		Online = online,
		MineTotal = if mine then mine.T else 0,
		MineWeek = if mine and mine.Wk == wk then mine.W else 0,
		DailyUsed = usedToday,
		DailyCap = GuildCatalog.DailyCap(levelOf(player)),
		Top = top,
		TopAll = topAll,
		Log = log,
		Shared = store ~= nil,
		Now = now,
	}
end

local function pushTo(player: Player)
	local f = factionOf(player)
	if f then
		StateRemote:FireClient(player, buildState(player, f))
	end
end

local function pushFaction(f: string)
	for _, pl in ipairs(Players:GetPlayers()) do
		if factionOf(pl) == f then
			pushTo(pl)
		end
	end
end

---------------------------------------------------------------------
-- Sincronización con el DataStore (compartido entre servidores)
---------------------------------------------------------------------
local function mergeDelta(into: GuildCatalog.Delta, from: GuildCatalog.Delta)
	for id, pa in pairs(from.Pass) do
		into.Pass[id] = (into.Pass[id] or 0) + pa
	end
	for uid, c in pairs(from.Contrib) do
		local e = into.Contrib[uid]
		if e then
			e.PA += c.PA
			e.Name = c.Name
			e.Lv, e.Role = c.Lv, c.Role
		else
			into.Contrib[uid] = { PA = c.PA, Name = c.Name, Lv = c.Lv, Role = c.Role }
		end
	end
	for _, l in ipairs(from.Log) do
		table.insert(into.Log, l)
	end
end

local function isEmpty(d: GuildCatalog.Delta): boolean
	return next(d.Pass) == nil and next(d.Contrib) == nil and #d.Log == 0
end

local function sync(f: string)
	if not store then
		if not warnedNoStore then
			warnedNoStore = true
			warn("[GuildService] Sin acceso a DataStore: el gremio funciona solo en memoria de este servidor (actívalo en Game Settings > Security).")
		end
		-- en memoria: los aportes ya están aplicados en la caché
		pending[f] = GuildCatalog.NewDelta()
		return
	end
	local sent = pending[f]
	pending[f] = GuildCatalog.NewDelta()
	local before = cache[f]
	local levelsBefore: { [string]: number } = {}
	for id, ps in pairs(before.Passives) do
		levelsBefore[id] = ps.L
	end
	local ok, result = pcall(function()
		return (store :: DataStore):UpdateAsync(f, function(old: any)
			local s = GuildCatalog.Sanitize(old)
			if not isEmpty(sent) then
				GuildCatalog.ApplyDelta(s, sent, os.time())
			end
			return s
		end)
	end)
	if not ok or result == nil then
		mergeDelta(pending[f], sent) -- no se perdió nada: se reintenta
		warn("[GuildService] No se pudo sincronizar " .. f .. ": " .. tostring(result))
		return
	end
	local fresh = GuildCatalog.Sanitize(result)
	-- aportes que llegaron mientras se esperaba la respuesta: se vuelven a poner encima del estado real
	GuildCatalog.ApplyDelta(fresh, pending[f], os.time())
	cache[f] = fresh
	for id, ps in pairs(fresh.Passives) do
		if ps.L > (levelsBefore[id] or 0) then
			local def = GuildCatalog.ById[id]
			for _, pl in ipairs(Players:GetPlayers()) do
				if factionOf(pl) == f then
					NotifyRemote:FireClient(pl, string.format("Gremio: ¡%s subió al nivel %d!", if def then def.Name else id, ps.L))
				end
			end
		end
	end
	applyFaction(f)
	pushFaction(f)
end

task.spawn(function()
	while true do
		for _, f in ipairs(FACTIONS) do
			local ok, err = pcall(sync, f)
			if not ok then
				warn("[GuildService] sync " .. f .. ": " .. tostring(err))
			end
			task.wait(1)
		end
		task.wait(FLUSH_SECONDS)
	end
end)

game:BindToClose(function()
	for _, f in ipairs(FACTIONS) do
		if not isEmpty(pending[f]) then
			pcall(sync, f)
		end
	end
end)

---------------------------------------------------------------------
-- Aportar
---------------------------------------------------------------------
local function finite(n: any): boolean
	return typeof(n) == "number" and n == n and n > 0 and n < 1e9
end

local function donate(player: Player, passiveId: any, kind: any, qty: any)
	local f = factionOf(player)
	if not f or not PlayerData.IsReady(player) then
		return
	end
	if typeof(passiveId) ~= "string" or not GuildCatalog.ById[passiveId] or typeof(kind) ~= "string" or not finite(qty) then
		return
	end
	local now = os.clock()
	if now - (lastDonate[player] or 0) < 0.4 then
		return
	end
	lastDonate[player] = now
	local state = cache[f]
	if state.Passives[passiveId].L >= GuildCatalog.MAX_LEVEL then
		reply(player, false, "Esa bendición ya está al nivel máximo.")
		return
	end
	local unit = if kind == "Gold" then 1 else GuildCatalog.Value[kind]
	if not unit then
		return
	end
	local n = math.floor(qty)
	local g = given[player]
	if not g or g.Day ~= today() then
		g = { Day = today(), Given = 0 }
		given[player] = g
	end
	local room = GuildCatalog.DailyCap(levelOf(player)) - g.Given
	if room <= 0 then
		reply(player, false, "Ya llegaste a tu límite de aporte de hoy. Vuelve mañana (00:00 UTC).")
		return
	end
	n = math.min(n, math.floor(room / unit))
	if kind ~= "Gold" then
		n = math.min(n, Inventory.Count(player, kind))
	else
		local have = player:GetAttribute("Gold")
		n = math.min(n, if typeof(have) == "number" then math.floor(have) else 0)
	end
	-- no aportar de más a una bendición que está a punto de completar el último nivel
	local ps = state.Passives[passiveId]
	local missing = 0
	for lv = ps.L + 1, GuildCatalog.MAX_LEVEL do
		missing += GuildCatalog.LEVEL_COST[lv]
	end
	missing -= ps.P
	n = math.min(n, math.ceil(missing / unit))
	if n < 1 then
		reply(player, false, if kind == "Gold" then "No tienes oro suficiente." else "No tienes ese material.")
		return
	end
	local pa = n * unit
	if kind == "Gold" then
		if not Wallet.TrySpendGold(player, n, "Gremio") then
			reply(player, false, "No tienes oro suficiente.")
			return
		end
	elseif not Inventory.Consume(player, kind, n) then
		reply(player, false, "No tienes ese material.")
		return
	end
	g.Given += pa
	pcall(function() -- misiones del Pabellón
		require(Services.MissionService).Report(player, "Donate", pa)
	end)
	-- aplica ya en la caché (el DataStore confirma en el próximo envío)
	local delta = GuildCatalog.NewDelta()
	delta.Pass[passiveId] = pa
	local lvAttr = player:GetAttribute("Level")
	local roleAttr = player:GetAttribute("Role")
	delta.Contrib[tostring(player.UserId)] = {
		PA = pa,
		Name = player.DisplayName,
		Lv = if typeof(lvAttr) == "number" then lvAttr else nil,
		Role = if typeof(roleAttr) == "string" then roleAttr else nil,
	}
	local def = GuildCatalog.ById[passiveId]
	local what = if kind == "Gold" then string.format("%d oro", n) else string.format("%d %s", n, (ItemCatalog.Items :: any)[kind] and (ItemCatalog.Items :: any)[kind].Name or kind)
	if pa >= GuildCatalog.LOG_MIN_PA then
		table.insert(delta.Log, { t = os.time(), m = string.format("%s aportó %s a %s", player.DisplayName, what, def.Name) })
	end
	local events = GuildCatalog.ApplyDelta(state, delta, os.time())
	mergeDelta(pending[f], delta)
	if #events > 0 then
		applyFaction(f)
		for _, pl in ipairs(Players:GetPlayers()) do
			if factionOf(pl) == f then
				NotifyRemote:FireClient(pl, "Gremio: " .. events[1])
			end
		end
	end
	reply(player, true, string.format("Aportaste %s a %s (+%d PA).", what, def.Name, pa))
	PlayerData.Save(player)
	pushFaction(f)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any, c: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.15 then
		return
	end
	lastAction[player] = now
	if action == "State" then
		pushTo(player)
	elseif action == "Donate" then
		donate(player, a, b, c)
	end
end)

---------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Guild", function(player: Player): any?
	local g = given[player]
	if g and g.Given > 0 then
		return { Day = g.Day, Given = g.Given }
	end
	return nil
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = (saved :: any).Guild
	if typeof(raw) == "table" and typeof(raw.Day) == "string" and typeof(raw.Given) == "number" and raw.Day == today() then
		given[player] = { Day = raw.Day, Given = math.max(0, raw.Given) }
	end
	-- esperar a que elija facción
	local waited = 0
	while player.Parent and not factionOf(player) and waited < 120 do
		task.wait(1)
		waited += 1
	end
	applyPassives(player)
	pushTo(player)
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		applyPassives(player)
		pushTo(player)
	end)
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
PlayerData.Releasing:Connect(function(pl: Player)
	given[pl] = nil
	lastAction[pl] = nil
	lastDonate[pl] = nil
end)

return GuildService
