
local PA = ProjectAstral

local PS = {}

PS.tokens         = 0
PS.categories     = {}
PS.items          = {}
PS.byCategory     = {}
PS.receiving      = false
PS.activeCategory = nil
PS.activeFilter   = nil
PS.selectedEntry  = nil

local SUBTYPE_TO_FILTER = {
    ["Cloth"]              = "cloth",
    ["Leather"]            = "leather",
    ["Mail"]               = "mail",
    ["Plate"]              = "plate",
    ["Stoff"]              = "cloth",
    ["Leder"]              = "leather",
    ["Kettenpanzer"]       = "mail",
    ["Schwere Rüstung"]    = "mail",
    ["Plattenpanzer"]      = "plate",
    ["Plattenrüstung"]     = "plate",
}

local WEAPON_TYPE_NAMES = {
    ["Weapon"] = true, ["Waffe"] = true,
}
local ARMOR_TYPE_NAMES = {
    ["Armor"] = true, ["Rüstung"] = true,
}
local MISC_EQUIP_LOCS = {
    ["INVTYPE_FINGER"]   = true,
    ["INVTYPE_TRINKET"]  = true,
    ["INVTYPE_NECK"]     = true,
    ["INVTYPE_HOLDABLE"] = true,
    ["INVTYPE_CLOAK"]    = true,
}

local itemClassCache = {}

local function ItemFilterClass(itemId)
    if not itemId then return nil end
    if itemClassCache[itemId] then return itemClassCache[itemId] end
    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemId)
    if not itemType then return nil end
    local cls = "misc"
    if WEAPON_TYPE_NAMES[itemType] then
        cls = "weapons"
    elseif ARMOR_TYPE_NAMES[itemType] then
        local sub = SUBTYPE_TO_FILTER[itemSubType]
        if sub then cls = sub
        elseif MISC_EQUIP_LOCS[equipLoc] then cls = "misc"
        else cls = "misc" end
    else
        cls = "misc"
    end
    itemClassCache[itemId] = cls
    return cls
end

local function MatchesFilter(entry, filter)
    if not filter or filter == "all" then return true end
    local cls = ItemFilterClass(entry.item)
    if cls == nil then return true end
    return cls == filter
end

local FILTERABLE_CATEGORIES = {
    ["Heirloom"]   = true,
    ["Heirlooms"]  = true,
    ["Erbstück"]   = true,
    ["Erbstücke"]  = true,
}

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

local prefetchTip
local function PrefetchItem(itemEntry)
    if not itemEntry then return end
    if PA and PA.ItemCache then
        PA.ItemCache.Register(itemEntry)
        return
    end
    if GetItemInfo(itemEntry) then return end
    if not prefetchTip then
        prefetchTip = CreateFrame("GameTooltip", "PSPrefetchTooltip",
                                  UIParent, "GameTooltipTemplate")
        prefetchTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    prefetchTip:ClearLines()
    prefetchTip:SetHyperlink("item:" .. itemEntry .. ":0:0:0:0:0:0:0")
    prefetchTip:Hide()
end

local function Split(str, sep)
    local t, i = {}, 1
    while true do
        local j = str:find(sep, i, true)
        if j then t[#t+1] = str:sub(i, j-1); i = j+1
        else      t[#t+1] = str:sub(i); break end
    end
    return t
end

local storeFrame

local function RequestData()
    PS.categories    = {}
    PS.items         = {}
    PS.byCategory    = {}
    PS.receiving     = true
    PS.selectedEntry = nil
    if PA and PA.AT and PA.AT.RequestStoreAIO then
        PA.AT.RequestStoreAIO()
    else
        if not PA or (PA.prestigeLevel or 0) == 0 then
            Send("astral tree")
        end
        Send("astral store")
    end
end

function PS.ApplyStore(payload)
    if type(payload) ~= "table" then return end

    -- A purchase re-requests the whole store; remember where the player was so
    -- the refresh doesn't bounce them back to the first category.
    local prevCategory = PS.activeCategory
    local prevFilter   = PS.activeFilter
    local prevSelected = PS.selectedEntry and PS.selectedEntry.id
    local prevOffset   = (storeFrame and storeFrame.scroll)
                         and FauxScrollFrame_GetOffset(storeFrame.scroll) or 0

    PS.tokens     = tonumber(payload.tokens) or 0
    PS.categories = {}
    PS.items      = {}
    PS.byCategory = {}
    PS.receiving  = false
    PS.selectedEntry = nil
    PS.itemMeta = (type(payload.itemMeta) == "table") and payload.itemMeta or {}
    PS.lastPayload   = payload     -- /storedebug (Collections.lua)
    PS.skipped       = 0
    PS.skippedSample = nil

    if PA then
        PA.prestigeLevel = tonumber(payload.prestigeLevel) or PA.prestigeLevel or 0
    end

    for _, cat in ipairs(payload.categories or {}) do
        PS.categories[#PS.categories + 1] = cat
        PS.byCategory[cat] = {}
    end
    local prefetchIds = {}
    for _, e in ipairs(payload.entries or {}) do
        local entry = {
            id       = e.id,
            cat      = e.category,
            item     = e.item,
            cost     = e.cost     or 0,
            order    = e.order    or 0,
            reqLevel = e.reqLevel or 0,
            owned    = e.owned and true or false,
            raw      = e,     -- any extra fields (e.g. a creature id for the mount viewer)
        }
        if entry.id and entry.item then
            PS.items[entry.id] = entry
            -- an entry whose category wasn't in payload.categories used to vanish
            local cat = entry.cat or "Other"
            entry.cat = cat
            if not PS.byCategory[cat] then
                PS.categories[#PS.categories + 1] = cat
                PS.byCategory[cat] = {}
            end
            local list = PS.byCategory[cat]
            list[#list + 1] = entry
            prefetchIds[#prefetchIds + 1] = entry.item
        else
            PS.skipped = PS.skipped + 1
            PS.skippedSample = PS.skippedSample or e
        end
    end
    if PA and PA.ItemCache and PA.ItemCache.RegisterMany then
        PA.ItemCache.RegisterMany(prefetchIds)
    else
        for _, e in ipairs(prefetchIds) do PrefetchItem(e) end
    end
    for _, list in pairs(PS.byCategory) do
        table.sort(list, function(a, b) return a.order < b.order end)
    end

    if storeFrame then
        if storeFrame.tokenText then
            storeFrame.tokenText:SetText("Tokens: " .. PS.tokens)
        end
        PS.RebuildTabs()
        if #PS.categories > 0 then
            if prevCategory and PS.byCategory[prevCategory] then
                PS.RestoreView(prevCategory, prevFilter, prevOffset, prevSelected)
            else
                PS.ShowCategory(PS.categories[1])
            end
        else
            PS.RefreshList()
        end
    end
end

PA.PrestigeStore = PS

local STORE_W  = 568
local TAB_H    = 32
local ROW_H    = 58
local ICON_SZ  = 46
local NUM_ROWS = 32

local function StoreContentWidth(frame)
    return math.max(1, (frame and frame:GetWidth() or STORE_W) - 22)
end

local rows = {}

local function IsMountCategory(cat)
    local c = type(cat) == "string" and cat:lower() or ""
    return c:find("mount", 1, true) ~= nil or c:find("reittier", 1, true) ~= nil
end

-- full-screen 3D view of a store mount (MountViewer.lua)
local function ViewStoreMount(entry)
    if not (entry and PA.MountViewer) then return end
    local meta = PS.itemMeta and PS.itemMeta[entry.item]
    PA.MountViewer.Show({
        item = entry.item,
        name = GetItemInfo(entry.item) or (meta and meta.name),
        raw  = entry.raw,
        meta = meta,
    })
end

local function CreateRow(parent, idx)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -((idx - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -22, -((idx - 1) * ROW_H))
    row:RegisterForClicks("LeftButtonUp")
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if idx % 2 == 0 then
        bg:SetTexture(0.05, 0.05, 0.10, 0.65)
    else
        bg:SetTexture(0.08, 0.08, 0.16, 0.65)
    end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    hl:SetAllPoints()
    hl:SetBlendMode("ADD")
    hl:SetVertexColor(0.35, 0.35, 0.35)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon = icon

    local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameStr:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    nameStr:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 6, -2)
    nameStr:SetPoint("RIGHT",    row,  "RIGHT",   -88, 0)
    nameStr:SetJustifyH("LEFT")
    nameStr:SetText("...")
    row.nameStr = nameStr

    local costStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    costStr:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    costStr:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    costStr:SetJustifyH("RIGHT")
    costStr:SetTextColor(1, 0.82, 0)
    costStr:SetText("--")
    row.costStr = costStr

    -- mounts only (shown by PopulateRow)
    local UI = PA.UI
    local view = CreateFrame("Button", nil, row)
    view:SetSize(46, 20)
    view:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
    view:SetFrameLevel(row:GetFrameLevel() + 3)
    local vbg = view:CreateTexture(nil, "BACKGROUND")
    vbg:SetTexture("Interface\\Buttons\\WHITE8X8")
    vbg:SetAllPoints()
    vbg:SetVertexColor(0, 0, 0, 0.85)
    local vlines = UI.Outline(view, view, "BORDER", UI.Nav.edgeMid, 1)
    local vtext = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    vtext:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    vtext:SetPoint("CENTER", view, "CENTER", 0, 0)
    vtext:SetText("View")
    view:SetScript("OnEnter", function(self)
        for _, l in ipairs(vlines) do l:SetVertexColor(unpack(UI.Nav.hot)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("View this mount in 3D")
        GameTooltip:Show()
    end)
    view:SetScript("OnLeave", function()
        for _, l in ipairs(vlines) do l:SetVertexColor(unpack(UI.Nav.edgeMid)) end
        GameTooltip:Hide()
    end)
    view:SetScript("OnClick", function() ViewStoreMount(row.entry) end)
    view:Hide()
    row.viewBtn = view

    row:SetScript("OnEnter", function(self)
        if self.itemEntry then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(
                "item:" .. self.itemEntry .. ":0:0:0:0:0:0:0")
            if self.entry and IsMountCategory(self.entry.cat) then
                GameTooltip:AddLine("Ctrl-click to view in 3D", 0.6, 0.8, 1.0)
            end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    row:SetScript("OnClick", function(self)
        if not self.entry then return end
        if IsModifiedClick("CHATLINK") then   -- Shift-click links the item
            local _, link = GetItemInfo(self.entry.item)
            if link and PA.InsertChatLink then PA.InsertChatLink(link) end
            return
        end
        if IsControlKeyDown() and IsMountCategory(self.entry.cat) then
            ViewStoreMount(self.entry)
            return
        end
        PS.selectedEntry = self.entry
        if not storeFrame then return end
        local e         = self.entry
        local cost      = e.cost
        local myLevel   = PA and PA.prestigeLevel or 0
        local lockedByLevel = e.reqLevel > 0 and myLevel < e.reqLevel
        local ownedText = e.owned and "  |cff888888(already owned)|r" or ""
        local reqText   = (e.reqLevel > 0)
            and ("  |cff888888(requires Prestige " .. e.reqLevel .. ")|r")
            or ""
        storeFrame.statusText:SetText(
            "|cffffcc00" .. self.nameStr:GetText() .. "|r  \226\128\147  " ..
            cost .. " Token" .. (cost == 1 and "" or "s") ..
            reqText .. ownedText)
        if e.owned or lockedByLevel then
            storeFrame.buyBtn:SetDisabledLook(true)
        else
            storeFrame.buyBtn:Enable()
            storeFrame.buyBtn:SetDisabledLook(false)
        end
    end)

    return row
end

local STORE_QUALITY_COLOR = {
    [0] = "|cff9d9d9d", [1] = "|cffffffff", [2] = "|cff1eff00",
    [3] = "|cff0070dd", [4] = "|cffa335ee", [5] = "|cffff8000",
    [6] = "|cffe6cc80", [7] = "|cffe6cc80",
}

local function PopulateRow(row, entry)
    row.entry     = entry
    row.itemEntry = entry and entry.item
    if entry and IsMountCategory(entry.cat) then row.viewBtn:Show() else row.viewBtn:Hide() end

    if entry then
        local name, _, _, _, _, _, _, _, _, iconPath =
            GetItemInfo(entry.item)
        if not name then
            PrefetchItem(entry.item)
        end
        local meta = PS.itemMeta and PS.itemMeta[entry.item] or nil
        local displayName = name
                         or (meta and meta.name ~= "" and meta.name)
                         or ("Item #" .. entry.item)
        if not name and meta and meta.quality
           and STORE_QUALITY_COLOR[meta.quality] then
            displayName = STORE_QUALITY_COLOR[meta.quality]
                       .. displayName .. "|r"
        end
        row.icon:SetTexture(
            iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.nameStr:SetText(displayName)
        local myLevel      = PA and PA.prestigeLevel or 0
        local ownedGate    = entry.owned
        local levelGate    = entry.reqLevel > 0 and myLevel < entry.reqLevel
        if ownedGate then
            row.costStr:SetText("|cff888888Owned|r")
        elseif levelGate then
            row.costStr:SetText(
                "|cffff8888Prestige " .. entry.reqLevel .. "|r")
        else
            row.costStr:SetText(
                entry.cost .. " Token" .. (entry.cost == 1 and "" or "s"))
        end
        row:Show()
    else
        row:Hide()
    end
end

local tabs = {}      -- the category tabs in use
local tabPool = {}   -- every tab button made so far; reused, since every store refresh
                     -- (opening the tab, each purchase) used to create a new set

function PS.RebuildTabs()
    if not storeFrame then return end
    for _, t in ipairs(tabPool) do t:Hide() end
    tabs = {}

    local n = #PS.categories
    if n == 0 then return end
    local contentW = StoreContentWidth(storeFrame)
    local tabW = math.max(72, math.min(160, math.floor((contentW - 4 * (n - 1)) / n)))

    for i, cat in ipairs(PS.categories) do
        local t = tabPool[i]
        if not t then
            t = CreateFrame("Button", nil, storeFrame.tabRow,
                            "UIPanelButtonTemplate")
            PA.UI.CosmicButton(t)
            t:SetScript("OnClick", function(self)
                PS.ShowCategory(self.cat)
            end)
            tabPool[i] = t
        end
        t.cat = cat
        t:SetSize(tabW, TAB_H)
        t:ClearAllPoints()
        t:SetPoint("LEFT", storeFrame.tabRow, "LEFT",
                   (i - 1) * (tabW + 4), 0)
        t:SetText(cat)
        if t:GetFontString() then t:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 13, "") end
        if cat == PS.activeCategory then t:LockHighlight() else t:UnlockHighlight() end
        t:Show()
        tabs[#tabs + 1] = t
    end
end

function PS.ShowCategory(cat)
    PS.activeCategory = cat
    PS.activeFilter   = nil
    PS.selectedEntry  = nil
    if storeFrame then
        -- back to the top: offset and scroll bar together (only the offset was reset,
        -- so the bar stayed where the previous category left it)
        FauxScrollFrame_SetOffset(storeFrame.scroll, 0)
        local bar = _G[(storeFrame.scroll:GetName() or "") .. "ScrollBar"]
        if bar then bar:SetValue(0) end
        storeFrame.buyBtn:SetDisabledLook(true)   -- Disable() alone left it looking clickable
        storeFrame.statusText:SetText("")
        for _, t in ipairs(tabs) do
            if t:GetText() == cat then
                t:LockHighlight()
            else
                t:UnlockHighlight()
            end
        end

        if storeFrame.filterRow then
            if FILTERABLE_CATEGORIES[cat] then
                storeFrame.filterRow:Show()
                for _, fb in ipairs(storeFrame.filterBtns) do fb:UnlockHighlight() end
                if storeFrame.filterBtnsByKey.all then
                    storeFrame.filterBtnsByKey.all:LockHighlight()
                end
                PS.activeFilter = "all"
                storeFrame.scroll:ClearAllPoints()
                storeFrame.scroll:SetPoint("TOPLEFT", storeFrame, "TOPLEFT",
                    0, -(TAB_H + 12 + storeFrame.FILTER_BAND))
                storeFrame.scroll:SetPoint("BOTTOMRIGHT", storeFrame, "BOTTOMRIGHT", -22, 14)
                storeFrame.rowFrame:ClearAllPoints()
                storeFrame.rowFrame:SetPoint("TOPLEFT", storeFrame, "TOPLEFT",
                    0, -(TAB_H + 12 + storeFrame.FILTER_BAND))
                storeFrame.rowFrame:SetPoint("BOTTOMRIGHT", storeFrame, "BOTTOMRIGHT", -22, 14)
            else
                storeFrame.filterRow:Hide()
                storeFrame.scroll:ClearAllPoints()
                storeFrame.scroll:SetPoint("TOPLEFT", storeFrame, "TOPLEFT",
                    0, -(TAB_H + 12))
                storeFrame.scroll:SetPoint("BOTTOMRIGHT", storeFrame, "BOTTOMRIGHT", -22, 14)
                storeFrame.rowFrame:ClearAllPoints()
                storeFrame.rowFrame:SetPoint("TOPLEFT", storeFrame, "TOPLEFT",
                    0, -(TAB_H + 12))
                storeFrame.rowFrame:SetPoint("BOTTOMRIGHT", storeFrame, "BOTTOMRIGHT", -22, 14)
            end
        end
    end
    PS.RefreshList()
end

function PS.RefreshList()
    if not storeFrame then return end
    local raw = PS.byCategory[PS.activeCategory] or {}
    local list
    if PS.activeFilter and PS.activeFilter ~= "all" then
        list = {}
        for _, e in ipairs(raw) do
            if MatchesFilter(e, PS.activeFilter) then
                list[#list + 1] = e
            end
        end
    else
        list = raw
    end

    local visibleN = math.floor(storeFrame.scroll:GetHeight() / ROW_H)
    if visibleN < 1 then visibleN = 1 end

    local offset = FauxScrollFrame_GetOffset(storeFrame.scroll)
    for i = 1, NUM_ROWS do
        if i <= visibleN then
            PopulateRow(rows[i], list[i + offset])
        else
            rows[i]:Hide()
        end
    end
    FauxScrollFrame_Update(storeFrame.scroll, #list, visibleN, ROW_H)
end

-- Re-open a category exactly as it was (filter, scroll position, selected row) so
-- buying the same item again after the post-purchase refresh is a single click.
function PS.RestoreView(cat, filter, offset, selectedId)
    PS.ShowCategory(cat)
    if not storeFrame then return end

    if filter and filter ~= "all" and FILTERABLE_CATEGORIES[cat]
       and storeFrame.filterBtnsByKey and storeFrame.filterBtnsByKey[filter] then
        PS.activeFilter = filter
        for _, fb in ipairs(storeFrame.filterBtns) do fb:UnlockHighlight() end
        storeFrame.filterBtnsByKey[filter]:LockHighlight()
    end

    -- clamp in case the list got shorter (e.g. a one-time item is now owned)
    local count = 0
    for _, e in ipairs(PS.byCategory[cat] or {}) do
        if MatchesFilter(e, PS.activeFilter) then count = count + 1 end
    end
    local visibleN = math.max(1, math.floor(storeFrame.scroll:GetHeight() / ROW_H))
    offset = math.max(0, math.min(offset or 0, count - visibleN))

    FauxScrollFrame_SetOffset(storeFrame.scroll, offset)
    PS.RefreshList()   -- sets the scroll bar's range before its value is restored
    local barName = storeFrame.scroll:GetName()
    local bar = barName and _G[barName .. "ScrollBar"]
    if bar then bar:SetValue(offset * ROW_H) end

    if selectedId then
        for i = 1, NUM_ROWS do
            local row = rows[i]
            if row and row:IsShown() and row.entry and row.entry.id == selectedId then
                row:GetScript("OnClick")(row)   -- same status text + Buy state as a click
                break
            end
        end
    end
end

local function BuildStoreTab(panel)
    local UI = ProjectAstral.UI
    local f = panel
    _G["PAPrestigeStoreFrame"] = f

    local tabRow = CreateFrame("Frame", nil, f)
    tabRow:SetHeight(TAB_H)
    tabRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tabRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, 0)
    f.tabRow = tabRow

    local sepTop = UI.SolidFill(f, UI.Nav.edge, "OVERLAY")
    sepTop:SetHeight(1)
    sepTop:SetPoint("TOPLEFT",  f, "TOPLEFT",   0, -(TAB_H + 6))
    sepTop:SetPoint("TOPRIGHT", f, "TOPRIGHT",  0, -(TAB_H + 6))
    sepTop:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                          UI.Color.accentSoft[3], 0.55)

    local FILTER_H    = 30
    local FILTER_BAND = FILTER_H + 6

    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:SetHeight(FILTER_H)
    filterRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(TAB_H + 10))
    filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -(TAB_H + 10))
    filterRow:Hide()
    f.filterRow = filterRow
    f.FILTER_BAND = FILTER_BAND

    local FILTER_DEFS = {
        { key = "all",     label = "All"     },
        { key = "cloth",   label = "Cloth"   },
        { key = "leather", label = "Leather" },
        { key = "mail",    label = "Mail"    },
        { key = "plate",   label = "Plate"   },
        { key = "weapons", label = "Weapons" },
        { key = "misc",    label = "Misc"    },
    }
    local fbtnW = math.floor((StoreContentWidth(f) - 4 * (#FILTER_DEFS - 1)) / #FILTER_DEFS)
    f.filterBtns      = {}
    f.filterBtnsByKey = {}
    for i, d in ipairs(FILTER_DEFS) do
        local b = CreateFrame("Button", nil, filterRow, "UIPanelButtonTemplate")
        PA.UI.CosmicButton(b)
        b:SetSize(fbtnW, FILTER_H)
        b:SetPoint("LEFT", filterRow, "LEFT", (i - 1) * (fbtnW + 4), 0)
        b:SetText(d.label)
        if b:GetFontString() then b:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
        local key = d.key
        b:SetScript("OnClick", function()
            PS.activeFilter = key
            for _, fb in ipairs(f.filterBtns) do fb:UnlockHighlight() end
            b:LockHighlight()
            if f.scroll then
                FauxScrollFrame_SetOffset(f.scroll, 0)
                local bar = _G[(f.scroll:GetName() or "") .. "ScrollBar"]
                if bar then bar:SetValue(0) end
            end
            PS.RefreshList()
        end)
        f.filterBtns[#f.filterBtns + 1] = b
        f.filterBtnsByKey[key] = b
    end

    local scroll = CreateFrame("ScrollFrame", "PAStoreScrollFrame", f,
                               "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(TAB_H + 12))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 14)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, PS.RefreshList)
    end)
    f.scroll = scroll

    local rowFrame = CreateFrame("Frame", nil, f)
    rowFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(TAB_H + 12))
    rowFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 14)
    f.rowFrame = rowFrame

    for i = 1, NUM_ROWS do
        rows[i] = CreateRow(rowFrame, i)
    end

    local sepBot = UI.SolidFill(f, UI.Nav.edge, "OVERLAY")
    sepBot:SetHeight(1)
    sepBot:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 42)
    sepBot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 42)
    sepBot:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                          UI.Color.accentSoft[3], 0.55)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    statusText:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  2, 14)
    statusText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -184, 14)
    statusText:SetJustifyH("LEFT")
    statusText:SetText("")
    statusText:SetTextColor(unpack(UI.Color.textPrimary))
    f.statusText = statusText

    local buyBtn = UI.MakeButton(f, "Purchase Item", {
        w = 170, h = 34,
        variant = "gold",
        onClick = function()
            if PS.selectedEntry and PA.AT and PA.AT.SendBuyEntryAIO then
                PA.AT.SendBuyEntryAIO(PS.selectedEntry.id)
            end
        end,
    })
    buyBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    buyBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 8)
    buyBtn:SetDisabledLook(true)
    f.buyBtn = buyBtn

    f.tokenText = setmetatable({}, { __index = function() return function() end end })

    f:SetScript("OnShow", function()
        PS.selectedEntry = nil
        f.buyBtn:SetDisabledLook(true)
        f.statusText:SetText("")
        RequestData()
        Send("astral tree")
        PS.RebuildTabs()
        if #PS.categories > 0 then
            PS.ShowCategory(PS.categories[1])
        end
    end)

    storeFrame = f
    local function LayoutStoreControls()
        local width = StoreContentWidth(f)
        tabRow:SetWidth(width)
        filterRow:SetWidth(width)
        local buttonW = math.floor((width - 4 * (#f.filterBtns - 1)) / #f.filterBtns)
        for i, button in ipairs(f.filterBtns) do
            button:SetWidth(buttonW)
            button:ClearAllPoints()
            button:SetPoint("LEFT", filterRow, "LEFT", (i - 1) * (buttonW + 4), 0)
        end
        PS.RebuildTabs()
        PS.RefreshList()
    end
    f:HookScript("OnSizeChanged", function()
        if storeFrame == f then LayoutStoreControls() end
    end)
    LayoutStoreControls()
end

local function OnItemInfoReceived()
    if storeFrame and storeFrame:IsShown() then
        PS.RefreshList()
    end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
evt:SetScript("OnEvent", function(_, event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" then
        OnItemInfoReceived()
    end
end)

if PA and PA.OnTokensChanged then
    PA:OnTokensChanged(function(tokens, _)
        PS.tokens = tokens or 0
        if storeFrame and storeFrame.tokenText then
            storeFrame.tokenText:SetText("Tokens: " .. PS.tokens)
        end
    end)
end

local function ToggleStoreFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "prestige_store" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("prestige_store")
        if mf._tabBar then mf._tabBar:SelectTab("prestige_store") end
    end
end

ProjectAstral:RegisterModule("prestige_store", "Token Store", ToggleStoreFrame, {
    subtitle = "Spend Tokens on cosmetic, utility, and gameplay rewards.",
})
ProjectAstral:RegisterTabContent("prestige_store", BuildStoreTab)
