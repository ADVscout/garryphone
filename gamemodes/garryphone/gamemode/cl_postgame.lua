function GM:CreatePostScreen()
    local plyPnl, replayPnl = self:TwoSidedMenu(true)
    self.PlyPnl = plyPnl
    self.ReplayPnl = replayPnl

    local authority = LocalPlayer():HasAuthority()
    if self.GameOver and authority then
        self:CreateEndButtons()
    end

    local curPly = self.NextPly and self.CurPly - 1 or self.CurPly
    if curPly then
        if !self.RoundData[curPly] then
            return
        end

        local roundData = self.RoundData[curPly]
        for i = 1, #roundData do
            local promptPnl = self:CreateReplayEntry(curPly, i)
            replayPnl:AddItem(promptPnl)
        end

        if !self.NextPly or !authority then
            return
        end

        self:CreateNextButton()

        return
    end

    if authority then
        local start = self:CreateMenuButton("#GarryPhone.Go")
        start.DoClick = function(s)
            if !self.MenuOpen then
                return
            end

            net.Start("GP_SendRound")
            net.SendToServer()

            s:Remove()
        end
    end
end

function GM:CreateReplayEntry(curPly, curRound)
    local rdata = self.RoundData[curPly][curRound]
    local author, data, isPrompt, instaReveal = rdata.author, rdata.data, rdata.prompt, rdata.revealed

    local scrw, scrh = ScrW(), ScrH()

    local dock = isPrompt and RIGHT or LEFT

    local promptPnl = vgui.Create("DPanel")
    promptPnl:SetTall(scrh * 0.1)
    promptPnl.Paint = nil

    local authorPnl = vgui.Create("DPanel", promptPnl)
    authorPnl:SetTall(scrh * 0.035)
    authorPnl:Dock(TOP)
    authorPnl:DockMargin(0, 0, 0, scrh * 0.01)
    authorPnl.Paint = nil

    local avPnl = vgui.Create("AvatarImage", authorPnl)
    avPnl:SetWide(scrh * 0.035)
    avPnl:Dock(dock)
    avPnl:SetPaintedManually(true)

    local authorValid = isentity(author)
    if authorValid then
        avPnl:SetPlayer(author, scrh * 0.035)
    end

    local authorTxt = vgui.Create("DLabel", authorPnl)
    authorTxt:SetAutoStretchVertical(true)
    authorTxt:Dock(dock)
    authorTxt:DockMargin(scrh * 0.01, 0, scrh * 0.01, 0)

    authorTxt:SetColor(color_white)
    authorTxt:SetFont("GPTargetID")
    -- Handle case where author entity becomes invalid (player disconnected)
    local authorName = authorValid and IsValid(author) and author:Nick() or tostring(author)
    authorTxt:SetText(authorName)
    authorTxt:SizeToContentsX()
    authorTxt:SetPaintedManually(true)

    authorPnl.Paint = function(s, w, h)
        avPnl:PaintManual()
        authorTxt:PaintManual()
    end

    local chatPnl = vgui.Create("DPanel", promptPnl)
    chatPnl:SetTall(scrh * 0.05)
    chatPnl:Dock(TOP)
    chatPnl.Paint = nil

    local chatBtn = vgui.Create("DButton", chatPnl)
    self.CurChat = chatBtn

    chatBtn:Dock(dock)
    chatBtn:SetWide(scrw * 0.055)

    chatBtn:SetFont("GPBoldSmall")
    chatBtn:SetText("")

    chatBtn.Ply = curPly
    chatBtn.Round = curRound

    local authority = LocalPlayer():HasAuthority()

    if instaReveal then
        chatBtn.Text = isPrompt and data or "(" .. language.GetPhrase("GarryPhone.BuildResult") .. ")"
    else
        chatBtn.Text = authority and language.GetPhrase("GarryPhone.Show") or "..."
        chatBtn.Data = isPrompt and data or "(" .. language.GetPhrase("GarryPhone.BuildResult") .. ")"
    end

    chatBtn.Paint = function(s, w, h)
        -- Simple rounded rectangle
        draw.RoundedBox(ScreenScaleH(8), 0, 0, w, h, color_white)

        if s.NoData then
            surface.SetTextColor(128, 128, 128, 255)
        else
            surface.SetTextColor(0, 0, 0, 255)
        end

        surface.SetFont(s:GetFont())

        local txt = chatBtn.Text
        local tx, ty = surface.GetTextSize(txt)

        w = tx + ScrW() * 0.01
        s:SetWide(w)

        surface.SetTextPos((w / 2) - (tx / 2), (h / 2) - (ty / 2))

        surface.DrawText(txt)
    end

    if !instaReveal and authority then
        local clickFunc = function(s)
            self:RevealPrompt(false, s)

            net.Start("GP_RevealPrompt")
            net.SendToServer()

            timer.Simple(
                3,
                function()
                    net.Start("GP_SendRound")
                    net.SendToServer()
                end
            )
        end

        chatBtn.DoClick = isPrompt and clickFunc or function(s)
                clickFunc()

                net.Start("GP_ShowResults")
                net.WriteBool(false)
                net.SendToServer()

                self.MenuOpen = false
                self:KillMenuScreen()
            end
    end

    return promptPnl
end

local ef2delay = 1 / 20
local function Effect2(pnl)
    if !pnl.LastChar then
        pnl.LastChar = ef2delay
        pnl.FullText = pnl.Text
        pnl.TextIndex = 0
        pnl.Text = ""
    end

    if pnl.LastChar > 0 then
        pnl.LastChar = pnl.LastChar - RealFrameTime()

        return
    end

    pnl.TextIndex = pnl.TextIndex + 1
    pnl.Text = pnl.FullText:sub(1, pnl.TextIndex)

    if pnl.TextIndex >= pnl.FullText:len() then
        pnl.Think = nil

        return
    end

    pnl.LastChar = ef2delay
end

function GM:RevealPrompt(nextPly, pnl)
    pnl = pnl or self.CurChat

    if nextPly then
        local parent = self.ReplayPnl

        parent:Clear()

        local curPly = self.CurPly
        local plys = self.PlyPnl:GetItems()
        plys[curPly - 1].Highlighted = false
        plys[curPly].Highlighted = true
        self.HighlightedPly = curPly
        self.AlbumText = language.GetPhrase("GarryPhone.Album"):format(plys[curPly].Text)

        parent:AddItem(self:CreateReplayEntry(curPly, 1))

        self.NextPly = false

        return
    end

    local rdata = self.RoundData[pnl.Ply][pnl.Round]
    if rdata.prompt then
        if pnl.Data then
            pnl.Text = pnl.Data
        else
            pnl.Text = "(" .. language.GetPhrase("GarryPhone.NoResult") .. ")"
            pnl.NoData = true
        end

        pnl.Think = function(s)
            Effect2(s)
        end
        pnl.DoClick = function()
        end
    end

    rdata.revealed = true
end
net.Receive(
    "GP_RevealPrompt",
    function()
        GAMEMODE:RevealPrompt(net.ReadBool())
    end
)

function GM:CreateNextButton()
    local parent = self.ReplayPnl
    if !IsValid(parent) then
        return
    end

    local nextPly = self:CreateMenuButton("#GarryPhone.Next")
    nextPly.DoClick = function(s)
        parent:Clear()

        local plyPnls = self.PlyPnl:GetItems()
        plyPnls[self.CurPly - 1].Highlighted = false
        plyPnls[self.CurPly].Highlighted = true
        self.HighlightedPly = self.CurPly
        self.AlbumText = language.GetPhrase("GarryPhone.Album"):format(plyPnls[self.CurPly].Text)

        parent:AddItem(self:CreateReplayEntry(self.CurPly, 1))

        self.NextPly = false

        net.Start("GP_RevealPrompt")
        net.SendToServer()

        s:Remove()
    end
end

function GM:CreateEndButtons()
    local endGame = self:CreateMenuButton("#GarryPhone.End")
    endGame.DoClick = function(s)
        net.Start("GP_BackToLobby")
        net.SendToServer()

        net.Start("GP_ShowResults")
        net.WriteBool(false)
        net.SendToServer()

        self.MenuOpen = false
        self:KillMenuScreen()
    end

    local txt = self.RoundSaved and "#GarryPhone.Saved" or "#GarryPhone.Save"
    local saveGame = self:CreateMenuButton(txt, ScrW() * 0.65, self.RoundSaved)

    if !self.RoundSaved then
        saveGame.DoClick = function(s)
            net.Start("GP_SaveGame")
            net.SendToServer()

            s:Remove()

            self:CreateMenuButton("#GarryPhone.Saved", ScrW() * 0.65, true)

            self.RoundSaved = true
        end
    end
end

local function bitsRequired(num)
    local bits, max = 0, 1

    while max <= num do
        bits = bits + 1
        max = max + max
    end

    return bits
end

local plyBits = bitsRequired(game.MaxPlayers())

local function ReceiveRound()
    local gm = GAMEMODE
    local parent = gm.ReplayPnl

    local curPly = net.ReadUInt(plyBits)
    local curRound = net.ReadUInt(plyBits)

    local roundType = net.ReadUInt(2)
    if roundType == STATE_POST then
        gm.GameOver = true

        if LocalPlayer():HasAuthority() and IsValid(parent) then
            gm:CreateEndButtons()
        end

        return
    end

    gm.CurPly = curPly
    gm.CurRound = curRound

    local author = net.ReadBool() and net.ReadPlayer() or net.ReadString()

    local isPrompt = roundType == STATE_PROMPT

    local data
    if net.ReadBool() and isPrompt then
        data = net.ReadString()
    end

    local roundData = gm.RoundData
    if !roundData[curPly] then
        roundData[curPly] = {}
    end

    roundData[curPly][gm.CurRound] = {
        author = author,
        data = data or "(" .. language.GetPhrase("GarryPhone.NoResult") .. ")",
        prompt = isPrompt,
        revealed = false
    }

    local authority = LocalPlayer():HasAuthority()
    if !isPrompt then
        author = isentity(author) and author:Nick() or author
        gm.PostText = language.GetPhrase("GarryPhone.BuiltBy"):format(author)

        if authority then
            local tab = input.LookupBinding("+showscores") or "NOT BOUND (scoreboard)"
            gm.PostText = gm.PostText .. " " .. language.GetPhrase("GarryPhone.ViewResults"):format(tab)
        end
    end

    if gm.CurRound == 1 and curPly != 1 then
        gm.NextPly = true

        if authority then
            gm:CreateNextButton()
        end

        return
    end

    if !IsValid(parent) then
        return
    end

    parent:AddItem(gm:CreateReplayEntry(gm.CurPly, gm.CurRound))
end
net.Receive("GP_SendRound", ReceiveRound)

local function ShowBuild()
    local idx = net.ReadUInt(MAX_EDICT_BITS)
    if !isnumber(idx) then
        return
    end

    local ent = Entity(idx)
    if !IsValid(ent) then
        return
    end

    local gm = GAMEMODE
    gm.RoundData[gm.CurPly][gm.CurRound].data = ent
end
net.Receive("GP_ShowBuild", ShowBuild)