--!strict
-- AUTORITE serveur sur le PLOT choisi par chaque joueur.
--
-- RUNTIME pour l'instant (en memoire, pas de save) : au Start de l'ecran de selection, le client ANNONCE quel Slot
-- il a choisi ; le serveur VALIDE que c'est un vrai Slot (le client ment toujours) et retient l'attribution. Sert a
-- n'autoriser que ce qui touche SON plot (ouvrir SA boite aux lettres, plus tard : build dessus, etc.).
--
-- La PERSISTANCE (le plot possede entre deux sessions) viendra avec le systeme de save : ici on pose juste le tuyau
-- d'autorite. Point d'entree unique de "quel plot est a qui" : les autres services LISENT via ownsSlot / getPlotName.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local BuildConfigs = require(ReplicatedStorage.Modules.Configs.BuildConfigs)

local PlotService = {}

local assignments: { [Player]: string } = {} -- joueur -> nom du Slot choisi cette session
-- Attribut pose sur le JOUEUR (replique au client) : le nom de son plot. Le client (ex MailboxController) le lit pour
-- n'afficher l'invite que sur SA boite. Meme nom cote client.
local PLOT_ATTRIBUTE = "LeafiaPlot"

-- Nom de la part-sol de chaque plot (sert de PrimaryPart : pivot fixe).
local GROUND_NAME = "PrimaryGround"

-- STREAMING : les plots sont eloignes les uns des autres. Avec StreamingEnabled (surtout sur MOBILE, ou le streaming est
-- plus serre), un client ne recoit QUE les plots proches de lui -> l'ecran de selection n'en voit que quelques-uns (2 au
-- lieu de tous). On force chaque plot en PERSISTENT : il est alors TOUJOURS replique a tous, quelle que soit la position.
--
-- Or ModelStreamingMode n'existe que sur les MODELS, et un plot pose en FOLDER dans Studio ne peut donc pas l'etre. Au
-- lieu d'exiger une conversion manuelle en Studio (galere, et facile a oublier), le SERVEUR convertit ici lui-meme les
-- Folders en Models de meme nom (transparent : les autres services cherchent le plot par son NOM). Resultat : rien a
-- faire cote Studio, ca marche des le boot. En tache de fond + WaitForChild pour ne pas bloquer l'init.
local function makePlotsPersistent()
	local worlds = workspace:WaitForChild("Worlds", 20)
	local plots = worlds and worlds:WaitForChild("Plots", 20)
	if not plots then
		warn("[PlotService] Worlds.Plots introuvable : plots non persistants, l'ecran de selection peut en rater (streaming).")
		return
	end
	local count = 0
	for _, plot in ipairs(plots:GetChildren()) do
		-- Folder -> Model (meme nom) : on reparente les enfants tels quels (positions, welds, connexions preservees,
		-- ce sont les MEMES instances). GetChildren() est un instantane, donc detruire / ajouter pendant la boucle est sur.
		if plot:IsA("Folder") then
			local model = Instance.new("Model")
			model.Name = plot.Name
			for _, child in ipairs(plot:GetChildren()) do
				child.Parent = model
			end
			model.Parent = plots
			plot:Destroy()
			plot = model
		end
		if plot:IsA("Model") then
			-- PrimaryPart FIXE = PrimaryGround : pivot stable quand on ajoutera des builds (sinon la bounding box derive
			-- des qu'on pose un objet dans le plot, cf journal).
			local ground = plot:FindFirstChild(GROUND_NAME)
			if ground and ground:IsA("BasePart") then
				plot.PrimaryPart = ground
				-- Le sol doit faire un MULTIPLE de TILE_SIZE : sinon la grille de build et le snap (qui partent d'un COIN)
				-- se decalent d'un reste au bord. On arrondit ici, au boot serveur -> robuste quelle que soit la taille
				-- posee en Studio (ex 170 -> 171), sans rien avoir a regler a la main. +/- 1-2 studs, invisible.
				local tile = BuildConfigs.TILE_SIZE
				local sx = math.max(tile, math.round(ground.Size.X / tile) * tile)
				local sz = math.max(tile, math.round(ground.Size.Z / tile) * tile)
				if sx ~= ground.Size.X or sz ~= ground.Size.Z then
					ground.Size = Vector3.new(sx, ground.Size.Y, sz)
				end
			end
			plot.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			count += 1
		end
	end
	if count == 0 then
		warn("[PlotService] Aucun plot sous Worlds.Plots : l'ecran de selection sera vide.")
	end
end

-- Le Slot demande existe-t-il vraiment sous Worlds.Plots ? On ne fait PAS confiance au nom envoye par le client.
local function isRealSlot(name: string): boolean
	local worlds = workspace:FindFirstChild("Worlds")
	local plots = worlds and worlds:FindFirstChild("Plots")
	return plots ~= nil and plots:FindFirstChild(name) ~= nil
end

-- Nom du Slot choisi par le joueur, ou nil s'il n'a pas encore choisi.
function PlotService.getPlotName(player: Player): string?
	return assignments[player]
end

-- Le joueur possede-t-il le Slot donne ? (== il l'a choisi cette session)
function PlotService.ownsSlot(player: Player, slotName: string): boolean
	return assignments[player] == slotName
end

function PlotService.init()
	task.spawn(makePlotsPersistent) -- les plots ne doivent JAMAIS streamer out (ecran de selection les veut tous)

	local remote = RemoteSetup.getRemote("SelectPlot", "Plot")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(function(player: Player, slotName)
			-- Le client ment : on valide TOUT. Le nom doit etre une string ET correspondre a un vrai Slot.
			if typeof(slotName) == "string" and isRealSlot(slotName) then
				assignments[player] = slotName
				player:SetAttribute(PLOT_ATTRIBUTE, slotName) -- replique au client (l'invite ne s'affiche que chez le proprietaire)
			end
		end)
	else
		warn("[PlotService] Remote Plot/SelectPlot introuvable : les plots ne seront pas attribues.")
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		assignments[player] = nil
	end)
end

return PlotService
