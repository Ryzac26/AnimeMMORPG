--!strict
--[[
    MountService (ModuleScript) -> ServerScriptService.Services.MountService
    MONTURAS (datos en MountCatalog): huevos, incubadora, eclosión, colección, montar y pasivas.
      - 1 HUEVO AL DÍA: lo da un nido de la franja (NestService) o un mini jefe (LootService). TryDailyEgg lo concede una sola vez por día.
        GrantEgg da un huevo sin límite (para la Tienda más adelante).
      - Incubadora (ciudad, IncubatorService): un huevo a la vez. El tiempo es de reloj (os.time), corre desconectado.
      - Abrir el huevo sortea rareza (con garantías cada 10/30/60 huevos) y especie. Repetida = sube de nivel.
      - Montar: tecla del cliente (remote MountAction "Toggle"). No se puede en la Arena PvP (se baja solo). En PvE se ataca montado.
        Monta = más velocidad (WalkSpeed), personaje sentado sobre el lomo (HipHeight = SitLift; la pose la dibuja MountClient) y sin salto. El dibujo de la montura es del cliente (MountClient).
      - Pasivas mientras vas montado: Vigor (cura), Zancada (energía), Saqueo (oro extra al matar).
    Atributos del jugador: MountEquipped ("Especie|Rareza"), Mounted (bool), EggClaimed (bool, huevo de hoy tomado), EggResetAt (Unix).
    Atributos del personaje: Mounted (bool), MountKey.
    Remotes: MountState (servidor -> cliente, estado completo) · MountAction (cliente -> servidor) · MountHatch (resultado de abrir un huevo) · MountOpen (abre la ventana).
    Se guarda en el perfil, sección "Mounts".
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local MountCatalog = require(Modules.MountCatalog)
local LootTables = require(Modules.LootTables)
local PlayerClass = require(Modules.PlayerClass)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Wallet = require(Services.WalletService)
local ArenaService = require(Services.ArenaService)
local RewardService = require(Services.RewardService)
local EnergyRegenService = require(Services.EnergyRegenService)

local StateRemote = Net.Get("MountState")
local ActionRemote = Net.Get("MountAction")
local HatchRemote = Net.Get("MountHatch")
local OpenRemote = Net.Get("MountOpen")
local NotifyRemote = Net.Get("Notify")
local rng = Random.new()

type Egg = { Tier: number, Source: string }
type Data = {
	Eggs: { Egg },
	Incub: { Tier: number, EndsAt: number }?,
	Owned: { [string]: number },
	Equipped: string?,
	Pity: { Raro: number, Epico: number, Legendario: number },
	Opened: number,
	Day: string,
	Claimed: boolean,
}
local data: { [Player]: Data } = {}
local mounted: { [Player]: { BaseSpeed: number, BaseHip: number, BaseJump: number, BaseJumpH: number } } = {}

local MountService = {}

local function notify(pl: Player, text: string)
	NotifyRemote:FireClient(pl, text)
end

local function today(): string
	local t = os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600
	return os.date("!%Y-%m-%d", t)
end

local function resetAt(): number
	local off = LootTables.Daily.ResetUtcOffsetHours * 3600
	local localNow = os.time() + off
	return localNow - (localNow % 86400) + 86400 - off
end

local function newData(): Data
	return { Eggs = {}, Owned = {}, Pity = { Raro = 0, Epico = 0, Legendario = 0 }, Opened = 0, Day = today(), Claimed = false }
end

-- Si cambió el día, el huevo diario vuelve a estar disponible
local function refreshDay(d: Data)
	local now = today()
	if d.Day ~= now then
		d.Day = now
		d.Claimed = false
	end
end

---------------------------------------------------------------------
-- Estado hacia el cliente
---------------------------------------------------------------------
local function push(pl: Player)
	local d = data[pl]
	if not d then
		return
	end
	refreshDay(d)
	pl:SetAttribute("EggClaimed", d.Claimed)
	pl:SetAttribute("EggResetAt", resetAt())
	pl:SetAttribute("MountEquipped", d.Equipped)
	StateRemote:FireClient(pl, {
		Eggs = d.Eggs,
		Incub = d.Incub,
		Owned = d.Owned,
		Equipped = d.Equipped,
		Pity = d.Pity,
		Opened = d.Opened,
		Claimed = d.Claimed,
		ResetAt = resetAt(),
		Now = os.time(),
	})
end

---------------------------------------------------------------------
-- Huevos
---------------------------------------------------------------------
function MountService.GrantEgg(pl: Player, tier: number, source: string): boolean
	if MountCatalog.Enabled == false then
		return false
	end
	local d = data[pl]
	if not d or #d.Eggs >= MountCatalog.MaxEggsBag then
		if d then
			notify(pl, "Tu bolsa de huevos está llena: abre o incuba alguno")
		end
		return false
	end
	tier = math.clamp(math.floor(tier), 1, #MountCatalog.Eggs)
	table.insert(d.Eggs, { Tier = tier, Source = source })
	notify(pl, string.format("¡Conseguiste un %s! Llévalo a la incubadora de la ciudad", MountCatalog.Eggs[tier].Name))
	push(pl)
	PlayerData.Save(pl)
	return true
end

-- Huevo del día (nido o mini jefe). Devuelve true si se entregó.
function MountService.TryDailyEgg(pl: Player, source: string, tier: number): boolean
	local d = data[pl]
	if not d or MountCatalog.Enabled == false then
		return false
	end
	refreshDay(d)
	if d.Claimed then
		return false
	end
	if not MountService.GrantEgg(pl, tier, source) then
		return false
	end
	d.Claimed = true
	push(pl)
	return true
end

function MountService.DailyAvailable(pl: Player): boolean
	local d = data[pl]
	if not d or MountCatalog.Enabled == false then
		return false
	end
	refreshDay(d)
	return not d.Claimed
end

---------------------------------------------------------------------
-- Incubadora
---------------------------------------------------------------------
local function startIncubation(pl: Player, index: number)
	local d = data[pl]
	if not d then
		return
	end
	if d.Incub then
		notify(pl, "La incubadora ya está ocupada")
		return
	end
	local egg = d.Eggs[index]
	if not egg then
		return
	end
	table.remove(d.Eggs, index)
	d.Incub = { Tier = egg.Tier, EndsAt = os.time() + MountCatalog.IncubationSeconds(egg.Tier) }
	notify(pl, string.format("Incubando %s: estará lista en %d h", MountCatalog.Eggs[egg.Tier].Name, MountCatalog.Eggs[egg.Tier].Hours))
	push(pl)
	PlayerData.Save(pl)
end

local function accelerate(pl: Player)
	local d = data[pl]
	if not d or not d.Incub or os.time() >= d.Incub.EndsAt then
		return
	end
	if MountCatalog.Accelerate.ProductId > 0 then
		notify(pl, "La aceleración con Robux se activará pronto")
	elseif RunService:IsStudio() then
		d.Incub.EndsAt = os.time() -- prueba en Studio: gratis
		push(pl)
		notify(pl, "(Prueba en Studio) Incubación acelerada")
	else
		notify(pl, "La aceleración con Robux estará disponible pronto")
	end
end

---------------------------------------------------------------------
-- Eclosión
---------------------------------------------------------------------
local function pickRarity(tier: number, d: Data): string
	local egg = MountCatalog.Eggs[tier]
	local total = 0
	for _, w in ipairs(egg.Odds) do
		total += w
	end
	local r = rng:NextNumber() * total
	local idx = 1
	for i, w in ipairs(egg.Odds) do
		r -= w
		if r < 0 then
			idx = i
			break
		end
		idx = i
	end
	-- Garantías: los contadores cuentan huevos abiertos sin conseguir esa rareza o mejor
	local P = MountCatalog.Pity
	if d.Pity.Legendario + 1 >= P.Legendario then
		idx = math.max(idx, 4)
	elseif d.Pity.Epico + 1 >= P.Epico then
		idx = math.max(idx, 3)
	elseif d.Pity.Raro + 1 >= P.Raro then
		idx = math.max(idx, 2)
	end
	return MountCatalog.Rarities[idx]
end

local function updatePity(d: Data, rarity: string)
	local idx = MountCatalog.RarityIndex[rarity]
	d.Pity.Raro = if idx >= 2 then 0 else d.Pity.Raro + 1
	d.Pity.Epico = if idx >= 3 then 0 else d.Pity.Epico + 1
	d.Pity.Legendario = if idx >= 4 then 0 else d.Pity.Legendario + 1
end

local function openIncubated(pl: Player)
	local d = data[pl]
	if not d or not d.Incub then
		return
	end
	if os.time() < d.Incub.EndsAt then
		notify(pl, "El huevo todavía no está listo")
		return
	end
	local tier = d.Incub.Tier
	local faction = PlayerClass.Get(pl).Faction
	local pool = MountCatalog.Pool(tier, faction)
	local species = pool[rng:NextInteger(1, #pool)]
	local rarity = pickRarity(tier, d)
	updatePity(d, rarity)
	d.Opened += 1
	d.Incub = nil

	local key = MountCatalog.Key(species.Id, rarity)
	local old = d.Owned[key]
	local isNew = old == nil
	local gold = 0
	if isNew then
		d.Owned[key] = 1
		if not d.Equipped then
			d.Equipped = key
		end
	elseif old < MountCatalog.MaxLevel then
		d.Owned[key] = old + 1
	else
		gold = MountCatalog.DuplicateGold[MountCatalog.RarityIndex[rarity]]
		Wallet.AddGold(pl, gold, "Montura repetida")
	end
	HatchRemote:FireClient(pl, { Key = key, Species = species.Id, Rarity = rarity, New = isNew, Level = d.Owned[key], Gold = gold, Tier = tier })
	push(pl)
	PlayerData.Save(pl)
end

---------------------------------------------------------------------
-- Montar
---------------------------------------------------------------------
local function parts(pl: Player): (Humanoid?, BasePart?)
	local char = pl.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and hum.Health > 0 and root and root:IsA("BasePart") then
		return hum, root
	end
	return nil, nil
end

local function dismount(pl: Player, silent: boolean?)
	local info = mounted[pl]
	if not info then
		return
	end
	mounted[pl] = nil
	pl:SetAttribute("Mounted", false)
	local char = pl.Character
	if char then
		char:SetAttribute("Mounted", false)
		char:SetAttribute("MountKey", nil)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = info.BaseSpeed
			hum.HipHeight = info.BaseHip
			hum.JumpPower = info.BaseJump
			hum.JumpHeight = info.BaseJumpH
		end
		if char:GetAttribute("BaseWalkSpeed") ~= nil then
			char:SetAttribute("BaseWalkSpeed", info.BaseSpeed)
		end
	end
	if not silent then
		push(pl)
	end
end

local function mount(pl: Player)
	local d = data[pl]
	if not d or not d.Equipped or mounted[pl] then
		return
	end
	local species, rarity = MountCatalog.Parse(d.Equipped)
	local level = d.Owned[d.Equipped]
	if not species or not rarity or not level then
		return
	end
	local hum, root = parts(pl)
	if not hum or not root then
		return
	end
	if ArenaService.IsInArena(root.Position) then
		notify(pl, "No puedes montar en la Arena PvP")
		return
	end
	if hum.WalkSpeed <= 0 then
		return -- aturdido o inmovilizado
	end
	local info = { BaseSpeed = hum.WalkSpeed, BaseHip = hum.HipHeight, BaseJump = hum.JumpPower, BaseJumpH = hum.JumpHeight }
	mounted[pl] = info
	local newSpeed = info.BaseSpeed * (1 + MountCatalog.SpeedPct(rarity, level) / 100)
	hum.WalkSpeed = newSpeed
	hum.HipHeight = info.BaseHip + MountCatalog.SitLift
	hum.JumpPower = 0
	hum.JumpHeight = 0
	local char = pl.Character :: Model
	char:SetAttribute("Mounted", true)
	char:SetAttribute("MountKey", d.Equipped)
	if char:GetAttribute("BaseWalkSpeed") ~= nil then
		char:SetAttribute("BaseWalkSpeed", newSpeed)
	end
	pl:SetAttribute("Mounted", true)
	push(pl)
end

local function equip(pl: Player, key: any)
	local d = data[pl]
	if not d then
		return
	end
	local species, rarity = MountCatalog.Parse(key)
	if not species or not rarity or not d.Owned[key :: string] then
		return
	end
	local was = mounted[pl] ~= nil
	if was then
		dismount(pl, true)
	end
	d.Equipped = key :: string
	if was then
		mount(pl)
	end
	push(pl)
	PlayerData.Save(pl)
end

---------------------------------------------------------------------
-- Pasivas: cada 2 s mientras vas montado
---------------------------------------------------------------------
local function tickPassives(pl: Player)
	local d = data[pl]
	if not d or not mounted[pl] then
		return
	end
	local hum, root = parts(pl)
	if not hum or not root then
		return
	end
	if ArenaService.IsInArena(root.Position) then
		dismount(pl)
		notify(pl, "Te bajaste de la montura: la Arena PvP no permite montar")
		return
	end
	local species, rarity = MountCatalog.Parse(d.Equipped)
	local level = d.Owned[d.Equipped or ""]
	if not species or not rarity or not level then
		return
	end
	for _, p in ipairs(MountCatalog.PassivesOf(species, rarity, level)) do
		if p.Kind == "Vigor" then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * p.Value / 100 * 2)
		elseif p.Kind == "Zancada" then
			local _, max = EnergyRegenService.GetEnergy(pl)
			EnergyRegenService.Gain(pl, max * p.Value / 100 * 2)
		end
	end
end

task.spawn(function()
	while true do
		task.wait(2)
		for pl in pairs(mounted) do
			if pl.Parent then
				tickPassives(pl)
			end
		end
	end
end)

-- Saqueo: al matar montado, probabilidad de oro extra (por nivel del mob)
RewardService.MobKilled:Connect(function(_mobId: string, level: number, participants: { Player }, _shares: any)
	for _, pl in ipairs(participants) do
		local d = data[pl]
		if d and mounted[pl] and d.Equipped then
			local species, rarity = MountCatalog.Parse(d.Equipped)
			local lv = d.Owned[d.Equipped]
			if species and rarity and lv then
				for _, p in ipairs(MountCatalog.PassivesOf(species, rarity, lv)) do
					if p.Kind == "Saqueo" and rng:NextNumber() * 100 < p.Value then
						Wallet.AddGold(pl, math.max(1, math.floor(level * 2)), "Saqueo de montura")
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Remotes y datos
---------------------------------------------------------------------
ActionRemote.OnServerEvent:Connect(function(pl: Player, action: any, arg: any)
	if typeof(action) ~= "string" or not data[pl] then
		return
	end
	if MountCatalog.Enabled == false then
		if action == "Toggle" or action == "Open" or action == "Start" or action == "Accelerate" then
			notify(pl, "Monturas: próximamente")
		end
		return
	end
	if action == "Toggle" then
		if mounted[pl] then
			dismount(pl)
		else
			mount(pl)
		end
	elseif action == "Start" and typeof(arg) == "number" then
		startIncubation(pl, math.floor(arg))
	elseif action == "Open" then
		openIncubated(pl)
	elseif action == "Accelerate" then
		accelerate(pl)
	elseif action == "Equip" then
		equip(pl, arg)
	elseif action == "Sync" then
		push(pl)
	end
end)

function MountService.OpenIncubator(pl: Player)
	if MountCatalog.Enabled == false then
		notify(pl, "Incubadora: próximamente")
		return
	end
	if data[pl] then
		push(pl)
		OpenRemote:FireClient(pl, "Incubator")
	end
end

-- Solo pruebas (comandos /montura y /listo de DevCommands)
function MountService.DevGrantMount(pl: Player, speciesId: string, rarity: string)
	local d = data[pl]
	if not d or not MountCatalog.Parse(MountCatalog.Key(speciesId, rarity)) then
		notify(pl, "Uso: /montura <Especie> <Rareza>. Especies: Jabali Ciervo Sapo Lobo Corcel Tortuga Tigre Oso Medusa Nube Espectro Alfombra · Rarezas: Comun Raro Epico Legendario Mitico")
		return
	end
	local key = MountCatalog.Key(speciesId, rarity)
	d.Owned[key] = math.min(MountCatalog.MaxLevel, (d.Owned[key] or 0) + 1)
	d.Equipped = key
	push(pl)
end

function MountService.DevFinishIncubation(pl: Player)
	local d = data[pl]
	if d and d.Incub then
		d.Incub.EndsAt = os.time()
		push(pl)
	end
end

function MountService.IsMounted(pl: Player): boolean
	return mounted[pl] ~= nil
end

local function valid(raw: any): Data
	local d = newData()
	if typeof(raw) ~= "table" then
		return d
	end
	if typeof(raw.Eggs) == "table" then
		for _, e in ipairs(raw.Eggs) do
			if typeof(e) == "table" and typeof(e.Tier) == "number" and #d.Eggs < MountCatalog.MaxEggsBag then
				table.insert(d.Eggs, { Tier = math.clamp(math.floor(e.Tier), 1, #MountCatalog.Eggs), Source = if typeof(e.Source) == "string" then e.Source else "Nido" })
			end
		end
	end
	if typeof(raw.Incub) == "table" and typeof(raw.Incub.Tier) == "number" and typeof(raw.Incub.EndsAt) == "number" then
		d.Incub = { Tier = math.clamp(math.floor(raw.Incub.Tier), 1, #MountCatalog.Eggs), EndsAt = raw.Incub.EndsAt }
	end
	if typeof(raw.Owned) == "table" then
		for k, lv in pairs(raw.Owned) do
			if MountCatalog.Parse(k) and typeof(lv) == "number" then
				d.Owned[k :: string] = math.clamp(math.floor(lv), 1, MountCatalog.MaxLevel)
			end
		end
	end
	if typeof(raw.Equipped) == "string" and d.Owned[raw.Equipped] then
		d.Equipped = raw.Equipped
	end
	if typeof(raw.Pity) == "table" then
		for _, k in ipairs({ "Raro", "Epico", "Legendario" }) do
			local v = raw.Pity[k]
			if typeof(v) == "number" then
				(d.Pity :: any)[k] = math.max(0, math.floor(v))
			end
		end
	end
	if typeof(raw.Opened) == "number" then
		d.Opened = math.max(0, math.floor(raw.Opened))
	end
	if typeof(raw.Day) == "string" then
		d.Day = raw.Day
		d.Claimed = raw.Claimed == true
	end
	return d
end

local function load(pl: Player)
	local saved = PlayerData.WaitForData(pl)
	if not saved or pl.Parent == nil then
		return
	end
	data[pl] = valid((saved :: any).Mounts)
	refreshDay(data[pl])
	push(pl)
end

PlayerData.RegisterSerializer("Mounts", function(pl: Player): any?
	local d = data[pl]
	if not d then
		return nil
	end
	return {
		Eggs = d.Eggs, Incub = d.Incub, Owned = d.Owned, Equipped = d.Equipped, Pity = d.Pity, Opened = d.Opened, Day = d.Day, Claimed = d.Claimed,
	}
end)

PlayerData.Releasing:Connect(function(pl: Player)
	dismount(pl, true)
	data[pl] = nil
end)

local function hookChar(pl: Player, char: Model)
	-- al reaparecer el estado de montura se reinicia
	mounted[pl] = nil
	pl:SetAttribute("Mounted", false)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Connect(function()
			dismount(pl, true)
			push(pl)
		end)
	end
end

Players.PlayerAdded:Connect(function(pl)
	pl.CharacterAdded:Connect(function(char)
		hookChar(pl, char)
	end)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	if pl.Character then
		task.spawn(hookChar, pl, pl.Character)
	end
	pl.CharacterAdded:Connect(function(char)
		hookChar(pl, char)
	end)
	task.spawn(load, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	mounted[pl] = nil
end)

return MountService
