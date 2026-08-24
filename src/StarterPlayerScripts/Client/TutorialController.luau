--!strict
-- DIDACTICIEL, cote client : ce qui GUIDE le joueur. Pendant de TutorialService, qui le pose deja face a la
-- maison du grand-pere.
--
-- Pour l'instant une seule chose : le HALO QUI RESPIRE sur la porte. Il dit "viens ici" sans ecrire une
-- consigne -- donc sans rien a traduire, et sans interface a poser par-dessus le monde.
--
-- PUREMENT VISUEL. Aucun etat de jeu ne depend de ce halo : l'eteindre ne bloque rien, l'oublier allume ne
-- casse rien. C'est important pour la suite -- la scene cinematique pourra le couper sans precaution.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)

local TutorialController = {}

local highlight: Highlight? = nil
local lastScanAt = 0
local startedAt = 0
local warned = false
local elapsed = 0
local doorHint = true
local conn: RBXScriptConnection? = nil

-- Le halo de la porte, ou nil. On tente le CHEMIN d'abord (trois FindFirstChild), et on ne balaye le Workspace
-- qu'en secours : le balayage marche meme si la maison demenage, mais il parcourt des milliers d'instances.
local function findHighlight(): Highlight?
	local node: Instance? = Workspace
	for _, name in ipairs(TutorialConfigs.DOOR_PATH) do
		node = node and node:FindFirstChild(name)
	end
	local door = node and node:FindFirstChild(TutorialConfigs.DOOR_NAME)
	if door then
		local found = door:FindFirstChild(TutorialConfigs.HIGHLIGHT_NAME)
		if found and found:IsA("Highlight") then
			return found
		end
	end

	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == TutorialConfigs.DOOR_NAME then
			local found = d:FindFirstChild(TutorialConfigs.HIGHLIGHT_NAME)
			if found and found:IsA("Highlight") then
				return found
			end
		end
	end
	return nil
end

local function step(dt: number)
	local now = os.clock()

	if not (highlight and highlight.Parent) then
		highlight = nil
		if now - lastScanAt < TutorialConfigs.RESCAN_INTERVAL then
			return
		end
		lastScanAt = now
		highlight = findHighlight()
		if not highlight then
			if not warned and now - startedAt > TutorialConfigs.NOT_FOUND_WARN_AFTER then
				warned = true
				warn(
					`[Tutorial] Aucun Highlight "{TutorialConfigs.HIGHLIGHT_NAME}" sous un Model `
						.. `"{TutorialConfigs.DOOR_NAME}" : la porte ne clignotera pas. Rojo ne synchronise pas le `
						.. "Workspace, ce Highlight se pose A LA MAIN dans CHAQUE place."
				)
			end
			return
		end
	end

	local halo = highlight :: Highlight
	if not doorHint then
		-- On ECRIT la valeur eteinte plutot que de sortir en silence : le halo a pu etre coupe en plein battement,
		-- et il resterait alors fige a moitie visible.
		if halo.FillTransparency ~= TutorialConfigs.FILL_MAX then
			halo.FillTransparency = TutorialConfigs.FILL_MAX
		end
		return
	end

	elapsed += dt
	-- SINUS, pas un aller-retour lineaire. Une respiration n'a ni depart ni arrivee : le cosinus repart de
	-- lui-meme, donc aucune saccade au bouclage. Un lerp aller-retour casse a chaque extremite.
	local a = 0.5 - 0.5 * math.cos(elapsed * math.pi * 2 / TutorialConfigs.PULSE_PERIOD)
	halo.FillTransparency = TutorialConfigs.FILL_MAX + (TutorialConfigs.FILL_MIN - TutorialConfigs.FILL_MAX) * a
end

--- Allume ou eteint le halo de la porte. A appeler avec `false` quand la scene se lance : un halo qui continue
--- de respirer pendant une cinematique tire l'oeil hors du plan.
function TutorialController.setDoorHint(on: boolean)
	doorHint = on
	local halo = highlight
	if halo and halo.Parent and not on then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
end

function TutorialController.init()
	startedAt = os.clock()
	-- LA BOUCLE PART MEME SI LA PORTE N'EST PAS ENCORE LA. Avec StreamingEnabled elle arrive souvent apres le
	-- spawn : sortir ici laisserait le halo mort pour toute la session, sans la moindre erreur pour le dire.
	-- Elle coute une comparaison de date tant qu'il n'y a rien a animer.
	if conn then
		return
	end
	conn = RunService.Heartbeat:Connect(step)
end

--- Coupe la boucle et rend le halo a son etat eteint. Celui qui cree est celui qui nettoie.
function TutorialController.stop()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	local halo = highlight
	if halo and halo.Parent then
		halo.FillTransparency = TutorialConfigs.FILL_MAX
	end
	highlight = nil
end

return TutorialController
