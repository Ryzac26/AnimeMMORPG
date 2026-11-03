--!strict
local Entry = {
	Version = "6.64",
	Date = "2 nov 2026",
	Title = "Llaves de cofre y límites diarios",
	Sections = {
		{
			Header = "Cofres con llave",
			Items = {
				"Los cofres del mapa ahora están sellados: se abren con una Llave de Cofre de su franja.",
				"Las llaves caen de los monstruos de la franja (con más probabilidad de mini jefes y jefes). Caen hasta 3 por día en cada franja y caducan al terminar el día.",
				"Las llaves no se venden ni se intercambian.",
			},
		},
		{
			Header = "Límites diarios por franja",
			Items = {
				"Cada franja cuenta por separado. Por día: 3 llaves de cofre, 2 desafíos del altar con premio y 3 mini jefes con premio.",
				"Si agotas los mini jefes de una franja no puedes atacarlo y no da nada.",
				"Si alguien de tu grupo tiene un desafío en curso, no puedes iniciar otro hasta que termine.",
			},
		},
		{
			Header = "Campamentos y ciudad",
			Items = {
				"Dentro del campamento ya no se puede atacar.",
				"La Franja 1 no tiene campamento: la ciudad ahora regenera vida y energía rápido.",
				"La olla del campamento abre la ventana del Alquimista (pociones por cantidad o Máx).",
			},
		},
	},
}

return Entry
