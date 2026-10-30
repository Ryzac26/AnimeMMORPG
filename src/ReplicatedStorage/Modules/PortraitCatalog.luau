--!strict
--[[
    PortraitCatalog (ModuleScript) -> ReplicatedStorage > Modules > PortraitCatalog
    RETRATOS PROPIOS (opcional). Si subes tu propia imagen a Roblox (Creator Hub > Assets > Images), pega aquí su id en el
    personaje que quieras: ese retrato reemplaza al busto 3D. Mientras un personaje esté en "" se usa el busto 3D en vivo.
    Formato: "rbxassetid://123456789"
    Usa SOLO arte que sea tuyo o tengas permiso de usar.
]]
local PortraitCatalog: { [string]: string } = {
	-- Saiyan
	Piccolo = "", Goku = "", Vegeta = "", Trunks = "", Gohan = "", Bulma = "",
	-- Shinobi
	Gaara = "", Naruto = "", Sasuke = "", Itachi = "", Kakashi = "", Sakura = "",
	-- Pirata
	Jinbe = "", Luffy = "", Zoro = "", Usopp = "", Sanji = "", Chopper = "",
	-- Shinigami
	Chad = "", Ichigo = "", Yoruichi = "", Uryu = "", Hitsugaya = "", Orihime = "",
}

return PortraitCatalog
