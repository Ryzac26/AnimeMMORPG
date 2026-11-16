--!strict
--[[
    HuntStats (ModuleScript) -> ServerScriptService > Services > HuntStats
    ANALIZADOR DE CAZA (estilo Tibia): cuenta por jugador lo que gana mientras mata monstruos: XP, bajas, oro y botín. El cliente (HuntClient) lo
    muestra en una ventana con XP/hora, oro/hora, tiempo estimado para el siguiente nivel y el ritmo frente al paquete de horas.
    No lo llamas tú: lo llaman RewardService (XP y bajas) y LootService (oro y objetos) justo cuando se entregan.
      HuntStats.Kill(player)            una baja con participación
      HuntStats.Xp(player, amount)      XP entregada de verdad (ya con boosts, mascota y brecha de nivel)
      HuntStats.Gold(player, amount)    oro de botín entregado
      HuntStats.Loot(player, id, count, plus)   objeto entregado
    MODO: "Mundo" o "Campo" (zona AFK, atributo InAfk). Al cambiar de modo las cuentas se REINICIAN solas (así no se mezclan ritmos distintos).
    TIEMPO ACTIVO: solo corre mientras hubo una baja en los últimos ACTIVE_WINDOW s; las tasas por hora usan ese tiempo, no el reloj de pared.
    REMOTO "Hunt": cliente -> servidor ("Open") ("Close") ("Reset"); servidor -> cliente ("Snap", {...}) cada SEND_EVERY s mientras la ventana está abierta.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local ItemCatalog = require(Modules.ItemCatalog)
local GearCatalog = require(Modules.GearCatalog)
local Net = require(ServerScriptService.Services.Net)

local CONFIG = {
	ACTIVE_WINDOW = 60, -- segundos sin bajas tras los cuales el reloj de "tiempo activo" se detiene
	SEND_EVERY = 1, -- segundos entre envíos al cliente
	MAX_ITEMS = 14, -- renglones de botín que se envían
}

type Stats = {
	Mode: string,
	Start: number, -- os.clock() de la primera baja
	LastKill: number,
	Active: number, -- segundos de tiempo activo
	StartLevel: number,
	Kills: number,
	Xp: number,
	Gold: number,
	Items: { [string]: number },
	Order: { string },
}

local Remote = Net.Get("Hunt")
local stats: { [Player]: Stats } = {}
local open: { [Player]: boolean } = {}

local function modeOf(p: Player): string
	return if p:GetAttribute("InAfk") ~= nil then "Campo" else "Mundo"
end

local function newStats(p: Player): Stats
	local lvl = p:GetAttribute("Level")
	local now = os.clock()
	return {
		Mode = modeOf(p),
		Start = now,
		LastKill = now,
		Active = 0,
		StartLevel = if typeof(lvl) == "number" then lvl else 1,
		Kills = 0,
		Xp = 0,
		Gold = 0,
		Items = {},
		Order = {},
	}
end

-- devuelve las cuentas del jugador; si cambió de modo (Mundo <-> Campo) las reinicia
local function get(p: Player): Stats
	local s = stats[p]
	if not s or s.Mode ~= modeOf(p) then
		s = newStats(p)
		stats[p] = s
	end
	return s
end

local function itemName(id: string, plus: number?): string
	local item = (ItemCatalog.Items :: any)[id]
	if not item then
		return id
	end
	local text: string = item.Name
	if item.Gear or item.Pet then
		text = string.format("[%s] %s", GearCatalog.RarityName[item.Rarity] or item.Rarity, item.Name)
		if plus and plus > 0 then
			text ..= " +" .. plus
		end
	end
	return text
end

local HuntStats = {}

function HuntStats.Kill(p: Player)
	local s = get(p)
	s.Kills += 1
	s.LastKill = os.clock()
end

function HuntStats.Xp(p: Player, amount: number)
	if amount > 0 then
		get(p).Xp += amount
	end
end

function HuntStats.Gold(p: Player, amount: number)
	if amount > 0 then
		get(p).Gold += amount
	end
end

function HuntStats.Loot(p: Player, id: string, count: number, plus: number?)
	local s = get(p)
	local name = itemName(id, plus)
	if s.Items[name] == nil then
		s.Items[name] = 0
		table.insert(s.Order, name)
	end
	s.Items[name] += math.max(count, 1)
end

local function snapshot(p: Player, s: Stats): any
	-- botín: equipo y mascotas (los que empiezan con "[") primero, luego por cantidad
	local names = table.clone(s.Order)
	table.sort(names, function(a, b)
		local ga = string.sub(a, 1, 1) == "["
		local gb = string.sub(b, 1, 1) == "["
		if ga ~= gb then
			return ga
		end
		if s.Items[a] ~= s.Items[b] then
			return s.Items[a] > s.Items[b]
		end
		return a < b
	end)
	local items: { any } = {}
	for i = 1, math.min(#names, CONFIG.MAX_ITEMS) do
		table.insert(items, { Name = names[i], Count = s.Items[names[i]] })
	end
	return {
		Mode = s.Mode,
		Total = os.clock() - s.Start,
		Active = s.Active,
		Kills = s.Kills,
		Xp = s.Xp,
		Gold = s.Gold,
		StartLevel = s.StartLevel,
		Items = items,
		More = math.max(#names - CONFIG.MAX_ITEMS, 0),
		Distinct = #names,
	}
end

Remote.OnServerEvent:Connect(function(p: Player, action: any)
	if action == "Open" then
		open[p] = true
		Remote:FireClient(p, "Snap", snapshot(p, get(p)))
	elseif action == "Close" then
		open[p] = nil
	elseif action == "Reset" then
		stats[p] = newStats(p)
		Remote:FireClient(p, "Snap", snapshot(p, stats[p]))
	end
end)

-- reloj: tiempo activo + envío periódico
task.spawn(function()
	local last = os.clock()
	local sendAcc = 0
	while true do
		task.wait(0.5)
		local now = os.clock()
		local dt = now - last
		last = now
		sendAcc += dt
		for p, s in pairs(stats) do
			if p.Parent and now - s.LastKill <= CONFIG.ACTIVE_WINDOW then
				s.Active += dt
			end
		end
		if sendAcc >= CONFIG.SEND_EVERY then
			sendAcc = 0
			for p in pairs(open) do
				if p.Parent then
					Remote:FireClient(p, "Snap", snapshot(p, get(p)))
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	stats[p] = nil
	open[p] = nil
end)

HuntStats.Config = CONFIG
return HuntStats
