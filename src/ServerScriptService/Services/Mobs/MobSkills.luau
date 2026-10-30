--!strict
--[[
    MobSkills (ModuleScript) -> ServerScriptService.Services.Mobs.MobSkills
    BIBLIOTECA de habilidades de enemigos. Cada "Kind" del MobCatalog es una función aquí.
    Para crear un poder nuevo: agrega una función a `Kinds` y úsala desde el catálogo (sin tocar la IA).

    Convención: Kinds[kind](ctx, skill, target) -> se ejecuta en su propio hilo (puede esperar el "Windup").
    El daño SIEMPRE pasa por DamageService.Deal(mobModel, jugador, skill.Mult, opts).
    Los ataques de área muestran un círculo rojo de aviso (telegraph) durante el Windup para que el jugador pueda esquivar.

    ctx = { Model, Root, Humanoid, Level, Alive(): boolean, Summon(id, count), Aura: Color3 }
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageService = require(ServerScriptService.Services.DamageService)
local AttackAnimator = require(ServerScriptService.Services.AttackAnimator)

export type Ctx = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid,
	Level: number,
	Alive: () -> boolean,
	Summon: (id: string, count: number) -> (),
	Color: Color3,
}

local MobSkills = {}

---------------------------------------------------------------------
-- utilidades
---------------------------------------------------------------------
-- Muros de jugador (Gaara / Jinbe): partes con tag "BlockProjectile" detienen los proyectiles
local function blockedAt(pos: Vector3): boolean
	for _, part in ipairs(CollectionService:GetTagged("BlockProjectile")) do
		if part:IsA("BasePart") then
			local l = part.CFrame:PointToObjectSpace(pos)
			local h = part.Size / 2
			if math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z + 1.5 then
				return true
			end
		end
	end
	return false
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function dirTo(from: Vector3, to: Vector3): Vector3
	local d = flat(to - from)
	return if d.Magnitude > 0.01 then d.Unit else Vector3.new(0, 0, -1)
end

local function targetRoot(t: Model): BasePart?
	local r = t:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function livePlayers(): { { Model: Model, Root: BasePart } }
	local out = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		local c = pl.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local root = c and targetRoot(c)
		if c and hum and hum.Health > 0 and root then
			table.insert(out, { Model = c, Root = root })
		end
	end
	return out
end

local function groundY(ctx: Ctx): number
	return ctx.Root.Position.Y - 3 * ctx.Model:GetScale()
end

local function face(ctx: Ctx, pos: Vector3)
	local p = ctx.Root.Position
	ctx.Root.CFrame = CFrame.lookAt(p, Vector3.new(pos.X, p.Y, pos.Z))
end

local function hit(ctx: Ctx, victim: Model, skill: any, origin: Vector3)
	local push: Vector3? = nil
	if skill.Push then
		local d = dirTo(origin, targetRoot(victim) and (targetRoot(victim) :: BasePart).Position or origin)
		push = d * skill.Push + Vector3.new(0, 25, 0)
	end
	DamageService.Deal(ctx.Model, victim, skill.Mult or 1, { Stun = skill.Stun, Slow = skill.Slow, Push = push })
end

local function fx(shape: Enum.PartType, cf: CFrame, size: Vector3, color: Color3, transparency: number, life: number): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = size
	p.CFrame = cf
	p.Parent = workspace
	Debris:AddItem(p, life)
	return p
end


---------------------------------------------------------------------
-- BIBLIOTECA VISUAL POR ANIME (solo efectos; el daño sigue en DamageService)
-- Cada skill del catálogo puede llevar Fx = "shuriken" | "kunai" | "fire" | "ki" | "bullet" ... y se dibuja distinto.
---------------------------------------------------------------------
local FX_COLOR: { [string]: Color3 } = {
	fire = Color3.fromRGB(255, 120, 30), poison = Color3.fromRGB(110, 200, 60), ice = Color3.fromRGB(150, 220, 255),
	smoke = Color3.fromRGB(160, 160, 170), seal = Color3.fromRGB(190, 120, 255), shock = Color3.fromRGB(235, 245, 255),
	bomb = Color3.fromRGB(255, 170, 60), water = Color3.fromRGB(80, 170, 255), bone = Color3.fromRGB(235, 230, 215),
	psychic = Color3.fromRGB(200, 120, 255), haki = Color3.fromRGB(150, 50, 190), supernova = Color3.fromRGB(255, 100, 170),
	pose = Color3.fromRGB(255, 230, 90), trap = Color3.fromRGB(220, 220, 220), sonic = Color3.fromRGB(200, 230, 255),
	blackhole = Color3.fromRGB(70, 30, 110), mist = Color3.fromRGB(200, 215, 230),
	cero = Color3.fromRGB(255, 70, 70), getsuga = Color3.fromRGB(40, 20, 90), reishi = Color3.fromRGB(110, 210, 255), reiatsu = Color3.fromRGB(150, 230, 255),
	kido = Color3.fromRGB(255, 190, 60), hollow = Color3.fromRGB(235, 235, 240),
}

-- Animación del atacante según el efecto (si no hay, se usa la del tipo de habilidad)
local FX_ANIM: { [string]: string } = {
	shuriken = "Throw", kunai = "Throw", needle = "Throw", knife = "Throw", blade = "Throw", bone = "Throw",
	bullet = "Shoot", cannon = "Shoot", pierce = "Stab",
	ki = "Cast", fire = "Cast", water = "Cast", snake = "Cast", spit = "Cast", seal = "Cast", psychic = "Cast", supernova = "Power",
	pose = "Power", haki = "Power", mist = "Power", shock = "Slam", slash = "Slash", fireSlash = "Slash", claw = "Slash", punch = "Punch",
	kick = "Punch", tail = "Slam", slashwave = "Slash",
	cero = "Cast", getsuga = "Slash", reishi = "Cast", reiatsu = "Power", kido = "Cast", hollow = "Slam",
}

local function puff(pos: Vector3, color: Color3, count: number, spread: number, life: number, size: number?)
	for _ = 1, count do
		local off = Vector3.new((math.random() - 0.5) * spread, math.random() * spread * 0.5, (math.random() - 0.5) * spread)
		local s = (size or 3) * (0.6 + math.random() * 0.8)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Color = color
		p.Transparency = 0.25
		p.Size = Vector3.new(s, s, s)
		p.Position = pos + off
		p.Parent = workspace
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(s * 1.8, s * 1.8, s * 1.8), Position = p.Position + Vector3.new(0, 2.5, 0) }):Play()
		Debris:AddItem(p, life + 0.1)
	end
end

local function ring(pos: Vector3, color: Color3, radius: number, life: number, y: number?)
	local r = Instance.new("Part")
	r.Shape = Enum.PartType.Cylinder
	r.Anchored = true
	r.CanCollide = false
	r.CanQuery = false
	r.CanTouch = false
	r.CastShadow = false
	r.Material = Enum.Material.Neon
	r.Color = color
	r.Transparency = 0.2
	r.Size = Vector3.new(0.4, 2, 2)
	r.CFrame = CFrame.new(pos.X, y or pos.Y, pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	r.Parent = workspace
	TweenService:Create(r, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(r, life + 0.1)
end

local function leaves(pos: Vector3, count: number)
	for _ = 1, count do
		local l = Instance.new("Part")
		l.Anchored = true
		l.CanCollide = false
		l.CanQuery = false
		l.CanTouch = false
		l.CastShadow = false
		l.Material = Enum.Material.Grass
		l.Color = if math.random() < 0.5 then Color3.fromRGB(90, 170, 70) else Color3.fromRGB(140, 110, 60)
		l.Size = Vector3.new(0.9, 0.12, 0.6)
		l.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 3, math.random() * 3, (math.random() - 0.5) * 3)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
		l.Parent = workspace
		TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Transparency = 1, Position = l.Position + Vector3.new((math.random() - 0.5) * 8, 2 + math.random() * 4, (math.random() - 0.5) * 8), Orientation = Vector3.new(math.random() * 360, math.random() * 360, 0) }):Play()
		Debris:AddItem(l, 0.9)
	end
end

local function spark(pos: Vector3, color: Color3, size: number?)
	local s = size or 2.4
	local p = fx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(s, s, s), color, 0.1, 0.2)
	TweenService:Create(p, TweenInfo.new(0.18), { Size = Vector3.new(s * 2, s * 2, s * 2), Transparency = 1 }):Play()
end

-- Arco de tajo: n segmentos neón siguiendo un arco frente al atacante (claw = 3 tajos paralelos)
local function slashArc(origin: Vector3, forward: Vector3, radius: number, angle: number, color: Color3, claws: number?, y: number?)
	local count = 8
	local yy = (y or origin.Y) + 0.5
	for c = 1, (claws or 1) do
		local lift = if claws and claws > 1 then (c - (claws + 1) / 2) * 1.6 else 0
		for i = 0, count do
			local a = math.rad(-angle / 2 + angle * i / count)
			local d = CFrame.Angles(0, a, 0):VectorToWorldSpace(forward)
			local pos = origin + d * (radius * 0.85) + Vector3.new(0, lift + 1.5, 0)
			local seg = fx(Enum.PartType.Block, CFrame.lookAt(Vector3.new(pos.X, yy + lift + 1, pos.Z), Vector3.new(pos.X + d.Z, yy + lift + 1, pos.Z - d.X)), Vector3.new(0.35, 0.35, radius * 0.45), color, 0.1, 0.3)
			TweenService:Create(seg, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.1, 0.1, radius * 0.5) }):Play()
		end
	end
end

type ProjSpec = { Parts: { { Shape: Enum.PartType?, Size: Vector3, Color: Color3, Mat: Enum.Material, Off: CFrame, Transp: number? } }, SpinY: boolean, Spin: number, Fire: boolean? }

local function projSpec(style: string?, size: number, color: Color3): ProjSpec
	local Ball, Neon, Metal = Enum.PartType.Ball, Enum.Material.Neon, Enum.Material.Metal
	local steel = Color3.fromRGB(200, 205, 215)
	local function P(shape: Enum.PartType?, sz: Vector3, c: Color3, m: Enum.Material, off: CFrame?, tr: number?)
		return { Shape = shape, Size = sz, Color = c, Mat = m, Off = off or CFrame.new(), Transp = tr }
	end
	if style == "shuriken" then
		return { Parts = { P(nil, Vector3.new(2, 0.16, 0.55), steel, Metal), P(nil, Vector3.new(2, 0.16, 0.55), steel, Metal, CFrame.Angles(0, math.rad(90), 0)), P(nil, Vector3.new(1.5, 0.16, 0.5), Color3.fromRGB(150, 155, 170), Metal, CFrame.Angles(0, math.rad(45), 0)), P(nil, Vector3.new(1.5, 0.16, 0.5), Color3.fromRGB(150, 155, 170), Metal, CFrame.Angles(0, math.rad(135), 0)) }, SpinY = true, Spin = 22 }
	elseif style == "kunai" or style == "knife" then
		local body = if style == "knife" then Color3.fromRGB(190, 195, 205) else Color3.fromRGB(60, 62, 72)
		return { Parts = { P(nil, Vector3.new(0.3, 0.3, 1.5), body, Metal), P(nil, Vector3.new(0.34, 0.34, 0.9), steel, Metal, CFrame.new(0, 0, -1.1)), P(nil, Vector3.new(0.9, 0.9, 0.16), Color3.fromRGB(40, 40, 50), Metal, CFrame.new(0, 0, 0.85)) }, SpinY = false, Spin = 0 }
	elseif style == "needle" then
		return { Parts = { P(nil, Vector3.new(0.18, 0.18, 2.8), Color3.fromRGB(190, 225, 255), Neon) }, SpinY = false, Spin = 0 }
	elseif style == "bullet" then
		return { Parts = { P(nil, Vector3.new(0.3, 0.3, 3.4), Color3.fromRGB(255, 235, 130), Neon), P(nil, Vector3.new(0.9, 0.9, 3.8), Color3.fromRGB(255, 200, 80), Neon, nil, 0.75) }, SpinY = false, Spin = 0 }
	elseif style == "cannon" then
		return { Parts = { P(Ball, Vector3.new(size * 1.4, size * 1.4, size * 1.4), Color3.fromRGB(45, 45, 52), Metal), P(Ball, Vector3.new(size * 0.7, size * 0.7, size * 0.7), Color3.fromRGB(255, 140, 40), Neon, CFrame.new(0, 0, size * 0.9)) }, SpinY = false, Spin = 0, Fire = true }
	elseif style == "fire" then
		return { Parts = { P(Ball, Vector3.new(size * 1.1, size * 1.1, size * 1.1), Color3.fromRGB(255, 120, 30), Neon, nil, 0.1), P(Ball, Vector3.new(size * 0.6, size * 0.6, size * 0.6), Color3.fromRGB(255, 230, 120), Neon) }, SpinY = false, Spin = 0, Fire = true }
	elseif style == "water" then
		return { Parts = { P(Ball, Vector3.new(size * 1.1, size * 1.1, size * 1.1), Color3.fromRGB(80, 170, 255), Neon, nil, 0.35), P(Ball, Vector3.new(size * 0.5, size * 0.5, size * 0.5), Color3.new(1, 1, 1), Neon, nil, 0.4) }, SpinY = false, Spin = 0 }
	elseif style == "ki" then
		return { Parts = { P(Ball, Vector3.new(size, size, size), color, Neon, nil, 0.1), P(Ball, Vector3.new(size * 0.55, size * 0.55, size * 0.55), Color3.new(1, 1, 1), Neon), P(Ball, Vector3.new(size * 1.6, size * 1.6, size * 1.6), color, Neon, nil, 0.75) }, SpinY = false, Spin = 0 }
	elseif style == "bone" then
		return { Parts = { P(nil, Vector3.new(0.55, 0.55, 3.4), Color3.fromRGB(235, 230, 215), Enum.Material.SmoothPlastic), P(Ball, Vector3.new(1, 1, 1), Color3.fromRGB(235, 230, 215), Enum.Material.SmoothPlastic, CFrame.new(0, 0, 1.7)) }, SpinY = false, Spin = 0 }
	elseif style == "snake" then
		return { Parts = { P(nil, Vector3.new(0.9, 0.9, 3.2), Color3.fromRGB(90, 170, 70), Enum.Material.Slate), P(Ball, Vector3.new(1.5, 1.2, 1.5), Color3.fromRGB(70, 140, 55), Enum.Material.Slate, CFrame.new(0, 0, -1.7)) }, SpinY = false, Spin = 0 }
	elseif style == "blade" then
		return { Parts = { P(nil, Vector3.new(0.25, 2.4, 1.0), steel, Metal), P(nil, Vector3.new(0.3, 0.5, 0.5), Color3.fromRGB(150, 60, 160), Neon, CFrame.new(0, -1.2, 0)) }, SpinY = false, Spin = 14 }
	elseif style == "spit" then
		return { Parts = { P(Ball, Vector3.new(size, size, size), Color3.fromRGB(190, 220, 70), Neon, nil, 0.2) }, SpinY = false, Spin = 0 }
	elseif style == "cero" then
		return { Parts = { P(Ball, Vector3.new(size * 1.2, size * 1.2, size * 1.2), Color3.fromRGB(255, 60, 60), Neon, nil, 0.05), P(Ball, Vector3.new(size * 0.6, size * 0.6, size * 0.6), Color3.fromRGB(255, 220, 220), Neon), P(Ball, Vector3.new(size * 1.9, size * 1.9, size * 1.9), Color3.fromRGB(255, 40, 40), Neon, nil, 0.8) }, SpinY = false, Spin = 0 }
	elseif style == "getsuga" then
		return { Parts = { P(nil, Vector3.new(size * 3, size * 0.3, size * 0.8), Color3.fromRGB(30, 15, 80), Neon, nil, 0.05), P(nil, Vector3.new(size * 3.3, size * 0.5, size * 1.0), Color3.fromRGB(120, 90, 255), Neon, nil, 0.6) }, SpinY = false, Spin = 0 }
	elseif style == "reishi" then
		return { Parts = { P(nil, Vector3.new(0.22, 0.22, 3.6), Color3.fromRGB(120, 215, 255), Neon), P(nil, Vector3.new(0.7, 0.7, 4.0), Color3.fromRGB(200, 240, 255), Neon, nil, 0.75) }, SpinY = false, Spin = 0 }
	elseif style == "pillar" then
		return { Parts = { P(nil, Vector3.new(size * 1.1, size * 3, size * 1.1), Color3.fromRGB(150, 140, 130), Enum.Material.Slate) }, SpinY = false, Spin = 8 }
	end
	return { Parts = { P(Ball, Vector3.new(size, size, size), color, Neon, nil, 0) }, SpinY = false, Spin = 0 }
end

-- Crea las piezas del proyectil. Devuelve una función update(pos, dir, dt) y una función destroy()
local function makeProjectile(style: string?, pos: Vector3, d: Vector3, size: number, color: Color3, life: number)
	local spec = projSpec(style, size, color)
	local parts: { Part } = {}
	for _, ps in ipairs(spec.Parts) do
		local p = fx(ps.Shape or Enum.PartType.Block, CFrame.new(pos), ps.Size, ps.Color, ps.Transp or 0, life)
		p.Material = ps.Mat
		table.insert(parts, p)
	end
	if spec.Fire and parts[1] then
		local f = Instance.new("Fire")
		f.Size = math.max(4, size * 1.6)
		f.Heat = 6
		f.Parent = parts[1]
	end
	local angle = 0
	local function update(p: Vector3, dir: Vector3, dt: number)
		angle += spec.Spin * dt
		local base = if spec.SpinY then CFrame.new(p) * CFrame.Angles(0, angle, 0) else CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, angle)
		for i, part in ipairs(parts) do
			part.CFrame = base * spec.Parts[i].Off
		end
	end
	local function destroy()
		for _, part in ipairs(parts) do
			part:Destroy()
		end
	end
	return update, destroy, parts[1]
end

-- Destello de impacto según el estilo
local function impactFx(style: string?, pos: Vector3, radius: number?, color: Color3)
	local r = radius or 0
	if style == "shuriken" or style == "kunai" or style == "knife" or style == "needle" or style == "bullet" or style == "blade" or style == "bone" then
		spark(pos, if style == "bullet" then Color3.fromRGB(255, 220, 100) else Color3.fromRGB(235, 240, 255), 2)
	elseif style == "fire" or style == "cannon" then
		local b = fx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(3, 3, 3), Color3.fromRGB(255, 130, 40), 0.15, 0.4)
		TweenService:Create(b, TweenInfo.new(0.35), { Size = Vector3.new(math.max(8, r * 2), math.max(8, r * 2), math.max(8, r * 2)), Transparency = 1 }):Play()
		puff(pos, Color3.fromRGB(70, 70, 75), 4, math.max(4, r), 0.6, 3)
	elseif style == "water" then
		local b = fx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(3, 3, 3), Color3.fromRGB(120, 190, 255), 0.3, 0.4)
		TweenService:Create(b, TweenInfo.new(0.3), { Size = Vector3.new(math.max(7, r * 2), math.max(7, r * 2), math.max(7, r * 2)), Transparency = 1 }):Play()
	elseif style == "cero" then
		local b = fx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(3, 3, 3), Color3.fromRGB(255, 70, 70), 0.1, 0.45)
		TweenService:Create(b, TweenInfo.new(0.4), { Size = Vector3.new(math.max(9, r * 2), math.max(9, r * 2), math.max(9, r * 2)), Transparency = 1 }):Play()
		ring(pos, Color3.fromRGB(255, 120, 120), math.max(7, r), 0.45)
	elseif style == "reishi" or style == "getsuga" then
		spark(pos, if style == "reishi" then Color3.fromRGB(150, 225, 255) else Color3.fromRGB(150, 120, 255), 3)
		ring(pos, if style == "reishi" then Color3.fromRGB(150, 225, 255) else Color3.fromRGB(120, 90, 255), math.max(5, r), 0.35)
	elseif style == "spit" or style == "snake" then
		puff(pos, Color3.fromRGB(150, 200, 70), 4, 4, 0.5, 2.5)
	else
		local b = fx(Enum.PartType.Ball, CFrame.new(pos), Vector3.new(3, 3, 3), color, 0.2, 0.4)
		TweenService:Create(b, TweenInfo.new(0.35), { Size = Vector3.new(math.max(7, r * 2), math.max(7, r * 2), math.max(7, r * 2)), Transparency = 1 }):Play()
		ring(pos, color, math.max(6, r), 0.4)
	end
end

-- Efectos de desplazamiento: shunshin (Naruto), transmisión instantánea (Dragon Ball), geppo (One Piece), espejos
local function moveFx(style: string?, from: Vector3, to: Vector3, color: Color3)
	if style == "shunshin" then
		puff(from, Color3.fromRGB(215, 215, 220), 5, 4, 0.6, 3)
		leaves(from, 7)
		puff(to, Color3.fromRGB(215, 215, 220), 4, 4, 0.6, 3)
		leaves(to, 7)
	elseif style == "flash" then
		local len = (to - from).Magnitude
		if len > 1 then
			local mid = (from + to) / 2
			local streak = fx(Enum.PartType.Block, CFrame.lookAt(mid, to), Vector3.new(0.8, 0.8, len), Color3.new(1, 1, 1), 0.1, 0.3)
			TweenService:Create(streak, TweenInfo.new(0.28), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
		end
		spark(from, Color3.new(1, 1, 1), 5)
		spark(to, color, 6)
		ring(to, color, 8, 0.3)
	elseif style == "geppo" then
		ring(from, Color3.fromRGB(235, 245, 255), 8, 0.35, from.Y - 2.5)
		ring(to, Color3.fromRGB(235, 245, 255), 8, 0.35, to.Y - 2.5)
		puff(from, Color3.fromRGB(235, 240, 245), 3, 3, 0.4, 2)
	elseif style == "shunpo" then
		local len = (to - from).Magnitude
		if len > 1 then
			local streak = fx(Enum.PartType.Block, CFrame.lookAt((from + to) / 2, to), Vector3.new(1.2, 0.4, len), Color3.fromRGB(230, 225, 255), 0.2, 0.3)
			TweenService:Create(streak, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
		end
		puff(from, Color3.fromRGB(215, 205, 255), 4, 3, 0.4, 2.5)
		spark(to, Color3.fromRGB(235, 230, 255), 5)
	elseif style == "mirror" then
		for _, pos in ipairs({ from, to }) do
			local pane = fx(Enum.PartType.Block, CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.random() * 6, 0), Vector3.new(5, 8, 0.4), Color3.fromRGB(170, 230, 255), 0.35, 0.6)
			TweenService:Create(pane, TweenInfo.new(0.55), { Transparency = 1 }):Play()
		end
		puff(to, Color3.fromRGB(200, 235, 255), 4, 4, 0.5, 2.5)
	else
		fx(Enum.PartType.Ball, CFrame.new(from), Vector3.new(6, 6, 6), color, 0.4, 0.25)
	end
end

local RED = Color3.fromRGB(255, 60, 60)

-- Los avisos de zona llevan el tag "MobTelegraph" (+ atributos) para que el Auto-farm del jugador los esquive
local function telegraphCircle(center: Vector3, radius: number, y: number, time: number, color: Color3?)
	local p = fx(Enum.PartType.Cylinder, CFrame.new(center.X, y + 0.2, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.2, radius * 2, radius * 2), color or RED, 0.6, time)
	p:SetAttribute("TgKind", "circle")
	p:SetAttribute("TgRadius", radius)
	p:SetAttribute("TgCenter", Vector3.new(center.X, y, center.Z))
	game:GetService("CollectionService"):AddTag(p, "MobTelegraph")
end

local function telegraphBox(origin: Vector3, dir: Vector3, length: number, width: number, y: number, time: number, color: Color3?)
	local mid = origin + dir * (length / 2)
	local p = fx(Enum.PartType.Block, CFrame.lookAt(Vector3.new(mid.X, y + 0.2, mid.Z), Vector3.new(mid.X + dir.X, y + 0.2, mid.Z + dir.Z)), Vector3.new(width, 0.2, length), color or RED, 0.6, time)
	p:SetAttribute("TgKind", "box")
	game:GetService("CollectionService"):AddTag(p, "MobTelegraph")
end

local function inCone(origin: Vector3, forward: Vector3, pos: Vector3, range: number, angle: number): boolean
	local off = flat(pos - origin)
	if off.Magnitude > range then
		return false
	end
	if off.Magnitude < 1.5 then
		return true
	end
	return math.deg(math.acos(math.clamp(off.Unit:Dot(forward), -1, 1))) <= angle / 2
end

local function pause(ctx: Ctx, t: number): boolean
	if t > 0 then
		task.wait(t)
	end
	return ctx.Alive()
end

---------------------------------------------------------------------
-- HABILIDADES
---------------------------------------------------------------------
local Kinds: { [string]: (ctx: Ctx, skill: any, target: Model) -> () } = {}

Kinds.Melee = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	face(ctx, tr.Position)
	if not pause(ctx, skill.Windup or 0.3) then
		return
	end
	local o = ctx.Root.Position
	local f = dirTo(o, tr.Position)
	if skill.Fx == "slash" or skill.Fx == "fireSlash" or skill.Fx == "claw" then
		slashArc(o, f, (skill.Range or 8) + 2, 130, if skill.Fx == "fireSlash" then FX_COLOR.fire else Color3.fromRGB(235, 240, 255), if skill.Fx == "claw" then 3 else 1, groundY(ctx) + 3)
	end
	for _, p in ipairs(livePlayers()) do
		if inCone(o, f, p.Root.Position, (skill.Range or 8) + 2, 130) then
			hit(ctx, p.Model, skill, o)
		end
	end
end

Kinds.Cone = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	local o = ctx.Root.Position
	local f = dirTo(o, tr.Position)
	face(ctx, tr.Position)
	telegraphBox(o, f, skill.Range, math.max(6, skill.Range * 0.8), groundY(ctx), skill.Windup or 0.4, FX_COLOR[skill.Fx or ""])
	if not pause(ctx, skill.Windup or 0.4) then
		return
	end
	local style = skill.Fx
	if style == "slash" or style == "fireSlash" or style == "claw" or style == "tail" then
		slashArc(o, f, skill.Range, skill.Angle or 100, if style == "fireSlash" then FX_COLOR.fire elseif style == "tail" then Color3.fromRGB(230, 120, 255) else Color3.fromRGB(235, 240, 255), if style == "claw" then 3 else 1, groundY(ctx) + 3)
	elseif style == "shock" or style == "sonic" then
		for i = 1, 3 do
			task.delay((i - 1) * 0.08, function()
				ring(o + f * (skill.Range * 0.3 * i), FX_COLOR[style], skill.Range * 0.35, 0.3, o.Y)
			end)
		end
	elseif style == "punch" or style == "kick" then
		spark(o + f * (skill.Range * 0.6) + Vector3.new(0, 1, 0), Color3.new(1, 1, 1), 5)
		ring(o + f * (skill.Range * 0.6), Color3.fromRGB(255, 240, 200), 5, 0.25, o.Y)
	elseif style == "water" then
		puff(o + f * (skill.Range * 0.5), FX_COLOR.water, 6, skill.Range * 0.6, 0.5, 3)
	else
		fx(Enum.PartType.Ball, CFrame.new(o + f * (skill.Range * 0.5)), Vector3.new(skill.Range, 3, skill.Range), ctx.Color, 0.5, 0.2)
	end
	for _, p in ipairs(livePlayers()) do
		if inCone(o, f, p.Root.Position, skill.Range, skill.Angle or 90) then
			hit(ctx, p.Model, skill, o)
		end
	end
end

Kinds.AoE = function(ctx, skill, target)
	local tr = targetRoot(target)
	local center: Vector3
	if skill.Center == "Target" and tr then
		center = tr.Position
	else
		center = ctx.Root.Position
	end
	local y = groundY(ctx)
	local windup = skill.Windup or 0.8
	if tr then
		face(ctx, tr.Position)
	end
	local style: string? = skill.Fx
	local tint = FX_COLOR[style or ""]
	telegraphCircle(center, skill.Radius, y, windup, tint)
	local sky: Part? = nil
	if style == "supernova" then -- bola enorme que crece sobre el objetivo
		sky = fx(Enum.PartType.Ball, CFrame.new(center.X, y + 32, center.Z), Vector3.new(4, 4, 4), tint :: Color3, 0.1, windup + 0.6)
		TweenService:Create(sky :: Part, TweenInfo.new(windup), { Size = Vector3.new(skill.Radius * 1.4, skill.Radius * 1.4, skill.Radius * 1.4) }):Play()
	elseif style == "seal" or style == "trap" then -- papeles / sellos flotando sobre el círculo
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local tag = fx(Enum.PartType.Block, CFrame.new(center.X + math.cos(a) * skill.Radius * 0.7, y + 4, center.Z + math.sin(a) * skill.Radius * 0.7) * CFrame.Angles(0, -a, 0), Vector3.new(0.15, 2.4, 1.2), Color3.fromRGB(245, 240, 220), 0.1, windup + 0.2)
			tag.Material = Enum.Material.SmoothPlastic
		end
	elseif style == "pose" then
		ring(center, tint :: Color3, skill.Radius, windup, y + 0.5)
	end
	if not pause(ctx, windup) then
		return
	end
	if style == "supernova" and sky then
		TweenService:Create(sky, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = Vector3.new(center.X, y + 3, center.Z) }):Play()
		task.wait(0.25)
	end
	if style == "shock" or style == "haki" or style == "pose" then
		for i = 1, 3 do
			task.delay((i - 1) * 0.1, function()
				ring(center, tint :: Color3, skill.Radius * (0.5 + i * 0.25), 0.35, y + 0.5)
			end)
		end
		if style == "haki" then
			spark(center + Vector3.new(0, 4, 0), tint :: Color3, skill.Radius * 0.6)
		end
	elseif style == "poison" or style == "smoke" or style == "mist" then
		puff(center + Vector3.new(0, 2, 0), tint :: Color3, 10, skill.Radius * 1.2, 1.2, 5)
	elseif style == "water" then
		puff(center + Vector3.new(0, 3, 0), tint :: Color3, 10, skill.Radius * 1.2, 0.7, 5)
		ring(center, tint :: Color3, skill.Radius, 0.45, y + 0.5)
	elseif style == "bone" then
		for i = 1, 10 do
			local a = i / 10 * math.pi * 2
			local spike = fx(Enum.PartType.Block, CFrame.new(center.X + math.cos(a) * skill.Radius * 0.7, y + 3, center.Z + math.sin(a) * skill.Radius * 0.7) * CFrame.Angles(0, -a, math.rad(15)), Vector3.new(0.8, 6, 0.8), tint :: Color3, 0, 0.5)
			spike.Material = Enum.Material.SmoothPlastic
			TweenService:Create(spike, TweenInfo.new(0.45), { Transparency = 1 }):Play()
		end
	else
		fx(Enum.PartType.Ball, CFrame.new(center.X, y + 2, center.Z), Vector3.new(skill.Radius * 2, skill.Radius * 2, skill.Radius * 2), tint or ctx.Color, 0.45, 0.3)
		if style == "fire" or style == "bomb" or style == "seal" or style == "supernova" then
			puff(center + Vector3.new(0, 3, 0), Color3.fromRGB(60, 60, 66), 6, skill.Radius, 0.8, 4)
		end
	end
	for _, p in ipairs(livePlayers()) do
		if flat(p.Root.Position - center).Magnitude <= skill.Radius then
			hit(ctx, p.Model, skill, center)
		end
	end
end

Kinds.Line = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	local o = ctx.Root.Position
	local f = dirTo(o, tr.Position)
	face(ctx, tr.Position)
	local windup = skill.Windup or 0.8
	local style: string? = skill.Fx
	local beamColor = FX_COLOR[style or ""] or ctx.Color
	telegraphBox(o, f, skill.Range, skill.Width, groundY(ctx), windup, FX_COLOR[style or ""])
	if style == "ki" or style == "pierce" then -- carga: esfera en la mano que crece
		local charge = fx(Enum.PartType.Ball, CFrame.new(o + f * 3 + Vector3.new(0, 1, 0)), Vector3.new(1, 1, 1), ctx.Color, 0.2, windup + 0.1)
		TweenService:Create(charge, TweenInfo.new(windup), { Size = Vector3.new(math.max(3, skill.Width), math.max(3, skill.Width), math.max(3, skill.Width)) }):Play()
	end
	if not pause(ctx, windup) then
		return
	end
	local mid = o + f * (skill.Range / 2)
	local beamCF = CFrame.lookAt(Vector3.new(mid.X, o.Y, mid.Z), Vector3.new(mid.X + f.X, o.Y, mid.Z + f.Z))
	if style == "slashwave" then
		fx(Enum.PartType.Block, CFrame.new(Vector3.new(mid.X, o.Y, mid.Z)) * beamCF.Rotation, Vector3.new(skill.Width * 2.4, 0.5, skill.Range), Color3.fromRGB(235, 240, 255), 0.2, 0.25)
	else
		local outer = fx(Enum.PartType.Block, beamCF, Vector3.new(skill.Width, skill.Width, skill.Range), beamColor, 0.35, 0.3)
		TweenService:Create(outer, TweenInfo.new(0.28), { Transparency = 1 }):Play()
		if style == "ki" or style == "pierce" or style == "water" or style == "bone" then
			local core = fx(Enum.PartType.Block, beamCF, Vector3.new(skill.Width * 0.45, skill.Width * 0.45, skill.Range), Color3.new(1, 1, 1), 0.1, 0.3)
			TweenService:Create(core, TweenInfo.new(0.28), { Transparency = 1 }):Play()
		end
		spark(o + f * 3 + Vector3.new(0, 1, 0), beamColor, math.max(3, skill.Width))
		if style == "ki" then
			spark(o + f * skill.Range, beamColor, math.max(4, skill.Width * 1.2))
		end
	end
	for _, p in ipairs(livePlayers()) do
		local off = flat(p.Root.Position - o)
		local along = off:Dot(f)
		local side = math.abs(off:Dot(Vector3.new(-f.Z, 0, f.X)))
		if along >= 0 and along <= skill.Range and side <= skill.Width / 2 + 1.5 then
			hit(ctx, p.Model, skill, o)
		end
	end
end

Kinds.Projectile = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	face(ctx, tr.Position)
	if not pause(ctx, skill.Windup or 0.35) then
		return
	end
	local count = skill.Count or 1
	local spread = skill.Spread or 0
	local size = skill.Size or 2
	local speed = skill.Speed or 80
	local burst = skill.Burst or 0
	local base = dirTo(ctx.Root.Position, tr.Position)
	for i = 1, count do
		if not ctx.Alive() then
			return
		end
		if burst > 0 then
			base = dirTo(ctx.Root.Position, tr.Position)
		end
		local angle = if count > 1 and spread > 0 then math.rad(-spread / 2 + spread * (i - 1) / (count - 1)) else 0
		local d = CFrame.Angles(0, angle, 0):VectorToWorldSpace(base)
		local pos = ctx.Root.Position + d * 3 + Vector3.new(0, 1, 0)
		local update, destroyOrb, orb = makeProjectile(skill.Fx, pos, d, size, ctx.Color, skill.Range / speed + 1)
		update(pos, d, 0)
		local travelled = 0
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function(dt)
			if not orb or not orb.Parent then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local step = speed * dt
			pos += d * step
			travelled += step
			update(pos, d, dt)
			if blockedAt(pos) then
				impactFx(skill.Fx, pos, 0, ctx.Color)
				destroyOrb()
				if conn then
					conn:Disconnect()
				end
				return
			end
			local exploded = false
			for _, p in ipairs(livePlayers()) do
				if (p.Root.Position - pos).Magnitude <= size / 2 + 2.5 then
					if skill.Radius then
						for _, q in ipairs(livePlayers()) do
							if (q.Root.Position - pos).Magnitude <= skill.Radius then
								hit(ctx, q.Model, skill, pos)
							end
						end
					else
						hit(ctx, p.Model, skill, pos)
					end
					exploded = true
					break
				end
			end
			if exploded or travelled >= skill.Range then
				if exploded then
					impactFx(skill.Fx, pos, skill.Radius, ctx.Color)
				end
				destroyOrb()
				if conn then
					conn:Disconnect()
				end
			end
		end)
		if burst > 0 then
			task.wait(burst)
		end
	end
end

Kinds.Dash = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	face(ctx, tr.Position)
	if not pause(ctx, skill.Windup or 0.35) then
		return
	end
	local hits = skill.Hits or 1
	local o = ctx.Root.Position
	local total = math.max(0, math.min(skill.Range, flat(tr.Position - o).Magnitude - 3))
	local d = dirTo(o, tr.Position)
	for i = 1, hits do
		if not ctx.Alive() then
			return
		end
		local cur = ctx.Root.Position
		local nextPos = cur + d * (total / hits)
		if skill.Fx == "afterimage" or skill.Fx == "rush" or skill.Fx == "claw" then
			moveFx(if skill.Fx == "shunpo" then "shunpo" elseif skill.Fx == "rush" then "geppo" else "flash", cur, nextPos, ctx.Color)
		end
		ctx.Root.CFrame = CFrame.lookAt(nextPos, nextPos + d)
		task.wait(0.14)
		for _, p in ipairs(livePlayers()) do
			if flat(p.Root.Position - ctx.Root.Position).Magnitude <= 7 then
				hit(ctx, p.Model, skill, ctx.Root.Position)
				spark(p.Root.Position + Vector3.new(0, 1, 0), Color3.new(1, 1, 1), 3)
				if skill.Fx == "claw" then
					slashArc(ctx.Root.Position, d, 7, 90, Color3.fromRGB(235, 240, 255), 3, groundY(ctx) + 3)
				end
			end
		end
	end
end

Kinds.Teleport = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	local from = ctx.Root.Position
	local dest: Vector3
	if skill.Behind then
		dest = tr.Position - tr.CFrame.LookVector * 4
	else
		local a = math.random() * math.pi * 2
		dest = tr.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * 18
	end
	ctx.Root.CFrame = CFrame.lookAt(Vector3.new(dest.X, tr.Position.Y, dest.Z), tr.Position)
	moveFx(skill.Fx, from, ctx.Root.Position, ctx.Color)
end

Kinds.Swap = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr then
		return
	end
	local a, b = ctx.Root.CFrame, tr.CFrame
	fx(Enum.PartType.Ball, a, Vector3.new(6, 6, 6), ctx.Color, 0.4, 0.3)
	ctx.Root.CFrame = b
	tr.CFrame = a
end

Kinds.Summon = function(ctx, skill, _target)
	local o = ctx.Root.Position
	if skill.Fx == "bunshin" then -- Kage Bunshin: nube de humo
		puff(o, Color3.fromRGB(225, 225, 230), 8, 8, 0.7, 4)
	elseif skill.Fx == "pose" then
		ring(o, FX_COLOR.pose, 14, 0.5, o.Y - 2.5)
	else
		ring(o, ctx.Color, 10, 0.5, o.Y - 2.5)
	end
	ctx.Summon(skill.SummonId, skill.Count or 2)
end

Kinds.Drain = function(ctx, skill, target)
	local tr = targetRoot(target)
	if not tr or (tr.Position - ctx.Root.Position).Magnitude > skill.Range + 3 then
		return
	end
	face(ctx, tr.Position)
	if not pause(ctx, skill.Windup or 0.5) then
		return
	end
	local dealt = DamageService.Deal(ctx.Model, target, skill.Mult or 1, nil)
	if dealt > 0 then
		ctx.Humanoid.Health = math.min(ctx.Humanoid.MaxHealth, ctx.Humanoid.Health + ctx.Humanoid.MaxHealth * (skill.HealPct or 0.05))
	end
end

Kinds.Invisible = function(ctx, skill, _target)
	if skill.Fx == "mist" then
		puff(ctx.Root.Position, FX_COLOR.mist, 14, 16, (skill.Duration or 2) + 0.5, 7)
	else
		puff(ctx.Root.Position, Color3.fromRGB(40, 40, 50), 4, 4, 0.5, 3)
	end
	local originals: { [BasePart]: number } = {}
	for _, d in ipairs(ctx.Model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			originals[d] = d.Transparency
			d.Transparency = 0.92
		end
	end
	ctx.Model:SetAttribute("Hidden", true)
	task.wait(skill.Duration or 2)
	ctx.Model:SetAttribute("Hidden", false)
	for p, t in pairs(originals) do
		if p.Parent then
			p.Transparency = t
		end
	end
end

Kinds.Barrier = function(ctx, skill, _target)
	local points = ctx.Humanoid.MaxHealth * (skill.Pct or 0.15)
	local token = os.clock()
	ctx.Model:SetAttribute("ShieldPoints", points)
	ctx.Model:SetAttribute("ShieldToken", token)
	fx(Enum.PartType.Ball, ctx.Root.CFrame, Vector3.new(9, 9, 9), ctx.Color, 0.6, skill.Duration or 5)
	task.delay(skill.Duration or 5, function()
		if ctx.Model:GetAttribute("ShieldToken") == token then
			ctx.Model:SetAttribute("ShieldPoints", 0)
		end
	end)
end

Kinds.Pull = function(ctx, skill, _target)
	local o = ctx.Root.Position
	local windup = skill.Windup or 0.9
	telegraphCircle(o, skill.Radius, groundY(ctx), windup, FX_COLOR[skill.Fx or ""])
	local hole: Part? = nil
	if skill.Fx == "blackhole" or skill.Fx == "shock" then -- esfera oscura que se forma sobre el atacante
		hole = fx(Enum.PartType.Ball, CFrame.new(o + Vector3.new(0, 8, 0)), Vector3.new(1, 1, 1), FX_COLOR[skill.Fx] or ctx.Color, 0.05, windup + 0.5)
		TweenService:Create(hole :: Part, TweenInfo.new(windup), { Size = Vector3.new(9, 9, 9) }):Play()
	end
	if not pause(ctx, windup) then
		return
	end
	ring(o, FX_COLOR[skill.Fx or ""] or ctx.Color, skill.Radius, 0.5, groundY(ctx) + 0.5)
	for _, p in ipairs(livePlayers()) do
		local off = flat(o - p.Root.Position)
		if off.Magnitude <= skill.Radius and off.Magnitude > 1 then
			p.Root.AssemblyLinearVelocity = off.Unit * (skill.Force or 60) + Vector3.new(0, 10, 0)
		end
	end
end

Kinds.Buff = function(ctx, skill, _target)
	local o = ctx.Root.Position
	for _, m in ipairs(CollectionService:GetTagged("Mob")) do
		local r = m:IsA("Model") and m:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and (r.Position - o).Magnitude <= skill.Radius then
			m:SetAttribute("DmgBuff", skill.DmgMult or 1.2)
			task.delay(skill.Duration or 8, function()
				if m.Parent then
					m:SetAttribute("DmgBuff", m:GetAttribute("BaseBuff") or 1)
				end
			end)
		end
	end
	fx(Enum.PartType.Ball, CFrame.new(o), Vector3.new(skill.Radius, skill.Radius, skill.Radius), Color3.fromRGB(255, 200, 80), 0.7, 0.5)
end

-- Esquiva de pasiva "Dodge": kawarimi (Shinobi: tronco + humo), geppo (Pirata), imagen residual (Saiyan)
function MobSkills.DodgeFx(model: Model, from: Vector3, to: Vector3, faction: string)
	if faction == "Shinobi" then
		local log = fx(Enum.PartType.Cylinder, CFrame.new(from) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(5, 2.2, 2.2), Color3.fromRGB(120, 80, 45), 0, 1.2)
		log.Material = Enum.Material.Wood
		TweenService:Create(log, TweenInfo.new(1), { Transparency = 1 }):Play()
		puff(from, Color3.fromRGB(225, 225, 230), 5, 4, 0.6, 3)
		leaves(to, 5)
	elseif faction == "Pirate" then
		moveFx("geppo", from, to, Color3.new(1, 1, 1))
	elseif faction == "Shinigami" then
		moveFx("shunpo", from, to, Color3.fromRGB(190, 170, 255))
	else
		moveFx("flash", from, to, Color3.fromRGB(255, 230, 120))
	end
end

-- Rango "efectivo" para que MobBrain decida cuándo usarla
function MobSkills.EffectiveRange(skill: any): number
	local k = skill.Kind
	if k == "AoE" then
		return if skill.Center == "Target" then skill.Range or 40 else (skill.Radius or 10) * 0.9
	elseif k == "Pull" then
		return (skill.Radius or 30) * 0.8
	elseif k == "Buff" or k == "Summon" or k == "Barrier" or k == "Invisible" then
		return 200
	elseif k == "Teleport" then
		return (skill.Range or 40)
	end
	return skill.Range or 10
end

-- Animación de ataque según el tipo de habilidad (la dibuja CharacterAnimClient)
local ANIM_BY_KIND: { [string]: string } = {
	Cone = "Slam", Line = "Cast", Projectile = "Cast", Drain = "Cast", Pull = "Cast", Swap = "Cast", Dash = "Stab",
	Buff = "Power", Summon = "Power", Barrier = "Power", Invisible = "Power",
}

function MobSkills.Run(ctx: Ctx, skill: any, target: Model)
	local fn = Kinds[skill.Kind]
	if fn then
		local style = ANIM_BY_KIND[skill.Kind]
		if skill.Kind == "Melee" then
			style = if ctx.Model:FindFirstChild("WeaponBlade") then "Slash" else "Punch"
		elseif skill.Kind == "AoE" then
			style = if skill.Center == "Target" then "Cast" else "Slam"
		end
		if skill.Fx and FX_ANIM[skill.Fx] then
			style = FX_ANIM[skill.Fx]
		end
		if style then
			local windup = skill.Windup or 0.3
			AttackAnimator.Play(ctx.Model, style, math.min(2.5, windup + 0.45), math.clamp(windup / (windup + 0.45), 0.2, 0.85))
		end
		fn(ctx, skill, target)
	else
		warn("[MobSkills] Kind desconocido: " .. tostring(skill.Kind))
	end
end

return MobSkills
