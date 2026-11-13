--!strict
--[[
    BaseSpeedService (ModuleScript) -> ServerScriptService.Services.BaseSpeedService
    Velocidad de caminata de los jugadores = la de su ROL (FactionClassesModule: Tanque/Mago/Curador 20, Tirador 21, Guerrero 23, Asesino 26).
    Sin rol elegido todavía: BASE_SPEED. Se aplica al aparecer el personaje y cuando se elige/cambia el rol.
    Las monturas y los efectos (ralentizar, aturdir) parten de este valor. El SHIFT de velocidad solo lo tiene el dueño (SpeedTestTool).
    Para cambiar las velocidades: SPEED_MULT y WalkSpeed por rol en ReplicatedStorage.Modules.FactionClassesModule.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local FactionClasses = require(ReplicatedStorage.Modules.FactionClassesModule)

local BASE_SPEED = 20

StarterPlayer.CharacterWalkSpeed = BASE_SPEED

local function speedOf(pl: Player): number
	local faction, role = pl:GetAttribute("Faction"), pl:GetAttribute("Role")
	if typeof(faction) == "string" and typeof(role) == "string" then
		local ok, cls = pcall(FactionClasses.GetClassByRole, faction, role)
		if ok and cls and typeof((cls :: any).WalkSpeed) == "number" then
			return (cls :: any).WalkSpeed
		end
	end
	return BASE_SPEED
end

local function apply(pl: Player)
	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.WalkSpeed <= 0 then
		return
	end
	local v = speedOf(pl)
	hum.WalkSpeed = v
	if char:GetAttribute("BaseWalkSpeed") ~= nil then
		char:SetAttribute("BaseWalkSpeed", v)
	end
end

local function hook(pl: Player)
	pl.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid", 10)
		apply(pl)
	end)
	pl:GetAttributeChangedSignal("Role"):Connect(function()
		apply(pl)
	end)
	if pl.Character then
		task.spawn(apply, pl)
	end
end

Players.PlayerAdded:Connect(hook)
for _, pl in ipairs(Players:GetPlayers()) do
	hook(pl)
end

return {}
