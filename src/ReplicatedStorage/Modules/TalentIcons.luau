--!strict
--[[
    TalentIcons (ModuleScript) -> ReplicatedStorage.Modules.TalentIcons
    Iconos de las PASIVAS del árbol: 73 imágenes sueltas (carpeta talentos/, nombre = NNN_idNodo_Nombre.png; 69-73 = las 5 ramas).
    Sube cada PNG y pega su ID en Ids[NNN]. Mientras falte se usan los emojis. Clave = Id del nodo (d1, o5, as3...) o "Rama_<rama>".
]]
local TalentIcons = {}

-- IDs por número de icono: Ids[1] = 123456789, ... (se rellena cuando se suban las imágenes)
TalentIcons.Ids = {
	[1] = 136651274781080, -- 001_d1_Piel-de-Hierro
	[2] = 123867274728520, -- 002_d2_Corazon-Robusto
	[3] = 74112778385887, -- 003_d3_Respiracion-Firme
	[4] = 104250802811268, -- 004_d4_Voluntad-de-Roca
	[5] = 91190098231329, -- 005_d5_Guardia-del-Vinculo
	[6] = 107011899817131, -- 006_d6_Escudo-Reactivo
	[7] = 85342919939553, -- 007_d7_Provocador
	[8] = 97917652543984, -- 008_d8_Espinas
	[9] = 98837763010812, -- 009_d9_Fortaleza
	[10] = 87469937667907, -- 010_d10_Muro-Viviente
	[11] = 108423659122405, -- 011_d11_Escudo-de-Sangre
	[12] = 120013553173004, -- 012_dk_Bastion-Inamovible
	[13] = 86844772387165, -- 013_o1_Filo-Afilado
	[14] = 74540366874396, -- 014_o2_Ojo-Certero
	[15] = 135841292291608, -- 015_o3_Golpe-Brutal
	[16] = 108480892770875, -- 016_o4_Instinto-Cazador
	[17] = 116935747053351, -- 017_o5_Sed-de-Batalla
	[18] = 113127602212137, -- 018_o6_Precision-Letal
	[19] = 77215957969434, -- 019_o7_Rabia-Creciente
	[20] = 85759173791621, -- 020_o8_Cazarrecompensas
	[21] = 110390778807694, -- 021_o9_Maestro-del-Combate
	[22] = 79372687083704, -- 022_o10_Golpe-Decisivo
	[23] = 86811953616953, -- 023_o11_Ejecutor
	[24] = 135191590264106, -- 024_ok_Furia-Sangrienta
	[25] = 87499248149265, -- 025_s1_Manos-Sanadoras
	[26] = 135930836604204, -- 026_s2_Aliento-Vital
	[27] = 96208350782664, -- 027_s3_Mente-Serena
	[28] = 96656694388341, -- 028_s4_Bendicion-Menor
	[29] = 133292151837688, -- 029_s5_Aura-de-Vigor
	[30] = 83575288276376, -- 030_s6_Inspiracion
	[31] = 138318194885235, -- 031_s7_Escudo-Compartido
	[32] = 94399571131784, -- 032_s8_Medicina-Potente
	[33] = 131310190592611, -- 033_s9_Gran-Sanacion
	[34] = 79839651433659, -- 034_s10_Coro-de-Batalla
	[35] = 103457473442204, -- 035_s11_Guardian-Eterno
	[36] = 71602687406087, -- 036_sk_Pacto-Vital
	[37] = 116771462483398, -- 037_u1_Buscador-de-Tesoros
	[38] = 127634121755949, -- 038_u2_Suerte-del-Viajero
	[39] = 96696848493991, -- 039_u3_Aprendiz-Veloz
	[40] = 125437110681204, -- 040_u4_Cuerpo-Agil
	[41] = 93027492950227, -- 041_u5_Saqueador
	[42] = 122842069325661, -- 042_u6_Fortuna
	[43] = 108107918179196, -- 043_u7_Sabiduria
	[44] = 138056461397414, -- 044_u8_Todoterreno
	[45] = 93461903911884, -- 045_u9_Rey-de-la-Colina
	[46] = 104266161707897, -- 046_u10_Bendicion-del-Azar
	[47] = 122504764772353, -- 047_u11_Maestro-Estratega
	[48] = 112054730534498, -- 048_uk_Fortuna-Imperial
	[49] = 74893742671693, -- 049_as1_Sangre-de-Guerrero
	[50] = 130733480757024, -- 050_as2_Ki-Desbordante
	[51] = 108507093157841, -- 051_as3_Orgullo-Saiyan
	[52] = 121894545551740, -- 052_as4_Instinto-Superior
	[53] = 96616057071977, -- 053_ask_Zenkai
	[54] = 80340477467752, -- 054_an1_Chakra-Profundo
	[55] = 82617703558043, -- 055_an2_Sigilo
	[56] = 109696733070891, -- 056_an3_Sabiduria-Ninja
	[57] = 126935905811476, -- 057_an4_Reflejos
	[58] = 78040410300036, -- 058_ank_Senjutsu
	[59] = 89178064094386, -- 059_ap1_Ambicion
	[60] = 90588247414347, -- 060_ap2_Voluntad-Ferrea
	[61] = 135467226704595, -- 061_ap3_Haki-del-Rey
	[62] = 91023797694578, -- 062_ap4_Ruta-Afortunada
	[63] = 105917264469042, -- 063_apk_Yonko
	[64] = 102992751457753, -- 064_ag1_Reiatsu-Elevado
	[65] = 89260964933735, -- 065_ag2_Alma-Pura
	[66] = 71514495016487, -- 066_ag3_Zanpakuto-Despierto
	[67] = 74707653934190, -- 067_ag4_Shunpo-Perfecto
	[68] = 80660546806594, -- 068_agk_Bankai-Perfecto
	[69] = 140216299684936, -- 069_Rama-Defensa_Rama-Defensa
	[70] = 101190677633286, -- 070_Rama-Ofensiva_Rama-Ofensiva
	[71] = 126061958413747, -- 071_Rama-Soporte_Rama-Soporte
	[72] = 76346891198108, -- 072_Rama-Utilidad_Rama-Utilidad
	[73] = 102820323041020, -- 073_Rama-Ascendencia_Rama-Ascendencia
} :: { [number]: number }

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

local function idOf(key: string): number?
	local n = TalentIcons.Index[key]
	local id = if n then TalentIcons.Ids[n] else nil
	return if id and id ~= 0 then id else nil
end

-- ¿hay icono listo para esta clave?
function TalentIcons.Has(key: string): boolean
	return idOf(key) ~= nil
end

-- Devuelve un ImageLabel con el icono o nil si todavía no hay ID cargado
function TalentIcons.Make(parent: Instance, key: string): ImageLabel?
	local id = idOf(key)
	if not id then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "TalentIcon"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = "rbxassetid://" .. tostring(id)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 2
	img.Parent = parent
	return img
end

return TalentIcons
