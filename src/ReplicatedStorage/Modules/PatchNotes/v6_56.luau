--!strict
local Entry = {
	Version = "6.56",
	Date = "31 oct 2026",
	Title = "Coliseo único, gradas y santuarios",
	Sections = {
		{
			Header = "Arena",
			Items = {
				"La arena queda con un solo diseño: el Coliseo de las Cuatro Naciones. Se quitaron las rocas, las Ruinas y la Isla flotante.",
				"/arena ahora deja la arena abierta 1 hora.",
				"Las vidas de arena suben de 3 a 5.",
			},
		},
		{
			Header = "Gradas",
			Items = {
				"Cada facción tiene su grada con muros separadores: no se puede pasar a la de otra facción.",
				"Entradas: portal en el puente, portal en tu campamento y, desde la grada, 'Bajar a la arena' o 'Volver a la ciudad'.",
				"Si pierdes las 5 vidas vas directo a tu grada y no puedes entrar a la arena hasta el próximo evento.",
			},
		},
		{
			Header = "Santuarios",
			Items = {
				"Nuevo panel con el % de captura de cada santuario, su dueño y tus bonus activos.",
				"Al capturar uno aparece una tarjeta con el bonus ganado.",
			},
		},
	},
}

return Entry
