-- Spells.lua: what SaltyM+Helper knows how to track.
--
-- Each entry:  add(class, category, spellID, baseCooldown, options)
--   category: INT interrupt, CC stuns & crowd control, BREZ battle res, BL bloodlust,
--             EXT external / raid cooldown, DEF personal defensive, OFF offensive, UTIL utility
--   options : specs   = { specID, ... }  only these specializations have it (nil = all)
--             cds     = { [specID] = seconds }  per-spec cooldown override
--             talent  = true  talent-dependent: for people without the addon it only shows up
--                             after we have seen them cast it
--             faction = "Horde" / "Alliance"
--
-- Interrupts were cross-checked against current Midnight sources (healers lost their
-- interrupts except Restoration Shaman, whose Wind Shear is 30s). Everything else is the
-- best known value from recent patches: your own cooldowns are read from the game and
-- learned automatically, and people running the addon share theirs, so a wrong base value
-- only affects players who do not run the addon. Edit freely.

local ADDON, ns = ...

local S = {}
ns.SPELLS = S
ns.CLASS_SPELLS = {}

local function add(class, cat, id, cd, o)
    local def = { class = class, cat = cat, cd = cd }
    if o then
        def.specs, def.cds, def.talent, def.faction = o.specs, o.cds, o.talent, o.faction
    end
    S[id] = def
    local list = ns.CLASS_SPELLS[class]
    if not list then
        list = {}
        ns.CLASS_SPELLS[class] = list
    end
    list[#list + 1] = id
end

-- specialization IDs
local BLOOD, FROST_DK, UNHOLY = 250, 251, 252
local HAVOC, VENGEANCE = 577, 581
local BALANCE, FERAL, GUARDIAN, RESTO_DRUID = 102, 103, 104, 105
local DEVASTATION, PRESERVATION, AUGMENTATION = 1467, 1468, 1473
local BM, MM, SV = 253, 254, 255
local ARCANE, FIRE, FROST_MAGE = 62, 63, 64
local BREWMASTER, MISTWEAVER, WINDWALKER = 268, 270, 269
local HOLY_PALADIN, PROT_PALADIN, RET = 65, 66, 70
local DISC, HOLY_PRIEST, SHADOW = 256, 257, 258
local ASSASSINATION, OUTLAW, SUBTLETY = 259, 260, 261
local ELEMENTAL, ENHANCEMENT, RESTO_SHAMAN = 262, 263, 264
local AFFLICTION, DEMONOLOGY, DESTRUCTION = 265, 266, 267
local ARMS, FURY, PROT_WARRIOR = 71, 72, 73

-------------------------------------------------------------------- DEATH KNIGHT
local C = "DEATHKNIGHT"
add(C, "INT", 47528, 15)                                   -- Mind Freeze
add(C, "CC", 221562, 45, { specs = { BLOOD } })            -- Asphyxiate
add(C, "CC", 108194, 45, { specs = { FROST_DK, UNHOLY } }) -- Asphyxiate
add(C, "CC", 207167, 60, { talent = true })                -- Blinding Sleet
add(C, "BREZ", 61999, 600)                                 -- Raise Ally
add(C, "EXT", 51052, 240, { talent = true })               -- Anti-Magic Zone
add(C, "DEF", 48707, 60)                                   -- Anti-Magic Shell
add(C, "DEF", 48792, 120)                                  -- Icebound Fortitude
add(C, "DEF", 49039, 120, { talent = true })               -- Lichborne
add(C, "DEF", 55233, 90, { specs = { BLOOD } })            -- Vampiric Blood
add(C, "DEF", 48743, 120, { talent = true })               -- Death Pact
add(C, "OFF", 49028, 120, { specs = { BLOOD } })           -- Dancing Rune Weapon
add(C, "OFF", 51271, 45, { specs = { FROST_DK } })         -- Pillar of Frost
add(C, "OFF", 47568, 120, { specs = { FROST_DK, UNHOLY } }) -- Empower Rune Weapon
add(C, "OFF", 152279, 120, { specs = { FROST_DK }, talent = true }) -- Breath of Sindragosa
add(C, "OFF", 279302, 90, { specs = { FROST_DK }, talent = true })  -- Frostwyrm's Fury
add(C, "OFF", 63560, 45, { specs = { UNHOLY } })           -- Dark Transformation
add(C, "OFF", 42650, 90, { specs = { UNHOLY } })           -- Army of the Dead
add(C, "OFF", 49206, 180, { specs = { UNHOLY }, talent = true })    -- Summon Gargoyle
add(C, "OFF", 207289, 90, { specs = { UNHOLY }, talent = true })    -- Unholy Assault
add(C, "UTIL", 49576, 25)                                  -- Death Grip

-------------------------------------------------------------------- DEMON HUNTER
C = "DEMONHUNTER"
add(C, "INT", 183752, 15)                                  -- Disrupt
add(C, "CC", 179057, 45)                                   -- Chaos Nova
add(C, "CC", 211881, 30, { talent = true })                -- Fel Eruption
add(C, "CC", 217832, 45)                                   -- Imprison
add(C, "EXT", 196718, 300, { specs = { HAVOC } })          -- Darkness
add(C, "DEF", 198589, 60, { specs = { HAVOC } })           -- Blur
add(C, "DEF", 187827, 180, { specs = { VENGEANCE } })      -- Metamorphosis
add(C, "DEF", 204021, 60, { specs = { VENGEANCE } })       -- Fiery Brand
add(C, "DEF", 196555, 180, { talent = true })              -- Netherwalk
add(C, "OFF", 191427, 120, { specs = { HAVOC } })          -- Metamorphosis
add(C, "OFF", 370965, 90, { talent = true })               -- The Hunt

-------------------------------------------------------------------- DRUID
C = "DRUID"
add(C, "INT", 106839, 15, { specs = { FERAL, GUARDIAN } }) -- Skull Bash
add(C, "INT", 78675, 60, { specs = { BALANCE } })          -- Solar Beam
add(C, "CC", 5211, 60, { talent = true })                  -- Mighty Bash
add(C, "CC", 99, 30, { talent = true })                    -- Incapacitating Roar
add(C, "CC", 102359, 30, { talent = true })                -- Mass Entanglement
add(C, "CC", 132469, 30, { talent = true })                -- Typhoon
add(C, "CC", 22570, 20, { specs = { FERAL } })             -- Maim
add(C, "BREZ", 20484, 600)                                 -- Rebirth
add(C, "EXT", 102342, 90, { specs = { RESTO_DRUID } })     -- Ironbark
add(C, "EXT", 740, 180, { specs = { RESTO_DRUID } })       -- Tranquility
add(C, "EXT", 197721, 90, { specs = { RESTO_DRUID }, talent = true }) -- Flourish
add(C, "DEF", 22812, 60)                                   -- Barkskin
add(C, "DEF", 61336, 180, { specs = { FERAL, GUARDIAN } }) -- Survival Instincts
add(C, "DEF", 204066, 60, { specs = { GUARDIAN }, talent = true }) -- Lunar Beam
add(C, "DEF", 108238, 90, { talent = true })               -- Renewal
add(C, "OFF", 194223, 180, { specs = { BALANCE } })        -- Celestial Alignment
add(C, "OFF", 102560, 180, { specs = { BALANCE }, talent = true })  -- Incarnation: Chosen of Elune
add(C, "OFF", 106951, 180, { specs = { FERAL } })          -- Berserk
add(C, "OFF", 102543, 180, { specs = { FERAL }, talent = true })    -- Incarnation: Avatar of Ashamane
add(C, "OFF", 50334, 150, { specs = { GUARDIAN } })        -- Berserk
add(C, "OFF", 102558, 180, { specs = { GUARDIAN }, talent = true }) -- Incarnation: Guardian of Ursoc
add(C, "OFF", 391528, 120, { talent = true })              -- Convoke the Spirits
add(C, "UTIL", 106898, 120)                                -- Stampeding Roar
add(C, "UTIL", 29166, 180)                                 -- Innervate

-------------------------------------------------------------------- EVOKER
C = "EVOKER"
add(C, "INT", 351338, 20, { specs = { DEVASTATION, AUGMENTATION } }) -- Quell
add(C, "CC", 357214, 90, { talent = true })                -- Wing Buffet
add(C, "CC", 358385, 90, { talent = true })                -- Landslide
add(C, "CC", 360806, 15, { talent = true })                -- Sleep Walk
add(C, "BL", 390386, 300)                                  -- Fury of the Aspects
add(C, "EXT", 363534, 240, { specs = { PRESERVATION }, talent = true }) -- Rewind
add(C, "EXT", 357170, 60, { specs = { PRESERVATION } })    -- Time Dilation
add(C, "EXT", 370537, 90, { specs = { PRESERVATION }, talent = true })  -- Stasis
add(C, "EXT", 359816, 120, { specs = { PRESERVATION }, talent = true }) -- Dream Flight
add(C, "EXT", 374227, 120, { talent = true })              -- Zephyr
add(C, "DEF", 363916, 90)                                  -- Obsidian Scales
add(C, "DEF", 374348, 90, { talent = true })               -- Renewing Blaze
add(C, "OFF", 375087, 120, { specs = { DEVASTATION } })    -- Dragonrage
add(C, "OFF", 357210, 120, { specs = { DEVASTATION } })    -- Deep Breath
add(C, "OFF", 403631, 120, { specs = { AUGMENTATION } })   -- Breath of Eons
add(C, "OFF", 404977, 180, { specs = { AUGMENTATION }, talent = true }) -- Time Skip
add(C, "UTIL", 372048, 120, { talent = true })             -- Oppressing Roar
add(C, "UTIL", 374968, 120, { talent = true })             -- Time Spiral

-------------------------------------------------------------------- HUNTER
C = "HUNTER"
add(C, "INT", 147362, 24, { specs = { BM, MM } })          -- Counter Shot
add(C, "INT", 187707, 15, { specs = { SV } })              -- Muzzle
add(C, "CC", 187650, 30)                                   -- Freezing Trap
add(C, "CC", 109248, 45, { talent = true })                -- Binding Shot
add(C, "CC", 19577, 60, { specs = { BM }, talent = true }) -- Intimidation
add(C, "BL", 264667, 300, { talent = true })               -- Primal Rage (ferocity pet)
add(C, "DEF", 186265, 180)                                 -- Aspect of the Turtle
add(C, "DEF", 109304, 120)                                 -- Exhilaration
add(C, "DEF", 264735, 90, { talent = true })               -- Survival of the Fittest
add(C, "OFF", 19574, 90, { specs = { BM } })               -- Bestial Wrath
add(C, "OFF", 359844, 120, { specs = { BM }, talent = true }) -- Call of the Wild
add(C, "OFF", 288613, 120, { specs = { MM } })             -- Trueshot
add(C, "OFF", 1250646, 90, { specs = { SV } })             -- Survival major cooldown (replaces Coordinated Assault)
add(C, "UTIL", 34477, 30)                                  -- Misdirection
add(C, "UTIL", 5384, 30)                                   -- Feign Death

-------------------------------------------------------------------- MAGE
C = "MAGE"
add(C, "INT", 2139, 25)                                    -- Counterspell
add(C, "CC", 113724, 45, { talent = true })                -- Ring of Frost
add(C, "CC", 31661, 45, { specs = { FIRE }, talent = true }) -- Dragon's Breath
add(C, "CC", 122, 30)                                      -- Frost Nova
add(C, "BL", 80353, 300)                                   -- Time Warp
add(C, "DEF", 45438, 240)                                  -- Ice Block
add(C, "DEF", 414658, 240, { specs = { FROST_MAGE }, talent = true }) -- Ice Cold
add(C, "DEF", 55342, 120, { talent = true })               -- Mirror Image
add(C, "DEF", 342245, 60, { talent = true })               -- Alter Time
add(C, "DEF", 110959, 120, { talent = true })              -- Greater Invisibility
add(C, "DEF", 66, 300, { talent = true })                  -- Invisibility
add(C, "OFF", 365350, 90, { specs = { ARCANE } })          -- Arcane Surge
add(C, "OFF", 321507, 45, { specs = { ARCANE }, talent = true }) -- Touch of the Magi
add(C, "OFF", 190319, 120, { specs = { FIRE } })           -- Combustion
add(C, "OFF", 12472, 180, { specs = { FROST_MAGE } })      -- Icy Veins
add(C, "OFF", 84714, 60, { specs = { FROST_MAGE }, talent = true }) -- Frozen Orb

-------------------------------------------------------------------- MONK
C = "MONK"
add(C, "INT", 116705, 15, { specs = { BREWMASTER, WINDWALKER } }) -- Spear Hand Strike
add(C, "CC", 115078, 45)                                   -- Paralysis
add(C, "CC", 119381, 60, { talent = true })                -- Leg Sweep
add(C, "CC", 116844, 45, { talent = true })                -- Ring of Peace
add(C, "UTIL", 116841, 30, { talent = true })              -- Tiger's Lust
add(C, "EXT", 116849, 120, { specs = { MISTWEAVER } })     -- Life Cocoon
add(C, "EXT", 115310, 180, { specs = { MISTWEAVER } })     -- Revival
add(C, "EXT", 388615, 180, { specs = { MISTWEAVER }, talent = true }) -- Restoral
add(C, "DEF", 115203, 360, { cds = { [WINDWALKER] = 120, [MISTWEAVER] = 120 } }) -- Fortifying Brew
add(C, "DEF", 122278, 120, { talent = true })              -- Dampen Harm
add(C, "DEF", 122783, 90, { talent = true })               -- Diffuse Magic
add(C, "DEF", 115176, 300, { specs = { BREWMASTER } })     -- Zen Meditation
add(C, "DEF", 122470, 90, { specs = { WINDWALKER } })       -- Touch of Karma
add(C, "OFF", 137639, 90, { specs = { WINDWALKER } })      -- Storm, Earth, and Fire
add(C, "OFF", 132578, 120, { specs = { BREWMASTER } })      -- Invoke Niuzao, the Black Ox
add(C, "OFF", 123904, 120, { specs = { WINDWALKER }, talent = true }) -- Invoke Xuen
add(C, "OFF", 152173, 90, { specs = { WINDWALKER }, talent = true })  -- Serenity
add(C, "OFF", 322118, 120, { specs = { MISTWEAVER }, talent = true }) -- Invoke Yu'lon
add(C, "OFF", 325197, 120, { specs = { MISTWEAVER }, talent = true }) -- Invoke Chi-Ji

-------------------------------------------------------------------- PALADIN
C = "PALADIN"
add(C, "INT", 96231, 15, { specs = { PROT_PALADIN, RET } }) -- Rebuke
add(C, "INT", 31935, 15, { specs = { PROT_PALADIN } })     -- Avenger's Shield
add(C, "CC", 853, 60)                                      -- Hammer of Justice
add(C, "CC", 115750, 90, { talent = true })                -- Blinding Light
add(C, "CC", 20066, 15, { talent = true })                 -- Repentance
add(C, "BREZ", 391054, 600, { talent = true })             -- Intercession
add(C, "EXT", 6940, 120)                                   -- Blessing of Sacrifice
add(C, "EXT", 1022, 300)                                   -- Blessing of Protection
add(C, "EXT", 633, 600)                                    -- Lay on Hands
add(C, "EXT", 31821, 180, { specs = { HOLY_PALADIN } })    -- Aura Mastery
add(C, "DEF", 642, 300)                                    -- Divine Shield
add(C, "DEF", 498, 60, { specs = { HOLY_PALADIN, RET } })  -- Divine Protection
add(C, "DEF", 86659, 300, { specs = { PROT_PALADIN } })    -- Guardian of Ancient Kings
add(C, "DEF", 31850, 90, { specs = { PROT_PALADIN } })     -- Ardent Defender
add(C, "DEF", 184662, 90, { specs = { RET } })             -- Shield of Vengeance
add(C, "DEF", 204018, 300, { talent = true })              -- Blessing of Spellwarding
add(C, "OFF", 31884, 120, { cds = { [RET] = 60 } })        -- Avenging Wrath (60s for Retribution)
add(C, "OFF", 231895, 120, { specs = { RET }, talent = true })      -- Crusade
add(C, "OFF", 255937, 30, { specs = { RET }, talent = true })       -- Wake of Ashes
add(C, "OFF", 343527, 60, { specs = { RET }, talent = true })       -- Execution Sentence
add(C, "OFF", 105809, 180, { talent = true })              -- Holy Avenger
add(C, "OFF", 375576, 60, { talent = true })               -- Divine Toll
add(C, "UTIL", 1044, 25)                                   -- Blessing of Freedom

-------------------------------------------------------------------- PRIEST
C = "PRIEST"
add(C, "INT", 15487, 30, { specs = { SHADOW } })           -- Silence
add(C, "CC", 8122, 45)                                     -- Psychic Scream
add(C, "CC", 64044, 45, { specs = { SHADOW }, talent = true }) -- Psychic Horror
add(C, "EXT", 33206, 180, { specs = { DISC } })            -- Pain Suppression
add(C, "EXT", 47788, 180, { specs = { HOLY_PRIEST } })     -- Guardian Spirit
add(C, "EXT", 62618, 180, { specs = { DISC } })            -- Power Word: Barrier
add(C, "EXT", 64843, 180, { specs = { HOLY_PRIEST } })     -- Divine Hymn
add(C, "EXT", 64901, 180, { specs = { HOLY_PRIEST }, talent = true }) -- Symbol of Hope
add(C, "EXT", 265202, 720, { specs = { HOLY_PRIEST }, talent = true }) -- Holy Word: Salvation
add(C, "DEF", 19236, 90)                                   -- Desperate Prayer
add(C, "DEF", 47585, 120, { specs = { SHADOW } })          -- Dispersion
add(C, "DEF", 15286, 120, { specs = { SHADOW } })          -- Vampiric Embrace
add(C, "OFF", 10060, 120, { talent = true })               -- Power Infusion
add(C, "OFF", 228260, 120, { specs = { SHADOW } })         -- Void Eruption
add(C, "OFF", 391109, 60, { specs = { SHADOW }, talent = true })    -- Dark Ascension
add(C, "OFF", 200174, 60, { specs = { DISC, SHADOW }, talent = true }) -- Mindbender
add(C, "OFF", 472433, 90, { specs = { DISC }, talent = true })      -- Evangelism
add(C, "OFF", 421453, 240, { specs = { DISC }, talent = true })     -- Ultimate Penitence
add(C, "OFF", 200183, 120, { specs = { HOLY_PRIEST }, talent = true }) -- Apotheosis
add(C, "UTIL", 32375, 120)                                 -- Mass Dispel
add(C, "UTIL", 73325, 90)                                  -- Leap of Faith

-------------------------------------------------------------------- ROGUE
C = "ROGUE"
add(C, "INT", 1766, 15)                                    -- Kick
add(C, "CC", 408, 20)                                      -- Kidney Shot
add(C, "CC", 2094, 120)                                    -- Blind
add(C, "CC", 1776, 25, { specs = { OUTLAW } })             -- Gouge
add(C, "DEF", 5277, 120)                                   -- Evasion
add(C, "DEF", 31224, 120)                                  -- Cloak of Shadows
add(C, "DEF", 1856, 120)                                   -- Vanish
add(C, "DEF", 185311, 30)                                  -- Crimson Vial
add(C, "OFF", 360194, 120, { specs = { ASSASSINATION }, talent = true }) -- Deathmark
add(C, "OFF", 385627, 60, { specs = { ASSASSINATION }, talent = true })  -- Kingsbane
add(C, "OFF", 121471, 90, { specs = { SUBTLETY } })        -- Shadow Blades
add(C, "OFF", 13750, 180, { specs = { OUTLAW } })          -- Adrenaline Rush
add(C, "OFF", 51690, 90, { specs = { OUTLAW }, talent = true })     -- Killing Spree
add(C, "OFF", 382245, 45, { talent = true })               -- Cold Blood
add(C, "UTIL", 114018, 360)                                -- Shroud of Concealment
add(C, "UTIL", 2983, 120)                                  -- Sprint

-------------------------------------------------------------------- SHAMAN
C = "SHAMAN"
add(C, "INT", 57994, 12, { cds = { [RESTO_SHAMAN] = 30 } }) -- Wind Shear (30s for Restoration)
add(C, "CC", 192058, 60)                                   -- Capacitor Totem
add(C, "CC", 51490, 30, { specs = { ELEMENTAL } })         -- Thunderstorm
add(C, "CC", 197214, 40, { specs = { ENHANCEMENT }, talent = true }) -- Sundering
add(C, "CC", 51514, 30)                                    -- Hex
add(C, "BL", 2825, 300, { faction = "Horde" })             -- Bloodlust
add(C, "BL", 32182, 300, { faction = "Alliance" })         -- Heroism
add(C, "EXT", 98008, 180, { specs = { RESTO_SHAMAN } })    -- Spirit Link Totem
add(C, "EXT", 108280, 180, { specs = { RESTO_SHAMAN } })   -- Healing Tide Totem
add(C, "EXT", 207399, 300, { specs = { RESTO_SHAMAN }, talent = true }) -- Ancestral Protection Totem
add(C, "EXT", 198838, 60, { specs = { RESTO_SHAMAN }, talent = true })  -- Earthen Wall Totem
add(C, "DEF", 108271, 120)                                 -- Astral Shift
add(C, "DEF", 198103, 180)                                 -- Earth Elemental
add(C, "DEF", 108281, 120, { talent = true })              -- Ancestral Guidance
add(C, "OFF", 114050, 180, { specs = { ELEMENTAL }, talent = true })    -- Ascendance
add(C, "OFF", 114051, 180, { specs = { ENHANCEMENT }, talent = true })  -- Ascendance
add(C, "OFF", 114052, 180, { specs = { RESTO_SHAMAN }, talent = true }) -- Ascendance
add(C, "OFF", 198067, 150, { specs = { ELEMENTAL } })      -- Fire Elemental
add(C, "OFF", 192249, 150, { specs = { ELEMENTAL }, talent = true })    -- Storm Elemental
add(C, "OFF", 191634, 60, { specs = { ELEMENTAL }, talent = true })     -- Stormkeeper
add(C, "OFF", 51533, 90, { specs = { ENHANCEMENT } })      -- Feral Spirit
add(C, "OFF", 384352, 60, { specs = { ENHANCEMENT }, talent = true })   -- Doom Winds
add(C, "UTIL", 192077, 120, { talent = true })             -- Wind Rush Totem
add(C, "UTIL", 79206, 120, { talent = true })              -- Spiritwalker's Grace

-------------------------------------------------------------------- WARLOCK
C = "WARLOCK"
add(C, "INT", 19647, 24, { specs = { AFFLICTION, DESTRUCTION } }) -- Spell Lock (Felhunter)
add(C, "INT", 89766, 30, { specs = { DEMONOLOGY } })       -- Axe Toss (Felguard)
add(C, "CC", 30283, 60, { talent = true })                 -- Shadowfury
add(C, "CC", 5484, 40, { talent = true })                  -- Howl of Terror
add(C, "CC", 6789, 45, { talent = true })                  -- Mortal Coil
add(C, "DEF", 104773, 180)                                 -- Unending Resolve
add(C, "DEF", 108416, 60, { talent = true })               -- Dark Pact
add(C, "OFF", 205180, 120, { specs = { AFFLICTION }, talent = true })   -- Summon Darkglare
add(C, "OFF", 386997, 60, { specs = { AFFLICTION }, talent = true })    -- Soul Rot
add(C, "OFF", 265187, 60, { specs = { DEMONOLOGY }, talent = true })    -- Summon Demonic Tyrant
add(C, "OFF", 111898, 120, { specs = { DEMONOLOGY }, talent = true })   -- Grimoire: Felguard
add(C, "OFF", 267217, 120, { specs = { DEMONOLOGY }, talent = true })   -- Nether Portal
add(C, "OFF", 1122, 120, { specs = { DESTRUCTION }, talent = true })    -- Summon Infernal

-------------------------------------------------------------------- WARRIOR
C = "WARRIOR"
add(C, "INT", 6552, 15)                                    -- Pummel
add(C, "INT", 386071, 90, { talent = true })               -- Disrupting Shout
add(C, "CC", 46968, 40, { talent = true })                 -- Shockwave
add(C, "CC", 107570, 30, { talent = true })                -- Storm Bolt
add(C, "CC", 5246, 90)                                     -- Intimidating Shout
add(C, "EXT", 97462, 180)                                  -- Rallying Cry
add(C, "DEF", 871, 210, { specs = { PROT_WARRIOR } })      -- Shield Wall
add(C, "DEF", 12975, 180, { specs = { PROT_WARRIOR }, talent = true }) -- Last Stand
add(C, "DEF", 118038, 120, { specs = { ARMS } })           -- Die by the Sword
add(C, "DEF", 184364, 120, { specs = { FURY }, talent = true })        -- Enraged Regeneration
add(C, "DEF", 23920, 25)                                   -- Spell Reflection
add(C, "DEF", 1160, 45, { specs = { PROT_WARRIOR } })      -- Demoralizing Shout
add(C, "OFF", 107574, 90, { talent = true })               -- Avatar
add(C, "OFF", 1719, 90, { specs = { FURY } })              -- Recklessness
add(C, "OFF", 167105, 45, { specs = { ARMS } })            -- Colossus Smash
add(C, "OFF", 262161, 45, { specs = { ARMS }, talent = true })  -- Warbreaker
add(C, "OFF", 227847, 90, { specs = { ARMS, FURY }, talent = true }) -- Bladestorm
add(C, "OFF", 228920, 90, { specs = { PROT_WARRIOR }, talent = true }) -- Ravager
add(C, "UTIL", 6544, 45)                                   -- Heroic Leap

-------------------------------------------------------------------- helpers

-- Other spell IDs that mean the same ability (pet versions of the Warlock interrupts).
ns.ALIASES = { [119910] = 19647, [132409] = 19647, [1276467] = 19647, [119914] = 89766 }

-- Talents that shorten (add < 0) or lengthen cooldowns, from the Midnight 12.1 data the
-- KiraUI plugin ships. { t = talentSpellID, add = seconds, pct = percent, spec = specID }
-- A modifier with `t` only applies when the player is known to have that talent; one with
-- `spec` only for that specialization.
ns.CD_MODS = {
    [49028] = { { t = 377637, add = -30 } },
    [48707] = { { t = 205727, add = -20 }, { t = 457574, add = 20 } },
    [51052] = { { t = 374383, add = -60 } },
    [196718] = { { t = 389783, add = -120 } },
    [194223] = { { t = 390378, add = -60 }, { t = 468743, add = -60 } },
    [106951] = { { t = 391174, add = -60 }, { t = 391548, add = -30 } },
    [22812] = { { spec = 104, add = -15 }, { t = 203965, pct = -12 } },
    [61336] = { { t = 203965, pct = -12 } },
    [102342] = { { t = 382552, add = -20 } },
    [363534] = { { t = 381922, add = -60 } },
    [403631] = { { t = 412713, pct = -10 } },
    [363916] = { { t = 412713, pct = -10 } },
    [357170] = { { t = 376204, add = -10 } },
    [19574] = { { t = 231548, add = -60 } },
    [288613] = { { t = 260404, add = -30 } },
    [1250646] = { { t = 1251790, add = -15 } },
    [186265] = { { t = 266921, add = -15 }, { t = 1258485, add = -30 } },
    [190319] = { { t = 1254194, add = -60 } },
    [45438] = { { t = 382424, add = -30 }, { t = 1265517, add = -30 }, { t = 1244110, add = -30 } },
    [342245] = { { t = 342249, add = -5 }, { t = 1255166, add = -10 } },
    [123904] = { { t = 392986, add = -30 } },
    [115203] = { { t = 388813, add = -30 } },
    [116849] = { { t = 202424, add = -45 } },
    [31884] = { { t = 1241511, add = -15 }, { t = 204074, pct = -50 } },
    [642] = { { t = 114154, pct = -30 }, { t = 378425, pct = -15 } },
    [498] = { { t = 114154, pct = -30 } },
    [31850] = { { t = 114154, pct = -30 } },
    [6940] = { { t = 384820, add = -60 } },
    [1022] = { { t = 384909, add = -60 }, { t = 378425, pct = -15 } },
    [19236] = { { t = 238100, add = -20 } },
    [47585] = { { t = 288733, add = -30 } },
    [114050] = { { t = 462440, add = -60 } },
    [114051] = { { t = 384444, add = -60 } },
    [108271] = { { t = 381647, add = -30 } },
    [1122] = { { t = 1280483, add = -30 } },
    [104773] = { { t = 386659, add = -45 } },
    [108416] = { { t = 386686, add = -15 } },
    [118038] = { { t = 391271, add = 0, pct = -10 } },
    [184364] = { { t = 391271, pct = -10 } },
    [23920] = { { t = 391271, pct = -10 } },
    [31821] = { { t = 392911, add = -30 } },
    [106898] = { { t = 288826, add = -60 } },
    [192077] = { { t = 462791, add = -30 } },
    [374227] = { { t = 412713, pct = -10 } },
    [374968] = { { t = 412713, pct = -10 } },
    [55342] = { { t = 1244025, add = -30 } },
    [204066] = { { t = 429539, add = -20 } },
    [351338] = { { t = 412713, pct = -10 } },    -- Quell
    [2139] = { { t = 382297, add = -5 } },       -- Counterspell
    [6552] = { { t = 391271, pct = -10 } },      -- Pummel
}

-- Cooldown for a spell: the specialization's value, shortened by the talents we know about
-- (talents is { [talentSpellID] = rank }, from inspecting the player; nil = unknown).
function ns.CooldownFor(id, spec, talents)
    local def = S[id]
    if not def then return 0 end
    local cd = (spec and def.cds and def.cds[spec]) or def.cd
    local mods = ns.CD_MODS[id]
    if mods then
        local add, mul = 0, 1
        for _, m in ipairs(mods) do
            local rank = 0
            if m.t then
                rank = talents and talents[m.t] or 0
            elseif m.spec and m.spec == spec then
                rank = 1
            end
            if rank > 0 then
                add = add + (m.add or 0) * rank
                mul = mul * (1 + (m.pct or 0) * rank / 100)
            end
        end
        if add ~= 0 or mul ~= 1 then
            cd = math.floor(math.max(5, math.min(900, (cd + add) * mul)) + 0.5)
        end
    end
    return cd
end

-- Does this spell exist for that class / specialization / faction?
-- With an unknown specialization only class-wide spells match.
function ns.SpellApplies(def, class, spec, faction)
    if def.class ~= class then return false end
    if def.faction and faction and def.faction ~= faction then return false end
    if def.specs then
        if not spec then return false end
        for _, s in ipairs(def.specs) do
            if s == spec then return true end
        end
        return false
    end
    return true
end

-- Crowd control the player applies to enemies. Used by the mob CC tracker as the starting
-- estimate; when the game lets us read the aura, the real remaining time is used instead.
-- Durations are the PvE values.
ns.CC_SPELLS = {
    [118] = 60, [28271] = 60, [28272] = 60, [61305] = 60, [61721] = 60, [61780] = 60, [126819] = 60, -- Polymorph
    [51514] = 60,   -- Hex
    [2094] = 60,    -- Blind
    [6770] = 60,    -- Sap
    [20066] = 60,   -- Repentance
    [115078] = 60,  -- Paralysis
    [2637] = 40,    -- Hibernate
    [339] = 30,     -- Entangling Roots
    [710] = 30,     -- Banish
    [9484] = 50,    -- Shackle Undead
    [187650] = 60,  -- Freezing Trap
    [5782] = 20,    -- Fear
    [217832] = 60,  -- Imprison
    [19386] = 30,   -- Wyvern Sting
    [360806] = 20,  -- Sleep Walk
    [853] = 6,      -- Hammer of Justice
    [115750] = 6,   -- Blinding Light
    [408] = 6,      -- Kidney Shot
    [5211] = 4,     -- Mighty Bash
    [119381] = 3,   -- Leg Sweep
    [46968] = 2,    -- Shockwave
    [107570] = 4,   -- Storm Bolt
    [5246] = 8,     -- Intimidating Shout
    [8122] = 8,     -- Psychic Scream
    [5484] = 20,    -- Howl of Terror
    [30283] = 3,    -- Shadowfury
    [179057] = 2,   -- Chaos Nova
    [221562] = 5,   -- Asphyxiate
    [108194] = 5,   -- Asphyxiate
    [207167] = 5,   -- Blinding Sleet
    [33786] = 6,    -- Cyclone
    [113724] = 10,  -- Ring of Frost
    [31661] = 4,    -- Dragon's Breath
    [99] = 3,       -- Incapacitating Roar
    [64044] = 4,    -- Psychic Horror
    [192058] = 3,   -- Capacitor Totem
    [19577] = 5,    -- Intimidation
    [211881] = 4,   -- Fel Eruption
}

-- Crowd control auras each class can put on enemies (aura spell IDs), used to feed the KiraUI
-- plugin's CC bars with your own CC. Polymorph and Hex have many forms.
ns.CC_BY_CLASS = {
    MAGE = { 118, 28271, 28272, 61305, 61721, 61780, 126819, 31661, 113724 },
    SHAMAN = { 51514, 210873, 211004, 211010, 211015, 269352, 277778, 277784, 309328, 118905 },
    ROGUE = { 2094, 6770, 1776, 408 },
    PALADIN = { 20066, 853, 115750 },
    MONK = { 115078, 119381 },
    DRUID = { 2637, 339, 5211, 99, 102359 },
    PRIEST = { 9484, 8122, 64044 },
    WARLOCK = { 5782, 710, 30283, 5484, 6789 },
    HUNTER = { 3355, 19386, 117526, 19577 },
    DEMONHUNTER = { 217832, 179057, 204490, 207684, 211881 },
    DEATHKNIGHT = { 108194, 221562, 207167 },
    WARRIOR = { 5246, 46968, 107570 },
    EVOKER = { 360806, 372245, 372048 },
}
