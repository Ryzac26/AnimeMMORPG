--!strict
--[[
    AuraTextures (ModuleScript) -> ReplicatedStorage.Modules.AuraTextures
    Texturas de las auras (38 imágenes del pack "texturas"): nombre -> ID. AuraTextures.Get("Llama-A") devuelve "rbxassetid://ID"
    o "" si el nombre no existe (las partículas usan entonces su textura por defecto).
]]
local IDS: { [string]: number } = {
	["Brillo-suave"] = 91291577762741, -- 001
	["Destello-4-puntas"] = 128219854684046, -- 002
	["Destello-lente"] = 122472628443568, -- 003
	["Chispa-punto"] = 110415529972980, -- 004
	["Llama-A"] = 91960150464004, -- 005
	["Llama-B"] = 106737329105705, -- 006
	["Llama-C"] = 137369963605070, -- 007
	["Humo-A"] = 116430561957136, -- 008
	["Humo-B"] = 107035312859164, -- 009
	["Brasas"] = 86694461595433, -- 010
	["Rayo-A"] = 121151660436321, -- 011
	["Rayo-B"] = 132724586303233, -- 012
	["Rayo-C"] = 90824167177809, -- 013
	["Anillo-energia"] = 134563308247983, -- 014
	["Anillo-runas"] = 90645774754795, -- 015
	["Circulo-magico"] = 78158306344658, -- 016
	["Rayos-sol"] = 110095981368631, -- 017
	["Remolino"] = 117204057809725, -- 018
	["Galaxia-A"] = 105456813051344, -- 019
	["Galaxia-B"] = 104571721736968, -- 020
	["Campo-estrellas"] = 71223877129053, -- 021
	["Pluma-A"] = 126497900768575, -- 022
	["Pluma-B"] = 90092922504459, -- 023
	["Cristal-A"] = 92808991091970, -- 024
	["Cristal-B"] = 80752398452542, -- 025
	["Copo-nieve-A"] = 89050566760252, -- 026
	["Copo-nieve-B"] = 74426716047832, -- 027
	["Petalo-sakura"] = 96702226910168, -- 028
	["Hoja"] = 73113718578527, -- 029
	["Mariposa"] = 115398286945771, -- 030
	["Burbuja"] = 131376857572346, -- 031
	["Ola-agua"] = 83463218565014, -- 032
	["Ojo-vacio"] = 85716215801602, -- 033
	["Columna-luz"] = 71423530065333, -- 034
	["Estela-viento"] = 92698701537678, -- 035
	["Halo-corona"] = 121535331639643, -- 036
	["Pinchos-dorados"] = 93558432060007, -- 037
	["Kunai-hoja-remolino"] = 71615387471543, -- 038
}

local M = {}

function M.Get(name: string): string
	local id = IDS[name]
	return if id then "rbxassetid://" .. tostring(id) else ""
end

return M
