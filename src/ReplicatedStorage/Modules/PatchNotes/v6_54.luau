--!strict
local Entry = {
	Version = "6.54",
	Date = "31 oct 2026",
	Title = "Nueva Arena: campamentos, santuarios y temas",
	Sections = {
		{
			Header = "Arena Central",
			Items = {
				"Cada facción tiene su campamento detrás de su puente, con una bandera y un cristal que cura vida y energía a los de su facción.",
				"Las 8 piedras Metin ahora están sobre altares con antorchas, y la plataforma del jefe tiene anillos y obeliscos.",
				"La Arena cambia de aspecto cada vez que aparece un jefe: Coliseo de las Cuatro Naciones, Ruinas del Torneo e Isla Flotante con cascadas.",
			},
		},
		{
			Header = "Santuarios de poder",
			Items = {
				"Cuatro santuarios en las esquinas de la arena. Quédate cerca 8 segundos para capturarlos; si hay dos facciones a la vez, queda disputado.",
				"Fuerza: +8% de daño. Vigor: +10% de vida máxima. Aliento: +40% de regeneración de energía. Fortuna: +15% de XP.",
				"Los bonus los recibe la facción dueña mientras esté dentro de la arena con el evento abierto.",
			},
		},
		{
			Header = "Pruebas",
			Items = {
				"Nuevo comando /tema 1, 2 o 3 para cambiar el tema de la arena. También cambia con /boss.",
			},
		},
	},
}

return Entry
