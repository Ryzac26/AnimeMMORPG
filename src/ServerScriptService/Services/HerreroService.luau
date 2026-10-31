--!strict
--[[
    HerreroService (ModuleScript) -> ServerScriptService.Services.HerreroService
    HERRERO de cada ciudad + MEJORA +1..+9 del equipo (los números están en ReplicatedStorage.Modules.EnhanceCatalog).
      - Pone un NPC en cada "NPCSpawnPoint" con Role = "Herrero" (la Forja de cada ciudad, que crea ProjectBootstrapper).
        La facción se saca del atributo Biome del punto. Nombres/colores: tabla SMITHS de aquí abajo.
      - Acercarse y usar el botón "Hablar" abre la ventana del herrero (SmithClient).
      - El cliente pide ("Enhance", "Equip", "Arma") o ("Enhance", "Bag", 7); el SERVIDOR valida todo:
        cerca del herrero, la pieza existe y es mejorable, oro y gemas suficientes, y tira el dado.
      - Éxito: +1 al objeto. Fallo: se pierde el costo; en +8 y +9 el objeto baja 1 nivel. Nunca se rompe.
      - Remotes: SmithOpen (servidor -> cliente: abrir ventana) · SmithAction (cliente -> servidor) · SmithResult (servidor -> cliente)
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local EnhanceCatalog = require(ReplicatedStorage.Modules.EnhanceCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local Inventory = require(ServerScriptService.Services.InventoryService)
local Wallet = require(ServerScriptService.Services.WalletService)

local OpenRemote = Net.Get("SmithOpen")
local ActionRemote = Net.Get("SmithAction")
local ResultRemote = Net.Get("SmithResult")

local USE_DISTANCE = 22 -- studs máximos al herrero para mejorar
local COOLDOWN = 0.6 -- s entre intentos de un mismo jugador

-- Un herrero por facción (cambia nombre, título y colores a tu gusto). Facción = clave de BIOME_FACTION.
local SMITHS: { [string]: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3 } } = {
	Saiyan = { Name = "Dr. Brief", Title = "Ingeniero del Taller de Armaduras", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(235, 238, 245), Pants = Color3.fromRGB(70, 90, 140) },
	Shinobi = { Name = "Tenten", Title = "Maestra de la Herrería de Kunai", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(200, 60, 80), Pants = Color3.fromRGB(70, 60, 55) },
	Pirate = { Name = "Franky", Title = "Maestro de la Fragua del Astillero", Skin = Color3.fromRGB(235, 190, 150), Shirt = Color3.fromRGB(40, 150, 200), Pants = Color3.fromRGB(35, 70, 140) },
	Shinigami = { Name = "Oh-Etsu Nimaiya", Title = "Herrero de Zanpakutō de la Forja de Espadas", Skin = Color3.fromRGB(235, 200, 170), Shirt = Color3.fromRGB(240, 240, 245), Pants = Color3.fromRGB(30, 30, 40) },
}
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local HerreroService = {}
local rng = Random.new()

local smithModels: { Model } = {}
local lastTry: { [Player]: number } = {}

---------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------
local function groundPosition(point: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local hit = Workspace:Raycast(point.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	return if hit then hit.Position else point.Position
end

local function buildRig(info: { Name: string, Skin: Color3, Shirt: Color3, Pants: Color3 }): Model?
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = info.Skin, info.Skin, info.Skin
	desc.TorsoColor, desc.LeftLegColor, desc.RightLegColor = info.Shirt, info.Pants, info.Pants
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if ok and rig then
		return rig
	end
	return nil
end

local function spawnSmith(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then SMITHS[faction] else nil
	if not info or not faction then
		return
	end
	if point:GetAttribute("SmithSpawned") then
		return
	end
	point:SetAttribute("SmithSpawned", true)

	local rig = buildRig(info)
	if not rig then
		warn("[HerreroService] No se pudo crear el modelo del herrero de " .. faction)
		return
	end
	rig.Name = "Herrero_" .. faction
	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = info.Name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 40
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	local ground = groundPosition(point)
	rig.Parent = Workspace
	local _, size = rig:GetBoundingBox()
	local look = point.CFrame.LookVector
	rig:PivotTo(CFrame.lookAt(ground + Vector3.new(0, size.Y / 2 + 0.05, 0), ground + Vector3.new(0, size.Y / 2 + 0.05, 0) + Vector3.new(look.X, 0, look.Z)))
	for _, d in ipairs(rig:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	rig:SetAttribute("Smith", true)
	rig:SetAttribute("Faction", faction)

	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hablar"
	prompt.ObjectText = info.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)

	table.insert(smithModels, rig)
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Herrero" then
			task.spawn(spawnSmith, inst)
		end
	end
end

---------------------------------------------------------------------
-- MEJORA
---------------------------------------------------------------------
local function nearSmith(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, m in ipairs(smithModels) do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - root.Position).Magnitude <= USE_DISTANCE then
			return true
		end
	end
	return false
end

local function reply(player: Player, ok: boolean, text: string, plus: number?)
	ResultRemote:FireClient(player, ok, text, plus or 0)
end

local function enhance(player: Player, kind: any, key: any)
	if typeof(kind) ~= "string" or (typeof(key) ~= "string" and typeof(key) ~= "number") then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or 0) < COOLDOWN then
		return
	end
	lastTry[player] = now
	if not nearSmith(player) then
		reply(player, false, "Estás muy lejos del herrero.")
		return
	end
	if not PlayerData.IsReady(player) then
		reply(player, false, "Tu perfil aún se está cargando.")
		return
	end

	local id, plus = Inventory.GetPlus(player, kind, key)
	local item: any = if id then (ItemCatalog.Items :: any)[id] else nil
	if not id or not EnhanceCatalog.CanEnhance(item) then
		reply(player, false, "Ese objeto no se puede mejorar.")
		return
	end
	if plus >= EnhanceCatalog.MaxPlus then
		reply(player, false, "Ya está al máximo (+" .. EnhanceCatalog.MaxPlus .. ").", plus)
		return
	end
	local target = plus + 1
	local goldCost = EnhanceCatalog.GoldCost(item, target)
	local gems = EnhanceCatalog.Gems[target]
	local have = Inventory.Count(player, EnhanceCatalog.GemItem)
	local wallet = Wallet.Get(player)
	if not wallet or wallet.Gold < goldCost then
		reply(player, false, string.format("Te falta oro (necesitas %d).", goldCost), plus)
		return
	end
	if have < gems then
		reply(player, false, string.format("Te faltan Gemas de Mejora (necesitas %d, tienes %d).", gems, have), plus)
		return
	end

	-- cobrar primero (si algo falla después, el costo ya está pagado y el resultado se aplica igual)
	if not Wallet.TrySpendGold(player, goldCost, "Herrero") then
		reply(player, false, "No se pudo cobrar el oro.", plus)
		return
	end
	if not Inventory.Consume(player, EnhanceCatalog.GemItem, gems) then
		Wallet.AddGold(player, goldCost, "Herrero") -- no debería pasar: se devuelve el oro
		reply(player, false, "No se pudieron gastar las gemas.", plus)
		return
	end

	-- ¿sigue ahí la pieza? (el cliente no puede cambiar nada durante el cobro, pero se comprueba)
	local id2, plus2 = Inventory.GetPlus(player, kind, key)
	if id2 ~= id or plus2 ~= plus then
		reply(player, false, "El objeto cambió de lugar. Inténtalo de nuevo.", plus2)
		return
	end

	local name = item.Name :: string
	if rng:NextNumber() < (EnhanceCatalog.SuccessRate[target] or 0) then
		Inventory.SetPlus(player, kind, key, target)
		reply(player, true, string.format("¡Éxito! %s", EnhanceCatalog.PlusName(name, target)), target)
	else
		local drop = EnhanceCatalog.FailDrop[target] or 0
		local newPlus = math.max(0, plus - drop)
		if newPlus ~= plus then
			Inventory.SetPlus(player, kind, key, newPlus)
			reply(player, false, string.format("Falló. %s baja a +%d.", name, newPlus), newPlus)
		else
			reply(player, false, string.format("Falló. %s se mantiene en +%d.", name, plus), plus)
		end
	end
	PlayerData.Save(player) -- la mejora cuesta oro y gemas: no se pierde por un cierre inesperado
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, kind: any, key: any)
	if action == "Enhance" then
		enhance(player, kind, key)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastTry[player] = nil
end)

-- Los puntos de NPC los crea ProjectBootstrapper al arrancar; se vigilan por si aparecen después
CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Herrero" then
		task.defer(spawnSmith, inst)
	end
end)
task.spawn(function()
	scan()
	task.wait(5)
	scan() -- por si el mapa terminó de crearse un poco después
end)

-- solo para pruebas automáticas
HerreroService.Debug = { Enhance = enhance, Smiths = smithModels }

return HerreroService
