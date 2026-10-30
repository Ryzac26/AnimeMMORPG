--!strict
local Entry = {
	Version = "6.43",
	Date = "29 oct 2026",
	Title = "Jefe mundial, grupos, Auto-Metin y muros con arcos",
	Sections = {
		{
			Header = "Jefe mundial",
			Items = {
				"Cada 6 horas despierta el Titán de la Arena en el centro de la Arena: una estatua gigante con un rayo de luz que se ve desde los 4 fuertes.",
				"Al despertar se abren los puentes para que lleguen las 4 facciones.",
				"Ataques: círculos rojos que aplastan, una onda enorme (hay que salir del círculo), súbditos invocados y furia con menos de 30% de vida.",
				"La XP se reparte según el daño que hiciste. El botín llegará en una próxima actualización.",
			},
		},
		{
			Header = "Mapa",
			Items = {
				"Entre cada franja hay un muro con 3 arcos gigantes para pasar a la siguiente.",
				"Cada arco tiene un holograma con el nombre de la franja y sus niveles (Franja 2, 3 y 4).",
			},
		},
		{
			Header = "Combate",
			Items = {
				"Ya no existe el daño entre jugadores de la misma facción, ni en PvE ni en PvP.",
				"Nuevo poder en la tecla 7: Primeros Auxilios, una curación propia cada 25 s. Cura según tu rol: Curador 20%, Mago 9%, Tirador 7%, Asesino 6%, Guerrero 5% y Tanque 4% de tu vida máxima. El Curador además cura a los aliados cercanos.",
				"Los monstruos pierden de vista a quien entra a la zona segura: se curan y vuelven a su lugar.",
				"El auto-ataque ya no se pausa con Q: siempre sigue al objetivo que marcaste.",
			},
		},
		{
			Header = "Auto-farm",
			Items = {
				"Arreglado el auto-farm que se quedaba parado: antes el servidor giraba al personaje al atacar y lo hacía rebotar hacia atrás. Además, si no avanza en 3 s cambia de meta.",
				"Nuevo modo Metin: ataca la piedra y se enfoca en sus oleadas. Funciona también dentro de la Arena y se apaga solo si otra facción golpea la piedra.",
				"Nuevo interruptor AUTO CURAR ALIADOS: detecta aliados o compañeros de grupo con menos de 70% de vida y los cura solo. El Curador camina hacia ellos si están lejos.",
				"Usa Primeros Auxilios cuando tu vida baja de 60%.",
				"La sección de pociones se puede minimizar y expandir.",
			},
		},
		{
			Header = "Grupo (party)",
			Items = {
				"Panel de grupo a la izquierda con la vida y la energía en % de cada miembro. Hasta 5 jugadores de la misma facción.",
				"Botón + Invitar (o tecla P) para invitar; la invitación llega con Aceptar / Rechazar.",
			},
		},
		{
			Header = "Perfil (C)",
			Items = {
				"Ahora muestra la descripción del personaje, sus 3 pasivas con sus porcentajes y el poder 7.",
			},
		},
	},
}

return Entry
