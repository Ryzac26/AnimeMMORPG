--!strict
--[[
    PurchaseService (ModuleScript) -> ServerScriptService.Services.PurchaseService
    COMPRAS REPETIBLES (Developer Products): boost de XP, paquetes de horas y combos. Catálogo y precios: ReplicatedStorage.Modules.ProductCatalog.
      - El SERVIDOR valida todo antes de abrir la compra: nivel mínimo, límite diario y la regla "un solo paquete de horas/combo por día" (el boost es independiente).
      - ProcessReceipt (único en todo el juego): entrega el producto, lo guarda en el perfil y recién entonces confirma a Roblox.
        Cada compra (PurchaseId) se entrega una sola vez aunque Roblox reintente.
      - Boost de XP: el tiempo corre solo con el jugador conectado. XpMult(player) lo usa RewardService.
      - Remotes: TiendaState (servidor -> cliente: estado) · TiendaAction (cliente -> servidor: "State" | "Buy", clave) · TiendaResult.
    Persistencia: sección "Shop" de PlayerData = { Day, Bought, Path, BoostLeft, Receipts }.
]]
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local GB = require(ReplicatedStorage.Modules.GameBalance)
local ProductCatalog = require(ReplicatedStorage.Modules.ProductCatalog)
local Net = require(ServerScriptService.Services.Net)
local BlessingService = require(ServerScriptService.Services.BlessingService)
local HouseService = require(ServerScriptService.Services.HouseService)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local LevelService = require(ServerScriptService.Services.LevelService)
local Inventory = require(ServerScriptService.Services.InventoryService)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)

local StateRemote = Net.Get("TiendaState")
local ActionRemote = Net.Get("TiendaAction")
local ResultRemote = Net.Get("TiendaResult")

type Shop = { Day: string, Bought: { [string]: number }, Path: string?, BoostLeft: number, Receipts: { string } }

local PurchaseService = {}
local shops: { [Player]: Shop } = {}
local pending: { [Player]: { Key: string, At: number } } = {}
local passOwned: { [Player]: { [string]: boolean } } = {} -- pases de una sola compra (ProductCatalog.Passes)
local studioGranted: { [Player]: { [string]: boolean } } = {} -- solo Studio: "comprados" en esta sesión de prueba
local lastAction: { [Player]: number } = {}

local function today(): string
	return os.date("!%Y-%m-%d") :: string
end

local function rollDay(s: Shop)
	local t = today()
	if s.Day ~= t then
		s.Day, s.Bought, s.Path = t, {}, nil
	end
end

local function levelOf(player: Player): number
	return LevelService.GetLevel(player)
end

-- ¿Se puede comprar ahora? (lo mismo lo comprueba el cliente para mostrar el motivo del bloqueo)
local function canBuy(player: Player, s: Shop, p: ProductCatalog.Product): (boolean, string?)
	rollDay(s)
	local level = levelOf(player)
	if level < p.MinLevel then
		return false, "Necesitas nivel " .. p.MinLevel
	end
	if (p.Kind == "Hours" or p.Kind == "Combo") and level >= GB.MAX_LEVEL then
		return false, "Ya estás en el nivel máximo"
	end
	if p.Kind == "Blessing" then
		local why = BlessingService.Reason(player, p)
		if why then
			return false, why
		end
	end
	if (s.Bought[p.Key] or 0) >= p.DailyLimit then
		return false, "Límite de hoy alcanzado"
	end
	if p.Lane == "Horas" and s.Path and s.Path ~= p.Key then
		local chosen = ProductCatalog.ByKey[s.Path]
		return false, "Bloqueado: hoy elegiste " .. (if chosen then chosen.Name else s.Path)
	end
	if p.Seconds and s.BoostLeft + (p.Seconds or 0) > ProductCatalog.MAX_BOOST_SECONDS then
		return false, "Ya tienes mucho boost acumulado"
	end
	return true, nil
end

local function pushState(player: Player)
	local s = shops[player]
	if not s then
		return
	end
	rollDay(s)
	local items: { [string]: any } = {}
	for _, p in ipairs(ProductCatalog.Products) do
		local ok, why = canBuy(player, s, p)
		items[p.Key] = { Bought = s.Bought[p.Key] or 0, Ok = ok, Why = why }
	end
	local t = os.time()
	local nextReset = (math.floor(t / 86400) + 1) * 86400
	StateRemote:FireClient(player, { Items = items, Path = s.Path, BoostLeft = math.floor(s.BoostLeft), ResetIn = nextReset - t, Passes = passOwned[player] or {} })
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

---------------------------------------------------------------------
-- PASES (Game Pass, una sola compra)
---------------------------------------------------------------------
local function setPass(player: Player, ps: ProductCatalog.Pass, owned: boolean)
	local t = passOwned[player]
	if not t then
		t = {}
		passOwned[player] = t
	end
	t[ps.Key] = owned
	player:SetAttribute(ps.Attr, owned)
end

local function checkPasses(player: Player)
	for _, ps in ipairs(ProductCatalog.Passes) do
		local owned = false
		if RunService:IsStudio() then
			-- en Studio tu cuenta NO tiene los pases salvo que lo pidas en ProductCatalog.DevOwnPasses (o los "compres" de prueba)
			owned = ProductCatalog.DevOwnPasses[ps.Key] == true or (studioGranted[player] ~= nil and studioGranted[player][ps.Key] == true)
		elseif ps.PassId > 0 then
			local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, ps.PassId)
			owned = ok and has == true
		end
		if player.Parent then
			setPass(player, ps, owned)
		end
	end
end

local function buyPass(player: Player, key: any)
	local ps = if typeof(key) == "string" then ProductCatalog.PassByKey[key] else nil
	if not ps then
		return
	end
	if passOwned[player] and passOwned[player][ps.Key] then
		reply(player, false, "Ya tienes este pase.")
		return
	end
	if ps.Key == "VipHouse" then
		local okSlot, why = HouseService.Reserve(player) -- cupo limitado de casas
		if not okSlot then
			reply(player, false, why or "Sin cupo")
			return
		end
	end
	if ps.PassId > 0 then
		local ok, err = pcall(MarketplaceService.PromptGamePassPurchase, MarketplaceService, player, ps.PassId)
		if not ok then
			warn("[PurchaseService] No se pudo abrir la compra del pase: " .. tostring(err))
			reply(player, false, "No se pudo abrir la compra")
		end
	elseif RunService:IsStudio() then
		local g = studioGranted[player]
		if not g then
			g = {}
			studioGranted[player] = g
		end
		g[ps.Key] = true
		setPass(player, ps, true)
		reply(player, true, "(Prueba en Studio) " .. ps.Name .. " activado solo en esta sesión.")
		pushState(player)
	else
		reply(player, false, "Este pase aún no está a la venta")
	end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if not purchased then
		if ProductCatalog.PassByKey.VipHouse and ProductCatalog.PassByKey.VipHouse.PassId == passId then
			task.spawn(HouseService.Release, player) -- no pagó: se libera su cupo
		end
		return
	end
	for _, ps in ipairs(ProductCatalog.Passes) do
		if ps.PassId > 0 and ps.PassId == passId then
			setPass(player, ps, true)
			reply(player, true, string.format("¡%s adquirido! Gracias por apoyar el juego.", ps.Name))
			pushState(player)
		end
	end
end)

-- Entrega el producto (ya pagado o de prueba). Devuelve true si quedó entregado.
local function grant(player: Player, s: Shop, p: ProductCatalog.Product): boolean
	rollDay(s)
	-- objetos: primero se meten en la mochila; si no caben, NO se entrega (la compra se reintenta / se pide liberar espacio)
	local gotItems: { { string | number } } = {}
	if p.Items then
		for id, n in pairs(p.Items) do
			if Inventory.Add(player, id, n) then
				table.insert(gotItems, { id, n })
			else
				for _, g in ipairs(gotItems) do
					Inventory.Consume(player, g[1] :: string, g[2] :: number)
				end
				reply(player, false, "Mochila llena: libera espacio y vuelve a intentarlo (la compra queda pendiente).")
				return false
			end
		end
	end
	if p.Kind == "HouseLicense" then
		HouseService.GrantLicense(player)
		return true
	end
	if p.Kind == "Blessing" then
		if not BlessingService.Activate(player, p) then
			reply(player, false, "No se pudo activar la bendición (elige tu facción primero).")
			return false
		end
	end
	s.Bought[p.Key] = (s.Bought[p.Key] or 0) + 1
	if p.Lane == "Horas" and not s.Path then
		s.Path = p.Key
	end
	local msgs: { string } = {}
	if p.Seconds then
		s.BoostLeft = math.min(s.BoostLeft + p.Seconds, ProductCatalog.MAX_BOOST_SECONDS)
		player:SetAttribute("XpBoostLeft", math.floor(s.BoostLeft))
		table.insert(msgs, string.format("Boost de XP activo: te quedan %d min.", math.floor(s.BoostLeft / 60)))
	end
	if p.Hours then
		local level = levelOf(player)
		local xp = ProductCatalog.HoursXp(GB, p.Hours, level, LevelService.GetXp(player))
		LevelService.AddXp(player, xp)
		table.insert(msgs, string.format("+%d XP (nivel %d → %d).", xp, level, levelOf(player)))
	end
	for _, g in ipairs(gotItems) do
		local it: any = (ItemCatalog.Items :: any)[g[1] :: string]
		table.insert(msgs, string.format("+%d %s en tu mochila.", g[2] :: number, if it then it.Name else g[1] :: string))
	end
	reply(player, true, string.format("¡%s! %s", p.Name, table.concat(msgs, " ")))
	return true
end

local function request(player: Player, key: any)
	local s = shops[player]
	local p = if typeof(key) == "string" then ProductCatalog.ByKey[key] else nil
	if not s or not p then
		return
	end
	local ok, why = canBuy(player, s, p)
	if not ok then
		reply(player, false, why or "No disponible")
		pushState(player)
		return
	end
	local pend = pending[player]
	if pend and os.clock() - pend.At < 120 then
		reply(player, false, "Termina primero la compra en curso")
		return
	end
	if p.ProductId > 0 then
		pending[player] = { Key = p.Key, At = os.clock() }
		local started, err = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, p.ProductId)
		if not started then
			pending[player] = nil
			warn("[PurchaseService] No se pudo abrir la compra: " .. tostring(err))
			reply(player, false, "No se pudo abrir la compra")
		end
	elseif RunService:IsStudio() then
		grant(player, s, p) -- prueba en Studio: sin ProductId se entrega gratis
		PlayerData.Save(player)
		pushState(player)
	else
		reply(player, false, "Este producto aún no está a la venta")
	end
end

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local rebuy = ProductCatalog.ByKey.VipHouseRebuy
		if rebuy and rebuy.ProductId == productId and not purchased then
			HouseService.RebuyCancelled(player) -- no pagó: se libera el cupo reservado
		end
		pending[player] = nil
		task.delay(1, function()
			if player.Parent then
				pushState(player)
			end
		end)
	end
end)

MarketplaceService.ProcessReceipt = function(info: any)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local s = shops[player]
	if not s then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- el perfil aún no cargó: Roblox reintenta
	end
	local pid = tostring(info.PurchaseId)
	if table.find(s.Receipts, pid) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- ya entregado antes
	end
	local product: ProductCatalog.Product? = nil
	for _, p in ipairs(ProductCatalog.Products) do
		if p.ProductId > 0 and p.ProductId == info.ProductId then
			product = p
		end
	end
	if not product then
		warn("[PurchaseService] Compra de un producto desconocido: " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not grant(player, s, product) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- mochila llena: Roblox reintenta (al liberar espacio / reconectar)
	end
	table.insert(s.Receipts, pid)
	while #s.Receipts > 100 do
		table.remove(s.Receipts, 1)
	end
	pending[player] = nil
	PlayerData.Save(player)
	pushState(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, key: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.3 then
		return
	end
	lastAction[player] = now
	if action == "State" then
		pushState(player)
	elseif action == "Buy" then
		request(player, key)
	elseif action == "BuyPass" then
		buyPass(player, key)
	end
end)

-- multiplicador de XP que usa RewardService
function PurchaseService.XpMult(player: Player): number
	local s = shops[player]
	if s and s.BoostLeft > 0 then
		return 1.5
	end
	return 1
end

-- el tiempo del boost corre solo con el jugador conectado
task.spawn(function()
	while true do
		task.wait(1)
		for player, s in pairs(shops) do
			if s.BoostLeft > 0 then
				s.BoostLeft = math.max(0, s.BoostLeft - 1)
				if s.BoostLeft % 10 == 0 or s.BoostLeft == 0 then
					player:SetAttribute("XpBoostLeft", math.floor(s.BoostLeft))
				end
				if s.BoostLeft == 0 then
					reply(player, true, "Tu boost de XP terminó")
					pushState(player)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Guardado / carga
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Shop", function(player: Player): any?
	local s = shops[player]
	if not s then
		return nil
	end
	return { Day = s.Day, Bought = s.Bought, Path = s.Path, BoostLeft = math.floor(s.BoostLeft), Receipts = s.Receipts }
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local raw: any = saved.Shop
	local s: Shop = { Day = today(), Bought = {}, Path = nil, BoostLeft = 0, Receipts = {} }
	if typeof(raw) == "table" then
		if typeof(raw.Day) == "string" then
			s.Day = raw.Day
		end
		if typeof(raw.Bought) == "table" then
			for k, v in pairs(raw.Bought) do
				if typeof(k) == "string" and typeof(v) == "number" then
					s.Bought[k] = math.floor(v)
				end
			end
		end
		local pp = if typeof(raw.Path) == "string" then ProductCatalog.ByKey[raw.Path] else nil
		if pp and pp.Lane == "Horas" then
			s.Path = raw.Path
		end
		if typeof(raw.BoostLeft) == "number" then
			s.BoostLeft = math.clamp(raw.BoostLeft, 0, ProductCatalog.MAX_BOOST_SECONDS)
		end
		if typeof(raw.Receipts) == "table" then
			for _, id in ipairs(raw.Receipts) do
				if typeof(id) == "string" then
					table.insert(s.Receipts, id)
				end
			end
		end
	end
	rollDay(s)
	shops[player] = s
	player:SetAttribute("XpBoostLeft", math.floor(s.BoostLeft))
	pushState(player)
	checkPasses(player)
	pushState(player)
end

PlayerData.Releasing:Connect(function(player: Player)
	shops[player] = nil
	pending[player] = nil
	passOwned[player] = nil
	studioGranted[player] = nil
	lastAction[player] = nil
end)
Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end

PurchaseService.Debug = { Request = request, Grant = grant, Shops = shops, CanBuy = canBuy }
return PurchaseService
