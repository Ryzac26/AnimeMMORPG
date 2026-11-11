--!nonstrict
--[[
    FactionBalance (ModuleScript) -> ServerScriptService.Services.FactionBalance
    TOPE DE JUGADORES POR FACCIÓN EN CADA SERVIDOR (para que las 4 facciones estén parejas).
      - Tope por defecto: DEFAULT_CAP (15 por facción = 60 jugadores). Se puede cambiar SIN publicar desde Creator Hub > Configs:
        crea la config "factionCap" (número). Si no existe o falla la carga, se usa DEFAULT_CAP.
      - Solo se aplica en servidores públicos (los privados/reservados no tienen tope).
      - Publica en Workspace los atributos FactionCap y FactionCount_<Facción> (el cliente los muestra en la selección de facción).
      - Directorio entre servidores (MemoryStore "FactionServers"): cada servidor anota cuántos jugadores hay de cada facción.
        Si tu facción está llena aquí, FindServer devuelve otro servidor con lugar y Teleport te manda ahí.
        Si no hay ninguno (o estás en Studio) el tope es "suave": a quien ya tenía facción lo dejamos entrar, y a quien aún no eligió se le pide otra facción.
      - ADMINISTRADORES (AdminList): NO cuentan para el tope de su facción, nunca ven su facción "llena" y entran aunque el servidor tenga 60 jugadores.
        Configura el máximo de jugadores del lugar en 62: los 2 cupos extra son solo para admins (PUBLIC_MAX = 4 facciones × tope = 60 para el resto;
        un jugador normal que llegue cuando ya hay 60 se manda a otro servidor, o se le pide que reintente).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminList = require(ReplicatedStorage.Modules.AdminList)
local okCfg, ConfigService = pcall(function()
	return game:GetService("ConfigService") -- puede no existir en versiones viejas de Studio
end)

local FactionBalance = {}

local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local DEFAULT_CAP = 15
local HEARTBEAT = 20 -- cada cuántos s este servidor anota sus números en el directorio
local EXPIRE = 60 -- el aviso de un servidor caduca a los 60 s (si el servidor muere, desaparece solo)
local MARGIN = 1 -- al elegir otro servidor se exige que le sobre este margen (los números tienen hasta 20 s de retraso)

local cap = DEFAULT_CAP
local latestVersion = 0 -- versión de lugar más nueva que ven los demás servidores (la usa UpdateNotice)
local studio = RunService:IsStudio()

local function enforced(): boolean
	return game.PrivateServerId == ""
end

-- Tope desde Creator Hub > Configs (clave "factionCap"); sigue funcionando con el valor por defecto si no existe
task.spawn(function()
	if not okCfg then
		return
	end
	local ok, snapshot = pcall(function()
		return ConfigService:GetConfigAsync()
	end)
	if not ok or not snapshot then
		return
	end
	local function apply()
		local v = snapshot:GetValue("factionCap")
		if typeof(v) == "number" and v >= 1 then
			cap = math.floor(v)
		else
			cap = DEFAULT_CAP
		end
	end
	apply()
	pcall(function()
		snapshot.UpdateAvailable:Connect(function()
			snapshot:Refresh()
			apply()
		end)
	end)
end)

function FactionBalance.Cap(): number
	return cap
end

-- Jugadores de esa facción en ESTE servidor (sin contar a `exclude` ni a los administradores)
function FactionBalance.Count(faction: string, exclude: Player?): number
	local n = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= exclude and pl:GetAttribute("ClassChosen") == true and pl:GetAttribute("Faction") == faction and not AdminList.IsAdmin(pl) then
			n += 1
		end
	end
	return n
end

-- Jugadores NO administradores en este servidor (los admins usan los 2 cupos extra)
function FactionBalance.PublicCount(exclude: Player?): number
	local n = 0
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= exclude and not AdminList.IsAdmin(pl) then
			n += 1
		end
	end
	return n
end

-- Máximo de jugadores normales por servidor: 4 facciones × tope (15 × 4 = 60). El resto del cupo del lugar (62) es para admins.
function FactionBalance.PublicMax(): number
	return #FACTIONS * cap
end

function FactionBalance.IsFull(faction: string, player: Player?): boolean
	if player and AdminList.IsAdmin(player) then
		return false -- los admins entran a cualquier facción aunque esté llena y no ocupan su cupo
	end
	return enforced() and FactionBalance.Count(faction, player) >= cap
end

---------------------------------------------------------------------
-- Atributos para el cliente + directorio entre servidores
---------------------------------------------------------------------
local map: any = nil
if not studio and enforced() and game.JobId ~= "" then
	local ok, m = pcall(function()
		return MemoryStoreService:GetSortedMap("FactionServers")
	end)
	if ok then
		map = m
	end
end

local function counts(): { [string]: number }
	local c: { [string]: number } = {}
	for _, f in ipairs(FACTIONS) do
		c[f] = FactionBalance.Count(f, nil)
	end
	return c
end

task.spawn(function()
	local sinceBeat = HEARTBEAT
	while true do
		local c = counts()
		Workspace:SetAttribute("FactionCap", if enforced() then cap else 0)
		for f, n in pairs(c) do
			Workspace:SetAttribute("FactionCount_" .. f, n)
		end
		sinceBeat += 2
		if map and sinceBeat >= HEARTBEAT then
			sinceBeat = 0
			local value = { n = FactionBalance.PublicCount(nil), t = os.time(), pv = game.PlaceVersion } -- n = jugadores normales (sin admins)
			for f, n in pairs(c) do
				value[f] = n
			end
			pcall(function()
				map:SetAsync(game.JobId, value, EXPIRE)
			end)
			-- aprovecha para ver cuál es la versión más nueva en marcha
			local okR, items = pcall(function()
				return map:GetRangeAsync(Enum.SortDirection.Ascending, 100)
			end)
			if okR and typeof(items) == "table" then
				local best = game.PlaceVersion
				for _, it in ipairs(items) do
					if typeof(it.value) == "table" and typeof(it.value.pv) == "number" and it.value.pv > best then
						best = it.value.pv
					end
				end
				latestVersion = best
			end
		end
		task.wait(2)
	end
end)

game:BindToClose(function()
	if map then
		pcall(function()
			map:RemoveAsync(game.JobId)
		end)
	end
end)

function FactionBalance.LatestVersion(): number
	return math.max(latestVersion, game.PlaceVersion)
end

-- Otro servidor público con lugar en esa facción (nil si no hay o no se puede consultar). minVersion: solo servidores con esa versión o más nueva.
function FactionBalance.FindServer(faction: string, minVersion: number?): string?
	if not map then
		return nil
	end
	local ok, items = pcall(function()
		return map:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok or typeof(items) ~= "table" then
		return nil
	end
	local best: string? = nil
	local bestN = -1
	for _, it in ipairs(items) do
		local v = it.value
		if it.key ~= game.JobId and typeof(v) == "table" and (v.pv or 0) >= (minVersion or 0) and (v[faction] or 0) <= cap - 1 - MARGIN and (v.n or 0) <= FactionBalance.PublicMax() - 1 - MARGIN then
			if (v.n or 0) > bestN then -- el más lleno que aún tenga lugar (así se llenan en vez de repartirse en muchos vacíos)
				best, bestN = it.key, v.n or 0
			end
		end
	end
	return best
end

-- Manda al jugador a ese servidor. true = el viaje empezó (si falla, el jugador sigue aquí).
function FactionBalance.Teleport(player: Player, jobId: string): boolean
	if studio then
		return false
	end
	local ok = pcall(function()
		local opts = Instance.new("TeleportOptions")
		opts.ServerInstanceId = jobId
		TeleportService:TeleportAsync(game.PlaceId, { player }, opts)
	end)
	return ok
end

-- CUPO PARA ADMINS: si el servidor ya tiene el máximo de jugadores normales, un jugador normal que llegue no ocupa los 2 cupos reservados
local function gate(player: Player)
	if studio or not enforced() or AdminList.IsAdmin(player) then
		return
	end
	if FactionBalance.PublicCount(player) < FactionBalance.PublicMax() then
		return
	end
	local job = FactionBalance.FindServer("")
	if job and FactionBalance.Teleport(player, job) then
		return
	end
	player:Kick("El servidor está lleno. Vuelve a entrar en unos segundos para que te asignemos otro.")
end
Players.PlayerAdded:Connect(gate)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(gate, p)
end

return FactionBalance
