--!strict
--[[
    InventoryService (ModuleScript) -> ServerScriptService.Services.InventoryService
    Mochila y equipo de cada jugador (SERVIDOR = fuente de verdad; el cliente solo pide acciones).
      - Mochila AUTO-EXPANDIBLE: capacidad = max(20, siguiente múltiplo de 5 sobre las casillas usadas + 1).
        Si llenas todas las casillas aparece una fila nueva sola. Nunca hay un tope fijo.
      - Equipo: una casilla por ranura de ItemCatalog.EquipSlots (Casco, Arma, Capa, Alas, Montura, Traje...).
      - API: Add(player, itemId, count) -> bool · Get(player) -> estado
      - Acciones del cliente por el remote InventoryAction: ("Equip", bagIndex) · ("Unequip", slotName) · ("Move", a, b) · ("Drop", bagIndex)
    Persistencia: sección "Inventory" de PlayerData (se guarda sola cada 120 s, al salir y al cerrar el servidor).
      - Al cargar se valida contra ItemCatalog. Un objeto que ya no existe (borrado o renombrado en el catálogo) NO se pierde:
        pasa a "Orphans" y se vuelve a guardar tal cual, por si más adelante se restaura el objeto.
      - Mientras el perfil carga, Get() devuelve nil y Add() devuelve false (el loot no debe llegar antes de cargar).
    Loot: Add() es el punto de entrada para el loot futuro.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)

local UpdateRemote = Net.Get("InventoryUpdate")
local ActionRemote = Net.Get("InventoryAction")

local MIN_SLOTS = 20
local ROW = 5
local MAX_SLOT = 1000 -- tope de seguridad al cargar datos (evita una mochila gigante por datos corruptos)

type Stack = { Id: string, Count: number }
type State = { Bag: { [number]: Stack }, Equip: { [string]: string }, Orphans: { Stack } }

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
	-- siempre queda al menos 1 casilla libre visible; crece de a filas completas
	local needed = usedSlots(st) + 1
	return math.max(MIN_SLOTS, math.ceil(needed / ROW) * ROW)
end

local function push(player: Player)
	local st = states[player]
	if st then
		-- lista plana (los remotes no conservan bien tablas con índices salteados)
		local list = {}
		for i, stack in pairs(st.Bag) do
			table.insert(list, { Slot = i, Id = stack.Id, Count = stack.Count })
		end
		UpdateRemote:FireClient(player, list, st.Equip, capacity(st))
	end
end

local function firstFree(st: State): number
	local i = 1
	while st.Bag[i] do
		i += 1
	end
	return i
end

---------------------------------------------------------------------
-- Guardado / carga (formato plano: el DataStore no admite índices con huecos)
---------------------------------------------------------------------
local function serialize(st: State): any
	local bag: { { Slot: number, Id: string, Count: number } } = {}
	for slot, stack in pairs(st.Bag) do
		table.insert(bag, { Slot = slot, Id = stack.Id, Count = stack.Count })
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
	return { Bag = bag, Equip = equip, Orphans = orphans }
end

local function deserialize(saved: any): State
	local st: State = { Bag = {}, Equip = {}, Orphans = {} }
	if typeof(saved) ~= "table" then
		return st
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
						st.Bag[slot] = { Id = id, Count = count }
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

function Inventory.Add(player: Player, itemId: string, count: number): boolean
	local st = states[player]
	local item = ItemCatalog.Items[itemId]
	if not st or not item or count <= 0 then
		return false
	end
	local maxStack = item.Stack or 1
	-- completar pilas existentes
	for _, stack in pairs(st.Bag) do
		if count <= 0 then
			break
		end
		if stack.Id == itemId and stack.Count < maxStack then
			local add = math.min(maxStack - stack.Count, count)
			stack.Count += add
			count -= add
		end
	end
	while count > 0 do
		local add = math.min(maxStack, count)
		st.Bag[firstFree(st)] = { Id = itemId, Count = add }
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

local function equip(player: Player, st: State, bagIndex: number)
	local stack = st.Bag[bagIndex]
	local item = stack and ItemCatalog.Items[stack.Id]
	if not stack or not item or not item.Slot then
		return
	end
	local slot = item.Slot :: string
	-- Accesorio: usa Accesorio1 y, si está ocupado, Accesorio2
	local previous = st.Equip[slot]
	st.Equip[slot] = stack.Id
	if stack.Count > 1 then
		stack.Count -= 1
		if previous then
			st.Bag[firstFree(st)] = { Id = previous, Count = 1 }
		end
	else
		st.Bag[bagIndex] = if previous then { Id = previous, Count = 1 } else nil
	end
	player:SetAttribute("Equip_" .. slot, st.Equip[slot])
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
		st.Equip[a] = nil
		player:SetAttribute("Equip_" .. a, nil)
		Inventory.Add(player, id, 1)
		return
	elseif action == "Move" and typeof(a) == "number" and typeof(b) == "number" then
		a, b = math.floor(a), math.floor(b)
		if a >= 1 and b >= 1 and b <= capacity(st) + 0 then
			st.Bag[a], st.Bag[b] = st.Bag[b], st.Bag[a]
		end
	elseif action == "Drop" and typeof(a) == "number" then
		st.Bag[math.floor(a)] = nil
	end
	push(player)
end)

local function init(pl: Player)
	local saved = PlayerData.WaitForData(pl)
	if not saved or pl.Parent == nil then
		return -- la carga falló (el jugador es expulsado) o ya salió
	end
	local st = deserialize(saved.Inventory)
	states[pl] = st
	-- AttackAnimator y compañía leen el equipo por atributos Equip_<ranura>: se restauran al cargar
	for slotName, id in pairs(st.Equip) do
		pl:SetAttribute("Equip_" .. slotName, id)
	end
	push(pl)
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
