--!strict
--[[
    BaseSpeedService (ModuleScript) -> ServerScriptService.Services.BaseSpeedService
    Velocidad BASE de caminata de todos los jugadores (el SHIFT de velocidad ya no existe para el público, ver SpeedTestTool).
    Se aplica a cada personaje al aparecer. Las monturas y los efectos (ralentizar, aturdir) parten de este valor.
    Para cambiarla: BASE_SPEED (Roblox usa 16 por defecto).
]]
local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")

local BASE_SPEED = 20

StarterPlayer.CharacterWalkSpeed = BASE_SPEED

local function apply(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") and hum.WalkSpeed > 0 and hum.WalkSpeed < BASE_SPEED then
		hum.WalkSpeed = BASE_SPEED
	end
end

local function hook(pl: Player)
	pl.CharacterAdded:Connect(apply)
	if pl.Character then
		task.spawn(apply, pl.Character)
	end
end

Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do
	hook(pl)
end

return {}
