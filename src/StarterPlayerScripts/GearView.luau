--!strict
--[[
    GearView (ModuleScript) -> StarterPlayer > StarterPlayerScripts > GearView
    Calcula EN EL CLIENTE lo mismo que GearService en el servidor (solo para mostrar en pantalla; el servidor manda):
      GearView.Compare(itemId)  -> compara un objeto de la mochila contra lo que llevas en esa ranura
      GearView.Breakdown()      -> total de cada estadística y de dónde sale (arma, casco, set, mascota...)
      GearView.Format(stat, v)  -> "+5.0%"
    Lo usan la mochila (B), el perfil (C) y el aviso de "mejor objeto".
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local ItemCatalog = require(Modules:WaitForChild("ItemCatalog", 10))
local GearCatalog = require(Modules:WaitForChild("GearCatalog", 10))
local PlayerClass = require(Modules:WaitForChild("PlayerClass", 10))
local PetCatalog = require(Modules:WaitForChild("PetCatalog", 10))
local Store = require(script.Parent:WaitForChild("InventoryStore", 10))

local player = Players.LocalPlayer
local Items = ItemCatalog.Items :: { [string]: any }

local GearView = {}

GearView.StatOrder = { "Ataque", "Critico", "Defensa", "Vida", "Curacion", "Suerte", "Oro", "Xp", "Regen", "Energia" }
GearView.StatName = {
	Ataque = "Ataque", Critico = "Crítico", Defensa = "Defensa", Vida = "Vida", Curacion = "Curación",
	Suerte = "Suerte de botín", Oro = "Oro", Xp = "Experiencia", Regen = "Regeneración", Energia = "Regen. de energía",
} :: { [string]: string }

function GearView.Format(stat: string, v: number): string
	local text = string.format("%+.1f%%", v * 100)
	if stat == "Regen" then
		text ..= "/s"
	end
	return text
end

local function levelOf(): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

function GearView.Usable(item: any): (boolean, string?)
	local class = PlayerClass.Get(player) :: any
	return GearCatalog.CanUse(item, class.Faction, class.Role, levelOf())
end

local function plusOf(slot: string): number
	return Store.EquipPlus[slot] or 0
end

-- Nombre con el nivel de mejora: "+3 Casco de Acero"
function GearView.DisplayName(item: any, plus: number?): string
	local n = plus or 0
	if item.Pet then
		return if n > 0 then string.format("Nv.%d %s", n + 1, item.Name) else item.Name -- mascota: Plus = nivel - 1
	end
	if n >= 9 then
		return string.format("★ +%d %s", n, item.Name) -- +9: al máximo
	end
	return if n > 0 then string.format("+%d %s", n, item.Name) else item.Name
end

-- Efectos de un objeto como fracciones (0.05 = 5%). nil si no es equipo ni mascota.
function GearView.Effects(item: any, plus: number?): { [string]: number }?
	local out: { [string]: number } = {}
	if item.Gear then
		local mult = GearCatalog.EnhanceMult(plus or 0)
		for stat, v in pairs(item.Gear) do
			out[stat] = v * mult
		end
		return out
	elseif item.Pet then
		local mult = PetCatalog.LevelMult(plus or 0)
		for stat, v in pairs(item.Pet.Effects) do
			out[stat] = v * mult
		end
		return out
	end
	return nil
end

local function sumOf(effects: { [string]: number }): number
	local s = 0
	for _, v in pairs(effects) do
		s += v
	end
	return s
end

---------------------------------------------------------------------
-- COMPARAR un objeto con lo equipado en su ranura
---------------------------------------------------------------------
export type Comparison = {
	Id: string, Plus: number, Item: any, Slot: string, Effects: { [string]: number },
	Usable: boolean, Reason: string?,
	EquippedId: string?, EquippedPlus: number, EquippedItem: any?, EquippedEffects: { [string]: number }?,
	Delta: { [string]: number },
	Verdict: string, -- "Better" | "Worse" | "Same" | "New" | "Different"
	Gain: number, -- cambio de poder (0.08 = +8%); 0 si no se puede medir
}

function GearView.Compare(itemId: string, itemPlus: number?): Comparison?
	local item = Items[itemId]
	if not item or not item.Slot then
		return nil
	end
	local effects = GearView.Effects(item, itemPlus or 0)
	if not effects then
		return nil
	end
	local slot: string = item.Slot
	local usable, reason = GearView.Usable(item)
	local class = PlayerClass.Get(player) :: any

	local eqId: string? = Store.Equip[slot]
	local eqItem: any? = if eqId then Items[eqId] else nil
	local eqEffects: { [string]: number }? = nil
	if eqItem then
		local eqUsable = GearView.Usable(eqItem)
		if eqUsable then
			eqEffects = GearView.Effects(eqItem, plusOf(slot))
		end
	end

	local delta: { [string]: number } = {}
	for stat, v in pairs(effects) do
		delta[stat] = v
	end
	if eqEffects then
		for stat, v in pairs(eqEffects) do
			delta[stat] = (delta[stat] or 0) - v
		end
	end

	local verdict, gain = "New", 0
	if item.Gear then
		local newScore = GearCatalog.PowerGain(class.Role, effects)
		if not eqEffects then
			gain = newScore - 1
		elseif eqItem and eqItem.Gear then
			gain = newScore / GearCatalog.PowerGain(class.Role, eqEffects) - 1
			verdict = if gain > 0.001 then "Better" elseif gain < -0.001 then "Worse" else "Same"
		else
			verdict = "Different"
		end
	elseif item.Pet then
		if eqEffects and eqItem and eqItem.Pet then
			if eqItem.Pet.Family == item.Pet.Family then
				local a, b = sumOf(effects), sumOf(eqEffects)
				gain = if b > 0 then a / b - 1 else 0
				verdict = if gain > 0.001 then "Better" elseif gain < -0.001 then "Worse" else "Same"
			else
				verdict = "Different"
			end
		elseif eqEffects then
			verdict = "Different"
		end
	end

	return {
		Id = itemId, Plus = itemPlus or 0, Item = item, Slot = slot, Effects = effects,
		Usable = usable, Reason = reason,
		EquippedId = eqId, EquippedPlus = plusOf(slot), EquippedItem = eqItem, EquippedEffects = eqEffects,
		Delta = delta, Verdict = verdict, Gain = gain,
	}
end

---------------------------------------------------------------------
-- DESGLOSE de todas las estadísticas (para la ventana C)
---------------------------------------------------------------------
export type Source = { Label: string, Value: number }
export type Breakdown = {
	Total: { [string]: number },
	Sources: { [string]: { Source } },
	SetPieces: number,
	SetBonus: number,
	Capped: { [string]: boolean },
	Ignored: { string }, -- objetos equipados que no cuentan (no puedes usarlos)
}

function GearView.Breakdown(): Breakdown
	local class = PlayerClass.Get(player) :: any
	local role: string = class.Role
	local gear: { [string]: number } = {}
	local pet: { [string]: number } = {}
	local sources: { [string]: { Source } } = {}
	local ignored: { string } = {}
	local setPieces = 0

	local function addSource(stat: string, label: string, v: number)
		local list = sources[stat]
		if not list then
			list = {}
			sources[stat] = list
		end
		table.insert(list, { Label = label, Value = v })
	end

	for _, slot in ipairs(ItemCatalog.EquipSlots) do
		local id = Store.Equip[slot]
		local item = if id then Items[id] else nil
		if item then
			local effects = GearView.Effects(item, plusOf(slot))
			if effects then
				if GearView.Usable(item) then
					local label = ItemCatalog.SlotDisplay[slot] or slot
					if item.Gear then
						local plus = plusOf(slot)
						if plus > 0 then
							label ..= " +" .. plus
						end
						for stat, v in pairs(effects) do
							gear[stat] = (gear[stat] or 0) + v
							addSource(stat, label, v)
						end
						if item.Set == role then
							setPieces += 1
						end
					else
						for stat, v in pairs(effects) do
							pet[stat] = (pet[stat] or 0) + v
							addSource(stat, "Mascota", v)
						end
					end
				else
					table.insert(ignored, item.Name)
				end
			end
		end
	end

	local setBonus = GearCatalog.SetBonus[math.min(setPieces, 4)] or 0
	local total: { [string]: number } = {}
	for stat, v in pairs(gear) do
		total[stat] = v * (1 + setBonus)
		if setBonus > 0 then
			addSource(stat, string.format("Set %d/4", setPieces), v * setBonus)
		end
	end
	for stat, v in pairs(pet) do
		total[stat] = (total[stat] or 0) + v
	end
	local capped: { [string]: boolean } = {}
	if (total.Defensa or 0) > GearCatalog.DEFENSE_CAP then
		total.Defensa = GearCatalog.DEFENSE_CAP
		capped.Defensa = true
	end
	if (total.Critico or 0) > GearCatalog.CRIT_CAP then
		total.Critico = GearCatalog.CRIT_CAP
		capped.Critico = true
	end

	return { Total = total, Sources = sources, SetPieces = setPieces, SetBonus = setBonus, Capped = capped, Ignored = ignored }
end

return GearView
