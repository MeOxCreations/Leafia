--!strict
-- LE REFUS D'UNE ACTION, DIT AU JOUEUR. Une seule question, une seule reponse.
--
-- POURQUOI CE MODULE. Le didacticiel verrouille les outils tant que le joueur n'est pas alle toquer a la porte.
-- Sans lui, chaque feature verrouillable devrait connaitre l'etat du didacticiel, savoir secouer un prompt, et
-- se souvenir si elle a deja affiche la notification. Trois choses a recopier par outil, donc trois occasions de
-- les faire diverger -- et le quatrieme outil qu'on ajoutera n'en aura aucune.
--
-- Ici l'appelant ecrit UNE ligne : `if ActionGate.denyIfLocked() then return end`.
--
-- L'ETAT PASSE PAR UN ATTRIBUT DE JOUEUR, pas par un require. Le didacticiel require deja la tondeuse et le
-- seau : leur faire require le didacticiel en retour fermerait le cycle. Un attribut n'a pas ce probleme, il se
-- lit de partout, et il est deja le moyen retenu dans ce projet pour "ce que les mains tiennent" (CarryUtils).

local Players = game:GetService("Players")

local InteractionPrompt = require(script.Parent.InteractionPrompt)
local SideNotificationHandler = require(script.Parent.Parent.Notification.SideNotificationHandler)

local ActionGate = {}

local player = Players.LocalPlayer

-- Pose par le didacticiel, lu ici. Vrai = les outils sont verrouilles, il faut d'abord aller toquer.
local ATTRIBUTE = "LeafiaActionLock"

ActionGate.ATTRIBUTE = ATTRIBUTE

-- ===== CE QU'ON DIT, ET COMBIEN DE FOIS =====
-- La notification n'apparait pas a CHAQUE refus : la pilule rouge qui tremble suffit a dire non, et une
-- notification qui revient a chaque appui devient du bruit. Elle rappelle POURQUOI, de temps en temps.
local NOTIFY_COOLDOWN = 12
-- EN ANGLAIS, comme tout texte vu par le joueur, et en mots simples : le public a dix ans.
local NOTIF: SideNotificationHandler.NotifData = {
	kind = "Warning",
	title = "Not Yet",
	description = "Go knock on the door first. The old man is waiting for you.",
	duration = 10,
}

local lastNotifyAt = -math.huge

--- Les outils sont-ils verrouilles ? Ne dit rien au joueur : pour ca, voir `denyIfLocked`.
function ActionGate.isLocked(): boolean
	return player:GetAttribute(ATTRIBUTE) == true
end

--- POSE OU LEVE LE VERROU. Appele par le didacticiel, et par lui seul.
function ActionGate.setLocked(locked: boolean)
	player:SetAttribute(ATTRIBUTE, if locked then true else nil)
end

--- REFUSE L'ACTION SI ELLE EST VERROUILLEE, en le DISANT, et rend vrai dans ce cas.
---
--- A appeler en premiere ligne d'une action verrouillable : `if ActionGate.denyIfLocked() then return end`.
---
--- DEUX RETOURS, PAS UN. La pilule rouge qui tremble repond a "j'ai appuye et rien ne s'est passe" -- sans elle,
--- un refus se lit comme un bug. La notification, elle, dit POURQUOI, ce qu'une couleur ne peut pas dire.
---
--- Et la notification a son propre ecart minimum : la secousse peut se rejouer a chaque appui sans lasser, une
--- notification non.
function ActionGate.denyIfLocked(): boolean
	if not ActionGate.isLocked() then
		return false
	end
	InteractionPrompt.refuse()
	local now = os.clock()
	if now - lastNotifyAt >= NOTIFY_COOLDOWN then
		lastNotifyAt = now
		SideNotificationHandler.spawn(NOTIF)
	end
	return true
end

return ActionGate
