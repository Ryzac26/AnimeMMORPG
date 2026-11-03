--!strict
--[[
    RarityPicker (ModuleScript) -> StarterPlayer > StarterPlayerScripts > RarityPicker
    Selector de RAREZAS (Común / Raro / Épico / Legendario / Mítico) + interruptor "Mejoradas". Lo usan el Mercader (vender)
    y el Alquimista (desmontar) para actuar sobre muchas piezas a la vez.
      local pick = RarityPicker.new(parentFrame, position, onChange)
      pick:List()          -> { "Comun", "Epico", ... } rarezas marcadas
      pick:IncludePlus()   -> true si "Mejoradas: SÍ"
      pick:Dangerous()     -> true si hay Épico o mejor marcado, o se incluyen mejoradas (pide confirmar)
      pick:Matches(item, plus) -> ¿esta pieza entra en la selección?
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemCatalog"))
local UITheme = require(script.Parent:WaitForChild("UITheme"))

local RarityPicker = {}
RarityPicker.__index = RarityPicker

local ORDER = { "Comun", "Raro", "Epico", "Legendario", "Mitico" }
local LABEL: { [string]: string } = { Comun = "Común", Raro = "Raro", Epico = "Épico", Legendario = "Legend.", Mitico = "Mítico" }

export type Picker = typeof(setmetatable({} :: { Set: { [string]: boolean }, Plus: boolean, Chips: { [string]: TextButton }, PlusButton: TextButton, OnChange: () -> (), Holder: Frame }, RarityPicker))

function RarityPicker.new(parent: Instance, pos: UDim2, onChange: () -> ()): Picker
	local self = setmetatable({ Set = { Comun = true } :: { [string]: boolean }, Plus = false, Chips = {} :: { [string]: TextButton }, OnChange = onChange, Holder = nil :: any }, RarityPicker)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = pos
	holder.Size = UDim2.fromOffset(318, 64)
	holder.Parent = parent
	self.Holder = holder
	UITheme.Text(holder, "Rarezas (toca para marcar):", 11, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(0, 0), UDim2.fromOffset(318, 14))
	for i, r in ipairs(ORDER) do
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset((i - 1) * 64, 16)
		b.Size = UDim2.fromOffset(60, 26)
		b.Font = UITheme.Font
		b.TextSize = 11
		b.Text = LABEL[r]
		b.ZIndex = 5
		b.Parent = holder
		Instance.new("UICorner", b)
		self.Chips[r] = b
		b.Activated:Connect(function()
			self.Set[r] = not self.Set[r]
			self:_paint()
			self.OnChange()
		end)
	end
	local plus = Instance.new("TextButton")
	plus.Position = UDim2.fromOffset(0, 46)
	plus.Size = UDim2.fromOffset(318, 18)
	plus.Font = UITheme.Font
	plus.TextSize = 11
	plus.ZIndex = 5
	plus.Parent = holder
	Instance.new("UICorner", plus)
	self.PlusButton = plus
	plus.Activated:Connect(function()
		self.Plus = not self.Plus
		self:_paint()
		self.OnChange()
	end)
	self:_paint()
	return self
end

function RarityPicker._paint(self: Picker)
	for r, b in pairs(self.Chips) do
		local col = ItemCatalog.RarityColor[r] or Color3.new(1, 1, 1)
		local on = self.Set[r] == true
		b.BackgroundColor3 = if on then col:Lerp(Color3.new(0, 0, 0), 0.35) else Color3.fromRGB(34, 34, 46)
		b.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(130, 130, 145)
		b.Text = (if on then "✔ " else "") .. LABEL[r]
	end
	self.PlusButton.Text = if self.Plus then "Piezas mejoradas (+): SÍ se incluyen" else "Piezas mejoradas (+): NO se incluyen"
	self.PlusButton.BackgroundColor3 = if self.Plus then Color3.fromRGB(150, 70, 50) else Color3.fromRGB(34, 34, 46)
	self.PlusButton.TextColor3 = if self.Plus then Color3.new(1, 1, 1) else Color3.fromRGB(150, 150, 165)
end

function RarityPicker.List(self: Picker): { string }
	local out: { string } = {}
	for _, r in ipairs(ORDER) do
		if self.Set[r] then
			table.insert(out, r)
		end
	end
	return out
end

function RarityPicker.IncludePlus(self: Picker): boolean
	return self.Plus
end

function RarityPicker.Dangerous(self: Picker): boolean
	return self.Plus or self.Set.Epico == true or self.Set.Legendario == true or self.Set.Mitico == true
end

function RarityPicker.Matches(self: Picker, item: any, plus: number): boolean
	return item ~= nil and self.Set[item.Rarity] == true and (self.Plus or plus == 0)
end

return RarityPicker
