--!strict
-- ECRAN PENDANT UN TELEPORT (vers le tuto, un chantier). Roblox l'affiche a la place de son ecran par defaut pendant
-- le voyage.
--
-- LE MEME DESSIN QUE LE RIDEAU D'ARRIVEE (`ReplicatedFirst.CurtainVisual`) : ciel bleu, tuile, visage du grand-pere.
-- C'etait un rideau GRIS avec une feuille et quatre boules, reste d'une ancienne version : le joueur passait d'un
-- ecran a un autre qui ne lui ressemblait pas, en plein milieu d'un chargement.
--
-- FIGE : les scripts ne tournent pas pendant un teleport, donc rien ne bouge ici. A l'arrivee, le rideau reprend le
-- meme dessin et l'anime.
--
-- NE SE VOIT PAS EN STUDIO : un teleport n'y part jamais. Seulement dans le jeu publie.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TeleportService = game:GetService("TeleportService")

-- ReplicatedFirst est replique AVANT que les scripts du joueur ne demarrent : le module est deja la.
local CurtainVisual = require(ReplicatedFirst.CurtainVisual)

local TeleportController = {}

function TeleportController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TeleportLoadingGui"
	-- Plein ecran, bord a bord, comme le rideau d'arrivee : sinon un bandeau reste decouvert en haut.
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000

	-- UN FRAME ET PAS UN CanvasGroup comme le rideau : ici rien ne fond, et il n'y a aucune raison d'ajouter une
	-- couche de rendu a un ecran fige. `ClipsDescendants` borne la tuile, deux fois plus grande que l'ecran.
	local container = Instance.new("Frame")
	container.Name = "Curtain"
	container.BackgroundColor3 = CurtainVisual.BG
	container.BorderSizePixel = 0
	container.Size = UDim2.fromScale(1, 1)
	container.ClipsDescendants = true
	container.Parent = gui

	-- LE NOM DU LIEU NE PEUT PAS ETRE CELUI DE LA DESTINATION : cet ecran est enregistre une fois au demarrage, et le
	-- client ne sait pas ou le serveur l'enverra. Le rideau d'arrivee affiche le vrai nom.
	CurtainVisual.build(container, CurtainVisual.DEST_FALLBACK)

	-- Enregistre ce GUI : Roblox l'affiche pendant TOUT teleport.
	TeleportService:SetTeleportGui(gui)
	print("[Teleport] Ecran de teleport pret : le meme dessin que le rideau d'arrivee, fige.")
end

return TeleportController
