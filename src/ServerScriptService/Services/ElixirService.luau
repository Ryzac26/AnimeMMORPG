--!strict
--[[
    ElixirService (ModuleScript) -> ServerScriptService.Services.ElixirService
    ELIXIRES del Alquimista: efecto temporal (AlchemyCatalog.ELIXIR_SECONDS = 30 min) que se bebe desde la mochila
    (botón "Equipar" sobre el elixir) o desde la ventana del Alquimista. Solo UNO activo a la vez: beber otro reemplaza al actual;
    beber el mismo renueva el tiempo. El tiempo solo corre CONECTADO y se guarda con el perfil (sección "Elixir").
    El efecto entra como bono temporal de GearService (Oro, Suerte, Ataque, Vida, Regen), así que ya lo leen
    loot, daño, vida máxima y regeneración sin tocar nada más.
    Atributos del jugador (para la interfaz): ElixirId (string) · ElixirLeft (segundos restantes).
    API: Drink(player, idDelElixir) -> ok, mensaje · Active(player) -> id?, segundos
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AlchemyCatalog = require(ReplicatedStorage.Modules.AlchemyCatalog)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local Inventory = require(ServerScriptService.Services.InventoryService)
local GearService = require(ServerScriptService.Services.GearService)

local ElixirService = {}

local active: { [Player]: { Id: string, Left: number } } = {}

local function apply(player: Player)
	local a = active[player]
	if a then
		local def = AlchemyCatalog.Elixirs[a.Id]
		GearService.SetTemp(player, if def then def.Effect else nil)
		player:SetAttribute("ElixirId", a.Id)
		player:SetAttribute("ElixirLeft", math.ceil(a.Left))
	else
		GearService.SetTemp(player, nil)
		player:SetAttribute("ElixirId", nil)
		player:SetAttribute("ElixirLeft", nil)
	end
end

function ElixirService.Active(player: Player): (string?, number)
	local a = active[player]
	if a then
		return a.Id, a.Left
	end
	return nil, 0
end

-- Bebe un elixir de la mochila (consume 1). Devuelve ok y un mensaje para mostrar.
function ElixirService.Drink(player: Player, id: any): (boolean, string)
	local def = if typeof(id) == "string" then AlchemyCatalog.Elixirs[id] else nil
	local item: any = if def and typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
	if not def or not item or typeof(id) ~= "string" then
		return false, "Eso no es un elixir."
	end
	if not PlayerData.IsReady(player) then
		return false, "Tu perfil aún se está cargando."
	end
	if Inventory.Count(player, id) < 1 then
		return false, "No tienes ese elixir."
	end
	local prev = active[player]
	if not Inventory.Consume(player, id, 1) then
		return false, "No se pudo beber."
	end
	active[player] = { Id = id, Left = AlchemyCatalog.ELIXIR_SECONDS }
	apply(player)
	PlayerData.Save(player)
	local msg = string.format("Bebiste %s: %s durante %d min.", def.Name, def.Short, AlchemyCatalog.ELIXIR_SECONDS // 60)
	if prev and prev.Id ~= id then
		local old = AlchemyCatalog.Elixirs[prev.Id]
		msg ..= " Reemplaza a " .. (if old then old.Name else "el anterior") .. "."
	end
	return true, msg
end

PlayerData.RegisterSerializer("Elixir", function(player: Player): any?
	local a = active[player]
	if not a then
		return nil
	end
	return { Id = a.Id, Left = math.floor(a.Left) }
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = (saved :: any).Elixir
	if typeof(raw) == "table" and typeof(raw.Id) == "string" and typeof(raw.Left) == "number" and AlchemyCatalog.Elixirs[raw.Id] and raw.Left > 0 then
		active[player] = { Id = raw.Id, Left = math.min(raw.Left, AlchemyCatalog.ELIXIR_SECONDS) }
		apply(player)
	end
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
PlayerData.Releasing:Connect(function(player: Player)
	active[player] = nil
end)

task.spawn(function()
	while true do
		task.wait(1)
		for player, a in pairs(active) do
			a.Left -= 1
			if a.Left <= 0 then
				active[player] = nil
				apply(player)
				local def = AlchemyCatalog.Elixirs[a.Id]
				Net.Get("Notify"):FireClient(player, (if def then def.Name else "El elixir") .. " se acabó.")
			else
				player:SetAttribute("ElixirLeft", math.ceil(a.Left))
			end
		end
	end
end)

return ElixirService
