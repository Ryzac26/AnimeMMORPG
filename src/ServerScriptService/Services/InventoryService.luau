--!strict
--[[
    InventoryService (ModuleScript) -> ServerScriptService.Services.InventoryService
    Mochila y equipo de cada jugador (SERVIDOR = fuente de verdad; el cliente solo pide acciones).
      - Mochila AUTO-EXPANDIBLE: capacidad = max(20, siguiente múltiplo de 5 sobre las casillas usadas + 1).
        Si llenas todas las casillas aparece una fila nueva sola. Nunca hay un tope fijo.
      - Equipo: una casilla por ranura de ItemCatalog.EquipSlots (Casco, Arma, Capa, Alas, Montura, Traje...).
      - API: Add(player, itemId, count) -> bool · Get(player) -> estado
      - Acciones del cliente por el remote InventoryAction: ("Equip", bagIndex) · ("Unequip", slotName) · ("Move", a, b) · ("Drop", bagIndex)
    Persistencia (DataStore) y loot: pendientes por diseño; Add() es el punto de entrada para el loot futuro.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Net = require(ServerScriptService.Services.Net)

local UpdateRemote = Net.Get("InventoryUpdate")
local ActionRemote = Net.Get("InventoryAction")

local MIN_SLOTS = 20
local ROW = 5

type Stack = { Id: string, Count: number }
type State = { Bag: { [number]: Stack }, Equip: { [string]: string } }

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

Players.PlayerAdded:Connect(function(pl)
	states[pl] = { Bag = {}, Equip = {} }
	task.defer(push, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	states[pl] = states[pl] or { Bag = {}, Equip = {} }
	push(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	states[pl] = nil
end)

return Inventory
