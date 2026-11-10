--!nonstrict
--[[
    WeaponSkins (ModuleScript) -> ServerScriptService.Services.WeaponSkins
    MODELOS 3D para las armas del avatar (espadas, dagas, hachas/martillos/mazas, lanzas/alabardas y báculos). Solo se usan MALLA y TEXTURA (ids de Roblox); los scripts de los
    paquetes originales NO se usan. La malla se crea en el servidor con AssetService:CreateMeshPartAsync: si no carga
    (privada, borrada, sin permiso), el arma se dibuja como siempre (AttackAnimator conserva el modelo con bloques).
    Reparto: cada arma del catálogo tiene Tier (1..N) y Rareza; a esa combinación le toca una skin de la lista (de menos a más
    espectacular), así cada pieza se ve distinta. Para quitar/cambiar skins edita SOLO las listas de abajo (nombre, malla, textura).
    Ajustes de agarre (AttackAnimator las usa tal cual):
      TARGET_LEN  largo fijo (studs) de las skins que lo traen (paquete Genshin)   REF_K/MIN_LEN/MAX_LEN  largo de las skins Low Poly = largo nativo x REF_K, limitado a [MIN,MAX]
      GRIP_FRAC   qué parte del largo queda detrás de la mano (empuñadura)
      TIP_SIGN    +1 si la punta está en el lado + del eje largo de la malla, -1 si está al revés (paquete Genshin)
      LP_TIP      lo mismo para el paquete Low Poly (si TODAS esas armas se ven "al revés", cambia SOLO este número por -1)
]]
local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)

local WeaponSkins = {}

WeaponSkins.TARGET_LEN = { Sword = 4.0, Dagger = 2.2 }
WeaponSkins.REF_K = { Sword = 0.65, Dagger = 0.65, Axe = 0.6, Staff = 0.8, Spear = 0.7 }
WeaponSkins.MIN_LEN = { Sword = 3.0, Dagger = 1.6, Axe = 2.6, Staff = 4.5, Spear = 5.0 }
WeaponSkins.MAX_LEN = { Sword = 4.6, Dagger = 2.8, Axe = 4.8, Staff = 6.0, Spear = 6.5 }
WeaponSkins.GRIP_FRAC = { Sword = 0.17, Dagger = 0.25, Axe = 0.2, Staff = 0.35, Spear = 0.3 }
WeaponSkins.TIP_SIGN = { Sword = 1, Dagger = 1 }
-- Cabeceo (grados) del arma alrededor de la mano: 0 = recta como antes; NEGATIVO = la punta/cabeza baja hacia delante.
-- Los mazos/hachas se llevan con la parte gruesa mirando hacia abajo. Si la quieres más o menos caída, cambia SOLO este número.
WeaponSkins.PITCH = { Axe = -60 }
local LP_TIP = 1
local LP_TEX = 2913129928 -- textura única del paquete Low Poly

-- { nombre interno, id de malla, id de textura }  (ordenadas de menos a más poderosa)
local SWORDS = {
	{ "wooden", 8605937395, 8605941722 },
	{ "dull blade", 8605049252, 8605047217 },
	{ "dull blade 2", 8605049567, 8605046953 },
	{ "cool steel", 8604994225, 8604999616 },
	{ "cool steel 2", 8604994489, 8604999356 },
	{ "traveler", 8605923546, 8605931228 },
	{ "traveler 2", 8605923790, 8605931002 },
	{ "silver", 8605643818, 8605650707 },
	{ "silver 2", 8605644071, 8605650492 },
	{ "fillet", 8605174377, 8605180112 },
	{ "fillet 2", 8605174542, 8605179878 },
	{ "katana", 8605586372, 8605591451 },
	{ "iron sting", 8605375734, 8605384260 },
	{ "iron sting 2", 8605376070, 8605385485 },
	{ "dark iron", 8605015639, 8605021352 },
	{ "dark iron 2", 8605015920, 8605021091 },
	{ "norse", 8605469069, 8605475685 },
	{ "norse 2", 8605469265, 8605475430 },
	{ "boreas", 8600711936, 8600720126 },
	{ "boreas 2", 8600712179, 8600719806 },
	{ "blackcliff", 8600683286, 8600695196 },
	{ "blackcliff 2", 8600683641, 8600694875 },
	{ "royal", 8605598117, 8605603869 },
	{ "royal 2", 8605598362, 8605603533 },
	{ "sacrificial", 8605619194, 8605627384 },
	{ "sacrificial 2", 8605619370, 8605627178 },
	{ "favonius", 8605074148, 8605079963 },
	{ "favonius 2", 8605074396, 8605085579 },
	{ "flute", 8605891206, 8605898445 },
	{ "flute 2", 8605891571, 8605898178 },
	{ "alley flash 2", 8605855967, 8605870018 },
	{ "lions roar", 8605393071, 8605400158 },
	{ "lions roar 2", 8605393373, 8605399895 },
	{ "festering", 8605159141, 8605164666 },
	{ "festering 2", 8605159340, 8605164448 },
	{ "rancour", 8605570816, 8605576028 },
	{ "rancour 2", 8605571029, 8605575800 },
	{ "black sword", 8605876456, 8605883814 },
	{ "black sword 2", 8605876713, 8605884055 },
	{ "cinnabar", 8600752348, 8600760250 },
	{ "cinnabar 2", 8600752657, 8600760034 },
	{ "freedom", 8605212976, 8605219425 },
	{ "freedom 2", 8605213140, 8605219099 },
	{ "jade cutter", 8605486047, 8605494897 },
	{ "jade cutter 2", 8605486272, 8605494483 },
	{ "harbinger", 8605287932, 8605319080 },
	{ "harbinger 2", 8605289268, 8605318371 },
	{ "mistsplitter", 8605410996, 8605417536 },
	{ "mistsplitter 2", 8605411382, 8605417305 },
	{ "narukami", 8605438283, 8605443513 },
	{ "narukami 2", 8605438466, 8605443268 },
	{ "amenoma", 8600620742, 8600632040 },
	{ "amenoma 2", 8600620938, 8600631786 },
	{ "bakufu", 8600667731, 8600669629 },
	{ "summit", 8605828934, 8605834707 },
	{ "summit 2", 8605829256, 8605834350 },
	{ "aquila", 8600649066, 8600656488 },
	{ "aquila 2", 8600649469, 8600656742 },
	{ "skyward", 8605676951, 8605682367 },
	{ "skyward 2", 8605677269, 8605682187 },
	{ "skyrider", 8605658978, 8605668011 },
	{ "skyrider 2", 8605659369, 8605667727 },
	{ "descension", 8605843181, 8605848121 },
	{ "descension 2", 8605843499, 8605847872 },
	{ "star aether", 8605814481, 8605821545 },
	{ "star lumine", 8605814719, 8605821079 },
	{ "transcend", 8605912117, 8605909987 },
	{ "transcend 2", 8605912542, 8605909659 },
}
local DAGGERS = {
	{ "borders", 121944778, 155199285 },
	{ "cheesy", 121944778, 161205828 },
	{ "kypto", 121944778, 155572642 },
	{ "missing", 121944778, 163625649 },
	{ "linked", 121944778, 172762850 },
	{ "8bit", 121944778, 159546779 },
	{ "spectrum", 121944778, 162718300 },
	{ "overseer", 121944778, 2599622211 },
	{ "fang", 117500241, 117500388 },
	{ "chroma fang", 117500241, 3248392136 },
}
-- Paquete Low Poly Weapons (todas comparten textura). {nombre, malla}
local LP_SWORDS = {
	{ "BrokenSword", 2913166772 }, { "Goblin_Machete", 2913164299 }, { "Straightsword", 2913165107 }, { "Cutlass", 2913167374 },
	{ "Goblin_Machete_Spikes", 2913164441 }, { "GreatSword", 2913166814 }, { "Greatsword_Straight", 2913164143 },
	{ "Ornate_Sword_02", 2913167218 }, { "Crystal_Ornate_Straightsword", 2913167431 }, { "Greatsword_Round", 2913166723 },
	{ "Greatsword_Curved", 2913165158 }, { "Ornate_Sword_01", 2913166918 }, { "Ornate_Spikes", 2913166437 },
	{ "Ornate_Spikes_Long", 2913166322 }, { "Crystal_DoubleSword", 2913165050 }, { "Staff_DoubleBlade", 2913164735 },
}
local LP_DAGGERS = {
	{ "Bone_02", 2913166854 }, { "Bone_01", 2913167801 }, { "Goblin_Shiv_Bone", 2913164189 }, { "Goblin_Shiv_Stone", 2913167495 },
}
-- hachas, martillos, mazas y alabardas (de menos a más poderosa)
local LP_AXES = {
	{ "Hammer_Small_01", 2913166567 }, { "HandAxe_01", 2913167316 }, { "Goblin_Club_01", 2913164242 }, { "Axe_01", 2913167569 },
	{ "Hammer_Small_02", 2913165002 }, { "Goblin_Axe_01", 2913165328 }, { "Goblin_Mace_01", 2913165419 },
	{ "Hammer_Large_Wood_01", 2913167095 }, { "Goblin_Bone_Axe_01", 2913166381 }, { "Hammer_Mace_Stone_01", 2913164793 },
	{ "Goblin_Axe_Spikes_01", 2913165216 }, { "Hammer_Large_Stone_01", 2913166669 }, { "Hammer_Mace_Sphere_01", 2913167266 },
	{ "Hammer_Mace_Spikes_01", 2913167637 }, { "Axe_Nature_01", 2913163970 }, { "Mace_Blades_01", 2913164038 },
	{ "Goblin_Axe_Large_01", 2913167727 }, { "Goblin_Gem_Hammer_01", 2913166481 },
	{ "Hammer_Large_Metal_01", 2913164683 }, { "Hammer_Large_Metal_010", 2913164898 },
	{ "Ornate_Axe_01", 2913166524 }, { "Ornate_Axe_02", 2913164392 }, { "Axe_Rune_01", 2913164947 },
	{ "Ornate_GreatAxe_01", 2913164487 }, { "Crystal_Axe_01", 2913164535 }, { "Crystal_Axe_Large_01", 2913167149 },
}
-- lanzas, alabardas y estandarte (de menos a más poderosa)
local LP_SPEARS = {
	{ "Spear_02", 2913164094 }, { "Spear_01", 2913165270 }, { "Goblin_Spear_01", 2913166608 }, { "Goblin_Halberd_01", 2913164587 },
	{ "Halberd_06", 2913166268 }, { "Banner_01", 2913166957 }, { "Ornate_Spear_01", 2913167051 }, { "Crysta_Halberdl_01", 2913166222 },
}
local LP_STAFFS = {
	{ "Goblin_Staff", 2913164641 }, { "Staff_Gem", 2913164343 },
}

-- Convierte listas en entradas { Name, Mesh, Tex, Len?, Tip }
local function entries(list: { any }, len: number?, tip: number, fixedTex: number?): { any }
	local out = {}
	for _, e in ipairs(list) do
		table.insert(out, { Name = e[1], Mesh = e[2], Tex = fixedTex or e[3], Len = len, Tip = tip })
	end
	return out
end

local function ordered(a: { any }, b: { any }): { any }
	-- mezcla dos listas ordenadas de menos a más poderosa repartiendo la segunda de forma pareja entre la primera
	local out = {}
	local ia, ib = 1, 1
	local na, nb = #a, #b
	while ia <= na or ib <= nb do
		-- toma de la lista que va "más atrasada" en proporción
		if ib > nb or (ia <= na and (ia - 1) / na <= (ib - 1) / nb) then
			table.insert(out, a[ia])
			ia += 1
		else
			table.insert(out, b[ib])
			ib += 1
		end
	end
	return out
end

local POOLS = {
	Sword = ordered(entries(SWORDS, 4.0, 1), entries(LP_SWORDS, nil, LP_TIP, LP_TEX)),
	Dagger = ordered(entries(DAGGERS, 2.2, 1), entries(LP_DAGGERS, nil, LP_TIP, LP_TEX)),
	Axe = entries(LP_AXES, nil, LP_TIP, LP_TEX),
	Spear = entries(LP_SPEARS, nil, LP_TIP, LP_TEX),
	Staff = entries(LP_STAFFS, nil, LP_TIP, LP_TEX),
}

-- Elige la skin de un arma según su Tier y su Rareza (reparto uniforme sobre la lista)
function WeaponSkins.Pick(style: string, weapon: any): { Name: string, Mesh: number, Tex: number, Style: string, Len: number?, Tip: number }?
	local pool = POOLS[style]
	if not pool or typeof(weapon) ~= "table" then
		return nil
	end
	local tiers = math.max(1, #GearCatalog.TierLevels)
	local rars = math.max(1, #GearCatalog.Rarities)
	local tier = if typeof(weapon.Tier) == "number" then weapon.Tier else 1
	local rIdx = table.find(GearCatalog.Rarities, weapon.Rarity) or 1
	local slot = (math.clamp(tier, 1, tiers) - 1) * rars + (rIdx - 1) -- 0 .. tiers*rars-1
	local idx = math.clamp(math.floor(slot * #pool / (tiers * rars)) + 1, 1, #pool)
	local e = pool[idx]
	return { Name = e.Name, Mesh = e.Mesh, Tex = e.Tex, Style = style, Len = e.Len, Tip = e.Tip }
end

-- Caché de mallas (se crean una vez y se clonan). false = no carga.
local meshCache: { [number]: any } = {}
local loading: { [number]: boolean } = {}
local waiters: { [number]: { () -> () } } = {}
local warned = false

local function load(meshId: number)
	if meshCache[meshId] ~= nil or loading[meshId] then
		return
	end
	loading[meshId] = true
	task.spawn(function()
		local ok, mp = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromAssetId(meshId))
		end)
		if not ok then
			ok, mp = pcall(function()
				return AssetService:CreateMeshPartAsync("rbxassetid://" .. meshId)
			end)
		end
		if ok and mp then
			meshCache[meshId] = mp
		else
			meshCache[meshId] = false
			if not warned then
				warned = true
				warn("[WeaponSkins] No se pudo cargar una malla (" .. tostring(meshId) .. "): " .. tostring(mp) .. " · se usa el arma con bloques.")
			end
		end
		loading[meshId] = nil
		local list = waiters[meshId]
		waiters[meshId] = nil
		for _, cb in ipairs(list or {}) do
			task.defer(cb)
		end
	end)
end

-- Orientación: eje LARGO de la malla -> hacia delante de la mano (-Z), ancho -> Y, grosor -> X
local function orientFor(native: Vector3, tipSign: number): CFrame
	local sizes = { native.X, native.Y, native.Z }
	local idx = { 1, 2, 3 }
	table.sort(idx, function(a, b)
		return sizes[a] > sizes[b]
	end)
	local v = {}
	v[idx[1]] = Vector3.new(0, 0, -tipSign)
	v[idx[3]] = Vector3.new(1, 0, 0)
	v[idx[2]] = Vector3.new(0, 1, 0)
	if v[1]:Cross(v[2]):Dot(v[3]) < 0 then
		v[idx[2]] = -v[idx[2]]
	end
	return CFrame.fromMatrix(Vector3.zero, v[1], v[2], v[3])
end

WeaponSkins.Pools = POOLS
WeaponSkins.OrientFor = orientFor

-- Malla ya creada por id (para otros módulos, p. ej. escudos): MeshPart si está lista, false si no carga, nil si aún carga (se llama onReady al terminar)
function WeaponSkins.MeshFor(meshId: number, onReady: (() -> ())?): any
	local mp = meshCache[meshId]
	if mp ~= nil then
		return mp
	end
	if onReady then
		local w = waiters[meshId]
		if not w then
			w = {}
			waiters[meshId] = w
		end
		table.insert(w, onReady)
	end
	load(meshId)
	return nil
end

-- Pone la skin en la mano. Devuelve true si quedó puesta; false si aún carga (se llama onReady al terminar) o no carga nunca.
function WeaponSkins.Attach(parent: Instance, hand: BasePart, skin: any, grip: Vector3, onReady: (() -> ())?): boolean
	local mp = meshCache[skin.Mesh]
	if mp == nil then
		if onReady then
			local w = waiters[skin.Mesh]
			if not w then
				w = {}
				waiters[skin.Mesh] = w
			end
			table.insert(w, onReady)
		end
		load(skin.Mesh)
		return false
	end
	if mp == false then
		return false
	end
	local style = skin.Style
	local piece: MeshPart = mp:Clone()
	local native: Vector3 = mp.Size
	local nativeMax = math.max(native.X, native.Y, native.Z)
	local target = skin.Len or math.clamp(nativeMax * WeaponSkins.REF_K[style], WeaponSkins.MIN_LEN[style], WeaponSkins.MAX_LEN[style])
	local k = target / nativeMax
	piece.Size = native * k
	piece.TextureID = "rbxassetid://" .. skin.Tex
	piece.Name = "WeaponPart"
	piece.Anchored = false
	piece.CanCollide = false
	piece.CanQuery = false
	piece.CanTouch = false
	piece.Massless = true
	piece.CastShadow = false
	piece.Material = Enum.Material.SmoothPlastic
	local len = math.max(piece.Size.X, piece.Size.Y, piece.Size.Z)
	local along = Vector3.new(0, 0, -(len * (0.5 - WeaponSkins.GRIP_FRAC[style])))
	local pitch = math.rad(WeaponSkins.PITCH[style] or 0)
	piece.Parent = parent
	local w = Instance.new("Weld")
	w.Part0 = hand
	w.Part1 = piece
	-- el arma gira sobre el puño (no sobre su centro) para que la mano siga agarrando el mango
	w.C0 = CFrame.new(grip) * CFrame.Angles(pitch, 0, 0) * CFrame.new(along) * orientFor(native, skin.Tip or WeaponSkins.TIP_SIGN[style] or 1)
	w.Parent = piece
	return true
end

return WeaponSkins
