
local PA = ProjectAstral
local UI = PA.UI

local DEFAULTS = {
    scale            = 1.0,
    fontScale        = 1.0,   -- text-only size, independent of window scale
    opacity          = 1.0,
    themeColor       = { 0.233, 0.353, 1.0 },   -- "Astral" (UI.ASTRAL_THEME): the unified navy look
    showMinimap      = true,
    defaultTab       = "skills",
    rememberLastTab  = true,
    autoFuse          = false,  -- Gem Fusion: auto-fuse stash gems
    autoFuseMaxTier   = 8,      -- ...up to this tier (2-8)
    disenchantAutoDeposit = true, -- Astral Table: move gems/scrolls from bags to the Gem Stash
    reagentAutoDeposit    = true, -- Reagent Bank: send bag reagents to the bank automatically
    autoAcceptQuests      = false,
    autoTurnInQuests      = false,
    autoLoot              = false,
    tokenTracker = {                -- on-screen Token Tracker (TokenTracker.lua); x/y set when moved
        shown        = true,
        locked       = false,
        scale        = 1.0,
        showOrbs     = false,
        style        = "detailed",  -- "detailed" (with session line) or "compact"
        font         = "Fonts\\FRIZQT__.TTF",
        size         = 15,
        textColor    = { 1, 1, 1 },
        outline      = "OUTLINE",   -- "OUTLINE", "THICKOUTLINE" or "NONE"
        outlineColor = { 0, 0, 0 }, -- text shadow colour
        opacity      = 0.88,        -- background (0 = text only)
    },
    lastTab          = nil,
    posX             = nil,
    posY             = nil,
    winW             = nil,     -- hub size from the resize grip (nil = fit screen)
    winH             = nil,
    fullscreen       = false,
    worldchatJoined  = true,
    minimapAngle     = 225,
    gainPopup = {
        enabled  = true,
        width    = 280,
        height   = 46,
        anchor   = "BOTTOMRIGHT",
        offsetX  = -30,
        offsetY  = 180,
        holdTime = 3.0,
        colors = {
            tokens  = { 0.35, 0.90, 0.70 },
            orbs    = { 0.55, 0.85, 1.00 },
            gems    = { 0.75, 0.55, 0.95 },
            warn    = { 1.00, 0.75, 0.35 },
            error   = { 1.00, 0.45, 0.45 },
        },
    },
}

PA.Settings = setmetatable({}, {
    __index = function(_, k) return DEFAULTS[k] end,
})

local function DeepBackfill(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            DeepBackfill(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

local function LoadSettings()
    ProjectAstralSettings = ProjectAstralSettings or {}
    DeepBackfill(ProjectAstralSettings, DEFAULTS)
    PA.Settings = ProjectAstralSettings
end

local function SaveSetting(key, value)
    if not ProjectAstralSettings then return end
    ProjectAstralSettings[key] = value
    PA.Settings[key] = value
end
PA.SaveSetting = SaveSetting

local function ApplyScale()
    local f = PA.mainFrame
    if not f then return end
    f:SetScale(PA.Settings.scale or 1.0)
    -- column count and window size depend on scale
    if f.Relayout and f.sections and f:IsShown() then
        f:Relayout()
        f:SetScrollInstant(f._scroll or 0)
    end
end

local function ApplyFontScale()
    PA.Settings.fontScale = math.max(0.7, math.min(1.3,
        tonumber(PA.Settings.fontScale) or 1.0))
    if PA.UI and PA.UI.SetFontScale then
        PA.UI.SetFontScale(PA.Settings.fontScale)
    end
end

local function ApplyOpacity()
    local f = PA.mainFrame
    if not f then return end
    -- UI.AnimatedShow fades the hub in to this each time it opens (it used to fade to 1)
    f.__paTargetAlpha = PA.Settings.opacity or 1.0
    f:SetAlpha(f.__paTargetAlpha)
end

local function ApplyPosition()
    local f = PA.mainFrame
    if not f then return end
    f:ClearAllPoints()
    if PA.Settings.posX and PA.Settings.posY then
        -- CENTER-to-CENTER must match OnDragStop's GetPoint anchor.
        f:SetPoint("CENTER", UIParent, "CENTER",
                   PA.Settings.posX, PA.Settings.posY)
    else
        f:SetPoint("CENTER")
    end
end

local function ApplyMinimap()
    if PA.MinimapButton and PA.MinimapButton.SetVisible then
        PA.MinimapButton.SetVisible(PA.Settings.showMinimap)
    end
end

local function ApplySettings()
    if UI.ApplyThemeColor then UI.ApplyThemeColor(PA.Settings.themeColor) end
    ApplyScale()
    ApplyFontScale()
    ApplyOpacity()
    ApplyPosition()
    ApplyMinimap()
end

PA.ApplyScale     = ApplyScale
PA.ApplyFontScale = ApplyFontScale
PA.ApplyOpacity   = ApplyOpacity
PA.ApplyPosition  = ApplyPosition
PA.ApplyMinimap   = ApplyMinimap
PA.ApplySettings  = ApplySettings

local function HookPositionPersist()
    local f = PA.mainFrame
    if not f or f._posHooked then return end
    f._posHooked = true
    f:HookScript("OnDragStop", function(self)
        if self._fullscreen then return end   -- keep the windowed position
        local _, _, _, x, y = self:GetPoint()
        SaveSetting("posX", x)
        SaveSetting("posY", y)
    end)
end
PA.HookPositionPersist = HookPositionPersist

local function BuildSettingsTab(panel)
    -- Three columns side by side when the card is wide, stacked when it's narrow.
    -- MainMenu sizes this card with the same 900px rule (PANEL_SIZE.Settings).
    -- The hub page is the scroller, so there's no inner scroll frame.
    local WIDE_MIN, COL_GAP = 900, 12
    -- colA grew by 60px (new "Text size" slider); B and C shift down to match
    -- MainMenu's PANEL_SIZE.Settings.h (+60 on both its wide/narrow branches).
    local STACK = { { y = 0, h = 680 }, { y = 692, h = 482 }, { y = 1186, h = 412 } }

    local f = CreateFrame("Frame", nil, panel)
    f:SetAllPoints(panel)

    local cols = {}
    for i = 1, 3 do
        local col = CreateFrame("Frame", nil, f)
        col:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 10,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        col:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.32))
        col:SetBackdropBorderColor(0.18, 0.18, 0.26, 0.75)
        if UI.Outline then UI.Outline(f, col, "BORDER", UI.Nav.edge, 1) end
        cols[i] = col
    end
    local colA, colB, colC = cols[1], cols[2], cols[3]

    local function LayoutColumns()
        local w = panel:GetWidth() or 0
        if w <= 0 then return end
        for i, col in ipairs(cols) do
            col:ClearAllPoints()
            if w >= WIDE_MIN then
                local cw = math.floor((w - COL_GAP * 2) / 3)
                local x  = (i - 1) * (cw + COL_GAP)
                col:SetPoint("TOPLEFT",    f, "TOPLEFT",    x, 0)
                col:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 0)
                col:SetWidth(cw)
            else
                col:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -STACK[i].y)
                col:SetSize(w, STACK[i].h)
            end
        end
    end

    -- MakeSectionDivider runs its rule to the parent's right edge; keep it in its column
    local function FixRule(section, col)
        section.rule:ClearAllPoints()
        section.rule:SetPoint("TOPLEFT", section, "BOTTOMLEFT", 0, -3)
        section.rule:SetPoint("RIGHT",   col,     "RIGHT",     -14, 0)
    end

    local function StyleSection(section)
        section:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    end
    local function StyleSliderEnds(slider)
        for _, suffix in ipairs({ "Low", "High" }) do
            local text = _G[slider:GetName() .. suffix]
            if text then text:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end
        end
    end
    local function StyleButton(button, width, height)
        button:SetSize(width, height)
        button.text:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    end
    local function StyleCheckText(checkButton, size)
        local text = _G[checkButton:GetName() .. "Text"]
        if text then
            text:SetFont("Fonts\\FRIZQT__.TTF", size or 13, "OUTLINE")
            text:SetTextColor(unpack(UI.Color.textPrimary))
        end
    end

    local s1 = UI.MakeSectionDivider(f, "GENERAL",
        { "TOPLEFT", colA, "TOPLEFT", 14, -14 })
    StyleSection(s1)
    FixRule(s1, colA)

    local scaleLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleLbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    scaleLbl:SetPoint("TOPLEFT", s1, "BOTTOMLEFT", 0, -14)
    scaleLbl:SetText("Window scale")
    local scaleVal = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    scaleVal:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    scaleVal:SetPoint("LEFT", scaleLbl, "RIGHT", 8, 0)
    scaleVal:SetTextColor(unpack(UI.Nav.muted))
    scaleVal:SetText(string.format("%.2f", PA.Settings.scale))

    local SCALE_STEP = 0.01

    local function snapStep(v, step)
        local inv = 1 / step
        return math.floor(v * inv + 0.5) / inv
    end

    local scaleSlider = CreateFrame("Slider", "PASettingScale", f,
        "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", scaleLbl, "BOTTOMLEFT", 0, -8)
    scaleSlider:SetWidth(220)
    scaleSlider:SetMinMaxValues(0.6, 2.0)   -- same range as Shift+drag on the hub grip
    scaleSlider:SetValueStep(SCALE_STEP)
    scaleSlider:SetValue(PA.Settings.scale)
    _G[scaleSlider:GetName() .. "Low"]:SetText("0.6")
    _G[scaleSlider:GetName() .. "High"]:SetText("2.0")
    _G[scaleSlider:GetName() .. "Text"]:SetText("")
    StyleSliderEnds(scaleSlider)

    scaleSlider._pending = PA.Settings.scale
    scaleSlider:SetScript("OnValueChanged", function(self, v)
        v = snapStep(v, SCALE_STEP)
        self._pending = v
        scaleVal:SetText(string.format("%.2f", v))
    end)
    local function commitScale(self)
        SaveSetting("scale", self._pending)
        ApplyScale()
    end
    -- no mouse-wheel on sliders: scrolling the page past them must not change values
    scaleSlider:SetScript("OnMouseUp",  commitScale)

    local fontLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontLbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    fontLbl:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -22)
    fontLbl:SetText("Text size")
    local fontVal = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    fontVal:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    fontVal:SetPoint("LEFT", fontLbl, "RIGHT", 8, 0)
    fontVal:SetTextColor(unpack(UI.Nav.muted))
    fontVal:SetText(string.format("%.2f", PA.Settings.fontScale))

    local FONT_STEP = 0.05

    local fontSlider = CreateFrame("Slider", "PASettingFontScale", f,
        "OptionsSliderTemplate")
    fontSlider:SetPoint("TOPLEFT", fontLbl, "BOTTOMLEFT", 0, -8)
    fontSlider:SetWidth(220)
    fontSlider:SetMinMaxValues(0.7, 1.3)
    fontSlider:SetValueStep(FONT_STEP)
    fontSlider:SetValue(PA.Settings.fontScale)
    _G[fontSlider:GetName() .. "Low"]:SetText("0.7")
    _G[fontSlider:GetName() .. "High"]:SetText("1.3")
    _G[fontSlider:GetName() .. "Text"]:SetText("")
    StyleSliderEnds(fontSlider)

    fontSlider._pending = PA.Settings.fontScale
    fontSlider:SetScript("OnValueChanged", function(self, v)
        v = snapStep(v, FONT_STEP)
        self._pending = v
        fontVal:SetText(string.format("%.2f", v))
        -- live preview: text resizes as the slider moves, saved on release
        if UI.SetFontScale then UI.SetFontScale(v) end
    end)
    local function commitFontScale(self)
        SaveSetting("fontScale", self._pending)
    end
    fontSlider:SetScript("OnMouseUp", commitFontScale)

    local opLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    opLbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    opLbl:SetPoint("TOPLEFT", fontSlider, "BOTTOMLEFT", 0, -22)
    opLbl:SetText("Window opacity")
    local opVal = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    opVal:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    opVal:SetPoint("LEFT", opLbl, "RIGHT", 8, 0)
    opVal:SetTextColor(unpack(UI.Nav.muted))
    opVal:SetText(string.format("%.2f", PA.Settings.opacity))

    local OPACITY_STEP = 0.01
    local opSlider = CreateFrame("Slider", "PASettingOpacity", f,
        "OptionsSliderTemplate")
    opSlider:SetPoint("TOPLEFT", opLbl, "BOTTOMLEFT", 0, -8)
    opSlider:SetWidth(220)
    opSlider:SetMinMaxValues(0.5, 1.0)
    opSlider:SetValueStep(OPACITY_STEP)
    opSlider:SetValue(PA.Settings.opacity)
    _G[opSlider:GetName() .. "Low"]:SetText("0.5")
    _G[opSlider:GetName() .. "High"]:SetText("1.0")
    _G[opSlider:GetName() .. "Text"]:SetText("")
    StyleSliderEnds(opSlider)

    opSlider._pending = PA.Settings.opacity
    opSlider:SetScript("OnValueChanged", function(self, v)
        v = snapStep(v, OPACITY_STEP)
        self._pending = v
        opVal:SetText(string.format("%.2f", v))
        PA.Settings.opacity = v
        ApplyOpacity()
    end)
    opSlider:SetScript("OnMouseUp", function(self)
        SaveSetting("opacity", self._pending)
    end)

    local themeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    themeLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    themeLabel:SetPoint("TOPLEFT", opSlider, "BOTTOMLEFT", 0, -22)
    themeLabel:SetText("Global UI color")

    local themeChoices = {
        { name = "Astral", color = { 0.233, 0.353, 1.0 } },
        { name = "Cosmic", color = { 0.65, 0.55, 0.95 } },
        { name = "Red",    color = { 0.92, 0.20, 0.28 } },
        { name = "Blue",   color = { 0.25, 0.55, 0.98 } },
        { name = "Green",  color = { 0.16, 0.76, 0.43 } },
        { name = "Gold",   color = { 1.00, 0.63, 0.18 } },
        { name = "Teal",   color = { 0.12, 0.72, 0.78 } },
    }
    local themeSwatches = {}
    local themeStatus = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    themeStatus:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", 0, -42)
    themeStatus:SetWidth(360)
    themeStatus:SetText("Tints every panel, border and highlight. Reload UI to apply it everywhere.")
    themeStatus:SetTextColor(unpack(UI.Nav.muted))

    local function SetThemeColor(color)
        local saved = {
            math.max(0, math.min(1, tonumber(color[1]) or 0.233)),
            math.max(0, math.min(1, tonumber(color[2]) or 0.353)),
            math.max(0, math.min(1, tonumber(color[3]) or 1.0)),
        }
        SaveSetting("themeColor", saved)
        if UI.ApplyThemeColor then UI.ApplyThemeColor(saved) end
        themeStatus:SetText("|cffffd970Color saved.|r Click Reload UI to apply it to the whole UI.")
    end

    local function MakeThemeSwatch(index, choice)
        local swatch = CreateFrame("Button", nil, colA)
        swatch:SetSize(22, 22)
        swatch:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", (index - 1) * 28, -8)
        swatch:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        swatch:SetBackdropColor(unpack(choice.color))
        swatch:SetBackdropBorderColor(unpack(UI.Nav.edgeMid))
        swatch:SetScript("OnClick", function() SetThemeColor(choice.color) end)
        swatch:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(choice.name, 1, 1, 1)
            GameTooltip:Show()
        end)
        swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)
        themeSwatches[index] = swatch
    end
    for index, choice in ipairs(themeChoices) do
        MakeThemeSwatch(index, choice)
    end

    local customTheme = UI.MakeButton(colA, "Custom…", {
        w = 82, h = 26, variant = "secondary",
    })
    customTheme:SetPoint("LEFT", themeSwatches[#themeSwatches], "RIGHT", 6, 0)
    StyleButton(customTheme, 82, 26)
    customTheme:SetScript("OnClick", function()
        local current = PA.Settings.themeColor or DEFAULTS.themeColor
        ColorPickerFrame:Hide()
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { current[1], current[2], current[3] }
        local function ApplyPickerColor()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            SetThemeColor({ r, g, b })
        end
        ColorPickerFrame.func = ApplyPickerColor
        ColorPickerFrame.swatchFunc = ApplyPickerColor
        ColorPickerFrame.cancelFunc = function(previous)
            if type(previous) == "table" and previous[1] then
                SetThemeColor(previous)
            end
        end
        ColorPickerFrame:SetColorRGB(current[1], current[2], current[3])
        ColorPickerFrame:Show()
    end)

    local reloadTheme = UI.MakeButton(colA, "Reload UI", {
        w = 88, h = 26, variant = "gold",
        onClick = function() ReloadUI() end,
    })
    reloadTheme:SetPoint("TOPLEFT", themeStatus, "BOTTOMLEFT", 0, -8)   -- under the hint, clear of the next column
    StyleButton(reloadTheme, 88, 26)

    local s2 = UI.MakeSectionDivider(f, "BEHAVIOR",
        { "TOPLEFT", reloadTheme, "BOTTOMLEFT", 0, -22 })
    StyleSection(s2)
    FixRule(s2, colA)

    local function MakeCheckbox(parent, label, tooltip, key, anchorTo)
        local cb = CreateFrame("CheckButton", "PASetting_" .. key, parent,
            "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
        cb:SetChecked(PA.Settings[key] and true or false)
        _G[cb:GetName() .. "Text"]:SetText(label)
        StyleCheckText(cb)
        cb.tooltipText = tooltip
        cb:SetScript("OnClick", function(self)
            local v = self:GetChecked() and true or false
            SaveSetting(key, v)
            if key == "showMinimap" then ApplySettings() end
        end)
        return cb
    end

    local cb2 = MakeCheckbox(f, "Show Astralhub minimap button",
        "Toggle the minimap launcher icon. /astral always works.",
        "showMinimap", s2)
    local cb4 = MakeCheckbox(f, "Reopen the tab I was on",
        "Open the hub on the tab you last used; otherwise use the tab below.",
        "rememberLastTab", cb2)
    local cbAutoAccept = MakeCheckbox(f, "Automatically accept quests",
        "Accept available quests immediately. Disabled by default.",
        "autoAcceptQuests", cb4)
    local cbAutoTurnIn = MakeCheckbox(f, "Automatically turn in quests",
        "Complete quests and choose the first reward immediately. Disabled by default.",
        "autoTurnInQuests", cbAutoAccept)
    local cbAutoLoot = MakeCheckbox(f, "Automatically loot without the loot window",
        "Loot every available item immediately and close the loot window. Disabled by default.",
        "autoLoot", cbAutoTurnIn)

    local ddLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ddLbl:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    ddLbl:SetPoint("TOPLEFT", cbAutoLoot, "BOTTOMLEFT", 4, -12)
    ddLbl:SetText("Start on tab")

    local dd = CreateFrame("Frame", "PASettingDefaultTab", f,
        "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", ddLbl, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(dd, 200)
    if _G[dd:GetName() .. "Text"] then
        _G[dd:GetName() .. "Text"]:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    end

    -- older saves hold a module name (or a removed one); HubTabFor maps both
    local function TabLabel(id)
        local t = PA.HubTabFor and PA.HubTabFor(id)
        return (t and t.label) or "Skills"
    end

    UIDropDownMenu_Initialize(dd, function(self)
        for _, t in ipairs(PA.HubTabs or {}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = t.label
            info.value = t.id
            info.checked = (PA.HubTabFor(PA.Settings.defaultTab) == t)
            info.func = function()
                SaveSetting("defaultTab", t.id)
                UIDropDownMenu_SetSelectedValue(dd, t.id)
                UIDropDownMenu_SetText(dd, t.label)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(dd, PA.Settings.defaultTab)
    UIDropDownMenu_SetText(dd, TabLabel(PA.Settings.defaultTab))

    -- column 3, below the popup colour swatches (built further down)
    local sWC = UI.MakeSectionDivider(f, "WORLD CHAT",
        { "TOPLEFT", colC, "TOPLEFT", 14, -130 })
    StyleSection(sWC)
    FixRule(sWC, colC)

    local cbWC = CreateFrame("CheckButton", "PASetting_worldchatJoined", f,
        "InterfaceOptionsCheckButtonTemplate")
    cbWC:SetPoint("TOPLEFT", sWC, "BOTTOMLEFT", 0, -6)
    cbWC:SetChecked(PA.Settings.worldchatJoined and true or false)
    _G[cbWC:GetName() .. "Text"]:SetText("Auto-join World chat")
    StyleCheckText(cbWC)
    cbWC.tooltipText = "Joins the cross-faction World channel on login. Untick to leave."
    cbWC:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        SaveSetting("worldchatJoined", v)
        if v and PA.JoinWorldChat then PA.JoinWorldChat()
        elseif not v and PA.LeaveWorldChat then PA.LeaveWorldChat() end
    end)

    local sGP = UI.MakeSectionDivider(f, "GAIN POPUP",
        { "TOPLEFT", colB, "TOPLEFT", 14, -14 })
    StyleSection(sGP)
    FixRule(sGP, colB)

    local cbGP = CreateFrame("CheckButton", "PASetting_gainPopupEnabled", f,
        "InterfaceOptionsCheckButtonTemplate")
    cbGP:SetPoint("TOPLEFT", sGP, "BOTTOMLEFT", 0, -6)
    cbGP:SetChecked(PA.Settings.gainPopup.enabled and true or false)
    _G[cbGP:GetName() .. "Text"]:SetText("Enable gain popup")
    StyleCheckText(cbGP)
    cbGP.tooltipText = "Show a bottom-corner popup on Token / Orb / Prestige gains."
    cbGP:SetScript("OnClick", function(self)
        PA.Settings.gainPopup.enabled = self:GetChecked() and true or false
    end)

    local previewBtn = UI.MakeButton(f, "Preview popup", {
        w = 160, h = 30, variant = "secondary",
        onClick = function()
            if not (PA.UI and PA.UI.GainPopup) then return end
            PA.UI.GainPopup("+250 Tokens (preview)",       "tokens")
            PA.UI.GainPopup("+5 Orbs of Destiny (preview)", "orbs")
            PA.UI.GainPopup("Gem drop: [Sample Gem] (preview)", "gems",
                { fontSize = 10 })
            PA.UI.GainPopup("Preview warning message",      "warn")
            PA.UI.GainPopup("Preview error message",        "error")
        end,
    })
    StyleButton(previewBtn, 160, 30)

    local dragAnchor
    local function BuildDragAnchor()
        if dragAnchor then return dragAnchor end
        local a = CreateFrame("Frame", "PA_GainPopupDragAnchor", UIParent)
        a.__paUnified = true   -- unified look: Theme.lua keeps its navy
        a:SetFrameStrata("FULLSCREEN_DIALOG")
        a:SetMovable(true)
        a:EnableMouse(true)
        a:RegisterForDrag("LeftButton")
        a:SetClampedToScreen(true)
        a:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        a:SetBackdropColor(0.10, 0.35, 0.60, 0.55)
        a:SetBackdropBorderColor(0.55, 0.85, 1.0, 1.0)

        local title = a:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
        title:SetPoint("CENTER", 0, 6)
        title:SetText("|cffFFD700Gain Popup|r")
        local hint = a:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        hint:SetPoint("CENTER", 0, -8)
        hint:SetText("Drag to reposition")
        hint:SetTextColor(0.85, 0.90, 1.0)

        a:SetScript("OnDragStart", a.StartMoving)
        a:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
            local cx, cy = self:GetCenter()
            local right  = cx > uw / 2
            local top    = cy > uh / 2
            local anchor = (top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT")

            local ax, ay
            if anchor == "BOTTOMRIGHT" then
                ax = self:GetRight() - uw
                ay = self:GetBottom()
            elseif anchor == "BOTTOMLEFT" then
                ax = self:GetLeft()
                ay = self:GetBottom()
            elseif anchor == "TOPRIGHT" then
                ax = self:GetRight() - uw
                ay = self:GetTop()  - uh
            else
                ax = self:GetLeft()
                ay = self:GetTop()  - uh
            end
            PA.Settings.gainPopup.anchor  = anchor
            PA.Settings.gainPopup.offsetX = math.floor(ax + 0.5)
            PA.Settings.gainPopup.offsetY = math.floor(ay + 0.5)
            self:ClearAllPoints()
            self:SetPoint(anchor, UIParent, anchor,
                PA.Settings.gainPopup.offsetX, PA.Settings.gainPopup.offsetY)
            if PA._GainPopupRefreshControls then PA._GainPopupRefreshControls() end
            if PA._RelayoutGainPopups then PA._RelayoutGainPopups() end
        end)

        a:Hide()
        dragAnchor = a
        return a
    end

    local function SyncDragAnchorSize()
        if not dragAnchor then return end
        dragAnchor:SetSize(PA.Settings.gainPopup.width,
                           PA.Settings.gainPopup.height)
        dragAnchor:ClearAllPoints()
        dragAnchor:SetPoint(PA.Settings.gainPopup.anchor, UIParent,
            PA.Settings.gainPopup.anchor,
            PA.Settings.gainPopup.offsetX, PA.Settings.gainPopup.offsetY)
    end

    local positionBtn = UI.MakeButton(f, "Position popup", {
        w = 160, h = 30, variant = "gold",
        onClick = function(self)
            local a = BuildDragAnchor()
            if a:IsShown() then
                a:Hide()
                self:SetLabel("Position popup")
            else
                SyncDragAnchorSize()
                a:Show()
                self:SetLabel("Done positioning")
            end
        end,
    })
    StyleButton(positionBtn, 160, 30)
    positionBtn:SetPoint("TOPLEFT", cbGP, "BOTTOMLEFT", 0, -14)
    previewBtn:SetPoint("TOPLEFT", positionBtn, "BOTTOMLEFT", 0, -8)   -- stacked under Position popup

    local function MakeGPSlider(label, key, minV, maxV, step, anchor, yGap, tooltip, xShift)
        local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        lbl:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (xShift or 0), -(yGap or 8))
        lbl:SetText(label)
        local val = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        val:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        val:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        val:SetTextColor(unpack(UI.Nav.muted))

        local sname = "PASetting_GP_" .. key
        local sld = CreateFrame("Slider", sname, f, "OptionsSliderTemplate")
        sld:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -6)
        sld:SetWidth(220)
        sld:SetMinMaxValues(minV, maxV)
        sld:SetValueStep(step)
        sld:SetValue(PA.Settings.gainPopup[key])
        _G[sname .. "Low"]:SetText(tostring(minV))
        _G[sname .. "High"]:SetText(tostring(maxV))
        _G[sname .. "Text"]:SetText("")
        StyleSliderEnds(sld)
        val:SetText(tostring(PA.Settings.gainPopup[key]))
        if tooltip then sld.tooltipText = tooltip end

        local function snap(v) return math.floor(v / step + 0.5) * step end
        local function repaint(v)
            val:SetText(step >= 1 and tostring(math.floor(v)) or string.format("%.1f", v))
        end
        sld:SetScript("OnValueChanged", function(self, v)
            v = snap(v)
            PA.Settings.gainPopup[key] = v
            repaint(v)
            SyncDragAnchorSize()
            if PA._RelayoutGainPopups then PA._RelayoutGainPopups() end
        end)
        sld._repaint = function() sld:SetValue(PA.Settings.gainPopup[key]); repaint(PA.Settings.gainPopup[key]) end
        return sld
    end

    local widthSld  = MakeGPSlider("Width",   "width",   180, 500, 5,   previewBtn, 20,
                                    "Popup width in pixels.")
    local heightSld = MakeGPSlider("Height",  "height",   32,  96, 2,   widthSld,    18,
                                    "Popup height in pixels.")
    local holdSld   = MakeGPSlider("Hold time (s)", "holdTime", 1.0, 8.0, 0.5, heightSld, 18,
                                    "How long the popup stays before fading out.")

    local anchorLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    anchorLbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    anchorLbl:SetPoint("TOPLEFT", holdSld, "BOTTOMLEFT", 0, -18)
    anchorLbl:SetText("Screen anchor")

    local ANCHOR_OPTIONS = {
        { label = "Bottom-right", value = "BOTTOMRIGHT" },
        { label = "Bottom-left",  value = "BOTTOMLEFT"  },
        { label = "Top-right",    value = "TOPRIGHT"    },
        { label = "Top-left",     value = "TOPLEFT"     },
    }

    local anchorDd = CreateFrame("Frame", "PASetting_GP_anchor", f,
        "UIDropDownMenuTemplate")
    anchorDd:SetPoint("TOPLEFT", anchorLbl, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(anchorDd, 180)
    if _G[anchorDd:GetName() .. "Text"] then
        _G[anchorDd:GetName() .. "Text"]:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    end
    UIDropDownMenu_Initialize(anchorDd, function(self)
        for _, opt in ipairs(ANCHOR_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = opt.label
            info.value = opt.value
            info.checked = (PA.Settings.gainPopup.anchor == opt.value)
            info.func = function()
                PA.Settings.gainPopup.anchor = opt.value
                UIDropDownMenu_SetSelectedValue(anchorDd, opt.value)
                SyncDragAnchorSize()
                if PA._RelayoutGainPopups then PA._RelayoutGainPopups() end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetSelectedValue(anchorDd, PA.Settings.gainPopup.anchor)

    local offXSld = MakeGPSlider("Offset X (px)", "offsetX", -400, 400, 5, anchorDd, 24,
                                  "Horizontal offset from the anchor corner. Also set by 'Position popup'.", 16)
    local offYSld = MakeGPSlider("Offset Y (px)", "offsetY",    0, 600, 5, offXSld,  18,
                                  "Vertical offset from the anchor corner. Also set by 'Position popup'.")

    PA._GainPopupRefreshControls = function()
        widthSld._repaint()
        heightSld._repaint()
        holdSld._repaint()
        UIDropDownMenu_SetSelectedValue(anchorDd, PA.Settings.gainPopup.anchor)
        offXSld._repaint()
        offYSld._repaint()
    end

    local sCol = UI.MakeSectionDivider(f, "POPUP COLOURS",
        { "TOPLEFT", colC, "TOPLEFT", 14, -14 })
    StyleSection(sCol)
    FixRule(sCol, colC)

    local colorHdr = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    colorHdr:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    colorHdr:SetPoint("TOPLEFT", sCol, "BOTTOMLEFT", 0, -10)
    colorHdr:SetText("Click a swatch to change its colour.")

    local function MakeSwatch(kind, label, col, row)
        local wrap = CreateFrame("Frame", nil, f)
        wrap:SetSize(100, 24)
        wrap:SetPoint("TOPLEFT", colorHdr, "BOTTOMLEFT",
            col * 110, -8 - row * 30)   -- three per row fits a column

        local sw = CreateFrame("Button", nil, wrap)
        sw:SetSize(28, 20)
        sw:SetPoint("LEFT", wrap, "LEFT", 0, 0)
        sw:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        local c = PA.Settings.gainPopup.colors[kind]
        sw:SetBackdropColor(c[1], c[2], c[3], 1)
        sw:SetBackdropBorderColor(0.6, 0.6, 0.75, 1)

        local lbl = wrap:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
        lbl:SetPoint("LEFT", sw, "RIGHT", 8, 0)
        lbl:SetText(label)
        lbl:SetTextColor(unpack(UI.Color.textPrimary))

        -- ColorPickerFrame contract: previousValues MUST be positional {r,g,b},
        sw:SetScript("OnClick", function(self)
            local cur = PA.Settings.gainPopup.colors[kind]
            ColorPickerFrame:Hide()
            ColorPickerFrame.hasOpacity  = false
            ColorPickerFrame.previousValues = { cur[1], cur[2], cur[3] }
            local function apply()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                PA.Settings.gainPopup.colors[kind] = { r, g, b }
                self:SetBackdropColor(r, g, b, 1)
            end
            ColorPickerFrame.func       = apply
            ColorPickerFrame.swatchFunc = apply
            ColorPickerFrame.cancelFunc = function(prev)
                if type(prev) == "table" and prev[1] then
                    PA.Settings.gainPopup.colors[kind] = { prev[1], prev[2], prev[3] }
                    self:SetBackdropColor(prev[1], prev[2], prev[3], 1)
                end
            end
            ColorPickerFrame:SetColorRGB(cur[1], cur[2], cur[3])
            ColorPickerFrame:Show()
        end)
        return sw
    end

    MakeSwatch("tokens", "Tokens", 0, 0)
    MakeSwatch("orbs",   "Orbs",   1, 0)
    MakeSwatch("gems",   "Gems",   2, 0)
    MakeSwatch("warn",   "Warn",   0, 1)
    MakeSwatch("error",  "Error",  1, 1)

    local sTT = UI.MakeSectionDivider(f, "TOKEN TRACKER",
        { "TOPLEFT", cbWC, "BOTTOMLEFT", 4, -22 })
    StyleSection(sTT)
    FixRule(sTT, colC)

    local function TrackerCheck(name, label, tooltip, anchor, key, apply)
        local cb = CreateFrame("CheckButton", name, f, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        _G[name .. "Text"]:SetText(label)
        StyleCheckText(cb)
        cb.tooltipText = tooltip
        local tt = PA.Settings.tokenTracker
        cb:SetChecked(type(tt) == "table" and tt[key] and true or false)
        cb:SetScript("OnClick", function(self) apply(self:GetChecked() and true or false) end)
        return cb
    end

    -- names are read by TokenTracker.lua to keep these in step with its right-click menu
    local cbTTShow = TrackerCheck("PASettingTokenTrackerShown", "Show token tracker",
        "A small window with your Tokens and what you've earned this session. It stays on screen with the hub closed. /tokentracker also toggles it.",
        sTT, "shown",
        function(on) if PA.TokenTracker then PA.TokenTracker.SetShown(on) end end)
    local cbTTLock = TrackerCheck("PASettingTokenTrackerLocked", "Lock tracker position",
        "Stops the tracker from being moved or resized. Right-click the tracker for more options.",
        cbTTShow, "locked",
        function(on) if PA.TokenTracker then PA.TokenTracker.SetLocked(on) end end)

    local ttOptions = UI.MakeButton(f, "Tracker options…", {
        w = 170, h = 30, variant = "secondary",
        onClick = function()
            if PA.TokenTracker and PA.TokenTracker.OpenOptions then PA.TokenTracker.OpenOptions() end
        end,
    })
    StyleButton(ttOptions, 170, 30)
    ttOptions:SetPoint("TOPLEFT", cbTTLock, "BOTTOMLEFT", 4, -8)

    local s3 = UI.MakeSectionDivider(f, "RESET",
        { "TOPLEFT", ttOptions, "BOTTOMLEFT", 0, -22 })
    StyleSection(s3)
    FixRule(s3, colC)

    local resetPos = UI.MakeButton(f, "Reset window size & position", {
        w = 270, h = 32, variant = "secondary",
        onClick = function()
            SaveSetting("posX", nil)
            SaveSetting("posY", nil)
            SaveSetting("winW", nil)
            SaveSetting("winH", nil)
            local mf = PA.mainFrame
            if mf and mf.SetFullscreen then
                mf._reqW, mf._reqH = nil, nil
                mf:SetFullscreen(false)
            end
            ApplySettings()
        end,
    })
    StyleButton(resetPos, 270, 32)
    resetPos:SetPoint("TOPLEFT", s3, "BOTTOMLEFT", 0, -8)

    local resetAll = UI.MakeButton(f, "Reset ALL settings to defaults", {
        w = 280, h = 32, variant = "danger",
        onClick = function()
            -- copy nested tables: saving DEFAULTS' own tables let later changes (chat
            -- opacity, popup colours, tracker options) edit the defaults themselves
            local function Copy(v)
                if type(v) ~= "table" then return v end
                local t = {}
                for k2, v2 in pairs(v) do t[k2] = Copy(v2) end
                return t
            end
            for k, v in pairs(DEFAULTS) do
                SaveSetting(k, Copy(v))
            end
            for index, choice in ipairs(themeChoices) do
                themeSwatches[index]:SetBackdropColor(unpack(choice.color))
            end
            themeStatus:SetText("Default theme restored. Reload for a full reskin.")
            scaleSlider:SetValue(DEFAULTS.scale)
            fontSlider:SetValue(DEFAULTS.fontScale)
            if UI.SetFontScale then UI.SetFontScale(DEFAULTS.fontScale) end
            opSlider:SetValue(DEFAULTS.opacity)
            cb2:SetChecked(DEFAULTS.showMinimap)
            cb4:SetChecked(DEFAULTS.rememberLastTab)
            cbAutoAccept:SetChecked(DEFAULTS.autoAcceptQuests)
            cbAutoTurnIn:SetChecked(DEFAULTS.autoTurnInQuests)
            cbAutoLoot:SetChecked(DEFAULTS.autoLoot)
            cbWC:SetChecked(DEFAULTS.worldchatJoined)
            -- gain popup and Token Tracker controls showed the old values until /reload
            cbGP:SetChecked(DEFAULTS.gainPopup.enabled)
            if PA._GainPopupRefreshControls then PA._GainPopupRefreshControls() end
            if PA._RelayoutGainPopups then PA._RelayoutGainPopups() end
            cbTTShow:SetChecked(DEFAULTS.tokenTracker.shown)
            cbTTLock:SetChecked(DEFAULTS.tokenTracker.locked)
            if PA.TokenTracker and PA.TokenTracker.ApplyAll then PA.TokenTracker.ApplyAll() end
            UIDropDownMenu_SetSelectedValue(dd, DEFAULTS.defaultTab)
            UIDropDownMenu_SetText(dd, TabLabel(DEFAULTS.defaultTab))
            ApplySettings()
        end,
    })
    StyleButton(resetAll, 280, 32)
    resetAll:SetPoint("TOPLEFT", resetPos, "BOTTOMLEFT", 0, -8)

    panel:SetScript("OnSizeChanged", LayoutColumns)
    LayoutColumns()
end

local function ToggleSettings()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "Settings" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("Settings")
        if mf._tabBar then mf._tabBar:SelectTab("Settings") end
        if mf._tabBarFooter then mf._tabBarFooter:SelectTab("Settings") end
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    LoadSettings()
    ApplySettings()
    HookPositionPersist()
end)

PA:RegisterModule("Settings", "Settings", ToggleSettings, {
    placement = "footer",
    subtitle  = "Configure the Astralhub UI — scale, opacity, start tab, behaviour.",
})
PA:RegisterTabContent("Settings", BuildSettingsTab)
