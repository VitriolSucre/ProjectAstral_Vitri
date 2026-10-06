-- GemStash.lua - MERGED VERSION
-- Live GitHub version + Dynamic rows + Removed tier badges

local _, PA = ...
PA = ProjectAstral or {}
local GS  = {}
PA.GemStash = GS

local SCROLL_SOCKET  = 99998
local SCROLL_REMOVAL = 99999
local SCROLL_ENTRIES = { [SCROLL_SOCKET] = true, [SCROLL_REMOVAL] = true }

local stock = {}
local stockLoaded = false
local itemMeta = {}


local function ItemName(entry)
    local m = itemMeta[entry]
    if m and m.name and m.name ~= "" then return m.name end
    return (select(1, GetItemInfo(entry))) or ("Item " .. tostring(entry))
end

local DelayedRequestState

-- ── Gem Stash tab: your stash and the full gem catalog ──────────────
-- "Owned" on lists what is in the account stash (with withdraw buttons); off
-- lists every gem in the catalog, owned ones marked. Each row shows the gem's
-- effect text so it can be read without hovering. Colours that must survive
-- Theme.lua's vivid-text pass are written as inline |c codes.

local FONT  = "Fonts\\FRIZQT__.TTF"
local SOLID = "Interface\\Buttons\\WHITE8X8"

local HEX_GOLD   = "|cffffd970"
local HEX_MUTED  = "|cffdcdff0"
local HEX_DIM    = "|cffaab0d4"
local HEX_DESC   = "|cffffffff"
local HEX_FLAVOR = "|cfff2dea0"

local TIER_HEX = {
    [1] = "|cffffffff", [2] = "|cff7cf26a", [3] = "|cff7fb4ff", [4] = "|cffd395ff",
    [5] = "|cffff8c26", [6] = "|cfff2d98c", [7] = "|cffff738c", [8] = "|cffff4040",
}

local TRIGGER_LABEL = {
    [0] = "Proc on Hit", [1] = "Proc on Cast", [2] = "Proc on Heal",
    [3] = "Proc on Struck", [4] = "Proc on Crit", [5] = "DoT/HoT",
}

local stashTier  = 1      -- index into TIER_FILTERS
local stashEvent = 1      -- index into EVENT_FILTERS
local stashName  = ""
local ownedOnly  = true

local stashFrame
local ROW_H = 72

-- chip order: All, T1..T8, Mythic, Scrolls
local TIER_FILTERS = {
    { label = "All",     match = function(cat, entry) return true end },
    { label = "T1",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 1 end },
    { label = "T2",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 2 end },
    { label = "T3",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 3 end },
    { label = "T4",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 4 end },
    { label = "T5",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 5 end },
    { label = "T6",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 6 end },
    { label = "T7",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 7 end },
    { label = "T8",      match = function(cat, entry) return cat and not cat.isMythic and cat.tier == 8 end },
    { label = "Mythic",  match = function(cat, entry) return cat and cat.isMythic end },
    { label = "Scrolls", match = function(cat, entry, isScroll) return isScroll end },
}

local EVENT_FILTERS = {
    { label = "Any trigger", match = function(cat) return true end },
    { label = "Hit",         match = function(cat) return cat and cat.eventType == 0 end },
    { label = "Cast",        match = function(cat) return cat and cat.eventType == 1 end },
    { label = "Heal",        match = function(cat) return cat and cat.eventType == 2 end },
    { label = "Struck",      match = function(cat) return cat and cat.eventType == 3 end },
}

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

local GS_DEBUG = false

local StartStashIconWarmup
local NotifyStockChanged

local function ApplyState(payload)
    if type(payload) ~= "table" then return end
    stock = {}
    itemMeta = (type(payload.itemMeta) == "table") and payload.itemMeta or {}
    for _, e in ipairs(payload.entries or {}) do
        local entry, count = e.entry, e.count
        if entry and count and count > 0 then
            stock[entry] = count
            if PA and PA.ItemCache then PA.ItemCache.Register(entry) end
        end
    end
    stockLoaded = true
    GS.Refresh()
    if NotifyStockChanged then NotifyStockChanged() end
    if stashFrame and stashFrame:IsVisible() and StartStashIconWarmup then
        StartStashIconWarmup()
    end
    if GS_DEBUG then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffaaffaa[GemStash dbg]|r State applied, " ..
            tostring(#(payload.entries or {})) .. " entries")
    end
end

-- ── Effect text, read from the item tooltip once and cached ──
local scanTip = CreateFrame("GameTooltip", "PA_GemStashScanTip", UIParent, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")
scanTip:Hide()

local SKIP_LINE = {}
for _, key in ipairs({ "ITEM_BIND_ON_PICKUP", "ITEM_BIND_ON_EQUIP", "ITEM_BIND_ON_USE",
                       "ITEM_SOULBOUND", "ITEM_BIND_TO_ACCOUNT", "ITEM_BIND_QUEST",
                       "ITEM_ACCOUNTBOUND", "ITEM_UNIQUE" }) do
    if _G[key] then SKIP_LINE[_G[key]] = true end
end
local SKIP_PREFIX = { "Binds ", "Soulbound", "Unique", "Requires ", "Item Level", "Sell Price", "Quest Item" }

local function SkipTooltipLine(text)
    if SKIP_LINE[text] then return true end
    for _, p in ipairs(SKIP_PREFIX) do
        if text:sub(1, #p) == p then return true end
    end
    return false
end

local descCache = {}
local function GemDescription(entry)
    if descCache[entry] then return descCache[entry] end
    if not GetItemInfo(entry) then return nil end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink("item:" .. entry .. ":0:0:0:0:0:0:0:0")
    local parts = {}
    for i = 2, scanTip:NumLines() do
        local fs = _G["PA_GemStashScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text ~= "" then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            if not SkipTooltipLine(text) then
                local hex = (text:sub(1, 1) == "\"") and HEX_FLAVOR or HEX_DESC
                parts[#parts + 1] = hex .. text .. "|r"
            end
        end
    end
    scanTip:Hide()
    local desc = table.concat(parts, "  ")
    if desc ~= "" then descCache[entry] = desc end
    return desc ~= "" and desc or nil
end
GS.GemDescription = GemDescription   -- also shown by the Astral Gems character sheet

-- ── Data ──
local function IsScroll(entry)
    local scrolls = PA.GemFusion and PA.GemFusion.scrolls
    return SCROLL_ENTRIES[entry] == true or (scrolls and scrolls[entry] ~= nil)
end

local function DisplayName(entry, cat)
    if cat and PA.GemFusion and PA.GemFusion.GemDisplayName then
        return PA.GemFusion.GemDisplayName(entry, cat)
    end
    local name = ItemName(entry)
    return (PA.CleanGemTierMarker(name):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function PassesSideFilters(entry, cat, isScroll)
    if not isScroll then
        local ef = EVENT_FILTERS[stashEvent]
        if ef and not ef.match(cat) then return false end
    elseif stashEvent ~= 1 then
        return false                      -- scrolls have no trigger
    end
    if stashName ~= "" then
        local raw = (GetItemInfo(entry)) or (cat and cat.name) or ItemName(entry)
        raw = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not raw:lower():find(stashName, 1, true) then return false end
    end
    return true
end

-- Every entry the current view can show: the stash, plus the catalog when not "Owned"
local function CollectSource()
    local seen = {}
    for entry in pairs(stock) do seen[entry] = true end
    if not ownedOnly then
        for entry in pairs((PA.GemFusion and PA.GemFusion.catalog) or {}) do seen[entry] = true end
        for entry in pairs((PA.GemFusion and PA.GemFusion.scrolls) or {}) do seen[entry] = true end
    end
    return seen
end

-- ── Rows ──
local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("LeftButtonUp")
    PA.UI.MakeRowChrome(row)

    row.altBg = row:CreateTexture(nil, "BACKGROUND")
    row.altBg:SetTexture(SOLID)
    row.altBg:SetAllPoints(row)
    row.altBg:SetVertexColor(1, 1, 1, 0.022)

    row.divider = row:CreateTexture(nil, "BORDER")
    row.divider:SetTexture(SOLID)
    row.divider:SetVertexColor(PA.UI.Tint(0.47, 0.55, 0.86, 0.10))
    row.divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    row.divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 1)
    row.divider:SetHeight(1)

    -- same warm tint as the "ready to fuse" rows in Gem Fusion
    row.ownedBg = row:CreateTexture(nil, "BACKGROUND")
    row.ownedBg:SetTexture(SOLID)
    row.ownedBg:SetAllPoints(row)
    row.ownedBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)

    row.ownedBar = row:CreateTexture(nil, "ARTWORK")
    row.ownedBar:SetTexture(SOLID)
    row.ownedBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    row.ownedBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.ownedBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.ownedBar:SetWidth(3)

    row.iconFrame = PA.UI.MakeIconFrame(row, { size = 36 })
    row.iconFrame:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -8)

    row.wAll = PA.UI.MakeButton(row, "All", { w = 40, h = 22, variant = "secondary" })
    row.wAll:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.w5 = PA.UI.MakeButton(row, "5", { w = 30, h = 22, variant = "secondary" })
    row.w5:SetPoint("RIGHT", row.wAll, "LEFT", -3, 0)
    row.w1 = PA.UI.MakeButton(row, "1", { w = 30, h = 22, variant = "secondary" })
    row.w1:SetPoint("RIGHT", row.w5, "LEFT", -3, 0)
    local function Withdraw(n)
        local d = row.data
        if not (d and d.count > 0) then return end
        Send("astralstash withdraw " .. d.entry .. " " .. math.min(n or d.count, d.count))
        DelayedRequestState(300)
    end
    row.w1:SetScript("OnClick", function() Withdraw(1) end)
    row.w5:SetScript("OnClick", function() Withdraw(5) end)
    row.wAll:SetScript("OnClick", function() Withdraw(nil) end)
    for _, b in ipairs({ row.w1, row.w5, row.wAll }) do
        b:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Withdraw to your bags", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row.count = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.count, 13)
    row.count:SetPoint("RIGHT", row.w1, "LEFT", -12, 0)
    row.count:SetJustifyH("RIGHT")

    row.title = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.title, 14)
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 56, -8)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.desc = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.desc, 12)
    row.desc:SetPoint("TOPLEFT", row, "TOPLEFT", 56, -26)
    row.desc:SetHeight(ROW_H - 30)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetJustifyV("TOP")
    row.desc:SetWordWrap(true)

    row:HookScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.data.entry .. ":0:0:0:0:0:0:0:0")
        GameTooltip:AddLine("Shift-click to link in chat", 0.62, 0.64, 0.78)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.data and IsModifiedClick("CHATLINK") and PA.InsertChatLink then
            PA.InsertChatLink(select(2, GetItemInfo(self.data.entry)))
        end
    end)
    return row
end

local RIGHT_COLUMN_W = 56 + 210   -- text indent + count/withdraw column

local function PaintRow(row, d, index, rowW)
    row.data = d
    if index % 2 == 0 then row.altBg:Show() else row.altBg:Hide() end
    if index > 1 then row.divider:Show() else row.divider:Hide() end
    if d.count > 0 then row.ownedBar:Show(); row.ownedBg:Show()
    else row.ownedBar:Hide(); row.ownedBg:Hide() end

    local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(d.entry)
    row.iconFrame:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.iconFrame:SetQuality(quality or (itemMeta[d.entry] and itemMeta[d.entry].quality)
                             or (d.cat and d.cat.quality) or 1)

    local textW = math.max(120, rowW - RIGHT_COLUMN_W)
    row.title:SetWidth(textW)
    row.desc:SetWidth(textW)

    local meta
    if d.isScroll then
        meta = HEX_MUTED .. "Scroll|r"
    else
        local cat = d.cat or {}
        if cat.isMythic then
            meta = "|cffff8c26Mythic|r"
        else
            meta = (TIER_HEX[cat.tier] or "|cffffffff") .. "T" .. tostring(cat.tier or "?") .. "|r"
        end
        local trigger = TRIGGER_LABEL[cat.eventType]
        if trigger then meta = meta .. HEX_MUTED .. "  ·  " .. trigger .. "|r" end
    end
    row.title:SetText(d.title .. "    " .. meta)

    local desc = GemDescription(d.entry)
    row.desc:SetText(desc or (HEX_DIM .. "Loading description…|r"))

    if d.count > 0 then
        row.count:SetText(HEX_GOLD .. "×" .. d.count .. "|r")
        row.w1:Show(); row.w5:Show(); row.wAll:Show()
        row.w5:SetLabel(tostring(math.min(5, d.count)))
    else
        row.count:SetText(HEX_DIM .. "Not owned|r")
        row.w1:Hide(); row.w5:Hide(); row.wAll:Hide()
    end
    row:Show()
end

local function ResetScroll()
    if not (stashFrame and stashFrame.scroll) then return end
    FauxScrollFrame_SetOffset(stashFrame.scroll, 0)
    local sb = _G[stashFrame.scroll:GetName() .. "ScrollBar"]
    if sb then sb:SetValue(0) end
end

local function BuildPanel(embedParent)
    if stashFrame then return stashFrame end

    local f, top
    if embedParent then
        f = CreateFrame("Frame", "PA_GemStashFrame", embedParent)
        f:SetAllPoints(embedParent)
        local ground = f:CreateTexture(nil, "BACKGROUND")
        ground:SetTexture(SOLID)
        ground:SetAllPoints(f)
        ground:SetVertexColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.85))
        top = -8
    else
        f = PA.UI.MakePanel(UIParent, 760, 640, {
            name    = "PA_GemStashFrame",
            strata  = "DIALOG",
            movable = true,
            point   = { "CENTER", UIParent, "CENTER", 0, 60 },
        })
        f:SetFrameLevel(100)
        f:Hide()
        tinsert(UISpecialFrames, "PA_GemStashFrame")
        f.header = PA.UI.MakeHeader(f, "Astral Gem Stash",
            "Your stash and every Astral Gem in the game")
        top = -80
    end
    stashFrame = f
    local SIDE, GAP = 10, 4
    local W = math.max(568, (embedParent and embedParent:GetWidth()) or 760)

    -- ── Header: what is listed, and Deposit all ──
    f.summary = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.summary, 13)
    f.summary:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE + 2, top - 6)

    local depAll = PA.UI.MakeButton(f, "Deposit all gems and scrolls", { w = 230, h = 24, variant = "gold" })
    depAll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, top)
    depAll:SetLabel("|cffffe39aDeposit all gems and scrolls|r")
    depAll:SetScript("OnClick", function()
        Send("astralstash depositall")
        DelayedRequestState(300)
    end)
    depAll:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Move every Astral Gem and scroll from your bags into the stash.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    depAll:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.depositAllBtn = depAll

    -- ── Tier chips ──
    local tierRowY = top - 32
    local chipW = math.floor((W - 2 * SIDE - GAP * (#TIER_FILTERS - 1)) / #TIER_FILTERS)
    f.tierChips = {}
    for i, tf in ipairs(TIER_FILTERS) do
        local idx = i
        local chip = PA.UI.MakeFilterChip(f, chipW, tf.label, function()
            stashTier = idx
            if TIER_FILTERS[idx].label == "Scrolls" then stashEvent = 1 end
            for j, c in ipairs(f.tierChips) do c:SetActive(j == idx) end
            for j, c in ipairs(f.trigChips) do c:SetActive(j == stashEvent) end
            ResetScroll()
            GS.Refresh()
        end)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE + (i - 1) * (chipW + GAP), tierRowY)
        chip:SetActive(i == stashTier)
        f.tierChips[i] = chip
    end

    -- ── Trigger chips, Owned, search ──
    local trigRowY = tierRowY - 30
    f.trigChips = {}
    local x = SIDE
    for i, ef in ipairs(EVENT_FILTERS) do
        local idx = i
        local w = (i == 1) and 84 or 58
        local chip = PA.UI.MakeFilterChip(f, w, ef.label, function()
            stashEvent = idx
            for j, c in ipairs(f.trigChips) do c:SetActive(j == idx) end
            ResetScroll()
            GS.Refresh()
        end)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", x, trigRowY)
        chip:SetActive(i == stashEvent)
        f.trigChips[i] = chip
        x = x + w + GAP
    end

    f.ownedChip = PA.UI.MakeFilterChip(f, 80, "Owned", function(self)
        ownedOnly = not ownedOnly
        self:SetActive(ownedOnly)
        ResetScroll()
        GS.Refresh()
    end)
    f.ownedChip:SetPoint("TOPLEFT", f, "TOPLEFT", x + 8, trigRowY)
    f.ownedChip:SetActive(ownedOnly)
    f.ownedChip:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(ownedOnly and "Showing your stash" or "Showing every gem", 1, 1, 1)
        GameTooltip:AddLine("Click to switch between your stash and the full catalog.", 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)

    local searchBox = PA.UI.MakeSearchBox(f, {
        width       = 160,
        height      = 24,
        placeholder = "Search gems…",
        onChanged   = function(text)
            stashName = (text or ""):lower()
            ResetScroll()
            GS.Refresh()
        end,
    })
    PA.UI.SetTextFont(searchBox.edit, 12)
    PA.UI.StyleFilterSearch(searchBox)
    searchBox:SetPoint("LEFT", f.ownedChip, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", f, "RIGHT", -SIDE, 0)
    f.searchBox = searchBox

    -- ── List (virtual rows over a FauxScrollFrame) ──
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT",     f, "TOPLEFT",     SIDE,  trigRowY - 32)
    list:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE, 10)
    PA.UI.AstralBackdrop(list, { thin = true })
    -- dark grey list (the gold rows read warm on it), whatever the Global UI color
    list:SetBackdropColor(0.099, 0.099, 0.099, 0.95)
    list:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    list.__paBackdrop = true
    f.list = list

    local scroll = CreateFrame("ScrollFrame", "PA_GemStashScroll", list, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     list, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, GS.Refresh)
    end)
    f.scroll = scroll

    f.emptyText = list:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.emptyText, 13)
    f.emptyText:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -14)
    f.emptyText:SetPoint("RIGHT", list, "RIGHT", -14, 0)
    f.emptyText:SetJustifyH("LEFT")

    -- rows are recycled; WoW 3.3.5 cannot destroy frames
    f.rows = {}
    function f:LayoutRows()
        local h = self.list:GetHeight() or 0
        local n = math.max(1, math.floor((h - 12) / ROW_H))
        for i = 1, math.max(n, #self.rows) do
            local row = self.rows[i]
            if i <= n then
                if not row then
                    row = MakeRow(self.list)
                    self.rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  self.list, "TOPLEFT",   6, -6 - (i - 1) * ROW_H)
                row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", -28, -6 - (i - 1) * ROW_H)
            elseif row then
                row.data = nil
                row:Hide()
            end
        end
        self.visibleRows = n
    end
    f:LayoutRows()

    f:HookScript("OnSizeChanged", function(self)
        self:LayoutRows()
        GS.Refresh()
    end)

    local pollAcc = 0
    f:HookScript("OnUpdate", function(self, dt)
        pollAcc = pollAcc + dt
        if pollAcc < 0.5 then return end
        pollAcc = 0
        GS.RequestState()
    end)

    return f
end

function GS.Refresh()
    if not (stashFrame and stashFrame:IsVisible()) then return end
    local f = stashFrame
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}

    local rows, ownedKinds = {}, 0
    local tf = TIER_FILTERS[stashTier]

    for entry in pairs(CollectSource()) do
        local cat      = catalog[entry]
        local isScroll = IsScroll(entry)
        if (cat or isScroll) and PassesSideFilters(entry, cat, isScroll) then
            if tf.match(cat, entry, isScroll) then
                local count = stock[entry] or 0
                if count > 0 then ownedKinds = ownedKinds + 1 end
                local title, color = DisplayName(entry, cat)
                rows[#rows + 1] = { entry = entry, cat = cat, isScroll = isScroll,
                                    count = count, title = title, color = color }
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.isScroll ~= b.isScroll then return b.isScroll end
        local am, bm = a.cat and a.cat.isMythic or false, b.cat and b.cat.isMythic or false
        if am ~= bm then return bm end
        local at, bt = a.cat and a.cat.tier or 0, b.cat and b.cat.tier or 0
        if at ~= bt then return at < bt end
        local an, bn = a.title:lower(), b.title:lower()
        if an ~= bn then return an < bn end
        return a.entry < b.entry
    end)


    if ownedOnly then
        f.summary:SetText(HEX_GOLD .. #rows .. "|r" .. HEX_MUTED .. " gem types in your stash|r")
    else
        f.summary:SetText(HEX_GOLD .. #rows .. "|r" .. HEX_MUTED .. " gems in the catalog  ·  |r"
            .. HEX_GOLD .. ownedKinds .. "|r" .. HEX_MUTED .. " owned|r")
    end

    if #rows == 0 then
        if ownedOnly and not next(stock) then
            f.emptyText:SetText(HEX_MUTED .. "Your stash is empty. Astral Gems you loot go straight into it.|r")
        elseif not ownedOnly and not next(catalog) then
            f.emptyText:SetText(HEX_MUTED .. "Loading the gem catalog…|r")
        else
            f.emptyText:SetText(HEX_MUTED .. "No gems match these filters.|r")
        end
        f.emptyText:Show()
    else
        f.emptyText:Hide()
    end

    local n = f.visibleRows or #f.rows
    FauxScrollFrame_Update(f.scroll, #rows, n, ROW_H)
    local offset = FauxScrollFrame_GetOffset(f.scroll) or 0
    local rowW = (f.list:GetWidth() or 600) - 34
    for i = 1, n do
        local row  = f.rows[i]
        local data = rows[offset + i]
        if row then
            if data then
                PaintRow(row, data, offset + i, rowW)
            else
                row.data = nil
                row:Hide()
            end
        end
    end
end

local queryTip = CreateFrame("GameTooltip", "PA_GemStashItemQueryTip", UIParent, "GameTooltipTemplate")
queryTip:SetOwner(UIParent, "ANCHOR_NONE")
queryTip:Hide()

local function ForceQueryItem(entry)
    if not entry then return end
    GetItemInfo(entry)
    queryTip:ClearLines()
    queryTip:SetHyperlink("item:" .. entry .. ":0:0:0:0:0:0:0:0")
    queryTip:Hide()
end

-- own driver: SetScript on stashFrame would wipe its stash-polling OnUpdate hook
local warmupDriver = CreateFrame("Frame")
warmupDriver:SetSize(1, 1)   -- same as GemFusion's autoDriver, so OnUpdate ticks
warmupDriver:Hide()
warmupDriver:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.10 then return end
    self.t = 0
    self.left = (self.left or 0) - 1

    local stillMissing = false
    for entry in pairs(stock) do
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry)
        if not texture then
            stillMissing = true
            ForceQueryItem(entry)
        end
    end

    GS.Refresh()

    if not stillMissing or self.left <= 0 then self:Hide() end
end)

StartStashIconWarmup = function()
    if not stashFrame then return end
    for entry in pairs(stock) do
        ForceQueryItem(entry)
    end
    warmupDriver.left, warmupDriver.t = 150, 0
    warmupDriver:Show()
end

local itemInfoEvt = CreateFrame("Frame")
itemInfoEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
itemInfoEvt:SetScript("OnEvent", function()
    if stashFrame and stashFrame:IsVisible() then
        GS.Refresh()
    end
end)

function GS.GetStock()
    return stock
end

function GS.IsLoaded()
    return stockLoaded
end

local subscribers = {}
function GS.OnStockChanged(fn)
    if type(fn) == "function" then subscribers[#subscribers+1] = fn end
end

NotifyStockChanged = function()
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn)
        if not ok and GS_DEBUG then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffff8888[GemStash]|r subscriber error: " .. tostring(err))
        end
    end
end

function GS.RequestState()
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralStashServer", "RequestState")
    end
end

DelayedRequestState = function(ms)
    local delay = (ms or 300) / 1000
    local acc = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= delay then
            self:SetScript("OnUpdate", nil)
            GS.RequestState()
        end
    end)
end
function GS.DelayedRequestState(ms) DelayedRequestState(ms) end

function GS.Toggle()
    local mf = PA.mainFrame
    if mf and mf.SwitchTab and PA._tabContent and PA._tabContent.GemStash then
        if mf:IsShown() and mf._activeTabId == "GemStash" then
            mf:Hide()
        else
            mf:Show()
            mf:SwitchTab("GemStash")
        end
        return
    end

    local f = BuildPanel()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        GS.RequestState()
        GS.Refresh()
        StartStashIconWarmup()
    end
end

local function BuildStashTab(panel)
    BuildPanel(panel)
    panel:SetScript("OnShow", function()
        GS.RequestState()
        -- the catalog view needs the gem list that Gem Fusion loads
        local gf = PA.GemFusion
        if gf and gf.RequestInfo and not next(gf.catalog or {}) then gf.RequestInfo() end
        GS.Refresh()
        StartStashIconWarmup()
    end)
end

PA:RegisterModule("GemStash", "Gem Stash", GS.Toggle, {
    subtitle = "Your account-wide stash and every Astral Gem in the game.",
})
PA:RegisterTabContent("GemStash", BuildStashTab)

local function RegisterStashHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local Client = _G.AIO.AddHandlers("AstralStash", {})
    Client.State = function(_, payload) ApplyState(payload) end
    return true
end

local bagBurstAcc = 0
local bagBurstFrame = CreateFrame("Frame")
bagBurstFrame:Hide()
bagBurstFrame:SetScript("OnUpdate", function(self, dt)
    bagBurstAcc = bagBurstAcc + dt
    if bagBurstAcc >= 0.30 then
        self:Hide()
        bagBurstAcc = 0
        GS.RequestState()
    end
end)
local function KickBagBurst()
    bagBurstAcc = 0
    bagBurstFrame:Show()
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("BAG_UPDATE")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:SetScript("OnEvent", function(self, event, msg)
    if event == "PLAYER_LOGIN" then
        if RegisterStashHandlers() then
            DelayedRequestState(300)
        end
        return
    end
    if event == "BAG_UPDATE" then
        if stashFrame and stashFrame:IsVisible() then
            KickBagBurst()
        end
        return
    end
    if event == "CHAT_MSG_SYSTEM" and msg then
        if msg:sub(1, 12) == "Astral Gem: " then
            local body = msg:match("^Astral Gem:%s*(.-)%s*dropped")
            if body and body ~= "" and PA.UI and PA.UI.GainPopup then
                PA.UI.GainPopup("Gem drop: " .. body, "gems",
                    { fontSize = 10 })
            end
        end
        return
    end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    return msg and msg:sub(1, 12) == ".astralstash"
        and author == UnitName("player")
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    return msg and msg:sub(1, 12) == "Astral Gem: "
end)
