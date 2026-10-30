--!strict
local Entry = {
	Version = "6.47",
	Date = "30 oct 2026",
	Title = "Jefe estable, auto-curar en la Arena y grupo mejorado",
	Sections = {
		{
			Header = "Jefe mundial",
			Items = {
				"Arreglado: el jefe nacía con 100 de vida en vez de su vida completa y moría (desaparecía) al primer golpe. Ahora aparece con toda su vida y se queda en su lugar hasta que lo derrotes.",
				"La barra de objetivo muestra el nombre del jefe.",
			},
		},
		{
			Header = "Objetivo",
			Items = {
				"La ventana de objetivo tiene una X para quitar el objetivo y detener el auto-ataque hacia él.",
			},
		},
		{
			Header = "Auto-farm",
			Items = {
				"AUTO CURAR ALIADOS ahora funciona siempre, también con el Auto-farm apagado y dentro de la Arena / zona PvP. Si un aliado de tu facción o grupo baja del umbral y está dentro del área de tu poder de curación, lo cura solo.",
				"Auto-Metin: que un compañero de tu facción golpee la piedra ya no lo apaga. Se apaga si hay jugadores de otra facción cerca o si alguno golpea la piedra.",
				"Con Auto-farm activo, el Curador se acerca a los aliados heridos hasta quedar dentro del área de su curación.",
			},
		},
		{
			Header = "Grupo",
			Items = {
				"+ Invitar muestra a todos los jugadores conectados y se actualiza sola. Los de tu facción se pueden invitar; los de otra facción aparecen apagados.",
			},
		},
	},
}

return Entry
