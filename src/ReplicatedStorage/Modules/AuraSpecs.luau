--!strict
--[[
    AuraSpecs (ModuleScript) -> ReplicatedStorage.Modules.AuraSpecs
    "Receta" de cada aura = lista de CAPAS que dibuja AuraClient. Clave = Id del aura en LevelMilestones.Auras.
    Colores: "A" / "B" = los del aura, "AB" degradado, "W" blanco, "WA"/"WB" blanco->color, "dark" oscuro, "rainbow" arcoíris, o un Color3.
    Capas (T):
      ground  : textura plana girando en el piso (Tex, C, Size, Spin, Y, Alpha, Pulse, Tilt, Rainbow)
      back    : plano detrás del torso que gira (halo/rayos/galaxia)  (Tex, C, Size, Spin, Y, Alpha)
      glow    : resplandor que mira a la cámara (Tex, C, Size, Alpha, Pulse, Y)
      emit    : partículas (Tex = nombre o lista, C, Where = root|feet|head|around|limbs, Rate, Life, Speed, Spread, Size, Accel, Dir, Alpha, Spin, Orient, Light)
      orbit   : cosas que giran alrededor (Kind = orb|rock|leaf|butterfly|eye|wave|shard|petal, N, Size, Radius, Speed, Tex, C, Trail, Tilts)
      arcs    : rayos que saltan (N)
      wings   : alas de plumas (Tex lista, C, Count, Scale)
      pillar  : pilar de luz (C)
      hl      : contorno/resplandor del cuerpo (Fill, Out)
      light   : luz puntual (Range, Bright, Flicker)
      bloom   : activa un brillo suave en pantalla (solo para quien la lleva)
]]
local TILT3 = { Vector3.new(0, 0, 0), Vector3.new(0.9, 0, 0.5), Vector3.new(-0.9, 0, 0.5) }

local S: { [string]: { any } } = {}

S.Brisa = {
	{ T = "ground", Tex = "Anillo-energia", C = "A", Size = 7, Spin = 1.2, Alpha = 0.55 },
	{ T = "emit", Tex = "Estela-viento", C = "WA", Where = "root", Rate = 9, Life = { 0.6, 1 }, Speed = { 8, 13 }, Spread = 180, Size = { 2.6, 0.6 }, Orient = "VelocityParallel", Alpha = { 0.2, 1 } },
	{ T = "emit", Tex = "Chispa-punto", C = "W", Where = "around", Rate = 8, Life = { 0.8, 1.4 }, Speed = { 0, 1 }, Size = { 0.7, 0 } },
	{ T = "hl", Fill = 0.93, Out = 0.6 },
}
S.Petalos = {
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 8, Spin = 0.4, Alpha = 0.5 },
	{ T = "emit", Tex = { "Petalo-sakura" }, C = "AB", Where = "head", Rate = 8, Life = { 3, 4.5 }, Speed = { 0.5, 1.5 }, Spread = 25, Size = { 0.9, 0.9 }, Accel = Vector3.new(0, -0.8, 0), Dir = "Bottom", Spin = 90, Light = 0.15, Alpha = { 0, 0.9 } },
	{ T = "emit", Tex = "Destello-4-puntas", C = "WA", Where = "around", Rate = 4, Life = { 1, 1.6 }, Speed = { 0, 0.6 }, Size = { 1.2, 0 } },
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 9, Alpha = 0.85, Pulse = 0.05 },
	{ T = "hl", Fill = 0.9, Out = 0.5 },
}
S.Brillo = {
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 10, Alpha = 0.72, Pulse = 0.08 },
	{ T = "ground", Tex = "Anillo-runas", C = "B", Size = 7.5, Spin = 0.5, Alpha = 0.45 },
	{ T = "emit", Tex = "Destello-4-puntas", C = "WA", Where = "around", Rate = 16, Life = { 1, 1.8 }, Speed = { 0, 0.6 }, Size = { 1.4, 0 } },
	{ T = "emit", Tex = "Destello-lente", C = "W", Where = "around", Rate = 2, Life = { 1.2, 1.8 }, Speed = { 0, 0.3 }, Size = { 4, 0 } },
	{ T = "hl", Fill = 0.9, Out = 0.55 },
	{ T = "light", Range = 10, Bright = 0.8 },
}
S.Escarcha = {
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 9, Spin = -0.8, Alpha = 0.5 },
	{ T = "ground", Tex = "Anillo-energia", C = "B", Size = 6, Spin = 2, Alpha = 0.4 },
	{ T = "emit", Tex = { "Copo-nieve-A", "Copo-nieve-B" }, C = "WA", Where = "head", Rate = 9, Life = { 3, 4 }, Speed = { 0.5, 1.5 }, Spread = 25, Size = { 1, 1 }, Accel = Vector3.new(0, -1, 0), Dir = "Bottom", Spin = 80, Alpha = { 0, 0.9 } },
	{ T = "emit", Tex = "Humo-A", C = "WA", Where = "feet", Rate = 3, Life = { 2, 3 }, Speed = { 0.5, 1 }, Size = { 2, 5 }, Alpha = { 0.7, 1 }, Light = 0.1 },
	{ T = "orbit", Kind = "shard", Tex = "Cristal-B", N = 5, Radius = 3.8, Speed = 1.2, Size = 2.2, C = "AB", Tilts = TILT3 },
	{ T = "hl", Fill = 0.86, Out = 0.3 },
	{ T = "light", Range = 12, Bright = 1 },
}
S.Llama = {
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 9, Alpha = 0.7, Pulse = 0.12 },
	{ T = "ground", Tex = "Anillo-energia", C = "A", Size = 8, Spin = -0.7, Alpha = 0.4 },
	{ T = "emit", Tex = { "Llama-A", "Llama-B", "Llama-C" }, C = "AB", Where = "limbs", Rate = 24, Life = { 0.5, 0.9 }, Speed = { 2, 4 }, Spread = 25, Size = { 2.2, 0.5 }, Accel = Vector3.new(0, 8, 0), Alpha = { 0.25, 1 } },
	{ T = "emit", Tex = { "Llama-A", "Llama-C" }, C = "AB", Where = "feet", Rate = 22, Life = { 0.8, 1.4 }, Speed = { 3, 6 }, Spread = 20, Size = { 4, 0.8 }, Accel = Vector3.new(0, 8, 0), Alpha = { 0.3, 1 } },
	{ T = "emit", Tex = "Brasas", C = "WB", Where = "around", Rate = 5, Life = { 1.2, 2 }, Speed = { 4, 8 }, Size = { 3, 3 }, Accel = Vector3.new(0, 6, 0) },
	{ T = "emit", Tex = "Humo-B", C = "dark", Where = "head", Rate = 5, Life = { 1.4, 2.2 }, Speed = { 1.5, 3 }, Size = { 1.4, 3.4 }, Dir = "Top", Alpha = { 0.65, 1 }, Light = 0.05 },
	{ T = "hl", Fill = 0.78, Out = 0.2 },
	{ T = "light", Range = 15, Bright = 2, Flicker = 0.5 },
}
S.Roca = {
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 10, Spin = 0.5, Alpha = 0.45 },
	{ T = "orbit", Kind = "rock", N = 7, Radius = 3.8, Speed = 1.1, Size = 1, Tilts = TILT3 },
	{ T = "orbit", Kind = "shard", Tex = "Cristal-A", N = 5, Radius = 4.8, Speed = -1.4, Size = 1.9, C = "B", Tilts = TILT3 },
	{ T = "emit", Tex = "Humo-A", C = "A", Where = "feet", Rate = 4, Life = { 1.5, 2.5 }, Speed = { 0.5, 1.5 }, Size = { 2, 5 }, Alpha = { 0.65, 1 }, Light = 0 },
	{ T = "emit", Tex = "Chispa-punto", C = "B", Where = "around", Rate = 8, Life = { 1, 1.6 }, Speed = { 1, 2.5 }, Size = { 0.8, 0 } },
	{ T = "hl", Fill = 0.86, Out = 0.4 },
	{ T = "light", Range = 8, Bright = 0.8 },
}
S.Tormenta = {
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 10, Alpha = 0.78, Pulse = 0.15 },
	{ T = "ground", Tex = "Anillo-energia", C = "A", Size = 8, Spin = 2.2, Alpha = 0.35 },
	{ T = "ground", Tex = "Anillo-energia", C = "B", Size = 5.6, Spin = -3.2, Alpha = 0.4 },
	{ T = "arcs", N = 6 },
	{ T = "emit", Tex = { "Rayo-A", "Rayo-B", "Rayo-C" }, C = "WA", Where = "limbs", Rate = 14, Life = { 0.12, 0.22 }, Speed = { 0, 1 }, Size = { 3.2, 4.5 }, Spin = 180, Alpha = { 0, 0.6 } },
	{ T = "emit", Tex = "Chispa-punto", C = "AB", Where = "root", Rate = 40, Life = { 0.2, 0.5 }, Speed = { 8, 16 }, Spread = 180, Size = { 0.9, 0 }, Alpha = { 0, 1 } },
	{ T = "hl", Fill = 0.8, Out = 0.25 },
	{ T = "light", Range = 14, Bright = 2, Flicker = 1 },
	{ T = "bloom" },
}
S.Cristal = {
	{ T = "glow", Tex = "Brillo-suave", C = "rainbow", Size = 10, Alpha = 0.8, Pulse = 0.08, Rainbow = true },
	{ T = "ground", Tex = "Rayos-sol", C = "rainbow", Size = 10, Spin = 0.6, Alpha = 0.45, Rainbow = true },
	{ T = "orbit", Kind = "shard", Tex = "Cristal-A", N = 5, Radius = 4, Speed = 1.3, Size = 2.2, C = "rainbow", Rainbow = true, Tilts = TILT3 },
	{ T = "orbit", Kind = "shard", Tex = "Cristal-B", N = 4, Radius = 5, Speed = -1.1, Size = 1.8, C = "rainbow", Rainbow = true, Tilts = TILT3 },
	{ T = "emit", Tex = "Destello-4-puntas", C = "rainbow", Where = "around", Rate = 18, Life = { 0.8, 1.4 }, Speed = { 0, 1 }, Size = { 1.6, 0 } },
	{ T = "emit", Tex = "Destello-lente", C = "rainbow", Where = "around", Rate = 2, Life = { 1, 1.6 }, Speed = { 0, 0.3 }, Size = { 4, 0 } },
	{ T = "hl", Fill = 0.8, Out = 0.2, Rainbow = true },
	{ T = "light", Range = 12, Bright = 1.2 },
	{ T = "bloom" },
}
S.Vacio = {
	{ T = "ground", Tex = "Remolino", C = "B", Size = 10, Spin = -1.2, Alpha = 0.35 },
	{ T = "ground", Tex = "Anillo-runas", C = "A", Size = 7.5, Spin = 0.6, Alpha = 0.5 },
	{ T = "emit", Tex = { "Humo-A", "Humo-B" }, C = "dark", Where = "root", Rate = 14, Life = { 1.4, 2.2 }, Speed = { 1.5, 3.5 }, Spread = 60, Size = { 2.5, 6 }, Dir = "Top", Alpha = { 0.35, 1 }, Light = 0 },
	{ T = "orbit", Kind = "eye", Tex = "Ojo-vacio", N = 3, Radius = 3.6, Speed = 0.9, Size = 2, C = "A", Tilts = TILT3 },
	{ T = "emit", Tex = "Chispa-punto", C = "A", Where = "around", Rate = 10, Life = { 1, 1.6 }, Speed = { 0.5, 1.5 }, Size = { 0.8, 0 } },
	{ T = "hl", Fill = 0.55, Out = 0.15 },
	{ T = "light", Range = 10, Bright = 0.9 },
}
S.Orbita = {
	{ T = "ground", Tex = "Galaxia-A", C = "W", Size = 11, Spin = 0.5, Alpha = 0.15 },
	{ T = "ground", Tex = "Anillo-runas", C = "B", Size = 7.4, Spin = -1.6, Alpha = 0.5 },
	{ T = "glow", Tex = "Brillo-suave", C = "B", Size = 10, Alpha = 0.8, Pulse = 0.08 },
	{ T = "orbit", Kind = "orb", N = 6, Radius = 4.2, Speed = 1.7, Size = 0.8, Trail = true, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = "Destello-4-puntas", C = "AB", Where = "around", Rate = 14, Life = { 1.4, 2.2 }, Speed = { 0.5, 1.5 }, Size = { 1.2, 0 } },
	{ T = "hl", Fill = 0.84, Out = 0.3 },
	{ T = "light", Range = 12, Bright = 1.3 },
}
S.Cosmos = {
	{ T = "back", Tex = "Galaxia-B", C = "W", Size = 8, Spin = 0.4, Alpha = 0.1, Y = 0.4 },
	{ T = "ground", Tex = "Galaxia-A", C = "W", Size = 13, Spin = 0.35, Alpha = 0.1 },
	{ T = "ground", Tex = "Galaxia-B", C = "W", Size = 10, Spin = -0.6, Alpha = 0.3, Y = 0.5, Tilt = Vector3.new(0.5, 0, 0.3) },
	{ T = "orbit", Kind = "orb", N = 5, Radius = 4.6, Speed = 1.3, Size = 0.6, Trail = true, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = "Destello-4-puntas", C = "WB", Where = "around", Rate = 22, Life = { 1, 1.8 }, Speed = { 0, 1 }, Size = { 0.9, 0 } },
	{ T = "emit", Tex = "Chispa-punto", C = "AB", Where = "around", Rate = 18, Life = { 1.2, 2 }, Speed = { 0.5, 1.5 }, Size = { 0.5, 0 } },
	{ T = "hl", Fill = 0.6, Out = 0.2 },
	{ T = "light", Range = 14, Bright = 1.4 },
	{ T = "bloom" },
}
S.Serafin = {
	{ T = "back", Tex = "Rayos-sol", C = "A", Size = 11, Spin = 0.25, Alpha = 0.25, Y = 0.4 },
	{ T = "wings", Tex = { "Pluma-A", "Pluma-B" }, C = "WA", Count = 6, Scale = 1.1 },
	{ T = "ground", Tex = "Halo-corona", C = "A", Size = 3.4, Spin = 2.4, Y = 6.4, Alpha = 0.18 },
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 9, Spin = 0.5, Alpha = 0.5 },
	{ T = "emit", Tex = "Pluma-B", C = "WA", Where = "head", Rate = 5, Life = { 2.5, 3.5 }, Speed = { 0.5, 1.2 }, Size = { 0.9, 0.9 }, Dir = "Bottom", Accel = Vector3.new(0, -0.6, 0), Spin = 70, Alpha = { 0.1, 1 } },
	{ T = "emit", Tex = "Destello-4-puntas", C = "WA", Where = "around", Rate = 14, Life = { 1.2, 2 }, Speed = { 0, 1 }, Size = { 1.4, 0 } },
	{ T = "hl", Fill = 0.78, Out = 0.15 },
	{ T = "light", Range = 16, Bright = 1.6 },
	{ T = "bloom" },
}
S.Corona = {
	{ T = "pillar", C = "A" },
	{ T = "back", Tex = "Rayos-sol", C = "A", Size = 14, Spin = 0.3, Alpha = 0.2, Y = 0.5 },
	{ T = "wings", Tex = { "Pluma-A", "Pluma-B" }, C = "AB", Count = 7, Scale = 1.3 },
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 11, Spin = 0.5, Alpha = 0.4 },
	{ T = "ground", Tex = "Anillo-runas", C = "B", Size = 7, Spin = -1.2, Alpha = 0.45 },
	{ T = "ground", Tex = "Halo-corona", C = "A", Size = 3.6, Spin = 2.4, Y = 6.4, Alpha = 0.16 },
	{ T = "orbit", Kind = "orb", N = 10, Radius = 4.3, Speed = -1.3, Size = 0.7, Trail = true, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = { "Llama-A", "Llama-C" }, C = "AB", Where = "feet", Rate = 18, Life = { 0.9, 1.5 }, Speed = { 2, 5 }, Spread = 30, Size = { 3, 0.4 }, Accel = Vector3.new(0, 5, 0), Alpha = { 0.4, 1 } },
	{ T = "emit", Tex = "Destello-4-puntas", C = "WA", Where = "around", Rate = 20, Life = { 1.2, 2 }, Speed = { 0.5, 2 }, Size = { 1.5, 0 } },
	{ T = "emit", Tex = "Destello-lente", C = "WA", Where = "around", Rate = 2, Life = { 1.2, 1.8 }, Speed = { 0, 0.4 }, Size = { 5, 0 } },
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 12, Alpha = 0.75, Pulse = 0.08 },
	{ T = "hl", Fill = 0.7, Out = 0.1 },
	{ T = "light", Range = 22, Bright = 2.6 },
	{ T = "bloom" },
}
-- por facción
S.KiDorado = {
	{ T = "back", Tex = "Pinchos-dorados", C = "A", Size = 12, Spin = 0.25, Alpha = 0.15, Y = 0.4 },
	{ T = "glow", Tex = "Brillo-suave", C = "A", Size = 10, Alpha = 0.7, Pulse = 0.12 },
	{ T = "ground", Tex = "Anillo-energia", C = "A", Size = 8, Spin = -1, Alpha = 0.4 },
	{ T = "ground", Tex = "Anillo-energia", C = "B", Size = 5.5, Spin = 2, Alpha = 0.4 },
	{ T = "emit", Tex = { "Llama-A", "Llama-B" }, C = "AB", Where = "feet", Rate = 30, Life = { 0.7, 1.2 }, Speed = { 5, 9 }, Spread = 12, Size = { 5, 1 }, Accel = Vector3.new(0, 10, 0), Alpha = { 0.3, 1 } },
	{ T = "emit", Tex = { "Rayo-A", "Rayo-B", "Rayo-C" }, C = "WA", Where = "limbs", Rate = 10, Life = { 0.1, 0.2 }, Speed = { 0, 1 }, Size = { 3, 4.5 }, Spin = 180, Alpha = { 0, 0.6 } },
	{ T = "hl", Fill = 0.7, Out = 0.1 },
	{ T = "light", Range = 16, Bright = 2, Flicker = 0.4 },
	{ T = "bloom" },
}
S.Hojas = {
	{ T = "ground", Tex = "Kunai-hoja-remolino", C = "A", Size = 10, Spin = 1.6, Alpha = 0.2 },
	{ T = "ground", Tex = "Kunai-hoja-remolino", C = "B", Size = 7, Spin = -2.2, Alpha = 0.25 },
	{ T = "orbit", Kind = "leaf", Tex = "Hoja", N = 9, Radius = 3.6, Speed = 2, Size = 1.6, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = "Hoja", C = "AB", Where = "around", Rate = 8, Life = { 1.5, 2.5 }, Speed = { 1, 3 }, Size = { 1, 0.6 }, Spin = 120, Light = 0.2, Alpha = { 0, 0.9 } },
	{ T = "emit", Tex = "Humo-A", C = "A", Where = "feet", Rate = 3, Life = { 1.5, 2.2 }, Speed = { 0.5, 1 }, Size = { 2, 4 }, Alpha = { 0.7, 1 }, Light = 0.1 },
	{ T = "hl", Fill = 0.86, Out = 0.3 },
	{ T = "light", Range = 10, Bright = 0.9 },
}
S.Marea = {
	{ T = "ground", Tex = "Remolino", C = "A", Size = 10, Spin = 1.2, Alpha = 0.3 },
	{ T = "ground", Tex = "Anillo-energia", C = "B", Size = 7, Spin = -1, Alpha = 0.4 },
	{ T = "orbit", Kind = "wave", Tex = "Ola-agua", N = 5, Radius = 3.8, Speed = 1.4, Size = 2.6, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = "Burbuja", C = "WA", Where = "feet", Rate = 12, Life = { 1.5, 2.5 }, Speed = { 2, 4 }, Size = { 0.8, 1.4 }, Dir = "Top", Alpha = { 0.3, 1 }, Light = 0.2 },
	{ T = "emit", Tex = "Humo-A", C = "W", Where = "feet", Rate = 4, Life = { 1.2, 2 }, Speed = { 0.5, 1.2 }, Size = { 2, 4 }, Alpha = { 0.7, 1 }, Light = 0.1 },
	{ T = "hl", Fill = 0.86, Out = 0.3 },
	{ T = "light", Range = 12, Bright = 1 },
}
S.Espectral = {
	{ T = "ground", Tex = "Circulo-magico", C = "A", Size = 10, Spin = 0.5, Alpha = 0.4 },
	{ T = "orbit", Kind = "butterfly", Tex = "Mariposa", N = 7, Radius = 3.8, Speed = 1, Size = 1.6, C = "AB", Tilts = TILT3 },
	{ T = "emit", Tex = "Humo-B", C = "WA", Where = "root", Rate = 8, Life = { 1.5, 2.2 }, Speed = { 1, 2.5 }, Spread = 50, Size = { 2, 5 }, Dir = "Top", Alpha = { 0.5, 1 }, Light = 0.3 },
	{ T = "emit", Tex = "Chispa-punto", C = "WB", Where = "around", Rate = 10, Life = { 1, 1.6 }, Speed = { 0.5, 1.5 }, Size = { 0.8, 0 } },
	{ T = "hl", Fill = 0.8, Out = 0.2 },
	{ T = "light", Range = 10, Bright = 1 },
}

return S
