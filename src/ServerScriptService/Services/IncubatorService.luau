--!strict
--[[
    IncubatorService (ModuleScript) -> ServerScriptService.Services.IncubatorService
    INCUBADORA de cada ciudad: una cúpula de cristal con luz junto al Mercader (se busca el punto "NPCSlot" con Role = "Mercader"
    y se pone al lado). Interactuar abre la ventana de la incubadora en el cliente (MountClient): ahí se ven tus huevos,
    se inicia la incubación, se acelera y se abre el huevo cuando termina. No hace falta quedarse en la franja.
    Si un día quieres moverla, cambia OFFSET (a la derecha del mercader, en studs).
]]
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local MountService = require(ServerScriptService.Services.MountService)

local OFFSET = Vector3.new(11, 0, 2)

local FACTION_COLOR: { [string]: Color3 } = {
	Imperio_Saiyan = Color3.fromRGB(255, 160, 50),
	Alianza_Shinobi = Color3.fromRGB(120, 200, 100),
	Flota_Pirata = Color3.fromRGB(80, 170, 235),
	Corte_Shinigami = Color3.fromRGB(170, 130, 255),
}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function build(point: BasePart)
	if point:GetAttribute("IncubatorSpawned") then
		return
	end
	point:SetAttribute("IncubatorSpawned", true)
	local biome = point:GetAttribute("Biome")
	local accent = (typeof(biome) == "string" and FACTION_COLOR[biome]) or Color3.fromRGB(255, 190, 70)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local want = point.CFrame:PointToWorldSpace(OFFSET)
	local hit = Workspace:Raycast(want + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
	local ground = if hit then hit.Position else Vector3.new(want.X, point.Position.Y - 1, want.Z)
	local base = CFrame.new(ground)

	-- anti-duplicado: si ya hay una incubadora en este punto (dos Mercader en el mismo sitio o mapa construido dos veces), no poner otra
	for _, other in ipairs(Workspace:GetChildren()) do
		if other:IsA("Model") and other.Name == "Incubadora" and other.PrimaryPart then
			local d = other.PrimaryPart.Position - ground
			if Vector3.new(d.X, 0, d.Z).Magnitude < 12 then
				return
			end
		end
	end

	local model = Instance.new("Model")
	model.Name = "Incubadora"
	part(model, "Base", Vector3.new(1.2, 7, 7), base * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 66, 76), Enum.Material.Slate, Enum.PartType.Cylinder)
	part(model, "Aro", Vector3.new(0.5, 7.4, 7.4), base * CFrame.new(0, 1.25, 0) * CFrame.Angles(0, 0, math.rad(90)), accent, Enum.Material.Metal, Enum.PartType.Cylinder)
	local nest = part(model, "Nido", Vector3.new(0.9, 4.6, 4.6), base * CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 110, 60), Enum.Material.Fabric, Enum.PartType.Cylinder)
	local egg = part(model, "Huevo", Vector3.new(2.2, 3, 2.2), base * CFrame.new(0, 3.5, 0), accent, Enum.Material.Neon, Enum.PartType.Ball)
	egg.Transparency = 0.25
	local dome = part(model, "Cupula", Vector3.new(6.4, 6.4, 6.4), base * CFrame.new(0, 3.6, 0), Color3.fromRGB(190, 225, 255), Enum.Material.Glass, Enum.PartType.Ball)
	dome.Transparency = 0.7
	dome.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = accent
	light.Range = 18
	light.Brightness = 1.4
	light.Parent = egg

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(180, 28)
	gui.StudsOffset = Vector3.new(0, 7.4, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 90
	gui.Parent = nest
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "INCUBADORA"
	lbl.TextColor3 = accent
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 18
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = gui

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Abrir incubadora"
	pp.ObjectText = "Huevos de montura"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 14
	pp.RequiresLineOfSight = false
	pp.Parent = nest
	pp.Triggered:Connect(function(pl)
		MountService.OpenIncubator(pl)
	end)

	model.PrimaryPart = nest
	model.Parent = Workspace
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Mercader" then
			task.spawn(build, inst)
		end
	end
end

CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Mercader" then
		task.defer(build, inst)
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

return {}
