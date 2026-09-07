-- Daily Tidies -- Tracker.
-- Reads the self-learning quest registry built by Discovery.lua
-- (DailyTidiesDB.quests) and shows live completion status for Maerys'
-- "Orbs of Lost Memories" daily/weekly chores.

DailyTidiesTracker = {}

local WEEKLY_TOTAL_HINT = 8  -- known concurrent weekly raid-kill slots; grows if more are learned

-- Weekly quests don't escalate tiers: one row per learned id.
local function buildWeeklyItems(activeTitles)
    local byID = {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        if entry.frequency ~= 1 then
            local title = entry.title or ("Quest " .. id)
            table.insert(byID, { id = id, title = title, display = entry.display or title })
        end
    end
    table.sort(byID, function(a, b) return a.id < b.id end)

    local items = {}
    for _, q in ipairs(byID) do
        local status
        if IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(q.id) then
            status = "done"
        elseif activeTitles[q.title] then
            status = "active"
        else
            status = "none"
        end
        table.insert(items, { key = q.id, label = q.display, status = status })
    end
    return items
end

-- Daily chores escalate tiers under the SAME title (e.g. "A Life, Lived
-- Through" 601000 -> 601100 -> ...), only the objective text and questID
-- change per tier. Group by title and show just the current tier's state
-- instead of a flat, ever-growing list of every tier ever seen.
local function buildDailyChainItems(activeTitles, activeStage)
    local groups, order = {}, {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        if entry.frequency == 1 then
            local title = entry.title or ("Quest " .. id)
            if not groups[title] then
                groups[title] = {}
                table.insert(order, title)
            end
            table.insert(groups[title], { id = id, objective = entry.objective, title = title, display = entry.display or title })
        end
    end
    table.sort(order)

    local items = {}
    for _, title in ipairs(order) do
        local tiers = groups[title]
        table.sort(tiers, function(a, b) return a.id < b.id end)

        -- Registry is account-wide (shared across characters), so it can
        -- hold tiers a fresh character never unlocked yet. The current
        -- tier is the LOWEST one not yet flagged completed on THIS
        -- character; if every known tier is completed, show the highest
        -- one as done. Stage number = the tier's position in our
        -- learned-tier list (tiers only ever go up, one at a time), which
        -- is what "Reach level 80 1 time / 2 times / 3 times..." maps to.
        local current, currentStage = tiers[#tiers], #tiers
        for i = 1, #tiers do
            if not (IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(tiers[i].id)) then
                current, currentStage = tiers[i], i
                break
            end
        end

        -- Live quest log objective text overrides the registry-derived
        -- stage: it's correct even if this tier's ID was never learned.
        if activeStage[title] then
            currentStage = activeStage[title]
        end

        local status
        if activeTitles[title] then
            status = "active"
        elseif IsQuestFlaggedCompleted and IsQuestFlaggedCompleted(current.id) then
            status = "done"
        else
            status = "none"
        end

        table.insert(items, { key = title, label = string.format("%s (x%d)", current.display, currentStage), status = status })
    end
    return items
end

-- ===== UI =====

local frame, dailyHeader, weeklyHeader, dailyHeaderBtn, weeklyHeaderBtn, dailyRows, weeklyRows

local COLLAPSE_ICON = { open = "|cFF888888-|r", closed = "|cFF888888+|r" }

local ROW_COLOR = { r = 0.85, g = 0.85, b = 0.85 }

local function acquireRow(pool, index, parent)
    local row = pool[index]
    if not row then
        row = CreateFrame("Frame", nil, parent)
        row:SetSize(340, 16)
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
-- The registry only learns a tier's ID from a live event (gossip, accept,
-- turn-in). A tier already sitting in the quest log from before this
-- session (or before Discovery saw it) never fires those events, so the
-- registry alone can under-report which tier is active. The quest log's
-- own objective text always says "N times" for tier N+1 (tier 1 has no
-- count), so read that directly off the active quest log entry instead of
-- trusting the registry for the stage number.
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
    local active, activeStage = {}, {}
    if not GetNumQuestLogEntries then
        return active, activeStage
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
            if not activeStage[title] and SelectQuestLogEntry and GetQuestLogQuestText then
                if pcall(SelectQuestLogEntry, index) then
                    local textOk, description, objectives = pcall(GetQuestLogQuestText)
                    if textOk then
                        local stage = extractStageFromText(objectives, description)
                        if stage then
                            activeStage[title] = stage
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

    return active, activeStage
end

local STATUS_TEXT = {
    done = "|cFF00FF00V|r",
    active = "|cFFFFFF00o|r",
    none = "|cFF888888-|r",
}

local function layoutRows(pool, items, anchorTo)
    local prev = anchorTo
    for i, item in ipairs(items) do
        local row = acquireRow(pool, i, frame)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", prev, i == 1 and "BOTTOMLEFT" or "BOTTOMLEFT", 0, i == 1 and -6 or 0)
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

local function Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    -- SavedVariables restore replaces the whole DailyTidiesDB global after
    -- this file loads, so an "or {}" fallback at file scope gets wiped for
    -- any DB saved before the "collapsed" key existed. Init it here instead.
    DailyTidiesDB.collapsed = DailyTidiesDB.collapsed or {}

    local activeTitles, activeStage = scanActiveQuestTitles()
    local dailyItems = buildDailyChainItems(activeTitles, activeStage)
    local weeklyItems = buildWeeklyItems(activeTitles)

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

    local lastDailyRow = layoutRows(dailyRows, dailyCollapsed and {} or dailyItems, dailyHeader)
    weeklyHeader:ClearAllPoints()
    weeklyHeader:SetPoint("TOPLEFT", lastDailyRow, "BOTTOMLEFT", 0, -14)
    weeklyHeaderBtn:ClearAllPoints()
    weeklyHeaderBtn:SetPoint("TOPLEFT", weeklyHeader, "TOPLEFT", -2, 2)
    layoutRows(weeklyRows, weeklyCollapsed and {} or weeklyItems, weeklyHeader)
end

local function CreateTrackerFrame()
    local f = CreateFrame("Frame", "DailyTidiesTrackerFrame", UIParent)
    f:SetSize(380, 320)
    f:SetPoint("CENTER", 200, 0)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetClampedToScreen(true) -- bumps against the screen edge instead of dragging off it
    if f.SetMinResize then f:SetMinResize(300, 220) end
    if f.SetMaxResize then f:SetMaxResize(600, 700) end
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
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

    dailyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dailyHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -32)
    dailyHeader:SetJustifyH("LEFT")
    dailyHeader:SetTextColor(0.9, 0.75, 0.35)

    dailyHeaderBtn = CreateFrame("Button", nil, f)
    dailyHeaderBtn:SetSize(340, 16)
    dailyHeaderBtn:SetPoint("TOPLEFT", dailyHeader, "TOPLEFT", -2, 2)
    dailyHeaderBtn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    dailyHeaderBtn:SetScript("OnClick", function()
        DailyTidiesDB.collapsed.daily = not DailyTidiesDB.collapsed.daily
        Refresh()
    end)

    weeklyHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    weeklyHeader:SetJustifyH("LEFT")
    weeklyHeader:SetTextColor(0.5, 0.75, 0.95)

    weeklyHeaderBtn = CreateFrame("Button", nil, f)
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
