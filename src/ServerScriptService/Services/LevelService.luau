--!strict
--[[
    LevelService (ModuleScript) -> ServerScriptService.Services.LevelService
    ÚNICO dueño del NIVEL y la XP de los jugadores. Nadie más escribe los atributos Level/XP.
      - AddXp(player, cantidad): suma XP y sube de nivel (varios niveles de golpe si hace falta)
      - LosePercent(player, pct): resta % de la XP del nivel actual (nunca baja de nivel)
      - SetLevel(player, nivel): solo para pruebas (DevCommands)
      - Carga/guarda a través de PlayerData (sección "Progress"); aquí ya no hay DataStore propio
    Eventos (BindableEvent): LevelChanged(player, newLevel, oldLevel)
    Fórmula de XP necesaria: GameBalance.XpToNext(nivel)
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)

local XPChanged = Net.Get("XPChanged")
local LevelUpRemote = Net.Get("LevelUp")

local LevelService = {}

local changedEvent = Instance.new("BindableEvent")
LevelService.LevelChanged = changedEvent.Event :: RBXScriptSignal

type Progress = { Level: number, XP: number }
local data: { [Player]: Progress } = {}

local function push(player: Player)
	local p = data[player]
	if not p then
		return
	end
	player:SetAttribute("Level", p.Level)
	player:SetAttribute("XP", p.XP)
	XPChanged:FireClient(player, p.Level, p.XP, GB.XpToNext(p.Level))
end

function LevelService.GetLevel(player: Player): number
	local p = data[player]
	return if p then p.Level else 1
end

function LevelService.GetXp(player: Player): number
	local p = data[player]
	return if p then p.XP else 0
end

function LevelService.AddXp(player: Player, amount: number)
	local p = data[player]
	if not p or amount <= 0 or p.Level >= GB.MAX_LEVEL then
		return
	end
	local old = p.Level
	p.XP += math.floor(amount)
	while p.Level < GB.MAX_LEVEL and p.XP >= GB.XpToNext(p.Level) do
		p.XP -= GB.XpToNext(p.Level)
		p.Level += 1
	end
	if p.Level >= GB.MAX_LEVEL then
		p.XP = 0
	end
	push(player)
	if p.Level ~= old then
		LevelUpRemote:FireClient(player, p.Level)
		changedEvent:Fire(player, p.Level, old)
	end
end

-- Penalización por muerte: % de la barra del nivel actual. No baja de nivel.
function LevelService.LosePercent(player: Player, pct: number)
	local p = data[player]
	if not p or p.Level < GB.DEATH_PENALTY_MIN_LEVEL or p.Level >= GB.MAX_LEVEL then
		return
	end
	local loss = math.floor(GB.XpToNext(p.Level) * pct)
	p.XP = math.max(0, p.XP - loss)
	push(player)
end

function LevelService.SetLevel(player: Player, level: number)
	local p = data[player]
	if not p then
		return
	end
	local old = p.Level
	p.Level = math.clamp(math.floor(level), 1, GB.MAX_LEVEL)
	p.XP = 0
	push(player)
	if p.Level ~= old then
		changedEvent:Fire(player, p.Level, old)
	end
end

local function load(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return -- la carga falló (el jugador es expulsado) o ya salió
	end
	local progress: Progress = { Level = 1, XP = 0 }
	local section = saved.Progress
	if typeof(section) == "table" then
		progress.Level = math.clamp(math.floor(tonumber(section.Level) or 1), 1, GB.MAX_LEVEL)
		progress.XP = math.max(0, math.floor(tonumber(section.XP) or 0))
	end
	data[player] = progress
	push(player)
	changedEvent:Fire(player, progress.Level, progress.Level)
end

-- Qué guarda PlayerData de este servicio (nil = el jugador aún no cargó: no se toca su sección)
PlayerData.RegisterSerializer("Progress", function(player: Player): any?
	local p = data[player]
	if p then
		return { Level = p.Level, XP = p.XP }
	end
	return nil
end)

-- PlayerData avisa DESPUÉS de tomar la foto final de datos: ahora sí se puede limpiar
PlayerData.Releasing:Connect(function(player: Player)
	data[player] = nil
end)

Net.Get("RequestSync").OnServerEvent:Connect(function(pl: Player)
	push(pl) -- el cliente ya está escuchando: reenvía nivel y XP
end)

Players.PlayerAdded:Connect(load)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end

return LevelService
