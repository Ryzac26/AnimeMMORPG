--!strict
--[[
    HelperService (ModuleScript) -> ServerScriptService.Services.HelperService
    AYUDANTES DE COMBATE (reemplazan a las mascotas). Catálogo y números: ReplicatedStorage.Modules.HelperCatalog.
      - Perfil (sección "Ayudantes"): colección {id -> estrellas, nivel, XP, equipo}, ranuras 1..3, cupones (carta y reclamados), garantías (pity), tope diario, regalo de bienvenida.
      - Ranuras: la 1 gratis; la 2 y la 3 piden el pase (atributo Pass_PetSlot). Todas desde nivel 1.
      - Cupones: caen de monstruos/jefes/cofres (DropCoupon, con tope diario por rareza) y llegan a la CARTA (atributo HelperMail). Se reclaman ahí y se gastan en el Reclutador.
      - Reclutar (solo cerca del Reclutador): 1 o 10 tiradas con un cupón de una rareza; las probabilidades en % salen del cupón. Una copia repetida sube estrellas (máx. 5) y después da Esencia.
      - Progreso del ayudante: rangos por nivel, ramas de poder (acción "Branch"), ascensión con Esencia ("Ascend"), regalos por rango ("ClaimGift"),
        apodo ("Nick", filtrado con TextService) y aura ("Aura": cada rareza tiene la suya y solo se puede cambiar a la de una rareza anterior). Vínculo de facción: bono para ti según el ayudante equipado de mayor nivel.
      - XP: cada ayudante equipado recibe el 10% de tu XP (extra, no te la quita) y nunca pasa de TU nivel (ShareXp, lo llama RewardService).
      - Equipo: 4 piezas (Arma, Casco, Armadura, Botas) del set del ROL del ayudante; salen de tu mochila. Bono extra de botín: RollBonusGear (LootService).
      - Efectos pasivos: se suman a tus estadísticas con GearService.SetTemp(player, stats, "Helpers") (Ataque, Defensa, Vida, Crítico, Curación, Energía). Dos ayudantes del mismo rol no se suman. En PvP GearService ya aplica el 50%.
      - Autoequipar piezas (acción "GearAuto"): mejor pieza de la mochila por hueco, solo si mejora la que lleva
      - Poderes de combate (solo PvE): PetPowerService usa HelperService.Active(player).
      - Atributos del jugador (los lee HelperFollowClient/HelperClient): Helper1..3 = "<id>#<nivel>#<estrellas>" · HelperLook1..3 = "<rango>#<aura>#<ascensión>#<apodo>" · HelperProp1..3 = "<claveArma>|<clavePieza>" (plantillas de HelperProps) · HelperMail = JSON de cupones en la carta · Pass_PetSlot (pase).
      - Remotes: HelperState (servidor -> cliente: estado) · HelperResult (resultado de reclutar) · HelperAction (cliente -> servidor).
      - Canje de mascotas viejas: ExchangePets (en el Reclutador): cada mascota -> 1 cupón de su misma rareza.
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local Modules = ReplicatedStorage.Modules
local HelperCatalog = require(Modules.HelperCatalog)
local ItemCatalog = require(Modules.ItemCatalog)
local GearCatalog = require(Modules.GearCatalog)
local LootTables = require(Modules.LootTables)
local GB = require(Modules.GameBalance)
local AdminList = require(Modules.AdminList)

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Inventory = require(Services.InventoryService)
local GearService = require(Services.GearService)
local LevelService = require(Services.LevelService)
local WalletService = require(Services.WalletService)
local HelperProps = require(Services.HelperProps)

local StateRemote = Net.Get("HelperState")
local ResultRemote = Net.Get("HelperResult")
local ActionRemote = Net.Get("HelperAction")
local NotifyRemote = Net.Get("Notify")
local CheerRemote = Net.Get("HelperCheer") -- (jugador, ranura) a todos: el ayudante celebra (rango, ascensión, rama)

local rng = Random.new()

type GearPiece = { Id: string, Plus: number }
type Entry = {
	Stars: number,
	Level: number,
	Xp: number,
	Gear: { [string]: GearPiece },
	Asc: number, -- ascensión 0..3
	Branch: string?, -- "A" (Ritmo) | "B" (Potencia) | nil
	Nick: string?, -- apodo (ya filtrado)
	Aura: number, -- aura que lleva (1..rareza del ayudante; por defecto la de su rareza, ver HelperCatalog.RarityAuras)
	Gifts: number, -- mayor rango cuyo regalo ya reclamaste (1 = ninguno)
}
type Profile = {
	Owned: { [string]: Entry },
	Slots: { [number]: string },
	Stock: { [string]: number }, -- cupones ya reclamados (se gastan en el Reclutador)
	Mail: { [string]: number }, -- cupones en la carta, sin reclamar
	Pity: { [string]: number },
	Day: string,
	DayCount: { [string]: number },
	Gift: boolean,
	Pulls: number,
	Essence: number,
}

export type ActiveHelper = {
	Slot: number,
	Id: string,
	Faction: string,
	Role: string,
	Rarity: string,
	Stars: number,
	Level: number,
	Factor: number,
	Asc: number,
	Branch: string?,
	Rank: number,
	Nick: string?,
	Aura: number,
}

local profiles: { [Player]: Profile } = {}
local active: { [Player]: { ActiveHelper } } = {}
local uiOpen: { [Player]: boolean } = {}
local pushQueued: { [Player]: boolean } = {}
local recruitAllowed: { [Player]: { Until: number, Pos: Vector3 } } = {}
local lastAction: { [Player]: number } = {}
local nickBusy: { [Player]: boolean } = {}

local HelperService = {}

---------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------
local function notify(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

local function today(): string
	local t = os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600
	return os.date("!%Y-%m-%d", t)
end

local function ownerLevel(player: Player): number
	return math.max(1, LevelService.GetLevel(player))
end

local function hasPass(player: Player): boolean
	return player:GetAttribute(HelperCatalog.PassAttr) == true
end

local function slotOpen(player: Player, slot: number): boolean
	return HelperCatalog.SlotOpen(slot, hasPass(player), ownerLevel(player))
end

local function isOwner(player: Player): boolean
	local e = AdminList.Get(player)
	return e ~= nil and e.Kind == "Owner"
end

local function newProfile(): Profile
	return { Owned = {}, Slots = {}, Stock = {}, Mail = {}, Pity = {}, Day = today(), DayCount = {}, Gift = false, Pulls = 0, Essence = 0 }
end

local function newEntry(rarity: string?): Entry
	return { Stars = 1, Level = 1, Xp = 0, Gear = {}, Asc = 0, Branch = nil, Nick = nil, Aura = HelperCatalog.AuraOf(rarity or "Comun"), Gifts = 1 }
end

-- oro de un monstruo normal de ese nivel (base de los regalos y del coste de cambiar de rama)
local function goldUnit(level: number): number
	return math.max(1, math.floor(LootTables.GoldBase * LootTables.GoldGrowth ^ (GB.Eq(level) - 1)))
end

local function helperName(id: string, e: Entry?): string
	if e and e.Nick and e.Nick ~= "" then
		return e.Nick
	end
	local parsed = HelperCatalog.Parse(id)
	return if parsed then HelperCatalog.NameOf(parsed) else id
end

local function slotOf(p: Profile, id: string): number?
	for i = 1, HelperCatalog.MaxSlots do
		if p.Slots[i] == id then
			return i
		end
	end
	return nil
end

local function validRarity(r: any): boolean
	return typeof(r) == "string" and HelperCatalog.RarityIndex[r] ~= nil
end

local function bagItem(id: string): any
	return (ItemCatalog.Items :: any)[id]
end

-- poder (+%) que aporta el equipo puesto de un ayudante
local function gearPowerOf(e: Entry): number
	local pieces: { { Rarity: string, Plus: number } } = {}
	for _, piece in pairs(e.Gear) do
		local item = bagItem(piece.Id)
		if item and typeof(item.Rarity) == "string" then
			table.insert(pieces, { Rarity = item.Rarity, Plus = piece.Plus })
		end
	end
	return HelperCatalog.GearPower(pieces)
end

---------------------------------------------------------------------
-- Guardado
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Ayudantes", function(player: Player): any?
	local p = profiles[player]
	if not p then
		return nil
	end
	local owned: { [string]: any } = {}
	for id, e in pairs(p.Owned) do
		local gear: { [string]: any } = {}
		for slot, piece in pairs(e.Gear) do
			gear[slot] = { I = piece.Id, P = piece.Plus }
		end
		owned[id] = { S = e.Stars, L = e.Level, X = e.Xp, G = gear, A = e.Asc, B = e.Branch, K = e.Nick, V = e.Aura, R = e.Gifts }
	end
	local slots: { [string]: string } = {}
	for i = 1, HelperCatalog.MaxSlots do
		if p.Slots[i] then
			slots[tostring(i)] = p.Slots[i]
		end
	end
	return { O = owned, S = slots, C = p.Stock, M = p.Mail, P = p.Pity, D = p.Day, DC = p.DayCount, G = p.Gift, N = p.Pulls, Es = p.Essence }
end)

local function numberMap(src: any, rarityKeys: boolean): { [string]: number }
	local out: { [string]: number } = {}
	if type(src) == "table" then
		for k, v in pairs(src) do
			if type(k) == "string" and type(v) == "number" and v >= 0 and (not rarityKeys or HelperCatalog.RarityIndex[k]) then
				out[k] = math.floor(v)
			end
		end
	end
	return out
end

---------------------------------------------------------------------
-- Cálculo de efectos y publicación
---------------------------------------------------------------------
local function dayRollover(p: Profile)
	local now = today()
	if p.Day ~= now then
		p.Day = now
		p.DayCount = {}
	end
end

-- Lista de ayudantes que SÍ cuentan: ranura abierta, ayudante tuyo y sin repetir rol
local function buildActive(player: Player, p: Profile): { ActiveHelper }
	local out: { ActiveHelper } = {}
	local seenRole: { [string]: boolean } = {}
	local lvOwner = ownerLevel(player)
	for slot = 1, HelperCatalog.MaxSlots do
		local id = p.Slots[slot]
		local e = if id then p.Owned[id] else nil
		local parsed = if id then HelperCatalog.Parse(id) else nil
		if id and e and parsed and slotOpen(player, slot) and not seenRole[parsed.Role] then
			seenRole[parsed.Role] = true
			table.insert(out, {
				Slot = slot,
				Id = id,
				Faction = parsed.Faction,
				Role = parsed.Role,
				Rarity = parsed.Rarity,
				Stars = e.Stars,
				Level = e.Level,
				Factor = HelperCatalog.LevelFactor(e.Level, lvOwner),
				Asc = e.Asc,
				Branch = e.Branch,
				Rank = HelperCatalog.RankOf(e.Level),
				Nick = e.Nick,
				Aura = e.Aura,
			})
		end
	end
	return out
end

local function publishAttributes(player: Player, p: Profile)
	for slot = 1, HelperCatalog.MaxSlots do
		local id = p.Slots[slot]
		local e = if id then p.Owned[id] else nil
		if id and e and slotOpen(player, slot) then
			player:SetAttribute("Helper" .. slot, string.format("%s#%d#%d", id, e.Level, e.Stars))
			player:SetAttribute("HelperLook" .. slot, string.format("%d#%d#%d#%s", HelperCatalog.RankOf(e.Level), e.Aura, e.Asc, e.Nick or ""))
			-- armas del ayudante (plantillas que dibuja HelperModel): arma principal y pieza secundaria de su clase
			local parsed = HelperCatalog.Parse(id)
			local propValue: string? = nil
			if parsed then
				local arma = e.Gear.Arma
				local okKeys, mainKey, offKey = pcall(HelperProps.KeysFor, parsed.Faction, parsed.Role, parsed.Rarity, e.Level, if arma then bagItem(arma.Id) else nil)
				if okKeys then
					propValue = (mainKey or "") .. "|" .. (offKey or "")
				else
					warn("[HelperService] armas del ayudante:", mainKey)
				end
			end
			player:SetAttribute("HelperProp" .. slot, propValue)
		else
			player:SetAttribute("Helper" .. slot, nil)
			player:SetAttribute("HelperLook" .. slot, nil)
			player:SetAttribute("HelperProp" .. slot, nil)
		end
	end
	local any = false
	for _, n in pairs(p.Mail) do
		if n > 0 then
			any = true
		end
	end
	player:SetAttribute("HelperMail", if any then HttpService:JSONEncode(p.Mail) else nil)
end

local function recompute(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	local list = buildActive(player, p)
	active[player] = list
	local lvOwner = ownerLevel(player)
	local effects: { { [string]: number } } = {}
	local topLevel = 0
	for _, h in ipairs(list) do
		local e = p.Owned[h.Id]
		local parsed = HelperCatalog.Parse(h.Id)
		if e and parsed then
			table.insert(effects, HelperCatalog.Effects(parsed, e.Stars, e.Level, lvOwner, gearPowerOf(e), e.Asc))
			topLevel = math.max(topLevel, e.Level)
		end
	end
	local total = HelperCatalog.Total(effects)
	-- vínculo de facción: perk propio según el ayudante equipado de mayor nivel (suma aparte del tope)
	local faction = player:GetAttribute("Faction")
	if typeof(faction) == "string" then
		for stat, v in pairs(HelperCatalog.BondStats(faction, topLevel)) do
			total[stat] = (total[stat] or 0) + v
		end
	end
	GearService.SetTemp(player, total, "Helpers")
	publishAttributes(player, p)
end

local function snapshot(player: Player, p: Profile): { [string]: any }
	dayRollover(p)
	local owned: { [string]: any } = {}
	for id, e in pairs(p.Owned) do
		local gear: { [string]: any } = {}
		for slot, piece in pairs(e.Gear) do
			gear[slot] = { Id = piece.Id, Plus = piece.Plus }
		end
		owned[id] = {
			S = e.Stars,
			L = e.Level,
			X = math.floor(e.Xp),
			N = HelperCatalog.XpToNext(e.Level),
			G = gear,
			Gp = gearPowerOf(e),
			A = e.Asc,
			B = e.Branch or "",
			K = e.Nick or "",
			U = e.Aura,
			R = e.Gifts,
		}
	end
	local slots: { string } = {}
	local open: { boolean } = {}
	for i = 1, HelperCatalog.MaxSlots do
		slots[i] = p.Slots[i] or ""
		open[i] = slotOpen(player, i)
	end
	return {
		Owned = owned,
		Slots = slots,
		Open = open,
		Pass = hasPass(player),
		Stock = p.Stock,
		Mail = p.Mail,
		Pity = p.Pity,
		Pulls = p.Pulls,
		DayCount = p.DayCount,
		Level = ownerLevel(player),
		Faction = player:GetAttribute("Faction"),
		Essence = p.Essence,
		GoldUnit = goldUnit(ownerLevel(player)),
	}
end

local function push(player: Player)
	local p = profiles[player]
	if p then
		StateRemote:FireClient(player, snapshot(player, p))
	end
end

-- Empuje con espera corta (muchos cambios seguidos = un solo envío)
local function queuePush(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.delay(0.4, function()
		pushQueued[player] = nil
		if player.Parent then
			push(player)
		end
	end)
end

local function changed(player: Player)
	recompute(player)
	queuePush(player)
end

---------------------------------------------------------------------
-- Colección
---------------------------------------------------------------------
-- Suma un ayudante. Devuelve (esNuevo, estrellasFinales, esenciaPorRepetido)
local function addHelper(player: Player, p: Profile, id: string, rarity: string): (boolean, number, number)
	local e = p.Owned[id]
	if not e then
		p.Owned[id] = newEntry(rarity)
		return true, 1, 0
	end
	if e.Stars < HelperCatalog.MaxStars then
		e.Stars += 1
		return false, e.Stars, 0
	end
	local essence = HelperCatalog.EssenceDup[rarity] or 0
	p.Essence += essence
	return false, e.Stars, essence
end

local function pickByOdds(odds: { number }, minIndex: number): string
	local total = 0
	for i, v in ipairs(odds) do
		if i >= minIndex then
			total += v
		end
	end
	local roll = rng:NextNumber() * total
	local last = HelperCatalog.Rarities[minIndex]
	for i, v in ipairs(odds) do
		if i >= minIndex and v > 0 then
			roll -= v
			last = HelperCatalog.Rarities[i]
			if roll < 0 then
				return last
			end
		end
	end
	return last
end

type PullResult = { Id: string, Rarity: string, New: boolean, Stars: number, Essence: number }

local function pullOne(player: Player, p: Profile, coupon: string, faction: string): PullResult
	local c = HelperCatalog.Coupons[coupon]
	local pity = p.Pity[coupon] or 0
	local minIndex = 1
	if c.Pity and pity + 1 >= c.Pity.Every then
		minIndex = HelperCatalog.RarityIndex[c.Pity.Min] -- garantía: esta tirada sale Min o mejor
	end
	local rarity = pickByOdds(c.Odds, minIndex)
	if c.Pity then
		if HelperCatalog.RarityIndex[rarity] >= HelperCatalog.RarityIndex[c.Pity.Min] then
			p.Pity[coupon] = 0
		else
			p.Pity[coupon] = pity + 1
		end
	end
	local role = HelperCatalog.Roles[rng:NextInteger(1, #HelperCatalog.Roles)]
	local id = HelperCatalog.Id(faction, role, rarity)
	local isNew, stars, essence = addHelper(player, p, id, rarity)
	p.Pulls += 1
	return { Id = id, Rarity = rarity, New = isNew, Stars = stars, Essence = essence }
end

local function recruit(player: Player, coupon: any, count: any)
	local p = profiles[player]
	if not p or not validRarity(coupon) or (count ~= 1 and count ~= HelperCatalog.PullsPerBatch) then
		return
	end
	local allowed = recruitAllowed[player]
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not allowed or os.clock() > allowed.Until or not root or not root:IsA("BasePart") or (root.Position - allowed.Pos).Magnitude > 70 then
		notify(player, "Acércate al Reclutador para reclutar ayudantes")
		return
	end
	local n = count :: number
	local have = p.Stock[coupon :: string] or 0
	if have < n then
		notify(player, string.format("Te faltan cupones: tienes %d y necesitas %d", have, n))
		return
	end
	local class = player:GetAttribute("Faction")
	local faction = if typeof(class) == "string" and HelperCatalog.Roster[class] then class else nil
	if not faction then
		return
	end
	p.Stock[coupon :: string] = have - n
	local results: { PullResult } = {}
	for _ = 1, n do
		table.insert(results, pullOne(player, p, coupon :: string, faction))
	end
	ResultRemote:FireClient(player, { Coupon = coupon, Results = results, Pity = p.Pity[coupon :: string] or 0 })
	PlayerData.Save(player)
	changed(player)
end

---------------------------------------------------------------------
-- Cupones: carta y reclamar
---------------------------------------------------------------------
function HelperService.AddCouponMail(player: Player, rarity: string, n: number)
	local p = profiles[player]
	if not p or not validRarity(rarity) or n <= 0 then
		return
	end
	p.Mail[rarity] = (p.Mail[rarity] or 0) + n
	publishAttributes(player, p)
	queuePush(player)
end

-- Cupón que cae de un monstruo/jefe/cofre. Respeta el tope diario por rareza. Devuelve true si se entregó.
function HelperService.DropCoupon(player: Player, rarity: string, source: string?): boolean
	local p = profiles[player]
	if not p or not validRarity(rarity) then
		return false
	end
	dayRollover(p)
	local cap = HelperCatalog.DailyCouponCap[rarity] or 0
	local used = p.DayCount[rarity] or 0
	if used >= cap then
		return false -- límite diario: no cae más hoy de esa rareza
	end
	p.DayCount[rarity] = used + 1
	HelperService.AddCouponMail(player, rarity, 1)
	notify(player, string.format("✉ ¡%s en tu carta! (hoy %d de %d) — reclámalo en la carta", HelperCatalog.Coupons[rarity].Name, used + 1, cap))
	if HelperCatalog.RarityIndex[rarity] >= 3 then
		PlayerData.Save(player)
	end
	return true
end

local function claimMail(player: Player, which: any)
	local p = profiles[player]
	if not p then
		return
	end
	local total = 0
	for _, rarity in ipairs(HelperCatalog.Rarities) do
		local n = p.Mail[rarity] or 0
		if n > 0 and (which == "all" or which == rarity) then
			p.Stock[rarity] = (p.Stock[rarity] or 0) + n
			p.Mail[rarity] = nil
			total += n
		end
	end
	if total > 0 then
		notify(player, string.format("🎟 %d cupón(es) reclamado(s). Úsalos en el Reclutador", total))
		PlayerData.Save(player)
	end
	publishAttributes(player, p)
	queuePush(player)
end

---------------------------------------------------------------------
-- Ranuras
---------------------------------------------------------------------
local function equip(player: Player, id: any, slot: any)
	local p = profiles[player]
	if not p or typeof(id) ~= "string" or typeof(slot) ~= "number" then
		return
	end
	slot = math.floor(slot)
	local parsed = HelperCatalog.Parse(id)
	if not parsed or not p.Owned[id] or slot < 1 or slot > HelperCatalog.MaxSlots then
		return
	end
	if not slotOpen(player, slot) then
		notify(player, "Esa ranura se abre con el pase de Ranuras de Ayudante (tienda > Pases)")
		return
	end
	for other = 1, HelperCatalog.MaxSlots do
		local oid = p.Slots[other]
		if other ~= slot and oid then
			local op = HelperCatalog.Parse(oid)
			if oid == id then
				p.Slots[other] = nil -- se mueve de ranura
			elseif op and op.Role == parsed.Role then
				notify(player, string.format("Ya tienes un ayudante de rol %s equipado (no se suman dos del mismo rol)", parsed.Role))
				return
			end
		end
	end
	p.Slots[slot] = id
	changed(player)
end

local function unequip(player: Player, slot: any)
	local p = profiles[player]
	if not p or typeof(slot) ~= "number" then
		return
	end
	slot = math.floor(slot)
	if slot >= 1 and slot <= HelperCatalog.MaxSlots then
		p.Slots[slot] = nil
		changed(player)
	end
end

---------------------------------------------------------------------
-- Equipo del ayudante (4 piezas del set de su rol)
---------------------------------------------------------------------
local function gearEquip(player: Player, helperId: any, slotName: any, bagIndex: any)
	local p = profiles[player]
	if not p or typeof(helperId) ~= "string" or typeof(slotName) ~= "string" or typeof(bagIndex) ~= "number" then
		return
	end
	local e = p.Owned[helperId]
	local parsed = HelperCatalog.Parse(helperId)
	if not e or not parsed or not table.find(HelperCatalog.GearSlots, slotName) then
		return
	end
	bagIndex = math.floor(bagIndex)
	local st = Inventory.Get(player)
	local stack = if st then st.Bag[bagIndex] else nil
	if not stack then
		return
	end
	local item = bagItem(stack.Id)
	if not item or item.Kind ~= "Set" or item.Slot ~= slotName or item.Role ~= parsed.Role then
		notify(player, string.format("Solo sirven piezas de %s de rol %s", HelperCatalog.GearSlotName[slotName] or slotName, parsed.Role))
		return
	end
	if typeof(item.ReqLevel) == "number" and item.ReqLevel > ownerLevel(player) then
		notify(player, "Necesitas nivel " .. tostring(item.ReqLevel) .. " para dárselo")
		return
	end
	if stack.Locked then
		notify(player, "Esa pieza tiene candado: desbloquéala primero")
		return
	end
	local newId, newPlus = stack.Id, stack.Plus or 0
	local takenId = Inventory.RemoveSlot(player, bagIndex, 1)
	if not takenId then
		return
	end
	local old = e.Gear[slotName]
	if old and not Inventory.Add(player, old.Id, 1, old.Plus) then
		Inventory.Add(player, newId, 1, newPlus) -- sin sitio para devolver la vieja: deshace el cambio
		return
	end
	e.Gear[slotName] = { Id = newId, Plus = newPlus }
	PlayerData.Save(player)
	changed(player)
end

local function gearUnequip(player: Player, helperId: any, slotName: any)
	local p = profiles[player]
	if not p or typeof(helperId) ~= "string" or typeof(slotName) ~= "string" then
		return
	end
	local e = p.Owned[helperId]
	local piece = if e then e.Gear[slotName] else nil
	if not e or not piece then
		return
	end
	if not Inventory.Add(player, piece.Id, 1, piece.Plus) then
		return -- mochila llena (Inventory ya avisó)
	end
	e.Gear[slotName] = nil
	PlayerData.Save(player)
	changed(player)
end

-- AUTOEQUIPAR: por cada hueco (Arma, Casco, Armadura, Zapatos) deja la MEJOR pieza de la mochila que sirva a ese ayudante (su rol, tu nivel,
-- sin candado). Solo reemplaza si es MEJOR que la que lleva (rareza + mejora); la pieza vieja vuelve a la mochila. Si el ayudante comparte rol
-- contigo y esa pieza mejoraría TU equipo, se la deja a tu "★ Mejor set" (no te la quita).
-- target = id de un ayudante, o "all" = todos los que tienes equipados en las ranuras.
local function pieceScore(item: any, plus: number): number
	return (HelperCatalog.PieceBonus[item.Rarity] or 0) * (1 + HelperCatalog.PlusBonus * math.clamp(plus, 0, 9))
end

-- ¿esa pieza de la mochila subiría el poder de TU propio personaje en su ranura?
local function betterForOwner(player: Player, st: any, stack: any, item: any): boolean
	if not GearService.CanEquip(player, stack.Id) then
		return false
	end
	local curId = st.Equip[item.Slot]
	local curItem = if curId then bagItem(curId) else nil
	if not curItem or not curItem.Gear then
		return true
	end
	local roleAttr = player:GetAttribute("Role")
	local role = if typeof(roleAttr) == "string" then roleAttr else "Guerrero"
	local function power(it: any, plus: number): number
		local mult = GearCatalog.EnhanceMult(plus)
		local effects: { [string]: number } = {}
		for stat, v in pairs(it.Gear or {}) do
			effects[stat] = v * mult
		end
		return GearCatalog.PowerGain(role, effects)
	end
	return power(item, stack.Plus or 0) > power(curItem, st.EquipPlus[item.Slot] or 0) + 1e-9
end

local function gearAuto(player: Player, target: any)
	local p = profiles[player]
	local st: any = Inventory.Get(player)
	if not p or not st then
		return
	end
	local ids: { string } = {}
	if target == "all" then
		for slot = 1, HelperCatalog.MaxSlots do
			local id = p.Slots[slot]
			if id and p.Owned[id] and slotOpen(player, slot) and not table.find(ids, id) then
				table.insert(ids, id)
			end
		end
	elseif typeof(target) == "string" and p.Owned[target] then
		ids = { target }
	else
		return
	end
	if #ids == 0 then
		notify(player, "No tienes ayudantes equipados")
		return
	end
	local lv = ownerLevel(player)
	local changedN, keptForOwner, bagFull = 0, 0, false
	for _, id in ipairs(ids) do
		local e = p.Owned[id]
		local parsed = HelperCatalog.Parse(id)
		if e and parsed then
			for _, slotName in ipairs(HelperCatalog.GearSlots) do
				local cur = e.Gear[slotName]
				local curItem = if cur then bagItem(cur.Id) else nil
				local bestScore = if cur and curItem then pieceScore(curItem, cur.Plus) else -1
				local bestIndex: number? = nil
				local skipped = false
				for i, stack in pairs(st.Bag) do
					local item = bagItem(stack.Id)
					if item and item.Kind == "Set" and item.Slot == slotName and item.Role == parsed.Role and not stack.Locked
						and (typeof(item.ReqLevel) ~= "number" or item.ReqLevel <= lv) then
						local sc = pieceScore(item, stack.Plus or 0)
						if sc > bestScore + 1e-9 then
							if betterForOwner(player, st, stack, item) then
								skipped = true
							else
								bestScore, bestIndex = sc, i
							end
						end
					end
				end
				if bestIndex then
					local stack = st.Bag[bestIndex]
					local newId, newPlus = stack.Id, stack.Plus or 0
					local takenId = Inventory.RemoveSlot(player, bestIndex, 1)
					if takenId then
						if cur and not Inventory.Add(player, cur.Id, 1, cur.Plus) then
							Inventory.Add(player, newId, 1, newPlus) -- sin sitio para devolver la vieja: deshace el cambio
							bagFull = true
						else
							e.Gear[slotName] = { Id = newId, Plus = newPlus }
							changedN += 1
						end
					end
				elseif skipped then
					keptForOwner += 1
				end
			end
		end
	end
	if changedN > 0 then
		PlayerData.Save(player)
		changed(player)
	end
	local msg = if changedN > 0 then string.format("Autoequipar: %d pieza(s) mejoradas en tus ayudantes", changedN) else "Tus ayudantes ya llevan lo mejor que tienes"
	if keptForOwner > 0 then
		msg ..= string.format(" · %d pieza(s) se quedan en la mochila porque mejoran TU equipo (usa ★ Mejor set)", keptForOwner)
	end
	if bagFull then
		msg ..= " · mochila llena: libera espacio"
	end
	notify(player, msg)
end

-- Bono de botín: cada pieza de set que te cae puede traer OTRA para el rol de uno de tus ayudantes equipados (no te quita la tuya)
function HelperService.RollBonusGear(player: Player, droppedId: string): string?
	local list = active[player]
	local item = bagItem(droppedId)
	if not list or #list == 0 or not item or item.Kind ~= "Set" or not table.find(HelperCatalog.GearSlots, item.Slot) then
		return nil
	end
	if rng:NextNumber() >= HelperCatalog.BonusGearChance then
		return nil
	end
	local helper = list[rng:NextInteger(1, #list)]
	local slot = HelperCatalog.GearSlots[rng:NextInteger(1, #HelperCatalog.GearSlots)]
	local style: string? = nil
	if slot == "Arma" then
		local styles = GearCatalog.StylesForRole(helper.Role)
		style = styles[rng:NextInteger(1, math.max(1, #styles))]
	end
	local step = if typeof(item.Step) == "number" then item.Step else 1
	local id = GearCatalog.SetPieceId(helper.Role, slot, style, step, item.Rarity)
	if GearCatalog.Items[id] then
		return id
	end
	return nil
end

---------------------------------------------------------------------
-- XP de los ayudantes
---------------------------------------------------------------------
function HelperService.ShareXp(player: Player, amount: number)
	local p = profiles[player]
	local list = active[player]
	if not p or not list or #list == 0 or amount <= 0 then
		return
	end
	local cap = math.min(ownerLevel(player), HelperCatalog.MaxLevel)
	local leveled = false
	local rankUps: { { Slot: number, Id: string, Entry: Entry, Rank: number } } = {}
	local gain = amount * HelperCatalog.XpShare
	for slot = 1, HelperCatalog.MaxSlots do
		local id = p.Slots[slot]
		local e = if id then p.Owned[id] else nil
		if id and e and slotOpen(player, slot) then
			local rankBefore = HelperCatalog.RankOf(e.Level)
			if e.Level >= cap then
				e.Xp = 0
			else
				e.Xp += gain
				local need = HelperCatalog.XpToNext(e.Level)
				while e.Xp >= need and e.Level < cap do
					e.Xp -= need
					e.Level += 1
					leveled = true
					need = HelperCatalog.XpToNext(e.Level)
				end
				if e.Level >= cap then
					e.Xp = 0
				end
			end
			local rankAfter = HelperCatalog.RankOf(e.Level)
			if rankAfter > rankBefore then
				table.insert(rankUps, { Slot = slot, Id = id, Entry = e, Rank = rankAfter })
			end
		end
	end
	if leveled then
		recompute(player)
		queuePush(player)
		for _, up in ipairs(rankUps) do
			local rankName = HelperCatalog.Ranks[up.Rank].Name
			local gift = if HelperCatalog.Gifts[up.Rank] then " · ¡trae un regalo! (Ayudantes > Camino)" else ""
			notify(player, string.format("⭐ %s alcanzó el rango %s%s", helperName(up.Id, up.Entry), rankName, gift))
			CheerRemote:FireAllClients(player, up.Slot)
		end
		if #rankUps > 0 then
			PlayerData.Save(player)
		end
	elseif uiOpen[player] then
		queuePush(player)
	end
end

function HelperService.Active(player: Player): { ActiveHelper }
	return active[player] or {}
end

function HelperService.AllowRecruit(player: Player, pos: Vector3)
	recruitAllowed[player] = { Until = os.clock() + 900, Pos = pos }
	uiOpen[player] = true
	push(player)
end

---------------------------------------------------------------------
-- Canje de mascotas viejas -> cupones de la misma rareza
---------------------------------------------------------------------
local function exchangePets(player: Player)
	local p = profiles[player]
	local st = Inventory.Get(player)
	if not p or not st then
		return
	end
	local allowed = recruitAllowed[player]
	if not allowed or os.clock() > allowed.Until then
		return
	end
	local got: { [string]: number } = {}
	local function take(rarity: any)
		if validRarity(rarity) then
			got[rarity :: string] = (got[rarity :: string] or 0) + 1
		end
	end
	for index, stack in pairs(st.Bag) do
		local item = bagItem(stack.Id)
		if item and item.Pet then
			for _ = 1, stack.Count do
				take(item.Rarity)
			end
			Inventory.RemovePiece(player, "Bag", index)
		end
	end
	for _, slot in ipairs({ "Accesorio2", "Accesorio3" }) do
		local id = st.Equip[slot]
		local item = if id then bagItem(id) else nil
		if item and item.Pet then
			take(item.Rarity)
			Inventory.RemovePiece(player, "Equip", slot)
		end
	end
	local total = 0
	for rarity, n in pairs(got) do
		p.Stock[rarity] = (p.Stock[rarity] or 0) + n
		total += n
	end
	if total > 0 then
		notify(player, string.format("🎟 Canjeaste %d mascota(s) por %d cupón(es) de reclutamiento", total, total))
		PlayerData.Save(player)
	else
		notify(player, "No tienes mascotas viejas para canjear")
	end
	changed(player)
end

---------------------------------------------------------------------
-- Progreso: ascensión, ramas, regalos, apodo y aura
---------------------------------------------------------------------
-- Nombre para mostrar (apodo o nombre del catálogo)
function HelperService.DisplayName(h: ActiveHelper): string
	if h.Nick and h.Nick ~= "" then
		return h.Nick
	end
	return HelperCatalog.NameOf({ Faction = h.Faction, Role = h.Role, Rarity = h.Rarity })
end

local function celebrate(player: Player, p: Profile, id: string)
	local slot = slotOf(p, id)
	if slot then
		CheerRemote:FireAllClients(player, slot)
	end
end

-- ASCENDER: gasta Esencia. Cada escalón sube el poder una rareza (hasta Mítico) y suma +5% a los bonos.
local function ascend(player: Player, id: any)
	local p = profiles[player]
	local e = if p and typeof(id) == "string" then p.Owned[id] else nil
	local parsed = if typeof(id) == "string" then HelperCatalog.Parse(id) else nil
	if not p or not e or not parsed or typeof(id) ~= "string" then
		return
	end
	local nextAsc = e.Asc + 1
	if nextAsc > HelperCatalog.MaxAsc then
		notify(player, "Ya está en su máxima ascensión")
		return
	end
	local needLevel = HelperCatalog.AscLevels[nextAsc]
	if e.Level < needLevel then
		notify(player, string.format("Necesita nivel %d para la ascensión %s", needLevel, HelperCatalog.AscNames[nextAsc]))
		return
	end
	local cost = HelperCatalog.AscendCost(parsed.Rarity, nextAsc)
	if p.Essence < cost then
		notify(player, string.format("Te falta Esencia: tienes %d y necesitas %d", p.Essence, cost))
		return
	end
	p.Essence -= cost
	e.Asc = nextAsc
	notify(player, string.format("✨ %s ascendió (%s): poder y bonos mejorados", helperName(id, e), HelperCatalog.AscNames[nextAsc]))
	celebrate(player, p, id)
	PlayerData.Save(player)
	changed(player)
end

-- RAMA: A (Ritmo) o B (Potencia). Se abre al nivel 100; la primera elección es gratis, cambiarla cuesta oro.
local function setBranch(player: Player, id: any, kind: any)
	local p = profiles[player]
	local e = if p and typeof(id) == "string" then p.Owned[id] else nil
	if not p or not e or typeof(id) ~= "string" or (kind ~= "A" and kind ~= "B") then
		return
	end
	if e.Level < HelperCatalog.BranchLevels[1] then
		notify(player, string.format("Las ramas se abren al nivel %d del ayudante", HelperCatalog.BranchLevels[1]))
		return
	end
	if e.Branch == kind then
		return
	end
	if e.Branch ~= nil then
		local cost = goldUnit(ownerLevel(player)) * HelperCatalog.BranchChangeMobs
		if not WalletService.TrySpendGold(player, cost, "Ayudantes") then
			notify(player, string.format("Cambiar de rama cuesta %s de oro y no te alcanza", tostring(cost)))
			return
		end
	end
	e.Branch = kind :: string
	local parsed = HelperCatalog.Parse(id)
	local info = if parsed then HelperCatalog.Branches[parsed.Role] else nil
	local branchName = if info then (info :: any)[kind].Name else kind
	notify(player, string.format("🔀 %s eligió la rama «%s»", helperName(id, e), tostring(branchName)))
	celebrate(player, p, id)
	PlayerData.Save(player)
	changed(player)
end

-- REGALOS: uno por rango alcanzado (oro, Esencia y a veces un cupón a la carta)
local function claimGiftFor(player: Player, p: Profile, id: string, e: Entry): (number, number, number, number)
	local rank = HelperCatalog.RankOf(e.Level)
	local parsed = HelperCatalog.Parse(id)
	if not parsed or rank <= e.Gifts then
		return 0, 0, 0, 0
	end
	local gold, essence, coupons = 0, 0, 0
	local unit = goldUnit(ownerLevel(player))
	local claimed = 0
	for r = e.Gifts + 1, rank do
		local g = HelperCatalog.Gifts[r]
		if g then
			claimed += 1
			gold += g.Mobs * unit
			essence += HelperCatalog.GiftEssence(r, parsed.Rarity)
			if g.Coupon and validRarity(g.Coupon) then
				local n = g.CouponN or 1
				HelperService.AddCouponMail(player, g.Coupon, n)
				coupons += n
			end
		end
	end
	e.Gifts = rank
	if gold > 0 then
		WalletService.AddGold(player, gold, "Ayudantes")
	end
	p.Essence += essence
	return claimed, gold, essence, coupons
end

local function claimGift(player: Player, which: any)
	local p = profiles[player]
	if not p then
		return
	end
	local ids: { string } = {}
	if which == "all" then
		for id in pairs(p.Owned) do
			table.insert(ids, id)
		end
	elseif typeof(which) == "string" and p.Owned[which] then
		ids = { which }
	else
		return
	end
	local n, gold, essence, coupons = 0, 0, 0, 0
	for _, id in ipairs(ids) do
		local c, g, es, cp = claimGiftFor(player, p, id, p.Owned[id])
		n += c
		gold += g
		essence += es
		coupons += cp
	end
	if n == 0 then
		notify(player, "No hay regalos por reclamar")
		return
	end
	local parts = { string.format("%d regalo(s)", n) }
	if gold > 0 then
		table.insert(parts, string.format("%s de oro", tostring(gold)))
	end
	if essence > 0 then
		table.insert(parts, string.format("%d de Esencia", essence))
	end
	if coupons > 0 then
		table.insert(parts, string.format("%d cupón(es) en la carta ✉", coupons))
	end
	notify(player, "🎁 " .. table.concat(parts, " · "))
	PlayerData.Save(player)
	changed(player)
end

-- AURA: cada rareza tiene su aura; el ayudante lleva la de su rareza y solo puede cambiar a la de una rareza ANTERIOR (nunca a una mayor)
local function setAura(player: Player, id: any, idx: any)
	local p = profiles[player]
	local parsed = if typeof(id) == "string" then HelperCatalog.Parse(id) else nil
	local e = if p and parsed and typeof(id) == "string" then p.Owned[id] else nil
	if not p or not e or not parsed or typeof(idx) ~= "number" or idx ~= idx then
		return
	end
	idx = math.floor(idx)
	if idx < 1 or idx > HelperCatalog.AuraOf(parsed.Rarity) or idx == e.Aura then
		return
	end
	e.Aura = idx
	changed(player)
end

-- APODO: ≤ NickMax letras/números/espacios y . - _ ' !  · pasa por el filtro de Roblox (si cambia algo, se rechaza)
local function validNickChars(text: string): boolean
	if not utf8.len(text) then
		return false
	end
	for _, cp in utf8.codes(text) do
		local ok = (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp == 32 or cp == 46 or cp == 45 or cp == 95
			or cp == 39 or cp == 33 or (cp >= 0xC0 and cp <= 0x17F and cp ~= 0xD7 and cp ~= 0xF7)
		if not ok then
			return false
		end
	end
	return true
end

local function setNick(player: Player, id: any, text: any)
	local p = profiles[player]
	local e = if p and typeof(id) == "string" then p.Owned[id] else nil
	if not p or not e or typeof(id) ~= "string" or typeof(text) ~= "string" or nickBusy[player] then
		return
	end
	local clean = string.gsub(string.gsub(text, "^%s+", ""), "%s+$", "")
	clean = string.gsub(clean, "%s+", " ")
	if clean == "" then
		e.Nick = nil
		notify(player, "Apodo quitado")
		changed(player)
		return
	end
	local len = utf8.len(clean)
	if not len or len > HelperCatalog.NickMax or not validNickChars(clean) then
		notify(player, string.format("Apodo no válido: hasta %d letras, números o espacios", HelperCatalog.NickMax))
		return
	end
	nickBusy[player] = true
	task.spawn(function()
		local ok, filtered = pcall(function()
			local res = TextService:FilterStringAsync(clean, player.UserId, Enum.TextFilterContext.PublicChat)
			return res:GetNonChatStringForBroadcastAsync()
		end)
		nickBusy[player] = nil
		local pp = profiles[player]
		local ee = if pp then pp.Owned[id] else nil
		if not player.Parent or not pp or not ee then
			return
		end
		if not ok or filtered ~= clean then
			notify(player, "Ese apodo no está permitido: prueba con otro")
			return
		end
		ee.Nick = clean
		notify(player, string.format("Apodo guardado: %s", clean))
		celebrate(player, pp, id)
		PlayerData.Save(player)
		changed(player)
	end)
end


---------------------------------------------------------------------
-- Acciones de prueba (SOLO el Fundador)
---------------------------------------------------------------------
local function devAction(player: Player, action: string, a: any, b: any)
	local p = profiles[player]
	if not p or not isOwner(player) then
		return
	end
	if action == "DevCoupon" and validRarity(a) and typeof(b) == "number" then
		p.Stock[a :: string] = math.max(0, (p.Stock[a :: string] or 0) + math.clamp(math.floor(b), -999, 999))
	elseif action == "DevMail" and validRarity(a) and typeof(b) == "number" then
		HelperService.AddCouponMail(player, a :: string, math.clamp(math.floor(b), 1, 99))
	elseif action == "DevHelper" and typeof(a) == "string" then
		local parsed = HelperCatalog.Parse(a)
		if parsed then
			local isNew, stars = addHelper(player, p, a, parsed.Rarity)
			notify(player, string.format("[Fundador] %s %s (%d★)", HelperCatalog.FullName(parsed), if isNew then "añadido" else "repetido", stars))
		end
	elseif action == "DevLevel" and typeof(a) == "string" and typeof(b) == "number" then
		local e = p.Owned[a]
		if e then
			e.Level = math.clamp(math.floor(b), 1, HelperCatalog.MaxLevel)
			e.Xp = 0
		end
	elseif action == "DevEssence" and typeof(a) == "number" then
		p.Essence = math.max(0, p.Essence + math.clamp(math.floor(a), -9999, 9999))
	elseif action == "DevLevelAll" and typeof(a) == "number" then
		for _, e in pairs(p.Owned) do
			e.Level = math.clamp(math.floor(a), 1, HelperCatalog.MaxLevel)
			e.Xp = 0
		end
	elseif action == "DevReset" then
		p.Owned, p.Slots, p.Stock, p.Mail, p.Pity, p.DayCount, p.Pulls, p.Essence = {}, {}, {}, {}, {}, {}, 0, 0
	end
	changed(player)
end

---------------------------------------------------------------------
-- Remote de acciones (con límite de frecuencia)
---------------------------------------------------------------------
ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any, c: any)
	if typeof(action) ~= "string" or not profiles[player] then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.12 then
		return
	end
	lastAction[player] = now
	if action == "Sync" then
		push(player)
	elseif action == "State" then
		uiOpen[player] = true -- abrió una ventana de ayudantes: mientras esté abierta se le manda la XP al día
		push(player)
	elseif action == "Close" then
		uiOpen[player] = nil
	elseif action == "Equip" then
		equip(player, a, b)
	elseif action == "Unequip" then
		unequip(player, a)
	elseif action == "Recruit" then
		recruit(player, a, b)
	elseif action == "ClaimMail" then
		claimMail(player, a)
	elseif action == "GearEquip" then
		gearEquip(player, a, b, c)
	elseif action == "GearUnequip" then
		gearUnequip(player, a, b)
	elseif action == "GearAuto" then
		gearAuto(player, a)
	elseif action == "Ascend" then
		ascend(player, a)
	elseif action == "Branch" then
		setBranch(player, a, b)
	elseif action == "ClaimGift" then
		claimGift(player, a)
	elseif action == "Aura" then
		setAura(player, a, b)
	elseif action == "Nick" then
		setNick(player, a, b)
	elseif action == "ExchangePets" then
		exchangePets(player)
	elseif string.sub(action, 1, 3) == "Dev" then
		devAction(player, action, a, b)
	end
end)

---------------------------------------------------------------------
-- Carga y salida
---------------------------------------------------------------------
local function loadProfile(player: Player)
	local p = newProfile()
	local ok, data = pcall(function()
		return PlayerData.WaitForData(player)
	end)
	local sec: any = if ok and type(data) == "table" then (data :: any).Ayudantes else nil
	if type(sec) == "table" then
		if type(sec.O) == "table" then
			for id, raw in pairs(sec.O) do
				if type(id) == "string" and HelperCatalog.Parse(id) and type(raw) == "table" then
					local parsedLoad = HelperCatalog.Parse(id)
					local e = newEntry(if parsedLoad then parsedLoad.Rarity else nil)
					e.Stars = math.clamp(math.floor(tonumber(raw.S) or 1), 1, HelperCatalog.MaxStars)
					e.Level = math.clamp(math.floor(tonumber(raw.L) or 1), 1, HelperCatalog.MaxLevel)
					e.Xp = math.max(0, tonumber(raw.X) or 0)
					e.Asc = math.clamp(math.floor(tonumber(raw.A) or 0), 0, HelperCatalog.MaxAsc)
					if raw.B == "A" or raw.B == "B" then
						e.Branch = raw.B
					end
					if type(raw.K) == "string" and raw.K ~= "" and utf8.len(raw.K) and (utf8.len(raw.K) :: number) <= HelperCatalog.NickMax and validNickChars(raw.K) then
						e.Nick = raw.K
					end
					e.Gifts = math.clamp(math.floor(tonumber(raw.R) or 1), 1, HelperCatalog.MaxRank)
					-- aura guardada (clave V; la U antigua era un color y se ignora): entre la primera y la de su rareza
					if parsedLoad and raw.V ~= nil then
						e.Aura = HelperCatalog.ClampAura(tonumber(raw.V), parsedLoad.Rarity)
					end
					if type(raw.G) == "table" then
						for slotName, piece in pairs(raw.G) do
							if type(slotName) == "string" and table.find(HelperCatalog.GearSlots, slotName) and type(piece) == "table" and type(piece.I) == "string" and bagItem(piece.I) then
								e.Gear[slotName] = { Id = piece.I, Plus = math.clamp(math.floor(tonumber(piece.P) or 0), 0, 9) }
							end
						end
					end
					p.Owned[id] = e
				end
			end
		end
		if type(sec.S) == "table" then
			for key, id in pairs(sec.S) do
				local i = tonumber(key)
				if i and i >= 1 and i <= HelperCatalog.MaxSlots and type(id) == "string" and p.Owned[id] then
					p.Slots[math.floor(i)] = id
				end
			end
		end
		p.Stock = numberMap(sec.C, true)
		p.Mail = numberMap(sec.M, true)
		p.Pity = numberMap(sec.P, true)
		p.DayCount = numberMap(sec.DC, true)
		if type(sec.D) == "string" then
			p.Day = sec.D
		end
		p.Gift = sec.G == true
		p.Pulls = math.max(0, math.floor(tonumber(sec.N) or 0))
		p.Essence = math.max(0, math.floor(tonumber(sec.Es) or 0))
	end
	dayRollover(p)
	profiles[player] = p
	-- regalo de bienvenida (una sola vez por cuenta): llega a la carta
	if not p.Gift then
		p.Gift = true
		local parts: { string } = {}
		for _, rarity in ipairs(HelperCatalog.Rarities) do
			local n = HelperCatalog.WelcomeGift[rarity]
			if n and n > 0 then
				p.Mail[rarity] = (p.Mail[rarity] or 0) + n
				table.insert(parts, string.format("%d %s", n, HelperCatalog.Coupons[rarity].Name))
			end
		end
		task.delay(6, function()
			if player.Parent then
				notify(player, "🎁 ¡Regalo de bienvenida de ayudantes! (" .. table.concat(parts, " + ") .. ") — revisa la carta ✉")
			end
		end)
	end
	recompute(player)
	push(player)
end

local function watch(player: Player)
	task.spawn(loadProfile, player)
	-- el pase abre ranuras; tu nivel cambia el factor de los ayudantes y hasta dónde pueden subir
	for _, attr in ipairs({ HelperCatalog.PassAttr, "Level" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			if profiles[player] then
				changed(player)
			end
		end)
	end
end
Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end

PlayerData.Releasing:Connect(function(pl: Player)
	profiles[pl] = nil
	active[pl] = nil
	uiOpen[pl] = nil
	pushQueued[pl] = nil
	nickBusy[pl] = nil
	recruitAllowed[pl] = nil
	lastAction[pl] = nil
end)

local okData, why = HelperCatalog.Validate()
if not okData then
	warn("[HelperService] Probabilidades del catálogo mal: " .. why)
end

return HelperService
