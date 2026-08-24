--!strict
-- CE QUE LES MAINS DU JOUEUR TIENNENT. Source UNIQUE, lue partout, ecrite par le SERVEUR seul.
--
-- POURQUOI CE MODULE. Avant, chaque objet portable posait SON drapeau et gardait SA petite liste de ceux qui le
-- bloquent. Trois drapeaux (LeafiaCarryingBin / Ladder / Mower), deux porteurs differents (le personnage pour
-- deux d'entre eux, le joueur pour le troisieme) et deux autorites (le CLIENT pour l'echelle, le serveur pour
-- les autres). Sur les 12 paires a tenir d'accord, 7 manquaient : on pouvait porter le seau ET prendre l'echelle,
-- ET la tondeuse, ET sortir un outil. Le drapeau du seau, lui, n'etait lu par PERSONNE.
--
-- Avec N objets ca fait N x (N-1) verifications a maintenir a la main, et chaque nouvel objet oblige a modifier
-- tous les autres -- ce que personne ne fait, parce que rien ne le rappelle. Ici il n'y a qu'UNE question ("les
-- mains sont prises par quoi ?"), donc qu'UNE reponse. Ajouter un cinquieme objet ne touche aucun des quatre
-- autres : il claim, il release, c'est tout.

local RunService = game:GetService("RunService")

-- Pose sur le PLAYER et pas sur le personnage : un attribut de joueur survit au respawn (donc aucun risque de
-- mains "prises pour toujours" par un objet perdu a la mort) et se replique a tout le monde, donc le client le
-- lit sans qu'on ait a inventer un remote.
local ATTRIBUTE = "LeafiaHands"

export type Carryable = "Bin" | "Ladder" | "Mower"

local CarryUtils = {}

CarryUtils.ATTRIBUTE = ATTRIBUTE

-- Ce que le joueur tient, ou nil si ses mains sont libres.
function CarryUtils.get(player: Player): string?
	local value = player:GetAttribute(ATTRIBUTE)
	return if typeof(value) == "string" then value else nil
end

function CarryUtils.isFree(player: Player): boolean
	return CarryUtils.get(player) == nil
end

-- Tient-il PRECISEMENT cet objet ? Remplace les anciens "GetAttribute(LeafiaCarryingXxx)" eparpilles.
function CarryUtils.holds(player: Player, kind: Carryable): boolean
	return CarryUtils.get(player) == kind
end

-- PREND LES MAINS. Rend false si elles sont deja prises par AUTRE CHOSE : l'appelant doit alors renoncer, c'est
-- le seul point de la base ou ce refus est decide.
--
-- Reprendre ce qu'on tient DEJA rend true : un systeme peut se rappeler sans se bloquer lui-meme (une prise
-- rejouee, un remote qui arrive deux fois) sans avoir a tenir un compteur de son cote.
function CarryUtils.claim(player: Player, kind: Carryable): boolean
	if not RunService:IsServer() then
		-- Le client ment toujours : s'il pouvait ecrire ici, la garde ne vaudrait rien. On refuse au lieu de
		-- laisser passer en silence, sinon le bug se decouvre le jour ou quelqu'un exploite le trou.
		warn(`[CarryUtils] claim("{kind}") appele depuis le CLIENT : ignore. Cet etat s'ecrit cote serveur.`)
		return false
	end
	local current = CarryUtils.get(player)
	if current ~= nil and current ~= kind then
		return false
	end
	player:SetAttribute(ATTRIBUTE, kind)
	return true
end

-- REND LES MAINS. On ne rend QUE ce qu'on tient : un systeme qui se termine en retard ne peut pas liberer les
-- mains d'un autre qui vient tout juste de les prendre.
function CarryUtils.release(player: Player, kind: Carryable)
	if not RunService:IsServer() then
		warn(`[CarryUtils] release("{kind}") appele depuis le CLIENT : ignore. Cet etat s'ecrit cote serveur.`)
		return
	end
	if CarryUtils.get(player) == kind then
		player:SetAttribute(ATTRIBUTE, nil)
	end
end

return CarryUtils
