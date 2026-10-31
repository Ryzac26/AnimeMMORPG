--!strict
--[[
    DevChatClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DevChatClient
    Registra los comandos de prueba en el chat nuevo de Roblox (TextChatService) y los manda al servidor
    (DevCommands los ejecuta para todos los jugadores; se apagan con DEV_COMMANDS_FOR_ALL=false en el servidor). Comandos: /clase /nivel /xp /mob /mobs /limpiar /arena /cerrar /item /items /vida /dano /metin
]]
local TextChatService = game:GetService("TextChatService")

local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local remote = ClientNet.Get("DevCommand")
if not remote or TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
	return -- con el chat antiguo el servidor ya escucha Player.Chatted
end

for _, name in ipairs({ "clase", "nivel", "xp", "mob", "mobs", "limpiar", "arena", "cerrar", "item", "items", "vida", "dano", "metin", "boss", "tema" }) do
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev_" .. name
	cmd.PrimaryAlias = "/" .. name
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(_origin: TextSource, text: string)
		remote:FireServer(text)
	end)
end
print("[DevChatClient] Comandos de prueba registrados.")
