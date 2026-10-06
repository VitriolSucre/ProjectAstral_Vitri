
local PA = ProjectAstral or _G.ProjectAstral
if not PA then return end

local Paragon = {}
PA.Paragon = Paragon

Paragon.state = {
    level     = 0,
    max       = 10,
    available = 0,
    str = 0, agi = 0, sta = 0, intl = 0, spi = 0, sp = 0, ap = 0,
    done      = 0,
    total     = 0,
    ready     = false,
    pct       = { str=2.5, agi=2.5, sta=2.5, intl=2.5, spi=2.5, sp=2.5, ap=2.5 },
}

local STAT_ORDER = { "str", "agi", "sta", "intl", "spi", "sp", "ap" }
local STAT_LABEL = {
    str  = "Strength",
    agi  = "Agility",
    sta  = "Stamina",
    intl = "Intellect",
    spi  = "Spirit",
    sp   = "Spell Power",
    ap   = "Attack Power",
}
local STAT_WIRE = { str="str", agi="agi", sta="sta", intl="int", spi="spi", sp="sp", ap="ap" }

local function SendCmd(text)
    SendChatMessage(text, "SAY")
end

local function ParseInt(s)  return tonumber(s) or 0 end

function Paragon.ApplyState(payload)
    if type(payload) ~= "table" then return end
    local s = Paragon.state
    s.level     = tonumber(payload.level)     or 0
    s.max       = tonumber(payload.maxLevel)  or 0
    s.available = tonumber(payload.available) or 0
    s.str       = tonumber(payload.str)       or 0
    s.agi       = tonumber(payload.agi)       or 0
    s.sta       = tonumber(payload.sta)       or 0
    s.intl      = tonumber(payload.intl)      or 0
    s.spi       = tonumber(payload.spi)       or 0
    s.sp        = tonumber(payload.sp)        or 0
    s.ap        = tonumber(payload.ap)        or 0
    s.done      = tonumber(payload.eligibleDone)  or 0
    s.total     = tonumber(payload.eligibleTotal) or 0
    s.ready     = payload.ready and true or false
    s.pct.str   = (tonumber(payload.pctStrX10) or 0) / 10.0
    s.pct.agi   = (tonumber(payload.pctAgiX10) or 0) / 10.0
    s.pct.sta   = (tonumber(payload.pctStaX10) or 0) / 10.0
    s.pct.intl  = (tonumber(payload.pctIntX10) or 0) / 10.0
    s.pct.spi   = (tonumber(payload.pctSpiX10) or 0) / 10.0
    s.pct.sp    = (tonumber(payload.pctSpX10)  or 0) / 10.0
    s.pct.ap    = (tonumber(payload.pctApX10)  or 0) / 10.0
    if Paragon.frame then Paragon.Refresh() end
    if PA.AT and PA.AT.RefreshSummary then PA.AT.RefreshSummary() end
end

PA.Paragon = Paragon

local function MakeStatRow(parent, statKey, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(300, 84)
    PA.UI.FlatBackdrop(row, 0.98)
    row:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.94))

    local edge = PA.UI.SolidFill(row, { 0.42, 0.34, 0.20, 0.8 }, "ARTWORK")
    edge:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    edge:SetWidth(2)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 14, -12)
    label:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(STAT_LABEL[statKey])

    local value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    value:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -4)
    value:SetTextColor(1.0, 0.84, 0.29)

    local hint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    hint:SetPoint("LEFT", value, "RIGHT", 8, 0)
    hint:SetPoint("RIGHT", row, "RIGHT", -76, 0)
    hint:SetJustifyH("LEFT")

    local plus = PA.UI.MakeButton(row, "+", { w = 34, h = 32, variant = "secondary" })
    plus:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 10)
    plus.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    plus:SetScript("OnClick", function()
        if PA.AT and PA.AT.SendSpendParagonAIO then
            PA.AT.SendSpendParagonAIO(STAT_WIRE[statKey], 1)
        else
            SendCmd(".astral paragon spend " .. STAT_WIRE[statKey] .. " 1")
        end
    end)

    local minus = PA.UI.MakeButton(row, "−", { w = 34, h = 32, variant = "secondary" })
    minus:SetPoint("RIGHT", plus, "LEFT", -6, 0)
    minus.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    minus:SetScript("OnClick", function()
        if PA.AT and PA.AT.SendSpendParagonAIO then
            PA.AT.SendSpendParagonAIO(STAT_WIRE[statKey], -1)
        else
            SendCmd(".astral paragon spend " .. STAT_WIRE[statKey] .. " -1")
        end
    end)

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        local pts = Paragon.state[statKey]
        local pct = Paragon.state.pct[statKey] or 0
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(STAT_LABEL[statKey])
        GameTooltip:AddLine(string.format("Currently: %d points = +%.1f%%",
            pts, pts * pct), 1, 1, 1)
        GameTooltip:AddLine(string.format("Each point = +%.1f%% permanent",
            pct), 0.65, 0.78, 1.00)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row, value, hint
end

local function CreatePanel(parent)
    if Paragon.frame then return Paragon.frame end
    local f = CreateFrame("Frame", "ProjectAstralParagonPanel", parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
    f:EnableMouse(true)
    PA.UI.FlatBackdrop(f, 0.98)
    f:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.96))
    local sideRule = PA.UI.SolidFill(f, { 0.92, 0.68, 0.25, 0.9 }, "ARTWORK")
    sideRule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -1)
    sideRule:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 1)
    sideRule:SetWidth(2)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -20)
    title:SetText("Paragon")
    title:SetTextColor(1.0, 0.82, 0.34)
    f.title = title

    local description = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    description:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    description:SetText("Permanent bonuses. Your build, your rules.")
    description:SetTextColor(0.62, 0.66, 0.76)

    local levelCaption = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    levelCaption:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    levelCaption:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -20)
    levelCaption:SetText("PARAGON LEVEL")
    levelCaption:SetTextColor(0.62, 0.66, 0.76)

    local level = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    level:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    level:SetPoint("TOPRIGHT", levelCaption, "BOTTOMRIGHT", 0, -3)
    level:SetTextColor(1.0, 0.84, 0.29)
    f.level = level

    local barBG = f:CreateTexture(nil, "BACKGROUND")
    barBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    barBG:SetVertexColor(0.10, 0.12, 0.18, 1.0)
    barBG:SetPoint("TOPLEFT",  f, "TOPLEFT",  24, -84)
    barBG:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -84)
    barBG:SetHeight(12)

    local barFG = f:CreateTexture(nil, "ARTWORK")
    barFG:SetTexture("Interface\\Buttons\\WHITE8X8")
    barFG:SetVertexColor(0.94, 0.68, 0.24, 1.0)
    barFG:SetPoint("TOPLEFT", barBG, "TOPLEFT", 0, 0)
    barFG:SetHeight(12)
    barFG:SetWidth(1)
    f.barBG = barBG; f.barFG = barFG

    -- Non-zero size + Show so WoW 3.3.5 actually ticks OnUpdate (0×0 hidden = never fires).
    f.barTargetPct = 0
    local drv = CreateFrame("Frame", nil, f)
    drv:SetSize(1, 1); drv:Show()
    drv:SetScript("OnUpdate", function(_, elapsed)
        if not f.barFG or not f.barBG then return end
        local fullW = f.barBG:GetWidth() or 0
        if fullW < 2 then return end
        local tgt = math.max(1, fullW * (f.barTargetPct or 0))
        local cur = f.barFG:GetWidth() or 1
        if math.abs(cur - tgt) < 0.5 then
            if cur ~= tgt then f.barFG:SetWidth(tgt) end
            return
        end
        local step = 450 * elapsed
        if cur < tgt then
            f.barFG:SetWidth(math.min(tgt, cur + step))
        else
            f.barFG:SetWidth(math.max(tgt, cur - step))
        end
    end)

    local progress = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    progress:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    progress:SetPoint("TOPLEFT", barBG, "BOTTOMLEFT", 0, -7)
    f.progress = progress

    local avail = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    avail:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    avail:SetPoint("TOPRIGHT", barBG, "BOTTOMRIGHT", 0, -6)
    f.avail = avail

    local divider = PA.UI.SolidFill(f, { 0.20, 0.22, 0.29, 0.9 }, "ARTWORK")
    divider:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -126)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -126)
    divider:SetHeight(1)

    local statsTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statsTitle:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    statsTitle:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -145)
    statsTitle:SetText("Permanent Bonuses")
    statsTitle:SetTextColor(0.91, 0.92, 0.97)

    local statsSubtitle = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statsSubtitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    statsSubtitle:SetPoint("LEFT", statsTitle, "RIGHT", 10, 0)
    statsSubtitle:SetText("Choose where each unspent point goes.")
    statsSubtitle:SetTextColor(0.55, 0.59, 0.68)

    f.rows = {}; f.rowValue = {}
    for _, statKey in ipairs(STAT_ORDER) do
        local row, value, hint = MakeStatRow(f, statKey)
        f.rows[statKey] = row
        f.rowValue[statKey] = value
        f.rowHint = f.rowHint or {}
        f.rowHint[statKey] = hint
    end

    local reset = PA.UI.MakeButton(f, "Paragon Up", {
        w = 400, h = 44, variant = "gold",
    })
    reset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 24, 14)
    reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 14)
    reset.SetText = reset.SetLabel
    reset.text:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    reset:SetScript("OnClick", function()
        if not Paragon.state.ready then return end
        local price = Paragon.state.total or 0
        StaticPopupDialogs["PA_PARAGON_CONFIRM"] = {
            text = string.format(
                "Spend %d Tokens to gain 1 Paragon level?\n\nThe tree, unlocked nodes, and every stat point you've spent stay exactly as they are.",
                price),
            button1 = "Confirm", button2 = "Cancel",
            OnAccept = function()
                if PA.AT and PA.AT.SendDoParagonUpAIO then
                    PA.AT.SendDoParagonUpAIO()
                else
                    SendCmd(".astral paragon")
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, exclusive = true,
        }
        StaticPopup_Show("PA_PARAGON_CONFIRM")
    end)
    f.reset = reset

    local function LayoutStats(width, height)
        local columns = width >= 620 and 2 or 1
        local rows = math.ceil(#STAT_ORDER / columns)
        local gapX, gapY = 12, 10
        local left, right = 24, 24
        local startY = 184
        local footerSpace = 76
        local tileW = (width - left - right - gapX * (columns - 1)) / columns
        local tileH = math.max(58,
            (height - startY - footerSpace - gapY * (rows - 1)) / rows)
        for index, statKey in ipairs(STAT_ORDER) do
            local column = (index - 1) % columns
            local rowIndex = math.floor((index - 1) / columns)
            local row = f.rows[statKey]
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", f, "TOPLEFT", left + column * (tileW + gapX),
                -(startY + rowIndex * (tileH + gapY)))
            row:SetSize(tileW, tileH)
        end
    end
    f:SetScript("OnSizeChanged", function(_, width, height)
        LayoutStats(width, height)
    end)
    LayoutStats(parent:GetWidth() or 800, parent:GetHeight() or 600)

    Paragon.frame = f
    if PA.OnTokensChanged and not Paragon._tokensHooked then
        Paragon._tokensHooked = true
        PA:OnTokensChanged(function() Paragon.Refresh() end)
    end
    f:HookScript("OnShow", function()
        if PA.AT and PA.AT.RequestParagonStateAIO then
            PA.AT.RequestParagonStateAIO()
        end
    end)
    if PA.AT and PA.AT.RequestParagonStateAIO then
        PA.AT.RequestParagonStateAIO()
    end
    return f
end

function Paragon.Refresh()
    local f = Paragon.frame; if not f then return end
    local s = Paragon.state

    local balance = (PA and PA.prestigeTokens) or s.done or 0
    s.done  = balance
    s.ready = (s.level < s.max) and (s.total > 0) and (balance >= s.total)

    if s.max == 0 and s.level == 0 and s.total == 0 then
        f.level:SetText("|cffffd24a…|r / …")
        f.progress:SetText("Loading paragon state…")
        f.avail:SetText("")
        f.reset:SetDisabledLook(true)
        f.reset:SetText("Loading…")
        f.barTargetPct = 0
        if not Paragon._reqRefresh then
            Paragon._reqRefresh = true
            SendCmd(".astral tree")
        end
        return
    end
    Paragon._reqRefresh = false

    f.level:SetText(string.format("|cffffd24a%d|r / %d", s.level, s.max))
    if s.total > 0 then
        local pct = balance / s.total
        if pct > 1 then pct = 1 end
        f.barTargetPct = pct
        local fullW = f.barBG:GetWidth() or 0
        if fullW > 2 then
            f.barFG:SetWidth(math.max(1, fullW * pct))
        end
        f.progress:SetText(string.format("%d / %d Tokens", balance, s.total))
    else
        f.barTargetPct = 0
        f.progress:SetText("Paragon max level reached")
    end
    f.avail:SetText(string.format("|cffffd24a%d|r unspent", s.available))

    for _, statKey in ipairs(STAT_ORDER) do
        local pts = s[statKey]
        f.rowValue[statKey]:SetText(string.format("%d", pts))
        f.rowHint[statKey]:SetText(string.format("+%.1f%% per point", s.pct[statKey] or 0))
    end

    if s.ready then
        f.reset:SetDisabledLook(false)
        f.reset:SetText(string.format("Buy Paragon %d/%d — %d Tokens",
            s.level + 1, s.max, s.total))
    else
        f.reset:SetDisabledLook(true)
        if s.level >= s.max then
            f.reset:SetText("Paragon Max Level")
        else
            f.reset:SetText(string.format("Need %d more Tokens",
                math.max(0, s.total - s.done)))
        end
    end
end

local function ToggleParagon()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "paragon" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("paragon")
    end
end

PA:RegisterModule("paragon", "Paragon", ToggleParagon, {
    subtitle = "Allocate permanent bonuses and advance your Paragon level.",
})
PA:RegisterTabContent("paragon", function(parent)
    CreatePanel(parent)
    Paragon.Refresh()
end)
