local meta = FindMetaTable("Player")

function meta:HasAuthority()
	if !game.IsDedicated() then
		return self:IsListenServerHost()
	end

	local adminsPresent = false
	for _, ply in player.Iterator() do
		if !ply:IsAdmin() then continue end

		adminsPresent = true
		break
	end

	return adminsPresent and self:IsAdmin() or self:EntIndex() == 1
end

if SERVER then
	function meta:SetBuildSpawn(pos, ang)
		if !self.BuildSpawn then self.BuildSpawn = {} end

		self.BuildSpawn.pos = pos or self:GetPos()
		self.BuildSpawn.ang = ang or self:GetAngles()

		net.Start("GP_SetSpawn")
			net.WriteVector(self.BuildSpawn.pos)
			net.WriteFloat(self.BuildSpawn.ang.y)
		net.Send(self)
	end

	function meta:SetReady(bool)
		SetReady(self:SteamID64(), bool)
	end

	function meta:GetReady()
		return GetReady(self:SteamID64())
	end

	function meta:SaveBuild(data, asdupe, round)
		data = data or undo.GetTable()[self:UniqueID()]
		if !data then return end

		round = round or GetRound()

		local build = {}
		for i = 1, #data do
			data[i].Lock = true

			local props = data[i].Entities
			if !props then continue end
			for j = 1, #props do
				local prop = props[j]
				-- HACK: there's probably a better way to ignore ents created for a constraint
				if !IsValid(prop) or prop:IsConstraint() or prop:GetClass() == "gmod_winch_controller" then continue end

				build[#build + 1] = prop
			end
		end

		if asdupe then
			build = duplicator.CopyEnts(build)
		end

		if self.BuildSpawn and !table.IsEmpty(self.BuildSpawn) then
			build.pos = self.BuildSpawn.pos
			build.ang = self.BuildSpawn.ang

			self.BuildSpawn = nil
		else
			build.pos = self:GetPos()
			build.ang = self:EyeAngles()
		end

		-- FIX: For build rounds, save to own album instead of using GetRecipient
		local sid = self:SteamID64()
		local gm = GAMEMODE
		
		-- Check if this is a build round
		local isBuildRound = gm:IsBuildRound(round)
		
		if isBuildRound then
			-- Build rounds: save to own album
			if gm.RoundData[sid] and gm.RoundData[sid][round] then
				gm.RoundData[sid][round].data = build
			end
		else
			-- Prompt rounds: save to recipient's album (only if GetRecipient succeeds)
			local success, recipient = pcall(gm.GetRecipient, gm, self)
			
			if success and recipient then
				if gm.RoundData[recipient] and gm.RoundData[recipient][round] then
					gm.RoundData[recipient][round].data = build
				end
			else
				-- Fallback: save to own album if GetRecipient fails
				if gm.RoundData[sid] and gm.RoundData[sid][round] then
					gm.RoundData[sid][round].data = build
				end
			end
		end
	end
end