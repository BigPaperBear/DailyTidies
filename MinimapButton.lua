-- Daily Tidies -- minimap button.
-- Plain child of Minimap with a standard icon+border, deliberately NOT a
-- custom framework, so generic minimap-button collector addons (MBB and
-- similar) recognize and can gather it like any other minimap button.

DailyTidiesDB = DailyTidiesDB or {}
DailyTidiesDB.minimapAngle = DailyTidiesDB.minimapAngle or 220

local RADIUS = 80

local button = CreateFrame("Button", "DailyTidiesMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexture("Interface\\AddOns\\DailyTidies\\Textures\\orb_icon.blp")

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetPoint("TOPLEFT", 0, 0)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdatePosition()
    local angle = math.rad(DailyTidiesDB.minimapAngle or 220)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        DailyTidiesDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
        UpdatePosition()
    end)
end)

button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

button:SetScript("OnClick", function(self, mouseButton)
    if mouseButton == "RightButton" then
        if DailyTidiesSettings and DailyTidiesSettings.Toggle then
            DailyTidiesSettings.Toggle()
        end
    elseif DailyTidiesTracker and DailyTidiesTracker.Toggle then
        DailyTidiesTracker.Toggle()
    end
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Daily Tidies")
    GameTooltip:AddLine("Left-click: toggle the tracker", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

UpdatePosition()
