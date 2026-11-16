--!strict
--[[
    ReclutadorService (ModuleScript) -> ServerScriptService.Services.ReclutadorService
    RECLUTADOR de ayudantes de combate: un NPC al lado del Instructor de cada ciudad (se busca el punto "NPCSlot" con Role = "Instructor",
    igual que InstructorService, y se pone a su lado con un cartel de reclutamiento). Interactuar abre la ventana de reclutamiento (RecruitClient):
    cupones, tiradas x1 / x10, probabilidades en % y canje de mascotas viejas.
      - Remote: RecruitOpen (servidor -> cliente): nombre del reclutador y facción.
      - El servidor solo acepta reclutar si abriste la ventana cerca del reclutador (HelperService.AllowRecruit).
    Si un día quieres moverlo, cambia OFFSET (a la derecha del instructor, en studs).
]]
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Net = require(ServerScriptService.Services.Net)
local NpcBuilder = require(ServerScriptService.Services.NpcBuilder)
local HelperService = require(ServerScriptService.Services.HelperService)

local OpenRemote = Net.Get("RecruitOpen")

local OFFSET = Vector3.new(9, 0, 1)
local USE_DISTANCE = 22

local RECRUITERS: { [string]: { Name: string, Title: string, Accent: Color3 } } = {
	Saiyan = { Name = "Capitán Brum", Title = "Reclutador de la Élite", Accent = Color3.fromRGB(255, 190, 70) },
	Shinobi = { Name = "Suzu", Title = "Reclutadora del Sigilo", Accent = Color3.fromRGB(150, 220, 170) },
	Pirate = { Name = "Contramaestre Dax", Title = "Reclutador de los Navegantes", Accent = Color3.fromRGB(110, 190, 245) },
	Shinigami = { Name = "Guía Mizuki", Title = "Reclutadora del Espíritu", Accent = Color3.fromRGB(190, 150, 255) },
}
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local ReclutadorService = {}
local models: { Model } = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function label(parent: Instance, text: string, color: Color3, y: number, w: number, h: number, size: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(w, h)
	gui.StudsOffset = Vector3.new(0, y, 0)
	gui.MaxDistance = 70
	gui.Parent = parent
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = gui
end

local function spawnRecruiter(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then RECRUITERS[faction] else nil
	if not info or not faction or point:GetAttribute("RecruiterSpawned") then
		return
	end
	point:SetAttribute("RecruiterSpawned", true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local want = point.CFrame:PointToWorldSpace(OFFSET)
	local hit = Workspace:Raycast(want + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
	local ground = if hit then hit.Position else Vector3.new(want.X, point.Position.Y - 1, want.Z)
	-- anti-duplicado
	for _, other in ipairs(models) do
		if other.PrimaryPart and (other.PrimaryPart.Position - ground).Magnitude < 10 then
			return
		end
	end
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 3.05, 0)
	local rig = NpcBuilder.Person("Reclutador", faction, CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)))
	rig.Name = "Reclutador_" .. faction
	rig:SetAttribute("Faction", faction)

	-- puesto: tarima baja y cartel con estandarte del color de la facción (modelo aparte: así NpcIdleClient solo anima al personaje)
	local stall = Instance.new("Model")
	stall.Name = "PuestoReclutador_" .. faction
	local base = CFrame.new(ground) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
	part(stall, "Tarima", Vector3.new(7, 0.5, 5), base * CFrame.new(0, 0.25, 0), Color3.fromRGB(70, 62, 56), Enum.Material.WoodPlanks)
	part(stall, "Poste", Vector3.new(0.5, 9, 0.5), base * CFrame.new(-3.2, 4.5, -1.6), Color3.fromRGB(86, 62, 44), Enum.Material.Wood)
	local flag = part(stall, "Estandarte", Vector3.new(0.2, 4.2, 2.6), base * CFrame.new(-3.2, 6.6, -0.2), info.Accent, Enum.Material.Fabric)
	part(stall, "EstandarteBorde", Vector3.new(0.25, 0.4, 2.8), base * CFrame.new(-3.2, 8.6, -0.2), Color3.fromRGB(240, 236, 222), Enum.Material.Metal)
	local ticket = part(stall, "MesaCupones", Vector3.new(2.6, 1.6, 1.4), base * CFrame.new(2.6, 1.2, 0.4), Color3.fromRGB(110, 78, 52), Enum.Material.Wood)
	part(stall, "Cupon1", Vector3.new(1.0, 0.08, 0.6), base * CFrame.new(2.2, 2.05, 0.3) * CFrame.Angles(0, math.rad(15), 0), Color3.fromRGB(245, 235, 200), Enum.Material.SmoothPlastic)
	part(stall, "Cupon2", Vector3.new(1.0, 0.08, 0.6), base * CFrame.new(3.0, 2.1, 0.5) * CFrame.Angles(0, math.rad(-25), 0), info.Accent, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = info.Accent
	light.Range = 14
	light.Brightness = 1.2
	light.Parent = flag
	label(flag, "RECLUTAMIENTO", info.Accent, 3.6, 240, 28, 18)

	local head = rig:FindFirstChild("Head", true)
	local nameTarget: Instance = if head then head else ticket
	label(nameTarget, info.Name, Color3.fromRGB(255, 235, 170), 3.2, 240, 24, 17)

	stall.Parent = Workspace
	rig.Parent = Workspace
	local root = rig.PrimaryPart or (rig:FindFirstChildWhichIsA("BasePart") :: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Reclutar ayudantes"
	prompt.ObjectText = info.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		if player:GetAttribute("ClassChosen") ~= true then
			return
		end
		local char = player.Character
		local pr = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pr or (pr.Position - root.Position).Magnitude > USE_DISTANCE then
			return
		end
		HelperService.AllowRecruit(player, root.Position)
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)
	table.insert(models, rig)
	print(string.format("[ReclutadorService] Reclutador de %s (%s) en %s", faction, info.Name, tostring(ground)))
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Instructor" then
			task.spawn(spawnRecruiter, inst)
		end
	end
end

CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst: Instance)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Instructor" then
		task.defer(spawnRecruiter, inst)
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

ReclutadorService.Debug = { Models = models }
return ReclutadorService
