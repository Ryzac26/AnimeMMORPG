--!strict
--[[
    AlchemyCatalog (ModuleScript) -> ReplicatedStorage.Modules.AlchemyCatalog
    ALQUIMISTA: recetas de pociones y rendimiento de "Desmontar equipo". Un solo lugar para balancear (lo leen servidor y cliente).
      RECETAS: cada poción cuesta recursos de recolección (Rec_1..4, se sacan de los nodos del mapa) + algo de material de franja + oro.
               Los grados Mayor y Suprema (Premium) necesitan el pase "Cinturón de Pociones" para fabricarlos y usarlos en el auto-farm; las normales son para todos.
               Los materiales NO dependen de los Metin (el más bajo es nivel 55): salen de nodos y monstruos de cada franja.
      DESMONTAR: equipo de la mochila (sin candado) -> materiales de su franja + fragmentos; Épico o mejor puede dar una Gema.
]]
local AlchemyCatalog = {}

export type Recipe = {
	Id: string, -- id del objeto que se fabrica (ItemCatalog)
	Kind: string, -- "Hp" | "En" (solo para ordenar/mostrar)
	Cost: { [string]: number }, -- material -> cantidad por poción
	Gold: number, -- oro por poción
	Yield: number, -- pociones por fabricación
	Premium: boolean?, -- true = solo con el pase "Cinturón de Pociones" (fabricar y usar en el auto-farm)
}

-- POCIONES EN EL AUTO-FARM: sin el pase "Cinturón de Pociones" el auto-farm solo usa las pociones BASE (las de siempre).
-- Con el pase puede usar Mayor y Suprema, elegir el grado a mano o usar siempre la mejor disponible.
-- Si algún día quieres que todos las usen: pon FREE_HIGH_GRADES = true (un solo cambio).
AlchemyCatalog.BASE_POTIONS = { Pocion_Vida = true, Pocion_Energia = true } :: { [string]: boolean }
AlchemyCatalog.FREE_HIGH_GRADES = false
-- ¿Puede este jugador fabricar esta receta? (las Premium piden el pase)
function AlchemyCatalog.CanCraft(recipe: Recipe, hasBelt: boolean): boolean
	return recipe.Premium ~= true or hasBelt or AlchemyCatalog.FREE_HIGH_GRADES
end
function AlchemyCatalog.PotionAllowed(id: string, hasBelt: boolean): boolean
	if hasBelt or AlchemyCatalog.FREE_HIGH_GRADES or AlchemyCatalog.BASE_POTIONS[id] then
		return true
	end
	return AlchemyCatalog.ById[id] == nil -- objetos fuera del Alquimista (futuros) no se restringen
end

AlchemyCatalog.MAX_QTY = 999
AlchemyCatalog.QTY_OPTIONS = { 1, 10, 50, 100 } -- más el botón "Máx"

-- Orden de la lista. Efecto (% de vida/energía) en ItemCatalog (Use).
AlchemyCatalog.Recipes = {
	{ Id = "Pocion_Vida", Kind = "Hp", Cost = { Rec_1 = 1 }, Gold = 10, Yield = 1 },
	{ Id = "Pocion_Vida_Mayor", Premium = true, Kind = "Hp", Cost = { Rec_2 = 2, Mat_Colmillo = 1 }, Gold = 40, Yield = 1 },
	{ Id = "Pocion_Vida_Suprema", Premium = true, Kind = "Hp", Cost = { Rec_3 = 2, Mat_Esencia = 2 }, Gold = 120, Yield = 1 },
	{ Id = "Pocion_Energia", Kind = "En", Cost = { Rec_1 = 1 }, Gold = 10, Yield = 1 },
	{ Id = "Pocion_Energia_Mayor", Premium = true, Kind = "En", Cost = { Rec_2 = 2, Mat_Colmillo = 1 }, Gold = 40, Yield = 1 },
	{ Id = "Pocion_Energia_Suprema", Premium = true, Kind = "En", Cost = { Rec_3 = 2, Mat_Esencia = 2 }, Gold = 120, Yield = 1 },
	-- ELIXIRES (pestaña "Elixires"): efecto temporal, para todos. Materiales de las franjas 1-3 (se consiguen antes del nivel 55).
	{ Id = "Elixir_Oro", Kind = "Elixir", Cost = { Rec_2 = 3, Mat_Piel = 3 }, Gold = 150, Yield = 1 },
	{ Id = "Elixir_Suerte", Kind = "Elixir", Cost = { Rec_2 = 3, Mat_Colmillo = 3 }, Gold = 200, Yield = 1 },
	{ Id = "Elixir_Poder", Kind = "Elixir", Cost = { Rec_3 = 3, Mat_Colmillo = 3 }, Gold = 300, Yield = 1 },
	{ Id = "Elixir_Vigor", Kind = "Elixir", Cost = { Rec_3 = 3, Mat_Esencia = 3 }, Gold = 300, Yield = 1 },
	{ Id = "Elixir_Regen", Kind = "Elixir", Cost = { Rec_1 = 6, Rec_2 = 2, Mat_Piel = 2 }, Gold = 120, Yield = 1 },
} :: { Recipe }

-- ELIXIRES: duran ELIXIR_SECONDS (solo corre mientras estás conectado). Solo UNO activo a la vez: beber otro reemplaza al actual.
-- Effect = estadísticas de GearService (fracciones). No dan experiencia (eso es de la Tienda).
AlchemyCatalog.ELIXIR_SECONDS = 1800
AlchemyCatalog.Elixirs = {
	Elixir_Oro = { Name = "Elixir de Oro", Short = "+20% de oro", Effect = { Oro = 0.20 } },
	Elixir_Suerte = { Name = "Elixir de Suerte", Short = "+15% de suerte (más botín raro)", Effect = { Suerte = 0.15 } },
	Elixir_Poder = { Name = "Elixir de Poder", Short = "+10% de daño", Effect = { Ataque = 0.10 } },
	Elixir_Vigor = { Name = "Elixir de Vigor", Short = "+10% de vida máxima", Effect = { Vida = 0.10 } },
	Elixir_Regen = { Name = "Elixir de Regeneración", Short = "Recuperas 1,5% de vida por segundo fuera de combate", Effect = { Regen = 0.015 } },
} :: { [string]: { Name: string, Short: string, Effect: { [string]: number } } }

AlchemyCatalog.ById = {} :: { [string]: Recipe }
for _, r in ipairs(AlchemyCatalog.Recipes) do
	AlchemyCatalog.ById[r.Id] = r
end

-- Cuántas veces se puede fabricar con lo que tienes. have(id) -> cantidad en mochila. Devuelve 0..MAX_QTY (o más limitado por el tope de pila).
function AlchemyCatalog.MaxCraft(recipe: Recipe, have: (string) -> number, gold: number): number
	local n = AlchemyCatalog.MAX_QTY
	for mat, need in pairs(recipe.Cost) do
		n = math.min(n, math.floor(have(mat) / need))
	end
	if recipe.Gold > 0 then
		n = math.min(n, math.floor(gold / recipe.Gold))
	end
	return math.max(0, n)
end

---------------------------------------------------------------------
-- DESMONTAR
---------------------------------------------------------------------
-- Por rareza: materiales de la franja (min,max), fragmentos de armadura (fijos) y probabilidad de Gema de Mejora.
AlchemyCatalog.Dismantle = {
	Comun = { Mat = { 1, 2 }, Frag = 0, Gem = 0 },
	Raro = { Mat = { 2, 3 }, Frag = 1, Gem = 0 },
	Epico = { Mat = { 3, 4 }, Frag = 2, Gem = 0.10 },
	Legendario = { Mat = { 4, 6 }, Frag = 3, Gem = 0.25 },
	Mitico = { Mat = { 6, 8 }, Frag = 4, Gem = 0.40 },
} :: { [string]: { Mat: { number }, Frag: number, Gem: number } }
AlchemyCatalog.StripMaterial = { "Mat_Piel", "Mat_Colmillo", "Mat_Esencia", "Mat_Nucleo" } -- = LootTables.StripMaterial
AlchemyCatalog.PlusFragEvery = 2 -- cada 2 niveles de mejora (+2, +4...) suman 1 fragmento más

-- Rendimiento de una pieza: nivel requerido, rareza, mejora. Devuelve { MatId, MatMin, MatMax, Frag, GemChance }.
function AlchemyCatalog.DismantleYield(reqLevel: number, rarity: string, plus: number): (string, number, number, number, number)
	local d = AlchemyCatalog.Dismantle[rarity] or AlchemyCatalog.Dismantle.Comun
	local strip = math.clamp(math.ceil(math.max(reqLevel, 1) / 25), 1, 4)
	local frag = d.Frag + math.floor(math.max(plus, 0) / AlchemyCatalog.PlusFragEvery)
	return AlchemyCatalog.StripMaterial[strip], d.Mat[1], d.Mat[2], frag, d.Gem
end

return AlchemyCatalog
