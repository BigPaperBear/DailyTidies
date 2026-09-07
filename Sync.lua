-- Daily Tidies -- peer sync.
-- Shares newly discovered Maerys quest data between players over a
-- dedicated hidden chat channel, so a new tier one player finds is
-- available to everyone else running the addon, without anyone needing
-- to hand-edit a seed list or wait for a new release.
--
-- SendAddonMessage(prefix, msg, "CHANNEL", id) raises "Unknown addon chat
-- type" on this client, so real addon messages over a channel aren't
-- available here. Other Ebonhold addons (RavioliFamilyActivityFinder)
-- work around this the same way: send a normal SendChatMessage over the
-- channel with a protocol prefix, and filter those lines out of the
-- visible chat frames.

DailyTidiesSync = {}

-- "|" is WoW's chat escape/color-code marker; SendChatMessage rejects any
-- message with a stray one. Use "~" everywhere in the protocol instead
-- (same "chat-safe" separator RavioliFamilyActivityFinder uses).
local PROTOCOL_PREFIX = "DTS~"
local SYNC_CHANNEL = "DailyTidiesSync"
local SEND_INTERVAL = 0.3 -- seconds between queued sends, avoids channel flood-drop

local sendQueue = {}
local sendElapsed = 0
local pendingSyncReplyAt = nil

-- Strip characters that would break SendChatMessage (the escape marker)
-- or our own field parsing (the field separator), just in case a future
-- quest title/objective contains either.
local function SanitizeField(text)
    if not text then
        return ""
    end
    return (text:gsub("[|~]", ""))
end

local function BuildAdd(id, entry)
    return string.format("ADD~%d~%s~%s~%s",
        id,
        entry.frequency == 1 and "1" or "",
        SanitizeField(entry.title),
        SanitizeField(entry.objective))
end

local function QueueSend(msg)
    table.insert(sendQueue, msg)
end

local function GetSyncChannelID()
    local id = GetChannelName(SYNC_CHANNEL)
    return (id and id > 0) and id or nil
end

local function EnsureChannelJoined()
    if not GetSyncChannelID() then
        if JoinChannelByName then
            local chatFrameID = DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.GetID and DEFAULT_CHAT_FRAME:GetID() or 1
            pcall(JoinChannelByName, SYNC_CHANNEL, nil, chatFrameID)
        end
    end
    -- This channel only ever carries addon protocol messages, never
    -- anything a player would want to read, so keep it off the chat tabs.
    if ChatFrame_RemoveChannel then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local frame = _G["ChatFrame" .. i]
            if frame then
                pcall(ChatFrame_RemoveChannel, frame, SYNC_CHANNEL)
            end
        end
    end
end

-- Belt-and-suspenders: even with the channel removed from every chat tab,
-- filter any protocol line that still tries to render.
local function ProtocolChatFilter(self, event, message, ...)
    if type(message) == "string" and message:sub(1, #PROTOCOL_PREFIX) == PROTOCOL_PREFIX then
        return true -- suppress
    end
end
if ChatFrame_AddMessageEventFilter then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ProtocolChatFilter)
end

-- Called by Discovery.lua whenever a genuinely new quest is learned from
-- this player's own play. Queue it for broadcast so any other online
-- player picks it up right away.
function DailyTidiesSync.OnLocalLearn(id, entry)
    QueueSend(BuildAdd(id, entry))
end

local function HandleAdd(message)
    local _, idStr, freqStr, title, objective = strsplit("~", message, 5)
    local id = tonumber(idStr)
    if not id or not title or title == "" then
        return
    end
    local frequency = (freqStr == "1") and 1 or nil
    if objective == "" then
        objective = nil
    end
    if DailyTidiesDiscovery and DailyTidiesDiscovery.Learn then
        DailyTidiesDiscovery.Learn(id, title, frequency, objective)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        EnsureChannelJoined()
        QueueSend("SYNCREQ") -- ask any peer already online to share what they know
        return
    end

    if event == "CHAT_MSG_CHANNEL" then
        local message, sender = ...
        if type(message) ~= "string" or message:sub(1, #PROTOCOL_PREFIX) ~= PROTOCOL_PREFIX then
            return
        end
        local payload = message:sub(#PROTOCOL_PREFIX + 1)

        local senderShort = strsplit("-", sender or "")
        if senderShort == UnitName("player") then
            return -- ignore our own broadcast, in case the server echoes it back
        end

        if payload == "SYNCREQ" then
            if not pendingSyncReplyAt then
                -- Stagger the reply so many peers don't all dump their
                -- full registry into the channel in the same instant.
                pendingSyncReplyAt = GetTime() + math.random() * 2
            end
        elseif string.sub(payload, 1, 4) == "ADD~" then
            HandleAdd(payload)
        end
        return
    end
end)

local sendTicker = CreateFrame("Frame")
sendTicker:SetScript("OnUpdate", function(self, dt)
    if pendingSyncReplyAt and GetTime() >= pendingSyncReplyAt then
        pendingSyncReplyAt = nil
        for id, entry in pairs(DailyTidiesDB.quests or {}) do
            QueueSend(BuildAdd(id, entry))
        end
    end

    if #sendQueue == 0 then
        return
    end
    sendElapsed = sendElapsed + dt
    if sendElapsed < SEND_INTERVAL then
        return
    end
    sendElapsed = 0

    local channelId = GetSyncChannelID()
    if not channelId then
        return -- channel not joined yet; retry next tick without dropping the message
    end
    local msg = table.remove(sendQueue, 1)
    SendChatMessage(PROTOCOL_PREFIX .. msg, "CHANNEL", nil, channelId)
end)
