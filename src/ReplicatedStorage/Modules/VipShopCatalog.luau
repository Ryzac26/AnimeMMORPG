--!strict
--[[
    VipShopCatalog (ModuleScript) -> ReplicatedStorage.Modules.VipShopCatalog
    TIENDA VIP DEL MES. Solo cosméticos (nada de poder extra). Se paga con SELLOS IMPERIALES, que solo ganan los suscriptores de la
    Suscripción Imperial (atributo Sub_Vip):
        +5 por entrar cada día · +10 por cada misión diaria reclamada · +30 por cada misión semanal reclamada
    La vitrina muestra PER_MONTH artículos y cambia sola el día 1 de cada mes (UTC): los comprados son tuyos para siempre.
    Para agregar artículos: añade una fila a Items (el orden importa: la vitrina del mes toma PER_MONTH seguidos, dando la vuelta).
      Kind: Title (Ref = Id de TitleCatalog) · Furniture (Ref = Id de HouseFurniture con Vip=true) · Aura (Ref = clave de Auras).
]]
local VipShopCatalog = {}

VipShopCatalog.PER_MONTH = 6
VipShopCatalog.Earn = { Login = 5, Daily = 10, Weekly = 30 }

export type Item = { Id: string, Kind: string, Ref: string, Name: string, Desc: string, Price: number, Icon: string, Rarity: string }

VipShopCatalog.Items = {
	{ Id = "t_noble", Kind = "Title", Ref = "V_Noble", Name = "Título: Noble de la Corte", Desc = "Se muestra sobre tu personaje. Equípalo en Ajustes → Mis títulos.", Price = 400, Icon = "⚜", Rarity = "Epico" },
	{ Id = "f_trono", Kind = "Furniture", Ref = "Trono", Name = "Trono Imperial", Desc = "Mueble para tu Casa VIP: ¡puedes sentarte! Colócalo en Decorar.", Price = 450, Icon = "👑", Rarity = "Legendario" },
	{ Id = "a_oro", Kind = "Aura", Ref = "Oro", Name = "Aura de Oro", Desc = "Destellos dorados a tu alrededor. Actívala aquí mismo.", Price = 350, Icon = "✨", Rarity = "Epico" },
	{ Id = "t_luna", Kind = "Title", Ref = "V_Luna", Name = "Título: Señor de la Luna Nueva", Desc = "Se muestra sobre tu personaje. Equípalo en Ajustes → Mis títulos.", Price = 400, Icon = "🌙", Rarity = "Epico" },
	{ Id = "f_estatua", Kind = "Furniture", Ref = "Estatua", Name = "Estatua Dorada", Desc = "Mueble para tu Casa VIP, con un orbe de luz. Colócalo en Decorar.", Price = 350, Icon = "🗿", Rarity = "Epico" },
	{ Id = "a_petalos", Kind = "Aura", Ref = "Petalos", Name = "Aura de Pétalos", Desc = "Pétalos rosados que flotan a tu alrededor. Actívala aquí mismo.", Price = 350, Icon = "🌸", Rarity = "Epico" },

	{ Id = "t_mecenas", Kind = "Title", Ref = "V_Mecenas", Name = "Título: Mecenas del Reino", Desc = "Se muestra sobre tu personaje. Equípalo en Ajustes → Mis títulos.", Price = 600, Icon = "💰", Rarity = "Legendario" },
	{ Id = "f_cristal", Kind = "Furniture", Ref = "Cristal", Name = "Cristal Flotante", Desc = "Mueble para tu Casa VIP que brilla y suelta destellos. Colócalo en Decorar.", Price = 450, Icon = "💎", Rarity = "Legendario" },
	{ Id = "a_estrellas", Kind = "Aura", Ref = "Estrellas", Name = "Aura de Estrellas", Desc = "Estrellas violetas que giran a tu alrededor. Actívala aquí mismo.", Price = 400, Icon = "⭐", Rarity = "Legendario" },
	{ Id = "t_alba", Kind = "Title", Ref = "V_Alba", Name = "Título: Heraldo del Amanecer Dorado", Desc = "Se muestra sobre tu personaje. Equípalo en Ajustes → Mis títulos.", Price = 600, Icon = "🌅", Rarity = "Legendario" },
	{ Id = "t_eclipse", Kind = "Title", Ref = "V_Eclipse", Name = "Título: Guardián del Eclipse", Desc = "Se muestra sobre tu personaje. Equípalo en Ajustes → Mis títulos.", Price = 600, Icon = "🌑", Rarity = "Legendario" },
	{ Id = "t_corona", Kind = "Title", Ref = "V_Corona", Name = "Título: Portador de la Corona de Cristal", Desc = "El título más raro de la tienda. Equípalo en Ajustes → Mis títulos.", Price = 900, Icon = "💎", Rarity = "Mitico" },
} :: { Item }

VipShopCatalog.ById = {} :: { [string]: Item }
for _, it in ipairs(VipShopCatalog.Items) do
	VipShopCatalog.ById[it.Id] = it
end

-- Auras (efecto de partículas en el personaje): colores y ritmo
VipShopCatalog.Auras = {
	Oro = { Name = "Aura de Oro", A = Color3.fromRGB(255, 226, 120), B = Color3.fromRGB(255, 150, 40), Rate = 14, Speed = 2, Size = 0.35 },
	Petalos = { Name = "Aura de Pétalos", A = Color3.fromRGB(255, 190, 210), B = Color3.fromRGB(255, 120, 170), Rate = 10, Speed = 1.5, Size = 0.5 },
	Estrellas = { Name = "Aura de Estrellas", A = Color3.fromRGB(190, 150, 255), B = Color3.fromRGB(120, 210, 255), Rate = 12, Speed = 2.5, Size = 0.4 },
} :: { [string]: { Name: string, A: Color3, B: Color3, Rate: number, Speed: number, Size: number } }

-- número de mes (UTC) y segundos que faltan para el siguiente
function VipShopCatalog.MonthIndex(now: number?): number
	local t = os.date("!*t", now or os.time())
	return t.year * 12 + (t.month - 1)
end

function VipShopCatalog.SecondsLeft(now: number?): number
	local n = now or os.time()
	local t = os.date("!*t", n)
	local nextMonth = os.time({ year = t.year + (if t.month == 12 then 1 else 0), month = (t.month % 12) + 1, day = 1, hour = 0, min = 0, sec = 0 })
	return math.max(0, nextMonth - n)
end

-- artículos de la vitrina del mes
function VipShopCatalog.Month(now: number?): { Item }
	local n = #VipShopCatalog.Items
	local per = math.min(VipShopCatalog.PER_MONTH, n)
	local start = (VipShopCatalog.MonthIndex(now) % math.max(1, n // per)) * per
	local out: { Item } = {}
	for i = 0, per - 1 do
		table.insert(out, VipShopCatalog.Items[(start + i) % n + 1])
	end
	return out
end

return VipShopCatalog
