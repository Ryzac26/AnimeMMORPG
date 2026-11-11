--!nonstrict
--[[
    UpdateNotice (ModuleScript) -> ServerScriptService.Services.UpdateNotice
    AVISO DE ACTUALIZACIÓN + BOTÓN "CAMBIAR DE SERVIDOR".
      · Reinicio programado: cuando en Creator Hub > Servidor > Reiniciar servidores pones una DEMORA, Roblox avisa a cada servidor viejo con
        game.ServerRestartScheduled. Aquí se publica la hora en Workspace (UpdateRestartAt, UpdateMsg) y UpdateNoticeClient muestra la franja con cuenta atrás.
      · Versión nueva SIN reinicio: FactionBalance anota la versión de cada servidor en el directorio; si hay una más nueva se pone UpdateNewVersion = true.
      · Remote "UpdateSwitch" (botón): guarda el progreso y manda al jugador a un servidor con la versión nueva:
          con reinicio programado -> viaje normal (Roblox ya no manda jugadores nuevos a los servidores que se van a cerrar);
          sin reinicio -> a un servidor con versión más nueva Y lugar en su facción (FactionBalance.FindServer); si aún no hay, se le avisa.
    En Studio solo se ve el aviso (los viajes no funcionan).
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local FactionBalance = require(ServerScriptService.Services.FactionBalance)

local UpdateNotice = {}

local switchR = Net.Get("UpdateSwitch")
local notify = Net.Get("Notify")
local restartAt: number? = nil
local lastTry: { [Player]: number } = {}

-- 1) reinicio programado (avisa Roblox)
pcall(function()
	game.ServerRestartScheduled:Connect(function(restartTime, source, attributes)
		local ts = restartTime.UnixTimestamp
		restartAt = ts
		Workspace:SetAttribute("UpdateRestartAt", ts)
		local m = ""
		if typeof(attributes) == "table" and typeof(attributes.message) == "string" then
			m = string.sub(attributes.message, 1, 400) -- el cartel lo desplaza como letrero (marquesina), así que cabe un mensaje largo
		end
		Workspace:SetAttribute("UpdateMsg", m)
	end)
end)

-- 2) versión nueva en marcha (sin reinicio)
task.spawn(function()
	while true do
		task.wait(30)
		if not restartAt then
			Workspace:SetAttribute("UpdateNewVersion", FactionBalance.LatestVersion() > game.PlaceVersion)
		end
	end
end)

-- 3) botón "Cambiar de servidor"
switchR.OnServerEvent:Connect(function(player: Player)
	local now = os.clock()
	if lastTry[player] and now - lastTry[player] < 15 then
		return
	end
	lastTry[player] = now
	if RunService:IsStudio() then
		notify:FireClient(player, "El cambio de servidor solo funciona en el juego publicado.")
		return
	end
	pcall(function()
		PlayerData.Save(player) -- el progreso queda guardado antes de viajar
	end)
	if restartAt then
		local ok = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, { player })
		end)
		if not ok then
			notify:FireClient(player, "No se pudo cambiar de servidor ahora; inténtalo otra vez en unos segundos (o espera al reinicio).")
		end
		return
	end
	local latest = FactionBalance.LatestVersion()
	if latest > game.PlaceVersion then
		local faction = player:GetAttribute("Faction")
		local job = FactionBalance.FindServer(if typeof(faction) == "string" then faction else "", latest)
		if job and FactionBalance.Teleport(player, job) then
			return
		end
		notify:FireClient(player, "Todavía no hay un servidor con la versión nueva y lugar para tu facción. Inténtalo en unos minutos.")
	else
		notify:FireClient(player, "Ya estás en la versión más nueva.")
	end
end)

Players.PlayerRemoving:Connect(function(pl)
	lastTry[pl] = nil
end)

return UpdateNotice
