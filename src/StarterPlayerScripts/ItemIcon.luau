--!strict
--[[
    ItemIcon (ModuleScript) -> StarterPlayer > StarterPlayerScripts > ItemIcon
    Icono de cada objeto SIN imágenes: un símbolo según la ranura (y el tipo de arma / familia de mascota) sobre un fondo del color de su rol,
    más una etiqueta con el peso de la armadura. Así se distinguen de un vistazo:
      PESADO (Tanque, Guerrero)  ·  MEDIO (Asesino, Tirador)  ·  LIGERO/TELA (Mago, Curador)
    Más adelante se puede cambiar por imágenes reales: basta con poner Icon = "rbxassetid://..." en el objeto (se usa si existe).
    ItemIcon.Build(parent, item, size, light?) -> Frame (centrado en el padre, no recibe clics)
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GearCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GearCatalog"))
local GearIcons = require(ReplicatedStorage.Modules.GearIcons)
local ItemIcon = {}

local WEIGHT = { Tanque = "H", Guerrero = "H", Asesino = "M", Tirador = "M", Mago = "L", Curador = "L" } :: { [string]: string }
local WEIGHT_TAG = { H = "PES", M = "MED", L = "LIG" } :: { [string]: string }
local ROLE_TAG = { Tanque = "TNQ", Guerrero = "GUE", Asesino = "ASE", Tirador = "TIR", Mago = "MAG", Curador = "CUR" } :: { [string]: string }

ItemIcon.RoleColor = {
	Tanque = Color3.fromRGB(90, 125, 175),
	Guerrero = Color3.fromRGB(190, 70, 60),
	Asesino = Color3.fromRGB(120, 80, 170),
	Tirador = Color3.fromRGB(80, 150, 90),
	Mago = Color3.fromRGB(70, 90, 200),
	Curador = Color3.fromRGB(215, 175, 70),
} :: { [string]: Color3 }

-- símbolos por ranura: H = pesado, M = medio, L = ligero
local SLOT_GLYPH = {
	Casco = { H = "🪖", M = "🧢", L = "🎩" },
	Armadura = { H = "🛡️", M = "🥋", L = "👘" },
	Zapatos = { H = "🥾", M = "👟", L = "👡" },
	Cinturon = { H = "⛓️", M = "🎗️", L = "🎀" },
	Brazalete = { H = "🔗", M = "⌚", L = "📿" },
	Capa = { H = "🧥", M = "🧥", L = "🧣" },
} :: { [string]: { [string]: string } }

local SHIELD_GLYPH = { Tanque = "🛡️", Guerrero = "⚔️", Asesino = "🗡️", Tirador = "🏹", Mago = "🔮", Curador = "📖" } :: { [string]: string }
local STYLE_GLYPH = { Sword = "🗡️", Dagger = "🔪", Bow = "🏹", Staff = "🪄", Gun = "🔫", Axe = "🪓", Fist = "👊" } :: { [string]: string }
local FIXED_GLYPH = {
	Collar = "📿", Pendientes = "🧿", Anillo = "💍", Anillo2 = "💍", Alas = "🪽", Montura = "🐎", Traje = "👕",
	Accesorio1 = "🏵️", Accesorio2 = "🐾", Accesorio3 = "🐾",
} :: { [string]: string }

function ItemIcon.Glyph(item: any): string
	local slot: string? = item.Slot
	local role: string? = item.Role
	local w = if role then WEIGHT[role] else nil
	if slot == "Arma" then
		return STYLE_GLYPH[item.Style or ""] or "⚔️"
	elseif slot == "Escudo" then
		return (role and SHIELD_GLYPH[role]) or "🛡️"
	elseif slot and SLOT_GLYPH[slot] then
		return SLOT_GLYPH[slot][w or "M"]
	elseif slot and FIXED_GLYPH[slot] then
		return FIXED_GLYPH[slot]
	elseif item.Pet then
		return "🐾"
	elseif item.Elixir then
		return "⚗️"
	elseif item.Use then
		return if item.Use.EnergyPct then "🧪" else "❤️"
	end
	return "💠" -- materiales y varios
end

function ItemIcon.Tint(item: any, rarityColor: Color3): Color3
	local th = if typeof(item.Theme) == "string" then GearCatalog.ThemeById[item.Theme] else nil
	if th then
		return Color3.fromHex(th.Base)
	end
	local role: string? = item.Role
	if role and ItemIcon.RoleColor[role] then
		return ItemIcon.RoleColor[role]
	end
	return rarityColor
end

-- Marco de rareza (imagen marcos/<rareza>) encima del icono, si está subida
local function addFrame(f: Frame, item: any)
	local r: string? = item.Rarity
	local id = if r then GearIcons["marcos/" .. string.lower(r)] else nil
	if id then
		local fr = Instance.new("ImageLabel")
		fr.Name = "MarcoRareza"
		fr.Size = UDim2.fromScale(1, 1)
		fr.BackgroundTransparency = 1
		fr.Image = id
		fr.ZIndex = 12
		fr.Parent = f
	end
end

function ItemIcon.Build(parent: Instance, item: any, size: number, rarityColor: Color3): Frame
	local f = Instance.new("Frame")
	f.Name = "ItemIcon"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 3)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = ItemIcon.Tint(item, rarityColor):Lerp(Color3.new(0, 0, 0), 0.35)
	f.BorderSizePixel = 0
	f.ZIndex = 7
	f.Active = false
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	local img: string? = item.Icon
	if typeof(img) == "string" and img ~= "" then
		local im = Instance.new("ImageLabel")
		im.Size = UDim2.fromScale(1, 1)
		im.BackgroundTransparency = 1
		im.Image = img
		im.ZIndex = 8
		im.Parent = f
		addFrame(f, item)
		return f
	end
	local g = Instance.new("TextLabel")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.Text = ItemIcon.Glyph(item)
	g.TextSize = math.floor(size * 0.62)
	g.Font = Enum.Font.GothamBold
	g.TextColor3 = Color3.new(1, 1, 1)
	g.ZIndex = 8
	g.Parent = f
	addFrame(f, item)
	local role: string? = item.Role
	if role and ROLE_TAG[role] then
		local tag = Instance.new("TextLabel")
		tag.AnchorPoint = Vector2.new(0, 1)
		tag.Position = UDim2.fromScale(0, 1)
		tag.Size = UDim2.fromOffset(math.floor(size * 0.62), math.max(9, math.floor(size * 0.26)))
		tag.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		tag.BackgroundTransparency = 0.25
		tag.BorderSizePixel = 0
		tag.Text = ROLE_TAG[role]
		tag.Font = Enum.Font.GothamBold
		tag.TextSize = math.max(7, math.floor(size * 0.2))
		tag.TextColor3 = Color3.new(1, 1, 1)
		tag.ZIndex = 9
		tag.Parent = f
		Instance.new("UICorner", tag).CornerRadius = UDim.new(0, 3)
		local wt = WEIGHT[role]
		if wt and (item.Slot == "Casco" or item.Slot == "Armadura" or item.Slot == "Zapatos" or item.Slot == "Cinturon" or item.Slot == "Brazalete") then
			local pill = tag:Clone()
			pill.AnchorPoint = Vector2.new(1, 0)
			pill.Position = UDim2.new(1, 0, 0, 0)
			pill.Size = UDim2.fromOffset(math.floor(size * 0.5), math.max(9, math.floor(size * 0.26)))
			pill.Text = WEIGHT_TAG[wt]
			pill.Parent = f
		end
	end
	return f
end

return ItemIcon
