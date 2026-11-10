--!strict
--[[
    AttackAnimator (ModuleScript) -> ServerScriptService.Services.AttackAnimator
    Decide QUÉ animación de ataque usa cada personaje y la "publica" con atributos del modelo; el CLIENTE
    (CharacterAnimClient) la dibuja fluida en todas las pantallas. También pone el arma equipada en la mano.
      Play(modelo, estilo, duración?, momentoDelGolpe?)   estilos: Slash Stab Punch Bow Cast Shoot Slam Power Throw
      StyleFor(jugador, aDistancia)  -> estilo según arma equipada (ranura Arma); sin arma, por facción/rol
      Atributos que escribe: AnimStyle, AnimAt, AnimLen, AnimStrike, AnimAlt
    Armas (ItemCatalog.Items[id].Style): Sword->Slash, Dagger->Stab, Axe->Slam, Spear->Thrust, Bow->Bow, Staff->Cast, Gun->Shoot, Fist->Punch
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local WeaponSkins = require(script.Parent.WeaponSkins)
local ShieldSkins = require(script.Parent.ShieldSkins)
local OffhandSkins = require(script.Parent.OffhandSkins)

local AttackAnimator = {}

local WEAPON_TO_STYLE: { [string]: string } = {
	Sword = "Slash", Dagger = "Stab", Axe = "Slam", Spear = "Thrust", Bow = "Bow", Staff = "Cast", Gun = "Shoot", Fist = "Punch",
}

-- Sin arma: cuerpo a cuerpo / a distancia por facción y rol
local DEFAULTS: { [string]: { Melee: { [string]: string }, Ranged: { [string]: string } } } = {
	Saiyan = { Melee = { Tanque = "Punch", Guerrero = "Punch", Asesino = "Punch" }, Ranged = { Tirador = "Cast", Mago = "Cast", Curador = "Cast" } },
	Shinobi = { Melee = { Tanque = "Punch", Guerrero = "Slash", Asesino = "Stab" }, Ranged = { Tirador = "Throw", Mago = "Cast", Curador = "Cast" } },
	Shinigami = { Melee = { Tanque = "Punch", Guerrero = "Slash", Asesino = "Punch" }, Ranged = { Tirador = "Bow", Mago = "Cast", Curador = "Cast" } },
	Pirate = { Melee = { Tanque = "Punch", Guerrero = "Slash", Asesino = "Stab" }, Ranged = { Tirador = "Shoot", Mago = "Cast", Curador = "Cast" } },
}

function AttackAnimator.WeaponStyleOf(player: Player): string?
	local id = player:GetAttribute("Equip_Arma")
	if typeof(id) == "string" then
		local item = (ItemCatalog.Items :: any)[id]
		if item and item.Style then
			return item.Style
		end
		if item then
			return "Sword"
		end
	end
	return nil
end

function AttackAnimator.StyleFor(player: Player, ranged: boolean): string
	local ws = AttackAnimator.WeaponStyleOf(player)
	if ws then
		local s = WEAPON_TO_STYLE[ws]
		-- un arma cuerpo a cuerpo usada con un poder a distancia se anima como lanzamiento de energía
		if s then
			if ranged and (s == "Slash" or s == "Stab" or s == "Slam" or s == "Punch" or s == "Thrust") then
				return "Cast"
			end
			return s
		end
	end
	local f = DEFAULTS[tostring(player:GetAttribute("Faction"))] or DEFAULTS.Saiyan
	local role = tostring(player:GetAttribute("Role"))
	if ranged then
		return f.Ranged[role] or "Cast"
	end
	return f.Melee[role] or (if f.Ranged[role] then f.Ranged[role] else "Punch")
end

function AttackAnimator.Play(model: Model, style: string, length: number?, strike: number?)
	local alt = model:GetAttribute("AnimAlt") == true
	model:SetAttribute("AnimAlt", not alt)
	model:SetAttribute("AnimStyle", style)
	model:SetAttribute("AnimLen", math.clamp(length or 0.5, 0.2, 3))
	model:SetAttribute("AnimStrike", math.clamp(strike or 0.45, 0.15, 0.9))
	model:SetAttribute("AnimAt", Workspace:GetServerTimeNow())
end

---------------------------------------------------------------------
-- ARMA EN LA MANO (modelo simple por bloques; se pone al equipar la ranura Arma)
---------------------------------------------------------------------
local function block(parent: Instance, to: BasePart, size: Vector3, color: Color3, off: CFrame, mat: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = "WeaponPart"
	p.Size = size
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = p
	w.C0 = off
	w.Parent = p
	return p
end

local STEEL = Color3.fromRGB(205, 212, 226)
local WOOD = Color3.fromRGB(110, 76, 48)
local DARK = Color3.fromRGB(50, 36, 28)
local GOLD = Color3.fromRGB(214, 180, 80)
local PAPER = Color3.fromRGB(240, 232, 205)

-- Postura de "arma en la mano" mientras NO se ataca (la aplica CharacterAnimClient con los atributos HoldR / HoldL).
-- Convención R6: derecho + = brazo adelante/arriba; izquierdo - = adelante/arriba.
local HOLD: { [string]: { R: number?, L: number? } } = {
	Sword = { R = 0.9 }, Dagger = { R = 0.7 }, Axe = { R = 1.0 }, Spear = { R = 1.0 }, Gun = { R = 0.9 },
	Staff = { R = 1.3, L = -0.4 }, Bow = { R = 0.35 },
}

local function hand(char: Model, right: boolean): BasePart?
	local r15 = char:FindFirstChild("RightHand") ~= nil
	local p = char:FindFirstChild(if r15 then (if right then "RightHand" else "LeftHand") else (if right then "Right Arm" else "Left Arm"))
	return if p and p:IsA("BasePart") then p else nil
end

-- ARCOS CON MALLA (5 modelos de Roblox, creador oficial; solo se usan malla y textura, sin sus scripts).
-- Tier = tramo de nivel del arma (1-11). Dir = hacia dónde van los ejes de la malla en el brazo izquierdo:
--   X = a lo ancho, Y = a lo largo del arco, Z = hacia donde "abulta" el arco. Si se ve girado o al revés, solo cambia Orient/Flip.
-- Agarre: la malla se centra por su caja, pero la mano agarra el arco por el medio de la PANZA (más hacia delante).
-- Z positivo = acerca el arco al cuerpo (la panza queda en la palma). Cada skin puede traer su propio Grip.
local BOW_GRIP = Vector3.new(0, 0.1, 0.45)
local BOW_TILT = 18 -- grados: la parte de arriba del arco se inclina hacia delante (más = más inclinado; 0 = vertical)
local BOW_SCALE = 0.65 -- multiplicador general del tamaño de todos los arcos (antes 1.0: se veían enormes)
-- El arco se lleva VERTICAL en la mano (largo = eje del brazo), con la panza hacia delante y la cuerda hacia el cuerpo.
-- (Ya no depende de que el brazo se levante: se ve bien con el brazo colgando.)
local ORIENT_Y_LONG = CFrame.identity -- mallas largas en Y
local ORIENT_X_LONG = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1)) -- mallas largas en X (Death Sling)
local BOW_SKINS: { { MinTier: number, Name: string, Mesh: number, Tex: number, Scale: number, Orient: CFrame, Flip: boolean } } = {
	{ MinTier = 1, Name = "Icshard Bow", Mesh = 192454317, Tex = 192454363, Scale = 1.0, Orient = ORIENT_Y_LONG, Flip = false },
	{ MinTier = 3, Name = "Goldstriked Bow", Mesh = 183684389, Tex = 183684472, Scale = 1.0, Orient = ORIENT_Y_LONG, Flip = false },
	{ MinTier = 5, Name = "Darkness Bow", Mesh = 95920116, Tex = 95920067, Scale = 0.8, Orient = ORIENT_Y_LONG, Flip = false },
	{ MinTier = 7, Name = "Death Sling", Mesh = 111502843, Tex = 111502821, Scale = 0.7, Orient = ORIENT_X_LONG, Flip = false },
	{ MinTier = 9, Name = "Imperial Bow", Mesh = 121945106, Tex = 121945146, Scale = 0.6, Orient = ORIENT_Y_LONG, Flip = false },
}
local function bowSkinFor(weapon: any): any
	local tier = if weapon and typeof(weapon.Tier) == "number" then weapon.Tier else 1
	local pick = BOW_SKINS[1]
	for _, s in ipairs(BOW_SKINS) do
		if tier >= s.MinTier then
			pick = s
		end
	end
	return pick
end

-- Arma de la mano DERECHA (hoja/mango a lo largo de -Z desde la palma; con el brazo levantado, hacia arriba) y, si hace falta, de la izquierda
local function buildWeapon(f: Folder, char: Model, style: string, glow: Color3, weapon: any?, retry: (() -> ())?)
	local rArm, lArm = hand(char, true), hand(char, false)
	if not rArm then
		return
	end
	local r15 = char:FindFirstChild("RightHand") ~= nil
	local g = if r15 then Vector3.new(0, -0.15, 0) else Vector3.new(0, -1, 0)
	-- modelo 3D (espada/daga/hacha/báculo) si carga; si no, sigue el dibujo con bloques de abajo
	if style == "Sword" or style == "Dagger" or style == "Axe" or style == "Staff" or style == "Spear" then
		local skin = WeaponSkins.Pick(style, weapon)
		if skin and WeaponSkins.Attach(f, rArm, skin, g, retry) then
			return
		end
	end
	local function along(len: number, from: number): CFrame -- centro a `from + len/2` hacia -Z
		return CFrame.new(g + Vector3.new(0, 0, -(from + len / 2)))
	end
	if style == "Sword" then
		block(f, rArm, Vector3.new(0.3, 0.3, 1.0), DARK, along(1.0, -0.5))
		block(f, rArm, Vector3.new(1.3, 0.25, 0.3), GOLD, along(0.3, 0.5), Enum.Material.Metal)
		block(f, rArm, Vector3.new(0.22, 0.55, 3.4), glow, along(3.4, 0.8), Enum.Material.Metal)
	elseif style == "Dagger" then
		block(f, rArm, Vector3.new(0.28, 0.28, 0.7), DARK, along(0.7, -0.3))
		block(f, rArm, Vector3.new(0.8, 0.2, 0.2), GOLD, along(0.2, 0.4))
		block(f, rArm, Vector3.new(0.18, 0.4, 1.6), glow, along(1.6, 0.6), Enum.Material.Metal)
	elseif style == "Axe" then
		block(f, rArm, Vector3.new(0.3, 0.3, 3.4), WOOD, along(3.4, -0.6))
		block(f, rArm, Vector3.new(0.25, 1.6, 1.3), glow, along(1.3, 2.0), Enum.Material.Metal)
	elseif style == "Spear" then
		-- lanza: asta larga con punta de acero (se empuña por el tercio de atrás)
		block(f, rArm, Vector3.new(0.26, 0.26, 4.6), WOOD, along(4.6, -1.2))
		block(f, rArm, Vector3.new(0.2, 0.7, 1.1), glow, along(1.1, 3.4), Enum.Material.Metal)
		block(f, rArm, Vector3.new(0.6, 0.2, 0.2), GOLD, along(0.2, 3.35), Enum.Material.Metal)
	elseif style == "Staff" then
		-- báculo: mango largo, remate dorado y orbe; con el brazo levantado queda casi vertical delante del pecho
		block(f, rArm, Vector3.new(0.3, 0.3, 5.4), WOOD, along(5.4, -1.3))
		block(f, rArm, Vector3.new(0.55, 0.55, 0.3), GOLD, along(0.3, 3.7), Enum.Material.Metal)
		block(f, rArm, Vector3.new(0.12, 0.9, 0.12), GOLD, along(0.12, 3.95)).Name = "WeaponPart"
		local orb = block(f, rArm, Vector3.new(0.95, 0.95, 0.95), glow, along(0.95, 4.1), Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
	elseif style == "Bow" and lArm then
		-- arco en la mano IZQUIERDA, agarrado por el centro: dos brazos curvados hacia el arquero y la cuerda
		local gl = if r15 then Vector3.new(0, -0.15, 0) else Vector3.new(0, -1, 0)
		local at = CFrame.new(gl)
		local skin = bowSkinFor(weapon)
		if skin then
			local orient: CFrame = skin.Orient
			if skin.Flip then
				orient = orient * CFrame.Angles(0, 0, math.pi)
			end
			local piece = block(f, lArm, Vector3.new(1, 1, 1), Color3.new(1, 1, 1), at * CFrame.new(skin.Grip or BOW_GRIP) * CFrame.Angles(-math.rad(BOW_TILT), 0, 0) * orient)
			piece.Name = "WeaponPart"
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.FileMesh
			m.MeshId = "rbxassetid://" .. skin.Mesh
			m.TextureId = "rbxassetid://" .. skin.Tex
			m.Scale = Vector3.one * (skin.Scale * BOW_SCALE)
			m.Parent = piece
			return
		end
		block(f, lArm, Vector3.new(0.3, 0.3, 0.9), DARK, at)
		local bend = math.rad(14)
		block(f, lArm, Vector3.new(0.22, 0.22, 1.35), WOOD, at * CFrame.new(0, 0.1, -1.05) * CFrame.Angles(bend, 0, 0))
		block(f, lArm, Vector3.new(0.22, 0.22, 1.35), WOOD, at * CFrame.new(0, 0.1, 1.05) * CFrame.Angles(-bend, 0, 0))
		block(f, lArm, Vector3.new(0.3, 0.3, 0.22), glow, at * CFrame.new(0, 0.32, -1.78) * CFrame.Angles(bend, 0, 0), Enum.Material.Neon)
		block(f, lArm, Vector3.new(0.3, 0.3, 0.22), glow, at * CFrame.new(0, 0.32, 1.78) * CFrame.Angles(-bend, 0, 0), Enum.Material.Neon)
		block(f, lArm, Vector3.new(0.06, 0.06, 3.55), Color3.fromRGB(235, 235, 225), at * CFrame.new(0, 0.38, 0))
	elseif style == "Gun" then
		block(f, rArm, Vector3.new(0.35, 0.8, 0.35), DARK, CFrame.new(g))
		block(f, rArm, Vector3.new(0.3, 1.1, 0.3), Color3.fromRGB(80, 84, 94), CFrame.new(g.X, g.Y - 0.55, -0.3), Enum.Material.Metal)
	elseif style == "Fist" then
		-- guanteletes: un bloque metálico sobre cada mano
		for _, h in ipairs({ rArm, lArm }) do
			if h then
				block(f, h, Vector3.new(1.2, if r15 then 0.7 else 1.2, 1.25), glow, CFrame.new(0, if r15 then -0.1 else -0.6, -0.1), Enum.Material.Metal)
				block(f, h, Vector3.new(1.0, 0.25, 0.3), GOLD, CFrame.new(0, if r15 then -0.45 else -1.05, -0.6), Enum.Material.Metal)
			end
		end
	end
end

-- Pieza de la ranura ESCUDO, en la mano izquierda (o a la espalda el Carcaj), según el rol de la pieza
local function buildOffhand(f: Folder, char: Model, item: any, glow: Color3, retry: (() -> ())?)
	local lArm = hand(char, false)
	local r15 = char:FindFirstChild("RightHand") ~= nil
	local g = if r15 then Vector3.new(0, -0.15, 0) else Vector3.new(0, -1, 0)
	local role = item.Role
	if role == "Tirador" then
		local torso = char:FindFirstChild(if r15 then "UpperTorso" else "Torso")
		if torso and torso:IsA("BasePart") then
			local at = CFrame.new(0.45, 0.15, 0.7) * CFrame.Angles(0, 0, math.rad(-18))
			if OffhandSkins.Attach(f, torso, "Quiver", item, at, retry) then
				return
			end
			block(f, torso, Vector3.new(0.6, 2.0, 0.6), WOOD, at)
			block(f, torso, Vector3.new(0.7, 0.2, 0.7), GOLD, at * CFrame.new(0, 0.95, 0), Enum.Material.Metal)
			for k = -1, 1 do
				block(f, torso, Vector3.new(0.1, 0.7, 0.1), glow, at * CFrame.new(k * 0.15, 1.35, 0) * CFrame.Angles(0, 0, math.rad(k * 8)))
			end
		end
		return
	end
	if not lArm then
		return
	end
	-- escudos con modelo 3D (Tanque, Guerrero y el genérico); si no cargan, se dibuja el escudo de bloques de abajo
	if role == "Tanque" or role == "Guerrero" or role == nil then
		local skin = ShieldSkins.Pick(item)
		local height = if role == "Tanque" then 3.6 elseif role == "Guerrero" then 3.1 else 2.6
		if skin and ShieldSkins.Attach(f, lArm, skin, g, height, retry) then
			return
		end
	end
	if role == "Tanque" then
		-- escudo torre: placa grande delante del brazo
		local at = CFrame.new(g.X - 0.15, g.Y + 0.45, -0.6)
		block(f, lArm, Vector3.new(1.9, 2.7, 0.3), STEEL, at, Enum.Material.Metal)
		block(f, lArm, Vector3.new(1.5, 2.3, 0.12), glow, at * CFrame.new(0, 0, -0.18), Enum.Material.Metal)
		local boss = block(f, lArm, Vector3.new(0.6, 0.6, 0.6), GOLD, at * CFrame.new(0, 0.1, -0.3), Enum.Material.Metal)
		boss.Shape = Enum.PartType.Ball
	elseif role == "Guerrero" or role == nil then
		-- escudo redondo (el genérico es más pequeño)
		local d = if role == nil then 1.5 else 2.1
		local at = CFrame.new(g.X - 0.1, g.Y + 0.35, -0.55) * CFrame.Angles(0, math.rad(90), 0)
		block(f, lArm, Vector3.new(0.28, d, d), STEEL, at, Enum.Material.Metal)
		block(f, lArm, Vector3.new(0.3, d * 0.7, d * 0.7), glow, at * CFrame.new(-0.05, 0, 0), Enum.Material.Metal)
		local boss = block(f, lArm, Vector3.new(0.5, 0.5, 0.5), GOLD, at * CFrame.new(-0.2, 0, 0), Enum.Material.Metal)
		boss.Shape = Enum.PartType.Ball
	elseif role == "Asesino" then
		-- segunda daga con modelo 3D (misma lista que la daga de la mano derecha, según el Tier/Rareza del objeto)
		local dskin = WeaponSkins.Pick("Dagger", item)
		if dskin and WeaponSkins.Attach(f, lArm, dskin, g, retry) then
			return
		end
		block(f, lArm, Vector3.new(0.28, 0.28, 0.7), DARK, CFrame.new(g.X, g.Y, 0.2))
		block(f, lArm, Vector3.new(0.8, 0.2, 0.2), GOLD, CFrame.new(g.X, g.Y, -0.2))
		block(f, lArm, Vector3.new(0.18, 0.4, 1.6), glow, CFrame.new(g.X, g.Y, -1.0), Enum.Material.Metal)
	elseif role == "Mago" then
		-- orbe: esfera brillante flotando sobre la palma izquierda
		local at = CFrame.new(g.X, g.Y - 0.1, -0.85)
		if OffhandSkins.Attach(f, lArm, "Orb", item, at, retry) then
			return
		end
		local orb = block(f, lArm, Vector3.new(1.0, 1.0, 1.0), glow, at, Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
		local ring = block(f, lArm, Vector3.new(0.12, 1.5, 1.5), GOLD, at * CFrame.Angles(0, math.rad(90), 0), Enum.Material.Metal)
		ring.Shape = Enum.PartType.Cylinder
	elseif role == "Curador" then
		-- libro sagrado abierto hacia delante
		local at = CFrame.new(g.X, g.Y + 0.25, -0.65)
		if OffhandSkins.Attach(f, lArm, "Book", item, at, retry) then
			return
		end
		block(f, lArm, Vector3.new(1.25, 1.5, 0.22), PAPER, at)
		block(f, lArm, Vector3.new(0.18, 1.55, 0.3), GOLD, at * CFrame.new(-0.62, 0, 0), Enum.Material.Metal)
		block(f, lArm, Vector3.new(0.4, 0.12, 0.06), glow, at * CFrame.new(0.08, 0.15, -0.14), Enum.Material.Neon)
		block(f, lArm, Vector3.new(0.12, 0.45, 0.06), glow, at * CFrame.new(0.08, 0.15, -0.14), Enum.Material.Neon)
	end
end

local function itemOf(player: Player, slot: string): any
	local id = player:GetAttribute("Equip_" .. slot)
	return if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
end

local function rarityColor(item: any): Color3
	return if item and ItemCatalog.RarityColor[item.Rarity] then ItemCatalog.RarityColor[item.Rarity] else STEEL
end

-- (Re)construye lo que lleva el personaje en las manos: arma en su mano y pieza de la ranura Escudo en la suya
local function onEquipChanged(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local old = char:FindFirstChild("EquippedWeapon")
	if old then
		old:Destroy()
	end
	local style = AttackAnimator.WeaponStyleOf(player)
	local weapon = itemOf(player, "Arma")
	local off = itemOf(player, "Escudo")
	-- arma de dos manos + escudo de verdad (datos viejos): el escudo no se dibuja
	if off and GearCatalog.IsShield(off) and weapon and GearCatalog.IsTwoHandedWeapon(weapon) then
		off = nil
	end
	local hold = if style then HOLD[style] else nil
	char:SetAttribute("HoldR", if hold then hold.R else nil)
	char:SetAttribute("HoldL", if hold then hold.L else nil)
	if not style and not off then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "EquippedWeapon"
	f.Parent = char
	-- si un modelo 3D termina de cargar después, se reconstruye lo que lleva en las manos
	local function retry()
		if player.Character == char and f.Parent == char then
			onEquipChanged(player)
		end
	end
	if style then
		buildWeapon(f, char, style, rarityColor(weapon), weapon, retry)
	end
	if off then
		buildOffhand(f, char, off, rarityColor(off), retry)
	end
end

local function hook(player: Player)
	player:GetAttributeChangedSignal("Equip_Arma"):Connect(function()
		onEquipChanged(player)
	end)
	player:GetAttributeChangedSignal("Equip_Escudo"):Connect(function()
		onEquipChanged(player)
	end)
	player.CharacterAdded:Connect(function(char)
		if not char:WaitForChild("Right Arm", 3) then
			char:WaitForChild("RightHand", 10)
		end
		task.wait(0.2)
		onEquipChanged(player)
	end)
	if player.Character then
		task.spawn(onEquipChanged, player)
	end
end
Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

return AttackAnimator
