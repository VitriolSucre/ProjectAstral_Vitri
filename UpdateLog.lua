local PA = ProjectAstral
local UI = PA.UI

local UPDATES = {
    {
        id = "2026-09-17c",
        date = "September 17, 2026",
        title = "UI polish and BuildSaver support",
        entries = {
            { "New", "BuildSaver support detects the separate BuildSaver addon and adds an Astral hub launcher without duplicating its saved data." },
            { "Improved", "BuildSaver uses the Astral dark window, panel, text and button theme." },
            { "Fixed", "BuildSaver styling now waits for the window to finish loading after /reload." },
            { "Fixed", "The BuildSaver close button keeps its normal X, pressed and hover artwork." },
            { "Improved", "Recent Project Astral code was cleaned up to remove unnecessary inline comments." },
        },
    },
    {
        id = "2026-09-17b",
        date = "September 17, 2026",
        title = "Daily Callboard and Skills fixes",
        entries = {
            { "Improved", "Daily Callboard filters now match the Astral hub tab bar." },
            { "Improved", "Callboard cards show category, objective, level range, token reward and action together." },
            { "Improved", "Callboard status separates reset time, token soft-cap progress and active quest count." },
            { "Fixed", "The client-side 300-second locked display was removed from Callboard actions." },
            { "Improved", "Callboard accept buttons use the Astral dark button style and tighter spacing." },
            { "Fixed", "Skills prerequisite unlock paths no longer repeatedly scan the full pending list." },
            { "Fixed", "Opening the Skills tab avoids duplicate focus and tree rebuild work." },
            { "Improved", "Dragging a mount temporarily reveals hidden action bars and restores them afterward." },
        },
    },
    {
        id = "2026-09-17a",
        date = "September 17, 2026",
        title = "Project Astral feature cleanup",
        entries = {
            { "New", "The Update Log now lists current Project Astral features and changes only." },
            { "Improved", "The hub includes Skills, Stats, Gems, Gem Builds, Store, Mounts, Raid, Leaderboards, Reagent Bank, Update Log and Settings." },
            { "Improved", "The Token Tracker and gain popups show Astral token and orb progress while you play." },
            { "Improved", "The hub remembers its position, size, scale, opacity and selected tab." },
            { "New", "Quest auto-accept, auto-turn-in and auto-loot are available as optional settings and disabled by default." },
            { "Fixed", "Removed disabled DPS, gem tracker and replacement chat modules from the Project Astral load list." },
            { "Fixed", "Removed misleading update entries for features no longer included in the addon." },
            { "Improved", "Blizzard windows are no longer given the removed global black reskin." },
        },
    },
}
PA.UpdateLog = UPDATES

local SOLID = "Interface\\Buttons\\WHITE8X8"
local MAX_TEXT_W = 900
local PILL_W = 74
local TAG_COLOR = {
    New = { 0.35, 0.90, 0.60 },
    Improved = { 0.55, 0.78, 1.00 },
    Fixed = { 1.00, 0.70, 0.35 },
}

local function LatestId()
    return UPDATES[1] and UPDATES[1].id
end

function PA.UpdateLogHasUnseen()
    local latest = LatestId()
    local seen = PA.Settings and PA.Settings.lastSeenUpdate
    return latest ~= nil and seen ~= latest
end

local function MarkSeen()
    if not PA.UpdateLogHasUnseen() then return end
    if PA.SaveSetting then PA.SaveSetting("lastSeenUpdate", LatestId()) end
    local mf = PA.mainFrame
    if mf and mf.RefreshTabBadges then mf:RefreshTabBadges() end
end

local host, scroll, content
local items = {}

local function BuildItems()
    for i, u in ipairs(UPDATES) do
        local hdr = CreateFrame("Frame", nil, content)
        hdr:SetHeight(40)

        local bar = hdr:CreateTexture(nil, "ARTWORK")
        bar:SetTexture(SOLID)
        bar:SetSize(3, 18)
        bar:SetPoint("LEFT", hdr, "LEFT", 0, 3)
        local barColor = (i == 1) and TAG_COLOR.New or UI.Color.accentSoft
        bar:SetVertexColor(barColor[1], barColor[2], barColor[3], 1)

        local title = hdr:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
        title:SetPoint("LEFT", bar, "RIGHT", 8, 0)
        title:SetText(u.title)
        title:SetTextColor(unpack(UI.Color.textTitle))

        local date = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        date:SetPoint("LEFT", title, "RIGHT", 10, -1)
        date:SetText(u.date)

        if i == 1 then
            local latest = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            latest:SetPoint("LEFT", date, "RIGHT", 10, 0)
            latest:SetText("LATEST")
            latest:SetTextColor(unpack(TAG_COLOR.New))
        end

        local rule = UI.SolidFill(hdr, UI.Nav.edge, "ARTWORK")
        rule:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 6)
        rule:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 6)
        rule:SetHeight(1)
        items[#items + 1] = { kind = "header", frame = hdr }

        for _, e in ipairs(u.entries) do
            local tag, text = e[1], e[2]
            local c = TAG_COLOR[tag] or UI.Nav.muted
            local row = CreateFrame("Frame", nil, content)
            local pill = CreateFrame("Frame", nil, row)
            pill:SetSize(PILL_W, 18)
            pill:SetPoint("TOPLEFT", row, "TOPLEFT", 12, 0)
            local pillBg = pill:CreateTexture(nil, "BACKGROUND")
            pillBg:SetTexture(SOLID)
            pillBg:SetAllPoints()
            pillBg:SetVertexColor(c[1], c[2], c[3], 0.15)
            if UI.Outline then UI.Outline(pill, pill, "BORDER", c, 0.6) end
            local pillText = pill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            pillText:SetPoint("CENTER")
            pillText:SetText(string.upper(tag))
            pillText:SetTextColor(c[1], c[2], c[3])

            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", pill, "TOPRIGHT", 10, 1)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetText(text)
            fs:SetTextColor(unpack(UI.Color.textPrimary))
            items[#items + 1] = { kind = "entry", frame = row, text = fs }
        end
    end
end

local function Layout()
    if not (host and content) then return end
    local w = (host:GetWidth() or 0) - 26
    if w <= 40 then return end
    content:SetWidth(w)
    local colW = math.min(w, MAX_TEXT_W)
    local padX = math.floor((w - colW) / 2)
    local textW = colW - 12 - PILL_W - 10 - 8
    local y = 0
    for i, it in ipairs(items) do
        if it.kind == "header" and i > 1 then y = y + 16 end
        it.frame:ClearAllPoints()
        it.frame:SetPoint("TOPLEFT", content, "TOPLEFT", padX, -y)
        it.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -padX, -y)
        if it.kind == "header" then
            y = y + 40
        else
            it.text:SetWidth(textW)
            local lines = math.max(1, math.ceil((it.text:GetStringWidth() or 0) / textW))
            local h = math.max(18, math.ceil(it.text:GetStringHeight() or 0), lines * 15)
            it.frame:SetHeight(h + 8)
            y = y + h + 8
        end
    end
    content:SetHeight(math.max(1, y + 10))
    scroll:UpdateScrollChildRect()
end

local function BuildUpdateLogTab(panel)
    host = panel
    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    intro:SetText("Current Project Astral features and fixes, newest first.")
    intro:SetTextColor(unpack(UI.Nav.muted))

    scroll = CreateFrame("ScrollFrame", "PAUpdateLogScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -26)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    BuildItems()
    panel:SetScript("OnSizeChanged", Layout)
    panel:SetScript("OnShow", function()
        Layout()
        MarkSeen()
    end)
end

local notice = CreateFrame("Frame")
notice:SetSize(1, 1)
notice:RegisterEvent("PLAYER_LOGIN")
notice:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local acc = 0
    self:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 6 then return end
        self:SetScript("OnUpdate", nil)
        local u = UPDATES[1]
        if u and PA.UpdateLogHasUnseen() then
            DEFAULT_CHAT_FRAME:AddMessage("|cff99b8ff[Project Astral]|r What's new: |cffffffff"
                .. u.title .. "|r. Type |cffffffff/astral|r and open the Update Log tab.")
        end
    end)
end)

local function ToggleUpdateLog()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "update_log" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("update_log")
    end
end

PA:RegisterModule("update_log", "Update Log", ToggleUpdateLog, {
    subtitle = "What's new in Project Astral.",
})
PA:RegisterTabContent("update_log", BuildUpdateLogTab)
