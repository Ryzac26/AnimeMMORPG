--!strict
--[[
    TalentIcons (ModuleScript) -> ReplicatedStorage.Modules.TalentIcons
    Iconos de las PASIVAS del árbol de talentos: 73 iconos en 2 láminas PNG de 1024x1024 (8x8 iconos de 128 px).
    Sube talentos_1.png y talentos_2.png a Roblox y pega sus IDs en SheetIds (1, 2). Mientras un ID sea 0 se usan los emojis de siempre.
    Clave = Id del nodo del TalentCatalog (d1, o5, as3...) y "Rama_<rama>" para las 5 ramas. Número = posición en la lámina
    (izquierda a derecha, arriba a abajo; la lámina 2 sigue la cuenta: 65 = primer icono de la lámina 2).
]]
local ICON = 128
local PER_SHEET = 64
local COLS = 8

local TalentIcons = {}

-- IDs de las láminas: talentos_1.png, talentos_2.png (pégalos aquí cuando los subas)
TalentIcons.SheetIds = { [1] = 104471046968971, [2] = 73183678030694 } :: { [number]: number }

TalentIcons.Index = {
	["d1"] = 1,
	["d2"] = 2,
	["d3"] = 3,
	["d4"] = 4,
	["d5"] = 5,
	["d6"] = 6,
	["d7"] = 7,
	["d8"] = 8,
	["d9"] = 9,
	["d10"] = 10,
	["d11"] = 11,
	["dk"] = 12,
	["o1"] = 13,
	["o2"] = 14,
	["o3"] = 15,
	["o4"] = 16,
	["o5"] = 17,
	["o6"] = 18,
	["o7"] = 19,
	["o8"] = 20,
	["o9"] = 21,
	["o10"] = 22,
	["o11"] = 23,
	["ok"] = 24,
	["s1"] = 25,
	["s2"] = 26,
	["s3"] = 27,
	["s4"] = 28,
	["s5"] = 29,
	["s6"] = 30,
	["s7"] = 31,
	["s8"] = 32,
	["s9"] = 33,
	["s10"] = 34,
	["s11"] = 35,
	["sk"] = 36,
	["u1"] = 37,
	["u2"] = 38,
	["u3"] = 39,
	["u4"] = 40,
	["u5"] = 41,
	["u6"] = 42,
	["u7"] = 43,
	["u8"] = 44,
	["u9"] = 45,
	["u10"] = 46,
	["u11"] = 47,
	["uk"] = 48,
	["as1"] = 49,
	["as2"] = 50,
	["as3"] = 51,
	["as4"] = 52,
	["ask"] = 53,
	["an1"] = 54,
	["an2"] = 55,
	["an3"] = 56,
	["an4"] = 57,
	["ank"] = 58,
	["ap1"] = 59,
	["ap2"] = 60,
	["ap3"] = 61,
	["ap4"] = 62,
	["apk"] = 63,
	["ag1"] = 64,
	["ag2"] = 65,
	["ag3"] = 66,
	["ag4"] = 67,
	["agk"] = 68,
	["Rama_Defensa"] = 69,
	["Rama_Ofensiva"] = 70,
	["Rama_Soporte"] = 71,
	["Rama_Utilidad"] = 72,
	["Rama_Ascendencia"] = 73,
} :: { [string]: number }

-- ¿hay icono listo para esta clave?
function TalentIcons.Has(key: string): boolean
	local n = TalentIcons.Index[key]
	if not n then
		return false
	end
	local id = TalentIcons.SheetIds[(n - 1) // PER_SHEET + 1]
	return id ~= nil and id ~= 0
end

-- Devuelve un ImageLabel con el icono (recortado de su lámina) o nil si todavía no hay ID cargado
function TalentIcons.Make(parent: Instance, key: string): ImageLabel?
	local n = TalentIcons.Index[key]
	if not n or not TalentIcons.Has(key) then
		return nil
	end
	local pos = (n - 1) % PER_SHEET
	local img = Instance.new("ImageLabel")
	img.Name = "TalentIcon"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = "rbxassetid://" .. tostring(TalentIcons.SheetIds[(n - 1) // PER_SHEET + 1])
	img.ImageRectSize = Vector2.new(ICON, ICON)
	img.ImageRectOffset = Vector2.new((pos % COLS) * ICON, (pos // COLS) * ICON)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = parent
	return img
end

return TalentIcons
