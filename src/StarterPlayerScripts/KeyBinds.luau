--!strict
--[[
    KeyBinds (ModuleScript) -> StarterPlayer > StarterPlayerScripts > KeyBinds
    Lee los atajos del jugador (atributo "Setting_Key_<Id>", guardado por SettingsService) con la tecla por defecto de KeyBindCatalog.
      KeyBinds.Matches(input, "Perfil")  -> true si esa pulsación es el atajo
      KeyBinds.Name(id) / KeyBinds.Label(id)  -> "C" / "1"
      KeyBinds.Set(id, "I")  -> cambia el atajo (si la tecla ya la usa otra acción, se intercambian)
      KeyBinds.Changed  -> evento (id) cuando cambia un atajo
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("KeyBindCatalog"))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))

local player = Players.LocalPlayer
local KeyBinds = {}

local changed = Instance.new("BindableEvent")
KeyBinds.Changed = changed.Event

local KEYPAD = {
	One = Enum.KeyCode.KeypadOne, Two = Enum.KeyCode.KeypadTwo, Three = Enum.KeyCode.KeypadThree, Four = Enum.KeyCode.KeypadFour,
	Five = Enum.KeyCode.KeypadFive, Six = Enum.KeyCode.KeypadSix, Seven = Enum.KeyCode.KeypadSeven, Eight = Enum.KeyCode.KeypadEight,
	Nine = Enum.KeyCode.KeypadNine, Zero = Enum.KeyCode.KeypadZero,
} :: { [string]: Enum.KeyCode }

function KeyBinds.Name(id: string): string
	local def = Catalog.ById[id]
	local v = player:GetAttribute("Setting_Key_" .. id)
	if typeof(v) == "string" and Catalog.IsAllowedKey(v) then
		return v
	end
	return if def then def.Default else ""
end

function KeyBinds.Label(id: string): string
	return Catalog.Display(KeyBinds.Name(id))
end

function KeyBinds.Get(id: string): Enum.KeyCode?
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[KeyBinds.Name(id)]
	end)
	return if ok then code else nil
end

function KeyBinds.Matches(input: InputObject, id: string): boolean
	local name = KeyBinds.Name(id)
	local code = KeyBinds.Get(id)
	if code and input.KeyCode == code then
		return true
	end
	local pad = KEYPAD[name]
	return pad ~= nil and input.KeyCode == pad
end

function KeyBinds.Set(id: string, keyName: string)
	if not Catalog.ById[id] or not Catalog.IsAllowedKey(keyName) then
		return
	end
	local remote = ClientNet.Get("SetSetting")
	local old = KeyBinds.Name(id)
	for _, a in ipairs(Catalog.Actions) do
		if a.Id ~= id and KeyBinds.Name(a.Id) == keyName then
			player:SetAttribute("Setting_Key_" .. a.Id, old) -- intercambio
			remote:FireServer("Key_" .. a.Id, old)
		end
	end
	player:SetAttribute("Setting_Key_" .. id, keyName)
	remote:FireServer("Key_" .. id, keyName)
end

function KeyBinds.Reset()
	local remote = ClientNet.Get("SetSetting")
	for _, a in ipairs(Catalog.Actions) do
		player:SetAttribute("Setting_Key_" .. a.Id, a.Default)
		remote:FireServer("Key_" .. a.Id, a.Default)
	end
end

player.AttributeChanged:Connect(function(attr: string)
	if string.sub(attr, 1, 12) == "Setting_Key_" then
		changed:Fire(string.sub(attr, 13))
	end
end)

return KeyBinds
