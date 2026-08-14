--!strict
-- Effet SLIME sur un GuiButton. Au SURVOL le bouton GONFLE avec un rebond elastique et RESPIRE doucement (effet
-- "prolonge" : vivant tant qu'on reste dessus). Au CLIC il s'ENFONCE. Sinon il repart a sa taille en douceur.
--
-- Reutilisable : ButtonSlime.bind(button) sur n'importe quel GuiButton. UNE SEULE boucle RenderStepped anime tous
-- les boutons enregistres. L'effet passe par un UIScale ajoute au bouton (nomme SlimeScale) : on ne touche JAMAIS
-- a la Size reglee dans Studio, et ce UIScale se compose proprement avec un eventuel UIScale deja present.
--
-- Le gonflement est CENTRE si le bouton a AnchorPoint (0.5, 0.5) ; sinon il grandit depuis son coin d'ancrage.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local ButtonSlime = {}

-- Reglages PAR BOUTON, tous optionnels : sans eux, bind() prend les valeurs globales par defaut. Permet de rendre
-- certains boutons plus intenses (ex les fleches de selection de plot) sans toucher aux autres.
export type SlimeOptions = { hover: number?, pressed: number?, pulse: number? }

-- Ressort SOUS-amorti (comme le curseur) : il depasse la cible puis revient -> c'est ce rebond qui fait le slime.
-- Amortissement critique ici ~ 2*sqrt(1700) ~ 82 ; a 22 on est bien en dessous, donc ca rebondit.
local STIFFNESS = 1700
local DAMPING = 22
-- Ecarts de taille (fraction : 0.10 = +10 %). Le survol GONFLE, la respiration l'anime, le clic ENFONCE.
local HOVER = 0.05
local HOVER_PULSE = 0.012 -- amplitude de la respiration pendant le survol (0 = juste le gonflement, sans pulse)
local HOVER_PULSE_SPEED = 4.5 -- vitesse de la respiration en rad/s (lent = elegant)
local PRESSED = -0.035 -- enfoncement au clic (negatif = plus petit)
-- Son joue A L'ENTREE sur CHAQUE bouton (2D). Par bouton (MouseEnter) : fiable meme sur des boutons colles, la ou
-- une detection "aucun bouton -> un bouton" ratait le son quand on passait direct d'un bouton a un autre. A creer
-- dans SoundService.Sounds.UI (comme PressButtonSound du clic).
local HOVER_SOUND = { "Sounds", "UI", "HoverButtonSound" }
-- Son du CLIC sur un bouton (distinct du clic curseur dans le monde, cf ClickSoundController). 2D.
local CLICK_SOUND = { "Sounds", "UI", "PressButtonSound" }

type Entry = {
	button: GuiButton,
	scaleObj: UIScale,
	pos: number,
	vel: number,
	phase: number,
	hovering: boolean,
	held: boolean,
	dead: boolean,
	-- Reglages PAR BOUTON (defaut = les globaux). C'est ce qui permet a certains boutons d'etre plus intenses.
	hover: number,
	pressed: number,
	pulse: number,
}

local entries: { Entry } = {}
local bound: { [GuiButton]: boolean } = {}
local started = false

local function start()
	if started then
		return
	end
	started = true

	-- Un relachement N'IMPORTE OU relache le clic de TOUS les boutons. Si le bouton DISPARAIT au clic (il ouvre un
	-- autre ecran), son MouseButton1Up ne tire pas et l'enfoncement resterait fige : ce filet l'evite.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			for _, e in ipairs(entries) do
				e.held = false
			end
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local step = math.min(dt, 1 / 30)
		-- Boucle a l'ENVERS : on peut retirer un bouton detruit sans casser le parcours.
		for i = #entries, 1, -1 do
			local e = entries[i]
			if e.dead then
				table.remove(entries, i)
				continue
			end

			-- Un bouton cache ne respire pas et ne grandit pas (sinon il reapparaitrait gonfle).
			local hovering = e.hovering and e.button.Visible

			-- REPOS (ni survol ni clic, ressort immobile) : on cale a 1 et on saute le calcul. Evite de relayout
			-- chaque bouton chaque frame pour rien -- ecrire Scale recalcule la mise en page du bouton.
			if not hovering and not e.held and math.abs(e.pos) < 1e-3 and math.abs(e.vel) < 1e-3 then
				if e.pos ~= 0 then
					e.pos = 0
					e.vel = 0
					e.scaleObj.Scale = 1
				end
				e.phase = 0
				continue
			end

			e.phase += step * HOVER_PULSE_SPEED
			-- Cible = gonflement du survol (+ respiration lente = slime PROLONGE) AJOUTE au creux du clic. Les deux
			-- se composent : survoler GONFLE, cliquer ENFONCE, relacher rend le gonflement.
			local hoverGoal = if hovering then e.hover + math.sin(e.phase) * e.pulse else 0
			local target = hoverGoal + (if e.held then e.pressed else 0)
			local force = -STIFFNESS * (e.pos - target) - DAMPING * e.vel
			e.vel += force * step
			e.pos += e.vel * step
			e.scaleObj.Scale = 1 + e.pos
		end
	end)
end

-- Ajoute l'effet slime a un bouton. Idempotent : un meme bouton n'est enregistre qu'une fois.
function ButtonSlime.bind(button: GuiButton, opts: SlimeOptions?)
	if bound[button] then
		return
	end
	bound[button] = true

	-- UIScale dedie (nomme), reutilise s'il existe deja. On ne touche pas a la Size ni a un autre UIScale.
	local existing = button:FindFirstChild("SlimeScale")
	local scaleObj: UIScale
	if existing and existing:IsA("UIScale") then
		scaleObj = existing
	else
		scaleObj = Instance.new("UIScale")
		scaleObj.Name = "SlimeScale"
		scaleObj.Parent = button
	end

	local entry: Entry = {
		button = button,
		scaleObj = scaleObj,
		pos = 0,
		vel = 0,
		phase = 0,
		hovering = false,
		held = false,
		dead = false,
		hover = (opts and opts.hover) or HOVER,
		pressed = (opts and opts.pressed) or PRESSED,
		pulse = (opts and opts.pulse) or HOVER_PULSE,
	}
	table.insert(entries, entry)

	button.MouseEnter:Connect(function()
		entry.hovering = true
		entry.phase = 0 -- la respiration repart proprement (sin(0) = 0) a chaque entree
		SoundUtils.play(HOVER_SOUND) -- un "pop" A CHAQUE bouton, meme colles
	end)
	button.MouseLeave:Connect(function()
		entry.hovering = false
	end)
	button.MouseButton1Down:Connect(function()
		entry.held = true
		SoundUtils.play(CLICK_SOUND) -- son dedie au clic bouton (le clic dans le monde sonne PressCursorSound)
	end)
	button.MouseButton1Up:Connect(function()
		entry.held = false
	end)
	-- Cache pendant qu'on le survole / clique (ex : UIManager change d'ecran) : on relache son etat pour qu'il ne
	-- revienne pas gonfle a la prochaine ouverture.
	button:GetPropertyChangedSignal("Visible"):Connect(function()
		if not button.Visible then
			entry.hovering = false
			entry.held = false
		end
	end)
	button.Destroying:Connect(function()
		entry.dead = true
		bound[button] = nil
	end)

	start()
end

return ButtonSlime
