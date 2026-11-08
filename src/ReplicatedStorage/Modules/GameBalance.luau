--!strict
--[[
    GameBalance (ModuleScript) -> ReplicatedStorage.Modules.GameBalance
    ÚNICO lugar con números y fórmulas del juego. Para rebalancear, tocas SOLO este archivo.
    Lo leen cliente (HUD) y servidor (servicios).
]]
local GB = {}

-- NIVEL MÁXIMO 3000 (antes 100). Los niveles están "inflados" x30: el jugador sube rápido al principio, pero el tiempo total hasta el
-- máximo es el mismo de antes. TODA la fuerza (vida, daño, ki, vida de monstruos, XP) se calcula con el NIVEL EQUIVALENTE
-- GB.Eq(nivel) (la escala vieja 1-100), así los números de combate no cambian: nv.750 = antes nv.25, nv.1500 = nv.50, nv.3000 = nv.100.
GB.MAX_LEVEL = 3000
GB.OLD_MAX_LEVEL = 100
GB.LEVEL_SCALE = 30 -- 1 nivel viejo = 30 niveles nuevos
GB.EARLY_LEVELS = 60 -- los 2 primeros niveles viejos se reparten en 60 niveles nuevos (rampa de inicio)
GB.MIN_KILLS_PER_LEVEL = 1 -- ningún nivel pide menos de 1 kill de su nivel

-- Nivel equivalente (escala vieja 1-100, con decimales). Continua y creciente: Eq(1)=1, Eq(60)=2, Eq(750)=25, Eq(3000)=100.
function GB.Eq(level: number): number
	level = math.max(1, level)
	if level <= GB.EARLY_LEVELS then
		return 1 + (level - 1) / (GB.EARLY_LEVELS - 1)
	end
	return level / GB.LEVEL_SCALE
end
-- Niveles nuevos que caben en un nivel viejo en ese punto (pendiente de Eq, inversa)
local function levelsPerOld(level: number): number
	return if level < GB.EARLY_LEVELS then GB.EARLY_LEVELS - 1 else GB.LEVEL_SCALE
end
-- Convierte un nivel de la escala vieja (1-100) a la nueva (1-3000): 1->1, 25->750, 50->1500, 100->3000
function GB.FromOld(old: number): number
	if old <= 1 then
		return 1
	end
	return math.floor(old * GB.LEVEL_SCALE + 0.5)
end
-- Primer nivel nuevo de un nivel viejo (para rangos de franja: 11 -> 301, 26 -> 751)
function GB.FromOldMin(old: number): number
	if old <= 1 then
		return 1
	end
	return (old - 1) * GB.LEVEL_SCALE + 1
end

-- Crecimiento exponencial por nivel
GB.PLAYER_DMG_GROWTH = 1.057
GB.PLAYER_HP_GROWTH = 1.0315
GB.MOB_HP_GROWTH = 1.057
GB.MOB_HP_LINEAR = 0.0202 -- factor extra (1 + 0.0202*(L-1)) para que un mob nivel 100 nunca muera en 1-2 golpes
GB.MOB_HIT_GROWTH = 1.045 -- (antes 1.0485) suaviza las franjas 3 y 4 junto con los atributos de rol (ClassStats)
GB.MOB_BASE_HP = 205
GB.MOB_BASE_HIT = 47

-- Progresión: ~1096 h totales = 365 días a 3 h/día
GB.KILLS_PER_HOUR = 126 -- ritmo teórico, calibra la XP necesaria por nivel
GB.XP_PER_KILL_DIV = 10 -- XP por kill = vida del mob / 10
GB.BOSS_HP_MULT = 120 -- (antiguo, ya no se usa para los élites de franja; queda por si se usa en jefes mundiales)
-- ÉLITES DE FRANJA (los 12 jefes del catálogo): vida = vida de mob de su nivel × multiplicador de su franja.
-- "Golpe" = auto-ataque de un Guerrero (130 x 22% x crecimiento de daño). Con estos valores:
--   Franja 1 (nv.750): jugador nv.750 ≈ 85 golpes | nv.3000 ≈ 1 golpe
--   Franja 2 (nv.1500): jugador nv.1500 ≈ 143 golpes | nv.3000 ≈ 9 golpes
--   Franja 3 (nv.2250): jugador nv.2250 ≈ 215 golpes | nv.3000 ≈ 54 golpes
--   Franja 4 (nv.3000): jugador nv.3000 ≈ 323 golpes (el desafío final)
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
GB.DEATH_PENALTY_MIN_LEVEL = 300 -- (antes 10)
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
	return GB.PLAYER_DMG_GROWTH ^ (GB.Eq(level) - 1)
end

-- KI / CHAKRA / HAKI: el máximo crece 3.5% de la base por nivel (nv.100 = x4.47). El costo de los poderes crece más lento
-- (exponente 0.85, nv.100 = x3.57): a nivel alto alcanza para ~25% más poderes seguidos, sin volverse infinito.
function GB.KiMult(level: number): number
	return 1 + 0.035 * (GB.Eq(level) - 1)
end
function GB.KiCostMult(level: number): number
	return GB.KiMult(level) ^ 0.85
end

function GB.PlayerHpMult(level: number): number
	return GB.PLAYER_HP_GROWTH ^ (GB.Eq(level) - 1)
end

function GB.MobHp(level: number): number
	local e = GB.Eq(level) - 1
	return GB.MOB_BASE_HP * GB.MOB_HP_GROWTH ^ e * (1 + GB.MOB_HP_LINEAR * e)
end

function GB.MobHit(level: number): number
	return GB.MOB_BASE_HIT * GB.MOB_HIT_GROWTH ^ (GB.Eq(level) - 1)
end

function GB.MobXp(level: number): number
	return math.floor(GB.MobHp(level) / GB.XP_PER_KILL_DIV)
end

function GB.BossXp(level: number): number
	return GB.MobXp(level) * GB.BOSS_XP_KILLS
end

-- Horas que tomaba pasar de un nivel VIEJO (escala 1-100, admite decimales) al siguiente
function GB.HoursForLevel(oldLevel: number): number
	return 0.0028 * (oldLevel + 6) ^ 2
end

-- XP necesaria para pasar de `level` a `level+1` (escala 1-3000). Es lo que costaba el nivel viejo repartido entre sus niveles nuevos:
-- el tiempo total hasta el 3000 es el de antes, pero el inicio da un nivel casi cada kill (mínimo MIN_KILLS_PER_LEVEL kills).
function GB.XpToNext(level: number): number
	if level >= GB.MAX_LEVEL then
		return math.huge
	end
	local mobXp = GB.MobXp(level)
	local fromCurve = GB.HoursForLevel(GB.Eq(level)) * GB.KILLS_PER_HOUR * mobXp / levelsPerOld(level)
	return math.max(math.floor(fromCurve), mobXp * GB.MIN_KILLS_PER_LEVEL)
end

-- XP que pedía el nivel VIEJO `oldLevel` (solo para migrar cuentas guardadas con la escala 1-100)
function GB.LegacyXpToNext(oldLevel: number): number
	return math.max(1, math.floor(GB.HoursForLevel(oldLevel) * GB.KILLS_PER_HOUR * GB.MobXp(GB.FromOld(oldLevel))))
end

-- Multiplicador de daño PvP: normalizado al nivel de la víctima + brecha de nivel al 40%
function GB.PvpDamageMult(attackerLevel: number, victimLevel: number): number
	local gap = GB.PlayerDamageMult(attackerLevel) / GB.PlayerDamageMult(victimLevel)
	return GB.PlayerDamageMult(victimLevel) * gap ^ GB.PVP_LEVEL_GAP_FACTOR * GB.PVP_DAMAGE_FACTOR
end

return GB
