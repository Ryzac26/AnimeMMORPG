--!strict
--[[
    TitleCatalog (ModuleScript) -> ReplicatedStorage.Modules.TitleCatalog
    TÍTULOS ÚNICOS. Un solo lugar para agregar/editar títulos; TitleService decide cuándo se desbloquean y TitleClient los muestra.
      Id        : clave estable (se guarda en el perfil; NO la cambies una vez publicada).
      Name      : texto que se ve sobre el personaje.
      Rarity    : Comun / Raro / Epico / Legendario / Mitico (color y degradado).
      Cat       : categoría de la ventana (Progreso / Combate / Forja / Salón / Facción / Especial).
      Kind      : cómo se consigue:
                    Level  (Value = nivel)        Kill / Metin / Boss (Value = cantidad acumulada)
                    Min    (Value = minutos conectado)
                    Dmg    (Value = mejor prueba de daño en el maniquí del Salón de Honor)
                    Forja9 (Value = piezas +9)
                    Grant  (lo entrega el servidor por un hecho: podio del Salón, Casa VIP, etc.)
      Faction   : si existe, solo esa facción puede tenerlo.
      Icon / Fx : emoji del título (usa solo emojis que Roblox dibuja) y fondo animado de TitleBadge:
      Bonus     : { Xp = 0.005 } etc. Solo los títulos por nivel lo tienen; se suma al texto de Desc automáticamente.
                  simple · rayos · llamas · aurora · estrellas · petalos · eclipse · cristal · oro · ki · hojas · olas · niebla
]]
local TitleCatalog = {}

export type Title = {
	Id: string, Name: string, Desc: string, Rarity: string, Cat: string, Kind: string, Value: number?, Faction: string?, Icon: string?, Fx: string?,
	Bonus: { [string]: number }?, -- bonus pequeño y permanente mientras el título está EQUIPADO (Xp, Oro, Suerte, Vida, Ataque, Defensa)
}

TitleCatalog.Rarities = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
TitleCatalog.RarityName = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" } :: { [string]: string }
-- Degradado del texto { color A, color B }
TitleCatalog.RarityColors = {
	Comun = { Color3.fromRGB(226, 228, 236), Color3.fromRGB(160, 166, 184) },
	Raro = { Color3.fromRGB(130, 200, 255), Color3.fromRGB(70, 130, 255) },
	Epico = { Color3.fromRGB(226, 150, 255), Color3.fromRGB(150, 80, 255) },
	Legendario = { Color3.fromRGB(255, 226, 120), Color3.fromRGB(255, 140, 40) },
	Mitico = { Color3.fromRGB(255, 130, 170), Color3.fromRGB(255, 60, 90) },
} :: { [string]: { Color3 } }

TitleCatalog.Categories = { "Progreso", "Combate", "Forja", "Salón", "Facción", "Especial", "VIP" }

TitleCatalog.List = {
	-- PROGRESO (nivel)
	-- Un título cada 150 niveles (20 en total); cada uno da un bonus pequeño equipado (se calcula abajo)
	{ Id = "Lv150", Name = "Chispa Despierta", Desc = "Llega al nivel 150.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 150, Icon = "🔥", Fx = "simple" },
	{ Id = "Lv450", Name = "Caminante de Cenizas", Desc = "Llega al nivel 450.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 450, Icon = "🌫", Fx = "niebla" },
	{ Id = "Lv600", Name = "Cazador de Horizontes", Desc = "Llega al nivel 600.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 600, Icon = "🏹", Fx = "hojas" },
	{ Id = "Lv900", Name = "Voluntad Inquebrantable", Desc = "Llega al nivel 900.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 900, Icon = "🛡", Fx = "cristal" },
	{ Id = "Lv1050", Name = "Furia del Alba Roja", Desc = "Llega al nivel 1050.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 1050, Icon = "🌋", Fx = "llamas" },
	{ Id = "Lv1200", Name = "Eco de Mil Batallas", Desc = "Llega al nivel 1200.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1200, Icon = "🔔", Fx = "olas" },
	{ Id = "Lv1350", Name = "Señor de las Tormentas", Desc = "Llega al nivel 1350.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1350, Icon = "🌩", Fx = "rayos" },
	{ Id = "Lv1650", Name = "Heraldo del Vacío", Desc = "Llega al nivel 1650.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1650, Icon = "🌀", Fx = "eclipse" },
	{ Id = "Lv1800", Name = "Portador de Estrellas", Desc = "Llega al nivel 1800.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1800, Icon = "💫", Fx = "estrellas" },
	{ Id = "Lv1950", Name = "Coloso Imparable", Desc = "Llega al nivel 1950.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 1950, Icon = "🗿", Fx = "cristal" },
	{ Id = "Lv2100", Name = "Dragón de Ceniza Dorada", Desc = "Llega al nivel 2100.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2100, Icon = "🐉", Fx = "llamas" },
	{ Id = "Lv2400", Name = "Muralla del Reino", Desc = "Llega al nivel 2400.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2400, Icon = "🏰", Fx = "oro" },
	{ Id = "Lv2550", Name = "Voz del Trueno Eterno", Desc = "Llega al nivel 2550.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2550, Icon = "📯", Fx = "rayos" },
	{ Id = "Lv2700", Name = "Soberano de la Aurora", Desc = "Llega al nivel 2700.", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 2700, Icon = "🌠", Fx = "aurora" },
	{ Id = "Lv2850", Name = "Último Umbral", Desc = "Llega al nivel 2850.", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 2850, Icon = "🔱", Fx = "eclipse" },
	{ Id = "Lv10", Name = "Estrella Naciente", Desc = "Llega al nivel 300.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 300, Icon = "🌟", Fx = "simple" },
	{ Id = "Lv25", Name = "Vanguardia del Alba", Desc = "Llega al nivel 750.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 750, Icon = "🌅", Fx = "aurora" },
	{ Id = "Lv50", Name = "Filo de Medianoche", Desc = "Llega al nivel 1500.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1500, Icon = "🌙", Fx = "estrellas" },
	{ Id = "Lv75", Name = "Tormenta Viviente", Desc = "Llega al nivel 2250.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2250, Icon = "⚡", Fx = "rayos" },
	{ Id = "Lv100", Name = "Leyenda Inmortal", Desc = "Llega al nivel máximo (3000).", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 3000, Icon = "👑", Fx = "oro" },
	{ Id = "Min600", Name = "Compañero Eterno", Desc = "Pasa 10 horas conectado.", Rarity = "Raro", Cat = "Progreso", Kind = "Min", Value = 600, Icon = "⏳", Fx = "simple" },

	-- COMBATE
	{ Id = "Kill100", Name = "Cazador Incansable", Desc = "Derrota 100 monstruos.", Rarity = "Comun", Cat = "Combate", Kind = "Kill", Value = 100, Icon = "🗡️", Fx = "simple" },
	{ Id = "Kill1000", Name = "Segador de Bestias", Desc = "Derrota 1.000 monstruos.", Rarity = "Raro", Cat = "Combate", Kind = "Kill", Value = 1000, Icon = "💀", Fx = "simple" },
	{ Id = "Kill10000", Name = "Azote del Mapa", Desc = "Derrota 10.000 monstruos.", Rarity = "Epico", Cat = "Combate", Kind = "Kill", Value = 10000, Icon = "🔥", Fx = "llamas" },
	{ Id = "Metin10", Name = "Rompepiedras", Desc = "Destruye 10 piedras Metin.", Rarity = "Comun", Cat = "Combate", Kind = "Metin", Value = 10, Icon = "🔷", Fx = "simple" },
	{ Id = "Metin100", Name = "Demoledor de Sellos", Desc = "Destruye 100 piedras Metin.", Rarity = "Epico", Cat = "Combate", Kind = "Metin", Value = 100, Icon = "💠", Fx = "cristal" },
	{ Id = "Boss1", Name = "Cazador de Titanes", Desc = "Participa en la caída de un jefe mundial.", Rarity = "Raro", Cat = "Combate", Kind = "Boss", Value = 1, Icon = "🐉", Fx = "simple" },
	{ Id = "Boss10", Name = "Terror de los Titanes", Desc = "Participa en la caída de 10 jefes mundiales.", Rarity = "Legendario", Cat = "Combate", Kind = "Boss", Value = 10, Icon = "🐲", Fx = "rayos" },

	-- FORJA
	{ Id = "Forja9", Name = "Maestro Forjador", Desc = "Forja una pieza +9.", Rarity = "Legendario", Cat = "Forja", Kind = "Forja9", Value = 1, Icon = "🔨", Fx = "llamas" },
	{ Id = "Forja9x5", Name = "Yunque Eterno", Desc = "Forja 5 piezas +9.", Rarity = "Mitico", Cat = "Forja", Kind = "Forja9", Value = 5, Icon = "🛠️", Fx = "oro" },

	-- SALÓN DE HONOR (maniquíes y ranking)
	{ Id = "Dmg10k", Name = "Puños de Hierro", Desc = "Haz 10.000 de daño en una prueba de 30 s.", Rarity = "Comun", Cat = "Salón", Kind = "Dmg", Value = 10000, Icon = "👊", Fx = "simple" },
	{ Id = "Dmg100k", Name = "Golpe Devastador", Desc = "Haz 100.000 de daño en una prueba de 30 s.", Rarity = "Raro", Cat = "Salón", Kind = "Dmg", Value = 100000, Icon = "💥", Fx = "simple" },
	{ Id = "Dmg1m", Name = "Fuerza Imparable", Desc = "Haz 1.000.000 de daño en una prueba de 30 s.", Rarity = "Epico", Cat = "Salón", Kind = "Dmg", Value = 1000000, Icon = "🌋", Fx = "llamas" },
	{ Id = "Dmg10m", Name = "Destructor de Mundos", Desc = "Haz 10.000.000 de daño en una prueba de 30 s.", Rarity = "Legendario", Cat = "Salón", Kind = "Dmg", Value = 10000000, Icon = "🌠", Fx = "rayos" },
	{ Id = "Podio", Name = "Elegido del Podio", Desc = "Llega al podio de daño de tu facción (top 3).", Rarity = "Legendario", Cat = "Salón", Kind = "Grant", Icon = "🏆", Fx = "oro" },
	{ Id = "Campeon", Name = "Campeón del Salón", Desc = "Sé el nº 1 del ranking de daño de tu facción.", Rarity = "Mitico", Cat = "Salón", Kind = "Grant", Icon = "🥇", Fx = "oro" },

	-- FACCIÓN (uno exclusivo por facción, nivel 30)
	{ Id = "F_Saiyan", Name = "Guerrero del Cielo Roto", Desc = "Exclusivo del Imperio Saiyan. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Saiyan", Icon = "⭐", Fx = "ki" },
	{ Id = "F_Shinobi", Name = "Susurro de las Hojas", Desc = "Exclusivo de la Alianza Shinobi. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Shinobi", Icon = "🍃", Fx = "hojas" },
	{ Id = "F_Pirate", Name = "Lobo de la Marea Negra", Desc = "Exclusivo de la Flota Pirata. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Pirate", Icon = "⚓", Fx = "olas" },
	{ Id = "F_Shinigami", Name = "Guardián del Velo Pálido", Desc = "Exclusivo de la Corte Shinigami. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Shinigami", Icon = "🦋", Fx = "niebla" },

	-- ESPECIAL
	-- VIP: se compran con Sellos Imperiales en la Tienda VIP del Mes (VipShopCatalog)
	{ Id = "V_Noble", Name = "Noble de la Corte", Desc = "Tienda VIP del Mes.", Rarity = "Epico", Cat = "VIP", Kind = "Grant", Icon = "🌸", Fx = "petalos" },
	{ Id = "V_Luna", Name = "Señor de la Luna Nueva", Desc = "Tienda VIP del Mes.", Rarity = "Epico", Cat = "VIP", Kind = "Grant", Icon = "🌜", Fx = "estrellas" },
	{ Id = "V_Mecenas", Name = "Mecenas del Reino", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "💰", Fx = "oro" },
	{ Id = "V_Alba", Name = "Heraldo del Amanecer Dorado", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "🌄", Fx = "aurora" },
	{ Id = "V_Eclipse", Name = "Guardián del Eclipse", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "🌘", Fx = "eclipse" },
	{ Id = "V_Corona", Name = "Portador de la Corona de Cristal", Desc = "Tienda VIP del Mes.", Rarity = "Mitico", Cat = "VIP", Kind = "Grant", Icon = "💎", Fx = "cristal" },
	{ Id = "Casa", Name = "Señor del Pabellón", Desc = "Posee tu Casa VIP.", Rarity = "Epico", Cat = "Especial", Kind = "Grant", Icon = "🏯", Fx = "aurora" },
} :: { Title }

-- BONUS por nivel (solo títulos de la categoría Progreso con Kind Level y sin facción): rota Xp, Oro, Suerte, Vida, Ataque, Defensa
-- y crece con el nivel (0,4% en el 150 -> 1% en el 2850); el de nivel 3000 da +2% de XP y de oro.
local STAT_ORDER = { "Xp", "Oro", "Suerte", "Vida", "Ataque", "Defensa" }
local STAT_NAME = { Xp = "XP", Oro = "oro", Suerte = "suerte", Vida = "vida", Ataque = "ataque", Defensa = "defensa" } :: { [string]: string }
local function pct(v: number): string
	return string.gsub(string.format("%.1f", v * 100), "%.", ",")
end
do
	local lv: { Title } = {}
	for _, t in ipairs(TitleCatalog.List) do
		if t.Cat == "Progreso" and t.Kind == "Level" and not t.Faction and t.Value then
			table.insert(lv, t)
		end
	end
	table.sort(lv, function(a, b)
		return (a.Value :: number) < (b.Value :: number)
	end)
	for i, t in ipairs(lv) do
		local v = math.floor((0.004 + 0.006 * ((t.Value :: number) / 3000)) * 1000 + 0.5) / 1000
		local bonus: { [string]: number } = {}
		local text
		if i == #lv then
			bonus = { Xp = 0.02, Oro = 0.02 }
			text = "+2% XP y +2% oro"
		else
			local st = STAT_ORDER[(i - 1) % #STAT_ORDER + 1]
			bonus[st] = v
			text = string.format("+%s%% %s", pct(v), STAT_NAME[st])
		end
		t.Bonus = bonus
		t.Desc = t.Desc .. " Equipado: " .. text .. "."
	end
end

TitleCatalog.ById = {} :: { [string]: Title }
for _, t in ipairs(TitleCatalog.List) do
	TitleCatalog.ById[t.Id] = t
end

return TitleCatalog
