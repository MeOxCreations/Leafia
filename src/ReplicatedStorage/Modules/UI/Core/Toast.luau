--!strict
-- TOASTS : petits messages qui popent, s'empilent, tiennent quelques secondes, puis se retractent.
--
-- Primitive UI REUTILISABLE : n'importe quelle feature client appelle Toast.show(kind, text). Le serveur, lui,
-- passe par le remote UI/Notify : il n'affiche rien, il DEMANDE au client d'afficher. Le client est le seul a
-- toucher a l'ecran.
--
-- L'interface (NotificationUI) est construite dans STUDIO, pas ici : Templates.TemplateNotification (le modele
-- d'un toast) et Holder.List (la pile, avec son UIListLayout). Ce module ne fait que cloner, remplir, animer et
-- detruire. Il ne suppose aucune mise en page : c'est le UIListLayout qui place, on n'anime donc que le Scale.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local RemoteSetup = require(ReplicatedStorage.Shared.RemoteSetup)

local Toast = {}

local player = Players.LocalPlayer

-- ===== Reglages =====
local HOLD = 4 -- secondes affiche avant retrait automatique
local MAX = 5 -- toasts simultanes ; au-dela, le plus vieux part
local IN = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Son joue a chaque toast, cherche sous SoundService a ce chemin. ABSENT = pas de son, sans bruit dans la
-- console : un son de confort qui manque n'est ni anormal ni actionnable. Depose un Sound la pour l'activer.
local SOUND_PATH = { "UI", "Notification" }

-- Couleur d'accent (UIStroke + UIGradient) selon le TYPE de notif. Type inconnu -> pas de teinte, le modele
-- garde ses couleurs de Studio.
local KIND_COLORS: { [string]: Color3 } = {
	Warning = Color3.fromRGB(255, 80, 60),
	Info = Color3.fromRGB(70, 160, 255),
	Success = Color3.fromRGB(70, 210, 110),
	Alert = Color3.fromRGB(255, 160, 40),
}

local template: GuiObject? = nil
local list: GuiObject? = nil
-- Toasts vivants, du plus VIEUX au plus recent : c'est cet ordre qui permet d'appliquer le plafond MAX en
-- retirant toujours le premier.
local active: { GuiObject } = {}
local warnedMissing = false

-- Retrouve le modele et la pile dans l'interface. REFAIT a la demande, jamais mis en cache pour de bon : une
-- ScreenGui a ResetOnSpawn recree ses instances au respawn, et les references d'avant deviennent mortes. On
-- verifie donc .Parent et on re-resout si besoin.
local function resolve(): boolean
	if template and template.Parent and list and list.Parent then
		return true
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local ui = playerGui and playerGui:FindFirstChild("NotificationUI")
	local templates = ui and ui:FindFirstChild("Templates")
	local foundTemplate = templates and templates:FindFirstChild("TemplateNotification")
	local holder = ui and ui:FindFirstChild("Holder")
	local foundList = holder and holder:FindFirstChild("List")

	if foundTemplate and foundTemplate:IsA("GuiObject") and foundList and foundList:IsA("GuiObject") then
		foundTemplate.Visible = false
		template = foundTemplate
		list = foundList
		return true
	end

	if not warnedMissing then
		warnedMissing = true
		warn(
			"[Toast] NotificationUI introuvable. Attendu dans StarterGui : "
				.. "NotificationUI.Templates.TemplateNotification et NotificationUI.Holder.List"
		)
	end
	return false
end

-- UIScale garanti sur un toast : l'entree et la sortie jouent sur son Scale, PAS sur la Size. Animer la Size se
-- battrait avec le UIListLayout qui gere le placement ; le Scale, lui, ne deplace rien.
local function getScale(toast: GuiObject): UIScale
	local existing = toast:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Parent = toast
	return scale
end

local function playSound()
	local node: Instance? = SoundService
	for _, name in ipairs(SOUND_PATH) do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("Sound") then
		-- Une COPIE par toast : relancer la meme instance couperait le son en cours quand deux toasts popent
		-- coup sur coup. La copie se detruit toute seule a la fin, pas de liste a tenir.
		local copy = node:Clone()
		copy.Parent = SoundService
		copy:Play()
		copy.Ended:Once(function()
			copy:Destroy()
		end)
	end
end

local function dismiss(toast: GuiObject)
	-- Un toast peut etre vise deux fois : par son minuteur ET par le plafond MAX. On ne rejoue pas la sortie.
	if toast:GetAttribute("Dismissed") then
		return
	end
	toast:SetAttribute("Dismissed", true)
	for index, other in ipairs(active) do
		if other == toast then
			table.remove(active, index)
			break
		end
	end
	local tween = TweenService:Create(getScale(toast), OUT, { Scale = 0 })
	tween.Completed:Once(function()
		toast:Destroy()
	end)
	tween:Play()
end

-- Affiche un toast. `kind` choisit la couleur d'accent (voir KIND_COLORS), `text` est le message.
function Toast.show(kind: string?, text: string?)
	if not resolve() then
		return
	end
	local model = template :: GuiObject
	local pile = list :: GuiObject

	local toast = model:Clone()
	toast.Name = "Notif"

	local message = toast:FindFirstChild("MessageText", true)
	if message and message:IsA("TextLabel") then
		message.Text = tostring(text or "")
	end

	local color = if typeof(kind) == "string" then KIND_COLORS[kind] else nil
	if color then
		local stroke = toast:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		-- On teinte le UIGradient (Color) du plein vers une version assombrie, pour donner du volume. On NE
		-- touche PAS a sa Transparency : c'est une NumberSequence reglee dans Studio, c'est elle qui fait le
		-- fondu du toast. La reecrire casserait l'effet.
		local gradient = toast:FindFirstChildOfClass("UIGradient")
		if gradient then
			local dark = Color3.new(color.R * 0.55, color.G * 0.55, color.B * 0.55)
			gradient.Color = ColorSequence.new(color, dark)
		end
	end

	local scale = getScale(toast)
	scale.Scale = 0
	toast.Visible = true
	toast.Parent = pile
	TweenService:Create(scale, IN, { Scale = 1 }):Play()

	table.insert(active, toast)
	-- Plafond : le plus vieux part d'abord. Sans lui, un pic de notifs empilerait a l'infini et couvrirait tout.
	while #active > MAX do
		dismiss(active[1])
	end

	playSound()

	-- Retrait auto. On capture CE toast dans la fermeture : si d'autres popent entre-temps, chacun garde son
	-- propre minuteur.
	task.delay(HOLD, function()
		dismiss(toast)
	end)
end

function Toast.init()
	-- Le serveur DEMANDE un toast par ce remote. Seul chemin serveur -> client : le client affiche, il ne
	-- valide rien (un FireClient ne peut venir que du serveur, qui est notre autorite).
	local remote = RemoteSetup.getRemote("Notify", "UI")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(kind, text)
			Toast.show(kind, text)
		end)
	else
		warn("[Toast] Remote UI/Notify introuvable : les notifications serveur n'arriveront pas")
	end

	-- On attend que StarterGui ait copie l'interface dans PlayerGui, en tache de fond pour ne pas bloquer le
	-- boot. Sans cette attente, un premier resolve() echouerait et previendrait a tort d'une interface absente.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		playerGui:WaitForChild("NotificationUI", 10)
		resolve()
	end)
end

return Toast
