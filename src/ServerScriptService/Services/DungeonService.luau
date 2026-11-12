--!strict
--[[
    DungeonService (ModuleScript) -> ServerScriptService.Services.DungeonService
    CUEVAS (mazmorras) por franja. Un portal en cada franja de cada facción (estilo Pabellón VIP) lleva a una cueva PRIVADA:
      - Sin grupo: entra solo, instancia propia, dificultad normal.
      - Con grupo: entran juntos los miembros del grupo que estén cerca del portal (máx. MAX_GROUP) a UNA instancia solo suya.
        Cada extra sube la vida y el daño de los monstruos (dificultad) y la XP (recompensa mayor que en solitario).
      - Cada jugador tiene ENTRADAS DIARIAS por franja (se guardan en el perfil, sección "Dungeon"). Si alguien del grupo no puede
        entrar (sin entradas o sin nivel) se avisa a TODO el grupo con su nombre y no entra nadie: así saben a quién sacar.
      - Si otro grupo entra justo después, recibe SU propia cueva (nunca se mezclan).
    ESTRUCTURA (generada por código, sin assets): 2 pisos. Cada piso usa una de 3 salas al azar (Caverna circular, Galería, Lago):
      Piso 1: mata ~80 % de los guardianes y se abre el PORTAL al piso 2.  Piso 2: guardianes + JEFE de la franja; al caer el jefe
      se abre el PORTAL de salida. La cueva se cierra sola (tiempo máximo, o vacía), y expulsa a quien quede dentro.
    Muerte: reapareces fuera; si tu cueva sigue abierta, vuelves a entrar por el mismo portal sin gastar otra entrada.
    Recompensas: los monstruos son los normales de la franja (botín y llaves de siempre); el jefe suelta el botín de jefe élite.
      La XP lleva el multiplicador del grupo vía atributo "XpMult" del monstruo (RewardService lo lee).
    Conexión: agrega  require(Services:WaitForChild("DungeonService"))  a GameServerMain.
    Para ajustar: tabla CONFIG (arriba). "Rarity" queda listo para los mapas con rareza (ver RARITY).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MobCatalog = require(ReplicatedStorage.Modules.MobCatalog)
local LootTables = require(ReplicatedStorage.Modules.LootTables)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local LevelService = require(Services.LevelService)
local PartyService = require(Services.PartyService)
local MobService = require(Services.Mobs.MobService)

local CONFIG = {
	ENTRIES_PER_DAY = { 3, 3, 3, 3 }, -- entradas por jugador, por franja, al día (reinicia a medianoche de Uruguay como DailyLimits)
	MIN_LEVEL = { 1, 751, 1501, 2251 }, -- nivel mínimo por franja
	MAX_GROUP = 5, -- jugadores por cueva
	PARTY_RADIUS = 60, -- los miembros del grupo deben estar a menos de esto del portal para entrar juntos
	-- Dificultad por cada jugador EXTRA (n-1). La XP sube más que la vida para que en grupo rinda más por persona.
	HP_PER_EXTRA = 0.30,
	DMG_PER_EXTRA = 0.12,
	XP_PER_EXTRA = 0.60,
	MOBS_PER_EXTRA = 2, -- guardianes extra por jugador extra
	MOBS_F1 = 10, -- guardianes del piso 1 (jugando solo)
	MOBS_F2 = 8, -- guardianes del piso 2 (jugando solo)
	UNLOCK_FRACTION = 0.8, -- % de guardianes del piso 1 para abrir el portal al piso 2
	BOSS_HP_FACTOR = 0.6, -- el jefe de la cueva es el jefe élite de la franja con esta fracción de su vida
	TTL = 40 * 60, -- duración máxima
	EXPIRE_AFTER_BOSS = 5 * 60, -- tiempo que queda abierta tras derrotar al jefe
	EMPTY_CLOSE = 180, -- se cierra si lleva tanto sin nadie dentro (da tiempo a volver tras morir)
	ORIGIN = Vector3.new(-40000, 500, 40000), -- MUY lejos del mapa y de las casas VIP (que están en +40000)
	SLOT_COLS = 6,
	SLOT_DX = 500,
	SLOT_DZ = 700,
	SLOT_COUNT = 36,
	FLOOR2_DZ = 300, -- el piso 2 está 300 studs al sur del piso 1 dentro del mismo espacio
}

-- Mapas con rareza (pendiente de implementar el ítem): multiplican vida/daño/XP. Valores de Albion Online.
local RARITY: { [string]: { Hp: number, Dmg: number, Xp: number } } = {
	Normal = { Hp = 1, Dmg = 1, Xp = 1 },
	Poco = { Hp = 1.16, Dmg = 1.08, Xp = 1.2 },
	Raro = { Hp = 1.36, Dmg = 1.18, Xp = 1.5 },
	Excepcional = { Hp = 1.58, Dmg = 1.3, Xp = 1.9 },
}

local NotifyRemote = Net.Get("Notify")

local BIOME_FACTION: { [string]: string } = {
	Imperio_Saiyan = "Saiyan",
	Alianza_Shinobi = "Shinobi",
	Flota_Pirata = "Pirate",
	Corte_Shinigami = "Shinigami",
}
local FACTION_COLOR: { [string]: Color3 } = {
	Saiyan = Color3.fromRGB(255, 190, 70),
	Shinobi = Color3.fromRGB(110, 220, 120),
	Pirate = Color3.fromRGB(90, 170, 255),
	Shinigami = Color3.fromRGB(190, 130, 255),
}

type Palette = { Floor: Color3, Wall: Color3, Crystal: Color3, Lake: Color3 }
local PALETTE: { [number]: Palette } = {
	[1] = { Floor = Color3.fromRGB(96, 88, 78), Wall = Color3.fromRGB(64, 58, 54), Crystal = Color3.fromRGB(120, 220, 255), Lake = Color3.fromRGB(60, 170, 230) },
	[2] = { Floor = Color3.fromRGB(74, 80, 96), Wall = Color3.fromRGB(46, 52, 68), Crystal = Color3.fromRGB(130, 255, 190), Lake = Color3.fromRGB(70, 210, 170) },
	[3] = { Floor = Color3.fromRGB(82, 66, 98), Wall = Color3.fromRGB(50, 38, 64), Crystal = Color3.fromRGB(215, 125, 255), Lake = Color3.fromRGB(190, 90, 255) },
	[4] = { Floor = Color3.fromRGB(78, 52, 50), Wall = Color3.fromRGB(46, 28, 28), Crystal = Color3.fromRGB(255, 125, 70), Lake = Color3.fromRGB(255, 100, 30) },
}

type Room = { Name: string, Arrive: CFrame, BackPortal: Vector3, ExitPortal: Vector3, BossPos: Vector3, Sample: () -> Vector3 }
type Portal = { Pad: Part, Prompt: ProximityPrompt, Label: TextLabel, Pillar: Part, Light: PointLight, Color: Color3, Set: (boolean, string) -> () }
type Inst = {
	Id: number,
	Slot: number,
	Strip: number,
	Faction: string,
	N: number,
	Members: { [Player]: boolean },
	Folder: Folder,
	Origin: Vector3,
	ExitCF: CFrame,
	F1: Room,
	F2: Room,
	F2Origin: Vector3,
	Rng: Random,
	HpMult: number,
	DmgMult: number,
	XpMult: number,
	Mobs: { Model },
	F1Total: number,
	F1Dead: number,
	Floor2Open: boolean,
	BossDead: boolean,
	P1Exit: Portal?,
	P2Exit: Portal?,
	ExpireAt: number,
	EmptySince: number?,
	Warned: boolean,
	Closed: boolean,
}

local DungeonService = {}
local instances: { [number]: Inst } = {}
local slotUsed: { [number]: boolean } = {}
local instOf: { [Player]: Inst } = {}
local entering: { [Player]: boolean } = {}
local nextId = 0

---------------------------------------------------------------------
-- UTILIDADES
---------------------------------------------------------------------
local function notify(p: Player, text: string)
	NotifyRemote:FireClient(p, text)
end

local function notifyAll(list: { Player }, text: string)
	for _, p in ipairs(list) do
		if p.Parent then
			notify(p, text)
		end
	end
end

local function rootOf(p: Player): BasePart?
	local c = p.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function moveTo(p: Player, cf: CFrame)
	task.spawn(function()
		pcall(function()
			p:RequestStreamAroundAsync(cf.Position, 3)
		end)
		local r = rootOf(p)
		if r then
			r.AssemblyLinearVelocity = Vector3.zero
			r.CFrame = cf
		end
	end)
end

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- cilindro vertical (el de Roblox tiene el eje en X)
local function cyl(parent: Instance, name: string, diameter: number, height: number, pos: Vector3, color: Color3, mat: Enum.Material, collide: boolean): Part
	return mk(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, mat, collide, Enum.PartType.Cylinder)
end

local function addLight(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

---------------------------------------------------------------------
-- ENTRADAS DIARIAS (perfil, sección "Dungeon")
---------------------------------------------------------------------
type Daily = { Day: string, Used: { [string]: number } }
local daily: { [Player]: Daily } = {}

local function today(): string
	return os.date("!%Y-%m-%d", os.time() + LootTables.Daily.ResetUtcOffsetHours * 3600) :: string
end

local function dailyOf(p: Player): Daily?
	local d = daily[p]
	if not d then
		return nil
	end
	local t = today()
	if d.Day ~= t then
		d.Day, d.Used = t, {}
	end
	return d
end

local function entriesLeft(p: Player, strip: number): number
	local d = dailyOf(p)
	if not d then
		return 0 -- el perfil aún no cargó
	end
	return math.max(0, CONFIG.ENTRIES_PER_DAY[strip] - (d.Used[tostring(strip)] or 0))
end

local function useEntry(p: Player, strip: number)
	local d = dailyOf(p)
	if d then
		d.Used[tostring(strip)] = (d.Used[tostring(strip)] or 0) + 1
	end
	p:SetAttribute("DungeonLeft_" .. strip, entriesLeft(p, strip))
end

PlayerData.RegisterSerializer("Dungeon", function(p: Player): any?
	local d = daily[p]
	if not d then
		return nil
	end
	return { Day = d.Day, Used = table.clone(d.Used) }
end)

local function loadDaily(p: Player)
	local saved = PlayerData.WaitForData(p)
	if not saved or p.Parent == nil then
		return
	end
	local d: Daily = { Day = today(), Used = {} }
	local raw: any = (saved :: any).Dungeon
	if typeof(raw) == "table" and typeof(raw.Day) == "string" then
		d.Day = raw.Day
		if typeof(raw.Used) == "table" then
			for k, v in pairs(raw.Used) do
				if typeof(k) == "string" and typeof(v) == "number" then
					d.Used[k] = math.max(0, math.floor(v))
				end
			end
		end
	end
	daily[p] = d
	for strip = 1, 4 do
		p:SetAttribute("DungeonLeft_" .. strip, entriesLeft(p, strip))
	end
end

PlayerData.Releasing:Connect(function(p: Player)
	daily[p] = nil
end)
Players.PlayerAdded:Connect(function(p)
	task.spawn(loadDaily, p)
end)
for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(loadDaily, p)
end

---------------------------------------------------------------------
-- PORTALES (estilo Pabellón VIP: disco de neón + columna de luz + cartel + "Entrar")
---------------------------------------------------------------------
local function makePortal(parent: Instance, name: string, pos: Vector3, color: Color3, title: string, action: string, objectText: string, onUse: (Player) -> ()): Portal
	local pad = Instance.new("Part")
	pad.Name = name
	pad.Anchored, pad.CanCollide, pad.CanQuery, pad.CanTouch = true, false, true, false
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.5, 8, 8)
	pad.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pad.Material = Enum.Material.Neon
	pad.Color = color
	pad.Transparency = 0.3
	pad.Parent = parent

	local pillar = Instance.new("Part")
	pillar.Name = "PilarLuz"
	pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch, pillar.CastShadow = true, false, false, false, false
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(36, 5, 5)
	pillar.CFrame = CFrame.new(pos + Vector3.new(0, 18, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Transparency = 0.75
	pillar.Parent = parent
	local light = addLight(pad, color, 30, 2)

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 40)
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 110
	bb.Parent = pad
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextWrapped = true
	label.TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
	label.TextStrokeTransparency = 0.4
	label.Text = title
	label.Parent = bb

	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = objectText
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.HoldDuration = 0.6
	pp.MaxActivationDistance = 11
	pp.RequiresLineOfSight = false
	pp.Parent = pad
	pp.Triggered:Connect(onUse)

	local portal: Portal
	portal = {
		Pad = pad,
		Prompt = pp,
		Label = label,
		Pillar = pillar,
		Light = light,
		Color = color,
		Set = function(open: boolean, text: string)
			label.Text = text
			pp.Enabled = open
			pad.Color = if open then color else Color3.fromRGB(90, 90, 105)
			pad.Transparency = if open then 0.3 else 0.5
			pillar.Transparency = if open then 0.75 else 1
			light.Color = if open then color else Color3.fromRGB(120, 120, 130)
		end,
	}
	return portal
end

---------------------------------------------------------------------
-- CUEVA: piezas
---------------------------------------------------------------------
local function spike(parent: Instance, base: Vector3, up: boolean, h: number, r: number, color: Color3, rng: Random)
	local dir = if up then 1 else -1
	local yaw = rng:NextNumber() * math.pi * 2
	for i = 0, 2 do
		local k = 1 - i * 0.32
		local seg = h / 3
		local sz = Vector3.new(r * 2 * k, seg + 0.4, r * 2 * k)
		local cf = CFrame.new(base + Vector3.new(0, dir * seg * (i + 0.5), 0)) * CFrame.Angles(0, yaw + i * 0.4, 0)
		mk(parent, "Roca", sz, cf, color, Enum.Material.Slate, false)
	end
end

local function crystal(parent: Instance, pos: Vector3, color: Color3, rng: Random)
	local h = 3 + rng:NextNumber() * 4
	local p = mk(parent, "Cristal", Vector3.new(1.2, h, 1.2), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles((rng:NextNumber() - 0.5) * 0.5, rng:NextNumber() * 6, (rng:NextNumber() - 0.5) * 0.5), color, Enum.Material.Neon, false)
	p.Transparency = 0.15
	addLight(p, color, 16, 1.3)
end

local function ceilingLights(parent: Instance, o: Vector3, hx: number, hz: number, H: number, n: number, rng: Random)
	for _ = 1, n do
		local p = mk(parent, "Luz", Vector3.new(1, 1, 1), CFrame.new(o + Vector3.new((rng:NextNumber() * 2 - 1) * hx, H - 4, (rng:NextNumber() * 2 - 1) * hz)), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, false)
		p.Transparency = 1
		addLight(p, Color3.fromRGB(255, 205, 160), 70, 0.9)
	end
end

local function decorate(parent: Instance, o: Vector3, hx: number, hz: number, H: number, pal: Palette, rng: Random, keepOut: { Vector3 })
	local function free(p: Vector3): boolean
		for _, k in ipairs(keepOut) do
			if (Vector3.new(p.X, 0, p.Z) - Vector3.new(k.X, 0, k.Z)).Magnitude < 14 then
				return false
			end
		end
		return true
	end
	for _ = 1, 26 do -- estalagmitas
		local p = o + Vector3.new((rng:NextNumber() * 2 - 1) * (hx - 18), 0, (rng:NextNumber() * 2 - 1) * (hz - 18))
		if free(p) then
			spike(parent, p, true, 5 + rng:NextNumber() * 9, 1.6 + rng:NextNumber() * 2, pal.Wall:Lerp(pal.Floor, 0.5), rng)
		end
	end
	for _ = 1, 30 do -- estalactitas
		local p = o + Vector3.new((rng:NextNumber() * 2 - 1) * (hx - 8), H - 1, (rng:NextNumber() * 2 - 1) * (hz - 8))
		spike(parent, p, false, 6 + rng:NextNumber() * 12, 1.8 + rng:NextNumber() * 2.4, pal.Wall, rng)
	end
	for _ = 1, 9 do -- cristales
		local p = o + Vector3.new((rng:NextNumber() * 2 - 1) * (hx - 16), 0, (rng:NextNumber() * 2 - 1) * (hz - 16))
		if free(p) then
			crystal(parent, p, pal.Crystal, rng)
		end
	end
	ceilingLights(parent, o, hx - 10, hz - 10, H, 7, rng)
end

-- muros de roca irregulares a lo largo de una recta (rectángulo)
local function rectWalls(parent: Instance, o: Vector3, hx: number, hz: number, H: number, pal: Palette, rng: Random)
	-- muro continuo detrás (sin huecos) + bloques de relieve por delante
	mk(parent, "Muro", Vector3.new(2 * hx + 10, H + 6, 4), CFrame.new(o + Vector3.new(0, H / 2, -hz - 2)), pal.Wall, Enum.Material.Slate, true)
	mk(parent, "Muro", Vector3.new(2 * hx + 10, H + 6, 4), CFrame.new(o + Vector3.new(0, H / 2, hz + 2)), pal.Wall, Enum.Material.Slate, true)
	mk(parent, "Muro", Vector3.new(4, H + 6, 2 * hz + 10), CFrame.new(o + Vector3.new(-hx - 2, H / 2, 0)), pal.Wall, Enum.Material.Slate, true)
	mk(parent, "Muro", Vector3.new(4, H + 6, 2 * hz + 10), CFrame.new(o + Vector3.new(hx + 2, H / 2, 0)), pal.Wall, Enum.Material.Slate, true)
	local function line(x0: number, z0: number, x1: number, z1: number, inward: Vector3)
		local len = Vector3.new(x1 - x0, 0, z1 - z0).Magnitude
		local n = math.max(2, math.floor(len / 9))
		for i = 0, n do
			local t = i / n
			local w = 8 + rng:NextNumber() * 7
			local h = H * (0.45 + rng:NextNumber() * 0.55)
			local d = 5 + rng:NextNumber() * 5
			local push = rng:NextNumber() * 4
			local base = o + Vector3.new(x0 + (x1 - x0) * t, 0, z0 + (z1 - z0) * t) + inward * (push + d / 2 - 1)
			local cf = CFrame.new(base.X, o.Y + h / 2, base.Z) * CFrame.Angles(0, (rng:NextNumber() - 0.5) * 0.6, 0)
			mk(parent, "Roca", Vector3.new(w, h, d), cf, pal.Wall:Lerp(pal.Floor, rng:NextNumber() * 0.4), Enum.Material.Rock, true)
		end
	end
	line(-hx, -hz, hx, -hz, Vector3.new(0, 0, 1))
	line(-hx, hz, hx, hz, Vector3.new(0, 0, -1))
	line(-hx, -hz, -hx, hz, Vector3.new(1, 0, 0))
	line(hx, -hz, hx, hz, Vector3.new(-1, 0, 0))
end

local function rectShell(parent: Instance, o: Vector3, hx: number, hz: number, H: number, pal: Palette, rng: Random)
	mk(parent, "Suelo", Vector3.new(2 * hx + 10, 2, 2 * hz + 10), CFrame.new(o + Vector3.new(0, -1, 0)), pal.Floor, Enum.Material.Slate, true)
	mk(parent, "Techo", Vector3.new(2 * hx + 10, 3, 2 * hz + 10), CFrame.new(o + Vector3.new(0, H + 1.5, 0)), pal.Wall, Enum.Material.Slate, true)
	rectWalls(parent, o, hx, hz, H, pal, rng)
end

-- punto al azar con separación mínima entre sí y lejos de las zonas reservadas
local function makeSampler(rng: Random, gen: () -> Vector3, keepOut: { Vector3 }): () -> Vector3
	local given: { Vector3 } = {}
	return function(): Vector3
		for _ = 1, 40 do
			local p = gen()
			local ok = true
			for _, k in ipairs(keepOut) do
				if (Vector3.new(p.X, 0, p.Z) - Vector3.new(k.X, 0, k.Z)).Magnitude < 24 then
					ok = false
					break
				end
			end
			if ok then
				for _, g in ipairs(given) do
					if (Vector3.new(p.X, 0, p.Z) - Vector3.new(g.X, 0, g.Z)).Magnitude < 9 then
						ok = false
						break
					end
				end
			end
			if ok then
				table.insert(given, p)
				return p
			end
		end
		local p = gen()
		table.insert(given, p)
		return p
	end
end

local function arrive(p: Vector3): CFrame
	return CFrame.lookAt(p + Vector3.new(0, 4, 0), p + Vector3.new(0, 4, -10))
end

---------------------------------------------------------------------
-- LAS 3 SALAS (el sur es la entrada, el norte la salida)
---------------------------------------------------------------------
type Builder = (Folder, Vector3, Palette, Random) -> Room

-- 1) CAVERNA CIRCULAR
local function roomRound(parent: Folder, o: Vector3, pal: Palette, rng: Random): Room
	local R, H = 70, 46
	cyl(parent, "Suelo", 2 * R + 12, 2, o + Vector3.new(0, -1, 0), pal.Floor, Enum.Material.Slate, true)
	cyl(parent, "Techo", 2 * R + 16, 3, o + Vector3.new(0, H + 1.5, 0), pal.Wall, Enum.Material.Slate, true)
	local N = 32
	local chord = 2 * (R + 3) * math.tan(math.pi / N) + 3
	for i = 0, N - 1 do
		local a = i / N * math.pi * 2
		local rp = R + 3
		local pos = o + Vector3.new(math.cos(a) * rp, H / 2, math.sin(a) * rp)
		mk(parent, "Muro", Vector3.new(chord, H + 6, 4), CFrame.lookAt(pos, o + Vector3.new(0, H / 2, 0)), pal.Wall, Enum.Material.Slate, true)
		-- relieve irregular por dentro
		local w = 9 + rng:NextNumber() * 7
		local h = H * (0.45 + rng:NextNumber() * 0.55)
		local d = 5 + rng:NextNumber() * 5
		local rr = R - (rng:NextNumber() * 4 + d / 2 - 1)
		local cp = o + Vector3.new(math.cos(a) * rr, h / 2, math.sin(a) * rr)
		mk(parent, "Roca", Vector3.new(w, h, d), CFrame.lookAt(cp, o + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, (rng:NextNumber() - 0.5) * 0.5, 0), pal.Wall:Lerp(pal.Floor, rng:NextNumber() * 0.4), Enum.Material.Rock, true)
	end
	-- columnas centrales
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2
		cyl(parent, "Columna", 7, H, o + Vector3.new(math.cos(a) * 9, H / 2, math.sin(a) * 9), pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Basalt, true)
	end
	local arrivePos = o + Vector3.new(0, 0, R - 32)
	local backPos = o + Vector3.new(0, 0, R - 18)
	local exitPos = o + Vector3.new(0, 0, -(R - 18))
	local bossPos = o + Vector3.new(0, 0, -36)
	local keep = { arrivePos, backPos, exitPos, bossPos }
	decorate(parent, o, R * 0.8, R * 0.8, H, pal, rng, keep)
	local sample = makeSampler(rng, function()
		local a = rng:NextNumber() * math.pi * 2
		local r = 22 + rng:NextNumber() * (R - 46)
		return o + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end, keep)
	return { Name = "Caverna circular", Arrive = arrive(arrivePos), BackPortal = backPos, ExitPortal = exitPos, BossPos = bossPos, Sample = sample }
end

-- 2) GALERÍA (pasillo largo con pilares)
local function roomGallery(parent: Folder, o: Vector3, pal: Palette, rng: Random): Room
	local hx, hz, H = 32, 95, 40
	rectShell(parent, o, hx, hz, H, pal, rng)
	for _, z in ipairs({ -45, -15, 15, 45 }) do
		for _, x in ipairs({ -14, 14 }) do
			cyl(parent, "Pilar", 6, H, o + Vector3.new(x, H / 2, z), pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Basalt, true)
		end
	end
	local arrivePos = o + Vector3.new(0, 0, hz - 32)
	local backPos = o + Vector3.new(0, 0, hz - 18)
	local exitPos = o + Vector3.new(0, 0, -(hz - 18))
	local bossPos = o + Vector3.new(0, 0, -(hz - 48))
	local keep = { arrivePos, backPos, exitPos, bossPos }
	decorate(parent, o, hx, hz, H, pal, rng, keep)
	local sample = makeSampler(rng, function()
		return o + Vector3.new((rng:NextNumber() * 2 - 1) * 20, 0, (rng:NextNumber() * 2 - 1) * (hz - 40))
	end, keep)
	return { Name = "Galería", Arrive = arrive(arrivePos), BackPortal = backPos, ExitPortal = exitPos, BossPos = bossPos, Sample = sample }
end

-- 3) LAGO SUBTERRÁNEO (lago brillante en el centro rodeado de roca; se rodea caminando)
local function roomLake(parent: Folder, o: Vector3, pal: Palette, rng: Random): Room
	local hx, hz, H = 75, 75, 44
	rectShell(parent, o, hx, hz, H, pal, rng)
	local lake = cyl(parent, "Lago", 48, 0.4, o + Vector3.new(0, 0.25, 0), pal.Lake, Enum.Material.Neon, false)
	lake.Transparency = 0.2
	addLight(lake, pal.Lake, 70, 2)
	for i = 0, 13 do -- anillo de rocas bajas alrededor del lago
		local a = i / 14 * math.pi * 2
		local h = 6 + rng:NextNumber() * 6
		mk(parent, "Roca", Vector3.new(9, h, 6), CFrame.lookAt(o + Vector3.new(math.cos(a) * 29, h / 2, math.sin(a) * 29), o + Vector3.new(0, h / 2, 0)), pal.Wall:Lerp(pal.Floor, 0.3), Enum.Material.Rock, true)
	end
	local arrivePos = o + Vector3.new(-38, 0, 38)
	local backPos = o + Vector3.new(-51, 0, 51)
	local exitPos = o + Vector3.new(51, 0, -51)
	local bossPos = o + Vector3.new(36, 0, -36)
	local keep = { arrivePos, backPos, exitPos, bossPos }
	decorate(parent, o, hx, hz, H, pal, rng, keep)
	local sample = makeSampler(rng, function()
		local a = rng:NextNumber() * math.pi * 2
		local r = 36 + rng:NextNumber() * 22
		return o + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	end, keep)
	return { Name = "Lago subterráneo", Arrive = arrive(arrivePos), BackPortal = backPos, ExitPortal = exitPos, BossPos = bossPos, Sample = sample }
end

local BUILDERS: { Builder } = { roomRound, roomGallery, roomLake }

---------------------------------------------------------------------
-- MONSTRUOS
---------------------------------------------------------------------
local function stripDefs(faction: string, strip: number): ({ MobCatalog.MobDef }, MobCatalog.MobDef?)
	local normals: { MobCatalog.MobDef } = {}
	local boss: MobCatalog.MobDef? = nil
	for _, d in ipairs(MobCatalog.All) do
		if d.Faction == faction and d.Strip == strip then
			if d.Boss then
				boss = boss or d
			else
				table.insert(normals, d)
			end
		end
	end
	table.sort(normals, function(a, b)
		return a.MinLevel < b.MinLevel
	end)
	return normals, boss
end

local function spawnMob(inst: Inst, def: MobCatalog.MobDef, pos: Vector3, level: number?, hpFactor: number, onDied: (Model) -> ()): Model?
	local model = MobService.SpawnAt(def.Id, CFrame.new(pos), level)
	if not model then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		local hp = math.max(1, math.floor(hum.MaxHealth * inst.HpMult * hpFactor))
		hum.MaxHealth = hp
		hum.Health = hp
		model:SetAttribute("MaxHp", hp)
		hum.Died:Once(function()
			onDied(model)
		end)
	end
	model:SetAttribute("DmgBuff", inst.DmgMult)
	model:SetAttribute("BaseBuff", inst.DmgMult)
	model:SetAttribute("XpMult", inst.XpMult)
	model:SetAttribute("Dungeon", inst.Id)
	table.insert(inst.Mobs, model)
	return model
end

---------------------------------------------------------------------
-- INSTANCIA
---------------------------------------------------------------------
local function insideBounds(inst: Inst, pos: Vector3): boolean
	local o = inst.Origin
	return math.abs(pos.X - o.X) <= 160 and pos.Z >= o.Z - 160 and pos.Z <= o.Z + CONFIG.FLOOR2_DZ + 160 and pos.Y >= o.Y - 40 and pos.Y <= o.Y + 140
end

local function memberList(inst: Inst): { Player }
	local out: { Player } = {}
	for p in pairs(inst.Members) do
		if p.Parent then
			table.insert(out, p)
		end
	end
	return out
end

local function closeInstance(inst: Inst, reason: string)
	if inst.Closed then
		return
	end
	inst.Closed = true
	for p in pairs(inst.Members) do
		if p.Parent then
			local r = rootOf(p)
			if r and insideBounds(inst, r.Position) then
				moveTo(p, inst.ExitCF)
			end
			notify(p, reason)
		end
		if instOf[p] == inst then
			instOf[p] = nil
		end
	end
	for _, m in ipairs(inst.Mobs) do
		if m.Parent then
			MobService.Despawn(m)
		end
	end
	inst.Folder:Destroy()
	slotUsed[inst.Slot] = nil
	instances[inst.Id] = nil
end

local function spawnFloor2(inst: Inst)
	local normals, boss = stripDefs(inst.Faction, inst.Strip)
	local pool: { MobCatalog.MobDef } = {}
	for i = 2, 3 do
		if normals[i] then
			table.insert(pool, normals[i])
		end
	end
	if #pool == 0 then
		pool = normals
	end
	local count = CONFIG.MOBS_F2 + CONFIG.MOBS_PER_EXTRA * (inst.N - 1)
	for _ = 1, count do
		local def = pool[inst.Rng:NextInteger(1, math.max(1, #pool))]
		if def then
			spawnMob(inst, def, inst.F2.Sample(), inst.Rng:NextInteger(def.MinLevel, def.MaxLevel), 1, function() end)
		end
	end
	if boss then
		spawnMob(inst, boss, inst.F2.BossPos, nil, CONFIG.BOSS_HP_FACTOR, function(_)
			inst.BossDead = true
			inst.ExpireAt = math.min(inst.ExpireAt, os.clock() + CONFIG.EXPIRE_AFTER_BOSS)
			if inst.P2Exit then
				inst.P2Exit.Set(true, "🌀 SALIDA — jefe derrotado")
			end
			notifyAll(memberList(inst), "¡Jefe de la cueva derrotado! La salida está abierta (la cueva se cierra en 5 min).")
		end)
	end
end

local function onGuardianDied(inst: Inst)
	if inst.Closed or inst.Floor2Open then
		return
	end
	inst.F1Dead += 1
	local need = math.ceil(inst.F1Total * CONFIG.UNLOCK_FRACTION)
	if inst.P1Exit then
		inst.P1Exit.Set(false, string.format("🔒 PISO 2 — guardianes %d/%d", math.min(inst.F1Dead, need), need))
	end
	if inst.F1Dead >= need then
		inst.Floor2Open = true
		if inst.P1Exit then
			inst.P1Exit.Set(true, "🌀 PISO 2 — portal abierto")
		end
		spawnFloor2(inst)
		notifyAll(memberList(inst), "El portal al piso 2 se abrió. ¡Allí te espera el jefe!")
	end
end

local function difficultyText(n: number, hp: number, dmg: number, xp: number): string
	if n <= 1 then
		return "Dificultad normal (en solitario)"
	end
	return string.format("Grupo de %d: monstruos +%d%% vida, +%d%% daño · XP x%.1f", n, math.floor((hp - 1) * 100 + 0.5), math.floor((dmg - 1) * 100 + 0.5), xp)
end

local function createInstance(strip: number, faction: string, group: { Player }, exitCF: CFrame, rarityName: string?): Inst?
	local slot: number? = nil
	for i = 0, CONFIG.SLOT_COUNT - 1 do
		if not slotUsed[i] then
			slot = i
			break
		end
	end
	if not slot then
		return nil
	end
	slotUsed[slot] = true
	nextId += 1
	local rar = RARITY[rarityName or "Normal"] or RARITY.Normal
	local n = #group
	local o = CONFIG.ORIGIN + Vector3.new((slot % CONFIG.SLOT_COLS) * CONFIG.SLOT_DX, 0, math.floor(slot / CONFIG.SLOT_COLS) * CONFIG.SLOT_DZ)
	local rng = Random.new()
	local folder = Instance.new("Folder")
	folder.Name = "Cueva_" .. nextId
	folder:SetAttribute("Strip", strip)
	folder:SetAttribute("Faction", faction)
	folder.Parent = Workspace

	local pal = PALETTE[strip] or PALETTE[1]
	local f1 = rng:NextInteger(1, 3)
	local f2 = ((f1 - 1 + rng:NextInteger(1, 2)) % 3) + 1 -- siempre distinta a la del piso 1
	local o2 = o + Vector3.new(0, 0, CONFIG.FLOOR2_DZ)
	local floor1 = Instance.new("Folder")
	floor1.Name = "Piso1"
	floor1.Parent = folder
	local floor2 = Instance.new("Folder")
	floor2.Name = "Piso2"
	floor2.Parent = folder
	local room1 = BUILDERS[f1](floor1, o, pal, rng)
	local room2 = BUILDERS[f2](floor2, o2, pal, rng)

	local hp = (1 + CONFIG.HP_PER_EXTRA * (n - 1)) * rar.Hp
	local dmg = (1 + CONFIG.DMG_PER_EXTRA * (n - 1)) * rar.Dmg
	local xp = (1 + CONFIG.XP_PER_EXTRA * (n - 1)) * rar.Xp

	local inst: Inst = {
		Id = nextId, Slot = slot, Strip = strip, Faction = faction, N = n, Members = {}, Folder = folder, Origin = o, ExitCF = exitCF,
		F1 = room1, F2 = room2, F2Origin = o2, Rng = rng, HpMult = hp, DmgMult = dmg, XpMult = xp, Mobs = {}, F1Total = 0, F1Dead = 0,
		Floor2Open = false, BossDead = false, P1Exit = nil, P2Exit = nil, ExpireAt = os.clock() + CONFIG.TTL, EmptySince = nil, Warned = false, Closed = false,
	}
	instances[inst.Id] = inst
	local color = FACTION_COLOR[faction] or Color3.fromRGB(255, 255, 255)

	-- PORTALES interiores
	local function enterOnly(p: Player): boolean
		if instOf[p] ~= inst or inst.Closed then
			notify(p, "Este portal es de otra cueva")
			return false
		end
		return true
	end
	makePortal(floor1, "Portal_Salida_P1", room1.BackPortal, Color3.fromRGB(255, 220, 140), "🏠 SALIR DE LA CUEVA", "Salir", "Volver a la franja", function(p)
		if enterOnly(p) then
			moveTo(p, inst.ExitCF)
		end
	end).Set(true, "🏠 SALIR DE LA CUEVA")
	local p1exit = makePortal(floor1, "Portal_Piso2", room1.ExitPortal, color, "", "Bajar", "Piso 2", function(p)
		if enterOnly(p) and inst.Floor2Open then
			moveTo(p, inst.F2.Arrive)
		end
	end)
	inst.P1Exit = p1exit
	makePortal(floor2, "Portal_Piso1", room2.BackPortal, Color3.fromRGB(180, 200, 255), "⬆ VOLVER AL PISO 1", "Subir", "Piso 1", function(p)
		if enterOnly(p) then
			moveTo(p, CFrame.lookAt(inst.F1.ExitPortal + Vector3.new(0, 4, 12), inst.F1.ExitPortal + Vector3.new(0, 4, 0)))
		end
	end).Set(true, "⬆ VOLVER AL PISO 1")
	local p2exit = makePortal(floor2, "Portal_Salida_P2", room2.ExitPortal, Color3.fromRGB(255, 220, 140), "", "Salir", "Cueva completada", function(p)
		if enterOnly(p) and inst.BossDead then
			instOf[p] = nil -- cueva completada: ya no puedes volver a entrar
			inst.Members[p] = nil
			moveTo(p, inst.ExitCF)
		end
	end)
	inst.P2Exit = p2exit
	p2exit.Set(false, "🔒 SALIDA — derrota al jefe")

	-- GUARDIANES del piso 1 (niveles bajos y medios de la franja)
	local normals, _ = stripDefs(faction, strip)
	local pool: { MobCatalog.MobDef } = {}
	for i = 1, 2 do
		if normals[i] then
			table.insert(pool, normals[i])
		end
	end
	if #pool == 0 then
		pool = normals
	end
	inst.F1Total = CONFIG.MOBS_F1 + CONFIG.MOBS_PER_EXTRA * (n - 1)
	local spawned = 0
	for _ = 1, inst.F1Total do
		local def = pool[rng:NextInteger(1, math.max(1, #pool))]
		if def and spawnMob(inst, def, room1.Sample(), rng:NextInteger(def.MinLevel, def.MaxLevel), 1, function(_)
				onGuardianDied(inst)
			end) then
			spawned += 1
		end
	end
	inst.F1Total = spawned
	local need = math.ceil(spawned * CONFIG.UNLOCK_FRACTION)
	if spawned == 0 then
		inst.Floor2Open = true -- sin monstruos (catálogo vacío): no bloquear
		spawnFloor2(inst)
		p1exit.Set(true, "🌀 PISO 2 — portal abierto")
	else
		p1exit.Set(false, string.format("🔒 PISO 2 — guardianes 0/%d", need))
	end
	return inst
end

---------------------------------------------------------------------
-- ENTRAR
---------------------------------------------------------------------
local function tryEnter(player: Player, strip: number, faction: string, portalPos: Vector3, exitCF: CFrame)
	if entering[player] then
		return
	end
	-- ¿ya tiene una cueva abierta? vuelve a entrar gratis
	local existing = instOf[player]
	if existing and not existing.Closed then
		local r = rootOf(player)
		if r and insideBounds(existing, r.Position) then
			return
		end
		moveTo(player, existing.F1.Arrive)
		notify(player, "Volviste a tu cueva (no gastas otra entrada)")
		return
	end
	if player:GetAttribute("Faction") ~= faction then
		notify(player, "Este portal es de la facción " .. faction)
		return
	end
	-- grupo: miembros del party cerca del portal
	local party = PartyService.MembersOf(player)
	local group: { Player } = {}
	local near = Vector3.new(portalPos.X, 0, portalPos.Z)
	for _, m in ipairs(party) do
		local r = rootOf(m)
		if m.Parent and r and not instOf[m] and not entering[m] and (Vector3.new(r.Position.X, 0, r.Position.Z) - near).Magnitude <= CONFIG.PARTY_RADIUS then
			table.insert(group, m)
		end
	end
	if not table.find(group, player) then
		table.insert(group, player)
	end
	-- comprobaciones: se avisa a TODO el grupo con el nombre de quien no puede
	local blockers: { string } = {}
	for _, m in ipairs(group) do
		if LevelService.GetLevel(m) < CONFIG.MIN_LEVEL[strip] then
			table.insert(blockers, string.format("%s no llega al nivel %d", m.DisplayName, CONFIG.MIN_LEVEL[strip]))
		elseif entriesLeft(m, strip) <= 0 then
			table.insert(blockers, string.format("%s ya usó las entradas diarias de la Franja %d", m.DisplayName, strip))
		end
	end
	if #blockers > 0 then
		local msg = "⛔ No pueden entrar: " .. table.concat(blockers, " · ")
		notifyAll(party, msg)
		if #group > 1 or #party > 1 then
			notifyAll(party, "Saquen del grupo a esa persona o entren sin ella.")
		end
		return
	end
	if #group > CONFIG.MAX_GROUP then
		notifyAll(party, string.format("Máximo %d jugadores por cueva (están %d cerca del portal). Que algunos se alejen del portal.", CONFIG.MAX_GROUP, #group))
		return
	end
	for _, m in ipairs(group) do
		entering[m] = true
	end
	local inst = createInstance(strip, faction, group, exitCF, nil)
	if not inst then
		for _, m in ipairs(group) do
			entering[m] = nil
		end
		notifyAll(group, "Todas las cuevas están ocupadas. Inténtalo en un momento.")
		return
	end
	for _, m in ipairs(group) do
		inst.Members[m] = true
		instOf[m] = inst
		useEntry(m, strip)
		entering[m] = nil
	end
	local text = difficultyText(inst.N, inst.HpMult, inst.DmgMult, inst.XpMult)
	for _, m in ipairs(group) do
		notify(m, string.format("Cueva de la Franja %d · %s · entradas restantes hoy: %d", strip, inst.F1.Name, entriesLeft(m, strip)))
		notify(m, text)
		moveTo(m, inst.F1.Arrive)
	end
end

---------------------------------------------------------------------
-- PORTALES DE ENTRADA EN EL MUNDO (uno por facción y franja)
---------------------------------------------------------------------
type Lane = { Faction: string, Strip: number, Start: Vector3, Dir: Vector3, FanC: number, FanK: number, U0: number, U1: number, FloorY: number }

local function readLanes(): { Lane }
	local found: { [string]: Lane } = {}
	for _, p in ipairs(CollectionService:GetTagged("ZonePvE")) do
		if p:IsA("BasePart") then
			local biome, strip = p:GetAttribute("Biome"), p:GetAttribute("Strip")
			local ls, ld = p:GetAttribute("LaneStart"), p:GetAttribute("LaneDir")
			local fc, fk = p:GetAttribute("FanC"), p:GetAttribute("FanK")
			local u0, u1 = p:GetAttribute("UStart"), p:GetAttribute("UEnd")
			if typeof(biome) == "string" and typeof(strip) == "number" and BIOME_FACTION[biome] and typeof(ls) == "Vector3" and typeof(ld) == "Vector3"
				and typeof(fc) == "number" and typeof(fk) == "number" and typeof(u0) == "number" and typeof(u1) == "number" then
				local key = biome .. "_" .. strip
				if not found[key] then
					found[key] = { Faction = BIOME_FACTION[biome], Strip = strip, Start = ls, Dir = ld, FanC = fc, FanK = fk, U0 = u0, U1 = u1, FloorY = p.Position.Y + p.Size.Y / 2 }
				end
			end
		end
	end
	local out: { Lane } = {}
	for _, l in pairs(found) do
		table.insert(out, l)
	end
	table.sort(out, function(a, b)
		if a.Faction ~= b.Faction then
			return a.Faction < b.Faction
		end
		return a.Strip < b.Strip
	end)
	return out
end

local function buildEntrances()
	local lanes = readLanes()
	if #lanes == 0 then
		return false
	end
	local old = Workspace:FindFirstChild("PortalesCueva")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "PortalesCueva"
	root.Parent = Workspace
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { root }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	for _, l in ipairs(lanes) do
		local u = l.U0 + (l.U1 - l.U0) * 0.07
		local side = Vector3.new(-l.Dir.Z, 0, l.Dir.X)
		local half = math.max(12, l.FanC + l.FanK * u - 20)
		local v = half * 0.55
		local p = l.Start + l.Dir * u + side * v
		local hit = Workspace:Raycast(Vector3.new(p.X, l.FloorY + 60, p.Z), Vector3.new(0, -140, 0), rayParams)
		local pos = Vector3.new(p.X, if hit then hit.Position.Y else l.FloorY, p.Z)
		local toCenter = -side * (if v >= 0 then 1 else -1)
		local exitCF = CFrame.lookAt(pos + toCenter * 14 + Vector3.new(0, 4, 0), pos + toCenter * 14 + l.Dir * 10 + Vector3.new(0, 4, 0))
		local color = FACTION_COLOR[l.Faction] or Color3.new(1, 1, 1)
		local strip, faction = l.Strip, l.Faction
		makePortal(root, string.format("Portal_Cueva_%s_%d", faction, strip), pos, color, string.format("🕳️ CUEVA — FRANJA %d", strip), "Entrar", string.format("Cueva · Franja %d (solo o en grupo)", strip), function(pl)
			tryEnter(pl, strip, faction, pos, exitCF)
		end)
		-- nadie nace encima del portal
		local ns = Instance.new("Part")
		ns.Name = "SinMobs"
		ns.Anchored, ns.CanCollide, ns.CanQuery, ns.CanTouch = true, false, false, false
		ns.Transparency = 1
		ns.Size = Vector3.new(40, 20, 40)
		ns.CFrame = CFrame.new(pos + Vector3.new(0, 6, 0))
		ns.Parent = root
		CollectionService:AddTag(ns, "MobNoSpawn")
	end
	print(string.format("[DungeonService] %d portales de cueva creados.", #lanes))
	return true
end

task.spawn(function()
	for _ = 1, 180 do
		if buildEntrances() then
			return
		end
		task.wait(1)
	end
	warn("[DungeonService] No se encontraron las losas ZonePvE: no se crearon los portales de cueva.")
end)

---------------------------------------------------------------------
-- CICLO DE VIDA
---------------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, inst in pairs(table.clone(instances)) do
			if inst.Closed then
				continue
			end
			local insideCount = 0
			for p in pairs(inst.Members) do
				local r = if p.Parent then rootOf(p) else nil
				if r and insideBounds(inst, r.Position) then
					insideCount += 1
				end
			end
			if insideCount > 0 then
				inst.EmptySince = nil
			else
				inst.EmptySince = inst.EmptySince or now
				if now - (inst.EmptySince :: number) >= CONFIG.EMPTY_CLOSE then
					closeInstance(inst, "Tu cueva se cerró por estar vacía")
					continue
				end
			end
			if now >= inst.ExpireAt then
				closeInstance(inst, "La cueva se desvaneció")
			elseif not inst.Warned and inst.ExpireAt - now <= 120 then
				inst.Warned = true
				notifyAll(memberList(inst), "La cueva se cierra en 2 minutos")
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(p)
	entering[p] = nil
	local inst = instOf[p]
	instOf[p] = nil
	if inst then
		inst.Members[p] = nil
	end
end)

-- API
function DungeonService.EntriesLeft(player: Player, strip: number): number
	return entriesLeft(player, strip)
end

DungeonService.Config = CONFIG
DungeonService.Rarity = RARITY

print("[DungeonService] Listo: cuevas por franja, 2 pisos y 3 salas al azar.")
return DungeonService
