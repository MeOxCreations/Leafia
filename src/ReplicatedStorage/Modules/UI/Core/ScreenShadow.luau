--!strict
-- L'OMBRE D'ECRAN : une grande image sombre sur les bords, posee DERRIERE un menu. Elle eteint le jeu autour et
-- detache le menu du decor, sans le masquer.
--
-- CONSTRUITE EN CODE, pas dans Studio : StarterGui n'est pas synchronise par Rojo, une ombre posee a la main
-- n'existerait que dans sa place. Et un seul reglage pour tous les menus qui s'en servent.
--
-- CHAQUE MENU A LA SIENNE, rangee DANS son propre ScreenGui, sous lui (ZIndex plus bas) : elle passe derriere le
-- menu et devant le jeu sans rien savoir des autres interfaces. Celui qui la cree la detruit.

local TweenService = game:GetService("TweenService")

local ScreenShadow = {}

local IMAGE = "rbxassetid://74658820247403"
-- Reglages poses dans Studio par le joueur : 120 % de l'ecran, centree -- les bords de l'image sortent du cadre, on
-- ne voit que le degrade.
local SIZE = UDim2.fromScale(1.2, 1.2)
-- Transparence une fois affichee. 0 = l'image telle qu'elle a ete dessinee.
local SHOWN_TRANSPARENCY = 0
local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

export type Handle = {
	-- Fondu d'apparition / de disparition. Cachee, elle n'est plus du tout dessinee.
	set: (on: boolean) -> (),
	destroy: () -> (),
}

--- Pose une ombre (cachee) dans `parent`, a `zIndex` : plus bas que le menu qu'elle accompagne.
function ScreenShadow.new(parent: Instance, zIndex: number): Handle
	local image = Instance.new("ImageLabel")
	image.Name = "LeafiaScreenShadow"
	image.BackgroundTransparency = 1
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.Size = SIZE
	image.Image = IMAGE
	image.ImageTransparency = 1
	image.ZIndex = zIndex
	image.Visible = false
	image.Parent = parent

	-- Un fondu de sortie qui finit APRES une reouverture ne doit pas la cacher : chaque appel prend un nouveau jeton.
	local token = 0
	local function set(on: boolean)
		token += 1
		local mine = token
		if on then
			image.Visible = true
		end
		local tween = TweenService:Create(image, FADE, { ImageTransparency = if on then SHOWN_TRANSPARENCY else 1 })
		tween.Completed:Once(function()
			if mine == token and not on then
				image.Visible = false
			end
		end)
		tween:Play()
	end

	local function destroy()
		token += 1
		image:Destroy()
	end

	return { set = set, destroy = destroy }
end

return ScreenShadow
