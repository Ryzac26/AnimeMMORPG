--!strict
--[[
    PurchaseService (ModuleScript) -> ServerScriptService.Services.PurchaseService
    COMPRAS REPETIBLES (Developer Products): boost de XP y paquetes de horas. Catálogo y precios: ReplicatedStorage.Modules.ProductCatalog.
      - El SERVIDOR valida todo antes de abrir la compra: nivel mínimo, límite diario y la regla "una sola opción de progreso por día".
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
local PlayerData = require(ServerScriptService.Services.PlayerData)
local LevelService = require(ServerScriptService.Services.LevelService)

local StateRemote = Net.Get("TiendaState")
local ActionRemote = Net.Get("TiendaAction")
local ResultRemote = Net.Get("TiendaResult")

type Shop = { Day: string, Bought: { [string]: number }, Path: string?, BoostLeft: number, Receipts: { string } }

local PurchaseService = {}
local shops: { [Player]: Shop } = {}
local pending: { [Player]: { Key: string, At: number } } = {}
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
	if p.Kind == "Hours" and level >= GB.MAX_LEVEL then
		return false, "Ya estás en el nivel máximo"
	end
	if (s.Bought[p.Key] or 0) >= p.DailyLimit then
		return false, "Límite de hoy alcanzado"
	end
	if p.Group == "Progreso" and s.Path and s.Path ~= p.Key then
		local chosen = ProductCatalog.ByKey[s.Path]
		return false, "Hoy elegiste: " .. (if chosen then chosen.Name else s.Path)
	end
	if p.Kind == "Boost" and s.BoostLeft + (p.Seconds or 0) > ProductCatalog.MAX_BOOST_SECONDS then
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
	StateRemote:FireClient(player, { Items = items, Path = s.Path, BoostLeft = math.floor(s.BoostLeft), ResetIn = nextReset - t })
end

local function reply(player: Player, ok: boolean, text: string)
	ResultRemote:FireClient(player, ok, text)
end

-- Entrega el producto (ya pagado o de prueba). Devuelve true si quedó entregado.
local function grant(player: Player, s: Shop, p: ProductCatalog.Product): boolean
	rollDay(s)
	s.Bought[p.Key] = (s.Bought[p.Key] or 0) + 1
	if p.Group == "Progreso" and not s.Path then
		s.Path = p.Key
	end
	if p.Kind == "Boost" then
		s.BoostLeft = math.min(s.BoostLeft + (p.Seconds or 0), ProductCatalog.MAX_BOOST_SECONDS)
		player:SetAttribute("XpBoostLeft", math.floor(s.BoostLeft))
		reply(player, true, string.format("¡%s activado! Te quedan %d min.", p.Name, math.floor(s.BoostLeft / 60)))
	elseif p.Kind == "Hours" then
		local level = levelOf(player)
		local xp = ProductCatalog.HoursXp(GB, p.Hours or 0, level, LevelService.GetXp(player))
		LevelService.AddXp(player, xp)
		reply(player, true, string.format("%s: +%d XP (nivel %d → %d).", p.Name, xp, level, levelOf(player)))
	end
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

MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, _productId: number, _purchased: boolean)
	local player = Players:GetPlayerByUserId(userId)
	if player then
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
	grant(player, s, product)
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
		if typeof(raw.Path) == "string" and ProductCatalog.ByKey[raw.Path] then
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
end

PlayerData.Releasing:Connect(function(player: Player)
	shops[player] = nil
	pending[player] = nil
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
