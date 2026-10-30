--!strict
--[[
    SCRIPT: SpeedTestTool.client.luau
    UBICACIÓN: StarterPlayer > StarterPlayerScripts (LocalScript)
    DESCRIPCIÓN: Opciones rápidas de velocidad y vuelo para inspeccionar el mapa.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer

-- Ajusta la velocidad normal y la súper velocidad aquí
local WALK_SPEED_NORMAL = 16
local WALK_SPEED_FAST = 200

local function applySpeed(speed: number)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = speed
		end
	end
end

-- Mantener presionado SHIFT IZQUIERDO para correr súper rápido
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		applySpeed(WALK_SPEED_FAST)
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		applySpeed(WALK_SPEED_NORMAL)
	end
end)

-- Restablecer velocidad si el personaje reaparece
player.CharacterAdded:Connect(function(character)
	character:WaitForChild("Humanoid")
	applySpeed(WALK_SPEED_NORMAL)
end)

print("[SpeedTestTool] Listo: Mantén presionado SHIFT IZQUIERDO para moverte a súper velocidad (200).")