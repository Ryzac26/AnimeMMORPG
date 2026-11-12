--!strict
--[[
    BiomeClimate (LocalScript) -> StarterPlayer > StarterPlayerScripts > BiomeClimate
    CIELO Y CLIMA DE CADA FRANJA (16 franjas PvE + las 4 ciudades). Se suma a BiomeAmbientClient (que sigue poniendo luz, niebla, tinte y
    cielo A/B); este script agrega encima:
      - ATMÓSFERA (bruma, resplandor del sol), NUBES, BLOOM, RAYOS DE SOL y un ajuste de color (saturación / contraste) propios de cada franja.
      - ESTRELLAS y tamaño del sol / la luna por franja.
      - CLIMA que cambia solo: lluvia, tormenta con relámpagos, nieve, ceniza, tormenta de arena, pétalos, brasas, espuma de mar, brillos y niebla.
        El clima de cada franja es el MISMO para todos los jugadores (sale de la hora del servidor, cambia cada SLOT segundos).
    Todo se edita en la tabla CLIMATE (una línea de datos por franja). Es solo visual: no toca el servidor.
    No tiene pantalla (no va en RELOAD). En celular baja solo la cantidad de partículas.
]]
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- AJUSTES GENERALES
---------------------------------------------------------------------
local CONFIG = {
	CLIMA = true, -- partículas de clima (lluvia, nieve, arena...)
	RELAMPAGOS = true, -- destellos en las tormentas
	NUBES = true,
	BLOOM = true,
	SLOT = 150, -- segundos que dura cada "turno" de clima (cambia sola con la hora del servidor)
	INTENSIDAD = 1, -- multiplicador de las partículas (0.5 = la mitad)
	TRANSICION = 6, -- segundos que tarda en cambiar de un clima a otro
	HORIZONTE = true, -- cordillera propia en el horizonte (tapa las montañas negras pintadas en el cielo y evita los cortes entre caras)
	ALTURA = 1, -- altura de la cordillera (1 = normal; 1.3 = más alta; 0.8 = más baja)
}
local MOBILE = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local RATE_SCALE = (if MOBILE then 0.5 else 1) * CONFIG.INTENSIDAD

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------------
-- DATOS: una entrada por franja
--   Atm   = D densidad · O desfase · C color · Dc color de la caída · G resplandor del sol · H bruma
--   Cloud = Cover cobertura (0-1) · Dens densidad · Col color            (nil = sin nubes)
--   Bloom = Int intensidad · Size tamaño · Thr umbral
--   Rays  = intensidad de los rayos de sol
--   Grade = Sat saturación · Con contraste · Bri brillo
--   Stars estrellas · Sun / Moon tamaño angular
--   Wind  = viento (X, Z) · Fx = color de pétalos / brasas / brillos
--   Weather = lista { clima, peso }  (clear rain storm fog snow ash sand petals embers spray sparkle)
---------------------------------------------------------------------
type Climate = {
	Atm: { D: number, O: number, C: Color3, Dc: Color3, G: number, H: number },
	Cloud: { Cover: number, Dens: number, Col: Color3 }?,
	Bloom: { Int: number, Size: number, Thr: number },
	Rays: number,
	Grade: { Sat: number, Con: number, Bri: number },
	Stars: number,
	Sun: number,
	Moon: number,
	Wind: Vector2,
	Fx: Color3,
	Weather: { { any } },
}

local CLIMATE: { [string]: Climate } = {
	-- ======================= SAIYAN =======================
	Saiyan_1 = { -- llanura de entrada: cielo abierto y limpio
		Atm = { D = 0.25, O = 0.1, C = C(200, 222, 245), Dc = C(150, 185, 225), G = 0.2, H = 1.1 },
		Cloud = { Cover = 0.45, Dens = 0.5, Col = C(255, 255, 255) },
		Bloom = { Int = 0.25, Size = 24, Thr = 1.8 }, Rays = 0.06, Grade = { Sat = 0.08, Con = 0.04, Bri = 0 },
		Stars = 0, Sun = 21, Moon = 11, Wind = Vector2.new(1, 0.3), Fx = C(255, 236, 140),
		Weather = { { "clear", 6 }, { "rain", 1 } },
	},
	Saiyan_2 = { -- Planeta Esmeralda: bruma verde, lluvia suave
		Atm = { D = 0.36, O = 0.05, C = C(150, 232, 182), Dc = C(80, 170, 130), G = 0.1, H = 2 },
		Cloud = { Cover = 0.6, Dens = 0.55, Col = C(190, 240, 212) },
		Bloom = { Int = 0.4, Size = 28, Thr = 1.6 }, Rays = 0.04, Grade = { Sat = 0.15, Con = 0.03, Bri = 0 },
		Stars = 0, Sun = 19, Moon = 11, Wind = Vector2.new(0.6, 0.6), Fx = C(150, 255, 190),
		Weather = { { "fog", 3 }, { "rain", 2 }, { "clear", 3 } },
	},
	Saiyan_3 = { -- Ruinas / Arena Rota: atardecer polvoriento
		Atm = { D = 0.3, O = 0.15, C = C(232, 192, 142), Dc = C(200, 130, 80), G = 0.5, H = 1.5 },
		Cloud = { Cover = 0.3, Dens = 0.45, Col = C(225, 185, 145) },
		Bloom = { Int = 0.35, Size = 24, Thr = 1.7 }, Rays = 0.2, Grade = { Sat = -0.05, Con = 0.12, Bri = 0 },
		Stars = 0, Sun = 26, Moon = 11, Wind = Vector2.new(1.6, 0.4), Fx = C(255, 150, 60),
		Weather = { { "sand", 4 }, { "embers", 2 }, { "clear", 3 } },
	},
	Saiyan_4 = { -- Dimensión del Coloso: crepúsculo rosa con estrellas
		Atm = { D = 0.36, O = 0.1, C = C(242, 172, 224), Dc = C(190, 110, 170), G = 0.3, H = 1.8 },
		Cloud = { Cover = 0.5, Dens = 0.5, Col = C(255, 205, 238) },
		Bloom = { Int = 0.5, Size = 30, Thr = 1.5 }, Rays = 0.08, Grade = { Sat = 0.12, Con = 0.06, Bri = 0 },
		Stars = 2500, Sun = 22, Moon = 16, Wind = Vector2.new(0.5, 0.2), Fx = C(255, 215, 245),
		Weather = { { "sparkle", 4 }, { "clear", 3 }, { "fog", 1 } },
	},
	-- ======================= SHINOBI =======================
	Shinobi_1 = { -- bosque de la mañana: niebla baja entre los árboles
		Atm = { D = 0.4, O = 0.05, C = C(192, 212, 202), Dc = C(140, 172, 152), G = 0, H = 2.2 },
		Cloud = { Cover = 0.6, Dens = 0.5, Col = C(228, 238, 232) },
		Bloom = { Int = 0.2, Size = 22, Thr = 1.9 }, Rays = 0.1, Grade = { Sat = 0.05, Con = 0.02, Bri = 0 },
		Stars = 0, Sun = 18, Moon = 11, Wind = Vector2.new(0.5, 0.3), Fx = C(255, 255, 255),
		Weather = { { "fog", 4 }, { "clear", 3 }, { "rain", 1 } },
	},
	Shinobi_2 = { -- Valle de la Lluvia: casi siempre lloviendo
		Atm = { D = 0.46, O = 0, C = C(140, 156, 176), Dc = C(90, 110, 140), G = 0, H = 2.5 },
		Cloud = { Cover = 0.9, Dens = 0.7, Col = C(130, 142, 162) },
		Bloom = { Int = 0.2, Size = 20, Thr = 2 }, Rays = 0, Grade = { Sat = -0.1, Con = 0.1, Bri = -0.02 },
		Stars = 0, Sun = 14, Moon = 11, Wind = Vector2.new(-1, 0.4), Fx = C(180, 210, 255),
		Weather = { { "rain", 5 }, { "storm", 3 }, { "fog", 1 } },
	},
	Shinobi_3 = { -- Desierto de Arena Roja: sol duro y tormentas de arena
		Atm = { D = 0.3, O = 0.2, C = C(236, 196, 142), Dc = C(210, 140, 80), G = 0.6, H = 1.8 },
		Cloud = { Cover = 0.15, Dens = 0.35, Col = C(255, 235, 205) },
		Bloom = { Int = 0.35, Size = 26, Thr = 1.6 }, Rays = 0.15, Grade = { Sat = 0.12, Con = 0.15, Bri = 0 },
		Stars = 0, Sun = 28, Moon = 11, Wind = Vector2.new(2, 0.6), Fx = C(235, 175, 110),
		Weather = { { "clear", 4 }, { "sand", 4 } },
	},
	Shinobi_4 = { -- Valle Final: cielo carmesí, ceniza y tormenta seca
		Atm = { D = 0.42, O = 0.05, C = C(172, 92, 98), Dc = C(112, 52, 62), G = 0.2, H = 2.5 },
		Cloud = { Cover = 0.8, Dens = 0.65, Col = C(96, 52, 62) },
		Bloom = { Int = 0.4, Size = 26, Thr = 1.6 }, Rays = 0.05, Grade = { Sat = 0.05, Con = 0.2, Bri = -0.02 },
		Stars = 0, Sun = 20, Moon = 14, Wind = Vector2.new(1, -0.5), Fx = C(255, 110, 80),
		Weather = { { "ash", 5 }, { "storm", 2 }, { "fog", 1 } },
	},
	-- ======================= PIRATA =======================
	Pirate_1 = { -- costa luminosa
		Atm = { D = 0.2, O = 0.1, C = C(212, 236, 252), Dc = C(150, 195, 230), G = 0.3, H = 0.8 },
		Cloud = { Cover = 0.5, Dens = 0.55, Col = C(255, 255, 255) },
		Bloom = { Int = 0.25, Size = 24, Thr = 1.8 }, Rays = 0.1, Grade = { Sat = 0.1, Con = 0.04, Bri = 0 },
		Stars = 0, Sun = 22, Moon = 11, Wind = Vector2.new(1.5, 0.5), Fx = C(255, 255, 255),
		Weather = { { "clear", 6 }, { "spray", 2 }, { "rain", 1 } },
	},
	Pirate_2 = { -- Parque del Tiburón: playa dorada
		Atm = { D = 0.25, O = 0.15, C = C(246, 228, 178), Dc = C(220, 170, 100), G = 0.4, H = 1.2 },
		Cloud = { Cover = 0.35, Dens = 0.5, Col = C(255, 242, 218) },
		Bloom = { Int = 0.3, Size = 24, Thr = 1.8 }, Rays = 0.12, Grade = { Sat = 0.08, Con = 0.06, Bri = -0.02 },
		Stars = 0, Sun = 24, Moon = 11, Wind = Vector2.new(1.5, 0.3), Fx = C(255, 255, 255),
		Weather = { { "clear", 5 }, { "spray", 3 }, { "rain", 1 } },
	},
	Pirate_3 = { -- Puerta de la Justicia: mármol claro (bloom bajo para que no encandile)
		Atm = { D = 0.15, O = 0.05, C = C(240, 246, 255), Dc = C(190, 210, 235), G = 0.2, H = 0.5 },
		Cloud = { Cover = 0.3, Dens = 0.45, Col = C(255, 255, 255) },
		Bloom = { Int = 0.2, Size = 20, Thr = 2.2 }, Rays = 0.08, Grade = { Sat = 0, Con = 0.08, Bri = -0.04 },
		Stars = 0, Sun = 20, Moon = 11, Wind = Vector2.new(1, 0.2), Fx = C(255, 226, 140),
		Weather = { { "clear", 6 }, { "sparkle", 2 } },
	},
	Pirate_4 = { -- Almirantazgo: atardecer de tormenta
		Atm = { D = 0.4, O = 0.1, C = C(232, 152, 112), Dc = C(160, 82, 70), G = 0.6, H = 2 },
		Cloud = { Cover = 0.75, Dens = 0.6, Col = C(236, 152, 122) },
		Bloom = { Int = 0.3, Size = 24, Thr = 1.7 }, Rays = 0.18, Grade = { Sat = 0.06, Con = 0.14, Bri = 0 },
		Stars = 0, Sun = 26, Moon = 11, Wind = Vector2.new(-1.5, 0.6), Fx = C(255, 130, 60),
		Weather = { { "storm", 3 }, { "embers", 2 }, { "rain", 2 }, { "clear", 2 } },
	},
	-- ======================= SHINIGAMI =======================
	Shinigami_1 = { -- atardecer de pétalos
		Atm = { D = 0.3, O = 0.1, C = C(242, 192, 152), Dc = C(190, 122, 100), G = 0.4, H = 1.4 },
		Cloud = { Cover = 0.45, Dens = 0.5, Col = C(250, 202, 172) },
		Bloom = { Int = 0.3, Size = 24, Thr = 1.7 }, Rays = 0.14, Grade = { Sat = 0.08, Con = 0.06, Bri = 0 },
		Stars = 200, Sun = 24, Moon = 14, Wind = Vector2.new(1.2, 0.5), Fx = C(255, 182, 202),
		Weather = { { "petals", 5 }, { "clear", 3 } },
	},
	Shinigami_2 = { -- Páramo Vacío: noche azul, niebla de almas
		Atm = { D = 0.36, O = 0, C = C(72, 82, 132), Dc = C(40, 46, 92), G = 0, H = 1.8 },
		Cloud = { Cover = 0.4, Dens = 0.4, Col = C(82, 92, 142) },
		Bloom = { Int = 0.45, Size = 28, Thr = 1.5 }, Rays = 0, Grade = { Sat = -0.15, Con = 0.1, Bri = 0 },
		Stars = 4000, Sun = 12, Moon = 20, Wind = Vector2.new(0.5, 0.2), Fx = C(180, 190, 255),
		Weather = { { "fog", 4 }, { "clear", 4 }, { "sparkle", 1 } },
	},
	Shinigami_3 = { -- Cúpula del Eclipse: luna enorme
		Atm = { D = 0.3, O = 0, C = C(92, 98, 162), Dc = C(50, 56, 112), G = 0, H = 1.4 },
		Cloud = { Cover = 0.25, Dens = 0.35, Col = C(102, 108, 172) },
		Bloom = { Int = 0.6, Size = 32, Thr = 1.4 }, Rays = 0, Grade = { Sat = -0.1, Con = 0.1, Bri = 0 },
		Stars = 5000, Sun = 10, Moon = 32, Wind = Vector2.new(0.4, 0.2), Fx = C(168, 180, 255),
		Weather = { { "clear", 4 }, { "sparkle", 3 }, { "fog", 2 } },
	},
	Shinigami_4 = { -- Bastión Blanco: crepúsculo y copos blancos
		Atm = { D = 0.3, O = 0.1, C = C(242, 188, 152), Dc = C(200, 122, 92), G = 0.4, H = 1.4 },
		Cloud = { Cover = 0.5, Dens = 0.5, Col = C(255, 218, 192) },
		Bloom = { Int = 0.3, Size = 24, Thr = 1.8 }, Rays = 0.14, Grade = { Sat = 0.04, Con = 0.06, Bri = -0.02 },
		Stars = 300, Sun = 24, Moon = 14, Wind = Vector2.new(1, 0.4), Fx = C(255, 205, 150),
		Weather = { { "petals", 4 }, { "clear", 4 }, { "snow", 2 } },
	},
}

-- Ciudades (zona "" del servidor): cielo bonito y clima casi siempre despejado
local CITY: { [string]: Climate } = {
	Saiyan = {
		Atm = { D = 0.2, O = 0.1, C = C(205, 226, 248), Dc = C(150, 185, 225), G = 0.25, H = 0.9 },
		Cloud = { Cover = 0.4, Dens = 0.5, Col = C(255, 255, 255) },
		Bloom = { Int = 0.25, Size = 22, Thr = 1.9 }, Rays = 0.06, Grade = { Sat = 0.06, Con = 0.03, Bri = 0 },
		Stars = 0, Sun = 21, Moon = 11, Wind = Vector2.new(1, 0.3), Fx = C(255, 255, 255),
		Weather = { { "clear", 1 } },
	},
	Shinobi = {
		Atm = { D = 0.24, O = 0.05, C = C(212, 226, 222), Dc = C(160, 188, 172), G = 0.1, H = 1.2 },
		Cloud = { Cover = 0.5, Dens = 0.5, Col = C(240, 246, 242) },
		Bloom = { Int = 0.2, Size = 22, Thr = 1.9 }, Rays = 0.08, Grade = { Sat = 0.04, Con = 0.02, Bri = 0 },
		Stars = 0, Sun = 19, Moon = 11, Wind = Vector2.new(0.6, 0.3), Fx = C(255, 198, 214),
		Weather = { { "clear", 5 }, { "petals", 2 } },
	},
	Pirate = {
		Atm = { D = 0.18, O = 0.1, C = C(214, 238, 252), Dc = C(152, 196, 232), G = 0.3, H = 0.7 },
		Cloud = { Cover = 0.45, Dens = 0.55, Col = C(255, 255, 255) },
		Bloom = { Int = 0.22, Size = 22, Thr = 1.9 }, Rays = 0.1, Grade = { Sat = 0.08, Con = 0.03, Bri = 0 },
		Stars = 0, Sun = 22, Moon = 11, Wind = Vector2.new(1.4, 0.4), Fx = C(255, 255, 255),
		Weather = { { "clear", 6 }, { "spray", 1 } },
	},
	Shinigami = {
		Atm = { D = 0.28, O = 0.1, C = C(240, 190, 156), Dc = C(188, 122, 100), G = 0.35, H = 1.3 },
		Cloud = { Cover = 0.45, Dens = 0.5, Col = C(250, 204, 176) },
		Bloom = { Int = 0.3, Size = 24, Thr = 1.7 }, Rays = 0.12, Grade = { Sat = 0.06, Con = 0.05, Bri = 0 },
		Stars = 400, Sun = 23, Moon = 14, Wind = Vector2.new(1, 0.4), Fx = C(255, 190, 210),
		Weather = { { "clear", 4 }, { "petals", 2 } },
	},
}
local DEFAULT_CITY = CITY.Saiyan

---------------------------------------------------------------------
-- EFECTOS (se reutilizan los que ya existan)
---------------------------------------------------------------------
local terrain = Workspace:WaitForChild("Terrain")

local function ensure(parent: Instance, class: string, name: string): any
	local inst = parent:FindFirstChild(name)
	if inst and inst.ClassName == class then
		return inst
	end
	local n = Instance.new(class)
	n.Name = name
	n.Parent = parent
	return n
end

local atmosphere: Atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or ensure(Lighting, "Atmosphere", "ClimaAtmosfera")
local clouds: Clouds = terrain:FindFirstChildOfClass("Clouds") or ensure(terrain, "Clouds", "ClimaNubes")
local bloom: BloomEffect = ensure(Lighting, "BloomEffect", "ClimaBloom")
local rays: SunRaysEffect = ensure(Lighting, "SunRaysEffect", "ClimaRayos")
local grade: ColorCorrectionEffect = ensure(Lighting, "ColorCorrectionEffect", "ClimaColor")
clouds.Enabled = CONFIG.NUBES
bloom.Enabled = CONFIG.BLOOM

---------------------------------------------------------------------
-- PARTÍCULAS: dos plataformas que siguen a la cámara (alta = lluvia/nieve/ceniza/pétalos, baja = arena/espuma/brasas/brillos)
---------------------------------------------------------------------
local function makeCarrier(name: string, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = size
	p.Parent = Workspace
	return p
end
local AREA = if MOBILE then 90 else 130
local highPart = makeCarrier("ClimaAlto", Vector3.new(AREA, 1, AREA))
local lowPart = makeCarrier("ClimaBajo", Vector3.new(AREA, 6, AREA))

local function emitter(parent: Part, name: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Rate = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightInfluence = 0.5
	e.Parent = parent
	return e
end

local FADE = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) })

local E: { [string]: ParticleEmitter } = {}
local BASE_RATE: { [string]: number } = {}

local function define(name: string, parent: Part, rate: number, setup: (ParticleEmitter) -> ())
	local e = emitter(parent, name)
	setup(e)
	E[name] = e
	BASE_RATE[name] = rate
end

define("rain", highPart, 260, function(e)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Lifetime = NumberRange.new(0.8, 1)
	e.Speed = NumberRange.new(80, 95)
	e.SpreadAngle = Vector2.new(2, 2)
	e.Size = NumberSequence.new(0.16)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-14)
	e.Transparency = NumberSequence.new(0.55)
	e.Color = ColorSequence.new(C(190, 210, 235))
	e.LightEmission = 0.2
end)
define("storm", highPart, 520, function(e)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Lifetime = NumberRange.new(0.7, 0.9)
	e.Speed = NumberRange.new(95, 115)
	e.SpreadAngle = Vector2.new(4, 4)
	e.Size = NumberSequence.new(0.18)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-16)
	e.Transparency = NumberSequence.new(0.5)
	e.Color = ColorSequence.new(C(175, 195, 225))
	e.LightEmission = 0.15
end)
define("snow", highPart, 140, function(e)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Lifetime = NumberRange.new(6, 8)
	e.Speed = NumberRange.new(5, 8)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new(0.32)
	e.Transparency = NumberSequence.new(0.1)
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Color = ColorSequence.new(C(255, 255, 255))
	e.LightEmission = 0.5
end)
define("ash", highPart, 70, function(e)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Lifetime = NumberRange.new(6, 9)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.25) })
	e.Transparency = FADE
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Color = ColorSequence.new(C(90, 78, 78))
	e.LightInfluence = 0.9
end)
define("petals", highPart, 14, function(e)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Lifetime = NumberRange.new(8, 11)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Size = NumberSequence.new(0.55)
	e.Transparency = FADE
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Color = ColorSequence.new(C(255, 182, 202))
	e.LightInfluence = 0.3
end)
define("sand", lowPart, 120, function(e)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(1, 5)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.7), NumberSequenceKeypoint.new(0.75, 0.75), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(C(228, 176, 116))
	e.LightInfluence = 0.8
	e.RotSpeed = NumberRange.new(-30, 30)
end)
define("spray", lowPart, 24, function(e)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(0.7, 0.88), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(C(235, 245, 255))
	e.LightInfluence = 1
end)
define("embers", lowPart, 38, function(e)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(4, 6)
	e.Speed = NumberRange.new(6, 11)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.08) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new(C(255, 140, 50))
	e.LightEmission = 1
	e.LightInfluence = 0
end)
define("sparkle", lowPart, 26, function(e)
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1)
	e.Color = ColorSequence.new(C(255, 240, 200))
	e.LightEmission = 1
	e.LightInfluence = 0
end)

local WEATHER_FX = { "rain", "storm", "snow", "ash", "petals", "sand", "spray", "embers", "sparkle" }
local targetRate: { [string]: number } = {}
local curRate: { [string]: number } = {}
for _, n in ipairs(WEATHER_FX) do
	targetRate[n] = 0
	curRate[n] = 0
end

---------------------------------------------------------------------
-- CÓMO CAMBIA EL CIELO SEGÚN EL CLIMA
---------------------------------------------------------------------
type Mod = { Dens: number, Haze: number, Cover: number, Dark: number, Desat: number, Tint: Color3?, TintK: number, Rays: number }
local MOD: { [string]: Mod } = {
	clear = { Dens = 0, Haze = 0, Cover = 0, Dark = 0, Desat = 0, TintK = 0, Rays = 1 },
	rain = { Dens = 0.1, Haze = 0.8, Cover = 0.85, Dark = 0.03, Desat = 0.08, TintK = 0, Rays = 0 },
	storm = { Dens = 0.18, Haze = 1.4, Cover = 1, Dark = 0.07, Desat = 0.15, Tint = C(70, 80, 100), TintK = 0.25, Rays = 0 },
	fog = { Dens = 0.25, Haze = 1.5, Cover = 0.7, Dark = 0.01, Desat = 0.05, Tint = C(225, 230, 235), TintK = 0.3, Rays = 0.3 },
	snow = { Dens = 0.1, Haze = 0.8, Cover = 0.8, Dark = 0, Desat = 0.05, Tint = C(235, 242, 255), TintK = 0.3, Rays = 0.2 },
	ash = { Dens = 0.1, Haze = 1, Cover = 0.85, Dark = 0.03, Desat = 0.08, Tint = C(110, 100, 100), TintK = 0.3, Rays = 0 },
	sand = { Dens = 0.3, Haze = 1.4, Cover = 0.2, Dark = 0.02, Desat = 0.03, Tint = C(226, 176, 120), TintK = 0.6, Rays = 0.2 },
	petals = { Dens = 0, Haze = 0, Cover = 0, Dark = 0, Desat = 0, TintK = 0, Rays = 1 },
	embers = { Dens = 0.04, Haze = 0.3, Cover = 0.1, Dark = 0.01, Desat = 0, TintK = 0, Rays = 0.8 },
	spray = { Dens = 0.03, Haze = 0.2, Cover = 0, Dark = 0, Desat = 0, TintK = 0, Rays = 1 },
	sparkle = { Dens = 0, Haze = 0, Cover = 0, Dark = 0, Desat = 0, TintK = 0, Rays = 1 },
}

-- cuántas partículas de cada tipo según el clima (se multiplica por la intensidad)
local FX_OF: { [string]: string } = {
	rain = "rain", storm = "storm", snow = "snow", ash = "ash", petals = "petals", sand = "sand", spray = "spray", embers = "embers", sparkle = "sparkle",
}

local tweens: { Tween } = {}
local function play(inst: Instance, seconds: number, goal: { [string]: any })
	local tw = TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), goal)
	table.insert(tweens, tw)
	tw:Play()
end
local function clearTweens()
	for _, t in ipairs(tweens) do
		t:Cancel()
	end
	table.clear(tweens)
end

local currentClimate: Climate? = nil

local function applySky(c: Climate)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = c.Stars
		sky.SunAngularSize = c.Sun
		sky.MoonAngularSize = c.Moon
		sky.CelestialBodiesShown = true
	end
end
Lighting.ChildAdded:Connect(function(ch: Instance)
	if ch:IsA("Sky") then
		task.defer(function()
			if currentClimate then
				applySky(currentClimate)
			end
		end)
	end
end)

local function applyClimate(c: Climate, weather: string, intensity: number, secs: number)
	local m = MOD[weather] or MOD.clear
	local k = intensity
	local atmColor = c.Atm.C
	if m.Tint then
		atmColor = atmColor:Lerp(m.Tint, m.TintK * k)
	end
	clearTweens()
	play(atmosphere, secs, {
		Density = math.clamp(c.Atm.D + m.Dens * k, 0, 1),
		Offset = c.Atm.O,
		Color = atmColor,
		Decay = c.Atm.Dc:Lerp(atmColor, m.TintK * k * 0.5),
		Glare = c.Atm.G * (1 - math.min(1, (1 - m.Rays) * k)),
		Haze = c.Atm.H + m.Haze * k,
	})
	if c.Cloud then
		local cover = math.max(c.Cloud.Cover, m.Cover * k)
		clouds.Enabled = CONFIG.NUBES
		play(clouds, secs, {
			Cover = math.clamp(cover, 0, 1),
			Density = c.Cloud.Dens,
			Color = c.Cloud.Col:Lerp(Color3.new(0.35, 0.37, 0.42), math.min(1, m.Dark * 6 * k)),
		})
	else
		clouds.Enabled = false
	end
	bloom.Enabled = CONFIG.BLOOM
	play(bloom, secs, { Intensity = c.Bloom.Int, Size = c.Bloom.Size, Threshold = c.Bloom.Thr })
	play(rays, secs, { Intensity = c.Rays * (1 - (1 - m.Rays) * k), Spread = 0.6 })
	play(grade, secs, {
		Saturation = c.Grade.Sat - m.Desat * k,
		Contrast = c.Grade.Con,
		Brightness = c.Grade.Bri - m.Dark * k,
	})
	applySky(c)
end

---------------------------------------------------------------------
-- QUÉ CLIMA TOCA (igual para todos los jugadores)
---------------------------------------------------------------------
local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

local function pickWeather(zone: string, c: Climate, slot: number): (string, number)
	local rng = Random.new(hashString(zone) * 7919 + slot)
	local total = 0
	for _, w in ipairs(c.Weather) do
		total += w[2] :: number
	end
	local roll = rng:NextNumber() * total
	local name = "clear"
	for _, w in ipairs(c.Weather) do
		roll -= w[2] :: number
		if roll <= 0 then
			name = w[1] :: string
			break
		end
	end
	return name, 0.55 + rng:NextNumber() * 0.45
end

local currentZone = ""
local currentWeather = ""
local currentIntensity = 0
local currentSlot = -1


---------------------------------------------------------------------
-- HORIZONTE: cordillera continua alrededor del jugador
-- El cielo pintado trae su propia silueta de montañas, que cambia de una cara a otra (cortes y bloques negros). Esta cordillera es de
-- piezas reales, se ve igual en los 360 grados, toma el color y la bruma de cada franja y siempre tapa la silueta pintada.
-- Siempre está lejos (1100 a 2000 studs) y sigue al jugador, así que nunca se alcanza. Sin colisión.
---------------------------------------------------------------------
type RidgeLayer = { R: number, ElevMin: number, ElevMax: number, Depth: number, N: number, Parts: { BasePart } }
local RIDGE_STYLE: { [string]: { Sharp: number, Seed: number } } = {
	Saiyan = { Sharp = 1.1, Seed = 1.3 },
	Shinobi = { Sharp = 0.9, Seed = 4.1 },
	Pirate = { Sharp = 1.3, Seed = 2.2 },
	Shinigami = { Sharp = 0.8, Seed = 5.7 },
}
local ridgeModel = Instance.new("Model")
ridgeModel.Name = "ClimaHorizonte"
local ridgePivot = Instance.new("Part") -- punto de giro en el centro, a la altura de la base (para que PivotTo mueva todo bien)
ridgePivot.Name = "Pivote"
ridgePivot.Anchored = true
ridgePivot.CanCollide = false
ridgePivot.CanQuery = false
ridgePivot.CanTouch = false
ridgePivot.Transparency = 1
ridgePivot.Size = Vector3.one
ridgePivot.CFrame = CFrame.new(0, 0, 0)
ridgePivot.Parent = ridgeModel
ridgeModel.PrimaryPart = ridgePivot
local ridgeBuilding = false
local ridgeLayers: { RidgeLayer } = {}
local ridgeBuilt = false
local ridgeFaction = ""
local ridgeBaseY = 0
local ridgeLastPos = Vector3.new(1e9, 0, 1e9)
local ridgeColors: { Color3 } = {}
local ridgeFrom: { Color3 } = {}
local ridgeT = 1

-- ¿hacia qué lado sube la pendiente de una cuña? (se mide con un rayo; así no dependemos de cómo la oriente Roblox)
local function wedgeHighSide(): number
	local t = Instance.new("WedgePart")
	t.Size = Vector3.new(4, 20, 20)
	t.Anchored = true
	t.CFrame = CFrame.new(0, -6000, 0)
	t.Parent = Workspace
	task.wait(0.15)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { t }
	local a = Workspace:Raycast(Vector3.new(0, -5900, 7), Vector3.new(0, -200, 0), rp)
	local b = Workspace:Raycast(Vector3.new(0, -5900, -7), Vector3.new(0, -200, 0), rp)
	t:Destroy()
	if a and b then
		return if a.Position.Y > b.Position.Y then 1 else -1
	end
	return -1
end

local function profile(a: number, seed: number, sharp: number): number
	local v = math.sin(a * 3 + seed * 1.7) * 0.5 + math.sin(a * 7 + seed * 3.1) * 0.3 + math.sin(a * 13 + seed * 5.3) * 0.2 + math.sin(a * 29 + seed * 7.9) * 0.12
	local n = math.clamp(0.5 + 0.5 * v / 1.12, 0, 1)
	return n ^ sharp
end

local function ridgeTargets(c: Climate)
	-- lejana: clara y azulada por la bruma · media · cercana: más oscura (siempre con algo de color, nunca negra)
	local far = c.Atm.C:Lerp(c.Atm.Dc, 0.4)
	local mid = c.Atm.Dc:Lerp(c.Atm.C, 0.25):Lerp(Color3.new(0, 0, 0), 0.25)
	local near = c.Atm.Dc:Lerp(Color3.new(0, 0, 0), 0.45):Lerp(c.Atm.C, 0.1)
	return { far, mid, near }
end

local function buildRidge(faction: string, base: Color3)
	for _, l in ipairs(ridgeLayers) do
		for _, p in ipairs(l.Parts) do
			p:Destroy()
		end
	end
	table.clear(ridgeLayers)
	-- las piezas nuevas se crean alrededor del origen: devolver el pivote al origen (si no, quedan donde estaba el modelo y el anillo
	-- de montañas pasa por encima del jugador al cambiar de facción) y forzar que se vuelva a centrar en la cámara
	ridgeModel:PivotTo(CFrame.new(0, 0, 0))
	ridgeLastPos = Vector3.new(1e9, 0, 1e9)
	ridgeBaseY = 0
	local hs = wedgeHighSide()
	local style = RIDGE_STYLE[faction] or RIDGE_STYLE.Saiyan
	local defs = {
		{ R = 2000, ElevMin = 14, ElevMax = 23, Depth = 520, N = if MOBILE then 64 else 96 },
		{ R = 1550, ElevMin = 7, ElevMax = 14, Depth = 420, N = if MOBILE then 56 else 84 },
		{ R = 1150, ElevMin = 3, ElevMax = 8, Depth = 320, N = if MOBILE then 0 else 72 },
	}
	for li, d in ipairs(defs) do
		local layer: RidgeLayer = { R = d.R, ElevMin = d.ElevMin, ElevMax = d.ElevMax, Depth = d.Depth, N = d.N, Parts = {} }
		table.insert(ridgeLayers, layer)
		local rng = Random.new(style.Seed * 1000 + li)
		for i = 0, d.N - 1 do
			local ang = i * 2 * math.pi / d.N
			local rv = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local tv = Vector3.new(-math.sin(ang), 0, math.cos(ang))
			local f = profile(ang + li * 0.7, style.Seed + li, style.Sharp) * (0.9 + rng:NextNumber() * 0.2)
			local elev = math.rad(d.ElevMin + (d.ElevMax - d.ElevMin) * math.clamp(f, 0, 1))
			local H = d.R * math.tan(elev) * CONFIG.ALTURA + 160
			local B = (2 * math.pi * d.R / d.N) * 2.3
			local peak = rv * d.R
			for half = -1, 1, 2 do
				local w = Instance.new("WedgePart")
				w.Anchored = true
				w.CanCollide = false
				w.CanQuery = false
				w.CanTouch = false
				w.CastShadow = false
				w.Material = Enum.Material.Slate
				w.Color = base
				w.Size = Vector3.new(d.Depth, H, B / 2)
				-- mitad izquierda (half = -1): sube hacia +tangente; derecha: sube hacia -tangente
				local zv = tv * (hs * -half)
				local xv = Vector3.yAxis:Cross(zv)
				w.CFrame = CFrame.fromMatrix(peak + tv * (half * B / 4) + Vector3.new(0, H / 2, 0), xv, Vector3.yAxis, zv)
				w.Parent = ridgeModel
				table.insert(layer.Parts, w)
			end
		end
	end
	ridgeFaction = faction
	ridgeBuilt = true
end

local function setRidgeColors(c: Climate, instant: boolean)
	local t = ridgeTargets(c)
	if instant then
		for li, l in ipairs(ridgeLayers) do
			for _, p in ipairs(l.Parts) do
				p.Color = t[li]
			end
		end
	end
	ridgeFrom = {}
	for li, l in ipairs(ridgeLayers) do
		ridgeFrom[li] = if l.Parts[1] then l.Parts[1].Color else t[li]
	end
	ridgeColors = t
	ridgeT = if instant then 1 else 0
end

local function updateRidge(zone: string, c: Climate)
	if not CONFIG.HORIZONTE or ridgeBuilding then
		return
	end
	local fname = string.match(zone, "^(%a+)_") or ""
	if fname == "Ciudad" then
		local f = player:GetAttribute("Faction")
		fname = if typeof(f) == "string" then f else "Saiyan"
	end
	if not ridgeBuilt or fname ~= ridgeFaction then
		ridgeBuilding = true
		local base = ridgeTargets(c)[1]
		buildRidge(fname, base)
		setRidgeColors(c, true)
		ridgeModel.Parent = Workspace
		ridgeBuilding = false
	else
		setRidgeColors(c, false)
	end
end

local function ridgeEnable(on: boolean)
	ridgeModel.Parent = if on and ridgeBuilt then Workspace else nil
end

---------------------------------------------------------------------
-- CICLO PRINCIPAL
---------------------------------------------------------------------
local function zoneKey(): (string, Climate)
	local z = player:GetAttribute("BiomeZone")
	if typeof(z) == "string" and z ~= "" and CLIMATE[z] then
		return z, CLIMATE[z]
	end
	local f = player:GetAttribute("Faction")
	local fname = if typeof(f) == "string" then f else ""
	return "Ciudad_" .. fname, CITY[fname] or DEFAULT_CITY
end

local function setEffectsEnabled(on: boolean)
	grade.Enabled = on
	rays.Enabled = on
	bloom.Enabled = on and CONFIG.BLOOM
	ridgeEnable(on)
	if not on then
		clouds.Enabled = false
		play(atmosphere, 1.5, { Density = 0, Haze = 0, Glare = 0 })
	end
end

local lastInHouse = false
local function update(force: boolean)
	local inHouse = player:GetAttribute("InHouse") == true
	if inHouse ~= lastInHouse then
		lastInHouse = inHouse
		setEffectsEnabled(not inHouse)
		if inHouse then
			for _, n in ipairs(WEATHER_FX) do
				targetRate[n] = 0
			end
			currentZone = ""
			return
		end
		force = true
	end
	if inHouse then
		return
	end
	local zone, c = zoneKey()
	local slot = math.floor(Workspace:GetServerTimeNow() / CONFIG.SLOT)
	if not force and zone == currentZone and slot == currentSlot then
		return
	end
	local weather, intensity = pickWeather(zone, c, slot)
	local zoneChanged = zone ~= currentZone
	local same = (not zoneChanged) and weather == currentWeather
	currentZone, currentSlot, currentClimate = zone, slot, c
	if same and not force then
		return
	end
	currentWeather, currentIntensity = weather, intensity
	applyClimate(c, weather, intensity, if zoneChanged then 3 else CONFIG.TRANSICION)
	if zoneChanged or not ridgeBuilt then
		task.spawn(updateRidge, zone, c)
	end
	-- partículas
	for _, n in ipairs(WEATHER_FX) do
		targetRate[n] = 0
	end
	local fx = FX_OF[weather]
	if fx and CONFIG.CLIMA then
		targetRate[fx] = BASE_RATE[fx] * intensity * RATE_SCALE
	end
	-- el clima de ambiente de la franja (pétalos / brasas / brillos) nunca se apaga del todo
	if CONFIG.CLIMA and weather ~= "petals" and weather ~= "embers" and weather ~= "sparkle" and weather ~= "rain" and weather ~= "storm" then
		for _, w in ipairs(c.Weather) do
			local nm = w[1] :: string
			if nm == "petals" or nm == "sparkle" then
				targetRate[nm] = math.max(targetRate[nm], BASE_RATE[nm] * 0.25 * RATE_SCALE)
			end
		end
	end
	-- viento y color de la franja
	local wind = c.Wind
	for _, n in ipairs(WEATHER_FX) do
		local e = E[n]
		local strength = if n == "sand" then 14 elseif n == "rain" or n == "storm" then 3 elseif n == "ash" or n == "snow" then 2.5 elseif n == "spray" then 4 else 3
		e.Acceleration = Vector3.new(wind.X * strength, e.Acceleration.Y, wind.Y * strength)
	end
	E.petals.Color = ColorSequence.new(c.Fx)
	E.embers.Color = ColorSequence.new(c.Fx)
	E.sparkle.Color = ColorSequence.new(c.Fx)
end

player:GetAttributeChangedSignal("BiomeZone"):Connect(function()
	update(false)
end)
player:GetAttributeChangedSignal("Faction"):Connect(function()
	update(false)
end)
player:GetAttributeChangedSignal("InHouse"):Connect(function()
	update(false)
end)
task.spawn(function()
	while true do
		update(false)
		task.wait(2)
	end
end)
update(true)

-- las plataformas siguen a la cámara; los caudales suben o bajan suavemente
RunService.RenderStepped:Connect(function(dt: number)
	local cam = Workspace.CurrentCamera
	if cam then
		local pos = cam.CFrame.Position
		highPart.CFrame = CFrame.new(pos + Vector3.new(0, 38, 0))
		lowPart.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
	end
	if ridgeBuilt and cam then
		local p = cam.CFrame.Position
		if ridgeBaseY == 0 then
			local ch = player.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			ridgeBaseY = (if root and root:IsA("BasePart") then root.Position.Y else p.Y) - 140
		end
		if (Vector3.new(p.X, 0, p.Z) - Vector3.new(ridgeLastPos.X, 0, ridgeLastPos.Z)).Magnitude > 8 then
			ridgeLastPos = p
			ridgeModel:PivotTo(CFrame.new(p.X, ridgeBaseY, p.Z))
		end
		if ridgeT < 1 then
			ridgeT = math.min(1, ridgeT + dt / 2.5)
			for li, l in ipairs(ridgeLayers) do
				local col = (ridgeFrom[li] or ridgeColors[li]):Lerp(ridgeColors[li], ridgeT)
				for _, part in ipairs(l.Parts) do
					part.Color = col
				end
			end
		end
	end
	local a = math.clamp(dt / 3, 0, 1)
	for _, n in ipairs(WEATHER_FX) do
		local r = curRate[n] + (targetRate[n] - curRate[n]) * a
		if math.abs(r - targetRate[n]) < 0.05 then
			r = targetRate[n]
		end
		curRate[n] = r
		E[n].Rate = r
	end
end)

-- relámpagos durante las tormentas
local rng = Random.new()
local function flash()
	local up = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local down = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(Lighting, up, { ExposureCompensation = 1.4 }):Play()
	task.wait(0.07)
	TweenService:Create(Lighting, down, { ExposureCompensation = 0 }):Play()
end
task.spawn(function()
	while true do
		task.wait(rng:NextNumber(6, 16))
		if CONFIG.RELAMPAGOS and currentWeather == "storm" and player:GetAttribute("InHouse") ~= true then
			flash()
			if rng:NextNumber() < 0.5 then
				task.wait(0.18)
				flash()
			end
		end
	end
end)
