--!strict
--[[
    LevelService (ModuleScript) -> ServerScriptService.Services.LevelService
    ÚNICO dueño del NIVEL y la XP de los jugadores. Nadie más escribe los atributos Level/XP.
      - AddXp(player, cantidad): suma XP y sube de nivel (varios niveles de golpe si hace falta)
      - LosePercent(player, pct): resta % de la XP del nivel actual (nunca baja de nivel)
      - SetLevel(player, nivel): solo para pruebas (DevCommands)
      - Guarda/carga en DataStore (con pcall; en Studio sin API sigue funcionando sin guardar)
    Eventos (BindableEvent): LevelChanged(player, newLevel, oldLevel)
    Fórmula de XP necesaria: GameBalance.XpToNext(nivel)
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Net = require(ServerScriptService.Services.Net)

local XPChanged = Net.Get("XPChanged")
local LevelUpRemote = Net.Get("LevelUp")

local LevelService = {}

local changedEvent = Instance.new("BindableEvent")
LevelService.LevelChanged = changedEvent.Event :: RBXScriptSignal

local STORE_NAME = "PlayerProgress_v1"
local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
end

type Progress = { Level: number, XP: number }
local data: { [Player]: Progress } = {}
local loaded: { [Player]: boolean } = {}

local function push(player: Player)
	local p = data[player]
	if not p then
		return
	end
	player:SetAttribute("Level", p.Level)
	player:SetAttribute("XP", p.XP)
	XPChanged:FireClient(player, p.Level, p.XP, GB.XpToNext(p.Level))
end

function LevelService.GetLevel(player: Player): number
	local p = data[player]
	return if p then p.Level else 1
end

function LevelService.GetXp(player: Player): number
	local p = data[player]
	return if p then p.XP else 0
end

function LevelService.AddXp(player: Player, amount: number)
	local p = data[player]
	if not p or amount <= 0 or p.Level >= GB.MAX_LEVEL then
		return
	end
	local old = p.Level
	p.XP += math.floor(amount)
	while p.Level < GB.MAX_LEVEL and p.XP >= GB.XpToNext(p.Level) do
		p.XP -= GB.XpToNext(p.Level)
		p.Level += 1
	end
	if p.Level >= GB.MAX_LEVEL then
		p.XP = 0
	end
	push(player)
	if p.Level ~= old then
		LevelUpRemote:FireClient(player, p.Level)
		changedEvent:Fire(player, p.Level, old)
	end
end

-- Penalización por muerte: % de la barra del nivel actual. No baja de nivel.
function LevelService.LosePercent(player: Player, pct: number)
	local p = data[player]
	if not p or p.Level < GB.DEATH_PENALTY_MIN_LEVEL or p.Level >= GB.MAX_LEVEL then
		return
	end
	local loss = math.floor(GB.XpToNext(p.Level) * pct)
	p.XP = math.max(0, p.XP - loss)
	push(player)
end

function LevelService.SetLevel(player: Player, level: number)
	local p = data[player]
	if not p then
		return
	end
	local old = p.Level
	p.Level = math.clamp(math.floor(level), 1, GB.MAX_LEVEL)
	p.XP = 0
	push(player)
	if p.Level ~= old then
		changedEvent:Fire(player, p.Level, old)
	end
end

local function load(player: Player)
	local progress: Progress = { Level = 1, XP = 0 }
	if store then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync("P_" .. player.UserId)
		end)
		if ok and typeof(saved) == "table" then
			progress.Level = math.clamp(tonumber(saved.Level) or 1, 1, GB.MAX_LEVEL)
			progress.XP = math.max(0, tonumber(saved.XP) or 0)
		end
	end
	data[player] = progress
	loaded[player] = true
	push(player)
	changedEvent:Fire(player, progress.Level, progress.Level)
end

local function save(player: Player)
	local p = data[player]
	if store and p and loaded[player] then
		pcall(function()
			(store :: DataStore):SetAsync("P_" .. player.UserId, { Level = p.Level, XP = p.XP })
		end)
	end
end

Net.Get("RequestSync").OnServerEvent:Connect(function(pl: Player)
	push(pl) -- el cliente ya está escuchando: reenvía nivel y XP
end)

Players.PlayerAdded:Connect(load)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	save(pl)
	data[pl] = nil
	loaded[pl] = nil
end)
game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		save(pl)
	end
end)

-- autoguardado cada 120 s
task.spawn(function()
	while true do
		task.wait(120)
		for _, pl in ipairs(Players:GetPlayers()) do
			save(pl)
		end
	end
end)

return LevelService
