--!strict
--[[
    DungeonNav (ModuleScript) -> ServerScriptService.Services.DungeonNav
    Datos del laberinto de cada cueva. Lo LLENA DungeonService al crear una cueva y lo USAN DungeonService y MobBrain para:
      1) LÍNEA DE VISIÓN: CanSee(id, desde, hasta) = no hay pared (ni pilar, ni roca grande) de por medio. Los monstruos de una cueva
         solo te detectan y te atacan si te ven.
      2) CAMINO POR CELDAS: Waypoint(id, desde, hasta) = el centro de la siguiente celda del laberinto hacia el objetivo, para que los
         monstruos que te perdieron de vista sigan el pasillo en vez de chocar contra el muro.
      3) DISTANCIA POR CAMINO: CellDistance(id, a, b) = cuántas celdas hay por el laberinto entre dos puntos (las manadas y el jefe
         aparecen cuando estás a pocas celdas POR EL CAMINO, no a pocos studs en línea recta a través de una pared).
    No requiere nada más. Si este módulo no existe, MobBrain funciona como siempre.
]]
local Workspace = game:GetService("Workspace")

export type FloorData = {
	Origin: Vector3, -- centro del piso (x, suelo, z)
	W: number,
	H: number,
	S: number, -- lado de una celda (studs)
	Adj: { [number]: { boolean } }, -- por celda (id = fila * W + columna): hay paso al norte(-Z), este(+X), sur(+Z), oeste(-X)
}
type Entry = {
	Floors: { FloorData },
	Params: RaycastParams,
	Dist: { [number]: { [number]: { [number]: number } } }, -- [piso][celda destino][celda] = pasos
}

local DX = { 0, 1, 0, -1 }
local DY = { -1, 0, 1, 0 }

local DungeonNav = {}
local entries: { [number]: Entry } = {}

function DungeonNav.Register(id: number, folder: Instance, floors: { FloorData })
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	entries[id] = { Floors = floors, Params = params, Dist = {} }
end

function DungeonNav.Unregister(id: number)
	entries[id] = nil
end

local function floorIndex(e: Entry, pos: Vector3): number
	local best, bestD = 1, math.huge
	for i, f in ipairs(e.Floors) do
		local d = math.abs(pos.Z - f.Origin.Z)
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

local function cellOf(f: FloorData, pos: Vector3): number
	local cx = math.clamp(math.floor((pos.X - f.Origin.X) / f.S + f.W / 2), 0, f.W - 1)
	local cy = math.clamp(math.floor((pos.Z - f.Origin.Z) / f.S + f.H / 2), 0, f.H - 1)
	return cy * f.W + cx
end

local function centerOf(f: FloorData, id: number, y: number): Vector3
	local cx, cy = id % f.W, id // f.W
	return Vector3.new(f.Origin.X + (cx - (f.W - 1) / 2) * f.S, y, f.Origin.Z + (cy - (f.H - 1) / 2) * f.S)
end

-- pasos desde una celda a todas las demás (el laberinto no cambia: se calcula una vez por celda destino y se guarda)
local function distTo(e: Entry, fi: number, target: number): { [number]: number }
	local perFloor: { [number]: { [number]: number } }? = e.Dist[fi]
	if not perFloor then
		perFloor = {}
		e.Dist[fi] = perFloor :: { [number]: { [number]: number } }
	end
	local floorCache = perFloor :: { [number]: { [number]: number } }
	local cached = floorCache[target]
	if cached then
		return cached
	end
	local f = e.Floors[fi]
	local dist: { [number]: number } = { [target] = 0 }
	local queue: { number } = { target }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		local adj = f.Adj[id]
		if adj then
			local cx, cy = id % f.W, id // f.W
			for d = 1, 4 do
				if adj[d] then
					local nid = (cy + DY[d]) * f.W + (cx + DX[d])
					if dist[nid] == nil then
						dist[nid] = dist[id] + 1
						table.insert(queue, nid)
					end
				end
			end
		end
	end
	floorCache[target] = dist
	return dist
end

-- ¿hay línea de visión? (solo cuentan las piezas de ESTA cueva con colisión: paredes, pilares, rocas grandes, columnas)
function DungeonNav.CanSee(id: number, from: Vector3, to: Vector3): boolean
	local e = entries[id]
	if not e then
		return true
	end
	return Workspace:Raycast(from, to - from, e.Params) == nil
end

-- siguiente punto del camino (centro de la celda vecina) para ir de "from" a "to"; nil = ir en línea recta
function DungeonNav.Waypoint(id: number, from: Vector3, to: Vector3): Vector3?
	local e = entries[id]
	if not e then
		return nil
	end
	local fi = floorIndex(e, from)
	if floorIndex(e, to) ~= fi then
		return nil
	end
	local f = e.Floors[fi]
	local a, b = cellOf(f, from), cellOf(f, to)
	if a == b then
		return nil
	end
	local dist = distTo(e, fi, b)
	local da = dist[a]
	local adj = f.Adj[a]
	if not da or not adj then
		return nil
	end
	local cx, cy = a % f.W, a // f.W
	local bestId: number? = nil
	local bestD = da
	for d = 1, 4 do
		if adj[d] then
			local nid = (cy + DY[d]) * f.W + (cx + DX[d])
			local dn = dist[nid]
			if dn and dn < bestD then
				bestId, bestD = nid, dn
			end
		end
	end
	if not bestId then
		return nil
	end
	return centerOf(f, bestId, from.Y)
end

-- celdas que hay POR EL LABERINTO entre dos puntos (nil si están en pisos distintos o la cueva no existe)
function DungeonNav.CellDistance(id: number, a: Vector3, b: Vector3): number?
	local e = entries[id]
	if not e then
		return nil
	end
	local fi = floorIndex(e, a)
	if floorIndex(e, b) ~= fi then
		return nil
	end
	local f = e.Floors[fi]
	return distTo(e, fi, cellOf(f, b))[cellOf(f, a)]
end

return DungeonNav
