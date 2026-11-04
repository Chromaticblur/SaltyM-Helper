-- MythicPlusExtras.lua: more keystone-pushing tools, built on the helpers in MythicPlus.lua
--   * Group death alert     : "<Name> died" in class colour
--   * Battle res + Bloodlust: two icons (charges / Sated timer)
--   * Kick order            : who kicks next, in an order you set (and can announce)
--   * Party keystones       : /skeys lists party keys (the clickable teleport list is KeyList.lua)
--   * Auto combat logging   : starts and stops /combatlog by dungeon / raid difficulty
--   * Hide the talking head
-- Written from scratch; reads only what the game gives addons and ignores hidden ("secret") values.

local ADDON, ns = ...
local mp = ns.MP
local issecret = ns.issecret or issecretvalue or function() return false end
local floor, max, min, format = math.floor, math.max, math.min, string.format
local Clock = mp.Clock

mp.DEFAULT_POS.DEATHS = { -130, 70 }
mp.DEFAULT_POS.ICONS = { 420, -20 }
mp.DEFAULT_POS.KICKS = { -430, 160 }

local function Num(v)
    if type(v) == "number" and not issecret(v) then return v end
end

local function Hex(r, g, b)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

---------------------------------------------------------------------------
-- group death alert
---------------------------------------------------------------------------

local dt = { lines = {}, was = {} }
mp.dt = dt
local dtFrame

local function DTFrame()
    if dtFrame then return dtFrame end
    local g = mp.NewFrame("DEATHS", 260, 70)
    g.text = mp.FS(g)
    g.text:SetPoint("TOP", 0, -6)
    g.text:SetWidth(248)
    g.text:SetJustifyH("CENTER")
    dtFrame = g
    return g
end

local function AddDeath(name, class)
    local db = ns.db
    mp.deathCount = mp.deathCount or {}
    mp.deathCount[name] = (mp.deathCount[name] or 0) + 1
    local r, g, b = ns.ClassRGB(class)
    local coloured = Hex(r, g, b) .. name .. "|r"
    local text = (db.dtText or "{name} died"):gsub("{name}", function() return coloured end)
    table.insert(dt.lines, 1, { text = text, expires = GetTime() + db.dtDuration })
    while #dt.lines > 4 do table.remove(dt.lines) end
    if db.dtSound then
        if not (ns.Snd and ns.Snd.Alert("Death")) and SOUNDKIT and SOUNDKIT.RAID_WARNING then
            pcall(PlaySound, SOUNDKIT.RAID_WARNING)
        end
    end
end

local function PollDeaths()
    local db = ns.db
    if not db.dtEnabled then return end
    if db.dtOnlyInstance and not IsInInstance() then
        wipe(dt.was)
        return
    end
    local units = { "party1", "party2", "party3", "party4" }
    if db.dtSelf then units[#units + 1] = "player" end
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local ok, dead = pcall(function() return UnitIsDeadOrGhost(u) and not UnitIsFeignDeath(u) end)
            local okName, name = pcall(UnitName, u)
            if ok and okName and type(dead) == "boolean" and not issecret(dead)
                and type(name) == "string" and not issecret(name) then
                if dead and not dt.was[name] then
                    dt.was[name] = true
                    local _, class = UnitClass(u)
                    AddDeath(name, class)
                elseif not dead then
                    dt.was[name] = nil
                end
            end
        end
    end
end

local function UpdateDeaths(now)
    local db = ns.db
    local g = dtFrame
    if not db.dtEnabled then
        if g then g:Hide() end
        return
    end
    local demo = ns.editMode or ns.preview
    for i = #dt.lines, 1, -1 do
        if now >= dt.lines[i].expires then table.remove(dt.lines, i) end
    end
    if not demo and #dt.lines == 0 then
        if g then g:Hide() end
        return
    end
    g = DTFrame()
    local out = {}
    if demo then
        local r, gr, b = ns.ClassRGB("WARRIOR")
        out[1] = (db.dtText or "{name} died"):gsub("{name}", function() return Hex(r, gr, b) .. "Buffalows|r" end)
    else
        for _, l in ipairs(dt.lines) do out[#out + 1] = l.text end
    end
    ns.ApplyFont(g.text, db.dtSize)
    g.text:SetText(table.concat(out, "\n"))
    g:SetSize(260, max(30, #out * (db.dtSize + 4) + 14))
    mp.Look(g, 0)
    g:Show()
end

---------------------------------------------------------------------------
-- battle res + bloodlust icons
---------------------------------------------------------------------------

local SATED = { 57723, 57724, 80354, 95809, 264689 } -- Exhaustion, Sated, Temporal Displacement, Insanity, Fatigued
local sat = { active = false, expiry = 0 }

local function PollSated(now)
    local found
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs(SATED) do
            local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
            if ok and aura then found = aura; break end
        end
    end
    if found then
        local exp = Num(found.expirationTime)
        if exp and exp > 0 then
            sat.expiry = exp
        elseif not sat.active then
            sat.expiry = now + 600 -- readable timing is hidden: assume the usual 10 minutes
        end
        sat.active = true
    else
        sat.active, sat.expiry = false, 0
    end
end

local iconFrame
local function MakeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.time = mp.FS(f)
    f.time:SetPoint("CENTER")
    f.count = mp.FS(f)
    f.count:SetPoint("BOTTOMRIGHT", -2, 2)
    return f
end

local function IconFrame()
    if iconFrame then return iconFrame end
    local g = mp.NewFrame("ICONS", 90, 46)
    g.br = MakeIcon(g)
    g.bl = MakeIcon(g)
    iconFrame = g
    return g
end

local function SpellTex(id, fallback)
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    return tex or fallback
end

local function UpdateIcons(now)
    local db = ns.db
    local g = iconFrame
    if not db.mpIcons then
        if g then g:Hide() end
        return
    end
    local demo = ns.editMode or ns.preview
    local inKey = mp.run.active and not mp.run.preview
    local _, itype = IsInInstance()
    local raidFight = itype == "raid" and IsEncounterInProgress and IsEncounterInProgress()

    local showBR, br, brTime = false, nil, nil
    if db.mpIconBR then
        if demo then
            showBR, br, brTime = true, { cur = 1, max = 2 }, 83
        elseif inKey or raidFight then
            br = inKey and mp.run.brez or mp.ReadBrez()
            if br then showBR, brTime = true, br.nextIn end
        end
    end
    local showBL, blText, blSated = false, nil, false
    if db.mpIconBL then
        if demo then
            showBL, blText, blSated = true, Clock(412), true
        elseif IsInGroup() and itype ~= "none" then
            if sat.active then
                showBL, blSated = true, true
                blText = Clock(max(0, sat.expiry - now))
            elseif db.blReady then
                showBL, blText = true, "READY"
            end
        end
    end
    if not (showBR or showBL) then
        if g then g:Hide() end
        return
    end

    g = IconFrame()
    local size = db.mpIconSize
    local x = 0
    local function put(icon, show)
        icon:SetShown(show)
        if show then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", g, "TOPLEFT", 4 + x, -4)
            icon:SetSize(size, size)
            x = x + size + 4
        end
    end
    put(g.br, showBR)
    put(g.bl, showBL)
    if showBR then
        g.br.tex:SetTexture(SpellTex(20484, 136080))
        ns.ApplyFont(g.br.time, max(9, floor(size * 0.32)))
        ns.ApplyFont(g.br.count, max(10, floor(size * 0.4)))
        g.br.time:SetText(brTime and Clock(brTime) or "")
        g.br.count:SetText(br.cur)
        if br.cur > 0 then g.br.count:SetTextColor(0.3, 1, 0.4) else g.br.count:SetTextColor(1, 0.3, 0.25) end
        g.br.tex:SetDesaturated(br.cur == 0)
    end
    if showBL then
        g.bl.tex:SetTexture(SpellTex(2825, 136012))
        ns.ApplyFont(g.bl.time, max(9, floor(size * (blSated and 0.32 or 0.26))))
        g.bl.count:SetText("")
        g.bl.time:SetText(blText)
        g.bl.tex:SetDesaturated(blSated)
        if blSated then g.bl.time:SetTextColor(1, 0.35, 0.3) else g.bl.time:SetTextColor(0.3, 1, 0.4) end
    end
    g:SetSize(x + 4, size + 8)
    mp.Look(g, db.mpBg * 0.5)
    g:Show()
end

---------------------------------------------------------------------------
-- kick order
---------------------------------------------------------------------------

local kickFrame
local kickRows = {}

local function KickFrame()
    if kickFrame then return kickFrame end
    local g = mp.NewFrame("KICKS", 200, 60)
    g.title = mp.FS(g)
    g.title:SetPoint("TOPLEFT", 8, -6)
    g.title:SetText("Kick order")
    g.title:SetTextColor(0.7, 0.75, 0.85)
    kickFrame = g
    return g
end

-- One entry per player: their interrupt, how long until it is ready, whether we only guess.
local function KickEntries(now)
    local list = {}
    for name, m in pairs(ns.members) do
        if (ns.preview and m.test) or (not ns.preview and not m.test) then
            local best
            for id, s in pairs(m.spells) do
                local def = ns.SPELLS[id]
                if s.known and def and def.cat == "INT" and (not best or id < best.id) then
                    local rem = (s.start and s.dur) and max(0, s.start + s.dur - now) or 0
                    best = {
                        id = id, rem = rem, start = s.start or 0,
                        unknown = rem == 0 and not m.isSelf and not m.hasAddon and not s.seen,
                    }
                end
            end
            if best then
                best.name, best.class = name, m.class
                list[#list + 1] = best
            end
        end
    end
    -- user order first, everyone else by name
    local rank = {}
    for i, n in ipairs(ns.db.kickOrder or {}) do rank[n] = i end
    table.sort(list, function(a, b)
        local ra, rb = rank[a.name] or 1000, rank[b.name] or 1000
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

-- "Next" is whoever follows the most recent kicker in the order and is ready.
local function PickNext(list)
    local last, lastStart = nil, 0
    for i, e in ipairs(list) do
        if e.rem > 0 and e.start > lastStart then last, lastStart = i, e.start end
    end
    local n = #list
    for step = 1, n do
        local i = ((last or 0) + step - 1) % n + 1
        local e = list[i]
        if e.rem == 0 and not e.unknown then return i end
    end
    for step = 1, n do
        local i = ((last or 0) + step - 1) % n + 1
        if list[i].rem == 0 then return i end
    end
end

local function UpdateKicks(now)
    local db = ns.db
    local g = kickFrame
    local demo = ns.editMode or ns.preview
    if not db.krEnabled or not (demo or IsInGroup()) then
        if g then g:Hide() end
        return
    end
    local list = KickEntries(now)
    if #list == 0 and not demo then
        if g then g:Hide() end
        return
    end
    g = KickFrame()
    local nextIdx = PickNext(list)
    local size = db.krSize
    local rowH = size + 6
    ns.ApplyFont(g.title, size - 2)
    for i, e in ipairs(list) do
        local row = kickRows[i]
        if not row then
            row = {}
            row.hl = g:CreateTexture(nil, "BACKGROUND")
            row.hl:SetColorTexture(0.2, 0.9, 0.35, 0.18)
            row.name = mp.FS(g)
            row.name:SetJustifyH("LEFT")
            row.state = mp.FS(g)
            row.state:SetJustifyH("RIGHT")
            kickRows[i] = row
        end
        local y = -(size + 14) - (i - 1) * rowH
        row.hl:ClearAllPoints()
        row.hl:SetPoint("TOPLEFT", g, "TOPLEFT", 3, y + 2)
        row.hl:SetPoint("TOPRIGHT", g, "TOPRIGHT", -3, y + 2)
        row.hl:SetHeight(rowH)
        row.hl:SetShown(i == nextIdx)
        ns.ApplyFont(row.name, size)
        ns.ApplyFont(row.state, size)
        row.name:ClearAllPoints()
        row.name:SetPoint("TOPLEFT", g, "TOPLEFT", 8, y)
        row.state:ClearAllPoints()
        row.state:SetPoint("TOPRIGHT", g, "TOPRIGHT", -8, y)
        local r, gr, b = ns.ClassRGB(e.class)
        local spell = ns.SpellInfo(e.id)
        row.name:SetText(format("%s%d  %s|r  |cff8a90a0%s|r", Hex(r, gr, b), i, e.name, spell or ""))
        if e.rem > 0 then
            row.state:SetText(Clock(e.rem))
            row.state:SetTextColor(1, 1, 1)
        elseif e.unknown then
            row.state:SetText("?")
            row.state:SetTextColor(0.7, 0.7, 0.75)
        else
            row.state:SetText(i == nextIdx and "NEXT" or "READY")
            row.state:SetTextColor(0.3, 1, 0.4)
        end
        row.name:Show()
        row.state:Show()
    end
    for i = #list + 1, #kickRows do
        kickRows[i].hl:Hide(); kickRows[i].name:Hide(); kickRows[i].state:Hide()
    end
    g:SetSize(db.krWidth, size + 22 + max(1, #list) * rowH)
    mp.Look(g, db.krBg)
    g:Show()
end

-- Put yourself first, then the rest of the party in group order, and optionally say it in chat.
function mp:AssignKickOrder(announce)
    local names, seen = {}, {}
    local function add(unit)
        local n = ns.UnitKey(unit)
        if n and not seen[n] and ns.members[n] then
            seen[n] = true
            names[#names + 1] = n
        end
    end
    if ns.preview then
        for n, m in pairs(ns.members) do if m.test then names[#names + 1] = n end end
        table.sort(names, function(a, b) return ns.members[a].previewIndex < ns.members[b].previewIndex end)
    else
        add("player")
        for i = 1, 4 do add("party" .. i) end
    end
    local now = GetTime()
    local have = {}
    for _, e in ipairs(KickEntries(now)) do have[e.name] = e end
    local order, parts = {}, {}
    for _, n in ipairs(names) do
        if have[n] then
            order[#order + 1] = n
            parts[#parts + 1] = format("%d) %s (%s)", #order, n, (ns.SpellInfo(have[n].id)) or "kick")
        end
    end
    ns.db.kickOrder = order
    if #order == 0 then
        ns.Print("No interrupts found in the party yet.")
        return
    end
    ns.Print("Kick order set: " .. table.concat(order, ", "))
    if announce and not ns.preview and IsInGroup() then
        local ch = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
        pcall(SendChatMessage, "Kick order: " .. table.concat(parts, "  "), ch)
    end
    ns:Refresh()
end

---------------------------------------------------------------------------
-- party keystones (players who run this addon answer with their key)
---------------------------------------------------------------------------

mp.keys = {}

local function OwnKey()
    local C = C_MythicPlus
    if not (C and C.GetOwnedKeystoneChallengeMapID and C.GetOwnedKeystoneLevel) then return end
    local map, level = Num(C.GetOwnedKeystoneChallengeMapID()), Num(C.GetOwnedKeystoneLevel())
    if map and level and level > 0 then return map, level end
end

local function DungeonName(map)
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local n = C_ChallengeMode.GetMapUIInfo(map)
        if type(n) == "string" and not issecret(n) then return n end
    end
    return "dungeon " .. map
end

mp.OwnKey, mp.DungeonName = OwnKey, DungeonName

function mp:PrintHistory()
    local h = ns.db.mpHistory
    if not h or #h == 0 then ns.Print("No finished keys recorded yet.") return end
    for i = 1, math.min(10, #h) do
        local e = h[i]
        ns.Print(format("%s  +%d %s  %s  %s  deaths %d", e.date or "", e.level, DungeonName(e.map),
            Clock(e.time), e.timed and "timed" or "over time", e.deaths or 0))
    end
end

function mp:PrintKeys()
    local any = false
    local map, level = OwnKey()
    if map then
        ns.Print(format("%s: +%d %s", UnitName("player"), level, DungeonName(map)))
        any = true
    end
    for name, k in pairs(mp.keys) do
        if ns.members[name] and not ns.members[name].isSelf then
            ns.Print(format("%s: +%d %s", name, k.level, DungeonName(k.map)))
            any = true
        end
    end
    if not any then ns.Print("No party keystones known yet. Players running SaltyM+Helper, Details, BigWigs or similar share theirs.") end
end

function mp:AnnounceKey()
    local map, level = OwnKey()
    if not map then ns.Print("You do not have a keystone.") return end
    if not IsInGroup() then ns.Print("You are not in a group.") return end
    local ch = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    pcall(SendChatMessage, format("My key: +%d %s", level, DungeonName(map)), ch)
end

SLASH_SALTYKEYS1 = "/skeys"
SlashCmdList["SALTYKEYS"] = function(msg)
    if msg and msg:lower():find("announce") then mp:AnnounceKey() else mp:PrintKeys() end
end

---------------------------------------------------------------------------
-- automatic combat logging
---------------------------------------------------------------------------

local weStarted = false
local function UpdateLogging()
    local db = ns.db
    if not (db and db.logEnabled and not db.syncOnly and LoggingCombat) then return end
    local _, itype, diff = GetInstanceInfo()
    local want = false
    if itype == "party" and diff == 8 then
        want = db.logMplus
    elseif itype == "raid" then
        if diff == 16 then want = db.logMythicRaid
        elseif diff == 15 then want = db.logHeroicRaid
        elseif diff == 14 then want = db.logNormalRaid end
    end
    local ok, logging = pcall(LoggingCombat)
    if not ok then return end
    if want and not logging then
        if pcall(LoggingCombat, true) then
            weStarted = true
            if db.logChat then ns.Print("Combat logging started.") end
        end
    elseif not want and weStarted and itype == "none" then
        if pcall(LoggingCombat, false) then
            weStarted = false
            if db.logChat then ns.Print("Combat logging stopped.") end
        end
    end
end

---------------------------------------------------------------------------
-- talking head
---------------------------------------------------------------------------

local thHooked
local function HookTalkingHead()
    if thHooked or not _G.TalkingHeadFrame then return end
    thHooked = true
    hooksecurefunc(_G.TalkingHeadFrame, "Show", function(f)
        if ns.db and ns.db.qolTalkingHead and ns.db.khEnabled and not ns.db.syncOnly then f:Hide() end
    end)
end

---------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------

mp.updaters[#mp.updaters + 1] = function(now)
    UpdateDeaths(now)
    UpdateIcons(now)
    UpdateKicks(now)
end
mp.slowUpdaters[#mp.slowUpdaters + 1] = function(now)
    PollDeaths()
    PollSated(now)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "CHALLENGE_MODE_START",
    "ADDON_LOADED", "GROUP_ROSTER_UPDATE" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event, arg1)
    if not ns.db then return end
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_TalkingHeadUI" then HookTalkingHead() end
    elseif event == "GROUP_ROSTER_UPDATE" then
        for name in pairs(mp.keys) do
            if not ns.members[name] then mp.keys[name] = nil end
        end
    else
        HookTalkingHead()
        UpdateLogging()
        if event == "CHALLENGE_MODE_START" then C_Timer.After(2, UpdateLogging) end
    end
end)

mp.creators.DEATHS, mp.creators.ICONS, mp.creators.KICKS = DTFrame, IconFrame, KickFrame
