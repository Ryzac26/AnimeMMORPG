--!strict
--[[
    HelperPortrait (ModuleScript) -> StarterPlayer > StarterPlayerScripts > HelperPortrait
    Retrato de un ayudante dentro de la interfaz (ViewportFrame con el mismo cuerpo de HelperModel).
      HelperPortrait.Build(parent, parsed, size, pos, opts) -> ViewportFrame
        opts: { Full: boolean? (cuerpo entero; si no, busto), Animate: boolean? (respira y se mueve), Spin: boolean? (gira despacio), Dim: boolean? (silueta oscura: sin obtener) }
    El ViewportFrame se destruye con su ventana; la animación se corta sola al desaparecer.
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HelperCatalog = require(Modules:WaitForChild("HelperCatalog"))
local HelperModel = require(Modules:WaitForChild("HelperModel"))

local HelperPortrait = {}

function HelperPortrait.Build(parent: Instance, parsed: HelperCatalog.Parsed, size: UDim2, pos: UDim2, opts: { Full: boolean?, Animate: boolean?, Spin: boolean?, Dim: boolean? }?): ViewportFrame
	local full = opts ~= nil and opts.Full == true
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Retrato"
	vp.Size = size
	vp.Position = pos
	vp.BackgroundTransparency = 1
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(190, 190, 200)
	vp.LightColor = Color3.fromRGB(255, 244, 225)
	vp.LightDirection = Vector3.new(-0.4, -0.6, -0.8)
	vp.Parent = parent

	local built = HelperModel.Build(parsed, { Scale = 1 })
	local s = built.Scale
	built.Root.CFrame = CFrame.new(0, 0, 0)
	if opts and opts.Dim then
		for _, d in ipairs(built.Model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				d.Color = Color3.fromRGB(34, 34, 42)
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	built.Model.Parent = vp

	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	vp.CurrentCamera = cam
	cam.Parent = vp
	-- el frente del modelo es -Z: la cámara mira desde -Z (un poco de lado para dar volumen)
	local function place(yaw: number)
		if full then
			local center = Vector3.new(0, 1.2 * s, 0)
			local dist = 13.5 * s
			local dir = CFrame.Angles(0, yaw, 0) * Vector3.new(0.35, 0.12, -1)
			cam.CFrame = CFrame.lookAt(center + dir.Unit * dist, center)
		else
			local center = Vector3.new(0, 2.7 * s, 0)
			local dist = 7.2 * s
			local dir = CFrame.Angles(0, yaw, 0) * Vector3.new(0.25, 0.05, -1)
			cam.CFrame = CFrame.lookAt(center + dir.Unit * dist, center)
		end
	end
	place(0)

	if opts and (opts.Animate or opts.Spin) then
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.Heartbeat:Connect(function()
			if not vp.Parent or not vp:IsDescendantOf(game) then
				conn:Disconnect()
				return
			end
			local t = os.clock() - t0
			if opts.Animate then
				HelperModel.Animate(built, t, 0, -1, 0)
			end
			if opts.Spin then
				place(math.sin(t * 0.6) * 0.7)
			end
		end)
		vp.Destroying:Connect(function()
			if conn.Connected then
				conn:Disconnect()
			end
		end)
	end
	return vp
end

return HelperPortrait
