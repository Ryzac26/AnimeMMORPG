--!strict
--[[
    PlayerData (ModuleScript) -> ServerScriptService.Services.PlayerData
    ÚNICO dueño del DataStore de los jugadores. Un solo perfil por jugador (clave "P_<UserId>") con una sección por sistema:
        Progress  = { Level, XP }                      (LevelService)
        Class     = { Faction, Role }                  (ClassSelectService)
        Inventory = { Bag, Equip, Orphans }            (InventoryService)

    Cómo lo usa un servicio:
        local saved = PlayerData.WaitForData(player)   -- espera a que el perfil cargue; nil si falló o el jugador salió
        PlayerData.RegisterSerializer("Mi", function(player) return {...} end)   -- qué guardar (nil = no tocar esa sección)
        PlayerData.Releasing:Connect(function(player) ... end)                   -- limpia tu estado AQUÍ, no en PlayerRemoving
        PlayerData.Save(player)                        -- guardado inmediato (cambios importantes)

    Protecciones:
      - UpdateAsync (nunca SetAsync): no pisa datos si dos servidores tocan al mismo jugador.
      - BLOQUEO DE SESIÓN: el perfil queda marcado con el JobId del servidor. Otro servidor espera a que se libere
        (o a que el bloqueo "muera": sin latido durante LOCK_DEAD_AFTER segundos). Evita duplicar ítems al cambiar de servidor.
      - Si la carga falla en el juego publicado, el jugador es expulsado con un mensaje: JAMÁS se entra con datos vacíos
        que luego sobrescribirían el progreso real.
      - En Studio sin acceso a la API entra en modo "efímero" (juega, pero no guarda), como antes.
      - Migración automática, una sola vez, desde los stores antiguos PlayerProgress_v1 y ClassChoice_v1.
      - Al salir/cerrar: se toma la foto de los datos ANTES de avisar a los servicios (Releasing), así el orden de arranque
        o de cierre de los servicios no pierde nada.
]]
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local DataVersion = require(script.Parent.DataVersion)
local STORE_NAME = DataVersion.Name("PlayerData_v1")
-- stores antiguos (migración): con versión nueva apuntan a stores vacíos, así un reinicio no recupera niveles viejos
local LEGACY_PROGRESS_STORE = DataVersion.Name("PlayerProgress_v1")
local LEGACY_CLASS_STORE = DataVersion.Name("ClassChoice_v1")

local AUTOSAVE_INTERVAL = 120 -- s entre autoguardados (también sirve de "latido" del bloqueo)
local LOCK_DEAD_AFTER = 360 -- s sin latido: el servidor dueño se considera caído y otro puede tomar el perfil
local LOAD_ATTEMPTS = 12
local LOAD_RETRY_WAIT = 3
local SAVE_ATTEMPTS = 3
local SAVE_RETRY_WAIT = 2
local CLOSE_WAIT_MAX = 25 -- BindToClose da 30 s en total

local SESSION_ID: string = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

export type Data = { [string]: any }
type Session = {
	Status: string, -- "Loading" | "Ready" | "Failed"
	Data: Data,
	Ephemeral: boolean, -- true: este jugador no se guarda nunca (Studio sin API)
	Released: boolean,
	Saving: boolean,
}

local PlayerData = {}

local releasingEvent = Instance.new("BindableEvent")
PlayerData.Releasing = releasingEvent.Event :: RBXScriptSignal -- (player) tras tomar la foto final, antes de guardar

local sessions: { [Player]: Session } = {}
local serializers: { [string]: (Player) -> any? } = {}
local pendingWrites = 0
local finalWrites: { [number]: boolean } = {} -- UserIds con un guardado final en curso (una recarga rápida debe esperarlo)

local function getStore(name: string): DataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		return result :: DataStore
	end
	return nil
end

local store: DataStore? = getStore(STORE_NAME)

local function keyOf(userId: number): string
	return "P_" .. userId
end

---------------------------------------------------------------------
-- Migración desde los stores antiguos (solo se ejecuta una vez por jugador)
---------------------------------------------------------------------
local function readLegacy(storeName: string, userId: number): (boolean, any)
	local legacy = getStore(storeName)
	if not legacy then
		return false, nil
	end
	for attempt = 1, 3 do
		local ok, res = pcall(function()
			return (legacy :: DataStore):GetAsync(keyOf(userId))
		end)
		if ok then
			return true, res
		end
		task.wait(attempt)
	end
	return false, nil
end

local function migrateLegacy(userId: number, data: Data): boolean
	local okP, progress = readLegacy(LEGACY_PROGRESS_STORE, userId)
	local okC, class = readLegacy(LEGACY_CLASS_STORE, userId)
	if not (okP and okC) then
		return false -- no se pudo leer: NO damos el perfil por migrado (se reintenta)
	end
	if data.Progress == nil and typeof(progress) == "table" then
		data.Progress = { Level = tonumber(progress.Level) or 1, XP = tonumber(progress.XP) or 0 }
	end
	if data.Class == nil and typeof(class) == "table" and typeof(class.Faction) == "string" and typeof(class.Role) == "string" then
		data.Class = { Faction = class.Faction, Role = class.Role }
	end
	return true
end

---------------------------------------------------------------------
-- Lectura / escritura con bloqueo de sesión
---------------------------------------------------------------------
-- Libera el bloqueo sin tocar los datos (carga fallida o jugador que salió mientras cargaba)
local function unlock(userId: number)
	if not store then
		return
	end
	for _ = 1, SAVE_ATTEMPTS do
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(keyOf(userId), function(old: any)
				if typeof(old) == "table" and typeof(old.Lock) == "table" and old.Lock.JobId == SESSION_ID then
					old.Lock = nil
					return old
				end
				return nil
			end)
		end)
		if ok then
			return
		end
		task.wait(SAVE_RETRY_WAIT)
	end
end

-- Devuelve "ok" + datos, "locked" (otro servidor lo tiene) o "error"
local function tryLoad(userId: number): (string, Data?)
	-- "box": la función de UpdateAsync puede ejecutarse varias veces; manda el resultado de la última
	local box: { outcome: string, data: Data? } = { outcome = "error", data = nil }
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyOf(userId), function(old: any)
			local now = os.time()
			local current: Data = if typeof(old) == "table" then old else {}
			local lock = current.Lock
			if typeof(lock) == "table" and lock.JobId ~= SESSION_ID and typeof(lock.Time) == "number" and now - lock.Time < LOCK_DEAD_AFTER then
				box.outcome = "locked"
				box.data = nil
				return nil -- cancela: otro servidor tiene vivo este perfil
			end
			current.Lock = { JobId = SESSION_ID, Time = now }
			box.outcome = "ok"
			box.data = current
			return current
		end)
	end)
	if not ok then
		warn("[PlayerData] error al cargar " .. userId .. ": " .. tostring(err))
		return "error", nil
	end
	local data = box.data
	if box.outcome ~= "ok" or data == nil then
		return box.outcome, nil
	end
	if data.LegacyMigrated ~= true then
		if not migrateLegacy(userId, data) then
			unlock(userId)
			return "error", nil
		end
		data.LegacyMigrated = true
	end
	return "ok", data
end

local function write(userId: number, sections: { [string]: any }, release: boolean): boolean
	if not store then
		return false
	end
	pendingWrites += 1
	local success = false
	for attempt = 1, SAVE_ATTEMPTS do
		local box = { aborted = false }
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(keyOf(userId), function(old: any)
				local now = os.time()
				local current: Data = if typeof(old) == "table" then old else {}
				local lock = current.Lock
				if typeof(lock) == "table" and lock.JobId ~= SESSION_ID then
					box.aborted = true -- otro servidor tomó el perfil: no escribimos encima
					return nil
				end
				box.aborted = false
				for key, value in pairs(sections) do
					current[key] = value
				end
				current.LegacyMigrated = true
				current.LastSaved = now
				current.Lock = if release then nil else { JobId = SESSION_ID, Time = now }
				return current
			end)
		end)
		if ok then
			if box.aborted then
				warn("[PlayerData] guardado cancelado para " .. userId .. ": el perfil lo tiene otro servidor")
			end
			success = not box.aborted
			break
		end
		warn("[PlayerData] error al guardar " .. userId .. " (intento " .. attempt .. "): " .. tostring(err))
		if attempt < SAVE_ATTEMPTS then
			task.wait(SAVE_RETRY_WAIT)
		end
	end
	pendingWrites -= 1
	return success
end

---------------------------------------------------------------------
-- Foto de los datos del jugador
---------------------------------------------------------------------
-- Base = lo que se cargó (así una sección que su servicio aún no aplicó no se pierde) + lo que dicen los serializadores
local function buildSections(player: Player, s: Session): { [string]: any }
	local out: { [string]: any } = {}
	for key, value in pairs(s.Data) do
		if key ~= "Lock" and key ~= "LastSaved" then
			out[key] = value
		end
	end
	for section, fn in pairs(serializers) do
		local ok, value = pcall(fn, player)
		if not ok then
			warn("[PlayerData] serializador '" .. section .. "' falló: " .. tostring(value))
		elseif value ~= nil then
			out[section] = value
		end
	end
	return out
end

---------------------------------------------------------------------
-- API pública
---------------------------------------------------------------------
function PlayerData.RegisterSerializer(section: string, fn: (Player) -> any?)
	serializers[section] = fn
end

-- Espera a que el perfil esté listo. Devuelve los datos cargados (puede estar vacío en jugador nuevo) o nil si falló/salió.
function PlayerData.WaitForData(player: Player): Data?
	while player.Parent == Players do
		local s = sessions[player]
		if s then
			if s.Status == "Ready" then
				return s.Data
			elseif s.Status == "Failed" then
				return nil
			end
		end
		task.wait(0.1)
	end
	return nil
end

function PlayerData.IsReady(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.Status == "Ready"
end

-- Guarda ahora (sin liberar la sesión). Se ignora si ya hay un guardado en curso.
function PlayerData.Save(player: Player)
	local s = sessions[player]
	if not s or s.Status ~= "Ready" or s.Ephemeral or s.Released or s.Saving or not store then
		return
	end
	s.Saving = true
	local sections = buildSections(player, s)
	local userId = player.UserId
	task.spawn(function()
		write(userId, sections, false)
		s.Saving = false
	end)
end

local function release(player: Player)
	local s = sessions[player]
	if not s or s.Released then
		return
	end
	s.Released = true
	local userId = player.UserId
	local sections: { [string]: any }? = nil
	if s.Status == "Ready" and not s.Ephemeral and store then
		sections = buildSections(player, s) -- foto final ANTES de avisar a los servicios
	end
	releasingEvent:Fire(player)
	if sections then
		pendingWrites += 1 -- cubre el hueco hasta que write() empiece a contar
		finalWrites[userId] = true
		task.spawn(function()
			while s.Saving do
				task.wait(0.1) -- que un autoguardado en curso termine antes (la foto final es la más nueva)
			end
			write(userId, sections :: { [string]: any }, true)
			finalWrites[userId] = nil
			pendingWrites -= 1
			sessions[player] = nil
		end)
	elseif s.Status ~= "Loading" then
		sessions[player] = nil
	end
	-- Si aún estaba "Loading", loadSession se encarga de liberar el bloqueo cuando termine
end

local function loadSession(player: Player, s: Session)
	local userId = player.UserId
	if store == nil then
		s.Ephemeral = true
		s.Status = "Ready"
		return
	end

	-- Si este mismo jugador acaba de salir de este servidor y su guardado final sigue en curso, se espera (evita leer datos viejos)
	local waited = 0
	while finalWrites[userId] and waited < 30 do
		task.wait(0.1)
		waited += 0.1
	end

	local lastOutcome = "error"
	for _ = 1, LOAD_ATTEMPTS do
		if player.Parent == nil then
			break
		end
		local outcome, data = tryLoad(userId)
		lastOutcome = outcome
		if outcome == "ok" and data then
			if s.Released then
				unlock(userId) -- el jugador salió mientras cargaba
				sessions[player] = nil
				return
			end
			s.Data = data
			s.Status = "Ready"
			return
		end
		if RunService:IsStudio() and (outcome == "error" or outcome == "locked") then
			-- En Studio nunca expulsamos ni robamos un bloqueo ajeno: se juega SIN guardar y no se toca el perfil real
			if outcome == "locked" then
				warn("[PlayerData] Studio: el perfil sigue bloqueado por otra sesión (prueba anterior o servidor real). Se juega SIN guardar; el bloqueo caduca solo en unos minutos.")
			else
				warn("[PlayerData] Studio sin acceso a la API: se juega SIN guardar. (Activa 'Enable Studio Access to API Services' para probar el guardado.)")
			end
			s.Ephemeral = true
			s.Status = "Ready"
			return
		end
		task.wait(LOAD_RETRY_WAIT)
	end

	s.Status = "Failed"
	if s.Released then
		sessions[player] = nil
		return
	end
	if player.Parent then
		if lastOutcome == "locked" then
			player:Kick("Tu sesión anterior todavía se está guardando. Vuelve a entrar en unos segundos.")
		else
			player:Kick("No se pudo cargar tu progreso. Tus datos están a salvo: vuelve a entrar en unos minutos.")
		end
	end
end

local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end
	local s: Session = { Status = "Loading", Data = {}, Ephemeral = false, Released = false, Saving = false }
	sessions[player] = s
	task.spawn(loadSession, player, s)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, pl in ipairs(Players:GetPlayers()) do
	onPlayerAdded(pl)
end
Players.PlayerRemoving:Connect(release)

game:BindToClose(function()
	for _, pl in ipairs(Players:GetPlayers()) do
		release(pl)
	end
	local started = os.clock()
	while pendingWrites > 0 and os.clock() - started < CLOSE_WAIT_MAX do
		task.wait(0.2)
	end
end)

-- Autoguardado escalonado (también renueva el "latido" del bloqueo de sesión)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, pl in ipairs(Players:GetPlayers()) do
			PlayerData.Save(pl)
			task.wait(0.5)
		end
	end
end)

return PlayerData
