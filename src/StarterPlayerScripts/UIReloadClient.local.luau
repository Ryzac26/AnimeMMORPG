--!strict
--[[
    UIReloadClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > UIReloadClient
    Cuando cambia tu Facción o tu Rol (selección de clase o comando /clase), reconstruye toda la interfaz con la facción nueva:
    destruye las pantallas actuales y vuelve a ejecutar los scripts de interfaz (se clonan: el clon arranca de cero).
    Si agregas un script de interfaz nuevo, súmalo a la lista RELOAD.
]]
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local RELOAD = { "HudClient", "AutoFarmClient", "BoostClient", "PartyClient", "InventoryClient", "CharacterClient", "ShrineClient", "MobileClient", "SmithClient", "GearAlertClient", "ShopClient", "ClassChangeClient", "TiendaClient", "AlquimiaClient", "BossBarClient", "DeathScreenClient", "DamageRankClient", "SettingsClient", "PetClient", "MountClient", "MasteryClient", "GuildClient", "HouseClient", "MissionClient", "SkillsClient", "ProbabilityClient", "TitleClient", "MilestoneClient", "TalentClient", "VipShopClient", "ReportClient" }
local KEEP_GUIS = { ClassSelect = true, ClassSelectGui = true, PatchNotesGui = true, PatchNotes = true, LoadingScreen = true, TouchGui = true }

local token = 0
local lastFaction = player:GetAttribute("Faction")
local lastRole = player:GetAttribute("Role")

local function reload()
	local scripts = script.Parent
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local clones: { LocalScript } = {}
	for _, name in ipairs(RELOAD) do
		local s = scripts:FindFirstChild(name)
		if s and s:IsA("LocalScript") then
			local c = s:Clone()
			s:Destroy() -- al destruirlo se desconectan sus eventos
			table.insert(clones, c)
		end
	end
	for _, g in ipairs(gui:GetChildren()) do
		if g:IsA("ScreenGui") and not KEEP_GUIS[g.Name] then
			g:Destroy()
		end
	end
	task.wait(0.15)
	for _, c in ipairs(clones) do
		c.Parent = scripts
	end
end

local function changed()
	local f, r = player:GetAttribute("Faction"), player:GetAttribute("Role")
	if f == lastFaction and r == lastRole then
		return
	end
	lastFaction, lastRole = f, r
	if typeof(f) ~= "string" or typeof(r) ~= "string" then
		return
	end
	token += 1
	local mine = token
	task.delay(1.2, function() -- espera a que lleguen los dos atributos y reaparezca el personaje
		if mine == token then
			reload()
		end
	end)
end

player:GetAttributeChangedSignal("Faction"):Connect(changed)
player:GetAttributeChangedSignal("Role"):Connect(changed)
