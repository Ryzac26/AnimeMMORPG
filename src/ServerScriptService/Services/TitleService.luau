--!strict
--[[
    TitleService (ModuleScript) -> ServerScriptService.Services.TitleService
    TÍTULOS ÚNICOS (catálogo en ReplicatedStorage.Modules.TitleCatalog).
      - Desbloqueo por progreso (nivel, kills, Metin, jefes, tiempo, forja, daño en el maniquí) o por hechos (TitleService.Grant).
      - El jugador equipa UNO: se muestra sobre su cabeza con degradado por rareza y en el Perfil. Atributos: TitleEquipped, TitleText.
      - Perfil: sección "Titles" = { U = {ids}, E = id equipado, C = { Kill, Metin, Boss, Min } }.
      - Remotes: TitleState (servidor -> cliente: { Unlocked, Equipped, Counters }) · TitleAction ("State" | "Equip", id | "" para quitar).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local RewardService = require(Services.RewardService)
local TitleCatalog = require(ReplicatedStorage.Modules.TitleCatalog)

local StateRemote = Net.Get("TitleState")
local ActionRemote = Net.Get("TitleAction")
local NotifyRemote = Net.Get("Notify")

type Profile = { U: { [string]: boolean }, E: string?, C: { [string]: number } }
local profiles: { [Player]: Profile } = {}
local pushQueued: { [Player]: boolean } = {}

local TitleService = {}

local function blank(): Profile
	return { U = {}, E = nil, C = { Kill = 0, Metin = 0, Boss = 0, Min = 0 } }
end

PlayerData.RegisterSerializer("Titles", function(player: Player): any?
	local p = profiles[player]
	if not p then
		return nil
	end
	local list: { string } = {}
	for id in pairs(p.U) do
		table.insert(list, id)
	end
	return { U = list, E = p.E, C = p.C }
end)

---------------------------------------------------------------------
-- Cartel sobre la cabeza
---------------------------------------------------------------------
local function applyTag(player: Player)
	local p = profiles[player]
	local def = if p and p.E then TitleCatalog.ById[p.E] else nil
	player:SetAttribute("TitleEquipped", if def then def.Id else nil)
	player:SetAttribute("TitleText", if def then def.Name else nil)
	-- bonus pequeño del título equipado (GearService lo suma a las estadísticas, como el Maestría)
	local okG, gear = pcall(function()
		return require(Services.GearService)
	end)
	if okG and type(gear) == "table" and gear.SetTemp then
		gear.SetTemp(player, if def then def.Bonus else nil, "Titulo")
	end
	-- la placa animada sobre la cabeza la dibuja cada cliente (TitleTagClient) a partir de estos atributos
	local head = player.Character and player.Character:FindFirstChild("Head")
	local legacy = head and head:FindFirstChild("TituloTag")
	if legacy then
		legacy:Destroy()
	end
end

---------------------------------------------------------------------
-- Estado hacia el cliente
---------------------------------------------------------------------
local function push(player: Player)
	local p = profiles[player]
	if not p or player.Parent == nil then
		return
	end
	StateRemote:FireClient(player, { Unlocked = p.U, Equipped = p.E, Counters = p.C })
end

local function queuePush(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.delay(1.5, function()
		pushQueued[player] = nil
		push(player)
	end)
end

---------------------------------------------------------------------
-- Desbloqueo
---------------------------------------------------------------------
local function unlock(player: Player, id: string)
	local p = profiles[player]
	local def = TitleCatalog.ById[id]
	if not p or not def or p.U[id] then
		return
	end
	local faction = player:GetAttribute("Faction")
	if def.Faction and def.Faction ~= faction then
		return
	end
	p.U[id] = true
	NotifyRemote:FireClient(player, string.format("🏷 ¡Nuevo título: %s %s! (%s)", def.Icon or "✦", def.Name, TitleCatalog.RarityName[def.Rarity] or ""))
	if not p.E then
		p.E = id -- el primero se equipa solo
		applyTag(player)
	end
	queuePush(player)
end

local function progress(player: Player, kind: string): number
	local p = profiles[player]
	if kind == "Level" then
		local lv = player:GetAttribute("Level")
		return if typeof(lv) == "number" then lv else 0
	elseif kind == "Dmg" then
		local v = player:GetAttribute("HallBest")
		return if typeof(v) == "number" then v else 0
	elseif kind == "Forja9" then
		local v = player:GetAttribute("Forja9")
		return if typeof(v) == "number" then v else 0
	end
	return if p then (p.C[kind] or 0) else 0
end

local function check(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	for _, def in ipairs(TitleCatalog.List) do
		if def.Kind ~= "Grant" and not p.U[def.Id] and def.Value and progress(player, def.Kind) >= def.Value then
			unlock(player, def.Id)
		end
	end
end

function TitleService.Grant(player: Player, id: string)
	unlock(player, id)
end

local function bump(player: Player, key: string, n: number)
	local p = profiles[player]
	if not p then
		return
	end
	p.C[key] = (p.C[key] or 0) + n
	check(player)
end

---------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------
local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local p = blank()
	local raw: any = (saved :: any).Titles
	if typeof(raw) == "table" then
		if typeof(raw.U) == "table" then
			for _, id in ipairs(raw.U) do
				if typeof(id) == "string" and TitleCatalog.ById[id] then
					p.U[id] = true
				end
			end
		end
		if typeof(raw.E) == "string" and p.U[raw.E] then
			p.E = raw.E
		end
		if typeof(raw.C) == "table" then
			for k, v in pairs(raw.C) do
				if typeof(k) == "string" and typeof(v) == "number" then
					p.C[k] = v
				end
			end
		end
	end
	profiles[player] = p
	applyTag(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		applyTag(player)
	end)
	for _, attr in ipairs({ "Level", "HallBest", "Forja9", "Faction" }) do
		player:GetAttributeChangedSignal(attr):Connect(function()
			check(player)
		end)
	end
	task.wait(3)
	check(player)
	push(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, id: any)
	local p = profiles[player]
	if not p then
		return
	end
	if action == "State" then
		push(player)
	elseif action == "Equip" then
		if id == "" or id == nil then
			p.E = nil
		elseif typeof(id) == "string" and p.U[id] and TitleCatalog.ById[id] then
			p.E = id
		else
			return
		end
		applyTag(player)
		push(player)
	end
end)

RewardService.MobKilled:Connect(function(mobId: string, _level: number, participants: { Player }, _shares: any)
	local key = if string.sub(mobId, 1, 6) == "Metin_" then "Metin" elseif mobId == "WorldBoss" then "Boss" else "Kill"
	for _, pl in ipairs(participants) do
		bump(pl, key, 1)
	end
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, pl in ipairs(Players:GetPlayers()) do
			if profiles[pl] then
				bump(pl, "Min", 1)
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	task.delay(30, function()
		profiles[pl] = nil
		pushQueued[pl] = nil
	end)
end)

print("[TitleService] Listo: " .. #TitleCatalog.List .. " títulos.")

return TitleService
