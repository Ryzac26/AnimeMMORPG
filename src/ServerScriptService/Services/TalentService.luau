--!strict
--[[
    TalentService (ModuleScript) -> ServerScriptService.Services.TalentService
    ÁRBOL DE TALENTOS (catálogo en ReplicatedStorage.Modules.TalentCatalog). TODO se valida aquí: puntos, rangos, requisitos, pases.
      - 3 builds (pestañas): la 1 es gratis; la 2 y la 3 piden los pases Pass_Talents2 / Pass_Talents3 (ProductCatalog.Passes).
        Solo la build ACTIVA aplica sus bonos. Cada build puede VINCULARSE a un rol: al cambiar de rol (pase Multiclase) se activa sola.
      - Puntos: TalentCatalog.PointsFor(nivel). Cada build tiene los mismos puntos y los gasta aparte.
      - Reinicio de una build: el primero es gratis (TalentCatalog.FREE_RESPECS); luego cuesta oro según el nivel.
      - Stats propios -> GearService.SetTemp(..., "Talentos"). Auras (soporte/tanque) -> a los aliados del grupo cercanos, "TalentAura":
        se toma el MEJOR valor de cada stat entre los auras que te alcanzan (no se suman entre soportes: tope por grupo).
      - Perfil: sección "Talents" = { A = build activa, S = { {R = {nodo = rango}, Role = rol?, F = reinicios gratis} x3 } }.
      - Remotes: TalentState (servidor -> cliente) · TalentAction ("State" | "Upgrade", slot, nodo | "Slot", n | "Reset", slot | "Link", slot, "rol" o "").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local WalletService = require(Services.WalletService)
local GearService = require(Services.GearService)
local Catalog = require(ReplicatedStorage.Modules.TalentCatalog)
local GB = require(ReplicatedStorage.Modules.GameBalance)

local StateRemote = Net.Get("TalentState")
local ActionRemote = Net.Get("TalentAction")
local NotifyRemote = Net.Get("Notify")

type Slot = { R: { [string]: number }, Role: string?, F: number }
type Profile = { Active: number, Slots: { Slot } }
local profiles: { [Player]: Profile } = {}
local lastAction: { [Player]: number } = {}
local appliedAura: { [Player]: string } = {}

local Service = {}

local function newSlot(): Slot
	return { R = {}, Role = nil, F = Catalog.FREE_RESPECS }
end

PlayerData.RegisterSerializer("Talents", function(player: Player): any?
	local p = profiles[player]
	if not p then
		return nil
	end
	local slots = {}
	for i, s in ipairs(p.Slots) do
		slots[i] = { R = s.R, Role = s.Role, F = s.F }
	end
	return { A = p.Active, S = slots }
end)

local function levelOf(player: Player): number
	local v = player:GetAttribute("Level")
	return if typeof(v) == "number" then v else 1
end

local function slotOwned(player: Player, n: number): boolean
	local attr = Catalog.SLOT_PASS[n]
	return n == 1 or (attr ~= nil and attr ~= "" and player:GetAttribute(attr) == true)
end

local function spentIn(slot: Slot, branch: string?): number
	local sum = 0
	for id, r in pairs(slot.R) do
		local n = Catalog.ById[id]
		if n and (branch == nil or n.Branch == branch) then
			sum += Catalog.TotalCost(n, r)
		end
	end
	return sum
end

local function keystones(slot: Slot): number
	local c = 0
	for id, r in pairs(slot.R) do
		local n = Catalog.ById[id]
		if n and n.Key and r > 0 then
			c += 1
		end
	end
	return c
end

local function respecCost(player: Player): number
	return math.floor(5000 * (1 + GB.Eq(levelOf(player)) * 0.6))
end

local function push(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	local slots = {}
	for i, s in ipairs(p.Slots) do
		slots[i] = { R = s.R, Role = s.Role, F = s.F, Owned = slotOwned(player, i), Spent = spentIn(s, nil) }
	end
	StateRemote:FireClient(player, { Active = p.Active, Slots = slots, Points = Catalog.PointsFor(levelOf(player)), RespecCost = respecCost(player) })
end

-- ¿es válida la build? (el nivel pudo bajar o la facción cambiar): quita lo que ya no cumple, sin devolver puntos de más
local function sanitize(player: Player, slot: Slot)
	local faction = player:GetAttribute("Faction")
	for id in pairs(slot.R) do
		local n = Catalog.ById[id]
		if not n or (n.Faction and n.Faction ~= faction) then
			slot.R[id] = nil
		end
	end
end

local function applyActive(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	local slot = p.Slots[p.Active]
	if not slot or not slotOwned(player, p.Active) then
		slot = p.Slots[1]
		p.Active = 1
	end
	local stats, aura = Catalog.Evaluate(slot.R)
	GearService.SetTemp(player, if next(stats) then stats else nil, "Talentos")
	player:SetAttribute("TalentAura", if next(aura) then game:GetService("HttpService"):JSONEncode(aura) else nil)
end

local function loadProfile(player: Player)
	local p: Profile = { Active = 1, Slots = { newSlot(), newSlot(), newSlot() } }
	local ok, data = pcall(function()
		return PlayerData.WaitForData(player)
	end)
	local sec = if ok and type(data) == "table" then (data :: any).Talents else nil
	if type(sec) == "table" then
		if type(sec.A) == "number" and sec.A >= 1 and sec.A <= Catalog.SLOTS then
			p.Active = math.floor(sec.A)
		end
		for i, s in ipairs(sec.S or {}) do
			if i <= Catalog.SLOTS and type(s) == "table" then
				local slot = p.Slots[i]
				for id, r in pairs(s.R or {}) do
					if type(id) == "string" and type(r) == "number" and Catalog.ById[id] then
						slot.R[id] = math.clamp(math.floor(r), 0, Catalog.MaxRankOf(Catalog.ById[id]))
					end
				end
				slot.Role = if type(s.Role) == "string" then s.Role else nil
				slot.F = if type(s.F) == "number" then math.max(0, math.floor(s.F)) else Catalog.FREE_RESPECS
			end
		end
	end
	profiles[player] = p
	for _, s in ipairs(p.Slots) do
		sanitize(player, s)
	end
	applyActive(player)
	push(player)
end

local function notify(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

local function upgrade(player: Player, slotN: number, nodeId: string)
	local p = profiles[player]
	local node = Catalog.ById[nodeId]
	if not p or not node or slotN ~= slotN or slotN < 1 or slotN > Catalog.SLOTS or slotN % 1 ~= 0 or not slotOwned(player, slotN) then
		return
	end
	local slot = p.Slots[slotN]
	if node.Faction and node.Faction ~= player:GetAttribute("Faction") then
		return
	end
	local rank = slot.R[nodeId] or 0
	if rank >= Catalog.MaxRankOf(node) then
		return
	end
	local level = levelOf(player)
	local ok, why = Catalog.Requirement(node, level, spentIn(slot, node.Branch))
	if not ok then
		notify(player, "🔒 " .. (why or "No cumples el requisito"))
		return
	end
	if node.Key and keystones(slot) >= Catalog.MAX_KEYSTONES then
		notify(player, string.format("Solo puedes tener %d talentos CLAVE activos a la vez", Catalog.MAX_KEYSTONES))
		return
	end
	local cost = Catalog.CostOf(node, rank + 1)
	if Catalog.PointsFor(level) - spentIn(slot, nil) < cost then
		notify(player, string.format("Te faltan puntos de talento (cuesta %d)", cost))
		return
	end
	slot.R[nodeId] = rank + 1
	if slotN == p.Active then
		applyActive(player)
	end
	push(player)
end

local function resetSlot(player: Player, slotN: number)
	local p = profiles[player]
	if not p or slotN < 1 or slotN > Catalog.SLOTS or slotN % 1 ~= 0 or not slotOwned(player, slotN) then
		return
	end
	local slot = p.Slots[slotN]
	if next(slot.R) == nil then
		return
	end
	if slot.F > 0 then
		slot.F -= 1
	else
		if not WalletService.TrySpendGold(player, respecCost(player), "Respec") then
			notify(player, string.format("Reiniciar cuesta %d de oro", respecCost(player)))
			return
		end
	end
	slot.R = {}
	if slotN == p.Active then
		applyActive(player)
	end
	notify(player, "♻ Build reiniciada: recuperaste todos tus puntos")
	push(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	local p = profiles[player]
	if not p then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.08 then
		return -- anti spam
	end
	lastAction[player] = now
	if action == "State" then
		push(player)
	elseif action == "Upgrade" and type(a) == "number" and type(b) == "string" then
		upgrade(player, a, b)
	elseif action == "Slot" and type(a) == "number" and a >= 1 and a <= Catalog.SLOTS and a % 1 == 0 then
		if slotOwned(player, a) then
			p.Active = a
			applyActive(player)
			push(player)
		else
			notify(player, "🔒 Esta build necesita su pase en la Tienda")
		end
	elseif action == "Reset" and type(a) == "number" then
		resetSlot(player, a)
	elseif action == "Link" and type(a) == "number" and a >= 1 and a <= Catalog.SLOTS and a % 1 == 0 and slotOwned(player, a) then
		local role = if type(b) == "string" and b ~= "" then player:GetAttribute("Role") else nil
		-- un rol solo puede estar en una build
		for i, s in ipairs(p.Slots) do
			if role ~= nil and s.Role == role and i ~= a then
				s.Role = nil
			end
		end
		p.Slots[a].Role = if typeof(role) == "string" then role else nil
		push(player)
	end
end)

-- al cambiar de rol (Instructor o pase Multiclase) se activa la build vinculada a ese rol
local function onRole(player: Player)
	local p = profiles[player]
	local role = player:GetAttribute("Role")
	if not p or typeof(role) ~= "string" then
		return
	end
	for i, s in ipairs(p.Slots) do
		if s.Role == role and slotOwned(player, i) and p.Active ~= i then
			p.Active = i
			applyActive(player)
			push(player)
			notify(player, string.format("🌳 Build %d activada para tu rol %s", i, role))
			return
		end
	end
end

-- AURAS: el mejor valor de cada stat entre los aliados cercanos del grupo (y el propio)
local function auraOf(player: Player): { [string]: number }?
	local raw = player:GetAttribute("TalentAura")
	if typeof(raw) ~= "string" then
		return nil
	end
	local ok, t = pcall(function()
		return game:GetService("HttpService"):JSONDecode(raw)
	end)
	return if ok and type(t) == "table" then t else nil
end

local function rootOf(pl: Player): BasePart?
	local c = pl.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function auraTick()
	local okP, Party = pcall(function()
		return require(Services.PartyService)
	end)
	local best: { [Player]: { [string]: number } } = {}
	for _, src in ipairs(Players:GetPlayers()) do
		local aura = auraOf(src)
		local sr = rootOf(src)
		if aura and sr then
			local members = if okP and type(Party) == "table" and Party.MembersOf then Party.MembersOf(src) else { src }
			for _, m in ipairs(members) do
				local mr = rootOf(m)
				if mr and (m == src or (mr.Position - sr.Position).Magnitude <= Catalog.AURA_RANGE) then
					local cur = best[m]
					if not cur then
						cur = {}
						best[m] = cur
					end
					for st, v in pairs(aura) do
						if v > (cur[st] or 0) then
							cur[st] = v
						end
					end
				end
			end
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		local t = best[pl]
		local parts = {}
		if t then
			for st, v in pairs(t) do
				table.insert(parts, string.format("%s=%.4f", st, v))
			end
			table.sort(parts)
		end
		local sig = table.concat(parts, ",")
		if (appliedAura[pl] or "") ~= sig and profiles[pl] then
			appliedAura[pl] = sig
			GearService.SetTemp(pl, if t and next(t) then t else nil, "TalentAura")
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(loadProfile, player)
	player:GetAttributeChangedSignal("Role"):Connect(function()
		onRole(player)
	end)
	player:GetAttributeChangedSignal("Level"):Connect(function()
		push(player)
	end)
	for i = 2, Catalog.SLOTS do
		local attr = Catalog.SLOT_PASS[i]
		player:GetAttributeChangedSignal(attr):Connect(function()
			push(player)
		end)
	end
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(loadProfile, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	profiles[pl] = nil
	lastAction[pl] = nil
	appliedAura[pl] = nil
end)

task.spawn(function()
	while true do
		task.wait(2)
		local ok, err = pcall(auraTick)
		if not ok then
			warn("[TalentService] aura:", err)
		end
	end
end)

return Service
