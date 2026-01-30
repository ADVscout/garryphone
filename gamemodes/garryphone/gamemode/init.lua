DEFINE_BASECLASS("gamemode_base")

--[[
	Garry Phone :D

	Made by figardo
	Commissioned by Dacoobers
	Inspired by Gartic Phone
]]

include("shared.lua")
AddCSLuaFile("shared.lua")
include("sh_ply_ext.lua")
AddCSLuaFile("sh_ply_ext.lua")

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("cl_hud.lua")
AddCSLuaFile("cl_menus.lua")
AddCSLuaFile("cl_postgame.lua")

include("sv_builds.lua")
include("sv_rounds.lua")
include("sv_gamemodes.lua")

local vguiLua = file.Find("garryphone/gamemode/vgui/*", "LUA")
for i = 1, #vguiLua do
	AddCSLuaFile("vgui/" .. vguiLua[i])
end

util.AddNetworkString("GP_NewRound")
util.AddNetworkString("GP_SendPrompt")
util.AddNetworkString("GP_SendRound")
util.AddNetworkString("GP_ShowBuild")
util.AddNetworkString("GP_StartGame")
util.AddNetworkString("GP_RevealPrompt")
util.AddNetworkString("GP_ShowResults")
util.AddNetworkString("GP_BackToLobby")
util.AddNetworkString("GP_ChangeSetting")
util.AddNetworkString("GP_Ready")
util.AddNetworkString("GP_SaveGame")
util.AddNetworkString("GP_SetSpawn")
util.AddNetworkString("GP_Reconnected")

function GM:InitPostEntity()
	local callbacks = concommand.GetTable()
	concommand.Add("gp_admin_cleanup", callbacks["gmod_admin_cleanup"])

	concommand.Add("gmod_admin_cleanup", function(ply)
		if GetRoundState() == STATE_LOBBY then RunConsoleCommand("gp_admin_cleanup") return end

		ply:ChatPrint("Garry Phone should automatically handle cleanup, please don't manually cleanup during a game.")
		ply:ChatPrint("If something has gone horribly wrong and you need to cleanup, the console command is now gp_admin_cleanup.")
	end)
end

function GM:PlayerSpawn(ply, transition)
	player_manager.SetPlayerClass(ply, "player_gphone")

	BaseClass.PlayerSpawn(self, ply, transition)
end

function GM:PlayerDisconnected(ply)
	if GetRoundState() != STATE_BUILD then return end

	ply:SaveBuild()
end

function GM:GetFallDamage()
	return 0
end

local lobbyPVP
function GM:PlayerShouldTakeDamage()
	if !lobbyPVP then
		lobbyPVP = GetConVar("gp_lobbypvp")
	end

	local rs = GetRoundState()
	if rs == STATE_LOBBY then return lobbyPVP:GetBool() end

	if rs != STATE_POST then return false end

	return true
end

local defaultWeps = {
	["gmod_tool"] = true,
	["gmod_camera"] = true,
	["weapon_physgun"] = true
}
function GM:PlayerCanPickupWeapon(ply, wep)
	return defaultWeps[wep:GetClass()]
end

function GM:PreventTransmitAll(ent, exception, stopTransmitting)
	local plys = self.Playing
	for i = 1, #plys do
		local ply = self.PlayerData[plys[i]].ply
		if !IsValid(ply) or ply == exception then continue end

		RecursiveSetPreventTransmit(ent, ply, stopTransmitting)
	end
end

function RecursiveSetPreventTransmit(ent, ply, stopTransmitting)
	if ent == ply or !IsValid(ent) or !IsValid(ply) then return end

	ent.GP_Hidden = stopTransmitting
	ent:SetPreventTransmit(ply, stopTransmitting)

	local tab = ent:GetChildren()
	for i = 1, #tab do
		RecursiveSetPreventTransmit(tab[i], ply, stopTransmitting)
	end
end

function GM:GetRecipient(ply, roundoffset)
	if !ply then
		error("GM:GetRecipient ply is nil!")
	end

	if isentity(ply) then ply = ply:SteamID64() end
	roundoffset = roundoffset or 0

	local roundNum = GetRound() + roundoffset
	if !self.PlayerData[ply] or !self.PlayerData[ply].order then
		error("GM:GetRecipient invalid player data for " .. tostring(ply))
	end
	
	if !self.PlayerData[ply].order[roundNum] then
		error("GM:GetRecipient no recipient found for round " .. roundNum .. " (player: " .. tostring(ply) .. ")")
	end

	return self.PlayerData[ply].order[roundNum]
end


-- LOBBY
local function StartGame(_, ply)
	if !ply:HasAuthority() then return end

	GAMEMODE:StartGame()
end
net.Receive("GP_StartGame", StartGame)

local function BackToLobby(_, ply)
	if GetRoundState() != STATE_POST or !ply:HasAuthority() then return end

	SetRoundState(STATE_LOBBY)

	game.CleanUpMap()
end
net.Receive("GP_BackToLobby", BackToLobby)

local function ChangeSetting(_, ply)
	if GetRoundState() != STATE_LOBBY or !ply:HasAuthority() then return end

	local settings = GAMEMODE.Settings
	local setting = settings[net.ReadUInt(bitsRequired(#settings)) + 1]
	if !setting then return end

	local cvar = GetConVar(setting.cvar)
	if setting.type == "checkbox" then
		cvar:SetBool(!cvar:GetBool())
	elseif setting.type == "num" then
		cvar:SetInt(net.ReadUInt(32))
	else
		cvar:SetString(net.ReadString())
	end
end
net.Receive("GP_ChangeSetting", ChangeSetting)


-- MID-GAME
local maxplybits = bitsRequired(game.MaxPlayers())
local function Reconnected(_, ply)
    -- anything that needs to be networked to our reconnected client goes here, otherwise see PLAYER:Init
    local plydata = GAMEMODE.PlayerData
    local mydata = plydata[ply:SteamID64()]

    local rs = GetRoundState()
    if rs == STATE_LOBBY then return end

    if mydata and !table.IsEmpty(mydata) and rs == STATE_BUILD then
		-- GM:SwitchToBuild
		-- Fix: Read from player's own album
		local sid = ply:SteamID64()
		local roundData = GAMEMODE.RoundData[sid] and GAMEMODE.RoundData[sid][GetRound()]
		local str = roundData and roundData.data or ""

        net.Start("GP_SendPrompt")
            net.WriteString(str)
        net.Send(ply)
    end

    local plys = GAMEMODE.Playing
    net.Start("GP_Reconnected")
        net.WriteUInt(#plys, maxplybits)
        for i = 1, #plys do
            local sid = plys[i]
            local data = plydata[sid]

            local isMe = data.ply == ply
            net.WriteBool(isMe)
            if isMe then continue end

            net.WritePlayer(data.ply)
            net.WriteUInt64(sid)
            net.WriteString(data.name)
        end
    net.Send(ply)
end
net.Receive("GP_Reconnected", Reconnected)


-- POST
local function LoadNextRound(_, ply)
	if !ply:HasAuthority() then return end

	GAMEMODE:LoadNextRound()
end
net.Receive("GP_SendRound", LoadNextRound)

local function RevealPrompt(_, ply)
	if !ply:HasAuthority() then return end

	local gm = GAMEMODE
	if gm.CurRound == 1 and gm.CurPly != 1 then
		if !gm.NextPly then
			gm.NextPly = false
		else
			game.CleanUpMap()
		end

		gm.NextPly = !gm.NextPly
	end

	if gm:IsBuildRound(gm.CurRound) then
		gm:ShowBuild()
	end

	net.Start("GP_RevealPrompt")
		net.WriteBool(gm.NextPly) -- did the host click "NEXT" instead of the chat button
	net.SendOmit(ply)
end
net.Receive("GP_RevealPrompt", RevealPrompt)

local function SendResults(_, ply)
	if !ply:HasAuthority() then return end

	net.Start("GP_ShowResults")
		net.WriteBool(net.ReadBool())
	net.SendOmit(ply)
end
net.Receive("GP_ShowResults", SendResults)


-- SAVE/LOAD
local function SaveGame(_, ply)
	if GetRoundState() != STATE_POST or !ply:HasAuthority() then return end

	local dir = "garryphone/" .. game.GetMap()
	if !file.Exists("garryphone", "DATA") then
		file.CreateDir("garryphone")
		file.CreateDir(dir)
	elseif !file.Exists(dir, "DATA") then
		file.CreateDir(dir)
	end

	local playing = GAMEMODE.Playing
	local pdata = GAMEMODE.PlayerData

	local nicks = {}
	for i = 1, #playing do
		local sid = playing[i]
		nicks[sid] = pdata[sid].name
	end

	file.Write(dir .. "/" .. os.date("%d.%m.%Y - %H-%M-%S") .. ".txt", util.TableToJSON(nicks) .. "\n" .. util.TableToJSON(GAMEMODE.RoundData))
end
net.Receive("GP_SaveGame", SaveGame)
concommand.Add("gp_savegame", function(ply) SaveGame(nil, ply) end)

local function LoadGame(ply, lefile)
	if !ply:HasAuthority() then return end

	if !file.Exists("garryphone", "DATA") then return end

	local data = file.Read("garryphone/" .. lefile .. ".txt", "DATA")
	if !data then return end

	GAMEMODE.RoundData = util.JSONToTable(data, false, true)

	GAMEMODE.Playing = {}
	GAMEMODE.PlayerData = {}

	for sid, _ in pairs(GAMEMODE.RoundData) do
		GAMEMODE.PlayerData[sid] = {ply = false, name = "Someone"}

		table.insert(GAMEMODE.Playing, sid)
	end

	GAMEMODE:EndGame()
end
concommand.Add("gp_loadgame", function(ply, cmd, args)
	if !ply:HasAuthority() or !file.Exists("garryphone", "DATA") then
		print("No replays found!")

		return
	end

	local lefile = args[1]
	if !lefile then
		local files = file.Find("garryphone/" .. game.GetMap() .. "/*", "DATA")
		if #files == 0 then
			print("No replays found on this map!")

			return
		end

		net.Start("GP_SendReplays")
			net.WriteUInt(#files, 8)
			for i = 1, #files do
				local f = files[i]:gsub(".txt", "")
				net.WriteString(f)
			end
		net.Send(ply)

		return
	end

	LoadGame(ply, lefile)
end, function(cmd)
	local files = file.Find("garryphone/" .. game.GetMap() .. "/*", "DATA")
		for i = 1, #files do
		local f = files[i]
		f = f:gsub(".txt", "")

		files[i] = cmd .. [[ "]] .. f .. [["]]
	end

	return files
end)


-- DEBUG
local commands = {
	["!end"] = function(ply) if !ply:HasAuthority() then return end SetRoundState(STATE_POST) GAMEMODE:EndGame() end
}

gameevent.Listen( "player_say" )
hook.Add( "player_say", "player_say_example", function( data )
	local ply = Player(data.userid)
	local text = data.text

	if commands[text:lower()] then commands[text:lower()](ply) end
end )