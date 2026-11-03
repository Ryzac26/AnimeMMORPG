--!strict
--[[
    DailyLimits (ModuleScript) -> ServerScriptService.Services.DailyLimits
    LÍMITES DIARIOS por jugador y por franja (1..4), guardados en el perfil (sección "Daily" de PlayerData):
      "Keys"      llaves de cofre que ya cayeron hoy        (tope: LootTables.Daily.Keys)
      "Challenge" desafíos del altar con premio hoy         (LootTables.Daily.Challenge)
      "MiniBoss"  mini jefes con premio hoy                 (LootTables.Daily.MiniBoss)
    El día cambia a medianoche según LootTables.Daily.ResetUtcOffsetHours (-3 = Montevideo). Al cambiar el día:
      - los contadores vuelven a 0
      - las llaves de cofre que sobraron CADUCAN (no se acumulan para el día siguiente)
    API: Limit(kind, strip) · Used(player, kind, strip) · Remaining(player, kind, strip) · Use(player, kind, strip) -> true si había cupo
    Si el perfil aún no cargó, Remaining = 0 (no se regala nada por una carga lenta).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LootTables = require(ReplicatedStorage.Modules.LootTables)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Inventory = require(Services.InventoryService)

local KINDS = { "Keys", "Challenge", "MiniBoss" }
type State = { Day: string, Keys: { [string]: number }, Challenge: { [string]: number }, MiniBoss: { [string]: number } }

local states: { [Player]: State } = {}
local DailyLimits = {}

local function today(): string
	local t = os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600
	return os.date("!%Y-%m-%d", t)
end

local function emptyState(): State
	return { Day = today(), Keys = {}, Challenge = {}, MiniBoss = {} }
end

-- Si cambió el día: contadores a 0 y caducan las llaves que sobraron
local function refresh(player: Player): State?
	local st = states[player]
	if not st then
		return nil
	end
	local now = today()
	if st.Day ~= now then
		st.Day = now
		st.Keys, st.Challenge, st.MiniBoss = {}, {}, {}
		local expired = 0
		for strip = 1, 4 do
			local id = "Key_" .. strip
			local n = Inventory.Count(player, id)
			if n > 0 and Inventory.Consume(player, id, n) then
				expired += n
			end
		end
		if expired > 0 then
			Net.Get("Notify"):FireClient(player, "Nuevo día: tus llaves de cofre del día anterior caducaron")
		end
	end
	return st
end

function DailyLimits.Limit(kind: string, strip: number): number
	local list = (LootTables.Daily :: any)[kind]
	return if typeof(list) == "table" then (list[math.clamp(strip, 1, 4)] or 0) else 0
end

function DailyLimits.Used(player: Player, kind: string, strip: number): number
	local st = refresh(player)
	if not st then
		return math.huge
	end
	local bucket = (st :: any)[kind]
	return if typeof(bucket) == "table" then (bucket[tostring(strip)] or 0) else math.huge
end

function DailyLimits.Remaining(player: Player, kind: string, strip: number): number
	local used = DailyLimits.Used(player, kind, strip)
	return math.max(0, DailyLimits.Limit(kind, strip) - used)
end

function DailyLimits.Use(player: Player, kind: string, strip: number): boolean
	if DailyLimits.Remaining(player, kind, strip) <= 0 then
		return false
	end
	local st = states[player] :: State
	local bucket = (st :: any)[kind] :: { [string]: number }
	local key = tostring(strip)
	bucket[key] = (bucket[key] or 0) + 1
	return true
end

local function load(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local st = emptyState()
	local section: any = saved.Daily
	if typeof(section) == "table" and typeof(section.Day) == "string" then
		st.Day = section.Day
		for _, kind in ipairs(KINDS) do
			local src: any = section[kind]
			if typeof(src) == "table" then
				for k, v in pairs(src) do
					if typeof(k) == "string" and typeof(v) == "number" then
						((st :: any)[kind] :: { [string]: number })[k] = math.max(0, math.floor(v))
					end
				end
			end
		end
	end
	states[player] = st
	-- las llaves viven en la mochila: espera a que cargue para poder retirar las caducadas
	local waited = 0
	while not Inventory.Get(player) and waited < 40 and player.Parent do
		task.wait(0.5)
		waited += 0.5
	end
	refresh(player)
end

PlayerData.RegisterSerializer("Daily", function(player: Player): any?
	local st = states[player]
	if not st then
		return nil
	end
	return { Day = st.Day, Keys = table.clone(st.Keys), Challenge = table.clone(st.Challenge), MiniBoss = table.clone(st.MiniBoss) }
end)

PlayerData.Releasing:Connect(function(player: Player)
	states[player] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end

-- Medianoche con el juego abierto: reinicia a todos (y caducan las llaves) sin esperar a que vuelvan a usarlas
task.spawn(function()
	while true do
		task.wait(60)
		for pl in pairs(states) do
			refresh(pl)
		end
	end
end)

return DailyLimits
