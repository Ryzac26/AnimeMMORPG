--!strict
--[[
    TargetFacingClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > TargetFacingClient
    Gira al personaje hacia su objetivo marcado:
      - Con el auto-ataque activo y el personaje quieto, se mantiene mirando al objetivo.
      - Al usar un poder (1-4) mira al objetivo aunque se esté moviendo (el servidor también lo gira al lanzar).
    El servidor decide el objetivo (ObjectValue "CombatTarget" dentro del Player); esto es solo la parte visual suave.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local FACE_RANGE = 60
local TURN_SPEED = 14 -- más alto = gira más rápido
local CAST_WINDOW = 0.6

local faceUntil = 0
local KEYS: { [Enum.KeyCode]: boolean } = {
	[Enum.KeyCode.One] = true, [Enum.KeyCode.Two] = true, [Enum.KeyCode.Three] = true, [Enum.KeyCode.Four] = true,
	[Enum.KeyCode.KeypadOne] = true, [Enum.KeyCode.KeypadTwo] = true, [Enum.KeyCode.KeypadThree] = true, [Enum.KeyCode.KeypadFour] = true,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and KEYS[input.KeyCode] then
		faceUntil = os.clock() + CAST_WINDOW
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local tv = player:FindFirstChild("CombatTarget") :: ObjectValue?
	local target = if tv then tv.Value else nil
	if not target or not target.Parent then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local tRoot = target:FindFirstChild("HumanoidRootPart")
	if not (hum and hum.Health > 0 and root and root:IsA("BasePart") and tRoot and tRoot:IsA("BasePart")) then
		return
	end
	local casting = os.clock() < faceUntil
	local attacking = player:GetAttribute("AutoAttack") == true and hum.MoveDirection.Magnitude < 0.1
	if not (casting or attacking) then
		return
	end
	local flat = Vector3.new(tRoot.Position.X - root.Position.X, 0, tRoot.Position.Z - root.Position.Z)
	if flat.Magnitude < 0.5 or flat.Magnitude > FACE_RANGE then
		return
	end
	local goal = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	root.CFrame = root.CFrame:Lerp(goal, math.clamp(dt * TURN_SPEED, 0, 1))
end)
