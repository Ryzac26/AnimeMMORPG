--!strict
--[[
    FactionZoneService (ModuleScript) -> ServerScriptService.Services.FactionZoneService
    TERRITORIO DE CADA NACIÓN: un jugador solo puede estar en su propia ciudad, su franja PvE y su puente. La ARENA es de todos.
    Si entra a territorio de otra nación (por cualquier camino: puente, borde, salto), el servidor lo devuelve a su
    última posición válida y avisa. No depende de grupos de colisión, así que no se puede esquivar.
    El territorio se calcula con la dirección de cada ciudad (posición de su SpawnLocation "Spawn_<Bioma>") respecto al centro.
    Para pruebas: workspace:SetAttribute("AllowCrossFaction", true) desactiva el bloqueo.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ServerScriptService.Services.Net)
local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)

local BIOME_OF: { [string]: string } = { Saiyan = "Imperio_Saiyan", Shinobi = "Alianza_Shinobi", Pirate = "Flota_Pirata", Shinigami = "Corte_Shinigami" }
local ARENA_EDGE = 765 -- medio lado de la arena (750) + margen
local CONE_DOT = 0.6 -- dentro de ~53° del eje de una ciudad = su territorio
local CHECK = 0.2

local axes: { [string]: Vector3 } = {}
local lastSafe: { [Player]: CFrame } = {}
local lastWarn: { [Player]: number } = {}

local FactionZone = {}

local function loadAxes()
	for faction, biome in pairs(BIOME_OF) do
		local sp = Workspace:FindFirstChild("Spawn_" .. biome, true)
		if sp and sp:IsA("BasePart") then
			local v = Vector3.new(sp.Position.X, 0, sp.Position.Z)
			if v.Magnitude > 1 then
				axes[faction] = v.Unit
			end
		end
	end
end

-- ¿De qué nación es el territorio en esa posición? (nil = arena / neutral)
function FactionZone.OwnerAt(pos: Vector3): string?
	if math.abs(pos.X) <= ARENA_EDGE and math.abs(pos.Z) <= ARENA_EDGE then
		return nil
	end
	local p = Vector3.new(pos.X, 0, pos.Z)
	if p.Magnitude < 1 then
		return nil
	end
	local u = p.Unit
	for faction, d in pairs(axes) do
		if u:Dot(d) >= CONE_DOT then
			return faction
		end
	end
	return nil
end

task.spawn(function()
	local t = 0
	while next(axes) == nil and t < 90 do
		loadAxes()
		if next(axes) == nil then
			task.wait(1)
			t += 1
		end
	end
	for f, d in pairs(axes) do
		print(string.format("[FactionZoneService] %s: eje (%.2f, %.2f)", f, d.X, d.Z))
	end
end)

task.spawn(function()
	while true do
		task.wait(CHECK)
		if Workspace:GetAttribute("AllowCrossFaction") == true then
			continue
		end
		for _, pl in ipairs(Players:GetPlayers()) do
			local faction = PlayerClass.Get(pl).Faction -- (si no eligió, PlayerClass usa Saiyan por defecto)
			local char = pl.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and hum and hum.Health > 0 then
				local owner = FactionZone.OwnerAt(root.Position)
				if owner ~= nil and owner ~= faction then
					local back = lastSafe[pl]
					if not back and pl.RespawnLocation then
						back = pl.RespawnLocation.CFrame + Vector3.new(0, 5, 0)
					end
					if back then
						root.AssemblyLinearVelocity = Vector3.zero
						root.CFrame = back
					end
					local now = os.clock()
					if now - (lastWarn[pl] or 0) > 3 then
						lastWarn[pl] = now
						Net.Get("Notify"):FireClient(pl, "Territorio de otra nación: no puedes entrar.")
					end
				elseif hum.FloorMaterial ~= Enum.Material.Air then
					lastSafe[pl] = root.CFrame
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	lastSafe[pl] = nil
	lastWarn[pl] = nil
end)

return FactionZone
