--!strict
--[[
    DungeonAmbientClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > DungeonAmbientClient
    Mientras estás dentro de una cueva (DungeonService pone el atributo de jugador "InDungeon" = número de franja) la luz cambia a CUEVA:
    de noche, ambiente muy oscuro con un tinte según la franja, niebla cercana y sin reflejos del cielo. Las antorchas, los braseros y los
    cristales de la cueva son lo que ilumina. Al salir vuelve suavemente a la luz que tenías al entrar.
    Se aplica cada fotograma (después de BiomeAmbientClient / HouseAmbientClient) para que ninguno le gane a la cueva.
    No tiene pantalla (no es una ScreenGui), no va en UIReloadClient.
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
