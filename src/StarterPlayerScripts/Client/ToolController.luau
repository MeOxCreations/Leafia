--!strict
-- Effets visuels de l'apparition d'un outil dans la main. Le client ne fait que reagir : c'est ToolService
-- qui decide qui tient quoi.
--
-- L'effet est GENERIQUE. Il ne connait pas le taille-haie : il lit le nom de l'effet dans ToolConfigs et joue
-- ce qu'il trouve. Un futur secateur passera par le meme code sans y toucher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")

local ToolConfigs = require(ReplicatedStorage.Modules.Configs.ToolConfigs)
local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)
local CameraEffects = require(script.Parent.Utils.CameraEffects)

local ToolController = {}

local TOOL_ATTRIBUTE = "LeafiaTool"
-- Compteur incremente par le serveur a chaque butee de corde. Un compteur et non un booleen : deux tirages
-- d'affilee ecriraient la meme valeur et l'attribut ne changerait pas.
local PULL_TICK_ATTRIBUTE = "LeafiaPullTick"
-- Emplacements d'outils facon inventaire : chaque touche equipe SON outil (ou le range si deja en main). 1 = cisaille
-- (outil de depart), 2 = taille-haie. Reflexe des joueurs sur la plateforme, et ca laisse E libre pour l'interaction.
local TOOL_SLOTS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.One] = "Shear",
	[Enum.KeyCode.Two] = "HedgeTrimmer",
}
local ASSET_TIMEOUT = 10
-- Filet si un emetteur n'a pas de Lifetime exploitable. Les particules vivent rarement plus longtemps.
local FALLBACK_EFFECT_LIFETIME = 3

local player = Players.LocalPlayer
local playedFor: { [Instance]: boolean } = {}

local function findEffectSource(effectName: string): Instance?
	local assets = ReplicatedStorage:WaitForChild("Assets", ASSET_TIMEOUT)
	if not assets then
		return nil
	end
	local effects = assets:WaitForChild("Effects", ASSET_TIMEOUT)
	if not effects then
		return nil
	end
	return effects:FindFirstChild(effectName)
end

-- On prend l'Attachment, pas la Part qui la contient : coller une Part dans la main ajouterait de la
-- geometrie visible et de la physique pour rien. L'Attachment porte les emetteurs, c'est tout ce qu'on veut.
local function findEffectAttachment(source: Instance): Attachment?
	if source:IsA("Attachment") then
		return source
	end
	for _, d in ipairs(source:GetDescendants()) do
		if d:IsA("Attachment") then
			return d
		end
	end
	return nil
end

-- Duree de vie reelle de l'effet : la plus longue duree de particule parmi les emetteurs. Un delai fixe
-- couperait les longues et laisserait trainer les courtes.
local function effectLifetime(attachment: Attachment): number
	local longest = 0
	for _, d in ipairs(attachment:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			longest = math.max(longest, d.Lifetime.Max)
		end
	end
	return if longest > 0 then longest else FALLBACK_EFFECT_LIFETIME
end

local function playSpawnEffect(character: Model, toolName: string)
	local config = ToolConfigs[toolName]
	if not (config and config.spawnEffect) then
		return
	end

	local hand = character:FindFirstChild(config.handPart)
	if not (hand and hand:IsA("BasePart")) then
		return
	end

	local source = findEffectSource(config.spawnEffect)
	if not source then
		return
	end
	local attachment = findEffectAttachment(source)
	if not attachment then
		return
	end

	local clone = attachment:Clone()
	clone.Parent = hand

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			-- Chaque emetteur peut imposer son propre nombre via un attribut pose dans Studio. Une onde de
			-- choc veut 1 particule, des braises en veulent 20 : un chiffre unique pour tous donne soit une
			-- gerbe d'ondes de choc, soit trois braises perdues.
			local count = d:GetAttribute("EmitCount")
			d:Emit(if typeof(count) == "number" then count else config.emitCount)
		end
	end

	Debris:AddItem(clone, effectLifetime(clone))
end

local function onToolAdded(character: Model, child: Instance)
	if playedFor[child] then
		return
	end
	local toolName = child:GetAttribute(TOOL_ATTRIBUTE)
	if typeof(toolName) ~= "string" then
		return
	end
	playedFor[child] = true
	playSpawnEffect(character, toolName)

	-- Retour camera a chaque butee de corde. On ecoute l'attribut plutot qu'un remote : le modele et son
	-- attribut se repliquent ensemble, donc rien a synchroniser et rien a rater au spawn.
	local config = ToolConfigs[toolName]
	if not config then
		return
	end
	child:GetAttributeChangedSignal(PULL_TICK_ATTRIBUTE):Connect(function()
		-- Les FX ne se declenchent QUE pour le porteur. Secouer la camera d'un voisin parce qu'un autre joueur
		-- demarre son moteur serait absurde, et injouable sur un serveur rempli.
		CameraEffects.Shake(config.pullShakeIntensity, config.pullShakeDuration)
		CameraEffects.PunchFov(config.pullFovPunch)
	end)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		onToolAdded(character, child)
	end)
	-- Le personnage peut deja porter l'outil quand ce script demarre : ChildAdded ne rattrape pas le passe.
	-- Sans ce balayage, le tout premier equipement de la session n'aurait jamais d'effet.
	for _, child in ipairs(character:GetChildren()) do
		onToolAdded(character, child)
	end
end

function ToolController.init()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end

	-- Le client ne fait qu'AVERTIR quel emplacement a ete presse. Le serveur valide le nom, verifie ce que le joueur
	-- tient et tranche (equiper / ranger). Le client ne touche jamais a l'outil lui-meme.
	local selectRemote = RemoteSetup.getRemote("SelectTool", "Tool")
	if not (selectRemote and selectRemote:IsA("RemoteEvent")) then
		warn("[ToolController] Remote Tool/SelectTool introuvable")
		return
	end

	local activateRemote = RemoteSetup.getRemote("ActivateTool", "Tool")
	local throttleRemote = RemoteSetup.getRemote("SetThrottle", "Tool")

	local function isPrimaryClick(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed est vrai quand le joueur tape dans le chat ou clique dans une interface. Sans ce test,
		-- ecrire "1" a un ami rangerait son taille-haie, et cliquer sur un bouton lancerait le demarrage.
		if gameProcessed then
			return
		end

		local slotTool = TOOL_SLOTS[input.KeyCode]
		if slotTool then
			selectRemote:FireServer(slotTool)
		elseif isPrimaryClick(input) then
			-- Le clic sert a deux choses selon l'etat, mais le CLIENT ne connait pas l'etat : il envoie les
			-- deux signaux et laisse le serveur trancher. ActivateTool fait avancer le demarrage (tirages) ;
			-- SetThrottle(true) accelere les lames une fois le moteur en marche. Le serveur ignore celui qui
			-- ne s'applique pas a son etat courant.
			if activateRemote and activateRemote:IsA("RemoteEvent") then
				activateRemote:FireServer()
			end
			if throttleRemote and throttleRemote:IsA("RemoteEvent") then
				throttleRemote:FireServer(true)
			end
		end
	end)

	-- Relachement du clic : on coupe l'accelerateur. InputEnded n'a pas de gameProcessed fiable a filtrer ici,
	-- et de toute facon relacher ne declenche jamais une action indesirable, au pire ca coupe une acceleration
	-- que le serveur ignorait deja.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if isPrimaryClick(input) and throttleRemote and throttleRemote:IsA("RemoteEvent") then
			throttleRemote:FireServer(false)
		end
	end)
end

return ToolController
