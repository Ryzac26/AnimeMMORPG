--!strict
--[[
    RecruitClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > RecruitClient
    Ventana del RECLUTADOR (el NPC junto al Instructor de tu ciudad): gasta CUPONES para reclutar ayudantes de combate de TU facción.
      - Elige el cupón (Común · Raro · Épico · Legendario · Mítico): cada uno tiene su tabla de probabilidades EN % y su garantía.
      - Reclutar x1 o x10. Los repetidos suben estrellas (máx. 5) y después dan Esencia.
      - Los cupones llegan a la carta ✉ (debajo de «Reportar»): reclámalos allí, o aquí con «Reclamar de la carta».
      - Canjear mascotas viejas: cada una se cambia por 1 cupón de su misma rareza.
    Todo lo decide el servidor (HelperService). Remote de apertura: RecruitOpen (nombre, título, facción).
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local HelperCatalog = require(Modules:WaitForChild("HelperCatalog", 10))
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local Inv = require(script.Parent:WaitForChild("InventoryStore", 10))
local Store = require(script.Parent:WaitForChild("HelperStore", 10))
local HelperPortrait = require(script.Parent:WaitForChild("HelperPortrait", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "RecruitGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 13
gui.Parent = player:WaitForChild("PlayerGui", 10)

local W, H = 660, 570
local win: Frame? = nil
local npcName, npcTitle = "Reclutador", "Reclutador de ayudantes"
local coupon = "Comun"
local lastResult: any = nil -- última tirada, se muestra encima hasta aceptar
local build: () -> ()

local function label(parent: Instance, text: string, size: number, color: Color3?, x: number, y: number, w: number, h: number, align: Enum.TextXAlignment?): TextLabel
	local l = UITheme.Text(parent, text, size, color, UDim2.fromOffset(x, y), UDim2.fromOffset(w, h), align)
	l.TextStrokeTransparency = 1
	return l
end

local function pct(v: number): string
	if v <= 0 then
		return "—"
	end
	return string.format("%g%%", math.floor(v * 100 + 0.5) / 100)
end

local function oldPets(): number
	local n = 0
	for _, stack in pairs(Inv.Bag) do
		local item: any = (ItemCatalog.Items :: any)[stack.Id]
		if item and item.Pet then
			n += stack.Count
		end
	end
	for _, slot in ipairs({ "Accesorio2", "Accesorio3" }) do
		local id = Inv.Equip[slot]
		local item: any = if id then (ItemCatalog.Items :: any)[id] else nil
		if item and item.Pet then
			n += 1
		end
	end
	return n
end

local function close()
	gui.Enabled = false
	lastResult = nil
	Store.Action("Close")
end

---------------------------------------------------------------------
-- Resultado del reclutamiento (tarjetas que se van revelando)
---------------------------------------------------------------------
local function drawResult(w: Frame, theme: any, pal: { [string]: Color3 })
	local r = lastResult
	local over = NpcKit.Panel(w, theme, UDim2.fromOffset(W - 28, H - 92), UDim2.fromOffset(14, 76), "inset")
	over.ZIndex = 20
	local results: { any } = r.Results
	local best = 1
	for _, it in ipairs(results) do
		best = math.max(best, HelperCatalog.RarityIndex[it.Rarity] or 1)
	end
	local titleColor = HelperCatalog.RarityColor[HelperCatalog.Rarities[best]]
	local t = label(over, if #results == 1 then "¡Reclutamiento!" else "¡Reclutamiento x" .. #results .. "!", 22, titleColor, 0, 8, W - 28, 28, Enum.TextXAlignment.Center)
	t.ZIndex = 21
	local cols = if #results == 1 then 1 else 5
	local cw, ch = 118, 168
	local startX = ((W - 28) - (cols * (cw + 8) - 8)) / 2
	local startY = if #results == 1 then 54 else 46
	for i, it in ipairs(results) do
		local parsed = HelperCatalog.Parse(it.Id)
		if parsed then
			local col = HelperCatalog.RarityColor[it.Rarity]
			local cx = startX + ((i - 1) % cols) * (cw + 8)
			local cy = startY + math.floor((i - 1) / cols) * (ch + 8)
			local card = NpcKit.Panel(over, theme, UDim2.fromOffset(cw, ch), UDim2.fromOffset(cx, cy), "card")
			card.ZIndex = 22
			local stroke = Instance.new("UIStroke")
			stroke.Color = col
			stroke.Thickness = 2
			stroke.Parent = card
			local vp = HelperPortrait.Build(card, parsed, UDim2.fromOffset(cw - 8, 92), UDim2.fromOffset(4, 4), {})
			vp.ZIndex = 23
			label(card, HelperCatalog.NameOf(parsed), 13, col, 2, 98, cw - 4, 16, Enum.TextXAlignment.Center).ZIndex = 24
			label(card, string.format("%s %s", HelperCatalog.RoleIcon[parsed.Role] or "", parsed.Role), 10, pal.FMuted, 2, 114, cw - 4, 12, Enum.TextXAlignment.Center).ZIndex = 24
			label(card, HelperCatalog.RarityName[it.Rarity], 10, col, 2, 126, cw - 4, 12, Enum.TextXAlignment.Center).ZIndex = 24
			local info: string
			local infoColor = pal.FText
			if it.New then
				info = "¡NUEVO!"
				infoColor = Color3.fromRGB(120, 235, 140)
			elseif it.Essence and it.Essence > 0 then
				info = string.format("Repetido  +%d Esencia", it.Essence)
				infoColor = Color3.fromRGB(255, 215, 90)
			else
				info = string.format("Repetido  %s", string.rep("★", it.Stars))
				infoColor = Color3.fromRGB(255, 200, 90)
			end
			label(card, info, 11, infoColor, 2, 144, cw - 4, 16, Enum.TextXAlignment.Center).ZIndex = 24
			-- aparición escalonada
			card.BackgroundTransparency = 1
			for _, d in ipairs(card:GetDescendants()) do
				if d:IsA("TextLabel") then
					d.TextTransparency = 1
				elseif d:IsA("ViewportFrame") then
					d.ImageTransparency = 1
				end
			end
			task.delay((i - 1) * 0.14, function()
				if not card.Parent then
					return
				end
				local info2 = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				TweenService:Create(card, info2, { BackgroundTransparency = 0 }):Play()
				for _, d in ipairs(card:GetDescendants()) do
					if d:IsA("TextLabel") then
						TweenService:Create(d, info2, { TextTransparency = 0 }):Play()
					elseif d:IsA("ViewportFrame") then
						TweenService:Create(d, info2, { ImageTransparency = 0 }):Play()
					end
				end
			end)
		end
	end
	local pityLeft = ""
	local c = HelperCatalog.Coupons[r.Coupon]
	if c and c.Pity then
		pityLeft = string.format("Garantía de %s o mejor: %d / %d", HelperCatalog.RarityName[c.Pity.Min], r.Pity or 0, c.Pity.Every - 1)
	end
	label(over, pityLeft, 11, pal.FMuted, 0, H - 92 - 62, W - 28, 14, Enum.TextXAlignment.Center).ZIndex = 21
	local ok = NpcKit.Button(over, theme, "Aceptar", UDim2.fromOffset(180, 34), UDim2.fromOffset((W - 28 - 180) / 2, H - 92 - 42), "buy", function()
		lastResult = nil
		build()
	end)
	ok.ZIndex = 21
end

---------------------------------------------------------------------
-- Ventana
---------------------------------------------------------------------
build = function()
	if win then
		win:Destroy()
		win = nil
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local facKey = player:GetAttribute("Faction")
	local facName = if typeof(facKey) == "string" then (HelperCatalog.FactionName[facKey] or facKey) else ""
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(W, H), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), npcName, npcTitle .. " · ayudantes de " .. facName, "🎟", close)
	win = w
	WindowDrag.Attach(w, "Recruit", 52, 50)

	local st: any = Store.State
	if not st then
		label(w, "Cargando...", 14, pal.FMuted, 14, 100, W - 28, 20, Enum.TextXAlignment.Center)
		return
	end

	-- izquierda: cupones
	label(w, "TUS CUPONES", 13, pal.Accent, 14, 76, 230, 18)
	for i, rarity in ipairs(HelperCatalog.Rarities) do
		local def = HelperCatalog.Coupons[rarity]
		local col = HelperCatalog.RarityColor[rarity]
		local card = NpcKit.Panel(w, theme, UDim2.fromOffset(236, 58), UDim2.fromOffset(14, 98 + (i - 1) * 64), "card")
		local on = rarity == coupon
		local bar = Instance.new("Frame")
		bar.Size = UDim2.fromOffset(6, 58)
		bar.BackgroundColor3 = col
		bar.BorderSizePixel = 0
		bar.Parent = card
		label(card, def.Name, 14, col, 16, 6, 150, 18)
		local have = (st.Stock and st.Stock[rarity]) or 0
		local mail = (st.Mail and st.Mail[rarity]) or 0
		label(card, "x" .. have, 20, pal.FText, 150, 6, 80, 24, Enum.TextXAlignment.Right)
		label(card, if mail > 0 then string.format("✉ %d en la carta", mail) else "Probabilidades abajo →", 10, if mail > 0 then Color3.fromRGB(255, 215, 90) else pal.FMuted, 16, 32, 214, 14)
		local b = Instance.new("TextButton")
		b.Size = UDim2.fromScale(1, 1)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.ZIndex = 12
		b.Parent = card
		local stroke = Instance.new("UIStroke")
		stroke.Color = if on then pal.Accent else pal.Edge
		stroke.Thickness = if on then 3 else 1
		stroke.Transparency = if on then 0 else 0.5
		stroke.Parent = b
		b.Activated:Connect(function()
			coupon = rarity
			build()
		end)
	end
	-- tope diario de lo que caen de monstruos
	local dc = st.DayCount or {}
	local parts: { string } = {}
	for _, rarity in ipairs(HelperCatalog.Rarities) do
		table.insert(parts, string.format("%s %d/%d", HelperCatalog.RarityName[rarity], dc[rarity] or 0, HelperCatalog.DailyCouponCap[rarity]))
	end
	local cap = label(w, "Cupones de hoy (límite diario): " .. table.concat(parts, " · "), 10, pal.FMuted, 14, 424, 236, 40)
	cap.TextWrapped = true
	cap.TextYAlignment = Enum.TextYAlignment.Top

	-- derecha: probabilidades del cupón elegido
	local def = HelperCatalog.Coupons[coupon]
	local right = NpcKit.Panel(w, theme, UDim2.fromOffset(384, 250), UDim2.fromOffset(262, 76), "inset")
	label(right, "PROBABILIDADES · " .. def.Name, 14, HelperCatalog.RarityColor[coupon], 12, 8, 360, 18)
	for i, rarity in ipairs(HelperCatalog.Rarities) do
		local y = 34 + (i - 1) * 30
		local v = def.Odds[i]
		local rc = HelperCatalog.RarityColor[rarity]
		label(right, HelperCatalog.RarityName[rarity], 12, rc, 12, y, 90, 20)
		local back = Instance.new("Frame")
		back.Position = UDim2.fromOffset(104, y + 2)
		back.Size = UDim2.fromOffset(190, 16)
		back.BackgroundColor3 = pal.Slot
		back.BorderSizePixel = 0
		back.Parent = right
		Instance.new("UICorner", back).CornerRadius = UDim.new(0, 4)
		if v > 0 then
			local fill = Instance.new("Frame")
			fill.Size = UDim2.new(math.clamp(v / 100, 0.012, 1), 0, 1, 0)
			fill.BackgroundColor3 = rc
			fill.BorderSizePixel = 0
			fill.Parent = back
			Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)
		end
		label(right, pct(v), 13, if v > 0 then pal.FText else pal.FMuted, 300, y, 76, 20, Enum.TextXAlignment.Right)
	end
	local pityText = "Sin garantía en este cupón."
	if def.Pity then
		local cur = (st.Pity and st.Pity[coupon]) or 0
		pityText = string.format("Garantía: cada %d tiradas sin %s o mejor, la siguiente lo es. Llevas %d / %d.", def.Pity.Every, HelperCatalog.RarityName[def.Pity.Min], cur, def.Pity.Every - 1)
	end
	local pl = label(right, pityText, 11, pal.FMuted, 12, 190, 360, 52)
	pl.TextWrapped = true
	pl.TextYAlignment = Enum.TextYAlignment.Top

	-- acciones
	local have = (st.Stock and st.Stock[coupon]) or 0
	local isOpen = true
	NpcKit.Button(w, theme, string.format("Reclutar x1  (1 %s)", def.Name), UDim2.fromOffset(186, 42), UDim2.fromOffset(262, 336), if have >= 1 then "buy" else "neutral", function()
		if have >= 1 and isOpen then
			Store.Action("Recruit", coupon, 1)
		end
	end)
	NpcKit.Button(w, theme, string.format("Reclutar x%d  (%d %s)", HelperCatalog.PullsPerBatch, HelperCatalog.PullsPerBatch, def.Name), UDim2.fromOffset(190, 42), UDim2.fromOffset(456, 336), if have >= HelperCatalog.PullsPerBatch then "buy" else "neutral", function()
		if have >= HelperCatalog.PullsPerBatch and isOpen then
			Store.Action("Recruit", coupon, HelperCatalog.PullsPerBatch)
		end
	end)
	local mailTotal = 0
	for _, n in pairs(st.Mail or {}) do
		mailTotal += n
	end
	local claim = NpcKit.Button(w, theme, if mailTotal > 0 then string.format("✉ Reclamar de la carta (%d)", mailTotal) else "✉ Carta vacía", UDim2.fromOffset(384, 34), UDim2.fromOffset(262, 388), if mailTotal > 0 then "primary" else "neutral", function()
		if mailTotal > 0 then
			Store.Action("ClaimMail", "all")
		end
	end)
	claim.TextSize = 13
	local pets = oldPets()
	local ex = NpcKit.Button(w, theme, if pets > 0 then string.format("Canjear mascotas viejas (%d) por cupones", pets) else "Sin mascotas viejas para canjear", UDim2.fromOffset(384, 34), UDim2.fromOffset(262, 430), if pets > 0 then "neutral" else "neutral", function()
		if pets > 0 then
			Store.Action("ExchangePets")
		end
	end)
	ex.TextSize = 12
	ex.TextTransparency = if pets > 0 then 0 else 0.5
	local pulls = st.Pulls or 0
	label(w, string.format("Reclutamientos hechos: %d · Los repetidos suben las estrellas (máx. 5) y después dan Esencia (para ascender)", pulls), 10, pal.FMuted, 262, 474, 384, 28).TextWrapped = true
	label(w, "Los ayudantes ayudan solo en PvE; contra jugadores no atacan y sus bonos valen el 50%.", 10, pal.FMuted, 14, 500, W - 28, 16, Enum.TextXAlignment.Center)

	if lastResult then
		drawResult(w, theme, pal)
	end
end

local rebuildQueued = false
local function refresh()
	if not gui.Enabled or rebuildQueued then
		return
	end
	rebuildQueued = true
	task.delay(0.12, function()
		rebuildQueued = false
		if gui.Enabled and not lastResult then
			build()
		end
	end)
end
Store.Changed:Connect(refresh)
Inv.Changed:Connect(refresh)

Store.Result:Connect(function(r: any)
	if type(r) ~= "table" or type(r.Results) ~= "table" or #r.Results == 0 then
		return
	end
	lastResult = r
	if gui.Enabled then
		build()
	end
end)

local openRemote = ClientNet.Get("RecruitOpen")
if openRemote then
	openRemote.OnClientEvent:Connect(function(name: any, title: any)
		npcName = if typeof(name) == "string" then name else "Reclutador"
		npcTitle = if typeof(title) == "string" then title else "Reclutador de ayudantes"
		lastResult = nil
		Store.Action("State")
		build()
		gui.Enabled = true
	end)
end

print("[RecruitClient] listo")
