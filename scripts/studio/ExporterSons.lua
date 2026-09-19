-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO. Rien a selectionner.
--
-- POURQUOI CE SCRIPT. Les sons du jeu passent dans le code (SoundConfigs), pour qu'ils arrivent dans TOUTES les
-- places par Rojo au lieu d'etre recopies a la main dans chacune. Les recopier ID par ID serait long et plein de
-- fautes : ce script lit tous les Sound poses sous SoundService et imprime les lignes de config, pretes a coller.
--
-- CE QU'IL LIT : l'id, le volume, la vitesse, la boucle, et s'il joue tout seul (Playing). Un Sound qui porte des EFFETS (egaliseur, reverb...) ou un
-- SoundGroup est signale en commentaire : la config ne les decrit pas, il faut garder ce Sound dans Studio.
--
-- A FAIRE DANS LA PLACE QUI A LE PLUS DE SONS, puis m'envoyer tout ce qui est imprime entre les deux lignes.

local SoundService = game:GetService("SoundService")

local function pathOf(sound)
	local names = {}
	local node = sound
	while node and node ~= SoundService do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end

local function num(value)
	return string.format("%.3g", value)
end

local lines = {}
for _, d in ipairs(SoundService:GetDescendants()) do
	if d:IsA("Sound") then
		local parts = { string.format('id = "%s"', d.SoundId) }
		if math.abs(d.Volume - 0.5) > 1e-3 then
			table.insert(parts, "volume = " .. num(d.Volume))
		end
		if math.abs(d.PlaybackSpeed - 1) > 1e-3 then
			table.insert(parts, "speed = " .. num(d.PlaybackSpeed))
		end
		if d.Looped then
			table.insert(parts, "looped = true")
		end
		if d.Playing then
			table.insert(parts, "playing = true")
		end
		local line = string.format('\t["%s"] = { %s },', pathOf(d), table.concat(parts, ", "))
		local extras = {}
		for _, child in ipairs(d:GetChildren()) do
			if child:IsA("SoundEffect") then
				table.insert(extras, child.ClassName)
			end
		end
		if d.SoundGroup then
			table.insert(extras, "SoundGroup " .. d.SoundGroup.Name)
		end
		if #extras > 0 then
			line = line .. " -- A GARDER DANS STUDIO : " .. table.concat(extras, ", ")
		end
		table.insert(lines, line)
	end
end
table.sort(lines)

print("----- DEBUT SoundConfigs (" .. #lines .. " sons) -----")
for _, line in ipairs(lines) do
	print(line)
end
print("----- FIN SoundConfigs -----")
