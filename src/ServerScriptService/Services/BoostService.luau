--!strict
--[[
    BoostService (ModuleScript) -> ServerScriptService.Services.BoostService
    Antes este archivo era una COPIA VIEJA de BossService (invocaba un segundo jefe mundial). Ahora es un módulo mínimo:
    RewardService lo consulta con XpMult(jugador). Los boosts de XP reales viven en PurchaseService y BlessingService.
]]
local BoostService = {}

function BoostService.XpMult(_player: Player): number
	return 1
end

return BoostService
