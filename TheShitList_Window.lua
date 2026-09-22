-- The Shit List - list window (/tsl). Browse, filter, search and edit everyone you've rated.
-- Built from plain frames + BackdropTemplate only: several stock Blizzard templates are
-- missing on the WoW Forever beta, so nothing here depends on them (the close button tries
-- UIPanelCloseButton and falls back to a plain "X").

local ADDON, ns = ...

local ROWS, ROW_H, WIDTH = 12, 36, 580
local win
local rows = {}
local offset = 0
local filter = nil       -- nil = all, or "bad" / "good" / "mixed" / "note"
local search = ""
local sortMode = "name"  -- "name" / "seen" / "rated"
local results = {}

local SORT_LABEL = { name = "Sort: Name", seen = "Sort: Last grouped", rated = "Sort: Recently rated" }
local SORT_NEXT = { name = "seen", seen = "rated", rated = "name" }

local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function stripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ------------------------------------------------------------------ data
local function matches(e)
    if search == "" then return true end
    local hay = { (e.name or ""), (e.realm or ""), (e.note or ""), (e.lastSeenWhere or "") }
    for id in pairs(e.tags or {}) do
        local t = ns.TAG_BY_ID[id]
        if t then hay[#hay + 1] = t.text end
    end
    for _, h in ipairs(hay) do
        if h:lower():find(search, 1, true) then return true end
    end
    return false
end

local function collect()
    wipe(results)
    for guid, e in pairs(ns.players or {}) do
        if ns.isActive(e) and (not filter or ns.verdict(e) == filter) and matches(e) then
            results[#results + 1] = { guid = guid, e = e }
        end
    end
    table.sort(results, function(a, b)
        if sortMode == "seen" and (a.e.lastSeen or 0) ~= (b.e.lastSeen or 0) then
            return (a.e.lastSeen or 0) > (b.e.lastSeen or 0)
        elseif sortMode == "rated" and (a.e.updated or 0) ~= (b.e.updated or 0) then
            return (a.e.updated or 0) > (b.e.updated or 0)
        end
        return (a.e.name or ""):lower() < (b.e.name or ""):lower()
    end)
end

local function seenText(e)
    if not e.lastSeen then return ns.color(ns.GREY, "never grouped") end
    return ns.color(ns.GREY, "grouped " .. (e.timesSeen or 1) .. "x, last " .. date("%b %d", e.lastSeen)
        .. (e.lastSeenWhere and (" - " .. e.lastSeenWhere) or ""))
end

-- ------------------------------------------------------------------ widgets
local function plainButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height or 22)
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    b:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.12)
    function b:SetSelected(on)
        if on then
            self:SetBackdropColor(0.45, 0.1, 0.1, 0.95)
            self:SetBackdropBorderColor(1, 0.35, 0.35, 1)
        else
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
            self:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
        end
    end
    return b
end

local update -- forward

local function openRowMenu(row)
    local item = row.item
    if not item then return end
    local e = item.e
    local snap = { guid = item.guid, name = e.name, realm = e.realm, class = e.class }
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(row, function(owner, root)
            root:CreateTitle(ns.classColored(e, ns.displayName(e)))
            ns.populateRatingMenu(root, snap)
        end)
    else
        ns.say("this client has no MenuUtil.CreateContextMenu - can't edit from the window.")
    end
end

local function showRowTooltip(row)
    local item = row.item
    if not item then return end
    local e = item.e
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.classColored(e, ns.displayName(e)))
    local v = ns.verdict(e)
    GameTooltip:AddLine(ns.color(ns.VERDICT_COLOR[v], v:upper()))
    for _, t in ipairs(ns.TAGS) do
        if e.tags and e.tags[t.id] then
            GameTooltip:AddLine((t.bad and "- " or "+ ") .. t.text, t.bad and 1 or 0.3, t.bad and 0.3 or 1, 0.35)
        end
    end
    if e.note and e.note ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine('"' .. e.note .. '"', 1, 1, 1, true)
    end
    if e.history and #e.history > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Thumbs: +" .. (e.up or 0) .. " / -" .. (e.down or 0), 1, 0.82, 0)
        for i = #e.history, math.max(1, #e.history - 5), -1 do -- newest 6
            local h = e.history[i]
            GameTooltip:AddLine((h.vote == 1 and "+1  " or "-1  ") .. date("%b %d", h.t) .. "  " .. (h.where or "?"),
                h.vote == 1 and 0.4 or 1, h.vote == 1 and 1 or 0.4, 0.4)
        end
        if #e.history > 6 then GameTooltip:AddLine("...and " .. (#e.history - 6) .. " older", 0.6, 0.6, 0.6) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(stripColors(seenText(e)), 0.6, 0.6, 0.6)
    if e.added then GameTooltip:AddLine("First rated " .. date("%b %d %Y", e.added), 0.6, 0.6, 0.6) end
    if e.updated then GameTooltip:AddLine("Last changed " .. date("%b %d %Y", e.updated), 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("Click to edit", 0.4, 0.8, 1)
    GameTooltip:Show()
end

local function build()
    win = CreateFrame("Frame", "TheShitListWindow", UIParent, "BackdropTemplate")
    win:SetSize(WIDTH, ROWS * ROW_H + 118)
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
        ns.db.settings.window = { point = point, x = x, y = y }
    end)
    local pos = ns.db.settings.window
    if pos and pos.point then
        win:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        win:SetPoint("CENTER")
    end
    tinsert(UISpecialFrames, "TheShitListWindow") -- Escape closes it
    win:Hide()

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText("|cffff5555The Shit List|r")
    win.count = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.count:SetPoint("LEFT", title, "RIGHT", 10, -1)

    local okClose, close = pcall(CreateFrame, "Button", nil, win, "UIPanelCloseButton")
    if not okClose or not close then
        close = plainButton(win, "X", 22, 22)
    end
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)

    -- filter buttons
    local filters = { { nil, "All" }, { "bad", "Bad" }, { "good", "Good" }, { "mixed", "Mixed" }, { "note", "Notes only" } }
    win.filterButtons = {}
    local prev
    for _, fdef in ipairs(filters) do
        local b = plainButton(win, fdef[2], fdef[2] == "Notes only" and 80 or 56)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 16, -42) end
        b.value = fdef[1]
        b:SetScript("OnClick", function() filter = b.value; offset = 0; update() end)
        win.filterButtons[#win.filterButtons + 1] = b
        prev = b
    end

    win.sortButton = plainButton(win, SORT_LABEL[sortMode], 140)
    win.sortButton:SetPoint("TOPRIGHT", -16, -42)
    win.sortButton:SetScript("OnClick", function() sortMode = SORT_NEXT[sortMode]; offset = 0; update() end)

    -- search box
    local box = CreateFrame("EditBox", nil, win, "BackdropTemplate")
    box:SetSize(WIDTH - 32, 22)
    box:SetPoint("TOPLEFT", 16, -70)
    box:SetBackdrop(BACKDROP)
    box:SetBackdropColor(0, 0, 0, 0.8)
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(8, 8, 0, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(60)
    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 9, 0)
    hint:SetText("Search names, tags, notes, places...")
    box:SetScript("OnTextChanged", function(self)
        local t = self:GetText() or ""
        hint:SetShown(t == "")
        search = strtrim(t):lower()
        offset = 0
        update()
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    -- rows
    for i = 1, ROWS do
        local row = CreateFrame("Button", nil, win)
        row:SetSize(WIDTH - 32, ROW_H - 2)
        row:SetPoint("TOPLEFT", 16, -98 - (i - 1) * ROW_H)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.3, 0.3, 0.15)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 6, -3)
        row.name:SetJustifyH("LEFT")
        row.seen = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.seen:SetPoint("TOPRIGHT", -6, -5)
        row.seen:SetJustifyH("RIGHT")
        row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.detail:SetPoint("BOTTOMLEFT", 6, 4)
        row.detail:SetWidth(WIDTH - 48)
        row.detail:SetJustifyH("LEFT")
        row.detail:SetWordWrap(false)

        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetScript("OnClick", openRowMenu)
        row:SetScript("OnEnter", showRowTooltip)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end

    win.empty = win:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOP", 0, -140)
    win.empty:SetWidth(WIDTH - 60)

    -- paging
    win.pageText = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.pageText:SetPoint("BOTTOM", 0, 16)
    win.prevButton = plainButton(win, "Prev", 60)
    win.prevButton:SetPoint("BOTTOMLEFT", 16, 12)
    win.prevButton:SetScript("OnClick", function() offset = math.max(0, offset - ROWS); update() end)
    win.nextButton = plainButton(win, "Next", 60)
    win.nextButton:SetPoint("BOTTOMRIGHT", -16, 12)
    win.nextButton:SetScript("OnClick", function() offset = offset + ROWS; update() end)

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        update()
    end)
    win:SetScript("OnShow", function() update() end)
end

function update()
    if not win then return end
    collect()
    local maxOffset = math.max(0, #results - ROWS)
    offset = math.max(0, math.min(offset, maxOffset))

    local total = 0
    for _, e in pairs(ns.players or {}) do if ns.isActive(e) then total = total + 1 end end
    win.count:SetText(total .. " player" .. (total == 1 and "" or "s"))

    for _, b in ipairs(win.filterButtons) do b:SetSelected(b.value == filter) end
    win.sortButton.text:SetText(SORT_LABEL[sortMode])

    for i, row in ipairs(rows) do
        local item = results[offset + i]
        row.item = item
        if item then
            local e = item.e
            local v = ns.verdict(e)
            row.name:SetText(ns.classColored(e, ns.displayName(e)) .. "  " .. ns.color(ns.VERDICT_COLOR[v], "(" .. v .. ")"))
            row.seen:SetText(seenText(e))
            local d = ns.describe(e)
            row.detail:SetText(d ~= "" and d or ns.color(ns.GREY, "(no tags)"))
            row:Show()
        else
            row:Hide()
        end
    end

    if #results == 0 then
        if total == 0 then
            win.empty:SetText("Nobody on the list yet.\n\nRight-click any player (target, party or raid frame) and pick The Shit List to rate them.")
        else
            win.empty:SetText("No one matches that filter/search.")
        end
        win.empty:Show()
    else
        win.empty:Hide()
    end

    if #results > ROWS then
        win.pageText:SetText((offset + 1) .. "-" .. math.min(offset + ROWS, #results) .. " of " .. #results)
    else
        win.pageText:SetText("")
    end
    win.prevButton:SetShown(offset > 0)
    win.nextButton:SetShown(offset < maxOffset)
end

ns.refresh = function()
    if win and win:IsShown() then update() end
end

ns.toggleWindow = function()
    if not win then build() end
    if win:IsShown() then win:Hide() else win:Show() end
end
