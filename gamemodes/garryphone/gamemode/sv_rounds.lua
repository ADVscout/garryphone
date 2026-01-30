local game_mode = CreateConVar("gp_gamemode", "default")

-- playin sudoku
local function DoPlayerOrder(plyCount, plyOrder, row, col)
	-- Special case: 2 players just swap them
	-- Fill ALL columns with the same swap pattern since there's only one valid permutation
	if plyCount == 2 then
		for c = 1, plyCount do
			plyOrder[1][c] = 2  -- Player 1 always writes for Player 2
			plyOrder[2][c] = 1  -- Player 2 always writes for Player 1
		end
		return true
	end

	if row == plyCount + 1 then
		return true
	end

	-- For 3+ players, only fill plyCount-1 columns to avoid diagonal
	if col == plyCount then
		return DoPlayerOrder(plyCount, plyOrder, row + 1, 1)
	end

	for num = 1, plyCount do
		if num == row then continue end

		local valid = true
		for i = 1, plyCount do
			if plyOrder[row][i] == num or plyOrder[i][col] == num then
				valid = false
				break
			end
		end

		if !valid then continue end

		plyOrder[row][col] = num

		if DoPlayerOrder(plyCount, plyOrder, row, col + 1) then
			return true
		end

		plyOrder[row][col] = nil
	end

	return false
end

function GM:StartGame()
	game.CleanUpMap()

	self.BuildRoundPlayed = false

	self.PlayerData = {}
	self.Playing = {}

	self.RoundData = {}
	self.BuildRounds = {}

	local plys = select(2, player.Iterator())
	for i = 1, #plys do
		local ply = plys[i]
		if ply:Team() == TEAM_SPECTATOR then continue end

		local sid = ply:SteamID64()

		self.PlayerData[sid] = {ply = ply, name = ply:Nick()}
		table.insert(self.Playing, sid)

		ply:SetTeam(TEAM_PLAYING)
	end

	local plyCount = #self.Playing

	-- Determine number of rounds to play
	local numRoundsCvar = GetConVar("gp_numrounds")
	local numRounds = numRoundsCvar and numRoundsCvar:GetInt() or 0
	if numRounds <= 0 then
		numRounds = plyCount -- Default to player count
	end

	-- Store the number of rounds for later use
	self.TotalRounds = numRounds

	local plyOrder = {}
	for i = 1, plyCount do
		plyOrder[i] = {}
	end

	if !DoPlayerOrder(plyCount, plyOrder, 1, 1) then
		error("Player ordering error! Something went very wrong!")
		return
	end

	local gm = game_mode:GetString()
	local orderFn = self.Gamemodes[gm] or self.Gamemodes["default"]
	orderFn = orderFn.order

	-- Determine which rounds are build rounds
	for i = 1, numRounds do
		self.BuildRounds[i] = orderFn(i, numRounds)
	end

	-- FIX: First, set up .order for all players based on plyOrder
	for i = 1, plyCount do
		local sid = self.Playing[i]
		self.PlayerData[sid].order = {}
		
		local promptNum = 0
		for j = 1, numRounds do
			if !self.BuildRounds[j] then
				promptNum = promptNum + 1
				
				-- Determine which album this player writes to in this prompt round
				local maxCols = plyCount == 2 and plyCount or (plyCount - 1)
				local orderIndex = ((promptNum - 1) % maxCols) + 1
				
				if plyCount == 1 then
					self.PlayerData[sid].order[j] = sid
				else
					local albumIndex = plyOrder[i][orderIndex]
					local albumSID = self.Playing[albumIndex]
					self.PlayerData[sid].order[j] = albumSID
				end
			end
		end
	end

	-- FIX: Then, set up RoundData based on .order
	for i = 1, plyCount do
		local sid = self.Playing[i]
		self.RoundData[sid] = {}

		for j = 1, numRounds do
			local isBuildRound = self.BuildRounds[j]
			
			-- Determine who creates content for this album in this round
			local authorsid
			if isBuildRound then
				-- For build rounds, the album owner builds
				authorsid = sid
			else
				-- For prompt rounds, find who writes to this album by checking .order
				authorsid = nil
				for k = 1, plyCount do
					local authorSID = self.Playing[k]
					if self.PlayerData[authorSID].order[j] == sid then
						authorsid = authorSID
						break
					end
				end
				authorsid = authorsid or sid  -- Fallback
			end
			
			self.RoundData[sid][j] = {author = authorsid}
		end
	end

	for _, ply in player.Iterator() do
		ply:Spawn()
	end

	net.Start("GP_NewRound")
	net.Broadcast()

	SetRound(1)
	self:SwitchToPrompt(1)
end

function GM:IsBuildRound(round)
	return self.BuildRounds[round]
end

local promptTime
function GM:SwitchToPrompt(curRound)
	if !promptTime then
		promptTime = GetConVar("gp_prompttime")
	end

	SetRoundTime(promptTime:GetFloat())

	for sid, data in pairs(self.PlayerData) do
		SetReady(sid, false)
	end

	if curRound > 1 then
		self:SaveBuilds(curRound, false)

		-- FIX: Show each player the build from the album they're about to describe
		local nextRound = curRound + 1
		
		for sid, data in pairs(self.PlayerData) do
			local ply = data.ply
			local validPly = IsValid(ply)
			
			if validPly then
				ply:Spawn()
			end

			-- Find which album this player will be working on in the next round
			local targetAlbum = self.PlayerData[sid].order and self.PlayerData[sid].order[nextRound]
			if !targetAlbum then
				-- Fallback to own album if no target (shouldn't happen)
				targetAlbum = sid
			end

			-- Show them the build from that album's previous round
			local buildData = self.RoundData[targetAlbum] and self.RoundData[targetAlbum][curRound]
			if !buildData then continue end
			
			local build = buildData.data
			if !build or !istable(build) or #build == 0 then continue end

			local builder = self.PlayerData[buildData.author].ply

			for i = 1, #build do
				local ent = build[i]

				-- hide build from the builder
				if IsValid(builder) then
					RecursiveSetPreventTransmit(ent, builder, true)
				end

				if validPly then
					-- show build to the guesser
					RecursiveSetPreventTransmit(ent, ply, false)
				end

				ent:SetNWEntity("GP_Owner", nil)
			end

			if validPly and build.pos and build.ang then
				ply:SetPos(build.pos)
				ply:SetEyeAngles(build.ang)
			end
		end
	end

	SetRoundState(STATE_PROMPT)
end

local buildTime
function GM:SwitchToBuild(curRound)
	if !buildTime then
		buildTime = GetConVar("gp_buildtime")
	end

	SetRoundTime(buildTime:GetFloat())

	if self.BuildRoundPlayed then
		self:BuildsToDupes(curRound)

		game.CleanUpMap()
	else
		self.BuildRoundPlayed = true
	end

	for sid, data in pairs(self.PlayerData) do
		SetReady(sid, false)

		local ply = data.ply
		if !IsValid(ply) then continue end

		ply:Spawn()
		ply:SetBuildSpawn()

		-- Read the prompt from the player's own album
		local roundData = self.RoundData[sid][curRound]
		local str = roundData and roundData.data or ""

		net.Start("GP_SendPrompt")
			net.WriteString(str)
		net.Send(ply)
	end

	SetRoundState(STATE_BUILD)
end

function GM:EndGame(curRound)
	curRound = curRound or GetRound()

	if curRound > 1 then
		local oldState = GetRoundState()
		if oldState == STATE_BUILD then
			self:SaveBuilds(curRound, true)
		else
			self:BuildsToDupes(curRound)
		end
	end

	game.CleanUpMap()

	for _, ply in player.Iterator() do
		ply:Spawn()

		for _, ply2 in player.Iterator() do
			RecursiveSetPreventTransmit(ply, ply2, false)
		end

		ply:SetTeam(TEAM_PLAYING)
	end

	self.CurPly = 1
	self.CurRound = 0

	SetRoundState(STATE_POST)

	-- PrintTable(self.RoundData)
end

local plyBits = bitsRequired(game.MaxPlayers())

local sid, data, authorID, author, authorName
function GM:LoadNextRound()
	local playing = self.Playing
	local numplaying = #playing
	local totalRounds = self.TotalRounds or numplaying

	self.CurRound = self.CurRound + 1

	if self.CurRound > totalRounds then
		self.CurPly = self.CurPly + 1
		self.CurRound = 1
	end

	local gameOver = self.CurPly > numplaying
	local isBuild = self:IsBuildRound(self.CurRound)

	if !gameOver then
		sid = playing[self.CurPly]
		data = self.RoundData[sid][self.CurRound]

		authorID = data.author
		author = self.PlayerData[authorID].ply
		authorName = self.PlayerData[authorID].name

		data = data.data

		if isBuild then
			game.CleanUpMap()
		end
	end

	net.Start("GP_SendRound")

	net.WriteUInt(self.CurPly, plyBits)
	net.WriteUInt(self.CurRound, plyBits)

	if gameOver then
		net.WriteUInt(STATE_POST, 2) -- no rounds remaining
		net.Broadcast()

		return
	end

	net.WriteUInt(isBuild and STATE_BUILD or STATE_PROMPT, 2)

	local authorValid = IsValid(author)
	net.WriteBool(authorValid)

	if authorValid then
		net.WritePlayer(author)
	else
		net.WriteString(authorName)
	end

	if !isBuild then -- prompt
		local valid = isstring(data)
		net.WriteBool(valid)

		if valid then
			net.WriteString(data)
		end
	end

	net.Broadcast()
end

function GM:ShowBuild()
	if !data or isstring(data) then return end

	for _, ply in player.Iterator() do
		ply:Spawn()

		if data.pos and data.ang then
			ply:SetPos(data.pos)
			ply:SetEyeAngles(data.ang)
		end
	end

	data = duplicator.Paste(self.PlayerData[authorID].ply, data.Entities, data.Constraints)

	if #data == 0 then return end

	local ent
	for i = 1, #data do
		ent = data[i]
		local valid = IsValid(ent) and ent:EntIndex()
		if valid then break end
	end

	if !IsValid(ent) then return end

	net.Start("GP_ShowBuild")
		net.WriteUInt(ent:EntIndex(), MAX_EDICT_BITS)
	net.Broadcast()
end

local function ReceivePrompt(_, ply)
	if GetRoundState() != STATE_PROMPT then return end

	local gm = GAMEMODE

	local prompt = net.ReadString()
	local plySID = ply:SteamID64()

	local curRound = GetRound()
	
	-- For prompt rounds, .order tells us which album this player writes to
	local recipient = gm.PlayerData[plySID].order and gm.PlayerData[plySID].order[curRound]
	
	-- Safety check: if recipient is nil, save to the player's own album
	if !recipient then
		recipient = plySID
	end

	if gm.RoundData[recipient] and gm.RoundData[recipient][curRound] then
		gm.RoundData[recipient][curRound].data = prompt
		gm.RoundData[recipient][curRound].author = plySID
	end

	if !ply:GetReady() then
		ply:SetReady(true)
	end
end
net.Receive("GP_SendPrompt", ReceivePrompt)

local infiniteTime
function GM:DoRoundTime()
	if !infiniteTime then
		infiniteTime = GetConVar("gp_infinitetime")
	end

	if infiniteTime:GetBool() or GetRoundTime() > CurTime() then return end

	self:NextRound()
end

function GM:NextRound()
	local curRound = GetRound()
	local totalRounds = self.TotalRounds or #self.Playing

	if curRound >= totalRounds then
		self:EndGame(curRound)
	elseif self:IsBuildRound(curRound + 1) then
		self:SwitchToBuild(curRound)
	else
		self:SwitchToPrompt(curRound)
	end

	SetRound(curRound + 1)
end

local thinkStates = {
	[STATE_PROMPT] = true,
	[STATE_BUILD] = true
}

function GM:Think()
	local shouldThink = thinkStates[GetRoundState()]
	if !shouldThink then return end

	self:DoRoundTime()

	local ready = true
	for _, pdata in pairs(self.PlayerData) do
		local ply = pdata.ply
		if !IsValid(ply) then continue end

		local done = ply:GetReady()
		if !done then
			ready = done
			break
		end
	end

	if !ready then return end

	self:NextRound()
end