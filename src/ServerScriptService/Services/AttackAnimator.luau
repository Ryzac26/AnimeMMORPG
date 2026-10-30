--!strict
--[[
    AttackAnimator (ModuleScript) -> ServerScriptService.Services.AttackAnimator
    Decide QUÉ animación de ataque usa cada personaje y la "publica" con atributos del modelo; el CLIENTE
    (CharacterAnimClient) la dibuja fluida en todas las pantallas. También pone el arma equipada en la mano.
      Play(modelo, estilo, duración?, momentoDelGolpe?)   estilos: Slash Stab Punch Bow Cast Shoot Slam Power Throw
      StyleFor(jugador, aDistancia)  -> estilo según arma equipada (ranura Arma); sin arma, por facción/rol
      Atributos que escribe: AnimStyle, AnimAt, AnimLen, AnimStrike, AnimAlt
    Armas (ItemCatalog.Items[id].Style): Sword->Slash, Dagger->Stab, Axe->Slam, Bow->Bow, Staff->Cast, Gun->Shoot, Fist->Punch
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)

local AttackAnimator = {}

local WEAPON_TO_STYLE: { [string]: string } = {
	Sword = "Slash", Dagger = "Stab", Axe = "Slam", Bow = "Bow", Staff = "Cast", Gun = "Shoot", Fist = "Punch",
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
			if ranged and (s == "Slash" or s == "Stab" or s == "Slam" or s == "Punch") then
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

-- Hoja/mango a lo largo de -Z desde la palma (con el brazo abajo apunta al frente; con el brazo levantado, hacia arriba)
local function buildWeapon(char: Model, style: string, rarity: Color3?)
	local old = char:FindFirstChild("EquippedWeapon")
	if old then
		old:Destroy()
	end
	local r15 = char:FindFirstChild("RightHand") ~= nil
	local rArm = char:FindFirstChild(if r15 then "RightHand" else "Right Arm")
	local lArm = char:FindFirstChild(if r15 then "LeftHand" else "Left Arm")
	if not rArm or not rArm:IsA("BasePart") then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "EquippedWeapon"
	f.Parent = char
	local g = if r15 then Vector3.new(0, -0.15, 0) else Vector3.new(0, -1, 0)
	local function along(len: number, from: number): CFrame -- centro a `from + len/2` hacia -Z
		return CFrame.new(g + Vector3.new(0, 0, -(from + len / 2)))
	end
	local glow = rarity or STEEL
	if style == "Sword" then
		block(f, rArm, Vector3.new(0.3, 0.3, 1.0), DARK, along(1.0, -0.5))
		block(f, rArm, Vector3.new(1.3, 0.25, 0.3), GOLD, along(0.3, 0.5), Enum.Material.Metal)
		block(f, rArm, Vector3.new(0.22, 0.55, 3.4), glow, along(3.4, 0.8), Enum.Material.Metal)
	elseif style == "Dagger" then
		block(f, rArm, Vector3.new(0.28, 0.28, 0.7), DARK, along(0.7, -0.3))
		block(f, rArm, Vector3.new(0.8, 0.2, 0.2), GOLD, along(0.2, 0.4))
		block(f, rArm, Vector3.new(0.18, 0.4, 1.6), glow, along(1.6, 0.6), Enum.Material.Metal)
		if lArm and lArm:IsA("BasePart") then
			block(f, lArm, Vector3.new(0.18, 0.4, 1.6), glow, CFrame.new(g.X, g.Y, -1.4), Enum.Material.Metal)
		end
	elseif style == "Axe" then
		block(f, rArm, Vector3.new(0.3, 0.3, 3.4), WOOD, along(3.4, -0.6))
		block(f, rArm, Vector3.new(0.25, 1.6, 1.3), glow, along(1.3, 2.0), Enum.Material.Metal)
	elseif style == "Staff" then
		block(f, rArm, Vector3.new(0.3, 0.3, 5.2), WOOD, along(5.2, -1.2))
		local orb = block(f, rArm, Vector3.new(0.9, 0.9, 0.9), glow, along(0.9, 4.0), Enum.Material.Neon)
		orb.Shape = Enum.PartType.Ball
	elseif style == "Bow" and lArm and lArm:IsA("BasePart") then
		-- el arco se sostiene con la izquierda: arco vertical al levantar el brazo
		block(f, lArm, Vector3.new(0.25, 0.25, 3.6), WOOD, CFrame.new(g.X, g.Y, -1.8))
		block(f, lArm, Vector3.new(0.25, 0.9, 0.9), WOOD, CFrame.new(g.X, g.Y, -0.2))
		block(f, lArm, Vector3.new(0.08, 0.08, 3.4), Color3.fromRGB(230, 230, 220), CFrame.new(g.X, g.Y - 0.35, -1.8))
	elseif style == "Gun" then
		block(f, rArm, Vector3.new(0.35, 0.8, 0.35), DARK, CFrame.new(g))
		block(f, rArm, Vector3.new(0.3, 1.1, 0.3), Color3.fromRGB(80, 84, 94), CFrame.new(g.X, g.Y - 0.55, -0.3), Enum.Material.Metal)
	end
end

local function onEquipChanged(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local ws = AttackAnimator.WeaponStyleOf(player)
	if ws and ws ~= "Fist" then
		local id = player:GetAttribute("Equip_Arma")
		local item = if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
		local col = if item and ItemCatalog.RarityColor[item.Rarity] then ItemCatalog.RarityColor[item.Rarity] else nil
		buildWeapon(char, ws, col)
	else
		local old = char:FindFirstChild("EquippedWeapon")
		if old then
			old:Destroy()
		end
	end
end

local function hook(player: Player)
	player:GetAttributeChangedSignal("Equip_Arma"):Connect(function()
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
