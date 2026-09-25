-- The Shit List (WoW Forever) - by Hexx
-- Rate the players you group with. Right-click a player (party/raid frame, target, focus)
-- -> "The Sh*t List" -> tick canned good/bad tags and/or add a note. Whenever someone on
-- the list is in your group (you join theirs, or they join yours) you get a warning -
-- or a heads-up that the rockstar tank from last week is back. Only YOU see any of it;
-- nothing is ever sent to party/raid chat.
--
-- Players are keyed by GUID (stable per character; scout-verified readable and plain -
-- not secret - for other players even in combat on WoW Forever build 69913).

local ADDON, ns = ... -- ns = private table shared with TheShtList_Window.lua

-- ------------------------------------------------------------------ canned tags
-- id = what's saved (never rename one, or existing ratings lose it); text = what's shown
local TAGS = {
    -- the id is what's saved, so ratings made before this was reworded still show up.
    -- The label is deliberately publishable: CurseForge bars profanity inside mods too.
    { id = "asshole",  text = "Total jerk",                 bad = true },
    { id = "baddps",   text = "Terrible damage",            bad = true },
    { id = "badheal",  text = "Bad healer",                 bad = true },
    { id = "badtank",  text = "Bad tank",                   bad = true },
    { id = "pulls",    text = "Pulls everything",           bad = true },
    { id = "nolisten", text = "Doesn't listen",             bad = true },
    { id = "ninja",    text = "Ninja looter",               bad = true },
    { id = "quitter",  text = "Leaves mid-run",             bad = true },
    { id = "afk",      text = "AFK / leecher",              bad = true },

    { id = "goodheal", text = "Great healer" },
    { id = "goodtank", text = "Great tank" },
    { id = "gooddps",  text = "Great damage" },
    { id = "class",    text = "Plays their class well" },
    { id = "fun",      text = "Friendly / fun to group with" },
    { id = "leader",   text = "Good leader" },
    { id = "fairloot", text = "Fair with loot" },
}
local TAG_BY_ID = {}
for _, t in ipairs(TAGS) do TAG_BY_ID[t.id] = t end

local RED, GREEN, YELLOW, GREY = "ffff4040", "ff40ff60", "ffffd040", "ff9d9d9d"
local PREFIX = "|cffff5555The Sh*t List:|r "
local function say(msg) DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg) end
local function color(hex, text) return "|c" .. hex .. text .. "|r" end

-- On WoW Forever the "realm" shown for a player you target is really a last name
-- ("Cordelia Mendenhall"), while lookups that don't go through a unit (chat names,
-- GetPlayerInfoByGUID) give the server instead ("ClassicBetaPvE2") - the same for
-- thousands of people, so it's useless as a name. Keep last names, drop server names.
local function realOrNil(realm)
    if type(realm) ~= "string" or realm == "" then return nil end
    if realm:find("^ClassicBeta") or realm == GetRealmName() or realm == GetNormalizedRealmName() then return nil end
    return realm
end

-- Set when the safety net (see "load check" below) finds the saved list failed to load.
-- While set, every edit is refused: the list on screen is empty and isn't the real one.
local loadFailed = false
local function editsBlocked()
    if not loadFailed then return false end
    say(color(RED, "rating is paused") .. " - your saved list didn't load this session (WoW Forever beta bug). /tsl help for details.")
    return true
end

-- ------------------------------------------------------------------ saved data
local db, players

local function copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = copy(v) end
    return c
end

-- Keep whichever copy of each player was changed most recently. Removals are kept as
-- "removed" tombstones (not deleted) so an older backup can't bring someone back.
local function merge(into, from)
    local restored = 0
    for key, theirs in pairs(from or {}) do
        local mine = into[key]
        if type(theirs) == "table" and (not mine or (theirs.updated or 0) > (mine.updated or 0)) then
            into[key] = copy(theirs)
            restored = restored + 1
        end
    end
    return restored
end

-- macroBackup: mirror the list into hidden macros, which live on Blizzard's servers and
-- so survive the beta bug that stops saved variables loading (see TheShtList_Macro.lua).
-- Off by default: it's an emergency option, offered by the "didn't load" popup, rather
-- than something that quietly fills everyone's macro list.
local DEFAULTS = { banner = true, sound = true, announceGood = true, macroBackup = false }

local function initDB()
    TheShtListDB = TheShtListDB or {}
    db = TheShtListDB
    db.players = db.players or {}
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do
        if db.settings[k] == nil then db.settings[k] = v end
    end
    players = db.players
    ns.db, ns.players = db, players
    -- v0.5.0 briefly saved chat-rated players' server as their last name
    for _, e in pairs(players) do
        if type(e) == "table" and e.realm and not realOrNil(e.realm) then e.realm = nil end
    end

    -- Account-wide saved files have failed to load on this beta before. If that ever
    -- happens, this character's backup refills the list instead of it being wiped.
    TheShtListBackup = TheShtListBackup or {}
    local restored = merge(players, TheShtListBackup.players)
    if restored > 0 and TheShtListBackup.players and next(TheShtListBackup.players) then
        -- normal after rating people on another character; only worth saying if big
        if restored >= 5 then say("restored " .. restored .. " entries from this character's backup.") end
    end
end

local function saveBackup()
    if players then TheShtListBackup.players = copy(players) end
end

-- ------------------------------------------------------------------ entry helpers
local function isActive(e)
    return e and not e.removed and (next(e.tags or {}) ~= nil or (e.note and e.note ~= "")
        or (e.up or 0) > 0 or (e.down or 0) > 0)
end

local function counts(e)
    local good, bad = 0, 0
    for id in pairs(e.tags or {}) do
        local t = TAG_BY_ID[id]
        if t then
            if t.bad then bad = bad + 1 else good = good + 1 end
        end
    end
    return good, bad
end

-- "bad" / "good" / "mixed" / "note". Tags and thumbs both count; when someone has some
-- of each, whichever side is ahead by 2+ wins (so "gave them a second chance, they blew
-- it again" tips them to bad, and one off night doesn't sink a proven player).
local function verdict(e)
    local goodTags, badTags = counts(e)
    local good, bad = goodTags + (e.up or 0), badTags + (e.down or 0)
    if bad > 0 and good == 0 then return "bad" end
    if good > 0 and bad == 0 then return "good" end
    if good > 0 and bad > 0 then
        if good - bad >= 2 then return "good" end
        if bad - good >= 2 then return "bad" end
        return "mixed"
    end
    return "note"
end
local VERDICT_COLOR = { bad = RED, good = GREEN, mixed = YELLOW, note = YELLOW }

local function tally(e)
    local up, down = e.up or 0, e.down or 0
    if up == 0 and down == 0 then return "" end
    return color(GREEN, "+" .. up) .. color(GREY, "/") .. color(RED, "-" .. down)
end

local function describe(e)
    local parts = {}
    local t = tally(e)
    if t ~= "" then parts[1] = t end
    for _, t in ipairs(TAGS) do -- in TAGS order so bad tags come first
        if e.tags and e.tags[t.id] then parts[#parts + 1] = color(t.bad and RED or GREEN, t.text) end
    end
    local s = table.concat(parts, ", ")
    if e.note and e.note ~= "" then
        s = s .. (s ~= "" and " - " or "") .. color("ffffffff", '"' .. e.note .. '"')
    end
    return s
end

local function classColored(e, text)
    local c = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
    if c and c.colorStr then return "|c" .. c.colorStr .. text .. "|r" end
    return text
end

local function displayName(e)
    local n = e.name or "?"
    if e.realm and e.realm ~= "" then n = n .. "-" .. e.realm end
    return n
end

-- who a unit is right now, grabbed immediately (the unit token can point at someone
-- else by the time a menu option is clicked, e.g. after a target change)
local function snapshot(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return nil end
    local guid = UnitGUID(unit)
    if not guid then return nil end
    local name, realm = UnitFullName(unit)
    if not name then name, realm = UnitName(unit) end
    local _, class = UnitClass(unit)
    return { guid = guid, name = name, realm = realm, class = class }
end

local function entryFor(snap, create)
    local e = players[snap.guid]
    if not e and create then
        e = { tags = {}, added = time() }
        players[snap.guid] = e
    end
    if e then
        if e.removed and create then
            e.removed, e.tags, e.note, e.up, e.down, e.history = nil, {}, nil, nil, nil, nil
        end
        e.name, e.class = snap.name or e.name, snap.class or e.class
        if realOrNil(snap.realm) then e.realm = snap.realm end -- fills in the last name when seen as a unit
    end
    return e
end

local announced = {} -- guid -> signature already announced for the current group
local function signature(e)
    local ids = {}
    for id in pairs(e.tags or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",") .. "|" .. (e.note or "") .. "|" .. (e.up or 0) .. "|" .. (e.down or 0)
end

local groupUnits -- defined below

local function inMyGroup(guid)
    if not IsInGroup() then return false end
    for _, unit in ipairs(groupUnits()) do
        if UnitGUID(unit) == guid then return true end
    end
    return false
end

local function notify() -- tell the list window (if open) that something changed
    if ns.refresh then ns.refresh() end
end

local function changed(snap, e)
    e.updated = time()
    notify()
    -- rating someone who's already IN your group: don't immediately "warn" you about the
    -- person you just rated. Anyone else must stay un-announced, so they trigger the
    -- warning when they join (v0.1.0 bug: rating a world player then inviting them = silent).
    if inMyGroup(snap.guid) and isActive(e) then
        announced[snap.guid] = signature(e)
    else
        announced[snap.guid] = nil
    end
end

local function toggleTag(snap, id)
    if editsBlocked() then return end
    local e = entryFor(snap, true)
    e.tags[id] = (not e.tags[id]) or nil
    changed(snap, e)
    if isActive(e) then
        say(classColored(e, displayName(e)) .. ": " .. describe(e))
    else
        say(classColored(e, displayName(e)) .. " no longer has any ratings.")
    end
end

local function setNote(snap, text)
    if editsBlocked() then return end
    text = text and strtrim(text) or ""
    local e = entryFor(snap, text ~= "")
    if not e then return end
    e.note = text ~= "" and text or nil
    changed(snap, e)
    say(classColored(e, displayName(e)) .. (isActive(e) and (": " .. describe(e)) or ": note cleared."))
end

local function removeEntry(guid)
    if editsBlocked() then return end
    local e = players[guid]
    if not e then return end
    e.removed, e.tags, e.note, e.updated = time(), {}, nil, time()
    e.up, e.down, e.history = nil, nil, nil
    announced[guid] = nil
    say(classColored(e, displayName(e)) .. " removed from the list.")
    notify()
end

local function whereAmI()
    local name, itype = GetInstanceInfo()
    if itype and itype ~= "none" and name then return name end
    return GetRealZoneText and GetRealZoneText() or name or "?"
end

-- ------------------------------------------------------------------ thumbs up / down
-- A running tally (e.up / e.down) plus a history of individual votes (when + where), so
-- "gave them a second chance and they blew it again" shows up as two separate examples.
local HISTORY_MAX = 30

-- v = 1 (thumbs up) or -1 (thumbs down). With a run, it's one vote per player per run:
-- clicking the same thumb again takes it back, clicking the other one switches it.
-- Without a run (the right-click menu) every click is a new vote.
local function castVote(snap, v, run)
    if editsBlocked() then return end
    local e = entryFor(snap, true)
    e.history = e.history or {}
    if run then
        run.votes = run.votes or {}
        local old = run.votes[snap.guid]
        if old then
            if old == 1 then e.up = math.max(0, (e.up or 0) - 1) else e.down = math.max(0, (e.down or 0) - 1) end
            for i = #e.history, 1, -1 do
                if e.history[i].run == run.id then table.remove(e.history, i) end
            end
        end
        if old == v then v = nil end
        run.votes[snap.guid] = v
    end
    if v then
        if v == 1 then e.up = (e.up or 0) + 1 else e.down = (e.down or 0) + 1 end
        e.history[#e.history + 1] = {
            t = run and run.start or time(),
            where = run and run.where or whereAmI(),
            vote = v,
            run = run and run.id or nil,
        }
        while #e.history > HISTORY_MAX do table.remove(e.history, 1) end
    end
    changed(snap, e)
    if not run then
        say(classColored(e, displayName(e)) .. ": " .. describe(e))
    end
end

local function resetVotes(snap)
    if editsBlocked() then return end
    local e = players[snap.guid]
    if not e then return end
    e.up, e.down, e.history = nil, nil, nil
    changed(snap, e)
    say(classColored(e, displayName(e)) .. ": thumbs up/down reset.")
end

-- ------------------------------------------------------------------ note popup
local function popupEditBox(self)
    return self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
end
local function acceptNote(popup)
    local data = popup.data
    local eb = popupEditBox(popup)
    if data and eb then setNote(data, eb:GetText()) end
end
StaticPopupDialogs.THESHITLIST_NOTE = {
    text = "Sh*t List note for %s:",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 200,
    editBoxWidth = 280,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self, data)
        data = data or self.data
        local eb = popupEditBox(self)
        local e = data and players[data.guid]
        if eb then
            eb:SetText(e and not e.removed and e.note or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self) acceptNote(self) end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        acceptNote(popup)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function editNote(snap)
    local dialog = StaticPopup_Show("THESHITLIST_NOTE", snap.name or "?", nil, snap)
    if dialog then dialog.data = snap end
end

-- ------------------------------------------------------------------ load check (safety net)
-- WoW Forever beta build 69913 writes SavedVariables to disk but often never reads them
-- back in. When that happens the list starts empty, and logging out then writes the
-- empty list over the real one. Tested: an addon can't stop that write (even a nil
-- variable gets written as "= nil"). What it CAN do is notice and say so.
--
-- WoW's layout cache (where you dragged named frames) is unaffected by the bug, so an
-- invisible named frame's position is used as a marker holding how many players the
-- list had at the last logout. Marker says 12 but the list came back empty = the load
-- failed. The layout cache is per character and rounds to whole numbers:
--   x = (count % 1000) - 500, y = 200 + floor(count / 1000)
local canary = CreateFrame("Frame", "TheShtListLoadMarker", UIParent)
canary:SetSize(1, 1)
canary:SetAlpha(0)
canary:EnableMouse(false)
canary:SetMovable(true) -- required for WoW to remember its position

local markedCount    -- what the marker said at login (nil = no marker yet)
local checkDone = false

local function entryCount()
    local n = 0
    for _ in pairs(players or {}) do n = n + 1 end -- tombstones count too: they're saved data
    return n
end

local function readMarker()
    if canary:GetNumPoints() == 0 then return nil end
    local _, _, _, x, y = canary:GetPoint(1)
    if not (x and y) then return nil end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if x < -500 or x > 499 or y < 200 or y > 400 then return nil end
    return (y - 200) * 1000 + (x + 500)
end

local function writeMarker(count)
    canary:ClearAllPoints()
    canary:SetPoint("CENTER", UIParent, "CENTER", (count % 1000) - 500, 200 + math.floor(count / 1000))
    canary:SetUserPlaced(true)
end

StaticPopupDialogs.THESHITLIST_LOADFAIL = {
    text = "|cffff5555The Sh*t List|r\n\nYour saved list (%s players) didn't load this session.\n\n"
        .. "This is a known WoW Forever beta bug (the game saves addon data but doesn't read it back), "
        .. "not a problem with the addon.\n\nRating is paused this session so nothing new gets mixed up with it.\n\n"
        .. "To get it back: quit the game completely, then in\nWTF\\Account\\<account>\\SavedVariables\n"
        .. "rename TheShtList.lua.bak to TheShtList.lua (it usually still has your list), "
        .. "or install ForeverSVFix, which fixes this for every addon.\n\n"
        .. "(The addon also keeps a backup in hidden macros, which survives this bug. It had "
        .. "nothing to restore this time - it starts saving from now on, so a future failure "
        .. "should recover by itself. /tsl macrobackup)\n\n"
        .. "Starting a new list on purpose? Type /tsl startfresh",
    button1 = OKAY or "OK",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function showLoadFailPopup()
    StaticPopup_Show("THESHITLIST_LOADFAIL", tostring(markedCount or "?"))
end

local function checkLoad()
    if checkDone then return end
    local marked = readMarker()
    if marked == nil then return end -- layout cache not applied yet (or first use)
    checkDone = true
    markedCount = marked
    if marked > 0 and entryCount() == 0 then
        -- the saved file didn't load: rebuild from the macro mirror before giving up
        if ns.restoreFromMacros then
            local restored = ns.restoreFromMacros()
            if restored and restored > 0 then
                say(color(GREEN, "restored " .. restored .. " player(s) from the macro backup")
                    .. " - the saved file didn't load (WoW Forever beta bug), so the built-in backup was used instead.")
                markedCount = entryCount()
                notify()
                return
            end
        end
        loadFailed = true
        say(color(RED, "your saved list (" .. marked .. " players) didn't load") .. " - known WoW Forever beta bug. Rating is paused this session. /tsl help for how to get it back.")
        showLoadFailPopup()
        notify()
    end
end

-- ------------------------------------------------------------------ right-click menu
local MENU_TAGS = {
    "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_RAID", "MENU_UNIT_PLAYER",
    "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS", "MENU_UNIT_FRIEND", "MENU_UNIT_ENEMY_PLAYER",
    -- names clicked in chat and in guild/community/chat-channel rosters
    "MENU_UNIT_CHAT_ROSTER", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
    "MENU_UNIT_COMMUNITIES_MEMBER", "MENU_UNIT_COMMUNITIES_WOW_MEMBER",
}

-- the tag checkboxes / note / remove items; used by the unit right-click submenu and by
-- the list window's row menu (snap = { guid, name, realm, class }). noVotes: leave out the
-- thumbs (the end-of-run window has its own per-run thumbs buttons).
local function populateRatingMenu(sub, snap, noVotes)
    if loadFailed then
        sub:CreateTitle(color(RED, "Your list didn't load - rating paused"))
        sub:CreateButton("What happened?", showLoadFailPopup)
        return
    end
    local e = players[snap.guid]
    if not noVotes then
        local t = isActive(e) and tally(e) or ""
        sub:CreateTitle("Thumbs" .. (t ~= "" and ("  " .. t) or ""))
        sub:CreateButton(color(GREEN, "Thumbs up (+1)"), function() castVote(snap, 1) end)
        sub:CreateButton(color(RED, "Thumbs down (-1)"), function() castVote(snap, -1) end)
        if e and ((e.up or 0) > 0 or (e.down or 0) > 0) then
            sub:CreateButton(color(GREY, "Reset thumbs"), function() resetVotes(snap) end)
        end
        sub:CreateDivider()
    end
    local function hasTag(id)
        local cur = players[snap.guid]
        return cur and not cur.removed and cur.tags and cur.tags[id] or false
    end
    local function addGroup(title, wantBad)
        sub:CreateTitle(title)
        for _, t in ipairs(TAGS) do
            if (t.bad or false) == wantBad then
                sub:CreateCheckbox(color(wantBad and RED or GREEN, t.text),
                    function() return hasTag(t.id) end,
                    function() toggleTag(snap, t.id) end)
            end
        end
    end
    addGroup("Bad", true)
    sub:CreateDivider()
    addGroup("Good", false)
    sub:CreateDivider()
    sub:CreateButton((e and e.note and not e.removed) and "Edit note..." or "Add note...", function() editNote(snap) end)
    if isActive(e) then
        sub:CreateButton(color(GREY, "Remove from list"), function() removeEntry(snap.guid) end)
    end
end

-- a value we can actually use (not nil, not a WoW Forever secret value)
local function plain(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

-- Names clicked in chat (and guild/community rosters) aren't units, so there's no unit
-- token to read a GUID from. Try, in order: a GUID the menu passes directly, the chat
-- line's sender GUID, and finally someone already on the list with that name.
local function snapshotFromName(ctx)
    local guid = plain(ctx.guid) and type(ctx.guid) == "string" and ctx.guid or nil
    if not guid and plain(ctx.lineID) and C_ChatInfo and C_ChatInfo.GetChatLineSenderGUID then
        local ok, g = pcall(C_ChatInfo.GetChatLineSenderGUID, ctx.lineID)
        if ok and plain(g) and type(g) == "string" and g ~= "" then guid = g end
    end
    local name = plain(ctx.name) and ctx.name or nil
    local realm = plain(ctx.server) and ctx.server or nil
    if name and not realm and name:find("-", 1, true) then name, realm = name:match("^(.-)%-(.+)$") end
    realm = realOrNil(realm)

    if guid and guid:find("^Player%-") then
        if guid == UnitGUID("player") then return nil end
        local class, gname
        if GetPlayerInfoByGUID then
            -- its realm return is deliberately ignored: on WoW Forever it's the server
            -- (e.g. "ClassicBetaPvE2"), not the "last name" the game shows for units
            local ok, _, c, _, _, _, n = pcall(GetPlayerInfoByGUID, guid)
            if ok then
                class = plain(c) and c or nil
                gname = plain(n) and n or nil
            end
        end
        return { guid = guid, name = gname or name, realm = realm, class = class }
    end

    -- no GUID: fall back to someone already on the list with this name
    if name then
        local want = name:lower()
        for g, e in pairs(players) do
            if not e.removed and (e.name or ""):lower() == want
                and (not realm or not e.realm or e.realm:lower() == realm:lower()) then
                return { guid = g, name = e.name, realm = e.realm, class = e.class }
            end
        end
    end
    return nil
end

local function describeContext(ctx) -- for the "can't identify" menu: what did the game give us?
    local parts = {}
    for k, v in pairs(ctx or {}) do
        parts[#parts + 1] = tostring(k) .. "=" .. (plain(v) and tostring(v) or "<secret>")
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- our own context menu, opened from the unit menu (see the comment in buildMenu)
local function openRatingMenu(snap, owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        say("this client can't open context menus - use /tsl instead.")
        return
    end
    local anchor = (owner and owner.GetName and owner:GetName() and owner) or UIParent
    -- next frame, so Blizzard's menu has finished closing
    C_Timer.After(0, function()
        local e = players[snap.guid]
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle(classColored(e or snap, displayName(e or snap)))
            populateRatingMenu(root, snap)
        end)
    end)
end

local lastRoot -- a menu could match two tags; only add our section once
local function buildMenu(owner, root, ctx, tag)
    if root == lastRoot then return end
    ctx = ctx or {}
    local snap = snapshot(ctx.unit)
    if not snap and not ctx.unit then
        snap = snapshotFromName(ctx)
        if not snap then
            -- a name we couldn't pin to a character: say so rather than silently vanish
            if not plain(ctx.name) or ctx.name == UnitName("player") then return end
            lastRoot = root
            root:CreateDivider()
            root:CreateButton(color(GREY, "The Sh*t List: can't identify this player"), function()
                say("can't tell who that is from here - target them or right-click their portrait instead.")
                say("menu " .. tostring(tag) .. ": " .. describeContext(ctx))
                return MenuResponse and MenuResponse.Close
            end)
            return
        end
    end
    if not snap then return end
    lastRoot = root

    local e = players[snap.guid]
    local label = "The Sh*t List"
    if isActive(e) then
        local v = verdict(e)
        label = label .. "  " .. color(VERDICT_COLOR[v], "(" .. v .. ")")
    end

    root:CreateDivider()
    -- One plain entry that closes Blizzard's menu and opens ours.
    --
    -- The tags used to be a submenu here, but picking anything in it made Blizzard's menu
    -- re-evaluate its own entries (Trade, Follow, Duel...) in an execution path our code
    -- had touched, and those entries need protected calls - producing
    -- "AddOn 'TheShtList' tried to call the protected function 'CheckInteractDistance()'".
    -- Our own menu contains only our items, so nothing protected is re-checked.
    root:CreateButton(label, function()
        openRatingMenu(snap, owner)
        return MenuResponse and MenuResponse.Close
    end)
end

local function hookMenus()
    if not (Menu and Menu.ModifyMenu) then
        say("this client has no Menu.ModifyMenu - right-click rating unavailable (use /tsl).")
        return
    end
    for _, tag in ipairs(MENU_TAGS) do
        Menu.ModifyMenu(tag, function(owner, root, ctx)
            local ok, err = pcall(buildMenu, owner, root, ctx, tag)
            if not ok then say("menu error: " .. tostring(err)) end
        end)
    end
end

-- ------------------------------------------------------------------ tooltip
local function hookTooltip()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tip)
        pcall(function()
            local _, unit = tip:GetUnit()
            if not unit or not UnitIsPlayer(unit) then return end
            local guid = UnitGUID(unit)
            local e = guid and players[guid]
            if not isActive(e) then return end
            -- picks up the last name for people first rated from chat (no unit back then)
            if not e.realm then
                local snap = snapshot(unit)
                if snap then entryFor(snap, false) end
            end
            local v = verdict(e)
            tip:AddLine(color(VERDICT_COLOR[v], "Sh*t List (" .. v .. "): ") .. describe(e), 1, 1, 1, true)
        end)
    end)
end

-- ------------------------------------------------------------------ group scanning
function groupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function banner(text, hex)
    if not db.settings.banner or not RaidNotice_AddMessage or not RaidWarningFrame then return end
    local r = tonumber(hex:sub(3, 4), 16) / 255
    local g = tonumber(hex:sub(5, 6), 16) / 255
    local b = tonumber(hex:sub(7, 8), 16) / 255
    pcall(RaidNotice_AddMessage, RaidWarningFrame, text, { r = r, g = g, b = b })
end

local function sound(kind)
    if not db.settings.sound then return end
    local id = kind == "bad" and SOUNDKIT.RAID_WARNING or (SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING)
    pcall(PlaySound, id, "Master")
end

-- quiet = chat line only (used right after a /reload, so reloading mid-dungeon doesn't
-- blast banners and sounds for people you were already warned about)
local function scan(quiet)
    if not players then return end
    if not IsInGroup() then
        wipe(announced)
        return
    end
    local where = whereAmI()
    local anyBad, anyGood, banners = false, false, 0
    for _, unit in ipairs(groupUnits()) do
        local guid = UnitExists(unit) and UnitGUID(unit)
        local e = guid and players[guid]
        if isActive(e) then
            local sig = signature(e)
            if announced[guid] ~= sig then
                local firstTimeThisGroup = announced[guid] == nil
                announced[guid] = sig
                local snap = snapshot(unit)
                if snap then entryFor(snap, false) end -- refresh name/realm/class
                local v = verdict(e)
                local name = classColored(e, displayName(e))
                local previously = e.lastSeen and (" (last grouped " .. date("%b %d", e.lastSeen) .. " in " .. (e.lastSeenWhere or "?") .. ")") or ""
                if v == "good" and not db.settings.announceGood then
                    -- still recorded as seen below, just not announced
                -- the wording is tinted to match the verdict, so a good player reads green
                -- at a glance and a bad one red, even before you read the words
                elseif v == "bad" then
                    say(color(RED, "WARNING: ") .. name .. color(RED, " is in your group - ") .. describe(e) .. color(RED, previously))
                    anyBad = true
                    if not quiet and banners < 3 then banner("Sh*t List: " .. (e.name or "?") .. " is in your group!", RED); banners = banners + 1 end
                elseif v == "good" then
                    say(color(GREEN, "Good news: ") .. name .. color(GREEN, " is in your group - ") .. describe(e) .. color(GREEN, previously))
                    anyGood = true
                    if not quiet and banners < 3 then banner("Sh*t List: " .. (e.name or "?") .. " (" .. describe(e):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. ")", GREEN); banners = banners + 1 end
                else
                    say(color(YELLOW, "Heads up: ") .. name .. color(YELLOW, " is in your group - ") .. describe(e) .. color(YELLOW, previously))
                end
                if firstTimeThisGroup then
                    e.lastSeen, e.lastSeenWhere = time(), where
                    e.timesSeen = (e.timesSeen or 0) + 1
                    notify()
                end
            end
        end
    end
    if not quiet then
        if anyBad then sound("bad") elseif anyGood then sound("good") end
    end
end

local scanQueued = false
local function queueScan(quiet)
    if scanQueued then return end
    scanQueued = true
    -- the roster fires several updates in a row while filling in; wait for it to settle
    C_Timer.After(1.5, function()
        scanQueued = false
        local ok, err = pcall(scan, quiet)
        if not ok then say("scan error: " .. tostring(err)) end
    end)
end

-- ------------------------------------------------------------------ runs (end-of-run rating)
-- A "run" = time spent grouped inside a dungeon/raid. Everyone seen in the group while
-- inside is remembered, so the prompt still works after they've left the group. Stored
-- per character (TheShtListBackup.run / .lastRun) so it survives /reload mid-dungeon.
local RUN_MIN_SECONDS = 10 * 60   -- shorter than this (wrong portal, instant wipe) = no prompt
local RESUME_SECONDS = 30 * 60    -- left and came back (repairs, hearth) = same run
local promptPending = false       -- run ended during combat; show the prompt afterwards

local function instanceKey()
    local name, itype, _, _, _, _, _, instanceID = GetInstanceInfo()
    if itype == "party" or itype == "raid" then return tostring(instanceID or name), name end
    return nil
end

local function showPrompt(run)
    if InCombatLockdown() then promptPending = true return end
    promptPending = false
    if ns.showRate then ns.showRate(run) end
end

local function finishRun(force) -- force = /tsl endrun (testing): skip the 10-minute minimum
    local B = TheShtListBackup
    local run = B.run
    B.run = nil
    if not run then return end
    run.ended = time()
    if not next(run.members) then return end
    if not force and run.ended - run.start < RUN_MIN_SECONDS then return end
    B.lastRun = run
    local n = 0
    for _ in pairs(run.members) do n = n + 1 end
    say("run over: " .. (run.where or "?") .. " with " .. n .. " player(s). Rate them now, or any time with " .. color("ffffffff", "/tsl rate") .. ".")
    showPrompt(run)
end

local function trackRun()
    local B = TheShtListBackup
    if not B then return end
    local key, where = instanceKey()
    local now = time()
    if key and IsInGroup() then
        local run = B.run
        if run and run.key ~= key then
            finishRun() -- went straight from one dungeon into another
            run = nil
        end
        if not run then
            local last = B.lastRun
            if last and last.key == key and last.ended and now - last.ended < RESUME_SECONDS then
                run = last -- came back to finish it; keep members and votes
                run.ended = nil
                B.lastRun = nil
                if ns.hideRate then ns.hideRate() end
            else
                run = { id = now .. ":" .. key, key = key, where = where, start = now, members = {}, votes = {} }
            end
            B.run = run
        end
        for _, unit in ipairs(groupUnits()) do
            local snap = snapshot(unit)
            if snap then
                local m = run.members[snap.guid]
                if not m then
                    m = snap
                    m.since = now
                    run.members[snap.guid] = m
                end
                m.name, m.realm, m.class = snap.name or m.name, snap.realm or m.realm, snap.class or m.class
                m.last = now
            end
        end
    elseif B.run then
        -- a ghost being ported out after releasing is a corpse run, not the end of the run
        if not key and UnitIsDeadOrGhost("player") then return end
        finishRun()
    end
end

local function queueTrack()
    C_Timer.After(2, function()
        local ok, err = pcall(trackRun)
        if not ok then say("run tracking error: " .. tostring(err)) end
    end)
end

-- ------------------------------------------------------------------ slash commands
local function sortedActive(filter)
    local list = {}
    for guid, e in pairs(players) do
        if isActive(e) and (not filter or verdict(e) == filter) then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

local function printEntry(e)
    local seen = e.lastSeen and color(GREY, "  (seen " .. (e.timesSeen or 1) .. "x, last " .. date("%b %d", e.lastSeen) .. " " .. (e.lastSeenWhere or "") .. ")") or ""
    say(classColored(e, displayName(e)) .. ": " .. describe(e) .. seen)
end

local function findByName(name)
    name = name:lower()
    local hits = {}
    for guid, e in pairs(players) do
        if isActive(e) then
            local n = (e.name or ""):lower()
            if n == name or displayName(e):lower() == name then hits[#hits + 1] = guid end
        end
    end
    return hits
end

local function onOff(v) return v and color(GREEN, "on") or color(RED, "off") end

SLASH_THESHITLIST1 = "/tsl"
SLASH_THESHITLIST2 = "/shitlist"
SlashCmdList.THESHITLIST = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "list" then
        local filter = rest ~= "" and rest:lower() or nil
        local list = sortedActive(filter)
        if #list == 0 then say("nobody on the list" .. (filter and (" marked " .. filter) or "") .. " yet.") return end
        say(#list .. " player(s):")
        for _, e in ipairs(list) do printEntry(e) end
    elseif cmd == "group" then
        if not IsInGroup() then say("you're not in a group.") return end
        local n = 0
        for _, unit in ipairs(groupUnits()) do
            local guid = UnitGUID(unit)
            local e = guid and players[guid]
            if isActive(e) then printEntry(e); n = n + 1 end
        end
        if n == 0 then say("nobody in this group is on your list.") end
    elseif cmd == "remove" then
        if rest == "" then say("usage: /tsl remove <name>") return end
        local hits = findByName(rest)
        if #hits == 0 then say("no one named '" .. rest .. "' on the list.")
        elseif #hits > 1 then say(#hits .. " matches - use Name-Realm (see /tsl list).")
        else removeEntry(hits[1]) end
    elseif cmd == "banner" or cmd == "sound" then
        db.settings[cmd] = not db.settings[cmd]
        say(cmd .. " " .. onOff(db.settings[cmd]))
    elseif cmd == "good" then
        db.settings.announceGood = not db.settings.announceGood
        say("announcing good players " .. onOff(db.settings.announceGood))
    elseif cmd == "scan" then
        -- forget who's been announced and check the group again right now, with details
        wipe(announced)
        local units = IsInGroup() and groupUnits() or {}
        local listed = 0
        for _, unit in ipairs(units) do
            local guid = UnitGUID(unit)
            if guid and isActive(players[guid]) then listed = listed + 1 end
        end
        say("scanning: in group=" .. tostring(IsInGroup()) .. ", " .. #units .. " other member(s), " .. listed .. " on your list.")
        local ok, err = pcall(scan, false)
        if not ok then say("scan error: " .. tostring(err)) end
    elseif cmd == "test" then
        -- preview what a group-join alert looks like: /tsl test [bad|good|mixed]
        local which = (rest ~= "" and rest:lower()) or "bad"
        if which == "good" then
            say(color(GREEN, "Good news: ") .. "Testname" .. color(GREEN, " is in your group - +3/-0, Great healer, Plays their class well (last grouped Sep 20 in Wailing Caverns)"))
            banner("Sh*t List: Testname (Great healer)", GREEN)
            sound("good")
        elseif which == "mixed" then
            say(color(YELLOW, "Heads up: ") .. "Testname is in your group - " .. color(GREEN, "+1") .. color(GREY, "/") .. color(RED, "-1") .. ", " .. color(RED, "Pulls everything") .. ", " .. color(GREEN, "Great damage"))
            banner("Sh*t List: Testname is in your group", YELLOW)
            sound("good")
        else
            say(color(RED, "WARNING: ") .. "Testname" .. color(RED, " is in your group - +0/-2, Complete asshole, Ninja looter (last grouped Sep 21 in Scholomance)"))
            banner("Sh*t List: Testname is in your group!", RED)
            sound("bad")
        end
        say(color(GREY, "(a preview - nothing is on your list. /tsl test good | mixed | bad)"))
    elseif cmd == "macrobackup" then
        if not ns.macroBackupSet then say("macro backup didn't load.") return end
        local slots = rest:match("^slots%s+(%d+)$")
        if slots then
            local n = ns.macroBackupSlots(tonumber(slots))
            say("macro backup may now use up to " .. n .. " macro(s) (~" .. (n * 3) .. "-" .. (n * 5) .. " players). WoW allows 120 account macros in total.")
        elseif rest == "on" or rest == "off" then
            local on = ns.macroBackupSet(rest == "on")
            say("macro backup " .. onOff(on) .. (on and " - your list is mirrored into hidden macros (TSL1, TSL2...), which survive the beta's saved-data bug."
                or " - the backup macros have been deleted."))
        else
            local used, saved, total = ns.macroBackupStatus()
            say("macro backup " .. onOff(db.settings.macroBackup) .. ": " .. saved .. " of " .. total
                .. " player(s) mirrored across " .. used .. " macro(s). Usage: /tsl macrobackup on|off|slots <n>")
        end
    elseif cmd == "lfgpreview" then
        if not ns.lfgPreview then say("group finder support didn't load.") return end
        local on, rows, tip = ns.lfgPreview()
        say("group finder preview " .. onOff(on) .. " (display only - sample marker on every row; nothing is saved)."
            .. ((rows and tip) and "" or color(YELLOW, " Open the group finder first so it can hook in, then run this again.")))
    elseif cmd == "startfresh" then
        if not loadFailed then say("nothing to do - your list loaded fine.") return end
        loadFailed = false
        markedCount = 0
        say("OK - starting a new list. Rating is unpaused. (Your old list's file is still on disk as TheShtList.lua.bak until the game replaces it.)")
        notify()
    elseif cmd == "testinvite" then
        -- run the invite warning by hand: /tsl testinvite <someone on your list>
        if ns.testInvite then ns.testInvite(rest) else say("group finder support didn't load.") end
    elseif cmd == "ratepreview" then
        -- see the end-of-run window without needing a dungeon group; saves nothing
        if ns.showRatePreview then ns.showRatePreview()
        else say("rating window didn't load.") end
    elseif cmd == "endrun" then
        -- testing: end the current run right now, as if you'd left after 10+ minutes
        if TheShtListBackup.run then finishRun(true)
        else say("not tracking a run right now (you need to be grouped inside a dungeon/raid).") end
    elseif cmd == "rate" then
        local run = TheShtListBackup.run or TheShtListBackup.lastRun
        if run and ns.showRate then ns.showRate(run)
        else say("no dungeon/raid run to rate yet (runs count once you've been grouped inside for 10+ minutes).") end
    elseif cmd == "" or cmd == "show" then
        if ns.toggleWindow then ns.toggleWindow() end
    else
        if loadFailed then
            say(color(RED, "Your saved list (" .. (markedCount or "?") .. " players) didn't load this session") .. " - a known WoW Forever beta bug, not the addon. Rating is paused.")
            say("To get it back: quit the game, then in WTF\\Account\\<account>\\SavedVariables rename TheShtList.lua.bak to TheShtList.lua - or install ForeverSVFix (fixes every addon).")
            say("Starting a new list on purpose: /tsl startfresh")
        end
        say("remember the players worth grouping with, and the ones worth avoiding.")
        say(color("ffffffff", "To rate someone:") .. " right-click them - their portrait, a party or raid frame, or their name in chat - and pick " .. color(RED, "The Sh*t List") .. ". Give a thumbs up or down, tick tags like " .. color(GREEN, "Great healer") .. " or " .. color(RED, "Ninja looter") .. ", or write a note.")
        say(color("ffffffff", "It then warns you") .. " when someone on your list joins your group or invites you, marks them in the group finder, and shows their rating on their tooltip. Only you ever see any of it - nothing is sent to chat.")
        say(color("ffffffff", "After a dungeon or raid") .. " it offers a window to thumb the group up or down while you still remember them.")
        say(color("ffffffff", "Commands:"))
        say("/tsl  - open your list (search, filter, edit)")
        say("/tsl list [bad|good|mixed]  -  /tsl group  -  /tsl rate  -  /tsl remove <name>")
        say("/tsl banner | sound | good  - toggle banner (" .. onOff(db.settings.banner) .. "), sound ("
            .. onOff(db.settings.sound) .. "), announcing good players (" .. onOff(db.settings.announceGood) .. ")")
        say("/tsl test  - preview a warning     /tsl macrobackup  - extra backup copy in hidden macros (" .. onOff(db.settings.macroBackup) .. ")")
    end
end

-- ------------------------------------------------------------------ shared with the window
ns.TAGS, ns.TAG_BY_ID, ns.VERDICT_COLOR = TAGS, TAG_BY_ID, VERDICT_COLOR
ns.RED, ns.GREEN, ns.YELLOW, ns.GREY = RED, GREEN, YELLOW, GREY
ns.color, ns.say, ns.isActive, ns.verdict, ns.describe = color, say, isActive, verdict, describe
ns.classColored, ns.displayName, ns.populateRatingMenu = classColored, displayName, populateRatingMenu
ns.castVote, ns.tally = castVote, tally
ns.loadFailed = function() return loadFailed, markedCount end
ns.entryCount = function() return entryCount() end
ns.entryFor = function(snap, create) return entryFor(snap, create) end

-- ------------------------------------------------------------------ events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("GROUP_LEFT")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ALIVE")
f:RegisterEvent("PLAYER_UNGHOST")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        initDB()
        hookMenus()
        hookTooltip()
        -- safety net for run tracking (events cover almost everything; this catches the rest)
        C_Timer.NewTicker(30, function() pcall(trackRun) end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isLogin, isReload = ...
        queueScan(isReload) -- after /reload: chat reminder only, no banner/sound
        queueTrack()
        -- the layout cache (load marker) is applied shortly after addons load; look a few times
        for _, delay in ipairs({ 0, 1, 3, 6, 10 }) do
            C_Timer.After(delay, function() pcall(checkLoad) end)
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        queueScan(false)
        queueTrack()
    elseif event == "GROUP_LEFT" then
        wipe(announced)
        queueTrack()
    elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        queueTrack()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if promptPending then
            local run = TheShtListBackup.lastRun
            if run then showPrompt(run) else promptPending = false end
        end
    elseif event == "PLAYER_LOGOUT" then
        saveBackup()
        -- after a failed load, keep the OLD count in the marker so the warning keeps coming
        -- back until the real list is restored (or /tsl startfresh)
        pcall(writeMarker, loadFailed and (markedCount or 0) or entryCount())
    end
end)
