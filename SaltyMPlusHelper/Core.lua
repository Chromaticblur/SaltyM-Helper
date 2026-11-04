-- Core.lua: shared state, cooldown tracking, party sync, events.
--
-- How tracking works (Midnight 12.0 stopped addons from reading the combat log):
--   1. Your own casts come from UNIT_SPELLCAST_SUCCEEDED and are shared with the party
--      over addon messages (accurate, talent-aware durations). Your own timers are also
--      checked against the game's "is this cooldown active" flag, which stays readable in
--      combat, so resets and cooldown reductions never leave stale timers.
--   2. Party members' casts are also picked up from UNIT_SPELLCAST_SUCCEEDED when the game
--      gives us a readable spell ID. That works without them having the addon and keeps
--      working inside an active key, using base cooldowns from Spells.lua.
--   3. Blizzard blocks addon messages during active M+ runs and boss encounters, so exact
--      syncing resumes between runs and pulls. Nothing breaks while messages are blocked.

local ADDON, ns = ...
local SPELLS = ns.SPELLS

ns.initHooks = {}
ns.members = {}
local members = ns.members

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

ns.PROTO = 3
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (getMeta and getMeta(ADDON, "Version")) or "?"
local PREFIX = "SALTYMPH"
ns.LOGO = "Interface\\AddOns\\SaltyMPlusHelper\\Media\\logo.tga"

ns.CATEGORIES = { "INT", "CC", "BREZ", "BL", "EXT", "DEF", "OFF", "UTIL" }
ns.CAT_ORDER = { INT = 1, CC = 2, BREZ = 3, BL = 4, EXT = 5, DEF = 6, OFF = 7, UTIL = 8 }
ns.CAT_NAMES = {
    INT = "Interrupts", CC = "Stuns & CC", BREZ = "Battle Res", BL = "Bloodlust",
    EXT = "External CDs", DEF = "Defensives", OFF = "Offensive Cooldowns", UTIL = "Utility",
}
ns.CAT_COLORS = {
    INT = { 0.95, 0.35, 0.35 }, CC = { 0.8, 0.5, 1 }, BREZ = { 0.4, 0.9, 0.5 }, BL = { 1, 0.75, 0.2 },
    EXT = { 0.4, 0.85, 0.9 }, DEF = { 0.4, 0.7, 1 }, OFF = { 1, 0.55, 0.2 }, UTIL = { 0.75, 0.75, 0.8 },
}

-- Fake party used by the preview. { name, class, specID, runsAddon, { spellIDs } }
-- The two "no addon" players show how guessed cooldowns look (? until we see a cast).
ns.PREVIEW = {
    { "Daegtides",  "SHAMAN",  264, true,  { 57994, 2825, 98008, 108271, 192058 } },
    { "Maeow",      "DRUID",   102, true,  { 78675, 20484, 22812, 132469, 194223 } },
    { "Buffalows",  "WARRIOR", 73,  false, { 6552, 97462, 871, 46968, 107574 } },
    { "Rykoojudge", "PALADIN", 70,  false, { 96231, 853, 6940, 633, 31884 } },
}

ns.DEFAULTS = {
    -- general
    enabled = true, showSelf = true, showReady = true, visibility = "ALWAYS",
    scale = 1, alpha = 1,
    showUnknown = true, offSeparate = false,
    -- where: next to the party frame, on its left, one merged row per player
    attach = "PARTY", side = "LEFT", align = "CENTER", offsetX = 4, offsetY = 0,
    stripOrder = "OFFENSIVE", scanFrames = true,
    -- attached layout (style: ICONS, BARS or BOTH)
    style = "ICONS", growth = "LEFT", perRow = 6, maxShown = 12,
    iconSize = 26, spacing = 2, barWidth = 150, barHeight = 18, iconBarHeight = 4,
    -- window (fallback / window mode)
    split = false, titles = true, listNames = true, listSpells = true, windowSort = "CATEGORY",
    -- appearance
    bgAlpha = 0.85, borderAlpha = 1,
    -- grid and snapping (move mode)
    snapOn = true, snapSize = 8, gridShow = true, gridAlpha = 0.18, snapEdges = true,
    -- sleek list windows (interrupts, defensives, CC ...)
    winStyle = "SLEEK", winOrient = "VERTICAL", winIconSize = 24, winGap = 4, winBar = "LINE",
    winBarW = 190, winBarH = 2, winBg = 0, winBorder = false, winIconSide = "LEFT", winPerRow = 8,
    winFill = 0.35, winTextSize = 11, winShowReady = true,
    showTimer = true, timerSize = 12, nameSize = 11, timerPos = "CENTER", decimals = true,
    showSwipe = true, desaturate = true,
    -- timer colour, urgency, per-state opacity, border by spell type, sort
    timerColor = "WHITE", urgentSecs = 5, urgentColor = "RED",
    readyAlpha = 1, cdAlpha = 1, unknownAlpha = 0.55, catBorder = false, stripSort = "CATEGORY",
    border = true, classBorder = true, readyBorder = true, zoom = true, borderSize = 1,
    barColor = "CLASS", barSpellName = true, readyColor = "GREEN",
    fontName = "Friz Quadrata", outline = "OUTLINE", barTexture = "Flat",
    -- mob crowd control tracker
    ccEnabled = true, ccStyle = "ICONS", ccGrowth = "RIGHT", ccIconSize = 32, ccBarWidth = 190,
    ccBarHeight = 22, ccMax = 8, ccShowName = true, ccEstimate = true, ccDefer = true,
    -- bars: icon on the LEFT / RIGHT / NONE, timer on the LEFT / RIGHT
    iconSide = "LEFT", timerSide = "RIGHT",
    -- mythic+: combat text, combat timer, key HUD
    ctEnabled = true, ctOnlyGroup = false, ctEnterText = "+ COMBAT", ctLeaveText = "- COMBAT",
    ctEnterColor = "RED", ctLeaveColor = "GREEN", ctSize = 36, ctDuration = 2, ctSound = false,
    cmbEnabled = true, cmbWhen = "GROUP", cmbSize = 22, cmbColor = "WHITE", cmbTenths = false,
    cmbHideDelay = 5, cmbBg = 0.35,
    mpEnabled = true, mpScale = 1, mpWidth = 230, mpBarHeight = 12, mpBg = 0.6, mpTimer = true,
    mpTimerMode = "ELAPSED", mpThresholds = true, welcomeMsg = true, fkAnnounceOn = false, fkAnnounceReady = true, fkAnnounceEnter = true,  alEnabled = true, sndEnabled = true, khEnabled = true, mdtEnabled = true, stackRows = false, stackKicks = "BOTTOM", stackGap = 3, sndFocusKick = "@RAID_WARNING", sndDeath = "@RAID_WARNING", sndKeyStart = "", sndKeyDone = "", sndKeyStartOn = false, sndKeyDoneOn = false, menuButton = true, nudgeOn = true, nudgeShift = 10, syncOnly = false, mdtTooltip = true, mpLastPull = true, mpForces = true, mpForcesMode = "PERCENT", mpSummary = true, mpHistoryOn = true, mpDeaths = true, mpBrez = true,
    mpHideBlizz = false, mpAutoKey = false,
    ctWhen = "ALWAYS", ctEnterClass = false, ctLeaveClass = false, ctEnter = true, ctLeave = true,
    cmbShowLast = true, urgentEnabled = true, fkSoundOn = true,
    mpTitle = true, mpAffixes = true, mpObjectives = true, mpCompare = true,
    dtEnabled = true, dtOnlyInstance = true, dtSelf = false, dtSound = false, dtSize = 20,
    dtDuration = 4, dtText = "{name} died",
    mpIcons = true, mpIconSize = 38, mpIconBR = true, mpIconBL = true, blReady = true,
    krEnabled = false, krSize = 13, krWidth = 210, krBg = 0.6,
    logEnabled = false, logMplus = true, logMythicRaid = true, logHeroicRaid = false, logNormalRaid = false,
    logChat = true, qolTalkingHead = false,
    klEnabled = true, klWhen = "OUTSIDE", klClick = true, klIncludeSelf = true, klScale = 1,
    klWidth = 280, klBg = 0.7,
    fkEnabled = true, fkText = "KICK FOCUS", fkColor = "ORANGE", fkSize = 34, fkOnlyReady = false,
    fkSound = "RAID_WARNING", fkMarkerIndex = 8,
    alRepair = true, alRepairPct = 30, alMana = true, alManaPct = 35, alNoTarget = false, alSize = 18,
    -- sync / integrations
    autoSync = true, euiUnlock = true, customFrame = "",
}

-- Order in which spell types are listed (and cut off when "maximum shown" is reached).
local ORDERS = {
    KICKS = { INT = 1, CC = 2, BREZ = 3, BL = 4, EXT = 5, DEF = 6, OFF = 7, UTIL = 8 },
    OFFENSIVE = { OFF = 1, DEF = 2, EXT = 3, INT = 4, CC = 5, BREZ = 6, BL = 7, UTIL = 8 },
    DEFENSIVE = { DEF = 1, EXT = 2, OFF = 3, INT = 4, CC = 5, BREZ = 6, BL = 7, UTIL = 8 },
}
function ns.CatRank(cat)
    local order = ORDERS[ns.db and ns.db.stripOrder] or ORDERS.KICKS
    return order[cat] or 99
end

-- One-time settings update: older versions defaulted to nameplates and a separate offensive window (nameplates are gone now).
function ns.MigrateDB(db)
    if (db.schema or 0) < 3 then
        db.offSeparate = false
        db.attach, db.side, db.align, db.growth = "PARTY", "LEFT", "CENTER", "LEFT"
        db.maxShown = max(db.maxShown or 0, 12)
        db.stripOrder = "OFFENSIVE"
        db.schema = 3
    end
    -- the focus kick sound is now one choice (default sounds or any sound) kept in sndFocusKick
    if db.sndFocusKick == nil or db.sndFocusKick == "" then
        db.sndFocusKick = "@" .. (db.fkSound or "RAID_WARNING")
    end
    if db.sndDeath == nil or db.sndDeath == "" then db.sndDeath = "@RAID_WARNING" end
    -- nameplate attaching was removed
    if db.attach == "NAMEPLATE" then db.attach = "PARTY" end
    if (db.schema or 0) < 4 then db.schema = 4 end
end

local DB, CharDB
local callbacks = {}
local needHello = false

-- "Sync only" mode: stay in the sync network (share and receive cooldowns, keep tracking) but
-- show nothing and run none of the extra features.
function ns.SyncOnly() return ns.db ~= nil and ns.db.syncOnly == true end

function ns.Print(...)
    print("|T" .. ns.LOGO .. ":14|t |cff33ccffSaltyM+|r", ...)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.ShortName(name)
    if type(name) ~= "string" or issecret(name) then return nil end
    return Ambiguate(name, "none")
end

function ns.UnitKey(unit)
    return ns.ShortName(GetUnitName(unit, true))
end
local UnitKey, ShortName = ns.UnitKey, ns.ShortName

-- Your own specialization ID (e.g. 264 = Restoration Shaman).
function ns.GetSelfSpec()
    local spi = C_SpecializationInfo
    local idx = (spi and spi.GetSpecialization and spi.GetSpecialization()) or (GetSpecialization and GetSpecialization())
    if not idx then return nil end
    local id
    if spi and spi.GetSpecializationInfo then
        id = spi.GetSpecializationInfo(idx)
    elseif GetSpecializationInfo then
        id = GetSpecializationInfo(idx)
    end
    if type(id) == "number" and id > 0 then return id end
end

-- "Restoration", "Protection", ... for a specialization ID.
function ns.SpecName(id)
    if not id then return nil end
    local ok, _, name = pcall(GetSpecializationInfoByID, id)
    if ok and type(name) == "string" then return name end
    return "spec " .. id
end

-- Specialization of an inspected unit (valid right after INSPECT_READY).
local function GetInspectSpec(unit)
    local spi = C_SpecializationInfo
    local id
    if spi and spi.GetInspectSpecialization then
        id = spi.GetInspectSpecialization(unit)
    elseif GetInspectSpecialization then
        id = GetInspectSpecialization(unit)
    end
    if type(id) == "number" and id > 0 then return id end
end

local infoCache = {}
function ns.SpellInfo(id)
    local c = infoCache[id]
    if c then return c[1], c[2] end
    local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
    if info and info.name then
        infoCache[id] = { info.name, info.iconID }
        return info.name, info.iconID
    end
    return "Spell " .. id, 134400
end

local function GetMember(name, class)
    local m = members[name]
    if not m then
        m = { name = name, spells = {} }
        members[name] = m
    end
    if class then m.class = class end
    return m
end
ns.GetMember = GetMember

local function Fire(...)
    for _, fn in ipairs(callbacks) do
        pcall(fn, ...)
    end
end

function ns:Notify()
    if ns.UI and ns.UI.Changed then ns.UI.Changed() end
end

-- True while Blizzard blocks addon messages (active key or boss encounter).
function ns:SyncBlocked()
    if ns.inEncounter then return true end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active then return true end
    end
    return false
end

function ns:ShouldShow()
    local db = ns.db
    if ns.editMode or ns.preview then return true end
    if not db.enabled then return false end
    local v = db.visibility
    if v == "COMBAT" then return IsInGroup() and UnitAffectingCombat("player") and true or false end
    if v == "GROUP" then return IsInGroup() end
    if v == "DUNGEON" then
        local inInstance, kind = IsInInstance()
        return inInstance and kind == "party"
    end
    return true
end

---------------------------------------------------------------------------
-- Addon messaging
---------------------------------------------------------------------------

local INSTANCE_CATEGORY = (Enum and Enum.PartyCategory and Enum.PartyCategory.Instance) or LE_PARTY_CATEGORY_INSTANCE

local function Channel()
    if IsInGroup(INSTANCE_CATEGORY) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

-- Blizzard blocks addon messages during active Mythic+ keys and boss encounters (result
-- AddOnMessageLockdown, 12.0+). We check first, never retry inside the lockdown, and the
-- caller re-announces afterwards (needHello -> out of combat / key finished).
local function MessagingLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and not issecret(locked) and locked then return true end
    end
    return false
end
ns.MessagingLocked = MessagingLocked

local function Send(msg)
    local ch = Channel()
    if not ch then return false end
    if MessagingLocked() then ns.msgBlocked = true; return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    if not ok then return false end
    local R = Enum and Enum.SendAddonMessageResult
    local success = (R and R.Success) or 0
    if res ~= nil and res ~= true and res ~= success then
        if R and res == R.AddOnMessageLockdown then ns.msgBlocked = true end
        return false
    end
    ns.msgBlocked = false
    return true
end
ns.Send = Send

-- "HI:<proto>:<version>:<id>=<cd>,<id>=<cd>,..." (split into several messages if long)
local function SendHello()
    local parts = {}
    local spec = ns.GetSelfSpec()
    for id in pairs(SPELLS) do
        if IsPlayerSpell(id) then
            parts[#parts + 1] = id .. "=" .. floor((CharDB.learned[id] or ns.CooldownFor(id, spec)) + 0.5)
        end
    end
    table.sort(parts)
    local head = "HI:" .. ns.PROTO .. ":" .. ns.VERSION .. ":" .. (spec or 0) .. ":"
    local msgs, cur, empty = {}, head, true
    for _, p in ipairs(parts) do
        if #cur + #p + 1 > 240 then
            msgs[#msgs + 1] = cur
            cur, empty = head, true
        end
        cur = cur .. (empty and "" or ",") .. p
        empty = false
    end
    msgs[#msgs + 1] = cur
    for _, m in ipairs(msgs) do
        if not Send(m) then return false end
    end
    return true
end
ns.SendHello = SendHello

-- Our own running cooldowns, so people who join or reload mid-key catch up.
local function SendStates()
    local me = UnitKey("player")
    local m = me and members[me]
    if not m then return true end
    local now = GetTime()
    for id, s in pairs(m.spells) do
        if s.start and s.dur and s.start + s.dur > now then
            if not Send(format("CS:%d:%d:%d", id, ceil(s.start + s.dur - now), floor(s.dur + 0.5))) then
                return false
            end
        end
    end
    return true
end

-- Tell the party we exist (and optionally ask them to answer).
function ns:Announce(withRequest)
    local ok = SendHello()
    if ok then ok = SendStates() end
    if ok and withRequest then ok = Send("REQ:" .. ns.PROTO) end
    if not ok then needHello = true end
    return ok
end

local helloTimer
function ns:QueueHello(delay)
    if helloTimer then return end
    helloTimer = C_Timer.NewTimer(delay or 2, function()
        helloTimer = nil
        ns:Announce(false)
    end)
end

local lastReply = 0
local function QueueReply()
    local now = GetTime()
    if now - lastReply < 3 then return end
    lastReply = now
    C_Timer.After(0.3 + random() * 1.2, function() ns:Announce(false) end)
end

-- Several announcements over the first minute, stopping as soon as everyone has answered.
local SYNC_DELAYS = { 1.5, 6, 15, 40 }
function ns:AllPartyAnswered()
    for _, m in pairs(members) do
        if not m.test and not m.isSelf and m.unit and not m.hasAddon then return false end
    end
    return true
end

function ns:ScheduleSync()
    ns.syncGen = (ns.syncGen or 0) + 1
    local gen = ns.syncGen
    if not (ns.db.autoSync and IsInGroup()) then return end
    for i, delay in ipairs(SYNC_DELAYS) do
        C_Timer.After(delay, function()
            if gen ~= ns.syncGen or not ns.db.autoSync or not IsInGroup() then return end
            if i > 1 and ns:AllPartyAnswered() then return end
            ns:Announce(true)
        end)
    end
end

---------------------------------------------------------------------------
-- Cooldown state
---------------------------------------------------------------------------

local function StartCD(name, spellID, dur, source, class)
    local def = SPELLS[spellID]
    if not def or not name then return end
    local m = GetMember(name, class)
    local s = m.spells[spellID]
    if not s then
        s = {}
        m.spells[spellID] = s
    end
    s.known = true
    s.seen = true
    dur = dur or s.base or ns.CooldownFor(spellID, m.spec, m.talents)
    local now = GetTime()
    if s.start and s.dur and (now - s.start) < 2 and s.start + s.dur > now then
        -- Same cast reported twice (event + addon message): only refine the duration.
        if source == "msg" then s.dur = dur end
    else
        s.start, s.dur = now, dur
    end
    Fire("START", name, spellID, s.start, s.dur)
end

local function ReadCooldownInfo(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and type(info) == "table" then return info end
end

local function ReadOwnDuration(spellID)
    local info = ReadCooldownInfo(spellID)
    if not info then return end
    local d = info.duration
    if type(d) ~= "number" or issecret(d) then return end
    if d > 2.5 then
        CharDB.learned[spellID] = d
        return d
    end
end

local function OnLocalCast(spellID)
    local def = SPELLS[spellID]
    if not def then return end
    local me = UnitKey("player")
    if not me then return end
    local _, class = UnitClass("player")
    StartCD(me, spellID, CharDB.learned[spellID], "event", class)
    C_Timer.After(0.25, function()
        local dur = ReadOwnDuration(spellID) or CharDB.learned[spellID] or ns.CooldownFor(spellID, ns.GetSelfSpec())
        StartCD(me, spellID, dur, "msg")
        Send("CD:" .. spellID .. ":" .. floor(dur + 0.5))
    end)
end

-- The "is this cooldown running" flag stays readable in combat even though the numbers
-- don't. If the game says one of our own cooldowns is no longer running while our timer
-- still is, it was reset or reduced: mark it ready and tell the party.
local function ReconcileOwn(now)
    local me = UnitKey("player")
    local m = me and members[me]
    if not m then return end
    for id, s in pairs(m.spells) do
        if s.start and s.dur and s.start + s.dur > now and now - s.start > 1.5 then
            local info = ReadCooldownInfo(id)
            if info then
                local active, onGCD = info.isActive, info.isOnGCD
                if type(active) == "boolean" and not issecret(active) and active == false
                    and not (type(onGCD) == "boolean" and not issecret(onGCD) and onGCD) then
                    s.start = nil
                    Send("RDY:" .. id)
                    Fire("READY", me, id)
                end
            end
        end
    end
end

function ns:HandleMessage(name, text, rawSender)
    local m = members[name]
    if not m then
        -- Roster not scanned yet: accept only real group members.
        local ok, inGroup = pcall(function() return UnitInParty(rawSender) or UnitInRaid(rawSender) end)
        if not (ok and inGroup) then return end
        m = GetMember(name)
    end
    local kind, rest = strsplit(":", text, 2)
    if kind == "CD" then
        local id, dur = strsplit(":", rest or "")
        id, dur = tonumber(id), tonumber(dur)
        if id and dur and SPELLS[id] and dur >= 1 and dur <= 3600 then
            StartCD(name, id, dur, "msg")
        end
    elseif kind == "CS" then
        local id, rem, dur = strsplit(":", rest or "")
        id, rem, dur = tonumber(id), tonumber(rem), tonumber(dur)
        if id and rem and dur and SPELLS[id] and dur >= 1 and dur <= 3600 and rem >= 0 and rem <= dur + 1 then
            local s = m.spells[id]
            if not s then
                s = {}
                m.spells[id] = s
            end
            s.known = true
            s.seen = true
            s.start, s.dur = GetTime() - (dur - rem), dur
            Fire("START", name, id, s.start, s.dur)
        end
    elseif kind == "RDY" then
        local id = tonumber(rest)
        local s = id and m.spells[id]
        if s and s.start then
            s.start = nil
            Fire("READY", name, id)
        end
    elseif kind == "REQ" then
        m.hasAddon = true
        QueueReply()
    elseif kind == "HI" then
        local first = not m.hasAddon
        local proto, ver, spec, list = strsplit(":", rest or "", 4)
        if (tonumber(proto) or 0) < 3 then spec, list = nil, spec end
        m.hasAddon = true
        m.version = ver
        spec = tonumber(spec)
        if spec and spec > 0 then m.spec = spec end
        m.reported = m.reported or {}
        for id, dur in string.gmatch(list or "", "(%d+)=(%d+)") do
            id, dur = tonumber(id), tonumber(dur)
            if SPELLS[id] then
                local s = m.spells[id]
                if not s then
                    s = {}
                    m.spells[id] = s
                end
                s.known = true
                s.baseline = nil
                s.base = dur
                m.reported[id] = true
            end
        end
        -- Exact data beats guessing: drop guessed spells this player does not actually have.
        for id, s in pairs(m.spells) do
            if s.baseline and not m.reported[id] and not s.start then m.spells[id] = nil end
        end
        -- Answer once so someone who just met us learns about us too.
        if first and ns.db.autoSync then QueueReply() end
    end
    ns:Notify()
end

---------------------------------------------------------------------------
-- Roster
---------------------------------------------------------------------------

local UNITS = { "player", "party1", "party2", "party3", "party4" }

function ns:RefreshSelf()
    local me = UnitKey("player")
    if not me then return end
    local _, class = UnitClass("player")
    local m = GetMember(me, class)
    m.isSelf, m.unit, m.hasAddon, m.version = true, "player", true, ns.VERSION
    m.spec = ns.GetSelfSpec() or m.spec
    m.faction = UnitFactionGroup and UnitFactionGroup("player") or m.faction
    local now = GetTime()
    for id in pairs(SPELLS) do
        local s = m.spells[id]
        if IsPlayerSpell(id) then
            if not s then
                s = {}
                m.spells[id] = s
            end
            s.known = true
            s.base = CharDB.learned[id] or ns.CooldownFor(id, m.spec)
        elseif s and not (s.start and s.dur and s.start + s.dur > now) then
            m.spells[id] = nil
        end
    end
end

function ns:ScanRoster()
    local present = {}
    for _, unit in ipairs(UNITS) do
        if UnitExists(unit) then
            local name = UnitKey(unit)
            if name then
                present[name] = true
                local _, class = UnitClass(unit)
                local m = GetMember(name, class)
                m.unit = unit
                if UnitFactionGroup then m.faction = UnitFactionGroup(unit) or m.faction end
            end
        end
    end
    for name, m in pairs(members) do
        if not present[name] and not m.test then
            members[name] = nil
        end
    end
    ns:RefreshSelf()
    for _, m in pairs(members) do ns:ApplyBaseline(m) end
    ns:Notify()
end

-- People without the addon: list everything their class and specialization has as guessed
-- cooldowns. Once we have inspected their talents, talent spells they actually took are
-- listed too (and cooldown-reducing talents are applied); before that, talent spells only
-- appear after we have seen them cast.
function ns:ApplyBaseline(m)
    if m.isSelf or m.test or m.hasAddon or not m.class then return end
    local want = {}
    for _, id in ipairs(ns.CLASS_SPELLS[m.class] or {}) do
        local def = SPELLS[id]
        if ns.SpellApplies(def, m.class, m.spec, m.faction) then
            if not def.talent or (m.talents and (m.talents[id] or 0) > 0) then want[id] = true end
        end
    end
    for id in pairs(want) do
        local s = m.spells[id]
        if not s then
            s = {}
            m.spells[id] = s
        end
        s.known = true
        s.baseline = true
        s.base = ns.CooldownFor(id, m.spec, m.talents)
    end
    local now = GetTime()
    for id, s in pairs(m.spells) do
        if s.baseline and not want[id] and not s.seen and not (s.start and s.dur and s.start + s.dur > now) then
            m.spells[id] = nil
        end
    end
end

---------------------------------------------------------------------------
-- Finding out other players' specialization (inspect), one at a time, out of combat
---------------------------------------------------------------------------

local inspectUnit
local lastInspect = 0
if NotifyInspect then
    -- other addons inspect too: never start one within two seconds of anyone else's
    hooksecurefunc("NotifyInspect", function() lastInspect = GetTime() end)
end

-- Talents of the inspected player: { [talentSpellID] = rank }, or nil when unavailable.
local function ReadInspectTalents()
    local T = C_Traits
    if not (T and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo and T.GetEntryInfo and T.GetDefinitionInfo) then
        return nil
    end
    local config = (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
    if T.HasValidInspectData and T.HasValidInspectData() == false then return nil end
    local info = T.GetConfigInfo(config)
    local trees = type(info) == "table" and info.treeIDs
    if type(trees) ~= "table" then return nil end
    local out, count = {}, 0
    for _, tree in ipairs(trees) do
        local nodes = T.GetTreeNodes(tree)
        if type(nodes) == "table" then
            for _, nodeID in ipairs(nodes) do
                local node = T.GetNodeInfo(config, nodeID)
                if type(node) == "table" and node.subTreeActive ~= false then
                    local act, rank = node.activeEntry, node.activeRank
                    if type(act) == "table" and type(rank) == "number" and rank > 0 then
                        local e = T.GetEntryInfo(config, act.entryID)
                        local d = type(e) == "table" and e.definitionID and T.GetDefinitionInfo(e.definitionID)
                        local sid = type(d) == "table" and d.spellID
                        if type(sid) == "number" then
                            out[sid] = rank
                            count = count + 1
                        end
                    end
                end
            end
        end
    end
    return count > 0 and out or nil
end

local function ProcessInspect()
    if inspectUnit or InCombatLockdown() or not IsInGroup() then return end
    if GetTime() - lastInspect < 2 then return end
    local sheet = _G.InspectFrame
    if sheet and sheet:IsShown() then return end
    for _, unit in ipairs(UNITS) do
        local name = unit ~= "player" and UnitExists(unit) and UnitKey(unit)
        local m = name and members[name]
        if m and not m.inspected and not m.test and not (m.hasAddon and m.spec) and (m.inspectTries or 0) < 6 then
            local ok, can = pcall(function()
                return CanInspect(unit) and UnitIsConnected(unit) and CheckInteractDistance(unit, 1)
            end)
            if ok and can then
                m.inspectTries = (m.inspectTries or 0) + 1
                inspectUnit = unit
                lastInspect = GetTime()
                pcall(NotifyInspect, unit)
                C_Timer.After(3, function() if inspectUnit == unit then inspectUnit = nil end end)
                return
            end
        end
    end
end

local function OnInspectReady(guid)
    local unit = inspectUnit
    if not unit then return end
    -- someone else's inspect can answer first: make sure this one is ours
    if guid ~= nil and not issecret(guid) then
        local ok, mine = pcall(UnitGUID, unit)
        if ok and mine ~= nil and not issecret(mine) and mine ~= guid then return end
    end
    inspectUnit = nil
    local name = UnitExists(unit) and UnitKey(unit)
    local m = name and members[name]
    if m then
        local spec = GetInspectSpec(unit)
        if spec then m.spec = spec end
        local ok, talents = pcall(ReadInspectTalents)
        if ok and talents then m.talents = talents end
        if spec or m.talents then
            m.inspected = true
            ns:ApplyBaseline(m)
            ns:Notify()
        end
    end
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
end

-- Everyone in the party with their addon status, in party order (for the Sync tab).
function ns:GetSyncRoster()
    local out = {}
    for _, unit in ipairs(UNITS) do
        for _, m in pairs(members) do
            if m.unit == unit and not m.test then
                out[#out + 1] = {
                    name = m.name, class = m.class, unit = unit, self = m.isSelf,
                    hasAddon = m.hasAddon and true or false, version = m.version, spec = m.spec,
                }
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Preview (fake party) and move mode
---------------------------------------------------------------------------

function ns:SetPreview(on)
    on = on and true or false
    ns.preview = on
    for name, m in pairs(members) do
        if m.test then members[name] = nil end
    end
    if on then
        local now = GetTime()
        for mi, f in ipairs(ns.PREVIEW) do
            local m = GetMember(f[1], f[2])
            m.test, m.previewIndex, m.spec, m.hasAddon = true, mi, f[3], f[4]
            m.faction = "Horde"
            for i, id in ipairs(f[5]) do
                local def = SPELLS[id]
                if def then
                    local cd = ns.CooldownFor(id, f[3])
                    local s = { known = true, base = cd, dur = cd }
                    if (mi + i) % 3 ~= 0 then
                        s.start = now - cd * (0.1 + 0.17 * ((mi + i) % 5))
                        s.loop = true
                        s.seen = true
                    elseif f[4] then
                        s.seen = true -- addon users always report their state
                    end
                    m.spells[id] = s
                end
            end
        end
    end
    if ns.CC then ns.CC:SetPreview(on) end
    ns:Refresh()
    ns:Notify()
end

function ns:SetEditMode(on)
    ns.editMode = on and true or false
    if not ns.editMode and ns.Select then ns.selected = nil; ns.Select(nil) end
    ns:Refresh()
    ns:Notify()
end

ns.editMode = false
ns.preview = false
ns.inEncounter = false

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_SALTYMPLUSHELPER1 = "/salty"
SLASH_SALTYMPLUSHELPER2 = "/smh"
SLASH_SALTYMPLUSHELPER3 = "/saltym"
SLASH_SALTYHIST1 = "/salthist"
SlashCmdList["SALTYHIST"] = function()
    if ns.MP then ns.MP:PrintHistory() end
end

SlashCmdList["SALTYMPLUSHELPER"] = function(msg)
    local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
    local db = ns.db
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.UI:Toggle()
    elseif cmd == "show" or cmd == "hide" or cmd == "toggle" then
        if cmd == "toggle" then db.enabled = not db.enabled else db.enabled = (cmd == "show") end
        ns:Refresh()
        ns:Notify()
    elseif cmd == "test" or cmd == "preview" then
        ns:SetPreview(not ns.preview)
    elseif cmd == "unlock" or cmd == "move" then
        ns:SetEditMode(not ns.editMode)
    elseif cmd == "lock" then
        ns:SetEditMode(false)
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if v then ns:SetScaleAll(v) else ns.Print("Usage: /salty scale 0.5-2") end
    elseif cmd == "sync" then
        ns.Print(ns:Announce(true) and "Sync sent." or "Could not send (not in a group, or messages are blocked right now).")
    elseif cmd == "status" then
        ns.Print(ns:StatusText())
    elseif cmd == "eui" then
        db.euiUnlock = not db.euiUnlock
        if db.euiUnlock then
            ns.Print(ns:RegisterEllesmere() and "EllesmereUI unlock mode: registered." or "EllesmereUI not found (or registration failed).")
        else
            ns:UnregisterEllesmere()
            ns.Print("EllesmereUI unlock mode: off. /reload to fully detach.")
        end
        ns:Notify()
    elseif cmd == "reset" then
        ns:ResetPositions()
        ns.Print("Positions reset.")
    elseif cmd == "synconly" then
        db.syncOnly = not db.syncOnly
        ns:Refresh()
        ns:Notify()
        ns.Print("Sync-only mode " .. (db.syncOnly and "ON: nothing is displayed, syncing continues." or "OFF."))
    elseif cmd == "mdt" then
        if ns.MP and ns.MP.MDT then ns.MP.MDT.Open() end
    elseif cmd == "history" then
        if ns.MP then ns.MP:PrintHistory() end
    elseif cmd == "cds" then
        -- compare the built-in cooldown values with what the game reported for your own spells
        local spec, n = ns.GetSelfSpec(), 0
        for id, learned in pairs(ns.charDB.learned) do
            local def = SPELLS[id]
            if def then
                local base = ns.CooldownFor(id, spec)
                if math.abs(learned - base) > 0.5 then
                    n = n + 1
                    ns.Print(format("%s: built-in %ds, game says %ds (edit Spells.lua)", (ns.SpellInfo(id)), base, learned))
                end
            end
        end
        ns.Print(n == 0 and "All the cooldowns learned so far match the built-in values." or (n .. " differ."))
    elseif cmd == "secrets" then
        -- which spell casts by other players can this client read right now?
        if not (C_Secrets and C_Secrets.ShouldUnitSpellCastBeSecret) then
            ns.Print("This client does not expose the secret-value checks.")
        else
            local readable, total, names = 0, 0, {}
            for id in pairs(SPELLS) do
                total = total + 1
                local ok, secret = pcall(C_Secrets.ShouldUnitSpellCastBeSecret, "party1", id)
                if ok and secret == false then
                    readable = readable + 1
                    if #names < 8 then names[#names + 1] = (ns.SpellInfo(id)) end
                end
            end
            ns.Print(format("Party casts the game lets addons read right now: %d of %d tracked spells%s",
                readable, total, #names > 0 and (" (e.g. " .. table.concat(names, ", ") .. ")") or ""))
        end
    else
        ns.Print("/salty opens the settings window. Also: show, hide, toggle, test, move, lock, scale <0.5-2>, sync, status, eui, reset, history, mdt, synconly, cds, secrets. Also /salthist and /skeys.")
    end
end

function SaltyMPlusHelper_OnAddonCompartmentClick()
    ns.UI:Toggle()
end

function SaltyMPlusHelper_OnAddonCompartmentEnter(_, frame)
    if not frame then return end
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("SaltyM+Helper")
    GameTooltip:AddLine("Click to open the settings window.", 1, 1, 1)
    GameTooltip:Show()
end

function SaltyMPlusHelper_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

---------------------------------------------------------------------------
-- Public API for other addons (UI suites, WeakAura-likes, etc.)
--   SaltyMPlusHelperAPI.GetCooldown(name, spellID) -> remaining, duration (nil if untracked)
--   SaltyMPlusHelperAPI.GetMembers()               -> { "Name", ... }
--   SaltyMPlusHelperAPI.RegisterCallback(fn)       -> fn("START", name, spellID, start, dur)
--                                                      fn("READY", name, spellID)
---------------------------------------------------------------------------

local api = { version = 1 }

function api.GetCooldown(name, spellID)
    local m = members[name]
    local s = m and m.spells[spellID]
    if not s or not s.known then return nil end
    if not (s.start and s.dur) then
        return 0, s.base or SPELLS[spellID].cd
    end
    return max(0, s.start + s.dur - GetTime()), s.dur
end

function api.GetMembers()
    local out = {}
    for name, m in pairs(members) do
        if not m.test then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function api.RegisterCallback(fn)
    if type(fn) == "function" then callbacks[#callbacks + 1] = fn end
end

_G.SaltyMPlusHelperAPI = api

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    SaltyMPlusHelperDB = SaltyMPlusHelperDB or {}
    SaltyMPlusHelperCharDB = SaltyMPlusHelperCharDB or {}
    DB, CharDB = SaltyMPlusHelperDB, SaltyMPlusHelperCharDB
    ns.db, ns.charDB = DB, CharDB

    -- Migrate settings from 0.3.x
    if DB.enabled == nil and DB.shown ~= nil then DB.enabled = DB.shown and true or false end

    for k, v in pairs(ns.DEFAULTS) do
        if DB[k] == nil then DB[k] = v end
    end
    ns.MigrateDB(DB)
    DB.pos = DB.pos or {}
    DB.disabled = DB.disabled or {}
    DB.categories = DB.categories or {}
    for _, cat in ipairs(ns.CATEGORIES) do
        if DB.categories[cat] == nil then DB.categories[cat] = true end
    end
    CharDB.learned = CharDB.learned or {}

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    for _, fn in ipairs(ns.initHooks) do fn() end

    local acc, acc2 = 0, 0
    ns.updater = CreateFrame("Frame")
    ns.updater:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        acc2 = acc2 + elapsed
        if acc >= 0.1 then
            acc = 0
            ns:Refresh()
        end
        if acc2 >= 0.25 then
            acc2 = 0
            ReconcileOwn(GetTime())
        end
    end)

    local ev = ns.eventFrame
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:RegisterEvent("GROUP_ROSTER_UPDATE")
    ev:RegisterEvent("SPELLS_CHANGED")
    ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ev:RegisterEvent("ENCOUNTER_START")
    ev:RegisterEvent("ENCOUNTER_END")
    ev:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:RegisterEvent("CHAT_MSG_ADDON")
    ev:RegisterEvent("INSPECT_READY")
    ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    C_Timer.NewTicker(3, ProcessInspect)
    if ns.db.welcomeMsg ~= false then
        ns.Print(format("Welcome back, %s! v%s loaded. |cffffffff/salty|r opens settings, |cffffffff/salthist|r shows your key history, |cffffffff/skeys|r lists party keystones.", UnitName("player") or "friend", ns.VERSION))
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    ns:ScanRoster()
    C_Timer.After(3, function()
        ns:ScanRoster()
        ns:ScheduleSync()
    end)
    ns:TryIntegrations(1)
end

function handlers.GROUP_ROSTER_UPDATE()
    ns:ScanRoster()
    for _, m in pairs(members) do
        if not m.spec then m.inspectTries = 0 end
    end
    -- (members that were already inspected keep what we learned)
    ns:ScheduleSync()
end

handlers.INSPECT_READY = OnInspectReady

function handlers.SPELLS_CHANGED()
    ns:RefreshSelf()
    ns:QueueHello(3)
end
handlers.PLAYER_SPECIALIZATION_CHANGED = handlers.SPELLS_CHANGED

function handlers.ENCOUNTER_START() ns.inEncounter = true end

-- Messages are blocked during encounters and keys, so re-announce once they end.
function handlers.ENCOUNTER_END()
    ns.inEncounter = false
    ns:QueueHello(2)
end
function handlers.CHALLENGE_MODE_COMPLETED() ns:QueueHello(2) end
function handlers.PLAYER_REGEN_ENABLED()
    if needHello then
        needHello = false
        ns:QueueHello(1)
    end
end

function handlers.CHAT_MSG_ADDON(prefix, text, _, sender)
    if issecret(prefix) or prefix ~= PREFIX or issecret(text) or issecret(sender)
        or type(text) ~= "string" or type(sender) ~= "string" then return end
    local name = ShortName(sender)
    if not name or name == UnitKey("player") then return end
    ns:HandleMessage(name, text, sender)
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if issecret(unit) or issecret(spellID) or type(spellID) ~= "number" then return end
    spellID = ns.ALIASES[spellID] or spellID
    if unit == "player" then
        if ns.CC then ns.CC:OnPlayerCast(spellID) end
        if SPELLS[spellID] then OnLocalCast(spellID) end
    elseif SPELLS[spellID] and type(unit) == "string" and unit:find("^party%d$") then
        local name = UnitKey(unit)
        if name then
            local _, class = UnitClass(unit)
            StartCD(name, spellID, nil, "event", class)
        end
    end
end

ns.eventFrame = CreateFrame("Frame")
ns.eventFrame:RegisterEvent("ADDON_LOADED")
ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if h then h(...) end
end)
