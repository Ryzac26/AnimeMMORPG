--!strict
--[[
    CityAssets (ModuleScript) -> ServerScriptService > Services > CityAssets
    IDs de las imágenes de las ciudades. Déjalas vacías ("") y CityStyler dibuja todo con partes y texto.
    Cuando subas una imagen a Roblox (Creator Hub > Assets > Decal/Image), pega aquí su ID (solo el número o rbxassetid://número).

    Nombres (4 facciones: Saiyan, Shinobi, Pirate, Shinigami):
      <Faccion>_gate   cartel grande sobre cada portón (se ve de los dos lados)      512 x 128 px
      <Faccion>_sign   fondo de los letreros de los 6 comercios (el nombre se escribe encima)   512 x 128 px
      <Faccion>_plaza  dibujo del suelo de la plaza central (visto desde arriba)       1024 x 1024 px
]]
local IDS: { [string]: string } = {
	Saiyan_gate = "115796696831590",
	Saiyan_sign = "118440725836124",
	Saiyan_plaza = "101830275166267",

	Shinobi_gate = "112150816653200",
	Shinobi_sign = "138224541553277",
	Shinobi_plaza = "132310684011866",

	Pirate_gate = "136330927753856",
	Pirate_sign = "13758873964549",
	Pirate_plaza = "120074048029618",

	Shinigami_gate = "84300767587978",
	Shinigami_sign = "127171329336536",
	Shinigami_plaza = "77987107719747",
}

local CityAssets = {}

-- Devuelve el texto listo para Image/Texture, o nil si no hay ID
function CityAssets.Get(faction: string, kind: string): string?
	local raw = IDS[faction .. "_" .. kind]
	if raw == nil or raw == "" then
		return nil
	end
	if string.find(raw, "rbxassetid://", 1, true) then
		return raw
	end
	local digits = string.match(raw, "%d+")
	if digits then
		return "rbxassetid://" .. digits
	end
	return nil
end

return CityAssets