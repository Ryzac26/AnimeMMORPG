--!strict
--[[
    MissionCatalog (ModuleScript) -> ReplicatedStorage.Modules.MissionCatalog
    MISIONES DEL PABELLÓN (NPC del Pabellón VIP de cada ciudad). Iguales para jugadores gratis y VIP.
      - 3 misiones DIARIAS (cambian cada día UTC, las mismas para todos) y 2 SEMANALES (cambian cada semana).
      - Al completar se reclama la recompensa (oro según tu nivel) y se cuenta 1 misión completada.
      - MARCOS DE PERFIL: se desbloquean por misiones completadas (Frames). Se equipan en el NPC y se ven en tu retrato.
    Tipos: Kill (monstruos) · Metin (piedras Metin) · Boss (jefe mundial) · Donate (PA al Gremio) · Online (minutos) · Enhance (mejoras exitosas).
]]
local MissionCatalog = {}

export type Def = { Id: string, Type: string, Goal: number, Text: string, GoldBase: number, GoldPerLevel: number }

MissionCatalog.DailyPool = {
	{ Id = "d_kill_a", Type = "Kill", Goal = 120, Text = "Derrota 120 monstruos", GoldBase = 2000, GoldPerLevel = 150 },
	{ Id = "d_kill_b", Type = "Kill", Goal = 250, Text = "Derrota 250 monstruos", GoldBase = 3500, GoldPerLevel = 250 },
	{ Id = "d_metin", Type = "Metin", Goal = 3, Text = "Destruye 3 piedras Metin", GoldBase = 3000, GoldPerLevel = 220 },
	{ Id = "d_donate", Type = "Donate", Goal = 5000, Text = "Aporta 5.000 PA al Gremio", GoldBase = 2500, GoldPerLevel = 180 },
	{ Id = "d_online", Type = "Online", Goal = 30, Text = "Juega 30 minutos", GoldBase = 2000, GoldPerLevel = 150 },
	{ Id = "d_enhance", Type = "Enhance", Goal = 2, Text = "Mejora con éxito 2 veces en el Herrero", GoldBase = 3000, GoldPerLevel = 200 },
} :: { Def }

MissionCatalog.WeeklyPool = {
	{ Id = "w_kill", Type = "Kill", Goal = 1500, Text = "Derrota 1.500 monstruos", GoldBase = 14000, GoldPerLevel = 1000 },
	{ Id = "w_boss", Type = "Boss", Goal = 1, Text = "Participa en la caída del jefe mundial", GoldBase = 16000, GoldPerLevel = 1100 },
	{ Id = "w_metin", Type = "Metin", Goal = 15, Text = "Destruye 15 piedras Metin", GoldBase = 14000, GoldPerLevel = 1000 },
	{ Id = "w_donate", Type = "Donate", Goal = 40000, Text = "Aporta 40.000 PA al Gremio", GoldBase = 15000, GoldPerLevel = 1000 },
} :: { Def }

MissionCatalog.ById = {} :: { [string]: Def }
for _, d in ipairs(MissionCatalog.DailyPool) do
	MissionCatalog.ById[d.Id] = d
end
for _, d in ipairs(MissionCatalog.WeeklyPool) do
	MissionCatalog.ById[d.Id] = d
end

-- cuántas de cada tipo se eligen
MissionCatalog.DAILY_COUNT = 3
MissionCatalog.WEEKLY_COUNT = 2

-- Elige las misiones del periodo (mismas para todos): `index` = día o semana. Mezcla determinista.
function MissionCatalog.Pick(pool: { Def }, count: number, index: number): { Def }
	local rng = Random.new(index * 7919 + #pool)
	local copy = table.clone(pool)
	local out: { Def } = {}
	while #out < count and #copy > 0 do
		table.insert(out, table.remove(copy, rng:NextInteger(1, #copy)))
	end
	return out
end

function MissionCatalog.Gold(def: Def, level: number): number
	return def.GoldBase + def.GoldPerLevel * math.max(1, math.floor(level))
end

-- Marcos de perfil: Need = misiones completadas en total
MissionCatalog.Frames = {
	{ Id = "Bronce", Name = "Marco de Bronce", Need = 5, Color = Color3.fromRGB(205, 127, 50) },
	{ Id = "Plata", Name = "Marco de Plata", Need = 20, Color = Color3.fromRGB(205, 212, 225) },
	{ Id = "Oro", Name = "Marco de Oro", Need = 50, Color = Color3.fromRGB(250, 200, 70) },
	{ Id = "Cristal", Name = "Marco de Cristal", Need = 100, Color = Color3.fromRGB(110, 225, 255) },
	{ Id = "Imperial", Name = "Marco Imperial", Need = 200, Color = Color3.fromRGB(195, 100, 255) },
} :: { { Id: string, Name: string, Need: number, Color: Color3 } }

MissionCatalog.FrameById = {} :: { [string]: { Id: string, Name: string, Need: number, Color: Color3 } }
for _, f in ipairs(MissionCatalog.Frames) do
	MissionCatalog.FrameById[f.Id] = f
end

return MissionCatalog
