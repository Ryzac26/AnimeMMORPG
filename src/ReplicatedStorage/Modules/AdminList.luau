--!strict
--[[
    AdminList (ModuleScript) -> ReplicatedStorage.Modules.AdminList
    ADMINISTRADORES del juego: SOLO ellos pueden usar los comandos de prueba (/nivel, /mob, /item...) y llevan un cartel sobre la cabeza con su cargo.
    Para añadir un admin: agrégalo a Admins con su nombre de usuario (sin importar mayúsculas), su cargo y el color del cartel.
    MÁS SEGURO: cuando entre un admin, la Output del servidor imprime "[Admin] <nombre> UserId=<número>". Pega ese número en UserIds y el admin
    queda atado a su cuenta aunque cambie de nombre de usuario.
    El DUEÑO de la experiencia (game.CreatorId, si es una cuenta y no un grupo) siempre es admin con el cargo de Soberano.
]]
local AdminList = {}

export type Entry = { Title: string, Color: Color3, Kind: string } -- Kind: "Owner" (Soberano) o "Admin"

AdminList.Owner = { Title = "Soberano Fundador", Color = Color3.fromRGB(255, 205, 80), Kind = "Owner" } :: Entry

-- por nombre de usuario (en minúsculas)
AdminList.Admins = {
	ryzacuru = AdminList.Owner,
	zcrulax = { Title = "Administrador", Color = Color3.fromRGB(110, 210, 255), Kind = "Admin" },
} :: { [string]: Entry }

-- por UserId (más seguro). Ejemplo: [123456789] = AdminList.Admins.zcrulax,
AdminList.UserIds = {} :: { [number]: Entry }

function AdminList.Get(player: Player): Entry?
	if game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId and game.CreatorId > 0 then
		return AdminList.Owner
	end
	return AdminList.UserIds[player.UserId] or AdminList.Admins[string.lower(player.Name)]
end

function AdminList.IsAdmin(player: Player): boolean
	return AdminList.Get(player) ~= nil
end

return AdminList
