-- Display.lua: draws the cooldowns.
--   * Attached mode: a small "strip" of icons, bars, or both next to each member's
--     party frame (side, offset, rows and growth are adjustable).
--   * Window mode: a movable list (also the fallback for members whose frame can't be found,
--     for example when no party frame is found).
--   * Offensive cooldowns can live in their own window.

local ADDON, ns = ...
local SPELLS = ns.SPELLS
local members = ns.members

local FLAT = "Interface\\Buttons\\WHITE8x8"
local WIDTH, ROW_H, HEADER_H = 250, 22, 24
local PLATE_STEP = 96

ns.ALL_KEYS = { "ALL" }
ns.SPLIT_KEYS = ns.CATEGORIES
ns.TITLES = { ALL = "SaltyM+ Cooldowns", PREVIEW = "Preview party frames", CCTRACK = "Crowd Control",
    CTEXT = "Combat text", CTIMER = "Combat timer", MPHUD = "Key HUD", FKICK = "Focus kick", ALERTS = "Reminders",
    DEATHS = "Death alert", ICONS = "Brez / Lust icons", KICKS = "Kick order", KEYS = "Party keystones" }
ns.EXTRA_KEYS = { "CCTRACK", "MPHUD", "CTEXT", "CTIMER", "FKICK", "DEATHS", "ALERTS", "ICONS", "KICKS", "KEYS" }
for cat, name in pairs(ns.CAT_NAMES) do ns.TITLES[cat] = name end
local TITLES = ns.TITLES

-- Default top-left corner of each movable frame, as an offset from the screen center.
local DEFAULT_POS = {
    ALL = { -330, 220 }, OFF = { -330, 20 },
    INT = { -600, 230 }, CC = { -350, 230 }, BREZ = { -600, 90 }, BL = { -350, 90 },
    EXT = { -600, -10 }, DEF = { -350, -10 }, UTIL = { -600, -150 },
    PREVIEW = { -330, 140 }, CCTRACK = { 20, 230 },
}

local groups = {}
ns.groups = groups
local strips = {}
local plates = {}
local holder

---------------------------------------------------------------------------
-- Look and feel helpers (shared with the CC tracker)
---------------------------------------------------------------------------

local FONTS = {
    ["Friz Quadrata"] = STANDARD_TEXT_FONT, ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    ["Skurri"] = "Fonts\\skurri.ttf", ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
}
local TEXTURES = {
    ["Flat"] = FLAT, ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["Raid"] = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
}
ns.READY_COLORS = {
    GREEN = { 0.3, 1, 0.4 }, CYAN = { 0.3, 0.9, 1 }, GOLD = { 1, 0.85, 0.2 }, WHITE = { 1, 1, 1 },
}

local function LSM()
    local stub = _G.LibStub
    return stub and stub("LibSharedMedia-3.0", true) or nil
end

function ns.ResolveFont()
    local name = ns.db.fontName
    if FONTS[name] then return FONTS[name] end
    local lsm = LSM()
    local path = lsm and lsm:Fetch("font", name, true)
    return path or STANDARD_TEXT_FONT
end

function ns.ResolveTexture()
    local name = ns.db.barTexture
    if TEXTURES[name] then return TEXTURES[name] end
    local lsm = LSM()
    local path = lsm and lsm:Fetch("statusbar", name, true)
    return path or FLAT
end

function ns.OutlineFlag()
    local o = ns.db.outline
    if o == "NONE" then return "" end
    return o or "OUTLINE"
end

-- Apply the chosen font to a FontString, only touching it when something changed.
function ns.ApplyFont(fs, size)
    local font, flag = ns.ResolveFont(), ns.OutlineFlag()
    local sig = font .. "|" .. size .. "|" .. flag
    if fs.fontSig ~= sig then
        fs.fontSig = sig
        fs:SetFont(font, size, flag)
    end
end

function ns.ClassRGB(class)
    local c = class and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end
local ClassRGB = ns.ClassRGB

function ns.FmtTime(rem)
    if rem >= 60 then return format("%d:%02d", floor(rem / 60), floor(rem % 60)) end
    if rem >= 10 or not ns.db.decimals then return format("%d", ceil(rem)) end
    return format("%.1f", rem)
end
local FmtTime = ns.FmtTime

ns.URGENT_COLORS = { RED = { 1, 0.25, 0.2 }, ORANGE = { 1, 0.6, 0.1 }, YELLOW = { 1, 0.9, 0.2 } }

-- Colour of the running timer text: white or class coloured, switching to the urgent colour
-- when only a few seconds are left (the warning colour is off when "urgent seconds" is 0).
function ns.TimerRGB(e)
    local db = ns.db
    if db.urgentEnabled and db.urgentSecs > 0 and e.rem > 0 and e.rem <= db.urgentSecs then
        local c = ns.URGENT_COLORS[db.urgentColor] or ns.URGENT_COLORS.RED
        return c[1], c[2], c[3]
    end
    if db.timerColor == "CLASS" then return ns.ClassRGB(e.class) end
    return 1, 1, 1
end

function ns.StateAlpha(e)
    local db = ns.db
    if e.unknown then return db.unknownAlpha end
    if e.rem > 0 then return db.cdAlpha end
    return db.readyAlpha
end

function ns.ReadyRGB()
    local c = ns.READY_COLORS[ns.db.readyColor] or ns.READY_COLORS.GREEN
    return c[1], c[2], c[3]
end

---------------------------------------------------------------------------
-- Movable frames (windows and the preview holder)
---------------------------------------------------------------------------

function ns.ApplyPos(g)
    g:ClearAllPoints()
    local p = ns.db.pos[g.key]
    if p then
        g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    else
        local d = DEFAULT_POS[g.key] or (ns.MP and ns.MP.DEFAULT_POS[g.key]) or DEFAULT_POS.ALL
        g:SetPoint("TOPLEFT", UIParent, "CENTER", d[1], d[2])
    end
end
local ApplyPos = ns.ApplyPos

-- If another addon (EllesmereUI's unlock mode, for example) re-anchored a frame to the
-- screen center, convert it back to a top-left anchor in the same spot so it grows
-- downward and the position is saved. Frames anchored to other frames are left alone.
function ns.NormalizeGroup(g)
    if g.moving or g:GetNumPoints() ~= 1 then return end
    local point, relTo = g:GetPoint()
    if point == "TOPLEFT" or relTo ~= UIParent then return end
    local left, top = g:GetLeft(), g:GetTop()
    if left and top then
        ns.db.pos[g.key] = { left, top }
        ApplyPos(g)
    end
end
local NormalizeGroup = ns.NormalizeGroup

---------------------------------------------------------------------------
-- Grid and snapping (move mode). Positions snap to the grid in screen pixels, and optionally
-- to the edges of the other movable frames.
---------------------------------------------------------------------------

local grid
local function GridFrame()
    if grid then return grid end
    grid = CreateFrame("Frame", nil, UIParent)
    grid:SetAllPoints(UIParent)
    grid:SetFrameStrata("BACKGROUND")
    grid:EnableMouse(false)
    grid.lines = {}
    grid.sig = ""
    grid:Hide()
    return grid
end

local function LineAt(i)
    local l = grid.lines[i]
    if not l then
        l = grid:CreateTexture(nil, "BACKGROUND")
        grid.lines[i] = l
    end
    return l
end

function ns.UpdateGrid()
    local db = ns.db
    if not db then return end
    local show = ns.editMode and db.gridShow and db.snapOn
    if not show then
        if grid then grid:Hide() end
        return
    end
    local f = GridFrame()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local size = max(4, db.snapSize or 8)
    local sig = format("%d|%d|%d|%.2f", w, h, size, db.gridAlpha or 0.18)
    if f.sig ~= sig then
        f.sig = sig
        local n = 0
        local step = size
        -- never draw more than ~140 lines per direction: bigger cells are drawn, not smaller ones
        while w / step > 140 or h / step > 140 do step = step * 2 end
        local a = db.gridAlpha or 0.18
        for x = 0, w, step do
            n = n + 1
            local l = LineAt(n)
            local major = (x / step) % 4 == 0
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
            l:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
            l:SetWidth(1)
            l:SetColorTexture(0.45, 0.75, 1, major and a * 1.8 or a)
            l:Show()
        end
        for y = 0, h, step do
            n = n + 1
            local l = LineAt(n)
            local major = (y / step) % 4 == 0
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
            l:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
            l:SetHeight(1)
            l:SetColorTexture(0.45, 0.75, 1, major and a * 1.8 or a)
            l:Show()
        end
        for i = n + 1, #f.lines do f.lines[i]:Hide() end
    end
    f:Show()
end

local movables = {}

local function SnapFrame(g)
    local db = ns.db
    if not db.snapOn then return end
    local left, top = g:GetLeft(), g:GetTop()
    if not (left and top) then return end
    local es = g:GetScale() or 1
    local grid = max(1, db.snapSize or 8)
    local W, H = g:GetWidth() * es, g:GetHeight() * es
    local L, T = left * es, top * es
    local nl, nt = floor(L / grid + 0.5) * grid, floor(T / grid + 0.5) * grid
    if db.snapEdges then
        -- line up with the edges of the other visible frames when one is within 8 pixels
        local bx, bxD, by, byD = nil, 8, nil, 8
        for _, o in pairs(movables) do
            if o ~= g and o:IsShown() and o:GetLeft() then
                local os = o:GetScale() or 1
                local ol, ot = o:GetLeft() * os, o:GetTop() * os
                local ow, oh = o:GetWidth() * os, o:GetHeight() * os
                for _, tx in ipairs({ ol, ol + ow }) do
                    for _, mine in ipairs({ { L, 0 }, { L + W, -W } }) do
                        local d = math.abs(mine[1] - tx)
                        if d < bxD then bx, bxD = tx + mine[2], d end
                    end
                end
                for _, ty in ipairs({ ot, ot - oh }) do
                    for _, mine in ipairs({ { T, 0 }, { T - H, H } }) do
                        local d = math.abs(mine[1] - ty)
                        if d < byD then by, byD = ty + mine[2], d end
                    end
                end
            end
        end
        if bx then nl = bx end
        if by then nt = by end
    end
    ns.db.pos[g.key] = { nl / es, nt / es }
end


---------------------------------------------------------------------------
-- Click a frame once in move mode to select it, then nudge it with the arrow keys
-- (Shift = bigger steps). Keys other than the arrows still reach the game.
---------------------------------------------------------------------------

local nudger = CreateFrame("Frame", nil, UIParent)
nudger:EnableKeyboard(false)

function ns.Select(g)
    local old = ns.selected
    ns.selected = g
    nudger:EnableKeyboard(g ~= nil and ns.editMode and ns.db.nudgeOn and true or false)
    if old ~= g and ns.Refresh then ns:Refresh() end
end

function ns.Nudge(dx, dy)
    local g = ns.selected
    if not g or not g.key then return end
    local left, top = g:GetLeft(), g:GetTop()
    if not (left and top) then return end
    ns.db.pos[g.key] = { left + dx, top + dy }
    ns.ApplyPos(g)
    ns.nudgeText = format("%s  x %d  y %d", ns.TITLES[g.key] or g.key, floor(left + dx + 0.5), floor(top + dy + 0.5))
end

local ARROWS = { UP = { 0, 1 }, DOWN = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 } }
nudger:SetScript("OnKeyDown", function(self, key)
    local a = ARROWS[key]
    if a and ns.selected and ns.editMode and ns.db.nudgeOn then
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
        local step = IsShiftKeyDown() and (ns.db.nudgeShift or 10) or 1
        ns.Nudge(a[1] * step, a[2] * step)
    elseif not InCombatLockdown() then
        self:SetPropagateKeyboardInput(true)
    end
end)

function ns.EditBorder(g)
    if ns.selected == g then return 1, 0.82, 0.2, 1 end
    return 0.2, 0.6, 1, 1
end

function ns.MakeMovable(g, key)
    movables[key] = g
    g.key = key
    g:SetClampedToScreen(true)
    g:SetMovable(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and ns.editMode and ns.db.nudgeOn then ns.Select(self) end
    end)
    g:SetScript("OnDragStart", function(self)
        if ns.editMode then
            self.moving = true
            self:StartMoving()
        end
    end)
    -- in move mode: right-click opens this frame's page in the settings window
    g:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and ns.editMode and ns.UI and ns.UI.OpenFor then
            ns.UI:OpenFor(self.key)
        end
    end)
    g:SetScript("OnEnter", function(self)
        if not ns.editMode then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Drag to move, or click then use the arrow keys (Shift = bigger steps)", 1, 1, 1)
        GameTooltip:AddLine("Right-click for this module's settings", 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    g:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.moving = false
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then ns.db.pos[self.key] = { left, top } end
        SnapFrame(self)
        ApplyPos(self) -- re-anchor to the top-left so the frame grows downward
    end)
end
local MakeMovable = ns.MakeMovable

-- Backdrop colours for a movable frame; the blue look while moving things.
function ns.EditLook(g, edit)
    local db = ns.db
    if edit then
        g:SetBackdropColor(0.05, 0.1, 0.2, 0.92)
        g:SetBackdropBorderColor(ns.EditBorder(g))
    elseif g.key == "PREVIEW" then
        g:SetBackdropColor(0, 0, 0, 0)
        g:SetBackdropBorderColor(0, 0, 0, 0)
    elseif db.winStyle ~= "CLASSIC" then
        -- sleek: no block behind the icons unless you ask for one with the slider
        g:SetBackdropColor(0.04, 0.04, 0.07, db.winBg or 0)
        g:SetBackdropBorderColor(0, 0, 0, db.winBorder and (db.winBg or 0) > 0 and db.borderAlpha or 0)
    else
        g:SetBackdropColor(0.05, 0.05, 0.08, db.bgAlpha)
        g:SetBackdropBorderColor(0, 0, 0, db.borderAlpha)
    end
    if g.edit ~= edit then
        g.edit = edit
        g:EnableMouse(edit) -- click-through unless you are moving things
    end
end
local EditLook = ns.EditLook

function ns.NewBackdropFrame(name)
    local g = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    g:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    return g
end
local NewBackdropFrame = ns.NewBackdropFrame

---------------------------------------------------------------------------
-- Window (list) mode
---------------------------------------------------------------------------

function ns.GetGroup(key)
    local g = groups[key]
    if g then return g end
    g = NewBackdropFrame("SaltyMPlusHelperGroup" .. key)
    g.rows = {}
    g.srows = {}
    g:SetSize(WIDTH, 60)
    MakeMovable(g, key)
    g.title = g:CreateFontString(nil, "OVERLAY")
    g.title:SetPoint("TOPLEFT", 8, -6)
    g.empty = g:CreateFontString(nil, "OVERLAY")
    g:SetScale(ns.db.scale)
    ApplyPos(g)
    g:Hide()
    groups[key] = g
    return g
end
local GetGroup = ns.GetGroup

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
    r.label = r:CreateFontString(nil, "OVERLAY")
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 5, 0)
    r.label:SetWidth(WIDTH - 12 - ROW_H - 62)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.time = r:CreateFontString(nil, "OVERLAY")
    r.time:SetPoint("RIGHT", 0, 0)
    r.time:SetJustifyH("RIGHT")
    g.rows[i] = r
    return r
end

---------------------------------------------------------------------------
-- Sleek list windows: borderless icons with a hairline progress bar, no background block.
-- Vertical = one row per cooldown (icon, text, timer, line); horizontal = a strip of icons.
---------------------------------------------------------------------------

local function GetSleekRow(g, i)
    local r = g.srows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, g)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.cd = CreateFrame("Cooldown", nil, r, "CooldownFrameTemplate")
    r.cd:SetAllPoints(r.icon)
    r.cd:SetHideCountdownNumbers(true)
    r.cd:SetDrawEdge(false)
    r.fill = CreateFrame("StatusBar", nil, r)
    r.fill:SetMinMaxValues(0, 1)
    r.fill:SetFrameLevel(r:GetFrameLevel())
    r.line = CreateFrame("StatusBar", nil, r)
    r.line:SetMinMaxValues(0, 1)
    r.lineBg = r.line:CreateTexture(nil, "BACKGROUND")
    r.lineBg:SetAllPoints()
    r.label = r:CreateFontString(nil, "OVERLAY")
    r.time = r:CreateFontString(nil, "OVERLAY")
    r.over = CreateFrame("Frame", nil, r) -- keeps the text above the swipe
    r.over:SetAllPoints(r.icon)
    r.over:SetFrameLevel(r.cd:GetFrameLevel() + 3)
    r.itime = r.over:CreateFontString(nil, "OVERLAY")
    g.srows[i] = r
    return r
end

local function LayoutSleek(g, list)
    local db = ns.db
    local edit = ns.editMode
    EditLook(g, edit)
    local horizontal = db.winOrient == "HORIZONTAL"
    local size, gap = db.winIconSize, db.winGap
    local showTitle = db.titles or edit
    local hh = showTitle and 14 or 0
    local suffix = edit and "  |cff66ccffdrag to move|r" or (ns:SyncBlocked() and "  |cffffaa33estimating|r" or "")
    local title = TITLES[g.key]
    if edit and db.attach ~= "WINDOW" and g.key == "ALL" then title = "Fallback window" end
    ns.ApplyFont(g.title, 10)
    ns.ApplyFont(g.empty, 10)
    g.title:ClearAllPoints()
    g.title:SetPoint("TOPLEFT", 2, -1)
    g.title:SetShown(showTitle)
    g.title:SetText("|cff9aa0b4" .. title .. "|r" .. suffix)

    local rr, rg, rb = ns.ReadyRGB()
    local texture = ns.ResolveTexture()
    local lineH = max(1, db.winBarH)
    local barMode = db.winBar
    local width = horizontal and 0 or db.winBarW
    local perRow = max(1, db.winPerRow)
    local shown = 0
    for i, e in ipairs(list) do
        if e.rem > 0 or e.unknown or db.winShowReady or edit then
            shown = shown + 1
            local r = GetSleekRow(g, shown)
            local onCD = e.rem > 0
            r:ClearAllPoints()
            r.icon:ClearAllPoints()
            r.label:ClearAllPoints()
            r.time:ClearAllPoints()
            r.line:ClearAllPoints()
            r.fill:ClearAllPoints()
            local cellH = horizontal and (size + (barMode == "LINE" and lineH + 2 or 0)) or size
            local cellW = horizontal and size or width
            r:SetSize(cellW, cellH)
            if horizontal then
                local col, row = (shown - 1) % perRow, floor((shown - 1) / perRow)
                r:SetPoint("TOPLEFT", g, "TOPLEFT", col * (size + gap), -(hh + row * (cellH + gap)))
            else
                r:SetPoint("TOPLEFT", g, "TOPLEFT", 0, -(hh + (shown - 1) * (size + gap)))
            end
            local iconRight = (not horizontal) and db.winIconSide == "RIGHT"
            r.icon:SetSize(size, size)
            r.icon:SetPoint(iconRight and "TOPRIGHT" or "TOPLEFT", r, iconRight and "TOPRIGHT" or "TOPLEFT", 0, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local _, tex = ns.SpellInfo(e.id)
            r.icon:SetTexture(tex)
            r.icon:SetDesaturated((onCD and db.desaturate) or e.unknown or false)
            r.icon:SetAlpha(ns.StateAlpha(e))
            if db.showSwipe and onCD then
                if r.cdStart ~= e.start then r.cd:SetCooldown(e.start, e.dur); r.cdStart = e.start end
                r.cd:Show()
            else
                if r.cdStart then r.cd:Clear(); r.cdStart = nil end
                r.cd:Hide()
            end
            local cr, cg, cb = ClassRGB(e.class)
            -- progress: how far through the cooldown (1 = ready)
            local frac = 1
            if onCD and e.dur and e.dur > 0 then frac = 1 - min(1, e.rem / e.dur) end
            local tr, tg, tb = ns.TimerRGB(e)
            if horizontal then
                -- icon with the timer over it, hairline underneath
                r.label:Hide(); r.time:Hide(); r.fill:Hide()
                ns.ApplyFont(r.itime, db.timerSize)
                r.itime:ClearAllPoints()
                r.itime:SetPoint("CENTER", r.icon, "CENTER", 0, 0)
                if onCD and db.showTimer then
                    r.itime:SetText(FmtTime(e.rem)); r.itime:SetTextColor(tr, tg, tb); r.itime:Show()
                elseif e.unknown then
                    r.itime:SetText("?"); r.itime:SetTextColor(0.85, 0.85, 0.9); r.itime:Show()
                else
                    r.itime:SetText(""); r.itime:Hide()
                end
                if barMode == "LINE" then
                    r.line:SetPoint("TOPLEFT", r.icon, "BOTTOMLEFT", 0, -2)
                    r.line:SetPoint("TOPRIGHT", r.icon, "BOTTOMRIGHT", 0, -2)
                end
            else
                r.itime:Hide()
                ns.ApplyFont(r.label, db.winTextSize)
                ns.ApplyFont(r.time, db.winTextSize)
                local textLeft = iconRight and 0 or (size + 6)
                local textRight = iconRight and (size + 6) or 0
                r.time:SetPoint("TOPRIGHT", r, "TOPRIGHT", -textRight, -(barMode == "FILL" and (size - db.winTextSize) / 2 or 1))
                r.time:SetJustifyH("RIGHT")
                r.time:Show()
                r.label:SetPoint("TOPLEFT", r, "TOPLEFT", textLeft, -(barMode == "FILL" and (size - db.winTextSize) / 2 or 1))
                r.label:SetPoint("RIGHT", r.time, "LEFT", -6, 0)
                r.label:SetJustifyH("LEFT")
                r.label:SetWordWrap(false)
                r.label:Show()
                local hex = format("ff%02x%02x%02x", floor(cr * 255 + 0.5), floor(cg * 255 + 0.5), floor(cb * 255 + 0.5))
                local spellName = ns.SpellInfo(e.id)
                if db.listNames and db.listSpells then
                    r.label:SetText("|c" .. hex .. e.name .. "|r |cff9aa0b4" .. spellName .. "|r")
                elseif db.listNames then
                    r.label:SetText("|c" .. hex .. e.name .. "|r")
                else
                    r.label:SetText("|cffdddddd" .. spellName .. "|r")
                end
                if onCD then
                    r.time:SetText(FmtTime(e.rem)); r.time:SetTextColor(tr, tg, tb)
                elseif e.unknown then
                    r.time:SetText("?"); r.time:SetTextColor(0.7, 0.7, 0.75)
                else
                    r.time:SetText("READY"); r.time:SetTextColor(rr, rg, rb)
                end
                if barMode == "LINE" then
                    r.line:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", textLeft, 0)
                    r.line:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -textRight, 0)
                elseif barMode == "FILL" then
                    r.fill:SetPoint("TOPLEFT", r, "TOPLEFT", textLeft, 0)
                    r.fill:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -textRight, 0)
                end
            end
            -- hairline progress
            if barMode == "LINE" then
                r.line:SetHeight(lineH)
                r.line:SetStatusBarTexture(texture)
                r.lineBg:SetColorTexture(1, 1, 1, 0.08)
                r.line:SetValue(frac)
                if e.unknown then r.line:SetStatusBarColor(0.5, 0.5, 0.55, 0.8)
                elseif onCD then r.line:SetStatusBarColor(cr, cg, cb, 0.95)
                else r.line:SetStatusBarColor(rr, rg, rb, 0.9) end
                r.line:Show()
            else
                r.line:Hide()
            end
            if barMode == "FILL" and not horizontal then
                r.fill:SetStatusBarTexture(texture)
                r.fill:SetValue(frac)
                local fa = db.winFill
                if e.unknown then r.fill:SetStatusBarColor(0.5, 0.5, 0.55, fa)
                elseif onCD then r.fill:SetStatusBarColor(cr, cg, cb, fa)
                else r.fill:SetStatusBarColor(rr, rg, rb, fa * 0.7) end
                r.fill:Show()
            else
                r.fill:Hide()
            end
            r:Show()
        end
    end
    local rows = g.srows
    for i = shown + 1, #rows do rows[i]:Hide(); rows[i].cdStart = nil end
    -- classic rows are not used in this style
    for _, r in ipairs(g.rows) do r:Hide() end

    g.empty:ClearAllPoints()
    g.empty:SetPoint("TOPLEFT", 2, -(hh + 2))
    g.empty:SetText(db.attach ~= "WINDOW" and edit and g.key == "ALL"
        and "Members without a party frame appear here" or "|cff7c8296no cooldowns yet|r")
    g.empty:SetShown(shown == 0)
    local w, h
    if horizontal then
        local cols = min(perRow, max(shown, 1))
        local rowsN = max(1, math.ceil(max(shown, 1) / perRow))
        local cellH = size + (barMode == "LINE" and lineH + 2 or 0)
        w = max(cols * size + (cols - 1) * gap, 90)
        h = hh + rowsN * cellH + (rowsN - 1) * gap
    else
        w = max(width, 90)
        h = hh + max(shown, 1) * size + (max(shown, 1) - 1) * gap
    end
    if shown == 0 then h = hh + 14 end
    g:SetSize(w, max(h, 14))
    g:SetScale(db.scale)
    g:SetAlpha(db.alpha)
    NormalizeGroup(g)
end

local function LayoutGroup(g, list)
    local db = ns.db
    if db.winStyle ~= "CLASSIC" then return LayoutSleek(g, list) end
    for _, r in ipairs(g.srows) do r:Hide() end
    g.title:ClearAllPoints()
    g.title:SetPoint("TOPLEFT", 8, -6)
    local edit = ns.editMode
    EditLook(g, edit)

    local showTitle = db.titles or edit
    local hh = showTitle and HEADER_H or 4
    local suffix = ""
    if edit then
        suffix = "  |cff66ccffdrag to move|r"
    elseif ns:SyncBlocked() then
        suffix = "  |cffffaa33estimating|r" -- party timers are base cooldowns while sync is blocked
    end
    local title = TITLES[g.key]
    if edit and db.attach ~= "WINDOW" and g.key == "ALL" then title = "Fallback window" end
    ns.ApplyFont(g.title, 12)
    ns.ApplyFont(g.empty, 11)
    g.title:SetShown(showTitle)
    g.title:SetText(title .. suffix)

    local rr, rg, rb = ns.ReadyRGB()
    for i, e in ipairs(list) do
        local r = GetRow(g, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", g, "TOPLEFT", 6, -(hh + (i - 1) * ROW_H))
        ns.ApplyFont(r.label, db.nameSize)
        ns.ApplyFont(r.time, db.timerSize)
        local spellName, icon = ns.SpellInfo(e.id)
        r.icon:SetTexture(icon)
        local cr, cg, cb = ClassRGB(e.class)
        local hex = format("ff%02x%02x%02x", floor(cr * 255 + 0.5), floor(cg * 255 + 0.5), floor(cb * 255 + 0.5))
        local text
        if db.listNames and db.listSpells then
            text = "|c" .. hex .. e.name .. "|r  |cffaaaaaa" .. spellName .. "|r"
        elseif db.listNames then
            text = "|c" .. hex .. e.name .. "|r"
        else
            text = "|cffdddddd" .. spellName .. "|r"
        end
        r.label:SetText(text)
        if e.rem > 0 then
            r.icon:SetDesaturated(true)
            r.icon:SetAlpha(1)
            r.time:SetText(FmtTime(e.rem))
            r.time:SetTextColor(1, 0.3, 0.3)
            if r.cdStart ~= e.start then
                r.cd:SetCooldown(e.start, e.dur)
                r.cdStart = e.start
            end
        else
            if r.cdStart then
                r.cd:Clear()
                r.cdStart = nil
            end
            if e.unknown then
                r.icon:SetDesaturated(true)
                r.icon:SetAlpha(0.55)
                r.time:SetText("?")
                r.time:SetTextColor(0.7, 0.7, 0.75)
            else
                r.icon:SetDesaturated(false)
                r.icon:SetAlpha(1)
                r.time:SetText("READY")
                r.time:SetTextColor(rr, rg, rb)
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
    if db.attach ~= "WINDOW" and edit and g.key == "ALL" then
        g.empty:SetText("Members without a party frame appear here")
    else
        g.empty:SetText("No cooldowns yet")
    end
    g.empty:SetShown(#list == 0)
    g:SetHeight(hh + max(#list, 1) * ROW_H + 6)
    g:SetScale(db.scale)
    g:SetAlpha(db.alpha)
    NormalizeGroup(g)
end

---------------------------------------------------------------------------
-- Attached mode: icon / bar / icon+bar strips
---------------------------------------------------------------------------

local function NewIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.tex)
    b.cd:SetHideCountdownNumbers(true)
    b.cd:SetDrawEdge(false)
    b.border = CreateFrame("Frame", nil, b, "BackdropTemplate")
    b.border:SetPoint("TOPLEFT", 0, 0)
    b.border:SetFrameLevel(b.cd:GetFrameLevel() + 1)
    b.textHolder = CreateFrame("Frame", nil, b)
    b.textHolder:SetAllPoints(b.border)
    b.textHolder:SetFrameLevel(b.cd:GetFrameLevel() + 3)
    b.time = b.textHolder:CreateFontString(nil, "OVERLAY")
    -- slim recharge bar under the icon ("both" style)
    b.bar = CreateFrame("StatusBar", nil, b)
    b.bar:SetMinMaxValues(0, 1)
    b.bar.bg = b.bar:CreateTexture(nil, "BACKGROUND")
    b.bar.bg:SetAllPoints()
    return b
end

local function UpdateIcon(b, e, both)
    local db = ns.db
    local size = db.iconSize
    local barH = both and db.iconBarHeight or 0
    local cellH = size + (both and (barH + 1) or 0)
    b:SetSize(size, cellH)

    local sig = size .. "|" .. cellH .. "|" .. tostring(db.border) .. tostring(db.zoom) .. db.borderSize
        .. db.timerPos .. db.barTexture
    if b.sig ~= sig then
        b.sig = sig
        local inset = db.border and db.borderSize or 0
        b.border:SetSize(size, size)
        b.border:SetBackdrop({ edgeFile = FLAT, edgeSize = max(1, db.borderSize) })
        b.tex:ClearAllPoints()
        b.tex:SetPoint("TOPLEFT", inset, -inset)
        b.tex:SetSize(size - 2 * inset, size - 2 * inset)
        if db.zoom then b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.tex:SetTexCoord(0, 1, 0, 1) end
        b.time:ClearAllPoints()
        b.time:SetPoint(db.timerPos, b.border, db.timerPos, 0, db.timerPos == "CENTER" and 0 or (db.timerPos == "TOP" and -1 or 1))
        b.bar:ClearAllPoints()
        b.bar:SetPoint("BOTTOMLEFT", 0, 0)
        b.bar:SetPoint("BOTTOMRIGHT", 0, 0)
        b.bar:SetStatusBarTexture(ns.ResolveTexture())
        b.bar.bg:SetColorTexture(0.05, 0.05, 0.08, 0.9)
    end
    ns.ApplyFont(b.time, db.timerSize)
    b.bar:SetHeight(max(1, barH))
    b.bar:SetShown(both)

    local _, icon = ns.SpellInfo(e.id)
    b.tex:SetTexture(icon)

    local onCD = e.rem > 0
    b.tex:SetDesaturated((onCD and db.desaturate) or e.unknown)
    b.tex:SetAlpha(ns.StateAlpha(e))
    if db.showSwipe and onCD then
        if b.cdStart ~= e.start then
            b.cd:SetCooldown(e.start, e.dur)
            b.cdStart = e.start
        end
        b.cd:Show()
    else
        if b.cdStart then
            b.cd:Clear()
            b.cdStart = nil
        end
        b.cd:Hide()
    end

    if onCD and db.showTimer then
        b.time:SetText(FmtTime(e.rem))
        b.time:SetTextColor(ns.TimerRGB(e))
        b.time:Show()
    elseif e.unknown then
        b.time:SetText("?")
        b.time:SetTextColor(0.85, 0.85, 0.9)
        b.time:Show()
    else
        b.time:SetText("")
        b.time:Hide()
    end

    local cr, cg, cb = ClassRGB(e.class)
    if both then
        if onCD and e.dur and e.dur > 0 then
            b.bar:SetValue(1 - min(1, e.rem / e.dur))
            b.bar:SetStatusBarColor(cr, cg, cb, 0.8)
        else
            local rr, rg, rb = ns.ReadyRGB()
            b.bar:SetValue(1)
            b.bar:SetStatusBarColor(e.unknown and 0.5 or rr, e.unknown and 0.5 or rg, e.unknown and 0.55 or rb, 1)
        end
    end

    if db.border then
        local r, g, bl
        if e.unknown then
            r, g, bl = 0.35, 0.35, 0.4
        elseif not onCD and db.readyBorder then
            r, g, bl = ns.ReadyRGB()
        elseif db.catBorder then
            local c = ns.CAT_COLORS[e.cat] or { 0.8, 0.8, 0.8 }
            r, g, bl = c[1], c[2], c[3]
        elseif db.classBorder then
            r, g, bl = cr, cg, cb
        else
            r, g, bl = 0, 0, 0
        end
        b.border:SetBackdropBorderColor(r, g, bl, db.borderAlpha)
    else
        b.border:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

-- Lay out the parts of a bar: the icon on the left, right or hidden, the timer on either side.
-- Used by the party cooldown bars and the CC tracker bars.
function ns.LayoutBar(b, h, nameFs)
    local db = ns.db
    local side, tside = db.iconSide, db.timerSide
    b.icon:ClearAllPoints()
    if side == "NONE" then
        b.icon:Hide()
    else
        b.icon:Show()
        b.icon:SetSize(h - 2, h - 2)
        if side == "RIGHT" then b.icon:SetPoint("TOPRIGHT", -1, -1) else b.icon:SetPoint("TOPLEFT", 1, -1) end
    end
    b.status:ClearAllPoints()
    if side == "RIGHT" then
        b.status:SetPoint("TOPLEFT", 1, -1)
        b.status:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMLEFT", -1, 0)
    elseif side == "NONE" then
        b.status:SetPoint("TOPLEFT", 1, -1)
        b.status:SetPoint("BOTTOMRIGHT", -1, 1)
    else
        b.status:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 1, 0)
        b.status:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    b.time:ClearAllPoints()
    nameFs:ClearAllPoints()
    if tside == "LEFT" then
        b.time:SetPoint("LEFT", 4, 0)
        b.time:SetJustifyH("LEFT")
        nameFs:SetPoint("LEFT", b.time, "RIGHT", 4, 0)
        nameFs:SetPoint("RIGHT", -4, 0)
    else
        b.time:SetPoint("RIGHT", -4, 0)
        b.time:SetJustifyH("RIGHT")
        nameFs:SetPoint("LEFT", 4, 0)
        nameFs:SetPoint("RIGHT", b.time, "LEFT", -4, 0)
    end
end

local function NewBar(parent)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.status = CreateFrame("StatusBar", nil, b)
    b.status:SetMinMaxValues(0, 1)
    b.name = b.status:CreateFontString(nil, "OVERLAY")
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.time = b.status:CreateFontString(nil, "OVERLAY")
    b.time:SetJustifyH("RIGHT")
    return b
end

local function UpdateBar(b, e)
    local db = ns.db
    local w, h = db.barWidth, db.barHeight
    b:SetSize(w, h)
    b:SetBackdropColor(0.05, 0.05, 0.08, db.bgAlpha)
    b:SetBackdropBorderColor(0, 0, 0, db.borderAlpha)
    local sig = w .. "|" .. h .. "|" .. db.barTexture .. "|" .. db.iconSide .. "|" .. db.timerSide
    if b.sig ~= sig then
        b.sig = sig
        ns.LayoutBar(b, h, b.name)
        b.status:SetStatusBarTexture(ns.ResolveTexture())
    end
    local fs = max(8, min(db.timerSize, h - 4))
    ns.ApplyFont(b.name, fs)
    ns.ApplyFont(b.time, fs)
    local spellName, icon = ns.SpellInfo(e.id)
    b.icon:SetTexture(icon)
    b.name:SetText(db.barSpellName and spellName or "")

    local r, g, bl
    if db.barColor == "CATEGORY" then
        local c = ns.CAT_COLORS[e.cat] or { 0.8, 0.8, 0.8 }
        r, g, bl = c[1], c[2], c[3]
    else
        r, g, bl = ClassRGB(e.class)
    end
    if e.rem > 0 and e.dur and e.dur > 0 then
        b.status:SetValue(1 - min(1, e.rem / e.dur)) -- fills up as the cooldown recharges
        b.status:SetStatusBarColor(r, g, bl, 0.6)
        b.time:SetText(FmtTime(e.rem))
        b.time:SetTextColor(ns.TimerRGB(e))
        b.icon:SetDesaturated(db.desaturate)
        b.icon:SetAlpha(ns.StateAlpha(e))
    elseif e.unknown then
        b.status:SetValue(1)
        b.status:SetStatusBarColor(0.45, 0.45, 0.5, 0.45)
        b.time:SetText("?")
        b.time:SetTextColor(0.8, 0.8, 0.85)
        b.icon:SetDesaturated(true)
        b.icon:SetAlpha(ns.StateAlpha(e))
    else
        local rr, rg, rb = ns.ReadyRGB()
        b.status:SetValue(1)
        b.status:SetStatusBarColor(r, g, bl, 1)
        b.time:SetText("READY")
        b.time:SetTextColor(rr, rg, rb)
        b.icon:SetDesaturated(false)
        b.icon:SetAlpha(ns.StateAlpha(e))
    end
end

local function GetStrip(name)
    local s = strips[name]
    if s then return s end
    s = CreateFrame("Frame", nil, UIParent)
    s:SetFrameStrata("MEDIUM")
    s:SetSize(10, 10)
    s.icons, s.bars, s.subs = {}, {}, {}
    s:Hide()
    strips[name] = s
    return s
end

local function LayoutList(s, list, isSub)
    local db = ns.db
    local n = #list
    local w, h
    if db.style == "BARS" then
        local bw, bh, sp = db.barWidth, db.barHeight, db.spacing
        local up = db.growth == "UP"
        for i, e in ipairs(list) do
            local b = s.bars[i]
            if not b then
                b = NewBar(s)
                s.bars[i] = b
            end
            UpdateBar(b, e)
            b:ClearAllPoints()
            if up then
                b:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, (i - 1) * (bh + sp))
            else
                b:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -(i - 1) * (bh + sp))
            end
            b:Show()
        end
        w, h = bw, n * bh + (n - 1) * sp
    else
        local both = db.style == "BOTH"
        local size, sp = db.iconSize, db.spacing
        local cellH = size + (both and (db.iconBarHeight + 1) or 0)
        local per = max(1, db.perRow)
        local horizontal = (db.growth == "RIGHT" or db.growth == "LEFT")
        local cols, rows
        if horizontal then
            cols, rows = min(n, per), ceil(n / per)
        else
            rows, cols = min(n, per), ceil(n / per)
        end
        local hRight, vUp
        if horizontal then
            hRight, vUp = (db.growth == "LEFT"), (db.side == "TOP")
        else
            hRight, vUp = (db.side == "LEFT"), (db.growth == "UP")
        end
        local corner = (vUp and "BOTTOM" or "TOP") .. (hRight and "RIGHT" or "LEFT")
        local sx, sy = hRight and -1 or 1, vUp and 1 or -1
        for i, e in ipairs(list) do
            local b = s.icons[i]
            if not b then
                b = NewIcon(s)
                s.icons[i] = b
            end
            UpdateIcon(b, e, both)
            local idx = i - 1
            local col, row
            if horizontal then
                col, row = idx % per, floor(idx / per)
            else
                row, col = idx % per, floor(idx / per)
            end
            b:ClearAllPoints()
            b:SetPoint(corner, s, corner, sx * col * (size + sp), sy * row * (cellH + sp))
            b:Show()
        end
        w, h = cols * size + (cols - 1) * sp, rows * cellH + (rows - 1) * sp
    end
    -- hide whatever is not in use (including the other style's pool)
    local usedIcons = (db.style == "BARS") and 0 or n
    local usedBars = (db.style == "BARS") and n or 0
    for i = usedIcons + 1, #s.icons do s.icons[i]:Hide() end
    for i = usedBars + 1, #s.bars do s.bars[i]:Hide() end
    s:SetSize(max(1, w), max(1, h))
    if not isSub then
        s:SetScale(db.scale)
        s:SetAlpha(db.alpha)
    end
    return max(1, w), max(1, h)
end

local function HidePool(s)
    for _, b in ipairs(s.icons) do b:Hide() end
    for _, b in ipairs(s.bars) do b:Hide() end
end

local function GetSub(s, which)
    local f = s.subs[which]
    if not f then
        f = CreateFrame("Frame", nil, s)
        f:SetSize(10, 10)
        f.icons, f.bars = {}, {}
        s.subs[which] = f
    end
    return f
end

-- Which stacked row a spell category goes in: defensives and externals on top, offensives (and
-- lust / battle res) at the bottom, kicks / CC / utility wherever "stackKicks" says.
local function StackRow(cat)
    if cat == "DEF" or cat == "EXT" then return "top" end
    if cat == "OFF" or cat == "BL" or cat == "BREZ" then return "bottom" end
    return (ns.db.stackKicks == "TOP") and "top" or "bottom"
end

-- One strip per player. Normally a single row/column of cooldowns; with "stack rows" on, two
-- rows attached together (defensives on top, offensives below), each with all the same settings.
local function LayoutStrip(s, list)
    local db = ns.db
    if not db.stackRows then
        for _, f in pairs(s.subs) do HidePool(f); f:Hide() end
        return LayoutList(s, list)
    end
    HidePool(s)
    local top, bottom = {}, {}
    for _, e in ipairs(list) do
        local row = StackRow(e.cat)
        local t = (row == "top") and top or bottom
        if #t < db.maxShown then t[#t + 1] = e end
    end
    local gap = db.stackGap or 3
    -- rows line up on the edge of the strip that is away from the player frame
    local right = (db.side == "LEFT")
    local corner = right and "TOPRIGHT" or "TOPLEFT"
    local y, wmax = 0, 1
    for _, which in ipairs({ "top", "bottom" }) do
        local rowList = (which == "top") and top or bottom
        local f = GetSub(s, which)
        if #rowList > 0 then
            local w, h = LayoutList(f, rowList, true)
            f:ClearAllPoints()
            f:SetPoint(corner, s, corner, 0, -y)
            f:Show()
            y = y + h + gap
            if w > wmax then wmax = w end
        else
            HidePool(f)
            f:Hide()
        end
    end
    s:SetSize(wmax, max(1, y - gap))
    s:SetScale(db.scale)
    s:SetAlpha(db.alpha)
end

-- Where a strip hangs on its frame. For each side and alignment: the strip's own anchor point,
-- the frame's anchor point, and which way "away from the frame" points (the layout KiraUI uses
-- for its party rows). START is the top (left/right sides) or left (above/below) edge.
local PLACE = {
    LEFT   = { CENTER = { "RIGHT", "LEFT" }, START = { "TOPRIGHT", "TOPLEFT" }, END = { "BOTTOMRIGHT", "BOTTOMLEFT" }, ax = -1, ay = 0 },
    RIGHT  = { CENTER = { "LEFT", "RIGHT" }, START = { "TOPLEFT", "TOPRIGHT" }, END = { "BOTTOMLEFT", "BOTTOMRIGHT" }, ax = 1, ay = 0 },
    TOP    = { CENTER = { "BOTTOM", "TOP" }, START = { "BOTTOMLEFT", "TOPLEFT" }, END = { "BOTTOMRIGHT", "TOPRIGHT" }, ax = 0, ay = 1 },
    BOTTOM = { CENTER = { "TOP", "BOTTOM" }, START = { "TOPLEFT", "BOTTOMLEFT" }, END = { "TOPRIGHT", "BOTTOMRIGHT" }, ax = 0, ay = -1 },
}
ns.PLACE = PLACE

-- "Distance from frame" (offsetX) pushes away from the frame, "Shift along frame" (offsetY) slides
-- the row along its edge (up on the sides, right above and below).
local function PlaceStrip(s, anchor)
    local db = ns.db
    local side = PLACE[db.side] and db.side or "RIGHT"
    local align = db.align or "CENTER"
    local p = PLACE[side]
    local pair = p[align] or p.CENTER
    local away, along = db.offsetX or 0, db.offsetY or 0
    local x = p.ax * away + (p.ax == 0 and along or 0)
    local y = p.ay * away + (p.ay == 0 and along or 0)
    local sig = side .. "|" .. align .. "|" .. x .. "|" .. y
    if s.anchorFrame == anchor and s.placeSig == sig then return end
    s.anchorFrame, s.placeSig = anchor, sig
    s:ClearAllPoints()
    s:SetPoint(pair[1], anchor, pair[2], x, y)
end

---------------------------------------------------------------------------
-- Preview nameplates (so side / offset / rows can be seen without a real party)
---------------------------------------------------------------------------

local function GetHolder()
    if holder then return holder end
    holder = NewBackdropFrame("SaltyMPlusHelperPreviewHolder")
    holder:SetSize(190, #ns.PREVIEW * PLATE_STEP + 30)
    MakeMovable(holder, "PREVIEW")
    holder.title = holder:CreateFontString(nil, "OVERLAY")
    holder.title:SetPoint("TOPLEFT", 8, -6)
    holder:SetScale(ns.db.scale)
    ApplyPos(holder)
    holder:Hide()
    return holder
end

function ns:GetPreviewPlate(m)
    local h = GetHolder()
    local i = m.previewIndex or 1
    local p = plates[i]
    if not p then
        p = CreateFrame("Frame", nil, h)
        p:SetSize(130, 14)
        p:SetPoint("TOPLEFT", h, "TOPLEFT", 16, -(28 + (i - 1) * PLATE_STEP))
        p.bg = p:CreateTexture(nil, "BACKGROUND")
        p.bg:SetAllPoints()
        p.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
        p.fill = p:CreateTexture(nil, "ARTWORK")
        p.fill:SetPoint("TOPLEFT", 1, -1)
        p.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        p.name = p:CreateFontString(nil, "OVERLAY")
        p.name:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
        p.name:SetPoint("BOTTOM", p, "TOP", 0, 2)
        plates[i] = p
    end
    local r, g, b = ClassRGB(m.class)
    p.fill:SetColorTexture(r, g, b, 0.85)
    p.name:SetText(m.name)
    p:Show()
    return p
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function StripSort(a, b)
    if ns.db.stripSort == "TIME" then
        if (a.rem > 0) ~= (b.rem > 0) then return a.rem > 0 end
        if a.rem ~= b.rem then return a.rem < b.rem end
    end
    local oa, ob = ns.CatRank(a.cat), ns.CatRank(b.cat)
    if oa ~= ob then return oa < ob end
    return a.id < b.id
end

local function WindowSort(a, b)
    local mode = ns.db.windowSort
    if mode == "PLAYER" and a.name ~= b.name then return a.name < b.name end
    if mode == "TIME" then
        if (a.rem > 0) ~= (b.rem > 0) then return a.rem > 0 end
        if a.rem ~= b.rem then return a.rem < b.rem end
    end
    local oa, ob = ns.CatRank(a.cat), ns.CatRank(b.cat)
    if oa ~= ob then return oa < ob end
    if (a.rem > 0) ~= (b.rem > 0) then return a.rem == 0 end
    if a.rem ~= b.rem then return a.rem < b.rem end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
end

local function Collect(now)
    local db = ns.db
    local out = {}
    for name, m in pairs(members) do
        local skip
        if ns.preview then
            skip = not m.test
        else
            skip = m.test or (m.isSelf and not db.showSelf)
        end
        if not skip then
            local list
            for id, s in pairs(m.spells) do
                -- Preview cooldowns restart a few seconds after they finish.
                if m.test and s.loop and s.start and now > s.start + s.dur + 4 then
                    s.start = now
                end
                local def = SPELLS[id]
                if s.known and def and db.categories[def.cat] and not db.disabled[id] then
                    local rem = 0
                    if s.start and s.dur then rem = max(0, s.start + s.dur - now) end
                    -- A guessed cooldown (no addon on their side, never seen cast) has unknown state.
                    local unknown = rem == 0 and not m.isSelf and not m.hasAddon and not s.seen
                    if rem > 0 or (db.showReady and (db.showUnknown or not unknown)) then
                        list = list or {}
                        list[#list + 1] = {
                            name = name, class = m.class, id = id, rem = rem,
                            start = s.start, dur = s.dur, cat = def.cat, unknown = unknown,
                        }
                    end
                end
            end
            if list then out[#out + 1] = { m = m, list = list } end
        end
    end
    table.sort(out, function(a, b) return a.m.name < b.m.name end)
    return out
end

function ns:Refresh()
    local db = ns.db
    if not db then return end
    local now = GetTime()
    ns.UpdateGrid()
    local forced = ns.editMode or ns:EUIUnlockActive()
    local show = forced or ns:ShouldShow()
    if ns.SyncOnly() then forced, show = false, false end

    local records = Collect(now)
    local windowList = {}
    local usedStrips = {}
    local wantPlates = ns.preview and db.attach ~= "WINDOW"

    if show then
        for _, rec in ipairs(records) do
            local m, list = rec.m, rec.list
            -- offensive cooldowns can live in their own window
            if db.offSeparate then
                local keep, off = {}, {}
                for _, e in ipairs(list) do
                    if e.cat == "OFF" then off[#off + 1] = e else keep[#keep + 1] = e end
                end
                table.sort(off, StripSort)
                for i = #off, db.maxShown + 1, -1 do off[i] = nil end
                for _, e in ipairs(off) do windowList[#windowList + 1] = e end
                list = keep
            end
            -- a class has dozens of spells: keep the most important ones per player
            table.sort(list, StripSort)
            -- (with stacked rows the maximum applies to each row instead)
            if not db.stackRows then
                for i = #list, db.maxShown + 1, -1 do list[i] = nil end
            end
            local anchor
            if #list > 0 and db.attach ~= "WINDOW" then
                if m.test then
                    anchor = wantPlates and ns:GetPreviewPlate(m) or nil
                elseif m.unit then
                    anchor = ns:ResolveAnchor(m.unit)
                end
            end
            if anchor then
                local s = GetStrip(m.name)
                LayoutStrip(s, list)
                PlaceStrip(s, anchor)
                s:Show()
                usedStrips[m.name] = true
            else
                for _, e in ipairs(list) do windowList[#windowList + 1] = e end
            end
        end
    end
    for name, s in pairs(strips) do
        if not usedStrips[name] then s:Hide() end
    end

    -- preview nameplates
    if holder or wantPlates then
        local h = GetHolder()
        local showHolder = wantPlates and show
        h:SetShown(showHolder)
        if showHolder then
            EditLook(h, ns.editMode)
            ns.ApplyFont(h.title, 11)
            h.title:SetText(ns.editMode and "Preview party frames  |cff66ccffdrag to move|r" or "")
            h:SetScale(db.scale)
        end
    end

    -- window(s)
    table.sort(windowList, WindowSort)
    local buckets = {}
    for _, e in ipairs(windowList) do
        local key
        if db.split then
            key = e.cat
        elseif db.offSeparate and e.cat == "OFF" then
            key = "OFF"
        else
            key = "ALL"
        end
        local b = buckets[key]
        if not b then
            b = {}
            buckets[key] = b
        end
        b[#b + 1] = e
    end
    local active
    if db.split then
        active = ns.SPLIT_KEYS
    elseif db.offSeparate then
        active = { "ALL", "OFF" }
    else
        active = ns.ALL_KEYS
    end
    local activeSet = {}
    for _, key in ipairs(active) do
        activeSet[key] = true
        local g = GetGroup(key)
        local b = buckets[key] or {}
        if show and (#b > 0 or forced) then
            LayoutGroup(g, b)
            g:Show()
        else
            g:Hide()
        end
    end
    for key, g in pairs(groups) do
        if not activeSet[key] then g:Hide() end
    end

    if ns.CC then ns.CC:Refresh(show, forced) end
end

function ns:ApplyAllPositions()
    for _, g in pairs(groups) do
        g:SetScale(ns.db.scale)
        ApplyPos(g)
    end
    if holder then
        holder:SetScale(ns.db.scale)
        ApplyPos(holder)
    end
    if ns.CC and ns.CC.frame then ApplyPos(ns.CC.frame) end
end

function ns:ResetPositions()
    wipe(ns.db.pos)
    ns:ApplyAllPositions()
end

function ns:SetScaleAll(new)
    local db = ns.db
    new = min(2, max(0.5, floor(new * 20 + 0.5) / 20))
    local old = db.scale
    if new == old then return end
    -- Keep each movable frame visually in place while its scale changes.
    local movable = {}
    if holder then movable[#movable + 1] = holder end
    for _, g in pairs(groups) do movable[#movable + 1] = g end
    for _, g in ipairs(movable) do
        local left, top = g:GetLeft(), g:GetTop()
        if left and top then db.pos[g.key] = { left * old / new, top * old / new } end
    end
    db.scale = new
    for _, g in ipairs(movable) do
        g:SetScale(new)
        ApplyPos(g)
    end
    ns:Refresh()
    ns:Notify()
end
