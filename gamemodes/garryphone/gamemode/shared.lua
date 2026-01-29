DeriveGamemode("sandbox")

include("player_class/player_gphone.lua")

GM.Name = "Garry Phone"
GM.Author = "figardo, Gamer"

GM.Settings = {
	{name = "InfiniteTime", cvar = "gp_infinitetime", type = "checkbox", default = 0, help = "Disable time limits?", replicated = true, grey = {cvars = {2, 3}, val = true}},
	{name = "PromptTime", cvar = "gp_prompttime", type = "num", default = "30", help = "How long are players given to type a prompt?"},
	{name = "BuildTime", cvar = "gp_buildtime", type = "num", default = "120", help = "How long are players given to build?"},
	{name = "NumRounds", cvar = "gp_numrounds", type = "num", default = "0", help = "Number of rounds (0 = same as player count)", replicated = true},
	{name = "LobbyPVP", cvar = "gp_lobbypvp", type = "checkbox", default = 0, help = "Should players be allowed to kill each other in the lobby?"}
}

function GM:CreateConVars()
	local dedicated = game.IsDedicated()
	local settings = self.Settings
	for i = 1, #settings do
		local setting = settings[i]
		if CLIENT and !dedicated and !setting.replicated then continue end

		local flags = CLIENT and FCVAR_REPLICATED or FCVAR_ARCHIVE
		if SERVER and (setting.replicated or dedicated) then
			flags = flags + FCVAR_REPLICATED
		end

		CreateConVar(setting.cvar, setting.default, flags, setting.help)
	end
end

STATE_LOBBY = 0
STATE_PROMPT = 1
STATE_BUILD = 2
STATE_POST = 3

TEAM_PLAYING = 1

function SetRound(round)
	SetGlobal2Int("GP_Round", round)
end

function GetRound()
	return GetGlobal2Int("GP_Round")
end

function SetRoundState(state)
	SetGlobal2Int("GP_RoundState", state)
end

function GetRoundState()
	return GetGlobal2Int("GP_RoundState")
end

function SetRoundTime(time)
	SetGlobal2Float("GP_RoundTime", CurTime() + time)
end

function GetRoundTime()
	return GetGlobal2Float("GP_RoundTime")
end

function GM:Initialize()
	self.RoundData = {}

	SetRound(0)
	SetRoundState(STATE_LOBBY)
	SetRoundTime(CurTime())

	if SERVER then
		self:CreateConVars()
	end
end

function GM:CreateTeams()
	team.SetUp(TEAM_PLAYING, "Playing", Color(149, 0, 255))
end

function GM:ShouldCollide(ent1, ent2)
	if ent1:IsWorld() or ent2:IsWorld() then return true end

	if ent1:IsPlayer() then
		if ent2:IsPlayer() then return false end

		return ent1 == ent2:GetNWEntity("GP_Owner")
	end

	if ent2:IsPlayer() then
		return ent2 == ent1:GetNWEntity("GP_Owner")
	end

	return ent1:GetNWEntity("GP_Owner") == ent2:GetNWEntity("GP_Owner")
end

local toolStates = {
	[STATE_LOBBY] = true,
	[STATE_BUILD] = true
}

function GM:CanTool()
	return toolStates[GetRoundState()]
end

function bitsRequired(num)
	local bits, max = 0, 1

	while max <= num do
		bits = bits + 1
		max = max + max
	end

	return bits
end