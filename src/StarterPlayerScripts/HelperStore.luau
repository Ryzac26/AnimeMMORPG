--!strict
--[[
    HelperStore (ModuleScript) -> StarterPlayer > StarterPlayerScripts > HelperStore
    Estado de tus AYUDANTES en el cliente (lo envía HelperService por el remote HelperState). Lo usan HelperClient, RecruitClient y SettingsClient.
      Store.State     última foto: { Owned = { [id] = { S = estrellas, L = nivel, X = xp, N = xp para subir, G = equipo, Gp = poder del equipo } },
                                     Slots = { id|"" x3 }, Open = { bool x3 }, Pass, Stock = { [rareza] = n }, Mail = { [rareza] = n }, Pity, Pulls, DayCount, Level, Faction }
      Store.Changed   se dispara al llegar una foto nueva
      Store.Result    se dispara al terminar un reclutamiento: { Coupon, Results = { { Id, Rarity, New, Stars, Gold } }, Pity }
      Store.Action(a, b, c, d)  pide algo al servidor (HelperAction): "State" (abrí una ventana) · "Close" · "Equip", id, ranura · "Unequip", ranura ·
                                "Recruit", cupón, 1|10 · "ClaimMail", rareza|"all" · "GearEquip", id, hueco, casilla · "GearUnequip", id, hueco · "ExchangePets"
    Es un ModuleScript: sobrevive a la recarga de interfaz (UIReloadClient), así que la foto no se pierde.
]]
local ClientNet = require(script.Parent:WaitForChild("ClientNet"))

local changed = Instance.new("BindableEvent")
local result = Instance.new("BindableEvent")

local Store: {
	State: any,
	Changed: RBXScriptSignal,
	Result: RBXScriptSignal,
	Action: (...any) -> (),
} = {
	State = nil,
	Changed = changed.Event,
	Result = result.Event,
	Action = function(...: any) end,
}

local stateRemote = ClientNet.Get("HelperState")
local resultRemote = ClientNet.Get("HelperResult")
local actionRemote = ClientNet.Get("HelperAction")

if stateRemote then
	stateRemote.OnClientEvent:Connect(function(s: any)
		if type(s) == "table" then
			Store.State = s
			changed:Fire()
		end
	end)
end
if resultRemote then
	resultRemote.OnClientEvent:Connect(function(r: any)
		if type(r) == "table" then
			result:Fire(r)
		end
	end)
end
if actionRemote then
	Store.Action = function(...: any)
		actionRemote:FireServer(...)
	end
	task.defer(function()
		actionRemote:FireServer("Sync") -- primera foto (la que el servidor mandó al entrar pudo llegar antes de conectar)
	end)
end

return Store
