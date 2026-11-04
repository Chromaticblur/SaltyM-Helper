-- Alerts.lua: small, useful on-screen reminders for pushing keys.
--   * Focus kick  : big "KICK FOCUS" when your focus target starts a cast and your interrupt is
--                   ready (dimmed while it is on cooldown, hidden for casts that can't be kicked)
--   * Repair      : "Repair needed" when your gear durability is low (out of combat)
--   * Healer mana : warns when the group's healer is running low on mana
--   * No target   : "NO TARGET" if you are fighting without a target
--   * Focus marker: tells the party which raid marker your focus gets (you set it yourself)
-- Ideas are common to several QoL addons; the code is written for this addon and avoids every
-- value the game marks "secret" (it hands those straight to widget methods instead).

local ADDON, ns = ...
local mp = ns.MP
local issecret = ns.issecret or issecretvalue or function() return false end
local floor, max, min, format = math.floor, math.max, math.min, string.format

mp.DEFAULT_POS.FKICK = { -200, 270 }
mp.DEFAULT_POS.ALERTS = { -130, 20 }

local function Num(v)
    if type(v) == "number" and not issecret(v) then return v end
end

local function Hex(key)
    local r, g, b = mp.RGB(key)
    return format("|cff%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

---------------------------------------------------------------------------
-- focus kick
---------------------------------------------------------------------------

local fk = { active = false, spell = nil, since = 0 }
mp.fk = fk
local fkFrame

local SOUNDS = { RAID_WARNING = "RAID_WARNING", READY_CHECK = "READY_CHECK", BOSS_WHISPER = "UI_RAID_BOSS_WHISPER_WARNING" }

local function FindInterrupt()
    fk.spell = nil
    for id, def in pairs(ns.SPELLS) do
        if def.cat == "INT" and IsPlayerSpell and IsPlayerSpell(id) then
            if not fk.spell or id < fk.spell then fk.spell = id end
        end
    end
end

local function FocusAttackable()
    local ok, can = pcall(function() return UnitExists("focus") and UnitCanAttack("player", "focus") end)
    return ok and not issecret(can) and can == true
end

-- true / false / a secret boolean (only ever handed to SetAlphaFromBoolean) / nil if no cast
local function NotInterruptible()
    local ok, name, _, _, _, _, _, _, ni = pcall(UnitCastingInfo, "focus")
    if ok and (issecret(name) or name) then return ni end
    local ok2, cname, _, _, _, _, _, cni = pcall(UnitChannelInfo, "focus")
    if ok2 and (issecret(cname) or cname) then return cni end
end

local function FocusIsCasting()
    local ok, name = pcall(UnitCastingInfo, "focus")
    if ok and (issecret(name) or name) then return true end
    local ok2, cname = pcall(UnitChannelInfo, "focus")
    return ok2 and (issecret(cname) or cname) and true or false
end

-- clean "is the cooldown running" flag, or nil when the game won't say
local function KickOnCooldown()
    if not fk.spell then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, fk.spell)
    if ok and type(info) == "table" and type(info.isActive) == "boolean" and not issecret(info.isActive) then
        return info.isActive
    end
end

local function FKFrame()
    if fkFrame then return fkFrame end
    local g = mp.NewFrame("FKICK", 260, 50)
    g.text = mp.FS(g)
    g.text:SetPoint("CENTER")
    fkFrame = g
    return g
end

local function Alpha(region, value, secretTrue, secretFalse)
    -- region:SetAlphaFromBoolean(boolean, whenTrue, whenFalse) accepts secret booleans
    if region.SetAlphaFromBoolean and issecret(value) then
        local ok = pcall(region.SetAlphaFromBoolean, region, value, secretTrue, secretFalse)
        if ok then return end
        region:SetAlpha(1)
        return
    end
    region:SetAlpha(value == true and secretTrue or secretFalse)
end

local function UpdateFocusKick(now)
    local db = ns.db
    local g = fkFrame
    if not db.fkEnabled then
        if g then g:Hide() end
        return
    end
    local demo = ns.editMode or ns.preview or (fk.testUntil and now < fk.testUntil)
    if not demo and fk.active and now - fk.since > 15 then fk.active = false end
    if not demo and not fk.active then
        if g then g:Hide() end
        return
    end
    g = FKFrame()
    ns.ApplyFont(g.text, db.fkSize)
    g.text:SetText(db.fkText)
    g.text:SetTextColor(mp.RGB(db.fkColor))
    g:SetSize(max(120, g.text:GetStringWidth() + 30), db.fkSize + 16)
    mp.Look(g, 0)
    if demo then
        g:SetAlpha(1)
        g.text:SetAlpha(1)
    else
        -- the whole frame hides for casts that cannot be interrupted ...
        local ni = NotInterruptible()
        if ni == nil then
            g:SetAlpha(1)
        elseif issecret(ni) then
            Alpha(g, ni, 0, 1)
        else
            g:SetAlpha(ni == true and 0 or 1)
        end
        -- ... and the text fades while your interrupt is on cooldown
        local cd = KickOnCooldown()
        if cd == nil then
            g.text:SetAlpha(1)
        elseif cd then
            g.text:SetAlpha(db.fkOnlyReady and 0 or 0.3)
        else
            g.text:SetAlpha(1)
        end
    end
    g:Show()
end

local function FocusCastStarted()
    local db = ns.db
    if not db.fkEnabled or not FocusAttackable() then return end
    fk.active, fk.since = true, GetTime()
    local cd = KickOnCooldown()
    if db.fkSoundOn and cd ~= true then
        if ns.Snd and ns.Snd.Alert("FocusKick") then return end
        local kit = SOUNDKIT and SOUNDKIT[SOUNDS[db.fkSound] or ""]
        if kit then pcall(PlaySound, kit) end
    end
end

local function FocusCastEnded()
    if fk.active and not FocusIsCasting() then fk.active = false end
end

function mp:TestFocusKick()
    fk.testUntil = GetTime() + 3
    local db = ns.db
    if db.fkSoundOn and ns.Snd and ns.Snd.Alert("FocusKick") then return end
    local kit = db.fkSoundOn and SOUNDKIT and SOUNDKIT[SOUNDS[db.fkSound] or ""]
    if kit then pcall(PlaySound, kit) end
end

-- Tell the party which marker your focus gets, as a clickable raid icon in chat
-- ("SaltyM+Helper: My focus kick marker is {rt8}"), so everyone knows which mob you are kicking. You choose the
-- marker in the settings and set it on the mob yourself.
local MARKER_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
mp.MARKER_NAMES = MARKER_NAMES
local lastAnnounce = 0

function mp:AnnounceFocus(force)
    local db = ns.db
    if not db or db.syncOnly then return false end
    if not (force or db.fkAnnounceOn) then return false end
    local now = GetTime()
    if not force and now - lastAnnounce < 20 then return false end
    if not IsInGroup() then
        if force then ns.Print("You are not in a group.") end
        return false
    end
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
        if force then ns.Print("Chat is locked right now (key or boss fight).") end
        return false
    end
    local marker = math.max(1, math.min(8, db.fkMarkerIndex or 8))
    local text = "SaltyM+Helper: My focus kick marker is {rt" .. marker .. "}"
    local channel = IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok = pcall(send, text, channel)
    if ok then lastAnnounce = now end
    return ok
end

---------------------------------------------------------------------------
-- repair / healer mana / no target
---------------------------------------------------------------------------

local alerts = { repairPct = nil, manaText = nil }
local alFrame

local function ReadDurability()
    local lowest
    for slot = 1, 19 do
        local ok, cur, mx = pcall(GetInventoryItemDurability, slot)
        cur, mx = ok and Num(cur), ok and Num(mx)
        if cur and mx and mx > 0 then
            local pct = cur / mx * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    alerts.repairPct = lowest
end

local function ReadHealerMana()
    alerts.manaText = nil
    local db = ns.db
    if not db.alEnabled or not db.alMana or not IsInInstance() then return end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            local okRole, role = pcall(UnitGroupRolesAssigned, u)
            if okRole and role == "HEALER" and not issecret(role) then
                local pct
                if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
                    local ok, v = pcall(UnitPowerPercent, u, Enum.PowerType.Mana, true, CurveConstants.ScaleTo100)
                    pct = ok and Num(v)
                end
                if not pct then
                    local ok1, cur = pcall(UnitPower, u, Enum.PowerType.Mana)
                    local ok2, mx = pcall(UnitPowerMax, u, Enum.PowerType.Mana)
                    cur, mx = ok1 and Num(cur), ok2 and Num(mx)
                    if cur and mx and mx > 0 then pct = cur / mx * 100 end
                end
                local okName, name = pcall(UnitName, u)
                if pct and pct < db.alManaPct and okName and type(name) == "string" and not issecret(name) then
                    alerts.manaText = format("Healer mana %d%% (%s)", floor(pct + 0.5), name)
                    return
                end
            end
        end
    end
end

local function AlertsFrame()
    if alFrame then return alFrame end
    local g = mp.NewFrame("ALERTS", 260, 40)
    g.text = mp.FS(g)
    g.text:SetPoint("TOP", 0, -6)
    g.text:SetWidth(250)
    g.text:SetJustifyH("CENTER")
    alFrame = g
    return g
end

local function UpdateAlerts()
    local db = ns.db
    local g = alFrame
    local lines = {}
    if not db.alEnabled then
        if g then g:Hide() end
        return
    end
    local demo = ns.editMode or ns.preview
    local inCombat = UnitAffectingCombat("player")
    if demo then
        lines[#lines + 1] = Hex("ORANGE") .. "Repair needed (24%)|r"
        lines[#lines + 1] = Hex("CYAN") .. "Healer mana 31% (Maeow)|r"
        lines[#lines + 1] = Hex("RED") .. "NO TARGET|r"
    else
        if db.alRepair and not inCombat and alerts.repairPct and alerts.repairPct < db.alRepairPct then
            lines[#lines + 1] = format("%sRepair needed (%d%%)|r", Hex("ORANGE"), floor(alerts.repairPct + 0.5))
        end
        if alerts.manaText then lines[#lines + 1] = Hex("CYAN") .. alerts.manaText .. "|r" end
        if db.alNoTarget and inCombat and not UnitExists("target") then
            lines[#lines + 1] = Hex("RED") .. "NO TARGET|r"
        end
    end
    if #lines == 0 then
        if g then g:Hide() end
        return
    end
    g = AlertsFrame()
    ns.ApplyFont(g.text, db.alSize)
    g.text:SetText(table.concat(lines, "\n"))
    g:SetSize(260, #lines * (db.alSize + 4) + 14)
    mp.Look(g, 0)
    g:Show()
end

---------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------

mp.updaters[#mp.updaters + 1] = function(now)
    UpdateFocusKick(now)
    UpdateAlerts()
end
mp.slowUpdaters[#mp.slowUpdaters + 1] = function()
    ReadHealerMana()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_SPECIALIZATION_CHANGED", "SPELLS_CHANGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_FOCUS_CHANGED", "UPDATE_INVENTORY_DURABILITY", "READY_CHECK" }) do
    ev:RegisterEvent(e)
end
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    ev:RegisterUnitEvent(e, "focus")
end
ev:SetScript("OnEvent", function(_, event)
    if not ns.db or ns.db.syncOnly then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        FocusCastStarted()
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        FocusCastEnded()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if FocusAttackable() and FocusIsCasting() then FocusCastStarted() else fk.active = false end
    elseif event == "UPDATE_INVENTORY_DURABILITY" then
        ReadDurability()
    elseif event == "READY_CHECK" then
        if ns.db.fkAnnounceReady then mp:AnnounceFocus(false) end
    else
        if event == "PLAYER_ENTERING_WORLD" and ns.db.fkAnnounceEnter then
            local inInstance, kind = IsInInstance()
            if inInstance and kind == "party" then C_Timer.After(6, function() mp:AnnounceFocus(false) end) end
        end
        FindInterrupt()
        ReadDurability()
    end
end)

mp.creators.FKICK, mp.creators.ALERTS = FKFrame, AlertsFrame
