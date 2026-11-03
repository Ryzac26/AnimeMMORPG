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
]]
local PetCatalog = {}

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
} :: { [string]: { Name: string, Effects: { [string]: { number } } } }
PetCatalog.FamilyOrder = { "Suerte", "Fortuna", "Sabiduria", "Guardian", "Furia", "Fenix", "Dragon", "Hada", "Lobo" }

-- Aspecto del cuerpo que te sigue (PetFollowClient): colores y forma por familia.
--   Body/Accent: colores principales · Flies: flota en el aire (si no, camina/salta) · Ears/Tail/Wings/Horns/Shell/Stripes: rasgos
PetCatalog.Looks = {
	Suerte = { Body = Color3.fromRGB(240, 140, 60), Accent = Color3.fromRGB(255, 245, 230), Flies = false, Ears = true, Tail = true },
	Fortuna = { Body = Color3.fromRGB(150, 110, 75), Accent = Color3.fromRGB(235, 215, 170), Flies = false, Ears = true, Tail = true },
	Sabiduria = { Body = Color3.fromRGB(165, 130, 90), Accent = Color3.fromRGB(240, 225, 190), Flies = true, Wings = true, Horns = true },
	Guardian = { Body = Color3.fromRGB(80, 160, 100), Accent = Color3.fromRGB(150, 110, 60), Flies = false, Shell = true },
	Furia = { Body = Color3.fromRGB(245, 170, 50), Accent = Color3.fromRGB(40, 30, 25), Flies = false, Ears = true, Tail = true, Stripes = true },
	Fenix = { Body = Color3.fromRGB(255, 110, 40), Accent = Color3.fromRGB(255, 215, 90), Flies = true, Wings = true, Tail = true, Fire = true },
	Dragon = { Body = Color3.fromRGB(120, 70, 190), Accent = Color3.fromRGB(255, 200, 80), Flies = true, Wings = true, Horns = true, Tail = true },
	Hada = { Body = Color3.fromRGB(255, 170, 220), Accent = Color3.fromRGB(190, 240, 255), Flies = true, Wings = true, Sparkle = true },
	Lobo = { Body = Color3.fromRGB(70, 75, 100), Accent = Color3.fromRGB(150, 190, 255), Flies = false, Ears = true, Tail = true },
} :: { [string]: { [string]: any } }

local EFFECT_TEXT: { [string]: string } = {
	Ataque = "Ataque", Defensa = "Defensa", Vida = "Vida", Critico = "Crítico", Curacion = "Curación",
	Suerte = "Suerte de botín", Oro = "Oro", Xp = "Experiencia", Regen = "Vida/s fuera de combate",
}
local EFFECT_ORDER = { "Ataque", "Critico", "Defensa", "Vida", "Curacion", "Suerte", "Oro", "Xp", "Regen" }

function PetCatalog.Id(family: string, rarity: string): string
	return string.format("Pet_%s_%s", family, rarity)
end

PetCatalog.Items = {} :: { [string]: { [string]: any } }

for _, family in ipairs(PetCatalog.FamilyOrder) do
	local def = PetCatalog.Families[family]
	for index, rarity in ipairs(PetCatalog.Rarities) do
		local effects: { [string]: number } = {}
		for effect, values in pairs(def.Effects) do
			effects[effect] = values[index]
		end
		local parts: { string } = { "Mascota · Todas las clases" }
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
			Pet = { Family = family, Effects = effects },
			Kind = "Pet",
			Desc = table.concat(parts, " · "),
		}
	end
end

return PetCatalog
