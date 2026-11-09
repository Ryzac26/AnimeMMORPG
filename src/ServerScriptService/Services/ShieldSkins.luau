--!nonstrict
--[[
    ShieldSkins (ModuleScript) -> ServerScriptService.Services.ShieldSkins
    ESCUDOS 3D para Tanque y Guerrero (y el escudo genérico). Cada escudo es un conjunto de piezas (mallas + bloques) con su posición,
    tamaño, color y material copiados del modelo original; solo se usan las MALLAS (por id) y bloques, los scripts del paquete NO.
    Las mallas se crean con AssetService (usa la caché de WeaponSkins). Si alguna NO carga, AttackAnimator dibuja el escudo de bloques de siempre.
    Reparto: igual que las armas, por Tier y Rareza de la pieza (de menos a más vistoso; edita SHIELDS para cambiar el orden o quitar).
    Ajustes (arriba):
      GRIP        punto del escudo (sin escalar) donde va la mano: entre las dos asas, en la cara de atrás
      GRIP_SHIFT  desplazamiento respecto a la mano (Y sube/baja el escudo, X izquierda/derecha, Z adelante/atrás)
      FACE        math.pi = la cara con emblema mira hacia delante; si se ve el revés cambia a 0
    El alto final lo pasa AttackAnimator (Tanque 3.6, Guerrero 3.1, genérico 2.6 studs).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local WeaponSkins = require(script.Parent.WeaponSkins)

local ShieldSkins = {}

local GRIP = Vector3.new(0, 0.52, -0.578)
local GRIP_SHIFT = Vector3.new(0, 0.3, -0.6) -- Z negativa = más adelante
local FACE = math.pi
local BASE_HEIGHT = 11.797 -- alto original de la placa base

-- S = tamaño original, C = color, P = CFrame relativa a la placa base (12 números). De menos a más vistoso.
local SHIELDS = {
	{ Name = "Baelish", Parts = {
		{ M = 14808191252, S = { 3.188, 4.580, 0.156 }, C = { 17, 17, 17 }, Mat = "Metal", P = { 0.011, 0.467, 0.019, -1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, -1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.636, 0.509, -0.578, 1.000, -0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.628, 0.536, -0.578, -1.000, 0.000, -0.000, -0.000, -1.000, 0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000, 0.000, -0.000, 0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 75, 151, 75 }, Mat = "Metal", P = { -0.000, -0.008, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000, 0.000, -0.000, 0.000, 1.000 } },
	} },
	{ Name = "Dothraki", Parts = {
		{ M = 14816867099, S = { 1.857, 4.307, 0.124 }, C = { 86, 66, 54 }, Mat = "Metal", P = { 0.880, 1.145, 0.034, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, -0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.636, 0.509, -0.578, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.628, 0.536, -0.578, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 226, 155, 64 }, Mat = "Metal", P = { 0.000, -0.008, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 14816867099, S = { 1.857, 4.307, 0.124 }, C = { 86, 66, 54 }, Mat = "Metal", P = { -0.986, 1.145, 0.034, -1.000, 0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
	} },
	{ Name = "Violeta", Parts = {
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, -0.000, 0.000, -0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 15997159607, S = { 4.031, 4.337, 0.153 }, C = { 123, 47, 123 }, Mat = "Metal", P = { -0.445, 0.615, 0.040, -1.000, -0.000, -0.000, -0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.636, 0.509, -0.578, 1.000, -0.000, 0.000, 0.000, 1.000, 0.000, 0.000, -0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.629, 0.536, -0.578, -1.000, 0.000, 0.000, -0.000, -1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.000, -0.008, 0.000, 1.000, -0.000, 0.000, -0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 15997161289, S = { 0.978, 1.324, 0.072 }, C = { 248, 248, 248 }, Mat = "Metal", P = { 0.865, 3.114, 0.075, -1.000, -0.000, -0.000, -0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
	} },
	{ Name = "Sol azul", Parts = {
		{ M = 16039904039, S = { 1.451, 3.578, 0.159 }, C = { 51, 88, 130 }, Mat = "Metal", P = { -1.639, 1.220, 0.016, -1.000, 0.000, -0.000, -0.000, 1.000, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 13400599153, S = { 1.728, 1.671, 0.025 }, C = { 51, 88, 130 }, Mat = "Metal", P = { -0.291, 0.329, 0.082, -1.000, 0.000, -0.000, -0.000, 1.000, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.643, 0.509, -0.557, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.622, 0.536, -0.557, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, -0.000, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, -0.008, -0.000, 1.000, 0.000, -0.000, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 16039900131, S = { 3.539, 4.381, 0.081 }, C = { 231, 231, 236 }, Mat = "Metal", P = { 0.187, 0.963, 0.060, -1.000, 0.000, -0.000, -0.000, 1.000, -0.000, 0.000, -0.000, -1.000 } },
	} },
	{ Name = "Wylde", Parts = {
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.641, 0.509, -0.558, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.624, 0.536, -0.557, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 16253069344, S = { 4.899, 4.918, 0.196 }, C = { 0, 143, 156 }, Mat = "Metal", P = { 0.027, 0.892, 0.010, -1.000, 0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, -1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 245, 205, 48 }, Mat = "Metal", P = { 0.000, -0.008, -0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
	} },
	{ Name = "Lorch", Parts = {
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.636, 0.509, -0.578, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, -0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.629, 0.536, -0.578, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, 0.000, 1.000 } },
		{ M = 16178125537, S = { 3.669, 3.954, 0.074 }, C = { 17, 17, 17 }, Mat = "Metal", P = { 0.252, -0.240, -0.013, -1.000, 0.000, 0.000, 0.000, 1.000, 0.000, -0.000, 0.000, -1.000 } },
		{ Shape = "Cylinder", S = { 0.093, 1.513, 1.513 }, C = { 245, 205, 48 }, Mat = "Metal", P = { -2.186, 3.095, -0.006, 0.000, 1.000, -0.000, 0.000, -0.000, -1.000, -1.000, 0.000, -0.000 } },
		{ Shape = "Cylinder", S = { 0.093, 1.513, 1.513 }, C = { 245, 205, 48 }, Mat = "Metal", P = { -0.002, 3.095, -0.006, 0.000, 1.000, -0.000, 0.000, -0.000, -1.000, -1.000, 0.000, -0.000 } },
		{ Shape = "Cylinder", S = { 0.093, 1.513, 1.513 }, C = { 245, 205, 48 }, Mat = "Metal", P = { 2.071, 3.095, -0.006, 0.000, 1.000, -0.000, 0.000, -0.000, -1.000, -1.000, 0.000, -0.000 } },
	} },
	{ Name = "Dragon verde", Parts = {
		{ Shape = "Block", S = { 0.183, 0.223, 0.001 }, C = { 248, 248, 248 }, Mat = "Neon", P = { -2.059, 1.614, 0.135, -0.934, 0.358, -0.000, 0.358, 0.934, -0.000, 0.000, -0.000, -1.000 } },
		{ Shape = "Block", S = { 0.183, 0.135, 0.001 }, C = { 44, 101, 29 }, Mat = "Neon", P = { -1.171, 2.600, 0.145, -0.934, 0.358, -0.000, 0.358, 0.934, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, -0.000, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 17, 17, 17 }, Mat = "Metal", P = { 0.000, -0.008, -0.000, 1.000, 0.000, -0.000, 0.000, 1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 15922629676, S = { 4.852, 4.212, 0.080 }, C = { 245, 205, 48 }, Mat = "Metal", P = { 0.065, 0.209, 0.097, -1.000, 0.000, -0.000, -0.000, 1.000, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 15922594626, S = { 4.372, 2.746, 0.080 }, C = { 117, 0, 0 }, Mat = "Metal", P = { 0.424, 1.622, 0.116, -0.998, 0.070, -0.000, 0.070, 0.998, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.643, 0.509, -0.557, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.622, 0.536, -0.557, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ Shape = "Block", S = { 0.155, 0.073, 0.001 }, C = { 196, 40, 28 }, Mat = "Neon", P = { 0.138, 2.992, 0.098, -0.934, 0.358, -0.000, 0.358, 0.934, -0.000, 0.000, -0.000, -1.000 } },
		{ M = 15922595166, S = { 1.490, 1.617, 0.080 }, C = { 44, 101, 29 }, Mat = "Metal", P = { 0.155, 2.285, 0.059, -0.998, 0.070, -0.000, 0.070, 0.998, -0.000, 0.000, -0.000, -1.000 } },
	} },
	{ Name = "Qoherys", Parts = {
		{ M = 14808298101, S = { 1.088, 1.663, 0.123 }, C = { 248, 248, 248 }, Mat = "Metal", P = { 2.186, 1.211, 0.043, -1.000, 0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
		{ Shape = "Block", S = { 0.240, 0.838, 8.174 }, C = { 245, 205, 48 }, Mat = "Metal", P = { -0.086, 1.470, -0.023, -0.000, 0.707, 0.707, 0.000, 0.707, -0.707, -1.000, -0.000, -0.000 } },
		{ M = 14808298101, S = { 1.088, 1.663, 0.123 }, C = { 248, 248, 248 }, Mat = "Metal", P = { -0.006, 3.621, 0.043, -1.000, 0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
		{ Shape = "Block", S = { 0.240, 0.838, 8.456 }, C = { 245, 205, 48 }, Mat = "Metal", P = { 0.174, 1.518, -0.023, 0.000, -0.707, -0.707, 0.000, 0.707, -0.707, 1.000, 0.000, 0.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { 0.636, 0.509, -0.578, 1.000, -0.000, -0.000, 0.000, 1.000, -0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126243293, S = { 1.265, 0.608, 0.983 }, C = { 202, 203, 209 }, Mat = "Metal", P = { -0.628, 0.536, -0.578, -1.000, 0.000, -0.000, -0.000, -1.000, -0.000, -0.000, -0.000, 1.000 } },
		{ M = 12126134560, S = { 6.727, 11.255, 0.177 }, C = { 17, 17, 17 }, Mat = "Metal", P = { 0.000, -0.008, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ M = 12126134329, S = { 6.986, 11.797, 0.257 }, C = { 159, 161, 172 }, Mat = "Metal", P = { 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000, 0.000, 0.000, 0.000, 1.000 } },
		{ Shape = "Block", S = { 0.258, 0.650, 8.218 }, C = { 117, 0, 0 }, Mat = "Metal", P = { -0.071, 1.455, -0.017, -0.000, 0.707, 0.707, 0.000, 0.707, -0.707, -1.000, -0.000, -0.000 } },
		{ Shape = "Block", S = { 0.258, 0.650, 8.316 }, C = { 117, 0, 0 }, Mat = "Metal", P = { 0.106, 1.450, -0.017, 0.000, -0.707, -0.707, 0.000, 0.707, -0.707, 1.000, 0.000, 0.000 } },
		{ M = 14808298101, S = { 1.088, 1.663, 0.123 }, C = { 248, 248, 248 }, Mat = "Metal", P = { -0.006, -1.518, 0.043, -1.000, 0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
		{ M = 14808298101, S = { 1.088, 1.663, 0.123 }, C = { 248, 248, 248 }, Mat = "Metal", P = { -2.185, 1.211, 0.044, -1.000, 0.000, -0.000, 0.000, 1.000, 0.000, 0.000, 0.000, -1.000 } },
	} },}

function ShieldSkins.Pick(item: any): any?
	if typeof(item) ~= "table" then
		return nil
	end
	local tiers = math.max(1, #GearCatalog.TierLevels)
	local rars = math.max(1, #GearCatalog.Rarities)
	local tier = if typeof(item.Tier) == "number" then item.Tier else 1
	local rIdx = table.find(GearCatalog.Rarities, item.Rarity) or 1
	local slot = (math.clamp(tier, 1, tiers) - 1) * rars + (rIdx - 1)
	return SHIELDS[math.clamp(math.floor(slot * #SHIELDS / (tiers * rars)) + 1, 1, #SHIELDS)]
end

-- Pone el escudo en la mano. true = quedó puesto; false = aún carga (onReady se llama UNA vez al terminar) o alguna malla no carga.
function ShieldSkins.Attach(parent: Instance, hand: BasePart, skin: any, g: Vector3, height: number, onReady: (() -> ())?): boolean
	-- 1) todas las mallas deben estar listas
	local meshes = {}
	local pending, failed = 0, false
	local needed = {}
	for _, p in ipairs(skin.Parts) do
		if p.M then
			needed[p.M] = true
		end
	end
	for id in pairs(needed) do
		local mp = WeaponSkins.MeshFor(id, function()
			pending -= 1
			if pending == 0 and onReady then
				onReady()
			end
		end)
		if mp == nil then
			pending += 1
		elseif mp == false then
			failed = true
		else
			meshes[id] = mp
		end
	end
	if failed or pending > 0 then
		return false
	end
	-- 2) construir
	local k = height / BASE_HEIGHT
	local origin = CFrame.new(g + GRIP_SHIFT) * CFrame.Angles(0, FACE, 0) * CFrame.new(-GRIP * k)
	for _, p in ipairs(skin.Parts) do
		local piece: BasePart
		local size = Vector3.new(p.S[1], p.S[2], p.S[3]) * k
		if p.M then
			local mesh: MeshPart = meshes[p.M]:Clone()
			mesh.TextureID = ""
			mesh.Size = size
			piece = mesh
		else
			local part = Instance.new("Part")
			part.Shape = Enum.PartType[p.Shape]
			part.Size = Vector3.new(math.max(size.X, 0.001), math.max(size.Y, 0.001), math.max(size.Z, 0.001))
			piece = part
		end
		piece.Name = "WeaponPart"
		piece.Color = Color3.fromRGB(p.C[1], p.C[2], p.C[3])
		piece.Material = Enum.Material[p.Mat]
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.CastShadow = false
		local rel = CFrame.new(table.unpack(p.P))
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = piece
		w.C0 = origin * (CFrame.new(rel.Position * k) * (rel - rel.Position))
		w.Parent = piece
		piece.Parent = parent
	end
	return true
end

return ShieldSkins
