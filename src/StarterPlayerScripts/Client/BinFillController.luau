--!strict
-- LE REMPLISSAGE DU SEAU, AFFICHE DANS SON PROMPT. Combien il reste de place, lu au meme endroit que l'action.
--
-- POURQUOI DANS LE PROMPT ET PAS A COTE. Un panneau a lui, flottant sous la pilule, fait DEUX choses a lire au
-- meme endroit -- et la seconde finit toujours par recouvrir la premiere : c'est exactement ce qui s'est passe,
-- la barre rentrait dans le badge. Une seule chose a lire, au seul endroit ou le joueur regarde deja.
--
-- IL NE DECIDE RIEN, il lit. Le compte vit sur le seau, en attribut pose par le serveur : deux joueurs qui
-- regardent le meme seau voient la meme chose sans qu'on envoie quoi que ce soit.
--
-- ON NE TOUCHE PAS AU PROMPT D'UN AUTRE. Il est SINGLETON et six features s'en servent : la jauge ne s'ecrit que
-- si le badge affiche appartient bien a CE seau -- `setGauge` refait le test de son cote, mais on evite meme de
-- le lui demander pour les seaux qui ne sont pas a l'ecran.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BinConfigs = require(ReplicatedStorage.Modules.Configs.BinConfigs)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)

local BinFillController = {}

--- LE SEAU QUE LE PROMPT DESIGNE EN CE MOMENT, ou nil.
---
--- ON PART DE LA CIBLE AFFICHEE, pas des seaux. Le prompt s'accroche a une PART du seau, et laquelle ne nous
--- regarde pas : remonter de la part au modele repond a la question sans qu'on ait a deviner quelle part
--- `BinCarryController` a choisie -- et ca reste juste le jour ou il en change.
local function shownBin(): Model?
	local target = InteractionPrompt.currentTarget()
	if typeof(target) ~= "Instance" then
		return nil
	end
	local part = target :: Instance
	if not part:IsA("BasePart") then
		return nil
	end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model.Name:sub(1, #BinConfigs.MODEL_PREFIX) == BinConfigs.MODEL_PREFIX then
			return model
		end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

function BinFillController.init()
	local nextCheck = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextCheck then
			return
		end
		nextCheck = now + BinConfigs.GAUGE_INTERVAL

		local bin = shownBin()
		if not bin then
			return -- le badge parle d'autre chose : ce n'est pas a nous d'y ecrire, ni de l'effacer
		end
		local raw = (bin :: Model):GetAttribute(BinConfigs.LEAVES_ATTRIBUTE)
		local leaves = if typeof(raw) == "number" then math.max(raw :: number, 0) else 0
		local target = InteractionPrompt.currentTarget()
		-- UN SEAU VIDE N'AFFICHE RIEN. Une barre a zero ne dit rien de plus que le seau lui-meme, et elle
		-- rallonge le badge pour ca.
		if leaves <= 0 then
			InteractionPrompt.setGauge(target, nil)
			return
		end
		local ratio = leaves / BinConfigs.LEAVES_CAPACITY
		-- PLEIN SE DIT AVEC UN MOT, pas avec deux nombres egaux : le joueur n'a pas a les comparer pour
		-- comprendre qu'il doit aller vider.
		local text = if ratio >= 1
			then BinConfigs.GAUGE_FULL_TEXT
			else `{math.floor(leaves)} / {BinConfigs.LEAVES_CAPACITY}`
		InteractionPrompt.setGauge(target, ratio, text)
	end)

	print("[BinFillController] Pret : le remplissage du seau s'affiche dans son prompt.")
end

return BinFillController
