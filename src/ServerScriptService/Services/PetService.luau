--!strict
--[[
    PetService (ModuleScript) -> ServerScriptService.Services.PetService
    ALIMENTAR MASCOTAS: sube el nivel de una mascota (1..10) gastando recursos de franja (PetCatalog.FeedCost).
    El nivel se guarda en el "Plus" de la mascota (nivel = Plus + 1), igual que la mejora del equipo, así viaja con ella
    (mochila, puesta, Maestría) y el perfil ya lo guarda. GearService multiplica los efectos por PetCatalog.LevelMult.
    Remote "PetFeed"(kind, key): kind "Equip" (key = "Accesorio2" o "Accesorio3" = Mascota 2) o "Bag" (key = número de casilla).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local ItemCatalog = require(Modules.ItemCatalog)
local PetCatalog = require(Modules.PetCatalog)
local LootTables = require(Modules.LootTables)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Inventory = require(Services.InventoryService)

local feedRemote = Net.Get("PetFeed")
local lastTry: { [Player]: number } = {}

local function notify(player: Player, text: string)
	Net.Get("Notify"):FireClient(player, text)
end

local function feed(player: Player, kind: any, key: any)
	local now = os.clock()
	if now - (lastTry[player] or 0) < 0.25 then
		return
	end
	lastTry[player] = now
	if (kind ~= "Equip" and kind ~= "Bag") or not PlayerData.IsReady(player) then
		return
	end
	if kind == "Equip" and key ~= "Accesorio2" and key ~= "Accesorio3" then
		return
	end
	if kind == "Bag" and typeof(key) ~= "number" then
		return
	end
	local id, plus = Inventory.GetPlus(player, kind, key)
	local item: any = if id then (ItemCatalog.Items :: any)[id] else nil
	if not id or not item or not item.Pet then
		notify(player, "Eso no es una mascota.")
		return
	end
	local level = PetCatalog.LevelOf(plus)
	if level >= PetCatalog.MaxLevel then
		notify(player, "Tu mascota ya está al nivel máximo.")
		return
	end
	local target = level + 1
	local res, count = PetCatalog.FeedCost(item.Rarity, target)
	local resName = (LootTables.Materials :: any)[res] and (LootTables.Materials :: any)[res].Name or res
	if Inventory.Count(player, res) < count then
		notify(player, string.format("Te faltan %s para alimentarla (necesitas %d).", resName, count))
		return
	end
	if not Inventory.Consume(player, res, count) then
		notify(player, "No se pudo gastar el alimento.")
		return
	end
	-- ¿sigue ahí la mascota? (comprobación tras cobrar)
	local id2, plus2 = Inventory.GetPlus(player, kind, key)
	if id2 ~= id or plus2 ~= plus then
		Inventory.Add(player, res, count)
		notify(player, "La mascota cambió de lugar. Inténtalo de nuevo.")
		return
	end
	if not Inventory.SetPlus(player, kind, key, target - 1) then
		Inventory.Add(player, res, count) -- no debería pasar: se devuelve el alimento
		notify(player, "No se pudo alimentar a la mascota.")
		return
	end
	local evolved = PetCatalog.Stage(target) > PetCatalog.Stage(level)
	if evolved then
		Net.Get("Notify"):FireAllClients(string.format("★ ¡%s hizo evolucionar a %s (nivel %d)!", player.DisplayName, item.Name, target))
	else
		notify(player, string.format("¡%s subió al nivel %d!", item.Name, target))
	end
	PlayerData.Save(player)
end

feedRemote.OnServerEvent:Connect(feed)
Players.PlayerRemoving:Connect(function(pl)
	lastTry[pl] = nil
end)

return {}
