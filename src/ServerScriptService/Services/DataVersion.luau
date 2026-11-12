--!strict
--[[
    DataVersion (ModuleScript) -> ServerScriptService.Services.DataVersion
    VERSIÓN DE LOS DATOS del juego. Todos los DataStore (perfiles, rankings, gremios, casas...) añaden este sufijo a su nombre.
    Para REINICIAR TODO (todos los jugadores vuelven a empezar: nivel 1, sin facción ni clase, sin ítems):
      sube BETA en 1 y publica. Los datos antiguos NO se borran: quedan guardados con el nombre anterior (respaldo) y nadie los lee.
    Cuentas y compras de Robux (Game Passes) no se tocan: viven en Roblox.
]]
local DataVersion = {}

DataVersion.BETA = 1

function DataVersion.Name(base: string): string
	return base .. "_B" .. tostring(DataVersion.BETA)
end

return DataVersion
