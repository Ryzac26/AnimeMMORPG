--!strict
--[[
    ItemCatalog (ModuleScript) -> ReplicatedStorage.Modules.ItemCatalog
    Catálogo de OBJETOS (datos puros). Lo leen servidor (reglas) y cliente (mostrar nombre/color/ranura).
    Slot = ranura de equipo donde se pone ("Arma", "Casco"...). Sin Slot = consumible/material (solo ocupa mochila).
    Los de aquí son de PRUEBA (/item Id cantidad). El loot real se diseña después.
    Rarity: Comun, Raro, Epico, Legendario, Mitico
]]
export type Item = {
	Name: string,
	Slot: string?,
	Rarity: string,
	Stack: number?, -- máx. por casilla (nil = 1)
	Stats: { [string]: number }?,
	Desc: string?,
	Use: { HealPct: number?, EnergyPct: number?, Cooldown: number? }?, -- consumibles: curan % de vida / energía al usarse
	Style: string?, -- armas: Sword | Dagger | Bow | Staff | Gun | Axe | Fist (decide la animación y el modelo en la mano)
	-- Campos del equipo generado (GearCatalog) y mascotas (PetCatalog)
	Gear: { [string]: number }?, -- bonos en fracción (0.05 = 5%): Ataque, Defensa, Vida, Critico, Curacion
	ReqLevel: number?,
	Role: string?, -- solo ese rol puede equiparlo
	Faction: string?, -- solo esa facción puede equiparlo
	Set: string?,
	Tier: number?,
	Kind: string?, -- "Set" | "Jewel" | "Emblem" | "Pet"
	Pet: { Family: string, Effects: { [string]: number } }?,
}

local ItemCatalog = {}

ItemCatalog.RarityColor = {
	Comun = Color3.fromRGB(200, 200, 205),
	Raro = Color3.fromRGB(80, 160, 255),
	Epico = Color3.fromRGB(180, 90, 255),
	Legendario = Color3.fromRGB(255, 170, 40),
	Mitico = Color3.fromRGB(255, 70, 90),
}

-- Ranuras de equipo, en el orden en que las dibuja el panel (tecla C). Estilo Metin2 + extras futuros.
ItemCatalog.EquipSlots = {
	"Casco", "Armadura", "Arma", "Escudo", "Zapatos", "Brazalete", "Collar", "Pendientes", "Anillo", "Cinturon",
	"Capa", "Alas", "Montura", "Traje", "Accesorio1", "Accesorio2",
}

ItemCatalog.SlotDisplay = {
	Casco = "Casco", Armadura = "Armadura", Arma = "Arma", Escudo = "Escudo", Zapatos = "Zapatos", Brazalete = "Brazalete",
	Collar = "Collar", Pendientes = "Pendientes", Anillo = "Anillo", Cinturon = "Cinturón", Capa = "Capa", Alas = "Alas",
	Montura = "Montura", Traje = "Traje (skin)", Accesorio1 = "Emblema", Accesorio2 = "Mascota",
}

ItemCatalog.Items = {
	Espada_Hierro = { Name = "Espada de Hierro", Slot = "Arma", Rarity = "Comun", Stats = { Ataque = 12 }, Style = "Sword" },
	Katana_Noche = { Name = "Katana de la Noche", Slot = "Arma", Rarity = "Epico", Stats = { Ataque = 55 }, Style = "Sword" },
	Daga_Sombra = { Name = "Daga de Sombra", Slot = "Arma", Rarity = "Raro", Stats = { Ataque = 20 }, Style = "Dagger" },
	Arco_Cazador = { Name = "Arco del Cazador", Slot = "Arma", Rarity = "Raro", Stats = { Ataque = 22 }, Style = "Bow" },
	Baston_Mistico = { Name = "Bastón Místico", Slot = "Arma", Rarity = "Epico", Stats = { Ataque = 30 }, Style = "Staff" },
	Pistola_Pirata = { Name = "Pistola Pirata", Slot = "Arma", Rarity = "Raro", Stats = { Ataque = 24 }, Style = "Gun" },
	Hacha_Guerra = { Name = "Hacha de Guerra", Slot = "Arma", Rarity = "Epico", Stats = { Ataque = 40 }, Style = "Axe" },
	Casco_Cuero = { Name = "Casco de Cuero", Slot = "Casco", Rarity = "Comun", Stats = { Defensa = 6 } },
	Armadura_Batalla = { Name = "Armadura de Batalla", Slot = "Armadura", Rarity = "Raro", Stats = { Defensa = 22, Vida = 80 } },
	Escudo_Roble = { Name = "Escudo de Roble", Slot = "Escudo", Rarity = "Comun", Stats = { Defensa = 10 } },
	Botas_Viento = { Name = "Botas del Viento", Slot = "Zapatos", Rarity = "Raro", Stats = { Velocidad = 2 } },
	Brazalete_Jade = { Name = "Brazalete de Jade", Slot = "Brazalete", Rarity = "Raro", Stats = { Vida = 120 } },
	Collar_Fuego = { Name = "Collar de Fuego", Slot = "Collar", Rarity = "Epico", Stats = { Ataque = 20 } },
	Anillo_Ki = { Name = "Anillo de Ki", Slot = "Anillo", Rarity = "Legendario", Stats = { Energia = 40 } },
	Capa_Roja = { Name = "Capa Roja", Slot = "Capa", Rarity = "Raro", Stats = { Defensa = 8 } },
	Alas_Fenix = { Name = "Alas de Fénix", Slot = "Alas", Rarity = "Mitico", Stats = { Velocidad = 3, Ataque = 30 } },
	Nube_Voladora = { Name = "Nube Voladora", Slot = "Montura", Rarity = "Legendario", Stats = { Velocidad = 6 } },
	Pocion_Vida = { Name = "Poción de Vida", Rarity = "Comun", Stack = 20, Desc = "Restaura 30% de la vida.", Use = { HealPct = 0.30, Cooldown = 8 } },
	-- Poción de energía: en el HUD se muestra con el nombre del recurso de cada facción (Ki / Chakra / Haki / Reiatsu)
	Pocion_Energia = { Name = "Poción de Energía", Rarity = "Comun", Stack = 20, Desc = "Restaura 30% de la energía (Ki, Chakra, Haki o Reiatsu).", Use = { EnergyPct = 0.30, Cooldown = 8 } },
	Fragmento_Metin = { Name = "Fragmento de Metin", Rarity = "Epico", Stack = 99, Desc = "Material de mejora." },
} :: { [string]: Item }

-- Botín nuevo: equipo por sets de clase, joyas, emblemas de facción, mascotas y materiales (se generan por fórmulas)
do
	local GearCatalog = require(script.Parent.GearCatalog)
	local PetCatalog = require(script.Parent.PetCatalog)
	local LootTables = require(script.Parent.LootTables)
	local items = ItemCatalog.Items :: { [string]: any }
	for id, item in pairs(GearCatalog.Items) do
		items[id] = item
	end
	for id, item in pairs(PetCatalog.Items) do
		items[id] = item
	end
	for id, item in pairs(LootTables.Materials) do
		items[id] = item
	end
end

return ItemCatalog
