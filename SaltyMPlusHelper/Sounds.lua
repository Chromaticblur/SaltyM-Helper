-- Sounds.lua: sound alerts that use any sound registered with LibSharedMedia, which is where
-- BigWigs, the Causese pack, SharedMedia_SaltyM and most other sound packs put theirs.
-- Nothing is copied from those addons; the sounds are only looked up by name when needed.

local ADDON, ns = ...
local snd = {}
ns.Snd = snd

local function LSM()
    local stub = _G.LibStub
    return stub and stub("LibSharedMedia-3.0", true) or nil
end

-- Pack names carry colour codes (for example the Causese numbers); strip them for display.
function snd.Clean(name)
    if type(name) ~= "string" then return "" end
    return (name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Sounds that are already inside the game (nothing is copied or downloaded). Each is looked up
-- by its SOUNDKIT name at run time, and only offered when this game version has it.
snd.GAME = {
    { "Ready Check", "READY_CHECK" }, { "Raid Warning", "RAID_WARNING" },
    { "Boss Whisper Warning", "UI_RAID_BOSS_WHISPER_WARNING" }, { "Alarm Clock 1", "ALARM_CLOCK_WARNING_1" },
    { "Alarm Clock 2", "ALARM_CLOCK_WARNING_2" }, { "Alarm Clock 3", "ALARM_CLOCK_WARNING_3" },
    { "Quest Complete", "IG_QUEST_LIST_COMPLETE" }, { "Map Ping", "MAP_PING" },
    { "Whisper Received", "TELL_MESSAGE" }, { "Group Invite", "IG_PLAYER_INVITE" },
    { "Countdown Finished", "UI_BATTLEGROUND_COUNTDOWN_FINISHED" }, { "Loot Roll End", "UI_BONUS_LOOT_ROLL_END" },
    { "Epic Loot Toast", "UI_EPICLOOT_TOAST" }, { "Auction Window Open", "AUCTION_WINDOW_OPEN" },
    { "Level Up", "LEVELUP" }, { "Achievement", "ACHIEVEMENT_MENU_OPEN" }, { "Raid Boss Emote Warning", "RAID_BOSS_EMOTE_WARNING" },
    { "PvP Queue Pop", "PVP_THROUGH_QUEUE" }, { "Queue Ready (LFG)", "LFG_ROLE_CHECK" }, { "Dungeon Reward", "LFG_REWARDS" },
    { "Raid Target Skull", "RAID_TARGET_8" } -- the last one may not exist; missing ones are skipped
}
local GAME_PREFIX = "WoW: "
local gameKits

local function GameKits()
    if gameKits then return gameKits end
    local kits = _G.SOUNDKIT
    if type(kits) ~= "table" then return {} end
    gameKits = {}
    for _, e in ipairs(snd.GAME) do
        local id = kits[e[2]]
        if type(id) == "number" then gameKits[GAME_PREFIX .. e[1]] = id end
    end
    return gameKits
end

function snd.ResetGameSounds() gameKits = nil end

function snd.GameCount()
    local n = 0
    for _ in pairs(GameKits()) do n = n + 1 end
    return n
end

-- every registered sound name, sorted by its clean name
function snd.List()
    local lsm = LSM()
    local out = {}
    if lsm and lsm.List then
        for _, name in ipairs(lsm:List("sound") or {}) do out[#out + 1] = name end
    end
    for name in pairs(GameKits()) do out[#out + 1] = name end
    table.sort(out, function(a, b) return snd.Clean(a):lower() < snd.Clean(b):lower() end)
    return out
end

function snd.Path(name)
    if GameKits()[name] then return nil end
    local lsm = LSM()
    if not (lsm and name and name ~= "") then return nil end
    local ok, path = pcall(lsm.Fetch, lsm, "sound", name, true)
    if ok and path then return path end
end

function snd.Play(name)
    if type(name) == "string" and name:sub(1, 1) == "@" then
        local d = snd.DEFAULTS[name:sub(2)]
        local id = d and _G.SOUNDKIT and _G.SOUNDKIT[d[2]]
        if id then return pcall(PlaySound, id, "Master") end
        return false
    end
    local kit = GameKits()[name]
    if kit then return pcall(PlaySound, kit, "Master") end
    local path = snd.Path(name)
    if not path then return false end
    local ok = pcall(PlaySoundFile, path, "Master")
    return ok
end

-- What is installed, for the settings page.
function snd.Summary()
    local lsm = LSM()
    if not lsm then return string.format("LibSharedMedia not found. WoW built-in sounds: %d", snd.GameCount()) end
    local total, bw, cs = 0, 0, 0
    for _, name in ipairs(lsm:List("sound") or {}) do
        total = total + 1
        local clean = snd.Clean(name):lower()
        if clean:find("^bigwigs") then bw = bw + 1 end
        local path = snd.Path(name)
        if path and tostring(path):lower():find("causese", 1, true) then cs = cs + 1 end
    end
    return string.format("%d sounds found  (BigWigs: %d, Causese: %d, WoW built-in: %d)", total + snd.GameCount(), bw, cs, snd.GameCount())
end

-- Sound pack check: is SharedMedia_SaltyM installed, loaded, and registering what it should?
snd.PACK = "SharedMedia_SaltyM"
snd.EXPECT = { saltym = 7, causese = 182 }

local function AddOnState(name)
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    local ok, info = pcall(getInfo, name)
    -- current clients return a table, older ones the name as a string
    local exists = ok and ((type(info) == "table" and info.name ~= nil) or type(info) == "string")
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    local loaded = isLoaded and isLoaded(name) and true or false
    local meta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = meta and meta(name, "Version") or nil
    return exists, loaded, version
end

-- list of { label, text, level } with level = "good" | "warn" | "bad"
function snd.Check(noPlay)
    local out = {}
    local function add(label, text, level) out[#out + 1] = { label = label, text = text, level = level } end
    local exists, loaded, version = AddOnState(snd.PACK)
    if not exists then
        add("Media addon", "not installed (put the SharedMedia_SaltyM folder in Interface/AddOns)", "bad")
    elseif not loaded then
        add("Media addon", "installed but not loaded (enable it on the AddOns list, then /reload)", "bad")
    else
        add("Media addon", "loaded" .. (version and ("  v" .. version) or ""), "good")
    end
    local lsm = LSM()
    if not lsm then
        add("LibSharedMedia", "not found", "bad")
        return out
    end
    add("LibSharedMedia", "found", "good")
    local nSalty, nCause, hasLogo = 0, 0, false
    for _, name in ipairs(lsm:List("sound") or {}) do
        local clean = snd.Clean(name)
        if clean:find("^SaltyM ") then nSalty = nSalty + 1 end
        if clean:find("^Causese: ") then nCause = nCause + 1 end
    end
    for _, name in ipairs(lsm:List("background") or {}) do
        if name == "SaltyM Logo" then hasLogo = true end
    end
    add("SaltyM sounds", format("%d of %d registered", nSalty, snd.EXPECT.saltym),
        nSalty >= snd.EXPECT.saltym and "good" or (nSalty > 0 and "warn" or "bad"))
    add("Causese sounds", format("%d of %d registered", nCause, snd.EXPECT.causese),
        nCause >= snd.EXPECT.causese and "good" or (nCause > 0 and "warn" or "bad"))
    add("SaltyM logo image", hasLogo and "registered" or "missing", hasLogo and "good" or "warn")
    -- can the game actually open a sound file? (plays a short quiet-ish ping)
    local path = snd.Path("SaltyM Test (quiet)") or snd.Path("SaltyM Ping")
    if noPlay then
        add("Sound file test", "press Check now to play a test sound", "warn")
    elseif not path then
        add("Sound file test", "skipped (SaltyM test sound is not registered)", "warn")
    else
        local ok, willPlay = pcall(PlaySoundFile, path, "Master")
        if ok and willPlay ~= false then
            add("Sound file test", "played a soft test beep", "good")
        else
            add("Sound file test", "the game could not play the file (missing or damaged)", "bad")
        end
    end
    -- the old pack still installed is harmless, but worth knowing
    local oldExists, oldLoaded = AddOnState("SharedMedia_Causese")
    if oldExists and oldLoaded then
        add("Old Causese addon", "also loaded (names differ, nothing breaks, but you can remove it)", "warn")
    end
    return out
end

-- Events that can play a chosen sound. key: setting prefix. "On" key gates it (nil = always).
snd.EVENTS = {
    { "KeyStart", "Key starts", "sndKeyStartOn" },
    { "KeyDone", "Key finished", "sndKeyDoneOn" },
}

-- Built-in game sounds that can be chosen as "defaults" (stored as "@KEY").
snd.DEFAULTS = {
    RAID_WARNING = { "Raid warning", "RAID_WARNING" },
    READY_CHECK = { "Ready check", "READY_CHECK" },
    BOSS_WHISPER = { "Boss whisper", "UI_RAID_BOSS_WHISPER_WARNING" },
}

function snd.DefaultLabel(name)
    local d = type(name) == "string" and name:sub(1, 1) == "@" and snd.DEFAULTS[name:sub(2)]
    return d and ("Default: " .. d[1]) or nil
end

-- Plays the sound chosen for an event. Returns true when it played one, so callers can fall
-- back to the game's built-in sound when the choice is "Default".
function snd.Alert(event)
    local db = ns.db
    if not db or db.syncOnly or not db.sndEnabled then return false end
    local name = db["snd" .. event]
    if type(name) ~= "string" or name == "" then return false end
    return snd.Play(name)
end
