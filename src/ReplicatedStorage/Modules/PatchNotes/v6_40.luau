--!strict
-- ModuleScript hijo de PatchNotes (una versión). Duplica este archivo para la siguiente versión y cambia el nombre (ej. v6_41).
local Entry = {
	Version = "6.40",
	Date = "28 oct 2026",
	Title = "Auto-farm renovado",
	Sections = {
		{
			Header = "Auto-farm",
			Items = {
				"Se eliminó el modo Quieto.",
				"Perseguir ahora farmea la franja donde lo activas: solo camina y mata enemigos de esa franja, patrulla cuando no hay enemigos y no se sale de sus bordes.",
				"Rodea obstáculos (árboles, rocas) para no atascarse.",
				"Semi se mantiene: tú caminas y los poderes (ahora hasta el 6) salen solos.",
			},
		},
	},
}

return Entry
