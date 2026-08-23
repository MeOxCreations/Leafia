-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO. Rien a selectionner.
--
-- POURQUOI CE SCRIPT. Le portage du Bin depend de choses invisibles dans l'Explorer : la PROPRIETE PrimaryPart
-- du model (differente d'une part NOMMEE "PrimaryPart"), le NOM du marqueur dans TakeAnimation, les membres que
-- IdleAnimation cle, et surtout le C0 du joint qui a servi a ANIMER. Les verifier a la main coute plusieurs
-- allers-retours, et une erreur passe inapercue.
--
-- LE C0 EST LE POINT CLE. Le Bin n'est pas un outil de ToolConfigs : sa prise n'est calculee par personne, donc
-- le placement fait a la main dans l'editeur (via AttacherObjetAuRig.lua) EST la source de verite. Le jeu doit
-- rejouer EXACTEMENT ce C0, sinon le Bin sera de travers dans la main alors que l'animation, elle, est bonne,
-- et on cherchera l'erreur dans l'animation. Ce script lit ce C0 sur le rig et l'affiche pret a coller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local MODEL_PREFIX = "Bin"
local ANIM_FOLDER = { "Animations", "Player", "Tools", "Bin" }
-- Membres de jambe : une pose de MAINTIEN qui les cle ecrase la marche (priorite Action). C'est le piege
-- principal ici, parce qu'on porte le Bin en se deplacant librement.
local LEG_PARTS = {
	LeftUpperLeg = true,
	LeftLowerLeg = true,
	LeftFoot = true,
	RightUpperLeg = true,
	RightLowerLeg = true,
	RightFoot = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
}

local problems = {}
local function fail(message)
	table.insert(problems, message)
	warn(`[VerifierBin] MANQUE : {message}`)
end

local function isBinModel(inst)
	return inst:IsA("Model") and inst.Name:sub(1, #MODEL_PREFIX) == MODEL_PREFIX
end

-- ===== 1. LES MODELS BIN =====
local bins = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if isBinModel(d) then
		table.insert(bins, d)
	end
end

if #bins == 0 then
	fail(`aucun Model dont le nom commence par "{MODEL_PREFIX}" dans le Workspace`)
else
	print(`[VerifierBin] {#bins} model(s) Bin trouve(s)`)
end

for _, model in ipairs(bins) do
	print(`[VerifierBin] --- {model:GetFullName()} ---`)

	-- Un Bin MONTE SUR UN RIG (pour animer) est desancre et souvent sans PrimaryPart : AttacherObjetAuRig.lua
	-- desancre tout expres, sinon le joint serait ignore. C'est donc NORMAL et pas un defaut. On saute les
	-- reproches sur celui-la : il ne sert qu'a lire le C0 de la prise. Warner dessus polluerait la sortie et
	-- ferait courir apres un faux probleme.
	local ancestor = model:FindFirstAncestorWhichIsA("Model")
	local rigName = nil
	while ancestor do
		if ancestor:FindFirstChildOfClass("Humanoid") then
			rigName = ancestor.Name
			break
		end
		ancestor = ancestor:FindFirstAncestorWhichIsA("Model")
	end
	if rigName then
		print(`[VerifierBin]   monte sur le rig "{rigName}" (sert a animer) -> verifications sautees, c'est normal`)
		continue
	end

	-- LE PIEGE : la PROPRIETE PrimaryPart, pas une part qui porte ce nom.
	if model.PrimaryPart then
		print(`[VerifierBin]   PrimaryPart (propriete) = "{model.PrimaryPart.Name}" -> OK`)
	elseif model:FindFirstChild("RootPart") then
		print("[VerifierBin]   pas de propriete PrimaryPart, mais un enfant RootPart existe -> OK")
	elseif model:FindFirstChild("PrimaryPart") then
		fail(
			`{model.Name} : la propriete PrimaryPart du Model est VIDE. Une part s'appelle "PrimaryPart", ce n'est PAS pareil. Selectionne le Model, puis Proprietes, puis PrimaryPart, et choisis cette part`
		)
	else
		fail(
			`{model.Name} : ni propriete PrimaryPart, ni enfant RootPart. Le portage n'aurait aucune reference fixe (GetPivot suit la bounding box et derive)`
		)
	end

	-- Etat des parts. Ancre au repos = normal : le service desancre a la prise et restaure a la repose.
	local anchored, total = 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			total += 1
			if d.Anchored then
				anchored += 1
			end
		end
	end
	print(`[VerifierBin]   {total} BasePart, dont {anchored} ancrees`)
	if anchored == 0 then
		fail(`{model.Name} : aucune part ancree, au repos il va tomber ou glisser. Ancre au moins la PrimaryPart`)
	end

	local highlight = model:FindFirstChildOfClass("Highlight")
	if highlight then
		print(
			`[VerifierBin]   NOTE : Highlight present (Enabled = {highlight.Enabled}). Soude a la main il brillera AUSSI pendant le portage. A couper a la prise si ce n'est pas voulu.`
		)
	end
end

-- ===== 2. LE C0 DU JOINT D'ANIMATION (la valeur a reporter en jeu) =====
-- On cherche tout joint dont Part1 appartient a un model Bin : c'est celui pose par AttacherObjetAuRig.lua sur
-- le rig d'animation. Son C0 est la prise REELLE qui a servi a animer.
print("[VerifierBin] ----- prise utilisee pour animer -----")
local found = 0
for _, d in ipairs(workspace:GetDescendants()) do
	if (d:IsA("Motor6D") or d:IsA("Weld")) and d.Part0 and d.Part1 then
		local owner = d.Part1:FindFirstAncestorWhichIsA("Model")
		while owner and not isBinModel(owner) do
			owner = owner:FindFirstAncestorWhichIsA("Model")
		end
		if owner then
			found += 1
			local c0 = d.C0
			local p = c0.Position
			local rx, ry, rz = c0:ToEulerAnglesXYZ()
			local pos = `{string.format("%.4f", p.X)}, {string.format("%.4f", p.Y)}, {string.format("%.4f", p.Z)}`
			local ang =
				`math.rad({string.format("%.2f", math.deg(rx))}), math.rad({string.format("%.2f", math.deg(ry))}), math.rad({string.format("%.2f", math.deg(rz))})`
			print(`[VerifierBin] joint "{d.Name}" ({d.ClassName}) : {d.Part0.Name} -> {d.Part1.Name}`)
			print("[VerifierBin]   C0 a reporter en jeu :")
			print(`[VerifierBin]   CFrame.new({pos}) * CFrame.Angles({ang})`)
			if d.C1 ~= CFrame.identity then
				print("[VerifierBin]   ATTENTION : C1 n'est pas l'identite, il faudra le reporter aussi.")
			end
		end
	end
end
if found == 0 then
	print("[VerifierBin] Aucun joint Bin trouve dans le Workspace.")
	print("[VerifierBin] Si tu as anime avec le Bin dans la main, garde ce rig : son joint porte la prise EXACTE.")
	print(
		"[VerifierBin] Sinon : place le Bin dans la main du rig, lance AttacherObjetAuRig.lua avec OBJECT_NAME = Bin, puis relance ce script."
	)
end

-- ===== 3. LES ANIMATIONS =====
print("[VerifierBin] ----- animations -----")
local node = ReplicatedStorage
for _, name in ipairs(ANIM_FOLDER) do
	node = node and node:FindFirstChild(name)
end

if not node then
	fail(`dossier introuvable : ReplicatedStorage.{table.concat(ANIM_FOLDER, ".")}`)
else
	for _, anim in ipairs(node:GetChildren()) do
		if anim:IsA("Animation") then
			if anim.AnimationId == "" then
				fail(`{anim.Name} n'a pas d'AnimationId (anim pas encore publiee ?)`)
			else
				print(`[VerifierBin] {anim.Name} -> {anim.AnimationId}`)

				-- Lecture RESEAU capricieuse : acceptable pour un diagnostic ponctuel, jamais dans le jeu.
				local ok, seq = pcall(function()
					return KeyframeSequenceProvider:GetKeyframeSequenceAsync(anim.AnimationId)
				end)
				if not ok or not seq then
					warn(`[VerifierBin]   lecture des keyframes impossible ({anim.Name}). Cette API rate souvent : RELANCE le script.`)
				else
					local markers, posed = {}, {}
					for _, kf in ipairs(seq:GetChildren()) do
						if kf:IsA("Keyframe") then
							for _, m in ipairs(kf:GetMarkers()) do
								table.insert(markers, `"{m.Name}" a t={string.format("%.2f", kf.Time)}s`)
							end
							for _, pose in ipairs(kf:GetDescendants()) do
								if pose:IsA("Pose") then
									posed[pose.Name] = true
								end
							end
						end
					end

					if #markers > 0 then
						print(`[VerifierBin]   MARQUEURS : {table.concat(markers, " | ")}`)
					elseif anim.Name:lower():find("take") then
						fail(`{anim.Name} n'a AUCUN marqueur. Il en faut un a l'image ou la main se referme sur le Bin`)
					else
						print("[VerifierBin]   MARQUEURS : aucun")
					end

					local legs = {}
					for name in pairs(posed) do
						if LEG_PARTS[name] then
							table.insert(legs, name)
						end
					end
					if #legs > 0 then
						print(`[VerifierBin]   jambes clees : {table.concat(legs, ", ")}`)
						if anim.Name:lower():find("idle") then
							fail(
								`{anim.Name} cle les JAMBES ({table.concat(legs, ", ")}). En pose de maintien (priorite Action) ca ecrase la marche : le joueur glissera au lieu de marcher. Supprime ces pistes, garde bras et torse`
							)
						end
					else
						print("[VerifierBin]   aucune jambe clee -> OK pour une pose de maintien")
					end
				end
			end
		end
	end
end

-- ===== RESUME =====
print("[VerifierBin] ==========")
if #problems == 0 then
	print("[VerifierBin] Tout est en place. Donne-moi le nom du MARQUEUR et la ligne C0 affiches ci-dessus.")
else
	warn(`[VerifierBin] {#problems} chose(s) a corriger :`)
	for i, p in ipairs(problems) do
		warn(`[VerifierBin]   {i}. {p}`)
	end
end
