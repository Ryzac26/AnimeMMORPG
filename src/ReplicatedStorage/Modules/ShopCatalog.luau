--!strict
--[[
    ShopCatalog (ModuleScript) -> ReplicatedStorage.Modules.ShopCatalog
    PRECIOS del mercader (un solo lugar para balancear). Lo leen el servidor (cobra/paga) y el cliente (muestra).
      COMPRA  (Stock): pociones. Precio = 25 x (1 + 0.15 x nivel del jugador)  -> nivel 1: 29 · nivel 50: 213 · nivel 100: 400
      VENTA   (SellPrice): equipo = 15 x (1 + nivelReq/5) x multiplicador de rareza x (1 + 0.5 x mejora)
                           materiales y pociones: valor fijo (tabla)
                           NO se venden: Gemas de Mejora, mascotas, objetos puestos (solo lo que está en la mochila)
      Multiplicador de rareza: Común 1 · Raro 2 · Épico 4 · Legendario 8 · Mítico 16
    Referencia (equipo +0): nivel 50 Común 165 · Épico 660 · Mítico 2.640 · nivel 100 Común 315 · Mítico 5.040
]]
local ShopCatalog = {}

ShopCatalog.Stock = { "Pocion_Vida", "Pocion_Energia" }

ShopCatalog.RarityMult = { Comun = 1, Raro = 2, Epico = 4, Legendario = 8, Mitico = 16 } :: { [string]: number }
ShopCatalog.MaterialSell = {
	Mat_Piel = 6, Mat_Colmillo = 12, Mat_Esencia = 40, Mat_Nucleo = 120, Mat_FragArmadura = 30, Mat_Escama = 600,
} :: { [string]: number }
ShopCatalog.PotionSell = 10
ShopCatalog.MAX_BUY = 999 -- máximo de unidades por compra

function ShopCatalog.BuyPrice(level: number): number
	return math.floor(25 * (1 + 0.15 * level) + 0.5)
end

-- Precio al que el mercader te compra UNA unidad. nil = no lo compra.
function ShopCatalog.SellPrice(itemId: string, item: { [string]: any }?, plus: number?): number?
	if not item then
		return nil
	end
	if item.Pet then
		return nil
	end
	if item.Gear or item.Slot then
		local req = item.ReqLevel
		local level = if typeof(req) == "number" then req else 1
		local mult = ShopCatalog.RarityMult[item.Rarity] or 1
		return math.floor(15 * (1 + level / 5) * mult * (1 + 0.5 * (plus or 0)) + 0.5)
	end
	local fixed = ShopCatalog.MaterialSell[itemId]
	if fixed then
		return fixed
	end
	if item.Use then
		return ShopCatalog.PotionSell
	end
	return nil
end

-- ¿Hay que pedir confirmación antes de vender? (rareza Épico o mayor, o mejorado)
function ShopCatalog.NeedsConfirm(item: { [string]: any }, plus: number?): boolean
	local r = item.Rarity
	return (plus or 0) > 0 or r == "Epico" or r == "Legendario" or r == "Mitico"
end

return ShopCatalog
