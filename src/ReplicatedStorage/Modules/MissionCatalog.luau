--!strict
--[[
    MissionCatalog (ModuleScript) -> ReplicatedStorage.Modules.MissionCatalog
    MISIONES DEL PABELLÓN (NPC del Pabellón VIP de cada ciudad). Iguales para jugadores gratis y VIP.
      - 3 misiones DIARIAS (cambian cada día UTC, las mismas para todos) y 2 SEMANALES (cambian cada semana).
      - Al completar se reclama la recompensa (oro según tu nivel) y se cuenta 1 misión completada.
      - MARCOS DE PERFIL: se desbloquean por misiones completadas (Frames). Se equipan en el NPC y se ven en tu retrato.
    Tipos: Kill (monstruos) · Metin (piedras Metin) · Boss (jefe mundial) · Donate (PA al Gremio) · Online (minutos) · Enhance (mejoras exitosas).
]]
local GB = require(script.Parent.GameBalance)
local MissionCatalog = {}

export type Def = { Id: string, Type: string, Goal: number, Text: string, GoldBase: number, GoldPerLevel: number, Tier: string, MinLevel: number }

-- DIFICULTADES: Facil · Normal · Dificil · Epica. Cada día sale 1 de cada dificultad (las que tu nivel permite); cada semana 1 Difícil + 1 Épica.
MissionCatalog.Tiers = {
	Facil = { Name = "Fácil", Color = Color3.fromRGB(120, 220, 130), Gold = 1 },
	Normal = { Name = "Normal", Color = Color3.fromRGB(110, 190, 255), Gold = 1.6 },
	Dificil = { Name = "Difícil", Color = Color3.fromRGB(255, 170, 70), Gold = 2.6 },
	Epica = { Name = "Épica", Color = Color3.fromRGB(215, 110, 255), Gold = 4.5 },
} :: { [string]: { Name: string, Color: Color3, Gold: number } }

local function d(id: string, ty: string, goal: number, text: string, tier: string, minLevel: number, base: number, per: number): Def
	return { Id = id, Type = ty, Goal = goal, Text = text, GoldBase = base, GoldPerLevel = per, Tier = tier, MinLevel = minLevel }
end

MissionCatalog.DailyPool = {
	-- Fácil (todos los niveles)
	d("d_f_kill", "Kill", 60, "Derrota 60 monstruos", "Facil", 1, 1500, 110),
	d("d_f_online", "Online", 20, "Juega 20 minutos", "Facil", 1, 1500, 110),
	d("d_f_metin", "Metin", 1, "Destruye 1 piedra Metin", "Facil", 1, 1800, 130),
	d("d_f_donate", "Donate", 2000, "Aporta 2.000 PA al Gremio", "Facil", 1, 1600, 120),
	-- Normal
	d("d_n_kill", "Kill", 150, "Derrota 150 monstruos", "Normal", 1, 2200, 160),
	d("d_n_metin", "Metin", 3, "Destruye 3 piedras Metin", "Normal", 1, 2600, 190),
	d("d_n_donate", "Donate", 5000, "Aporta 5.000 PA al Gremio", "Normal", 1, 2300, 170),
	d("d_n_enhance", "Enhance", 2, "Mejora con éxito 2 veces (hasta +5) en el Herrero", "Normal", 5, 2800, 200),
	-- Difícil
	d("d_d_kill", "Kill", 400, "Derrota 400 monstruos", "Dificil", 10, 3500, 260),
	d("d_d_metin", "Metin", 6, "Destruye 6 piedras Metin", "Dificil", 10, 3800, 280),
	d("d_d_online", "Online", 60, "Juega 60 minutos", "Dificil", 10, 3200, 240),
	d("d_d_enhance", "Enhance", 4, "Mejora con éxito 4 veces en el Herrero", "Dificil", 15, 4000, 290),
	-- Épica
	d("d_e_kill", "Kill", 900, "Derrota 900 monstruos", "Epica", 20, 6500, 480),
	d("d_e_metin", "Metin", 12, "Destruye 12 piedras Metin", "Epica", 20, 7000, 500),
	d("d_e_donate", "Donate", 25000, "Aporta 25.000 PA al Gremio", "Epica", 20, 6800, 490),
} :: { Def }

MissionCatalog.WeeklyPool = {
	d("w_d_kill", "Kill", 1500, "Derrota 1.500 monstruos", "Dificil", 1, 14000, 1000),
	d("w_d_metin", "Metin", 15, "Destruye 15 piedras Metin", "Dificil", 1, 14000, 1000),
	d("w_d_donate", "Donate", 40000, "Aporta 40.000 PA al Gremio", "Dificil", 1, 15000, 1000),
	d("w_e_boss", "Boss", 1, "Participa en la caída del jefe mundial", "Epica", 1, 22000, 1500),
	d("w_e_kill", "Kill", 4000, "Derrota 4.000 monstruos", "Epica", 20, 26000, 1800),
	d("w_e_metin", "Metin", 40, "Destruye 40 piedras Metin", "Epica", 20, 26000, 1800),
} :: { Def }

MissionCatalog.ById = {} :: { [string]: Def }
for _, def in ipairs(MissionCatalog.DailyPool) do
	MissionCatalog.ById[def.Id] = def
end
for _, def in ipairs(MissionCatalog.WeeklyPool) do
	MissionCatalog.ById[def.Id] = def
end

MissionCatalog.DAILY_TIERS = { "Facil", "Normal", "Dificil", "Epica" }
MissionCatalog.WEEKLY_TIERS = { "Dificil", "Epica" }

-- la meta crece con tu nivel (por tramos, para que no cambie a cada subida)
function MissionCatalog.Scale(level: number): number
	if level < 50 then
		return 1
	elseif level < 200 then
		return 1.6
	elseif level < 600 then
		return 2.5
	elseif level < 1500 then
		return 4
	end
	return 6
end
function MissionCatalog.GoalFor(def: Def, level: number): number
	if def.Type == "Boss" then
		return def.Goal
	end
	local g = def.Goal * MissionCatalog.Scale(level)
	return math.max(1, math.floor(g / (if g >= 100 then 10 else 1) + 0.5) * (if g >= 100 then 10 else 1))
end

-- Elige las misiones del periodo según tu nivel: 1 por dificultad (las que tu nivel permite), de forma determinista por día/semana.
function MissionCatalog.Pick(pool: { Def }, tiers: { string }, index: number, level: number): { Def }
	local out: { Def } = {}
	for ti, tier in ipairs(tiers) do
		local opts: { Def } = {}
		for _, def in ipairs(pool) do
			if def.Tier == tier and def.MinLevel <= level then
				table.insert(opts, def)
			end
		end
		if #opts > 0 then
			local rng = Random.new(index * 7919 + ti * 131 + #pool)
			table.insert(out, opts[rng:NextInteger(1, #opts)])
		end
	end
	return out
end

-- el texto con la meta ya escalada ("Derrota 60 monstruos" -> "Derrota 96 monstruos")
function MissionCatalog.TextFor(def: Def, goal: number): string
	if goal == def.Goal then
		return def.Text
	end
	local function fmt(n: number): string
		local str = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1."):reverse()
		return (str:gsub("^%.", ""))
	end
	local out = def.Text:gsub("[%d%.]+", function(num: string)
		return if tonumber((num:gsub("%.", ""))) == def.Goal then fmt(goal) else num
	end)
	return out
end

function MissionCatalog.Gold(def: Def, level: number): number
	local tier = MissionCatalog.Tiers[def.Tier]
	return math.floor((def.GoldBase + def.GoldPerLevel * math.max(1, math.floor(GB.Eq(level)))) * (if tier then tier.Gold else 1) * (if def.Type == "Boss" then 1 else MissionCatalog.Scale(level) ^ 0.5))
end

-- Marcos de perfil: Need = misiones completadas en total
MissionCatalog.Frames = {
	{ Id = "Bronce", Name = "Marco de Bronce", Need = 5, Color = Color3.fromRGB(205, 127, 50) },
	{ Id = "Plata", Name = "Marco de Plata", Need = 20, Color = Color3.fromRGB(205, 212, 225) },
	{ Id = "Oro", Name = "Marco de Oro", Need = 50, Color = Color3.fromRGB(250, 200, 70) },
	{ Id = "Cristal", Name = "Marco de Cristal", Need = 100, Color = Color3.fromRGB(110, 225, 255) },
	{ Id = "Imperial", Name = "Marco Imperial", Need = 200, Color = Color3.fromRGB(195, 100, 255) },
} :: { { Id: string, Name: string, Need: number, Color: Color3, Passive: { Name: string, Text: string, Stats: { [string]: number } }? } }

-- Pasivas únicas de los marcos altos (solo mientras el marco está EQUIPADO; elegir uno es una decisión)
MissionCatalog.Frames[4].Passive = { Name = "Brillo de Cristal", Text = "+4% de suerte con el botín", Stats = { Suerte = 0.04 } }
MissionCatalog.Frames[5].Passive = { Name = "Sello Imperial", Text = "+4% de XP y +4% de oro", Stats = { Xp = 0.04, Oro = 0.04 } }

MissionCatalog.FrameById = {} :: { [string]: { Id: string, Name: string, Need: number, Color: Color3, Passive: { Name: string, Text: string, Stats: { [string]: number } }? } }
for _, f in ipairs(MissionCatalog.Frames) do
	MissionCatalog.FrameById[f.Id] = f
end

return MissionCatalog
