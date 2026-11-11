--!nonstrict
--[[
    FloorSkins (ModuleScript) -> ServerScriptService.Services.FloorSkins
    PISOS CON VIDA (se suma encima de BiomeStyler / CityStyler / BiomeDetails; si falla algo, el mapa queda como estaba):
      1) SUELO DE FRANJA: cambia la textura de cada losa por un suelo suave y repetible (sin líneas fuertes ni cuadrículas) y reparte
         PARCHES con borde difuso (charcos, flores, grietas, escombros, runas, dunas...) con posiciones fijas por franja.
      2) CIUDAD: suelo con textura, caminos con bordes suaves y plaza con borde difuso, todo sin escalones (a ras del piso).
      3) SOMBRAS al pie de los muros de la ciudad (apagadas por defecto: ver SOMBRAS).
    Todo es decoración sin colisión. Con StreamingEnabled solo se dibuja lo cercano. Ajustes: bloque CONFIG.
]]
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- ===================== CONFIG =====================
local CONFIG = {
	SUELOS = true,        -- textura nueva en las losas de las franjas
	PARCHES = true,       -- parches de vida repartidos por cada franja
	CIUDAD = true,        -- suelo, caminos y plaza de las 4 ciudades
	SOMBRAS = false,      -- sombra suave al pie de los muros de la ciudad (ver SOMBRA_GIRO)
	TILE = 40,            -- studs que mide una repetición del suelo (más grande = menos se nota la repetición)
	CITY_TILE = 36,       -- idem en la ciudad
	AREA_POR_PARCHE = 6500, -- studs² por parche (más chico = más parches)
	MAX_PARCHES = 230,    -- tope por franja (cuida el rendimiento)
	SOMBRA_GIRO = 0,      -- 0..3: cuartos de giro de la imagen de la sombra (si el degradado sale a lo largo del muro, prueba 1)
	SOMBRA_ANCHO = 11,    -- studs de ancho de la sombra
}
-- ==================================================

local MAP_NAME = "Map_WC3_Style"
local BIOME_FACTION = { Imperio_Saiyan = "Saiyan", Alianza_Shinobi = "Shinobi", Flota_Pirata = "Pirate", Corte_Shinigami = "Shinigami" }
local CAMP_CLEAR = 38
local EDGE_MARGIN = 16

-- ===== IDS DE LAS IMAGENES =====
local TILES = {
	Saiyan_1 = 127535037252267,
	Saiyan_2 = 99286906259465,
	Saiyan_3 = 131523779097277,
	Saiyan_4 = 74128820835855,
	Shinobi_1 = 104351296430249,
	Shinobi_2 = 76336529921708,
	Shinobi_3 = 126093465799560,
	Shinobi_4 = 104415015845421,
	Pirate_1 = 126960033161529,
	Pirate_2 = 102667531798560,
	Pirate_3 = 125758604203758,
	Pirate_4 = 134302374714648,
	Shinigami_1 = 107178812366505,
	Shinigami_2 = 135514952397864,
	Shinigami_3 = 72446678444598,
	Shinigami_4 = 140655487545532,
}
-- parches por franja: { id, tamaño mínimo, tamaño máximo } (studs)
local PATCHES = {
	Saiyan_1 = { { 97187441986756, 30, 52 }, { 74368285362408, 26, 44 }, { 112516249056959, 20, 34 } },
	Saiyan_2 = { { 121831087550103, 18, 32 }, { 75924761855380, 26, 44 }, { 111522892423174, 20, 34 } },
	Saiyan_3 = { { 80626807463927, 30, 54 }, { 126195253606876, 22, 38 }, { 129639477022874, 26, 44 } },
	Saiyan_4 = { { 101129700210506, 18, 32 }, { 119986597341840, 20, 34 }, { 113774724980348, 20, 34 } },
	Shinobi_1 = { { 131109203605257, 30, 50 }, { 71793107418933, 18, 30 }, { 117664368368970, 18, 32 } },
	Shinobi_2 = { { 97788784287431, 18, 32 }, { 122454462980952, 28, 46 }, { 118647191251728, 30, 54 } },
	Shinobi_3 = { { 118791011227386, 44, 76 }, { 137519022498627, 24, 40 }, { 70402715284393, 30, 54 } },
	Shinobi_4 = { { 109134140141130, 30, 54 }, { 91754839511444, 22, 38 }, { 111516444813104, 18, 32 } },
	Pirate_1 = { { 102253058039599, 22, 38 }, { 112439614327611, 22, 36 }, { 98322144386475, 20, 34 } },
	Pirate_2 = { { 100049070239174, 44, 76 }, { 119535724019757, 18, 32 }, { 132475708882391, 20, 32 } },
	Pirate_3 = { { 140554012439114, 40, 66 }, { 105362290719128, 30, 54 }, { 133731612784734, 22, 38 } },
	Pirate_4 = { { 102800181023743, 30, 54 }, { 111058304259907, 26, 44 }, { 97326012584383, 30, 50 } },
	Shinigami_1 = { { 84297851230819, 30, 52 }, { 135476859600005, 26, 44 }, { 107277815666448, 18, 32 } },
	Shinigami_2 = { { 88615511002472, 44, 76 }, { 132553908117925, 20, 32 }, { 94040190435762, 20, 34 } },
	Shinigami_3 = { { 102066180565564, 30, 54 }, { 103162754918248, 22, 38 }, { 129286857134669, 40, 60 } },
	Shinigami_4 = { { 111643390904526, 30, 50 }, { 84477230427428, 18, 32 }, { 131929463587799, 26, 44 } },
}
local CITY = {
	Saiyan = { suelo = 73221419882506, camino = 113385593592686, plaza = 93590715825905 },
	Shinobi = { suelo = 80283883413490, camino = 104658988237225, plaza = 136638563867339 },
	Pirate = { suelo = 136169324928129, camino = 104319410303614, plaza = 86481219884055 },
	Shinigami = { suelo = 111479846695269, camino = 118990139337041, plaza = 79197985440834 },
}
local SHADOW_ID = 110038362342208
-- ===============================

local function rbx(id)
	if not id or id == 0 then
		return nil
	end
	return "rbxassetid://" .. tostring(id)
end

local function factionOf(inst)
	local p = inst
	while p and p ~= Workspace do
		local f = BIOME_FACTION[p.Name]
		if f then
			return f
		end
		p = p.Parent
	end
	return nil
end

local folder = nil
local token = 0

local function clearOld(part, className)
	for _, c in ipairs(part:GetChildren()) do
		if c:IsA(className) then
			c:Destroy()
		end
	end
end

---------------------------------------------------------------------
-- 1) Suelo de franja
---------------------------------------------------------------------
local function styleSlices(map)
	local n = 0
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") then
			local idx = d.Parent and tonumber(string.match(d.Parent.Name, "Franja(%d)"))
			if idx and d.Parent.Parent and d.Parent.Parent.Name == "Piso" then
				local f = factionOf(d)
				local id = f and rbx(TILES[f .. "_" .. idx])
				if id then
					clearOld(d, "Texture")
					local tex = Instance.new("Texture")
					tex.Name = "PisoNuevo"
					tex.Texture = id
					tex.Face = Enum.NormalId.Top
					tex.StudsPerTileU = CONFIG.TILE
					tex.StudsPerTileV = CONFIG.TILE
					tex.Parent = d
					n += 1
				end
			end
		end
	end
	return n
end

---------------------------------------------------------------------
-- 2) Parches (usa las mismas franjas que BiomeDetails)
---------------------------------------------------------------------
local function readLanes(map)
	local found = {}
	for _, p in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if p:IsA("BasePart") and p:IsDescendantOf(map) then
			local biome, strip = p:GetAttribute("Biome"), p:GetAttribute("Strip")
			local ls, ld = p:GetAttribute("LaneStart"), p:GetAttribute("LaneDir")
			local fc, fk = p:GetAttribute("FanC"), p:GetAttribute("FanK")
			local u0, u1 = p:GetAttribute("UStart"), p:GetAttribute("UEnd")
			if typeof(biome) == "string" and typeof(strip) == "number" and BIOME_FACTION[biome] and typeof(ls) == "Vector3" and typeof(ld) == "Vector3"
				and typeof(fc) == "number" and typeof(fk) == "number" and typeof(u0) == "number" and typeof(u1) == "number" then
				local key = biome .. "_" .. strip
				if not found[key] then
					found[key] = { Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld, FanC = fc, FanK = fk, U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2 }
				end
			end
		end
	end
	local out = {}
	for _, l in pairs(found) do
		table.insert(out, l)
	end
	table.sort(out, function(a, b)
		if a.Faction ~= b.Faction then
			return a.Faction < b.Faction
		end
		return a.Strip < b.Strip
	end)
	return out
end

local function buildPatches(l, root)
	local list = PATCHES[l.Faction .. "_" .. l.Strip]
	if not list then
		return 0
	end
	local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
	local function pt(u, v)
		local p = l.Start + l.Dir * u + side * v
		return Vector3.new(p.X, l.FloorY, p.Z)
	end
	local len = l.U1 - l.U0
	local campPos = pt(l.U0 + len * 0.5, 0)
	local midHalf = l.FanC + l.FanK * (l.U0 + len * 0.5)
	local count = math.clamp(math.floor(len * 2 * midHalf / CONFIG.AREA_POR_PARCHE), 30, CONFIG.MAX_PARCHES)
	local f = Instance.new("Folder")
	f.Name = "Parches_" .. l.Faction .. "_" .. l.Strip
	f.Parent = root
	local rng = Random.new(l.Strip * 6007 + #l.Faction * 211 + 5)
	local made = 0
	for i = 1, count do
		local entry = list[((i - 1) % #list) + 1]
		local id = rbx(entry[1])
		if id then
			local u = l.U0 + 14 + rng:NextNumber() * (len - 28)
			local half = math.max(10, (l.FanC + l.FanK * u) - EDGE_MARGIN)
			local v = (rng:NextNumber() * 2 - 1) * half
			local p = pt(u, v)
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(campPos.X, 0, campPos.Z)).Magnitude > CAMP_CLEAR then
				local s = entry[2] + rng:NextNumber() * (entry[3] - entry[2])
				local part = Instance.new("Part")
				part.Name = "Parche"
				part.Anchored = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.CastShadow = false
				part.Transparency = 0.98 -- casi invisible: con 1 el Decal desaparece
				part.Size = Vector3.new(s, 0.02, s)
				part.CFrame = CFrame.new(p + Vector3.new(0, 0.04 + (i % 5) * 0.02, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
				local d = Instance.new("Decal")
				d.Face = Enum.NormalId.Top
				d.Texture = id
				d.Parent = part
				part.Parent = f
				made += 1
			end
		end
	end
	return made
end

---------------------------------------------------------------------
-- 3) Ciudad
---------------------------------------------------------------------
local CITY_GROUND = {
	Saiyan = Color3.fromRGB(46, 59, 82), Shinobi = Color3.fromRGB(180, 154, 115),
	Pirate = Color3.fromRGB(123, 90, 58), Shinigami = Color3.fromRGB(132, 140, 160),
}
local function startsWith(s, p)
	return string.sub(s, 1, #p) == p
end

local function styleCities(map, root)
	local walls = {}
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") then
			local f = factionOf(d)
			local ids = f and CITY[f]
			if ids and d.Parent and d.Parent.Name == "Piso" then
				if startsWith(d.Name, "Z1_Ciudad") and rbx(ids.suelo) then
					clearOld(d, "Texture")
					local tex = Instance.new("Texture")
					tex.Name = "CiudadSuelo"
					tex.Texture = rbx(ids.suelo)
					tex.Face = Enum.NormalId.Top
					tex.StudsPerTileU = CONFIG.CITY_TILE
					tex.StudsPerTileV = CONFIG.CITY_TILE
					tex.Parent = d
				elseif startsWith(d.Name, "Camino_") and rbx(ids.camino) then
					clearOld(d, "Texture")
					d.Color = CITY_GROUND[f]
					d.Material = Enum.Material.SmoothPlastic
					local narrow = math.min(d.Size.X, d.Size.Z)
					local tex = Instance.new("Texture")
					tex.Name = "CaminoNuevo"
					tex.Texture = rbx(ids.camino)
					tex.Face = Enum.NormalId.Top
					if d.Size.X <= d.Size.Z then
						tex.StudsPerTileU = narrow
						tex.StudsPerTileV = 64
					else
						tex.StudsPerTileU = 64
						tex.StudsPerTileV = narrow
					end
					tex.Parent = d
				elseif startsWith(d.Name, "Plaza_Central") and rbx(ids.plaza) then
					clearOld(d, "Decal")
					clearOld(d, "Texture")
					d.Transparency = 0.98 -- la losa casi no se ve: el dibujo (con borde difuso) se funde con el suelo de la ciudad
					local dec = Instance.new("Decal")
					dec.Name = "PlazaNueva"
					dec.Face = Enum.NormalId.Top
					dec.Texture = rbx(ids.plaza)
					dec.Parent = d
				end
			elseif ids and CONFIG.SOMBRAS and SHADOW_ID ~= 0 and startsWith(d.Name, "Muralla_") then
				table.insert(walls, { Part = d, Faction = f })
			end
		end
	end
	if CONFIG.SOMBRAS and SHADOW_ID ~= 0 then
		for _, w in ipairs(walls) do
			local p = w.Part
			local city = p:FindFirstAncestor("Ciudad")
			local pisoF = city and city:FindFirstChild("Piso")
			local plaza = pisoF and pisoF:FindFirstChild("Plaza_Central")
			if plaza then
				local long = if p.Size.X >= p.Size.Z then p.CFrame.RightVector else p.CFrame.LookVector
				local L = math.max(p.Size.X, p.Size.Z)
				local toPlaza = Vector3.new(plaza.Position.X - p.Position.X, 0, plaza.Position.Z - p.Position.Z)
				local inner = (toPlaza - long * toPlaza:Dot(long))
				if inner.Magnitude > 0.1 then
					inner = inner.Unit
					local thick = math.min(p.Size.X, p.Size.Z)
					local floorY = plaza.Position.Y + plaza.Size.Y / 2
					local pos = Vector3.new(p.Position.X, floorY + 0.03, p.Position.Z) + inner * (thick / 2 + CONFIG.SOMBRA_ANCHO / 2)
					local cf = CFrame.fromMatrix(pos, long, Vector3.yAxis, long:Cross(Vector3.yAxis))
					if cf.LookVector:Dot(-inner) < 0 then
						cf = cf * CFrame.Angles(0, math.pi, 0)
					end
					local turns = CONFIG.SOMBRA_GIRO % 4
					cf = cf * CFrame.Angles(0, turns * math.pi / 2, 0)
					local sz = if turns % 2 == 0 then Vector3.new(L, 0.02, CONFIG.SOMBRA_ANCHO) else Vector3.new(CONFIG.SOMBRA_ANCHO, 0.02, L)
					local s = Instance.new("Part")
					s.Name = "SombraMuro"
					s.Anchored = true
					s.CanCollide = false
					s.CanQuery = false
					s.CanTouch = false
					s.CastShadow = false
					s.Transparency = 0.98
					s.Size = sz
					s.CFrame = cf
					local dec = Instance.new("Decal")
					dec.Face = Enum.NormalId.Top
					dec.Texture = rbx(SHADOW_ID)
					dec.Parent = s
					s.Parent = root
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Construcción
---------------------------------------------------------------------
local function build()
	token += 1
	local mine = token
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		return
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	for _, stale in ipairs(Workspace:GetChildren()) do
		if stale.Name == "PisoVivo" then
			stale:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "PisoVivo"
	root.Parent = Workspace
	folder = root
	if CONFIG.SUELOS then
		local ok, res = pcall(styleSlices, map)
		print(ok and ("[FloorSkins] Losas con textura nueva: " .. tostring(res)) or ("[FloorSkins] Error en suelos: " .. tostring(res)))
	end
	task.wait()
	if CONFIG.CIUDAD then
		local ok, err = pcall(styleCities, map, root)
		if not ok then
			warn("[FloorSkins] Error en ciudades: " .. tostring(err))
		end
	end
	if CONFIG.PARCHES then
		local total = 0
		for _, l in ipairs(readLanes(map)) do
			if token ~= mine then
				return
			end
			local ok, res = pcall(buildPatches, l, root)
			if ok then
				total += res
			else
				warn(string.format("[FloorSkins] Error en %s franja %d: %s", l.Faction, l.Strip, tostring(res)))
			end
			task.wait()
		end
		print("[FloorSkins] Parches colocados: " .. total)
	end
end

task.spawn(function()
	local t = 0
	while (not Workspace:FindFirstChild(MAP_NAME) or Workspace:GetAttribute("MapBuilt") ~= true) and t < 90 do
		task.wait(1)
		t += 1
	end
	task.wait(16) -- después de BiomeStyler, CityStyler y BiomeDetails
	build()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == MAP_NAME then
		local mine = token
		task.delay(24, function()
			if token == mine and Workspace:FindFirstChild(MAP_NAME) then
				build()
			end
		end)
	end
end)

local FloorSkins = {}
FloorSkins.Rebuild = build
return FloorSkins
