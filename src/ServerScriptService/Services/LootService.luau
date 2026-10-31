--!strict
--[[
    LootService (ModuleScript) -> ServerScriptService.Services.LootService
    REPARTE EL BOTÍN. Escucha RewardService.MobKilled(mobId, nivel, participantes, partes) y entrega a cada jugador:
        Mob normal   : oro siempre · 30% objeto (poción o material) · 2% equipo · 0.08% mascota
        Metin        : oro + puntos de facción · 45% Gema · 17% "cofre" (tirada extra de equipo alto) · 4% Emblema de tu facción · 1% mascota
        Jefe de franja / Jefe mundial : TODOS los participantes reciben oro, puntos y materiales garantizados;
                       además hay un SORTEO de un objeto Épico/Legendario entre los participantes: no tocan a todos.
    Todos los números viven en ReplicatedStorage.Modules.LootTables. Las reglas de reparto "parejo":
      - Botín personal: cada jugador con suficiente participación (% del daño) tira por su cuenta.
      - El equipo se RESUELVE a quien lo recibe (su rol y su arma de facción), así nunca cae algo inútil.
      - Sorteo: boletos iguales para todos (+ un extra pequeño por daño) y "pity": cada sorteo perdido suma boletos, al ganar se reinicia.
      - La Suerte de la mascota "Zorro" multiplica las probabilidades (no el oro ni lo garantizado ni el sorteo).
      - Los monstruos invocados no dan botín (RewardService ya los descarta).
    Avisos: un solo mensaje por jugador y muerte (Notify). Un mob normal solo avisa si soltó algo (el oro se ve en el HUD).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage.Modules
local ItemCatalog = require(Modules.ItemCatalog)
local GearCatalog = require(Modules.GearCatalog)
local LootTables = require(Modules.LootTables)
local MobCatalog = require(Modules.MobCatalog)
local PlayerClass = require(Modules.PlayerClass)

local Services = ServerScriptService.Services
local Net = require(Services.Net)
local RewardService = require(Services.RewardService)
local Inventory = require(Services.InventoryService)
local Wallet = require(Services.WalletService)
local GearService = require(Services.GearService)
local PlayerData = require(Services.PlayerData)

local NotifyRemote = Net.Get("Notify")
local rng = Random.new()

local MAX_CHANCE = 0.95 -- ni con toda la suerte del mundo algo es seguro

local function chance(p: number, luck: number): number
	return math.min(MAX_CHANCE, p * (1 + luck))
end

---------------------------------------------------------------------
-- Entrega
---------------------------------------------------------------------
type Haul = { Gold: number, Points: number, Items: { { Id: string, Count: number } }, Notable: boolean }

local function newHaul(): Haul
	return { Gold = 0, Points = 0, Items = {}, Notable = false }
end

local function addItem(h: Haul, id: string?, count: number, notable: boolean)
	if id then
		table.insert(h.Items, { Id = id, Count = count })
		if notable then
			h.Notable = true
		end
	end
end

local function label(id: string, count: number): string
	local item = (ItemCatalog.Items :: any)[id]
	if not item then
		return id
	end
	local text = item.Name
	if item.Gear or item.Pet then
		text = string.format("[%s] %s", GearCatalog.RarityName[item.Rarity] or item.Rarity, item.Name)
	end
	if count > 1 then
		text ..= " x" .. count
	end
	return text
end

local function notify(player: Player, text: string)
	NotifyRemote:FireClient(player, text)
end

-- Entrega el botín y avisa. alwaysNotify = jefes y Metin (siempre); mob normal = solo si cayó un objeto.
local function deliver(player: Player, h: Haul, header: string, alwaysNotify: boolean)
	local parts: { string } = {}
	local gold = Wallet.AddGold(player, h.Gold)
	if gold > 0 then
		table.insert(parts, string.format("+%d oro", gold))
	end
	local points = Wallet.AddFactionPoints(player, h.Points)
	if points > 0 then
		table.insert(parts, string.format("+%d pts de facción", points))
	end
	local gotItems = false
	for _, entry in ipairs(h.Items) do
		if Inventory.Add(player, entry.Id, entry.Count) then
			gotItems = true
			table.insert(parts, label(entry.Id, entry.Count))
		end
	end
	if #parts > 0 and (alwaysNotify or gotItems) then
		notify(player, header .. ": " .. table.concat(parts, " · "))
	end
	if h.Notable and gotItems then
		PlayerData.Save(player) -- un premio importante no debe esperar al próximo autoguardado
	end
end

local function goldFor(player: Player, level: number, mult: number): number
	return math.floor(LootTables.GoldFor(level, mult, rng) * GearService.GoldMult(player))
end

local function classOf(player: Player): (string, string)
	local class = PlayerClass.Get(player)
	return class.Faction, class.Role
end

local function sharesOf(participants: { Player }, shares: { [Player]: number }?): { [Player]: number }
	local out: { [Player]: number } = {}
	for _, pl in ipairs(participants) do
		out[pl] = if shares and shares[pl] then shares[pl] else 1 / #participants
	end
	return out
end

---------------------------------------------------------------------
-- Sorteo de jefe (objeto Épico/Legendario: no toca a todos)
---------------------------------------------------------------------
local function runLottery(participants: { Player }, shares: { [Player]: number }, cfg: any, prizeRarity: { [string]: number }, level: number, title: string)
	local entries: { { Key: any, Tickets: number } } = {}
	for _, pl in ipairs(participants) do
		table.insert(entries, { Key = pl, Tickets = LootTables.Tickets(shares[pl] or 0, Wallet.GetPity(pl, "Boss")) })
	end
	local count = LootTables.WinnerCount(#participants, cfg.WinnerFraction, cfg.MinWinners, cfg.MaxWinners)
	local isWinner: { [Player]: boolean } = {}
	for _, key in ipairs(LootTables.Draw(entries, count, rng)) do
		isWinner[key :: Player] = true
	end
	for _, pl in ipairs(participants) do
		if isWinner[pl] then
			local faction, role = classOf(pl)
			local id = LootTables.RollGear(faction, role, level, prizeRarity, rng)
			if id and Inventory.Add(pl, id, 1) then
				Wallet.SetPity(pl, "Boss", 0)
				notify(pl, string.format("¡Ganaste el sorteo del %s! %s", title, label(id, 1)))
				PlayerData.Save(pl)
			end
		else
			local L = LootTables.Lottery
			Wallet.SetPity(pl, "Boss", math.min(L.PityMax, Wallet.GetPity(pl, "Boss") + L.PityStep))
			notify(pl, string.format("Sorteo del %s: esta vez no hubo suerte (la próxima tendrás más boletos)", title))
		end
	end
end

---------------------------------------------------------------------
-- Cada tipo de muerte
---------------------------------------------------------------------
local function onMob(level: number, strip: number, participants: { Player }, shares: { [Player]: number })
	local M = LootTables.Mob
	for _, pl in ipairs(participants) do
		if pl.Parent and (shares[pl] or 0) >= M.MinShare then
			local luck = GearService.Luck(pl)
			local faction, role = classOf(pl)
			local h = newHaul()
			h.Gold = goldFor(pl, level, 1)
			if rng:NextNumber() < chance(M.ItemChance, luck) then
				if LootTables.Pick(M.ItemWeights, rng) == "Consumible" then
					local id = if rng:NextNumber() < 0.6 then "Pocion_Vida" else "Pocion_Energia"
					addItem(h, id, LootTables.Count(M.ConsumableCount, rng), false)
				else
					local id = if rng:NextNumber() < M.FragmentShare then "Mat_FragArmadura" else LootTables.StripMaterial[strip]
					addItem(h, id, LootTables.Count(M.MaterialCount, rng), false)
				end
			end
			if rng:NextNumber() < chance(M.GearChance, luck) then
				addItem(h, LootTables.RollGear(faction, role, level, M.GearRarity, rng), 1, true)
			end
			if rng:NextNumber() < chance(M.PetChance, luck) then
				addItem(h, LootTables.RollPet(M.PetRarity, rng), 1, true)
			end
			deliver(pl, h, "Botín", false)
		end
	end
end

local function onBoss(cfg: any, level: number, strip: number?, participants: { Player }, shares: { [Player]: number }, title: string)
	for _, pl in ipairs(participants) do
		if pl.Parent then
			local luck = GearService.Luck(pl)
			local h = newHaul()
			h.Gold = goldFor(pl, level, cfg.GoldMult)
			h.Points = cfg.FactionPoints
			if strip then -- jefe de franja
				addItem(h, LootTables.StripMaterial[strip], LootTables.Count(cfg.StripCount, rng), false)
				addItem(h, "Mat_FragArmadura", LootTables.Count(cfg.FragmentCount, rng), false)
			else -- jefe mundial
				addItem(h, "Mat_Escama", LootTables.Count(cfg.ScaleCount, rng), false)
			end
			if rng:NextNumber() < chance(cfg.PetChance, luck) then
				addItem(h, LootTables.RollPet(cfg.PetRarity, rng), 1, true)
			end
			deliver(pl, h, "Jefe derrotado", true)
		end
	end
	local prize = if strip then cfg.PrizeRarity[strip] else cfg.PrizeRarity
	runLottery(participants, shares, cfg, prize, level, title)
end

local function onMetin(rarityId: string, level: number, participants: { Player }, shares: { [Player]: number })
	local X = LootTables.Metin
	local R = X.Rarities[rarityId]
	if not R then
		return
	end
	for _, pl in ipairs(participants) do
		if pl.Parent and (shares[pl] or 0) >= X.MinShare then
			local luck = GearService.Luck(pl)
			local faction, role = classOf(pl)
			local h = newHaul()
			h.Gold = goldFor(pl, level, R.GoldMult)
			h.Points = R.FactionPoints
			if rng:NextNumber() < chance(X.GemChance, luck) then
				addItem(h, "Mat_Gema", LootTables.Count(R.GemCount, rng), false)
			end
			if rng:NextNumber() < chance(X.ChestChance, luck) then
				addItem(h, LootTables.RollGear(faction, role, level, R.ChestRarity, rng), 1, true)
			end
			if rng:NextNumber() < chance(X.EmblemChance, luck) then
				addItem(h, LootTables.RollEmblem(faction, level, R.EmblemRarity, rng), 1, true)
			end
			if rng:NextNumber() < chance(X.PetChance, luck) then
				addItem(h, LootTables.RollPet(R.PetRarity, rng), 1, true)
			end
			deliver(pl, h, "Metin destruido", true)
		end
	end
end

---------------------------------------------------------------------
-- Conexión con RewardService
---------------------------------------------------------------------
local function onKilled(mobId: string, level: number, participants: { Player }, rawShares: { [Player]: number }?)
	if #participants == 0 then
		return
	end
	local shares = sharesOf(participants, rawShares)
	if mobId == "WorldBoss" then
		onBoss(LootTables.WorldBoss, level, nil, participants, shares, "jefe mundial")
	elseif string.sub(mobId, 1, 6) == "Metin_" then
		onMetin(string.sub(mobId, 7), level, participants, shares)
	else
		local def: any = (MobCatalog.ById :: any)[mobId]
		local strip = if def then def.Strip else math.clamp(math.ceil(level / 25), 1, 4)
		if def and def.Boss then
			onBoss(LootTables.EliteBoss, level, strip, participants, shares, "jefe")
		else
			onMob(level, strip, participants, shares)
		end
	end
end

RewardService.MobKilled:Connect(onKilled)

-- API por si otro sistema (misiones, eventos) quiere repartir con las mismas reglas
local LootService = {}
LootService.OnKilled = onKilled

return LootService
