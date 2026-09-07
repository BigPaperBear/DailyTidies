# Daily Tidies

> Tracks NPC Maerys' daily & weekly "Orbs of Lost Memories" chores on Ebonhold (WoW 3.3.5a)

Never lose track of which stage each daily chain is on, or which weekly raid kills you still owe Maerys. Daily Tidies learns Maerys' quests automatically as you play — no manual setup, no quest list to keep updated by hand.

![Interface: 30403](https://img.shields.io/badge/Interface-30403-blue) ![Server: Ebonhold](https://img.shields.io/badge/Server-Project%20Ebonhold-purple)

## Features

- **Self-learning quest tracker** — automatically picks up every quest Maerys offers, including new stages as your daily chains escalate. No hardcoded quest list to go stale.
- **Daily chores at a glance** — each daily chain shown at its current stage (`x1`, `x2`, `x3`, ...) with live status: done, in progress, or not started.
- **Weekly raid kills** — every known weekly objective with completion status and a running count.
- **Auto-opens on login**, movable, resizable, and stays on screen — can't be dragged off the edge.
- **Minimap button** — click to toggle the tracker; works with minimap-button collector addons.
- **Discovery log** — `/dtidy log` shows a raw, copyable log of everything the addon has learned, handy for reporting a new quest stage.

## Install

1. Download the latest release zip from [Releases](https://github.com/BigPaperBear/DailyTidies/releases).
2. Extract into `World of Warcraft\Interface\AddOns\` so you end up with `Interface\AddOns\DailyTidies\*.lua` (not a nested `DailyTidies\DailyTidies\...` folder).
3. `/reload` or restart WoW.

## Slash commands

| Command | Action |
|---|---|
| `/dtidy` | Toggle the tracker window |
| `/dtidy log` | Toggle the raw copyable discovery log |
| `/dtidy clear` | Clear the discovery log |

## Compatibility

- WoW 3.3.5a, Interface 30403 (Ebonhold's client)
- Server: Project Ebonhold
- No other addons required
