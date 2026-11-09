--!strict
--[[
    SkillsClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > SkillsClient
    Ventana "HABILIDADES" (botón del menú de abajo, MenuBus "Skills"): muestra SOLO los 7 poderes de la clase que llevas, con su icono,
    la tecla, qué hace, recarga, costo y alcance.
    Datos: PlayerClass (poderes 1-2) + AbilityCatalog (3-6). Iconos: AbilityIcons.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient (se reconstruye al cambiar de clase).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10) :: Folder
local PlayerClass: any = require(Modules:WaitForChild("PlayerClass", 10))
local AbilityCatalog: any = require(Modules:WaitForChild("AbilityCatalog", 10))
local AbilityIcons: any = require(Modules:WaitForChild("AbilityIcons", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local NpcKit = require(script.Parent:WaitForChild("NpcKit", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

local gui = Instance.new("ScreenGui")
gui.Name = "SkillsGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 14
gui.Parent = player:WaitForChild("PlayerGui", 10)

local win: Frame? = nil

local function num(v: any): string
	if typeof(v) ~= "number" then
		return "–"
	end
	return if v == math.floor(v) then tostring(v) else string.format("%.1f", v)
end

local TYPE_TEXT: { [string]: string } = {
	Damage = "Daño", AoE_Damage = "Daño en área", Healing = "Curación", Shield = "Escudo", CrowdControl = "Control",
}

type Row = { Slot: number, Name: string, Text: string, Cd: number?, Cost: number?, Range: number?, Radius: number?, Tag: string? }

local function rows(class: any): { Row }
	local out: { Row } = {}
	local p, s = class.PrimarySkill, class.SecondarySkill
	if p then
		table.insert(out, { Slot = 1, Name = p.Name, Text = p.Description, Cd = p.Cooldown, Cost = p.EnergyCost, Range = p.Range, Radius = p.AoERadius, Tag = TYPE_TEXT[p.SkillType] })
	end
	if s then
		table.insert(out, { Slot = 2, Name = s.Name, Text = s.Description, Cd = s.Cooldown, Cost = s.EnergyCost, Range = s.Range, Radius = s.AoERadius, Tag = TYPE_TEXT[s.SkillType] })
	end
	local set = AbilityCatalog[class.CharacterName]
	for i = 3, 6 do
		local a = set and set[i]
		if a then
			table.insert(out, { Slot = i, Name = a.Name, Text = a.Text, Cd = a.CdPve, Cost = a.Cost, Range = a.Range, Radius = a.Radius })
		end
	end
	table.insert(out, { Slot = 7, Name = "Primeros Auxilios", Text = "Te curas a ti mismo. Sirve para cualquier clase; recarga de 25 s.", Cd = 25, Tag = "Curación" })
	return out
end

local function build()
	if win then
		win:Destroy()
		win = nil
	end
	local theme = UITheme.For(player:GetAttribute("Faction"))
	local pal = NpcKit.Palette(theme)
	local class = PlayerClass.Get(player)
	local WW, HH = 760, 600
	local w = NpcKit.Window(gui, theme, UDim2.fromOffset(WW, HH), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "Habilidades",
		string.format("%s · %s", class.CharacterName, class.Role), "⚔️", function()
			gui.Enabled = false
		end)
	win = w
	WindowDrag.Attach(w, "Skills", 40, 50)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(14, NpcKit.TOP + 4)
	scroll.Size = UDim2.fromOffset(WW - 28, HH - NpcKit.TOP - 18)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = pal.Accent
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.Parent = w
	local innerW = WW - 28 - 10

	local rowH = 78
	local list = rows(class)
	for i, r in ipairs(list) do
		local card = NpcKit.Panel(scroll, theme, UDim2.fromOffset(innerW, rowH - 6), UDim2.fromOffset(0, (i - 1) * rowH), "card")
		-- icono
		local box = Instance.new("Frame")
		box.Position = UDim2.fromOffset(10, 8)
		box.Size = UDim2.fromOffset(58, 58)
		box.BackgroundColor3 = theme.Dark
		box.BorderSizePixel = 0
		box.Parent = card
		Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)
		local st = Instance.new("UIStroke")
		st.Color = theme.Primary
		st.Thickness = 2
		st.Parent = box
		local fallback = UITheme.Text(box, string.upper(string.sub(r.Name, 1, 2)), 18, theme.Primary, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
		fallback.TextStrokeTransparency = 0.3
		local art = AbilityIcons.Make(box, if r.Slot == 7 then "General/7" else class.CharacterName .. "/" .. r.Slot)
		if art then
			fallback.Visible = false
			Instance.new("UICorner", art).CornerRadius = UDim.new(0, 10)
		end
		-- tecla
		local key = UITheme.Text(card, "[" .. KeyBinds.Label("Poder" .. r.Slot) .. "]", 12, pal.Accent, UDim2.fromOffset(78, 8), UDim2.fromOffset(36, 18), Enum.TextXAlignment.Left)
		key.TextStrokeTransparency = 1
		local nm = UITheme.Text(card, r.Name, 15, pal.Text, UDim2.fromOffset(114, 8), UDim2.fromOffset(innerW - 130, 18), Enum.TextXAlignment.Left)
		nm.TextStrokeTransparency = 1
		nm.Font = Enum.Font.GothamBold
		local ds = UITheme.Text(card, r.Text, 12, pal.Muted, UDim2.fromOffset(78, 28), UDim2.fromOffset(innerW - 92, 28), Enum.TextXAlignment.Left)
		ds.TextWrapped = true
		ds.TextYAlignment = Enum.TextYAlignment.Top
		ds.TextStrokeTransparency = 1
		-- datos
		local bits: { string } = {}
		if r.Tag then
			table.insert(bits, r.Tag)
		end
		if r.Cd then
			table.insert(bits, "⏱ " .. num(r.Cd) .. " s")
		end
		if r.Cost and r.Cost > 0 then
			table.insert(bits, "💧 " .. num(r.Cost) .. " " .. string.lower(theme.Resource))
		end
		if r.Range and r.Range > 0 then
			table.insert(bits, "🎯 " .. num(r.Range) .. " studs")
		end
		if r.Radius and r.Radius > 0 then
			table.insert(bits, "⭕ radio " .. num(r.Radius))
		end
		local info = UITheme.Text(card, table.concat(bits, "   ·   "), 12, pal.Accent, UDim2.fromOffset(78, 54), UDim2.fromOffset(innerW - 92, 16), Enum.TextXAlignment.Left)
		info.TextStrokeTransparency = 1
	end
	scroll.CanvasSize = UDim2.fromOffset(0, #list * rowH + 6)
end

MenuBus.Event:Connect(function(name: string)
	if name == "Skills" then
		if gui.Enabled then
			gui.Enabled = false
		else
			build()
			gui.Enabled = true
		end
	end
end)
player:GetAttributeChangedSignal("Role"):Connect(function()
	if gui.Enabled then
		build()
	end
end)
print("[SkillsClient] listo")
