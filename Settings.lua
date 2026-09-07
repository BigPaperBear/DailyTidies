-- Daily Tidies -- Settings.
-- Right-click the minimap button to open. Controls auto-accept,
-- auto turn-in, and which quest chains get auto-picked at Maerys.

DailyTidiesSettings = {}

local frame, chainRows
local cbCounter = 0

local function CreateCheckbox(parent, getValue, setValue)
    cbCounter = cbCounter + 1
    local cb = CreateFrame("CheckButton", "DailyTidiesSettingsCB" .. cbCounter, parent, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    local text = _G[cb:GetName() .. "Text"]
    if text then
        text:SetFontObject(GameFontHighlightSmall)
        text:SetTextColor(0.85, 0.85, 0.85)
        cb.text = text
    end
    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked() and true or false)
    end)
    cb.getValue = getValue
    return cb
end

-- Every known chain title, daily first then weekly, deduped (a chain has
-- one row regardless of how many tiers we've learned for it).
local function collectChainTitles()
    local dailySeen, weeklySeen = {}, {}
    local daily, weekly = {}, {}
    for id, entry in pairs(DailyTidiesDB.quests or {}) do
        local title = entry.title
        if title then
            if entry.frequency == 1 then
                if not dailySeen[title] then
                    dailySeen[title] = true
                    table.insert(daily, { title = title, label = entry.display or title })
                end
            else
                if not weeklySeen[title] then
                    weeklySeen[title] = true
                    table.insert(weekly, { title = title, label = entry.display or title })
                end
            end
        end
    end
    table.sort(daily, function(a, b) return a.label < b.label end)
    table.sort(weekly, function(a, b) return a.label < b.label end)
    local all = {}
    for _, c in ipairs(daily) do table.insert(all, c) end
    for _, c in ipairs(weekly) do table.insert(all, c) end
    return all
end

local function RefreshChainList()
    local chains = collectChainTitles()
    for i, chain in ipairs(chains) do
        local row = chainRows[i]
        if not row then
            row = CreateCheckbox(frame.scrollChild, nil, nil)
            chainRows[i] = row
        end
        row.text:SetText(chain.label)
        row.getValue = function() return not (DailyTidiesDB.excludedTitles and DailyTidiesDB.excludedTitles[chain.title]) end
        row:SetScript("OnClick", function(self)
            DailyTidiesDB.excludedTitles = DailyTidiesDB.excludedTitles or {}
            DailyTidiesDB.excludedTitles[chain.title] = (not self:GetChecked()) or nil
        end)
        row:SetChecked(row.getValue())
        row:Show()
    end
    for i = #chains + 1, #chainRows do
        chainRows[i]:Hide()
    end
    return #chains
end

local function SaveFramePosition(f)
    local point, _, relativePoint, x, y = f:GetPoint(1)
    DailyTidiesDB.settingsFrame = DailyTidiesDB.settingsFrame or {}
    DailyTidiesDB.settingsFrame.point = point
    DailyTidiesDB.settingsFrame.relativePoint = relativePoint
    DailyTidiesDB.settingsFrame.x = x
    DailyTidiesDB.settingsFrame.y = y
end

local function CreateSettingsFrame()
    local f = CreateFrame("Frame", "DailyTidiesSettingsFrame", UIParent)
    f:SetSize(300, 420)

    local saved = DailyTidiesDB.settingsFrame
    if saved and saved.point then
        f:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
    else
        f:SetPoint("CENTER", -200, 0)
    end

    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
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
    title:SetText("|cFFE0B84DDaily Tidies|r Settings")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local autoAcceptCB = CreateCheckbox(f,
        function() return DailyTidiesDB.autoAcceptMaerys ~= false end,
        function(v) DailyTidiesDB.autoAcceptMaerys = v end)
    autoAcceptCB:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    autoAcceptCB.text:SetText("Auto-accept Maerys quests")

    local autoTurnInCB = CreateCheckbox(f,
        function() return DailyTidiesDB.autoTurnIn == true end,
        function(v) DailyTidiesDB.autoTurnIn = v end)
    autoTurnInCB:SetPoint("TOPLEFT", autoAcceptCB, "BOTTOMLEFT", 0, -2)
    autoTurnInCB.text:SetText("Auto turn-in")

    local chainsHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chainsHeader:SetPoint("TOPLEFT", autoTurnInCB, "BOTTOMLEFT", 4, -12)
    chainsHeader:SetText("|cFF9999FFAuto-accept these chains:|r")

    local scrollFrame = CreateFrame("ScrollFrame", "DailyTidiesSettingsScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", chainsHeader, "BOTTOMLEFT", -4, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 12)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local newScroll = self:GetVerticalScroll() - delta * 20
        newScroll = math.max(0, math.min(newScroll, self:GetVerticalScrollRange()))
        self:SetVerticalScroll(newScroll)
    end)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(250)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    chainRows = {}

    f:SetScript("OnShow", function()
        -- A checkbox's own OnShow doesn't fire just because its PARENT
        -- frame was shown (its own IsShown() never changed), so the saved
        -- value has to be re-applied here explicitly every time the
        -- settings window opens.
        autoAcceptCB:SetChecked(autoAcceptCB.getValue())
        autoTurnInCB:SetChecked(autoTurnInCB.getValue())

        local count = RefreshChainList()
        local prev = nil
        for i = 1, count do
            local row = chainRows[i]
            row:ClearAllPoints()
            if i == 1 then
                row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -2)
            else
                row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2)
            end
            prev = row
        end
        scrollChild:SetHeight(math.max(count * 22 + 8, 1))
    end)

    f:Hide()
    return f
end

function DailyTidiesSettings.Toggle()
    frame = frame or CreateSettingsFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        frame:Raise()
    end
end
