--!strict
--[[
    PetFollowClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > PetFollowClient
    MASCOTAS CON CUERPO: la mascota equipada (ranura "Mascota" = Equip_Accesorio2, ids Pet_<Familia>_<Rareza>) aparece
    como una criatura pequeña que SIGUE al personaje. Todos ven las mascotas de los jugadores cercanos.
      - Modelos propios opcionales en ReplicatedStorage > PetModels (<Familia>, <Familia>_Mitico, Mariposa_Alas); si faltan, cuerpo de bloques.
      - Aspecto por familia (PetCatalog.Looks.Species): zorro, tanuki, búho, tortuga, tigre, fénix, dragón, hada, lobo; cada una con su propia silueta y cola que se mueve.
      - La rareza cambia tamaño y brillo: Común sencilla · Raro chispas · Épico luz · Legendario luz y más grande · Mítico halo.
      - Las que vuelan flotan y aletean; las de tierra caminan pegadas al suelo y saltan al correr.
      - Al subir de nivel el dueño ve a su mascota dar una vuelta de celebración.
      - Al atacar el dueño, la mascota da un saltito; si el dueño se queda quieto ~15 s, se duerme ("zZz") y despierta al moverse.
      - Ajuste "Mostrar mascotas" (SettingsClient, atributo Setting_PetsMode): Todas · Solo la mía · Ninguna.
      - Nivel de la mascota (1..10, atributo EquipPlus_Accesorio2 = nivel-1): cada nivel la hace un poco más grande y en los niveles 4, 7 y 10
        evoluciona (más chispas, luz y halo).
      - Segunda mascota (ranura "Mascota 2" = Equip_Accesorio3, con el pase Pass_PetSlot): camina al otro lado del personaje.
      - Mascotas de facción: Mono (Saiyan), Sapo (Shinobi), Loro (Pirata), Mariposa (Shinigami).
      - Solo es visual (se crea en cada cliente); los bonus los sigue dando GearService.
    No tiene ScreenGui, no va en RELOAD.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local PetCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetCatalog"))

local VIEW_RANGE = 150
local SLEEP_AFTER = 15 -- segundos quieto para dormirse
local JUMP_TIME = 0.45
local RARITY = {
	Comun = { Scale = 0.85, Color = Color3.fromRGB(200, 200, 200) },
	Raro = { Scale = 0.95, Color = Color3.fromRGB(80, 160, 255) },
	Epico = { Scale = 1.05, Color = Color3.fromRGB(180, 90, 255) },
	Legendario = { Scale = 1.18, Color = Color3.fromRGB(255, 170, 40) },
	Mitico = { Scale = 1.3, Color = Color3.fromRGB(255, 70, 110) },
} :: { [string]: { Scale: number, Color: Color3 } }
local RARITY_INDEX = { Comun = 1, Raro = 2, Epico = 3, Legendario = 4, Mitico = 5 } :: { [string]: number }

-- MODELOS PROPIOS (ReplicatedStorage > PetModels): <Familia> y, para el Mítico, <Familia>_Mitico (aspecto exclusivo).
-- Si no hay modelo se usa el cuerpo de bloques. "Mariposa_Alas" reemplaza las alas de bloques de la mariposa.
local CUSTOM_SIZE = 0.55 -- los modelos vienen preparados a 4 studs de largo: se escalan x esto x rareza x nivel
local CUSTOM_SCALE: { [string]: number } = {} -- ajuste de tamaño por modelo, ej. Dragon = 1.2, Lobo_Mitico = 0.9
-- grados para girar un modelo que mira de lado o de espaldas (el frente es -Z). Vale para <Familia> y también para <Familia>_Mitico
-- (si un Mítico mira distinto, ponle su propia entrada, ej. Lobo_Mitico = 0). Mira a la izquierda = -90 · a la derecha = 90 · atrás = 180
local CUSTOM_YAW: { [string]: number } = { Sabiduria = 180, Fenix = -90, Hada = 90, Lobo = 90, Sapo = -90 }
-- familias SIN modelo propio (usan el cuerpo de bloques aunque exista el modelo en PetModels): para volver a usarlo, quitar de la lista
local CUSTOM_OFF: { [string]: boolean } = { Furia = true, Loro = true }

local folder = Workspace:FindFirstChild("PetsFx") or Instance.new("Folder")
folder.Name = "PetsFx"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }

type Pet = {
	Player: Player,
	Id: string,
	Char: Model,
	Root: Part,
	Model: Model,
	Look: { [string]: any },
	Rarity: string,
	Level: number,
	Slot: number,
	Scale: number,
	Wander: Vector3?,
	WanderAt: number?,
	WanderHome: Vector3?,
	Wings: { { Weld: Weld, Side: number, Base: CFrame } },
	Wag: { { Weld: Weld, Base: CFrame, Amp: number } },
	Halo: Weld?,
	Cf: CFrame,
	Vel: Vector3,
	Phase: number,
	SpinUntil: number,
	Tag: BillboardGui?,
	IdleSince: number,
	JumpAt: number,
	Zzz: BillboardGui?,
}
local pets: { [number]: Pet } = {} -- clave = UserId*2 + (ranura-1)
local SLOTS = { "Accesorio2", "Accesorio3" }
local function keyOf(pl: Player, slotIndex: number): number
	return pl.UserId * 2 + (slotIndex - 1)
end

local function parse(id: any): (string?, string?)
	if typeof(id) ~= "string" then
		return nil, nil
	end
	local fam, rar = string.match(id, "^Pet_(%w+)_(%w+)$")
	if fam and rar and PetCatalog.Looks[fam] and RARITY[rar] then
		return fam, rar
	end
	return nil, nil
end

local function part(model: Model, root: Part, shape: Enum.PartType, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?, transparency: number?): (Part, Weld)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p, w
end

local function templateFor(name: string): Model?
	if CUSTOM_OFF[(string.gsub(name, "_Mitico$", ""))] then
		return nil
	end
	local f = ReplicatedStorage:FindFirstChild("PetModels")
	local m = if f then f:FindFirstChild(name) else nil
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

-- clona un modelo propio, lo escala, lo pega al Root con Welds y lo apoya (en el suelo, o centrado si vuela). Devuelve false si no tiene partes.
local function attachTemplate(model: Model, root: Part, tpl: Model, key: string, s: number, flies: boolean, offset: CFrame?, sizeMult: number?): boolean
	local c = tpl:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("Motor6D") or d:IsA("Weld") or d:IsA("WeldConstraint") or d:IsA("ManualWeld") or d:IsA("Snap") then
			d:Destroy() -- las uniones del modelo original sobran: lo pegamos nosotros
		elseif d:IsA("BasePart") and d.Transparency >= 0.95 and #d:GetChildren() == 0 then
			d:Destroy() -- partes invisibles (cajas de rig): pesan y no se ven
		end
	end
	c:ScaleTo(c:GetScale() * CUSTOM_SIZE * (CUSTOM_SCALE[key] or 1) * s * (sizeMult or 1))
	local parts: { BasePart } = {}
	local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			local cf, sz = d.CFrame, d.Size
			local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
			local hx = 0.5 * (math.abs(r.X) * sz.X + math.abs(u.X) * sz.Y + math.abs(l.X) * sz.Z)
			local hy = 0.5 * (math.abs(r.Y) * sz.X + math.abs(u.Y) * sz.Y + math.abs(l.Y) * sz.Z)
			local hz = 0.5 * (math.abs(r.Z) * sz.X + math.abs(u.Z) * sz.Y + math.abs(l.Z) * sz.Z)
			minX, maxX = math.min(minX, cf.X - hx), math.max(maxX, cf.X + hx)
			minY, maxY = math.min(minY, cf.Y - hy), math.max(maxY, cf.Y + hy)
			minZ, maxZ = math.min(minZ, cf.Z - hz), math.max(maxZ, cf.Z + hz)
		end
	end
	if #parts == 0 then
		c:Destroy()
		return false
	end
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local yRef = if flies then (minY + maxY) / 2 else minY
	local yTarget = if flies then 0 else -0.75 * s -- el Root de las de tierra flota 0.75*s sobre el suelo
	local base = (offset or CFrame.identity) * CFrame.new(0, yTarget, 0) * CFrame.Angles(0, math.rad(CUSTOM_YAW[key] or CUSTOM_YAW[(string.gsub(key, "_Mitico$", ""))] or 0), 0)
	for _, p in ipairs(parts) do
		local rel = base * CFrame.new(-cx, -yRef, -cz) * p.CFrame
		p.Anchored = false
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Massless = true
		local w = Instance.new("Weld")
		w.Part0 = root
		w.Part1 = p
		w.C0 = rel
		w.Parent = p
	end
	c.Name = "Cuerpo"
	c.Parent = model
	return true
end

local function build(pl: Player, id: string, family: string, rarity: string, char: Model, level: number, slotIndex: number): Pet?
	local look = PetCatalog.Looks[family]
	local rr = RARITY[rarity]
	local s = rr.Scale * (1 + PetCatalog.LEVEL_SIZE * (level - 1))
	local idx = math.min(5, RARITY_INDEX[rarity] + PetCatalog.Stage(level)) -- la evolución suma brillo, luz y halo
	local sp = (look.Species :: string?) or ""
	local model = Instance.new("Model")
	model.Name = "Pet_" .. pl.Name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local tplKey = if rarity == "Mitico" and templateFor(family .. "_Mitico") then family .. "_Mitico" else family
	local tpl = templateFor(tplKey)
	local custom = tpl ~= nil
	local wingsTpl = if sp == "Mariposa" then templateFor("Mariposa_Alas") else nil

	local body: Color3, accent: Color3 = look.Body, look.Accent
	local belly: Color3 = look.Belly or accent
	local B = Enum.PartType.Ball
	local K = Enum.PartType.Block
	local V = Vector3.new
	local dark = Color3.fromRGB(25, 22, 30)
	local wings: { { Weld: Weld, Side: number, Base: CFrame } } = {}
	local wag: { { Weld: Weld, Base: CFrame, Amp: number } } = {}

	-- ayudantes: medidas y posiciones se escalan solas con la rareza (el frente es -Z)
	local function add(shape: Enum.PartType, size: Vector3, color: Color3, pos: Vector3, rot: CFrame?, mat: Enum.Material?, tr: number?): (Part, Weld)
		return part(model, root, shape, size * s, color, CFrame.new(pos * s) * (rot or CFrame.identity), mat, tr)
	end
	local function ball(d: number, color: Color3, pos: Vector3, mat: Enum.Material?, tr: number?): Part
		local p = add(B, Vector3.one * d, color, pos, nil, mat, tr)
		return p
	end
	local function tail(shape: Enum.PartType, size: Vector3, color: Color3, pos: Vector3, amp: number, rot: CFrame?, mat: Enum.Material?)
		local _, w = add(shape, size, color, pos, rot, mat)
		table.insert(wag, { Weld = w, Base = w.C0, Amp = amp })
	end
	local function wing(side: number, size: Vector3, pos: Vector3, color: Color3)
		local _, w = add(K, size, color, V(side * pos.X, pos.Y, pos.Z), nil, if look.Sparkle then Enum.Material.Neon else nil, if look.Sparkle then 0.45 else 0)
		table.insert(wings, { Weld = w, Side = side, Base = w.C0 })
	end

	local hs: number, hp: Vector3 = 1.0, V(0, 0.75, -0.55)
	if not custom then
		-- proporciones por especie
		local bs = ({ Zorro = 1.4, Tanuki = 1.7, Buho = 1.5, Tortuga = 1.3, Tigre = 1.5, Fenix = 1.3, Dragon = 1.5, Hada = 1.1, Lobo = 1.5, Mono = 1.5, Sapo = 1.7, Loro = 1.2, Mariposa = 0.9 } :: { [string]: number })[sp] or 1.5
		hs = ({ Zorro = 1.0, Tanuki = 1.05, Buho = 1.25, Tortuga = 0.8, Tigre = 1.0, Fenix = 0.9, Dragon = 1.0, Hada = 1.1, Lobo = 1.0, Mono = 1.05, Sapo = 1.1, Loro = 0.9, Mariposa = 0.7 } :: { [string]: number })[sp] or 1.0
		hp = ({ Buho = V(0, 0.65, -0.35), Tortuga = V(0, 0.3, -1.0), Hada = V(0, 0.8, -0.35) } :: { [string]: Vector3 })[sp] or V(0, 0.75, -0.55)

		-- cuerpo, cabeza y panza
		ball(bs, body, V(0, 0, 0.2))
		ball(hs, body, hp)
		ball(bs * (if sp == "Tanuki" then 0.75 else 0.57), belly, V(0, -0.15, -0.5))

		-- ojos (brillan desde Épico; lobo y dragón siempre)
		local glowEyes = sp == "Lobo" or sp == "Dragon" or idx >= 3
		local eyeColor = if sp == "Lobo" or sp == "Dragon" then accent elseif idx >= 3 then rr.Color elseif sp == "Tanuki" then Color3.fromRGB(245, 245, 235) else dark
		local eyeMat = if glowEyes then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if sp == "Buho" then
			for _, sx in ipairs({ -1, 1 }) do
				ball(0.5, Color3.fromRGB(250, 250, 245), hp + V(sx * 0.3, 0.1, -0.5))
				ball(0.24, if glowEyes then eyeColor else dark, hp + V(sx * 0.3, 0.1, -0.7), eyeMat)
			end
			add(K, V(0.2, 0.2, 0.3), Color3.fromRGB(240, 170, 50), hp + V(0, -0.15, -0.72), CFrame.Angles(-0.3, 0, 0))
		else
			for _, sx in ipairs({ -1, 1 }) do
				if sp == "Tanuki" then
					add(K, V(0.3, 0.22, 0.1), dark, hp + V(sx * 0.22 * hs, 0.1 * hs, -0.4 * hs))
				end
				ball(0.18, eyeColor, hp + V(sx * 0.2 * hs, 0.1 * hs, -0.45 * hs), eyeMat)
			end
		end

		-- hocico
		if look.Snout then
			local long = if sp == "Lobo" or sp == "Dragon" then 0.55 else 0.35
			local muzzle = if sp == "Lobo" or sp == "Dragon" then body:Lerp(accent, 0.25) else belly
			add(K, V(0.34, 0.28, long), muzzle, hp + V(0, -0.12 * hs, -(0.5 * hs + long * 0.5 - 0.1)))
			ball(0.16, dark, hp + V(0, -0.04 * hs, -(0.5 * hs + long - 0.05)))
		end

		-- orejas: puntiagudas (zorro, lobo) o redondas (tanuki, tigre)
		if look.Ears then
			for _, sx in ipairs({ -1, 1 }) do
				if sp == "Zorro" or sp == "Lobo" then
					local h = if sp == "Lobo" then 0.8 else 0.65
					add(K, V(0.28, h, 0.16), body, hp + V(sx * 0.32 * hs, 0.62 * hs + h * 0.15, 0), CFrame.Angles(0, 0, -sx * 0.25))
					add(K, V(0.14, h * 0.6, 0.1), if sp == "Lobo" then accent else dark, hp + V(sx * 0.32 * hs, 0.58 * hs + h * 0.1, -0.06), CFrame.Angles(0, 0, -sx * 0.25))
				else
					ball(0.38, body, hp + V(sx * 0.4 * hs, 0.48 * hs, 0))
					ball(0.2, if sp == "Tigre" then dark else belly, hp + V(sx * 0.4 * hs, 0.48 * hs, -0.1))
				end
			end
		end

		-- cuernos / penachos
		if look.Horns then
			for _, sx in ipairs({ -1, 1 }) do
				if sp == "Buho" then
					add(K, V(0.22, 0.5, 0.14), accent, hp + V(sx * 0.4, 0.62, -0.1), CFrame.Angles(0, 0, -sx * 0.45))
				else
					add(K, V(0.14, 0.5, 0.14), accent, hp + V(sx * 0.3 * hs, 0.55 * hs + 0.1, 0.05), CFrame.Angles(0.35, 0, -sx * 0.4))
				end
			end
		end

		-- tortuga: caparazón con placas, cuello y patas
		if look.Shell then
			ball(1.9, accent, V(0, 0.45, 0.35))
			ball(1.4, body:Lerp(accent, 0.35), V(0, 0.85, 0.35))
			for _, o in ipairs({ V(0, 1.5, 0.35), V(0.5, 1.3, 0.35), V(-0.5, 1.3, 0.35), V(0, 1.3, -0.15), V(0, 1.3, 0.85) }) do
				ball(0.45, body, o)
			end
			add(K, V(0.45, 0.45, 0.5), body, V(0, 0.3, -0.7))
			for _, lx in ipairs({ -1, 1 }) do
				for _, lz in ipairs({ -0.2, 0.9 }) do
					add(K, V(0.4, 0.45, 0.4), body, V(lx * 0.7, -0.6, lz))
				end
			end
		end

		-- tigre: rayas en el lomo y la frente
		if look.Stripes then
			for i = -1, 1 do
				add(K, V(1.55, 0.14, 0.16), accent, V(0, 0.62, 0.2 + i * 0.42))
				add(K, V(0.08, 0.04, 0.3), accent, hp + V(i * 0.15, 0.5 * hs, -0.05))
			end
		end

		-- dragón: púas en el lomo
		if sp == "Dragon" then
			for i = 0, 2 do
				add(K, V(0.14, 0.3 - i * 0.04, 0.2), accent, V(0, 0.78 - i * 0.12, 0.05 + i * 0.4), CFrame.Angles(-0.4 + i * 0.2, 0, 0))
			end
		end

		-- fénix: cresta de fuego y pico
		if sp == "Fenix" then
			add(K, V(0.16, 0.55, 0.14), accent, hp + V(0, 0.6, 0), CFrame.Angles(-0.25, 0, 0), Enum.Material.Neon)
			for _, sx in ipairs({ -1, 1 }) do
				add(K, V(0.13, 0.42, 0.12), body, hp + V(sx * 0.16, 0.55, 0.05), CFrame.Angles(-0.2, 0, -sx * 0.4), Enum.Material.Neon)
			end
			add(K, V(0.18, 0.14, 0.32), Color3.fromRGB(255, 190, 60), hp + V(0, -0.08, -0.62), CFrame.Angles(0.15, 0, 0))
		end

		-- hada: peinado y varita
		if sp == "Hada" then
			ball(0.75, accent, hp + V(0, 0.4, 0.12))
			for _, sx in ipairs({ -1, 1 }) do
				ball(0.3, accent, hp + V(sx * 0.55, 0.1, 0.15))
			end
			add(K, V(0.07, 0.07, 0.9), Color3.fromRGB(250, 250, 255), V(0.85, 0.1, -0.55), CFrame.Angles(0.5, 0, 0))
			ball(0.3, accent, V(0.85, 0.32, -0.95), Enum.Material.Neon)
		end

		-- lobo: crin en el cuello
		if sp == "Lobo" then
			ball(1.15, body:Lerp(accent, 0.2), hp + V(0, -0.3, 0.4))
		end

		-- mono: cara clara y mejillas
		if sp == "Mono" then
			ball(0.75, belly, hp + V(0, -0.05, -0.28))
			for _, sx in ipairs({ -1, 1 }) do
				ball(0.18, accent, hp + V(sx * 0.42, 0.05, -0.1), Enum.Material.Neon)
			end
		end

		-- sapo: ojos saltones, boca ancha y manchas en el lomo
		if sp == "Sapo" then
			for _, sx in ipairs({ -1, 1 }) do
				ball(0.42, belly, hp + V(sx * 0.3, 0.5, -0.2))
				ball(0.2, dark, hp + V(sx * 0.3, 0.52, -0.38))
			end
			add(K, V(0.8, 0.07, 0.3), dark, hp + V(0, -0.2, -0.5))
			for _, o in ipairs({ V(-0.35, 0.8, 0.0), V(0.3, 0.85, 0.5), V(-0.1, 0.8, 0.9) }) do
				ball(0.3, accent, o)
			end
		end

		-- loro: pico curvo y cresta
		if sp == "Loro" then
			add(K, V(0.2, 0.2, 0.34), Color3.fromRGB(255, 205, 70), hp + V(0, -0.05, -0.55), CFrame.Angles(0.25, 0, 0))
			add(K, V(0.12, 0.12, 0.2), dark, hp + V(0, -0.2, -0.62))
			for i = -1, 1 do
				add(K, V(0.12, 0.4, 0.14), accent, hp + V(i * 0.14, 0.5, 0.05), CFrame.Angles(-0.2, 0, i * -0.3))
			end
			for _, sx in ipairs({ -1, 1 }) do
				ball(0.32, Color3.fromRGB(250, 250, 245), hp + V(sx * 0.24, 0.08, -0.35))
				ball(0.16, dark, hp + V(sx * 0.24, 0.08, -0.5))
			end
		end

		-- mariposa: antenas
		if sp == "Mariposa" then
			for _, sx in ipairs({ -1, 1 }) do
				add(K, V(0.06, 0.6, 0.06), dark, hp + V(sx * 0.2, 0.6, -0.1), CFrame.Angles(0.2, 0, -sx * 0.35))
				ball(0.14, accent, hp + V(sx * 0.42, 0.9, -0.15), Enum.Material.Neon)
			end
		end

		-- adornos de familia: hoja y saco (tanuki), trébol (zorro)
		if look.Charm == "Leaf" then
			add(K, V(0.7, 0.05, 0.5), Color3.fromRGB(90, 190, 90), hp + V(0, 0.55 * hs, 0), CFrame.Angles(0.1, 0.6, 0.25))
			ball(0.7, Color3.fromRGB(205, 170, 110), V(0, 0.95, 1.1))
			ball(0.25, Color3.fromRGB(255, 210, 70), V(0, 1.3, 1.1), Enum.Material.Neon)
		elseif look.Charm == "Clover" then
			for _, o in ipairs({ V(-0.14, 0.14, 0), V(0.14, 0.14, 0), V(-0.14, -0.14, 0), V(0.14, -0.14, 0) }) do
				ball(0.24, Color3.fromRGB(90, 230, 120), hp + V(0, 1.15, 0) + o, Enum.Material.Neon)
			end
		end

		-- alas (la mariposa con alas nuevas "Mariposa_Alas" no lleva las de bloques)
		if look.Wings and not (sp == "Mariposa" and wingsTpl) then
			for _, side in ipairs({ -1, 1 }) do
				if sp == "Dragon" then
					wing(side, V(1.7, 0.08, 1.0), V(0.9, 0.5, 0.45), body:Lerp(accent, 0.25))
				elseif sp == "Fenix" then
					wing(side, V(1.5, 0.1, 0.9), V(0.85, 0.4, 0.35), accent)
					wing(side, V(1.1, 0.1, 0.6), V(0.8, 0.3, 0.9), body)
				elseif sp == "Hada" then
					wing(side, V(1.2, 0.06, 0.9), V(0.7, 0.55, 0.2), accent)
					wing(side, V(0.8, 0.06, 0.6), V(0.6, 0.2, 0.55), accent)
				elseif sp == "Buho" then
					wing(side, V(1.2, 0.1, 0.9), V(0.8, 0.35, 0.35), body:Lerp(accent, 0.3))
				elseif sp == "Mariposa" then
					wing(side, V(1.9, 0.06, 1.3), V(0.95, 0.5, 0.0), accent)
					wing(side, V(1.3, 0.06, 0.9), V(0.8, 0.3, 0.8), belly)
				elseif sp == "Loro" then
					wing(side, V(1.1, 0.1, 0.9), V(0.7, 0.3, 0.3), accent)
				else
					wing(side, V(1.3, 0.1, 0.85), V(0.8, 0.4, 0.35), accent)
				end
			end
		end

		-- colas (se mueven al caminar)
		if look.Tail then
			if sp == "Zorro" then
				tail(B, Vector3.one * 0.75, body, V(0, 0.25, 1.2), 0.1)
				tail(B, Vector3.one * 0.6, body, V(0, 0.45, 1.7), 0.18)
				tail(B, Vector3.one * 0.45, accent, V(0, 0.6, 2.1), 0.26)
			elseif sp == "Tanuki" then
				tail(B, Vector3.one * 0.6, body, V(0, 0.3, 1.2), 0.08)
				tail(B, Vector3.one * 0.55, dark, V(0, 0.45, 1.55), 0.14)
				tail(B, Vector3.one * 0.5, body, V(0, 0.6, 1.9), 0.2)
			elseif sp == "Tigre" then
				for i = 0, 3 do
					tail(B, Vector3.one * (0.42 - i * 0.04), if i == 3 then dark else body, V(0, 0.3 + i * 0.15, 1.2 + i * 0.35), 0.08 + i * 0.07)
				end
			elseif sp == "Dragon" then
				tail(B, Vector3.one * 0.5, body, V(0, 0.2, 1.2), 0.08)
				tail(B, Vector3.one * 0.4, body, V(0, 0.15, 1.6), 0.15)
				tail(K, V(0.5, 0.08, 0.45), accent, V(0, 0.1, 2.0), 0.22)
			elseif sp == "Lobo" then
				tail(B, Vector3.one * 0.6, body, V(0, 0.3, 1.2), 0.08)
				tail(B, Vector3.one * 0.55, body, V(0, 0.35, 1.55), 0.14)
				tail(B, Vector3.one * 0.4, accent, V(0, 0.45, 1.95), 0.2, nil, Enum.Material.Neon)
			elseif sp == "Fenix" then
				tail(K, V(0.22, 0.08, 1.1), accent, V(0, 0.25, 1.55), 0.05, nil, Enum.Material.Neon)
				for _, sx in ipairs({ -1, 1 }) do
					tail(K, V(0.2, 0.08, 1.0), body, V(sx * 0.3, 0.2, 1.5), 0.08, CFrame.Angles(0, sx * 0.3, 0), Enum.Material.Neon)
				end
			elseif sp == "Tortuga" then
				tail(B, Vector3.one * 0.3, body, V(0, -0.1, 1.35), 0.2)
			elseif sp == "Mono" then
				for i = 0, 4 do
					tail(B, Vector3.one * (0.3 - i * 0.02), if i == 4 then accent else body, V(0, 0.2 + i * 0.28, 1.2 + math.sin(i * 0.9) * 0.3), 0.08 + i * 0.07)
				end
			elseif sp == "Loro" then
				tail(K, V(0.2, 0.08, 1.2), body, V(0, 0.15, 1.6), 0.06)
				tail(K, V(0.2, 0.08, 1.0), accent, V(0.25, 0.1, 1.5), 0.08, CFrame.Angles(0, 0.25, 0))
				tail(K, V(0.2, 0.08, 1.0), Color3.fromRGB(255, 205, 70), V(-0.25, 0.1, 1.5), 0.08, CFrame.Angles(0, -0.25, 0))
			else
				tail(B, Vector3.one * 0.5, accent, V(0, 0.2, 1.15), 0.1)
				tail(B, Vector3.one * 0.38, body, V(0, 0.5, 1.5), 0.2)
			end
		end
	end

	-- modelo propio (si existe): reemplaza al cuerpo de bloques; las alas de la mariposa se suman al cuerpo de bloques
	if custom and tpl then
		if not attachTemplate(model, root, tpl, tplKey, s, look.Flies == true, nil, 1) then
			custom = false
		end
	elseif wingsTpl then
		attachTemplate(model, root, wingsTpl, "Mariposa_Alas", s, true, CFrame.new(0, 0.5 * s, 0.15 * s), 2.2)
	end

	-- corona dorada del Legendario
	if idx == 4 and not custom then
		for i = 0, 4 do
			local a = i * math.pi * 2 / 5
			add(K, V(0.1, 0.26, 0.1), Color3.fromRGB(255, 205, 60), hp + V(math.cos(a) * 0.26, 0.55 * hs + 0.05, math.sin(a) * 0.26), nil, Enum.Material.Neon)
		end
	end

	-- brillo por rareza
	local emitAt = root
	if idx >= 2 or look.Fire or look.Sparkle then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(if look.Fire then Color3.fromRGB(255, 160, 50) else rr.Color, accent)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * s), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Speed = NumberRange.new(0.5, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rate = if look.Fire or look.Sparkle then 14 else 2 + idx * 2
		pe.Parent = emitAt
	end
	if idx >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rr.Color
		light.Range = 5 + idx * 2
		light.Brightness = 0.8 + idx * 0.25
		light.Parent = root
	end
	local halo: Weld? = nil
	if idx >= 5 then
		local haloPart, hw = part(model, root, K, Vector3.new(0.12, 1.1 * s, 1.1 * s), rr.Color, CFrame.new(0, 1.9 * s, -0.5 * s) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon, 0.15)
		haloPart.Shape = Enum.PartType.Cylinder
		haloPart.Size = Vector3.new(0.12, 1.1 * s, 1.1 * s)
		halo = hw
	end

	local tag: BillboardGui? = nil
	if pl == localPlayer then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 20)
		bb.StudsOffset = Vector3.new(0, 2.6 * s, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 40
		bb.Adornee = root
		bb.Parent = root
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = 13
		t.TextColor3 = rr.Color
		t.TextStrokeTransparency = 0.4
		t.Text = (PetCatalog.Families[family] :: any).Name
		t.Parent = bb
		tag = bb
	end

	model.Parent = folder
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local start = if hrp and hrp:IsA("BasePart") then hrp.CFrame * CFrame.new(3, 0, 3) else CFrame.new()
	return {
		Player = pl, Id = id, Char = char, Root = root, Model = model, Look = look, Rarity = rarity, Level = level, Slot = slotIndex, Scale = s,
		Wings = wings, Wag = wag, Halo = halo, Cf = start, Vel = Vector3.zero, Phase = math.random() * 6, SpinUntil = 0, Tag = tag,
		IdleSince = os.clock(), JumpAt = -100, Zzz = nil,
	}
end

local function remove(key: number)
	local p = pets[key]
	if p then
		p.Model:Destroy()
		pets[key] = nil
	end
end

-- cada medio segundo: ¿qué mascotas debería tener cada jugador? (ranura 1: siempre; ranura 2: con el pase)
local function reconcile()
	local cam = Workspace.CurrentCamera
	local mode = localPlayer:GetAttribute("Setting_PetsMode")
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local alive = hrp ~= nil and hrp:IsA("BasePart") and hum ~= nil and hum.Health > 0
		local baseVisible = alive and not (mode == "none" or (mode == "mine" and pl ~= localPlayer))
		for i, slotName in ipairs(SLOTS) do
			local key = keyOf(pl, i)
			-- mascotas sueltas en la Casa VIP (atributo PetsHome1 / PetsHome2): se ven donde está la casa, no donde está el dueño
			local home = pl:GetAttribute("PetsHome" .. i)
			local refPos = if typeof(home) == "Vector3" then home else (if hrp then hrp.Position else nil)
			local visible = baseVisible
			-- VISTA PREVIA (solo Fundador, desde Ajustes > Lista de mascotas): atributo local PetPreview reemplaza la mascota de la ranura 1
			local rawId: any = pl:GetAttribute("Equip_" .. slotName)
			local previewing = false
			local pvLevel = 1
			if i == 1 and pl == localPlayer then
				local pv = pl:GetAttribute("PetPreview")
				if typeof(pv) == "string" and parse(pv) ~= nil then
					rawId = pv
					previewing = true
					local lv = pl:GetAttribute("PetPreviewLevel")
					pvLevel = if typeof(lv) == "number" then math.clamp(math.floor(lv), 1, 10) else 1
					visible = alive -- se ve aunque "Mostrar mascotas" esté en Ninguna
				end
			end
			if visible and not previewing and (pl ~= localPlayer or typeof(home) == "Vector3") and cam and refPos and (cam.CFrame.Position - refPos).Magnitude > VIEW_RANGE then
				visible = false
			end
			local family, rarity = parse(rawId)
			local want = visible and family ~= nil and rarity ~= nil
			if want and i == 2 and pl:GetAttribute("Pass_PetSlot") ~= true then
				want = false
			end
			local cur = pets[key]
			if not want then
				if cur then
					remove(key)
				end
			else
				local id = rawId :: string
				local plus = pl:GetAttribute("EquipPlus_" .. slotName)
				local level = PetCatalog.LevelOf(if typeof(plus) == "number" then plus else 0)
				if previewing then
					level = PetCatalog.LevelOf(pvLevel - 1)
				end
				if not cur or cur.Id ~= id or cur.Char ~= char or cur.Level ~= level then
					remove(key)
					local made = build(pl, id, family :: string, rarity :: string, char :: Model, level, i)
					if made then
						pets[key] = made
					end
				end
			end
		end
	end
end

local acc = 0

RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc >= 0.5 then
		acc = 0
		reconcile()
	end
	local t = os.clock()
	for key, p in pairs(pets) do
		local hrp = p.Char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") or not p.Char.Parent then
			remove(key)
			continue
		end
		local flies: boolean = p.Look.Flies == true
		local s = p.Scale
		-- dormir: dueño quieto mucho rato y sin pelear; despierta al moverse o al atacar
		local moving = hrp.AssemblyLinearVelocity.Magnitude > 2
		if moving then
			p.IdleSince = t
		elseif p.JumpAt > p.IdleSince then
			p.IdleSince = p.JumpAt
		end
		local home = p.Player:GetAttribute("PetsHome" .. p.Slot)
		local atHome = typeof(home) == "Vector3"
		local sleeping = not atHome and t - p.IdleSince > SLEEP_AFTER
		if sleeping and not p.Zzz then
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(60, 24)
			bb.StudsOffset = Vector3.new(0, 2.4 * s, 0)
			bb.AlwaysOnTop = false
			bb.MaxDistance = 60
			bb.Adornee = p.Root
			bb.Parent = p.Root
			local z = Instance.new("TextLabel")
			z.Size = UDim2.fromScale(1, 1)
			z.BackgroundTransparency = 1
			z.Font = Enum.Font.GothamBold
			z.TextSize = 16
			z.TextColor3 = Color3.fromRGB(200, 220, 255)
			z.TextStrokeTransparency = 0.5
			z.Text = "zZz"
			z.Parent = bb
			p.Zzz = bb
		elseif not sleeping and p.Zzz then
			p.Zzz:Destroy()
			p.Zzz = nil
		end
		-- punto donde "debería" estar: detrás y a la derecha del dueño
		local anchorCf = if p.Slot == 2 then hrp.CFrame * CFrame.new(-3.0, 0, 4.6) else hrp.CFrame * CFrame.new(3.0, 0, 3.6)
		local target = anchorCf.Position
		if atHome then
			-- sueltas en la casa: pasean solas por el jardín (cada pocos segundos eligen otro punto)
			local radius = p.Player:GetAttribute("PetsHomeR")
			local R = if typeof(radius) == "number" then radius else 25
			if not p.Wander or t > (p.WanderAt or 0) or (p.WanderHome :: Vector3 - home :: Vector3).Magnitude > 1 then
				p.WanderHome = home
				p.Wander = (home :: Vector3) + Vector3.new((math.random() * 2 - 1) * R, 0, (math.random() * 2 - 1) * R * 0.7)
				p.WanderAt = t + 2.5 + math.random() * 5
			end
			target = p.Wander
		else
			p.Wander = nil
		end
		local bob = 0
		local speed = p.Vel.Magnitude
		if flies then
			bob = if sleeping then 1.4 + math.sin(t * 1.0 + p.Phase) * 0.1 else 3.3 + math.sin(t * 2.2 + p.Phase) * 0.4
		else
			local hit = Workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), rayParams)
			target = Vector3.new(target.X, if hit then hit.Position.Y else hrp.Position.Y - 3, target.Z)
			bob = (if sleeping then 0.42 else 0.75) * s + (if speed > 3 then math.abs(math.sin(t * 9 + p.Phase)) * 0.55 else 0)
		end
		target += Vector3.new(0, bob, 0)

		local cur = p.Cf.Position
		if (cur - target).Magnitude > 60 then
			cur = target
		end
		local alpha = 1 - math.exp(-(if atHome then 1.4 else 6.5) * dt)
		local newPos = cur:Lerp(target, alpha)
		p.Vel = (newPos - cur) / math.max(dt, 1e-3)
		-- orientación: hacia donde se mueve; quieta, mira como el dueño
		local flat = Vector3.new(p.Vel.X, 0, p.Vel.Z)
		local dir = if flat.Magnitude > 2.5 then flat.Unit else Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if dir.Magnitude < 0.01 then
			dir = Vector3.new(0, 0, -1)
		end
		local want = CFrame.lookAt(newPos, newPos + dir.Unit)
		local baseCf = CFrame.new(newPos) * p.Cf.Rotation:Lerp(want.Rotation, 1 - math.exp(-9 * dt))
		p.Cf = baseCf -- (sin el giro de celebración, que es solo de adorno)
		local cf = baseCf
		-- vuelta de celebración al subir de nivel
		if t < p.SpinUntil then
			local k = 1 - (p.SpinUntil - t) / 1.2
			cf = baseCf * CFrame.Angles(0, k * math.pi * 4, 0) + Vector3.new(0, math.sin(k * math.pi) * 2.2, 0)
		end
		-- saltito al atacar el dueño
		local jt = (t - p.JumpAt) / JUMP_TIME
		if jt >= 0 and jt < 1 then
			cf += Vector3.new(0, math.sin(jt * math.pi) * 1.7, 0)
		end
		p.Root.CFrame = cf
		-- aleteo y halo
		for _, w in ipairs(p.Wings) do
			local flap = math.sin(t * (if flies then 11 else 3) + p.Phase) * (if flies then 0.55 else 0.12)
			w.Weld.C0 = w.Base * CFrame.Angles(0, 0, w.Side * (0.35 + flap))
		end
		if p.Halo then
			p.Halo.C0 = CFrame.new(0, 1.9 * s + math.sin(t * 2) * 0.08, -0.5 * s) * CFrame.Angles(0, t * 2, math.pi / 2)
		end
		local wagRate = if sleeping then 0.6 elseif moving then 7 else 2.5
		for _, w in ipairs(p.Wag) do
			w.Weld.C0 = CFrame.Angles(0, math.sin(t * wagRate + p.Phase) * w.Amp * (if sleeping then 0.3 else 1), 0) * w.Base
		end
	end
end)

-- celebración: cualquier jugador que sube de nivel
local lastLevel: { [Player]: number } = {}
local function watch(pl: Player)
	local v = pl:GetAttribute("Level")
	if typeof(v) == "number" then
		lastLevel[pl] = v
	end
	pl:GetAttributeChangedSignal("PetHit"):Connect(function()
		for i = 1, #SLOTS do
			local pet = pets[keyOf(pl, i)]
			if pet then
				pet.JumpAt = os.clock()
			end
		end
	end)
	pl:GetAttributeChangedSignal("Level"):Connect(function()
		local n = pl:GetAttribute("Level")
		if typeof(n) ~= "number" then
			return
		end
		local prev = lastLevel[pl]
		lastLevel[pl] = n
		if prev and n > prev then
			for i = 1, #SLOTS do
				local pet = pets[keyOf(pl, i)]
				if pet then
					pet.SpinUntil = os.clock() + 1.2
				end
			end
		end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	for i = 1, #SLOTS do
		remove(keyOf(pl, i))
	end
	lastLevel[pl] = nil
end)
