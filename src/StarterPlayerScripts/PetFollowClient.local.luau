--!strict
--[[
    PetFollowClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > PetFollowClient
    MASCOTAS CON CUERPO: la mascota equipada (ranura "Mascota" = Equip_Accesorio2, ids Pet_<Familia>_<Rareza>) aparece
    como una criatura pequeña que SIGUE al personaje. Todos ven las mascotas de los jugadores cercanos.
      - Aspecto por familia (PetCatalog.Looks): zorro, tanuki, búho, tortuga, tigre, fénix, dragón, hada, lobo.
      - La rareza cambia tamaño y brillo: Común sencilla · Raro chispas · Épico luz · Legendario luz y más grande · Mítico halo.
      - Las que vuelan flotan y aletean; las de tierra caminan pegadas al suelo y saltan al correr.
      - Al subir de nivel el dueño ve a su mascota dar una vuelta de celebración.
      - Solo es visual (se crea en cada cliente); los bonus los sigue dando GearService.
    No tiene ScreenGui, no va en RELOAD.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local PetCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PetCatalog"))

local VIEW_RANGE = 150
local RARITY = {
	Comun = { Scale = 0.85, Color = Color3.fromRGB(200, 200, 200) },
	Raro = { Scale = 0.95, Color = Color3.fromRGB(80, 160, 255) },
	Epico = { Scale = 1.05, Color = Color3.fromRGB(180, 90, 255) },
	Legendario = { Scale = 1.18, Color = Color3.fromRGB(255, 170, 40) },
	Mitico = { Scale = 1.3, Color = Color3.fromRGB(255, 70, 110) },
} :: { [string]: { Scale: number, Color: Color3 } }
local RARITY_INDEX = { Comun = 1, Raro = 2, Epico = 3, Legendario = 4, Mitico = 5 } :: { [string]: number }

local folder = Workspace:FindFirstChild("PetsFx") or Instance.new("Folder")
folder.Name = "PetsFx"
folder.Parent = Workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { folder }

type Pet = {
	Player: Player,
	Id: string,
	Char: Model,
	Root: Part,
	Model: Model,
	Look: { [string]: any },
	Rarity: string,
	Scale: number,
	Wings: { { Weld: Weld, Side: number, Base: CFrame } },
	Halo: Weld?,
	Cf: CFrame,
	Vel: Vector3,
	Phase: number,
	SpinUntil: number,
	Tag: BillboardGui?,
}
local pets: { [Player]: Pet } = {}

local function parse(id: any): (string?, string?)
	if typeof(id) ~= "string" then
		return nil, nil
	end
	local fam, rar = string.match(id, "^Pet_(%w+)_(%w+)$")
	if fam and rar and PetCatalog.Looks[fam] and RARITY[rar] then
		return fam, rar
	end
	return nil, nil
end

local function part(model: Model, root: Part, shape: Enum.PartType, size: Vector3, color: Color3, offset: CFrame, material: Enum.Material?, transparency: number?): (Part, Weld)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.Parent = model
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	return p, w
end

local function build(pl: Player, id: string, family: string, rarity: string, char: Model): Pet?
	local look = PetCatalog.Looks[family]
	local rr = RARITY[rarity]
	local s = rr.Scale
	local model = Instance.new("Model")
	model.Name = "Pet_" .. pl.Name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.Parent = model
	model.PrimaryPart = root

	local body: Color3, accent: Color3 = look.Body, look.Accent
	local B = Enum.PartType.Ball
	local K = Enum.PartType.Block
	local wings: { { Weld: Weld, Side: number, Base: CFrame } } = {}
	local dark = Color3.fromRGB(25, 22, 30)

	-- cuerpo y cabeza (el frente es -Z)
	part(model, root, B, Vector3.one * 1.5 * s, body, CFrame.new(0, 0, 0.2 * s))
	part(model, root, B, Vector3.one * 1.0 * s, body, CFrame.new(0, 0.75 * s, -0.55 * s))
	part(model, root, B, Vector3.one * 0.85 * s, accent, CFrame.new(0, -0.15 * s, -0.5 * s), nil, 0.0) -- panza / pecho
	-- ojos
	for _, sx in ipairs({ -1, 1 }) do
		part(model, root, B, Vector3.one * 0.18 * s, dark, CFrame.new(sx * 0.2 * s, 0.85 * s, -1.0 * s), Enum.Material.SmoothPlastic)
	end
	if look.Ears then
		for _, sx in ipairs({ -1, 1 }) do
			part(model, root, K, Vector3.new(0.28, 0.5, 0.2) * s, body, CFrame.new(sx * 0.32 * s, 1.35 * s, -0.5 * s) * CFrame.Angles(0, 0, -sx * 0.25))
		end
	end
	if look.Tail then
		part(model, root, B, Vector3.one * 0.5 * s, accent, CFrame.new(0, 0.2 * s, 1.15 * s))
		part(model, root, B, Vector3.one * 0.38 * s, body, CFrame.new(0, 0.5 * s, 1.5 * s))
	end
	if look.Horns then
		for _, sx in ipairs({ -1, 1 }) do
			part(model, root, K, Vector3.new(0.14, 0.45, 0.14) * s, accent, CFrame.new(sx * 0.3 * s, 1.35 * s, -0.55 * s) * CFrame.Angles(0, 0, -sx * 0.4))
		end
	end
	if look.Shell then
		part(model, root, B, Vector3.new(1.9, 1.9, 1.9) * s, accent, CFrame.new(0, 0.45 * s, 0.35 * s))
		part(model, root, B, Vector3.new(1.4, 1.4, 1.4) * s, body:Lerp(accent, 0.35), CFrame.new(0, 0.85 * s, 0.35 * s))
	end
	if look.Stripes then
		for i = -1, 1 do
			part(model, root, K, Vector3.new(1.55, 0.14, 0.16) * s, accent, CFrame.new(0, 0.62 * s, (0.2 + i * 0.42) * s))
		end
	end
	if look.Wings then
		for _, side in ipairs({ -1, 1 }) do
			local base = CFrame.new(side * 0.8 * s, 0.4 * s, 0.35 * s)
			local trans = if look.Sparkle then 0.45 else 0
			local p, w = part(model, root, K, Vector3.new(1.3, 0.1, 0.85) * s, accent, base, if look.Sparkle then Enum.Material.Neon else Enum.Material.SmoothPlastic, trans)
			p.Size = Vector3.new(1.3 * s, 0.1 * s, 0.85 * s)
			table.insert(wings, { Weld = w, Side = side, Base = base })
		end
	end

	-- brillo por rareza
	local idx = RARITY_INDEX[rarity]
	local emitAt = root
	if idx >= 2 or look.Fire or look.Sparkle then
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(if look.Fire then Color3.fromRGB(255, 160, 50) else rr.Color, accent)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * s), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(0.6, 1.2)
		pe.Speed = NumberRange.new(0.5, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rate = if look.Fire or look.Sparkle then 14 else 2 + idx * 2
		pe.Parent = emitAt
	end
	if idx >= 3 then
		local light = Instance.new("PointLight")
		light.Color = rr.Color
		light.Range = 5 + idx * 2
		light.Brightness = 0.8 + idx * 0.25
		light.Parent = root
	end
	local halo: Weld? = nil
	if idx >= 5 then
		local hp, hw = part(model, root, K, Vector3.new(0.12, 1.1 * s, 1.1 * s), rr.Color, CFrame.new(0, 1.9 * s, -0.5 * s) * CFrame.Angles(0, 0, math.pi / 2), Enum.Material.Neon, 0.15)
		hp.Shape = Enum.PartType.Cylinder
		hp.Size = Vector3.new(0.12, 1.1 * s, 1.1 * s)
		halo = hw
	end

	local tag: BillboardGui? = nil
	if pl == localPlayer then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 20)
		bb.StudsOffset = Vector3.new(0, 2.6 * s, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 40
		bb.Adornee = root
		bb.Parent = root
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = 13
		t.TextColor3 = rr.Color
		t.TextStrokeTransparency = 0.4
		t.Text = (PetCatalog.Families[family] :: any).Name
		t.Parent = bb
		tag = bb
	end

	model.Parent = folder
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local start = if hrp and hrp:IsA("BasePart") then hrp.CFrame * CFrame.new(3, 0, 3) else CFrame.new()
	return {
		Player = pl, Id = id, Char = char, Root = root, Model = model, Look = look, Rarity = rarity, Scale = s,
		Wings = wings, Halo = halo, Cf = start, Vel = Vector3.zero, Phase = math.random() * 6, SpinUntil = 0, Tag = tag,
	}
end

local function remove(pl: Player)
	local p = pets[pl]
	if p then
		p.Model:Destroy()
		pets[pl] = nil
	end
end

-- cada medio segundo: ¿qué mascota debería tener cada jugador?
local function reconcile()
	local cam = Workspace.CurrentCamera
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local family, rarity = parse(pl:GetAttribute("Equip_Accesorio2"))
		local want = family ~= nil and rarity ~= nil and hrp ~= nil and hrp:IsA("BasePart") and hum ~= nil and hum.Health > 0
		if want and pl ~= localPlayer and cam and hrp and (cam.CFrame.Position - hrp.Position).Magnitude > VIEW_RANGE then
			want = false
		end
		local cur = pets[pl]
		if not want then
			if cur then
				remove(pl)
			end
		else
			local id = pl:GetAttribute("Equip_Accesorio2") :: string
			if not cur or cur.Id ~= id or cur.Char ~= char then
				remove(pl)
				local made = build(pl, id, family :: string, rarity :: string, char :: Model)
				if made then
					pets[pl] = made
				end
			end
		end
	end
end

local acc = 0

RunService.RenderStepped:Connect(function(dt)
	acc += dt
	if acc >= 0.5 then
		acc = 0
		reconcile()
	end
	local t = os.clock()
	for pl, p in pairs(pets) do
		local hrp = p.Char:FindFirstChild("HumanoidRootPart")
		if not hrp or not hrp:IsA("BasePart") or not p.Char.Parent then
			remove(pl)
			continue
		end
		local flies: boolean = p.Look.Flies == true
		local s = p.Scale
		-- punto donde "debería" estar: detrás y a la derecha del dueño
		local anchorCf = hrp.CFrame * CFrame.new(3.0, 0, 3.6)
		local target = anchorCf.Position
		local bob = 0
		local speed = p.Vel.Magnitude
		if flies then
			bob = 3.3 + math.sin(t * 2.2 + p.Phase) * 0.4
		else
			local hit = Workspace:Raycast(target + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), rayParams)
			target = Vector3.new(target.X, if hit then hit.Position.Y else hrp.Position.Y - 3, target.Z)
			bob = 0.75 * s + (if speed > 3 then math.abs(math.sin(t * 9 + p.Phase)) * 0.55 else 0)
		end
		target += Vector3.new(0, bob, 0)

		local cur = p.Cf.Position
		if (cur - target).Magnitude > 60 then
			cur = target
		end
		local alpha = 1 - math.exp(-6.5 * dt)
		local newPos = cur:Lerp(target, alpha)
		p.Vel = (newPos - cur) / math.max(dt, 1e-3)
		-- orientación: hacia donde se mueve; quieta, mira como el dueño
		local flat = Vector3.new(p.Vel.X, 0, p.Vel.Z)
		local dir = if flat.Magnitude > 2.5 then flat.Unit else Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
		if dir.Magnitude < 0.01 then
			dir = Vector3.new(0, 0, -1)
		end
		local want = CFrame.lookAt(newPos, newPos + dir.Unit)
		local baseCf = CFrame.new(newPos) * p.Cf.Rotation:Lerp(want.Rotation, 1 - math.exp(-9 * dt))
		p.Cf = baseCf -- (sin el giro de celebración, que es solo de adorno)
		local cf = baseCf
		-- vuelta de celebración al subir de nivel
		if t < p.SpinUntil then
			local k = 1 - (p.SpinUntil - t) / 1.2
			cf = baseCf * CFrame.Angles(0, k * math.pi * 4, 0) + Vector3.new(0, math.sin(k * math.pi) * 2.2, 0)
		end
		p.Root.CFrame = cf
		-- aleteo y halo
		for _, w in ipairs(p.Wings) do
			local flap = math.sin(t * (if flies then 11 else 3) + p.Phase) * (if flies then 0.55 else 0.12)
			w.Weld.C0 = w.Base * CFrame.Angles(0, 0, w.Side * (0.35 + flap))
		end
		if p.Halo then
			p.Halo.C0 = CFrame.new(0, 1.9 * s + math.sin(t * 2) * 0.08, -0.5 * s) * CFrame.Angles(0, t * 2, math.pi / 2)
		end
	end
end)

-- celebración: cualquier jugador que sube de nivel
local lastLevel: { [Player]: number } = {}
local function watch(pl: Player)
	local v = pl:GetAttribute("Level")
	if typeof(v) == "number" then
		lastLevel[pl] = v
	end
	pl:GetAttributeChangedSignal("Level"):Connect(function()
		local n = pl:GetAttribute("Level")
		if typeof(n) ~= "number" then
			return
		end
		local prev = lastLevel[pl]
		lastLevel[pl] = n
		if prev and n > prev and pets[pl] then
			(pets[pl] :: Pet).SpinUntil = os.clock() + 1.2
		end
	end)
end
Players.PlayerAdded:Connect(watch)
for _, pl in ipairs(Players:GetPlayers()) do
	watch(pl)
end
Players.PlayerRemoving:Connect(function(pl)
	remove(pl)
	lastLevel[pl] = nil
end)
