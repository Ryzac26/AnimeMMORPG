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
		play({
			Ambient = Color3.fromRGB(120, 96, 78),
			OutdoorAmbient = Color3.fromRGB(150, 124, 100),
			FogColor = Color3.fromRGB(80, 60, 50),
			FogStart = 150,
			FogEnd = 900,
			Brightness = 2.4,
			ClockTime = 17.6,
		})
	elseif saved then
		play(saved)
		saved = nil
	end
end

player:GetAttributeChangedSignal("InHouse"):Connect(apply)
apply()
