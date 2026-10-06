
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

-- Mythic Upgrade window (server: lua_scripts/Server/astral_bridge/mythicupgrade/mythic_upgrade.lua).
-- Opened only by the server when the player talks to the Mythic Artificer. This file only
-- displays: stats, costs and affordability come from the server, which re-checks the NPC
-- range and the item on every request.

local FRAME_W, FRAME_H = 400, 486
local ROW_H = 22
local GOLD_ICON   = "Interface\\MoneyFrame\\UI-GoldIcon"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local S = { item = nil, data = nil, pending = false, closingFromServer = false, refreshAt = nil,
            quietUntil = 0, iconRetry = false, sentAt = nil }
local W = {}

local REASON = {
    ITEM_NOT_FOUND = "Item not found in that bag slot.",
    EQUIPPED       = "Unequip the item first.",
    IN_TRADE       = "Close the trade window first.",
    NOT_MYTHIC     = "Only items with a Mythic affix can be upgraded.",
    NO_COST        = "This item cannot be upgraded here.",
    MAXED          = "This item is already at the highest tier.",
    CHANGED        = "The item changed. Check the new preview.",
    NOT_SOULBOUND  = "Equip the item once to bind it to you before upgrading.",
    LOOT_TRADEABLE = "This item can still be traded to your group. Upgrade it once that time has run out.",
    BAGS_ONLY      = "Drag the item from your bags.",
    CANNOT_AFFORD  = "You cannot afford this upgrade.",
    ERROR          = "Something went wrong. Please try again.",
}

local lastPickup = nil
hooksecurefunc("PickupContainerItem", function(bag, slot)
    if not bag or not slot then return end
    lastPickup = { bag = bag, slot = slot }
end)
hooksecurefunc("ClearCursor", function() lastPickup = nil end)

StaticPopupDialogs["PA_MYTHIC_UPGRADE_CONFIRM"] = {
    text         = "%s",
    button1      = "Upgrade",
    button2      = "Cancel",
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    exclusive    = true,
    OnAccept     = function() end,
}

local function Colored(c, s)
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, s)
end

local function FormatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg"):format(math.floor(copper / 10000))
end

local function ItemIcon(entryOrLink)
    if not entryOrLink then return UNKNOWN_ICON end
    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(entryOrLink)
    if not tex and type(entryOrLink) == "number" and PA.ItemCache then
        PA.ItemCache.Register(entryOrLink)
    end
    return tex or UNKNOWN_ICON
end

local function SetStatus(text, color)
    W.status:SetText(text or "")
    local c = color or UI.Color.textBad
    W.status:SetTextColor(c[1], c[2], c[3])
end

local function SetButton(enabled, label)
    W.upgradeBtn:SetLabel(label or "Upgrade")
    W.upgradeBtn:SetDisabledLook(not enabled)
end

local function ClearRows(rows)
    for _, r in ipairs(rows) do r:Hide() end
end

-- ---------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------

local function RenderEmpty()
    StaticPopup_Hide("PA_MYTHIC_UPGRADE_CONFIRM")
    S.item, S.data, S.pending = nil, nil, false
    W.slot.icon:SetTexture(nil)
    W.slot:SetQuality(1)
    W.slotPlus:Show()
    W.itemName:SetText(Colored(UI.Nav.muted, "Place a Mythic item here"))
    W.tierText:SetText("")
    ClearRows(W.statRows)
    ClearRows(W.costRows)
    W.statsEmpty:Show()
    W.costEmpty:Show()
    SetStatus("")
    SetButton(false)
end

local function RenderPreview(data)
    S.data, S.pending = data, false
    W.slotPlus:Hide()
    if data.link then
        W.slot:SetTexture(ItemIcon(data.link))
        local _, _, quality = GetItemInfo(data.link)
        W.slot:SetQuality(quality or 4)
        W.itemName:SetText(data.link)
    end
    ClearRows(W.statRows)
    ClearRows(W.costRows)
    W.statsEmpty:Show()
    W.costEmpty:Show()

    if data.error then
        W.tierText:SetText("")
        SetStatus(REASON[data.error] or data.error)
        SetButton(false)
        return
    end

    if data.maxed then
        W.tierText:SetText(Colored(UI.Color.textHi, "Tier " .. data.tierName) .. "  "
            .. Colored(UI.Nav.muted, "(maximum)"))
    else
        W.tierText:SetText(Colored(UI.Color.textPrimary, "Tier " .. data.tierName) .. "  "
            .. Colored(UI.Nav.muted, "->") .. "  "
            .. Colored(UI.Color.textGood, "Tier " .. data.nextName))
    end

    if data.stats and #data.stats > 0 then
        W.statsEmpty:Hide()
        for i, st in ipairs(data.stats) do
            local r = W.statRows[i]
            r.label:SetText(st.label)
            if data.maxed then
                r.value:SetText(Colored(UI.Color.textTitle, "+" .. st.cur))
            else
                local gain = st.nxt - st.cur
                r.value:SetText(Colored(UI.Color.textPrimary, "+" .. st.cur) .. "  "
                    .. Colored(UI.Nav.muted, "->") .. "  "
                    .. Colored(UI.Color.textGood, "+" .. st.nxt) .. "  "
                    .. Colored(UI.Color.textGood, ("(+%d)"):format(gain)))
            end
            r:Show()
        end
    end

    if data.maxed then
        SetStatus(REASON.MAXED, UI.Color.textHi)
        SetButton(false)
        return
    end

    local cost, have = data.cost, data.have
    if cost and have then
        W.costEmpty:Hide()
        local lines = {
            { icon = ItemIcon(cost.currencyItem), name = cost.currencyName,
              need = tostring(cost.currencyCount), own = tostring(have.currency),
              ok = have.currency >= cost.currencyCount },
            { icon = UI.Icon.tokens, name = "Tokens",
              need = tostring(cost.tokens), own = tostring(have.tokens),
              ok = have.tokens >= cost.tokens },
            { icon = GOLD_ICON, name = "Gold",
              need = FormatMoney(cost.money), own = FormatMoney(have.money),
              ok = have.money >= cost.money },
        }
        if lines[1].icon == UNKNOWN_ICON and not S.iconRetry then
            S.iconRetry = true
            S.refreshAt = GetTime() + 1
        end
        for i, l in ipairs(lines) do
            local r = W.costRows[i]
            r.icon:SetTexture(l.icon)
            r.label:SetText(l.name)
            r.value:SetText(Colored(l.ok and UI.Color.textGood or UI.Color.textBad, l.need)
                .. Colored(UI.Nav.muted, "  /  you have ") .. l.own)
            r:Show()
        end
    end

    if data.affordable then
        SetStatus("")
        SetButton(true, "Upgrade to Tier " .. data.nextName)
    else
        SetStatus(REASON.CANNOT_AFFORD)
        SetButton(false, "Upgrade to Tier " .. data.nextName)
    end
end

local function RequestPreview()
    if not S.item then return end
    S.pending = true
    S.sentAt = GetTime()
    SetButton(false)
    AIO.Handle("AstralMythicUpgradeServer", "Preview", S.item.bag, S.item.slot)
end

local function PlaceItem(ref)
    StaticPopup_Hide("PA_MYTHIC_UPGRADE_CONFIRM")
    S.refreshAt = nil
    S.item = { bag = ref.bag, slot = ref.slot }
    W.slotPlus:Hide()
    W.slot:SetTexture(ItemIcon(GetContainerItemLink(ref.bag, ref.slot)))
    W.itemName:SetText(GetContainerItemLink(ref.bag, ref.slot) or "")
    W.tierText:SetText(Colored(UI.Nav.muted, "Loading..."))
    SetStatus("")
    RequestPreview()
end

local function TakeCursorItem()
    if not CursorHasItem() then return end
    local ctype, _, clink = GetCursorInfo()
    local ref = lastPickup
    lastPickup = nil
    local fromBag = ctype == "item" and ref and ref.bag >= 0 and ref.bag <= 4
        and select(3, GetContainerItemInfo(ref.bag, ref.slot))
        and GetContainerItemLink(ref.bag, ref.slot) == clink
    ClearCursor()
    if not fromBag then
        SetStatus(REASON.BAGS_ONLY)
        return
    end
    PlaceItem(ref)
end

local function ConfirmUpgrade()
    local d = S.data
    if not (d and S.item and d.cost and not d.maxed and not d.error) then return end
    local c = d.cost
    local text = ("Upgrade %s\nto Tier %s?\n\nCost: %d %s, %d Tokens, %s")
        :format(d.link or "this item", d.nextName, c.currencyCount, c.currencyName, c.tokens,
                FormatMoney(c.money))
    local bag, slot, suffixId, itemGuid = S.item.bag, S.item.slot, d.suffixId, d.itemGuid
    StaticPopupDialogs["PA_MYTHIC_UPGRADE_CONFIRM"].OnAccept = function()
        if not (S.item and S.item.bag == bag and S.item.slot == slot
                and S.data and S.data.suffixId == suffixId) then return end
        S.pending = true
        S.sentAt = GetTime()
        SetButton(false, "Upgrading...")
        AIO.Handle("AstralMythicUpgradeServer", "Upgrade", bag, slot, suffixId, itemGuid)
    end
    StaticPopup_Show("PA_MYTHIC_UPGRADE_CONFIRM", text)
end

-- ---------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------

local function MakeRow(parent, withIcon)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    local x = 0
    if withIcon then
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16)
        r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        x = 22
    end
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.label:SetPoint("LEFT", r, "LEFT", x, 0)
    r.label:SetTextColor(unpack(UI.Color.textPrimary))
    r.value = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.value:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.value:SetJustifyH("RIGHT")
    r:Hide()
    return r
end

local function Build()
    if W.frame then return end

    local f = UI.MakePanel(UIParent, FRAME_W, FRAME_H, {
        name = "ProjectAstralMythicUpgrade", movable = true, strata = "HIGH", cosmic = true,
    })
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:Hide()
    W.frame = f

    W.header = UI.MakeHeader(f, "Mythic Upgrade", "Mythic Artificer")
    W.header.closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Item slot
    local slot = UI.MakeIconFrame(f, { size = 52 })
    slot:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -88)
    W.slot = slot
    W.slotPlus = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    W.slotPlus:SetPoint("CENTER", slot, "CENTER", 0, 1)
    W.slotPlus:SetText("+")
    W.slotPlus:SetTextColor(0.45, 0.45, 0.50, 0.7)

    local hit = CreateFrame("Button", nil, f)
    hit:SetAllPoints(slot)
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:RegisterForDrag("LeftButton")
    hit:SetScript("OnClick", function(_, button)
        if button == "RightButton" then RenderEmpty() return end
        TakeCursorItem()
    end)
    hit:SetScript("OnReceiveDrag", TakeCursorItem)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if S.data and S.data.link then
            GameTooltip:SetHyperlink(S.data.link)
        else
            GameTooltip:SetText("Mythic item")
            GameTooltip:AddLine("Drag an item with a Mythic affix from your bags here.", 1, 1, 1, true)
            GameTooltip:AddLine("Equipped items must be unequipped first. Right-click to clear.", 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    W.itemName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    W.itemName:SetPoint("TOPLEFT", slot, "TOPRIGHT", 14, -6)
    W.itemName:SetPoint("RIGHT", f, "RIGHT", -24, 0)
    W.itemName:SetJustifyH("LEFT")
    W.tierText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    W.tierText:SetPoint("TOPLEFT", W.itemName, "BOTTOMLEFT", 0, -8)

    -- Stats section
    local statsLabel = UI.MakeSectionLabel(f, "Stat changes")
    statsLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -160)
    statsLabel:SetPoint("RIGHT", f, "RIGHT", -26, 0)
    W.statRows = {}
    for i = 1, 3 do
        local r = MakeRow(f, false)
        r:SetPoint("TOPLEFT", statsLabel, "BOTTOMLEFT", 4, -6 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", f, "RIGHT", -30, 0)
        W.statRows[i] = r
    end
    W.statsEmpty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    W.statsEmpty:SetPoint("TOPLEFT", statsLabel, "BOTTOMLEFT", 4, -10)
    W.statsEmpty:SetText("-")

    -- Cost section
    local costLabel = UI.MakeSectionLabel(f, "Upgrade cost")
    costLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 26, -262)
    costLabel:SetPoint("RIGHT", f, "RIGHT", -26, 0)
    W.costRows = {}
    for i = 1, 3 do
        local r = MakeRow(f, true)
        r:SetPoint("TOPLEFT", costLabel, "BOTTOMLEFT", 4, -6 - (i - 1) * ROW_H)
        r:SetPoint("RIGHT", f, "RIGHT", -30, 0)
        W.costRows[i] = r
    end
    W.costEmpty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    W.costEmpty:SetPoint("TOPLEFT", costLabel, "BOTTOMLEFT", 4, -10)
    W.costEmpty:SetText("-")

    -- Status + button
    W.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    W.status:SetPoint("BOTTOM", f, "BOTTOM", 0, 100)
    W.status:SetWidth(FRAME_W - 50)
    W.status:SetJustifyH("CENTER")

    W.upgradeBtn = UI.MakeButton(f, "Upgrade", { w = 220, h = 30, onClick = ConfirmUpgrade })
    W.upgradeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 58)

    UI.MakeFooter(f, { text = "Only the tier rises. Affix, gems, enchants and binding stay the same." })

    -- Refresh when currency, money or the bag slot change.
    f:RegisterEvent("BAG_UPDATE")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
    f:SetScript("OnEvent", function()
        if S.item and not S.pending and GetTime() >= S.quietUntil then
            S.refreshAt = GetTime() + 0.4
        end
    end)
    f:SetScript("OnUpdate", function()
        -- A request without an answer (e.g. dropped by the server throttle) must not
        -- leave the window stuck: ask again after 2 seconds.
        if S.pending and S.sentAt and GetTime() - S.sentAt > 2 then
            S.pending = false
            if S.item then RequestPreview() end
            return
        end
        if S.refreshAt and GetTime() >= S.refreshAt then
            S.refreshAt = nil
            if S.item and not S.pending then RequestPreview() end
        end
    end)

    f:HookScript("OnHide", function()
        if f:IsShown() then return end
        StaticPopup_Hide("PA_MYTHIC_UPGRADE_CONFIRM")
        if not S.closingFromServer then AIO.Handle("AstralMythicUpgradeServer", "Close") end
        S.closingFromServer = false
        RenderEmpty()
    end)
    tinsert(UISpecialFrames, "ProjectAstralMythicUpgrade")

    RenderEmpty()
end

-- ---------------------------------------------------------------------
-- AIO handlers (server -> client)
-- ---------------------------------------------------------------------

local Client = AIO.AddHandlers("AstralMythicUpgrade", {})

Client.Open = function(_, npcName)
    Build()
    S.closingFromServer = false
    S.iconRetry = false
    if W.header.subtitle then W.header.subtitle:SetText("|cffaab0d4" .. (npcName or "") .. "|r") end
    RenderEmpty()
    W.frame:Show()
end

Client.Close = function()
    if not W.frame then return end
    if W.frame:IsShown() then
        S.closingFromServer = true
        W.frame:Hide()
        S.closingFromServer = false
    end
    -- OnHide does not fire while the UI is hidden (Alt+Z), so clean up here as well.
    RenderEmpty()
end

Client.Preview = function(_, data)
    if not (W.frame and W.frame:IsShown() and S.item and data) then return end
    if data.bag ~= S.item.bag or data.slot ~= S.item.slot then return end
    RenderPreview(data)
end

Client.Result = function(_, ok, reason, data)
    if not (W.frame and W.frame:IsShown()) then return end
    S.quietUntil = GetTime() + 1.5
    if data and S.item and data.bag == S.item.bag and data.slot == S.item.slot then
        RenderPreview(data)
    elseif S.data then
        RenderPreview(S.data)
    else
        S.pending = false
    end
    if ok then
        PlaySound("igQuestListComplete")
        SetStatus("Upgrade complete!", UI.Color.textGood)
    elseif reason then
        SetStatus(REASON[reason] or reason)
    end
end
