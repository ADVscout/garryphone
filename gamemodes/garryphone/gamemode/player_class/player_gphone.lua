AddCSLuaFile()
DEFINE_BASECLASS( "player_sandbox" )

local PLAYER = {}

function PLAYER:Init()
	local rs = GetRoundState()
	if rs != STATE_PROMPT and rs != STATE_BUILD then return end

	local plydata = GAMEMODE.PlayerData
	if !plydata or table.IsEmpty(plydata) then return end

	local ply = self.Player
	local sid = ply:SteamID64()
	local mydata = plydata[sid]
	if !mydata or table.IsEmpty(mydata) then
		ply:ChatPrint("Game already in progress! You will be spectator until the game ends.")
		ply:SetTeam(TEAM_SPECTATOR)

		if CLIENT then
			local gm = GAMEMODE

			gm:OnSpawnMenuClose()

			gm.MenuLock = false
			gm:KillMenuScreen(true)
		end

		return
	end

	if CLIENT then return end

	ply:SetTeam(TEAM_PLAYING)
	mydata.ply = ply

	-- hide every other player from us (we are hidden to them by PLAYER:Spawn)
	for _, p in player.Iterator() do
		if p == ply then continue end

		RecursiveSetPreventTransmit(p, ply, true)

		-- hide this player's build from us
		local data = undo.GetTable()[p:UniqueID()]
		if !data then continue end
		for i = 1, #data do
			local props = data[i].Entities
			if !props then continue end

			for j = 1, #props do
				local prop = props[j]
				RecursiveSetPreventTransmit(prop, ply, true)
			end
		end
	end

	-- if we need to network something to this player then we wait for them to send GP_Reconnected first (init.lua)
	if rs == STATE_PROMPT then
		-- GM:SwitchToPrompt
		local curRound = GetRound()
		if curRound == 1 then return end

		-- Fix: Read from player's own album
		-- GetRound() returns current round, we want build from previous round
		local buildData = GAMEMODE.RoundData[sid] and GAMEMODE.RoundData[sid][curRound - 1]
		if !buildData then return end
		
		local build = buildData.data
		if !build then return end

		for i = 1, #build do
			local ent = build[i]

			-- show the build we were meant to be guessing
			RecursiveSetPreventTransmit(ent, ply, false)
		end

		if build.pos and build.ang then
			ply:SetPos(build.pos)
			ply:SetEyeAngles(build.ang)
		end
	elseif rs == STATE_BUILD then
		-- GM:SwitchToBuild
		SetReady(sid, false)

		ply:Spawn()
		ply:SetBuildSpawn()
	end
end

function PLAYER:Loadout()
	self.Player:RemoveAllAmmo()

	self.Player:Give("gmod_tool")
	self.Player:Give("gmod_camera")
	self.Player:Give("weapon_physgun")

	self.Player:SwitchToDefaultWeapon()
end

function PLAYER:Spawn()
	BaseClass.Spawn( self )

	if self.Player.DiedAward then -- this is extremely retarded but it fixes SetPreventTransmit when players die/reconnect
		self.Player.DiedAward = false

		self.Player:Spawn()
	end

	self.Player:SetCustomCollisionCheck(true) -- disable player to player collisions
	self.Player:CollisionRulesChanged()

	local rs = GetRoundState()
	if rs == STATE_PROMPT or rs == STATE_BUILD then
		for _, ply in player.Iterator() do
			if ply == self.Player then continue end

			RecursiveSetPreventTransmit(self.Player, ply, true) -- put each player in their own realm
		end
	end
end

function PLAYER:Death()
	local rs = GetRoundState()
	if rs == STATE_PROMPT or rs == STATE_BUILD then
		self.Player.DiedAward = true
	end
end

player_manager.RegisterClass( "player_gphone", PLAYER, "player_sandbox" )