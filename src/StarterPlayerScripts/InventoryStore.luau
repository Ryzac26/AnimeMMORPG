--!strict
--[[
    InventoryStore (ModuleScript) -> StarterPlayer > StarterPlayerScripts > InventoryStore
    Copia local del inventario que manda el servidor (remote InventoryUpdate). Lo comparten la mochila (I) y el perfil (C).
      Store.Bag[slot] = { Id, Count } · Store.Equip[slotName] = itemId · Store.Capacity · Store.Changed (signal)
      Store.Action(...) pide una acción al servidor (Equip / Unequip / Move / Drop)
]]
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))

local Store = {}
Store.Bag = {} :: { [number]: { Id: string, Count: number } }
Store.Equip = {} :: { [string]: string }
Store.Capacity = 20

local changed = Instance.new("BindableEvent")
Store.Changed = changed.Event :: RBXScriptSignal

local updateRemote = ClientNet.Get("InventoryUpdate")
local actionRemote = ClientNet.Get("InventoryAction")

if updateRemote then
	updateRemote.OnClientEvent:Connect(function(list: any, equip: any, capacity: number)
		local bag = {}
		for _, e in ipairs(list) do
			bag[e.Slot] = { Id = e.Id, Count = e.Count }
		end
		Store.Bag = bag
		Store.Equip = equip
		Store.Capacity = capacity
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
