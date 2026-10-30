--!strict
--[[
    =================================================================================
    SCRIPT: PlayerClass.luau  (v2)
    UBICACIÓN: ReplicatedStorage.Modules.PlayerClass (ModuleScript)
    DESCRIPCIÓN: Un solo lugar para saber qué clase tiene un jugador.
      Lee los atributos del Player:
          Faction = "Saiyan" | "Shinobi" | "Pirate" | "Shinigami"   (también acepta "Pirata", "Saiyajin")
          Role    = "Tanque" | "Guerrero" | "Asesino" | "Tirador" | "Mago" | "Curador"
                    (o el personaje: "Goku", "Naruto", "Luffy"...; también inglés/minúsculas)
      Si faltan o son inválidos, usa Saiyan / Guerrero (Goku) y avisa UNA sola vez por valor.

      >>> Cuando tu pantalla de selección de clase elija una, solo tiene que hacer:
              player:SetAttribute("Faction", "Shinobi")
              player:SetAttribute("Role", "Asesino")
          y CombatService, EnergyRegenService y HUDManager se actualizan solos.
    =================================================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FactionClassesModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("FactionClassesModule"))

export type ClassData = FactionClassesModule.ClassData

local DEFAULT_FACTION = "Saiyan"
local DEFAULT_ROLE = "Guerrero"

local FACTION_ALIASES: { [string]: string } = {
	pirata = "Pirate",
	pirate = "Pirate",
	pirates = "Pirate",
	saiyan = "Saiyan",
	saiyajin = "Saiyan",
	shinobi = "Shinobi",
	shinigami = "Shinigami",
	bleach = "Shinigami",
}

local ROLE_ALIASES: { [string]: string } = {
	tank = "Tanque",
	warrior = "Guerrero",
	fighter = "Guerrero",
	assassin = "Asesino",
	marksman = "Tirador",
	archer = "Tirador",
	ranger = "Tirador",
	mage = "Mago",
	healer = "Curador",
	support = "Curador",
}

local PlayerClass = {}

-- Clave "factionAttr|roleAttr" ya avisada, por jugador
local warned: { [Player]: { [string]: boolean } } = {}

local function warnOnce(player: Player, key: string, message: string)
	local seen = warned[player]
	if not seen then
		seen = {}
		warned[player] = seen
	end
	if not seen[key] then
		seen[key] = true
		warn(message)
	end
end

local function fallbackClass(): ClassData
	local fallback = FactionClassesModule.FindClass(DEFAULT_FACTION, DEFAULT_ROLE)
	assert(fallback, "[PlayerClass] FactionClassesModule no tiene la clase por defecto")
	return fallback
end

function PlayerClass.Get(player: Player): ClassData
	local factionAttr = player:GetAttribute("Faction")
	local roleAttr = player:GetAttribute("Role")

	if typeof(factionAttr) ~= "string" or typeof(roleAttr) ~= "string" then
		warnOnce(player, "missing", string.format(
			"[PlayerClass] %s no tiene atributos Faction/Role. Usando %s/%s por defecto.",
			player.Name, DEFAULT_FACTION, DEFAULT_ROLE
			))
		return fallbackClass()
	end

	local faction = FACTION_ALIASES[factionAttr:lower()] or factionAttr
	local role = ROLE_ALIASES[roleAttr:lower()] or roleAttr

	-- FindClass no hace ruido: el aviso lo damos nosotros, una sola vez
	local data = FactionClassesModule.FindClass(faction, role)
	if data then
		return data
	end

	warnOnce(player, factionAttr .. "|" .. roleAttr, string.format(
		"[PlayerClass] %s tiene Faction='%s' Role='%s' (no existe). Usando %s/%s por defecto.",
		player.Name, factionAttr, roleAttr, DEFAULT_FACTION, DEFAULT_ROLE
		))
	return fallbackClass()
end

Players.PlayerRemoving:Connect(function(player: Player)
	warned[player] = nil
end)

return PlayerClass
