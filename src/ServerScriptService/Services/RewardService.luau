--!strict
--[[
    RewardService (ModuleScript) -> ServerScriptService.Services.RewardService
    Reparte XP y botín cuando muere un mob. NO conoce IA ni combate: solo recibe "murió X" y "el jugador P hizo N de daño".
      Mob normal : XP total = GameBalance.MobXp(nivel), repartida según el % de daño de cada jugador.
      Jefe       : cada jugador con >= 1% del daño recibe XP completa del jefe (= 30 kills de su nivel).
                   El botín del jefe se sortea entre los participantes elegibles (1 ganador).
    Señales para conectar tu inventario / sistema de botín (BindableEvents):
      RewardService.MobKilled:Connect(function(mobId, level, participants: {Player}) end)
      RewardService.BossLoot:Connect(function(winner: Player, mobId, level) end)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Services = ServerScriptService.Services
local LevelService = require(Services.LevelService)
local DamageService = require(Services.DamageService)
local Net = require(Services.Net)
-- BoostService se carga al usarlo (evita el error "required recursively" si otro módulo lo requiere de vuelta)
local function boostMult(pl: Player): number
	local ok, bs = pcall(function()
		return require(Services.BoostService)
	end)
	local mult = 1
	if ok and type(bs) == "table" and bs.XpMult then
		mult = bs.XpMult(pl)
	end
	local shrine = pl:GetAttribute("ShrineXp") -- santuario de Fortuna (ArenaStyler)
	if typeof(shrine) == "number" then
		mult *= shrine
	end
	return mult
end

local RewardService = {}

local killedEvent = Instance.new("BindableEvent")
local lootEvent = Instance.new("BindableEvent")
RewardService.MobKilled = killedEvent.Event :: RBXScriptSignal
RewardService.BossLoot = lootEvent.Event :: RBXScriptSignal

local damageLog: { [Model]: { Total: number, ByPlayer: { [Player]: number } } } = {}

local function record(mob: Model, player: Player, amount: number)
	local log = damageLog[mob]
	if not log then
		log = { Total = 0, ByPlayer = {} }
		damageLog[mob] = log
	end
	log.Total += amount
	log.ByPlayer[player] = (log.ByPlayer[player] or 0) + amount
end
DamageService.SetDamageListener(record)

function RewardService.Forget(mob: Model)
	damageLog[mob] = nil
end

-- Llamado por MobService cuando el mob muere
function RewardService.OnMobKilled(mob: Model, mobId: string, level: number, isBoss: boolean, summoned: boolean, xpMult: number?)
	local log = damageLog[mob]
	damageLog[mob] = nil
	if not log or log.Total <= 0 or summoned then
		return -- invocados (clones/marionetas) no dan XP ni botín: evita farmeo
	end

	local participants: { Player } = {}
	if isBoss then
		local maxHp = mob:GetAttribute("MaxHp")
		local denom = if typeof(maxHp) == "number" and maxHp > 0 then maxHp else log.Total
		for pl, dmg in pairs(log.ByPlayer) do
			if pl.Parent and dmg / denom >= GB.BOSS_MIN_DAMAGE_PCT then
				table.insert(participants, pl)
			end
		end
		local xp = math.floor(GB.BossXp(level) * (xpMult or 1))
		for _, pl in ipairs(participants) do
			LevelService.AddXp(pl, math.floor(xp * boostMult(pl)))
			Net.Get("Notify"):FireClient(pl, string.format("Jefe derrotado: +%d XP", xp))
		end
		if #participants > 0 then
			local winner = participants[math.random(1, #participants)]
			Net.Get("Notify"):FireClient(winner, "¡Ganaste el botín del jefe!")
			lootEvent:Fire(winner, mobId, level)
		end
	else
		local xp = GB.MobXp(level) * (xpMult or 1)
		for pl, dmg in pairs(log.ByPlayer) do
			if pl.Parent then
				table.insert(participants, pl)
				LevelService.AddXp(pl, math.max(1, math.floor(xp * dmg / log.Total * boostMult(pl))))
			end
		end
	end
	if #participants > 0 then
		killedEvent:Fire(mobId, level, participants)
	end
end

Players.PlayerRemoving:Connect(function(pl)
	for _, log in pairs(damageLog) do
		log.ByPlayer[pl] = nil
	end
end)

return RewardService
