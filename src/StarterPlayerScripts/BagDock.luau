--!strict
--[[
    BagDock (ModuleScript) -> StarterPlayer > StarterPlayerScripts > BagDock
    Une la MOCHILA (InventoryClient) con el PERFIL (CharacterClient) en una sola ventana: el perfil crea un hueco ("host") y la mochila
    se acopla dentro. Cada script puede arrancar primero: el que llega segundo completa la unión.
      BagDock.Register(frame)  la mochila entrega su panel
      BagDock.Attach(host)     el perfil entrega su hueco (vuelve a llamarse cada vez que reconstruye su ventana)
      BagDock.Detach()         el perfil avisa antes de destruir su ventana (la mochila no se destruye con ella)
]]
local BagDock = {}
BagDock.Frame = nil :: Frame?
BagDock.Host = nil :: Instance?

local function dock()
	local f, h = BagDock.Frame, BagDock.Host
	if f and h then
		pcall(function()
			f.Parent = h
			f.Position = UDim2.fromScale(0, 0)
		end)
	end
end

function BagDock.Register(frame: Frame)
	BagDock.Frame = frame
	dock()
end

function BagDock.Attach(host: Instance)
	BagDock.Host = host
	dock()
end

function BagDock.Detach()
	BagDock.Host = nil
	local f = BagDock.Frame
	if f then
		pcall(function()
			f.Parent = nil
		end)
	end
end

return BagDock
