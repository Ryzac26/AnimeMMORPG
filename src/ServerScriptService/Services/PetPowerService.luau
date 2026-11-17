--!strict
--[[
    PetPowerService (ModuleScript) -> ServerScriptService.Services.PetPowerService
    (Conserva su nombre de siempre: ahora aplica los PODERES DE LOS AYUDANTES DE COMBATE.)
    Cada ayudante equipado tiene el poder de su ROL (HelperCatalog.Powers tiene los números; crece con la rareza y se escala por su nivel):
      Tanque    Muro              bajo 35% de vida, escudo de % de tu vida máxima (8 s)
      Guerrero  Golpe de apoyo    cada X golpes, golpe extra de % del daño
      Asesino   Filo cazador      cada X golpes, tajo extra (x1,5 contra jefes, mini jefes y Metin)
      Tirador   Disparo certero   cada X s, al atacar, dispara al enemigo
      Mago      Estallido         cada X s, al atacar, daño en área alrededor del enemigo
      Curador   Brisa sanadora    cada X s, cura % de la vida máxima a ti y a tu grupo cercano
    SOLO PvE: se enganchan a DamageService.AddDamageListener (que solo avisa de golpes a monstruos). Los ayudantes nunca atacan a jugadores.
    Aviso visual: remote HelperFx (todos los clientes) -> HelperFollowClient anima al ayudante.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HelperCatalog = require(ReplicatedStorage.Modules.HelperCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local DamageService = require(Services.DamageService)
local HelperService = require(Services.HelperService)
local PartyService = require(Services.PartyService)

local FloatingRemote = Net.Get("Floating")
local FxRemote = Net.Get("HelperFx")

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

-- cuenta eventos; devuelve true cada `n`
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

-- avisa a los clientes para que el ayudante haga el ataque (slot = su ranura)
local function fx(player: Player, h: HelperService.ActiveHelper, pos: Vector3)
	FxRemote:FireAllClients(player, h.Slot, pos)
end

local ROLE_COLOR: { [string]: Color3 } = {
	Tanque = Color3.fromRGB(120, 230, 150),
	Guerrero = Color3.fromRGB(255, 190, 80),
	Asesino = Color3.fromRGB(255, 110, 130),
	Tirador = Color3.fromRGB(150, 210, 255),
	Mago = Color3.fromRGB(200, 140, 255),
	Curador = Color3.fromRGB(255, 170, 230),
}

local function isBig(mob: Model): boolean
	return mob:GetAttribute("Boss") == true or mob:GetAttribute("WorldBoss") == true or mob:GetAttribute("Mini") == true or mob:GetAttribute("Metin") == true
end

---------------------------------------------------------------------
-- GOLPES (Guerrero, Asesino, Tirador, Mago)
---------------------------------------------------------------------
DamageService.AddDamageListener(function(mob: Model, player: Player, damage: number)
	if inPower or damage <= 0 then
		return
	end
	local list = HelperService.Active(player)
	local char = player.Character
	if #list == 0 or not char then
		return
	end
	local mobRoot = mob:FindFirstChild("HumanoidRootPart")
	inPower = true
	local ok, err = pcall(function()
		for _, h in ipairs(list) do
			-- ascensión y rama de poder del ayudante cuentan aquí (HelperCatalog.PowerParams)
			local pp = HelperCatalog.PowerParams(h.Role, h.Rarity, h.Asc, h.Branch, h.Level)
			if pp then
				local value = pp.Value * h.Factor
				local name = HelperService.DisplayName(h)
				local pos = if mobRoot and mobRoot:IsA("BasePart") then mobRoot.Position else char:GetPivot().Position
				if h.Role == "Guerrero" then
					if every(player, "Guerrero", (pp.Every :: number)) and DamageService.TrueDamage(char, mob, damage * value) > 0 then
						fx(player, h, pos)
						say(player, name .. ": ¡Golpe de apoyo!", ROLE_COLOR.Guerrero)
					end
				elseif h.Role == "Asesino" then
					if every(player, "Asesino", (pp.Every :: number)) then
						local mult = if isBig(mob) then 1.5 else 1
						if DamageService.TrueDamage(char, mob, damage * value * mult) > 0 then
							fx(player, h, pos)
							say(player, name .. ": ¡Filo cazador!", ROLE_COLOR.Asesino)
						end
					end
				elseif h.Role == "Tirador" then
					if ready(player, "Tirador", (pp.Cooldown :: number)) and DamageService.TrueDamage(char, mob, damage * value) > 0 then
						fx(player, h, pos)
						say(player, name .. ": ¡Disparo certero!", ROLE_COLOR.Tirador)
					end
				elseif h.Role == "Mago" then
					if mobRoot and mobRoot:IsA("BasePart") and ready(player, "Mago", (pp.Cooldown :: number)) then
						local params = OverlapParams.new()
						params.FilterType = Enum.RaycastFilterType.Exclude
						params.FilterDescendantsInstances = { char }
						local seen: { [Model]: boolean } = {}
						local hits = 0
						for _, part in ipairs(Workspace:GetPartBoundsInRadius(mobRoot.Position, 12, params)) do
							local m = part:FindFirstAncestorOfClass("Model")
							if m and not seen[m] and m:GetAttribute("IsMob") == true and aliveHumanoid(m) then
								seen[m] = true
								if hits < 6 then
									hits += 1
									DamageService.TrueDamage(char, m, damage * value)
								end
							end
						end
						fx(player, h, mobRoot.Position)
						say(player, name .. ": ¡Estallido!", ROLE_COLOR.Mago)
					end
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
-- CADA MEDIO SEGUNDO (Tanque: Muro · Curador: Brisa sanadora)
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in ipairs(Players:GetPlayers()) do
			local list = HelperService.Active(player)
			if #list > 0 then
				local char = player.Character
				local hum = aliveHumanoid(char)
				local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
				if char and hum and root and root:IsA("BasePart") then
					for _, h in ipairs(list) do
						local pp = HelperCatalog.PowerParams(h.Role, h.Rarity, h.Asc, h.Branch, h.Level)
						if pp then
							local value = pp.Value * h.Factor
							local name = HelperService.DisplayName(h)
							if h.Role == "Tanque" and hum.Health / hum.MaxHealth < 0.35 then
								if ready(player, "Tanque", (pp.Cooldown :: number)) then
									local token = os.clock()
									char:SetAttribute("ShieldPoints", math.floor(hum.MaxHealth * value))
									char:SetAttribute("ShieldToken", token)
									task.delay(8, function()
										if char:GetAttribute("ShieldToken") == token then
											char:SetAttribute("ShieldPoints", 0)
										end
									end)
									fx(player, h, root.Position)
									say(player, name .. ": ¡Muro!", ROLE_COLOR.Tanque)
								end
							elseif h.Role == "Curador" then
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
								if hurt and ready(player, "Curador", (pp.Cooldown :: number)) then
									for _, t in ipairs(targets) do
										t.Health = math.min(t.MaxHealth, t.Health + t.MaxHealth * value)
									end
									fx(player, h, root.Position)
									say(player, name .. ": ¡Brisa sanadora!", ROLE_COLOR.Curador)
								end
							end
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
