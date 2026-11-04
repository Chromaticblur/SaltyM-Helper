-- KeyList.lua: the party's keystones, outside of dungeons, with click-to-teleport.
--
-- Shown while you are in a party and NOT inside an instance (and never during a key). Each row is
-- one player's keystone: dungeon icon, level, player, dungeon, and the state of the teleport
-- spell for that dungeon (ready / on cooldown / not learned). Click a row to cast the teleport,
-- shift-click to post that key in party chat.
--
-- Keys are exchanged over the public key-sharing channels other addons already use, so players
-- running Details!, BigWigs-style key sharing, LibKeystone users, etc. show up without needing
-- this addon:
--     "LibKS"          : "<level>,<mapID>,<rating>"  and the request "R"
--     "WA-KeyStGrList" : "KSGL:Send:<mapID>:<level>:<activityID>:<groupID>:<resilient>"
--                        and the request "KSGL:Request:0"
-- Teleports are a SecureActionButton aimed at the row under the mouse. Secure attributes are
-- never touched in combat (the game would taint them; teleports cannot be cast in combat anyway).

local ADDON, ns = ...
local mp = ns.MP
local issecret = ns.issecret or issecretvalue or function() return false end
local floor, max, format = math.floor, math.max, string.format
local Clock = mp.Clock

mp.DEFAULT_POS.KEYS = { -430, -40 }

local PREFIX_LIBKS, PREFIX_KSGL = "LibKS", "WA-KeyStGrList"

-- Dungeon (challenge mode map) -> teleport spell. A pair is { Alliance, Horde }.
-- These are public game identifiers; a dungeon that is missing or has no learned spell simply
-- shows "no port".
local PORTS = {
    [438] = 410080, [456] = 424142, [507] = 445424, [2] = 131204,
    [161] = 159898, [165] = 159899, [168] = 159901,
    [198] = 424163, [199] = 424153, [200] = 393764, [206] = 410078, [210] = 393766, [239] = 1254551,
    [244] = 424187, [245] = 410071, [247] = { 467553, 467555 }, [248] = 424167, [249] = 1286831,
    [250] = 1286828, [251] = 410074, [353] = { 445418, 464256 }, [370] = 373274,
    [375] = 354464, [376] = 354462, [378] = 354465, [382] = 354467, [391] = 367416, [392] = 367416,
    [399] = 393256, [400] = 393262, [401] = 393279, [402] = 393273, [403] = 393222, [404] = 393276,
    [405] = 393267, [406] = 393283, [463] = 424197, [464] = 424197,
    [499] = 445444, [500] = 445443, [501] = 445269, [502] = 445416, [503] = 445417, [504] = 445441,
    [505] = 445414, [506] = 445440, [525] = 1216786, [542] = 1237215,
    [556] = 1254555, [557] = 1254400, [558] = 1254572, [559] = 1254563, [560] = 1254559, [583] = 1254551,
    [584] = 1286801, [585] = 1286804, [586] = 1286807, [587] = 1286809, [588] = 1286812,
}

local function PortSpell(mapID)
    local p = PORTS[mapID]
    if type(p) == "table" then
        return (UnitFactionGroup("player") == "Horde") and p[2] or p[1]
    end
    return p
end

local function Known(spellID)
    if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
    if IsSpellKnown and IsSpellKnown(spellID) then return true end
    return false
end

-- "ready", seconds left, or nil when the spell is not learned
local function PortStatus(mapID)
    local id = PortSpell(mapID)
    if not id then return "none" end
    if not Known(id) then return "unknown", nil, id end
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" then
            local s, d = info.startTime, info.duration
            if type(s) == "number" and type(d) == "number" and not issecret(s) and not issecret(d)
                and d > 2.5 and s > 0 then
                local left = s + d - GetTime()
                if left > 0 then return "cooldown", left, id end
            end
        end
    end
    return "ready", nil, id
end

---------------------------------------------------------------------------
-- key sharing
---------------------------------------------------------------------------

local lastReply, lastRequest = 0, 0
local dirty = true

local function Rating()
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, sum = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(sum) == "table" and type(sum.currentSeasonScore) == "number"
            and not issecret(sum.currentSeasonScore) then
            return floor(sum.currentSeasonScore)
        end
    end
    return 0
end

local function PartySend(prefix, msg)
    if not IsInGroup() then return end
    if ns.MessagingLocked and ns.MessagingLocked() then return end
    pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "PARTY")
end

local function SendOwnKey()
    local map, level = mp.OwnKey()
    if not map then return end
    PartySend(PREFIX_LIBKS, format("%d,%d,%d", level, map, Rating()))
    PartySend(PREFIX_KSGL, format("KSGL:Send:%d:%d:0:0:0", map, level))
end

local function RequestKeys()
    local now = GetTime()
    if now - lastRequest < 5 then return end
    lastRequest = now
    PartySend(PREFIX_LIBKS, "R")
    PartySend(PREFIX_KSGL, "KSGL:Request:0")
    SendOwnKey()
end

local function ReplyWithKey()
    local now = GetTime()
    if now - lastReply < 3 then return end
    lastReply = now
    C_Timer.After(0.2 + math.random() * 0.8, SendOwnKey)
end

local function Store(sender, map, level)
    if not (map and level and level >= 1 and level <= 99) then return end
    local short = Ambiguate(sender, "none")
    if short == UnitName("player") then return end
    mp.keys[short] = { map = map, level = level }
    dirty = true
end

local function OnAddonMessage(prefix, msg, channel, sender)
    if issecret(prefix) or issecret(msg) or issecret(sender)
        or type(msg) ~= "string" or type(sender) ~= "string" then return end
    if channel ~= "PARTY" then return end
    if prefix == PREFIX_LIBKS then
        if msg == "R" then ReplyWithKey(); return end
        local level, map = msg:match("^(%d+),(%d+),%d+$")
        Store(sender, tonumber(map), tonumber(level))
    elseif prefix == PREFIX_KSGL then
        local kind = msg:match("^KSGL:(%a+):")
        if kind == "Send" then
            local map, level = msg:match("^KSGL:Send:(%d+):(%d+)")
            Store(sender, tonumber(map), tonumber(level))
        elseif kind == "Request" then
            ReplyWithKey()
        end
    end
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------

local ROW_H, ICON = 36, 28
local win
local rows = {}
local hover -- the single secure button

local function ChatKey(entry)
    if not IsInGroup() then return end
    local text
    local dname = mp.DungeonName(entry.map)
    if entry.isSelf then
        text = format("My key: +%d %s", entry.level, dname)
    else
        text = format("%s's key: +%d %s", entry.name, entry.level, dname)
    end
    pcall(SendChatMessage, text, IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY")
end

local function HoverButton()
    if hover then return hover end
    local b = CreateFrame("Button", "SaltyMPlusHelperPortButton", win, "InsecureActionButtonTemplate")
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type1", "spell")
    b:Hide()
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self:ClearAllPoints()
        self:Hide()
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(format("+%d %s", e.level, mp.DungeonName(e.map)), 1, 0.82, 0.3)
        local status, left = PortStatus(e.map)
        if status == "ready" then
            GameTooltip:AddLine("Click to teleport", 0.3, 1, 0.4)
        elseif status == "cooldown" then
            GameTooltip:AddLine("Teleport ready in " .. Clock(left), 1, 0.4, 0.3)
        elseif status == "unknown" then
            GameTooltip:AddLine("You have not learned this teleport", 0.7, 0.7, 0.75)
        else
            GameTooltip:AddLine("No teleport known for this dungeon", 0.7, 0.7, 0.75)
        end
        GameTooltip:AddLine("Shift-click: post this key in party chat", 0.6, 0.65, 0.75)
        GameTooltip:Show()
    end)
    b:HookScript("OnClick", function(self)
        if self.entry and IsShiftKeyDown() then ChatKey(self.entry) end
    end)
    hover = b
    return b
end

local function AttachHover(row)
    local e = row.entry
    if not e or InCombatLockdown() or ns.editMode or not ns.db.klClick then return end
    local status, _, spellID = PortStatus(e.map)
    local b = HoverButton()
    b.entry = e
    if spellID and (status == "ready" or status == "cooldown") then
        b:SetAttribute("spell", spellID)
    else
        b:SetAttribute("spell", nil) -- nothing to cast; the button still gives the tooltip and shift-click
    end
    b:ClearAllPoints()
    b:SetAllPoints(row)
    b:SetFrameLevel(row:GetFrameLevel() + 5)
    b:Show()
end

local function Win()
    if win then return win end
    win = mp.NewFrame("KEYS", ns.db.klWidth, 80)
    win.title = mp.FS(win)
    win.title:SetPoint("TOPLEFT", 8, -6)
    win.title:SetText("Party keystones")
    win.title:SetTextColor(0.7, 0.75, 0.85)
    return win
end

local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win)
    r:EnableMouse(true)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON, ICON)
    r.icon:SetPoint("LEFT", 4, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.level = mp.FS(r)
    r.level:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.level:SetWidth(34)
    r.level:SetJustifyH("LEFT")
    r.name = mp.FS(r)
    r.name:SetPoint("TOPLEFT", r.level, "TOPRIGHT", 2, 8)
    r.name:SetJustifyH("LEFT")
    r.dungeon = mp.FS(r)
    r.dungeon:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
    r.dungeon:SetJustifyH("LEFT")
    r.state = mp.FS(r)
    r.state:SetPoint("RIGHT", -8, 0)
    r.state:SetJustifyH("RIGHT")
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.hl:Hide()
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        AttachHover(self)
    end)
    r:SetScript("OnLeave", function(self)
        -- the secure button sits on top while hovered; hide the highlight only if it is not
        if not (hover and hover:IsShown() and hover.entry == self.entry and MouseIsOver(hover)) then
            self.hl:Hide()
        end
    end)
    rows[i] = r
    return r
end

local SAMPLE = {
    { name = "Daegtides", class = "SHAMAN", map = 503, level = 14 },
    { name = "Maeow", class = "DRUID", map = 558, level = 12 },
    { name = "Buffalows", class = "WARRIOR", map = 505, level = 15 },
    { name = "Rykoojudge", class = "PALADIN", map = 560, level = 13 },
}

local function Entries()
    local out = {}
    if ns.editMode or ns.preview then
        for _, e in ipairs(SAMPLE) do out[#out + 1] = e end
        return out
    end
    local units = { "player", "party1", "party2", "party3", "party4" }
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local ok, name = pcall(UnitName, u)
            if ok and type(name) == "string" and not issecret(name) then
                local _, class = UnitClass(u)
                if u == "player" then
                    if ns.db.klIncludeSelf then
                        local map, level = mp.OwnKey()
                        if map then out[#out + 1] = { name = name, class = class, map = map, level = level, isSelf = true } end
                    end
                else
                    local k = mp.keys[name]
                    if k then out[#out + 1] = { name = name, class = class, map = k.map, level = k.level } end
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return out
end

local function ShouldShow()
    local db = ns.db
    if not db.klEnabled then return false end
    if ns.editMode or ns.preview then return true end
    if mp.run.active then return false end
    if not IsInGroup() then return false end
    local inInstance = IsInInstance()
    if db.klWhen == "OUTSIDE" and inInstance then return false end
    return true
end

local acc = 0
local function Update(now, force)
    local db = ns.db
    if not ShouldShow() then
        if win then win:Hide() end
        if hover and hover:IsShown() and not InCombatLockdown() then hover:Hide() end
        return
    end
    if not force and not dirty and now - acc < 0.5 then return end
    acc, dirty = now, false
    local g = Win()
    local list = Entries()
    if #list == 0 and not (ns.editMode or ns.preview) then
        g:Hide()
        return
    end
    g:SetScale(db.klScale)
    local width = db.klWidth
    ns.ApplyFont(g.title, 11)
    for i, e in ipairs(list) do
        local r = Row(i)
        r.entry = e
        r:SetSize(width - 8, ROW_H)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", g, "TOPLEFT", 4, -22 - (i - 1) * ROW_H)
        local mapName, _, _, tex = C_ChallengeMode.GetMapUIInfo(e.map)
        if type(mapName) ~= "string" or issecret(mapName) then mapName = "Dungeon " .. e.map end
        r.icon:SetTexture(tex)
        ns.ApplyFont(r.level, 15)
        ns.ApplyFont(r.name, 12)
        ns.ApplyFont(r.dungeon, 10)
        ns.ApplyFont(r.state, 11)
        r.level:SetText("|cffffd24d+" .. e.level .. "|r")
        local cr, cg, cb = ns.ClassRGB(e.class)
        r.name:SetText(e.name)
        r.name:SetTextColor(cr, cg, cb)
        r.dungeon:SetText(mapName)
        r.dungeon:SetTextColor(0.7, 0.73, 0.8)
        r.name:SetWidth(width - 120)
        r.dungeon:SetWidth(width - 120)
        local status, left = PortStatus(e.map)
        if status == "ready" then
            r.state:SetText("READY")
            r.state:SetTextColor(0.3, 1, 0.4)
            r.icon:SetDesaturated(false)
        elseif status == "cooldown" then
            r.state:SetText(Clock(left))
            r.state:SetTextColor(1, 0.45, 0.3)
            r.icon:SetDesaturated(true)
        else
            r.state:SetText(status == "unknown" and "not learned" or "no port")
            r.state:SetTextColor(0.55, 0.58, 0.65)
            r.icon:SetDesaturated(true)
        end
        r:Show()
    end
    for i = #list + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    g:SetSize(width, 28 + max(1, #list) * ROW_H)
    mp.Look(g, db.klBg)
    g:Show()
end

---------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------

mp.updaters[#mp.updaters + 1] = function(now) Update(now) end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "BAG_UPDATE_DELAYED", "PLAYER_REGEN_ENABLED" }) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event, ...)
    if ns.db and ns.db.syncOnly then return end
    if event == "CHAT_MSG_ADDON" then
        if ns.db then OnAddonMessage(...) end
        return
    end
    if not ns.db then return end
    dirty = true
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        if IsInGroup() then C_Timer.After(2, RequestKeys) end
        for name in pairs(mp.keys) do -- forget people who left
            if not UnitInParty(name) then mp.keys[name] = nil end
        end
    elseif event == "BAG_UPDATE_DELAYED" and IsInGroup() then
        C_Timer.After(1, SendOwnKey)
    end
end)

do
    local reg = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
    if reg then
        pcall(reg, PREFIX_LIBKS)
        pcall(reg, PREFIX_KSGL)
    end
end

function mp:RequestKeys() lastRequest = 0; RequestKeys() end
mp.PortStatus = PortStatus

mp.creators.KEYS = Win
