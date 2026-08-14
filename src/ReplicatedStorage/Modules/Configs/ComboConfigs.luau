--!strict
-- Reglages du COMBO de coupe. Data pure, zero logique. Partage client + serveur (le client n'a besoin que du nom
-- d'attribut, le serveur des reglages de rythme).
--
-- Le combo recompense la CONTINUITE du geste : tant que le joueur amene des carreaux au ras sans s'arreter, le
-- compteur monte (x1, x2, x3...). Des qu'il cesse de tailler (RESET_TIMEOUT sans nouveau carreau fini), il retombe a
-- zero. C'est un ENJEU (cf CLAUDE.md : sans enjeu, pas d'emotion) : le joueur a quelque chose a PERDRE en s'arretant,
-- donc quelque chose a gagner en enchainant. Pour l'instant purement visuel ; un bonus (XP, argent) pourra s'y
-- brancher plus tard, une fois le ressenti valide.

return {
	-- Attribut pose par le serveur (ComboService) sur le JOUEUR, lu par ComboController. Partage : un seul nom, pas
	-- deux chaines codees en dur qui finiraient par diverger.
	COMBO_ATTRIBUTE = "LeafiaCombo", -- entier : palier de combo courant (0 = pas de combo affiche)

	-- Sans nouveau carreau amene au ras pendant ce temps (secondes), le combo retombe a zero. Court : le combo se
	-- merite frame apres frame, il ne se garde pas en flanant. A REGLER a l'oeil.
	RESET_TIMEOUT = 1.2,

	-- Plancher entre deux montees du compteur (secondes). La coupe continue amene des carreaux au ras a ~60 fps : sans
	-- ce plancher le combo sauterait a x60 en une seconde, illisible. Avec, il monte a un rythme qu'on voit defiler.
	-- Doit rester bien plus court que RESET_TIMEOUT, sinon le combo pourrait expirer entre deux montees en pleine
	-- coupe. A REGLER a l'oeil.
	MIN_INTERVAL = 0.16,
}
