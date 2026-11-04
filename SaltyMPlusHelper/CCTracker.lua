-- CCTracker.lua: how long is left on the crowd control YOU applied to enemies.
-- Shown in its own movable window as icons, bars, or both.
--
-- Two sources, because Midnight (12.0) hides a lot of enemy data from addons:
--   * Aura scan: debuffs on enemy nameplates / target / focus that are crowd control applied
--     by you. When the game lets us read their timing we use it; otherwise the game's own
--     duration object drives the swipe and countdown. If the aura disappears the CC broke
--     or ended, and the entry is removed.
--   * Cast estimate: when you cast a known CC spell on your target we start a timer from its
--     normal PvE duration, so something always shows even if the aura cannot be read.

local ADDON, ns = ...
local cc = {}
ns.CC = cc
local issecret = ns.issecret

local FLAT = "Interface\\Buttons\\WHITE8x8"
local HEADER_H = 22
local FILTER = "HARMFUL|CROWD_CONTROL"

local entries = {}
cc.entries = entries
local byKey = {}
local counter = 0
local frame
local pool = { icons = {}, bars = {} }

local TOKENS = {}
for i = 1, 20 do TOKENS[#TOKENS + 1] = "nameplate" .. i end
TOKENS[#TOKENS + 1] = "target"
TOKENS[#TOKENS + 1] = "focus"
TOKENS[#TOKENS + 1] = "mouseover"

local PREVIEW = {
    { 115078, "Ethereal Plunderer", 60, 0.25 },
    { 118, "Spiteful Shade", 60, 0.55 },
    { 853, "Manifested Timeways", 6, 0.4 },
    { 51514, "Cursed Spirit", 60, 0.1 },
}

---------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------

local function PickUnit()
    for _, u in ipairs({ "target", "focus", "mouseover" }) do
        local ok, can = pcall(function() return UnitExists(u) and UnitCanAttack("player", u) end)
        if ok and not issecret(can) and can then return u end
    end
end

-- KiraUI's CC bars already draw this with Midnight's aura containers; do not show it twice.
local function Deferred()
    return ns.db.ccDefer and not ns.preview and not ns.editMode and ns:KiraCCBarsOn()
end
cc.Deferred = Deferred

-- Called for every spell the player casts.
function cc:OnPlayerCast(spellID)
    local db = ns.db
    if not (db.ccEnabled and db.ccEstimate) or Deferred() then return end
    local dur = ns.CC_SPELLS[spellID]
    if not dur then return end
    local unit = PickUnit()
    if not unit then return end
    local ok, name = pcall(UnitName, unit)
    counter = counter + 1
    for i = #entries, 1, -1 do -- recasting on the same target replaces the older timer
        local e = entries[i]
        if e.estimate and e.spellID == spellID and e.unit == unit then table.remove(entries, i) end
    end
    entries[#entries + 1] = {
        key = "e" .. counter, estimate = true, numeric = true, unit = unit,
        name = ok and name or nil, spellID = spellID, start = GetTime(), dur = dur,
    }
end

local function SameMob(a, b)
    local ok, r = pcall(UnitIsUnit, a, b)
    return ok and not issecret(r) and r == true
end

-- Crowd control auras on one unit that we applied. nil = the game would not let us look.
local function MobAuras(unit)
    local out = {}
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetDebuffDataByIndex, unit, i, FILTER)
        if not ok then return nil end
        if not aura then break end
        local mine = aura.isFromPlayerOrPlayerPet
        if issecret(mine) then
            mine = false -- cannot tell whose it is while restricted: skip rather than guess
        elseif mine == nil then
            local src = aura.sourceUnit
            mine = (not issecret(src)) and src == "player"
        end
        if mine then out[#out + 1] = aura end
    end
    return out
end

function cc:Scan()
    local db = ns.db
    if not db.ccEnabled or ns.preview or Deferred() then return end
    if not (C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex) then return end
    local now = GetTime()
    local seen, scanned, supported = {}, {}, false
    for _, token in ipairs(TOKENS) do
        if UnitExists(token) then
            local dup = false
            for _, t in ipairs(scanned) do
                if SameMob(t, token) then dup = true; break end
            end
            if not dup then
                scanned[#scanned + 1] = token
                local list = MobAuras(token)
                if list then
                    supported = true
                    for _, aura in ipairs(list) do
                        local id = aura.auraInstanceID
                        if not issecret(id) and id then
                            local key = token .. ":" .. id
                            seen[key] = true
                            local e = byKey[key]
                            if not e then
                                -- the real aura replaces the guess we made a moment ago
                                for i = #entries, 1, -1 do
                                    if entries[i].estimate and now - entries[i].start < 3 then table.remove(entries, i) end
                                end
                                e = { key = key, aura = true, unit = token }
                                byKey[key] = e
                                entries[#entries + 1] = e
                            end
                            e.unit = token
                            e.icon = aura.icon -- may be a secret value: only ever passed to SetTexture
                            local sid = aura.spellId
                            if not issecret(sid) and sid then e.spellID = sid end
                            local exp, dur = aura.expirationTime, aura.duration
                            if type(exp) == "number" and type(dur) == "number" and not issecret(exp)
                                and not issecret(dur) and dur > 0 then
                                e.numeric, e.start, e.dur = true, exp - dur, dur
                            else
                                e.numeric = false
                                if C_UnitAuras.GetAuraDuration then
                                    local ok, obj = pcall(C_UnitAuras.GetAuraDuration, token, id)
                                    if ok and obj then e.durObj = obj end
                                end
                            end
                            local ok, name = pcall(UnitName, token)
                            if ok then e.name = name end -- may be secret: only ever displayed
                        end
                    end
                end
            end
        end
    end
    if supported then
        for i = #entries, 1, -1 do
            local e = entries[i]
            if e.aura and not seen[e.key] then
                byKey[e.key] = nil
                table.remove(entries, i)
            end
        end
    end
end

function cc:SetPreview(on)
    for i = #entries, 1, -1 do
        if entries[i].preview then table.remove(entries, i) end
    end
    if on then
        local now = GetTime()
        for i, p in ipairs(PREVIEW) do
            entries[#entries + 1] = {
                key = "p" .. i, preview = true, estimate = true, numeric = true, loop = true,
                spellID = p[1], name = p[2], dur = p[3], start = now - p[3] * p[4],
            }
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function CreateFrameOnce()
    if frame then return frame end
    frame = ns.NewBackdropFrame("SaltyMPlusHelperCCFrame")
    frame:SetSize(200, 60)
    ns.MakeMovable(frame, "CCTRACK")
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetPoint("TOPLEFT", 8, -5)
    frame.empty = frame:CreateFontString(nil, "OVERLAY")
    frame:SetScale(ns.db.scale)
    ns.ApplyPos(frame)
    frame:Hide()
    cc.frame = frame
    return frame
end
cc.Ensure = CreateFrameOnce

local function SetName(fs, e, fallback)
    local name = e.name
    if name == nil then name = fallback end
    local ok = pcall(fs.SetText, fs, name or "")
    if not ok then fs:SetText("") end
end

local function SetIcon(tex, e)
    local icon
    if e.spellID then icon = select(2, ns.SpellInfo(e.spellID)) end
    if icon then
        tex:SetTexture(icon)
    elseif e.icon ~= nil then
        pcall(tex.SetTexture, tex, e.icon)
    else
        tex:SetTexture(134400)
    end
end

-- Apply the entry's timing to a cooldown frame; returns true when the game's own countdown
-- numbers are showing (so we must not draw ours).
local function SetTiming(cd, e, rem)
    if e.numeric then
        local key = e.key .. tostring(e.start)
        if cd.cdKey ~= key then
            cd.cdKey = key
            cd:SetCooldown(e.start, e.dur)
        end
        cd:SetHideCountdownNumbers(true)
        return false
    elseif e.durObj then
        if cd.cdKey ~= e.durObj then
            cd.cdKey = e.durObj
            pcall(cd.SetCooldownFromDurationObject, cd, e.durObj)
        end
        cd:SetHideCountdownNumbers(false)
        return true
    end
    cd:SetHideCountdownNumbers(true)
    return false
end

local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.tex)
    b.cd:SetDrawEdge(false)
    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.border:SetPoint("TOPLEFT", 0, 0)
    b.border:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    b.border:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.holder = CreateFrame("Frame", nil, b)
    b.holder:SetAllPoints(b.border)
    b.holder:SetFrameLevel(b.cd:GetFrameLevel() + 3)
    b.time = b.holder:CreateFontString(nil, "OVERLAY")
    b.time:SetPoint("CENTER", 0, 0)
    b.nameFs = b:CreateFontString(nil, "OVERLAY")
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetMinMaxValues(0, 1)
    b.bar.bg = b.bar:CreateTexture(nil, "BACKGROUND")
    b.bar.bg:SetAllPoints()
    return b
end

local function UpdateIcon(b, e, rem, both)
    local db = ns.db
    local size = db.ccIconSize
    local showName = db.ccShowName
    local barH = both and db.iconBarHeight or 0
    local cellH = size + (both and (barH + 1) or 0) + (showName and 13 or 0)
    b:SetSize(size, cellH)
    b.tex:ClearAllPoints()
    b.tex:SetPoint("TOPLEFT", 1, -1)
    b.tex:SetSize(size - 2, size - 2)
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border:SetSize(size, size)
    b.border:SetBackdropBorderColor(0.8, 0.45, 1, db.borderAlpha)
    SetIcon(b.tex, e)
    local native = SetTiming(b.cd, e, rem)
    ns.ApplyFont(b.time, db.timerSize)
    if native or not rem then
        b.time:SetText("")
    else
        b.time:SetText(ns.FmtTime(rem))
    end
    b.time:SetTextColor(1, 1, 1)
    b.nameFs:ClearAllPoints()
    b.nameFs:SetPoint("TOP", b, "TOP", 0, -(size + (both and (barH + 2) or 1)))
    b.nameFs:SetWidth(size + 24)
    ns.ApplyFont(b.nameFs, max(8, db.nameSize - 2))
    b.nameFs:SetShown(showName)
    if showName then SetName(b.nameFs, e, nil) end
    b.bar:ClearAllPoints()
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(size + 1))
    b.bar:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -(size + 1))
    b.bar:SetHeight(max(1, barH))
    b.bar:SetStatusBarTexture(ns.ResolveTexture())
    b.bar.bg:SetColorTexture(0.05, 0.05, 0.08, 0.9)
    b.bar:SetShown(both)
    if both then
        b.bar:SetStatusBarColor(0.8, 0.45, 1, 1)
        if rem and e.dur and e.dur > 0 then
            b.bar:SetValue(min(1, rem / e.dur)) -- drains as the CC runs out
        elseif e.durObj and b.bar.SetTimerDuration then
            pcall(b.bar.SetTimerDuration, b.bar, e.durObj)
        else
            b.bar:SetValue(1)
        end
    end
    return size, cellH
end

local function NewBar(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.status = CreateFrame("StatusBar", nil, b)
    b.status:SetMinMaxValues(0, 1)
    b.nameFs = b.status:CreateFontString(nil, "OVERLAY")
    b.nameFs:SetJustifyH("LEFT")
    b.nameFs:SetWordWrap(false)
    b.time = b.status:CreateFontString(nil, "OVERLAY")
    b.time:SetJustifyH("RIGHT")
    -- the game's countdown numbers when the exact time is hidden from us
    b.cd = CreateFrame("Cooldown", nil, b.status, "CooldownFrameTemplate")
    b.cd:SetDrawSwipe(false)
    b.cd:SetDrawEdge(false)
    b.cd:SetDrawBling(false)
    return b
end

local function UpdateBar(b, e, rem)
    local db = ns.db
    local w, h = db.ccBarWidth, db.ccBarHeight
    b:SetSize(w, h)
    b:SetBackdropColor(0.05, 0.05, 0.08, db.bgAlpha)
    b:SetBackdropBorderColor(0, 0, 0, db.borderAlpha)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.LayoutBar(b, h, b.nameFs)
    SetIcon(b.icon, e)
    b.status:SetStatusBarTexture(ns.ResolveTexture())
    b.status:SetStatusBarColor(0.8, 0.45, 1, 0.85)
    b.cd:SetAllPoints(b.time)
    local fs = max(8, min(db.timerSize, h - 4))
    ns.ApplyFont(b.nameFs, fs)
    ns.ApplyFont(b.time, fs)
    b.time:SetWidth(46)
    local spell = e.spellID and ns.SpellInfo(e.spellID) or "Crowd control"
    if db.ccShowName and e.name ~= nil then
        SetName(b.nameFs, e, spell)
    else
        b.nameFs:SetText(spell)
    end
    local native = SetTiming(b.cd, e, rem)
    if rem and e.dur and e.dur > 0 then
        b.status:SetValue(min(1, rem / e.dur))
    elseif e.durObj and b.status.SetTimerDuration then
        pcall(b.status.SetTimerDuration, b.status, e.durObj)
    else
        b.status:SetValue(1)
    end
    if native or not rem then b.time:SetText("") else b.time:SetText(ns.FmtTime(rem)) end
    b.time:SetTextColor(1, 1, 1)
end

function cc:Refresh(show, forced)
    local db = ns.db
    CreateFrameOnce()
    local now = GetTime()

    local list = {}
    for i = #entries, 1, -1 do
        local e = entries[i]
        local rem
        if e.numeric then
            rem = e.start + e.dur - now
            if rem <= 0 then
                if e.loop then
                    if rem < -4 then e.start = now end
                    rem = 0
                else
                    byKey[e.key] = nil
                    table.remove(entries, i)
                    rem = nil
                end
            end
        end
        if rem ~= nil or not e.numeric then
            if not (e.loop and rem == 0) then list[#list + 1] = { e = e, rem = rem } end
        end
    end
    -- oldest first, numbers soonest-to-expire first
    table.sort(list, function(a, b)
        if a.rem and b.rem then return a.rem < b.rem end
        if (a.rem ~= nil) ~= (b.rem ~= nil) then return a.rem ~= nil end
        return a.e.key < b.e.key
    end)
    for i = #list, db.ccMax + 1, -1 do list[i] = nil end

    local visible = show and db.ccEnabled and not Deferred() and (#list > 0 or ns.editMode)
    if not visible then
        frame:Hide()
        return
    end

    local edit = ns.editMode
    ns.EditLook(frame, edit)
    ns.ApplyFont(frame.title, 12)
    frame.title:SetText(ns.TITLES.CCTRACK .. (edit and "  |cff66ccffdrag to move|r" or ""))
    ns.ApplyFont(frame.empty, 11)
    frame.empty:ClearAllPoints()
    frame.empty:SetPoint("TOPLEFT", 8, HEADER_H * -1 - 4)
    frame.empty:SetText("Your CC on enemies shows up here")
    frame.empty:SetShown(#list == 0)

    local style = db.ccStyle
    local w, h = 150, 0
    local top = HEADER_H
    if style == "BARS" then
        local bw, bh, sp = db.ccBarWidth, db.ccBarHeight, db.spacing
        local up = db.ccGrowth == "UP"
        for i, item in ipairs(list) do
            local b = pool.bars[i]
            if not b then
                b = NewBar(frame)
                pool.bars[i] = b
            end
            UpdateBar(b, item.e, item.rem)
            b:ClearAllPoints()
            if up then
                b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6 + (i - 1) * (bh + sp))
            else
                b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(top + (i - 1) * (bh + sp)))
            end
            b:Show()
        end
        w, h = bw + 12, top + #list * bh + max(0, #list - 1) * sp + 8
        for i = #list + 1, #pool.bars do pool.bars[i]:Hide() end
        for i = 1, #pool.icons do pool.icons[i]:Hide() end
    else
        local both = style == "BOTH"
        local sp = db.spacing + (db.ccShowName and 12 or 2)
        local horizontal = db.ccGrowth == "RIGHT" or db.ccGrowth == "LEFT"
        local rtl = db.ccGrowth == "LEFT"
        local up = db.ccGrowth == "UP"
        local cellW, cellH = 0, 0
        for i, item in ipairs(list) do
            local b = pool.icons[i]
            if not b then
                b = NewIcon(frame)
                pool.icons[i] = b
            end
            local size, ch = UpdateIcon(b, item.e, item.rem, both)
            cellW, cellH = size, ch
            b:ClearAllPoints()
            local idx = i - 1
            if horizontal then
                local x = idx * (size + sp)
                if rtl then
                    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6 - x, -top)
                else
                    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + x, -top)
                end
            elseif up then
                b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6 + idx * (ch + 4))
            else
                b:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -(top + idx * (ch + 4)))
            end
            b:Show()
        end
        local n = #list
        if n == 0 then
            cellW, cellH = db.ccIconSize, db.ccIconSize
        end
        if horizontal then
            w, h = 12 + max(1, n) * cellW + max(0, n - 1) * sp, top + cellH + 8
        else
            w, h = 12 + cellW, top + max(1, n) * cellH + max(0, n - 1) * 4 + 8
        end
        for i = #list + 1, #pool.icons do pool.icons[i]:Hide() end
        for i = 1, #pool.bars do pool.bars[i]:Hide() end
    end
    frame:SetSize(max(w, 170), h)
    frame:SetScale(db.scale)
    frame:SetAlpha(db.alpha)
    ns.NormalizeGroup(frame)
    frame:Show()
end

-- Scan for the real auras a few times a second.
table.insert(ns.initHooks, function()
    CreateFrameOnce()
    local acc = 0
    local scanner = CreateFrame("Frame")
    scanner:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.3 then
            acc = 0
            local ok, err = pcall(cc.Scan, cc)
            if not ok and not cc.scanError then
                cc.scanError = err -- never spam; the estimate path keeps working
            end
        end
    end)
end)
