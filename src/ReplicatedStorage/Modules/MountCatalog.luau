--!strict
--[[
    MountCatalog (ModuleScript) -> ReplicatedStorage.Modules.MountCatalog
    MONTURAS: 12 especies x 5 rarezas = 60. Datos puros (servidor y cliente los leen). Un solo lugar para rebalancear.

    HUEVOS
      - 1 HUEVO AL DÍA en total (DailyEggs): se toma de un NIDO de la franja o se obtiene al matar un MINI JEFE (lo que pase primero).
        Los huevos de la Tienda (más adelante) NO cuentan en ese límite.
      - El huevo tiene el nivel de su franja (1..4): Común, Raro, Épico, Legendario. Cuanto más alto, más tarda en incubar y mejores probabilidades.
      - La rareza de la montura se revela al abrir el huevo.
    INCUBADORA (ciudad): una a la vez. El tiempo corre aunque estés desconectado. Se puede acelerar con Robux (Accelerate).
    GARANTÍAS (pity), cuentan huevos abiertos: Raro o mejor cada 10 · Épico o mejor cada 30 · Legendario cada 60. Mítico: sin garantía.
    NIVEL de montura (1..5): una montura repetida sube de nivel (+1 punto de velocidad y +15% a sus pasivas por nivel). En el nivel máximo da oro.
    PASIVAS: Vigor (cura vida), Zancada (energía) y Saqueo (oro extra al matar), solo mientras vas montado. Legendaria y Mítica suman una segunda pasiva.
    Las 4 especies FLOTANTES solo se ven flotando: no suben ni vuelan.
]]
local MountCatalog = {}

MountCatalog.Rarities = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
MountCatalog.RarityIndex = { Comun = 1, Raro = 2, Epico = 3, Legendario = 4, Mitico = 5 } :: { [string]: number }
MountCatalog.RarityName = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" } :: { [string]: string }
MountCatalog.RarityColor = {
	Comun = Color3.fromRGB(200, 200, 205),
	Raro = Color3.fromRGB(80, 160, 255),
	Epico = Color3.fromRGB(180, 90, 255),
	Legendario = Color3.fromRGB(255, 170, 40),
	Mitico = Color3.fromRGB(255, 70, 110),
} :: { [string]: Color3 }

-- Velocidad extra (en %) por rareza y por nivel de montura por encima del 1
MountCatalog.Speed = { 8, 14, 20, 28, 36 }
MountCatalog.LevelSpeed = 1
MountCatalog.MaxLevel = 5
MountCatalog.LevelPassive = 0.15
-- Oro que da una montura repetida cuando ya está al nivel máximo (por rareza)
MountCatalog.DuplicateGold = { 300, 900, 3000, 10000, 40000 }
-- Cuánto se levanta el personaje sobre el suelo al montar (studs)
MountCatalog.Lift = 2.6

---------------------------------------------------------------------
-- Huevos
---------------------------------------------------------------------
MountCatalog.DailyEggs = 1
MountCatalog.MaxEggsBag = 20
export type Egg = { Name: string, Rarity: string, Hours: number, Odds: { number } }
-- Odds: Común, Raro, Épico, Legendario, Mítico (suman 100). Hours: horas de incubación.
MountCatalog.Eggs = {
	{ Name = "Huevo Común", Rarity = "Comun", Hours = 4, Odds = { 70, 25, 5, 0, 0 } },
	{ Name = "Huevo Raro", Rarity = "Raro", Hours = 8, Odds = { 30, 50, 17, 3, 0 } },
	{ Name = "Huevo Épico", Rarity = "Epico", Hours = 16, Odds = { 20, 40, 30, 10, 0 } },
	{ Name = "Huevo Legendario", Rarity = "Legendario", Hours = 24, Odds = { 0, 28, 48, 23.6, 0.4 } },
} :: { Egg }

-- Garantías: cada N huevos abiertos sin conseguir esa rareza (o mejor), el siguiente la trae
MountCatalog.Pity = { Raro = 10, Epico = 30, Legendario = 60 } :: { [string]: number }

-- Acelerar la incubación con Robux. ProductId = 0: aún sin producto (en Studio se acelera gratis para probar).
MountCatalog.Accelerate = { ProductId = 0, PriceText = "[PRECIO R$]" }

function MountCatalog.IncubationSeconds(tier: number): number
	local egg = MountCatalog.Eggs[math.clamp(tier, 1, #MountCatalog.Eggs)]
	return math.floor(egg.Hours * 3600)
end

---------------------------------------------------------------------
-- Nidos
---------------------------------------------------------------------
MountCatalog.Nest = {
	PerStrip = { 1, 2, 2, 3 }, -- nidos por franja
	Guards = { 2, 3, 3, 4 }, -- guardianes de cada nido
	GuardRespawn = 150, -- segundos hasta que reaparece un guardián caído
	ClearRadius = 70, -- no se puede tomar el huevo con enemigos vivos a esta distancia
	GuardRadius = 22, -- los guardianes nacen alrededor del nido
	ClaimDistance = 16,
}

---------------------------------------------------------------------
-- Pasivas (valores por rareza: Común..Mítico)
---------------------------------------------------------------------
export type Passive = { Name: string, Desc: string, Values: { number }, Unit: string }
MountCatalog.Passives = {
	Vigor = { Name = "Aliento vital", Desc = "Recuperas vida cada segundo mientras vas montado.", Values = { 0.4, 0.6, 0.8, 1.1, 1.5 }, Unit = "% de vida/s" },
	Zancada = { Name = "Zancada ligera", Desc = "Recuperas energía más rápido mientras vas montado.", Values = { 0.5, 0.8, 1.1, 1.5, 2 }, Unit = "% de energía/s" },
	Saqueo = { Name = "Saqueo", Desc = "Al matar montado, a veces sueltas oro extra.", Values = { 8, 12, 16, 22, 30 }, Unit = "% de oro extra" },
} :: { [string]: Passive }

---------------------------------------------------------------------
-- Especies
---------------------------------------------------------------------
export type Species = {
	Id: string, Name: string, Strip: number, Float: boolean, Faction: string?, Passive: string, Passive2: string,
	Shape: string, Color: Color3, Accent: Color3,
}
-- Shape decide la silueta de piezas: "Beast" (cuatro patas), "Boar", "Deer", "Turtle", "Frog", "Cloud", "Wisp", "Jelly", "Carpet"
MountCatalog.Species = {
	{ Id = "Jabali", Name = "Jabalí Pardo", Strip = 1, Float = false, Passive = "Vigor", Passive2 = "Zancada", Shape = "Boar", Color = Color3.fromRGB(122, 84, 56), Accent = Color3.fromRGB(235, 225, 200) },
	{ Id = "Ciervo", Name = "Ciervo Plateado", Strip = 1, Float = false, Passive = "Zancada", Passive2 = "Vigor", Shape = "Deer", Color = Color3.fromRGB(190, 190, 205), Accent = Color3.fromRGB(240, 240, 250) },
	{ Id = "Sapo", Name = "Sapo Gigante", Strip = 1, Float = false, Faction = "Shinobi", Passive = "Saqueo", Passive2 = "Vigor", Shape = "Frog", Color = Color3.fromRGB(90, 150, 80), Accent = Color3.fromRGB(230, 200, 80) },
	{ Id = "Lobo", Name = "Lobo del Alba", Strip = 2, Float = false, Passive = "Zancada", Passive2 = "Saqueo", Shape = "Beast", Color = Color3.fromRGB(110, 120, 150), Accent = Color3.fromRGB(230, 235, 255) },
	{ Id = "Corcel", Name = "Corcel Negro", Strip = 2, Float = false, Passive = "Vigor", Passive2 = "Zancada", Shape = "Deer", Color = Color3.fromRGB(40, 40, 52), Accent = Color3.fromRGB(200, 60, 60) },
	{ Id = "Tortuga", Name = "Tortuga Marina", Strip = 2, Float = false, Faction = "Pirate", Passive = "Vigor", Passive2 = "Saqueo", Shape = "Turtle", Color = Color3.fromRGB(70, 140, 120), Accent = Color3.fromRGB(220, 200, 140) },
	{ Id = "Tigre", Name = "Tigre de Ceniza", Strip = 3, Float = false, Passive = "Saqueo", Passive2 = "Zancada", Shape = "Beast", Color = Color3.fromRGB(215, 160, 80), Accent = Color3.fromRGB(50, 40, 40) },
	{ Id = "Oso", Name = "Oso de Roca", Strip = 3, Float = false, Passive = "Vigor", Passive2 = "Saqueo", Shape = "Boar", Color = Color3.fromRGB(100, 96, 100), Accent = Color3.fromRGB(170, 165, 150) },
	{ Id = "Medusa", Name = "Medusa Celeste", Strip = 3, Float = true, Passive = "Zancada", Passive2 = "Vigor", Shape = "Jelly", Color = Color3.fromRGB(150, 220, 255), Accent = Color3.fromRGB(255, 255, 255) },
	{ Id = "Nube", Name = "Nube Kinton", Strip = 4, Float = true, Faction = "Saiyan", Passive = "Zancada", Passive2 = "Saqueo", Shape = "Cloud", Color = Color3.fromRGB(255, 205, 80), Accent = Color3.fromRGB(255, 245, 200) },
	{ Id = "Espectro", Name = "Espectro Gris", Strip = 4, Float = true, Faction = "Shinigami", Passive = "Vigor", Passive2 = "Zancada", Shape = "Wisp", Color = Color3.fromRGB(150, 150, 175), Accent = Color3.fromRGB(190, 220, 255) },
	{ Id = "Alfombra", Name = "Alfombra Arcana", Strip = 4, Float = true, Passive = "Saqueo", Passive2 = "Vigor", Shape = "Carpet", Color = Color3.fromRGB(150, 60, 170), Accent = Color3.fromRGB(255, 215, 110) },
} :: { Species }

MountCatalog.ById = {} :: { [string]: Species }
for _, s in ipairs(MountCatalog.Species) do
	MountCatalog.ById[s.Id] = s
end

-- Una montura concreta = especie + rareza. Clave "Especie|Rareza"
function MountCatalog.Key(species: string, rarity: string): string
	return species .. "|" .. rarity
end

function MountCatalog.Parse(key: any): (Species?, string?)
	if typeof(key) ~= "string" then
		return nil, nil
	end
	local sp, rar = string.match(key, "^(%w+)|(%w+)$")
	if not sp or not rar then
		return nil, nil
	end
	local s = MountCatalog.ById[sp]
	if not s or not MountCatalog.RarityIndex[rar] then
		return nil, nil
	end
	return s, rar
end

-- % de velocidad extra de una montura según rareza y nivel
function MountCatalog.SpeedPct(rarity: string, level: number): number
	local idx = MountCatalog.RarityIndex[rarity] or 1
	return MountCatalog.Speed[idx] + (math.clamp(level, 1, MountCatalog.MaxLevel) - 1) * MountCatalog.LevelSpeed
end

-- Pasivas activas de una montura: { { Kind, Value } } (la segunda solo desde Legendario)
function MountCatalog.PassivesOf(species: Species, rarity: string, level: number): { { Kind: string, Value: number } }
	local idx = MountCatalog.RarityIndex[rarity] or 1
	local mult = 1 + (math.clamp(level, 1, MountCatalog.MaxLevel) - 1) * MountCatalog.LevelPassive
	local out = { { Kind = species.Passive, Value = MountCatalog.Passives[species.Passive].Values[idx] * mult } }
	if idx >= 4 then
		table.insert(out, { Kind = species.Passive2, Value = MountCatalog.Passives[species.Passive2].Values[idx] * mult * 0.75 })
	end
	return out
end

-- Especies que pueden salir de un huevo de la franja `tier` para un jugador de la facción `faction`
function MountCatalog.Pool(tier: number, faction: string?): { Species }
	local out: { Species } = {}
	for _, s in ipairs(MountCatalog.Species) do
		if s.Strip == tier or (faction ~= nil and s.Faction == faction) then
			table.insert(out, s)
		end
	end
	return out
end

return MountCatalog
