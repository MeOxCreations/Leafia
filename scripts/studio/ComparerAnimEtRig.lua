-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO (mode edition ou en partie, peu importe).
-- Hors de src/, donc Rojo ne le synchronise pas : outil d'atelier.
--
-- PROBLEME QU'IL REGLE
-- Une animation qui JOUE (la piste existe, son poids vaut 1) mais qui ne bouge RIEN, ou qui n'anime qu'une PARTIE
-- du personnage. Une animation Roblox retrouve les membres PAR LEUR NOM : elle contient une hierarchie de poses
-- nommees comme les os / les parts du rig sur lequel elle a ete creee. Si un nom a change depuis, ou si l'animation
-- vient d'un autre rig, elle ne trouve plus a qui parler et joue dans le vide, sans la moindre erreur.
--
-- CE QU'IL FAIT, ET DANS LES DEUX SENS
-- 1. Les noms de l'animation ABSENTS du rig  -> l'animation parle a des membres qui n'existent pas.
-- 2. Les membres du rig que l'animation NE TOUCHE PAS -> ils resteront figes (typiquement : une canne, un outil).
--
-- Le 2 est celui qu'on oublie, et c'est lui qui repond a "pourquoi la canne ne bouge pas alors que le reste bouge".

local NOM_DU_PNJ = "OldmanOriginal"
local ANIMATIONS = {
	Idle = "rbxassetid://102639960685891",
	Walking = "rbxassetid://109013940658757",
}

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local model = workspace:FindFirstChild(NOM_DU_PNJ, true)
if not model or not model:IsA("Model") then
	warn(`[ComparerAnimEtRig] Model "{NOM_DU_PNJ}" introuvable dans le Workspace.`)
	return
end

-- LES DEUX FAMILLES DE RIG, et il FAUT balayer les deux. Un modele assemble est pilote par des `Motor6D` (on lit
-- alors le nom de leur `Part1`, jamais celui du joint) ; un skinned mesh est pilote par des `Bone`, qui descendent
-- d'`Attachment` et n'ont donc aucune classe commune avec le premier cas. Une sonde qui n'en connait qu'une seule
-- ne trouve rien sur l'autre et designe un coupable avec autorite -- piege deja paye sur ce meme grand-pere.
local dansLeRig, listeRig = {}, {}
local nbMotors, nbBones = 0, 0
for _, descendant in ipairs(model:GetDescendants()) do
	local nom: string? = nil
	if descendant:IsA("Motor6D") and descendant.Part1 then
		nom = descendant.Part1.Name
		nbMotors += 1
	elseif descendant:IsA("Bone") then
		nom = descendant.Name
		nbBones += 1
	end
	if nom and not dansLeRig[nom] then
		dansLeRig[nom] = true
		listeRig[#listeRig + 1] = nom
	end
end

if #listeRig == 0 then
	warn(
		`[ComparerAnimEtRig] "{NOM_DU_PNJ}" n'a NI Motor6D NI Bone : aucune animation ne pourra le bouger. `
			.. "Ce n'est pas un probleme d'animation, c'est un rig absent."
	)
	return
end

table.sort(listeRig)
print(
	`[ComparerAnimEtRig] RIG "{NOM_DU_PNJ}" : {nbMotors} Motor6D + {nbBones} Bone -> {#listeRig} nom(s) : `
		.. table.concat(listeRig, ", ")
)

-- Parcourt la hierarchie de poses d'une animation et releve tous les noms qu'elle porte.
local function releverPoses(instance: Instance, noms: { string })
	for _, enfant in ipairs(instance:GetChildren()) do
		if enfant:IsA("Pose") then
			noms[#noms + 1] = enfant.Name
		end
		releverPoses(enfant, noms)
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
	local vus, uniques, absentsDuRig = {}, {}, {}
	for _, nom in ipairs(noms) do
		if not vus[nom] then
			vus[nom] = true
			uniques[#uniques + 1] = nom
			if not dansLeRig[nom] then
				absentsDuRig[#absentsDuRig + 1] = nom
			end
		end
	end
	table.sort(uniques)
	print(`[ComparerAnimEtRig] ANIM "{etiquette}" ({#uniques} membre(s)) : {table.concat(uniques, ", ")}`)

	-- SENS 1 : l'animation parle a des membres qui n'existent pas dans le rig.
	if #absentsDuRig > 0 then
		table.sort(absentsDuRig)
		warn(
			`   -> {#absentsDuRig} nom(s) de l'ANIMATION absents du RIG : {table.concat(absentsDuRig, ", ")}. `
				.. "Ces poses tombent dans le vide."
		)
	end

	-- SENS 2 : le rig a des membres que l'animation ne cle pas. CE SONT EUX QUI RESTENT FIGES.
	local jamaisTouches = {}
	for _, nom in ipairs(listeRig) do
		if not vus[nom] then
			jamaisTouches[#jamaisTouches + 1] = nom
		end
	end
	if #jamaisTouches > 0 then
		warn(
			`   -> {#jamaisTouches} membre(s) du RIG que "{etiquette}" ne cle PAS : `
				.. `{table.concat(jamaisTouches, ", ")}. Ceux-la resteront figes pendant cette animation.`
		)
	end

	if #absentsDuRig == 0 and #jamaisTouches == 0 then
		print(`   -> correspondance PARFAITE. Si ca ne bouge toujours pas, le probleme est ailleurs.`)
	end
end
