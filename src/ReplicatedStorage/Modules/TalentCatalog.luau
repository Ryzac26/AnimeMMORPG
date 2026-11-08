--!strict
--[[
    TalentCatalog (ModuleScript) -> ReplicatedStorage.Modules.TalentCatalog
    ÁRBOL DE TALENTOS. Datos puros: TalentService valida y aplica, TalentClient dibuja la ventana.
      PUNTOS      : 1 cada 10 niveles + 4 extra en cada nivel múltiplo de 250 (3000 niveles = 348 puntos). Un árbol completo cuesta
                    mucho más (~590), así que hay que ELEGIR.
      RAMAS       : Defensa (tanque) · Ofensiva (daño) · Soporte · Utilidad  (para todos) + ASCENDENCIA (exclusiva de la facción, nivel 1500).
      TIERS       : 1 = nivel 50 · 2 = nivel 250 y 10 pts en la rama · 3 = nivel 1000 y 30 pts en la rama · CLAVE = nivel 1000 y 40 pts.
      RANGOS      : cada talento sube 1..5; el rango r cuesta RANK_COST[r] puntos (1,1,2,3,5 = 12 en total).
      CLAVES      : un solo rango (15 pts) que cambia las reglas: da mucho pero cuesta algo. Máximo MAX_KEYSTONES activas a la vez.
      Stats       : { Ataque, Defensa, Vida, Critico, CritDmg, Curacion, Suerte, Oro, Xp, Regen } (fracciones por rango) -> GearService.SetTemp.
      Aura        : mismos stats, pero se aplican también a los aliados del grupo cercanos (el mejor de cada stat, no se suman entre soportes).
      TOPES       : TalentCatalog.Caps limita el total de cada stat (los talentos no rompen el balance del equipo).
      Pestañas    : SLOTS = 3 builds. La 1 es gratis; la 2 y la 3 vienen con los pases "Talentos II/III" (ProductCatalog.Passes).
]]
local T = {}

T.MAX_RANK = 5
T.RANK_COST = { 1, 1, 2, 3, 5 }
T.KEYSTONE_COST = 15
T.MAX_KEYSTONES = 2
T.AURA_RANGE = 60 -- studs
T.SLOTS = 3
T.SLOT_PASS = { [1] = "", [2] = "Pass_Talents2", [3] = "Pass_Talents3" } :: { [number]: string }
T.FREE_RESPECS = 1 -- por build
T.ASCENDENCIA_LEVEL = 1500
T.TierLevel = { 50, 250, 1000 } :: { number }
T.TierSpent = { 0, 10, 30 } :: { number }
T.KEY_LEVEL, T.KEY_SPENT, T.ASC_KEY_SPENT = 1000, 40, 30

T.Caps = { Ataque = 0.45, Defensa = 0.15, Vida = 0.60, Critico = 0.20, CritDmg = 0.50, Curacion = 0.50, Suerte = 0.30, Oro = 0.40, Xp = 0.30, Regen = 0.03 } :: { [string]: number }
T.StatName = { Ataque = "ataque", Defensa = "defensa", Vida = "vida", Critico = "crítico", CritDmg = "daño crítico", Curacion = "curación", Suerte = "suerte", Oro = "oro", Xp = "XP", Regen = "regeneración" } :: { [string]: string }

export type Node = {
	Id: string, Branch: string, Tier: number, Name: string, Icon: string, Desc: string,
	Stats: { [string]: number }?, Aura: { [string]: number }?, Key: boolean?, Faction: string?, Col: number, Row: number,
}

T.Branches = {
	{ Id = "Defensa", Name = "Defensa", Icon = "🛡", Role = "Tanque", Desc = "Aguanta por el grupo: vida, defensa y auras que protegen a los aliados.", Color = Color3.fromRGB(90, 160, 255) },
	{ Id = "Ofensiva", Name = "Ofensiva", Icon = "⚔", Role = "Daño", Desc = "Más daño y críticos. El camino de los que quieren caer enemigos rápido.", Color = Color3.fromRGB(255, 90, 80) },
	{ Id = "Soporte", Name = "Soporte", Icon = "💚", Role = "Soporte", Desc = "Curación y auras que mejoran a todo el grupo cercano.", Color = Color3.fromRGB(100, 220, 140) },
	{ Id = "Utilidad", Name = "Utilidad", Icon = "🧭", Role = "Utilidad", Desc = "Oro, suerte y experiencia: progresa y gana más por hora.", Color = Color3.fromRGB(255, 205, 90) },
	{ Id = "Ascendencia", Name = "Ascendencia", Icon = "🌟", Role = "Facción", Desc = "Talentos exclusivos de tu facción. Se abren en el nivel 1500.", Color = Color3.fromRGB(200, 120, 255) },
} :: { { Id: string, Name: string, Icon: string, Role: string, Desc: string, Color: Color3 } }

T.List = {} :: { Node }
local function add(branch: string, tier: number, col: number, id: string, name: string, icon: string, desc: string, stats: { [string]: number }?, aura: { [string]: number }?, key: boolean?, faction: string?)
	table.insert(T.List, { Id = id, Branch = branch, Tier = tier, Name = name, Icon = icon, Desc = desc, Stats = stats, Aura = aura, Key = key, Faction = faction, Col = col, Row = if key then 4 else tier })
end

-- DEFENSA ------------------------------------------------------------------
add("Defensa", 1, 1, "d1", "Piel de Hierro", "🛡", "Reduce el daño que recibes.", { Defensa = 0.006 })
add("Defensa", 1, 2, "d2", "Corazón Robusto", "❤", "Más vida máxima.", { Vida = 0.03 })
add("Defensa", 1, 3, "d3", "Respiración Firme", "🌬", "Regeneras vida fuera de combate.", { Regen = 0.003 })
add("Defensa", 1, 4, "d4", "Voluntad de Roca", "🪨", "Un poco de defensa y de vida.", { Defensa = 0.004, Vida = 0.015 })
add("Defensa", 2, 1, "d5", "Guardia del Vínculo", "🤝", "Tú y tus aliados cercanos reciben menos daño.", nil, { Defensa = 0.008 })
add("Defensa", 2, 2, "d6", "Escudo Reactivo", "🔰", "Defensa y vida.", { Defensa = 0.006, Vida = 0.02 })
add("Defensa", 2, 3, "d7", "Provocador", "📢", "Mucha vida: es tu trabajo recibir los golpes.", { Vida = 0.035, Defensa = 0.003 })
add("Defensa", 2, 4, "d8", "Espinas", "🌵", "Defensa y algo de ataque.", { Defensa = 0.004, Ataque = 0.01 })
add("Defensa", 3, 1, "d9", "Fortaleza", "⛰", "Gran aumento de vida máxima.", { Vida = 0.05 })
add("Defensa", 3, 2, "d10", "Muro Viviente", "🏰", "Gran reducción de daño.", { Defensa = 0.008 })
add("Defensa", 3, 3, "d11", "Escudo de Sangre", "💠", "Regeneración y curación recibida.", { Regen = 0.004, Curacion = 0.02 })
add("Defensa", 4, 2, "dk", "Bastión Inamovible", "🏛", "CLAVE: +20% de vida y +8% de defensa, pero −15% de ataque.", { Vida = 0.20, Defensa = 0.08, Ataque = -0.15 }, nil, true)

-- OFENSIVA -----------------------------------------------------------------
add("Ofensiva", 1, 1, "o1", "Filo Afilado", "⚔", "Más daño.", { Ataque = 0.01 })
add("Ofensiva", 1, 2, "o2", "Ojo Certero", "🎯", "Más probabilidad de crítico.", { Critico = 0.008 })
add("Ofensiva", 1, 3, "o3", "Golpe Brutal", "💥", "Los críticos pegan más.", { CritDmg = 0.02 })
add("Ofensiva", 1, 4, "o4", "Instinto Cazador", "🐺", "Daño y crítico.", { Ataque = 0.006, Critico = 0.004 })
add("Ofensiva", 2, 1, "o5", "Sed de Batalla", "🔥", "Mucho más daño.", { Ataque = 0.012 })
add("Ofensiva", 2, 2, "o6", "Precisión Letal", "🗡", "Crítico y daño crítico.", { Critico = 0.01, CritDmg = 0.01 })
add("Ofensiva", 2, 3, "o7", "Rabia Creciente", "😡", "Daño y regeneración.", { Ataque = 0.008, Regen = 0.002 })
add("Ofensiva", 2, 4, "o8", "Cazarrecompensas", "💰", "Daño y oro.", { Oro = 0.015, Ataque = 0.005 })
add("Ofensiva", 3, 1, "o9", "Maestro del Combate", "🥋", "Gran aumento de daño.", { Ataque = 0.014 })
add("Ofensiva", 3, 2, "o10", "Golpe Decisivo", "⚡", "Críticos devastadores.", { CritDmg = 0.04 })
add("Ofensiva", 3, 3, "o11", "Ejecutor", "☠", "Crítico y daño.", { Critico = 0.012, Ataque = 0.008 })
add("Ofensiva", 4, 2, "ok", "Furia Sangrienta", "🩸", "CLAVE: +22% de ataque y +25% de daño crítico, pero −12% de vida y −5% de defensa.", { Ataque = 0.22, CritDmg = 0.25, Vida = -0.12, Defensa = -0.05 }, nil, true)

-- SOPORTE ------------------------------------------------------------------
add("Soporte", 1, 1, "s1", "Manos Sanadoras", "🤲", "Tus curaciones y escudos valen más.", { Curacion = 0.02 })
add("Soporte", 1, 2, "s2", "Aliento Vital", "🌿", "Regeneración fuera de combate.", { Regen = 0.003 })
add("Soporte", 1, 3, "s3", "Mente Serena", "🧘", "Vida y curación.", { Vida = 0.02, Curacion = 0.01 })
add("Soporte", 1, 4, "s4", "Bendición Menor", "✨", "Tú y tu grupo cercano ganan más XP.", nil, { Xp = 0.004 })
add("Soporte", 2, 1, "s5", "Aura de Vigor", "💚", "Tú y tus aliados cercanos regeneran vida.", nil, { Regen = 0.002 })
add("Soporte", 2, 2, "s6", "Inspiración", "🎶", "Tú y tus aliados cercanos hacen más daño.", nil, { Ataque = 0.006 })
add("Soporte", 2, 3, "s7", "Escudo Compartido", "🫧", "Tú y tus aliados cercanos reciben menos daño.", nil, { Defensa = 0.005 })
add("Soporte", 2, 4, "s8", "Medicina Potente", "💊", "Mucha más curación.", { Curacion = 0.03 })
add("Soporte", 3, 1, "s9", "Gran Sanación", "🌟", "Curación enorme.", { Curacion = 0.04 })
add("Soporte", 3, 2, "s10", "Coro de Batalla", "📯", "Aura de daño y XP para el grupo.", nil, { Ataque = 0.008, Xp = 0.004 })
add("Soporte", 3, 3, "s11", "Guardián Eterno", "🕊", "Vida y curación.", { Vida = 0.04, Curacion = 0.02 })
add("Soporte", 4, 2, "sk", "Pacto Vital", "💞", "CLAVE: +30% de curación y +8% de XP para tu grupo cercano, pero −10% de ataque.", { Curacion = 0.30, Ataque = -0.10 }, { Xp = 0.08 }, true)

-- UTILIDAD -----------------------------------------------------------------
add("Utilidad", 1, 1, "u1", "Buscador de Tesoros", "🪙", "Más oro.", { Oro = 0.015 })
add("Utilidad", 1, 2, "u2", "Suerte del Viajero", "🍀", "Mejor botín.", { Suerte = 0.012 })
add("Utilidad", 1, 3, "u3", "Aprendiz Veloz", "📘", "Más XP.", { Xp = 0.01 })
add("Utilidad", 1, 4, "u4", "Cuerpo Ágil", "🏃", "Un poco más de vida.", { Vida = 0.02 })
add("Utilidad", 2, 1, "u5", "Saqueador", "💎", "Mucho más oro.", { Oro = 0.02 })
add("Utilidad", 2, 2, "u6", "Fortuna", "🎲", "Mucha más suerte.", { Suerte = 0.018 })
add("Utilidad", 2, 3, "u7", "Sabiduría", "🦉", "Mucha más XP.", { Xp = 0.014 })
add("Utilidad", 2, 4, "u8", "Todoterreno", "🧭", "Un poco de todo.", { Ataque = 0.006, Defensa = 0.003, Vida = 0.01 })
add("Utilidad", 3, 1, "u9", "Rey de la Colina", "👑", "Oro y XP.", { Oro = 0.025, Xp = 0.01 })
add("Utilidad", 3, 2, "u10", "Bendición del Azar", "🔮", "Suerte enorme.", { Suerte = 0.025 })
add("Utilidad", 3, 3, "u11", "Maestro Estratega", "📜", "XP enorme.", { Xp = 0.02 })
add("Utilidad", 4, 2, "uk", "Fortuna Imperial", "🌠", "CLAVE: +15% de oro y suerte y +10% de XP, pero −8% de vida.", { Oro = 0.15, Suerte = 0.15, Xp = 0.10, Vida = -0.08 }, nil, true)

-- ASCENDENCIA (por facción) --------------------------------------------------
local function asc(f: string, p: string, names: { { string } }, stats: { { [string]: number } }, key: { Name: string, Icon: string, Desc: string, Stats: { [string]: number } })
	for i, n in ipairs(names) do
		add("Ascendencia", 1, i, p .. i, n[1], n[2], n[3], stats[i], nil, nil, f)
	end
	add("Ascendencia", 4, 2, p .. "k", key.Name, key.Icon, key.Desc, key.Stats, nil, true, f)
end
asc("Saiyan", "as", {
	{ "Sangre de Guerrero", "🩸", "Más daño." }, { "Ki Desbordante", "🔆", "Más vida." }, { "Orgullo Saiyan", "🦁", "Críticos más fuertes." }, { "Instinto Superior", "👁", "Crítico y defensa." },
}, { { Ataque = 0.01 }, { Vida = 0.03 }, { CritDmg = 0.03 }, { Critico = 0.01, Defensa = 0.004 } },
{ Name = "Zenkai", Icon = "⭐", Desc = "CLAVE: +12% de ataque, +0,8% de regeneración y +5% de vida.", Stats = { Ataque = 0.12, Regen = 0.008, Vida = 0.05 } })
asc("Shinobi", "an", {
	{ "Chakra Profundo", "🌀", "Más vida." }, { "Sigilo", "🌫", "Más crítico." }, { "Sabiduría Ninja", "📜", "Más XP." }, { "Reflejos", "⚡", "Defensa y daño." },
}, { { Vida = 0.03 }, { Critico = 0.012 }, { Xp = 0.012 }, { Defensa = 0.004, Ataque = 0.006 } },
{ Name = "Senjutsu", Icon = "🐸", Desc = "CLAVE: +12% de crítico y +20% de daño crítico, pero −3% de defensa.", Stats = { Critico = 0.12, CritDmg = 0.20, Defensa = -0.03 } })
asc("Pirate", "ap", {
	{ "Ambición", "💰", "Más oro." }, { "Voluntad Férrea", "💪", "Más vida." }, { "Haki del Rey", "👑", "Daño y defensa." }, { "Ruta Afortunada", "🧭", "Más suerte." },
}, { { Oro = 0.02 }, { Vida = 0.03 }, { Ataque = 0.01, Defensa = 0.003 }, { Suerte = 0.015 } },
{ Name = "Yonkō", Icon = "⚓", Desc = "CLAVE: +15% de oro, +12% de suerte y +8% de ataque.", Stats = { Oro = 0.15, Suerte = 0.12, Ataque = 0.08 } })
asc("Shinigami", "ag", {
	{ "Reiatsu Elevado", "💠", "Más daño." }, { "Alma Pura", "🦋", "Curación y vida." }, { "Zanpakutō Despierto", "🗡", "Crítico y daño crítico." }, { "Shunpo Perfecto", "💨", "Defensa y regeneración." },
}, { { Ataque = 0.01 }, { Curacion = 0.02, Vida = 0.015 }, { Critico = 0.01, CritDmg = 0.02 }, { Defensa = 0.005, Regen = 0.002 } },
{ Name = "Bankai Perfecto", Icon = "🌑", Desc = "CLAVE: +12% de ataque, +5% de defensa y +0,8% de regeneración.", Stats = { Ataque = 0.12, Defensa = 0.05, Regen = 0.008 } })

T.ById = {} :: { [string]: Node }
for _, n in ipairs(T.List) do
	T.ById[n.Id] = n
end

-- PUNTOS TOTALES según el nivel (1 por cada 10 niveles + 4 por cada 250)
function T.PointsFor(level: number): number
	level = math.max(0, math.floor(level))
	return level // 10 + 4 * (level // 250)
end

function T.CostOf(node: Node, rank: number): number
	if node.Key then
		return T.KEYSTONE_COST
	end
	return T.RANK_COST[rank] or 0
end

function T.MaxRankOf(node: Node): number
	return if node.Key then 1 else T.MAX_RANK
end

-- Costo total acumulado para tener `rank` rangos
function T.TotalCost(node: Node, rank: number): number
	local sum = 0
	for r = 1, rank do
		sum += T.CostOf(node, r)
	end
	return sum
end

-- ¿Puede comprarse el siguiente rango? -> ok, motivo
function T.Requirement(node: Node, level: number, spentInBranch: number): (boolean, string?)
	if node.Branch == "Ascendencia" then
		if level < T.ASCENDENCIA_LEVEL then
			return false, string.format("Se abre en el nivel %d", T.ASCENDENCIA_LEVEL)
		end
		if node.Key and spentInBranch < T.ASC_KEY_SPENT then
			return false, string.format("Gasta %d puntos en Ascendencia", T.ASC_KEY_SPENT)
		end
		return true, nil
	end
	if node.Key then
		if level < T.KEY_LEVEL then
			return false, string.format("Nivel %d", T.KEY_LEVEL)
		end
		if spentInBranch < T.KEY_SPENT then
			return false, string.format("Gasta %d puntos en la rama", T.KEY_SPENT)
		end
		return true, nil
	end
	local tl = T.TierLevel[node.Tier]
	if level < tl then
		return false, string.format("Nivel %d", tl)
	end
	if spentInBranch < T.TierSpent[node.Tier] then
		return false, string.format("Gasta %d puntos en la rama", T.TierSpent[node.Tier])
	end
	return true, nil
end

-- Suma las stats de una build { [nodeId] = rango } -> stats, aura (con topes)
function T.Evaluate(ranks: { [string]: number }): ({ [string]: number }, { [string]: number })
	local stats: { [string]: number } = {}
	local aura: { [string]: number } = {}
	for id, r in pairs(ranks) do
		local n = T.ById[id]
		if n and r > 0 then
			for st, v in pairs(n.Stats or {}) do
				stats[st] = (stats[st] or 0) + v * r
			end
			for st, v in pairs(n.Aura or {}) do
				aura[st] = (aura[st] or 0) + v * r
			end
		end
	end
	for st, v in pairs(stats) do
		local cap = T.Caps[st]
		if cap and v > cap then
			stats[st] = cap
		end
	end
	for st, v in pairs(aura) do
		local cap = (T.Caps[st] or 0.2) * 0.5 -- el aura vale como máximo la mitad del tope personal
		if v > cap then
			aura[st] = cap
		end
	end
	return stats, aura
end

return T
