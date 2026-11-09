--!strict
--[[
    LevelMilestoneService (ModuleScript) -> ServerScriptService.Services.LevelMilestoneService
    HITOS DE NIVEL y AURAS (catálogo en ReplicatedStorage.Modules.LevelMilestones).
      - Perfil: sección "Hitos" = { C = { índices reclamados }, A = id de aura elegida }.
      - Remotes: MilestoneState (servidor -> cliente: { Claimed = { [index]=true }, Aura = id? }) ·
                 MilestoneAction ("State" | "Claim", index | "ClaimAll" | "Aura", id o "" para quitar).
      - Atributo del jugador "Aura" (id): lo dibuja AuraClient para todos.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local WalletService = require(Services.WalletService)
local Inventory = require(Services.InventoryService)
local Milestones = require(ReplicatedStorage.Modules.LevelMilestones)

local StateRemote = Net.Get("MilestoneState")
local ActionRemote = Net.Get("MilestoneAction")
local NotifyRemote = Net.Get("Notify")

type Profile = { Claimed: { [number]: boolean }, Aura: string? }
local profiles: { [Player]: Profile } = {}

local Service = {}

PlayerData.RegisterSerializer("Hitos", function(player: Player): any?
	local p = profiles[player]
	if not p then
		return nil
	end
	local list: { number } = {}
	for i in pairs(p.Claimed) do
		table.insert(list, i)
	end
	table.sort(list)
	return { C = list, A = p.Aura }
end)

local function levelOf(player: Player): number
	local v = player:GetAttribute("Level")
	return if typeof(v) == "number" then v else 1
end

local function push(player: Player)
	local p = profiles[player]
	if p then
		StateRemote:FireClient(player, { Claimed = p.Claimed, Aura = p.Aura })
	end
end

-- Auras de facción: solo las puede usar quien sea de esa facción (atributo Faction del jugador)
local function canUseAura(player: Player, def: any): boolean
	if levelOf(player) < def.Need then
		return false
	end
	return def.Faction == nil or player:GetAttribute("Faction") == def.Faction
end

local function applyAura(player: Player)
	local p = profiles[player]
	local def = if p and p.Aura then Milestones.AuraById[p.Aura] else nil
	if def and not canUseAura(player, def) then
		def = nil
	end
	player:SetAttribute("Aura", if def then def.Id else nil)
end

local function claim(player: Player, index: number): boolean
	local p = profiles[player]
	if not p or index < 1 or index > Milestones.COUNT or index % 1 ~= 0 or p.Claimed[index] then
		return false
	end
	if levelOf(player) < Milestones.LevelOf(index) then
		return false
	end
	local r = Milestones.Reward(index)
	p.Claimed[index] = true
	local gold = r.Gold
	if r.Mat and not Inventory.Add(player, r.Mat, r.MatCount) then
		gold += r.MatCount * 150 -- mochila llena: se compensa con oro
	end
	if r.Scroll > 0 and not Inventory.Add(player, "Pergamino_Proteccion", r.Scroll) then
		gold += r.Scroll * 5000
	end
	WalletService.AddGold(player, gold, "Hitos")
	return true
end

local function loadProfile(player: Player)
	local p: Profile = { Claimed = {}, Aura = nil }
	local ok, data = pcall(function()
		return PlayerData.WaitForData(player)
	end)
	local sec = if ok and type(data) == "table" then (data :: any).Hitos else nil
	if type(sec) == "table" then
		for _, i in ipairs(sec.C or {}) do
			if type(i) == "number" then
				p.Claimed[i] = true
			end
		end
		if type(sec.A) == "string" and Milestones.AuraById[sec.A] then
			p.Aura = sec.A
		end
	end
	profiles[player] = p
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		applyAura(player)
	end)
	applyAura(player)
	push(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
	local p = profiles[player]
	if not p then
		return
	end
	if action == "State" then
		push(player)
	elseif action == "Claim" and type(arg) == "number" then
		if claim(player, arg) then
			NotifyRemote:FireClient(player, string.format("🎁 ¡Recompensa del nivel %d reclamada!", Milestones.LevelOf(arg)))
		end
		push(player)
	elseif action == "ClaimAll" then
		local n = 0
		for i = 1, Milestones.COUNT do
			if claim(player, i) then
				n += 1
			end
		end
		if n > 0 then
			NotifyRemote:FireClient(player, string.format("🎁 %d recompensas de nivel reclamadas", n))
		end
		push(player)
	elseif action == "Aura" and type(arg) == "string" then
		if arg == "" then
			p.Aura = nil
		else
			local def = Milestones.AuraById[arg]
			if def and canUseAura(player, def) then
				p.Aura = def.Id
			end
		end
		applyAura(player)
		push(player)
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadProfile, player)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		applyAura(player)
	end)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(loadProfile, pl)
end
-- Releasing = después de la foto final del guardado (PlayerRemoving corría antes y se guardaba vacío)
PlayerData.Releasing:Connect(function(pl: Player)
	profiles[pl] = nil
end)

return Service
