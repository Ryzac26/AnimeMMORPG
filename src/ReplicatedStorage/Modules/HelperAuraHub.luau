--!strict
--[[
    HelperAuraHub (ModuleScript) -> ReplicatedStorage.Modules.HelperAuraHub
    Puente entre HelperFollowClient (que mueve a los ayudantes) y AuraClient (que dibuja las auras).
    HelperFollowClient anota aquí cada ayudante que lleva aura; AuraClient lee la lista y dibuja el aura de la rareza a escala del ayudante.
      Hub.Set(clave, { Root, Model, AuraId, Scale, Feet, Mine })   anota o actualiza
      Hub.Clear(clave)                                              lo quita
      Hub.Enabled() -> boolean                                      ajuste "Auras de ayudantes" (Setting_HelperAuras) en "on"
    Es solo cliente (cada jugador ve las auras según su propio ajuste).
]]
local Players = game:GetService("Players")

export type Target = {
	Root: BasePart, -- pieza que sigue el aura (su frente es -Z)
	Model: Model, -- el modelo del ayudante (no se dibuja el aura sobre él: solo se usa para el raycast/limbos)
	AuraId: string, -- id en LevelMilestones.Auras
	Scale: number, -- tamaño del aura respecto a la de un jugador (≈ la escala del ayudante)
	Feet: number, -- studs de la raíz a los pies
	Mine: boolean, -- es de mis ayudantes (siempre se dibuja primero y con luz)
}

local Hub = {}
Hub.Targets = {} :: { [string]: Target }

function Hub.Set(key: string, target: Target)
	Hub.Targets[key] = target
end

function Hub.Clear(key: string)
	Hub.Targets[key] = nil
end

function Hub.Enabled(): boolean
	local lp = Players.LocalPlayer
	return lp == nil or lp:GetAttribute("Setting_HelperAuras") ~= "off"
end

return Hub
