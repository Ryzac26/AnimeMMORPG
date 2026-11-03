--!strict
--[[
    InventoryService (ModuleScript) -> ServerScriptService.Services.InventoryService
    Mochila y equipo de cada jugador (SERVIDOR = fuente de verdad; el cliente solo pide acciones).
      - Mochila por PÁGINAS (ReplicatedStorage.Modules.BagCatalog): 2 páginas gratis de 35 casillas + 3 páginas de pago (Game Pass) de 40.
        Add() devuelve false si no cabe (mochila llena). "BuyPage" (remote InventoryAction) abre la compra de la siguiente página.
      - Equipo: una casilla por ranura de ItemCatalog.EquipSlots (Casco, Arma, Capa, Alas, Montura, Traje...).
      - API: Add(player, itemId, count, plus?) -> bool · Get(player) -> estado
      - Mejora +0..+9 (la hace el Herrero): cada pieza de equipo lleva su propio "Plus" (en la mochila: stack.Plus; puesta: st.EquipPlus[ranura],
        que también se publica como atributo EquipPlus_<ranura> para GearService). GetPlus / SetPlus trabajan con una referencia:
        ("Equip", "Arma") o ("Bag", 7).
      - Acciones del cliente por el remote InventoryAction: ("Equip", bagIndex) · ("Unequip", slotName) · ("Move", a, b) · ("Drop", bagIndex)
    Persistencia: sección "Inventory" de PlayerData (se guarda sola cada 120 s, al salir y al cerrar el servidor).
      - Al cargar se valida contra ItemCatalog. Un objeto que ya no existe (borrado o renombrado en el catálogo) NO se pierde:
        pasa a "Orphans" y se vuelve a guardar tal cual, por si más adelante se restaura el objeto.
      - Mientras el perfil carga, Get() devuelve nil y Add() devuelve false (el loot no debe llegar antes de cargar).
    Loot: Add() es el punto de entrada para el loot futuro.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local BagCatalog = require(ReplicatedStorage.Modules.BagCatalog)
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local GearService = require(ServerScriptService.Services.GearService)

local UpdateRemote = Net.Get("InventoryUpdate")
local ActionRemote = Net.Get("InventoryAction")

local MAX_SLOT = 1000 -- tope de seguridad al cargar datos (evita una mochila gigante por datos corruptos)

type Stack = { Id: string, Count: number, Plus: number?, Locked: boolean? }
type State = { Bag: { [number]: Stack }, Equip: { [string]: string }, EquipPlus: { [string]: number }, EquipLocked: { [string]: boolean }, Orphans: { Stack }, Pages: number }
local MAX_PLUS = 9

local function cleanPlus(item: any, plus: any): number
	if item and item.Gear and typeof(plus) == "number" then
		return math.clamp(math.floor(plus), 0, MAX_PLUS)
	end
	return 0
end

local Inventory = {}
local states: { [Player]: State } = {}

local function usedSlots(st: State): number
	local highest = 0
	for i in pairs(st.Bag) do
		highest = math.max(highest, i)
	end
	return highest
end

local function capacity(st: State): number
	-- tamaño fijo por páginas (BagCatalog); si hay objetos guardados más allá (datos viejos) se muestran igual
	return math.max(BagCatalog.Capacity(st.Pages), usedSlots(st))
end

local function push(player: Player)
	local st = states[player]
	if st then
		-- lista plana (los remotes no conservan bien tablas con índices salteados)
		local list = {}
		for i, stack in pairs(st.Bag) do
			table.insert(list, { Slot = i, Id = stack.Id, Count = stack.Count, Plus = stack.Plus or 0, Locked = stack.Locked == true })
		end
		UpdateRemote:FireClient(player, list, st.Equip, capacity(st), st.EquipPlus, st.Pages)
	end
end

local function firstFree(st: State): number
	local i = 1
	while st.Bag[i] do
		i += 1
	end
	return i
end

-- primera casilla libre DENTRO de la capacidad (nil = mochila llena)
local function firstFreeInside(st: State): number?
	local cap = capacity(st)
	for i = 1, cap do
		if not st.Bag[i] then
			return i
		end
	end
	return nil
end

-- ¿Cabe `count` de este objeto? (completando pilas existentes y usando casillas libres)
local function canFit(st: State, itemId: string, count: number, plus: number, locked: boolean?): boolean
	local item = ItemCatalog.Items[itemId]
	if not item then
		return false
	end
	local maxStack = item.Stack or 1
	local room = 0
	for _, stack in pairs(st.Bag) do
		if stack.Id == itemId and (stack.Plus or 0) == plus and stack.Count < maxStack and not stack.Locked and not locked then
			room += maxStack - stack.Count
		end
	end
	local free = 0
	for i = 1, capacity(st) do
		if not st.Bag[i] then
			free += 1
		end
	end
	return room + free * maxStack >= count
end

---------------------------------------------------------------------
-- Guardado / carga (formato plano: el DataStore no admite índices con huecos)
---------------------------------------------------------------------
local function serialize(st: State): any
	local bag: { { Slot: number, Id: string, Count: number, Plus: number?, Locked: boolean? } } = {}
	for slot, stack in pairs(st.Bag) do
		table.insert(bag, { Slot = slot, Id = stack.Id, Count = stack.Count, Plus = stack.Plus, Locked = if stack.Locked then true else nil })
	end
	table.sort(bag, function(a: { Slot: number }, b: { Slot: number }): boolean
		return a.Slot < b.Slot
	end)
	local equip = {}
	for slotName, id in pairs(st.Equip) do
		equip[slotName] = id
	end
	local orphans = {}
	for _, o in ipairs(st.Orphans) do
		table.insert(orphans, { Id = o.Id, Count = o.Count })
	end
	local equipPlus = {}
	for slotName, plus in pairs(st.EquipPlus) do
		if plus > 0 then
			equipPlus[slotName] = plus
		end
	end
	local equipLocked = {}
	for slotName, v in pairs(st.EquipLocked) do
		if v then
			equipLocked[slotName] = true
		end
	end
	return { Bag = bag, Equip = equip, EquipPlus = equipPlus, EquipLocked = equipLocked, Orphans = orphans, Pages = st.Pages }
end

local function deserialize(saved: any): State
	local st: State = { Bag = {}, Equip = {}, EquipPlus = {}, EquipLocked = {}, Orphans = {}, Pages = 0 }
	if typeof(saved) ~= "table" then
		return st
	end
	if typeof(saved.Pages) == "number" then
		st.Pages = math.clamp(math.floor(saved.Pages), 0, BagCatalog.MaxPaid())
	end
	local orphans: any = saved.Orphans
	if typeof(orphans) == "table" then
		for _, entry in ipairs(orphans) do
			local o: any = entry
			local id, count = o.Id, o.Count
			if typeof(o) == "table" and typeof(id) == "string" and typeof(count) == "number" then
				table.insert(st.Orphans, { Id = id, Count = math.floor(count) })
			end
		end
	end
	local bag: any = saved.Bag
	if typeof(bag) == "table" then
		for _, entry in ipairs(bag) do
			local e: any = entry
			local id, slotNumber, countNumber = e.Id, e.Slot, e.Count
			if typeof(e) == "table" and typeof(id) == "string" and typeof(slotNumber) == "number" and typeof(countNumber) == "number" then
				local count = math.floor(countNumber)
				if count >= 1 then
					if not (ItemCatalog.Items :: any)[id] then
						table.insert(st.Orphans, { Id = id, Count = count }) -- el objeto ya no existe en el catálogo
					else
						local slot = math.floor(slotNumber)
						if slot < 1 or slot > MAX_SLOT or st.Bag[slot] ~= nil then
							slot = firstFree(st) -- casilla inválida o repetida: no se pierde, va a la primera libre
						end
						local plus = cleanPlus((ItemCatalog.Items :: any)[id], e.Plus)
						st.Bag[slot] = { Id = id, Count = count, Plus = if plus > 0 then plus else nil, Locked = if e.Locked == true then true else nil }
					end
				end
			end
		end
	end
	local equip: any = saved.Equip
	if typeof(equip) == "table" then
		for slotName, id in pairs(equip) do
			if typeof(slotName) == "string" and typeof(id) == "string" then
				local item = (ItemCatalog.Items :: any)[id]
				if not item then
					table.insert(st.Orphans, { Id = id, Count = 1 })
				elseif item.Slot == slotName then
					st.Equip[slotName] = id
					local savedPlus: any = if typeof(saved.EquipPlus) == "table" then saved.EquipPlus[slotName] else nil
					local plus = cleanPlus(item, savedPlus)
					if plus > 0 then
						st.EquipPlus[slotName] = plus
					end
					if typeof(saved.EquipLocked) == "table" and saved.EquipLocked[slotName] == true then
						st.EquipLocked[slotName] = true
					end
				else
					st.Bag[firstFree(st)] = { Id = id, Count = 1 } -- cambió la ranura del objeto en el catálogo: vuelve a la mochila
				end
			end
		end
	end
	return st
end

function Inventory.Get(player: Player): State?
	return states[player]
end

function Inventory.Add(player: Player, itemId: string, count: number, plus: number?, locked: boolean?): boolean
	local st = states[player]
	local item = ItemCatalog.Items[itemId]
	if not st or not item or count <= 0 then
		return false
	end
	local maxStack = item.Stack or 1
	local plusValue = cleanPlus(item, plus)
	if not canFit(st, itemId, count, plusValue, locked) then
		Net.Get("Notify"):FireClient(player, "Mochila llena: libera espacio (o desbloquea más páginas)")
		return false
	end
	-- completar pilas existentes (solo con el mismo nivel de mejora)
	for _, stack in pairs(st.Bag) do
		if count <= 0 then
			break
		end
		if stack.Id == itemId and (stack.Plus or 0) == plusValue and stack.Count < maxStack and not stack.Locked and not locked then
			local add = math.min(maxStack - stack.Count, count)
			stack.Count += add
			count -= add
		end
	end
	while count > 0 do
		local add = math.min(maxStack, count)
		st.Bag[firstFreeInside(st) :: number] = { Id = itemId, Count = add, Plus = if plusValue > 0 then plusValue else nil, Locked = if locked then true else nil }
		count -= add
	end
	push(player)
	return true
end

-- Cantidad total de un objeto en la mochila
function Inventory.Count(player: Player, itemId: string): number
	local st = states[player]
	local n = 0
	if st then
		for _, stack in pairs(st.Bag) do
			if stack.Id == itemId then
				n += stack.Count
			end
		end
	end
	return n
end

-- Gasta 1 (o count) del objeto. Devuelve true si había suficientes.
function Inventory.Consume(player: Player, itemId: string, count: number?): boolean
	local st = states[player]
	local need = count or 1
	if not st or Inventory.Count(player, itemId) < need then
		return false
	end
	for slot, stack in pairs(st.Bag) do
		if need <= 0 then
			break
		end
		if stack.Id == itemId then
			local take = math.min(stack.Count, need)
			stack.Count -= take
			need -= take
			if stack.Count <= 0 then
				st.Bag[slot] = nil
			end
		end
	end
	push(player)
	return true
end

-- Quita (hasta) count unidades de UNA casilla de la mochila (venta, tienda). Devuelve itemId, plus, cantidad quitada (nil,0,0 si no hay nada).
function Inventory.RemoveSlot(player: Player, index: number, count: number?): (string?, number, number)
	local st = states[player]
	local stack = if st then st.Bag[math.floor(index)] else nil
	if not st or not stack or stack.Locked then
		return nil, 0, 0 -- lo bloqueado (candado) nunca se vende ni se quita por aquí
	end
	local take = math.clamp(math.floor(count or stack.Count), 1, stack.Count)
	local id, plus = stack.Id, stack.Plus or 0
	stack.Count -= take
	if stack.Count <= 0 then
		st.Bag[math.floor(index)] = nil
	end
	push(player)
	return id, plus, take
end

-- Mejora +n de una pieza. ref: ("Equip", "Arma") o ("Bag", 7). Devuelve itemId, plus (o nil si no hay nada ahí).
function Inventory.GetPlus(player: Player, kind: string, key: any): (string?, number)
	local st = states[player]
	if not st then
		return nil, 0
	end
	if kind == "Equip" and typeof(key) == "string" then
		local id = st.Equip[key]
		return id, if id then (st.EquipPlus[key] or 0) else 0
	elseif kind == "Bag" and typeof(key) == "number" then
		local stack = st.Bag[math.floor(key)]
		return if stack then stack.Id else nil, if stack then (stack.Plus or 0) else 0
	end
	return nil, 0
end

function Inventory.SetPlus(player: Player, kind: string, key: any, plus: number): boolean
	local st = states[player]
	if not st then
		return false
	end
	local value = math.clamp(math.floor(plus), 0, MAX_PLUS)
	if kind == "Equip" and typeof(key) == "string" and st.Equip[key] then
		st.EquipPlus[key] = if value > 0 then value else nil
		player:SetAttribute("EquipPlus_" .. key, if value > 0 then value else nil)
	elseif kind == "Bag" and typeof(key) == "number" and st.Bag[math.floor(key)] then
		local stack = st.Bag[math.floor(key)]
		if stack.Count ~= 1 then
			return false
		end
		stack.Plus = if value > 0 then value else nil
	else
		return false
	end
	push(player)
	return true
end

local function equip(player: Player, st: State, bagIndex: number)
	local stack = st.Bag[bagIndex]
	local item = stack and ItemCatalog.Items[stack.Id]
	if stack and item and item.Elixir then
		-- elixir del Alquimista: "Equipar" lo bebe (carga perezosa: ElixirService requiere este módulo)
		local ok, ElixirService = pcall(require, game:GetService("ServerScriptService").Services.ElixirService)
		if ok then
			local _, msg = (ElixirService :: any).Drink(player, stack.Id)
			Net.Get("Notify"):FireClient(player, msg)
			return
		end
		return
	end
	if not stack or not item or not item.Slot then
		return
	end
	-- nivel, rol, facción y arma propia de la clase (sets de clase, Emblema de facción)
	local allowed, reason = GearService.CanEquip(player, stack.Id)
	if not allowed then
		Net.Get("Notify"):FireClient(player, reason or "No puedes equipar esto")
		return
	end
	if stack.Count > 1 and st.Equip[item.Slot :: string] and not firstFreeInside(st) then
		Net.Get("Notify"):FireClient(player, "Mochila llena: no hay dónde dejar la pieza que llevas puesta")
		return
	end
	local slot = item.Slot :: string
	-- Accesorio: usa Accesorio1 y, si está ocupado, Accesorio2
	local previous = st.Equip[slot]
	local previousPlus = st.EquipPlus[slot]
	local previousLocked = st.EquipLocked[slot]
	local newPlus = stack.Plus or 0
	st.Equip[slot] = stack.Id
	st.EquipPlus[slot] = if newPlus > 0 then newPlus else nil
	st.EquipLocked[slot] = if stack.Locked then true else nil -- el candado viaja con la pieza
	local previousStack: Stack? = if previous then { Id = previous, Count = 1, Plus = previousPlus, Locked = previousLocked } else nil
	if stack.Count > 1 then
		stack.Count -= 1
		if previousStack then
			st.Bag[firstFreeInside(st) :: number] = previousStack
		end
	else
		st.Bag[bagIndex] = previousStack
	end
	player:SetAttribute("Equip_" .. slot, st.Equip[slot])
	player:SetAttribute("EquipPlus_" .. slot, if newPlus > 0 then newPlus else nil)
end

-- Poder de una pieza = suma de sus bonos x multiplicador de mejora (igual que la comparación de la mochila)
local function powerOf(player: Player, item: any, plus: number): number
	if item and item.Gear then
		local mult = GearCatalog.EnhanceMult(plus)
		local effects: { [string]: number } = {}
		for stat, v in pairs(item.Gear) do
			effects[stat] = v * mult
		end
		local role = player:GetAttribute("Role")
		return GearCatalog.PowerGain(if typeof(role) == "string" then role else "Guerrero", effects)
	end
	return 0
end

-- EQUIPAR MEJOR SET: por cada ranura deja la pieza más fuerte que tu clase y nivel pueden usar.
-- Lo que llevas puesto y ya no puedes usar (cambio de clase) vuelve a la mochila si hay espacio.
local function equipBest(player: Player, st: State)
	local changed = 0
	for _, slotName in ipairs(ItemCatalog.EquipSlots) do
		local curId = st.Equip[slotName]
		local curItem: any = if curId then (ItemCatalog.Items :: any)[curId] else nil
		local curUsable = curItem ~= nil and GearService.CanEquip(player, curId :: string)
		local bestPower = if curItem and curUsable then powerOf(player, curItem, st.EquipPlus[slotName] or 0) else 0
		local bestIndex: number? = nil
		for i, stack in pairs(st.Bag) do
			local item: any = (ItemCatalog.Items :: any)[stack.Id]
			if item and item.Slot == slotName and item.Gear and not item.Pet and GearService.CanEquip(player, stack.Id) then
				local p = powerOf(player, item, stack.Plus or 0)
				if p > bestPower + 1e-9 then
					bestPower, bestIndex = p, i
				end
			end
		end
		if bestIndex then
			equip(player, st, bestIndex)
			changed += 1
		elseif curItem and not curUsable and canFit(st, curId :: string, 1, st.EquipPlus[slotName] or 0) then
			local plus = st.EquipPlus[slotName]
			local wasLocked = st.EquipLocked[slotName]
			st.Equip[slotName] = nil
			st.EquipPlus[slotName] = nil
			st.EquipLocked[slotName] = nil
			player:SetAttribute("Equip_" .. slotName, nil)
			player:SetAttribute("EquipPlus_" .. slotName, nil)
			Inventory.Add(player, curId :: string, 1, plus, wasLocked)
			changed += 1
		end
	end
	Net.Get("Notify"):FireClient(player, if changed > 0 then string.format("Mejor set: %d pieza(s) cambiadas", changed) else "Ya llevas lo mejor que puedes usar")
end

-- ORDENAR: junta lo apilable (pociones, materiales) y ordena todo por rareza (Mítico primero), luego equipo antes que materiales
local RARITY_RANK: { [string]: number } = { Mitico = 5, Legendario = 4, Epico = 3, Raro = 2, Comun = 1 }
local function sortBag(st: State)
	local stacks: { Stack } = {}
	local merged: { [string]: Stack } = {}
	for _, stack in pairs(st.Bag) do
		local item: any = (ItemCatalog.Items :: any)[stack.Id]
		local maxStack = if item then (item.Stack or 1) else 1
		local key = stack.Id .. "|" .. tostring(stack.Plus or 0) .. "|" .. tostring(stack.Locked == true)
		local target = merged[key]
		if maxStack > 1 and target and target.Count < maxStack then
			local move = math.min(maxStack - target.Count, stack.Count)
			target.Count += move
			if stack.Count - move > 0 then
				local rest = { Id = stack.Id, Count = stack.Count - move, Plus = stack.Plus, Locked = stack.Locked }
				table.insert(stacks, rest)
				merged[key] = rest
			end
		else
			table.insert(stacks, stack)
			if maxStack > 1 then
				merged[key] = stack
			end
		end
	end
	table.sort(stacks, function(x: Stack, y: Stack): boolean
		local ix: any, iy: any = (ItemCatalog.Items :: any)[x.Id], (ItemCatalog.Items :: any)[y.Id]
		local rx = if ix then (RARITY_RANK[ix.Rarity] or 0) else 0
		local ry = if iy then (RARITY_RANK[iy.Rarity] or 0) else 0
		if rx ~= ry then
			return rx > ry
		end
		local gx = if ix and ix.Slot then 1 else 0
		local gy = if iy and iy.Slot then 1 else 0
		if gx ~= gy then
			return gx > gy -- el equipo antes que lo demás
		end
		local sx = if ix and ix.Slot then ix.Slot else ""
		local sy = if iy and iy.Slot then iy.Slot else ""
		if sx ~= sy then
			return sx < sy
		end
		if (x.Plus or 0) ~= (y.Plus or 0) then
			return (x.Plus or 0) > (y.Plus or 0)
		end
		if x.Id ~= y.Id then
			return x.Id < y.Id
		end
		return x.Count > y.Count
	end)
	st.Bag = {}
	for i, stack in ipairs(stacks) do
		st.Bag[i] = stack
	end
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local st = states[player]
	if not st or typeof(action) ~= "string" then
		return
	end
	if action == "Equip" and typeof(a) == "number" then
		equip(player, st, math.floor(a))
	elseif action == "Unequip" and typeof(a) == "string" and st.Equip[a] then
		local id = st.Equip[a]
		local plus = st.EquipPlus[a]
		if not canFit(st, id, 1, plus or 0, st.EquipLocked[a]) then
			Net.Get("Notify"):FireClient(player, "Mochila llena: libera espacio para quitarte esto")
			return
		end
		local wasLocked = st.EquipLocked[a]
		st.Equip[a] = nil
		st.EquipPlus[a] = nil
		st.EquipLocked[a] = nil
		player:SetAttribute("Equip_" .. a, nil)
		player:SetAttribute("EquipPlus_" .. a, nil)
		Inventory.Add(player, id, 1, plus, wasLocked)
		return
	elseif action == "Move" and typeof(a) == "number" and typeof(b) == "number" then
		a, b = math.floor(a), math.floor(b)
		if a >= 1 and b >= 1 and b <= capacity(st) + 0 then
			st.Bag[a], st.Bag[b] = st.Bag[b], st.Bag[a]
		end
	elseif action == "Sort" then
		sortBag(st)
	elseif action == "EquipBest" then
		equipBest(player, st)
	elseif action == "BuyPage" then
		Inventory.RequestPage(player)
		return
	elseif action == "Lock" and typeof(a) == "number" and a == a then
		local stack = st.Bag[math.floor(a)]
		if stack then
			stack.Locked = if stack.Locked then nil else true -- candado: pone / quita
		end
	elseif action == "Drop" and typeof(a) == "number" and a == a then
		local stack = st.Bag[math.floor(a)]
		if stack and stack.Locked then
			Net.Get("Notify"):FireClient(player, "Está bloqueado 🔒: quítale el candado para tirarlo")
			return
		end
		st.Bag[math.floor(a)] = nil
	end
	push(player)
end)

---------------------------------------------------------------------
-- Páginas de pago (Game Pass). Se compran en orden: la 3, luego la 4, luego la 5.
---------------------------------------------------------------------
local function unlockTo(player: Player, paid: number)
	local st = states[player]
	if st and paid > st.Pages and paid <= BagCatalog.MaxPaid() then
		st.Pages = paid
		push(player)
		PlayerData.Save(player)
		Net.Get("Notify"):FireClient(player, string.format("¡Página %d de la mochila desbloqueada! (+%d casillas)", BagCatalog.FreePages + paid, BagCatalog.PageSizes[BagCatalog.FreePages + paid]))
	end
end

function Inventory.RequestPage(player: Player)
	local st = states[player]
	if not st then
		return
	end
	local nextPaid = st.Pages + 1
	if nextPaid > BagCatalog.MaxPaid() then
		return
	end
	local passId = BagCatalog.GamePassIds[nextPaid]
	if passId and passId > 0 then
		local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, passId)
		if not ok then
			warn("[InventoryService] No se pudo abrir la compra de la página: " .. tostring(err))
		end
	elseif RunService:IsStudio() then
		unlockTo(player, nextPaid) -- prueba en Studio: sin pase configurado se desbloquea gratis
	else
		Net.Get("Notify"):FireClient(player, "Esta página aún no está a la venta")
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	for i, id in ipairs(BagCatalog.GamePassIds) do
		if id == passId and id > 0 then
			unlockTo(player, i)
		end
	end
end)

-- al entrar: si ya tenía algún pase (otro servidor, compra anterior) se reconocen sus páginas
local function checkOwnedPasses(player: Player)
	for i, id in ipairs(BagCatalog.GamePassIds) do
		if id > 0 and states[player] then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, id)
			if ok and owns then
				unlockTo(player, i)
			end
		end
	end
end

local function init(pl: Player)
	local saved = PlayerData.WaitForData(pl)
	if not saved or pl.Parent == nil then
		return -- la carga falló (el jugador es expulsado) o ya salió
	end
	local st = deserialize(saved.Inventory)
	local ignorePasses = RunService:IsStudio() and BagCatalog.DevIgnorePasses
	if ignorePasses then
		st.Pages = 0 -- prueba en Studio: se ven las páginas de pago como las vería un jugador nuevo
	end
	states[pl] = st
	-- AttackAnimator y compañía leen el equipo por atributos Equip_<ranura>: se restauran al cargar
	for slotName, id in pairs(st.Equip) do
		pl:SetAttribute("Equip_" .. slotName, id)
		pl:SetAttribute("EquipPlus_" .. slotName, st.EquipPlus[slotName])
	end
	push(pl)
	if not ignorePasses then
		task.spawn(checkOwnedPasses, pl)
	end
	-- cambio de clase: lo puesto que la nueva clase no puede usar vuelve a la mochila (lo que todas las clases usan se queda puesto)
	pl:GetAttributeChangedSignal("Role"):Connect(function()
		task.wait(0.4) -- deja que ClassSelectService termine de aplicar facción y rol
		local cur = states[pl]
		if not cur then
			return
		end
		local moved = 0
		for _, slotName in ipairs(ItemCatalog.EquipSlots) do
			local id = cur.Equip[slotName]
			if id and not GearService.CanEquip(pl, id) then
				local plus = cur.EquipPlus[slotName]
				local wasLocked = cur.EquipLocked[slotName]
				if canFit(cur, id, 1, plus or 0, wasLocked) then
					cur.Equip[slotName] = nil
					cur.EquipPlus[slotName] = nil
					cur.EquipLocked[slotName] = nil
					pl:SetAttribute("Equip_" .. slotName, nil)
					pl:SetAttribute("EquipPlus_" .. slotName, nil)
					Inventory.Add(pl, id, 1, plus, wasLocked)
					moved += 1
				end
			end
		end
		if moved > 0 then
			Net.Get("Notify"):FireClient(pl, string.format("Cambio de clase: %d pieza(s) que tu nueva clase no usa volvieron a la mochila", moved))
		end
	end)
end

-- Qué guarda PlayerData de este servicio (nil = todavía no cargó: no se toca la sección)
PlayerData.RegisterSerializer("Inventory", function(player: Player): any?
	local st = states[player]
	if st then
		return serialize(st)
	end
	return nil
end)

-- PlayerData avisa DESPUÉS de tomar la foto final de datos: ahora sí se puede limpiar
PlayerData.Releasing:Connect(function(pl: Player)
	states[pl] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end

return Inventory
