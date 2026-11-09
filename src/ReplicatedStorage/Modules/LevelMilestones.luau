--!strict
--[[
    LevelMilestones (ModuleScript) -> ReplicatedStorage.Modules.LevelMilestones
    HITOS DE NIVEL: una recompensa cada STEP (50) niveles = 60 hitos hasta el 3000, más 5 AURAS que rodean al personaje.
      - Cada hito: oro (crece con el nivel). Cada 100 niveles: materiales de la franja. Cada 250: Pergamino de Protección.
      - Se reclaman a mano en la ventana "Hitos de nivel" (Ajustes) para no perderlos con la mochila llena.
      - AURAS: se desbloquean solas al llegar al nivel; el jugador elige una (o ninguna) y la ven todos. Solo estética.
      - Los TÍTULOS por nivel (uno cada 150) están en TitleCatalog y dan un bonus pequeño mientras estén equipados.
]]
local GB = require(script.Parent.GameBalance)
local LootTables = require(script.Parent.LootTables)

local M = {}

M.STEP = 50
M.COUNT = GB.MAX_LEVEL // M.STEP -- 60

export type Reward = { Gold: number, Mat: string?, MatCount: number, Scroll: number }

function M.LevelOf(index: number): number
	return index * M.STEP
end

function M.Strip(level: number): number
	return math.clamp(math.ceil(level / (GB.MAX_LEVEL / 4)), 1, 4)
end

function M.Reward(index: number): Reward
	local level = M.LevelOf(index)
	local gold = math.floor(LootTables.GoldBase * LootTables.GoldGrowth ^ (GB.Eq(level) - 1) * 400)
	local mat, matCount = nil, 0
	if level % 100 == 0 then
		mat = LootTables.StripMaterial[M.Strip(level)]
		matCount = 4 + M.Strip(level)
	end
	local scroll = 0
	if level % 250 == 0 then
		scroll = 1 + level // 1000
	end
	return { Gold = gold, Mat = mat, MatCount = matCount, Scroll = scroll }
end

export type Aura = { Id: string, Name: string, Desc: string, Need: number, Icon: string, Style: string, A: Color3, B: Color3, Faction: string? }

-- Style = receta en AuraSpecs (mismo Id). Faction = solo la pueden usar jugadores de esa facción.
M.Auras = {
	{ Id = "Brisa", Name = "Brisa Veloz", Desc = "Estelas de viento y destellos que te siguen.", Need = 100, Icon = "💨", Style = "Brisa", A = Color3.fromRGB(215, 240, 255), B = Color3.fromRGB(150, 205, 255) },
	{ Id = "Petalos", Name = "Lluvia de Pétalos", Desc = "Pétalos rosados caen a tu alrededor.", Need = 250, Icon = "🌸", Style = "Petalos", A = Color3.fromRGB(255, 190, 215), B = Color3.fromRGB(255, 130, 170) },
	{ Id = "Brillo", Name = "Brillo Etéreo", Desc = "Resplandor y destellos de luz que flotan.", Need = 500, Icon = "✨", Style = "Brillo", A = Color3.fromRGB(190, 225, 255), B = Color3.fromRGB(120, 170, 255) },
	{ Id = "Escarcha", Name = "Escarcha Eterna", Desc = "Copos, niebla helada y cristales de hielo.", Need = 750, Icon = "❄️", Style = "Escarcha", A = Color3.fromRGB(190, 235, 255), B = Color3.fromRGB(110, 190, 255) },
	{ Id = "Llama", Name = "Llama Carmesí", Desc = "Fuego vivo en todo tu cuerpo, con brasas y humo.", Need = 1000, Icon = "🔥", Style = "Llama", A = Color3.fromRGB(255, 190, 70), B = Color3.fromRGB(255, 70, 40) },
	{ Id = "Roca", Name = "Roca Ancestral", Desc = "Rocas y cristales giran a tu alrededor.", Need = 1250, Icon = "🪨", Style = "Roca", A = Color3.fromRGB(210, 170, 110), B = Color3.fromRGB(110, 150, 255) },
	{ Id = "Tormenta", Name = "Tormenta Eléctrica", Desc = "Rayos que recorren tu cuerpo y saltan a tu alrededor.", Need = 1500, Icon = "⚡", Style = "Tormenta", A = Color3.fromRGB(190, 240, 255), B = Color3.fromRGB(90, 150, 255) },
	{ Id = "KiDorado", Name = "Ki Dorado", Desc = "Pinchos de energía dorada y llamas altas. Solo Saiyan.", Need = 1500, Icon = "💥", Style = "KiDorado", A = Color3.fromRGB(255, 230, 110), B = Color3.fromRGB(255, 150, 30), Faction = "Saiyan" },
	{ Id = "Hojas", Name = "Torbellino de Hojas", Desc = "Hojas y remolinos de chakra. Solo Shinobi.", Need = 1500, Icon = "🍃", Style = "Hojas", A = Color3.fromRGB(150, 235, 130), B = Color3.fromRGB(70, 170, 90), Faction = "Shinobi" },
	{ Id = "Marea", Name = "Marea Pirata", Desc = "Olas, espuma y burbujas del mar. Solo Pirata.", Need = 1500, Icon = "🌊", Style = "Marea", A = Color3.fromRGB(120, 210, 255), B = Color3.fromRGB(50, 120, 230), Faction = "Pirate" },
	{ Id = "Espectral", Name = "Reiatsu Espectral", Desc = "Mariposas espirituales y niebla de reiatsu. Solo Shinigami.", Need = 1500, Icon = "🦋", Style = "Espectral", A = Color3.fromRGB(215, 200, 255), B = Color3.fromRGB(140, 120, 255), Faction = "Shinigami" },
	{ Id = "Cristal", Name = "Cristal Prismático", Desc = "Cristales y destellos que cambian de color.", Need = 1750, Icon = "💎", Style = "Cristal", A = Color3.fromRGB(255, 160, 220), B = Color3.fromRGB(150, 220, 255) },
	{ Id = "Vacio", Name = "Vacío Abisal", Desc = "Humo oscuro, ojos del vacío y runas.", Need = 2000, Icon = "🌑", Style = "Vacio", A = Color3.fromRGB(190, 90, 255), B = Color3.fromRGB(70, 30, 140) },
	{ Id = "Orbita", Name = "Órbita Celeste", Desc = "Esferas con estela y una galaxia a tus pies.", Need = 2250, Icon = "🪐", Style = "Orbita", A = Color3.fromRGB(220, 160, 255), B = Color3.fromRGB(110, 90, 255) },
	{ Id = "Cosmos", Name = "Cosmos Girante", Desc = "Galaxias que giran detrás de ti y sobre ti.", Need = 2500, Icon = "🌌", Style = "Cosmos", A = Color3.fromRGB(230, 170, 255), B = Color3.fromRGB(90, 140, 255) },
	{ Id = "Serafin", Name = "Alas del Serafín", Desc = "Alas de luz, halo sobre la cabeza y plumas que caen.", Need = 2750, Icon = "🕊️", Style = "Serafin", A = Color3.fromRGB(255, 245, 210), B = Color3.fromRGB(255, 220, 130) },
	{ Id = "Corona", Name = "Corona Imperial", Desc = "Pilar dorado, alas, galaxia y estrellas. Solo en el nivel máximo.", Need = 3000, Icon = "👑", Style = "Corona", A = Color3.fromRGB(255, 232, 130), B = Color3.fromRGB(255, 150, 40) },
} :: { Aura }

M.AuraById = {} :: { [string]: Aura }
for _, a in ipairs(M.Auras) do
	M.AuraById[a.Id] = a
end

return M
