--!strict
--[[
    ContributionService (ModuleScript) -> ServerScriptService.Services.ContributionService
    APORTE DE GRUPO: el XP y el botín ya no dependen SOLO del daño. Además del daño cuentan:
      - TANQUE   : daño que recibió DE ESE monstruo (Taken).
      - SOPORTE  : curación real hecha, escudos dados y apoyo (auras, guardias, revivir, provocar...) en los últimos SUPPORT_WINDOW s.
    Al morir un monstruo, RewardService pide Shares(mob, damageByPlayer, mobPos): cada categoría reparte su parte entre quienes la hicieron
    y se mezclan con W (si una categoría no existe en ese combate, su peso se reparte entre las demás: jugando solo todo es tuyo).
    Anti-abuso: el apoyo solo cuenta si el jugador está cerca del monstruo al morir (SUPPORT_RANGE) y se limita por evento.
]]
local Players = game:GetService("Players")

local C = {}

C.W = { Damage = 0.60, Taken = 0.25, Support = 0.15 }
C.SUPPORT_WINDOW = 20 -- s
C.SUPPORT_RANGE = 90 -- studs al morir el monstruo
C.MIN_SHARE_ELIGIBLE = 0.05 -- para el jefe: aporte mínimo (en cualquier categoría) para recibir premio

local taken: { [Model]: { [Player]: number } } = {}
local support: { [Player]: { { T: number, V: number } } } = {}

-- daño que un monstruo le hizo a un jugador (ya mitigado)
function C.Taken(mob: Model, victim: Player, amount: number)
	if amount <= 0 then
		return
	end
	local t = taken[mob]
	if not t then
		t = {}
		taken[mob] = t
	end
	t[victim] = (t[victim] or 0) + amount
end

-- apoyo: `amount` ya en unidades de vida (curación efectiva, escudo...). Se guarda con su hora.
function C.Support(player: Player, amount: number)
	if amount <= 0 or amount ~= amount then
		return
	end
	local list = support[player]
	if not list then
		list = {}
		support[player] = list
	end
	table.insert(list, { T = os.clock(), V = amount })
	if #list > 200 then
		table.remove(list, 1)
	end
end

local function recentSupport(player: Player): number
	local list = support[player]
	if not list then
		return 0
	end
	local now = os.clock()
	local sum = 0
	for i = #list, 1, -1 do
		if now - list[i].T <= C.SUPPORT_WINDOW then
			sum += list[i].V
		else
			table.remove(list, i)
		end
	end
	return sum
end

function C.Forget(mob: Model)
	taken[mob] = nil
end

-- Reparto final: devuelve shares[player] (suman 1) y la lista de quienes participaron en alguna categoría
function C.Shares(mob: Model, damage: { [Player]: number }, mobPos: Vector3?): ({ [Player]: number }, { [Player]: { Damage: number, Taken: number, Support: number } })
	local cats: { Damage: { [Player]: number }, Taken: { [Player]: number }, Support: { [Player]: number } } = { Damage = {}, Taken = {}, Support = {} }
	local totals = { Damage = 0, Taken = 0, Support = 0 }
	for pl, v in pairs(damage) do
		if pl.Parent and v > 0 then
			cats.Damage[pl] = v
			totals.Damage += v
		end
	end
	for pl, v in pairs(taken[mob] or {}) do
		if pl.Parent and v > 0 then
			cats.Taken[pl] = v
			totals.Taken += v
		end
	end
	taken[mob] = nil
	for _, pl in ipairs(Players:GetPlayers()) do
		local s = recentSupport(pl)
		if s > 0 then
			local near = true
			if mobPos then
				local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
				near = r ~= nil and r:IsA("BasePart") and (r.Position - mobPos).Magnitude <= C.SUPPORT_RANGE
			end
			if near then
				cats.Support[pl] = s
				totals.Support += s
			end
		end
	end
	-- pesos: solo cuentan las categorías que existen en este combate
	local wsum = 0
	for k, w in pairs(C.W) do
		if (totals :: any)[k] > 0 then
			wsum += w
		end
	end
	local shares: { [Player]: number } = {}
	local detail: { [Player]: { Damage: number, Taken: number, Support: number } } = {}
	if wsum <= 0 then
		return shares, detail
	end
	for k, w in pairs(C.W) do
		local tot = (totals :: any)[k]
		if tot > 0 then
			for pl, v in pairs((cats :: any)[k]) do
				local part = (v / tot)
				shares[pl] = (shares[pl] or 0) + (w / wsum) * part
				local d = detail[pl]
				if not d then
					d = { Damage = 0, Taken = 0, Support = 0 }
					detail[pl] = d
				end
				(d :: any)[k] = part
			end
		end
	end
	return shares, detail
end

Players.PlayerRemoving:Connect(function(pl)
	support[pl] = nil
end)

return C
