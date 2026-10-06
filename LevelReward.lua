
local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local LR = {}
PA.LR = LR

StaticPopupDialogs["PA_LEVELREWARD_SELL_CONFIRM"] = {
    text = "Sell the highest-value level-up reward for gold?\n\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() LR.OnSell() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local popup
local candidates
local itemMeta = {}
local selectedSlot = 1
local disenchantPending = false

local POPUP_W = 360
local POPUP_H = 280
local ROW_H   = 56

local function ChatInfo(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFFD700[Level Reward]|r " .. msg)
    end
end

local function Send(cmd) SendChatMessage("." .. cmd, "SAY") end

local function GetSavedVar()
    if not ProjectAstralLevelReward then
        ProjectAstralLevelReward = {
            autoSell      = false,
            autoDisenchant = false,
            showInCombat  = false,
            confirmSell   = true,
        }
    end
    if ProjectAstralLevelReward.autoDisenchant == nil then
        ProjectAstralLevelReward.autoDisenchant = false
    end
    if ProjectAstralLevelReward.showInCombat == nil then
        ProjectAstralLevelReward.showInCombat = false
    end
    if ProjectAstralLevelReward.confirmSell == nil then
        ProjectAstralLevelReward.confirmSell = true
    end
    return ProjectAstralLevelReward
end

local function RestoreSavedPos(f)
    local sv = GetSavedVar()
    if type(sv.posX) ~= "number" or type(sv.posY) ~= "number" then return end
    local sw = UIParent:GetWidth() or 1024
    local sh = UIParent:GetHeight() or 768
    if sv.posX < 0 or sv.posX > sw - 50 then return end
    if sv.posY < 50 or sv.posY > sh then return end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sv.posX, sv.posY)
end

local function SavePos(f)
    local x, y = f:GetLeft(), f:GetTop()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local sv = GetSavedVar()
    sv.posX = x
    sv.posY = y
end

local lastChoice = nil
local reopenBtn

local UpdateReopenButton
local ShowChoiceNow

local function FormatCopper(copper)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts+1] = g .. "g" end
    if s > 0 then parts[#parts+1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts+1] = c .. "c" end
    return table.concat(parts, " ")
end

local function IsRewardDisenchantable(entry)
    if not entry then return false end
    local meta = itemMeta[entry] or itemMeta[tostring(entry)]
    if meta and (meta.crafted == true or meta.isCrafted == true) then
        return false
    end
    local _, _, quality, _, _, _, _, _, equipLoc = GetItemInfo(entry)
    if quality ~= 2 and quality ~= 3 and quality ~= 4 then return false end
    return equipLoc and equipLoc ~= ""
        and equipLoc ~= "INVTYPE_AMMO"
        and equipLoc ~= "INVTYPE_BAG"
        and equipLoc ~= "INVTYPE_QUIVER"
end

local function SnapshotItemInBags(itemID)
    local snapshot = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemID and GetContainerItemID(bag, slot) == itemID then
                local _, count = GetContainerItemInfo(bag, slot)
                snapshot[bag .. ":" .. slot] = tonumber(count) or 1
            end
        end
    end
    return snapshot
end

local function FindNewItemInBags(itemID, snapshot)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            if GetContainerItemID and GetContainerItemID(bag, slot) == itemID then
                local _, count = GetContainerItemInfo(bag, slot)
                local previous = snapshot[bag .. ":" .. slot] or 0
                if (tonumber(count) or 1) > previous then
                    return bag, slot
                end
            end
        end
    end
end

local function UpdateDisenchantButton()
    if not (popup and popup.disenchantBtn) then return end
    local entry = candidates and candidates[selectedSlot]
    if not disenchantPending and IsRewardDisenchantable(entry) then
        popup.disenchantBtn:Enable()
    else
        popup.disenchantBtn:Disable()
    end
end

local function CreatePopup()
    if popup then return popup end

    local f = CreateFrame("Frame", "PALevelRewardPopup", UIParent)
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:SetSize(POPUP_W, POPUP_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        SavePos(self)
    end)
    f:SetClampedToScreen(true)
    f:Hide()
    RestoreSavedPos(f)
    tinsert(UISpecialFrames, "PALevelRewardPopup")

    f:HookScript("OnHide", function()
        UpdateReopenButton()
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    PA.UI.CosmicCorners(f)
    f:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.40, 0.45, 0.65)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Level-Up Reward")
    title:SetTextColor(1.0, 0.85, 0.3)

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
    sub:SetText("Pick one — or auto-sell the highest value for gold.")
    sub:SetTextColor(0.75, 0.8, 0.85)

    f.rows = {}
    f.acceptBtn = nil

    for i = 1, 5 do
        local row = CreateFrame("Button", nil, f)
        row:SetHeight(ROW_H)
        row:SetPoint("LEFT",  f, "LEFT",  14, 0)
        row:SetPoint("RIGHT", f, "RIGHT", -14, 0)
        if i == 1 then
            row:SetPoint("TOP", f, "TOP", 0, -56)
        else
            row:SetPoint("TOP", f.rows[i-1], "BOTTOM", 0, -4)
        end

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.bg:SetVertexColor(0.12, 0.14, 0.20, 0.6)

        row.sel = row:CreateTexture(nil, "BORDER")
        row.sel:SetPoint("TOPLEFT",     -1, 1)
        row.sel:SetPoint("BOTTOMRIGHT",  1, -1)
        row.sel:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
        row.sel:Hide()

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(40, 40)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 6)
        row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.name:SetJustifyH("LEFT")

        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.value:SetPoint("LEFT", row.icon, "RIGHT", 8, -10)
        row.value:SetJustifyH("LEFT")

        row:RegisterForClicks("AnyUp")
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetHyperlink("item:" .. self.entry)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self, button)
            if not self.entry then return end
            -- Shift-click (either button) links the item into the chat box in use
            if IsModifiedClick("CHATLINK") then
                if ProjectAstral.InsertChatLink then
                    ProjectAstral.InsertChatLink(select(2, GetItemInfo(self.entry)))
                end
            elseif button == "LeftButton" then
                selectedSlot = self.slot
                LR.RefreshSelection()
                if GetSavedVar().autoDisenchant then
                    LR.OnDisenchant()
                end
            end
        end)

        f.rows[i] = row
    end

    local function AttachTooltip(btn, text)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(accept)
    accept:SetSize(115, 28)
    accept:SetPoint("BOTTOM", f, "BOTTOM", -112, 56)
    accept:SetText("Accept")
    accept:SetScript("OnClick", function() LR.OnAccept() end)
    AttachTooltip(accept, "Accept selected levelreward")
    f.acceptBtn = accept

    local disenchant = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(disenchant)
    disenchant:SetSize(100, 28)
    disenchant:SetPoint("BOTTOM", f, "BOTTOM", 0, 56)
    disenchant:SetText("Disenchant")
    disenchant:SetScript("OnClick", function() LR.OnDisenchant() end)
    AttachTooltip(disenchant,
        "Claim the selected reward, then disenchant it from your bags.\n"
        .. "Only green, blue, or purple non-crafted items are eligible.")
    f.disenchantBtn = disenchant

    local autoDisenchant = CreateFrame("CheckButton", "PALevelRewardAutoDisenchant", f,
                                        "OptionsCheckButtonTemplate")
    autoDisenchant:SetPoint("BOTTOM", f, "BOTTOM", -74, 88)
    PALevelRewardAutoDisenchantText:SetText("Auto disenchant")
    autoDisenchant:SetScript("OnClick", function(self)
        GetSavedVar().autoDisenchant = self:GetChecked() and true or false
    end)
    AttachTooltip(autoDisenchant,
        "Automatically disenchant an eligible reward when you select it.")
    f.autoDisenchant = autoDisenchant

    local sell = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(sell)
    sell:SetSize(100, 28)
    sell:SetPoint("BOTTOM", f, "BOTTOM", 112, 56)
    sell:SetText("Sell")
    sell:SetScript("OnClick", function()
        if GetSavedVar().confirmSell then
            StaticPopup_Show("PA_LEVELREWARD_SELL_CONFIRM")
        else
            LR.OnSell()
        end
    end)
    AttachTooltip(sell,
        "Auto-sell the highest value reward for gold.\n"
        .. "Confirmation is gated by the checkbox on the right.")
    f.sellBtn = sell

    local cic = CreateFrame("CheckButton", "PALevelRewardShowInCombat", f,
                             "OptionsCheckButtonTemplate")
    cic:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    PALevelRewardShowInCombatText:SetText("Show popups on combat")
    cic:SetScript("OnClick", function(self)
        GetSavedVar().showInCombat = self:GetChecked() and true or false
    end)
    f.showInCombat = cic

    local confirm = CreateFrame("CheckButton", "PALevelRewardConfirmSell", f,
                                 "OptionsCheckButtonTemplate")
    confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -136, 14)
    PALevelRewardConfirmSellText:SetText("Confirm popup on sell")
    confirm:SetScript("OnClick", function(self)
        GetSavedVar().confirmSell = self:GetChecked() and true or false
    end)
    f.confirmSell = confirm

    popup = f
    return f
end

function LR.RefreshSelection()
    if not popup then return end
    for i = 1, #popup.rows do
        local row = popup.rows[i]
        if row.entry then
            if i == selectedSlot then row.sel:Show() else row.sel:Hide() end
        else
            row.sel:Hide()
        end
    end
    UpdateDisenchantButton()
end

function LR.Refresh()
    if not (popup and candidates) then return end
    local n = #candidates
    popup:SetHeight(120 + n * (ROW_H + 4) + 90)

    for i = 1, #popup.rows do
        local row = popup.rows[i]
        local entry = candidates[i]
        if entry then
            local meta = itemMeta[entry]
            local nameClient, link, _, _, _, _, _, _, _, icon = GetItemInfo(entry)
            row.entry = entry
            row.slot  = i
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local displayName = link
                or (meta and meta.name ~= "" and meta.name)
                or nameClient
                or ("Item " .. entry)
            row.name:SetText(displayName)
            if meta and meta.sellPrice and meta.sellPrice > 0 then
                row.value:SetText("Vendor: " .. FormatCopper(meta.sellPrice))
            else
                row.value:SetText("")
            end
            row:Show()
        else
            row.entry = nil
            row.slot  = nil
            row:Hide()
        end
    end
    if selectedSlot > n or selectedSlot < 1 then selectedSlot = 1 end
    LR.RefreshSelection()

    local sv = GetSavedVar()
    popup.showInCombat:SetChecked(sv.showInCombat)
    popup.confirmSell:SetChecked(sv.confirmSell)
    popup.autoDisenchant:SetChecked(sv.autoDisenchant)
    UpdateDisenchantButton()
end

local warmupTimer = CreateFrame("Frame")
warmupTimer:Hide()
local warmupT, warmupLeft = 0, 0

warmupTimer:SetScript("OnUpdate", function(self, elapsed)
    warmupT = warmupT + elapsed
    if warmupT < 0.10 then return end
    warmupT = 0
    warmupLeft = warmupLeft - 1
    if popup and popup:IsShown() then LR.Refresh() end
    if warmupLeft <= 0 then self:Hide() end
end)

local function StartWarmup()
    if not candidates then return end
    for i = 1, #candidates do GetItemInfo(candidates[i]) end
    warmupT, warmupLeft = 0, 50
    warmupTimer:Show()
end

local function DelayedRequestState(ms)
    local delay = (ms or 300) / 1000
    local acc = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= delay then
            self:SetScript("OnUpdate", nil)
            if _G.AIO and _G.AIO.Handle then
                _G.AIO.Handle("AstralLevelRewardServer", "RequestState")
            end
        end
    end)
end

function LR.RequestState()
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralLevelRewardServer", "RequestState")
    end
end

function LR.OnAccept()
    if not candidates or #candidates == 0 then
        if popup then popup:Hide() end
        return
    end
    local slot = selectedSlot or 1
    if slot < 1 or slot > #candidates then slot = 1 end
    Send("levelreward pick " .. slot)
    DelayedRequestState(300)
end

function LR.OnDisenchant()
    if disenchantPending or not candidates or #candidates == 0 then return end
    local slot = selectedSlot or 1
    local itemID = candidates[slot]
    if not IsRewardDisenchantable(itemID) then
        UpdateDisenchantButton()
        return
    end
    if not (_G.AIO and _G.AIO.Handle) then
        UIErrorsFrame:AddMessage(
            "Level Reward: disenchanting is unavailable. Try /reload.",
            1.0, 0.42, 0.42, 1.0)
        return
    end

    local beforeItems = SnapshotItemInBags(itemID)
    disenchantPending = true
    if popup and popup.disenchantBtn then popup.disenchantBtn:Disable() end
    Send("levelreward pick " .. slot)
    DelayedRequestState(300)

    local waitFrame = CreateFrame("Frame")
    local elapsedTotal = 0
    local pollElapsed = 0
    waitFrame:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        pollElapsed = pollElapsed + elapsed
        if pollElapsed < 0.25 then return end
        pollElapsed = 0

        local bag, bagSlot = FindNewItemInBags(itemID, beforeItems)
        if bag and bagSlot then
            self:SetScript("OnUpdate", nil)
            _G.AIO.Handle("AstralDisenchantServer", "Submit", {
                { bag = bag, slot = bagSlot },
            })
            disenchantPending = false
            UpdateDisenchantButton()
            return
        end

        if elapsedTotal >= 8 then
            self:SetScript("OnUpdate", nil)
            disenchantPending = false
            UIErrorsFrame:AddMessage(
                "Level Reward: the selected item was not found in your bags.",
                1.0, 0.42, 0.42, 1.0)
            UpdateDisenchantButton()
        end
    end)
end

function LR.OnSell()
    if not candidates or #candidates == 0 then
        if popup then popup:Hide() end
        return
    end
    Send("levelreward sell")
    DelayedRequestState(300)
end

local function CreateReopenBtn()
    if reopenBtn then return reopenBtn end
    local b = CreateFrame("Button", "PALevelRewardReopen", UIParent)
    b:SetSize(48, 48)
    b:SetPoint("RIGHT", UIParent, "RIGHT", -80, 100)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop",  b.StopMovingOrSizing)
    b:SetClampedToScreen(true)
    b:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture("Interface\\Icons\\INV_Box_03")
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetVertexColor(1.0, 0.85, 0.3, 0.9)

    local badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    badge:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    badge:SetTextColor(1.0, 0.85, 0.3)
    b.badge = badge

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Level-Up Reward Pending")
        GameTooltip:AddLine("Click to open the choice popup.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Drag to move. Hides automatically once you pick.",
                            0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        if not lastChoice then return end
        ShowChoiceNow(lastChoice)
    end)

    reopenBtn = b
    return b
end

UpdateReopenButton = function()
    if not lastChoice then
        if reopenBtn then reopenBtn:Hide() end
        return
    end
    if popup and popup:IsShown() then
        if reopenBtn then reopenBtn:Hide() end
        return
    end
    CreateReopenBtn()
    reopenBtn.badge:SetText("")
    reopenBtn:Show()
end

ShowChoiceNow = function(head)
    if not head or not head.entries or #head.entries == 0 then return end
    candidates = {}
    for _, e in ipairs(head.entries) do
        candidates[#candidates + 1] = e
    end
    selectedSlot = 1
    CreatePopup()
    LR.Refresh()
    popup:Show()
    StartWarmup()
    UpdateReopenButton()
end

local function OnState(payload)
    if not payload then return end
    itemMeta = payload.itemMeta or {}

    if not payload.head or not payload.head.entries or #payload.head.entries == 0 then
        candidates = nil
        lastChoice = nil
        if popup and popup:IsShown() then popup:Hide() end
        UpdateReopenButton()
        return
    end

    lastChoice = payload.head

    if InCombatLockdown() and not GetSavedVar().showInCombat then
        ChatInfo("|cffaaaaaaLevel-up reward waiting until you leave combat — click the icon to open anyway.|r")
        UpdateReopenButton()
        return
    end
    ShowChoiceNow(payload.head)
end

local function RegisterLRHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local Client = _G.AIO.AddHandlers("AstralLevelReward", {})
    Client.State = function(_, payload) OnState(payload) end
    return true
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_LEVEL_UP")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")
evt:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        GetSavedVar()
        if RegisterLRHandlers() then
            DelayedRequestState(300)
        end
        return
    end
    if event == "PLAYER_LEVEL_UP" then
        DelayedRequestState(500)
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        if lastChoice and not (popup and popup:IsShown()) then
            ShowChoiceNow(lastChoice)
        end
        return
    end
end)
