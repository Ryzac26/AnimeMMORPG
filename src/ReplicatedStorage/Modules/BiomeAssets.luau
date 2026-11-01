--!strict
--[[
    BiomeAssets (ModuleScript) -> ReplicatedStorage > Modules > BiomeAssets
    IDs de las imágenes de los biomas (franjas PvE) y el ambiente (luz, niebla, cielo) de cada zona.
    Déjalas vacías ("") y todo se ve igual con materiales y colores; al pegar un ID se usa esa imagen.
    Pega solo el número (o rbxassetid://número). Deben ser IDs de IMAGEN (no de Decal).

    Nombres:
      <Facción>_<1-4>_floor   textura repetible del suelo de esa franja (512x512)
      <Facción>_<1-4>_wall    textura repetible del muro de esa franja (512x512)
      <Facción>_banner        bandera vertical (512x1024)
      <Facción>_sky<A|B>_<ft|bk|lf|rt|up|dn>   las 6 caras del cielo (cada franja usa A o B, ver Zones más abajo)
]]
local IDS: { [string]: string } = {
	Saiyan_1_floor = "97208414213951",
	Saiyan_2_floor = "130660233295959",
	Saiyan_3_floor = "132771256732269",
	Saiyan_4_floor = "119267066210705",
	Shinobi_1_floor = "91819467782429",
	Shinobi_2_floor = "71586298818569",
	Shinobi_3_floor = "70800007832313",
	Shinobi_4_floor = "110267747250957",
	Pirate_1_floor = "101965625117593",
	Pirate_2_floor = "130362664171431",
	Pirate_3_floor = "134731718034476",
	Pirate_4_floor = "111420119526259",
	Shinigami_1_floor = "82494534619684",
	Shinigami_2_floor = "137422621474192",
	Shinigami_3_floor = "71008328696465",
	Shinigami_4_floor = "95091960178725",
	Saiyan_1_wall = "7746919026110",
	Saiyan_2_wall = "117002942127872",
	Saiyan_3_wall = "73496820664804",
	Saiyan_4_wall = "96227981805910",
	Shinobi_1_wall = "131854436768228",
	Shinobi_2_wall = "82121090077643",
	Shinobi_3_wall = "104688494642659",
	Shinobi_4_wall = "128053857956998",
	Pirate_1_wall = "80292620174954",
	Pirate_2_wall = "98927067545706",
	Pirate_3_wall = "133461961685260",
	Pirate_4_wall = "104653008858964",
	Shinigami_1_wall = "112762615907659",
	Shinigami_2_wall = "101252941776834",
	Shinigami_3_wall = "79985961312697",
	Shinigami_4_wall = "82565296604286",
	Saiyan_banner = "102658964033917",
	Shinobi_banner = "128868982084181",
	Pirate_banner = "90685345936788",
	Shinigami_banner = "108366366461423",
	Saiyan_skyA_ft = "92047106160637",
	Saiyan_skyA_bk = "115825533224125",
	Saiyan_skyA_lf = "126343187011874",
	Saiyan_skyA_rt = "110746843454532",
	Saiyan_skyA_up = "70437016811164",
	Saiyan_skyA_dn = "90379088764230",
	Saiyan_skyB_ft = "129213770452208",
	Saiyan_skyB_bk = "137938519613344",
	Saiyan_skyB_lf = "118055965272419",
	Saiyan_skyB_rt = "85476322744058",
	Saiyan_skyB_up = "73444900842420",
	Saiyan_skyB_dn = "116791604917430",
	Shinobi_skyA_ft = "74189011461846",
	Shinobi_skyA_bk = "111166169991613",
	Shinobi_skyA_lf = "110399530997107",
	Shinobi_skyA_rt = "97811055605664",
	Shinobi_skyA_up = "90103121338439",
	Shinobi_skyA_dn = "114765132340992",
	Shinobi_skyB_ft = "89876238193625",
	Shinobi_skyB_bk = "103273574212082",
	Shinobi_skyB_lf = "73761017539714",
	Shinobi_skyB_rt = "94234022767224",
	Shinobi_skyB_up = "80259221081130",
	Shinobi_skyB_dn = "92350659983256",
	Pirate_skyA_ft = "83292635391361",
	Pirate_skyA_bk = "70568977921891",
	Pirate_skyA_lf = "112046489315240",
	Pirate_skyA_rt = "73203389744904",
	Pirate_skyA_up = "104732187868452",
	Pirate_skyA_dn = "96003481111296",
	Pirate_skyB_ft = "127695158980678",
	Pirate_skyB_bk = "123280244166662",
	Pirate_skyB_lf = "115421830059671",
	Pirate_skyB_rt = "94684571163507",
	Pirate_skyB_up = "135635018506003",
	Pirate_skyB_dn = "102331754838791",
	Shinigami_skyA_ft = "75700918640329",
	Shinigami_skyA_bk = "89180756641115",
	Shinigami_skyA_lf = "84299326201275",
	Shinigami_skyA_rt = "130115951272887",
	Shinigami_skyA_up = "131686684921838",
	Shinigami_skyA_dn = "92694616045571",
	Shinigami_skyB_ft = "106897424398256",
	Shinigami_skyB_bk = "71027618377285",
	Shinigami_skyB_lf = "140421648817034",
	Shinigami_skyB_rt = "121876946780992",
	Shinigami_skyB_up = "116050443990871",
	Shinigami_skyB_dn = "97881354318536",
}

local BiomeAssets = {}

function BiomeAssets.Get(key: string): string?
	local raw = IDS[key]
	if raw == nil or raw == "" then
		return nil
	end
	if string.find(raw, "rbxassetid://", 1, true) then
		return raw
	end
	local digits = string.match(raw, "%d+")
	if digits then
		return "rbxassetid://" .. digits
	end
	return nil
end

-- Ambiente por zona: lo aplica BiomeAmbientClient al entrar en cada franja
export type Zone = { Sky: string, Ambient: Color3, Outdoor: Color3, Fog: Color3, FogStart: number, FogEnd: number, Tint: Color3, Brightness: number, ClockTime: number }
local function Z(sky: string, amb: Color3, out: Color3, fog: Color3, fogEnd: number, tint: Color3, bright: number, clock: number): Zone
	return { Sky = sky, Ambient = amb, Outdoor = out, Fog = fog, FogStart = fogEnd * 0.25, FogEnd = fogEnd, Tint = tint, Brightness = bright, ClockTime = clock }
end
local C = Color3.fromRGB

BiomeAssets.Zones = ({
	Saiyan_1 = Z("A", C(120, 130, 140), C(150, 165, 180), C(190, 215, 235), 2600, C(255, 255, 255), 2.2, 13),
	Saiyan_2 = Z("A", C(90, 140, 120), C(130, 190, 160), C(150, 225, 175), 2200, C(225, 255, 235), 2.2, 14),
	Saiyan_3 = Z("B", C(120, 105, 95), C(160, 135, 110), C(200, 170, 130), 1800, C(255, 240, 220), 2.0, 17),
	Saiyan_4 = Z("B", C(140, 80, 120), C(200, 120, 170), C(240, 160, 200), 1500, C(255, 225, 245), 2.0, 18),
	Shinobi_1 = Z("A", C(110, 125, 125), C(140, 155, 155), C(185, 200, 200), 1100, C(240, 250, 250), 1.8, 11),
	Shinobi_2 = Z("A", C(90, 100, 115), C(115, 125, 140), C(120, 135, 150), 1400, C(215, 230, 250), 1.6, 12),
	Shinobi_3 = Z("B", C(160, 130, 90), C(210, 175, 120), C(235, 200, 140), 2200, C(255, 240, 210), 2.6, 15),
	Shinobi_4 = Z("B", C(90, 60, 70), C(130, 80, 90), C(110, 50, 60), 1300, C(255, 215, 215), 1.6, 18.5),
	Pirate_1 = Z("A", C(130, 150, 165), C(165, 190, 210), C(200, 230, 245), 2800, C(255, 252, 245), 2.6, 13),
	Pirate_2 = Z("A", C(170, 140, 100), C(220, 185, 135), C(240, 215, 160), 2400, C(255, 240, 210), 2.6, 14),
	Pirate_3 = Z("A", C(150, 165, 185), C(190, 205, 225), C(225, 238, 250), 2800, C(250, 252, 255), 2.8, 13),
	Pirate_4 = Z("B", C(100, 70, 70), C(150, 95, 75), C(160, 100, 80), 1500, C(255, 215, 195), 1.8, 18),
	Shinigami_1 = Z("A", C(130, 105, 95), C(190, 140, 100), C(225, 170, 110), 1800, C(255, 235, 215), 1.8, 17.5),
	Shinigami_2 = Z("B", C(45, 50, 80), C(70, 80, 120), C(30, 35, 60), 1700, C(220, 225, 255), 1.4, 0),
	Shinigami_3 = Z("B", C(60, 65, 100), C(95, 105, 150), C(40, 45, 80), 1700, C(225, 230, 255), 1.6, 0),
	Shinigami_4 = Z("A", C(150, 90, 70), C(215, 130, 90), C(230, 130, 90), 1500, C(255, 220, 200), 1.8, 17.5),
} :: { [string]: Zone })

return BiomeAssets