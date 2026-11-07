--!strict
--[[
    HerreroService (ModuleScript) -> ServerScriptService.Services.HerreroService
    HERRERO de cada ciudad + MEJORA +1..+9 del equipo (los números están en ReplicatedStorage.Modules.EnhanceCatalog).
      - Pone un NPC en cada "NPCSpawnPoint" con Role = "Herrero" (la Forja de cada ciudad, que crea ProjectBootstrapper).
        La facción se saca del atributo Biome del punto. Nombres/colores: tabla SMITHS de aquí abajo.
      - Acercarse y usar el botón "Hablar" abre la ventana del herrero (SmithClient).
      - El cliente pide ("Enhance", "Equip", "Arma") o ("Enhance", "Bag", 7); el SERVIDOR valida todo:
        cerca del herrero, la pieza existe y es mejorable, oro y gemas suficientes, y tira el dado.
      - Éxito: +1 al objeto. Fallo: se pierde el costo; en +7, +8 y +9 el objeto baja 1 nivel o SE ROMPE (EnhanceCatalog.BreakChance), salvo que uses un Pergamino de Protección: entonces se queda igual y se gasta el pergamino. Al forjar un +9 ganas el título "Maestro Forjador" (se ve en el Perfil) y se anuncia al servidor.
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
local NpcBuilder = require(ServerScriptService.Services.NpcBuilder)

local forged9: { [Player]: number } = {} -- cuántas piezas +9 ha forjado (da el título EnhanceCatalog.TitlePlus9)
PlayerData.RegisterSerializer("Forja", function(player: Player): any?
	local n = forged9[player]
	return if n and n > 0 then { Plus9 = n } else nil
end)
local function loadForja(player: Player)
	local data = PlayerData.WaitForData(player)
	if not data or player.Parent == nil then
		return
	end
	local raw: any = (data :: any).Forja
	if typeof(raw) == "table" and typeof(raw.Plus9) == "number" and raw.Plus9 > 0 then
		forged9[player] = math.floor(raw.Plus9)
		player:SetAttribute("Forja9", forged9[player])
		player:SetAttribute("TitleForja", EnhanceCatalog.TitlePlus9)
	end
end
Players.PlayerAdded:Connect(function(pl)
	task.spawn(loadForja, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(loadForja, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	forged9[pl] = nil
end)

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

-- Cuerpo del NPC armado con piezas simples (así se ve siempre, sin depender de avatares ni de la nube de Roblox)
local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = name == "HumanoidRootPart" or name == "Yunque"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function buildSmith(info: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3 }, cf: CFrame, faction: string): Model
	local model, head = NpcBuilder.Person("Herrero", faction, cf)
	-- yunque al lado
	local anvilCF = cf * CFrame.new(4, -2.1, -1)
	part(model, "Yunque", Vector3.new(2.6, 1.6, 2), anvilCF, Color3.fromRGB(60, 60, 68), Enum.Material.Metal)
	part(model, "YunqueBase", Vector3.new(1.6, 1.2, 1.4), anvilCF * CFrame.new(0, -1.3, 0), Color3.fromRGB(45, 45, 52), Enum.Material.Metal)

	-- cartel con el nombre
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 46)
	gui.StudsOffset = Vector3.new(0, 4.8, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	gui.Parent = head
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(255, 214, 90)
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
	titleLabel.Text = "Herrero"
	titleLabel.Parent = gui
	return model
end

local function spawnSmith(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then SMITHS[faction] else nil
	if not info or not faction then
		warn("[HerreroService] Punto de herrero con Biome desconocido: " .. tostring(biome))
		return
	end
	if point:GetAttribute("SmithSpawned") then
		return
	end
	point:SetAttribute("SmithSpawned", true)

	local ground = groundPosition(point)
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 3.05, 0) -- el centro del torso queda 5 studs sobre el piso (piernas de 2 + mitad del torso... + margen)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
	local rig = buildSmith(info, cf, faction)
	rig.Name = "Herrero_" .. faction
	rig:SetAttribute("Smith", true)
	rig:SetAttribute("Faction", faction)
	rig.Parent = Workspace

	local root = rig.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Hablar"
	prompt.ObjectText = info.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		print(string.format("[HerreroService] %s habla con %s: se abre la ventana", player.Name, info.Name))
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)

	table.insert(smithModels, rig)
	print(string.format("[HerreroService] Herrero de %s (%s) en %s", faction, info.Name, tostring(ground)))
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

local function enhance(player: Player, kind: any, key: any, useScroll: any)
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
		if target <= 5 then -- las misiones solo cuentan mejoras hasta +5 (no regalan valor a pergaminos y suerte)
			pcall(function() -- misiones del Pabellón
				require(script.Parent.MissionService).Report(player, "Enhance", 1)
			end)
		end
		reply(player, true, string.format("¡Éxito! %s", EnhanceCatalog.PlusName(name, target)), target)
		if target >= EnhanceCatalog.MaxPlus then
			forged9[player] = (forged9[player] or 0) + 1
			player:SetAttribute("Forja9", forged9[player])
			player:SetAttribute("TitleForja", EnhanceCatalog.TitlePlus9)
			-- +9: hazaña anunciada a todo el servidor
			Net.Get("Notify"):FireAllClients(string.format("★ ¡%s forjó %s al máximo!", player.DisplayName, EnhanceCatalog.PlusName(name, target)))
		end
	else
		local drop = EnhanceCatalog.FailDrop[target] or 0
		local breakChance = EnhanceCatalog.BreakChance[target] or 0
		if (drop > 0 or breakChance > 0) and useScroll == true and Inventory.Consume(player, EnhanceCatalog.ScrollItem, 1) then
			reply(player, false, string.format("Falló, pero el Pergamino de Protección salvó tu pieza: %s se mantiene en +%d.", name, plus), plus)
			PlayerData.Save(player)
			return
		end
		if breakChance > 0 and rng:NextNumber() < breakChance then
			Inventory.RemovePiece(player, kind, key)
			reply(player, false, string.format("¡%s SE ROMPIÓ! (Un Pergamino de Protección la habría salvado.)", EnhanceCatalog.PlusName(name, plus)), 0)
			PlayerData.Save(player)
			return
		end
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

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, kind: any, key: any, useScroll: any)
	if action == "Enhance" then
		enhance(player, kind, key, useScroll)
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
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	scan()
	task.wait(5)
	scan() -- por si algo apareció un poco después
end)

-- solo para pruebas automáticas
HerreroService.Debug = { Enhance = enhance, Smiths = smithModels }

return HerreroService
