--!strict
-- Retours camera : champ de vision (repos / mouvement / a-coups) et deplacement de camera (secousse + bob).
--
-- Purement client, et volontairement generique : ce module ne connait ni le taille-haie ni le sprint. Les
-- appelants lui donnent le dosage.
--
-- REGLE CENTRALE : chaque propriete de camera a UN SEUL ecrivain, ici, dans une seule boucle.
--   FieldOfView  = fond (repos vs mouvement)      + a-coup (un tirage)
--   CameraOffset = secousse (impact) + bob (sprint continu) + plongee (atterrissage, revient en douceur)
-- Si chaque source ecrivait directement, elles se battraient chaque frame. Elles alimentent des variables,
-- la boucle compose.
--
-- On passe par Humanoid.CameraOffset et NON par Camera.CFrame : ecrire dans la CFrame revient a se battre
-- contre les scripts de camera de Roblox, ce qui saccade des que le joueur bouge la souris.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraEffects = {}

local player = Players.LocalPlayer

-- ===== Champ de vision =====
local FOV_LERP_SPEED = 3
local DEFAULT_FOV = 70
local fovBase = DEFAULT_FOV
local fovBaseTarget = DEFAULT_FOV
local fovPunch = 0
local fovPunchDecay = 6

-- OFFSET DE FOV, persistant. Distinct du "fond" (pilote par CameraController selon repos / mouvement) et de
-- l'a-coup (transitoire) : c'est un TROISIEME terme, qu'un appelant peut tenir aussi longtemps qu'il veut sans
-- se battre avec les deux autres. Negatif = la vue se resserre.
local fovOffset = 0
local fovOffsetTarget = 0

-- ===== Recul de camera =====
-- La camera Custom de Roblox ne se recule pas : c'est le JOUEUR qui possede sa distance de zoom. On deplace donc
-- ses bornes de zoom, en douceur, et on les rend telles quelles a la fin. Bouger la borne PROGRESSIVEMENT evite
-- le coup sec qu'un clamp pose d'un coup produirait.
-- Pendant le recul le joueur ne peut plus zoomer : c'est voulu, l'effet dure le temps d'une touche maintenue.
local ZOOM_LERP_SPEED = 4
local zoomBoost = 0
local zoomBoostTarget = 0
local zoomBase: number? = nil -- distance du joueur AU MOMENT ou le recul commence
local zoomMinWas, zoomMaxWas = 0, 0

-- ===== Secousse (impact) =====
-- Ecrite par la tache de Shake, lue par la boucle. Revient a zero quand la secousse est finie.
local shakeOffset = Vector3.zero
local shakeToken = 0

-- ===== Bob (oscillation du sprint) =====
-- L'amplitude suit sa cible progressivement : le bob monte et retombe en douceur au lieu d'apparaitre d'un
-- coup quand on lache le sprint.
local bobAmplitude = 0
local bobTarget = 0
local bobFrequency = 0
local bobPhase = 0
local BOB_LERP_SPEED = 6

-- Dernier decalage compose, garde pour les cameras SCRIPTEES. Humanoid.CameraOffset n'est applique que par
-- les scripts de camera par defaut de Roblox : des qu'une feature passe la camera en Scriptable, il est
-- ignore. Une camera scriptee doit donc venir chercher cette valeur et l'appliquer elle-meme, sinon secousses
-- et plongees disparaissent exactement la ou on en a le plus besoin.
local composedOffset = Vector3.zero

-- ===== Plongee d'atterrissage (RESSORT) =====
-- Un simple decalage qui revient a zero donnait un "TAC" : la descente etait instantanee, seule la remontee
-- etait douce. Ici c'est un ressort amorti. A la reception on donne une IMPULSION de vitesse vers le bas ; le
-- ressort ramene la position a zero. Resultat : la camera descend en douceur, freine, remonte, avec un petit
-- rebond. C'est ce leger depassement qui donne le cote "slime" au lieu d'un a-coup sec.
local dipPos = 0
local dipVel = 0
-- Raideur et amortissement. L'amortissement est SOUS l'amortissement critique (2*sqrt(raideur) ~ 22) : le
-- ressort depasse legerement avant de se stabiliser, ce qui fait le rebond mou. Plus d'amortissement = plus
-- sec, moins = plus elastique.
local DIP_STIFFNESS = 120
local DIP_DAMPING = 13

local function getHumanoid(): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

-- Cible du fond de FOV. Valeur ABSOLUE ; la douceur vient du lerp de la boucle. nil = valeur par defaut.
function CameraEffects.SetFovBase(fov: number?)
	fovBaseTarget = fov or DEFAULT_FOV
end

-- Offset de FOV TENU. S'ajoute au fond et n'en bouge plus jusqu'au prochain appel. Negatif = vue resserree.
-- A remettre a 0 par l'appelant : ce module ne devine pas quand un effet tenu doit s'arreter.
function CameraEffects.SetFovOffset(amount: number)
	fovOffsetTarget = amount
end

-- RECUL de camera TENU, en studs. 0 = la camera revient a la distance qu'avait choisie le joueur.
-- Meme regle : c'est l'appelant qui l'eteint.
function CameraEffects.SetZoomBoost(studs: number)
	zoomBoostTarget = studs
end

-- A-coup de FOV : s'ajoute au fond puis s'efface. Negatif = la vue se resserre.
function CameraEffects.PunchFov(amount: number)
	fovPunch = amount
end

-- Bob : oscillation verticale continue. amplitude a 0 l'eteint (en douceur). frequency en oscillations par
-- seconde, grossierement la cadence des pas.
function CameraEffects.SetBob(amplitude: number, frequency: number)
	bobTarget = amplitude
	if frequency > 0 then
		bobFrequency = frequency
	end
end

-- Plongee d'atterrissage. `strength` = vitesse initiale vers le bas donnee au ressort (studs/seconde). Plus
-- grand = plus profond et plus elastique. On REMPLACE la vitesse au lieu de l'additionner : deux receptions
-- rapprochees ne cumulent pas une plongee enorme.
function CameraEffects.LandDip(strength: number)
	dipVel = -math.abs(strength)
end

-- Secousse amortie : forte au debut, eteinte a la fin. Une amplitude constante se lit comme une panne du
-- moteur de jeu, pas comme un impact.
function CameraEffects.Shake(intensity: number, duration: number)
	if intensity <= 0 or duration <= 0 then
		return
	end

	shakeToken += 1
	local token = shakeToken

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local dt = RunService.Heartbeat:Wait()
			-- Une nouvelle secousse a pris la main.
			if shakeToken ~= token then
				return
			end
			elapsed += dt
			local falloff = 1 - (elapsed / duration)
			local amount = intensity * falloff
			shakeOffset = Vector3.new((math.random() - 0.5) * 2 * amount, (math.random() - 0.5) * 2 * amount, 0)
		end
		if shakeToken == token then
			shakeOffset = Vector3.zero
		end
	end)
end

-- Decalage compose (secousse + bob + plongee), en repere CAMERA. A appliquer soi-meme quand on pilote une
-- camera Scriptable : Roblox n'applique Humanoid.CameraOffset que sur sa camera par defaut.
function CameraEffects.GetOffset(): Vector3
	return composedOffset
end

function CameraEffects.init()
	RunService.RenderStepped:Connect(function(dt: number)
		-- dt dans chaque facteur de lerp -> meme vitesse quel que soit le framerate.
		local camera = workspace.CurrentCamera
		if camera then
			fovBase += (fovBaseTarget - fovBase) * math.min(1, FOV_LERP_SPEED * dt)
			fovPunch += (0 - fovPunch) * math.min(1, fovPunchDecay * dt)
			fovOffset += (fovOffsetTarget - fovOffset) * math.min(1, FOV_LERP_SPEED * dt)
			camera.FieldOfView = fovBase + fovPunch + fovOffset

			-- RECUL. On capture la distance du joueur AU DEMARRAGE, pas a chaque image : la relire en continu
			-- pendant qu'on la modifie ferait fuir la camera toujours plus loin.
			-- La VRAIE distance est camera -> Focus, jamais camera -> personnage : c'est elle, le zoom.
			zoomBoost += (zoomBoostTarget - zoomBoost) * math.min(1, ZOOM_LERP_SPEED * dt)
			if zoomBoostTarget > 0 and not zoomBase then
				zoomBase = (camera.CFrame.Position - camera.Focus.Position).Magnitude
				zoomMinWas = player.CameraMinZoomDistance
				zoomMaxWas = player.CameraMaxZoomDistance
			end
			if zoomBase then
				if zoomBoostTarget <= 0 and zoomBoost < 0.05 then
					-- Fini : on rend ses bornes au joueur. La camera est deja revenue a sa distance, rien ne saute.
					player.CameraMinZoomDistance = zoomMinWas
					player.CameraMaxZoomDistance = zoomMaxWas
					zoomBoost = 0
					zoomBase = nil
				else
					-- Min ET max sur la MEME valeur : la camera Custom s'y cale, et comme la valeur glisse, elle glisse.
					local d = (zoomBase :: number) + zoomBoost
					player.CameraMinZoomDistance = d
					player.CameraMaxZoomDistance = d
				end
			end
		end

		bobAmplitude += (bobTarget - bobAmplitude) * math.min(1, BOB_LERP_SPEED * dt)
		bobPhase += dt * bobFrequency
		-- math.abs sur le sinus : le bob rebondit vers le HAUT a chaque pas puis retombe, au lieu de passer
		-- symetriquement sous la ligne. C'est ce qui imite une foulee, pas un balancement de bateau.
		local bobY = math.abs(math.sin(bobPhase)) * bobAmplitude

		-- Plongee : ressort amorti vers zero. F = -k*x - c*v, integre en Euler. Suffisant a la frequence d'une
		-- camera ; pas besoin d'un integrateur plus fin pour un effet de 0.4 s.
		local dipForce = -DIP_STIFFNESS * dipPos - DIP_DAMPING * dipVel
		dipVel += dipForce * dt
		dipPos += dipVel * dt

		-- L'ECRITURE UNIQUE : secousse, bob et plongee reunis ici, nulle part ailleurs.
		composedOffset = shakeOffset + Vector3.new(0, bobY + dipPos, 0)

		local humanoid = getHumanoid()
		if humanoid then
			humanoid.CameraOffset = composedOffset
		end
	end)
end

return CameraEffects
