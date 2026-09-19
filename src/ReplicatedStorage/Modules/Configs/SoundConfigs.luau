--!strict
-- TOUS LES SONS DU JEU, PAR LEUR ID. Table de donnees pure.
--
-- POURQUOI. Un Sound pose dans Studio n'existe que dans la place ou on l'a pose : Rojo ne synchronise pas
-- SoundService. Il manque alors dans l'autre place SANS RIEN DIRE -- vecu sur la replique devant la haie, presente
-- dans une place et absente du didacticiel, et on cherchait le bug dans la voix. Ici le son part sur GitHub avec
-- le code et arrive dans TOUTES les places d'un coup.
--
-- LE SERVEUR LES POSE AU DEMARRAGE, a ce chemin sous SoundService (voir SoundRegistryService) : tout le code qui
-- cherche un son par son chemin le trouve sans avoir change. Si un Sound existe deja a ce chemin dans Studio, il
-- prend l'id d'ici (la config gagne) et garde ses enfants (effets) et ses reglages non precises -- on peut donc
-- migrer petit a petit, puis supprimer les Sound de Studio.
--
-- CLE = le chemin sous SoundService, separe par des "/". `volume`, `speed`, `looped` : FACULTATIFS. Absents, un Sound
-- deja pose dans Studio GARDE ses valeurs (son volume regle a l'oreille n'est pas ecrase) ; un son cree par le code
-- prend les defauts de Roblox (0.5, 1, pas de boucle). Seul l'id est toujours impose.
--
-- POUR REMPLIR : coller `scripts/studio/ExporterSons.lua` dans la barre de commandes de Studio, il imprime ces
-- lignes a partir des Sound deja poses. La liste ci-dessous en vient (19/09/2026, 82 sons, aucun effet ni
-- SoundGroup) : les Sound de Studio peuvent donc etre supprimes, tout est ici.

-- `playing = true` : le son joue tout seul des le demarrage, pour tout le monde (une ambiance comme `Nature`).
export type Entry = { id: string, volume: number?, speed: number?, looped: boolean?, playing: boolean? }

local SoundConfigs: { [string]: Entry } = {
	-- ===== TAILLE-HAIE =====
	["Sounds/Engins/HedgeTrimmer/IdleSound"] = { id = "rbxassetid://125973675482567", looped = true },
	["Sounds/Engins/HedgeTrimmer/SpeedStartMotor"] = { id = "rbxassetid://140365046135870" },
	["Sounds/Engins/HedgeTrimmer/SpeedStartMotorInfinite"] = { id = "rbxassetid://111384966371570" },
	["Sounds/Engins/HedgeTrimmer/StartFirstSound"] = { id = "rbxassetid://124324008992320" },
	["Sounds/Engins/HedgeTrimmer/TryLaunchSound"] = { id = "rbxassetid://105854367308281" },
	-- ===== ECHELLE =====
	["Sounds/Engins/Ladder/LadderClimbStepOne"] = { id = "rbxassetid://123516158890121" },
	["Sounds/Engins/Ladder/LadderClimbStepTwo"] = { id = "rbxassetid://91896511790466" },
	["Sounds/Engins/Ladder/LadderDeposeSound"] = { id = "rbxassetid://101257499986377" },
	["Sounds/Engins/Ladder/LadderTakeSound"] = { id = "rbxassetid://130066040440975" },
	-- ===== TONDEUSE =====
	["Sounds/Engins/LawnMower/IdleLawnMowerSound"] = { id = "rbxassetid://108231814930143" },
	["Sounds/Engins/LawnMower/SucessTryLaunchSound"] = { id = "rbxassetid://109057911869830" },
	["Sounds/Engins/LawnMower/TryLaunchSound"] = { id = "rbxassetid://130333921586760" },
	-- ===== RATEAU =====
	["Sounds/Engins/Rake/RakeSound"] = { id = "rbxassetid://120265530505885" },
	-- ===== ENVIRONNEMENT (pas, feuilles) =====
	["Sounds/Environnement/FootSteps/GroundStepSound"] = { id = "rbxassetid://92715028306400" },
	["Sounds/Environnement/Leafs/LeafCutSound"] = { id = "rbxassetid://71548559176319" },
	-- ===== AMBIANCE (joue toute seule, pour tout le monde) =====
	["Sounds/Game/Background/Nature"] = { id = "rbxassetid://118755434492556", volume = 0.1, looped = true, playing = true },
	-- ===== SONS DU MONDE (camion, boite aux lettres, depots) =====
	["Sounds/Game/GlobalSounds/CloseDoorTruckSound"] = { id = "rbxassetid://86379404626306" },
	["Sounds/Game/GlobalSounds/CloseMailboxSound"] = { id = "rbxassetid://116996075824435" },
	["Sounds/Game/GlobalSounds/DropSound"] = { id = "rbxassetid://101141177714787" },
	["Sounds/Game/GlobalSounds/JoinSound"] = { id = "rbxassetid://103716524346544" },
	["Sounds/Game/GlobalSounds/OpenDoorTruckSound"] = { id = "rbxassetid://131610185149540" },
	["Sounds/Game/GlobalSounds/OpenMailboxSound"] = { id = "rbxassetid://76627983706798" },
	-- ===== MUSIQUES DU MODE BUILD =====
	["Sounds/Game/Musics/Build/MusicBuild1"] = { id = "rbxassetid://109736730543867", volume = 0.2 },
	["Sounds/Game/Musics/Build/MusicBuild2"] = { id = "rbxassetid://135887795209145", volume = 0.2 },
	["Sounds/Game/Musics/Build/MusicBuild3"] = { id = "rbxassetid://100473199218843", volume = 0.2 },
	["Sounds/Game/Musics/Build/MusicBuild4"] = { id = "rbxassetid://126815240231500", volume = 0.2 },
	["Sounds/Game/Musics/Build/MusicBuild5"] = { id = "rbxassetid://71266878799604", volume = 0.2 },
	-- ===== MUSIQUES (la boucle est posee par le code qui les joue) =====
	["Sounds/Game/Musics/Music1"] = { id = "rbxassetid://96165653865003" },
	["Sounds/Game/Musics/Music2"] = { id = "rbxassetid://133946377022705", volume = 0.2 },
	["Sounds/Game/Musics/MusicMainMenu"] = { id = "rbxassetid://134274317565831", volume = 0.2 },
	-- ===== SCENE 1 : la porte =====
	["Sounds/Scenes/Scene1/DingDongSound"] = { id = "rbxassetid://82126204576333" },
	["Sounds/Scenes/Scene1/KnockDoorSound"] = { id = "rbxassetid://104599555824865" },
	["Sounds/Scenes/Scene1/OpenDoorSound"] = { id = "rbxassetid://139842253747596" },
	["Sounds/Scenes/Scene1/SceneFontSound"] = { id = "rbxassetid://98223755178135" },
	["Sounds/Scenes/Scene1/TryUnlockDoorSound"] = { id = "rbxassetid://135441014182396" },
	-- ===== LES VOIX DU GRAND-PERE =====
	["Sounds/Scenes/Voices/Oldman_scene_speech_0"] = { id = "rbxassetid://116521869903565" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_1"] = { id = "rbxassetid://138057580250669" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_AsUCanSeeDoorTruck"] = { id = "rbxassetid://90581071724822" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_BeforeOpen"] = { id = "rbxassetid://100538084400814" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_DidntFinishItAll"] = { id = "rbxassetid://118418222005740" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_ExplainToolTruck"] = { id = "rbxassetid://94100786074977" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Final_mybuisness"] = { id = "rbxassetid://91667448908254" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Final_mybuisness_1"] = { id = "rbxassetid://82398954870392" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Final_say_1"] = { id = "rbxassetid://91125045666381" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_GoOnTruck"] = { id = "rbxassetid://95560463779429" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_GrabMowerAgain"] = { id = "rbxassetid://101432488664034" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_GrabTheShear"] = { id = "rbxassetid://120868682814149" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_HappyForCutHedge"] = { id = "rbxassetid://126978564351732" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_HeppyForCutGrass"] = { id = "rbxassetid://135447734670510" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_1"] = { id = "rbxassetid://138379579967397" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_2"] = { id = "rbxassetid://95481014857786" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_3"] = { id = "rbxassetid://111558424509433" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_4"] = { id = "rbxassetid://128883051980543" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_5"] = { id = "rbxassetid://71310807905839" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Impatient_opentruck_1"] = { id = "rbxassetid://121008440674395" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_MowThatLawn"] = { id = "rbxassetid://90473313629601" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_OpenTruckBack"] = { id = "rbxassetid://132995006132841" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Perfect"] = { id = "rbxassetid://118338500537538" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_PerfectComeSeeMe"] = { id = "rbxassetid://119735842161658" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_PullTheRope"] = { id = "rbxassetid://115776081911643" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Pulltherope2"] = { id = "rbxassetid://74744130019845" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_PutBinDown"] = { id = "rbxassetid://101012870678343" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_PutBinDown2"] = { id = "rbxassetid://78232383402705" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_PutBinDown3"] = { id = "rbxassetid://77491840522166" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_SayComeToCutHedge"] = { id = "rbxassetid://120698768006337" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_SayHowPickupLeaves"] = { id = "rbxassetid://138387355567638" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_HupJump"] = { id = "rbxassetid://100435204099052" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_SeatDown"] = { id = "rbxassetid://124267831530621" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_1"] = { id = "rbxassetid://96060574109385" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_2"] = { id = "rbxassetid://131152052946573" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_3"] = { id = "rbxassetid://87484201791752" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_4"] = { id = "rbxassetid://76409832856011" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_5"] = { id = "rbxassetid://104171039520251" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Say_wait_player_6"] = { id = "rbxassetid://120478642081816" },
	["Sounds/Scenes/Voices/Oldman_scene_speech_Thishedge_needcut"] = { id = "rbxassetid://128358915165021" },
	-- ===== INTERFACE =====
	["Sounds/UI/AppearSound_1"] = { id = "rbxassetid://138424352985426", volume = 0.4 },
	["Sounds/UI/HoverButtonSound"] = { id = "rbxassetid://106419078545029", volume = 0.4 },
	["Sounds/UI/NotificationSound"] = { id = "rbxassetid://116529150972106", volume = 0.4 },
	["Sounds/UI/PassingSound"] = { id = "rbxassetid://136350943692482", volume = 0.4 },
	["Sounds/UI/PopSound_1"] = { id = "rbxassetid://85294471660646", volume = 0.4 },
	["Sounds/UI/PressButtonSound"] = { id = "rbxassetid://77899431201803" },
	["Sounds/UI/PressCursorSound"] = { id = "rbxassetid://120539641598067", volume = 0.012 },
}

return SoundConfigs
