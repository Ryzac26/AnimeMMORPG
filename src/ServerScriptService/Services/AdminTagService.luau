--!strict
--[[
    AdminTagService (ModuleScript) -> ServerScriptService.Services.AdminTagService
    Publica en cada administrador (AdminList) los atributos "AdminTitle" (cargo) y "AdminKind" ("Owner"/"Admin"). Con ellos:
      - AdminTagClient dibuja el cartel sobre la cabeza de CADA cliente (así no se pierde si otro script limpia o reemplaza la cabeza del personaje),
      - DevChatClient registra los comandos solo a los admins.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AdminList = require(ReplicatedStorage.Modules.AdminList)

local function setup(player: Player)
	local entry = AdminList.Get(player)
	if not entry then
		return
	end
	player:SetAttribute("AdminTitle", entry.Title)
	player:SetAttribute("AdminKind", entry.Kind)
	print(string.format("[Admin] %s (%s) UserId=%d", player.Name, entry.Title, player.UserId))
end

Players.PlayerAdded:Connect(setup)
for _, p in ipairs(Players:GetPlayers()) do
	setup(p)
end

if RunService:IsStudio() then
	print("[AdminTagService] listo")
end

return {}
