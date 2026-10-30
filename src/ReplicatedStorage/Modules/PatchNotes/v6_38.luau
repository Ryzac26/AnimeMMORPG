--!strict
-- ModuleScript hijo de PatchNotes (una versión). Duplica este archivo para la siguiente versión y cambia el nombre (ej. v6_41).
local Entry = {
	Version = "6.38",
	Date = "28 oct 2026",
	Title = "Shinigami, nuevos poderes y mundo más justo",
	Sections = {
		{
			Header = "Nueva facción: Corte Shinigami (Bleach)",
			Items = {
				"Territorio propio al sur de la Arena, con puente, cartel y emblema giratorio (máscara Hollow y katanas).",
				"6 personajes: Chad (Tanque), Ichigo (Guerrero), Yoruichi (Asesino), Uryu (Tirador), Hitsugaya (Mago) y Orihime (Curadora). Recurso: REIATSU.",
				"16 enemigos nuevos con jefes: Grand Fisher, Grimmjow, Ulquiorra y Aizen.",
			},
		},
		{
			Header = "Poderes",
			Items = {
				"Cada personaje tiene ahora 6 poderes (teclas 1 a 6).",
				"Los curadores (Bulma, Sakura, Chopper, Orihime) ya tienen poderes de daño.",
			},
		},
		{
			Header = "Pasivas por rol (3 cada una, con porcentajes bajos)",
			Items = {
				"Tanque: Piel de acero, Presencia (los enemigos cercanos lo prefieren a él) y Voluntad (sobrevive a un golpe mortal cada 120 s).",
				"Guerrero: Sed de combate, Segundo aire y Furia.",
				"Asesino: Puñalada por la espalda, Evasión y Remate.",
				"Tirador: Ojo de halcón, Disparo encadenado y Retirada.",
				"Mago: Maestría elemental, Flujo de energía y Eco.",
				"Curador: Aura de vida, Sobrecura y Última esperanza.",
				"Gaara, Jinbe y Chad tienen un nuevo poder de provocación (poder 5) para mantener a los enemigos sobre ellos.",
			},
		},
		{
			Header = "Enemigos y mapa",
			Items = {
				"Cada enemigo nace en la zona de su nivel dentro de la franja: los más débiles cerca de la entrada y los más fuertes al fondo.",
				"Ya no nacen pegados a los bordes, así que no se caen del mapa.",
				"En las franjas 3 y 4 los grupos están mucho más separados: puedes pelear y moverte sin que te agarre un segundo grupo.",
				"El emblema pirata del cartel gira de izquierda a derecha.",
				"Jinbe ya no aparece bajo el mapa.",
			},
		},
	},
}

return Entry
