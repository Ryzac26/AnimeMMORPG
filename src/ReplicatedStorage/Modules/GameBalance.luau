--!strict
--[[
    GameBalance (ModuleScript) -> ReplicatedStorage.Modules.GameBalance
    ÚNICO lugar con números y fórmulas del juego. Para rebalancear, tocas SOLO este archivo.
    Lo leen cliente (HUD) y servidor (servicios).
]]
local GB = {}

GB.MAX_LEVEL = 100

-- Crecimiento exponencial por nivel
GB.PLAYER_DMG_GROWTH = 1.057
GB.PLAYER_HP_GROWTH = 1.0315
GB.MOB_HP_GROWTH = 1.057
GB.MOB_HP_LINEAR = 0.0202 -- factor extra (1 + 0.0202*(L-1)) para que un mob nivel 100 nunca muera en 1-2 golpes
GB.MOB_HIT_GROWTH = 1.0485
GB.MOB_BASE_HP = 205
GB.MOB_BASE_HIT = 47

-- Progresión: ~1096 h totales = 365 días a 3 h/día
GB.KILLS_PER_HOUR = 126 -- ritmo teórico, calibra la XP necesaria por nivel
GB.XP_PER_KILL_DIV = 10 -- XP por kill = vida del mob / 10
GB.BOSS_HP_MULT = 120 -- (antiguo, ya no se usa para los élites de franja; queda por si se usa en jefes mundiales)
-- ÉLITES DE FRANJA (los 12 jefes del catálogo): vida = vida de mob de su nivel × multiplicador de su franja.
-- "Golpe" = auto-ataque de un Guerrero (130 x 22% x crecimiento de daño). Con estos valores:
--   Franja 1 (nv.25): jugador nv.25 ≈ 85 golpes | nv.100 ≈ 1 golpe
--   Franja 2 (nv.50): jugador nv.50 ≈ 143 golpes | nv.100 ≈ 9 golpes
--   Franja 3 (nv.75): jugador nv.75 ≈ 215 golpes | nv.100 ≈ 54 golpes
--   Franja 4 (nv.100): jugador nv.100 ≈ 323 golpes (el desafío final)
-- (antes: 1277 / 1712 / 2146 / 2580 golpes de un jugador de su nivel). Para ajustarlo, cambia solo esta lista.
GB.ELITE_HP_MULT_BY_STRIP = { 8, 10, 12, 15 }
function GB.EliteHpMult(strip: number): number
	return GB.ELITE_HP_MULT_BY_STRIP[math.clamp(math.floor(strip), 1, #GB.ELITE_HP_MULT_BY_STRIP)]
end
GB.BOSS_XP_KILLS = 30 -- el jefe da el equivalente a 30 kills por participante
GB.BOSS_MIN_DAMAGE_PCT = 0.01 -- 1% del daño para participar en XP y botín

-- Muerte
GB.DEATH_PENALTY_PVE = 0.03 -- % de la XP del nivel actual (nunca baja de nivel)
GB.DEATH_PENALTY_PVP = 0.02
GB.DEATH_PENALTY_MIN_LEVEL = 10
GB.SPAWN_PROTECTION = 5 -- segundos

-- PvP (solo Arena Central, entre naciones distintas)
GB.PVP_DAMAGE_FACTOR = 0.27
GB.PVP_LEVEL_GAP_FACTOR = 0.40 -- la diferencia de nivel pesa solo el 40% en PvP
GB.FRAGILITY_PER_HIT = 0.05 -- +5% daño recibido por golpe
GB.FRAGILITY_MAX_STACKS = 10
GB.FRAGILITY_DURATION = 8 -- s desde el último golpe
GB.CC_DR_WINDOW = 10 -- s: un 2º aturdimiento dentro de la ventana dura la mitad, el 3º la cuarta parte, el 4º nada
GB.ARENA_LIVES = 5

-- Skills 3 y 4 (cooldown PvP = PvE × factor)
GB.PVP_COOLDOWN_UTILITY = 1.5
GB.PVP_COOLDOWN_ULTIMATE = 2.5

function GB.PlayerDamageMult(level: number): number
	return GB.PLAYER_DMG_GROWTH ^ (level - 1)
end

-- KI / CHAKRA / HAKI: el máximo crece 3.5% de la base por nivel (nv.100 = x4.47). El costo de los poderes crece más lento
-- (exponente 0.85, nv.100 = x3.57): a nivel alto alcanza para ~25% más poderes seguidos, sin volverse infinito.
function GB.KiMult(level: number): number
	return 1 + 0.035 * (math.max(1, level) - 1)
end
function GB.KiCostMult(level: number): number
	return GB.KiMult(level) ^ 0.85
end

function GB.PlayerHpMult(level: number): number
	return GB.PLAYER_HP_GROWTH ^ (level - 1)
end

function GB.MobHp(level: number): number
	return GB.MOB_BASE_HP * GB.MOB_HP_GROWTH ^ (level - 1) * (1 + GB.MOB_HP_LINEAR * (level - 1))
end

function GB.MobHit(level: number): number
	return GB.MOB_BASE_HIT * GB.MOB_HIT_GROWTH ^ (level - 1)
end

function GB.MobXp(level: number): number
	return math.floor(GB.MobHp(level) / GB.XP_PER_KILL_DIV)
end

function GB.BossXp(level: number): number
	return GB.MobXp(level) * GB.BOSS_XP_KILLS
end

function GB.HoursForLevel(level: number): number
	return 0.0028 * (level + 6) ^ 2
end

-- XP necesaria para pasar de `level` a `level+1`
function GB.XpToNext(level: number): number
	if level >= GB.MAX_LEVEL then
		return math.huge
	end
	return math.floor(GB.HoursForLevel(level) * GB.KILLS_PER_HOUR * GB.MobXp(level))
end

-- Multiplicador de daño PvP: normalizado al nivel de la víctima + brecha de nivel al 40%
function GB.PvpDamageMult(attackerLevel: number, victimLevel: number): number
	local gap = GB.PlayerDamageMult(attackerLevel) / GB.PlayerDamageMult(victimLevel)
	return GB.PlayerDamageMult(victimLevel) * gap ^ GB.PVP_LEVEL_GAP_FACTOR * GB.PVP_DAMAGE_FACTOR
end

return GB
