--!strict
--[[
    EnergyRegenService (ModuleScript) -> ServerScriptService.Services.EnergyRegenService
    Dueño de la ENERGÍA (Ki / Chakra / Haki) de cada jugador. REEMPLAZA al EnergyRegenService anterior.
      - Máximo = BaseEnergy de la clase × GB.KiMult(nivel). Se recalcula si cambia Faction/Role/Nivel (conserva el % actual al subir).
      - Cost(player, base) = costo real de un poder (base × GB.KiCostMult(nivel)); ConsumeEnergy lo aplica solo.
      - Regeneración: 5% del máximo por segundo (REGEN_PCT_PER_SEC).
      - ConsumeEnergy(player, costo) -> true si alcanzó (y la descuenta); false si no.
      - Gain(player, cantidad): suma energía (auto-ataque)
      - GetEnergy(player) -> (actual, máximo) · Refill(player)
      - Publica los atributos de jugador "Energy" y "MaxEnergy" (los lee el HUD).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local GB = require(ReplicatedStorage.Modules.GameBalance)
local ClassStats = require(ReplicatedStorage.Modules.ClassStats)
local GearService = require(script.Parent.GearService) -- mascota de facción: +% de regeneración de energía

local REGEN_PCT_PER_SEC = 0.05

local Energy = {}
local current: { [Player]: number } = {}
local maxOf: { [Player]: number } = {}
local regenOf: { [Player]: number } = {} -- Espíritu del rol

local function publish(player: Player)
	player:SetAttribute("Energy", math.floor(current[player] or 0))
	player:SetAttribute("MaxEnergy", maxOf[player] or 0)
end

local function recalc(player: Player, refill: boolean)
	local lvl = player:GetAttribute("Level")
	local cls = PlayerClass.Get(player)
	local m = math.floor(cls.BaseEnergy * ClassStats.EnergyMax(cls.Role) * GB.KiMult(if typeof(lvl) == "number" then lvl else 1))
	local oldMax = maxOf[player]
	local oldCur = current[player]
	maxOf[player] = m
	regenOf[player] = ClassStats.EnergyRegen(cls.Role)
	if refill or oldMax == nil or oldCur == nil then
		current[player] = m
	else
		current[player] = math.min(m, oldCur + math.max(0, m - oldMax)) -- al subir de nivel, el aumento llega lleno
	end
	publish(player)
end

function Energy.GetEnergy(player: Player): (number, number)
	return current[player] or 0, maxOf[player] or 0
end

function Energy.Refill(player: Player)
	current[player] = maxOf[player] or 0
	publish(player)
end

-- Suma energía (el auto-ataque devuelve un poco en cada golpe)
function Energy.Gain(player: Player, amount: number)
	local m = maxOf[player]
	if m and current[player] then
		current[player] = math.min(m, (current[player] :: number) + amount)
		publish(player)
	end
end

function Energy.Cost(player: Player, base: number): number
	local lvl = player:GetAttribute("Level")
	return math.floor(base * GB.KiCostMult(if typeof(lvl) == "number" then lvl else 1) + 0.5)
end

-- raw=true: descuenta la cantidad tal cual (ya es un valor real, p. ej. el desgaste de Super Saiyan)
function Energy.ConsumeEnergy(player: Player, cost: number, raw: boolean?): boolean
	if not raw then
		cost = Energy.Cost(player, cost)
	end
	local c = current[player]
	if c == nil then
		recalc(player, true)
		c = current[player]
	end
	if (c :: number) < cost then
		return false
	end
	current[player] = (c :: number) - cost
	publish(player)
	return true
end

local function hook(player: Player)
	recalc(player, true)
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		recalc(player, true)
	end)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		recalc(player, true)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		recalc(player, false)
	end)
	player.CharacterAdded:Connect(function()
		Energy.Refill(player)
	end)
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end
Players.PlayerRemoving:Connect(function(p)
	current[p] = nil
	maxOf[p] = nil
	regenOf[p] = nil
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.25 then
		return
	end
	local step = acc
	acc = 0
	for p, c in pairs(current) do
		local m = maxOf[p] or 0
		if c < m then
			local mult = p:GetAttribute("EnergyRegenMult")
			local shrine = p:GetAttribute("ShrineEnergy") -- santuario de Aliento (ArenaStyler)
			current[p] = math.min(m, c + m * REGEN_PCT_PER_SEC * (regenOf[p] or 1) * (if typeof(mult) == "number" then mult else 1) * (if typeof(shrine) == "number" then shrine else 1) * (1 + GearService.Get(p).Energia) * step)
			publish(p)
		end
	end
end)

return Energy
