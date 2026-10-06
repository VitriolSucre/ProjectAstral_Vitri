
local PA = ProjectAstral
local WORLD = "World"

local suppressLeave = false

local function GetSlot()
    local id = GetChannelName(WORLD)
    return id or 0
end

local function BindToChatFrame()
    if GetSlot() == 0 then return end
    ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, WORLD)
end

local function JoinWorld()
    if GetSlot() > 0 then
        BindToChatFrame()
        return
    end
    -- hasVoice=0 mandatory — 1 crashes ChatFrame.lua format on later CHAT_MSG_CHANNEL_* (no voice subsystem)
    JoinPermanentChannel(WORLD, nil, DEFAULT_CHAT_FRAME:GetID(), 0)
end

local function LeaveWorld()
    if GetSlot() > 0 then LeaveChannelByName(WORLD) end
end

PA.JoinWorldChat  = JoinWorld
PA.LeaveWorldChat = LeaveWorld

local function After(seconds, fn)
    local f, t = CreateFrame("Frame"), 0
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t >= seconds then
            self:SetScript("OnUpdate", nil); self:Hide(); fn()
        end
    end)
end

local triedJoin = false
local function AttemptAutoJoin()
    if triedJoin then return end
    triedJoin = true
    After(5, function()
        if PA.Settings and PA.Settings.worldchatJoined then
            JoinWorld()
        end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        AttemptAutoJoin()
    elseif event == "CHAT_MSG_CHANNEL_NOTICE" then
        local kind = select(1, ...)
        local channelName = select(9, ...) or ""
        if channelName ~= WORLD then return end
        if kind == "YOU_LEFT" then
            if suppressLeave then
                suppressLeave = false
                return
            end
            if PA.SaveSetting then PA.SaveSetting("worldchatJoined", false) end
        elseif kind == "YOU_JOINED" then
            if PA.SaveSetting then PA.SaveSetting("worldchatJoined", true) end
            BindToChatFrame()
        end
    end
end)
