--!strict
--[[
    DevChatClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DevChatClient
    Registra los comandos de prueba en el chat nuevo de Roblox (TextChatService) y los manda al servidor
    (DevCommands los ejecuta SOLO para administradores de AdminList). Comandos: /clase /nivel /xp /mob /mobs /limpiar /arena /cerrar /item /items /vida /dano /metin
]]
local TextChatService = game:GetService("TextChatService")

local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local remote = ClientNet.Get("DevCommand")
if not remote or TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
	return -- con el chat antiguo el servidor ya escucha Player.Chatted
end

-- solo los administradores (AdminList) registran los comandos: el servidor pone el atributo "AdminTitle" al entrar
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
if not RunService:IsStudio() then
	local t0 = os.clock()
	while me:GetAttribute("AdminTitle") == nil and os.clock() - t0 < 15 do
		task.wait(0.5)
	end
	if me:GetAttribute("AdminTitle") == nil then
		return
	end
end

for _, name in ipairs({ "clase", "nivel", "xp", "mob", "mobs", "limpiar", "arena", "cerrar", "item", "items", "vida", "dano", "metin", "boss", "tema", "rankpos" }) do
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev_" .. name
	cmd.PrimaryAlias = "/" .. name
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(_origin: TextSource, text: string)
		remote:FireServer(text)
	end)
end
print("[DevChatClient] Comandos de prueba registrados.")
