--!strict
--[[
    DungeonAmbientClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DungeonAmbientClient
    1) LUZ DE CUEVA. Mientras estás dentro de una cueva (DungeonService pone el atributo de jugador "InDungeon" = número de franja) la luz
       cambia a CUEVA: de noche, ambiente muy oscuro con un tinte según la franja, niebla cercana y sin reflejos del cielo. Las antorchas,
       los braseros y los cristales de la cueva son lo que ilumina. Al salir vuelve suavemente a la luz que tenías al entrar.
       Se aplica cada fotograma (después de BiomeAmbientClient / HouseAmbientClient) para que ninguno le gane a la cueva.
    2) TRANSICIÓN. Al entrar, cambiar de piso o salir, el servidor pone el atributo "DungeonTransit" (y el texto en "DungeonTransitText"):
       la pantalla se funde a negro, el servidor precarga el destino y te teletransporta, y aquí se destapa en cuanto hay SUELO bajo tus
       pies (en vez de ver el vacío mientras llega el mapa). Si algo falla, se destapa sola (tope de seguridad).
    Crea una ScreenGui propia "DungeonTransition" (se queda siempre en PlayerGui). No va en UIReloadClient.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
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
local DEBUG = true -- imprime cuánto tiempo estuvo tapada la pantalla (ponlo en false cuando ya no lo necesites)
local FADE_TO_BLACK = 0.25 -- segundos de fundido a negro
local FADE_FROM_BLACK = 0.5 -- segundos de fundido de vuelta
local MIN_HOLD = 0.15 -- segundos mínimos tapada después de que el servidor suelta
local MAX_HOLD = 6 -- tope de espera por el suelo después de que el servidor suelta (si no llega, se destapa igual)
local FAILSAFE = 25 -- si el servidor nunca suelta (error), se destapa igual
local MIN_JUMP = 60 -- los traslados mueven al jugador mucho más que esto: así no se destapa antes de llegar

task.spawn(function()
	local playerGui = player:WaitForChild("PlayerGui")
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
	local label = Instance.new("TextLabel")
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
	gui.Parent = playerGui

	local active: number? = nil -- identificador de la transición que está tapando la pantalla
	local startPos: Vector3? = nil
	local shownAt = 0

	local function rootPart(): BasePart?
		local ch = player.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		return if r and r:IsA("BasePart") then r else nil
	end

	-- ¿hay suelo (o terreno) debajo del jugador? Con StreamingEnabled aparece cuando llega el mapa del destino
	local function floorUnderfoot(): boolean
		local r = rootPart()
		local ch = player.Character
		if not r or not ch then
			return false
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ch }
		return Workspace:Raycast(r.Position, Vector3.new(0, -60, 0), params) ~= nil
	end

	local function hide()
		active = nil
		TweenService:Create(cover, TweenInfo.new(FADE_FROM_BLACK), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(FADE_FROM_BLACK * 0.7), { TextTransparency = 1 }):Play()
		if DEBUG then
			print(string.format("[DungeonTransition] pantalla tapada %.2f s", os.clock() - shownAt))
		end
		task.delay(FADE_FROM_BLACK + 0.05, function()
			if active == nil then
				gui.Enabled = false
			end
		end)
	end

	local function show(id: number)
		active = id
		shownAt = os.clock()
		local r = rootPart()
		startPos = if r then r.Position else nil
		local t = player:GetAttribute("DungeonTransitText")
		label.Text = if typeof(t) == "string" then t else "Cargando…"
		gui.Enabled = true
		TweenService:Create(cover, TweenInfo.new(FADE_TO_BLACK), { BackgroundTransparency = 0 }):Play()
		TweenService:Create(label, TweenInfo.new(FADE_TO_BLACK), { TextTransparency = 0.1 }):Play()
		task.delay(FAILSAFE, function()
			if active == id then
				hide()
			end
		end)
	end

	-- el servidor ya te movió: se espera a que haya suelo en el destino para destapar
	local function release(id: number)
		local releasedAt = os.clock()
		while active == id do
			local waited = os.clock() - releasedAt
			local r = rootPart()
			local moved = r ~= nil and (startPos == nil or (r.Position - startPos).Magnitude > MIN_JUMP)
			if waited >= MAX_HOLD or (waited >= MIN_HOLD and moved and floorUnderfoot()) then
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
			show(v)
		elseif current ~= nil then
			task.spawn(release, current)
		end
	end)
end)
