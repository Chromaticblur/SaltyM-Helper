-- Changelog.lua: what is new in each version. The Welcome page shows the newest entry.
-- Every new build of the addon adds an entry at the TOP of this list (matching the Version line
-- in SaltyMPlusHelper.toc) with a short list of what changed.

local ADDON, ns = ...

ns.CHANGELOG = {
    { version = "1.11.0", items = {
        "What's new on the Welcome page now follows the current version automatically",
        "Earlier versions are listed below it",
    } },
    { version = "1.10.0", items = {
        "Key Team button on the Welcome page (shows the Raider.IO team link to copy)",
    } },
    { version = "1.9.0", items = {
        "Focus kick: dropdown for your focus marker and an \"Announce to party\" checkbox",
        "Announces \"SaltyM+Helper: My focus kick marker is\" plus your icon at ready checks and dungeon entry",
        "Focus kick and death alert sounds moved onto their own pages (default sounds or any sound)",
        "The option that put a marker on your focus target was removed",
    } },
    { version = "1.8.0", items = {
        "Modules page: a master switch for every module, with shortcuts to their settings",
        "Attaching cooldowns to nameplates was removed (party frames or a window only)",
    } },
    { version = "1.7.0", items = {
        "Two stacked rows on party frames: defensives on top, offensives below",
        "Sound pack check, quieter test beep, built-in WoW sounds in the pickers",
    } },
    { version = "1.6.0", items = {
        "Sounds page with pickers for BigWigs, Causese and other LibSharedMedia packs",
        "SharedMedia_SaltyM companion addon (Causese voices bundled, your own files supported)",
        "Fixed having to open the settings twice the first time; Esc-menu logo button",
    } },
    { version = "1.5.0", items = {
        "Just to Sync mode, click a frame and nudge it with the arrow keys, Meow button",
    } },
    { version = "1.4.0", items = {
        "Optional Mythic Dungeon Tools link: mob forces in tooltips, last-pull forces on the Key HUD",
    } },
    { version = "1.3.0", items = {
        "Sleek list windows, grid and edge snapping, every module in EllesmereUI unlock mode",
        "Resizable, scrollable settings window",
    } },
    { version = "1.2.0", items = {
        "Enemy forces as percent or count, run summary in chat, run history (/salthist)",
        "Welcome page and a welcome message at login",
    } },
}
