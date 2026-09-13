--!strict
-- LES FEUILLES A RAMASSER, dans le didacticiel : chaque tas au sol respire en blanc, et une pastille " ! " se pose
-- sur le plus proche du joueur.
--
-- A PART DE TutorialController, et pas par gout du rangement : Luau n'accepte que 200 variables locales au premier
-- niveau d'un fichier, et le didacticiel les avait atteintes -- le client entier refusait de demarrer. Une
-- fonctionnalite qui a son etat, son debut et sa fin tient dans son propre module.
--
-- ALLUME QUAND LE GRAND-PERE EN PARLE (`start`), et ne s'eteint plus seul : une fois les feuilles ramassees, il n'y a
-- simplement plus de tas a faire briller.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)
local HedgeConfigs = require(ReplicatedStorage.Modules.Configs.HedgeConfigs)
local RakeConfigs = require(ReplicatedStorage.Modules.Configs.RakeConfigs)
local WorldMarker = require(ReplicatedStorage.Modules.UI.Core.WorldMarker)

local TutorialLeaves = {}

local player = Players.LocalPlayer

-- Le nom des petits tas : dernier element du chemin d'asset, lu et pas recopie (meme regle que RakeService).
local SMALL_NAME = HedgeConfigs.STOCK_DEBRIS_ASSET[#HedgeConfigs.STOCK_DEBRIS_ASSET]

local on = false
local clock = 0
local halos: { Highlight } = {}
local nextScan = 0
-- La pastille et la part qu'elle suit. UNE seule, sur un tas a la fois : dix pastilles sur dix tas ne designent
-- plus rien.
local marker: Frame? = nil
local markerPart: BasePart? = nil

--- Allume les feuilles. Idempotent : le relancer ne remet pas le battement a zero.
function TutorialLeaves.start()
	if on then
		return
	end
	on = true
	nextScan = 0
	print("[TutorialLeaves] Le grand-pere explique les feuilles : les tas respirent, pastille sur le plus proche.")
end

--- La pastille passe au tas le plus proche, mais SEULEMENT si le sien a disparu.
---
--- Suivre "le plus proche" a chaque relecture la ferait sauter d'un tas a l'autre des que le joueur passe entre
--- deux -- une pastille qui hesite ne designe rien. Le tas ramasse (fondu dans un gros tas, avale par le seau), elle
--- passe au suivant.
local function updateMarker(piles: { Model })
	local current = markerPart
	if current and current.Parent then
		return
	end
	WorldMarker.remove(marker)
	marker, markerPart = nil, nil
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local from = if root and root:IsA("BasePart") then root.Position else nil
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, pile in piles do
		-- UNE PART, pas le modele : la pastille s'accroche a une part. Les feuilles sont des MeshParts.
		local part = pile.PrimaryPart or pile:FindFirstChildWhichIsA("BasePart", true)
		if part then
			local dist = if from then ((part :: BasePart).Position - from).Magnitude else 0
			if dist < bestDist then
				best, bestDist = part :: BasePart, dist
			end
		end
	end
	if best then
		markerPart = best
		marker = WorldMarker.show(best, Vector3.new(0, TutorialConfigs.LEAVES_MARKER_UP, 0))
	end
end

--- A appeler a chaque image. La liste des tas est relue a intervalle, le battement ecrit a chaque image : le rateau
--- fait naitre et disparaitre des tas, une liste figee raterait tous ceux qui arrivent ensuite.
---
--- Une limite a connaitre : Roblox n'affiche que 31 `Highlight` a la fois. Une face de haie en pose une dizaine.
function TutorialLeaves.step(dt: number, now: number)
	if not on then
		return
	end
	if now >= nextScan then
		nextScan = now + TutorialConfigs.LEAVES_RESCAN_INTERVAL
		table.clear(halos)
		local piles: { Model } = {}
		for _, folderName in { HedgeConfigs.STOCK_FOLDER, RakeConfigs.PILE_FOLDER } do
			local folder = Workspace:FindFirstChild(folderName)
			if folder then
				for _, d in folder:GetDescendants() do
					if d:IsA("Highlight") and d.Name == TutorialConfigs.LEAVES_HIGHLIGHT_NAME then
						table.insert(halos, d)
					elseif d:IsA("Model") and (d.Name == SMALL_NAME or d.Name == RakeConfigs.PILE_NAME) then
						table.insert(piles, d)
					end
				end
			end
		end
		updateMarker(piles)
	end
	clock += dt
	-- Meme formule que le halo de la porte : un cosinus repart de lui-meme, donc aucune saccade au bouclage.
	local a = 0.5 - 0.5 * math.cos(clock * math.pi * 2 / TutorialConfigs.PULSE_PERIOD)
	local fill = TutorialConfigs.FILL_MAX + (TutorialConfigs.FILL_MIN - TutorialConfigs.FILL_MAX) * a
	for _, halo in halos do
		if halo.Parent then
			-- LE SERVEUR LES POSE ETEINTS : on les rallume chez nous seulement, le reglage ne remonte pas.
			if not halo.Enabled then
				halo.Enabled = true
			end
			if halo.FillColor ~= TutorialConfigs.LEAVES_HIGHLIGHT_FILL then
				halo.FillColor = TutorialConfigs.LEAVES_HIGHLIGHT_FILL
			end
			halo.FillTransparency = fill
		end
	end
end

--- Eteint tout : plus de battement, plus de pastille. Le halo est ECRIT eteint plutot qu'abandonne, sinon il
--- resterait fige a mi-battement. Celui qui cree est celui qui nettoie.
function TutorialLeaves.stop()
	on = false
	for _, halo in halos do
		if halo.Parent then
			halo.FillTransparency = TutorialConfigs.FILL_MAX
		end
	end
	table.clear(halos)
	WorldMarker.remove(marker)
	marker, markerPart = nil, nil
end

return TutorialLeaves
