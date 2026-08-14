--!strict
-- Applique l'effet SLIME (survol + clic) a TOUS les GuiButton de l'interface du joueur, et aux nouveaux qui
-- apparaissent ensuite. L'UI se fait dans Studio : ce controller n'ajoute QUE le comportement, il ne cree ni ne
-- modifie aucun visuel. Ainsi un bouton ajoute dans Studio est slime automatiquement, sans cablage a la main.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonSlime = require(ReplicatedStorage.Modules.UI.Core.ButtonSlime)

local ButtonSlimeController = {}

local player = Players.LocalPlayer

-- Le curseur a deja son propre effet slime : on ne slime pas d'eventuels boutons vivant sous son GUI.
local EXCLUDE_GUI = "CursorGui"

-- Reglages RENFORCES par NOM de bouton (les autres gardent les defauts de ButtonSlime). Ici : les fleches de
-- selection de plot ont un enfoncement au clic bien plus marque, pour un feedback plus punchy.
local OVERRIDES: { [string]: ButtonSlime.SlimeOptions } = {
	PreviousButton = { pressed = -0.1 },
	NextButton = { pressed = -0.1 },
}

local function tryBind(instance: Instance)
	if not instance:IsA("GuiButton") then
		return
	end
	local screenGui = instance:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui and screenGui.Name == EXCLUDE_GUI then
		return
	end
	-- Opt-out reutilisable : un ScreenGui avec l'attribut LeafiaNoSlime ne veut pas de slime (ex la nav, dont les boutons
	-- sont dans un layout auto-size ou le scale du slime ferait bouger le texte). Zero cablage a la main cote bouton.
	if screenGui and screenGui:GetAttribute("LeafiaNoSlime") then
		return
	end
	ButtonSlime.bind(instance, OVERRIDES[instance.Name])
end

function ButtonSlimeController.init()
	-- PlayerGui n'est peuple qu'au spawn (parfois tardif) : on attend en tache de fond pour ne pas bloquer le boot.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		for _, descendant in ipairs(playerGui:GetDescendants()) do
			tryBind(descendant)
		end
		playerGui.DescendantAdded:Connect(tryBind)
	end)
end

return ButtonSlimeController
