--!strict
--[[
    Net (ModuleScript) -> ServerScriptService.Services.Net
    Crea/obtiene RemoteEvents en ReplicatedStorage.Remotes. Así ningún servicio depende del orden de arranque.
    Se ejecuta lo primero (GameServerMain lo requiere en su primera línea). Remotes que usa el sistema (cliente solo ESCUCHA, nunca manda daño ni XP):
      XPChanged(level, xp, xpToNext) | LevelUp(level) | Notify(texto) | ArenaLives(vidas) | Fragility(stacks) | Floating(pos, texto, color)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

local function folder(): Folder
	local f = ReplicatedStorage:FindFirstChild("Remotes")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = ReplicatedStorage
	end
	return f :: Folder
end

function Net.Get(name: string): RemoteEvent
	local f = folder()
	local r = f:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = f
	end
	return r :: RemoteEvent
end

-- Se crean TODOS al cargar: el cliente puede hacer WaitForChild sin esperar a que el servidor los use por primera vez
for _, n in ipairs({ "DealDamageEvent", "XPChanged", "LevelUp", "Notify", "ArenaLives", "Fragility", "Floating", "InventoryUpdate", "InventoryAction", "DevCommand", "RequestSync", "AutoAttack", "UseAbility", "AbilityCooldown", "Party", "Boosts", "AutoFarm", "AutoFarmMove", "ChooseClass", "WorldLoaded", "SmithOpen", "SmithAction", "SmithResult", "ShopOpen", "ShopAction", "ShopResult", "ClassChangeOpen", "TiendaState", "TiendaAction", "TiendaResult", "AlquimiaOpen", "AlquimiaAction", "AlquimiaResult", "DeathRespawn", "MasteryState", "MasteryAction", "MasteryResult", "GuildState", "GuildAction", "GuildResult", "HouseState", "HouseAction", "HouseOpen", "MissionState", "MissionAction", "MissionOpen", "HallOpen" }) do
	Net.Get(n)
end

-- Marca para el cliente: "ya existen todos los remotes"
ReplicatedStorage:SetAttribute("RemotesReady", true)

return Net
