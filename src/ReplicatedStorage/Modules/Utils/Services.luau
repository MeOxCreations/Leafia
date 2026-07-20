--!strict
-- Raccourci vers les services Roblox, pour eviter de repeter game:GetService(...) partout.
-- Optionnel : sur le projet precedent tu appelais GetService directement dans chaque fichier. Les deux
-- marchent, garde celui que tu preferes, mais garde le MEME dans tout le projet.

local Services = {
	Players = game:GetService("Players"),
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	ReplicatedFirst = game:GetService("ReplicatedFirst"),
	ServerStorage = game:GetService("ServerStorage"),
	ServerScriptService = game:GetService("ServerScriptService"),
	RunService = game:GetService("RunService"),
	TweenService = game:GetService("TweenService"),
	UserInputService = game:GetService("UserInputService"),
	ContextActionService = game:GetService("ContextActionService"),
	SoundService = game:GetService("SoundService"),
	Workspace = game:GetService("Workspace"),
	Lighting = game:GetService("Lighting"),
	HttpService = game:GetService("HttpService"),
	MarketplaceService = game:GetService("MarketplaceService"),
	DataStoreService = game:GetService("DataStoreService"),
	CollectionService = game:GetService("CollectionService"),
	TextService = game:GetService("TextService"),
	ContentProvider = game:GetService("ContentProvider"),
}

return Services
