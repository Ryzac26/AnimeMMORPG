--!strict
--[[
    MercaderService (ModuleScript) -> ServerScriptService.Services.MercaderService
    MERCADER de cada ciudad (el "Bazar del Mercader", slot 4 de ProjectBootstrapper). Compras pociones y vendes lo que te sobra.
      - Pone un NPC en cada "NPCSpawnPoint" con Role = "Mercader". Nombres/colores: tabla MERCHANTS de aquí abajo.
      - Hablar con él (botón "Comerciar") abre la ventana (ShopClient).
      - Remotes: ShopOpen (servidor -> cliente) · ShopAction (cliente -> servidor) · ShopResult (servidor -> cliente)
        ShopAction: ("Buy", itemId, cantidad) · ("Sell", casillaMochila, cantidad?) · ("SellRarity", {rarezas}, incluirMejoradas) · ("SellCommons")
      - El SERVIDOR valida todo: cerca del mercader, perfil cargado, el objeto está en la mochila (no puesto) y se puede vender.
      - Precios: ReplicatedStorage.Modules.ShopCatalog. El oro entra al historial como "Venta" y sale como "Tienda".
    Necesita Inventory.RemoveSlot (pequeño añadido a InventoryService, ver LEEME).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local ShopCatalog = require(ReplicatedStorage.Modules.ShopCatalog)
local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local Inventory = require(ServerScriptService.Services.InventoryService)
local Wallet = require(ServerScriptService.Services.WalletService)
local NpcBuilder = require(ServerScriptService.Services.NpcBuilder)

local OpenRemote = Net.Get("ShopOpen")
local ActionRemote = Net.Get("ShopAction")
local ResultRemote = Net.Get("ShopResult")

local USE_DISTANCE = 22
local COOLDOWN = 0.25

local MERCHANTS: { [string]: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 } } = {
	Saiyan = { Name = "Oolong", Title = "Mercader de la Tienda de Cápsulas", Skin = Color3.fromRGB(240, 170, 190), Shirt = Color3.fromRGB(60, 90, 160), Pants = Color3.fromRGB(50, 50, 70), Hair = Color3.fromRGB(60, 40, 40) },
	Shinobi = { Name = "Teuchi", Title = "Mercader de la Tienda Ninja", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(235, 235, 240), Pants = Color3.fromRGB(70, 60, 55), Hair = Color3.fromRGB(45, 35, 30) },
	Pirate = { Name = "Zeff", Title = "Mercader del Mercado del Muelle", Skin = Color3.fromRGB(235, 190, 150), Shirt = Color3.fromRGB(245, 245, 245), Pants = Color3.fromRGB(40, 40, 60), Hair = Color3.fromRGB(230, 225, 210) },
	Shinigami = { Name = "Kisuke Urahara", Title = "Mercader de la Tienda de Provisiones", Skin = Color3.fromRGB(240, 205, 175), Shirt = Color3.fromRGB(70, 110, 80), Pants = Color3.fromRGB(70, 110, 80), Hair = Color3.fromRGB(235, 220, 150) },
}
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local MercaderService = {}

local merchantModels: { Model } = {}
local lastTry: { [Player]: number } = {}

---------------------------------------------------------------------
-- NPC (piezas simples: se ve siempre)
---------------------------------------------------------------------
local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = name == "HumanoidRootPart" or name == "Cajon"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local function buildMerchant(info: { Name: string, Title: string, Skin: Color3, Shirt: Color3, Pants: Color3, Hair: Color3 }, cf: CFrame, faction: string): Model
	local model, head = NpcBuilder.Person("Mercader", faction, cf)
	-- puesto: cajones con mercancía al lado
	local crateCF = cf * CFrame.new(-4, -1.9, -1)
	part(model, "Cajon", Vector3.new(2.4, 2.2, 2.4), crateCF, Color3.fromRGB(140, 100, 55), Enum.Material.WoodPlanks)
	part(model, "CajonB", Vector3.new(2, 1.6, 2), crateCF * CFrame.new(0.2, 1.9, 0), Color3.fromRGB(165, 120, 65), Enum.Material.WoodPlanks)
	part(model, "Frasco", Vector3.new(0.6, 1, 0.6), crateCF * CFrame.new(-0.6, 3.0, 0), Color3.fromRGB(220, 60, 70), Enum.Material.Glass)

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 46)
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
	titleLabel.Text = "Mercader"
	titleLabel.Parent = gui
	return model
end

local function groundPosition(point: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { point }
	local hit = Workspace:Raycast(point.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
	return if hit then hit.Position else point.Position
end

local function spawnMerchant(point: BasePart)
	local biome = point:GetAttribute("Biome")
	local faction = if typeof(biome) == "string" then BIOME_FACTION[biome] else nil
	local info = if faction then MERCHANTS[faction] else nil
	if not info or not faction then
		warn("[MercaderService] Punto de mercader con Biome desconocido: " .. tostring(biome))
		return
	end
	if point:GetAttribute("MerchantSpawned") then
		return
	end
	point:SetAttribute("MerchantSpawned", true)

	local ground = groundPosition(point)
	local look = point.CFrame.LookVector
	local pos = ground + Vector3.new(0, 3.05, 0)
	local cf = CFrame.lookAt(pos, pos + Vector3.new(look.X, 0, look.Z))
	local rig = buildMerchant(info, cf, faction)
	rig.Name = "Mercader_" .. faction
	rig:SetAttribute("Merchant", true)
	rig:SetAttribute("Faction", faction)
	rig.Parent = Workspace

	local root = rig.PrimaryPart :: BasePart
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Comerciar"
	prompt.ObjectText = info.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player: Player)
		OpenRemote:FireClient(player, info.Name, info.Title, faction)
	end)
	table.insert(merchantModels, rig)
	print(string.format("[MercaderService] Mercader de %s (%s) en %s", faction, info.Name, tostring(ground)))
end

local function scan()
	for _, inst in ipairs(CollectionService:GetTagged("NPCSlot")) do
		if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Mercader" then
			task.spawn(spawnMerchant, inst)
		end
	end
end

---------------------------------------------------------------------
-- COMPRAR / VENDER
---------------------------------------------------------------------
local function nearMerchant(player: Player): boolean
	if player:GetAttribute("Pass_Merchant") == true then
		return true -- pase "Mercader Portátil": comercia desde cualquier lugar
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, m in ipairs(merchantModels) do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - root.Position).Magnitude <= USE_DISTANCE then
			return true
		end
	end
	return false
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

local function levelOf(player: Player): number
	local lv = player:GetAttribute("Level")
	return if typeof(lv) == "number" then lv else 1
end

local function finite(n: any): boolean -- rechaza NaN / infinito que mande un cliente tramposo
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function buy(player: Player, itemId: any, qty: any)
	if typeof(itemId) ~= "string" or not finite(qty) or not table.find(ShopCatalog.Stock, itemId) then
		return
	end
	local n = math.clamp(math.floor(qty), 1, ShopCatalog.MAX_BUY)
	local item: any = (ItemCatalog.Items :: any)[itemId]
	if not item then
		return
	end
	local price = ShopCatalog.BuyPrice(levelOf(player)) * n
	if not Wallet.TrySpendGold(player, price, "Tienda") then
		reply(player, false, string.format("Te falta oro (necesitas %d).", price))
		return
	end
	if not Inventory.Add(player, itemId, n) then
		Wallet.AddGold(player, price, "Tienda") -- no debería pasar: se devuelve el oro
		reply(player, false, "Mochila llena: libera espacio.")
		return
	end
	reply(player, true, string.format("Compraste %s x%d por %d de oro.", item.Name, n, price))
	PlayerData.Save(player)
end

local function sell(player: Player, index: any, count: any)
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
		reply(player, false, "Está bloqueado 🔒: quítale el candado en la mochila para venderlo.")
		return
	end
	local item: any = (ItemCatalog.Items :: any)[stack.Id]
	local unit = ShopCatalog.SellPrice(stack.Id, item, stack.Plus)
	if not unit then
		reply(player, false, "El mercader no compra eso.")
		return
	end
	local want = if finite(count) then math.floor(count) else stack.Count
	want = math.clamp(want, 1, stack.Count)
	local id, _, taken = Inventory.RemoveSlot(player, slot, want)
	if not id or taken <= 0 then
		reply(player, false, "No se pudo vender.")
		return
	end
	local gold = Wallet.AddGold(player, unit * taken, "Venta")
	reply(player, true, string.format("Vendiste %s x%d por %d de oro.", item.Name, taken, gold))
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

-- Vende de una vez TODO el equipo de las rarezas elegidas que esté en la mochila (sin candado; lo mejorado solo si includePlus)
local function sellRarities(player: Player, rarities: any, includePlus: any)
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
		local item: any = (ItemCatalog.Items :: any)[stack.Id]
		if item and not item.Pet and (item.Gear or item.Slot) and set[item.Rarity] and (withPlus or (stack.Plus or 0) == 0) and not stack.Locked then
			table.insert(slots, i)
		end
	end
	local total, pieces = 0, 0
	for _, i in ipairs(slots) do
		local stack = st.Bag[i]
		if stack then
			local item: any = (ItemCatalog.Items :: any)[stack.Id]
			local unit = ShopCatalog.SellPrice(stack.Id, item, stack.Plus or 0)
			if unit then
				local id, _, taken = Inventory.RemoveSlot(player, i, stack.Count)
				if id then
					total += unit * taken
					pieces += taken
				end
			end
		end
	end
	if pieces == 0 then
		reply(player, false, "No tienes equipo de esa rareza para vender.")
		return
	end
	Wallet.AddGold(player, total, "Venta")
	reply(player, true, string.format("Vendiste %d piezas por %d de oro.", pieces, total))
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
	if action == "OpenPortable" then
		if player:GetAttribute("Pass_Merchant") == true then
			OpenRemote:FireClient(player, "Mercader Portátil", "Compra y vende desde donde estés", "", true)
		else
			reply(player, false, "Necesitas el pase Mercader Portátil (Tienda > Pases).")
		end
		return
	end
	if not nearMerchant(player) then
		reply(player, false, "Estás muy lejos del mercader.")
		return
	end
	if not PlayerData.IsReady(player) then
		reply(player, false, "Tu perfil aún se está cargando.")
		return
	end
	if action == "Buy" then
		buy(player, a, b)
	elseif action == "Sell" then
		sell(player, a, b)
	elseif action == "SellRarity" then
		sellRarities(player, a, b)
	elseif action == "SellCommons" then
		sellRarities(player, { "Comun" }, false)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastTry[player] = nil
end)

CollectionService:GetInstanceAddedSignal("NPCSlot"):Connect(function(inst)
	if inst:IsA("BasePart") and inst:GetAttribute("Role") == "Mercader" then
		task.defer(spawnMerchant, inst)
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

-- solo para pruebas automáticas
MercaderService.Debug = { Buy = buy, Sell = sell, SellRarities = sellRarities, Merchants = merchantModels }

return MercaderService
