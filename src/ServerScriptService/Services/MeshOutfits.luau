--!strict
--[[
    MeshOutfits (ModuleScript) -> ServerScriptService.Services.MeshOutfits
    Cambia las piezas de BLOQUES del traje por las piezas 3D hechas en Blender (carpeta ServerStorage > OutfitMeshes).
    Hoy: GOKU (pelo, mangas, muñequeras, botas, faja). Funciona en R6 y R15 (en R15 ancla al hombro/mano y cadera/pie). Si falta una pieza en la carpeta, queda el bloque de siempre.
    Las piezas llegan SIN color: aquí se pintan con los colores del personaje (tabla Looks de PlayerOutfits).

    AJUSTES RÁPIDOS:
      FLIP = true   -> si las piezas aparecen mirando hacia atrás (la punta de la bota debe ir al frente).
      HAIR_SCALE    -> tamaño del pelo (1 = como salió de Blender).
]]
local ServerStorage = game:GetService("ServerStorage")

local FLIP = false
local HAIR_SCALE = 1.0

-- size = medidas finales (studs, ejes Roblox: X ancho, Y alto, Z fondo). center = centro de la caja de la pieza respecto
-- a su ORIGEN de diseño (Roblox coloca las mallas por el centro de su caja, no por el origen). Salen de medidas.txt / FBX.
type Meta = { size: Vector3, center: Vector3, scale: number? }
local META: { [string]: Meta } = {
	Hair_Goku = { size = Vector3.new(2.95, 2.15, 2.20), center = Vector3.new(0, 0.8555, 0.397), scale = HAIR_SCALE },
	Wristband = { size = Vector3.new(1.07, 0.45, 1.07), center = Vector3.zero },
	WristTrim = { size = Vector3.new(1.10, 0.08, 1.10), center = Vector3.zero },
	Boot = { size = Vector3.new(1.14, 0.81, 1.40), center = Vector3.new(0, -0.095, -0.14) },
	BootCuff = { size = Vector3.new(1.08, 0.16, 1.08), center = Vector3.zero },
	Belt = { size = Vector3.new(2.06, 0.95, 1.10), center = Vector3.new(0, -0.33, -0.06) },
	Sleeve = { size = Vector3.new(1.10, 1.00, 1.10), center = Vector3.zero },
}

-- Qué piezas lleva cada personaje: malla, parte del cuerpo, desplazamiento del origen, llave de color, bloques que reemplaza
type Slot = { mesh: string, part: string, offset: Vector3, colorKey: string, remove: { string } }
local SLOTS: { [string]: { Slot } } = {
	Goku = {
		{ mesh = "Hair_Goku", part = "Head", offset = Vector3.zero, colorKey = "Hair", remove = { "Hair" } },
		{ mesh = "Wristband", part = "Right Arm", offset = Vector3.new(0, -0.62, 0), colorKey = "Wrists", remove = { "Gauntlet" } },
		{ mesh = "Wristband", part = "Left Arm", offset = Vector3.new(0, -0.62, 0), colorKey = "Wrists", remove = { "Gauntlet" } },
		{ mesh = "WristTrim", part = "Right Arm", offset = Vector3.new(0, -0.28, 0), colorKey = "WristTrim", remove = { "GauntletTrim" } },
		{ mesh = "WristTrim", part = "Left Arm", offset = Vector3.new(0, -0.28, 0), colorKey = "WristTrim", remove = { "GauntletTrim" } },
		{ mesh = "BootCuff", part = "Right Leg", offset = Vector3.new(0, -0.22, 0), colorKey = "BootCuff", remove = { "BootCuff" } },
		{ mesh = "BootCuff", part = "Left Leg", offset = Vector3.new(0, -0.22, 0), colorKey = "BootCuff", remove = { "BootCuff" } },
		{ mesh = "Belt", part = "Torso", offset = Vector3.new(0, -0.8, 0), colorKey = "Belt", remove = { "Belt", "Buckle" } },
	},
}

-- En R15 las mangas y las botas NO son bloques encima (se veían hinchadas): se pintan las piezas redondeadas del propio cuerpo.
-- parte del cuerpo (R15) -> llave de color del look. También se borran los bloques "Sleeve"/"Boot" del traje.
local PAINT_R15: { [string]: { parts: { [string]: string }, remove: { string } } } = {
	Goku = {
		parts = { RightUpperArm = "Sleeves", LeftUpperArm = "Sleeves", RightFoot = "Boots", LeftFoot = "Boots" },
		remove = { "Sleeve", "Boot" },
	},
}

local MeshOutfits = {}

local function meshIn(item: Instance?): MeshPart?
	if not item then
		return nil
	end
	if item:IsA("MeshPart") then
		return item
	end
	return item:FindFirstChildWhichIsA("MeshPart", true)
end

-- Busca la pieza por nombre: primero en ServerStorage > OutfitMeshes (aunque esté dentro de otras carpetas/Models),
-- y si no, en el resto de ServerStorage, ReplicatedStorage o Workspace (por si la dejaste en otro lugar).
local function template(name: string): MeshPart?
	local folder = ServerStorage:FindFirstChild("OutfitMeshes")
	local found = meshIn(folder and folder:FindFirstChild(name, true))
	if found then
		return found
	end
	for _, root in ipairs({ ServerStorage, game:GetService("ReplicatedStorage"), workspace }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name and (d:IsA("MeshPart") or d:IsA("Model")) and not d:FindFirstAncestorOfClass("Humanoid") then
				local inChar = false
				for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
					if pl.Character and d:IsDescendantOf(pl.Character) then
						inChar = true
					end
				end
				local m = if inChar then nil else meshIn(d)
				if m and m.MeshId ~= "" then
					return m
				end
			end
		end
	end
	return nil
end

-- Cuerpo R15: nombres de las piezas reales que forman cada "pieza lógica" R6
local R15_LIMBS: { [string]: { string } } = {
	["Right Arm"] = { "RightUpperArm", "RightLowerArm", "RightHand" },
	["Left Arm"] = { "LeftUpperArm", "LeftLowerArm", "LeftHand" },
	["Right Leg"] = { "RightUpperLeg", "RightLowerLeg", "RightFoot" },
	["Left Leg"] = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" },
}

-- Convierte "pieza lógica R6 + desplazamiento vertical" en (pieza real, desplazamiento en su espacio).
-- R6: tal cual. R15: lo de arriba se ancla al hombro/cadera y lo de abajo a la mano/pie (los miembros R15 son más largos que los R6).
local function resolve(char: Model, logical: string, off: Vector3, isR15: boolean): (BasePart?, Vector3)
	local function bp(n: string): BasePart?
		local p = char:FindFirstChild(n)
		return if p and p:IsA("BasePart") then p else nil
	end
	if not isR15 then
		return bp(logical), off
	end
	if logical == "Head" then
		return bp("Head"), off
	end
	if logical == "Torso" then
		local ut, lt = bp("UpperTorso"), bp("LowerTorso")
		if not (ut and lt) then
			return nil, off
		end
		local top = ut.Position.Y + ut.Size.Y / 2
		local bottom = lt.Position.Y - lt.Size.Y / 2
		local worldY = (top + bottom) / 2 + off.Y
		local attach = if worldY >= lt.Position.Y + lt.Size.Y / 2 then ut else lt
		return attach, Vector3.new(off.X, worldY - attach.Position.Y, off.Z)
	end
	local names = R15_LIMBS[logical]
	if not names then
		return nil, off
	end
	local parts: { BasePart } = {}
	for _, n in ipairs(names) do
		local p = bp(n)
		if not p then
			return nil, off
		end
		table.insert(parts, p)
	end
	local top = parts[1].Position.Y + parts[1].Size.Y / 2
	local bottom = math.huge
	for _, p in ipairs(parts) do
		bottom = math.min(bottom, p.Position.Y - p.Size.Y / 2)
	end
	local yReal = if off.Y >= 0 then top - (1 - off.Y) else bottom + (off.Y + 1)
	local pick = parts[#parts]
	local bestScore = math.huge
	for _, p in ipairs(parts) do
		local d = math.abs(yReal - p.Position.Y)
		local score = if d <= p.Size.Y / 2 then d else d + 100
		if score < bestScore then
			bestScore = score
			pick = p
		end
	end
	return pick, Vector3.new(off.X, yReal - pick.Position.Y, off.Z)
end

function MeshOutfits.Apply(char: Model, characterName: string, look: { [string]: any })
	local slots = SLOTS[characterName]
	local outfit = char:FindFirstChild("Outfit")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not slots then
		return -- este personaje todavía no tiene piezas 3D
	end
	if not outfit then
		warn("[MeshOutfits] el personaje aún no tiene el traje de bloques (Outfit)")
		return
	end
	local isR15 = hum ~= nil and hum.RigType == Enum.HumanoidRigType.R15
	local placed = 0
	local removed: { [string]: boolean } = {}
	local paintCfg = PAINT_R15[characterName]
	if isR15 and paintCfg then
		for partName, key in pairs(paintCfg.parts) do
			local bp = char:FindFirstChild(partName)
			local c = look[key]
			if bp and bp:IsA("BasePart") and typeof(c) == "Color3" then
				bp.Color = c
			end
		end
		for _, n in ipairs(paintCfg.remove) do
			removed[n] = true
		end
	end
	local missing: { string } = {}
	for _, slot in ipairs(slots) do
		local tpl = template(slot.mesh)
		local attach, offset = resolve(char, slot.part, slot.offset, isR15)
		local meta = META[slot.mesh]
		local color = look[slot.colorKey]
		if tpl and attach and meta and typeof(color) == "Color3" then
			local k = meta.scale or 1
			local p = tpl:Clone()
			p.Name = "Mesh_" .. slot.mesh
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.Size = meta.size * k
			p.Color = color
			p.Material = Enum.Material.SmoothPlastic
			p.TextureID = ""
			local w = Instance.new("Weld")
			w.Part0 = attach
			w.Part1 = p
			w.C0 = CFrame.new(offset + meta.center * k) * (if FLIP then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
			w.Parent = p
			p.Parent = outfit
			placed += 1
			for _, n in ipairs(slot.remove) do
				removed[n] = true
			end
		elseif not tpl then
			table.insert(missing, slot.mesh)
		end
	end
	for n in pairs(removed) do
		for _, d in ipairs(outfit:GetChildren()) do
			if d.Name == n then
				d:Destroy()
			end
		end
	end
	print(string.format("[MeshOutfits] %s (%s): %d piezas 3D puestas, %d faltan", characterName, if isR15 then "R15" else "R6", placed, #missing))
	if #missing > 0 then
		local folder = ServerStorage:FindFirstChild("OutfitMeshes")
		local have: { string } = {}
		if folder then
			for _, d in ipairs(folder:GetDescendants()) do
				table.insert(have, d.Name .. "(" .. d.ClassName .. ")")
			end
		end
		warn("[MeshOutfits] faltan: " .. table.concat(missing, ", ") .. " | OutfitMeshes " .. (if folder then "contiene: " .. table.concat(have, ", ") else "NO EXISTE en ServerStorage"))
	end
end

return MeshOutfits
