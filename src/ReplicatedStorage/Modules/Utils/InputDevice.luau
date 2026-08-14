--!strict
-- Detection LEGERE du type d'input ACTIF (tactile / clavier-souris / manette). Sert d'AIGUILLAGE : montrer les boutons
-- mobiles, cacher les hints clavier, choisir le mode de visee. Il n'agit sur rien, il INFORME.
--
-- Volontairement minimal (le public Roblox est ~90% mobile) : on ne modelise que ce dont on se sert. Roblox donne deja
-- TouchEnabled / GamepadEnabled, mais ces CAPACITES ne disent pas ce que le joueur UTILISE (un mobile peut avoir un
-- clavier branche). On suit donc le DERNIER input reellement employe, et on previent quand il change.

local UserInputService = game:GetService("UserInputService")

local InputDevice = {}

export type Kind = "Touch" | "KeyboardMouse" | "Gamepad"

local changed = Instance.new("BindableEvent")
-- (Kind) -> () : tire quand le type d'input actif change (ex : le joueur pose son clavier et touche l'ecran).
InputDevice.changed = changed.Event

local current: Kind = "KeyboardMouse"

local function kindOf(inputType: Enum.UserInputType): Kind?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	elseif inputType == Enum.UserInputType.Keyboard or string.find(inputType.Name, "Mouse") then
		return "KeyboardMouse"
	elseif string.find(inputType.Name, "Gamepad") then
		return "Gamepad"
	end
	return nil -- Focus, TextInput... : on ignore, ca ne change pas le "device" du joueur
end

local function set(kind: Kind)
	if kind ~= current then
		current = kind
		changed:Fire(current)
	end
end

-- Type d'input ACTIF (le dernier reellement utilise). A preferer aux capacites : un mobile peut avoir un clavier.
function InputDevice.kind(): Kind
	return current
end

function InputDevice.isTouch(): boolean
	return current == "Touch"
end

-- Etat de depart : on devine avec le dernier input connu, sinon les capacites de l'appareil.
local function guess(): Kind
	local last = kindOf(UserInputService:GetLastInputType())
	if last then
		return last
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "KeyboardMouse"
end

-- Singleton passif : mis en place a la 1re require (pas de ceremonie de bootstrap pour un simple detecteur).
current = guess()
UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	local k = kindOf(inputType)
	if k then
		set(k)
	end
end)

return InputDevice
