--!strict
--[[
    UIAssets (ModuleScript) -> StarterPlayer > StarterPlayerScripts > UIAssets
    Diccionario de IDs de imágenes para los marcos y efectos de UITheme.
]]

local UIAssets = {}

local assets: { [string]: string } = {
	-- Shinobi
	["shinobi_window"] = "rbxassetid://9050287733914",
	["shinobi_seal"] = "rbxassetid://12375909464194",
	["shinobi_portrait"] = "rbxassetid://10253668635246",
	["shinobi_wind"] = "rbxassetid://9583040976801",
	["shinobi_panel"] = "rbxassetid://76557203447425",
	["shinobi_leaf"] = "rbxassetid://7952385834412",

	-- Shinigami
	["shinigami_window"] = "rbxassetid://7369122138907",
	["shinigami_seal2"] = "rbxassetid://106065060407853",
	["shinigami_spirit"] = "rbxassetid://12849874265658",
	["shinigami_seal1"] = "rbxassetid://134770483044860", -- (Nota: hay otra variante en otra captura con id 119114899374619, se deja esta activa)
	["shinigami_portrait"] = "rbxassetid://125137814953673",
	["shinigami_panel"] = "rbxassetid://124292235855685",
	["shinigami_edge"] = "rbxassetid://9881656191165",

	-- Saiyan
	["saiyan_window"] = "rbxassetid://133972536473213", -- (También disponible id 82335733199824 si prefieres la otra)
	["saiyan_panel"] = "rbxassetid://107363156882752", -- (También disponible id 97443032455163)
	["saiyan_portrait"] = "rbxassetid://96569673960141",
	["saiyan_spark"] = "rbxassetid://132313599422345",
	["saiyan_flame"] = "rbxassetid://137896754632240",

	-- Pirate
	["pirate_window"] = "rbxassetid://128439470060890", -- (También disponible id 134356020825096)
	["pirate_wave2"] = "rbxassetid://121223660570103",
	["pirate_wave1"] = "rbxassetid://100723359659360",
	["pirate_portrait"] = "rbxassetid://132713043668734",
	["pirate_needle"] = "rbxassetid://86699892309893",
	["pirate_compass"] = "rbxassetid://95719920046547",
	["pirate_panel"] = "rbxassetid://110475678525450",
}

function UIAssets.Get(name: string): string?
	return assets[name]
end

return UIAssets