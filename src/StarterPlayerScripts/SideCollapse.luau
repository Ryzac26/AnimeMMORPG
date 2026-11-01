--!strict
--[[
    SideCollapse (ModuleScript) -> StarterPlayer > StarterPlayerScripts > SideCollapse
    Esconde un panel del HUD hacia el borde de la pantalla y deja una FLECHA para volver a sacarlo.
      SideCollapse.Attach(gui, panel, "Left" | "Right", "Clave", ancho)
    El estado (escondido o no) se recuerda mientras dura la sesión, aunque la interfaz se reconstruya.
]]
local TweenService = game:GetService("TweenService")

local SideCollapse = {}
local state: { [string]: boolean } = {}
local TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function SideCollapse.Attach(gui: ScreenGui, panel: Frame, side: string, key: string, width: number)
	local right = side == "Right"
	local open = panel.Position
	local m = if right then -open.X.Offset else open.X.Offset -- margen al borde
	local closed = UDim2.new(open.X.Scale, open.X.Offset + (if right then width + m else -(width + m)), open.Y.Scale, open.Y.Offset)

	local arrow = Instance.new("TextButton")
	arrow.Name = "Arrow_" .. key
	arrow.AnchorPoint = Vector2.new(if right then 1 else 0, panel.AnchorPoint.Y)
	arrow.Size = UDim2.fromOffset(22, 44)
	arrow.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	arrow.BackgroundTransparency = 0.2
	arrow.TextColor3 = Color3.fromRGB(230, 230, 240)
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 14
	arrow.ZIndex = 30
	arrow.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = arrow

	local function arrowPos(isOpen: boolean): UDim2
		local x = if right then (if isOpen then open.X.Offset - width - 2 else 0) else (if isOpen then open.X.Offset + width + 2 else 0)
		return UDim2.new(if right then 1 else 0, x, open.Y.Scale, open.Y.Offset)
	end
	local function glyph(isOpen: boolean): string
		-- abierto: la flecha apunta hacia donde se esconde; cerrado: hacia donde sale
		if right then
			return if isOpen then "▶" else "◀"
		end
		return if isOpen then "◀" else "▶"
	end
	local function apply(isOpen: boolean, animate: boolean)
		arrow.Text = glyph(isOpen)
		local goal = if isOpen then open else closed
		if animate then
			TweenService:Create(panel, TWEEN, { Position = goal }):Play()
			TweenService:Create(arrow, TWEEN, { Position = arrowPos(isOpen) }):Play()
		else
			panel.Position = goal
			arrow.Position = arrowPos(isOpen)
		end
	end

	local isOpen = state[key] ~= true
	apply(isOpen, false)
	arrow.Activated:Connect(function()
		isOpen = not isOpen
		state[key] = not isOpen
		apply(isOpen, true)
	end)
end

return SideCollapse
