--!strict
--[[
    MasteryService (ModuleScript) -> ServerScriptService.Services.MasteryService
    MAESTRÍA DE ROL + pase "Maestría Multiclase" (números en ReplicatedStorage.Modules.MasteryCatalog).
      - Cada rol tiene sus propios PUNTOS y RANGO (1..10). Se ganan matando monstruos con ese rol (RewardService.MobKilled).
        El bono del rango (daño / defensa / vida) se aplica solo mientras juegas con ese rol: entra como fuente "Mastery" de GearService.
      - Con el pase (atributo Pass_Multiclass):
          · los puntos suben MasteryCatalog.PASS_MULT veces más rápido
          · puedes CAMBIAR DE ROL en cualquier lugar (remote MasteryAction "Switch", rol) sin ir al Instructor
          · el EQUIPO se guarda por rol: al cambiar, se guarda lo que llevas y se pone lo último que usaste con el rol nuevo
        El cambio no se permite en la Arena, en combate (MasteryCatalog.COMBAT_LOCK s) ni muerto; vuelves al mismo sitio.
      - Remotes: MasteryAction (cliente -> servidor: "State" | "Switch", rol) · MasteryState (servidor -> cliente: estado) · MasteryResult.
    Guardado: sección "Mastery" de PlayerData = { Points = { rol = puntos }, Loadouts = { rol = { ranura = { Id, Plus } } } }.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MasteryCatalog = require(ReplicatedStorage.Modules.MasteryCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local RewardService = require(Services.RewardService)
local GearService = require(Services.GearService)
local Inventory = require(Services.InventoryService)
local ClassSelect = require(Services.ClassSelectService)
local ArenaService = require(Services.ArenaService)

local StateRemote = Net.Get("MasteryState")
local ActionRemote = Net.Get("MasteryAction")
local ResultRemote = Net.Get("MasteryResult")
local NotifyRemote = Net.Get("Notify")

type Loadout = { [string]: { Id: string, Plus: number } }
type Data = { Points: { [string]: number }, Loadouts: { [string]: Loadout } }

local MasteryService = {}
local data: { [Player]: Data } = {}
local lastSwitch: { [Player]: number } = {}
local lastAction: { [Player]: number } = {}
local switching: { [Player]: boolean } = {}

local function validRole(role: any): boolean
	return typeof(role) == "string" and table.find(MasteryCatalog.ROLES, role) ~= nil
end

local function hasPass(player: Player): boolean
	return player:GetAttribute("Pass_Multiclass") == true
end

local function roleOf(player: Player): string
	local r = player:GetAttribute("Role")
	return if typeof(r) == "string" then r else "Guerrero"
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

-- Aplica el bono del rango del rol actual
local function applyBonus(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local role = roleOf(player)
	local rank = MasteryCatalog.RankOf(d.Points[role] or 0)
	GearService.SetTemp(player, if rank > 0 then MasteryCatalog.StatsFor(rank) else nil, "Mastery")
	player:SetAttribute("MasteryRank", rank)
	local title = MasteryCatalog.RankTitle(role, rank)
	player:SetAttribute("TitleMastery", title)
end

local function pushState(player: Player)
	local d = data[player]
	if not d then
		return
	end
	local roles: { { Role: string, Points: number, Rank: number, HasLoadout: boolean } } = {}
	for _, role in ipairs(MasteryCatalog.ROLES) do
		local pts = d.Points[role] or 0
		table.insert(roles, { Role = role, Points = math.floor(pts), Rank = MasteryCatalog.RankOf(pts), HasLoadout = d.Loadouts[role] ~= nil })
	end
	StateRemote:FireClient(player, { Roles = roles, Current = roleOf(player), Pass = hasPass(player) })
end

---------------------------------------------------------------------
-- Puntos por monstruo derrotado
---------------------------------------------------------------------
RewardService.MobKilled:Connect(function(mobId: any, level: any, participants: any, _shares: any)
	if typeof(mobId) ~= "string" or typeof(level) ~= "number" or typeof(participants) ~= "table" then
		return
	end
	local special = string.find(mobId, "Metin", 1, true) ~= nil or string.sub(mobId, 1, 5) == "Mini|"
	for _, pl in ipairs(participants :: { Player }) do
		local d = data[pl]
		local plLevel = pl:GetAttribute("Level")
		if d and pl.Parent and typeof(plLevel) == "number" and level >= plLevel - MasteryCatalog.LEVEL_WINDOW then
			local role = roleOf(pl)
			local before = MasteryCatalog.RankOf(d.Points[role] or 0)
			local gain = (if special then MasteryCatalog.SPECIAL_KILL_POINTS else 1) * (if hasPass(pl) then MasteryCatalog.PASS_MULT else 1)
			d.Points[role] = (d.Points[role] or 0) + gain
			local after = MasteryCatalog.RankOf(d.Points[role])
			if after > before then
				applyBonus(pl)
				NotifyRemote:FireClient(pl, string.format("★ ¡Maestría de %s: rango %d/%d!", role, after, MasteryCatalog.MAX_RANK))
				pushState(pl)
			end
		end
	end
end)

---------------------------------------------------------------------
-- Cambio de rol en cualquier lugar (pase)
---------------------------------------------------------------------
local function switchRole(player: Player, role: any)
	if not hasPass(player) then
		reply(player, false, "Necesitas el pase Maestría Multiclase (Tienda > Pases). Sin él, cambia de rol con el Instructor.")
		return
	end
	local d = data[player]
	if not d or not validRole(role) or switching[player] then
		return
	end
	local newRole = role :: string
	local oldRole = roleOf(player)
	if newRole == oldRole then
		reply(player, false, "Ya juegas con ese rol.")
		return
	end
	local now = os.clock()
	local wait = (lastSwitch[player] or 0) + MasteryCatalog.SWITCH_COOLDOWN - now
	if wait > 0 then
		reply(player, false, string.format("Espera %d s para volver a cambiar de rol.", math.ceil(wait)))
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then
		reply(player, false, "No puedes cambiar de rol ahora.")
		return
	end
	if ArenaService.IsInArena(root.Position) then
		reply(player, false, "No se puede cambiar de rol dentro de la Arena.")
		return
	end
	local lastHit = char:GetAttribute("LastHitAt")
	if typeof(lastHit) == "number" and now - lastHit < MasteryCatalog.COMBAT_LOCK then
		reply(player, false, "No puedes cambiar de rol en combate.")
		return
	end
	switching[player] = true
	lastSwitch[player] = now
	local cf = root.CFrame
	-- guarda el equipo del rol actual (antes de que el rol cambie)
	d.Loadouts[oldRole] = Inventory.GetLoadout(player)
	local saved = d.Loadouts[newRole]
	local ok = ClassSelect.SwitchRole(player, newRole, function()
		Inventory.ApplyLoadout(player, saved) -- rol nuevo ya puesto: equipa lo suyo antes de reaparecer
		applyBonus(player)
	end)
	if not ok then
		switching[player] = nil
		reply(player, false, "No se pudo cambiar de rol ahora.")
		return
	end
	-- LoadCharacter reaparece en la ciudad: se te devuelve al mismo sitio
	task.spawn(function()
		local newChar = player.Character
		local deadline = os.clock() + 5
		while player.Parent and os.clock() < deadline do
			newChar = player.Character
			local r = newChar and newChar:FindFirstChild("HumanoidRootPart")
			if newChar and r and r:IsA("BasePart") then
				task.wait(0.5)
				if player.Character == newChar then
					newChar:PivotTo(cf + Vector3.new(0, 3, 0))
				end
				break
			end
			task.wait(0.2)
		end
		switching[player] = nil
		if player.Parent then
			reply(player, true, string.format("Ahora juegas como %s.", newRole))
			pushState(player)
			PlayerData.Save(player)
		end
	end)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, role: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.4 then
		return
	end
	lastAction[player] = now
	if action == "State" then
		pushState(player)
	elseif action == "Switch" then
		switchRole(player, role)
	end
end)

---------------------------------------------------------------------
-- Guardado / carga
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Mastery", function(player: Player): any?
	local d = data[player]
	if not d then
		return nil
	end
	local points: { [string]: number } = {}
	for role, v in pairs(d.Points) do
		points[role] = math.floor(v * 10) / 10
	end
	return { Points = points, Loadouts = d.Loadouts }
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = (saved :: any).Mastery
	local d: Data = { Points = {}, Loadouts = {} }
	if typeof(raw) == "table" then
		if typeof(raw.Points) == "table" then
			for role, v in pairs(raw.Points) do
				if validRole(role) and typeof(v) == "number" and v >= 0 then
					d.Points[role] = math.min(v, 1e9)
				end
			end
		end
		if typeof(raw.Loadouts) == "table" then
			for role, lo in pairs(raw.Loadouts) do
				if validRole(role) and typeof(lo) == "table" then
					local clean: Loadout = {}
					for slotName, rec in pairs(lo) do
						if typeof(slotName) == "string" and typeof(rec) == "table" and typeof(rec.Id) == "string" and typeof(rec.Plus) == "number" then
							clean[slotName] = { Id = rec.Id, Plus = math.floor(rec.Plus) }
						end
					end
					d.Loadouts[role] = clean
				end
			end
		end
	end
	data[player] = d
	applyBonus(player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		applyBonus(player)
	end)
	pushState(player)
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
PlayerData.Releasing:Connect(function(pl: Player)
	data[pl] = nil
	lastSwitch[pl] = nil
	lastAction[pl] = nil
	switching[pl] = nil
end)

return MasteryService
