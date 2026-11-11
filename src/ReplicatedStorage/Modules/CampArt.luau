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

-- Pisos por facción (ids internos: Saiyan = Élite, Shinobi = Sigilo, Pirate = Navegantes, Shinigami = Espíritu)
CampArt.ChallengeBy = {
	Saiyan = 114060024819183,
	Shinobi = 77005661763122,
	Pirate = 88542187738575,
	Shinigami = 103361731175843,
} :: { [string]: number }

CampArt.OfferingBy = {
	Saiyan = 72913801447497,
	Shinobi = 113032366075115,
	Pirate = 86771055023130,
	Shinigami = 135419579369633,
} :: { [string]: number }

CampArt.LairBy = {
	Saiyan = 84205605810822,
	Shinobi = 111932742162922,
	Pirate = 93459341364315,
	Shinigami = 123696782073952,
} :: { [string]: number }

CampArt.Relic = {
	Saiyan = 77222847810004,
	Shinobi = 76446975031284,
	Pirate = 77324702578075,
	Shinigami = 132756055954027,
} :: { [string]: number }

-- Hogar (vista cenital) y llama por facción
CampArt.Hearth = {
	Saiyan = 135691991467116,
	Shinobi = 122260954056106,
	Pirate = 115589975035953,
	Shinigami = 104325521302643,
} :: { [string]: number }

CampArt.Flame = {
	Saiyan = 120221897863132,
	Shinobi = 115538646183004,
	Pirate = 73427640739662,
	Shinigami = 72789104006465,
} :: { [string]: number }

-- Recursos de recolección: Resource[franja][facción] (1 Hierba, 2 Cristal, 3 Reliquia, 4 Corazón)
CampArt.Resource = {
	[1] = { Saiyan = 110585183357194, Shinobi = 101822301184594, Pirate = 108101137779597, Shinigami = 130571979764195 },
	[2] = { Saiyan = 105364803322871, Shinobi = 94289319316592, Pirate = 126927589316890, Shinigami = 113772040919847 },
	[3] = { Saiyan = 90309293163369, Shinobi = 100655358017786, Pirate = 82830954876186, Shinigami = 125757343308460 },
	[4] = { Saiyan = 96759312369690, Shinobi = 71093963992296, Pirate = 123714734167748, Shinigami = 127593663323556 },
} :: { [number]: { [string]: number } }

CampArt.ChestClosed = {
	Saiyan = 73986397361886,
	Shinobi = 104149369881928,
	Pirate = 122911078357778,
	Shinigami = 82768405433805,
} :: { [string]: number }

CampArt.ChestOpen = {
	Saiyan = 135608020019575,
	Shinobi = 125046799802555,
	Pirate = 140112137877157,
	Shinigami = 80644514381660,
} :: { [string]: number }

-- Props de campamento (cápsula Élite, tienda Sigilo, toldo Navegantes)
CampArt.Prop = {
	Saiyan = 135208518151982,
	Shinobi = 135846105266867,
	Pirate = 106707033564610,
} :: { [string]: number }

-- Portal y buzón del Pabellón en la plaza de cada ciudad
CampArt.PortalArt = {
	Saiyan = 135468793482907,
	Shinobi = 80207069725905,
	Pirate = 107239179692594,
	Shinigami = 78074527472290,
} :: { [string]: number }

CampArt.Mailbox = {
	Saiyan = 80256328993427,
	Shinobi = 98597758975478,
	Pirate = 124034899487184,
	Shinigami = 76155762853290,
} :: { [string]: number }

-- Cartel que mira siempre a la cámara (w x h en studs); su base queda a offY sobre la pieza
function CampArt.Sprite(p: BasePart, name: string, id: number, w: number, h: number, offY: number, maxDist: number?): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromScale(w, h)
	bb.StudsOffset = Vector3.new(0, offY, 0)
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0.35
	bb.MaxDistance = maxDist or 150
	bb.Adornee = p
	local im = Instance.new("ImageLabel")
	im.Name = "Img"
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.Image = CampArt.Url(id)
	im.Parent = bb
	bb.Parent = p
	return bb
end

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
function CampArt.Panel(p: BasePart, face: Enum.NormalId, id: number, name: string?, pixelsPerStud: number?)
	local g = Instance.new("SurfaceGui")
	g.Name = name or "Panel"
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pixelsPerStud or 60
	g.LightInfluence = 0.6
	g.Parent = p
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.Image = CampArt.Url(id)
	im.Parent = g
end

return CampArt
