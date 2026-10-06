
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local lastPickup = nil
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if not bag or not slot then return end
    lastPickup = {
        bag    = bag,
        slot   = slot,
        link   = GetContainerItemLink(bag, slot),
        itemID = GetContainerItemID and GetContainerItemID(bag, slot) or nil,
    }
end)
hooksecurefunc("ClearCursor", function() lastPickup = nil end)

local FRAME_W    = 340
local FRAME_H    = 420   -- room for the affix stats under the item
local SLOT_SIZE  = 64

-- 2026-09-06 fix (poison/imbue replace-enchant taint bug):
-- The previous line here was:
--     StaticPopupDialogs = StaticPopupDialogs or {}
-- That is a GLOBAL re-assignment from insecure addon code. WoW's taint
-- system flags the global `StaticPopupDialogs` variable as tainted from
-- that moment onward. Blizzard's secure StaticPopup_Show later reads
-- StaticPopupDialogs["REPLACE_ENCHANT"] to render the "replace existing
-- enchant?" confirmation popup for poisons + shaman weapon imbues. The
-- read inherits the taint -> the popup's OnAccept function reference is
-- tainted -> when the user clicks Yes, the call to ReplaceEnchant()
-- (protected) is refused with "ProjectAstral has been blocked from an
-- action only available to the Blizzard UI".
--
-- Blizzard's FrameXML (Interface/FrameXML/StaticPopup.lua) defines the
-- StaticPopupDialogs global unconditionally at client load time, well
-- before any addon runs. The defensive `or {}` was never needed and
-- caused the taint. Simply omit it -- the assignment below writes to
-- an existing table (safe: key-level writes do not taint other keys).
StaticPopupDialogs["PA_CUBE_CONFIRM"] = {
    text          = "%s",
    button1       = "Re-roll",
    button2       = "Cancel",
    hasEditBox    = false,
    timeout       = 0,
    whileDead     = false,
    hideOnEscape  = true,
    exclusive     = true,
    OnAccept      = function() end,
}

local frame
local slotButton
local reserved = nil
local lastRoll            -- { bag, slot, link, entry, at }: the item being re-rolled

local function SplitSuffix(fullName)
    if not fullName or fullName == "" then return "", "" end
    local last
    local start = 1
    while true do
        local s = fullName:find(" of ", start, true)
        if not s then break end
        last = s
        start = s + 1
    end
    if not last then return fullName, "" end
    return fullName:sub(1, last - 1), fullName:sub(last + 1)
end

-- The affix ("of the Elder") gives the item's last white stat lines: 3 on epic and
-- legendary items, 2 on rare, 1 on uncommon. Read from the bag item's tooltip.
local AFFIX_LINES = { [2] = 1, [3] = 2, [4] = 3, [5] = 3 }
local scanTip
local function AffixStats(bag, slot)
    if not (bag and slot) then return {} end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "PACubeScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    scanTip:ClearLines()
    scanTip:SetBagItem(bag, slot)
    local stats = {}
    for i = 2, scanTip:NumLines() do
        local fs = _G["PACubeScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        -- random-suffix lines can come wrapped in colour codes or with leading spaces
        if text then text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "") end
        if text and text:find("^%+%s*%d+") then stats[#stats + 1] = text end
    end
    local _, _, quality = GetItemInfo(GetContainerItemLink(bag, slot) or "")
    local n = math.min(#stats, AFFIX_LINES[quality or 0] or 0)
    local out = {}
    for i = #stats - n + 1, #stats do out[#out + 1] = stats[i] end
    return out
end

local function UpdateAffixLabel()
    if not (frame and frame.affixLabel) then return end
    if not (reserved and reserved.link) then frame.affixLabel:SetText(""); return end
    local full = GetItemInfo(reserved.link)
    local _, suffix = SplitSuffix(full or "")
    local stats = AffixStats(reserved.bag, reserved.slot)
    if suffix == "" or #stats == 0 then frame.affixLabel:SetText(""); return end
    frame.affixLabel:SetText("|cffaab0d4Stats from|r |cffffd970" .. suffix .. "|r\n|cffffffff"
        .. table.concat(stats, "\n") .. "|r")
end

local function UpdateNameLabel()
    if not frame or not frame.nameLabel then return end
    UpdateAffixLabel()
    if not reserved or not reserved.link then
        frame.nameLabel:SetText("")
        return
    end
    local full = GetItemInfo(reserved.link)
    if not full then
        frame.nameLabel:SetText(reserved.link)
        return
    end
    local base, suffix = SplitSuffix(full)
    if suffix == "" then
        frame.nameLabel:SetText(base)
    else
        frame.nameLabel:SetFormattedText("%s |cffffd200%s|r", base, suffix)
    end
end

local function ClearReserved()
    reserved = nil
    if not slotButton then return end
    slotButton.icon:SetTexture("")
    if slotButton.emptyMark then slotButton.emptyMark:Show() end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Disable()
        frame.rerollBtn:SetText("Re-roll (1 Orb of Destiny)")
    end
    if frame and frame.nameLabel then
        frame.nameLabel:SetText("")
        if frame.affixLabel then frame.affixLabel:SetText("") end
    end
end

local function ResolveItemIcon(entry)
    if not entry then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(entry)
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- What the cube will do with the item. Mythic items (suffix 2000..4999 in
-- link field 7) and legendaries are changed in place: gems, enchants and the
-- tier stay. A legendary without a suffix gets a random Mythic affix.
local function RerollKind(ref)
    local _, _, quality = GetItemInfo(ref.itemID)
    local suffix = tonumber(ref.link and ref.link:match(
        "|Hitem:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d+)")) or 0
    if suffix <= -2000 and suffix >= -4999 then return "mythic" end
    if quality == 5 then return "legendary" end
    return "normal"
end

local CONFIRM_TEXT = {
    legendary = "Give this legendary a random Mythic affix (tier I)?\n\n"
                .. "Gems and enchants stay on the item. From then on it can be upgraded.\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
    mythic    = "Re-roll the Mythic affix of this item?\n\n"
                .. "The tier, gems and enchants stay on the item.\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
    normal    = "Re-roll this item?\n\n"
                .. "|cffff6b6bAny gems and enchants on the item will be destroyed.|r\n"
                .. "|cffff6b6bThis action cannot be undone.|r\n\n"
                .. "Cost: |cffffd2001 Orb of Destiny|r.",
}

local function RerollButtonText(ref)
    if ref and RerollKind(ref) == "legendary" then
        return "Mythic affix (1 Orb of Destiny)"
    end
    return "Re-roll (1 Orb of Destiny)"
end

local function SetReserved(ref)
    reserved = {
        bag    = ref.bag,
        slot   = ref.slot,
        link   = ref.link,
        itemID = ref.itemID,
    }
    slotButton.icon:SetTexture(ResolveItemIcon(ref.itemID))
    if slotButton.emptyMark then slotButton.emptyMark:Hide() end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Enable()
        frame.rerollBtn:SetText(RerollButtonText(ref))
    end
    UpdateNameLabel()
end

-- After a re-roll the server puts the new item in the bags. Found by position, not by
-- link (a roll can come out identical): the old slot if it holds that item (the old
-- one is gone on success), else a slot that didn't hold it before the roll (bag
-- snapshot taken at the click). Waits 0.4 s for the bags to update; gives up after 5 s.
local function SnapshotBags(itemID)
    local had = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            if GetContainerItemID(bag, slot) == itemID then had[bag .. ":" .. slot] = true end
        end
    end
    return had
end
local awaitNew = CreateFrame("Frame")
awaitNew:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
awaitNew:Hide()
awaitNew:SetScript("OnUpdate", function(self)
    local r = lastRoll
    if not (r and r.entry) or GetTime() - (r.at or 0) > 5 or not (frame and frame:IsShown()) then
        lastRoll = nil; self:Hide(); return
    end
    if GetTime() - r.at < 0.4 then return end
    local function Take(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        lastRoll = nil; self:Hide()
        SetReserved({ bag = bag, slot = slot, link = link, itemID = r.entry })
    end
    if GetContainerItemID(r.bag, r.slot) == r.entry then
        return Take(r.bag, r.slot)
    end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            if GetContainerItemID(bag, slot) == r.entry and not (r.had and r.had[bag .. ":" .. slot]) then
                return Take(bag, slot)
            end
        end
    end
end)

local function ValidateBeforeSubmit(ref)
    if not ref or not ref.itemID then return false, "No item picked up." end
    local _, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(ref.itemID)
    if not equipLoc or equipLoc == "" then
        return false, "Item is not equippable."
    end
    if quality and (quality < 2 or quality > 5) then
        return false, "Only green, blue, purple, and legendary items can be re-rolled."
    end
    return true
end

local function Build()
    if frame then return end

    frame = CreateFrame("Frame", "ProjectAstralCubeOfDestiny", UIParent)
    frame.__paUnified = true   -- unified look: Theme.lua keeps its navy
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    -- unified window: navy with a gold edge and a gold top glow
    PA.UI.AstralBackdrop(frame, { thin = true })
    frame:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
    frame:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)
    local glow = frame:CreateTexture(nil, "ARTWORK"); glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    glow:SetHeight(48)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(title, 18)
    title:SetPoint("TOP", frame, "TOP", 0, -20)
    title:SetText("Cube of Destiny")
    title:SetTextColor(1, 1, 1)
    local titleBar = frame:CreateTexture(nil, "OVERLAY"); titleBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBar:SetVertexColor(0.886, 0.753, 0.384, 1); titleBar:SetSize(3, 19)
    titleBar:SetPoint("RIGHT", title, "LEFT", -9, 0)

    local orbLabel = frame:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(orbLabel, 13)
    orbLabel:SetPoint("TOP", title, "BOTTOM", 0, -6)
    orbLabel:SetJustifyH("CENTER")
    orbLabel:SetTextColor(0.85, 0.80, 0.35)
    frame.orbLabel = orbLabel
    local function RefreshOrbLabel()
        orbLabel:SetText(("|cffdcdff0Orbs of Destiny|r  |cffffd970%d|r"):format(PA.orbs or 0))
    end
    RefreshOrbLabel()
    if PA.OnTokensChanged then
        PA:OnTokensChanged(function() if frame:IsShown() then RefreshOrbLabel() end end)
    end

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(closeBtn)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        AIO.Handle("AstralCubeOfDestinyServer", "Close")
        frame:Hide()
        ClearReserved()
    end)

    local nameLabel = frame:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(nameLabel, 13)
    nameLabel:SetPoint("BOTTOM", frame, "TOP", 0, -100)
    nameLabel:SetJustifyH("CENTER")
    nameLabel:SetWidth(FRAME_W - 30)
    nameLabel:SetText("")
    frame.nameLabel = nameLabel

    -- the stats the item's affix gives ("of the Elder"), under the slot
    local affixLabel = frame:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(affixLabel, 12)
    affixLabel:SetPoint("TOP", frame, "TOP", 0, -(108 + SLOT_SIZE + 10))
    affixLabel:SetWidth(FRAME_W - 30)
    affixLabel:SetJustifyH("CENTER")
    affixLabel:SetSpacing(2)
    frame.affixLabel = affixLabel

    slotButton = CreateFrame("Button", "ProjectAstralCubeSlot", frame)
    slotButton:SetSize(SLOT_SIZE, SLOT_SIZE)
    slotButton:SetPoint("TOP", frame, "TOP", 0, -108)
    slotButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
                             edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    slotButton:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.95))
    slotButton:SetBackdropBorderColor(PA.UI.Tint(0.300, 0.360, 0.620, 1))

    local icon = slotButton:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT",     slotButton, "TOPLEFT",      4, -4)
    icon:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", -4,  4)
    icon:SetTexture("")
    slotButton.icon = icon

    local empty = slotButton:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    empty:SetPoint("CENTER", slotButton, "CENTER", 0, 1)
    empty:SetText("+")
    empty:SetTextColor(PA.UI.Tint(0.667, 0.690, 0.831, 0.55))
    slotButton.emptyMark = empty

    slotButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slotButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ClearReserved()
            return
        end
        if CursorHasItem() and lastPickup then
            local ok, why = ValidateBeforeSubmit(lastPickup)
            if not ok then
                UIErrorsFrame:AddMessage(
                    "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
                ClearCursor()
                return
            end
            SetReserved(lastPickup)
            ClearCursor()
            lastPickup = nil
        end
    end)
    slotButton:RegisterForDrag("LeftButton")
    slotButton:SetScript("OnReceiveDrag", function(self)
        if CursorHasItem() and lastPickup then
            local ok, why = ValidateBeforeSubmit(lastPickup)
            if not ok then
                UIErrorsFrame:AddMessage(
                    "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
                ClearCursor()
                return
            end
            SetReserved(lastPickup)
            ClearCursor()
            lastPickup = nil
        end
    end)

    hooksecurefunc("PickupContainerItem", function(bag, slot)
        if not IsShiftKeyDown() then return end
        if not frame:IsShown() then return end
        if not CursorHasItem() then return end
        local ref = {
            bag    = bag,
            slot   = slot,
            link   = GetContainerItemLink(bag, slot),
            itemID = GetContainerItemID and GetContainerItemID(bag, slot) or nil,
        }
        local ok, why = ValidateBeforeSubmit(ref)
        if not ok then
            UIErrorsFrame:AddMessage(
                "Cube of Destiny: " .. why, 1.0, 0.42, 0.42, 1.0)
            ClearCursor()
            return
        end
        SetReserved(ref)
        ClearCursor()
    end)

    slotButton:SetScript("OnEnter", function(self)
        if reserved and reserved.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(reserved.link)
            GameTooltip:Show()
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Empty slot")
            GameTooltip:AddLine("Pick up an item from your bag and click here, or shift-click.", 1, 1, 1, true)
            GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6, true)
            GameTooltip:Show()
        end
    end)
    slotButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(btn)
    -- main action: gold outline (kept on hover/leave over the navy button skin)
    local function GoldIdle(self) self:SetBackdropColor(0.886, 0.753, 0.384, 0.08); self:SetBackdropBorderColor(0.79, 0.66, 0.31, 1) end
    GoldIdle(btn)
    btn:HookScript("OnEnter", function(self) self:SetBackdropColor(0.886, 0.753, 0.384, 0.22); self:SetBackdropBorderColor(1, 0.89, 0.60, 1) end)
    btn:HookScript("OnLeave", GoldIdle)
    if btn:GetFontString() then btn:GetFontString():SetTextColor(1.00, 0.89, 0.60); PA.UI.SetTextFont(btn:GetFontString(), 13) end
    btn:SetSize(180, 28)
    btn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 60)
    btn:SetText("Re-roll (1 Orb of Destiny)")
    btn:Disable()
    btn:SetScript("OnClick", function()
        if not reserved then return end
        local capturedBag  = reserved.bag
        local capturedSlot = reserved.slot
        local roll = { bag = capturedBag, slot = capturedSlot, link = reserved.link, itemID = reserved.itemID }
        local function DoRoll()
            roll.had = SnapshotBags(roll.itemID)   -- where that item already was
            lastRoll = roll   -- the re-rolled item is put back in the slot when it returns
            AIO.Handle("AstralCubeOfDestinyServer",
                       "Reroll", capturedBag, capturedSlot)
            btn:Disable()
            btn:SetText("Rolling...")
        end
        if ProjectAstralSettings and ProjectAstralSettings.cubeSkipConfirm then
            DoRoll()
        else
            StaticPopupDialogs["PA_CUBE_CONFIRM"].OnAccept = DoRoll
            StaticPopup_Show("PA_CUBE_CONFIRM", CONFIRM_TEXT[RerollKind(reserved)])
        end
    end)
    frame.rerollBtn = btn

    -- skip the confirmation popup (saved)
    local skip = CreateFrame("CheckButton", "ProjectAstralCubeSkipConfirm", frame, "UICheckButtonTemplate")
    skip:SetSize(22, 22)
    skip:SetPoint("TOP", btn, "BOTTOM", -60, -8)
    local skipText = _G["ProjectAstralCubeSkipConfirmText"]
    skipText:ClearAllPoints()
    skipText:SetPoint("LEFT", skip, "RIGHT", 4, 1)
    PA.UI.SetTextFont(skipText, 12)
    skipText:SetText("|cffdcdff0Don't ask again|r")
    skip:SetChecked(ProjectAstralSettings and ProjectAstralSettings.cubeSkipConfirm and true or false)
    skip:SetScript("OnClick", function(self)
        ProjectAstralSettings = ProjectAstralSettings or {}
        ProjectAstralSettings.cubeSkipConfirm = self:GetChecked() and true or nil
    end)
    skip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Don't ask again", 1, 1, 1)
        GameTooltip:AddLine("Re-roll right away, without the confirmation popup. Gems and enchants are still destroyed.", 1, 0.42, 0.42, true)
        GameTooltip:Show()
    end)
    skip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local hint = frame:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(hint, 12)
    hint:SetPoint("BOTTOM", btn, "TOP", 0, 12)
    hint:SetText("Cost: 1 Orb of Destiny. Item comes back with fresh random stats.\n"
        .. "|cffff6b6bWARNING:|r gems and enchants are destroyed (Mythic items and legendaries keep them).\n"
        .. "|cffff6b6bThis action cannot be undone.|r")
    hint:SetTextColor(0.86, 0.87, 0.94)
    hint:SetWidth(FRAME_W - 30)
    hint:SetJustifyH("CENTER")

    tinsert(UISpecialFrames, "ProjectAstralCubeOfDestiny")

    ClearReserved()
end

local ClientHandler = AIO.AddHandlers("AstralCubeOfDestiny", {})

ClientHandler.Open = function(_, orbs)
    Build()
    if orbs then PA.orbs = orbs end
    frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    ClearReserved()
    frame:Show()
end

ClientHandler.Close = function()
    if frame then frame:Hide() end
    ClearReserved()
end

ClientHandler.OrbsUpdated = function(_, orbs)
    if orbs then PA.orbs = orbs end
    if frame and frame:IsShown() then
        frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    end
end

ClientHandler.Result = function(_, ok, entry, orbs, reason)
    if orbs then PA.orbs = orbs end
    if frame and frame.rerollBtn then
        frame.rerollBtn:Enable()
        frame.rerollBtn:SetText("Re-roll (1 Orb of Destiny)")
    end
    if frame and frame.orbLabel then
        frame.orbLabel:SetText(("|cffffd200Orbs of Destiny|r  %d"):format(PA.orbs or 0))
    end

    if ok then
        UIErrorsFrame:AddMessage(
            "Cube of Destiny: item re-rolled!",
            0.55, 1.00, 0.55, 1.0)
        ClearReserved()
        if lastRoll then
            lastRoll.entry, lastRoll.at = tonumber(entry) or lastRoll.itemID, GetTime()
            awaitNew:Show()   -- put the new item back in the slot once it's in the bags
        end
    else
        local reasonStr = ({
            NOT_OPEN          = "You must be at the cube.",
            NOT_AT_CUBE       = "You walked away from the cube.",
            ITEM_NOT_FOUND    = "Item missing from that slot.",
            NOT_EQUIPPABLE    = "Only equippable items can be re-rolled.",
            BAD_QUALITY       = "Only green, blue, purple, and legendary items can be re-rolled.",
            NO_RANDOM_ROLL    = "This item has no random stats to re-roll.",
            INSUFFICIENT_ORBS = "You don't have enough Orbs of Destiny.",
            ADDITEM_FAILED    = "Your bags are full — item was returned, orb refunded.",
        })[reason] or ("Re-roll rejected: " .. tostring(reason))
        UIErrorsFrame:AddMessage(
            "Cube of Destiny: " .. reasonStr,
            1.0, 0.42, 0.42, 1.0)
    end
end
