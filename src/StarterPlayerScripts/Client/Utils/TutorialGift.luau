--!strict
-- LE CADEAU DU GRAND-PERE, dans le didacticiel. Les feuilles ramassees, la pastille se pose sur lui et le badge
-- PARLER revient. Le joueur vient le voir : il lui fait face et lui donne son entreprise.
--
-- CHAQUE REPLIQUE A SA VOIX ET SA BULLE (voir GIFT_LINES), enchainees par la suite de repliques du controller.
--
-- A PART DE TutorialController pour la meme raison que TutorialLeaves : Luau n'accepte que 200 variables locales
-- au premier niveau d'un fichier, et le didacticiel en est tout pres.
--
-- LE CONTROLLER LUI PRETE CE QU'IL A DEJA : trouver le corps du grand-pere, le faire se tourner, le faire
-- gesticuler. Les refaire ici donnerait deux recherches du meme corps et deux copies des memes remotes.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TutorialConfigs = require(ReplicatedStorage.Modules.Configs.TutorialConfigs)
local CarryUtils = require(ReplicatedStorage.Modules.Utils.CarryUtils)
local InteractionPrompt = require(ReplicatedStorage.Modules.UI.Core.InteractionPrompt)
local WorldMarker = require(ReplicatedStorage.Modules.UI.Core.WorldMarker)

export type Hooks = {
	-- La part a laquelle s'accrochent la pastille et le badge.
	body: () -> BasePart?,
	-- Il se tourne vers le joueur.
	face: () -> (),
	-- Il gesticule pendant tant de secondes.
	talk: (seconds: number) -> (),
	-- Il dit ces repliques a la suite, chacune avec sa bulle (la suite de repliques du controller).
	say: (paths: { { string } }, lines: { [number]: { text: string, emotion: string? } }) -> (),
}

local TutorialGift = {}

local player = Players.LocalPlayer

local hooks: Hooks? = nil
local given = false
local marker: Frame? = nil
local markerPart: BasePart? = nil
local anchor: BasePart? = nil
local bound = false
local nextCheck = 0

local function getRoot(): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function setBound(active: boolean)
	if active == bound then
		return
	end
	bound = active
	if active then
		ContextActionService:BindAction(TutorialConfigs.GIFT_ACTION_NAME, function(_, state: Enum.UserInputState)
			-- LA TOUCHE SUIT LE BADGE : `Pass` laisse l'appui filer vers tout ce qui est a portee, donc sans ce test
			-- parler au grand-pere ramasserait aussi le seau pose a ses pieds.
			if state == Enum.UserInputState.Begin and InteractionPrompt.owns(anchor) then
				TutorialGift.give()
			end
			return Enum.ContextActionResult.Pass
			-- PAS DE BOUTON TACTILE AUTOMATIQUE (le `false`) : la pilule PARLER se tape deja.
		end, false, TutorialConfigs.ACTION_KEY)
	else
		ContextActionService:UnbindAction(TutorialConfigs.GIFT_ACTION_NAME)
	end
end

-- ON RETIRE NOTRE DEMANDE, jamais un cache global : les autres features a portee garderaient la leur.
local function release()
	if anchor then
		InteractionPrompt.release(anchor)
		anchor = nil
	end
	setBound(false)
end

local function clearMarker()
	WorldMarker.remove(marker)
	marker, markerPart = nil, nil
end

--- Ouvre l'etape : pastille sur lui, badge quand on approche. Idempotent.
function TutorialGift.start(h: Hooks)
	if hooks then
		return
	end
	hooks = h
	given = false
	nextCheck = 0
	print("[TutorialGift] Les feuilles sont ramassees : le grand-pere attend le joueur.")
end

--- IL DONNE SON ENTREPRISE. Appelee par la touche ET par le tap de la pilule. Une seule fois : un cadeau qui se
--- rejoue n'en est plus un.
function TutorialGift.give()
	local h = hooks
	if given or not h then
		return
	end
	given = true
	release()
	clearMarker()
	-- IL SE TOURNE ET IL GESTICULE EN MEME TEMPS que le texte arrive : on ne donne pas son entreprise de profil.
	h.face()
	h.talk(TutorialConfigs.GIFT_TALK_SECONDS)
	local paths: { { string } } = {}
	local lines: { [number]: { text: string, emotion: string? } } = {}
	for i, entry in TutorialConfigs.GIFT_LINES do
		paths[i] = entry.sound
		lines[i] = { text = entry.text, emotion = entry.emotion }
	end
	-- LA SUITE N'EST PAS ECRITE : le choix du nom et le depart en ville viendront apres ces repliques.
	h.say(paths, lines)
end

--- A appeler a chaque image.
function TutorialGift.step(now: number)
	local h = hooks
	if not h or given then
		return
	end
	local body = h.body()
	-- LA PASTILLE, mains libres ou pas : elle DESIGNE, elle ne propose rien. Accrochee a son CORPS et pas a un point,
	-- sinon elle resterait la ou il etait au moment du calcul.
	if body and markerPart ~= body then
		clearMarker()
		marker = WorldMarker.show(body, Vector3.new(0, TutorialConfigs.GRANDPA_MARKER_UP, 0))
		markerPart = body
	end
	if now < nextCheck then
		return
	end
	nextCheck = now + TutorialConfigs.PROMPT_INTERVAL
	local me = getRoot()
	-- LES MAINS LIBRES, comme apres la tonte : `E` reposerait le seau EN MEME TEMPS que la conversation.
	if not (body and me and CarryUtils.isFree(player)) then
		release()
		return
	end
	-- DISTANCE RADIALE, a plat : meme regle que le badge d'apres la tonte.
	local flat = ((body :: BasePart).Position - (me :: BasePart).Position) * Vector3.new(1, 0, 1)
	if flat.Magnitude > TutorialConfigs.TALK_RADIUS then
		release()
		return
	end
	if anchor ~= body then
		release()
		anchor = body
	end
	setBound(true)
	-- REDEMANDE A CHAQUE PASSAGE : ca ne fait que rafraichir, et la pilule revient toute seule si une voisine l'a
	-- prise puis relachee.
	InteractionPrompt.show(
		body :: BasePart,
		TutorialConfigs.TALK_PROMPT_KEY,
		TutorialConfigs.TALK_PROMPT_LABEL,
		TutorialConfigs.TALK_PROMPT_OFFSET,
		TutorialGift.give,
		TutorialConfigs.TALK_PROMPT_TITLE
	)
end

--- Coupe tout : badge, touche, pastille. Celui qui cree est celui qui nettoie.
function TutorialGift.stop()
	release()
	clearMarker()
	hooks = nil
	given = false
end

return TutorialGift
