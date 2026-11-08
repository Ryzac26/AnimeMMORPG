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

export type Aura = { Id: string, Name: string, Desc: string, Need: number, Icon: string, Style: string, A: Color3, B: Color3 }

M.Auras = {
	{ Id = "Brillo", Name = "Brillo Etéreo", Desc = "Chispas de luz que suben suavemente.", Need = 500, Icon = "✨", Style = "brillo", A = Color3.fromRGB(190, 225, 255), B = Color3.fromRGB(120, 170, 255) },
	{ Id = "Llama", Name = "Llama Carmesí", Desc = "Llamas que envuelven tu cuerpo.", Need = 1000, Icon = "🔥", Style = "llama", A = Color3.fromRGB(255, 190, 70), B = Color3.fromRGB(255, 70, 40) },
	{ Id = "Tormenta", Name = "Tormenta Eléctrica", Desc = "Rayos que saltan a tu alrededor.", Need = 1500, Icon = "⚡", Style = "rayos", A = Color3.fromRGB(190, 240, 255), B = Color3.fromRGB(90, 150, 255) },
	{ Id = "Orbita", Name = "Órbita Celeste", Desc = "Esferas de luz giran alrededor de ti.", Need = 2250, Icon = "🌌", Style = "orbita", A = Color3.fromRGB(220, 160, 255), B = Color3.fromRGB(110, 90, 255) },
	{ Id = "Corona", Name = "Corona Imperial", Desc = "Pilar dorado, anillo de luz y chispas de oro. Solo en el nivel máximo.", Need = 3000, Icon = "👑", Style = "corona", A = Color3.fromRGB(255, 232, 130), B = Color3.fromRGB(255, 150, 40) },
} :: { Aura }

M.AuraById = {} :: { [string]: Aura }
for _, a in ipairs(M.Auras) do
	M.AuraById[a.Id] = a
end

return M
