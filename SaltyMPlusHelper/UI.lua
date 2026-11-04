-- UI.lua: the settings window (/salty). A small flat widget kit plus six tabs:
-- General, Layout, Appearance, Tracking, Sync, Integrations.

local ADDON, ns = ...
local UI = {}
ns.UI = UI

local FLAT = "Interface\\Buttons\\WHITE8x8"
local C = {
    bg     = { 0.055, 0.05, 0.085, 0.97 },
    side   = { 0.075, 0.065, 0.11, 1 },
    panel  = { 0.11, 0.1, 0.16, 1 },
    hover  = { 0.16, 0.14, 0.24, 1 },
    line   = { 0.22, 0.2, 0.32, 1 },
    accent = { 0.72, 0.4, 1.0 },
    text   = { 0.92, 0.92, 0.96 },
    dim    = { 0.62, 0.6, 0.72 },
    good   = { 0.35, 0.9, 0.5 },
    bad    = { 1, 0.45, 0.45 },
}
local WIN_W, WIN_H, SIDE_W, HEAD_H = 760, 680, 168, 56
local PANEL_W = WIN_W - SIDE_W - 56

---------------------------------------------------------------------------
-- Widget kit
---------------------------------------------------------------------------

local function Backdrop(f, bg, border)
    f:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    local b = border or C.line
    f:SetBackdropBorderColor(b[1], b[2], b[3], b[4] or 1)
end

local function Text(parent, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function Button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, height)
    Backdrop(b, C.panel, C.line)
    b.text = Text(b, 12, C.text, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self) if not self.selected then self:SetBackdropColor(unpack(C.hover)) end end)
    b:SetScript("OnLeave", function(self) self:SetSelected(self.selected) end)
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    function b:SetSelected(on)
        self.selected = on and true or false
        if on then
            self:SetBackdropColor(C.accent[1] * 0.55, C.accent[2] * 0.55, C.accent[3] * 0.55, 1)
            self:SetBackdropBorderColor(unpack(C.accent))
        else
            self:SetBackdropColor(unpack(C.panel))
            self:SetBackdropBorderColor(unpack(C.line))
        end
    end
    return b
end

-- Every widget is { frame, height, Refresh(), visible()? }.
local function Header(parent, label)
    local w = { height = 26, gap = 4 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(26)
    local t = Text(f, 11, C.accent)
    t:SetPoint("BOTTOMLEFT", 0, 6)
    t:SetText(string.upper(label))
    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    w.frame = f
    w.Refresh = function() end
    return w
end

local function Info(parent, textFn, height)
    local w = { height = height or 32, gap = 6 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(w.height)
    local t = Text(f, 11, C.dim)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetPoint("TOPRIGHT", 0, 0)
    t:SetWordWrap(true)
    t:SetJustifyV("TOP")
    w.frame = f
    w.live = type(textFn) == "function"
    w.Refresh = function()
        t:SetText(type(textFn) == "function" and textFn() or textFn)
    end
    return w
end

local function Checkbox(parent, label, get, set)
    local w = { height = 24, gap = 4 }
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(24)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    Backdrop(box, C.panel, C.line)
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetPoint("TOPLEFT", 3, -3)
    tick:SetPoint("BOTTOMRIGHT", -3, 3)
    tick:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    local t = Text(f, 12, C.text)
    t:SetPoint("LEFT", box, "RIGHT", 8, 0)
    t:SetText(label)
    f:SetScript("OnClick", function()
        -- redraw the page even if applying the setting hits an error, so the box never lies
        local ok, err = pcall(set, not get())
        UI.Changed()
        if not ok then error(err, 0) end
    end)
    f:SetScript("OnEnter", function() box:SetBackdropBorderColor(unpack(C.accent)) end)
    f:SetScript("OnLeave", function() box:SetBackdropBorderColor(unpack(C.line)) end)
    w.frame = f
    w.Refresh = function() tick:SetShown(get() and true or false) end
    return w
end

-- Dropdown: a button showing the current choice; click it to open a short list.
-- entries = { { value, "text (can hold |T..|t icons)" }, ... }
local ddPopup
local function DropdownPopup()
    if ddPopup then return ddPopup end
    local f = CreateFrame("Frame", "SaltyMPlusHelperDropdown", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    Backdrop(f, C.bg, C.accent)
    f:Hide()
    f.buttons = {}
    ddPopup = f
    return f
end

local function Dropdown(parent, label, entries, get, set)
    local w = { height = 30, gap = 4 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(30)
    local t = Text(f, 12, C.text)
    t:SetPoint("LEFT", 0, 0)
    t:SetText(label)
    local btn = Button(f, "", 200, 24, nil)
    btn:SetPoint("RIGHT", 0, 0)
    btn.text:ClearAllPoints()
    btn.text:SetPoint("LEFT", 8, 0)
    btn.text:SetPoint("RIGHT", -18, 0)
    btn.text:SetJustifyH("LEFT")
    local arrow = Text(btn, 11, C.dim, "RIGHT")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    btn:SetScript("OnClick", function(self)
        local pop = DropdownPopup()
        if pop:IsShown() and pop.owner == self then pop:Hide() return end
        pop.owner = self
        pop:ClearAllPoints()
        pop:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)
        pop:SetSize(200, #entries * 22 + 8)
        local cur = get()
        for i, e in ipairs(entries) do
            local b = pop.buttons[i]
            if not b then
                b = Button(pop, "", 192, 20, nil)
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 8, 0)
                b.text:SetJustifyH("LEFT")
                pop.buttons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", pop, "TOPLEFT", 4, -4 - (i - 1) * 22)
            b.text:SetText(e[2])
            b:SetSelected(e[1] == cur)
            b:SetScript("OnClick", function()
                pop:Hide()
                set(e[1])
                UI.Changed()
            end)
            b:Show()
        end
        for i = #entries + 1, #pop.buttons do pop.buttons[i]:Hide() end
        pop:Show()
    end)
    w.frame = f
    w.Refresh = function()
        local cur = get()
        for _, e in ipairs(entries) do
            if e[1] == cur then btn.text:SetText(e[2]) return end
        end
        btn.text:SetText(tostring(cur))
    end
    return w
end

local function Slider(parent, label, min, max, step, get, set, fmt)
    local w = { height = 40, gap = 4 }
    fmt = fmt or "%d"
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(40)
    local t = Text(f, 12, C.text)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(label)
    local val = Text(f, 12, C.accent, "RIGHT")
    val:SetPoint("TOPRIGHT", 0, 0)
    local s = CreateFrame("Slider", nil, f)
    s:SetOrientation("HORIZONTAL")
    s:SetPoint("TOPLEFT", 0, -22)
    s:SetPoint("TOPRIGHT", 0, -22)
    s:SetHeight(14)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    s:SetThumbTexture(FLAT)
    local thumb = s:GetThumbTexture()
    thumb:SetSize(10, 14)
    thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(C.accent[1] * 0.7, C.accent[2] * 0.7, C.accent[3] * 0.7, 1)
    s:SetScript("OnValueChanged", function(_, v)
        if w.syncing then return end
        v = floor(v / step + 0.5) * step
        val:SetText(format(fmt, v))
        if get() ~= v then
            set(v)
            UI.Changed(w)
        end
    end)
    w.frame = f
    w.slider = s
    w.Refresh = function()
        local v = get()
        w.syncing = true
        s:SetValue(v)
        w.syncing = false
        val:SetText(format(fmt, v))
    end
    return w
end

-- options = { { value, label }, ... }
local function Segmented(parent, label, options, get, set)
    local w = { height = 50, gap = 4 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(50)
    local t = Text(f, 12, C.text)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(label)
    local btns = {}
    for i, o in ipairs(options) do
        local b = Button(f, o[2], 80, 22, function()
            local ok, err = pcall(set, o[1])
            UI.Changed()
            if not ok then error(err, 0) end
        end)
        b.value = o[1]
        btns[i] = b
    end
    local function layout()
        local width = f:GetWidth() or 0
        if width < 20 then width = PANEL_W end
        local gap, n = 4, #btns
        local bw = (width - gap * (n - 1)) / n
        for i, b in ipairs(btns) do
            b:SetWidth(bw)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (bw + gap), -22)
        end
    end
    f:SetScript("OnSizeChanged", layout)
    layout()
    w.frame = f
    w.Refresh = function()
        local cur = get()
        for _, b in ipairs(btns) do b:SetSelected(b.value == cur) end
    end
    return w
end

-- Toggle chips: options = { { key, label }, ... } (wraps onto several lines)
local function Chips(parent, options, get, set)
    local w = { gap = 6 }
    local f = CreateFrame("Frame", nil, parent)
    local btns = {}
    local x, y, lineH = 0, 0, 30
    for _, o in ipairs(options) do
        local b = Button(f, o[2], 96, 24, function()
            set(o[1], not get(o[1]))
            UI.Changed()
        end)
        local bw = max(70, #o[2] * 7 + 24)
        b:SetWidth(bw)
        if x + bw > PANEL_W and x > 0 then
            x = 0
            y = y + lineH
        end
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -(y + 2))
        x = x + bw + 6
        b.key = o[1]
        btns[#btns + 1] = b
    end
    w.height = y + lineH
    f:SetHeight(w.height)
    w.frame = f
    w.Refresh = function()
        for _, b in ipairs(btns) do b:SetSelected(get(b.key)) end
    end
    return w
end

local function ButtonRow(parent, defs)
    local w = { height = 32, gap = 6 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(32)
    local btns = {}
    local x = 0
    for _, d in ipairs(defs) do
        local b = Button(f, d.label, d.width or 140, 26, d.onClick)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -2)
        x = x + (d.width or 140) + 8
        b.def = d
        btns[#btns + 1] = b
    end
    w.frame = f
    w.Refresh = function()
        for _, b in ipairs(btns) do
            if b.def.selected then b:SetSelected(b.def.selected()) end
            if b.def.text then b.text:SetText(b.def.text()) end
        end
    end
    return w
end

local function EditBox(parent, label, get, set)
    local w = { height = 50, gap = 4 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(50)
    local t = Text(f, 12, C.text)
    t:SetPoint("TOPLEFT", 0, 0)
    t:SetText(label)
    local box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, -20)
    box:SetPoint("TOPRIGHT", 0, -20)
    box:SetHeight(26)
    Backdrop(box, C.panel, C.line)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetPoint("TOPLEFT", 8, 0)
    eb:SetPoint("BOTTOMRIGHT", -8, 0)
    eb:SetFont(STANDARD_TEXT_FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3], 1)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEnterPressed", function(self)
        set(self:GetText() or "")
        self:ClearFocus()
        UI.Changed()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        w.Refresh()
    end)
    eb:SetScript("OnEditFocusGained", function() box:SetBackdropBorderColor(unpack(C.accent)) end)
    eb:SetScript("OnEditFocusLost", function() box:SetBackdropBorderColor(unpack(C.line)) end)
    w.frame = f
    w.edit = eb
    w.Refresh = function()
        if not eb:HasFocus() then eb:SetText(get() or "") end
    end
    return w
end

-- A vertical list of "name   status" lines.
local function LineList(parent, count, dataFn)
    local w = { height = count * 22 + 4, gap = 6, tick = true }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(w.height)
    local lines = {}
    for i = 1, count do
        local l = {}
        l.name = Text(f, 12, C.text)
        l.name:SetPoint("TOPLEFT", 0, -(i - 1) * 22 - 2)
        l.status = Text(f, 12, C.dim, "RIGHT")
        l.status:SetPoint("TOPRIGHT", 0, -(i - 1) * 22 - 2)
        lines[i] = l
    end
    w.frame = f
    w.Refresh = function()
        local data = dataFn()
        for i, l in ipairs(lines) do
            local d = data[i]
            if d then
                local c = d.class and RAID_CLASS_COLORS[d.class]
                if c then l.name:SetTextColor(c.r, c.g, c.b, 1) else l.name:SetTextColor(C.text[1], C.text[2], C.text[3], 1) end
                l.name:SetText(d.name)
                local col = d.color or C.dim
                l.status:SetTextColor(col[1], col[2], col[3], 1)
                l.status:SetText(d.text)
                l.name:Show()
                l.status:Show()
            else
                l.name:Hide()
                l.status:Hide()
            end
        end
    end
    return w
end

local function SpellGrid(parent)
    local w = { gap = 8 }
    local f = CreateFrame("Frame", nil, parent)
    local BTN, GAP, COLS = 30, 4, 14
    local y = 0
    local buttons = {}
    for _, cat in ipairs(ns.CATEGORIES) do
        local ids = {}
        for id, def in pairs(ns.SPELLS) do
            if def.cat == cat then ids[#ids + 1] = id end
        end
        table.sort(ids)
        local hdr = Text(f, 11, C.accent)
        hdr:SetPoint("TOPLEFT", 0, -y)
        hdr:SetText(string.upper(ns.CAT_NAMES[cat]))
        y = y + 18
        for i, id in ipairs(ids) do
            local col, row = (i - 1) % COLS, floor((i - 1) / COLS)
            local b = CreateFrame("Button", nil, f, "BackdropTemplate")
            b:SetSize(BTN, BTN)
            b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (BTN + GAP), -(y + row * (BTN + GAP)))
            Backdrop(b, C.panel, C.line)
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 1, -1)
            b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local _, icon = ns.SpellInfo(id)
            b.icon:SetTexture(icon)
            b.id = id
            b:SetScript("OnClick", function()
                ns.db.disabled[id] = (not ns.db.disabled[id]) or nil
                ns:Refresh()
                w.Refresh()
            end)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(id)
                local def = ns.SPELLS[id]
                GameTooltip:AddLine(format("%s  |  %ds cooldown", def.class:sub(1, 1) .. def.class:sub(2):lower(), def.cd), 0.7, 0.7, 0.8)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            buttons[#buttons + 1] = b
        end
        y = y + ceil(#ids / COLS) * (BTN + GAP) + 6
    end
    f:SetHeight(y)
    w.height = y
    w.frame = f
    w.Refresh = function()
        for _, b in ipairs(buttons) do
            local off = ns.db.disabled[b.id]
            b.icon:SetDesaturated(off and true or false)
            b.icon:SetAlpha(off and 0.35 or 1)
            if off then b:SetBackdropBorderColor(unpack(C.line)) else b:SetBackdropBorderColor(unpack(C.accent)) end
        end
    end
    return w
end

---------------------------------------------------------------------------
-- Panels (vertical stacks of widgets inside a scroll frame)
---------------------------------------------------------------------------

local function NewPage(parent)
    local page = CreateFrame("ScrollFrame", nil, parent)
    page:SetAllPoints(parent)
    local child = CreateFrame("Frame", nil, page)
    child:SetSize(PANEL_W, 10)
    page:SetScrollChild(child)
    page.child = child
    page.rows = {}

    local track = page:CreateTexture(nil, "BACKGROUND")
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    track:SetColorTexture(1, 1, 1, 0.05)
    track:Hide()
    local barFrame = CreateFrame("Button", nil, page)
    barFrame:SetWidth(8)
    barFrame:SetFrameLevel(page:GetFrameLevel() + 5)
    barFrame:Hide()
    local bar = barFrame:CreateTexture(nil, "OVERLAY")
    bar:SetAllPoints()
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.7)
    function bar:SetHeight(h) barFrame:SetHeight(h) end
    function bar:Hide() barFrame:Hide(); track:Hide() end
    function bar:Show() barFrame:Show(); track:Show() end
    function bar:ClearAllPoints() barFrame:ClearAllPoints() end
    function bar:SetPoint(...) barFrame:SetPoint(...) end

    local function updateBar()
        local view = page:GetHeight() or 1
        local total = child:GetHeight() or 1
        if total <= view + 1 then
            bar:Hide()
            return
        end
        local cur = page:GetVerticalScroll() or 0
        local h = max(24, view * view / total)
        local travel = view - h
        local range = max(1, total - view)
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -(travel * cur / range))
        bar:SetHeight(h)
        bar:Show()
    end
    barFrame:EnableMouse(true)
    barFrame:RegisterForDrag("LeftButton")
    barFrame:SetScript("OnDragStart", function(self)
        local _, cy = GetCursorPosition()
        self.dragY = cy / (page:GetEffectiveScale() or 1)
        self.dragScroll = page:GetVerticalScroll() or 0
        self:SetScript("OnUpdate", function(f)
            local _, y = GetCursorPosition()
            y = y / (page:GetEffectiveScale() or 1)
            local view = page:GetHeight() or 1
            local total = child:GetHeight() or 1
            local h = max(24, view * view / total)
            local travel = max(1, view - h)
            local maxScroll = max(0, total - view)
            local v = f.dragScroll + (f.dragY - y) * maxScroll / travel
            page:SetVerticalScroll(min(maxScroll, max(0, v)))
            updateBar()
        end)
    end)
    barFrame:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    page:SetScript("OnSizeChanged", function(self, w)
        if w and w > 50 then child:SetWidth(w - 14) end
        if self.Layout then self:Layout() end
    end)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(self, delta)
        local total = child:GetHeight() or 0
        local view = self:GetHeight() or 0
        local maxScroll = max(0, total - view)
        local cur = self:GetVerticalScroll() or 0
        self:SetVerticalScroll(min(maxScroll, max(0, cur - delta * 48)))
        updateBar()
    end)

    function page:Add(w)
        w.frame:SetParent(child)
        self.rows[#self.rows + 1] = w
        return w
    end
    function page:Layout()
        local y = 0
        for _, w in ipairs(self.rows) do
            local vis = (not w.visible) or w.visible()
            w.frame:SetShown(vis)
            if vis then
                w.frame:ClearAllPoints()
                w.frame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
                w.frame:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
                y = y + w.height + (w.gap or 4)
            end
        end
        child:SetHeight(max(y, 10))
        local maxScroll = max(0, y - (page:GetHeight() or 0))
        if (page:GetVerticalScroll() or 0) > maxScroll then page:SetVerticalScroll(maxScroll) end
        updateBar()
    end
    function page:Sync(except)
        for _, w in ipairs(self.rows) do
            local vis = (not w.visible) or w.visible()
            if vis and w ~= except then w.Refresh() end
        end
        self:Layout()
    end
    return page
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

local function Opt(key)
    return function() return ns.db[key] end, function(v) ns.db[key] = v; ns:Refresh() end
end

local function Gate(fn, w) w.visible = fn; return w end
-- greyed out and unclickable while fn() is true (used for options that need another addon)
local function GreyIf(fn, w)
    local refresh = w.Refresh
    w.Refresh = function()
        refresh()
        local off = fn() and true or false
        w.frame:SetAlpha(off and 0.35 or 1)
        w.frame:EnableMouse(not off)
    end
    return w
end
local function NoMDT() return not (ns.MP and ns.MP.MDT and ns.MP.MDT.Available()) end
local function Key(k) return function() return ns.db[k] end end
local function All(...)
    local keys = { ... }
    return function()
        for _, k in ipairs(keys) do if not ns.db[k] then return false end end
        return true
    end
end

local function BuildGeneral(p)
    p:Add(Header(p.child, "Cooldown tracker"))
    local g, s = Opt("enabled")
    p:Add(Checkbox(p.child, "Enable cooldown tracking", g, s))
    g, s = Opt("visibility")
    p:Add(Segmented(p.child, "Show", {
        { "ALWAYS", "Always" }, { "GROUP", "In a group" }, { "DUNGEON", "In dungeons only" },
        { "COMBAT", "In combat only" },
    }, g, s))
    g, s = Opt("showSelf")
    p:Add(Checkbox(p.child, "Include my own cooldowns", g, s))
    g, s = Opt("showReady")
    p:Add(Checkbox(p.child, "Show spells that are ready (not only on cooldown)", g, s))
    p:Add(Header(p.child, "Size and visibility"))
    p:Add(Slider(p.child, "Scale", 0.5, 2, 0.05, function() return ns.db.scale end,
        function(v) ns:SetScaleAll(v) end, "%.2f"))
    g, s = Opt("alpha")
    p:Add(Slider(p.child, "Overall opacity (everything)", 0.2, 1, 0.05, g, s, "%.2f"))
    g, s = Opt("bgAlpha")
    p:Add(Slider(p.child, "Background opacity (windows and bars)", 0, 1, 0.05, g, s, "%.2f"))
    p:Add(Header(p.child, "Layout editing"))
    p:Add(Info(p.child, "Preview shows a test party so you can see changes live. Move mode lets you drag the windows with the left mouse button.", 34))
    p:Add(ButtonRow(p.child, {
        { label = "Preview party", width = 160,
          onClick = function() ns:SetPreview(not ns.preview) end,
          selected = function() return ns.preview end },
        { label = "Move frames", width = 160,
          onClick = function() ns:SetEditMode(not ns.editMode) end,
          selected = function() return ns.editMode end },
        { label = "Reset positions", width = 140,
          onClick = function() ns:ResetPositions() end },
    }))
end

local function BuildLayout(p)
    local function attached() return ns.db.attach ~= "WINDOW" end
    local function icons() return attached() and ns.db.style ~= "BARS" end
    local function bars() return attached() and ns.db.style == "BARS" end
    local function both() return attached() and ns.db.style == "BOTH" end
    local function vis(fn, w) w.visible = fn; return w end

    p:Add(Header(p.child, "Where cooldowns appear"))
    local g, s = Opt("attach")
    p:Add(Segmented(p.child, "Attach to", {
        { "PARTY", "Party frames" }, { "WINDOW", "Window" },
    }, g, function(v)
        ns.db.attach = v
        ns:ClearFrameCache()
        ns:Refresh()
    end))
    p:Add(Info(p.child, function()
        local a = ns.db.attach
        if a == "PARTY" then
            return "Hangs one row per player on their party frame, offensive and defensive cooldowns together. Any unit frame addon is found automatically (Blizzard, EllesmereUI, ElvUI, Cell, Grid2, VuhDo...)."
        end
        return "Shows everything in one movable list. Use Move frames to place it."
    end, 54))

    g, s = Opt("showSelf")
    p:Add(Checkbox(p.child, "Show my own cooldowns (untick to show only the other party members)", g, s))
    g, s = Opt("side")
    p:Add(vis(attached, Segmented(p.child, "Side of the frame", {
        { "LEFT", "Left" }, { "RIGHT", "Right" }, { "TOP", "Above" }, { "BOTTOM", "Below" },
    }, g, s)))
    g, s = Opt("align")
    p:Add(vis(attached, Segmented(p.child, "Line up along the frame", {
        { "CENTER", "Centre" }, { "START", "Top / left edge" }, { "END", "Bottom / right edge" },
    }, g, s)))
    g, s = Opt("offsetX")
    p:Add(vis(attached, Slider(p.child, "Distance from the frame", -50, 100, 1, g, s)))
    g, s = Opt("offsetY")
    p:Add(vis(attached, Slider(p.child, "Shift along the frame", -100, 100, 1, g, s)))

    p:Add(vis(attached, Header(p.child, "Rows and bars")))
    g, s = Opt("style")
    p:Add(vis(attached, Segmented(p.child, "Style", {
        { "ICONS", "Icons" }, { "BARS", "Bars" }, { "BOTH", "Icons + bars" },
    }, g, s)))
    g, s = Opt("stackRows")
    p:Add(vis(attached, Checkbox(p.child, "Two stacked rows: defensives on top, offensives below", g, s)))
    local function stacked() return attached() and ns.db.stackRows end
    g, s = Opt("stackKicks")
    p:Add(vis(stacked, Segmented(p.child, "Kicks, CC and utility go in the", { { "TOP", "Top row" }, { "BOTTOM", "Bottom row" } }, g, s)))
    g, s = Opt("stackGap")
    p:Add(vis(stacked, Slider(p.child, "Gap between the two rows", 0, 20, 1, g, s)))
    g, s = Opt("growth")
    p:Add(vis(attached, Segmented(p.child, "Grow towards", {
        { "RIGHT", "Right" }, { "LEFT", "Left" }, { "UP", "Up" }, { "DOWN", "Down" },
    }, g, s)))
    g, s = Opt("stripOrder")
    p:Add(vis(attached, Segmented(p.child, "Spell order (what survives the maximum)", {
        { "OFFENSIVE", "Offensive first" }, { "DEFENSIVE", "Defensive first" }, { "KICKS", "Kicks first" },
    }, g, s)))
    g, s = Opt("stripSort")
    p:Add(vis(attached, Segmented(p.child, "Order within a row", {
        { "CATEGORY", "By spell type" }, { "TIME", "Running timers first" },
    }, g, s)))
    g, s = Opt("perRow")
    p:Add(vis(icons, Slider(p.child, "Icons per row", 1, 12, 1, g, s)))
    g, s = Opt("maxShown")
    p:Add(vis(attached, Slider(p.child, "Maximum shown per player (per row when stacked)", 1, 16, 1, g, s)))
    g, s = Opt("iconSize")
    p:Add(vis(icons, Slider(p.child, "Icon size", 14, 64, 1, g, s)))
    g, s = Opt("iconBarHeight")
    p:Add(vis(both, Slider(p.child, "Bar thickness under icons", 2, 12, 1, g, s)))
    g, s = Opt("barWidth")
    p:Add(vis(bars, Slider(p.child, "Bar width", 60, 300, 1, g, s)))
    g, s = Opt("barHeight")
    p:Add(vis(bars, Slider(p.child, "Bar height", 10, 36, 1, g, s)))
    g, s = Opt("spacing")
    p:Add(vis(attached, Slider(p.child, "Spacing", 0, 12, 1, g, s)))

    p:Add(Header(p.child, "Window"))
    g, s = Opt("windowSort")
    p:Add(Segmented(p.child, "Sort window by", {
        { "CATEGORY", "Spell type" }, { "TIME", "Time left" }, { "PLAYER", "Player" },
    }, g, s))
    g, s = Opt("split")
    p:Add(Checkbox(p.child, "One window per category", g, function(v)
        ns.db.split = v
        if next(ns.euiRegistered) then ns:RegisterEllesmere() end
        ns:Refresh()
    end))
    g, s = Opt("winStyle")
    p:Add(Segmented(p.child, "Window look", { { "SLEEK", "Sleek (no background)" }, { "CLASSIC", "Classic block" } }, g, s))
    local function sleek() return ns.db.winStyle ~= "CLASSIC" end
    local function sleekV() return sleek() and ns.db.winOrient ~= "HORIZONTAL" end
    local function sleekH() return sleek() and ns.db.winOrient == "HORIZONTAL" end
    g, s = Opt("winOrient")
    p:Add(vis(sleek, Segmented(p.child, "Orientation", { { "VERTICAL", "Rows (top to bottom)" }, { "HORIZONTAL", "Icon strip (left to right)" } }, g, s)))
    g, s = Opt("winBar")
    p:Add(vis(sleek, Segmented(p.child, "Progress", { { "LINE", "Thin line" }, { "FILL", "Soft fill" }, { "NONE", "None" } }, g, s)))
    g, s = Opt("winIconSide")
    p:Add(vis(sleekV, Segmented(p.child, "Icon side", { { "LEFT", "Left" }, { "RIGHT", "Right" } }, g, s)))
    g, s = Opt("winIconSize")
    p:Add(vis(sleek, Slider(p.child, "Icon size", 14, 56, 1, g, s)))
    g, s = Opt("winGap")
    p:Add(vis(sleek, Slider(p.child, "Spacing", 0, 24, 1, g, s)))
    g, s = Opt("winBarW")
    p:Add(vis(sleekV, Slider(p.child, "Row width", 100, 400, 1, g, s)))
    g, s = Opt("winPerRow")
    p:Add(vis(sleekH, Slider(p.child, "Icons per row", 1, 16, 1, g, s)))
    g, s = Opt("winBarH")
    p:Add(vis(sleek, Slider(p.child, "Line thickness", 1, 8, 1, g, s)))
    g, s = Opt("winFill")
    p:Add(vis(sleekV, Slider(p.child, "Fill opacity", 0.05, 1, 0.05, g, s, "%.2f")))
    g, s = Opt("winTextSize")
    p:Add(vis(sleekV, Slider(p.child, "Text size", 8, 18, 1, g, s)))
    g, s = Opt("winBg")
    p:Add(vis(sleek, Slider(p.child, "Background opacity (0 = transparent)", 0, 1, 0.05, g, s, "%.2f")))
    g, s = Opt("winBorder")
    p:Add(vis(sleek, Checkbox(p.child, "Thin border (only with a background)", g, s)))
    g, s = Opt("winShowReady")
    p:Add(vis(sleek, Checkbox(p.child, "Show spells that are ready", g, s)))
    g, s = Opt("titles")
    p:Add(Checkbox(p.child, "Show window titles", g, s))
    g, s = Opt("listNames")
    p:Add(Checkbox(p.child, "Show player names", g, s))
    g, s = Opt("listSpells")
    p:Add(Checkbox(p.child, "Show spell names", g, s))

    p:Add(Header(p.child, "Grid and snapping (Move frames)"))
    g, s = Opt("nudgeOn")
    p:Add(Checkbox(p.child, "Click a frame once to select it, then move it with the arrow keys", g, s))
    g, s = Opt("nudgeShift")
    p:Add(Gate(Key("nudgeOn"), Slider(p.child, "Shift + arrow step (pixels)", 2, 50, 1, g, s)))
    g, s = Opt("snapOn")
    p:Add(Checkbox(p.child, "Snap frames to a grid when you let go", g, s))
    g, s = Opt("snapSize")
    p:Add(Gate(Key("snapOn"), Slider(p.child, "Grid size (pixels)", 4, 64, 2, g, s)))
    g, s = Opt("gridShow")
    p:Add(Gate(Key("snapOn"), Checkbox(p.child, "Show the grid while moving", g, s)))
    g, s = Opt("gridAlpha")
    p:Add(Gate(All("snapOn", "gridShow"), Slider(p.child, "Grid brightness", 0.05, 0.6, 0.05, g, s, "%.2f")))
    g, s = Opt("snapEdges")
    p:Add(Gate(Key("snapOn"), Checkbox(p.child, "Also line up with the edges of other frames", g, s)))
end

local function BuildAppearance(p)
    local function icons() return ns.db.style ~= "BARS" end
    local function bars() return ns.db.style == "BARS" end
    local function vis(fn, w) w.visible = fn; return w end
    local g, s

    p:Add(Header(p.child, "Transparency"))
    g, s = Opt("alpha")
    p:Add(Slider(p.child, "Overall opacity", 0.2, 1, 0.05, g, s, "%.2f"))
    g, s = Opt("bgAlpha")
    p:Add(Slider(p.child, "Background opacity", 0, 1, 0.05, g, s, "%.2f"))
    g, s = Opt("borderAlpha")
    p:Add(Slider(p.child, "Border opacity", 0, 1, 0.05, g, s, "%.2f"))

    p:Add(Header(p.child, "Text"))
    g, s = Opt("fontName")
    p:Add(EditBox(p.child, "Font (Friz Quadrata, Arial Narrow, Skurri, Morpheus, or a SharedMedia name)", g, s))
    g, s = Opt("outline")
    p:Add(Segmented(p.child, "Outline", {
        { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick" },
    }, g, s))
    g, s = Opt("timerSize")
    p:Add(Slider(p.child, "Timer text size", 8, 24, 1, g, s))
    g, s = Opt("nameSize")
    p:Add(Slider(p.child, "Name text size", 8, 20, 1, g, s))
    g, s = Opt("showTimer")
    p:Add(Checkbox(p.child, "Show remaining time on icons", g, s))
    g, s = Opt("decimals")
    p:Add(Checkbox(p.child, "Show tenths of a second under 10 seconds", g, s))
    g, s = Opt("timerPos")
    p:Add(vis(icons, Segmented(p.child, "Timer position on icons", {
        { "CENTER", "Centre" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" },
    }, g, s)))
    g, s = Opt("timerColor")
    p:Add(Segmented(p.child, "Timer colour", { { "WHITE", "White" }, { "CLASS", "Class colour" } }, g, s))
    g, s = Opt("urgentEnabled")
    p:Add(Checkbox(p.child, "Change the timer colour when only a few seconds are left", g, s))
    g, s = Opt("urgentSecs")
    p:Add(Gate(Key("urgentEnabled"), Slider(p.child, "Warning under (seconds)", 1, 30, 1, g, s)))
    g, s = Opt("urgentColor")
    p:Add(Gate(Key("urgentEnabled"), Segmented(p.child, "Warning colour", {
        { "RED", "Red" }, { "ORANGE", "Orange" }, { "YELLOW", "Yellow" },
    }, g, s)))

    p:Add(Header(p.child, "Opacity by state"))
    g, s = Opt("readyAlpha")
    p:Add(Slider(p.child, "Ready spells", 0.1, 1, 0.05, g, s, "%.2f"))
    g, s = Opt("cdAlpha")
    p:Add(Slider(p.child, "Spells on cooldown", 0.1, 1, 0.05, g, s, "%.2f"))
    g, s = Opt("unknownAlpha")
    p:Add(Slider(p.child, "Guessed spells (?)", 0.1, 1, 0.05, g, s, "%.2f"))

    p:Add(Header(p.child, "Icons"))
    g, s = Opt("border")
    p:Add(Checkbox(p.child, "Border", g, s))
    g, s = Opt("borderSize")
    p:Add(Slider(p.child, "Border thickness", 1, 4, 1, g, s))
    g, s = Opt("classBorder")
    p:Add(Checkbox(p.child, "Class-coloured border", g, s))
    g, s = Opt("catBorder")
    p:Add(Checkbox(p.child, "Border coloured by spell type (overrides class colour)", g, s))
    g, s = Opt("readyBorder")
    p:Add(Checkbox(p.child, "Coloured border when ready", g, s))
    g, s = Opt("zoom")
    p:Add(Checkbox(p.child, "Crop icon edges", g, s))
    g, s = Opt("showSwipe")
    p:Add(Checkbox(p.child, "Show cooldown sweep", g, s))
    g, s = Opt("desaturate")
    p:Add(Checkbox(p.child, "Grey out while on cooldown", g, s))

    p:Add(Header(p.child, "Colours and bars"))
    g, s = Opt("readyColor")
    p:Add(Segmented(p.child, "Ready colour", {
        { "GREEN", "Green" }, { "CYAN", "Cyan" }, { "GOLD", "Gold" }, { "WHITE", "White" },
    }, g, s))
    g, s = Opt("barColor")
    p:Add(Segmented(p.child, "Bar colour", { { "CLASS", "Class colour" }, { "CATEGORY", "Spell type" } }, g, s))
    g, s = Opt("barSpellName")
    p:Add(Checkbox(p.child, "Show spell name on bars", g, s))
    g, s = Opt("iconSide")
    p:Add(Segmented(p.child, "Icon on bars", {
        { "LEFT", "Left" }, { "RIGHT", "Right" }, { "NONE", "Hidden" },
    }, g, s))
    g, s = Opt("timerSide")
    p:Add(Segmented(p.child, "Timer on bars", { { "RIGHT", "Right" }, { "LEFT", "Left" } }, g, s))
    g, s = Opt("barTexture")
    p:Add(EditBox(p.child, "Bar texture (Flat, Blizzard, Raid, or a SharedMedia name)", g, s))
end

-- Each feature below has its own page: a master checkbox, then one checkbox per element, with
-- the dependent options appearing only while their checkbox is ticked.

local COLOR_CHOICES = { { "RED", "Red" }, { "GREEN", "Green" }, { "WHITE", "White" }, { "GOLD", "Gold" },
    { "CYAN", "Cyan" }, { "ORANGE", "Orange" }, { "PURPLE", "Purple" } }
local WHEN_CHOICES = { { "ALWAYS", "Always" }, { "GROUP", "In a group" }, { "DUNGEON", "Dungeons only" } }

local function Feature(p, title, blurb, key, label)
    p:Add(Header(p.child, title))
    if blurb then p:Add(Info(p.child, blurb, 34)) end
    local g, s = Opt(key)
    p:Add(Checkbox(p.child, label or ("Enable " .. title), g, s))
end

local SoundPicker -- defined below with the other sound widgets

local function BuildCombatText(p)
    local g, s
    Feature(p, "Combat text", "Flashes text in the middle of the screen when you enter and leave combat.", "ctEnabled",
        "Enable combat text")
    local on = Key("ctEnabled")
    g, s = Opt("ctEnter")
    p:Add(Gate(on, Checkbox(p.child, "Show when entering combat", g, s)))
    g, s = Opt("ctEnterText")
    p:Add(Gate(All("ctEnabled", "ctEnter"), EditBox(p.child, "Entering combat text", g, s)))
    g, s = Opt("ctEnterClass")
    p:Add(Gate(All("ctEnabled", "ctEnter"), Checkbox(p.child, "Use my class colour (instead of the colour below)", g, s)))
    g, s = Opt("ctEnterColor")
    p:Add(Gate(All("ctEnabled", "ctEnter"), Segmented(p.child, "Entering colour", COLOR_CHOICES, g, s)))
    g, s = Opt("ctLeave")
    p:Add(Gate(on, Checkbox(p.child, "Show when leaving combat", g, s)))
    g, s = Opt("ctLeaveText")
    p:Add(Gate(All("ctEnabled", "ctLeave"), EditBox(p.child, "Leaving combat text", g, s)))
    g, s = Opt("ctLeaveClass")
    p:Add(Gate(All("ctEnabled", "ctLeave"), Checkbox(p.child, "Use my class colour (instead of the colour below)", g, s)))
    g, s = Opt("ctLeaveColor")
    p:Add(Gate(All("ctEnabled", "ctLeave"), Segmented(p.child, "Leaving colour", COLOR_CHOICES, g, s)))
    g, s = Opt("ctSound")
    p:Add(Gate(on, Checkbox(p.child, "Play a sound when entering combat", g, s)))
    g, s = Opt("ctWhen")
    p:Add(Gate(on, Segmented(p.child, "Show", WHEN_CHOICES, g, s)))
    g, s = Opt("ctSize")
    p:Add(Gate(on, Slider(p.child, "Text size", 16, 80, 1, g, s)))
    g, s = Opt("ctDuration")
    p:Add(Gate(on, Slider(p.child, "Seconds on screen", 0.5, 6, 0.5, g, s, "%.1f")))
    p:Add(Gate(on, ButtonRow(p.child, {
        { label = "Test combat text", width = 160, onClick = function() ns.MP:TestText() end },
    })))
end

local function BuildCombatTimer(p)
    local g, s
    Feature(p, "Combat timer", "How long the current fight has lasted. The last fight stays up, dimmed, for a few seconds.",
        "cmbEnabled", "Enable combat timer")
    local on = Key("cmbEnabled")
    g, s = Opt("cmbWhen")
    p:Add(Gate(on, Segmented(p.child, "Show", WHEN_CHOICES, g, s)))
    g, s = Opt("cmbTenths")
    p:Add(Gate(on, Checkbox(p.child, "Show tenths of a second", g, s)))
    g, s = Opt("cmbShowLast")
    p:Add(Gate(on, Checkbox(p.child, "Keep showing the last fight's time after combat", g, s)))
    g, s = Opt("cmbHideDelay")
    p:Add(Gate(All("cmbEnabled", "cmbShowLast"), Slider(p.child, "For how long (seconds, 60 = until the next fight)", 1, 60, 1, g, s)))
    g, s = Opt("cmbColor")
    p:Add(Gate(on, Segmented(p.child, "Colour", COLOR_CHOICES, g, s)))
    g, s = Opt("cmbSize")
    p:Add(Gate(on, Slider(p.child, "Size", 12, 60, 1, g, s)))
    g, s = Opt("cmbBg")
    p:Add(Gate(on, Slider(p.child, "Background opacity", 0, 1, 0.05, g, s, "%.2f")))
end

local function BuildFocusKick(p)
    local g, s, g2, s2
    Feature(p, "Focus kick reminder",
        "When your focus target starts casting and your interrupt is ready, this tells you to kick it. It fades while your interrupt is on cooldown and hides for casts that cannot be interrupted.",
        "fkEnabled", "Enable focus kick reminder")
    p:Add(Gate(Key("fkEnabled"), Info(p.child, "Set a focus with /focus or a macro. Works for any interrupt your class has.", 20)))
    local on = Key("fkEnabled")
    g, s = Opt("fkOnlyReady")
    p:Add(Gate(on, Checkbox(p.child, "Hide it completely while my interrupt is on cooldown", g, s)))
    g, s = Opt("fkSoundOn")
    p:Add(Gate(on, Checkbox(p.child, "Play a sound when the cast starts (only if my interrupt is ready)", g, s)))
    p:Add(Gate(All("fkEnabled", "fkSoundOn"), SoundPicker(p.child, "Sound", "sndFocusKick", {
        { "@RAID_WARNING", "Default: Raid warning" }, { "@READY_CHECK", "Default: Ready check" },
        { "@BOSS_WHISPER", "Default: Boss whisper" },
    })))
    g, s = Opt("fkText")
    p:Add(Gate(on, EditBox(p.child, "Text", g, s)))
    g, s = Opt("fkColor")
    p:Add(Gate(on, Segmented(p.child, "Colour", COLOR_CHOICES, g, s)))
    g, s = Opt("fkSize")
    p:Add(Gate(on, Slider(p.child, "Size", 16, 80, 1, g, s)))
    g, s = Opt("fkMarkerIndex")
    local markers = {}
    for i, name in ipairs({ "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }) do
        markers[i] = { i, "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":16|t  " .. name }
    end
    local fk = Key("fkEnabled")
    g2, s2 = Opt("fkAnnounceOn")
    p:Add(Gate(fk, Checkbox(p.child, "Announce to party", g2, s2)))
    p:Add(Gate(fk, Dropdown(p.child, "My focus marker", markers, g, s)))
    p:Add(Gate(fk, ButtonRow(p.child, {
        { label = "Announce now", width = 140, onClick = function() ns.MP:AnnounceFocus(true) end },
        { label = "Test reminder", width = 140, onClick = function() ns.MP:TestFocusKick() end },
    })))
end

local function BuildDeaths(p)
    local g, s
    Feature(p, "Group death alert", "Shows \"<name> died\" in class colour when a party member dies.", "dtEnabled",
        "Enable group death alert")
    local on = Key("dtEnabled")
    g, s = Opt("dtOnlyInstance")
    p:Add(Gate(on, Checkbox(p.child, "Only inside dungeons and raids", g, s)))
    g, s = Opt("dtSelf")
    p:Add(Gate(on, Checkbox(p.child, "Also alert when I die", g, s)))
    g, s = Opt("dtSound")
    p:Add(Gate(on, Checkbox(p.child, "Play a sound", g, s)))
    p:Add(Gate(All("dtEnabled", "dtSound"), SoundPicker(p.child, "Sound", "sndDeath", {
        { "@RAID_WARNING", "Default: Raid warning" }, { "@READY_CHECK", "Default: Ready check" },
        { "@BOSS_WHISPER", "Default: Boss whisper" },
    })))
    g, s = Opt("dtText")
    p:Add(Gate(on, EditBox(p.child, "Text ({name} is replaced by the player)", g, s)))
    g, s = Opt("dtSize")
    p:Add(Gate(on, Slider(p.child, "Text size", 10, 40, 1, g, s)))
    g, s = Opt("dtDuration")
    p:Add(Gate(on, Slider(p.child, "Seconds on screen", 1, 15, 1, g, s)))
end

local function BuildAlerts(p)
    local g, s
    p:Add(Header(p.child, "Reminders"))
    do local mg, ms = Opt("alEnabled"); p:Add(Checkbox(p.child, "Enable the reminders module", mg, ms)) end
    p:Add(Info(p.child, "Small text reminders in one movable spot. Each one is its own switch.", 20))
    g, s = Opt("alRepair")
    p:Add(Checkbox(p.child, "Repair reminder (out of combat)", g, s))
    g, s = Opt("alRepairPct")
    p:Add(Gate(Key("alRepair"), Slider(p.child, "Warn below this durability (%)", 5, 90, 5, g, s)))
    g, s = Opt("alMana")
    p:Add(Checkbox(p.child, "Healer low on mana (in dungeons)", g, s))
    g, s = Opt("alManaPct")
    p:Add(Gate(Key("alMana"), Slider(p.child, "Warn below this mana (%)", 5, 90, 5, g, s)))
    g, s = Opt("alNoTarget")
    p:Add(Checkbox(p.child, "\"No target\" while in combat", g, s))
    g, s = Opt("alSize")
    p:Add(Slider(p.child, "Text size", 10, 40, 1, g, s))
end

local function BuildKeyHUD(p)
    local g, s
    Feature(p, "Key HUD", "Timer, enemy forces, deaths and bosses for the key you are running.", "mpEnabled",
        "Enable the key HUD")
    local on = Key("mpEnabled")
    g, s = Opt("mpTitle")
    p:Add(Gate(on, Checkbox(p.child, "Dungeon name and key level", g, s)))
    g, s = Opt("mpAffixes")
    p:Add(Gate(on, Checkbox(p.child, "Affixes", g, s)))
    g, s = Opt("mpTimer")
    p:Add(Gate(on, Checkbox(p.child, "Key timer with +2 / +3 markers", g, s)))
    g, s = Opt("mpTimerMode")
    p:Add(Gate(All("mpEnabled", "mpTimer"), Segmented(p.child, "Timer shows", { { "ELAPSED", "Time elapsed" }, { "REMAINING", "Time left" } }, g, s)))
    g, s = Opt("mpThresholds")
    p:Add(Gate(All("mpEnabled", "mpTimer"), Checkbox(p.child, "Time left for +3 / +2 / +1 (deaths included)", g, s)))
    g, s = Opt("mpForces")
    p:Add(Gate(on, Checkbox(p.child, "Enemy forces percentage", g, s)))
    g, s = Opt("mpForcesMode")
    p:Add(Gate(All("mpEnabled", "mpForces"), Segmented(p.child, "Forces shown as", { { "PERCENT", "Percent" }, { "COUNT", "Count" }, { "BOTH", "Both" } }, g, s)))
    g, s = Opt("mpSummary")
    p:Add(Gate(on, Checkbox(p.child, "Run summary in chat when a key ends (deaths per player)", g, s)))
    g, s = Opt("mpHistoryOn")
    p:Add(Gate(on, Checkbox(p.child, "Keep run history (/salthist)", g, s)))
    g, s = Opt("mpDeaths")
    p:Add(Gate(on, Checkbox(p.child, "Death count and time lost", g, s)))
    g, s = Opt("mpBrez")
    p:Add(Gate(on, Checkbox(p.child, "Battle res charges and next charge", g, s)))
    g, s = Opt("mpObjectives")
    p:Add(Gate(on, Checkbox(p.child, "Boss list with kill times", g, s)))
    g, s = Opt("mpCompare")
    p:Add(Gate(All("mpEnabled", "mpObjectives"), Checkbox(p.child, "Compare with my fastest kill of each boss", g, s)))
    g, s = Opt("mpScale")
    p:Add(Gate(on, Slider(p.child, "Scale", 0.6, 1.6, 0.05, g, s, "%.2f")))
    g, s = Opt("mpWidth")
    p:Add(Gate(on, Slider(p.child, "Width", 160, 400, 5, g, s)))
    g, s = Opt("mpBarHeight")
    p:Add(Gate(on, Slider(p.child, "Bar height", 6, 24, 1, g, s)))
    g, s = Opt("mpBg")
    p:Add(Gate(on, Slider(p.child, "Background opacity", 0, 1, 0.05, g, s, "%.2f")))
end

local function BuildIcons(p)
    local g, s
    Feature(p, "Battle res and Bloodlust icons", "Two small icons: battle res charges (with the next charge timer) and the Sated timer.",
        "mpIcons", "Enable the icons")
    local on = Key("mpIcons")
    g, s = Opt("mpIconBR")
    p:Add(Gate(on, Checkbox(p.child, "Battle res icon (in keys and raid fights)", g, s)))
    g, s = Opt("mpIconBL")
    p:Add(Gate(on, Checkbox(p.child, "Bloodlust / Sated icon", g, s)))
    g, s = Opt("blReady")
    p:Add(Gate(All("mpIcons", "mpIconBL"), Checkbox(p.child, "Show \"READY\" when I am not Sated", g, s)))
    g, s = Opt("mpIconSize")
    p:Add(Gate(on, Slider(p.child, "Icon size", 20, 80, 1, g, s)))
end

local function BuildKickOrder(p)
    local g, s
    Feature(p, "Kick order", "Lists who should interrupt next, in an order you set. The next player lights up green once the one before them has used their kick.",
        "krEnabled", "Show the kick order")
    local on = Key("krEnabled")
    p:Add(Gate(on, ButtonRow(p.child, {
        { label = "Set order (me first)", width = 170, onClick = function() ns.MP:AssignKickOrder(false) end },
        { label = "Set order and announce", width = 190, onClick = function() ns.MP:AssignKickOrder(true) end },
    })))
    g, s = Opt("krSize")
    p:Add(Gate(on, Slider(p.child, "Text size", 9, 24, 1, g, s)))
    g, s = Opt("krWidth")
    p:Add(Gate(on, Slider(p.child, "Width", 140, 360, 5, g, s)))
    g, s = Opt("krBg")
    p:Add(Gate(on, Slider(p.child, "Background opacity", 0, 1, 0.05, g, s, "%.2f")))
end

local function BuildPartyKeys(p)
    local g, s
    Feature(p, "Party keystones",
        "While you are in a group and outside a dungeon, lists everyone's keystone. Click a row to teleport to that dungeon, shift-click to post the key in party chat.",
        "klEnabled", "Show the party keystone list")
    local on = Key("klEnabled")
    g, s = Opt("klWhen")
    p:Add(Gate(on, Segmented(p.child, "Show", {
        { "OUTSIDE", "Outside dungeons only" }, { "ANYWHERE", "Anywhere except during a key" },
    }, g, s)))
    g, s = Opt("klClick")
    p:Add(Gate(on, Checkbox(p.child, "Click a row to teleport", g, s)))
    g, s = Opt("klIncludeSelf")
    p:Add(Gate(on, Checkbox(p.child, "Include my own key", g, s)))
    g, s = Opt("klScale")
    p:Add(Gate(on, Slider(p.child, "Scale", 0.6, 1.6, 0.05, g, s, "%.2f")))
    g, s = Opt("klWidth")
    p:Add(Gate(on, Slider(p.child, "Width", 220, 420, 5, g, s)))
    g, s = Opt("klBg")
    p:Add(Gate(on, Slider(p.child, "Background opacity", 0, 1, 0.05, g, s, "%.2f")))
    p:Add(Gate(on, Info(p.child, "Keys are shared the same way Details, BigWigs and LibKeystone users share them, so party members need no special addon. Teleports need the dungeon's teleport spell learned, and cannot be cast in combat.", 48)))
    p:Add(Gate(on, ButtonRow(p.child, {
        { label = "Ask the party for keys", width = 190, onClick = function() ns.MP:RequestKeys() end },
        { label = "Post my key", width = 130, onClick = function() ns.MP:AnnounceKey() end },
    })))
end

local function BuildKeyHelpers(p)
    local g, s
    p:Add(Header(p.child, "Key helpers"))
    do local mg, ms = Opt("khEnabled"); p:Add(Checkbox(p.child, "Enable the key helpers module", mg, ms)) end
    g, s = Opt("mpAutoKey")
    p:Add(Checkbox(p.child, "Put my keystone in the pedestal automatically", g, s))
    g, s = Opt("mpHideBlizz")
    p:Add(Checkbox(p.child, "Hide Blizzard's objective tracker during a key", g, s))
    g, s = Opt("qolTalkingHead")
    p:Add(Checkbox(p.child, "Hide the talking head pop-up", g, s))
    p:Add(Info(p.child, "A finished key prints your time and compares it with your personal best for that dungeon and level.", 34))
    g, s = Opt("mpLastPull")
    p:Add(Checkbox(p.child, "Show how much enemy forces your last pull gave (on the Key HUD)", g, s))
    p:Add(Header(p.child, "Mythic Dungeon Tools (MDT)"))
    p:Add(Info(p.child, "|cffffaa33Needs the Mythic Dungeon Tools addon (MDT) to be installed.|r These options are found and switched on automatically when MDT is present, and greyed out when it is not. Nothing from MDT is copied into this addon.", 48))
    p:Add(Info(p.child, function() return "Status: " .. ((ns.MP and ns.MP.MDT) and ns.MP.MDT.Status() or "MDT not installed") end, 18))
    g, s = Opt("mdtEnabled")
    p:Add(GreyIf(NoMDT, Checkbox(p.child, "Enable the MDT link", g, s)))
    g, s = Opt("mdtTooltip")
    p:Add(GreyIf(NoMDT, Checkbox(p.child, "Show enemy forces (count and %) in mob tooltips", g, s)))
    p:Add(GreyIf(NoMDT, ButtonRow(p.child, {
        { label = "Open MDT", width = 140, onClick = function()
            if not NoMDT() then ns.MP.MDT.Open() end
        end },
    })))
end

local function BuildLogging(p)
    local g, s
    Feature(p, "Automatic combat logging", "Starts /combatlog when you enter the content ticked below and stops it when you leave.",
        "logEnabled", "Enable automatic combat logging")
    local on = Key("logEnabled")
    g, s = Opt("logMplus")
    p:Add(Gate(on, Checkbox(p.child, "Mythic+ dungeons", g, s)))
    g, s = Opt("logMythicRaid")
    p:Add(Gate(on, Checkbox(p.child, "Mythic raids", g, s)))
    g, s = Opt("logHeroicRaid")
    p:Add(Gate(on, Checkbox(p.child, "Heroic raids", g, s)))
    g, s = Opt("logNormalRaid")
    p:Add(Gate(on, Checkbox(p.child, "Normal raids", g, s)))
    g, s = Opt("logChat")
    p:Add(Gate(on, Checkbox(p.child, "Tell me in chat when logging starts or stops", g, s)))
end

local function BuildTracking(p)
    local g, s
    p:Add(Header(p.child, "What to show"))
    p:Add(Chips(p.child, {
        { "INT", "Interrupts" }, { "CC", "Stuns & CC" }, { "BREZ", "Battle res" }, { "BL", "Bloodlust" },
        { "EXT", "External CDs" }, { "DEF", "Defensives" }, { "OFF", "Offensive" }, { "UTIL", "Utility" },
    }, function(key) return ns.db.categories[key] end,
       function(key, v) ns.db.categories[key] = v; ns:Refresh() end))
    g, s = Opt("offSeparate")
    p:Add(Checkbox(p.child, "Offensive cooldowns in a separate window (off = one merged row)", g, s))
    g, s = Opt("showUnknown")
    p:Add(Checkbox(p.child, "Show guessed cooldowns as ? until a cast is seen", g, s))
    p:Add(Info(p.child, "Players without the addon get every cooldown their class and specialization has, shown as ? until we see them use it. Talent spells appear after their first cast.", 48))
    p:Add(Header(p.child, "Spells"))
    p:Add(Info(p.child, "Click a spell to stop tracking it. Click again to bring it back. Hover for details. Edit Spells.lua to add spells.", 34))
    p:Add(SpellGrid(p.child))
    p:Add(ButtonRow(p.child, {
        { label = "Track everything", width = 150, onClick = function()
            wipe(ns.db.disabled)
            for _, cat in ipairs(ns.CATEGORIES) do ns.db.categories[cat] = true end
            ns:Refresh()
        end },
    }))
end

local function BuildCC(p)
    local g, s
    p:Add(Header(p.child, "KiraUI CC bars (recommended)"))
    p:Add(Info(p.child, function()
        local ok, why = ns:KiraCCReady()
        if not ok then return "|cffff7373" .. why .. "|r  Without it, the simpler tracker below is used." end
        local on = ns:KiraCCBarsOn()
        return on and "KiraUI's CC bars are on. They show how long stuns and CC have left on each enemy using Midnight's own widgets, so the numbers stay exact. Add your own CC below and they appear there."
            or "KiraUI's CC bars are installed but switched off. Turn them on to track CC with Midnight's own widgets."
    end, 62))
    p:Add(ButtonRow(p.child, {
        { label = "Turn on KiraUI CC bars", width = 190, onClick = function()
            local ok, why = ns:KiraEnableCC()
            ns.Print(ok and "KiraUI CC bars switched on." or why)
            UI.Changed()
        end },
        { label = "Add my class's CC spells", width = 200, onClick = function()
            local ok, n = ns:KiraAddMyCC()
            if ok then
                ns.Print(n > 0 and (n .. " CC spells added to KiraUI's CC bars.") or "Your CC spells are already in KiraUI's CC bars.")
            else
                ns.Print(n)
            end
            UI.Changed()
        end },
    }))
    p:Add(ButtonRow(p.child, {
        { label = "Open KiraUI settings", width = 190, onClick = function()
            if not ns:OpenKiraSettings() then ns.Print("KiraUI plugin not found.") end
        end },
    }))
    p:Add(Header(p.child, "Crowd control on enemies (built-in tracker)"))
    g, s = Opt("ccEnabled")
    p:Add(Checkbox(p.child, "Track the crowd control I put on enemies", g, s))
    p:Add(Info(p.child, "A simpler tracker for when KiraUI's CC bars are not available. It steps aside automatically while they are on. Midnight hides some enemy data, so when the exact time cannot be read a timer starts when you cast.", 48))
    g, s = Opt("ccStyle")
    p:Add(Segmented(p.child, "Style", {
        { "ICONS", "Icons" }, { "BARS", "Bars" }, { "BOTH", "Icons + bars" },
    }, g, s))
    g, s = Opt("ccGrowth")
    p:Add(Segmented(p.child, "Grow towards", {
        { "RIGHT", "Right" }, { "LEFT", "Left" }, { "UP", "Up" }, { "DOWN", "Down" },
    }, g, s))
    g, s = Opt("ccMax")
    p:Add(Slider(p.child, "Maximum shown", 1, 16, 1, g, s))
    g, s = Opt("ccIconSize")
    p:Add(Slider(p.child, "Icon size", 20, 64, 1, g, s))
    g, s = Opt("ccBarWidth")
    p:Add(Slider(p.child, "Bar width", 100, 320, 1, g, s))
    g, s = Opt("ccBarHeight")
    p:Add(Slider(p.child, "Bar height", 12, 40, 1, g, s))
    g, s = Opt("ccShowName")
    p:Add(Checkbox(p.child, "Show the enemy's name", g, s))
    g, s = Opt("ccEstimate")
    p:Add(Checkbox(p.child, "Start a timer when I cast a CC spell (fallback)", g, s))
    p:Add(Info(p.child, "Use Preview party in the sidebar to see example crowd control, and Move frames to place the window.", 34))
end

local function SyncOnlyBox(p)
    local g = function() return ns.db.syncOnly end
    p:Add(Checkbox(p.child, "Just to Sync (sync-only mode)", g, function(v)
        ns.db.syncOnly = v
        ns:Refresh()
    end))
    p:Add(Info(p.child, "Stays in the SaltyM+Helper sync network, sharing your cooldowns and tracking everyone else's, but shows nothing and runs none of the other features (windows, HUD, alerts, key list, logging...). Use it when another addon does the displaying. Untick to get everything back. Also /salty synconly.", 62))
end

-- Looks through the sounds registered with LibSharedMedia (BigWigs registers its sounds there,
-- as "BigWigs: <name>") for a cat sound. Nothing is bundled; the sound files stay BigWigs's.
local function FindMeows()
    local stub = _G.LibStub
    local lsm = stub and stub("LibSharedMedia-3.0", true)
    if not (lsm and lsm.List and lsm.Fetch) then return {}, 0, false end
    local out, total, bigwigs = {}, 0, false
    for _, name in ipairs(lsm:List("sound") or {}) do
        total = total + 1
        local lower = name:lower()
        if lower:find("^bigwigs") then bigwigs = true end
        if lower:find("meow", 1, true) or lower:find("kitty", 1, true) or lower:find("purr", 1, true)
            or lower:find("%f[%a]cat%f[%A]") then
            local path = lsm:Fetch("sound", name, true)
            if path then
                -- BigWigs sounds first
                table.insert(out, lower:find("^bigwigs") and 1 or #out + 1, { name = name, path = path })
            end
        end
    end
    return out, total, bigwigs
end

local function Meow()
    local list, total, bigwigs = FindMeows()
    if #list == 0 then
        ns.Print(bigwigs and "BigWigs sounds are loaded, but none of them is a meow." or "No BigWigs sounds found (BigWigs not loaded?).")
        ns.Print("Tell me the name of the sound you want (or the sound pack it is in) and I will use it.")
        return
    end
    local pick = list[math.random(#list)]
    local ok = pcall(PlaySoundFile, pick.path, "Master")
    if ok then ns.Print("Meow! (" .. pick.name .. ")") end
end

---------------------------------------------------------------------------
-- Sound picker: a button that opens a scrollable list of every sound LibSharedMedia knows
---------------------------------------------------------------------------

local soundPopup
local function SoundPopup()
    if soundPopup then return soundPopup end
    local f = CreateFrame("Frame", "SaltyMPlusHelperSoundList", UIParent, "BackdropTemplate")
    f:SetSize(280, 320)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    Backdrop(f, C.bg, C.accent)
    f:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(268, 10)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(min(maxScroll, max(0, (self:GetVerticalScroll() or 0) - delta * 66)))
    end)
    f.child, f.buttons = child, {}
    soundPopup = f
    return f
end

local function OpenSoundList(anchor, current, onPick, defaults)
    local f = SoundPopup()
    if f:IsShown() and f.owner == anchor then f:Hide() return end
    f.owner = anchor
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    local names = ns.Snd and ns.Snd.List() or {}
    local entries = {}
    if defaults then
        for _, d in ipairs(defaults) do entries[#entries + 1] = d end
    else
        entries[1] = { "", "Default (built-in sound)" }
    end
    for _, n in ipairs(names) do entries[#entries + 1] = { n, ns.Snd.Clean(n) } end
    for i, e in ipairs(entries) do
        local b = f.buttons[i]
        if not b then
            b = Button(f.child, "", 262, 20, nil)
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 6, 0)
            b.text:SetJustifyH("LEFT")
            f.buttons[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.child, "TOPLEFT", 0, -(i - 1) * 21)
        b.text:SetText(e[2])
        b:SetSelected(e[1] == (current or ""))
        b:SetScript("OnClick", function()
            f:Hide()
            onPick(e[1])
        end)
        b:Show()
    end
    for i = #entries + 1, #f.buttons do f.buttons[i]:Hide() end
    f.child:SetHeight(#entries * 21)
    f:Show()
end

SoundPicker = function(parent, label, key, defaults)
    local w = { height = 30, gap = 4 }
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(30)
    local t = Text(f, 12, C.text)
    t:SetPoint("LEFT", 0, 0)
    t:SetText(label)
    local test = Button(f, "Test", 46, 22, function()
        local name = ns.db[key]
        if name and name ~= "" then ns.Snd.Play(name) else ns.Print("Default sound is chosen: pick one from the list to hear it.") end
    end)
    test:SetPoint("RIGHT", 0, 0)
    local pick = Button(f, "", 210, 22, nil)
    pick:SetPoint("RIGHT", test, "LEFT", -6, 0)
    pick.text:ClearAllPoints()
    pick.text:SetPoint("LEFT", 8, 0)
    pick.text:SetPoint("RIGHT", -8, 0)
    pick.text:SetJustifyH("LEFT")
    pick:SetScript("OnClick", function(self)
        OpenSoundList(self, ns.db[key], function(name)
            ns.db[key] = name
            if name ~= "" then ns.Snd.Play(name) end
            UI.Changed()
        end, defaults)
    end)
    w.frame = f
    w.Refresh = function()
        local name = ns.db[key]
        pick.text:SetText(ns.Snd.DefaultLabel(name) or ((name and name ~= "") and ns.Snd.Clean(name) or "Default (built-in sound)"))
    end
    return w
end

local function BuildSounds(p)
    p:Add(Header(p.child, "Sound pack check (SharedMedia_SaltyM)"))
    local results = {}
    local function run(noPlay) results = ns.Snd and ns.Snd.Check(noPlay) or {} end
    run(true)
    p:Add(LineList(p.child, 7, function()
        local out = {}
        for _, r in ipairs(results) do
            local col = r.level == "good" and C.good or (r.level == "bad" and C.bad or { 1, 0.75, 0.3 })
            out[#out + 1] = { name = r.label, text = r.text, color = col }
        end
        if #out == 0 then out[1] = { name = "Press Check now", text = "", color = C.dim } end
        return out
    end))
    p:Add(ButtonRow(p.child, { { label = "Check now", width = 140, onClick = function()
        run()
        UI.Changed()
    end } }))
    p:Add(Info(p.child, "Looks for the SharedMedia_SaltyM addon, confirms its sounds and image are registered, and plays a test sound to prove the game can open the files.", 34))
    p:Add(Header(p.child, "Sound alerts"))
    do local mg, ms = Opt("sndEnabled"); p:Add(Checkbox(p.child, "Enable custom sound alerts", mg, ms)) end
    p:Add(Info(p.child, "Pick any sound from BigWigs, the Causese pack, SharedMedia_SaltyM or any other pack that uses LibSharedMedia. Nothing is copied from those addons; they only need to be installed.", 48))
    p:Add(Info(p.child, function() return ns.Snd and ns.Snd.Summary() or "" end, 18))
    local on = {
        FocusKick = "fkSoundOn", Death = "dtSound", KeyStart = "sndKeyStartOn", KeyDone = "sndKeyDoneOn",
    }
    local labels = {
        FocusKick = "Play a sound when my focus starts a cast", Death = "Play a sound when a group member dies",
        KeyStart = "Play a sound when a key starts", KeyDone = "Play a sound when a key finishes",
    }
    for _, e in ipairs(ns.Snd and ns.Snd.EVENTS or {}) do
        local ev = e[1]
        local g, s = Opt(on[ev])
        p:Add(Checkbox(p.child, labels[ev], g, s))
        p:Add(Gate(Key(on[ev]), SoundPicker(p.child, "   Sound", "snd" .. ev)))
    end
end

-- Master switch for every module (like EllesmereUI's module list): one checkbox each, plus a
-- shortcut to that module's own settings page.
local MODULES = {
    { "PARTY COOLDOWNS" },
    { "Party cooldowns", "enabled", "general", "Kicks, defensives and offensives next to the party frames" },
    { "Crowd control tracker", "ccEnabled", "cc", "Timers for the CC you put on enemies" },
    { "COMBAT" },
    { "Combat text", "ctEnabled", "combattext", "+ COMBAT / - COMBAT flash" },
    { "Combat timer", "cmbEnabled", "combattimer", "How long the fight has run" },
    { "Focus kick", "fkEnabled", "focuskick", "Reminder when your focus is casting" },
    { "Death alert", "dtEnabled", "deaths", "Announces group deaths" },
    { "Reminders", "alEnabled", "alerts", "Repair, healer mana, no target" },
    { "Custom sound alerts", "sndEnabled", "sounds", "Your chosen sounds for alerts" },
    { "MYTHIC+ RUN" },
    { "Key HUD", "mpEnabled", "hud", "Timer, forces, deaths, brez, bosses" },
    { "Brez / Lust icons", "mpIcons", "icons", "Battle res and Sated icons" },
    { "Kick order", "krEnabled", "kickorder", "Who kicks next" },
    { "Party keystones", "klEnabled", "partykeys", "Keystone list with teleports" },
    { "Key helpers", "khEnabled", "keyhelpers", "Auto-slot key, hide tracker, talking head" },
    { "Combat logging", "logEnabled", "logging", "Starts /combatlog for you" },
    { "ADDON" },
    { "Mythic Dungeon Tools link", "mdtEnabled", "keyhelpers", "Mob forces in tooltips (needs MDT)" },
}

local function BuildModules(p)
    p:Add(Header(p.child, "Modules"))
    p:Add(Info(p.child, "Master switch for each part of the addon. A module that is off does nothing and shows nothing. Settings are kept, so switching it back on restores everything.", 34))
    p:Add(ButtonRow(p.child, {
        { label = "Enable all", width = 120, onClick = function()
            for _, m in ipairs(MODULES) do if m[2] then ns.db[m[2]] = true end end
            ns:Refresh(); UI.Changed()
        end },
        { label = "Disable all", width = 120, onClick = function()
            for _, m in ipairs(MODULES) do if m[2] then ns.db[m[2]] = false end end
            ns:Refresh(); UI.Changed()
        end },
    }))
    for _, m in ipairs(MODULES) do
        if not m[2] then
            p:Add(Header(p.child, m[1]))
        else
            local key, tab = m[2], m[3]
            local w = Checkbox(p.child, m[1], function() return ns.db[key] end, function(v)
                ns.db[key] = v
                ns:Refresh()
            end)
            local go = Button(w.frame, "Settings", 70, 20, function()
                if UI.SelectTab then UI.SelectTab(tab) end
            end)
            go:SetPoint("RIGHT", 0, 0)
            local d = Text(w.frame, 11, C.dim, "RIGHT")
            d:SetPoint("RIGHT", go, "LEFT", -10, 0)
            d:SetText(m[4])
            p:Add(w)
        end
    end
end

-- WoW addons cannot open a web page, so the link is shown in a box that is already selected:
-- press Ctrl+C, then paste it into a browser.
local KEY_TEAM_URL = "https://raider.io/teams/us/guys-he-bloodlusted"
local linkBox
local function ShowLink(title, url)
    if not linkBox then
        local f = CreateFrame("Frame", "SaltyMPlusHelperLinkBox", UIParent, "BackdropTemplate")
        f:SetSize(440, 110)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        Backdrop(f, C.bg, C.accent)
        f.title = Text(f, 14, C.text, "CENTER")
        f.title:SetPoint("TOP", 0, -12)
        f.hint = Text(f, 11, C.dim, "CENTER")
        f.hint:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
        f.hint:SetText("Press Ctrl+C to copy the link, then paste it into your browser.")
        local eb = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        eb:SetSize(400, 24)
        eb:SetPoint("TOP", f.hint, "BOTTOM", 0, -10)
        eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal or GameFontNormal)
        eb:SetTextInsets(6, 6, 0, 0)
        Backdrop(eb, C.panel, C.line)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        -- keep the text unchanged if someone types in it
        eb:SetScript("OnTextChanged", function(self, user)
            if user and f.url then self:SetText(f.url); self:HighlightText() end
        end)
        f.edit = eb
        local close = Button(f, "Close", 90, 22, function() f:Hide() end)
        close:SetPoint("BOTTOM", 0, 10)
        tinsert(UISpecialFrames, "SaltyMPlusHelperLinkBox")
        linkBox = f
    end
    linkBox.url = url
    linkBox.title:SetText(title)
    linkBox.edit:SetText(url)
    linkBox:Show()
    linkBox.edit:SetFocus()
    linkBox.edit:HighlightText()
end

local function BuildWelcome(p)
    SyncOnlyBox(p)
    local mg = Opt("menuButton")
    p:Add(Checkbox(p.child, "Show my logo on the Esc game menu (click it to open these settings)", mg, function(v)
        ns.db.menuButton = v
        if UI.UpdateMenuButton then UI.UpdateMenuButton() end
    end))
    local wg, ws = Opt("welcomeMsg")
    p:Add(Checkbox(p.child, "Show a welcome message in chat when I log in", wg, ws))
    p:Add(Header(p.child, "Welcome to SaltyM+Helper v" .. tostring(ns.VERSION)))
    p:Add(Info(p.child, "One addon for pushing keys: party cooldowns, crowd control, a full key HUD, alerts and party keystone teleports. Every feature has its own page in the sidebar and every setting has a checkbox. In move mode, right-click any module to jump to its settings.", 48))
    p:Add(ButtonRow(p.child, {
        { label = "Meow", width = 110, onClick = Meow },
        { label = "Key Team", width = 110, onClick = function() ShowLink("Key Team on Raider.IO", KEY_TEAM_URL) end },
    }))
    local log = ns.CHANGELOG or {}
    local newest = log[1]
    p:Add(Header(p.child, "What's new in " .. (newest and newest.version or tostring(ns.VERSION))))
    if newest then
        local lines = {}
        for _, item in ipairs(newest.items) do lines[#lines + 1] = "- " .. item end
        p:Add(Info(p.child, table.concat(lines, "\n"), #lines * 14 + 8))
    end
    if #log > 1 then
        p:Add(Header(p.child, "Earlier versions"))
        local lines = {}
        for i = 2, #log do
            lines[#lines + 1] = "|cffb866ff" .. log[i].version .. "|r"
            for _, item in ipairs(log[i].items) do lines[#lines + 1] = "- " .. item end
        end
        p:Add(Info(p.child, table.concat(lines, "\n"), #lines * 14 + 8))
    end
    p:Add(Header(p.child, "Slash commands"))
    p:Add(Info(p.child, "/salty  (or /smh, /saltym)  open this window\n/salty test  toggle the preview party\n/salty move  unlock or lock frames for dragging\n/salty show | hide | toggle  turn the addon on or off\n/salty scale 0.5-2  scale every frame\n/salty sync  announce yourself to the party\n/salty status  print sync and version info\n/salty reset  reset all frame positions\n/salty eui  toggle EllesmereUI unlock mode\n/salty cds  compare built-in cooldowns with the game's values\n/salty mdt  open Mythic Dungeon Tools (if installed)\n/salty secrets  show which party casts the game lets addons read\n/salthist  list your last 10 finished keys\n/skeys  list party keystones ('/skeys announce' posts yours)", 228))
    p:Add(Header(p.child, "Feature sets"))
    p:Add(Info(p.child, "Party cooldowns: kicks, CC, defensives and offensives in one display, bars and/or icons, auto-sync with other users and spec guessing\nCrowd control: timers for CC you put on enemies\nCombat: in/out of combat text, combat timer, focus kick reminder, group death alert, reminders (repair, healer mana, no target)\nMythic+ run: key HUD (timer, +2/+3, forces, deaths, brez, bosses), brez and lust icons, kick order, party keystone list with teleports, key helpers, auto combat logging\nAddon: sync, EllesmereUI/KiraUI integrations, profiles with import and export", 130))
end

local function BuildSync(p)
    SyncOnlyBox(p)
    local g, s = Opt("autoSync")
    p:Add(Header(p.child, "Party sync"))
    p:Add(Checkbox(p.child, "Automatically find and sync with party members", g, function(v)
        ns.db.autoSync = v
        if v then ns:ScheduleSync() end
    end))
    p:Add(Info(p.child, "When you join a group the addon announces itself and asks everyone to answer. Members running SaltyM+Helper share exact cooldowns, everyone else is estimated from their casts.", 48))
    p:Add(Header(p.child, "Party members"))
    p:Add(LineList(p.child, 5, function()
        local out = {}
        for _, e in ipairs(ns:GetSyncRoster()) do
            local text, color
            local spec = e.spec and ns.SpecName(e.spec) or "spec unknown"
            if e.self then
                text, color = format("you  v%s  (%s)", ns.VERSION, spec), C.good
            elseif e.hasAddon then
                text, color = format("synced  v%s  (%s)", e.version or "?", spec), C.good
            else
                text, color = format("no addon, guessed from class  (%s)", spec), C.dim
            end
            out[#out + 1] = { name = e.name, class = e.class, text = text, color = color }
        end
        if #out == 0 then out[1] = { name = "Not in a group", text = "", color = C.dim } end
        return out
    end))
    p:Add(Info(p.child, function()
        return "Sync status: " .. (ns:SyncBlocked() and "paused (key or boss fight, Blizzard blocks addon messages)" or "live")
    end, 20))
    p:Add(ButtonRow(p.child, {
        { label = "Sync now", width = 140, onClick = function()
            ns.Print(ns:Announce(true) and "Sync sent." or "Could not send (not in a group, or messages are blocked right now).")
        end },
        { label = "Re-scan party", width = 140, onClick = function()
            ns:ScanRoster()
            ns:ScheduleSync()
        end },
    }))
end

local function BuildIntegrations(p)
    p:Add(Header(p.child, "UI addons"))
    p:Add(Checkbox(p.child, "Add the windows to EllesmereUI /unlock", function() return ns.db.euiUnlock end, function(v)
        ns.db.euiUnlock = v
        if v then ns:RegisterEllesmere() else ns:UnregisterEllesmere() end
    end))
    p:Add(Info(p.child, function()
        local bw, eui, kira = ns:IntegrationStatus()
        return "BigWigs: " .. bw .. "     EllesmereUI: " .. eui .. "     KiraUI: " .. kira
    end, 20))

    p:Add(Header(p.child, "KiraUI plugin"))
    p:Add(Info(p.child, "KiraUI already draws crowd control, party cooldowns and interrupts with Midnight 12.1's aura containers. Its modules that are switched on are listed here so you can avoid showing the same thing twice.", 48))
    p:Add(LineList(p.child, 6, function()
        local out = {}
        for _, m in ipairs(ns:KiraModuleList()) do
            out[#out + 1] = { name = m.label, text = m.on and "on" or "off", color = m.on and C.good or C.dim }
        end
        if #out == 0 then out[1] = { name = "KiraUI plugin not found", text = "", color = C.dim } end
        return out
    end))
    p:Add(Checkbox(p.child, "Hide my CC tracker while KiraUI's CC bars are on", function() return ns.db.ccDefer end, function(v)
        ns.db.ccDefer = v
        ns:Refresh()
    end))
    p:Add(ButtonRow(p.child, {
        { label = "Open KiraUI settings", width = 190, onClick = function()
            if not ns:OpenKiraSettings() then ns.Print("KiraUI plugin not found.") end
        end },
    }))
    p:Add(Header(p.child, "What each party member is attached to"))
    p:Add(Checkbox(p.child, "Scan for unit frames of any addon when no known name matches", function() return ns.db.scanFrames end, function(v)
        ns.db.scanFrames = v
        ns:ClearFrameCache()
        if v then ns:RequestFrameScan(true) end
    end))
    p:Add(LineList(p.child, 5, function()
        local out = {}
        for _, e in ipairs(ns:DescribeAnchors()) do
            local ok = e.text ~= "window (no frame found)"
            out[#out + 1] = { name = e.name, class = e.class, text = e.text, color = ok and C.good or C.dim }
        end
        return out
    end))
    p:Add(Header(p.child, "Custom party frames"))
    p:Add(EditBox(p.child, "Frame name pattern (use %d for the slot number)",
        function() return ns.db.customFrame end,
        function(v)
            ns.db.customFrame = v
            ns:ClearFrameCache()
            ns:Refresh()
        end))
    p:Add(Info(p.child, "Type /fstack in game and hover your party frame to read its name, then replace the slot number with %d. Example: ElvUF_PartyGroup1UnitButton%d", 48))
    p:Add(ButtonRow(p.child, {
        { label = "Re-detect frames", width = 150, onClick = function()
            ns:ClearFrameCache()
            ns:Refresh()
        end },
    }))
end

local function BuildProfiles(p)
    local exportBox, importBox
    p:Add(Header(p.child, "Share your setup"))
    p:Add(Info(p.child, "Export turns every setting (colours, layout, positions, tracked spells) into one line of text you can keep as a backup or paste to a friend.", 34))
    exportBox = EditBox(p.child, "Your profile string", function() return UI.exportText or "" end, function() end)
    p:Add(exportBox)
    p:Add(ButtonRow(p.child, {
        { label = "Export my settings", width = 180, onClick = function()
            UI.exportText = ns:ExportProfile()
            exportBox.Refresh()
            exportBox.edit:HighlightText()
            exportBox.edit:SetFocus()
        end },
    }))
    p:Add(Header(p.child, "Import"))
    importBox = EditBox(p.child, "Paste a profile string here", function() return "" end, function() end)
    p:Add(importBox)
    p:Add(Info(p.child, function() return UI.importMsg or "" end, 20))
    p:Add(ButtonRow(p.child, {
        { label = "Import", width = 120, onClick = function()
            local ok, msg = ns:ImportProfile(importBox.edit:GetText())
            UI.importMsg = (ok and "|cff59e680" or "|cffff7373") .. msg .. "|r"
            importBox.edit:SetText("")
            UI.Changed()
        end },
        { label = "Reset all settings", width = 200,
          text = function() return UI.resetArmed and "Click again to confirm" or "Reset all settings" end,
          selected = function() return UI.resetArmed end,
          onClick = function()
            if UI.resetArmed then
                UI.resetArmed = false
                ns:ResetProfile()
                UI.importMsg = "Settings reset to the defaults."
            else
                UI.resetArmed = true
                C_Timer.After(5, function() UI.resetArmed = false; UI.Changed() end)
            end
            UI.Changed()
        end },
    }))
end

-- { key, label, builder }; an entry without a builder is a group heading in the sidebar.
local TABS = {
    { "#", "START" },
    { "welcome", "Welcome", BuildWelcome },
    { "modules", "Modules", BuildModules },
    { "#", "PARTY COOLDOWNS" },
    { "general", "General", BuildGeneral },
    { "layout", "Layout", BuildLayout },
    { "appearance", "Appearance", BuildAppearance },
    { "tracking", "Tracking", BuildTracking },
    { "cc", "Crowd Control", BuildCC },
    { "#", "COMBAT" },
    { "combattext", "Combat text", BuildCombatText },
    { "combattimer", "Combat timer", BuildCombatTimer },
    { "focuskick", "Focus kick", BuildFocusKick },
    { "deaths", "Death alert", BuildDeaths },
    { "alerts", "Reminders", BuildAlerts },
    { "sounds", "Sounds", BuildSounds },
    { "#", "MYTHIC+ RUN" },
    { "hud", "Key HUD", BuildKeyHUD },
    { "icons", "Brez / Lust icons", BuildIcons },
    { "kickorder", "Kick order", BuildKickOrder },
    { "partykeys", "Party keystones", BuildPartyKeys },
    { "keyhelpers", "Key helpers", BuildKeyHelpers },
    { "logging", "Combat logging", BuildLogging },
    { "#", "ADDON" },
    { "sync", "Sync", BuildSync },
    { "integrations", "Integrations", BuildIntegrations },
    { "profiles", "Profiles", BuildProfiles },
}

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local win
local pages = {}
local tabButtons = {}
local current

local function SelectTab(key)
    current = key
    for _, t in ipairs(TABS) do
      local k, _, build = t[1], t[2], t[3]
      if build then
        local btn = tabButtons[k]
        btn:SetSelected(k == key)
        if k == key then
            if not pages[k] then
                local page = NewPage(win.content)
                build(page)
                pages[k] = page
            end
            pages[k]:Show()
            pages[k]:Sync()
        elseif pages[k] then
            pages[k]:Hide()
        end
      end
    end
end

UI.SelectTab, UI.TABS = SelectTab, TABS

function UI.Changed(except)
    if not (win and win:IsShown()) then return end
    local page = current and pages[current]
    if page then page:Sync(except) end
    if win.preview then win.preview:SetSelected(ns.preview) end
    if win.move then win.move:SetSelected(ns.editMode) end
end

local function Create()
    win = CreateFrame("Frame", "SaltyMPlusHelperOptions", UIParent, "BackdropTemplate")
    win:Hide() -- new frames start shown; hide it so the first Toggle/OpenFor really opens it
    win:SetSize(WIN_W, WIN_H)
    win:SetPoint("TOPLEFT", UIParent, "TOPLEFT", max(0, UIParent:GetWidth() - WIN_W - 50), -max(10, (UIParent:GetHeight() - WIN_H) / 2))
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    Backdrop(win, C.bg, C.accent)

    -- header
    local logo = win:CreateTexture(nil, "ARTWORK")
    logo:SetSize(38, 38)
    logo:SetPoint("TOPLEFT", 14, -9)
    logo:SetTexture(ns.LOGO)
    local title = Text(win, 18, C.text)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 5)
    title:SetText("SaltyM+Helper")
    local sub = Text(win, 11, C.dim)
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetText("Party cooldowns for Mythic+   v" .. ns.VERSION)
    local close = Button(win, "x", 26, 26, function() win:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -14)
    local headLine = win:CreateTexture(nil, "ARTWORK")
    headLine:SetPoint("TOPLEFT", 0, -HEAD_H)
    headLine:SetPoint("TOPRIGHT", 0, -HEAD_H)
    headLine:SetHeight(1)
    headLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    -- sidebar
    local side = CreateFrame("Frame", nil, win, "BackdropTemplate")
    side:SetPoint("TOPLEFT", 1, -HEAD_H - 1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE_W)
    Backdrop(side, C.side, C.side)
    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", 0, 0)
    sideScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetSize(SIDE_W, 700)
    sideScroll:SetScrollChild(sideChild)
    sideScroll:EnableMouseWheel(true)
    sideScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = max(0, (sideChild:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(min(maxScroll, max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
    end)
    local y = 10
    for _, t in ipairs(TABS) do
        local key, label = t[1], t[2]
        if t[3] then
            local b = Button(sideChild, label, SIDE_W - 24, 24, function() SelectTab(key) end)
            b:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 12, -y)
            tabButtons[key] = b
            y = y + 26
        else
            y = y + 6
            local h = Text(sideChild, 10, C.dim)
            h:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 14, -y)
            h:SetText(label)
            y = y + 16
        end
    end
    sideChild:SetHeight(y + 14)
    -- preview / move live in the header so the sidebar has room for every feature page
    win.move = Button(win, "Move frames", 110, 26, function() ns:SetEditMode(not ns.editMode) end)
    win.move:SetPoint("RIGHT", close, "LEFT", -8, 0)
    win.preview = Button(win, "Preview party", 110, 26, function() ns:SetPreview(not ns.preview) end)
    win.preview:SetPoint("RIGHT", win.move, "LEFT", -6, 0)
    -- small screens: shrink the window instead of letting it run off the bottom
    local fit = (UIParent:GetHeight() - 40) / WIN_H
    if fit < 0.75 then win:SetScale(max(0.6, fit)) end

    -- resizing: drag the grip in the bottom-right corner (size is remembered)
    win:SetResizable(true)
    local sc = win:GetScale() or 1
    local maxW = max(WIN_W, math.floor(UIParent:GetWidth() / sc) - 20)
    local maxH = max(WIN_H, math.floor(UIParent:GetHeight() / sc) - 20)
    if win.SetResizeBounds then win:SetResizeBounds(560, 380, maxW, maxH)
    elseif win.SetMinResize then win:SetMinResize(560, 380) end
    local sw, sh = ns.db and ns.db.winW, ns.db and ns.db.winH
    if type(sw) == "number" and type(sh) == "number" then
        win:SetSize(min(maxW, max(560, sw)), min(maxH, max(380, sh)))
    else
        win:SetHeight(min(WIN_H, math.floor((UIParent:GetHeight() - 40) / sc)))
    end
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(win:GetFrameLevel() + 20)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnEnter", function() gt:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
    grip:SetScript("OnLeave", function() gt:SetVertexColor(1, 1, 1, 1) end)
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        if ns.db then ns.db.winW, ns.db.winH = math.floor(win:GetWidth() + 0.5), math.floor(win:GetHeight() + 0.5) end
    end)

    -- content area
    win.content = CreateFrame("Frame", nil, win)
    win.content:SetPoint("TOPLEFT", win, "TOPLEFT", SIDE_W + 24, -HEAD_H - 16)
    win.content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -20, 22)

    win:SetScript("OnShow", function()
        ns:SetPreview(true)
        ns:SetEditMode(true)
        SelectTab(current or "welcome")
    end)
    win:SetScript("OnHide", function()
        ns:SetPreview(false)
        ns:SetEditMode(false)
        GameTooltip:Hide()
    end)

    -- refresh live status lines (sync list, attachments) once a second
    local acc = 0
    win:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 1 then
            acc = 0
            local page = current and pages[current]
            if page then
                for _, w in ipairs(page.rows) do
                    if w.tick and w.frame:IsShown() then w.Refresh() end
                end
                for _, w in ipairs(page.rows) do
                    if w.live and w.frame:IsShown() then w.Refresh() end
                end
            end
        end
    end)

    tinsert(UISpecialFrames, "SaltyMPlusHelperOptions") -- Esc closes it
end

-- Which settings page belongs to which movable frame (right-click in move mode).
local PAGE_FOR_FRAME = {
    PREVIEW = "layout", CCTRACK = "cc", CTEXT = "combattext", CTIMER = "combattimer", FKICK = "focuskick",
    DEATHS = "deaths", ALERTS = "alerts", MPHUD = "hud", ICONS = "icons", KICKS = "kickorder", KEYS = "partykeys",
}

function UI:OpenFor(frameKey)
    if not win then Create() end
    if not win:IsShown() then win:Show() end
    SelectTab(PAGE_FOR_FRAME[frameKey] or "layout") -- the party cooldown windows live on Layout
end

function UI:Toggle()
    if not win then Create() end
    if win:IsShown() then win:Hide() else win:Show() end
end

---------------------------------------------------------------------------
-- Game menu (Esc) button: the logo in the top-left corner opens these settings
---------------------------------------------------------------------------

local menuButton
local function UpdateMenuButton()
    local menu = _G.GameMenuFrame
    if not (menu and ns.db) then return end
    if not menuButton then
        menuButton = CreateFrame("Button", "SaltyMPlusHelperMenuButton", menu)
        menuButton:SetSize(32, 32)
        menuButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 14, -12)
        menuButton:SetFrameLevel(menu:GetFrameLevel() + 10)
        local tex = menuButton:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(ns.LOGO)
        menuButton.tex = tex
        local glow = menuButton:CreateTexture(nil, "HIGHLIGHT")
        glow:SetAllPoints()
        glow:SetTexture(ns.LOGO)
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0.4)
        menuButton:SetScript("OnClick", function()
            if not InCombatLockdown() then pcall(HideUIPanel, menu) end
            if not _G.SaltyMPlusHelperOptions or not _G.SaltyMPlusHelperOptions:IsShown() then UI:Toggle() end
        end)
        menuButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("SaltyM+Helper", 1, 1, 1)
            GameTooltip:AddLine("Click to open the settings", 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        menuButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    menuButton:SetShown(ns.db.menuButton ~= false)
end
UI.UpdateMenuButton = UpdateMenuButton

if _G.GameMenuFrame and _G.GameMenuFrame.HookScript then
    _G.GameMenuFrame:HookScript("OnShow", UpdateMenuButton)
end
