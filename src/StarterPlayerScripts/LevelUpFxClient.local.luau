--!strict
--[[
    LevelUpFxClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > LevelUpFxClient
    PILAR DE LUZ al subir de nivel: columna luminosa con el color de la facción, anillos que suben, chispas
    y un cartel "¡NIVEL N!". Lo ven todos los jugadores cercanos (hasta 160 studs).
    No necesita servidor: reacciona al atributo "Level" que ya publica LevelService en cada jugador.
    No tiene ScreenGui, así que no va en la lista RELOAD.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))

local VIEW_RANGE = 160
local DURATION = 2.2

local folder = Workspace:FindFirstChild("LevelUpFx") or Instance.new("Folder")
folder.Name = "LevelUpFx"
folder.Parent = Workspace

local function colorOf(pl: Player): Color3
	local ok, c = pcall(function()
		return UITheme.Accent(UITheme.For(pl:GetAttribute("Faction")))
	end)
	return if ok and typeof(c) == "Color3" then c else Color3.fromRGB(255, 220, 120)
end

local function neon(size: Vector3, color: Color3, transparency: number): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.Parent = folder
	return p
end

local function play(pl: Player, level: number)
	local char = pl.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local cam = Workspace.CurrentCamera
	if pl ~= localPlayer and cam and (cam.CFrame.Position - root.Position).Magnitude > VIEW_RANGE then
		return
	end
	local color = colorOf(pl)
	local white = color:Lerp(Color3.new(1, 1, 1), 0.6)
	local H = 70
	local parts: { Part } = {}

	-- columna (el cilindro de Roblox tiene su eje en X: se gira para ponerlo vertical)
	local pillar = neon(Vector3.new(H, 3.2, 3.2), white, 0.15)
	pillar.Shape = Enum.PartType.Cylinder
	table.insert(parts, pillar)
	local glow = neon(Vector3.new(H, 6, 6), color, 0.65)
	glow.Shape = Enum.PartType.Cylinder
	table.insert(parts, glow)

	local rings: { Part } = {}
	for i = 1, 3 do
		local r = neon(Vector3.new(0.4, 6, 6), color, 0.2)
		r.Shape = Enum.PartType.Cylinder
		table.insert(rings, r)
		table.insert(parts, r)
		TweenService:Create(r, TweenInfo.new(DURATION * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, (i - 1) * 0.18), { Size = Vector3.new(0.4, 16, 16), Transparency = 1 }):Play()
	end
	TweenService:Create(pillar, TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(H, 1, 1) }):Play()
	TweenService:Create(glow, TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(H, 2, 2) }):Play()

	-- chispas
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = folder
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(white, color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.9, 1.6)
	pe.Speed = NumberRange.new(10, 22)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 0
	pe.Acceleration = Vector3.new(0, 4, 0)
	pe.Parent = anchor
	pe:Emit(60)

	-- cartel
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 50)
	bb.StudsOffset = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.Text = string.format("¡NIVEL %d!", level)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeColor3 = color
	t.TextStrokeTransparency = 0
	t.Parent = bb
	TweenService:Create(t, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, DURATION - 0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local age = os.clock() - t0
		if age >= DURATION or not root.Parent then
			conn:Disconnect()
			for _, p in ipairs(parts) do
				p:Destroy()
			end
			anchor:Destroy()
			return
		end
		local base = root.Position - Vector3.new(0, 3, 0)
		local up = CFrame.Angles(0, 0, math.pi / 2)
		local spin = CFrame.Angles(0, age * 2, 0)
		pillar.CFrame = CFrame.new(base + Vector3.new(0, H / 2, 0)) * spin * up
		glow.CFrame = pillar.CFrame
		for i, r in ipairs(rings) do
			local rise = math.clamp((age - (i - 1) * 0.18) / (DURATION * 0.8), 0, 1)
			r.CFrame = CFrame.new(base + Vector3.new(0, 0.3 + rise * 14, 0)) * up
		end
		anchor.CFrame = CFrame.new(base + Vector3.new(0, 3, 0))
	end)
end

local last: { [Player]: number } = {}

local function watch(pl: Player)
	local v = pl:GetAttribute("Level")
	if typeof(v) == "number" then
		last[pl] = v
	end
	pl:GetAttributeChangedSignal("Level"):Connect(function()
		local n = pl:GetAttribute("Level")
		if typeof(n) ~= "number" then
			return
		end
		local prev = last[pl]
		last[pl] = n
		if prev and n > prev then -- la primera carga (nil -> nivel) y las bajadas no cuentan
			play(pl, n)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	last[pl] = nil
end)
