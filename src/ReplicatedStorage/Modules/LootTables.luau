--!strict
--[[
    LootTables (ModuleScript) -> ReplicatedStorage.Modules.LootTables
    TODOS los porcentajes y cantidades del botín en un solo lugar + funciones puras de sorteo (sin Roblox: se pueden probar).
    LootService lee esto; para rebalancear tocas SOLO los números de aquí.

    REPARTO "PAREJO" ENTRE FACCIONES
      - Las 4 facciones tienen los mismos jefes, niveles y franjas: las tablas dependen del nivel/franja, NUNCA de la facción del mob.
      - El botín es PERSONAL: cada jugador con suficiente participación tira por su cuenta.
      - El equipo que cae se RESUELVE al set de quien lo recibe (su rol y su arma de facción): jamás cae algo inútil.
      - Sorteo de jefe: todos los participantes tienen la misma base de boletos (+ un extra pequeño por daño) y una protección
        contra la mala racha ("pity": cada sorteo perdido suma boletos, al ganar se reinicia). Los ganadores se eligen por suerte.
    Los rangos { min, max } son enteros inclusivos.
]]
local GearCatalog = require(script.Parent.GearCatalog)
local PetCatalog = require(script.Parent.PetCatalog)

export type RNG = { NextNumber: (RNG) -> number, NextInteger: (RNG, number, number) -> number }

local LootTables = {}

---------------------------------------------------------------------
-- MATERIALES (apilables). Las pociones ya existen en ItemCatalog.
---------------------------------------------------------------------
LootTables.Materials = {
	Mat_Piel = { Name = "Piel de Bestia", Rarity = "Comun", Stack = 99, Desc = "Material de la Franja 1." },
	Mat_Colmillo = { Name = "Colmillo Afilado", Rarity = "Comun", Stack = 99, Desc = "Material de la Franja 2." },
	Mat_Esencia = { Name = "Esencia Oscura", Rarity = "Raro", Stack = 99, Desc = "Material de la Franja 3." },
	Mat_Nucleo = { Name = "Núcleo de Poder", Rarity = "Raro", Stack = 99, Desc = "Material de la Franja 4." },
	Mat_FragArmadura = { Name = "Fragmento de Armadura", Rarity = "Comun", Stack = 99, Desc = "Material de mejora de armaduras." },
	Mat_Gema = { Name = "Gema de Mejora", Rarity = "Raro", Stack = 99, Desc = "Sirve para mejorar el equipo (+1 a +9)." },
	Mat_Escama = { Name = "Escama del Titán", Rarity = "Epico", Stack = 99, Desc = "Material de crafteo avanzado del jefe mundial." },
} :: { [string]: { [string]: any } }
LootTables.StripMaterial = { "Mat_Piel", "Mat_Colmillo", "Mat_Esencia", "Mat_Nucleo" } -- por franja 1..4

---------------------------------------------------------------------
-- NÚMEROS
---------------------------------------------------------------------
LootTables.GoldBase = 8 -- oro de un monstruo de nivel 1
LootTables.GoldGrowth = 1.045 -- por nivel (nv.50 ≈ 69, nv.100 ≈ 628)
LootTables.GoldJitter = 0.20 -- ±20%

-- Boletos del sorteo de jefe
LootTables.Lottery = { BaseTickets = 1, ShareTickets = 4, PityStep = 0.5, PityMax = 6 }

-- Equipo: ranura de la pieza (80% set de clase) y reparto entre joyas (20%)
LootTables.GearSlotWeights = { Arma = 30, Armadura = 25, Casco = 25, Zapatos = 20 }
LootTables.JewelryChance = 0.20

LootTables.Mob = {
	MinShare = 0.10, -- % mínimo del daño para tener botín (evita "tocar y llevarse")
	ItemChance = 0.30,
	ItemWeights = { Consumible = 55, Material = 45 },
	ConsumableCount = { 1, 3 },
	MaterialCount = { 1, 2 },
	FragmentShare = 0.30, -- de los materiales, qué parte es Fragmento de Armadura (el resto, material de la franja)
	GearChance = 0.02,
	GearRarity = { Comun = 60, Raro = 32, Epico = 8 },
	PetChance = 0.0008,
	PetRarity = { Comun = 85, Raro = 15 },
}

-- Jefes de franja (los 16 élites del catálogo: 4 por facción, niveles 25/50/75/100)
LootTables.EliteBoss = {
	GoldMult = 12,
	FactionPoints = 25,
	StripCount = { 2, 4 }, -- material de la franja, garantizado
	FragmentCount = { 2, 4 }, -- Fragmentos de Armadura, garantizados
	WinnerFraction = 0.20, MinWinners = 1, MaxWinners = 4,
	PrizeRarity = {
		[1] = { Epico = 85, Legendario = 15 },
		[2] = { Epico = 85, Legendario = 15 },
		[3] = { Epico = 70, Legendario = 30 },
		[4] = { Epico = 70, Legendario = 30 },
	},
	PetChance = 0.015,
	PetRarity = { Raro = 55, Epico = 40, Legendario = 5 },
}

LootTables.WorldBoss = {
	GoldMult = 40,
	FactionPoints = 100,
	ScaleCount = { 1, 3 }, -- Escamas del Titán, garantizadas
	WinnerFraction = 0.25, MinWinners = 1, MaxWinners = 6,
	PrizeRarity = { Epico = 45, Legendario = 55 },
	PetChance = 0.02,
	PetRarity = { Epico = 55, Legendario = 40, Mitico = 5 },
}

-- Piedras Metin (por id de MetinCatalog)
LootTables.Metin = {
	MinShare = 0.05,
	GemChance = 0.45,
	ChestChance = 0.17, -- "cofre": tirada extra de equipo de rareza alta (se entrega directo, sin objeto cofre)
	EmblemChance = 0.04, -- Emblema exclusivo de TU facción
	PetChance = 0.01,
	Rarities = {
		Comun = { GoldMult = 3, FactionPoints = 5, GemCount = { 1, 1 }, ChestRarity = { Raro = 70, Epico = 30 }, EmblemRarity = { Epico = 100 }, PetRarity = { Comun = 40, Raro = 40, Epico = 18, Legendario = 2 } },
		PocoComun = { GoldMult = 4, FactionPoints = 8, GemCount = { 1, 1 }, ChestRarity = { Raro = 60, Epico = 40 }, EmblemRarity = { Epico = 100 }, PetRarity = { Comun = 40, Raro = 40, Epico = 18, Legendario = 2 } },
		Raro = { GoldMult = 6, FactionPoints = 12, GemCount = { 1, 2 }, ChestRarity = { Raro = 45, Epico = 50, Legendario = 5 }, EmblemRarity = { Epico = 85, Legendario = 15 }, PetRarity = { Raro = 55, Epico = 40, Legendario = 5 } },
		Epico = { GoldMult = 9, FactionPoints = 20, GemCount = { 1, 3 }, ChestRarity = { Epico = 80, Legendario = 20 }, EmblemRarity = { Epico = 70, Legendario = 30 }, PetRarity = { Raro = 40, Epico = 50, Legendario = 10 } },
		Legendario = { GoldMult = 14, FactionPoints = 35, GemCount = { 2, 3 }, ChestRarity = { Epico = 60, Legendario = 40 }, EmblemRarity = { Epico = 50, Legendario = 50 }, PetRarity = { Epico = 55, Legendario = 40, Mitico = 5 } },
	},
}

---------------------------------------------------------------------
-- FUNCIONES PURAS
---------------------------------------------------------------------
-- Elige una clave según pesos (claves en orden alfabético: resultado reproducible con la misma semilla)
function LootTables.Pick(weights: { [string]: number }, rng: RNG): string
	local keys: { string } = {}
	local total = 0
	for key, w in pairs(weights) do
		if w > 0 then
			table.insert(keys, key)
			total += w
		end
	end
	table.sort(keys)
	local roll = rng:NextNumber() * total
	for _, key in ipairs(keys) do
		roll -= weights[key]
		if roll < 0 then
			return key
		end
	end
	return keys[#keys]
end

function LootTables.Count(range: { number }, rng: RNG): number
	return rng:NextInteger(range[1], range[2])
end

function LootTables.GoldFor(level: number, mult: number, rng: RNG): number
	local base = LootTables.GoldBase * LootTables.GoldGrowth ^ (math.max(1, level) - 1)
	local jitter = 1 + (rng:NextNumber() * 2 - 1) * LootTables.GoldJitter
	return math.max(1, math.floor(base * mult * jitter))
end

function LootTables.WinnerCount(participants: number, fraction: number, minWinners: number, maxWinners: number): number
	if participants <= 0 then
		return 0
	end
	return math.min(participants, math.clamp(math.ceil(participants * fraction), minWinners, maxWinners))
end

-- Sorteo sin reemplazo con boletos: devuelve las claves ganadoras
function LootTables.Draw(entries: { { Key: any, Tickets: number } }, winners: number, rng: RNG): { any }
	local pool: { { Key: any, Tickets: number } } = {}
	for _, e in ipairs(entries) do
		if e.Tickets > 0 then
			table.insert(pool, e)
		end
	end
	local result: { any } = {}
	for _ = 1, math.min(winners, #pool) do
		local total = 0
		for _, e in ipairs(pool) do
			total += e.Tickets
		end
		local roll = rng:NextNumber() * total
		local picked = #pool
		for i, e in ipairs(pool) do
			roll -= e.Tickets
			if roll < 0 then
				picked = i
				break
			end
		end
		table.insert(result, pool[picked].Key)
		table.remove(pool, picked)
	end
	return result
end

-- Boletos de un participante en el sorteo de jefe
function LootTables.Tickets(share: number, pity: number): number
	local L = LootTables.Lottery
	return L.BaseTickets + L.ShareTickets * math.clamp(share, 0, 1) + math.clamp(pity, 0, L.PityMax)
end

-- Equipo que cae, YA resuelto al personaje que lo recibe. Devuelve el id del objeto.
function LootTables.RollGear(faction: string, role: string, level: number, rarityWeights: { [string]: number }, rng: RNG): string?
	local tier = GearCatalog.TierOfLevel(level)
	local rarity = LootTables.Pick(rarityWeights, rng)
	local id: string
	if rng:NextNumber() < LootTables.JewelryChance then
		local slots = { "Anillo", "Brazalete", "Collar" }
		local slot = slots[rng:NextInteger(1, #slots)]
		local focus = LootTables.Pick(GearCatalog.RoleWeights[role], rng)
		id = GearCatalog.JewelId(slot, focus, tier, rarity)
	else
		local slot = LootTables.Pick(LootTables.GearSlotWeights, rng)
		local style = if slot == "Arma" then GearCatalog.WeaponStyle[faction][role] else nil
		id = GearCatalog.SetPieceId(role, slot, style, tier, rarity)
	end
	if GearCatalog.Items[id] then
		return id
	end
	return nil
end

function LootTables.RollEmblem(faction: string, level: number, rarityWeights: { [string]: number }, rng: RNG): string?
	local id = GearCatalog.EmblemId(faction, GearCatalog.TierOfLevel(level), LootTables.Pick(rarityWeights, rng))
	if GearCatalog.Items[id] then
		return id
	end
	return nil
end

function LootTables.RollPet(rarityWeights: { [string]: number }, rng: RNG): string?
	local family = PetCatalog.FamilyOrder[rng:NextInteger(1, #PetCatalog.FamilyOrder)]
	local id = PetCatalog.Id(family, LootTables.Pick(rarityWeights, rng))
	if PetCatalog.Items[id] then
		return id
	end
	return nil
end

return LootTables
