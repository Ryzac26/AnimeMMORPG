--!strict
--[[
    MountAssets (ModuleScript) -> ReplicatedStorage.Modules.MountAssets
    MODELOS PROPIOS de las monturas. Por defecto está vacío: el juego arma cada montura con piezas (forma según la especie).
    Para usar un modelo tuyo: crea una carpeta "MountModels" dentro de ReplicatedStorage, mete un Model con el nombre exacto
    de la especie (Jabali, Ciervo, Sapo, Lobo, Corcel, Tortuga, Tigre, Oso, Medusa, Nube, Espectro, Alfombra) y listo.
    Reglas del modelo: con PrimaryPart (o una pieza llamada "Base"), apoyado en y = 0 al frente -Z (mirando hacia -Z),
    de unos 5 studs de alto. Se pinta del color de la rareza solo en las piezas llamadas "Tinte".
    Si quieres otra carpeta o un nombre distinto por especie, cámbialo aquí. Nunca se usan IDs de otros juegos.
]]
local MountAssets = {}

MountAssets.Folder = "MountModels"
-- nombre del modelo por especie (si no está aquí se usa el Id de la especie)
MountAssets.ModelName = {} :: { [string]: string }

return MountAssets
