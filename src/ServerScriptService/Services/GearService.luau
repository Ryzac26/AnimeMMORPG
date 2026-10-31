--!strict
--[[
    GearService (ModuleScript) -> ServerScriptService.Services.GearService
    Convierte el EQUIPO y la MASCOTA en estadísticas reales. Lee los atributos Equip_<ranura> que pone InventoryService
    (y EquipPlus_<ranura> = mejora +0..+9, para cuando exista). Recalcula solo cuando algo cambia.

    Get(player) -> { Ataque, Defensa, Vida, Critico, Curacion, Suerte, Oro, Xp, Regen }   (fracciones: 0.05 = 5%)
      - Solo cuentan las piezas que tu personaje PUEDE usar (nivel, rol, facción, arma de su clase).
      - Bono de set: piezas equipadas del set de TU rol (2-3: +5% / 4: +15% a todo el equipo).
      - Defensa y Crítico tienen tope (GearCatalog.DEFENSE_CAP / CRIT_CAP).
    Aplicación:
      Outgoing(player, daño, pvp)  daño x (1+Ataque) y crítico x1.5    -> DamageService (jugador -> mob / PvP)
      Incoming(player, daño, pvp)  daño x (1-Defensa)                  -> DamageService (mob / jugador -> jugador)
      HealMult(player)             1+Curacion                          -> DamageService.Heal
      XpMult(player) · GoldMult(player) · Luck(player)                 -> RewardService / LootService (mascotas)
      Vida: StatService la suma a la vida máxima (escucha GearService.Changed)
      Regen (Fénix): cura % de la vida máxima por segundo si pasaron 6 s sin recibir golpes
    En PvP el equipo cuenta GearCatalog.PVP_GEAR_FACTOR (50%).
    CanEquip(player, itemId) -> ok, motivo   (lo usa InventoryService antes de equipar)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)

export type Stats = {
	Ataque: number, Defensa: number, Vida: number, Critico: number, Curacion: number,
	Suerte: number, Oro: number, Xp: number, Regen: number,
}

local OUT_OF_COMBAT = 6 -- s sin recibir golpes para que el Fénix regenere

local GearService = {}

local changedEvent = Instance.new("BindableEvent")
GearService.Changed = changedEvent.Event :: RBXScriptSignal -- (player) cuando cambian sus estadísticas

local cache: { [Player]: Stats } = {}
local pending: { [Player]: boolean } = {}
local rng = Random.new()

local function zero(): Stats
	return { Ataque = 0, Defensa = 0, Vida = 0, Critico = 0, Curacion = 0, Suerte = 0, Oro = 0, Xp = 0, Regen = 0 }
end

local function levelOf(player: Player): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function compute(player: Player): Stats
	local class = PlayerClass.Get(player)
	local faction, role, level = class.Faction, class.Role, levelOf(player)
	local gear: { [string]: number } = {}
	local pet: { [string]: number } = {}
	local setPieces = 0

	for _, slot in ipairs(ItemCatalog.EquipSlots) do
		local id = player:GetAttribute("Equip_" .. slot)
		local item: any = if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
		if item then
			if item.Gear then
				if GearCatalog.CanUse(item, faction, role, level) then
					local plus = player:GetAttribute("EquipPlus_" .. slot)
					local mult = GearCatalog.EnhanceMult(if typeof(plus) == "number" then plus else 0)
					for stat, v in pairs(item.Gear) do
						gear[stat] = (gear[stat] or 0) + v * mult
					end
					if item.Set == role then
						setPieces += 1
					end
				end
			elseif item.Pet then
				for effect, v in pairs(item.Pet.Effects) do
					pet[effect] = (pet[effect] or 0) + v
				end
			end
		end
	end

	local setMult = 1 + (GearCatalog.SetBonus[math.min(setPieces, 4)] or 0)
	local s = zero()
	local out = s :: any
	for stat, v in pairs(gear) do
		out[stat] = v * setMult
	end
	for effect, v in pairs(pet) do
		out[effect] = (out[effect] or 0) + v
	end
	s.Defensa = math.min(s.Defensa, GearCatalog.DEFENSE_CAP)
	s.Critico = math.min(s.Critico, GearCatalog.CRIT_CAP)
	return s
end

local function refresh(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent then
			cache[player] = compute(player)
			changedEvent:Fire(player)
		end
	end)
end

function GearService.Get(player: Player): Stats
	local s = cache[player]
	if not s then
		s = compute(player)
		cache[player] = s
	end
	return s
end

function GearService.Outgoing(player: Player?, damage: number, pvp: boolean): number
	if not player then
		return damage
	end
	local s = GearService.Get(player)
	local f = if pvp then GearCatalog.PVP_GEAR_FACTOR else 1
	local out = damage * (1 + s.Ataque * f)
	local crit = s.Critico * f
	if crit > 0 and rng:NextNumber() < crit then
		out *= GearCatalog.CRIT_MULT
	end
	return out
end

function GearService.Incoming(player: Player?, damage: number, pvp: boolean): number
	if not player then
		return damage
	end
	local f = if pvp then GearCatalog.PVP_GEAR_FACTOR else 1
	return damage * (1 - GearService.Get(player).Defensa * f)
end

function GearService.HealMult(player: Player?): number
	return if player then 1 + GearService.Get(player).Curacion else 1
end
function GearService.XpMult(player: Player): number
	return 1 + GearService.Get(player).Xp
end
function GearService.GoldMult(player: Player): number
	return 1 + GearService.Get(player).Oro
end
function GearService.Luck(player: Player): number
	return GearService.Get(player).Suerte
end

function GearService.CanEquip(player: Player, itemId: string): (boolean, string?)
	local item: any = (ItemCatalog.Items :: any)[itemId]
	if not item then
		return false, "Objeto desconocido"
	end
	local class = PlayerClass.Get(player)
	return GearCatalog.CanUse(item, class.Faction, class.Role, levelOf(player))
end

local function watch(player: Player)
	player.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 6) == "Equip_" or string.sub(name, 1, 10) == "EquipPlus_" or name == "Faction" or name == "Role" or name == "Level" then
			refresh(player)
		end
	end)
	refresh(player)
end

Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	cache[pl] = nil
	pending[pl] = nil
end)

-- Fénix: regeneración fuera de combate (DamageService marca LastHitAt en la víctima con cada golpe)
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local s = cache[player]
			if s and s.Regen > 0 then
				local char = player.Character
				local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
				if char and hum and hum.Health > 0 and hum.Health < hum.MaxHealth then
					local lastHit = char:GetAttribute("LastHitAt")
					if typeof(lastHit) ~= "number" or os.clock() - lastHit > OUT_OF_COMBAT then
						hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * s.Regen)
					end
				end
			end
		end
	end
end)

return GearService
