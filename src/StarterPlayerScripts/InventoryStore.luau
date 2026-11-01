--!strict
--[[
    InventoryStore (ModuleScript) -> StarterPlayer > StarterPlayerScripts > InventoryStore
    Copia local del inventario que manda el servidor (remote InventoryUpdate). Lo comparten la mochila (I) y el perfil (C).
      Store.Bag[slot] = { Id, Count, Plus } · Store.Equip[slotName] = itemId · Store.EquipPlus[slotName] = +n de la pieza puesta
      Store.Capacity · Store.Changed (signal)
      Store.Action(...) pide una acción al servidor (Equip / Unequip / Move / Drop)
]]
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))

local Store = {}
Store.Bag = {} :: { [number]: { Id: string, Count: number, Plus: number } }
Store.Equip = {} :: { [string]: string }
Store.EquipPlus = {} :: { [string]: number }
Store.Capacity = 70
Store.Pages = 0 -- páginas de pago desbloqueadas (0..3)

local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event :: RBXScriptSignal

local updateRemote = ClientNet.Get("InventoryUpdate")
local actionRemote = ClientNet.Get("InventoryAction")

if updateRemote then
	updateRemote.OnClientEvent:Connect(function(list: any, equip: any, capacity: number, equipPlus: any, pages: any)
		local bag = {}
		for _, e in ipairs(list) do
			bag[e.Slot] = { Id = e.Id, Count = e.Count, Plus = e.Plus or 0 }
		end
		Store.Bag = bag
		Store.Equip = equip
		Store.EquipPlus = if typeof(equipPlus) == "table" then equipPlus else {}
		Store.Capacity = capacity
		Store.Pages = if typeof(pages) == "number" then pages else 0
		changed:Fire()
	end)
end

function Store.Action(action: string, a: any?, b: any?)
	if actionRemote then
		actionRemote:FireServer(action, a, b)
	end
end

-- el servidor mandó el inventario antes de que escucháramos: pide una copia
Store.Action("Sync")

return Store
