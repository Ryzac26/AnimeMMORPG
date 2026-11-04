--!strict
--[[
    MasteryCatalog (ModuleScript) -> ReplicatedStorage.Modules.MasteryCatalog
    MAESTRÍA DE ROL: cada rol (Tanque, Guerrero, Asesino, Tirador, Mago, Curador) sube su PROPIO rango jugando con él.
      - Puntos: 1 por monstruo derrotado con ese rol (x5 Metin / mini jefe). Solo cuentan monstruos de nivel parecido al tuyo
        (a partir de LEVEL_WINDOW niveles por debajo ya no suman: no sirve farmear bichos débiles).
      - 10 rangos. Cada rango da un bono PERMANENTE pequeño, solo mientras juegas con ese rol (BONUS_PER_RANK, acumulable).
      - Pase "Maestría Multiclase": la maestría sube PASS_MULT veces más rápido, cambias de rol en cualquier lugar
        y el equipo se guarda por rol (lo hace MasteryService).
    Todos los números están aquí para balancear.
]]
local MasteryCatalog = {}

MasteryCatalog.ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
MasteryCatalog.MAX_RANK = 10
-- Puntos ACUMULADOS para alcanzar el rango 1..10
MasteryCatalog.THRESHOLDS = { 300, 900, 2000, 4000, 7000, 11000, 17000, 25000, 36000, 50000 } :: { number }
-- Bono por rango (fracciones; rango 10 = x10): +4% daño, +3% defensa, +4% vida
MasteryCatalog.BONUS_PER_RANK = { Ataque = 0.004, Defensa = 0.003, Vida = 0.004 } :: { [string]: number }
MasteryCatalog.PASS_MULT = 1.25
MasteryCatalog.LEVEL_WINDOW = 15
MasteryCatalog.SPECIAL_KILL_POINTS = 5 -- Metin y mini jefes
MasteryCatalog.SWITCH_COOLDOWN = 20 -- s entre cambios de rol (pase)
MasteryCatalog.COMBAT_LOCK = 10 -- s sin recibir golpes para poder cambiar

function MasteryCatalog.RankOf(points: number): number
	local r = 0
	for i, t in ipairs(MasteryCatalog.THRESHOLDS) do
		if points >= t then
			r = i
		end
	end
	return r
end

-- (puntos dentro del rango actual, puntos que pide el siguiente). Rango máximo: (1, 1).
function MasteryCatalog.Progress(points: number): (number, number)
	local r = MasteryCatalog.RankOf(points)
	if r >= MasteryCatalog.MAX_RANK then
		return 1, 1
	end
	local base = if r == 0 then 0 else MasteryCatalog.THRESHOLDS[r]
	return points - base, MasteryCatalog.THRESHOLDS[r + 1] - base
end

function MasteryCatalog.StatsFor(rank: number): { [string]: number }
	local out: { [string]: number } = {}
	for stat, v in pairs(MasteryCatalog.BONUS_PER_RANK) do
		out[stat] = v * rank
	end
	return out
end

function MasteryCatalog.RankTitle(role: string, rank: number): string?
	if rank >= MasteryCatalog.MAX_RANK then
		return "Maestro " .. role
	end
	return nil
end

return MasteryCatalog
