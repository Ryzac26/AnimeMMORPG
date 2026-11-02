--!strict
--[[
    ProductCatalog (ModuleScript) -> ReplicatedStorage.Modules.ProductCatalog
    PRODUCTOS que se compran varias veces (Developer Products de Roblox), un solo lugar para precios y límites.
    Los PASES de una sola compra (mochila...) van en BagCatalog; esto es solo lo repetible.

    Cómo crear cada producto: Creator Hub > tu experiencia > Monetización > Productos de desarrollador. Pega su ID en ProductId.
    Mientras ProductId sea 0: en Roblox Studio se entrega gratis (para probar); en el juego publicado NO se puede comprar.

    REGLAS DE PROGRESO
      - Por día (se reinicia a las 00:00 UTC = 21:00 en Uruguay):
          · Los PAQUETES DE HORAS y los COMBOS se bloquean entre sí: al comprar uno, los demás quedan bloqueados hasta el día
            siguiente (el elegido se puede repetir hasta su límite diario).
          · El BOOST de XP es independiente: se combina con cualquier paquete.
      - Boost de XP: +50% durante 4 h de juego (el tiempo solo corre con el jugador conectado; comprar más SUMA tiempo, nunca
        multiplica; tope MAX_BOOST_SECONDS acumulado). El +50% NO se aplica a la XP de los paquetes.
      - Paquete de horas: da la XP de esas horas de juego a TU nivel actual (HoursXp). Desde nivel MIN_LEVEL_HOURS, y como máximo
        MAX_LEVELS_PER_USE niveles por compra, para que no sirva para saltarse el inicio.
      - Combo = boost + paquete en una sola compra con descuento (Components + Price sirven para mostrar "Ahorras X R$").
]]
local ProductCatalog = {}

export type Product = {
	Key: string,
	Group: string,
	Kind: string, -- "Boost" | "Hours" | "Combo"
	Lane: string, -- "Boost" (independiente) | "Horas" (se bloquean entre sí)
	Price: number, -- R$ (solo para calcular descuentos en pantalla; el cobro real es el del Developer Product)
	Components: { string }?,
	Name: string,
	Desc: string,
	ProductId: number,
	PriceText: string,
	DailyLimit: number,
	MinLevel: number,
	Seconds: number?,
	Mult: number?,
	Hours: number?,
}

ProductCatalog.MIN_LEVEL_HOURS = 20
ProductCatalog.MAX_LEVELS_PER_USE = 2
ProductCatalog.MAX_BOOST_SECONDS = 12 * 3600

ProductCatalog.Products = {
	{
		Key = "Boost4h", Group = "Progreso", Kind = "Boost", Lane = "Boost", Price = 49, Name = "Boost de XP +50% (4 h)",
		Desc = "+50% de XP durante 4 horas de juego. Comprar más suma tiempo.",
		ProductId = 2064418488, PriceText = "49 R$", DailyLimit = 3, MinLevel = 1, Seconds = 4 * 3600, Mult = 1.5,
	},
	{
		Key = "Horas3", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 59, Name = "Paquete de 3 horas",
		Desc = "Recupera la XP de 3 horas de juego a tu nivel actual.",
		ProductId = 2064189703, PriceText = "59 R$", DailyLimit = 2, MinLevel = 20, Hours = 3,
	},
	{
		Key = "Horas5", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 89, Name = "Paquete de 5 horas",
		Desc = "Recupera la XP de 5 horas de juego a tu nivel actual.",
		ProductId = 2063976038, PriceText = "89 R$", DailyLimit = 1, MinLevel = 20, Hours = 5,
	},
	{
		Key = "Horas8", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 139, Name = "Paquete de 8 horas",
		Desc = "Recupera la XP de 8 horas de juego a tu nivel actual.",
		ProductId = 2064089903, PriceText = "139 R$", DailyLimit = 1, MinLevel = 20, Hours = 8,
	},
	{
		Key = "Horas12", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 199, Name = "Paquete de 12 horas",
		Desc = "Recupera la XP de 12 horas de juego a tu nivel actual.",
		ProductId = 2063992040, PriceText = "199 R$", DailyLimit = 1, MinLevel = 20, Hours = 12,
	},
	{
		Key = "ComboDespegue", Group = "Progreso", Kind = "Combo", Lane = "Horas", Price = 99,
		Components = { "Boost4h", "Horas3" },
		Name = "Combo Despegue",
		Desc = "Boost de XP +50% (4 h) y paquete de 3 horas en una sola compra.",
		ProductId = 2064342565, PriceText = "99 R$", DailyLimit = 1, MinLevel = 20, Seconds = 4 * 3600, Mult = 1.5, Hours = 3,
	},
	{
		Key = "ComboMaraton", Group = "Progreso", Kind = "Combo", Lane = "Horas", Price = 169,
		Components = { "Boost4h", "Horas8" },
		Name = "Combo Maratón",
		Desc = "Boost de XP +50% (4 h) y paquete de 8 horas en una sola compra.",
		ProductId = 2063900141, PriceText = "169 R$", DailyLimit = 1, MinLevel = 20, Seconds = 4 * 3600, Mult = 1.5, Hours = 8,
	},
} :: { Product }

ProductCatalog.ByKey = {} :: { [string]: Product }
for _, p in ipairs(ProductCatalog.Products) do
	ProductCatalog.ByKey[p.Key] = p
end

-- Para combos: (precio sumando las partes por separado, lo que ahorras). Para el resto: (precio, 0).
function ProductCatalog.Savings(p: Product): (number, number)
	if not p.Components then
		return p.Price, 0
	end
	local sum = 0
	for _, k in ipairs(p.Components) do
		local c = ProductCatalog.ByKey[k]
		if c then
			sum += c.Price
		end
	end
	return sum, math.max(0, sum - p.Price)
end

-- XP que da un paquete de `hours` horas a `level`, con el tope de niveles por compra.
-- GB = ReplicatedStorage.Modules.GameBalance (se pasa para no depender de él aquí). Devuelve (xp, niveles aproximados).
function ProductCatalog.HoursXp(GB: any, hours: number, level: number, currentXp: number): (number, number)
	if level >= GB.MAX_LEVEL then
		return 0, 0
	end
	local xp = hours * GB.KILLS_PER_HOUR * GB.MobXp(level)
	-- tope: lo que falta para el siguiente nivel + (MAX_LEVELS_PER_USE - 1) niveles enteros más
	local cap = GB.XpToNext(level) - currentXp
	for i = 1, ProductCatalog.MAX_LEVELS_PER_USE - 1 do
		if level + i < GB.MAX_LEVEL then
			cap += GB.XpToNext(level + i)
		end
	end
	local granted = math.floor(math.min(xp, math.max(cap, 0)))
	return granted, granted / math.max(GB.XpToNext(level), 1)
end

return ProductCatalog