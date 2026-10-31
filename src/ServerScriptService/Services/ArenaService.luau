--!strict
--[[
    ArenaService (ModuleScript) -> ServerScriptService.Services.ArenaService
    Reglas de la ARENA CENTRAL (único lugar con PvP entre naciones):
      - IsInArena(pos): ¿está esa posición dentro de una parte con tag "ZonePvP"? (Coliseo_Central)
      - Vidas: 5 por evento (GameBalance.ARENA_LIVES). Se recargan al pasar Workspace.EventState a "Open".
      - Con 0 vidas el jugador va a la GRADA de su facción (solo ahí puede estar hasta el próximo evento);
        con el evento cerrado, todos salen de la arena y de las gradas hacia su ciudad.
      - Gradas: partes con tag "ZoneGrada" (atributo Faction) y puntos de aparición con tag "GradaSpawn" (los crea ArenaStyler).
      - PvpAllowed(a, b): ambos dentro, evento abierto, naciones distintas y con vidas.
    Dueño del atributo de jugador "ArenaLives" y del remote ArenaLives (para el HUD).
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Net = require(ServerScriptService.Services.Net)

local LivesRemote = Net.Get("ArenaLives")

-- true: cualquier muerte dentro de la arena (también por enemigos del evento) gasta una vida.
-- false: solo las muertes por otro jugador (PvP) gastan vida.
local COUNT_ENEMY_DEATHS = true
local ARENA_HEIGHT = 120 -- altura sobre el piso que cuenta como "dentro"

local ArenaService = {}
ArenaService.CountEnemyDeaths = COUNT_ENEMY_DEATHS

function ArenaService.IsInArena(pos: Vector3): boolean
	for _, part in ipairs(CollectionService:GetTagged("ZonePvP")) do
		if part:IsA("BasePart") then
			local l = part.CFrame:PointToObjectSpace(pos)
			local s = part.Size
			if math.abs(l.X) <= s.X / 2 and math.abs(l.Z) <= s.Z / 2 and l.Y >= -s.Y / 2 - 5 and l.Y <= s.Y / 2 + ARENA_HEIGHT then
				return true
			end
		end
	end
	return false
end

-- ¿está en una grada? devuelve (true, facción de esa grada)
function ArenaService.GradaAt(pos: Vector3): (boolean, string?)
	for _, part in ipairs(CollectionService:GetTagged("ZoneGrada")) do
		if part:IsA("BasePart") then
			local l = part.CFrame:PointToObjectSpace(pos)
			local s = part.Size
			if math.abs(l.X) <= s.X / 2 and math.abs(l.Z) <= s.Z / 2 and l.Y >= -s.Y / 2 - 5 and l.Y <= s.Y / 2 + 60 then
				local f = part:GetAttribute("Faction")
				return true, if typeof(f) == "string" then f else nil
			end
		end
	end
	return false, nil
end

function ArenaService.IsOpen(): boolean
	return Workspace:GetAttribute("EventState") == "Open"
end

function ArenaService.GetLives(player: Player): number
	local v = player:GetAttribute("ArenaLives")
	return if typeof(v) == "number" then v else GB.ARENA_LIVES
end

local function setLives(player: Player, n: number)
	player:SetAttribute("ArenaLives", n)
	LivesRemote:FireClient(player, n)
end

function ArenaService.CanEnter(player: Player): boolean
	return ArenaService.IsOpen() and ArenaService.GetLives(player) > 0
end

function ArenaService.LoseLife(player: Player)
	setLives(player, math.max(0, ArenaService.GetLives(player) - 1))
end

function ArenaService.RefillAll()
	for _, pl in ipairs(Players:GetPlayers()) do
		setLives(pl, GB.ARENA_LIVES)
	end
end

function ArenaService.PosOf(player: Player): Vector3?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

function ArenaService.PvpAllowed(a: Player, b: Player): boolean
	if a == b or not ArenaService.IsOpen() then
		return false
	end
	local fa, fb = a:GetAttribute("Faction"), b:GetAttribute("Faction")
	if fa ~= nil and fa == fb then
		return false
	end
	local pa, pb = ArenaService.PosOf(a), ArenaService.PosOf(b)
	if not pa or not pb or not ArenaService.IsInArena(pa) or not ArenaService.IsInArena(pb) then
		return false
	end
	return ArenaService.GetLives(a) > 0 and ArenaService.GetLives(b) > 0
end

local function teleport(player: Player, pos: Vector3)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(pos)
	end
end

function ArenaService.SendToCity(player: Player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local spawn = player.RespawnLocation
	if root and root:IsA("BasePart") and spawn then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = spawn.CFrame + Vector3.new(0, 6, 0)
	end
end

-- Lleva al jugador a la grada de SU facción (si el evento está abierto); si no, a su ciudad.
function ArenaService.SendToGrada(player: Player): boolean
	local f = player:GetAttribute("Faction")
	if ArenaService.IsOpen() and typeof(f) == "string" then
		local options: { BasePart } = {}
		for _, p in ipairs(CollectionService:GetTagged("GradaSpawn")) do
			if p:IsA("BasePart") and p:GetAttribute("Faction") == f then
				table.insert(options, p)
			end
		end
		if #options > 0 then
			teleport(player, options[math.random(1, #options)].Position)
			return true
		end
	end
	ArenaService.SendToCity(player)
	return false
end

local function expel(player: Player)
	if ArenaService.IsOpen() and ArenaService.GetLives(player) <= 0 then
		if ArenaService.SendToGrada(player) then
			Net.Get("Notify"):FireClient(player, "Sin vidas de arena: te llevamos a tu grada hasta el próximo evento.")
			return
		end
	end
	ArenaService.SendToCity(player)
	Net.Get("Notify"):FireClient(player, "La arena está cerrada para ti (evento terminado o sin vidas).")
end

Net.Get("RequestSync").OnServerEvent:Connect(function(pl: Player)
	LivesRemote:FireClient(pl, ArenaService.GetLives(pl))
end)

Players.PlayerAdded:Connect(function(pl)
	setLives(pl, GB.ARENA_LIVES)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	setLives(pl, GB.ARENA_LIVES)
end

Workspace:GetAttributeChangedSignal("EventState"):Connect(function()
	if ArenaService.IsOpen() then
		ArenaService.RefillAll()
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		for _, pl in ipairs(Players:GetPlayers()) do
			local pos = ArenaService.PosOf(pl)
			if pos and ArenaService.IsInArena(pos) and not ArenaService.CanEnter(pl) then
				expel(pl)
			elseif pos then
				local inG, gf = ArenaService.GradaAt(pos)
				if inG and (not ArenaService.IsOpen() or (gf ~= nil and gf ~= pl:GetAttribute("Faction"))) then
					ArenaService.SendToCity(pl)
					Net.Get("Notify"):FireClient(pl, "La grada está cerrada (evento terminado).")
				end
			end
		end
	end
end)

return ArenaService
