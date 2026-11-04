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
	Pergamino_Proteccion = { Name = "Pergamino de Protección", Rarity = "Epico", Stack = 99, Desc = "Úsalo en el Herrero al intentar +7, +8 o +9: si la mejora falla, la pieza NO baja de nivel ni se rompe (el pergamino se gasta). Solo se consigue en la Tienda." },
	Mat_Escama = { Name = "Escama del Titán", Rarity = "Epico", Stack = 99, Desc = "Material de crafteo avanzado del jefe mundial." },
	-- Recursos de recolección (nodos del mapa). Sirven para la Ofrenda del altar y para cocinar pociones en el campamento.
	Rec_1 = { Name = "Hierba Espiritual", Rarity = "Comun", Stack = 99, Desc = "Se recolecta en la Franja 1. Sirve para cocinar pociones en el campamento y para la Ofrenda del altar." },
	Rec_2 = { Name = "Cristal de Zona", Rarity = "Raro", Stack = 99, Desc = "Se recolecta en la Franja 2. Sirve para cocinar pociones en el campamento y para la Ofrenda del altar." },
	Rec_3 = { Name = "Reliquia Antigua", Rarity = "Raro", Stack = 99, Desc = "Se recolecta en la Franja 3. Sirve para cocinar pociones en el campamento y para la Ofrenda del altar." },
	Rec_4 = { Name = "Corazón de Poder", Rarity = "Epico", Stack = 99, Desc = "Se recolecta en la Franja 4. Sirve para cocinar pociones en el campamento y para la Ofrenda del altar." },
	-- Llaves de cofre (una por franja). Caen de los monstruos de esa franja, con tope diario. Duran solo el día en que caen.
	-- Bound = true: no se pueden vender (ShopCatalog) ni intercambiar (cuando exista el intercambio, debe respetar Bound).
	Key_1 = { Name = "Llave de Cofre · Franja 1", Rarity = "Raro", Stack = 99, Bound = true, Desc = "Abre un cofre de la Franja 1. Caduca al terminar el día. No se vende ni se intercambia." },
	Key_2 = { Name = "Llave de Cofre · Franja 2", Rarity = "Raro", Stack = 99, Bound = true, Desc = "Abre un cofre de la Franja 2. Caduca al terminar el día. No se vende ni se intercambia." },
	Key_3 = { Name = "Llave de Cofre · Franja 3", Rarity = "Epico", Stack = 99, Bound = true, Desc = "Abre un cofre de la Franja 3. Caduca al terminar el día. No se vende ni se intercambia." },
	Key_4 = { Name = "Llave de Cofre · Franja 4", Rarity = "Epico", Stack = 99, Bound = true, Desc = "Abre un cofre de la Franja 4. Caduca al terminar el día. No se vende ni se intercambia." },
} :: { [string]: { [string]: any } }
LootTables.StripMaterial = { "Mat_Piel", "Mat_Colmillo", "Mat_Esencia", "Mat_Nucleo" } -- por franja 1..4
LootTables.StripResource = { "Rec_1", "Rec_2", "Rec_3", "Rec_4" } -- recursos de recolección por franja 1..4

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

-- Mob normal. El equipo mejora con la franja, pero Épico/Legendario siguen siendo raros (cada franja da más que la anterior).
-- Los mobs normales NUNCA sueltan Mítico. Para subir o bajar la dificultad cambia SOLO estas listas.
LootTables.Mob = {
	MinShare = 0.10, -- % mínimo del daño para tener botín (evita "tocar y llevarse")
	ItemChance = 0.30,
	ItemWeights = { Consumible = 55, Material = 45 },
	ConsumableCount = { 1, 3 },
	MaterialCount = { 1, 2 },
	FragmentShare = 0.30, -- de los materiales, qué parte es Fragmento de Armadura (el resto, material de la franja)
	GearChanceByStrip = { 0.012, 0.014, 0.016, 0.018 }, -- antes 0.02 fijo
	GearRarityByStrip = {
		[1] = { Comun = 86, Raro = 13.7, Epico = 0.3 },
		[2] = { Comun = 76, Raro = 22.5, Epico = 1.5 },
		[3] = { Comun = 64, Raro = 32, Epico = 3.9, Legendario = 0.1 },
		[4] = { Comun = 52, Raro = 41, Epico = 6.5, Legendario = 0.5 },
	},
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
		[1] = { Raro = 60, Epico = 39, Legendario = 1 },
		[2] = { Raro = 35, Epico = 62, Legendario = 3 },
		[3] = { Epico = 85, Legendario = 14.5, Mitico = 0.5 },
		[4] = { Epico = 75, Legendario = 23, Mitico = 2 },
	},
	PetChance = 0.015,
	PetRarity = { Raro = 62, Epico = 35, Legendario = 3 },
}

LootTables.WorldBoss = {
	GoldMult = 40,
	FactionPoints = 100,
	ScaleCount = { 1, 3 }, -- Escamas del Titán, garantizadas
	WinnerFraction = 0.25, MinWinners = 1, MaxWinners = 6,
	PrizeRarity = { Epico = 62, Legendario = 36, Mitico = 2 },
	PetChance = 0.02,
	PetRarity = { Epico = 62, Legendario = 36, Mitico = 2 },
}

-- Piedras Metin (por id de MetinCatalog)
LootTables.Metin = {
	MinShare = 0.05,
	GemChance = 0.45,
	ChestChance = 0.08, -- antes 0.17 -- "cofre": tirada extra de equipo de rareza alta (se entrega directo, sin objeto cofre)
	EmblemChance = 0.02, -- antes 0.04 -- Emblema exclusivo de TU facción
	PetChance = 0.01,
	Rarities = {
		Comun = { GoldMult = 3, FactionPoints = 5, GemCount = { 1, 1 }, ChestRarity = { Comun = 40, Raro = 55, Epico = 5 }, EmblemRarity = { Epico = 100 }, PetRarity = { Comun = 55, Raro = 40, Epico = 5 } },
		PocoComun = { GoldMult = 4, FactionPoints = 8, GemCount = { 1, 1 }, ChestRarity = { Raro = 80, Epico = 20 }, EmblemRarity = { Epico = 100 }, PetRarity = { Comun = 50, Raro = 42, Epico = 8 } },
		Raro = { GoldMult = 6, FactionPoints = 12, GemCount = { 1, 2 }, ChestRarity = { Raro = 62, Epico = 37, Legendario = 1 }, EmblemRarity = { Epico = 94, Legendario = 6 }, PetRarity = { Raro = 70, Epico = 28, Legendario = 2 } },
		Epico = { GoldMult = 9, FactionPoints = 20, GemCount = { 1, 3 }, ChestRarity = { Raro = 30, Epico = 66, Legendario = 4 }, EmblemRarity = { Epico = 88, Legendario = 12 }, PetRarity = { Raro = 55, Epico = 41, Legendario = 4 } },
		Legendario = { GoldMult = 14, FactionPoints = 35, GemCount = { 2, 3 }, ChestRarity = { Epico = 80, Legendario = 19, Mitico = 1 }, EmblemRarity = { Epico = 78, Legendario = 21, Mitico = 1 }, PetRarity = { Epico = 66, Legendario = 32, Mitico = 2 } },
	},
}


---------------------------------------------------------------------
-- PUNTOS DE INTERÉS DE LAS FRANJAS (PveZoneService)
-- Todo es por franja 1..4: cada franja da más y mejor que la anterior. Épico/Legendario/Mítico son difíciles de ver.
---------------------------------------------------------------------
-- Mini jefe (uno por franja). Vida = vida de mob de su nivel x HpMult. XP = XpKills kills de ese nivel.
LootTables.MiniBoss = {
	HpMult = { 3, 3.5, 4, 5 }, -- élite de franja: 8 / 10 / 12 / 15
	DmgMult = 1.2,
	Scale = 1.35,
	XpKills = 4,
	RespawnSeconds = 480,
	MinShare = 0.10,
	GoldMult = 5,
	FactionPoints = 4,
	StripCount = { 1, 3 },
	FragmentCount = { 1, 2 },
	GemChance = 0.30,
	GearChance = { 0.28, 0.30, 0.32, 0.35 },
	GearRarity = {
		[1] = { Comun = 40, Raro = 54, Epico = 6 },
		[2] = { Comun = 25, Raro = 62, Epico = 12.5, Legendario = 0.5 },
		[3] = { Raro = 70, Epico = 27, Legendario = 3 },
		[4] = { Raro = 55, Epico = 38, Legendario = 6.5, Mitico = 0.5 },
	},
	PetChance = 0.004,
	PetRarity = { Comun = 40, Raro = 50, Epico = 10 },
}

-- Cofre del mapa: se abre con una LLAVE de su franja (ver KeyDrop y Daily). Lo gana quien lo abre, sin sorteo.
LootTables.MapChest = {
	AnimSeconds = 3, -- tiempo que queda abierta la tapa (el cofre sigue disponible: lo limita la llave)
	GoldMult = 6,
	StripCount = { 2, 4 },
	GemChance = 0.35,
	GemCount = { 1, 2 },
	GearChance = { 0.55, 0.60, 0.65, 0.70 },
	GearRarity = {
		[1] = { Comun = 20, Raro = 66, Epico = 14 },
		[2] = { Raro = 62, Epico = 36, Legendario = 2 },
		[3] = { Raro = 45, Epico = 51, Legendario = 4 },
		[4] = { Raro = 30, Epico = 60, Legendario = 9.5, Mitico = 0.5 },
	},
	-- "Mejorado": poco común. El equipo sube UNA rareza y llega con mejora +1 a +3.
	UpgradedChance = { 0.04, 0.05, 0.06, 0.08 },
	UpgradedPlus = { 1, 3 },
}

-- Altar de Ofrenda: entregas recursos + material de la franja + oro y recibes una tirada de equipo mejor que la de un mob.
LootTables.Offering = {
	CooldownSeconds = 600, -- por jugador y altar
	ResourceCost = { 6, 8, 10, 12 }, -- Rec_<franja>
	MaterialCost = { 4, 5, 6, 8 }, -- Mat de la franja
	GoldCostMult = 3, -- oro = GoldFor(nivel, mult)
	GemCount = { 1, 2 },
	GearRarity = {
		[1] = { Comun = 25, Raro = 62, Epico = 13 },
		[2] = { Raro = 62, Epico = 36, Legendario = 2 },
		[3] = { Raro = 48, Epico = 48, Legendario = 4 },
		[4] = { Raro = 34, Epico = 57, Legendario = 8.5, Mitico = 0.5 },
	},
	JewelryBias = 0.25, -- las ofrendas dan joyas un poco más seguido
}

-- Altar de Desafío: 3 oleadas contra monstruos de la franja. Premio personal para todos los que ayudaron.
LootTables.Challenge = {
	CooldownSeconds = 480, -- del altar (cualquiera que lo active lo gasta)
	TimeLimit = 150,
	Radius = 70, -- quienes estén a esta distancia del altar cuando termina, reciben el premio
	WaveSizes = { 3, 4, 3 }, -- la última oleada incluye un campeón
	GoldMult = 7,
	FactionPoints = 6,
	StripCount = { 2, 4 },
	GemChance = 0.55,
	GearChance = { 0.70, 0.72, 0.75, 0.80 },
	GearRarity = {
		[1] = { Raro = 62, Epico = 36, Legendario = 2 },
		[2] = { Raro = 48, Epico = 48, Legendario = 4 },
		[3] = { Raro = 34, Epico = 58, Legendario = 7.5, Mitico = 0.5 },
		[4] = { Raro = 22, Epico = 62, Legendario = 14, Mitico = 2 },
	},
	PetChance = 0.01,
	PetRarity = { Raro = 55, Epico = 40, Legendario = 5 },
}

-- Nodos de recolección
LootTables.Gathering = {
	RespawnSeconds = 150,
	Count = { 1, 3 },
	BonusMatChance = 0.25, -- además, 1 material de la franja
	NodesPerStrip = 10,
}

-- (Cocinar: la olla del campamento abre la ventana del Alquimista; las recetas están en AlchemyCatalog)

-- LÍMITES DIARIOS por jugador y por franja (cada franja cuenta aparte). Se reinician a medianoche (ResetUtcOffsetHours: -3 = hora de Montevideo).
--   Keys      = llaves de cofre que PUEDEN CAER por día (no se acumulan: las que sobren caducan al reiniciar el día) = cofres que se pueden abrir por día
--   Challenge = desafíos del altar con premio por día
--   MiniBoss  = mini jefes con premio por día (al agotarlo no puedes ni pegarle)
LootTables.Daily = {
	ResetUtcOffsetHours = -3,
	Keys = { 3, 3, 3, 3 },
	Challenge = { 2, 2, 2, 2 },
	MiniBoss = { 3, 3, 3, 3 },
}

-- Probabilidad de que caiga una llave de la franja al matar (solo mientras queden llaves por caer ese día)
LootTables.KeyDrop = { Mob = 0.025, Mini = 0.35, Elite = 0.50 }

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
function LootTables.RollGear(faction: string, role: string, level: number, rarityWeights: { [string]: number }, rng: RNG, jewelryChance: number?, upgradeRarity: boolean?): string?
	local tier = GearCatalog.TierOfLevel(level)
	local rarity = LootTables.Pick(rarityWeights, rng)
	if upgradeRarity then
		local order = GearCatalog.Rarities
		local at = table.find(order, rarity) or 1
		rarity = order[math.min(#order, at + 1)]
	end
	local id: string
	if rng:NextNumber() < (jewelryChance or LootTables.JewelryChance) then
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
