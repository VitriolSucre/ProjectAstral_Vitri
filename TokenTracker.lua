
local PA = ProjectAstral
local UI = PA.UI

-- Token Tracker: a small Astral-styled window with your Tokens (and optionally Orbs
-- of Destiny) plus what you've earned this session. It lives on UIParent, so it
-- stays on screen with the hub closed.
--   drag: move · corner grip: resize · right-click: menu
--   /tokentracker: show/hide · /tokentracker options (or /ttc): appearance options
--
-- The appearance options (font, size, text/shadow colour, outline style, background
-- opacity, compact look) are adapted from the standalone TokenTracker addon by
-- Seville and rebuilt in the Astral theme.

local SOLID   = "Interface\\Buttons\\WHITE8X8"
local TOKEN_C = { 0.35, 0.90, 0.70 }   -- same dot colours as the hub's currency chips
local ORB_C   = { 0.55, 0.85, 1.00 }
local BASE_W  = 190
local MIN_SCALE, MAX_SCALE = 0.6, 2.0

local FONTS = {
    { name = "Friz Quadrata", val = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  val = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus",      val = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri",        val = "Fonts\\SKURRI.TTF" },
    { name = "Comic Sans",    val = "Fonts\\COMIC.TTF" },
}
local OUTLINES = {
    { name = "Outline",       val = "OUTLINE" },
    { name = "Thick outline", val = "THICKOUTLINE" },
    { name = "No outline",    val = "NONE" },
}
local STYLES = {
    { name = "Detailed", val = "detailed" },   -- values + session line
    { name = "Compact",  val = "compact" },    -- values only
}

-- appearance defaults (mirrors Settings.lua DEFAULTS.tokenTracker)
local DEFAULT_LOOK = {
    style = "detailed", font = "Fonts\\FRIZQT__.TTF", size = 15,
    textColor = { 1, 1, 1 }, outline = "OUTLINE", outlineColor = { 0, 0, 0 },
    opacity = 0.88,
}

PA.TokenTracker = PA.TokenTracker or {}
local TT = PA.TokenTracker

local frame, optionsWin
local session = { startAt = nil, last = nil, lastOrbs = nil, earned = 0, spent = 0, orbsEarned = 0 }
local Refresh, Relayout, ApplyLook

local function CopyLook(key)
    local v = DEFAULT_LOOK[key]
    return type(v) == "table" and { v[1], v[2], v[3] } or v
end

local function Cfg()
    local s = PA.Settings and PA.Settings.tokenTracker
    if type(s) ~= "table" then
        s = { shown = true, locked = false, scale = 1, showOrbs = false }
        if ProjectAstralSettings then ProjectAstralSettings.tokenTracker = s end
    end
    for key in pairs(DEFAULT_LOOK) do
        if s[key] == nil then s[key] = CopyLook(key) end
    end
    return s
end

local function Commas(n)
    local s = tostring(math.floor((n or 0) + 0.5))
    local sign, digits = s:match("^(-?)(%d+)$")
    if not digits then return s end
    local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. out:gsub("^,", "")
end

local function Duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    return string.format("%dm", m)
end

-- keep the Settings tab's and the options window's controls in step with the menu
local function SyncControls()
    local c = Cfg()
    if _G.PASettingTokenTrackerShown  then _G.PASettingTokenTrackerShown:SetChecked(c.shown and true or false) end
    if _G.PASettingTokenTrackerLocked then _G.PASettingTokenTrackerLocked:SetChecked(c.locked and true or false) end
    if optionsWin and optionsWin:IsShown() then optionsWin.SyncAll() end
end

-- ── session tracking ────────────────────────────────────────────────
local function StartSession()
    session.startAt  = time()
    session.last     = PA.prestigeTokens or 0
    session.lastOrbs = PA.orbs or 0
    session.earned, session.spent, session.orbsEarned = 0, 0, 0
end

local function OnWallet()
    local t, o = PA.prestigeTokens or 0, PA.orbs or 0
    if not session.startAt then
        StartSession()   -- the first wallet push after login is the baseline
    else
        local d = t - session.last
        if d > 0 then session.earned = session.earned + d
        elseif d < 0 then session.spent = session.spent - d end
        local od = o - session.lastOrbs
        if od > 0 then session.orbsEarned = session.orbsEarned + od end
        session.last, session.lastOrbs = t, o
    end
    if Refresh then Refresh() end
end

-- ── position / scale ────────────────────────────────────────────────
local function ApplyPosition()
    local c = Cfg()
    frame:SetScale(math.max(MIN_SCALE, math.min(MAX_SCALE, tonumber(c.scale) or 1)))
    frame:ClearAllPoints()
    if c.x and c.y then
        frame:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

-- saved as a CENTER offset in the tracker's own (scaled) units
local function SavePosition()
    local s = frame:GetScale()
    local cx, cy = frame:GetCenter()
    if not cx then return end
    local c = Cfg()
    c.x = cx - UIParent:GetWidth()  / (2 * s)
    c.y = cy - UIParent:GetHeight() / (2 * s)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", c.x, c.y)
end

-- ── tracker UI ──────────────────────────────────────────────────────
local function PaintOutline(col)
    local alpha = (Cfg().opacity or 0) > 0 and 1 or 0   -- text-only mode: no outline
    for _, line in ipairs(frame.outline or {}) do line:SetVertexColor(col[1], col[2], col[3], alpha) end
end

local function MakeRow(label, color, iconPath)
    local row = CreateFrame("Frame", nil, frame)
    row:SetHeight(22)

    -- icon on a dark square with a thin outline in the currency's colour
    local holder = row:CreateTexture(nil, "ARTWORK")
    holder:SetTexture(SOLID)
    holder:SetVertexColor(0, 0, 0, 0.9)
    holder:SetSize(18, 18)
    holder:SetPoint("LEFT", row, "LEFT", 0, 0)
    if UI.Outline then UI.Outline(row, holder, "OVERLAY", color, 0.8) end

    local icon = row:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(iconPath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER", holder, "CENTER", 0, 0)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lbl:SetPoint("LEFT", holder, "RIGHT", 7, 0)
    lbl:SetText(string.upper(label))

    local val = row:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    val:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    val:SetText("0")
    row.value = val
    return row
end

local function ShowTooltip(self)
    local c = Cfg()
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Token Tracker", 1, 1, 1)
    GameTooltip:AddDoubleLine("Tokens", Commas(PA.prestigeTokens), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Orbs of Destiny", Commas(PA.orbs), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine("Prestige", tostring(PA.prestigeLevel or 0), 0.7, 0.7, 0.7, 1, 1, 1)
    if session.startAt then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Earned this session", "+" .. Commas(session.earned),
            0.7, 0.7, 0.7, TOKEN_C[1], TOKEN_C[2], TOKEN_C[3])
        GameTooltip:AddDoubleLine("Spent this session", Commas(session.spent), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine("Orbs earned", "+" .. Commas(session.orbsEarned),
            0.7, 0.7, 0.7, ORB_C[1], ORB_C[2], ORB_C[3])
        GameTooltip:AddDoubleLine("Session time", Duration(time() - session.startAt), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(c.locked and "Locked. Right-click for options."
        or "Drag to move, drag the corner to resize, right-click for options.", 0.55, 0.55, 0.6, true)
    GameTooltip:Show()
end

local function ShowMenu()
    local c = Cfg()
    EasyMenu({
        { text = "Token Tracker", isTitle = true, notCheckable = true },
        { text = "Options…", notCheckable = true, func = function() TT.OpenOptions() end },
        { text = "Compact layout", checked = c.style == "compact",
          func = function() c.style = (c.style == "compact") and "detailed" or "compact"; ApplyLook() end },
        { text = "Show Orbs of Destiny", checked = c.showOrbs and true or false,
          func = function() c.showOrbs = not c.showOrbs; ApplyLook() end },
        { text = "Lock position", checked = c.locked and true or false,
          func = function() TT.SetLocked(not c.locked) end },
        { text = "Reset session", notCheckable = true,
          func = function() StartSession(); Refresh() end },
        { text = "Hide  (/tokentracker to show)", notCheckable = true,
          func = function() TT.SetShown(false) end },
    }, frame.menu, "cursor", 0, 0, "MENU")
end

local function Build()
    frame = CreateFrame("Frame", "PATokenTracker", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetWidth(BASE_W)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetBackdrop({ bgFile = SOLID, tile = false,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    frame.outline = UI.Outline and UI.Outline(frame, frame, "BORDER", UI.Nav.edge, 1) or {}

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetTexture(SOLID)
    frame.accent:SetWidth(2)
    frame.accent:SetPoint("TOPLEFT",    frame, "TOPLEFT",    1, -1)
    frame.accent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1,  1)
    frame.accent:SetVertexColor(TOKEN_C[1], TOKEN_C[2], TOKEN_C[3], 1)

    frame.tokens = MakeRow("Tokens", TOKEN_C, UI.Icon and UI.Icon.tokens)
    frame.tokens:SetPoint("TOPLEFT",  frame, "TOPLEFT",  12, -8)
    frame.tokens:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)

    frame.orbs = MakeRow("Orbs", ORB_C, UI.Icon and UI.Icon.orbs)
    frame.orbs:SetPoint("TOPLEFT",  frame.tokens, "BOTTOMLEFT",  0, 0)
    frame.orbs:SetPoint("TOPRIGHT", frame.tokens, "BOTTOMRIGHT", 0, 0)

    frame.session = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.session:SetJustifyH("LEFT")

    if UI.AnimatedNumber then
        frame.tokenTween = UI.AnimatedNumber(frame.tokens.value)
        frame.orbTween   = UI.AnimatedNumber(frame.orbs.value)
    end

    frame.menu = CreateFrame("Frame", "PATokenTrackerMenu", frame, "UIDropDownMenuTemplate")

    -- corner grip: drag to resize (scales the whole tracker)
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(12, 12)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    grip:SetFrameLevel(frame:GetFrameLevel() + 5)
    for i = 0, 1 do
        for j = 0, 1 - i do
            local d = grip:CreateTexture(nil, "OVERLAY")
            d:SetTexture(SOLID)
            d:SetSize(2, 2)
            d:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -2 - i * 4, 2 + j * 4)
            d:SetVertexColor(unpack(UI.Color.accentSoft))
        end
    end
    grip:SetAlpha(0)
    frame.grip = grip

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or Cfg().locked then return end
        local s = frame:GetScale()
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)   -- pin the top-left corner
        self.drag = { x = GetCursorPosition(), scale = s, w = frame:GetWidth(),
                      left = left * s, top = top * s }
        self:SetScript("OnUpdate", function(g)
            local d = g.drag
            if not d then return end
            local dx = (GetCursorPosition() - d.x) / UIParent:GetEffectiveScale()
            local ns = d.scale * (1 + dx / (d.w * d.scale))
            ns = math.floor(math.max(MIN_SCALE, math.min(MAX_SCALE, ns)) * 100 + 0.5) / 100
            if ns ~= frame:GetScale() then
                frame:SetScale(ns)
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left / ns, d.top / ns)
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        if not self.drag then return end
        self.drag = nil
        self:SetScript("OnUpdate", nil)
        Cfg().scale = frame:GetScale()
        SavePosition()
    end)

    frame:SetScript("OnDragStart", function(self)
        if not Cfg().locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ShowMenu() end
    end)
    frame:SetScript("OnEnter", function(self)
        PaintOutline(UI.Nav.edgeMid)
        ShowTooltip(self)
    end)
    frame:SetScript("OnLeave", function()
        PaintOutline(UI.Nav.edge)
        GameTooltip:Hide()
    end)

    -- 1s ticker: per-hour rate; 0.1s: grip visibility while hovered
    local acc, hoverAcc = 0, 0
    frame:SetScript("OnUpdate", function(self, dt)
        hoverAcc = hoverAcc + dt
        if hoverAcc >= 0.1 then
            hoverAcc = 0
            local show = not Cfg().locked and (MouseIsOver(self) or grip.drag)
            grip:SetAlpha(show and 1 or 0)
        end
        acc = acc + dt
        if acc >= 1 then
            acc = 0
            if not session.startAt and PA._walletPrimed then StartSession() end
            Refresh()
        end
    end)

    -- registers the tracker as an Astral frame, so its right-click menu is themed
    if UI.SkinTree then UI.SkinTree(frame) end
end

local function StyleValue(fs, c)
    local size  = tonumber(c.size) or 15
    local flags = (c.outline ~= "NONE") and c.outline or nil
    -- an unknown font path leaves the previous font in place, so text never vanishes
    if flags then fs:SetFont(c.font, size, flags) else fs:SetFont(c.font, size) end
    local tc = c.textColor
    fs:SetTextColor(tc[1], tc[2], tc[3])
    if c.outline == "NONE" then
        fs:SetShadowOffset(0, 0)
    else
        local oc  = c.outlineColor
        local off = (c.outline == "THICKOUTLINE") and 2 or 1
        fs:SetShadowColor(oc[1], oc[2], oc[3], 1)
        fs:SetShadowOffset(off, -off)
    end
end

ApplyLook = function()
    if not frame then return end
    local c = Cfg()
    StyleValue(frame.tokens.value, c)
    StyleValue(frame.orbs.value, c)
    local op = math.max(0, math.min(1, tonumber(c.opacity) or 0.88))
    frame:SetBackdropColor(UI.Nav.deep[1], UI.Nav.deep[2], UI.Nav.deep[3], op)
    frame.accent:SetAlpha(op > 0 and 1 or 0)
    PaintOutline(UI.Nav.edge)
    Relayout()
    Refresh()
end

Relayout = function()
    if not frame then return end
    local c = Cfg()
    local size = tonumber(c.size) or 15
    local rowH = math.max(22, size + 8)
    frame.tokens:SetHeight(rowH)
    frame.orbs:SetHeight(rowH)

    local last = frame.tokens
    if c.showOrbs then
        frame.orbs:Show()
        last = frame.orbs
    else
        frame.orbs:Hide()
    end

    local detailed = c.style ~= "compact"
    frame.session:ClearAllPoints()
    if detailed then
        frame.session:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -2)
        frame.session:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -2)
        frame.session:Show()
    else
        frame.session:Hide()
    end

    frame:SetWidth(math.max(BASE_W, 100 + size * 6))
    frame:SetHeight(8 + rowH * (c.showOrbs and 2 or 1) + (detailed and 16 or 0) + 8)
end

Refresh = function()
    if not frame then return end
    local t, o = PA.prestigeTokens or 0, PA.orbs or 0
    if frame.tokenTween then
        if not frame._painted then
            frame._painted = true
            frame.tokenTween:SetInstant(t)
            frame.orbTween:SetInstant(o)
        else
            frame.tokenTween:SetValue(t)
            frame.orbTween:SetValue(o)
        end
    else
        frame.tokens.value:SetText(Commas(t))
        frame.orbs.value:SetText(Commas(o))
    end

    if not session.startAt then
        frame.session:SetText("Waiting for your wallet…")
    else
        local elapsed = time() - session.startAt
        local text = "+" .. Commas(session.earned) .. " this session"
        if elapsed >= 60 and session.earned > 0 then
            text = text .. "  ·  " .. Commas(session.earned / (elapsed / 3600)) .. "/hr"
        end
        frame.session:SetText(text)
    end
end

-- ── options window ──────────────────────────────────────────────────
local function BuildOptions()
    if optionsWin then return optionsWin end

    local w = UI.MakePanel(UIParent, 300, 552, { name = "PATokenTrackerOptions", movable = true, strata = "HIGH" })
    w:Hide()
    -- unified window: navy with a gold edge and a gold top glow (Theme.lua keeps its navy)
    w.__paUnified = true
    UI.AstralBackdrop(w, { thin = true })
    w:SetBackdropColor(unpack(UI.Nav.deep))
    w:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 0.95))
    local glow = w:CreateTexture(nil, "ARTWORK"); glow:SetTexture(SOLID)
    glow:SetPoint("TOPLEFT", w, "TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", w, "TOPRIGHT", -4, -4)
    glow:SetHeight(44)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)
    tinsert(UISpecialFrames, "PATokenTrackerOptions")
    w.header = UI.MakeHeader(w, "Token Tracker", "Appearance and layout. Changes show right away.")

    local controls = {}
    local y = -84

    local function Section(text)
        UI.MakeSectionDivider(w, text, { "TOPLEFT", w, "TOPLEFT", 18, y })
        y = y - 26
    end

    local function Label(text, dy)
        local fs = w:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(fs, 12)
        fs:SetPoint("TOPLEFT", w, "TOPLEFT", 20, y + (dy or 0))
        fs:SetText(text)
        fs:SetTextColor(unpack(UI.Nav.muted))
        return fs
    end

    local ddCount = 0
    local function Dropdown(text, items, key)
        ddCount = ddCount + 1
        Label(text, -8)
        local dd = CreateFrame("Frame", "PATokenTrackerOptDD" .. ddCount, w, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", w, "TOPLEFT", 104, y)
        UIDropDownMenu_SetWidth(dd, 130)
        local function Sync()
            local cur = Cfg()[key]
            for _, it in ipairs(items) do
                if it.val == cur then
                    UIDropDownMenu_SetSelectedValue(dd, it.val)
                    UIDropDownMenu_SetText(dd, it.name)
                end
            end
        end
        UIDropDownMenu_Initialize(dd, function()
            for _, it in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text    = it.name
                info.value   = it.val
                info.checked = (Cfg()[key] == it.val)
                info.func    = function()
                    Cfg()[key] = it.val
                    Sync()
                    ApplyLook()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        dd.Sync = Sync
        controls[#controls + 1] = dd
        y = y - 34
    end

    local function Check(name, text, get, set)
        local cb = CreateFrame("CheckButton", name, w, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", w, "TOPLEFT", 14, y + 4)
        _G[name .. "Text"]:SetText(text)
        _G[name .. "Text"]:SetTextColor(1, 1, 1); UI.SetTextFont(_G[name .. "Text"], 12)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        cb.Sync = function() cb:SetChecked(get() and true or false) end
        controls[#controls + 1] = cb
        y = y - 26
    end

    local sliderCount = 0
    local function Slider(text, minV, maxV, step, key, fmt)
        sliderCount = sliderCount + 1
        local name = "PATokenTrackerOptSlider" .. sliderCount
        Label(text)
        local valText = w:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(valText, 12)
        valText:SetPoint("TOPRIGHT", w, "TOPRIGHT", -24, y)
        valText:SetTextColor(1.00, 0.85, 0.44)
        local s = CreateFrame("Slider", name, w, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", w, "TOPLEFT", 22, y - 18)
        s:SetWidth(256)
        s:SetMinMaxValues(minV, maxV)
        s:SetValueStep(step)
        _G[name .. "Low"]:SetText(fmt(minV))
        _G[name .. "High"]:SetText(fmt(maxV))
        _G[name .. "Text"]:SetText("")
        s:SetScript("OnValueChanged", function(_, v)
            v = math.floor(v / step + 0.5) * step
            valText:SetText(fmt(v))
            if Cfg()[key] ~= v then
                Cfg()[key] = v
                ApplyLook()
            end
        end)
        s.Sync = function()
            s:SetValue(Cfg()[key])
            valText:SetText(fmt(Cfg()[key]))
        end
        controls[#controls + 1] = s
        y = y - 52
    end

    local function Swatch(text, key)
        Label(text, -3)
        local sw = CreateFrame("Button", nil, w)
        sw:SetSize(40, 18)
        sw:SetPoint("TOPRIGHT", w, "TOPRIGHT", -24, y)
        sw:SetBackdrop({ bgFile = SOLID, tile = false,
                         insets = { left = 0, right = 0, top = 0, bottom = 0 } })
        if UI.Outline then UI.Outline(sw, sw, "BORDER", UI.Nav.edgeMid, 1) end
        local function Paint()
            local col = Cfg()[key]
            sw:SetBackdropColor(col[1], col[2], col[3], 1)
        end
        local function SetColor(r, g, b)
            Cfg()[key] = { r, g, b }
            Paint()
            ApplyLook()
        end
        sw:SetScript("OnClick", function()
            local cur = Cfg()[key]
            ColorPickerFrame:Hide()
            ColorPickerFrame.hasOpacity = false
            -- ColorPickerFrame contract: previousValues must be positional {r,g,b}
            ColorPickerFrame.previousValues = { cur[1], cur[2], cur[3] }
            local function apply() SetColor(ColorPickerFrame:GetColorRGB()) end
            ColorPickerFrame.func       = apply
            ColorPickerFrame.swatchFunc = apply
            ColorPickerFrame.cancelFunc = function(prev)
                if type(prev) == "table" and prev[1] then SetColor(prev[1], prev[2], prev[3]) end
            end
            ColorPickerFrame:SetColorRGB(cur[1], cur[2], cur[3])
            ColorPickerFrame:Show()
        end)
        sw.Sync = Paint
        controls[#controls + 1] = sw
        y = y - 30
    end

    Section("LAYOUT")
    Dropdown("Style", STYLES, "style")
    Check("PATokenTrackerOptOrbs", "Show Orbs of Destiny",
        function() return Cfg().showOrbs end,
        function(on) Cfg().showOrbs = on; ApplyLook() end)
    Check("PATokenTrackerOptLock", "Lock position",
        function() return Cfg().locked end,
        function(on) TT.SetLocked(on) end)
    y = y - 8

    Section("TEXT")
    Dropdown("Font", FONTS, "font")
    Slider("Size", 10, 24, 1, "size", function(v) return math.floor(v + 0.5) .. " px" end)
    Swatch("Text colour", "textColor")
    Dropdown("Outline", OUTLINES, "outline")
    Swatch("Shadow colour", "outlineColor")
    y = y - 4

    Section("BACKGROUND")
    Slider("Opacity", 0, 1, 0.05, "opacity", function(v) return math.floor(v * 100 + 0.5) .. "%" end)

    local resetLook = UI.MakeButton(w, "Reset appearance", {
        w = 124, h = 24, variant = "secondary",
        onClick = function()
            local c = Cfg()
            for key in pairs(DEFAULT_LOOK) do c[key] = CopyLook(key) end
            ApplyLook()
            w.SyncAll()
        end,
    })
    resetLook:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", 18, 16)

    local resetPos = UI.MakeButton(w, "Reset size & position", {
        w = 140, h = 24, variant = "secondary",
        onClick = function()
            local c = Cfg()
            c.x, c.y, c.scale = nil, nil, 1
            if frame then ApplyPosition() end
        end,
    })
    resetPos:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -18, 16)

    w.SyncAll = function()
        for _, ctl in ipairs(controls) do ctl.Sync() end
    end
    w:HookScript("OnShow", function() w.SyncAll() end)

    if UI.SkinTree then UI.SkinTree(w) end   -- Astral dropdowns, sliders, check boxes
    optionsWin = w
    return w
end

-- ── public API (Settings tab, menu, slash commands) ─────────────────
function TT.SetShown(on)
    Cfg().shown = on and true or false
    if frame then
        if on then frame:Show() else frame:Hide() end
    end
    SyncControls()
end

function TT.SetLocked(on)
    Cfg().locked = on and true or false
    SyncControls()
end

-- re-read every option (Settings' "Reset ALL settings" replaces the whole table)
function TT.ApplyAll()
    if frame then
        ApplyPosition()
        ApplyLook()
        if Cfg().shown then frame:Show() else frame:Hide() end
    end
    SyncControls()
end

function TT.OpenOptions()
    local w = BuildOptions()
    if w:IsShown() then w:Raise() else w:Show() end
end

SLASH_ASTRALTOKENTRACKER1 = "/tokentracker"
SlashCmdList["ASTRALTOKENTRACKER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "options" or msg == "config" then
        TT.OpenOptions()
    else
        TT.SetShown(not Cfg().shown)
    end
end

if PA.OnTokensChanged then PA:OnTokensChanged(OnWallet) end

-- after Settings.lua's PLAYER_LOGIN handler (this file loads later), so saved options are in
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Build()
    ApplyPosition()
    ApplyLook()
    if Cfg().shown then frame:Show() else frame:Hide() end

    if IsAddOnLoaded("TokenTracker") then
        -- Seville's standalone addon owns /ttc; don't fight it for the command
        DEFAULT_CHAT_FRAME:AddMessage("|cff99b8ff[Project Astral]|r The Token Tracker now includes TokenTracker's "
            .. "appearance options (|cffffffff/tokentracker options|r). You can disable the separate TokenTracker addon at character select.")
    else
        SLASH_ASTRALTOKENTRACKEROPTS1 = "/ttc"
        SlashCmdList["ASTRALTOKENTRACKEROPTS"] = function() TT.OpenOptions() end
    end
end)
