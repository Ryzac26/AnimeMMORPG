--!strict
--[[
    MasteryClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > MasteryClient
    Ventana de MAESTRÍA DE ROL (tecla N o botón "⚔ Maestría" a la izquierda). Para cada uno de los 6 roles muestra rango (0-10), barra de
    progreso, el bono actual y si tiene equipo guardado. Con el pase "Maestría Multiclase" aparece el botón "Cambiar" (cambio de rol en
    cualquier lugar; el servidor lo valida y te devuelve al mismo sitio). Sin pase muestra qué da y un botón para abrir la Tienda.
    Datos: MasteryState (servidor). Acciones: MasteryAction ("State" | "Switch", rol). IMPORTANTE: está en la lista RELOAD de UIReloadClient.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules", 10)
local MasteryCatalog = require(Modules:WaitForChild("MasteryCatalog", 10))
local UITheme = require(script.Parent:WaitForChild("UITheme", 10))
local ClientNet = require(script.Parent:WaitForChild("ClientNet", 10))
local WindowDrag = require(script.Parent:WaitForChild("WindowDrag", 10))
local MenuBus = require(script.Parent:WaitForChild("MenuBus", 10))

local stateRemote = ClientNet.Get("MasteryState")
local actionRemote = ClientNet.Get("MasteryAction")
local resultRemote = ClientNet.Get("MasteryResult")

local GREEN, RED, GRAY, GOLD = "#6fdc7f", "#ff6b6b", "#aaaab8", "#ffd45e"
local theme = UITheme.For(player:GetAttribute("Faction"))

local gui = Instance.new("ScreenGui")
gui.Name = "MasteryGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.DisplayOrder = 12
gui.Parent = player:WaitForChild("PlayerGui", 10)

local launcherGui = Instance.new("ScreenGui")
launcherGui.Name = "MasteryLauncher"
launcherGui.ResetOnSpawn = false
launcherGui.DisplayOrder = 8
launcherGui.Parent = player:WaitForChild("PlayerGui", 10)

local HINT: { [string]: string } = {
	Tanque = "Aguanta el daño y protege al grupo",
	Guerrero = "Daño equilibrado cuerpo a cuerpo",
	Asesino = "Mucho daño, poca vida, muy veloz",
	Tirador = "Daño a larga distancia",
	Mago = "Daño en área",
	Curador = "Cura y apoya al equipo",
}

type RoleInfo = { Role: string, Points: number, Rank: number, HasLoadout: boolean }
local state: { Roles: { RoleInfo }, Current: string, Pass: boolean }? = nil
local win: Frame? = nil
local resultLabel: TextLabel? = nil

local function withDots(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if string.sub(out, 1, 1) == "." then
		out = string.sub(out, 2)
	end
	return out
end

local function bonusText(rank: number): string
	if rank <= 0 then
		return "Sin bono todavía"
	end
	local b = MasteryCatalog.StatsFor(rank)
	return string.format("+%.1f%% daño · +%.1f%% defensa · +%.1f%% vida", (b.Ataque or 0) * 100, (b.Defensa or 0) * 100, (b.Vida or 0) * 100)
end

local function build()
	theme = UITheme.For(player:GetAttribute("Faction"))
	if win then
		win:Destroy()
	end
	local w = UITheme.Frame(gui, theme, UDim2.fromOffset(500, 560), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), "window")
	win = w
	WindowDrag.Attach(w, "Mastery", 52, 50)
	UITheme.Text(w, "Maestría de rol", 20, theme.Primary, UDim2.fromOffset(18, 6), UDim2.fromOffset(340, 26))
	local hasPass = state ~= nil and state.Pass
	local sub = UITheme.Text(w, if hasPass then "Pase Maestría Multiclase activo" else "Cada rol sube su propio rango jugando con él", 12, Color3.fromRGB(170, 170, 185), UDim2.fromOffset(18, 30), UDim2.fromOffset(440, 16))
	sub.TextColor3 = if hasPass then Color3.fromRGB(255, 214, 90) else Color3.fromRGB(170, 170, 185)

	local close = Instance.new("TextButton")
	close.Position = UDim2.new(1, -38, 0, 8)
	close.Size = UDim2.fromOffset(28, 28)
	close.Text = "X"
	close.BackgroundTransparency = 1
	close.TextColor3 = Color3.fromRGB(255, 120, 120)
	close.Font = UITheme.Font
	close.TextSize = 18
	close.ZIndex = 30
	close.Parent = w
	close.Activated:Connect(function()
		gui.Enabled = false
	end)

	if not state then
		UITheme.Text(w, "Cargando…", 14, Color3.new(1, 1, 1), UDim2.fromOffset(18, 70), UDim2.fromOffset(300, 20))
		return
	end
	for i, info in ipairs(state.Roles) do
		local y = 56 + (i - 1) * 66
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(16, y)
		row.Size = UDim2.fromOffset(468, 60)
		row.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
		row.BorderSizePixel = 0
		row.Parent = w
		Instance.new("UICorner", row)
		local isCurrent = info.Role == state.Current
		local st = Instance.new("UIStroke")
		st.Color = if isCurrent then theme.Primary else Color3.fromRGB(70, 70, 85)
		st.Thickness = if isCurrent then 2 else 1
		st.Parent = row
		UITheme.Text(row, info.Role, 15, if isCurrent then Color3.fromRGB(255, 214, 90) else Color3.new(1, 1, 1), UDim2.fromOffset(10, 4), UDim2.fromOffset(120, 20))
		local rankTxt = UITheme.Text(row, string.format("Rango %d/%d", info.Rank, MasteryCatalog.MAX_RANK), 13, Color3.fromRGB(150, 220, 255), UDim2.fromOffset(120, 5), UDim2.fromOffset(110, 18))
		rankTxt.TextXAlignment = Enum.TextXAlignment.Left
		local cur, need = MasteryCatalog.Progress(info.Points)
		local barBg = Instance.new("Frame")
		barBg.Position = UDim2.fromOffset(10, 28)
		barBg.Size = UDim2.fromOffset(300, 8)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 52)
		barBg.BorderSizePixel = 0
		barBg.Parent = row
		Instance.new("UICorner", barBg)
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(math.clamp(cur / math.max(need, 1), 0, 1), 1)
		fill.BackgroundColor3 = if info.Rank >= MasteryCatalog.MAX_RANK then Color3.fromRGB(255, 205, 80) else theme.Primary
		fill.BorderSizePixel = 0
		fill.Parent = barBg
		Instance.new("UICorner", fill)
		UITheme.Text(row, if info.Rank >= MasteryCatalog.MAX_RANK then "MAESTRÍA MÁXIMA" else string.format("%s / %s", withDots(cur), withDots(need)), 10, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(320, 24), UDim2.fromOffset(140, 14))
		UITheme.Text(row, bonusText(info.Rank) .. (if info.HasLoadout then "   ·   ✔ equipo guardado" else ""), 11, Color3.fromRGB(165, 205, 170), UDim2.fromOffset(10, 40), UDim2.fromOffset(330, 16))
		if isCurrent then
			UITheme.Text(row, "ACTUAL", 11, Color3.fromRGB(255, 214, 90), UDim2.fromOffset(380, 8), UDim2.fromOffset(78, 16), Enum.TextXAlignment.Right)
		elseif state.Pass then
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(372, 14)
			b.Size = UDim2.fromOffset(88, 32)
			b.BackgroundColor3 = Color3.fromRGB(50, 130, 70)
			b.TextColor3 = Color3.new(1, 1, 1)
			b.Font = UITheme.Font
			b.TextSize = 13
			b.Text = "Cambiar"
			b.ZIndex = 30
			b.Parent = row
			Instance.new("UICorner", b)
			b.Activated:Connect(function()
				actionRemote:FireServer("Switch", info.Role)
			end)
		else
			UITheme.Text(row, "🔒 Pase", 11, Color3.fromRGB(150, 150, 165), UDim2.fromOffset(380, 22), UDim2.fromOffset(78, 16), Enum.TextXAlignment.Right)
		end
	end

	resultLabel = UITheme.Text(w, "", 13, nil, UDim2.fromOffset(18, 456), UDim2.fromOffset(464, 36))
	resultLabel.TextWrapped = true
	resultLabel.RichText = true
	resultLabel.TextYAlignment = Enum.TextYAlignment.Top

	if state.Pass then
		local info = UITheme.Text(w, "Tu equipo se guarda por rol y la maestría sube un 25% más rápido. No se puede cambiar en la Arena ni en combate.", 11, Color3.fromRGB(165, 165, 180), UDim2.fromOffset(18, 500), UDim2.fromOffset(464, 40))
		info.TextWrapped = true
		info.TextYAlignment = Enum.TextYAlignment.Top
	else
		local buy = Instance.new("TextButton")
		buy.Position = UDim2.fromOffset(18, 496)
		buy.Size = UDim2.fromOffset(464, 40)
		buy.BackgroundColor3 = Color3.fromRGB(140, 90, 200)
		buy.TextColor3 = Color3.new(1, 1, 1)
		buy.Font = UITheme.Font
		buy.TextSize = 13
		buy.TextWrapped = true
		buy.Text = "Maestría Multiclase: cambia de rol en cualquier lugar · equipo por rol · maestría +25%  →  Tienda"
		buy.ZIndex = 30
		buy.Parent = w
		Instance.new("UICorner", buy)
		buy.Activated:Connect(function()
			gui.Enabled = false
			MenuBus.Fire("Tienda")
		end)
	end
end

local function open()
	if gui.Enabled then
		gui.Enabled = false
		return
	end
	build()
	gui.Enabled = true
	actionRemote:FireServer("State")
end

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(s: any)
		if typeof(s) == "table" and typeof(s.Roles) == "table" then
			state = s
			if gui.Enabled then
				build()
			end
		end
	end)
end
if resultRemote then
	resultRemote.OnClientEvent:Connect(function(ok: any, text: any)
		if resultLabel and gui.Enabled then
			resultLabel.Text = string.format('<font color="%s"><b>%s</b></font>', if ok == true then GREEN else RED, tostring(text))
		end
	end)
end

-- botón flotante (izquierda) y tecla N
local btn = Instance.new("TextButton")
btn.AnchorPoint = Vector2.new(0, 0.5)
btn.Position = UDim2.new(0, 10, 0.70, 0)
btn.Size = UDim2.fromOffset(112, 34)
btn.BackgroundColor3 = Color3.fromRGB(70, 70, 130)
btn.TextColor3 = Color3.new(1, 1, 1)
btn.Font = UITheme.Font
btn.TextSize = 13
btn.Text = "⚔ Maestría [N]"
btn.Parent = launcherGui
Instance.new("UICorner", btn)
btn.Activated:Connect(open)
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.N then
		open()
	end
end)

player:GetAttributeChangedSignal("Pass_Multiclass"):Connect(function()
	actionRemote:FireServer("State")
end)
-- refresco suave mientras está abierta (los puntos suben al matar)
task.spawn(function()
	while true do
		task.wait(5)
		if gui.Enabled then
			actionRemote:FireServer("State")
		end
	end
end)

actionRemote:FireServer("State")
print("[MasteryClient] listo")
