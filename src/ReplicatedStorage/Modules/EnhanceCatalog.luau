--!strict
--[[
    EnhanceCatalog (ModuleScript) -> ReplicatedStorage.Modules.EnhanceCatalog
    MEJORA DEL EQUIPO +1 a +9 (la hace el Herrero de cada ciudad). Un solo lugar para balancear.
      - Solo se mejora EQUIPO (armas, armaduras, cascos, zapatos, joyas, emblemas). Las mascotas no.
      - Cada +n multiplica las estadísticas del objeto: GearCatalog.EnhanceMult(n) = 1 + 0.05n + 0.01n²  (+9 = x2.26)
      - Costo: oro (crece con n y con el nivel del objeto) + Gemas: Gema Menor (Mat_GemaMenor) de +1 a +5 y Gema Mayor (Mat_Gema, solo de los Metin) de +6 a +9.
      - Éxito: +1..+3 siempre salen. Desde +4 hay riesgo.
      - Fallo: el objeto NUNCA se rompe. +4..+6: no pasa nada (pierdes el costo). +7, +8 y +9: baja 1 nivel o SE ROMPE (BreakChance); el Pergamino de Protección evita las dos.
      - Llegar de +0 a +9 (simulado, 7 nov 2026): CON Pergamino de Protección ≈ 57 intentos, ≈ 234 gemas, ≈ 46 pergaminos y ≈ 1.060.000 de oro en una pieza de nivel 100
        (≈ 190.000 de oro en nivel 10). SIN pergaminos es prácticamente imposible (≈ 9.700 intentos y ≈ 290 piezas rotas por camino).
]]
local EnhanceCatalog = {}

EnhanceCatalog.MaxPlus = 9
EnhanceCatalog.GemItem = "Mat_Gema" -- Gema MAYOR (Metin): mejoras +6 a +9
EnhanceCatalog.MinorGemItem = "Mat_GemaMenor" -- Gema MENOR (mobs, mini jefes, cofres, altares): mejoras +1 a +5
EnhanceCatalog.MinorGemMaxTarget = 5

-- ¿Qué gema pide el intento de llegar a +target?
function EnhanceCatalog.GemItemFor(target: number): string
	return if target <= EnhanceCatalog.MinorGemMaxTarget then EnhanceCatalog.MinorGemItem else EnhanceCatalog.GemItem
end

-- Probabilidad de éxito al intentar llegar a +n
-- Hasta +5 es fácil (≈5 intentos); de ahí en adelante es MUY duro: +9 es un gran mérito (≈29 intentos solo en el último tramo, ≈47 pergaminos de +6 a +9; sin pergaminos casi imposible)
EnhanceCatalog.SuccessRate = { [1] = 1.00, [2] = 1.00, [3] = 1.00, [4] = 0.95, [5] = 0.90, [6] = 0.40, [7] = 0.15, [8] = 0.075, [9] = 0.035 } :: { [number]: number }

-- Si falla el intento a +n: cuántos niveles baja el objeto (0 = se queda igual)
EnhanceCatalog.FailDrop = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 1, [8] = 1, [9] = 1 } :: { [number]: number }

EnhanceCatalog.ScrollItem = "Pergamino_Proteccion" -- evita que la pieza baje al fallar (solo importa en +7, +8 y +9)

-- Al FALLAR el intento a +n: probabilidad de que la pieza SE ROMPA (desaparece). Si no se rompe, baja según FailDrop.
-- El Pergamino de Protección evita ambas cosas: la pieza se queda igual (mismo nivel) y se gasta el pergamino.
EnhanceCatalog.BreakChance = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 0.10, [8] = 0.20, [9] = 0.30 } :: { [number]: number }

-- Título que se gana al forjar un +9
EnhanceCatalog.TitlePlus9 = "Maestro Forjador"

-- Gemas necesarias para intentar llegar a +n
EnhanceCatalog.Gems = { [1] = 1, [2] = 1, [3] = 1, [4] = 2, [5] = 2, [6] = 3, [7] = 3, [8] = 4, [9] = 5 } :: { [number]: number }

-- Oro para intentar llegar a +n: 40 x n^1.8 x (1 + nivelDelObjeto/10)
function EnhanceCatalog.GoldCost(item: { [string]: any }, target: number): number
	local req = item.ReqLevel
	local level = if typeof(req) == "number" then req else 1
	return math.floor(40 * target ^ 1.8 * (1 + level / 10) + 0.5)
end

-- ¿Se puede mejorar este objeto?
function EnhanceCatalog.CanEnhance(item: { [string]: any }?): boolean
	return item ~= nil and item.Gear ~= nil and item.Slot ~= nil
end

function EnhanceCatalog.PlusName(name: string, plus: number): string
	if plus >= EnhanceCatalog.MaxPlus then
		return string.format("★ +%d %s", plus, name) -- +9: pieza al máximo
	end
	return if plus > 0 then string.format("+%d %s", plus, name) else name
end

return EnhanceCatalog
