--!strict
--[[
    GameServerMain (Script, RunContext Server) -> ServerScriptService.GameServerMain
    ÚNICO Script "que arranca". Solo hace require() de los módulos en orden; no tiene lógica propia.
    Orden: balance -> datos -> servicios base -> mobs -> combate -> herramientas de prueba.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")

require(Services:WaitForChild("Net"))
require(Services:WaitForChild("PlayerData")) -- perfil único de cada jugador (nivel, clase, inventario): debe cargar antes que los servicios que lo usan
require(Services:WaitForChild("PlayerDefaults"))
require(Services:WaitForChild("ClassSelectService")) -- pantalla de selección de facción/rol
require(Services:WaitForChild("PlayerOutfits")) -- trajes de los 18 personajes
require(Services:WaitForChild("BridgeSigns")) -- carteles en el arco de cada puente
require(Services:WaitForChild("EnergyRegenService"))
require(Services:WaitForChild("ArenaGate"))
require(Services:WaitForChild("FactionZoneService"))
require(Services:WaitForChild("LevelService"))
require(Services:WaitForChild("StatService"))
require(Services:WaitForChild("ArenaService"))
require(Services:WaitForChild("DamageService"))
require(Services:WaitForChild("BoostService")) -- boosts activos (XP)
require(Services:WaitForChild("PartyService")) -- grupos (party)
require(Services:WaitForChild("RewardService"))
require(Services:WaitForChild("DeathService"))
require(Services:WaitForChild("AutoAttackService"))
require(Services:WaitForChild("InventoryService"))
require(Services:WaitForChild("Mobs"):WaitForChild("MobService"))
require(Services:WaitForChild("DevCommands"))
require(Services:WaitForChild("AbilityService")) -- habilidades 3 y 4
require(Services:WaitForChild("MetinService")) -- piedras Metin del evento de la Arena
require(Services:WaitForChild("BossService")) -- jefe mundial (cada 6 h)
require(Services:WaitForChild("AutoFarmService")) -- Auto-farm PvE (Semi / Metin / Jefe)
-- CombatService: se carga aquí por si nadie más lo requiere (require repetido devuelve el mismo módulo, no se duplica)
local combat = Services:FindFirstChild("CombatService")
if combat and combat:IsA("ModuleScript") then
	require(combat)
end

print("[GameServerMain] Sistema de enemigos / niveles / arena listo.")
