--!strict
--[[
    ClassSelectService (ModuleScript) -> ServerScriptService.Services.ClassSelectService
    SELECCIÓN DE FACCIÓN + ROL.
      - Al entrar: carga la elección guardada (DataStore). Si existe -> pone Faction/Role y ClassChosen=true.
        Si no existe (jugador nuevo) -> ClassChosen=false y el cliente muestra la pantalla de selección.
      - Remote "ChooseClass"(faction, role): el servidor valida contra FactionClassesModule, guarda,
        pone los atributos y reaparece al jugador en la ciudad de su facción (RespawnLocation lo fija ProjectBootstrapper).
      - Solo se puede elegir una vez. Para pruebas: workspace:SetAttribute("AllowReselect", true) permite volver a elegir
        (y en Studio puedes borrar tu elección con player:SetAttribute("ClassChosen", false) desde la consola del servidor).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")

local Net = require(ServerScriptService.Services.Net)
local FactionClasses = require(ReplicatedStorage.Modules.FactionClassesModule)

local STORE_NAME = "ClassChoice_v1"
local choose = Net.Get("ChooseClass")

local store: DataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
	end
end

local loaded: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}

local function applyChoice(player: Player, faction: string, role: string)
	player:SetAttribute("Faction", faction)
	player:SetAttribute("Role", role)
	player:SetAttribute("ClassChosen", true)
end

local function load(player: Player)
	local saved: any = nil
	if store then
		local ok, res = pcall(function()
			return (store :: DataStore):GetAsync("P_" .. player.UserId)
		end)
		if ok then
			saved = res
		end
	end
	if player.Parent == nil then
		return
	end
	if typeof(saved) == "table" and typeof(saved.Faction) == "string" and typeof(saved.Role) == "string"
		and FactionClasses.FindClass(saved.Faction, saved.Role) then
		applyChoice(player, saved.Faction, saved.Role)
	else
		player:SetAttribute("ClassChosen", false)
	end
	loaded[player] = true
end

local function save(player: Player)
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	if store and player:GetAttribute("ClassChosen") == true and typeof(faction) == "string" and typeof(role) == "string" then
		pcall(function()
			(store :: DataStore):SetAsync("P_" .. player.UserId, { Faction = faction, Role = role })
		end)
	end
end

choose.OnServerEvent:Connect(function(player: Player, faction: any, role: any)
	if not loaded[player] or busy[player] then
		return
	end
	if player:GetAttribute("ClassChosen") == true and Workspace:GetAttribute("AllowReselect") ~= true then
		return
	end
	if typeof(faction) ~= "string" or typeof(role) ~= "string" then
		return
	end
	if not FactionClasses.FindClass(faction, role) then
		return
	end
	busy[player] = true
	applyChoice(player, faction, role)
	save(player)
	task.wait(0.25) -- deja que ProjectBootstrapper actualice RespawnLocation de la nueva facción
	if player.Parent then
		player:LoadCharacter() -- reaparece en la ciudad de su facción con su clase nueva
	end
	busy[player] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	save(pl)
	loaded[pl] = nil
	busy[pl] = nil
end)
game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		save(pl)
	end
end)

return {}
