--!strict
--[[
    MenuBus (ModuleScript) -> StarterPlayer > StarterPlayerScripts > MenuBus
    Canal entre la BARRA DE MENÚ del HUD y las ventanas (perfil, mochila...). El menú hace MenuBus.Fire("Character") y la ventana
    correspondiente se abre/cierra. Así el menú no necesita conocer cómo se construye cada ventana.
]]
local event = Instance.new("BindableEvent")
local MenuBus = {}
MenuBus.Event = event.Event :: RBXScriptSignal
function MenuBus.Fire(name: string)
	event:Fire(name)
end
return MenuBus
