-- MDTLink.lua: optional link to the Mythic Dungeon Tools addon (MDT).
--   * Detects MDT by itself. Nothing here works without it, and the settings are greyed out then.
--   * Mob tooltips: adds "Forces +5 (1.2%)" for the mob you point at, using MDT's public
--     MythicDungeonToolsAPI. No MDT code or data is copied into this addon.
--   * Open MDT button / /salty mdt.
-- Also here (needs no MDT): the pull tracker, which measures how much enemy forces each pull gave,
-- from the game's own count after the fight (nothing is predicted while you fight).

local ADDON, ns = ...
local mp = ns.MP
local issecret = ns.issecret or issecretvalue or function() return false end
local format = string.format

local link = {}
mp.MDT = link

---------------------------------------------------------------------------
-- detection
---------------------------------------------------------------------------

function link.API()
    local api = _G.MythicDungeonToolsAPI
    if type(api) == "table" and type(api.GetEnemyForces) == "function" then return api end
end

function link.Available()
    return link.API() ~= nil
end

function link.Status()
    if link.Available() then return "MDT found" end
    return "MDT not installed"
end

function link.Open()
    local api = link.API()
    if not api then
        ns.Print("Mythic Dungeon Tools is not installed.")
        return false
    end
    local ok = type(api.ShowInterface) == "function" and pcall(api.ShowInterface, api)
    if not ok and SlashCmdList and SlashCmdList.MYTHICDUNGEONTOOLS then
        ok = pcall(SlashCmdList.MYTHICDUNGEONTOOLS, "")
    end
    return ok
end

---------------------------------------------------------------------------
-- mob forces
---------------------------------------------------------------------------

local cache = {}

-- count, total for an NPC id (nil when MDT does not know it)
function link.Forces(npcId)
    local api = link.API()
    if not api then return end
    local hit = cache[npcId]
    if hit ~= nil then
        if hit == false then return end
        return hit[1], hit[2]
    end
    local ok, count, total = pcall(api.GetEnemyForces, api, npcId)
    if ok and type(count) == "number" and not issecret(count) then
        cache[npcId] = { count, total }
        return count, total
    end
    -- do not cache a miss for long: MDT's data window may simply not be loaded yet
    cache[npcId] = nil
end

local function NpcIdFromGuid(guid)
    if type(guid) ~= "string" or issecret(guid) then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

local function OnTooltip(tooltip, data)
    local db = ns.db
    if not (db and db.mdtTooltip and db.mdtEnabled and not db.syncOnly and link.Available()) then return end
    if tooltip ~= GameTooltip then return end
    local ok = pcall(function()
        local guid = data and data.guid
        local id = NpcIdFromGuid(guid)
        if not id then return end
        local count, total = link.Forces(id)
        if not count then return end
        -- prefer the real total of the key you are in, fall back to MDT's own total
        local run = mp.run
        local base = (run and run.ft and run.ft > 1) and run.ft or total
        if count <= 0 then
            tooltip:AddLine("Enemy forces: none", 0.6, 0.6, 0.7)
        elseif base and base > 0 then
            tooltip:AddLine(format("Enemy forces: +%d  (%.2f%%)", count, count / base * 100), 0.55, 0.45, 1)
        else
            tooltip:AddLine(format("Enemy forces: +%d", count), 0.55, 0.45, 1)
        end
    end)
    return ok
end

local function HookTooltip()
    if link.hooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        link.hooked = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, OnTooltip)
    end
end

---------------------------------------------------------------------------
-- pull tracker: forces gained per pull, from the game's own count (no MDT)
---------------------------------------------------------------------------

local pull = { start = nil, last = nil, total = 0 }
mp.pull = pull

local function Forces()
    local run = mp.run
    return run and run.active and run.forces or nil
end

local function PullStart()
    if not (ns.db and ns.db.mpLastPull) then return end
    local f = Forces()
    if f then pull.start = f end
end

local function PullEnd()
    if not (ns.db and ns.db.mpLastPull) or not pull.start then return end
    local startVal = pull.start
    pull.start = nil
    -- the count settles a moment after the mobs die
    C_Timer.After(3, function()
        local f = Forces()
        if f and f >= startVal then
            local gain = f - startVal
            if gain > 0.05 then
                pull.last = gain
                pull.total = pull.total + gain
                pull.n = (pull.n or 0) + 1
            end
        end
    end)
end

function mp:PullText()
    if not (ns.db and ns.db.mpLastPull) then return nil end
    if pull.last then return format("last pull +%.1f%%", pull.last) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("CHALLENGE_MODE_START")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if not ns.db or ns.db.syncOnly then return end
    if event == "PLAYER_REGEN_DISABLED" then
        PullStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        PullEnd()
    elseif event == "CHALLENGE_MODE_START" then
        pull.start, pull.last, pull.total, pull.n = nil, nil, 0, 0
    else
        HookTooltip()
    end
end)
HookTooltip()
