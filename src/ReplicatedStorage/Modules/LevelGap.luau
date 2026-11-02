--!strict
--[[
    LevelGap (ModuleScript) -> ReplicatedStorage.Modules.LevelGap
    PENALIZACIÓN POR BRECHA DE NIVEL: si matas monstruos de MUCHO menos nivel que tú, ganas menos XP y menos botín.
    Así un jugador de nivel alto no se queda farmeando la franja 1 y se ve obligado a estar en el rango de su nivel.
      brecha = nivel del jugador - nivel del monstruo
      Hasta SAFE_GAP niveles de diferencia: 100 %. Después baja en línea recta entre estos puntos:
        brecha  5 -> 100 % · 10 -> 70 % · 15 -> 40 % · 20 -> 20 % · 30 -> 7 % · 40 o más -> 3 %
    Se aplica a la XP (RewardService) y al botín: oro y probabilidades de objeto/equipo/mascota (LootService).
    Monstruos de MAYOR nivel que tú: sin cambios (1.0).
    Para balancear solo toca la tabla POINTS (un solo lugar).
]]
local LevelGap = {}

-- { brecha, multiplicador }. Orden ascendente por brecha.
LevelGap.POINTS = { { 5, 1.0 }, { 10, 0.7 }, { 15, 0.4 }, { 20, 0.2 }, { 30, 0.07 }, { 40, 0.03 } } :: { { number } }

function LevelGap.Mult(playerLevel: number, mobLevel: number): number
	local gap = playerLevel - mobLevel
	local pts = LevelGap.POINTS
	if gap <= pts[1][1] then
		return 1
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if gap <= b[1] then
			return a[2] + (b[2] - a[2]) * (gap - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

return LevelGap
