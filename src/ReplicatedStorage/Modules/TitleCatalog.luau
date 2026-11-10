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
                    Mission (Value = misiones completadas en total)   Hito (Value = hitos de nivel reclamados, de 60)
                    Grant  (lo entrega el servidor por un hecho: podio del Salón, Casa VIP, etc.)
      Faction   : si existe, solo esa facción puede tenerlo.
      Icon / Fx : emoji del título (usa solo emojis que Roblox dibuja) y fondo animado de TitleBadge:
      Look      : estilo visual de la placa (clave de TitleFrames.Looks: Cobre, Acero, Plata, Hierro, Forja, Ascua, Tormenta, Escarcha, Cristal, Honor,
                  Realeza, Campeon, Dragon, Coloso, Muralla, Marea, Velo, Hoja, Saiyan, Sakura, Cosmos, Luna, Aurora, Eclipse). Más rareza = más adornos.
      Bonus     : { Xp = 0.005 } etc. Solo los títulos por nivel lo tienen; se suma al texto de Desc automáticamente.
                  simple · rayos · llamas · aurora · estrellas · petalos · eclipse · cristal · oro · ki · hojas · olas · niebla
]]
local TitleCatalog = {}

export type Title = {
	Id: string, Name: string, Desc: string, Rarity: string, Cat: string, Kind: string, Value: number?, Faction: string?, Icon: string?, Fx: string?, Look: string?,
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

TitleCatalog.Categories = { "Progreso", "Combate", "Forja", "Salón", "Misiones", "Hitos", "Facción", "Especial", "VIP" }

TitleCatalog.List = {
	-- PROGRESO (nivel)
	-- Un título cada 150 niveles (20 en total); cada uno da un bonus pequeño equipado (se calcula abajo)
	{ Id = "Lv150", Name = "Chispa Despierta", Desc = "Llega al nivel 150.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 150, Icon = "🔥", Fx = "simple", Look = "Cobre" },
	{ Id = "Lv450", Name = "Caminante de Cenizas", Desc = "Llega al nivel 450.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 450, Icon = "🌫", Fx = "niebla", Look = "Acero" },
	{ Id = "Lv600", Name = "Cazador de Horizontes", Desc = "Llega al nivel 600.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 600, Icon = "🏹", Fx = "hojas", Look = "Hoja" },
	{ Id = "Lv900", Name = "Voluntad Inquebrantable", Desc = "Llega al nivel 900.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 900, Icon = "🛡", Fx = "cristal", Look = "Plata" },
	{ Id = "Lv1050", Name = "Furia del Alba Roja", Desc = "Llega al nivel 1050.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 1050, Icon = "🌋", Fx = "llamas", Look = "Ascua" },
	{ Id = "Lv1200", Name = "Eco de Mil Batallas", Desc = "Llega al nivel 1200.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1200, Icon = "🔔", Fx = "olas", Look = "Marea" },
	{ Id = "Lv1350", Name = "Señor de las Tormentas", Desc = "Llega al nivel 1350.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1350, Icon = "🌩", Fx = "rayos", Look = "Tormenta" },
	{ Id = "Lv1650", Name = "Heraldo del Vacío", Desc = "Llega al nivel 1650.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1650, Icon = "🌀", Fx = "eclipse", Look = "Eclipse" },
	{ Id = "Lv1800", Name = "Portador de Estrellas", Desc = "Llega al nivel 1800.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1800, Icon = "💫", Fx = "estrellas", Look = "Cosmos" },
	{ Id = "Lv1950", Name = "Coloso Imparable", Desc = "Llega al nivel 1950.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 1950, Icon = "🗿", Fx = "cristal", Look = "Coloso" },
	{ Id = "Lv2100", Name = "Dragón de Ceniza Dorada", Desc = "Llega al nivel 2100.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2100, Icon = "🐉", Fx = "llamas", Look = "Dragon" },
	{ Id = "Lv2400", Name = "Muralla del Reino", Desc = "Llega al nivel 2400.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2400, Icon = "🏰", Fx = "oro", Look = "Muralla" },
	{ Id = "Lv2550", Name = "Voz del Trueno Eterno", Desc = "Llega al nivel 2550.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2550, Icon = "📯", Fx = "rayos", Look = "Tormenta" },
	{ Id = "Lv2700", Name = "Soberano de la Aurora", Desc = "Llega al nivel 2700.", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 2700, Icon = "🌠", Fx = "aurora", Look = "Aurora" },
	{ Id = "Lv2850", Name = "Último Umbral", Desc = "Llega al nivel 2850.", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 2850, Icon = "🔱", Fx = "eclipse", Look = "Eclipse" },
	{ Id = "Lv10", Name = "Estrella Naciente", Desc = "Llega al nivel 300.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 300, Icon = "🌟", Fx = "simple", Look = "Cobre" },
	{ Id = "Lv25", Name = "Vanguardia del Alba", Desc = "Llega al nivel 750.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 750, Icon = "🌅", Fx = "aurora", Look = "Honor" },
	{ Id = "Lv50", Name = "Filo de Medianoche", Desc = "Llega al nivel 1500.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 1500, Icon = "🌙", Fx = "estrellas", Look = "Luna" },
	{ Id = "Lv75", Name = "Tormenta Viviente", Desc = "Llega al nivel 2250.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 2250, Icon = "⚡", Fx = "rayos", Look = "Tormenta" },
	{ Id = "Lv100", Name = "Leyenda Inmortal", Desc = "Llega al nivel máximo (3000).", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 3000, Icon = "👑", Fx = "oro", Look = "Realeza" },
	{ Id = "Min600", Name = "Compañero Eterno", Desc = "Pasa 10 horas conectado.", Rarity = "Raro", Cat = "Progreso", Kind = "Min", Value = 600, Icon = "⏳", Fx = "simple", Look = "Acero" },

	-- COMBATE
	{ Id = "Kill100", Name = "Cazador Incansable", Desc = "Derrota 100 monstruos.", Rarity = "Comun", Cat = "Combate", Kind = "Kill", Value = 100, Icon = "🗡️", Fx = "simple", Look = "Cobre" },
	{ Id = "Kill1000", Name = "Segador de Bestias", Desc = "Derrota 1.000 monstruos.", Rarity = "Raro", Cat = "Combate", Kind = "Kill", Value = 1000, Icon = "💀", Fx = "simple", Look = "Hierro" },
	{ Id = "Kill10000", Name = "Azote del Mapa", Desc = "Derrota 10.000 monstruos.", Rarity = "Epico", Cat = "Combate", Kind = "Kill", Value = 10000, Icon = "🔥", Fx = "llamas", Look = "Ascua" },
	{ Id = "Metin10", Name = "Rompepiedras", Desc = "Destruye 10 piedras Metin.", Rarity = "Comun", Cat = "Combate", Kind = "Metin", Value = 10, Icon = "🔷", Fx = "simple", Look = "Acero" },
	{ Id = "Metin100", Name = "Demoledor de Sellos", Desc = "Destruye 100 piedras Metin.", Rarity = "Epico", Cat = "Combate", Kind = "Metin", Value = 100, Icon = "💠", Fx = "cristal", Look = "Cristal" },
	{ Id = "Boss1", Name = "Cazador de Titanes", Desc = "Participa en la caída de un jefe mundial.", Rarity = "Raro", Cat = "Combate", Kind = "Boss", Value = 1, Icon = "🐉", Fx = "simple", Look = "Plata" },
	{ Id = "Boss10", Name = "Terror de los Titanes", Desc = "Participa en la caída de 10 jefes mundiales.", Rarity = "Legendario", Cat = "Combate", Kind = "Boss", Value = 10, Icon = "🐲", Fx = "rayos", Look = "Coloso" },

	-- FORJA
	{ Id = "Forja9", Name = "Maestro Forjador", Desc = "Forja una pieza +9.", Rarity = "Legendario", Cat = "Forja", Kind = "Forja9", Value = 1, Icon = "🔨", Fx = "llamas", Look = "Forja" },
	{ Id = "Forja9x5", Name = "Yunque Eterno", Desc = "Forja 5 piezas +9.", Rarity = "Mitico", Cat = "Forja", Kind = "Forja9", Value = 5, Icon = "🛠️", Fx = "oro", Look = "Forja" },

	-- SALÓN DE HONOR (maniquíes y ranking)
	{ Id = "Dmg10k", Name = "Puños de Hierro", Desc = "Haz 10.000 de daño en una prueba de 30 s.", Rarity = "Comun", Cat = "Salón", Kind = "Dmg", Value = 10000, Icon = "👊", Fx = "simple", Look = "Cobre" },
	{ Id = "Dmg100k", Name = "Golpe Devastador", Desc = "Haz 100.000 de daño en una prueba de 30 s.", Rarity = "Raro", Cat = "Salón", Kind = "Dmg", Value = 100000, Icon = "💥", Fx = "simple", Look = "Hierro" },
	{ Id = "Dmg1m", Name = "Fuerza Imparable", Desc = "Haz 1.000.000 de daño en una prueba de 30 s.", Rarity = "Epico", Cat = "Salón", Kind = "Dmg", Value = 1000000, Icon = "🌋", Fx = "llamas", Look = "Ascua" },
	{ Id = "Dmg10m", Name = "Destructor de Mundos", Desc = "Haz 10.000.000 de daño en una prueba de 30 s.", Rarity = "Legendario", Cat = "Salón", Kind = "Dmg", Value = 10000000, Icon = "🌠", Fx = "rayos", Look = "Dragon" },
	{ Id = "Podio", Name = "Elegido del Podio", Desc = "Llega al podio de daño de tu facción (top 3).", Rarity = "Legendario", Cat = "Salón", Kind = "Grant", Icon = "🏆", Fx = "oro", Look = "Honor" },
	{ Id = "Campeon", Name = "Campeón del Salón", Desc = "Sé el nº 1 del ranking de daño de tu facción.", Rarity = "Mitico", Cat = "Salón", Kind = "Grant", Icon = "🥇", Fx = "oro", Look = "Campeon" },

	-- FACCIÓN (uno exclusivo por facción, nivel 30)
	{ Id = "F_Saiyan", Name = "Guerrero del Cielo Roto", Desc = "Exclusivo del Imperio de Élite. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Saiyan", Icon = "⭐", Fx = "ki", Look = "Saiyan" },
	{ Id = "F_Shinobi", Name = "Susurro de las Hojas", Desc = "Exclusivo de la Alianza del Sigilo. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Shinobi", Icon = "🍃", Fx = "hojas", Look = "Hoja" },
	{ Id = "F_Pirate", Name = "Lobo de la Marea Negra", Desc = "Exclusivo de la Flota de Navegantes. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Pirate", Icon = "⚓", Fx = "olas", Look = "Marea" },
	{ Id = "F_Shinigami", Name = "Guardián del Velo Pálido", Desc = "Exclusivo de la Corte Espiritual. Llega al nivel 900.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 900, Faction = "Shinigami", Icon = "🦋", Fx = "niebla", Look = "Velo" },

	-- ESPECIAL
	-- VIP: se compran con Sellos Imperiales en la Tienda VIP del Mes (VipShopCatalog)
	{ Id = "V_Noble", Name = "Noble de la Corte", Desc = "Tienda VIP del Mes.", Rarity = "Epico", Cat = "VIP", Kind = "Grant", Icon = "🌸", Fx = "petalos", Look = "Sakura" },
	{ Id = "V_Luna", Name = "Señor de la Luna Nueva", Desc = "Tienda VIP del Mes.", Rarity = "Epico", Cat = "VIP", Kind = "Grant", Icon = "🌜", Fx = "estrellas", Look = "Luna" },
	{ Id = "V_Mecenas", Name = "Mecenas del Reino", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "💰", Fx = "oro", Look = "Realeza" },
	{ Id = "V_Alba", Name = "Heraldo del Amanecer Dorado", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "🌄", Fx = "aurora", Look = "Aurora" },
	{ Id = "V_Eclipse", Name = "Guardián del Eclipse", Desc = "Tienda VIP del Mes.", Rarity = "Legendario", Cat = "VIP", Kind = "Grant", Icon = "🌘", Fx = "eclipse", Look = "Eclipse" },
	{ Id = "V_Corona", Name = "Portador de la Corona de Cristal", Desc = "Tienda VIP del Mes.", Rarity = "Mitico", Cat = "VIP", Kind = "Grant", Icon = "💎", Fx = "cristal", Look = "Cristal" },
	{ Id = "Casa", Name = "Señor del Pabellón", Desc = "Posee tu Casa VIP.", Rarity = "Epico", Cat = "Especial", Kind = "Grant", Icon = "🏯", Fx = "aurora", Look = "Realeza" },

	-- COMBATE (más escalones, hasta un millón de bajas)
	{ Id = "Kill25000", Name = "Verdugo de Legiones", Desc = "Derrota 25.000 monstruos.", Rarity = "Epico", Cat = "Combate", Kind = "Kill", Value = 25000, Icon = "⚔️", Fx = "llamas", Look = "Ascua" },
	{ Id = "Kill50000", Name = "Cosechador de Almas", Desc = "Derrota 50.000 monstruos.", Rarity = "Legendario", Cat = "Combate", Kind = "Kill", Value = 50000, Icon = "💀", Fx = "niebla", Look = "Velo" },
	{ Id = "Kill100000", Name = "Calamidad Andante", Desc = "Derrota 100.000 monstruos.", Rarity = "Legendario", Cat = "Combate", Kind = "Kill", Value = 100000, Icon = "🌪", Fx = "llamas", Look = "Ascua" },
	{ Id = "Kill250000", Name = "Fin de las Especies", Desc = "Derrota 250.000 monstruos.", Rarity = "Mitico", Cat = "Combate", Kind = "Kill", Value = 250000, Icon = "🌑", Fx = "eclipse", Look = "Eclipse" },
	{ Id = "Kill1000000", Name = "Apocalipsis Viviente", Desc = "Derrota 1.000.000 de monstruos.", Rarity = "Mitico", Cat = "Combate", Kind = "Kill", Value = 1000000, Icon = "💥", Fx = "llamas", Look = "Dragon" },
	{ Id = "Metin500", Name = "Azote de las Piedras", Desc = "Destruye 500 piedras Metin.", Rarity = "Legendario", Cat = "Combate", Kind = "Metin", Value = 500, Icon = "💎", Fx = "cristal", Look = "Cristal" },
	{ Id = "Metin1000", Name = "Señor de los Sellos Rotos", Desc = "Destruye 1.000 piedras Metin.", Rarity = "Mitico", Cat = "Combate", Kind = "Metin", Value = 1000, Icon = "🔮", Fx = "estrellas", Look = "Cosmos" },
	{ Id = "Boss5", Name = "Rompecolosos", Desc = "Participa en la caída de 5 jefes mundiales.", Rarity = "Epico", Cat = "Combate", Kind = "Boss", Value = 5, Icon = "🦴", Fx = "simple", Look = "Coloso" },
	{ Id = "Boss25", Name = "Verdugo de Gigantes", Desc = "Participa en la caída de 25 jefes mundiales.", Rarity = "Legendario", Cat = "Combate", Kind = "Boss", Value = 25, Icon = "⚔️", Fx = "rayos", Look = "Coloso" },
	{ Id = "Boss100", Name = "Ocaso de los Titanes", Desc = "Participa en la caída de 100 jefes mundiales.", Rarity = "Mitico", Cat = "Combate", Kind = "Boss", Value = 100, Icon = "🌅", Fx = "aurora", Look = "Aurora" },

	-- TIEMPO
	{ Id = "Min3000", Name = "Alma Veterana", Desc = "Pasa 50 horas conectado.", Rarity = "Epico", Cat = "Progreso", Kind = "Min", Value = 3000, Icon = "⌛", Fx = "simple", Look = "Plata" },
	{ Id = "Min6000", Name = "Centinela Eterno", Desc = "Pasa 100 horas conectado.", Rarity = "Legendario", Cat = "Progreso", Kind = "Min", Value = 6000, Icon = "🕰", Fx = "oro", Look = "Muralla" },
	{ Id = "Min30000", Name = "Testigo de Eras", Desc = "Pasa 500 horas conectado.", Rarity = "Mitico", Cat = "Progreso", Kind = "Min", Value = 30000, Icon = "🌌", Fx = "estrellas", Look = "Luna" },

	-- SALÓN y FORJA (escalones altos)
	{ Id = "Dmg50m", Name = "Cataclismo Encarnado", Desc = "Haz 50.000.000 de daño en una prueba de 30 s.", Rarity = "Legendario", Cat = "Salón", Kind = "Dmg", Value = 50000000, Icon = "💥", Fx = "rayos", Look = "Tormenta" },
	{ Id = "Dmg200m", Name = "Más Allá del Límite", Desc = "Haz 200.000.000 de daño en una prueba de 30 s.", Rarity = "Mitico", Cat = "Salón", Kind = "Dmg", Value = 200000000, Icon = "🌌", Fx = "estrellas", Look = "Cosmos" },
	{ Id = "Forja3", Name = "Aprendiz del Yunque", Desc = "Forja 3 piezas +9.", Rarity = "Epico", Cat = "Forja", Kind = "Forja9", Value = 3, Icon = "🔨", Fx = "llamas", Look = "Forja" },
	{ Id = "Forja15", Name = "Titán de la Forja", Desc = "Forja 15 piezas +9.", Rarity = "Mitico", Cat = "Forja", Kind = "Forja9", Value = 15, Icon = "🌋", Fx = "llamas", Look = "Forja" },
	{ Id = "Forja25", Name = "Dios del Yunque", Desc = "Forja 25 piezas +9.", Rarity = "Mitico", Cat = "Forja", Kind = "Forja9", Value = 25, Icon = "🔥", Fx = "oro", Look = "Dragon" },

	-- MISIONES (se aceptan con el Mayordomo del Pabellón VIP)
	{ Id = "Mis5", Name = "Recadero Imperial", Desc = "Completa 5 misiones.", Rarity = "Comun", Cat = "Misiones", Kind = "Mission", Value = 5, Icon = "📜", Fx = "simple", Look = "Cobre" },
	{ Id = "Mis15", Name = "Mensajero de Confianza", Desc = "Completa 15 misiones.", Rarity = "Raro", Cat = "Misiones", Kind = "Mission", Value = 15, Icon = "📨", Fx = "simple", Look = "Acero" },
	{ Id = "Mis30", Name = "Voz del Pabellón", Desc = "Completa 30 misiones.", Rarity = "Raro", Cat = "Misiones", Kind = "Mission", Value = 30, Icon = "📣", Fx = "oro", Look = "Plata" },
	{ Id = "Mis60", Name = "Mano Derecha del Mayordomo", Desc = "Completa 60 misiones.", Rarity = "Epico", Cat = "Misiones", Kind = "Mission", Value = 60, Icon = "🤝", Fx = "oro", Look = "Honor" },
	{ Id = "Mis120", Name = "Cazador de Encargos", Desc = "Completa 120 misiones.", Rarity = "Epico", Cat = "Misiones", Kind = "Mission", Value = 120, Icon = "🎯", Fx = "simple", Look = "Muralla" },
	{ Id = "Mis250", Name = "Leyenda del Tablón", Desc = "Completa 250 misiones.", Rarity = "Legendario", Cat = "Misiones", Kind = "Mission", Value = 250, Icon = "🏅", Fx = "oro", Look = "Realeza" },
	{ Id = "Mis500", Name = "Incansable", Desc = "Completa 500 misiones.", Rarity = "Legendario", Cat = "Misiones", Kind = "Mission", Value = 500, Icon = "⚡", Fx = "aurora", Look = "Aurora" },
	{ Id = "Mis1000", Name = "Emperador de los Encargos", Desc = "Completa 1.000 misiones.", Rarity = "Mitico", Cat = "Misiones", Kind = "Mission", Value = 1000, Icon = "👑", Fx = "oro", Look = "Realeza" },

	-- HITOS DE NIVEL (hay 60)
	{ Id = "Hito1", Name = "Primer Escalón", Desc = "Reclama tu primer hito de nivel.", Rarity = "Comun", Cat = "Hitos", Kind = "Hito", Value = 1, Icon = "🌱", Fx = "simple", Look = "Cobre" },
	{ Id = "Hito10", Name = "Escalador de Cumbres", Desc = "Reclama 10 hitos de nivel.", Rarity = "Raro", Cat = "Hitos", Kind = "Hito", Value = 10, Icon = "⛰", Fx = "simple", Look = "Acero" },
	{ Id = "Hito25", Name = "Coleccionista de Gloria", Desc = "Reclama 25 hitos de nivel.", Rarity = "Epico", Cat = "Hitos", Kind = "Hito", Value = 25, Icon = "🏆", Fx = "oro", Look = "Honor" },
	{ Id = "Hito45", Name = "Cosechador de Hitos", Desc = "Reclama 45 hitos de nivel.", Rarity = "Legendario", Cat = "Hitos", Kind = "Hito", Value = 45, Icon = "🎖", Fx = "oro", Look = "Realeza" },
	{ Id = "Hito60", Name = "Corona Completa", Desc = "Reclama los 60 hitos de nivel.", Rarity = "Mitico", Cat = "Hitos", Kind = "Hito", Value = 60, Icon = "👑", Fx = "oro", Look = "Campeon" },

	-- FACCIÓN (tres escalones exclusivos por facción)
	{ Id = "F_Saiyan2", Name = "Príncipe del Ki Ardiente", Desc = "Exclusivo del Imperio de Élite. Llega al nivel 1500.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 1500, Faction = "Saiyan", Icon = "⭐", Fx = "ki", Look = "Saiyan" },
	{ Id = "F_Saiyan3", Name = "Guerrero Dorado Ascendido", Desc = "Exclusivo del Imperio de Élite. Llega al nivel 2250.", Rarity = "Legendario", Cat = "Facción", Kind = "Level", Value = 2250, Faction = "Saiyan", Icon = "⭐", Fx = "ki", Look = "Saiyan" },
	{ Id = "F_Saiyan4", Name = "Rey del Imperio de Élite", Desc = "Exclusivo del Imperio de Élite. Llega al nivel 3000.", Rarity = "Mitico", Cat = "Facción", Kind = "Level", Value = 3000, Faction = "Saiyan", Icon = "⭐", Fx = "ki", Look = "Saiyan" },
	{ Id = "F_Shinobi2", Name = "Sombra de la Aldea", Desc = "Exclusivo de la Alianza del Sigilo. Llega al nivel 1500.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 1500, Faction = "Shinobi", Icon = "🍃", Fx = "hojas", Look = "Hoja" },
	{ Id = "F_Shinobi3", Name = "Sabio de los Seis Vías", Desc = "Exclusivo de la Alianza del Sigilo. Llega al nivel 2250.", Rarity = "Legendario", Cat = "Facción", Kind = "Level", Value = 2250, Faction = "Shinobi", Icon = "🍃", Fx = "hojas", Look = "Hoja" },
	{ Id = "F_Shinobi4", Name = "Sombra Eterna", Desc = "Exclusivo de la Alianza del Sigilo. Llega al nivel 3000.", Rarity = "Mitico", Cat = "Facción", Kind = "Level", Value = 3000, Faction = "Shinobi", Icon = "🍃", Fx = "hojas", Look = "Hoja" },
	{ Id = "F_Pirate2", Name = "Capitán Temido", Desc = "Exclusivo de la Flota de Navegantes. Llega al nivel 1500.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 1500, Faction = "Pirate", Icon = "⚓", Fx = "olas", Look = "Marea" },
	{ Id = "F_Pirate3", Name = "Emperador de los Mares", Desc = "Exclusivo de la Flota de Navegantes. Llega al nivel 2250.", Rarity = "Legendario", Cat = "Facción", Kind = "Level", Value = 2250, Faction = "Pirate", Icon = "⚓", Fx = "olas", Look = "Marea" },
	{ Id = "F_Pirate4", Name = "Rey de los Mares", Desc = "Exclusivo de la Flota de Navegantes. Llega al nivel 3000.", Rarity = "Mitico", Cat = "Facción", Kind = "Level", Value = 3000, Faction = "Pirate", Icon = "⚓", Fx = "olas", Look = "Marea" },
	{ Id = "F_Shinigami2", Name = "Capitán de División", Desc = "Exclusivo de la Corte Espiritual. Llega al nivel 1500.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 1500, Faction = "Shinigami", Icon = "🦋", Fx = "niebla", Look = "Velo" },
	{ Id = "F_Shinigami3", Name = "Portador de la Liberación Final", Desc = "Exclusivo de la Corte Espiritual. Llega al nivel 2250.", Rarity = "Legendario", Cat = "Facción", Kind = "Level", Value = 2250, Faction = "Shinigami", Icon = "🦋", Fx = "niebla", Look = "Velo" },
	{ Id = "F_Shinigami4", Name = "Comandante de la Corte", Desc = "Exclusivo de la Corte Espiritual. Llega al nivel 3000.", Rarity = "Mitico", Cat = "Facción", Kind = "Level", Value = 3000, Faction = "Shinigami", Icon = "🦋", Fx = "niebla", Look = "Velo" },
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
