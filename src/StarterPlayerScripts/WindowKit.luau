--!strict
--[[
    WindowKit (ModuleScript) -> StarterPlayer > StarterPlayerScripts > WindowKit
    Imágenes de ventanas por facción (kit "ventanas.zip"). WindowKit.Get("Saiyan"|"Shinobi"|"Pirate"|"Shinigami")
    -> { frame, header, tabOn, tabOff, card, close, emblem, cardTall, TabOnText, TabOffText, CardText }
]]
local WindowKit = {}
local IDS: { [string]: { [string]: any } } = {
	Saiyan = {
		frame = "rbxassetid://90373394364632",
		header = "rbxassetid://113667684032221",
		tabOn = "rbxassetid://110800430662713",
		tabOff = "rbxassetid://83251054785123",
		card = "rbxassetid://96023649571639",
		close = "rbxassetid://84944427879834",
		emblem = "rbxassetid://132556779687160",
		cardTall = "rbxassetid://117924459282470",
	},
	Shinobi = {
		frame = "rbxassetid://92868356042823",
		header = "rbxassetid://106660791656940",
		tabOn = "rbxassetid://113419140916413",
		tabOff = "rbxassetid://98749741857871",
		card = "rbxassetid://111365947176087",
		close = "rbxassetid://123989230636504",
		emblem = "rbxassetid://99865820838522",
		cardTall = "rbxassetid://116612848448685",
	},
	Pirate = {
		frame = "rbxassetid://137248018096779",
		header = "rbxassetid://70535246525903",
		tabOn = "rbxassetid://135717994008457",
		tabOff = "rbxassetid://109016881777890",
		card = "rbxassetid://77033473189892",
		close = "rbxassetid://107833600375160",
		emblem = "rbxassetid://103044019674353",
		cardTall = "rbxassetid://87101813163038",
	},
	Shinigami = {
		frame = "rbxassetid://90086658404231",
		header = "rbxassetid://93055677966912",
		tabOn = "rbxassetid://139113320414245",
		tabOff = "rbxassetid://77404841397874",
		card = "rbxassetid://112491524615803",
		close = "rbxassetid://94330801348307",
		emblem = "rbxassetid://109848627686773",
		cardTall = "rbxassetid://87419872984363",
	},
}
-- colores de texto que se leen bien sobre cada imagen
local TXT: { [string]: { [string]: Color3 } } = {
	Saiyan = { TabOnText = Color3.fromRGB(255, 244, 200), TabOffText = Color3.fromRGB(190, 198, 220) },
	Shinobi = { TabOnText = Color3.fromRGB(60, 30, 20), TabOffText = Color3.fromRGB(96, 70, 40) },
	Pirate = { TabOnText = Color3.fromRGB(255, 240, 205), TabOffText = Color3.fromRGB(226, 200, 150) },
	Shinigami = { TabOnText = Color3.fromRGB(245, 240, 255), TabOffText = Color3.fromRGB(176, 164, 214) },
}
for f, t in pairs(TXT) do
	for k, v in pairs(t) do
		IDS[f][k] = v
	end
end
function WindowKit.Get(faction: string): { [string]: any }?
	return IDS[faction]
end
return WindowKit
