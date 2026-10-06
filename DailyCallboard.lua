
local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local M = {}
M.slots        = {}
M.tokensToday  = 0
M.softCap      = 0
M.overCapPct   = 100
M.activeCount  = 0
M.maxAccept    = 3
M.slotCount    = 15
M.resetEpoch   = 0
M.rangeYards   = 12
M.boardOpen    = false
M.filter       = { category = 0, hideCd = false, sortBy = "tokens" }

local frame, gridFrame, filterPanel
local tiles = {}

local CAT_LABEL = {
    [1] = "Slay",  [2] = "Rare",  [3] = "Elite", [4] = "Skin",
    [5] = "Herb",  [6] = "Mine",  [7] = "Fish",  [8] = "Cloth",
    [9] = "Craft", [10] = "Quests", [11] = "LFG",
}

local ZONE_NAMES = {
    [1]  = "Elwynn Forest",       [2]  = "Westfall",
    [3]  = "Duskwood",            [4]  = "Redridge Mountains",
    [5]  = "Stranglethorn Vale",  [6]  = "Swamp of Sorrows",
    [7]  = "Blasted Lands",       [8]  = "Burning Steppes",
    [9]  = "Searing Gorge",       [10] = "Badlands",
    [11] = "Loch Modan",          [12] = "Dun Morogh",
    [13] = "Wetlands",            [14] = "Arathi Highlands",
    [15] = "Hillsbrad Foothills", [16] = "Alterac Mountains",
    [17] = "Silverpine Forest",   [18] = "Tirisfal Glades",
    [19] = "Western Plaguelands", [20] = "Eastern Plaguelands",
    [30] = "Durotar",             [31] = "The Barrens",
    [32] = "Mulgore",             [33] = "Stonetalon Mountains",
    [34] = "Ashenvale",           [35] = "Darkshore",
    [36] = "Teldrassil",          [37] = "Felwood",
    [38] = "Winterspring",        [39] = "Moonglade",
    [40] = "Azshara",             [41] = "Dustwallow Marsh",
    [42] = "Thousand Needles",    [43] = "Tanaris",
    [44] = "Un'Goro Crater",      [45] = "Silithus",
    [46] = "Desolace",             [47] = "Feralas",
    [99] = "Eastern Kingdoms",   [100] = "Kalimdor",
    [201] = "Shadowfang Keep",       [202] = "The Stockade",
    [203] = "The Deadmines",         [204] = "Wailing Caverns",
    [205] = "Razorfen Kraul",        [206] = "Blackfathom Deeps",
    [207] = "Uldaman",               [208] = "Gnomeregan",
    [209] = "Sunken Temple",         [210] = "Razorfen Downs",
    [211] = "Scarlet Monastery",     [212] = "Zul'Farrak",
    [213] = "Blackrock Spire",       [214] = "Blackrock Depths",
    [215] = "Scholomance",           [216] = "Stratholme",
    [217] = "Maraudon",              [218] = "Ragefire Chasm",
    [219] = "Dire Maul",
}

local PROFESSION_NAMES = {
    [129] = "First Aid",      [164] = "Blacksmithing",
    [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism",      [185] = "Cooking",
    [186] = "Mining",         [197] = "Tailoring",
    [202] = "Engineering",    [333] = "Enchanting",
    [356] = "Fishing",        [393] = "Skinning",
    [755] = "Jewelcrafting",  [773] = "Inscription",
}
local CRAFT_PHANTOM_CRAFT    = 5020024
local CRAFT_PHANTOM_COOKING  = 5020025
local CRAFT_PHANTOM_FIRSTAID = 5020026
local function professionLabelFor(slot)
    local skill = slot.skill or 0
    if PROFESSION_NAMES[skill] then return PROFESSION_NAMES[skill] end
    if slot.cat == 9 then
        if slot.reqNpc == CRAFT_PHANTOM_COOKING  then return "Cooking"   end
        if slot.reqNpc == CRAFT_PHANTOM_FIRSTAID then return "First Aid" end
        return "Crafting"
    end
    return nil
end
local function isProfessionCategory(cat)
    return cat == 4 or cat == 5 or cat == 6 or cat == 7 or cat == 9
end
local CAT_COLOR = {
    [1]  = { 0.92, 0.62, 0.55 },
    [2]  = { 0.92, 0.55, 0.92 },
    [3]  = { 0.65, 0.55, 0.92 },
    [4]  = { 0.82, 0.66, 0.55 },
    [5]  = { 0.55, 0.92, 0.55 },
    [6]  = { 0.66, 0.66, 0.66 },
    [7]  = { 0.55, 0.82, 0.92 },
    [8]  = { 0.92, 0.92, 0.92 },
    [9]  = { 0.92, 0.82, 0.55 },
    [10] = { 0.65, 0.82, 1.00 },
    [11] = { 0.85, 0.55, 1.00 },
}

local function send(cmd) SendChatMessage("." .. cmd, "SAY") end

local function DelayedRequestState(ms)
    if frame and frame.loadingOverlay then
        frame.loadingOverlay:Show()
    end
    local delay = (ms or 250) / 1000
    local acc = 0
    local f = CreateFrame("Frame")
    f:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        if acc >= delay then
            self:SetScript("OnUpdate", nil)
            if _G.AIO and _G.AIO.Handle then
                _G.AIO.Handle("AstralDailyCallboardServer", "RequestState")
            end
        end
    end)
end

function M:Accept(idx)
    send("dailycallboard accept " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "accept" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(280)
end

function M:TurnIn(idx)
    send("dailycallboard turnin " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "turnin" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(400)
end

function M:Abandon(idx)
    send("dailycallboard abandon " .. tostring(idx))
    local s = M.slots[idx]
    if s then s._pending = "abandon" end
    if frame and frame:IsShown() then M:_renderGrid() end
    DelayedRequestState(280)
end

function M:Refresh()
    send("dailycallboard refresh")
    DelayedRequestState(280)
end

function M:CloseServer()
    send("dailycallboard close")
end

function M:RequestState()
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralDailyCallboardServer", "RequestState")
    end
end


-- ── Window (unified Astral look) ───────────────────────────────────
-- Navy window with a gold edge and a gold-barred title; a gold status bar with
-- the active quests, today's tokens against the soft cap (as a fill) and the reset
-- timer; filter chips; a dark-grey list whose accepted quests get the gold tint.
-- Blues go through UI.Tint (Settings > Global UI color). Colours that must survive
-- Theme.lua's vivid-text pass are inline |c codes; navy frames set __paBackdrop.
local FRAME_W, FRAME_H = 980, 720
local TILE_H = 64
local TILE_GAP = 4
local SIDE = 16
local SOLID = "Interface\\Buttons\\WHITE8X8"

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"

local filterChips, sortChip = {}, nil
local statusBar

local function Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local function makeFrame()
    if frame then return end
    frame = CreateFrame("Frame", "ProjectAstralDailyCallboardFrame", UIParent)
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop",  frame.StopMovingOrSizing)
    UI.AstralBackdrop(frame, { thin = true })
    frame:SetBackdropColor(UI.Tint(0.031, 0.047, 0.133, 0.97))
    frame:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)
    frame.__paBackdrop = true

    -- title: gold glow, gold bar, white title, dim subtitle
    local glow = frame:CreateTexture(nil, "ARTWORK"); glow:SetTexture(SOLID)
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    glow:SetHeight(44)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)
    local accent = frame:CreateTexture(nil, "OVERLAY"); accent:SetTexture(SOLID)
    accent:SetVertexColor(0.886, 0.753, 0.384, 1); accent:SetSize(3, 18)
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -18)
    local title = frame:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(title, 16)
    title:SetPoint("LEFT", accent, "RIGHT", 9, 0)
    title:SetText("Daily Callboard")
    local sub = frame:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(sub, 12)
    sub:SetPoint("LEFT", title, "RIGHT", 12, -1)
    sub:SetText(HEX_DIM .. "Daily tasks: fresh picks after every turn-in.|r")
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    UI.CosmicCloseButton(close)
    close:SetScript("OnClick", function()
        if frame then frame:Hide() end
        M:CloseServer()
    end)
    frame.closeBtn = close

    -- status bar: active quests · tokens today vs soft cap (fill) · reset timer
    statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetHeight(38)
    statusBar:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -50)
    statusBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -50)
    UI.AstralBackdrop(statusBar, { thin = true })
    statusBar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
    statusBar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    statusBar.__paBackdrop = true
    statusBar.fill = statusBar:CreateTexture(nil, "ARTWORK"); statusBar.fill:SetTexture(SOLID)
    statusBar.fill:SetPoint("TOPLEFT", statusBar, "TOPLEFT", 4, -4)
    statusBar.fill:SetPoint("BOTTOMLEFT", statusBar, "BOTTOMLEFT", 4, 4)
    statusBar.fill:SetWidth(1)
    statusBar.fill:SetVertexColor(0.886, 0.753, 0.384, 0.30)
    statusBar.active = statusBar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(statusBar.active, 13)
    statusBar.active:SetPoint("LEFT", statusBar, "LEFT", 12, 0)
    statusBar.cap = statusBar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(statusBar.cap, 13)
    statusBar.cap:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    statusBar.reset = statusBar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(statusBar.reset, 13)
    statusBar.reset:SetPoint("RIGHT", statusBar, "RIGHT", -12, 0)
    statusBar:EnableMouse(true)
    statusBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Daily Callboard", 1, 1, 1)
        GameTooltip:AddLine(("You can have %d callboard quests active at once."):format(M.maxAccept or 3), 0.86, 0.87, 0.94, true)
        GameTooltip:AddLine("Past today's token soft cap, quests still pay, at a reduced rate.", 0.86, 0.87, 0.94, true)
        GameTooltip:Show()
    end)
    statusBar:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- filter chips + sort
    filterPanel = CreateFrame("Frame", nil, frame)
    filterPanel:SetPoint("TOPLEFT",  statusBar, "BOTTOMLEFT",  0, -10)
    filterPanel:SetPoint("TOPRIGHT", statusBar, "BOTTOMRIGHT", 0, -10)
    filterPanel:SetHeight(24)
    M:_buildFilterButtons()

    -- list: dark grey panel (the gold rows read warm on it)
    local listPanel = CreateFrame("Frame", nil, frame)
    listPanel:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -10)
    listPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE, SIDE)
    listPanel:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    listPanel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)
    listPanel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    listPanel.__paBackdrop = true

    local scroll = CreateFrame("ScrollFrame",
                               "ProjectAstralDailyCallboardScroll",
                               listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",     6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -26, 6)

    gridFrame = CreateFrame("Frame", nil, scroll)
    gridFrame:SetWidth(FRAME_W - 2 * SIDE - 36)
    gridFrame:SetHeight(1)
    scroll:SetScrollChild(gridFrame)

    gridFrame.empty = gridFrame:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(gridFrame.empty, 13)
    gridFrame.empty:SetPoint("TOP", gridFrame, "TOP", 0, -30)
    gridFrame.empty:SetText(HEX_MUTED .. "No callboard quests in this filter.|r")
    gridFrame.empty:Hide()

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local step = (TILE_H + TILE_GAP) * 1.5
        local maxScroll = math.max(0, self:GetVerticalScrollRange())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * step)))
    end)

    if UI and UI.MakeLoadingOverlay then
        frame.loadingOverlay = UI.MakeLoadingOverlay(frame,
            { text = "Loading callboard" .. string.char(0xE2, 0x80, 0xA6) })
    end

    if UI.SkinTree then UI.SkinTree(frame) end
end

function M:_buildFilterButtons()
    local labels = {
        { 0,         "All" },
        { "SLAY",    "Slay" },
        { "PROF",    "Gather" },
        { 9,         "Craft" },
        { 10,        "Quests" },
        { "DUNGEON", "Dungeon" },
    }
    local function Paint()
        for _, chip in ipairs(filterChips) do chip:SetActive(chip.cat == M.filter.category) end
    end
    local prev
    for _, row in ipairs(labels) do
        local cat, label = row[1], row[2]
        local chip = UI.MakeFilterChip(filterPanel, math.max(64, string.len(label) * 8 + 26), label, function()
            M.filter.category = cat
            Paint()
            M:_renderGrid()
        end)
        chip.cat = cat
        chip.__paBackdrop = true
        if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else chip:SetPoint("LEFT", filterPanel, "LEFT", 0, 0) end
        prev = chip
        filterChips[#filterChips + 1] = chip
    end

    sortChip = UI.MakeFilterChip(filterPanel, 132, "Sort: Tokens", function(self)
        if M.filter.sortBy == "tokens" then
            M.filter.sortBy = "level"
            self.text:SetText("Sort: Level")
        else
            M.filter.sortBy = "tokens"
            self.text:SetText("Sort: Tokens")
        end
        M:_renderGrid()
    end)
    sortChip.__paBackdrop = true
    sortChip:SetPoint("RIGHT", filterPanel, "RIGHT", 0, 0)
    Paint()
end

local function makeTile(parent, i)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(TILE_H)

    -- alternating rows; accepted quests get the gold tint and gold bar
    t.alt = t:CreateTexture(nil, "BACKGROUND"); t.alt:SetTexture(SOLID); t.alt:SetAllPoints(t)
    t.alt:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.025 or 0)
    t.goldBg = t:CreateTexture(nil, "BACKGROUND", nil, 1); t.goldBg:SetTexture(SOLID); t.goldBg:SetAllPoints(t)
    t.goldBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.16, 0.94, 0.82, 0.43, 0)
    local divider = t:CreateTexture(nil, "BORDER"); divider:SetTexture(SOLID)
    divider:SetVertexColor(1, 1, 1, 0.06)
    divider:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0); divider:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)

    -- category bar (gold when the quest is accepted)
    t.catBar = t:CreateTexture(nil, "ARTWORK"); t.catBar:SetTexture(SOLID)
    t.catBar:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    t.catBar:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 0)
    t.catBar:SetWidth(3)

    -- right side: action buttons, then the reward
    t.goldBtn = UI.MakeButton(t, "Accept", { w = 112, h = 26, variant = "gold" })
    t.goldBtn:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    t.abandonBtn = UI.MakeButton(t, "Abandon", { w = 112, h = 26, variant = "danger" })
    t.abandonBtn:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    -- "Slots full" explains itself on hover (hooked once: tiles are reused)
    for _, b in ipairs({ t.goldBtn, t.abandonBtn }) do
        b:HookScript("OnEnter", function(self)
            if not self._fullTip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Slots full", 1, 1, 1)
            GameTooltip:AddLine(("You already have %d callboard quests active. Finish or abandon one first.")
                :format(M.activeCount or 0), 0.86, 0.87, 0.94, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function(self) if self._fullTip then GameTooltip:Hide() end end)
    end

    t.tokens = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.tokens, 15)
    t.tokens:SetPoint("BOTTOMRIGHT", t, "RIGHT", -136, 1)
    t.tokens:SetJustifyH("RIGHT")
    t.lvl = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.lvl, 11)
    t.lvl:SetPoint("TOPRIGHT", t, "RIGHT", -136, -3)
    t.lvl:SetJustifyH("RIGHT")

    -- left side: category · profession / state, title, objective
    t.catTag = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.catTag, 11)
    t.catTag:SetPoint("TOPLEFT", t, "TOPLEFT", 14, -8)
    t.catTag:SetPoint("RIGHT", t, "RIGHT", -250, 0)
    t.catTag:SetJustifyH("LEFT"); t.catTag:SetWordWrap(false)

    t.title = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.title, 14)
    t.title:SetPoint("TOPLEFT", t, "TOPLEFT", 14, -23)
    t.title:SetPoint("RIGHT", t, "RIGHT", -250, 0)
    t.title:SetJustifyH("LEFT"); t.title:SetWordWrap(false)

    t.objective = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.objective, 12)
    t.objective:SetPoint("TOPLEFT", t, "TOPLEFT", 14, -42)
    t.objective:SetPoint("RIGHT", t, "RIGHT", -250, 0)
    t.objective:SetJustifyH("LEFT"); t.objective:SetWordWrap(false)
    return t
end

local function statusButtonState(slot)
    if slot._pending then
        if     slot._pending == "accept"  then return "Accepting...", false, "accept"
        elseif slot._pending == "turnin"  then return "Turning in...", false, "turnin"
        elseif slot._pending == "abandon" then return "Abandoning...", false, "abandon" end
    end
    if slot.status == 1 then
        if slot.serverComplete then
            return "Get Reward", true, "turnin"
        end
        return "Abandon", true, "abandon"
    end
    if slot.status == 0 and slot.qid and slot.qid > 0 then
        return "Accept", true, "accept"
    end
    return "-", false, "accept"
end

function M:_renderGrid()
    if not gridFrame then return end

    local list = {}
    local fc = M.filter.category
    local function passesFilter(s)
        if fc == 0 then return true end
        if fc == "SLAY" then
            return s.cat == 1 or s.cat == 3
        end
        if fc == "PROF" then
            return s.cat == 4 or s.cat == 5 or s.cat == 6 or s.cat == 7
        end
        if fc == "DUNGEON" then
            return s.cat == 2 or s.cat == 11
        end
        return s.cat == fc
    end
    for _, s in pairs(M.slots) do
        local hasQuest = s.qid and s.qid > 0
        if hasQuest and passesFilter(s) then
            table.insert(list, s)
        end
    end
    table.sort(list, function(a, b)
        if M.filter.sortBy == "level" then
            if a.lvlMin ~= b.lvlMin then return a.lvlMin < b.lvlMin end
            return a.tokens > b.tokens
        end
        if a.tokens ~= b.tokens then return a.tokens > b.tokens end
        return a.idx < b.idx
    end)

    for _, t in ipairs(tiles) do t:Hide() end

    for i, slot in ipairs(list) do
        local t = tiles[i]
        if not t then
            t = makeTile(gridFrame, i)
            tiles[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT",  gridFrame, "TOPLEFT",  0, -(i - 1) * (TILE_H + TILE_GAP))
        t:SetPoint("TOPRIGHT", gridFrame, "TOPRIGHT", 0, -(i - 1) * (TILE_H + TILE_GAP))

        local accepted = slot.status == 1
        local col = CAT_COLOR[slot.cat] or { 0.55, 0.55, 0.55 }
        if accepted then
            t.goldBg:Show()
            t.catBar:SetVertexColor(0.886, 0.753, 0.384, 1)
        else
            t.goldBg:Hide()
            t.catBar:SetVertexColor(col[1], col[2], col[3], 0.95)
        end

        local tag = Hex(col) .. (CAT_LABEL[slot.cat] or "?") .. "|r"
        local profLabel = isProfessionCategory(slot.cat) and professionLabelFor(slot)
        if profLabel then tag = tag .. HEX_DIM .. "  ·  " .. profLabel .. "|r" end
        if accepted then
            tag = tag .. HEX_DIM .. "  ·  |r" .. (slot.serverComplete and (HEX_GOOD .. "Ready to turn in|r")
                                                  or (HEX_GOLD .. "In progress|r"))
        end
        t.catTag:SetText(tag)
        t.title:SetText("|cffffffff" .. (slot.title or "") .. "|r")
        t.objective:SetText(HEX_MUTED .. (slot.objective or "") .. "|r")

        t.tokens:SetText(HEX_GOLD .. (slot.tokens or 0) .. "|r" .. HEX_MUTED .. " Tokens|r")
        t.lvl:SetText(HEX_DIM .. ("Level %d-%d"):format(slot.lvlMin or 0, slot.lvlMax or 0) .. "|r")

        local label, enabled, action = statusButtonState(slot)
        local full = action == "accept" and slot.status == 0
           and M.maxAccept and M.activeCount
           and M.activeCount >= M.maxAccept
           and not slot._pending
        if full then enabled = false; label = "Slots full" end

        -- Accept / Get Reward: gold; Abandon: red
        local btn, other = t.goldBtn, t.abandonBtn
        if action == "abandon" then btn, other = t.abandonBtn, t.goldBtn end
        other:Hide()
        btn:Show()
        btn:SetLabel(label)
        btn:SetDisabledLook(not enabled)
        btn:SetScript("OnClick", function()
            if not enabled then return end
            if     action == "accept"  then M:Accept(slot.idx)
            elseif action == "abandon" then M:Abandon(slot.idx)
            elseif action == "turnin"  then M:TurnIn(slot.idx) end
        end)
        btn._fullTip = full

        t:Show()
    end

    if #list == 0 then gridFrame.empty:Show() else gridFrame.empty:Hide() end
    local total = math.max(1, #list) * (TILE_H + TILE_GAP)
    gridFrame:SetHeight(total)
end

local function paintFooter()
    if not statusBar then return end
    local secLeft = M.resetEpoch - time()
    local h = math.max(0, math.floor(secLeft / 3600))
    local m = math.max(0, math.floor((secLeft % 3600) / 60))

    local active, maxA = M.activeCount or 0, M.maxAccept or 3
    statusBar.active:SetText(HEX_MUTED .. "Active quests  |r" .. (active >= maxA and HEX_WARN or HEX_GOLD)
        .. active .. " / " .. maxA .. "|r")

    local frac = 0
    if M.softCap and M.softCap > 0 then
        frac = math.min(1, (M.tokensToday or 0) / M.softCap)
        local pct = math.floor(((M.tokensToday or 0) / M.softCap) * 100)
        statusBar.cap:SetText(HEX_MUTED .. "Tokens today  |r" .. HEX_GOLD .. (M.tokensToday or 0) .. " / " .. M.softCap
            .. "|r" .. HEX_DIM .. "  (" .. pct .. "% of the soft cap)|r")
    else
        statusBar.cap:SetText(HEX_DIM .. "Soft cap unavailable|r")
    end
    statusBar.fill:SetWidth(math.max(1, ((statusBar:GetWidth() or 0) - 8) * frac))
    if frac >= 1 then statusBar.fill:SetVertexColor(1.00, 0.80, 0.40, 0.30)
    else statusBar.fill:SetVertexColor(0.886, 0.753, 0.384, 0.30) end

    statusBar.reset:SetText(HEX_MUTED .. "Resets in  |r" .. HEX_GOLD .. ("%dh %dm"):format(h, m) .. "|r")
end

function M:Show()
    makeFrame()
    paintFooter()
    M:_renderGrid()
    frame:Show()
end

local function ApplyState(payload)
    if not payload then return end
    M.tokensToday = payload.tokensToday or 0
    M.softCap     = payload.softCap     or 0
    M.overCapPct  = payload.overCapPct  or 100
    M.activeCount = payload.activeCount or 0
    M.maxAccept   = payload.maxAccept   or 3
    M.slotCount   = payload.slotCount   or 15
    M.resetEpoch  = payload.resetEpoch  or 0
    M.rangeYards  = payload.rangeYards  or 12

    M.slots = {}
    for _, s in ipairs(payload.slots or {}) do
        s.cdExpires = (s.cdSec and s.cdSec > 0) and (GetTime() + s.cdSec) or 0
        s._pending = nil
        M.slots[s.idx] = s
    end

    if frame and frame:IsShown() then
        M:_renderGrid()
        paintFooter()
    end
    if frame and frame.loadingOverlay then
        frame.loadingOverlay:Hide()
    end
end

local function RegisterDCHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local Client = _G.AIO.AddHandlers("AstralDailyCallboard", {})

    Client.OpenFrame = function(_, goGuid, rangeYards)
        M.boardOpen  = true
        M.rangeYards = tonumber(rangeYards) or M.rangeYards
        makeFrame()
        frame:Show()
        M:_renderGrid()
        paintFooter()
        if frame.loadingOverlay then frame.loadingOverlay:Show() end
        DelayedRequestState(350)
    end

    Client.State = function(_, payload) ApplyState(payload) end

    return true
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function(self)
    if RegisterDCHandlers() then
        self:UnregisterAllEvents()
    end
end)

local ticker = CreateFrame("Frame")
ticker.acc = 0
ticker:SetScript("OnUpdate", function(self, elapsed)
    self.acc = self.acc + elapsed
    if self.acc < 1.0 then return end
    self.acc = 0
    if frame and frame:IsShown() then
        M:_renderGrid()
        paintFooter()
    end
end)

function M:Open()
    makeFrame()
    frame:Show()
    M:_renderGrid()
    paintFooter()
    M:RequestState()
end

PA.DailyCallboard = M
