--!strict
--[[
    ArenaStyler (ModuleScript) -> ServerScriptService > Services > ArenaStyler
    Diseño de la ARENA CENTRAL (se aplica encima de lo que crea ProjectBootstrapper; no lo modifica).

    FIJO (siempre):
      - 4 campamentos de facción detrás de cada puente (cristal que cura 1,5% de vida y energía cada 0,5 s a los de esa facción).
      - 8 altares bajos bajo las piedras Metin (planos: no tocan la piedra ni su spawn).
      - Anillos y obeliscos alrededor de la plataforma del jefe (planos: no tocan el spawn del jefe).
      - 4 SANTUARIOS de poder en las diagonales: se capturan quedándose cerca 8 s (si hay dos facciones, queda disputado).
        Con el evento abierto, la facción dueña recibe EN LA ARENA:
          Santuario de Fuerza   +8% de daño          (atributo de jugador ShrineDmg,    lo lee DamageService)
          Santuario de Vigor    +10% de vida máxima  (se aplica aquí mismo al Humanoid)
          Santuario de Aliento  +40% regeneración de energía (ShrineEnergy, lo lee EnergyRegenService)
          Santuario de Fortuna  +15% de XP           (ShrineXp,     lo lee RewardService)
        Al cerrarse el evento o salir de la arena, los bonus se quitan solos.
      - Dibujo del suelo opcional (CityAssets: Arena_floor).

    DISEÑO ÚNICO: Coliseo de las Cuatro Naciones (sin rotación de temas, sin rocas ni cascadas).
      - GRADAS: 5 niveles de 5 studs por cada lado de la arena, divididas en dos alas (a cada lado del puente).
        Cada ala tiene muros separadores a los extremos y hacia el puente, así que NO se puede pasar a la grada de otra facción.
      - ENTRADAS: portales con ProximityPrompt (solo para la facción dueña de la grada):
          · en el puente, justo antes de la compuerta  -> "Ir a la grada"
          · en cada campamento (dentro de la arena)     -> "Subir a la grada"
          · en la grada                                  -> "Bajar a la arena" (si te quedan vidas y el evento está abierto)
                                                           "Volver a la ciudad" (siempre)
      - Quien pierde las 5 vidas va directo a su grada (ArenaService/DeathService) y no puede entrar a la arena hasta el próximo evento.
      - Con el evento cerrado todos salen de las gradas hacia su ciudad (lo hace ArenaService).
      - Datos para la interfaz: Workspace attr "Shrine_<Id>" = "dueño|retador|progreso%" y atributo de jugador "ShrineBuffs".
    ENABLED = false lo apaga y deja la arena como estaba (los temas quitan lo que pusieron).
]]
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GB = require(ReplicatedStorage.Modules.GameBalance)

local ENABLED = true
local MAP_NAME = "Map_WC3_Style"

local Services = script.Parent
local Net = require(Services:WaitForChild("Net"))
local CityAssets = require(Services:WaitForChild("CityAssets"))
local NotifyRemote = Net.Get("Notify")

local FLOOR_TOP = 12
local ARENA_HALF = 750
local CAMP_DIST = 660 -- centro del campamento respecto al centro de la arena
local CAMP_RADIUS = 26
local SHRINE_RADIUS = 18
local CAPTURE_SECONDS = 8
local SHRINE_POS = 396 -- las 4 diagonales: (±396, ±396)

local BUFF_DMG = 1.08
local BUFF_HP = 1.10
local BUFF_ENERGY = 1.40
local BUFF_XP = 1.15

-- CAMPO PROTECTOR: al capturar, el santuario crea una cúpula con vida que solo otra facción puede romper.
-- Vida = vida de un mob de nivel máximo (GB.MobHp) × el multiplicador del santuario (más valioso = más vida).
-- Un grupo de ~6 debería tardar 30-40 s; uno solo, más de 2 min. Ajusta estos números tras probar.
local FIELD_HP_MULT: { [string]: number } = { Aliento = 10, Fortuna = 14, Vigor = 18, Fuerza = 20 }
local FIELD_DIAMETER = 46
local FIELD_REGEN_DELAY = 10 -- s sin recibir golpes para empezar a recuperar
local FIELD_REGEN_PCT = 0.03 -- de la vida máxima por segundo

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

---------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------
type LaneDef = { Faction: string, Out: Vector3, Kanji: string, Base: Color3, Glow: Color3, Cloth: Color3, Name: string }
local LANES: { LaneDef } = {
	{ Faction = "Saiyan", Out = Vector3.new(0, 0, -1), Kanji = "龍", Base = C(46, 59, 82), Glow = C(79, 209, 255), Cloth = C(255, 138, 31), Name = "SAIYAN" },
	{ Faction = "Shinobi", Out = Vector3.new(-1, 0, 0), Kanji = "忍", Base = C(122, 82, 50), Glow = C(232, 166, 64), Cloth = C(96, 160, 86), Name = "SHINOBI" },
	{ Faction = "Pirate", Out = Vector3.new(1, 0, 0), Kanji = "海", Base = C(91, 65, 48), Glow = C(255, 190, 90), Cloth = C(60, 120, 190), Name = "PIRATA" },
	{ Faction = "Shinigami", Out = Vector3.new(0, 0, 1), Kanji = "死", Base = C(200, 204, 214), Glow = C(126, 200, 255), Cloth = C(140, 110, 220), Name = "SHINIGAMI" },
}
local FACTION_COLOR: { [string]: Color3 } = {}
for _, l in ipairs(LANES) do
	FACTION_COLOR[l.Faction] = l.Cloth
end

type ShrineDef = { Id: string, Name: string, Color: Color3, Text: string, X: number, Z: number }
local SHRINES: { ShrineDef } = {
	{ Id = "Fuerza", Name = "Santuario de Fuerza", Color = C(255, 90, 60), Text = "+8% daño", X = -SHRINE_POS, Z = -SHRINE_POS },
	{ Id = "Vigor", Name = "Santuario de Vigor", Color = C(90, 230, 120), Text = "+10% vida máx.", X = SHRINE_POS, Z = -SHRINE_POS },
	{ Id = "Aliento", Name = "Santuario de Aliento", Color = C(90, 180, 255), Text = "+40% regen. de energía", X = -SHRINE_POS, Z = SHRINE_POS },
	{ Id = "Fortuna", Name = "Santuario de Fortuna", Color = C(255, 215, 90), Text = "+15% XP", X = SHRINE_POS, Z = SHRINE_POS },
}

local ARENA_NAME = "Coliseo de las Cuatro Naciones"

-- Gradas
local STAND_TIERS = 5
local STAND_RISE = 5
local STAND_DEPTH = 12
local STAND_START = ARENA_HALF + 2
local WING_IN = 86 -- el ala empieza a esta distancia del eje del puente
local WING_OUT = 745
local STAND_TOP = FLOOR_TOP + STAND_TIERS * STAND_RISE

---------------------------------------------------------------------
-- Helpers de partes
---------------------------------------------------------------------
local built = 0
local function breathe()
	built += 1
	if built % 60 == 0 then
		task.wait()
	end
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.Parent = parent
	breathe()
	return p
end

-- cilindro vertical: pos = centro
local function cylV(parent: Instance, name: string, pos: Vector3, h: number, d: number, color: Color3, mat: Enum.Material, solid: boolean?): Part
	local p = part(parent, name, Vector3.new(h, d, d), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, mat, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, pos: Vector3, d: number, color: Color3, mat: Enum.Material): Part
	local p = part(parent, name, Vector3.new(d, d, d), CFrame.new(pos), color, mat, false)
	p.Shape = Enum.PartType.Ball
	return p
end

local function folder(name: string, parent: Instance): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function light(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

local function emitter(p: BasePart, color: Color3, rate: number, speed: number, life: number, size: number, accel: Vector3, spread: number, emission: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.6, speed)
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Size = NumberSequence.new(size)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.LightEmission = emission
	e.Acceleration = accel
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Parent = p
end

local function billboard(p: BasePart, text: string, color: Color3, offsetY: number, width: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 56)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 320
	gui.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextColor3 = color
	tl.TextStrokeTransparency = 0.3
	tl.Font = Enum.Font.GothamBold
	tl.TextSize = 17
	tl.TextWrapped = true
	tl.Parent = gui
	return tl
end

local function kanjiSign(p: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 30
	sg.LightInfluence = 0
	sg.Parent = p
	local tl = Instance.new("TextLabel")
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Text = text
	tl.TextScaled = true
	tl.TextColor3 = color
	tl.Font = Enum.Font.GothamBlack
	tl.Parent = sg
end

local function notifyAll(text: string)
	NotifyRemote:FireAllClients(text)
end

-- carga perezosa de ArenaService (evita ciclos al arrancar)
local ArenaServiceMod: any = nil
local function arenaService(): any
	if ArenaServiceMod == nil then
		local ok, m = pcall(require, Services:WaitForChild("ArenaService"))
		ArenaServiceMod = if ok then m else false
	end
	return ArenaServiceMod
end

local function tellPlayer(pl: Player, text: string)
	NotifyRemote:FireClient(pl, text)
end

local function teleportTo(pl: Player, pos: Vector3)
	local root = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.new(pos)
	end
end

-- Portal: aro de luz + cartel + ProximityPrompt. onUse solo se llama si el jugador es de la facción indicada.
local function makePad(parent: Instance, name: string, pos: Vector3, color: Color3, title: string, action: string, key: Enum.KeyCode, faction: string, onUse: (Player) -> ())
	local p = cylV(parent, name, pos, 0.4, 7, color, Enum.Material.Neon, false)
	p.Transparency = 0.35
	local label = billboard(p, title, color:Lerp(C(255, 255, 255), 0.4), 4, 200)
	label.TextSize = 15
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 1, 0)
	att.Parent = p
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = title
	pp.KeyboardKeyCode = key
	pp.HoldDuration = 0.6
	pp.MaxActivationDistance = 9
	pp.RequiresLineOfSight = false
	pp.Parent = att
	pp.Triggered:Connect(function(pl: Player)
		if pl:GetAttribute("Faction") ~= faction then
			tellPlayer(pl, "Este acceso es de la facción " .. faction .. ".")
			return
		end
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		onUse(pl)
	end)
end

local function goToGrada(pl: Player)
	local a = arenaService()
	if a and a.IsOpen and a.IsOpen() and a.SendToGrada then
		a.SendToGrada(pl)
	else
		tellPlayer(pl, "Las gradas solo abren con el evento.")
	end
end

---------------------------------------------------------------------
-- Estado
---------------------------------------------------------------------
type Camp = { Faction: string, Pos: Vector3 }
type Shrine = {
	Def: ShrineDef, Pos: Vector3, Owner: string?, Challenger: string?, Progress: number,
	Ring: Part, Crystal: Part, Label: TextLabel, Shown: string,
	Field: Model?, FieldHum: Humanoid?, FieldHitAt: number, FieldLastHp: number,
}
local camps: { Camp } = {}
local shrines: { Shrine } = {}
local arenaFolder: Instance? = nil
local styleRoot: Folder? = nil

---------------------------------------------------------------------
-- FIJO 1: campamentos
---------------------------------------------------------------------
local function buildCamp(parent: Instance, lane: LaneDef)
	local dir = -lane.Out
	local c = lane.Out * CAMP_DIST + Vector3.new(0, FLOOR_TOP, 0)
	local cf0 = CFrame.lookAt(c, c + dir)
	local function at(lx: number, ly: number, lz: number): CFrame
		return cf0 * CFrame.new(lx, ly, lz)
	end
	local f = Instance.new("Folder")
	f.Name = "Campamento_" .. lane.Faction
	f.Parent = parent

	local pad = part(f, "Base", Vector3.new(130, 0.6, 76), at(0, 0.3, 0), lane.Base, Enum.Material.Slate, true)
	pad.Name = "Base"
	cylV(f, "Emblema", cf0.Position + Vector3.new(0, 0.7, 0) + cf0.LookVector * 14, 0.2, 44, lane.Glow, Enum.Material.Neon).Transparency = 0.45

	-- cristal que cura
	local crystalPos = (cf0 * CFrame.new(0, 0, 0)).Position + Vector3.new(0, 0, 0)
	cylV(f, "Pedestal", crystalPos + Vector3.new(0, 2.2, 0), 3, 9, lane.Base:Lerp(C(255, 255, 255), 0.25), Enum.Material.Marble, true)
	local crystal = ball(f, "Cristal_Curacion", crystalPos + Vector3.new(0, 8.5, 0), 5.5, lane.Glow, Enum.Material.Neon)
	crystal.Transparency = 0.15
	light(crystal, lane.Glow, 34, 1.4)
	emitter(crystal, lane.Glow, 8, 5, 2.5, 0.5, Vector3.new(0, 2, 0), 180, 0.8)
	billboard(crystal, "CAMPAMENTO " .. lane.Name, lane.Cloth:Lerp(C(255, 255, 255), 0.35), 4.5, 240)
	table.insert(camps, { Faction = lane.Faction, Pos = crystalPos })

	-- banderas
	for _, sx in ipairs({ -1, 1 }) do
		local pole = part(f, "Asta", Vector3.new(1.2, 26, 1.2), at(sx * 52, 13.6, -6), C(60, 60, 68), Enum.Material.Metal, true)
		pole.Name = "Asta"
		local cloth = part(f, "Bandera", Vector3.new(0.4, 9, 13), at(sx * 52 + sx * 0.7, 21, -6), lane.Cloth, Enum.Material.Fabric, false)
		cloth.Name = "Bandera"
		kanjiSign(cloth, Enum.NormalId.Right, lane.Kanji, C(255, 255, 255))
		kanjiSign(cloth, Enum.NormalId.Left, lane.Kanji, C(255, 255, 255))
		ball(f, "Remate", at(sx * 52, 27.2, -6).Position, 2, lane.Glow, Enum.Material.Neon)
	end
	-- portal a la grada de la facción (detrás del cristal, hacia el muro)
	makePad(f, "Portal_Grada", at(0, 0.5, 38).Position, lane.Glow, "GRADA " .. lane.Name, "Subir a la grada", Enum.KeyCode.E, lane.Faction, goToGrada)
	-- toldo al fondo (lado del puente)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part(f, "Poste_Toldo", Vector3.new(1, 10, 1), at(sx * 30, 5.6, 22 + sz * 8), lane.Base:Lerp(C(0, 0, 0), 0.25), Enum.Material.Wood, true)
		end
		part(f, "Toldo", Vector3.new(26, 0.8, 22), at(sx * 30, 10.6, 22), lane.Cloth, Enum.Material.Fabric, false)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "Caja", Vector3.new(4, 4, 4), at(sx * 30, 2.6, 22), lane.Base:Lerp(C(120, 90, 60), 0.5), Enum.Material.WoodPlanks, true)
	end
end

---------------------------------------------------------------------
-- FIJO 2: altares Metin, jefe, suelo
---------------------------------------------------------------------
local function buildAltars(parent: Instance)
	local f = Instance.new("Folder")
	f.Name = "Altares_Metin"
	f.Parent = parent
	for _, m in ipairs(CollectionService:GetTagged("MetinStoneSpawn")) do
		if m:IsA("BasePart") then
			local p = Vector3.new(m.Position.X, FLOOR_TOP, m.Position.Z)
			cylV(f, "Altar_Base", p + Vector3.new(0, 0.3, 0), 0.6, 26, C(88, 92, 108), Enum.Material.Slate, false)
			cylV(f, "Altar_Anillo", p + Vector3.new(0, 0.72, 0), 0.16, 22, C(79, 209, 255), Enum.Material.Neon, false).Transparency = 0.3
			for k = 0, 3 do
				local a = k * math.pi / 2 + math.pi / 4
				local tp = p + Vector3.new(math.cos(a) * 12, 0, math.sin(a) * 12)
				cylV(f, "Antorcha_Poste", tp + Vector3.new(0, 3.6, 0), 7.2, 0.9, C(70, 66, 60), Enum.Material.Wood, true)
				local fl = ball(f, "Antorcha_Fuego", tp + Vector3.new(0, 7.8, 0), 2.2, C(255, 150, 50), Enum.Material.Neon)
				light(fl, C(255, 170, 80), 16, 0.9)
			end
		end
	end
end

local function buildBossDecor(parent: Instance)
	local f = Instance.new("Folder")
	f.Name = "Plataforma_Titan"
	f.Parent = parent
	cylV(f, "Anillo_Oro_1", Vector3.new(0, FLOOR_TOP + 0.2, 0), 0.16, 276, C(224, 176, 74), Enum.Material.Neon, false).Transparency = 0.45
	cylV(f, "Anillo_Oro_2", Vector3.new(0, FLOOR_TOP + 0.22, 0), 0.16, 246, C(255, 120, 80), Enum.Material.Neon, false).Transparency = 0.55
	for k = 0, 7 do
		local a = k * math.pi / 4 + math.pi / 8
		local p = Vector3.new(math.cos(a) * 138, FLOOR_TOP, math.sin(a) * 138)
		local ob = part(f, "Obelisco", Vector3.new(4, 12, 4), CFrame.new(p + Vector3.new(0, 6, 0)) * CFrame.Angles(0, a, 0), C(70, 72, 90), Enum.Material.Basalt, true)
		ob.Name = "Obelisco"
		part(f, "Obelisco_Runa", Vector3.new(0.5, 7, 1.4), CFrame.new(p + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.05), C(255, 120, 80), Enum.Material.Neon, false)
	end
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = Vector3.new(math.cos(a) * 158, FLOOR_TOP, math.sin(a) * 158)
		part(f, "Brasero_Base", Vector3.new(5, 3, 5), CFrame.new(p + Vector3.new(0, 1.5, 0)), C(60, 58, 66), Enum.Material.Granite, true)
		local fl = ball(f, "Brasero_Fuego", p + Vector3.new(0, 4.2, 0), 3.4, C(255, 110, 60), Enum.Material.Neon)
		light(fl, C(255, 130, 70), 26, 1.1)
		emitter(fl, C(255, 150, 70), 10, 6, 1.6, 1, Vector3.new(0, 8, 0), 25, 0.9)
	end
end

local function buildFloorDecor(parent: Instance, arenaPart: BasePart?)
	local f = Instance.new("Folder")
	f.Name = "Suelo"
	f.Parent = parent
	-- diagonales doradas
	for _, s in ipairs({ 1, -1 }) do
		part(f, "Diagonal", Vector3.new(26, 0.12, 2000), CFrame.new(0, FLOOR_TOP + 0.14, 0) * CFrame.Angles(0, math.rad(45 * s), 0), C(224, 176, 74), Enum.Material.Neon, false).Transparency = 0.72
	end
	-- dibujo del suelo (opcional)
	local img = CityAssets.Get("Arena", "floor")
	if img and arenaPart then
		local old = arenaPart:FindFirstChild("Arena_Dibujo")
		if old then
			old:Destroy()
		end
		local d = Instance.new("Decal")
		d.Name = "Arena_Dibujo"
		d.Face = Enum.NormalId.Top
		d.Texture = img
		d.Parent = arenaPart
	end
end

---------------------------------------------------------------------
-- FIJO 3: santuarios
---------------------------------------------------------------------
local function buildShrine(parent: Instance, def: ShrineDef)
	local f = Instance.new("Folder")
	f.Name = "Santuario_" .. def.Id
	f.Parent = parent
	local base = Vector3.new(def.X, FLOOR_TOP, def.Z)
	cylV(f, "Plataforma", base + Vector3.new(0, 0.4, 0), 0.8, 40, C(70, 72, 90), Enum.Material.Basalt, true)
	local ring = cylV(f, "Anillo", base + Vector3.new(0, 0.9, 0), 0.16, 36, C(150, 150, 160), Enum.Material.Neon, false)
	ring.Transparency = 0.35
	cylV(f, "Anillo_Interior", base + Vector3.new(0, 0.95, 0), 0.12, 20, def.Color, Enum.Material.Neon, false).Transparency = 0.6
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = base + Vector3.new(math.cos(a) * 15, 0, math.sin(a) * 15)
		cylV(f, "Pilar", p + Vector3.new(0, 5.4, 0), 9, 2.4, C(96, 98, 118), Enum.Material.Granite, true)
		ball(f, "Pilar_Luz", p + Vector3.new(0, 10.4, 0), 2, def.Color, Enum.Material.Neon)
	end
	cylV(f, "Pedestal", base + Vector3.new(0, 2.2, 0), 3, 6, C(110, 112, 130), Enum.Material.Marble, true)
	local crystal = ball(f, "Cristal", base + Vector3.new(0, 9, 0), 5.5, def.Color, Enum.Material.Neon)
	crystal.Transparency = 0.1
	light(crystal, def.Color, 40, 1.3)
	emitter(crystal, def.Color, 6, 4, 2.5, 0.5, Vector3.new(0, 2, 0), 180, 0.8)
	local label = billboard(crystal, def.Name .. "\n" .. def.Text .. " · Libre", C(255, 255, 255), 6, 260)
	table.insert(shrines, {
		Def = def, Pos = base, Owner = nil, Challenger = nil, Progress = 0,
		Ring = ring, Crystal = crystal, Label = label, Shown = "",
		Field = nil, FieldHum = nil, FieldHitAt = 0, FieldLastHp = 0,
	})
end

---------------------------------------------------------------------
-- TEMAS
---------------------------------------------------------------------
local function buildStands(parent: Instance)
	local gradaFolder = Instance.new("Folder")
	gradaFolder.Name = "Gradas"
	gradaFolder.Parent = parent
	local totalDepth = STAND_TIERS * STAND_DEPTH
	for _, l in ipairs(LANES) do
		local out = l.Out
		local along = Vector3.new(-out.Z, 0, out.X)
		local lf = Instance.new("Folder")
		lf.Name = "Grada_" .. l.Faction
		lf.Parent = gradaFolder
		for _, sign in ipairs({ -1, 1 }) do
			local len = WING_OUT - WING_IN
			local mid = sign * (WING_IN + WING_OUT) / 2
			-- relleno entre el borde del suelo de la arena y la primera grada (antes quedaba una franja hueco: se caía al vacío)
			do
				local fd0, fd1 = ARENA_HALF - 6, STAND_START + 4
				local fc = out * ((fd0 + fd1) / 2) + along * mid
				part(lf, "Relleno_Grada", Vector3.new(len + 6, FLOOR_TOP + 8, fd1 - fd0), CFrame.lookAt(Vector3.new(fc.X, (FLOOR_TOP - 8) / 2, fc.Z), Vector3.new(fc.X, (FLOOR_TOP - 8) / 2, fc.Z) + out), C(70, 72, 90), Enum.Material.Concrete, true)
			end
			for tier = 1, STAND_TIERS do
				local d0 = STAND_START + (tier - 1) * STAND_DEPTH
				local topY = FLOOR_TOP + tier * STAND_RISE
				local c = out * (d0 + STAND_DEPTH / 2) + along * mid
				local h = topY + 6
				local cf = CFrame.lookAt(Vector3.new(c.X, (topY - 6) / 2, c.Z), Vector3.new(c.X, (topY - 6) / 2, c.Z) + out)
				part(lf, "Grada", Vector3.new(len, h, STAND_DEPTH), cf, C(204, 200, 190), Enum.Material.Marble, true)
				-- franja de color de la facción en el borde de cada nivel
				local sc = out * (d0 + 0.5) + along * mid
				local sp = part(lf, "Franja", Vector3.new(len, 0.25, 1), CFrame.lookAt(Vector3.new(sc.X, topY + 0.13, sc.Z), Vector3.new(sc.X, topY + 0.13, sc.Z) + out), l.Cloth, Enum.Material.SmoothPlastic, false)
				sp.Name = "Franja"
			end
			-- baranda trasera (cristal tintado, sólida)
			local bc = out * (STAND_START + totalDepth + 0.5) + along * mid
			-- muy alta (40 studs) y gruesa: no se puede saltar por encima ni caer al vacío (antes 12, se saltaba)
			local back = part(lf, "Baranda", Vector3.new(len + 3, 40, 4), CFrame.lookAt(Vector3.new(bc.X, STAND_TOP + 20, bc.Z), Vector3.new(bc.X, STAND_TOP + 20, bc.Z) + out), l.Cloth, Enum.Material.Glass, true)
			back.Transparency = 0.7
			-- muros separadores: extremo (hacia la grada de la facción vecina) e interior (hacia el puente)
			for _, edge in ipairs({ sign * (WING_OUT + 1), sign * (WING_IN - 1) }) do
				local wc = out * (STAND_START + totalDepth / 2 + 1) + along * edge
				-- lookAt hacia 'along': el eje Z local (grosor 3) queda sobre 'along', el X local (largo) sobre 'out'
				local wall = part(lf, "Muro_Separador", Vector3.new(totalDepth + 4, STAND_TOP + 6 + 30, 4), CFrame.lookAt(Vector3.new(wc.X, (STAND_TOP + 30 - 6) / 2, wc.Z), Vector3.new(wc.X, (STAND_TOP + 30 - 6) / 2, wc.Z) + along), C(90, 90, 104), Enum.Material.Concrete, true)
				local trim = part(lf, "Muro_Franja", Vector3.new(totalDepth + 4.2, 1.2, 4.2), wall.CFrame * CFrame.new(0, (STAND_TOP + 36) / 2 - 0.6, 0), l.Cloth, Enum.Material.Neon, false)
				trim.Transparency = 0.2
			end
			-- zona de la grada (invisible; la usa ArenaService)
			local zc = out * (STAND_START + totalDepth / 2) + along * mid
			local zone = part(lf, "Zona_Grada", Vector3.new(len, 70, totalDepth + 4), CFrame.lookAt(Vector3.new(zc.X, 35, zc.Z), Vector3.new(zc.X, 35, zc.Z) + out), l.Cloth, Enum.Material.SmoothPlastic, false)
			zone.Transparency = 1
			zone.CanQuery = false
			zone:SetAttribute("Faction", l.Faction)
			CollectionService:AddTag(zone, "ZoneGrada")
			-- punto de aparición en la grada (nivel 3, centro del ala)
			local spawnPos = out * (STAND_START + 2.5 * STAND_DEPTH) + along * (sign * 330) + Vector3.new(0, FLOOR_TOP + 3 * STAND_RISE + 3.2, 0)
			local sp = part(lf, "Aparicion_Grada", Vector3.new(4, 1, 4), CFrame.new(spawnPos), l.Cloth, Enum.Material.SmoothPlastic, false)
			sp.Transparency = 1
			sp:SetAttribute("Faction", l.Faction)
			CollectionService:AddTag(sp, "GradaSpawn")
			-- portales dentro de la grada (nivel 3, junto al muro interior)
			local px = out * (STAND_START + 2.5 * STAND_DEPTH)
			local py = FLOOR_TOP + 3 * STAND_RISE + 0.3
			makePad(lf, "Portal_Ciudad", px + along * (sign * (WING_IN + 22)) + Vector3.new(0, py, 0), C(255, 255, 255), "VOLVER A LA CIUDAD", "Volver a la ciudad", Enum.KeyCode.E, l.Faction, function(pl: Player)
				local a = arenaService()
				if a and a.SendToCity then
					a.SendToCity(pl)
				end
			end)
			makePad(lf, "Portal_Arena", px + along * (sign * (WING_IN + 40)) + Vector3.new(0, py, 0), l.Glow, "BAJAR A LA ARENA", "Bajar a la arena", Enum.KeyCode.F, l.Faction, function(pl: Player)
				local a = arenaService()
				if a and a.CanEnter and a.CanEnter(pl) then
					teleportTo(pl, out * (CAMP_DIST - 34) + Vector3.new(0, FLOOR_TOP + 3.5, 0))
				else
					tellPlayer(pl, "No puedes bajar: sin vidas de arena o el evento está cerrado.")
				end
			end)
			-- banderas sobre el muro del extremo
			local fx = out * (STAND_START + totalDepth - 8) + along * (sign * (WING_OUT - 20))
			local fy = STAND_TOP + 11
			part(lf, "Asta", Vector3.new(1.2, 22, 1.2), CFrame.new(fx.X, fy, fx.Z), C(70, 70, 80), Enum.Material.Metal, false)
			local cloth = part(lf, "Bandera", Vector3.new(10, 8, 0.4), CFrame.lookAt(Vector3.new(fx.X, fy + 6, fx.Z) + along * (sign * -5.6), Vector3.new(fx.X, fy + 6, fx.Z) + along * (sign * -5.6) + out), l.Cloth, Enum.Material.Fabric, false)
			kanjiSign(cloth, Enum.NormalId.Front, l.Kanji, C(255, 255, 255))
			kanjiSign(cloth, Enum.NormalId.Back, l.Kanji, C(255, 255, 255))
		end
		-- portal de entrada en el puente, antes de la compuerta
		local bp = out * 800 + along * 36 + Vector3.new(0, FLOOR_TOP + 0.3, 0)
		makePad(lf, "Portal_Puente", bp, l.Glow, "GRADA " .. l.Name, "Ir a la grada", Enum.KeyCode.E, l.Faction, goToGrada)
	end
	-- ESQUINAS: entre el extremo de una grada y el de la vecina quedaba un cuadro abierto hacia afuera (los muros separadores no se tocan).
	-- Se rellena con un bloque macizo del suelo al techo de los muros, así no hay hueco ni por donde salir de las gradas.
	local cornerFrom = WING_OUT + 2 -- desde el muro separador del extremo (se pisan 1-2 studs, sin hueco)
	local cornerSize = (STAND_START + totalDepth + 8) - cornerFrom
	local cornerCenter = cornerFrom + cornerSize / 2
	local cornerH = STAND_TOP + 30 + 6 -- hasta la altura de los muros (STAND_TOP + 30) más el fondo enterrado
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cp = Vector3.new(sx * cornerCenter, (STAND_TOP + 30 - 6) / 2, sz * cornerCenter)
			part(gradaFolder, "Esquina_Maciza", Vector3.new(cornerSize, cornerH, cornerSize), CFrame.new(cp), C(176, 172, 164), Enum.Material.Marble, true)
			part(gradaFolder, "Esquina_Franja", Vector3.new(cornerSize + 0.4, 1.2, cornerSize + 0.4), CFrame.new(cp.X, STAND_TOP + 30 - 0.6, cp.Z), C(224, 176, 74), Enum.Material.Metal, false)
		end
	end
end

local function lanterns(parent: Instance, rng: Random, count: number, radius: number, y0: number, y1: number)
	for _ = 1, count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(150, radius)
		local l = ball(parent, "Farolillo", Vector3.new(math.cos(a) * r, rng:NextNumber(y0, y1), math.sin(a) * r), rng:NextNumber(2.5, 4), C(255, 205, 110), Enum.Material.Neon)
		if rng:NextNumber() < 0.3 then
			light(l, C(255, 205, 110), 28, 0.9)
		end
	end
end

local function themeColiseo(parent: Folder)
	local rng = Random.new(1001)
	buildStands(parent)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local p = Vector3.new(sx * 800, 0, sz * 800)
			part(parent, "Torre_Esquina", Vector3.new(38, 76, 38), CFrame.new(p.X, 32, p.Z), C(176, 172, 164), Enum.Material.Marble, true)
			part(parent, "Torre_Remate", Vector3.new(44, 4, 44), CFrame.new(p.X, 72, p.Z), C(224, 176, 74), Enum.Material.Metal, true)
			local fl = ball(parent, "Torre_Fuego", p + Vector3.new(0, 80, 0), 8, C(255, 130, 60), Enum.Material.Neon)
			light(fl, C(255, 150, 80), 60, 1.3)
		end
	end
	-- anillo de energía en el cielo
	local n = 40
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		local p = Vector3.new(math.cos(a) * 980, 240, math.sin(a) * 980)
		part(parent, "Anillo_Cielo", Vector3.new(120, 4, 5), CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), C(255, 210, 90), Enum.Material.Neon, false).Transparency = 0.35
	end
	lanterns(parent, rng, 26, 700, 40, 80)
end

---------------------------------------------------------------------
-- Aplicar el diseño (una sola vez)
---------------------------------------------------------------------
local function applyDesign(root: Folder)
	local tf = folder("Coliseo", root)
	local ok, err = pcall(themeColiseo, tf)
	if not ok then
		warn("[ArenaStyler] Error en el Coliseo: " .. tostring(err))
	end
	Workspace:SetAttribute("ArenaTheme", ARENA_NAME)
end

---------------------------------------------------------------------
-- Santuarios, bonus y campamentos (bucle cada 0,5 s)
---------------------------------------------------------------------
local EnergyMod: any = nil
local function energyService(): any
	if EnergyMod == nil then
		local ok, m = pcall(require, Services:WaitForChild("EnergyRegenService"))
		EnergyMod = if ok then m else false
	end
	return EnergyMod
end

local function rootOf(pl: Player): (BasePart?, Humanoid?)
	local ch = pl.Character
	if not ch then
		return nil, nil
	end
	local r = ch:FindFirstChild("HumanoidRootPart")
	local h = ch:FindFirstChildOfClass("Humanoid")
	if r and r:IsA("BasePart") and h and h.Health > 0 then
		return r, h
	end
	return nil, nil
end

local function setHpBuff(pl: Player, hum: Humanoid, mult: number)
	local ch = pl.Character
	if not ch then
		return
	end
	local base = ch:GetAttribute("ShrineHpBase") :: number?
	local applied = ch:GetAttribute("ShrineHpApplied") :: number?
	if mult > 1 then
		if base == nil or applied == nil or hum.MaxHealth ~= applied then
			base = hum.MaxHealth -- StatService pudo cambiarla (nivel): partimos de la actual
		end
		local newMax = math.floor((base :: number) * mult)
		if hum.MaxHealth ~= newMax then
			local ratio = hum.Health / math.max(1, hum.MaxHealth)
			hum.MaxHealth = newMax
			hum.Health = newMax * ratio
		end
		ch:SetAttribute("ShrineHpBase", base)
		ch:SetAttribute("ShrineHpApplied", newMax)
	elseif base ~= nil and applied ~= nil then
		if hum.MaxHealth == applied then
			hum.MaxHealth = base
			hum.Health = math.min(hum.Health, base)
		end
		ch:SetAttribute("ShrineHpBase", nil)
		ch:SetAttribute("ShrineHpApplied", nil)
	end
end

local function clearBuffs(pl: Player)
	pl:SetAttribute("ShrineDmg", nil)
	pl:SetAttribute("ShrineEnergy", nil)
	pl:SetAttribute("ShrineXp", nil)
	pl:SetAttribute("ShrineBuffs", nil)
	local _, hum = rootOf(pl)
	if hum then
		setHpBuff(pl, hum, 1)
	end
end

---------------------------------------------------------------------
-- Campo protector (cúpula con vida, apuntable)
---------------------------------------------------------------------
local RewardMod: any = nil
local function forgetDamage(model: Model)
	if RewardMod == nil then
		local ok, m = pcall(require, Services:WaitForChild("RewardService"))
		RewardMod = if ok then m else false
	end
	if RewardMod and RewardMod.Forget then
		RewardMod.Forget(model)
	end
end

local function fieldHpFor(id: string): number
	return math.floor(GB.MobHp(GB.MAX_LEVEL) * (FIELD_HP_MULT[id] or 12))
end

local function removeField(s: Shrine, burst: boolean)
	local m = s.Field
	if m then
		local root = m.PrimaryPart
		if burst and root then
			local fx = Instance.new("Part")
			fx.Anchored, fx.CanCollide, fx.CanQuery, fx.CanTouch, fx.Shape = true, false, false, false, Enum.PartType.Ball
			fx.Material, fx.Color, fx.Transparency = Enum.Material.Neon, root.Color, 0.3
			fx.Size, fx.Position = Vector3.new(FIELD_DIAMETER, FIELD_DIAMETER, FIELD_DIAMETER), root.Position
			fx.Parent = Workspace
			TweenService:Create(fx, TweenInfo.new(0.7), { Size = Vector3.new(FIELD_DIAMETER * 1.6, FIELD_DIAMETER * 1.6, FIELD_DIAMETER * 1.6), Transparency = 1 }):Play()
			task.delay(0.8, function()
				fx:Destroy()
			end)
		end
		forgetDamage(m)
		m:Destroy()
	end
	s.Field, s.FieldHum, s.FieldHitAt, s.FieldLastHp = nil, nil, 0, 0
end

local function createField(s: Shrine, faction: string)
	removeField(s, false)
	local hp = fieldHpFor(s.Def.Id)
	local col = FACTION_COLOR[faction] or s.Def.Color
	local model = Instance.new("Model")
	model.Name = "Campo de " .. s.Def.Name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Shape = Enum.PartType.Ball
	root.Size = Vector3.new(FIELD_DIAMETER, FIELD_DIAMETER, FIELD_DIAMETER)
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = true
	root.CastShadow = false
	root.Material = Enum.Material.Neon
	root.Color = col
	root.Transparency = 0.85
	root.CFrame = CFrame.new(s.Pos + Vector3.new(0, 10, 0))
	root.Parent = model
	model.PrimaryPart = root
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = hp
	hum.Health = hp
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.Parent = model
	-- cartel con nombre y % de vida (misma idea que la piedra Metin)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Cartel"
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(240, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, FIELD_DIAMETER / 2 + 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.Parent = model
	local title = Instance.new("TextLabel")
	title.Name = "Titulo"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0.55, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = col
	title.TextStrokeTransparency = 0.2
	title.Text = string.format("CAMPO %s · %s", string.upper(s.Def.Id), string.upper(faction))
	title.Parent = bb
	local bar = Instance.new("Frame")
	bar.Name = "Barra"
	bar.Position = UDim2.fromScale(0.05, 0.62)
	bar.Size = UDim2.fromScale(0.9, 0.28)
	bar.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	bar.BorderSizePixel = 0
	bar.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Vida"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = col
	fill.BorderSizePixel = 0
	fill.Parent = bar
	model:SetAttribute("IsMob", true)
	model:SetAttribute("ShrineField", true)
	model:SetAttribute("ShrineOwner", faction)
	model:SetAttribute("Level", GB.MAX_LEVEL)
	model:SetAttribute("MaxHp", hp)
	model:SetAttribute("Boss", false)
	CollectionService:AddTag(model, "Targetable")
	model.Parent = styleRoot
	s.Field, s.FieldHum, s.FieldHitAt, s.FieldLastHp = model, hum, 0, hp
end

local function fieldPct(s: Shrine): number
	local h = s.FieldHum
	if s.Field and h and h.MaxHealth > 0 then
		return math.clamp(math.ceil(h.Health / h.MaxHealth * 100), 0, 100)
	end
	return 0
end

local function updateShrineVisual(s: Shrine)
	local state = (s.Owner or "-") .. "|" .. (s.Challenger or "-") .. "|" .. tostring(math.floor(s.Progress * 10)) .. "|" .. tostring(fieldPct(s))
	if state == s.Shown then
		return
	end
	s.Shown = state
	-- dato para el panel del cliente: "dueño|retador|progreso%"
	Workspace:SetAttribute("Shrine_" .. s.Def.Id, (s.Owner or "-") .. "|" .. (s.Challenger or "-") .. "|" .. tostring(math.floor(s.Progress * 100)) .. "|" .. tostring(fieldPct(s)))
	local col = if s.Owner then FACTION_COLOR[s.Owner] or C(255, 255, 255) else C(150, 150, 160)
	s.Ring.Color = if s.Challenger then FACTION_COLOR[s.Challenger] or col else col
	local txt = s.Def.Name .. "\n" .. s.Def.Text .. " · "
	if s.Challenger and s.Progress > 0 then
		txt ..= "Capturando " .. s.Challenger .. " " .. math.floor(s.Progress * 100) .. "%"
	elseif s.Owner then
		txt ..= s.Owner .. " · campo " .. fieldPct(s) .. "%"
	else
		txt ..= "Libre"
	end
	s.Label.Text = txt
end

local function tick(dt: number)
	local open = Workspace:GetAttribute("EventState") == "Open"
	local list = Players:GetPlayers()

	-- campamentos: curan a su facción
	for _, camp in ipairs(camps) do
		for _, pl in ipairs(list) do
			if pl:GetAttribute("Faction") == camp.Faction then
				local root, hum = rootOf(pl)
				if root and hum and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(camp.Pos.X, 0, camp.Pos.Z)).Magnitude <= CAMP_RADIUS and math.abs(root.Position.Y - camp.Pos.Y) < 20 then
					if hum.Health < hum.MaxHealth then
						hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.03 * dt)
					end
					local en = energyService()
					if en and en.GetEnergy then
						local cur, mx = en.GetEnergy(pl)
						if mx > 0 and cur < mx then
							en.Gain(pl, mx * 0.03 * dt)
						end
					end
				end
			end
		end
	end

	-- santuarios
	local owned: { [string]: { [string]: boolean } } = {}
	for _, s in ipairs(shrines) do
		if not open then
			if s.Owner or s.Challenger or s.Progress > 0 or s.Field then
				s.Owner, s.Challenger, s.Progress = nil, nil, 0
				removeField(s, false)
			end
		else
			-- campo protector: vida, regeneración y rotura
			local fh = s.FieldHum
			if s.Field and fh then
				if fh.Health < s.FieldLastHp then
					s.FieldHitAt = os.clock()
				elseif fh.Health < fh.MaxHealth and os.clock() - s.FieldHitAt > FIELD_REGEN_DELAY and fh.Health > 0 then
					fh.Health = math.min(fh.MaxHealth, fh.Health + fh.MaxHealth * FIELD_REGEN_PCT * dt)
				end
				s.FieldLastHp = fh.Health
				local gui = s.Field:FindFirstChild("Cartel")
				local vida = gui and gui:FindFirstChild("Vida", true)
				if vida and vida:IsA("Frame") then
					vida.Size = UDim2.fromScale(math.clamp(fh.Health / fh.MaxHealth, 0, 1), 1)
				end
				if fh.Health <= 0 then
					local by = s.Field:GetAttribute("LastHitFaction")
					local old = s.Owner
					notifyAll("¡" .. (if typeof(by) == "string" then by else "Una facción") .. " rompió el campo de " .. (old or "?") .. " en el " .. s.Def.Name .. "! Queda libre para capturar.")
					removeField(s, true)
					s.Owner, s.Challenger, s.Progress = nil, nil, 0
				end
			elseif s.Field then
				removeField(s, false) -- el modelo desapareció
			end
			local present: { [string]: number } = {}
			for _, pl in ipairs(list) do
				local f = pl:GetAttribute("Faction")
				local root = rootOf(pl)
				if typeof(f) == "string" and root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(s.Pos.X, 0, s.Pos.Z)).Magnitude <= SHRINE_RADIUS then
					present[f] = (present[f] or 0) + 1
				end
			end
			local count, only = 0, nil :: string?
			for f, _ in pairs(present) do
				count += 1
				only = f
			end
			if s.Field then
				-- mientras exista el campo nadie captura: hay que romperlo primero
				s.Challenger, s.Progress = nil, 0
			elseif count == 1 and only then
				if only == s.Owner then
					s.Progress = math.max(0, s.Progress - dt / CAPTURE_SECONDS * 2)
					s.Challenger = nil
				else
					if s.Challenger ~= only then
						s.Challenger = only
						s.Progress = 0
					end
					s.Progress += dt / CAPTURE_SECONDS
					if s.Progress >= 1 then
						s.Owner, s.Challenger, s.Progress = only, nil, 0
						createField(s, only)
						notifyAll("¡" .. only .. " capturó el " .. s.Def.Name .. "! (" .. s.Def.Text .. ")")
					end
				end
			elseif count == 0 then
				s.Progress = math.max(0, s.Progress - dt / CAPTURE_SECONDS * 0.5)
				if s.Progress == 0 then
					s.Challenger = nil
				end
			end
			-- count > 1: disputado, no avanza
		end
		if s.Owner then
			owned[s.Owner] = owned[s.Owner] or {}
			owned[s.Owner][s.Def.Id] = true
		end
		updateShrineVisual(s)
	end

	-- bonus para quienes estén en la arena
	local arena = arenaService()
	for _, pl in ipairs(list) do
		local f = pl:GetAttribute("Faction")
		local root, hum = rootOf(pl)
		local mine = if typeof(f) == "string" then owned[f] else nil
		if open and mine and root and hum and arena and arena.IsInArena and arena.IsInArena(root.Position) then
			pl:SetAttribute("ShrineDmg", if mine.Fuerza then BUFF_DMG else nil)
			pl:SetAttribute("ShrineEnergy", if mine.Aliento then BUFF_ENERGY else nil)
			pl:SetAttribute("ShrineXp", if mine.Fortuna then BUFF_XP else nil)
			setHpBuff(pl, hum, if mine.Vigor then BUFF_HP else 1)
			local names: { string } = {}
			for _, def in ipairs(SHRINES) do
				if mine[def.Id] then
					table.insert(names, def.Id)
				end
			end
			pl:SetAttribute("ShrineBuffs", if #names > 0 then table.concat(names, ",") else nil)
		elseif pl:GetAttribute("ShrineDmg") ~= nil or pl:GetAttribute("ShrineEnergy") ~= nil or pl:GetAttribute("ShrineXp") ~= nil or pl:GetAttribute("ShrineBuffs") ~= nil
			or (pl.Character and pl.Character:GetAttribute("ShrineHpBase") ~= nil) then
			clearBuffs(pl)
		end
	end
end

---------------------------------------------------------------------
-- Arranque
---------------------------------------------------------------------
local ArenaStyler = {}
local started = false -- las conexiones (tick, jugadores) se crean una sola vez aunque run() se repita para reparar

local function run()
	Workspace:SetAttribute("StyleVersion", "6.55") -- lo lee CityStyleCheck para saber si el servidor tiene los scripts nuevos
	-- espera a que ProjectBootstrapper termine el mapa NUEVO (no el viejo que pudiera venir guardado en el lugar)
	local waited = 0
	while Workspace:GetAttribute("MapBuilt") ~= true and waited < 90 do
		task.wait(0.25)
		waited += 0.25
	end
	local map = Workspace:WaitForChild(MAP_NAME, 60)
	local arena = map and map:WaitForChild("Arena_Central", 30)
	if not map or not arena then
		warn("[ArenaStyler] No existe la Arena Central")
		Workspace:SetAttribute("ArenaStyleDone", true) -- no bloquear WorldReady
		return
	end
	arenaFolder = arena
	for _ = 1, 20 do
		if #CollectionService:GetTagged("MetinStoneSpawn") >= 8 then
			break
		end
		task.wait(0.5)
	end
	local root = folder("Estilo", arena)
	styleRoot = root
	camps, shrines = {}, {}
	local coliseo = arena:FindFirstChild("Coliseo_Central")
	local ok, err = pcall(function()
		buildFloorDecor(root, if coliseo and coliseo:IsA("BasePart") then coliseo else nil)
		buildBossDecor(root)
		buildAltars(root)
		for _, l in ipairs(LANES) do
			buildCamp(root, l)
		end
		for _, def in ipairs(SHRINES) do
			buildShrine(root, def)
		end
	end)
	if not ok then
		warn("[ArenaStyler] Error en lo fijo: " .. tostring(err))
	end

	local okDesign, errDesign = pcall(applyDesign, root)
	if not okDesign then
		warn("[ArenaStyler] Error en el diseño: " .. tostring(errDesign))
	end
	Workspace:SetAttribute("ArenaStyleDone", true)

	if started then
		print("[ArenaStyler] Arena rehecha (reparación).")
		return
	end
	started = true
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		local step = acc
		acc = 0
		local good, e = pcall(tick, step)
		if not good then
			warn("[ArenaStyler] tick: " .. tostring(e))
		end
	end)
	Players.PlayerRemoving:Connect(function(pl)
		pl:SetAttribute("ShrineDmg", nil)
	end)
	print("[ArenaStyler] Arena lista: 4 campamentos, 8 altares, 4 santuarios y Coliseo con gradas.")
end

ArenaStyler.Run = run

if ENABLED then
	task.spawn(run)
end

return ArenaStyler
