--!strict
-- SON DE CLIC DU CURSEUR : un pop discret au clic gauche DANS LE MONDE (hors interface). Les clics SUR un bouton
-- ont leur propre son (PressButtonSound, joue par ButtonSlime) : on filtre donc les clics pris par l'UI
-- (gameProcessed) pour ne jamais jouer deux sons a la fois. Le volume se regle sur le Sound dans Studio (bas).

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundUtils = require(ReplicatedStorage.Modules.Utils.SoundUtils)

local ClickSoundController = {}

-- Son 2D (pas de host). Dedie au clic curseur (monde), distinct du clic bouton (PressButtonSound).
local CLICK_SOUND = { "Sounds", "UI", "PressCursorSound" }

function ClickSoundController.init()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed = le clic a ete pris par l'interface (un bouton, un panneau). Dans ce cas c'est ButtonSlime
		-- qui sonne (PressButtonSound) : on se tait pour ne pas doubler.
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			SoundUtils.play(CLICK_SOUND)
		end
	end)
end

return ClickSoundController
