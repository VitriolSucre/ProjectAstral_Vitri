
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

-- Ember Warden window (server: lua_scripts/Server/astral_bridge/mythicplus/mythic_plus_warden.lua).
-- Opened only by the server when the player talks to an Ember Warden, closed by the server once
-- the player leaves gossip range. Page 1: the levels with this week's affixes and a start button.
-- Page 2: every affix, and whether (from which level) it is active this week. This file only
-- displays; the server re-checks range, leader and unlock on every start.

local FRAME_W, FRAME_H = 660, 480
local TAB_W            = 150
local CONTENT_W        = FRAME_W - TAB_W - 36 - 18 - 28   -- minus tab column, margins, scrollbar
local LEVEL_ROW_H      = 34
local ICON_SIZE        = 20
local ICON_STEP        = 22
local UNKNOWN_ICON     = "Interface\\Icons\\INV_Misc_QuestionMark"
local POPUP            = "PA_MYTHIC_PLUS_START"

-- Affix icons: PA.MythicPlusAffixIcons (MythicPlusHUD.lua, loaded before this file); the spell icon
-- from Spell.dbc is the fallback.
local AFFIX_ICONS = PA.MythicPlusAffixIcons or {}

local S = { data = nil, openedAt = 0, closingFromServer = false, tick = 0 }
local W = {}

StaticPopupDialogs[POPUP] = {
    text         = "%s",
    button1      = "Start",
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

local function Tint(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

local function Pct(v)
    return (math.floor(v) == v) and ("%d%%"):format(v) or ("%.1f%%"):format(v)
end

local function Remaining(secs)
    secs = math.max(0, math.floor(secs))
    local d, h, m = math.floor(secs / 86400), math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(math.max(1, m))
end

local function AffixById(id)
    for _, a in ipairs(S.data and S.data.affixes or {}) do
        if a.id == id then return a end
    end
end

local function AffixIcon(a)
    if a and AFFIX_ICONS[a.id] then return AFFIX_ICONS[a.id] end
    local _, _, icon = GetSpellInfo(a and a.spell or 0)
    return icon or UNKNOWN_ICON
end

local function ShowAffixTip(owner, a)
    if not a then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(a.name, UI.Color.textHi[1], UI.Color.textHi[2], UI.Color.textHi[3])
    GameTooltip:AddLine(a.description, 1, 1, 1, true)
    GameTooltip:Show()
end

local function HideTip() GameTooltip:Hide() end

-- Seconds until the weekly order changes (the earliest raid reset), or nil.
local function SecondsToReset()
    local d = S.data
    if not d then return nil end
    local soonest
    for _, m in ipairs(d.maps or {}) do
        if m.resetsAt and m.resetsAt > 0 and (not soonest or m.resetsAt < soonest) then soonest = m.resetsAt end
    end
    if not soonest then return nil end
    return soonest - (d.now + (GetTime() - S.openedAt))
end

local function UnlockText(m)
    local name = m.unlockAchievement > 0 and select(2, GetAchievementInfo(m.unlockAchievement))
    if name then return ("Earn the achievement \"%s\" to unlock Mythic+ 1."):format(name) end
    return "Defeat the final boss on Mythic difficulty to unlock Mythic+ 1."
end

-- The level at which each affix joins this week, per raid: [affixId] = level.
local function FirstLevels(m)
    local first = {}
    for level = 1, m.cap do
        for _, id in ipairs(m.levels[level] or {}) do
            if not first[id] then first[id] = level end
        end
    end
    return first
end

local function HasSchedule(m)
    return m.resetsAt and m.resetsAt > 0
end

-- ---------------------------------------------------------------------
-- Start page
-- ---------------------------------------------------------------------

local function ConfirmStart(mapId, level, raidName)
    StaticPopupDialogs[POPUP].OnAccept = function()
        if not (W.frame and W.frame:IsShown()) then return end
        AIO.Handle("AstralMythicPlusWardenServer", "Start", mapId, level)
    end
    local what = raidName and ("Mythic+ %d (%s)"):format(level, raidName) or ("Mythic+ %d"):format(level)
    StaticPopup_Show(POPUP, ("Start %s?\nYour group will be moved into a new Mythic+ instance."):format(what))
end

local function LevelRowTip(row)
    local info = row.info
    if not info then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(("Mythic+ %d"):format(info.level), 1, 1, 1)
    GameTooltip:AddLine(("+%s health, +%s damage for every enemy"):format(Pct(info.health), Pct(info.damage)),
        UI.Color.textPrimary[1], UI.Color.textPrimary[2], UI.Color.textPrimary[3], true)
    if info.reason then
        GameTooltip:AddLine(info.reason, UI.Color.textBad[1], UI.Color.textBad[2], UI.Color.textBad[3], true)
    end
    GameTooltip:Show()
end

local function MakeLevelRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(CONTENT_W, LEVEL_ROW_H)
    r:EnableMouse(true)
    r:SetScript("OnEnter", LevelRowTip)
    r:SetScript("OnLeave", HideTip)
    UI.MakeRowChrome(r, {})

    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.level:SetPoint("TOPLEFT", r, "TOPLEFT", 10, -4)
    r.scaling = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.scaling:SetPoint("TOPLEFT", r.level, "BOTTOMLEFT", 0, -2)
    Tint(r.scaling, UI.Nav.muted)

    r.icons = {}
    r.noAffix = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.noAffix:SetPoint("LEFT", r, "LEFT", 128, 0)

    r.btn = UI.MakeButton(r, "Start", { w = 64, h = 22, onClick = function(self)
        ConfirmStart(self.mapId, self.level, self.raidName)
    end })
    r.btn:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.locked = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.locked:SetPoint("RIGHT", r, "RIGHT", -14, 0)
    r.locked:SetText("Locked")
    return r
end

local function RowIcon(r, i)
    local ic = r.icons[i]
    if ic then return ic end
    ic = UI.MakeIconFrame(r, { size = ICON_SIZE })
    ic:SetPoint("LEFT", r, "LEFT", 128 + (i - 1) * ICON_STEP, 0)
    ic:EnableMouse(true)
    ic:SetScript("OnEnter", function(self) ShowAffixTip(self, self.affix) end)
    ic:SetScript("OnLeave", HideTip)
    r.icons[i] = ic
    return ic
end

local function Acquire(pool, make, parent)
    pool.used = pool.used + 1
    local item = pool[pool.used]
    if not item then
        item = make(parent)
        pool[pool.used] = item
    end
    item:Show()
    return item
end

local function ResetPool(pool)
    for _, item in ipairs(pool) do item:Hide() end
    pool.used = 0
end

local function MakeText(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(CONTENT_W - 12)
    fs:SetJustifyH("LEFT")
    return fs
end

local function MakeMapHeader(parent)
    local h = UI.MakeSectionLabel(parent, "")
    h:SetWidth(CONTENT_W)
    h.best = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.best:SetPoint("RIGHT", h, "RIGHT", 0, 1)
    if h.line then
        h.line:ClearAllPoints()
        h.line:SetPoint("LEFT", h.label, "RIGHT", 10, 0)
        h.line:SetPoint("RIGHT", h.best, "LEFT", -10, 0)
    end
    return h
end

local function RenderStart()
    local d, P = S.data, W.start
    ResetPool(P.headers)
    ResetPool(P.texts)
    ResetPool(P.rows)

    local y = -4
    local function PlaceText(text, color)
        local fs = Acquire(P.texts, MakeText, P.child)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", P.child, "TOPLEFT", 6, y)
        fs:SetText(text)
        Tint(fs, color)
        y = y - fs:GetStringHeight() - 10
    end

    if not d.enabled then
        PlaceText("Mythic+ is not available right now.", UI.Color.textBad)
    end

    local multi = #d.maps > 1
    for _, m in ipairs(d.maps) do
        y = y - 14
        local h = Acquire(P.headers, MakeMapHeader, P.child)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", P.child, "TOPLEFT", 0, y)
        h:SetText(m.name)
        h.best:SetText(m.best > 0 and ("Your best: " .. Colored(UI.Color.textHi, "Mythic+ " .. m.best))
            or Colored(UI.Nav.muted, "No Mythic+ cleared yet"))
        y = y - 24

        if d.enabled and m.maxStart == 0 then PlaceText(UnlockText(m), UI.Color.textWarn) end
        if not HasSchedule(m) and not d.perRun then
            PlaceText("This week's affixes are not available yet.", UI.Nav.muted)
        end

        for level = 1, m.cap do
            local r = Acquire(P.rows, MakeLevelRow, P.child)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", P.child, "TOPLEFT", 0, y)
            local unlocked = d.enabled and level <= m.maxStart
            r.level:SetText(("Mythic+ %d"):format(level))
            Tint(r.level, unlocked and UI.Color.textHi or UI.Nav.muted)
            local health, damage = d.healthPct * level, d.damagePct * level
            r.scaling:SetText(("+%s HP / +%s dmg"):format(Pct(health), Pct(damage)))

            local ids = m.levels[level] or {}
            for _, ic in ipairs(r.icons) do ic:Hide() end
            for i, id in ipairs(ids) do
                local ic = RowIcon(r, i)
                ic.affix = AffixById(id)
                ic:SetTexture(AffixIcon(ic.affix))
                ic:Show()
            end
            r.noAffix:SetText(#ids == 0 and (d.perRun and "Rolled when the run starts" or "No affixes") or "")

            local reason
            if not d.enabled then
                reason = "Mythic+ is not available right now."
            elseif m.maxStart == 0 then
                reason = UnlockText(m)
            elseif level > m.maxStart then
                reason = ("Clear Mythic+ %d first."):format(level - 1)
            elseif not d.leader then
                reason = "Only your group leader can start a Mythic+ run."
            elseif d.needsGroup then
                reason = "You need a group to start a Mythic+ run."
            end
            r.info = { level = level, health = health, damage = damage, reason = reason }

            if unlocked then
                r.locked:Hide()
                r.btn:Show()
                r.btn.mapId, r.btn.level, r.btn.raidName = m.id, level, multi and m.name or nil
                r.btn:SetDisabledLook(reason ~= nil)
            else
                r.btn:Hide()
                r.locked:Show()
            end
            y = y - LEVEL_ROW_H - 2
        end
    end

    P.child:SetHeight(math.max(1, -y + 6))
end

-- ---------------------------------------------------------------------
-- Affixes page
-- ---------------------------------------------------------------------

local function MakeAffixRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetWidth(CONTENT_W)
    r:EnableMouse(true)
    UI.MakeRowChrome(r, {})

    r.icon = UI.MakeIconFrame(r, { size = 32 })
    r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 8, -6)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, -1)
    r.badge = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.badge:SetPoint("TOPRIGHT", r, "TOPRIGHT", -8, -8)
    r.badge:SetJustifyH("RIGHT")
    r.desc = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.desc:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.desc:SetWidth(CONTENT_W - 64)
    r.desc:SetJustifyH("LEFT")
    Tint(r.desc, UI.Color.textPrimary)
    return r
end

local function ThresholdText(m)
    local joins, last = {}, 0
    for level = 1, m.cap do
        local n = #(m.levels[level] or {})
        if n > last then joins[#joins + 1] = tostring(level) end
        last = n
    end
    if #joins == 0 then return nil end
    if #joins == 1 then return ("Mythic+ %s adds an affix."):format(joins[1]) end
    return ("Mythic+ %s and %s each add an affix."):format(table.concat(joins, ", ", 1, #joins - 1), joins[#joins])
end

local function RenderAffixes()
    local d, P = S.data, W.affixes
    ResetPool(P.rows)

    local multi = #d.maps > 1
    local firsts = {}
    for i, m in ipairs(d.maps) do firsts[i] = FirstLevels(m) end

    local lines = {}
    if d.perRun then
        lines[#lines + 1] = "Affixes are rolled when a run starts."
    else
        lines[#lines + 1] = multi and "Active this week in each raid, and the level they join at."
            or "Active this week, and the level they join at."
        local threshold = d.maps[1] and ThresholdText(d.maps[1])
        if threshold then lines[#lines + 1] = threshold end
    end
    P.info:SetText(table.concat(lines, "\n"))
    local y = -4

    -- This week's affixes first, by the level they join at; then the rest by id.
    local list = {}
    for _, a in ipairs(d.affixes) do
        local soonest
        for i in ipairs(d.maps) do
            local lv = firsts[i][a.id]
            if lv and (not soonest or lv < soonest) then soonest = lv end
        end
        list[#list + 1] = { affix = a, soonest = soonest }
    end
    table.sort(list, function(x, z)
        if (x.soonest ~= nil) ~= (z.soonest ~= nil) then return x.soonest ~= nil end
        if x.soonest and z.soonest and x.soonest ~= z.soonest then return x.soonest < z.soonest end
        return x.affix.id < z.affix.id
    end)

    for _, e in ipairs(list) do
        local a = e.affix
        local r = Acquire(P.rows, MakeAffixRow, P.child)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", P.child, "TOPLEFT", 0, y)
        r.icon:SetTexture(AffixIcon(a))
        r.name:SetText(a.name)

        local active = e.soonest ~= nil
        Tint(r.name, (active or d.perRun) and UI.Color.textHi or UI.Nav.muted)
        r.icon:SetAlpha((active or d.perRun) and 1 or 0.5)
        if d.perRun then
            r.badge:SetText("")
        elseif not active then
            r.badge:SetText(Colored(UI.Nav.muted, "Not this week"))
        elseif multi then
            r.badge:SetText(Colored(UI.Color.textGood, "This week"))
        else
            r.badge:SetText(Colored(UI.Color.textGood, ("From Mythic+ %d"):format(e.soonest)))
        end

        local desc = a.description
        if multi and active then
            local per = {}
            for i, m in ipairs(d.maps) do
                if firsts[i][a.id] then per[#per + 1] = ("%s: from Mythic+ %d"):format(m.name, firsts[i][a.id]) end
            end
            desc = desc .. "\n" .. Colored(UI.Color.textGood, table.concat(per, ", "))
        end
        r.desc:SetText(desc)
        r:SetHeight(math.max(44, 30 + r.desc:GetStringHeight()))
        y = y - r:GetHeight() - 2
    end

    P.child:SetHeight(math.max(1, -y + 6))
end

-- ---------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------

local function UpdateResetText()
    local left = SecondsToReset()
    local d = S.data
    if not d or d.perRun or not left then
        W.footer.text:SetText("")
        return
    end
    W.footer.text:SetText("New weekly affixes in " .. Colored(UI.Color.textTitle, Remaining(left)))
end

local function MakePage(name)
    local page = CreateFrame("Frame", nil, W.frame)
    page:SetPoint("TOPLEFT", W.frame, "TOPLEFT", TAB_W + 36, -84)
    page:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", -18, 48)

    page.info = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    page.info:SetPoint("TOPLEFT", page, "TOPLEFT", 6, 0)
    page.info:SetWidth(CONTENT_W)
    page.info:SetJustifyH("LEFT")
    Tint(page.info, UI.Nav.muted)

    local scroll = CreateFrame("ScrollFrame", name, page, "UIPanelScrollFrameTemplate")
    page.scroll = scroll
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(CONTENT_W, 1)
    scroll:SetScrollChild(child)
    page.child = child
    page.headers, page.texts, page.rows = { used = 0 }, { used = 0 }, { used = 0 }
    page:Hide()
    return page
end

local function ShowPage(id)
    S.page = id
    if id == "affixes" then
        W.start:Hide()
        W.affixes:Show()
    else
        W.affixes:Hide()
        W.start:Show()
    end
end

local function Build()
    if W.frame then return end

    local f = UI.MakePanel(UIParent, FRAME_W, FRAME_H, {
        name = "ProjectAstralMythicPlusWarden", movable = true, strata = "HIGH", cosmic = true,
    })
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:Hide()
    W.frame = f

    W.header = UI.MakeHeader(f, "Mythic+", "Ember Warden")
    W.header.closeBtn:SetScript("OnClick", function() f:Hide() end)

    W.tabs = UI.MakeTabBar(f, {
        { id = "start",   label = "Start a run" },
        { id = "affixes", label = "Affixes" },
    }, function(id) ShowPage(id) end)
    W.tabs:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -84)
    W.tabs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 48)
    W.tabs:SetWidth(TAB_W)

    W.start = MakePage("ProjectAstralMythicPlusWardenStartScroll")
    W.start.scroll:SetPoint("TOPLEFT", W.start, "TOPLEFT", 0, 0)
    W.start.scroll:SetPoint("BOTTOMRIGHT", W.start, "BOTTOMRIGHT", -24, 0)

    W.affixes = MakePage("ProjectAstralMythicPlusWardenAffixScroll")
    W.affixes.scroll:SetPoint("TOPLEFT", W.affixes, "TOPLEFT", 0, -30)
    W.affixes.scroll:SetPoint("BOTTOMRIGHT", W.affixes, "BOTTOMRIGHT", -24, 0)

    W.footer = UI.MakeFooter(f, { text = "" })

    f:SetScript("OnUpdate", function(_, elapsed)
        S.tick = S.tick + elapsed
        if S.tick < 1 then return end
        S.tick = 0
        UpdateResetText()
    end)

    f:HookScript("OnHide", function()
        if f:IsShown() then return end
        StaticPopup_Hide(POPUP)
        if not S.closingFromServer then AIO.Handle("AstralMythicPlusWardenServer", "Close") end
        S.closingFromServer = false
    end)
    tinsert(UISpecialFrames, "ProjectAstralMythicPlusWarden")
end

-- The affix page's info text sets where its list starts, so it renders after the info.
local function Render()
    RenderStart()
    RenderAffixes()
    W.affixes.scroll:ClearAllPoints()
    W.affixes.scroll:SetPoint("TOPLEFT", W.affixes, "TOPLEFT", 0, -(W.affixes.info:GetStringHeight() + 10))
    W.affixes.scroll:SetPoint("BOTTOMRIGHT", W.affixes, "BOTTOMRIGHT", -24, 0)
    UpdateResetText()
end

-- ---------------------------------------------------------------------
-- AIO handlers (server -> client)
-- ---------------------------------------------------------------------

local Client = AIO.AddHandlers("AstralMythicPlusWarden", {})

Client.Open = function(_, data)
    if type(data) ~= "table" then return end
    Build()
    S.data = data
    S.openedAt = GetTime()
    S.closingFromServer = false
    if W.header.subtitle then W.header.subtitle:SetText("|cffaab0d4" .. (data.npcName or "") .. "|r") end
    StaticPopup_Hide(POPUP)
    Render()
    local page = S.page or "start"
    W.tabs:SelectTab(page)
    ShowPage(page)
    W.frame:Show()
end

Client.Close = function()
    if not W.frame then return end
    StaticPopup_Hide(POPUP)
    if W.frame:IsShown() then
        S.closingFromServer = true
        W.frame:Hide()
        S.closingFromServer = false
    end
end
