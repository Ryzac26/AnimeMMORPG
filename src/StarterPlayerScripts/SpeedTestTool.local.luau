--!strict
--[[
    SpeedTestTool (LocalScript) -> StarterPlayer > StarterPlayerScripts > SpeedTestTool
    SHIFT IZQUIERDO = súper velocidad, SOLO para el Soberano (dueño del juego). El resto de jugadores usa la velocidad base
    (BaseSpeedService) y este script no hace nada para ellos.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local okList, AdminList: any = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Modules", 10):WaitForChild("AdminList", 10))
end)
if not okList then
	return
end
local entry = AdminList.Get(player)
if not entry or entry.Kind ~= "Owner" then
	return
end

local WALK_SPEED_FAST = 200
local savedSpeed: number? = nil

local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.KeyCode ~= Enum.KeyCode.LeftShift then
		return
	end
	local h = humanoid()
	if h and savedSpeed == nil then
		savedSpeed = h.WalkSpeed -- vuelve a ESTA velocidad al soltar (no a un número fijo)
		h.WalkSpeed = WALK_SPEED_FAST
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode ~= Enum.KeyCode.LeftShift then
		return
	end
	local h = humanoid()
	if h and savedSpeed ~= nil then
		h.WalkSpeed = savedSpeed
	end
	savedSpeed = nil
end)

player.CharacterAdded:Connect(function()
	savedSpeed = nil
end)
