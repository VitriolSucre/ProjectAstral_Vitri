
if AIO.AddAddon() then return end

local PA = ProjectAstral
local UI = PA and PA.UI

local PL = {}
PA.PL = PL

StaticPopupDialogs["PA_PERSONALLOOT_SELL_CONFIRM"] = {
    text = "Sell the highest-value personal loot for gold?\n\nThis cannot be undone.",
    button1 = YES,
    button2 = NO,
    OnAccept = function() PL.OnSell() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local popup
local candidates       -- { {entry=, quality=}, ... }
local currentQueueId
local currentBoss
local selectedSlot = 1

local POPUP_W = 380
local POPUP_H = 300
local ROW_H   = 60

local function ChatInfo(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff88[Personal Loot]|r " .. msg)
    end
end

local function GetSavedVar()
    if not ProjectAstralPersonalLoot then
        ProjectAstralPersonalLoot = {
            showInCombat = false,
            confirmSell  = true,
        }
    end
    if ProjectAstralPersonalLoot.showInCombat == nil then
        ProjectAstralPersonalLoot.showInCombat = false
    end
    if ProjectAstralPersonalLoot.confirmSell == nil then
        ProjectAstralPersonalLoot.confirmSell = true
    end
    return ProjectAstralPersonalLoot
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

local function QualityColor(q)
    if q == 5 then return 1.0, 0.5, 0.0
    elseif q == 4 then return 0.64, 0.21, 0.93
    end
    return 0.8, 0.8, 0.8
end

local lastPayload = nil
local reopenBtn

local UpdateReopenButton
local ShowNow

local function CreatePopup()
    if popup then return popup end

    local f = CreateFrame("Frame", "PAPersonalLootPopup", UIParent)
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
    tinsert(UISpecialFrames, "PAPersonalLootPopup")

    f:HookScript("OnHide", function() UpdateReopenButton() end)

    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if UI and UI.CosmicCorners then UI.CosmicCorners(f) end
    f:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.40, 0.45, 0.65)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("Personal Loot")
    title:SetTextColor(0.35, 1.0, 0.55)

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
        row.icon:SetSize(44, 44)
        row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        row.iconBorder = row:CreateTexture(nil, "ARTWORK", nil, 1)
        row.iconBorder:SetPoint("TOPLEFT",     row.icon, -1, 1)
        row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon,  1, -1)
        row.iconBorder:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 8)
        row.name:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.name:SetJustifyH("LEFT")

        row.qualityLabel = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.qualityLabel:SetPoint("LEFT", row.icon, "RIGHT", 10, -10)
        row.qualityLabel:SetJustifyH("LEFT")

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
                PL.RefreshSelection()
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
    if UI and UI.CosmicButton then UI.CosmicButton(accept) end
    accept:SetSize(115, 28)
    accept:SetPoint("BOTTOM", f, "BOTTOM", -65, 56)
    accept:SetText("Accept")
    accept:SetScript("OnClick", function() PL.OnAccept() end)
    AttachTooltip(accept, "Take the selected item.")
    f.acceptBtn = accept

    local sell = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    if UI and UI.CosmicButton then UI.CosmicButton(sell) end
    sell:SetSize(115, 28)
    sell:SetPoint("BOTTOM", f, "BOTTOM", 65, 56)
    sell:SetText("Sell")
    sell:SetScript("OnClick", function()
        if GetSavedVar().confirmSell then
            StaticPopup_Show("PA_PERSONALLOOT_SELL_CONFIRM")
        else
            PL.OnSell()
        end
    end)
    AttachTooltip(sell,
        "Auto-sell the highest-value item for gold.\n"
        .. "Confirmation is gated by the checkbox on the right.")
    f.sellBtn = sell

    local cic = CreateFrame("CheckButton", "PAPersonalLootShowInCombat", f,
                             "OptionsCheckButtonTemplate")
    cic:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
    PAPersonalLootShowInCombatText:SetText("Show popups on combat")
    cic:SetScript("OnClick", function(self)
        GetSavedVar().showInCombat = self:GetChecked() and true or false
    end)
    f.showInCombat = cic

    local confirm = CreateFrame("CheckButton", "PAPersonalLootConfirmSell", f,
                                 "OptionsCheckButtonTemplate")
    confirm:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -136, 14)
    PAPersonalLootConfirmSellText:SetText("Confirm popup on sell")
    confirm:SetScript("OnClick", function(self)
        GetSavedVar().confirmSell = self:GetChecked() and true or false
    end)
    f.confirmSell = confirm

    popup = f
    return f
end

function PL.RefreshSelection()
    if not popup then return end
    for i = 1, #popup.rows do
        local row = popup.rows[i]
        if row.entry then
            if i == selectedSlot then row.sel:Show() else row.sel:Hide() end
        else
            row.sel:Hide()
        end
    end
end

function PL.Refresh()
    if not (popup and candidates) then return end
    local n = #candidates
    popup:SetHeight(120 + n * (ROW_H + 4) + 90)

    for i = 1, #popup.rows do
        local row = popup.rows[i]
        local c = candidates[i]
        if c then
            local entry   = c.entry
            local quality = c.quality or 4
            local name, link, _, _, _, _, _, _, _, icon = GetItemInfo(entry)
            row.entry = entry
            row.slot  = i
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(link or (name or ("Item " .. entry)))
            local r, g, b = QualityColor(quality)
            row.iconBorder:SetVertexColor(r, g, b, 1.0)
            row.qualityLabel:SetText(quality == 5 and "|cffff8000Legendary|r" or "|cffa335eeEpic|r")
            row:Show()
        else
            row.entry = nil
            row.slot  = nil
            row:Hide()
        end
    end
    if selectedSlot > n or selectedSlot < 1 then selectedSlot = 1 end
    PL.RefreshSelection()

    local sv = GetSavedVar()
    popup.showInCombat:SetChecked(sv.showInCombat)
    popup.confirmSell:SetChecked(sv.confirmSell)
end

local warmupTimer = CreateFrame("Frame")
warmupTimer:Hide()
local warmupT, warmupLeft = 0, 0
warmupTimer:SetScript("OnUpdate", function(self, elapsed)
    warmupT = warmupT + elapsed
    if warmupT < 0.10 then return end
    warmupT = 0
    warmupLeft = warmupLeft - 1
    if popup and popup:IsShown() then PL.Refresh() end
    if warmupLeft <= 0 then self:Hide() end
end)

local function StartWarmup()
    if not candidates then return end
    for i = 1, #candidates do GetItemInfo(candidates[i].entry) end
    warmupT, warmupLeft = 0, 50
    warmupTimer:Show()
end

-- the race that causes a "second popup with no reward".
local function ClearLocalPickState()
    lastPayload    = nil
    candidates     = nil
    currentQueueId = nil
    currentBoss    = nil
    if popup then popup:Hide() end
    if reopenBtn then reopenBtn:Hide() end
end

function PL.OnAccept()
    if not candidates or #candidates == 0 or not currentQueueId then
        if popup then popup:Hide() end
        return
    end
    local slot = selectedSlot or 1
    if slot < 1 or slot > #candidates then slot = 1 end
    AIO.Handle("AstralPersonalLootServer", "Pick", currentQueueId, slot)
    ClearLocalPickState()
end

function PL.OnSell()
    if not candidates or #candidates == 0 or not currentQueueId then
        if popup then popup:Hide() end
        return
    end
    AIO.Handle("AstralPersonalLootServer", "Sell", currentQueueId)
    ClearLocalPickState()
end

local function CreateReopenBtn()
    if reopenBtn then return reopenBtn end
    local b = CreateFrame("Button", "PAPersonalLootReopen", UIParent)
    b:SetSize(48, 48)
    b:SetPoint("RIGHT", UIParent, "RIGHT", -80, 160)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop",  b.StopMovingOrSizing)
    b:SetClampedToScreen(true)
    b:Hide()

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture("Interface\\Icons\\INV_Box_02")
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetVertexColor(0.35, 1.0, 0.55, 0.9)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Personal Loot Pending")
        GameTooltip:AddLine("Click to open the choice popup.", 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine("Drag to move.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function()
        if not lastPayload then return end
        ShowNow(lastPayload)
    end)

    reopenBtn = b
    return b
end

UpdateReopenButton = function()
    if not lastPayload then
        if reopenBtn then reopenBtn:Hide() end
        return
    end
    if popup and popup:IsShown() then
        if reopenBtn then reopenBtn:Hide() end
        return
    end
    CreateReopenBtn()
    reopenBtn:Show()
end

ShowNow = function(payload)
    currentQueueId = payload.qid
    currentBoss    = payload.boss
    candidates = {}
    for i, item in ipairs(payload.items or {}) do
        candidates[#candidates+1] = { entry = item.entry, quality = item.quality or 4 }
    end
    selectedSlot = 1
    CreatePopup()
    PL.Refresh()
    popup:Show()
    StartWarmup()
    UpdateReopenButton()
end

local ClientHandler = AIO.AddHandlers("AstralPersonalLoot", {})

function ClientHandler.Show(player, payload)
    if type(payload) ~= "table" then return end
    lastPayload = payload

    if InCombatLockdown() and not GetSavedVar().showInCombat then
        ChatInfo("|cffaaaaaaPersonal loot waiting until you leave combat — click the icon to open anyway.|r")
        UpdateReopenButton()
        return
    end
    ShowNow(payload)
end

function ClientHandler.Empty(player)
    candidates = nil
    lastPayload = nil
    currentQueueId = nil
    currentBoss = nil
    if popup then popup:Hide() end
    UpdateReopenButton()
end

function ClientHandler.Toast(player, msg)
    if type(msg) == "string" then ChatInfo(msg) end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_REGEN_ENABLED")
evt:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        GetSavedVar()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if lastPayload and not (popup and popup:IsShown()) then
            ShowNow(lastPayload)
        end
    end
end)
