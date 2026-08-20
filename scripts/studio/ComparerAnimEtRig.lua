-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO (mode edition ou en partie, peu importe).
-- Hors de src/, donc Rojo ne le synchronise pas : outil d'atelier.
--
-- PROBLEME QU'IL REGLE
-- Une animation qui JOUE (la piste existe, son poids vaut 1) mais qui ne bouge RIEN.
-- Une animation Roblox retrouve les membres PAR LEUR NOM. Elle contient une hierarchie de poses nommees comme les
-- parts du rig sur lequel elle a ete creee. Si un nom a change depuis -- ou si l'animation vient d'un autre rig --
-- elle ne trouve plus a qui parler et joue dans le vide, sans la moindre erreur.
--
-- CE QU'IL FAIT
-- Il telecharge l'animation, liste les noms qu'elle contient, liste les parts du rig, et dit lesquels ne se
-- correspondent PAS. C'est la comparaison qui tranche, pas le raisonnement.

local NOM_DU_PNJ = "OldManIdle"
local ANIMATIONS = {
	Idle = "rbxassetid://136244394563436",
	Walking = "rbxassetid://101745125575203",
}

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local model = workspace:FindFirstChild(NOM_DU_PNJ, true)
if not model or not model:IsA("Model") then
	warn(`[ComparerAnimEtRig] Model "{NOM_DU_PNJ}" introuvable.`)
	return
end

-- Les noms que le rig PEUT recevoir : le nom de chaque part reliee par un Motor6D.
local dansLeRig = {}
local listeRig = {}
for _, descendant in ipairs(model:GetDescendants()) do
	if descendant:IsA("Motor6D") and descendant.Part1 then
		dansLeRig[descendant.Part1.Name] = true
		listeRig[#listeRig + 1] = descendant.Part1.Name
	end
end
table.sort(listeRig)
print(`[ComparerAnimEtRig] RIG "{NOM_DU_PNJ}" ({#listeRig} membres) : {table.concat(listeRig, ", ")}`)

-- Parcourt la hierarchie de poses d'une animation et releve tous les noms qu'elle porte.
local function releverPoses(instance: Instance, noms: { string })
	for _, enfant in ipairs(instance:GetChildren()) do
		if enfant:IsA("Pose") then
			noms[#noms + 1] = enfant.Name
			releverPoses(enfant, noms)
		else
			releverPoses(enfant, noms)
		end
	end
end

for etiquette, id in pairs(ANIMATIONS) do
	-- Appel RESEAU, et capricieux : on protege, et un echec EST une reponse (asset inaccessible = animation vide en
	-- jeu, ce qui donne exactement le symptome "elle joue et ne bouge rien").
	local ok, sequence = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(id)
	end)
	if not ok or not sequence then
		warn(
			`[ComparerAnimEtRig] "{etiquette}" ({id}) ILLISIBLE. Souvent : l'animation n'appartient pas au meme `
				.. `compte / groupe que l'experience. Dans ce cas elle joue en jeu sans rien bouger.`
		)
		continue
	end

	local noms = {}
	releverPoses(sequence, noms)
	if #noms == 0 then
		warn(`[ComparerAnimEtRig] "{etiquette}" ne contient AUCUNE pose : l'animation est vide.`)
		continue
	end

	-- Doublons retires pour que la liste reste lisible.
	local vus, uniques, manquants = {}, {}, {}
	for _, nom in ipairs(noms) do
		if not vus[nom] then
			vus[nom] = true
			uniques[#uniques + 1] = nom
			if not dansLeRig[nom] then
				manquants[#manquants + 1] = nom
			end
		end
	end
	table.sort(uniques)
	print(`[ComparerAnimEtRig] ANIM "{etiquette}" ({#uniques} membres) : {table.concat(uniques, ", ")}`)

	if #manquants == 0 then
		print(`   -> tous les noms existent dans le rig. L'animation devrait mordre : cherche ailleurs.`)
	else
		table.sort(manquants)
		warn(
			`   -> {#manquants} nom(s) de l'animation ABSENTS du rig : {table.concat(manquants, ", ")}. `
				.. `C'est la cause : l'animation parle a des membres qui n'existent plus sous ces noms.`
		)
	end
end
