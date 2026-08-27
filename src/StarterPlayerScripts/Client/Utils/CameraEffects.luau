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
-- VITESSE PROPRE, separee de FOV_LERP_SPEED. Le fond change en permanence (repos <-> mouvement) et doit
-- rester vif ; un effet TENU, lui, doit s'installer lentement. Partager la vitesse forcerait a compenser
-- l'un en reglant l'autre, et le compensateur serait toujours une estimation.
-- BAS = lent et pose. 1.1 met environ deux secondes a s'installer.
local FOV_OFFSET_LERP_SPEED = 1.1
-- Cadence REELLEMENT utilisee, remise a la valeur ci-dessus a chaque appel qui n'en demande pas d'autre : une
-- cadence exceptionnelle ne doit pas rester en place pour l'effet suivant.
local fovOffsetSpeed = FOV_OFFSET_LERP_SPEED
local fovOffset = 0
local fovOffsetTarget = 0

-- ===== Recul de camera =====
-- La camera Custom de Roblox ne se recule pas : c'est le JOUEUR qui possede sa distance de zoom. On deplace donc
-- ses bornes de zoom, en douceur, et on les rend telles quelles a la fin. Bouger la borne PROGRESSIVEMENT evite
-- le coup sec qu'un clamp pose d'un coup produirait.
-- Pendant le recul le joueur ne peut plus zoomer : c'est voulu, l'effet dure le temps d'une touche maintenue.
-- MEME allure que FOV_OFFSET_LERP_SPEED, et ce n'est pas un hasard : recul et resserrement sont les deux
-- moities du MEME geste. A vitesses differentes on verrait l'un arriver avant l'autre, et le mouvement
-- se lirait comme deux effets colles au lieu d'un seul.
-- Allure PAR DEFAUT. Lente expres : elle sert aux effets de fond, ou un changement de distance ne doit pas se
-- remarquer. Un appelant qui veut une reaction VIVE la passe en argument -- meme mecanique que SetFovOffset.
local ZOOM_LERP_SPEED = 1.1
-- Distance minimale gardee, en studs. Sous un demi-stud Roblox bascule en vue subjective.
local MIN_ZOOM = 1.5
local zoomBoost = 0
local zoomBoostTarget = 0
local zoomBoostSpeed = ZOOM_LERP_SPEED
local zoomBase: number? = nil -- distance du joueur AU MOMENT ou le recul commence
local zoomMinWas, zoomMaxWas = 0, 0
local zoomSaved = false -- les bornes du joueur sont-elles mises de cote ?
-- VUE SUBJECTIVE. Deuxieme raison de toucher aux bornes de zoom, et elle PRIME sur le recul : reculer la vue n'a
-- aucun sens quand on est dans les yeux. Elle vit ICI et pas dans le controller qui la demande, parce que les
-- bornes de zoom n'ont droit qu'a UN ecrivain -- c'est la regle en tete de ce fichier.
local firstPerson = false
-- ELLE GLISSE, elle ne bascule pas. Passer d'un coup de la distance du joueur a zero est un COUP SEC : on se
-- retrouve dans sa tete sans avoir vu le chemin, et le retour est pire encore. On fait donc voyager la distance.
-- BAS = lent. 4.5 met environ une demi-seconde.
local FP_LERP_SPEED = 4.5
local fpAmount = 0 -- 0 = vue de dos, 1 = dans les yeux. Lu aussi par l'appelant, pour effacer le corps AU MEME rythme.
local fpBase: number? = nil -- distance du joueur AVANT d'entrer : c'est la qu'on revient
-- ECART MINIMAL garde entre l'oeil et la tete, en studs. A ZERO, Roblox considere qu'on est en vue subjective et
-- VERROUILLE la souris au centre a chaque image -- impossible de lui reprendre, meme en ecrivant apres lui
-- (verifie a l'ecran). Laisser un cheveu d'ecart le fait renoncer, et la souris redevient libre.
-- Sert donc uniquement a RENDRE LE CURSEUR ; le reste du temps il vaut zero et rien ne change.
local fpGap = 0

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
--
-- `speed` impose la CADENCE de cette transition, pour un effet que l'allure par defaut rendrait trop mou. Omise,
-- c'est FOV_OFFSET_LERP_SPEED qui s'applique -- une allure lente, faite pour des resserrements de fond. Un
-- resserrement qui doit CLAQUER a l'ouverture d'une porte n'a rien a voir avec elle : deux moments differents,
-- deux cadences, sinon regler l'un derangerait l'autre.
function CameraEffects.SetFovOffset(amount: number, speed: number?)
	fovOffsetTarget = amount
	fovOffsetSpeed = speed or FOV_OFFSET_LERP_SPEED
end

-- DECALAGE de distance TENU, en studs. 0 = la camera revient a la distance qu'avait choisie le joueur.
--
-- POSITIF elle RECULE, NEGATIF elle SE RAPPROCHE. Le negatif n'etait pas supporte : la distance de depart n'etait
-- capturee que pour une valeur positive, donc une valeur negative ne faisait simplement rien -- sans erreur.
--
-- Meme regle : c'est l'appelant qui l'eteint.
function CameraEffects.SetZoomBoost(studs: number, speed: number?)
	zoomBoostTarget = studs
	-- L'allure appartient a l'APPEL, pas au module : le meme decalage doit pouvoir s'installer lentement pour un
	-- effet de fond et d'un coup pour une reaction. Une seule constante partagee forcerait a choisir.
	zoomBoostSpeed = speed or ZOOM_LERP_SPEED
end

--- VUE SUBJECTIVE. Colle les bornes de zoom a zero tant que c'est vrai, et rend au joueur les siennes en sortant.
--- Passe par ici et pas par l'appelant : les bornes de zoom n'ont droit qu'a UN ecrivain (voir la regle en tete).
function CameraEffects.SetFirstPerson(on: boolean)
	firstPerson = on
end

--- Ou en est le glissement : 0 = vue de dos, 1 = dans les yeux. A lire pour accorder un effet AU MEME rythme --
--- effacer le corps d'un coup pendant que la camera glisse encore montrerait un trou a la place du personnage.
function CameraEffects.GetFirstPersonAmount(): number
	return fpAmount
end

--- Ecart minimal entre l'oeil et la tete, en studs, pendant la vue subjective. Zero = colle a la tete, et Roblox
--- verrouille alors la souris au centre. Une valeur non nulle le fait renoncer : c'est la SEULE facon de rendre le
--- curseur sans quitter la vue subjective (verifie a l'ecran, l'ecriture de MouseBehavior apres lui ne suffit pas).
function CameraEffects.SetFirstPersonGap(studs: number)
	fpGap = math.max(studs, 0)
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
			fovOffset += (fovOffsetTarget - fovOffset) * math.min(1, fovOffsetSpeed * dt)
			camera.FieldOfView = fovBase + fovPunch + fovOffset

			-- RECUL. On capture la distance du joueur AU DEMARRAGE, pas a chaque image : la relire en continu
			-- pendant qu'on la modifie ferait fuir la camera toujours plus loin.
			-- La VRAIE distance est camera -> Focus, jamais camera -> personnage : c'est elle, le zoom.
			-- Les bornes du joueur sont mises de cote a la PREMIERE raison qui se presente, et rendues quand plus
			-- aucune ne tient. Une capture par raison finirait par memoriser une borne qu'on avait deja modifiee.
			if (firstPerson or zoomBoostTarget ~= 0) and not zoomSaved then
				zoomSaved = true
				zoomMinWas = player.CameraMinZoomDistance
				zoomMaxWas = player.CameraMaxZoomDistance
			end
			-- La distance de DEPART se capture a l'entree, jamais en continu : la relire pendant qu'on la modifie
			-- ferait fuir la camera toujours plus loin. Meme piege que le recul, juste au-dessus.
			if firstPerson and not fpBase then
				fpBase = math.max((camera.CFrame.Position - camera.Focus.Position).Magnitude, 0.5)
			end
			local fpTarget = if firstPerson then 1 else 0
			fpAmount += (fpTarget - fpAmount) * math.min(1, FP_LERP_SPEED * dt)
			-- ON CLE SUR LA CIBLE. Un lerp exponentiel n'atteint JAMAIS son but : sans ca, `fpAmount` resterait a
			-- 0.004 pour toujours et on ne rendrait donc JAMAIS ses bornes au joueur -- il ne pourrait plus zoomer,
			-- sans que rien ne l'explique.
			if math.abs(fpTarget - fpAmount) < 0.01 then
				fpAmount = fpTarget
			end

			if fpAmount > 0 then
				-- LA VUE SUBJECTIVE PRIME sur le recul de camera : reculer la vue n'a aucun sens quand on est dans
				-- les yeux, et deux raisons ecrivant la meme borne se battraient a chaque image.
				-- Le recul est remis a plat pour qu'en ressortant il reparte d'une distance FRAICHE.
				zoomBase = nil
				zoomBoost = 0
				-- L'ECART PREND LE DESSUS quand il est demande, sans jamais faire RECULER la camera plus que le
				-- glissement en cours : au debut du voyage la distance est encore grande, l'ecart ne doit pas s'y
				-- ajouter.
				local d = math.max((fpBase or 12) * (1 - fpAmount), math.min(fpGap, fpBase or 12))
				player.CameraMinZoomDistance = d
				player.CameraMaxZoomDistance = d
			else
				fpBase = nil
				zoomBoost += (zoomBoostTarget - zoomBoost) * math.min(1, zoomBoostSpeed * dt)
				if zoomBoostTarget ~= 0 and not zoomBase then
					zoomBase = (camera.CFrame.Position - camera.Focus.Position).Magnitude
				end
				if zoomBase then
					if zoomBoostTarget == 0 and math.abs(zoomBoost) < 0.05 then
						zoomBoost = 0
						zoomBase = nil
					else
						-- Min ET max sur la MEME valeur : la camera Custom s'y cale, et comme la valeur glisse,
						-- elle glisse.
						-- PLANCHER. En dessous d'un demi-stud Roblox bascule en vue subjective : un rapprochement un
						-- peu fort -- ou un joueur deja zoome au maximum -- ferait passer la camera DANS la tete,
						-- et on chercherait la cause du cote de la vue subjective.
						local d = math.max((zoomBase :: number) + zoomBoost, MIN_ZOOM)
						player.CameraMinZoomDistance = d
						player.CameraMaxZoomDistance = d
					end
				end
				if zoomSaved and not zoomBase then
					-- Plus aucune raison de tenir les bornes : on les rend. La camera est deja revenue a sa
					-- distance, donc rien ne saute.
					player.CameraMinZoomDistance = zoomMinWas
					player.CameraMaxZoomDistance = zoomMaxWas
					zoomSaved = false
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
