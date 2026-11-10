--!strict
--[[
    OffhandSkins (ModuleScript) -> ServerScriptService.Services.OffhandSkins
    Modelos 3D de la MANO SECUNDARIA: carcaj (Tirador), libro (Curador) y orbe (Mago), con el mismo estilo que las armas.
    Cada tipo tiene 6 mallas (una por TEMA de set: el tema sale del Tier, 2 tiers por tema) y 55 texturas (11 tiers x 5 rarezas).
      MESH[tipo][tema 1..6]      id de malla        TEX[tipo][tier 1..11][rareza 1..5]   id de textura (rarezas: Comun, Raro, Epico, Legendario, Mitico)
    Un id en 0 = ese objeto se dibuja con bloques (como antes). Mallas: +Y arriba, la tapa/frente mira a -Z.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local WeaponSkins = require(script.Parent.WeaponSkins)

local OffhandSkins = {}

-- ===== IDS (los rellena el equipo al subir las mallas y las imágenes) =====
OffhandSkins.MESH = {
	Quiver = { 85483268658140, 110259641135315, 76433088483724, 98214793463657, 114013771106923, 86420806876170 },
	Book = { 113778594176147, 127982397569378, 104003317272596, 109898810738578, 109734216492380, 96237172155741 },
	Orb = { 112127570391783, 118722644042170, 124270229728471, 134588153806382, 78654793104474, 79050268828530 },
}
OffhandSkins.TEX = {
	Quiver = {
		{ 129376731393835, 95889962681943, 125979261205409, 89469431941996, 112481444200139 }, -- Cobre
		{ 112744989398758, 70646774753517, 75801471198884, 112487984979515, 124592850812754 }, -- Bronce
		{ 75802685816569, 90370634949543, 97130393087200, 70407680314593, 77149791751853 }, -- Hierro
		{ 91964795650584, 97810786138116, 98232328393508, 91834828883321, 81479795961221 }, -- Acero
		{ 132170549964021, 95437672974250, 123527829530504, 125970602580332, 88222869005850 }, -- Plata
		{ 137402241224445, 106576194423803, 115756713748985, 77009927860615, 93934608304850 }, -- Oro
		{ 105296145364114, 115822089473162, 117349252574536, 97996264297732, 74121902040852 }, -- Platino
		{ 123715827075266, 129893255478485, 94799843838609, 117458943045340, 94217493415517 }, -- Cristal
		{ 119191902247551, 75756116617829, 71135180943140, 114951908795360, 87097946605013 }, -- Obsidiana
		{ 83066953517626, 138952548136434, 121274540491469, 74264557982001, 102443136517487 }, -- Celestial
		{ 100081645957853, 101773907708371, 105502122924647, 105260351738880, 94625749867320 }, -- Divino
	},
	Book = {
		{ 86868325797171, 133491549255643, 83289035357809, 117157496945964, 72347220523904 }, -- Cobre
		{ 137231599749074, 118193272819177, 99413571145929, 78059769251516, 116495669501220 }, -- Bronce
		{ 73633454392859, 116187874834817, 71867250127902, 97225448094050, 135614249939337 }, -- Hierro
		{ 98254170662380, 139492635535493, 76183500864587, 131233779564858, 137052934703193 }, -- Acero
		{ 113662318787819, 101583921530263, 133233598805128, 101033379778261, 104704395135467 }, -- Plata
		{ 86318803270053, 119037048059158, 87795426692363, 80712506623810, 131628229715425 }, -- Oro
		{ 108640121494460, 103937661213517, 92965547387894, 86347374185848, 104063802231407 }, -- Platino
		{ 91203648197900, 100165140663950, 137851436770323, 122510836126101, 131006052613517 }, -- Cristal
		{ 73422403534745, 118488352204723, 93895292215962, 94119743073110, 137682571828081 }, -- Obsidiana
		{ 0, 123111363944810, 86520565919174, 96204018818517, 87879986306791 }, -- Celestial
		{ 129403661892174, 137061067631360, 97996098588615, 90388035572480, 127371232736069 }, -- Divino
	},
	Orb = {
		{ 133994108390379, 116901922715879, 96455183045422, 106030379323377, 89660160746125 }, -- Cobre
		{ 132311717246273, 76267128616522, 110997181747003, 137737007187905, 85893862536283 }, -- Bronce
		{ 125639225843247, 78149251769462, 123598370050810, 127152180091031, 119160158661901 }, -- Hierro
		{ 87236684017351, 81276484047221, 79615419764213, 108983294467060, 122932132660709 }, -- Acero
		{ 113974067559365, 113340457495405, 109980289898704, 121210698348321, 93370225537725 }, -- Plata
		{ 115089251933779, 113046831557653, 86835847932417, 137351517884525, 136214699654676 }, -- Oro
		{ 106947097325236, 132663392208940, 92910963836186, 120729974633496, 80391396277297 }, -- Platino
		{ 122190695427248, 110550191746212, 119921747524729, 110433145324335, 119057501401486 }, -- Cristal
		{ 109729343438965, 119533138690236, 73740731123020, 78362771546647, 138354489985002 }, -- Obsidiana
		{ 130396068603083, 72725592572751, 103622872597046, 87463978171875, 118166215733294 }, -- Celestial
		{ 77131488294242, 114541979102272, 76509235359191, 124541749157496, 96032606060936 }, -- Divino
	},
}
-- ========================================================================

-- studs por unidad de la malla original (así todos los modelos de un tipo mantienen la misma escala entre sí)
OffhandSkins.UNIT = { Quiver = 1.013, Book = 1.07, Orb = 0.99 }
-- por malla: { dimensión mayor original, centro de la caja / dimensión mayor } (para que el cuerpo del objeto quede en el punto de agarre)
local DIM = {
	Quiver = { { 2.37, Vector3.new(0.0, 0.1287, -0.0021) }, { 2.26, Vector3.new(0.0, 0.1327, -0.0011) }, { 2.65, Vector3.new(0.0, 0.0472, -0.0) }, { 2.78, Vector3.new(0.0, 0.1295, 0.0) }, { 2.28, Vector3.new(0.0307, 0.136, -0.0046) }, { 2.51, Vector3.new(0.0, 0.1175, -0.006) } },
	Book = { { 1.4, Vector3.new(0.0, 0.0, -0.0357) }, { 1.4, Vector3.new(0.0, 0.0, -0.0286) }, { 1.925, Vector3.new(-0.0026, -0.1104, -0.0338) }, { 1.4, Vector3.new(0.0107, 0.0, -0.0357) }, { 1.72, Vector3.new(0.0233, 0.0, -0.0508) }, { 1.64, Vector3.new(0.0, 0.0732, -0.0762) } },
	Orb = { { 1.57, Vector3.new(0.0, -0.0096, 0.0) }, { 1.21, Vector3.new(-0.0, -0.1198, -0.0) }, { 1.5037, Vector3.new(0.0179, -0.0865, -0.0358) }, { 1.53, Vector3.new(0.0, -0.0229, 0.0) }, { 1.61, Vector3.new(0.0, 0.0714, 0.0) }, { 1.96, Vector3.new(0.0, 0.0, 0.0) } },
}

local function idx(item: any): (number, number)
	local tiers = math.max(1, #GearCatalog.TierLevels)
	local tier = if typeof(item) == "table" and typeof(item.Tier) == "number" then item.Tier else 1
	tier = math.clamp(tier, 1, tiers)
	local rar = if typeof(item) == "table" then (table.find(GearCatalog.Rarities, item.Rarity) or 1) else 1
	return tier, rar
end

-- Pone el objeto pegado a `to` con el CFrame `cf` (la posición del cuerpo del objeto). true = quedó puesto;
-- false = sin id, aún carga (se llama onReady al terminar) o no carga → quien llama dibuja los bloques.
function OffhandSkins.Attach(parent: Instance, to: BasePart, kind: string, item: any, cf: CFrame, onReady: (() -> ())?): boolean
	local tier, rar = idx(item)
	local variant = math.clamp((tier + 1) // 2, 1, 6)
	local id = OffhandSkins.MESH[kind][variant]
	local dims = DIM[kind][variant]
	if not id or id == 0 or not dims then
		return false
	end
	local mp = WeaponSkins.MeshFor(id, onReady)
	if not mp then
		return false -- nil = cargando, false = no carga
	end
	local piece: MeshPart = mp:Clone()
	local native = piece.Size
	local final = dims[1] * OffhandSkins.UNIT[kind]
	piece.Size = native * (final / math.max(native.X, native.Y, native.Z))
	local row = OffhandSkins.TEX[kind][tier]
	local tex = if row then row[rar] else 0
	if row and (not tex or tex == 0) then
		for _, alt in ipairs(row) do -- si falta la imagen de esta rareza se usa la de otra del mismo tier
			if alt ~= 0 then
				tex = alt
				break
			end
		end
	end
	if tex and tex ~= 0 then
		piece.TextureID = "rbxassetid://" .. tex
	end
	piece.Name = "WeaponPart"
	piece.Anchored = false
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
	piece.Material = Enum.Material.SmoothPlastic
	piece.Parent = parent
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = piece
	w.C0 = cf * CFrame.new(dims[2] * final)
	w.Parent = piece
	return true
end

return OffhandSkins
