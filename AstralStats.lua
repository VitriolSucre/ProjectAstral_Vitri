
local PA = ProjectAstral
local UI = PA.UI

-- Stats tab: your character and account at a glance (identity, play time, wallet,
-- gem stash and builds), then every bonus the Astral Tree gives you, from unlocked
-- nodes plus spent Paragon points, in one column per bonus group. Totals come from
-- Skilltree.lua (AT.NodeTotals / AT.ParagonTotals) so this always matches the
-- tree's Total Bonuses panel. Colours that must survive Theme.lua's vivid-text pass
-- are inline |c codes, and frames set __paBackdrop so Theme.lua keeps their navy.

local SOLID  = "Interface\\Buttons\\WHITE8X8"
local ROW_H  = 24
local COLS   = 3     -- Offensive / Defensive / Quality of Life (+ anything ungrouped)
local GAP    = 10
local SIDE   = 10
local TILE_H = 46

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"

local host
local tiles = {}
local account = {}

local function Round(v)
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return tostring(math.floor(v + 0.5))
    end
    return string.format("%.1f", v)
end

-- same sign rules as the tree's FormatEffect, without the label
local function ValueText(meta, v)
    if meta and meta.unit == "flag" then return "Unlocked" end
    local sign
    if meta and meta.invert then
        sign = v > 0 and "-" or (v < 0 and "+" or "")
    else
        sign = v < 0 and "-" or "+"
    end
    local text = sign .. Round(math.abs(v))
    if meta and meta.unit == "pct" then text = text .. "%" end
    return text
end

local function FriendlyLabel(effectType)
    local label = effectType:gsub("_PCT$", ""):gsub("_ALLOWED$", "")
        :gsub("_UNLOCKED$", ""):gsub("_", " ")
    return label:gsub("%S+", function(word)
        return word:sub(1, 1) .. word:sub(2):lower()
    end)
end

local function NavyBox(f, bg, edge)
    f.__paBackdrop = true   -- Theme.lua would grey out the navy
    f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

local function OpenTab(id)
    local mf = PA.mainFrame
    if mf and mf.SwitchTab then mf:SwitchTab(id) end
end

-- ── summary tile: icon, label, value; optionally opens a tab ──
local function MakeTile(parent, label, iconPath, tint, tabId, tip)
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(TILE_H)
    NavyBox(t, UI.Tinted({ 0.063, 0.090, 0.227, 0.95 }), UI.Tinted({ 0.173, 0.216, 0.408, 1 }))

    local lane = t:CreateTexture(nil, "BACKGROUND", nil, 1)
    lane:SetTexture(SOLID)
    lane:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1)
    lane:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 1, 1)
    lane:SetWidth(38)
    lane:SetVertexColor(tint[1], tint[2], tint[3], 0.16)

    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("CENTER", lane, "CENTER")
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    t.label = t:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(t.label, 11)
    t.label:SetPoint("TOPLEFT", lane, "TOPRIGHT", 9, -7)
    t.label:SetPoint("RIGHT", t, "RIGHT", -6, 0)
    t.label:SetJustifyH("LEFT"); t.label:SetWordWrap(false)
    t.label:SetText(HEX_MUTED .. label .. "|r")

    t.value = t:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(t.value, 15)
    t.value:SetPoint("TOPLEFT", t.label, "BOTTOMLEFT", 0, -3)
    t.value:SetPoint("RIGHT", t, "RIGHT", -6, 0)
    t.value:SetJustifyH("LEFT"); t.value:SetWordWrap(false)
    t.hex = string.format("|cff%02x%02x%02x", tint[1] * 255, tint[2] * 255, tint[3] * 255)

    function t:SetValue(v) self.value:SetText(self.hex .. tostring(v) .. "|r") end

    if tabId then
        t:SetScript("OnClick", function() OpenTab(tabId) end)
        t:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(UI.Tint(0.30, 0.36, 0.62, 1))
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(tip or label, 1, 1, 1)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(UI.Tint(0.173, 0.216, 0.408, 1))
            GameTooltip:Hide()
        end)
    else
        t:EnableMouse(false)
    end
    return t
end

-- ── bonus columns ──
-- Every group (Offensive, Defensive, Quality of Life, …) is a header followed by
-- its bonus rows. The whole list flows top to bottom through the columns like a
-- newspaper, so a long group continues in the next column ("continued") instead of
-- running off the page, and all columns end at about the same height. The area
-- scrolls if it still doesn't fit.
local HDR_H     = 34   -- group header height
local GROUP_GAP = 12   -- space before a new group in the same column
local COL_PAD   = 6    -- inner padding at the top and bottom of a column

local flow = { headers = {}, rows = {}, cols = {} }

local function GetHeader(i)
    local h = flow.headers[i]
    if h then return h end
    h = CreateFrame("Frame", nil, flow.content)
    h:SetHeight(HDR_H)
    h:SetFrameLevel(flow.content:GetFrameLevel() + 2)   -- above the column backgrounds
    local bar = h:CreateTexture(nil, "ARTWORK")
    bar:SetTexture(SOLID)
    bar:SetVertexColor(0.886, 0.753, 0.384, 1)
    bar:SetSize(3, 16)
    bar:SetPoint("LEFT", h, "LEFT", 8, 1)
    h.title = h:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(h.title, 14)
    h.title:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    h.count = h:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(h.count, 11)
    h.count:SetPoint("RIGHT", h, "RIGHT", -10, 0)
    local rule = h:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(SOLID)
    rule:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.30))
    rule:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  6, 2)
    rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -6, 2)
    rule:SetHeight(1)
    flow.headers[i] = h
    return h
end

local function GetRow(i)
    local r = flow.rows[i]
    if r then return r end

    r = CreateFrame("Frame", nil, flow.content)
    r:SetHeight(ROW_H)
    r:SetFrameLevel(flow.content:GetFrameLevel() + 2)

    r.alt = r:CreateTexture(nil, "BACKGROUND")
    r.alt:SetTexture(SOLID); r.alt:SetAllPoints()
    r.alt:SetVertexColor(1, 1, 1, 0.025)

    r.value = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.value, 13)
    r.value:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.value:SetJustifyH("RIGHT")

    -- how much of the total comes from Paragon points
    r.note = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.note, 10)
    r.note:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
    r.note:SetJustifyH("RIGHT")

    r.label = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.label, 13)
    r.label:SetPoint("LEFT",  r,      "LEFT", 8, 0)
    r.label:SetPoint("RIGHT", r.note, "LEFT", -8, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)

    flow.rows[i] = r
    return r
end

-- flow.items: { header = true, title, count } or { label, value, note, alt }.
-- Splits them into COLS columns of about equal height and positions everything.
local function PlaceFlow()
    if not flow.content then return end
    local items = flow.items or {}
    local inner = flow.content:GetWidth() or 0
    if inner <= 0 then return end
    local colW = math.floor((inner - GAP * (COLS - 1)) / COLS)

    -- rows per group, so a short group can move to the next column in one piece
    local groupRows, current = {}, nil
    for i, it in ipairs(items) do
        if it.header then current = i; groupRows[i] = 0
        elseif current then groupRows[current] = groupRows[current] + 1 end
    end

    -- Greedy fill under a height cap; returns the item indexes that open a column.
    -- Groups of up to SMALL_GROUP rows are never split; longer ones continue in the
    -- next column under a "(continued)" header.
    local SMALL_GROUP = 10
    local function Breaks(cap)
        local breaks, cols, y = {}, 1, 0
        for i, it in ipairs(items) do
            local need
            if it.header then
                local whole = HDR_H + groupRows[i] * ROW_H
                need = (y > 0 and GROUP_GAP or 0) + ((groupRows[i] <= SMALL_GROUP) and whole or (HDR_H + ROW_H))
            else
                need = ROW_H
            end
            if y > 0 and y + need > cap then
                breaks[i], cols = true, cols + 1
                y = it.header and 0 or HDR_H   -- a split group repeats its header
            end
            y = y + (it.header and (y > 0 and GROUP_GAP or 0) + HDR_H or ROW_H)
        end
        return breaks, cols
    end
    -- smallest cap (in row steps) that fits everything in COLS columns
    local total = 0
    for _, it in ipairs(items) do total = total + (it.header and HDR_H + GROUP_GAP or ROW_H) end
    local cap = math.max(HDR_H + ROW_H, math.floor(total / COLS))
    local breaks, used = Breaks(cap)
    while used > COLS do
        cap = cap + ROW_H
        breaks, used = Breaks(cap)
    end

    local col, y, nHdr, nRow = 1, COL_PAD, 0, 0
    local heights = {}
    current = nil       -- the group being laid out (for "continued" headers)
    local function PutHeader(title, count, x)
        nHdr = nHdr + 1
        local h = GetHeader(nHdr)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", flow.content, "TOPLEFT", x, -y)
        h:SetWidth(colW)
        h.title:SetText(title)
        h.count:SetText(count or "")
        h:Show()
        y = y + HDR_H
    end
    for i, it in ipairs(items) do
        local isFirstInCol = (y == COL_PAD)
        if breaks[i] and col < COLS then
            heights[col] = y
            col, y = col + 1, COL_PAD
            isFirstInCol = true
            if not it.header and current then
                PutHeader(current.title .. HEX_DIM .. "  (continued)|r", nil, (col - 1) * (colW + GAP))
            end
        end
        local x = (col - 1) * (colW + GAP)
        if it.header then
            current = it
            if not isFirstInCol then y = y + GROUP_GAP end
            PutHeader(it.title, it.count, x)
        else
            nRow = nRow + 1
            local r = GetRow(nRow)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", flow.content, "TOPLEFT", x + 4, -y)
            r:SetWidth(colW - 8)
            r.label:SetText(it.label)
            r.value:SetText(it.value)
            r.note:SetText(it.note or "")
            if it.alt then r.alt:Show() else r.alt:Hide() end
            r:Show()
            y = y + ROW_H
        end
    end
    heights[col] = y
    for i = nHdr + 1, #flow.headers do flow.headers[i]:Hide() end
    for i = nRow + 1, #flow.rows do flow.rows[i]:Hide() end

    -- column backgrounds: all as tall as the tallest column
    local tallest = 0
    for c = 1, COLS do tallest = math.max(tallest, heights[c] or 0) end
    tallest = tallest + COL_PAD
    for c = 1, COLS do
        local bg = flow.cols[c]
        bg:ClearAllPoints()
        bg:SetPoint("TOPLEFT", flow.content, "TOPLEFT", (c - 1) * (colW + GAP), 0)
        bg:SetSize(colW, tallest)
    end
    flow.content:SetHeight(tallest)
    flow.scroll:UpdateScrollChildRect()
    local range = math.max(0, tallest - (flow.scroll:GetHeight() or 0))
    if flow.scroll:GetVerticalScroll() > range then flow.scroll:SetVerticalScroll(range) end

    if #items == 0 then flow.empty:Show() else flow.empty:Hide() end
end

local TILE_ORDER = { "nodes", "paragon", "points", "bonuses", "tokens", "orbs", "prestige", "stash", "builds" }
local HEADER_H   = 50   -- identity + play time

local function Layout()
    if not host then return end
    local w = host:GetWidth() or 0
    if w <= 0 then return end
    local inner = w - 2 * SIDE

    -- tiles: as many per row as fit at 130px or more, spread evenly over the rows
    local maxPerRow = math.max(3, math.min(#TILE_ORDER, math.floor((inner + 6) / 136)))
    local rows = math.ceil(#TILE_ORDER / maxPerRow)
    local perRow = math.ceil(#TILE_ORDER / rows)
    local tileW = math.floor((inner - 6 * (perRow - 1)) / perRow)
    local y = HEADER_H
    for i, key in ipairs(TILE_ORDER) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local t = tiles[key]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", host, "TOPLEFT", SIDE + col * (tileW + 6), -(y + row * (TILE_H + 6)))
        t:SetWidth(tileW)
    end
    local colsTop = y + rows * (TILE_H + 6) + 6

    flow.scroll:ClearAllPoints()
    flow.scroll:SetPoint("TOPLEFT",     host, "TOPLEFT",     SIDE, -colsTop)
    flow.scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -SIDE, 8)
    flow.content:SetWidth(inner)
    PlaceFlow()
end

-- ── account ──
local function FormatPlayTime(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%dd %dh %dm", math.floor(seconds / 86400),
        math.floor((seconds % 86400) / 3600), math.floor((seconds % 3600) / 60))
end

local function RefreshAccount()
    if not host then return end
    local name = UnitName("player") or "?"
    local className = UnitClass("player") or "?"
    local level = UnitLevel("player") or 0
    account.identity:SetText(name .. HEX_DIM .. "  ·  |r" .. className .. HEX_DIM .. "  ·  |r" .. "Level " .. level)
    if account.total then
        account.played:SetText(HEX_MUTED .. FormatPlayTime(account.total) .. " played|r"
            .. HEX_DIM .. "  ·  " .. FormatPlayTime(account.level) .. " this level|r")
    else
        account.played:SetText(HEX_DIM .. "Play time: waiting for the server…|r")
    end

    if PA._walletPrimed then
        tiles.tokens:SetValue(PA.prestigeTokens or 0)
        tiles.orbs:SetValue(PA.orbs or 0)
        tiles.prestige:SetValue(PA.prestigeLevel or 0)
    else
        tiles.tokens:SetValue("…"); tiles.orbs:SetValue("…"); tiles.prestige:SetValue("…")
    end

    local builds = ProjectAstralGemBuilds and ProjectAstralGemBuilds.builds or {}
    local nBuilds = 0
    for _ in pairs(builds) do nBuilds = nBuilds + 1 end
    tiles.builds:SetValue(nBuilds)

    local stash = PA.GemStash
    if stash and stash.IsLoaded and stash.IsLoaded() then
        local total, kinds = 0, 0
        for _, count in pairs(stash.GetStock and stash.GetStock() or {}) do
            count = tonumber(count) or 0
            if count > 0 then total, kinds = total + count, kinds + 1 end
        end
        -- the type count goes in the label: "619 · 319 types" didn't fit the tile
        tiles.stash:SetValue(total)
        tiles.stash.label:SetText(HEX_MUTED .. "Gem Stash|r" .. HEX_DIM .. "  ·  " .. kinds .. " types|r")
    else
        tiles.stash:SetValue("…")
    end
end

-- play time: ask the server once per session, without the chat line it prints
local playedEvent = CreateFrame("Frame")
playedEvent:RegisterEvent("TIME_PLAYED_MSG")
playedEvent:SetScript("OnEvent", function(_, _, total, level)
    account.total, account.level = total, level
    RefreshAccount()
end)
local playedAsked = false
local function AskPlayTime()
    if playedAsked or not RequestTimePlayed then return end
    playedAsked = true
    local orig = ChatFrame_DisplayTimePlayed
    if orig then
        ChatFrame_DisplayTimePlayed = function() end
        local restore, acc = CreateFrame("Frame"), 0
        restore:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt
            if acc > 3 then
                ChatFrame_DisplayTimePlayed = orig
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
    RequestTimePlayed()
end

local function Refresh()
    if not (host and host:IsVisible()) then return end
    RefreshAccount()
    local AT = PA.AT
    if not (AT and AT.NodeTotals) then return end

    local nodeTotals = AT.NodeTotals()
    local pgTotals   = AT.ParagonTotals and AT.ParagonTotals() or {}
    local meta       = AT.EffectMeta or {}
    local groups     = AT.SummaryGroups or {}

    local totals = {}
    for t, v in pairs(nodeTotals) do totals[t] = v end
    for t, v in pairs(pgTotals)   do totals[t] = (totals[t] or 0) + v end

    -- every group in order, then any bonus type no group lists under "Other"
    local placed = {}
    local list = {}
    for _, group in ipairs(groups) do
        for _, t in ipairs(group.types or {}) do placed[t] = true end
        list[#list + 1] = { name = group.name, types = group.types or {} }
    end
    local extra = {}
    for t in pairs(totals) do
        if not placed[t] then extra[#extra + 1] = t end
    end
    table.sort(extra)
    if #extra > 0 then list[#list + 1] = { name = "Other", types = extra } end

    local items, bonuses = {}, 0
    for _, group in ipairs(list) do
        local rows = {}
        for _, t in ipairs(group.types) do
            local v = totals[t]
            if v and v ~= 0 then
                local m = meta[t]
                local text = ValueText(m, v)
                local pg = pgTotals[t]
                local note
                if pg and pg ~= 0 then
                    note = HEX_DIM .. (nodeTotals[t] and ("incl. " .. ValueText(m, pg) .. " Paragon") or "Paragon") .. "|r"
                end
                rows[#rows + 1] = {
                    label = m and m.label or FriendlyLabel(t),
                    value = (text == "Unlocked" and HEX_GOLD or HEX_GOOD) .. text .. "|r",
                    note  = note,
                    alt   = (#rows % 2 == 1),
                }
            end
        end
        if #rows > 0 then
            local n = #rows
            items[#items + 1] = { header = true, title = group.name,
                count = HEX_DIM .. n .. (n == 1 and " bonus" or " bonuses") .. "|r" }
            for _, r in ipairs(rows) do items[#items + 1] = r end
            bonuses = bonuses + n
        end
    end
    flow.items = items
    PlaceFlow()

    local unlocked = 0
    for _ in pairs(AT.unlocked or {}) do unlocked = unlocked + 1 end
    local pg = (PA.Paragon and PA.Paragon.state) or {}
    tiles.nodes:SetValue(unlocked)
    tiles.paragon:SetValue(string.format("%d / %d", pg.level or 0, pg.max or 0))
    tiles.points:SetValue(pg.available or 0)
    tiles.bonuses:SetValue(bonuses)
end

local function BuildStatsTab(panel)
    host = panel

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID); ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    -- identity and play time
    account.identity = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(account.identity, 15)
    account.identity:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE + 2, -10)
    account.played = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(account.played, 11)
    account.played:SetPoint("TOPLEFT", account.identity, "BOTTOMLEFT", 0, -4)

    local treeBtn = UI.MakeButton(panel, "Open Astral Tree", {
        w = 140, h = 26, variant = "secondary",
        onClick = function() OpenTab("skills") end,
    })
    treeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, -10)

    -- tree, wallet and account-wide tiles
    tiles.nodes    = MakeTile(panel, "Nodes", "Interface\\Icons\\Spell_Nature_Starfall", UI.Tinted({ 0.40, 0.78, 1.00 }), "skills", "Open the Astral Tree")
    tiles.paragon  = MakeTile(panel, "Paragon", "Interface\\Icons\\Spell_Holy_PowerInfusion", { 1.00, 0.84, 0.29 }, "paragon", "Open Paragon")
    tiles.points   = MakeTile(panel, "Unspent points", "Interface\\Icons\\Spell_ChargePositive", { 0.35, 0.90, 0.70 })
    tiles.bonuses  = MakeTile(panel, "Bonuses", "Interface\\Icons\\Spell_Holy_WordFortitude", UI.Tinted({ 0.80, 0.55, 1.00 }))
    tiles.tokens   = MakeTile(panel, "Tokens", UI.Icon.tokens, { 0.35, 0.90, 0.70 }, "store", "Spend Tokens in the Store")
    tiles.orbs     = MakeTile(panel, "Orbs of Destiny", UI.Icon.orbs, { 0.55, 0.85, 1.00 })
    tiles.prestige = MakeTile(panel, "Prestige", UI.Icon.prestige, { 1.00, 0.85, 0.35 })
    tiles.stash    = MakeTile(panel, "Gem Stash", "Interface\\Icons\\INV_Misc_Bag_08", { 0.45, 0.90, 0.70 }, "gem_stash", "Open the Gem Stash (shared by your characters)")
    tiles.builds   = MakeTile(panel, "Gem Builds", "Interface\\Icons\\INV_Misc_Note_01", UI.Tinted({ 0.78, 0.70, 1.00 }), "gembuilds", "Open Gem Builds (shared by your characters)")

    -- bonus area: scrolls only when the flowed columns don't fit
    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, (flow.content:GetHeight() or 0) - (self:GetHeight() or 0))
        if range <= 0 then
            -- nothing to scroll here: let the hub page scroll instead
            local mf = PA.mainFrame
            if mf and mf.ScrollBy then mf:ScrollBy(-delta * 90) end
            return
        end
        self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * 48)))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    flow.scroll, flow.content = scroll, content
    for c = 1, COLS do
        flow.cols[c] = CreateFrame("Frame", nil, content)
        NavyBox(flow.cols[c], UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
    end
    flow.empty = content:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(flow.empty, 12)
    flow.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 14, -14)
    flow.empty:SetText(HEX_DIM .. "No bonuses yet: unlock nodes in the Astral Tree or spend Paragon points.|r")

    panel:SetScript("OnSizeChanged", Layout)
    Layout()

    local acc = 0
    panel:SetScript("OnShow", function()
        Layout()
        local AT = PA.AT
        if AT then
            if AT.RequestParagonStateAIO then AT.RequestParagonStateAIO() end
            -- the tree only loads its state when the Skills tab opens; fetch it if
            -- the player came here first
            if not next(AT.unlocked or {}) and AT.RequestInitialStateAIO then
                AT.RequestInitialStateAIO()
            end
        end
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        AskPlayTime()
        acc = 0
        Refresh()
    end)

    -- cheap fallback refresh while visible (one pass over unlocked nodes a second)
    panel:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 1 then
            acc = 0
            Refresh()
        end
    end)
end

-- live updates: node unlock/remove/reset, Paragon, wallet and stash changes
-- (Skilltree.lua loads first)
if PA.AT and PA.AT.OnStatsChanged then PA.AT.OnStatsChanged(Refresh) end
if PA.OnTokensChanged then PA:OnTokensChanged(function() Refresh() end) end

local function ToggleStats()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "astral_stats" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("astral_stats")
    end
end

PA:RegisterModule("astral_stats", "Astral Stats", ToggleStats, {
    subtitle = "Your character, wallet and every bonus from the Astral Tree and Paragon.",
})
PA:RegisterTabContent("astral_stats", BuildStatsTab)
