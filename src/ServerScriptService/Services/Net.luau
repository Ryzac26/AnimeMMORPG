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

-- Observador de tráfico (lo usa AntiExploitService para detectar spam): se le avisa de CADA evento que un cliente manda a CUALQUIER remote.
local observer: ((Player, string) -> ())? = nil
local hooked: { [Instance]: boolean } = {}

local function hookRemote(r: Instance)
	if hooked[r] or not r:IsA("RemoteEvent") then
		return
	end
	hooked[r] = true
	local remote = r :: RemoteEvent
	remote.OnServerEvent:Connect(function(pl: Player)
		local o = observer
		if o then
			o(pl, remote.Name)
		end
	end)
end

function Net.SetObserver(fn: (Player, string) -> ())
	observer = fn
end

function Net.Get(name: string): RemoteEvent
	local f = folder()
	local r: Instance
	local existing = f:FindFirstChild(name)
	if existing then
		r = existing
	else
		local created = Instance.new("RemoteEvent")
		created.Name = name
		created.Parent = f
		r = created
	end
	hookRemote(r)
	return r :: RemoteEvent
end

-- Remotes que alguien cree a mano en la carpeta también quedan vigilados
folder().ChildAdded:Connect(hookRemote)
for _, child in ipairs(folder():GetChildren()) do
	hookRemote(child)
end

-- Se crean TODOS al cargar: el cliente puede hacer WaitForChild sin esperar a que el servidor los use por primera vez
for _, n in ipairs({ "ClientPulse", "DealDamageEvent", "XPChanged", "LevelUp", "Notify", "ArenaLives", "Fragility", "Floating", "InventoryUpdate", "InventoryAction", "DevCommand", "RequestSync", "AutoAttack", "UseAbility", "AbilityCooldown", "Party", "Boosts", "AutoFarm", "AutoFarmMove", "ChooseClass", "WorldLoaded", "SmithOpen", "SmithAction", "SmithResult", "ShopOpen", "ShopAction", "ShopResult", "ClassChangeOpen", "TiendaState", "TiendaAction", "TiendaResult", "AlquimiaOpen", "AlquimiaAction", "AlquimiaResult", "DeathRespawn", "MasteryState", "MasteryAction", "MasteryResult", "GuildState", "GuildAction", "GuildResult", "HouseState", "HouseAction", "HouseOpen", "MissionState", "MissionAction", "MissionOpen", "HallOpen", "TitleState", "TitleAction", "VipShopState", "VipShopAction", "MilestoneState", "MilestoneAction", "TalentState", "TalentAction" }) do
	Net.Get(n)
end

-- Marca para el cliente: "ya existen todos los remotes"
ReplicatedStorage:SetAttribute("RemotesReady", true)

return Net
