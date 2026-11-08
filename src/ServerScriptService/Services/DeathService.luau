--!strict
--[[
    DeathService (ModuleScript) -> ServerScriptService.Services.DeathService
    Qué pasa cuando muere un JUGADOR:
      - Pierde XP del nivel actual: 3% si murió por mob (PvE), 2% si por otro jugador (PvP). Nunca baja de nivel; nada bajo nivel 300 (antes 10).
      - Si murió dentro de la Arena: pierde 1 vida de arena (ArenaService). Al perder la última (5ª), al reaparecer
        va directo a la GRADA de su facción y no puede volver a la arena hasta el próximo evento.
      - Reaparece en el punto de su ciudad (player.RespawnLocation lo fija ProjectBootstrapper).
      - Protección de reaparición: ForceField de 5 s.
      - Al morir NO reaparece solo: la pantalla de muerte (DeathScreenClient) muestra "Ir a la ciudad" / "Ir al campamento" y el jugador
        reaparece cuando elige (remote DeathRespawn). Si no está presente, su personaje queda caído hasta que vuelva y elija.
        El atributo DeathChoice ("City" | "Camp") se lo lee PveZoneService para decidir dónde ponerlo.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local Services = ServerScriptService.Services
local LevelService = require(Services.LevelService)
local ArenaService = require(Services.ArenaService)
local Net = require(Services.Net)

local DeathService = {}

-- Sin reaparición automática: se espera a que el jugador elija (LoadCharacter lo llama el remote DeathRespawn)
Players.RespawnTime = 86400
local RespawnRemote = Net.Get("DeathRespawn")

local function protect(char: Model)
	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = char
	Debris:AddItem(ff, GB.SPAWN_PROTECTION)
end

local function onDied(player: Player, char: Model)
	local root = char:FindFirstChild("HumanoidRootPart")
	local inArena = root ~= nil and root:IsA("BasePart") and ArenaService.IsInArena(root.Position)
	local lastAt = char:GetAttribute("LastHitAt")
	local recent = typeof(lastAt) == "number" and os.clock() - lastAt < 15
	local byPlayer = recent and char:GetAttribute("LastHitByPlayer") == true

	player:SetAttribute("DeathWaiting", true)
	local lost = LevelService.LosePercent(player, if byPlayer then GB.DEATH_PENALTY_PVP else GB.DEATH_PENALTY_PVE)
	-- datos para la pantalla de muerte (DeathScreenClient)
	local killer = char:GetAttribute("LastHitBy")
	player:SetAttribute("DeathKiller", if recent and typeof(killer) == "string" then killer else "")
	player:SetAttribute("DeathXpLoss", lost)

	if inArena and (byPlayer or ArenaService.CountEnemyDeaths) then
		ArenaService.LoseLife(player)
		local left = ArenaService.GetLives(player)
		if left > 0 then
			Net.Get("Notify"):FireClient(player, string.format("Vidas de arena restantes: %d", left))
		else
			player:SetAttribute("PendingGrada", true)
			Net.Get("Notify"):FireClient(player, "Sin vidas de arena: irás a tu grada hasta el próximo evento.")
		end
	end
end

local function onCharacter(player: Player, char: Model)
	protect(char)
	player:SetAttribute("DeathWaiting", nil)
	player:SetAttribute("DeathPlace", nil) -- PveZoneService lo pone al morir si reaparecerá en un campamento
	if player:GetAttribute("PendingGrada") == true then
		player:SetAttribute("PendingGrada", nil)
		task.spawn(function()
			char:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.4) -- deja que termine el spawn normal antes de moverlo
			if player.Character == char then
				ArenaService.SendToGrada(player) -- evento cerrado: lo deja en su ciudad
			end
		end)
	end
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Once(function()
			onDied(player, char)
		end)
	end
end

local function hook(player: Player)
	player.CharacterAdded:Connect(function(c)
		onCharacter(player, c)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

RespawnRemote.OnServerEvent:Connect(function(player: Player, choice: any)
	if choice ~= "City" and choice ~= "Camp" then
		return
	end
	if player:GetAttribute("DeathWaiting") ~= true then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if char and hum and hum.Health > 0 then
		player:SetAttribute("DeathWaiting", nil)
		return
	end
	player:SetAttribute("DeathWaiting", nil)
	player:SetAttribute("DeathChoice", choice)
	player:LoadCharacter()
	task.delay(6, function()
		if player.Parent and player:GetAttribute("DeathWaiting") ~= true then
			player:SetAttribute("DeathChoice", nil)
		end
	end)
end)

-- Red de seguridad: quien cae al vacío (por un hueco del mapa) muere y puede elegir dónde reaparecer, en vez de caer sin fin
task.spawn(function()
	while true do
		task.wait(1)
		for _, pl in ipairs(Players:GetPlayers()) do
			local char = pl.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and hum and hum.Health > 0 and root.Position.Y < -60 then
				hum.Health = 0
			end
		end
	end
end)

Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do
	hook(pl)
end

return DeathService
