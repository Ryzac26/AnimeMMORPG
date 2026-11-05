--!strict
--[[
    PetPowerService (ModuleScript) -> ServerScriptService.Services.PetPowerService
    PODERES de las mascotas Épicas, Legendarias y Míticas (PetCatalog.Powers tiene los números; el poder crece con la rareza):
      Zorro (Suerte)      Olfato del Zorro   cada X s, el siguiente monstruo normal da una segunda tirada de botín
      Tanuki (Fortuna)    Lluvia de monedas  cada X monstruos, oro extra (el oro ya va directo al personaje)
      Búho (Sabiduría)    Mente clara        cada X golpes, recupera un % de la energía máxima
      Tortuga (Guardián)  Caparazón          bajo 30% de vida, escudo de % de la vida máxima (8 s)
      Tigre (Furia)       Zarpazo            cada X golpes, un golpe extra de % del daño
      Fénix               Renacer            un golpe mortal te deja con % de vida (cada varios minutos)
      Dragón              Aliento de fuego   cada X s, al atacar, daña a los enemigos cercanos
      Hada                Brisa curativa     cada X s cura a ti y al grupo cercano
      Lobo                Instinto cazador   daño extra contra jefes, mini jefes y Metin
    Las mascotas de facción (Mono, Sapo, Loro, Mariposa) no tienen poder: su efecto es la energía.
    Con el pase de Segunda Mascota (Pass_PetSlot) valen los poderes de las DOS mascotas (familias distintas).
    Se engancha a: DamageService.AddDamageListener / TrueDamage, RewardService.MobKilled, PassiveService.SetPetLethalHook.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local ItemCatalog = require(Modules.ItemCatalog)
local PetCatalog = require(Modules.PetCatalog)
local LootTables = require(Modules.LootTables)
local MobCatalog = require(Modules.MobCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local DamageService = require(Services.DamageService)
local PassiveService = require(Services.PassiveService)
local RewardService = require(Services.RewardService)
local LootService = require(Services.LootService)
local EnergyRegenService = require(Services.EnergyRegenService)
local WalletService = require(Services.WalletService)
local GearService = require(Services.GearService)
local PartyService = require(Services.PartyService)

local FloatingRemote = Net.Get("Floating")
local rng = Random.new()

type State = { ReadyAt: { [string]: number }, Count: { [string]: number } }
local states: { [Player]: State } = {}
local inPower = false -- evita que un poder dispare otros poderes (daño extra -> más daño extra)

local function stateOf(player: Player): State
	local st = states[player]
	if not st then
		st = { ReadyAt = {}, Count = {} }
		states[player] = st
	end
	return st
end

type Power = { Family: string, Cfg: any, Tier: number }

-- poderes activos del jugador (mascota 1 y, con el pase, mascota 2; dos familias iguales no se suman)
local function powersOf(player: Player): { Power }
	local out: { Power } = {}
	local seen: { [string]: boolean } = {}
	for _, slot in ipairs({ "Accesorio2", "Accesorio3" }) do
		local needPass = ItemCatalog.SlotPass[slot]
		if not needPass or player:GetAttribute(needPass) == true then
			local id = player:GetAttribute("Equip_" .. slot)
			local item: any = if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
			if item and item.Pet and not seen[item.Pet.Family] then
				local name, _, tier = PetCatalog.PowerInfo(item.Pet.Family, item.Rarity)
				if name and tier then
					seen[item.Pet.Family] = true
					table.insert(out, { Family = item.Pet.Family, Cfg = PetCatalog.Powers[item.Pet.Family], Tier = tier })
				end
			end
		end
	end
	return out
end

local function say(player: Player, text: string, color: Color3)
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		FloatingRemote:FireClient(player, root.Position + Vector3.new(0, 8, 0), text, color)
	end
end

local function ready(player: Player, key: string, cooldown: number): boolean
	local st = stateOf(player)
	local now = os.clock()
	if now < (st.ReadyAt[key] or 0) then
		return false
	end
	st.ReadyAt[key] = now + cooldown
	return true
end

-- cuenta eventos; devuelve true cada `every`
local function every(player: Player, key: string, n: number): boolean
	local st = stateOf(player)
	local c = (st.Count[key] or 0) + 1
	if c >= n then
		st.Count[key] = 0
		return true
	end
	st.Count[key] = c
	return false
end

local function aliveHumanoid(model: Model?): Humanoid?
	local h = if model then model:FindFirstChildOfClass("Humanoid") else nil
	return if h and h.Health > 0 then h else nil
end

local function fireBurst(pos: Vector3)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 70, 20))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.4, 0.9)
	pe.Speed = NumberRange.new(8, 16)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = p
	p.Parent = Workspace
	pe:Emit(40)
	Debris:AddItem(p, 1.5)
end

---------------------------------------------------------------------
-- GOLPES (Tigre, Búho, Dragón, Lobo)
---------------------------------------------------------------------
DamageService.AddDamageListener(function(mob: Model, player: Player, damage: number)
	if inPower or damage <= 0 then
		return
	end
	local powers = powersOf(player)
	local char = player.Character
	if #powers == 0 or not char then
		return
	end
	inPower = true
	local ok, err = pcall(function()
		for _, pw in ipairs(powers) do
			local family, cfg, tier = pw.Family, pw.Cfg, pw.Tier
			if family == "Furia" then
				if every(player, "Furia", cfg.Every[tier]) then
					if DamageService.TrueDamage(char, mob, damage * cfg.Value[tier]) > 0 then
						say(player, "¡Zarpazo!", Color3.fromRGB(255, 190, 80))
					end
				end
			elseif family == "Sabiduria" then
				if every(player, "Sabiduria", cfg.Every[tier]) then
					local _, maxEnergy = EnergyRegenService.GetEnergy(player)
					if maxEnergy > 0 then
						EnergyRegenService.Gain(player, maxEnergy * cfg.Value[tier])
						say(player, "¡Mente clara!", Color3.fromRGB(150, 190, 255))
					end
				end
			elseif family == "Lobo" then
				if mob:GetAttribute("Boss") == true or mob:GetAttribute("WorldBoss") == true or mob:GetAttribute("Mini") == true or mob:GetAttribute("Metin") == true then
					DamageService.TrueDamage(char, mob, damage * cfg.Value[tier])
				end
			elseif family == "Dragon" then
				local root = mob:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") and ready(player, "Dragon", cfg.Cooldown[tier]) then
					local params = OverlapParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { char }
					local seen: { [Model]: boolean } = {}
					local hits = 0
					for _, part in ipairs(Workspace:GetPartBoundsInRadius(root.Position, 12, params)) do
						local m = part:FindFirstAncestorOfClass("Model")
						if m and not seen[m] and m:GetAttribute("IsMob") == true and aliveHumanoid(m) then
							seen[m] = true
							if hits < 6 then
								hits += 1
								DamageService.TrueDamage(char, m, damage * cfg.Value[tier])
							end
						end
					end
					fireBurst(root.Position + Vector3.new(0, 2, 0))
					say(player, "¡Aliento de fuego!", Color3.fromRGB(255, 120, 50))
				end
			end
		end
	end)
	inPower = false
	if not ok then
		warn("[PetPowerService] golpe:", err)
	end
end)

---------------------------------------------------------------------
-- MUERTES (Zorro, Tanuki)
---------------------------------------------------------------------
local function isPlainMob(mobId: string): boolean
	if mobId == "WorldBoss" or string.sub(mobId, 1, 6) == "Metin_" or string.sub(mobId, 1, 5) == "Mini|" then
		return false
	end
	local def: any = (MobCatalog.ById :: any)[mobId]
	return def ~= nil and not def.Boss
end

RewardService.MobKilled:Connect(function(mobId: any, level: any, participants: any, shares: any)
	if typeof(mobId) ~= "string" or typeof(level) ~= "number" or typeof(participants) ~= "table" then
		return
	end
	for _, pl in ipairs(participants :: { Player }) do
		if pl.Parent and (typeof(shares) ~= "table" or ((shares :: any)[pl] or 1) >= 0.05) then
			for _, pw in ipairs(powersOf(pl)) do
				local family, cfg, tier = pw.Family, pw.Cfg, pw.Tier
				local ok, err = pcall(function()
					if family == "Suerte" then
						if isPlainMob(mobId) and ready(pl, "Suerte", cfg.Cooldown[tier]) then
							LootService.OnKilled(mobId, level, { pl }, { [pl] = 1 })
							say(pl, "¡Olfato del Zorro!", Color3.fromRGB(120, 235, 140))
						end
					elseif family == "Fortuna" then
						if every(pl, "Fortuna", cfg.Every[tier]) then
							local gold = LootTables.GoldFor(level, cfg.Value[tier], rng) * GearService.GoldMult(pl)
							local given = WalletService.AddGold(pl, gold, "Mascota")
							if given > 0 then
								say(pl, string.format("¡Lluvia de monedas! +%d", given), Color3.fromRGB(255, 215, 80))
							end
						end
					end
				end)
				if not ok then
					warn("[PetPowerService] muerte:", err)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- GOLPE MORTAL (Fénix)
---------------------------------------------------------------------
PassiveService.SetPetLethalHook(function(victim: Model, damage: number, hum: Humanoid): number
	local player = Players:GetPlayerFromCharacter(victim)
	if not player then
		return damage
	end
	local fenix: Power? = nil
	for _, pw in ipairs(powersOf(player)) do
		if pw.Family == "Fenix" then
			fenix = pw
		end
	end
	if not fenix or not ready(player, "Fenix", fenix.Cfg.Cooldown[fenix.Tier]) then
		return damage
	end
	local cfg, tier = fenix.Cfg, fenix.Tier
	hum.Health = math.max(1, hum.MaxHealth * cfg.Value[tier])
	victim:SetAttribute("Immune", true)
	task.delay(3, function()
		victim:SetAttribute("Immune", nil)
	end)
	say(player, "¡Renacer!", Color3.fromRGB(255, 150, 60))
	return 0
end)

---------------------------------------------------------------------
-- CADA SEGUNDO (Tortuga, Hada)
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hum = aliveHumanoid(char)
			local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
			if char and hum and root and root:IsA("BasePart") then
				for _, pw in ipairs(powersOf(player)) do
					local family, cfg, tier = pw.Family, pw.Cfg, pw.Tier
					if family == "Guardian" and hum.Health / hum.MaxHealth < 0.30 then
						if ready(player, "Guardian", cfg.Cooldown[tier]) then
							local token = os.clock()
							char:SetAttribute("ShieldPoints", math.floor(hum.MaxHealth * cfg.Value[tier]))
							char:SetAttribute("ShieldToken", token)
							task.delay(8, function()
								if char:GetAttribute("ShieldToken") == token then
									char:SetAttribute("ShieldPoints", 0)
								end
							end)
							say(player, "¡Caparazón!", Color3.fromRGB(120, 230, 150))
						end
					elseif family == "Hada" then
						-- solo se gasta si alguien del grupo cercano está herido
						local targets: { Humanoid } = {}
						local hurt = false
						for _, m in ipairs(PartyService.MembersOf(player)) do
							local mh = aliveHumanoid(m.Character)
							local mr = if m.Character then m.Character:FindFirstChild("HumanoidRootPart") else nil
							if mh and mr and mr:IsA("BasePart") and (mr.Position - root.Position).Magnitude <= 40 then
								table.insert(targets, mh)
								if mh.Health < mh.MaxHealth * 0.9 then
									hurt = true
								end
							end
						end
						if hurt and ready(player, "Hada", cfg.Cooldown[tier]) then
							for _, h in ipairs(targets) do
								h.Health = math.min(h.MaxHealth, h.Health + h.MaxHealth * cfg.Value[tier])
							end
							say(player, "¡Brisa curativa!", Color3.fromRGB(255, 170, 230))
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	states[pl] = nil
end)

return {}
