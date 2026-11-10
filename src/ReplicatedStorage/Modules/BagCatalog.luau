--!strict
--[[
    BagCatalog (ModuleScript) -> ReplicatedStorage.Modules.BagCatalog
    PÁGINAS de la mochila (un solo lugar para cambiar tamaños y precios).
      Páginas 1 y 2: gratis, 35 casillas cada una (70 en total).
      Páginas 3, 4 y 5: de pago (Robux), 40 casillas cada una. Se compran EN ORDEN (la 3, luego la 4, luego la 5).
    Cada página de pago es un PASE DE JUEGO (Game Pass) permanente: créalos en el panel de Roblox (Creator Hub > tu experiencia >
    Monetización > Pases) y pega aquí cada ID en GamePassIds. Mientras un ID sea 0:
      - en Roblox Studio la página se desbloquea gratis (para probar)
      - en el juego publicado NO se puede comprar (sale un aviso)
    Casillas: página p ocupa las casillas (inicio .. fin) globales; la mochila guarda todo con un número de casilla global.
]]
local BagCatalog = {}

BagCatalog.PageSizes = { 35, 35, 40, 40, 40 } :: { number }
BagCatalog.FreePages = 2
BagCatalog.GamePassIds = { 3730251882, 3730251976, 3730252060 } :: { number } -- Mochila Ampliada I, II y III (páginas 3, 4 y 5)
-- SOLO PARA PROBAR en Roblox Studio: true = tu cuenta NO cuenta los pases (aunque seas la dueña) y ves las páginas 3-5 bloqueadas con su precio.
-- En el juego publicado no tiene ningún efecto. Antes de lanzar ponlo en false.
BagCatalog.DevIgnorePasses = true

BagCatalog.PriceText = { "99 R$", "149 R$", "199 R$" } :: { string } -- texto informativo del precio (opcional, p. ej. "99 R$")

function BagCatalog.MaxPaid(): number
	return #BagCatalog.PageSizes - BagCatalog.FreePages
end

-- Casillas totales con `paid` páginas de pago desbloqueadas
function BagCatalog.Capacity(paid: number): number
	local n = 0
	for i = 1, BagCatalog.FreePages + math.clamp(paid, 0, BagCatalog.MaxPaid()) do
		n += BagCatalog.PageSizes[i]
	end
	return n
end

-- (primera, última) casilla global de la página p
function BagCatalog.PageRange(p: number): (number, number)
	local first = 1
	for i = 1, p - 1 do
		first += BagCatalog.PageSizes[i]
	end
	return first, first + BagCatalog.PageSizes[p] - 1
end

return BagCatalog
