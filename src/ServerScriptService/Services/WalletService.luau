--!strict
--[[
    WalletService (ModuleScript) -> ServerScriptService.Services.WalletService
    Billetera de cada jugador: ORO y PUNTOS DE FACCIÓN. Se guarda en PlayerData (sección "Wallet").
    También guarda el contador de mala suerte ("Pity") del sorteo de jefes.
      Get(player) -> { Gold, FactionPoints, Pity } o nil si aún no cargó
      AddGold(player, n) / AddFactionPoints(player, n) -> cantidad sumada (0 si aún no cargó)
      TrySpendGold(player, n) -> bool      (para tiendas futuras; nunca deja saldo negativo)
      GetPity(player, clave) / SetPity(player, clave, valor)
    Cada cambio se refleja en atributos del jugador (Gold, FactionPoints): el cliente los lee sin remotes (WalletClient).
]]
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData = require(ServerScriptService.Services.PlayerData)

export type Wallet = { Gold: number, FactionPoints: number, Pity: { [string]: number } }

local WalletService = {}
local wallets: { [Player]: Wallet } = {}

local function push(player: Player)
	local w = wallets[player]
	if w then
		player:SetAttribute("Gold", w.Gold)
		player:SetAttribute("FactionPoints", w.FactionPoints)
	end
end

function WalletService.Get(player: Player): Wallet?
	return wallets[player]
end

function WalletService.AddGold(player: Player, amount: number): number
	local w = wallets[player]
	local n = math.floor(amount)
	if not w or n <= 0 then
		return 0
	end
	w.Gold += n
	push(player)
	return n
end

function WalletService.AddFactionPoints(player: Player, amount: number): number
	local w = wallets[player]
	local n = math.floor(amount)
	if not w or n <= 0 then
		return 0
	end
	w.FactionPoints += n
	push(player)
	return n
end

function WalletService.TrySpendGold(player: Player, amount: number): boolean
	local w = wallets[player]
	local n = math.floor(amount)
	if not w or n <= 0 or w.Gold < n then
		return false
	end
	w.Gold -= n
	push(player)
	return true
end

function WalletService.GetPity(player: Player, key: string): number
	local w = wallets[player]
	return if w then (w.Pity[key] or 0) else 0
end

function WalletService.SetPity(player: Player, key: string, value: number)
	local w = wallets[player]
	if w then
		w.Pity[key] = math.max(0, value)
	end
end

local function load(player: Player)
	local saved = PlayerData.WaitForData(player)
	if not saved or player.Parent == nil then
		return -- la carga falló (el jugador es expulsado) o ya salió
	end
	local w: Wallet = { Gold = 0, FactionPoints = 0, Pity = {} }
	local section: any = saved.Wallet
	if typeof(section) == "table" then
		w.Gold = math.max(0, math.floor(tonumber(section.Gold) or 0))
		w.FactionPoints = math.max(0, math.floor(tonumber(section.FactionPoints) or 0))
		local pity: any = section.Pity
		if typeof(pity) == "table" then
			for key, value in pairs(pity) do
				if typeof(key) == "string" and typeof(value) == "number" then
					w.Pity[key] = math.max(0, value)
				end
			end
		end
	end
	wallets[player] = w
	push(player)
end

-- Qué guarda PlayerData de este servicio (nil = todavía no cargó: no se toca la sección)
PlayerData.RegisterSerializer("Wallet", function(player: Player): any?
	local w = wallets[player]
	if not w then
		return nil
	end
	local pity: { [string]: number } = {}
	for key, value in pairs(w.Pity) do
		pity[key] = value
	end
	return { Gold = w.Gold, FactionPoints = w.FactionPoints, Pity = pity }
end)

-- PlayerData avisa DESPUÉS de tomar la foto final de datos: ahora sí se puede limpiar
PlayerData.Releasing:Connect(function(player: Player)
	wallets[player] = nil
end)

Players.PlayerAdded:Connect(function(pl)
	task.spawn(load, pl)
end)
for _, pl in ipairs(Players:GetPlayers()) do
	task.spawn(load, pl)
end

return WalletService
