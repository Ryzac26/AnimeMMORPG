--!strict
local Entry = {
	Version = "6.45",
	Date = "30 oct 2026",
	Title = "Auto-Jefe y paneles con movimiento",
	Sections = {
		{
			Header = "Auto-farm: modo Jefe",
			Items = {
				"Nuevo modo Jefe: ataca solo al jefe mundial; si salen súbditos se enfoca en ellos y después vuelve al jefe.",
				"Se apaga solo si hay jugadores de otra facción cerca, si uno te ataca o si el jefe ya no está (el PvP es siempre a mano).",
				"Arreglado: el modo Metin ahora ve piedras lejanas (antes solo las que estaban muy cerca).",
			},
		},
		{
			Header = "Jefe mundial",
			Items = {
				"Arreglada la maqueta: ahora sube del piso y se ve en el centro de la Arena.",
			},
		},
		{
			Header = "Interfaz",
			Items = {
				"Los paneles tienen fondo animado de tu facción detrás de las barras: luz inferior, destello que cruza y llamas, olas o partículas.",
				"Las barras de vida, energía y XP tienen rayas que avanzan.",
				"La cuerda pirata es más fina y detallada.",
			},
		},
	},
}

return Entry
