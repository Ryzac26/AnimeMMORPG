--!strict
local Entry = {
	Version = "6.44",
	Date = "29 oct 2026",
	Title = "Interfaz por facción, retratos y jefe interactivo",
	Sections = {
		{
			Header = "Interfaz por facción",
			Items = {
				"Todos los marcos y ventanas tienen ahora el estilo de tu facción: fondo con degradado y marca de agua, borde animado y detalles propios (llamas y rayos de ki, hojas y pergaminos, olas y cuerda, almas y esquinas en ángulo).",
				"El borde pirata ahora es una cuerda fina con remaches dorados.",
				"El panel del jugador se rediseñó: retrato cuadrado con el fondo de tu facción y su kanji, nombre, personaje y rol, y barras de vida, energía y XP con borde de facción.",
				"Si cambias de facción o de rol, toda la interfaz se reconstruye sola con el estilo nuevo.",
			},
		},
		{
			Header = "Retratos",
			Items = {
				"El retrato muestra el busto 3D de tu personaje con el fondo y el marco de tu facción.",
			},
		},
		{
			Header = "Jefe mundial",
			Items = {
				"Ya se puede seleccionar haciendo clic en cualquier parte de su cuerpo y atacarlo.",
				"El alcance de los ataques y poderes se mide desde su superficie, no desde su centro, así los cuerpo a cuerpo también le llegan.",
			},
		},
		{
			Header = "Correcciones",
			Items = {
				"Arreglados los errores de Boost y Auto-farm que aparecían al entrar (los canales de comunicación ahora se crean al iniciar el servidor).",
				"Arreglado el error de carga cruzada entre las recompensas y los boosts.",
			},
		},
	},
}

return Entry
