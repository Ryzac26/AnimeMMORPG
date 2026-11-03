--!strict
--[[
    EnhanceCatalog (ModuleScript) -> ReplicatedStorage.Modules.EnhanceCatalog
    MEJORA DEL EQUIPO +1 a +9 (la hace el Herrero de cada ciudad). Un solo lugar para balancear.
      - Solo se mejora EQUIPO (armas, armaduras, cascos, zapatos, joyas, emblemas). Las mascotas no.
      - Cada +n multiplica las estadísticas del objeto: GearCatalog.EnhanceMult(n) = 1 + 0.05n + 0.01n²  (+9 = x2.26)
      - Costo: oro (crece con n y con el nivel del objeto) + Gemas de Mejora (Mat_Gema, las sueltan los Metin).
      - Éxito: +1..+3 siempre salen. Desde +4 hay riesgo.
      - Fallo: el objeto NUNCA se rompe. +4..+6: no pasa nada (pierdes el costo). +7, +8 y +9: baja 1 nivel (se evita con Pergamino de Protección).
      - Llegar de +0 a +9 cuesta en promedio ~31 intentos, ~99 gemas y ~450.000 de oro en una pieza de nivel 100 (~45.000 en nivel 10).
]]
local EnhanceCatalog = {}

EnhanceCatalog.MaxPlus = 9
EnhanceCatalog.GemItem = "Mat_Gema"

-- Probabilidad de éxito al intentar llegar a +n
EnhanceCatalog.SuccessRate = { [1] = 1.00, [2] = 1.00, [3] = 1.00, [4] = 0.85, [5] = 0.75, [6] = 0.65, [7] = 0.50, [8] = 0.40, [9] = 0.30 } :: { [number]: number }

-- Si falla el intento a +n: cuántos niveles baja el objeto (0 = se queda igual)
EnhanceCatalog.FailDrop = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 0, [7] = 1, [8] = 1, [9] = 1 } :: { [number]: number }

EnhanceCatalog.ScrollItem = "Pergamino_Proteccion" -- evita que la pieza baje al fallar (solo importa en +7, +8 y +9)

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
	return if plus > 0 then string.format("+%d %s", plus, name) else name
end

return EnhanceCatalog
