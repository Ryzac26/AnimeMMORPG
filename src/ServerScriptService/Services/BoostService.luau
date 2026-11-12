--!strict
--[[
    BoostService (ModuleScript) -> ServerScriptService.Services.BoostService
    HERMANDAD DE FRANJA: +4% de XP por cada aliado de tu misma facción que esté en tu misma franja (bioma + franja), máximo +12%.
    RewardService consulta XpMult(jugador). Cada 3 s se avisa al cliente (remote "Boosts") para el cuadro "BOOST ACTIVO".
    Los demás boosts de XP viven en PurchaseService y BlessingService.
]]
local Players = game:GetService("Players")

local Net = require(script.Parent.Net)

local BoostService = {}

local PER_ALLY = 0.04
local MAX_BONUS = 0.12

local function allies(player: Player): number
	local faction, biome, strip = player:GetAttribute("Faction"), player:GetAttribute("Biome"), player:GetAttribute("Strip")
	if typeof(faction) ~= "string" or typeof(strip) ~= "number" then
		return 0
	end
	local n = 0
	for _, o in ipairs(Players:GetPlayers()) do
		if o ~= player and o:GetAttribute("Faction") == faction and o:GetAttribute("Strip") == strip and o:GetAttribute("Biome") == biome then
			n += 1
		end
	end
	return n
end

function BoostService.Bonus(player: Player): number
	return math.min(MAX_BONUS, allies(player) * PER_ALLY)
end

function BoostService.XpMult(player: Player): number
	return 1 + BoostService.Bonus(player)
end

local lastSent: { [Player]: number } = {}

task.spawn(function()
	while true do
		task.wait(3)
		for _, pl in ipairs(Players:GetPlayers()) do
			local b = BoostService.Bonus(pl)
			if lastSent[pl] ~= b then
				lastSent[pl] = b
				local list = {}
				if b > 0 then
					table.insert(list, {
						Name = "Hermandad de franja",
						Text = string.format("%d aliado(s) de tu facción en tu franja (+4%% c/u, máx +12%%)", math.floor(b / PER_ALLY + 0.5)),
						XpPct = b,
					})
				end
				Net.Get("Boosts"):FireClient(pl, list)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	lastSent[pl] = nil
end)

return BoostService
