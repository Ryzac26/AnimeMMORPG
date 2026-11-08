--!strict
--[[
    LevelLabelService (ModuleScript) -> ServerScriptService.Services.LevelLabelService
    Pasa a la escala 1-3000 los rangos de nivel que el mapa YA CONSTRUIDO tiene escritos: carteles "Franja 1 - Nvl 1-25",
    hologramas "Niveles 26-50" y los atributos MinLevel/MaxLevel de cada franja. Así no hace falta volver a generar el mapa.
    Es idempotente: solo toca rangos cuyo máximo es <= 100 (escala vieja). Si el mapa se regenera con el Bootstrapper nuevo, no hace nada.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GB = require(ReplicatedStorage.Modules.GameBalance)

local LevelLabelService = {}

local PATTERNS = { "(Nvl )(%d+)%-(%d+)", "(Niveles )(%d+)%-(%d+)" }

local function convert(text: string): string
	for _, pat in ipairs(PATTERNS) do
		text = string.gsub(text, pat, function(prefix: string, a: string, b: string)
			local lo, hi = tonumber(a) :: number, tonumber(b) :: number
			if hi > GB.OLD_MAX_LEVEL then
				return nil -- ya está en la escala nueva
			end
			return string.format("%s%d-%d", prefix, GB.FromOldMin(lo), GB.FromOld(hi))
		end)
	end
	return text
end

local function fix(inst: Instance)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		local t = convert(inst.Text)
		if t ~= inst.Text then
			inst.Text = t
		end
	end
	local lo, hi = inst:GetAttribute("MinLevel"), inst:GetAttribute("MaxLevel")
	if typeof(lo) == "number" and typeof(hi) == "number" and inst:GetAttribute("Strip") ~= nil and hi <= GB.OLD_MAX_LEVEL then
		inst:SetAttribute("MinLevel", GB.FromOldMin(lo))
		inst:SetAttribute("MaxLevel", GB.FromOld(hi))
	end
end

local function scan()
	for _, d in ipairs(workspace:GetDescendants()) do
		fix(d)
	end
end

task.spawn(function()
	scan()
	for _, delay in ipairs({ 5, 20, 60 }) do -- el mapa se genera/streamea un poco después de arrancar
		task.wait(delay)
		scan()
	end
end)

return LevelLabelService
