--!strict
--[[
    GearService (ModuleScript) -> ServerScriptService.Services.GearService
    Convierte el EQUIPO y la MASCOTA en estadísticas reales. Lee los atributos Equip_<ranura> que pone InventoryService
    (y EquipPlus_<ranura> = mejora +0..+9, para cuando exista). Recalcula solo cuando algo cambia.

    Get(player) -> { Ataque, Defensa, Vida, Critico, Curacion, Suerte, Oro, Xp, Regen }   (fracciones: 0.05 = 5%)
      - Solo cuentan las piezas que tu personaje PUEDE usar (nivel, rol, facción, arma de su clase).
      - Bono de set: piezas equipadas del set de TU rol (2-3: +5% / 4: +15% a todo el equipo + efecto propio del rol: GearCatalog.SetFull).
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
local PetCatalog = require(ReplicatedStorage.Modules.PetCatalog)
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)

export type Stats = {
	Ataque: number, Defensa: number, Vida: number, Critico: number, Curacion: number,
	Suerte: number, Oro: number, Xp: number, Regen: number, CritDmg: number, Energia: number,
}

local OUT_OF_COMBAT = 6 -- s sin recibir golpes para que el Fénix regenere

local GearService = {}

local changedEvent = Instance.new("BindableEvent")
GearService.Changed = changedEvent.Event :: RBXScriptSignal -- (player) cuando cambian sus estadísticas

local cache: { [Player]: Stats } = {}
local setEffects: { [Player]: { [string]: any }? } = {} -- efecto especial del set completo (alcance, radio, robo de vida, reflejo)
local pending: { [Player]: boolean } = {}
local temp: { [Player]: { [string]: { [string]: number } } } = {} -- bonos extra por FUENTE ("Elixir", "Mastery"...): se suman a las estadísticas
local rng = Random.new()

local function zero(): Stats
	return { Ataque = 0, Defensa = 0, Vida = 0, Critico = 0, Curacion = 0, Suerte = 0, Oro = 0, Xp = 0, Regen = 0, CritDmg = 0, Energia = 0 }
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
	local themeItems: { any } = {}

	local petFamilies: { [string]: boolean } = {}
	for _, slot in ipairs(ItemCatalog.EquipSlots) do
		local id = player:GetAttribute("Equip_" .. slot)
		local item: any = if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
		-- ranura de pase (Mascota 2): sin el pase no cuenta
		local needPass = ItemCatalog.SlotPass[slot]
		if item and needPass and player:GetAttribute(needPass) ~= true then
			item = nil
		end
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
					if item.Theme then
						table.insert(themeItems, item)
					end
				end
			elseif item.Pet then
				-- la mascota de facción solo vale para su facción; el nivel (Plus) multiplica los efectos
				local fOk = typeof(item.Faction) ~= "string" or item.Faction == faction
				if fOk and petFamilies[item.Pet.Family] then
					fOk = false -- dos mascotas de la misma familia no se suman
				end
				if fOk then
					petFamilies[item.Pet.Family] = true
					local plus = player:GetAttribute("EquipPlus_" .. slot)
					local mult = PetCatalog.LevelMult(if typeof(plus) == "number" then plus else 0)
					for effect, v in pairs(item.Pet.Effects) do
						pet[effect] = (pet[effect] or 0) + v * mult
					end
				end
			end
		end
	end

	local themeSum = GearCatalog.ThemeSummary(themeItems)
	local setMult = 1 + (GearCatalog.SetBonus[math.min(setPieces, 4)] or 0) + themeSum.Mult
	local s = zero()
	local out = s :: any
	for stat, v in pairs(gear) do
		out[stat] = v * setMult
	end
	for effect, v in pairs(pet) do
		out[effect] = (out[effect] or 0) + v
	end
	for stat, v in pairs(themeSum.Extra) do
		out[stat] = (out[stat] or 0) + v
	end
	local sources = temp[player]
	if sources then
		for _, extra in pairs(sources) do
			for stat, v in pairs(extra) do
				out[stat] = (out[stat] or 0) + v
			end
		end
	end
	-- bono de set COMPLETO (4/4): efecto propio del rol
	local full = if setPieces >= 4 then GearCatalog.SetFull[role] else nil
	if full then
		s.Critico += full.Critico or 0
		s.Curacion += full.Curacion or 0
		s.CritDmg += full.CritDmg or 0
	end
	setEffects[player] = full
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
			GearService.ApplySetAttributes(player)
			changedEvent:Fire(player)
		end
	end)
end

-- Pone en el personaje los atributos del bono de set completo (los leen CombatService, AbilityService, AutoAttack, AutoFarm y DamageService).
-- Son atributos PROPIOS (SetRange...), así no chocan con los de los poderes temporales (RangeMult, Lifesteal...).
function GearService.ApplySetAttributes(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local e = setEffects[player]
	char:SetAttribute("SetRange", if e then e.Range else nil)
	char:SetAttribute("SetRadius", if e then e.Radius else nil)
	char:SetAttribute("SetLifesteal", if e then e.Lifesteal else nil)
	char:SetAttribute("SetReflect", if e then e.Reflect else nil)
end

-- Bonos temporales (elixires). stats = { Oro = 0.2, ... } o nil para quitarlos. Recalcula y avisa (StatService ajusta la vida máxima).
function GearService.SetTemp(player: Player, stats: { [string]: number }?, source: string?)
	local t = temp[player]
	if not t then
		t = {}
		temp[player] = t
	end
	(t :: any)[source or "Elixir"] = stats
	refresh(player)
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
		out *= GearCatalog.CRIT_MULT + s.CritDmg * f
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
		if string.sub(name, 1, 6) == "Equip_" or string.sub(name, 1, 10) == "EquipPlus_" or name == "Faction" or name == "Role" or name == "Level" or name == "Pass_PetSlot" then
			refresh(player)
		end
	end)
	refresh(player)
end

Players.PlayerAdded:Connect(watch)
Players.PlayerAdded:Connect(function(pl)
	pl.CharacterAdded:Connect(function()
		task.defer(function()
			GearService.ApplySetAttributes(pl)
		end)
	end)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	temp[pl] = nil
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
