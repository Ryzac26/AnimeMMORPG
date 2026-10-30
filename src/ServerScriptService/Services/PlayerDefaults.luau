--!strict
--[[
    PlayerDefaults (ModuleScript) -> ServerScriptService.Services.PlayerDefaults
    Si un jugador entra sin facción/rol (todavía no hay pantalla de selección), le pone Saiyan / Guerrero para que TODOS los
    sistemas (territorio, PvP, HUD, respawn en su ciudad) tengan datos reales. Cuando exista la selección de clase, ella
    sobrescribe estos atributos y esto deja de hacer algo.
]]
local Players = game:GetService("Players")

local function apply(pl: Player)
	if pl:GetAttribute("Faction") == nil then
		pl:SetAttribute("Faction", "Saiyan")
	end
	if pl:GetAttribute("Role") == nil then
		pl:SetAttribute("Role", "Guerrero")
	end
end

Players.PlayerAdded:Connect(apply)
for _, p in ipairs(Players:GetPlayers()) do
	apply(p)
end

return {}
