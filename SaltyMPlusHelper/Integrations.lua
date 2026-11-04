-- Integrations.lua: finding party frames to attach to, EllesmereUI and BigWigs.
--
-- (Attaching to friendly nameplates was removed: Blizzard treats friendly player nameplates
-- inside dungeons and raids as "forbidden" frames that addons cannot anchor to.)

local ADDON, ns = ...
local issecret = ns.issecret

local EUI_PREFIX = "SMH_"
ns.euiRegistered = {}
local euiRegistered = ns.euiRegistered

---------------------------------------------------------------------------
-- Finding frames to anchor to
---------------------------------------------------------------------------

local function Usable(f)
    if not f then return false end
    local ok, vis = pcall(function()
        if f.IsForbidden and f:IsForbidden() then return false end
        return f:IsVisible()
    end)
    if not ok or issecret(vis) then return false end
    return vis and true or false
end

-- Known party-frame name patterns (%d = slot number). Blizzard's frames are checked first.
local PATTERNS = {
    "CompactPartyFrameMember%d",        -- Blizzard raid-style party frames
    "ElvUF_PartyGroup1UnitButton%d",    -- ElvUI
    "Grid2LayoutHeader1UnitButton%d",   -- Grid2
    "CellPartyFrameHeaderUnitButton%d", -- Cell
}
local PLAYER_FRAMES = { "EllesmereUIUnitFrames_Player", "PlayerFrame", "ElvUF_Player" }

-- EllesmereUI keeps its party frames as a list of secure buttons on its Raid Frames module.
local function EllesmerePartyButtons()
    local eui = _G.EllesmereUI
    local rf = eui and eui._ModuleNS and eui._ModuleNS.EllesmereUIRaidFrames
    local list = rf and rf._partyAllButtons
    return type(list) == "table" and list or nil
end

local function FrameUnit(f)
    local ok, u = pcall(function()
        return f.unit or f.displayedUnit or f.unitToken or (f.GetAttribute and f:GetAttribute("unit"))
    end)
    if ok and type(u) == "string" and not issecret(u) then return u end
end

local function SameUnit(u, unit)
    if u == unit then return true end
    local ok, r = pcall(UnitIsUnit, u, unit)
    if not ok or issecret(r) then return false end
    return r and true or false
end

local function Search(unit)
    local custom = ns.db.customFrame
    local patterns = PATTERNS
    if custom and custom:find("%%d") then
        patterns = { custom, unpack(PATTERNS) }
    end
    if unit == "player" then
        for _, name in ipairs(PLAYER_FRAMES) do
            local f = _G[name]
            if Usable(f) then return f, name end
        end
    end
    local slot = tonumber(unit:match("^party(%d)$"))
    local euiButtons = EllesmerePartyButtons()
    if euiButtons then
        for _, btn in ipairs(euiButtons) do
            if Usable(btn) then
                local u = FrameUnit(btn)
                if u and SameUnit(u, unit) then return btn, "EllesmereUI party frame" end
            end
        end
    end
    for pi, pattern in ipairs(patterns) do
        for i = 1, 5 do
            local name = format(pattern, i)
            local f = _G[name]
            if Usable(f) then
                local u = FrameUnit(f)
                if u then
                    if SameUnit(u, unit) then return f, name end
                elseif custom and pi == 1 and patterns ~= PATTERNS and slot == i then
                    return f, name -- custom frames without a unit field: slot N is partyN
                end
            end
        end
    end
    -- Blizzard's non-raid-style party frames
    local pf = _G.PartyFrame
    if pf and slot then
        for i = 1, 4 do
            local f = pf["MemberFrame" .. i]
            if Usable(f) then
                local u = FrameUnit(f)
                if u and SameUnit(u, unit) then return f, "PartyFrame.MemberFrame" .. i end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Generic scan: any visible secure button whose "unit" attribute is you or a party member.
-- This is how KiraUI finds party frames, so it works with any unit frame addon (Cell, ElvUI,
-- VuhDo, Grid2, Danders, EllesmereUI, Blizzard...). It walks the frame list in small slices so it
-- never causes a hitch, and is only used when the known frame names did not match.
---------------------------------------------------------------------------

local WANT_UNITS = { player = true, party1 = true, party2 = true, party3 = true, party4 = true }
local scan = { found = {}, pending = {}, cursor = nil, running = false, last = nil }
ns.frameScan = scan

local function SizeOf(f)
    local ok, w, h = pcall(f.GetSize, f)
    if ok and not issecret(w) and not issecret(h) and type(w) == "number" and type(h) == "number"
        and w > 0 and h > 0 then
        return w, h
    end
end

local function Candidate(f)
    -- every widget read below can come back secret or error on protected frames
    local ok, forbidden, otype, vis, name, u = pcall(function()
        if f:IsForbidden() then return true end
        return false, f:GetObjectType(), f:IsVisible(), f:GetName(), f:GetAttribute("unit")
    end)
    if not ok or forbidden or issecret(otype) or otype ~= "Button" then return end
    if issecret(vis) or not vis then return end
    if type(name) == "string" and not issecret(name) and name:sub(1, 13) == "SaltyMPlusHel" then return end
    if issecret(u) or type(u) ~= "string" then return end
    u = u:lower()
    if not WANT_UNITS[u] then return end
    local list = scan.pending[u]
    if not list then
        list = {}
        scan.pending[u] = list
    end
    list[#list + 1] = f
end

local function Area(f)
    local w, h = SizeOf(f)
    return w and w * h or 0
end

local function FinishScan()
    local found, sizes = {}, {}
    for _, unit in ipairs({ "party1", "party2", "party3", "party4" }) do
        local best, bestArea
        for _, f in ipairs(scan.pending[unit] or {}) do
            local a = Area(f)
            if a > 0 and (not best or a > bestArea) then best, bestArea = f, a end
        end
        if best then
            found[unit] = best
            local w, h = SizeOf(best)
            sizes[#sizes + 1] = { w, h }
        end
    end
    -- your own frame: prefer one the size of the party frames (EllesmereUI, Cell... list you in
    -- the party), otherwise the biggest one (the normal player frame)
    local list, pick = scan.pending.player or {}, nil
    if #sizes > 0 then
        local pw, ph = sizes[1][1], sizes[1][2]
        for _, f in ipairs(list) do
            local w, h = SizeOf(f)
            if w and math.abs(w - pw) <= pw * 0.1 and math.abs(h - ph) <= ph * 0.1 then
                pick = f
                break
            end
        end
    end
    if not pick then
        local bestArea = 0
        for _, f in ipairs(list) do
            local a = Area(f)
            if a > bestArea then pick, bestArea = f, a end
        end
    end
    found.player = pick
    scan.found, scan.pending, scan.cursor = found, {}, nil
    scan.running, scan.last = false, GetTime()
end

local driver
local function ScanStep()
    local start = debugprofilestop()
    local f, n = scan.cursor, 0
    while true do
        f = EnumerateFrames(f)
        if not f then
            FinishScan()
            return
        end
        pcall(Candidate, f)
        n = n + 1
        if n % 64 == 0 and debugprofilestop() - start > 2.5 then break end
    end
    scan.cursor = f
end

function ns:RequestFrameScan(force)
    if scan.running then return end
    if not force then
        if not ns.db.scanFrames then return end
        if scan.last and GetTime() - scan.last < 8 then return end
    end
    scan.running, scan.cursor, scan.pending = true, nil, {}
    if not driver then
        driver = CreateFrame("Frame")
        scan.driver = driver
        driver:SetScript("OnUpdate", function()
            if scan.running then ScanStep() end
        end)
    end
end

local frameCache = {}

function ns:FindPartyFrame(unit)
    local now = GetTime()
    local c = frameCache[unit]
    if c and now - c.t < 1.5 and (not c.f or Usable(c.f)) then return c.f, c.name end
    local ok, f, name = pcall(Search, unit)
    if not ok then f, name = nil, nil end
    if not f and ns.db.scanFrames then
        local sf = scan.found[unit]
        if sf and Usable(sf) then f, name = sf, "scanned party frame" end
        ns:RequestFrameScan()
    end
    frameCache[unit] = { f = f, name = name, t = now }
    return f, name
end

function ns:ClearFrameCache()
    wipe(frameCache)
    scan.last = nil
end

-- The frame to attach a member's cooldowns to, given the user's "attach to" choice.
-- Returns nil when nothing is available, so the caller shows them in the window instead.
function ns:ResolveAnchor(unit)
    local attach = ns.db.attach
    if attach ~= "WINDOW" then
        local f, name = ns:FindPartyFrame(unit)
        if f then return f, name end
    end
    return nil
end

-- One line per party member describing what they are attached to (for the settings window).
function ns:DescribeAnchors()
    local out = {}
    for _, e in ipairs(ns:GetSyncRoster()) do
        local text
        if ns.db.attach == "WINDOW" then
            text = "window"
        else
            local _, what = ns:ResolveAnchor(e.unit)
            text = what or "window (no frame found)"
        end
        out[#out + 1] = { name = e.name, class = e.class, text = text }
    end
    return out
end

---------------------------------------------------------------------------
-- KiraUI plugin: it already ships crowd-control bars, party cooldowns, interrupts and
-- externals built on Midnight 12.1's aura containers. We read which of its modules are on
-- (so two displays do not fight), and our CC tracker steps aside when its CC bars are on.
---------------------------------------------------------------------------

local KIRA_MODULES = {
    { "Party cooldowns", "PTCGetCfg" }, { "Interrupts", "IKGetCfg" }, { "CC bars", "CCBGetCfg" },
    { "Party stops", "PSTGetCfg" }, { "Externals", "ExtGetCfg" }, { "Healer externals", "HXGetCfg" },
}

function ns:KiraNS()
    local k = _G.KiraUIPlugin
    return type(k) == "table" and type(k.__ns) == "table" and k.__ns or nil
end

local function KiraModuleOn(kns, accessor)
    local fn = kns and kns[accessor]
    if type(fn) ~= "function" then return nil end -- module not present
    local ok, cfg = pcall(fn)
    if not ok or type(cfg) ~= "table" then return nil end
    return cfg.enable == true
end

-- { { label, on = true/false }, ... } for the KiraUI modules that exist.
function ns:KiraModuleList()
    local kns, out = ns:KiraNS(), {}
    if not kns then return out end
    for _, m in ipairs(KIRA_MODULES) do
        local on = KiraModuleOn(kns, m[2])
        if on ~= nil then out[#out + 1] = { label = m[1], on = on } end
    end
    return out
end

function ns:KiraCCBarsOn()
    local kns = ns:KiraNS()
    if not kns or kns.CCBUnavailable then return false end
    return KiraModuleOn(kns, "CCBGetCfg") == true
end

-- KiraUI's CC bars draw every crowd-control aura with the game's own widgets. These helpers feed
-- them: turn them on, and add the CC your class applies (Paralysis, Polymorph, Hex, ...).
function ns:KiraCCReady()
    local kns = ns:KiraNS()
    if not (kns and type(kns.CCBGetCfg) == "function") then return false, "KiraUI plugin not found." end
    if kns.CCBUnavailable then return false, "KiraUI's CC bars need Midnight 12.1 or newer." end
    return true
end

local function KiraCCConfig()
    local ok, why = ns:KiraCCReady()
    if not ok then return nil, why end
    local kns = ns:KiraNS()
    local good, cfg = pcall(kns.CCBGetCfg)
    if not good or type(cfg) ~= "table" or type(cfg.spells) ~= "table" then
        return nil, "Could not read KiraUI's CC bar settings."
    end
    return cfg, nil, kns
end

function ns:KiraEnableCC()
    local cfg, why, kns = KiraCCConfig()
    if not cfg then return false, why end
    cfg.enable = true
    if type(kns.CCBApply) == "function" then pcall(kns.CCBApply) end
    return true
end

-- Returns true, numberAdded  or  false, reason
function ns:KiraAddMyCC()
    local cfg, why, kns = KiraCCConfig()
    if not cfg then return false, why end
    local _, class = UnitClass("player")
    local have = {}
    for _, id in ipairs(cfg.spells) do have[id] = true end
    local added = 0
    for _, id in ipairs(ns.CC_BY_CLASS[class] or {}) do
        if not have[id] then
            cfg.spells[#cfg.spells + 1] = id
            have[id] = true
            added = added + 1
        end
    end
    if added > 0 and type(kns.CCBApply) == "function" then pcall(kns.CCBApply) end
    return true, added
end

function ns:OpenKiraSettings()
    local k = _G.KiraUIPlugin
    if type(k) == "table" and type(k.OpenConfig) == "function" then
        local ok = pcall(k.OpenConfig)
        return ok
    end
    return false
end

function ns:EUIUnlockActive()
    local e = _G.EllesmereUI
    if e and e.IsUnlockModeActive then
        local ok, v = pcall(e.IsUnlockModeActive)
        return (ok and v) and true or false
    end
    return false
end

---------------------------------------------------------------------------
-- EllesmereUI: register the movable windows with its /unlock mode.
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
    local db = ns.db
    if not (db and db.euiUnlock and e and e.RegisterUnlockElements) then return false end
    ns:UnregisterEllesmere()
    local elems = {}
    -- one entry per movable frame. getFrame creates the frame if it does not exist yet, so
    -- every module can be placed in unlock mode even before it has been shown.
    local function Add(key, order, getFrame)
        elems[#elems + 1] = {
            key = EUI_PREFIX .. key,
            label = "SaltyM+ " .. (ns.TITLES[key] or key),
            name = "SaltyM+ " .. (ns.TITLES[key] or key),
            order = order,
            noResize = true,
            getFrame = Safe(getFrame),
            getSize = Safe(function()
                local g = getFrame()
                return g and g:GetWidth() or 250, g and g:GetHeight() or 60
            end),
            -- The frame itself is the source of truth, so the position is read back from it.
            loadPosition = Safe(function()
                local g = getFrame()
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
                    local g = getFrame()
                    if g then ns.NormalizeGroup(g) end
                end)
            end),
            applyPosition = Safe(function()
                local g = getFrame()
                if g then ns.ApplyPos(g) end
            end),
            clearPosition = Safe(function()
                db.pos[key] = nil
                local g = getFrame()
                if g then ns.ApplyPos(g) end
            end),
        }
        euiRegistered[key] = true
    end
    for i, key in ipairs(db.split and ns.SPLIT_KEYS or ns.ALL_KEYS) do
        Add(key, 900 + i, function() return ns.GetGroup(key) end)
    end
    for i, key in ipairs(ns.EXTRA_KEYS) do
        Add(key, 950 + i, function()
            if key == "CCTRACK" then return ns.CC and ns.CC.Ensure and ns.CC.Ensure() end
            local make = ns.MP and ns.MP.creators and ns.MP.creators[key]
            return make and make()
        end)
    end
    local ok = pcall(e.RegisterUnlockElements, e, elems)
    if not ok then wipe(euiRegistered) end
    return ok
end

---------------------------------------------------------------------------
-- BigWigs: know when an encounter is running (addon messages are blocked then, so
-- other players' timers switch to estimates).
---------------------------------------------------------------------------

function ns:RegisterBigWigs()
    if ns.bwRegistered then return true end
    local loader = _G.BigWigsLoader
    if not (loader and loader.RegisterMessage) then return false end
    local function engage() ns.inEncounter = true end
    local function done()
        ns.inEncounter = false
        ns:QueueHello(2)
    end
    local ok = pcall(function()
        loader.RegisterMessage(ns, "BigWigs_OnBossEngage", engage)
        loader.RegisterMessage(ns, "BigWigs_OnBossWin", done)
        loader.RegisterMessage(ns, "BigWigs_OnBossWipe", done)
    end)
    ns.bwRegistered = ok
    return ok
end

function ns:TryIntegrations(attempt)
    attempt = attempt or 1
    local pending = false
    if _G.BigWigsLoader and not ns.bwRegistered then
        if not ns:RegisterBigWigs() then pending = true end
    end
    if ns.db.euiUnlock and _G.EllesmereUI and not next(euiRegistered) then
        if not ns:RegisterEllesmere() then pending = true end
    end
    if pending and attempt < 6 then
        C_Timer.After(2, function() ns:TryIntegrations(attempt + 1) end)
    end
end

function ns:IntegrationStatus()
    local bw = _G.BigWigsLoader and (ns.bwRegistered and "linked" or "found") or "not found"
    local eui = "not found"
    if _G.EllesmereUI then
        eui = next(euiRegistered) and "linked" or (ns.db.euiUnlock and "found" or "off")
    end
    local kira = ns:KiraNS() and "found" or "not found"
    return bw, eui, kira
end

function ns:StatusText()
    local bw, eui, kira = ns:IntegrationStatus()
    return format("BigWigs: %s   EllesmereUI: %s   KiraUI: %s   Sync: %s", bw, eui, kira,
        ns:SyncBlocked() and "paused" or "live")
end
