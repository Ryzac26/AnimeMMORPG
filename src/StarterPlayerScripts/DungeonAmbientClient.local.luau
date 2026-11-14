--!strict
--[[
    DungeonAmbientClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DungeonAmbientClient
    1) LUZ DE CUEVA. Mientras estás dentro de una cueva (DungeonService pone el atributo de jugador "InDungeon" = número de franja) la luz
       cambia a CUEVA: de noche, ambiente muy oscuro con un tinte según la franja, niebla cercana y sin reflejos del cielo. Las antorchas,
       los braseros y los cristales de la cueva son lo que ilumina. Al salir vuelve suavemente a la luz que tenías al entrar.
       Se aplica cada fotograma (después de BiomeAmbientClient / HouseAmbientClient) para que ninguno le gane a la cueva.
    2) TRANSICIÓN en dos tiempos (entrar / cambiar de piso / salir de la cueva). El servidor pone el atributo "DungeonTransit":
         a) PREPARACIÓN: sigues en el mundo y ves un aviso abajo ("Entrando a la cueva…") mientras tu cliente recibe el destino. Este script mira
            si ya hay SUELO en el destino ("DungeonDest") y se lo avisa al servidor por el remoto DungeonReady.
         b) SALTO: el servidor pone "DungeonCover": fundido a negro corto, te teletransporta (anclado un instante, no caes) y aquí se destapa en
            cuanto hay suelo bajo tus pies. Si algo falla, se destapa sola (topes de seguridad).
    Crea una ScreenGui propia "DungeonTransition" (se queda siempre en PlayerGui). No va en UIReloadClient.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local FADE_IN = 1.2 -- segundos hasta la luz de cueva
local FADE_OUT = 1.6 -- segundos hasta volver a la luz de afuera

type Look = {
	Ambient: Color3,
	OutdoorAmbient: Color3,
	FogColor: Color3,
	FogStart: number,
	FogEnd: number,
	Brightness: number,
	ClockTime: number,
	EnvironmentDiffuseScale: number,
	EnvironmentSpecularScale: number,
}

-- una luz por franja (1..4); más clara = más visible. Si se ve demasiado oscuro, sube Ambient/OutdoorAmbient y Brightness.
local LOOKS: { [number]: Look } = {
	[1] = { Ambient = Color3.fromRGB(46, 48, 58), OutdoorAmbient = Color3.fromRGB(48, 52, 64), FogColor = Color3.fromRGB(10, 14, 22), FogStart = 30, FogEnd = 300, Brightness = 0.05, ClockTime = 0, EnvironmentDiffuseScale = 0.1, EnvironmentSpecularScale = 0.1 },
	[2] = { Ambient = Color3.fromRGB(38, 54, 58), OutdoorAmbient = Color3.fromRGB(40, 58, 62), FogColor = Color3.fromRGB(6, 20, 20), FogStart = 30, FogEnd = 300, Brightness = 0.05, ClockTime = 0, EnvironmentDiffuseScale = 0.1, EnvironmentSpecularScale = 0.1 },
	[3] = { Ambient = Color3.fromRGB(56, 42, 68), OutdoorAmbient = Color3.fromRGB(60, 46, 74), FogColor = Color3.fromRGB(18, 8, 28), FogStart = 30, FogEnd = 300, Brightness = 0.05, ClockTime = 0, EnvironmentDiffuseScale = 0.1, EnvironmentSpecularScale = 0.1 },
	[4] = { Ambient = Color3.fromRGB(66, 42, 38), OutdoorAmbient = Color3.fromRGB(72, 46, 40), FogColor = Color3.fromRGB(26, 8, 4), FogStart = 30, FogEnd = 300, Brightness = 0.05, ClockTime = 0, EnvironmentDiffuseScale = 0.1, EnvironmentSpecularScale = 0.1 },
}

local function read(): Look
	return {
		Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient,
		FogColor = Lighting.FogColor,
		FogStart = Lighting.FogStart,
		FogEnd = Lighting.FogEnd,
		Brightness = Lighting.Brightness,
		ClockTime = Lighting.ClockTime,
		EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
	}
end

local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function write(a: Look, b: Look, t: number)
	Lighting.Ambient = a.Ambient:Lerp(b.Ambient, t)
	Lighting.OutdoorAmbient = a.OutdoorAmbient:Lerp(b.OutdoorAmbient, t)
	Lighting.FogColor = a.FogColor:Lerp(b.FogColor, t)
	Lighting.FogStart = mix(a.FogStart, b.FogStart, t)
	Lighting.FogEnd = mix(a.FogEnd, b.FogEnd, t)
	Lighting.Brightness = mix(a.Brightness, b.Brightness, t)
	Lighting.ClockTime = mix(a.ClockTime, b.ClockTime, t) -- de 14 a 0 pasa por la tarde y la noche; con la niebla no se nota
	Lighting.EnvironmentDiffuseScale = mix(a.EnvironmentDiffuseScale, b.EnvironmentDiffuseScale, t)
	Lighting.EnvironmentSpecularScale = mix(a.EnvironmentSpecularScale, b.EnvironmentSpecularScale, t)
end

local base: Look? = nil -- la luz de afuera, guardada al entrar
local k = 0 -- 0 = afuera, 1 = dentro de la cueva
local strip = 1

RunService:BindToRenderStep("DungeonAmbient", Enum.RenderPriority.Last.Value, function(dt: number)
	local s = player:GetAttribute("InDungeon")
	local inside = typeof(s) == "number"
	if inside then
		strip = math.clamp(math.floor(s :: number), 1, 4)
	end
	if not inside and k <= 0 then
		return -- afuera: no se toca nada
	end
	if inside and not base then
		base = read()
	end
	local b = base
	if not b then
		return
	end
	if inside then
		k = math.min(1, k + dt / FADE_IN)
	else
		k = math.max(0, k - dt / FADE_OUT)
	end
	local t = k * k * (3 - 2 * k) -- suavizado
	write(b, LOOKS[strip] or LOOKS[1], t)
	if k <= 0 then
		base = nil -- ya está igual que afuera: se deja de tocar la luz
	end
end)

---------------------------------------------------------------------
-- TRANSICIÓN (entrar / cambiar de piso / salir de la cueva)
---------------------------------------------------------------------
local DEBUG = true -- imprime los tiempos de cada traslado (ponlo en false cuando ya no lo necesites)
local FADE_TO_BLACK = 0.25 -- segundos de fundido a negro
local FADE_FROM_BLACK = 0.5 -- segundos de fundido de vuelta
local READY_EXTRA = 0.5 -- tras ver el suelo del destino, espera un poco más para que lleguen también paredes y adornos
local READY_GIVEUP = 8 -- si en 8 s no se ve el suelo del destino, avisa igual (el servidor ya habrá seguido por tiempo)
local MIN_HOLD = 0.15 -- segundos mínimos tapada después de que el servidor suelta
local MAX_HOLD = 6 -- tope de espera por el suelo después de que el servidor suelta (si no llega, se destapa igual)
local FAILSAFE = 30 -- si el servidor nunca suelta (error), se destapa igual
local MIN_JUMP = 60 -- los traslados mueven al jugador mucho más que esto: así no se destapa antes de llegar

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local readyRemote = remotes:WaitForChild("DungeonReady", 60) -- lo crea DungeonService; si no existe, el servidor salta por tiempo

	local gui = Instance.new("ScreenGui")
	gui.Name = "DungeonTransition"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 900
	gui.Enabled = false

	local cover = Instance.new("Frame")
	cover.Name = "Cover"
	cover.Size = UDim2.fromScale(1, 1)
	cover.BackgroundColor3 = Color3.new(0, 0, 0)
	cover.BackgroundTransparency = 1
	cover.BorderSizePixel = 0
	cover.Parent = gui

	local label = Instance.new("TextLabel") -- texto grande, en el centro, solo mientras la pantalla está negra
	label.Name = "Texto"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromOffset(460, 40)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(215, 215, 225)
	label.TextTransparency = 1
	label.Text = ""
	label.Parent = cover

	local pill = Instance.new("TextLabel") -- aviso pequeño, abajo, mientras todavía ves el mundo
	pill.Name = "Aviso"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.fromScale(0.5, 0.86)
	pill.Size = UDim2.fromOffset(0, 36)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
	pill.BackgroundTransparency = 0.25
	pill.BorderSizePixel = 0
	pill.Font = Enum.Font.GothamMedium
	pill.TextSize = 18
	pill.TextColor3 = Color3.fromRGB(235, 235, 245)
	pill.Text = ""
	pill.Visible = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = pill
	pill.Parent = gui

	gui.Parent = playerGui

	local active: number? = nil -- identificador del traslado en curso
	local covered = false -- ¿ya está negra la pantalla?
	local startPos: Vector3? = nil
	local shownAt = 0
	local coveredAt = 0
	local running: { [Instance]: Tween } = {}

	local function tween(obj: Instance, time: number, goal: { [string]: any })
		local old = running[obj]
		if old then
			old:Cancel()
		end
		local t = TweenService:Create(obj, TweenInfo.new(time), goal)
		running[obj] = t
		t:Play()
	end

	local function rootPart(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return if r and r:IsA("BasePart") then r else nil
	end

	local function rayDown(from: Vector3, length: number): boolean
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ch = player.Character
		if ch then
			params.FilterDescendantsInstances = { ch }
		end
		return Workspace:Raycast(from, Vector3.new(0, -length, 0), params) ~= nil
	end

	-- ¿hay suelo debajo del jugador? (al llegar al destino)
	local function floorUnderfoot(): boolean
		local r = rootPart()
		return r ~= nil and rayDown(r.Position, 60)
	end

	-- ¿ya llegó al cliente el suelo del destino? (el destino está unos 4 studs sobre el suelo)
	local function destReady(): boolean
		local dest = player:GetAttribute("DungeonDest")
		return typeof(dest) == "Vector3" and rayDown((dest :: Vector3) + Vector3.new(0, 20, 0), 60)
	end

	local function hide()
		active = nil
		covered = false
		pill.Visible = false
		tween(cover, FADE_FROM_BLACK, { BackgroundTransparency = 1 })
		tween(label, FADE_FROM_BLACK * 0.7, { TextTransparency = 1 })
		if DEBUG then
			print(string.format("[DungeonTransition] en el mundo %.2f s · pantalla negra %.2f s", math.max(0, coveredAt - shownAt), if coveredAt > 0 then os.clock() - coveredAt else 0))
		end
		task.delay(FADE_FROM_BLACK + 0.05, function()
			if active == nil then
				gui.Enabled = false
			end
		end)
	end

	local function prep(id: number)
		active = id
		covered = false
		shownAt = os.clock()
		coveredAt = 0
		local t = player:GetAttribute("DungeonTransitText")
		local text = if typeof(t) == "string" then t else "Cargando…"
		label.Text = text
		pill.Text = text
		pill.Visible = true
		gui.Enabled = true
		tween(cover, 0.05, { BackgroundTransparency = 1 })
		tween(label, 0.05, { TextTransparency = 1 })
		-- espera a ver el suelo del destino y avisa al servidor
		task.spawn(function()
			local t0 = os.clock()
			while active == id and not covered do
				if destReady() then
					task.wait(READY_EXTRA)
					break
				end
				if os.clock() - t0 > READY_GIVEUP then
					break
				end
				task.wait(0.1)
			end
			if active == id and readyRemote and readyRemote:IsA("RemoteEvent") then
				readyRemote:FireServer(id)
			end
		end)
		task.delay(FAILSAFE, function()
			if active == id then
				hide()
			end
		end)
	end

	local function cover_(id: number)
		if active ~= id then
			return
		end
		covered = true
		coveredAt = os.clock()
		local r = rootPart()
		startPos = if r then r.Position else nil
		pill.Visible = false
		tween(cover, FADE_TO_BLACK, { BackgroundTransparency = 0 })
		tween(label, FADE_TO_BLACK, { TextTransparency = 0.1 })
	end

	-- el servidor ya te movió: se espera a que haya suelo bajo los pies para destapar
	local function release(id: number)
		local releasedAt = os.clock()
		while active == id do
			local waited = os.clock() - releasedAt
			local r = rootPart()
			local moved = r ~= nil and (startPos == nil or (r.Position - startPos).Magnitude > MIN_JUMP)
			if not covered or waited >= MAX_HOLD or (waited >= MIN_HOLD and moved and floorUnderfoot()) then
				break
			end
			task.wait(0.1)
		end
		if active == id then
			hide()
		end
	end

	player:GetAttributeChangedSignal("DungeonTransit"):Connect(function()
		local v = player:GetAttribute("DungeonTransit")
		local current = active
		if typeof(v) == "number" then
			prep(v)
		elseif current ~= nil then
			task.spawn(release, current)
		end
	end)

	player:GetAttributeChangedSignal("DungeonCover"):Connect(function()
		local v = player:GetAttribute("DungeonCover")
		if typeof(v) == "number" then
			cover_(v)
		end
	end)
end)
