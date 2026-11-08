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
require(Services:WaitForChild("WalletService")) -- oro y puntos de facción
require(Services:WaitForChild("LootService")) -- botín de mobs, Metin y jefes (necesita RewardService, Inventory, Wallet)
require(Services:WaitForChild("HerreroService")) -- herrero de cada ciudad: mejora +1..+9 del equipo
require(Services:WaitForChild("BlessingService")) -- bendiciones de facción de pago (Tienda)
require(Services:WaitForChild("PurchaseService")) -- compras repetibles: boost de XP y paquetes de horas (Tienda)
require(Services:WaitForChild("InstructorService")) -- instructor de cada ciudad: cambio de clase gratis
require(Services:WaitForChild("MercaderService")) -- mercader de cada ciudad: compra pociones, vende botín
require(Services:WaitForChild("MissionService")) -- misiones del Pabellón VIP (NPC en cada ciudad) y marcos de perfil
require(Services:WaitForChild("HouseService")) -- Casa VIP (Pabellón Imperial): portal, salón privado, baúl, invitados
require(Services:WaitForChild("VipShopService")) -- Tienda VIP del Mes (Sellos Imperiales, solo cosméticos)
require(Services:WaitForChild("TitleService")) -- títulos únicos (desbloqueo, equipado y cartel sobre la cabeza)
require(Services:WaitForChild("HallService")) -- Salón de Honor del Gremio: rankings globales por facción y maniquíes
require(Services:WaitForChild("GuildService")) -- gremio de facción: bendiciones por aportes (DataStore compartido)
require(Services:WaitForChild("MasteryService")) -- maestría de rol + pase Multiclase (cambio de rol en cualquier lugar, equipo por rol)
require(Services:WaitForChild("AlquimistaService")) -- alquimista de cada ciudad: fabrica pociones y desmonta equipo
require(Services:WaitForChild("Mobs"):WaitForChild("MobService"))
require(Services:WaitForChild("DevCommands"))
require(Services:WaitForChild("AbilityService")) -- habilidades 3 y 4
require(Services:WaitForChild("MetinService")) -- piedras Metin del evento de la Arena
require(Services:WaitForChild("BossService")) -- jefe mundial (cada 6 h)
require(Services:WaitForChild("AutoFarmService")) -- Auto-farm PvE (Semi / Metin / Jefe)
require(Services:WaitForChild("CityStyler")) -- estilo anime de las 4 ciudades (usa CityAssets)
require(Services:WaitForChild("ArenaStyler")) -- Arena: campamentos, altares, santuarios y temas rotativos
require(Services:WaitForChild("BiomeStyler")) -- biomas PvE de las 4 franjas de cada facción (suelo, muros, ríos, árboles, escenografía)
require(Services:WaitForChild("PveZoneService")) -- campamentos, altares de ofrenda y desafío, cofres, mini jefes y recolección de las 16 franjas
require(Services:WaitForChild("BiomeDetails")) -- detalles de suelo (senderos, charcos, grietas, flores) y partículas de ambiente por franja
require(Services:WaitForChild("BiomeLandmarks")) -- hitos temáticos: un monumento grande por franja (16)
require(Services:WaitForChild("DamageRankService")) -- ranking de daño en pantalla para jefes, mini jefes y Metin
require(Services:WaitForChild("PetPowerService")) -- poderes de las mascotas Épicas, Legendarias y Míticas
require(Services:WaitForChild("PetService")) -- alimentar mascotas: suben de nivel 1..10 (Plus de la mascota)
require(Services:WaitForChild("SettingsService")) -- ajustes del jugador (ocultar mascotas) guardados en el perfil
require(Services:WaitForChild("MountService")) -- monturas: huevos, incubadora, eclosión, montar y pasivas
require(Services:WaitForChild("IncubatorService")) -- incubadora de cada ciudad (junto al Mercader)
require(Services:WaitForChild("NestService")) -- nidos con guardianes en las franjas PvE
require(Services:WaitForChild("StreamService")) -- pide al cliente que cargue el mapa donde aparece (Roblox web)
require(Services:WaitForChild("WorldReadyService")) -- mundo listo: espera mapa + estilos y mantiene quieto al jugador hasta que su pantalla cargue
-- CombatService: se carga aquí por si nadie más lo requiere (require repetido devuelve el mismo módulo, no se duplica)
local combat = Services:FindFirstChild("CombatService")
if combat and combat:IsA("ModuleScript") then
	require(combat)
end

print("[GameServerMain] Sistema de enemigos / niveles / arena listo.")
