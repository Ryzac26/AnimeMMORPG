--!strict
--[[
    TitleFrames (ModuleScript) -> ReplicatedStorage.Modules.TitleFrames
    Imágenes de las PLACAS de título (carpeta marcos/, 56 PNG numerados) y los "LOOKS" (estilos completos) que usa TitleBadge.
      Ids[NNN] = ID de la imagen (tipo Imágenes) · Index["Nombre-sin-numero"] = NNN
      Get(nombre) -> "rbxassetid://..."  ("" si no existe)
    LOOK = { Frame, Tile, Tint, TileAlpha, Fx?, Wing?, Top?, Swirl?, Spark?, Text? }
      Frame  : marco estirable (Marco-<Frame>)          Tile  : textura interior (Tex-<Tile>), Tint la oscurece/tiñe, TileAlpha = transparencia
      Fx     : fondo animado de TitleBadge (si falta, el del título)
      Wing   : alas (Ala-<Wing>-Izq/Der)  -> desde rareza Legendario        Top : adorno superior (Adorno-<Top>) -> desde Épico
      Swirl  : remolino detrás de la placa -> solo Mítico                   Spark: color de los destellos -> desde Épico
      Text   : "dark" para fondos claros (pergamino)
    Para cambiar el estilo de un título: edita su campo Look en TitleCatalog (o el LOOK de aquí).
]]
local M = {}

M.Ids = {
	[1] = 115075925807334, -- 001_Marco-Oro-Gemas
	[2] = 77202536107632, -- 002_Marco-Piedra-Runas
	[3] = 119956752048440, -- 003_Marco-Trenza-Dorada
	[4] = 126784725540771, -- 004_Marco-Laurel-Honor
	[5] = 108116715903688, -- 005_Marco-Plata-Muralla
	[6] = 114403843107409, -- 006_Marco-Hierro-Forja
	[7] = 93453237316815, -- 007_Marco-Llamas-Obsidiana
	[8] = 132396470004811, -- 008_Marco-Hielo-Cristal
	[9] = 134547230042523, -- 009_Marco-Rayo-Tormenta
	[10] = 129010960306934, -- 010_Marco-Madera-Laton
	[11] = 126434149762672, -- 011_Marco-Velo-Espectral
	[12] = 129552262115863, -- 012_Marco-Bambu-Hoja
	[13] = 89652430388867, -- 013_Marco-Ki-Saiyan
	[14] = 81965899644759, -- 014_Marco-Sakura-Noble
	[15] = 114698696262932, -- 015_Marco-Cosmos
	[16] = 86303623136256, -- 016_Marco-Eclipse
	[17] = 135394252311932, -- 017_Marco-Cobre-Simple
	[18] = 138627968185987, -- 018_Marco-Acero-Simple
	[19] = 136336464105161, -- 019_Ala-Dorada-Izq
	[20] = 97281670746667, -- 020_Ala-Dorada-Der
	[21] = 79151148268889, -- 021_Ala-Cristal-Arcoiris-Izq
	[22] = 103011882573841, -- 022_Ala-Cristal-Arcoiris-Der
	[23] = 134236825245789, -- 023_Ala-Celeste-Izq
	[24] = 79448092825091, -- 024_Ala-Celeste-Der
	[25] = 135497268321878, -- 025_Ala-Sombra-Izq
	[26] = 122917156310362, -- 026_Ala-Sombra-Der
	[27] = 100404735947057, -- 027_Ala-Fuego-Izq
	[28] = 135909256972809, -- 028_Ala-Fuego-Der
	[29] = 81323040284093, -- 029_Ala-Hielo-Izq
	[30] = 77049702676727, -- 030_Ala-Hielo-Der
	[31] = 114310301312599, -- 031_Ala-Mariposa-Izq
	[32] = 95419389125211, -- 032_Ala-Mariposa-Der
	[33] = 86550260572113, -- 033_Ala-Cosmos-Izq
	[34] = 131487681628796, -- 034_Ala-Cosmos-Der
	[35] = 130681371040565, -- 035_Remolino-Rosa
	[36] = 106211207419198, -- 036_Remolino-Dorado
	[37] = 103024488026798, -- 037_Aurora-Verde
	[38] = 116482484166925, -- 038_Remolino-Vacio
	[39] = 81391661237556, -- 039_Adorno-Corona
	[40] = 108734671181356, -- 040_Adorno-Cuernos
	[41] = 98547487146643, -- 041_Adorno-Llama
	[42] = 96234835501628, -- 042_Adorno-Halo
	[43] = 107097720127090, -- 043_Adorno-Rayo
	[44] = 130823172777162, -- 044_Adorno-Sakura
	[45] = 113350131849115, -- 045_Adorno-Hielo
	[46] = 96729017038198, -- 046_Adorno-Estrellas
	[47] = 89786063893869, -- 047_Tex-Piedra
	[48] = 125891890564089, -- 048_Tex-Ladrillo
	[49] = 88126949665757, -- 049_Tex-Pergamino
	[50] = 103664898458511, -- 050_Tex-Madera
	[51] = 101009995835364, -- 051_Tex-Hierro
	[52] = 140098956421899, -- 052_Tex-Lava
	[53] = 126187339904196, -- 053_Tex-Marmol
	[54] = 71012365110936, -- 054_Tex-Cuero-Azul
	[55] = 87142124595034, -- 055_Tex-Bambu
	[56] = 104900806646141, -- 056_Tex-Galaxia-Fondo
} :: { [number]: number }

M.Index = {
	["Marco-Oro-Gemas"] = 1,
	["Marco-Piedra-Runas"] = 2,
	["Marco-Trenza-Dorada"] = 3,
	["Marco-Laurel-Honor"] = 4,
	["Marco-Plata-Muralla"] = 5,
	["Marco-Hierro-Forja"] = 6,
	["Marco-Llamas-Obsidiana"] = 7,
	["Marco-Hielo-Cristal"] = 8,
	["Marco-Rayo-Tormenta"] = 9,
	["Marco-Madera-Laton"] = 10,
	["Marco-Velo-Espectral"] = 11,
	["Marco-Bambu-Hoja"] = 12,
	["Marco-Ki-Saiyan"] = 13,
	["Marco-Sakura-Noble"] = 14,
	["Marco-Cosmos"] = 15,
	["Marco-Eclipse"] = 16,
	["Marco-Cobre-Simple"] = 17,
	["Marco-Acero-Simple"] = 18,
	["Ala-Dorada-Izq"] = 19,
	["Ala-Dorada-Der"] = 20,
	["Ala-Cristal-Arcoiris-Izq"] = 21,
	["Ala-Cristal-Arcoiris-Der"] = 22,
	["Ala-Celeste-Izq"] = 23,
	["Ala-Celeste-Der"] = 24,
	["Ala-Sombra-Izq"] = 25,
	["Ala-Sombra-Der"] = 26,
	["Ala-Fuego-Izq"] = 27,
	["Ala-Fuego-Der"] = 28,
	["Ala-Hielo-Izq"] = 29,
	["Ala-Hielo-Der"] = 30,
	["Ala-Mariposa-Izq"] = 31,
	["Ala-Mariposa-Der"] = 32,
	["Ala-Cosmos-Izq"] = 33,
	["Ala-Cosmos-Der"] = 34,
	["Remolino-Rosa"] = 35,
	["Remolino-Dorado"] = 36,
	["Aurora-Verde"] = 37,
	["Remolino-Vacio"] = 38,
	["Adorno-Corona"] = 39,
	["Adorno-Cuernos"] = 40,
	["Adorno-Llama"] = 41,
	["Adorno-Halo"] = 42,
	["Adorno-Rayo"] = 43,
	["Adorno-Sakura"] = 44,
	["Adorno-Hielo"] = 45,
	["Adorno-Estrellas"] = 46,
	["Tex-Piedra"] = 47,
	["Tex-Ladrillo"] = 48,
	["Tex-Pergamino"] = 49,
	["Tex-Madera"] = 50,
	["Tex-Hierro"] = 51,
	["Tex-Lava"] = 52,
	["Tex-Marmol"] = 53,
	["Tex-Cuero-Azul"] = 54,
	["Tex-Bambu"] = 55,
	["Tex-Galaxia-Fondo"] = 56,
} :: { [string]: number }

function M.Get(name: string): string
	local n = M.Index[name]
	local id = if n then M.Ids[n] else nil
	return if id and id > 0 then "rbxassetid://" .. tostring(id) else ""
end

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local W = c(255, 255, 255)

export type Look = {
	Frame: string, Tile: string?, Tint: Color3?, TileAlpha: number?, Fx: string?, Wing: string?, Top: string?, Swirl: string?, Spark: Color3?, Text: string?,
}

M.Looks = {
	Cobre = { Frame = "Cobre-Simple" },
	Acero = { Frame = "Acero-Simple" },
	Plata = { Frame = "Plata-Muralla", Tile = "Hierro", Tint = c(150, 160, 190), TileAlpha = 0.45, Top = "Halo", Spark = c(220, 235, 255) },
	Hierro = { Frame = "Hierro-Forja", Tile = "Hierro", Tint = c(190, 190, 200), TileAlpha = 0.25, Spark = c(255, 170, 90) },
	Forja = { Frame = "Hierro-Forja", Tile = "Lava", Tint = c(255, 200, 150), TileAlpha = 0.2, Fx = "llamas", Wing = "Fuego", Top = "Llama", Swirl = "Remolino-Dorado", Spark = c(255, 190, 80) },
	Ascua = { Frame = "Llamas-Obsidiana", Tile = "Lava", Tint = c(255, 210, 170), TileAlpha = 0.15, Fx = "llamas", Wing = "Fuego", Top = "Llama", Swirl = "Remolino-Dorado", Spark = c(255, 170, 60) },
	Tormenta = { Frame = "Rayo-Tormenta", Tile = "Cuero-Azul", Tint = c(190, 200, 255), TileAlpha = 0.2, Fx = "rayos", Wing = "Celeste", Top = "Rayo", Swirl = "Remolino-Vacio", Spark = c(190, 225, 255) },
	Escarcha = { Frame = "Hielo-Cristal", Tile = "Marmol", Tint = c(130, 190, 235), TileAlpha = 0.3, Fx = "cristal", Wing = "Hielo", Top = "Hielo", Swirl = "Aurora-Verde", Spark = c(210, 245, 255) },
	Cristal = { Frame = "Hielo-Cristal", Tile = "Marmol", Tint = c(170, 160, 235), TileAlpha = 0.3, Fx = "cristal", Wing = "Cristal-Arcoiris", Top = "Estrellas", Swirl = "Remolino-Rosa", Spark = c(255, 210, 255) },
	Honor = { Frame = "Laurel-Honor", Tile = "Pergamino", Tint = c(255, 240, 215), TileAlpha = 0.05, Fx = "simple", Wing = "Dorada", Top = "Corona", Swirl = "Remolino-Dorado", Spark = c(255, 226, 130), Text = "dark" },
	Realeza = { Frame = "Oro-Gemas", Tile = "Cuero-Azul", Tint = c(255, 230, 200), TileAlpha = 0.15, Fx = "oro", Wing = "Dorada", Top = "Corona", Swirl = "Remolino-Dorado", Spark = c(255, 226, 130) },
	Campeon = { Frame = "Oro-Gemas", Tile = "Madera", Tint = c(255, 220, 190), TileAlpha = 0.25, Fx = "oro", Wing = "Cristal-Arcoiris", Top = "Corona", Swirl = "Remolino-Rosa", Spark = c(255, 226, 255) },
	Dragon = { Frame = "Trenza-Dorada", Tile = "Lava", Tint = c(255, 190, 120), TileAlpha = 0.1, Fx = "llamas", Wing = "Fuego", Top = "Llama", Swirl = "Remolino-Dorado", Spark = c(255, 200, 90) },
	Coloso = { Frame = "Piedra-Runas", Tile = "Piedra", Tint = c(190, 190, 215), TileAlpha = 0.1, Fx = "cristal", Wing = "Cosmos", Top = "Estrellas", Swirl = "Remolino-Vacio", Spark = c(190, 150, 255) },
	Muralla = { Frame = "Plata-Muralla", Tile = "Ladrillo", Tint = c(255, 235, 225), TileAlpha = 0.1, Fx = "simple", Wing = "Celeste", Top = "Halo", Swirl = "Remolino-Dorado", Spark = c(255, 240, 200) },
	Marea = { Frame = "Madera-Laton", Tile = "Madera", Tint = c(200, 215, 255), TileAlpha = 0.35, Fx = "olas", Wing = "Celeste", Top = "Hielo", Swirl = "Aurora-Verde", Spark = c(180, 230, 255) },
	Velo = { Frame = "Velo-Espectral", Tile = "Cuero-Azul", Tint = c(190, 160, 255), TileAlpha = 0.3, Fx = "niebla", Wing = "Sombra", Top = "Cuernos", Swirl = "Remolino-Vacio", Spark = c(200, 170, 255) },
	Hoja = { Frame = "Bambu-Hoja", Tile = "Bambu", Tint = c(190, 230, 170), TileAlpha = 0.4, Fx = "hojas", Wing = "Mariposa", Top = "Sakura", Swirl = "Aurora-Verde", Spark = c(190, 255, 160) },
	Saiyan = { Frame = "Ki-Saiyan", Tile = "Hierro", Tint = c(120, 130, 200), TileAlpha = 0.3, Fx = "ki", Wing = "Fuego", Top = "Llama", Swirl = "Remolino-Dorado", Spark = c(255, 226, 120) },
	Sakura = { Frame = "Sakura-Noble", Tile = "Pergamino", Tint = c(255, 205, 225), TileAlpha = 0.1, Fx = "petalos", Wing = "Mariposa", Top = "Sakura", Swirl = "Remolino-Rosa", Spark = c(255, 200, 225), Text = "dark" },
	Cosmos = { Frame = "Cosmos", Tile = "Galaxia-Fondo", Tint = W, TileAlpha = 0, Fx = "estrellas", Wing = "Cosmos", Top = "Estrellas", Swirl = "Remolino-Rosa", Spark = c(230, 210, 255) },
	Luna = { Frame = "Cosmos", Tile = "Galaxia-Fondo", Tint = c(190, 200, 255), TileAlpha = 0.1, Fx = "estrellas", Wing = "Celeste", Top = "Halo", Swirl = "Remolino-Vacio", Spark = c(220, 230, 255) },
	Aurora = { Frame = "Cosmos", Tile = "Galaxia-Fondo", Tint = c(160, 255, 220), TileAlpha = 0.2, Fx = "aurora", Wing = "Cristal-Arcoiris", Top = "Halo", Swirl = "Aurora-Verde", Spark = c(180, 255, 230) },
	Eclipse = { Frame = "Eclipse", Tile = "Lava", Tint = c(90, 60, 70), TileAlpha = 0.3, Fx = "eclipse", Wing = "Sombra", Top = "Halo", Swirl = "Remolino-Vacio", Spark = c(255, 210, 120) },
} :: { [string]: Look }

return M
