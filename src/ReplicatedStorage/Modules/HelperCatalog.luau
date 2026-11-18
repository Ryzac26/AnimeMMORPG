--!strict
--[[
    HelperCatalog (ModuleScript) -> ReplicatedStorage.Modules.HelperCatalog
    AYUDANTES DE COMBATE (reemplazan a las mascotas). Todo el sistema se rebalancea desde AQUÍ:
      - 4 facciones x 6 roles = 24 personajes (nombre y aspecto propios) x 5 rarezas.
      - CUPONES de reclutamiento (5 rarezas): cada cupón tiene su tabla de probabilidades en % (Légendario y Mítico, difíciles: estilo +8/+9 de la forja).
      - 3 ranuras: la 1 es gratis; la 2 y la 3 las da el pase (atributo Pass_PetSlot, el mismo pase de antes). Todas desde nivel 1.
      - Efectos pasivos al dueño (mismas claves que GearService: Ataque, Defensa, Vida, Critico, Curacion, Energia) + un poder de combate por rol (PvE).
      - XP: cada ayudante equipado recibe el 10% de la XP que ganas (extra: NO te la descuenta). Nivel máximo = tu nivel.
    Id de un ayudante: "<Facción>|<Rol>|<Rareza>"  (ej. "Saiyan|Tanque|Epico"). Una copia repetida sube sus estrellas (máx. 5); después da Esencia.
    PROGRESO: rangos por nivel (12 hitos, +3,5% a sus bonos cada uno y un aspecto nuevo), ramas de poder (nv. 100/500/1500), ascensión con Esencia
    (nv. 100/500/1500), vínculo de facción (nv. 100/1000), regalos por rango y personalización (apodo y color de aura). Todo está al final de este archivo.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GB = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameBalance"))

local HelperCatalog = {}

---------------------------------------------------------------------
-- Básicos
---------------------------------------------------------------------
HelperCatalog.Rarities = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
HelperCatalog.RarityName = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" } :: { [string]: string }
HelperCatalog.RarityColor = {
	Comun = Color3.fromRGB(190, 195, 205),
	Raro = Color3.fromRGB(80, 160, 255),
	Epico = Color3.fromRGB(190, 100, 255),
	Legendario = Color3.fromRGB(255, 175, 40),
	Mitico = Color3.fromRGB(255, 85, 115),
} :: { [string]: Color3 }
HelperCatalog.RarityIndex = { Comun = 1, Raro = 2, Epico = 3, Legendario = 4, Mitico = 5 } :: { [string]: number }

HelperCatalog.Roles = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
HelperCatalog.RoleIcon = { Tanque = "🛡️", Guerrero = "⚔️", Asesino = "🗡️", Tirador = "🏹", Mago = "🔮", Curador = "✚" } :: { [string]: string }
HelperCatalog.RoleInfo = {
	Tanque = "Aguanta por ti: más Defensa y Vida. Poder «Muro»: te da un escudo cada cierto tiempo.",
	Guerrero = "Equilibrado: más Ataque y Vida. Poder «Golpe de apoyo»: ataca contigo al enemigo que golpeas.",
	Asesino = "Letal: Ataque y Crítico. Poder «Filo cazador»: golpe extra, más fuerte contra jefes.",
	Tirador = "A distancia: Ataque y Crítico. Poder «Disparo certero»: dispara al enemigo que golpeas.",
	Mago = "Arcano: Ataque y energía. Poder «Estallido»: daño en área alrededor del enemigo.",
	Curador = "Sanador: más Curación y Vida. Poder «Brisa sanadora»: te cura (y a tu grupo) cada cierto tiempo.",
} :: { [string]: string }

HelperCatalog.Factions = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
HelperCatalog.FactionName = { Saiyan = "Élite", Shinobi = "Sigilo", Pirate = "Navegantes", Shinigami = "Espíritu" } :: { [string]: string }

-- Personajes: nombre propio por facción y rol (todos originales)
HelperCatalog.Roster = {
	Saiyan = {
		Tanque = { Name = "Bruk", Title = "Bastión de Élite" }, Guerrero = { Name = "Varek", Title = "Lanza de Élite" },
		Asesino = { Name = "Zorin", Title = "Filo Rojo" }, Tirador = { Name = "Kyra", Title = "Ojo de Ki" },
		Mago = { Name = "Orun", Title = "Canalizador" }, Curador = { Name = "Mina", Title = "Chispa Vital" },
	},
	Shinobi = {
		Tanque = { Name = "Torao", Title = "Muro de Hoja" }, Guerrero = { Name = "Hiro", Title = "Hoja Firme" },
		Asesino = { Name = "Kage", Title = "Sombra Corta" }, Tirador = { Name = "Shiba", Title = "Arco Mudo" },
		Mago = { Name = "Rensei", Title = "Sello Arcano" }, Curador = { Name = "Aoi", Title = "Loto Sereno" },
	},
	Pirate = {
		Tanque = { Name = "Rocamar", Title = "Ancla Viva" }, Guerrero = { Name = "Vento", Title = "Sable de Proa" },
		Asesino = { Name = "Nerea", Title = "Filo de Marea" }, Tirador = { Name = "Tuma", Title = "Mira de Bronce" },
		Mago = { Name = "Isa", Title = "Voz de Tormenta" }, Curador = { Name = "Coral", Title = "Savia de Cubierta" },
	},
	Shinigami = {
		Tanque = { Name = "Kuroha", Title = "Guardián Pálido" }, Guerrero = { Name = "Soren", Title = "Hoja Etérea" },
		Asesino = { Name = "Yami", Title = "Susurro" }, Tirador = { Name = "Rei", Title = "Flecha Pálida" },
		Mago = { Name = "Anzu", Title = "Voz de Almas" }, Curador = { Name = "Shion", Title = "Lámpara Espiritual" },
	},
} :: { [string]: { [string]: { Name: string, Title: string } } }

-- Aspecto por facción (HelperModel lo usa)
HelperCatalog.Look = {
	Saiyan = { Skin = Color3.fromRGB(240, 205, 175), Hair = Color3.fromRGB(30, 30, 40), Primary = Color3.fromRGB(235, 125, 35), Secondary = Color3.fromRGB(45, 85, 170), Accent = Color3.fromRGB(255, 215, 90), HairStyle = "Spiky" },
	Shinobi = { Skin = Color3.fromRGB(235, 200, 170), Hair = Color3.fromRGB(70, 45, 35), Primary = Color3.fromRGB(55, 95, 70), Secondary = Color3.fromRGB(35, 45, 80), Accent = Color3.fromRGB(210, 215, 225), HairStyle = "Band" },
	Pirate = { Skin = Color3.fromRGB(225, 180, 140), Hair = Color3.fromRGB(110, 60, 30), Primary = Color3.fromRGB(35, 70, 130), Secondary = Color3.fromRGB(235, 235, 235), Accent = Color3.fromRGB(230, 185, 70), HairStyle = "Bandana" },
	Shinigami = { Skin = Color3.fromRGB(235, 225, 225), Hair = Color3.fromRGB(235, 235, 245), Primary = Color3.fromRGB(28, 28, 38), Secondary = Color3.fromRGB(70, 55, 110), Accent = Color3.fromRGB(170, 120, 255), HairStyle = "Long" },
} :: { [string]: { Skin: Color3, Hair: Color3, Primary: Color3, Secondary: Color3, Accent: Color3, HairStyle: string } }

---------------------------------------------------------------------
-- Ranuras
---------------------------------------------------------------------
HelperCatalog.MaxSlots = 3
HelperCatalog.SlotNeedsPass = { false, true, true } :: { boolean } -- la 1 es gratis; la 2 y la 3 las abre el pase
HelperCatalog.SlotMinLevel = { 1, 1, 1 } :: { number } -- nivel mínimo de cada ranura (todas desde el 1)
HelperCatalog.PassAttr = "Pass_PetSlot" -- el mismo pase que antes era «Segunda Mascota»

function HelperCatalog.SlotOpen(slot: number, hasPass: boolean, level: number): boolean
	if slot < 1 or slot > HelperCatalog.MaxSlots then
		return false
	end
	if HelperCatalog.SlotNeedsPass[slot] and not hasPass then
		return false
	end
	return level >= (HelperCatalog.SlotMinLevel[slot] or 1)
end

---------------------------------------------------------------------
-- Ids
---------------------------------------------------------------------
function HelperCatalog.Id(faction: string, role: string, rarity: string): string
	return faction .. "|" .. role .. "|" .. rarity
end

export type Parsed = { Faction: string, Role: string, Rarity: string }
function HelperCatalog.Parse(id: any): Parsed?
	if typeof(id) ~= "string" then
		return nil
	end
	local f, r, q = string.match(id, "^([%a]+)|([%a]+)|([%a]+)$")
	if not f or not r or not q then
		return nil
	end
	if not HelperCatalog.Roster[f] or not HelperCatalog.Roster[f][r] or not HelperCatalog.RarityIndex[q] then
		return nil
	end
	return { Faction = f, Role = r, Rarity = q }
end

function HelperCatalog.NameOf(p: Parsed): string
	local e = HelperCatalog.Roster[p.Faction][p.Role]
	return e.Name
end

function HelperCatalog.FullName(p: Parsed): string
	local e = HelperCatalog.Roster[p.Faction][p.Role]
	return e.Name .. ", " .. e.Title
end

---------------------------------------------------------------------
-- Cupones y reclutamiento (probabilidades en %)
---------------------------------------------------------------------
-- Odds: % de obtener Común, Raro, Épico, Legendario, Mítico (cada fila suma 100). Legendario y Mítico, difíciles: comparables a +8 (7,5%) y +9 (3,5%) de la forja.
-- Pity: garantía. Cada «Every» reclutamientos con ese cupón SIN llegar a «Min» o mejor, el siguiente sale «Min» o mejor.
HelperCatalog.Coupons = {
	Comun = { Name = "Cupón Común", Odds = { 80, 17, 2.9, 0.1, 0 }, Pity = nil },
	Raro = { Name = "Cupón Raro", Odds = { 45, 45, 9.5, 0.5, 0 }, Pity = { Min = "Epico", Every = 15 } },
	Epico = { Name = "Cupón Épico", Odds = { 20, 42, 33, 4.9, 0.1 }, Pity = { Min = "Legendario", Every = 30 } },
	Legendario = { Name = "Cupón Legendario", Odds = { 0, 35, 53.5, 10.5, 1 }, Pity = { Min = "Legendario", Every = 15 } },
	Mitico = { Name = "Cupón Mítico", Odds = { 0, 15, 66, 15, 4 }, Pity = nil },
} :: { [string]: { Name: string, Odds: { number }, Pity: { Min: string, Every: number }? } }

-- Tope diario de cupones que se reciben de monstruos/cofres/cuevas (por rareza). Los de prueba del Fundador no cuentan.
HelperCatalog.DailyCouponCap = { Comun = 20, Raro = 8, Epico = 4, Legendario = 1, Mitico = 1 } :: { [string]: number }
HelperCatalog.WelcomeGift = { Comun = 3, Raro = 1 } :: { [string]: number } -- regalo único de bienvenida (llega a la carta)
-- Esencia por una copia repetida cuando el ayudante ya tiene 5 estrellas (se gasta en la ascensión)
HelperCatalog.EssenceDup = { Comun = 2, Raro = 5, Epico = 12, Legendario = 30, Mitico = 60 } :: { [string]: number }
HelperCatalog.MaxStars = 5
HelperCatalog.PullsPerBatch = 10

-- Chequeo de datos: devuelve (true) o (false, motivo) si alguna fila de probabilidades no suma 100
function HelperCatalog.Validate(): (boolean, string)
	for key, c in pairs(HelperCatalog.Coupons) do
		local sum = 0
		for _, v in ipairs(c.Odds) do
			sum += v
		end
		if math.abs(sum - 100) > 0.001 then
			return false, string.format("%s suma %.3f (debe sumar 100)", key, sum)
		end
		if #c.Odds ~= #HelperCatalog.Rarities then
			return false, key .. " no tiene 5 valores"
		end
	end
	return true, "ok"
end

---------------------------------------------------------------------
-- Poder del ayudante
---------------------------------------------------------------------
-- Efectos base de cada rol (Común, nivel parejo con el dueño). Claves de GearService.Get().
HelperCatalog.RoleEffects = {
	Tanque = { Defensa = 0.020, Vida = 0.040 },
	Guerrero = { Ataque = 0.020, Vida = 0.020 },
	Asesino = { Ataque = 0.012, Critico = 0.015 },
	Tirador = { Ataque = 0.016, Critico = 0.012 },
	Mago = { Ataque = 0.022, Energia = 0.040 },
	Curador = { Curacion = 0.040, Vida = 0.020 },
} :: { [string]: { [string]: number } }
HelperCatalog.RarityPower = { Comun = 1.0, Raro = 1.7, Epico = 2.6, Legendario = 4.0, Mitico = 6.0 } :: { [string]: number }
HelperCatalog.StarBonus = 0.08 -- +8% por estrella (5 estrellas = +40%)
-- Tope TOTAL entre los 3 ayudantes (para que no desbalanceen el juego)
HelperCatalog.EffectCap = { Ataque = 0.30, Vida = 0.35, Defensa = 0.25, Critico = 0.18, Curacion = 0.40, Energia = 0.30 } :: { [string]: number }
HelperCatalog.EffectName = { Ataque = "Ataque", Vida = "Vida", Defensa = "Defensa", Critico = "Crítico", Curacion = "Curación", Energia = "Energía" } :: { [string]: string }
HelperCatalog.EffectOrder = { "Ataque", "Defensa", "Vida", "Critico", "Curacion", "Energia" }

-- Equipo del ayudante: 4 piezas del set de su rol (las mismas que dejan los monstruos)
HelperCatalog.GearSlots = { "Arma", "Casco", "Armadura", "Zapatos" }
HelperCatalog.GearSlotName = { Arma = "Arma", Casco = "Casco", Armadura = "Armadura", Zapatos = "Botas" } :: { [string]: string }
HelperCatalog.PieceBonus = { Comun = 0.03, Raro = 0.05, Epico = 0.08, Legendario = 0.12, Mitico = 0.18 } :: { [string]: number } -- +% de poder por pieza
HelperCatalog.PlusBonus = 0.06 -- +6% extra de esa pieza por cada +1 de mejora
HelperCatalog.BonusGearChance = 0.25 -- cada pieza de equipo que te cae tiene esta probabilidad de traer OTRA para un ayudante equipado

-- XP
HelperCatalog.XpShare = 0.10 -- el ayudante recibe el 10% de tu XP (extra, no te la quita)
HelperCatalog.XpCost = 0.20 -- sube de nivel con el 20% de la XP que cuesta a un jugador (con el 10% de reparto va ~75-80% de tu nivel)
function HelperCatalog.XpToNext(level: number): number
	return math.max(10, math.floor(GB.XpToNext(math.max(1, level)) * HelperCatalog.XpCost))
end
HelperCatalog.MaxLevel = GB.MAX_LEVEL

export type Entry = { Stars: number?, Level: number?, Xp: number?, Gear: { [string]: { Id: string, Plus: number? } }? }
local RankOfLevel: (number) -> number -- (definida más abajo)

-- +% de poder por el equipo puesto (lo calcula con la rareza del objeto: viene en su Id, p. ej. "Set_..._Epico"; el servidor pasa la rareza ya resuelta)
HelperCatalog.FullSetBonus = 0.10 -- las 4 piezas puestas: +10% sobre el aporte del equipo
function HelperCatalog.GearPower(pieces: { { Rarity: string, Plus: number } }): number
	local sum = 0
	for _, p in ipairs(pieces) do
		sum += (HelperCatalog.PieceBonus[p.Rarity] or 0) * (1 + HelperCatalog.PlusBonus * math.clamp(p.Plus, 0, 9))
	end
	if #pieces >= #HelperCatalog.GearSlots then
		sum *= 1 + HelperCatalog.FullSetBonus
	end
	return sum
end

-- Factor por nivel: un ayudante rezagado rinde menos (40% a nivel 1 relativo, 100% al alcanzar tu nivel)
function HelperCatalog.LevelFactor(helperLevel: number, ownerLevel: number): number
	return 0.4 + 0.6 * math.min(1, helperLevel / math.max(1, ownerLevel))
end

-- Efectos de UN ayudante (antes del tope total)
-- asc = ascensión (0..3): suma +5% por escalón. El rango del ayudante (por su nivel) también suma: ver ProgressMult.
function HelperCatalog.Effects(p: Parsed, stars: number, helperLevel: number, ownerLevel: number, gearPower: number, asc: number?): { [string]: number }
	local base = HelperCatalog.RoleEffects[p.Role]
	local out: { [string]: number } = {}
	if not base then
		return out
	end
	local mult = (HelperCatalog.RarityPower[p.Rarity] or 1) * (1 + HelperCatalog.StarBonus * math.clamp(stars, 0, HelperCatalog.MaxStars)) * (1 + gearPower) * HelperCatalog.LevelFactor(helperLevel, ownerLevel)
		* HelperCatalog.ProgressMult(helperLevel, asc or 0)
	for k, v in pairs(base) do
		out[k] = v * mult
	end
	return out
end

-- Suma los efectos de varios ayudantes aplicando el tope total
function HelperCatalog.Total(list: { { [string]: number } }): { [string]: number }
	local sum: { [string]: number } = {}
	for _, eff in ipairs(list) do
		for k, v in pairs(eff) do
			sum[k] = (sum[k] or 0) + v
		end
	end
	for k, v in pairs(sum) do
		local cap = HelperCatalog.EffectCap[k]
		if cap and v > cap then
			sum[k] = cap
		end
	end
	return sum
end

-- Poder de combate por rol (PetPowerService). Solo en PvE: contra jugadores los ayudantes NO atacan (los bonos pasivos valen el 50%).
-- Los arreglos se indexan por rareza (1 Común .. 5 Mítico). Cooldown en segundos; Every = cada cuántos golpes tuyos; Value = fuerza.
-- La fuerza se multiplica por el factor de nivel del ayudante (si va rezagado, rinde menos).
HelperCatalog.Powers = {
	Tanque = { Name = "Muro", Cooldown = { 60, 55, 50, 45, 40 }, Value = { 0.12, 0.16, 0.20, 0.26, 0.34 }, Desc = "Si tu vida baja del 35%, un escudo de {pct}% de tu vida máxima durante 8 s. Se recarga en {cd} s." },
	Guerrero = { Name = "Golpe de apoyo", Every = { 8, 7, 7, 6, 5 }, Value = { 0.30, 0.45, 0.60, 0.80, 1.10 }, Desc = "Cada {every} golpes, ataca contigo: un golpe extra de {pct}% del daño." },
	Asesino = { Name = "Filo cazador", Every = { 9, 8, 7, 6, 5 }, Value = { 0.40, 0.55, 0.75, 1.00, 1.40 }, Desc = "Cada {every} golpes, un tajo extra de {pct}% del daño (x1,5 contra jefes, mini jefes y Metin)." },
	Tirador = { Name = "Disparo certero", Cooldown = { 5, 4.5, 4, 3.5, 3 }, Value = { 0.35, 0.50, 0.70, 0.95, 1.30 }, Desc = "Cada {cd} s, al atacar, dispara al enemigo: {pct}% del daño del golpe." },
	Mago = { Name = "Estallido", Cooldown = { 9, 8, 7, 6, 5 }, Value = { 0.35, 0.50, 0.70, 0.95, 1.30 }, Desc = "Cada {cd} s, al atacar, un estallido arcano daña a los enemigos cercanos ({pct}% del golpe)." },
	Curador = { Name = "Brisa sanadora", Cooldown = { 26, 22, 18, 15, 12 }, Value = { 0.06, 0.09, 0.12, 0.16, 0.22 }, Desc = "Cada {cd} s cura {pct}% de la vida máxima a ti y a tu grupo cercano." },
} :: { [string]: { Name: string, Cooldown: { number }?, Every: { number }?, Value: { number }, Desc: string } }
HelperCatalog.PowerName = { Tanque = "Muro", Guerrero = "Golpe de apoyo", Asesino = "Filo cazador", Tirador = "Disparo certero", Mago = "Estallido", Curador = "Brisa sanadora" } :: { [string]: string }

-- Parámetros reales del poder de un ayudante: rareza + ascensión (cada escalón sube 1 el índice, hasta Mítico) + rama según su nivel.
--   Rama A («Ritmo»): menos tiempo/golpes entre usos. Rama B («Potencia»): más fuerza. Los topes evitan escudos/curaciones desmedidos.
function HelperCatalog.PowerParams(role: string, rarity: string, asc: number, branch: string?, level: number): { Value: number, Cooldown: number?, Every: number?, Index: number, Tier: number }?
	local cfg = HelperCatalog.Powers[role]
	local base = HelperCatalog.RarityIndex[rarity]
	if not cfg or not base then
		return nil
	end
	local idx = math.clamp(base + math.clamp(asc, 0, HelperCatalog.MaxAsc), 1, #HelperCatalog.Rarities)
	local value = cfg.Value[idx]
	local cooldown = if cfg.Cooldown then cfg.Cooldown[idx] else nil
	local every = if cfg.Every then cfg.Every[idx] else nil
	local tier = if branch == "A" or branch == "B" then HelperCatalog.BranchTier(level) else 0
	if tier > 0 then
		if branch == "A" then
			local rate = HelperCatalog.BranchRate[tier]
			if cooldown then
				cooldown *= 1 - rate
			end
			if every then
				every = math.max(3, math.floor(every * (1 - rate) + 0.5))
			end
		else
			value *= 1 + HelperCatalog.BranchPower[tier]
		end
	end
	local cap = HelperCatalog.ValueCap[role]
	if cap and value > cap then
		value = cap
	end
	return { Value = value, Cooldown = cooldown, Every = every, Index = idx, Tier = tier }
end

-- Texto del poder con sus números (con ascensión y rama si se indican)
function HelperCatalog.PowerTextFor(role: string, rarity: string, asc: number, branch: string?, level: number): string
	local cfg = HelperCatalog.Powers[role]
	local params = HelperCatalog.PowerParams(role, rarity, asc, branch, level)
	if not cfg or not params then
		return ""
	end
	local text = cfg.Desc
	text = string.gsub(text, "{cd}", string.format("%.3g", params.Cooldown or 0))
	text = string.gsub(text, "{every}", string.format("%g", params.Every or 0))
	text = string.gsub(text, "{pct}", string.format("%g", math.floor(params.Value * 1000 + 0.5) / 10))
	return text
end

function HelperCatalog.PowerText(role: string, rarity: string): string
	return HelperCatalog.PowerTextFor(role, rarity, 0, nil, 1)
end

-- Texto de un efecto: "Ataque +2,4%"
function HelperCatalog.EffectText(effects: { [string]: number }): string
	local parts: { string } = {}
	for _, key in ipairs(HelperCatalog.EffectOrder) do
		local v = effects[key]
		if v and v > 0.00005 then
			table.insert(parts, string.format("%s +%.1f%%", HelperCatalog.EffectName[key], v * 100))
		end
	end
	return table.concat(parts, " · ")
end

---------------------------------------------------------------------
-- PROGRESO DEL AYUDANTE
---------------------------------------------------------------------
-- 1) RANGOS: se ganan por NIVEL del ayudante (no depende de tu nivel). Cada rango suma +3,5% a sus bonos pasivos (hasta +42%) y suele traer
--    un aspecto nuevo y un regalo. Los 12 hitos: 10, 25, 50, 100, 200, 400, 800, 1200, 1600, 2000, 2500 y 3000.
HelperCatalog.Ranks = {
	{ Min = 1, Name = "Recluta" }, { Min = 10, Name = "Aprendiz" }, { Min = 25, Name = "Soldado" }, { Min = 50, Name = "Veterano" },
	{ Min = 100, Name = "Experto" }, { Min = 200, Name = "Élite" }, { Min = 400, Name = "Campeón" }, { Min = 800, Name = "Maestro" },
	{ Min = 1200, Name = "Gran Maestro" }, { Min = 1600, Name = "Héroe" }, { Min = 2000, Name = "Mito" }, { Min = 2500, Name = "Leyenda" },
	{ Min = 3000, Name = "Eterno" },
} :: { { Min: number, Name: string } }
HelperCatalog.RankBonus = 0.035
HelperCatalog.RankColors = {
	Color3.fromRGB(150, 155, 165), Color3.fromRGB(176, 128, 92), Color3.fromRGB(196, 140, 86), Color3.fromRGB(170, 190, 205),
	Color3.fromRGB(130, 205, 235), Color3.fromRGB(255, 205, 90), Color3.fromRGB(255, 185, 55), Color3.fromRGB(120, 235, 200),
	Color3.fromRGB(100, 215, 255), Color3.fromRGB(190, 130, 255), Color3.fromRGB(255, 110, 190), Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(255, 245, 200),
} :: { Color3 }
RankOfLevel = function(level: number): number
	local rank = 1
	for i, r in ipairs(HelperCatalog.Ranks) do
		if level >= r.Min then
			rank = i
		end
	end
	return rank
end
HelperCatalog.RankOf = RankOfLevel
HelperCatalog.MaxRank = #HelperCatalog.Ranks

-- Multiplicador de sus bonos pasivos por rango y ascensión
function HelperCatalog.ProgressMult(level: number, asc: number): number
	return (1 + HelperCatalog.RankBonus * (RankOfLevel(level) - 1)) * (1 + HelperCatalog.AscBonus * math.clamp(asc, 0, HelperCatalog.MaxAsc))
end

-- 2) RAMAS DE PODER: al nivel 100 se elige A (Ritmo) o B (Potencia); a los 500 y 1500 sube el escalón de la rama elegida.
HelperCatalog.BranchLevels = { 100, 500, 1500 } :: { number }
HelperCatalog.BranchRate = { 0.08, 0.16, 0.25 } :: { number } -- A: -% de tiempo/golpes entre usos
HelperCatalog.BranchPower = { 0.20, 0.40, 0.65 } :: { number } -- B: +% de fuerza
HelperCatalog.ValueCap = { Tanque = 0.55, Curador = 0.32 } :: { [string]: number } -- tope de fuerza (escudo / cura) tras rama
HelperCatalog.Branches = {
	Tanque = { A = { Name = "Bastión", Desc = "El Muro se recarga antes." }, B = { Name = "Coraza", Desc = "El Muro absorbe más daño." } },
	Guerrero = { A = { Name = "Furia", Desc = "Golpea contigo más a menudo." }, B = { Name = "Filo", Desc = "Cada golpe de apoyo pega más fuerte." } },
	Asesino = { A = { Name = "Ráfaga", Desc = "Tajos más seguidos." }, B = { Name = "Cazador", Desc = "Tajos mucho más fuertes." } },
	Tirador = { A = { Name = "Cadencia", Desc = "Dispara más seguido." }, B = { Name = "Mira de águila", Desc = "Cada disparo pega más fuerte." } },
	Mago = { A = { Name = "Fluir arcano", Desc = "Estallidos más seguidos." }, B = { Name = "Supernova", Desc = "Estallidos más potentes." } },
	Curador = { A = { Name = "Plegaria rápida", Desc = "Cura más a menudo." }, B = { Name = "Luz plena", Desc = "Cada cura repone más vida." } },
} :: { [string]: { A: { Name: string, Desc: string }, B: { Name: string, Desc: string } } }
HelperCatalog.BranchKindText = { A = "Ritmo", B = "Potencia" } :: { [string]: string }
HelperCatalog.BranchChangeMobs = 300 -- cambiar de rama (después de la primera elección, gratis) cuesta el oro de este número de monstruos de tu nivel

function HelperCatalog.BranchTier(level: number): number
	local tier = 0
	for i, lv in ipairs(HelperCatalog.BranchLevels) do
		if level >= lv then
			tier = i
		end
	end
	return tier
end

-- 3) ASCENSIÓN: gasta Esencia (copias repetidas con 5★ y regalos de rango). Cada escalón: +1 al índice del poder (hasta Mítico) y +5% a sus bonos.
HelperCatalog.MaxAsc = 3
HelperCatalog.AscLevels = { 100, 500, 1500 } :: { number } -- nivel del ayudante para ascender al escalón 1, 2, 3
HelperCatalog.AscBase = { Comun = 20, Raro = 30, Epico = 45, Legendario = 70, Mitico = 100 } :: { [string]: number }
HelperCatalog.AscMult = { 1, 3, 8 } :: { number }
HelperCatalog.AscBonus = 0.05
HelperCatalog.AscNames = { "I", "II", "III" } :: { string }
function HelperCatalog.AscendCost(rarity: string, nextAsc: number): number
	return (HelperCatalog.AscBase[rarity] or 20) * (HelperCatalog.AscMult[nextAsc] or 8)
end

-- 4) VÍNCULO DE FACCIÓN: un perk propio de la facción para el DUEÑO, según el nivel del ayudante equipado de mayor nivel.
HelperCatalog.BondLevels = { 100, 1000 } :: { number }
HelperCatalog.Bond = {
	Saiyan = { Name = "Ki desbordado", Stat = "Energia", Label = "Energía", Values = { 0.03, 0.06 } },
	Shinobi = { Name = "Paso de sombra", Stat = "Critico", Label = "Crítico", Values = { 0.015, 0.03 } },
	Pirate = { Name = "Instinto de botín", Stat = "Oro", Label = "Oro", Values = { 0.02, 0.04 } },
	Shinigami = { Name = "Alma serena", Stat = "Regen", Label = "Regeneración", Values = { 0.002, 0.004 } },
} :: { [string]: { Name: string, Stat: string, Label: string, Values: { number } } }
function HelperCatalog.BondTier(level: number): number
	local tier = 0
	for i, lv in ipairs(HelperCatalog.BondLevels) do
		if level >= lv then
			tier = i
		end
	end
	return tier
end
function HelperCatalog.BondStats(faction: string, topLevel: number): { [string]: number }
	local b = HelperCatalog.Bond[faction]
	local tier = HelperCatalog.BondTier(topLevel)
	if not b or tier <= 0 then
		return {}
	end
	return { [b.Stat] = b.Values[tier] }
end

-- 5) REGALOS: uno por rango alcanzado (se reclaman en la ventana). Oro = «mobs» de monstruos de ese nivel; Esencia según rareza; cupón en hitos grandes.
HelperCatalog.Gifts = {
	[2] = { Mobs = 20, Essence = 2 }, [3] = { Mobs = 30, Essence = 3 }, [4] = { Mobs = 40, Essence = 5 },
	[5] = { Mobs = 60, Essence = 8, Coupon = "Raro", CouponN = 1 }, [6] = { Mobs = 80, Essence = 12 },
	[7] = { Mobs = 100, Essence = 18, Coupon = "Raro", CouponN = 2 }, [8] = { Mobs = 130, Essence = 26 },
	[9] = { Mobs = 160, Essence = 38, Coupon = "Epico", CouponN = 1 }, [10] = { Mobs = 200, Essence = 55 },
	[11] = { Mobs = 250, Essence = 80, Coupon = "Epico", CouponN = 2 }, [12] = { Mobs = 300, Essence = 110 },
	[13] = { Mobs = 400, Essence = 160, Coupon = "Legendario", CouponN = 1 },
} :: { [number]: { Mobs: number, Essence: number, Coupon: string?, CouponN: number? } }
function HelperCatalog.GiftEssence(rank: number, rarity: string): number
	local g = HelperCatalog.Gifts[rank]
	if not g then
		return 0
	end
	return math.floor(g.Essence * (1 + 0.25 * ((HelperCatalog.RarityIndex[rarity] or 1) - 1)) + 0.5)
end

-- 6) PERSONALIZACIÓN: apodo (filtrado por el servidor) y AURA POR RAREZA.
--    Cada rareza tiene su aura (las mismas que usan los jugadores, a escala del ayudante; la receta está en AuraSpecs). El ayudante lleva la de su rareza
--    y solo puede cambiar a la de una rareza ANTERIOR (nunca a una mayor). Aura = número 1..5 (1 = Común ... 5 = Mítico).
HelperCatalog.NickMax = 14
HelperCatalog.RarityAuras = { "Brisa", "Brillo", "Llama", "Cosmos", "Serafin" } :: { string } -- ids de LevelMilestones.Auras, en orden de rareza
-- Número de aura de la rareza (el máximo que puede llevar un ayudante de esa rareza)
function HelperCatalog.AuraOf(rarity: string): number
	return HelperCatalog.RarityIndex[rarity] or 1
end
-- Id de aura (LevelMilestones) de un número de aura
function HelperCatalog.AuraId(aura: number): string
	return HelperCatalog.RarityAuras[math.clamp(math.floor(aura), 1, #HelperCatalog.RarityAuras)]
end
-- Aura válida para un ayudante de esa rareza: entre 1 y la de su rareza (si viene algo raro, la de su rareza)
function HelperCatalog.ClampAura(aura: any, rarity: string): number
	local top = HelperCatalog.AuraOf(rarity)
	if typeof(aura) ~= "number" or aura ~= aura then
		return top
	end
	return math.clamp(math.floor(aura), 1, top)
end


return HelperCatalog
