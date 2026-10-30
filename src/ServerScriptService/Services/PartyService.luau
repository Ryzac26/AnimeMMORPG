--!strict
--[[
    PartyService (ModuleScript) -> ServerScriptService.Services.PartyService
    Grupo (party) de hasta 5 jugadores DE LA MISMA FACCIÓN. El cliente muestra vida y energía en % de cada miembro.
    Remote "Party":
      cliente -> servidor: ("Invite", nombre) · ("Accept") · ("Decline") · ("Leave") · ("Kick", nombre)
      servidor -> cliente: ("State", { {Name, Hp, En, Leader} ... })  ·  ("Invite", nombreDeQuienInvita)  ·  ("Clear")
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(script.Parent.Net)
local EnergyRegenService = require(ServerScriptService.Services.EnergyRegenService)

local Remote = Net.Get("Party")
local Notify = Net.Get("Notify")
local MAX = 5
local INVITE_TTL = 30

type Party = { Leader: Player, Members: { Player } }
local partyOf: { [Player]: Party } = {}
local invites: { [Player]: { From: Player, At: number } } = {}

local PartyService = {}

local function notify(p: Player, t: string)
	Notify:FireClient(p, t)
end

local function indexOf(list: { Player }, p: Player): number?
	for i, v in ipairs(list) do
		if v == p then
			return i
		end
	end
	return nil
end

local function broadcast(party: Party)
	local data = {}
	for _, m in ipairs(party.Members) do
		local c = m.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local cur, mx = EnergyRegenService.GetEnergy(m)
		table.insert(data, {
			Name = m.Name,
			Hp = if h and h.MaxHealth > 0 then math.floor(h.Health / h.MaxHealth * 100 + 0.5) else 0,
			En = if mx and mx > 0 then math.floor(cur / mx * 100 + 0.5) else 0,
			Leader = m == party.Leader,
		})
	end
	for _, m in ipairs(party.Members) do
		Remote:FireClient(m, "State", data)
	end
end

local function leave(p: Player)
	local party = partyOf[p]
	if not party then
		return
	end
	partyOf[p] = nil
	local i = indexOf(party.Members, p)
	if i then
		table.remove(party.Members, i)
	end
	Remote:FireClient(p, "Clear")
	if #party.Members <= 1 then
		for _, m in ipairs(party.Members) do
			partyOf[m] = nil
			Remote:FireClient(m, "Clear")
			notify(m, "El grupo se disolvió")
		end
		return
	end
	if party.Leader == p then
		party.Leader = party.Members[1]
	end
	for _, m in ipairs(party.Members) do
		notify(m, p.Name .. " salió del grupo")
	end
	broadcast(party)
end

local function findPlayer(name: string): Player?
	local lower = string.lower(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lower or string.lower(p.DisplayName) == lower then
			return p
		end
	end
	return nil
end

Remote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
	if action == "Invite" and typeof(arg) == "string" then
		local other = findPlayer(arg)
		if not other or other == player then
			return
		end
		if other:GetAttribute("Faction") ~= player:GetAttribute("Faction") then
			notify(player, "Solo puedes invitar a tu propia facción")
			return
		end
		if partyOf[other] then
			notify(player, other.Name .. " ya está en un grupo")
			return
		end
		local party = partyOf[player]
		if party and party.Leader ~= player then
			notify(player, "Solo el líder invita")
			return
		end
		if party and #party.Members >= MAX then
			notify(player, "El grupo está lleno")
			return
		end
		invites[other] = { From = player, At = os.clock() }
		Remote:FireClient(other, "Invite", player.Name)
		notify(player, "Invitación enviada a " .. other.Name)
	elseif action == "Accept" then
		local inv = invites[player]
		invites[player] = nil
		if not inv or os.clock() - inv.At > INVITE_TTL or not inv.From.Parent or partyOf[player] then
			return
		end
		local party = partyOf[inv.From]
		if not party then
			party = { Leader = inv.From, Members = { inv.From } }
			partyOf[inv.From] = party
		end
		if #party.Members >= MAX then
			notify(player, "El grupo está lleno")
			return
		end
		table.insert(party.Members, player)
		partyOf[player] = party
		for _, m in ipairs(party.Members) do
			notify(m, player.Name .. " se unió al grupo")
		end
		broadcast(party)
	elseif action == "Decline" then
		invites[player] = nil
	elseif action == "Leave" then
		leave(player)
	elseif action == "Kick" and typeof(arg) == "string" then
		local party = partyOf[player]
		local other = findPlayer(arg)
		if party and party.Leader == player and other and other ~= player and partyOf[other] == party then
			leave(other)
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	invites[p] = nil
	leave(p)
end)

-- refresco de vida/energía (1 vez por segundo)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 1 then
		return
	end
	acc = 0
	local seen: { [Party]: boolean } = {}
	for _, party in pairs(partyOf) do
		if not seen[party] then
			seen[party] = true
			broadcast(party)
		end
	end
end)

function PartyService.SameParty(a: Player, b: Player): boolean
	return partyOf[a] ~= nil and partyOf[a] == partyOf[b]
end

print("[PartyService] Listo: grupos de hasta 5 de la misma facción.")
return PartyService
