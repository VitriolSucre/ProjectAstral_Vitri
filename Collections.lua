
local AIO = AIO or (require and require("AIO"))
if AIO and AIO.AddAddon and AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local C = {}
PA.collections = C

C.entries      = {}
C.activeTab    = "mount"
C.activeFilter = "all"
C.receiving    = false

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
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

local prefetchTip
local function PrefetchItem(itemEntry)
    if not itemEntry or itemEntry == 0 then return end
    if GetItemInfo(itemEntry) then return end
    if not prefetchTip then
        prefetchTip = CreateFrame("GameTooltip", "CLPrefetchTooltip",
                                  UIParent, "GameTooltipTemplate")
        prefetchTip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    prefetchTip:ClearLines()
    prefetchTip:SetHyperlink("item:" .. itemEntry .. ":0:0:0:0:0:0:0")
    prefetchTip:Hide()
end

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
local WEAPON_TYPE_NAMES = { ["Weapon"] = true, ["Waffe"] = true }
local ARMOR_TYPE_NAMES  = { ["Armor"]  = true, ["Rüstung"] = true }
local MISC_EQUIP_LOCS = {
    ["INVTYPE_FINGER"]   = true,
    ["INVTYPE_TRINKET"]  = true,
    ["INVTYPE_NECK"]     = true,
    ["INVTYPE_HOLDABLE"] = true,
    ["INVTYPE_CLOAK"]    = true,
}

local itemClassCache = {}
local function ItemFilterClass(itemId)
    if not itemId or itemId == 0 then return nil end
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
    end
    itemClassCache[itemId] = cls
    return cls
end

local function MatchesHeirloomFilter(itemEntry, filter)
    if not filter or filter == "all" then return true end
    local cls = ItemFilterClass(itemEntry)
    if cls == nil then return true end
    return cls == filter
end

local frame

-- The server sometimes never answers (handler missing or the request sent too early).
-- Without a timeout the loading overlay covered the card forever and, with
-- `receiving` stuck, reopening the tab never asked again.
local LOAD_TIMEOUT = 8
local timeout = CreateFrame("Frame")
timeout:Hide()
timeout:SetScript("OnUpdate", function(self)
    if not C.receiving then self:Hide(); return end
    if GetTime() - (C.requestedAt or 0) >= LOAD_TIMEOUT then
        self:Hide()
        C.receiving = false
        C.failed    = true
        if frame and frame.loadingOverlay then frame.loadingOverlay:Hide() end
        if C.Refresh then C.Refresh() end
    end
end)

local function RequestData()
    C.entries     = {}
    C.receiving   = true
    C.failed      = false
    C.requestedAt = GetTime()
    timeout:Show()
    if frame and frame.loadingOverlay then frame.loadingOverlay:Show() end
    if AIO and AIO.Handle then
        AIO.Handle("CollectionsServer", "RequestList")
    else
        Send("collections list")
    end
end

if AIO and AIO.AddHandlers then
    local ClientHandler = AIO.AddHandlers("Collections", {})

    ClientHandler.List = function(_, store, alpha, itemMeta)
        if frame and frame.loadingOverlay then frame.loadingOverlay:Hide() end
        C.entries  = {}
        C.itemMeta = (type(itemMeta) == "table") and itemMeta or {}
        for _, e in ipairs(store or {}) do
            C.entries[#C.entries + 1] = {
                kind      = "store",
                storeId   = e.storeId,
                itemEntry = e.itemEntry,
                category  = e.category,
                raw       = e,          -- any extra fields (e.g. a creature id for the mount viewer)
            }
            if e.itemEntry then PrefetchItem(e.itemEntry) end
        end
        for _, a in ipairs(alpha or {}) do
            C.entries[#C.entries + 1] = {
                kind     = "alpha",
                akind    = a.kind,
                rewardId = a.rewardId,
                label    = a.label or "",
            }
            if a.kind == "ITEM" and a.rewardId then PrefetchItem(a.rewardId) end
        end
        C.receiving = false
        if frame and frame:IsShown() and C.Refresh then C.Refresh() end
    end

    local CLAIM_FAIL_MSG = {
        NOT_OWNED       = "You don't own this entry.",
        NOT_FOUND       = "Entry not found or disabled.",
        ALREADY_LEARNED = "Already in your spellbook.",
    }

    ClientHandler.ClaimResult = function(_, status, storeEntryId)
        if status == "OK" then
            SendChatMessage(".collections claim " .. tostring(storeEntryId), "SAY")
            UIErrorsFrame:AddMessage("Collection: claimed.", 0.55, 1.0, 0.55, 1.0)
            if frame and frame:IsShown() then RequestData() end
        else
            UIErrorsFrame:AddMessage(
                "Collection: " .. (CLAIM_FAIL_MSG[status] or ("Claim failed: " .. tostring(status))),
                1.0, 0.42, 0.42, 1.0)
        end
    end

    ClientHandler.ClaimAlphaResult = function(_, status, kind, rewardId)
        if status == "OK" then
            SendChatMessage(string.format(".collections claim_alpha %s %d",
                                           tostring(kind), tonumber(rewardId) or 0), "SAY")
            UIErrorsFrame:AddMessage("Collection: alpha reward claimed.",
                0.55, 1.0, 0.55, 1.0)
            if frame and frame:IsShown() then RequestData() end
        else
            UIErrorsFrame:AddMessage(
                "Collection: " .. (CLAIM_FAIL_MSG[status] or ("Claim failed: " .. tostring(status))),
                1.0, 0.42, 0.42, 1.0)
        end
    end
end

local STORE_W = 568
local TAB_H   = 32
local FILTER_H = 30
local MIN_CARD_W = 220
local CARD_H  = 78
local ICON_SZ = 58
local GAP_X   = 12
local GAP_Y   = 10

local cardPool = {}
local gridOffset = 0   -- first card row shown (mouse wheel)

local function CollectionGridMetrics(width)
    local innerW = math.max(1, (width or STORE_W) - 8)
    local cols = math.max(1, math.floor((innerW + GAP_X) / (MIN_CARD_W + GAP_X)))
    local cardW = math.floor((innerW - GAP_X * (cols - 1)) / cols)
    return cols, cardW
end

local function CreateCard(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(MIN_CARD_W, CARD_H)
    UI.AstralBackdrop(b, { thin = true,
                           bg = UI.Nav.panel,
                           border = UI.Nav.edge })

    local iconHolder = CreateFrame("Frame", nil, b)
    iconHolder:SetSize(ICON_SZ, ICON_SZ)
    iconHolder:SetPoint("LEFT", b, "LEFT", 5, 0)
    iconHolder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    PA.UI.CosmicCorners(iconHolder)
    iconHolder:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 1.0))

    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT",     iconHolder, "TOPLEFT",      3, -3)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -3,  3)
    b.iconHolder = iconHolder
    b.icon = icon

    local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    name:SetPoint("TOPLEFT",  iconHolder, "TOPRIGHT", 7, -3)
    name:SetPoint("TOPRIGHT", b, "TOPRIGHT", -6, -3)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("TOP")
    name:SetHeight(30)
    name:SetText("…")
    name:SetTextColor(unpack(UI.Color.textTitle))
    b.name = name

    local sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    sub:SetPoint("BOTTOMLEFT",  iconHolder, "BOTTOMRIGHT", 8, 3)
    sub:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 3)
    sub:SetJustifyH("LEFT")
    sub:SetTextColor(unpack(UI.Nav.muted))
    sub:SetText("")
    b.sub = sub

    -- mounts only (shown by C.Refresh): full-screen 3D view, MountViewer.lua
    local view = CreateFrame("Button", nil, b)
    view:SetSize(48, 22)
    view:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5)
    view:SetFrameLevel(b:GetFrameLevel() + 3)
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
    view:SetScript("OnClick", function() C.ViewMount(b.entry) end)
    view:Hide()
    b.viewBtn = view

    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.Nav.hot))
        if self.entry then
            local e = self.entry
            if e.kind == "alpha" and e.akind == "SPELL" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("spell:" .. e.rewardId)
                GameTooltip:Show()
            else
                local itemId = (e.kind == "store" and e.itemEntry) or e.rewardId
                if itemId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. itemId .. ":0:0:0:0:0:0:0")
                    if C.IsMountEntry(e) then
                        GameTooltip:AddLine("Ctrl-click to view in 3D", 0.6, 0.8, 1.0)
                    end
                    GameTooltip:Show()
                end
            end
        end
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(UI.Nav.edge[1], UI.Nav.edge[2],
                                     UI.Nav.edge[3], UI.Nav.edge[4] or 1)
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        -- Shift-click links the reward (it used to fall through and claim it)
        if IsModifiedClick("CHATLINK") then
            local link
            if e.kind == "alpha" and e.akind == "SPELL" then
                link = e.rewardId and GetSpellLink(e.rewardId)
            else
                local id = (e.kind == "store" and e.itemEntry) or e.rewardId
                link = id and select(2, GetItemInfo(id))
            end
            if link and PA.InsertChatLink then PA.InsertChatLink(link) end
            return
        end
        if IsControlKeyDown() and C.IsMountEntry(e) then
            C.ViewMount(e)
            return
        end
        if e.kind == "store" then
            if AIO and AIO.Handle then
                AIO.Handle("CollectionsServer", "Claim", e.storeId)
            else
                Send("collections claim " .. e.storeId)
            end
        else
            if AIO and AIO.Handle then
                AIO.Handle("CollectionsServer", "ClaimAlpha", e.akind, e.rewardId)
            else
                Send("collections claim_alpha " .. e.akind .. " " .. e.rewardId)
            end
        end
    end)

    return b
end

local function GetCard(idx)
    if not cardPool[idx] then
        cardPool[idx] = CreateCard(frame.grid)
    end
    return cardPool[idx]
end

-- the server's category names vary ("Mount", "Mounts", German client strings);
-- an exact == "Mount" match left Store Mounts empty for anything else
local function CategoryKind(cat)
    local c = type(cat) == "string" and cat:lower() or ""
    if c:find("mount", 1, true) or c:find("reittier", 1, true) then return "mount" end
    if c:find("heirloom", 1, true) or c:find("erbst", 1, true) then return "heirloom" end
    return nil
end

function C.IsMountEntry(e)
    return e ~= nil and e.kind == "store" and CategoryKind(e.category) == "mount"
end

function C.ViewMount(e)
    if not (e and PA.MountViewer) then return end
    local meta = C.itemMeta and C.itemMeta[e.itemEntry]
    PA.MountViewer.Show({
        item = e.itemEntry,
        name = GetItemInfo(e.itemEntry) or (meta and meta.name),
        raw  = e.raw,
        meta = meta,
    })
end

local EMPTY_TEXT = {
    mount    = "No Token Store mounts to claim yet.",
    heirloom = "No heirlooms to claim yet.",
    alpha    = "No event rewards to claim yet.",
}

function C.Refresh()
    if not (frame and frame.grid) then return end

    local list = {}
    for _, e in ipairs(C.entries) do
        local keep = false
        if C.activeTab == "mount" then
            keep = (e.kind == "store" and CategoryKind(e.category) == "mount")
        elseif C.activeTab == "heirloom" then
            keep = (e.kind == "store" and CategoryKind(e.category) == "heirloom")
                and MatchesHeirloomFilter(e.itemEntry, C.activeFilter)
        elseif C.activeTab == "alpha" then
            keep = (e.kind == "alpha")
        end
        if keep then list[#list + 1] = e end
    end

    -- Cards sit straight on the panel and the mouse wheel pages through rows. They
    -- used to live in a ScrollFrame's scroll child, and in 3.3.5 a scroll child
    -- inside the hub's own scrolling page stayed behind (drawn under the window)
    -- while the hub was dragged.
    local gridH     = frame.grid:GetHeight() or 0
    local cols, cardW = CollectionGridMetrics(frame.grid:GetWidth())
    local visRows   = (gridH > 0) and math.max(1, math.floor((gridH - 4) / (CARD_H + GAP_Y))) or 7
    local totalRows = math.ceil(#list / cols)
    local maxOffset = math.max(0, totalRows - visRows)
    if gridOffset > maxOffset then gridOffset = maxOffset end
    C.maxOffset = maxOffset

    local slot = 0
    for i = gridOffset * cols + 1, math.min(#list, (gridOffset + visRows) * cols) do
        local entry = list[i]
        slot = slot + 1
        local card = GetCard(slot)
        card.entry = entry
        card:SetSize(cardW, CARD_H)

        local itemId, spellId, nameText, iconTex, subText
        if entry.kind == "store" then
            itemId = entry.itemEntry
        elseif entry.kind == "alpha" then
            if entry.akind == "ITEM"  then itemId  = entry.rewardId end
            if entry.akind == "SPELL" then spellId = entry.rewardId end
        end

        if itemId then
            local n, _, _, _, _, _, _, _, _, tex = GetItemInfo(itemId)
            local meta = C.itemMeta and C.itemMeta[itemId] or nil
            nameText = n
                    or (meta and meta.name ~= "" and meta.name)
                    or ("Item #" .. itemId)
            if not n and meta and meta.quality then
                local COL = { [0]="|cff9d9d9d",[1]="|cffffffff",
                              [2]="|cff1eff00",[3]="|cff0070dd",
                              [4]="|cffa335ee",[5]="|cffff8000",
                              [6]="|cffe6cc80",[7]="|cffe6cc80" }
                if COL[meta.quality] then
                    nameText = COL[meta.quality] .. nameText .. "|r"
                end
            end
            iconTex  = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
        elseif spellId then
            local n, _, tex = GetSpellInfo(spellId)
            nameText = n or ("Spell #" .. spellId)
            iconTex  = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
        end

        if entry.kind == "store" then
            subText = entry.category
        else
            subText = (entry.label ~= "" and entry.label) or "Alpha Reward"
        end

        card.name:SetText(nameText or "…")
        card.icon:SetTexture(iconTex)
        card.sub:SetText(subText or "")
        if C.IsMountEntry(entry) then card.viewBtn:Show() else card.viewBtn:Hide() end

        local col = (slot - 1) % cols
        local row = math.floor((slot - 1) / cols)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", frame.grid, "TOPLEFT",
            col * (cardW + GAP_X) + 4,
            -(row * (CARD_H + GAP_Y) + 4))
        card:Show()
    end

    for i = slot + 1, #cardPool do cardPool[i]:Hide() end

    local track, thumb = frame.track, frame.thumb
    if maxOffset > 0 then
        local th = math.max(8, gridH - 8)
        local h  = math.max(18, math.floor(th * visRows / totalRows))
        track:SetHeight(th)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((th - h) * gridOffset / maxOffset))
        track:Show()
        thumb:Show()
    else
        track:Hide()
        thumb:Hide()
    end

    if frame.empty then
        local msg = ""
        if #list == 0 and not C.receiving then
            msg = C.failed
                and "Couldn't load collections from the server. Open this tab again to retry."
                or (EMPTY_TEXT[C.activeTab] or "")
        end
        frame.empty:SetText(msg)
    end
end

local TABS = {
    { id = "mount",    label = "Store Mounts" },
    { id = "heirloom", label = "Heirlooms" },
    { id = "alpha",    label = "Rewards"   },
}

local function SelectSubTab(id)
    C.activeTab    = id
    C.activeFilter = "all"
    gridOffset     = 0
    if not frame then return end
    for _, t in ipairs(frame.subTabs) do
        if t.id == id then t:LockHighlight() else t:UnlockHighlight() end
    end
    if frame.filterRow then
        if id == "heirloom" then
            frame.filterRow:Show()
            for _, fb in ipairs(frame.filterBtns) do fb:UnlockHighlight() end
            if frame.filterBtnsByKey.all then
                frame.filterBtnsByKey.all:LockHighlight()
            end
            frame.grid:ClearAllPoints()
            frame.grid:SetPoint("TOPLEFT",  frame, "TOPLEFT",   0, -(TAB_H + 6 + FILTER_H + 4))
            frame.grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 14)
        else
            frame.filterRow:Hide()
            frame.grid:ClearAllPoints()
            frame.grid:SetPoint("TOPLEFT",  frame, "TOPLEFT",   0, -(TAB_H + 12))
            frame.grid:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, 14)
        end
    end
    C.Refresh()
end

local function BuildCollectionsTab(panel)
    local f = panel
    frame = f

    if PA and PA.UI and PA.UI.MakeLoadingOverlay then
        f.loadingOverlay = PA.UI.MakeLoadingOverlay(f,
            { text = "Loading collections" .. string.char(0xE2, 0x80, 0xA6) })
    end

    local tabRow = CreateFrame("Frame", nil, f)
    tabRow:SetHeight(TAB_H)
    tabRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tabRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, 0)
    f.tabRow = tabRow

    f.subTabs = {}
    local tabW = math.max(100, math.floor((math.max(STORE_W, f:GetWidth()) - 30) / #TABS) - 4)
    for i, t in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, tabRow, "UIPanelButtonTemplate")
        PA.UI.CosmicButton(btn)
        btn:SetSize(tabW, TAB_H)
        btn:SetPoint("LEFT", tabRow, "LEFT", (i - 1) * (tabW + 4), 0)
        btn:SetText(t.label)
        if btn:GetFontString() then btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 13, "") end
        btn.id = t.id
        local id = t.id
        btn:SetScript("OnClick", function() SelectSubTab(id) end)
        f.subTabs[#f.subTabs + 1] = btn
    end

    local sepTop = UI.SolidFill(f, UI.Nav.edge, "OVERLAY")
    sepTop:SetHeight(1)
    sepTop:SetPoint("TOPLEFT",  f, "TOPLEFT",   0, -(TAB_H + 6))
    sepTop:SetPoint("TOPRIGHT", f, "TOPRIGHT",  0, -(TAB_H + 6))
    sepTop:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                           UI.Color.accentSoft[3], 0.55)

    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:SetHeight(FILTER_H)
    filterRow:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(TAB_H + 10))
    filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -22, -(TAB_H + 10))
    filterRow:Hide()
    f.filterRow = filterRow

    local FILTER_DEFS = {
        { key = "all",     label = "All"     },
        { key = "cloth",   label = "Cloth"   },
        { key = "leather", label = "Leather" },
        { key = "mail",    label = "Mail"    },
        { key = "plate",   label = "Plate"   },
        { key = "weapons", label = "Weapons" },
        { key = "misc",    label = "Misc"    },
    }
    local fbW = math.floor((math.max(STORE_W, f:GetWidth()) - 30 - 4 * (#FILTER_DEFS - 1)) / #FILTER_DEFS)
    f.filterBtns      = {}
    f.filterBtnsByKey = {}
    for i, d in ipairs(FILTER_DEFS) do
        local b = CreateFrame("Button", nil, filterRow, "UIPanelButtonTemplate")
        PA.UI.CosmicButton(b)
        b:SetSize(fbW, FILTER_H)
        b:SetPoint("LEFT", filterRow, "LEFT", (i - 1) * (fbW + 4), 0)
        b:SetText(d.label)
        if b:GetFontString() then b:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
        local key = d.key
        b:SetScript("OnClick", function()
            C.activeFilter = key
            gridOffset = 0
            for _, fb in ipairs(f.filterBtns) do fb:UnlockHighlight() end
            b:LockHighlight()
            C.Refresh()
        end)
        f.filterBtns[#f.filterBtns + 1] = b
        f.filterBtnsByKey[key] = b
    end

    -- a plain frame, not a ScrollFrame (see C.Refresh): cards move with the hub
    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT",     f, "TOPLEFT",      0, -(TAB_H + 12))
    grid:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 14)
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta)
        local o = math.max(0, math.min(C.maxOffset or 0, gridOffset - delta))
        if o ~= gridOffset then
            gridOffset = o
            C.Refresh()
        end
    end)
    grid:SetScript("OnSizeChanged", function() C.Refresh() end)
    f.grid = grid

    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetTexture("Interface\\Buttons\\WHITE8X8")
    track:SetWidth(3)
    track:SetPoint("TOPLEFT", grid, "TOPRIGHT", 10, -4)
    track:SetVertexColor(UI.Nav.edge[1], UI.Nav.edge[2], UI.Nav.edge[3], 0.8)
    track:Hide()
    f.track = track

    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetWidth(3)
    thumb:SetVertexColor(unpack(UI.Color.accentSoft))
    thumb:Hide()
    f.thumb = thumb

    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", grid, "TOPLEFT", 12, -16)
    empty:SetPoint("RIGHT",   f,      "RIGHT",  -30, 0)
    empty:SetJustifyH("LEFT")
    f.empty = empty

    SelectSubTab("mount")

    f:SetScript("OnShow", function()
        if not C.receiving then RequestData() end
    end)

    local function LayoutCollectionControls()
        local width = math.max(STORE_W, f:GetWidth() or STORE_W)
        tabRow:SetWidth(width - 22)
        filterRow:SetWidth(width - 22)
        local nextTabW = math.max(100, math.floor((width - 30) / #TABS) - 4)
        for i, button in ipairs(f.subTabs) do
            button:SetWidth(nextTabW)
            button:ClearAllPoints()
            button:SetPoint("LEFT", tabRow, "LEFT", (i - 1) * (nextTabW + 4), 0)
        end
        local nextFilterW = math.floor((width - 30 - 4 * (#f.filterBtns - 1)) / #f.filterBtns)
        for i, button in ipairs(f.filterBtns) do
            button:SetWidth(nextFilterW)
            button:ClearAllPoints()
            button:SetPoint("LEFT", filterRow, "LEFT", (i - 1) * (nextFilterW + 4), 0)
        end
        C.Refresh()
    end
    f:HookScript("OnSizeChanged", LayoutCollectionControls)
    LayoutCollectionControls()
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    return type(msg) == "string"
       and msg:sub(1, 12) == ".collections"
       and author == UnitName("player")
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if frame and frame:IsShown() then C.Refresh() end
    end
end)

local function ToggleCollectionsFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "collections" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("collections")
        if mf._tabBar then mf._tabBar:SelectTab("collections") end
    end
end

ProjectAstral:RegisterModule("collections", "Collections", ToggleCollectionsFrame, {
    subtitle = "Browse mounts, heirlooms, and special-event rewards.",
})
ProjectAstral:RegisterTabContent("collections", BuildCollectionsTab)

-- /storedebug: what the server actually sent to the Token Store and Collections, so a
-- missing category (e.g. mounts) can be told apart from a display problem
SLASH_PASTOREDEBUG1 = "/storedebug"
SlashCmdList["PASTOREDEBUG"] = function()
    local out = DEFAULT_CHAT_FRAME
    local tag = "|cff99b8ff[Project Astral]|r "
    local PS = ProjectAstral.PrestigeStore
    local p = PS and PS.lastPayload
    if not p then
        out:AddMessage(tag .. "Token Store: no data yet. Open the Store tab, wait a moment, then try again.")
    else
        out:AddMessage(tag .. string.format("Token Store: %d categories listed, %d entries sent, %d skipped (no id or item).",
            #(p.categories or {}), #(p.entries or {}), PS.skipped or 0))
        for _, cat in ipairs(PS.categories or {}) do
            out:AddMessage("   " .. tostring(cat) .. ": " .. #(PS.byCategory[cat] or {}) .. " items")
        end
        if PS.skippedSample then
            local parts = {}
            for k, v in pairs(PS.skippedSample) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
            out:AddMessage("   first skipped entry: " .. table.concat(parts, ", "))
        end
    end

    local counts, alpha = {}, 0
    for _, e in ipairs(C.entries or {}) do
        if e.kind == "store" then
            local k = tostring(e.category)
            counts[k] = (counts[k] or 0) + 1
        else
            alpha = alpha + 1
        end
    end
    local state = C.receiving and "still loading" or (C.failed and "server didn't answer" or "loaded")
    out:AddMessage(tag .. "Collections (" .. state .. "): " .. alpha .. " event rewards")
    for k, n in pairs(counts) do
        out:AddMessage("   " .. k .. ": " .. n .. " entries" .. (CategoryKind(k) and (" -> " .. CategoryKind(k)) or ""))
    end

    -- the fields the server sends for a mount (the 3D viewer needs a creature/display id
    -- for mounts this character hasn't learned yet)
    local function Fields(t)
        local parts = {}
        for k, v in pairs(t) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
        return table.concat(parts, ", ")
    end
    for _, e in ipairs(C.entries or {}) do
        if C.IsMountEntry(e) and type(e.raw) == "table" then
            out:AddMessage("   first Store Mount fields: " .. Fields(e.raw))
            break
        end
    end
    for _, cat in ipairs((PS and PS.categories) or {}) do
        local first = PS.byCategory[cat] and PS.byCategory[cat][1]
        if CategoryKind(cat) == "mount" and first and type(first.raw) == "table" then
            out:AddMessage("   first Token Store mount fields: " .. Fields(first.raw))
            break
        end
    end
end

do
    local mods = ProjectAstral.modules
    if type(mods) == "table" and #mods > 0 then
        local cIdx
        for i, m in ipairs(mods) do
            if m.name == "collections" then cIdx = i; break end
        end
        local anchorIdx
        for i, m in ipairs(mods) do
            local n = m.name
            if n == "prestigestore" or n == "store" or n == "prestige_store" then
                anchorIdx = i; break
            end
        end
        if cIdx and anchorIdx and cIdx ~= anchorIdx + 1 then
            local entry = table.remove(mods, cIdx)
            local insertAt = anchorIdx + (cIdx < anchorIdx and 0 or 1)
            table.insert(mods, insertAt, entry)
        end
    end
end
