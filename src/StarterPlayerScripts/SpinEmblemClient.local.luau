--!strict
--[[
    SpinEmblemClient (LocalScript) -> StarterPlayer > StarterPlayerScripts > SpinEmblemClient
    Hace girar sin parar los emblemas de los carteles (Models con tag "SpinEmblem"): Bola de Dragón, protector ninja, calavera pirata.
    Se anima en el cliente (suave y sin cargar la red).
]]
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local SPEED = math.rad(40) -- grados por segundo

RunService.RenderStepped:Connect(function(dt: number)
	for _, inst in ipairs(CollectionService:GetTagged("SpinEmblem")) do
		if inst:IsA("Model") and inst:IsDescendantOf(workspace) then
			-- giro sobre el eje VERTICAL del mundo que pasa por el centro del emblema (izquierda -> derecha)
			local cf = inst:GetPivot()
			local pos = cf.Position
			inst:PivotTo(CFrame.new(pos) * CFrame.Angles(0, SPEED * dt, 0) * CFrame.new(-pos) * cf)
		end
	end
end)
