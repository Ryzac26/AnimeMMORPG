--!strict
--[[
    DamageRankService (ModuleScript) -> ServerScriptService.Services.DamageRankService
    RANKING DE DAÑO en pantalla para los mobs de mucha vida: jefe mundial, jefe de franja, mini jefe y piedras Metin
    (atributos WorldBoss / Boss / Mini / Metin). Los mobs normales NO lo muestran.
      - Cada golpe de un jugador a uno de esos mobs se suma (DamageService.AddDamageListener).
      - Cada ~0.5 s manda a quienes lo están golpeando (últimos 25 s) el ranking: facciones (% del total), jugadores (top 8),
        la posición del propio jugador y el % de su grupo (PartyService).
      - Cuando el mob muere o desaparece, manda "cerrar" y la ventana desaparece sola.
    Remote: DmgRank (servidor -> cliente). El cliente solo muestra.
]]
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local DamageService = require(Services.DamageService)
local Net = require(Services.Net)

local Remote = Net.Get("DmgRank")

local VIEW_SECONDS = 25 -- tras dejar de golpearlo, la ventana se cierra a los 25 s
local SEND_EVERY = 0.5
local TOP = 8

type Log = {
	Id: number,
	Mob: Model,
	Kind: string,
	Total: number,
	ByPlayer: { [Player]: number },
	LastHit: { [Player]: number },
	Dirty: boolean,
	LastSend: number,
}
local logs: { [Model]: Log } = {}
local nextId = 0

local function kindOf(m: Model): string?
	if m:GetAttribute("WorldBoss") == true then
		return "World"
	elseif m:GetAttribute("Metin") == true then
		return "Metin"
	elseif m:GetAttribute("Boss") == true then
		return "Boss"
	elseif m:GetAttribute("Mini") == true then
		return "Mini"
	end
	return nil
end

local function mobName(m: Model): string
	local n = m:GetAttribute("DisplayName")
	return if typeof(n) == "string" and n ~= "" then n else m.Name
end

local function sameParty(a: Player, b: Player): boolean
	local ok, ps = pcall(function()
		return require(Services.PartyService)
	end)
	if ok and type(ps) == "table" and ps.SameParty then
		local ok2, r = pcall(ps.SameParty, a, b)
		return ok2 and r == true
	end
	return false
end

local function viewersOf(log: Log): { Player }
	local out: { Player } = {}
	local now = os.clock()
	for pl, t in pairs(log.LastHit) do
		if pl.Parent and now - t <= VIEW_SECONDS then
			table.insert(out, pl)
		end
	end
	return out
end

local function send(log: Log)
	log.Dirty = false
	log.LastSend = os.clock()
	if log.Total <= 0 then
		return
	end
	local rows: { { Player: Player, Dmg: number } } = {}
	local byFaction: { [string]: number } = {}
	for pl, dmg in pairs(log.ByPlayer) do
		if pl.Parent then
			table.insert(rows, { Player = pl, Dmg = dmg })
			local f = tostring(pl:GetAttribute("Faction") or "")
			byFaction[f] = (byFaction[f] or 0) + dmg
		end
	end
	table.sort(rows, function(a, b)
		return a.Dmg > b.Dmg
	end)
	local top = {}
	for i = 1, math.min(TOP, #rows) do
		local r = rows[i]
		table.insert(top, { r.Player.DisplayName, tostring(r.Player:GetAttribute("Faction") or ""), r.Dmg, r.Player.UserId })
	end
	local factions = {}
	for f, d in pairs(byFaction) do
		table.insert(factions, { f, d })
	end
	table.sort(factions, function(a, b)
		return a[2] > b[2]
	end)
	local hum = log.Mob:FindFirstChildOfClass("Humanoid")
	local frac = if hum and hum.MaxHealth > 0 then math.clamp(hum.Health / hum.MaxHealth, 0, 1) else 1

	for _, viewer in ipairs(viewersOf(log)) do
		local pos, mine = 0, 0
		local party = 0
		for i, r in ipairs(rows) do
			if r.Player == viewer then
				pos, mine = i, r.Dmg
			end
			if r.Player == viewer or sameParty(viewer, r.Player) then
				party += r.Dmg
			end
		end
		Remote:FireClient(viewer, {
			id = log.Id,
			name = mobName(log.Mob),
			kind = log.Kind,
			hp = frac,
			total = log.Total,
			top = top,
			factions = factions,
			count = #rows,
			pos = pos,
			mine = mine,
			party = if party > mine then party else 0,
		})
	end
end

local function close(log: Log)
	for _, viewer in ipairs(viewersOf(log)) do
		Remote:FireClient(viewer, { id = log.Id, closed = true })
	end
	logs[log.Mob] = nil
end

DamageService.AddDamageListener(function(mob: Model, player: Player, amount: number)
	local kind = kindOf(mob)
	if not kind or amount <= 0 then
		return
	end
	local log = logs[mob]
	if not log then
		nextId += 1
		log = {
			Id = nextId, Mob = mob, Kind = kind, Total = 0, ByPlayer = {}, LastHit = {}, Dirty = false, LastSend = 0,
		}
		logs[mob] = log
		local hum = mob:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Once(function()
				local l = logs[mob]
				if l then
					close(l)
				end
			end)
		end
		mob.AncestryChanged:Connect(function(_, parent)
			if not parent then
				local l = logs[mob]
				if l then
					close(l)
				end
			end
		end)
	end
	local l = log :: Log
	l.Total += amount
	l.ByPlayer[player] = (l.ByPlayer[player] or 0) + amount
	l.LastHit[player] = os.clock()
	l.Dirty = true
	if os.clock() - l.LastSend >= SEND_EVERY then
		send(l)
	end
end)

-- reenvío de los pendientes y cierre a quienes llevan 25 s sin golpear
task.spawn(function()
	while true do
		task.wait(SEND_EVERY)
		local now = os.clock()
		for mob, log in pairs(logs) do
			if not mob.Parent then
				close(log)
			else
				if log.Dirty and now - log.LastSend >= SEND_EVERY then
					send(log)
				end
				for pl, t in pairs(log.LastHit) do
					if now - t > VIEW_SECONDS then
						log.LastHit[pl] = nil
						if pl.Parent then
							Remote:FireClient(pl, { id = log.Id, closed = true })
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	for _, log in pairs(logs) do
		log.ByPlayer[pl] = nil
		log.LastHit[pl] = nil
	end
end)

return {}
