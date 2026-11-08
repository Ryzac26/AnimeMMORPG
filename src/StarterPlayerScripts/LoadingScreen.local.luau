--!strict
--[[
    LoadingScreen (LocalScript) -> StarterPlayer > StarterPlayerScripts > LoadingScreen
    PANTALLA DE CARGA del mundo. Tapa la pantalla hasta que:
      1. el servidor confirma  Workspace.WorldReady  (mapa + estilos listos; lo pone WorldReadyService)
      2. te han llegado los adornos de ciudades y arena (carpetas "Estilo", comparadas con su atributo Count)
      3. tu personaje existe (y, si el mapa usa StreamingEnabled, se pidió cargar el lugar donde apareces)
    Entonces avisa al servidor (remote WorldLoaded), que suelta a tu personaje, y la pantalla se desvanece.
    Nunca se queda pegada: tope TIMEOUT_TOTAL s (avisa en la consola F9 qué faltó).
]]
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TIMEOUT_SERVER = 60 -- s esperando la marca WorldReady del servidor
local TIMEOUT_TOTAL = 90 -- s máximo en total
local NEED_RATIO = 0.9 -- fracción de adornos que deben haber llegado (los temas de la arena varían un poco)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 30)
if not playerGui then
	return
end

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = playerGui

local back = Instance.new("Frame")
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
back.BorderSizePixel = 0
back.Active = true -- bloquea clics hacia lo de abajo
back.Parent = gui

local title = Instance.new("TextLabel")
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.42)
title.Size = UDim2.fromOffset(600, 50)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 34
title.TextColor3 = Color3.fromRGB(255, 214, 90)
title.Text = "Cargando el mundo..."
title.Parent = back

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0.5)
status.Position = UDim2.fromScale(0.5, 0.5)
status.Size = UDim2.fromOffset(600, 24)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 16
status.TextColor3 = Color3.fromRGB(190, 190, 205)
status.Text = "Conectando con el servidor"
status.Parent = back

local barBack = Instance.new("Frame")
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.Position = UDim2.fromScale(0.5, 0.58)
barBack.Size = UDim2.fromOffset(420, 10)
barBack.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
barBack.BorderSizePixel = 0
barBack.Parent = back
Instance.new("UICorner", barBack).CornerRadius = UDim.new(1, 0)
local bar = Instance.new("Frame")
bar.Size = UDim2.fromScale(0, 1)
bar.BackgroundColor3 = Color3.fromRGB(255, 214, 90)
bar.BorderSizePixel = 0
bar.Parent = barBack
Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

---------------------------------------------------------------------
-- CONSEJOS: uno distinto cada pocos segundos mientras carga. {Nombre} se cambia por la tecla real (la del jugador si la cambió en Ajustes).
-- Solo datos ciertos del juego; para agregar uno, añade una línea a TIPS.
---------------------------------------------------------------------
local TIPS = {
	"Pulsa {Perfil} para ver tu perfil y {Mochila} para abrir la mochila.",
	"{AutoFarm} activa el auto-farmeo y {AutoAtaque} pausa el auto-ataque.",
	"Tus poderes van del 1 al 7. El 7 son Primeros Auxilios.",
	"{Mercader} abre al Mercader: vende y compra sin ir a buscarlo.",
	"{Maestria} abre la Maestría de rol y {Faccion} tu facción.",
	"{Grupo} abre el grupo y las invitaciones: en equipo se juega mejor.",
	"{Notas} muestra las novedades del último parche.",
	"Si mueres no bajas de nivel: solo pierdes un poco de la experiencia del nivel actual.",
	"Tras reaparecer tienes unos segundos de protección.",
	"El PvP solo existe en la Arena Central y entre naciones distintas.",
	"En la Arena tienes 5 vidas. Elige bien tus peleas.",
	"Para repartirse el botín de un jefe hay que hacerle al menos el 1% del daño.",
	"Tus mascotas te siguen, crecen y pueden darte poderes.",
}
local FOOTER = "¿Algo falla? Usa el botón REPORTAR del borde derecho de la pantalla. Nos ayuda muchísimo."

local function keyLabel(id: string): string
	local label: string? = nil
	pcall(function()
		local KeyBinds = require(script.Parent:WaitForChild("KeyBinds", 5))
		label = KeyBinds.Label(id)
	end)
	if not label then
		pcall(function()
			local cat = require(game:GetService("ReplicatedStorage").Modules.KeyBindCatalog)
			label = cat.ById[id].Default
		end)
	end
	return label or "?"
end

local function tipText(raw: string): string
	return (string.gsub(raw, "{(%w+)}", keyLabel))
end

local tipLabel = Instance.new("TextLabel")
tipLabel.AnchorPoint = Vector2.new(0.5, 0)
tipLabel.Position = UDim2.fromScale(0.5, 0.64)
tipLabel.Size = UDim2.new(0.8, 0, 0, 44)
tipLabel.BackgroundTransparency = 1
tipLabel.Font = Enum.Font.Gotham
tipLabel.TextSize = 18
tipLabel.TextWrapped = true
tipLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
tipLabel.Text = ""
tipLabel.Parent = back
local tipSize = Instance.new("UITextSizeConstraint")
tipSize.MaxTextSize = 20
tipSize.MinTextSize = 12
tipSize.Parent = tipLabel

local footer = Instance.new("TextLabel")
footer.AnchorPoint = Vector2.new(0.5, 1)
footer.Position = UDim2.new(0.5, 0, 1, -24)
footer.Size = UDim2.new(0.9, 0, 0, 40)
footer.BackgroundTransparency = 1
footer.Font = Enum.Font.GothamMedium
footer.TextSize = 14
footer.TextWrapped = true
footer.TextColor3 = Color3.fromRGB(150, 150, 170)
footer.Text = FOOTER
footer.Parent = back

local tipsRunning = true
task.spawn(function()
	local order = {}
	for i = 1, #TIPS do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local n = 0
	while tipsRunning and gui.Parent do
		n = n % #order + 1
		tipLabel.Text = tipText(TIPS[order[n]])
		tipLabel.TextTransparency = 1
		TweenService:Create(tipLabel, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
		for _ = 1, 50 do -- ~5 s
			if not tipsRunning then
				return
			end
			task.wait(0.1)
		end
		if tipsRunning then
			TweenService:Create(tipLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.35)
		end
	end
end)

local function setProgress(ratio: number, text: string)
	bar.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	status.Text = text
end

local startedAt = os.clock()
local function elapsed(): number
	return os.clock() - startedAt
end

-- 1) marca del servidor
setProgress(0.05, "Conectando con el servidor")
while Workspace:GetAttribute("WorldReady") ~= true and elapsed() < TIMEOUT_SERVER do
	task.wait(0.2)
end
local serverReady = Workspace:GetAttribute("WorldReady") == true
if not serverReady then
	warn("[LoadingScreen] El servidor no marcó WorldReady en " .. TIMEOUT_SERVER .. " s (¿WorldReadyService no está en GameServerMain?). Se continúa igual.")
end

-- 2) adornos de ciudades y arena (con StreamingEnabled solo llegan los cercanos: no se cuentan)
local streaming = Workspace.StreamingEnabled
if serverReady and not streaming then
	local expected = Workspace:GetAttribute("WorldStyleFolders")
	local need = if typeof(expected) == "number" then expected else 0
	while elapsed() < TIMEOUT_TOTAL do
		local tagged = CollectionService:GetTagged("WorldStyle")
		local have, want = 0, 0
		for _, f in ipairs(tagged) do
			local count = f:GetAttribute("Count")
			if typeof(count) == "number" then
				want += count * NEED_RATIO
				have += math.min(#f:GetDescendants(), count * NEED_RATIO)
			end
		end
		local foldersOk = #tagged >= need
		local ratio = if want > 0 then have / want else (if foldersOk then 1 else 0)
		setProgress(0.1 + 0.75 * ratio, string.format("Descargando ciudades y arena  %d%%", math.floor(ratio * 100)))
		if foldersOk and ratio >= 1 then
			break
		end
		task.wait(0.3)
	end
	if elapsed() >= TIMEOUT_TOTAL then
		warn("[LoadingScreen] No llegaron todos los adornos a tiempo; se continúa igual.")
	end
end

-- 3) personaje y, con StreamingEnabled, el lugar donde apareces
setProgress(0.9, "Preparando tu personaje")
local root: BasePart? = nil
local waitedChar = os.clock()
while os.clock() - waitedChar < 20 do
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		root = r
		break
	end
	task.wait(0.2)
end
if root and streaming then
	setProgress(0.93, "Cargando tu zona")
	pcall(function()
		player:RequestStreamAroundAsync(root.Position, 8)
	end)
end
task.wait(0.6)

-- avisar al servidor (suelta a tu personaje) y desvanecer
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Remotes", 10)
local loadedRemote = remotes and remotes:WaitForChild("WorldLoaded", 10)
if loadedRemote and loadedRemote:IsA("RemoteEvent") then
	loadedRemote:FireServer()
end
setProgress(1, "¡Listo!")
print(string.format("[LoadingScreen] Mundo cargado en %.1f s (servidor=%s, streaming=%s).", elapsed(), tostring(serverReady), tostring(streaming)))

tipsRunning = false
local info = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(back, info, { BackgroundTransparency = 1 }):Play()
for _, d in ipairs(back:GetDescendants()) do
	if d:IsA("TextLabel") then
		TweenService:Create(d, info, { TextTransparency = 1 }):Play()
	elseif d:IsA("Frame") then
		TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
	end
end
task.wait(0.7)
gui:Destroy()
