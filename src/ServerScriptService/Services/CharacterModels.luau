--!strict
--[[
    CharacterModels (ModuleScript) -> ServerScriptService.Services.CharacterModels
    PERSONAJES COMPLETOS: si existe un modelo con el nombre del personaje en ServerStorage > CharacterModels (p. ej. "Goku"),
    se usa en lugar del traje de bloques. Cada pieza del modelo se suelda a la pieza gemela del R15 del jugador, así que se mueve
    con las animaciones. Es una PRUEBA: borrando el modelo de la carpeta (o la carpeta) todo vuelve al traje de siempre.

    Acepta DOS formatos de modelo: (1) el Goku suelto de 12 piezas, o (2) el R15 ya armado con piezas NombreR15_Goku soldadas.

    PREPARAR EL MODELO (una vez), formato 1: el Goku de 12 piezas (Head, Torso, Left Leg, Right Leg, LeftUpperArm, LeftLowerArm, LeftHand,
    RightUpperArm, RightLowerArm, RightHand, LeftFoot, RightFoot) se pone en ServerStorage > CharacterModels y se llama "Goku".

    Atributos opcionales en el modelo:  RotY (grados, 180 si mira hacia atrás) · ScaleMul (multiplica el tamaño, 1 por defecto).
]]
local ServerStorage = game:GetService("ServerStorage")

local FOLDER = "CharacterModels"

-- pieza del modelo -> pieza del R15
local MAP: { [string]: string } = {
	Head = "Head",
	Torso = "UpperTorso",
	["Left Leg"] = "LeftUpperLeg",
	["Right Leg"] = "RightUpperLeg",
	LeftUpperArm = "LeftUpperArm",
	LeftLowerArm = "LeftLowerArm",
	LeftHand = "LeftHand",
	RightUpperArm = "RightUpperArm",
	RightLowerArm = "RightLowerArm",
	RightHand = "RightHand",
	LeftFoot = "LeftFoot",
	RightFoot = "RightFoot",
}
-- piezas del R15 que el modelo ya cubre y se ocultan
local HIDE = { "LowerTorso", "LeftLowerLeg", "RightLowerLeg" }
local SUFFIX = "_CM"
-- Las piernas del modelo son una sola malla (sin rodilla). Con RIGID_FEET = true los pies/botas se pegan a la pierna (no se despegan al doblar
-- la rodilla; la pierna se mueve rígida). false = botas pegadas al pie del R15 (se mueven con la rodilla pero pueden despegarse).
local RIGID_FEET = true
local FOOT_ANCHOR: { [string]: string } = { LeftFoot = "LeftUpperLeg", RightFoot = "RightUpperLeg" }

local CharacterModels = {}

local function template(name: string): Model?
	local folder = ServerStorage:FindFirstChild(FOLDER)
	local m = folder and folder:FindFirstChild(name)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

function CharacterModels.Has(name: string): boolean
	return template(name) ~= nil
end

local function part(m: Instance, n: string): BasePart?
	local p = m:FindFirstChild(n, true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

-- Devuelve true si el personaje quedó vestido con el modelo
function CharacterModels.Apply(char: Model, name: string): boolean
	local tpl = template(name)
	if not tpl then
		return false
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end

	-- limpiar un vestido anterior (por si se aplica dos veces)
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("BasePart") and string.sub(c.Name, -#SUFFIX) == SUFFIX then
			c:Destroy()
		end
	end

	local cTorso, cFoot = part(char, "UpperTorso"), part(char, "LeftFoot")
	if not (cTorso and cFoot) then
		return false
	end

	-- Formato "ya armado": el modelo es un R15 con piezas NombreR15_Goku soldadas (lo que deja el script de la barra de comandos).
	-- Cada pieza se coloca respecto a su pieza R15 igual que en el modelo.
	local assembled: { { BasePart | string } } = {}
	for _, c in ipairs(tpl:GetChildren()) do
		if c:IsA("BasePart") then
			local base = string.match(c.Name, "^(.+)_Goku$")
			if base then
				table.insert(assembled, { c, base })
			end
		end
	end
	if #assembled > 0 then
		local n = 0
		for _, e in ipairs(assembled) do
			local c = e[1] :: BasePart
			local base = e[2] :: string
			local anchorName = (RIGID_FEET and FOOT_ANCHOR[base]) or base
			local tp = tpl:FindFirstChild(anchorName)
			local p = part(char, anchorName)
			if tp and tp:IsA("BasePart") and p then
				local gp = c:Clone()
				for _, d in ipairs(gp:GetDescendants()) do
					if d:IsA("WeldConstraint") or d:IsA("Script") or d:IsA("LocalScript") then
						d:Destroy()
					end
				end
				gp.Anchored = false
				gp.CanCollide = false
				gp.CanTouch = false
				gp.CanQuery = false
				gp.Massless = true
				gp.Name = base .. SUFFIX
				gp.Parent = char
				gp.CFrame = p.CFrame * tp.CFrame:ToObjectSpace(c.CFrame)
				local w = Instance.new("WeldConstraint")
				w.Part0 = p
				w.Part1 = gp
				w.Parent = gp
				local own = part(char, base)
				if own then
					own.Transparency = 1
				end
				n += 1
			end
		end
		for _, hn in ipairs(HIDE) do
			local hp = part(char, hn)
			if hp then
				hp.Transparency = 1
			end
		end
		if n > 0 then
			char:SetAttribute("CharacterModel", name)
			return true
		end
		return false
	end

	local g = tpl:Clone()
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local gTorso, gFoot = part(g, "Torso"), part(g, "LeftFoot")
	if not (gTorso and gFoot) then
		g:Destroy()
		warn("[CharacterModels] el modelo " .. name .. " no tiene Torso o LeftFoot")
		return false
	end

	-- escala: de la planta del pie a la parte alta del torso (el pelo no cuenta)
	local cH = (cTorso.Position.Y + cTorso.Size.Y / 2) - (cFoot.Position.Y - cFoot.Size.Y / 2)
	local gH = (gTorso.Position.Y + gTorso.Size.Y / 2) - (gFoot.Position.Y - gFoot.Size.Y / 2)
	local mul = g:GetAttribute("ScaleMul")
	g:ScaleTo((cH / gH) * (if typeof(mul) == "number" then mul else 1))

	-- girar alrededor del torso
	local rot = g:GetAttribute("RotY")
	if typeof(rot) == "number" and rot ~= 0 then
		local c = gTorso.Position
		g:PivotTo(CFrame.new(c) * CFrame.Angles(0, math.rad(rot), 0) * CFrame.new(-c) * g:GetPivot())
	end

	-- alinear: pies (altura) y torso (x, z)
	local dy = (cFoot.Position.Y - cFoot.Size.Y / 2) - (gFoot.Position.Y - gFoot.Size.Y / 2)
	local dp = cTorso.Position - gTorso.Position
	g:PivotTo(g:GetPivot() + Vector3.new(dp.X, dy, dp.Z))

	-- soldar pieza por pieza
	local count = 0
	for _, gp in ipairs(g:GetChildren()) do
		local r15 = MAP[gp.Name]
		if gp:IsA("BasePart") and r15 then
			local p = part(char, r15)
			if p then
				gp.Anchored = false
				gp.CanCollide = false
				gp.CanTouch = false
				gp.CanQuery = false
				gp.Massless = true
				gp.Name = r15 .. SUFFIX
				gp.Parent = char
				local w = Instance.new("WeldConstraint")
				w.Part0 = p
				w.Part1 = gp
				w.Parent = gp
				p.Transparency = 1
				count += 1
			end
		end
	end
	for _, n in ipairs(HIDE) do
		local p = part(char, n)
		if p then
			p.Transparency = 1
		end
	end
	g:Destroy()

	if count == 0 then
		return false
	end
	char:SetAttribute("CharacterModel", name)
	return true
end

return CharacterModels
