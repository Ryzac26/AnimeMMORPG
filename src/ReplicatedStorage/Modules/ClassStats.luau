--!strict
--[[
    ClassStats (ModuleScript) -> ReplicatedStorage.Modules.ClassStats
    ATRIBUTOS DE ROL (estilo MMORPG). Cada rol tiene 5 atributos y TODOS tienen efecto real en el combate:
      FUE Fuerza        daño de los roles físicos (Tanque, Guerrero) y fuerza de defensa
      DES Destreza      daño de Asesino y Tirador · crítico · velocidad de ataque · esquiva
      INT Inteligencia  daño de Mago y Curador · potencia de curación
      VIT Vitalidad     vida máxima y defensa (reducción de daño de los monstruos)
      ESP Espíritu      energía máxima y regeneración de energía (Ki / Chakra / Haki)
    100 = valor de referencia. Para rebalancear una clase solo toca su fila en STATS (y COEF si es de apoyo).

    Efectos (todos con el nivel ya aplicado por GameBalance; aquí solo hay PROPORCIONES):
      Daño        = COEF[rol] × (atributo principal / 100)
      Crítico     = (DES - 70) × 0,12%                     (se suma al crítico del equipo)
      Vel. ataque = 1 + (DES - 100) × 0,2%
      Esquiva     = (DES - 90) × 0,1%  (máx. 10%)           (contra monstruos)
      Vida base   = VIT × 10
      Defensa     = VIT × 0,45 + FUE × 0,25  ->  reducción = Def / (Def + 220)   (contra monstruos)
      Curación    = máx(1, INT / 100)
      Energía     = 1 + (ESP - 100) × 0,4%  (máximo) · regeneración × ESP / 100
    COEF = "coeficiente de golpe": el Tanque y el Curador tienen poderes de escudo/cura, así que su golpe básico es más fuerte
    para que farmear no sea una espera eterna.
]]
local ClassStats = {}

export type Stats = { FUE: number, DES: number, INT: number, VIT: number, ESP: number }

ClassStats.Order = { "FUE", "DES", "INT", "VIT", "ESP" }
ClassStats.Names = { FUE = "Fuerza", DES = "Destreza", INT = "Inteligencia", VIT = "Vitalidad", ESP = "Espíritu" } :: { [string]: string }
ClassStats.Hints = {
	FUE = "Daño de Tanque y Guerrero · defensa",
	DES = "Daño de Asesino y Tirador · crítico, velocidad de ataque y esquiva",
	INT = "Daño de Mago y Curador · potencia de curación",
	VIT = "Vida máxima y defensa",
	ESP = "Energía máxima y regeneración",
} :: { [string]: string }

ClassStats.STATS = {
	Tanque   = { FUE = 100, DES = 70,  INT = 50,  VIT = 210, ESP = 90 },
	Guerrero = { FUE = 130, DES = 100, INT = 50,  VIT = 130, ESP = 90 },
	Asesino  = { FUE = 105, DES = 128, INT = 50,  VIT = 100, ESP = 90 },
	Tirador  = { FUE = 70,  DES = 132, INT = 75,  VIT = 120, ESP = 100 },
	Mago     = { FUE = 50,  DES = 80,  INT = 170, VIT = 110, ESP = 140 },
	Curador  = { FUE = 50,  DES = 70,  INT = 140, VIT = 125, ESP = 150 },
} :: { [string]: Stats }

-- atributo que da el daño de cada rol
ClassStats.MAIN = { Tanque = "FUE", Guerrero = "FUE", Asesino = "DES", Tirador = "DES", Mago = "INT", Curador = "INT" } :: { [string]: string }
-- coeficiente de golpe (apoyo > 1)
ClassStats.COEF = { Tanque = 1.8, Curador = 2.2 } :: { [string]: number }

ClassStats.DEF_K = 220
ClassStats.DODGE_CAP = 0.10

local function statsOf(role: string): Stats
	return ClassStats.STATS[role] or ClassStats.STATS.Guerrero
end

function ClassStats.Get(role: string): Stats
	return statsOf(role)
end

function ClassStats.Main(role: string): string
	return ClassStats.MAIN[role] or "FUE"
end

function ClassStats.DamageMult(role: string): number
	local s = statsOf(role)
	return (ClassStats.COEF[role] or 1) * ((s :: any)[ClassStats.Main(role)] / 100)
end

function ClassStats.CritChance(role: string): number
	return math.max(0, (statsOf(role).DES - 70) * 0.0012)
end

function ClassStats.AttackSpeed(role: string): number
	return 1 + (statsOf(role).DES - 100) * 0.002
end

function ClassStats.Dodge(role: string): number
	return math.clamp((statsOf(role).DES - 90) * 0.001, 0, ClassStats.DODGE_CAP)
end

function ClassStats.BaseHp(role: string): number
	return statsOf(role).VIT * 10
end

function ClassStats.Defense(role: string): number
	local s = statsOf(role)
	return s.VIT * 0.45 + s.FUE * 0.25
end

function ClassStats.Mitigation(role: string): number
	local d = ClassStats.Defense(role)
	return d / (d + ClassStats.DEF_K)
end

function ClassStats.HealMult(role: string): number
	return math.max(1, statsOf(role).INT / 100)
end

function ClassStats.EnergyMax(role: string): number
	return 1 + (statsOf(role).ESP - 100) * 0.004
end

function ClassStats.EnergyRegen(role: string): number
	return statsOf(role).ESP / 100
end

-- Valor que se muestra en pantalla: crece con el nivel (solo estético; los efectos usan las proporciones de arriba)
function ClassStats.Shown(role: string, stat: string, eqLevel: number): number
	local base = (statsOf(role) :: any)[stat] or 0
	return math.floor(base * (1 + (eqLevel - 1) * 0.1) + 0.5)
end

return ClassStats
