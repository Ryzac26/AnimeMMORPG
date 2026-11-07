--!strict
--[[
    InstructorService (ModuleScript) -> ServerScriptService.Services.InstructorService
    INSTRUCTOR de cada ciudad (el "Dojo del Instructor", slot 1 de ProjectBootstrapper). Cambio de clase GRATIS.
      - Pone un NPC en cada "NPCSpawnPoint" con Role = "Instructor". Nombres/colores: tabla INSTRUCTORS de aquí abajo.
      - Botón "Cambiar de clase": da el permiso (ClassSelectService.Allow) y abre la ventana ClassChangeClient.
      - Solo se puede cambiar de ROL dentro de TU facción; el servidor (ClassSelectService) valida el permiso y reaparece al jugador.
      - Remote: ClassChangeOpen (servidor -> cliente). La elección va por el remote ChooseClass de siempre.
]]
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Net = require(ServerScriptService.Services.Net)
local ClassSelect = require(ServerScriptService.Services.ClassSelectService)
local NpcBuilder = require(ServerScriptService.Services.NpcBuilder)

local OpenRemote = Net.Get("ClassChangeOpen")

local INSTRUCTORS: { [string]: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 } } = {
	Saiyan = { Name = "Maestro Roshi", Title = "Instructor de la Escuela de Combate", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(235, 130, 40), Pants = Color3.fromRGB(60, 90, 160), Hair = Color3.fromRGB(240, 240, 240) },
	Shinobi = { Name = "Iruka", Title = "Instructor de la Academia", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(60, 90, 70), Pants = Color3.fromRGB(40, 50, 90), Hair = Color3.fromRGB(70, 45, 35) },
	Pirate = { Name = "Rayleigh", Title = "Instructor de la Escuela de Haki", Skin = Color3.fromRGB(235, 190, 150), Shirt = Color3.fromRGB(235, 235, 235), Pants = Color3.fromRGB(60, 60, 75), Hair = Color3.fromRGB(235, 230, 215) },
	Shinigami = { Name = "Yamamoto", Title = "Instructor de la Academia Shino", Skin = Color3.fromRGB(235, 200, 170), Shirt = Color3.fromRGB(30, 30, 38), Pants = Color3.fromRGB(30, 30, 38), Hair = Color3.fromRGB(235, 235, 235) },
}
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}
local USE_DISTANCE = 22

local InstructorService = {}
local models: { Model } = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = name == "HumanoidRootPart"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function build(info: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 }, cf: CFrame, faction: string): Model
	local model, head = NpcBuilder.Person("Instructor", faction, cf)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffset = Vector3.new(0, 4.8, 0)
	gui.MaxDistance = 60
	gui.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Text = info.Name
	nameLabel.Parent = gui
	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromScale(0, 0.55)
	titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
	titleLabel.Font = Enum.Font.Gotham
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextStrokeTransparency = 0.5
	titleLabel.Text = "Instructor · Cambio de clase"
	titleLabel.Parent = gui
	return model
end

local function spawnInstructor(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then INSTRUCTORS[faction] else nil
	if not info or not faction or point:GetAttribute("InstructorSpawned") then
		return
	end
	point:SetAttribute("InstructorSpawned", true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local hit = Workspace:Raycast(point.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	local ground = if hit then hit.Position else point.Position
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 3.05, 0)
	local rig = build(info, CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)), faction)
	rig.Name = "Instructor_" .. faction
	rig:SetAttribute("Faction", faction)
	rig.Parent = Workspace
	local root = rig.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Cambiar de clase"
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
		ClassSelect.Allow(player)
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)
	table.insert(models, rig)
	print(string.format("[InstructorService] Instructor de %s (%s) en %s", faction, info.Name, tostring(ground)))
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Instructor" then
			task.spawn(spawnInstructor, inst)
		end
	end
end

CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Instructor" then
		task.defer(spawnInstructor, inst)
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

InstructorService.Debug = { Models = models }
return InstructorService
