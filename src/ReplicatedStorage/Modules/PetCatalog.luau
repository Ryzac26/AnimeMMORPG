--!strict
--[[
    PetCatalog (ModuleScript) -> ReplicatedStorage.Modules.PetCatalog
    MASCOTAS: 9 familias x 5 rarezas = 45 mascotas. Cada rareza mejora a la anterior (los números suben en cada lista).
    Se equipan en la ranura "Accesorio2" (en pantalla aparece como "Mascota"). Sirven a TODAS las clases.
    Cada efecto es una lista de 5 valores, en orden: Común, Raro, Épico, Legendario, Mítico. Un solo lugar para rebalancear.

      Suerte    Zorro de la Suerte   +% a las probabilidades de botín (objetos, equipo, gemas, mascotas; no al oro ni a lo garantizado)
      Fortuna   Tanuki Mercader      +% de oro
      Sabiduria Búho Sabio           +% de experiencia
      Guardian  Tortuga Guardiana    +% Defensa y +% Vida
      Furia     Tigre Furioso        +% Ataque y +% Crítico
      Fenix     Fénix Menor          regenera % de la vida máxima por segundo, fuera de combate (6 s sin recibir golpes)
      Dragon    Dragón Joven         +% Ataque y +% Vida
      Hada      Hada Sanadora        +% Curación y regeneración fuera de combate
      Lobo      Lobo Sombra          +% Crítico y +% Suerte de botín
    Las claves de Effects son las de GearService.Get(): Ataque, Defensa, Vida, Critico, Curacion, Suerte, Oro, Xp, Regen.
    Ids: Pet_<Familia>_<Rareza>

    MASCOTAS DE FACCIÓN (solo las puede equipar y encontrar esa facción; efecto "Energia" = % de regeneración de Ki/Chakra/Haki/Reiatsu):
      Mono (Saiyan: energía + Ataque) · Sapo (Shinobi: energía + Crítico) · Loro (Pirata: energía + Oro) · Mariposa (Shinigami: energía + Xp)

    CRECIMIENTO: cada mascota sube de nivel 1 a 10 alimentándola (PetService). El nivel se guarda en "Plus" de la mascota (nivel = Plus+1).
      Cada nivel suma LEVEL_BONUS a sus efectos y LEVEL_SIZE a su tamaño. Evoluciones visuales en los niveles de EVOLVE_AT.
      Alimentar cuesta recursos de franja: los primeros niveles Hierba, luego Cristal, Reliquia y Corazón (FeedCost).
]]
local PetCatalog = {}

PetCatalog.MaxLevel = 10
PetCatalog.LEVEL_BONUS = 0.10 -- +10% de los efectos por nivel (nivel 10 = x1.9)
PetCatalog.LEVEL_SIZE = 0.04 -- +4% de tamaño por nivel
PetCatalog.EVOLVE_AT = { 4, 7, 10 } -- niveles en los que cambia el aspecto (más brillo, luz y halo)
PetCatalog.FeedRarityMult = { Comun = 1, Raro = 1.25, Epico = 1.6, Legendario = 2.1, Mitico = 2.8 } :: { [string]: number }

-- Multiplicador de efectos según el Plus guardado (nivel = Plus + 1)
function PetCatalog.LevelMult(plus: number?): number
	local lvl = math.clamp((plus or 0) + 1, 1, PetCatalog.MaxLevel)
	return 1 + PetCatalog.LEVEL_BONUS * (lvl - 1)
end

function PetCatalog.LevelOf(plus: number?): number
	return math.clamp((plus or 0) + 1, 1, PetCatalog.MaxLevel)
end

-- Etapa de evolución (0..3) de un nivel
function PetCatalog.Stage(level: number): number
	local n = 0
	for _, at in ipairs(PetCatalog.EVOLVE_AT) do
		if level >= at then
			n += 1
		end
	end
	return n
end

-- Costo de subir a `targetLevel` (2..10): { recurso, cantidad }
function PetCatalog.FeedCost(rarity: string, targetLevel: number): (string, number)
	local res = if targetLevel <= 3 then "Rec_1" elseif targetLevel <= 5 then "Rec_2" elseif targetLevel <= 7 then "Rec_3" else "Rec_4"
	local base = 5 + 3 * (targetLevel - 2)
	return res, math.ceil(base * (PetCatalog.FeedRarityMult[rarity] or 1))
end

PetCatalog.Rarities = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
PetCatalog.RarityName = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" }

PetCatalog.Families = {
	Suerte = { Name = "Zorro de la Suerte", Effects = { Suerte = { 0.03, 0.05, 0.08, 0.12, 0.18 } } },
	Fortuna = { Name = "Tanuki Mercader", Effects = { Oro = { 0.05, 0.08, 0.12, 0.17, 0.25 } } },
	Sabiduria = { Name = "Búho Sabio", Effects = { Xp = { 0.03, 0.05, 0.08, 0.12, 0.16 } } },
	Guardian = {
		Name = "Tortuga Guardiana",
		Effects = { Defensa = { 0.02, 0.03, 0.05, 0.07, 0.10 }, Vida = { 0.03, 0.05, 0.08, 0.12, 0.16 } },
	},
	Furia = {
		Name = "Tigre Furioso",
		Effects = { Ataque = { 0.02, 0.04, 0.06, 0.09, 0.13 }, Critico = { 0.01, 0.02, 0.03, 0.05, 0.07 } },
	},
	Fenix = { Name = "Fénix Menor", Effects = { Regen = { 0.005, 0.008, 0.012, 0.018, 0.025 } } },
	Dragon = {
		Name = "Dragón Joven",
		Effects = { Ataque = { 0.015, 0.03, 0.045, 0.07, 0.10 }, Vida = { 0.02, 0.03, 0.05, 0.07, 0.10 } },
	},
	Hada = {
		Name = "Hada Sanadora",
		Effects = { Curacion = { 0.04, 0.07, 0.10, 0.15, 0.22 }, Regen = { 0.002, 0.004, 0.006, 0.010, 0.015 } },
	},
	Lobo = {
		Name = "Lobo Sombra",
		Effects = { Critico = { 0.015, 0.025, 0.04, 0.06, 0.09 }, Suerte = { 0.01, 0.02, 0.03, 0.05, 0.07 } },
	},
	-- De facción (solo esa facción)
	Mono = {
		Name = "Mono Saiyan", Faction = "Saiyan",
		Effects = { Energia = { 0.10, 0.16, 0.24, 0.34, 0.48 }, Ataque = { 0.01, 0.02, 0.03, 0.05, 0.08 } },
	},
	Sapo = {
		Name = "Sapo Sabio", Faction = "Shinobi",
		Effects = { Energia = { 0.10, 0.16, 0.24, 0.34, 0.48 }, Critico = { 0.01, 0.015, 0.025, 0.04, 0.06 } },
	},
	Loro = {
		Name = "Loro Pirata", Faction = "Pirate",
		Effects = { Energia = { 0.10, 0.16, 0.24, 0.34, 0.48 }, Oro = { 0.03, 0.05, 0.08, 0.12, 0.18 } },
	},
	Mariposa = {
		Name = "Mariposa Infernal", Faction = "Shinigami",
		Effects = { Energia = { 0.10, 0.16, 0.24, 0.34, 0.48 }, Xp = { 0.02, 0.03, 0.05, 0.08, 0.12 } },
	},
} :: { [string]: { Name: string, Faction: string?, Effects: { [string]: { number } } } }
PetCatalog.FamilyOrder = { "Suerte", "Fortuna", "Sabiduria", "Guardian", "Furia", "Fenix", "Dragon", "Hada", "Lobo" }
PetCatalog.FactionFamily = { Saiyan = "Mono", Shinobi = "Sapo", Pirate = "Loro", Shinigami = "Mariposa" } :: { [string]: string }
PetCatalog.AllFamilies = { "Suerte", "Fortuna", "Sabiduria", "Guardian", "Furia", "Fenix", "Dragon", "Hada", "Lobo", "Mono", "Sapo", "Loro", "Mariposa" }

-- Aspecto del cuerpo que te sigue (PetFollowClient): colores y forma por familia.
--   Species: forma propia que dibuja PetFollowClient · Body/Accent/Belly: colores (cuerpo, detalles, panza)
--   Flies: flota en el aire (si no, camina/salta) · Ears/Tail/Wings/Horns/Shell/Stripes/Snout: rasgos
--   Fire/Sparkle: efectos · Charm: adorno propio (Clover = trébol, Leaf = hoja y saco)
PetCatalog.Looks = {
	Suerte = { Species = "Zorro", Body = Color3.fromRGB(240, 140, 60), Accent = Color3.fromRGB(255, 245, 230), Belly = Color3.fromRGB(255, 245, 230), Flies = false, Ears = true, Tail = true, Snout = true, Charm = "Clover" },
	Fortuna = { Species = "Tanuki", Body = Color3.fromRGB(150, 110, 75), Accent = Color3.fromRGB(235, 215, 170), Belly = Color3.fromRGB(235, 215, 170), Flies = false, Ears = true, Tail = true, Snout = true, Charm = "Leaf" },
	Sabiduria = { Species = "Buho", Body = Color3.fromRGB(165, 130, 90), Accent = Color3.fromRGB(240, 225, 190), Belly = Color3.fromRGB(240, 225, 190), Flies = true, Wings = true, Horns = true },
	Guardian = { Species = "Tortuga", Body = Color3.fromRGB(80, 160, 100), Accent = Color3.fromRGB(150, 110, 60), Belly = Color3.fromRGB(170, 210, 140), Flies = false, Shell = true, Tail = true },
	Furia = { Species = "Tigre", Body = Color3.fromRGB(245, 170, 50), Accent = Color3.fromRGB(40, 30, 25), Belly = Color3.fromRGB(255, 240, 220), Flies = false, Ears = true, Tail = true, Stripes = true, Snout = true },
	Fenix = { Species = "Fenix", Body = Color3.fromRGB(255, 110, 40), Accent = Color3.fromRGB(255, 215, 90), Belly = Color3.fromRGB(255, 215, 90), Flies = true, Wings = true, Tail = true, Fire = true },
	Dragon = { Species = "Dragon", Body = Color3.fromRGB(120, 70, 190), Accent = Color3.fromRGB(255, 200, 80), Belly = Color3.fromRGB(255, 200, 80), Flies = true, Wings = true, Horns = true, Tail = true, Snout = true },
	Hada = { Species = "Hada", Body = Color3.fromRGB(255, 170, 220), Accent = Color3.fromRGB(190, 240, 255), Belly = Color3.fromRGB(255, 230, 245), Flies = true, Wings = true, Sparkle = true },
	Lobo = { Species = "Lobo", Body = Color3.fromRGB(70, 75, 100), Accent = Color3.fromRGB(150, 190, 255), Belly = Color3.fromRGB(150, 160, 190), Flies = false, Ears = true, Tail = true, Snout = true },
	Mono = { Species = "Mono", Body = Color3.fromRGB(150, 95, 55), Accent = Color3.fromRGB(255, 190, 70), Belly = Color3.fromRGB(235, 200, 150), Flies = false, Ears = true, Tail = true, Snout = true },
	Sapo = { Species = "Sapo", Body = Color3.fromRGB(95, 170, 90), Accent = Color3.fromRGB(235, 220, 120), Belly = Color3.fromRGB(220, 235, 160), Flies = false, Snout = true },
	Loro = { Species = "Loro", Body = Color3.fromRGB(225, 60, 60), Accent = Color3.fromRGB(70, 150, 235), Belly = Color3.fromRGB(255, 220, 90), Flies = true, Wings = true, Tail = true },
	Mariposa = { Species = "Mariposa", Body = Color3.fromRGB(60, 40, 90), Accent = Color3.fromRGB(190, 150, 255), Belly = Color3.fromRGB(150, 230, 255), Flies = true, Wings = true, Sparkle = true },
} :: { [string]: { [string]: any } }

local EFFECT_TEXT: { [string]: string } = {
	Ataque = "Ataque", Defensa = "Defensa", Vida = "Vida", Critico = "Crítico", Curacion = "Curación",
	Suerte = "Suerte de botín", Oro = "Oro", Xp = "Experiencia", Regen = "Vida/s fuera de combate", Energia = "Regeneración de energía",
}
local EFFECT_ORDER = { "Ataque", "Critico", "Defensa", "Vida", "Curacion", "Suerte", "Oro", "Xp", "Regen", "Energia" }
PetCatalog.EffectText = EFFECT_TEXT

-- PODERES (Épico, Legendario, Mítico; las Comunes y Raras no tienen). Los ejecuta PetPowerService; aquí están los números y el texto.
-- Cada lista tiene 3 valores: Épico, Legendario, Mítico. En Desc: {cd} enfriamiento (s) · {every} cada cuántos golpes/monstruos · {pct} porcentaje · {v} multiplicador.
PetCatalog.Powers = {
	Suerte = { Name = "Olfato del Zorro", Cooldown = { 30, 22, 15 }, Desc = "Cada {cd} s, el siguiente monstruo que mates te da una segunda tirada de botín." },
	Fortuna = { Name = "Lluvia de monedas", Every = { 12, 9, 6 }, Value = { 5, 8, 12 }, Desc = "Cada {every} monstruos que mates, una lluvia de oro extra (x{v} del oro de un monstruo)." },
	Sabiduria = { Name = "Mente clara", Every = { 10, 8, 6 }, Value = { 0.06, 0.09, 0.12 }, Desc = "Cada {every} golpes, recuperas {pct}% de tu energía máxima (Ki, Chakra, Haki o Reiatsu)." },
	Guardian = { Name = "Caparazón", Cooldown = { 60, 50, 40 }, Value = { 0.20, 0.30, 0.40 }, Desc = "Si tu vida baja del 30%, un escudo de {pct}% de tu vida máxima durante 8 s. Se recarga en {cd} s." },
	Furia = { Name = "Zarpazo", Every = { 8, 7, 6 }, Value = { 0.6, 0.9, 1.3 }, Desc = "Cada {every} golpes, un zarpazo extra de {pct}% del daño del golpe." },
	Fenix = { Name = "Renacer", Cooldown = { 600, 480, 360 }, Value = { 0.15, 0.25, 0.40 }, Desc = "Si recibes un golpe mortal, revives con {pct}% de vida y 3 s de inmunidad. Se recarga en {cd} s." },
	Dragon = { Name = "Aliento de fuego", Cooldown = { 8, 6, 4 }, Value = { 0.5, 0.8, 1.2 }, Desc = "Cada {cd} s, al atacar, un aliento de fuego daña a los enemigos cercanos ({pct}% del golpe)." },
	Hada = { Name = "Brisa curativa", Cooldown = { 24, 18, 12 }, Value = { 0.08, 0.12, 0.16 }, Desc = "Cada {cd} s cura {pct}% de la vida máxima a ti y a tu grupo cercano." },
	Lobo = { Name = "Instinto cazador", Value = { 0.12, 0.20, 0.30 }, Desc = "+{pct}% de daño extra contra jefes, mini jefes y Metin." },
} :: { [string]: { Name: string, Cooldown: { number }?, Every: { number }?, Value: { number }?, Desc: string } }

-- Poder de una mascota: nombre, texto con sus números, y el nivel del poder (1..3). nil si no tiene (Común, Raro o mascota de facción).
function PetCatalog.PowerInfo(family: string, rarity: string): (string?, string?, number?)
	local cfg = PetCatalog.Powers[family]
	local tier = (table.find(PetCatalog.Rarities, rarity) or 0) - 2
	if not cfg or tier < 1 then
		return nil, nil, nil
	end
	local function n(list: { number }?): number
		return if list then list[tier] else 0
	end
	local text = cfg.Desc
	text = string.gsub(text, "{cd}", tostring(n(cfg.Cooldown)))
	text = string.gsub(text, "{every}", tostring(n(cfg.Every)))
	local v = n(cfg.Value)
	text = string.gsub(text, "{pct}", string.format("%g", math.floor(v * 1000 + 0.5) / 10))
	text = string.gsub(text, "{v}", tostring(v))
	return cfg.Name, text, tier
end
PetCatalog.EffectOrder = EFFECT_ORDER

function PetCatalog.Id(family: string, rarity: string): string
	return string.format("Pet_%s_%s", family, rarity)
end

PetCatalog.Items = {} :: { [string]: { [string]: any } }

for _, family in ipairs(PetCatalog.AllFamilies) do
	local def = PetCatalog.Families[family]
	for index, rarity in ipairs(PetCatalog.Rarities) do
		local effects: { [string]: number } = {}
		for effect, values in pairs(def.Effects) do
			effects[effect] = values[index]
		end
		local parts: { string } = { if def.Faction then "Mascota de facción" else "Mascota · Todas las clases" }
		for _, key in ipairs(EFFECT_ORDER) do
			local v = effects[key]
			if v then
				table.insert(parts, string.format("%s +%.1f%%", EFFECT_TEXT[key], v * 100))
			end
		end
		PetCatalog.Items[PetCatalog.Id(family, rarity)] = {
			Name = string.format("%s (%s)", def.Name, PetCatalog.RarityName[rarity]),
			Slot = "Accesorio2",
			Rarity = rarity,
			Faction = def.Faction,
			Pet = { Family = family, Effects = effects },
			Kind = "Pet",
			Desc = table.concat(parts, " · "),
		}
	end
end

return PetCatalog
