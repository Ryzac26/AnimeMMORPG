--!strict
--[[
    BiomeDetails (ModuleScript) -> ServerScriptService.Services.BiomeDetails
    DETALLES DE SUELO Y AMBIENTE de las 16 franjas PvE (se suma encima de BiomeStyler, no lo reemplaza):
      - SENDERO de tierra a lo largo de la franja (tramos, pasa junto al campamento).
      - Charcos, grietas (de lava en las zonas de fuego), flores o brotes, escombros, hongos y huesos según el tema de cada franja.
      - PARTÍCULAS de ambiente por franja: polen, bruma, lluvia, brasas, polvo, ceniza, pétalos, brillos o espuma.
    Todo es decoración sin colisión (CanCollide/CanQuery/CanTouch apagados) y se genera solo, en posiciones fijas (semilla fija).
    Cada franja se ajusta en la tabla THEMES: cuánto de cada detalle y qué partículas. Si el mapa se reconstruye, se rehace solo.
    Con StreamingEnabled solo se dibuja lo cercano al jugador.
]]
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- false = no dibuja el sendero, los charcos ni las grietas planos (los reemplazan los parches de FloorSkins, con borde suave)
local FLAT_DETAILS = false

local MAP_NAME = "Map_WC3_Style"
local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- Detalles de cada franja. Cantidades POR FRANJA (se reparten en toda su longitud).
--   puddle = charcos · crack = grietas · flower = flores/brotes · rubble = escombros · mushroom = hongos · bones = huesos
--   Puddle/Flower/Crack/Rubble color: Col. Glow = brilla (neón). Fx = partículas: pollen mist rain embers dust ash petals sparkle spray
type Theme = {
	Puddle: number?, Crack: number?, Flower: number?, Rubble: number?, Mushroom: number?, Bones: number?,
	PuddleCol: Color3?, CrackCol: Color3?, FlowerCol: Color3?, FlowerCol2: Color3?, RubbleCol: Color3?,
	Glow: boolean?, GlowCrack: boolean?, PathCol: Color3?, Fx: string, FxCol: Color3,
}
local THEMES: { [string]: Theme } = {
	Saiyan_1 = { Flower = 16, Rubble = 10, Puddle = 4, FlowerCol = C(255, 240, 120), FlowerCol2 = C(255, 170, 200), RubbleCol = C(130, 130, 128), PuddleCol = C(70, 150, 200), PathCol = C(150, 120, 80), Fx = "pollen", FxCol = C(255, 245, 160) },
	Saiyan_2 = { Puddle = 12, Flower = 16, Rubble = 6, FlowerCol = C(90, 255, 220), FlowerCol2 = C(150, 255, 160), PuddleCol = C(70, 200, 160), Glow = true, PathCol = C(110, 190, 150), Fx = "mist", FxCol = C(150, 255, 200) },
	Saiyan_3 = { Crack = 12, Rubble = 20, Bones = 4, CrackCol = C(30, 26, 22), RubbleCol = C(110, 100, 90), PathCol = C(130, 110, 85), Fx = "embers", FxCol = C(255, 150, 60) },
	Saiyan_4 = { Puddle = 8, Flower = 20, FlowerCol = C(255, 120, 190), FlowerCol2 = C(255, 220, 90), PuddleCol = C(255, 130, 190), Glow = true, PathCol = C(220, 130, 170), Fx = "sparkle", FxCol = C(255, 160, 220) },
	Shinobi_1 = { Mushroom = 14, Flower = 10, Puddle = 8, FlowerCol = C(190, 230, 140), FlowerCol2 = C(255, 255, 255), PuddleCol = C(80, 110, 100), PathCol = C(120, 100, 70), Fx = "mist", FxCol = C(200, 220, 215) },
	Shinobi_2 = { Puddle = 22, Rubble = 8, PuddleCol = C(90, 125, 165), RubbleCol = C(90, 98, 108), PathCol = C(70, 80, 92), Fx = "rain", FxCol = C(170, 200, 235) },
	Shinobi_3 = { Rubble = 18, Bones = 8, Crack = 8, RubbleCol = C(190, 150, 100), CrackCol = C(120, 90, 60), PathCol = C(200, 165, 110), Fx = "dust", FxCol = C(225, 195, 140) },
	Shinobi_4 = { Crack = 14, Rubble = 14, Puddle = 6, CrackCol = C(20, 18, 24), RubbleCol = C(70, 56, 60), PuddleCol = C(60, 80, 110), PathCol = C(70, 56, 64), Fx = "ash", FxCol = C(200, 190, 190) },
	Pirate_1 = { Rubble = 18, Puddle = 8, Flower = 8, RubbleCol = C(240, 235, 220), PuddleCol = C(80, 170, 215), FlowerCol = C(255, 130, 100), FlowerCol2 = C(255, 255, 255), PathCol = C(200, 180, 130), Fx = "spray", FxCol = C(220, 240, 255) },
	Pirate_2 = { Puddle = 20, Rubble = 10, Bones = 4, PuddleCol = C(60, 170, 200), RubbleCol = C(90, 120, 150), PathCol = C(170, 150, 110), Fx = "spray", FxCol = C(190, 235, 255) },
	Pirate_3 = { Crack = 10, Flower = 12, Rubble = 8, FlowerCol = C(255, 215, 110), FlowerCol2 = C(255, 255, 255), CrackCol = C(150, 150, 150), RubbleCol = C(230, 230, 225), PathCol = C(215, 215, 205), Fx = "sparkle", FxCol = C(255, 225, 130) },
	Pirate_4 = { Crack = 18, Rubble = 22, CrackCol = C(255, 110, 40), RubbleCol = C(60, 52, 48), GlowCrack = true, PathCol = C(80, 68, 60), Fx = "embers", FxCol = C(255, 130, 50) },
	Shinigami_1 = { Flower = 24, Rubble = 8, FlowerCol = C(230, 40, 50), FlowerCol2 = C(255, 255, 255), RubbleCol = C(120, 110, 100), PathCol = C(150, 130, 105), Fx = "petals", FxCol = C(255, 90, 100) },
	Shinigami_2 = { Bones = 14, Rubble = 18, Crack = 8, CrackCol = C(150, 150, 140), RubbleCol = C(235, 232, 220), PathCol = C(220, 215, 195), Fx = "mist", FxCol = C(235, 238, 245) },
	Shinigami_3 = { Crack = 14, Rubble = 16, CrackCol = C(150, 160, 175), RubbleCol = C(235, 238, 244), PathCol = C(205, 210, 220), Fx = "mist", FxCol = C(190, 205, 235) },
	Shinigami_4 = { Flower = 8, Puddle = 8, Rubble = 8, FlowerCol = C(255, 175, 200), FlowerCol2 = C(255, 255, 255), PuddleCol = C(150, 200, 235), RubbleCol = C(235, 232, 225), PathCol = C(225, 215, 195), Fx = "petals", FxCol = C(255, 185, 205) },
}

local PATH_WIDTH = 9
local EDGE_MARGIN = 36
local CAMP_CLEAR = 36
local FX_STEP_U = 150 -- una fuente de partículas cada 150 studs a lo largo de la franja

type Lane = { Biome: string, Faction: string, Strip: number, Start: Vector3, Dir: Vector3, FanC: number, FanK: number, U0: number, U1: number, FloorY: number, FloorCol: Color3 }

local folder: Folder? = nil
local token = 0

local function lanePoint(l: Lane, u: number, v: number): Vector3
	local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
	local p = l.Start + l.Dir * u + side * v
	return Vector3.new(p.X, l.FloorY, p.Z)
end

local function halfWidth(l: Lane, u: number): number
	return l.FanC + l.FanK * u
end

local function readLanes(map: Instance): { Lane }
	local found: { [string]: Lane } = {}
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
					found[key] = {
						Biome = biome, Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld, FanC = fc, FanK = fk,
						U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2, FloorCol = p.Color,
					}
				end
			end
		end
	end
	local out: { Lane } = {}
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

---------------------------------------------------------------------
-- Piezas
---------------------------------------------------------------------
local function flat(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?, transparency: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- disco plano (el cilindro de Roblox tiene el eje en X: se gira para que quede acostado)
local function disc(parent: Instance, name: string, diameter: number, pos: Vector3, color: Color3, mat: Enum.Material, transparency: number?, thickness: number?): Part
	return flat(parent, name, Vector3.new(thickness or 0.12, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, mat, Enum.PartType.Cylinder, transparency)
end

---------------------------------------------------------------------
-- Partículas
---------------------------------------------------------------------
local function emitterFor(kind: string, color: Color3): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.LightInfluence = 0.6
	e.Rate = 4
	e.Lifetime = NumberRange.new(8, 12)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.5)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.3), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1) })
	if kind == "pollen" then
		e.Rate = 3
		e.LightEmission = 0.6
		e.Size = NumberSequence.new(0.35)
		e.Acceleration = Vector3.new(1, 0.5, 0.5)
	elseif kind == "mist" then
		e.Rate = 1.6
		e.Lifetime = NumberRange.new(12, 18)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 24) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(0.7, 0.88), NumberSequenceKeypoint.new(1, 1) })
		e.LightInfluence = 1
		e.SpreadAngle = Vector2.new(20, 20)
		e.EmissionDirection = Enum.NormalId.Front
		e.Acceleration = Vector3.new(0.6, 0, 0.2)
	elseif kind == "rain" then
		e.Rate = 55
		e.Lifetime = NumberRange.new(0.9, 1.1)
		e.Speed = NumberRange.new(75, 90)
		e.SpreadAngle = Vector2.new(2, 2)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Size = NumberSequence.new(0.18)
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = NumberSequence.new(-14)
		e.Transparency = NumberSequence.new(0.55)
		e.LightEmission = 0.2
		e.Acceleration = Vector3.new(-6, 0, 0)
	elseif kind == "embers" then
		e.Rate = 4
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(3, 6)
		e.SpreadAngle = Vector2.new(35, 35)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) })
		e.Acceleration = Vector3.new(2, 2, 0)
	elseif kind == "dust" then
		e.Rate = 3
		e.Lifetime = NumberRange.new(8, 12)
		e.Speed = NumberRange.new(3, 6)
		e.SpreadAngle = Vector2.new(10, 10)
		e.EmissionDirection = Enum.NormalId.Front
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 16) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.88), NumberSequenceKeypoint.new(1, 1) })
		e.Acceleration = Vector3.new(4, 0, 0)
	elseif kind == "ash" then
		e.Rate = 5
		e.Lifetime = NumberRange.new(9, 13)
		e.Speed = NumberRange.new(1, 2)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.SpreadAngle = Vector2.new(25, 25)
		e.Size = NumberSequence.new(0.28)
		e.Acceleration = Vector3.new(1.5, -1.2, 0)
	elseif kind == "petals" then
		e.Rate = 3
		e.Lifetime = NumberRange.new(9, 14)
		e.Speed = NumberRange.new(1, 3)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.SpreadAngle = Vector2.new(30, 30)
		e.Size = NumberSequence.new(0.7)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-60, 60)
		e.LightEmission = 0.15
		e.Acceleration = Vector3.new(2, -0.8, 1)
	elseif kind == "sparkle" then
		e.Rate = 3
		e.Lifetime = NumberRange.new(4, 7)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new(0.1)
	elseif kind == "spray" then
		e.Rate = 2
		e.Lifetime = NumberRange.new(10, 14)
		e.Speed = NumberRange.new(1, 2)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 9), NumberSequenceKeypoint.new(1, 16) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.9), NumberSequenceKeypoint.new(1, 1) })
		e.EmissionDirection = Enum.NormalId.Front
		e.Acceleration = Vector3.new(3, 0, 0)
	end
	return e
end

---------------------------------------------------------------------
-- Detalles
---------------------------------------------------------------------
local function buildLane(l: Lane, root: Folder)
	local key = l.Faction .. "_" .. l.Strip
	local th = THEMES[key]
	if not th then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Detalles_" .. key
	f.Parent = root
	local rng = Random.new(l.Strip * 7919 + #l.Faction * 131 + 17)
	local len = l.U1 - l.U0
	local campPos = lanePoint(l, l.U0 + len * 0.5, 0)

	local function randomSpot(): Vector3?
		for _ = 1, 25 do
			local u = l.U0 + 20 + rng:NextNumber() * (len - 40)
			local half = math.max(8, halfWidth(l, u) - EDGE_MARGIN)
			local v = (rng:NextNumber() * 2 - 1) * half
			local p = lanePoint(l, u, v)
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(campPos.X, 0, campPos.Z)).Magnitude > CAMP_CLEAR then
				return p
			end
		end
		return nil
	end

	-- sendero: tramos que serpentean por el centro de la franja
	if FLAT_DETAILS then
		local step = 34
		local u = l.U0 + 30
		local pathCol = th.PathCol or l.FloorCol:Lerp(Color3.new(1, 1, 1), 0.15)
		while u < l.U1 - 30 do
			local v = math.sin(u / 95) * math.min(40, halfWidth(l, u) * 0.18)
			local v2 = math.sin((u + step) / 95) * math.min(40, halfWidth(l, u + step) * 0.18)
			local a, b = lanePoint(l, u, v), lanePoint(l, u + step, v2)
			local mid = (a + b) / 2 + Vector3.new(0, 0.07, 0)
			local d = b - a
			flat(f, "Sendero", Vector3.new(PATH_WIDTH + rng:NextNumber() * 3, 0.14, d.Magnitude + 2), CFrame.lookAt(mid, mid + d), pathCol, Enum.Material.Ground, nil, 0.05)
			u += step
		end
	end

	-- charcos
	for _ = 1, if FLAT_DETAILS then (th.Puddle or 0) else 0 do
		local p = randomSpot()
		if p then
			local d = 5 + rng:NextNumber() * 9
			local col = th.PuddleCol or Color3.fromRGB(80, 120, 160)
			local pd = disc(f, "Charco", d, p + Vector3.new(0, 0.1, 0), col, if th.Glow then Enum.Material.Neon else Enum.Material.Glass, if th.Glow then 0.35 else 0.3, 0.1)
			pd.Reflectance = 0.25
			disc(f, "CharcoOrilla", d + 1.2, p + Vector3.new(0, 0.07, 0), col:Lerp(Color3.new(0, 0, 0), 0.45), Enum.Material.Mud, 0.25, 0.08)
		end
	end

	-- grietas (dos o tres tramos finos, a veces ramificados)
	for _ = 1, if FLAT_DETAILS then (th.Crack or 0) else 0 do
		local p = randomSpot()
		if p then
			local yaw = rng:NextNumber() * math.pi
			local col = th.CrackCol or Color3.fromRGB(30, 28, 26)
			for k = 1, 3 do
				local len2 = 6 + rng:NextNumber() * 9
				local off = (k - 2) * 5
				local cf = CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, yaw + (k - 2) * 0.55, 0) * CFrame.new(0, 0, off)
				flat(f, "Grieta", Vector3.new(0.5 + rng:NextNumber() * 0.4, 0.1, len2), cf, col, if th.GlowCrack then Enum.Material.Neon else Enum.Material.Slate)
			end
		end
	end

	-- flores / brotes (parches de 3 a 5)
	for _ = 1, th.Flower or 0 do
		local p = randomSpot()
		if p then
			for _ = 1, rng:NextInteger(3, 5) do
				local q = p + Vector3.new((rng:NextNumber() - 0.5) * 7, 0, (rng:NextNumber() - 0.5) * 7)
				local col = if rng:NextNumber() < 0.5 then (th.FlowerCol or Color3.new(1, 1, 1)) else (th.FlowerCol2 or Color3.new(1, 1, 1))
				local h = 1.3 + rng:NextNumber() * 1.2
				flat(f, "Tallo", Vector3.new(0.18, h, 0.18), CFrame.new(q + Vector3.new(0, h / 2, 0)), Color3.fromRGB(60, 120, 60), Enum.Material.Grass)
				flat(f, "Flor", Vector3.new(0.9, 0.9, 0.9), CFrame.new(q + Vector3.new(0, h + 0.3, 0)), col, if th.Glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			end
		end
	end

	-- escombros
	for _ = 1, th.Rubble or 0 do
		local p = randomSpot()
		if p then
			local col = th.RubbleCol or Color3.fromRGB(110, 110, 110)
			for _ = 1, rng:NextInteger(2, 4) do
				local q = p + Vector3.new((rng:NextNumber() - 0.5) * 5, 0, (rng:NextNumber() - 0.5) * 5)
				local s = 0.7 + rng:NextNumber() * 1.6
				flat(f, "Escombro", Vector3.new(s * 1.3, s, s), CFrame.new(q + Vector3.new(0, s / 2 - 0.1, 0)) * CFrame.Angles(rng:NextNumber() * 0.6, rng:NextNumber() * 6, rng:NextNumber() * 0.6), col:Lerp(Color3.new(0.4, 0.4, 0.4), rng:NextNumber() * 0.3), Enum.Material.Slate)
			end
		end
	end

	-- hongos
	for _ = 1, th.Mushroom or 0 do
		local p = randomSpot()
		if p then
			for _ = 1, rng:NextInteger(2, 3) do
				local q = p + Vector3.new((rng:NextNumber() - 0.5) * 4, 0, (rng:NextNumber() - 0.5) * 4)
				local h = 0.9 + rng:NextNumber() * 1.2
				flat(f, "HongoTallo", Vector3.new(0.35, h, 0.35), CFrame.new(q + Vector3.new(0, h / 2, 0)), Color3.fromRGB(225, 215, 195), Enum.Material.SmoothPlastic)
				flat(f, "HongoSombrero", Vector3.new(1.7, 0.9, 1.7), CFrame.new(q + Vector3.new(0, h, 0)), Color3.fromRGB(170, 70, 60), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			end
		end
	end

	-- huesos (costillas y un cráneo)
	for _ = 1, th.Bones or 0 do
		local p = randomSpot()
		if p then
			local yaw = rng:NextNumber() * math.pi * 2
			for k = -2, 2 do
				flat(f, "Costilla", Vector3.new(0.25, 0.25, 2.4), CFrame.new(p + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(k * 0.8, 0, 0) * CFrame.Angles(math.rad(35), 0, 0), Color3.fromRGB(235, 228, 210), Enum.Material.SmoothPlastic)
			end
			flat(f, "Columna", Vector3.new(0.4, 0.4, 5), CFrame.new(p + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, yaw + math.pi / 2, 0), Color3.fromRGB(225, 218, 200), Enum.Material.SmoothPlastic)
			flat(f, "Craneo", Vector3.new(1.4, 1.2, 1.5), CFrame.new(p + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, yaw, 0) * CFrame.new(3.4, 0, 0), Color3.fromRGB(235, 228, 210), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		end
	end

	-- partículas: una fuente cada FX_STEP_U a lo largo, repartidas a ambos lados
	local count = 0
	local u = l.U0 + FX_STEP_U / 2
	while u < l.U1 do
		for _, frac in ipairs({ -0.45, 0.45 }) do
			local half = halfWidth(l, u)
			local p = lanePoint(l, u, half * frac)
			local at = if th.Fx == "rain" then p + Vector3.new(0, 70, 0) else p + Vector3.new(0, if th.Fx == "mist" or th.Fx == "spray" or th.Fx == "dust" then 6 else 9, 0)
			local part = flat(f, "Ambiente", Vector3.new(110, 1, 110), CFrame.lookAt(at, at + l.Dir), th.FxCol, Enum.Material.SmoothPlastic, nil, 1)
			part.Massless = true
			emitterFor(th.Fx, th.FxCol).Parent = part
			count += 1
		end
		u += FX_STEP_U
	end
end

local function build()
	token += 1
	local mine = token
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		return
	end
	local lanes = readLanes(map)
	if #lanes == 0 then
		return
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	-- copias viejas guardadas en el lugar (si alguna vez se generó en Edit y se guardó): se borran para no duplicar
	for _, stale in ipairs(Workspace:GetChildren()) do
		if stale.Name == "DetallesZona" then
			stale:Destroy()
		end
	end
	local root = Instance.new("Folder")
	root.Name = "DetallesZona"
	root.Parent = Workspace
	folder = root
	for _, l in ipairs(lanes) do
		if token ~= mine then
			return
		end
		local ok, err = pcall(buildLane, l, root)
		if not ok then
			warn(string.format("[BiomeDetails] Error en %s franja %d: %s", l.Faction, l.Strip, tostring(err)))
		end
		task.wait() -- reparte el trabajo en varios cuadros
	end
	print("[BiomeDetails] Detalles de suelo y partículas listos.")
end

task.spawn(function()
	local t = 0
	while (not Workspace:FindFirstChild(MAP_NAME) or Workspace:GetAttribute("MapBuilt") ~= true) and t < 90 do
		task.wait(1)
		t += 1
	end
	task.wait(4)
	build()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == MAP_NAME then
		local mine = token
		task.delay(12, function()
			if token == mine and Workspace:FindFirstChild(MAP_NAME) then
				build()
			end
		end)
	end
end)

local BiomeDetails = {}
BiomeDetails.Rebuild = build

return BiomeDetails
