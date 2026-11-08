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
        LEVELS_CAP_PER_HOUR niveles por cada hora del paquete, para que no sirva para saltarse el inicio.
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
	Icon: string?, -- opcional: "rbxassetid://..." propio; si no, se toma el icono del Developer Product (GetProductInfo)
	Name: string,
	Desc: string,
	ProductId: number,
	PriceText: string,
	DailyLimit: number,
	MinLevel: number,
	Seconds: number?,
	Mult: number?,
	Hours: number?,
	BlessGroup: string?, -- Kind "Blessing": línea de tiempo de la Bendición de Facción (ProductCatalog.BlessGroups)
	BlessSeconds: number?, -- Kind "Blessing": segundos que suma a esa línea
	Items: { [string]: number }?, -- Kind "Item": objetos que se entregan en la mochila (id -> cantidad)
}

ProductCatalog.MIN_LEVEL_HOURS = 20
-- Tope de niveles por hora del paquete (0,6): a nivel bajo el paquete da menos que jugar (protege el inicio); desde ~nivel 45 ya no se nota.
ProductCatalog.LEVELS_CAP_PER_HOUR = 18 -- niveles (escala 1-3000) por hora del paquete; antes 0,6 niveles viejos

-- CALIBRACIÓN con jugadores reales (nov 2026): XP por hora de juego REAL ÷ lo que dice el modelo de GameBalance.
--   nivel 20 (= 600 en la escala nueva): 15,6 % de nivel en 3 min y 1 nivel en 18 min  -> ≈ 62.000 XP/h  (modelo 10.206)  -> x6,1
--   nivel 50 (= 1500): 10,9 % (74.369 XP) en 20 min                   -> ≈ 223.000 XP/h (modelo 77.616)  -> x2,87
--   nivel 100 (= 3000): SIN MEDIR (estimado x1,6). Volver a medir a nivel 80+ y corregir esta tabla.
-- Así un paquete de N horas da lo mismo que jugar N horas a ritmo normal. Entre puntos se interpola (logarítmico).
ProductCatalog.RATE_POINTS = { { 600, 6.1 }, { 1500, 2.87 }, { 3000, 1.6 } } :: { { number } }

function ProductCatalog.RateFactor(level: number): number
	local pts = ProductCatalog.RATE_POINTS
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			local t = (math.log(level) - math.log(a[1])) / (math.log(b[1]) - math.log(a[1]))
			return math.exp(math.log(a[2]) + t * (math.log(b[2]) - math.log(a[2])))
		end
	end
	return pts[#pts][2]
end
ProductCatalog.MAX_BOOST_SECONDS = 12 * 3600

-- BENDICIONES DE FACCIÓN (de pago): un jugador las compra y TODA su facción en ese servidor recibe el bono mientras dure.
--   · El tiempo solo corre si hay jugadores de la facción en el servidor. Varias compras del mismo grupo SUMAN tiempo (no el bono).
--   · Si dos grupos dan el mismo bono, vale el mayor (no se acumulan). Tope por facción y día en este servidor: BLESS_DAILY_SECONDS.
--   · Si el servidor se cierra CON jugadores dentro (actualización, apagado), el tiempo sobrante se devuelve a quien lo compró
--     como bendición PERSONAL (la recibe al volver a entrar). Si se cierra por quedar vacío, no se devuelve.
ProductCatalog.BLESS_DAILY_SECONDS = 24 * 3600
ProductCatalog.BLESS_MAX_PERSONAL = 24 * 3600
ProductCatalog.BlessGroups = {
	Xp = { Name = "Bendición de Sabiduría", Short = "XP +50%", Stats = { Xp = 0.5 } },
	Oro = { Name = "Bendición de Fortuna", Short = "Oro +20%", Stats = { Oro = 0.2 } },
	Suerte = { Name = "Bendición de Hallazgo", Short = "Suerte +20%", Stats = { Suerte = 0.2 } },
	Total = { Name = "Bendición Total", Short = "XP +50% · Oro +20% · Suerte +20%", Stats = { Xp = 0.5, Oro = 0.2, Suerte = 0.2 } },
} :: { [string]: { Name: string, Short: string, Stats: { [string]: number } } }

ProductCatalog.Products = {
	{
		Key = "Boost4h", Group = "Progreso", Kind = "Boost", Lane = "Boost", Price = 49, Name = "Boost de XP +50% (4 h)",
		Desc = "+50% de XP durante 4 horas de juego. Comprar más suma tiempo.",
		ProductId = 2064418488, PriceText = "49 R$", DailyLimit = 3, MinLevel = 1, Seconds = 4 * 3600, Mult = 1.5,
	},
	{
		Key = "Horas3", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 59, Name = "Paquete de 3 horas",
		Desc = "Recupera la XP de 3 horas de juego a tu nivel actual.",
		ProductId = 2064189703, PriceText = "59 R$", DailyLimit = 2, MinLevel = 600, Hours = 3,
	},
	{
		Key = "Horas5", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 89, Name = "Paquete de 5 horas",
		Desc = "Recupera la XP de 5 horas de juego a tu nivel actual.",
		ProductId = 2063976038, PriceText = "89 R$", DailyLimit = 1, MinLevel = 600, Hours = 5,
	},
	{
		Key = "Horas8", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 139, Name = "Paquete de 8 horas",
		Desc = "Recupera la XP de 8 horas de juego a tu nivel actual.",
		ProductId = 2064089903, PriceText = "139 R$", DailyLimit = 1, MinLevel = 600, Hours = 8,
	},
	{
		Key = "Horas12", Group = "Progreso", Kind = "Hours", Lane = "Horas", Price = 199, Name = "Paquete de 12 horas",
		Desc = "Recupera la XP de 12 horas de juego a tu nivel actual.",
		ProductId = 2063992040, PriceText = "199 R$", DailyLimit = 1, MinLevel = 600, Hours = 12,
	},
	{
		Key = "ComboDespegue", Group = "Progreso", Kind = "Combo", Lane = "Horas", Price = 99,
		Components = { "Boost4h", "Horas3" },
		Name = "Combo Despegue",
		Desc = "Boost de XP +50% (4 h) y paquete de 3 horas en una sola compra.",
		ProductId = 2064342565, PriceText = "99 R$", DailyLimit = 1, MinLevel = 600, Seconds = 4 * 3600, Mult = 1.5, Hours = 3,
	},
	{
		Key = "ComboMaraton", Group = "Progreso", Kind = "Combo", Lane = "Horas", Price = 169,
		Components = { "Boost4h", "Horas8" },
		Name = "Combo Maratón",
		Desc = "Boost de XP +50% (4 h) y paquete de 8 horas en una sola compra.",
		ProductId = 2063900141, PriceText = "169 R$", DailyLimit = 1, MinLevel = 600, Seconds = 4 * 3600, Mult = 1.5, Hours = 8,
	},
	-- OBJETOS (sin bloqueo entre sí ni con los paquetes): se entregan en la mochila
	{
		Key = "Pergamino1", Group = "Objetos", Kind = "Item", Lane = "Objetos", Price = 25, Name = "Pergamino de Protección",
		Desc = "Evita que tu equipo baje de nivel o se ROMPA al fallar una mejora +7, +8 o +9 en el Herrero.",
		ProductId = 2067307786, PriceText = "25 R$", DailyLimit = 20, MinLevel = 1, Items = { Pergamino_Proteccion = 1 },
	},
	{
		Key = "Pergamino5", Group = "Objetos", Kind = "Item", Lane = "Objetos", Price = 99, Components = { "Pergamino1", "Pergamino1", "Pergamino1", "Pergamino1", "Pergamino1" },
		Name = "Pack x5 Pergaminos de Protección",
		Desc = "5 Pergaminos de Protección en una sola compra, más barato que por separado.",
		ProductId = 2067373763, PriceText = "99 R$", DailyLimit = 10, MinLevel = 1, Items = { Pergamino_Proteccion = 5 },
	},
	-- CASA VIP: recompra del pago único cuando la licencia venció (la ofrece el portal del Pabellón; no sale en la Tienda)
	{
		Key = "VipHouseRebuy", Group = "Casa", Kind = "HouseLicense", Lane = "Casa", Price = 599, Name = "Pabellón Imperial (recompra)",
		Desc = "Vuelve a activar tu Casa VIP tras vencer la suscripción. Sujeto a cupo de casas.",
		ProductId = 0, PriceText = "599 R$", DailyLimit = 99, MinLevel = 1, -- TODO: crea este Developer Product (599 R$) y pega aquí su ID
	},
	-- BENDICIONES DE FACCIÓN (ver reglas arriba). Crea cada Developer Product y pega su ID; con ProductId 0 solo se prueba en Studio.
	{
		Key = "BlessXp3", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 449, Name = "Sabiduría 3 h",
		Desc = "+50% de XP para toda tu facción en este servidor durante 3 horas.",
		ProductId = 2073006411, PriceText = "449 R$", DailyLimit = 8, MinLevel = 1, BlessGroup = "Xp", BlessSeconds = 3 * 3600,
	},
	{
		Key = "BlessXp5", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 699, Name = "Sabiduría 5 h",
		Desc = "+50% de XP para toda tu facción durante 5 horas.",
		ProductId = 2068058795, PriceText = "699 R$", DailyLimit = 5, MinLevel = 1, BlessGroup = "Xp", BlessSeconds = 5 * 3600,
	},
	{
		Key = "BlessXp8", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 999, Name = "Sabiduría 8 h",
		Desc = "+50% de XP para toda tu facción durante 8 horas.",
		ProductId = 2071285111, PriceText = "999 R$", DailyLimit = 3, MinLevel = 1, BlessGroup = "Xp", BlessSeconds = 8 * 3600,
	},
	{
		Key = "BlessOro4", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 249, Name = "Fortuna 4 h",
		Desc = "+20% de oro para toda tu facción durante 4 horas.",
		ProductId = 2073384365, PriceText = "249 R$", DailyLimit = 6, MinLevel = 1, BlessGroup = "Oro", BlessSeconds = 4 * 3600,
	},
	{
		Key = "BlessSuerte4", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 249, Name = "Hallazgo 4 h",
		Desc = "+20% de suerte con el botín para toda tu facción durante 4 horas.",
		ProductId = 2073920260, PriceText = "249 R$", DailyLimit = 6, MinLevel = 1, BlessGroup = "Suerte", BlessSeconds = 4 * 3600,
	},
	{
		Key = "BlessTotal4", Group = "Gremio", Kind = "Blessing", Lane = "Gremio", Price = 799, Name = "Bendición Total 4 h",
		Desc = "XP +50%, oro +20% y suerte +20% para toda tu facción durante 4 horas.",
		ProductId = 2068052819, PriceText = "799 R$", DailyLimit = 4, MinLevel = 1, BlessGroup = "Total", BlessSeconds = 4 * 3600,
	},
} :: { Product }

---------------------------------------------------------------------
-- PASES (se compran UNA sola vez, Game Pass). Creación: Creator Hub > tu experiencia > Monetización > Pases.
-- Pega el ID en PassId. Con PassId = 0 no se puede comprar en el juego publicado (en Studio se entrega para probar).
-- Al tenerlo, el jugador recibe el atributo `Attr` (true) y los sistemas lo consultan.
---------------------------------------------------------------------
export type Pass = {
	Key: string,
	Attr: string,
	Name: string,
	Desc: string,
	Perks: { string },
	PassId: number,
	PriceText: string,
	Icon: string?,
}
-- Solo Studio: pases que TU cuenta tendrá "comprados" para probar. false = como un jugador sin el pase.
ProductCatalog.DevOwnPasses = { Belt = false, Merchant = false, Multiclass = false, PetSlot = false, VipHouse = false, Talents2 = true, Talents3 = true } :: { [string]: boolean }

ProductCatalog.Passes = {
	{
		Key = "Belt", Attr = "Pass_Belt", Name = "Cinturón de Pociones",
		Desc = "Fabrica pociones Mayor y Suprema y deja que el Auto-farm las use.",
		Perks = {
			"Fabrica pociones Mayor (50%) y Suprema (75%) con el Alquimista",
			"El Auto-farm las usa solas",
			"Elige el grado a mano o deja \"Auto\" = siempre la mejor que tengas",
			"Sin el pase: solo pociones normales (Auto-farm incluido)",
		},
		PassId = 2067774732, PriceText = "99 R$",
	},
	{
		Key = "Merchant", Attr = "Pass_Merchant", Name = "Mercader Portátil",
		Desc = "Compra y vende desde cualquier lugar, sin volver a la ciudad.",
		Perks = {
			"Abre el Mercader en cualquier parte (botón 🛒 o tecla V)",
			"Compra pociones y vende equipo por rareza sin regresar a la ciudad",
			"Ideal para el Auto-farm largo: vacía la mochila y repón pociones sin viajar",
		},
		PassId = 2068735719, PriceText = "99 R$",
	},
	{
		Key = "Multiclass", Attr = "Pass_Multiclass", Name = "Maestría Multiclase",
		Desc = "Cambia de rol en cualquier lugar, guarda tu equipo por rol y sube la maestría más rápido.",
		Perks = {
			"Cambia de rol donde estés (sin ir al Instructor), volviendo al mismo sitio",
			"Tu equipo se guarda por rol: al cambiar se pone lo último que usaste con él",
			"La maestría de cada rol sube un 25% más rápido",
			"Sin el pase: la maestría y el cambio gratis con el Instructor siguen funcionando",
		},
		PassId = 2068231801, PriceText = "149 R$",
	},
	{
		Key = "PetSlot", Attr = "Pass_PetSlot", Name = "Segunda Mascota",
		Desc = "Lleva dos mascotas a la vez: se suman sus efectos y poderes.",
		Perks = {
			"Desbloquea la ranura \"Mascota 2\" en el perfil (tecla C)",
			"Las dos mascotas te siguen y suman sus bonos y poderes (deben ser de familias distintas)",
			"Sin el pase: sigues con tu ranura de mascota normal",
		},
		PassId = 2068286395, PriceText = "249 R$", -- TODO: crea el Game Pass en el Creator Hub y pega aquí su ID
	},
	{
		Key = "VipHouse", Attr = "Pass_VipHouse", Name = "Pabellón Imperial",
		Desc = "Pago único para tener tu casa privada, con el primer mes incluido. Después se mantiene con la Suscripción Imperial.",
		Perks = {
			"Casa VIP privada con portal en la plaza de tu ciudad",
			"Baúl privado de 60 casillas y jardín para tus mascotas y montura",
			"Invita a quien quieras: pueden entrar y mirar, pero no tocar nada",
			"El primer mes va incluido; después se mantiene con la Suscripción Imperial (199 R$/mes). Si no se renueva, la casa vence",
		},
		PassId = 2075582326, PriceText = "599 R$",
	},
	{
		Key = "Talents2", Attr = "Pass_Talents2", Name = "Talentos II · Segunda Build",
		Desc = "Una segunda pestaña del árbol de talentos: arma otra build y cámbiala cuando quieras.",
		Perks = {
			"Desbloquea la pestaña 2 del árbol de talentos (mismos puntos, otra distribución)",
			"Vincúlala a un rol: al cambiar de rol se activa sola (ideal con Maestría Multiclase)",
			"Cambiar de build es gratis e instantáneo",
			"Sin el pase: sigues con la pestaña 1 gratuita",
		},
		PassId = 0, PriceText = "149 R$", -- TODO: crea el Game Pass "Talentos II" y pega aquí su ID (precio provisional, lo definimos juntos)
	},
	{
		Key = "Talents3", Attr = "Pass_Talents3", Name = "Talentos III · Tercera Build",
		Desc = "Una tercera pestaña del árbol de talentos para tener tres builds listas (tanque, daño, soporte...).",
		Perks = {
			"Desbloquea la pestaña 3 del árbol de talentos",
			"Vincúlala a un rol para que se active sola al cambiar de rol",
			"Con las tres pestañas tienes una build por cada estilo de juego",
			"Sin el pase: sigues con la pestaña 1 gratuita",
		},
		PassId = 0, PriceText = "199 R$", -- TODO: crea el Game Pass "Talentos III" y pega aquí su ID (precio provisional)
	},
} :: { Pass }

-- SUSCRIPCIÓN IMPERIAL (mensual, se renueva sola). Creación: Creator Hub > Monetización > Suscripciones (precio mínimo 49 R$).
-- Pega el ID (texto "EXP-...") en SubId.
-- DESCRIPCIÓN para el Creator Hub: "Costo mensual para seguir usando tu Casa VIP (Pabellón Imperial). El primer mes va incluido en la compra del
-- Pabellón; se cobra al pasar los 30 días. Con la suscripción activa conservas tu
-- casa, tu baúl de 60 casillas y el jardín de mascotas. Si no se renueva, la casa vence: tu baúl pasa al buzón de la ciudad y para volver a
-- tenerla hay que pagar de nuevo el Pabellón (599 R$), si todavía quedan casas."
-- Al vencer nada se borra: el baúl entero pasa al buzón.
ProductCatalog.VipSub = { SubId = "EXP-2977508916442825297", Attr = "Sub_Vip", Name = "Suscripción Imperial", PriceText = "199 R$/mes" }
-- Casas VIP limitadas: máximo de dueños del pase en total. Al tocar "comprar" se RESERVA una casa 10 minutos; si no se paga, se libera.
ProductCatalog.VIP_HOUSE_CAP = 1000
ProductCatalog.VIP_RESERVE_SECONDS = 600
ProductCatalog.DevOwnSub = false -- solo Studio: true = tu cuenta de prueba cuenta como suscrita

ProductCatalog.PassByKey = {} :: { [string]: Pass }
for _, ps in ipairs(ProductCatalog.Passes) do
	ProductCatalog.PassByKey[ps.Key] = ps
end

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
function ProductCatalog.HoursXp(GB: any, hours: number, level: number, currentXp: number): (number, number, boolean)
	if level >= GB.MAX_LEVEL then
		return 0, 0, false
	end
	local xp = hours * GB.KILLS_PER_HOUR * GB.MobXp(level) * ProductCatalog.RateFactor(level)
	-- tope por compra: LEVELS_CAP_PER_HOUR niveles por cada hora del paquete (así 3 h < 5 h < 8 h < 12 h SIEMPRE, también
	-- a niveles bajos donde jugar da muchos niveles por hora). Se mide desde el nivel actual; no depende de la XP ya ganada.
	local r = hours * ProductCatalog.LEVELS_CAP_PER_HOUR
	local cap = 0
	for i = 0, math.ceil(r) - 1 do
		if level + i < GB.MAX_LEVEL then
			cap += GB.XpToNext(level + i) * math.min(1, r - i)
		end
	end
	local granted = math.floor(math.min(xp, math.max(cap, 0)))
	return granted, granted / math.max(GB.XpToNext(level), 1), xp > math.max(cap, 0)
end

return ProductCatalog
