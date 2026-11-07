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
]]
local TitleCatalog = {}

export type Title = {
	Id: string, Name: string, Desc: string, Rarity: string, Cat: string, Kind: string, Value: number?, Faction: string?, Icon: string?,
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

TitleCatalog.Categories = { "Progreso", "Combate", "Forja", "Salón", "Facción", "Especial" }

TitleCatalog.List = {
	-- PROGRESO (nivel)
	{ Id = "Lv10", Name = "Estrella Naciente", Desc = "Llega al nivel 10.", Rarity = "Comun", Cat = "Progreso", Kind = "Level", Value = 10, Icon = "✦" },
	{ Id = "Lv25", Name = "Vanguardia del Alba", Desc = "Llega al nivel 25.", Rarity = "Raro", Cat = "Progreso", Kind = "Level", Value = 25, Icon = "☀" },
	{ Id = "Lv50", Name = "Filo de Medianoche", Desc = "Llega al nivel 50.", Rarity = "Epico", Cat = "Progreso", Kind = "Level", Value = 50, Icon = "☾" },
	{ Id = "Lv75", Name = "Tormenta Viviente", Desc = "Llega al nivel 75.", Rarity = "Legendario", Cat = "Progreso", Kind = "Level", Value = 75, Icon = "⚡" },
	{ Id = "Lv100", Name = "Leyenda Inmortal", Desc = "Llega al nivel máximo (100).", Rarity = "Mitico", Cat = "Progreso", Kind = "Level", Value = 100, Icon = "♛" },
	{ Id = "Min600", Name = "Compañero Eterno", Desc = "Pasa 10 horas conectado.", Rarity = "Raro", Cat = "Progreso", Kind = "Min", Value = 600, Icon = "⌛" },

	-- COMBATE
	{ Id = "Kill100", Name = "Cazador Incansable", Desc = "Derrota 100 monstruos.", Rarity = "Comun", Cat = "Combate", Kind = "Kill", Value = 100, Icon = "⚔" },
	{ Id = "Kill1000", Name = "Segador de Bestias", Desc = "Derrota 1.000 monstruos.", Rarity = "Raro", Cat = "Combate", Kind = "Kill", Value = 1000, Icon = "☠" },
	{ Id = "Kill10000", Name = "Azote del Mapa", Desc = "Derrota 10.000 monstruos.", Rarity = "Epico", Cat = "Combate", Kind = "Kill", Value = 10000, Icon = "🔥" },
	{ Id = "Metin10", Name = "Rompepiedras", Desc = "Destruye 10 piedras Metin.", Rarity = "Comun", Cat = "Combate", Kind = "Metin", Value = 10, Icon = "◆" },
	{ Id = "Metin100", Name = "Demoledor de Sellos", Desc = "Destruye 100 piedras Metin.", Rarity = "Epico", Cat = "Combate", Kind = "Metin", Value = 100, Icon = "◈" },
	{ Id = "Boss1", Name = "Cazador de Titanes", Desc = "Participa en la caída de un jefe mundial.", Rarity = "Raro", Cat = "Combate", Kind = "Boss", Value = 1, Icon = "🐉" },
	{ Id = "Boss10", Name = "Terror de los Titanes", Desc = "Participa en la caída de 10 jefes mundiales.", Rarity = "Legendario", Cat = "Combate", Kind = "Boss", Value = 10, Icon = "🐲" },

	-- FORJA
	{ Id = "Forja9", Name = "Maestro Forjador", Desc = "Forja una pieza +9.", Rarity = "Legendario", Cat = "Forja", Kind = "Forja9", Value = 1, Icon = "🔨" },
	{ Id = "Forja9x5", Name = "Yunque Eterno", Desc = "Forja 5 piezas +9.", Rarity = "Mitico", Cat = "Forja", Kind = "Forja9", Value = 5, Icon = "⚒" },

	-- SALÓN DE HONOR (maniquíes y ranking)
	{ Id = "Dmg10k", Name = "Puños de Hierro", Desc = "Haz 10.000 de daño en una prueba de 30 s.", Rarity = "Comun", Cat = "Salón", Kind = "Dmg", Value = 10000, Icon = "✊" },
	{ Id = "Dmg100k", Name = "Golpe Devastador", Desc = "Haz 100.000 de daño en una prueba de 30 s.", Rarity = "Raro", Cat = "Salón", Kind = "Dmg", Value = 100000, Icon = "💥" },
	{ Id = "Dmg1m", Name = "Fuerza Imparable", Desc = "Haz 1.000.000 de daño en una prueba de 30 s.", Rarity = "Epico", Cat = "Salón", Kind = "Dmg", Value = 1000000, Icon = "🌋" },
	{ Id = "Dmg10m", Name = "Destructor de Mundos", Desc = "Haz 10.000.000 de daño en una prueba de 30 s.", Rarity = "Legendario", Cat = "Salón", Kind = "Dmg", Value = 10000000, Icon = "☄" },
	{ Id = "Podio", Name = "Elegido del Podio", Desc = "Llega al podio de daño de tu facción (top 3).", Rarity = "Legendario", Cat = "Salón", Kind = "Grant", Icon = "🏆" },
	{ Id = "Campeon", Name = "Campeón del Salón", Desc = "Sé el nº 1 del ranking de daño de tu facción.", Rarity = "Mitico", Cat = "Salón", Kind = "Grant", Icon = "👑" },

	-- FACCIÓN (uno exclusivo por facción, nivel 30)
	{ Id = "F_Saiyan", Name = "Guerrero del Cielo Roto", Desc = "Exclusivo del Imperio Saiyan. Llega al nivel 30.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 30, Faction = "Saiyan", Icon = "⭐" },
	{ Id = "F_Shinobi", Name = "Susurro de las Hojas", Desc = "Exclusivo de la Alianza Shinobi. Llega al nivel 30.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 30, Faction = "Shinobi", Icon = "🍃" },
	{ Id = "F_Pirate", Name = "Lobo de la Marea Negra", Desc = "Exclusivo de la Flota Pirata. Llega al nivel 30.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 30, Faction = "Pirate", Icon = "☠" },
	{ Id = "F_Shinigami", Name = "Guardián del Velo Pálido", Desc = "Exclusivo de la Corte Shinigami. Llega al nivel 30.", Rarity = "Epico", Cat = "Facción", Kind = "Level", Value = 30, Faction = "Shinigami", Icon = "⚔" },

	-- ESPECIAL
	{ Id = "Casa", Name = "Señor del Pabellón", Desc = "Posee tu Casa VIP.", Rarity = "Epico", Cat = "Especial", Kind = "Grant", Icon = "🏯" },
} :: { Title }

TitleCatalog.ById = {} :: { [string]: Title }
for _, t in ipairs(TitleCatalog.List) do
	TitleCatalog.ById[t.Id] = t
end

return TitleCatalog
