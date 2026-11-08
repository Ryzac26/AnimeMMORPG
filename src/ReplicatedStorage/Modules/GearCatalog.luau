--!strict
--[[
    GearCatalog (ModuleScript) -> ReplicatedStorage.Modules.GearCatalog
    EQUIPO GENERADO por fórmulas (no se escribe objeto por objeto). ItemCatalog lo mezcla en ItemCatalog.Items.
    Para rebalancear, tocas SOLO los números de la sección "NÚMEROS".

    SETS DE CLASE (uno por ROL, iguales para las 4 facciones: la simetría entre facciones es estructural)
        Tanque "Baluarte" · Guerrero "Vanguardia" · Asesino "Sombra" · Tirador "Cazador" · Mago "Arcano" · Curador "Santuario"
        Piezas: Arma, Armadura, Casco, Zapatos  (+ joyas universales y el Emblema de facción)
        El arma depende del rol Y de la facción (WeaponStyle: es lo que decide la animación y el modelo en la mano).
    ESTADÍSTICAS (todas en % como fracción: 0.05 = 5%)
        Ataque (daño) · Defensa (reduce daño recibido, tope 50%) · Vida (vida máxima) · Critico (prob., daño x1.5) · Curacion (poder de cura)
    FÓRMULA de cada estadística de una pieza:
        valor = BASE_SET_BUDGET x TierMult(tier) x RarityMult[rareza] x RoleScale[rol] x PieceShare[ranura] x RoleWeights[rol][estadística]
        TierMult = 1 + TIER_STEP x (tier-1)        (11 tramos de nivel: 1,10,20...100)
    PARIDAD entre roles: RoleScale se calibró para que el "Índice de Poder" del set completo sea igual en los 6 roles
        (ValidateBalance() lo comprueba: dispersión máxima 3%). Si cambias pesos o presupuesto, corre ValidateBalance().
    +1..+9 (mejora futura): EnhanceMult(plus) ya está; GearService lee el atributo "EquipPlus_<ranura>" (0 si no existe).
    Ids:  G_<Rol>_<Ranura>_<tramo>_<rareza>  (arma: Arma<Estilo>) · J_<Joya>_<Foco>_<tramo>_<rareza> · F_<Facción>_<tramo>_<rareza>
]]
export type Gear = { [string]: number }

local GearCatalog = {}

---------------------------------------------------------------------
-- NÚMEROS
---------------------------------------------------------------------
GearCatalog.Stats = { "Ataque", "Defensa", "Vida", "Critico", "Curacion" }
GearCatalog.StatDisplay = { Ataque = "Ataque", Defensa = "Defensa", Vida = "Vida", Critico = "Crítico", Curacion = "Curación" } :: { [string]: string }
GearCatalog.Roles = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
GearCatalog.Factions = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
GearCatalog.FactionDisplay = { Saiyan = "Saiyan", Shinobi = "Shinobi", Pirate = "Pirata", Shinigami = "Shinigami" } :: { [string]: string }

GearCatalog.TierLevels = { 1, 300, 600, 900, 1200, 1500, 1800, 2100, 2400, 2700, 3000 } -- (antes 1,10,20...100; x30)
GearCatalog.TierNames = { "Cobre", "Bronce", "Hierro", "Acero", "Plata", "Oro", "Platino", "Cristal", "Obsidiana", "Celestial", "Divino" }

GearCatalog.Rarities = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
GearCatalog.RarityName = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" } :: { [string]: string }
GearCatalog.RarityMult = { Comun = 1.00, Raro = 1.25, Epico = 1.55, Legendario = 1.95, Mitico = 2.50 } :: { [string]: number }

GearCatalog.BASE_SET_BUDGET = 0.08 -- presupuesto total del set completo (4 piezas) en Común, tramo 1
GearCatalog.TIER_STEP = 0.15 -- cada tramo de nivel suma +15% (tramo 11 = x2.5)
GearCatalog.CRIT_MULT = 1.5 -- daño de un golpe crítico
GearCatalog.DEFENSE_CAP = 0.50 -- máximo de reducción de daño por equipo+mascota
GearCatalog.CRIT_CAP = 0.60
GearCatalog.PVP_GEAR_FACTOR = 0.50 -- en PvP el equipo cuenta la mitad (el PvP no se decide por el equipo)

GearCatalog.PieceShare = { Arma = 0.40, Armadura = 0.25, Casco = 0.20, Zapatos = 0.15 } :: { [string]: number } -- suman 1
GearCatalog.JewelryShare = { Collar = 0.10, Anillo = 0.10, Brazalete = 0.10, Pendientes = 0.10 } :: { [string]: number } -- extra sobre el set (el Anillo también va en la ranura Anillo 2)
-- Piezas de CLASE extra (Escudo, Cinturón, Capa): solo para el rol, con las estadísticas de su rol. No cuentan para el bono de set (que sigue siendo de 4 piezas).
GearCatalog.ClassExtraShare = { Escudo = 0.12, Cinturon = 0.08, Capa = 0.08 } :: { [string]: number }
GearCatalog.ClassExtraOrder = { "Escudo", "Cinturon", "Capa" }
GearCatalog.ShieldNames = { Tanque = "Escudo Torre", Guerrero = "Escudo de Guerra", Asesino = "Daga Gemela", Tirador = "Carcaj", Mago = "Orbe", Curador = "Libro Sagrado" } :: { [string]: string }
GearCatalog.ExtraNames = { Cinturon = "Cinturón", Capa = "Capa" } :: { [string]: string }
GearCatalog.EmblemShare = 0.10 -- Emblema de facción (ranura Accesorio1)
-- BONUS DE SET COMPLETO (4/4 piezas del set de TU rol): se suma al +15% a todo el equipo. Un efecto propio por rol.
-- Claves: Range (x alcance) · Radius (x radio de áreas) · Lifesteal · Reflect · Critico (+) · CritDmg (+ al multiplicador crítico) · Curacion (+)
GearCatalog.SetFull = {
	Tirador = { Text = "+25% de alcance en ataques y poderes", Range = 1.25 },
	Mago = { Text = "+20% de radio en sus poderes de área", Radius = 1.20 },
	Guerrero = { Text = "8% del daño que haces te cura", Lifesteal = 0.08 },
	Tanque = { Text = "10% del daño cuerpo a cuerpo recibido se refleja", Reflect = 0.10 },
	Asesino = { Text = "+12% de crítico y críticos +0,25 de daño (x1,75)", Critico = 0.12, CritDmg = 0.25 },
	Curador = { Text = "+20% de curación y +25% de alcance", Curacion = 0.20, Range = 1.25 },
} :: { [string]: { [string]: any } }
GearCatalog.SetBonus = { [0] = 0, [1] = 0, [2] = 0.05, [3] = 0.05, [4] = 0.15 } :: { [number]: number } -- piezas del set de TU rol equipadas -> +% a todo el equipo

-- Pesos de estadísticas por rol (suman 1)
GearCatalog.RoleWeights = {
	Tanque = { Defensa = 0.50, Vida = 0.40, Ataque = 0.10 },
	Guerrero = { Ataque = 0.45, Vida = 0.30, Defensa = 0.25 },
	Asesino = { Ataque = 0.50, Critico = 0.35, Vida = 0.15 },
	Tirador = { Ataque = 0.50, Critico = 0.30, Vida = 0.20 },
	Mago = { Ataque = 0.60, Vida = 0.20, Defensa = 0.20 },
	Curador = { Curacion = 0.50, Vida = 0.30, Defensa = 0.20 },
} :: { [string]: { [string]: number } }
-- Cuánto pesa cada cosa en el poder de cada rol: { daño, supervivencia, curación } (suman 1)
GearCatalog.RoleMix = {
	Tanque = { 0.20, 0.80, 0.00 },
	Guerrero = { 0.50, 0.50, 0.00 },
	Asesino = { 0.70, 0.30, 0.00 },
	Tirador = { 0.70, 0.30, 0.00 },
	Mago = { 0.70, 0.30, 0.00 },
	Curador = { 0.15, 0.35, 0.50 },
} :: { [string]: { number } }
-- Calibración de paridad (ver ValidateBalance)
GearCatalog.RoleScale = { Tanque = 0.704, Guerrero = 1.079, Asesino = 1.061, Tirador = 1.067, Mago = 1.022, Curador = 1.293 } :: { [string]: number }

-- Foco de las joyas (universales). El Crítico rinde la mitad que el resto por punto, por eso lleva más %.
GearCatalog.JewelFocus = { "Ataque", "Defensa", "Vida", "Critico", "Curacion" }
GearCatalog.FocusMult = { Ataque = 1, Defensa = 1, Vida = 1, Critico = 1.6, Curacion = 1 } :: { [string]: number }
GearCatalog.JewelFocusName = { Ataque = "Fuerza", Defensa = "Muralla", Vida = "Vitalidad", Critico = "Precisión", Curacion = "Sanación" } :: { [string]: string }
GearCatalog.JewelNames = { Collar = "Collar", Anillo = "Anillo", Brazalete = "Brazalete", Pendientes = "Pendientes" } :: { [string]: string }

GearCatalog.EmblemWeights = { Ataque = 0.40, Vida = 0.30, Defensa = 0.30 } :: { [string]: number }
GearCatalog.EmblemRarities = { "Epico", "Legendario", "Mitico" }
GearCatalog.EmblemNames = { Saiyan = "Emblema Saiyan", Shinobi = "Banda Shinobi", Pirate = "Brújula Pirata", Shinigami = "Insignia Shinigami" } :: { [string]: string }

GearCatalog.SetNames = { Tanque = "Baluarte", Guerrero = "Vanguardia", Asesino = "Sombra", Tirador = "Cazador", Mago = "Arcano", Curador = "Santuario" } :: { [string]: string }
GearCatalog.PieceNames = { Armadura = "Coraza", Casco = "Casco", Zapatos = "Botas" } :: { [string]: string }
GearCatalog.WeaponNames = { Sword = "Espada", Dagger = "Daga", Bow = "Arco", Staff = "Báculo", Gun = "Pistola", Axe = "Hacha", Fist = "Guanteletes" } :: { [string]: string }

-- Arma por facción y rol (coincide con las animaciones de AttackAnimator)
GearCatalog.WeaponStyle = {
	Saiyan = { Tanque = "Fist", Guerrero = "Fist", Asesino = "Fist", Tirador = "Staff", Mago = "Staff", Curador = "Staff" },
	Shinobi = { Tanque = "Fist", Guerrero = "Sword", Asesino = "Dagger", Tirador = "Dagger", Mago = "Staff", Curador = "Staff" },
	Pirate = { Tanque = "Fist", Guerrero = "Sword", Asesino = "Dagger", Tirador = "Gun", Mago = "Staff", Curador = "Staff" },
	Shinigami = { Tanque = "Fist", Guerrero = "Sword", Asesino = "Fist", Tirador = "Bow", Mago = "Staff", Curador = "Staff" },
} :: { [string]: { [string]: string } }

-- ARMAS DE DOS MANOS: el Báculo (Mago/Curador) y el Arco. Con una equipada no se puede llevar ESCUDO (Escudo Torre, Escudo de Guerra...).
-- Las piezas de clase "foco" (Orbe, Libro Sagrado, Carcaj, Daga Gemela) no son escudos y sí se pueden llevar.
GearCatalog.TwoHandedStyles = { Staff = true, Bow = true } :: { [string]: boolean }
function GearCatalog.IsTwoHandedWeapon(item: any): boolean
	return item ~= nil and item.Slot == "Arma" and typeof(item.Style) == "string" and GearCatalog.TwoHandedStyles[item.Style] == true
end
function GearCatalog.IsShield(item: any): boolean
	return item ~= nil and item.Slot == "Escudo" and (item.Role == nil or item.Role == "Tanque" or item.Role == "Guerrero")
end

---------------------------------------------------------------------
-- TEMAS DE SET por PESO (Pesado: Tanque/Guerrero · Medio: Asesino/Tirador · Ligero: Mago/Curador)
-- Cada tema es una identidad visual + elemento y cubre 2 tramos de nivel (el último, solo el 11). Los ids de los objetos NO cambian:
-- el tema de una pieza sale de su tramo. Piezas temáticas (7 ranuras): Casco, Armadura, Zapatos, Arma, Escudo, Cinturón y Capa.
-- Los iconos viven en GearIcons (ArtKey -> rbxassetid), se rellena cuando se suben las imágenes.
---------------------------------------------------------------------
GearCatalog.Weights = { Tanque = "pesado", Guerrero = "pesado", Asesino = "medio", Tirador = "medio", Mago = "ligero", Curador = "ligero" } :: { [string]: string }
GearCatalog.WeightName = { pesado = "Pesado", medio = "Medio", ligero = "Ligero" } :: { [string]: string }
GearCatalog.WeightOrder = { "pesado", "medio", "ligero" }
GearCatalog.Themes = {
	pesado = {
		{ Id = "coloso_hierro", Name = "Coloso de Hierro", Elem = "Tierra", Base = "#7c8794", Acc = "#e0903a" },
		{ Id = "centinela_granito", Name = "Centinela de Granito", Elem = "Hielo", Base = "#6b7f95", Acc = "#5ad0e0" },
		{ Id = "vanguardia_carmesi", Name = "Vanguardia Carmesí", Elem = "Fuego", Base = "#a83a3a", Acc = "#f0c050" },
		{ Id = "paladin_solar", Name = "Paladín Solar", Elem = "Luz", Base = "#d8c9a0", Acc = "#f2b632" },
		{ Id = "titan_obsidiana", Name = "Titán de Obsidiana", Elem = "Sombra", Base = "#34303f", Acc = "#a65cff" },
		{ Id = "behemoth_volcanico", Name = "Behemoth Volcánico", Elem = "Lava", Base = "#3a2a28", Acc = "#ff5a1f" },
	},
	medio = {
		{ Id = "cazador_bosque", Name = "Cazador del Bosque", Elem = "Naturaleza", Base = "#5f8a4a", Acc = "#c9a064" },
		{ Id = "nomada_desierto", Name = "Nómada del Desierto", Elem = "Viento", Base = "#c8a465", Acc = "#2fb7b0" },
		{ Id = "corsario_abismo", Name = "Corsario del Abismo", Elem = "Agua", Base = "#26456e", Acc = "#e2b864" },
		{ Id = "viboras_esmeralda", Name = "Víbora Esmeralda", Elem = "Veneno", Base = "#2f6b4f", Acc = "#9cf05a" },
		{ Id = "ventisca_gelida", Name = "Ventisca Gélida", Elem = "Hielo", Base = "#9ec6dc", Acc = "#ffffff" },
		{ Id = "sombra_nocturna", Name = "Sombra Nocturna", Elem = "Sombra", Base = "#2a2438", Acc = "#c86bff" },
	},
	ligero = {
		{ Id = "aprendiz_celeste", Name = "Aprendiz Celeste", Elem = "Aire", Base = "#4f7fd0", Acc = "#f2d36b" },
		{ Id = "bosque_mistico", Name = "Bosque Místico", Elem = "Naturaleza", Base = "#6fbf7a", Acc = "#ff9ad0" },
		{ Id = "abismo_marino", Name = "Abismo Marino", Elem = "Agua", Base = "#1f8f9f", Acc = "#8ee8ff" },
		{ Id = "ceniza_infernal", Name = "Ceniza Infernal", Elem = "Fuego", Base = "#a1352b", Acc = "#ff9a2e" },
		{ Id = "santuario_luz", Name = "Santuario de Luz", Elem = "Luz", Base = "#efe9d8", Acc = "#e8b93a" },
		{ Id = "eclipse_violeta", Name = "Eclipse Violeta", Elem = "Cosmos", Base = "#5b3c9b", Acc = "#ff6fd0" },
	},
} :: { [string]: { { Id: string, Name: string, Elem: string, Base: string, Acc: string } } }
GearCatalog.ThemeById = {} :: { [string]: { Id: string, Name: string, Elem: string, Base: string, Acc: string, Weight: string } }
for weight, list in pairs(GearCatalog.Themes) do
	for _, t in ipairs(list) do
		(t :: any).Weight = weight
		GearCatalog.ThemeById[t.Id] = t :: any
	end
end

function GearCatalog.ThemeOfTier(weight: string, tier: number): any
	local list = GearCatalog.Themes[weight]
	return list[math.clamp((tier + 1) // 2, 1, #list)]
end

-- Bonos de combinación (se suman al bono de set de rol)
GearCatalog.ThemeMult = { [2] = 0.04, [4] = 0.10, [7] = 0.18 } :: { [number]: number } -- piezas del MISMO tema -> +% a todo el equipo
GearCatalog.MestizoMult = 0.06 -- 3+ piezas de un tema y 3+ de otro (cualquier peso) -> +% a todo el equipo
GearCatalog.WeightPieces = 5 -- piezas del mismo peso para su bono propio
GearCatalog.WeightStat = { pesado = { Vida = 0.03 }, medio = { Critico = 0.03 }, ligero = { Ataque = 0.03 } } :: { [string]: { [string]: number } }
-- Efecto del elemento: 4 piezas del tema = menor, 7 = mayor (suma plana a la estadística)
GearCatalog.ElementStat = {
	Fuego = "Ataque", Lava = "Ataque", Hielo = "Defensa", Tierra = "Defensa", Naturaleza = "Vida", Agua = "Vida",
	Viento = "Critico", Aire = "Critico", Sombra = "Critico", Veneno = "CritDmg", Cosmos = "CritDmg", Luz = "Curacion",
} :: { [string]: string }
GearCatalog.ElementMinor = 0.02
GearCatalog.ElementMajor = 0.04
GearCatalog.StatShort = { Ataque = "ataque", Defensa = "defensa", Vida = "vida", Critico = "crítico", CritDmg = "daño crítico", Curacion = "curación" } :: { [string]: string }

export type ThemeSummary = { Mult: number, Extra: { [string]: number }, Lines: { string }, Best: string?, BestCount: number }
-- items: piezas equipadas que el jugador PUEDE usar (con campos Theme / Weight). Lo usan GearService (valor real) y GearView (ventana).
function GearCatalog.ThemeSummary(items: { any }): ThemeSummary
	local counts: { [string]: number } = {}
	local weights: { [string]: number } = {}
	for _, it in ipairs(items) do
		if typeof(it.Theme) == "string" then
			counts[it.Theme] = (counts[it.Theme] or 0) + 1
			if typeof(it.Weight) == "string" then
				weights[it.Weight] = (weights[it.Weight] or 0) + 1
			end
		end
	end
	local order: { string } = {}
	for id in pairs(counts) do
		table.insert(order, id)
	end
	table.sort(order, function(a, b)
		if counts[a] ~= counts[b] then
			return counts[a] > counts[b]
		end
		return a < b
	end)
	local out: ThemeSummary = { Mult = 0, Extra = {}, Lines = {}, Best = order[1], BestCount = if order[1] then counts[order[1]] else 0 }
	local function add(stat: string, v: number)
		out.Extra[stat] = (out.Extra[stat] or 0) + v
	end
	local n1 = out.BestCount
	local themeMult = 0
	for need, m in pairs(GearCatalog.ThemeMult) do
		if n1 >= need and m > themeMult then
			themeMult = m
		end
	end
	local n2 = if order[2] then counts[order[2]] else 0
	local mestizo = n1 >= 3 and n2 >= 3
	if order[1] then
		local t = GearCatalog.ThemeById[order[1]]
		if t then
			local stat = GearCatalog.ElementStat[t.Elem]
			local line = string.format("Tema %s %d/7", t.Name, n1)
			if n1 >= 7 then
				add(stat, GearCatalog.ElementMajor)
			elseif n1 >= 4 then
				add(stat, GearCatalog.ElementMinor)
			end
			if themeMult > 0 then
				line ..= string.format(": +%d%% al equipo", math.floor(themeMult * 100 + 0.5))
			end
			if n1 >= 4 and stat then
				line ..= string.format(" · %s: +%d%% %s", t.Elem, math.floor((if n1 >= 7 then GearCatalog.ElementMajor else GearCatalog.ElementMinor) * 100 + 0.5), GearCatalog.StatShort[stat] or stat)
			end
			table.insert(out.Lines, line)
		end
	end
	if mestizo and GearCatalog.MestizoMult > themeMult then
		themeMult = GearCatalog.MestizoMult
	end
	if mestizo then
		local t2 = GearCatalog.ThemeById[order[2]]
		local t1 = GearCatalog.ThemeById[order[1]]
		if t1 and t2 and t1.Id ~= t2.Id then
			local s1, s2 = GearCatalog.ElementStat[t1.Elem], GearCatalog.ElementStat[t2.Elem]
			if s1 then
				add(s1, GearCatalog.ElementMinor / 2)
			end
			if s2 then
				add(s2, GearCatalog.ElementMinor / 2)
			end
			table.insert(out.Lines, string.format("Mestizo %s + %s (%d+%d): +%d%% al equipo y mitad del efecto de cada elemento", t1.Elem, t2.Elem, n1, n2, math.floor(GearCatalog.MestizoMult * 100 + 0.5)))
		end
	end
	out.Mult = themeMult
	for w, n in pairs(weights) do
		if n >= GearCatalog.WeightPieces then
			for stat, v in pairs(GearCatalog.WeightStat[w]) do
				add(stat, v)
				table.insert(out.Lines, string.format("Peso %s %d piezas: +%d%% %s", GearCatalog.WeightName[w], n, math.floor(v * 100 + 0.5), GearCatalog.StatShort[stat] or stat))
			end
		end
	end
	return out
end

-- Mejora +0..+9: multiplica las estadísticas de la pieza. (Probabilidades sugeridas para cuando se implemente:
-- +1..+3 100% · +4 85% · +5 70% · +6 55% · +7 40% · +8 30% · +9 20%)
function GearCatalog.EnhanceMult(plus: number): number
	local n = math.clamp(math.floor(plus), 0, 9)
	-- +9 (máximo): +10% extra sobre la curva normal (x2,36 en vez de x2,26)
	return 1 + 0.05 * n + 0.01 * n * n + (if n >= 9 then 0.10 else 0)
end

---------------------------------------------------------------------
-- AUXILIARES
---------------------------------------------------------------------
local function round4(x: number): number
	return math.floor(x * 10000 + 0.5) / 10000
end

function GearCatalog.TierMult(tier: number): number
	return 1 + GearCatalog.TIER_STEP * (tier - 1)
end

-- Tramo de equipo que corresponde a un nivel (el más alto con ReqLevel <= nivel)
function GearCatalog.TierOfLevel(level: number): number
	local tier = 1
	for i, req in ipairs(GearCatalog.TierLevels) do
		if level >= req then
			tier = i
		end
	end
	return tier
end

-- Estilos de arma distintos que existen para un rol (según facción)
function GearCatalog.StylesForRole(role: string): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	for _, faction in ipairs(GearCatalog.Factions) do
		local style = GearCatalog.WeaponStyle[faction][role]
		if style and not seen[style] then
			seen[style] = true
			table.insert(out, style)
		end
	end
	table.sort(out)
	return out
end

function GearCatalog.SetPieceId(role: string, slot: string, style: string?, tier: number, rarity: string): string
	local slotKey = if slot == "Arma" then "Arma" .. tostring(style) else slot
	return string.format("G_%s_%s_%d_%s", role, slotKey, tier, rarity)
end
function GearCatalog.JewelId(slot: string, focus: string, tier: number, rarity: string): string
	return string.format("J_%s_%s_%d_%s", slot, focus, tier, rarity)
end
function GearCatalog.EmblemId(faction: string, tier: number, rarity: string): string
	return string.format("F_%s_%d_%s", faction, tier, rarity)
end

local function budget(tier: number, rarity: string): number
	return GearCatalog.BASE_SET_BUDGET * GearCatalog.TierMult(tier) * GearCatalog.RarityMult[rarity]
end

function GearCatalog.SetPieceGear(role: string, slot: string, tier: number, rarity: string): Gear
	local base = budget(tier, rarity) * GearCatalog.RoleScale[role] * (GearCatalog.PieceShare[slot] or GearCatalog.ClassExtraShare[slot])
	local gear: Gear = {}
	for stat, w in pairs(GearCatalog.RoleWeights[role]) do
		gear[stat] = round4(base * w)
	end
	return gear
end

function GearCatalog.JewelGear(slot: string, focus: string, tier: number, rarity: string): Gear
	local base = budget(tier, rarity) * GearCatalog.JewelryShare[slot]
	local gear: Gear = {}
	local second = if focus == "Vida" then "Defensa" else "Vida"
	gear[focus] = round4(base * 0.70 * GearCatalog.FocusMult[focus])
	gear[second] = round4(base * 0.30)
	return gear
end

function GearCatalog.EmblemGear(tier: number, rarity: string): Gear
	local base = budget(tier, rarity) * GearCatalog.EmblemShare
	local gear: Gear = {}
	for stat, w in pairs(GearCatalog.EmblemWeights) do
		gear[stat] = round4(base * w)
	end
	return gear
end

-- Índice de Poder de un conjunto de bonos para un rol (1.00 = sin equipo)
function GearCatalog.PowerGain(role: string, g: Gear): number
	local crit = math.min(g.Critico or 0, GearCatalog.CRIT_CAP)
	local off = (1 + (g.Ataque or 0)) * (1 + (GearCatalog.CRIT_MULT - 1) * crit)
	local def = (1 + (g.Vida or 0)) / (1 - math.min(g.Defensa or 0, GearCatalog.DEFENSE_CAP))
	local heal = 1 + (g.Curacion or 0)
	local mix = GearCatalog.RoleMix[role]
	return off ^ mix[1] * def ^ mix[2] * heal ^ mix[3]
end

-- Suma de las 4 piezas del set de un rol
function GearCatalog.FullSetGear(role: string, tier: number, rarity: string): Gear
	local total: Gear = {}
	for slot in pairs(GearCatalog.PieceShare) do
		for stat, v in pairs(GearCatalog.SetPieceGear(role, slot, tier, rarity)) do
			total[stat] = (total[stat] or 0) + v
		end
	end
	return total
end

-- Dispersión del poder del set completo entre los 6 roles en varios puntos (tramo, rareza). Debe ser <= 3%.
function GearCatalog.ValidateBalance(): (boolean, string)
	local worst = 0
	local lines: { string } = {}
	for _, tier in ipairs({ 1, 6, 11 }) do
		for _, rarity in ipairs({ "Comun", "Epico", "Mitico" }) do
			local lo: number, hi: number = math.huge, 0
			for _, role in ipairs(GearCatalog.Roles) do
				local pg = GearCatalog.PowerGain(role, GearCatalog.FullSetGear(role, tier, rarity))
				lo, hi = math.min(lo, pg), math.max(hi, pg)
			end
			local spread = hi / lo - 1
			worst = math.max(worst, spread)
			table.insert(lines, string.format("tramo %2d %-10s %.3f-%.3f (%.1f%%)", tier, rarity, lo, hi, spread * 100))
		end
	end
	return worst <= 0.03, string.format("dispersión máxima %.2f%%\n%s", worst * 100, table.concat(lines, "\n"))
end

-- ¿Puede este jugador equipar el objeto? (nivel, rol, facción y arma propia de su clase)
function GearCatalog.CanUse(item: { [string]: any }, faction: string, role: string, level: number): (boolean, string?)
	local req = item.ReqLevel
	if typeof(req) == "number" and level < req then
		return false, "Necesitas nivel " .. tostring(req)
	end
	local itemRole = item.Role
	if typeof(itemRole) == "string" and itemRole ~= role then
		return false, "Solo para " .. itemRole
	end
	local itemFaction = item.Faction
	if typeof(itemFaction) == "string" and itemFaction ~= faction then
		return false, "Solo para " .. (GearCatalog.FactionDisplay[itemFaction] or itemFaction)
	end
	if typeof(itemRole) == "string" and item.Slot == "Arma" and typeof(item.Style) == "string" then
		local byFaction = GearCatalog.WeaponStyle[faction]
		local want = if byFaction then byFaction[role] else nil
		if want and want ~= item.Style then
			return false, "Tu personaje no usa esa arma"
		end
	end
	return true, nil
end

---------------------------------------------------------------------
-- GENERACIÓN DE OBJETOS
---------------------------------------------------------------------
local function describe(prefix: string, gear: Gear): string
	local parts: { string } = { prefix }
	for _, stat in ipairs(GearCatalog.Stats) do
		local v = gear[stat]
		if v then
			table.insert(parts, string.format("%s +%.1f%%", GearCatalog.StatDisplay[stat], v * 100))
		end
	end
	return table.concat(parts, " · ")
end

GearCatalog.Items = {} :: { [string]: { [string]: any } }
local Items = GearCatalog.Items

-- Variantes de una pieza: el arma tiene una por estilo que usa el rol (según facción); las demás piezas una sola
local function variantsFor(role: string, slot: string): { { Style: string? } }
	local list: { { Style: string? } } = {}
	if slot == "Arma" then
		for _, style in ipairs(GearCatalog.StylesForRole(role)) do
			table.insert(list, { Style = style })
		end
	else
		table.insert(list, { Style = nil })
	end
	return list
end

for tier, req in ipairs(GearCatalog.TierLevels) do
	local tierName = GearCatalog.TierNames[tier]
	for _, rarity in ipairs(GearCatalog.Rarities) do
		-- Set de clase
		for _, role in ipairs(GearCatalog.Roles) do
			for slot in pairs(GearCatalog.PieceShare) do
				for _, variant in ipairs(variantsFor(role, slot)) do
					local styleName = variant.Style
					local gear = GearCatalog.SetPieceGear(role, slot, tier, rarity)
					local pieceName = if styleName then GearCatalog.WeaponNames[styleName] else GearCatalog.PieceNames[slot]
					local weight = GearCatalog.Weights[role]
					local theme = GearCatalog.ThemeOfTier(weight, tier)
					local artPiece = if styleName then "arma_" .. string.lower(styleName) else string.lower(({ Armadura = "armadura", Casco = "casco", Zapatos = "botas" } :: any)[slot])
					Items[GearCatalog.SetPieceId(role, slot, styleName, tier, rarity)] = {
						Name = string.format("%s %s [%s]", pieceName, theme.Name, tierName),
						Theme = theme.Id,
						Weight = weight,
						ArtKey = string.format("%s/%s/%s", weight, theme.Id, artPiece),
						Slot = slot,
						Rarity = rarity,
						Style = styleName,
						Gear = gear,
						ReqLevel = req,
						Role = role,
						Set = role,
						Tier = tier,
						Kind = "Set",
						Desc = describe(string.format("Nv %d · Solo %s", req, role), gear),
					}
				end
			end
		end
		-- Piezas de clase extra: Escudo, Cinturón, Capa (solo su rol; no cuentan para el bono de set)
		for _, role in ipairs(GearCatalog.Roles) do
			for _, slot in ipairs(GearCatalog.ClassExtraOrder) do
				local gear = GearCatalog.SetPieceGear(role, slot, tier, rarity)
				local pieceName = if slot == "Escudo" then GearCatalog.ShieldNames[role] else GearCatalog.ExtraNames[slot]
				local weight = GearCatalog.Weights[role]
				local theme = GearCatalog.ThemeOfTier(weight, tier)
				local artPiece = if slot == "Escudo" then "escudo_" .. string.lower(role) elseif slot == "Cinturon" then "cinturon" else "capa"
				Items[GearCatalog.SetPieceId(role, slot, nil, tier, rarity)] = {
					Name = string.format("%s %s [%s]", pieceName, theme.Name, tierName),
					Theme = theme.Id,
					Weight = weight,
					ArtKey = string.format("%s/%s/%s", weight, theme.Id, artPiece),
					Slot = slot,
					Rarity = rarity,
					Gear = gear,
					ReqLevel = req,
					Role = role,
					Tier = tier,
					Kind = "ClassPiece",
					Desc = describe(string.format("Nv %d · Solo %s", req, role), gear),
				}
			end
		end
		-- Joyas universales
		for slot in pairs(GearCatalog.JewelryShare) do
			for _, focus in ipairs(GearCatalog.JewelFocus) do
				local gear = GearCatalog.JewelGear(slot, focus, tier, rarity)
				Items[GearCatalog.JewelId(slot, focus, tier, rarity)] = {
					Name = string.format("%s de %s [%s]", GearCatalog.JewelNames[slot], GearCatalog.JewelFocusName[focus], tierName),
					Slot = slot,
					Rarity = rarity,
					Gear = gear,
					ReqLevel = req,
					Tier = tier,
					Kind = "Jewel",
					ArtKey = string.format("joyas/%s_%s", string.lower(slot), string.lower(focus)),
					Desc = describe(string.format("Nv %d · Todas las clases", req), gear),
				}
			end
		end
	end
	-- Emblemas de facción (solo rarezas altas)
	for _, rarity in ipairs(GearCatalog.EmblemRarities) do
		for _, faction in ipairs(GearCatalog.Factions) do
			local gear = GearCatalog.EmblemGear(tier, rarity)
			Items[GearCatalog.EmblemId(faction, tier, rarity)] = {
				Name = string.format("%s [%s]", GearCatalog.EmblemNames[faction], tierName),
				Slot = "Accesorio1",
				Rarity = rarity,
				Gear = gear,
				ReqLevel = req,
				Faction = faction,
				Tier = tier,
				Kind = "Emblem",
				ArtKey = "emblemas/emblema_" .. string.lower(faction),
				Desc = describe(string.format("Nv %d · Solo %s", req, GearCatalog.FactionDisplay[faction]), gear),
			}
		end
	end
end

return GearCatalog
