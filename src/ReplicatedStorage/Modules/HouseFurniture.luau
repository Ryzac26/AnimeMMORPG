--!strict
--[[
    HouseFurniture (ModuleScript) -> ReplicatedStorage.Modules.HouseFurniture
    Catálogo de muebles de la Casa VIP y su constructor (el servidor los coloca; el cliente usa el mismo Build para la vista previa).
    Coordenadas guardadas: X, Z relativas al origen de la casa y R = giro en grados. El frente del mueble mira a -Z local.
    Build(id, parent, cf, opts) -> Model   opts: Ghost (vista previa, sin colisión ni luz) · Image (id de imagen) · Interactive (servidor: asientos con prompt)
]]
local Players = game:GetService("Players")

local HouseFurniture = {}

HouseFurniture.MaxItems = 100

-- el servidor lo rellena: manda un aviso a un jugador (lo usan las interacciones de los muebles)
HouseFurniture.Notify = nil :: ((Player, string) -> ())?
HouseFurniture.GardenMaxZ = 122 -- el jardín mide 60 más que el original (66 -> 126)

-- colores de pared a elegir (el 1 es el mármol original)
HouseFurniture.WallColors = {
	{ Name = "Mármol", Color = Color3.fromRGB(214, 204, 186) },
	{ Name = "Hueso", Color = Color3.fromRGB(240, 236, 228) },
	{ Name = "Crema", Color = Color3.fromRGB(236, 220, 184) },
	{ Name = "Rosa", Color = Color3.fromRGB(234, 190, 200) },
	{ Name = "Salvia", Color = Color3.fromRGB(176, 200, 170) },
	{ Name = "Celeste", Color = Color3.fromRGB(170, 200, 226) },
	{ Name = "Lavanda", Color = Color3.fromRGB(196, 180, 224) },
	{ Name = "Terracota", Color = Color3.fromRGB(206, 140, 110) },
	{ Name = "Azul noche", Color = Color3.fromRGB(70, 84, 130) },
	{ Name = "Bosque", Color = Color3.fromRGB(66, 108, 84) },
	{ Name = "Burdeos", Color = Color3.fromRGB(120, 52, 64) },
	{ Name = "Grafito", Color = Color3.fromRGB(70, 72, 80) },
} :: { { Name: string, Color: Color3 } }
HouseFurniture.FloorY = 1.45

export type Def = { Id: string, Name: string, Icon: string, Image: boolean?, Radius: number, Vip: boolean? }

HouseFurniture.Catalog = {
	{ Id = "Sofa", Name = "Sofá", Icon = "🛋️", Radius = 6 },
	{ Id = "Sillon", Name = "Sillón", Icon = "💺", Radius = 3 },
	{ Id = "Silla", Name = "Silla", Icon = "🪑", Radius = 2 },
	{ Id = "Banco", Name = "Banco de jardín", Icon = "🪵", Radius = 4.5 },
	{ Id = "Mesa", Name = "Mesa redonda", Icon = "🍽️", Radius = 3.5 },
	{ Id = "Alfombra", Name = "Alfombra", Icon = "🟥", Radius = 7 },
	{ Id = "Lampara", Name = "Lámpara de pie", Icon = "💡", Radius = 1.5 },
	{ Id = "Planta", Name = "Planta", Icon = "🪴", Radius = 2 },
	{ Id = "Estanteria", Name = "Estantería", Icon = "📚", Radius = 4.5 },
	{ Id = "Cuadro", Name = "Cuadro (tu imagen)", Icon = "🖼️", Image = true, Radius = 4 },
	{ Id = "Pantalla", Name = "Pantalla (tu imagen)", Icon = "📺", Image = true, Radius = 6.5 },
	{ Id = "Farol", Name = "Farol de jardín", Icon = "🏮", Radius = 1.2 },
	{ Id = "Fuente", Name = "Fuente pequeña", Icon = "⛲", Radius = 4 },
	{ Id = "Estandarte", Name = "Estandarte", Icon = "🚩", Radius = 3 },
	{ Id = "Chimenea", Name = "Chimenea", Icon = "🔥", Radius = 8 },
	-- EXCLUSIVOS de la Tienda VIP del Mes (solo los puede colocar quien los compró)
	{ Id = "Trono", Name = "Trono Imperial", Icon = "👑", Radius = 4, Vip = true },
	{ Id = "Estatua", Name = "Estatua Dorada", Icon = "🗿", Radius = 3.5, Vip = true },
	{ Id = "Cristal", Name = "Cristal Flotante", Icon = "💎", Radius = 3, Vip = true },
} :: { Def }

HouseFurniture.ById = {} :: { [string]: Def }
for _, d in ipairs(HouseFurniture.Catalog) do
	HouseFurniture.ById[d.Id] = d
end

-- Distribución inicial del salón y el jardín (antes eran piezas fijas; ahora son muebles normales: se mueven, giran o se quitan)
HouseFurniture.Defaults = {
	{ T = "Sofa", X = -29, Z = -44, R = 270 }, { T = "Sofa", X = 29, Z = -44, R = 90 },
	{ T = "Mesa", X = -21, Z = -44, R = 0 }, { T = "Mesa", X = 21, Z = -44, R = 0 },
	{ T = "Estanteria", X = -65.5, Z = -10, R = 270 }, { T = "Estanteria", X = -65.5, Z = 0, R = 270 },
	{ T = "Estanteria", X = 65.5, Z = -10, R = 90 }, { T = "Estanteria", X = 65.5, Z = 0, R = 90 },
	{ T = "Planta", X = -26, Z = -58, R = 0 }, { T = "Planta", X = 26, Z = -58, R = 0 },
	{ T = "Planta", X = -26, Z = -2, R = 0 }, { T = "Planta", X = 26, Z = -2, R = 0 },
	{ T = "Estandarte", X = -66.5, Z = -50, R = 270 }, { T = "Estandarte", X = -66.5, Z = -57, R = 270 },
	{ T = "Estandarte", X = 66.5, Z = -50, R = 90 }, { T = "Estandarte", X = 66.5, Z = -57, R = 90 },
	{ T = "Chimenea", X = -26, Z = -67, R = 180 },
	{ T = "Banco", X = -14, Z = 68, R = 0 }, { T = "Banco", X = 14, Z = 68, R = 0 },
} :: { { T: string, X: number, Z: number, R: number } }

local BOOK_LINES = {
	"📖 «La paciencia forja más espadas que la ira.»",
	"📖 Un viejo tratado de energía espiritual: «Respira hondo antes del primer golpe.»",
	"📖 Un bestiario: «Los jefes del mundo temen a quien nunca retrocede.»",
	"📖 Diario de un aventurero: «Hoy encontré un metin... y salí corriendo.»",
	"📖 «Quien cuida a su montura, cuida su camino.»",
	"📖 Recetas del alquimista: «Nunca mezcles azul con rojo cerca del fuego.»",
	"📖 «Las facciones pasan; las historias quedan.»",
	"📖 Un libro sin título, con una sola frase: «Sigue subiendo.»",
}

-- ¿Se puede poner un mueble en (x, z)? (relativo al origen de la casa)
-- límites del salón y el jardín (los muebles guardados solo se comprueban contra esto)
function HouseFurniture.InBounds(x: number, z: number): boolean
	if x ~= x or z ~= z or math.abs(x) > 67 then
		return false
	end
	local salon = z >= -68 and z <= 7
	local garden = z >= 16 and z <= HouseFurniture.GardenMaxZ
	if not (salon or garden) then
		return false
	end
	-- el hueco entre el salón y el jardín debe quedar libre
	if z > 4 and z < 17 and math.abs(x) < 16 then
		return false
	end
	return true
end

-- ¿Se puede colocar un mueble NUEVO en (x, z)? (relativo al origen de la casa). Evita portal, baúl, tablón, mesa de diseño, caseta y estanques.
function HouseFurniture.Valid(x: number, z: number): boolean
	if not HouseFurniture.InBounds(x, z) then
		return false
	end
	local function near(cx: number, cz: number, r: number): boolean
		return (x - cx) ^ 2 + (z - cz) ^ 2 < r * r
	end
	if near(0, -62, 11) or near(-56, -30, 13) or near(61, -30, 9) or near(44, -56, 7) or near(38, 44, 15) or near(-30, 56, 13) or near(26, 96, 17) then
		return false
	end
	return true
end

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

-- asiento con prompt "Sentarse" (el Seat queda desactivado para que no se siente quien solo pasa corriendo)
function HouseFurniture.MakeSeat(parent: Instance, cf: CFrame, size: Vector3?)
	local seat = Instance.new("Seat")
	seat.Name = "Asiento"
	seat.Anchored = true
	seat.Size = size or Vector3.new(3.6, 0.4, 3.2)
	seat.CFrame = cf
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Disabled = true
	seat.TopSurface, seat.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	seat.Parent = parent
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Sentarse"
	pp.ObjectText = "Asiento"
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0
	pp.MaxActivationDistance = 7
	pp.RequiresLineOfSight = false
	pp.Parent = seat
	pp.Triggered:Connect(function(pl: Player)
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart or seat.Occupant then
			return
		end
		seat.Disabled = false
		seat:Sit(hum)
	end)
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			seat.Disabled = true
		end
	end)
	return seat
end

local WOOD = Color3.fromRGB(110, 76, 46)
local GOLD = Color3.fromRGB(240, 196, 90)
local RED = Color3.fromRGB(130, 40, 56)

function HouseFurniture.Build(id: string, parent: Instance, cf: CFrame, opts: { Ghost: boolean?, Image: string?, Interactive: boolean?, Accent: Color3?, Owner: Player? }?): Model?
	local def = HouseFurniture.ById[id]
	if not def then
		return nil
	end
	local o: { Ghost: boolean?, Image: string?, Interactive: boolean?, Accent: Color3?, Owner: Player? } = opts or {}
	local m = Instance.new("Model")
	m.Name = "Mueble_" .. id
	local seats: { CFrame } = {}
	local prompts: { { Part: BasePart, Action: string, Object: string, Fn: (Player) -> () } } = {}
	local function P(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		return mk(m, name, size, cf * off, color, mat, shape)
	end
	local function C(x: number, y: number, z: number): CFrame
		return CFrame.new(x, y, z)
	end
	local function cyl(name: string, d: number, h: number, off: CFrame, color: Color3, mat: Enum.Material): Part
		return P(name, Vector3.new(h, d, d), off * CFrame.Angles(0, 0, math.rad(90)), color, mat, Enum.PartType.Cylinder)
	end
	local function light(p: BasePart, range: number, bright: number, color: Color3)
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color = range, bright, color
		l.Parent = p
	end
	local function face(panel: Part, w: number, h: number)
		-- imagen del jugador en la cara frontal (-Z local)
		local img = o.Image
		if img and img ~= "" then
			local d = Instance.new("Decal")
			d.Face = Enum.NormalId.Front
			d.Texture = "rbxassetid://" .. img
			d.Parent = panel
		end
	end

	if id == "Sofa" then
		P("Base", Vector3.new(12, 1.6, 5), C(0, 1.2, 0), RED, Enum.Material.Fabric)
		P("Respaldo", Vector3.new(12, 3.2, 1.2), C(0, 3, 2.1), RED, Enum.Material.Fabric)
		for _, sx in ipairs({ -6.2, 6.2 }) do
			P("Brazo", Vector3.new(1.4, 3, 5), C(sx, 2.2, 0), Color3.fromRGB(105, 30, 46), Enum.Material.Fabric)
		end
		P("Cojin", Vector3.new(4.6, 0.8, 4), C(-2.6, 2.4, -0.3), Color3.fromRGB(150, 52, 68), Enum.Material.Fabric)
		P("Cojin", Vector3.new(4.6, 0.8, 4), C(2.6, 2.4, -0.3), Color3.fromRGB(150, 52, 68), Enum.Material.Fabric)
		P("Pata", Vector3.new(11, 0.6, 4.4), C(0, 0.3, 0), GOLD, Enum.Material.Metal)
		table.insert(seats, cf * C(-2.6, 3.1, -0.3))
		table.insert(seats, cf * C(2.6, 3.1, -0.3))
	elseif id == "Sillon" then
		P("Base", Vector3.new(5, 1.6, 4.6), C(0, 1.2, 0), Color3.fromRGB(60, 90, 140), Enum.Material.Fabric)
		P("Respaldo", Vector3.new(5, 3.4, 1.1), C(0, 3, 1.9), Color3.fromRGB(60, 90, 140), Enum.Material.Fabric)
		for _, sx in ipairs({ -2.8, 2.8 }) do
			P("Brazo", Vector3.new(1, 2.8, 4.6), C(sx, 2.1, 0), Color3.fromRGB(48, 74, 120), Enum.Material.Fabric)
		end
		P("Pata", Vector3.new(4.6, 0.6, 4.2), C(0, 0.3, 0), GOLD, Enum.Material.Metal)
		table.insert(seats, cf * C(0, 3.1, -0.2))
	elseif id == "Silla" then
		P("Asiento", Vector3.new(2.6, 0.5, 2.6), C(0, 2.2, 0), WOOD, Enum.Material.Wood)
		P("Respaldo", Vector3.new(2.6, 3, 0.4), C(0, 3.9, 1.1), WOOD, Enum.Material.Wood)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				P("Pata", Vector3.new(0.4, 2, 0.4), C(sx * 1.0, 1, sz * 1.0), GOLD, Enum.Material.Metal)
			end
		end
		table.insert(seats, cf * C(0, 2.9, 0))
	elseif id == "Banco" then
		P("Asiento", Vector3.new(8, 0.7, 2.6), C(0, 2.2, 0), WOOD, Enum.Material.Wood)
		P("Respaldo", Vector3.new(8, 2.6, 0.5), C(0, 3.9, 1.2), WOOD, Enum.Material.Wood)
		for _, sx in ipairs({ -3.4, 3.4 }) do
			P("Pata", Vector3.new(0.7, 2.2, 2.4), C(sx, 1.1, 0), GOLD, Enum.Material.Metal)
		end
		table.insert(seats, cf * C(-2, 2.9, 0))
		table.insert(seats, cf * C(2, 2.9, 0))
	elseif id == "Mesa" then
		cyl("Tapa", 6.4, 0.5, C(0, 3, 0), WOOD, Enum.Material.Wood)
		cyl("Borde", 6.8, 0.2, C(0, 2.7, 0), GOLD, Enum.Material.Metal)
		cyl("Pie", 1, 2.6, C(0, 1.5, 0), GOLD, Enum.Material.Metal)
		cyl("Base", 3.2, 0.3, C(0, 0.3, 0), GOLD, Enum.Material.Metal)
	elseif id == "Alfombra" then
		cyl("Borde", 14, 0.18, C(0, 0.09, 0), GOLD, Enum.Material.Fabric)
		cyl("Centro", 12.6, 0.24, C(0, 0.12, 0), Color3.fromRGB(150, 44, 64), Enum.Material.Fabric)
		cyl("Detalle", 7, 0.3, C(0, 0.15, 0), Color3.fromRGB(226, 190, 100), Enum.Material.Fabric)
		cyl("Detalle", 5.4, 0.34, C(0, 0.17, 0), Color3.fromRGB(150, 44, 64), Enum.Material.Fabric)
	elseif id == "Lampara" then
		cyl("Base", 2.4, 0.4, C(0, 0.2, 0), GOLD, Enum.Material.Metal)
		P("Poste", Vector3.new(0.4, 6.4, 0.4), C(0, 3.4, 0), GOLD, Enum.Material.Metal)
		local shade = P("Pantalla", Vector3.new(3, 2.4, 3), C(0, 7, 0), Color3.fromRGB(255, 232, 170), Enum.Material.Neon)
		shade.Transparency = 0.25
		if not o.Ghost then
			light(shade, 26, 0.8, Color3.fromRGB(255, 226, 170))
			local pole = m:FindFirstChild("Poste") :: BasePart
			local on = true
			table.insert(prompts, { Part = pole, Action = "Encender / apagar", Object = "Lámpara", Fn = function()
				on = not on
				shade.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				shade.Transparency = if on then 0.25 else 0
				local l = shade:FindFirstChildOfClass("PointLight")
				if l then
					l.Enabled = on
				end
			end })
		end
	elseif id == "Planta" then
		cyl("Maceta", 3, 2.6, C(0, 1.3, 0), Color3.fromRGB(176, 92, 60), Enum.Material.Slate)
		P("Hojas", Vector3.new(5, 5, 5), C(0, 5, 0), Color3.fromRGB(64, 150, 70), Enum.Material.Grass, Enum.PartType.Ball)
		P("Hojas", Vector3.new(3.2, 3.2, 3.2), C(1, 7.2, 0.4), Color3.fromRGB(86, 172, 90), Enum.Material.Grass, Enum.PartType.Ball)
	elseif id == "Estanteria" then
		P("Fondo", Vector3.new(8, 11, 1), C(0, 5.5, 1.5), WOOD, Enum.Material.Wood)
		for _, sx in ipairs({ -4, 4 }) do
			P("Lado", Vector3.new(0.8, 11, 3), C(sx, 5.5, 0.5), WOOD, Enum.Material.Wood)
		end
		for row = 0, 3 do
			P("Balda", Vector3.new(8, 0.5, 3), C(0, 0.5 + row * 3.2, 0.5), GOLD, Enum.Material.Wood)
			if row < 3 then
				for k = 0, 5 do
					P("Libro", Vector3.new(0.9, 2.2, 1.6), C(-3 + k * 1.2, 1.9 + row * 3.2, 0.5), Color3.fromHSV((row * 0.2 + k * 0.11) % 1, 0.5, 0.8), Enum.Material.SmoothPlastic)
				end
			end
		end
		P("Techo", Vector3.new(8.6, 0.6, 3.2), C(0, 11.2, 0.5), GOLD, Enum.Material.Wood)
		table.insert(prompts, { Part = m:FindFirstChild("Fondo") :: BasePart, Action = "Leer un libro", Object = "Estantería", Fn = function(pl: Player)
			if HouseFurniture.Notify then
				HouseFurniture.Notify(pl, BOOK_LINES[math.random(#BOOK_LINES)])
			end
		end })
	elseif id == "Cuadro" then
		for _, sx in ipairs({ -2, 2 }) do
			P("Pata", Vector3.new(0.4, 6, 0.4), C(sx, 3, 0.6), WOOD, Enum.Material.Wood)
		end
		P("Marco", Vector3.new(7.4, 5.8, 0.6), C(0, 6.5, 0), GOLD, Enum.Material.Metal)
		local panel = P("Lienzo", Vector3.new(6.6, 5, 0.7), C(0, 6.5, 0), Color3.fromRGB(235, 228, 214), Enum.Material.SmoothPlastic)
		face(panel, 6.6, 5)
	elseif id == "Pantalla" then
		P("Mueble", Vector3.new(11, 2, 3), C(0, 1, 0), Color3.fromRGB(40, 36, 42), Enum.Material.Wood)
		P("Soporte", Vector3.new(1.2, 1.6, 1), C(0, 2.8, 0.4), Color3.fromRGB(30, 30, 36), Enum.Material.Metal)
		P("Carcasa", Vector3.new(12, 7, 0.8), C(0, 7, 0.2), Color3.fromRGB(24, 24, 30), Enum.Material.Metal)
		local panel = P("Pantalla", Vector3.new(11.2, 6.2, 0.4), C(0, 7, -0.25), Color3.fromRGB(18, 22, 34), Enum.Material.SmoothPlastic)
		face(panel, 11.2, 6.2)
		if not (o.Image and o.Image ~= "") then
			panel.Color = Color3.fromRGB(30, 60, 110)
			panel.Material = Enum.Material.Neon
			panel.Transparency = 0.3
		end
		local tvOn = true
		table.insert(prompts, { Part = m:FindFirstChild("Carcasa") :: BasePart, Action = "Encender / apagar", Object = "Pantalla", Fn = function()
			tvOn = not tvOn
			local dec = panel:FindFirstChildOfClass("Decal")
			if dec then
				dec.Transparency = if tvOn then 0 else 1
			end
			if tvOn then
				if not dec then
					panel.Color = Color3.fromRGB(30, 60, 110)
					panel.Material = Enum.Material.Neon
					panel.Transparency = 0.3
				else
					panel.Color = Color3.fromRGB(18, 22, 34)
					panel.Material = Enum.Material.SmoothPlastic
				end
			else
				panel.Color = Color3.fromRGB(10, 10, 12)
				panel.Material = Enum.Material.SmoothPlastic
				panel.Transparency = 0
			end
		end })
	elseif id == "Farol" then
		P("Poste", Vector3.new(0.7, 7, 0.7), C(0, 3.5, 0), Color3.fromRGB(40, 40, 48), Enum.Material.Metal)
		local lamp = P("Luz", Vector3.new(1.8, 1.8, 1.8), C(0, 7.6, 0), Color3.fromRGB(255, 226, 150), Enum.Material.Neon)
		if not o.Ghost then
			light(lamp, 24, 1, Color3.fromRGB(255, 226, 160))
		end
	elseif id == "Fuente" then
		cyl("Base", 7.6, 1.2, C(0, 0.6, 0), Color3.fromRGB(190, 184, 172), Enum.Material.Marble)
		local w = cyl("Agua", 6.6, 0.3, C(0, 1.25, 0), Color3.fromRGB(80, 170, 230), Enum.Material.Glass)
		w.Transparency = 0.35
		cyl("Pilar", 1.4, 3, C(0, 2.4, 0), Color3.fromRGB(214, 204, 186), Enum.Material.Marble)
		cyl("Copa", 3.4, 0.4, C(0, 3.8, 0), Color3.fromRGB(214, 204, 186), Enum.Material.Marble)
		if not o.Ghost then
			local spout = P("Chorro", Vector3.new(0.5, 0.5, 0.5), C(0, 4.2, 0), Color3.new(1, 1, 1), Enum.Material.Glass)
			spout.Transparency = 1
			local pe = Instance.new("ParticleEmitter")
			pe.Rate = 30
			pe.Lifetime = NumberRange.new(0.8, 1.2)
			pe.Speed = NumberRange.new(7, 9)
			pe.SpreadAngle = Vector2.new(20, 20)
			pe.Acceleration = Vector3.new(0, -24, 0)
			pe.Size = NumberSequence.new(0.35, 0.1)
			pe.Color = ColorSequence.new(Color3.fromRGB(180, 225, 255))
			pe.Transparency = NumberSequence.new(0.2, 1)
			pe.Parent = spout
		end
	elseif id == "Trono" then
		P("Escalon", Vector3.new(7, 0.8, 6), C(0, 0.4, 0), Color3.fromRGB(120, 38, 56), Enum.Material.Fabric)
		P("Base", Vector3.new(5, 1.6, 4.4), C(0, 1.6, 0), GOLD, Enum.Material.Metal)
		P("Cojin", Vector3.new(4.2, 0.9, 3.6), C(0, 2.7, -0.1), Color3.fromRGB(150, 36, 60), Enum.Material.Fabric)
		P("Respaldo", Vector3.new(5, 8.6, 1), C(0, 6, 2.1), Color3.fromRGB(150, 36, 60), Enum.Material.Fabric)
		P("RespaldoMarco", Vector3.new(5.6, 9.2, 0.7), C(0, 6.2, 2.6), GOLD, Enum.Material.Metal)
		for _, sx in ipairs({ -2.8, 2.8 }) do
			P("Brazo", Vector3.new(0.9, 2.2, 4.2), C(sx, 3.4, -0.1), GOLD, Enum.Material.Metal)
			P("Pomo", Vector3.new(1.3, 1.3, 1.3), C(sx, 4.7, -1.8), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
			P("Pilar", Vector3.new(0.9, 9.6, 0.9), C(sx * 0.95, 5.6, 2.8), GOLD, Enum.Material.Metal)
			P("Punta", Vector3.new(1.4, 1.4, 1.4), C(sx * 0.95, 10.7, 2.8), Color3.fromRGB(110, 225, 255), Enum.Material.Neon, Enum.PartType.Ball)
		end
		P("Corona", Vector3.new(3, 1, 0.5), C(0, 11, 2.6), GOLD, Enum.Material.Metal)
		P("Gema", Vector3.new(1, 1, 0.6), C(0, 11.2, 2.3), Color3.fromRGB(255, 70, 110), Enum.Material.Neon, Enum.PartType.Ball)
		table.insert(seats, cf * C(0, 3.4, -0.2))
	elseif id == "Estatua" then
		P("Pedestal", Vector3.new(4.4, 1.6, 4.4), C(0, 0.8, 0), Color3.fromRGB(60, 58, 66), Enum.Material.Marble)
		P("PedestalOro", Vector3.new(4.8, 0.4, 4.8), C(0, 1.8, 0), GOLD, Enum.Material.Metal)
		P("Piernas", Vector3.new(2, 4, 1.4), C(0, 4, 0), GOLD, Enum.Material.Metal)
		P("Torso", Vector3.new(2.6, 3.4, 1.5), C(0, 7.7, 0), GOLD, Enum.Material.Metal)
		P("Cabeza", Vector3.new(1.7, 1.7, 1.7), C(0, 10.3, 0), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
		P("BrazoIzq", Vector3.new(0.9, 3.2, 0.9), C(-1.8, 7.9, 0), GOLD, Enum.Material.Metal)
		P("BrazoDer", Vector3.new(0.9, 3.2, 0.9), C(1.8, 9.6, 0) * CFrame.Angles(0, 0, math.rad(25)), GOLD, Enum.Material.Metal)
		local orb = P("Orbe", Vector3.new(1.6, 1.6, 1.6), C(2.6, 11.4, 0), Color3.fromRGB(255, 226, 140), Enum.Material.Neon, Enum.PartType.Ball)
		if not o.Ghost then
			light(orb, 16, 0.8, Color3.fromRGB(255, 220, 140))
		end
	elseif id == "Cristal" then
		P("Base", Vector3.new(0.8, 5, 5), C(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 50, 62), Enum.Material.Slate, Enum.PartType.Cylinder)
		P("BaseOro", Vector3.new(0.4, 5.6, 5.6), C(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
		local main = P("Cristal", Vector3.new(2.6, 5.6, 2.6), C(0, 6, 0) * CFrame.Angles(0, math.rad(45), math.rad(45)), Color3.fromRGB(120, 230, 255), Enum.Material.Neon)
		main.Transparency = 0.2
		for i = 1, 3 do
			local a = i / 3 * math.pi * 2
			local sh = P("Esquirla" .. i, Vector3.new(0.9, 2.4, 0.9), C(math.cos(a) * 2.4, 5.2 + i * 0.5, math.sin(a) * 2.4) * CFrame.Angles(math.rad(20 * i), a, math.rad(30)), Color3.fromRGB(190, 150, 255), Enum.Material.Neon)
			sh.Transparency = 0.25
		end
		if not o.Ghost then
			light(main, 22, 1, Color3.fromRGB(140, 220, 255))
			local pe = Instance.new("ParticleEmitter")
			pe.Rate = 8
			pe.Lifetime = NumberRange.new(1.5, 2.5)
			pe.Speed = NumberRange.new(0.5, 1.5)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Size = NumberSequence.new(0.35, 0)
			pe.LightEmission = 1
			pe.Color = ColorSequence.new(Color3.fromRGB(170, 235, 255), Color3.fromRGB(200, 160, 255))
			pe.Transparency = NumberSequence.new(0.1, 1)
			pe.Parent = main
		end
	end

	if id == "Estandarte" then
		local cloth = o.Accent or Color3.fromRGB(150, 40, 56)
		cyl("Base", 3, 0.5, C(0, 0.25, 0), GOLD, Enum.Material.Metal)
		P("Mastil", Vector3.new(0.5, 15, 0.5), C(0, 7.8, 0), GOLD, Enum.Material.Metal)
		P("Travesano", Vector3.new(6.4, 0.5, 0.5), C(0, 14.6, 0), GOLD, Enum.Material.Metal)
		P("Remate", Vector3.new(1, 1, 1), C(0, 15.8, 0), GOLD, Enum.Material.Metal, Enum.PartType.Ball)
		P("Tela", Vector3.new(5, 11, 0.3), C(0, 8.8, 0), cloth, Enum.Material.Fabric)
		P("TelaBorde", Vector3.new(5.2, 0.7, 0.4), C(0, 3.5, 0), GOLD, Enum.Material.Metal)
		P("TelaEmblema", Vector3.new(1.8, 1.8, 0.4), C(0, 9.5, -0.05) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Enum.Material.Neon)
	elseif id == "Chimenea" then
		P("Marco", Vector3.new(16, 11, 2), C(0, 5.5, 0.5), Color3.fromRGB(120, 108, 96), Enum.Material.Brick)
		P("Hueco", Vector3.new(9, 6.5, 2.2), C(0, 3.6, 0.1), Color3.fromRGB(26, 22, 22), Enum.Material.Slate)
		P("Repisa", Vector3.new(18, 1, 3), C(0, 11.4, 0), GOLD, Enum.Material.Wood)
		P("Leños", Vector3.new(5, 0.9, 1.2), C(0, 1.3, -0.2), Color3.fromRGB(86, 56, 36), Enum.Material.Wood)
		local fire = P("Fuego", Vector3.new(3, 1, 1.2), C(0, 2.1, -0.2), Color3.fromRGB(255, 130, 40), Enum.Material.Neon)
		fire.CanCollide = false
		fire.Transparency = 0.3
		if not o.Ghost then
			local f = Instance.new("Fire")
			f.Size, f.Heat = 6, 8
			f.Parent = fire
			light(fire, 28, 1.3, Color3.fromRGB(255, 150, 80))
			local fon = true
			table.insert(prompts, { Part = m:FindFirstChild("Marco") :: BasePart, Action = "Encender / apagar", Object = "Chimenea", Fn = function()
				fon = not fon
				f.Enabled = fon
				fire.Transparency = if fon then 0.3 else 1
				local l = fire:FindFirstChildOfClass("PointLight")
				if l then
					l.Enabled = fon
				end
			end })
		end
	end

	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if o.Ghost then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Transparency = math.max(d.Transparency, 0.55)
			elseif d.Name == "Alfombra" or id == "Alfombra" then
				d.CanCollide = false
			end
		end
	end
	if o.Interactive and not o.Ghost then
		for _, pr in ipairs(prompts) do
			local pp = Instance.new("ProximityPrompt")
			pp.ActionText = pr.Action
			pp.ObjectText = pr.Object
			pp.KeyboardKeyCode = Enum.KeyCode.E
			pp.HoldDuration = 0.2
			pp.MaxActivationDistance = 8
			pp.RequiresLineOfSight = false
			pp.Parent = pr.Part
			pp.Triggered:Connect(function(pl: Player)
				if o.Owner and pl ~= o.Owner then
					if HouseFurniture.Notify then
						HouseFurniture.Notify(pl, "Solo el dueño puede usar esto.")
					end
					return
				end
				pr.Fn(pl)
			end)
		end
		for _, scf in ipairs(seats) do
			HouseFurniture.MakeSeat(m, scf)
		end
	end
	m.Parent = parent
	return m
end

return HouseFurniture
