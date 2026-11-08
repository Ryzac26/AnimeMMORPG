--!strict
--[[
    VipShopService (ModuleScript) -> ServerScriptService.Services.VipShopService
    TIENDA VIP DEL MES (catálogo y precios: ReplicatedStorage.Modules.VipShopCatalog). Solo cosméticos.
      - Sellos Imperiales: solo los ganan y gastan los suscriptores (atributo Sub_Vip). Earn(player, "Login" | "Daily" | "Weekly").
      - Compra: Title -> TitleService.Grant · Furniture -> OwnsFurniture (HouseService lo exige al colocar) · Aura -> se equipa aquí.
      - Perfil: sección "VipShop" = { P = sellos, Own = {ids de artículos}, Aura = clave equipada, Day = último día de bono }.
      - Remotes: VipShopState (servidor -> cliente) · VipShopAction ("State" | "Buy", id | "Aura", clave | "").
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local VipShopCatalog = require(ReplicatedStorage.Modules.VipShopCatalog)

local StateRemote = Net.Get("VipShopState")
local ActionRemote = Net.Get("VipShopAction")
local NotifyRemote = Net.Get("Notify")

type Profile = { P: number, Own: { [string]: boolean }, Aura: string?, Day: number }
local profiles: { [Player]: Profile } = {}
local lastAction: { [Player]: number } = {}

local VipShopService = {}

local function isSub(player: Player): boolean
	return player:GetAttribute("Sub_Vip") == true
end

PlayerData.RegisterSerializer("VipShop", function(player: Player): any?
	local p = profiles[player]
	if not p then
		return nil
	end
	local own: { string } = {}
	for id in pairs(p.Own) do
		table.insert(own, id)
	end
	return { P = p.P, Own = own, Aura = p.Aura, Day = p.Day }
end)

local function push(player: Player)
	local p = profiles[player]
	if not p or player.Parent == nil then
		return
	end
	local items: { any } = {}
	for _, it in ipairs(VipShopCatalog.Month()) do
		table.insert(items, { Id = it.Id, Owned = p.Own[it.Id] == true })
	end
	local owned: { string } = {}
	for id in pairs(p.Own) do
		table.insert(owned, id)
	end
	StateRemote:FireClient(player, {
		Points = p.P,
		Sub = isSub(player),
		Items = items,
		Owned = owned,
		Aura = p.Aura,
		SecondsLeft = VipShopCatalog.SecondsLeft(),
	})
end

---------------------------------------------------------------------
-- Aura (partículas en el personaje)
---------------------------------------------------------------------
local function applyAura(player: Player)
	local p = profiles[player]
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local old = root:FindFirstChild("AuraVip")
	if old then
		old:Destroy()
	end
	local def = if p and p.Aura then VipShopCatalog.Auras[p.Aura] else nil
	if not def then
		return
	end
	local at = Instance.new("Attachment")
	at.Name = "AuraVip"
	at.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = def.Rate
	pe.Lifetime = NumberRange.new(1.2, 2)
	pe.Speed = NumberRange.new(def.Speed * 0.5, def.Speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, def.Size), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(def.A, def.B)
	pe.LightEmission = 1
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	pe.Acceleration = Vector3.new(0, 1.5, 0)
	pe.Parent = at
end

---------------------------------------------------------------------
-- API para otros servicios
---------------------------------------------------------------------
function VipShopService.Earn(player: Player, kind: string)
	local p = profiles[player]
	local n = VipShopCatalog.Earn[kind]
	if not p or not n or not isSub(player) then
		return
	end
	p.P += n
	NotifyRemote:FireClient(player, string.format("🎖 +%d Sellos Imperiales (%d)", n, p.P))
	push(player)
end

function VipShopService.OwnsFurniture(player: Player, furnitureId: string): boolean
	local p = profiles[player]
	if not p then
		return false
	end
	for id in pairs(p.Own) do
		local it = VipShopCatalog.ById[id]
		if it and it.Kind == "Furniture" and it.Ref == furnitureId then
			return true
		end
	end
	return false
end

function VipShopService.OwnedFurniture(player: Player): { string }
	local out: { string } = {}
	local p = profiles[player]
	if p then
		for id in pairs(p.Own) do
			local it = VipShopCatalog.ById[id]
			if it and it.Kind == "Furniture" then
				table.insert(out, it.Ref)
			end
		end
	end
	return out
end

---------------------------------------------------------------------
-- Compra y aura
---------------------------------------------------------------------
local function buy(player: Player, id: any)
	local p = profiles[player]
	local it = if typeof(id) == "string" then VipShopCatalog.ById[id] else nil
	if not p or not it then
		return
	end
	local inMonth = false
	for _, m in ipairs(VipShopCatalog.Month()) do
		if m.Id == it.Id then
			inMonth = true
		end
	end
	if not inMonth then
		NotifyRemote:FireClient(player, "Ese artículo ya no está en la vitrina de este mes.")
		return
	end
	if not isSub(player) then
		NotifyRemote:FireClient(player, "Necesitas la Suscripción Imperial activa para comprar en la Tienda VIP.")
		return
	end
	if p.Own[it.Id] then
		return
	end
	if p.P < it.Price then
		NotifyRemote:FireClient(player, string.format("Te faltan %d Sellos Imperiales.", it.Price - p.P))
		return
	end
	p.P -= it.Price
	p.Own[it.Id] = true
	if it.Kind == "Title" then
		local ok, TS = pcall(function()
			return require(Services.TitleService)
		end)
		if ok and TS then
			(TS :: any).Grant(player, it.Ref)
		end
	elseif it.Kind == "Aura" then
		p.Aura = it.Ref
		applyAura(player)
	end
	NotifyRemote:FireClient(player, string.format("🛍 Compraste: %s", it.Name))
	PlayerData.Save(player)
	push(player)
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any)
	local p = profiles[player]
	if not p or typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.3 then
		return
	end
	lastAction[player] = now
	if action == "Buy" then
		buy(player, a)
		return
	elseif action == "Aura" then
		if a == "" or a == nil then
			p.Aura = nil
		elseif typeof(a) == "string" and VipShopCatalog.Auras[a] then
			local owns = false
			for id in pairs(p.Own) do
				local it = VipShopCatalog.ById[id]
				if it and it.Kind == "Aura" and it.Ref == a then
					owns = true
				end
			end
			if not owns then
				return
			end
			p.Aura = a
		else
			return
		end
		applyAura(player)
	end
	push(player)
end)

---------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------
local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local p: Profile = { P = 0, Own = {}, Aura = nil, Day = 0 }
	local raw: any = (saved :: any).VipShop
	if typeof(raw) == "table" then
		p.P = if typeof(raw.P) == "number" then math.max(0, math.floor(raw.P)) else 0
		p.Day = if typeof(raw.Day) == "number" then raw.Day else 0
		if typeof(raw.Own) == "table" then
			for _, id in ipairs(raw.Own) do
				if typeof(id) == "string" and VipShopCatalog.ById[id] then
					p.Own[id] = true
				end
			end
		end
		if typeof(raw.Aura) == "string" and VipShopCatalog.Auras[raw.Aura] and p.Own["a_" .. string.lower(raw.Aura)] ~= nil then
			p.Aura = raw.Aura
		end
	end
	profiles[player] = p
	player.CharacterAdded:Connect(function()
		task.wait(1)
		applyAura(player)
	end)
	applyAura(player)
	-- bono de entrada diario (espera a que se confirme la suscripción)
	task.delay(8, function()
		local today = math.floor(os.time() / 86400)
		if profiles[player] and isSub(player) and p.Day ~= today then
			p.Day = today
			VipShopService.Earn(player, "Login")
		end
		push(player)
	end)
	push(player)
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	task.delay(30, function()
		profiles[pl] = nil
		lastAction[pl] = nil
	end)
end)

print("[VipShopService] Listo: vitrina del mes con " .. #VipShopCatalog.Month() .. " artículos.")

return VipShopService
