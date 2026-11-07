--!strict
--[[
    HouseAmbientClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > HouseAmbientClient
    Al entrar a una Casa VIP (HouseService pone el atributo de jugador "InHouse") cambia la luz suavemente: ambiente cálido, atardecer y
    poca niebla, como al cruzar una franja de bioma. Al salir restaura lo que había. No tiene pantalla (no va en RELOAD).
]]
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local TWEEN = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local sky = Lighting:FindFirstChildOfClass("Sky")
local savedStars: number? = nil
local saved: { [string]: any }? = nil
local tweens: { Tween } = {}

local function play(goal: { [string]: any })
	for _, t in ipairs(tweens) do
		t:Cancel()
	end
	table.clear(tweens)
	local tw = TweenService:Create(Lighting, TWEEN, goal)
	table.insert(tweens, tw)
	tw:Play()
end

local function apply()
	if player:GetAttribute("InHouse") == true then
		if not saved then
			saved = {
				Ambient = Lighting.Ambient,
				OutdoorAmbient = Lighting.OutdoorAmbient,
				FogColor = Lighting.FogColor,
				FogStart = Lighting.FogStart,
				FogEnd = Lighting.FogEnd,
				Brightness = Lighting.Brightness,
				ClockTime = Lighting.ClockTime,
			}
		end
		if sky and not savedStars then
			savedStars = sky.StarCount
		end
		if sky then
			sky.StarCount = 0
		end
		local night = player:GetAttribute("HouseNight") == true
		if sky then
			sky.StarCount = if night then (savedStars or 3000) else 0
		end
		if night then
			play({
				Ambient = Color3.fromRGB(34, 38, 64),
				OutdoorAmbient = Color3.fromRGB(46, 52, 90),
				FogColor = Color3.fromRGB(14, 16, 32),
				FogStart = 120,
				FogEnd = 700,
				Brightness = 0.35,
				ClockTime = 0,
			})
		else
			play({
				Ambient = Color3.fromRGB(96, 84, 78),
				OutdoorAmbient = Color3.fromRGB(120, 108, 98),
				FogColor = Color3.fromRGB(150, 130, 112),
				FogStart = 200,
				FogEnd = 1100,
				Brightness = 1.6,
				ClockTime = 14,
			})
		end
	elseif saved then
		if sky and savedStars then
			sky.StarCount = savedStars
			savedStars = nil
		end
		play(saved)
		saved = nil
	end
end

player:GetAttributeChangedSignal("InHouse"):Connect(apply)
player:GetAttributeChangedSignal("HouseNight"):Connect(apply)
apply()
