--!strict
--[[
    WorldReadyService (ModuleScript) -> ServerScriptService.Services.WorldReadyService
    MUNDO LISTO: garantiza que el jugador NO juegue hasta que el mapa (ciudades + arena con su estilo) exista de verdad
    y le haya llegado completo a su pantalla. Resuelve el "tengo que reconectar varias veces hasta que carguen".

    Cadena de orden (todo por atributos de Workspace, sin depender de qué script arranca primero):
      1. ProjectBootstrapper construye el mapa y pone  MapBuilt = true
      2. CityStyler y ArenaStyler esperan MapBuilt, estilizan y ponen  CityStyleDone / ArenaStyleDone = true
      3. ESTE servicio espera las 3 marcas, cuenta los adornos de cada carpeta "Estilo" (atributo Count + tag "WorldStyle")
         y pone  WorldReady = true  (máx. WAIT_MAX s; si algo falló lo avisa en la consola y sigue, no deja el servidor colgado)
      4. LoadingScreen (cliente) muestra "Cargando el mundo..." hasta ver WorldReady y recibir todos los adornos;
         entonces avisa por el remote WorldLoaded.
      5. Hasta ese aviso el personaje del jugador queda QUIETO (anclado) en su ciudad: no cae al vacío ni lo atacan.
         Tope de seguridad: HOLD_MAX s, pase lo que pase se libera.
    Los Count se refrescan cada REFRESH s porque los temas de la Arena cambian sus adornos.
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Net = require(ServerScriptService.Services.Net)

local MAP_NAME = "Map_WC3_Style"
local WAIT_MAX = 90 -- s esperando que el mapa y los estilos terminen
local HOLD_MAX = 60 -- s máximo que un jugador espera quieto a que su pantalla cargue
local REFRESH = 10 -- s entre recuentos de adornos

local LoadedRemote = Net.Get("WorldLoaded")

local WorldReadyService = {}

local loaded: { [Player]: boolean } = {}

local function release(player: Player)
	loaded[player] = true
	local char = player.Character
	if char and char:GetAttribute("WorldHold") then
		char:SetAttribute("WorldHold", nil)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Anchored = false
		end
	end
end

local function hold(player: Player, char: Model)
	if loaded[player] then
		return
	end
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root or not root:IsA("BasePart") or loaded[player] then
		return
	end
	root.Anchored = true
	char:SetAttribute("WorldHold", true)
	task.delay(HOLD_MAX, function()
		if player.Parent and not loaded[player] then
			warn("[WorldReadyService] " .. player.Name .. ": su pantalla no confirmó la carga en " .. HOLD_MAX .. " s; se libera igual.")
			release(player)
		end
	end)
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(char)
		hold(player, char)
	end)
	if player.Character then
		task.spawn(hold, player, player.Character)
	end
end

LoadedRemote.OnServerEvent:Connect(function(player: Player)
	release(player)
end)
Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do
	watch(p)
end
Players.PlayerRemoving:Connect(function(p)
	loaded[p] = nil
end)

-- Cuenta los adornos de cada carpeta "Estilo" y los publica para que el cliente sepa cuánto debe llegarle
local function recount(): number
	local map = Workspace:FindFirstChild(MAP_NAME)
	local folders = 0
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("Folder") and d.Name == "Estilo" then
				d:SetAttribute("Count", #d:GetDescendants())
				if not CollectionService:HasTag(d, "WorldStyle") then
					CollectionService:AddTag(d, "WorldStyle")
				end
				folders += 1
			end
		end
	end
	Workspace:SetAttribute("WorldStyleFolders", folders)
	return folders
end

-- ¿Cuántas carpetas "Estilo" tiene el mapa ahora mismo? (sin tocar atributos)
local function countStyle(): number
	local map = Workspace:FindFirstChild(MAP_NAME)
	local n = 0
	if map then
		for _, d in ipairs(map:GetDescendants()) do
			if d:IsA("Folder") and d.Name == "Estilo" then
				n += 1
			end
		end
	end
	return n
end

local function stylers(): (any?, any?)
	local services = ServerScriptService:FindFirstChild("Services")
	local city, arena = nil, nil
	local c = services and services:FindFirstChild("CityStyler")
	local a = services and services:FindFirstChild("ArenaStyler")
	if c and c:IsA("ModuleScript") then
		local ok, m = pcall(require, c)
		city = if ok then m else nil
	end
	if a and a:IsA("ModuleScript") then
		local ok, m = pcall(require, a)
		arena = if ok then m else nil
	end
	return city, arena
end

local t0 = os.clock()
local function stamp(): string
	return string.format("t=%.1fs", os.clock() - t0)
end

-- Vigilancia del mapa: avisa si se construye más de una vez o si lo reemplazan/borran
Workspace.ChildAdded:Connect(function(child)
	if child.Name == MAP_NAME then
		print(string.format("[WorldReadyService] %s mapa AGREGADO a Workspace (construcciones=%s)", stamp(), tostring(Workspace:GetAttribute("MapBuildCount"))))
	end
end)
Workspace.ChildRemoved:Connect(function(child)
	if child.Name == MAP_NAME then
		warn(string.format("[WorldReadyService] %s mapa BORRADO de Workspace (construcciones=%s)", stamp(), tostring(Workspace:GetAttribute("MapBuildCount"))))
	end
end)

local healing = false
local function heal(reason: string)
	if healing then
		return
	end
	healing = true
	warn(string.format("[WorldReadyService] %s Reparando el estilo del mundo: %s", stamp(), reason))
	Workspace:SetAttribute("WorldReady", false)
	local city, arena = stylers()
	if city and city.Run then
		pcall(city.Run)
	end
	if arena and arena.Run then
		pcall(arena.Run)
	end
	recount()
	Workspace:SetAttribute("WorldReady", true)
	healing = false
end

task.spawn(function()
	local function marks(): (boolean, boolean, boolean)
		return Workspace:GetAttribute("MapBuilt") == true, Workspace:GetAttribute("CityStyleDone") == true, Workspace:GetAttribute("ArenaStyleDone") == true
	end
	while os.clock() - t0 < WAIT_MAX do
		local a, b, c = marks()
		if a and b and c then
			break
		end
		task.wait(0.25)
	end
	local a, b, c = marks()
	if not (a and b and c) then
		warn(string.format("[WorldReadyService] Tras %d s faltan marcas: MapBuilt=%s CityStyleDone=%s ArenaStyleDone=%s (¿falta actualizar ProjectBootstrapper / CityStyler / ArenaStyler?)", WAIT_MAX, tostring(a), tostring(b), tostring(c)))
	end
	local folders = recount()
	local builds = Workspace:GetAttribute("MapBuildCount")
	if typeof(builds) == "number" and builds > 1 then
		warn(string.format("[WorldReadyService] ¡El mapa se construyó %d veces! Hay un constructor duplicado (otro ProjectBootstrapper / MapBuilder en ServerScriptService). Borra el sobrante en Studio.", builds))
	end
	-- Si nadie dejó estilo (0 carpetas), se rehace antes de abrir el mundo
	if folders == 0 then
		heal("el mapa no tiene carpetas de estilo al arrancar")
		folders = countStyle()
	end
	Workspace:SetAttribute("WorldReady", true)
	print(string.format("[WorldReadyService] %s Mundo listo: %d carpetas de estilo, construcciones del mapa=%s.", stamp(), folders, tostring(builds)))

	-- Vigilancia: durante los primeros 2 min revisa cada 2 s que el estilo siga ahí; si se pierde, lo rehace (máx. 3 veces)
	local baseline = folders
	local repairs = 0
	local lastLogged = folders
	local tick0 = os.clock()
	while true do
		task.wait(if os.clock() - tick0 < 120 then 2 else REFRESH)
		local now = countStyle()
		if now ~= lastLogged then
			print(string.format("[WorldReadyService] %s carpetas de estilo: %d -> %d", stamp(), lastLogged, now))
			lastLogged = now
		end
		baseline = math.max(baseline, now)
		if baseline > 0 and now < baseline * 0.8 and repairs < 3 then
			repairs += 1
			heal(string.format("el estilo bajó de %d a %d carpetas", baseline, now))
			baseline = countStyle()
		elseif now > 0 then
			recount()
		end
	end
end)

return WorldReadyService
