--!strict
--[[
    PatchNotes (ModuleScript) -> ReplicatedStorage.Modules.PatchNotes
    Cada VERSIÓN es un ModuleScript HIJO de este script (ej. v6_40, v6_38). Así el archivo nunca crece: para una versión nueva
    solo creas un hijo nuevo (duplica uno existente, cambia el nombre y los textos). No hace falta tocar este script.
    Devuelve la lista ordenada de la más nueva a la más vieja según el campo Version ("6.41" > "6.40" > "6.9").
    Los jugadores no pueden editar nada de esto: vive en Studio.
    Cada hijo devuelve: { Version, Date, Title, Sections = { { Header, Items = { "..." } } } }
]]
export type Section = { Header: string, Items: { string } }
export type Entry = { Version: string, Date: string, Title: string, Sections: { Section } }

local function parts(v: string): { number }
	local out = {}
	for n in string.gmatch(v, "%d+") do
		table.insert(out, tonumber(n) or 0)
	end
	return out
end

local function newer(a: Entry, b: Entry): boolean
	local pa, pb = parts(a.Version), parts(b.Version)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end

local Notes: { Entry } = {}
for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") then
		local ok, entry = pcall(require, child)
		if ok and typeof(entry) == "table" and entry.Version then
			table.insert(Notes, entry :: Entry)
		else
			warn("[PatchNotes] versión inválida: " .. child.Name .. " -> " .. tostring(entry))
		end
	end
end
table.sort(Notes, newer)

return Notes
