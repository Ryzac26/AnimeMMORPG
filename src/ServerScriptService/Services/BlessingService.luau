--!strict
--[[
    BlessingService (ModuleScript) -> ServerScriptService.Services.BlessingService
    BENDICIONES DE FACCIÓN DE PAGO (productos Kind "Blessing" de ProductCatalog; reglas en el comentario de BlessGroups).
      - Activate(player, producto): suma tiempo a la línea (facción, grupo) de ESTE servidor. Todos los de esa facción reciben el bono
        (fuente "Blessing" de GearService: Xp, Oro, Suerte). El tiempo solo corre si hay jugadores de la facción conectados.
      - Si dos grupos dan el mismo bono, vale el mayor. Tope por facción y día: ProductCatalog.BLESS_DAILY_SECONDS.
      - Cierre del servidor CON jugadores dentro: el tiempo sobrante se reparte entre quienes lo compraron (DataStore "BlessRefund_v1",
        clave = UserId) y se entrega como bendición PERSONAL al volver a entrar. Si el servidor se cierra vacío, no se devuelve.
      - Bendición personal: se guarda en el perfil (sección "Blessing" = { P = { grupo = segundos } }); el tiempo corre con el jugador conectado.
      - Atributo del jugador "BlessInfo" (texto "Grupo:segundos;...") para mostrar lo activo.
]]
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProductCatalog = require(ReplicatedStorage.Modules.ProductCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local GearService = require(Services.GearService)

local NotifyRemote = Net.Get("Notify")

type Line = { Left: number, Buyers: { [string]: number } }
type Day = { Day: string, Used: number }

local BlessingService = {}

local lines: { [string]: { [string]: Line } } = {} -- facción -> grupo -> línea
local used: { [string]: Day } = {} -- facción -> segundos comprados hoy (UTC)
local personal: { [Player]: { [string]: number } } = {}

local refundStore: DataStore? = nil
do
	local ok, r = pcall(function()
		return DataStoreService:GetDataStore("BlessRefund_v1")
	end)
	if ok then
		refundStore = r :: DataStore
	end
end

local function today(): string
	return os.date("!%Y-%m-%d") :: string
end

local function factionOf(player: Player): string?
	local f = player:GetAttribute("Faction")
	return if typeof(f) == "string" then f else nil
end

local function usedToday(f: string): number
	local d = used[f]
	if not d or d.Day ~= today() then
		d = { Day = today(), Used = 0 }
		used[f] = d
	end
	return d.Used
end

-- Bono vigente de un jugador: lo mayor entre las líneas de su facción y sus bendiciones personales
local function apply(player: Player)
	local stats: { [string]: number } = {}
	local info: { string } = {}
	local function take(group: string, left: number)
		local def = ProductCatalog.BlessGroups[group]
		if def and left > 0 then
			for st, v in pairs(def.Stats) do
				stats[st] = math.max(stats[st] or 0, v)
			end
			table.insert(info, string.format("%s:%d", group, math.floor(left)))
		end
	end
	local f = factionOf(player)
	if f and lines[f] then
		for g, l in pairs(lines[f]) do
			take(g, l.Left)
		end
	end
	for g, left in pairs(personal[player] or {}) do
		take(g, left)
	end
	GearService.SetTemp(player, if next(stats) then stats else nil, "Blessing")
	player:SetAttribute("BlessInfo", table.concat(info, ";"))
end

local function applyFaction(f: string)
	for _, pl in ipairs(Players:GetPlayers()) do
		if factionOf(pl) == f then
			apply(pl)
		end
	end
end

-- Motivo por el que NO se puede comprar (o nil)
function BlessingService.Reason(player: Player, p: ProductCatalog.Product): string?
	local f = factionOf(player)
	if not f then
		return "Elige tu facción primero"
	end
	local secs = p.BlessSeconds or 0
	if usedToday(f) + secs > ProductCatalog.BLESS_DAILY_SECONDS then
		return "Tu facción ya tiene el máximo de horas de hoy en este servidor"
	end
	return nil
end

function BlessingService.Activate(player: Player, p: ProductCatalog.Product): boolean
	local f = factionOf(player)
	local group = p.BlessGroup
	local secs = p.BlessSeconds
	if not f or not group or not secs or not ProductCatalog.BlessGroups[group] then
		return false
	end
	usedToday(f)
	local fl = lines[f]
	if not fl then
		fl = {}
		lines[f] = fl
	end
	local l = fl[group]
	if not l then
		l = { Left = 0, Buyers = {} }
		fl[group] = l
	end
	l.Left += secs
	local uid = tostring(player.UserId)
	l.Buyers[uid] = (l.Buyers[uid] or 0) + secs
	local dayRec = used[f]
	dayRec.Used += secs
	local def = ProductCatalog.BlessGroups[group]
	for _, pl in ipairs(Players:GetPlayers()) do
		if factionOf(pl) == f then
			NotifyRemote:FireClient(pl, string.format("%s compró %s para la facción (%s) · %.1f h", player.DisplayName, def.Name, def.Short, secs / 3600))
		end
	end
	applyFaction(f)
	return true
end

-- el tiempo corre solo si hay jugadores de la facción
task.spawn(function()
	while true do
		task.wait(1)
		local online: { [string]: boolean } = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			local f = factionOf(pl)
			if f then
				online[f] = true
			end
			local pp = personal[pl]
			if pp and next(pp) then
				local changed = false
				for g, left in pairs(pp) do
					local n = left - 1
					if n <= 0 then
						pp[g] = nil
						changed = true
					else
						pp[g] = n
						if n % 30 == 0 then
							changed = true
						end
					end
				end
				if changed then
					apply(pl)
				end
			end
		end
		for f, fl in pairs(lines) do
			if online[f] then
				local changed = false
				for g, l in pairs(fl) do
					l.Left -= 1
					if l.Left <= 0 then
						fl[g] = nil
						changed = true
						for _, pl in ipairs(Players:GetPlayers()) do
							if factionOf(pl) == f then
								NotifyRemote:FireClient(pl, string.format("Terminó la %s de tu facción", ProductCatalog.BlessGroups[g].Name))
							end
						end
					elseif l.Left % 30 == 0 then
						changed = true
					end
				end
				if changed then
					applyFaction(f)
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Cierre del servidor: devolver el tiempo sobrante si NO se cerró por quedar vacío
---------------------------------------------------------------------
game:BindToClose(function()
	if #Players:GetPlayers() == 0 or not refundStore then
		return
	end
	local owed: { [string]: { [string]: number } } = {} -- uid -> grupo -> segundos
	for _, fl in pairs(lines) do
		for g, l in pairs(fl) do
			local total = 0
			for _, v in pairs(l.Buyers) do
				total += v
			end
			if l.Left > 60 and total > 0 then
				for uid, v in pairs(l.Buyers) do
					local share = math.floor(l.Left * v / total)
					if share > 0 then
						owed[uid] = owed[uid] or {}
						owed[uid][g] = (owed[uid][g] or 0) + share
					end
				end
			end
		end
	end
	local pendingWrites = 0
	for uid, groups in pairs(owed) do
		pendingWrites += 1
		task.spawn(function()
			pcall(function()
				local rs = refundStore :: DataStore
				rs:UpdateAsync(uid, function(old: any)
					local out: { [string]: number } = if typeof(old) == "table" then old else {}
					for g, secs in pairs(groups) do
						out[g] = math.min((out[g] or 0) + secs, ProductCatalog.BLESS_MAX_PERSONAL)
					end
					return out
				end)
			end)
			pendingWrites -= 1
		end)
	end
	local t0 = os.clock()
	while pendingWrites > 0 and os.clock() - t0 < 20 do
		task.wait(0.2)
	end
end)

---------------------------------------------------------------------
-- Jugadores: perfil + devoluciones pendientes
---------------------------------------------------------------------
PlayerData.RegisterSerializer("Blessing", function(player: Player): any?
	local pp = personal[player]
	if pp and next(pp) then
		local out: { [string]: number } = {}
		for g, v in pairs(pp) do
			out[g] = math.floor(v)
		end
		return { P = out }
	end
	return nil
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local pp: { [string]: number } = {}
	local raw: any = (saved :: any).Blessing
	if typeof(raw) == "table" and typeof(raw.P) == "table" then
		for g, v in pairs(raw.P) do
			if ProductCatalog.BlessGroups[g] and typeof(v) == "number" and v > 0 then
				pp[g] = math.min(v, ProductCatalog.BLESS_MAX_PERSONAL)
			end
		end
	end
	personal[player] = pp
	-- devoluciones por cierre de servidor (RemoveAsync devuelve lo que quitó: no se entrega dos veces)
	if refundStore then
		local ok, got = pcall(function()
			return (refundStore :: DataStore):RemoveAsync(tostring(player.UserId))
		end)
		if ok and typeof(got) == "table" and player.Parent then
			local any = false
			for g, secs in pairs(got) do
				if ProductCatalog.BlessGroups[g] and typeof(secs) == "number" and secs > 0 then
					pp[g] = math.min((pp[g] or 0) + secs, ProductCatalog.BLESS_MAX_PERSONAL)
					any = true
				end
			end
			if any then
				NotifyRemote:FireClient(player, "El servidor se cerró y te devolvimos el tiempo sobrante de tu bendición de facción (bendición personal).")
				PlayerData.Save(player)
			end
		end
	end
	apply(player)
	player:GetAttributeChangedSignal("Faction"):Connect(function()
		apply(player)
	end)
end

Players.PlayerAdded:Connect(function(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(init, pl)
end
PlayerData.Releasing:Connect(function(pl: Player)
	personal[pl] = nil
end)

return BlessingService
