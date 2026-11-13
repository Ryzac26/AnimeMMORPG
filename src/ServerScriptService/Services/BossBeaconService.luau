--!strict
--[[
    BossBeaconService (ModuleScript) -> ServerScriptService.Services.BossBeaconService
    MAQUETA DEL JEFE MUNDIAL: una estatua gigante (provisoria) que se levanta en el centro de la Arena y se ve desde los 4 fuertes,
    con un rayo de luz hacia el cielo y un cartel visible a gran distancia. Se muestra cuando el jefe aparece y se oculta al caer.
      BossBeaconService.Show(nombre?)   BossBeaconService.Hide()   (los usa BossService)
    Prueba en Studio: /boss  (invoca o retira al jefe completo).
    Para cambiar el aspecto: tabla PARTS (tamaño y posición relativos, en studs) y COLOR.
]]
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Net = require(ServerScriptService.Services.Net)
local NotifyRemote = Net.Get("Notify")

local CENTER = Vector3.new(0, 0, 0) -- centro de la Arena
local SCALE = 0.55 -- tamaño de la estatua (el jefe real mide ~250 studs)
local GROUND_Y = 12 -- altura del piso de la Arena
local COLOR = Color3.fromRGB(190, 40, 45)
local DARK = Color3.fromRGB(35, 25, 30)

-- nombre, tamaño, centro relativo a los pies (X, Y, Z), material/color
local PARTS: { { any } } = {
	{ "PieIzq", Vector3.new(60, 40, 70), Vector3.new(-45, 20, 0), DARK },
	{ "PieDer", Vector3.new(60, 40, 70), Vector3.new(45, 20, 0), DARK },
	{ "PiernaIzq", Vector3.new(50, 120, 50), Vector3.new(-45, 100, 0), DARK },
	{ "PiernaDer", Vector3.new(50, 120, 50), Vector3.new(45, 100, 0), DARK },
	{ "Cadera", Vector3.new(150, 40, 70), Vector3.new(0, 180, 0), COLOR },
	{ "Torso", Vector3.new(170, 150, 80), Vector3.new(0, 275, 0), DARK },
	{ "Pecho", Vector3.new(110, 70, 10), Vector3.new(0, 290, 42), COLOR },
	{ "HombroIzq", Vector3.new(60, 60, 60), Vector3.new(-115, 330, 0), COLOR },
	{ "HombroDer", Vector3.new(60, 60, 60), Vector3.new(115, 330, 0), COLOR },
	{ "BrazoIzq", Vector3.new(45, 140, 45), Vector3.new(-120, 240, 0), DARK },
	{ "BrazoDer", Vector3.new(45, 140, 45), Vector3.new(120, 240, 0), DARK },
	{ "PuñoIzq", Vector3.new(60, 55, 60), Vector3.new(-120, 140, 0), COLOR },
	{ "PuñoDer", Vector3.new(60, 55, 60), Vector3.new(120, 140, 0), COLOR },
	{ "Cabeza", Vector3.new(70, 70, 70), Vector3.new(0, 385, 0), DARK },
	{ "CuernoIzq", Vector3.new(14, 60, 14), Vector3.new(-30, 440, 0), COLOR },
	{ "CuernoDer", Vector3.new(14, 60, 14), Vector3.new(30, 440, 0), COLOR },
}

-- MODELOS PROPIOS: ServerStorage > BossModels > (Model con PrimaryPart, AnimationController/Animator y carpeta Animations > Monster).
-- Cada vez que aparece el jefe se elige uno al azar. Si la carpeta no existe o está vacía, se usa la estatua de bloques.
local TARGET_LENGTH = 170 -- largo (studs) al que se escala el modelo propio
local Y_OFFSET = 0 -- ajuste manual de altura (studs): negativo = más bajo, positivo = más alto
local SINK = 1 -- studs que se hunde el punto más bajo en el piso (para que "toque" de verdad)
local FACING_Y = 0 -- grados para girarlo si mira al lado equivocado (prueba 90, 180 o -90)
-- (las animaciones del modelo original NO se pueden usar: pertenecen a otro creador y Roblox no las carga en tu juego.
--  El movimiento lo hace BossAnimClient por código, con los Motor6D del cuerpo; aquí solo se avisa cuándo ataca.)

local BossBeaconService = {}
local model: Model? = nil
local customCenter: Vector3? = nil -- centro del cuerpo visible del modelo propio (para la raíz invisible)

local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- punto más bajo (Y) de las partes VISIBLES, contando su rotación. Devuelve (Y, nombre de la parte más baja)
local function lowestY(parts: { BasePart }): (number, string)
	local low, who = math.huge, "?"
	for _, p in ipairs(parts) do
		if p.Transparency < 0.9 then -- las partes invisibles (cajas de colisión, raíces) no cuentan
			local cf, sz = p.CFrame, p.Size
			local ext = 0.5 * (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z)
			local y = cf.Position.Y - ext
			if y < low then
				low, who = y, p:GetFullName()
			end
		end
	end
	return low, who
end

local function pickTemplate(): Model?
	local folder = ServerStorage:FindFirstChild("BossModels")
	if not folder then
		return nil
	end
	local list: { Model } = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") then
			table.insert(list, c)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

-- clona el modelo, lo escala y lo apoya en el piso (el movimiento lo pone BossAnimClient en cada cliente)
local function buildFromTemplate(tpl: Model, base: Vector3): Model
	local m = tpl:Clone()
	m.Name = "Maqueta_Jefe"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Animator") or d:IsA("AnimationController") then
			d:Destroy() -- scripts del Toolbox por seguridad; el Animator ya no hace falta (sus animaciones no cargan)
		elseif d:IsA("BasePart") then
			d.CanQuery = true -- clic sobre cualquier parte del cuerpo selecciona al jefe
			if d.Name == "HumanoidRootPart" then
				d.Name = "BodyRoot" -- el nombre HumanoidRootPart lo usa la raíz invisible de abajo (selección y rango de ataque)
			end
		end
	end
	local anims = m:FindFirstChild("Animations")
	if anims then
		anims:Destroy()
	end
	if FACING_Y ~= 0 then
		m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.rad(FACING_Y), 0))
	end
	local _, size0 = m:GetBoundingBox()
	local longest = math.max(size0.X, size0.Z)
	if longest > 0 then
		m:ScaleTo(m:GetScale() * TARGET_LENGTH / longest)
	end
	local cf = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + Vector3.new(base.X - cf.Position.X, 0, base.Z - cf.Position.Z))

	-- apoyar el punto visible más bajo en el piso (las partes invisibles no cuentan)
	local bodyParts: { BasePart } = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(bodyParts, d)
		end
	end
	local lowest, lowestName = lowestY(bodyParts)
	if lowest ~= math.huge then
		local delta = base.Y - lowest - SINK + Y_OFFSET
		print(string.format("[BossBeacon] punto más bajo Y=%.1f (%s) | piso Y=%.1f | ajuste %.1f", lowest, lowestName, base.Y, delta))
		m:PivotTo(m:GetPivot() + Vector3.new(0, delta, 0))
	end
	local mn: Vector3?, mx: Vector3?
	for _, p in ipairs(bodyParts) do
		if p.Transparency < 0.9 then
			local lo, hi = p.Position - p.Size / 2, p.Position + p.Size / 2
			mn = if mn then Vector3.new(math.min(mn.X, lo.X), math.min(mn.Y, lo.Y), math.min(mn.Z, lo.Z)) else lo
			mx = if mx then Vector3.new(math.max(mx.X, hi.X), math.max(mx.Y, hi.Y), math.max(mx.Z, hi.Z)) else hi
		end
	end
	customCenter = if mn and mx then (mn + mx) / 2 else nil
	m:SetAttribute("BossRig", true) -- BossAnimClient mueve a los que tienen esto
	m:SetAttribute("BossLength", TARGET_LENGTH)
	m.Parent = Workspace
	return m
end

-- BossService la llama justo antes de cada golpe grande: los clientes lo ven en AttackAt y hacen la mordida
function BossBeaconService.Attack()
	local m = model
	if m and m:GetAttribute("BossRig") == true then
		m:SetAttribute("AttackAt", Workspace:GetServerTimeNow())
	end
end

function BossBeaconService.Hide()
	local m = model
	model = nil
	if m then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(2), { Transparency = 1 }):Play()
			end
		end
		task.delay(2.2, function()
			m:Destroy()
		end)
	end
end

function BossBeaconService.Show(bossName: string?): Model
	BossBeaconService.Hide()
	customCenter = nil
	local base = Vector3.new(CENTER.X, GROUND_Y, CENTER.Z)
	local m: Model
	local tpl = pickTemplate()
	local okT: boolean = false
	local built: any = nil
	if tpl then
		okT, built = pcall(buildFromTemplate, tpl, base)
		if not okT then
			warn("[BossBeacon] falló el modelo propio, uso la estatua:", built)
		end
	end
	local custom = okT and built ~= nil
	if custom then
		m = built :: Model
	else
		m = Instance.new("Model")
		m.Name = "Maqueta_Jefe"
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- se ve desde cualquier fuerte
		for _, spec in ipairs(PARTS) do
			local nm, size, off, color = spec[1] :: string, spec[2] :: Vector3, spec[3] :: Vector3, spec[4] :: Color3
			local p = part(m, nm, size * SCALE, base + off * SCALE, color, if color == COLOR then Enum.Material.Neon else Enum.Material.Slate)
			p.Transparency = 0
			p.CanQuery = true -- el cursor puede seleccionar al jefe haciendo clic en cualquier parte del cuerpo
		end
	end
	-- raíz invisible: la usan la selección de objetivo, el rango del auto-ataque y el pivote de la animación
	local root = part(m, "HumanoidRootPart", Vector3.new(40, 30, 40), base + Vector3.new(0, 15, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	root.Transparency = 1
	root.CanQuery = true
	if custom and customCenter then
		root.CFrame = CFrame.new(customCenter)
	end
	m.PrimaryPart = root
	local head = m:FindFirstChild("Cabeza")
	if not custom and head and head:IsA("BasePart") then
		for _, x in ipairs({ -16, 16 }) do
			local eye = part(m, "Ojo", Vector3.new(14, 8, 6) * SCALE, head.Position + Vector3.new(x * SCALE, 6 * SCALE, 36 * SCALE), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
			local l = Instance.new("PointLight")
			l.Color = eye.Color
			l.Range = 60
			l.Parent = eye
		end
	end
	-- rayo de luz al cielo
	local beam = part(m, "Rayo", Vector3.new(1800, 30, 30), base + Vector3.new(0, 900, 0), COLOR, Enum.Material.Neon)
	beam.Transparency = 0.6
	beam.Shape = Enum.PartType.Cylinder
	beam.CFrame = CFrame.new(base + Vector3.new(0, 900, 0)) * CFrame.Angles(0, 0, math.rad(90))
	-- cartel visible desde lejos
	local sign = part(m, "Cartel", Vector3.new(1, 1, 1), base + Vector3.new(0, 520 * SCALE, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	sign.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 70)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 6000
	gui.Parent = sign
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = "☠ " .. (bossName or "JEFE MUNDIAL") .. " ☠"
	lbl.TextColor3 = Color3.fromRGB(255, 120, 120)
	lbl.TextStrokeTransparency = 0
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 30
	lbl.Parent = gui
	m.Parent = Workspace
	model = m
	-- aparece directamente en su posición final (sin animación de subida, que dejaba la maqueta bajo el piso)
	print(string.format("[BossBeacon] maqueta creada en %s con %d partes", tostring(m:GetPivot().Position), #m:GetDescendants()))
	return m
end

function BossBeaconService.IsShown(): boolean
	return model ~= nil
end

return BossBeaconService
