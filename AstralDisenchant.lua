
local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local NUM_SLOTS = 9
local COLS      = 3

local lastPickup = nil
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if not bag or not slot then return end
    lastPickup = {
        bag      = bag,
        slot     = slot,
        link     = GetContainerItemLink(bag, slot),
        itemID   = GetContainerItemID and GetContainerItemID(bag, slot) or nil,
    }
end)
hooksecurefunc("ClearCursor", function() lastPickup = nil end)

local lockedBagItems = {}

local function ContainerFrame_GetBag(frame)
    if not frame then return nil end
    return frame:GetID()
end

local function FindBagButton(bag, slot)
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf:GetID() == bag then
            local size = cf.size or GetContainerNumSlots(bag) or 16
            for s = 1, size do
                local btn = _G["ContainerFrame" .. i .. "Item" .. s]
                if btn and btn:GetID() == slot then
                    return btn
                end
            end
        end
    end
    return nil
end

local function ApplyDesatToBagButton(bag, slot, locked)
    local btn = FindBagButton(bag, slot)
    if not btn then return end

    if locked then
        SetItemButtonDesaturated(btn, 1, 0.4, 0.4, 0.4)
        local icon = _G[btn:GetName() .. "IconTexture"]
        if icon then icon:SetVertexColor(0.35, 0.35, 0.35) end
        local overlay = btn._astralLockOverlay
        if not overlay then
            overlay = btn:CreateTexture(nil, "OVERLAY")
            overlay:SetTexture("Interface\\Buttons\\WHITE8X8")
            overlay:SetVertexColor(0, 0, 0, 0.55)
            overlay:SetAllPoints(btn)
            btn._astralLockOverlay = overlay
        end
        overlay:Show()
    else
        SetItemButtonDesaturated(btn, nil)
        local icon = _G[btn:GetName() .. "IconTexture"]
        if icon then icon:SetVertexColor(1, 1, 1) end
        if btn._astralLockOverlay then btn._astralLockOverlay:Hide() end
    end
end

local function ApplyBagDesaturation(frame)
    if not frame then return end
    local bag = ContainerFrame_GetBag(frame)
    if not bag then return end
    local size = frame.size or GetContainerNumSlots(bag) or 16
    for s = 1, size do
        local btn = _G[frame:GetName() .. "Item" .. s]
        if btn then
            local clientSlot = btn:GetID()
            if lockedBagItems[bag .. ":" .. clientSlot] then
                SetItemButtonDesaturated(btn, 1, 0.4, 0.4, 0.4)
                local icon = _G[btn:GetName() .. "IconTexture"]
                if icon then icon:SetVertexColor(0.35, 0.35, 0.35) end
                local overlay = btn._astralLockOverlay
                if not overlay then
                    overlay = btn:CreateTexture(nil, "OVERLAY")
                    overlay:SetTexture("Interface\\Buttons\\WHITE8X8")
                    overlay:SetVertexColor(0, 0, 0, 0.55)
                    overlay:SetAllPoints(btn)
                    btn._astralLockOverlay = overlay
                end
                overlay:Show()
            else
                if btn._astralLockOverlay then btn._astralLockOverlay:Hide() end
            end
        end
    end
end

hooksecurefunc("ContainerFrame_Update", ApplyBagDesaturation)
if ContainerFrame_UpdateLocked then
    hooksecurefunc("ContainerFrame_UpdateLocked", ApplyBagDesaturation)
end

local function RefreshAllOpenBags()
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local cf = _G["ContainerFrame" .. i]
        if cf and cf:IsShown() then ApplyBagDesaturation(cf) end
    end
end

local bagEv = CreateFrame("Frame")
bagEv:RegisterEvent("BAG_UPDATE")
bagEv:SetScript("OnEvent", function() RefreshAllOpenBags() end)

-- Items saved in an equipment set (EquipmentSets.lua) are kept out of the table:
-- returns the first set's name, or nil.
local function SavedSetOf(bag, slot)
    local ES = PA.EquipmentSets
    if not (ES and ES.SetsWithBagItem) then return nil end
    return ES.SetsWithBagItem(bag, slot)[1]
end

local function RejectSetItem(setName)
    UIErrorsFrame:AddMessage("Astral Disenchant: this item is saved in your equipment set '"
        .. setName .. "'.", 1.0, 0.42, 0.42, 1.0)
end

local disenchantFrameRef   -- forward declaration; set in Build()
local disenchantSlotsRef   -- forward declaration; set in Build()
local SetSlotRef           -- forward-declared so drag-to-slot can call SetSlot

hooksecurefunc("PickupContainerItem", function(bag, slot)
    if not IsShiftKeyDown() then return end
    if not disenchantFrameRef or not disenchantFrameRef:IsShown() then return end
    if not CursorHasItem() then return end

    local texture, _, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
    if not texture then ClearCursor(); return end
    if not quality or quality < 2 or quality > 4 then
        UIErrorsFrame:AddMessage("Astral Disenchant: green / blue / purple only.",
            1.0, 0.80, 0.30, 1.0)
        ClearCursor()
        return
    end

    local setName = SavedSetOf(bag, slot)
    if setName then
        RejectSetItem(setName)
        ClearCursor()
        return
    end

    local itemId = GetContainerItemID and GetContainerItemID(bag, slot)
    if itemId then
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
        if not equipLoc or equipLoc == "" then
            UIErrorsFrame:AddMessage("Astral Disenchant: equippable items only.",
                1.0, 0.80, 0.30, 1.0)
            ClearCursor()
            return
        end
        if equipLoc == "INVTYPE_AMMO"
           or equipLoc == "INVTYPE_BAG"
           or equipLoc == "INVTYPE_QUIVER" then
            UIErrorsFrame:AddMessage("Astral Disenchant: not a weapon or armor piece.",
                1.0, 0.80, 0.30, 1.0)
            ClearCursor()
            return
        end
    end

    if disenchantSlotsRef then
        for _, s in ipairs(disenchantSlotsRef) do
            if s.ref and s.ref.bag == bag and s.ref.slot == slot then
                ClearCursor()
                return
            end
        end
    end

    local empty
    if disenchantSlotsRef then
        for _, s in ipairs(disenchantSlotsRef) do
            if not s.ref then empty = s; break end
        end
    end
    if not empty then
        UIErrorsFrame:AddMessage("Astral Disenchant: all 9 slots are full.",
            1.0, 0.80, 0.30, 1.0)
        ClearCursor()
        return
    end

    if SetSlotRef then
        SetSlotRef(empty, {
            bag    = bag,
            slot   = slot,
            link   = link,
            itemID = itemId,
        })
    end
    ClearCursor()
end)

local D = {}
PA.disenchant = D
-- D.OnServer(event, ...): set by DisenchantTab.lua to follow Result / Batch_end / Batch_fail

D.slots = {}

-- Item entries the server reports as crafted (Show payload, or a CRAFTED_ITEM
-- batch fail). One crafted item rejects the whole batch, so they never go in.
D.crafted = {}

local NOT_GEAR = { INVTYPE_AMMO = true, INVTYPE_BAG = true, INVTYPE_QUIVER = true }
-- What the table would do with this bag slot: "ok" (it can go in), "set" (saved in
-- an equipment set, kept out), "crafted" (the server rejects it), or nil (not a
-- green/blue/purple weapon or armor piece). Also returns set name, item id, link,
-- quality. Used by Auto Import and the hub's Disenchant tab (DisenchantTab.lua).
local function Classify(bag, slot)
    local texture, _, _, quality, _, _, link = GetContainerItemInfo(bag, slot)
    if not texture or not quality or quality < 2 or quality > 4 then return nil end
    local itemId = GetContainerItemID and GetContainerItemID(bag, slot)
    if not itemId then return nil end
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
    if not equipLoc or equipLoc == "" or NOT_GEAR[equipLoc] then return nil end
    if D.crafted[itemId] then return "crafted", nil, itemId, link, quality end
    local setName = SavedSetOf(bag, slot)
    if setName then return "set", setName, itemId, link, quality end
    return "ok", nil, itemId, link, quality
end
D.Classify = Classify

-- Sends one batch (9 items at most, the server's limit) of { bag =, slot = }.
function D.Submit(batch)
    if #batch == 0 or not (_G.AIO and _G.AIO.Handle) then return false end
    D.batchLoot = 0   -- gems/scrolls received this batch (for auto-deposit)
    _G.AIO.Handle("AstralDisenchantServer", "Submit", batch)
    return true
end

D.weights = { gem = 70, socket = 15, removal = 15 }

-- Auto-deposit (on by default): after a batch, gems and scrolls it gave you are moved
-- from your bags into the Gem Stash, same as the stash's Deposit All button.
local function AutoDepositEnabled()
    return not (PA.Settings and PA.Settings.disenchantAutoDeposit == false)
end

local function FormatWeightsLine(w)
    local sum = (w.gem or 0) + (w.socket or 0) + (w.removal or 0)
    if sum <= 0 then
        return "|cff9a9aa0Gem drop chance|r  |cffffffff100%|r"
    end
    local pctGem = math.floor((w.gem or 0) / sum * 100 + 0.5)
    return string.format("|cff9a9aa0Gem drop chance|r  |cffffffff%d%%|r", pctGem)
end

local function RefreshWeightsText()
    if D.weightsText then
        D.weightsText:SetText(FormatWeightsLine(D.weights))
    end
end

local frame

local SLOT_SIZE   = 60
local SLOT_GAP    = 8
local FRAME_W     = 360
local FRAME_H     = 496   -- +26 for the auto-deposit checkbox under the buttons

-- Astral look, matching the hub: flat dark panels, 1px outlines, white titles, and
-- the Gems tab's purple as the accent (no Blizzard dialog art).
local SOLID  = "Interface\\Buttons\\WHITE8X8"
local ACCENT = { 0.80, 0.55, 1.00 }

local function AstralChrome(f, withGlow)
    f:SetBackdrop({ bgFile = SOLID, tile = false,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    f:SetBackdropColor(unpack(UI.Nav.deep))
    if UI.Outline then UI.Outline(f, f, "BORDER", UI.Nav.edge, 1) end
    if withGlow then
        local band = f:CreateTexture(nil, "BACKGROUND")
        band:SetTexture(SOLID)
        band:SetPoint("TOPLEFT",  f, "TOPLEFT",   1, -1)
        band:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        band:SetHeight(110)
        band:SetGradientAlpha("VERTICAL", ACCENT[1], ACCENT[2], ACCENT[3], 0,
                                          ACCENT[1], ACCENT[2], ACCENT[3], 0.16)
    end
end

local function TitleFont(fs, size)
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    fs:SetTextColor(unpack(UI.Color.textTitle))
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

local function PaintSlotOutline(slot, c)
    for _, line in ipairs(slot._outline or {}) do
        line:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

local function ResolveItemIcon(entry)
    if not entry then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(entry)
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ClearSlot(slot)
    if slot.ref then
        local oldBag, oldSlot = slot.ref.bag, slot.ref.slot
        lockedBagItems[oldBag .. ":" .. oldSlot] = nil
        ApplyDesatToBagButton(oldBag, oldSlot, false)
    end
    slot.ref = nil
    slot.craftedRejected = nil
    if slot.craftedMark then slot.craftedMark:Hide() end
    slot.icon:SetTexture("")
    slot.resultText:SetText("")
    if slot.emptyMark then slot.emptyMark:Show() end
end

local function SetSlot(slot, ref)
    local setName = SavedSetOf(ref.bag, ref.slot)
    if setName then
        RejectSetItem(setName)
        return
    end
    if ref.itemID and D.crafted[ref.itemID] then
        UIErrorsFrame:AddMessage(
            "Astral Disenchant: crafted items cannot be disenchanted.",
            1.0, 0.42, 0.42, 1.0)
        return
    end
    if ref.itemID then
        local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(ref.itemID)
        if equipLoc == "INVTYPE_AMMO"
           or equipLoc == "INVTYPE_BAG"
           or equipLoc == "INVTYPE_QUIVER" then
            UIErrorsFrame:AddMessage(
                "Astral Disenchant: not a weapon or armor piece.",
                1.0, 0.42, 0.42, 1.0)
            return
        end
    end

    if D.slots then
        for _, s in ipairs(D.slots) do
            if s ~= slot and s.ref
               and s.ref.bag == ref.bag and s.ref.slot == ref.slot then
                UIErrorsFrame:AddMessage(
                    "Astral Disenchant: that item is already in the table.",
                    1.0, 0.42, 0.42, 1.0)
                return
            end
        end
    end

    if slot.ref then
        local oldBag, oldSlot = slot.ref.bag, slot.ref.slot
        lockedBagItems[oldBag .. ":" .. oldSlot] = nil
        ApplyDesatToBagButton(oldBag, oldSlot, false)
    end
    slot.craftedRejected = nil
    if slot.craftedMark then slot.craftedMark:Hide() end
    slot.ref = ref
    slot.icon:SetTexture(ResolveItemIcon(ref.itemID))
    slot.icon:SetVertexColor(1, 1, 1, 1)
    slot.resultText:SetText("")
    if slot.emptyMark then slot.emptyMark:Hide() end
    lockedBagItems[ref.bag .. ":" .. ref.slot] = true
    ApplyDesatToBagButton(ref.bag, ref.slot, true)
    RefreshAllOpenBags()
    if disenchantFrameRef then
        if disenchantFrameRef.disenchantBtn then
            local filled = 0
            for _, s in ipairs(disenchantSlotsRef) do
                if s.ref then filled = filled + 1 end
            end
            if filled > 0 then
                disenchantFrameRef.disenchantBtn:Enable()
                disenchantFrameRef.disenchantBtn:SetText("Disenchant (" .. filled .. ")")
            else
                disenchantFrameRef.disenchantBtn:Disable()
                disenchantFrameRef.disenchantBtn:SetText("Disenchant")
            end
        end
    end
end
SetSlotRef = SetSlot

local function CountFilled()
    local n = 0
    for _, s in ipairs(D.slots) do
        if s.ref then n = n + 1 end
    end
    return n
end

local function UpdateButtonState()
    if not frame or not frame.disenchantBtn then return end
    local filled = CountFilled()
    if filled == 0 then
        frame.disenchantBtn:Disable()
        frame.disenchantBtn:SetText("Disenchant")
    else
        frame.disenchantBtn:Enable()
        frame.disenchantBtn:SetText("Disenchant (" .. filled .. ")")
    end
end

local function CreateSlot(parent, idx)
    local b = CreateFrame("Button", "PAAstralDisenchantSlot" .. idx, parent)
    b:SetSize(SLOT_SIZE, SLOT_SIZE)
    b:SetBackdrop({ bgFile = SOLID, tile = false,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    b:SetBackdropColor(UI.Nav.panel[1], UI.Nav.panel[2], UI.Nav.panel[3], 0.95)
    b._outline = UI.Outline and UI.Outline(b, b, "BORDER", UI.Nav.edge, 1) or {}

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT",     b, "TOPLEFT",      4, -4)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4,  4)
    icon:SetTexture("")
    b.icon = icon

    local empty = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    empty:SetPoint("CENTER", b, "CENTER", 0, 1)
    empty:SetText("+")
    empty:SetTextColor(0.50, 0.50, 0.55, 0.50)
    b.emptyMark = empty

    local result = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    result:SetPoint("CENTER", b, "CENTER", 0, 0)
    result:SetText("")
    result:SetTextColor(0.55, 1.00, 0.55)
    result:SetShadowOffset(1, -1)
    result:SetShadowColor(0, 0, 0, 1)
    b.resultText = result

    local craftedMark = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    craftedMark:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    craftedMark:SetPoint("BOTTOM", b, "BOTTOM", 0, 4)
    craftedMark:SetText("CRAFTED")
    craftedMark:SetTextColor(1.00, 0.32, 0.28)
    craftedMark:SetShadowColor(0, 0, 0, 1)
    craftedMark:SetShadowOffset(1, -1)
    craftedMark:Hide()
    b.craftedMark = craftedMark

    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ClearSlot(self)
            UpdateButtonState()
            return
        end
        if CursorHasItem() and lastPickup then
            SetSlot(self, lastPickup)
            ClearCursor()
            lastPickup = nil
            UpdateButtonState()
        end
    end)

    b:RegisterForDrag("LeftButton")
    b:SetScript("OnReceiveDrag", function(self)
        if CursorHasItem() and lastPickup then
            SetSlot(self, lastPickup)
            ClearCursor()
            lastPickup = nil
            UpdateButtonState()
        end
    end)

    b:SetScript("OnEnter", function(self)
        PaintSlotOutline(self, ACCENT)
        if self.ref and self.ref.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.ref.link)
            if self.craftedRejected then
                GameTooltip:AddLine("Crafted item: cannot be disenchanted.", 1.00, 0.32, 0.28, true)
            end
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Empty slot")
            GameTooltip:AddLine("Pick up an item from your bag and click this slot.", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        PaintSlotOutline(self, self.craftedRejected and { 1.00, 0.32, 0.28 }
            or UI.Nav.edge)
        GameTooltip:Hide()
    end)

    return b
end

local function GetImportFilter()
    if not ProjectAstralSettings then ProjectAstralSettings = {} end
    if not ProjectAstralSettings.disenchantFilter then
        ProjectAstralSettings.disenchantFilter = {
            green  = true,
            blue   = true,
            purple = true,
        }
    end
    return ProjectAstralSettings.disenchantFilter
end

local function GetBagFilter()
    if not ProjectAstralSettings then ProjectAstralSettings = {} end
    if not ProjectAstralSettings.disenchantBagFilter then
        ProjectAstralSettings.disenchantBagFilter = {
            [0] = true,  -- backpack
            [1] = true,
            [2] = true,
            [3] = true,
            [4] = true,
        }
    end
    return ProjectAstralSettings.disenchantBagFilter
end

local function AutoImportItems()
    if not disenchantSlotsRef then return end

    local filter      = GetImportFilter()
    local bagFilter   = GetBagFilter()
    local allowQ      = {}
    if filter.green  then allowQ[2] = true end
    if filter.blue   then allowQ[3] = true end
    if filter.purple then allowQ[4] = true end

    local already = {}
    for _, s in ipairs(disenchantSlotsRef) do
        if s.ref then already[s.ref.bag .. ":" .. s.ref.slot] = true end
    end

    local function NextEmpty()
        for _, s in ipairs(disenchantSlotsRef) do
            if not s.ref then return s end
        end
        return nil
    end

    local imported = 0
    local skipped  = 0
    local inSets   = 0     -- items saved in an equipment set, left alone
    local lastBag = NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        if bagFilter[bag] ~= false then
        local numSlots = GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local empty = NextEmpty()
            if not empty then break end

            local kind, _, itemId, link, quality = Classify(bag, slot)
            if kind and allowQ[quality] and not already[bag .. ":" .. slot] then
                if kind == "crafted" then
                    skipped = skipped + 1
                elseif kind == "set" then
                    inSets = inSets + 1
                else
                    SetSlotRef(empty, {
                        bag    = bag,
                        slot   = slot,
                        link   = link,
                        itemID = itemId,
                    })
                    already[bag .. ":" .. slot] = true
                    imported = imported + 1
                end
            end
        end
        end
        if not NextEmpty() then break end
    end

    if inSets > 0 then
        UIErrorsFrame:AddMessage(string.format(
            "Astral Disenchant: kept %d item%s saved in your equipment sets.",
            inSets, inSets == 1 and "" or "s"),
            1.0, 0.80, 0.30, 1.0)
    end
    if imported == 0 and skipped > 0 then
        UIErrorsFrame:AddMessage(
            "Astral Disenchant: only crafted items found, they cannot be disenchanted.",
            1.0, 0.80, 0.30, 1.0)
    elseif imported == 0 and inSets == 0 then
        UIErrorsFrame:AddMessage(
            "Astral Disenchant: no matching items in bags (check filter).",
            1.0, 0.80, 0.30, 1.0)
    elseif skipped > 0 then
        UIErrorsFrame:AddMessage(string.format(
            "Astral Disenchant: skipped %d crafted item%s.",
            skipped, skipped == 1 and "" or "s"),
            1.0, 0.80, 0.30, 1.0)
    end
end

local function Build()
    if frame then return end

    frame = CreateFrame("Frame", "ProjectAstralAstralDisenchant", UIParent)
    frame.__paUnified = true   -- unified look: Theme.lua keeps its navy
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    AstralChrome(frame, true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local hdrBadge = CreateFrame("Frame", nil, frame)
    hdrBadge:SetSize(44, 44)
    hdrBadge:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -18)
    hdrBadge:SetBackdrop({ bgFile = SOLID, tile = false,
                           insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    hdrBadge:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 1))
    if UI.Outline then UI.Outline(hdrBadge, hdrBadge, "BORDER", ACCENT, 0.8) end

    local hdrIcon = hdrBadge:CreateTexture(nil, "ARTWORK")
    hdrIcon:SetTexture("Interface\\Icons\\INV_Enchant_DustIllusion")
    hdrIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    hdrIcon:SetPoint("TOPLEFT",     hdrBadge, "TOPLEFT",      4, -4)
    hdrIcon:SetPoint("BOTTOMRIGHT", hdrBadge, "BOTTOMRIGHT", -4,  4)

    local title = frame:CreateFontString(nil, "OVERLAY")
    TitleFont(title, 18)
    title:SetPoint("TOPLEFT", hdrBadge, "TOPRIGHT", 12, -3)
    title:SetText("The Astral Table")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    sub:SetText("Shift + left-click items in your bag to add them here.")
    sub:SetTextColor(unpack(UI.Nav.muted))

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(close)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    frame.tierLink = nil

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(UI.Nav.edgeMid[1], UI.Nav.edgeMid[2], UI.Nav.edgeMid[3], 1)
    rule:SetPoint("TOPLEFT",  frame, "TOPLEFT",  20, -76)
    rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -76)
    rule:SetHeight(1)

    local gridW = COLS * SLOT_SIZE + (COLS - 1) * SLOT_GAP
    local gridStartX = math.floor((FRAME_W - gridW) / 2)

    for i = 1, NUM_SLOTS do
        local row = math.floor((i - 1) / COLS)
        local col = (i - 1) % COLS
        local slot = CreateSlot(frame, i)
        slot:SetPoint("TOPLEFT", frame, "TOPLEFT",
            gridStartX + col * (SLOT_SIZE + SLOT_GAP),
            -(96 + row * (SLOT_SIZE + SLOT_GAP)))
        ClearSlot(slot)
        D.slots[i] = slot
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 158)
    hint:SetTextColor(unpack(UI.Color.textPrimary))
    frame.weightsText = hint
    D.weightsText = hint
    RefreshWeightsText()

    local tip = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tip:SetPoint("BOTTOM", frame, "BOTTOM", 0, 140)
    tip:SetText("If your bags fill, rewards arrive by mail.")
    tip:SetTextColor(unpack(UI.Nav.muted))

    local SMALL_W = 100
    local BIG_W   = 160
    local BTN_H   = 28
    local BTN_GAP = 8
    local ROW1_Y  = 106
    local ROW2_Y  = 70
    local LEFT_X  = math.floor((FRAME_W - (BIG_W + BTN_GAP + SMALL_W)) / 2)

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(btn)
    btn:SetSize(BIG_W, BTN_H)
    btn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, ROW1_Y)
    btn:SetText("Disenchant")
    btn:SetScript("OnClick", function()
        local batch = {}
        for _, s in ipairs(D.slots) do
            if s.ref then
                batch[#batch + 1] = { bag = s.ref.bag, slot = s.ref.slot }
            end
        end
        if #batch == 0 then return end
        if D.Submit(batch) then
            btn:Disable()
            btn:SetText("Disenchanting...")
        else
            UIErrorsFrame:AddMessage(
                "Astral Disenchant: connection not ready. Try /reload.",
                1.0, 0.42, 0.42, 1.0)
        end
    end)
    btn:Disable()
    frame.disenchantBtn = btn

    local tierBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(tierBtn)
    tierBtn:SetSize(SMALL_W, BTN_H)
    tierBtn:SetPoint("LEFT", btn, "RIGHT", BTN_GAP, 0)
    tierBtn:SetText("View tier table")
    tierBtn:SetScript("OnClick", function()
        if not frame.tierPopup then return end
        if frame.tierPopup:IsShown() then frame.tierPopup:Hide()
        else frame.tierPopup:Show() end
    end)
    frame.tierLink = tierBtn

    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(importBtn)
    importBtn:SetSize(BIG_W, BTN_H)
    importBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X, ROW2_Y)
    importBtn:SetText("Auto Import Items")
    importBtn:SetScript("OnClick", function() AutoImportItems() end)
    frame.importBtn = importBtn

    local filterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(filterBtn)
    filterBtn:SetSize(SMALL_W, BTN_H)
    filterBtn:SetPoint("LEFT", importBtn, "RIGHT", BTN_GAP, 0)
    filterBtn:SetText("Filter")
    filterBtn:SetScript("OnClick", function()
        if not frame.filterPopup then return end
        if frame.filterPopup:IsShown() then frame.filterPopup:Hide()
        else frame.filterPopup:Show() end
    end)
    frame.filterBtn = filterBtn

    local depositChk = CreateFrame("CheckButton", "ProjectAstralAstralDisenchantAutoDeposit",
        frame, "OptionsCheckButtonTemplate")
    depositChk:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", LEFT_X - 4, 18)
    local depositTxt = _G[depositChk:GetName() .. "Text"]
    if depositTxt then
        depositTxt:SetText("Auto-deposit gems into Gem Stash")
        depositTxt:SetTextColor(unpack(UI.Color.textPrimary))
    end
    depositChk.tooltipText = "After each disenchant, the gems and scrolls you receive are moved from your bags into your Gem Stash. "
        .. "Rewards sent to your mail (full bags) stay in the mail."
    depositChk:SetChecked(AutoDepositEnabled())
    depositChk:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if PA.SaveSetting then
            PA.SaveSetting("disenchantAutoDeposit", on)
        else
            ProjectAstralSettings = ProjectAstralSettings or {}
            ProjectAstralSettings.disenchantAutoDeposit = on
        end
    end)
    frame.autoDepositCheck = depositChk

    tinsert(UISpecialFrames, "ProjectAstralAstralDisenchant")

    disenchantFrameRef = frame
    disenchantSlotsRef = D.slots
    local POP_W = 300
    local POP_H = 200
    local pop = CreateFrame("Frame", "ProjectAstralAstralDisenchantTierPopup", frame)
    pop:SetSize(POP_W, POP_H)
    pop:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)
    pop:SetFrameStrata("HIGH")
    AstralChrome(pop)
    pop:Hide()
    frame.tierPopup = pop

    local popTitle = pop:CreateFontString(nil, "OVERLAY")
    TitleFont(popTitle, 14)
    popTitle:SetPoint("TOP", pop, "TOP", 0, -16)
    popTitle:SetText("Reward Tier Table")

    local COL_X  = { 22, 110, 180, 244 }
    local ROW_Y  = -52
    local ROW_DY = -30

    local superHeader = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    superHeader:SetPoint("TOP", pop, "TOPLEFT",
        (COL_X[2] + COL_X[4] + 32) / 2, ROW_Y + 16)
    superHeader:SetText("itemlevel")
    superHeader:SetTextColor(unpack(UI.Color.textAccent))
    superHeader:SetShadowOffset(1, -1)
    superHeader:SetShadowColor(0, 0, 0, 1)

    local function MakeColHeader(colIdx, txt)
        local fs = pop:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", pop, "TOPLEFT", COL_X[colIdx], ROW_Y)
        fs:SetText(txt)
        fs:SetTextColor(unpack(UI.Nav.muted))
    end
    MakeColHeader(2, "1-105")
    MakeColHeader(3, "106-160")
    MakeColHeader(4, "161+")

    local function MakeRow(rowIdx, qualityLabel, qualityColor, tiers, fallbacks)
        local yOff = ROW_Y + rowIdx * ROW_DY
        if rowIdx % 2 == 1 then
            local stripe = pop:CreateTexture(nil, "BACKGROUND")
            stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
            stripe:SetVertexColor(1, 1, 1, 0.04)
            stripe:SetPoint("LEFT", pop, "TOPLEFT",  18, yOff + 2)
            stripe:SetSize(POP_W - 36, math.abs(ROW_DY) - 4)
        end
        local q = pop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        q:SetPoint("LEFT", pop, "TOPLEFT", COL_X[1], yOff)
        q:SetText(qualityLabel)
        q:SetTextColor(qualityColor[1], qualityColor[2], qualityColor[3])
        q:SetShadowOffset(1, -1)
        q:SetShadowColor(0, 0, 0, 1)
        for col = 1, 3 do
            local txt = pop:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            txt:SetPoint("LEFT", pop, "TOPLEFT", COL_X[col + 1], yOff)
            txt:SetText(tiers[col])
            if fallbacks[col] then
                txt:SetTextColor(0.35, 0.45, 0.55)
            else
                txt:SetTextColor(unpack(UI.Color.textTitle))
            end
            txt:SetShadowOffset(1, -1)
            txt:SetShadowColor(0, 0, 0, 1)
        end
    end

    local greenColor  = { 0.12, 1.00, 0.00 }
    local blueColor   = { 0.00, 0.44, 0.87 }
    local purpleColor = { 0.78, 0.40, 1.00 }

    MakeRow(1, "Green",  greenColor,  { "T1", "T2", "T3" }, { false, false, false })
    MakeRow(2, "Blue",   blueColor,   { "T1", "T2", "T3" }, { false, false, false })
    MakeRow(3, "Purple", purpleColor, { "T1", "T2", "T3" }, { false, false, false })
    local FPOP_W = 180
    local FPOP_H = 290
    local fpop = CreateFrame("Frame", "ProjectAstralAstralDisenchantFilterPopup", frame)
    fpop:SetSize(FPOP_W, FPOP_H)
    fpop:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, 0)
    fpop:SetFrameStrata("HIGH")
    AstralChrome(fpop)
    fpop:Hide()
    frame.filterPopup = fpop

    local fpopTitle = fpop:CreateFontString(nil, "OVERLAY")
    TitleFont(fpopTitle, 14)
    fpopTitle:SetPoint("TOP", fpop, "TOP", 0, -16)
    fpopTitle:SetText("Import Filter")

    local qLabel = fpop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    qLabel:SetPoint("TOPLEFT", fpop, "TOPLEFT", 18, -42)
    qLabel:SetText("Quality")
    qLabel:SetTextColor(unpack(UI.Nav.muted))
    qLabel:SetShadowOffset(1, -1)
    qLabel:SetShadowColor(0, 0, 0, 1)

    local function MakeQualityCheckbox(name, label, color, yOff)
        local chk = CreateFrame("CheckButton",
            "ProjectAstralAstralDisenchantFilter" .. name,
            fpop, "OptionsCheckButtonTemplate")
        chk:SetPoint("TOPLEFT", fpop, "TOPLEFT", 20, yOff)
        local txt = _G[chk:GetName() .. "Text"]
        if txt then
            txt:SetText(label)
            txt:SetTextColor(color[1], color[2], color[3])
            txt:SetShadowOffset(1, -1)
            txt:SetShadowColor(0, 0, 0, 1)
        end
        local sv = GetImportFilter()
        chk:SetChecked(sv[name:lower()] and true or false)
        chk:SetScript("OnClick", function(self)
            local f = GetImportFilter()
            f[name:lower()] = self:GetChecked() and true or false
        end)
        return chk
    end

    MakeQualityCheckbox("Green",  "Green",  { 0.12, 1.00, 0.00 }, -60)
    MakeQualityCheckbox("Blue",   "Blue",   { 0.00, 0.60, 1.00 }, -82)
    MakeQualityCheckbox("Purple", "Purple", { 0.78, 0.40, 1.00 }, -104)

    local bLabel = fpop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bLabel:SetPoint("TOPLEFT", fpop, "TOPLEFT", 18, -138)
    bLabel:SetText("Bags")
    bLabel:SetTextColor(unpack(UI.Nav.muted))
    bLabel:SetShadowOffset(1, -1)
    bLabel:SetShadowColor(0, 0, 0, 1)

    local function MakeBagCheckbox(bagIdx, label, yOff)
        local chk = CreateFrame("CheckButton",
            "ProjectAstralAstralDisenchantBagFilter" .. bagIdx,
            fpop, "OptionsCheckButtonTemplate")
        chk:SetPoint("TOPLEFT", fpop, "TOPLEFT", 20, yOff)
        local txt = _G[chk:GetName() .. "Text"]
        if txt then
            txt:SetText(label)
            txt:SetTextColor(unpack(UI.Color.textPrimary))
            txt:SetShadowOffset(1, -1)
            txt:SetShadowColor(0, 0, 0, 1)
        end
        local sv = GetBagFilter()
        chk:SetChecked(sv[bagIdx] ~= false)
        chk:SetScript("OnClick", function(self)
            local f = GetBagFilter()
            f[bagIdx] = self:GetChecked() and true or false
        end)
        return chk
    end

    MakeBagCheckbox(0, "Backpack", -156)
    MakeBagCheckbox(1, "Bag 1",    -178)
    MakeBagCheckbox(2, "Bag 2",    -200)
    MakeBagCheckbox(3, "Bag 3",    -222)
    MakeBagCheckbox(4, "Bag 4",    -244)

    -- Astral check boxes (filter + auto-deposit) and any other template widgets
    if UI.SkinTree then UI.SkinTree(frame) end
end

local function FindSlotByBagSlot(bag, slot)
    for _, s in ipairs(D.slots) do
        if s.ref and s.ref.bag == bag and s.ref.slot == slot then
            return s
        end
    end
    return nil
end

local function MarkCraftedSlot(slot)
    if not slot then return end
    if slot.ref and slot.ref.itemID then D.crafted[slot.ref.itemID] = true end
    slot.craftedRejected = true
    if slot.craftedMark then slot.craftedMark:Show() end
    PaintSlotOutline(slot, { 1.00, 0.32, 0.28 })
end

local OUTCOME_LABEL = {
    GEM       = "GEM!",
    SCROLL_1  = "SOCKET",
    SCROLL_2  = "REMOVAL",
    LOST      = "LOST",
}
local OUTCOME_COLOR = {
    GEM       = { 1.00, 0.85, 0.30 },
    SCROLL_1  = { 0.55, 1.00, 0.85 },
    SCROLL_2  = { 0.55, 0.85, 1.00 },
    LOST      = { 1.00, 0.42, 0.42 },
}

local function FlashSlotResult(slot, outcome, entry, tier)
    local label = OUTCOME_LABEL[outcome] or outcome
    local col   = OUTCOME_COLOR[outcome] or { 1, 1, 1 }
    if slot.ref then
        lockedBagItems[slot.ref.bag .. ":" .. slot.ref.slot] = nil
    end
    slot.icon:SetTexture(ResolveItemIcon(entry))
    slot.icon:SetVertexColor(1, 1, 1, 1)
    if slot.emptyMark then slot.emptyMark:Hide() end
    if outcome == "GEM" and tier and tier > 0 then
        slot.resultText:SetText("|cffFFD700T" .. tier .. "|r")
    else
        slot.resultText:SetText(string.format("|cff%02x%02x%02x%s|r",
            math.floor(col[1] * 255), math.floor(col[2] * 255), math.floor(col[3] * 255), label))
    end
end

local function FinishBatch(mailedCount)
    if not frame then return end
    if mailedCount and mailedCount > 0 then
        UIErrorsFrame:AddMessage(string.format(
            "Astral Disenchant: %d reward%s sent to mail (bags full).",
            mailedCount, mailedCount == 1 and "" or "s"),
            1.00, 0.85, 0.30, 1.0)
    end
    local timer = CreateFrame("Frame")
    local acc   = 0
    timer:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 2.0 then return end
        self:SetScript("OnUpdate", nil)
        for _, s in ipairs(D.slots) do ClearSlot(s) end
        frame.disenchantBtn:SetText("Disenchant")
        UpdateButtonState()
    end)
end

local function DepositLootSoon()
    local timer = CreateFrame("Frame")
    local acc   = 0
    timer:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc < 1.0 then return end   -- let the rewards land in the bags first
        self:SetScript("OnUpdate", nil)
        SendChatMessage(".astralstash depositall", "SAY")
        -- refresh stash counts; the stock update also lets Auto Fuse run if it's on
        if PA.GemStash and PA.GemStash.DelayedRequestState then
            PA.GemStash.DelayedRequestState(800)
        end
    end)
end

local function RegisterAstralDisenchantHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralDisenchant", {})

    ClientHandler.Show = function(_, payload)
        payload = payload or {}
        D.weights.gem     = tonumber(payload.gem)     or D.weights.gem
        D.weights.socket  = tonumber(payload.socket)  or D.weights.socket
        D.weights.removal = tonumber(payload.removal) or D.weights.removal
        if type(payload.crafted) == "table" then
            for _, entry in ipairs(payload.crafted) do
                entry = tonumber(entry)
                if entry then D.crafted[entry] = true end
            end
        end
        Build()
        RefreshWeightsText()
        if frame then frame:Show() end
    end

    ClientHandler.Result = function(_, bagSlot, kind, entry, tier)
        if D.OnServer then D.OnServer("Result", bagSlot, kind, entry, tier) end
        if kind == "GEM" or kind == "SCROLL_1" or kind == "SCROLL_2" then
            D.batchLoot = (D.batchLoot or 0) + 1
        end
        bagSlot = tostring(bagSlot or "")
        local b, s = bagSlot:match("^(%d+):(%d+)$")
        if not b then return end
        local slot = FindSlotByBagSlot(tonumber(b), tonumber(s))
        if slot then
            FlashSlotResult(slot, kind or "LOST", tonumber(entry) or 0, tonumber(tier) or 0)
        end
    end

    ClientHandler.Batch_end = function(_, mailedCount)
        if D.OnServer then D.OnServer("Batch_end", mailedCount) end
        FinishBatch(tonumber(mailedCount) or 0)
        if (D.batchLoot or 0) > 0 and AutoDepositEnabled() then
            DepositLootSoon()
        end
        D.batchLoot = 0
    end

    ClientHandler.Batch_fail = function(_, bagSlot, reason)
        if D.OnServer then D.OnServer("Batch_fail", bagSlot, reason) end
        local reasonStr = ({
            NOT_FOUND      = "Item missing from that slot.",
            BAD_QUALITY    = "Only green / blue / purple items.",
            NOT_EQUIPPABLE = "Equippable items only.",
            CRAFTED_ITEM   = "Crafted items cannot be disenchanted.",
            EMPTY          = "Nothing in the disenchanter.",
            OVERSIZED      = "Too many items (max 9).",
            INV_FULL       = "Inventory full.",
            DUPLICATE      = "Same item placed in multiple slots.",
            MOVED          = "An item was moved out of place mid-batch.",
            DISABLED       = "Astral Disenchant is disabled on this realm.",
        })[reason] or ("Batch rejected: " .. tostring(reason))
        if reason == "CRAFTED_ITEM" then
            local bag, slotIndex = tostring(bagSlot or ""):match("^(%d+):(%d+)$")
            if bag and slotIndex then
                MarkCraftedSlot(FindSlotByBagSlot(tonumber(bag), tonumber(slotIndex)))
            end
        end
        UIErrorsFrame:AddMessage("Astral Disenchant: " .. reasonStr,
            1.0, 0.42, 0.42, 1.0)
        if frame and frame.disenchantBtn then
            frame.disenchantBtn:SetText("Disenchant")
            UpdateButtonState()
        end
    end

    return true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    if RegisterAstralDisenchantHandlers() then
        self:UnregisterAllEvents()
    end
end)
