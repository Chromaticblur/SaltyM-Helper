-- Profiles.lua: export your settings as a text string, import someone else's, or reset.
-- The string is a small self-describing format (not Lua code), so importing one can never run
-- anything: it is parsed, checked against the known settings, and only matching values are used.

local ADDON, ns = ...

local PREFIX = "SMH1:"
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, #B64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

---------------------------------------------------------------------------
-- serialize / parse
---------------------------------------------------------------------------

local function Serialize(v, out, depth)
    if depth > 8 then return end
    local t = type(v)
    if t == "number" then
        out[#out + 1] = "n" .. format("%.10g", v) .. ";"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        out[#out + 1] = "{"
        local keys = {}
        for k in pairs(v) do
            if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
        end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local value = v[k]
            local vt = type(value)
            if vt == "number" or vt == "string" or vt == "boolean" or vt == "table" then
                Serialize(k, out, depth + 1)
                Serialize(value, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    end
end

local function Parse(str, pos, depth)
    if depth > 8 then error("nested too deeply") end
    local c = str:sub(pos, pos)
    if c == "n" then
        local e = str:find(";", pos, true)
        local num = e and tonumber(str:sub(pos + 1, e - 1))
        if not num then error("bad number") end
        return num, e + 1
    elseif c == "s" then
        local colon = str:find(":", pos, true)
        local len = colon and tonumber(str:sub(pos + 1, colon - 1))
        if not len or len < 0 or len > 20000 then error("bad string") end
        local value = str:sub(colon + 1, colon + len)
        if #value ~= len then error("short string") end
        return value, colon + len + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        local t = {}
        pos = pos + 1
        local count = 0
        while str:sub(pos, pos) ~= "}" do
            if pos > #str then error("unterminated table") end
            count = count + 1
            if count > 2000 then error("too many entries") end
            local k, v
            k, pos = Parse(str, pos, depth + 1)
            if type(k) ~= "string" and type(k) ~= "number" then error("bad key") end
            v, pos = Parse(str, pos, depth + 1)
            t[k] = v
        end
        return t, pos + 1
    end
    error("unexpected data")
end

local function Base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Base64Decode(text)
    text = text:gsub("%s", "")
    if #text % 4 ~= 0 then error("bad length") end
    local out = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local v = {}
        local pad = 0
        for j = 1, 4 do
            local ch = chunk:sub(j, j)
            if ch == "=" then
                pad = pad + 1
                v[j] = 0
            else
                local idx = B64_INDEX[ch]
                if not idx or pad > 0 then error("bad character") end
                v[j] = idx
            end
        end
        local n = ((v[1] * 64 + v[2]) * 64 + v[3]) * 64 + v[4]
        local bytes = string.char(floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- export / import
---------------------------------------------------------------------------

function ns:ExportProfile()
    local out = {}
    Serialize({ v = 1, db = ns.db }, out, 0)
    return PREFIX .. Base64Encode(table.concat(out))
end

local function CopySimple(v)
    local t = type(v)
    if t == "number" or t == "string" or t == "boolean" then return v end
    return nil
end

-- Returns true, "message" or false, "reason". Only settings we know are applied.
function ns:ImportProfile(text)
    if type(text) ~= "string" then return false, "Nothing to import." end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return false, "That is not a SaltyM+Helper profile string." end
    local ok, data = pcall(function()
        local raw = Base64Decode(text:sub(#PREFIX + 1))
        local value, pos = Parse(raw, 1, 0)
        if pos <= #raw then error("trailing data") end
        return value
    end)
    if not ok or type(data) ~= "table" or data.v ~= 1 or type(data.db) ~= "table" then
        return false, "The profile string is damaged or from a different version."
    end
    local db, src = ns.db, data.db
    local applied = 0
    for key, default in pairs(ns.DEFAULTS) do
        local value = CopySimple(src[key])
        if value ~= nil and type(value) == type(default) then
            if type(default) == "number" then
                -- keep numbers sane: no NaN/inf, within a generous range
                if value == value and value > -1e6 and value < 1e6 then db[key] = value; applied = applied + 1 end
            else
                db[key] = value
                applied = applied + 1
            end
        end
    end
    if type(src.categories) == "table" then
        for _, cat in ipairs(ns.CATEGORIES) do
            if type(src.categories[cat]) == "boolean" then db.categories[cat] = src.categories[cat] end
        end
    end
    if type(src.disabled) == "table" then
        wipe(db.disabled)
        for id, v in pairs(src.disabled) do
            if type(id) == "number" and v == true and ns.SPELLS[id] then db.disabled[id] = true end
        end
    end
    if type(src.pos) == "table" then
        wipe(db.pos)
        for key, p in pairs(src.pos) do
            if type(key) == "string" and type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
                db.pos[key] = { p[1], p[2] }
            end
        end
    end
    ns:ApplyAllPositions()
    ns:ClearFrameCache()
    if next(ns.euiRegistered) then ns:RegisterEllesmere() end
    ns:Refresh()
    ns:Notify()
    return true, format("Imported %d settings.", applied)
end

-- Back to the defaults (keeps what the game learned about your own cooldown lengths).
function ns:ResetProfile()
    local db = ns.db
    for key, default in pairs(ns.DEFAULTS) do db[key] = default end
    wipe(db.pos)
    wipe(db.disabled)
    for _, cat in ipairs(ns.CATEGORIES) do db.categories[cat] = true end
    ns:ApplyAllPositions()
    ns:ClearFrameCache()
    ns:Refresh()
    ns:Notify()
end
