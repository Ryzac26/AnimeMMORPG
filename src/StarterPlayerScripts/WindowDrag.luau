--!strict
--[[
    WindowDrag (ModuleScript) -> StarterPlayer > StarterPlayerScripts > WindowDrag
    Hace que una ventana se pueda MOVER arrastrando su barra de título (mouse o toque).
      WindowDrag.Attach(ventana, "Clave", alturaDeLaBarra, margenDerecho)
    La posición se recuerda mientras dura la sesión (por "Clave"), aunque la ventana se reconstruya.
    La ventana nunca sale entera de la pantalla.
]]
local UserInputService = game:GetService("UserInputService")

local WindowDrag = {}

local saved: { [string]: UDim2 } = {}
local MIN_VISIBLE = 80 -- píxeles que siempre quedan a la vista

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function clamp(win: Frame)
	local gui = win:FindFirstAncestorOfClass("ScreenGui")
	if not gui then
		return
	end
	local view = gui.AbsoluteSize
	local pos = win.AbsolutePosition - gui.AbsolutePosition
	local size = win.AbsoluteSize
	local cx = math.clamp(pos.X, MIN_VISIBLE - size.X, view.X - MIN_VISIBLE)
	local cy = math.clamp(pos.Y, 0, view.Y - 40)
	if cx ~= pos.X or cy ~= pos.Y then
		local p = win.Position
		win.Position = UDim2.new(p.X.Scale, p.X.Offset + (cx - pos.X), p.Y.Scale, p.Y.Offset + (cy - pos.Y))
	end
end

function WindowDrag.Attach(win: Frame, key: string, handleHeight: number, rightMargin: number?)
	local remembered = saved[key]
	if remembered then
		win.Position = remembered
	end

	local handle = Instance.new("TextButton")
	handle.Name = "DragHandle"
	handle.BackgroundTransparency = 1
	handle.Text = ""
	handle.AutoButtonColor = false
	handle.Size = UDim2.new(1, -(rightMargin or 44), 0, handleHeight)
	handle.ZIndex = 20
	handle.Parent = win

	local dragging = false
	local startPointer = Vector2.zero
	local startPos = win.Position

	handle.InputBegan:Connect(function(input)
		if isPointer(input) then
			dragging = true
			startPointer = Vector2.new(input.Position.X, input.Position.Y)
			startPos = win.Position
		end
	end)
	local changedConn = UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = Vector2.new(input.Position.X, input.Position.Y) - startPointer
			win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			clamp(win)
		end
	end)
	local endedConn = UserInputService.InputEnded:Connect(function(input)
		if dragging and isPointer(input) then
			dragging = false
			saved[key] = win.Position
		end
	end)
	-- si la ventana se destruye (el perfil se reconstruye al abrir), soltamos las conexiones
	win.Destroying:Connect(function()
		if dragging then
			saved[key] = win.Position
		end
		changedConn:Disconnect()
		endedConn:Disconnect()
	end)
end

return WindowDrag
