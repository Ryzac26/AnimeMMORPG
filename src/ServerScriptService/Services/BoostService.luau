--!strict
--[[
    BossService (ModuleScript) -> ServerScriptService.Services.BossService
    JEFE MUNDIAL: cada BOSS_INTERVAL (6 h) despierta en el centro de la Arena. Abre los puentes para que las 4 facciones lleguen,
    se ve desde los 4 fuertes (BossBeaconService) y dura como máximo BOSS_DURATION. Ataques:
      - Aplastar: marca círculos rojos bajo varios jugadores y golpea tras un instante (esquivable).
      - Onda: gran círculo rojo alrededor del jefe (hay que salir corriendo).
      - Súbditos: invoca monstruos de la franja 4.
      - Furia: con menos de 30% de vida todo es más rápido.
    XP: reparte según el daño (RewardService, jefe). El botín llega con el sistema de drops (evento ya emitido por RewardService).
    Prueba en Studio: /boss  (invoca o retira al jefe).   Todo se ajusta en CONFIG.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local BossBeacon = require(Services.BossBeaconService)
local DamageService = require(Services.DamageService)
local RewardService = require(Services.RewardService)
local ArenaService = require(Services.ArenaService)
local MobService = require(Services.Mobs.MobService)
local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local GB = require(ReplicatedStorage.Modules.GameBalance)

local NotifyRemote = Net.Get("Notify")

local CONFIG = {
	Interval = 6 * 3600, -- cada cuánto aparece
	Duration = 30 * 60, -- si nadie lo mata, se retira
	Name = "TITÁN DE LA ARENA",
	Level = 100,
	HpMult = 600, -- vida = vida de un mob de su nivel x esto
	Center = Vector3.new(0, 12, 0),
	SlamEvery = 7, SlamRadius = 16, SlamTargets = 4, SlamMult = 2.5,
	WaveEvery = 18, WaveRadius = 70, WaveMult = 3,
	SummonEvery = 30, SummonCount = 5,
	EnrageBelow = 0.30, EnrageSpeed = 0.6, -- en furia los tiempos se multiplican por esto
	WarnSeconds = { 300, 60 },
}

local BossService = {}
local model: Model? = nil
local token = 0
local openedByBoss = false

local function telegraph(center: Vector3, radius: number, life: number): Part
	local p = Instance.new("Part")
	p.Name = "BossTelegraph"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.4, radius * 2, radius * 2)
	p.CFrame = CFrame.new(center.X, CONFIG.Center.Y + 0.3, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 50, 50)
	p.Transparency = 0.55
	p:SetAttribute("TgKind", "circle")
	p:SetAttribute("TgRadius", radius)
	p:SetAttribute("TgCenter", Vector3.new(center.X, center.Y, center.Z))
	CollectionService:AddTag(p, "MobTelegraph")
	p.Parent = Workspace
	Debris:AddItem(p, life + 0.3)
	return p
end

local function playersNear(pos: Vector3, radius: number): { { Player: Player, Char: Model, Root: BasePart } }
	local out = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		local r = c and c:FindFirstChild("HumanoidRootPart")
		if c and h and h.Health > 0 and r and r:IsA("BasePart") then
			local d = Vector3.new(r.Position.X - pos.X, 0, r.Position.Z - pos.Z).Magnitude
			if d <= radius then
				table.insert(out, { Player = pl, Char = c, Root = r })
			end
		end
	end
	return out
end

local function strike(boss: Model, center: Vector3, radius: number, mult: number, delay: number)
	telegraph(center, radius, delay)
	task.delay(delay, function()
		if not boss.Parent then
			return
		end
		local fx = Instance.new("Part")
		fx.Anchored, fx.CanCollide, fx.CanQuery, fx.CanTouch = true, false, false, false
		fx.Shape = Enum.PartType.Ball
		fx.Material, fx.Color, fx.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 120, 60), 0.3
		fx.Size = Vector3.new(radius, radius, radius)
		fx.Position = center + Vector3.new(0, 4, 0)
		fx.Parent = Workspace
		game:GetService("TweenService"):Create(fx, TweenInfo.new(0.5), { Size = Vector3.new(radius * 2, radius * 1.2, radius * 2), Transparency = 1 }):Play()
		Debris:AddItem(fx, 0.6)
		for _, e in ipairs(playersNear(center, radius)) do
			DamageService.Deal(boss, e.Char, mult, { Stun = 0.6 })
		end
	end)
end

local function summon(boss: Model, count: number)
	local pool: { MobCatalog.MobDef } = {}
	for _, d in ipairs(MobCatalog.All) do
		if d.MinLevel >= 76 and not d.Boss then
			table.insert(pool, d)
		end
	end
	if #pool == 0 then
		return
	end
	local near = playersNear(CONFIG.Center, 400)
	local target: Model? = if #near > 0 then near[math.random(1, #near)].Char else nil
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local rad = 50 + math.random() * 30
		local pos = CONFIG.Center + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
		local d = pool[math.random(1, #pool)]
		MobService.SpawnWave(d.Id, CFrame.new(pos), math.clamp(d.MaxLevel, 1, GB.MAX_LEVEL), target)
	end
end

local function loop(boss: Model, hum: Humanoid, myToken: number)
	local t0 = os.clock()
	local nextSlam, nextWave, nextSummon = t0 + 5, t0 + CONFIG.WaveEvery, t0 + 12
	while model == boss and token == myToken and hum.Health > 0 do
		task.wait(0.5)
		local now = os.clock()
		if now - t0 > CONFIG.Duration then
			NotifyRemote:FireAllClients("El jefe mundial se retiró…")
			BossService.Despawn()
			return
		end
		local speed = if hum.Health / hum.MaxHealth < CONFIG.EnrageBelow then CONFIG.EnrageSpeed else 1
		local near = playersNear(CONFIG.Center, 450)
		if #near > 0 then
			if now >= nextSlam then
				nextSlam = now + CONFIG.SlamEvery * speed
				for i = #near, 2, -1 do -- baraja
					local j = math.random(1, i)
					near[i], near[j] = near[j], near[i]
				end
				for i = 1, math.min(CONFIG.SlamTargets, #near) do
					strike(boss, near[i].Root.Position, CONFIG.SlamRadius, CONFIG.SlamMult, 1.8)
				end
			end
			if now >= nextWave then
				nextWave = now + CONFIG.WaveEvery * speed
				strike(boss, CONFIG.Center, CONFIG.WaveRadius, CONFIG.WaveMult, 2.5)
				NotifyRemote:FireAllClients("¡El jefe prepara una onda! ¡Sal del círculo rojo!")
			end
			if now >= nextSummon then
				nextSummon = now + CONFIG.SummonEvery * speed
				summon(boss, CONFIG.SummonCount)
			end
		end
	end
end

function BossService.IsActive(): boolean
	return model ~= nil
end

function BossService.Despawn()
	token += 1
	local m = model
	model = nil
	if m then
		DamageService.Forget(m)
	end
	BossBeacon.Hide()
	Workspace:SetAttribute("BossActive", false)
	if openedByBoss then
		openedByBoss = false
		Workspace:SetAttribute("EventForce", "Closed")
	end
end

function BossService.Spawn()
	if model then
		return
	end
	local m = BossBeacon.Show(CONFIG.Name)
	local hp = math.floor(GB.MobHp(CONFIG.Level) * CONFIG.HpMult)
	local hum = Instance.new("Humanoid")
	hum.MaxHealth, hum.Health = hp, hp
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = m

	-- barra de vida visible desde lejos
	local sign = m:FindFirstChild("Cartel") :: Part?
	local lbl = if sign then sign:FindFirstChildWhichIsA("BillboardGui", true) else nil
	local text = if lbl then lbl:FindFirstChildOfClass("TextLabel") else nil
	hum.HealthChanged:Connect(function(h)
		if text then
			text.Text = string.format("☠ %s ☠  %d%%", CONFIG.Name, math.ceil(math.clamp(h / hum.MaxHealth, 0, 1) * 100))
		end
	end)
	if text then
		text.Text = string.format("☠ %s ☠  100%%", CONFIG.Name)
	end

	m:SetAttribute("IsMob", true)
	m:SetAttribute("Boss", true)
	m:SetAttribute("WorldBoss", true)
	m:SetAttribute("Level", CONFIG.Level)
	m:SetAttribute("MaxHp", hp)
	m:SetAttribute("HitRadius", 55) -- alcance desde su superficie (el cuerpo mide ~90 studs de ancho)
	CollectionService:AddTag(m, "Targetable") -- (sin tag "Mob": ni el auto-farm ni MobBrain lo manejan)
	model = m
	token += 1
	local myToken = token
	Workspace:SetAttribute("BossActive", true)

	if not ArenaService.IsOpen() then
		openedByBoss = true
		Workspace:SetAttribute("EventForce", "Open") -- puentes abiertos: las 4 facciones pueden llegar
	end
	NotifyRemote:FireAllClients("¡El " .. CONFIG.Name .. " despertó en la Arena! Se ve desde los 4 fuertes y los puentes están abiertos")

	hum.Died:Once(function()
		if model ~= m then
			return
		end
		RewardService.OnMobKilled(m, "WorldBoss", CONFIG.Level, true, false)
		NotifyRemote:FireAllClients("¡El " .. CONFIG.Name .. " cayó!")
		BossService.Despawn()
	end)
	task.spawn(loop, m, hum, myToken)
end

-- aparición programada, con avisos previos
task.spawn(function()
	while true do
		local left = CONFIG.Interval
		for _, w in ipairs(CONFIG.WarnSeconds) do
			if left > w then
				task.wait(left - w)
				left = w
				if not model then
					NotifyRemote:FireAllClients(string.format("El jefe mundial despierta en %d min", math.floor(w / 60 + 0.5)))
				end
			end
		end
		task.wait(left)
		if not model then
			BossService.Spawn()
		end
		task.wait(CONFIG.Duration + 5)
	end
end)

print("[BossService] Listo: jefe mundial cada 6 h en el centro de la Arena.")
return BossService
