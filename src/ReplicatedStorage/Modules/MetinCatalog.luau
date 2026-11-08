--!strict
--[[
    MetinCatalog (ModuleScript) -> ReplicatedStorage.Modules.MetinCatalog
    DATOS puros de las PIEDRAS METIN (evento de la Arena Central). Sin lógica: para ajustar algo editas SOLO esta tabla.

    Cada rareza define:
      Name / Color        : cómo se ve y se llama.
      Weight              : probabilidad relativa de aparecer.
      Level               : nivel de la piedra y de los monstruos que invoca (±2).
      HpMult              : vida de la piedra = GameBalance.MobHp(Level) × HpMult.
      XpKills             : XP al destruirla = XP de N monstruos de su nivel (repartida según el daño de cada jugador).
      Pool                : franjas (1-4) de las que salen los monstruos de las oleadas (de las 4 naciones).
      Waves               : lista de oleadas. At = % de vida de la piedra al que se activa (1 = 100%), Count = monstruos,
                            Elite = true suma ADEMÁS un jefe de franja 4 a esa oleada.
    El botín (drop) NO está aquí todavía: se conectará al final con RewardService.MobKilled (mobId "Metin_<Id>").
]]
export type Wave = { At: number, Count: number, Elite: boolean? }
export type Rarity = {
	Id: string, Name: string, Color: Color3, Weight: number, Level: number, HpMult: number, XpKills: number,
	Pool: { number }, Waves: { Wave },
}

local MetinCatalog = {}

MetinCatalog.Rarities = {
	{
		Id = "Comun", Name = "Común", Color = Color3.fromRGB(200, 200, 210), Weight = 50, Level = 1650, HpMult = 30, XpKills = 6,
		Pool = { 3 },
		Waves = { { At = 0.70, Count = 3 }, { At = 0.35, Count = 3 } },
	},
	{
		Id = "PocoComun", Name = "Poco común", Color = Color3.fromRGB(90, 220, 120), Weight = 28, Level = 1950, HpMult = 45, XpKills = 10,
		Pool = { 3 },
		Waves = { { At = 0.75, Count = 4 }, { At = 0.50, Count = 4 }, { At = 0.25, Count = 4 } },
	},
	{
		Id = "Raro", Name = "Raro", Color = Color3.fromRGB(80, 160, 255), Weight = 14, Level = 2250, HpMult = 70, XpKills = 16,
		Pool = { 3, 4 },
		Waves = { { At = 0.80, Count = 5 }, { At = 0.60, Count = 5 }, { At = 0.40, Count = 5 }, { At = 0.20, Count = 5 } },
	},
	{
		Id = "Epico", Name = "Épico", Color = Color3.fromRGB(190, 90, 255), Weight = 6, Level = 2640, HpMult = 110, XpKills = 26,
		Pool = { 4 },
		Waves = {
			{ At = 0.80, Count = 6 }, { At = 0.65, Count = 6 }, { At = 0.50, Count = 6 }, { At = 0.35, Count = 6 },
			{ At = 0.20, Count = 6, Elite = true },
		},
	},
	{
		Id = "Legendario", Name = "Legendario", Color = Color3.fromRGB(255, 190, 50), Weight = 2, Level = 3000, HpMult = 180, XpKills = 45,
		Pool = { 4 },
		Waves = {
			{ At = 0.90, Count = 7 }, { At = 0.75, Count = 7 }, { At = 0.60, Count = 7 }, { At = 0.45, Count = 7 },
			{ At = 0.30, Count = 7, Elite = true }, { At = 0.15, Count = 8, Elite = true },
		},
	},
} :: { Rarity }

MetinCatalog.ById = {} :: { [string]: Rarity }
for _, r in ipairs(MetinCatalog.Rarities) do
	MetinCatalog.ById[r.Id] = r
end

-- Ajustes generales del evento
MetinCatalog.Settings = {
	StonesAtOnce = 4, -- piedras vivas a la vez mientras la Arena está abierta (máx. 8: hay 8 puntos)
	RespawnDelay = 45, -- segundos para que aparezca una nueva cuando destruyen una
	WaveRadiusMin = 14, -- los monstruos de cada oleada aparecen en un anillo alrededor de la piedra
	WaveRadiusMax = 24,
	LevelSpread = 60, -- nivel de los monstruos = nivel de la piedra ± esto (antes 2 niveles viejos)
	EliteLevelBonus = 0,
}

-- Sorteo de rareza según Weight
function MetinCatalog.Roll(): Rarity
	local total = 0
	for _, r in ipairs(MetinCatalog.Rarities) do
		total += r.Weight
	end
	local x = math.random() * total
	for _, r in ipairs(MetinCatalog.Rarities) do
		x -= r.Weight
		if x <= 0 then
			return r
		end
	end
	return MetinCatalog.Rarities[1]
end

return MetinCatalog
