--!nonstrict
--[[
    MountModels (ModuleScript) -> StarterPlayer > StarterPlayerScripts > MountModels
    Arma el dibujo de cada montura con piezas (sin imágenes ni IDs de otros juegos). Lo usan MountClient (montura en el mundo y vista previa).
      MountModels.Build(speciesDef, rarity) -> { Model = Model, Legs = {...}, Top = number, Float = bool }
        El modelo mira hacia -Z, su suelo está en y = 0 y su lomo (donde pisa el personaje) en y = Top.
        Con un Model propio en ReplicatedStorage.MountModels (ver MountAssets) se usa ese en vez de las piezas.
      MountModels.Animate(rig, cf, t, speed)   mueve el modelo a cf y balancea las patas según la velocidad.
    Todas las piezas son Anchored y sin colisión (solo adorno visual).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MountCatalog = require(Modules:WaitForChild("MountCatalog"))
local MountAssets = require(Modules:WaitForChild("MountAssets"))

local MountModels = {}

local GROUND_TOP = 2.5 -- altura del lomo de las monturas de suelo
local FLOAT_TOP = 1.6 -- las flotantes se levantan además FLOAT_HOVER
local FLOAT_HOVER = 0.9
MountModels.FloatHover = FLOAT_HOVER

local function mkPart(model, name, size, cf, color, mat, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local BALL = Enum.PartType.Ball

-- Cuadrúpedos: Beast (lobo/tigre), Boar (jabalí/oso), Deer (ciervo/corcel)
local function quadruped(model, legs, sp, shape)
	local c, a = sp.Color, sp.Accent
	local T = GROUND_TOP
	local bodyW, bodyH, bodyL, legL, legW, headSize
	if shape == "Boar" then
		bodyW, bodyH, bodyL, legL, legW, headSize = 2.7, 1.6, 3.4, 0.9, 0.8, Vector3.new(1.7, 1.5, 1.4)
	elseif shape == "Deer" then
		bodyW, bodyH, bodyL, legL, legW, headSize = 1.6, 1.1, 3.4, 1.4, 0.4, Vector3.new(0.8, 0.9, 1.3)
	else
		bodyW, bodyH, bodyL, legL, legW, headSize = 2.2, 1.4, 3.6, 1.1, 0.6, Vector3.new(1.4, 1.2, 1.5)
	end
	local bodyY = legL + bodyH / 2
	mkPart(model, "Cuerpo", Vector3.new(bodyW, bodyH, bodyL), CFrame.new(0, bodyY, 0), c, Enum.Material.Fabric)
	mkPart(model, "Lomo", Vector3.new(bodyW * 0.9, 0.18, bodyL * 0.7), CFrame.new(0, legL + bodyH + 0.09, 0.1), a, Enum.Material.Fabric) -- manta/silla
	mkPart(model, "Panza", Vector3.new(bodyW * 0.8, 0.2, bodyL * 0.8), CFrame.new(0, legL + 0.05, 0), a, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local hip = Vector3.new(sx * (bodyW / 2 - legW / 2 - 0.05), legL, sz * (bodyL / 2 - 0.55))
			local leg = mkPart(model, "Pata", Vector3.new(legW, legL, legW), CFrame.new(hip) * CFrame.new(0, -legL / 2, 0), c:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
			table.insert(legs, { Part = leg, Hip = hip, Len = legL, Phase = if (sx * sz) > 0 then 0 else math.pi })
		end
	end
	local headY, headZ
	if shape == "Deer" then
		mkPart(model, "Cuello", Vector3.new(0.7, 1.7, 0.7), CFrame.new(0, legL + bodyH + 0.4, -bodyL / 2 + 0.2) * CFrame.Angles(math.rad(25), 0, 0), c, Enum.Material.Fabric)
		headY, headZ = legL + bodyH + 1.3, -bodyL / 2 - 0.6
		if sp.Id == "Ciervo" then
			for _, sx in ipairs({ -1, 1 }) do
				mkPart(model, "Asta", Vector3.new(0.14, 1.1, 0.14), CFrame.new(sx * 0.3, headY + 0.9, headZ + 0.2) * CFrame.Angles(0, 0, math.rad(-sx * 20)), a, Enum.Material.Wood)
				mkPart(model, "AstaB", Vector3.new(0.14, 0.6, 0.14), CFrame.new(sx * 0.55, headY + 1.1, headZ + 0.1) * CFrame.Angles(0, 0, math.rad(-sx * 55)), a, Enum.Material.Wood)
			end
		else
			mkPart(model, "Crin", Vector3.new(0.3, 1.5, 0.9), CFrame.new(0, legL + bodyH + 0.7, -bodyL / 2 + 0.9) * CFrame.Angles(math.rad(25), 0, 0), a, Enum.Material.Fabric)
		end
	else
		headY, headZ = legL + bodyH - 0.1, -bodyL / 2 - 0.6
	end
	mkPart(model, "Cabeza", headSize, CFrame.new(0, headY, headZ), c, Enum.Material.Fabric)
	mkPart(model, "Hocico", Vector3.new(headSize.X * 0.6, headSize.Y * 0.5, 0.8), CFrame.new(0, headY - headSize.Y * 0.2, headZ - headSize.Z / 2 - 0.3), a, Enum.Material.Fabric)
	mkPart(model, "Nariz", Vector3.new(0.3, 0.25, 0.25), CFrame.new(0, headY - headSize.Y * 0.1, headZ - headSize.Z / 2 - 0.7), Color3.fromRGB(25, 22, 25))
	for _, sx in ipairs({ -1, 1 }) do
		mkPart(model, "Ojo", Vector3.new(0.22, 0.22, 0.1), CFrame.new(sx * headSize.X * 0.3, headY + headSize.Y * 0.15, headZ - headSize.Z / 2 - 0.01), Color3.fromRGB(20, 18, 20))
		if shape == "Boar" then
			mkPart(model, "Colmillo", Vector3.new(0.18, 0.5, 0.18), CFrame.new(sx * 0.5, headY - 0.45, headZ - headSize.Z / 2 - 0.3) * CFrame.Angles(math.rad(-30), 0, 0), Color3.fromRGB(245, 240, 220))
		end
		if shape ~= "Deer" then
			mkPart(model, "Oreja", Vector3.new(0.35, 0.55, 0.25), CFrame.new(sx * headSize.X * 0.4, headY + headSize.Y / 2 + 0.2, headZ + 0.2), c:Lerp(Color3.new(0, 0, 0), 0.2), Enum.Material.Fabric)
		else
			mkPart(model, "Oreja", Vector3.new(0.4, 0.2, 0.2), CFrame.new(sx * 0.4, headY + 0.4, headZ + 0.3) * CFrame.Angles(0, 0, math.rad(sx * -25)), c, Enum.Material.Fabric)
		end
	end
	mkPart(model, "Cola", Vector3.new(0.5, 0.5, 1.7), CFrame.new(0, legL + bodyH - 0.1, bodyL / 2 + 0.7) * CFrame.Angles(math.rad(-25), 0, 0), if shape == "Beast" then a else c, Enum.Material.Fabric)
	return T
end

local function turtle(model, legs, sp)
	local c, a = sp.Color, sp.Accent
	local T = GROUND_TOP
	local shell = mkPart(model, "Caparazon", Vector3.new(3.8, 2.4, 4.6), CFrame.new(0, T - 1.1, 0.2), c, Enum.Material.Slate, BALL)
	shell.Name = "Caparazon"
	mkPart(model, "Panza", Vector3.new(3.4, 0.5, 4.2), CFrame.new(0, 0.6, 0.2), a, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local hip = Vector3.new(sx * 1.7, 0.9, sz * 1.5)
			local fl = mkPart(model, "Aleta", Vector3.new(0.9, 0.6, 1.5), CFrame.new(hip) * CFrame.new(0, -0.3, 0), a, Enum.Material.Fabric)
			table.insert(legs, { Part = fl, Hip = hip, Len = 0.6, Phase = if (sx * sz) > 0 then 0 else math.pi })
		end
	end
	mkPart(model, "Cuello", Vector3.new(0.9, 0.9, 1.1), CFrame.new(0, 1.7, -2.5), a, Enum.Material.Fabric)
	mkPart(model, "Cabeza", Vector3.new(1.2, 1.1, 1.3), CFrame.new(0, 1.9, -3.2), a, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		mkPart(model, "Ojo", Vector3.new(0.22, 0.22, 0.1), CFrame.new(sx * 0.35, 2.1, -3.86), Color3.fromRGB(20, 18, 20))
	end
	for k = 1, 3 do -- placas del caparazón
		mkPart(model, "Placa", Vector3.new(1.2, 0.18, 1.0), CFrame.new(0, T - 0.02, -1.3 + (k - 1) * 1.1), a, Enum.Material.Slate)
	end
	return T
end

local function frog(model, legs, sp)
	local c, a = sp.Color, sp.Accent
	local T = GROUND_TOP
	mkPart(model, "Cuerpo", Vector3.new(3.2, 2.2, 3.6), CFrame.new(0, T - 1.1, 0), c, Enum.Material.Fabric, BALL)
	mkPart(model, "Vientre", Vector3.new(2.4, 1.4, 3), CFrame.new(0, T - 1.5, -0.2), a, Enum.Material.Fabric, BALL)
	for _, sx in ipairs({ -1, 1 }) do
		local hip = Vector3.new(sx * 1.6, 1.0, 1.1)
		local leg = mkPart(model, "PataTrasera", Vector3.new(0.9, 1.0, 1.9), CFrame.new(hip) * CFrame.new(0, -0.5, 0), c:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Fabric)
		table.insert(legs, { Part = leg, Hip = hip, Len = 1.0, Phase = if sx > 0 then 0 else math.pi })
		local hipF = Vector3.new(sx * 1.2, 0.9, -1.4)
		local legF = mkPart(model, "PataDelantera", Vector3.new(0.6, 0.9, 0.6), CFrame.new(hipF) * CFrame.new(0, -0.45, 0), c, Enum.Material.Fabric)
		table.insert(legs, { Part = legF, Hip = hipF, Len = 0.9, Phase = if sx > 0 then math.pi else 0 })
		mkPart(model, "OjoGlobo", Vector3.new(0.9, 0.9, 0.9), CFrame.new(sx * 0.95, T - 0.1, -1.5), a, Enum.Material.SmoothPlastic, BALL)
		mkPart(model, "Pupila", Vector3.new(0.4, 0.4, 0.4), CFrame.new(sx * 0.95, T - 0.05, -1.9), Color3.fromRGB(20, 18, 20), Enum.Material.SmoothPlastic, BALL)
	end
	mkPart(model, "Boca", Vector3.new(2.0, 0.15, 0.2), CFrame.new(0, T - 1.4, -1.9), Color3.fromRGB(60, 30, 30))
	return T
end

local function floater(model, legs, sp, shape)
	local c, a = sp.Color, sp.Accent
	local T = FLOAT_TOP
	if shape == "Cloud" then
		local puffs = { { 0, 0, 0, 3.0 }, { 1.4, -0.1, 0.6, 2.2 }, { -1.4, -0.1, 0.4, 2.3 }, { 0.6, -0.1, -1.4, 2.0 }, { -0.7, -0.1, 1.5, 2.1 }, { 0, -0.5, 0.2, 3.2 } }
		for i, p in ipairs(puffs) do
			mkPart(model, "Nube" .. i, Vector3.new(p[4], p[4] * 0.62, p[4]), CFrame.new(p[1], T - 0.9 + p[2], p[3]), if i % 2 == 0 then a else c, Enum.Material.SmoothPlastic, BALL).Transparency = 0.05
		end
		mkPart(model, "Aura", Vector3.new(4, 0.1, 4), CFrame.new(0, T - 1.45, 0), c, Enum.Material.Neon, BALL).Transparency = 0.7
	elseif shape == "Wisp" then
		local body = mkPart(model, "Cuerpo", Vector3.new(2.6, 2.4, 3.2), CFrame.new(0, T - 1.1, 0), c, Enum.Material.Glass, BALL)
		body.Transparency = 0.3
		for i = 1, 4 do
			local s = 2.2 - i * 0.4
			mkPart(model, "Cola" .. i, Vector3.new(s, s, s), CFrame.new(0, T - 1.4 - i * 0.05, 1.6 + i * 0.8), c, Enum.Material.Glass, BALL).Transparency = 0.3 + i * 0.1
		end
		for _, sx in ipairs({ -1, 1 }) do
			mkPart(model, "Ojo", Vector3.new(0.55, 0.75, 0.2), CFrame.new(sx * 0.55, T - 0.8, -1.5), Color3.fromRGB(20, 20, 30), Enum.Material.SmoothPlastic, BALL)
			mkPart(model, "Llama", Vector3.new(0.5, 0.9, 0.5), CFrame.new(sx * 0.9, T - 0.1, 0.4), a, Enum.Material.Neon, BALL).Transparency = 0.2
		end
	elseif shape == "Jelly" then
		local dome = mkPart(model, "Campana", Vector3.new(4.0, 2.6, 4.0), CFrame.new(0, T - 1.1, 0), c, Enum.Material.Glass, BALL)
		dome.Transparency = 0.25
		mkPart(model, "Nucleo", Vector3.new(1.6, 1.2, 1.6), CFrame.new(0, T - 1.0, 0), a, Enum.Material.Neon, BALL).Transparency = 0.35
		for k = 1, 6 do
			local ang = k * math.pi * 2 / 6
			local hip = Vector3.new(math.cos(ang) * 1.3, T - 1.9, math.sin(ang) * 1.3)
			local tent = mkPart(model, "Tentaculo", Vector3.new(0.18, 1.6, 0.18), CFrame.new(hip) * CFrame.new(0, -0.8, 0), a, Enum.Material.Neon)
			tent.Transparency = 0.2
			table.insert(legs, { Part = tent, Hip = hip, Len = 1.6, Phase = k * 1.1, Sway = true })
		end
	else -- Carpet
		mkPart(model, "Tela", Vector3.new(3.4, 0.3, 4.6), CFrame.new(0, T - 0.15, 0), c, Enum.Material.Fabric)
		mkPart(model, "Borde", Vector3.new(3.6, 0.25, 0.4), CFrame.new(0, T - 0.12, -2.3), a, Enum.Material.Fabric)
		mkPart(model, "BordeB", Vector3.new(3.6, 0.25, 0.4), CFrame.new(0, T - 0.12, 2.3), a, Enum.Material.Fabric)
		mkPart(model, "BordeC", Vector3.new(0.4, 0.25, 4.6), CFrame.new(-1.7, T - 0.12, 0), a, Enum.Material.Fabric)
		mkPart(model, "BordeD", Vector3.new(0.4, 0.25, 4.6), CFrame.new(1.7, T - 0.12, 0), a, Enum.Material.Fabric)
		mkPart(model, "Dibujo", Vector3.new(1.2, 0.05, 1.2), CFrame.new(0, T + 0.02, 0) * CFrame.Angles(0, math.rad(45), 0), a, Enum.Material.Neon)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local hip = Vector3.new(sx * 1.75, T - 0.25, sz * 2.4)
				local tas = mkPart(model, "Borla", Vector3.new(0.2, 0.7, 0.2), CFrame.new(hip) * CFrame.new(0, -0.35, 0), a, Enum.Material.Fabric)
				table.insert(legs, { Part = tas, Hip = hip, Len = 0.7, Phase = sx + sz, Sway = true })
			end
		end
	end
	return T
end

function MountModels.Build(sp, rarity)
	local custom = nil
	local folder = ReplicatedStorage:FindFirstChild(MountAssets.Folder)
	if folder then
		local nm = MountAssets.ModelName[sp.Id] or sp.Id
		local m = folder:FindFirstChild(nm)
		if m and m:IsA("Model") then
			custom = m:Clone()
		end
	end
	local model = custom or Instance.new("Model")
	local legs = {}
	local top
	local rc = MountCatalog.RarityColor[rarity]
	local idx = MountCatalog.RarityIndex[rarity] or 1
	if custom then
		top = if sp.Float then FLOAT_TOP else GROUND_TOP
		for _, d in ipairs(custom:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				if d.Name == "Tinte" then
					d.Color = sp.Color
				end
			end
		end
	else
		if sp.Shape == "Beast" or sp.Shape == "Boar" or sp.Shape == "Deer" then
			top = quadruped(model, legs, sp, sp.Shape)
		elseif sp.Shape == "Turtle" then
			top = turtle(model, legs, sp)
		elseif sp.Shape == "Frog" then
			top = frog(model, legs, sp)
		else
			top = floater(model, legs, sp, sp.Shape)
		end
	end
	-- pieza raíz invisible en el origen (para PivotTo)
	local root = mkPart(model, "Raiz", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	model.PrimaryPart = root
	-- brillo por rareza: aro bajo la montura (Raro+), luz (Épico+), destellos (Legendario+)
	if idx >= 2 then
		local ring = mkPart(model, "Aro", Vector3.new(0.12, 6.2, 6.2), CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), rc, Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.Transparency = 0.55
	end
	if idx >= 3 then
		local l = Instance.new("PointLight")
		l.Color = rc
		l.Range = 8 + idx
		l.Brightness = 0.7 + idx * 0.1
		root.Parent = model
		l.Parent = root
	end
	if idx >= 4 then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(rc)
		pe.Rate = 4 + (idx - 4) * 8
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(1, 3)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.LightEmission = 0.8
		pe.Shape = Enum.ParticleEmitterShape.Box
		pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		pe.Parent = root
	end
	return { Model = model, Legs = legs, Top = top, Float = sp.Float, Root = root }
end

-- Mueve el modelo a cf (suelo del modelo) y balancea patas/colgantes. speed = velocidad horizontal del jinete (studs/s).
function MountModels.Animate(rig, cf, t, speed)
	rig.Model:PivotTo(cf)
	local moving = math.clamp(speed / 14, 0, 1.4)
	for _, leg in ipairs(rig.Legs) do
		local sw
		if leg.Sway then
			sw = math.sin(t * 2.2 + leg.Phase) * 0.25 + moving * 0.3
		else
			sw = math.sin(t * (6 + moving * 4) + leg.Phase) * 0.7 * moving
		end
		leg.Part.CFrame = cf * CFrame.new(leg.Hip) * CFrame.Angles(sw, 0, 0) * CFrame.new(0, -leg.Len / 2, 0)
	end
end

return MountModels
