-- Daily Tidies -- Discovery mode.
-- Logs quest IDs/titles/objectives/rewards seen at NPCs so the real quest
-- IDs behind Ebonhold's custom "Orbs of Lost Memories" dailies can be
-- captured, since they are quest-giver-side custom quests with no known IDs.

DailyTidiesLogDB = DailyTidiesLogDB or {}
DailyTidiesDB = DailyTidiesDB or { quests = {} }
DailyTidiesDB.quests = DailyTidiesDB.quests or {}

local titleToID = {} -- session cache: quest title -> questID, filled from gossip scans
local pendingObjective = {} -- session cache: quest title -> objective text, from QUEST_DETAIL

-- Maerys' "Orbs of Lost Memories" quests all live in this custom ID block.
-- Gate auto-learning to this range so unrelated world dailies don't pollute
-- the tracker's registry.
local MAERYS_ID_MIN, MAERYS_ID_MAX = 601000, 601999

-- Raw quest titles ("The Frozen Heart", "What the Stone Kept"...) are lore
-- flavor text and don't tell the player which actual chore/boss they map
-- to. Give the tracker a human-readable display name per title instead.
local FRIENDLY_NAMES = {
    ["A Life, Lived Through"] = "Reach Level 80",
    ["One More Door"] = "Complete a Dungeon (LFD)",
    ["Everything, Given Up"] = "Complete a Prestige",
    ["The Whole Board"] = "Callboard: One of Each Type",
    ["The Frozen Heart"] = "Kel'Thuzad - Naxxramas",
    ["The Maddening Deep"] = "Yogg-Saron - Ulduar",
    ["The Last Contender"] = "Anub'arak - Trial of the Crusader",
    ["The Throne at the Top"] = "The Lich King - Icecrown Citadel",
    ["Embers Beneath the Garden"] = "Halion - Ruby Sanctum",
    ["The Shape She Wears"] = "Onyxia - Onyxia's Lair",
    ["The Clutch Below"] = "Sartharion - Obsidian Sanctum",
    ["What the Stone Kept"] = "Archavon - Vault of Archavon",
}

-- Known-good seed from live testing on 2026-09-06, so the tracker has data
-- before Discovery re-learns everything from scratch on a fresh install.
local SEED_QUESTS = {
    [601000] = { title = "A Life, Lived Through", frequency = 1, objective = "Reach level 80 in a single run, then return to Maerys." },
    [601100] = { title = "A Life, Lived Through", frequency = 1, objective = "Reach level 80 in a single run 2 times, then return to Maerys." },
    [601001] = { title = "One More Door", frequency = 1 },
    [601002] = { title = "Everything, Given Up", frequency = 1 },
    [601003] = { title = "The Whole Board", frequency = 1 },
    [601010] = { title = "The Frozen Heart" },
    [601011] = { title = "The Maddening Deep" },
    [601012] = { title = "The Last Contender" },
    [601013] = { title = "The Throne at the Top" },
    [601014] = { title = "Embers Beneath the Garden" },
    [601015] = { title = "The Shape She Wears" },
    [601016] = { title = "The Clutch Below" },
    [601017] = { title = "What the Stone Kept" },
}

local function Learn(id, title, frequency, objective)
    id = tonumber(id)
    if not id or id < MAERYS_ID_MIN or id > MAERYS_ID_MAX then
        return
    end
    local entry = DailyTidiesDB.quests[id]
    if not entry then
        entry = { firstSeen = time() }
        DailyTidiesDB.quests[id] = entry
    end
    if title then
        entry.title = title
        entry.display = entry.display or FRIENDLY_NAMES[title]
    end
    if frequency ~= nil then
        entry.frequency = frequency
    end
    if objective then
        entry.objective = objective
    end
    entry.lastSeen = time()
end

-- NOT run at file scope: SavedVariables restore replaces the whole
-- DailyTidiesDB global right after this file finishes loading (for any
-- addon whose SavedVariables already exist on disk), which would wipe out
-- anything this loop writes here. Call this from PLAYER_LOGIN instead,
-- which fires after that restore.
local function ApplySeedsAndBackfill()
    DailyTidiesDB.quests = DailyTidiesDB.quests or {}
    for id, seed in pairs(SEED_QUESTS) do
        if not DailyTidiesDB.quests[id] then
            Learn(id, seed.title, seed.frequency, seed.objective)
        end
    end

    -- Backfill display names onto quests already saved from before this
    -- feature existed (Learn() above only touches new/re-seen entries).
    for _, entry in pairs(DailyTidiesDB.quests) do
        if entry.title and not entry.display then
            entry.display = FRIENDLY_NAMES[entry.title]
        end
    end
end

local function timestamp()
    return date("%H:%M:%S")
end

local function AddLine(fmt, ...)
    local text = string.format(fmt, ...)
    local line = "[" .. timestamp() .. "] " .. text
    table.insert(DailyTidiesLogDB, line)
    if DailyTidiesLogEditBox then
        DailyTidiesLogEditBox:SetText(table.concat(DailyTidiesLogDB, "\n"))
    end
    print("|cFF66CCFF[DailyTidies]|r " .. text)
end

local function dumpFields(prefix, entry)
    local parts = {}
    for k, v in pairs(entry) do
        table.insert(parts, tostring(k) .. "=" .. tostring(v))
    end
    AddLine("%s %s", prefix, table.concat(parts, " "))
end

-- ===== UI: copyable log window =====

local function CreateLogFrame()
    local f = CreateFrame("Frame", "DailyTidiesLogFrame", UIParent)
    f:SetSize(520, 420)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("Daily Tidies - Discovery Log")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", "DailyTidiesLogScrollFrame", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)

    local editBox = CreateFrame("EditBox", "DailyTidiesLogEditBox", scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(460)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetText(table.concat(DailyTidiesLogDB, "\n"))
    scrollFrame:SetScrollChild(editBox)

    local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copyBtn:SetSize(90, 22)
    copyBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    copyBtn:SetText("Select All")
    copyBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(90, 22)
    clearBtn:SetPoint("LEFT", copyBtn, "RIGHT", 8, 0)
    clearBtn:SetText("Clear Log")
    clearBtn:SetScript("OnClick", function()
        wipe(DailyTidiesLogDB)
        editBox:SetText("")
    end)

    return f
end

local function ToggleLogFrame()
    local f = _G.DailyTidiesLogFrame or CreateLogFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        f:Raise()
    end
end

-- ===== Event capture =====

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("QUEST_ACCEPTED")
eventFrame:RegisterEvent("QUEST_TURNED_IN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        ApplySeedsAndBackfill()
        -- GetQuestLogTitle/C_DateAndTime etc. stay empty until this
        -- load-on-demand UI addon loads, which normally only happens when
        -- the player manually opens the quest log. Force it at login so
        -- the tracker works without that manual step.
        if IsAddOnLoaded and not IsAddOnLoaded("Blizzard_QuestLog") and LoadAddOn then
            LoadAddOn("Blizzard_QuestLog")
        end
        -- Some server builds only push full quest-log data to the client
        -- once the quest log UI itself is opened. Force a silent open/close
        -- so GetQuestLogTitle() etc. return real data before the player
        -- ever manually presses the questlog key.
        if _G.QuestLogFrame then
            local wasShown = _G.QuestLogFrame:IsShown()
            pcall(_G.QuestLogFrame.Show, _G.QuestLogFrame)
            if not wasShown then
                pcall(_G.QuestLogFrame.Hide, _G.QuestLogFrame)
            end
        end
        print("|cFF66CCFF[DailyTidies]|r Discovery mode loaded. Talk to the Orbs NPC and go through today's dailies once. /dtidy shows the copyable log.")
        return
    end

    if event == "GOSSIP_SHOW" then
        local npcName = (UnitExists("npc") and UnitName("npc")) or "?"
        AddLine("GOSSIP_SHOW npc=%s", npcName)

        if C_GossipInfo and C_GossipInfo.GetAvailableQuests then
            local avail = C_GossipInfo.GetAvailableQuests()
            for i, quest in ipairs(avail or {}) do
                dumpFields("GOSSIP_AVAILABLE[" .. i .. "]", quest)
                if quest.title and quest.questID then
                    titleToID[quest.title] = quest.questID
                    Learn(quest.questID, quest.title, quest.frequency)
                end
            end
        end

        if C_GossipInfo and C_GossipInfo.GetActiveQuests then
            local active = C_GossipInfo.GetActiveQuests()
            for i, quest in ipairs(active or {}) do
                dumpFields("GOSSIP_ACTIVE[" .. i .. "]", quest)
                if quest.title and quest.questID then
                    titleToID[quest.title] = quest.questID
                    Learn(quest.questID, quest.title, quest.frequency)
                end
            end
        end
        return
    end

    if event == "QUEST_DETAIL" then
        local title = GetTitleText()
        local objective = GetObjectiveText()
        local id = titleToID[title] or "?"
        AddLine("QUEST_DETAIL id=%s title=%s objective=%s", tostring(id), tostring(title), tostring(objective))
        if title and objective then
            pendingObjective[title] = objective
        end
        return
    end

    if event == "QUEST_PROGRESS" then
        local title = GetTitleText()
        local progress = GetProgressText()
        local id = titleToID[title] or "?"
        AddLine("QUEST_PROGRESS id=%s title=%s progress=%s", tostring(id), tostring(title), tostring(progress))
        return
    end

    if event == "QUEST_COMPLETE" then
        local title = GetTitleText()
        local id = titleToID[title] or "?"
        local money = GetRewardMoney and GetRewardMoney() or 0
        AddLine("QUEST_COMPLETE id=%s title=%s money=%s", tostring(id), tostring(title), tostring(money))

        if C_QuestLog and C_QuestLog.GetQuestLogRewardCurrencies then
            local currencies = C_QuestLog.GetQuestLogRewardCurrencies()
            for i, cur in ipairs(currencies or {}) do
                dumpFields("QUEST_COMPLETE_CURRENCY[" .. i .. "]", cur)
            end
        else
            for i = 1, 5 do
                local ok, name, texture, numItems = pcall(GetQuestLogRewardCurrencyInfo, i)
                if ok and name then
                    AddLine("QUEST_COMPLETE_CURRENCY[%d] name=%s amount=%s", i, tostring(name), tostring(numItems))
                end
            end
        end
        return
    end

    if event == "QUEST_ACCEPTED" then
        local questLogIndex, eventArgID = ...
        local title, frequency, logID

        if GetQuestLogTitle then
            local ok, t, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, freq, idFromLog =
                pcall(GetQuestLogTitle, questLogIndex)
            if ok then
                title = t
                frequency = freq
                logID = idFromLog
            end
        end

        AddLine("QUEST_ACCEPTED index=%s eventArgID=%s logID=%s title=%s frequency=%s",
            tostring(questLogIndex), tostring(eventArgID), tostring(logID), tostring(title), tostring(frequency))

        local bestID = logID or eventArgID
        if title and bestID then
            titleToID[title] = bestID
            Learn(bestID, title, frequency, pendingObjective[title])
        end
        return
    end

    if event == "QUEST_TURNED_IN" then
        local questID, xpReward, moneyReward = ...
        AddLine("QUEST_TURNED_IN id=%s xp=%s money=%s", tostring(questID), tostring(xpReward), tostring(moneyReward))
        Learn(questID, nil, nil)
        return
    end
end)

SLASH_DAILYTIDIES1 = "/dtidy"
SLASH_DAILYTIDIES2 = "/dailytidies"
SlashCmdList["DAILYTIDIES"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "log" then
        ToggleLogFrame()
    elseif msg == "clear" then
        wipe(DailyTidiesLogDB)
        if DailyTidiesLogEditBox then
            DailyTidiesLogEditBox:SetText("")
        end
        print("|cFF66CCFF[DailyTidies]|r Log cleared.")
    elseif DailyTidiesTracker and DailyTidiesTracker.Toggle then
        DailyTidiesTracker.Toggle()
    else
        ToggleLogFrame()
    end
end
