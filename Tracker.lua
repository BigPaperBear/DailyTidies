-- Daily Tidies -- Tracker.
-- Reads the self-learning quest registry built by Discovery.lua
-- (DailyTidiesDB.quests) and shows live completion status for Maerys'
-- "Orbs of Lost Memories" daily/weekly chores.

DailyTidiesTracker = {}

local WEEKLY_TOTAL_HINT = 8  -- known concurrent weekly raid-kill slots; grows if more are learned

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV" }
local function toRoman(n)
    return ROMAN[n] or tostring(n)
end

-- Neither IsQuestFlaggedCompleted nor C_QuestLog exist on this client
-- (confirmed via /dtidy diag: both nil, even with the quest log UI
-- already loaded). The only "done" signal this addon can trust is a
-- turn-in it personally witnessed (Discovery.lua's QUEST_TURNED_IN
-- handler stamps entry.completedAt), checked against the most recent
-- reset. That means a quest completed before this addon was watching
-- won't show as done until it's completed again after this update.
local function computeLastDailyResetEpoch()
    if not GetQuestResetTime then
        return nil
    end
    local secondsUntilReset = GetQuestResetTime()
    if not secondsUntilReset or secondsUntilReset <= 0 then
        return nil
    end
    return time() + secondsUntilReset - 86400
end

local function computeLastWeeklyResetEpoch()
    if not C_DateAndTime or not C_DateAndTime.GetSecondsUntilWeeklyReset then
        return nil
    end
    local secondsUntilReset = C_DateAndTime.GetSecondsUntilWeeklyReset()
    if not secondsUntilReset or secondsUntilReset <= 0 then
        return nil
    end
    return time() + secondsUntilReset - (7 * 86400)
end

-- Weekly quests don't escalate tiers: one row per learned id.
local function buildWeeklyItems(activeTitles, lastWeeklyResetEpoch)
    local byID = {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        if entry.frequency ~= 1 then
            local title = entry.title or ("Quest " .. id)
            table.insert(byID, { id = id, title = title, display = entry.display or title, completedAt = entry.completedAt })
        end
    end
    table.sort(byID, function(a, b) return a.id < b.id end)

    local items = {}
    for _, q in ipairs(byID) do
        local doneThisWeek = q.completedAt and lastWeeklyResetEpoch and q.completedAt >= lastWeeklyResetEpoch
        local status
        if activeTitles[q.title] then
            status = "active"
        elseif doneThisWeek then
            status = "done"
        else
            status = "none"
        end
        table.insert(items, { key = q.id, label = q.display, status = status })
    end
    return items
end

-- Daily chores escalate tiers under the SAME title (e.g. "A Life, Lived
-- Through" 601000 -> 601100 -> ...), only the objective text and questID
-- change per tier. One row per chain, with a pip per known tier (I, II,
-- III, ...) instead of one row per tier -- lets you see the whole chain's
-- progress (which tiers are done, which is active, which aren't reached
-- yet) without the row count growing forever as new tiers get discovered.

local function buildDailyChainItems(activeTitles, activeTierIDs, activeStage, lastResetEpoch, lastGossipAvailable)
    local groups, order = {}, {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        if entry.frequency == 1 then
            local title = entry.title or ("Quest " .. id)
            if not groups[title] then
                groups[title] = {}
                table.insert(order, title)
            end
            table.insert(groups[title], { id = id, display = entry.display or entry.title, completedAt = entry.completedAt })
        end
    end
    table.sort(order)

    local items = {}
    for _, title in ipairs(order) do
        local tiers = groups[title]
        table.sort(tiers, function(a, b) return a.id < b.id end)

        -- Which tier position(s) are active right now. An exact
        -- objective-text match is authoritative; if the title is active
        -- but this exact tier's text isn't on file yet (a brand new
        -- tier), fall back to the regex-extracted "N times" stage number.
        local activeIndices = {}
        local matched = activeTierIDs[title]
        if matched and next(matched) then
            for i, t in ipairs(tiers) do
                if matched[t.id] then
                    activeIndices[i] = true
                end
            end
        elseif activeTitles[title] then
            activeIndices[activeStage[title] or 1] = true
        end

        -- Lowest currently-active tier, if any: being on tier N>1 PROVES
        -- tiers 1..N-1 were completed at some point (tiers only unlock in
        -- order). Whether that proof counts as "this cycle" depends on
        -- whether Maerys is still withholding tier 1 -- if her last known
        -- available-quest list (from the most recent GOSSIP_SHOW) does
        -- NOT offer this chain's base quest, no reset has happened since
        -- those lower tiers were cleared, so they count as done. This is
        -- the only way to recover pre-existing progress on a client with
        -- no completed-flag API at all.
        local lowestActiveIndex = nil
        for i in pairs(activeIndices) do
            if not lowestActiveIndex or i < lowestActiveIndex then
                lowestActiveIndex = i
            end
        end
        local provenDoneByGossip = lowestActiveIndex and lowestActiveIndex > 1
            and lastGossipAvailable and not lastGossipAvailable[title]

        -- "Done" is otherwise judged per tier ON ITS OWN -- never implied
        -- from a different tier merely being active (that was the earlier
        -- bug: a leftover higher tier someone forgot to turn in doesn't
        -- prove a LOWER tier was done today). No native completed-flag
        -- exists on this client, so the witnessed-turn-in timestamp is
        -- the fallback signal.
        local pips, touchedToday = {}, false
        for i, t in ipairs(tiers) do
            local doneToday = (provenDoneByGossip and i < lowestActiveIndex)
                or (t.completedAt and lastResetEpoch and t.completedAt >= lastResetEpoch)
            local state
            if activeIndices[i] then
                state = "active"
            elseif doneToday then
                state = "done"
            else
                state = "none"
            end
            if state ~= "none" then
                touchedToday = true
            end
            table.insert(pips, { roman = toRoman(i), state = state })
        end

        table.insert(items, {
            key = title,
            display = tiers[1].display,
            pips = pips,
            touchedToday = touchedToday,
        })
    end
    return items
end

-- ===== UI =====

local frame, scrollChild, dailyHeader, weeklyHeader, dailyHeaderBtn, weeklyHeaderBtn, dailyRows, weeklyRows

local COLLAPSE_ICON = { open = "|cFF888888-|r", closed = "|cFF888888+|r" }

local ROW_COLOR = { r = 0.85, g = 0.85, b = 0.85 }
local ROW_HEIGHT = 16

local STATUS_TEXT = {
    done = "|cFF00FF00V|r",
    active = "|cFFFFFF00o|r",
    none = "|cFF888888-|r",
}

local PIP_COLOR = {
    active = "|cFFFFD100%s|r", -- gold: current tier
    done = "|cFF33CC33%s|r",   -- green: already cleared today
    none = "|cFF555555%s|r",   -- grey: not reached yet
}

-- Weekly rows: status glyph + name, unchanged from before.
local function acquireRow(pool, index, parent)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetSize(340, ROW_HEIGHT)
        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.status:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.status:SetWidth(16)
        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.title:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
        row.title:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetTextColor(ROW_COLOR.r, ROW_COLOR.g, ROW_COLOR.b)
        pool[index] = row
    end
    return row
end

local function layoutRows(pool, items, anchorTo)
    local prev = anchorTo
    for i, item in ipairs(items) do
        local row = acquireRow(pool, i, scrollChild)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -6 or 0)
        row:Show()

        row.status:SetText(STATUS_TEXT[item.status] or STATUS_TEXT.none)
        row.title:SetText(item.label)
        prev = row
    end
    for i = #items + 1, #pool do
        pool[i]:Hide()
    end
    return prev
end

-- Daily rows: a "touched today" dot + chain name + a pip per known tier.
local function acquireDailyRow(pool, index, parent)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetSize(340, ROW_HEIGHT)
        row.dot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dot:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.dot:SetWidth(10)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.dot, "RIGHT", 2, 0)
        row.name:SetWidth(150)
        row.name:SetJustifyH("LEFT")
        row.name:SetTextColor(ROW_COLOR.r, ROW_COLOR.g, ROW_COLOR.b)
        row.pips = {}
        pool[index] = row
    end
    return row
end

local function layoutDailyRows(pool, items, anchorTo)
    local prev = anchorTo
    for i, item in ipairs(items) do
        local row = acquireDailyRow(pool, i, scrollChild)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, i == 1 and -6 or 0)
        row:Show()

        row.dot:SetText(item.touchedToday and "|cFF33CC33*|r" or "|cFF555555*|r")
        row.name:SetText(item.display)

        local pipAnchor = row.name
        for pi, pip in ipairs(item.pips) do
            local pipFS = row.pips[pi]
            if not pipFS then
                pipFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.pips[pi] = pipFS
            end
            pipFS:ClearAllPoints()
            pipFS:SetPoint("LEFT", pipAnchor, "RIGHT", pi == 1 and 6 or 3, 0)
            pipFS:SetText(string.format(PIP_COLOR[pip.state] or PIP_COLOR.none, pip.roman))
            pipFS:Show()
            pipAnchor = pipFS
        end
        for pi = #item.pips + 1, #row.pips do
            row.pips[pi]:Hide()
        end

        prev = row
    end
    for i = #items + 1, #pool do
        pool[i]:Hide()
        for _, pipFS in ipairs(pool[i].pips) do
            pipFS:Hide()
        end
    end
    return prev
end

-- No guaranteed C_QuestLog namespace on this client (nil until the
-- Blizzard quest log UI happens to load). Use the always-native raw
-- global IsQuestFlaggedCompleted(id) for completion, and a manual
-- quest-log scan for "currently active". Match by TITLE, not questID:
-- an untracked (unwatched) quest's log row doesn't reliably return a
-- questID on this client, but its title always does.
--
-- GetQuestLogTitle's linear index skips every row under a COLLAPSED
-- header, so a quest inside a collapsed category silently vanishes from
-- the scan. Expand any collapsed headers first, then restore their
-- collapsed state afterward. This all happens synchronously with no
-- frame yield in between, so it never paints on screen even if the
-- player's real quest log window is open.
local function extractStageFromText(...)
    for i = 1, select("#", ...) do
        local text = select(i, ...)
        if text then
            local count = text:match("(%d+)%s+times?")
            if count then
                return tonumber(count)
            end
        end
    end
    return nil
end

local function scanActiveQuestTitles()
    local active, activeTierIDs, activeStage = {}, {}, {}
    if not GetNumQuestLogEntries then
        return active, activeTierIDs, activeStage
    end

    -- Reverse lookup per title: known tier objective text -> questID, so a
    -- live quest log entry can be matched to the EXACT known tier it is.
    local objectiveIndex = {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        if entry.frequency == 1 and entry.objective and entry.title then
            objectiveIndex[entry.title] = objectiveIndex[entry.title] or {}
            objectiveIndex[entry.title][entry.objective] = id
        end
    end

    local collapsedHeaderTitles = {}
    if ExpandQuestHeader then
        local n = GetNumQuestLogEntries()
        for index = 1, n do
            local ok, title, level, questTag, suggestedGroup, isHeader, isCollapsed = pcall(GetQuestLogTitle, index)
            if ok and isHeader and isCollapsed then
                table.insert(collapsedHeaderTitles, title)
                pcall(ExpandQuestHeader, index)
            end
        end
    end

    local prevSelected = GetQuestLogSelection and GetQuestLogSelection()

    local n = GetNumQuestLogEntries()
    for index = 1, n do
        local ok, title, level, questTag, suggestedGroup, isHeader = pcall(GetQuestLogTitle, index)
        if ok and not isHeader and title then
            active[title] = true
            if SelectQuestLogEntry and GetQuestLogQuestText then
                if pcall(SelectQuestLogEntry, index) then
                    local textOk, description, objectives = pcall(GetQuestLogQuestText)
                    if textOk then
                        local titleIndex = objectiveIndex[title]
                        local matchedID = titleIndex and (titleIndex[description] or titleIndex[objectives])
                        if matchedID then
                            activeTierIDs[title] = activeTierIDs[title] or {}
                            activeTierIDs[title][matchedID] = true
                        end
                        if not activeStage[title] then
                            local stage = extractStageFromText(objectives, description)
                            if stage then
                                activeStage[title] = stage
                            end
                        end
                    end
                end
            end
        end
    end

    if SelectQuestLogEntry and prevSelected then
        pcall(SelectQuestLogEntry, prevSelected)
    end

    if CollapseQuestHeader and #collapsedHeaderTitles > 0 then
        n = GetNumQuestLogEntries()
        for index = 1, n do
            local ok, title, level, questTag, suggestedGroup, isHeader = pcall(GetQuestLogTitle, index)
            if ok and isHeader then
                for _, collapsedTitle in ipairs(collapsedHeaderTitles) do
                    if collapsedTitle == title then
                        pcall(CollapseQuestHeader, index)
                        break
                    end
                end
            end
        end
    end

    return active, activeTierIDs, activeStage
end

local function Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    -- SavedVariables restore replaces the whole DailyTidiesDB global after
    -- this file loads, so an "or {}" fallback at file scope gets wiped for
    -- any DB saved before the "collapsed" key existed. Init it here instead.
    DailyTidiesDB.collapsed = DailyTidiesDB.collapsed or {}

    local activeTitles, activeTierIDs, activeStage = scanActiveQuestTitles()
    local dailyItems = buildDailyChainItems(activeTitles, activeTierIDs, activeStage, computeLastDailyResetEpoch(), DailyTidiesDB.lastGossipAvailable)
    local weeklyItems = buildWeeklyItems(activeTitles, computeLastWeeklyResetEpoch())

    local weeklyDone = 0
    for _, item in ipairs(weeklyItems) do
        if item.status == "done" then
            weeklyDone = weeklyDone + 1
        end
    end

    local dailyCollapsed = DailyTidiesDB.collapsed.daily
    local weeklyCollapsed = DailyTidiesDB.collapsed.weekly

    dailyHeader:SetText(string.format("%s Daily chores", dailyCollapsed and COLLAPSE_ICON.closed or COLLAPSE_ICON.open))
    weeklyHeader:SetText(string.format("%s Weekly raid kills: %d/%d", weeklyCollapsed and COLLAPSE_ICON.closed or COLLAPSE_ICON.open, weeklyDone, math.max(WEEKLY_TOTAL_HINT, #weeklyItems)))

    local shownDaily = dailyCollapsed and {} or dailyItems
    local shownWeekly = weeklyCollapsed and {} or weeklyItems

    local lastDailyRow = layoutDailyRows(dailyRows, shownDaily, dailyHeader)
    weeklyHeader:ClearAllPoints()
    weeklyHeader:SetPoint("TOPLEFT", lastDailyRow, "BOTTOMLEFT", 0, -14)
    weeklyHeaderBtn:ClearAllPoints()
    weeklyHeaderBtn:SetPoint("TOPLEFT", weeklyHeader, "TOPLEFT", -2, 2)
    layoutRows(weeklyRows, shownWeekly, weeklyHeader)

    -- The row list lives in a scrollable area so the window itself never
    -- has to grow tall as more quests get learned; resize the scroll
    -- child to fit whatever got laid out instead.
    local contentHeight = 8 + 16 + (#shownDaily * ROW_HEIGHT) + 6 + 14 + 16 + (#shownWeekly * ROW_HEIGHT) + 6 + 12
    scrollChild:SetHeight(math.max(contentHeight, 1))
end

local function SaveFramePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    DailyTidiesDB.frame = DailyTidiesDB.frame or {}
    DailyTidiesDB.frame.point = point
    DailyTidiesDB.frame.relativePoint = relativePoint
    DailyTidiesDB.frame.x = x
    DailyTidiesDB.frame.y = y
end

local function SaveFrameSize(f)
    DailyTidiesDB.frame = DailyTidiesDB.frame or {}
    DailyTidiesDB.frame.width = f:GetWidth()
    DailyTidiesDB.frame.height = f:GetHeight()
end

local function CreateTrackerFrame()
    local f = CreateFrame("Frame", "DailyTidiesTrackerFrame", UIParent)
    local saved = DailyTidiesDB.frame

    f:SetSize((saved and saved.width) or 380, (saved and saved.height) or 320)
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        f:SetPoint("CENTER", 200, 0)
    end

    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true) -- bumps against the screen edge instead of dragging off it
    if f.SetMinResize then f:SetMinResize(300, 220) end
    if f.SetMaxResize then f:SetMaxResize(600, 700) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition(self)
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.09, 0.92)
    f:SetBackdropBorderColor(0.65, 0.53, 0.22, 1)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText("|cFFE0B84DDaily Tidies|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Fixed-height scroll area for the row lists: the window stays a
    -- constant size no matter how many quests get learned over time.
    local scrollFrame = CreateFrame("ScrollFrame", "DailyTidiesTrackerScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 20)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local newScroll = self:GetVerticalScroll() - delta * 20
        newScroll = math.max(0, math.min(newScroll, self:GetVerticalScrollRange()))
        self:SetVerticalScroll(newScroll)
    end)

    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(340)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    dailyHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dailyHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -4)
    dailyHeader:SetJustifyH("LEFT")
    dailyHeader:SetTextColor(0.9, 0.75, 0.35)

    dailyHeaderBtn = CreateFrame("Button", nil, scrollChild)
    dailyHeaderBtn:SetSize(340, 16)
    dailyHeaderBtn:SetPoint("TOPLEFT", dailyHeader, "TOPLEFT", -2, 2)
    dailyHeaderBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    dailyHeaderBtn:SetScript("OnClick", function()
        DailyTidiesDB.collapsed.daily = not DailyTidiesDB.collapsed.daily
        Refresh()
    end)

    weeklyHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weeklyHeader:SetJustifyH("LEFT")
    weeklyHeader:SetTextColor(0.5, 0.75, 0.95)

    weeklyHeaderBtn = CreateFrame("Button", nil, scrollChild)
    weeklyHeaderBtn:SetSize(340, 16)
    weeklyHeaderBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    weeklyHeaderBtn:SetScript("OnClick", function()
        DailyTidiesDB.collapsed.weekly = not DailyTidiesDB.collapsed.weekly
        Refresh()
    end)

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        SaveFrameSize(f)
        Refresh()
    end)

    dailyRows = {}
    weeklyRows = {}

    f:SetScript("OnShow", Refresh)
    f:Hide()
    return f
end

function DailyTidiesTracker.Show()
    frame = frame or CreateTrackerFrame()
    frame:Show()
    frame:Raise()
end

function DailyTidiesTracker.Toggle()
    frame = frame or CreateTrackerFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        DailyTidiesTracker.Show()
    end
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("QUEST_LOG_UPDATE")
watcher:RegisterEvent("PLAYER_LOGIN")
local elapsed = 0
watcher:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        DailyTidiesTracker.Show()
    else
        Refresh()
    end
end)
watcher:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= 5 then
        elapsed = 0
        Refresh()
    end
end)
