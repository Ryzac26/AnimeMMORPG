--!strict
local Entry = {
	Version = "6.42",
	Date = "28 oct 2026",
	Title = "Piedras Metin, boosts y auto-farm más inteligente",
	Sections = {
		{
			Header = "Piedras Metin en la Arena",
			Items = {
				"Mientras la Arena está abierta aparecen piedras Metin en el anillo exterior.",
				"Hay 5 rarezas: Común, Poco común, Raro, Épico y Legendario. Mientras más rara, más vida tiene y más difíciles son sus monstruos.",
				"Al bajarle la vida a la piedra salen oleadas de monstruos: Común 2, Poco común 3, Raro 4, Épico 5 y Legendario 6 (los más raros traen jefes).",
				"Al destruirla ganas experiencia según el daño que hiciste. El botín llegará en una próxima actualización.",
			},
		},
		{
			Header = "Boost activo",
			Items = {
				"Nuevo cuadro \"BOOST ACTIVO\" bajo los carteles de evento y arena: lista todos tus boosts y se puede minimizar.",
				"Hermandad de franja: +4% de XP por cada aliado de tu facción en tu misma franja (máximo +12%).",
			},
		},
		{
			Header = "Auto-farm",
			Items = {
				"Perseguir ve mucho más lejos, va siempre al grupo más cercano y no se queda parado: si un objetivo no recibe daño se acerca más o lo descarta.",
				"Los personajes cuerpo a cuerpo (como Jinbe) se pegan al enemigo y siguen buscando el siguiente grupo.",
				"Esquiva las zonas rojas de los poderes en área y en línea de los enemigos.",
				"Ya no se apaga con vida o energía bajas: se cura antes (con 75% de vida), usa defensas y puede usar áreas aunque haya un solo rival.",
				"Nueva sección de pociones: dos cuadros (vida y energía) con el % al que se toman. Se detectan solas del inventario.",
			},
		},
		{
			Header = "Combate",
			Items = {
				"Los cuerpos de los enemigos ya no hacen rebotar al jugador: al morir se vuelven transparentes e intangibles.",
			},
		},
	},
}

return Entry
