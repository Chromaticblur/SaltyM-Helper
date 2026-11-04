-- SaltyM+Helper
-- Tracks party members' key cooldowns for Mythic+ (Retail / Midnight 12.0+).
--
-- How it works (Midnight 12.0 stopped addons from reading the combat log):
--   1. Your own casts come from UNIT_SPELLCAST_SUCCEEDED and are shared with the
--      party over addon messages (accurate, talent-aware durations). Your own timers
--      are also checked against the game's "is this cooldown active" flag, which stays
--      readable in combat, so resets and cooldown reductions don't leave stale timers.
--   2. Party members' casts are also picked up from UNIT_SPELLCAST_SUCCEEDED when the
--      game gives us a readable spell ID. This works without them having the addon
--      and keeps working inside an active key, using base cooldowns from Spells.lua.
--   3. Blizzard blocks addon messages during active M+ runs and boss encounters, so
--      syncing resumes between runs/pulls. Nothing breaks when messages are blocked.
--
-- Integrations (all optional, all wrapped so a failure can never break the addon):
--   * EllesmereUI: groups are registered with its /unlock mode (move, snap, anchor).
--   * BigWigs: boss engage/win/wipe messages tell us when an encounter is running.
--   * Other addons: a small public API, SaltyMPlusHelperAPI (see bottom of file).
--
-- Type /salty in game to open the preview / layout window.

local ADDON, ns = ...
local SPELLS = ns.SPELLS

local PREFIX = "SALTYMPH"
local WIDTH, ROW_H, HEADER_H = 250, 22, 24
local CAT_ORDER = { INT = 1, BREZ = 2, BL = 3, DEF = 4, UTIL = 5 }
local SPLIT_KEYS = { "INT", "BREZ", "BL", "DEF", "UTIL" }
local ALL_KEYS = { "ALL" }
local TITLES = {
    ALL = "SaltyM+ Cooldowns", INT = "Interrupts", BREZ = "Battle Res",
    BL = "Bloodlust", DEF = "Defensives", UTIL = "Stuns & Utility",
}
-- Default top-left corner of each group, as an offset from the screen center.
local DEFAULT_POS = {
    ALL  = { -300, 200 },
    INT  = { -520, 220 },
    DEF  = { -260, 220 },
    BREZ = { -520, 60 },
    BL   = { -260, 60 },
    UTIL = { -520, -20 },
}
-- Fake party used by the preview. { name, class, { spellIDs } }
local PREVIEW = {
    { "Stabby",  "ROGUE",       { 1766 } },
    { "Deathy",  "DEATHKNIGHT", { 47528, 48707, 61999 } },
    { "Holyguy", "PRIEST",      { 33206, 62618 } },
    { "Zappy",   "SHAMAN",      { 57994, 2825 } },
    { "Tanky",   "PALADIN",     { 96231, 853, 6940 } },
    { "Treeman", "DRUID",       { 20484, 132469 } },
}

local issecret = issecretvalue or function() return false end
local DB, CharDB
local members = {}
local groups = {}
local callbacks = {}
local euiRegistered = {}
local needHello = false
local SyncConfig -- defined with the config window below

local EUI_PREFIX = "SMH_"
local LOGO = "Interface\\AddOns\\SaltyMPlusHelper\\Media\\logo.tga"

ns.editMode = false
ns.preview = false
ns.inEncounter = false

local function Print(...)
    print("|T" .. LOGO .. ":14|t |cff33ccffSaltyM+|r", ...)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function ShortName(name)
    if type(name) ~= "string" or issecret(name) then return nil end
    return Ambiguate(name, "none")
end

local function UnitKey(unit)
    return ShortName(GetUnitName(unit, true))
end

local infoCache = {}
local function SpellInfo(id)
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

local function Fire(...)
    for _, fn in ipairs(callbacks) do
        pcall(fn, ...)
    end
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

local function EUIUnlockActive()
    local e = _G.EllesmereUI
    if e and e.IsUnlockModeActive then
        local ok, v = pcall(e.IsUnlockModeActive)
        return (ok and v) and true or false
    end
    return false
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

local function Send(msg)
    local ch = Channel()
    if not ch then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, ch)
    if not ok then return false end
    local success = (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success) or 0
    if res ~= nil and res ~= true and res ~= success then return false end
    return true
end

local function SendHello()
    local parts = {}
    for id, def in pairs(SPELLS) do
        if IsPlayerSpell(id) then
            parts[#parts + 1] = id .. "=" .. floor((CharDB.learned[id] or def.cd) + 0.5)
        end
    end
    local msgs, cur = {}, "HI:"
    for _, p in ipairs(parts) do
        if #cur + #p + 1 > 240 then
            msgs[#msgs + 1] = cur
            cur = "HI:"
        end
        cur = cur .. (cur == "HI:" and "" or ",") .. p
    end
    msgs[#msgs + 1] = cur
    for _, m in ipairs(msgs) do
        if not Send(m) then return false end
    end
    return true
end

local helloTimer
local function QueueHello(delay)
    if helloTimer then return end
    helloTimer = C_Timer.NewTimer(delay or 2, function()
        helloTimer = nil
        if not SendHello() then needHello = true end
    end)
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
    dur = dur or s.base or def.cd
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
        local dur = ReadOwnDuration(spellID) or CharDB.learned[spellID] or def.cd
        StartCD(me, spellID, dur, "msg")
        Send("CD:" .. spellID .. ":" .. floor(dur + 0.5))
    end)
end

-- The "is this cooldown running" flag stays readable in combat even though the
-- numbers don't. If the game says one of our own cooldowns is no longer running
-- while our timer still is, it was reset or reduced: mark it ready and tell the party.
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

function ns:HandleMessage(name, text)
    local kind, rest = strsplit(":", text, 2)
    if kind == "CD" then
        local id, dur = strsplit(":", rest or "")
        id, dur = tonumber(id), tonumber(dur)
        if id and dur and SPELLS[id] then
            StartCD(name, id, dur, "msg")
        end
    elseif kind == "RDY" then
        local id = tonumber(rest)
        local m = members[name]
        local s = m and id and m.spells[id]
        if s and s.start then
            s.start = nil
            Fire("READY", name, id)
        end
    elseif kind == "HI" then
        local m = GetMember(name)
        m.hasAddon = true
        for id, dur in string.gmatch(rest or "", "(%d+)=(%d+)") do
            id, dur = tonumber(id), tonumber(dur)
            if SPELLS[id] then
                local s = m.spells[id]
                if not s then
                    s = {}
                    m.spells[id] = s
                end
                s.known = true
                s.base = dur
            end
        end
    end
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
    local now = GetTime()
    for id, def in pairs(SPELLS) do
        local s = m.spells[id]
        if IsPlayerSpell(id) then
            if not s then
                s = {}
                m.spells[id] = s
            end
            s.known = true
            s.base = CharDB.learned[id] or def.cd
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
                GetMember(name, class)
            end
        end
    end
    for name, m in pairs(members) do
        if not present[name] and not m.test then
            members[name] = nil
        end
    end
    ns:RefreshSelf()
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
        for mi, f in ipairs(PREVIEW) do
            local m = GetMember(f[1], f[2])
            m.test = true
            for i, id in ipairs(f[3]) do
                local def = SPELLS[id]
                if def then
                    local s = { known = true, base = def.cd, dur = def.cd }
                    if (mi + i) % 3 ~= 0 then
                        s.start = now - def.cd * (0.1 + 0.17 * ((mi + i) % 5))
                        s.loop = true
                    end
                    m.spells[id] = s
                end
            end
        end
    end
    ns:Refresh()
    SyncConfig()
end

function ns:SetEditMode(on)
    ns.editMode = on and true or false
    ns:Refresh()
    SyncConfig()
end

---------------------------------------------------------------------------
-- Cooldown display (one movable frame, or one per category)
---------------------------------------------------------------------------

local function FmtTime(rem)
    if rem >= 60 then return format("%d:%02d", floor(rem / 60), floor(rem % 60)) end
    if rem >= 10 then return format("%d", ceil(rem)) end
    return format("%.1f", rem)
end

local function ApplyPos(g)
    g:ClearAllPoints()
    local p = DB.pos[g.key]
    if p then
        g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        local d = DEFAULT_POS[g.key] or DEFAULT_POS.ALL
        g:SetPoint("TOPLEFT", UIParent, "CENTER", d[1], d[2])
    end
end

-- If another addon (EllesmereUI's unlock mode, for example) re-anchored a group to the
-- screen center, convert it back to a top-left anchor in the same spot so it grows
-- downward and the position is saved. Groups anchored to other frames are left alone.
local function NormalizeGroup(g)
    if g.moving or g:GetNumPoints() ~= 1 then return end
    local point, relTo = g:GetPoint()
    if point == "TOPLEFT" or relTo ~= UIParent then return end
    local left, top = g:GetLeft(), g:GetTop()
    if left and top then
        DB.pos[g.key] = { left, top }
        ApplyPos(g)
    end
end

local function GetGroup(key)
    local g = groups[key]
    if g then return g end
    g = CreateFrame("Frame", "SaltyMPlusHelperGroup" .. key, UIParent, "BackdropTemplate")
    g.key = key
    g.rows = {}
    g:SetSize(WIDTH, 60)
    g:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    g:SetClampedToScreen(true)
    g:SetMovable(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnDragStart", function(self)
        if ns.editMode then
            self.moving = true
            self:StartMoving()
        end
    end)
    g:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.moving = false
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then DB.pos[self.key] = { left, top } end
        ApplyPos(self) -- re-anchor to the top-left so the group grows downward
    end)
    g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.title:SetPoint("TOPLEFT", 8, -6)
    g.empty = g:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    g.empty:SetText("No cooldowns yet")
    g:SetScale(DB.scale)
    ApplyPos(g)
    g:Hide()
    groups[key] = g
    return g
end

local function GetRow(g, i)
    local r = g.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, g)
    r:SetSize(WIDTH - 12, ROW_H)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_H - 2, ROW_H - 2)
    r.icon:SetPoint("LEFT", 0, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cd = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
    r.cd:SetAllPoints(r.icon)
    r.cd:SetHideCountdownNumbers(true)
    r.cd:SetDrawEdge(false)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.label:SetWidth(WIDTH - 12 - ROW_H - 62)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.time = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.time:SetPoint("RIGHT", 0, 0)
    r.time:SetJustifyH("RIGHT")
    g.rows[i] = r
    return r
end

local function LayoutGroup(g, list)
    local edit = ns.editMode
    if g.edit ~= edit then
        g.edit = edit
        g:EnableMouse(edit) -- click-through unless you are moving things
        if edit then
            g:SetBackdropColor(0.05, 0.1, 0.2, 0.92)
            g:SetBackdropBorderColor(0.2, 0.6, 1, 1)
        else
            g:SetBackdropColor(0.05, 0.05, 0.08, 0.85)
            g:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    local showTitle = DB.titles or edit
    local hh = showTitle and HEADER_H or 4
    local suffix = ""
    if edit then
        suffix = "  |cff66ccffdrag to move|r"
    elseif ns:SyncBlocked() then
        suffix = "  |cffffaa33estimating|r" -- party timers are base cooldowns while sync is blocked
    end
    g.title:SetShown(showTitle)
    g.title:SetText(TITLES[g.key] .. suffix)

    for i, e in ipairs(list) do
        local r = GetRow(g, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", g, "TOPLEFT", 6, -(hh + (i - 1) * ROW_H))
        local spellName, icon = SpellInfo(e.id)
        r.icon:SetTexture(icon)
        local color = e.class and RAID_CLASS_COLORS[e.class]
        local hex = color and color:GenerateHexColor() or "ffffffff"
        r.label:SetText("|c" .. hex .. e.name .. "|r  |cffaaaaaa" .. spellName .. "|r")
        if e.rem > 0 then
            r.icon:SetDesaturated(true)
            r.time:SetText(FmtTime(e.rem))
            r.time:SetTextColor(1, 0.3, 0.3)
            if r.cdStart ~= e.start then
                r.cd:SetCooldown(e.start, e.dur)
                r.cdStart = e.start
            end
        else
            r.icon:SetDesaturated(false)
            r.time:SetText("READY")
            r.time:SetTextColor(0.3, 1, 0.3)
            if r.cdStart then
                r.cd:Clear()
                r.cdStart = nil
            end
        end
        r:Show()
    end
    for i = #list + 1, #g.rows do
        g.rows[i]:Hide()
        g.rows[i].cdStart = nil
    end

    g.empty:ClearAllPoints()
    g.empty:SetPoint("TOPLEFT", 8, -(hh + 3))
    g.empty:SetShown(#list == 0)
    g:SetHeight(hh + max(#list, 1) * ROW_H + 6)
    NormalizeGroup(g)
end

function ns:Refresh()
    if not DB then return end
    local now = GetTime()
    local forced = ns.editMode or EUIUnlockActive()
    local visible = DB.shown or forced

    local list = {}
    for _, m in pairs(members) do
        for id, s in pairs(m.spells) do
            -- Preview cooldowns restart a few seconds after they finish.
            if m.test and s.loop and s.start and now > s.start + s.dur + 4 then
                s.start = now
            end
            if s.known then
                local rem = 0
                if s.start and s.dur then rem = max(0, s.start + s.dur - now) end
                if rem > 0 or DB.showReady then
                    list[#list + 1] = {
                        name = m.name, class = m.class, id = id, rem = rem,
                        start = s.start, dur = s.dur, cat = SPELLS[id].cat,
                    }
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.cat ~= b.cat then return CAT_ORDER[a.cat] < CAT_ORDER[b.cat] end
        if (a.rem > 0) ~= (b.rem > 0) then return a.rem == 0 end
        if a.rem ~= b.rem then return a.rem < b.rem end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)

    local buckets = {}
    for _, e in ipairs(list) do
        local key = DB.split and e.cat or "ALL"
        local b = buckets[key]
        if not b then
            b = {}
            buckets[key] = b
        end
        b[#b + 1] = e
    end

    local active, activeSet = DB.split and SPLIT_KEYS or ALL_KEYS, {}
    for _, key in ipairs(active) do
        activeSet[key] = true
        local g = GetGroup(key)
        local b = buckets[key] or {}
        if visible and (#b > 0 or forced) then
            LayoutGroup(g, b)
            g:Show()
        else
            g:Hide()
        end
    end
    for key, g in pairs(groups) do
        if not activeSet[key] then g:Hide() end
    end
end

function ns:ResetPositions()
    DB.pos = {}
    for _, g in pairs(groups) do ApplyPos(g) end
end

function ns:SetScaleAll(new)
    new = min(2, max(0.5, floor(new * 10 + 0.5) / 10))
    local old = DB.scale
    if new == old then return end
    -- Keep each group visually in place while its scale changes.
    for key, g in pairs(groups) do
        local left, top = g:GetLeft(), g:GetTop()
        if left and top then DB.pos[key] = { left * old / new, top * old / new } end
    end
    DB.scale = new
    for _, g in pairs(groups) do
        g:SetScale(new)
        ApplyPos(g)
    end
    SyncConfig()
end

---------------------------------------------------------------------------
-- EllesmereUI integration: register each group with its /unlock mode.
-- (Uses only EllesmereUI's public registration API; none of its code is copied.)
---------------------------------------------------------------------------

local function Safe(fn)
    return function(...)
        local ok, a, b, c = pcall(fn, ...)
        if ok then return a, b, c end
    end
end

function ns:UnregisterEllesmere()
    local e = _G.EllesmereUI
    if e and e.UnregisterUnlockElement then
        for key in pairs(euiRegistered) do
            pcall(e.UnregisterUnlockElement, e, EUI_PREFIX .. key)
        end
    end
    wipe(euiRegistered)
end

function ns:RegisterEllesmere()
    local e = _G.EllesmereUI
    if not (DB and DB.euiUnlock and e and e.RegisterUnlockElements) then return false end
    ns:UnregisterEllesmere()
    local elems = {}
    for i, key in ipairs(DB.split and SPLIT_KEYS or ALL_KEYS) do
        elems[#elems + 1] = {
            key = EUI_PREFIX .. key,
            label = "SaltyM+ " .. TITLES[key],
            name = "SaltyM+ " .. TITLES[key],
            order = 900 + i,
            noResize = true,
            getFrame = Safe(function() return GetGroup(key) end),
            getSize = Safe(function()
                local g = groups[key]
                return g and g:GetWidth() or WIDTH, g and g:GetHeight() or 60
            end),
            -- The frame itself is the source of truth, so the position is read back from it.
            loadPosition = Safe(function()
                local g = groups[key]
                local cx, cy = g and g:GetCenter()
                if not cx then return nil end
                local es = g:GetEffectiveScale() / UIParent:GetEffectiveScale()
                return {
                    point = "CENTER", relPoint = "CENTER",
                    x = cx * es - UIParent:GetWidth() / 2,
                    y = cy * es - UIParent:GetHeight() / 2,
                }
            end),
            savePosition = Safe(function()
                C_Timer.After(0.1, function()
                    local g = groups[key]
                    if g then NormalizeGroup(g) end
                end)
            end),
            applyPosition = Safe(function()
                local g = groups[key]
                if g then ApplyPos(g) end
            end),
            clearPosition = Safe(function()
                DB.pos[key] = nil
                local g = groups[key]
                if g then ApplyPos(g) end
            end),
        }
        euiRegistered[key] = true
    end
    local ok = pcall(e.RegisterUnlockElements, e, elems)
    if not ok then wipe(euiRegistered) end
    return ok
end

---------------------------------------------------------------------------
-- BigWigs integration: know when an encounter is running (addon messages are
-- blocked then, so party timers switch to estimates).
---------------------------------------------------------------------------

function ns:RegisterBigWigs()
    if ns.bwRegistered then return true end
    local loader = _G.BigWigsLoader
    if not (loader and loader.RegisterMessage) then return false end
    local function engage() ns.inEncounter = true end
    local function done()
        ns.inEncounter = false
        QueueHello(2)
    end
    local ok = pcall(function()
        loader.RegisterMessage(ns, "BigWigs_OnBossEngage", engage)
        loader.RegisterMessage(ns, "BigWigs_OnBossWin", done)
        loader.RegisterMessage(ns, "BigWigs_OnBossWipe", done)
    end)
    ns.bwRegistered = ok
    return ok
end

local function TryIntegrations(attempt)
    attempt = attempt or 1
    local pending = false
    if _G.BigWigsLoader and not ns.bwRegistered then
        if not ns:RegisterBigWigs() then pending = true end
    end
    if DB.euiUnlock and _G.EllesmereUI and not next(euiRegistered) then
        if not ns:RegisterEllesmere() then pending = true end
    end
    if pending and attempt < 6 then
        C_Timer.After(2, function() TryIntegrations(attempt + 1) end)
    end
end

function ns:StatusText()
    local bw = _G.BigWigsLoader and (ns.bwRegistered and "linked" or "found") or "not found"
    local eui = "not found"
    if _G.EllesmereUI then
        eui = next(euiRegistered) and "linked" or (DB.euiUnlock and "found" or "off")
    end
    return format("BigWigs: %s   EllesmereUI: %s   Sync: %s", bw, eui, ns:SyncBlocked() and "paused" or "live")
end

---------------------------------------------------------------------------
-- Config window (/salty)
---------------------------------------------------------------------------

local config
local checks = {}

local CHECK_DEFS = {
    { "Preview with a test party",        function() return ns.preview end,   function(v) ns:SetPreview(v) end },
    { "Move mode (drag the blue frames)", function() return ns.editMode end,  function(v) ns:SetEditMode(v) end },
    { "Split into groups by category",    function() return DB.split end,     function(v)
        DB.split = v
        if next(euiRegistered) then ns:RegisterEllesmere() end
        ns:Refresh()
    end },
    { "Show ready cooldowns",             function() return DB.showReady end, function(v) DB.showReady = v; ns:Refresh() end },
    { "Show group titles",                function() return DB.titles end,    function(v) DB.titles = v; ns:Refresh() end },
    { "Show cooldown window",             function() return DB.shown end,     function(v) DB.shown = v; ns:Refresh() end },
    { "Use EllesmereUI /unlock mode",     function() return DB.euiUnlock end, function(v)
        DB.euiUnlock = v
        if v then
            if not ns:RegisterEllesmere() and _G.EllesmereUI then Print("Could not register with EllesmereUI.") end
        else
            ns:UnregisterEllesmere()
        end
        SyncConfig()
    end },
}

SyncConfig = function()
    if not config then return end
    for _, cb in ipairs(checks) do
        cb:SetChecked(cb.get() and true or false)
    end
    config.scaleText:SetText(format("%.1f", DB.scale))
    config.status:SetText(ns:StatusText())
end

local function CreateConfig()
    config = CreateFrame("Frame", "SaltyMPlusHelperConfig", UIParent, "BackdropTemplate")
    config:SetSize(300, 424)
    config:SetPoint("CENTER", UIParent, "CENTER", 330, 0)
    config:SetFrameStrata("DIALOG")
    config:SetClampedToScreen(true)
    config:SetMovable(true)
    config:EnableMouse(true)
    config:RegisterForDrag("LeftButton")
    config:SetScript("OnDragStart", config.StartMoving)
    config:SetScript("OnDragStop", config.StopMovingOrSizing)
    config:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    config:SetBackdropColor(0.06, 0.06, 0.09, 0.95)
    config:SetBackdropBorderColor(0.2, 0.6, 1, 1)

    local logo = config:CreateTexture(nil, "ARTWORK")
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 10, -8)
    logo:SetTexture(LOGO)

    local title = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("SaltyM+Helper")

    local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local help = config:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 14, -52)
    help:SetWidth(272)
    help:SetJustifyH("LEFT")
    help:SetText("A test party is shown while this window is open. Drag the blue frames to place them where you like.")

    local y = -82
    for _, def in ipairs(CHECK_DEFS) do
        local cb = CreateFrame("CheckButton", nil, config, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", 12, y)
        cb.get = def[2]
        local set = def[3]
        cb:SetScript("OnClick", function(self)
            set(self:GetChecked() and true or false)
        end)
        local label = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(def[1])
        checks[#checks + 1] = cb
        y = y - 28
    end

    local scaleLabel = config:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLabel:SetPoint("TOPLEFT", 18, y - 8)
    scaleLabel:SetText("Scale")

    local minus = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    minus:SetSize(26, 22)
    minus:SetPoint("TOPLEFT", 90, y - 4)
    minus:SetText("-")
    minus:SetScript("OnClick", function() ns:SetScaleAll(DB.scale - 0.1) end)

    config.scaleText = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    config.scaleText:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    config.scaleText:SetWidth(40)

    local plus = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    plus:SetSize(26, 22)
    plus:SetPoint("LEFT", config.scaleText, "RIGHT", 0, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() ns:SetScaleAll(DB.scale + 0.1) end)

    config.status = config:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    config.status:SetPoint("BOTTOM", 0, 78)
    config.status:SetWidth(272)

    local reset = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    reset:SetSize(128, 24)
    reset:SetPoint("BOTTOMLEFT", 14, 44)
    reset:SetText("Reset positions")
    reset:SetScript("OnClick", function() ns:ResetPositions() end)

    local sync = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    sync:SetSize(128, 24)
    sync:SetPoint("BOTTOMRIGHT", -14, 44)
    sync:SetText("Sync with party")
    sync:SetScript("OnClick", function()
        Print(SendHello() and "Sync sent." or "Could not send (not in a group, or messages are blocked right now).")
    end)

    local done = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
    done:SetSize(272, 24)
    done:SetPoint("BOTTOM", 0, 14)
    done:SetText("Done")
    done:SetScript("OnClick", function() config:Hide() end)

    config:SetScript("OnShow", function()
        ns.preview = true
        ns.editMode = true
        ns:SetPreview(true)
        ns:SetEditMode(true)
    end)
    config:SetScript("OnHide", function()
        ns:SetPreview(false)
        ns:SetEditMode(false)
    end)
    tinsert(UISpecialFrames, "SaltyMPlusHelperConfig") -- Esc closes it
end

function ns:ToggleConfig()
    if not config then CreateConfig() end
    if config:IsShown() then config:Hide() else config:Show() end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_SALTYMPLUSHELPER1 = "/salty"
SLASH_SALTYMPLUSHELPER2 = "/smh"
SLASH_SALTYMPLUSHELPER3 = "/saltym"
SlashCmdList["SALTYMPLUSHELPER"] = function(msg)
    local cmd, arg = strsplit(" ", strlower(strtrim(msg or "")), 2)
    if cmd == "" or cmd == "config" or cmd == "options" then
        ns:ToggleConfig()
    elseif cmd == "show" then
        DB.shown = true
        ns:Refresh()
        SyncConfig()
    elseif cmd == "hide" then
        DB.shown = false
        ns:Refresh()
        SyncConfig()
    elseif cmd == "toggle" then
        DB.shown = not DB.shown
        ns:Refresh()
        SyncConfig()
    elseif cmd == "test" or cmd == "preview" then
        ns:SetPreview(not ns.preview)
    elseif cmd == "unlock" or cmd == "move" then
        ns:SetEditMode(not ns.editMode)
    elseif cmd == "lock" then
        ns:SetEditMode(false)
    elseif cmd == "ready" then
        DB.showReady = not DB.showReady
        ns:Refresh()
        SyncConfig()
    elseif cmd == "scale" then
        local v = tonumber(arg)
        if v then
            ns:SetScaleAll(v)
        else
            Print("Usage: /salty scale 0.5-2")
        end
    elseif cmd == "sync" then
        Print(SendHello() and "Sync sent." or "Could not send (not in a group, or messages are blocked right now).")
    elseif cmd == "status" then
        Print(ns:StatusText())
    elseif cmd == "eui" then
        DB.euiUnlock = not DB.euiUnlock
        if DB.euiUnlock then
            Print(ns:RegisterEllesmere() and "EllesmereUI unlock mode: registered." or "EllesmereUI not found (or registration failed).")
        else
            ns:UnregisterEllesmere()
            Print("EllesmereUI unlock mode: off. /reload to fully detach.")
        end
        SyncConfig()
    elseif cmd == "reset" then
        ns:ResetPositions()
        Print("Positions reset.")
    else
        Print("/salty opens the preview window. Also: show, hide, toggle, test, move, lock, ready, scale <0.5-2>, sync, status, eui, reset")
    end
end

---------------------------------------------------------------------------
-- Addon compartment (the addon list button next to the minimap) uses the logo too
---------------------------------------------------------------------------

function SaltyMPlusHelper_OnAddonCompartmentClick()
    ns:ToggleConfig()
end

function SaltyMPlusHelper_OnAddonCompartmentEnter(_, frame)
    if not frame then return end
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("SaltyM+Helper")
    GameTooltip:AddLine("Click to open the preview and layout window.", 1, 1, 1)
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
    local defaults = {
        scale = 1, shown = true, showReady = true, split = false, titles = true, euiUnlock = true,
    }
    for k, v in pairs(defaults) do
        if DB[k] == nil then DB[k] = v end
    end
    DB.pos = DB.pos or {}
    CharDB.learned = CharDB.learned or {}

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

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
    ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "party1", "party2", "party3", "party4")
    Print("loaded. Type /salty to open the preview and layout window.")
end

function handlers.PLAYER_ENTERING_WORLD()
    ns:ScanRoster()
    C_Timer.After(3, function()
        ns:ScanRoster()
        QueueHello(0)
    end)
    TryIntegrations(1)
end

function handlers.GROUP_ROSTER_UPDATE()
    ns:ScanRoster()
    QueueHello(3)
end

function handlers.SPELLS_CHANGED()
    ns:RefreshSelf()
    QueueHello(3)
end
handlers.PLAYER_SPECIALIZATION_CHANGED = handlers.SPELLS_CHANGED

function handlers.ENCOUNTER_START() ns.inEncounter = true end

-- Messages are blocked during encounters and keys, so re-announce once they end.
function handlers.ENCOUNTER_END()
    ns.inEncounter = false
    QueueHello(2)
end
function handlers.CHALLENGE_MODE_COMPLETED() QueueHello(2) end
function handlers.PLAYER_REGEN_ENABLED()
    if needHello then
        needHello = false
        QueueHello(1)
    end
end

function handlers.CHAT_MSG_ADDON(prefix, text, _, sender)
    if prefix ~= PREFIX or issecret(text) or issecret(sender) then return end
    local name = ShortName(sender)
    if not name or name == UnitKey("player") then return end
    ns:HandleMessage(name, text)
end

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
    if issecret(unit) or issecret(spellID) or type(spellID) ~= "number" then return end
    if not SPELLS[spellID] then return end
    if unit == "player" then
        OnLocalCast(spellID)
    else
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
