
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end

local AT = PA.AT
if not AT then return end

local pendingLabel = nil
function AT.SendLoadBuildAIO(removeIds, addIds, label)
    pendingLabel = label
    AIO.Handle("AstralTreeServer", "LoadBuild",
               removeIds or {},
               addIds    or {})
end

local ClientHandler = AIO.AddHandlers("AstralTree", {})

ClientHandler.LoadBuildResult = function(_, status, nAdded, nRemoved, delta)
    local labelSuffix = pendingLabel and (" for " .. pendingLabel) or ""
    pendingLabel = nil

    if status == "OK" then
        SendChatMessage(".astral rebuild " .. tostring(delta or 0), "SAY")

        if AT.__lastLoadBuild then
            for _, id in ipairs(AT.__lastLoadBuild.remove or {}) do
                AT.unlocked[id] = nil
            end
            for _, id in ipairs(AT.__lastLoadBuild.add or {}) do
                AT.unlocked[id] = true
            end
            AT.__lastLoadBuild = nil
            if AT.RefreshNodes then AT.RefreshNodes() end
        end

        local msg = string.format("Build applied%s (+%d, -%d).",
                                  labelSuffix, nAdded or 0, nRemoved or 0)
        DEFAULT_CHAT_FRAME:AddMessage("|cffcc99ff[Astral]|r " .. msg)

    elseif status == "INSUFFICIENT" then
        local have, need = nAdded or 0, nRemoved or 0
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cffff5555[Astral]|r Not enough Tokens for this build: have %d, need %d.",
            have, need))
        AT.__lastLoadBuild = nil

    elseif status == "NOOP" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffcc99ff[Astral]|r Build already matches current state.")
        AT.__lastLoadBuild = nil
    end
end

function AT.SendUnlockAIO(nodeId)
    AIO.Handle("AstralTreeServer", "Unlock", nodeId)
end

function AT.SendUnlockBulkAIO(ids)
    AIO.Handle("AstralTreeServer", "UnlockBulk", ids or {})
end

function AT.SendRemoveAIO(nodeId)
    AIO.Handle("AstralTreeServer", "Remove", nodeId)
end

function AT.SendRemoveBulkAIO(ids)
    AIO.Handle("AstralTreeServer", "RemoveBulk", ids or {})
end

function AT.SendResetAllAIO()
    AIO.Handle("AstralTreeServer", "ResetAll")
end

local function TriggerRebuild(delta)
    SendChatMessage(".astral rebuild " .. tostring(delta or 0), "SAY")
end

local function Info(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc99ff[Astral]|r " .. string.format(fmt, ...))
end
local function Warn(fmt, ...)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[Astral]|r " .. string.format(fmt, ...))
end

ClientHandler.UnlockResult = function(_, status, nodeId, delta)
    if status == "OK" then
        AT.unlocked[nodeId] = true
        if AT.RefreshNodes then AT.RefreshNodes() end
        TriggerRebuild(delta or 0)
    elseif status == "NO_ITEM" then
        Warn("Not enough Tokens.")
    else
        Warn("Prerequisite not met.")
    end
end

ClientHandler.UnlockBulkResult = function(_, okList, failList, delta)
    if type(okList) == "table" and #okList > 0 then
        for _, id in ipairs(okList) do AT.unlocked[id] = true end
        if AT.RefreshNodes then AT.RefreshNodes() end
        TriggerRebuild(delta or 0)
    end
    if type(failList) == "table" and #failList > 0 then
        local noItem = 0
        for _, e in ipairs(failList) do
            if e.reason == "NO_ITEM" then noItem = noItem + 1 end
        end
        if noItem > 0 then
            Warn("Ran out of Tokens after %d node(s).", #okList or 0)
        end
    end
end

ClientHandler.RemoveResult = function(_, status, nodeId, delta)
    if status == "OK" then
        AT.unlocked[nodeId] = nil
        if AT.RefreshNodes then AT.RefreshNodes() end
        TriggerRebuild(delta or 0)
    elseif status == "HAS_DEPENDENTS" then
        Warn("Cannot remove: other unlocked nodes require this one as prerequisite.")
    else
        Warn("Cannot remove: node is not unlocked.")
    end
end

ClientHandler.RemoveBulkResult = function(_, okList, failList, delta)
    if type(okList) == "table" and #okList > 0 then
        for _, id in ipairs(okList) do AT.unlocked[id] = nil end
        if AT.RefreshNodes then AT.RefreshNodes() end
        TriggerRebuild(delta or 0)
    end
end

function AT.RequestStoreAIO()
    AIO.Handle("AstralTreeServer", "RequestStore")
end

ClientHandler.StoreData = function(_, payload)
    if PA.PrestigeStore and PA.PrestigeStore.ApplyStore then
        PA.PrestigeStore.ApplyStore(payload)
    end
end

ClientHandler.ResetAllResult = function(_, count, delta)
    if (count or 0) == 0 then
        Info("No nodes to reset.")
        return
    end
    for id in pairs(AT.unlocked) do AT.unlocked[id] = nil end
    if AT.RefreshNodes then AT.RefreshNodes() end
    TriggerRebuild(delta or 0)
    Info("Reset complete — %d node(s) removed.", count)
end

function AT.RequestInitialStateAIO()
    AIO.Handle("AstralTreeServer", "RequestInitialState")
end

function AT.RequestFullTreeAIO()
    AIO.Handle("AstralTreeServer", "RequestFullTree")
end

function AT.RequestParagonStateAIO()
    AIO.Handle("AstralTreeServer", "RequestParagonState")
end

function AT.SendBuyEntryAIO(entryId)
    AIO.Handle("AstralTreeServer", "BuyEntry", entryId)
end

function AT.SendSpendParagonAIO(stat, delta)
    AIO.Handle("AstralTreeServer", "SpendParagon", stat, delta)
end

function AT.SendDoParagonUpAIO()
    AIO.Handle("AstralTreeServer", "DoParagonUp")
end

ClientHandler.InitialState = function(_, payload)
    if type(payload) ~= "table" then return end
    AT.unlocked = AT.unlocked or {}
    for id in pairs(AT.unlocked) do AT.unlocked[id] = nil end
    for _, id in ipairs(payload.unlocked or {}) do
        AT.unlocked[id] = true
    end
    AT.tierCost   = payload.costs   or AT.tierCost   or {}
    AT.tierRefund = payload.refunds or AT.tierRefund or {}
    AT.dataVersion = payload.dataVersion or 0
    if AT.OnInitialStateApplied then AT.OnInitialStateApplied() end
    if AT.RefreshNodes then AT.RefreshNodes() end
end

ClientHandler.FullTree = function(_, payload)
    if type(payload) ~= "table" then return end
    if AT.ApplyFullTree then
        AT.ApplyFullTree(payload)
    end
end

ClientHandler.ParagonState = function(_, payload)
    if type(payload) ~= "table" then return end
    if PA.Paragon and PA.Paragon.ApplyState then
        PA.Paragon.ApplyState(payload)
    end
end

ClientHandler.BuyResult = function(_, status, entryId, arg2)
    if status == "OK" then
        SendChatMessage(".astral buy " .. tostring(entryId or 0), "SAY")
        if AT.RequestStoreAIO then AT.RequestStoreAIO() end
        Info("Purchase queued for entry %d.", entryId or 0)
    elseif status == "ALREADY_OWNED" then
        Warn("You already own this entry.")
    elseif status == "NEEDS_LEVEL" then
        Warn("Requires Prestige Level %d.", arg2 or 0)
    elseif status == "INSUFFICIENT" then
        Warn("Not enough Prestige Tokens (need %d).", arg2 or 0)
    else
        Warn("Purchase failed.")
    end
end

-- `.astral paragon spend` mutates cache + queues async DB UPDATE. Reading state
-- immediately loses the race — defer the AIO refresh so the UPDATE commits first.
local function ScheduleParagonRefresh()
    if not AT.RequestParagonStateAIO then return end
    if not AT._paragonRefreshTimer then
        AT._paragonRefreshTimer = CreateFrame("Frame")
    end
    local elapsed = 0
    AT._paragonRefreshTimer:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.25 then
            self:SetScript("OnUpdate", nil)
            AT.RequestParagonStateAIO()
        end
    end)
end

local PARAGON_STAT_FIELD = {
    str = "str", agi = "agi", sta = "sta", int = "intl", intl = "intl",
    spi = "spi", sp = "sp", ap = "ap",
}

ClientHandler.SpendParagonResult = function(_, status, stat, delta)
    if status == "OK" then
        SendChatMessage(string.format(".astral paragon spend %s %d",
                                       tostring(stat), tonumber(delta) or 0), "SAY")
        if PA.Paragon and PA.Paragon.state then
            local s = PA.Paragon.state
            local field = PARAGON_STAT_FIELD[tostring(stat)]
            local d = tonumber(delta) or 0
            if field and s[field] then
                s[field] = math.max(0, s[field] + d)
                s.available = math.max(0, (s.available or 0) - d)
                if PA.Paragon.Refresh then PA.Paragon.Refresh() end
            end
        end
        ScheduleParagonRefresh()
    elseif status == "BAD_STAT" then
        Warn("Invalid paragon stat: %s.", tostring(stat))
    elseif status == "NO_POINTS" then
        Warn("Not enough paragon points available.")
    elseif status == "BELOW_ZERO" then
        Warn("Cannot refund below zero.")
    end
end

ClientHandler.DoParagonUpResult = function(_, status, arg1, arg2)
    if status == "OK" then
        SendChatMessage(".astral paragon", "SAY")
        ScheduleParagonRefresh()
        Info("Paragon Level %d reached!", arg1 or 0)
    elseif status == "AT_CAP" then
        Warn("Already at paragon cap (%d).", arg2 or 0)
    elseif status == "NOT_READY" then
        Warn("Not enough Prestige Tokens (need %d).", arg2 or 0)
    end
end
