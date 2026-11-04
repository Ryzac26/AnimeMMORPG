--!strict
--[[
    GuildCatalog (ModuleScript) -> ReplicatedStorage.Modules.GuildCatalog
    GREMIO DE FACCIÓN: todos los jugadores de una facción forman su gremio (automático). Aportan oro y materiales a las BENDICIONES
    (pasivas para TODA la facción). Subirlas es lento a propósito: cada bendición tiene 10 niveles, cada nivel pide muchos "puntos de aporte" (PA)
    y cada jugador tiene un límite diario de aporte (DailyCap). Todos los números para balancear están aquí; lo leen servidor y cliente.
      PA: 1 de oro = 1 PA · los materiales valen más que su precio de venta (ver Value) para que los recursos sirvan de algo.
]]
local GuildCatalog = {}

GuildCatalog.MAX_LEVEL = 10
-- PA para pasar del nivel n al n+1 (n = 0..9). Total por bendición ≈ 10,7 millones de PA.
GuildCatalog.LEVEL_COST = { 50000, 90000, 150000, 250000, 400000, 650000, 1000000, 1600000, 2500000, 4000000 } :: { number }

-- Límite de aporte por jugador y día (PA): crece con el nivel del jugador
function GuildCatalog.DailyCap(playerLevel: number): number
	return 5000 + 400 * math.max(1, math.floor(playerLevel))
end

-- Bendiciones. Effect = bono POR NIVEL (fracciones de GearService: Oro, Xp, Vida, Ataque, Defensa, Suerte)
GuildCatalog.Passives = {
	{ Id = "Fortuna", Name = "Fortuna", Icon = "💰", Desc = "Más oro de los monstruos", Stat = "Oro", PerLevel = 0.005, Color = Color3.fromRGB(255, 205, 80) },
	{ Id = "Sabiduria", Name = "Sabiduría", Icon = "📖", Desc = "Más experiencia", Stat = "Xp", PerLevel = 0.005, Color = Color3.fromRGB(120, 190, 255) },
	{ Id = "Vigor", Name = "Vigor", Icon = "❤", Desc = "Más vida máxima", Stat = "Vida", PerLevel = 0.005, Color = Color3.fromRGB(120, 220, 130) },
	{ Id = "Furia", Name = "Furia", Icon = "⚔", Desc = "Más daño", Stat = "Ataque", PerLevel = 0.004, Color = Color3.fromRGB(240, 100, 90) },
	{ Id = "Coraza", Name = "Coraza", Icon = "🛡", Desc = "Menos daño recibido", Stat = "Defensa", PerLevel = 0.003, Color = Color3.fromRGB(170, 170, 200) },
	{ Id = "Hallazgo", Name = "Hallazgo", Icon = "🔎", Desc = "Más suerte con el botín", Stat = "Suerte", PerLevel = 0.01, Color = Color3.fromRGB(200, 130, 255) },
} :: { { Id: string, Name: string, Icon: string, Desc: string, Stat: string, PerLevel: number, Color: Color3 } }

GuildCatalog.ById = {} :: { [string]: any }
for _, p in ipairs(GuildCatalog.Passives) do
	GuildCatalog.ById[p.Id] = p
end

-- Valor en PA de lo que se puede aportar (oro = 1 PA). Materiales: ~3x su precio de venta.
GuildCatalog.Value = {
	Mat_Piel = 18, Mat_Colmillo = 36, Mat_Esencia = 120, Mat_Nucleo = 360,
	Rec_1 = 24, Rec_2 = 60, Rec_3 = 150, Rec_4 = 330,
	Mat_Gema = 300,
} :: { [string]: number }
GuildCatalog.MaterialOrder = { "Rec_1", "Rec_2", "Rec_3", "Rec_4", "Mat_Piel", "Mat_Colmillo", "Mat_Esencia", "Mat_Nucleo", "Mat_Gema" }

GuildCatalog.LOG_MAX = 30
GuildCatalog.LOG_MIN_PA = 1000 -- aportes menores no se anotan en el registro
GuildCatalog.WEEK_SECONDS = 604800

function GuildCatalog.WeekId(now: number): number
	return math.floor(now / GuildCatalog.WEEK_SECONDS)
end

export type PassiveState = { L: number, P: number } -- nivel, progreso hacia el siguiente
export type State = {
	Passives: { [string]: PassiveState },
	Contrib: { [string]: { T: number, W: number, Wk: number, N: string } },
	Log: { { t: number, m: string } },
}

function GuildCatalog.NewState(): State
	local s: State = { Passives = {}, Contrib = {}, Log = {} }
	for _, p in ipairs(GuildCatalog.Passives) do
		s.Passives[p.Id] = { L = 0, P = 0 }
	end
	return s
end

-- Pasa datos externos (DataStore) a un estado completo y válido
function GuildCatalog.Sanitize(raw: any): State
	local s = GuildCatalog.NewState()
	if typeof(raw) ~= "table" then
		return s
	end
	if typeof(raw.Passives) == "table" then
		for id, v in pairs(raw.Passives) do
			if s.Passives[id] and typeof(v) == "table" and typeof(v.L) == "number" and typeof(v.P) == "number" then
				s.Passives[id] = { L = math.clamp(math.floor(v.L), 0, GuildCatalog.MAX_LEVEL), P = math.max(0, v.P) }
			end
		end
	end
	if typeof(raw.Contrib) == "table" then
		for uid, c in pairs(raw.Contrib) do
			if typeof(uid) == "string" and typeof(c) == "table" and typeof(c.T) == "number" then
				s.Contrib[uid] = { T = c.T, W = if typeof(c.W) == "number" then c.W else 0, Wk = if typeof(c.Wk) == "number" then c.Wk else 0, N = if typeof(c.N) == "string" then c.N else "?" }
			end
		end
	end
	if typeof(raw.Log) == "table" then
		for _, e in ipairs(raw.Log) do
			if typeof(e) == "table" and typeof(e.t) == "number" and typeof(e.m) == "string" then
				table.insert(s.Log, { t = e.t, m = e.m })
			end
		end
	end
	return s
end

local function addLog(s: State, now: number, text: string)
	table.insert(s.Log, { t = now, m = text })
	while #s.Log > GuildCatalog.LOG_MAX do
		table.remove(s.Log, 1)
	end
end

-- Suma `pa` a una bendición. Devuelve los niveles que subió (lista de textos) y los PA realmente usados (en el nivel máximo no cabe más).
function GuildCatalog.AddProgress(s: State, passiveId: string, pa: number, now: number): ({ string }, number)
	local ps = s.Passives[passiveId]
	local def = GuildCatalog.ById[passiveId]
	local events: { string } = {}
	if not ps or not def or pa <= 0 or ps.L >= GuildCatalog.MAX_LEVEL then
		return events, 0
	end
	ps.P += pa
	while ps.L < GuildCatalog.MAX_LEVEL and ps.P >= GuildCatalog.LEVEL_COST[ps.L + 1] do
		ps.P -= GuildCatalog.LEVEL_COST[ps.L + 1]
		ps.L += 1
		local txt = string.format("★ ¡%s subió al nivel %d!", def.Name, ps.L)
		table.insert(events, txt)
		addLog(s, now, txt)
	end
	if ps.L >= GuildCatalog.MAX_LEVEL then
		ps.P = 0
	end
	return events, pa
end

-- Aplica un lote de aportes pendientes (lo hace el servidor dentro de UpdateAsync y también de forma optimista en la caché)
export type Delta = {
	Pass: { [string]: number },
	Contrib: { [string]: { PA: number, Name: string } },
	Log: { { t: number, m: string } },
}
function GuildCatalog.NewDelta(): Delta
	return { Pass = {}, Contrib = {}, Log = {} }
end

function GuildCatalog.ApplyDelta(s: State, d: Delta, now: number): { string }
	local events: { string } = {}
	for id, pa in pairs(d.Pass) do
		local ev = GuildCatalog.AddProgress(s, id, pa, now)
		for _, e in ipairs(ev) do
			table.insert(events, e)
		end
	end
	local wk = GuildCatalog.WeekId(now)
	for uid, c in pairs(d.Contrib) do
		local e = s.Contrib[uid]
		if not e then
			e = { T = 0, W = 0, Wk = wk, N = c.Name }
			s.Contrib[uid] = e
		end
		if e.Wk ~= wk then
			e.W, e.Wk = 0, wk
		end
		e.T += c.PA
		e.W += c.PA
		e.N = c.Name
	end
	for _, l in ipairs(d.Log) do
		addLog(s, l.t, l.m)
	end
	-- solo se guardan los 200 mayores aportantes (el resto es ruido)
	local n = 0
	for _ in pairs(s.Contrib) do
		n += 1
	end
	if n > 200 then
		local list: { { string | number } } = {}
		for uid, e in pairs(s.Contrib) do
			table.insert(list, { uid, e.T })
		end
		table.sort(list, function(a, b)
			return (a[2] :: number) > (b[2] :: number)
		end)
		for i = 201, #list do
			s.Contrib[list[i][1] :: string] = nil
		end
	end
	return events
end

-- Bonos totales de las bendiciones para GearService
function GuildCatalog.StatsFor(s: State): { [string]: number }
	local out: { [string]: number } = {}
	for _, p in ipairs(GuildCatalog.Passives) do
		local ps = s.Passives[p.Id]
		if ps and ps.L > 0 then
			out[p.Stat] = (out[p.Stat] or 0) + p.PerLevel * ps.L
		end
	end
	return out
end

-- Ranking: lista ordenada { Uid, Name, Total, Week }. weekly=true ordena por la semana actual.
function GuildCatalog.Ranking(s: State, weekly: boolean, now: number, limit: number): { { Uid: string, Name: string, Total: number, Week: number } }
	local wk = GuildCatalog.WeekId(now)
	local list: { { Uid: string, Name: string, Total: number, Week: number } } = {}
	for uid, e in pairs(s.Contrib) do
		table.insert(list, { Uid = uid, Name = e.N, Total = e.T, Week = if e.Wk == wk then e.W else 0 })
	end
	table.sort(list, function(a, b)
		local av = if weekly then a.Week else a.Total
		local bv = if weekly then b.Week else b.Total
		if av ~= bv then
			return av > bv
		end
		return a.Uid < b.Uid
	end)
	local out = {}
	for i = 1, math.min(limit, #list) do
		if not weekly or list[i].Week > 0 then
			table.insert(out, list[i])
		end
	end
	return out
end

return GuildCatalog
