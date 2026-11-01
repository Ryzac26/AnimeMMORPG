--!strict
--[[
    BiomeAmbientClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BiomeAmbientClient
    Cambia luz, niebla, tinte y cielo según la franja PvE donde está el jugador.
    El servidor (BiomeStyler) pone el atributo de jugador "BiomeZone" ("Saiyan_2", ...; vacío fuera de las franjas).
    Los datos de cada zona y los IDs del cielo están en ReplicatedStorage > Modules > BiomeAssets.
    No es una pantalla (no hay ScreenGui), así que no necesita estar en UIReloadClient.
]]
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BiomeAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("BiomeAssets"))
local player = Players.LocalPlayer

local TWEEN = TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local original = {
	Ambient = Lighting.Ambient,
	OutdoorAmbient = Lighting.OutdoorAmbient,
	FogColor = Lighting.FogColor,
	FogStart = Lighting.FogStart,
	FogEnd = Lighting.FogEnd,
	Brightness = Lighting.Brightness,
	ClockTime = Lighting.ClockTime,
}
local originalSky: Sky? = Lighting:FindFirstChildOfClass("Sky")

local tint = Instance.new("ColorCorrectionEffect")
tint.Name = "BiomeTint"
tint.Parent = Lighting

local biomeSky: Sky? = nil
local currentTween: { Tween } = {}

local function clearTweens()
	for _, tw in ipairs(currentTween) do
		tw:Cancel()
	end
	table.clear(currentTween)
end

local function play(inst: Instance, goal: { [string]: any })
	local tw = TweenService:Create(inst, TWEEN, goal)
	table.insert(currentTween, tw)
	tw:Play()
end

local function useSky(faction: string, variant: string): boolean
	local faces = { ft = "SkyboxFt", bk = "SkyboxBk", lf = "SkyboxLf", rt = "SkyboxRt", up = "SkyboxUp", dn = "SkyboxDn" }
	local ids: { [string]: string } = {}
	for face, prop in pairs(faces) do
		local id = BiomeAssets.Get(string.format("%s_sky%s_%s", faction, variant, face))
		if not id then
			return false -- si falta una cara, no se usa el cielo propio
		end
		ids[prop] = id
	end
	if not biomeSky then
		biomeSky = Instance.new("Sky")
		biomeSky.Name = "BiomeSky"
	end
	local sky = biomeSky :: Sky
	for prop, id in pairs(ids) do
		(sky :: any)[prop] = id
	end
	if originalSky and originalSky.Parent then
		originalSky.Parent = nil
	end
	sky.Parent = Lighting
	return true
end

local function restoreSky()
	if biomeSky then
		biomeSky.Parent = nil
	end
	if originalSky and not originalSky.Parent then
		originalSky.Parent = Lighting
	end
end

local lastZone = ""
local function apply()
	local zone = player:GetAttribute("BiomeZone")
	local name = if typeof(zone) == "string" then zone else ""
	if name == lastZone then
		return
	end
	lastZone = name
	clearTweens()
	local z = BiomeAssets.Zones[name]
	if not z then
		restoreSky()
		play(Lighting, {
			Ambient = original.Ambient, OutdoorAmbient = original.OutdoorAmbient, FogColor = original.FogColor,
			FogStart = original.FogStart, FogEnd = original.FogEnd, Brightness = original.Brightness, ClockTime = original.ClockTime,
		})
		play(tint, { TintColor = Color3.new(1, 1, 1) })
		return
	end
	local faction = string.match(name, "^(%a+)_")
	if faction and not useSky(faction, z.Sky) then
		restoreSky()
	end
	play(Lighting, {
		Ambient = z.Ambient, OutdoorAmbient = z.Outdoor, FogColor = z.Fog, FogStart = z.FogStart,
		FogEnd = z.FogEnd, Brightness = z.Brightness, ClockTime = z.ClockTime,
	})
	play(tint, { TintColor = z.Tint })
end

player:GetAttributeChangedSignal("BiomeZone"):Connect(apply)
apply()
