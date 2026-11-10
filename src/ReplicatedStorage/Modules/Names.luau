--!strict
--[[
    Names (ModuleScript) -> ReplicatedStorage > Modules > Names
    NOMBRES VISIBLES (los ids internos no cambian: "Saiyan", "Shinobi", "Pirate", "Shinigami" y las claves de personaje siguen
    guardando datos, iconos y modelos). TODO lo que el jugador lee sale de aquí:
      Names.Faction(id)            -> "Guerreros de Élite" ...
      Names.FactionShort(id)       -> "Élite" ...
      Names.Territory(id)          -> "Imperio de Élite" ...
      Names.Char(claveInterna)     -> nombre original del personaje (Goku -> "Kaelon")
]]
local Names = {}

local FACTION: { [string]: { Full: string, Short: string, Territory: string } } = {
	Saiyan = { Full = "Guerreros de Élite", Short = "Élite", Territory = "Imperio de Élite" },
	Shinobi = { Full = "Shinobi del Sigilo", Short = "Sigilo", Territory = "Alianza del Sigilo" },
	Pirate = { Full = "Navegantes de los Mares", Short = "Navegantes", Territory = "Flota de Navegantes" },
	Shinigami = { Full = "Guardianes Espirituales", Short = "Guardianes", Territory = "Corte Espiritual" },
}

local CHAR: { [string]: string } = {
	Piccolo = "Torvak", Goku = "Kaelon", Vegeta = "Vorren", Trunks = "Tiryn", Gohan = "Ghalen", Bulma = "Belora",
	Gaara = "Kuroma", Naruto = "Hikaro", Sasuke = "Senrei", Itachi = "Tsukane", Kakashi = "Kagemi", Sakura = "Hanabi",
	Jinbe = "Orcan", Luffy = "Marlo", Zoro = "Zarek", Usopp = "Tobbin", Sanji = "Salvio", Chopper = "Pimpa",
	Chad = "Ghedo", Ichigo = "Asahi", Yoruichi = "Yamira", Uryu = "Sorai", Hitsugaya = "Fuyuki", Orihime = "Miyori",
}

local function find(id: string): string
	for k in pairs(FACTION) do
		if string.find(id, k, 1, true) then
			return k
		end
	end
	if string.find(id, "Pirat", 1, true) then
		return "Pirate"
	end
	return id
end

function Names.Faction(id: string): string
	local f = FACTION[find(id)]
	return if f then f.Full else id
end
function Names.FactionShort(id: string): string
	local f = FACTION[find(id)]
	return if f then f.Short else id
end
function Names.Territory(id: string): string
	local f = FACTION[find(id)]
	return if f then f.Territory else id
end
function Names.Char(key: string): string
	return CHAR[key] or key
end

return Names
