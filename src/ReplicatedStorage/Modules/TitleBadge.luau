--!strict
--[[
    TitleBadge (ModuleScript) -> ReplicatedStorage.Modules.TitleBadge
    Dibuja la PLACA de un título: MARCO (tu marco de perfil equipado) + FONDO ANIMADO (según el título) + ICONO + NOMBRE con degradado de rareza.
    Solo cliente (usa TweenService). Lo usan TitleTagClient (sobre la cabeza) y TitleClient (ventana).
      TitleBadge.Build(parent, def, { Width, Height, Frame = "Bronce"|"Plata"|"Oro"|"Cristal"|"Imperial"|nil, Static = true|nil, Position, AnchorPoint }) -> Frame
      TitleBadge.SizeFor(def, height) -> ancho recomendado según el largo del nombre.
    Fondos (def.Fx): simple · rayos · llamas · aurora · estrellas · petalos · eclipse · cristal · oro · ki · hojas · olas · niebla.
    Static = true: sin animaciones (títulos bloqueados en la ventana).
]]
local TweenService = game:GetService("TweenService")

local TitleBadge = {}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local RARITY_TEXT: { [string]: { Color3 } } = {
	Comun = { c(255, 255, 255), c(174, 180, 200) },
	Raro = { c(214, 239, 255), c(90, 160, 255) },
	Epico = { c(243, 212, 255), c(161, 92, 255) },
	Legendario = { c(255, 240, 168), c(255, 154, 40) },
	Mitico = { c(255, 208, 222), c(255, 74, 120) },
}
local RARITY_NAME: { [string]: string } = { Comun = "COMÚN", Raro = "RARO", Epico = "ÉPICO", Legendario = "LEGENDARIO", Mitico = "MÍTICO" }

-- marcos: gradiente de 3 colores + brillo
local FRAMES: { [string]: { Color3 } } = {
	Bronce = { c(240, 178, 122), c(168, 100, 42), c(229, 160, 104) },
	Plata = { c(255, 255, 255), c(154, 164, 184), c(230, 235, 245) },
	Oro = { c(255, 243, 176), c(224, 165, 22), c(255, 226, 122) },
	Cristal = { c(232, 251, 255), c(88, 208, 242), c(201, 244, 255) },
	Imperial = { c(245, 208, 255), c(155, 63, 224), c(255, 217, 120) },
}

local LINEAR = Enum.EasingStyle.Linear
local SINE = Enum.EasingStyle.Sine

-- tween en bucle (reverse = ida y vuelta) con retraso opcional
local function loop(inst: Instance, seconds: number, props: { [string]: any }, reverse: boolean?, delay: number?, style: Enum.EasingStyle?)
	local info = TweenInfo.new(seconds, style or SINE, Enum.EasingDirection.InOut, -1, reverse == true)
	local tw = TweenService:Create(inst, info, props)
	if delay and delay > 0 then
		task.delay(delay, function()
			if inst.Parent then
				tw:Play()
			end
		end)
	else
		tw:Play()
	end
end

local function box(parent: Instance, size: UDim2, pos: UDim2, color: Color3, transparency: number?, round: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.Size = size
	f.Position = pos
	if round then
		local u = Instance.new("UICorner")
		u.CornerRadius = UDim.new(round, 0)
		u.Parent = f
	end
	f.Parent = parent
	return f
end

local function gradient(parent: Instance, a: Color3, b: Color3, rotation: number?, mid: Color3?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = if mid then ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.5, mid), ColorSequenceKeypoint.new(1, b) }) else ColorSequence.new(a, b)
	g.Rotation = rotation or 0
	g.Parent = parent
	return g
end

-- degradado de transparencia horizontal (centro visible, bordes que se desvanecen): da el efecto "difuminado"
local function softEdges(f: Instance)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
end

local function alive(inst: Instance): boolean
	return inst:IsDescendantOf(game)
end

---------------------------------------------------------------------
-- Fondos
---------------------------------------------------------------------
type Ctx = { Bg: Frame, Fx: Frame, W: number, H: number, K: number, Static: boolean }

local function rnd(seed: number): number -- pseudoaleatorio estable 0..1
	return (math.sin(seed * 12.9898) * 43758.5453) % 1
end

local FX: { [string]: (Ctx) -> () } = {}

FX.simple = function(x: Ctx)
	gradient(x.Bg, c(34, 38, 58), c(18, 20, 34), 90)
end

FX.rayos = function(x: Ctx)
	gradient(x.Bg, c(44, 42, 120), c(13, 11, 46), 0)
	local glow = box(x.Fx, UDim2.fromScale(0.7, 1), UDim2.fromScale(0.15, 0), c(140, 170, 255), 0.75, 0.5)
	softEdges(glow)
	if x.Static then
		return
	end
	loop(glow, 0.6, { BackgroundTransparency = 0.35 }, true)
	for i, px in ipairs({ 0.16, 0.5, 0.82 }) do
		local bolt = box(x.Fx, UDim2.fromOffset(math.max(2, 3 * x.K), x.H * 1.2), UDim2.new(px, 0, 0.5, 0), c(207, 230, 255), 1)
		bolt.AnchorPoint = Vector2.new(0.5, 0.5)
		bolt.Rotation = if i % 2 == 0 then 14 else -12
		local st = Instance.new("UIStroke")
		st.Color = c(127, 178, 255)
		st.Thickness = 2
		st.Transparency = 1
		st.Parent = bolt
		task.spawn(function()
			task.wait(i * 0.35)
			while alive(bolt) do
				task.wait(0.9 + rnd(i + os.clock()) * 1.4)
				for _, t in ipairs({ 0, 0.8, 0, 0.6, 0, 1 }) do
					if not alive(bolt) then
						return
					end
					bolt.BackgroundTransparency = t
					st.Transparency = math.min(1, t + 0.1)
					task.wait(0.05)
				end
			end
		end)
	end
end

FX.llamas = function(x: Ctx)
	gradient(x.Bg, c(42, 10, 6), c(122, 35, 8), 90)
	if x.Static then
		return
	end
	local n = math.max(4, math.floor(x.W / (46 * x.K)))
	for i = 1, n do
		local fh = (50 + rnd(i) * 26) * x.K
		local f = box(x.Fx, UDim2.fromOffset(40 * x.K, fh), UDim2.new((i - 0.5) / n, 0, 1, 6 * x.K), c(255, 150, 40), 0.1, 0.5)
		f.AnchorPoint = Vector2.new(0.5, 1)
		gradient(f, c(255, 242, 160), c(232, 69, 10), 90, c(255, 176, 46))
		loop(f, 0.45 + rnd(i + 3) * 0.4, { Size = UDim2.fromOffset(34 * x.K, fh * 1.25) }, true, rnd(i + 7) * 0.5)
	end
	for i = 1, 4 do
		local e = box(x.Fx, UDim2.fromOffset(3 * x.K, 3 * x.K), UDim2.new(rnd(i + 11), 0, 1, 0), c(255, 211, 106), 0, 1)
		loop(e, 1.6 + rnd(i) * 1.2, { Position = UDim2.new(rnd(i + 11) + 0.04, 0, 0, -4), BackgroundTransparency = 1 }, false, rnd(i + 2) * 1.5, LINEAR)
	end
end

FX.aurora = function(x: Ctx)
	gradient(x.Bg, c(10, 31, 58), c(11, 45, 77), 90)
	if x.Static then
		return
	end
	local cols = { c(62, 230, 176), c(90, 139, 255), c(183, 107, 255) }
	for i, col in ipairs(cols) do
		local b = box(x.Fx, UDim2.fromOffset(x.W * 0.7, x.H * 0.9), UDim2.new(-0.2 + i * 0.1, 0, 0.05 * i, 0), col, 0.35, 0.5)
		softEdges(b)
		loop(b, 3.5 + i, { Position = UDim2.new(0.45 - i * 0.08, 0, 0.05 * i - 0.1, 0) }, true, i * 0.4)
	end
end

FX.estrellas = function(x: Ctx)
	gradient(x.Bg, c(29, 33, 96), c(7, 10, 36), 20)
	if x.Static then
		return
	end
	for i = 1, 9 do
		local s = (6 + rnd(i) * 6) * x.K
		local d = box(x.Fx, UDim2.fromOffset(s, s), UDim2.new(0.05 + rnd(i + 1) * 0.9, 0, 0.12 + rnd(i + 5) * 0.76, 0), Color3.new(1, 1, 1), 0.85)
		d.Rotation = 45
		loop(d, 0.8 + rnd(i + 2) * 0.9, { BackgroundTransparency = 0, Size = UDim2.fromOffset(s * 1.5, s * 1.5) }, true, rnd(i + 9) * 1.2)
	end
end

FX.petalos = function(x: Ctx)
	gradient(x.Bg, c(74, 22, 52), c(138, 44, 94), 20)
	if x.Static then
		return
	end
	for i = 1, 8 do
		local p = box(x.Fx, UDim2.fromOffset(11 * x.K, 7 * x.K), UDim2.new(rnd(i) * 0.95, 0, -0.2, 0), c(255, 160, 200), 0.1, 0.5)
		gradient(p, c(255, 217, 230), c(255, 127, 174), 45)
		loop(p, 2.6 + rnd(i + 4) * 1.6, { Position = UDim2.new(rnd(i) * 0.95 + 0.06, 0, 1.2, 0), Rotation = 360 }, false, rnd(i + 6) * 2.5, LINEAR)
	end
end

FX.eclipse = function(x: Ctx)
	gradient(x.Bg, c(20, 16, 24), c(5, 4, 8), 0)
	local d = x.H * 1.5
	local corona = box(x.Fx, UDim2.fromOffset(d, d), UDim2.new(0, x.H * 0.5, 0.5, 0), c(255, 140, 60), 0.35, 1)
	corona.AnchorPoint = Vector2.new(0.5, 0.5)
	gradient(corona, c(255, 210, 120), c(255, 90, 30), 0, c(255, 150, 50))
	local moon = box(x.Fx, UDim2.fromOffset(x.H * 0.78, x.H * 0.78), UDim2.new(0, x.H * 0.5, 0.5, 0), c(5, 4, 8), 0, 1)
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	local st = Instance.new("UIStroke")
	st.Color = c(255, 190, 100)
	st.Thickness = 2
	st.Parent = moon
	if not x.Static then
		loop(corona, 6, { Rotation = 360 }, false, 0, LINEAR)
		loop(corona, 1.4, { BackgroundTransparency = 0.6, Size = UDim2.fromOffset(d * 1.12, d * 1.12) }, true)
	end
end

FX.cristal = function(x: Ctx)
	gradient(x.Bg, c(11, 42, 69), c(42, 47, 120), 20, c(18, 74, 110))
	for i = 1, 4 do
		local s = box(x.Fx, UDim2.fromOffset((40 + rnd(i) * 40) * x.K, x.H * 1.4), UDim2.new(0.08 + i * 0.22, 0, 0.5, 0), Color3.new(1, 1, 1), 0.86)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Rotation = 18
	end
	if x.Static then
		return
	end
	for i = 1, 4 do
		local s = (8 + rnd(i + 3) * 4) * x.K
		local d = box(x.Fx, UDim2.fromOffset(s, s), UDim2.new(0.08 + rnd(i + 8) * 0.84, 0, 0.15 + rnd(i + 2) * 0.7, 0), Color3.new(1, 1, 1), 0.9)
		d.Rotation = 45
		loop(d, 0.7 + rnd(i) * 0.6, { BackgroundTransparency = 0, Size = UDim2.fromOffset(s * 1.6, s * 1.6) }, true, rnd(i + 1) * 1.4)
	end
end

FX.oro = function(x: Ctx)
	gradient(x.Bg, c(106, 67, 8), c(42, 24, 2), 0)
	local g = Instance.new("Frame")
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromOffset(x.H * 4, x.H * 4)
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Parent = x.Fx
	for i = 0, 7 do
		local r = box(g, UDim2.fromOffset(x.H * 0.34, x.H * 4), UDim2.fromScale(0.5, 0.5), c(255, 226, 120), 0.82)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Rotation = i * 22.5
	end
	if not x.Static then
		loop(g, 20, { Rotation = 360 }, false, 0, LINEAR)
	end
end

FX.ki = function(x: Ctx)
	gradient(x.Bg, c(14, 16, 48), c(36, 26, 80), 90)
	local aura = box(x.Fx, UDim2.fromOffset(x.H * 2.2, x.H * 1.5), UDim2.new(0, 0, 1, x.H * 0.3), c(255, 170, 40), 0.45, 0.5)
	aura.AnchorPoint = Vector2.new(0.3, 1)
	gradient(aura, c(255, 226, 120), c(255, 110, 20), 90)
	if x.Static then
		return
	end
	loop(aura, 0.6, { BackgroundTransparency = 0.7, Size = UDim2.fromOffset(x.H * 2.6, x.H * 1.8) }, true)
	for i = 1, 5 do
		local s = box(x.Fx, UDim2.fromOffset(math.max(2, 3 * x.K), 38 * x.K), UDim2.new(0.12 + i * 0.16, 0, 1, 0), c(255, 226, 122), 0.1, 0.5)
		loop(s, 1.1 + rnd(i) * 0.7, { Position = UDim2.new(0.12 + i * 0.16, 0, -0.5, 0), BackgroundTransparency = 1 }, false, rnd(i + 3) * 1.2, LINEAR)
	end
end

FX.hojas = function(x: Ctx)
	gradient(x.Bg, c(15, 42, 28), c(29, 74, 44), 20)
	if x.Static then
		return
	end
	for i = 1, 5 do
		local l = box(x.Fx, UDim2.fromOffset(15 * x.K, 8 * x.K), UDim2.new(-0.1, 0, 0.15 + rnd(i) * 0.65, 0), c(130, 210, 100), 0.05, 0.5)
		gradient(l, c(182, 240, 138), c(63, 154, 58), 45)
		loop(l, 2.4 + rnd(i + 2) * 1.6, { Position = UDim2.new(1.1, 0, 0.15 + rnd(i + 5) * 0.65, 0), Rotation = 420 }, false, rnd(i + 8) * 2.5, LINEAR)
	end
end

FX.olas = function(x: Ctx)
	gradient(x.Bg, c(10, 37, 64), c(13, 59, 102), 90)
	local function row(color: Color3, y: number, seconds: number, reverse: boolean)
		local d = x.H * 0.5
		local n = math.ceil(x.W * 2 / (d * 0.7)) + 2
		local g = Instance.new("Frame")
		g.BackgroundTransparency = 1
		g.Size = UDim2.fromOffset(x.W * 2, d)
		g.Position = UDim2.new(0, 0, 1, y)
		g.Parent = x.Fx
		for i = 0, n do
			box(g, UDim2.fromOffset(d, d), UDim2.fromOffset(i * d * 0.7, 0), color, 0.1, 1)
		end
		if not x.Static then
			if reverse then
				g.Position = UDim2.new(0, -x.W, 1, y)
				loop(g, seconds, { Position = UDim2.new(0, 0, 1, y) }, false, 0, LINEAR)
			else
				loop(g, seconds, { Position = UDim2.new(0, -x.W, 1, y) }, false, 0, LINEAR)
			end
		end
	end
	row(c(29, 106, 168), -x.H * 0.22, 9, true)
	row(c(46, 143, 208), -x.H * 0.1, 6, false)
end

FX.niebla = function(x: Ctx)
	gradient(x.Bg, c(10, 7, 22), c(26, 16, 48), 20)
	local cres = box(x.Fx, UDim2.fromOffset(x.H * 0.42, x.H * 0.42), UDim2.new(1, -x.H * 0.55, 0.28, 0), c(232, 224, 255), 0, 1)
	local cut = box(x.Fx, UDim2.fromOffset(x.H * 0.4, x.H * 0.4), UDim2.new(1, -x.H * 0.4, 0.24, 0), c(18, 12, 36), 0, 1)
	cut.ZIndex = 2
	if x.Static then
		return
	end
	loop(cres, 1.6, { BackgroundTransparency = 0.35 }, true)
	for i = 1, 3 do
		local m = box(x.Fx, UDim2.fromOffset(x.W * 0.6, x.H * 0.8), UDim2.new(-0.2 + i * 0.12, 0, 0.1 * i - 0.1, 0), c(150, 120, 235), 0.5, 0.5)
		softEdges(m)
		loop(m, 4 + i * 1.2, { Position = UDim2.new(0.5 - i * 0.1, 0, 0.1 * i - 0.2, 0) }, true, i * 0.5)
	end
end

---------------------------------------------------------------------
-- API
---------------------------------------------------------------------
function TitleBadge.SizeFor(def: any, height: number): number
	local n = utf8.len(def.Name) or #def.Name
	return math.floor(height * 1.5 + n * height * 0.3)
end

function TitleBadge.Build(parent: Instance, def: any, o: { Width: number, Height: number, Frame: string?, Static: boolean?, Position: UDim2?, AnchorPoint: Vector2? }): Frame
	local W, H = o.Width, o.Height
	local K = H / 96
	local pad = math.max(3, math.floor(H * 0.065))
	local frameKey = if o.Frame and FRAMES[o.Frame] then o.Frame else nil

	local outer = Instance.new("Frame")
	outer.Name = "TituloPlaca"
	outer.Size = UDim2.fromOffset(W, H)
	outer.BackgroundColor3 = c(58, 63, 85)
	outer.BorderSizePixel = 0
	if o.Position then
		outer.Position = o.Position
	end
	if o.AnchorPoint then
		outer.AnchorPoint = o.AnchorPoint
	end
	local oc = Instance.new("UICorner")
	oc.CornerRadius = UDim.new(0, math.floor(H * 0.18))
	oc.Parent = outer
	if frameKey then
		local cols = FRAMES[frameKey]
		gradient(outer, cols[1], cols[3], 45, cols[2])
		outer.BackgroundColor3 = Color3.new(1, 1, 1)
		if frameKey == "Imperial" and not o.Static then
			local st = Instance.new("UIStroke")
			st.Color = c(200, 120, 255)
			st.Thickness = math.max(1.5, 2 * K)
			st.Transparency = 0.4
			st.Parent = outer
			loop(st, 1.2, { Transparency = 0.05, Thickness = math.max(2.5, 4 * K) }, true)
		elseif frameKey == "Oro" and not o.Static then
			local st = Instance.new("UIStroke")
			st.Color = c(255, 210, 90)
			st.Thickness = math.max(1, 1.5 * K)
			st.Transparency = 0.6
			st.Parent = outer
			loop(st, 1.6, { Transparency = 0.2 }, true)
		end
		-- tachuelas en las esquinas
		for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
			local s = math.max(5, 8 * K)
			local stud = box(outer, UDim2.fromOffset(s, s), UDim2.new(corner[1], 0, corner[2], 0), c(232, 195, 90), 0, 1)
			stud.AnchorPoint = Vector2.new(0.5, 0.5)
			stud.ZIndex = 6
			gradient(stud, c(255, 255, 255), c(122, 84, 16), 45)
		end
		if frameKey == "Cristal" and not o.Static then
			local sw = box(outer, UDim2.fromOffset(H * 0.35, H * 1.6), UDim2.new(-0.2, 0, 0.5, 0), Color3.new(1, 1, 1), 0.55)
			sw.AnchorPoint = Vector2.new(0.5, 0.5)
			sw.Rotation = 20
			sw.ZIndex = 6
			softEdges(sw)
			loop(sw, 2.6, { Position = UDim2.new(1.2, 0, 0.5, 0) }, false, 0, LINEAR)
		end
	end

	local bg = Instance.new("Frame")
	bg.Name = "Fondo"
	bg.Size = UDim2.new(1, -pad * 2, 1, -pad * 2)
	bg.Position = UDim2.fromOffset(pad, pad)
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.BorderSizePixel = 0
	bg.ClipsDescendants = true
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, math.max(3, math.floor(H * 0.14)))
	bc.Parent = bg
	bg.Parent = outer

	local fx = Instance.new("Frame")
	fx.Name = "Efectos"
	fx.BackgroundTransparency = 1
	fx.Size = UDim2.fromScale(1, 1)
	fx.Parent = bg

	local builder = FX[if typeof(def.Fx) == "string" and FX[def.Fx] then def.Fx else "simple"]
	local ctx: Ctx = { Bg = bg, Fx = fx, W = W - pad * 2, H = H - pad * 2, K = K, Static = o.Static == true }
	builder(ctx)

	-- brillo que cruza
	if not o.Static then
		local shine = box(bg, UDim2.fromOffset(H * 0.3, H * 1.8), UDim2.new(-0.3, 0, 0.5, 0), Color3.new(1, 1, 1), 0.88)
		shine.AnchorPoint = Vector2.new(0.5, 0.5)
		shine.Rotation = 20
		shine.ZIndex = 5
		softEdges(shine)
		loop(shine, 3.6, { Position = UDim2.new(1.3, 0, 0.5, 0) }, false, 0, LINEAR)
	end

	-- icono + nombre
	local isEclipse = def.Fx == "eclipse"
	local iconW = if isEclipse then H * 0.95 else H * 0.58
	local icon = Instance.new("TextLabel")
	icon.Name = "Icono"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(iconW, H - pad * 2)
	icon.Position = UDim2.fromOffset(H * 0.12, 0)
	icon.Font = Enum.Font.GothamBold
	icon.TextScaled = true
	icon.Text = if isEclipse then "" else (def.Icon or "★")
	icon.TextColor3 = Color3.new(1, 1, 1)
	icon.ZIndex = 4
	local ic = Instance.new("UITextSizeConstraint")
	ic.MaxTextSize = math.floor(H * 0.46)
	ic.Parent = icon
	icon.Parent = bg

	local textLeft = H * 0.12 + iconW + H * 0.08
	local cols = RARITY_TEXT[def.Rarity] or RARITY_TEXT.Comun
	local name = Instance.new("TextLabel")
	name.Name = "Nombre"
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, textLeft, 0.1, 0)
	name.Size = UDim2.new(1, -textLeft - H * 0.12, 0.56, 0)
	name.Font = Enum.Font.GothamBlack
	name.TextScaled = true
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = def.Name
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextStrokeColor3 = c(8, 8, 16)
	name.TextStrokeTransparency = 0.35
	name.ZIndex = 4
	local nc = Instance.new("UITextSizeConstraint")
	nc.MaxTextSize = math.floor(H * 0.34)
	nc.MinTextSize = 6
	nc.Parent = name
	gradient(name, cols[1], cols[2], 90)
	name.Parent = bg

	if H >= 40 then
		local rar = Instance.new("TextLabel")
		rar.Name = "Rareza"
		rar.BackgroundTransparency = 1
		rar.Position = UDim2.new(0, textLeft, 0.68, 0)
		rar.Size = UDim2.new(1, -textLeft - H * 0.12, 0.2, 0)
		rar.Font = Enum.Font.GothamBold
		rar.TextScaled = true
		rar.TextXAlignment = Enum.TextXAlignment.Left
		rar.Text = RARITY_NAME[def.Rarity] or ""
		rar.TextColor3 = cols[2]
		rar.TextStrokeColor3 = c(8, 8, 16)
		rar.TextStrokeTransparency = 0.5
		rar.ZIndex = 4
		local rc = Instance.new("UITextSizeConstraint")
		rc.MaxTextSize = math.floor(H * 0.14)
		rc.MinTextSize = 5
		rc.Parent = rar
		rar.Parent = bg
	end

	outer.Parent = parent
	return outer
end

return TitleBadge
