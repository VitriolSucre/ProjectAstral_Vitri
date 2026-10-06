
local ProjectAstral = ProjectAstral
local IG = {}

local SLOT_BUTTONS = {
    [1]  = "InspectHeadSlot",
    [2]  = "InspectNeckSlot",
    [3]  = "InspectShoulderSlot",
    [5]  = "InspectChestSlot",
    [6]  = "InspectWaistSlot",
    [7]  = "InspectLegsSlot",
    [8]  = "InspectFeetSlot",
    [9]  = "InspectWristSlot",
    [10] = "InspectHandsSlot",
    [11] = "InspectFinger0Slot",
    [12] = "InspectFinger1Slot",
    [13] = "InspectTrinket0Slot",
    [14] = "InspectTrinket1Slot",
    [15] = "InspectBackSlot",
    [16] = "InspectMainHandSlot",
    [17] = "InspectSecondaryHandSlot",
    [18] = "InspectRangedSlot",
}

local pending = {}

local function EnsureOverlays(btn)
    if btn._paGems then return btn._paGems end
    local pool = {}
    for i = 1, 4 do
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetSize(11, 11)
        if i == 1 then
            t:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 2)
        else
            t:SetPoint("LEFT", pool[i-1], "RIGHT", 1, 0)
        end
        t:Hide()
        pool[i] = t
    end
    btn._paGems = pool
    return pool
end

local function ResetSlot(slotId)
    local btnName = SLOT_BUTTONS[slotId]
    if not btnName then return end
    local btn = _G[btnName]
    if not btn or not btn._paGems then return end
    for i = 1, 4 do btn._paGems[i]:Hide() end
end

local function ExtractGems(link)
    if not link then return nil end
    local _, _, j1, j2, j3, j4 = link:find(
        "item:%-?%d+:%-?%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):")
    if not j1 then return nil end
    local gems = {}
    for i, v in ipairs({ j1, j2, j3, j4 }) do
        local n = tonumber(v)
        if n and n > 0 then gems[i] = n end
    end
    return gems
end

local function RenderSlot(slotId)
    local btnName = SLOT_BUTTONS[slotId]
    if not btnName then return end
    local btn = _G[btnName]
    if not btn then return end

    local link = GetInventoryItemLink("target", slotId)
    local gems = ExtractGems(link)
    local overlays = EnsureOverlays(btn)
    for i = 1, 4 do overlays[i]:Hide() end
    if not gems then return end

    local outIdx = 0
    for i = 1, 4 do
        local gemId = gems[i]
        if gemId then
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(gemId)
            if icon then
                outIdx = outIdx + 1
                local t = overlays[outIdx]
                t:SetTexture(icon)
                t:Show()
            else
                pending[gemId] = pending[gemId] or {}
                pending[gemId][slotId] = true
            end
        end
    end
end

local function RenderAll()
    if not InspectFrame or not InspectFrame:IsShown() then return end
    for slotId in pairs(SLOT_BUTTONS) do RenderSlot(slotId) end
end

local function ClearAll()
    for slotId in pairs(SLOT_BUTTONS) do ResetSlot(slotId) end
    pending = {}
end

local function PrimeItemCache(id)
    local probe = _G["PA_InspectGemsProbe"]
    if not probe then
        probe = CreateFrame("GameTooltip", "PA_InspectGemsProbe", UIParent, "GameTooltipTemplate")
        probe:SetOwner(UIParent, "ANCHOR_NONE")
        probe:Hide()
    end
    probe:ClearLines()
    probe:SetHyperlink("item:" .. id)
end

local function PrimeAll()
    for slotId in pairs(SLOT_BUTTONS) do
        local link = GetInventoryItemLink("target", slotId)
        local gems = ExtractGems(link)
        if gems then
            for i = 1, 4 do
                local id = gems[i]
                if id and not GetItemInfo(id) then PrimeItemCache(id) end
            end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("INSPECT_TALENT_READY")
f:RegisterEvent("UNIT_INVENTORY_CHANGED")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_TALENT_READY" or
       (event == "UNIT_INVENTORY_CHANGED" and arg1 == "target") then
        PrimeAll()
        RenderAll()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local gemId = arg1
        if not pending[gemId] then return end
        local slots = pending[gemId]
        pending[gemId] = nil
        for slotId in pairs(slots) do RenderSlot(slotId) end
    elseif event == "ADDON_LOADED" and arg1 == "Blizzard_InspectUI" then
        if InspectFrame then
            InspectFrame:HookScript("OnShow", function()
                PrimeAll()
                RenderAll()
            end)
            InspectFrame:HookScript("OnHide", ClearAll)
        end
        f:UnregisterEvent("ADDON_LOADED")
    end
end)

if InspectFrame then
    InspectFrame:HookScript("OnShow", function()
        PrimeAll()
        RenderAll()
    end)
    InspectFrame:HookScript("OnHide", ClearAll)
end

IG.version    = 3
IG.RenderAll  = RenderAll
IG.RenderSlot = RenderSlot
ProjectAstral.InspectGems = IG
