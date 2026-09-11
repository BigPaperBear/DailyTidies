# Daily Tidies

[![Downloads](https://img.shields.io/github/downloads/BigPaperBear/DailyTidies/total?style=flat-square&label=Downloads)](https://github.com/BigPaperBear/DailyTidies/releases)

Tracks NPC Maerys' daily and weekly "Orbs of Lost Memories" quests on Ebonhold (WoW 3.3.5a).

The addon learns Maerys' quests automatically as you play. You do not need to set anything up by hand.

![Interface: 30403](https://img.shields.io/badge/Interface-30403-blue) ![Server: Ebonhold](https://img.shields.io/badge/Server-Project%20Ebonhold-purple)

## Features

**Tracking**
- Learns quests automatically, no setup needed. New stages get picked up as your daily chains go up.
- Daily chores: each chain shows every known stage (I, II, III, and so on) with a status of done, in progress, or not reached yet.
- Weekly raid kills: shows every known weekly quest with its status and a count of how many are done.
- Shares newly found quest stages with other players running the addon, so a stage one person finds shows up for everyone else without an update.

**Automation**
- Auto-accept: no need to click the quest or press Accept yourself, it happens the moment her dialog opens. You still need to talk to her again for each quest she offers, you just don't have to click through each one.
- Auto turn-in (off by default): hands in a finished quest right away, but only when there is a single reward, never when you have to choose one.
- Settings window: right-click the minimap button to turn auto-accept and auto turn-in on or off, and to pick which quest chains get auto-accepted.

**Window**
- Opens automatically when you log in. You can move and resize it, and it remembers both for next time. It will not go off-screen.
- Minimap button: left-click to open or close the tracker, right-click for settings. Works with minimap button addons that collect other buttons.
- Debug logging (off by default, in Settings): turns on detailed tracing for bug reports, viewable with `/dtidy diag`.

## Install

1. Download the latest release zip from Releases.
2. Extract it into `World of Warcraft\Interface\AddOns\`.
3. Type `/reload` or restart WoW.

## Slash commands

| Command | Action |
|---|---|
| `/dtidy` | Toggle the tracker window |
| `/dtidy diag` | Show a copyable diagnostic report, for bug reports |
| `/dtidy clear` | Clear the diagnostic/debug log |
| `/dtidy autoaccept` | Turn auto-accept on or off (also available in Settings) |

## Compatibility

- WoW 3.3.5
- Server: Project Ebonhold
- No other addons needed
