--!strict
--[[
    StatService (ModuleScript) -> ServerScriptService.Services.StatService
    Convierte NIVEL en ESTADÍSTICAS del personaje:
      - Vida máxima = Vitalidad de la clase × 10 (ClassStats) × GameBalance.PlayerHpMult(nivel)
      - Copia el nivel al personaje (atributo Level) y lo etiqueta "Targetable"
    También responde "¿de qué nivel es esto?" para jugadores, personajes y mobs: StatService.GetLevel(instancia)
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local ClassStats = require(ReplicatedStorage.Modules.ClassStats)
local LevelService = require(ServerScriptService.Services.LevelService)
local GearService = require(ServerScriptService.Services.GearService)

local StatService = {}

function StatService.GetLevel(inst: Instance): number
	local pl = if inst:IsA("Player") then inst else Players:GetPlayerFromCharacter(inst)
	if pl then
		return LevelService.GetLevel(pl)
	end
	local lv = inst:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function applyToCharacter(player: Player, char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	local level = LevelService.GetLevel(player)
	local class = PlayerClass.Get(player)
	local maxHp = math.floor(ClassStats.BaseHp(class.Role) * GB.PlayerHpMult(level) * (1 + GearService.Get(player).Vida)) -- Vida del equipo y la mascota
	local ratio = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
	hum.MaxHealth = maxHp
	hum.Health = math.max(1, maxHp * math.clamp(ratio, 0, 1))
	char:SetAttribute("Level", level)
	CollectionService:AddTag(char, "Targetable")
end

function StatService.Refresh(player: Player)
	local char = player.Character
	if char then
		applyToCharacter(player, char)
	end
end

local function onCharacter(player: Player, char: Model)
	applyToCharacter(player, char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth -- al reaparecer, vida completa
	end
end

Players.PlayerAdded:Connect(function(pl)
	pl.CharacterAdded:Connect(function(c)
		onCharacter(pl, c)
	end)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	pl.CharacterAdded:Connect(function(c)
		onCharacter(pl, c)
	end)
	if pl.Character then
		task.spawn(onCharacter, pl, pl.Character)
	end
end

-- al subir de nivel (o cargar datos) se recalcula la vida
LevelService.LevelChanged:Connect(function(player: Player)
	StatService.Refresh(player)
end)

-- al cambiar el equipo o la mascota se recalcula la vida máxima
GearService.Changed:Connect(function(player: Player)
	StatService.Refresh(player)
end)

return StatService
