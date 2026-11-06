--!strict
--[[
    PortraitKit (ModuleScript) -> StarterPlayer > StarterPlayerScripts > PortraitKit   (junto a UITheme)
    Retrato vivo del personaje: un BUSTO 3D (cabeza y hombros) de tu personaje real, con el fondo y el marco de tu facción
    (brillo que respira + destello que cruza). Si en PortraitCatalog hay una imagen propia para el personaje, usa esa imagen.
      PortraitKit.Mount(parent, position, size, theme, characterName, character?) -> Frame
    El busto se actualiza solo cuando reapareces o cambia tu equipo visible.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Catalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PortraitCatalog"))

local player = Players.LocalPlayer
local PortraitKit = {}

-- imágenes opcionales (UIAssets); si no existe el módulo o no hay IDs, se dibuja por código
local UIAssets: { Get: (string) -> string? } = { Get = function(_: string): string? return nil end }
do
	local m = script.Parent:FindFirstChild("UIAssets")
	if m and m:IsA("ModuleScript") then
		local ok, mod = pcall(require, m)
		if ok and type(mod) == "table" and mod.Get then
			UIAssets = mod
		end
	end
end

local function bustCamera(vp: ViewportFrame, model: Model)
	local head = model:FindFirstChild("Head") :: BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not head or not root then
		return
	end
	local cam = vp.CurrentCamera
	if not cam then
		cam = Instance.new("Camera")
		vp.CurrentCamera = cam
		cam.Parent = vp
	end
	-- la distancia depende del tamaño real de la cabeza (personajes grandes como Jinbe o pequeños como Chopper)
	local headSize = math.max(head.Size.X, head.Size.Y, head.Size.Z)
	local focus = head.Position - Vector3.new(0, head.Size.Y * 0.12, 0)
	local front = root.CFrame.LookVector
	local from = focus + front * (headSize * 3.4) + Vector3.new(headSize * 0.25, headSize * 0.12, 0)
	-- la luz viaja hacia la cara (de frente), así no queda a contraluz
	vp.LightDirection = -front + Vector3.new(0, -0.35, 0)
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(from, focus)
end

function PortraitKit.Mount(parent: Instance, pos: UDim2, size: UDim2, theme: UITheme.Theme, characterName: string, character: Model?): Frame
	local imgId = UIAssets.Get(string.lower(UITheme.Key(theme)) .. "_portrait")
	local accent = UITheme.Accent(theme)
	local frame = Instance.new("Frame")
	frame.Name = "Retrato"
	frame.Position = pos
	frame.Size = size
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = parent
	local r = UITheme.Radius(theme)
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, math.max(r - 2, 0))
	local stroke: UIStroke? = nil
	if imgId then
		-- fondo exportado de la maqueta (marco, degradado y kanji ya dibujados)
		frame.BackgroundTransparency = 1
		local bgImg = Instance.new("ImageLabel")
		bgImg.Name = "Fondo"
		bgImg.BackgroundTransparency = 1
		bgImg.Size = UDim2.fromScale(1, 1)
		bgImg.Image = imgId
		bgImg.ZIndex = 1
		bgImg.Parent = frame
	else
		-- marco liso de acento (como en la maqueta), con brillo que respira
		stroke = Instance.new("UIStroke")
		local sk = stroke :: UIStroke
		sk.Color = accent
		sk.Thickness = 2
		sk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		sk.Parent = frame

		-- fondo: degradado vertical de la facción (claro abajo -> oscuro arriba) + luz inferior + kanji grande
		local grad = Instance.new("UIGradient")
		grad.Color = ColorSequence.new(theme.Dark:Lerp(Color3.new(0, 0, 0), 0.45), theme.Primary:Lerp(theme.Dark, 0.3))
		grad.Rotation = 90
		grad.Parent = frame
		local glow = Instance.new("Frame")
		glow.Name = "Luz"
		glow.AnchorPoint = Vector2.new(0.5, 1)
		glow.Position = UDim2.fromScale(0.5, 1.2)
		glow.Size = UDim2.fromScale(1.4, 0.8)
		glow.BackgroundColor3 = accent
		glow.BackgroundTransparency = 0.7
		glow.BorderSizePixel = 0
		glow.ZIndex = 1
		glow.Parent = frame
		Instance.new("UICorner", glow).CornerRadius = UDim.new(1, 0)
		local back = Instance.new("TextLabel")
		back.Name = "Kanji"
		back.BackgroundTransparency = 1
		back.AnchorPoint = Vector2.new(0.5, 0.5)
		back.Position = UDim2.fromScale(0.5, 0.5)
		back.Size = UDim2.fromScale(0.95, 0.95)
		back.Text = theme.Emblem
		back.TextScaled = true
		back.Font = Enum.Font.GothamBlack
		back.TextColor3 = accent
		back.TextTransparency = 0.35
		back.TextStrokeColor3 = theme.Primary
		back.TextStrokeTransparency = 0.7
		back.ZIndex = 2
		back.Parent = frame


	end

	local custom = Catalog[characterName]
	if custom and custom ~= "" then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.Image = custom
		img.ScaleType = Enum.ScaleType.Crop
		img.ZIndex = 3
		img.Parent = frame
	else
		local vp = Instance.new("ViewportFrame")
		vp.Size = UDim2.fromScale(1, 1)
		vp.BackgroundTransparency = 1
		vp.Ambient = Color3.fromRGB(235, 235, 240)
		vp.LightColor = Color3.new(1, 1, 1)
		vp.LightDirection = Vector3.new(-0.4, -0.6, -0.7)
		vp.ZIndex = 3
		vp.Parent = frame
		local clone: Model? = nil
		local function refresh()
			if clone then
				clone:Destroy()
				clone = nil
			end
			local char = character or player.Character
			if not char then
				return
			end
			char.Archivable = true
			local c = char:Clone()
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ForceField") or d:IsA("Highlight") or d:IsA("BillboardGui") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			local hrp = c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp then
				c:Destroy()
				return
			end
			c:PivotTo(CFrame.new(0, 0, 0))
			c.Parent = vp
			clone = c
			bustCamera(vp, c)
		end
		refresh()
		if not character then
			player.CharacterAdded:Connect(function()
				task.wait(1.2) -- espera a que se vistan los accesorios del personaje
				if frame.Parent then
					refresh()
				end
			end)
			-- el equipo visible (accesorios) puede llegar un momento después de aparecer
			task.delay(2.5, function()
				if frame.Parent then
					refresh()
				end
			end)
		end
	end

	-- brillo que respira en el borde + destello que cruza
	if stroke then
		TweenService:Create(stroke, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.55 }):Play()
	end
	local shine = Instance.new("Frame")
	shine.Size = UDim2.fromScale(0.25, 1.4)
	shine.Position = UDim2.fromScale(-0.4, -0.2)
	shine.Rotation = 20
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.88
	shine.BorderSizePixel = 0
	shine.ZIndex = 5
	shine.Parent = frame
	task.spawn(function()
		while frame.Parent do
			shine.Position = UDim2.fromScale(-0.4, -0.2)
			TweenService:Create(shine, TweenInfo.new(1.6, Enum.EasingStyle.Quad), { Position = UDim2.fromScale(1.2, -0.2) }):Play()
			task.wait(5)
		end
	end)
	-- marco de perfil ganado con las misiones del Pabellón (atributo "ProfileFrame" del jugador local)
	if not character then
		local MissionCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MissionCatalog"))
		local lp = game:GetService("Players").LocalPlayer
		local function applyFrame()
			local old = frame:FindFirstChild("MarcoPerfil")
			if old then
				old:Destroy()
			end
			local def = MissionCatalog.FrameById[tostring(lp:GetAttribute("ProfileFrame") or "")]
			if def then
				local st = Instance.new("UIStroke")
				st.Name = "MarcoPerfil"
				st.Color = def.Color
				st.Thickness = 3.5
				st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				st.Parent = frame
			end
		end
		applyFrame()
		lp:GetAttributeChangedSignal("ProfileFrame"):Connect(applyFrame)
	end
	return frame
end

return PortraitKit
