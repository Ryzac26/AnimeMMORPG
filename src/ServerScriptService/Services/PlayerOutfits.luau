--!strict
--[[
    PlayerOutfits (ModuleScript) -> ServerScriptService.Services.PlayerOutfits
    TRAJES DE LOS 18 PERSONAJES JUGABLES (según la hoja de diseños). Al aparecer el personaje del jugador, pone el kit del
    personaje que eligió (Faction + Role) sobre su avatar: pinta el cuerpo, quita la ropa del avatar y pega las piezas.
    Las piezas van soldadas a brazos/piernas, así que se mueven con las animaciones. Los colores salen de la hoja (disenos_personajes).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerClass = require(ReplicatedStorage.Modules.PlayerClass)
local MobBuilder = require(ServerScriptService.Services.Mobs.MobBuilder)
local MeshOutfits = require(ServerScriptService.Services.MeshOutfits)
local CharacterModels = require(ServerScriptService.Services.CharacterModels)

local Looks: { [string]: { [string]: any } } = {
	Piccolo = { Skin = Color3.fromHex("#5fa845"), Torso = Color3.fromHex("#6a3fa0"), Legs = Color3.fromHex("#6a3fa0"), Boots = Color3.fromHex("#4a2d78"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#6a3fa0"), Trim = Color3.fromHex("#4a2d78"), Belt = Color3.fromHex("#2a4fa8"), Shoulders = Color3.fromHex("#f2f2f2"), Wrists = Color3.fromHex("#2a4fa8"), BootCuff = Color3.fromHex("#2a4fa8"), Cape = Color3.fromHex("#f2f2f2"), Ears = Color3.fromHex("#5fa845"), Antenna = Color3.fromHex("#5fa845"), Brow = Color3.fromHex("#2b5a1c"), HatStyle = "turban", Hat = Color3.fromHex("#f2f2f2"), Scale = 1.08 },
	Goku = { Skin = Color3.fromHex("#efb98f"), Torso = Color3.fromHex("#f08a1c"), Legs = Color3.fromHex("#f08a1c"), Boots = Color3.fromHex("#2a4fa0"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#f08a1c"), Trim = Color3.fromHex("#c06a0c"), Belt = Color3.fromHex("#2a4fa0"), Sleeves = Color3.fromHex("#2a4fa0"), Wrists = Color3.fromHex("#2a4fa0"), WristTrim = Color3.fromHex("#f2c94a"), BootCuff = Color3.fromHex("#f2c94a"), Collar = Color3.fromHex("#2a4fa0"), Brow = Color3.fromHex("#15151c"), Emblem = Color3.fromHex("#f2f2f2"), Hair = Color3.fromHex("#15151c"), HairStyle = "spiky" },
	Vegeta = { Skin = Color3.fromHex("#efb98f"), Torso = Color3.fromHex("#1f3a8a"), Legs = Color3.fromHex("#1f3a8a"), Boots = Color3.fromHex("#f2f2f2"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#f2f2f2"), Trim = Color3.fromHex("#c9cad4"), Belly = Color3.fromHex("#e8c13a"), Belt = Color3.fromHex("#7a5a2a"), Shoulders = Color3.fromHex("#e8c13a"), Wrists = Color3.fromHex("#f2f2f2"), WristTrim = Color3.fromHex("#e8c13a"), Gloves = Color3.fromHex("#f2f2f2"), BootCuff = Color3.fromHex("#f2f2f2"), BootToe = Color3.fromHex("#e8c13a"), Brow = Color3.fromHex("#15151c"), Hair = Color3.fromHex("#15151c"), HairStyle = "tall" },
	Trunks = { Skin = Color3.fromHex("#efb98f"), Torso = Color3.fromHex("#1a1a24"), Legs = Color3.fromHex("#4b5878"), Boots = Color3.fromHex("#6a4a2a"), Eye = Color3.fromHex("#2a5a9a"), Trim = Color3.fromHex("#2f3f78"), Belt = Color3.fromHex("#3a2a1a"), Shoulders = Color3.fromHex("#6f86c4"), Wrists = Color3.fromHex("#1a1a24"), Gloves = Color3.fromHex("#3a2a1a"), BootCuff = Color3.fromHex("#3a2a1a"), Coat = Color3.fromHex("#6f86c4"), Collar = Color3.fromHex("#6f86c4"), Brow = Color3.fromHex("#7a5ab8"), BackSword = Color3.fromHex("#cfd6e0"), Emblem = Color3.fromHex("#e8c13a"), Hair = Color3.fromHex("#8f6fe0"), HairStyle = "trunks" },
	Gohan = { Skin = Color3.fromHex("#efb98f"), Torso = Color3.fromHex("#6b3fa0"), Legs = Color3.fromHex("#6b3fa0"), Boots = Color3.fromHex("#3a2a1a"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#6b3fa0"), Trim = Color3.fromHex("#4a2d78"), Belt = Color3.fromHex("#e07a1c"), Shoulders = Color3.fromHex("#f2f2f2"), Wrists = Color3.fromHex("#e07a1c"), BootCuff = Color3.fromHex("#e07a1c"), Cape = Color3.fromHex("#f2f2f2"), Brow = Color3.fromHex("#15151c"), Hair = Color3.fromHex("#15151c"), HairStyle = "messy" },
	Bulma = { Skin = Color3.fromHex("#f3c6a2"), Torso = Color3.fromHex("#f06fa0"), Legs = Color3.fromHex("#f3c6a2"), Boots = Color3.fromHex("#f2f2f2"), Eye = Color3.fromHex("#2a5a9a"), Chest = Color3.fromHex("#f06fa0"), Trim = Color3.fromHex("#b04a78"), Belt = Color3.fromHex("#7a4aa8"), Gloves = Color3.fromHex("#f2f2f2"), BootCuff = Color3.fromHex("#f06fa0"), Scarf = Color3.fromHex("#f2f2f2"), Brow = Color3.fromHex("#2a8a80"), Pouch = Color3.fromHex("#d03a3a"), Skirt = Color3.fromHex("#7a4aa8"), Hair = Color3.fromHex("#3fd2c2"), HairStyle = "bulma", Headband = Color3.fromHex("#f06fa0"), HeadbandPlate = false },
	Gaara = { Skin = Color3.fromHex("#efd2b8"), Torso = Color3.fromHex("#5a5a66"), Legs = Color3.fromHex("#3a3a46"), Boots = Color3.fromHex("#2a2a32"), Eye = Color3.fromHex("#2a8a80"), Chest = Color3.fromHex("#5a5a66"), Trim = Color3.fromHex("#2a2a32"), Belt = Color3.fromHex("#7a5a2a"), Wrists = Color3.fromHex("#e8e4d8"), Greaves = Color3.fromHex("#3a3a46"), Brow = Color3.fromHex("#7a1a1a"), Bandolier = Color3.fromHex("#7a5a2a"), Hair = Color3.fromHex("#b0302a"), HairStyle = "messy", Gourd = Color3.fromHex("#d9b878"), ForeheadMark = Color3.fromHex("#c0302b"), Scale = 1.06 },
	Naruto = { Skin = Color3.fromHex("#efc59a"), Torso = Color3.fromHex("#f08a1c"), Legs = Color3.fromHex("#f08a1c"), Boots = Color3.fromHex("#2a3a6a"), Eye = Color3.fromHex("#3a8ad8"), Chest = Color3.fromHex("#f08a1c"), Trim = Color3.fromHex("#2a3a6a"), Belt = Color3.fromHex("#2a3a6a"), Shoulders = Color3.fromHex("#2a3a6a"), Wrists = Color3.fromHex("#e8e4d8"), Greaves = Color3.fromHex("#e8e4d8"), Collar = Color3.fromHex("#2a3a6a"), Brow = Color3.fromHex("#d4a82a"), Pouch = Color3.fromHex("#c9b878"), Hair = Color3.fromHex("#f2c94a"), HairStyle = "spiky", Headband = Color3.fromHex("#2a3a6a"), Whiskers = Color3.fromHex("#6a3a1a") },
	Sasuke = { Skin = Color3.fromHex("#efd2b8"), Torso = Color3.fromHex("#e8e8f0"), Legs = Color3.fromHex("#2a2a3a"), Boots = Color3.fromHex("#1a1a22"), Eye = Color3.fromHex("#d03a3a"), Chest = Color3.fromHex("#e8e8f0"), Trim = Color3.fromHex("#9a9aae"), Belt = Color3.fromHex("#6a4aa0"), Wrists = Color3.fromHex("#e8e4d8"), Greaves = Color3.fromHex("#e8e4d8"), Collar = Color3.fromHex("#e8e8f0"), Brow = Color3.fromHex("#15151c"), BackSword = Color3.fromHex("#cfd6e0"), Sheath = Color3.fromHex("#2a2a2a"), Hair = Color3.fromHex("#15151c"), HairStyle = "swept" },
	Itachi = { Skin = Color3.fromHex("#efd2b8"), Torso = Color3.fromHex("#14141c"), Legs = Color3.fromHex("#14141c"), Boots = Color3.fromHex("#14141c"), Eye = Color3.fromHex("#d03a3a"), Trim = Color3.fromHex("#2a2a3a"), Coat = Color3.fromHex("#14141c"), Collar = Color3.fromHex("#14141c"), Brow = Color3.fromHex("#15151c"), Braid = Color3.fromHex("#15151c"), Marks = Color3.fromHex("#d03a3a"), Hair = Color3.fromHex("#15151c"), HairStyle = "round", Headband = Color3.fromHex("#2d2d3a"), HeadbandSlash = true },
	Kakashi = { Skin = Color3.fromHex("#efd2b8"), Torso = Color3.fromHex("#2a3a5a"), Legs = Color3.fromHex("#2a3a5a"), Boots = Color3.fromHex("#1a2a40"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#4a6a3a"), Trim = Color3.fromHex("#2a3a22"), Belt = Color3.fromHex("#2a2a2a"), Wrists = Color3.fromHex("#e8e4d8"), Gloves = Color3.fromHex("#14141c"), Greaves = Color3.fromHex("#e8e4d8"), Mask = Color3.fromHex("#2a3a5a"), Brow = Color3.fromHex("#9aa3b4"), Pouch = Color3.fromHex("#c9b878"), Hair = Color3.fromHex("#c9d0df"), HairStyle = "spiky", Headband = Color3.fromHex("#2a3a5a"), EyeCover = true },
	Sakura = { Skin = Color3.fromHex("#f3c6a2"), Torso = Color3.fromHex("#c0302b"), Legs = Color3.fromHex("#2a2a3a"), Boots = Color3.fromHex("#1a1a22"), Eye = Color3.fromHex("#2a8a60"), Chest = Color3.fromHex("#c0302b"), Trim = Color3.fromHex("#8a1a1a"), Belt = Color3.fromHex("#e8e4d8"), Wrists = Color3.fromHex("#2a2a3a"), Gloves = Color3.fromHex("#2a2a3a"), Greaves = Color3.fromHex("#2a2a3a"), Brow = Color3.fromHex("#c06a80"), Pouch = Color3.fromHex("#c9b878"), Emblem = Color3.fromHex("#f2f2f2"), Hair = Color3.fromHex("#f0a0b8"), HairStyle = "bob", Headband = Color3.fromHex("#c0302b") },
	Jinbe = { Skin = Color3.fromHex("#3a6aa0"), Torso = Color3.fromHex("#2a3a6a"), Legs = Color3.fromHex("#2a3a6a"), Boots = Color3.fromHex("#2a3a6a"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#2a3a6a"), Trim = Color3.fromHex("#1a2448"), Belt = Color3.fromHex("#e0b83a"), Shoulders = Color3.fromHex("#2a3a6a"), Wrists = Color3.fromHex("#e0b83a"), Greaves = Color3.fromHex("#2a3a6a"), Brow = Color3.fromHex("#15151c"), Fins = Color3.fromHex("#2a5a90"), Mustache = Color3.fromHex("#15151c"), Scale = 1.2 },
	Luffy = { Skin = Color3.fromHex("#efc59a"), Torso = Color3.fromHex("#efc59a"), Legs = Color3.fromHex("#2a4a9a"), Boots = Color3.fromHex("#7a5a2a"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#c0302b"), Trim = Color3.fromHex("#8a1a1a"), Belt = Color3.fromHex("#f2c94a"), BootCuff = Color3.fromHex("#7a5a2a"), Brow = Color3.fromHex("#15151c"), Hair = Color3.fromHex("#15151c"), HairStyle = "flat", HatStyle = "straw", Hat = Color3.fromHex("#e8c870"), HatBand = Color3.fromHex("#c0302b"), Scar = Color3.fromHex("#a05050"), ScarX = -0.3 },
	Zoro = { Skin = Color3.fromHex("#e0b08a"), Torso = Color3.fromHex("#e8e8ee"), Legs = Color3.fromHex("#2a2a2a"), Boots = Color3.fromHex("#1a1a1a"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#e8e8ee"), Trim = Color3.fromHex("#9a9aae"), Belt = Color3.fromHex("#3a8a3a"), Wrists = Color3.fromHex("#2a2a2a"), Brow = Color3.fromHex("#2a6a2a"), Sheath = Color3.fromHex("#2a2a2a"), Piercings = Color3.fromHex("#d9b73a"), Hair = Color3.fromHex("#3a8a3a"), HairStyle = "flat", Scar = Color3.fromHex("#a05050"), ScarX = -0.3 },
	Usopp = { Skin = Color3.fromHex("#d8a982"), Torso = Color3.fromHex("#f2d24a"), Legs = Color3.fromHex("#3a7a4a"), Boots = Color3.fromHex("#5a3a22"), Eye = Color3.fromHex("#161616"), Chest = Color3.fromHex("#3a7a4a"), Trim = Color3.fromHex("#245a32"), Belt = Color3.fromHex("#7a5a2a"), Wrists = Color3.fromHex("#7a5a2a"), BootCuff = Color3.fromHex("#7a5a2a"), LongNose = Color3.fromHex("#d8a982"), Brow = Color3.fromHex("#2a1d14"), Pouch = Color3.fromHex("#7a5a2a"), Goggles = Color3.fromHex("#d9c24a"), Bandolier = Color3.fromHex("#7a5a2a"), Hair = Color3.fromHex("#2a1d14"), HairStyle = "big", Backpack = Color3.fromHex("#8a6a3a") },
	Sanji = { Skin = Color3.fromHex("#efc59a"), Torso = Color3.fromHex("#e8e8ee"), Legs = Color3.fromHex("#14141c"), Boots = Color3.fromHex("#0c0c12"), Eye = Color3.fromHex("#161616"), Trim = Color3.fromHex("#2a2a3a"), Wrists = Color3.fromHex("#14141c"), Coat = Color3.fromHex("#14141c"), Collar = Color3.fromHex("#e8e8ee"), Scarf = Color3.fromHex("#3a6ab0"), Brow = Color3.fromHex("#c9a22a"), Hair = Color3.fromHex("#f2d24a"), HairStyle = "swoop", Cigarette = true },
	Chopper = { Skin = Color3.fromHex("#b06a3a"), Torso = Color3.fromHex("#b06a3a"), Legs = Color3.fromHex("#b06a3a"), Boots = Color3.fromHex("#7a4a22"), Eye = Color3.fromHex("#161616"), Belt = Color3.fromHex("#3a6ab0"), BootCuff = Color3.fromHex("#e8dcc0"), Horns = Color3.fromHex("#e8dcc0"), Nose = Color3.fromHex("#3a6ab0"), Brow = Color3.fromHex("#7a4a22"), HatStyle = "cap", Hat = Color3.fromHex("#e86a9a"), HatCross = Color3.fromHex("#f2f2f2"), Backpack = Color3.fromHex("#3a6ab0"), Scale = 0.6 },
	Chad = { Skin = Color3.fromHex("#b8825a"), Torso = Color3.fromHex("#2a2a38"), Legs = Color3.fromHex("#2a2a38"), Boots = Color3.fromHex("#1a1a22"), Eye = Color3.fromHex("#2a1d14"), Chest = Color3.fromHex("#2a2a38"), Trim = Color3.fromHex("#c9a02a"), Belt = Color3.fromHex("#c9a02a"), Wrists = Color3.fromHex("#3a3a4a"), Brow = Color3.fromHex("#14141c"), Hair = Color3.fromHex("#14141c"), HairStyle = "flat", Scale = 1.1 },
	Ichigo = { Skin = Color3.fromHex("#f0c8a0"), Torso = Color3.fromHex("#14141c"), Legs = Color3.fromHex("#14141c"), Boots = Color3.fromHex("#0c0c12"), Eye = Color3.fromHex("#7a4a22"), Chest = Color3.fromHex("#14141c"), Trim = Color3.fromHex("#f2f2f6"), Belt = Color3.fromHex("#f2f2f6"), Wrists = Color3.fromHex("#f2f2f6"), Greaves = Color3.fromHex("#f2f2f6"), Brow = Color3.fromHex("#d9822a"), BackSword = Color3.fromHex("#cfd6e0"), Sheath = Color3.fromHex("#2a2a2a"), Hair = Color3.fromHex("#f08a2a"), HairStyle = "spiky" },
	Yoruichi = { Skin = Color3.fromHex("#a0724e"), Torso = Color3.fromHex("#f08a2a"), Legs = Color3.fromHex("#2a2a38"), Boots = Color3.fromHex("#1a1a22"), Eye = Color3.fromHex("#d8a42a"), Chest = Color3.fromHex("#f08a2a"), Trim = Color3.fromHex("#14141c"), Belt = Color3.fromHex("#14141c"), Wrists = Color3.fromHex("#f2f2f6"), Brow = Color3.fromHex("#3a2a5a"), Hair = Color3.fromHex("#5a3a8a"), HairStyle = "straightLong" },
	Uryu = { Skin = Color3.fromHex("#f3d2b0"), Torso = Color3.fromHex("#f2f2f6"), Legs = Color3.fromHex("#f2f2f6"), Boots = Color3.fromHex("#f2f2f6"), Eye = Color3.fromHex("#3a5a9a"), Chest = Color3.fromHex("#f2f2f6"), Trim = Color3.fromHex("#58a8ff"), Belt = Color3.fromHex("#58a8ff"), Cape = Color3.fromHex("#f2f2f6"), Collar = Color3.fromHex("#58a8ff"), Brow = Color3.fromHex("#14141c"), Hair = Color3.fromHex("#14141c"), HairStyle = "swept" },
	Hitsugaya = { Skin = Color3.fromHex("#f3d6b8"), Torso = Color3.fromHex("#14141c"), Legs = Color3.fromHex("#14141c"), Boots = Color3.fromHex("#0c0c12"), Eye = Color3.fromHex("#2a8a8a"), Chest = Color3.fromHex("#14141c"), Trim = Color3.fromHex("#f2f2f6"), Belt = Color3.fromHex("#f2f2f6"), Coat = Color3.fromHex("#f2f2f6"), Brow = Color3.fromHex("#a8d8e8"), Hair = Color3.fromHex("#f2f2f6"), HairStyle = "spiky", Scale = 0.9 },
	Orihime = { Skin = Color3.fromHex("#f6d4b6"), Torso = Color3.fromHex("#f2f2f6"), Legs = Color3.fromHex("#d8d0e0"), Boots = Color3.fromHex("#e8e8f0"), Eye = Color3.fromHex("#6a5a4a"), Chest = Color3.fromHex("#f2f2f6"), Trim = Color3.fromHex("#f06fa0"), Belt = Color3.fromHex("#f06fa0"), Brow = Color3.fromHex("#7a4a22"), Hair = Color3.fromHex("#d9822a"), HairStyle = "big", Headband = Color3.fromHex("#58a8ff"), HeadbandPlate = false },
}

local WAIT_APPEARANCE = 8 -- segundos máx. esperando al avatar (si Roblox tarda, se viste igual)

local function dress(player: Player, char: Model)
	local t0 = os.clock()
	while char.Parent and not player:HasAppearanceLoaded() and os.clock() - t0 < WAIT_APPEARANCE do
		task.wait(0.1)
	end
	if not char.Parent or player.Character ~= char then
		return
	end
	local name = PlayerClass.Get(player).CharacterName
	local look = Looks[name]
	if not look then
		return
	end
	-- Cuerpo base DETERMINISTA: el avatar de cada jugador trae sus propias proporciones (alto, ancho, Rthro, ropa del catálogo).
	-- Se aplica una HumanoidDescription con escalas clásicas fijas y sin accesorios/ropa, así el traje siempre cae sobre las mismas medidas.
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and hum.RigType == Enum.HumanoidRigType.R15 then
		local okD, errD = pcall(function()
			local d = Instance.new("HumanoidDescription")
			d.HeightScale, d.WidthScale, d.DepthScale, d.HeadScale = 1, 1, 1, 1
			d.BodyTypeScale, d.ProportionScale = 0, 0
			d.Shirt, d.Pants, d.GraphicTShirt, d.Face = 0, 0, 0, 0
			d.HatAccessory, d.HairAccessory, d.FaceAccessory, d.NeckAccessory = "", "", "", ""
			d.ShouldersAccessory, d.FrontAccessory, d.BackAccessory, d.WaistAccessory = "", "", "", ""
			d.HeadColor, d.TorsoColor, d.LeftArmColor, d.RightArmColor = look.Skin, look.Torso, look.Arm or look.Skin, look.Arm or look.Skin
			d.LeftLegColor, d.RightLegColor = look.Legs, look.Legs
			hum:ApplyDescription(d)
		end)
		if not okD then
			warn("[PlayerOutfits] ApplyDescription falló: " .. tostring(errD))
		end
		if not char.Parent or player.Character ~= char then
			return
		end
	end
	-- Personaje completo (ServerStorage > CharacterModels > <Nombre>): si existe, se usa en lugar del traje de bloques
	if CharacterModels.Has(name) then
		local okC, doneC = pcall(CharacterModels.Apply, char, name)
		if okC and doneC then
			pcall(CharacterModels.Extras, char, name)
			char:SetAttribute("Outfit", name)
			return
		elseif not okC then
			warn("[PlayerOutfits] modelo completo: " .. tostring(doneC))
		end
	end
	local ok, err = pcall(MobBuilder.Dress, look, char)
	if ok and err == false then -- Dress devuelve false si el cuerpo aún no estaba completo: reintenta
		for _ = 1, 5 do
			task.wait(0.6)
			if not char.Parent or player.Character ~= char then
				return
			end
			ok, err = pcall(MobBuilder.Dress, look, char)
			if not (ok and err == false) then
				break
			end
		end
	end
	if ok and err == false then
		warn("[PlayerOutfits] no se pudo vestir (cuerpo incompleto) a " .. player.Name)
		return
	end
	-- Seguro anti-caída: el traje puede escalar al personaje (Jinbe x1.2). Si el cuerpo quedó bajo el piso, se sube encima.
	-- Se revisa varias veces porque la física reacomoda el cuerpo un instante después de escalarlo.
	local function keepAboveFloor()
		local root = char:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char }
		local hit = workspace:Raycast(root.Position + Vector3.new(0, 150, 0), Vector3.new(0, -400, 0), rp)
		if hit and root.Position.Y < hit.Position.Y + 1 then
			char:PivotTo(char:GetPivot() + Vector3.new(0, hit.Position.Y - root.Position.Y + 5, 0))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	keepAboveFloor()
	task.delay(0.4, keepAboveFloor)
	task.delay(1.5, keepAboveFloor)
	if ok then
		local okM, errM = pcall(MeshOutfits.Apply, char, name, look)
		if not okM then
			warn("[PlayerOutfits] piezas 3D: " .. tostring(errM))
		end
		pcall(CharacterModels.Extras, char, name)
		char:SetAttribute("Outfit", name)
	else
		warn("[PlayerOutfits] no se pudo vestir a " .. player.Name .. " como " .. name .. ": " .. tostring(err))
	end
end

local function hook(player: Player)
	player.CharacterAdded:Connect(function(char)
		task.spawn(dress, player, char)
	end)
	if player.Character then
		task.spawn(dress, player, player.Character)
	end
end

Players.PlayerAdded:Connect(hook)
for _, p in ipairs(Players:GetPlayers()) do
	hook(p)
end

return { Looks = Looks }
