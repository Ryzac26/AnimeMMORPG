--!strict
--[[
    HelperFollowClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HelperFollowClient
    (REEMPLAZA a PetFollowClient.) AYUDANTES DE COMBATE con cuerpo: los ayudantes equipados (atributos Helper1..3 = "<id>#<nivel>#<estrellas>",
    los publica HelperService, junto con HelperLook1..3 = "<rango>#<aura>#<ascensión>#<apodo>") aparecen como mini personajes (~55% de un jugador) que SIGUEN a su dueño. Todos ven los de los jugadores cercanos.
      - Formación: ranura 1 detrás a la derecha, ranura 2 detrás a la izquierda, ranura 3 más atrás.
      - Cuando el dueño entra a SU casa (atributos HelperHome1..3, los pone HouseService) van solos a la Cabaña de ayudantes y descansan allí.
      - Atacan con el dueño: al golpear él, mueven el arma; cuando se activa su poder (remote HelperFx) se lanzan al enemigo con un destello.
      - Celebran cuando el dueño sube de nivel o cuando ellos suben de rango, ascienden o cambian de rama (remote HelperCheer). Son solo visuales (el daño y los bonos los calcula el servidor; los ayudantes NO atacan a jugadores).
      - Ajuste "Mostrar mascotas" (Setting_PetsMode): Todas · Solo la mía · Ninguna.
      - Prueba (solo Fundador, Ajustes): el atributo local HelperPreview (id) y HelperPreviewLevel reemplazan al ayudante de la ranura 1.
    No tiene ScreenGui, no va en RELOAD.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local HelperCatalog = require(Modules:WaitForChild("HelperCatalog"))
local HelperModel = require(Modules:WaitForChild("HelperModel"))
local ClientNet = require(script.Parent:WaitForChild("ClientNet"))

local VIEW_RANGE = 150
local SLOTS = 3
local FORMATION: { Vector3 } = { Vector3.new(3.0, 0, 3.6), Vector3.new(-3.0, 0, 3.6), Vector3.new(0, 0, 6.6) }

type Active = {
	Player: Player,
	Slot: number,
	Id: string,
	Level: number,
	Stars: number,
	Rank: number,
	Aura: number,
	Asc: number,
	Nick: string,
	BurstStamp: number,
	Char: Model,
	Built: HelperModel.Built,
	Pos: Vector3,
	Yaw: CFrame,
	Vel: Vector3,
	AttackAt: number,
	FxUntil: number,
	FxPos: Vector3,
	CheerUntil: number,
}
local helpers: { [string]: Active } = {}
local cheerStamp: { [string]: number } = {} -- cuándo celebró (HelperCheer); se aplica al modelo vigente en el siguiente cuadro

local folder = Instance.new("Folder")
folder.Name = "AyudantesClient"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }

local function keyOf(pl: Player, slot: number): string
	return pl.UserId .. ":" .. slot
end

local function parseAttr(v: any): (HelperCatalog.Parsed?, number, number, string?)
	if typeof(v) ~= "string" then
		return nil, 1, 1, nil
	end
	local id, lv, stars = string.match(v, "^(.-)#(%d+)#(%d+)$")
	if not id then
		return nil, 1, 1, nil
	end
	local parsed = HelperCatalog.Parse(id)
	return parsed, tonumber(lv) or 1, tonumber(stars) or 1, id
end

local function starsText(n: number): string
	return string.rep("★", math.clamp(n, 0, HelperCatalog.MaxStars))
end

-- "<rango>#<aura>#<ascensión>#<apodo>" (HelperLook1..3)
local function parseLook(v: any, level: number): (number, number, number, string)
	if typeof(v) == "string" then
		local rank, aura, asc, nick = string.match(v, "^(%d+)#(%d+)#(%d+)#(.*)$")
		if rank then
			return math.clamp(tonumber(rank) or 1, 1, HelperCatalog.MaxRank), math.max(1, tonumber(aura) or 1), math.clamp(tonumber(asc) or 0, 0, HelperCatalog.MaxAsc), nick or ""
		end
	end
	return HelperCatalog.RankOf(level), 1, 0, ""
end

local function tagName(parsed: HelperCatalog.Parsed, nick: string): string
	return if nick ~= "" then nick else HelperCatalog.NameOf(parsed)
end

local function tagSub(pl: Player, level: number, stars: number, rank: number, asc: number): string
	local ascText = if asc > 0 then " · Asc." .. HelperCatalog.AscNames[asc] else ""
	local owner = if pl == localPlayer then "" else " · de " .. pl.DisplayName
	return string.format("%s · Nv.%d %s%s%s", HelperCatalog.Ranks[rank].Name, level, starsText(stars), ascText, owner)
end

local function remove(key: string)
	local h = helpers[key]
	if h then
		h.Built.Model:Destroy()
		helpers[key] = nil
	end
end

---------------------------------------------------------------------
-- Efectos de los poderes
---------------------------------------------------------------------
local ROLE_FX: { [string]: Color3 } = {
	Tanque = Color3.fromRGB(120, 230, 150),
	Guerrero = Color3.fromRGB(255, 200, 90),
	Asesino = Color3.fromRGB(255, 110, 130),
	Tirador = Color3.fromRGB(150, 210, 255),
	Mago = Color3.fromRGB(200, 140, 255),
	Curador = Color3.fromRGB(255, 170, 230),
}

local function glow(pos: Vector3, color: Color3, size: number, life: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size * 0.3, size * 0.3, size * 0.3)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = 0.2
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Position = pos
	p.Parent = folder
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(size, size, size), Transparency = 1 }):Play()
	Debris:AddItem(p, life + 0.1)
end

local function shot(from: Vector3, to: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.7, 0.7, 0.7)
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Position = from
	p.Parent = folder
	local tw = TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Linear), { Position = to })
	tw.Completed:Connect(function()
		glow(to, color, 3.2, 0.3)
	end)
	tw:Play()
	Debris:AddItem(p, 0.5)
end

local fxRemote = ClientNet.Get("HelperFx")
if fxRemote then
	fxRemote.OnClientEvent:Connect(function(owner: any, slot: any, pos: any)
		if typeof(owner) ~= "Instance" or not owner:IsA("Player") or typeof(slot) ~= "number" or typeof(pos) ~= "Vector3" then
			return
		end
		local h = helpers[keyOf(owner, slot)]
		if not h then
			return
		end
		local t = os.clock()
		local color = ROLE_FX[h.Built.Role] or Color3.new(1, 1, 1)
		h.AttackAt = t
		local origin = h.Built.Root.Position + Vector3.new(0, 1.2, 0)
		local target = pos + Vector3.new(0, 2, 0)
		if h.Built.Role == "Tirador" or h.Built.Role == "Mago" then
			shot(origin, target, color)
			if h.Built.Role == "Mago" then
				task.delay(0.22, function()
					glow(pos + Vector3.new(0, 1.5, 0), color, 14, 0.5)
				end)
			end
		elseif h.Built.Role == "Tanque" or h.Built.Role == "Curador" then
			glow(origin, color, 12, 0.7)
			h.CheerUntil = t + 0.8
		else
			-- guerrero / asesino: se lanzan al enemigo un instante
			h.FxUntil = t + 0.55
			h.FxPos = pos
			glow(pos + Vector3.new(0, 2, 0), color, 5, 0.3)
		end
	end)
end

-- El ayudante celebra: subió de rango, ascendió o cambió de rama/apodo (HelperService)
local cheerRemote = ClientNet.Get("HelperCheer")
if cheerRemote then
	cheerRemote.OnClientEvent:Connect(function(owner: any, slot: any)
		if typeof(owner) == "Instance" and owner:IsA("Player") and typeof(slot) == "number" then
			cheerStamp[keyOf(owner, slot)] = os.clock()
		end
	end)
end

---------------------------------------------------------------------
-- Qué ayudantes debe haber (cada medio segundo)
---------------------------------------------------------------------
local function reconcile()
	local cam = Workspace.CurrentCamera
	local mode = localPlayer:GetAttribute("Setting_PetsMode")
	local exclude: { Instance } = { folder }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(exclude, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = exclude

	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local alive = hrp ~= nil and hrp:IsA("BasePart") and hum ~= nil and hum.Health > 0
		local baseVisible = alive and not (mode == "none" or (mode == "mine" and pl ~= localPlayer))
		for slot = 1, SLOTS do
			local key = keyOf(pl, slot)
			local home = pl:GetAttribute("HelperHome" .. slot)
			local refPos = if typeof(home) == "Vector3" then home else (if hrp then hrp.Position else nil)
			local visible = baseVisible
			local rawAttr: any = pl:GetAttribute("Helper" .. slot)
			local previewing = false
			if slot == 1 and pl == localPlayer then
				local pv = pl:GetAttribute("HelperPreview")
				if typeof(pv) == "string" and HelperCatalog.Parse(pv) ~= nil then
					local lv = pl:GetAttribute("HelperPreviewLevel")
					rawAttr = string.format("%s#%d#%d", pv, if typeof(lv) == "number" then math.clamp(math.floor(lv), 1, 3000) else 1, 3)
					previewing = true
					visible = alive -- se ve aunque "Mostrar mascotas" esté en Ninguna
				end
			end
			if visible and not previewing and cam and refPos and (cam.CFrame.Position - refPos).Magnitude > VIEW_RANGE then
				visible = false
			end
			local parsed, level, stars, id = parseAttr(rawAttr)
			local rank, aura, asc, nick = parseLook(pl:GetAttribute("HelperLook" .. slot), level)
			if previewing then
				rank, aura, asc, nick = HelperCatalog.RankOf(level), 1, 0, ""
			end
			local cur = helpers[key]
			if not (visible and parsed and id and char) then
				if cur then
					remove(key)
				end
			else
				-- se reconstruye si cambia el ayudante o su aspecto (rango, aura, ascensión); entonces conserva su sitio
				local sameBody = cur ~= nil and cur.Id == id and cur.Char == char
				if not cur or not sameBody or cur.Rank ~= rank or cur.Aura ~= aura or cur.Asc ~= asc then
					local keepPos = if cur and sameBody then cur.Pos else nil
					local keepYaw = if cur and sameBody then cur.Yaw else nil
					remove(key)
					local built = HelperModel.Build(parsed, {
						Rank = rank,
						Aura = aura,
						Asc = asc,
						Tag = { Name = tagName(parsed, nick), Sub = tagSub(pl, level, stars, rank, asc), MaxDistance = 45 },
					})
					built.Model.Name = "Ayudante_" .. pl.Name .. "_" .. slot
					local start = keepPos or ((if hrp then hrp.Position else Vector3.zero) + Vector3.new(0, 3, 0))
					built.Root.CFrame = CFrame.new(start)
					built.Model.Parent = folder
					helpers[key] = {
						Player = pl,
						Slot = slot,
						Id = id,
						Level = level,
						Stars = stars,
						Rank = rank,
						Aura = aura,
						Asc = asc,
						Nick = nick,
						BurstStamp = 0,
						Char = char,
						Built = built,
						Pos = start,
						Yaw = keepYaw or CFrame.identity,
						Vel = Vector3.zero,
						AttackAt = -10,
						FxUntil = 0,
						FxPos = start,
						CheerUntil = 0,
					}
				elseif cur.Level ~= level or cur.Stars ~= stars or cur.Nick ~= nick then
					cur.Level, cur.Stars, cur.Nick = level, stars, nick
					HelperModel.SetTag(cur.Built, tagName(parsed, nick), tagSub(pl, level, stars, rank, asc))
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Movimiento y animación (cada cuadro)
---------------------------------------------------------------------
local acc = 0
RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc >= 0.5 then
		acc = 0
		reconcile()
	end
	local t = os.clock()
	for key, h in pairs(helpers) do
		local hrp = h.Char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") or not h.Char.Parent then
			remove(key)
			continue
		end
		local b = h.Built
		local stamp = cheerStamp[key]
		if stamp and t - stamp < 3 and stamp ~= h.BurstStamp then
			h.BurstStamp = stamp
			h.CheerUntil = math.max(h.CheerUntil, stamp + 2.0)
			HelperModel.Burst(b)
		end
		local home = h.Player:GetAttribute("HelperHome" .. h.Slot)
		local atHome = typeof(home) == "Vector3"
		local fxActive = t < h.FxUntil
		local target: Vector3
		local lookAt: Vector3? = nil
		if fxActive then
			-- se lanza hacia el enemigo y se queda a 2 studs de él
			local toMob = Vector3.new(h.FxPos.X - hrp.Position.X, 0, h.FxPos.Z - hrp.Position.Z)
			local back = if toMob.Magnitude > 0.1 then toMob.Unit * 2.4 else Vector3.zero
			target = Vector3.new(h.FxPos.X - back.X, h.FxPos.Y, h.FxPos.Z - back.Z)
			lookAt = h.FxPos
		elseif atHome then
			target = home :: Vector3
			lookAt = hrp.Position
		else
			target = (hrp.CFrame * CFrame.new(FORMATION[h.Slot] or FORMATION[1])).Position
		end
		local hit = Workspace:Raycast(target + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), rayParams)
		local groundY = if hit then hit.Position.Y else hrp.Position.Y - 3
		target = Vector3.new(target.X, groundY + b.Feet, target.Z)

		local cur = h.Pos
		if (cur - target).Magnitude > 70 then
			cur = target
		end
		local rate = if fxActive then 16 elseif atHome then 3 else 6.5
		local alpha = 1 - math.exp(-rate * dt)
		local newPos = cur:Lerp(target, alpha)
		h.Vel = (newPos - cur) / math.max(dt, 1e-3)
		h.Pos = newPos
		-- orientación: hacia donde camina; quieto, mira a su dueño (o al enemigo)
		local flat = Vector3.new(h.Vel.X, 0, h.Vel.Z)
		local dir: Vector3
		if lookAt and flat.Magnitude < 3 then
			dir = Vector3.new(lookAt.X - newPos.X, 0, lookAt.Z - newPos.Z)
		elseif flat.Magnitude > 2.5 then
			dir = flat
		else
			dir = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		end
		if dir.Magnitude < 0.01 then
			dir = Vector3.new(0, 0, -1)
		end
		local want = CFrame.lookAt(newPos, newPos + dir.Unit)
		local baseCf = CFrame.new(newPos) * h.Yaw:Lerp(want.Rotation, 1 - math.exp(-10 * dt))
		h.Yaw = baseCf.Rotation
		local cf = baseCf
		-- salto de alegría al subir de nivel el dueño
		local cheer = 0
		if t < h.CheerUntil then
			cheer = 1
			cf += Vector3.new(0, math.abs(math.sin((h.CheerUntil - t) * 7)) * 1.0, 0)
		end
		b.Root.CFrame = cf
		local speed = math.clamp(flat.Magnitude / 12, 0, 1)
		local attack = -1.0
		local since = t - h.AttackAt
		if since >= 0 and since < 0.4 then
			attack = since / 0.4
		end
		HelperModel.Animate(b, t, speed, attack, cheer)
	end
end)

---------------------------------------------------------------------
-- Eventos del dueño: golpes (PetHit) y subida de nivel
---------------------------------------------------------------------
local lastLevel: { [Player]: number } = {}
local lastSwing: { [Player]: number } = {}
local function watch(pl: Player)
	local v = pl:GetAttribute("Level")
	if typeof(v) == "number" then
		lastLevel[pl] = v
	end
	pl:GetAttributeChangedSignal("PetHit"):Connect(function()
		local now = os.clock()
		if now - (lastSwing[pl] or 0) < 1.1 then
			return
		end
		lastSwing[pl] = now
		for slot = 1, SLOTS do
			local h = helpers[keyOf(pl, slot)]
			-- los de apoyo (curador) no blanden nada; el resto hace el gesto de golpear
			if h and h.Built.Role ~= "Curador" then
				h.AttackAt = now + (slot - 1) * 0.12
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
			for slot = 1, SLOTS do
				local h = helpers[keyOf(pl, slot)]
				if h then
					h.CheerUntil = os.clock() + 1.2
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
	for slot = 1, SLOTS do
		cheerStamp[keyOf(pl, slot)] = nil
		remove(keyOf(pl, slot))
	end
	lastLevel[pl] = nil
	lastSwing[pl] = nil
end)

print("[HelperFollowClient] listo")
