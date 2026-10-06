-- 3.3.5a's GetItemInfo silently fails on uncached IDs — no client-side retry.

local PA = ProjectAstral
local IC = {}
PA.ItemCache = IC

local prefetchTip
local registered = {}
local resolved   = {}
local subscribers = {}

local function EnsureTip()
    if prefetchTip then return end
    prefetchTip = CreateFrame("GameTooltip", "PA_ItemCacheTooltip",
                              UIParent, "GameTooltipTemplate")
    prefetchTip:SetOwner(UIParent, "ANCHOR_NONE")
end

local function HasIconCached(entry)
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry)
    return texture ~= nil
end

local prefetchQueue = {}
local PREFETCH_BATCH   = 30
local PREFETCH_INTERVAL = 0.05

local function DoActualPrefetch(entry)
    EnsureTip()
    prefetchTip:ClearLines()
    prefetchTip:SetHyperlink("item:" .. entry .. ":0:0:0:0:0:0:0:0")
    prefetchTip:Hide()
end

local prefetchTicker
local function EnsurePrefetchTicker()
    if prefetchTicker then return end
    prefetchTicker = CreateFrame("Frame")
    prefetchTicker:Hide()
    local acc = 0
    prefetchTicker:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc < PREFETCH_INTERVAL then return end
        acc = 0
        local processed = 0
        while processed < PREFETCH_BATCH and #prefetchQueue > 0 do
            local entry = table.remove(prefetchQueue, 1)
            if entry and not HasIconCached(entry) then
                DoActualPrefetch(entry)
            elseif entry then
                resolved[entry] = true
            end
            processed = processed + 1
        end
        if #prefetchQueue == 0 then
            self:Hide()
        end
    end)
end

function IC.Register(entry)
    if type(entry) ~= "number" or entry <= 0 then return end
    if registered[entry] then return end
    registered[entry] = true
    if HasIconCached(entry) then
        resolved[entry] = true
        return
    end
    DoActualPrefetch(entry)
end

function IC.RegisterMany(list)
    if type(list) ~= "table" then return end
    local queued = 0
    for _, e in ipairs(list) do
        if type(e) == "number" and e > 0 and not registered[e] then
            registered[e] = true
            if HasIconCached(e) then
                resolved[e] = true
            else
                prefetchQueue[#prefetchQueue + 1] = e
                queued = queued + 1
            end
        end
    end
    if queued > 0 then
        EnsurePrefetchTicker()
        prefetchTicker:Show()
    end
end

function IC.IsRegistered(entry)
    return registered[entry] == true
end

function IC.Subscribe(fn)
    if type(fn) == "function" then subscribers[#subscribers + 1] = fn end
end

local function Notify(entry)
    for _, fn in ipairs(subscribers) do
        pcall(fn, entry)
    end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
evt:SetScript("OnEvent", function(_, _, itemId)
    if not itemId then return end
    if not registered[itemId] then return end
    if resolved[itemId] then return end
    resolved[itemId] = true
    Notify(itemId)
end)
