--!strict
--[[
    BridgeSigns (ModuleScript) -> ServerScriptService.Services.BridgeSigns
    CARTEL EN LO ALTO DEL ARCO DE CADA PUENTE (entre las dos torres del portón de cada ciudad), visible desde la Arena y desde la ciudad.
      - Imperio Saiyan : tablero azul noche con borde dorado + gran Bola de Dragón de 4 estrellas.
      - Alianza Shinobi: tablero verde oscuro + protector de frente ninja (placa de metal con el kanji 忍) con cintas.
      - Flota Pirata   : tablero de madera azul + calavera con huesos cruzados y sombrero de paja.
    No toca el mapa existente: busca "Torre_Porton_A/B" de cada ciudad y construye encima. Todo es decorativo (sin colisión, sin clics).
]]
local Workspace = game:GetService("Workspace")

local MAP_NAME = "Map_WC3_Style"
local SignKit = require(script.Parent:WaitForChild("SignKit"))
local LOOKS = SignKit.LOOKS
local part = SignKit.Part

local function buildSign(mapFolder: Instance, biome: string, look: any)
	local biomeFolder = mapFolder:FindFirstChild(biome)
	if not biomeFolder then
		return
	end
	local a = biomeFolder:FindFirstChild("Torre_Porton_A", true)
	local b = biomeFolder:FindFirstChild("Torre_Porton_B", true)
	if not (a and b and a:IsA("BasePart") and b:IsA("BasePart")) then
		warn("[BridgeSigns] no encontré las torres del portón de " .. biome)
		return
	end
	local old = Workspace:FindFirstChild("Cartel_" .. biome)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = "Cartel_" .. biome

	local mid = (a.Position + b.Position) / 2
	local rot = a.CFrame.Rotation -- los lados del carril (LookVector = hacia la ciudad)
	local span = (a.Position - b.Position).Magnitude -- distancia entre ejes de torres
	local topY = a.Position.Y + a.Size.Y / 2
	local lintelH, boardH, boardW = 7, 30, math.max(80, span - 36)

	local base = CFrame.new(mid.X, topY, mid.Z) * rot
	-- dintel entre torres (cierra el arco)
	part(folder, "Dintel", Vector3.new(span, lintelH, 22), base * CFrame.new(0, -lintelH / 2 - 2, 0), Color3.fromRGB(70, 62, 56), Enum.Material.Brick)
	part(folder, "DintelBorde", Vector3.new(span, 1.2, 23), base * CFrame.new(0, 0.1, 0), look.Trim, Enum.Material.Metal)
	-- tablero
	local boardCF = base * CFrame.new(0, 1 + boardH / 2, 0)
	local board = part(folder, "Tablero", Vector3.new(boardW, boardH, 3), boardCF, look.Board, Enum.Material.SmoothPlastic)
	part(folder, "BordeSup", Vector3.new(boardW + 4, 2, 4), boardCF * CFrame.new(0, boardH / 2 + 1, 0), look.Trim, Enum.Material.Neon)
	part(folder, "BordeInf", Vector3.new(boardW + 4, 2, 4), boardCF * CFrame.new(0, -boardH / 2 - 1, 0), look.Trim, Enum.Material.Neon)
	part(folder, "BordeIzq", Vector3.new(2, boardH + 4, 4), boardCF * CFrame.new(-boardW / 2 - 1, 0, 0), look.Trim, Enum.Material.Neon)
	part(folder, "BordeDer", Vector3.new(2, boardH + 4, 4), boardCF * CFrame.new(boardW / 2 + 1, 0, 0), look.Trim, Enum.Material.Neon)
	-- mismo diseño en las dos caras (ciudad y arena)
	SignKit.Design(board, Enum.NormalId.Back, biome, look, boardW, boardH)
	SignKit.Design(board, Enum.NormalId.Front, biome, look, boardW, boardH)
	-- emblema arriba del tablero
	SignKit.SpinningEmblem(biome, folder, boardCF * CFrame.new(0, boardH / 2 + 12, 0), look, 1)

	folder.Parent = Workspace
end

task.spawn(function()
	local map = Workspace:WaitForChild(MAP_NAME, 90)
	if not map then
		warn("[BridgeSigns] no apareció el mapa " .. MAP_NAME)
		return
	end
	task.wait(2) -- deja que terminen de construirse las murallas y torres
	for biome, look in pairs(LOOKS) do
		local ok, err = pcall(buildSign, map, biome, look)
		if not ok then
			warn("[BridgeSigns] error en " .. biome .. ": " .. tostring(err))
		end
	end
	print("[BridgeSigns] Carteles de los 3 puentes listos.")
end)

return {}
