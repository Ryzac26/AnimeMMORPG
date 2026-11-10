--!strict
--[[
    MobBuilder (ModuleScript) -> ServerScriptService.Services.Mobs.MobBuilder
    Construye el MODELO R6 de un enemigo a partir de su "Look" (MobLooks). Solo visual: no sabe de vida, IA ni daño.
      Build(look, displayName) -> Model con Humanoid, 6 partes R6, Motor6D y accesorios (pelo redondeado, capa, cola, cuernos,
                                  cinta, máscara, sombrero, parche, arma agarrada en la mano, scouter, aura)
      Animate(model, speedFactor, t) -> balanceo simple de brazos/piernas (lo llama MobBrain mientras camina)
    Pelo: SIEMPRE en bloques/esferas redondeadas (nada de picos).
]]
local Players = game:GetService("Players")

local MobBuilder = {}

local function part(name: string, size: Vector3, color: Color3, parent: Instance, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- Pieza "lógica": en R6 es la pieza real; en R15 reparte el accesorio entre brazo/antebrazo/mano, muslo/pierna/pie, etc.
-- Part = pieza real principal; Resolve(offset en coordenadas R6) -> (pieza real, offset real)
type Logical = { Part: BasePart, Resolve: (CFrame) -> (BasePart, CFrame), Fit: ((Vector3, CFrame) -> (Vector3, CFrame))? }

local function resolveTo(to: any, off: CFrame): (BasePart, CFrame)
	if typeof(to) == "table" then
		return (to :: Logical).Resolve(off)
	end
	return to :: BasePart, off
end

local function accessory(name: string, size: Vector3, color: Color3, to: any, offset: CFrame, parent: Instance, shape: Enum.PartType?, material: Enum.Material?): Part
	local base
	if typeof(to) == "table" and (to :: Logical).Fit then
		-- ajuste a las medidas REALES del avatar (ancho de brazo/pierna/torso/cabeza)
		size, offset = ((to :: Logical).Fit :: any)(size, offset)
	end
	base, offset = resolveTo(to, offset)
	to = base
	local p = part(name, size, color, parent, shape)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	if material then
		p.Material = material
	end
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame, parent: Instance)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = parent
end

local function darker(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

---------------------------------------------------------------------
-- PEINADOS DE LOS PERSONAJES (diseñados y revisados en vista previa 3D). Coordenadas en studs de una cabeza R15 de 1.2 (centro 0,
-- frente = -Z, espalda = +Z, arriba = +Y); se escalan solos si la cabeza cambia de tamaño. Cada entrada:
--   {"B", sx, sy, sz, x, y, z}                         elipsoide (masa de pelo)
--   {"K", sx, sy, sz, x, y, z}                         bloque (flequillo plano, melena)
--   {"S", bx, by, bz, dx, dy, dz, largo, radio, ancho, grosor}   mechón/púa: base, dirección, largo, radio de la base y aplastado
-- Para añadir un peinado: copia una entrada, cámbiale el nombre y ponlo en HairStyle del personaje (PlayerOutfits > Looks).
---------------------------------------------------------------------
local HAIR: { [string]: { { any } } } = {
	goku = {
		{ "B", 1.38, 0.95, 1.36, 0, 0.4, 0.07 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.8, -0.05, 0, 1, -0.2, 0.95, 0.25, 1.4, 0.55 },
		{ "S", 0.36, 0.78, -0.05, 0.5, 1, -0.05, 0.9, 0.23, 1.3, 0.55 },
		{ "S", -0.36, 0.78, -0.05, -0.5, 1, -0.05, 0.9, 0.23, 1.3, 0.55 },
		{ "S", 0.55, 0.62, 0.12, 1, 0.55, 0.1, 0.75, 0.2, 1.2, 0.6 },
		{ "S", -0.55, 0.62, 0.12, -1, 0.55, 0.1, 0.75, 0.2, 1.2, 0.6 },
		{ "S", 0, 0.72, 0.42, 0, 0.45, 1, 0.8, 0.23, 1.4, 0.6 },
		{ "S", 0.32, 0.74, 0.35, 0.55, 0.7, 0.9, 0.75, 0.2, 1.2, 0.6 },
		{ "S", -0.32, 0.74, 0.35, -0.55, 0.7, 0.9, 0.75, 0.2, 1.2, 0.6 },
		{ "S", 0.34, 0.52, -0.6, 0.15, -1, -0.1, 0.36, 0.13, 1.4, 0.5 },
		{ "S", -0.34, 0.52, -0.6, -0.15, -1, -0.1, 0.36, 0.13, 1.4, 0.5 },
		{ "S", 0, 0.54, -0.62, 0, -1, -0.15, 0.4, 0.14, 1.4, 0.5 },
	},
	vegeta = {
		{ "B", 1.36, 0.9, 1.34, 0, 0.38, 0.06 },
		{ "B", 1.319, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.56, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.56, 0.24, 0.1 },
		{ "B", 1.1, 1.3, 1, 0, 0.95, 0.05 },
		{ "S", 0, 1.3, 0, 0, 1, 0, 0.9, 0.3, 1.3, 0.8 },
		{ "S", 0.3, 1.2, 0, 0.22, 1, 0, 0.75, 0.22, 1.2, 0.8 },
		{ "S", -0.3, 1.2, 0, -0.22, 1, 0, 0.75, 0.22, 1.2, 0.8 },
		{ "S", 0.5, 0.6, 0.1, 0.6, 1, 0, 0.5, 0.18, 1.1, 0.8 },
		{ "S", -0.5, 0.6, 0.1, -0.6, 1, 0, 0.5, 0.18, 1.1, 0.8 },
		{ "S", 0, 0.45, -0.62, 0, -1, -0.1, 0.3, 0.12, 1.2, 0.5 },
		{ "K", 0.1, 0.45, 0.6, 0.66, 0.15, 0 },
		{ "K", 0.1, 0.45, 0.6, -0.66, 0.15, 0 },
	},
	trunks = {
		{ "B", 1.38, 0.95, 1.38, 0, 0.38, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "B", 1.3, 1, 0.5, 0, 0, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.35, -1, -0.1, 0.55, 0.15, 1.4, 0.5 },
		{ "S", 0.1, 0.5, -0.62, 0.15, -1, -0.1, 0.5, 0.14, 1.4, 0.5 },
		{ "S", 0.38, 0.5, -0.55, 0.55, -1, -0.1, 0.45, 0.12, 1.4, 0.5 },
		{ "S", -0.2, 0.85, 0, -0.3, 1, 0.1, 0.45, 0.2, 1.3, 0.7 },
		{ "S", 0.15, 0.88, 0, 0.3, 1, 0.1, 0.45, 0.2, 1.3, 0.7 },
		{ "S", 0.62, 0.3, 0, 0.05, -1, 0.1, 0.6, 0.12, 0.8, 1.4 },
		{ "S", -0.62, 0.3, 0, -0.05, -1, 0.1, 0.6, 0.12, 0.8, 1.4 },
	},
	gohan = {
		{ "B", 1.38, 0.9, 1.36, 0, 0.38, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", -0.25, 0.8, -0.1, -0.3, 1, -0.1, 0.5, 0.22, 1.3, 0.7 },
		{ "S", 0.25, 0.82, -0.05, 0.3, 1, -0.1, 0.5, 0.22, 1.3, 0.7 },
		{ "S", 0, 0.85, 0.1, 0, 1, 0.3, 0.5, 0.22, 1.3, 0.7 },
		{ "S", 0.45, 0.65, 0.1, 1, 0.7, 0, 0.4, 0.18, 1.2, 0.7 },
		{ "S", -0.45, 0.65, 0.1, -1, 0.7, 0, 0.4, 0.18, 1.2, 0.7 },
		{ "S", 0.05, 0.54, -0.62, 0, -1, -0.05, 0.45, 0.13, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.36, 0.12, 1.3, 0.5 },
		{ "S", 0.32, 0.5, -0.6, 0.1, -1, -0.1, 0.36, 0.12, 1.3, 0.5 },
	},
	bulma = {
		{ "B", 1.4, 0.9, 1.38, 0, 0.38, 0.06 },
		{ "B", 1.358, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.58, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.58, 0.24, 0.1 },
		{ "B", 1.5, 1.7, 0.5, 0, -0.25, 0.52 },
		{ "K", 0.32, 1.5, 1.1, 0.72, -0.2, 0.12 },
		{ "K", 0.32, 1.5, 1.1, -0.72, -0.2, 0.12 },
		{ "B", 0.5, 0.5, 0.5, 0.78, -1.05, 0.2 },
		{ "B", 0.5, 0.5, 0.5, -0.78, -1.05, 0.2 },
		{ "S", 0.3, 0.5, -0.6, 0.1, -1, -0.1, 0.4, 0.13, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.4, 0.13, 1.3, 0.5 },
	},
	gaara = {
		{ "B", 1.38, 0.78, 1.36, 0, 0.34, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.7, -0.1, 0.1, 1, -0.2, 0.45, 0.2, 1.3, 0.7 },
		{ "S", 0.3, 0.68, 0, 0.6, 1, 0.1, 0.42, 0.2, 1.3, 0.7 },
		{ "S", -0.3, 0.68, 0, -0.6, 1, 0.1, 0.42, 0.2, 1.3, 0.7 },
		{ "S", 0.5, 0.55, 0.15, 1, 0.5, 0.3, 0.38, 0.18, 1.3, 0.7 },
		{ "S", -0.5, 0.55, 0.15, -1, 0.5, 0.3, 0.38, 0.18, 1.3, 0.7 },
		{ "S", 0, 0.65, 0.45, 0, 0.5, 1, 0.45, 0.2, 1.3, 0.7 },
		{ "S", 0.3, 0.62, 0.4, 0.5, 0.4, 1, 0.4, 0.18, 1.3, 0.7 },
		{ "S", -0.3, 0.62, 0.4, -0.5, 0.4, 1, 0.4, 0.18, 1.3, 0.7 },
		{ "S", -0.15, 0.5, -0.62, -0.1, -1, -0.1, 0.3, 0.12, 1.3, 0.5 },
		{ "S", 0.2, 0.5, -0.62, 0.1, -1, -0.1, 0.26, 0.12, 1.3, 0.5 },
	},
	naruto = {
		{ "B", 1.38, 0.9, 1.36, 0, 0.4, 0.07 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.82, -0.1, 0, 1, -0.2, 0.65, 0.2, 1.3, 0.6 },
		{ "S", 0.3, 0.8, -0.05, 0.5, 1, -0.05, 0.6, 0.2, 1.2, 0.6 },
		{ "S", -0.3, 0.8, -0.05, -0.5, 1, -0.05, 0.6, 0.2, 1.2, 0.6 },
		{ "S", 0.5, 0.65, 0.1, 1, 0.7, 0.1, 0.55, 0.19, 1.2, 0.6 },
		{ "S", -0.5, 0.65, 0.1, -1, 0.7, 0.1, 0.55, 0.19, 1.2, 0.6 },
		{ "S", 0, 0.75, 0.4, 0, 0.5, 1, 0.6, 0.2, 1.3, 0.6 },
		{ "S", 0.3, 0.77, 0.35, 0.55, 0.7, 0.9, 0.55, 0.18, 1.2, 0.6 },
		{ "S", -0.3, 0.77, 0.35, -0.55, 0.7, 0.9, 0.55, 0.18, 1.2, 0.6 },
		{ "S", 0.66, 0.1, -0.1, 0.15, -1, 0, 0.38, 0.1, 1.2, 0.8 },
		{ "S", -0.66, 0.1, -0.1, -0.15, -1, 0, 0.38, 0.1, 1.2, 0.8 },
	},
	sasuke = {
		{ "B", 1.38, 0.92, 1.38, 0, 0.38, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.7, 0.4, 0, 0.55, 1, 0.9, 0.24, 1.3, 0.6 },
		{ "S", 0.3, 0.68, 0.4, 0.55, 0.5, 1, 0.8, 0.22, 1.3, 0.6 },
		{ "S", -0.3, 0.68, 0.4, -0.55, 0.5, 1, 0.8, 0.22, 1.3, 0.6 },
		{ "S", 0, 0.88, 0.1, 0, 1, 0.5, 0.6, 0.22, 1.3, 0.6 },
		{ "S", 0.42, 0.5, -0.55, 0.15, -1, -0.15, 0.8, 0.13, 1.3, 0.5 },
		{ "S", -0.42, 0.5, -0.55, -0.15, -1, -0.15, 0.8, 0.13, 1.3, 0.5 },
		{ "S", 0, 0.52, -0.62, 0, -1, -0.15, 0.45, 0.12, 1.3, 0.5 },
	},
	itachi = {
		{ "B", 1.4, 0.95, 1.4, 0, 0.38, 0.06 },
		{ "B", 1.358, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.58, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.58, 0.24, 0.1 },
		{ "B", 1.3, 1, 0.5, 0, 0, 0.5 },
		{ "S", 0, 0.2, 0.6, 0, -1, 0.25, 1.9, 0.22, 1.6, 0.8 },
		{ "S", 0.42, 0.5, -0.55, 0.1, -1, -0.1, 1, 0.13, 1.2, 0.5 },
		{ "S", -0.42, 0.5, -0.55, -0.1, -1, -0.1, 1, 0.13, 1.2, 0.5 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.1, 0.35, 0.12, 1.3, 0.5 },
	},
	kakashi = {
		{ "B", 1.38, 0.9, 1.36, 0, 0.4, 0.07 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.82, 0, 0, 1, 0.3, 0.8, 0.22, 1.4, 0.6 },
		{ "S", 0.3, 0.8, 0, 0.7, 1, 0.3, 0.8, 0.21, 1.3, 0.6 },
		{ "S", -0.3, 0.8, 0, -0.7, 1, 0.3, 0.8, 0.21, 1.3, 0.6 },
		{ "S", 0.5, 0.62, 0.1, 1, 0.6, 0.4, 0.75, 0.2, 1.3, 0.6 },
		{ "S", -0.5, 0.62, 0.1, -1, 0.6, 0.4, 0.75, 0.2, 1.3, 0.6 },
		{ "S", 0, 0.72, 0.42, 0, 0.6, 1, 0.75, 0.22, 1.4, 0.6 },
		{ "S", 0.3, 0.74, 0.38, 0.6, 0.6, 1, 0.7, 0.2, 1.3, 0.6 },
		{ "S", -0.3, 0.74, 0.38, -0.6, 0.6, 1, 0.7, 0.2, 1.3, 0.6 },
		{ "S", 0.45, 0.4, -0.45, 0.3, -0.4, -0.3, 0.3, 0.1, 1.3, 0.7 },
		{ "S", -0.45, 0.4, -0.45, -0.3, -0.4, -0.3, 0.3, 0.1, 1.3, 0.7 },
	},
	sakura = {
		{ "B", 1.42, 0.9, 1.4, 0, 0.38, 0.06 },
		{ "B", 1.377, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.59, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.59, 0.24, 0.1 },
		{ "B", 1.5, 1.3, 0.5, 0, -0.05, 0.52 },
		{ "K", 0.3, 1, 1, 0.72, -0.02, 0.08 },
		{ "K", 0.3, 1, 1, -0.72, -0.02, 0.08 },
		{ "S", 0.3, 0.5, -0.6, 0.1, -1, -0.1, 0.3, 0.13, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.3, 0.13, 1.3, 0.5 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.1, 0.3, 0.13, 1.3, 0.5 },
	},
	luffy = {
		{ "B", 1.36, 0.7, 1.36, 0, 0.33, 0.06 },
		{ "B", 1.319, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.56, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.56, 0.24, 0.1 },
		{ "S", 0.3, 0.5, -0.6, 0.1, -1, -0.1, 0.3, 0.12, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.3, 0.12, 1.3, 0.5 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.1, 0.3, 0.12, 1.3, 0.5 },
	},
	zoro = {
		{ "B", 1.38, 0.8, 1.36, 0, 0.34, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.7, -0.05, 0, 1, 0, 0.35, 0.2, 1.3, 0.7 },
		{ "S", 0.3, 0.68, 0, 0.6, 1, 0, 0.33, 0.19, 1.3, 0.7 },
		{ "S", -0.3, 0.68, 0, -0.6, 1, 0, 0.33, 0.19, 1.3, 0.7 },
		{ "S", 0.5, 0.5, 0.1, 1, 0.4, 0, 0.3, 0.17, 1.3, 0.7 },
		{ "S", -0.5, 0.5, 0.1, -1, 0.4, 0, 0.3, 0.17, 1.3, 0.7 },
		{ "S", 0, 0.65, 0.4, 0, 0.5, 1, 0.35, 0.19, 1.3, 0.7 },
		{ "S", 0.1, 0.5, -0.62, 0, -1, -0.05, 0.28, 0.12, 1.3, 0.5 },
		{ "S", -0.22, 0.5, -0.6, -0.05, -1, -0.05, 0.24, 0.12, 1.3, 0.5 },
	},
	usopp = {
		{ "B", 1.9, 1.7, 1.9, 0, 0.55, 0.1 },
		{ "B", 0.7, 0.7, 0.7, 0.8, 0.95, 0.1 },
		{ "B", 0.7, 0.7, 0.7, -0.8, 0.95, 0.1 },
		{ "B", 0.7, 0.7, 0.7, 0.7, 0.45, 0.6 },
		{ "B", 0.7, 0.7, 0.7, -0.7, 0.45, 0.6 },
		{ "B", 0.6, 0.6, 0.6, 0.85, 0.25, -0.2 },
		{ "B", 0.6, 0.6, 0.6, -0.85, 0.25, -0.2 },
		{ "B", 0.7, 0.7, 0.7, 0, 1.45, 0.1 },
		{ "B", 0.7, 0.7, 0.7, 0, 0.45, 0.9 },
	},
	sanji = {
		{ "B", 1.38, 0.9, 1.38, 0, 0.38, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "B", 1.3, 0.8, 0.5, 0, 0.1, 0.5 },
		{ "S", -0.15, 0.5, -0.62, 0.25, -1, -0.1, 0.75, 0.22, 1.8, 0.45 },
		{ "S", 0.25, 0.5, -0.6, 0.3, -1, -0.1, 0.3, 0.1, 1.3, 0.5 },
		{ "S", 0.1, 0.85, 0, 0.3, 1, 0.1, 0.4, 0.2, 1.3, 0.7 },
	},
	chad = {
		{ "B", 1.38, 0.85, 1.38, 0, 0.36, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.7, -0.05, 0, 1, 0.1, 0.35, 0.22, 1.3, 0.7 },
		{ "S", 0.3, 0.68, 0, 0.6, 1, 0.1, 0.32, 0.2, 1.3, 0.7 },
		{ "S", -0.3, 0.68, 0, -0.6, 1, 0.1, 0.32, 0.2, 1.3, 0.7 },
		{ "S", 0, 0.65, 0.4, 0, 0.6, 1, 0.35, 0.2, 1.3, 0.7 },
		{ "S", 0.28, 0.54, -0.6, 0.05, -1, -0.05, 0.38, 0.14, 1.5, 0.5 },
		{ "S", -0.28, 0.54, -0.6, -0.05, -1, -0.05, 0.38, 0.14, 1.5, 0.5 },
		{ "S", 0, 0.55, -0.62, 0, -1, -0.05, 0.4, 0.14, 1.5, 0.5 },
	},
	ichigo = {
		{ "B", 1.38, 0.95, 1.36, 0, 0.4, 0.07 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "S", 0, 0.85, -0.05, 0.1, 1, -0.3, 0.9, 0.24, 1.4, 0.55 },
		{ "S", 0.34, 0.82, -0.02, 0.7, 1, -0.1, 0.85, 0.22, 1.3, 0.55 },
		{ "S", -0.34, 0.82, -0.02, -0.7, 1, -0.1, 0.85, 0.22, 1.3, 0.55 },
		{ "S", 0.55, 0.62, 0.12, 1, 0.5, 0.2, 0.7, 0.2, 1.2, 0.6 },
		{ "S", -0.55, 0.62, 0.12, -1, 0.5, 0.2, 0.7, 0.2, 1.2, 0.6 },
		{ "S", 0, 0.72, 0.42, 0, 0.5, 1, 0.85, 0.23, 1.4, 0.6 },
		{ "S", 0.3, 0.74, 0.36, 0.6, 0.6, 1, 0.75, 0.2, 1.3, 0.6 },
		{ "S", -0.3, 0.74, 0.36, -0.6, 0.6, 1, 0.75, 0.2, 1.3, 0.6 },
		{ "S", -0.34, 0.54, -0.6, -0.1, -1, -0.1, 0.38, 0.14, 1.4, 0.5 },
		{ "S", 0, 0.55, -0.62, 0, -1, -0.15, 0.42, 0.15, 1.4, 0.5 },
		{ "S", 0.34, 0.54, -0.6, 0.3, -1, -0.1, 0.46, 0.14, 1.4, 0.5 },
	},
	yoruichi = {
		{ "B", 1.4, 0.92, 1.4, 0, 0.38, 0.06 },
		{ "B", 1.358, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.58, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.58, 0.24, 0.1 },
		{ "S", 0, 0.45, 0.62, 0, -1, 0.15, 2.3, 0.24, 1.4, 0.8 },
		{ "S", 0.45, 0.5, -0.5, 0.1, -1, -0.1, 0.85, 0.12, 1.2, 0.5 },
		{ "S", -0.45, 0.5, -0.5, -0.1, -1, -0.1, 0.85, 0.12, 1.2, 0.5 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.1, 0.35, 0.12, 1.3, 0.5 },
	},
	uryu = {
		{ "B", 1.38, 0.9, 1.38, 0, 0.38, 0.06 },
		{ "B", 1.339, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.57, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.57, 0.24, 0.1 },
		{ "B", 1.3, 0.8, 0.5, 0, 0.1, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.45, -1, -0.1, 0.55, 0.14, 1.6, 0.5 },
		{ "S", 0.15, 0.5, -0.62, 0.1, -1, -0.1, 0.35, 0.12, 1.4, 0.5 },
		{ "S", 0.38, 0.5, -0.55, 0.5, -1, -0.1, 0.38, 0.12, 1.4, 0.5 },
	},
	hitsugaya = {
		{ "B", 1.36, 0.85, 1.36, 0, 0.38, 0.06 },
		{ "B", 1.319, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.56, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.56, 0.24, 0.1 },
		{ "S", 0, 0.78, -0.05, 0, 1, -0.15, 0.6, 0.22, 1.3, 0.6 },
		{ "S", 0.3, 0.75, 0, 0.55, 1, 0, 0.55, 0.2, 1.2, 0.6 },
		{ "S", -0.3, 0.75, 0, -0.55, 1, 0, 0.55, 0.2, 1.2, 0.6 },
		{ "S", 0.5, 0.6, 0.1, 1, 0.6, 0.1, 0.45, 0.18, 1.2, 0.6 },
		{ "S", -0.5, 0.6, 0.1, -1, 0.6, 0.1, 0.45, 0.18, 1.2, 0.6 },
		{ "S", 0, 0.68, 0.4, 0, 0.4, 1, 0.5, 0.2, 1.3, 0.6 },
		{ "S", 0.3, 0.7, 0.35, 0.55, 0.6, 1, 0.45, 0.18, 1.2, 0.6 },
		{ "S", -0.3, 0.7, 0.35, -0.55, 0.6, 1, 0.45, 0.18, 1.2, 0.6 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.2, 0.4, 0.13, 1.3, 0.5 },
		{ "S", 0.3, 0.5, -0.6, 0.1, -1, -0.1, 0.34, 0.12, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.34, 0.12, 1.3, 0.5 },
	},
	orihime = {
		{ "B", 1.42, 0.92, 1.4, 0, 0.38, 0.06 },
		{ "B", 1.377, 1.35, 0.62, 0, 0.02, 0.5 },
		{ "B", 0.3, 0.62, 0.85, 0.59, 0.24, 0.1 },
		{ "B", 0.3, 0.62, 0.85, -0.59, 0.24, 0.1 },
		{ "K", 1.5, 2.6, 0.4, 0, -0.95, 0.68 },
		{ "K", 0.3, 2.4, 0.9, 0.72, -0.75, 0.1 },
		{ "K", 0.3, 2.4, 0.9, -0.72, -0.75, 0.1 },
		{ "S", 0.3, 0.5, -0.6, 0.1, -1, -0.1, 0.35, 0.13, 1.3, 0.5 },
		{ "S", -0.3, 0.5, -0.6, -0.1, -1, -0.1, 0.35, 0.13, 1.3, 0.5 },
		{ "S", 0, 0.5, -0.62, 0, -1, -0.1, 0.35, 0.13, 1.3, 0.5 },
	},
}

local function addHairNew(prims: { { any } }, color: Color3, head: any, model: Model)
	local nf: any = head
	local part: BasePart
	if typeof(head) == "table" then
		-- sin el "ajuste" de cabeza ancha de R6: estos peinados ya van en medidas de cabeza R15
		nf = { Part = head.Part, Resolve = head.Resolve }
		part = head.Part
	else
		part = head
	end
	local hs = math.clamp(part.Size.Y / 1.2, 0.6, 1.6)
	if part.Size.Y < 1.1 and part.Size.X > 1.6 then
		hs = 1 -- cabeza R6 (pieza de 2x1x1 con una malla de ~1.25)
	end
	local Ball = Enum.PartType.Ball
	for _, p in ipairs(prims) do
		local k = p[1]
		if k == "B" or k == "K" then
			accessory("Hair", Vector3.new(p[2], p[3], p[4]) * hs, color, nf, CFrame.new(p[5] * hs, p[6] * hs, p[7] * hs), model, if k == "B" then Ball else nil)
		elseif k == "S" then
			local d = Vector3.new(p[5], p[6], p[7]).Unit
			local xa = Vector3.xAxis - d * Vector3.xAxis:Dot(d)
			if xa.Magnitude < 1e-3 then
				xa = Vector3.zAxis - d * Vector3.zAxis:Dot(d)
			end
			xa = xa.Unit
			local ya = d:Cross(xa)
			local base = Vector3.new(p[2], p[3], p[4])
			local len, r, fx, fy = p[8], p[9], p[10], p[11]
			for i = 0, 3 do
				local t = (i + 0.5) / 4
				local ri = r * (1 - 0.9 * t ^ 1.1)
				local c = (base + d * (len * t)) * hs
				accessory("Hair", Vector3.new(ri * 2 * fx, ri * 2 * fy, len / 4 * 1.45 * 2) * hs, color, nf, CFrame.fromMatrix(c, xa, ya, d), model, Ball)
			end
		end
	end
end


local function addHair(style: string, color: Color3, head: any, model: Model)
	if HAIR[style] then
		addHairNew(HAIR[style], color, head, model)
		return
	end
	local ball = Enum.PartType.Ball
	local function h(size: Vector3, off: Vector3, shape: Enum.PartType?)
		accessory("Hair", size, color, head, CFrame.new(off), model, shape)
	end
	if style == "flat" then
		h(Vector3.new(2.15, 0.55, 1.15), Vector3.new(0, 0.74, 0), ball)
	elseif style == "messy" then
		h(Vector3.new(2.15, 0.7, 1.15), Vector3.new(0, 0.74, 0), ball)
		for _, o in ipairs({ Vector3.new(-0.6, 0.85, 0), Vector3.new(0.5, 0.9, 0.1), Vector3.new(0, 0.95, -0.3) }) do
			h(Vector3.new(0.7, 0.7, 0.7), o, ball)
		end
	elseif style == "spiky" then -- "pelo en volumen": esferas redondeadas, sin puntas
		h(Vector3.new(2.2, 0.75, 1.2), Vector3.new(0, 0.74, 0.05), ball)
		for _, o in ipairs({ Vector3.new(-0.65, 1.05, 0.05), Vector3.new(0.65, 1.05, 0.05), Vector3.new(0, 1.2, 0.05), Vector3.new(-0.3, 1.1, -0.15), Vector3.new(0.3, 1.1, -0.15) }) do
			h(Vector3.new(0.8, 0.8, 0.8), o, ball)
		end
	elseif style == "straightLong" then
		h(Vector3.new(2.15, 0.6, 1.2), Vector3.new(0, 0.74, 0), ball)
		h(Vector3.new(2.0, 1.6, 0.3), Vector3.new(0, -0.35, 0.55))
		h(Vector3.new(0.25, 1.2, 0.9), Vector3.new(-0.98, -0.3, 0))
		h(Vector3.new(0.25, 1.2, 0.9), Vector3.new(0.98, -0.3, 0))
	elseif style == "tall" then -- Vegeta: llama hacia arriba
		h(Vector3.new(2.2, 0.8, 1.2), Vector3.new(0, 0.74, 0), ball)
		h(Vector3.new(1.6, 1.0, 1.0), Vector3.new(0, 1.2, 0), ball)
		h(Vector3.new(1.0, 0.9, 0.8), Vector3.new(0, 1.9, 0), ball)
		h(Vector3.new(2.0, 0.6, 0.3), Vector3.new(0, 0.1, 0.55))
	elseif style == "swept" then -- Sasuke: flequillo a los lados y nuca alta
		h(Vector3.new(2.2, 0.8, 1.2), Vector3.new(0, 0.74, 0.05), ball)
		h(Vector3.new(0.3, 0.45, 0.2), Vector3.new(-0.38, 0.4, -0.58))
		h(Vector3.new(0.3, 0.45, 0.2), Vector3.new(0.38, 0.4, -0.58))
		h(Vector3.new(1.6, 1.0, 0.8), Vector3.new(0, 0.9, 0.6), ball)
		h(Vector3.new(2.0, 0.7, 0.4), Vector3.new(0, 0.1, 0.6))
	elseif style == "bob" then -- Sakura: corto
		h(Vector3.new(2.25, 0.9, 1.25), Vector3.new(0, 0.45, 0), ball)
		h(Vector3.new(2.1, 1.5, 0.35), Vector3.new(0, -0.25, 0.6))
		h(Vector3.new(0.3, 1.2, 1.0), Vector3.new(-1.05, -0.2, 0.05))
		h(Vector3.new(0.3, 1.2, 1.0), Vector3.new(1.05, -0.2, 0.05))
		h(Vector3.new(1.6, 0.3, 0.2), Vector3.new(0, 0.5, -0.55))
	elseif style == "swoop" then -- Sanji: flequillo que tapa el ojo izquierdo
		h(Vector3.new(2.2, 0.8, 1.2), Vector3.new(0, 0.74, 0), ball)
		h(Vector3.new(2.0, 0.9, 0.3), Vector3.new(0, 0.1, 0.6))
		h(Vector3.new(0.3, 0.8, 0.9), Vector3.new(1.0, 0.1, 0))
		h(Vector3.new(0.3, 0.8, 0.9), Vector3.new(-1.0, 0.1, 0))
		h(Vector3.new(0.95, 1.1, 0.3), Vector3.new(-0.5, 0.05, -0.6))
		h(Vector3.new(2.0, 0.35, 0.5), Vector3.new(0, 0.62, -0.4))
	elseif style == "big" then -- Usopp: pelo rizado grande
		h(Vector3.new(3.0, 2.2, 2.6), Vector3.new(0, 0.7, 0.1), ball)
	elseif style == "trunks" then -- Trunks: lila hasta la nuca, flequillo lateral
		h(Vector3.new(2.25, 0.8, 1.25), Vector3.new(0, 0.74, 0), ball)
		h(Vector3.new(1.4, 0.6, 0.9), Vector3.new(0, 1.0, 0), ball)
		h(Vector3.new(0.4, 0.45, 0.2), Vector3.new(-0.4, 0.4, -0.6))
		h(Vector3.new(0.35, 0.45, 0.2), Vector3.new(0.3, 0.4, -0.6))
		h(Vector3.new(0.3, 1.2, 1.2), Vector3.new(-1.05, 0, 0.1))
		h(Vector3.new(0.3, 1.2, 1.2), Vector3.new(1.05, 0, 0.1))
		h(Vector3.new(2.2, 1.6, 0.4), Vector3.new(0, -0.2, 0.6))
		h(Vector3.new(1.8, 0.4, 0.35), Vector3.new(0, -1.0, 0.62))
	elseif style == "bulma" then -- Bulma: hasta los hombros, puntas hacia afuera
		h(Vector3.new(2.25, 0.8, 1.25), Vector3.new(0, 0.74, 0), ball)
		h(Vector3.new(1.4, 0.5, 0.9), Vector3.new(0, 0.95, 0), ball)
		h(Vector3.new(0.4, 1.8, 1.2), Vector3.new(-1.05, -0.45, 0.05))
		h(Vector3.new(0.4, 1.8, 1.2), Vector3.new(1.05, -0.45, 0.05))
		h(Vector3.new(2.2, 1.8, 0.45), Vector3.new(0, -0.4, 0.62))
		h(Vector3.new(0.5, 0.4, 0.5), Vector3.new(-1.15, -1.45, 0.15), ball)
		h(Vector3.new(0.5, 0.4, 0.5), Vector3.new(1.15, -1.45, 0.15), ball)
		h(Vector3.new(0.4, 0.45, 0.2), Vector3.new(-0.4, 0.4, -0.6))
		h(Vector3.new(0.35, 0.45, 0.2), Vector3.new(0.4, 0.4, -0.6))
	else -- round
		h(Vector3.new(2.15, 0.7, 1.15), Vector3.new(0, 0.74, 0), ball)
	end
end


---------------------------------------------------------------------
-- KIT MODULAR (diseño tipo "hoja de diseño de Brakkar"): piezas sueltas armadura/accesorios sobre el cuerpo R6.
-- Todas las claves son opcionales; los colores salen de MobLooks. Frente del personaje = -Z, espalda = +Z.
---------------------------------------------------------------------
local function applyKit(look: { [string]: any }, model: Model, torso: any, head: any, rArm: any, lArm: any, rLeg: any, lLeg: any, clean: boolean?)
	local Ball, Cyl = Enum.PartType.Ball, Enum.PartType.Cylinder
	local function a(name: string, size: Vector3, color: Color3, to: any, off: CFrame, shape: Enum.PartType?, mat: Enum.Material?): Part
		return accessory(name, size, color, to, off, model, shape, mat)
	end
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	local trim: Color3? = look.Trim
	local function trimOf(c: Color3): Color3
		return trim or darker(c, 0.7)
	end

	-- PECHO (peto con ribete)
	if look.Chest and not clean then -- (modo limpio R15: el torso ya va pintado, sin bloque encima)
		local c: Color3 = look.Chest
		a("Chest", v(2.08, 1.3, 1.08), c, torso, CFrame.new(0, 0.28, 0))
		a("ChestTrimLow", v(2.12, 0.1, 1.12), trimOf(c), torso, CFrame.new(0, -0.38, 0))
		a("ChestTrimTop", v(1.1, 0.1, 1.12), trimOf(c), torso, CFrame.new(0, 0.92, 0))
	end
	-- PLACA DEL VIENTRE (Nappa / Saiyans)
	if look.Belly then
		local c: Color3 = look.Belly
		a("BellyFrame", v(1.14, 1.14, 0.1), trimOf(c), torso, CFrame.new(0, -0.18, -0.54), Ball)
		a("BellyPlate", v(1.0, 1.0, 0.14), c, torso, CFrame.new(0, -0.18, -0.57), Ball)
		for _, y in ipairs({ -0.42, -0.18, 0.06 }) do
			a("BellyRidge", v(0.8, 0.06, 0.16), darker(c, 0.7), torso, CFrame.new(0, y, -0.62))
		end
	end
	-- CINTURÓN
	if look.Belt then
		local c: Color3 = look.Belt
		a("Belt", if clean then v(2.04, 0.3, 1.04) else v(2.14, 0.3, 1.14), c, torso, CFrame.new(0, -0.8, 0))
		a("Buckle", v(0.4, 0.3, 0.1), look.Buckle or Color3.fromRGB(210, 180, 80), torso, CFrame.new(0, -0.8, -0.6), nil, Enum.Material.Metal)
	end
	-- HOMBRERAS RECTANGULARES (estilo bloque de Roblox): placa superior + ribete + placa baja, apoyadas sobre el hombro
	if look.Shoulders then
		local c: Color3 = look.Shoulders
		for _, sx in ipairs({ -1, 1 }) do
			local tilt = CFrame.Angles(0, 0, math.rad(-sx * 10))
			a("Pauldron", v(1.5, 0.5, 1.4), c, torso, CFrame.new(sx * 1.35, 1.0, 0) * tilt)
			a("PauldronTrimTop", v(1.54, 0.09, 1.44), trimOf(c), torso, CFrame.new(sx * 1.35, 1.27, 0) * tilt)
			a("PauldronTrimEdge", v(0.1, 0.55, 1.44), trimOf(c), torso, CFrame.new(sx * 2.07, 0.88, 0) * tilt)
			a("PauldronLow", v(1.35, 0.35, 1.3), darker(c, 0.85), torso, CFrame.new(sx * 1.4, 0.62, 0) * tilt)
		end
	end
	-- MANGAS
	if look.Sleeves and not clean then -- (en modo limpio las mangas se pintan en el brazo)
		for _, arm in ipairs({ rArm, lArm }) do
			a("Sleeve", v(1.05, 1.1, 1.05), look.Sleeves, arm, CFrame.new(0, 0.42, 0))
		end
	end
	-- GUANTELETES (muñequeras con ribete)
	if look.Wrists then
		local c: Color3 = look.Wrists
		for _, arm in ipairs({ rArm, lArm }) do
			if clean then
				a("Gauntlet", v(1.06, 0.5, 1.06), c, arm, CFrame.new(0, -0.62, 0))
				a("GauntletTrim", v(1.1, 0.08, 1.1), look.WristTrim or trimOf(c), arm, CFrame.new(0, -0.35, 0))
			else
				a("Gauntlet", v(1.12, 0.75, 1.12), c, arm, CFrame.new(0, -0.55, 0))
				a("GauntletTrim", v(1.15, 0.12, 1.15), look.WristTrim or trimOf(c), arm, CFrame.new(0, -0.14, 0))
			end
		end
	end
	if look.Gloves and not clean then -- (modo limpio: la mano se pinta)
		for _, arm in ipairs({ rArm, lArm }) do
			a("Glove", v(1.08, 0.45, 1.08), look.Gloves, arm, CFrame.new(0, -0.8, 0))
		end
	end
	-- CANILLERAS / BOTAS
	if look.Greaves and not clean then -- (modo limpio: la espinilla se pinta)
		for _, leg in ipairs({ rLeg, lLeg }) do
			a("Greave", v(1.1, 0.6, 1.1), look.Greaves, leg, CFrame.new(0, 0.05, 0))
		end
	end
	for _, leg in ipairs({ rLeg, lLeg }) do
		if look.BootCuff then
			a("BootCuff", if clean then v(1.06, 0.14, 1.06) else v(1.14, 0.24, 1.14), look.BootCuff, leg, CFrame.new(0, -0.27, 0))
		end
		if look.BootToe and not clean then
			a("BootToe", v(1.1, 0.38, 0.5), look.BootToe, leg, CFrame.new(0, -0.8, -0.4))
		end
	end
	-- LARGOS: abrigo (Akatsuki), cuello alto, nubes
	if look.Coat then
		local c: Color3 = look.Coat
		a("CoatBody", v(2.14, 2.06, 1.14), c, torso, CFrame.new(0, 0, 0))
		a("CoatSkirt", v(2.2, 1.5, 1.22), c, torso, CFrame.new(0, -1.55, 0.02))
		a("CoatHem", v(2.24, 0.12, 1.26), trimOf(c), torso, CFrame.new(0, -2.3, 0.02))
		a("CoatFront", v(0.12, 3.4, 0.06), trimOf(c), torso, CFrame.new(0, -0.75, -0.62))
		for _, arm in ipairs({ rArm, lArm }) do
			a("CoatSleeve", v(1.14, 1.45, 1.14), c, arm, CFrame.new(0, 0.28, 0))
		end
	end
	if look.Collar then
		if clean then
			-- modo limpio R15: sin cuello (el torso ya va pintado; las piezas sobre el cuello chocaban con la cara)
		else
			a("Collar", v(2.2, 0.55, 1.3), look.Collar, torso, CFrame.new(0, 1.05, 0.06))
			a("CollarBack", v(2.2, 0.9, 0.2), look.Collar, torso, CFrame.new(0, 1.2, 0.6))
		end
	end
	if look.Marks then -- nubes rojas con borde blanco
		local spots = { Vector3.new(-0.55, 0.45, -0.6), Vector3.new(0.5, -0.05, -0.6), Vector3.new(-0.45, -1.4, -0.66), Vector3.new(0.5, -1.9, -0.66) }
		for _, p in ipairs(spots) do
			a("CloudEdge", v(0.72, 0.5, 0.05), Color3.fromRGB(240, 240, 245), torso, CFrame.new(p))
			a("Cloud", v(0.6, 0.38, 0.07), look.Marks, torso, CFrame.new(p + v(0, 0, -0.02)), Ball)
		end
	end
	if look.Stripes then
		for _, y in ipairs({ 0.55, 0.05, -0.45 }) do
			a("Stripe", v(2.03, 0.2, 1.03), look.Stripes, torso, CFrame.new(0, y, 0))
		end
	end
	if look.Emblem then
		a("EmblemBase", v(0.55, 0.55, 0.05), Color3.fromRGB(235, 235, 235), torso, CFrame.new(0.5, 0.5, -0.54))
		a("Emblem", v(0.42, 0.42, 0.07), look.Emblem, torso, CFrame.new(0.5, 0.5, -0.56))
	end
	if look.Bandolier then
		a("Bandolier", v(0.28, 2.7, 0.14), look.Bandolier, torso, CFrame.new(0, 0, -0.57) * CFrame.Angles(0, 0, math.rad(38)))
		a("BandolierBack", v(0.28, 2.7, 0.14), look.Bandolier, torso, CFrame.new(0, 0, 0.57) * CFrame.Angles(0, 0, math.rad(38)))
		for i = -2, 2 do
			a("Cartridge", v(0.2, 0.28, 0.12), Color3.fromRGB(200, 170, 70), torso, CFrame.new(i * 0.32, i * 0.32 * -0.78 * -1, -0.66) * CFrame.Angles(0, 0, math.rad(38)))
		end
	end
	if look.Scarf then
		a("Scarf", if clean then v(1.45, 0.3, 0.95) else v(2.1, 0.4, 1.2), look.Scarf, torso, CFrame.new(0, if clean then 0.97 else 0.95, 0))
		a("ScarfTail", v(0.5, 1.6, 0.14), look.Scarf, torso, CFrame.new(0.6, 0.2, 0.62))
	end
	if look.Pouch then
		a("Pouch", v(0.7, 0.7, 0.5), look.Pouch, rLeg, CFrame.new(0.58, 0.25, 0))
	end
	if look.Sheath then
		for i, sx in ipairs({ -1, 1 }) do
			a("Scabbard", v(0.22, 0.22, 2.4), look.Sheath, torso, CFrame.new(sx * 1.2, -0.75 - i * 0.05, 0.2) * CFrame.Angles(math.rad(-25), 0, 0))
			a("ScabbardHilt", v(0.3, 0.3, 0.5), Color3.fromRGB(230, 230, 235), torso, CFrame.new(sx * 1.2, -0.75 - i * 0.05 - 0.4, -0.95) * CFrame.Angles(math.rad(-25), 0, 0))
		end
	end
	if look.BackSword then
		a("BackBlade", v(0.2, 3.4, 0.4), look.BackSword, torso, CFrame.new(0.3, 0.7, 0.75) * CFrame.Angles(0, 0, math.rad(35)), nil, Enum.Material.Metal)
		a("BackHilt", v(0.3, 0.7, 0.3), Color3.fromRGB(60, 40, 30), torso, CFrame.new(-0.55, -0.85, 0.75) * CFrame.Angles(0, 0, math.rad(35)))
	end
	if look.Backpack then
		a("Backpack", v(2.4, 1.0, 0.9), look.Backpack, torso, CFrame.new(0, 0.3, 0.95) * CFrame.Angles(0, 0, math.rad(90)), Cyl)
	end
	if look.Wings then
		for _, sx in ipairs({ -1, 1 }) do
			a("Wing", v(0.1, 2.4, 1.5), look.Wings, torso, CFrame.new(sx * 0.9, 0.5, 0.85) * CFrame.Angles(math.rad(10), 0, math.rad(sx * 28)))
		end
	end
	if look.Spots then
		for _, p in ipairs({ v(-0.5, 0.5, -0.55), v(0.55, 0.1, -0.55), v(-0.35, -0.5, -0.55), v(0.4, 0.8, -0.55) }) do
			a("Spot", v(0.3, 0.3, 0.06), look.Spots, torso, CFrame.new(p), Ball)
		end
		for _, arm in ipairs({ rArm, lArm }) do
			a("Spot", v(0.3, 0.3, 0.3), look.Spots, arm, CFrame.new(0.4, 0.2, -0.3), Ball)
		end
	end
	if look.Bones then -- espinas de hueso
		for i = -2, 2 do
			a("Bone", v(0.2, 1.6, 0.2), look.Bones, torso, CFrame.new(i * 0.4, 0.9, 0.75) * CFrame.Angles(math.rad(25), 0, math.rad(i * 12)))
		end
		for _, arm in ipairs({ rArm, lArm }) do
			a("Bone", v(1.5, 0.2, 0.2), look.Bones, arm, CFrame.new(0, -0.3, -0.7) * CFrame.Angles(0, math.rad(90), 0), Cyl)
		end
	end
	if look.Fins then
		a("FinHead", v(0.1, 0.9, 1.0), look.Fins, head, CFrame.new(0, 0.75, 0.25) * CFrame.Angles(math.rad(-20), 0, 0))
		a("FinBack", v(0.1, 1.5, 1.1), look.Fins, torso, CFrame.new(0, 0.3, 0.75) * CFrame.Angles(math.rad(-10), 0, 0))
		for _, arm in ipairs({ rArm, lArm }) do
			a("FinArm", v(0.08, 0.8, 0.8), look.Fins, arm, CFrame.new(0, -0.2, 0.55))
		end
	end
	if look.Tentacles then
		for _, sx in ipairs({ -1, 1 }) do
			for i = 1, 4 do
				local sz = 0.9 - i * 0.12
				a("Tentacle", v(sz, sz, 1.0), look.Tentacles, torso, CFrame.new(sx * (0.5 + i * 0.45), 0.2 - i * 0.2, 0.8 + i * 0.85) * CFrame.Angles(math.rad(10), math.rad(sx * 15), 0), Ball)
			end
		end
	end
	if look.Pet then
		a("Bird", v(0.8, 0.8, 0.9), look.Pet, torso, CFrame.new(-1.1, 1.65, 0.1), Ball)
		a("BirdHead", v(0.5, 0.5, 0.5), look.Pet, torso, CFrame.new(-1.1, 2.15, -0.25), Ball)
		a("BirdBeak", v(0.15, 0.12, 0.3), Color3.fromRGB(240, 150, 40), torso, CFrame.new(-1.1, 2.12, -0.58))
	end

	-- CABEZA
	if look.Helmet then
		a("Helmet", v(2.35, 1.5, 1.6), look.Helmet, head, CFrame.new(0, 0.42, 0.06), Ball)
		a("HelmetRim", v(2.2, 0.16, 1.3), darker(look.Helmet, 0.7), head, CFrame.new(0, 0.28, 0))
	end
	if look.Dome then
		a("Dome", v(1.7, 1.1, 1.5), look.Dome, head, CFrame.new(0, 0.62, 0.1), Ball)
	end
	if look.Gem then
		a("Gem", v(0.4, 0.4, 0.2), look.Gem, head, CFrame.new(0, 0.55, -0.55), Ball, Enum.Material.Neon)
	end
	if look.Hood then
		a("Hood", v(2.5, 1.9, 2.0), look.Hood, head, CFrame.new(0, 0.2, 0.3), Ball)
		a("HoodBack", v(2.3, 1.7, 0.9), look.Hood, torso, CFrame.new(0, 1.1, 0.7), Ball)
	end
	if look.Ears then
		for _, sx in ipairs({ -1, 1 }) do
			a("Ear", v(0.55, 0.85, 0.35), look.Ears, head, CFrame.new(sx * 0.75, 0.85, 0.05) * CFrame.Angles(0, 0, math.rad(-sx * 12)), Ball)
		end
	end
	if look.Antenna then
		local c: Color3 = look.Antenna
		a("Antenna", v(0.55, 0.55, 0.55), c, head, CFrame.new(0, 0.85, 0.3), Ball)
		a("Antenna", v(0.45, 0.45, 0.45), c, head, CFrame.new(0, 1.3, 0.7), Ball)
		a("Antenna", v(0.4, 0.4, 0.4), c, head, CFrame.new(0, 1.35, 1.2), Ball)
		a("AntennaTip", v(0.5, 0.5, 0.5), c, head, CFrame.new(0, 1.0, 1.6), Ball)
	end
	if look.Braid then
		for i = 0, 5 do
			a("Braid", v(0.5, 0.5, 0.5), look.Braid, head, CFrame.new(0, -0.1 - i * 0.55, 0.62 + i * 0.05), Ball)
		end
	end
	if look.Piercings then
		for _, p in ipairs({ v(-0.15, 0.1, -0.64), v(0.15, 0.1, -0.64), v(-0.95, 0.1, 0), v(0.95, 0.1, 0), v(-0.95, -0.15, 0), v(0.95, -0.15, 0), v(-0.28, -0.12, -0.64), v(0.28, -0.12, -0.64) }) do
			a("Piercing", v(0.12, 0.12, 0.12), look.Piercings, head, CFrame.new(p), Ball, Enum.Material.Metal)
		end
	end
	if look.Mustache then
		a("Mustache", v(0.8, 0.14, 0.1), look.Mustache, head, CFrame.new(0, -0.14, -0.66))
		for _, sx in ipairs({ -1, 1 }) do
			a("MustacheEnd", v(0.2, 0.2, 0.1), look.Mustache, head, CFrame.new(sx * 0.42, -0.22, -0.66), Ball)
		end
	end
	if look.Beard then
		a("Beard", v(1.35, 0.7, 0.4), look.Beard, head, CFrame.new(0, -0.5, -0.5), Ball)
		a("BeardWide", v(1.9, 0.6, 0.9), look.Beard, head, CFrame.new(0, -0.35, -0.1), Ball)
	end
	if look.Brow then
		for _, sx in ipairs({ -1, 1 }) do
			a("Brow", v(0.28, 0.055, 0.06), look.Brow, head, CFrame.new(sx * 0.27, 0.235, -0.625) * CFrame.Angles(0, 0, math.rad(sx * 10)))
		end
	end
	if look.Scar then
		local sx: number = look.ScarX or 0.3
		a("Scar", v(0.07, 0.65, 0.06), look.Scar, head, CFrame.new(sx, 0.05, -0.65) * CFrame.Angles(0, 0, math.rad(if sx > 0 then -18 else 18)))
	end
	if look.Nose then
		a("Nose", v(0.6, 0.6, 0.6), look.Nose, head, CFrame.new(0, -0.02, -0.82), Ball)
	end
	if look.Saw then
		a("SawNose", v(0.3, 0.22, 1.7), look.Saw, head, CFrame.new(0, -0.05, -1.4), nil, Enum.Material.Metal)
		for i = 0, 3 do
			a("SawTooth", v(0.5, 0.14, 0.22), look.Saw, head, CFrame.new(0, -0.2, -0.85 - i * 0.4), nil, Enum.Material.Metal)
		end
	end
	if look.MaskMarks and look.Mask then
		for _, sx in ipairs({ -1, 1 }) do
			a("MaskMark", v(0.1, 0.5, 0.05), look.MaskMarks, head, CFrame.new(sx * 0.3, -0.05, -0.7))
		end
	end
	if look.Crown then
		a("Crown", v(1.9, 0.3, 1.0), look.Crown, head, CFrame.new(0, 0.7, 0), nil, Enum.Material.Metal)
	end
end

local function whole(p: BasePart): Logical
	return { Part = p, Resolve = function(off: CFrame) return p, off end }
end

-- Cuerpo R6 (respaldo si el cuerpo R15 aún no está listo o falla)
local function buildR6(look: { [string]: any }, displayName: string): (Model, BasePart, any, any, any, any, any, any)
	local model = Instance.new("Model")
	model.Name = displayName

	local skin: Color3 = look.Skin
	local arm: Color3 = look.Arm or skin

	local hrp = part("HumanoidRootPart", Vector3.new(2, 2, 1), skin, model)
	hrp.Transparency = 1
	hrp.CanCollide = false
	local torso = part("Torso", Vector3.new(2, 2, 1), look.Torso, model)
	local head = part("Head", Vector3.new(2, 1, 1), skin, model)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local rArm = part("Right Arm", Vector3.new(1, 2, 1), arm, model)
	local lArm = part("Left Arm", Vector3.new(1, 2, 1), arm, model)
	local rLeg = part("Right Leg", Vector3.new(1, 2, 1), look.Legs, model)
	local lLeg = part("Left Leg", Vector3.new(1, 2, 1), look.Legs, model)
	rLeg.CanCollide = false
	lLeg.CanCollide = false
	hrp.CanCollide = true

	local rootRot = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
	motor("RootJoint", hrp, torso, rootRot, rootRot, hrp)
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.5, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), torso)
	motor("Right Shoulder", torso, rArm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), torso)
	motor("Left Shoulder", torso, lArm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), torso)
	motor("Right Hip", torso, rLeg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), torso)
	motor("Left Hip", torso, lLeg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), torso)


	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.HipHeight = 0
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 70
	hum.HealthDisplayDistance = 70
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	hum.Parent = model
	model.PrimaryPart = hrp
	return model, hrp, whole(torso), whole(head), whole(rArm), whole(lArm), whole(rLeg), whole(lLeg)
end

---------------------------------------------------------------------
-- CUERPO R15 (el mismo de los jugadores: miembros redondeados, manos, codos y rodillas)
-- Se crea UNA vez con Players:CreateHumanoidModelFromDescription y se clona para cada enemigo.
---------------------------------------------------------------------
-- Interruptor: false = vuelve a los cuerpos R6 de bloques (como antes)
local USE_R15 = true
local R15Template: Model? = nil
task.spawn(function()
	if not USE_R15 then
		return
	end
	local ok, res = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not res then
		warn("[MobBuilder] No se pudo crear el cuerpo R15 (" .. tostring(res) .. "): se usa R6.")
		return
	end
	local m = res :: Model
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("Accessory") or d:IsA("HumanoidDescription") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if not m:FindFirstChild("HumanoidRootPart") or not m:FindFirstChild("UpperTorso") then
		warn("[MobBuilder] El cuerpo R15 generado no tiene las piezas esperadas: se usa R6.")
		return
	end
	R15Template = m
	print("[MobBuilder] Cuerpo R15 listo.")
end)

function MobBuilder.UsesR15(): boolean
	return R15Template ~= nil
end


-- Ajuste del torso R15 al ancho/fondo reales + recorte del cuello/collar para que no tape la cara
local function makeTorsoFit(kx: number, kz: number): (Vector3, CFrame) -> (Vector3, CFrame)
	return function(size: Vector3, off: CFrame)
		local p = off.Position
		local sy, py = size.Y, p.Y
		-- el cuello y la cabeza R15 empiezan justo sobre el torso: lo que sobresale por arriba en el centro (cuello alto, collar)
		-- se recorta. Solo piezas sin rotación y en el centro (hombreras, alas y capa no).
		local rx, ry, rz = off:ToEulerAnglesXYZ()
		if math.abs(rx) + math.abs(ry) + math.abs(rz) < 0.01 and math.abs(p.X) < 1.0 and sy > 0.15 then
			local maxTop = 1.08
			local top = py + sy / 2
			if top > maxTop then
				local bottom = py - sy / 2
				if bottom > maxTop - 0.1 then
					sy, py = 0.1, maxTop - 0.05
				else
					sy = maxTop - bottom
					py = bottom + sy / 2
				end
			end
		end
		return Vector3.new(size.X * kx, sy, size.Z * kz), CFrame.new(p.X * kx, py, p.Z * kz) * off.Rotation
	end
end

-- Extremidad R15 como pieza "lógica" R6 (2 de largo, centrada, hombro/cadera arriba = +1, mano/pie abajo = -1).
-- Las piezas R15 SE SOLAPAN en codos y rodillas, así que no se suman tamaños: se usan las posiciones reales de las piezas.
-- Lo que está en la mitad baja (botas, muñequeras, guantes) se ancla al extremo inferior real; lo de la mitad alta, al hombro/cadera.
local function r15Limb(model: Model, names: { string }): Logical
	local parts: { BasePart } = {}
	for _, n in ipairs(names) do
		table.insert(parts, model:FindFirstChild(n) :: BasePart)
	end
	local top = parts[1].Position.Y + parts[1].Size.Y / 2
	local bottom = math.huge
	for _, p in ipairs(parts) do
		bottom = math.min(bottom, p.Position.Y - p.Size.Y / 2)
	end
	local widthK = math.clamp(math.max(parts[1].Size.X, parts[1].Size.Z), 0.6, 1.6) -- R6: 1 stud de ancho
	return {
		Part = parts[1],
		Fit = function(size: Vector3, off: CFrame)
			local p = off.Position
			return Vector3.new(size.X * widthK, size.Y, size.Z * widthK), CFrame.new(p.X * widthK, p.Y, p.Z * widthK) * off.Rotation
		end,
		Resolve = function(off: CFrame)
			local y = off.Position.Y
			local yReal = if y >= 0 then top - (1 - y) else bottom + (y + 1)
			-- pieza cuyo tramo contiene esa altura (si hay varias, la de centro más cercano)
			local pick = parts[#parts]
			local bestD = math.huge
			for _, p in ipairs(parts) do
				local half = p.Size.Y / 2
				local d = math.abs(yReal - p.Position.Y)
				local inside = d <= half
				local score = if inside then d else d + 100
				if score < bestD then
					bestD = score
					pick = p
				end
			end
			return pick, CFrame.new(0, (yReal - pick.Position.Y) - y, 0) * off
		end,
	}
end

-- CUERPOS PERSONALIZADOS: look.Base = "MagmaFiend" / "JunkBot" / ... usa el modelo de ServerStorage > MobBodies (cuerpo R15 con mallas propias).
-- Se limpia (sin accesorios, scripts ni colores de avatar) y conserva sus mallas. Si no existe, el mob usa el cuerpo normal.
local function bodyFor(look: { [string]: any }): Model?
	local name = look.Base
	if typeof(name) ~= "string" then
		return nil
	end
	local folder = game:GetService("ServerStorage"):FindFirstChild("MobBodies")
	local src = folder and folder:FindFirstChild(name)
	if not (src and src:IsA("Model") and src:FindFirstChild("HumanoidRootPart") and src:FindFirstChild("UpperTorso") and src:FindFirstChildOfClass("Humanoid")) then
		warn("[MobBuilder] Cuerpo '" .. name .. "' no encontrado en ServerStorage.MobBodies (o incompleto): se usa el cuerpo normal")
		return nil
	end
	local m = src:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Accessory") or d:IsA("Script") or d:IsA("LocalScript") or d:IsA("HumanoidDescription") or d:IsA("BodyColors") then
			d:Destroy()
		end
	end
	m:SetAttribute("CustomBody", true)
	return m
end

local function buildR15(look: { [string]: any }, displayName: string, custom: Model?): (Model, BasePart, any, any, any, any, any, any)
	local model = (custom or (R15Template :: Model)):Clone()
	model.Name = displayName
	local skin: Color3 = look.Skin
	local armC: Color3 = look.Arm or skin
	local legC: Color3 = look.Legs
	local function paint(name: string, c: Color3)
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = c
			p.Material = Enum.Material.SmoothPlastic
		end
	end
	if not custom then
		paint("Head", skin)
		paint("UpperTorso", look.Torso)
		paint("LowerTorso", legC)
		for _, side in ipairs({ "Right", "Left" }) do
			paint(side .. "UpperArm", armC)
			paint(side .. "LowerArm", armC)
			paint(side .. "Hand", armC)
			paint(side .. "UpperLeg", legC)
			paint(side .. "LowerLeg", legC)
			paint(side .. "Foot", look.Boots)
		end
	elseif typeof(look.BodyColor) == "Color3" then -- tinte opcional sobre las mallas del cuerpo
		for _, d in ipairs(model:GetChildren()) do
			if d:IsA("MeshPart") then
				d.Color = look.BodyColor
			end
		end
	end
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local ut = model:FindFirstChild("UpperTorso") :: BasePart
	local lt = model:FindFirstChild("LowerTorso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart

	-- torso lógico R6 (2 de alto, centrado) = tramo LowerTorso + UpperTorso
	local bottom = lt.Position.Y - lt.Size.Y / 2
	local top = ut.Position.Y + ut.Size.Y / 2
	local midOff = (bottom + top) / 2 - ut.Position.Y
	local kx, kz = math.clamp(ut.Size.X / 2, 0.6, 1.6), math.clamp(ut.Size.Z / 1, 0.6, 1.6)
	local torsoL: Logical = {
		Part = ut,
		Fit = makeTorsoFit(kx, kz),
		Resolve = function(off: CFrame)
			return ut, CFrame.new(0, -midOff, 0) * off
		end,
	}
	local headL = whole(head)

	local function limb(names: { string }): Logical
		return r15Limb(model, names)
	end
	local rArm = limb({ "RightUpperArm", "RightLowerArm", "RightHand" })
	local lArm = limb({ "LeftUpperArm", "LeftLowerArm", "LeftHand" })
	local rLeg = limb({ "RightUpperLeg", "RightLowerLeg", "RightFoot" })
	local lLeg = limb({ "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" })

	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	hum.NameDisplayDistance = 70
	hum.HealthDisplayDistance = 70
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	model.PrimaryPart = hrp
	return model, hrp, torsoL, headL, rArm, lArm, rLeg, lLeg
end

function MobBuilder.Build(look: { [string]: any }, displayName: string): Model
	local model, hrp, torso, head, rArm, lArm, rLeg, lLeg
	local customBody = bodyFor(look)
	if customBody or R15Template then
		model, hrp, torso, head, rArm, lArm, rLeg, lLeg = buildR15(look, displayName, customBody)
	else
		model, hrp, torso, head, rArm, lArm, rLeg, lLeg = buildR6(look, displayName)
	end
	local skin: Color3 = look.Skin

	local custom = customBody ~= nil -- cuerpo con mallas propias: ya trae botas, cara y pelo
	-- botas (en la parte baja de las piernas)
	for _, leg in ipairs(if custom then {} else { rLeg, lLeg }) do
		accessory("Boot", Vector3.new(1.08, 0.7, 1.08), look.Boots, leg, CFrame.new(0, -0.65, 0), model)
	end

	-- cara: ojos
	local eyeColor: Color3 = look.Eye or Color3.fromRGB(20, 20, 24)
	for _, sx in ipairs(if custom then {} else { -0.32, 0.32 }) do
		accessory("Eye", Vector3.new(0.22, 0.18, 0.08), eyeColor, head, CFrame.new(sx, 0.08, -0.62), model, Enum.PartType.Ball)
	end
	if not custom then
		accessory("Mouth", Vector3.new(0.5, 0.08, 0.06), darker(skin, 0.55), head, CFrame.new(0, -0.28, -0.63), model)
	end

	-- pelo
	if look.Hair and not custom then
		addHair(look.HairStyle or "round", look.Hair, head, model)
	end
	-- armadura (peto sobre el torso)
	if look.Armor then
		accessory("Armor", Vector3.new(2.12, 1.5, 1.12), look.Armor, torso, CFrame.new(0, 0.2, 0), model)
		for _, sx in ipairs({ -1.05, 1.05 }) do
			accessory("Pauldron", Vector3.new(0.7, 0.45, 1.2), look.Armor, torso, CFrame.new(sx, 1.0, 0), model, Enum.PartType.Ball)
		end
	end
	-- capa
	if look.Cape then
		accessory("Cape", Vector3.new(2.1, 2.8, 0.15), look.Cape, torso, CFrame.new(0, -0.3, 0.62) * CFrame.Angles(math.rad(8), 0, 0), model)
	end
	-- cola (3 segmentos curvados)
	if look.Tail then
		local c: Color3 = look.Tail
		accessory("Tail", Vector3.new(0.4, 0.4, 1.0), c, torso, CFrame.new(0, -0.9, 0.9) * CFrame.Angles(math.rad(-20), 0, 0), model)
		accessory("Tail", Vector3.new(0.35, 0.35, 1.0), c, torso, CFrame.new(0, -0.55, 1.75) * CFrame.Angles(math.rad(-35), 0, 0), model)
		accessory("Tail", Vector3.new(0.3, 0.3, 0.9), c, torso, CFrame.new(0, 0.0, 2.45) * CFrame.Angles(math.rad(-50), 0, 0), model)
	end
	-- cuernos / aletas (redondeados)
	if look.Horns then
		for _, sx in ipairs({ -0.6, 0.6 }) do
			accessory("Horn", Vector3.new(0.35, 0.9, 0.35), look.Horns, head, CFrame.new(sx, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-sx * 25)), model, Enum.PartType.Cylinder)
		end
	end
	if look.Headband then
		accessory("Headband", Vector3.new(2.1, 0.3, 1.1), look.Headband, head, CFrame.new(0, 0.35, 0), model)
		accessory("Plate", Vector3.new(0.7, 0.3, 0.1), Color3.fromRGB(190, 195, 205), head, CFrame.new(0, 0.35, -0.57), model, nil, Enum.Material.Metal)
	end
	if look.Mask then
		accessory("Mask", Vector3.new(1.2, 0.8, 0.15), look.Mask, head, CFrame.new(0, -0.05, -0.62), model)
	end
	if look.Hat then
		accessory("HatBrim", Vector3.new(2.5, 0.12, 2.5), look.Hat, head, CFrame.new(0, 0.7, 0), model, Enum.PartType.Cylinder)
		accessory("HatTop", Vector3.new(1.3, 1.0, 1.3), look.Hat, head, CFrame.new(0, 1.2, 0), model, Enum.PartType.Cylinder)
	end
	if look.Patch then
		accessory("Patch", Vector3.new(0.45, 0.4, 0.08), look.Patch, head, CFrame.new(0.32, 0.1, -0.64), model)
	end
	if look.Scouter then
		-- Scouter_Attch (pieza en la oreja) + brazo + Scouter_Lens (lente translúcido)
		accessory("ScouterEar", Vector3.new(0.35, 0.6, 0.45), Color3.fromRGB(190, 195, 205), head, CFrame.new(-0.98, 0.1, 0), model, nil, Enum.Material.Metal)
		accessory("ScouterArm", Vector3.new(0.12, 0.12, 0.8), Color3.fromRGB(170, 175, 185), head, CFrame.new(-0.85, 0.25, -0.35), model)
		accessory("ScouterLens", Vector3.new(0.6, 0.5, 0.18), look.Scouter, head, CFrame.new(-0.32, 0.14, -0.72), model, nil, Enum.Material.Neon).Transparency = 0.35
		accessory("ScouterFrame", Vector3.new(0.7, 0.1, 0.2), Color3.fromRGB(180, 185, 195), head, CFrame.new(-0.32, 0.42, -0.72), model, nil, Enum.Material.Metal)
	end
	applyKit(look, model, torso, head, rArm, lArm, rLeg, lLeg)
	-- arma agarrada: mango dentro de la mano derecha, hoja hacia adelante
	if look.Weapon then
		local c: Color3 = look.Weapon
		local grip = Vector3.new(0, -1.0, 0) -- palma de la mano derecha
		accessory("WeaponHandle", Vector3.new(0.25, 0.9, 0.25), Color3.fromRGB(60, 40, 30), rArm, CFrame.new(grip) * CFrame.Angles(math.rad(-90), 0, 0), model)
		accessory("WeaponBlade", Vector3.new(0.18, 3.6, 0.5), c, rArm, CFrame.new(grip + Vector3.new(0, 0, -2.4)) * CFrame.Angles(math.rad(-90), 0, 0), model, nil, Enum.Material.Metal)
	end
	-- aura
	if look.Aura then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(look.Aura)
		pe.Rate = 12
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(2, 4)
		pe.SpreadAngle = Vector2.new(25, 25)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 0.8
		pe.Parent = torso.Part
		local light = Instance.new("PointLight")
		light.Color = look.Aura
		light.Range = 10
		light.Brightness = 0.8
		light.Parent = torso.Part
	end

	local scale = look.Scale
	if typeof(scale) == "number" and scale ~= 1 then
		model:ScaleTo(scale)
	end
	return model
end

-- Balanceo simple de extremidades. `amount` 0 = quieto, 1 = corriendo.
function MobBuilder.Animate(model: Model, amount: number, t: number)
	local torso = model:FindFirstChild("Torso")
	if not torso then
		return
	end
	local swing = math.sin(t * 9) * 0.9 * amount
	local function set(jointName: string, angle: number)
		local j = torso:FindFirstChild(jointName)
		if j and j:IsA("Motor6D") then
			j.Transform = CFrame.Angles(0, 0, angle)
		end
	end
	set("Right Shoulder", swing)
	set("Left Shoulder", swing)
	set("Right Hip", -swing)
	set("Left Hip", -swing)
end

---------------------------------------------------------------------
-- TRAJES DE JUGADOR: pone el kit sobre el avatar de un jugador (R6 o R15). No crea cuerpo: usa el del avatar.
--   Dress(look, character): pinta piel/ropa del cuerpo, quita ropa y accesorios del avatar, y pega las piezas del kit
--   dentro de un Model "Outfit" (se pueden quitar con Undress). Las piezas van soldadas a brazos/piernas, así que se animan.
---------------------------------------------------------------------
local function logicalsOf(char: Model, isR15: boolean): (any, any, any, any, any, any)
	if not isR15 then
		local function w(n: string): Logical
			return whole(char:FindFirstChild(n) :: BasePart)
		end
		-- Cabeza R6: la pieza mide 2x1x1 pero lo que se ve (malla) es una cabeza de ~1.25 de lado. Pelo/casco/capucha se diseñaron
		-- para cabeza ancha: las piezas anchas se encogen a ~62 % de ancho y las de los lados se acercan; la cara no se toca.
		local headR6 = w("Head")
		headR6.Fit = function(size: Vector3, off: CFrame)
			local p = off.Position
			local wide = size.X > 1.3
			local px = if math.abs(p.X) > 0.45 then p.X * 0.62 else p.X
			return Vector3.new(if wide then size.X * 0.62 else size.X, size.Y, if wide and size.Z > 1.0 then size.Z * 1.08 else size.Z), CFrame.new(px, p.Y, p.Z) * off.Rotation
		end
		return w("Torso"), headR6, w("Right Arm"), w("Left Arm"), w("Right Leg"), w("Left Leg")
	end
	local ut = char:FindFirstChild("UpperTorso") :: BasePart
	local lt = char:FindFirstChild("LowerTorso") :: BasePart
	local bottom = lt.Position.Y - lt.Size.Y / 2
	local top = ut.Position.Y + ut.Size.Y / 2
	local midOff = (bottom + top) / 2 - ut.Position.Y
	local kx, kz = math.clamp(ut.Size.X / 2, 0.6, 1.6), math.clamp(ut.Size.Z / 1, 0.6, 1.6)
	local torsoL: Logical = {
		Part = ut,
		Fit = makeTorsoFit(kx, kz),
		Resolve = function(off: CFrame)
			return ut, CFrame.new(0, -midOff, 0) * off
		end,
	}
	local function limb(names: { string }): Logical
		return r15Limb(char, names)
	end
	-- Cabeza R15 ~1.2 de lado (la de R6 se ve de 1.25). Las piezas de pelo/casco/capucha se diseñaron para una cabeza "de 2 de ancho":
	-- las piezas anchas se encogen y las de los lados se acercan; lo que va sobre la cara (ojos, cejas, cicatriz) no se toca.
	local headPart = char:FindFirstChild("Head") :: BasePart
	local headL = whole(headPart)
	local hk = math.clamp(headPart.Size.X / 1.25, 0.5, 1.4)
	local wideK = 0.62 * hk
	headL.Fit = function(size: Vector3, off: CFrame)
		local p = off.Position
		local sx = if size.X > 1.3 then size.X * wideK else size.X
		local sz = if size.Z > 1.0 and size.X > 1.3 then size.Z * 1.05 else size.Z
		local px = if math.abs(p.X) > 0.45 then p.X * wideK else p.X
		return Vector3.new(sx, size.Y, sz), CFrame.new(px, p.Y, p.Z) * off.Rotation
	end
	return torsoL, headL,
		limb({ "RightUpperArm", "RightLowerArm", "RightHand" }), limb({ "LeftUpperArm", "LeftLowerArm", "LeftHand" }),
		limb({ "RightUpperLeg", "RightLowerLeg", "RightFoot" }), limb({ "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" })
end

function MobBuilder.Undress(char: Model)
	local old = char:FindFirstChild("Outfit")
	if old then
		old:Destroy()
	end
end

function MobBuilder.Dress(look: { [string]: any }, char: Model): boolean
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return false
	end
	local isR15 = hum.RigType == Enum.HumanoidRigType.R15
	if not (char:FindFirstChild(if isR15 then "UpperTorso" else "Torso") and char:FindFirstChild("Head")) then
		return false
	end
	MobBuilder.Undress(char)
	do -- medidas reales del avatar (para calibrar trajes): se imprime una vez por personaje
		local parts: { string } = {}
		for _, n in ipairs(if isR15 then { "Head", "UpperTorso", "LowerTorso", "RightUpperArm", "RightLowerArm", "RightHand", "RightUpperLeg", "RightLowerLeg", "RightFoot" } else { "Head", "Torso", "Right Arm", "Right Leg" }) do
			local bp = char:FindFirstChild(n)
			if bp and bp:IsA("BasePart") then
				table.insert(parts, string.format("%s %.2fx%.2fx%.2f", n, bp.Size.X, bp.Size.Y, bp.Size.Z))
			end
		end
		print("[Outfit] " .. (if isR15 then "R15" else "R6") .. " " .. table.concat(parts, " | "))
	end

	-- 1) ropa y accesorios del avatar fuera; cuerpo pintado con los colores del personaje
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("CharacterMesh") then
			d:Destroy()
		end
	end
	local skin: Color3 = look.Skin
	local armC: Color3 = look.Arm or skin
	local legC: Color3 = look.Legs
	local bc = char:FindFirstChildOfClass("BodyColors")
	if not bc then
		bc = Instance.new("BodyColors")
		bc.Parent = char
	end
	local bodyColors = bc :: BodyColors
	bodyColors.HeadColor3 = skin
	bodyColors.TorsoColor3 = look.Torso
	bodyColors.LeftArmColor3 = armC
	bodyColors.RightArmColor3 = armC
	bodyColors.LeftLegColor3 = legC
	bodyColors.RightLegColor3 = legC
	local function paint(name: string, c: Color3)
		local p = char:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = c
		end
	end
	paint("Head", skin)
	if isR15 then
		paint("UpperTorso", look.Torso)
		paint("LowerTorso", legC)
		for _, side in ipairs({ "Right", "Left" }) do
			paint(side .. "UpperArm", armC)
			paint(side .. "LowerArm", armC)
			paint(side .. "Hand", armC)
			paint(side .. "UpperLeg", legC)
			paint(side .. "LowerLeg", legC)
			paint(side .. "Foot", look.Boots)
			-- MODO LIMPIO R15: mangas, guantes y canilleras se pintan en la pieza redondeada del cuerpo (en vez de bloques encima)
			if typeof(look.Sleeves) == "Color3" then
				paint(side .. "UpperArm", look.Sleeves)
			end
			if typeof(look.Gloves) == "Color3" then
				paint(side .. "Hand", look.Gloves)
			end
			if typeof(look.Greaves) == "Color3" then
				paint(side .. "LowerLeg", look.Greaves)
			end
		end
	else
		paint("Torso", look.Torso)
		paint("Right Arm", armC)
		paint("Left Arm", armC)
		paint("Right Leg", legC)
		paint("Left Leg", legC)
	end

	-- 2) piezas
	local outfit = Instance.new("Model")
	outfit.Name = "Outfit"
	outfit.Parent = char
	local torso, head, rArm, lArm, rLeg, lLeg = logicalsOf(char, isR15)
	local function a(name: string, size: Vector3, color: Color3, to: any, off: CFrame, shape: Enum.PartType?, mat: Enum.Material?): Part
		return accessory(name, size, color, to, off, outfit, shape, mat)
	end
	local function v(x: number, y: number, z: number): Vector3
		return Vector3.new(x, y, z)
	end
	local rotZ = CFrame.Angles(0, 0, math.rad(90)) -- cilindro "de pie" (el eje del cilindro de Roblox es X)
	local Cyl, Ball = Enum.PartType.Cylinder, Enum.PartType.Ball

	for _, leg in ipairs(if isR15 then {} else { rLeg, lLeg }) do -- R15: el pie ya va pintado del color de las botas
		a("Boot", v(1.08, 0.7, 1.08), look.Boots, leg, CFrame.new(0, -0.65, 0))
	end
	-- cara propia (los avatares no siempre traen carita visible): ojos con blanco + iris, boca
	local headPart = char:FindFirstChild("Head")
	if headPart then
		-- la carita por defecto del avatar (sonrisa negra) se oculta, también si Roblox la vuelve a poner un instante después
		local function hideFace(d: Instance)
			if d:IsA("Decal") or d:IsA("Texture") then
				d.Transparency = 1
			end
		end
		for _, d in ipairs(headPart:GetDescendants()) do
			hideFace(d)
		end
		headPart.DescendantAdded:Connect(hideFace)
	end
	-- cara estilo anime, pequeña y limpia: párpado, ojo (blanco + iris + pupila + brillo) y sonrisa corta
	local eyeColor: Color3 = look.Eye or Color3.fromRGB(20, 20, 24)
	local lidColor = Color3.fromRGB(24, 22, 28)
	for _, sx in ipairs({ -0.26, 0.26 }) do
		a("EyeWhite", v(0.25, 0.24, 0.05), Color3.new(1, 1, 1), head, CFrame.new(sx, 0.0, -0.615))
		a("Iris", v(0.16, 0.21, 0.055), eyeColor, head, CFrame.new(sx, -0.01, -0.635))
		a("Pupil", v(0.08, 0.12, 0.06), Color3.fromRGB(10, 10, 14), head, CFrame.new(sx, -0.01, -0.65))
		a("Glint", v(0.055, 0.055, 0.06), Color3.new(1, 1, 1), head, CFrame.new(sx + 0.035, 0.05, -0.665))
		a("Lid", v(0.3, 0.05, 0.06), lidColor, head, CFrame.new(sx, 0.135, -0.63) * CFrame.Angles(0, 0, math.rad(if sx > 0 then 6 else -6)))
	end
	local mouthColor = darker(skin, 0.4)
	a("Mouth", v(0.18, 0.045, 0.05), mouthColor, head, CFrame.new(0, -0.3, -0.62))
	for _, sx in ipairs({ -1, 1 }) do
		a("MouthCorner", v(0.08, 0.045, 0.05), mouthColor, head, CFrame.new(sx * 0.115, -0.275, -0.62) * CFrame.Angles(0, 0, math.rad(sx * 28)))
	end
	if look.Hair then
		addHair(look.HairStyle or "round", look.Hair, head, outfit)
	end
	if look.Cape then
		a("Cape", v(2.1, 2.8, 0.15), look.Cape, torso, CFrame.new(0, -0.3, 0.62) * CFrame.Angles(math.rad(8), 0, 0))
	end
	if look.Horns then
		for _, sx in ipairs({ -0.6, 0.6 }) do
			a("Horn", v(0.35, 0.9, 0.35), look.Horns, head, CFrame.new(sx, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-sx * 25)))
		end
	end
	local newHair = look.Hair ~= nil and HAIR[look.HairStyle or ""] ~= nil
	local hbHead: any = head -- los peinados nuevos van en medidas de cabeza R15 (sin el ajuste de R6): la banda rodea el pelo
	local hbS, hbY, hbZ = 1, 0.35, -0.57
	if newHair then
		hbHead = { Part = head.Part, Resolve = head.Resolve }
		hbS, hbY, hbZ = math.clamp(head.Part.Size.Y / 1.2, 0.6, 1.6), 0.38, -0.75
	end
	if look.Headband then
		if newHair then
			a("Headband", v(1.5, 0.26, 1.5) * hbS, look.Headband, hbHead, CFrame.new(0, hbY * hbS, 0.04 * hbS))
		else
			a("Headband", v(2.1, 0.3, 1.1), look.Headband, head, CFrame.new(0, 0.35, 0))
		end
		if look.HeadbandPlate ~= false then
			a("Plate", v(0.7, 0.3, 0.1) * (if newHair then 0.75 * hbS else 1), Color3.fromRGB(190, 195, 205), hbHead, CFrame.new(0, hbY * hbS, hbZ * hbS), nil, Enum.Material.Metal)
		end
		if look.EyeCover then -- Kakashi: el protector baja y tapa el ojo izquierdo
			a("EyeCover", v(0.4, 0.36, 0.08), look.Headband, head, CFrame.new(-0.26, 0.02, -0.66))
		end
		if look.HeadbandSlash then
			a("Slash", v(0.7, 0.07, 0.11) * (if newHair then 0.75 * hbS else 1), Color3.fromRGB(40, 40, 40), hbHead, CFrame.new(0, hbY * hbS, (if newHair then -0.79 else -0.58) * hbS) * CFrame.Angles(0, 0, math.rad(25)))
		end
	end
	if look.Mask then
		a("Mask", v(1.2, 0.55, 0.15), look.Mask, head, CFrame.new(0, -0.25, -0.62))
	end
	if look.HatStyle == "straw" then -- Luffy
		local hc: Color3 = look.Hat
		a("HatBrim", v(0.12, 2.9, 2.9), hc, head, CFrame.new(0, 0.62, 0) * rotZ, Cyl)
		a("HatTop", v(0.8, 1.5, 1.5), hc, head, CFrame.new(0, 1.05, 0) * rotZ, Cyl)
		a("HatBand", v(0.25, 1.56, 1.56), look.HatBand or Color3.fromRGB(192, 48, 43), head, CFrame.new(0, 0.78, 0) * rotZ, Cyl)
	elseif look.HatStyle == "turban" then -- Piccolo
		local hc: Color3 = look.Hat
		a("Turban", v(2.25, 0.6, 1.4), hc, head, CFrame.new(0, 0.6, 0))
		a("TurbanTop", v(1.8, 0.5, 1.15), darker(hc, 0.92), head, CFrame.new(0, 1.05, 0))
	elseif look.HatStyle == "cap" then -- Chopper
		local hc: Color3 = look.Hat
		a("Cap", v(2.2, 1.0, 1.35), hc, head, CFrame.new(0, 0.75, 0))
		local cross: Color3 = look.HatCross or Color3.new(1, 1, 1)
		a("CapCrossA", v(0.8, 0.18, 0.06), cross, head, CFrame.new(0, 0.8, -0.7) * CFrame.Angles(0, 0, math.rad(45)))
		a("CapCrossB", v(0.8, 0.18, 0.06), cross, head, CFrame.new(0, 0.8, -0.7) * CFrame.Angles(0, 0, math.rad(-45)))
	end
	if look.Goggles then -- Usopp
		a("GoggleStrap", v(2.2, 0.3, 1.2), Color3.fromRGB(58, 58, 58), head, CFrame.new(0, 0.45, 0))
		for _, sx in ipairs({ -0.45, 0.45 }) do
			a("GoggleLens", v(0.25, 0.65, 0.65), look.Goggles, head, CFrame.new(sx, 0.5, -0.62) * CFrame.Angles(0, math.rad(90), 0), Cyl)
		end
	end
	if look.LongNose then -- Usopp
		a("LongNose", v(0.35, 0.35, 1.0), look.LongNose, head, CFrame.new(0, -0.08, -0.95))
	end
	if look.Cigarette then -- Sanji
		a("Cigarette", v(0.12, 0.12, 0.55), Color3.fromRGB(240, 240, 240), head, CFrame.new(0.3, -0.3, -0.85))
		a("CigaretteTip", v(0.13, 0.13, 0.1), Color3.fromRGB(224, 122, 28), head, CFrame.new(0.3, -0.3, -1.15), nil, Enum.Material.Neon)
	end
	if look.Whiskers then -- Naruto: tres marcas por mejilla
		for _, sx in ipairs({ -1, 1 }) do
			for i = -1, 1 do
				a("Whisker", v(0.05, 0.3, 0.05), look.Whiskers, head, CFrame.new(sx * 0.62, -0.1 + i * 0.12, -0.64) * CFrame.Angles(0, 0, math.rad(sx * (80 + i * 12))))
			end
		end
	end
	if look.ForeheadMark then -- Gaara: "amor" en la frente
		a("ForeheadMark", v(0.28, 0.3, 0.06), look.ForeheadMark, head, CFrame.new(-0.55, 0.38, -0.64))
	end
	if look.Skirt then -- Bulma
		local c: Color3 = look.Skirt
		a("Skirt", v(2.3, 0.9, 1.3), c, torso, CFrame.new(0, -1.1, 0))
		a("SkirtHem", v(2.34, 0.1, 1.34), darker(c, 0.7), torso, CFrame.new(0, -1.55, 0))
	end
	if look.Gourd then -- Gaara: calabaza de arena
		local c: Color3 = look.Gourd
		a("GourdBody", v(1.9, 1.9, 1.9), c, torso, CFrame.new(0, 0.2, 1.3), Ball)
		a("GourdTop", v(1.0, 1.0, 1.0), c, torso, CFrame.new(0, 1.35, 1.2), Ball)
		a("GourdCork", v(0.4, 0.4, 0.4), darker(c, 0.6), torso, CFrame.new(0, 1.95, 1.2))
	end
	applyKit(look, outfit, torso, head, rArm, lArm, rLeg, lLeg, isR15)

	local scale = look.Scale
	if typeof(scale) == "number" and scale ~= 1 then
		char:ScaleTo(scale)
	end
	return true
end

return MobBuilder
