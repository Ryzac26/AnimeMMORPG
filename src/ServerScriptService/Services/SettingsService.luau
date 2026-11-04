--!strict
--[[
    SettingsService (ModuleScript) -> ServerScriptService.Services.SettingsService
    AJUSTES del jugador, guardados en el perfil (sección "Settings" de PlayerData) y publicados como atributos del Player:
      Setting_PetsMode  "all" (todas) · "mine" (solo la mía) · "none" (ninguna)   -> PetFollowClient
    También publica PetHit (contador): sube cuando el jugador golpea a un mob, para que su mascota salte (solo visual).
    Remote: "SetSetting" (clave, valor) del cliente; se valida contra la lista de abajo.
]]
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local DamageService = require(Services.DamageService)

local DEFS: { [string]: { Default: string, Allowed: { string } } } = {
	PetsMode = { Default = "all", Allowed = { "all", "mine", "none" } },
}

local values: { [Player]: { [string]: string } } = {}

local function isAllowed(key: string, value: any): boolean
	local def = DEFS[key]
	return def ~= nil and typeof(value) == "string" and table.find(def.Allowed, value) ~= nil
end

local function publish(player: Player, key: string, value: string)
	player:SetAttribute("Setting_" .. key, value)
end

local function load(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local v: { [string]: string } = {}
	local section: any = saved.Settings
	for key, def in pairs(DEFS) do
		local val = def.Default
		if typeof(section) == "table" and isAllowed(key, section[key]) then
			val = section[key]
		end
		v[key] = val
		publish(player, key, val)
	end
	values[player] = v
end

PlayerData.RegisterSerializer("Settings", function(player: Player): any?
	local v = values[player]
	return if v then table.clone(v) else nil
end)

PlayerData.Releasing:Connect(function(player: Player)
	values[player] = nil
end)

Net.Get("SetSetting").OnServerEvent:Connect(function(player: Player, key: any, value: any)
	local v = values[player]
	if not v or typeof(key) ~= "string" or not isAllowed(key, value) then
		return
	end
	v[key] = value :: string
	publish(player, key, value :: string)
end)

-- Golpes del jugador a mobs -> PetHit (máx. 2 por segundo; solo adorno de la mascota)
local lastHit: { [Player]: number } = {}
DamageService.AddDamageListener(function(_mob: Model, player: Player, _amount: number)
	local now = os.clock()
	if now - (lastHit[player] or 0) < 0.5 then
		return
	end
	lastHit[player] = now
	player:SetAttribute("PetHit", (player:GetAttribute("PetHit") or 0) + 1)
end)
Players.PlayerRemoving:Connect(function(pl)
	lastHit[pl] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end

return {}
