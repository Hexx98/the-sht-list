-- The Shit List - group finder integration. Flags rated players in the group finder's
-- browse list (a ready-check icon + tally next to the leader's name) and adds a line to
-- the row's tooltip, so you can tell before you join or invite.
--
-- WoW Forever uses the Classic-style group finder (LFGParentFrame / LFGBrowseFrame),
-- loaded on demand. Scout-verified on build 69913: leaderName is plain (not secret) and
-- is the full "First Last" name; other members of a listed group have no name, only
-- class and role - so it's the leader (or the solo player listing themselves) we can
-- check. Entries carry no player GUID, so matching is by name: full name = exact; people
-- rated from chat before we knew their last name match by first name only ("maybe").

local ADDON, ns = ...

-- A thumbs up / thumbs down at a glance. Not every client ships the same art, so each
-- slot lists candidates best-first and the first one that actually resolves to a file is
-- used; the ready-check icons at the end always exist. ns.lfgIcons records the winners.
local function firstExistingTexture(candidates)
    local probe = UIParent:CreateTexture()
    for _, path in ipairs(candidates) do
        probe:SetTexture(path)
        local ok, id = pcall(probe.GetTextureFileID, probe)
        if ok and id then
            probe:SetTexture(nil)
            return path
        end
    end
    probe:SetTexture(nil)
    return nil
end

local ICON_SIZE = 16
local ICON = {}
do
    -- this client ships no thumbs art, so the addon brings its own (media\thumbs*.tga)
    local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
    local up = firstExistingTexture({
        MEDIA .. "thumbsup.tga",
        "Interface\\RaidFrame\\ReadyCheck-Ready",
    })
    local down = firstExistingTexture({
        MEDIA .. "thumbsdown.tga",
        "Interface\\RaidFrame\\ReadyCheck-NotReady",
    })
    local maybe = firstExistingTexture({ "Interface\\RaidFrame\\ReadyCheck-Waiting" })
    local function tex(path)
        return path and ("|T" .. path .. ":" .. ICON_SIZE .. ":" .. ICON_SIZE .. "|t") or ""
    end
    ICON.good, ICON.bad = tex(up), tex(down)
    ICON.mixed = tex(maybe)
    ICON.note = ICON.mixed
    ns.lfgIcons = { up = up or "none", down = down or "none", maybe = maybe or "none" }
    ns.thumbIcons = ICON -- shared with the end-of-run window's +1 / -1 buttons
end

local function plain(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- "Seashells Sunseam" (or "Seashells Sunseam-Server") -> entry, exact
local function findByFullName(full)
    if type(full) ~= "string" or full == "" then return nil end
    full = full:gsub("%-.*$", ""):lower()
    local first = full:match("^(%S+)") or full
    local maybe
    for _, e in pairs(ns.players or {}) do
        if ns.isActive(e) and e.name then
            local n = e.name:lower()
            if e.realm and (n .. " " .. e.realm:lower()) == full then return e, true end
            if not e.realm and n == first then maybe = e end
        end
    end
    if maybe then return maybe, false end
    return nil
end

-- Simple rule for the row icon: whichever side is ahead wins, ties get the question mark.
-- (The group-join warning uses the stricter "ahead by 2" rule; here you just want a
-- thumb at a glance.)
local function lfgVerdict(e)
    local good, bad = 0, 0
    for id in pairs(e.tags or {}) do
        local t = ns.TAG_BY_ID[id]
        if t then
            if t.bad then bad = bad + 1 else good = good + 1 end
        end
    end
    good, bad = good + (e.up or 0), bad + (e.down or 0)
    if good > bad then return "good" end
    if bad > good then return "bad" end
    return good == 0 and "note" or "mixed"
end

-- returns the leader's name and how many people are in that listing
local function leaderOf(resultID)
    if not (resultID and C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or type(info) ~= "table" or not plain(info.leaderName) then return nil end
    local n = plain(info.numMembers) and tonumber(info.numMembers) or 1
    return info.leaderName, n or 1
end

-- /tsl lfgpreview: show a sample marker on every row (display only, this session only)
local preview = false
local PREVIEW_ENTRY = { name = "Preview", tags = { asshole = true }, note = "preview only - not a real rating", up = 1, down = 3 }

local function lookup(leader)
    if not leader then return nil end
    if preview then return PREVIEW_ENTRY, true end
    return findByFullName(leader)
end

local function decorate(row)
    if type(row) ~= "table" or not row.GetRegions then return end
    local leader = leaderOf(row.resultID or row.TSLResultID)
    local e, exact = lookup(leader)
    if not e then
        if row.TSLMarker then row.TSLMarker:Hide() end
        return
    end
    if not row.TSLMarker then
        row.TSLMarker = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    local marker = row.TSLMarker
    -- icon only: thumbs up when they're net positive, thumbs down when net negative,
    -- question mark when it's even or there's only a note. Numbers live in the tooltip.
    marker:SetText(ICON[lfgVerdict(e)] .. (exact and "" or ns.color(ns.GREY, "?")))
    marker:ClearAllPoints()
    -- Sit just past the rightmost thing in the row (the role icons), measured rather than
    -- assumed: the row's layout isn't documented. Full-width pieces (background,
    -- highlight) are skipped so they don't count as "rightmost".
    local rowLeft, rowWidth = row:GetLeft(), row:GetWidth()
    local maxRight
    if rowLeft and rowWidth and rowWidth > 0 then
        -- Only visible leaves (icons and text) count. Containers are skipped: the role
        -- icons live in a frame that stretches to the row's right edge, and measuring
        -- that put the marker off the edge, where the list clipped it.
        local function consider(obj)
            if obj == marker or not obj.IsVisible or not obj:IsVisible() then return end
            local t = obj.GetObjectType and obj:GetObjectType()
            if t ~= "FontString" and t ~= "Texture" then return end
            local w, r = obj:GetWidth(), obj:GetRight()
            if w and r and w > 0 and w < rowWidth * 0.5 and (not maxRight or r > maxRight) then maxRight = r end
        end
        local function walk(frame, depth)
            for _, r in ipairs({ frame:GetRegions() }) do consider(r) end
            if depth < 3 then
                for _, child in ipairs({ frame:GetChildren() }) do
                    if child.IsVisible and child:IsVisible() then walk(child, depth + 1) end
                end
            end
        end
        walk(row, 0)
    end
    -- layout record for placing the marker (written once per session while previewing;
    -- saved with the character's data on /reload, read from the file - not shown in game)
    if preview and not ns.lfgLayoutRecorded and rowLeft and TheShtListBackup then
        ns.lfgLayoutRecorded = true
        local out = { rowWidth = rowWidth, rowHeight = row:GetHeight() }
        local function rec(obj, prefix)
            if obj == marker then return end
            local okN, name = pcall(obj.GetDebugName, obj)
            local left = obj:GetLeft()
            local line = prefix .. obj:GetObjectType() .. " " .. (okN and tostring(name) or "?")
                .. " x=" .. (left and math.floor(left - rowLeft + 0.5) or "?")
                .. " w=" .. math.floor((obj:GetWidth() or 0) + 0.5)
                .. " shown=" .. tostring(obj:IsShown())
            if obj.GetText then local okT, t = pcall(obj.GetText, obj); if okT and plain(t) then line = line .. " text=" .. tostring(t) end end
            if obj.GetAtlas then local okA, a = pcall(obj.GetAtlas, obj); if okA and a then line = line .. " atlas=" .. tostring(a) end end
            if obj.GetTexture then local okX, x = pcall(obj.GetTexture, obj); if okX and x then line = line .. " tex=" .. tostring(x) end end
            out[#out + 1] = line
        end
        for _, r in ipairs({ row:GetRegions() }) do rec(r, "") end
        for _, child in ipairs({ row:GetChildren() }) do
            rec(child, "")
            for _, r in ipairs({ child:GetRegions() }) do rec(r, "  ") end
            for _, gc in ipairs({ child:GetChildren() }) do rec(gc, "  ") end
        end
        out.chosenX = maxRight and math.floor(maxRight - rowLeft + 0.5) or "none"
        TheShtListBackup.lfgLayout = out
    end
    -- Right-aligned to the end of the row, so markers line up in a column down the list,
    -- but never closer than 10px to the role icons (which end at maxRight).
    local markerWidth = marker:GetStringWidth() or 0
    if rowWidth and rowWidth > 0 then
        local x = rowWidth - markerWidth - 5
        if maxRight and rowLeft then x = math.max(x, (maxRight - rowLeft) + 10) end
        marker:SetPoint("LEFT", row, "LEFT", x, 0)
    else
        marker:SetPoint("RIGHT", row, "RIGHT", -5, 0) -- not laid out yet
    end
    marker:Show()
end

-- The group finder's hover tooltip is a custom frame built from font strings, not a
-- GameTooltip, so there's no AddLine to call. Instead a small panel of our own is parked
-- directly under it and filled with the rating.
local function ratingPanel(tooltip)
    if tooltip.TSLPanel then return tooltip.TSLPanel end
    local panel = CreateFrame("Frame", nil, tooltip)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 0, -2)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.92)
    local border = panel:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.4, 0.4, 0.4, 0.9)
    bg:SetDrawLayer("BACKGROUND", 1)
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.text:SetPoint("TOPLEFT", 8, -6)
    panel.text:SetJustifyH("LEFT")
    panel.text:SetWidth(240)
    tooltip:HookScript("OnHide", function() panel:Hide() end)
    tooltip.TSLPanel = panel
    return panel
end

local function addTooltipLine(tooltip, resultID)
    if type(tooltip) ~= "table" or not tooltip.CreateFontString then return end
    local leader, numMembers = leaderOf(resultID)
    local e, exact = lookup(leader)
    local panel = ratingPanel(tooltip)
    if not e then panel:Hide() return end

    local v = lfgVerdict(e)
    local lines = {
        ICON[v] .. " " .. ns.color(ns.VERDICT_COLOR[v], "Sh*t List")
            .. (exact and "" or ns.color(ns.GREY, "  (matched by first name only)")),
        ns.describe(e),
    }
    if e.lastSeen then
        lines[#lines + 1] = ns.color(ns.GREY, "Last grouped " .. date("%b %d", e.lastSeen)
            .. (e.lastSeenWhere and (" in " .. e.lastSeenWhere) or ""))
    end
    if (numMembers or 1) > 1 then
        -- the game only names the leader of a listed group; the rest are class/role only
        lines[#lines + 1] = ns.color(ns.YELLOW, "This rating is for the group leader. The game doesn't name the other members.")
    end
    panel.text:SetText(table.concat(lines, "\n"))
    panel:SetWidth(math.max(tooltip:GetWidth() or 0, (panel.text:GetStringWidth() or 0) + 16))
    panel:SetHeight((panel.text:GetStringHeight() or 12) + 12)
    panel:Show()
end

-- The group finder UI loads on demand, so keep trying until its functions exist.
local hookedRows, hookedTooltip = false, false
local function tryHook()
    if not hookedRows and type(_G.LFGBrowseSearchEntry_Update) == "function" then
        hooksecurefunc("LFGBrowseSearchEntry_Update", function(row) pcall(decorate, row) end)
        if type(_G.LFGBrowseSearchEntry_Init) == "function" then
            -- remember the result ID Init was handed, in case the row doesn't store it
            -- under the key we expect
            hooksecurefunc("LFGBrowseSearchEntry_Init", function(row, data)
                if type(row) == "table" then
                    if type(data) == "number" then row.TSLResultID = data
                    elseif type(data) == "table" and type(data.resultID) == "number" then row.TSLResultID = data.resultID end
                end
                pcall(decorate, row)
            end)
        end
        hookedRows = true
    end
    if not hookedTooltip and type(_G.LFGBrowseSearchEntryTooltip_UpdateAndShow) == "function" then
        hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(tooltip, resultID)
            pcall(addTooltipLine, tooltip, resultID)
        end)
        hookedTooltip = true
    end
    return hookedRows and hookedTooltip
end

-- redraw visible rows (after preview toggles or list changes)
local function redraw()
    local box = _G.LFGBrowseFrameScrollBox
    if box and box.ForEachFrame then
        pcall(box.ForEachFrame, box, function(row) pcall(decorate, row) end)
    end
end

ns.lfgPreview = function()
    preview = not preview
    redraw()
    return preview, hookedRows, hookedTooltip
end

local previousRefresh = ns.refresh
ns.refresh = function()
    if previousRefresh then previousRefresh() end
    redraw()
end

-- Someone invites YOU: this client's group finder has no "apply to group" step (you get
-- invited directly with its Group Invite button), so the invite popup is where a warning
-- is actually useful - before you accept, rather than after you're already in the group.
local function onInvite(name)
    if not plain(name) or type(name) ~= "string" then return end
    local e, exact = findByFullName(name)
    if not e then return end
    local v = lfgVerdict(e)
    local label = (v == "bad" and ns.color(ns.RED, "WARNING") )
        or (v == "good" and ns.color(ns.GREEN, "Good news"))
        or ns.color(ns.YELLOW, "Heads up")
    ns.say(label .. ": " .. ns.classColored(e, ns.displayName(e)) .. " just invited you - "
        .. ns.describe(e) .. (exact and "" or ns.color(ns.GREY, " (matched by first name only)")))
    if ns.db and ns.db.settings and ns.db.settings.sound then
        pcall(PlaySound, v == "bad" and SOUNDKIT.RAID_WARNING or SOUNDKIT.READY_CHECK, "Master")
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PARTY_INVITE_REQUEST")
f:SetScript("OnEvent", function(self, event, ...)
    if event == "PARTY_INVITE_REQUEST" then
        pcall(onInvite, (...))
        return
    end
    if tryHook() then
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)
