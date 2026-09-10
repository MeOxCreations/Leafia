--!strict
-- COMPETENCE DE TONTE : la jauge qui monte pendant qu'on tond, a cote de la tete du joueur.
--
-- ELLE VIT COTE CLIENT, comme l'herbe elle-meme. `GrassZoneController` calcule la coupe chez chaque joueur : il
-- n'y a aujourd'hui aucune autorite serveur sur la pelouse, donc rien a demander au serveur ici. Le jour ou la
-- progression devra etre SAUVEGARDEE, c'est un service qui tiendra le compte et ce controller n'affichera plus
-- que ce qu'on lui pose -- exactement comme ExperiencesController le fait deja pour le niveau.
--
-- Le niveau et le remplissage sont poses en ATTRIBUTS sur le joueur : ca se replique tout seul et n'importe quel
-- module peut les lire sans connaitre celui qui les calcule.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SkillBar = require(ReplicatedStorage.Modules.UI.Core.SkillBar)
local SkillConfigs = require(ReplicatedStorage.Modules.Configs.SkillConfigs)

local SkillController = {}

local player = Players.LocalPlayer

local level = 1
local progress = 0 -- dans le niveau courant
local lastGainAt = 0
local visible = false
local conn: RBXScriptConnection? = nil

-- Combien il faut couper pour finir CE niveau. Bornee a 1 : on divise par elle pour la fraction de remplissage.
local function needFor(lvl: number): number
	return math.max(1, SkillConfigs.MOW_BASE * SkillConfigs.MOW_GROWTH ^ (lvl - 1))
end

local function push()
	player:SetAttribute(SkillConfigs.MOW_LEVEL_ATTRIBUTE, level)
	player:SetAttribute(SkillConfigs.MOW_FILL_ATTRIBUTE, progress / needFor(level))
end

local function bodyPart(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root :: BasePart else nil
end

--- A APPELER QUAND LE JOUEUR COUPE VRAIMENT DE L'HERBE. `amount` est ce que rend `GrassZoneController.mowAt` :
--- une quantite rabattue, pas un temps -- passer la tondeuse sur du beton ne fait donc rien monter.
---
--- Silencieuse a zero : l'appelant peut la brancher sans condition dans sa boucle par image.
function SkillController.addMow(amount: number)
	if amount <= 0 then
		return
	end
	lastGainAt = os.clock()

	if level < SkillConfigs.MOW_MAX_LEVEL then
		progress += amount
		-- UNE BOUCLE, PAS UN `if` : un gros gain peut passer plusieurs paliers d'un coup, et un seul test en
		-- laisserait le reste dans la jauge -- elle resterait pleine sans monter.
		while level < SkillConfigs.MOW_MAX_LEVEL and progress >= needFor(level) do
			progress -= needFor(level)
			level += 1
		end
		if level >= SkillConfigs.MOW_MAX_LEVEL then
			-- AU MAXIMUM ELLE RESTE PLEINE. La vider ferait croire qu'on repart de zero, et un joueur qui a fini
			-- de progresser doit le VOIR, pas le deduire.
			progress = needFor(level)
		end
		push()
	end

	local anchor = bodyPart()
	if anchor then
		visible = true
		SkillBar.show(anchor, progress / needFor(level))
	end
end

-- ELLE S'EFFACE QUAND ON S'ARRETE. Affichee en permanence, une jauge devient du decor : on cesse de la voir, donc
-- elle cesse de recompenser.
local function step()
	if visible and os.clock() - lastGainAt >= SkillConfigs.MOW_LINGER then
		visible = false
		SkillBar.hide()
	end
end

function SkillController.init()
	push()
	-- LA JAUGE EST DETRUITE AVEC LE PERSONNAGE. Elle est accrochee a une part du rig : gardee apres une mort, elle
	-- suivrait une RootPart detruite -- WorldAnchor calculerait une position pour un objet qui n'existe plus.
	player.CharacterRemoving:Connect(function()
		visible = false
		SkillBar.destroy()
	end)
	-- La boucle coute une comparaison de date tant qu'il n'y a rien a cacher.
	conn = RunService.Heartbeat:Connect(step)
end

--- Coupe tout. Celui qui cree est celui qui nettoie, et il nettoie TOUT.
function SkillController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	SkillBar.destroy()
	visible = false
end

return SkillController
