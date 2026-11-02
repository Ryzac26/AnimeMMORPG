--!strict
--[[
    AlchemyCatalog (ModuleScript) -> ReplicatedStorage.Modules.AlchemyCatalog
    ALQUIMISTA: recetas de pociones y rendimiento de "Desmontar equipo". Un solo lugar para balancear (lo leen servidor y cliente).
      RECETAS: cada poción cuesta recursos de recolección (Rec_1..4, se sacan de los nodos del mapa) + algo de material de franja + oro.
               Los grados altos NO se pagan con Robux: los puede fabricar cualquiera con los materiales.
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
}

AlchemyCatalog.MAX_QTY = 999
AlchemyCatalog.QTY_OPTIONS = { 1, 10, 50, 100 } -- más el botón "Máx"

-- Orden de la lista. Efecto (% de vida/energía) en ItemCatalog (Use).
AlchemyCatalog.Recipes = {
	{ Id = "Pocion_Vida", Kind = "Hp", Cost = { Rec_1 = 1 }, Gold = 10, Yield = 1 },
	{ Id = "Pocion_Vida_Mayor", Kind = "Hp", Cost = { Rec_2 = 2, Mat_Colmillo = 1 }, Gold = 40, Yield = 1 },
	{ Id = "Pocion_Vida_Suprema", Kind = "Hp", Cost = { Rec_3 = 2, Mat_Esencia = 2 }, Gold = 120, Yield = 1 },
	{ Id = "Pocion_Energia", Kind = "En", Cost = { Rec_1 = 1 }, Gold = 10, Yield = 1 },
	{ Id = "Pocion_Energia_Mayor", Kind = "En", Cost = { Rec_2 = 2, Mat_Colmillo = 1 }, Gold = 40, Yield = 1 },
	{ Id = "Pocion_Energia_Suprema", Kind = "En", Cost = { Rec_3 = 2, Mat_Esencia = 2 }, Gold = 120, Yield = 1 },
} :: { Recipe }

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
