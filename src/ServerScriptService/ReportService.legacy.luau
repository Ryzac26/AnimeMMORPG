--!nonstrict
--[[
    ReportService (Script) -> ServerScriptService > ReportService
    REPORTES de jugadores/colaboradores. El jugador escribe el problema en el botón "REPORTAR" (ReportClient) y aquí se guarda con datos útiles
    (versión, personaje, nivel, atributos, posición, errores recientes del servidor y del cliente).
    Solo el DUEÑO del juego (game.CreatorId, o rango 254+ si el juego es de un grupo) y los de la lista ADMINS ven la ventana "Ver reportes"
    (en Studio siempre se ve). Los reportes se guardan en el DataStore "Reports_v1"; si no hay acceso (Studio sin API) se guardan en memoria.
    Remotes: ReportSubmit (cliente -> servidor, y respuesta) · ReportAdmin (lista / borrar, solo admins).
    Para dar acceso a otra persona: pon su UserId en ADMINS.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

local Net = require(ServerScriptService:WaitForChild("Services"):WaitForChild("Net"))
local SubmitRemote = Net.Get("ReportSubmit")
local AdminRemote = Net.Get("ReportAdmin")

local ADMINS: { [number]: boolean } = {} -- ej.: [123456789] = true
local COOLDOWN = 45 -- s entre reportes de un mismo jugador
local MAX_LEN = 600
local KEEP_LIST = 40 -- cuántos reportes se muestran en la ventana
local CATEGORIES = { Error = "Error", Visual = "Se ve mal", Balance = "Balance", Idea = "Idea" }

local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("Reports_v1")
end)
local mem: { [string]: any } = {} -- respaldo si el DataStore no responde
local counter = 0
local lastAt: { [Player]: number } = {}

-- últimos errores/avisos del servidor
local serverLog: { string } = {}
LogService.MessageOut:Connect(function(msg, kind)
	if kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning then
		table.insert(serverLog, (if kind == Enum.MessageType.MessageError then "[E] " else "[W] ") .. string.sub(msg, 1, 220))
		if #serverLog > 12 then
			table.remove(serverLog, 1)
		end
	end
end)

local function isAdmin(pl: Player): boolean
	if RunService:IsStudio() or ADMINS[pl.UserId] then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return pl.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return pl:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank >= 254
end

local function latestPatch(): string
	local best, bm, bn = "?", -1, -1
	local mods = ReplicatedStorage:FindFirstChild("Modules")
	local pn = mods and mods:FindFirstChild("PatchNotes")
	if pn then
		for _, c in ipairs(pn:GetChildren()) do
			local a, b = string.match(c.Name, "^v(%d+)_(%d+)$")
			if a and (tonumber(a) > bm or (tonumber(a) == bm and tonumber(b) > bn)) then
				bm, bn, best = tonumber(a), tonumber(b), c.Name
			end
		end
	end
	return best
end

-- solo datos útiles (nada del equipo): así el reporte es corto
local KEEP_WORDS = { "level", "faction", "role", "class", "char", "zone", "biome", "mount", "outfit", "strip" }

local function attrLines(inst: Instance?, skip: number): string
	if not inst then
		return "-"
	end
	local keys = {}
	for k, v in pairs(inst:GetAttributes()) do
		local t = typeof(v)
		local lk = string.lower(k)
		local okType = t == "string" or t == "number" or t == "boolean"
		local useful = false
		for _, w in ipairs(KEEP_WORDS) do
			if string.find(lk, w, 1, true) then
				useful = true
				break
			end
		end
		if okType and useful and not string.find(lk, "equip", 1, true) then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	local out = {}
	for i, k in ipairs(keys) do
		if i > 40 then
			break
		end
		local v = inst:GetAttribute(k)
		if typeof(v) == "number" then
			v = math.floor(v * 100) / 100
		end
		table.insert(out, k .. "=" .. string.sub(tostring(v), 1, 40))
	end
	return table.concat(out, ", ")
end

local function context(pl: Player, clientLog: any): string
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local pos = if root then string.format("%.0f, %.0f, %.0f", root.Position.X, root.Position.Y, root.Position.Z) else "sin personaje"
	local lines = {
		"Versión: " .. latestPatch(),
		"Jugador: " .. pl.Name .. " (" .. pl.UserId .. ") · cuenta de " .. pl.AccountAge .. " días",
		"Posición: " .. pos,
		"Atributos jugador: " .. attrLines(pl, 0),
		"Atributos personaje: " .. attrLines(char, 0),
		"Jugadores en el servidor: " .. #Players:GetPlayers(),
	}
	table.insert(lines, "Errores servidor: " .. (if #serverLog > 0 then "\n  " .. table.concat(serverLog, "\n  ") else "ninguno"))
	local cl = {}
	if typeof(clientLog) == "table" then
		for i = 1, math.min(#clientLog, 10) do
			if typeof(clientLog[i]) == "string" then
				table.insert(cl, string.sub(clientLog[i], 1, 220))
			end
		end
	end
	table.insert(lines, "Errores cliente: " .. (if #cl > 0 then "\n  " .. table.concat(cl, "\n  ") else "ninguno"))
	return table.concat(lines, "\n")
end

local function save(key: string, data: any)
	if store and not RunService:IsStudio() then
		local ok = pcall(function()
			store:SetAsync(key, data)
		end)
		if ok then
			return
		end
	end
	mem[key] = data
end

local function listAll(): { { Key: string, Data: any } }
	local keys: { string } = {}
	for k in pairs(mem) do
		table.insert(keys, k)
	end
	if store and not RunService:IsStudio() then
		pcall(function()
			local pages = store:ListKeysAsync("R")
			for _ = 1, 8 do
				for _, item in ipairs(pages:GetCurrentPage()) do
					table.insert(keys, item.KeyName)
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
		end)
	end
	table.sort(keys, function(a, b)
		return a > b
	end)
	local out = {}
	for i = 1, math.min(#keys, KEEP_LIST) do
		local k = keys[i]
		local d = mem[k]
		if d == nil and store then
			pcall(function()
				d = store:GetAsync(k)
			end)
		end
		if d then
			table.insert(out, { Key = k, Data = d })
		end
	end
	return out
end

local function format(list: { { Key: string, Data: any } }): string
	if #list == 0 then
		return "No hay reportes."
	end
	local parts = {}
	for i, it in ipairs(list) do
		local d = it.Data
		table.insert(parts, string.format("===== REPORTE %d · %s · %s =====\n%s\n\n%s", i, os.date("!%Y-%m-%d %H:%M", d.T or 0) .. " UTC", tostring(d.C), tostring(d.M), tostring(d.X)))
	end
	return table.concat(parts, "\n\n")
end

SubmitRemote.OnServerEvent:Connect(function(pl: Player, category: any, msg: any, clientLog: any)
	if typeof(msg) ~= "string" then
		return
	end
	msg = string.gsub(msg, "^%s+", "")
	msg = string.gsub(msg, "%s+$", "")
	if #msg < 5 then
		SubmitRemote:FireClient(pl, "short")
		return
	end
	local now = os.clock()
	if lastAt[pl] and now - lastAt[pl] < COOLDOWN then
		SubmitRemote:FireClient(pl, "wait", math.ceil(COOLDOWN - (now - lastAt[pl])))
		return
	end
	lastAt[pl] = now
	local cat = if typeof(category) == "string" and CATEGORIES[category] then CATEGORIES[category] else "Error"
	counter += 1
	local key = string.format("R%010d_%d_%d", os.time(), pl.UserId, counter)
	save(key, { T = os.time(), U = pl.UserId, C = cat, M = string.sub(msg, 1, MAX_LEN), X = context(pl, clientLog) })
	SubmitRemote:FireClient(pl, "ok")
end)

AdminRemote.OnServerEvent:Connect(function(pl: Player, action: any)
	if not isAdmin(pl) then
		return
	end
	if action == "clear" then
		for _, it in ipairs(listAll()) do
			mem[it.Key] = nil
			if store and not RunService:IsStudio() then
				pcall(function()
					store:RemoveAsync(it.Key)
				end)
			end
		end
	end
	local list = listAll()
	AdminRemote:FireClient(pl, "list", format(list), #list)
end)

local function mark(pl: Player)
	if isAdmin(pl) then
		pl:SetAttribute("ReportAdmin", true)
	end
end
Players.PlayerAdded:Connect(mark)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(mark, pl)
end
Players.PlayerRemoving:Connect(function(pl)
	lastAt[pl] = nil
end)
print("[ReportService] listo")
