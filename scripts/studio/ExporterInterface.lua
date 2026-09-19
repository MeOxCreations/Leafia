-- A COLLER DANS LA BARRE DE COMMANDES DE STUDIO.
--
-- SELECTIONNE D'ABORD L'INTERFACE A EXPORTER dans l'Explorer (par exemple StarterGui > NotificationUI). Sans
-- selection, il prend StarterGui.NotificationUI.
--
-- POURQUOI CE SCRIPT. Une interface faite dans Studio n'arrive que dans la place ou elle a ete faite : Rojo ne
-- synchronise pas StarterGui. La passer en code la fait arriver partout -- mais la recopier propriete par propriete
-- a la main serait long et plein de fautes. Ce script imprime TOUT l'arbre : chaque objet, et chaque propriete qui
-- n'est PAS a sa valeur par defaut (comparee a un objet neuf de la meme classe). Les attributs aussi.
--
-- M'envoyer tout ce qui est imprime entre les deux lignes. Si la sortie coupe (tres grande interface), l'exporter en
-- plusieurs fois : selectionner un sous-dossier a la fois.

local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local root = Selection:Get()[1] or StarterGui:FindFirstChild("NotificationUI")
if not root then
	warn("Rien a exporter : selectionne une interface dans l'Explorer.")
	return
end

-- Les proprietes lues, par ordre d'interet. Celles qu'une classe n'a pas sont simplement sautees.
local PROPS = {
	-- Place et taille
	"AnchorPoint", "Position", "Size", "SizeConstraint", "AutomaticSize", "Rotation", "ZIndex", "LayoutOrder",
	"Visible", "ClipsDescendants", "Active", "Selectable",
	-- Fond
	"BackgroundColor3", "BackgroundTransparency", "BorderSizePixel", "BorderColor3", "BorderMode",
	-- Texte
	"Text", "RichText", "FontFace", "TextSize", "TextScaled", "TextWrapped", "TextColor3", "TextTransparency",
	"TextStrokeColor3", "TextStrokeTransparency", "TextXAlignment", "TextYAlignment", "LineHeight",
	"TextTruncate", "AutoButtonColor",
	-- Image
	"Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale", "TileSize",
	"ImageRectOffset", "ImageRectSize", "ResampleMode",
	-- Groupes et ecran
	"GroupTransparency", "GroupColor3", "Enabled", "DisplayOrder", "IgnoreGuiInset", "ScreenInsets", "ResetOnSpawn",
	"ZIndexBehavior", "ClipToDeviceSafeArea", "SafeAreaCompatibility",
	-- Modificateurs
	"CornerRadius", "TopLeftRadius", "TopRightRadius", "BottomLeftRadius", "BottomRightRadius",
	"Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "StrokeSizingMode",
	"BorderStrokePosition", "Offset", "Scale",
	"FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Padding", "Wraps",
	"HorizontalFlex", "VerticalFlex", "ItemLineAlignment",
	"CellSize", "CellPadding", "StartCorner", "FillDirectionMaxCells",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight",
	"AspectRatio", "AspectType", "DominantAxis", "MinSize", "MaxSize", "MinTextSize", "MaxTextSize",
	"FlexMode", "GrowRatio", "ShrinkRatio",
}

local function n(v)
	return string.format("%.4g", v)
end

local function show(v)
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "number" then
		return n(v)
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "UDim2" then
		return string.format("UDim2.new(%s, %s, %s, %s)", n(v.X.Scale), n(v.X.Offset), n(v.Y.Scale), n(v.Y.Offset))
	elseif t == "UDim" then
		return string.format("UDim.new(%s, %s)", n(v.Scale), n(v.Offset))
	elseif t == "Vector2" then
		return string.format("Vector2.new(%s, %s)", n(v.X), n(v.Y))
	elseif t == "Color3" then
		return string.format("Color3.fromRGB(%d, %d, %d)", math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "Rect" then
		return string.format("Rect.new(%s, %s, %s, %s)", n(v.Min.X), n(v.Min.Y), n(v.Max.X), n(v.Max.Y))
	elseif t == "ColorSequence" then
		local k = {}
		for _, p in ipairs(v.Keypoints) do
			table.insert(k, string.format("%s:%s", n(p.Time), show(p.Value)))
		end
		return "ColorSequence{ " .. table.concat(k, ", ") .. " }"
	elseif t == "NumberSequence" then
		local k = {}
		for _, p in ipairs(v.Keypoints) do
			table.insert(k, string.format("%s:%s", n(p.Time), n(p.Value)))
		end
		return "NumberSequence{ " .. table.concat(k, ", ") .. " }"
	elseif t == "Font" then
		return string.format('Font.new("%s", Enum.FontWeight.%s, Enum.FontStyle.%s)', v.Family, v.Weight.Name, v.Style.Name)
	elseif t == "EnumItem" then
		return tostring(v)
	end
	return "<" .. t .. ">"
end

-- La valeur par defaut d'une propriete, lue sur un objet NEUF de la meme classe (cree une fois par classe).
local fresh = {}
local function defaultOf(obj, prop)
	local cls = obj.ClassName
	if fresh[cls] == nil then
		local ok, inst = pcall(Instance.new, cls)
		fresh[cls] = if ok then inst else false
	end
	local base = fresh[cls]
	if not base then
		return nil, false
	end
	local ok, v = pcall(function()
		return base[prop]
	end)
	return v, ok
end

local out = {}
local function dump(obj, depth)
	local pad = string.rep("  ", depth)
	local fields = {}
	for _, prop in ipairs(PROPS) do
		local ok, v = pcall(function()
			return obj[prop]
		end)
		if ok and v ~= nil and typeof(v) ~= "Instance" then
			local d, hasDefault = defaultOf(obj, prop)
			if not hasDefault or d ~= v then
				table.insert(fields, prop .. " = " .. show(v))
			end
		end
	end
	for key, value in pairs(obj:GetAttributes()) do
		table.insert(fields, "@" .. key .. " = " .. show(value))
	end
	table.insert(out, string.format('%s%s "%s" { %s }', pad, obj.ClassName, obj.Name, table.concat(fields, ", ")))
	for _, child in ipairs(obj:GetChildren()) do
		dump(child, depth + 1)
	end
end

dump(root, 0)
for _, inst in pairs(fresh) do
	if inst then
		inst:Destroy()
	end
end

print("----- DEBUT " .. root:GetFullName() .. " (" .. #out .. " objets) -----")
for _, line in ipairs(out) do
	print(line)
end
print("----- FIN -----")
