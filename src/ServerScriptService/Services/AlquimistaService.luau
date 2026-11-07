--!strict
--[[
    AlquimistaService (ModuleScript) -> ServerScriptService.Services.AlquimistaService
    ALQUIMISTA de cada ciudad (el "Laboratorio del Alquimista", slot 3 de ProjectBootstrapper). Dos servicios:
      FABRICAR pociones (Vida/Energía en 3 grados) y ELIXIRES (efecto temporal de 30 min, ver ElixirService) con recursos + material + oro. Cantidades: 1, 10, 50, 100 o Máx.
      DESMONTAR equipo de la mochila (sin candado) -> materiales de su franja + fragmentos (+ Gema de vez en cuando).
    Recetas y rendimientos: ReplicatedStorage.Modules.AlchemyCatalog.
    - Pone un NPC en cada "NPCSpawnPoint" con Role = "Alquimista". Botón "Hablar" abre la ventana (AlquimiaClient).
    - Remotes: AlquimiaOpen (servidor -> cliente) · AlquimiaAction (cliente -> servidor) · AlquimiaResult (servidor -> cliente)
        AlquimiaAction: ("Craft", idReceta, cantidad | "max") · ("Drink", idElixir) · ("Dismantle", casillaMochila) · ("DismantleRarity", {rarezas}, incluirMejoradas) · ("DismantleCommons")
    - El SERVIDOR valida todo: cerca del alquimista, perfil cargado, recursos y oro. Si algo no cabe en la mochila se devuelve todo.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AlchemyCatalog = require(ReplicatedStorage.Modules.AlchemyCatalog)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local Inventory = require(ServerScriptService.Services.InventoryService)
local Wallet = require(ServerScriptService.Services.WalletService)
local ElixirService = require(ServerScriptService.Services.ElixirService)
local NpcBuilder = require(ServerScriptService.Services.NpcBuilder)

local OpenRemote = Net.Get("AlquimiaOpen")
local ActionRemote = Net.Get("AlquimiaAction")
local ResultRemote = Net.Get("AlquimiaResult")

local USE_DISTANCE = 22
local COOLDOWN = 0.25
local rng = Random.new()

local ALCHEMISTS: { [string]: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 } } = {
	Saiyan = { Name = "Bulma", Title = "Alquimista del Laboratorio Cápsula", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(245, 245, 245), Pants = Color3.fromRGB(70, 110, 170), Hair = Color3.fromRGB(110, 200, 200) },
	Shinobi = { Name = "Shizune", Title = "Alquimista del Hospital Ninja", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(40, 45, 60), Pants = Color3.fromRGB(40, 45, 60), Hair = Color3.fromRGB(40, 35, 40) },
	Pirate = { Name = "Chopper", Title = "Alquimista de la Enfermería", Skin = Color3.fromRGB(215, 170, 120), Shirt = Color3.fromRGB(235, 90, 110), Pants = Color3.fromRGB(150, 60, 70), Hair = Color3.fromRGB(110, 70, 50) },
	Shinigami = { Name = "Mayuri", Title = "Alquimista del Instituto de Investigación", Skin = Color3.fromRGB(235, 225, 200), Shirt = Color3.fromRGB(235, 235, 235), Pants = Color3.fromRGB(35, 35, 45), Hair = Color3.fromRGB(240, 220, 90) },
}
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local AlquimistaService = {}
local models: { Model } = {}
local lastTry: { [Player]: number } = {}
local stations: { BasePart } = {} -- otros puestos de alquimia (la olla de los campamentos, PveZoneService)

-- Registra una parte (la olla de un campamento) como puesto de alquimia: quien esté cerca puede fabricar y desmontar
function AlquimistaService.RegisterStation(part: BasePart)
	table.insert(stations, part)
end

-- Abre la ventana del alquimista para un jugador (misma ventana que el NPC)
function AlquimistaService.OpenAt(player: Player, name: string, title: string, faction: string)
	OpenRemote:FireClient(player, name, title, faction)
end

---------------------------------------------------------------------
-- NPC
---------------------------------------------------------------------
local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = name == "HumanoidRootPart" or name == "Caldero"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function build(info: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 }, cf: CFrame, faction: string): Model
	local model, head = NpcBuilder.Person("Alquimista", faction, cf)
	-- caldero con poción burbujeante + frascos
	local potCF = cf * CFrame.new(-4, -1.9, -1)
	part(model, "Caldero", Vector3.new(2.6, 2.2, 2.6), potCF, Color3.fromRGB(40, 40, 48), Enum.Material.Metal)
	local brew = part(model, "Brebaje", Vector3.new(2.2, 0.3, 2.2), potCF * CFrame.new(0, 1.1, 0), Color3.fromRGB(120, 255, 150), Enum.Material.Neon)
	brew.CanCollide = false

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
	nameLabel.TextColor3 = Color3.fromRGB(130, 255, 170)
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
	titleLabel.Text = "Alquimista · Pociones y desmontar"
	titleLabel.Parent = gui
	return model
end

local function spawnAlchemist(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then ALCHEMISTS[faction] else nil
	if not info or not faction or point:GetAttribute("AlchemistSpawned") then
		return
	end
	point:SetAttribute("AlchemistSpawned", true)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local hit = Workspace:Raycast(point.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	local ground = if hit then hit.Position else point.Position
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 3.05, 0)
	local rig = build(info, CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z)), faction)
	rig.Name = "Alquimista_" .. faction
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
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)
	table.insert(models, rig)
	print(string.format("[AlquimistaService] Alquimista de %s (%s) en %s", faction, info.Name, tostring(ground)))
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Alquimista" then
			task.spawn(spawnAlchemist, inst)
		end
	end
end

---------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------
local function nearAlchemist(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, m in ipairs(models) do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - root.Position).Magnitude <= USE_DISTANCE then
			return true
		end
	end
	for _, s in ipairs(stations) do
		if s.Parent and (s.Position - root.Position).Magnitude <= USE_DISTANCE then
			return true
		end
	end
	return false
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

local function finite(n: any): boolean
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function goldOf(player: Player): number
	local g = player:GetAttribute("Gold")
	return if typeof(g) == "number" then g else 0
end

local function nameOf(id: string): string
	local it: any = (ItemCatalog.Items :: any)[id]
	return if it then it.Name else id
end

---------------------------------------------------------------------
-- FABRICAR
---------------------------------------------------------------------
local function craft(player: Player, recipeId: any, qty: any)
	local recipe = if typeof(recipeId) == "string" then AlchemyCatalog.ById[recipeId] else nil
	if not recipe then
		return
	end
	local have = function(id: string): number
		return Inventory.Count(player, id)
	end
	local most = AlchemyCatalog.MaxCraft(recipe, have, goldOf(player))
	local n: number
	if qty == "max" then
		n = most
	elseif finite(qty) then
		n = math.clamp(math.floor(qty), 1, AlchemyCatalog.MAX_QTY)
	else
		return
	end
	local item: any = (ItemCatalog.Items :: any)[recipe.Id]
	if not AlchemyCatalog.CanCraft(recipe, player:GetAttribute("Pass_Belt") == true) then
		reply(player, false, "Necesitas el pase Cinturón de Pociones (Tienda > Pases) para fabricar " .. item.Name .. ".")
		return
	end
	if n < 1 or most < 1 then
		reply(player, false, "Te faltan materiales u oro para fabricar " .. nameOf(recipe.Id) .. ".")
		return
	end
	if n > most then
		reply(player, false, string.format("Solo alcanza para %d (pediste %d).", most, n))
		return
	end
	local gold = recipe.Gold * n
	if gold > 0 and not Wallet.TrySpendGold(player, gold, "Alquimia") then
		reply(player, false, string.format("Te falta oro (necesitas %d).", gold))
		return
	end
	local spent: { { string | number } } = {}
	local failed = false
	for mat, need in pairs(recipe.Cost) do
		if Inventory.Consume(player, mat, need * n) then
			table.insert(spent, { mat, need * n })
		else
			failed = true
			break
		end
	end
	local made = n * recipe.Yield
	if failed or not Inventory.Add(player, recipe.Id, made) then
		for _, s in ipairs(spent) do
			Inventory.Add(player, s[1] :: string, s[2] :: number)
		end
		if gold > 0 then
			Wallet.AddGold(player, gold, "Alquimia")
		end
		reply(player, false, if failed then "No se pudo fabricar." else "Mochila llena: libera espacio.")
		return
	end
	reply(player, true, string.format("Fabricaste %s x%d.", item.Name, made))
	PlayerData.Save(player)
end

---------------------------------------------------------------------
-- DESMONTAR
---------------------------------------------------------------------
-- ¿Es una pieza de equipo que se puede desmontar? (no mascotas; solo equipo, sin candado)
local function dismantlable(stack: any): any?
	local item: any = (ItemCatalog.Items :: any)[stack.Id]
	if item and not item.Pet and (item.Gear or item.Slot) and not stack.Locked then
		return item
	end
	return nil
end

-- Sortea lo que da UNA pieza. Suma en `out` (id -> cantidad).
local function rollYield(item: any, plus: number, out: { [string]: number })
	local req = if typeof(item.ReqLevel) == "number" then item.ReqLevel else 1
	local matId, mMin, mMax, frag, gemChance = AlchemyCatalog.DismantleYield(req, item.Rarity, plus)
	out[matId] = (out[matId] or 0) + rng:NextInteger(mMin, mMax)
	if frag > 0 then
		out.Mat_FragArmadura = (out.Mat_FragArmadura or 0) + frag
	end
	if gemChance > 0 and rng:NextNumber() < gemChance then
		out.Mat_Gema = (out.Mat_Gema or 0) + 1
	end
end

local function describe(yields: { [string]: number }): string
	local ids: { string } = {}
	for id in pairs(yields) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local parts: { string } = {}
	for _, id in ipairs(ids) do
		table.insert(parts, string.format("%d %s", yields[id], nameOf(id)))
	end
	return table.concat(parts, ", ")
end

-- Entrega los materiales; si no caben, deshace lo ya entregado y devuelve false.
local function giveAll(player: Player, yields: { [string]: number }): boolean
	local given: { { string | number } } = {}
	for id, n in pairs(yields) do
		if n > 0 then
			if Inventory.Add(player, id, n) then
				table.insert(given, { id, n })
			else
				for _, g in ipairs(given) do
					Inventory.Consume(player, g[1] :: string, g[2] :: number)
				end
				return false
			end
		end
	end
	return true
end

local function dismantle(player: Player, index: any)
	if not finite(index) then
		return
	end
	local st = Inventory.Get(player)
	local slot = math.floor(index)
	local stack = if st then st.Bag[slot] else nil
	if not stack then
		reply(player, false, "Ese objeto ya no está en tu mochila.")
		return
	end
	if stack.Locked then
		reply(player, false, "Está bloqueado 🔒: quítale el candado en la mochila para desmontarlo.")
		return
	end
	local item = dismantlable(stack)
	if not item then
		reply(player, false, "Eso no se puede desmontar (solo equipo).")
		return
	end
	local yields: { [string]: number } = {}
	rollYield(item, stack.Plus or 0, yields)
	if not giveAll(player, yields) then
		reply(player, false, "Mochila llena: libera espacio.")
		return
	end
	local id, _, taken = Inventory.RemoveSlot(player, slot, 1)
	if not id or taken <= 0 then
		for mat, n in pairs(yields) do
			Inventory.Consume(player, mat, n)
		end
		reply(player, false, "No se pudo desmontar.")
		return
	end
	reply(player, true, string.format("Desmontaste %s: %s.", item.Name, describe(yields)))
	PlayerData.Save(player)
end

local VALID_RARITY = { Comun = true, Raro = true, Epico = true, Legendario = true, Mitico = true }
-- Lista de rarezas que manda el cliente -> conjunto validado (ignora basura)
local function raritySet(list: any): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if typeof(list) == "table" then
		for i = 1, math.min(#list, 8) do
			local r = (list :: any)[i]
			if typeof(r) == "string" and VALID_RARITY[r] then
				set[r] = true
			end
		end
	end
	return set
end

-- Desmonta de una vez TODO el equipo de las rarezas elegidas (sin candado; las piezas mejoradas solo si includePlus)
local function dismantleRarities(player: Player, rarities: any, includePlus: any)
	local set = raritySet(rarities)
	if next(set) == nil then
		reply(player, false, "Elige al menos una rareza.")
		return
	end
	local st = Inventory.Get(player)
	if not st then
		return
	end
	local withPlus = includePlus == true
	local slots: { number } = {}
	for i, stack in pairs(st.Bag) do
		local item = dismantlable(stack)
		if item and set[item.Rarity] and (withPlus or (stack.Plus or 0) == 0) then
			table.insert(slots, i)
		end
	end
	local yields: { [string]: number } = {}
	local pieces = 0
	for _, i in ipairs(slots) do
		local stack = st.Bag[i]
		local item = if stack then dismantlable(stack) else nil
		if stack and item then
			for _ = 1, stack.Count do
				rollYield(item, stack.Plus or 0, yields)
				pieces += 1
			end
		end
	end
	if pieces == 0 then
		reply(player, false, "No tienes equipo de esa rareza para desmontar.")
		return
	end
	if not giveAll(player, yields) then
		reply(player, false, "Mochila llena: libera espacio.")
		return
	end
	for _, i in ipairs(slots) do
		local stack = st.Bag[i]
		if stack then
			Inventory.RemoveSlot(player, i, stack.Count)
		end
	end
	reply(player, true, string.format("Desmontaste %d piezas: %s.", pieces, describe(yields)))
	PlayerData.Save(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or 0) < COOLDOWN then
		return
	end
	lastTry[player] = now
	if not nearAlchemist(player) then
		reply(player, false, "Estás muy lejos del alquimista.")
		return
	end
	if not PlayerData.IsReady(player) then
		reply(player, false, "Tu perfil aún se está cargando.")
		return
	end
	if action == "Craft" then
		craft(player, a, b)
	elseif action == "Dismantle" then
		dismantle(player, a)
	elseif action == "DismantleRarity" then
		dismantleRarities(player, a, b)
	elseif action == "DismantleCommons" then
		dismantleRarities(player, { "Comun" }, false)
	elseif action == "Drink" then
		local ok, msg = ElixirService.Drink(player, a)
		reply(player, ok, msg)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastTry[player] = nil
end)

CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Alquimista" then
		task.defer(spawnAlchemist, inst)
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

AlquimistaService.Debug = { Craft = craft, Dismantle = dismantle, DismantleRarities = dismantleRarities, Models = models }
return AlquimistaService
