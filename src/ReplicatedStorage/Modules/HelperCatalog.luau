--!strict
--[[
    HelperCatalog (ModuleScript) -> ReplicatedStorage.Modules.HelperCatalog
    AYUDANTES DE COMBATE (reemplazan a las mascotas). Todo el sistema se rebalancea desde AQUÍ:
      - 4 facciones x 6 roles = 24 personajes (nombre y aspecto propios) x 5 rarezas.
      - CUPONES de reclutamiento (5 rarezas): cada cupón tiene su tabla de probabilidades en % (Légendario y Mítico, difíciles: estilo +8/+9 de la forja).
      - 3 ranuras: la 1 es gratis; la 2 y la 3 las da el pase (atributo Pass_PetSlot, el mismo pase de antes). Todas desde nivel 1.
      - Efectos pasivos al dueño (mismas claves que GearService: Ataque, Defensa, Vida, Critico, Curacion, Energia) + un poder de combate por rol (PvE).
      - XP: cada ayudante equipado recibe el 10% de la XP que ganas (extra: NO te la descuenta). Nivel máximo = tu nivel.
    Id de un ayudante: "<Facción>|<Rol>|<Rareza>"  (ej. "Saiyan|Tanque|Epico"). Una copia repetida sube sus estrellas (máx. 5); después da oro.
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
-- Oro por una copia repetida cuando el ayudante ya tiene 5 estrellas
HelperCatalog.DuplicateGold = { Comun = 500, Raro = 2000, Epico = 8000, Legendario = 30000, Mitico = 100000 } :: { [string]: number }
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
function HelperCatalog.Effects(p: Parsed, stars: number, helperLevel: number, ownerLevel: number, gearPower: number): { [string]: number }
	local base = HelperCatalog.RoleEffects[p.Role]
	local out: { [string]: number } = {}
	if not base then
		return out
	end
	local mult = (HelperCatalog.RarityPower[p.Rarity] or 1) * (1 + HelperCatalog.StarBonus * math.clamp(stars, 0, HelperCatalog.MaxStars)) * (1 + gearPower) * HelperCatalog.LevelFactor(helperLevel, ownerLevel)
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

-- Texto del poder con sus números para una rareza
function HelperCatalog.PowerText(role: string, rarity: string): string
	local cfg = HelperCatalog.Powers[role]
	local idx = HelperCatalog.RarityIndex[rarity]
	if not cfg or not idx then
		return ""
	end
	local text = cfg.Desc
	text = string.gsub(text, "{cd}", string.format("%g", if cfg.Cooldown then cfg.Cooldown[idx] else 0))
	text = string.gsub(text, "{every}", string.format("%g", if cfg.Every then cfg.Every[idx] else 0))
	text = string.gsub(text, "{pct}", string.format("%g", math.floor(cfg.Value[idx] * 1000 + 0.5) / 10))
	return text
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

return HelperCatalog
