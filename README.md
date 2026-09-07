# Daily Tidies

Tracks Maerys' "Orbs of Lost Memories" daily/weekly chores on Ebonhold
(WotLK 3.3.5, custom client `## Interface: 30403`).

## Files

- `Discovery.lua` — event hooks (`GOSSIP_SHOW`, `QUEST_DETAIL`, `QUEST_ACCEPTED`,
  `QUEST_TURNED_IN`, `QUEST_COMPLETE`) that self-learn every Maerys quest seen
  into `DailyTidiesDB.quests[id] = {title, frequency, objective, firstSeen, lastSeen}`.
  Also owns the raw copyable discovery log (`DailyTidiesLogDB`, `/dtidy log`)
  used to bootstrap new questID discoveries.
- `Tracker.lua` — the UI. Builds "daily chore" rows (grouped/collapsed by
  title, since tiers share one title) and "weekly raid kill" rows (flat list)
  from `DailyTidiesDB.quests`, using live client state for status.
- `MinimapButton.lua` — plain `Minimap` child button (not a library), so
  generic minimap-button collector addons (MBB etc.) can gather it.

## Slash commands

- `/dtidy` — toggle the tracker window (also auto-opens on login).
- `/dtidy log` — toggle the raw copyable discovery log window.
- `/dtidy clear` — clear the discovery log (not the learned quest DB).

## Data model

`DailyTidiesDB.quests[questID] = { title, display, frequency, objective, firstSeen, lastSeen }`

- `frequency == 1` → one of the 4 daily escalating chores.
- `frequency == nil` → one of the weekly raid-kill quests.
- `display` is a human-readable label (e.g. "Kel'Thuzad - Naxxramas" instead
  of raw title "The Frozen Heart"), looked up by title from the
  `FRIENDLY_NAMES` table in `Discovery.lua` and stamped onto the entry by
  `Learn()`. Tracker.lua shows `display` (falling back to raw `title` for
  anything unmapped); `title` itself stays the raw quest-log string since
  that's what matching against the live quest log requires.
- Learning is gated to questID range **601000-601999** (`MAERYS_ID_MIN/MAX`
  in `Discovery.lua`) so unrelated world dailies never pollute the registry.

See the `ebonhold-maerys-quest-ids` memory file (Claude's memory system) for
the full known-ID table and how tiers were discovered — that's the
source-of-truth history, this file just covers the code.

## Client quirks this addon works around (important — don't re-break these)

1. **`C_QuestLog` is not guaranteed to exist.** It appears to only get
   defined once `Blizzard_QuestLog` (a load-on-demand addon) has loaded,
   which normally only happens when the player manually opens the quest
   log. We force-load it at `PLAYER_LOGIN` in `Discovery.lua`. Because of
   this, all status checks use the raw native global `IsQuestFlaggedCompleted(id)`
   instead of `C_QuestLog.IsQuestFlaggedCompleted`.
2. **Quest log data may need a forced sync.** Some server builds don't push
   full quest-log data to the client until the quest log UI is shown once.
   `Discovery.lua`'s `PLAYER_LOGIN` handler silently `Show()`s then `Hide()`s
   `QuestLogFrame` once to force this, if the frame exists.
3. **`GetQuestLogTitle`'s linear index skips collapsed header groups.** A
   quest inside a collapsed quest-log category is invisible to
   `GetNumQuestLogEntries()`/`GetQuestLogTitle()` until you expand it.
   `Tracker.lua`'s `scanActiveQuestTitles()` expands every collapsed header,
   scans, then restores the original collapsed state — all synchronously
   (no frame yield), so it never visibly flickers even with the real quest
   log window open.
4. **Match "is this quest active" by TITLE, not questID.** An untracked
   (unwatched) quest's log row doesn't reliably return a questID on this
   client, but its title always does.
5. **`QUEST_ACCEPTED`'s 2nd event arg is unreliable here** (`arg2` came back
   `nil` in testing) — the real questID comes from `GetQuestLogTitle(questLogIndex)`'s
   9th return value. Its actual signature is
   `title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, ...`
   — don't forget `suggestedGroup`, it's easy to miscount and shift every
   field by one (this bug happened once already, see the earlier session).
6. **Tiers do NOT increment the questID by 1.** First jump observed:
   601000 → 601100 (title "A Life, Lived Through" tier 1 → tier 2). Don't
   assume a fixed ID-block gap for undiscovered tiers; only trust IDs
   actually captured live via Discovery.

## Known limitations / open TODOs for next session

- **Daily chain "current tier" heuristic can be wrong right after a daily
  reset.** It picks the highest known tier for that title that isn't
  flagged completed. If the player progressed to e.g. tier 5 yesterday and
  today's server-side reset silently reverted them to tier 1, but tier 5's
  completed-flag also got reset (unconfirmed), the display could show a
  stale/wrong tier until the player re-opens Maerys' gossip and we re-learn
  the real current tier from a fresh `QUEST_DETAIL`/`QUEST_ACCEPTED`. Needs
  a full day-boundary test to confirm actual reset behavior.
- **No reward tracking yet.** We haven't confirmed how "Orbs of Lost
  Memories" currency rewards surface per quest (`QUEST_COMPLETE_CURRENCY`
  logging exists in Discovery.lua but hasn't caught a real payload yet —
  test by actually hitting "Complete Quest" on the reward screen, not just
  opening the turn-in dialog).
- **Row width is fixed (340px)**, doesn't reflow when the tracker window is
  resized wider — only height usage changes. Low priority polish.
- **Weekly section total (8) is a hint, not a hard cap** — `WEEKLY_TOTAL_HINT`
  in Tracker.lua grows automatically if more than 8 weekly quests get
  learned, but starts from a hardcoded guess.
- Only 12 questIDs known total (4 daily tier-1's + 1 tier-2 + 8 weekly).
  Keep playing through the dailies on new days to capture tier-3+ IDs via
  `/dtidy log`.
