-- The Shit List - end-of-run rating window. Pops up when you leave a dungeon/raid you
-- were grouped in for 10+ minutes (and /tsl rate brings it back). One row per player you
-- ran with: thumbs up / thumbs down for this run, plus "Tags..." for the full tag menu.
-- Plain frames + BackdropTemplate only (stock templates are unreliable on WoW Forever).

local ADDON, ns = ...

local ROWS, ROW_H, WIDTH = 10, 30, 470
local win
local rows = {}
local offset = 0
local currentRun
local members = {}

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function plainButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 22)
    b:SetBackdrop(BACKDROP)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.12)
    -- r,g,b = the colour it lights up in when selected
    function b:SetLit(on, r, g, bl)
        if on then
            self:SetBackdropColor(r * 0.45, g * 0.45, bl * 0.45, 0.95)
            self:SetBackdropBorderColor(r, g, bl, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
    end
    b:SetLit(false)
    return b
end

local function duration(run)
    local secs = (run.ended or time()) - run.start
    local mins = math.floor(secs / 60)
    if mins >= 60 then return math.floor(mins / 60) .. "h " .. (mins % 60) .. "m" end
    return mins .. " min"
end

local update -- forward

local function snapOf(m)
    return { guid = m.guid, name = m.name, realm = m.realm, class = m.class }
end

local function build()
    win = CreateFrame("Frame", "TheShitListRateWindow", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, ROWS * ROW_H + 112)
    win:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    win:SetBackdropColor(0.05, 0.05, 0.05, 0.94)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        ns.db.settings.rateWindow = { point = point, x = x, y = y }
    end)
    local pos = ns.db.settings.rateWindow
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        win:SetPoint("CENTER", 0, 80)
    end
    tinsert(UISpecialFrames, "TheShitListRateWindow")
    win:Hide()

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", 18, -16)
    win.title:SetPoint("RIGHT", -40, 0)
    win.title:SetJustifyH("LEFT")
    win.sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.sub:SetPoint("TOPLEFT", 18, -40)
    win.sub:SetPoint("RIGHT", -18, 0)
    win.sub:SetJustifyH("LEFT")

    local okClose, close = pcall(CreateFrame, "Button", nil, win, "UIPanelCloseButton")
    if not okClose or not close then close = plainButton(win, "X", 22, 22) end
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, win)
        row:SetSize(WIDTH - 32, ROW_H - 2)
        row:SetPoint("TOPLEFT", 16, -62 - (i - 1) * ROW_H)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(170)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.tally = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.tally:SetPoint("LEFT", 180, 0)

        row.tags = plainButton(row, "Tags...", 60)
        row.tags:SetPoint("RIGHT", -2, 0)
        row.down = plainButton(row, "|cffff6060-1|r", 40)
        row.down:SetPoint("RIGHT", row.tags, "LEFT", -6, 0)
        row.up = plainButton(row, "|cff60ff60+1|r", 40)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -4, 0)

        local function vote(v)
            if not row.member then return end
            if currentRun and currentRun.preview then
                -- preview: remember the click for the look of it, save nothing
                currentRun.votes[row.member.guid] = currentRun.votes[row.member.guid] ~= v and v or nil
            else
                ns.castVote(snapOf(row.member), v, currentRun)
            end
            update()
        end
        row.up:SetScript("OnClick", function() vote(1) end)
        row.down:SetScript("OnClick", function() vote(-1) end)
        row.tags:SetScript("OnClick", function(self)
            local m = row.member
            if not m or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            if currentRun and currentRun.preview then
                ns.say("preview only - these players aren't real, so there's nothing to tag.")
                return
            end
            local snap = snapOf(m)
            MenuUtil.CreateContextMenu(self, function(owner, root)
                root:CreateTitle(ns.classColored(m, ns.displayName(m)))
                ns.populateRatingMenu(root, snap, true)
            end)
        end)
        for _, b in ipairs({ row.up, row.down }) do
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self == row.up and "Thumbs up for this run" or "Thumbs down for this run")
                GameTooltip:AddLine("Click again to take it back.", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        rows[i] = row
    end

    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("BOTTOM", 0, 20)
    win.prevButton = plainButton(win, "Prev", 50)
    win.prevButton:SetPoint("BOTTOMLEFT", 16, 14)
    win.prevButton:SetScript("OnClick", function() offset = math.max(0, offset - ROWS); update() end)
    win.nextButton = plainButton(win, "Next", 50)
    win.nextButton:SetPoint("LEFT", win.prevButton, "RIGHT", 4, 0)
    win.nextButton:SetScript("OnClick", function() offset = offset + ROWS; update() end)

    local done = plainButton(win, "Done", 80, 24)
    done:SetPoint("BOTTOMRIGHT", -16, 14)
    done:SetScript("OnClick", function() win:Hide() end)
    local later = plainButton(win, "Later", 80, 24)
    later:SetPoint("RIGHT", done, "LEFT", -6, 0)
    later:SetScript("OnClick", function()
        win:Hide()
        ns.say("no problem - " .. "|cffffffff/tsl rate|r" .. " brings this back.")
    end)

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta) offset = offset - delta * 2; update() end)
end

function update()
    if not win or not currentRun then return end
    wipe(members)
    for guid, m in pairs(currentRun.members or {}) do
        m.guid = guid
        members[#members + 1] = m
    end
    table.sort(members, function(a, b) return (a.since or 0) < (b.since or 0) end)

    local maxOffset = math.max(0, #members - ROWS)
    offset = math.max(0, math.min(offset, maxOffset))

    local inProgress = not currentRun.ended
    win.title:SetText("|cffff5555How was|r " .. (currentRun.where or "that run") .. "|cffff5555?|r")
    win.sub:SetText(duration(currentRun) .. (inProgress and " so far" or "") .. "  -  " .. #members
        .. " player" .. (#members == 1 and "" or "s") .. "  -  +1 / -1 for this run, Tags... for details")

    local votes = currentRun.votes or {}
    for i, row in ipairs(rows) do
        local m = members[offset + i]
        row.member = m
        if m then
            local e = ns.players[m.guid]
            local brief = m.last and m.since and (m.last - m.since) < 120
            row.name:SetText(ns.classColored(m, m.name or "?") .. (brief and ns.color(ns.GREY, " (briefly)") or ""))
            local t = e and ns.isActive(e) and ns.tally(e) or ""
            row.tally:SetText(t ~= "" and t or ns.color(ns.GREY, "new"))
            local v = votes[m.guid]
            row.up:SetLit(v == 1, 0.3, 1, 0.3)
            row.down:SetLit(v == -1, 1, 0.3, 0.3)
            row:Show()
        else
            row:Hide()
        end
    end

    win.pageText:SetText(#members > ROWS and ((offset + 1) .. "-" .. math.min(offset + ROWS, #members) .. " of " .. #members) or "")
    win.prevButton:SetShown(offset > 0)
    win.nextButton:SetShown(offset < maxOffset)
end

-- /tsl ratepreview: the end-of-run window with made-up players, for checking the layout
-- without needing a dungeon group. Votes are kept inside the fake run, so nothing is saved.
ns.showRatePreview = function()
    local now = time()
    local fake = {
        id = "preview", key = "preview", where = "Wailing Caverns (preview)",
        start = now - 42 * 60, ended = now, votes = {}, preview = true,
        members = {
            ["preview-1"] = { name = "Kakinu", realm = "Indebols", class = "HUNTER", since = now - 42 * 60, last = now },
            ["preview-2"] = { name = "Seashells", realm = "Sunseam", class = "ROGUE", since = now - 40 * 60, last = now },
            ["preview-3"] = { name = "Adrix", realm = "First", class = "PALADIN", since = now - 39 * 60, last = now },
            ["preview-4"] = { name = "Latecomer", realm = "Joinedlate", class = "MAGE", since = now - 60, last = now },
        },
    }
    ns.showRate(fake)
end

ns.showRate = function(run)
    if not win then build() end
    currentRun = run
    offset = 0
    update()
    win:Show()
end

ns.hideRate = function()
    if win then win:Hide() end
end

-- votes or tags changed elsewhere (list window, right-click menu) - keep tallies current
local previousRefresh = ns.refresh
ns.refresh = function()
    if previousRefresh then previousRefresh() end
    if win and win:IsShown() then update() end
end
