include("shared.lua")
include("sh_ply_ext.lua")
include("cl_hud.lua")
include("cl_menus.lua")
include("cl_postgame.lua")

local vguiLua = file.Find("garryphone/gamemode/vgui/*", "LUA")
for i = 1, #vguiLua do
	include("vgui/" .. vguiLua[i])
end

function GM:Initialize()
	self.LobbyOpen = false
end

function GM:InitPostEntity()
	local rs = GetRoundState()
	if rs != STATE_LOBBY then
		net.Start("GP_Reconnected")
		net.SendToServer()
	end

	self:CreateConVars()
end

if CLIENT then
	local fontsCreated = false

	-- FIX: Declare GenerateFonts as local before it's used
	local function GenerateFonts()
		if fontsCreated then return end
		fontsCreated = true

		local baseSize = math.floor(ScrH() * 0.03) -- stable scale

		surface.CreateFont("GPTargetID", {
			font = "Arial", -- EXISTS everywhere
			size = baseSize,
			outline = true,
			extended = false
		})

		surface.CreateFont("GPTextEntry", {
			font = "Arial",
			size = baseSize,
			extended = false
		})

		surface.CreateFont("GPBoldSmall", {
			font = "Arial",
			size = baseSize,
			weight = 800,
			extended = false
		})

		surface.CreateFont("GPTitle", {
			font = "Arial",
			size = math.floor(baseSize * 1.3),
			outline = true,
			extended = false
		})

		surface.CreateFont("GPBold", {
			font = "Arial",
			size = math.floor(baseSize * 1.6),
			weight = 800,
			extended = false
		})
	end

	hook.Add("Initialize", "GP_GenerateFonts", GenerateFonts)

	-- FIX: Use the local function reference
	function GM:OnScreenSizeChanged()
		GenerateFonts()
	end
end

local online = Sound("friends/friend_online.wav")
local join = Sound("friends/friend_join.wav")
local message = Sound("friends/message.wav")

local stateSwitchFuncs = {
	[STATE_LOBBY] = function(gm)
		gm.GameOver = false
		gm.RoundSaved = false
	end,
	[STATE_PROMPT] = function(gm)
		if LocalPlayer():Team() == TEAM_SPECTATOR then return end

		gm:OnSpawnMenuClose()

		gm.MenuLock = true
		
		-- FIX: Explicitly close menu state before killing the screen
		-- This ensures the lobby menu is properly closed for non-host players
		local isFirstPrompt = GetRound() == 1
		if !isFirstPrompt then
			gm.MenuOpen = false
		end
		
		gm:KillMenuScreen(true)

		gm:CreatePromptScreen()
		
		-- For round 1, the prompt screen needs the menu open
		if isFirstPrompt then
			gm.MenuOpen = true
		end

		return online
	end,
	[STATE_BUILD] = function(gm)
		if LocalPlayer():Team() == TEAM_SPECTATOR then return end

		gm:ScoreboardHide()

		gm.MenuLock = true
		gm.MenuOpen = false
		gm:KillMenuScreen(GetRound() != 1)

		gm:CreateBuildText()

		return online
	end,
	[STATE_POST] = function(gm)
		gm.MenuLock = false
		gm.MenuOpen = false  -- FIX: Always start with menu closed
		gm:KillMenuScreen(true)

		gm.PostText = language.GetPhrase("GarryPhone.GameOver")
		if LocalPlayer():HasAuthority() then
			local tab = input.LookupBinding("+showscores") or "NOT BOUND (scoreboard)"
			gm.PostText = gm.PostText .. " " .. language.GetPhrase("GarryPhone.ViewResults"):format(tab)
		end

		gm.RoundData = {}

		gm.CurPly = nil
		gm.CurRound = nil
		gm.HighlightedPly = 1
		gm.AlbumText = language.GetPhrase("GarryPhone.Album"):format(Entity(1):Nick())
		gm.NextPly = false

		return join
	end
}

local infiniteTime
local rs, lastAlert
function GM:Think()
	local newrs = GetRoundState()

	if !infiniteTime then
		infiniteTime = GetConVar("gp_infinitetime")
	end

	if (newrs == STATE_PROMPT or newrs == STATE_BUILD) and !infiniteTime:GetBool() then
		local time = math.ceil(math.max(0, GetRoundTime() - CurTime()))
		if time <= 5 and time != 0 then
			if !lastAlert or time < lastAlert then
				surface.PlaySound(message)
				lastAlert = time
			end
		else
			lastAlert = 6
		end
	end

	if rs == newrs then return end

	rs = newrs

	self.Ready = false

	if IsValid(self.ReadyMark) then
		self.ReadyMark:Remove()
	end

	local fn = stateSwitchFuncs[rs]
	if !fn then return end

	local snd = fn(self)
	if !snd then return end

	surface.PlaySound(snd)
end

local function ReceivePrompt()
	local prompt = net.ReadString()
	prompt = prompt or ""

	local pnl = GAMEMODE.TextPanel
	if IsValid(pnl) and pnl.SetPlaceholderText then
		pnl:SetPlaceholderText(prompt)
	end

	GAMEMODE.CurPrompt = prompt
end
net.Receive("GP_SendPrompt", ReceivePrompt)

local function ShowResults()
	if GetRoundState() != STATE_POST then return end

	local gm = GAMEMODE
	gm.MenuOpen = net.ReadBool()

	if gm.MenuOpen then
		gm:CreateMenu()
		gm:CreatePostScreen()
	else
		gm:KillMenuScreen()
	end
end
net.Receive("GP_ShowResults", ShowResults)

function GM:SetMark(pos, y)
	local mark = self.ReadyMark

	if IsValid(mark) then
		mark:Remove()
	end

	mark = ClientsideModel("models/editor/playerstart.mdl")
	mark:SetPos(pos)
	mark:SetAngles(Angle(0, y, 0))
	mark:Spawn()

	self.ReadyMark = mark
end
net.Receive("GP_SetSpawn", function() GAMEMODE:SetMark(net.ReadVector(), net.ReadFloat()) end)

local function Ready()
	GAMEMODE.Ready = net.ReadBool()
end
net.Receive("GP_Ready", Ready)

local maxplybits = bitsRequired(game.MaxPlayers())
local function Reconnected()
	GAMEMODE.Playing = {}
	GAMEMODE.PlayerData = {}

	local numplys = net.ReadUInt(maxplybits)
	local ply, sid, nick
	for i = 1, numplys do
		if net.ReadBool() then -- it's me!
			ply = LocalPlayer()
			sid = ply:SteamID64()
			nick = ply:Nick()
		else
			ply = net.ReadPlayer()
			sid = net.ReadUInt64()
			nick = net.ReadString()
		end

		GAMEMODE.PlayerData[sid] = {ply = ply, name = nick}
		GAMEMODE.Playing[i] = sid
	end
end
net.Receive("GP_Reconnected", Reconnected)