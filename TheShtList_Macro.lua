-- The Shit List - built-in backup that survives the WoW Forever saved-variables bug.
--
-- Build 69913 writes SavedVariables but often never reads them back, and logging out then
-- overwrites the file with an empty list. Addons can't fix that themselves (tested: even
-- leaving the variable nil still writes "= nil"), and the usual answer is an external
-- tool. Macros, however, are stored on Blizzard's servers rather than in the WTF folder,
-- they survive the bug, and addons may read and write them - so the list is mirrored into
-- a few hidden account macros ("TSL1", "TSL2", ...) and restored automatically when the
-- saved file comes back empty.
--
-- Limits: 255 characters per macro, so notes are trimmed and the least recently changed
-- players drop off the end. It's a safety net, not the primary store.

local ADDON, ns = ...

local MACRO_PREFIX = "TSL"
-- WoW allows 120 account macros; only as many as the list needs are created, so a small
-- list still uses one or two. The default 40 holds roughly 120 players with notes, 200
-- without, and leaves 80 slots free for the player's own macros. /tsl macrobackup slots
-- <n> raises it for bigger lists (at 100 slots, ~300-500 players); the hard ceiling is
-- the macro cap itself, so a list of thousands needs the saved file to work.
local DEFAULT_MACROS, MAX_MACROS_LIMIT = 40, 100
local function maxMacros()
    local n = ns.db and ns.db.settings and ns.db.settings.macroSlots
    return math.max(1, math.min(tonumber(n) or DEFAULT_MACROS, MAX_MACROS_LIMIT))
end
local MAX_BODY = 250         -- macro bodies cap at 255
local NOTE_MAX = 24
local MACRO_ICON = 134400    -- INV_Misc_QuestionMark

-- ------------------------------------------------------------------ small helpers
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function to36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local out = ""
    while n > 0 do
        local d = n % 36
        out = B36:sub(d + 1, d + 1) .. out
        n = math.floor(n / 36)
    end
    return out
end
local function from36(s)
    return tonumber(s, 36) or 0
end

-- ~ and ; separate fields and records; | would break macro text
local function clean(s, maxLen)
    s = tostring(s or ""):gsub("[~;|\n\r]", " ")
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end

local function macroAPI()
    local get = GetMacroBody or (C_Macro and C_Macro.GetMacroBody)
    local index = GetMacroIndexByName or (C_Macro and C_Macro.GetMacroIndexByName)
    return get, index, CreateMacro, EditMacro, DeleteMacro
end

-- ------------------------------------------------------------------ encode / decode
-- one record: guid~name~realm~class#~tagbits36~up36~down36~updatedMinutes36~note
-- (class as a number and time in minutes keep records short, so more players fit)
local CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}
local CLASS_INDEX = {}
for i, c in ipairs(CLASSES) do CLASS_INDEX[c] = i end
local function tagBits(e)
    local bits = 0
    for i, t in ipairs(ns.TAGS) do
        if e.tags and e.tags[t.id] then bits = bits + 2 ^ (i - 1) end
    end
    return bits
end

local function bitsToTags(bits)
    local tags = {}
    for i, t in ipairs(ns.TAGS) do
        local bit = 2 ^ (i - 1)
        if math.floor(bits / bit) % 2 == 1 then tags[t.id] = true end
    end
    return tags
end

local function encode(guid, e)
    return table.concat({
        (guid:gsub("^Player%-", "")),
        clean(e.name, 24),
        clean(e.realm, 24),
        to36(CLASS_INDEX[e.class or ""] or 0),
        to36(tagBits(e)),
        to36(e.up or 0),
        to36(e.down or 0),
        to36(math.floor((e.updated or 0) / 60)),
        clean(e.note, NOTE_MAX),
    }, "~")
end

local function decode(record)
    local f = {}
    for field in (record .. "~"):gmatch("([^~]*)~") do f[#f + 1] = field end
    if #f < 8 or f[1] == "" then return nil end
    local guid = "Player-" .. f[1]
    return guid, {
        name = f[2] ~= "" and f[2] or nil,
        realm = f[3] ~= "" and f[3] or nil,
        class = CLASSES[from36(f[4])] or nil,
        tags = bitsToTags(from36(f[5])),
        up = from36(f[6]) > 0 and from36(f[6]) or nil,
        down = from36(f[7]) > 0 and from36(f[7]) or nil,
        updated = from36(f[8]) * 60,
        note = (f[9] and f[9] ~= "") and f[9] or nil,
    }
end

-- newest changes first, so if the list outgrows the macros it's the stalest that drop off
local function records()
    local list = {}
    for guid, e in pairs(ns.players or {}) do
        if ns.isActive(e) then list[#list + 1] = { guid = guid, e = e } end
    end
    table.sort(list, function(a, b) return (a.e.updated or 0) > (b.e.updated or 0) end)
    local out = {}
    for _, item in ipairs(list) do out[#out + 1] = encode(item.guid, item.e) end
    return out
end

local function bodies()
    local out, current = {}, ""
    for _, rec in ipairs(records()) do
        if #rec + 1 > MAX_BODY then
            -- pathological single record: skip rather than corrupt a macro
        elseif current == "" then
            current = rec
        elseif #current + 1 + #rec <= MAX_BODY then
            current = current .. ";" .. rec
        else
            out[#out + 1] = current
            if #out >= maxMacros() then return out end
            current = rec
        end
    end
    if current ~= "" and #out < maxMacros() then out[#out + 1] = current end
    return out
end

-- ------------------------------------------------------------------ writing
local warned = false
local function write()
    if not (ns.db and ns.db.settings and ns.db.settings.macroBackup) then return end
    if InCombatLockdown() then return end -- macro APIs are unavailable in combat
    local getBody, indexByName, create, edit, delete = macroAPI()
    if not (getBody and indexByName and create and edit and delete) then return end

    local list = bodies()
    for i = 1, MAX_MACROS_LIMIT do
        local name = MACRO_PREFIX .. i
        local idx = indexByName(name) or 0
        local body = list[i]
        if body then
            local ok
            if idx > 0 then
                ok = pcall(edit, idx, name, MACRO_ICON, body)
            else
                ok = pcall(create, name, MACRO_ICON, body, false) -- false = account-wide
            end
            if not ok and not warned then
                warned = true
                ns.say(ns.color(ns.YELLOW, "couldn't write the macro backup")
                    .. " - your macro list may be full. /tsl macrobackup off to stop trying.")
            end
        elseif idx > 0 then
            pcall(delete, idx) -- list shrank: drop the leftover macro
        end
    end
end

local pending = false
local function queueWrite()
    if pending then return end
    pending = true
    C_Timer.After(3, function()
        pending = false
        pcall(write)
    end)
end

-- ------------------------------------------------------------------ reading
ns.restoreFromMacros = function()
    if not (ns.db and ns.db.settings and ns.db.settings.macroBackup) then return 0 end
    local getBody, indexByName = macroAPI()
    if not (getBody and indexByName) then return 0 end
    local restored = 0
    for i = 1, MAX_MACROS_LIMIT do
        local idx = indexByName(MACRO_PREFIX .. i) or 0
        if idx > 0 then
            local ok, body = pcall(getBody, idx)
            if ok and type(body) == "string" then
                for record in (body .. ";"):gmatch("([^;]+);") do
                    local guid, e = decode(record)
                    if guid then
                        local mine = ns.players[guid]
                        if not mine or (e.updated or 0) > (mine.updated or 0) then
                            e.added = (mine and mine.added) or e.updated
                            ns.players[guid] = e
                            restored = restored + 1
                        end
                    end
                end
            end
        end
    end
    return restored
end

ns.macroBackupSet = function(on)
    ns.db.settings.macroBackup = on and true or false
    if on then
        warned = false
        pcall(write)
    else
        local _, indexByName, _, _, delete = macroAPI()
        if indexByName and delete then
            for i = MAX_MACROS_LIMIT, 1, -1 do
                local idx = indexByName(MACRO_PREFIX .. i) or 0
                if idx > 0 then pcall(delete, idx) end
            end
        end
    end
    return ns.db.settings.macroBackup
end

ns.macroBackupSlots = function(n)
    ns.db.settings.macroSlots = math.max(1, math.min(tonumber(n) or DEFAULT_MACROS, MAX_MACROS_LIMIT))
    pcall(write)
    return ns.db.settings.macroSlots
end

ns.macroBackupStatus = function()
    local _, indexByName = macroAPI()
    local used, saved = 0, 0
    if indexByName then
        for i = 1, MAX_MACROS_LIMIT do
            local idx = indexByName(MACRO_PREFIX .. i) or 0
            if idx > 0 then
                used = used + 1
                local getBody = macroAPI()
                local ok, body = pcall(getBody, idx)
                if ok and type(body) == "string" then
                    for _ in body:gmatch("[^;]+") do saved = saved + 1 end
                end
            end
        end
    end
    return used, saved, #records()
end

-- ------------------------------------------------------------------ hooks
local previousRefresh = ns.refresh
ns.refresh = function()
    if previousRefresh then previousRefresh() end
    queueWrite()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(12, function() pcall(write) end) -- after the load check has settled
    else
        pcall(write) -- logout, or combat ended with changes waiting
    end
end)
