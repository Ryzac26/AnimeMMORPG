--!strict
--[[
    LightDimmer (ModuleScript) -> ServerScriptService.Services.LightDimmer
    BAJA EL BRILLO de todas las luces del mundo (antorchas, focos, farolas, hogueras, hitos...) en UN solo lugar.
    Cada PointLight / SpotLight / SurfaceLight que aparece en Workspace se multiplica UNA vez por BRIGHTNESS_SCALE (se marca con el atributo "LightDimmed",
    así nunca se atenúa dos veces). Las luces de los personajes (auras, etc.) no se tocan.
    AJUSTES: BRIGHTNESS_SCALE (0.55 = 45% menos de brillo; 1 = como antes) y RANGE_SCALE (alcance de la luz).
    Si algún lugar concreto sigue muy brillante, bájale a mano su Brightness o pon el atributo "LightDimmed" = true para que no se toque.
]]
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local BRIGHTNESS_SCALE = 0.55
local RANGE_SCALE = 0.9

local LightDimmer = {}

local function isCharacterLight(l: Instance): boolean
	local model = l:FindFirstAncestorOfClass("Model")
	while model do
		if Players:GetPlayerFromCharacter(model) then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function dim(l: Instance)
	if not (l:IsA("PointLight") or l:IsA("SpotLight") or l:IsA("SurfaceLight")) then
		return
	end
	if l:GetAttribute("LightDimmed") == true or isCharacterLight(l) then
		return
	end
	l:SetAttribute("LightDimmed", true)
	local light = l :: PointLight
	if light.Brightness > 0 then
		light.Brightness = light.Brightness * BRIGHTNESS_SCALE
	end
	light.Range = math.max(4, light.Range * RANGE_SCALE)
end

-- las luces que se creen después (los estilizadores construyen el mapa al arrancar) y las que ya existen
Workspace.DescendantAdded:Connect(dim)
for _, d in ipairs(Workspace:GetDescendants()) do
	dim(d)
end

function LightDimmer.Scale(): number
	return BRIGHTNESS_SCALE
end

return LightDimmer
