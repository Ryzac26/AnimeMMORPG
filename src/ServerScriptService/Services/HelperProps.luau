--!strict
--[[
    HelperProps (ModuleScript) -> ServerScriptService.Services.HelperProps
    ARMAS DE LOS AYUDANTES: construye, con las MISMAS funciones que los personajes (AttackAnimator.BuildWeapon / BuildOffhand), el arma principal
    y la pieza secundaria de cada clase (escudo, segunda daga, carcaj, orbe, libro) y las deja como plantillas en ReplicatedStorage.HelperProps/<clave>.
    HelperFollowClient/HelperModel las clonan sobre el cuerpo del ayudante (copia del dueño) escaladas a su tamaño.
      - Arma principal: la pieza "Arma" que lleva equipada el ayudante; si no tiene, el arma de su rol y facción (GearCatalog.WeaponStyle) según su nivel y rareza.
      - Pieza secundaria: la de su rol (Tanque escudo torre · Guerrero escudo redondo · Asesino segunda daga · Tirador carcaj a la espalda · Mago orbe · Curador libro).
    Cada plantilla es un Folder con dos Models: "R15" y "R6" (piezas sueltas "Right Arm"/"RightHand"... + las piezas soldadas a ellas).
    Los modelos 3D cargan despacio la primera vez: mientras tanto sale la versión de bloques; al terminar se reconstruye la plantilla y sube su atributo Rev
    (el cliente lo mira y rehace al ayudante).
    API:  HelperProps.KeysFor(faction, role, rarity, level, armaItem?) -> (claveArma?, clavePieza?)   (crea las plantillas si hacen falta)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GearCatalog = require(ReplicatedStorage.Modules.GearCatalog)
local ItemCatalog = require(ReplicatedStorage.Modules.ItemCatalog)
local AttackAnimator = require(script.Parent.AttackAnimator)

local HelperProps = {}

local root = ReplicatedStorage:FindFirstChild("HelperProps")
if not root then
	root = Instance.new("Folder")
	root.Name = "HelperProps"
	root.Parent = ReplicatedStorage
end
local ROOT: Instance = root :: Instance

type Spec = { Kind: string, Style: string?, Item: any, Glow: Color3 }
local specs: { [string]: Spec } = {}
local refilling: { [string]: boolean } = {}

local DUMMIES = {
	R15 = { Right = "RightHand", Left = "LeftHand", Torso = "UpperTorso" },
	R6 = { Right = "Right Arm", Left = "Left Arm", Torso = "Torso" },
}

local function dummy(parent: Instance, name: string)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p:SetAttribute("Dummy", true)
	p.Parent = parent
end

local function variant(r15: boolean, spec: Spec, retry: () -> ()): Model
	local m = Instance.new("Model")
	m.Name = if r15 then "R15" else "R6"
	local names = if r15 then DUMMIES.R15 else DUMMIES.R6
	dummy(m, names.Right)
	dummy(m, names.Left)
	dummy(m, names.Torso)
	local f = Instance.new("Folder")
	f.Name = "Pieces"
	f.Parent = m
	if spec.Kind == "W" then
		AttackAnimator.BuildWeapon(f, m, spec.Style :: string, spec.Glow, spec.Item, retry)
	else
		AttackAnimator.BuildOffhand(f, m, spec.Item, spec.Glow, retry)
	end
	return m
end

local fill: (string) -> ()

-- Cuando un modelo 3D termina de cargar se reconstruye la plantilla (una sola vez aunque lleguen varios avisos)
local function scheduleRefill(key: string)
	if refilling[key] then
		return
	end
	refilling[key] = true
	task.defer(function()
		refilling[key] = nil
		fill(key)
	end)
end

fill = function(key: string)
	local spec = specs[key]
	local tpl = ROOT:FindFirstChild(key)
	if not spec or not tpl then
		return
	end
	for _, c in ipairs(tpl:GetChildren()) do
		c:Destroy()
	end
	local function retry()
		scheduleRefill(key)
	end
	for _, r15 in ipairs({ true, false }) do
		local ok, m = pcall(variant, r15, spec, retry)
		if ok then
			(m :: Model).Parent = tpl
		else
			warn("[HelperProps] " .. key .. ": " .. tostring(m))
		end
	end
	local rev = tpl:GetAttribute("Rev")
	tpl:SetAttribute("Rev", (if typeof(rev) == "number" then rev else 0) + 1)
end

local function ensure(key: string, spec: Spec)
	if specs[key] then
		return
	end
	specs[key] = spec
	local tpl = Instance.new("Folder")
	tpl.Name = key
	tpl:SetAttribute("Rev", 0)
	tpl.Parent = ROOT
	fill(key)
end

-- Escalón de aspecto (1..11) según el nivel del ayudante
local function tierOf(level: number): number
	return math.clamp(GearCatalog.TierOfLevel(level), 1, #GearCatalog.TierLevels)
end

local function rarityOk(r: string): string
	return if table.find(GearCatalog.Rarities, r) then r else "Comun"
end

function HelperProps.KeysFor(faction: string, role: string, rarity: string, level: number, armaItem: any?): (string?, string?)
	rarity = rarityOk(rarity)
	local tier = tierOf(level)
	local mainKey: string? = nil
	local offKey: string? = nil

	-- arma principal: la pieza equipada o, si no hay, la del rol/facción
	local style: string? = nil
	local weapon: any = nil
	if armaItem and typeof(armaItem.Style) == "string" then
		style = armaItem.Style
		weapon = { Tier = if typeof(armaItem.Tier) == "number" then armaItem.Tier else tier, Rarity = if typeof(armaItem.Rarity) == "string" then rarityOk(armaItem.Rarity) else rarity }
	else
		local byFaction = (GearCatalog.WeaponStyle :: any)[faction]
		style = if byFaction then byFaction[role] else nil
		weapon = { Tier = tier, Rarity = rarity }
	end
	if style then
		local wt = math.clamp(weapon.Tier, 1, #GearCatalog.TierLevels)
		local key = string.format("W_%s_%d_%s", style, wt, weapon.Rarity)
		ensure(key, { Kind = "W", Style = style, Item = { Tier = wt, Rarity = weapon.Rarity, Slot = "Arma", Style = style }, Glow = AttackAnimator.RarityColor({ Rarity = weapon.Rarity }) })
		mainKey = key
	end

	-- pieza secundaria del rol (como la ranura Escudo de los jugadores)
	if role == "Tanque" or role == "Guerrero" or role == "Asesino" or role == "Tirador" or role == "Mago" or role == "Curador" then
		local key = string.format("O_%s_%d_%s", role, tier, rarity)
		ensure(key, { Kind = "O", Item = { Tier = tier, Rarity = rarity, Slot = "Escudo", Role = role }, Glow = AttackAnimator.RarityColor({ Rarity = rarity }) })
		offKey = key
	end
	return mainKey, offKey
end

-- (para que ItemCatalog quede referenciado si cambia el color de rareza)
HelperProps.RarityColor = ItemCatalog.RarityColor

return HelperProps
