--!strict
-- ACCESSOIRES POSES SUR UN OS. Un objet de decor (une canne, un outil de PNJ) qui doit suivre un membre d'un
-- personnage SKINNE.
--
-- POURQUOI UN SYSTEME A PART, ET PAS UN MOTOR6D. Un Motor6D exige DEUX BasePart. Sur un mesh skinne, les membres
-- sont des `Bone`, qui heritent d'Attachment : aucun joint ne peut s'y accrocher. La seule propriete qui donne la
-- position ANIMEE d'un os est `Bone.TransformedWorldCFrame`, et elle se lit -- elle ne se soude pas. On recopie
-- donc, image par image.
--
-- QUAND NE PAS S'EN SERVIR. Pour un accessoire qui ne se lache JAMAIS, le mieux reste de l'integrer au mesh dans
-- Blender et de le peser sur l'os : il devient une partie du personnage, il suit tout seul, et ca ne coute rien
-- a l'execution. Ce module est fait pour les objets qu'on veut pouvoir deplacer, echanger ou retirer sans
-- reexporter le personnage.

export type Prop = {
	-- Nom du MODELE du personnage dans le Workspace.
	model: string,
	-- Nom de l'OS a suivre, tel qu'il apparait dans l'Explorer (souvent sous la MeshPart du corps).
	bone: string,
	-- Nom de l'objet a accrocher. Il peut trainer a la racine du Workspace ou etre deja range sous le
	-- personnage : on le cherche aux deux endroits.
	prop: string,
}

local PropAttachConfigs = {
	-- L'ECART EST CAPTURE AU DEMARRAGE, il ne se regle pas ici. On lit ou l'objet est POSE par rapport a l'os, et
	-- on garde cet ecart : le placement fait a l'oeil dans Studio EST donc la source de verite, comme pour un
	-- Motor6D. Deplacer la canne dans l'editeur et relancer suffit a corriger la prise.
	--
	-- CONSEQUENCE : l'objet doit etre pose A SA PLACE dans Studio. Laisse au hasard, il sera tenu de travers.
	PROPS = {
		{
			model = "GrandFather",
			-- La main GAUCHE : c'est celle qui tient la canne sur le modele. Verifie dans l'Explorer, l'os
			-- s'appelle bien "RootLeftHand" et vit sous LeftLowerArm.
			bone = "RootLeftHand",
			prop = "Canne",
		},
	} :: { Prop },

	-- Delai TOTAL pour trouver personnage, os et objet au demarrage. Ils peuvent arriver tard (streaming), et un
	-- accessoire absent n'est pas une erreur -- une place peut tres bien ne pas avoir ce PNJ.
	RESOLVE_TIMEOUT = 20,
}

return PropAttachConfigs
