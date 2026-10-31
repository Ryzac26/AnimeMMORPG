--!strict
--[[
    StreamService (ModuleScript) -> ServerScriptService > Services > StreamService
    Si el mapa usa StreamingEnabled, el cliente solo recibe lo que tiene cerca. Cuando un jugador aparece o es
    teletransportado a su ciudad (muy lejos de donde estaba), en Roblox web el mapa tarda en llegar y se ve vacío.
    Este servicio le pide al cliente que cargue el lugar al que va (Player:RequestStreamAroundAsync) al aparecer
    y cada vez que se mueve más de 250 studs de golpe. Si StreamingEnabled está apagado no hace nada.
]]
local Players = game:GetService("Players")

local JUMP = 250 -- distancia que cuenta como teletransporte
local TIMEOUT = 6

local StreamService = {}

local function request(player: Player, pos: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(pos, TIMEOUT)
	end)
end

StreamService.Request = request

local function watch(player: Player)
	task.spawn(function()
		local last: Vector3? = nil
		while player.Parent == Players do
			local ch = player.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local pos = root.Position
				if last == nil or (pos - last).Magnitude > JUMP then
					last = pos
					request(player, pos)
				end
			end
			task.wait(0.75)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end

return StreamService
