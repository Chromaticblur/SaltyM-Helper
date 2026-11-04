-- MythicPlus.lua: the "keystone pushing" tools, so one addon covers them:
--   * Combat text   : "+ COMBAT" / "- COMBAT" flashes in the middle of the screen
--   * Combat timer  : how long the current (or last) fight has run
--   * Run HUD       : key timer with +2 / +3 thresholds, enemy forces %, deaths and their time
--                     penalty, battle-res charges, personal best on completion
--   * Key helpers   : put your keystone in the pedestal for you, hide the Blizzard tracker
-- Everything here is written from scratch (the ideas come from what players expect of these
-- features). It only reads values the game gives addons freely and ignores anything the game
-- hides ("secret" values), so it keeps working under Midnight's addon restrictions.

local ADDON, ns = ...
local mp = {}
ns.MP = mp

-- Every font string gets a font the moment it exists: SetText on a font-less string is an error.
function mp.FS(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ns.ApplyFont(fs, size or 12)
    return fs
end
local issecret = ns.issecret or issecretvalue or function() return false end

local FLAT = "Interface\\Buttons\\WHITE8x8"
local floor, max, min, format = math.floor, math.max, math.min, string.format

local COLORS = {
    RED = { 1, 0.25, 0.2 }, GREEN = { 0.3, 1, 0.4 }, WHITE = { 1, 1, 1 }, GOLD = { 1, 0.82, 0.2 },
    CYAN = { 0.3, 0.9, 1 }, ORANGE = { 1, 0.6, 0.1 }, PURPLE = { 0.75, 0.45, 1 },
}
ns.TEXT_COLORS = COLORS
local function RGB(key) local c = COLORS[key] or COLORS.WHITE; return c[1], c[2], c[3] end

local DEFAULT_POS = { CTEXT = { -150, 200 }, CTIMER = { -60, 140 }, MPHUD = { 420, 160 } }
local BREZ_SPELL = 20484

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function ApplyP(g)
    g:ClearAllPoints()
    local p = ns.db.pos[g.key]
    if p then
        g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        local d = DEFAULT_POS[g.key]
        g:SetPoint("TOPLEFT", UIParent, "CENTER", d[1], d[2])
    end
end

mp.frames, mp.updaters, mp.slowUpdaters = {}, {}, {}
mp.creators = {} -- key -> function that creates (or returns) that movable frame
mp.DEFAULT_POS = DEFAULT_POS

local function NewFrame(key, w, h)
    local g = ns.NewBackdropFrame("SaltyMPlusHelper" .. key)
    mp.frames[#mp.frames + 1] = g
    g:SetSize(w, h)
    ns.MakeMovable(g, key)
    ApplyP(g)
    g:SetFrameStrata("MEDIUM")
    g:Hide()
    return g
end

-- background: faint (set by the slider) normally, blue "drag me" look in move mode
local function Look(g, bgAlpha)
    if ns.editMode then
        g:SetBackdropColor(0.05, 0.1, 0.2, 0.92)
        g:SetBackdropBorderColor((ns.EditBorder or function() return 0.2, 0.6, 1, 1 end)(g))
    else
        g:SetBackdropColor(0.05, 0.05, 0.08, bgAlpha)
        g:SetBackdropBorderColor(0, 0, 0, bgAlpha > 0 and ns.db.borderAlpha or 0)
    end
    if g.edit ~= ns.editMode then
        g.edit = ns.editMode
        g:EnableMouse(ns.editMode and true or false) -- click-through unless you are moving things
    end
end

mp.NewFrame, mp.ApplyP, mp.Look, mp.RGB = NewFrame, ApplyP, Look, RGB

local function Clock(t, tenths)
    if t < 0 then t = 0 end
    local m = floor(t / 60)
    local s = t - m * 60
    if tenths then return format("%d:%04.1f", m, s) end
    return format("%d:%02d", m, floor(s))
end
mp.Clock = Clock

local function InGroupNow(when)
    if when == "ALWAYS" then return true end
    if when == "DUNGEON" then
        local inInstance, kind = IsInInstance()
        return inInstance and kind == "party"
    end
    return IsInGroup()
end

---------------------------------------------------------------------------
-- 1. combat text
---------------------------------------------------------------------------

local ct = { frame = nil }
mp.ct = ct

local function CTFrame()
    if ct.frame then return ct.frame end
    local g = NewFrame("CTEXT", 300, 56)
    g.text = mp.FS(g)
    g.text:SetPoint("CENTER")
    ct.frame = g
    return g
end

function ct:Flash(text, colorKey, classColor)
    if ns.db and ns.db.syncOnly then return end
    local db = ns.db
    local g = CTFrame()
    ns.ApplyFont(g.text, db.ctSize)
    g.text:SetText(text)
    if classColor then
        local _, class = UnitClass("player")
        g.text:SetTextColor(ns.ClassRGB(class))
    else
        g.text:SetTextColor(RGB(colorKey))
    end
    ct.startedAt = GetTime()
    ct.endsAt = ct.startedAt + max(0.5, db.ctDuration)
    g:Show()
end

function ct:Update(now)
    local g = ct.frame
    if not g then return end
    local db = ns.db
    if ns.editMode then
        ns.ApplyFont(g.text, db.ctSize)
        g.text:SetText(db.ctEnterText)
        g.text:SetTextColor(RGB(db.ctEnterColor))
        g.text:SetAlpha(1)
        Look(g, 0)
        g:Show()
        return
    end
    Look(g, 0)
    if not ct.endsAt then g:Hide(); return end
    if now >= ct.endsAt then
        ct.endsAt = nil
        g:Hide()
        return
    end
    local fadeIn = min(1, (now - ct.startedAt) / 0.12)
    local fadeOut = min(1, (ct.endsAt - now) / 0.7)
    g.text:SetAlpha(min(fadeIn, fadeOut))
    g:Show()
end

function mp:TestText()
    local db = ns.db
    ct:Flash(db.ctEnterText, db.ctEnterColor)
    C_Timer.After(db.ctDuration + 0.3, function()
        ct:Flash(db.ctLeaveText, db.ctLeaveColor)
    end)
end

local function CombatChanged(entering)
    local db = ns.db
    if not db or not db.ctEnabled then return end
    local when = db.ctWhen
    if when == "ALWAYS" and db.ctOnlyGroup then when = "GROUP" end
    if not InGroupNow(when) then return end
    if entering then
        if not db.ctEnter then return end
        ct:Flash(db.ctEnterText, db.ctEnterColor, db.ctEnterClass)
        if db.ctSound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
    else
        if not db.ctLeave then return end
        ct:Flash(db.ctLeaveText, db.ctLeaveColor, db.ctLeaveClass)
    end
end

---------------------------------------------------------------------------
-- 2. combat timer
---------------------------------------------------------------------------

local cmb = { frame = nil, start = nil, last = nil, hideAt = nil }
mp.cmb = cmb

local function CMBFrame()
    if cmb.frame then return cmb.frame end
    local g = NewFrame("CTIMER", 120, 30)
    g.text = mp.FS(g)
    g.text:SetPoint("CENTER")
    cmb.frame = g
    return g
end

function cmb:Update(now)
    local db = ns.db
    local g = cmb.frame
    if not g and db.cmbEnabled then g = CMBFrame() end
    if not g then return end
    if not db.cmbEnabled then g:Hide(); return end

    local text, alpha
    if ns.editMode or ns.preview then
        text, alpha = Clock(42, db.cmbTenths), 1
    elseif not InGroupNow(db.cmbWhen) then
        g:Hide(); return
    elseif cmb.start then
        text, alpha = Clock(now - cmb.start, db.cmbTenths), 1
    elseif db.cmbShowLast and cmb.last and (db.cmbHideDelay >= 60 or now < (cmb.hideAt or 0)) then
        text, alpha = Clock(cmb.last, db.cmbTenths), 0.6 -- the fight that just ended, dimmed
    else
        g:Hide(); return
    end

    ns.ApplyFont(g.text, db.cmbSize)
    g.text:SetText(text)
    g.text:SetTextColor(RGB(db.cmbColor))
    g.text:SetAlpha(alpha)
    local w = max(70, g.text:GetStringWidth() + 24)
    g:SetSize(w, db.cmbSize + 14)
    Look(g, db.cmbBg)
    g:Show()
end

local function CMBStart()
    cmb.start = GetTime()
    cmb.hideAt = nil
end

local function CMBStop()
    if not cmb.start then return end
    local now = GetTime()
    cmb.last = now - cmb.start
    cmb.start = nil
    cmb.hideAt = now + (ns.db and ns.db.cmbHideDelay or 5)
end

---------------------------------------------------------------------------
-- 3. Mythic+ run HUD
---------------------------------------------------------------------------

local run = { active = false }
mp.run = run
local hud

local PREVIEW_RUN = {
    active = true, preview = true, name = "Test Dungeon", level = 12, limit = 1800,
    elapsed = 872, deaths = 2, timeLost = 10, forces = 62.4,
    brez = { cur = 1, max = 2, nextIn = 83 },
    affixText = "Fortified, Xal'atath's Bargain",
    objs = {
        { name = "First Boss", done = true, elapsed = 410, best = 430 },
        { name = "Second Boss", done = true, elapsed = 905, best = 870 },
        { name = "Final Boss", done = false },
    },
}

local function Num(v)
    if type(v) == "number" and not issecret(v) then return v end
end

local function ReadForces()
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then return end
    local ok, _, _, num = pcall(C_Scenario.GetStepInfo)
    num = ok and Num(num)
    if not num then return end
    for i = num, 1, -1 do
        local good, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if good and type(info) == "table" and info.isWeightedProgress == true then
            local qs = info.quantityString
            if type(qs) == "string" and not issecret(qs) then
                local pct = tonumber(qs:match("(%d+%.?%d*)%%"))
                local q0, t0 = Num(info.quantity), Num(info.totalQuantity)
                if q0 and t0 and t0 > 1 then run.fq, run.ft = q0, t0 end
                if pct then return pct end
            end
            local q, total = Num(info.quantity), Num(info.totalQuantity)
            if q and total and total > 1 then run.fq, run.ft = q, total end
            if q and total and total > 0 then return q / total * 100 end
            return
        end
    end
end

-- Boss objectives: the kill time is stamped when we see the objective flip to done (same
-- limitation as every timer addon: after a /reload mid-run, earlier kills have no time).
local function ReadObjectives()
    if not (C_Scenario and C_Scenario.GetStepInfo and C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo) then return end
    local ok, _, _, num = pcall(C_Scenario.GetStepInfo)
    num = ok and Num(num)
    if not num then return end
    run.objs = run.objs or {}
    local first = not run.objsRead
    local idx = 0
    for i = 1, num do
        local good, info = pcall(C_ScenarioInfo.GetCriteriaInfo, i)
        if good and type(info) == "table" then
            local weighted = info.isWeightedProgress
            if issecret(weighted) then weighted = true end
            if weighted ~= true then
                idx = idx + 1
                local o = run.objs[idx]
                if not o then o = {}; run.objs[idx] = o end
                local d = info.description
                if type(d) == "string" and not issecret(d) then o.name = d end
                local done = info.completed
                if issecret(done) then done = nil end
                if done == true and not o.done then
                    o.done = true
                    if not first then o.elapsed = (run.elapsed or 0) end
                end
            end
        end
    end
    run.objsRead = true
end

local function ReadBrez()
    if not (C_Spell and C_Spell.GetSpellCharges) then return end
    local ok, info = pcall(C_Spell.GetSpellCharges, BREZ_SPELL)
    if not ok or type(info) ~= "table" then return end
    local cur, mx = Num(info.currentCharges), Num(info.maxCharges)
    if not (cur and mx) then return end
    local nextIn
    local s, d = Num(info.cooldownStartTime), Num(info.cooldownDuration)
    if s and d and d > 0 and cur < mx then nextIn = max(0, s + d - GetTime()) end
    return { cur = cur, max = mx, nextIn = nextIn }
end

mp.ReadBrez = ReadBrez

local function ReadRun()
    local C = C_ChallengeMode
    if not (C and C.IsChallengeModeActive) then run.active = false; return end
    local ok, active = pcall(C.IsChallengeModeActive)
    if not ok or issecret(active) or not active then
        if not run.finished then run.active = false end
        return
    end
    run.active, run.finished = true, nil
    local mapID = C.GetActiveChallengeMapID and Num(C.GetActiveChallengeMapID())
    if mapID and mapID ~= run.mapID then
        run.mapID = mapID
        local name, _, limit = C.GetMapUIInfo(mapID)
        run.name = (type(name) == "string" and not issecret(name)) and name or "Mythic+"
        run.limit = Num(limit) or 0
    end
    if C.GetActiveKeystoneInfo then
        local okk, lvl, affixes = pcall(C.GetActiveKeystoneInfo)
        if okk then
            if Num(lvl) then run.level = lvl end
            if type(affixes) == "table" and not run.affixText and C.GetAffixInfo then
                local names = {}
                for _, id in ipairs(affixes) do
                    id = Num(id)
                    local n = id and C.GetAffixInfo(id)
                    if type(n) == "string" and not issecret(n) then names[#names + 1] = n end
                end
                run.affixText = table.concat(names, ", ")
            end
        end
    end
    local _, elapsed = GetWorldElapsedTime(1)
    run.elapsed = Num(elapsed) or run.elapsed or 0
    if C.GetDeathCount then
        local d, lost = C.GetDeathCount()
        run.deaths, run.timeLost = Num(d) or 0, Num(lost) or 0
    end
    run.forces = ReadForces() or run.forces
    run.brez = ReadBrez()
    ReadObjectives()
end

local function Bar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.03, 0.03, 0.05, 0.8)
    return b
end

local function HUDFrame()
    if hud then return hud end
    local g = NewFrame("MPHUD", 230, 100)
    g.title = mp.FS(g)
    g.time = mp.FS(g)
    g.timeBar = Bar(g)
    g.tick3 = g.timeBar:CreateTexture(nil, "OVERLAY")
    g.tick2 = g.timeBar:CreateTexture(nil, "OVERLAY")
    g.tick3:SetColorTexture(1, 1, 1, 0.7)
    g.tick2:SetColorTexture(1, 1, 1, 0.7)
    g.thresh = mp.FS(g)
    g.forces = mp.FS(g)
    g.forcesBar = Bar(g)
    g.deaths = mp.FS(g)
    g.brez = mp.FS(g)
    g.affix = mp.FS(g)
    g.objs = {}
    for _, fs in ipairs({ g.title, g.time, g.thresh, g.forces, g.deaths, g.brez, g.affix }) do
        fs:SetJustifyH("LEFT")
    end
    hud = g
    return g
end

local function TimeColor(elapsed, limit)
    if limit <= 0 then return 1, 1, 1 end
    local f = elapsed / limit
    if f < 0.6 then return 0.3, 1, 0.4 end      -- still inside +3
    if f < 0.8 then return 0.6, 0.95, 0.3 end   -- inside +2
    if f < 1 then return 1, 0.75, 0.2 end       -- inside +1
    return 1, 0.25, 0.2                         -- over time
end

local function ThresholdText(eff, limit)
    local parts = {}
    local t3, t2 = limit * 0.6, limit * 0.8
    if eff < t3 then parts[#parts + 1] = format("|cff66ff77+3|r %s", Clock(t3 - eff)) end
    if eff < t2 then parts[#parts + 1] = format("|cffaaf055+2|r %s", Clock(t2 - eff)) end
    if eff < limit then
        parts[#parts + 1] = format("|cffffbf33+1|r %s", Clock(limit - eff))
    else
        parts[#parts + 1] = format("|cffff4033Over by|r %s", Clock(eff - limit))
    end
    return table.concat(parts, "   ")
end

function mp:UpdateHUD(now)
    local db = ns.db
    local r = run
    local demo = ns.editMode or ns.preview
    if demo and not (r.active and not r.preview) then r = PREVIEW_RUN end
    if not db.mpEnabled or not (r.active or (run.doneUntil and now < run.doneUntil)) and not demo then
        if hud then hud:Hide() end
        return
    end
    local g = HUDFrame()
    local w = db.mpWidth
    g:SetScale(db.mpScale)
    g:SetWidth(w)
    local pad = 8
    local inner = w - pad * 2
    local y = -6

    local function place(fs, size, height)
        ns.ApplyFont(fs, size)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", g, "TOPLEFT", pad, y)
        fs:SetWidth(inner)
        fs:Show()
        y = y - height
    end
    local function placeBar(bar, height)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", g, "TOPLEFT", pad, y)
        bar:SetSize(inner, height)
        bar:SetStatusBarTexture(ns.ResolveTexture())
        bar:Show()
        y = y - height - 4
    end

    -- title and affixes
    if db.mpTitle then
        g.title:SetText(format("|cffffd24d+%d|r  %s", r.level or 0, r.name or "Mythic+"))
        place(g.title, 13, 18)
    else
        g.title:Hide()
    end
    if db.mpAffixes and r.affixText and r.affixText ~= "" then
        g.affix:SetText(r.affixText)
        g.affix:SetTextColor(0.6, 0.63, 0.7)
        place(g.affix, 10, 14)
    else
        g.affix:Hide()
    end

    -- key timer
    local limit = r.limit or 0
    local eff = (r.elapsed or 0) + (r.timeLost or 0)
    if run.finalTime and not demo and not r.active then eff = run.finalTime end
    if db.mpTimer and limit > 0 then
        local shown = db.mpTimerMode == "REMAINING" and (limit - eff) or eff
        local label = db.mpTimerMode == "REMAINING"
            and ((limit - eff) < 0 and "-" .. Clock(eff - limit) or Clock(limit - eff))
            or Clock(shown)
        g.time:SetText(format("%s |cff9aa0aa/ %s|r", label, Clock(limit)))
        g.time:SetTextColor(TimeColor(eff, limit))
        place(g.time, 18, 24)
        g.timeBar:SetMinMaxValues(0, limit)
        g.timeBar:SetValue(min(eff, limit))
        g.timeBar:SetStatusBarColor(TimeColor(eff, limit))
        placeBar(g.timeBar, db.mpBarHeight)
        g.tick3:ClearAllPoints()
        g.tick3:SetPoint("TOP", g.timeBar, "TOPLEFT", inner * 0.6, 0)
        g.tick3:SetPoint("BOTTOM", g.timeBar, "BOTTOMLEFT", inner * 0.6, 0)
        g.tick3:SetWidth(1)
        g.tick2:ClearAllPoints()
        g.tick2:SetPoint("TOP", g.timeBar, "TOPLEFT", inner * 0.8, 0)
        g.tick2:SetPoint("BOTTOM", g.timeBar, "BOTTOMLEFT", inner * 0.8, 0)
        g.tick2:SetWidth(1)
        if db.mpThresholds then
            g.thresh:SetText(ThresholdText(eff, limit))
            place(g.thresh, 11, 16)
        else
            g.thresh:Hide()
        end
    else
        g.time:Hide(); g.timeBar:Hide(); g.thresh:Hide()
    end

    -- enemy forces
    if db.mpForces and r.forces then
        local pct = min(100, r.forces)
        local mode, val = db.mpForcesMode or "PERCENT", format("%.1f%%", pct)
        if run.fq and run.ft and run.ft > 1 then
            local cnt = format("%d/%d", run.fq, run.ft)
            if mode == "COUNT" then val = cnt elseif mode == "BOTH" then val = val .. "  (" .. cnt .. ")" end
        end
        local lastPull = mp.PullText and mp:PullText()
        if lastPull then val = val .. "  |cff9aa0b4" .. lastPull .. "|r" end
        g.forces:SetText("Enemy forces  |cffffffff" .. val .. "|r")
        g.forces:SetTextColor(0.75, 0.78, 0.85)
        place(g.forces, 11, 15)
        g.forcesBar:SetMinMaxValues(0, 100)
        g.forcesBar:SetValue(pct)
        if pct >= 100 then g.forcesBar:SetStatusBarColor(0.3, 1, 0.4) else g.forcesBar:SetStatusBarColor(0.55, 0.45, 1) end
        placeBar(g.forcesBar, max(6, db.mpBarHeight - 4))
    else
        g.forces:Hide(); g.forcesBar:Hide()
    end

    -- deaths
    if db.mpDeaths then
        local d, lost = r.deaths or 0, r.timeLost or 0
        g.deaths:SetText(format("Deaths  |cffffffff%d|r%s", d, lost > 0 and format("  |cffff6655(-%s)|r", Clock(lost)) or ""))
        g.deaths:SetTextColor(0.75, 0.78, 0.85)
        place(g.deaths, 11, 15)
    else
        g.deaths:Hide()
    end

    -- battle res
    local br = r.brez
    if db.mpBrez and br then
        local text = format("Battle res  |cffffffff%d/%d|r", br.cur, br.max)
        if br.nextIn then text = text .. format("  |cff9aa0aanext %s|r", Clock(br.nextIn)) end
        g.brez:SetText(text)
        g.brez:SetTextColor(0.75, 0.78, 0.85)
        place(g.brez, 11, 15)
    else
        g.brez:Hide()
    end

    -- boss objectives with kill times and comparison to your best split
    local objs = db.mpObjectives and r.objs or nil
    local splits = (run.mapID and run.level and db.mpSplits and db.mpSplits[run.mapID .. ":" .. run.level]) or {}
    local shownObjs = 0
    if objs then
        for i, o in ipairs(objs) do
            local fs = g.objs[i]
            if not fs then
                fs = mp.FS(g)
                fs:SetJustifyH("LEFT")
                g.objs[i] = fs
            end
            local name = o.name or ("Boss " .. i)
            if o.done then
                local text = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11|t " .. name
                if o.elapsed then
                    text = text .. "  |cffffffff" .. Clock(o.elapsed) .. "|r"
                    local best = r.preview and o.best or splits[i]
                    if db.mpCompare and best then
                        local delta = o.elapsed - best
                        text = text .. format("  %s%s%s|r", delta <= 0 and "|cff66ff77" or "|cffff6655",
                            delta <= 0 and "-" or "+", Clock(math.abs(delta)))
                    end
                end
                fs:SetText(text)
                fs:SetTextColor(0.75, 0.78, 0.85)
            else
                fs:SetText("|cff9aa0aa-  " .. name .. "|r")
            end
            place(fs, 10, 14)
            shownObjs = i
        end
    end
    for i = shownObjs + 1, #g.objs do g.objs[i]:Hide() end

    g:SetHeight(-y + 4)
    Look(g, db.mpBg)
    g:Show()
end

local function RecordCompletion()
    local C = C_ChallengeMode
    if not (C and C.GetCompletionInfo) then return end
    local ok, mapID, level, timeMs, onTime = pcall(C.GetCompletionInfo)
    if not ok then return end
    mapID, level, timeMs = Num(mapID), Num(level), Num(timeMs)
    if not (mapID and level and timeMs) then return end
    local sec = timeMs / 1000
    run.finished, run.finalTime, run.doneUntil = true, sec, GetTime() + 25
    run.active = false
    local db = ns.db
    db.mpBest = db.mpBest or {}
    local key = mapID .. ":" .. level
    local prev = db.mpBest[key]
    local line = format("Key finished in %s", Clock(sec))
    if prev then
        line = line .. format(" (best %s, %s%s)", Clock(prev), sec <= prev and "-" or "+", Clock(math.abs(sec - prev)))
    end
    if onTime == true and (not prev or sec < prev) then
        db.mpBest[key] = sec
        line = line .. " - new personal best!"
    end
    ns.Print(line)
    if db.sndKeyDoneOn and ns.Snd then ns.Snd.Alert("KeyDone") end
    if db.mpHistoryOn ~= false then
        db.mpHistory = db.mpHistory or {}
        table.insert(db.mpHistory, 1, { map = mapID, level = level, time = sec, timed = onTime == true,
            deaths = Num(run.deaths) or 0, date = date and date("%Y-%m-%d") or "" })
        while #db.mpHistory > 40 do table.remove(db.mpHistory) end
    end
    if db.mpSummary ~= false then
        local parts = {}
        for name, n in pairs(mp.deathCount or {}) do parts[#parts + 1] = format("%s %d", name, n) end
        table.sort(parts)
        ns.Print(format("Run summary: +%d, %s, deaths %d%s", level, onTime == true and "timed" or "over time",
            Num(run.deaths) or 0, #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""))
    end
    -- remember your fastest time for each boss in this dungeon and level
    if run.objs then
        db.mpSplits = db.mpSplits or {}
        local rec = db.mpSplits[key] or {}
        db.mpSplits[key] = rec
        for i, o in ipairs(run.objs) do
            if o.elapsed and (not rec[i] or o.elapsed < rec[i]) then rec[i] = o.elapsed end
        end
    end
end

---------------------------------------------------------------------------
-- 4. key helpers
---------------------------------------------------------------------------

local function SlotKeystone()
    if not (C_Container and C_ChallengeMode and C_ChallengeMode.SlotKeystone) then return end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local link = info and info.hyperlink
            if type(link) == "string" and not issecret(link) and link:find("keystone:", 1, true) then
                C_Container.PickupContainerItem(bag, slot)
                C_ChallengeMode.SlotKeystone()
                return true
            end
        end
    end
end

local hooked
local function HookKeystoneFrame()
    if hooked or not ChallengesKeystoneFrame then return end
    hooked = true
    ChallengesKeystoneFrame:HookScript("OnShow", function()
        if ns.db and ns.db.mpAutoKey and ns.db.khEnabled and not ns.db.syncOnly then
            C_Timer.After(0.25, function() pcall(SlotKeystone) end)
        end
    end)
end

local function ApplyBlizzTracker()
    local f = _G.ObjectiveTrackerFrame
    if not f or not f.SetAlpha then return end
    local hide = ns.db.mpHideBlizz and ns.db.khEnabled and run.active and not run.preview
    if hide then
        f.smhHidden = true
        pcall(f.SetAlpha, f, 0)
    elseif f.smhHidden then
        f.smhHidden = nil
        pcall(f.SetAlpha, f, 1)
    end
end

---------------------------------------------------------------------------
-- driver
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
local acc, slow = 0, 0
local function HideAllMP()
    for _, g in ipairs(mp.frames) do
        if g:IsShown() then g:Hide() end
    end
    local f = _G.ObjectiveTrackerFrame
    if f and f.smhHidden then f.smhHidden = nil; pcall(f.SetAlpha, f, 1) end
end
mp.HideAll = HideAllMP

driver:SetScript("OnUpdate", function(_, dt)
    if not ns.db then return end
    if ns.db.syncOnly then
        acc = acc + dt
        if acc >= 1 then acc = 0; HideAllMP() end
        return
    end
    acc = acc + dt
    if acc < 0.1 then return end
    local frameDt = acc
    acc = 0
    local now = GetTime()
    slow = slow + frameDt
    if slow >= 0.5 then
        slow = 0
        pcall(ReadRun)
        ApplyBlizzTracker()
        for _, fn in ipairs(mp.slowUpdaters) do pcall(fn, now) end
    end
    ct:Update(now)
    cmb:Update(now)
    mp:UpdateHUD(now)
    for _, fn in ipairs(mp.updaters) do pcall(fn, now) end
end)

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED",
    "CHALLENGE_MODE_RESET", "SCENARIO_CRITERIA_UPDATE", "CHALLENGE_MODE_DEATH_COUNT_UPDATED",
    "PLAYER_ENTERING_WORLD", "ADDON_LOADED",
}) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event, arg1)
    if not ns.db or ns.db.syncOnly then return end
    if event == "PLAYER_REGEN_DISABLED" then
        CMBStart()
        CombatChanged(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        CMBStop()
        CombatChanged(false)
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        pcall(ReadRun)
        pcall(RecordCompletion)
    elseif event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET" then
        run.mapID, run.finished, run.finalTime, run.doneUntil, run.forces = nil, nil, nil, nil, nil
        run.fq, run.ft = nil, nil
        if event == "CHALLENGE_MODE_START" and ns.db.sndKeyStartOn and ns.Snd then ns.Snd.Alert("KeyStart") end
        mp.deathCount = {}
        run.objs, run.objsRead, run.affixText = nil, nil, nil
        pcall(ReadRun)
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_ChallengesUI" then HookKeystoneFrame() end
    else
        if event == "PLAYER_ENTERING_WORLD" then HookKeystoneFrame() end
        pcall(ReadRun)
    end
end)

-- called by ns:Refresh / position changes
function mp:Refresh()
    if not ns.db then return end
    if ns.db.syncOnly then HideAllMP() return end
    local now = GetTime()
    ct:Update(now)
    cmb:Update(now)
    mp:UpdateHUD(now)
    for _, fn in ipairs(mp.updaters) do pcall(fn, now) end
end

function mp:ApplyPositions()
    for _, g in ipairs(mp.frames) do ApplyP(g) end
end

local origRefresh = ns.Refresh
function ns:Refresh(...)
    origRefresh(self, ...)
    mp:Refresh()
end
local origApply = ns.ApplyAllPositions
function ns:ApplyAllPositions(...)
    origApply(self, ...)
    mp:ApplyPositions()
end

mp.creators.CTEXT, mp.creators.CTIMER, mp.creators.MPHUD = CTFrame, CMBFrame, HUDFrame

mp.run = run
