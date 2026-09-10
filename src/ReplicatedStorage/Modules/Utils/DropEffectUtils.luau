--!strict
-- POUSSIERE DE POSE : la bouffee de particules qui part quand un objet touche le sol. Un seau, une echelle, et
-- tout ce qu'on posera ensuite -- l'effet ne connait aucun d'eux, on lui donne un point.
--
-- DEUX FONCTIONS, ET IL FAUT LES DEUX. `broadcast` est ce qu'appelle le SERVEUR : il ne joue rien lui-meme, il
-- dit a tous les clients ou l'objet a touche. `spawnAt` est ce que chaque client execute chez lui.
--
-- POURQUOI CE DETOUR. `ParticleEmitter:Emit()` NE SE REPLIQUE PAS. Appele par le serveur, il emet dans la
-- simulation serveur et personne ne voit rien -- alors que le clone, lui, se replique parfaitement. Symptome
-- trompeur au possible : la part EST dans le Workspace de tout le monde, a la bonne place, avec ses emetteurs
-- dedans, et il ne se passe rien. On va donc chercher le bug dans l'effet, dans l'ancrage, dans la position...
-- alors que seules les PROPRIETES se repliquent, jamais les appels de methode.
--
-- LE MODELE VIT DANS STUDIO (`ReplicatedStorage.Assets.Effects.DropOnGroundEffect`). Rojo ne synchronise pas les
-- Assets : on le retrouve par son chemin plutot que de le decrire en code.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local DropEffectUtils = {}

local ASSET_PATH = { "Assets", "Effects", "DropOnGroundEffect" }
-- COMBIEN DE PARTICULES par emetteur, en une seule bouffee.
local EMIT_COUNT = 15
-- Marge apres la derniere particule avant de detruire le clone. La duree de vie, elle, est LUE sur les emetteurs
-- eux-memes : un chiffre en dur ici couperait l'effet en plein vol le jour ou on allonge une particule dans
-- Studio. Une borne ne doit jamais etre plus serree que la donnee qu'elle borne.
local CLEANUP_MARGIN = 0.5
-- Si aucun emetteur n'est trouve, on ne garde pas un clone pour toujours.
local FALLBACK_LIFE = 3

local warned = false

local function asset(): BasePart?
	local node: Instance? = ReplicatedStorage
	for _, step in ASSET_PATH do
		node = node and node:FindFirstChild(step)
	end
	if node and node:IsA("BasePart") then
		return node
	end
	-- UNE SEULE FOIS. Repete a chaque pose, ce message noierait la console -- et un avertissement qui defile est
	-- un avertissement qu'on n'ecoute plus.
	if not warned then
		warned = true
		warn(
			`[DropEffectUtils] Effet introuvable : ReplicatedStorage.{table.concat(ASSET_PATH, ".")}. `
				.. "Rojo ne synchronise pas les Assets : il doit exister dans CETTE place."
		)
	end
	return nil
end

--- Joue la bouffee a un point du monde, SUR CETTE MACHINE. Rien a nettoyer chez l'appelant : le clone se detruit
--- tout seul quand la derniere particule est eteinte.
---
--- Cote serveur, ca ne sert a rien -- voir l'en-tete du module. C'est `broadcast` qu'il faut appeler.
function DropEffectUtils.spawnAt(position: Vector3)
	local source = asset()
	if not source then
		return
	end
	local clone = source:Clone()
	clone.Name = "LeafiaDropEffect"
	clone.CFrame = CFrame.new(position)
	-- ANCREE, ET C'EST LA LIGNE QUI COMPTE. Une part non ancree TOMBE, et ses emetteurs vont jouer sous la map :
	-- l'effet se declenche parfaitement, a un endroit que personne ne regarde. Ca se lit comme "l'effet ne marche
	-- pas" alors qu'il fait exactement son travail, et on part debugger le code.
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanTouch = false
	-- `CanQuery` n'a d'effet QUE parce que CanCollide est faux. Sans les deux, les raycasts du jeu verraient cette
	-- part et croiraient a un obstacle la ou il n'y a que de la poussiere.
	clone.CanQuery = false
	clone.CastShadow = false
	-- INVISIBLE : ce n'est qu'un porteur d'emetteurs. Le modele est a 0.5 dans Studio pour qu'on le VOIE en le
	-- reglant -- laisser cette valeur ferait apparaitre un cube gris a chaque pose.
	clone.Transparency = 1
	clone.Parent = Workspace

	local longest = 0
	for _, d in clone:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			-- `Emit` PLUTOT QUE `Enabled` : une bouffee unique, dont on maitrise le nombre. Laisser l'emetteur
			-- tourner obligerait a le couper au bon moment, et ce "bon moment" depend de son `Rate` -- donc d'un
			-- reglage de Studio qu'aucun code ne peut deviner.
			d.Enabled = false
			d:Emit(EMIT_COUNT)
			longest = math.max(longest, d.Lifetime.Max)
		end
	end
	Debris:AddItem(clone, (if longest > 0 then longest else FALLBACK_LIFE) + CLEANUP_MARGIN)
end

--- SERVEUR : demande a tous les clients de jouer la bouffee a ce point.
---
--- Silencieuse hors du serveur : appelee par erreur cote client, elle ne fait rien plutot que de crasher. Un
--- effet decoratif ne doit jamais casser l'action qu'il accompagne.
function DropEffectUtils.broadcast(position: Vector3)
	if not RunService:IsServer() then
		return
	end
	local remote = RemoteSetup.getRemote("PlayDropEffect", "Fx") :: RemoteEvent
	remote:FireAllClients(position)
end

--- SERVEUR : la meme chose, SOUS un modele -- au centre de son emprise, a la hauteur de son point le plus bas.
---
--- La boite englobante plutot que le pivot : `GetPivot` d'un Model SANS PrimaryPart suit deja la boite, et avec
--- un PrimaryPart il suit une part qui peut etre n'importe ou dans l'objet. La boite, elle, repond toujours a la
--- meme question -- ou est le bas de ce qu'on voit.
function DropEffectUtils.broadcastUnder(model: Model)
	local cf, size = model:GetBoundingBox()
	DropEffectUtils.broadcast(cf.Position - Vector3.new(0, size.Y / 2, 0))
end

return DropEffectUtils
