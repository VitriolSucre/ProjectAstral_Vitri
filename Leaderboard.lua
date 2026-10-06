
local PA = ProjectAstral or _G.ProjectAstral
local UI = PA.UI or _G.PA_UI

local LB = {}
PA.Leaderboard = LB

local activeCat  = "tokens"
local results    = {}
local selfEntries = {}
local building   = {}
local lastErr    = {}
local clearMap = nil
local challengeMain = "Hardcore"
local challengeSub  = "Normal"

local RAIDS = {
    { id = 409, label = "Molten Core" },
    -- { id = 469, label = "Blackwing Lair" },
    -- { id = 531, label = "AQ40" },
    -- { id = 509, label = "AQ20" },
    -- { id = 309, label = "Zul'Gurub" },
}
local BOSSES_BY_MAP = {
    [409] = {
        { entry = 12118, label = "Lucifron" },
        { entry = 11982, label = "Magmadar" },
        { entry = 12259, label = "Gehennas" },
        { entry = 12057, label = "Garr" },
        { entry = 12056, label = "Baron Geddon" },
        { entry = 12264, label = "Shazzrah" },
        { entry = 12098, label = "Sulfuron Harbinger" },
        { entry = 11988, label = "Golemagg the Incinerator" },
        { entry = 12018, label = "Majordomo Executus" },
        { entry = 11502, label = "Ragnaros" },
    },
}

local CATS = {
    { id = "tokens",    label = "Tokens",       valueKind = "int"     },
    { id = "prestiges", label = "Prestiges",    valueKind = "int"     },
    { id = "level",     label = "Speed 1-60",   valueKind = "seconds" },
    { id = "playtime",  label = "Playtime",     valueKind = "seconds" },
    { id = "challenge", label = "Challenges",   valueKind = "seconds" },
    { id = "clear",     label = "Raid Clear",   valueKind = "seconds", wip = true },
}

-- MUST match mod-Astralchallenges Family/BaseMode/Modifier TINYINTs — drift = empty results.
local FAMILY_ENUM   = { Classic = 0, MakeLove = 1, Taskman = 2, Ironman = 3, Greenman = 4, Pacifist = 5 }
local BASEMODE_ENUM = { None = 0, Hardcore = 1, Nightmare = 2, HardcoreNightmare = 3 }
local MODIFIER_ENUM = { Normal = 0, Nodeless = 1, Gemless = 2, Astralless = 3 }

local CHALLENGE_MAIN = {
    { key = "Hardcore",          label = "Hardcore",           kind = "classic", mode = "Hardcore" },
    { key = "Nightmare",         label = "Nightmare",          kind = "classic", mode = "Nightmare" },
    { key = "HardcoreNightmare", label = "Hardcore Nightmare", kind = "classic", mode = "HardcoreNightmare" },
    { key = "MakeLove",          label = "Make Love not Warcraft", kind = "family", family = "MakeLove" },
    { key = "Taskman",           label = "Taskman",            kind = "family", family = "Taskman" },
    { key = "Ironman",           label = "Ironman",            kind = "family", family = "Ironman" },
    { key = "Greenman",          label = "Greenman",           kind = "family", family = "Greenman" },
    { key = "Pacifist",          label = "Pacifist",           kind = "family", family = "Pacifist" },
}

local CHALLENGE_SUB_CLASSIC = {
    { key = "Normal",     label = "Normal",     modifier = "Normal" },
    { key = "Gemless",    label = "Gemless",    modifier = "Gemless" },
    { key = "Nodeless",   label = "Nodeless",   modifier = "Nodeless" },
    { key = "Astralless", label = "Astralless", modifier = "Astralless" },
}
local CHALLENGE_SUB_FAMILY = {
    { key = "Normal",     label = "Normal",     mode = "None",              modifier = "Normal" },
    { key = "Gemless",    label = "Gemless",    mode = "None",              modifier = "Gemless" },
    { key = "Nodeless",   label = "Nodeless",   mode = "None",              modifier = "Nodeless" },
    { key = "Astralless", label = "Astralless", mode = "None",              modifier = "Astralless" },
    { key = "Nightmare",  label = "Nightmare",  mode = "Nightmare",         modifier = "Normal" },
    { key = "Hardcore",   label = "Hardcore",   mode = "Hardcore",          modifier = "Normal" },
    { key = "NightmareHardcore",           label = "Nightmare + Hardcore", mode = "HardcoreNightmare", modifier = "Normal" },
    { key = "NightmareHardcoreAstralless", label = "The Full Nightmare",   mode = "HardcoreNightmare", modifier = "Astralless" },
}

local function ChallengeMainByKey(k)
    for _, c in ipairs(CHALLENGE_MAIN) do if c.key == k then return c end end
end
local function ChallengeSubList(mainKey)
    local main = ChallengeMainByKey(mainKey)
    if not main then return CHALLENGE_SUB_CLASSIC end
    return main.kind == "classic" and CHALLENGE_SUB_CLASSIC or CHALLENGE_SUB_FAMILY
end
local function ChallengeSubByKey(mainKey, subKey)
    for _, s in ipairs(ChallengeSubList(mainKey)) do
        if s.key == subKey then return s end
    end
end

local function ResolveChallengeTriple()
    local main = ChallengeMainByKey(challengeMain)
    if not main then return nil end
    local sub  = ChallengeSubByKey(challengeMain, challengeSub)
    if not sub then return nil end

    local family, mode, mod
    if main.kind == "classic" then
        family = FAMILY_ENUM.Classic
        mode   = BASEMODE_ENUM[main.mode] or 0
        mod    = MODIFIER_ENUM[sub.modifier] or 0
    else
        family = FAMILY_ENUM[main.family] or 0
        mode   = BASEMODE_ENUM[sub.mode]  or 0
        mod    = MODIFIER_ENUM[sub.modifier] or 0
    end
    return family, mode, mod
end

local function CatById(id)
    for _, c in ipairs(CATS) do if c.id == id then return c end end
end

local function FormatSeconds(s)
    s = tonumber(s) or 0
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sec = s % 60
    return string.format("%d:%02d:%02d", h, m, sec)
end

local function FormatValue(kind, v)
    if kind == "seconds" then return FormatSeconds(v) end
    return tostring(v)
end

-- declared before SendServer, which uses it (declaring it further down left SendServer
-- reading a nil global, so the loading overlay never showed)
local listFrame

local function SendServer(cat, arg1, arg2, arg3)
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralLeaderboardServer", "Request", cat, arg1, arg2, arg3)
    end
    if listFrame and listFrame.loadingOverlay then
        listFrame.loadingOverlay:Show()
    end
end

local function RequestCurrent()
    if activeCat == "tokens"    then SendServer("tokens")
    elseif activeCat == "prestiges" then SendServer("prestiges")
    elseif activeCat == "level"     then SendServer("level")
    elseif activeCat == "playtime"  then SendServer("playtime")
    elseif activeCat == "challenge" then
        local family, mode, mod = ResolveChallengeTriple()
        if family then
            SendServer("challenge", family, mode, mod)
        end
    elseif activeCat == "clear" then
        if clearMap then
            SendServer("clear", clearMap)
        end
    end
end

local panel
local subTabBar
local rowFrames = {}
local emptyText
local errText
local clearRaidDd
local challengeMainDd, challengeSubDd

local ROW_H        = 34
local MAX_ENTRIES  = 50   -- matches server LB_LIMIT

local function ApplyDropdownVisibility()
    local showClr = activeCat == "clear"
    local showChl = activeCat == "challenge"
    if clearRaidDd      then if showClr then clearRaidDd:Show()      else clearRaidDd:Hide()      end end
    if challengeMainDd then if showChl then challengeMainDd:Show() else challengeMainDd:Hide() end end
    if challengeSubDd  then if showChl then challengeSubDd:Show()  else challengeSubDd:Hide()  end end
end

local function RefreshList()
    if not listFrame then return end
    local cat = CatById(activeCat)
    if not cat then return end

    local data = results[activeCat] or {}
    local err  = lastErr[activeCat]

    if err then
        errText:SetText("|cffff8888" .. err .. "|r")
        errText:Show()
    else
        errText:Hide()
    end

    if #data == 0 then
        if activeCat == "challenge" and not ResolveChallengeTriple() then
            emptyText:SetText("Pick a challenge and a variant to view the ranking.")
        elseif activeCat == "clear" and not clearMap then
            emptyText:SetText("Pick a raid to view the ranking.")
        elseif err then
            emptyText:SetText("")
        else
            emptyText:SetText("No entries yet — be the first.")
        end
        emptyText:Show()
    else
        emptyText:Hide()
    end

    local total = math.min(#data, MAX_ENTRIES)
    local scroll = listFrame.scroll
    local visibleRows = scroll and math.floor((scroll:GetHeight() or 0) / ROW_H) or 0
    if visibleRows < 1 then visibleRows = 10 end
    visibleRows = math.min(visibleRows, MAX_ENTRIES)
    if scroll then
        FauxScrollFrame_Update(scroll, total, visibleRows, ROW_H)
    end
    local offset = (scroll and FauxScrollFrame_GetOffset(scroll)) or 0

    for i = 1, visibleRows do
        local row  = rowFrames[i]
        local entry = data[offset + i]
        if entry and (offset + i) <= MAX_ENTRIES then
            row.rank:SetText(tostring(entry.rank or (offset + i)) .. ".")
            row.name:SetText(entry.name or "?")
            row.value:SetText(FormatValue(cat.valueKind, entry.value))
            row:Show()
        else
            row:Hide()
        end
    end
    for i = visibleRows + 1, #rowFrames do
        rowFrames[i]:Hide()
    end

    if listFrame and listFrame.selfRow then
        local self_ = selfEntries[activeCat]
        if self_ then
            listFrame.selfRow.rank:SetText(tostring(self_.rank or "?") .. ".")
            listFrame.selfRow.name:SetText(self_.name or "?")
                listFrame.selfRow.value:SetText(FormatValue(cat.valueKind, self_.value))
            listFrame.selfRow:Show()
        else
            listFrame.selfRow:Hide()
        end
    end
end
LB._RefreshList = RefreshList

local function FindOptionLabel(options, value)
    for _, opt in ipairs(options) do
        if opt.value == value then return opt.label end
    end
end

local function InitDropdown(dd, options, getCurrent, onPick, width)
    UIDropDownMenu_SetWidth(dd, width or 160)
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text     = opt.label
            info.value    = opt.value
            info.checked  = (opt.value == getCurrent())
            info.func     = function()
                onPick(opt.value, opt)
                -- 3.3.5a UIDropDownMenu_SetText is (frame, text); reversed args crash on string:GetName().
                UIDropDownMenu_SetSelectedValue(dd, opt.value)
                UIDropDownMenu_SetText(dd, opt.label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetSelectedValue(dd, getCurrent())
    local lbl = FindOptionLabel(options, getCurrent())
    if lbl then UIDropDownMenu_SetText(dd, lbl) end
    local text = dd:GetName() and _G[dd:GetName() .. "Text"]
    if text then text:SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
end

local function PaintSubTabs(buttons)
    for id, b in pairs(buttons) do
        if b._wip then
            b:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.85))
            b:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 1.0))
            if b.text then b.text:SetTextColor(0.45, 0.45, 0.50) end
        elseif id == activeCat then
            b:SetBackdropColor(0.20, 0.16, 0.34, 0.95)
            b:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 1.0))
            if b.text then b.text:SetTextColor(1.00, 0.92, 0.40) end
        else
            b:SetBackdropColor(0.10, 0.10, 0.16, 0.90)
            b:SetBackdropBorderColor(0.30, 0.34, 0.50, 1.0)
            if b.text then b.text:SetTextColor(0.85, 0.88, 0.95) end
        end
    end
end

local function BuildSubTabBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    bar:SetHeight(34)
    bar.buttons = {}

    local btnW = 92
    local btnH = 30
    local gap  = 5
    local function LayoutButtons()
        local width = bar:GetWidth()
        if width <= 0 then width = 560 end
        btnW = math.floor((width - gap * (#CATS - 1)) / #CATS)
        local x = 0
        for _, cat in ipairs(CATS) do
            local button = bar.buttons[cat.id]
            if button then
                button:SetSize(btnW, btnH)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
                x = x + btnW + gap
            end
        end
    end
    local x    = 0
    for _, c in ipairs(CATS) do
        local b = UI.MakeButton(bar, c.label, {
            w = btnW, h = btnH,
            variant = "gold",
            onClick = function()
                if c.wip then return end
                activeCat = c.id
                ApplyDropdownVisibility()
                PaintSubTabs(bar.buttons)
                RequestCurrent()
                RefreshList()
            end,
        })
        b.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
        b._catId = c.id
        b._wip   = c.wip == true

        b:SetScript("OnEnter", function(self)
            if self._wip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(c.label)
                GameTooltip:AddLine("|cffff8888Work in Progress|r", 1, 1, 1, true)
                GameTooltip:Show()
                return
            end
            if self._catId == activeCat then return end
            self:SetBackdropColor(0.16, 0.16, 0.22, 0.95)
            self:SetBackdropBorderColor(0.55, 0.60, 0.80, 1.0)
        end)
        b:SetScript("OnLeave", function(self)
            if self._wip then GameTooltip:Hide() end
            PaintSubTabs(bar.buttons)
        end)

        bar.buttons[c.id] = b
        x = x + btnW + gap
    end
    bar:SetScript("OnSizeChanged", LayoutButtons)
    LayoutButtons()

    PaintSubTabs(bar.buttons)
    return bar
end

local function BuildLeaderboardTab(parent)
    if panel and panel:GetParent() == parent then return panel end

    panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints(parent)

    panel:SetScript("OnHide", function()
        if subTabBar        then subTabBar:Hide()        end
        if listFrame        then listFrame:Hide()        end
        if clearRaidDd      then clearRaidDd:Hide()      end
        if challengeMainDd then challengeMainDd:Hide() end
        if challengeSubDd  then challengeSubDd:Hide()  end
    end)
    panel:SetScript("OnShow", function()
        if subTabBar then subTabBar:Show() end
        if listFrame then listFrame:Show() end
        ApplyDropdownVisibility()
    end)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "THICKOUTLINE")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)
    title:SetText("|cffFFD700Leaderboard|r")

    subTabBar = BuildSubTabBar(panel)
    subTabBar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  8, -38)
    subTabBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -38)

    local ddRow = CreateFrame("Frame", nil, panel)
    ddRow:SetPoint("TOPLEFT",  subTabBar, "BOTTOMLEFT", 0, -10)
    ddRow:SetPoint("TOPRIGHT", subTabBar, "BOTTOMRIGHT", 0, -10)
    ddRow:SetHeight(40)

    challengeMainDd = CreateFrame("Frame", "PA_LB_ChallengeMainDD", ddRow, "UIDropDownMenuTemplate")
    challengeMainDd:SetPoint("LEFT", ddRow, "LEFT", -4, 0)

    challengeSubDd = CreateFrame("Frame", "PA_LB_ChallengeSubDD", ddRow, "UIDropDownMenuTemplate")
    challengeSubDd:SetPoint("LEFT", challengeMainDd, "RIGHT", -4, 0)

    local function InitSubDropdown()
        local list = ChallengeSubList(challengeMain)
        InitDropdown(challengeSubDd, (function()
            local out = {}
            for _, s in ipairs(list) do out[#out+1] = { value = s.key, label = s.label } end
            return out
        end)(), function() return challengeSub end, function(v)
            challengeSub = v
            RequestCurrent()
        end, 200)
    end

    InitDropdown(challengeMainDd, (function()
        local out = {}
        for _, c in ipairs(CHALLENGE_MAIN) do
            out[#out+1] = { value = c.key, label = c.label }
        end
        return out
    end)(), function() return challengeMain end, function(v)
        challengeMain = v
        local list = ChallengeSubList(challengeMain)
        challengeSub = list[1] and list[1].key or "Normal"
        InitSubDropdown()
        RequestCurrent()
    end, 200)

    InitSubDropdown()

    clearRaidDd = CreateFrame("Frame", "PA_LB_ClearRaidDD", ddRow, "UIDropDownMenuTemplate")
    clearRaidDd:SetPoint("LEFT", ddRow, "LEFT", -4, 0)
    InitDropdown(clearRaidDd, (function()
        local out = {}
        for _, r in ipairs(RAIDS) do out[#out+1] = { value = r.id, label = r.label } end
        return out
    end)(), function() return clearMap or RAIDS[1].id end, function(v)
        clearMap = v
        RequestCurrent()
    end)

    listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT",  ddRow, "BOTTOMLEFT",  0, -10)
    listFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 12)
    listFrame:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    PA.UI.CosmicCorners(listFrame)
    listFrame:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.85))
    listFrame:SetBackdropBorderColor(0.35, 0.40, 0.55, 1)

    if PA.UI and PA.UI.MakeLoadingOverlay then
        listFrame.loadingOverlay = PA.UI.MakeLoadingOverlay(listFrame,
            { text = "Fetching leaderboard" .. string.char(0xE2, 0x80, 0xA6) })
    end

    emptyText = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
    emptyText:SetPoint("CENTER", listFrame, "CENTER", 0, 0)
    emptyText:SetTextColor(0.7, 0.7, 0.8)

    errText = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    errText:SetPoint("TOP", listFrame, "TOP", 0, -6)
    errText:Hide()

    local SELF_ROW_STRIP = ROW_H + 8
    local columnRank = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    columnRank:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    columnRank:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 20, -10)
    columnRank:SetWidth(40)
    columnRank:SetText("RANK")
    columnRank:SetTextColor(unpack(UI.Nav.muted))

    local columnPlayer = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    columnPlayer:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    columnPlayer:SetPoint("LEFT", columnRank, "RIGHT", 12, 0)
    columnPlayer:SetText("PLAYER")
    columnPlayer:SetTextColor(unpack(UI.Nav.muted))

    local columnValue = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    columnValue:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    columnValue:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -34, -10)
    columnValue:SetText("VALUE")
    columnValue:SetTextColor(unpack(UI.Nav.muted))

    local scroll = CreateFrame("ScrollFrame", "PA_LB_Scroll", listFrame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listFrame, "TOPLEFT",      6, -30)
    scroll:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -28, 6 + SELF_ROW_STRIP)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)
    listFrame.scroll = scroll

    local divider = listFrame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(0.4, 0.45, 0.6, 0.6)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT",  listFrame, "BOTTOMLEFT",  6, SELF_ROW_STRIP + 2)
    divider:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, SELF_ROW_STRIP + 2)

    local selfRow = CreateFrame("Frame", nil, listFrame)
    selfRow:SetHeight(ROW_H)
    selfRow:SetPoint("BOTTOMLEFT",  listFrame, "BOTTOMLEFT",  8, 4)
    selfRow:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -8, 4)

    local selfBg = selfRow:CreateTexture(nil, "BACKGROUND")
    selfBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    selfBg:SetVertexColor(0.15, 0.20, 0.35, 0.55)
    selfBg:SetAllPoints()

    local selfAccent = selfRow:CreateTexture(nil, "ARTWORK")
    selfAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    selfAccent:SetVertexColor(1.0, 0.84, 0.29, 1.0)
    selfAccent:SetWidth(3)
    selfAccent:SetPoint("TOPLEFT",    selfRow, "TOPLEFT",    0, 0)
    selfAccent:SetPoint("BOTTOMLEFT", selfRow, "BOTTOMLEFT", 0, 0)

    selfRow.rank = selfRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selfRow.rank:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    selfRow.rank:SetPoint("LEFT", selfRow, "LEFT", 10, 0)
    selfRow.rank:SetWidth(56)
    selfRow.rank:SetJustifyH("LEFT")
    selfRow.rank:SetTextColor(1.0, 0.84, 0.29)

    selfRow.name = selfRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selfRow.name:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    selfRow.name:SetPoint("LEFT", selfRow.rank, "RIGHT", 6, 0)
    selfRow.name:SetPoint("RIGHT", selfRow, "RIGHT", -250, 0)
    selfRow.name:SetJustifyH("LEFT")

    selfRow.value = selfRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selfRow.value:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    selfRow.value:SetWidth(220)
    selfRow.value:SetPoint("RIGHT", selfRow, "RIGHT", -16, 0)
    selfRow.value:SetJustifyH("RIGHT")
    selfRow.value:SetTextColor(0.8, 0.85, 1.0)

    selfRow:Hide()
    listFrame.selfRow = selfRow

    for i = 1, MAX_ENTRIES do
        local row = CreateFrame("Frame", nil, listFrame)
        row:SetHeight(ROW_H)
        row:SetPoint("LEFT",  listFrame, "LEFT",  10, 0)
        row:SetPoint("RIGHT", listFrame, "RIGHT", -32, 0)
        row:SetPoint("TOP",   listFrame, "TOP",   0, -((i - 1) * ROW_H) - 38)

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rank:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
        row.rank:SetPoint("LEFT", row, "LEFT", 6, 0)
        row.rank:SetWidth(50)
        row.rank:SetJustifyH("LEFT")
        row.rank:SetTextColor(1.0, 0.84, 0.29)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
        row.name:SetPoint("LEFT", row.rank, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -250, 0)
        row.name:SetJustifyH("LEFT")

        row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.value:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
        row.value:SetWidth(220)
        row.value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.value:SetJustifyH("RIGHT")
        row.value:SetTextColor(0.8, 0.85, 1.0)

        row:Hide()
        rowFrames[i] = row
    end
    scroll:SetScript("OnSizeChanged", function() RefreshList() end)

    ApplyDropdownVisibility()
    SendServer("tokens")
    return panel
end

if PA and PA.RegisterModule then
    PA:RegisterModule("Leaderboard", "Leaderboard", function() end, {
        subtitle = "Top players by tokens, prestiges, speedrun, raid times.",
    })
    PA:RegisterTabContent("Leaderboard", BuildLeaderboardTab)
end

local function RegisterLeaderboardHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralLeaderboard", {})

    ClientHandler.Rows = function(_, cat, entries, err, selfEntry)
        cat = tostring(cat or "")
        if err and err ~= "" then
            results[cat] = {}
            lastErr[cat] = err
        else
            results[cat] = (type(entries) == "table") and entries or {}
            lastErr[cat] = nil
        end
        selfEntries[cat] = (type(selfEntry) == "table") and selfEntry or nil
        building[cat] = false
        if LB._RefreshList then LB._RefreshList() end
        if listFrame and listFrame.loadingOverlay then
            listFrame.loadingOverlay:Hide()
        end
    end

    return true
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:SetScript("OnEvent", function(self)
    if RegisterLeaderboardHandlers() then
        self:UnregisterAllEvents()
    end
end)
