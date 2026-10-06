-- Slot schema frozen; MUST mirror AstralGemMgr.h LOADOUT_SLOTS.

local PA = ProjectAstral
local UI = PA.UI

local AG = {}
PA.AstralGems = AG

local C_GREEN, C_BLUE, C_PURPLE, C_ORANGE = 2, 3, 4, 5

local SLOT_SCHEMA = {
    { ord = 0, equipSlot = 0,  label = "Head",   colors = { C_BLUE } },
    { ord = 1, equipSlot = 1,  label = "Neck",   colors = { C_PURPLE } },
    { ord = 2, equipSlot = 4,  label = "Chest",  colors = { C_GREEN, C_BLUE, C_PURPLE } },
    { ord = 3, equipSlot = 6,  label = "Legs",   colors = { C_GREEN, C_BLUE, C_PURPLE } },
    { ord = 4, equipSlot = 7,  label = "Boots",  colors = { C_GREEN } },
    { ord = 5, equipSlot = 15, label = "Weapon", colors = { C_GREEN, C_BLUE, C_PURPLE, C_ORANGE } },
}

local COLOR_RGB = {
    [C_GREEN]  = { 0.30, 1.00, 0.30 },
    [C_BLUE]   = { 0.20, 0.60, 1.00 },
    [C_PURPLE] = UI.Tinted({ 0.75, 0.35, 1.00 }),
    [C_ORANGE] = { 1.00, 0.60, 0.20 },
}

local COLOR_NAME = {
    [C_GREEN]  = "Uncommon",
    [C_BLUE]   = "Rare",
    [C_PURPLE] = "Epic",
    [C_ORANGE] = "Legendary",
}

local COLOR_SLOT_TEX = {
    [C_GREEN]  = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_green",
    [C_BLUE]   = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_blue",
    [C_PURPLE] = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_purple",
    [C_ORANGE] = "Interface\\AddOns\\ProjectAstral\\assets\\gemslots\\slot_legendary",
}
local SLOT_LOCK_TEX     = "Interface\\Buttons\\WHITE8X8"
local SLOT_CHROME_EXTRA = 10
local SLOT_LOCK_INSET   = -2

local function GetGemTexture(itemId)
    if not itemId or itemId <= 0 then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    if PA.ItemCache and PA.ItemCache.Register then PA.ItemCache.Register(itemId) end
    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemId)
    if texture and texture ~= "" then return texture end
    if GetItemIcon then
        local icon = GetItemIcon(itemId)
        if icon and icon ~= "" then return icon end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ApplySocketGemIcon(icon, itemId)
    if not icon then return end

    local texture = GetGemTexture(itemId)
    if texture and texture ~= "" and texture ~= "Interface\\Buttons\\WHITE8X8" and texture ~= "Interface\\Icons\\INV_Misc_QuestionMark" then
        icon:SetTexture(texture)
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetAlpha(1)
        icon:SetDrawLayer("ARTWORK", 7)
        icon:Show()
        return
    end

    icon:SetTexture(nil)
    icon:SetAlpha(0)
    icon:Hide()
end

local function CreateModernLockGlyph(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    holder:SetPoint("CENTER", parent, "CENTER", 0, 0)
    holder:SetFrameLevel(parent:GetFrameLevel() + 30)

    local mark = holder:CreateFontString(nil, "OVERLAY")
    mark:SetFont("Fonts\\FRIZQT__.TTF", size * 0.75, "OUTLINE")
    mark:SetPoint("CENTER", holder, "CENTER", 0, 0)
    mark:SetText("X")
    mark:SetTextColor(0.25, 0.65, 1.00, 1)
    mark:SetJustifyH("CENTER")
    mark:SetJustifyV("MIDDLE")

    return holder
end

AG.loadout    = {}
AG.inspect    = {}
AG.inspecting = nil

local function Send(cmd) SendChatMessage("." .. cmd, "SAY") end

local function Split(s, sep)
    local t, i = {}, 1
    while true do
        local j = s:find(sep, i, true)
        if j then t[#t + 1] = s:sub(i, j - 1); i = j + 1
        else      t[#t + 1] = s:sub(i); break end
    end
    return t
end

local function ClearTable(t) for k in pairs(t) do t[k] = nil end end

local function PutSocket(tbl, ord, idx, gemId, active)
    if not tbl[ord] then tbl[ord] = {} end
    tbl[ord][idx] = { gemId = gemId, active = active }
    if gemId and gemId > 0 and PA.ItemCache then
        PA.ItemCache.Register(gemId)
    end
end

local LOADOUT_SLOT_OK_ERR_MSG = {
    BAD_SLOT   = "That slot has no sockets.",
    IN_COMBAT  = "You cannot change your gem loadout while in combat.",
    USAGE      = "Command syntax error.",
}

local function RegisterAstralGemsHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralGemsClient", {})

    ClientHandler.Loadout = function(_, payload)
        if type(payload) ~= "table" then return end
        ClearTable(AG.loadout)
        for _, slot in ipairs(payload.slots or {}) do
            local ord = tonumber(slot.ord)
            for _, sock in ipairs(slot.sockets or {}) do
                if ord and sock.idx then
                    PutSocket(AG.loadout, ord, sock.idx,
                              tonumber(sock.gem) or 0,
                              sock.active and true or false)
                end
            end
        end
        AG.inspecting = nil
        AG.Render()
        if AG.OnApplyLoadoutRefreshed then AG.OnApplyLoadoutRefreshed() end
    end

    ClientHandler.InspectResult = function(_, status, targetOrName, slots)
        if status == "OK" then
            AG.inspecting = targetOrName
            ClearTable(AG.inspect)
            for _, slot in ipairs(slots or {}) do
                local ord = tonumber(slot.ord)
                for _, sock in ipairs(slot.sockets or {}) do
                    if ord and sock.idx then
                        PutSocket(AG.inspect, ord, sock.idx,
                                  tonumber(sock.gem) or 0,
                                  sock.active and true or false)
                    end
                end
            end
            AG.Render()
        elseif status == "OFFLINE" then
            UIErrorsFrame:AddMessage((targetOrName or "Player") ..
                " is not online.", 1, 0.5, 0.5, 53, 5)
        else
            UIErrorsFrame:AddMessage("Inspect failed: " .. tostring(status),
                1, 0.5, 0.5, 53, 5)
        end
    end

    local function ForwardSocketOp(op, status, equipSlot, socketIdx, gemEntry)
        if status == "OK" then
            -- while a whole loadout is applied, skip the per-gem screen message
            -- (the Gem Builds bar shows the progress)
            local batch = AG.IsApplyingLoadout and AG.IsApplyingLoadout()
            if op == "socket" then
                SendChatMessage(string.format(".gem socket %d %d %d",
                                              equipSlot, socketIdx, gemEntry or 0), "SAY")
                if not batch then UIErrorsFrame:AddMessage("Loadout SOCKET", 0.6, 1.0, 0.6, 53, 4) end
            else
                SendChatMessage(string.format(".gem unsocket %d %d",
                                              equipSlot, socketIdx), "SAY")
                if not batch then UIErrorsFrame:AddMessage("Loadout UNSOCKET", 0.6, 1.0, 0.6, 53, 4) end
            end
            -- re-read the real state from the server after every change
            if AIO and AIO.Handle then
                AIO.Handle("AstralgemServer", "RequestLoadout")
            end
        else
            local m = LOADOUT_SLOT_OK_ERR_MSG[status] or ("Loadout error: " .. tostring(status))
            UIErrorsFrame:AddMessage(m, 1, 0.4, 0.4, 53, 5)
        end
    end

    ClientHandler.SocketResult = function(_, status, equipSlot, socketIdx)
        ForwardSocketOp("socket", status, equipSlot, socketIdx,
                        AG._pendingGemEntry)
        AG._pendingGemEntry = nil
        if AG.OnApplySocketResult then AG.OnApplySocketResult(status) end
    end

    ClientHandler.UnsocketResult = function(_, status, equipSlot, socketIdx)
        ForwardSocketOp("unsocket", status, equipSlot, socketIdx)
        if AG.OnApplyUnsocketResult then AG.OnApplyUnsocketResult(status) end
    end
    return true
end

local aioInit = CreateFrame("Frame")
aioInit:RegisterEvent("PLAYER_LOGIN")
aioInit:SetScript("OnEvent", function(self)
    if RegisterAstralGemsHandlers() then
        self:UnregisterAllEvents()
        if _G.AIO and _G.AIO.Handle then
            _G.AIO.Handle("AstralgemServer", "RequestLoadout")
        end
    end
end)

local PICKER_TIER_FILTERS = {
    { label = "All Tiers", match = function(c) return true end },
    { label = "T1",     match = function(c) return not c.isMythic and c.tier == 1 end },
    { label = "T2",     match = function(c) return not c.isMythic and c.tier == 2 end },
    { label = "T3",     match = function(c) return not c.isMythic and c.tier == 3 end },
    { label = "T4",     match = function(c) return not c.isMythic and c.tier == 4 end },
    { label = "T5",     match = function(c) return not c.isMythic and c.tier == 5 end },
    { label = "T6",     match = function(c) return not c.isMythic and c.tier == 6 end },
    { label = "T7",     match = function(c) return not c.isMythic and c.tier == 7 end },
    { label = "T8",     match = function(c) return not c.isMythic and c.tier == 8 end },
    { label = "Mythic", match = function(c) return c.isMythic end },
}

local PICKER_EVENT_FILTERS = {
    { label = "All Triggers",   match = function(c) return true end },
    { label = "Proc on Hit",    match = function(c) return c.eventType == 0 end },
    { label = "Proc on Cast",   match = function(c) return c.eventType == 1 end },
    { label = "Proc on Heal",   match = function(c) return c.eventType == 2 end },
    { label = "Proc on Struck", match = function(c) return c.eventType == 3 end },
}

local pickerTier   = 1
local pickerEvent  = 1
local pickerSearch = ""

local function MatchesPickerFilter(cat)
    if not cat then
        return pickerTier == 1 and pickerEvent == 1
    end
    local tf = PICKER_TIER_FILTERS[pickerTier]
    local ef = PICKER_EVENT_FILTERS[pickerEvent]
    return (tf and tf.match(cat)) and (ef and ef.match(cat))
end

local function InitPickerDropdown(dd, list, getCurrentIdx, onChoose)
    UIDropDownMenu_Initialize(dd, function(self, level)
        local cur = getCurrentIdx()
        for i, item in ipairs(list) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = item.label
            info.checked = (i == cur)
            info.func    = function()
                onChoose(i)
                UIDropDownMenu_SetSelectedID(dd, i)
                UIDropDownMenu_SetText(dd, list[i].label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local cur = getCurrentIdx()
    UIDropDownMenu_SetSelectedID(dd, cur)
    UIDropDownMenu_SetText(dd, list[cur].label)
end

local picker
local pickerCtx
local RebuildPickerRows

local SCROLL_IDS = { [99998] = true, [99999] = true }

-- families already socketed; the socket being changed (pickerCtx) doesn't count,
-- so its own family (other tiers) can be picked to replace it
local function CollectActiveFamilies()
    local active = {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    for ord = 0, 5 do
        local slot = AG.loadout[ord]
        if slot then
            for idx = 0, 3 do
                local data = slot[idx]
                local skip = pickerCtx and pickerCtx.ord == ord and pickerCtx.idx == idx
                if data and data.gemId and data.gemId > 0 and not skip then
                    local cat = catalog[data.gemId]
                    if cat and cat.family and cat.family ~= "" then
                        active[cat.family] = true
                    end
                end
            end
        end
    end
    return active
end

local function GetSortedStashGems()
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local activeFamilies = CollectActiveFamilies()
    local out = {}
    for entry, count in pairs(stock) do
        local isGem
        if catalogReady then
            isGem = catalog[entry] ~= nil
        else
            isGem = not SCROLL_IDS[entry]
        end

        local familyOk = true
        if isGem and catalogReady then
            local cat = catalog[entry]
            local family = cat and cat.family or ""
            if family ~= "" and activeFamilies[family] then
                familyOk = false
            end
        end

        local filterOk = true
        if isGem and catalogReady then
            filterOk = MatchesPickerFilter(catalog[entry])
        end

        if isGem and familyOk and filterOk and count > 0 then
            if PA.ItemCache then PA.ItemCache.Register(entry) end
            local name, _, quality, _, _, _, _, _, _, texture = GetItemInfo(entry)
            local shownName = PA.CleanGemTierMarker(name or ("Item " .. entry))
            local cat = catalog[entry]
            local searchOk = pickerSearch == ""
                or shownName:lower():find(pickerSearch, 1, true)
                or (cat and cat.family and cat.family:lower():find(pickerSearch, 1, true))
            if searchOk then
                out[#out + 1] = {
                    entry = entry, count = count,
                    name = shownName,
                    texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                    quality = quality or 1,
                    tier = (cat and cat.tier) or 0,
                }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

local function BuildPicker()
    if picker then return picker end
    local f = CreateFrame("Frame", "AstralGemsPicker", UIParent)
    f:SetSize(560, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    UI.AstralBackdrop(f)
    UI.AddStarfield(f, 0.3)
    f:Hide()
    tinsert(UISpecialFrames, "AstralGemsPicker")

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Pick a gem from the stash")
    title:SetTextColor(unpack(UI.Color.textTitle))
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(close)
    close:SetPoint("TOPRIGHT", -2, -2)

    local tierLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tierLbl:SetPoint("TOPLEFT", 22, -44)
    tierLbl:SetText("Tier")

    local tierDd = CreateFrame("Frame", "AstralGemsPickerTierDD", f, "UIDropDownMenuTemplate")
    tierDd:SetPoint("TOPLEFT", tierLbl, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(tierDd, 90)
    InitPickerDropdown(tierDd, PICKER_TIER_FILTERS,
        function() return pickerTier end,
        function(i)
            pickerTier = i
            if RebuildPickerRows then RebuildPickerRows() end
        end)
    f.tierDd = tierDd

    local evtLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    evtLbl:SetPoint("TOPLEFT", tierLbl, "TOPRIGHT", 120, 0)
    evtLbl:SetText("Trigger")

    local evtDd = CreateFrame("Frame", "AstralGemsPickerEventDD", f, "UIDropDownMenuTemplate")
    evtDd:SetPoint("TOPLEFT", evtLbl, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(evtDd, 130)
    InitPickerDropdown(evtDd, PICKER_EVENT_FILTERS,
        function() return pickerEvent end,
        function(i)
            pickerEvent = i
            if RebuildPickerRows then RebuildPickerRows() end
        end)
    f.evtDd = evtDd

    local search = UI.MakeSearchBox(f, {
        width       = 560 - 22 - 24,
        height      = 24,
        placeholder = "Search gems by name or family…",
        onChanged   = function(text)
            pickerSearch = (text or ""):lower()
            if RebuildPickerRows then RebuildPickerRows() end
        end,
    })
    search:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -96)
    f.search = search

    local scroll = CreateFrame("ScrollFrame", "AstralGemsPickerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -130)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(560 - 12 - 28, 1)
    scroll:SetScrollChild(content)
    f.content = content
    content._rows = {}

    if UI.SkinTree then UI.SkinTree(f) end
    picker = f
    return f
end

RebuildPickerRows = function()
    if not picker then return end
    local content = picker.content
    if not content then return end

    for _, r in ipairs(content._rows) do r:Hide() end

    local rows = GetSortedStashGems()
    local rowH = 38
    content:SetHeight(math.max(1, #rows * rowH))

    for i, gem in ipairs(rows) do
        local r = content._rows[i]
        if not r then
            r = CreateFrame("Button", nil, content)
            r:SetSize(content:GetWidth() - 10, rowH - 2)
            local bg = r:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.06, 0.06, 0.07, 0.55)
            r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            r:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(rowH - 6, rowH - 6)
            r.icon:SetPoint("LEFT", 4, 0)
            r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            r.name:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
            r.count = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            r.count:SetPoint("RIGHT", -6, 0)
            r:SetScript("OnEnter", function(self)
                if self._entry then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("item:" .. self._entry)
                    GameTooltip:Show()
                end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            content._rows[i] = r
        end
        r._entry = gem.entry
        r.icon:SetTexture(gem.texture)
        local q = ITEM_QUALITY_COLORS[gem.quality]
        local nameColor = q and string.format("|cff%02x%02x%02x", q.r * 255, q.g * 255, q.b * 255) or "|cffffffff"
        r.name:SetText(nameColor .. gem.name .. "|r  |cff888888T" .. gem.tier .. "|r")
        r.count:SetText("|cffffffffx" .. gem.count .. "|r")
        r:SetScript("OnClick", function()
            if IsModifiedClick("CHATLINK") then
                if ProjectAstral.InsertChatLink then
                    ProjectAstral.InsertChatLink(select(2, GetItemInfo(gem.entry)))
                end
                return
            end
            if not pickerCtx then return end
            local schema = SLOT_SCHEMA[pickerCtx.ord + 1]
            local cur = AG.loadout[pickerCtx.ord] and AG.loadout[pickerCtx.ord][pickerCtx.idx]
            if cur and cur.gemId and cur.gemId > 0 and AG.ApplyLoadoutText then
                -- replacing a gem: the apply queue unsockets it first, checks with the server, then sockets
                AG.ApplyLoadoutText(string.format("AGEMS:1:%d.%d=%d", pickerCtx.ord, pickerCtx.idx, gem.entry))
                picker:Hide()
                return
            end
            if AIO and AIO.Handle then
                AG._pendingGemEntry = gem.entry
                AIO.Handle("AstralgemServer", "Socket", schema.equipSlot, pickerCtx.idx, gem.entry)
            else
                Send(string.format("gem socket %d %d %d", schema.equipSlot, pickerCtx.idx, gem.entry))
            end
            picker:Hide()
        end)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        r:Show()
    end

    if #rows == 0 then
        if not content.empty then
            content.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            content.empty:SetPoint("TOP", 0, -10)
        end
        content.empty:SetText("No gems match your filters or search.")
        content.empty:Show()
    elseif content.empty then
        content.empty:Hide()
    end
end

local function OpenPicker(ord, idx)
    pickerCtx = { ord = ord, idx = idx }
    local f = BuildPicker()
    if f.search then f.search:Clear() end
    pickerSearch = ""
    RebuildPickerRows()
    f:Show()
    f:Raise()
end

local SOCKET_SIZE = 52
local SOCKET_GAP = 10

-- Vertical slot box (sockets stacked vertically)
local function BuildSlotBox(parent, schemaIdx, opts)
    opts = opts or {}
    local socketSize = opts.socketSize or SOCKET_SIZE
    local socketGap = opts.socketGap or SOCKET_GAP
    local nameWidth = opts.showGemNames and (opts.gemNameWidth or 140) or 0
    local schema = SLOT_SCHEMA[schemaIdx]
    local nSockets = #schema.colors
    local labelHeight = 26
    local labelGap = 12
    local socketAreaHeight = nSockets * socketSize + (nSockets - 1) * socketGap
    local w = socketSize + 20 + nameWidth
    local h = labelHeight + labelGap + socketAreaHeight
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    box.gemNameWidth = nameWidth
    function box:SetGemNameWidth(width)
        if not opts.showGemNames then return end
        self.gemNameWidth = math.max(60, width)
        self:SetWidth(socketSize + 20 + self.gemNameWidth)
        for _, socket in ipairs(self.sockets) do
            if socket.gemName then socket.gemName:SetWidth(self.gemNameWidth - 8) end
        end
    end

    -- Label ABOVE the socket area - bigger and cleaner
    local label = box:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    if opts.showGemNames then
        label:SetPoint("TOP", box, "TOPLEFT", socketSize / 2 + 8, -2)
    else
        label:SetPoint("TOP", 0, -2)
    end
    label:SetText(schema.label)
    label:SetTextColor(0.85, 0.95, 1.00, 1)  -- Brighter, cleaner color
    label:SetShadowColor(0.05, 0.10, 0.25, 1.0)
    label:SetShadowOffset(1, -1)
    box.label = label

    -- Black background ONLY around the sockets (below the label) - tight fit
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(UI.Tint(0.02, 0.02, 0.05, 0.85))
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -(labelHeight + labelGap))
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

    box.sockets = {}
    box.schema = schema

    for i, color in ipairs(schema.colors) do
        local s = CreateFrame("Button", nil, box)
        s:SetSize(socketSize, socketSize)
        -- Vertical positioning (stacked top to bottom, starting below label with gap)
        local yOffset = -(labelHeight + labelGap + socketSize/2 + 4)
            - (i - 1) * (socketSize + socketGap)
        if opts.showGemNames then
            s:SetPoint("CENTER", box, "TOPLEFT", socketSize / 2 + 8, yOffset)
        else
            s:SetPoint("CENTER", box, "TOP", 0, yOffset)
        end

        local edges = {}
        local edgePoints = {
            { "TOPLEFT", "TOPRIGHT", 0, 0, 0, 0, "height" },
            { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 0, 0, "height" },
            { "TOPLEFT", "BOTTOMLEFT", 0, -2, 0, 2, "width" },
            { "TOPRIGHT", "BOTTOMRIGHT", 0, -2, 0, 2, "width" },
        }
        for edgeIndex, points in ipairs(edgePoints) do
            local edge = s:CreateTexture(nil, "ARTWORK")
            edge:SetTexture("Interface\\Buttons\\WHITE8X8")
            edge:SetPoint(points[1], s, points[1], points[3], points[4])
            edge:SetPoint(points[2], s, points[2], points[5], points[6])
            if points[7] == "height" then
                edge:SetHeight(2)
            else
                edge:SetWidth(2)
            end
            edge:SetVertexColor(COLOR_RGB[color][1], COLOR_RGB[color][2], COLOR_RGB[color][3], 0.75)
            edges[edgeIndex] = edge
        end
        s.edges = edges

        local face = s:CreateTexture(nil, "BACKGROUND")
        face:SetDrawLayer("BORDER", 1)
        face:SetTexture("Interface\\Buttons\\WHITE8X8")
        face:SetPoint("TOPLEFT", s, "TOPLEFT", 2, -2)
        face:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
        face:SetVertexColor(UI.Tint(0.04, 0.04, 0.06, 0.92))

        local icon = s:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("TOPLEFT", s, "TOPLEFT", 5, -5)
        icon:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -5, 5)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        icon:SetVertexColor(UI.Tint(0.8, 0.8, 1.0, 1))
        icon:SetDrawLayer("ARTWORK", 7)
        s.icon = icon
        icon:Hide()

        local emptyMark = s:CreateFontString(nil, "OVERLAY")
        emptyMark:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        emptyMark:SetPoint("CENTER", s, "CENTER", 0, 0)
        emptyMark:SetText("+")
        emptyMark:SetTextColor(COLOR_RGB[color][1], COLOR_RGB[color][2], COLOR_RGB[color][3], 0.82)
        emptyMark:Hide()
        s.emptyMark = emptyMark

        local dim = CreateModernLockGlyph(s, socketSize - 4)
        dim:Hide()
        s.dim = dim
        s.dim:SetFrameLevel(s:GetFrameLevel() + 20)

        s._color = color
        s._idx = i - 1
        s._ord = schema.ord
        s._readonly = opts.readonly

        if opts.showGemNames then
            local gemName = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            gemName:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
            gemName:SetPoint("LEFT", s, "RIGHT", 7, 0)
            gemName:SetWidth(math.max(52, nameWidth - 8))
            gemName:SetJustifyH("LEFT")
            gemName:SetWordWrap(false)
            if gemName.SetMaxLines then gemName:SetMaxLines(1) end
            gemName:SetTextColor(unpack(UI.Color.textPrimary))
            s.gemName = gemName
        end

        s:SetScript("OnEnter", function(self)
            if self.glow then
                self.glow:SetAlpha(0.55)
            end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local source = self._readonly and AG.inspect or AG.loadout
            local data = source[self._ord] and source[self._ord][self._idx]
            local qName = COLOR_NAME[self._color] or ""
            GameTooltip:AddLine(qName .. " Socket", 1, 1, 1)
            if data and data.gemId and data.gemId > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:SetHyperlink("item:" .. data.gemId)
                if not data.active then
                    GameTooltip:AddLine("|cffff5555Inactive|r — item quality too low.", 1, 0.4, 0.4, true)
                end
            else
                if not data or not data.active then
                    GameTooltip:AddLine("|cffaaaaaaInactive|r — needs at least " .. qName .. " quality item.", 0.6, 0.6, 0.6, true)
                else
                    GameTooltip:AddLine("|cffaaaaaaEmpty|r — click to socket a gem.", 0.6, 0.6, 0.6, true)
                end
            end
            GameTooltip:Show()
        end)
        s:SetScript("OnLeave", function(self)
            if self.glow then
                self.glow:SetAlpha(0.16)
            end
            GameTooltip:Hide()
        end)

        s:SetScript("OnClick", function(self)
            if self._readonly then return end
            local data = AG.loadout[self._ord] and AG.loadout[self._ord][self._idx]
            if IsModifiedClick("CHATLINK") then
                if data and data.gemId and data.gemId > 0 and ProjectAstral.InsertChatLink then
                    ProjectAstral.InsertChatLink(select(2, GetItemInfo(data.gemId)))
                end
                return
            end
            if data and data.gemId and data.gemId > 0 then
                if AIO and AIO.Handle then
                    AIO.Handle("AstralgemServer", "Unsocket",
                               SLOT_SCHEMA[self._ord + 1].equipSlot, self._idx)
                else
                    Send(string.format("gem unsocket %d %d",
                                       SLOT_SCHEMA[self._ord + 1].equipSlot, self._idx))
                end
            else
                if data and not data.active then
                    UIErrorsFrame:AddMessage("Slot inactive — item quality too low.", 1, 0.5, 0.5, 53, 4)
                    return
                end
                OpenPicker(self._ord, self._idx)
            end
        end)

        box.sockets[i] = s
    end

    return box
end

local function RenderTo(panel, source)
    if not panel or not panel.boxes then return end
    for schemaIdx = 1, 6 do
        local box = panel.boxes[schemaIdx]
        local schema = SLOT_SCHEMA[schemaIdx]
        if box then
            for i, s in ipairs(box.sockets) do
                local idx = i - 1
                local data = source[schema.ord] and source[schema.ord][idx]
                local filled = data and data.gemId and data.gemId > 0
                local active = data and data.active
                if filled then
                    ApplySocketGemIcon(s.icon, data.gemId)
                    if s.icon:IsShown() then
                        s.icon:SetAlpha(active and 1 or 0.72)
                    end
                else
                    s.icon:Hide()
                end

                if s.icon then
                    s.icon:SetDrawLayer("ARTWORK", 5)
                end
                local tint = COLOR_RGB[s._color]
                for _, edge in ipairs(s.edges) do
                    edge:SetVertexColor(tint[1], tint[2], tint[3], active and 0.75 or 0.35)
                end
                if s.emptyMark then
                    if not filled and active then s.emptyMark:Show()
                    else s.emptyMark:Hide() end
                end
                if s.dim then
                    if active or filled then
                        s.dim:Hide()
                    else
                        s.dim:Show()
                    end
                end
                if s.gemName then
                    if filled then
                        local category = PA.GemFusion and PA.GemFusion.catalog
                            and PA.GemFusion.catalog[data.gemId]
                        local name, _, quality = GetItemInfo(data.gemId)
                        name = PA.CleanGemTierMarker(name or (category and category.name)
                            or ("Item " .. data.gemId))
                        local spellName = category and category.family
                        if not spellName or spellName == "" then
                            spellName = name:match("[Oo]f%s+(.+)$") or name
                            spellName = spellName:gsub("^[Yy]ellow Astral Gem of%s+", "")
                        end
                        spellName = spellName:gsub("^%s*%[?T%d+%]?%s*", "")
                        spellName = spellName:gsub("%s*%[?T%d+%]?%s*$", "")
                        local qualityColor = ITEM_QUALITY_COLORS[quality or 1]
                        local color = qualityColor and string.format("|cff%02x%02x%02x",
                            qualityColor.r * 255, qualityColor.g * 255, qualityColor.b * 255)
                            or "|cffffffff"
                        local tier = category and tonumber(category.tier)
                        local inactive = active and "" or "  |cffff5555(inactive)|r"
                        s.gemName:SetText(color .. (tier and ("T" .. tier .. " ") or "") ..
                                          spellName .. "|r" .. inactive)
                        s.gemName:SetTextColor(unpack(UI.Color.textPrimary))
                    else
                        s.gemName:SetText("|cff777780Empty socket|r")
                    end
                end
                if s.icon then
                    s.icon:SetDrawLayer("ARTWORK", 7)
                end
            end
        end
    end
end
AG.RenderTo = RenderTo

function AG.Render()
    if AG.panel then
        RenderTo(AG.panel, AG.loadout)
        if AG.panel.statusText then
            AG.panel.statusText:SetText("")
        end
    end
    if AG.sheet and AG.sheet:IsVisible() then AG.sheet:Refresh() end
    if AG.inspectFramePanel and AG.inspectFramePanel:IsShown() then
        RenderTo(AG.inspectFramePanel, AG.inspect)
    end
end

local LOADOUT_PREFIX = "AGEMS:1:"

local function EncodeLoadout()
    local parts = {}
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                parts[#parts + 1] = string.format("%d.%d=%d", schema.ord, idx, data.gemId)
            end
        end
    end
    return LOADOUT_PREFIX .. table.concat(parts, ","), #parts
end
AG.EncodeLoadout = EncodeLoadout
AG.SLOT_SCHEMA   = SLOT_SCHEMA

local function DecodeLoadout(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    local body = text:match("^AGEMS:%d+:(.*)$")
    if not body then return nil end
    local wanted = {}
    for ord, idx, entry in body:gmatch("(%d+)%.(%d+)=(%d+)") do
        wanted[#wanted + 1] = { ord = tonumber(ord), idx = tonumber(idx), entry = tonumber(entry) }
    end
    return wanted
end

local function TiersByFamily(catalog)
    local byFamily = {}
    for entry, cat in pairs(catalog) do
        local family = cat.family or ""
        if family ~= "" then
            local list = byFamily[family]
            if not list then
                list = {}
                byFamily[family] = list
            end
            list[#list + 1] = { entry = entry, tier = tonumber(cat.tier) or 0 }
        end
    end
    for _, list in pairs(byFamily) do
        table.sort(list, function(a, b) return a.tier > b.tier end)
    end
    return byFamily
end

local function PickOwnedTier(wantedEntry, catalog, byFamily, left)
    if (left[wantedEntry] or 0) > 0 then return wantedEntry end
    local cat  = catalog[wantedEntry]
    local list = cat and byFamily[cat.family or ""]
    if not list then return nil end
    local maxTier = tonumber(cat.tier) or 0
    for _, g in ipairs(list) do
        if g.tier < maxTier and (left[g.entry] or 0) > 0 then return g.entry end
    end
    return nil
end

local function PlanLoadout(wanted, replace)
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local byFamily = catalogReady and TiersByFamily(catalog) or {}
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local left = {}
    for entry, n in pairs(stock) do left[entry] = n end

    local function FamilyOf(entry)
        local cat = catalogReady and catalog[entry]
        return (cat and cat.family) or ""
    end

    local current, holderOf = {}, {}
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                local key = schema.ord .. "." .. idx
                local family = FamilyOf(data.gemId)
                current[key] = { ord = schema.ord, idx = idx, gemId = data.gemId, family = family }
                if family ~= "" then holderOf[family] = key end
            end
        end
    end

    local wantedAt = {}
    for _, w in ipairs(wanted) do wantedAt[w.ord .. "." .. w.idx] = w.entry end

    local plan = { fill = {}, unsocket = {}, replaced = 0, already = 0, occupied = 0,
                   inactive = 0, missing = 0, family = 0, invalid = 0, lowerTier = 0 }
    local freed = {}

    local function Free(key)
        local c = current[key]
        freed[key] = true
        plan.unsocket[#plan.unsocket + 1] = { op = "unsocket",
            equipSlot = SLOT_SCHEMA[c.ord + 1].equipSlot, idx = c.idx, entry = c.gemId }
        if c.family ~= "" and holderOf[c.family] == key then holderOf[c.family] = nil end
    end

    for _, w in ipairs(wanted) do
        local schema = SLOT_SCHEMA[w.ord + 1]
        local key  = w.ord .. "." .. w.idx
        local data = AG.loadout[w.ord] and AG.loadout[w.ord][w.idx]
        local c    = (not freed[key]) and current[key] or nil
        if not schema or w.idx >= #schema.colors then
            plan.invalid = plan.invalid + 1
        elseif c and c.gemId == w.entry then
            plan.already = plan.already + 1
        elseif not (data and data.active) then
            plan.inactive = plan.inactive + 1
        elseif c and not replace then
            plan.occupied = plan.occupied + 1
        else
            local family = FamilyOf(w.entry)
            local holder = (family ~= "") and holderOf[family] or nil
            local freeHolder
            if holder and holder ~= key then
                local h = current[holder]
                local keep = (holder == "placed") or (h and wantedAt[holder] == h.gemId)
                if replace and not keep then freeHolder = holder end
            end

            if holder and holder ~= key and not freeHolder then
                plan.family = plan.family + 1
            else
                local returned = {}
                if freeHolder then returned[#returned + 1] = current[freeHolder].gemId end
                if c then returned[#returned + 1] = c.gemId end
                for _, g in ipairs(returned) do left[g] = (left[g] or 0) + 1 end

                local pick
                if catalogReady then
                    pick = PickOwnedTier(w.entry, catalog, byFamily, left)
                elseif (left[w.entry] or 0) > 0 then
                    pick = w.entry
                end

                if not pick or (c and pick == c.gemId) then
                    for _, g in ipairs(returned) do left[g] = left[g] - 1 end
                    if pick then
                        plan.already = plan.already + 1
                    else
                        plan.missing = plan.missing + 1
                    end
                else
                    if freeHolder then Free(freeHolder) end
                    if c then
                        Free(key)
                        plan.replaced = plan.replaced + 1
                    end
                    if family ~= "" then holderOf[family] = "placed" end
                    left[pick] = left[pick] - 1
                    if pick ~= w.entry then plan.lowerTier = plan.lowerTier + 1 end
                    plan.fill[#plan.fill + 1] = { equipSlot = schema.equipSlot, idx = w.idx, entry = pick }
                end
            end
        end
    end
    return plan
end

local function DescribePlan(plan)
    local n = #plan.fill
    local notes = {}
    if plan.replaced > 0 then
        notes[#notes + 1] = plan.replaced .. " replacing a socketed gem"
    end
    local movedOut = #plan.unsocket - plan.replaced
    if movedOut > 0 then
        notes[#notes + 1] = movedOut .. " same-family gem(s) removed from other sockets"
    end
    if plan.lowerTier > 0 then
        notes[#notes + 1] = plan.lowerTier .. " at a lower tier"
    end
    local head = (n > 0)
        and string.format("|cff80e090Ready to socket %d gem%s from your stash%s.|r", n, n == 1 and "" or "s",
            #notes > 0 and (" (" .. table.concat(notes, ", ") .. ")") or "")
        or "|cffffcc66Nothing to socket.|r"
    local skipped = {}
    local function add(count, text)
        if count > 0 then skipped[#skipped + 1] = string.format(text, count) end
    end
    add(plan.already,  "%d already in place")
    add(plan.occupied, "%d socket(s) still hold another gem")
    add(plan.inactive, "%d socket(s) inactive")
    add(plan.missing,  "%d gem(s) not in your stash at any tier")
    add(plan.family,   "%d share a family with an equipped gem")
    add(plan.invalid,  "%d unknown socket(s)")
    if #skipped == 0 then return head end
    return head .. "  Skipped: " .. table.concat(skipped, " · ")
end

-- ── Applying a loadout ──────────────────────────────────────────────
-- One server request at a time: each Socket/Unsocket waits for its result, then
-- the next step goes out after APPLY_STEP_GAP. After the unsockets, the queue asks
-- the server for the real loadout and stash ("refresh") and plans the sockets from
-- that ("replan"); it moves on as soon as both answers are in.
local APPLY_STEP_GAP  = 0.1   -- seconds between a result and the next request
local APPLY_TIMEOUT   = 4.0   -- give up on a step the server never answers
local REFRESH_TIMEOUT = 3.0   -- plan anyway if the refresh answers don't come

local applyQueue
local applyDone, applyRemoved, applyFailed = 0, 0, 0
local applyTotal, applyStep = 0, 0
local applyWait, applyAcc = 0, 0
local applyDriver = CreateFrame("Frame")
applyDriver:SetSize(1, 1)
applyDriver:Hide()

-- progress for the UI (Gem Builds loading bar): state = {
--   active, finished, step, total, text, done, removed, failed }
local progressListeners = {}
function AG.OnApplyProgress(fn)
    if type(fn) == "function" then progressListeners[#progressListeners + 1] = fn end
end

local function NotifyProgress(state)
    for _, fn in ipairs(progressListeners) do pcall(fn, state) end
end

-- refresh step: wait for a fresh loadout and stash state from the server
local refreshNeed, stashHooked
local function RefreshArrived(kind)
    if not (refreshNeed and AG._applyWaiting == "refresh") then return end
    if kind then refreshNeed[kind] = nil end
    if not (refreshNeed.loadout or refreshNeed.stash) then
        refreshNeed = nil
        AG._applyWaiting = nil
        applyWait, applyAcc = 0, 0
    end
end
function AG.OnApplyLoadoutRefreshed() RefreshArrived("loadout") end

local function SlotLabel(equipSlot)
    for _, s in ipairs(SLOT_SCHEMA) do
        if s.equipSlot == equipSlot then return s.label end
    end
    return "?"
end

local function GemLabel(entry)
    local cat = PA.GemFusion and PA.GemFusion.catalog and PA.GemFusion.catalog[entry]
    if PA.GemFusion and PA.GemFusion.GemDisplayName then
        local name = PA.GemFusion.GemDisplayName(entry, cat)
        if cat and cat.tier then return name .. " T" .. cat.tier end
        return name
    end
    return (GetItemInfo(entry)) or ("gem " .. tostring(entry))
end

local function StepText(step)
    if step.op == "refresh" then return "Checking your gems with the server" end
    if step.op == "replan"  then return "Planning the sockets" end
    if step.op == "unsocket" then
        return string.format("Removing %s from %s", step.entry and GemLabel(step.entry) or "gem",
            SlotLabel(step.equipSlot))
    end
    return string.format("Socketing %s into %s", GemLabel(step.entry), SlotLabel(step.equipSlot))
end

local function FinishApply()
    applyDriver:Hide()
    applyQueue = nil
    AG._applyWaiting = nil
    local parts = { applyDone .. " socketed" }
    if applyRemoved > 0 then parts[#parts + 1] = applyRemoved .. " removed" end
    if applyFailed  > 0 then parts[#parts + 1] = applyFailed .. " failed" end
    local msg = "Gem loadout applied: " .. table.concat(parts, ", ") .. "."
    DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Astral Gems]|r " .. msg)
    if UI.GainPopup then UI.GainPopup(msg, applyFailed > 0 and "warn" or "gems") end
    if AIO and AIO.Handle then AIO.Handle("AstralgemServer", "RequestLoadout") end
    if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
    NotifyProgress({ active = false, finished = true, step = applyTotal, total = applyTotal,
                     text = msg, done = applyDone, removed = applyRemoved, failed = applyFailed })
end

local function ApplyNext()
    local step = applyQueue and table.remove(applyQueue, 1)
    if not step then FinishApply(); return end
    local hasAIO = AIO and AIO.Handle
    applyStep = applyStep + 1
    NotifyProgress({ active = true, step = applyStep, total = applyTotal, text = StepText(step),
                     done = applyDone, removed = applyRemoved, failed = applyFailed })

    if step.op == "refresh" then
        if not stashHooked and PA.GemStash and PA.GemStash.OnStockChanged then
            stashHooked = true
            PA.GemStash.OnStockChanged(function() RefreshArrived("stash") end)
        end
        refreshNeed = { loadout = hasAIO and true or nil,
                        stash = (PA.GemStash and PA.GemStash.RequestState) and true or nil }
        AG._applyWaiting = "refresh"
        if hasAIO then AIO.Handle("AstralgemServer", "RequestLoadout") end
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        applyWait, applyAcc = REFRESH_TIMEOUT, 0
        if not (refreshNeed.loadout or refreshNeed.stash) then RefreshArrived() end
    elseif step.op == "replan" then
        local plan = PlanLoadout(DecodeLoadout(step.text) or {}, false)
        for _, s in ipairs(plan.fill) do applyQueue[#applyQueue + 1] = s end
        applyTotal = applyStep + #applyQueue
        applyWait, applyAcc = 0, 0
    elseif step.op == "unsocket" then
        if hasAIO then
            AG._applyWaiting = "unsocket"
            AIO.Handle("AstralgemServer", "Unsocket", step.equipSlot, step.idx)
            applyWait, applyAcc = APPLY_TIMEOUT, 0
        else
            Send(string.format("gem unsocket %d %d", step.equipSlot, step.idx))
            applyRemoved = applyRemoved + 1
            applyWait, applyAcc = 0.6, 0
        end
    elseif hasAIO then
        AG._pendingGemEntry = step.entry
        AG._applyWaiting = "socket"
        AIO.Handle("AstralgemServer", "Socket", step.equipSlot, step.idx, step.entry)
        applyWait, applyAcc = APPLY_TIMEOUT, 0
    else
        Send(string.format("gem socket %d %d %d", step.equipSlot, step.idx, step.entry))
        applyDone = applyDone + 1
        applyWait, applyAcc = 0.6, 0
    end
    applyDriver:Show()
end

applyDriver:SetScript("OnUpdate", function(_, dt)
    applyAcc = applyAcc + dt
    if applyAcc < applyWait then return end
    if AG._applyWaiting == "refresh" then
        AG._applyWaiting, refreshNeed = nil, nil   -- no answer in time: plan with what we have
    elseif AG._applyWaiting then
        AG._applyWaiting = nil
        applyFailed = applyFailed + 1
    end
    ApplyNext()
end)

local function OnApplyResult(kind, status)
    if AG._applyWaiting ~= kind then return end
    AG._applyWaiting = nil
    if status == "OK" then
        if kind == "socket" then applyDone = applyDone + 1 else applyRemoved = applyRemoved + 1 end
    else
        applyFailed = applyFailed + 1
        if status == "IN_COMBAT" then applyQueue = {} end
    end
    applyWait, applyAcc = APPLY_STEP_GAP, 0
end

function AG.OnApplySocketResult(status)   OnApplyResult("socket", status)   end
function AG.OnApplyUnsocketResult(status) OnApplyResult("unsocket", status) end

function AG.ApplyLoadoutText(text)
    if applyQueue then
        UIErrorsFrame:AddMessage("A gem loadout is already being applied.", 1, 0.5, 0.5, 53, 4)
        return
    end
    local wanted = DecodeLoadout(text)
    if not wanted then return end
    local plan = PlanLoadout(wanted, true)
    if #plan.fill == 0 then
        UIErrorsFrame:AddMessage("No gems to socket from that loadout.", 1, 0.8, 0.3, 53, 4)
        return
    end
    applyQueue = {}
    applyDone, applyRemoved, applyFailed = 0, 0, 0
    if #plan.unsocket > 0 then
        -- sockets are planned again from the server's state once the unsockets are done
        for _, s in ipairs(plan.unsocket) do applyQueue[#applyQueue + 1] = s end
        applyQueue[#applyQueue + 1] = { op = "refresh" }
        applyQueue[#applyQueue + 1] = { op = "replan", text = text }
        applyTotal = #applyQueue + #plan.fill   -- estimate until the replan
    else
        for _, s in ipairs(plan.fill) do applyQueue[#applyQueue + 1] = s end
        applyTotal = #applyQueue
    end
    applyStep = 0
    ApplyNext()
end

AG.DecodeLoadout = DecodeLoadout

function AG.DescribeLoadoutText(text)
    local wanted = DecodeLoadout(text)
    if not wanted then return nil end
    local plan = PlanLoadout(wanted, true)
    return DescribePlan(plan), #plan.fill
end

function AG.IsApplyingLoadout()
    return applyQueue ~= nil
end

function AG.LoadoutGemStatus(text)
    local wanted = DecodeLoadout(text)
    if not wanted then return nil end
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local catalogReady = next(catalog) ~= nil
    local byFamily = catalogReady and TiersByFamily(catalog) or {}

    local left = {}
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    for entry, n in pairs(stock) do left[entry] = n end
    for _, schema in ipairs(SLOT_SCHEMA) do
        local slot = AG.loadout and AG.loadout[schema.ord]
        for idx = 0, #schema.colors - 1 do
            local data = slot and slot[idx]
            if data and data.gemId and data.gemId > 0 then
                left[data.gemId] = (left[data.gemId] or 0) + 1
            end
        end
    end

    local st = { total = #wanted, exact = 0, lower = 0, missing = 0, byIndex = {} }
    local pending = {}
    for i, w in ipairs(wanted) do
        if (left[w.entry] or 0) > 0 then
            left[w.entry] = left[w.entry] - 1
            st.exact = st.exact + 1
            st.byIndex[i] = "exact"
        else
            pending[#pending + 1] = i
        end
    end
    for _, i in ipairs(pending) do
        local pick = catalogReady and PickOwnedTier(wanted[i].entry, catalog, byFamily, left)
        if pick then
            left[pick] = left[pick] - 1
            st.lower = st.lower + 1
            st.byIndex[i] = "lower"
        else
            st.missing = st.missing + 1
            st.byIndex[i] = "missing"
        end
    end
    return st
end

local exportDialog, importDialog

local function ShowLoadoutExport()
    if not (UI.MakeTextDialog) then return end
    if not exportDialog then
        exportDialog = UI.MakeTextDialog({
            name         = "AstralGemsExportDialog",
            title        = "Export Gem Loadout",
            subtitle     = "Ctrl+A to select all, Ctrl+C to copy, then share it.",
            button1Label = "Close",
        })
    end
    local text, count = EncodeLoadout()
    exportDialog:Show()
    exportDialog.editBox:SetText(text)
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
    exportDialog.status:SetText(count > 0
        and string.format("%d socketed gem%s in this loadout.", count, count == 1 and "" or "s")
        or "No gems socketed — the loadout is empty.")
end

local function ShowLoadoutImport()
    if not (UI.MakeTextDialog) then return end
    if not importDialog then
        importDialog = UI.MakeTextDialog({
            name         = "AstralGemsImportDialog",
            title        = "Import Gem Loadout",
            subtitle     = "Paste a loadout (AGEMS:1:...). Missing gems fall back to the best lower tier you own.",
            button1Label = "Import",
            onAccept     = function(text, dlg)
                if applyQueue then
                    dlg.status:SetText("|cffffcc66A gem loadout is already being applied — wait for it to finish.|r")
                    return true
                end
                local wanted = DecodeLoadout(text)
                if not wanted then
                    dlg.status:SetText("|cffff6060That isn't a gem loadout (it should start with AGEMS:1:).|r")
                    return true
                end
                local plan = PlanLoadout(wanted, true)
                if #plan.fill == 0 then
                    dlg.status:SetText(DescribePlan(plan))
                    return true
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cffa335ee[Astral Gems]|r " .. DescribePlan(plan))
                AG.ApplyLoadoutText(text)
                return false
            end,
        })
    end
    importDialog.status:SetText("Paste a loadout and click Import. Gems you own are socketed right away.")
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
    if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
end

local function AddButtonTip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- ── Character sheet (the Astral Gems tab) ───────────────────────────
-- Item cards around a faceted constellation figure holding a sword, and a detail
-- bar for the selected socket. Selecting a card, a socket or a part of the figure
-- selects the same item; that part of the figure turns gold. A plain click only
-- selects: gems are added, changed and removed with the detail bar's buttons.
-- The figure is drawn with straight line textures (rotated "UI-Taxi-Line", the
-- same technique Blizzard's taxi map uses) and star textures on the joints.
local BuildSheet
do
    local SOLID     = "Interface\\Buttons\\WHITE8X8"
    local LINE_TEX  = "Interface\\TaxiFrame\\UI-Taxi-Line"
    local STAR_TEX  = "Interface\\Cooldown\\star4"
    local LOCK_TEX  = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
    local GLOW_TEX  = { "Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64", "Interface\\Cooldown\\ping4", STAR_TEX }
    local CW, CH    = 340, 500         -- figure design units
    local LINE_W, LINE_W_ON = 10, 13   -- line texture width (the visible stroke is thinner)
    local TILE, TILE_GAP = 40, 6

    local HEX_GOLD  = "|cffffd970"
    local HEX_MUTED = "|cffdcdff0"
    local HEX_DIM   = "|cffaab0d4"
    local HEX_BAD   = "|cffff9a8f"
    local HEX_BTN   = "|cffffe39a"
    local TIER_HEX  = { "|cffffffff", "|cff7cf26a", "|cff7fb4ff", "|cffd395ff", "|cffff8c26", "|cfff2d98c", "|cffff738c", "|cffff4040" }
    local TRIGGER   = { [0] = "Proc on Hit", [1] = "Proc on Cast", [2] = "Proc on Heal", [3] = "Proc on Struck", [4] = "Proc on Crit", [5] = "DoT/HoT" }
    local PART_OF   = { [0] = "head", "neck", "chest", "legs", "boots", "weapon" }   -- by slot ord
    local ORD_OF    = { head = 0, neck = 1, chest = 2, legs = 3, boots = 4, weapon = 5 }

    -- ── figure geometry (faceted armor, sword raised) ──
    local function Seg(out, a, b) out[#out + 1] = { a[1], a[2], b[1], b[2] } end
    local function Poly(out, pts)
        for i = 1, #pts do Seg(out, pts[i], pts[i % #pts + 1]) end
    end
    local function Limb(out, a, b, w)
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local l = math.sqrt(dx * dx + dy * dy)
        local nx, ny = -dy / l, dx / l
        Seg(out, { a[1] + nx * w, a[2] + ny * w }, { b[1] + nx * w * 0.8, b[2] + ny * w * 0.8 })
        Seg(out, { a[1] - nx * w, a[2] - ny * w }, { b[1] - nx * w * 0.8, b[2] - ny * w * 0.8 })
    end
    local function Diamond(out, c, r)
        Poly(out, { { c[1], c[2] - r }, { c[1] + r, c[2] }, { c[1], c[2] + r }, { c[1] - r, c[2] } })
    end
    local function Joints(out, pts, major)
        for _, p in ipairs(pts) do out[#out + 1] = { p[1], p[2], major } end
    end

    local J = {
        skull = { 170, 60 }, neck = { 170, 98 }, core = { 170, 150 }, pelvis = { 170, 226 },
        shL = { 128, 118 }, shR = { 212, 118 }, elL = { 104, 188 }, elR = { 236, 188 },
        wrL = { 90, 250 }, wrR = { 250, 250 }, fingL = { 86, 272 },
        hipL = { 150, 236 }, hipR = { 190, 236 }, knL = { 146, 332 }, knR = { 194, 332 },
        anL = { 142, 422 }, anR = { 198, 422 },
    }

    local FIG = {}
    do
        local s, j
        -- head: hexagonal helm, visor, crest line
        s, j = {}, {}
        local helm = { { 170, 32 }, { 192, 44 }, { 194, 74 }, { 170, 90 }, { 146, 74 }, { 148, 44 } }
        Poly(s, helm); Seg(s, { 150, 60 }, { 190, 60 }); Seg(s, { 170, 32 }, { 170, 90 })
        Joints(j, helm, false); Joints(j, { J.skull }, true)
        FIG.head = { segs = s, joints = j, glow = { 170, 60, 40 }, label = { 112, 46 } }
        -- neck: collar
        s, j = {}, {}
        local collar = { { 160, 90 }, { 180, 90 }, { 186, 106 }, { 154, 106 } }
        Poly(s, collar)
        Joints(j, collar, false); Joints(j, { J.neck }, true)
        FIG.neck = { segs = s, joints = j, glow = { 170, 98, 26 }, label = { 124, 100 } }
        -- chest: plate, pauldrons, both arms (the right hand belongs to the sword)
        s, j = {}, {}
        local torso = { { 140, 108 }, { 200, 108 }, { 210, 150 }, { 192, 222 }, { 148, 222 }, { 130, 150 } }
        Poly(s, torso)
        Poly(s, { { 124, 106 }, { 106, 124 }, { 138, 134 } }); Poly(s, { { 216, 106 }, { 234, 124 }, { 202, 134 } })
        Seg(s, { 130, 150 }, { 210, 150 }); Seg(s, { 138, 186 }, { 202, 186 }); Seg(s, { 170, 108 }, { 170, 222 })
        Limb(s, J.shL, J.elL, 9); Limb(s, J.elL, J.wrL, 7); Limb(s, J.shR, J.elR, 9); Limb(s, J.elR, J.wrR, 7)
        Poly(s, { J.wrL, { 80, 262 }, J.fingL, { 94, 264 } })
        Joints(j, torso, false); Joints(j, { J.wrL, J.fingL }, false)
        Joints(j, { J.core, J.shL, J.shR, J.elL, J.elR }, true)
        FIG.chest = { segs = s, joints = j, glow = { 170, 165, 85 }, label = { 62, 140 } }
        -- legs: pelvis, straight-sided thighs and shins, knee diamonds
        s, j = {}, {}
        Poly(s, { { 148, 226 }, { 192, 226 }, { 170, 248 } })
        Limb(s, J.hipL, J.knL, 11); Limb(s, J.knL, J.anL, 8); Limb(s, J.hipR, J.knR, 11); Limb(s, J.knR, J.anR, 8)
        Diamond(s, J.knL, 9); Diamond(s, J.knR, 9)
        Joints(j, { J.pelvis, J.knL, J.knR }, true)
        FIG.legs = { segs = s, joints = j, glow = { 170, 330, 72 }, label = { 96, 330 } }
        -- boots
        s, j = {}, {}
        local footL = { { 136, 418 }, { 150, 418 }, { 154, 452 }, { 122, 454 } }
        local footR = { { 190, 418 }, { 204, 418 }, { 218, 454 }, { 186, 452 } }
        Poly(s, footL); Poly(s, footR)
        Joints(j, footL, false); Joints(j, footR, false); Joints(j, { J.anL, J.anR }, true)
        FIG.boots = { segs = s, joints = j, glow = { 170, 440, 52 }, label = { 92, 476 } }
        -- weapon: sword held in the right hand, blade pointing up
        s, j = {}, {}
        local grip, guard, tip = { 251, 266 }, { 253, 232 }, { 264, 40 }
        local dx, dy = tip[1] - guard[1], tip[2] - guard[2]
        local l = math.sqrt(dx * dx + dy * dy)
        local nx, ny = -dy / l, dx / l
        local function At(k, off) return { guard[1] + dx / l * k + nx * off, guard[2] + dy / l * k + ny * off } end
        Seg(s, grip, guard)
        Seg(s, At(0, -20), At(0, 20))
        Seg(s, At(0, -6), tip); Seg(s, At(0, 6), tip)
        Seg(s, At(6, 0), At(l * 0.8, 0))
        Diamond(s, { 250, 272 }, 5)
        Joints(j, { J.wrR, tip }, true); Joints(j, { At(0, -20), At(0, 20), grip }, false)
        FIG.weapon = { segs = s, joints = j, glow = { 258, 140, 75 }, label = { 302, 140 } }
    end

    -- click targets: points along every segment
    local HIT = {}
    for key, part in pairs(FIG) do
        for _, sg in ipairs(part.segs) do
            for i = 0, 4 do
                HIT[#HIT + 1] = { sg[1] + (sg[3] - sg[1]) * i / 4, sg[2] + (sg[4] - sg[2]) * i / 4, key }
            end
        end
    end

    -- Blizzard's taxi-route line math (TaxiFrame.lua): rotates a line texture between two points
    local LINEFACTOR_2 = (128 / 126) / 2
    local function DrawLine(T, C, sx, sy, ex, ey, w)
        local dx, dy = ex - sx, ey - sy
        local cx, cy = (sx + ex) / 2, (sy + ey) / 2
        if dx < 0 then dx, dy = -dx, -dy end
        local l = math.sqrt(dx * dx + dy * dy)
        T:ClearAllPoints()
        if l == 0 then
            T:SetTexCoord(0, 0, 0, 0, 0, 0, 0, 0)
            T:SetPoint("BOTTOMLEFT", C, "BOTTOMLEFT", cx, cy)
            T:SetPoint("TOPRIGHT", C, "BOTTOMLEFT", cx, cy)
            return
        end
        local s, c = -dy / l, dx / l
        local sc = s * c
        local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy
        if dy >= 0 then
            Bwid = ((l * c) - (w * s)) * LINEFACTOR_2
            Bhgt = ((w * c) - (l * s)) * LINEFACTOR_2
            BLx, BLy, BRy = (w / l) * sc, s * s, (l / w) * sc
            BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx
            TRy = BRx
        else
            Bwid = ((l * c) + (w * s)) * LINEFACTOR_2
            Bhgt = ((w * c) + (l * s)) * LINEFACTOR_2
            BLx, BLy, BRx = s * s, -(l / w) * sc, 1 + (w / l) * sc
            BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy
            TRx = TLy
        end
        T:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy)
        T:SetPoint("BOTTOMLEFT", C, "BOTTOMLEFT", cx - Bwid, cy - Bhgt)
        T:SetPoint("TOPRIGHT", C, "BOTTOMLEFT", cx + Bwid, cy + Bhgt)
    end

    local function SetFirstTexture(tex, list)
        for _, path in ipairs(list) do
            if tex:SetTexture(path) then return end
        end
    end

    local function SolidBorder(f, bg, edge)
        f.__paBackdrop = true   -- keep the navy: Theme.lua greys out navy backdrops it skins
        f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
        f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
    end

    local function Outline4(owner, layer, off, thick)
        local t = {}
        for i = 1, 4 do t[i] = owner:CreateTexture(nil, layer); t[i]:SetTexture(SOLID) end
        t[1]:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off);       t[1]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", off, off);       t[1]:SetHeight(thick)
        t[2]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -off, -off); t[2]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", off, -off); t[2]:SetHeight(thick)
        t[3]:SetPoint("TOPLEFT", owner, "TOPLEFT", -off, off);       t[3]:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", -off, -off); t[3]:SetWidth(thick)
        t[4]:SetPoint("TOPRIGHT", owner, "TOPRIGHT", off, off);      t[4]:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", off, -off); t[4]:SetWidth(thick)
        return t
    end
    local function Tint(list, r, g, b, a)
        for _, t in ipairs(list) do t:SetVertexColor(r, g, b, a) end
    end
    local function ShowAll(list, on)
        for _, t in ipairs(list) do if on then t:Show() else t:Hide() end end
    end

    local function GemName(entry)
        local cat = PA.GemFusion and PA.GemFusion.catalog and PA.GemFusion.catalog[entry]
        if PA.GemFusion and PA.GemFusion.GemDisplayName then
            return (PA.GemFusion.GemDisplayName(entry, cat)), cat
        end
        return PA.CleanGemTierMarker((GetItemInfo(entry)) or ("Gem " .. entry)), cat
    end

    -- ── socket tile ──
    local function NewTile(parent, size)
        local t = CreateFrame("Button", nil, parent)
        t:SetSize(size, size)
        t:RegisterForClicks("LeftButtonUp")
        t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetTexture(SOLID); t.bg:SetAllPoints(t)
        t.edges = Outline4(t, "BORDER", 0, 1)
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 3, -3); t.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -3, 3)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.plus = t:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(t.plus, math.floor(size * 0.45))
        t.plus:SetPoint("CENTER", t, "CENTER", 0, 1)
        t.plus:SetText("+")
        t.lock = t:CreateTexture(nil, "OVERLAY")
        t.lock:SetSize(size * 0.45, size * 0.45); t.lock:SetPoint("CENTER")
        if not t.lock:SetTexture(LOCK_TEX) then t.lock:SetTexture(SOLID); t.lock:SetVertexColor(UI.Tint(0.4, 0.42, 0.55, 1)) end
        t.sel = Outline4(t, "OVERLAY", 3, 2)
        Tint(t.sel, 1.00, 0.85, 0.44, 1)
        ShowAll(t.sel, false)
        return t
    end

    -- data: AG.loadout entry or nil; colour: socket quality
    local function PaintTile(t, data, colour, selected)
        local filled = data and data.gemId and data.gemId > 0
        local active = data and data.active
        local c = COLOR_RGB[colour]
        Tint(t.edges, c[1], c[2], c[3], active and 0.9 or 0.35)
        t.bg:SetVertexColor(c[1] * 0.10 + 0.02, c[2] * 0.10 + 0.03, c[3] * 0.10 + 0.07, 1)
        if filled then
            t.icon:SetTexture(GetGemTexture(data.gemId)); t.icon:SetAlpha(active and 1 or 0.45); t.icon:Show()
            t.plus:Hide(); t.lock:Hide()
        elseif active then
            t.icon:Hide(); t.lock:Hide()
            t.plus:SetText(string.format("|cff%02x%02x%02x+|r", c[1] * 255, c[2] * 255, c[3] * 255)); t.plus:Show()
        else
            t.icon:Hide(); t.plus:Hide(); t.lock:Show()
            t.bg:SetVertexColor(UI.Tint(0.035, 0.045, 0.11, 1))
        end
        ShowAll(t.sel, selected)
    end

    local function TileTooltip(t)
        local data = AG.loadout[t.ord] and AG.loadout[t.ord][t.idx]
        GameTooltip:SetOwner(t, "ANCHOR_RIGHT")
        if data and data.gemId and data.gemId > 0 then
            GameTooltip:SetHyperlink("item:" .. data.gemId)
            GameTooltip:AddLine("Double-click to remove it  ·  Shift-click to link in chat", 0.62, 0.64, 0.78)
        else
            local q = COLOR_NAME[t.colour] or ""
            GameTooltip:SetText(q .. " socket", 1, 1, 1)
            if data and data.active then
                GameTooltip:AddLine("Empty. Click to pick a gem.", 0.8, 0.8, 0.85)
            else
                GameTooltip:AddLine("Locked. Needs a " .. q .. " (or better) item.", 1, 0.6, 0.56, true)
            end
        end
        GameTooltip:Show()
    end

    -- ── the tab ──
    function BuildSheet(host)
        local sheet = CreateFrame("Frame", nil, host)
        sheet:SetAllPoints(host)
        AG.sheet = sheet
        AG.panel = sheet                  -- AG.Render / item cache refresh look for AG.panel
        local SIDE, GAP = 10, 12
        local sel = { ord = 2, idx = 0 }

        local function Busy() return AG.IsApplyingLoadout and AG.IsApplyingLoadout() end
        local function OpenFor(ord, idx)
            if Busy() then return end
            OpenPicker(ord, idx)
        end
        local function RemoveGem(ord, idx)
            if Busy() then return end
            local equipSlot = SLOT_SCHEMA[ord + 1].equipSlot
            if AIO and AIO.Handle then
                AIO.Handle("AstralgemServer", "Unsocket", equipSlot, idx)
            else
                Send(string.format("gem unsocket %d %d", equipSlot, idx))
            end
        end
        -- double click on a socket removes its gem (a single click on an empty
        -- socket already opens the picker)
        local function SocketDoubleClick(t)
            local data = AG.loadout[t.ord] and AG.loadout[t.ord][t.idx]
            if data and data.gemId and data.gemId > 0 then
                RemoveGem(t.ord, t.idx)
            end
        end

        local ground = sheet:CreateTexture(nil, "BACKGROUND")
        ground:SetTexture(SOLID); ground:SetAllPoints(sheet)
        ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

        -- header: summary and Export / Import / Refresh
        sheet.summary = sheet:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(sheet.summary, 13)
        sheet.summary:SetPoint("TOPLEFT", sheet, "TOPLEFT", SIDE + 2, -14)

        local refreshBtn = UI.MakeButton(sheet, "Refresh", { w = 84, h = 24, variant = "secondary",
            onClick = function()
                if AIO and AIO.Handle then AIO.Handle("AstralgemServer", "RequestLoadout") else Send("gem loadout") end
            end })
        refreshBtn:SetPoint("TOPRIGHT", sheet, "TOPRIGHT", -SIDE, -8)
        local importBtn = UI.MakeButton(sheet, "Import", { w = 84, h = 24, variant = "secondary", onClick = ShowLoadoutImport })
        importBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -6, 0)
        AddButtonTip(importBtn, "Import loadout",
            "Paste someone's loadout. Gems from your stash are socketed automatically, replacing gems that are in the way. If you don't have a gem, the highest lower tier of it that you own is used instead.")
        local exportBtn = UI.MakeButton(sheet, "Export", { w = 84, h = 24, variant = "secondary", onClick = ShowLoadoutExport })
        exportBtn:SetPoint("RIGHT", importBtn, "LEFT", -6, 0)
        AddButtonTip(exportBtn, "Export loadout", "Copy your socketed gems as text to share with other players.")

        -- legend: socket border = item quality that unlocks it
        local lx = SIDE
        for _, colour in ipairs({ C_GREEN, C_BLUE, C_PURPLE, C_ORANGE }) do
            local chip = CreateFrame("Frame", nil, sheet)
            chip:SetHeight(22)
            SolidBorder(chip, UI.Tinted({ 0.063, 0.090, 0.227, 0.95 }), UI.Tinted({ 0.173, 0.216, 0.408, 1 }))
            local sw = chip:CreateTexture(nil, "ARTWORK"); sw:SetTexture(SOLID); sw:SetSize(7, 7)
            sw:SetPoint("LEFT", chip, "LEFT", 9, 0)
            local c = COLOR_RGB[colour]; sw:SetVertexColor(c[1], c[2], c[3], 1)
            local tx = chip:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(tx, 11)
            tx:SetPoint("LEFT", sw, "RIGHT", 7, 0); tx:SetText(COLOR_NAME[colour] .. " item")
            chip:SetWidth(tx:GetStringWidth() + 32)
            chip:SetPoint("TOPLEFT", sheet, "TOPLEFT", lx, -40)
            lx = lx + chip:GetWidth() + 5
        end
        local legendNote = sheet:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(legendNote, 11)
        legendNote:SetPoint("TOPLEFT", sheet, "TOPLEFT", lx + 8, -45)
        legendNote:SetText(HEX_MUTED .. "Socket border = item quality that unlocks it|r")

        -- ── cards ──
        sheet.cards = {}
        local function NewCard(ord)
            local schema = SLOT_SCHEMA[ord + 1]
            local c = CreateFrame("Button", nil, sheet)
            c:RegisterForClicks("LeftButtonUp")
            SolidBorder(c, UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
            c.title = c:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(c.title, 13)
            c.title:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -8)
            c.count = c:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(c.count, 11)
            c.count:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -9)
            c.tiles, c.names = {}, {}
            for i, colour in ipairs(schema.colors) do
                local t = NewTile(c, TILE)
                t:SetPoint("TOPLEFT", c, "TOPLEFT", 10 + (i - 1) * (TILE + TILE_GAP), -28)
                t.ord, t.idx, t.colour = ord, i - 1, colour
                t:SetScript("OnClick", function(self)
                    local data = AG.loadout[self.ord] and AG.loadout[self.ord][self.idx]
                    if IsModifiedClick("CHATLINK") and data and data.gemId and data.gemId > 0 then
                        PA.InsertChatLink(select(2, GetItemInfo(data.gemId)))
                        return
                    end
                    sheet:Select(self.ord, self.idx)
                    if not (data and data.gemId and data.gemId > 0) and data and data.active then
                        OpenFor(self.ord, self.idx)   -- empty socket: straight to the gem picker
                    end
                end)
                t:SetScript("OnDoubleClick", SocketDoubleClick)
                t:SetScript("OnEnter", TileTooltip)
                t:SetScript("OnLeave", function() GameTooltip:Hide() end)
                c.tiles[i] = t
                local n = c:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(n, 11)
                n:SetPoint("TOPLEFT", c, "TOPLEFT", 10, -(28 + TILE + 7 + (i - 1) * 15))
                n:SetJustifyH("LEFT"); n:SetWordWrap(false)
                c.names[i] = n
            end
            c:SetHeight(28 + TILE + 7 + #schema.colors * 15 + 6)
            c.ord = ord
            c:SetScript("OnClick", function(self) sheet:Select(self.ord, 0) end)
            c:SetScript("OnEnter", function(self) if sel.ord ~= self.ord then self:SetBackdropBorderColor(UI.Tint(0.30, 0.36, 0.62, 1)) end end)
            c:SetScript("OnLeave", function(self) sheet:PaintCardBorder(self) end)
            sheet.cards[ord] = c
            return c
        end
        for ord = 0, 5 do NewCard(ord) end

        function sheet:PaintCardBorder(c)
            if c.ord == sel.ord then c:SetBackdropBorderColor(0.886, 0.753, 0.384, 1)
            else c:SetBackdropBorderColor(UI.Tint(0.165, 0.204, 0.400, 1)) end
        end

        -- ── figure ──
        local fig = CreateFrame("Frame", nil, sheet)
        SolidBorder(fig, UI.Tinted({ 0.024, 0.035, 0.094, 1 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
        local light = fig:CreateTexture(nil, "BACKGROUND", nil, 1)
        light:SetTexture(SOLID)
        light:SetPoint("TOPLEFT", fig, "TOPLEFT", 1, -1); light:SetPoint("BOTTOMRIGHT", fig, "BOTTOMRIGHT", -1, 1)
        local lr, lg, lb = UI.Tint(0.16, 0.39, 0.86)
        local tr, tg, tb = UI.Tint(0.47, 0.76, 1.00)
        light:SetGradientAlpha("VERTICAL", lr, lg, lb, 0.08, tr, tg, tb, 0.30)
        local cv = CreateFrame("Button", nil, fig)
        cv:RegisterForClicks("LeftButtonUp")
        fig.cv = cv

        local coreGlow = cv:CreateTexture(nil, "BACKGROUND")
        SetFirstTexture(coreGlow, GLOW_TEX); coreGlow:SetBlendMode("ADD"); coreGlow:SetVertexColor(UI.Tint(0.67, 0.86, 1, 0.22))
        coreGlow:Hide()   -- no glow ring behind the figure

        local veils = {}
        for i, vx in ipairs({ 40, 92, 150, 196, 252, 304 }) do
            local t = cv:CreateTexture(nil, "BORDER"); t:SetTexture(LINE_TEX); t:SetBlendMode("ADD")
            t:SetVertexColor(UI.Tint(0.67, 0.86, 1, 0.07))
            veils[i] = { t, vx, 0, vx + 14, CH }
        end
        local dust = {}
        do
            local seed = 5
            local function r() seed = (seed * 16807) % 2147483647; return seed / 2147483647 end
            for i = 1, 90 do
                local t = cv:CreateTexture(nil, "BORDER"); t:SetTexture(SOLID)
                local size = (r() < 0.25) and 2 or 1
                t:SetSize(size, size)
                dust[i] = { t, r() * CW, r() * CH, 0.25 + r() * 0.5, r() * 6.28 }
            end
        end

        local lines, stars = {}, {}
        for key, part in pairs(FIG) do
            for _, sg in ipairs(part.segs) do
                local t = cv:CreateTexture(nil, "ARTWORK"); t:SetTexture(LINE_TEX); t:SetBlendMode("ADD")
                lines[#lines + 1] = { tex = t, seg = sg, part = key }
            end
            for _, jn in ipairs(part.joints) do
                local glow = cv:CreateTexture(nil, "OVERLAY"); glow:SetTexture(STAR_TEX); glow:SetBlendMode("ADD")
                local dot = cv:CreateTexture(nil, "OVERLAY"); dot:SetTexture(SOLID)
                stars[#stars + 1] = { glow = glow, dot = dot, x = jn[1], y = jn[2], major = jn[3], part = key, ph = (jn[1] * 0.07 + jn[2] * 0.05) }
            end
        end
        local partLabel = cv:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(partLabel, 11)

        local scale = 1
        local function P(x, y) return x * scale, (CH - y) * scale end
        local function LayoutFigure()
            local fw, fh = fig:GetWidth() - 2, fig:GetHeight() - 2
            if fw <= 0 or fh <= 0 then return end
            scale = math.min(fw / CW, fh / CH)
            cv:SetSize(CW * scale, CH * scale)
            cv:ClearAllPoints(); cv:SetPoint("CENTER", fig, "CENTER", 0, 0)
            coreGlow:ClearAllPoints(); coreGlow:SetSize(380 * scale, 380 * scale)
            coreGlow:SetPoint("CENTER", cv, "BOTTOMLEFT", P(170, 175))
            for _, v in ipairs(veils) do
                local x1, y1 = P(v[2], v[3]); local x2, y2 = P(v[4], v[5])
                DrawLine(v[1], cv, x1, y1, x2, y2, LINE_W)
            end
            for _, d in ipairs(dust) do
                d[1]:ClearAllPoints(); d[1]:SetPoint("CENTER", cv, "BOTTOMLEFT", P(d[2], d[3]))
            end
            for _, ln in ipairs(lines) do
                local sg = ln.seg
                local x1, y1 = P(sg[1], sg[2]); local x2, y2 = P(sg[3], sg[4])
                DrawLine(ln.tex, cv, x1, y1, x2, y2, ln.part == PART_OF[sel.ord] and LINE_W_ON or LINE_W)
            end
            for _, st in ipairs(stars) do
                local size = (st.major and 15 or 9) * scale
                st.glow:SetSize(size * 1.6, size * 1.6)
                st.glow:ClearAllPoints(); st.glow:SetPoint("CENTER", cv, "BOTTOMLEFT", P(st.x, st.y))
                local ds = st.major and 3 or 2
                st.dot:SetSize(ds, ds)
                st.dot:ClearAllPoints(); st.dot:SetPoint("CENTER", cv, "BOTTOMLEFT", P(st.x, st.y))
            end
        end

        local function PartEmpty(key)
            local schema = SLOT_SCHEMA[ORD_OF[key] + 1]
            local slot = AG.loadout[schema.ord]
            for idx = 0, #schema.colors - 1 do
                local d = slot and slot[idx]
                if d and d.gemId and d.gemId > 0 then return false end
            end
            return true
        end

        local function PaintFigure()
            local selKey = PART_OF[sel.ord]
            local empty = {}
            for key in pairs(FIG) do empty[key] = PartEmpty(key) end
            for _, ln in ipairs(lines) do
                if ln.part == selKey then ln.tex:SetVertexColor(1.00, 0.87, 0.53, 0.95)
                elseif empty[ln.part] then ln.tex:SetVertexColor(UI.Tint(0.63, 0.84, 1.00, 0.30))
                else ln.tex:SetVertexColor(UI.Tint(0.71, 0.89, 1.00, 0.65)) end
            end
            for _, st in ipairs(stars) do
                local on = st.part == selKey
                st.base = on and 1 or (empty[st.part] and 0.5 or 0.95)
                if on then st.glow:SetVertexColor(1.00, 0.84, 0.43, 1) else st.glow:SetVertexColor(UI.Tint(0.65, 0.87, 1.00, 1)) end
                st.dot:SetVertexColor(1, 1, 1, st.base)
            end
            local lb = FIG[selKey].label
            partLabel:ClearAllPoints(); partLabel:SetPoint("CENTER", cv, "BOTTOMLEFT", P(lb[1], lb[2]))
            partLabel:SetText(HEX_GOLD .. SLOT_SCHEMA[sel.ord + 1].label:upper() .. "|r")
            LayoutFigure()   -- the selected part's lines are drawn a little wider
        end

        -- gentle twinkle on the joints and the dust (20 updates a second)
        local tick = 0
        fig:SetScript("OnUpdate", function(_, elapsed)
            tick = tick + elapsed
            if tick < 0.05 then return end
            local now = GetTime()
            tick = 0
            for _, st in ipairs(stars) do
                st.glow:SetAlpha((st.base or 1) * (0.78 + 0.22 * math.sin(now * 2 + st.ph)))
            end
            for _, d in ipairs(dust) do
                d[1]:SetVertexColor(0.86, 0.94, 1, d[4] * (0.55 + 0.45 * math.sin(now * 1.4 + d[5])))
            end
        end)

        -- clicking the figure selects the nearest part
        cv:SetScript("OnClick", function(self)
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local mx = (cx / es - self:GetLeft()) / scale
            local my = CH - (cy / es - self:GetBottom()) / scale
            local best, bd = nil, 26
            for _, h in ipairs(HIT) do
                local d = math.sqrt((h[1] - mx) ^ 2 + (h[2] - my) ^ 2)
                if d < bd then bd, best = d, h[3] end
            end
            if best then sheet:Select(ORD_OF[best], 0) end
        end)

        -- ── detail bar ──
        local bar = CreateFrame("Frame", nil, sheet)
        bar:SetHeight(74)
        UI.AstralBackdrop(bar, { thin = true })
        bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
        bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
        bar.__paBackdrop = true
        bar.tile = NewTile(bar, 48)
        bar.tile:SetPoint("LEFT", bar, "LEFT", 14, 0)
        bar.tile:SetScript("OnClick", function(self)
            local data = AG.loadout[self.ord] and AG.loadout[self.ord][self.idx]
            if not (data and data.gemId and data.gemId > 0) and data and data.active then OpenFor(self.ord, self.idx) end
        end)
        bar.tile:SetScript("OnDoubleClick", SocketDoubleClick)
        bar.tile:SetScript("OnEnter", TileTooltip)
        bar.tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.remove = UI.MakeButton(bar, "Remove", { w = 90, h = 26, variant = "danger" })
        bar.remove:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
        bar.action = UI.MakeButton(bar, "Change gem", { w = 124, h = 26, variant = "gold" })
        bar.action:SetPoint("RIGHT", bar.remove, "LEFT", -6, 0)
        bar.title = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.title, 14)
        bar.title:SetPoint("TOPLEFT", bar.tile, "TOPRIGHT", 14, -2)
        bar.title:SetPoint("RIGHT", bar.action, "LEFT", -12, 0)
        bar.title:SetJustifyH("LEFT"); bar.title:SetWordWrap(false)
        bar.desc = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.desc, 12)
        bar.desc:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -4)
        bar.desc:SetPoint("RIGHT", bar.action, "LEFT", -12, 0)
        bar.desc:SetHeight(32)
        bar.desc:SetJustifyH("LEFT"); bar.desc:SetJustifyV("TOP")

        bar.action:SetScript("OnClick", function() OpenFor(sel.ord, sel.idx) end)
        bar.remove:SetScript("OnClick", function() RemoveGem(sel.ord, sel.idx) end)

        local function GemsThatFit()
            local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
            local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
            local used, n = {}, 0
            for ord = 0, 5 do
                for idx = 0, 3 do
                    local d = AG.loadout[ord] and AG.loadout[ord][idx]
                    local cat = d and d.gemId and catalog[d.gemId]
                    if cat and cat.family then used[cat.family] = true end
                end
            end
            for entry, count in pairs(stock) do
                local cat = catalog[entry]
                if cat and count > 0 and not used[cat.family or ""] then n = n + 1 end
            end
            return n
        end

        local function PaintDetail()
            local schema = SLOT_SCHEMA[sel.ord + 1]
            local colour = schema.colors[sel.idx + 1]
            local data = AG.loadout[sel.ord] and AG.loadout[sel.ord][sel.idx]
            local q = COLOR_NAME[colour] or ""
            bar.tile.ord, bar.tile.idx, bar.tile.colour = sel.ord, sel.idx, colour
            PaintTile(bar.tile, data, colour, false)
            local busy = AG.IsApplyingLoadout and AG.IsApplyingLoadout()
            if data and data.gemId and data.gemId > 0 then
                local name, cat = GemName(data.gemId)
                local tier = cat and tonumber(cat.tier)
                local meta = (TRIGGER[cat and cat.eventType] and ("  ·  " .. TRIGGER[cat.eventType]) or "")
                    .. "  ·  " .. schema.label .. ", " .. q .. " socket"
                bar.title:SetText(name .. (tier and ("  " .. (TIER_HEX[tier] or "") .. "T" .. tier .. "|r") or "")
                    .. HEX_MUTED .. meta .. "|r")
                local desc = PA.GemStash and PA.GemStash.GemDescription and PA.GemStash.GemDescription(data.gemId)
                desc = desc or (HEX_DIM .. "Loading description…|r")
                if not data.active then
                    desc = HEX_BAD .. "Inactive: this socket needs a " .. q .. " (or better) item.|r  " .. desc
                end
                bar.desc:SetText(desc)
                bar.action:SetLabel(HEX_BTN .. "Change gem|r"); bar.action:Show(); bar.remove:Show()
            elseif data and data.active then
                bar.title:SetText("Empty " .. q .. " socket" .. HEX_MUTED .. "  ·  " .. schema.label .. "|r")
                local n = GemsThatFit()
                bar.desc:SetText(HEX_MUTED .. n .. (n == 1 and " gem" or " gems")
                    .. " in your stash can go here. One gem per family across the whole loadout.|r")
                bar.action:SetLabel(HEX_BTN .. "Add gem|r"); bar.action:Show(); bar.remove:Hide()
            else
                bar.title:SetText(HEX_MUTED .. "Locked " .. q .. " socket  ·  " .. schema.label .. "|r")
                bar.desc:SetText(HEX_MUTED .. "Equip a " .. q .. " (or better) " .. schema.label:lower()
                    .. " item to unlock this socket.|r")
                bar.action:Hide(); bar.remove:Hide()
            end
            bar.action:SetDisabledLook(busy and true or false)
            bar.remove:SetDisabledLook(busy and true or false)
        end

        -- ── layout ──
        local LEFT_COL, RIGHT_COL = { 0, 1, 2 }, { 5, 3, 4 }   -- weapon top right, next to the raised blade
        local function Layout()
            local w, h = sheet:GetWidth(), sheet:GetHeight()
            if w <= 0 or h <= 0 then return end
            local top, bottom = 70, 10 + 74 + 10
            local bodyH = math.max(200, h - top - bottom)
            local figW = math.min(bodyH * CW / CH, w - 2 * SIDE - 2 * GAP - 2 * 214)
            figW = math.max(180, figW)
            local colW = math.floor((w - 2 * SIDE - 2 * GAP - figW) / 2)
            fig:ClearAllPoints()
            fig:SetPoint("TOPLEFT", sheet, "TOPLEFT", SIDE + colW + GAP, -top)
            fig:SetSize(figW, bodyH)
            for side, list in ipairs({ LEFT_COL, RIGHT_COL }) do
                local x = side == 1 and SIDE or (SIDE + colW + GAP + figW + GAP)
                local y = top
                for _, ord in ipairs(list) do
                    local c = sheet.cards[ord]
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", sheet, "TOPLEFT", x, -y)
                    c:SetWidth(colW)
                    for _, n in ipairs(c.names) do n:SetWidth(colW - 20) end
                    y = y + c:GetHeight() + 10
                end
            end
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", sheet, "BOTTOMLEFT", SIDE, 10)
            bar:SetPoint("BOTTOMRIGHT", sheet, "BOTTOMRIGHT", -SIDE, 10)
            LayoutFigure()
            PaintFigure()
        end
        sheet:SetScript("OnSizeChanged", Layout)
        fig:SetScript("OnSizeChanged", function() LayoutFigure(); PaintFigure() end)

        -- ── refresh ──
        function sheet:Refresh()
            local total, filled, locked = 0, 0, 0
            for ord = 0, 5 do
                local schema = SLOT_SCHEMA[ord + 1]
                local c = self.cards[ord]
                local n = 0
                for i, colour in ipairs(schema.colors) do
                    local idx = i - 1
                    local data = AG.loadout[ord] and AG.loadout[ord][idx]
                    local has = data and data.gemId and data.gemId > 0
                    total = total + 1
                    if has then n = n + 1; filled = filled + 1
                    elseif not (data and data.active) then locked = locked + 1 end
                    PaintTile(c.tiles[i], data, colour, ord == sel.ord and idx == sel.idx)
                    local q = COLOR_NAME[colour] or ""
                    if has then
                        local name, cat = GemName(data.gemId)
                        local tier = cat and tonumber(cat.tier)
                        c.names[i]:SetText(name .. (tier and ("  " .. (TIER_HEX[tier] or "") .. "T" .. tier .. "|r") or "")
                            .. (data.active and "" or (HEX_BAD .. "  inactive|r")))
                    elseif data and data.active then
                        c.names[i]:SetText(HEX_DIM .. "Empty " .. q .. " socket|r")
                    else
                        c.names[i]:SetText(HEX_DIM .. "Locked " .. q .. " socket|r")
                    end
                end
                c.title:SetText(ord == sel.ord and (HEX_GOLD .. schema.label .. "|r") or schema.label)
                c.count:SetText(HEX_DIM .. n .. "/" .. #schema.colors .. "|r")
                self:PaintCardBorder(c)
            end
            local empty = total - filled - locked
            self.summary:SetText(HEX_GOLD .. filled .. "|r" .. HEX_MUTED .. " of " .. total .. " sockets filled  ·  |r"
                .. HEX_GOLD .. empty .. "|r" .. HEX_MUTED .. " empty  ·  " .. locked .. " locked|r")
            PaintFigure()
            PaintDetail()
        end

        function sheet:Select(ord, idx)
            sel.ord, sel.idx = ord, idx or 0
            self:Refresh()
        end

        -- the description and "gems that fit" follow the stash and item info
        if PA.GemStash and PA.GemStash.OnStockChanged then
            PA.GemStash.OnStockChanged(function() if sheet:IsVisible() then PaintDetail() end end)
        end
        if AG.OnApplyProgress then
            AG.OnApplyProgress(function() if sheet:IsVisible() then PaintDetail() end end)
        end

        Layout()
        sheet:Refresh()
        return sheet
    end
end

function AG.RefreshTheme()
    if AG.sheet and AG.sheet:IsVisible() then AG.sheet:Refresh() end
end


local function BuildAstralGemsTab(host)
    if not AG.sheet then BuildSheet(host) end
    host:SetScript("OnShow", function()
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestLoadout")
        else
            Send("gem loadout")
        end
        if not (PA.GemFusion and PA.GemFusion.catalog and next(PA.GemFusion.catalog)) then
            if PA.GemFusion and PA.GemFusion.RequestInfo then
                PA.GemFusion.RequestInfo()
            else
                Send("gem info")
            end
        end
        if not (PA.GemStash and PA.GemStash.GetStock and next(PA.GemStash.GetStock())) then
            SendChatMessage(".astralstash list", "SAY")
        end
        AG.Render()
    end)
end

local function ToggleFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "AstralGems" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("AstralGems")
        if mf._tabBar then mf._tabBar:SelectTab("AstralGems") end
    end
end

local function CompactSlotGrid(parent)
    local boxOpts = { socketSize = 20, readonly = true }

    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(200, 380)  -- Increased height for better spacing
    grid:SetPoint("TOP", parent, "TOP", 0, -56)
    parent.boxes = {}

    local col1X = 5
    local col2X = 65
    local col3X = 125
    local startY = 0
    local boxGap = -8  -- Gap between boxes in same column

    -- Column 1: Head, Neck, Boots
    local boxHead = BuildSlotBox(grid, 1, boxOpts)
    boxHead:SetPoint("TOPLEFT", grid, "TOPLEFT", col1X, startY)
    parent.boxes[1] = boxHead

    local boxNeck = BuildSlotBox(grid, 2, boxOpts)
    boxNeck:SetPoint("TOP", boxHead, "BOTTOM", 0, boxGap)
    parent.boxes[2] = boxNeck

    local boxBoots = BuildSlotBox(grid, 5, boxOpts)
    boxBoots:SetPoint("TOP", boxNeck, "BOTTOM", 0, boxGap)
    parent.boxes[5] = boxBoots

    -- Column 2: Chest, Legs
    local boxChest = BuildSlotBox(grid, 3, boxOpts)
    boxChest:SetPoint("TOPLEFT", grid, "TOPLEFT", col2X, startY)
    parent.boxes[3] = boxChest

    local boxLegs = BuildSlotBox(grid, 4, boxOpts)
    boxLegs:SetPoint("TOP", boxChest, "BOTTOM", 0, boxGap)
    parent.boxes[4] = boxLegs

    -- Column 3: Weapon
    local boxWeapon = BuildSlotBox(grid, 6, boxOpts)
    boxWeapon:SetPoint("TOPLEFT", grid, "TOPLEFT", col3X, startY)
    parent.boxes[6] = boxWeapon
end

local function HideInspectContentFrames()
    if InspectPaperDollFrame then InspectPaperDollFrame:Hide() end
    if InspectPVPFrame       then InspectPVPFrame:Hide()       end
    if InspectTalentFrame    then InspectTalentFrame:Hide()    end
    if InspectModelFrame     then InspectModelFrame:Hide()     end
end

local function ShowInspectGemsContent()
    if not (InspectFrame and InspectFrame.gemsPanel) then return end
    HideInspectContentFrames()
    InspectFrame.gemsPanel:Show()
    local unit = (InspectFrame.unit) or "target"
    local name = UnitName(unit)

    if InspectFrame.gemsPanel._portraitCopy and UnitExists(unit) then
        SetPortraitTexture(InspectFrame.gemsPanel._portraitCopy, unit)
    end
    if InspectFrame.gemsPanel._titleCopy and InspectFrameTitleText then
        InspectFrame.gemsPanel._titleCopy:SetText(
            InspectFrameTitleText:GetText() or "")
    end
    if name and name ~= "" then
        AG.inspecting = name
        ClearTable(AG.inspect)
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestInspect", name)
        else
            Send("gem inspect " .. name)
        end
        if InspectFrame.gemsPanel.statusText then
            InspectFrame.gemsPanel.statusText:SetText(
                "|cffffd000Inspect:|r " .. name)
        end
    else
        if InspectFrame.gemsPanel.statusText then
            InspectFrame.gemsPanel.statusText:SetText(
                "|cffff5555No target selected.|r")
        end
    end
    AG.Render()
end

local function HideInspectGemsContent()
    if InspectFrame and InspectFrame.gemsPanel then
        InspectFrame.gemsPanel:Hide()
    end
end

local inspectTabHooked = false
local function BuildInspectFrameGemsTab()
    if inspectTabHooked then return end
    if not InspectFrame then return end

    local existingCount = InspectFrame.numTabs or 3
    local lastTab = _G["InspectFrameTab" .. existingCount]
    if not lastTab then return end

    local newIdx = existingCount + 1
    local newTab = CreateFrame("Button", "InspectFrameTab" .. newIdx,
                                InspectFrame, "CharacterFrameTabButtonTemplate")
    newTab:SetID(newIdx)
    newTab:SetText("Gems")
    newTab:SetPoint("LEFT", lastTab, "RIGHT", -16, 0)
    PanelTemplates_TabResize(newTab, 0)
    InspectFrame.numTabs = newIdx

    local panel = CreateFrame("Frame", "InspectFrameGemsPanel", InspectFrame)
    panel:SetFrameLevel((InspectFrame:GetFrameLevel() or 0) + 10)
    panel:SetPoint("TOPLEFT",     InspectFrame, "TOPLEFT",     10,  -20)
    panel:SetPoint("BOTTOMRIGHT", InspectFrame, "BOTTOMRIGHT", -32,  76)

    if UI and UI.AstralBackdrop then
        UI.AstralBackdrop(panel, { cosmic = true })
    end

    local topOver = CreateFrame("Frame", nil, panel)
    topOver:SetAllPoints(InspectFrame)
    topOver:SetFrameLevel((panel:GetFrameLevel() or 0) + 10)

    local portraitCopy = topOver:CreateTexture(nil, "OVERLAY")
    if InspectFramePortrait then
        portraitCopy:SetSize(InspectFramePortrait:GetWidth(),
                             InspectFramePortrait:GetHeight())
        portraitCopy:SetPoint("TOPLEFT", InspectFramePortrait, "TOPLEFT", 0, 0)
    else
        portraitCopy:SetSize(60, 60)
        portraitCopy:SetPoint("TOPLEFT", InspectFrame, "TOPLEFT", 7, -6)
    end
    panel._portraitCopy = portraitCopy

    local titleCopy = topOver:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if InspectFrameTitleText then
        titleCopy:SetPoint("TOP", InspectFrameTitleText, "TOP", 0, 0)
    else
        titleCopy:SetPoint("TOP", InspectFrame, "TOP", 0, -15)
    end
    titleCopy:SetTextColor(1, 0.82, 0)
    panel._titleCopy = titleCopy

    panel:Hide()
    InspectFrame.gemsPanel = panel
    AG.inspectFramePanel = panel

    local statusText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOP", 0, -30)
    statusText:SetText("")
    panel.statusText = statusText

    CompactSlotGrid(panel)

    newTab:SetScript("OnClick", function(self)
        PanelTemplates_Tab_OnClick(self, InspectFrame)
        ShowInspectGemsContent()
    end)

    for i = 1, existingCount do
        local t = _G["InspectFrameTab" .. i]
        if t and not t._astralGemsTabHook then
            t._astralGemsTabHook = true
            t:HookScript("OnClick", function() HideInspectGemsContent() end)
        end
    end

    InspectFrame:HookScript("OnHide", function()
        HideInspectGemsContent()
        AG.inspecting = nil
        ClearTable(AG.inspect)
    end)

    inspectTabHooked = true
end

if PA.ItemCache and PA.ItemCache.Subscribe then
    PA.ItemCache.Subscribe(function()
        if AG.panel and AG.panel:IsShown() then AG.Render() end
        if picker and picker:IsShown() and RebuildPickerRows then
            RebuildPickerRows()
        end
        if AG.inspectFramePanel and AG.inspectFramePanel:IsShown() then
            AG.Render()
        end
    end)
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("ADDON_LOADED")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("UNIT_INVENTORY_CHANGED")
local pendingReqAt = 0
evt:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_InspectUI" then
            BuildInspectFrameGemsTab()
        end
    elseif event == "PLAYER_LOGIN" then
        if AIO and AIO.Handle then
            AIO.Handle("AstralgemServer", "RequestInfo")
            AIO.Handle("AstralgemServer", "RequestLoadout")
        end
    elseif event == "UNIT_INVENTORY_CHANGED" and arg1 == "player" then
        pendingReqAt = GetTime() + 0.1
        evt:SetScript("OnUpdate", function(self)
            if GetTime() < pendingReqAt then return end
            self:SetScript("OnUpdate", nil)
            if AIO and AIO.Handle then
                AIO.Handle("AstralgemServer", "RequestLoadout")
            end
        end)
    end
end)

if IsAddOnLoaded and IsAddOnLoaded("Blizzard_InspectUI") then
    BuildInspectFrameGemsTab()
end

PA:RegisterModule("AstralGems", "Astral Gems", ToggleFrame, {
    subtitle = "Place gems in loadout sockets — item quality unlocks slots.",
})
PA:RegisterTabContent("AstralGems", BuildAstralGemsTab)
