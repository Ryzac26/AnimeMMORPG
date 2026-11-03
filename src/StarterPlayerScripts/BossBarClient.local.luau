--!strict
--[[
    BossBarClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > BossBarClient
    BARRA DE JEFE (arriba al centro). Muestra al jefe o mini jefe más cercano que esté vivo y a la vista:
      JEFE MUNDIAL (dorado)  ·  JEFE DE FRANJA (rojo)  ·  MINI JEFE (naranja)
    Nombre y nivel, vida actual / máxima, porcentaje y una "estela" blanca que baja despacio cuando recibe daño.
    Solo muestra: la vida la manda el servidor (Humanoid). No pide nada ni cambia nada.
    IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local Platform = require(script.Parent:WaitForChild("Platform", 10))
local MOBILE = Platform.IsMobile()
local theme = UITheme.For(player:GetAttribute("Faction"))

local KIND = {
	World = { Badge = "JEFE MUNDIAL", Color = Color3.fromRGB(255, 205, 70), Range = 700 },
	Boss = { Badge = "JEFE DE FRANJA", Color = Color3.fromRGB(230, 70, 70), Range = 160 },
	Mini = { Badge = "MINI JEFE", Color = Color3.fromRGB(255, 150, 50), Range = 130 },
} :: { [string]: { Badge: string, Color: Color3, Range: number } }
local PRIORITY = { World = 3, Boss = 2, Mini = 1 } :: { [string]: number }

local gui = Instance.new("ScreenGui")
gui.Name = "BossBarGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 6
gui.Parent = player:WaitForChild("PlayerGui", 10)

local WIDTH = if MOBILE then 320 else 560
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, if MOBILE then 6 else 10)
panel.Size = UDim2.fromOffset(WIDTH, if MOBILE then 46 else 58)
panel.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local stroke = UITheme.Border(panel, theme, 2)

local badge = Instance.new("TextLabel")
badge.BackgroundTransparency = 1
badge.Position = UDim2.fromOffset(12, 4)
badge.Size = UDim2.fromOffset(150, if MOBILE then 14 else 16)
badge.Font = UITheme.Font
badge.TextSize = if MOBILE then 11 else 13
badge.TextXAlignment = Enum.TextXAlignment.Left
badge.TextColor3 = Color3.new(1, 1, 1)
badge.Parent = panel

local nameLabel = Instance.new("TextLabel")
nameLabel.BackgroundTransparency = 1
nameLabel.Position = UDim2.fromOffset(12, if MOBILE then 16 else 19)
nameLabel.Size = UDim2.new(1, -90, 0, if MOBILE then 16 else 20)
nameLabel.Font = Enum.Font.GothamBlack
nameLabel.TextSize = if MOBILE then 14 else 18
nameLabel.TextXAlignment = Enum.TextXAlignment.Left
nameLabel.TextColor3 = Color3.new(1, 1, 1)
nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
nameLabel.Parent = panel

local pctLabel = Instance.new("TextLabel")
pctLabel.BackgroundTransparency = 1
pctLabel.AnchorPoint = Vector2.new(1, 0)
pctLabel.Position = UDim2.new(1, -12, 0, 4)
pctLabel.Size = UDim2.fromOffset(70, if MOBILE then 28 else 34)
pctLabel.Font = Enum.Font.GothamBlack
pctLabel.TextSize = if MOBILE then 18 else 24
pctLabel.TextXAlignment = Enum.TextXAlignment.Right
pctLabel.TextColor3 = Color3.new(1, 1, 1)
pctLabel.Parent = panel

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0, 1)
barBack.Position = UDim2.new(0, 10, 1, -7)
barBack.Size = UDim2.new(1, -20, 0, if MOBILE then 10 else 14)
barBack.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
barBack.BorderSizePixel = 0
barBack.Parent = panel
Instance.new("UICorner", barBack).CornerRadius = UDim.new(0, 6)

local ghost = Instance.new("Frame") -- estela de daño
ghost.Size = UDim2.fromScale(1, 1)
ghost.BackgroundColor3 = Color3.fromRGB(250, 250, 250)
ghost.BackgroundTransparency = 0.25
ghost.BorderSizePixel = 0
ghost.Parent = barBack
Instance.new("UICorner", ghost).CornerRadius = UDim.new(0, 6)

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = barBack
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(165, 165, 165))
grad.Rotation = 90
grad.Parent = fill

local hpText = Instance.new("TextLabel")
hpText.BackgroundTransparency = 1
hpText.Size = UDim2.fromScale(1, 1)
hpText.ZIndex = 3
hpText.Font = UITheme.Font
hpText.TextSize = if MOBILE then 9 else 11
hpText.TextColor3 = Color3.new(1, 1, 1)
hpText.TextStrokeTransparency = 0.4
hpText.Parent = barBack

-- 12345678 -> "12.345.678"
local function fmt(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	return out
end

local function kindOf(m: Model): string?
	if m:GetAttribute("WorldBoss") == true then
		return "World"
	elseif m:GetAttribute("Boss") == true then
		return "Boss"
	elseif m:GetAttribute("Mini") == true then
		return "Mini"
	end
	return nil
end

local function alive(m: Model?): Humanoid?
	if not m or not m.Parent then
		return nil
	end
	local h = m:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local current: Model? = nil
local currentKind: string? = nil
local ghostFrac = 1
local lastScan = 0
local shownKind: string? = nil

local function distanceTo(m: Model): number
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local part = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and part and part:IsA("BasePart") then
		return (root.Position - part.Position).Magnitude
	end
	return math.huge
end

local function scan()
	-- se mantiene el actual mientras viva y siga en rango
	if current and alive(current) and currentKind and distanceTo(current) <= KIND[currentKind].Range * 1.25 then
		return
	end
	local best: Model? = nil
	local bestKind: string? = nil
	local bestScore = -math.huge
	for _, inst in ipairs(CollectionService:GetTagged("Targetable")) do
		if inst:IsA("Model") and inst ~= player.Character then
			local k = kindOf(inst)
			if k and alive(inst) then
				local d = distanceTo(inst)
				if d <= KIND[k].Range then
					local score = PRIORITY[k] * 1000 - d -- primero el de más rango (mundial > jefe > mini), luego el más cercano
					if score > bestScore then
						best, bestKind, bestScore = inst, k, score
					end
				end
			end
		end
	end
	if best ~= current then
		current, currentKind = best, bestKind
		ghostFrac = 1
	end
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	if now - lastScan > 0.25 then
		lastScan = now
		scan()
	end
	local hum = alive(current)
	if not hum or not current or not currentKind then
		panel.Visible = false
		return
	end
	local info = KIND[currentKind]
	if shownKind ~= currentKind then
		shownKind = currentKind
		badge.Text = info.Badge
		badge.TextColor3 = info.Color
		fill.BackgroundColor3 = info.Color
		stroke.Color = info.Color
	end
	nameLabel.Text = (current:GetAttribute("DisplayName") or current.Name) :: string
	local frac = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
	fill.Size = UDim2.fromScale(frac, 1)
	-- la estela baja despacio hasta alcanzar la vida real (sube de golpe si se cura)
	if ghostFrac < frac then
		ghostFrac = frac
	else
		ghostFrac = math.max(frac, ghostFrac - dt * 0.35)
	end
	ghost.Size = UDim2.fromScale(ghostFrac, 1)
	pctLabel.Text = string.format("%d%%", math.ceil(frac * 100))
	hpText.Text = string.format("%s / %s", fmt(hum.Health), fmt(hum.MaxHealth))
	if not panel.Visible then
		panel.Visible = true
		panel.Position = UDim2.new(0.5, 0, 0, if MOBILE then -20 else -30)
		TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, if MOBILE then 6 else 10) }):Play()
	end
end)
