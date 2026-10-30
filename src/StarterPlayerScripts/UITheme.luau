--!strict
--[[
    UITheme (ModuleScript) -> StarterPlayer > StarterPlayerScripts > UITheme
    Colores, bordes y recurso (Ki / Chakra / Haki) por facción + helpers para crear UI con el mismo estilo.
    Todos los paneles (HUD, mochila, perfil) lo usan, así cambiar el look de una facción es tocar este archivo.
]]
local UITheme = {}

-- Imágenes opcionales (UIAssets): si pegaste los IDs, los marcos usan los dibujos de las maquetas; si no, se usa el código.
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

export type Theme = {
	Faction: string,
	Primary: Color3,
	Secondary: Color3,
	Dark: Color3,
	Resource: string, -- nombre de la barra de energía
	ResourceColor: Color3,
	Emblem: string,
}

UITheme.Themes = {
	Saiyan = {
		Faction = "Imperio Saiyan", Primary = Color3.fromRGB(255, 190, 70), Secondary = Color3.fromRGB(220, 90, 30),
		Dark = Color3.fromRGB(34, 22, 14), Resource = "KI", ResourceColor = Color3.fromRGB(80, 190, 255), Emblem = "龍",
	},
	Shinobi = {
		Faction = "Alianza Shinobi", Primary = Color3.fromRGB(130, 220, 120), Secondary = Color3.fromRGB(40, 130, 80),
		Dark = Color3.fromRGB(16, 28, 20), Resource = "CHAKRA", ResourceColor = Color3.fromRGB(90, 140, 255), Emblem = "忍",
	},
	Pirate = {
		Faction = "Flota Pirata", Primary = Color3.fromRGB(110, 180, 245), Secondary = Color3.fromRGB(200, 60, 60),
		Dark = Color3.fromRGB(14, 22, 36), Resource = "HAKI", ResourceColor = Color3.fromRGB(190, 80, 210), Emblem = "海",
	},
	Shinigami = {
		Faction = "Corte Shinigami", Primary = Color3.fromRGB(165, 140, 255), Secondary = Color3.fromRGB(235, 235, 245),
		Dark = Color3.fromRGB(20, 16, 34), Resource = "REIATSU", ResourceColor = Color3.fromRGB(150, 230, 255), Emblem = "死",
	},
} :: { [string]: Theme }

local DEFAULT = "Saiyan"

function UITheme.For(faction: any): Theme
	local key = if typeof(faction) == "string" then faction else DEFAULT
	return UITheme.Themes[key] or UITheme.Themes[DEFAULT]
end

UITheme.Font = Enum.Font.GothamBold

---------------------------------------------------------------------
-- EFECTOS POR FACCIÓN (todas las ventanas usan Frame/Border, así que se aplican solos)
--   · el borde tiene un degradado "conic" de la facción que gira sin parar
--   · el borde respira (grosor y brillo)
--   · las ventanas grandes sueltan partículas: chispas de ki (Saiyan), hojas (Shinobi), destellos (Pirata), almas (Shinigami)
-- Un solo bucle compartido anima todo (barato). Para apagarlo: UITheme.Effects = false antes de crear la UI.
---------------------------------------------------------------------
local RunService = game:GetService("RunService")
UITheme.Effects = true

local function seq(points: { { any } }): ColorSequence
	local kp: { ColorSequenceKeypoint } = {}
	for _, p in ipairs(points) do
		kp[#kp + 1] = ColorSequenceKeypoint.new(p[1] :: number, p[2] :: Color3)
	end
	return ColorSequence.new(kp)
end

local CONIC: { [string]: ColorSequence } = {
	Saiyan = seq({ { 0, Color3.fromRGB(255, 226, 122) }, { 0.2, Color3.fromRGB(255, 138, 31) }, { 0.4, Color3.fromRGB(122, 42, 5) }, { 0.6, Color3.fromRGB(255, 138, 31) }, { 0.78, Color3.fromRGB(255, 226, 122) }, { 0.9, Color3.fromRGB(122, 42, 5) }, { 1, Color3.fromRGB(255, 226, 122) } }),
	Shinobi = seq({ { 0, Color3.fromRGB(155, 224, 138) }, { 0.25, Color3.fromRGB(47, 90, 56) }, { 0.45, Color3.fromRGB(239, 228, 196) }, { 0.65, Color3.fromRGB(47, 90, 56) }, { 1, Color3.fromRGB(155, 224, 138) } }),
	Pirate = seq({ { 0, Color3.fromRGB(217, 183, 119) }, { 0.2, Color3.fromRGB(140, 106, 53) }, { 0.4, Color3.fromRGB(217, 183, 119) }, { 0.6, Color3.fromRGB(63, 169, 255) }, { 0.8, Color3.fromRGB(140, 106, 53) }, { 1, Color3.fromRGB(217, 183, 119) } }),
	Shinigami = seq({ { 0, Color3.fromRGB(238, 242, 255) }, { 0.25, Color3.fromRGB(58, 64, 104) }, { 0.42, Color3.fromRGB(211, 36, 60) }, { 0.58, Color3.fromRGB(58, 64, 104) }, { 0.8, Color3.fromRGB(238, 242, 255) }, { 1, Color3.fromRGB(238, 242, 255) } }),
}

type Spinner = { G: UIGradient, S: UIStroke, Base: number, Phase: number }
type Particle = { F: GuiObject, Host: GuiObject, Kind: string, X: number, Speed: number, Phase: number }
local spinners: { Spinner } = {}
local particles: { Particle } = {}
local acc = 0

RunService.RenderStepped:Connect(function(dt: number)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	local now = os.clock()
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		if not s.G.Parent or not s.S.Parent then
			spinners[i] = spinners[#spinners]
			spinners[#spinners] = nil
		else
			s.G.Rotation = (now * 70 + s.Phase) % 360
			s.S.Thickness = s.Base + 0.8 * (0.5 + 0.5 * math.sin(now * 2.2 + s.Phase))
		end
	end
	for i = #particles, 1, -1 do
		local p = particles[i]
		if not p.F.Parent or not p.Host.Parent then
			particles[i] = particles[#particles]
			particles[#particles] = nil
		else
			local u = ((now * p.Speed) + p.Phase) % 1
			if p.Kind == "rise" then
				p.F.Position = UDim2.fromScale(p.X + math.sin(u * 6 + p.Phase * 9) * 0.02, 1.02 - u * 1.1)
				p.F.BackgroundTransparency = 0.2 + math.abs(u - 0.5) * 1.4
			elseif p.Kind == "fall" then
				p.F.Position = UDim2.fromScale(p.X - u * 0.35 + 0.2, -0.05 + u * 1.1)
				p.F.Rotation = u * 540
				p.F.BackgroundTransparency = 0.15 + math.abs(u - 0.5) * 1.2
			elseif p.Kind == "spin" then
				p.F.Rotation = (now * p.Speed * 360) % 360
			elseif p.Kind == "irise" then
				local img = p.F :: ImageLabel
				img.Position = UDim2.fromScale(p.X + math.sin(u * 6 + p.Phase * 9) * 0.02, 1.02 - u * 1.1)
				img.ImageTransparency = math.min(1, 0.1 + math.abs(u - 0.5) * 1.6)
			elseif p.Kind == "ifall" then
				local img = p.F :: ImageLabel
				img.Position = UDim2.fromScale(p.X - u * 0.35 + 0.2, -0.05 + u * 1.1)
				img.Rotation = u * 540
				img.ImageTransparency = math.min(1, 0.1 + math.abs(u - 0.5) * 1.4)
			elseif p.Kind == "iflick" then
				local img = p.F :: ImageLabel
				img.ImageTransparency = 0.2 + 0.2 * math.sin(now * 5 + p.Phase * 12)
				img.Rotation = math.sin(now * 3 + p.Phase * 9) * 3
			elseif p.Kind == "iscroll" then
				local d = (now * math.abs(p.Speed)) % p.Phase
				p.F.Position = UDim2.new(0, p.X + (if p.Speed < 0 then -d else d), p.F.Position.Y.Scale, p.F.Position.Y.Offset)
			elseif p.Kind == "slide" then
				p.F.Position = UDim2.fromOffset(-((now * p.Speed) % 16), 0)
			elseif p.Kind == "swing" then
				p.F.Rotation = math.sin(now * 1.3 + p.Phase * 6) * 18
			elseif p.Kind == "flame" then
				p.F.BackgroundTransparency = 0.4 + 0.25 * math.sin(now * 5 + p.Phase * 12)
			elseif p.Kind == "wave" then
				p.F.Position = UDim2.new(p.X, 0, 1, -4 + math.sin(now * 2 + p.Phase * 9) * 4)
			elseif p.Kind == "sweep" then
				p.F.Position = UDim2.new(u * 1.5 - 0.25, 0, p.X, 0)
			else -- twinkle
				p.F.Position = UDim2.fromScale(p.X, 0.1 + (p.Phase * 0.8))
				p.F.BackgroundTransparency = 0.15 + (0.5 + 0.5 * math.sin(u * math.pi * 2)) * 0.85
			end
		end
	end
end)

local function key(theme: Theme): string
	for _, k in ipairs({ "Saiyan", "Shinobi", "Pirata", "Shinigami" }) do
		if string.find(theme.Faction, k, 1, true) then
			return if k == "Pirata" then "Pirate" else k
		end
	end
	return "Saiyan"
end

local KIND: { [string]: string } = { Saiyan = "rise", Shinigami = "rise", Shinobi = "fall", Pirate = "twinkle" }

local RADIUS: { [string]: number } = { Saiyan = 8, Shinobi = 3, Pirate = 12, Shinigami = 0 }

local function box(parent: Instance, size: UDim2, pos: UDim2, color: Color3, transp: number, z: number?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transp
	f.ZIndex = z or 0
	f.Parent = parent
	return f
end

local function dot(parent: Instance, d: number, pos: UDim2, color: Color3, anchor: Vector2?, z: number?): Frame
	local f = box(parent, UDim2.fromOffset(d, d), pos, color, 0, z)
	f.AnchorPoint = anchor or Vector2.new(0.5, 0.5)
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	return f
end

local function addParticle(f: GuiObject, host: GuiObject, kind: string, x: number, speed: number, phase: number)
	table.insert(particles, { F = f, Host = host, Kind = kind, X = x, Speed = speed, Phase = phase })
end

-- Decoración propia de cada facción (ventanas grandes y paneles). Imita los diseños: cabecera, forma del marco y efectos.
local function skin(f: Frame, theme: Theme, w: number, h: number)
	local k = key(theme)
	local window = w >= 300 and h >= 300
	local panelSized = w >= 150 and h >= 90
	-- contenedor recortado para efectos internos (detrás del contenido)
	local fx = box(f, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), theme.Dark, 1, 0)
	fx.Name = "Fx"
	fx.ClipsDescendants = true
	Instance.new("UICorner", fx).CornerRadius = UDim.new(0, RADIUS[k] or 8)
	-- FONDO de la facción (degradado + marca de agua + motivo animado), detrás del contenido
	if panelSized then
		local BG: { [string]: { Color3 } } = {
			Saiyan = { Color3.fromRGB(40, 20, 11), Color3.fromRGB(20, 10, 5) },
			Shinobi = { Color3.fromRGB(26, 54, 36), Color3.fromRGB(11, 22, 16) },
			Pirate = { Color3.fromRGB(16, 48, 78), Color3.fromRGB(7, 22, 38) },
			Shinigami = { Color3.fromRGB(18, 18, 36), Color3.fromRGB(6, 6, 12) },
		}
		local pair = BG[k] or BG.Saiyan
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local bgG = Instance.new("UIGradient")
		bgG.Color = ColorSequence.new(pair[1], pair[2])
		bgG.Rotation = 90
		bgG.Parent = f
		local s = math.min(w, h)
		local mark = Instance.new("TextLabel")
		mark.BackgroundTransparency = 1
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(0.5, 0.55)
		mark.Size = UDim2.fromOffset(s * 0.8, s * 0.8)
		mark.Text = theme.Emblem
		mark.TextScaled = true
		mark.Font = Enum.Font.GothamBlack
		mark.TextColor3 = theme.Primary
		mark.TextTransparency = 0.9
		mark.ZIndex = 0
		mark.Parent = fx
		-- luz inferior de la facción + destello que cruza el panel
		local glow = box(fx, UDim2.new(1, 0, 0.55, 0), UDim2.fromScale(0, 0.45), theme.Primary, 0, 0)
		local glowG = Instance.new("UIGradient")
		glowG.Rotation = 90
		glowG.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.72) })
		glowG.Parent = glow
		if k ~= "Shinigami" then
			local sh = box(fx, UDim2.fromOffset(44, h * 1.8), UDim2.fromScale(0, 0.5), Color3.new(1, 1, 1), 0, 0)
			sh.AnchorPoint = Vector2.new(0.5, 0.5)
			sh.Rotation = 20
			local shG = Instance.new("UIGradient")
			shG.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.86), NumberSequenceKeypoint.new(1, 1) })
			shG.Parent = sh
			addParticle(sh, f, "sweep", 0.5, 0.16, 0)
		end
		local function ring(d: number, anchor: Vector2, pos: UDim2, dashed: boolean, speed: number)
			local r = box(fx, UDim2.fromOffset(d, d), pos, theme.Primary, 1, 0)
			r.AnchorPoint = anchor
			Instance.new("UICorner", r).CornerRadius = UDim.new(1, 0)
			local st = Instance.new("UIStroke")
			st.Color = theme.Primary
			st.Thickness = dashed and 1 or 1.5
			st.Transparency = 0.62
			st.Parent = r
			if speed ~= 0 then
				addParticle(r, f, "spin", 0, speed, 0)
			end
			return r
		end
		if window or (panelSized and h >= 100) then
			if k == "Saiyan" then
				for i = -2, 2 do
					local ray = box(fx, UDim2.fromOffset(math.max(8, s * 0.03), h * 1.7), UDim2.new(0.5, i * w * 0.2, 1, 0), Color3.fromRGB(255, 150, 40), 0.88, 0)
					ray.AnchorPoint = Vector2.new(0.5, 1)
					ray.Rotation = i * 9
				end
			elseif k == "Shinobi" then
				ring(s * 0.62, Vector2.new(1, 1), UDim2.new(1, s * 0.18, 1, s * 0.18), false, 0.03)
				ring(s * 0.44, Vector2.new(1, 1), UDim2.new(1, s * 0.09, 1, s * 0.09), true, -0.05)
				ring(s * 0.34, Vector2.new(0, 0), UDim2.new(0, -s * 0.08, 0, 40), false, 0.04)
			elseif k == "Pirate" then
				local c = ring(s * 0.36, Vector2.new(1, 1), UDim2.new(1, -14, 1, -34), false, 0)
				ring(s * 0.28, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), true, 0).Parent = c
				local needle = box(c, UDim2.fromOffset(3, s * 0.3), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(224, 69, 58), 0.35, 0)
				needle.AnchorPoint = Vector2.new(0.5, 0.5)
				addParticle(needle, f, "swing", 0, 0, 0.2)
			else
				local moon = box(fx, UDim2.fromOffset(s * 0.5, s * 0.5), UDim2.new(0.5, 0, 0.5, 0), Color3.fromRGB(235, 232, 255), 0.93, 0)
				moon.AnchorPoint = Vector2.new(0.5, 0.5)
				Instance.new("UICorner", moon).CornerRadius = UDim.new(1, 0)
				ring(s * 0.55, Vector2.new(1, 1), UDim2.new(1, s * 0.12, 1, s * 0.12), true, 0.04)
				ring(s * 0.38, Vector2.new(1, 1), UDim2.new(1, s * 0.03, 1, s * 0.03), false, -0.06)
			end
		end
	end
	if window then
		-- cabecera de 44 px: degradado de la facción con línea de acento
		local band = box(fx, UDim2.new(1, 0, 0, 44), UDim2.fromScale(0, 0), theme.Primary, 0.35, 0)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, theme.Dark), ColorSequenceKeypoint.new(0.5, theme.Secondary), ColorSequenceKeypoint.new(1, theme.Dark) })
		g.Parent = band
		box(fx, UDim2.new(1, 0, 0, 2), UDim2.fromOffset(0, 43), theme.Primary, 0, 0)
	end
	local n = if window then 9 elseif panelSized then 7 else 4
	if k == "Saiyan" then
		for i = 1, n do
			local s = dot(fx, 5, UDim2.fromScale(0, 0), theme.Primary)
			addParticle(s, f, "rise", (i - 0.5) / n, 0.12 + (i % 3) * 0.05, (i * 0.37) % 1)
		end
		if panelSized then -- llamas al pie
			local fs = if window then 22 else 14
			local teeth = math.floor(w / (fs * 1.5))
			for i = 1, teeth do
				local t2 = box(fx, UDim2.fromOffset(fs, fs), UDim2.new((i - 0.5) / teeth, 0, 1, 2), Color3.fromRGB(255, 120, 30), 0.5, 0)
				t2.AnchorPoint = Vector2.new(0.5, 0.5)
				t2.Rotation = 45
				addParticle(t2, f, "flame", 0, 0, (i * 0.23) % 1)
			end
		end
	elseif k == "Shinobi" then
		for i = 1, n do
			local l = box(fx, UDim2.fromOffset(9, 6), UDim2.fromScale(0, 0), theme.Primary, 0.3, 0)
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			Instance.new("UICorner", l).CornerRadius = UDim.new(1, 0)
			addParticle(l, f, "fall", (i - 0.5) / n + 0.3, 0.1 + (i % 3) * 0.04, (i * 0.41) % 1)
		end
		if window or panelSized then -- rollos de pergamino arriba y abajo (fuera del marco)
			local cream = Color3.fromRGB(232, 222, 190)
			for _, y in ipairs({ -9, 1 }) do
				local r = box(f, UDim2.new(1, 24, 0, 16), UDim2.new(0, -12, y < 0 and 0 or 1, y < 0 and -9 or -7), cream, 0, 6)
				Instance.new("UICorner", r).CornerRadius = UDim.new(0, 8)
				local st = Instance.new("UIStroke")
				st.Color = Color3.fromRGB(138, 118, 72)
				st.Thickness = 2
				st.Parent = r
			end
		end
	elseif k == "Pirata" or k == "Pirate" then
		for i = 1, n do
			local s = box(fx, UDim2.fromOffset(3, 3), UDim2.fromScale(0, 0), Color3.fromRGB(255, 240, 200), 0.3, 0)
			addParticle(s, f, "twinkle", (i - 0.5) / n, 0.2 + (i % 3) * 0.06, (i * 0.29) % 1)
		end
		if panelSized then -- olas al pie
			local ws = if window then 36 else 24
			local waves = math.floor(w / (ws * 1.1))
			for i = 1, waves do
				local d = dot(fx, ws, UDim2.new((i - 0.5) / waves, 0, 1, 0), Color3.fromRGB(44, 127, 192))
				d.BackgroundTransparency = 0.45
				addParticle(d, f, "wave", (i - 0.5) / waves, 0, (i * 0.31) % 1)
			end
		end
		if panelSized then -- remaches dorados en las esquinas
			for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
				dot(f, 10, UDim2.new(c[1], c[1] == 0 and 5 or -5, c[2], c[2] == 0 and 5 or -5), Color3.fromRGB(235, 200, 110), nil, 8)
			end
		end
	else -- Shinigami
		for i = 1, n do
			local s = dot(fx, 5, UDim2.fromScale(0, 0), Color3.fromRGB(207, 224, 255))
			addParticle(s, f, "rise", (i - 0.5) / n, 0.09 + (i % 3) * 0.04, (i * 0.43) % 1)
		end
		if panelSized then -- esquinas en ángulo + destello que recorre el borde superior e inferior
			local white = Color3.fromRGB(238, 242, 255)
			for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
				local ax, ay = c[1], c[2]
				local hb = box(f, UDim2.fromOffset(20, 3), UDim2.new(ax, ax == 0 and 5 or -5, ay, ay == 0 and 5 or -5), white, 0, 7)
				hb.AnchorPoint = Vector2.new(ax, ay)
				local vb = box(f, UDim2.fromOffset(3, 20), UDim2.new(ax, ax == 0 and 5 or -5, ay, ay == 0 and 5 or -5), white, 0, 7)
				vb.AnchorPoint = Vector2.new(ax, ay)
			end
			for _, y in ipairs({ 0, 1 }) do
				local sw = box(fx, UDim2.fromOffset(70, 2), UDim2.fromScale(0, y), white, 0.2, 1)
				sw.AnchorPoint = Vector2.new(0, y)
				local sg = Instance.new("UIGradient")
				sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
				sg.Parent = sw
				addParticle(sw, f, "sweep", y, 0.2, y * 0.5)
			end
		end
	end
end

function UITheme.Key(theme: Theme): string
	return key(theme)
end

-- Marco con IMÁGENES (exportadas de las maquetas) + capas animadas por código. art = "panel" (370x122) o "window" (700x700).
local IMG_PAD: { [string]: number } = { Saiyan = 4, Shinobi = 0, Pirate = 9, Shinigami = 1 }
local function imageSkin(f: Frame, theme: Theme, id: string, art: string, w: number, h: number)
	local k = key(theme)
	f.BackgroundTransparency = 1
	local bg = Instance.new("ImageLabel")
	bg.Name = "Marco"
	bg.BackgroundTransparency = 1
	bg.Image = id
	bg.ZIndex = 0
	if k == "Shinobi" then -- los rollos y kunai sobresalen del marco
		bg.Position = UDim2.fromOffset(-14, -12)
		bg.Size = UDim2.new(1, 28, 1, 24)
	else
		bg.Size = UDim2.fromScale(1, 1)
	end
	bg.Parent = f
	local pad = IMG_PAD[k] or 0
	local fx = box(f, UDim2.new(1, -pad * 2, 1, -pad * 2), UDim2.fromOffset(pad, pad), theme.Dark, 1, 0)
	fx.Name = "Fx"
	fx.ClipsDescendants = true
	if not UITheme.Effects then
		return
	end
	local win = art == "window"
	local sc = if win then 1 else 0.5

	local function I(name: string, sx: number, sy: number, pos: UDim2, anchor: Vector2?, parent: Instance?): ImageLabel?
		local src = UIAssets.Get(name)
		if not src then
			return nil
		end
		local im = Instance.new("ImageLabel")
		im.Name = name
		im.BackgroundTransparency = 1
		im.Image = src
		im.Size = UDim2.fromOffset(sx, sy)
		im.Position = pos
		im.AnchorPoint = anchor or Vector2.zero
		im.ZIndex = 1
		im.Parent = parent or fx
		return im
	end

	if k == "Pirate" then
		local w1 = I("pirate_wave1", 840, 60, UDim2.new(0, 0, 1, -54))
		if w1 then
			addParticle(w1, f, "iscroll", 0, -24, 120)
		end
		local w2 = I("pirate_wave2", 840, 60, UDim2.new(0, -120, 1, -46))
		if w2 then
			addParticle(w2, f, "iscroll", -120, 17, 120)
		end
		local cs = 120 * sc
		local compass = I("pirate_compass", cs, cs, UDim2.new(1, -12, 1, if win then -34 else -8), Vector2.new(1, 1))
		if compass then
			local needle = I("pirate_needle", cs, cs, UDim2.fromScale(0, 0), nil, compass)
			if needle then
				needle.Size = UDim2.fromScale(1, 1)
				addParticle(needle, f, "swing", 0, 0, 0.2)
			end
		end
	elseif k == "Saiyan" then
		local fw, fh = 34 * sc, 44 * sc
		local teeth = math.floor(w / (fw * 1.5))
		for i = 1, teeth do
			local fl = I("saiyan_flame", fw, fh, UDim2.new((i - 0.5) / teeth, 0, 1, 2), Vector2.new(0.5, 1))
			if fl then
				addParticle(fl, f, "iflick", 0, 0, (i * 0.23) % 1)
			end
		end
		local n = if win then 9 else 7
		for i = 1, n do
			local sp = I("saiyan_spark", 16, 16, UDim2.fromScale(0, 0), Vector2.new(0.5, 0.5))
			if sp then
				addParticle(sp, f, "irise", (i - 0.5) / n, 0.12 + (i % 3) * 0.05, (i * 0.37) % 1)
			end
		end
	elseif k == "Shinobi" then
		local seal = I("shinobi_seal", 170 * sc, 170 * sc, UDim2.new(1, 24 * sc, 1, 24 * sc), Vector2.new(1, 1))
		if seal then
			addParticle(seal, f, "spin", 0, 1 / 14, 0)
		end
		if win then
			I("shinobi_wind", w, h, UDim2.fromScale(0, 0))
		end
		local n = if win then 7 else 5
		for i = 1, n do
			local lf = I("shinobi_leaf", 10, 7, UDim2.fromScale(0, 0), Vector2.new(0.5, 0.5))
			if lf then
				addParticle(lf, f, "ifall", (i - 0.5) / n + 0.3, 0.1 + (i % 3) * 0.04, (i * 0.41) % 1)
			end
		end
	else -- Shinigami
		local ss = 210 * sc
		local s1 = I("shinigami_seal1", ss, ss, UDim2.new(1, ss * 0.2, 1, ss * 0.2), Vector2.new(1, 1))
		if s1 then
			addParticle(s1, f, "spin", 0, 1 / 22, 0)
		end
		local s2 = I("shinigami_seal2", ss, ss, UDim2.new(1, ss * 0.2, 1, ss * 0.2), Vector2.new(1, 1))
		if s2 then
			addParticle(s2, f, "spin", 0, -1 / 14, 0)
		end
		local n = if win then 6 else 5
		for i = 1, n do
			local sp = I("shinigami_spirit", 14, 14, UDim2.fromScale(0, 0), Vector2.new(0.5, 0.5))
			if sp then
				addParticle(sp, f, "irise", (i - 0.5) / n, 0.09 + (i % 3) * 0.04, (i * 0.43) % 1)
			end
		end
		for _, y in ipairs({ 0, 1 }) do
			local ed = I("shinigami_edge", 90, 4, UDim2.fromScale(0, y), Vector2.new(0, y))
			if ed then
				addParticle(ed, f, "sweep", y, 0.2, y * 0.5)
			end
		end
	end
end

-- Marco con borde degradado (color primario -> secundario) de la facción
function UITheme.Frame(parent: Instance, theme: Theme, size: UDim2, pos: UDim2, anchor: Vector2?, art: string?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor or Vector2.zero
	f.BackgroundColor3 = theme.Dark
	f.BackgroundTransparency = 0.04
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, RADIUS[key(theme)] or 8)
	c.Parent = f
	local w = size.X.Offset + size.X.Scale * 1280
	local h = size.Y.Offset + size.Y.Scale * 720
	if art then
		local id = UIAssets.Get(string.lower(key(theme)) .. "_" .. art)
		if id then
			imageSkin(f, theme, id, art, w, h)
			return f
		end
	end
	local st = UITheme.Border(f, theme, 2)
	if key(theme) == "Pirate" then
		-- cuerda: línea dorada fina por fuera + banda de 6 px con rayas diagonales finas (oro / marrón), como en la maqueta
		for i = #spinners, 1, -1 do
			if spinners[i].S == st then
				table.remove(spinners, i)
			end
		end
		local g0 = st:FindFirstChildOfClass("UIGradient")
		if g0 then
			g0:Destroy()
		end
		st.Color = Color3.fromRGB(217, 183, 119)
		st.Thickness = 1.5
		if size.X.Scale == 0 and size.Y.Scale == 0 and w >= 60 and h >= 30 then
			local gold, brown = Color3.fromRGB(228, 194, 128), Color3.fromRGB(112, 82, 38)
			local BAND, STEP = 5, if (w + h) * 2 > 1500 then 8 else 6
			local function edge(pos: UDim2, dim: UDim2, length: number)
				local e = box(f, dim, pos, brown, 0, 6)
				e.Name = "Cuerda"
				e.ClipsDescendants = true
				for i = 0, math.floor(length / STEP) + 1 do
					local tick = box(e, UDim2.fromOffset(STEP / 2, BAND * 2.6), UDim2.fromOffset(i * STEP, BAND / 2), gold, 0, 6)
					tick.AnchorPoint = Vector2.new(0.5, 0.5)
					tick.Rotation = 45
					if dim.Y.Offset ~= BAND then -- borde vertical: se reparte a lo largo de Y
						tick.Position = UDim2.fromOffset(BAND / 2, i * STEP)
					end
				end
			end
			local IN = 9 -- las esquinas redondeadas quedan libres (ahí van los remaches)
			edge(UDim2.fromOffset(IN, 0), UDim2.fromOffset(w - IN * 2, BAND), w)
			edge(UDim2.fromOffset(IN, h - BAND), UDim2.fromOffset(w - IN * 2, BAND), w)
			edge(UDim2.fromOffset(0, IN), UDim2.fromOffset(BAND, h - IN * 2), h)
			edge(UDim2.fromOffset(w - BAND, IN), UDim2.fromOffset(BAND, h - IN * 2), h)
		end
	end
	if UITheme.Effects then
		skin(f, theme, w, h)
	end
	return f
end

-- radio de esquina de la facción y color de acento claro (lo usan retratos y paneles)
function UITheme.Radius(theme: Theme): number
	return RADIUS[key(theme)] or 8
end

function UITheme.Accent(theme: Theme): Color3
	return theme.Primary:Lerp(Color3.new(1, 1, 1), 0.35)
end

function UITheme.Border(inst: GuiObject, theme: Theme, thickness: number): UIStroke
	local st = Instance.new("UIStroke")
	st.Thickness = thickness
	st.Color = Color3.new(1, 1, 1)
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = inst
	local g = Instance.new("UIGradient")
	g.Color = CONIC[key(theme)] or ColorSequence.new(theme.Primary, theme.Secondary)
	g.Rotation = 45
	g.Parent = st
	if UITheme.Effects and thickness >= 2 then
		table.insert(spinners, { G = g, S = st, Base = thickness, Phase = (#spinners * 37) % 360 })
	end
	return st
end

function UITheme.Text(parent: Instance, text: string, size: number, color: Color3?, pos: UDim2, dim: UDim2, align: Enum.TextXAlignment?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.Font = UITheme.Font
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.Position = pos
	t.Size = dim
	t.TextStrokeTransparency = 0.6
	t.Parent = parent
	return t
end

-- Barra con relleno, texto central y esquinas redondeadas. Devuelve (contenedor, función set(valor, máximo, texto?))
function UITheme.Bar(parent: Instance, pos: UDim2, size: UDim2, fill: Color3, label: string?, textSize: number?, edge: Color3?): (Frame, (number, number, string?) -> ())
	local back = Instance.new("Frame")
	back.Position = pos
	back.Size = size
	back.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	back.BorderSizePixel = 0
	back.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 5)
	c.Parent = back
	if edge then
		local es = Instance.new("UIStroke")
		es.Color = edge
		es.Thickness = 1
		es.Transparency = 0.35
		es.Parent = back
	end
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = fill
	bar.BorderSizePixel = 0
	bar.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 5)
	c2.Parent = bar
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	g.Rotation = 90
	g.Parent = bar
	if UITheme.Effects and size.X.Offset >= 60 and size.Y.Offset >= 8 then
		-- rayas diagonales que avanzan por el relleno (como en la maqueta)
		local clip = Instance.new("Frame")
		clip.Name = "Rayas"
		clip.BackgroundTransparency = 1
		clip.Size = UDim2.fromScale(1, 1)
		clip.ClipsDescendants = true
		clip.ZIndex = 2
		clip.Parent = bar
		Instance.new("UICorner", clip).CornerRadius = UDim.new(0, 5)
		local slider = Instance.new("Frame")
		slider.BackgroundTransparency = 1
		slider.Size = UDim2.fromOffset(size.X.Offset + 48, size.Y.Offset)
		slider.Parent = clip
		for i = 0, math.floor(size.X.Offset / 16) + 3 do
			local s = box(slider, UDim2.fromOffset(6, size.Y.Offset * 2), UDim2.fromOffset(i * 16, size.Y.Offset / 2), Color3.new(1, 1, 1), 0.82, 2)
			s.AnchorPoint = Vector2.new(0, 0.5)
			s.Rotation = 25
		end
		addParticle(slider, back, "slide", 0, 22, 0)
	end
	local t = UITheme.Text(back, label or "", textSize or 13, nil, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Enum.TextXAlignment.Center)
	t.ZIndex = 3
	return back, function(value: number, max: number, text: string?)
		local ratio = if max > 0 then math.clamp(value / max, 0, 1) else 0
		bar.Size = UDim2.fromScale(ratio, 1)
		t.Text = text or string.format("%d / %d", math.floor(value), math.floor(max))
	end
end

return UITheme
