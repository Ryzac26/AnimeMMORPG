--!strict
--[[
    RewardService (ModuleScript) -> ServerScriptService.Services.RewardService
    Reparte XP y botín cuando muere un mob. NO conoce IA ni combate: solo recibe "murió X" y "el jugador P hizo N de daño".
      Mob normal : XP total = GameBalance.MobXp(nivel), repartida según el % de daño de cada jugador.
      Jefe       : cada jugador con >= 1% del daño recibe XP completa del jefe (= 30 kills de su nivel).
                   El botín del jefe se sortea entre los participantes elegibles (1 ganador).
    Señales para conectar tu inventario / sistema de botín (BindableEvents):
      RewardService.MobKilled:Connect(function(mobId, level, participants: {Player}, shares: {[Player]: number}) end)
        (también se dispara con jefes y Metin; LootService reparte el botín con ella)
      RewardService.BossLoot: ya no se dispara (el sorteo del jefe lo hace LootService)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Services = ServerScriptService.Services
local LevelService = require(Services.LevelService)
local LevelGap = require(ReplicatedStorage.Modules.LevelGap)
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
	-- boost de XP comprado en la Tienda (PurchaseService)
	local okP, ps = pcall(function()
		return require(Services.PurchaseService)
	end)
	if okP and type(ps) == "table" and ps.XpMult then
		mult *= ps.XpMult(pl)
	end
	local shrine = pl:GetAttribute("ShrineXp") -- santuario de Fortuna (ArenaStyler)
	if typeof(shrine) == "number" then
		mult *= shrine
	end
	return mult
end

-- Mascota Búho (XP): GearService se carga al usarlo, igual que BoostService
local function petXpMult(pl: Player): number
	local ok, gs = pcall(function()
		return require(Services.GearService)
	end)
	if ok and type(gs) == "table" and gs.XpMult then
		return gs.XpMult(pl)
	end
	return 1
end

local RewardService = {}

-- XP reducida por brecha de nivel (ver LevelGap). Avisa al jugador como mucho cada 40 s.
local gapNotified: { [Player]: number } = {}
local XP_FRANJA = true -- XP al 100 % dentro de la franja; al pasar su tope baja deprisa (LevelGap.XP_POINTS). false = sin castigo extra
local function gapMult(pl: Player, mobLevel: number): number
	if not XP_FRANJA then
		return 1
	end
	local m = LevelGap.MultXp(LevelService.GetLevel(pl), mobLevel)
	if m < 0.95 and os.clock() - (gapNotified[pl] or -1000) > 40 then
		gapNotified[pl] = os.clock()
		Net.Get("Notify"):FireClient(pl, string.format("Ya superaste esta franja: XP al %d%%. Avanza a la siguiente", math.floor(m * 100 + 0.5)))
	end
	return m
end

local killedEvent = Instance.new("BindableEvent")
local lootEvent = Instance.new("BindableEvent")
RewardService.MobKilled = killedEvent.Event :: RBXScriptSignal
RewardService.BossLoot = lootEvent.Event :: RBXScriptSignal

local Contribution = require(script.Parent.ContributionService)
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
	Contribution.Forget(mob)
end

-- Llamado por MobService cuando el mob muere
function RewardService.OnMobKilled(mob: Model, mobId: string, level: number, isBoss: boolean, summoned: boolean, xpMult: number?)
	local log = damageLog[mob]
	damageLog[mob] = nil
	if not log or log.Total <= 0 or summoned then
		Contribution.Forget(mob)
		return -- invocados (clones/marionetas) no dan XP ni botín: evita farmeo
	end
	-- APORTE: daño + daño recibido (tanque) + apoyo (curación, escudos, auras). Ver ContributionService.
	local mobRoot = mob:FindFirstChild("HumanoidRootPart")
	local cShares = Contribution.Shares(mob, log.ByPlayer, if mobRoot and mobRoot:IsA("BasePart") then mobRoot.Position else nil)

	local participants: { Player } = {}
	if isBoss then
		local maxHp = mob:GetAttribute("MaxHp")
		local denom = if typeof(maxHp) == "number" and maxHp > 0 then maxHp else log.Total
		for pl in pairs(cShares) do
			local dmg = log.ByPlayer[pl] or 0
			-- el jefe premia el daño mínimo O un aporte mínimo de tanque/soporte (si no, solo los DPS cobrarían)
			if pl.Parent and (dmg / denom >= GB.BOSS_MIN_DAMAGE_PCT or (cShares[pl] or 0) >= Contribution.MIN_SHARE_ELIGIBLE) then
				table.insert(participants, pl)
			end
		end
		local xp = math.floor(GB.BossXp(level) * (xpMult or 1))
		for _, pl in ipairs(participants) do
			LevelService.AddXp(pl, math.floor(xp * boostMult(pl) * petXpMult(pl) * gapMult(pl, level)))
			Net.Get("Notify"):FireClient(pl, string.format("Jefe derrotado: +%d XP", xp))
		end
		-- El botín del jefe (reparto garantizado + sorteo) lo hace LootService con MobKilled; ya no se elige un único ganador aquí.
	else
		local xp = GB.MobXp(level) * (xpMult or 1)
		for pl, share in pairs(cShares) do
			if pl.Parent then
				table.insert(participants, pl)
				LevelService.AddXp(pl, math.max(1, math.floor(xp * share * boostMult(pl) * petXpMult(pl) * gapMult(pl, level))))
			end
		end
	end
	if #participants > 0 then
		-- partes: % del daño total de cada participante (LootService lo usa para el mínimo de botín y los boletos del sorteo)
		local shares: { [Player]: number } = {}
		for _, pl in ipairs(participants) do
			shares[pl] = cShares[pl] or 0
		end
		killedEvent:Fire(mobId, level, participants, shares)
	end
end

Players.PlayerRemoving:Connect(function(pl)
	gapNotified[pl] = nil
	for _, log in pairs(damageLog) do
		log.ByPlayer[pl] = nil
	end
end)

return RewardService
