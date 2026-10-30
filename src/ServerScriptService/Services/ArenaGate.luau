--!strict
--[[
    ArenaGate (ModuleScript) -> ServerScriptService.Services.ArenaGate
    Abre/cierra la ARENA (puentes + compuertas) sin depender del ProjectBootstrapper. Se activa con:
        workspace:SetAttribute("EventForce", "Open")   /   "Closed"      (lo usan los comandos /arena y /cerrar)
    También ajusta EventState y EventCountdown, y el temporizador automático del Bootstrapper sigue funcionando
    desde ese nuevo estado (no interfiere: solo lee EventState/EventCountdown).
    PUENTES con diseño por nación (piedra dorada Saiyan, madera y cuerdas Shinobi, cubierta de barco Pirata), con barandas
    sólidas a los lados (nadie cae al vacío), farolas suaves y un arco en la entrada de la arena.
    Cada puente tiene una BARRERA de nación en el lado de la arena: solo los jugadores de esa nación pueden subir a su
    puente de regreso a la ciudad (usa los grupos de colisión Barrier_<Facción> que crea el ProjectBootstrapper).
    Cuando exista el sistema real de eventos (jefe mundial / Metin), llamará a esto mismo.
]]
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local SignKit = require(script.Parent:WaitForChild("SignKit"))
local MAP_NAME = "Map_WC3_Style"
local EVENT_GROUP = "Event_Bridges"
local BRIDGE_VISIBLE_TRANSPARENCY = 0.15
local WALL_TRANSPARENCY = 0.85
local OPEN_SECONDS = 600
local CLOSED_SECONDS = 1800
local GATE_WIDTH = 116 -- ancho de las compuertas (BRIDGE_WIDTH + GATE_MARGIN del Bootstrapper): el puente lo iguala, sin huecos
local BRIDGE_OVERLAP = 60 -- lo que el puente se mete bajo el piso de la arena (igual que en el Bootstrapper)

type Style = {
	Faction: string, Base: Color3, BaseMat: Enum.Material, Rail: Color3, RailMat: Enum.Material,
	Accent: Color3, Glow: Color3, Rope: boolean, Gate: Color3, Dragon: boolean?,
}
local STYLES: { [string]: Style } = {
	Imperio_Saiyan = {
		Faction = "Saiyan", Base = Color3.fromRGB(118, 100, 84), BaseMat = Enum.Material.Slate,
		Rail = Color3.fromRGB(150, 128, 104), RailMat = Enum.Material.Granite,
		Accent = Color3.fromRGB(226, 168, 60), Glow = Color3.fromRGB(255, 170, 70), Rope = false, Gate = Color3.fromRGB(255, 160, 60), -- Dragon = true (Camino de la Serpiente) queda desactivado; se retoma más adelante
	},
	Alianza_Shinobi = {
		Faction = "Shinobi", Base = Color3.fromRGB(124, 92, 62), BaseMat = Enum.Material.WoodPlanks,
		Rail = Color3.fromRGB(92, 66, 42), RailMat = Enum.Material.Wood,
		Accent = Color3.fromRGB(205, 190, 140), Glow = Color3.fromRGB(255, 120, 90), Rope = true, Gate = Color3.fromRGB(90, 220, 110),
	},
	Flota_Pirata = {
		Faction = "Pirate", Base = Color3.fromRGB(98, 72, 50), BaseMat = Enum.Material.WoodPlanks,
		Rail = Color3.fromRGB(64, 46, 34), RailMat = Enum.Material.Wood,
		Accent = Color3.fromRGB(196, 170, 120), Glow = Color3.fromRGB(255, 205, 120), Rope = true, Gate = Color3.fromRGB(80, 170, 255),
	},
	Corte_Shinigami = {
		Faction = "Shinigami", Base = Color3.fromRGB(210, 208, 222), BaseMat = Enum.Material.Marble,
		Rail = Color3.fromRGB(235, 235, 245), RailMat = Enum.Material.Marble,
		Accent = Color3.fromRGB(170, 150, 235), Glow = Color3.fromRGB(165, 190, 255), Rope = false, Gate = Color3.fromRGB(165, 140, 255),
	},
}
local decoFolder: Folder? = nil

local ArenaGate = {}


local function piece(parent: Instance, cf: CFrame, size: Vector3, color: Color3, mat: Enum.Material, transparency: number, collide: boolean, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
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
	p:SetAttribute("TargetTransparency", transparency)
	p.Transparency = 1
	p.Parent = parent
	return p
end


-- CAMINO DEL DRAGÓN / CAMINO DE LA SERPIENTE (Dragon Ball): el camino ES el cuerpo del dragón. Camino lila-gris que serpentea
-- (curvas en S), con la orilla dentada (picos triangulares) y un costado de malla de rombos hacia el vacío.
-- Los extremos son rectos y miden lo mismo que las compuertas (116) para encajar con la ciudad y con la arena.
local function snakeRoad(folder: Folder, at: (number, number, number) -> CFrame, z0: number, z1: number, top: number)
	local deckC = Color3.fromRGB(208, 208, 230)
	local curbC = Color3.fromRGB(178, 178, 210)
	local meshC = Color3.fromRGB(120, 124, 182)
	local len = z1 - z0
	local AMP, PERIOD = 46, 190
	local function smooth(t: number): number
		t = math.clamp(t, 0, 1)
		return t * t * (3 - 2 * t)
	end
	local function offsetAt(z: number): number
		local t = (z - z0) / len
		return AMP * smooth(math.min(t, 1 - t) / 0.13) * math.sin((z - z0) / PERIOD * 2 * math.pi)
	end
	local function widthAt(z: number): number
		local t = (z - z0) / len
		return GATE_WIDTH - 50 * smooth(math.min(t, 1 - t) / 0.1)
	end
	local seg = 4
	for i = 0, math.ceil(len / seg) - 1 do
		local zA = z0 + i * seg
		local zm = zA + seg / 2
		local xA, xB = offsetAt(zA), offsetAt(zA + seg)
		local dx = xB - xA
		local segLen = math.sqrt(dx * dx + seg * seg) + 0.7
		local w = widthAt(zm)
		local cf = at((xA + xB) / 2, top, zm) * CFrame.Angles(0, math.atan2(dx, seg), 0)
		piece(folder, cf * CFrame.new(0, -1, 0), Vector3.new(w, 2, segLen), deckC, Enum.Material.SmoothPlastic, 0, true)
		for _, sx in ipairs({ -1, 1 }) do
			local ex = sx * w / 2
			piece(folder, cf * CFrame.new(ex - sx * 0.7, 0.7, 0), Vector3.new(1.4, 1.4, segLen), curbC, Enum.Material.SmoothPlastic, 0, false)
			piece(folder, cf * CFrame.new(ex + sx * 0.25, -5.5, 0), Vector3.new(0.5, 9, segLen), meshC, Enum.Material.DiamondPlate, 0, false)
			for _, tz in ipairs({ -1, 1 }) do -- dientes (cubos girados 45°: picos triangulares)
				piece(folder, cf * CFrame.new(ex - sx * 0.2, 1.1, tz) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(2.2, 2.2, 1.6), curbC, Enum.Material.SmoothPlastic, 0, false)
			end
			piece(folder, cf * CFrame.new(ex + sx * 0.8, 8, 0), Vector3.new(1, 16, segLen), curbC, Enum.Material.SmoothPlastic, 1, true) -- pared invisible
		end
	end
end

-- Barandas, postes, farolas, arco y barrera de nación para UN puente
local function decorate(bridge: BasePart, style: Style, folder: Folder, biome: string)
	local W, L = bridge.Size.X, bridge.Size.Z
	local top = bridge.Position.Y + bridge.Size.Y / 2
	local z0 = -L / 2 -- extremo de la ciudad
	local z1 = L / 2 - BRIDGE_OVERLAP -- borde de la arena
	local len = z1 - z0
	local zc = (z0 + z1) / 2
	local function at(x: number, y: number, z: number): CFrame
		return bridge.CFrame * CFrame.new(x, y - bridge.Position.Y, z)
	end
	local half = W / 2

	if style.Dragon then
		snakeRoad(folder, at, z0, z1, top)
	end
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (half - 0.8)
		-- pared invisible alta: no se puede caer ni saltar por encima
		piece(folder, at(x, top + 8, zc), Vector3.new(1, 16, len), style.Rail, Enum.Material.SmoothPlastic, 1, true)
		if style.Dragon then
			continue -- el camino serpiente trae sus propias paredes (ver snakeRoad)
		end
		-- baranda visible (2 vigas o cuerdas)
		local thick = if style.Rope then 0.5 else 1.4
		piece(folder, at(x, top + 4.6, zc), Vector3.new(thick, thick, len), if style.Rope then style.Accent else style.Rail, if style.Rope then Enum.Material.Fabric else style.RailMat, 0, false)
		piece(folder, at(x, top + 2.4, zc), Vector3.new(thick, thick, len), if style.Rope then style.Accent else style.Rail, if style.Rope then Enum.Material.Fabric else style.RailMat, 0, false)
		if not style.Rope then
			piece(folder, at(x, top + 1.1, zc), Vector3.new(1.8, 2.2, len), style.Rail, style.RailMat, 0, false) -- zócalo de piedra
		end
		-- postes con farola suave cada 24 studs
		local z = z0 + 12
		while z < z1 do
			piece(folder, at(x, top + 3.2, z), Vector3.new(1.7, 6.4, 1.7), style.Rail, style.RailMat, 0, false)
			local lamp = piece(folder, at(x, top + 7.2, z), Vector3.new(2, 2, 2), style.Glow, Enum.Material.SmoothPlastic, 0.1, false, Enum.PartType.Ball)
			local light = Instance.new("PointLight")
			light.Color = style.Glow
			light.Brightness = 0.5
			light.Range = 14
			light.Parent = lamp
			z += 24
		end
	end
	-- detalle del suelo
	if style.Dragon then
		-- (el camino serpiente ya es el suelo)
	elseif style.Rope then
		local z = z0 + 6
		while z < z1 do
			piece(folder, at(0, top + 0.12, z), Vector3.new(W - 2, 0.25, 1), style.Rail, style.RailMat, 0, false)
			z += 9
		end
	else
		piece(folder, at(0, top + 0.1, zc), Vector3.new(7, 0.2, len), style.Accent, Enum.Material.Marble, 0, false)
		piece(folder, at(0, top + 0.1, zc), Vector3.new(W - 16, 0.18, len), style.Base:Lerp(Color3.new(0, 0, 0), 0.15), Enum.Material.Cobblestone, 0, false)
	end
	-- arco de entrada a la arena (el Camino del Dragón usa las cabezas de los dragones como entrada)
	for _, sx in ipairs(if style.Dragon then {} else { -1, 1 }) do
		piece(folder, at(sx * (half + 1), top + 12, z1 - 4), Vector3.new(5, 24, 5), style.Rail, style.RailMat, 0, false)
	end
	if not style.Dragon then
		piece(folder, at(0, top + 25, z1 - 4), Vector3.new(W + 12, 4, 5), style.Rail, style.RailMat, 0, false)
		-- cartel del anime sobre el arco (dos caras) + emblema giratorio
		local look = SignKit.LOOKS[biome]
		if look then
			local signW, signH = W + 12, 16
			local board = SignKit.Part(folder, "CartelArco", Vector3.new(signW, signH, 1.6), at(0, top + 27 + signH / 2, z1 - 4), look.Board, Enum.Material.SmoothPlastic)
			SignKit.Design(board, Enum.NormalId.Back, biome, look, signW, signH)
			SignKit.Design(board, Enum.NormalId.Front, biome, look, signW, signH)
			for _, dy in ipairs({ 0, signH }) do
				SignKit.Part(folder, "CartelBorde", Vector3.new(signW + 2, 1.2, 2.4), at(0, top + 27 + dy, z1 - 4), look.Trim, Enum.Material.Metal)
			end
			SignKit.SpinningEmblem(biome, folder, at(0, top + 27 + signH + 1.5, z1 - 4), look, 0.5)
		end
	end

	-- barrera de NACIÓN en el lado de la arena: solo deja pasar a los jugadores de esa facción
	-- (una en el lado de la arena y otra en el de la ciudad, a todo el ancho del puente)
	for _, bz in ipairs({ z1 - 14, z0 + 6 }) do
		local barrier = piece(folder, at(0, top + 15, bz), Vector3.new(W, 30, 1.5), style.Gate, Enum.Material.ForceField, 0.6, true)
		barrier.CollisionGroup = "Barrier_" .. style.Faction
		barrier.CanQuery = false
	end
end

function ArenaGate.SetOpen(open: boolean)
	local map = Workspace:FindFirstChild(MAP_NAME)
	if not map then
		warn("[ArenaGate] No existe el mapa " .. MAP_NAME)
		return
	end
	-- puentes
	local group = map:FindFirstChild(EVENT_GROUP)
	-- limpiar decoración anterior
	local oldDeco = decoFolder
	decoFolder = nil
	if oldDeco then
		for _, p in ipairs(oldDeco:GetChildren()) do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(0.8), { Transparency = 1 }):Play()
			end
		end
		task.delay(1, function()
			oldDeco:Destroy()
		end)
	end
	if group then
		local folder: Folder? = nil
		if open then
			local f = Instance.new("Folder")
			f.Name = "Puentes_Deco"
			f.Parent = map
			folder = f
			decoFolder = f
		end
		for _, child in ipairs(group:GetChildren()) do
			if child:IsA("BasePart") then
				if open then
					local style = STYLES[tostring(child:GetAttribute("Biome"))]
					child.CanCollide = true
					child.CanQuery = true
					child.Size = Vector3.new(GATE_WIDTH, child.Size.Y, child.Size.Z) -- sin huecos laterales en las compuertas
					if style then
						child.Material = style.BaseMat
						child.Color = style.Base
						decorate(child, style, folder :: Folder, tostring(child:GetAttribute("Biome")))
					end
					if style and style.Dragon then
						-- el suelo lo hace el camino serpiente: la losa recta original queda invisible y sin colisión
						child.Transparency = 1
						child.CanCollide = false
						child.CanQuery = false
					else
						TweenService:Create(child, TweenInfo.new(1.5), { Transparency = 0 }):Play()
					end
				else
					local tw = TweenService:Create(child, TweenInfo.new(1.5), { Transparency = 1 })
					tw.Completed:Once(function()
						if child.Transparency >= 1 then
							child.CanCollide = false
							child.CanQuery = false
						end
					end)
					tw:Play()
				end
			end
		end
		if open and decoFolder then
			for _, p in ipairs(decoFolder:GetChildren()) do
				if p:IsA("BasePart") then
					TweenService:Create(p, TweenInfo.new(1.5), { Transparency = (p:GetAttribute("TargetTransparency") :: number?) or 0 }):Play()
				end
			end
		end
	else
		warn("[ArenaGate] No se encontró la carpeta " .. EVENT_GROUP)
	end
	-- compuertas / paredes que bloquean el ingreso
	local gates = 0
	for _, d in ipairs(map:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("GateGroup") == EVENT_GROUP then
			gates += 1
			d.CanCollide = not open
			TweenService:Create(d, TweenInfo.new(1), { Transparency = if open then 1 else WALL_TRANSPARENCY }):Play()
		end
	end
	Workspace:SetAttribute("EventState", if open then "Open" else "Closed")
	Workspace:SetAttribute("EventCountdown", if open then OPEN_SECONDS else CLOSED_SECONDS)
	print(string.format("[ArenaGate] Arena %s (%d compuertas)", if open then "ABIERTA" else "CERRADA", gates))
end

-- (EventForce lo atiende el ProjectBootstrapper, que llama a ArenaGate.SetOpen; así no hay dos escuchas compitiendo)

return ArenaGate
