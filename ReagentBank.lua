
local PA = ProjectAstral
if not PA then return end

local AB = {}

AB.unlocked      = false
AB.stock         = {}
AB.itemMeta      = {}
AB.totalValue    = 0
AB.sortedKeys    = {}
AB.filterText    = ""
AB.receiving     = false
AB.selectedEntry = nil

local QUALITY_COLOR = {
    [0] = "|cff9d9d9d",
    [1] = "|cffffffff",
    [2] = "|cff1eff00",
    [3] = "|cff0070dd",
    [4] = "|cffa335ee",
    [5] = "|cffff8000",
    [6] = "|cffe6cc80",
    [7] = "|cffe6cc80",
}

local function ItemName(entry)
    local m = AB.itemMeta[entry]
    if m and m.name and m.name ~= "" then return m.name end
    return GetItemInfo(entry)
end

PA.astralbank = AB

local function SendServer(method, ...)
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralBankServer", method, ...)
    end
end

-- Auto-deposit (on by default); the timer and triggers live further down.
local function AutoDepositEnabled()
    return not (PA.Settings and PA.Settings.reagentAutoDeposit == false)
end
local KickAutoDeposit = function() end

-- 3.3.5 GetItemInfo doesn't trigger fetch on miss; hidden tooltip SetHyperlink does.
local prefetchTip
local function PrefetchItem(itemEntry)
    if not itemEntry then return end
    if GetItemInfo(itemEntry) then return end
    if not prefetchTip then
        prefetchTip = CreateFrame("GameTooltip", "ABPrefetchTooltip",
                                  UIParent, "GameTooltipTemplate")
        prefetchTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    prefetchTip:ClearLines()
    prefetchTip:SetHyperlink("item:" .. itemEntry .. ":0:0:0:0:0:0:0")
    prefetchTip:Hide()
end

local bankFrame

local function RebuildSortedKeys()
    AB.sortedKeys = {}
    local needle = (AB.filterText or ""):lower()
    for entry, count in pairs(AB.stock) do
        if count > 0 then
            if needle == "" then
                AB.sortedKeys[#AB.sortedKeys + 1] = entry
            else
                local name = ItemName(entry)
                if not name or name:lower():find(needle, 1, true) then
                    AB.sortedKeys[#AB.sortedKeys + 1] = entry
                end
            end
        end
    end
    table.sort(AB.sortedKeys, function(a, b)
        local na = ItemName(a) or ""
        local nb = ItemName(b) or ""
        if na == "" and nb ~= "" then return false end
        if nb == "" and na ~= "" then return true  end
        if na == nb then return a < b end
        return na < nb
    end)
end

local function RequestSnapshot()
    AB.receiving = true
    SendServer("RequestState")
end

local UpdateTradeReagents = function() end

local function ApplyState(payload)
    if type(payload) ~= "table" then return end
    AB.unlocked = payload.unlocked and true or false
    AB.stock    = {}
    AB.itemMeta = (type(payload.itemMeta) == "table") and payload.itemMeta or {}
    AB.totalValue = tonumber(payload.totalValue) or 0
    if AB.unlocked and type(payload.stock) == "table" then
        for entry, count in pairs(payload.stock) do
            local e = tonumber(entry)
            local c = tonumber(count)
            if e and c and c > 0 then
                AB.stock[e] = c
                PrefetchItem(e)
            end
        end
    end
    AB.receiving = false
    RebuildSortedKeys()
    if bankFrame then
        bankFrame:RefreshLockState()
        bankFrame:RefreshList()
    end
    UpdateTradeReagents()
    KickAutoDeposit()   -- bags may already hold reagents when the bank state arrives
end

local function RecomputeTotalValue()
    local sum = 0
    for entry, count in pairs(AB.stock) do
        local m = AB.itemMeta[entry]
        if m and m.sellPrice and m.sellPrice > 0 and count > 0 then
            sum = sum + m.sellPrice * count
        end
    end
    AB.totalValue = sum
end

local function ApplyUpdate(entry, count)
    entry = tonumber(entry)
    count = tonumber(count) or 0
    if not entry then return end
    if count > 0 then
        AB.stock[entry] = count
        PrefetchItem(entry)
    else
        AB.stock[entry] = nil
        if AB.selectedEntry == entry then AB.selectedEntry = nil end
    end
    RebuildSortedKeys()
    RecomputeTotalValue()
    if bankFrame then
        bankFrame:RefreshList()
    end
    UpdateTradeReagents()
end

local ERR_MSG = {
    LOCKED       = "Astral Reagent Bank not unlocked.",
    DISABLED     = "Reagent bank is currently disabled.",
    NOT_REAGENT  = "That item is not a reagent.",
    NO_ITEM      = "You don't have that item.",
    INSUFFICIENT = "Bank doesn't have enough of that item.",
    INV_FULL     = "Inventory full.",
    CASTING      = "Can't move reagents while casting.",
}
local function ApplyError(reason)
    DEFAULT_CHAT_FRAME:AddMessage(
        "|cffff4444[Reagent Bank]|r " ..
        (ERR_MSG[reason] or ("Error: " .. tostring(reason))))
end

local BANK_W   = 568
local ROW_H    = 46
local ICON_SZ  = 38
local SEARCH_H = 34
local FOOTER_H = 96
local MAX_ROWS = 50

local rows = {}

local function CreateRow(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -((idx - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -((idx - 1) * ROW_H))
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if idx % 2 == 0 then bg:SetTexture(PA.UI.Tint(0.043, 0.067, 0.188, 0.65))   -- navy rows
    else                 bg:SetTexture(PA.UI.Tint(0.063, 0.090, 0.227, 0.65)) end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.35, 0.35, 0.35)

    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetTexture(PA.UI.Tint(0.30, 0.50, 0.80, 0.30))
    sel:SetAllPoints()
    sel:Hide()
    row.sel = sel

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon = icon

    local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameStr:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    nameStr:SetPoint("LEFT",  icon, "RIGHT", 8, 0)
    nameStr:SetPoint("RIGHT", row,  "RIGHT", -110, 0)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("...")
    row.nameStr = nameStr

    local countStr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countStr:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    countStr:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    countStr:SetJustifyH("RIGHT")
    countStr:SetTextColor(1, 0.82, 0)
    countStr:SetText("0")
    row.countStr = countStr

    row:SetScript("OnEnter", function(self)
        if self.itemEntry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemEntry .. ":0:0:0:0:0:0:0")
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row:SetScript("OnClick", function(self)
        if not self.itemEntry then return end
        if IsModifiedClick("CHATLINK") then   -- Shift-click links the reagent
            local _, link = GetItemInfo(self.itemEntry)
            if link and PA.InsertChatLink then PA.InsertChatLink(link) end
            return
        end
        AB.selectedEntry = self.itemEntry
        if bankFrame then bankFrame:RefreshSelection() end
    end)

    return row
end

local function PopulateRow(row, entry)
    row.itemEntry = entry
    if entry then
        local meta = AB.itemMeta[entry]
        local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(entry)
        if not iconPath then PrefetchItem(entry) end

        local displayName = ItemName(entry) or ("Item #" .. entry)
        local q = meta and meta.quality or nil
        if q and QUALITY_COLOR[q] then
            displayName = QUALITY_COLOR[q] .. displayName .. "|r"
        end

        row.icon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.nameStr:SetText(displayName)
        row.countStr:SetText(tostring(AB.stock[entry] or 0))
        if AB.selectedEntry == entry then row.sel:Show() else row.sel:Hide() end
        row:Show()
    else
        row:Hide()
    end
end

local function BuildBankTab(panel)
    local UI = PA.UI
    local f  = panel
    _G["PAReagentBankFrame"] = f

    local searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    searchBox:SetSize(220, SEARCH_H)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    searchBox:SetTextInsets(8, 8, 2, 2)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            AB.filterText = self:GetText() or ""
            RebuildSortedKeys()
            FauxScrollFrame_SetOffset(f.scroll, 0)
            f.scroll:SetVerticalScroll(0)
            f:RefreshList()
        end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    hint:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    hint:SetText("Search reagents...")
    searchBox:SetScript("OnEditFocusGained", function() hint:Hide() end)
    searchBox:SetScript("OnEditFocusLost",   function(self)
        if self:GetText() == "" then hint:Show() end
    end)
    f.searchBox = searchBox

    local autoDep = CreateFrame("CheckButton", "PAReagentBankAutoDeposit", f,
        "InterfaceOptionsCheckButtonTemplate")
    autoDep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -190, -6)
    _G[autoDep:GetName() .. "Text"]:SetText("Auto-deposit reagents")
    _G[autoDep:GetName() .. "Text"]:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    _G[autoDep:GetName() .. "Text"]:SetTextColor(unpack(UI.Color.textPrimary))
    autoDep.tooltipText = "Reagents that land in your bags are sent to the bank automatically. "
        .. "Paused while a profession, bank, mailbox, trade, auction house or vendor window is open."
    autoDep:SetChecked(AutoDepositEnabled())
    autoDep:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if PA.SaveSetting then PA.SaveSetting("reagentAutoDeposit", on) end
        if on then KickAutoDeposit() end
    end)
    f.autoDepositCheck = autoDep
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -6)
    searchBox:SetPoint("RIGHT", autoDep, "LEFT", -14, 0)

    local sepTop = UI.SolidFill(f, UI.Nav.edge, "OVERLAY")
    sepTop:SetHeight(1)
    sepTop:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -(SEARCH_H + 10))
    sepTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -(SEARCH_H + 10))
    sepTop:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                          UI.Color.accentSoft[3], 0.55)

    local inventoryLabel = UI.MakeSectionDivider(f, "REAGENT INVENTORY",
        { "TOPLEFT", f, "TOPLEFT", 10, -(SEARCH_H + 20) })
    inventoryLabel:SetFont("Fonts\\FRIZQT__.TTF", 13, "")

    local scroll = CreateFrame("ScrollFrame", "PABankScrollFrame", f,
                               "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(SEARCH_H + 42))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, FOOTER_H)
    UI.AstralBackdrop(scroll, { thin = true, bg = UI.Nav.deep,
                                border = UI.Nav.edge })
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function()
            f:RefreshList()
        end)
    end)
    f.scroll = scroll

    local rowFrame = CreateFrame("Frame", nil, f)
    rowFrame:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -6)
    rowFrame:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", -28, 6)
    for i = 1, MAX_ROWS do rows[i] = CreateRow(rowFrame, i) end

    local lockedBanner = CreateFrame("Frame", nil, f)
    lockedBanner:SetAllPoints(f)
    lockedBanner:SetFrameLevel(f:GetFrameLevel() + 20)
    lockedBanner:EnableMouse(true)
    local lockedBg = lockedBanner:CreateTexture(nil, "BACKGROUND")
    lockedBg:SetAllPoints()
    lockedBg:SetTexture(0.04, 0.04, 0.08, 0.92)
    local lockedText = lockedBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    lockedText:SetPoint("CENTER")
    lockedText:SetText("|cffff5555Astral Reagent Bank locked.|r\n\nUnlock the |cff88ccffReagent Bank|r node in the Astral Skill Tree\nto begin storing reagents.")
    lockedText:SetJustifyH("CENTER")
    lockedBanner:Hide()
    f.lockedBanner = lockedBanner

    local sepBot = UI.SolidFill(f, UI.Nav.edge, "OVERLAY")
    sepBot:SetHeight(1)
    sepBot:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, FOOTER_H)
    sepBot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOTER_H)
    sepBot:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                          UI.Color.accentSoft[3], 0.55)

    local FOOTER_Y         = 18
    local ACTION_BUTTON_W  = 220

    local selLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selLabel:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    selLabel:SetJustifyH("LEFT")
    selLabel:SetText("Select a reagent to withdraw.")
    selLabel:SetTextColor(unpack(UI.Color.textPrimary))
    f.selLabel = selLabel

    local INPUT_W, INPUT_H = 76, 30
    local amountInput = CreateFrame("EditBox", nil, f)
    amountInput:SetSize(INPUT_W, INPUT_H)
    amountInput:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 86, FOOTER_Y + 12)
    selLabel:SetPoint("BOTTOM", amountInput, "TOP", 0, 5)
    selLabel:SetWidth(190)
    selLabel:SetJustifyH("CENTER")
    amountInput:SetAutoFocus(false)
    amountInput:SetNumeric(true)
    amountInput:SetMaxLetters(10)
    amountInput:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    amountInput:SetJustifyH("CENTER")
    amountInput:SetTextInsets(4, 4, 2, 2)
    amountInput:SetText("1")
    local inputBg = amountInput:CreateTexture(nil, "BACKGROUND")
    inputBg:SetAllPoints()
    inputBg:SetTexture(PA.UI.Tint(0.031, 0.047, 0.133, 0.95))
    local function makeEdge(parent, w, h, anchor, relX, relY)
        local t = parent:CreateTexture(nil, "BORDER")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(UI.Nav.edgeMid[1], UI.Nav.edgeMid[2],
                         UI.Nav.edgeMid[3], 1)
        t:SetSize(w, h)
        t:SetPoint(anchor, parent, anchor, relX, relY)
        return t
    end
    makeEdge(amountInput, INPUT_W, 1, "TOPLEFT",     0,  0)
    makeEdge(amountInput, INPUT_W, 1, "BOTTOMLEFT",  0,  0)
    makeEdge(amountInput, 1, INPUT_H, "TOPLEFT",     0,  0)
    makeEdge(amountInput, 1, INPUT_H, "TOPRIGHT",    0,  0)
    local amountLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    amountLabel:SetPoint("RIGHT", amountInput, "LEFT", -8, 0)
    amountLabel:SetText("Amount")
    amountLabel:SetTextColor(unpack(UI.Nav.muted))
    amountInput:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local n = math.floor(tonumber(self:GetText()) or 1)
        local hi = AB.selectedEntry and (AB.stock[AB.selectedEntry] or 1) or 1
        if n < 1 then n = 1 elseif n > hi then n = hi end
        if tostring(n) ~= self:GetText() then self:SetText(tostring(n)) end
    end)
    amountInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    amountInput:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.amountInput = amountInput

    local withdrawBtn = UI.MakeButton(f, "Withdraw", {
        w = ACTION_BUTTON_W, h = 32,
        variant = "gold",
        onClick = function()
            local entry = AB.selectedEntry
            if not entry then return end
            local n = math.floor(tonumber(amountInput:GetText()) or 0)
            if n < 1 or n > (AB.stock[entry] or 0) then return end
            SendServer("Withdraw", entry, n)
        end,
    })
    withdrawBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    withdrawBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, FOOTER_Y + 12)
    f.withdrawBtn = withdrawBtn

    local depositAllBtn = UI.MakeButton(f, "Deposit All Reagents", {
        w = ACTION_BUTTON_W, h = 32,
        variant = "secondary",
        onClick = function()
            SendServer("DepositAll")
        end,
    })
    depositAllBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    depositAllBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, FOOTER_Y + 40)

    function f:RefreshList()
        local n      = #AB.sortedKeys
        local offset = FauxScrollFrame_GetOffset(self.scroll)
        local visibleRows = math.floor((self.scroll:GetHeight() or 0) / ROW_H)
        visibleRows = math.max(1, math.min(#rows, visibleRows))
        for i = 1, visibleRows do
            PopulateRow(rows[i], AB.sortedKeys[i + offset])
        end
        for i = visibleRows + 1, #rows do rows[i]:Hide() end
        FauxScrollFrame_Update(self.scroll, n, visibleRows, ROW_H)
        if n == 0 and AB.unlocked then
            self.selLabel:SetText("|cff888888Bank is empty. Deposit reagents from your bags.|r")
        elseif not AB.selectedEntry then
            self.selLabel:SetText("Select a reagent to withdraw.")
        else
            self:RefreshSelection()
        end
    end

    scroll:SetScript("OnSizeChanged", function()
        if f.RefreshList then f:RefreshList() end
    end)

    function f:RefreshSelection()
        local entry = AB.selectedEntry
        if not entry or not AB.stock[entry] then
            self.selLabel:SetText("Select a reagent to withdraw.")
            self.amountInput:SetText("1")
            return
        end
        local count = AB.stock[entry]
        local name  = GetItemInfo(entry) or ("Item #" .. entry)
        self.selLabel:SetText("|cffffcc00" .. name .. "|r")
        local cur = math.floor(tonumber(self.amountInput:GetText()) or 1)
        if cur < 1 then cur = 1 elseif cur > count then cur = count end
        self.amountInput:SetText(tostring(cur))
    end

    function f:RefreshLockState()
        if AB.unlocked then
            self.lockedBanner:Hide()
        else
            self.lockedBanner:Show()
            AB.stock = {}
            AB.sortedKeys = {}
            AB.selectedEntry = nil
            self:RefreshList()
        end
    end

    f:SetScript("OnShow", function(self)
        self:RefreshLockState()
        RequestSnapshot()
    end)

    f:HookScript("OnHide", function(self)
        if self.lockedBanner then self.lockedBanner:Hide() end
        if self.searchBox    then self.searchBox:ClearFocus() end
    end)

    bankFrame = f
    f:RefreshLockState()
end

local function OnItemInfoReceived()
    if bankFrame and bankFrame:IsShown() then
        RebuildSortedKeys()
        bankFrame:RefreshList()
    end
end

local function RegisterAstralBankHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralBank", {})

    ClientHandler.State = function(_, payload)
        ApplyState(payload)
    end

    ClientHandler.Update = function(_, entry, count)
        ApplyUpdate(entry, count)
    end

    ClientHandler.Error = function(_, reason)
        -- an automatic deposit that failed (casting, locked...) stays quiet
        if AB._autoDepositAt and GetTime() - AB._autoDepositAt < 5 then
            AB._autoDepositAt = nil
            return
        end
        ApplyError(reason)
    end

    local function ItemLabel(entry)
        entry = tonumber(entry) or 0
        local _, link = GetItemInfo(entry)
        return link or ("item " .. entry)
    end

    ClientHandler.DepositAck = function(_, entry, deposited, newTotal)
        if newTotal ~= nil then
            ApplyUpdate(entry, newTotal)
        else
            RequestSnapshot()
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff88ccff[Reagent Bank]|r Deposited %d x %s (new total: %d)",
            tonumber(deposited) or 0, ItemLabel(entry), tonumber(newTotal) or 0))
    end

    ClientHandler.WithdrawAck = function(_, entry, count, newTotal)
        if newTotal ~= nil then
            ApplyUpdate(entry, newTotal)
        else
            RequestSnapshot()
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff88ccff[Reagent Bank]|r Withdrew %d x %s (remaining: %d)",
            tonumber(count) or 0, ItemLabel(entry), tonumber(newTotal) or 0))
    end

    ClientHandler.DepositAllAck = function(_, totalItems, totalKinds)
        totalItems = tonumber(totalItems) or 0
        totalKinds = tonumber(totalKinds) or 0
        if totalItems > 0 then RequestSnapshot() end
        if AB._autoDepositAt and GetTime() - AB._autoDepositAt < 5 then
            AB._autoDepositAt = nil
            if totalItems == 0 then return end   -- nothing the bank accepts: no chat spam
            DEFAULT_CHAT_FRAME:AddMessage(string.format(
                "|cff88ccff[Reagent Bank]|r Auto-deposited %d item%s.",
                totalItems, totalItems == 1 and "" or "s"))
            return
        end
        if totalItems == 0 then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff88ccff[Reagent Bank]|r No reagents found in bags to deposit.")
            return
        end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff88ccff[Reagent Bank]|r Deposited %d item%s across %d stack%s.",
            totalItems, totalItems == 1 and "" or "s",
            totalKinds, totalKinds == 1 and "" or "s"))
    end

    return true
end

-- ── Auto-deposit ────────────────────────────────────────────────────
-- A couple of seconds after your bags change, reagents are sent to the bank with
-- the same DepositAll the button uses (the server decides what counts as a
-- reagent). Paused while a window where you want reagents in your bags is open:
-- professions (crafting pulls reagents out of the bank first), bank, mail, trade,
-- auction house, vendor, guild bank. Also skipped in combat and while casting.
local AUTO_DELAY   = 2.0
local PAUSE_FRAMES = { "TradeSkillFrame", "BankFrame", "MailFrame", "TradeFrame",
                       "AuctionFrame", "MerchantFrame", "GuildBankFrame" }

local function AutoDepositPaused()
    if InCombatLockdown() then return true end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return true end
    for _, name in ipairs(PAUSE_FRAMES) do
        local fr = _G[name]
        if fr and fr:IsShown() then return true end
    end
    return false
end

-- Trade Goods in the bags, by the client's localized item class (6th auction class)
local tradeGoodsClass
local function BagTradeGoodsCount()
    if not tradeGoodsClass and GetAuctionItemClasses then
        tradeGoodsClass = select(6, GetAuctionItemClasses())
    end
    if not tradeGoodsClass then return 0 end
    local n = 0
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, _, _, _, itemType = GetItemInfo(link)
                if itemType == tradeGoodsClass then
                    local _, count = GetContainerItemInfo(bag, slot)
                    n = n + (count or 1)
                end
            end
        end
    end
    return n
end

local autoDriver = CreateFrame("Frame")
autoDriver:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
autoDriver:Hide()
local autoWait, lastAttemptCount = 0, nil

autoDriver:SetScript("OnUpdate", function(self, dt)
    autoWait = autoWait - dt
    if autoWait > 0 then return end
    self:Hide()
    if not (AutoDepositEnabled() and AB.unlocked) or AutoDepositPaused() then return end
    local n = BagTradeGoodsCount()
    -- nothing to send, or the same leftovers the bank already turned down
    if n <= 0 or n == lastAttemptCount then return end
    lastAttemptCount = n
    AB._autoDepositAt = GetTime()
    SendServer("DepositAll")
end)

KickAutoDeposit = function()
    if not (AutoDepositEnabled() and AB.unlocked) then return end
    autoWait = AUTO_DELAY
    autoDriver:Show()
end

local autoEvents = CreateFrame("Frame")
for _, ev in ipairs({ "BAG_UPDATE", "PLAYER_REGEN_ENABLED", "TRADE_SKILL_CLOSE",
                      "BANKFRAME_CLOSED", "MAIL_CLOSED", "TRADE_CLOSED",
                      "AUCTION_HOUSE_CLOSED", "MERCHANT_CLOSED", "GUILDBANKFRAME_CLOSED" }) do
    autoEvents:RegisterEvent(ev)
end
autoEvents:SetScript("OnEvent", function() KickAutoDeposit() end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        if RegisterAstralBankHandlers() then
            SendServer("RequestState")
        end
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        OnItemInfoReceived()
    end
end)

local function ToggleBankFrame()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "reagent_bank" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("reagent_bank")
        if mf._tabBar then mf._tabBar:SelectTab("reagent_bank") end
    end
end

PA:RegisterModule("reagent_bank", "Reagent Bank", ToggleBankFrame, {
    subtitle = "Account-wide storage for crafting reagents (unlocked via the Astral Tree).",
})
PA:RegisterTabContent("reagent_bank", BuildBankTab)

-- 3.3.5 client gates Create on bag-only counts from GetTradeSkillReagentInfo;
-- override to return bag+bank or the cast never leaves the client.
local function ParseItemId(link)
    if not link then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

local _origGetReagentInfo
local _origDoTradeSkill

local function RealBagCount(skillIndex, reagentIndex)
    if not _origGetReagentInfo then return nil end
    local _, _, _, have = _origGetReagentInfo(skillIndex, reagentIndex)
    return have
end

local pullThenDo

local function InstallTradeSkillOverrides()
    if _origGetReagentInfo then return end
    if type(GetTradeSkillReagentInfo) ~= "function" then return end

    _origGetReagentInfo = GetTradeSkillReagentInfo
    _origDoTradeSkill   = DoTradeSkill

    GetTradeSkillReagentInfo = function(skillIndex, reagentIndex)
        local name, tex, need, have = _origGetReagentInfo(skillIndex, reagentIndex)
        if AB.unlocked and name then
            local link = GetTradeSkillReagentItemLink(skillIndex, reagentIndex)
            local entry = ParseItemId(link)
            if entry and AB.stock[entry] then
                have = (have or 0) + AB.stock[entry]
            end
        end
        return name, tex, need, have
    end

    DoTradeSkill = function(skillIndex, count)
        if not skillIndex or skillIndex == 0 then return end
        if not AB.unlocked then return _origDoTradeSkill(skillIndex, count) end
        return pullThenDo(skillIndex, count)
    end
end

UpdateTradeReagents = function()
    if not AB.unlocked then return end
    if not TradeSkillFrame or not TradeSkillFrame:IsShown() then return end
    if not GetTradeSkillSelectionIndex then return end
    local selIdx = GetTradeSkillSelectionIndex()
    if not selIdx or selIdx == 0 then return end

    local num = GetTradeSkillNumReagents(selIdx) or 0
    local bankCovers = true

    for i = 1, num do
        local _, _, need = GetTradeSkillReagentInfo(selIdx, i)
        local realHave   = RealBagCount(selIdx, i) or 0
        local link       = GetTradeSkillReagentItemLink(selIdx, i)
        local widget     = _G["TradeSkillReagent" .. i .. "Count"]
        local entry      = link and ParseItemId(link) or nil
        local banked     = (entry and AB.stock[entry]) or 0
        if need and need > 0 then
            if realHave < need then
                if widget then
                    if realHave + banked >= need then
                        widget:SetText(string.format(
                            "|cffff9933%d(+%d)|r/%d", realHave, banked, need))
                    else
                        widget:SetText(string.format(
                            "|cffff2020%d(+%d)|r/%d", realHave, banked, need))
                    end
                end
                if realHave + banked < need then
                    bankCovers = false
                end
            end
        end
    end

    if bankCovers then
        if TradeSkillCreateButton then TradeSkillCreateButton:Enable() end
        if TradeSkillCreateAllButton then TradeSkillCreateAllButton:Enable() end
    end
end

local function computePullsFor(skillIndex, batchCount)
    batchCount = math.max(1, tonumber(batchCount) or 1)
    local pulls = {}
    if not AB.unlocked or not _origGetReagentInfo then return pulls end
    for i = 1, (GetTradeSkillNumReagents(skillIndex) or 0) do
        local _, _, need = _origGetReagentInfo(skillIndex, i)
        local have       = RealBagCount(skillIndex, i) or 0
        if need and need > 0 then
            local totalNeed = need * batchCount
            if have < totalNeed then
                local link   = GetTradeSkillReagentItemLink(skillIndex, i)
                local entry  = ParseItemId(link)
                local banked = (entry and AB.stock[entry]) or 0
                local missing = totalNeed - have
                if not entry or banked < missing then return nil end
                pulls[#pulls + 1] = { entry = entry, count = missing }
            end
        end
    end
    return pulls
end

local function bagSatisfiesFor(skillIndex, batchCount)
    batchCount = math.max(1, tonumber(batchCount) or 1)
    if not _origGetReagentInfo then return true end
    for i = 1, (GetTradeSkillNumReagents(skillIndex) or 0) do
        local _, _, need = _origGetReagentInfo(skillIndex, i)
        local have       = RealBagCount(skillIndex, i) or 0
        if need and have < need * batchCount then return false end
    end
    return true
end

local function maxBatchFromBankAndBag(skillIndex)
    local minBatch = math.huge
    for i = 1, (GetTradeSkillNumReagents(skillIndex) or 0) do
        local _, _, need = _origGetReagentInfo(skillIndex, i)
        if need and need > 0 then
            local have   = RealBagCount(skillIndex, i) or 0
            local link   = GetTradeSkillReagentItemLink(skillIndex, i)
            local entry  = link and ParseItemId(link) or nil
            local banked = (entry and AB.stock[entry]) or 0
            local possible = math.floor((have + banked) / need)
            if possible < minBatch then minBatch = possible end
        end
    end
    if minBatch == math.huge then return 1 end
    return math.max(1, minBatch)
end

pullThenDo = function(skillIndex, count)
    local batch = tonumber(count) or 1
    if batch <= 0 then batch = maxBatchFromBankAndBag(skillIndex) end
    local pulls = computePullsFor(skillIndex, batch)
    if pulls == nil then
        UIErrorsFrame:AddMessage(SPELL_FAILED_REAGENTS or "Missing reagents",
                                 1, 0.1, 0.1, 1, 5)
        return
    end
    if #pulls == 0 then
        return _origDoTradeSkill(skillIndex, batch)
    end
    -- Two-click: auto-firing after BAG_UPDATE trips taint (no user-input flag).
    for _, p in ipairs(pulls) do
        SendServer("Withdraw", p.entry, p.count)
    end
    local listener = CreateFrame("Frame")
    local started  = GetTime()
    listener:RegisterEvent("BAG_UPDATE")
    listener:SetScript("OnEvent", function(self)
        if bagSatisfiesFor(skillIndex, batch) then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
            UIErrorsFrame:AddMessage("|cff99ccffReagents pulled \226\128\148 click Create again|r",
                                     0.5, 1, 0.5, 1, 4)
        elseif GetTime() - started > 3 then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
            UIErrorsFrame:AddMessage("Bank withdraw timed out",
                                     1, 0.1, 0.1, 1, 5)
        end
    end)
end

local _disableHooked = false
local function HookButtonDisable()
    if _disableHooked then return end
    if not TradeSkillCreateButton or not TradeSkillCreateAllButton then return end
    _disableHooked = true
    local function reenable(btn)
        local selIdx = GetTradeSkillSelectionIndex and GetTradeSkillSelectionIndex() or 0
        if selIdx == 0 or not AB.unlocked then return end
        local pulls = computePullsFor(selIdx)
        if pulls then btn:Enable() end
    end
    TradeSkillCreateButton:HookScript("OnDisable",    function(self) reenable(self) end)
    TradeSkillCreateAllButton:HookScript("OnDisable", function(self) reenable(self) end)
end

local _tsHooked = false
local function HookTradeSkillFrame()
    if _tsHooked then return end
    if not TradeSkillFrame then return end
    _tsHooked = true
    InstallTradeSkillOverrides()
    HookButtonDisable()
    if TradeSkillFrame_SetSelection then
        hooksecurefunc("TradeSkillFrame_SetSelection", UpdateTradeReagents)
    end
    if TradeSkillFrame_Update then
        hooksecurefunc("TradeSkillFrame_Update", UpdateTradeReagents)
    end
end

local _tsEvt = CreateFrame("Frame")
_tsEvt:RegisterEvent("PLAYER_LOGIN")
_tsEvt:RegisterEvent("TRADE_SKILL_SHOW")
_tsEvt:RegisterEvent("TRADE_SKILL_UPDATE")
_tsEvt:SetScript("OnEvent", function(_, ev)
    InstallTradeSkillOverrides()
    if ev ~= "PLAYER_LOGIN" then
        HookTradeSkillFrame()
        UpdateTradeReagents()
    end
end)
