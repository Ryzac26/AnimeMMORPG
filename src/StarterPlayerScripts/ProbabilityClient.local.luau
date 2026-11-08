--!strict
--[[
    ProbabilityClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > ProbabilityClient
    Ventana "PROBABILIDADES": muestra las tasas REALES del juego (botín de monstruos, jefes, Metin, cofres, huevos de monturas,
    mejora del equipo y desmontaje). No tiene números propios: lee los mismos catálogos que usa el servidor
    (LootTables, MetinCatalog, MountCatalog, EnhanceCatalog, AlchemyCatalog), así que si rebalanceas, esta ventana se actualiza sola.
    Se abre desde Ajustes ("Ver probabilidades") con MenuBus "Probs". IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))
local LootTables: any = require(Modules:WaitForChild("LootTables", 10))
local MetinCatalog: any = require(Modules:WaitForChild("MetinCatalog", 10))
local MountCatalog: any = require(Modules:WaitForChild("MountCatalog", 10))
local EnhanceCatalog: any = require(Modules:WaitForChild("EnhanceCatalog", 10))
local AlchemyCatalog: any = require(Modules:WaitForChild("AlchemyCatalog", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "ProbabilityGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil
local selected = "mob"

local RARITIES = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
local RARITY_NAME: { [string]: string } = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legendario", Mitico = "Mítico" }
local RARITY_COLOR: { [string]: Color3 } = {
	Comun = Color3.fromRGB(205, 205, 212),
	Raro = Color3.fromRGB(90, 165, 255),
	Epico = Color3.fromRGB(190, 105, 255),
	Legendario = Color3.fromRGB(255, 176, 50),
	Mitico = Color3.fromRGB(255, 85, 120),
}

---------------------------------------------------------------------
-- Formato
---------------------------------------------------------------------
local function pct(x: number): string
	-- x en 0..100 -> "12,5 %" (hasta 3 decimales, sin ceros sobrantes)
	local s: string
	if x >= 10 then
		s = string.format("%.1f", x)
	elseif x >= 1 then
		s = string.format("%.2f", x)
	else
		s = string.format("%.3f", x)
	end
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return (s:gsub("%.", ",")) .. " %"
end

local function frac(x: number): string -- 0..1 -> %
	return pct(x * 100)
end

local function range(r: { number }): string
	if r[1] == r[2] then
		return tostring(r[1])
	end
	return string.format("%d a %d", r[1], r[2])
end

local function normalized(weights: { [string]: number }): { [string]: number }
	local total = 0
	for _, w in pairs(weights) do
		total += w
	end
	local out: { [string]: number } = {}
	for k, w in pairs(weights) do
		out[k] = if total > 0 then w / total * 100 else 0
	end
	return out
end

---------------------------------------------------------------------
-- Bloques de contenido
---------------------------------------------------------------------
type Cell = { Text: string, Color: Color3? }
type Block = { Kind: string, Text: string?, Cols: { string }?, Rows: { { Cell } }? }

local function H(text: string): Block
	return { Kind = "h", Text = text }
end
local function P(text: string): Block
	return { Kind = "p", Text = text }
end
local function T(cols: { string }, rows: { { Cell } }): Block
	return { Kind = "t", Cols = cols, Rows = rows }
end
local function cell(text: string, color: Color3?): Cell
	return { Text = text, Color = color }
end
local function kv(label: string, value: string): { Cell }
	return { cell(label), cell(value) }
end

-- tabla "rareza x franja": byStrip[i] = { Comun = peso, ... }
local function rarityByStrip(byStrip: { { [string]: number } }): Block
	local rows: { { Cell } } = {}
	local norm: { { [string]: number } } = {}
	for i, w in ipairs(byStrip) do
		norm[i] = normalized(w)
	end
	for _, r in ipairs(RARITIES) do
		local any = false
		local row: { Cell } = { cell(RARITY_NAME[r], RARITY_COLOR[r]) }
		for i = 1, #byStrip do
			local v = norm[i][r]
			if v and v > 0 then
				any = true
				table.insert(row, cell(pct(v)))
			else
				table.insert(row, cell("—", Color3.fromRGB(120, 120, 130)))
			end
		end
		if any then
			table.insert(rows, row)
		end
	end
	local cols = { "Rareza" }
	for i = 1, #byStrip do
		table.insert(cols, "Franja " .. i)
	end
	return T(cols, rows)
end

local function rarityList(weights: { [string]: number }): Block
	local norm = normalized(weights)
	local rows: { { Cell } } = {}
	for _, r in ipairs(RARITIES) do
		if norm[r] and norm[r] > 0 then
			table.insert(rows, { cell(RARITY_NAME[r], RARITY_COLOR[r]), cell(pct(norm[r])) })
		end
	end
	return T({ "Rareza", "Probabilidad" }, rows)
end

local function perStrip(label: string, values: { number }): { Cell }
	local row: { Cell } = { cell(label) }
	for _, v in ipairs(values) do
		table.insert(row, cell(frac(v)))
	end
	return row
end

local function stripCols(first: string): { string }
	return { first, "Franja 1", "Franja 2", "Franja 3", "Franja 4" }
end

---------------------------------------------------------------------
-- Secciones
---------------------------------------------------------------------
type Section = { Id: string, Title: string, Build: () -> { Block } }

local SECTIONS: { Section } = {
	{
		Id = "mob", Title = "👹 Monstruos",
		Build = function()
			local m = LootTables.Mob
			local iw = normalized(m.ItemWeights)
			local blocks: { Block } = {
				H("Cada monstruo que derrotas"),
				P("El botín es personal: necesitas haber hecho al menos el " .. frac(m.MinShare) .. " del daño. Los monstruos normales nunca sueltan equipo Mítico."),
				T({ "Premio", "Probabilidad" }, {
					kv("Objeto (consumible o material)", frac(m.ItemChance)),
					kv("   · si cae objeto: consumible", pct(iw.Consumible or 0)),
					kv("   · si cae objeto: material", pct(iw.Material or 0)),
					kv("Gema Menor (mejora +1 a +5)", frac(m.MinorGemChance)),
					kv("Mascota", frac(m.PetChance)),
					kv("Llave de cofre (con tope diario)", frac(LootTables.KeyDrop.Mob)),
				}),
				H("Equipo: probabilidad de que caiga"),
				T(stripCols("Dato"), { perStrip("Equipo por kill", m.GearChanceByStrip) }),
				H("Equipo: rareza si cae"),
				rarityByStrip(m.GearRarity),
				H("Mascota: rareza si cae"),
				rarityList(m.PetRarity),
				P("Las 4 facciones comparten estas tablas: no dependen de tu facción."),
			}
			return blocks
		end,
	},
	{
		Id = "mini", Title = "⚔ Mini jefes",
		Build = function()
			local m = LootTables.MiniBoss
			return {
				H("Mini jefe de franja"),
				P("Premio personal para quien haga al menos el " .. frac(m.MinShare) .. " del daño. Hay un tope diario por franja."),
				T(stripCols("Dato"), {
					perStrip("Equipo", m.GearChance),
				}),
				T({ "Premio", "Probabilidad" }, {
					kv("Gema Menor", frac(m.GemChance)),
					kv("Mascota", frac(m.PetChance)),
					kv("Llave de cofre", frac(LootTables.KeyDrop.Mini)),
					kv("Material de franja (garantizado)", range(m.StripCount)),
					kv("Fragmentos de armadura (garantizado)", range(m.FragmentCount)),
				}),
				H("Equipo: rareza si cae"),
				rarityByStrip(m.GearRarity),
				H("Mascota: rareza si cae"),
				rarityList(m.PetRarity),
			}
		end,
	},
	{
		Id = "elite", Title = "👑 Jefes élite",
		Build = function()
			local e = LootTables.EliteBoss
			return {
				H("Jefes de franja (niveles 25 / 50 / 75 / 100)"),
				P(string.format("Sorteo entre quienes participaron: ganan el %s de los participantes (mínimo %d, máximo %d). Todos reciben material y fragmentos garantizados. Cada sorteo perdido suma boletos (protección contra mala racha).", frac(e.WinnerFraction), e.MinWinners, e.MaxWinners)),
				T({ "Premio garantizado", "Cantidad" }, {
					kv("Material de franja", range(e.StripCount)),
					kv("Fragmentos de armadura", range(e.FragmentCount)),
				}),
				H("Equipo del sorteo: rareza"),
				rarityByStrip(e.PrizeRarity),
				T({ "Premio extra", "Probabilidad" }, { kv("Mascota", frac(e.PetChance)) }),
				H("Mascota: rareza si cae"),
				rarityList(e.PetRarity),
			}
		end,
	},
	{
		Id = "world", Title = "🐉 Jefe mundial",
		Build = function()
			local w = LootTables.WorldBoss
			return {
				H("Jefe mundial"),
				P(string.format("Sorteo entre quienes participaron: ganan el %s (mínimo %d, máximo %d). Todos reciben Escamas del Titán (%s).", frac(w.WinnerFraction), w.MinWinners, w.MaxWinners, range(w.ScaleCount))),
				H("Equipo del sorteo: rareza"),
				rarityList(w.PrizeRarity),
				T({ "Premio extra", "Probabilidad" }, { kv("Mascota", frac(w.PetChance)) }),
				H("Mascota: rareza si cae"),
				rarityList(w.PetRarity),
			}
		end,
	},
	{
		Id = "metin", Title = "💎 Piedras Metin",
		Build = function()
			local m = LootTables.Metin
			local weights: { [string]: number } = {}
			local names: { [string]: string } = {}
			for _, r in ipairs(MetinCatalog.Rarities) do
				weights[r.Id] = r.Weight
				names[r.Id] = r.Name
			end
			local norm = normalized(weights)
			local spawn: { { Cell } } = {}
			for _, r in ipairs(MetinCatalog.Rarities) do
				table.insert(spawn, { cell(r.Name, r.Color), cell(pct(norm[r.Id] or 0)), cell("Nv. " .. tostring(r.Level)) })
			end
			local blocks: { Block } = {
				H("Qué piedra aparece"),
				T({ "Piedra", "Aparición", "Nivel" }, spawn),
				H("Al destruirla (por jugador con al menos " .. frac(m.MinShare) .. " del daño)"),
				T({ "Premio", "Probabilidad" }, {
					kv("Gema Mayor", frac(m.GemChance)),
					kv("Cofre (tirada extra de equipo)", frac(m.ChestChance)),
					kv("Emblema de tu facción", frac(m.EmblemChance)),
					kv("Mascota", frac(m.PetChance)),
				}),
			}
			for _, r in ipairs(MetinCatalog.Rarities) do
				local d = m.Rarities[r.Id]
				if d then
					table.insert(blocks, H("Piedra " .. r.Name))
					table.insert(blocks, P("Gemas Mayores: " .. range(d.GemCount)))
					table.insert(blocks, T({ "Cofre: rareza", "Prob.", "Emblema: rareza", "Prob." }, (function()
						local cn, en = normalized(d.ChestRarity), normalized(d.EmblemRarity)
						local rows: { { Cell } } = {}
						for _, k in ipairs(RARITIES) do
							if (cn[k] or 0) > 0 or (en[k] or 0) > 0 then
								table.insert(rows, {
									cell(if (cn[k] or 0) > 0 then RARITY_NAME[k] else "", RARITY_COLOR[k]),
									cell(if (cn[k] or 0) > 0 then pct(cn[k]) else ""),
									cell(if (en[k] or 0) > 0 then RARITY_NAME[k] else "", RARITY_COLOR[k]),
									cell(if (en[k] or 0) > 0 then pct(en[k]) else ""),
								})
							end
						end
						return rows
					end)()))
				end
			end
			return blocks
		end,
	},
	{
		Id = "chest", Title = "🧰 Cofres y altares",
		Build = function()
			local c, o, ch = LootTables.MapChest, LootTables.Offering, LootTables.Challenge
			return {
				H("Cofre del mapa (se abre con llave)"),
				T(stripCols("Dato"), {
					perStrip("Equipo", c.GearChance),
					perStrip("Cofre mejorado (+1 a +3, sube 1 rareza)", c.UpgradedChance),
				}),
				T({ "Premio", "Probabilidad" }, { kv("Gema Menor", frac(c.GemChance)) }),
				rarityByStrip(c.GearRarity),
				H("Altar de ofrenda (equipo)"),
				rarityByStrip(o.GearRarity),
				H("Altar de desafío"),
				T(stripCols("Dato"), { perStrip("Equipo", ch.GearChance) }),
				T({ "Premio", "Probabilidad" }, {
					kv("Gema Menor", frac(ch.GemChance)),
					kv("Mascota", frac(ch.PetChance)),
				}),
				rarityByStrip(ch.GearRarity),
				H("Mascota (desafío): rareza si cae"),
				rarityList(ch.PetRarity),
			}
		end,
	},
	{
		Id = "egg", Title = "🥚 Huevos de monturas",
		Build = function()
			local rows: { { Cell } } = {}
			for _, egg in ipairs(MountCatalog.Eggs) do
				local row: { Cell } = { cell(egg.Name, RARITY_COLOR[egg.Rarity]) }
				for i = 1, 5 do
					local v = egg.Odds[i] or 0
					table.insert(row, cell(if v > 0 then pct(v) else "—", if v > 0 then nil else Color3.fromRGB(120, 120, 130)))
				end
				table.insert(row, cell(string.format("%d h", egg.Hours)))
				table.insert(rows, row)
			end
			local pity = MountCatalog.Pity
			return {
				H("Rareza de la montura según el huevo"),
				T({ "Huevo", "Común", "Raro", "Épico", "Legend.", "Mítico", "Incuba" }, rows),
				H("Garantía (mala racha)"),
				P(string.format("Si abres %d huevos seguidos sin conseguir Raro o mejor, el siguiente lo trae. Igual con Épico a los %d y Legendario a los %d.", pity.Raro, pity.Epico, pity.Legendario)),
			}
		end,
	},
	{
		Id = "enh", Title = "🔨 Mejora de equipo",
		Build = function()
			local rows: { { Cell } } = {}
			for n = 1, EnhanceCatalog.MaxPlus do
				local drop = EnhanceCatalog.FailDrop[n] or 0
				local brk = EnhanceCatalog.BreakChance[n] or 0
				local onFail = if brk > 0 then string.format("%s se rompe, si no baja %d", frac(brk), drop) elseif drop > 0 then string.format("baja %d", drop) else "no pasa nada"
				table.insert(rows, {
					cell("+" .. n),
					cell(frac(EnhanceCatalog.SuccessRate[n] or 0)),
					cell(tostring(EnhanceCatalog.Gems[n] or 0) .. (if n <= EnhanceCatalog.MinorGemMaxTarget then " menor" else " mayor")),
					cell(onFail),
				})
			end
			return {
				H("Éxito al intentar llegar a +n"),
				T({ "Mejora", "Éxito", "Gemas", "Si falla" }, rows),
				P("Con el Pergamino de Protección, en +7, +8 y +9 la pieza no baja ni se rompe al fallar (el pergamino se gasta). El equipo nunca se rompe antes de +7."),
			}
		end,
	},
	{
		Id = "dis", Title = "♻ Desmontar",
		Build = function()
			local rows: { { Cell } } = {}
			for _, r in ipairs(RARITIES) do
				local d = AlchemyCatalog.Dismantle[r]
				if d then
					table.insert(rows, {
						cell(RARITY_NAME[r], RARITY_COLOR[r]),
						cell(range(d.Mat)),
						cell(tostring(d.Frag)),
						cell(if d.Gem > 0 then frac(d.Gem) else "—"),
					})
				end
			end
			return {
				H("Al desmontar una pieza de equipo"),
				T({ "Rareza", "Materiales", "Fragmentos", "Gema Menor" }, rows),
				P(string.format("Cada %d niveles de mejora (+%d, +%d…) suman 1 fragmento más.", AlchemyCatalog.PlusFragEvery, AlchemyCatalog.PlusFragEvery, AlchemyCatalog.PlusFragEvery * 2)),
			}
		end,
	},
	{
		Id = "luck", Title = "🍀 Suerte y notas",
		Build = function()
			return {
				H("Suerte de botín"),
				P("La Suerte (por ejemplo la del Zorro de la Suerte o el Lobo Sombra) multiplica las probabilidades de objetos, equipo, gemas y mascotas. No afecta al oro ni a lo garantizado."),
				H("Cómo leer esta ventana"),
				P("Las probabilidades son por intento y siempre sobre las tablas reales del juego. Las rarezas se reparten entre sí: por ejemplo, en la tabla de rareza de equipo todas las filas suman 100 %."),
				P("Los premios garantizados (material, fragmentos, Escamas) no dependen de la suerte."),
			}
		end,
	},
}

---------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------
local function renderBlocks(scroll: ScrollingFrame, blocks: { Block }, pal: { [string]: Color3 }, width: number)
	local y = 4
	for _, b in ipairs(blocks) do
		if b.Kind == "h" then
			y += 8
			local l = UITheme.Text(scroll, b.Text or "", 15, pal.Accent, UDim2.fromOffset(8, y), UDim2.fromOffset(width - 16, 22))
			l.TextStrokeTransparency = 1
			l.Font = Enum.Font.GothamBold
			y += 26
		elseif b.Kind == "p" then
			local l = UITheme.Text(scroll, b.Text or "", 12, pal.Muted, UDim2.fromOffset(8, y), UDim2.fromOffset(width - 16, 16))
			l.TextStrokeTransparency = 1
			l.TextWrapped = true
			l.TextYAlignment = Enum.TextYAlignment.Top
			local lines = math.max(1, math.ceil(#(b.Text or "") * 6.4 / (width - 24)))
			l.Size = UDim2.fromOffset(width - 16, lines * 16)
			y += lines * 16 + 6
		elseif b.Kind == "t" then
			local cols = b.Cols or {}
			local rows = b.Rows or {}
			local n = #cols
			local firstW = if n <= 2 then (width - 16) * 0.62 else (width - 16) * (if n >= 6 then 0.26 else 0.34)
			local restW = (width - 16 - firstW) / math.max(n - 1, 1)
			local function colX(i: number): number
				return if i == 1 then 0 else firstW + (i - 2) * restW
			end
			local function colW(i: number): number
				return if i == 1 then firstW else restW
			end
			local head = NpcKit.Panel(scroll, UITheme.For(player:GetAttribute("Faction")), UDim2.fromOffset(width - 16, 24), UDim2.fromOffset(8, y), "inset")
			for i, name in ipairs(cols) do
				local l = UITheme.Text(head, name, 11, pal.Text, UDim2.fromOffset(colX(i) + 8, 0), UDim2.fromOffset(colW(i) - 12, 24), if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right)
				l.TextStrokeTransparency = 1
				l.Font = Enum.Font.GothamBold
			end
			y += 26
			for ri, row in ipairs(rows) do
				local bg = Instance.new("Frame")
				bg.Position = UDim2.fromOffset(8, y)
				bg.Size = UDim2.fromOffset(width - 16, 24)
				bg.BackgroundColor3 = pal.Inset
				bg.BackgroundTransparency = if ri % 2 == 0 then 0.6 else 1
				bg.BorderSizePixel = 0
				bg.Parent = scroll
				for i, c in ipairs(row) do
					local l = UITheme.Text(bg, c.Text, 13, c.Color or pal.Text, UDim2.fromOffset(colX(i) + 8, 0), UDim2.fromOffset(colW(i) - 12, 24), if i == 1 then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right)
					l.TextStrokeTransparency = 1
					l.TextTruncate = Enum.TextTruncate.AtEnd
					if i == 1 then
						l.Font = Enum.Font.GothamBold
					end
				end
				y += 24
			end
			y += 6
		end
	end
	scroll.CanvasSize = UDim2.fromOffset(0, y + 16)
end

local function build()
	if win then
		win:Destroy()
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local WW, HH = 900, 600
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Probabilidades",
		"Las tasas reales del juego, siempre al día", "📊", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Probs", 40, 50)

	-- lista de secciones (izquierda)
	local sideW = 200
	for i, s in ipairs(SECTIONS) do
		NpcKit.Tab(w, theme, s.Title, UDim2.fromOffset(sideW - 12, 34), UDim2.fromOffset(12, NpcKit.TOP + (i - 1) * 40), selected == s.Id, function()
			selected = s.Id
			build()
		end)
	end

	-- contenido (derecha)
	local contentW = WW - sideW - 36
	local holder = NpcKit.Panel(w, theme, UDim2.fromOffset(contentW, HH - NpcKit.TOP - 16), UDim2.fromOffset(sideW + 14, NpcKit.TOP), "card")
	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(4, 4)
	scroll.Size = UDim2.new(1, -8, 1, -8)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = pal.Edge
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Parent = holder

	local blocks: { Block } = {}
	for _, s in ipairs(SECTIONS) do
		if s.Id == selected then
			local ok, res = pcall(s.Build)
			if ok then
				blocks = res :: { Block }
			else
				blocks = { H("No se pudo cargar esta sección"), P(tostring(res)) }
			end
		end
	end
	renderBlocks(scroll, blocks, pal, contentW - 20)
end

MenuBus.Event:Connect(function(name: string)
	if name == "Probs" then
		if gui.Enabled then
			gui.Enabled = false
		else
			build()
			gui.Enabled = true
		end
	end
end)

build()
