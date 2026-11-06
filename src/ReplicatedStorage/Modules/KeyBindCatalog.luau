--!strict
--[[
    KeyBindCatalog (ModuleScript) -> ReplicatedStorage.Modules.KeyBindCatalog
    ATAJOS de teclado configurables (Ajustes > Atajos de teclado). Cada acción tiene una tecla por defecto; el jugador puede cambiarla.
    Se guardan en el perfil como ajustes "Key_<Id>" = nombre de la tecla (SettingsService los valida con esta lista).
    Teclas reservadas (no se pueden asignar): W A S D (mover), E (interactuar), Espacio.
]]
local KeyBindCatalog = {}

export type Action = { Id: string, Label: string, Default: string, Group: string, Short: string }

KeyBindCatalog.Actions = {
	{ Id = "Perfil", Label = "Perfil y mochila", Default = "C", Group = "Ventanas", Short = "Perfil" },
	{ Id = "Mochila", Label = "Mochila", Default = "B", Group = "Ventanas", Short = "Mochila" },
	{ Id = "Faccion", Label = "Facción (gremio)", Default = "G", Group = "Ventanas", Short = "Facción" },
	{ Id = "Mercader", Label = "Mercader", Default = "V", Group = "Ventanas", Short = "Mercader" },
	{ Id = "Maestria", Label = "Maestría de rol", Default = "N", Group = "Ventanas", Short = "Maestría" },
	{ Id = "Grupo", Label = "Grupo e invitaciones", Default = "P", Group = "Ventanas", Short = "Grupo" },
	{ Id = "Notas", Label = "Novedades del parche", Default = "J", Group = "Ventanas", Short = "Novedades" },
	{ Id = "AutoFarm", Label = "Auto-farmeo", Default = "Z", Group = "Combate", Short = "Auto-farm" },
	{ Id = "AutoAtaque", Label = "Pausar auto-ataque", Default = "Q", Group = "Combate", Short = "Auto-atq" },
	{ Id = "Montura", Label = "Montar / bajar de la montura", Default = "H", Group = "Combate", Short = "Montura" },
	{ Id = "Poder1", Label = "Poder 1", Default = "One", Group = "Poderes", Short = "Poder 1" },
	{ Id = "Poder2", Label = "Poder 2", Default = "Two", Group = "Poderes", Short = "Poder 2" },
	{ Id = "Poder3", Label = "Poder 3", Default = "Three", Group = "Poderes", Short = "Poder 3" },
	{ Id = "Poder4", Label = "Poder 4", Default = "Four", Group = "Poderes", Short = "Poder 4" },
	{ Id = "Poder5", Label = "Poder 5", Default = "Five", Group = "Poderes", Short = "Poder 5" },
	{ Id = "Poder6", Label = "Poder 6", Default = "Six", Group = "Poderes", Short = "Poder 6" },
	{ Id = "Poder7", Label = "Poder 7 · Primeros Auxilios", Default = "Seven", Group = "Poderes", Short = "Poder 7" },
} :: { Action }

KeyBindCatalog.ById = {} :: { [string]: Action }
for _, a in ipairs(KeyBindCatalog.Actions) do
	KeyBindCatalog.ById[a.Id] = a
end

-- Filas del teclado visual y teclas permitidas
KeyBindCatalog.Rows = {
	{ "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero" },
	{ "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P" },
	{ "A", "S", "D", "F", "G", "H", "J", "K", "L" },
	{ "Z", "X", "C", "V", "B", "N", "M" },
} :: { { string } }
KeyBindCatalog.Reserved = { W = "Mover", A = "Mover", S = "Mover", D = "Mover", E = "Interactuar" } :: { [string]: string }

local DIGITS = { One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0" }

function KeyBindCatalog.Display(name: string): string
	return DIGITS[name] or name
end

local allowed: { [string]: boolean } = {}
for _, row in ipairs(KeyBindCatalog.Rows) do
	for _, k in ipairs(row) do
		if not KeyBindCatalog.Reserved[k] then
			allowed[k] = true
		end
	end
end
function KeyBindCatalog.IsAllowedKey(name: any): boolean
	return typeof(name) == "string" and allowed[name] == true
end

return KeyBindCatalog
