--!strict
local Entry = {
	Version = "6.80",
	Date = "8 nov 2026",
	Title = "Atributos y rebalanceo de clases",
	Sections = {
		{
			Header = "Atributos de rol",
			Items = {
				"Cada clase tiene ahora 5 atributos: Fuerza, Destreza, Inteligencia, Vitalidad y Espíritu. Los ves en tu ficha de personaje, con ★ en el principal.",
				"Fuerza: daño de Tanque y Guerrero. Destreza: daño de Asesino y Tirador, además de crítico, velocidad de ataque y esquiva. Inteligencia: daño de Mago y Curador y potencia de curación.",
				"Vitalidad: vida máxima y defensa (antes la defensa de la clase no hacía nada). Espíritu: energía máxima y regeneración.",
			},
		},
		{
			Header = "Rebalanceo",
			Items = {
				"Tanque: mucha más vida y reducción de daño; su golpe básico es más fuerte para no esperar una eternidad al farmear.",
				"Curador: golpe básico más fuerte, se cura mejor a sí mismo y sus curas escalan con Inteligencia.",
				"Asesino: más crítico, velocidad de ataque y esquiva. Tirador: crítico y esquiva. Mago: más daño y más regeneración de energía.",
				"Los monstruos de franjas altas pegan algo menos (crecimiento de su golpe 1,0485 → 1,045): mismo desafío, menos frustración.",
			},
		},
	},
}

return Entry
