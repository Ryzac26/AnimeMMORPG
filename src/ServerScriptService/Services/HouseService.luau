--!strict
--[[
    HouseService (ModuleScript) -> ServerScriptService.Services.HouseService
    CASA VIP ("Pabellón Imperial"). Fase 1.
      - LICENCIA DE CASA: el pago único (Game Pass "VipHouse", o su recompra "VipHouseRebuy") da la casa y la SUSCRIPCIÓN IMPERIAL (mensual) es el costo
        de seguir usándola; el primer mes (30 días) va INCLUIDO en el pago único. Si pasado ese mes no hay suscripción (más GRACE_SECONDS de margen) la licencia VENCE: se pierde la casa, se libera el cupo, todo el baúl
        pasa al buzón de la ciudad y para volver a tenerla hay que pagar de nuevo el pase (si aún quedan casas). Atributo del jugador: House_Active.
      - Portal en la plaza de cada ciudad (CityStyler llama AddCityPortal). El dueño entra a SU casa; un invitado entra a la del que lo invitó.
      - La casa se construye lejos del mapa (en lo alto) cuando el dueño entra por primera vez y se borra cuando él sale del servidor.
        Dentro: portal de SALIDA, BAÚL (solo el dueño lo abre), TABLÓN de invitados (solo el dueño) y rincón de mascotas (próximamente).
      - Invitados: pueden entrar, mirar y salir. Nada más: todos los prompts comprueban que sea el dueño. Invitar/expulsar: ventana (HouseClient).
      - Baúl: se guarda en el perfil (sección "House" = { V = { ["slot"] = {Id, Count, Plus, Locked} } }). Sin pase se conserva, pero no se abre.
      - Remotes: HouseOpen (servidor -> cliente: abre la ventana) · HouseState · HouseAction ("State" | "Deposit" | "Withdraw" | "Invite" | "Uninvite" | "Exit" | "BuySub").
]]
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local MountCatalog = require(ReplicatedStorage.Modules.MountCatalog)
local HouseDecor = require(script.Parent.HouseDecor)
local ProductCatalog = require(ReplicatedStorage.Modules.ProductCatalog)
local Services = ServerScriptService.Services
local Net = require(Services.Net)
local PlayerData = require(Services.PlayerData)
local Inventory = require(Services.InventoryService)

local OpenRemote = Net.Get("HouseOpen")
local StateRemote = Net.Get("HouseState")
local ActionRemote = Net.Get("HouseAction")
local NotifyRemote = Net.Get("Notify")

local VAULT_CAP = 60 -- casillas del baúl (la casa siempre tiene suscripción activa)
local INCLUDED_SECONDS = 30 * 86400 -- el pago único incluye el primer mes: la suscripción se cobra recién después
local GRACE_SECONDS = 3 * 86400 -- margen para que se acredite el pago de la suscripción / reintento de cobro
local REMIND_SECONDS = 5 * 86400 -- avisa de que hay que suscribirse cuando faltan menos de 5 días
local MAX_GUESTS = 8
local SLOT_COUNT = 48
local HOUSE_W = 140
local ORIGIN = Vector3.new(40000, 500, 40000) -- cuadrícula de casas MUY lejos del mapa (más allá de la distancia de dibujo: nadie las ve desde fuera)
local SPACING = 260

type Stack = { Id: string, Count: number, Plus: number?, Locked: boolean? }
type House = { Owner: Player, Slot: number, Origin: Vector3, Model: Model, Garden: Vector3 }

local HouseService = {}
local houses: { [Player]: House } = {}
local usedSlots: { [number]: boolean } = {}
local vaults: { [Player]: { [number]: Stack } } = {}
local invited: { [Player]: { [number]: boolean } } = {} -- dueño -> UserIds invitados
local invitedBy: { [Player]: Player } = {} -- invitado -> último que lo invitó
local inside: { [Player]: Player } = {} -- jugador -> dueño de la casa donde está
local returnCF: { [Player]: CFrame } = {}
local portals: { [string]: Vector3 } = {}

local MAX_MOUNTS_OUT = 6

local function mountKeys(player: Player): { string }
	local raw = player:GetAttribute("MountHomeKeys")
	local out: { string } = {}
	if typeof(raw) == "string" then
		for k in string.gmatch(raw, "[^;]+") do
			table.insert(out, k)
		end
	end
	return out
end

local function setMountKeys(player: Player, list: { string })
	player:SetAttribute("MountHomeKeys", if #list > 0 then table.concat(list, ";") else nil)
	-- el centro del jardín lo leen los clientes para pasear
	if #list == 0 then
		player:SetAttribute("MountHome", nil)
	end
end

local lastAction: { [Player]: number } = {}
local lic: { [Player]: { On: boolean, Until: number } } = {} -- licencia de casa (se guarda en el perfil)
local rebuying: { [Player]: boolean } = {}
local reminded: { [Player]: boolean } = {}
local mail: { [Player]: { Stack } } = {} -- BUZÓN: objetos que no caben en el baúl (p. ej. al terminar la suscripción)
local mailboxes: { Vector3 } = {}
local MAIL_MAX = 300

local function say(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

local function hasPass(player: Player): boolean
	return player:GetAttribute("House_Active") == true -- licencia de casa vigente
end

local function vaultCap(_player: Player): number
	return VAULT_CAP
end

local function rootOf(player: Player): BasePart?
	local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function moveTo(player: Player, cf: CFrame)
	local r = rootOf(player)
	if r then
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, 2)
		end)
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = cf
	end
end

---------------------------------------------------------------------
-- Construcción de la casa
---------------------------------------------------------------------
local function part(parent: Instance, name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material, trans: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = mat
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Transparency = trans or 0
	p.Parent = parent
	return p
end

local function sign(p: BasePart, text: string, color: Color3, offsetY: number)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 36)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextSize = 18
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	l.Text = text
	l.Parent = bb
end

local function prompt(p: BasePart, action: string, object: string, key: Enum.KeyCode, hold: number, onUse: (Player) -> ()): ProximityPrompt
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.KeyboardKeyCode = key
	pp.HoldDuration = hold
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.Parent = p
	pp.Triggered:Connect(onUse)
	return pp
end

local function buildPad(parent: Instance, name: string, pos: Vector3, color: Color3, title: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide = true, false
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.5, 8, 8)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.3
	p.Parent = parent
	sign(p, title, color:Lerp(Color3.new(1, 1, 1), 0.5), 5)
	return p
end

local function exitHouse(player: Player)
	inside[player] = nil
	player:SetAttribute("InHouse", nil)
	local cf = returnCF[player]
	returnCF[player] = nil
	if not cf then
		-- sin punto guardado: portal de su facción, o cualquier portal, o su punto de reaparición
		local pp = portals[tostring(player:GetAttribute("Faction"))]
		if not pp then
			local _, any = next(portals)
			pp = any
		end
		if pp then
			cf = CFrame.new(pp + Vector3.new(0, 4, 14))
		else
			local sp = player.RespawnLocation or Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
			if sp then
				cf = sp.CFrame + Vector3.new(0, 6, 0)
			end
		end
	end
	if cf then
		moveTo(player, cf)
	end
end

local buildPush: (Player) -> () = function() end

local function buildHouse(owner: Player): House?
	local slot: number? = nil
	for i = 0, SLOT_COUNT - 1 do
		if not usedSlots[i] then
			slot = i
			break
		end
	end
	if not slot then
		return nil
	end
	usedSlots[slot] = true
	local o = ORIGIN + Vector3.new((slot % 8) * SPACING, 0, math.floor(slot / 8) * SPACING)
	local m = Instance.new("Model")
	m.Name = "CasaVIP_" .. owner.UserId
	local wood = Color3.fromRGB(96, 66, 42)
	local stone = Color3.fromRGB(214, 204, 186)
	local gold = Color3.fromRGB(240, 196, 90)
	local W, H = HOUSE_W, 34 -- 140 x 140 studs, 34 de alto
	local HALF = W / 2
	local function at(x: number, y: number, z: number): Vector3
		return o + Vector3.new(x, y, z)
	end
	-- SUELO: mármol y madera (sur = vestíbulo y salón, norte = jardín de mascotas)
	part(m, "Suelo", Vector3.new(W, 2, W), o, Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)
	part(m, "SueloSalon", Vector3.new(W, 0.3, 80), at(0, 1.1, -30), Color3.fromRGB(226, 218, 200), Enum.Material.Marble)
	part(m, "Alfombra", Vector3.new(36, 0.2, 70), at(0, 1.3, -30), Color3.fromRGB(150, 38, 52), Enum.Material.Fabric)
	part(m, "AlfombraBorde", Vector3.new(40, 0.15, 74), at(0, 1.25, -30), gold, Enum.Material.Fabric)
	-- MUROS exteriores
	for _, s2 in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local horiz = s2[1] ~= 0
		part(m, "Muro", if horiz then Vector3.new(2, H, W) else Vector3.new(W, H, 2), at(s2[1] * HALF, H / 2, s2[2] * HALF), stone, Enum.Material.Marble)
		part(m, "Friso", if horiz then Vector3.new(2.4, 1.4, W) else Vector3.new(W, 1.4, 2.4), at(s2[1] * HALF, 5, s2[2] * HALF), gold, Enum.Material.Metal)
	end
	-- TECHO solo sobre el salón (z < 10): el jardín queda al cielo abierto
	local ceil = part(m, "Techo", Vector3.new(W + 2, 2, 82), at(0, H + 1, -30), wood, Enum.Material.Wood)
	part(m, "TechoVigaE", Vector3.new(2, 3, 82), at(HALF - 1, H - 1, -30), gold, Enum.Material.Metal)
	-- muro interior bajo que separa el salón del jardín, con un arco central
	part(m, "DivisionO", Vector3.new(56, 14, 2), at(-42, 7, 10), stone, Enum.Material.Marble)
	part(m, "DivisionE", Vector3.new(56, 14, 2), at(42, 7, 10), stone, Enum.Material.Marble)
	part(m, "DivisionOro", Vector3.new(56, 1, 2.4), at(-42, 14.5, 10), gold, Enum.Material.Metal)
	part(m, "DivisionOroE", Vector3.new(56, 1, 2.4), at(42, 14.5, 10), gold, Enum.Material.Metal)
	-- COLUMNAS y faroles del salón
	for _, dx in ipairs({ -34, 34 }) do
		for _, dz in ipairs({ -60, -30, 0 }) do
			part(m, "Columna", Vector3.new(4, H, 4), at(dx, H / 2, dz), stone, Enum.Material.Marble)
			local lamp = part(m, "Farol", Vector3.new(2, 2, 2), at(dx, 24, dz), Color3.fromRGB(255, 226, 150), Enum.Material.Neon)
			local pl = Instance.new("PointLight")
			pl.Range, pl.Brightness, pl.Color = 30, 0.7, Color3.fromRGB(255, 226, 170)
			pl.Parent = lamp
		end
	end
	local sky = Instance.new("PointLight")
	sky.Range, sky.Brightness = 40, 0.4
	sky.Parent = ceil
	-- LÁMPARA central colgante
	local chand = part(m, "Lampara", Vector3.new(6, 1, 6), at(0, H - 4, -30), gold, Enum.Material.Metal)
	local chl = Instance.new("PointLight")
	chl.Range, chl.Brightness, chl.Color = 45, 0.9, Color3.fromRGB(255, 232, 180)
	chl.Parent = chand

	-- SALIDA (portal blanco, al fondo del vestíbulo)
	local exitPad = buildPad(m, "Portal_Salida", at(0, 1.4, -62), Color3.fromRGB(255, 255, 255), "SALIR A LA CIUDAD")
	prompt(exitPad, "Salir", "Portal de salida", Enum.KeyCode.E, 0.5, function(pl)
		-- vale si figura dentro o si físicamente está en esta casa (el estado pudo perderse)
		local r = rootOf(pl)
		local physically = r ~= nil and (r.Position - o).Magnitude < HOUSE_W
		if inside[pl] == owner or physically then
			exitHouse(pl)
		end
	end)
	-- BAÚL (ala oeste, solo el dueño)
	local chest = part(m, "Baul", Vector3.new(8, 5, 5), at(-56, 3.5, -30), Color3.fromRGB(122, 78, 38), Enum.Material.Wood)
	part(m, "BaulTapa", Vector3.new(8.4, 1.4, 5.4), at(-56, 6.4, -30), gold, Enum.Material.Metal)
	sign(chest, "BAÚL PRIVADO", gold, 5)
	prompt(chest, "Abrir baúl", "Baúl privado", Enum.KeyCode.E, 0.3, function(pl)
		if pl ~= owner then
			say(pl, "Solo el dueño puede abrir este baúl.")
			return
		end
		OpenRemote:FireClient(pl, "Vault")
		buildPush(pl)
	end)
	-- TABLÓN de invitados (ala este, solo el dueño)
	local board = part(m, "Tablon", Vector3.new(10, 6, 1), at(58, 5, -30), wood, Enum.Material.Wood)
	sign(board, "INVITADOS", gold, 5)
	prompt(board, "Invitados", "Tablón de invitados", Enum.KeyCode.E, 0.3, function(pl)
		if pl ~= owner then
			say(pl, "Solo el dueño puede invitar o expulsar.")
			return
		end
		OpenRemote:FireClient(pl, "Guests")
		buildPush(pl)
	end)
	-- Sala de DECORACIÓN reservada (Fase 3): pedestal vacío
	local deco = part(m, "Pedestal", Vector3.new(10, 1, 10), at(0, 1.6, -46), gold, Enum.Material.Metal)
	sign(deco, "RINCÓN DE DECORACIÓN (próximamente)", Color3.fromRGB(255, 236, 170), 4)

	-- JARDÍN DE MASCOTAS (norte, cielo abierto): césped, estanque, árboles, valla y la caseta donde se sueltan / se agarran
	local GZ = 42 -- centro del jardín en z
	part(m, "Cesped", Vector3.new(W - 6, 0.4, 46), at(0, 1.2, 45), Color3.fromRGB(86, 150, 78), Enum.Material.Grass)
	local pond = part(m, "Estanque", Vector3.new(24, 0.3, 16), at(-30, 1.45, GZ + 14), Color3.fromRGB(70, 150, 210), Enum.Material.Glass)
	pond.Transparency = 0.25
	for i = -3, 3 do
		part(m, "Valla" .. i, Vector3.new(2, 4, 2), at(i * 18, 3, 12), wood, Enum.Material.Wood)
	end
	part(m, "VallaTravesano", Vector3.new(W - 6, 0.8, 0.8), at(0, 4.2, 12), wood, Enum.Material.Wood)
	local hut = part(m, "Caseta", Vector3.new(14, 7, 10), at(30, 4.5, GZ - 4), Color3.fromRGB(160, 110, 66), Enum.Material.WoodPlanks)
	part(m, "CasetaTecho", Vector3.new(17, 1.5, 13), at(30, 8.8, GZ - 4), Color3.fromRGB(150, 50, 56), Enum.Material.Wood)
	sign(hut, "CASETA DE MASCOTAS", Color3.fromRGB(190, 255, 200), 7)
	prompt(hut, "Mascotas y monturas", "Caseta de animales", Enum.KeyCode.E, 0.4, function(pl)
		if pl ~= owner then
			say(pl, "Solo el dueño puede soltar o agarrar sus animales.")
			return
		end
		pl:SetAttribute("PetsHomeR", 30)
		OpenRemote:FireClient(pl, "Animals")
		buildPush(pl)
	end)
	local FACTION_COLOR: { [string]: Color3 } = {
		Imperio_Saiyan = Color3.fromRGB(220, 120, 40),
		Alianza_Shinobi = Color3.fromRGB(70, 130, 220),
		Flota_Pirata = Color3.fromRGB(200, 50, 60),
		Corte_Shinigami = Color3.fromRGB(150, 90, 220),
	}
	local okDecor, errDecor = pcall(HouseDecor.Build, m, o, W, H, GZ, FACTION_COLOR[tostring(owner:GetAttribute("Faction"))] or gold, owner.DisplayName)
	if not okDecor then
		warn("[HouseService] decoración falló: " .. tostring(errDecor))
	end
	m.Parent = Workspace
	local h: House = { Owner = owner, Slot = slot, Origin = o, Model = m, Garden = at(0, 1.6, GZ + 6) }
	houses[owner] = h
	return h
end

local function enterHouse(player: Player, host: Player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	if not hum or hum.Health <= 0 or not root or inside[player] then
		return
	end
	local h = houses[host] or buildHouse(host)
	if not h then
		say(player, "La casa no está disponible ahora. Prueba en un momento.")
		return
	end
	returnCF[player] = root.CFrame
	inside[player] = host
	player:SetAttribute("InHouse", true)
	moveTo(player, CFrame.new(h.Origin + Vector3.new(0, 5, -54)) * CFrame.Angles(0, math.rad(180), 0))
	if player ~= host then
		say(host, player.DisplayName .. " entró a tu casa.")
	end
end

local function closeHouse(owner: Player)
	local h = houses[owner]
	if not h then
		return
	end
	for pl, host in pairs(inside) do
		if host == owner and pl ~= owner then
			exitHouse(pl)
			say(pl, "El dueño se fue: la casa se cerró.")
		end
	end
	owner:SetAttribute("PetsHome1", nil)
	owner:SetAttribute("PetsHome2", nil)
	owner:SetAttribute("MountHome", nil)
	owner:SetAttribute("MountHomeKeys", nil)
	usedSlots[h.Slot] = nil
	houses[owner] = nil
	h.Model:Destroy()
end

---------------------------------------------------------------------
-- Portal de la ciudad
---------------------------------------------------------------------
local function player_grabAll(pl: Player)
	pl:SetAttribute("PetsHome1", nil)
	pl:SetAttribute("PetsHome2", nil)
	setMountKeys(pl, {})
	say(pl, "Tus animales volvieron contigo.")
end

function HouseService.AddCityPortal(faction: string, pos: Vector3)
	if portals[faction] then
		return
	end
	portals[faction] = pos
	-- BUZÓN de la ciudad (aquí llega lo que no cabe en el baúl cuando termina la suscripción)
	local boxPos = pos + Vector3.new(0, 0, 18)
	table.insert(mailboxes, boxPos)
	local box = Instance.new("Part")
	box.Name = "Buzon_" .. faction
	box.Anchored = true
	box.Size = Vector3.new(3.4, 5, 2.4)
	box.CFrame = CFrame.new(boxPos + Vector3.new(0, 2.5, 0))
	box.Color = Color3.fromRGB(190, 50, 56)
	box.Material = Enum.Material.Metal
	box.Parent = Workspace
	local top = Instance.new("Part")
	top.Anchored = true
	top.Shape = Enum.PartType.Cylinder
	top.Size = Vector3.new(3.4, 3.4, 3.4)
	top.CFrame = CFrame.new(boxPos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	top.Color = Color3.fromRGB(190, 50, 56)
	top.Material = Enum.Material.Metal
	top.Parent = Workspace
	sign(box, "📮 BUZÓN", Color3.fromRGB(255, 220, 140), 5)
	prompt(box, "Abrir buzón", "Buzón de la ciudad", Enum.KeyCode.E, 0.3, function(pl)
		OpenRemote:FireClient(pl, "Mail")
		buildPush(pl)
	end)
	local pad = buildPad(Workspace, "Portal_CasaVIP_" .. faction, pos, Color3.fromRGB(255, 200, 90), "🏠 PABELLÓN IMPERIAL")
	-- recoger todos los animales sueltos desde la ciudad
	local grabPrompt = prompt(pad, "Agarrar animales", "Casa VIP", Enum.KeyCode.F, 0.4, function(pl)
		if houses[pl] then
			player_grabAll(pl)
		end
	end)
	grabPrompt.UIOffset = Vector2.new(0, -90) -- que no se encime con "Entrar"
	prompt(pad, "Entrar", "Casa VIP", Enum.KeyCode.E, 0.6, function(pl)
		if pl:GetAttribute("Faction") ~= faction then
			say(pl, "Este portal es de la facción " .. faction .. ".")
			return
		end
		if hasPass(pl) then
			enterHouse(pl, pl)
			return
		end
		if lic[pl] and not lic[pl].On then
			say(pl, "Tu Casa VIP venció por falta de suscripción. Se abrirá la recompra del Pabellón (si quedan casas).")
			HouseService.RequestRebuy(pl)
			return
		end
		local host = invitedBy[pl]
		if host and host.Parent and invited[host] and invited[host][pl.UserId] and houses[host] then
			enterHouse(pl, host)
		elseif host and host.Parent and invited[host] and invited[host][pl.UserId] then
			-- el dueño aún no abrió su casa: se abre al entrar él; mientras, que avise
			say(pl, host.DisplayName .. " debe abrir su casa primero.")
		else
			say(pl, "Necesitas el pase Pabellón Imperial (Tienda > Pases) o que te inviten.")
		end
	end)
end

---------------------------------------------------------------------
-- Baúl
---------------------------------------------------------------------
local function cleanStack(raw: any): Stack?
	if typeof(raw) ~= "table" or typeof(raw.Id) ~= "string" or typeof(raw.Count) ~= "number" then
		return nil
	end
	local it: any = (ItemCatalog.Items :: any)[raw.Id]
	if not it then
		return nil
	end
	return {
		Id = raw.Id,
		Count = math.clamp(math.floor(raw.Count), 1, it.Stack or 1),
		Plus = if typeof(raw.Plus) == "number" and raw.Plus > 0 then math.clamp(math.floor(raw.Plus), 1, 9) else nil,
		Locked = if raw.Locked == true then true else nil,
	}
end

local function vaultAdd(player: Player, id: string, count: number, plus: number, locked: boolean?): boolean
	local v = vaults[player]
	local it: any = (ItemCatalog.Items :: any)[id]
	if not v or not it then
		return false
	end
	local maxStack = it.Stack or 1
	if not locked then
		for _, st in pairs(v) do
			if count <= 0 then
				break
			end
			if st.Id == id and (st.Plus or 0) == plus and not st.Locked and st.Count < maxStack then
				local add = math.min(maxStack - st.Count, count)
				st.Count += add
				count -= add
			end
		end
	end
	local cap = math.max(vaultCap(player), 0)
	while count > 0 do
		local free: number? = nil
		for i = 1, cap do
			if not v[i] then
				free = i
				break
			end
		end
		if not free then
			return false
		end
		local add = math.min(maxStack, count)
		v[free] = { Id = id, Count = add, Plus = if plus > 0 then plus else nil, Locked = locked }
		count -= add
	end
	return true
end

local function vaultFreeFor(player: Player, id: string, count: number, plus: number, locked: boolean?): boolean
	-- comprobación en seco con una copia: ¿cabe todo?
	local v = vaults[player]
	if not v then
		return false
	end
	local backup: { [number]: Stack } = {}
	for i, st in pairs(v) do
		backup[i] = table.clone(st)
	end
	local ok = vaultAdd(player, id, count, plus, locked)
	vaults[player] = backup
	return ok
end

buildPush = function(player: Player)
	local isOwner = hasPass(player)
	local vault: { any } = {}
	local bag: { any } = {}
	if isOwner then
		for slot, st in pairs(vaults[player] or {}) do
			table.insert(vault, { Slot = slot, Id = st.Id, Count = st.Count, Plus = st.Plus or 0, Locked = st.Locked == true })
		end
		local inv = Inventory.Get(player)
		if inv then
			for slot, st in pairs(inv.Bag) do
				table.insert(bag, { Slot = slot, Id = st.Id, Count = st.Count, Plus = st.Plus or 0, Locked = st.Locked == true })
			end
		end
	end
	local people: { any } = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= player then
			table.insert(people, { UserId = pl.UserId, Name = pl.DisplayName, Invited = invited[player] ~= nil and invited[player][pl.UserId] == true, Inside = inside[pl] == player })
		end
	end
	local animals: { any } = {}
	local function addAnimal(key: string, name: string?, released: boolean)
		if name then
			table.insert(animals, { Key = key, Name = name, Released = released })
		end
	end
	local function petName(slotAttr: string): string?
		local id = player:GetAttribute("Equip_" .. slotAttr)
		local it: any = if typeof(id) == "string" then (ItemCatalog.Items :: any)[id] else nil
		return if it and it.Pet then it.Name else nil
	end
	addAnimal("Pet1", petName("Accesorio2"), typeof(player:GetAttribute("PetsHome1")) == "Vector3")
	if player:GetAttribute("Pass_PetSlot") == true then
		addAnimal("Pet2", petName("Accesorio3"), typeof(player:GetAttribute("PetsHome2")) == "Vector3")
	end
	local outKeys = mountKeys(player)
	for _, mk in ipairs(outKeys) do
		local sp = MountCatalog.Parse(mk)
		if sp then
			addAnimal("Mount:" .. mk, sp.Name, true)
		end
	end
	local eqKey = player:GetAttribute("MountEquipped")
	local esp = MountCatalog.Parse(eqKey)
	if esp and typeof(eqKey) == "string" and not table.find(outKeys, eqKey) then
		addAnimal("Mount:" .. eqKey, esp.Name, false)
	end
	local mailList: { any } = {}
	for i, st in ipairs(mail[player] or {}) do
		table.insert(mailList, { Slot = i, Id = st.Id, Count = st.Count, Plus = st.Plus or 0, Locked = st.Locked == true })
	end
	StateRemote:FireClient(player, {
		Lapsed = lic[player] ~= nil and not lic[player].On,
		TimeLeft = if lic[player] and lic[player].On and player:GetAttribute("Sub_Vip") ~= true then math.max(0, lic[player].Until - os.time()) else nil, -- mes incluido / margen
		Grace = GRACE_SECONDS,
		Animals = animals,
		Mail = mailList,
		HasPass = isOwner,
		Cap = vaultCap(player),
		Sub = player:GetAttribute("Sub_Vip") == true,
		SubPrice = ProductCatalog.VipSub.PriceText,
		Vault = vault,
		Bag = bag,
		People = people,
		MaxGuests = MAX_GUESTS,
		At = if inside[player] == player then "Home" else if inside[player] then "Guest" else "Out",
	})
end

local function ownerHome(player: Player): boolean
	return hasPass(player) and inside[player] == player and houses[player] ~= nil
end

local function deposit(player: Player, slot: any, count: any)
	if not ownerHome(player) or typeof(slot) ~= "number" then
		return
	end
	local inv = Inventory.Get(player)
	local st = if inv then inv.Bag[math.floor(slot)] else nil
	if not st or st.Locked then
		say(player, "Ese objeto está bloqueado (candado).")
		return
	end
	local n = if typeof(count) == "number" then math.clamp(math.floor(count), 1, st.Count) else st.Count
	if not vaultFreeFor(player, st.Id, n, st.Plus or 0, nil) then
		say(player, "El baúl está lleno.")
		return
	end
	local id, plus, took = Inventory.RemoveSlot(player, slot, n)
	if not id or took < 1 then
		return
	end
	if not vaultAdd(player, id, took, plus, nil) then
		Inventory.Add(player, id, took, plus) -- no debería pasar: ya se comprobó que cabe
	end
end

local function withdraw(player: Player, slot: any)
	if not ownerHome(player) or typeof(slot) ~= "number" then
		return
	end
	local v = vaults[player]
	local st = if v then v[math.floor(slot)] else nil
	if not v or not st then
		return
	end
	if Inventory.Add(player, st.Id, st.Count, st.Plus, st.Locked) then
		v[math.floor(slot)] = nil
	end
end

local function invite(player: Player, userId: any, on: boolean)
	if not hasPass(player) or typeof(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return
	end
	local list = invited[player]
	if not list then
		list = {}
		invited[player] = list
	end
	if on then
		local n = 0
		for _ in pairs(list) do
			n += 1
		end
		if n >= MAX_GUESTS and not list[userId] then
			say(player, "Máximo de invitados: " .. MAX_GUESTS)
			return
		end
		list[userId] = true
		invitedBy[target] = player
		say(target, player.DisplayName .. " te invitó a su Casa VIP. Entra por el portal 🏠 de la plaza de tu ciudad.")
	else
		list[userId] = nil
		if invitedBy[target] == player then
			invitedBy[target] = nil
		end
		if inside[target] == player then
			exitHouse(target)
			say(target, "Ya no estás invitado a esa casa.")
		end
	end
end

function HouseService.SetRelease(player: Player, key: any, on: boolean)
	local h = houses[player]
	if not h or typeof(key) ~= "string" then
		return
	end
	-- SOLTAR solo estando dentro de la casa; AGARRAR se puede desde cualquier lado
	if on and inside[player] ~= player then
		return
	end
	local mkey = string.match(key, "^Mount:(.+)$")
	if mkey then
		local list = mountKeys(player)
		local idx = table.find(list, mkey)
		if on then
			if idx then
				return
			end
			if player:GetAttribute("MountEquipped") ~= mkey or player:GetAttribute("Mounted") == true then
				say(player, "Equipa esa montura y baja de ella para dejarla.")
				return
			end
			if #list >= MAX_MOUNTS_OUT then
				say(player, "Máximo " .. MAX_MOUNTS_OUT .. " monturas sueltas.")
				return
			end
			table.insert(list, mkey)
			player:SetAttribute("MountHome", h.Garden)
		elseif idx then
			table.remove(list, idx)
		end
		setMountKeys(player, list)
		return
	end
	local attr = if key == "Pet1" then "PetsHome1" elseif key == "Pet2" then "PetsHome2" else nil
	if not attr then
		return
	end
	if on then
		if key == "Pet2" and player:GetAttribute("Pass_PetSlot") ~= true then
			return
		end
		player:SetAttribute(attr, h.Garden)
	else
		player:SetAttribute(attr, nil)
	end
end

-- BUZÓN: guarda un objeto y devuelve si cupo
local function mailAdd(player: Player, st: Stack): boolean
	local list = mail[player]
	if not list or #list >= MAIL_MAX then
		return false
	end
	table.insert(list, { Id = st.Id, Count = st.Count, Plus = st.Plus, Locked = st.Locked })
	return true
end

function HouseService.MailClaim(player: Player, index: any)
	local list = mail[player]
	if not list then
		return
	end
	local near = false
	local r = rootOf(player)
	for _, p in ipairs(mailboxes) do
		if r and (r.Position - p).Magnitude < 45 then
			near = true
		end
	end
	if not near then
		return
	end
	if index == "all" then
		for i = #list, 1, -1 do
			local st = list[i]
			if Inventory.Add(player, st.Id, st.Count, st.Plus or 0, st.Locked) then
				table.remove(list, i)
			end
		end
	elseif typeof(index) == "number" and list[math.floor(index)] then
		local st = list[math.floor(index)]
		if Inventory.Add(player, st.Id, st.Count, st.Plus or 0, st.Locked) then
			table.remove(list, math.floor(index))
		else
			say(player, "Tu mochila está llena.")
		end
	end
end

ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, a: any, b: any)
	if typeof(action) ~= "string" then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < 0.12 then
		return
	end
	lastAction[player] = now
	if action == "Deposit" then
		deposit(player, a, b)
	elseif action == "Withdraw" then
		withdraw(player, a)
	elseif action == "Invite" then
		invite(player, a, true)
	elseif action == "Uninvite" then
		invite(player, a, false)
	elseif action == "Release" then
		HouseService.SetRelease(player, a, b == true)
	elseif action == "Rebuy" then
		HouseService.RequestRebuy(player)
		return
	elseif action == "MailClaim" then
		HouseService.MailClaim(player, a)
	elseif action == "Exit" then
		exitHouse(player)
		return
	elseif action == "BuySub" then
		local id = ProductCatalog.VipSub.SubId
		if id ~= "" then
			pcall(MarketplaceService.PromptSubscriptionPurchase, MarketplaceService, player, id)
		else
			say(player, "La suscripción aún no está a la venta.")
		end
		return
	end
	buildPush(player)
end)

---------------------------------------------------------------------
-- Cupo de casas (registro compartido entre servidores): reservar al pulsar comprar, reclamar al pagar, liberar si no se paga
---------------------------------------------------------------------
local registryStore: DataStore? = nil
do
	local ok, r = pcall(function()
		return DataStoreService:GetDataStore("VipHouses_v1")
	end)
	if ok then
		registryStore = r :: DataStore
	end
end

local function countKeys(t: any): number
	local n = 0
	if typeof(t) == "table" then
		for _ in pairs(t) do
			n += 1
		end
	end
	return n
end

local function publishLeft(reg: any)
	local left = ProductCatalog.VIP_HOUSE_CAP - countKeys(reg.Claimed) - countKeys(reg.Reserved)
	Workspace:SetAttribute("VipHousesCap", ProductCatalog.VIP_HOUSE_CAP)
	Workspace:SetAttribute("VipHousesLeft", math.max(0, left))
end

-- fn recibe el registro limpio y devuelve (resultado); se aplica de forma atómica
local function registry(fn: (any, number) -> any): (boolean, any)
	if not registryStore then
		return false, nil
	end
	local result: any = nil
	local ok = pcall(function()
		(registryStore :: DataStore):UpdateAsync("Registry", function(old: any)
			local reg: any = if typeof(old) == "table" then old else {}
			reg.Claimed = if typeof(reg.Claimed) == "table" then reg.Claimed else {}
			reg.Reserved = if typeof(reg.Reserved) == "table" then reg.Reserved else {}
			local now = os.time()
			for uid, exp in pairs(reg.Reserved) do
				if typeof(exp) ~= "number" or exp < now then
					reg.Reserved[uid] = nil
				end
			end
			result = fn(reg, now)
			publishLeft(reg)
			return reg
		end)
	end)
	return ok, result
end

-- true = puede comprar (ya tenía casa, o se le reservó una). En Studio / sin DataStore no hay límite.
function HouseService.Reserve(player: Player): (boolean, string?)
	if not registryStore or RunService:IsStudio() then
		return true, nil
	end
	local uid = tostring(player.UserId)
	local ok, res = registry(function(reg: any, now: number)
		if reg.Claimed[uid] then
			return "ya"
		end
		local others = countKeys(reg.Claimed) + countKeys(reg.Reserved) - (if reg.Reserved[uid] then 1 else 0)
		if others >= ProductCatalog.VIP_HOUSE_CAP then
			return "lleno"
		end
		reg.Reserved[uid] = now + ProductCatalog.VIP_RESERVE_SECONDS
		return "ok"
	end)
	if not ok then
		return false, "No se pudo comprobar el cupo de casas. Inténtalo de nuevo."
	end
	if res == "lleno" then
		return false, "¡Agotado! Ya se vendieron todas las casas VIP. Si alguien no completa su compra se libera un cupo."
	end
	return true, nil
end

function HouseService.Claim(player: Player)
	if not registryStore or RunService:IsStudio() then
		return
	end
	local uid = tostring(player.UserId)
	registry(function(reg: any)
		reg.Reserved[uid] = nil
		reg.Claimed[uid] = true -- quien ya pagó siempre conserva su casa, aunque se haya pasado del cupo
		return "ok"
	end)
end

function HouseService.Unclaim(player: Player)
	if not registryStore or RunService:IsStudio() then
		return
	end
	local uid = tostring(player.UserId)
	registry(function(reg: any)
		reg.Reserved[uid] = nil
		reg.Claimed[uid] = nil -- el cupo vuelve a quedar libre
		return "ok"
	end)
end

function HouseService.Release(player: Player)
	if not registryStore or RunService:IsStudio() then
		return
	end
	local uid = tostring(player.UserId)
	registry(function(reg: any)
		reg.Reserved[uid] = nil
		return "ok"
	end)
end

task.spawn(function()
	while registryStore and not RunService:IsStudio() do
		registry(function()
			return "leer"
		end)
		task.wait(90)
	end
end)

---------------------------------------------------------------------
-- Suscripción (estado mensual, lo comprueba el servidor)
---------------------------------------------------------------------
local function publishLicense(player: Player)
	local L = lic[player]
	player:SetAttribute("House_Active", L ~= nil and L.On)
end

-- Da (o devuelve) la licencia de casa: pago único hecho. Se pide la suscripción mensual para seguir usándola.
function HouseService.GrantLicense(player: Player)
	lic[player] = { On = true, Until = os.time() + INCLUDED_SECONDS } -- 30 días incluidos en el pago único
	rebuying[player] = nil
	publishLicense(player)
	task.spawn(HouseService.Claim, player)
	say(player, "¡Pabellón Imperial activado! El primer mes (30 días) va incluido. Después, suscríbete (199 R$/mes) para seguir usándolo.")
	buildPush(player)
end

-- La licencia venció (suscripción sin renovar): se pierde la casa; el baúl entero pasa al buzón y se libera el cupo
local function lapse(player: Player)
	local L = lic[player]
	if not L or not L.On then
		return
	end
	L.On = false
	publishLicense(player)
	local v = vaults[player]
	local moved = 0
	if v then
		for i, st in pairs(v) do
			if mailAdd(player, st) then
				v[i] = nil
				moved += 1
			end
		end
	end
	player:SetAttribute("PetsHome1", nil)
	player:SetAttribute("PetsHome2", nil)
	player:SetAttribute("MountHome", nil)
	player:SetAttribute("MountHomeKeys", nil)
	exitHouse(player)
	closeHouse(player)
	task.spawn(HouseService.Unclaim, player)
	say(player, string.format("Tu Casa VIP venció (suscripción sin renovar). %d objetos del baúl están en el buzón de la ciudad. Para recuperar la casa hay que pagar de nuevo el Pabellón, si quedan casas.", moved))
	PlayerData.Save(player)
end

-- Se llama tras consultar la suscripción (estado definitivo) y cuando cambia el pase
function HouseService.Evaluate(player: Player)
	local subscribed = player:GetAttribute("Sub_Vip") == true
	local L = lic[player]
	local now = os.time()
	if not L then
		if player:GetAttribute("Pass_VipHouse") == true then
			HouseService.GrantLicense(player) -- compra anterior del pase: empieza su ciclo (margen para suscribirse)
		end
	elseif L.On then
		if subscribed then
			L.Until = math.max(L.Until, now + GRACE_SECONDS) -- nunca se acorta el mes incluido
		elseif now > L.Until + GRACE_SECONDS then
			lapse(player)
		elseif L.Until - now < REMIND_SECONDS and not reminded[player] then
			reminded[player] = true
			say(player, string.format("Tu mes incluido del Pabellón termina en %d días. Suscríbete (199 R$/mes) en la pestaña Suscripción de tu casa para no perderlo.", math.max(0, math.ceil((L.Until - now) / 86400))))
		end
	end
	publishLicense(player)
end

-- Recompra (casa vencida): reserva cupo y abre el pago del Developer Product "VipHouseRebuy"
function HouseService.RequestRebuy(player: Player)
	if hasPass(player) or rebuying[player] then
		return
	end
	local okSlot, why = HouseService.Reserve(player)
	if not okSlot then
		say(player, why or "Sin cupo de casas")
		return
	end
	local prod = ProductCatalog.ByKey.VipHouseRebuy
	if prod and prod.ProductId > 0 then
		rebuying[player] = true
		local started = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, prod.ProductId)
		if not started then
			rebuying[player] = nil
			task.spawn(HouseService.Release, player)
			say(player, "No se pudo abrir la compra.")
		end
	elseif RunService:IsStudio() then
		HouseService.GrantLicense(player) -- prueba en Studio
	else
		task.spawn(HouseService.Release, player)
		say(player, "La recompra aún no está a la venta.")
	end
end

function HouseService.RebuyCancelled(player: Player)
	if rebuying[player] then
		rebuying[player] = nil
		task.spawn(HouseService.Release, player)
	end
end

local function checkSub(player: Player)
	local subscribed = false
	local definitive = true -- si Roblox no responde NO se toca nada (no se manda nada al buzón por error)
	if RunService:IsStudio() then
		subscribed = ProductCatalog.DevOwnSub
	elseif ProductCatalog.VipSub.SubId ~= "" then
		local ok, res = pcall(MarketplaceService.GetUserSubscriptionStatusAsync, MarketplaceService, player, ProductCatalog.VipSub.SubId)
		if ok and typeof(res) == "table" then
			subscribed = (res :: any).IsSubscribed == true
		else
			definitive = false
		end
	end
	if player.Parent and (definitive or player:GetAttribute("Sub_Vip") == nil) then
		player:SetAttribute("Sub_Vip", if definitive then subscribed else false)
	end
	if definitive and player.Parent then
		HouseService.Evaluate(player)
	end
end

pcall(function()
	Players.UserSubscriptionStatusChanged:Connect(function(player: Player, subId: string)
		if subId == ProductCatalog.VipSub.SubId then
			checkSub(player)
			buildPush(player)
		end
	end)
end)

---------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------
PlayerData.RegisterSerializer("House", function(player: Player): any?
	local v = vaults[player]
	if (not v or next(v) == nil) and #(mail[player] or {}) == 0 and not lic[player] then
		return nil
	end
	v = v or {}
	local out: { [string]: any } = {}
	for i, st in pairs(v) do
		out[tostring(i)] = { Id = st.Id, Count = st.Count, Plus = st.Plus, Locked = st.Locked }
	end
	local m: { any } = {}
	for _, st in ipairs(mail[player] or {}) do
		table.insert(m, { Id = st.Id, Count = st.Count, Plus = st.Plus, Locked = st.Locked })
	end
	local L = lic[player]
	return { V = out, M = m, L = if L then { On = L.On, Until = L.Until } else nil }
end)

local function init(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return
	end
	local v: { [number]: Stack } = {}
	local raw: any = (saved :: any).House
	if typeof(raw) == "table" and typeof(raw.V) == "table" then
		for k, st in pairs(raw.V) do
			local i = tonumber(k)
			local c = cleanStack(st)
			if i and c and i >= 1 and i <= 200 then
				v[math.floor(i)] = c
			end
		end
	end
	vaults[player] = v
	local ml: { Stack } = {}
	if typeof(raw) == "table" and typeof(raw.M) == "table" then
		for _, st in ipairs(raw.M) do
			local c = cleanStack(st)
			if c and #ml < MAIL_MAX then
				table.insert(ml, c)
			end
		end
	end
	mail[player] = ml
	if typeof(raw) == "table" and typeof(raw.L) == "table" and typeof(raw.L.On) == "boolean" and typeof(raw.L.Until) == "number" then
		lic[player] = { On = raw.L.On, Until = raw.L.Until }
	end
	publishLicense(player)
	checkSub(player)
	-- el pase se detecta después (PurchaseService): al aparecer, se evalúa la licencia
	player:GetAttributeChangedSignal("Pass_VipHouse"):Connect(function()
		HouseService.Evaluate(player)
	end)
end

local function leave(player: Player)
	if inside[player] then
		inside[player] = nil
	end
	closeHouse(player)
	invited[player] = nil
	invitedBy[player] = nil
	for host, list in pairs(invited) do
		list[player.UserId] = nil
		if inside[player] == host then
			inside[player] = nil
		end
	end
	returnCF[player] = nil
	lastAction[player] = nil
end

-- cada 10 minutos se vuelve a consultar la suscripción de quien tiene licencia (puede vencer con la sesión abierta)
task.spawn(function()
	while true do
		task.wait(600)
		for _, pl in ipairs(Players:GetPlayers()) do
			if lic[pl] and lic[pl].On then
				task.spawn(checkSub, pl)
			end
		end
	end
end)

local function hookChar(pl: Player)
	pl.CharacterAdded:Connect(function()
		-- si muere dentro de la casa reaparece en su ciudad: ya no está dentro
		inside[pl] = nil
		pl:SetAttribute("InHouse", nil)
		returnCF[pl] = nil
	end)
end
Players.PlayerAdded:Connect(function(pl)
	hookChar(pl)
	task.spawn(init, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	hookChar(pl)
	task.spawn(init, pl)
end
Players.PlayerRemoving:Connect(leave)
PlayerData.Releasing:Connect(function(pl: Player)
	lic[pl] = nil
	rebuying[pl] = nil
	reminded[pl] = nil
	vaults[pl] = nil
	mail[pl] = nil
end)

return HouseService
