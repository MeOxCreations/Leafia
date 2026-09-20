--[[
	EXPORTER L'ECRAN DE CHARGEMENT FAIT A LA MAIN. A coller dans la barre de commandes de Studio.

	POURQUOI : placer des feuillages a la souris est mille fois plus rapide que de deviner des chiffres. Mais l'ecran
	de chargement vit dans `ReplicatedFirst` (Rojo le synchronise), pas dans StarterGui. On releve donc les valeurs
	posees a la main, et on les recopie dans le code.

	CE QU'IL SORT : une ligne par element, avec sa position et sa taille EN FRACTION DE L'ECRAN, sa rotation et ses
	reglages visuels. Les fractions d'ecran ne dependent ni du rangement (dossiers, cadres imbriques) ni de la taille
	de la fenetre : elles se recollent telles quelles dans le code.

	UTILISATION : coller, lancer, copier TOUT ce qui sort de la console, me l'envoyer.
]]

local StarterGui = game:GetService("StarterGui")

-- Le nom de la copie faite a la main. A changer si elle est ailleurs ou nommee autrement.
local TARGET = "LoadingScreenManuel"

local screen = StarterGui:FindFirstChild(TARGET, true)
if not screen then
	warn(`[Export] "{TARGET}" introuvable dans StarterGui. Verifie le nom EXACT (pas de recherche approchante).`)
	return
end

-- On mesure tout par rapport a la surface de l'ecran. Un GuiObject qui n'a pas encore ete dessine n'a pas de taille :
-- on le dit plutot que de sortir des zeros qui ressembleraient a des vraies valeurs.
local root = if screen:IsA("LayerCollector") then screen else screen:FindFirstAncestorWhichIsA("LayerCollector")
local viewport = if root then root.AbsoluteSize else Vector2.zero
if viewport.X <= 0 or viewport.Y <= 0 then
	warn("[Export] L'ecran n'a pas de taille : ouvre-le (Enabled = true) et relance. Rien n'est mesurable sinon.")
	return
end
local origin = if root then root.AbsolutePosition else Vector2.zero

local function n(v: number): string
	return string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
end

local function colour(c: Color3): string
	return string.format("Color3.fromRGB(%d, %d, %d)", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

-- Rectangle d'un element en fraction d'ecran. `AbsolutePosition` / `AbsoluteSize` ignorent la ROTATION (ils donnent
-- la boite avant rotation) : c'est exactement ce qu'il faut, la rotation est relevee a part.
local function rect(gui: GuiObject): (string, string)
	local size = gui.AbsoluteSize
	local centre = gui.AbsolutePosition + size / 2 - origin
	-- Pas d'accolade dans une chaine interpolee (Luau la lit comme un debut d'expression) : on concatene.
	local pos = "pos = { " .. n(centre.X / viewport.X) .. ", " .. n(centre.Y / viewport.Y) .. " }"
	return pos, "size = { " .. n(size.X / viewport.X) .. ", " .. n(size.Y / viewport.Y) .. " }"
end

local lines: { string } = {}

local function describe(gui: GuiObject, depth: number)
	local pos, size = rect(gui)
	local parts = { `{string.rep("  ", depth)}{gui.Name} ({gui.ClassName})`, pos, size }
	if gui.Rotation ~= 0 then
		table.insert(parts, `rot = {n(gui.Rotation)}`)
	end
	table.insert(parts, `z = {gui.ZIndex}`)
	if not gui.Visible then
		table.insert(parts, "CACHE")
	end
	if gui:IsA("ImageLabel") or gui:IsA("ImageButton") then
		table.insert(parts, `image = "{gui.Image}"`)
		table.insert(parts, `tint = {colour(gui.ImageColor3)}`)
		table.insert(parts, `imageTransparency = {n(gui.ImageTransparency)}`)
		if gui.ScaleType ~= Enum.ScaleType.Stretch then
			table.insert(parts, `scaleType = {gui.ScaleType.Name}`)
		end
		if gui.ScaleType == Enum.ScaleType.Tile then
			table.insert(parts, `tileSize = {gui.TileSize}`)
		end
		-- Une image DECOUPEE dans une planche : sans ces deux valeurs, on afficherait la planche entiere.
		if gui.ImageRectSize.X > 0 or gui.ImageRectSize.Y > 0 then
			table.insert(parts, `rect = {gui.ImageRectOffset} + {gui.ImageRectSize}`)
		end
	end
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		table.insert(parts, `text = "{gui.Text}"`)
		table.insert(parts, `font = {gui.FontFace.Family}`)
		table.insert(parts, `textColor = {colour(gui.TextColor3)}`)
		table.insert(parts, `textTransparency = {n(gui.TextTransparency)}`)
	end
	if gui.BackgroundTransparency < 1 then
		table.insert(parts, `bg = {colour(gui.BackgroundColor3)}`)
		table.insert(parts, `bgTransparency = {n(gui.BackgroundTransparency)}`)
	end
	table.insert(lines, table.concat(parts, "  |  "))

	-- LES ENFANTS QUI CHANGENT LE RENDU. Sans eux, un degrade exporte n'est qu'un aplat, et un mot detoure perd son
	-- contour : on relirait l'ecran a l'ecran en se demandant ce qui manque.
	for _, child in ipairs(gui:GetChildren()) do
		local indent = string.rep("  ", depth + 1)
		if child:IsA("UIGradient") then
			local colours = {}
			for _, k in ipairs(child.Color.Keypoints) do
				table.insert(colours, `{n(k.Time)} = {colour(k.Value)}`)
			end
			local fades = {}
			for _, k in ipairs(child.Transparency.Keypoints) do
				table.insert(fades, `{n(k.Time)} = {n(k.Value)}`)
			end
			local parts2 = {
				`{indent}UIGradient`,
				`rotation = {n(child.Rotation)}`,
				`offset = {n(child.Offset.X)}, {n(child.Offset.Y)}`,
				`couleurs : {table.concat(colours, " , ")}`,
			}
			if #fades > 1 or (fades[1] and fades[1] ~= "0 = 0") then
				table.insert(parts2, `transparences : {table.concat(fades, " , ")}`)
			end
			table.insert(lines, table.concat(parts2, "  |  "))
		elseif child:IsA("UIStroke") then
			table.insert(
				lines,
				`{indent}UIStroke  |  color = {colour(child.Color)}  |  thickness = {n(child.Thickness)}`
					.. `  |  transparency = {n(child.Transparency)}  |  mode = {child.ApplyStrokeMode.Name}`
			)
		elseif child:IsA("UICorner") then
			table.insert(lines, `{indent}UICorner  |  radius = {child.CornerRadius}`)
		elseif child:IsA("UIAspectRatioConstraint") then
			table.insert(lines, `{indent}UIAspectRatioConstraint  |  ratio = {n(child.AspectRatio)}`)
		end
	end

	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("GuiObject") then
			describe(child, depth + 1)
		end
	end
end

for _, child in ipairs(screen:GetChildren()) do
	if child:IsA("GuiObject") then
		describe(child, 0)
	end
end

print(("="):rep(78))
print(`EXPORT DE {screen:GetFullName()} -- ecran {math.round(viewport.X)}x{math.round(viewport.Y)}`)
print("pos et size sont des FRACTIONS D'ECRAN, centre de l'element. rot en degres.")
print(("="):rep(78))
for _, line in ipairs(lines) do
	print(line)
end
print(("="):rep(78))
print(`{#lines} element(s). Copier TOUT ce bloc.`)
