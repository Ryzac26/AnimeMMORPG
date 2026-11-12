--!strict
--[[
    DevCommands (Script/Module) -> ServerScriptService.Services.DevCommands
    COMANDOS DE PRUEBA SOLO PARA ADMINISTRADORES (lista en ReplicatedStorage.Modules.AdminList; también en el juego publicado) y en Studio.
    Cualquier otro jugador que escriba un comando es ignorado. Cada uso queda en la Output del servidor ("[Admin] ...").
    Escribe en el chat:
      /nivel 1500        fija tu nivel (1-3000)
      /xp 5000           suma XP
      /mob Saiyan_Nappa 30   crea un enemigo delante de ti (nivel opcional)
      /mobs              lista los Id disponibles en la Output
      /limpiar           borra los enemigos activos
      /quien             lista la facción y el rol que ve el servidor de cada jugador
      /arena             abre el evento 1 HORA: puentes + compuertas + vidas de arena (vía ProjectBootstrapper)
      /cerrar            cierra el evento
      /clase Shinobi Asesino   cambia de facción/rol y reaparece
      /item Espada_Hierro 1    te da un objeto de prueba (/items lista los Id)
      /huevo 3           te da un huevo de montura (1..4 = franja)
      /montura Lobo Epico  te da esa montura · /listo termina la incubación
      /vida              te cura al máximo
      /dano 300          te hace daño (probar penalización por muerte)
]]
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminList = require(ReplicatedStorage.Modules.AdminList)

-- INTERRUPTORES del Fundador (panel en su pantalla): "Owner" = sus propios comandos, "Admin" = los de los administradores.
-- Con uno en OFF ese grupo juega normal (sus comandos se ignoran). Se guardan y valen para todos los servidores.
local switches: { [string]: boolean } = { Owner = true, Admin = true }

-- ¿Puede usar comandos? Admins de AdminList con su interruptor en ON (o cualquiera dentro de Studio, que es tu propia prueba)
local function allowed(player: Player): boolean
	local entry = AdminList.Get(player)
	if entry then
		return switches[entry.Kind] ~= false
	end
	return RunService:IsStudio()
end

local Services = ServerScriptService.Services
local LevelService = require(Services.LevelService)
local MobService = require(Services.Mobs.MobService)
local MetinService = require(Services.MetinService)
local BossService = require(Services.BossService)
local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local Inventory = require(Services.InventoryService)
local MountService = require(Services.MountService)

local lastBossCmd = 0
local function handle(player: Player, msg: string)
	if not allowed(player) then
		return
	end
	print(string.format("[Admin] %s: %s", player.Name, msg))
	local args = string.split(msg, " ")
	local cmd = string.lower(args[1] or "")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if cmd == "/nivel" then
		LevelService.SetLevel(player, tonumber(args[2]) or 1)
	elseif cmd == "/xp" then
		LevelService.AddXp(player, tonumber(args[2]) or 100)
	elseif cmd == "/mob" and root and root:IsA("BasePart") and args[2] then
		local m = MobService.SpawnAt(args[2], root.CFrame * CFrame.new(0, -3, -14), tonumber(args[3]))
		if not m then
			warn("Id de mob desconocido: " .. args[2] .. " (usa /mobs)")
		end
	elseif cmd == "/mobs" then
		for _, d in ipairs(MobCatalog.All) do
			print(string.format("%s  (Nv %d-%d)%s", d.Id, d.MinLevel, d.MaxLevel, if d.Boss then "  JEFE" else ""))
		end
	elseif cmd == "/metin" and root and root:IsA("BasePart") then
		-- /metin <Comun|PocoComun|Raro|Epico|Legendario>  -> crea una piedra Metin frente a ti (sin esperar el evento)
		MetinService.SpawnAt(args[2] or "Comun", (root.CFrame * CFrame.new(0, -3, -30)).Position)
	elseif cmd == "/boss" then
		-- (ignora repeticiones a menos de 2 s: un doble envío del chat lo invocaba y lo retiraba al instante)
		local nowT = os.clock()
		if nowT - lastBossCmd < 2 then
			return
		end
		lastBossCmd = nowT
		if BossService.IsActive() then
			BossService.Despawn("comando /boss")
		else
			BossService.Spawn()
		end
	elseif cmd == "/limpiar" then
		MobService.ClearAll()
	elseif cmd == "/arena" then
		Workspace:SetAttribute("EventForce", "Open") -- ProjectBootstrapper abre puentes y compuertas
		-- el evento de prueba dura 1 hora (el Bootstrapper pone 10 min; lo corregimos tras abrir)
		task.delay(1.5, function()
			if Workspace:GetAttribute("EventState") == "Open" then
				Workspace:SetAttribute("EventCountdown", 3600)
			end
		end)
	elseif cmd == "/cerrar" then
		Workspace:SetAttribute("EventForce", "Closed")
	elseif cmd == "/clase" then
		-- /clase Shinobi Asesino   (Facción: Saiyan|Shinobi|Pirate|Shinigami · Rol: Tanque|Guerrero|Asesino|Tirador|Mago|Curador)
		if args[2] and args[3] then
			-- normaliza mayúsculas y alias (pirata -> Pirate): un "pirata" mal escrito dejaba a dos amigos en facciones distintas
			local aliases: { [string]: string } = { saiyan = "Saiyan", shinobi = "Shinobi", pirate = "Pirate", pirata = "Pirate", shinigami = "Shinigami" }
			local fac = aliases[string.lower(args[2])]
			if not fac then
				print("Facción no válida: " .. args[2] .. " (usa Saiyan, Shinobi, Pirate o Shinigami)")
				return
			end
			local role = string.upper(string.sub(args[3], 1, 1)) .. string.lower(string.sub(args[3], 2))
			player:SetAttribute("Faction", fac)
			player:SetAttribute("Role", role)
			player:LoadCharacter()
		else
			print("Uso: /clase <Saiyan|Shinobi|Pirate|Shinigami> <Tanque|Guerrero|Asesino|Tirador|Mago|Curador>")
		end
	elseif cmd == "/quien" then
		-- lista la facción y el rol que el SERVIDOR ve en cada jugador (para revisar grupos y fuego amigo)
		for _, p in ipairs(Players:GetPlayers()) do
			local msg = string.format("%s · facción=%s · rol=%s", p.Name, tostring(p:GetAttribute("Faction")), tostring(p:GetAttribute("Role")))
			print("[/quien] " .. msg)
			require(Services.Net).Get("Notify"):FireClient(player, msg)
		end
	elseif cmd == "/item" and args[2] then
		Inventory.Add(player, args[2], tonumber(args[3]) or 1)
	elseif cmd == "/items" then
		for id, it in pairs(ItemCatalog.Items) do
			print(id, it.Name, it.Slot or "consumible")
		end
	elseif cmd == "/huevo" then
		MountService.GrantEgg(player, tonumber(args[2]) or 1, "Prueba") -- /huevo 1..4 (franja del huevo)
	elseif cmd == "/montura" and args[2] and args[3] then
		MountService.DevGrantMount(player, args[2], args[3]) -- /montura Lobo Epico
	elseif cmd == "/listo" then
		MountService.DevFinishIncubation(player) -- termina la incubación al instante
	elseif cmd == "/rankpos" and root and root:IsA("BasePart") then
		-- coloca el cartel del ranking global 16 studs delante de ti, mirándote; imprime el CFrame para dejarlo fijo en GlobalRankService.SPOTS
		local f = tostring(player:GetAttribute("Faction"))
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if look.Magnitude > 0.1 then
			look = look.Unit
			local ground = Vector3.new(root.Position.X, root.Position.Y - 3, root.Position.Z) + look * 16
			local cf = CFrame.lookAt(ground, ground - look)
			local ok, GR = pcall(function()
				return require(Services.GlobalRankService)
			end)
			if ok then
				(GR :: any).PlaceAt(f, cf)
				print(string.format("[RankPos] SPOTS.%s = CFrame.lookAt(Vector3.new(%.1f, %.1f, %.1f), Vector3.new(%.1f, %.1f, %.1f))", f, ground.X, ground.Y, ground.Z, ground.X - look.X, ground.Y, ground.Z - look.Z))
			end
		end
	elseif cmd == "/vida" and char then
		local h = char:FindFirstChildOfClass("Humanoid")
		if h then
			h.Health = h.MaxHealth
		end
	elseif cmd == "/dano" and char then
		local h = char:FindFirstChildOfClass("Humanoid")
		if h then
			h:TakeDamage(tonumber(args[2]) or 100)
		end
	end
end

-- Chat nuevo (TextChatService): los comandos se registran en el CLIENTE (DevChatClient) y llegan por este remote.
-- Chat antiguo: se escucha Player.Chatted. Solo admins (ver allowed).
local Net = require(Services.Net)
Net.Get("DevCommand").OnServerEvent:Connect(function(pl: Player, text: any)
	if typeof(text) == "string" and #text < 100 then
		handle(pl, text)
	end
end)

do
	local DataStoreService = game:GetService("DataStoreService")
	local store: DataStore? = nil
	pcall(function()
		store = DataStoreService:GetDataStore("AdminSwitch_v1")
	end)
	if store then
		pcall(function()
			local d: any = (store :: DataStore):GetAsync("state")
			if typeof(d) == "table" then
				if d.Owner == false then
					switches.Owner = false
				end
				if d.Admin == false then
					switches.Admin = false
				end
			end
		end)
	end
	local switchRemote = Net.Get("AdminSwitch")
	local notifyRemote = Net.Get("Notify")
	local function refresh(notice: boolean)
		for _, pl in ipairs(Players:GetPlayers()) do
			local entry = AdminList.Get(pl)
			if entry then
				local on = switches[entry.Kind] ~= false
				if pl:GetAttribute("AdminCmds") ~= on then
					pl:SetAttribute("AdminCmds", on)
					if notice and entry.Kind ~= "Owner" then
						notifyRemote:FireClient(pl, if on then "Tus comandos de administrador fueron ACTIVADOS." else "Tus comandos de administrador fueron DESACTIVADOS.")
					end
				end
				if entry.Kind == "Owner" then
					switchRemote:FireClient(pl, switches.Owner, switches.Admin)
				end
			end
		end
	end
	switchRemote.OnServerEvent:Connect(function(pl: Player, which: any)
		local entry = AdminList.Get(pl)
		if not entry or entry.Kind ~= "Owner" then
			return -- solo el Fundador maneja los interruptores
		end
		if which == "Owner" or which == "Admin" then
			switches[which] = not switches[which]
			if store then
				local snapshot = { Owner = switches.Owner, Admin = switches.Admin }
				task.spawn(function()
					pcall(function()
						(store :: DataStore):SetAsync("state", snapshot)
					end)
				end)
			end
			refresh(true)
		elseif which == "Sync" then
			switchRemote:FireClient(pl, switches.Owner, switches.Admin)
		end
	end)
	Players.PlayerAdded:Connect(function()
		task.delay(2, refresh, false)
	end)
	task.delay(2, refresh, false)
end

local function hook(pl: Player)
	pl.Chatted:Connect(function(msg)
		if string.sub(msg, 1, 1) == "/" then
			handle(pl, msg)
		end
	end)
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

return {}
