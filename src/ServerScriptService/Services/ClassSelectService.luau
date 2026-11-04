--!strict
--[[
    ClassSelectService (ModuleScript) -> ServerScriptService.Services.ClassSelectService
    SELECCIÓN DE FACCIÓN + ROL.
      - Al entrar: carga la elección guardada (PlayerData, sección "Class"). Si existe -> pone Faction/Role y ClassChosen=true.
        Si no existe (jugador nuevo) -> ClassChosen=false y el cliente muestra la pantalla de selección.
      - Remote "ChooseClass"(faction, role): el servidor valida contra FactionClassesModule, guarda,
        pone los atributos y reaparece al jugador en la ciudad de su facción (RespawnLocation lo fija ProjectBootstrapper).
      - Solo se puede elegir una vez. Para pruebas: workspace:SetAttribute("AllowReselect", true) permite volver a elegir
        Cambio de clase GRATIS: el Instructor de tu ciudad (InstructorService) llama a Allow(player) y el jugador puede elegir otro rol de SU facción.
        (y en Studio puedes borrar tu elección con player:SetAttribute("ClassChosen", false) desde la consola del servidor).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Net = require(ServerScriptService.Services.Net)
local PlayerData = require(ServerScriptService.Services.PlayerData)
local FactionClasses = require(ReplicatedStorage.Modules.FactionClassesModule)

local choose = Net.Get("ChooseClass")

local loaded: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}
local ClassSelect = {}
local tickets: { [Player]: number } = {} -- permiso de cambio de clase dado por el Instructor (vence a los 120 s)
local TICKET_SECONDS = 120

-- El Instructor de la ciudad da permiso para cambiar de rol (gratis) dentro de tu misma facción
function ClassSelect.Allow(player: Player)
	tickets[player] = os.clock() + TICKET_SECONDS
end

local function applyChoice(player: Player, faction: string, role: string)
	player:SetAttribute("Faction", faction)
	player:SetAttribute("Role", role)
	player:SetAttribute("ClassChosen", true)
end

-- Cambio de rol SIN ir al Instructor (pase Maestría Multiclase; lo llama MasteryService, que ya validó todo).
-- beforeSpawn se ejecuta con el rol nuevo ya puesto y antes de reaparecer (p. ej. para cambiar el equipo y que la vida salga bien).
function ClassSelect.SwitchRole(player: Player, role: string, beforeSpawn: (() -> ())?): boolean
	local faction = player:GetAttribute("Faction")
	if not loaded[player] or busy[player] or typeof(faction) ~= "string" or not FactionClasses.FindClass(faction, role) then
		return false
	end
	busy[player] = true
	applyChoice(player, faction, role)
	if beforeSpawn then
		beforeSpawn()
	end
	PlayerData.Save(player)
	task.wait(0.25)
	if player.Parent then
		player:LoadCharacter()
	end
	busy[player] = nil
	return true
end


local function load(player: Player)
	local data = PlayerData.WaitForData(player)
	if not data or player.Parent == nil then
		return -- la carga falló (el jugador es expulsado) o ya salió
	end
	local saved: any = data.Class
	if typeof(saved) == "table" and typeof(saved.Faction) == "string" and typeof(saved.Role) == "string"
		and FactionClasses.FindClass(saved.Faction, saved.Role) then
		applyChoice(player, saved.Faction, saved.Role)
		loaded[player] = true
		-- Si el personaje ya había aparecido ANTES de cargar tu perfil (con la facción por defecto: Goku, ciudad Saiyan),
		-- se hace reaparecer ya con tu clase guardada (traje y ciudad correctos). Si aún no aparecía, nace bien solo.
		local classData = FactionClasses.FindClass(saved.Faction, saved.Role)
		local wanted = if classData then classData.CharacterName else nil
		for _ = 1, 16 do
			local ch = player.Character
			local outfit = if ch then ch:GetAttribute("Outfit") else nil
			if outfit ~= nil then
				if outfit ~= wanted and player.Parent then
					task.wait(0.25) -- deja que ProjectBootstrapper actualice RespawnLocation de la facción guardada
					if player.Parent then
						player:LoadCharacter()
					end
				end
				break
			end
			task.wait(0.25)
		end
		return
	else
		player:SetAttribute("ClassChosen", false)
	end
	loaded[player] = true
end

-- Qué guarda PlayerData de este servicio (nil = todavía no hay elección: no se toca la sección)
PlayerData.RegisterSerializer("Class", function(player: Player): any?
	local faction = player:GetAttribute("Faction")
	local role = player:GetAttribute("Role")
	if player:GetAttribute("ClassChosen") == true and typeof(faction) == "string" and typeof(role) == "string" then
		return { Faction = faction, Role = role }
	end
	return nil
end)

choose.OnServerEvent:Connect(function(player: Player, faction: any, role: any)
	if not loaded[player] or busy[player] then
		return
	end
	if typeof(faction) ~= "string" or typeof(role) ~= "string" then
		return
	end
	if not FactionClasses.FindClass(faction, role) then
		return
	end
	if player:GetAttribute("ClassChosen") == true and Workspace:GetAttribute("AllowReselect") ~= true then
		-- cambio de clase: solo con permiso del Instructor, misma facción y otro rol
		local ticket = tickets[player]
		if not ticket or os.clock() > ticket or faction ~= player:GetAttribute("Faction") or role == player:GetAttribute("Role") then
			return
		end
		tickets[player] = nil
	end
	busy[player] = true
	applyChoice(player, faction, role)
	PlayerData.Save(player) -- la elección se guarda al instante
	task.wait(0.25) -- deja que ProjectBootstrapper actualice RespawnLocation de la nueva facción
	if player.Parent then
		player:LoadCharacter() -- reaparece en la ciudad de su facción con su clase nueva
	end
	busy[player] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end
-- PlayerData avisa DESPUÉS de tomar la foto final de datos: ahora sí se puede limpiar
PlayerData.Releasing:Connect(function(pl: Player)
	loaded[pl] = nil
	busy[pl] = nil
	tickets[pl] = nil
end)

return ClassSelect
