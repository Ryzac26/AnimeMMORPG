--!strict
--[[
    MissionService (ModuleScript) -> ServerScriptService.Services.MissionService
    MISIONES DEL PABELLÓN (catálogo: ReplicatedStorage.Modules.MissionCatalog). Las hace cualquiera (gratis o VIP) con el NPC del Pabellón VIP
    de cada ciudad (NPCSlot con Role "VIP"). Progreso y marcos se guardan en el perfil (sección "Missions").
      - Report(player, tipo, cantidad): otros sistemas avisan aquí (Kill/Metin/Boss se leen solos de RewardService; Donate: GuildService;
        Enhance: HerreroService; Online: este servicio).
      - Marcos de perfil: se desbloquean por misiones completadas; el elegido se publica en el atributo "ProfileFrame" (lo dibuja PortraitKit).
      - Remotes: MissionOpen (servidor -> cliente) · MissionState · MissionAction ("State" | "Claim", id | "Frame", idMarco | "").
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MissionCatalog = require(ReplicatedStorage.Modules.MissionCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Wallet = require(Services.WalletService)
local RewardService = require(Services.RewardService)
local GearService = require(Services.GearService)

local OpenRemote = Net.Get("MissionOpen")
local StateRemote = Net.Get("MissionState")
local ActionRemote = Net.Get("MissionAction")
local NotifyRemote = Net.Get("Notify")

type Prog = { P: number, C: boolean } -- progreso, reclamada
type Data = { Day: number, Week: number, D: { [string]: Prog }, W: { [string]: Prog }, Total: number, Frame: string? }

local MissionService = {}
local data: { [Player]: Data } = {}
local dirty: { [Player]: boolean } = {}
local lastAction: { [Player]: number } = {}
local USE_DISTANCE = 24

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan", Alianza_Shinobi = "Shinobi", Flota_Pirata = "Pirate", Corte_Shinigami = "Shinigami",
}

local function dayIndex(): number
	return math.floor(os.time() / 86400)
end
local function weekIndex(): number
	return math.floor(os.time() / 604800)
end

local function levelOf(player: Player): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

-- renueva las misiones del día / la semana si cambió el periodo
local function roll(d: Data)
	local di, wi = dayIndex(), weekIndex()
	if d.Day ~= di then
		d.Day, d.D = di, {}
	end
	if d.Week ~= wi then
		d.Week, d.W = wi, {}
	end
	for _, def in ipairs(MissionCatalog.Pick(MissionCatalog.DailyPool, MissionCatalog.DAILY_COUNT, di)) do
		if not d.D[def.Id] then
			d.D[def.Id] = { P = 0, C = false }
		end
	end
	for _, def in ipairs(MissionCatalog.Pick(MissionCatalog.WeeklyPool, MissionCatalog.WEEKLY_COUNT, wi)) do
		if not d.W[def.Id] then
			d.W[def.Id] = { P = 0, C = false }
		end
	end
end

local function publishFrame(player: Player)
	local d = data[player]
	player:SetAttribute("ProfileFrame", if d and d.Frame then d.Frame else "")
	local def = if d and d.Frame then MissionCatalog.FrameById[d.Frame] else nil
	GearService.SetTemp(player, if def and def.Passive then def.Passive.Stats else nil, "Marco")
end

local function push(player: Player)
	local d = data[player]
	if not d then
		return
	end
	roll(d)
	local lv = levelOf(player)
	local function list(src: { [string]: Prog }, pool: { MissionCatalog.Def }, picks: { MissionCatalog.Def }): { any }
		local out: { any } = {}
		for _, def in ipairs(picks) do
			local p = src[def.Id]
			table.insert(out, { Id = def.Id, Text = def.Text, Goal = def.Goal, P = if p then math.min(p.P, def.Goal) else 0, Claimed = p ~= nil and p.C, Gold = MissionCatalog.Gold(def, lv) })
		end
		return out
	end
	local now = os.time()
	StateRemote:FireClient(player, {
		Daily = list(d.D, MissionCatalog.DailyPool, MissionCatalog.Pick(MissionCatalog.DailyPool, MissionCatalog.DAILY_COUNT, d.Day)),
		Weekly = list(d.W, MissionCatalog.WeeklyPool, MissionCatalog.Pick(MissionCatalog.WeeklyPool, MissionCatalog.WEEKLY_COUNT, d.Week)),
		Total = d.Total,
		Frame = d.Frame,
		DailyReset = (d.Day + 1) * 86400 - now,
		WeeklyReset = (d.Week + 1) * 604800 - now,
	})
end

function MissionService.Report(player: Player, kind: string, amount: number?)
	local d = data[player]
	local n = amount or 1
	if not d or n <= 0 then
		return
	end
	roll(d)
	local function add(src: { [string]: Prog })
		for id, p in pairs(src) do
			local def = MissionCatalog.ById[id]
			if def and def.Type == kind and not p.C and p.P < def.Goal then
				p.P = math.min(def.Goal, p.P + n)
				dirty[player] = true
			end
		end
	end
	add(d.D)
	add(d.W)
end

local function claim(player: Player, id: any)
	local d = data[player]
	local def = if typeof(id) == "string" then MissionCatalog.ById[id] else nil
	if not d or not def then
		return
	end
	roll(d)
	local p = d.D[def.Id] or d.W[def.Id]
	if not p or p.C or p.P < def.Goal then
		return
	end
	p.C = true
	local gold = MissionCatalog.Gold(def, levelOf(player))
	Wallet.AddGold(player, gold, "Misiones")
	d.Total += 1
	NotifyRemote:FireClient(player, string.format("Misión completada: %s · +%d oro", def.Text, gold))
	for _, f in ipairs(MissionCatalog.Frames) do
		if d.Total == f.Need then
			NotifyRemote:FireClient(player, "¡Desbloqueaste el " .. f.Name .. "! Equípalo con el NPC del Pabellón.")
		end
	end
	PlayerData.Save(player)
end

local function setFrame(player: Player, id: any)
	local d = data[player]
	if not d then
		return
	end
	if id == "" then
		d.Frame = nil
	elseif typeof(id) == "string" and MissionCatalog.FrameById[id] and d.Total >= MissionCatalog.FrameById[id].Need then
		d.Frame = id
	else
		return
	end
	publishFrame(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.15 then
		return
	end
	lastAction[player] = now
	if action == "Claim" then
		claim(player, a)
	elseif action == "Frame" then
		setFrame(player, a)
	end
	push(player)
end)

-- flush de progreso (como mucho 1 vez por segundo) y minutos en línea
task.spawn(function()
	local minute = 0
	while true do
		task.wait(1)
		for pl in pairs(dirty) do
			dirty[pl] = nil
			if pl.Parent then
				push(pl)
			end
		end
		minute += 1
		if minute >= 60 then
			minute = 0
			for _, pl in ipairs(Players:GetPlayers()) do
				MissionService.Report(pl, "Online", 1)
			end
		end
	end
end)

-- monstruos / Metin / jefe mundial
RewardService.MobKilled:Connect(function(mobId: string, _level: number, participants: { Player }, _shares: any)
	local isMetin = string.sub(mobId, 1, 6) == "Metin_"
	local isBoss = mobId == "WorldBoss"
	for _, pl in ipairs(participants) do
		if isMetin then
			MissionService.Report(pl, "Metin", 1)
		elseif isBoss then
			MissionService.Report(pl, "Boss", 1)
		else
			MissionService.Report(pl, "Kill", 1)
		end
	end
end)

---------------------------------------------------------------------
-- NPC del Pabellón VIP (cada ciudad)
---------------------------------------------------------------------
local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = name == "HumanoidRootPart"
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function buildSteward(cf: CFrame): Model
	local skin, robe, gold = Color3.fromRGB(240, 205, 175), Color3.fromRGB(110, 40, 70), Color3.fromRGB(240, 196, 90)
	local m = Instance.new("Model")
	local root = part(m, "HumanoidRootPart", Vector3.new(2, 2, 1), cf, robe)
	root.Transparency = 1
	m.PrimaryPart = root
	part(m, "Torso", Vector3.new(2, 2, 1), cf, robe)
	part(m, "Falda", Vector3.new(2.4, 2.4, 1.4), cf * CFrame.new(0, -2, 0), robe)
	part(m, "Faja", Vector3.new(2.1, 0.4, 1.1), cf * CFrame.new(0, -0.8, 0), gold, Enum.Material.Metal)
	local head = part(m, "Head", Vector3.new(1.3, 1.3, 1.3), cf * CFrame.new(0, 1.65, 0), skin)
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	part(m, "Sombrero", Vector3.new(1.6, 0.9, 1.6), cf * CFrame.new(0, 2.5, 0), robe)
	part(m, "SombreroOro", Vector3.new(1.7, 0.2, 1.7), cf * CFrame.new(0, 2.1, 0), gold, Enum.Material.Metal)
	part(m, "BrazoIzq", Vector3.new(1, 2, 1), cf * CFrame.new(-1.5, 0, 0), robe)
	part(m, "BrazoDer", Vector3.new(1, 2, 1), cf * CFrame.new(1.5, 0, 0), robe)
	part(m, "Pergamino", Vector3.new(0.4, 1.6, 1.2), cf * CFrame.new(1.7, 0.4, -0.9), Color3.fromRGB(245, 235, 205))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 46)
	gui.StudsOffset = Vector3.new(0, 4.2, 0)
	gui.MaxDistance = 60
	gui.Parent = head
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Size = UDim2.fromScale(1, 0.55)
	n.Font = Enum.Font.GothamBold
	n.TextScaled = true
	n.TextColor3 = gold
	n.TextStrokeTransparency = 0.4
	n.Text = "Mayordomo Imperial"
	n.Parent = gui
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0, 0.55)
	t.Size = UDim2.fromScale(1, 0.45)
	t.Font = Enum.Font.Gotham
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.5
	t.Text = "Pabellón · Misiones y marcos"
	t.Parent = gui
	return m
end

local function spawnSteward(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	if not faction or point:GetAttribute("StewardSpawned") then
		return
	end
	point:SetAttribute("StewardSpawned", true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local hit = Workspace:Raycast(point.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	local ground = if hit then hit.Position else point.Position
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 5.1, 0)
	local rig = buildSteward(CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
	rig.Name = "Mayordomo_" .. faction
	rig.Parent = Workspace
	local root = rig.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Misiones del Pabellón"
	prompt.ObjectText = "Mayordomo Imperial"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		local pr = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pr or (pr.Position - root.Position).Magnitude > USE_DISTANCE then
			return
		end
		OpenRemote:FireClient(player)
		push(player)
	end)
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "VIP" then
			task.spawn(spawnSteward, inst)
		end
	end
end
CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "VIP" then
		task.defer(spawnSteward, inst)
	end
end)
task.spawn(function()
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	scan()
	task.wait(5)
	scan()
end)

---------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Missions", function(player: Player): any?
	local d = data[player]
	if not d then
		return nil
	end
	return { Day = d.Day, Week = d.Week, D = d.D, W = d.W, Total = d.Total, Frame = d.Frame }
end)

local function cleanProg(raw: any): { [string]: Prog }
	local out: { [string]: Prog } = {}
	if typeof(raw) == "table" then
		for id, p in pairs(raw) do
			if typeof(id) == "string" and MissionCatalog.ById[id] and typeof(p) == "table" and typeof(p.P) == "number" then
				out[id] = { P = math.max(0, p.P), C = p.C == true }
			end
		end
	end
	return out
end

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = (saved :: any).Missions
	local d: Data = { Day = 0, Week = 0, D = {}, W = {}, Total = 0, Frame = nil }
	if typeof(raw) == "table" then
		d.Day = if typeof(raw.Day) == "number" then raw.Day else 0
		d.Week = if typeof(raw.Week) == "number" then raw.Week else 0
		d.D, d.W = cleanProg(raw.D), cleanProg(raw.W)
		d.Total = if typeof(raw.Total) == "number" then math.max(0, math.floor(raw.Total)) else 0
		if typeof(raw.Frame) == "string" and MissionCatalog.FrameById[raw.Frame] and d.Total >= MissionCatalog.FrameById[raw.Frame].Need then
			d.Frame = raw.Frame
		end
	end
	data[player] = d
	roll(d)
	publishFrame(player)
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
PlayerData.Releasing:Connect(function(pl: Player)
	data[pl] = nil
	dirty[pl] = nil
	lastAction[pl] = nil
end)

return MissionService
