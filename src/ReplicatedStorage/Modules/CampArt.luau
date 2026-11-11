--!strict
-- Imágenes de campamentos y altares (IDs de "Imágenes" del Creator Hub).
local CampArt = {}

CampArt.Floor = {
	Saiyan = 100419819690368, -- Élite
	Shinobi = 93687453770506, -- Sigilo
	Pirate = 122886843051673, -- Navegantes
	Shinigami = 72437353791861, -- Espíritu
} :: { [string]: number }

CampArt.Banner = {
	Saiyan = 94332345268091,
	Shinobi = 78846970823576,
	Pirate = 88378586923715,
	Shinigami = 101039083179021,
} :: { [string]: number }

CampArt.Offering = 139103928079391
CampArt.Challenge = 113550601702883

function CampArt.Url(id: number): string
	return "rbxassetid://" .. tostring(id)
end

-- Pone la imagen como Decal en una cara de la pieza
function CampArt.Decal(p: BasePart, face: Enum.NormalId, id: number, name: string?)
	local d = Instance.new("Decal")
	d.Name = name or "Arte"
	d.Face = face
	d.Texture = CampArt.Url(id)
	d.Parent = p
end

-- Imagen con fondo transparente sobre una pieza invisible (SurfaceGui)
function CampArt.Panel(p: BasePart, face: Enum.NormalId, id: number, name: string?)
	local g = Instance.new("SurfaceGui")
	g.Name = name or "Panel"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 60
	g.LightInfluence = 0.6
	g.Parent = p
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.Image = CampArt.Url(id)
	im.Parent = g
end

return CampArt
