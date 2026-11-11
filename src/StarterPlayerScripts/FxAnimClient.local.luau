--!strict
--[[
    FxAnimClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > FxAnimClient
    Anima en el cliente las piezas con tag "FxAnim" (altares, campamentos, guaridas). El servidor solo pone atributos:
      FxSpin (grados/s, gira sobre el eje vertical)         FxBob (altura) + FxBobSpeed (rad/s)
      FxCenter (Vector3) + FxOrbitR + FxOrbitSpeed (grados/s) + FxOrbitPhase (grados) + FxOrbitY  -> órbita horizontal
      FxPulse (0-1): la luz de la pieza late      FxFade (0-1): la transparencia late
    Solo se anima lo que está cerca de la cámara.
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "FxAnim"
local RANGE = 200

type State = { Base: CFrame, Rot: CFrame, Light: PointLight?, LightBase: number, TrBase: number }

local items: { [BasePart]: State } = {}

local function add(inst: Instance)
	if inst:IsA("BasePart") and not items[inst] then
		local light = inst:FindFirstChildOfClass("PointLight")
		items[inst] = {
			Base = inst.CFrame,
			Rot = inst.CFrame - inst.CFrame.Position,
			Light = light,
			LightBase = if light then light.Brightness else 0,
			TrBase = inst.Transparency,
		}
	end
end

for _, i in ipairs(CollectionService:GetTagged(TAG)) do
	add(i)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(i)
	if i:IsA("BasePart") then
		items[i] = nil
	end
end)

RunService.RenderStepped:Connect(function()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = os.clock()
	for p, st in pairs(items) do
		if p.Parent == nil then
			items[p] = nil
		elseif (st.Base.Position - camPos).Magnitude < RANGE then
			local pos = st.Base.Position
			local ang = 0
			local spin = p:GetAttribute("FxSpin")
			if typeof(spin) == "number" then
				ang = math.rad(spin) * t
			end
			local orbitR = p:GetAttribute("FxOrbitR")
			if typeof(orbitR) == "number" then
				local c = p:GetAttribute("FxCenter")
				local sp = p:GetAttribute("FxOrbitSpeed")
				local ph = p:GetAttribute("FxOrbitPhase")
				local oy = p:GetAttribute("FxOrbitY")
				if typeof(c) == "Vector3" then
					local a = math.rad((if typeof(ph) == "number" then ph else 0) + (if typeof(sp) == "number" then sp else 30) * t)
					pos = c + Vector3.new(math.cos(a) * orbitR, if typeof(oy) == "number" then oy else 0, math.sin(a) * orbitR)
				end
			end
			local bob = p:GetAttribute("FxBob")
			if typeof(bob) == "number" then
				local bs = p:GetAttribute("FxBobSpeed")
				pos += Vector3.new(0, math.sin(t * (if typeof(bs) == "number" then bs else 1.5) + pos.X * 0.07) * bob, 0)
			end
			p.CFrame = CFrame.new(pos) * CFrame.Angles(0, ang, 0) * st.Rot
			local pulse = p:GetAttribute("FxPulse")
			if typeof(pulse) == "number" and st.Light then
				st.Light.Brightness = st.LightBase * (1 + pulse * (0.6 * math.sin(t * 3.1 + pos.X) + 0.4 * math.sin(t * 7.7 + pos.Z)))
			end
			local fade = p:GetAttribute("FxFade")
			if typeof(fade) == "number" then
				p.Transparency = math.clamp(st.TrBase + fade * math.sin(t * 2 + pos.X * 0.1), 0, 1)
			end
		end
	end
end)
