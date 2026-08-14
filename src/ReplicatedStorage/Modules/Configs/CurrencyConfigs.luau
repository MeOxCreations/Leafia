--!strict
-- Reglages de l'ECONOMIE joueur (pieces + reputation). Data pure, zero logique. Partage client + serveur : le
-- client n'a besoin que des noms d'attributs, pour lire ce que le serveur pose sur le joueur.
--
-- LE GAIN EST BRANCHE : finir une haie (100%) paie un CHEQUE (coins), via CurrencyService.grantCoins appele par
-- HedgeCutService a la completion. La persistance suit toute seule (les coins vivent dans la company active, cf
-- DataTemplate). Le systeme de chantiers (boite aux lettres -> courrier d'un client -> chantier -> paye) viendra
-- ENCADRER ce gain plus tard (assigner des haies, primes de client) ; le tuyau de paie, lui, est deja en place.

return {
	-- Attributs poses par le serveur (CurrencyService) sur le JOUEUR, lus par CurrencyController. Un seul nom
	-- partage des deux cotes, pas deux chaines codees en dur qui finiraient par diverger.
	COINS_ATTRIBUTE = "LeafiaCoins", -- entier : pieces possedees (monnaie principale, CurrencyUI)
	-- entier : renommee de l'entreprise. C'est un RANG qui se MERITE par la qualite du boulot, pas une monnaie
	-- qu'on achete (d'ou l'absence de bouton d'achat cote UI). Son GAIN viendra avec le systeme de chantiers.
	REPUTATION_ATTRIBUTE = "LeafiaReputation",

	-- CHEQUE DE FIN DE HAIE : la 1re fois qu'une haie atteint 100%, le joueur touche
	--   payout = HEDGE_BASE_PAYOUT + floor(nb de carreaux de la haie * HEDGE_PER_CELL_PAYOUT)
	-- Une plus grosse haie = un plus gros cheque. Regle vers ~100 par haie moyenne (cf onboarding "cheque 100$"),
	-- A AFFINER a la console admin (F2) selon le rythme voulu. Regle par defaut du projet : donner MOINS, on desserre
	-- plus tard (jamais l'inverse : un nerf est vecu comme une punition).
	HEDGE_BASE_PAYOUT = 40, -- paie fixe par haie finie
	HEDGE_PER_CELL_PAYOUT = 0.6, -- paie ajoutee par carreau (recompense les grosses haies)
}
