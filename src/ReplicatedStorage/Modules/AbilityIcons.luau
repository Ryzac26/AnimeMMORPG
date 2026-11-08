--!strict
--[[
    AbilityIcons (ModuleScript) -> ReplicatedStorage.Modules.AbilityIcons
    Iconos de los PODERES (barra de habilidades 1-7). 145 iconos en 3 láminas PNG de 1024x1024 (8x8 iconos de 128 px cada una):
    sube cada lámina a Roblox y pega su ID en SheetIds (1, 2, 3). Mientras un ID sea 0 el HUD usa las 2 letras del nombre de siempre.
    Clave: "<Personaje>/<slot 1-6>" y "General/7" (Primeros Auxilios).  Número = posición en la lámina (de izquierda a derecha, de arriba a abajo).
]]
local ICON = 128
local PER_SHEET = 64
local COLS = 8

local AbilityIcons = {}

-- IDs de las láminas: poderes_1.png, poderes_2.png, poderes_3.png (pégalos aquí cuando los subas)
AbilityIcons.SheetIds = { [1] = 131465115340620, [2] = 127350918844347, [3] = 139303001796735 } :: { [number]: number }

AbilityIcons.Index = {
	["Piccolo/1"] = 1,
	["Piccolo/2"] = 2,
	["Piccolo/3"] = 3,
	["Piccolo/4"] = 4,
	["Piccolo/5"] = 5,
	["Piccolo/6"] = 6,
	["Goku/1"] = 7,
	["Goku/2"] = 8,
	["Goku/3"] = 9,
	["Goku/4"] = 10,
	["Goku/5"] = 11,
	["Goku/6"] = 12,
	["Vegeta/1"] = 13,
	["Vegeta/2"] = 14,
	["Vegeta/3"] = 15,
	["Vegeta/4"] = 16,
	["Vegeta/5"] = 17,
	["Vegeta/6"] = 18,
	["Trunks/1"] = 19,
	["Trunks/2"] = 20,
	["Trunks/3"] = 21,
	["Trunks/4"] = 22,
	["Trunks/5"] = 23,
	["Trunks/6"] = 24,
	["Gohan/1"] = 25,
	["Gohan/2"] = 26,
	["Gohan/3"] = 27,
	["Gohan/4"] = 28,
	["Gohan/5"] = 29,
	["Gohan/6"] = 30,
	["Bulma/1"] = 31,
	["Bulma/2"] = 32,
	["Bulma/3"] = 33,
	["Bulma/4"] = 34,
	["Bulma/5"] = 35,
	["Bulma/6"] = 36,
	["Gaara/1"] = 37,
	["Gaara/2"] = 38,
	["Gaara/3"] = 39,
	["Gaara/4"] = 40,
	["Gaara/5"] = 41,
	["Gaara/6"] = 42,
	["Naruto/1"] = 43,
	["Naruto/2"] = 44,
	["Naruto/3"] = 45,
	["Naruto/4"] = 46,
	["Naruto/5"] = 47,
	["Naruto/6"] = 48,
	["Sasuke/1"] = 49,
	["Sasuke/2"] = 50,
	["Sasuke/3"] = 51,
	["Sasuke/4"] = 52,
	["Sasuke/5"] = 53,
	["Sasuke/6"] = 54,
	["Itachi/1"] = 55,
	["Itachi/2"] = 56,
	["Itachi/3"] = 57,
	["Itachi/4"] = 58,
	["Itachi/5"] = 59,
	["Itachi/6"] = 60,
	["Kakashi/1"] = 61,
	["Kakashi/2"] = 62,
	["Kakashi/3"] = 63,
	["Kakashi/4"] = 64,
	["Kakashi/5"] = 65,
	["Kakashi/6"] = 66,
	["Sakura/1"] = 67,
	["Sakura/2"] = 68,
	["Sakura/3"] = 69,
	["Sakura/4"] = 70,
	["Sakura/5"] = 71,
	["Sakura/6"] = 72,
	["Jinbe/1"] = 73,
	["Jinbe/2"] = 74,
	["Jinbe/3"] = 75,
	["Jinbe/4"] = 76,
	["Jinbe/5"] = 77,
	["Jinbe/6"] = 78,
	["Luffy/1"] = 79,
	["Luffy/2"] = 80,
	["Luffy/3"] = 81,
	["Luffy/4"] = 82,
	["Luffy/5"] = 83,
	["Luffy/6"] = 84,
	["Zoro/1"] = 85,
	["Zoro/2"] = 86,
	["Zoro/3"] = 87,
	["Zoro/4"] = 88,
	["Zoro/5"] = 89,
	["Zoro/6"] = 90,
	["Usopp/1"] = 91,
	["Usopp/2"] = 92,
	["Usopp/3"] = 93,
	["Usopp/4"] = 94,
	["Usopp/5"] = 95,
	["Usopp/6"] = 96,
	["Sanji/1"] = 97,
	["Sanji/2"] = 98,
	["Sanji/3"] = 99,
	["Sanji/4"] = 100,
	["Sanji/5"] = 101,
	["Sanji/6"] = 102,
	["Chopper/1"] = 103,
	["Chopper/2"] = 104,
	["Chopper/3"] = 105,
	["Chopper/4"] = 106,
	["Chopper/5"] = 107,
	["Chopper/6"] = 108,
	["Chad/1"] = 109,
	["Chad/2"] = 110,
	["Chad/3"] = 111,
	["Chad/4"] = 112,
	["Chad/5"] = 113,
	["Chad/6"] = 114,
	["Ichigo/1"] = 115,
	["Ichigo/2"] = 116,
	["Ichigo/3"] = 117,
	["Ichigo/4"] = 118,
	["Ichigo/5"] = 119,
	["Ichigo/6"] = 120,
	["Yoruichi/1"] = 121,
	["Yoruichi/2"] = 122,
	["Yoruichi/3"] = 123,
	["Yoruichi/4"] = 124,
	["Yoruichi/5"] = 125,
	["Yoruichi/6"] = 126,
	["Uryu/1"] = 127,
	["Uryu/2"] = 128,
	["Uryu/3"] = 129,
	["Uryu/4"] = 130,
	["Uryu/5"] = 131,
	["Uryu/6"] = 132,
	["Hitsugaya/1"] = 133,
	["Hitsugaya/2"] = 134,
	["Hitsugaya/3"] = 135,
	["Hitsugaya/4"] = 136,
	["Hitsugaya/5"] = 137,
	["Hitsugaya/6"] = 138,
	["Orihime/1"] = 139,
	["Orihime/2"] = 140,
	["Orihime/3"] = 141,
	["Orihime/4"] = 142,
	["Orihime/5"] = 143,
	["Orihime/6"] = 144,
	["General/7"] = 145,
} :: { [string]: number }

-- Devuelve un ImageLabel con el icono (recortado de su lámina) o nil si todavía no hay ID cargado
function AbilityIcons.Make(parent: Instance, key: string): ImageLabel?
	local n = AbilityIcons.Index[key]
	if not n then
		return nil
	end
	local sheet = (n - 1) // PER_SHEET + 1
	local id = AbilityIcons.SheetIds[sheet]
	if not id or id == 0 then
		return nil
	end
	local pos = (n - 1) % PER_SHEET
	local img = Instance.new("ImageLabel")
	img.Name = "AbilityIcon"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = "rbxassetid://" .. tostring(id)
	img.ImageRectSize = Vector2.new(ICON, ICON)
	img.ImageRectOffset = Vector2.new((pos % COLS) * ICON, (pos // COLS) * ICON)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = parent
	return img
end

return AbilityIcons
