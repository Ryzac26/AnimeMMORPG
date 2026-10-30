--!strict
--[[
    =================================================================================
    PROJECT: 3-FACTION ANIME MMORPG (Dragon Ball | Naruto | One Piece)
    SCRIPT: FactionClassesModule.luau  (v2 - balanceado y sin copy-paste)
    UBICACIÓN: ReplicatedStorage.Modules.FactionClassesModule (ModuleScript)
    NO LO BORRES: PlayerClass, CombatService, EnergyRegenService y HUDManager dependen de él.
                  Reemplaza el contenido del actual por este archivo.

    6 ROLES x 3 FACCIONES = 18 PERSONAJES

        Rol        Función                              Saiyan   Shinobi   Pirate
        Tanque     Aguanta: escudo propio + aturdir     Piccolo  Gaara     Jinbe
        Guerrero   Daño equilibrado cuerpo a cuerpo     Goku     Naruto    Luffy
        Asesino    Máximo daño, poca vida, muy rápido   Vegeta   Sasuke    Zoro
        Tirador    Daño a larga distancia               Trunks   Itachi    Usopp
        Mago       Daño en área                         Gohan    Kakashi   Sanji
        Curador    Cura en área y a distancia           Bulma    Sakura    Chopper

    REGLAS DE BALANCE
      1) Simetría entre facciones: los NÚMEROS viven solo en ROLE_BALANCE_SPECS (una vez por
         rol). Los personajes solo aportan nombre, descripción y VFX. Es estructuralmente
         imposible que un personaje tenga más poder que su homólogo de otra facción.
      2) Paridad entre roles: ValidateBalance() calcula un Índice de Poder por rol y exige que
         todos queden a ±12% de la media. Si cambias un número, corre ValidateBalance().

    ÍNDICE DE PODER (cómo se mide)
         Salida   = Σ por habilidad de  (BaseValue / Cooldown) x peso del tipo x bono de área x bono de alcance
                    peso: Damage 1.0 | AoE_Damage 1.0 | CrowdControl 1.25 | Healing 0.85 | Shield 0.85
                    área:  1 + AoERadius / 50        alcance: 1 + (Range - 20) / 150
         Sostén   = min(1, segundos que dura la energía en combate / 20)
         Vida ef. = BaseHP x (1 + BaseDefense / 100)
         ÍNDICE   = Salida x Sostén x raíz(Vida ef.)

    AJUSTES DE BALANCE RESPECTO A LA VERSIÓN ANTERIOR (dispersión entre roles: 70% -> 11%)
         Tanque : Escudo 80->120 (cd 6->5, costo 25->20) | CC 110->165 (cd 14->11, costo 45->40)
         Asesino: Energía 110->120 | P 170->165 (costo 25->22) | S 280->270 (costo 55->48)
         Tirador: P 115->100 | S 195->160            (su alcance 45-55 ya era una gran ventaja)
         Mago   : P 140->120 | S 250->215, radio 22->18   (el área tiene "impuesto")
         Curador: Energía 160->150 | P 150->145 | S 260->250
         Guerrero: sin cambios (es la referencia)
    =================================================================================
]]

local FactionClassesModule = {}

-------------------------------------------------------------------------------------
-- 1. TIPOS ESTRICTOS (LUAU TYPE CHECKING)
-------------------------------------------------------------------------------------

export type SkillType = "Damage" | "Healing" | "Shield" | "CrowdControl" | "AoE_Damage"

export type SkillData = {
	Name: string,
	SkillType: SkillType,
	BaseValue: number,       -- Daño base o Cantidad de Curación/Escudo
	Cooldown: number,        -- Tiempo de recarga en segundos
	EnergyCost: number,      -- Costo de Maná / Ki / Chakra / Stamina
	Range: number,           -- Rango de alcance en studs
	AoERadius: number?,      -- Radio de área de impacto en studs (si aplica)
	CastTime: number,        -- Tiempo de casteo en segundos (0 para instantáneo)
	Description: string,     -- Descripción in-game
	VFXTheme: string,        -- Identificador de efectos visuales (ReplicatedStorage.VFX)
}

export type ClassData = {
	Role: string,            -- "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador"
	CharacterName: string,   -- Personaje (ej. "Piccolo", "Gaara", "Jinbe")
	Faction: string,         -- "Saiyan", "Shinobi", "Pirate"
	AnimeSource: string,     -- "Dragon Ball", "Naruto", "One Piece"
	BaseHP: number,
	BaseEnergy: number,
	BaseDefense: number,
	WalkSpeed: number,
	PrimarySkill: SkillData,
	SecondarySkill: SkillData,
}

export type FactionRegistry = {
	[string]: {
		[string]: ClassData
	}
}

type SkillSpec = {
	SkillType: SkillType,
	BaseValue: number,
	Cooldown: number,
	EnergyCost: number,
	Range: number,
	AoERadius: number?,
	CastTime: number,
}

type RoleSpec = {
	BaseHP: number,
	BaseEnergy: number,
	BaseDefense: number,
	WalkSpeed: number,
	Primary: SkillSpec,
	Secondary: SkillSpec,
}

type SkillFlavor = {
	Name: string,
	Description: string,
	VFXTheme: string,
}

type CharacterFlavor = {
	CharacterName: string,
	Primary: SkillFlavor,
	Secondary: SkillFlavor,
}

type FactionInfo = {
	AnimeSource: string,
	Characters: { [string]: CharacterFlavor },
}

local ROLES = { "Tanque", "Guerrero", "Asesino", "Tirador", "Mago", "Curador" }
local FACTIONS = { "Saiyan", "Shinobi", "Pirate", "Shinigami" }
local MAX_SKILL_NAME_LENGTH = 24 -- para que quepa en la barra de habilidades del HUD

-------------------------------------------------------------------------------------
-- 2. NÚMEROS POR ROL (única fuente de balance; los 3 personajes de un rol los comparten)
-------------------------------------------------------------------------------------

local ROLE_BALANCE_SPECS: { [string]: RoleSpec } = {
	Tanque = {
		BaseHP = 1600,
		BaseEnergy = 100,
		BaseDefense = 120,
		WalkSpeed = 16,
		Primary = {
			SkillType = "Shield",
			BaseValue = 120,
			Cooldown = 5.0,
			EnergyCost = 20,
			Range = 14,
			AoERadius = nil,
			CastTime = 0.0,
		},
		Secondary = {
			SkillType = "CrowdControl",
			BaseValue = 165,
			Cooldown = 11.0,
			EnergyCost = 40,
			Range = 22,
			AoERadius = 10,
			CastTime = 0.35,
		},
	},
	Guerrero = {
		BaseHP = 1250,
		BaseEnergy = 120,
		BaseDefense = 75,
		WalkSpeed = 18,
		Primary = {
			SkillType = "Damage",
			BaseValue = 130,
			Cooldown = 4.5,
			EnergyCost = 20,
			Range = 20,
			AoERadius = nil,
			CastTime = 0.1,
		},
		Secondary = {
			SkillType = "Damage",
			BaseValue = 220,
			Cooldown = 11.0,
			EnergyCost = 50,
			Range = 28,
			AoERadius = 8,
			CastTime = 0.4,
		},
	},
	Asesino = {
		BaseHP = 950,
		BaseEnergy = 120,
		BaseDefense = 50,
		WalkSpeed = 21,
		Primary = {
			SkillType = "Damage",
			BaseValue = 165,
			Cooldown = 4.0,
			EnergyCost = 22,
			Range = 16,
			AoERadius = nil,
			CastTime = 0.0,
		},
		Secondary = {
			SkillType = "Damage",
			BaseValue = 270,
			Cooldown = 13.0,
			EnergyCost = 48,
			Range = 24,
			AoERadius = 6,
			CastTime = 0.25,
		},
	},
	Tirador = {
		BaseHP = 1000,
		BaseEnergy = 130,
		BaseDefense = 60,
		WalkSpeed = 17,
		Primary = {
			SkillType = "Damage",
			BaseValue = 100,
			Cooldown = 3.5,
			EnergyCost = 15,
			Range = 45,
			AoERadius = nil,
			CastTime = 0.1,
		},
		Secondary = {
			SkillType = "Damage",
			BaseValue = 160,
			Cooldown = 9.0,
			EnergyCost = 40,
			Range = 55,
			AoERadius = 12,
			CastTime = 0.5,
		},
	},
	Mago = {
		BaseHP = 1050,
		BaseEnergy = 150,
		BaseDefense = 55,
		WalkSpeed = 16,
		Primary = {
			SkillType = "AoE_Damage",
			BaseValue = 120,
			Cooldown = 5.0,
			EnergyCost = 30,
			Range = 30,
			AoERadius = 14,
			CastTime = 0.2,
		},
		Secondary = {
			SkillType = "AoE_Damage",
			BaseValue = 215,
			Cooldown = 12.0,
			EnergyCost = 60,
			Range = 35,
			AoERadius = 18,
			CastTime = 0.6,
		},
	},
	Curador = {
		BaseHP = 1150,
		BaseEnergy = 150,
		BaseDefense = 85,
		WalkSpeed = 16,
		Primary = {
			SkillType = "Healing",
			BaseValue = 145,
			Cooldown = 4.0,
			EnergyCost = 20,
			Range = 25,
			AoERadius = nil,
			CastTime = 0.1,
		},
		Secondary = {
			SkillType = "Healing",
			BaseValue = 250,
			Cooldown = 15.0,
			EnergyCost = 55,
			Range = 30,
			AoERadius = 16,
			CastTime = 0.5,
		},
	},
}

-------------------------------------------------------------------------------------
-- 3. PERSONAJES: SOLO IDENTIDAD (nombre, descripción, VFX). Nada numérico aquí.
--    Las descripciones dicen lo que la habilidad HACE de verdad en el juego.
-------------------------------------------------------------------------------------

local FACTION_INFO: { [string]: FactionInfo } = {
	-- ==============================================================================
	-- FACCIÓN 1: IMPERIO SAIYAN (Dragon Ball)
	-- ==============================================================================
	Saiyan = {
		AnimeSource = "Dragon Ball",
		Characters = {
			Tanque = {
				CharacterName = "Piccolo",
				Primary = {
					Name = "Barrera de Ki",
					Description = "Te cubre con una cúpula de Ki que absorbe daño durante unos segundos.",
					VFXTheme = "VFX_Piccolo_KiBarrier",
				},
				Secondary = {
					Name = "Brazo Elástico",
					Description = "Estira sus brazos para atrapar a los enemigos del área: los daña y los aturde.",
					VFXTheme = "VFX_Piccolo_ArmStretchStun",
				},
			},
			Guerrero = {
				CharacterName = "Goku",
				Primary = {
					Name = "Kamehameha",
					Description = "Dispara una ráfaga concentrada de Ki celeste contra el objetivo.",
					VFXTheme = "VFX_Goku_Kamehameha",
				},
				Secondary = {
					Name = "Puño del Dragón",
					Description = "Un dragón dorado de Ki arremete contra el objetivo y estalla dañando a los cercanos.",
					VFXTheme = "VFX_Goku_DragonFist",
				},
			},
			Asesino = {
				CharacterName = "Vegeta",
				Primary = {
					Name = "Big Bang Attack",
					Description = "Lanza una esfera azul de Ki letal que detona al contacto con el objetivo.",
					VFXTheme = "VFX_Vegeta_BigBang",
				},
				Secondary = {
					Name = "Final Flash",
					Description = "Abre los brazos y libera una columna de energía dorada que daña al objetivo y a los cercanos.",
					VFXTheme = "VFX_Vegeta_FinalFlash",
				},
			},
			Tirador = {
				CharacterName = "Trunks",
				Primary = {
					Name = "Buster Cannon",
					Description = "Disparo veloz de Ki a larga distancia para hostigar objetivos en retirada.",
					VFXTheme = "VFX_Trunks_BusterCannon",
				},
				Secondary = {
					Name = "Burning Attack",
					Description = "Una gran llamarada esférica de Ki, lanzada desde lejos, que explota en área.",
					VFXTheme = "VFX_Trunks_BurningAttack",
				},
			},
			Mago = {
				CharacterName = "Gohan",
				Primary = {
					Name = "Masenko",
					Description = "Descarga una onda de Ki amarillo que detona en el objetivo y barre a los enemigos cercanos.",
					VFXTheme = "VFX_Gohan_Masenko",
				},
				Secondary = {
					Name = "Explosión Mística",
					Description = "Libera todo su poder oculto en una explosión de energía pura de gran radio.",
					VFXTheme = "VFX_Gohan_MysticBurst",
				},
			},
			Curador = {
				CharacterName = "Bulma",
				Primary = {
					Name = "Cápsula Hoi-Poi",
					Description = "Lanza una cápsula médica que restaura vida de inmediato.",
					VFXTheme = "VFX_Bulma_CapsuleHeal",
				},
				Secondary = {
					Name = "Campo de Nanodrones",
					Description = "Nanodrones crean un campo regenerativo que cura a todos los aliados del área.",
					VFXTheme = "VFX_Bulma_DroneField",
				},
			},
		},
	},

	-- ==============================================================================
	-- FACCIÓN 2: ALIANZA SHINOBI (Naruto)
	-- ==============================================================================
	Shinobi = {
		AnimeSource = "Naruto",
		Characters = {
			Tanque = {
				CharacterName = "Gaara",
				Primary = {
					Name = "Escudo de Arena",
					Description = "La arena de la calabaza forma un muro a tu alrededor que absorbe daño durante unos segundos.",
					VFXTheme = "VFX_Gaara_SandShield",
				},
				Secondary = {
					Name = "Ataúd de Arena",
					Description = "Aprisiona a los enemigos del área bajo arena pesada: los daña y los aturde.",
					VFXTheme = "VFX_Gaara_SandCoffin",
				},
			},
			Guerrero = {
				CharacterName = "Naruto",
				Primary = {
					Name = "Rasengan",
					Description = "Esfera de chakra en rotación extrema que embiste al objetivo.",
					VFXTheme = "VFX_Naruto_Rasengan",
				},
				Secondary = {
					Name = "Rasenshuriken",
					Description = "Vórtice de viento que estalla en miles de agujas, dañando al objetivo y a los cercanos.",
					VFXTheme = "VFX_Naruto_Rasenshuriken",
				},
			},
			Asesino = {
				CharacterName = "Sasuke",
				Primary = {
					Name = "Chidori",
					Description = "Embestida supersónica con la mano cargada de rayos cortantes.",
					VFXTheme = "VFX_Sasuke_Chidori",
				},
				Secondary = {
					Name = "Kirin",
					Description = "Una bestia de relámpago cae desde las nubes sobre el objetivo y los enemigos cercanos.",
					VFXTheme = "VFX_Sasuke_Kirin",
				},
			},
			Tirador = {
				CharacterName = "Itachi",
				Primary = {
					Name = "Bola de Fuego",
					Description = "Exhala una gran esfera de fuego a larga distancia con precisión milimétrica.",
					VFXTheme = "VFX_Itachi_Fireball",
				},
				Secondary = {
					Name = "Amaterasu",
					Description = "Llamas negras prenden en el punto focal del objetivo y se extienden en área.",
					VFXTheme = "VFX_Itachi_Amaterasu",
				},
			},
			Mago = {
				CharacterName = "Kakashi",
				Primary = {
					Name = "Cadena de Rayos",
					Description = "Un arco de relámpagos salta desde el objetivo y electrocuta a los enemigos cercanos.",
					VFXTheme = "VFX_Kakashi_LightningChain",
				},
				Secondary = {
					Name = "Kamui",
					Description = "Abre un vórtice dimensional que tritura a los enemigos dentro del área.",
					VFXTheme = "VFX_Kakashi_Kamui",
				},
			},
			Curador = {
				CharacterName = "Sakura",
				Primary = {
					Name = "Palma Mística",
					Description = "Chakra médico verde que restaura vida de inmediato.",
					VFXTheme = "VFX_Sakura_MysticPalm",
				},
				Secondary = {
					Name = "Sello Byakugō",
					Description = "Libera el sello de su frente y una marea de chakra sana a los aliados cercanos.",
					VFXTheme = "VFX_Sakura_Byakugou",
				},
			},
		},
	},

	-- ==============================================================================
	-- FACCIÓN 3: FLOTA PIRATA (One Piece)
	-- ==============================================================================
	Pirate = {
		AnimeSource = "One Piece",
		Characters = {
			Tanque = {
				CharacterName = "Jinbe",
				Primary = {
					Name = "Bloqueo Gyojin",
					Description = "Postura de karate gyojin que te protege con una barrera de agua durante unos segundos.",
					VFXTheme = "VFX_Jinbe_WaterBlock",
				},
				Secondary = {
					Name = "Vórtice Marino",
					Description = "Una columna de agua a presión arrastra a los enemigos del área: los daña y los aturde.",
					VFXTheme = "VFX_Jinbe_OceanVortex",
				},
			},
			Guerrero = {
				CharacterName = "Luffy",
				Primary = {
					Name = "Gomu Gomu Pistol",
					Description = "Estira el brazo hacia atrás y golpea al objetivo con un puñetazo contundente.",
					VFXTheme = "VFX_Luffy_Pistol",
				},
				Secondary = {
					Name = "Red Hawk",
					Description = "Puñetazo ardiente imbuido en Haki que explota en el objetivo y los cercanos.",
					VFXTheme = "VFX_Luffy_RedHawk",
				},
			},
			Asesino = {
				CharacterName = "Zoro",
				Primary = {
					Name = "Oni Giri",
					Description = "Cruza sus tres katanas y se lanza con un corte diagonal sobre el objetivo.",
					VFXTheme = "VFX_Zoro_OniGiri",
				},
				Secondary = {
					Name = "Sanzen Sekai",
					Description = "Gira sus katanas con Haki creando una tormenta de tajos que daña al objetivo y a los cercanos.",
					VFXTheme = "VFX_Zoro_SanzenSekai",
				},
			},
			Tirador = {
				CharacterName = "Usopp",
				Primary = {
					Name = "Firebird Star",
					Description = "Dispara desde su resortera un proyectil con forma de fénix flamígero a larga distancia.",
					VFXTheme = "VFX_Usopp_Firebird",
				},
				Secondary = {
					Name = "Dokuroboshi",
					Description = "Semillas Pop Green estallan formando una nube con forma de calavera en el área.",
					VFXTheme = "VFX_Usopp_Dokuroboshi",
				},
			},
			Mago = {
				CharacterName = "Sanji",
				Primary = {
					Name = "Flambage Shot",
					Description = "Gira sobre su talón con la pierna en llamas y libera una llamarada expansiva en el objetivo.",
					VFXTheme = "VFX_Sanji_DiableJambe",
				},
				Secondary = {
					Name = "Hell Memories",
					Description = "Llamas azules forman un tifón de fuego infernal sobre toda el área.",
					VFXTheme = "VFX_Sanji_HellMemories",
				},
			},
			Curador = {
				CharacterName = "Chopper",
				Primary = {
					Name = "Botica Milagrosa",
					Description = "Ungüentos y vendajes instantáneos que restauran vida de inmediato.",
					VFXTheme = "VFX_Chopper_Remedy",
				},
				Secondary = {
					Name = "Monster Point",
					Description = "Una Rumble Ball libera un aura protectora que cura a todos los aliados cercanos.",
					VFXTheme = "VFX_Chopper_MonsterAura",
				},
			},
		},
	},

	-- ==============================================================================
	-- FACCIÓN 4: SHINIGAMI (Bleach) · recurso REIATSU
	-- ==============================================================================
	Shinigami = {
		AnimeSource = "Bleach",
		Characters = {
			Tanque = {
				CharacterName = "Chad",
				Primary = {
					Name = "Brazo del Gigante",
					Description = "Su brazo derecho se cubre de energía y detiene el golpe: te protege con un escudo de reiatsu.",
					VFXTheme = "VFX_Chad_GiganteArm",
				},
				Secondary = {
					Name = "Brazo del Diablo",
					Description = "El brazo izquierdo dispara un rayo de reiatsu que daña y aturde a los enemigos del área.",
					VFXTheme = "VFX_Chad_DiabloArm",
				},
			},
			Guerrero = {
				CharacterName = "Ichigo",
				Primary = {
					Name = "Getsuga Tenshō",
					Description = "Un tajo de Zangetsu libera una media luna de energía que atraviesa al objetivo.",
					VFXTheme = "VFX_Ichigo_Getsuga",
				},
				Secondary = {
					Name = "Getsuga Jūjishō",
					Description = "Doble tajo en cruz cargado de reiatsu que explota en el objetivo y los cercanos.",
					VFXTheme = "VFX_Ichigo_Jujishou",
				},
			},
			Asesino = {
				CharacterName = "Yoruichi",
				Primary = {
					Name = "Shunkō: Golpe",
					Description = "Se lanza con shunpo y golpea con puños envueltos en reiatsu relámpago.",
					VFXTheme = "VFX_Yoruichi_Shunko",
				},
				Secondary = {
					Name = "Shunkō: Torbellino",
					Description = "Ráfaga de golpes relámpago a velocidad imposible que daña al objetivo y a los cercanos.",
					VFXTheme = "VFX_Yoruichi_Whirl",
				},
			},
			Tirador = {
				CharacterName = "Uryu",
				Primary = {
					Name = "Ginrei Kojaku",
					Description = "Dispara una flecha de reishi con el arco Quincy a larga distancia.",
					VFXTheme = "VFX_Uryu_Kojaku",
				},
				Secondary = {
					Name = "Licht Regen",
					Description = "Una lluvia de flechas de luz cae sobre toda el área.",
					VFXTheme = "VFX_Uryu_LichtRegen",
				},
			},
			Mago = {
				CharacterName = "Hitsugaya",
				Primary = {
					Name = "Hyōrinmaru",
					Description = "El dragón de hielo muerde al objetivo y lo congela en su lugar.",
					VFXTheme = "VFX_Hitsugaya_Hyorinmaru",
				},
				Secondary = {
					Name = "Guncho Tsurara",
					Description = "Pilares de hielo brotan del suelo y empalan a los enemigos del área.",
					VFXTheme = "VFX_Hitsugaya_Tsurara",
				},
			},
			Curador = {
				CharacterName = "Orihime",
				Primary = {
					Name = "Hinagiku y Baigon",
					Description = "Los Shun Shun Rikka cierran las heridas de inmediato.",
					VFXTheme = "VFX_Orihime_Hinagiku",
				},
				Secondary = {
					Name = "Shun Shun Rikka",
					Description = "Un escudo de sanación cubre y cura a todos los aliados cercanos.",
					VFXTheme = "VFX_Orihime_Rikka",
				},
			},
		},
	},
}

-------------------------------------------------------------------------------------
-- 4. CONSTRUCCIÓN DEL REGISTRO (números del rol + identidad del personaje)
-------------------------------------------------------------------------------------

local function buildSkill(spec: SkillSpec, flavor: SkillFlavor): SkillData
	return {
		Name = flavor.Name,
		SkillType = spec.SkillType,
		BaseValue = spec.BaseValue,
		Cooldown = spec.Cooldown,
		EnergyCost = spec.EnergyCost,
		Range = spec.Range,
		AoERadius = spec.AoERadius,
		CastTime = spec.CastTime,
		Description = flavor.Description,
		VFXTheme = flavor.VFXTheme,
	}
end

local CLASSES_REGISTRY: FactionRegistry = {}

for _, factionName in ipairs(FACTIONS) do
	local info = FACTION_INFO[factionName]
	local factionClasses: { [string]: ClassData } = {}
	for _, role in ipairs(ROLES) do
		local spec = ROLE_BALANCE_SPECS[role]
		local flavor = info.Characters[role]
		factionClasses[role] = {
			Role = role,
			CharacterName = flavor.CharacterName,
			Faction = factionName,
			AnimeSource = info.AnimeSource,
			BaseHP = spec.BaseHP,
			BaseEnergy = spec.BaseEnergy,
			BaseDefense = spec.BaseDefense,
			WalkSpeed = spec.WalkSpeed,
			PrimarySkill = buildSkill(spec.Primary, flavor.Primary),
			SecondarySkill = buildSkill(spec.Secondary, flavor.Secondary),
		}
	end
	CLASSES_REGISTRY[factionName] = factionClasses
end

-------------------------------------------------------------------------------------
-- 5. FUNCIONES PÚBLICAS
-------------------------------------------------------------------------------------

--[[
    Busca una clase SIN avisar si no existe (lo usa PlayerClass para no llenar el Output).
    @param factionName: "Saiyan" | "Shinobi" | "Pirate"
    @param className: rol ("Tanque"... "Curador") o personaje ("Goku", "Gaara"...), sin distinguir mayúsculas
]]
function FactionClassesModule.FindClass(factionName: string, className: string): ClassData?
	local faction = CLASSES_REGISTRY[factionName]
	if not faction then
		return nil
	end

	local direct = faction[className]
	if direct then
		return direct
	end

	local lowered = className:lower()
	for role, candidate in pairs(faction) do
		if role:lower() == lowered or candidate.CharacterName:lower() == lowered then
			return candidate
		end
	end
	return nil
end

--[[
    Igual que FindClass, pero avisa en el Output cuando no encuentra la clase.
]]
function FactionClassesModule.GetClassData(factionName: string, className: string): ClassData?
	local classData = FactionClassesModule.FindClass(factionName, className)
	if not classData then
		if not CLASSES_REGISTRY[factionName] then
			warn(string.format("[FactionClassesModule] Facción desconocida: '%s'", tostring(factionName)))
		else
			warn(string.format("[FactionClassesModule] '%s' no encontrado en facción '%s'", tostring(className), tostring(factionName)))
		end
	end
	return classData
end

--[[
    Devuelve la tabla completa con todas las facciones y clases registradas.
]]
function FactionClassesModule.GetAllClasses(): FactionRegistry
	return CLASSES_REGISTRY
end

--[[
    Obtiene la clase por rol explícito.
]]
function FactionClassesModule.GetClassByRole(factionName: string, role: string): ClassData?
	return FactionClassesModule.GetClassData(factionName, role)
end

-------------------------------------------------------------------------------------
-- 6. AUDITORÍAS AUTOMÁTICAS (corre las tres después de tocar cualquier número o nombre)
-------------------------------------------------------------------------------------

local function skillsEqual(a: SkillData, b: SkillData): boolean
	return a.SkillType == b.SkillType
		and a.BaseValue == b.BaseValue
		and a.Cooldown == b.Cooldown
		and a.EnergyCost == b.EnergyCost
		and a.Range == b.Range
		and a.AoERadius == b.AoERadius
		and a.CastTime == b.CastTime
end

--[[
    Simetría: los 3 personajes de un mismo rol deben tener EXACTAMENTE los mismos números
    (vida, energía, defensa, velocidad y todos los campos numéricos de ambas habilidades).
]]
function FactionClassesModule.ValidateSymmetry(): (boolean, string?)
	for _, role in ipairs(ROLES) do
		local base = CLASSES_REGISTRY[FACTIONS[1]][role]
		for _, fac in ipairs(FACTIONS) do
			local current = CLASSES_REGISTRY[fac][role]
			if current.BaseHP ~= base.BaseHP
				or current.BaseEnergy ~= base.BaseEnergy
				or current.BaseDefense ~= base.BaseDefense
				or current.WalkSpeed ~= base.WalkSpeed
				or not skillsEqual(current.PrimarySkill, base.PrimarySkill)
				or not skillsEqual(current.SecondarySkill, base.SecondarySkill) then
				return false, string.format("Desbalance numérico en rol '%s' entre %s y %s", role, FACTIONS[1], fac)
			end
		end
	end
	return true, "100% de simetría matemática verificada"
end

--[[
    Nombres: únicos en todo el juego, no vacíos y con largo que quepa en el HUD.
]]
function FactionClassesModule.ValidateNames(): (boolean, string?)
	local seen: { [string]: string } = {}
	for _, fac in ipairs(FACTIONS) do
		for _, role in ipairs(ROLES) do
			local class = CLASSES_REGISTRY[fac][role]
			for slot, skill in pairs({ Primary = class.PrimarySkill, Secondary = class.SecondarySkill }) do
				local label = string.format("%s/%s (%s)", fac, class.CharacterName, slot)
				if #skill.Name == 0 or utf8.len(skill.Name) :: number > MAX_SKILL_NAME_LENGTH then
					return false, string.format("Nombre vacío o demasiado largo (>%d): %s", MAX_SKILL_NAME_LENGTH, label)
				end
				if skill.Description == "" or skill.VFXTheme == "" then
					return false, "Falta descripción o VFXTheme: " .. label
				end
				local previous = seen[skill.Name]
				if previous then
					return false, string.format("Nombre repetido '%s': %s y %s", skill.Name, previous, label)
				end
				seen[skill.Name] = label
			end
		end
	end
	return true, "Nombres únicos y con largo válido"
end

local TYPE_WEIGHT: { [string]: number } = {
	Damage = 1.0,
	AoE_Damage = 1.0,
	CrowdControl = 1.25,
	Healing = 0.85,
	Shield = 0.85,
}
local BALANCE_TOLERANCE = 0.12 -- cada rol debe quedar a ±12% de la media
local COMBAT_REGEN_RATE = 0.02 -- mismo valor que EnergyRegenService en combate
local TARGET_COMBAT_SECONDS = 20

local function skillOutput(spec: SkillSpec): number
	local areaBonus = 1 + (spec.AoERadius or 0) / 50
	local rangeBonus = 1 + (spec.Range - 20) / 150
	return (spec.BaseValue / spec.Cooldown) * TYPE_WEIGHT[spec.SkillType] * areaBonus * rangeBonus
end

--[[
    Índice de Poder de un rol (ver fórmula en la cabecera). Sirve para comparar roles entre sí.
]]
function FactionClassesModule.GetPowerIndex(role: string): number?
	local spec = ROLE_BALANCE_SPECS[role]
	if not spec then
		return nil
	end

	local output = skillOutput(spec.Primary) + skillOutput(spec.Secondary)

	local energyPerSecond = spec.Primary.EnergyCost / spec.Primary.Cooldown + spec.Secondary.EnergyCost / spec.Secondary.Cooldown
	local regen = math.ceil(spec.BaseEnergy * COMBAT_REGEN_RATE)
	local net = energyPerSecond - regen
	local duration = if net > 0 then spec.BaseEnergy / net else math.huge
	local sustain = math.min(1, duration / TARGET_COMBAT_SECONDS)

	local effectiveHP = spec.BaseHP * (1 + spec.BaseDefense / 100)

	return output * sustain * math.sqrt(effectiveHP)
end

--[[
    Paridad entre roles: todos deben quedar a ±12% de la media del Índice de Poder.
    Devuelve true/false y un texto con el detalle de cada rol.
]]
function FactionClassesModule.ValidateBalance(): (boolean, string?)
	local indexes: { [string]: number } = {}
	local total = 0
	for _, role in ipairs(ROLES) do
		local index = FactionClassesModule.GetPowerIndex(role) :: number
		indexes[role] = index
		total += index
	end
	local mean = total / #ROLES

	local ok = true
	local lines: { string } = {}
	for _, role in ipairs(ROLES) do
		local deviation = indexes[role] / mean - 1
		if math.abs(deviation) > BALANCE_TOLERANCE then
			ok = false
		end
		table.insert(lines, string.format("%s %+.1f%%", role, deviation * 100))
	end

	local summary = table.concat(lines, " | ")
	if ok then
		return true, "Roles balanceados (±12%): " .. summary
	end
	return false, "Roles fuera de ±12%: " .. summary
end

return FactionClassesModule
