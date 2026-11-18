--!strict
--[[
    HelperPortrait (ModuleScript) -> StarterPlayer > StarterPlayerScripts > HelperPortrait
    Retrato de un ayudante dentro de la interfaz (ViewportFrame con el mismo cuerpo de HelperModel: COPIA DE TU PERSONAJE).
      HelperPortrait.Build(parent, parsed, size, pos, opts) -> ViewportFrame
        opts: { Full: boolean? (cuerpo entero; si no, busto), Animate: boolean? (respira y se mueve), Spin: boolean? (gira despacio), Dim: boolean? (silueta oscura: sin obtener),
                Props: string? (armas, atributo HelperProp<n> del jugador; sin esto sale sin armas), Owner: Player? (de quién se copia el cuerpo; por defecto tú) }
    El ViewportFrame se destruye con su ventana; la animación se corta sola al desaparecer.
    Para no cargar la pantalla, solo los MAX_AVATARS retratos vivos a la vez copian tu personaje; los demás salen con el cuerpo de bloques.
]]
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HelperCatalog = require(Modules:WaitForChild("HelperCatalog"))
local HelperModel = require(Modules:WaitForChild("HelperModel"))

local HelperPortrait = {}

local MAX_AVATARS = 36
local liveAvatars = 0

local function silhouette(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = Color3.fromRGB(34, 34, 42)
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") or d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") then
			d:Destroy()
		end
	end
end

function HelperPortrait.Build(parent: Instance, parsed: HelperCatalog.Parsed, size: UDim2, pos: UDim2, opts: { Full: boolean?, Animate: boolean?, Spin: boolean?, Dim: boolean?, Props: string?, Owner: Player? }?): ViewportFrame
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

	local owner: Player? = if opts and opts.Owner then opts.Owner else Players.LocalPlayer
	local wantAvatar = liveAvatars < MAX_AVATARS
	local built = HelperModel.Build(parsed, { Scale = 1, Owner = if wantAvatar then owner else nil, Props = if opts then opts.Props else nil })
	if built.IsAvatar then
		liveAvatars += 1
		vp.Destroying:Connect(function()
			liveAvatars = math.max(0, liveAvatars - 1)
		end)
	end
	built.Root.CFrame = CFrame.new(0, 0, 0)
	if opts and opts.Dim then
		silhouette(built.Model)
	end
	built.Model.Parent = vp
	HelperModel.Pose(built) -- en un ViewportFrame no hay física: las piezas se colocan a mano

	-- encuadre según la altura real del cuerpo (la raíz está en el origen; los pies a -Feet y la cabeza a +Top)
	local bodyH = built.Top + built.Feet
	local midY = (built.Top - built.Feet) / 2
	local cam = Instance.new("Camera")
	cam.FieldOfView = 32
	vp.CurrentCamera = cam
	cam.Parent = vp
	-- el frente del modelo es -Z: la cámara mira desde -Z (un poco de lado para dar volumen)
	local function place(yaw: number)
		if full then
			local center = Vector3.new(0, midY, 0)
			local dist = bodyH * 2.55
			local dir = CFrame.Angles(0, yaw, 0) * Vector3.new(0.35, 0.12, -1)
			cam.CFrame = CFrame.lookAt(center + dir.Unit * dist, center)
		else
			local center = Vector3.new(0, built.Top - bodyH * 0.17, 0)
			local dist = bodyH * 1.35
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
				HelperModel.Pose(built)
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
