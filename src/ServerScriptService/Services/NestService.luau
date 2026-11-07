--!strict
--[[
    NestService (ModuleScript) -> ServerScriptService.Services.NestService
    NIDOS SALVAJES de las franjas (los coloca PveZoneService.buildLane; cantidad por franja en MountCatalog.Nest.PerStrip).
      - Cada nido está VIGILADO por un grupo de monstruos de la franja que reaparecen (MountCatalog.Nest.Guards / GuardRespawn).
      - El huevo se toma con [E] solo si NO hay enemigos vivos cerca (ClearRadius). Es el "huevo del día": si ya tomaste el de hoy
        (de un nido o de un mini jefe) avisa cuánto falta. El huevo es del nivel de la franja (Común..Legendario).
      - El nido no se vacía: sigue ahí; lo limita el huevo diario por jugador.
      - Los guardianes solo existen con jugadores cerca (se crean a <230 studs y se retiran a >420 studs si están ilesos).
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MountCatalog = require(ReplicatedStorage.Modules.MountCatalog)
local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local MobService = require(Services.Mobs.MobService)
local MountService = require(Services.MountService)

local NotifyRemote = Net.Get("Notify")
local rng = Random.new()

type Nest = {
	Pos: Vector3,
	Strip: number,
	Defs: { MobCatalog.MobDef },
	Guards: { Model? },
	RespawnAt: { number },
	Folder: Folder,
}
local nests: { Nest } = {}

local NestService = {}

local function aliveMobNear(pos: Vector3, radius: number): boolean
	for _, m in ipairs(CollectionService:GetTagged("Mob")) do
		if m:IsA("Model") and m.Parent then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local root = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and root and root:IsA("BasePart") then
				if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= radius then
					return true
				end
			end
		end
	end
	return false
end

local function playerWithin(pos: Vector3, dist: number): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - pos).Magnitude <= dist then
			return true
		end
	end
	return false
end

local function fmt(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%02d:%02d:%02d", sec // 3600, (sec % 3600) // 60, sec % 60)
end

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide == true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local EGG_COLOR = { Color3.fromRGB(215, 215, 205), Color3.fromRGB(80, 160, 255), Color3.fromRGB(180, 90, 255), Color3.fromRGB(255, 170, 40) }

function NestService.Build(root: Folder, pos: Vector3, strip: number, index: number, defs: { MobCatalog.MobDef })
	if MountCatalog.Enabled == false then
		return -- monturas "próximamente": sin nidos ni guardianes
	end
	strip = math.clamp(strip, 1, 4)
	local f = Instance.new("Folder")
	f.Name = string.format("Nido_%d_%d", strip, index)
	f.Parent = root
	local base = CFrame.new(pos)
	local straw = Color3.fromRGB(176, 140, 76)
	mk(f, "Monticulo", Vector3.new(0.8, 12, 12), base * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(84, 62, 38), Enum.Material.Ground, Enum.PartType.Cylinder, false)
	for k = 1, 10 do -- anillo de paja
		local a = k * math.pi * 2 / 10
		mk(f, "Paja", Vector3.new(1, 0.7, 3.6), base * CFrame.new(math.cos(a) * 5, 0.9, math.sin(a) * 5) * CFrame.Angles(0, -a, 0), straw, Enum.Material.Fabric, nil, false)
	end
	local tint = EGG_COLOR[strip]
	local main = mk(f, "Huevo", Vector3.new(2.6, 3.4, 2.6), base * CFrame.new(0, 2.4, 0), tint, Enum.Material.SmoothPlastic, Enum.PartType.Ball, true)
	mk(f, "HuevoB", Vector3.new(2, 2.7, 2), base * CFrame.new(2.6, 1.9, 1.4), tint:Lerp(Color3.new(1, 1, 1), 0.2), Enum.Material.SmoothPlastic, Enum.PartType.Ball, false)
	mk(f, "HuevoC", Vector3.new(1.8, 2.4, 1.8), base * CFrame.new(-2.4, 1.7, -1.6), tint:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.SmoothPlastic, Enum.PartType.Ball, false)
	local light = Instance.new("PointLight")
	light.Color = tint
	light.Range = 14
	light.Brightness = 0.9
	light.Parent = main

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(190, 26)
	gui.StudsOffset = Vector3.new(0, 4.6, 0)
	gui.MaxDistance = 110
	gui.Parent = main
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "NIDO SALVAJE · FRANJA " .. strip
	lbl.TextColor3 = Color3.fromRGB(255, 225, 150)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 15
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = gui

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Tomar huevo"
	pp.ObjectText = "Nido salvaje · Franja " .. strip
	pp.HoldDuration = 1.5
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.MaxActivationDistance = MountCatalog.Nest.ClaimDistance
	pp.RequiresLineOfSight = false
	pp.Parent = main
	pp.Triggered:Connect(function(pl: Player)
		local char = pl.Character
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if not r or not r:IsA("BasePart") or (r.Position - pos).Magnitude > MountCatalog.Nest.ClaimDistance + 8 then
			return
		end
		if aliveMobNear(pos, MountCatalog.Nest.ClearRadius) then
			NotifyRemote:FireClient(pl, "Nido salvaje: hay enemigos vivos cerca. Elimina a los guardianes primero")
			return
		end
		if not MountService.DailyAvailable(pl) then
			local reset = pl:GetAttribute("EggResetAt")
			local left = if typeof(reset) == "number" then reset - os.time() else 0
			NotifyRemote:FireClient(pl, "Ya tomaste tu huevo de hoy. Vuelve a estar disponible en " .. fmt(left))
			return
		end
		MountService.TryDailyEgg(pl, "Nido", strip)
	end)

	local guards: { Model? } = {}
	local respawn: { number } = {}
	for i = 1, MountCatalog.Nest.Guards[strip] do
		guards[i] = nil
		respawn[i] = 0
	end
	table.insert(nests, { Pos = pos, Strip = strip, Defs = defs, Guards = guards, RespawnAt = respawn, Folder = f })
end

function NestService.Clear()
	for _, n in ipairs(nests) do
		for _, g in ipairs(n.Guards) do
			if g and g.Parent then
				MobService.Despawn(g)
			end
		end
	end
	table.clear(nests)
end

local function step()
	local now = os.clock()
	for _, n in ipairs(nests) do
		local near = playerWithin(n.Pos, 230)
		for i = 1, #n.RespawnAt do
			local g = n.Guards[i]
			if g then
				local hum = g.Parent and g:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 then
					n.Guards[i] = nil
					n.RespawnAt[i] = now + MountCatalog.Nest.GuardRespawn
				elseif hum.Health >= hum.MaxHealth and not playerWithin(n.Pos, 420) then
					MobService.Despawn(g)
					n.Guards[i] = nil
					n.RespawnAt[i] = 0
				end
			elseif near and now >= n.RespawnAt[i] and #n.Defs > 0 then
				local def = n.Defs[rng:NextInteger(1, #n.Defs)]
				local a = rng:NextNumber() * math.pi * 2
				local d = MountCatalog.Nest.GuardRadius * (0.5 + rng:NextNumber() * 0.5)
				local p = n.Pos + Vector3.new(math.cos(a) * d, 3, math.sin(a) * d)
				n.Guards[i] = MobService.SpawnAt(def.Id, CFrame.new(p), nil)
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(3)
		local ok, err = pcall(step)
		if not ok then
			warn("[NestService] " .. tostring(err))
		end
	end
end)

return NestService
