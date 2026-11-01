--!strict
--[[
    Platform (ModuleScript) -> StarterPlayer > StarterPlayerScripts > Platform
    Platform.IsMobile(): true en celular/tablet táctil SIN teclado. Para probar la interfaz de celular en la PC:
    en Studio, selecciona Workspace y agrega el atributo ForceMobileUI (booleano) = true.
]]
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Platform = {}

function Platform.IsMobile(): boolean
	if Workspace:GetAttribute("ForceMobileUI") == true then
		return true
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

return Platform
