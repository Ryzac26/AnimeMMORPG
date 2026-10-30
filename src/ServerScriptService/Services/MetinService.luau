--!strict
--[[
    MetinService (ModuleScript) -> ServerScriptService.Services.MetinService
    PIEDRAS METIN: durante el evento de la Arena (Workspace.EventState == "Open") aparecen piedras en los puntos con tag
    "MetinStoneSpawn" (8 en anillo). Cada piedra tiene una RAREZA (MetinCatalog) y, a medida que le bajan la vida, invoca OLEADAS
    de monstruos según su % de vida:   Común 2 oleadas · Poco común 3 · Raro 4 · Épico 5 (+élite) · Legendario 6 (+2 élites).
      - Se destruyen con los poderes normales (la piedra es un Model con Humanoid, IsMob = true, tag Targetable).
      - Al destruirla reparte XP (RewardService, según el daño de cada jugador). El BOTÍN NO está hecho: se conectará al final
        con RewardService.MobKilled (mobId "Metin_<Rareza>").
      - Al cerrarse el evento, las piedras y los monstruos que queden desaparecen.
    API: MetinService.SpawnAt(rarityId, posición) -> Model?  (pruebas: /metin <Rareza>) · MetinService.ClearAll()
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local MetinCatalog = require(ReplicatedStorage.Modules.MetinCatalog)
local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local MobService = require(Services.Mobs.MobService)
local RewardService = require(Services.RewardService)
local DamageService = require(Services.DamageService)
local ArenaService = require(Services.ArenaService)

local NotifyRemote = Net.Get("Notify")
local S = MetinCatalog.Settings
local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }

type Stone = { Model: Model, Rarity: MetinCatalog.Rarity, Marker: Instance?, NextWave: number, Minions: { Model }, Dead: boolean }
local stones: { [Model]: Stone } = {}
local lastDeath = 0
local wasOpen = false

local MetinService = {}

local function folder(): Folder
	local f = Workspace:FindFirstChild("Metins")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "Metins"
	nf.Parent = Workspace
	return nf
end

---------------------------------------------------------------------
-- MODELO DE LA PIEDRA
---------------------------------------------------------------------
local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function buildStone(r: MetinCatalog.Rarity, groundPos: Vector3, level: number): Model
	local model = Instance.new("Model")
	model.Name = string.format("Metin %s", r.Name)
	local base = CFrame.new(groundPos)

	-- raíz invisible (la usan DamageService, la selección de objetivo y los efectos)
	local root = part(model, "HumanoidRootPart", Vector3.new(6, 12, 6), base * CFrame.new(0, 7, 0), r.Color, Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CanCollide = true
	model.PrimaryPart = root

	-- base de piedra oscura con runas
	part(model, "Base", Vector3.new(2, 14, 14), base * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(45, 42, 55), Enum.Material.Slate, Enum.PartType.Cylinder)
	part(model, "Anillo", Vector3.new(0.6, 17, 17), base * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)), r.Color, Enum.Material.Neon, Enum.PartType.Cylinder).Transparency = 0.35
	for i = 1, 4 do
		local a = math.rad(i * 90 + 45)
		part(model, "Pilar", Vector3.new(2, 7, 2), base * CFrame.new(math.cos(a) * 6.5, 4.5, math.sin(a) * 6.5), Color3.fromRGB(55, 52, 68), Enum.Material.Slate)
		part(model, "Gema", Vector3.new(1.2, 1.2, 1.2), base * CFrame.new(math.cos(a) * 6.5, 8.6, math.sin(a) * 6.5), r.Color, Enum.Material.Neon, Enum.PartType.Ball)
	end

	-- cristal central (diamante = 2 bloques girados 45°); gira para siempre con SpinEmblemClient
	local crystal = Instance.new("Model")
	crystal.Name = "Cristal"
	crystal.Parent = model
	local top = base * CFrame.new(0, 10, 0)
	for i = 0, 1 do
		local c = part(crystal, "Facet", Vector3.new(6, 14, 6), top * CFrame.Angles(0, math.rad(i * 45), 0), r.Color, Enum.Material.Neon)
		c.Transparency = 0.12 + i * 0.1
	end
	part(crystal, "Nucleo", Vector3.new(3.2, 3.2, 3.2), top, Color3.new(1, 1, 1), Enum.Material.Neon, Enum.PartType.Ball)
	crystal.WorldPivot = top
	CollectionService:AddTag(crystal, "SpinEmblem")

	local light = Instance.new("PointLight")
	light.Color = r.Color
	light.Range = 45
	light.Brightness = 2
	light.Parent = root

	-- Humanoid (solo para llevar la vida; la piedra no se mueve)
	local hum = Instance.new("Humanoid")
	local hp = math.floor(GB.MobHp(level) * r.HpMult)
	hum.MaxHealth = hp
	hum.Health = hp
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model

	-- cartel con rareza, nivel y % de vida
	local bb = Instance.new("BillboardGui")
	bb.Name = "Cartel"
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(240, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 13, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.Parent = model
	local title = Instance.new("TextLabel")
	title.Name = "Titulo"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = r.Color
	title.TextStrokeTransparency = 0.2
	title.Text = string.format("METIN %s  ·  Nv.%d", string.upper(r.Name), level)
	title.Parent = bb
	local bar = Instance.new("Frame")
	bar.Name = "Barra"
	bar.Position = UDim2.fromScale(0.05, 0.62)
	bar.Size = UDim2.fromScale(0.9, 0.28)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	bar.BorderSizePixel = 0
	bar.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Vida"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = r.Color
	fill.BorderSizePixel = 0
	fill.Parent = bar

	model:SetAttribute("IsMob", true)
	model:SetAttribute("Metin", true)
	model:SetAttribute("IsMetin", true)
	model:SetAttribute("MetinRarity", r.Id)
	model:SetAttribute("Level", level)
	model:SetAttribute("MaxHp", hp)
	model:SetAttribute("Boss", false)
	CollectionService:AddTag(model, "Targetable") -- (sin tag "Mob": no es un monstruo con IA ni lo ataca el auto-farm)
	return model
end

---------------------------------------------------------------------
-- OLEADAS
---------------------------------------------------------------------
local function poolFor(r: MetinCatalog.Rarity, elite: boolean): { MobCatalog.MobDef }
	local out: { MobCatalog.MobDef } = {}
	for _, f in ipairs(FACTIONS) do
		for _, strip in ipairs(if elite then { 4 } else r.Pool) do
			for _, d in ipairs(MobCatalog.ForStrip(f, strip)) do
				if d.Boss == elite then
					table.insert(out, d)
				end
			end
		end
	end
	return out
end

local function nearestPlayer(pos: Vector3, maxDist: number): Model?
	local best: Model?, bd = nil, maxDist
	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		local h = ch and ch:FindFirstChildOfClass("Humanoid")
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if ch and h and h.Health > 0 and r and r:IsA("BasePart") then
			local d = (r.Position - pos).Magnitude
			if d < bd then
				best, bd = ch, d
			end
		end
	end
	return best
end

local function spawnWave(st: Stone, index: number)
	local wave = st.Rarity.Waves[index]
	local root = st.Model.PrimaryPart
	if not wave or not root then
		return
	end
	local ground = Vector3.new(root.Position.X, root.Position.Y - 7, root.Position.Z)
	local target = nearestPlayer(root.Position, 120)
	local function one(def: MobCatalog.MobDef, level: number)
		local a = math.random() * math.pi * 2
		local rad = S.WaveRadiusMin + math.random() * (S.WaveRadiusMax - S.WaveRadiusMin)
		local pos = ground + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
		local m = MobService.SpawnWave(def.Id, CFrame.new(pos), math.clamp(level, 1, GB.MAX_LEVEL), target)
		if m then
			m:SetAttribute("MetinWave", true)
			table.insert(st.Minions, m)
		end
	end
	local normals = poolFor(st.Rarity, false)
	local level = st.Rarity.Level
	for _ = 1, wave.Count do
		if #normals > 0 then
			one(normals[math.random(1, #normals)], level + math.random(-S.LevelSpread, S.LevelSpread))
		end
	end
	if wave.Elite then
		local elites = poolFor(st.Rarity, true)
		if #elites > 0 then
			one(elites[math.random(1, #elites)], level + S.EliteLevelBonus)
		end
	end
	NotifyRemote:FireAllClients(string.format("¡Oleada %d/%d del Metin %s!", index, #st.Rarity.Waves, st.Rarity.Name))
end

---------------------------------------------------------------------
-- CICLO DE VIDA
---------------------------------------------------------------------
local function killMinions(st: Stone)
	for _, m in ipairs(st.Minions) do
		local h = m.Parent and m:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then
			h.Health = 0 -- muere por el camino normal (limpia la IA); no da XP porque ya no hay registro de daño
		end
	end
	table.clear(st.Minions)
end

local function destroyStone(st: Stone)
	local root = st.Model.PrimaryPart
	if root then
		local fx = Instance.new("Part")
		fx.Anchored, fx.CanCollide, fx.Shape = true, false, Enum.PartType.Ball
		fx.Material, fx.Color, fx.Transparency = Enum.Material.Neon, st.Rarity.Color, 0.2
		fx.Size, fx.Position = Vector3.new(6, 6, 6), root.Position
		fx.Parent = Workspace
		game:GetService("TweenService"):Create(fx, TweenInfo.new(0.6), { Size = Vector3.new(40, 40, 40), Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(fx, 0.8)
	end
	st.Model:Destroy()
	stones[st.Model] = nil
end

local function register(model: Model, r: MetinCatalog.Rarity, marker: Instance?): Stone
	local st: Stone = { Model = model, Rarity = r, Marker = marker, NextWave = 1, Minions = {}, Dead = false }
	stones[model] = st
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local fill = model:FindFirstChild("Cartel") and (model.Cartel :: any).Barra.Vida :: Frame
	hum.HealthChanged:Connect(function(h)
		local pct = math.clamp(h / hum.MaxHealth, 0, 1)
		if fill then
			fill.Size = UDim2.fromScale(pct, 1)
		end
		while st.NextWave <= #r.Waves and pct <= r.Waves[st.NextWave].At and h > 0 do
			spawnWave(st, st.NextWave)
			st.NextWave += 1
		end
	end)
	hum.Died:Once(function()
		st.Dead = true
		lastDeath = os.clock()
		local level = model:GetAttribute("Level") :: number
		RewardService.OnMobKilled(model, "Metin_" .. r.Id, level, false, false, r.XpKills)
		DamageService.Forget(model)
		NotifyRemote:FireAllClients(string.format("¡Metin %s destruido!", r.Name))
		task.delay(0.2, function()
			destroyStone(st)
		end)
		-- los monstruos que queden desaparecen un rato después si nadie los mata
		task.delay(45, function()
			killMinions(st)
		end)
	end)
	return st
end

function MetinService.SpawnAt(rarityId: string, groundPos: Vector3, marker: Instance?): Model?
	local r = MetinCatalog.ById[rarityId]
	if not r then
		warn("[MetinService] Rareza desconocida: " .. tostring(rarityId) .. " (Comun, PocoComun, Raro, Epico, Legendario)")
		return nil
	end
	local model = buildStone(r, groundPos, r.Level)
	model.Parent = folder()
	register(model, r, marker)
	NotifyRemote:FireAllClients(string.format("¡Apareció un Metin %s (Nv.%d) en la Arena!", r.Name, r.Level))
	return model
end

function MetinService.ClearAll()
	for _, st in pairs(table.clone(stones)) do
		killMinions(st)
		destroyStone(st)
	end
end

local function freeMarker(): Instance?
	local used: { [Instance]: boolean } = {}
	for _, st in pairs(stones) do
		if st.Marker then
			used[st.Marker] = true
		end
	end
	local free: { Instance } = {}
	for _, m in ipairs(CollectionService:GetTagged("MetinStoneSpawn")) do
		if not used[m] then
			table.insert(free, m)
		end
	end
	return if #free > 0 then free[math.random(1, #free)] else nil
end

local function spawnAtMarker()
	local marker = freeMarker()
	if marker and marker:IsA("BasePart") then
		MetinService.SpawnAt(MetinCatalog.Roll().Id, marker.Position - Vector3.new(0, 3, 0), marker)
	end
end

-- Bucle lento: mantiene StonesAtOnce piedras mientras el evento está abierto y limpia al cerrarse
task.spawn(function()
	while true do
		task.wait(2)
		local open = ArenaService.IsOpen()
		if open and not wasOpen then
			for _ = 1, S.StonesAtOnce do
				spawnAtMarker()
			end
		elseif not open and wasOpen then
			MetinService.ClearAll()
		elseif open then
			local alive = 0
			for _, st in pairs(stones) do
				if st.Marker then
					alive += 1
				end
			end
			if alive < S.StonesAtOnce and os.clock() - lastDeath >= S.RespawnDelay then
				lastDeath = os.clock()
				spawnAtMarker()
			end
		end
		wasOpen = open
	end
end)

print("[MetinService] Listo: piedras Metin durante el evento de la Arena.")
return MetinService
