--!strict
--[[
    HudKit (ModuleScript) -> StarterPlayer > StarterPlayerScripts > HudKit
    Imágenes del HUD del jugador por facción (kit "hud.zip", IDs de Imágenes). HudKit.Get("Saiyan"|"Shinobi"|"Pirate"|"Shinigami")
    -> { panel, portrait, housing, level, crest, barHP, barEnergia, barXP } (rbxassetid) o nil si falta alguno.
]]
local HudKit = {}
local IDS: { [string]: { [string]: string } } = {
	Saiyan = {
		panel = "rbxassetid://76669753042224",
		portrait = "rbxassetid://109675065869350",
		housing = "rbxassetid://107428751218153",
		level = "rbxassetid://85061697941584",
		crest = "rbxassetid://90184541370710",
		barHP = "rbxassetid://87239715937943",
		barEnergia = "rbxassetid://91696508157252",
		barXP = "rbxassetid://122467926945275",
	},
	Shinobi = {
		panel = "rbxassetid://75746018015230",
		portrait = "rbxassetid://115242026428015",
		housing = "rbxassetid://84279013754493",
		level = "rbxassetid://79260535357186",
		crest = "rbxassetid://134394125900924",
		barHP = "rbxassetid://96557799059012",
		barEnergia = "rbxassetid://111822952107232",
		barXP = "rbxassetid://116570911105028",
	},
	Pirate = {
		panel = "rbxassetid://118864546116586",
		portrait = "rbxassetid://88752578520348",
		housing = "rbxassetid://108073603068491",
		level = "rbxassetid://139303617886345",
		crest = "rbxassetid://84241243569292",
		barHP = "rbxassetid://75462232660579",
		barEnergia = "rbxassetid://96418763281824",
		barXP = "rbxassetid://80837328065650",
	},
	Shinigami = {
		panel = "rbxassetid://73074218621951",
		portrait = "rbxassetid://130636086577071",
		housing = "rbxassetid://80044326684466",
		level = "rbxassetid://121665083974480",
		crest = "rbxassetid://124088024182289",
		barHP = "rbxassetid://86762135467149",
		barEnergia = "rbxassetid://121710214184100",
		barXP = "rbxassetid://121647624311361",
	},
}
function HudKit.Get(faction: string): { [string]: string }?
	return IDS[faction]
end
return HudKit
