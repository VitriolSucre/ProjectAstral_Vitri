
ProjectAstral     = ProjectAstral or {}
local PA          = ProjectAstral

PA.modules        = {}
PA.prestigeTokens = 0
PA.prestigeLevel  = 0
PA.orbs           = 0

function PA.CleanGemTierMarker(text)
    if type(text) ~= "string" then return text end
    text = text:gsub("%[,T([1-8])%]", "[T%1]")
    return (text:gsub("%[%[T([1-8])%]", "[T%1]"))
end

PA._tokenListeners = PA._tokenListeners or {}
function PA:OnTokensChanged(fn) table.insert(PA._tokenListeners, fn) end

local function fireTokenListeners()
    for _, fn in ipairs(PA._tokenListeners) do
        local ok, err = pcall(fn, PA.prestigeTokens, PA.prestigeLevel)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[ProjectAstral]|r listener error: " .. tostring(err))
        end
    end
end

local function RegisterWalletHandler()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local WalletHandler = _G.AIO.AddHandlers("AstralWallet", {})
    WalletHandler.State = function(_, payload)
        if type(payload) ~= "table" then return end
        local changed = false
        local t = tonumber(payload.tokens)
        local o = tonumber(payload.orbs)
        local l = tonumber(payload.level)
        local firstPush = not PA._walletPrimed
        local dt = (t and PA.prestigeTokens) and (t - PA.prestigeTokens) or 0
        local do_ = (o and PA.orbs)          and (o - PA.orbs)           or 0
        local dl = (l and PA.prestigeLevel)  and (l - PA.prestigeLevel)  or 0
        if t and t ~= PA.prestigeTokens then PA.prestigeTokens = t; changed = true end
        if o and o ~= PA.orbs           then PA.orbs           = o; changed = true end
        if l and l ~= PA.prestigeLevel  then PA.prestigeLevel  = l; changed = true end
        if changed then fireTokenListeners() end
        if not firstPush and PA.UI and PA.UI.GainPopup then
            if dt > 0 then PA.UI.GainPopup(("+%d Tokens"):format(dt),           "tokens") end
            if do_ > 0 then PA.UI.GainPopup(("+%d Orbs of Destiny"):format(do_), "orbs")   end
            if dl > 0 then PA.UI.GainPopup(("Prestige advanced to %d!"):format(l), "orbs") end

            local mf = PA.mainFrame
            if mf and mf:IsShown() and PA.UI.PulseChip then
                if dt > 0 and mf.tokenChip then
                    PA.UI.PulseChip(mf.tokenChip, { 0.35, 0.90, 0.70 })
                end
                if do_ > 0 and mf.orbChip then
                    PA.UI.PulseChip(mf.orbChip, { 0.55, 0.85, 1.00 })
                end
                if dl > 0 and mf.prestigeChip then
                    PA.UI.PulseChip(mf.prestigeChip, { 1.00, 0.85, 0.35 })
                end
            end

        end
        PA._walletPrimed = true
    end
    return true
end

local walletInit = CreateFrame("Frame")
walletInit:RegisterEvent("PLAYER_LOGIN")
walletInit:SetScript("OnEvent", function(self)
    if RegisterWalletHandler() then
        self:UnregisterAllEvents()
        if _G.AIO and _G.AIO.Handle then
            _G.AIO.Handle("AstralWalletServer", "RequestWalletState")
        end
    end
end)

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    if not msg then return false end
    local stripped = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if stripped:find("^%+%d+ Tokens for defeating") then return true end
    if stripped:find("^%+%d+ Orbs of Destiny")     then return true end
    return false
end)

PA.UI = PA.UI or {}
local UI = PA.UI

-- ── Global UI color: tint for the unified look ────────────────────────
-- The unified surfaces (navy panels, blue-grey borders, light-blue hover and
-- selection) were designed in the "Astral" blue. UI.Tint(r, g, b[, a]) turns any
-- such blue-family colour to the hue of Settings > Global UI color, keeping its
-- brightness; other colours (gold, green, red, greys) come back unchanged, so it
-- is safe on any colour. The theme is read from the saved settings, so frames
-- built after login are tinted; a theme change shows everywhere after a reload.
UI.ASTRAL_THEME = { 0.233, 0.353, 1.0 }       -- the "Astral" swatch: no change

local function ToHSV(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = 60 * (((g - b) / d) % 6)
        elseif mx == g then h = 60 * ((b - r) / d + 2)
        else h = 60 * ((r - g) / d + 4) end
    end
    return h, (mx > 0) and d / mx or 0, mx
end

local function FromHSV(h, s, v)
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return r + m, g + m, b + m
end

local REF_H, REF_S = ToHSV(UI.ASTRAL_THEME[1], UI.ASTRAL_THEME[2], UI.ASTRAL_THEME[3])
local tintKey, tintShift, tintSat

local function ThemeShift()
    local t = (ProjectAstralSettings and ProjectAstralSettings.themeColor) or UI.ASTRAL_THEME
    local key = string.format("%.3f,%.3f,%.3f", t[1] or 0, t[2] or 0, t[3] or 0)
    if key ~= tintKey then
        local h, s = ToHSV(t[1] or 0, t[2] or 0, t[3] or 0)
        tintKey = key
        tintShift = h - REF_H
        -- a greyer theme gives greyer surfaces; a pure grey one, neutral greys
        tintSat = math.min(1.15, s / REF_S)
    end
    return tintShift, tintSat
end

function UI.Tint(r, g, b, a)
    if type(r) ~= "number" then return r, g, b, a end
    local h, s, v = ToHSV(r, g, b)
    -- only the blue family (cyan to indigo) of the unified look
    if s > 0.08 and h >= 170 and h <= 262 then
        local shift, sat = ThemeShift()
        if shift ~= 0 or sat ~= 1 then
            r, g, b = FromHSV((h + shift) % 360, math.min(1, s * sat), v)
        end
    end
    return r, g, b, a or 1
end

-- Colour tables ({ r, g, b[, a] }) passed around by the unified code: tinted in
-- place now and again once the saved settings are loaded (tables built while the
-- addon's files run come before them).
local tintedTables = setmetatable({}, { __mode = "k" })
function UI.Tinted(t)
    if type(t) ~= "table" or type(t[1]) ~= "number" then return t end
    local orig = tintedTables[t] or { t[1], t[2], t[3], t[4] }
    tintedTables[t] = orig
    t[1], t[2], t[3] = UI.Tint(orig[1], orig[2], orig[3])
    return t
end
-- Unified palette for every window and tab (tinted by the Global UI color).
-- Frames under a root with __paUnified keep these colours (Theme.lua skips them).
UI.Nav = {
    deep    = UI.Tinted({ 0.031, 0.047, 0.133, 0.97 }),
    panel   = UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }),
    row     = UI.Tinted({ 0.063, 0.090, 0.227, 0.70 }),
    hover   = UI.Tinted({ 0.100, 0.140, 0.320, 0.95 }),
    edge    = UI.Tinted({ 0.165, 0.204, 0.400, 1 }),
    edgeMid = UI.Tinted({ 0.300, 0.360, 0.620, 1 }),
    hot     = UI.Tinted({ 0.440, 0.820, 1.000, 1 }),
    muted   = { 0.86, 0.87, 0.94 },
    dim     = { 0.667, 0.690, 0.831 },
}

function UI.RetintTables()
    tintKey = nil
    for t, orig in pairs(tintedTables) do
        t[1], t[2], t[3] = UI.Tint(orig[1], orig[2], orig[3])
    end
end
local tintBoot = CreateFrame("Frame")
tintBoot:RegisterEvent("ADDON_LOADED")
tintBoot:SetScript("OnEvent", function(self, _, name)
    if name ~= "ProjectAstral" then return end
    self:UnregisterAllEvents()
    -- once: the old default ("Cosmic" purple) never tinted the unified look, so a
    -- player who kept it keeps the Astral blue they have been seeing
    local s = ProjectAstralSettings
    if s and not s.themeV2 then
        local t = s.themeColor
        if type(t) == "table" and math.abs((t[1] or 0) - 0.65) < 0.001
           and math.abs((t[2] or 0) - 0.55) < 0.001 and math.abs((t[3] or 0) - 0.95) < 0.001 then
            s.themeColor = { UI.ASTRAL_THEME[1], UI.ASTRAL_THEME[2], UI.ASTRAL_THEME[3] }
        end
        s.themeV2 = true
    end
    UI.RetintTables()
end)

local function ScaleFontStrings(frame, scale, seen)
    if not frame then return end
    if frame.GetName and frame:GetName() == "AT_Canvas" then return end
    seen = seen or {}
    if seen[frame] then return end
    seen[frame] = true

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        if #regions > 400 then return end
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                local font, size, flags = region:GetFont()
                if font and size then
                    region.__paBaseFontSize = region.__paBaseFontSize or size
                    local newSize = region.__paBaseFontSize * scale
                    if newSize < 4 then newSize = 4 end
                    region:SetFont(font, newSize, flags)
                end
            end
        end
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        if #children > 400 then return end
        for _, child in ipairs(children) do
            ScaleFontStrings(child, scale, seen)
        end
    end
end

function UI.SetFontScale(scale)
    scale = math.max(0.7, math.min(1.3, tonumber(scale) or 1.0))
    local mainFrame = PA.mainFrame
    local seen = {}

    if mainFrame then
        ScaleFontStrings(mainFrame, scale, seen)
        if mainFrame.page then
            ScaleFontStrings(mainFrame.page, scale, seen)
        end
        if mainFrame.visibleSections then
            for _, section in ipairs(mainFrame.visibleSections) do
                if section.card then ScaleFontStrings(section.card, scale, seen) end
                if section.panel then ScaleFontStrings(section.panel, scale, seen) end
            end
        end
    end

    if mainFrame and mainFrame.tabButtons then
        for _, button in pairs(mainFrame.tabButtons) do
            if button.label then
                button._labelW = button.label:GetStringWidth()
            end
        end
    end
    if mainFrame and mainFrame.Relayout and mainFrame.activeTab then
        mainFrame:Relayout()
    end
end

-- VIBRANT: Pure white text colors for all tabs
UI.Color = {
    bgDeep    = { 0.010, 0.010, 0.012, 0.97 },
    bgPanel   = { 0.035, 0.035, 0.040, 0.97 },
    bgRowAlt  = { 0.075, 0.075, 0.080, 0.70 },
    bgHover   = { 0.160, 0.160, 0.170, 0.95 },

    borderDim  = { 0.18, 0.18, 0.20, 1.0 },
    borderMid  = { 0.34, 0.34, 0.37, 1.0 },
    borderHot  = { 0.95, 0.95, 0.95, 1.0 },

    textTitle    = { 1.00, 1.00, 1.00 },  -- Pure white
    textPrimary  = { 1.00, 1.00, 1.00 },  -- VIBRANT: Pure white (was 0.90)
    textMuted    = { 0.80, 0.80, 0.85 },  -- VIBRANT: Bright gray (was 0.52)
    textAccent   = { 1.00, 1.00, 1.00 },  -- VIBRANT: Pure white (was 0.92)
    textHi       = { 1.00, 0.88, 0.42 },
    textGood     = { 0.55, 1.00, 0.70 },
    textBad      = { 1.00, 0.42, 0.42 },
    textWarn     = { 1.00, 0.80, 0.30 },

    accent       = { 1.00, 1.00, 1.00 },
    accentSoft   = { 0.90, 0.90, 0.95 },  -- VIBRANT: Brighter (was 0.72)
}

-- Currency icons shared by the hub header chips and the Token Tracker.
UI.Icon = {
    tokens   = "Interface\\Icons\\INV_Misc_Coin_02",
    orbs     = "Interface\\Icons\\INV_Misc_Orb_05",
    prestige = "Interface\\Icons\\Achievement_Level_80",
    lockouts = "Interface\\Icons\\INV_Misc_Key_03",
}

local DIALOG_EDGE = "Interface\\DialogFrame\\UI-DialogBox-Border"
local TOOLTIP_BG  = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_EDGE = "Interface\\Tooltips\\UI-Tooltip-Border"
local SOLID8      = "Interface\\Buttons\\WHITE8X8"

function UI.AstralBackdrop(frame, opts)
    opts = opts or {}
    frame:SetBackdrop({
        bgFile   = TOOLTIP_BG,
        edgeFile = TOOLTIP_EDGE,
        tile     = true, tileSize = 16, edgeSize = opts.thin and 18 or 32,
        insets   = opts.thin and { left = 4, right = 4, top = 4, bottom = 4 }
                              or { left = 11, right = 12, top = 12, bottom = 11 },
    })
    local bg = opts.bg or UI.Nav.deep          -- unified navy (Global UI color)
    local br = opts.border or UI.Nav.edgeMid
    frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    frame:SetBackdropBorderColor(br[1], br[2], br[3], br[4])
    if opts.cosmic then
        UI.CosmicCorners(frame, opts.cosmicCornerSize)
    end
end

function UI.CosmicButton(b)
    if b.GetNormalTexture   and b:GetNormalTexture()   then b:SetNormalTexture(nil)   end
    if b.GetPushedTexture   and b:GetPushedTexture()   then b:SetPushedTexture(nil)   end
    if b.GetDisabledTexture and b:GetDisabledTexture() then b:SetDisabledTexture(nil) end
    local left   = _G[(b:GetName() or "")]
    if b.Left        then b.Left:SetTexture(nil)        end
    if b.Right       then b.Right:SetTexture(nil)       end
    if b.Middle      then b.Middle:SetTexture(nil)      end
    if b.LeftDisabled  then b.LeftDisabled:SetTexture(nil)  end
    if b.MiddleDisabled then b.MiddleDisabled:SetTexture(nil) end
    if b.RightDisabled  then b.RightDisabled:SetTexture(nil)  end
    for _, r in ipairs({ b:GetRegions() }) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end

    b:SetBackdrop({
        bgFile   = SOLID8,
        edgeFile = TOOLTIP_EDGE,
        tile     = false,
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    local idle  = { UI.Tint(0.055, 0.094, 0.220, 0.96) }   -- unified navy (secondary button)
    local hover = { UI.Tint(0.100, 0.160, 0.320, 1.00) }
    b:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
    b:SetBackdropBorderColor(UI.Color.borderMid[1], UI.Color.borderMid[2],
                             UI.Color.borderMid[3], 1)

    local fs = b.GetFontString and b:GetFontString()
    if fs then
        fs:SetTextColor(unpack(UI.Color.textTitle))
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
    end
    local glow = b:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(SOLID8)
    glow:SetVertexColor(UI.Color.borderHot[1], UI.Color.borderHot[2],
                        UI.Color.borderHot[3], 1)
    glow:SetBlendMode("ADD")
    glow:SetAllPoints(b)
    glow:SetAlpha(0)
    b.__paGlow = glow

    local glowT = CreateFrame("Frame", nil, b)
    glowT:Hide()
    local glowAcc = 0
    glowT:SetScript("OnUpdate", function(self, dt)
        glowAcc = glowAcc + dt
        local phase = (glowAcc % 1.4) / 1.4
        local wave  = 0.5 * (1 - math.cos(phase * 2 * math.pi))
        glow:SetAlpha(0.05 + wave * 0.17)
    end)

    b:HookScript("OnEnter", function(self)
        self:SetBackdropColor(hover[1], hover[2], hover[3], hover[4])
        self:SetBackdropBorderColor(unpack(UI.Color.borderHot))
        glowAcc = 0
        glowT:Show()
    end)
    b:HookScript("OnLeave", function(self)
        self:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
        self:SetBackdropBorderColor(UI.Color.borderMid[1], UI.Color.borderMid[2],
                                     UI.Color.borderMid[3], 1)
        glowT:Hide()
        glow:SetAlpha(0)
    end)

    local pressT = CreateFrame("Frame", nil, b)
    pressT:Hide()
    local pressAcc = 0
    pressT:SetScript("OnUpdate", function(self, dt)
        pressAcc = pressAcc + dt
        local total = 0.22
        local p = math.min(1, pressAcc / total)
        local s
        if p < 0.30 then
            s = 1.0 - 0.06 * (p / 0.30)
        else
            local q = (p - 0.30) / 0.70
            local eased = 1 - (1 - q) * (1 - q)
            if eased < 0.7 then
                s = 0.94 + (1.03 - 0.94) * (eased / 0.7)
            else
                s = 1.03 - (1.03 - 1.0) * ((eased - 0.7) / 0.3)
            end
        end
        b:SetScale(s)
        if p >= 1 then b:SetScale(1.0); self:Hide() end
    end)
    b:HookScript("OnClick", function()
        pressAcc = 0
        pressT:Show()
    end)
end

function UI.CosmicCloseButton(btn)
    for _, r in ipairs({ btn:GetRegions() }) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end
    if btn.GetNormalTexture    and btn:GetNormalTexture()    then btn:SetNormalTexture(nil)    end
    if btn.GetPushedTexture    and btn:GetPushedTexture()    then btn:SetPushedTexture(nil)    end
    if btn.GetHighlightTexture and btn:GetHighlightTexture() then btn:SetHighlightTexture(nil) end
    if btn.GetDisabledTexture  and btn:GetDisabledTexture()  then btn:SetDisabledTexture(nil)  end

    btn:SetBackdrop({
        bgFile   = SOLID8,
        edgeFile = TOOLTIP_EDGE,
        tile     = false,
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local idle  = { UI.Tint(0.055, 0.094, 0.220, 0.96) }   -- unified navy (secondary button)
    local hover = { UI.Tint(0.100, 0.160, 0.320, 1.00) }
    btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
    btn:SetBackdropBorderColor(UI.Color.borderMid[1], UI.Color.borderMid[2],
                                UI.Color.borderMid[3], 1)

    local x = btn:CreateFontString(nil, "OVERLAY")
    x:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
    x:SetPoint("CENTER", btn, "CENTER", 0, 0)
    x:SetText("×")
    x:SetTextColor(unpack(UI.Color.textAccent))
    x:SetShadowColor(0, 0, 0, 0.9)
    x:SetShadowOffset(1, -1)

    btn:HookScript("OnEnter", function(self)
        self:SetBackdropColor(hover[1], hover[2], hover[3], hover[4])
        self:SetBackdropBorderColor(unpack(UI.Color.borderHot))
    end)
    btn:HookScript("OnLeave", function(self)
        self:SetBackdropColor(idle[1], idle[2], idle[3], idle[4])
        self:SetBackdropBorderColor(UI.Color.borderMid[1], UI.Color.borderMid[2],
                                     UI.Color.borderMid[3], 1)
    end)

    btn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if parent and parent.AnimatedHide then
            parent:AnimatedHide()
        elseif parent then
            parent:Hide()
        end
    end)
end

local COSMIC_TEX_BASE   = "Interface\\AddOns\\ProjectAstral\\assets\\gembox\\"
local COSMIC_TEX_CORNER = COSMIC_TEX_BASE .. "slot_box_corner"
local COSMIC_TEX_EDGE_H = COSMIC_TEX_BASE .. "slot_box_edge_h"
local COSMIC_TEX_EDGE_V = COSMIC_TEX_BASE .. "slot_box_edge_v"

function UI.CosmicCorners(frame, cornerSize)
    local fw, fh = frame:GetWidth(), frame:GetHeight()
    if fw and fh and (fw < 34 or fh < 34) then return end

    local sz = cornerSize or 20
    local et = 6  -- edge thickness

    local tl = frame:CreateTexture(nil, "BORDER")
    tl:SetTexture(COSMIC_TEX_CORNER)
    tl:SetSize(sz, sz)
    tl:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

    local tr = frame:CreateTexture(nil, "BORDER")
    tr:SetTexture(COSMIC_TEX_CORNER)
    tr:SetSize(sz, sz)
    tr:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    tr:SetTexCoord(1, 0, 0, 1)

    local bl = frame:CreateTexture(nil, "BORDER")
    bl:SetTexture(COSMIC_TEX_CORNER)
    bl:SetSize(sz, sz)
    bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    bl:SetTexCoord(0, 1, 1, 0)

    local br = frame:CreateTexture(nil, "BORDER")
    br:SetTexture(COSMIC_TEX_CORNER)
    br:SetSize(sz, sz)
    br:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    br:SetTexCoord(1, 0, 1, 0)

    local top = frame:CreateTexture(nil, "BORDER")
    top:SetTexture(COSMIC_TEX_EDGE_H)
    top:SetHeight(et)
    top:SetPoint("TOPLEFT",  frame, "TOPLEFT",  sz, 0)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -sz, 0)

    local bot = frame:CreateTexture(nil, "BORDER")
    bot:SetTexture(COSMIC_TEX_EDGE_H)
    bot:SetHeight(et)
    bot:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  sz, 0)
    bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -sz, 0)
    bot:SetTexCoord(0, 1, 1, 0)

    local left = frame:CreateTexture(nil, "BORDER")
    left:SetTexture(COSMIC_TEX_EDGE_V)
    left:SetWidth(et)
    left:SetPoint("TOPLEFT",    frame, "TOPLEFT",    0,  -sz)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0,   sz)

    local right = frame:CreateTexture(nil, "BORDER")
    right:SetTexture(COSMIC_TEX_EDGE_V)
    right:SetWidth(et)
    right:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0,  -sz)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,   sz)
    right:SetTexCoord(1, 0, 0, 1)
end

function UI.AddStarfield(frame, alpha)
    local tex = frame:CreateTexture(nil, "BACKGROUND")
    tex:SetTexture("Interface\\TalentFrame\\TalentFrameBackground")
    tex:SetAllPoints()
    tex:SetAlpha(alpha or 0.07)
    return tex
end

function UI.SolidFill(parent, c, layer)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(SOLID8)
    t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    return t
end

function UI.MakePanel(parent, w, h, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", opts.name, parent or UIParent)
    f:SetSize(w, h)
    if opts.point then
        f:SetPoint(unpack(opts.point))
    else
        f:SetPoint("CENTER")
    end
    UI.AstralBackdrop(f, {
        thin   = opts.thin,
        cosmic = opts.cosmic == true,
    })
    if opts.starfield == true then UI.AddStarfield(f, opts.starfieldAlpha) end
    if opts.movable then
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
    end
    if opts.strata then f:SetFrameStrata(opts.strata) end
    if opts.animate ~= false and UI.AnimatedShow then
        UI.AnimatedShow(f, { duration = opts.animateDuration or 0.20 })
    end
    return f
end

function UI.MakeHeader(frame, title, subtitle)
    local h = CreateFrame("Frame", nil, frame)
    h:SetHeight(56)
    h:SetPoint("TOPLEFT",  frame, "TOPLEFT",   18, -16)
    h:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -16)

    -- unified title: navy divider, 3px gold bar, white chat-style title, dim subtitle
    local divider = UI.SolidFill(h, UI.Nav.edge, "ARTWORK")
    divider:SetPoint("BOTTOMLEFT",  h, "BOTTOMLEFT",  0, 0)
    divider:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)
    divider:SetHeight(1)

    local bar = h:CreateTexture(nil, "OVERLAY")
    bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetVertexColor(0.886, 0.753, 0.384, 1)
    bar:SetSize(3, 18)
    bar:SetPoint("TOPLEFT", h, "TOPLEFT", 0, -3)

    local t = h:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(t, 17)
    t:SetPoint("LEFT", bar, "RIGHT", 9, 0)
    t:SetText(title or "")
    t:SetTextColor(1, 1, 1)
    h.title = t

    if subtitle and subtitle ~= "" then
        local s = h:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(s, 12)
        s:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
        s:SetText("|cffaab0d4" .. subtitle .. "|r")
        h.subtitle = s
    end

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    UI.CosmicCloseButton(closeBtn)
    h.closeBtn = closeBtn

    return h
end

function UI.MakeFooter(frame, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, frame)
    f:SetHeight(28)
    f:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  18, 14)
    f:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 14)

    local divider = UI.SolidFill(f, UI.Color.borderDim, "ARTWORK")
    divider:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    divider:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    divider:SetHeight(1)
    divider:SetVertexColor(UI.Color.borderDim[1], UI.Color.borderDim[2],
                           UI.Color.borderDim[3], 0.6)

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("LEFT", f, "LEFT", 0, -3)
    f.text:SetTextColor(unpack(UI.Color.textMuted))
    f.text:SetText(opts.text or "")

    return f
end

function UI.MakeSectionDivider(parent, label, anchor)
    local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetText(label or "")
    h:SetTextColor(unpack(UI.Color.accent))
    if anchor then h:SetPoint(unpack(anchor)) end

    local rule = UI.SolidFill(parent, UI.Color.accentSoft, "ARTWORK")
    rule:SetPoint("TOPLEFT",  h, "BOTTOMLEFT",  0, -3)
    rule:SetPoint("TOPRIGHT", parent, "RIGHT", -8, 0)
    rule:SetHeight(1)
    rule:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                        UI.Color.accentSoft[3], 0.55)

    h.rule = rule
    return h
end

function UI.AnimatedNumber(fontString, opts)
    opts = opts or {}
    local self = {
        fs       = fontString,
        format   = opts.format   or "%d",
        duration = opts.duration or 0.4,
        prefix   = opts.prefix   or "",
        suffix   = opts.suffix   or "",
        current  = 0,
        target   = 0,
        start    = 0,
        acc      = 0,
        active   = false,
    }
    local ticker = CreateFrame("Frame")
    ticker:Hide()

    local function paint(v)
        v = math.floor(v + 0.5)
        self.fs:SetText(self.prefix .. string.format(self.format, v) .. self.suffix)
    end

    ticker:SetScript("OnUpdate", function(_, dt)
        self.acc = self.acc + dt
        local t = math.min(1, self.acc / self.duration)
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        local v = self.start + (self.target - self.start) * eased
        paint(v)
        self.current = v
        if t >= 1 then
            ticker:Hide()
            self.active = false
            self.current = self.target
        end
    end)

    function self:SetInstant(n)
        n = tonumber(n) or 0
        self.current = n
        self.target  = n
        self.active  = false
        ticker:Hide()
        paint(n)
    end

    function self:SetValue(n)
        n = tonumber(n) or 0
        if n == self.target and not self.active then return end
        if n == self.current and not self.active then return end
        self.start   = self.active and self.current or (self.current or 0)
        self.target  = n
        self.acc     = 0
        self.active  = true
        ticker:Show()
    end

    function self:GetValue() return self.target end

    return self
end

local GAIN_STACK      = {}
local GAIN_TIME_IN    = 0.35
local GAIN_TIME_OUT   = 0.5
local GAIN_GAP        = 6
local GAIN_FALLBACK_ACCENT = {
    tokens  = { 0.35, 0.90, 0.70 },
    orbs    = { 0.55, 0.85, 1.00 },
    gems    = { 0.75, 0.55, 0.95 },
    warn    = { 1.00, 0.75, 0.35 },
    error   = { 1.00, 0.45, 0.45 },
    success = { 0.35, 0.90, 0.70 },
    info    = { 0.55, 0.85, 1.00 },
}
local GAIN_FALLBACK = {
    enabled   = true,
    width     = 280,
    height    = 46,
    anchor    = "BOTTOMRIGHT",
    offsetX   = -30,
    offsetY   = 180,
    holdTime  = 3.0,
}

local function CurrentGainCfg()
    local s = (PA.Settings and PA.Settings.gainPopup) or {}
    local out = {}
    for k, v in pairs(GAIN_FALLBACK) do
        if s[k] ~= nil then out[k] = s[k] else out[k] = v end
    end
    out.colors = {}
    local cs = s.colors or {}
    for k, v in pairs(GAIN_FALLBACK_ACCENT) do
        out.colors[k] = cs[k] or v
    end
    return out
end

local function RelayoutGainPopups()
    local cfg = CurrentGainCfg()
    local live = {}
    for _, t in ipairs(GAIN_STACK) do
        if t.frame:IsShown() then live[#live + 1] = t end
    end
    GAIN_STACK = live
    for i, t in ipairs(GAIN_STACK) do
        t.frame:ClearAllPoints()
        local stackDir = (cfg.anchor:find("BOTTOM")) and 1 or -1
        t.frame:SetPoint(cfg.anchor, UIParent, cfg.anchor,
            cfg.offsetX,
            cfg.offsetY + stackDir * (i - 1) * (cfg.height + GAIN_GAP))
    end
end
PA._RelayoutGainPopups = RelayoutGainPopups

local GAIN_POOL = {}

local function AcquireGainPopup()
    local f = table.remove(GAIN_POOL)
    if f then return f end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    UI.AstralBackdrop(f, { thin = true, bg = { 0.04, 0.06, 0.11, 0.92 } })
    local stripe = f:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetWidth(4)
    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetTextColor(0.95, 0.95, 1.0)
    lbl:SetShadowColor(0.05, 0.10, 0.25, 0.85)
    lbl:SetShadowOffset(1, -1)
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    if lbl.SetMaxLines then lbl:SetMaxLines(1) end
    f.label = lbl
    f.stripe = stripe
    return f
end

function UI.GainPopup(text, kind, opts)
    local cfg = CurrentGainCfg()
    if cfg.enabled == false then return end
    kind = kind or "info"
    opts = opts or {}
    local accent = cfg.colors[kind] or cfg.colors.info

    local f = AcquireGainPopup()
    f:SetSize(cfg.width, cfg.height)
    f:SetBackdropColor(UI.Tint(0.04, 0.06, 0.11, 0.92))
    f:SetBackdropBorderColor(accent[1], accent[2], accent[3], accent[4] or 1)
    f:SetAlpha(0)

    local stripeOnRight = (cfg.anchor == "BOTTOMRIGHT" or cfg.anchor == "TOPRIGHT")
    local stripe, lbl = f.stripe, f.label
    stripe:SetVertexColor(accent[1], accent[2], accent[3], 1.0)
    stripe:ClearAllPoints()
    lbl:ClearAllPoints()
    if stripeOnRight then
        stripe:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -2, -2)
        stripe:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2,  2)
        lbl:SetPoint("LEFT",  f, "LEFT",   8, 0)
        lbl:SetPoint("RIGHT", f, "RIGHT", -14, 0)
        lbl:SetJustifyH("RIGHT")
    else
        stripe:SetPoint("TOPLEFT",     f, "TOPLEFT",     2, -2)
        stripe:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  2,  2)
        lbl:SetPoint("LEFT",  f, "LEFT",  14, 0)
        lbl:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        lbl:SetJustifyH("LEFT")
    end
    lbl:SetFont("Fonts\\MORPHEUS.TTF", opts.fontSize or 12)
    lbl:SetText(text or "")

    local phase, phaseT = "in", 0
    f:Show()
    GAIN_STACK[#GAIN_STACK + 1] = { frame = f }
    RelayoutGainPopups()

    f:SetScript("OnUpdate", function(self, dt)
        phaseT = phaseT + dt
        if phase == "in" then
            local t = math.min(1, phaseT / GAIN_TIME_IN)
            local eased = 1 - (1 - t) * (1 - t) * (1 - t)
            self:SetAlpha(eased)
            if t >= 1 then phase, phaseT = "hold", 0 end
        elseif phase == "hold" then
            if phaseT >= cfg.holdTime then phase, phaseT = "out", 0 end
        elseif phase == "out" then
            local t = math.min(1, phaseT / GAIN_TIME_OUT)
            self:SetAlpha(1 - t)
            if t >= 1 then
                self:SetScript("OnUpdate", nil)
                self:Hide()
                RelayoutGainPopups()
                GAIN_POOL[#GAIN_POOL + 1] = self
            end
        end
    end)

    return f
end

UI.Toast = UI.GainPopup

function UI.AnimatedShow(frame, opts)
    if not frame or frame.__paAnimShow then return end
    frame.__paAnimShow = true
    opts = opts or {}
    local dur = opts.duration or 0.20

    local ticker = CreateFrame("Frame")
    ticker:Hide()
    local mode, acc, targetHide = nil, 0, false

    local function Target() return frame.__paTargetAlpha or 1 end

    ticker:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        local t = math.min(1, acc / dur)
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        if mode == "in" then
            frame:SetAlpha(eased * Target())
            if t >= 1 then self:Hide() end
        elseif mode == "out" then
            frame:SetAlpha((1 - eased) * Target())
            if t >= 1 then
                self:Hide()
                targetHide = false
                frame:SetAlpha(Target())
                if frame.__paHideAfterFade then
                    frame.__paHideAfterFade = false
                    frame:Hide()
                end
            end
        end
    end)

    frame:HookScript("OnShow", function(self)
        mode = "in"
        acc  = 0
        self:SetAlpha(0)
        ticker:Show()
    end)

    frame.AnimatedHide = function(self)
        if not self:IsShown() then return end
        mode = "out"
        acc  = 0
        self.__paHideAfterFade = true
        ticker:Show()
    end
end

function UI.MakeLoadingOverlay(parent, opts)
    opts = opts or {}
    local o = CreateFrame("Frame", nil, parent)
    o:SetAllPoints(parent)
    o:SetFrameStrata(parent:GetFrameStrata() or "DIALOG")
    o:SetFrameLevel((parent:GetFrameLevel() or 0) + 20)
    o:EnableMouse(true)
    o:Hide()

    local bg = o:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(UI.Tint(0.02, 0.04, 0.10, 0.55))

    local lbl = o:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\MORPHEUS.TTF", 22)
    lbl:SetPoint("CENTER", o, "CENTER", 0, 0)
    lbl:SetText(opts.text or "Loading" .. string.char(0xE2, 0x80, 0xA6))
    if UI.Color and UI.Color.textAccent then
        lbl:SetTextColor(unpack(UI.Color.textAccent))
    else
        lbl:SetTextColor(0.75, 0.85, 1.0)
    end
    lbl:SetShadowColor(0.05, 0.10, 0.25, 0.9)
    lbl:SetShadowOffset(1, -1)
    o.label = lbl

    local pulseAcc = 0
    o:SetScript("OnUpdate", function(self, dt)
        pulseAcc = pulseAcc + dt
        local phase = (pulseAcc % 1.4) / 1.4
        local wave  = 0.55 + 0.45 * (0.5 * (1 - math.cos(phase * 6.2831853)))
        lbl:SetAlpha(wave)
    end)

    o:HookScript("OnShow", function() pulseAcc = 0; lbl:SetAlpha(0.55) end)

    return o
end

function UI.MakeStatBox(parent, w, h, label)
    w = w or 160; h = h or 64
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    UI.AstralBackdrop(box, { thin = true,
                             bg = UI.Nav.panel,
                             border = UI.Nav.edge })

    local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lbl:SetPoint("TOP", box, "TOP", 0, -8)
    lbl:SetText(label or "")
    lbl:SetTextColor(unpack(UI.Nav.muted))

    local val = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    val:SetPoint("BOTTOM", box, "BOTTOM", 0, 10)
    val:SetText("--")
    val:SetTextColor(unpack(UI.Color.textTitle))

    box.label = lbl
    box.value = val
    return box
end

local THEMED_BUTTONS = setmetatable({}, { __mode = "k" })

local VARIANT = {
    primary = {
        idle = { 0.10, 0.20, 0.42, 0.95 },
        hover= { 0.20, 0.36, 0.68, 1.00 },
        text = UI.Color.textTitle,
        border = UI.Color.borderMid,
    },
    secondary = {
        idle = { 0.05, 0.09, 0.18, 0.95 },
        hover= { 0.12, 0.22, 0.38, 1.00 },
        text = UI.Color.textPrimary,
        border = UI.Color.borderDim,
    },
    -- titan gold, not re-tinted by ApplyThemeColor: outline style used for the
    -- main gem actions (Fuse, Fuse all, Load, Save current, Deposit all...)
    gold = {
        idle = { 0.886, 0.753, 0.384, 0.08 },
        hover= { 0.886, 0.753, 0.384, 0.22 },
        text = { 1.00, 0.89, 0.60 },
        border = { 0.79, 0.66, 0.31, 1.0 },
    },
    danger = {
        idle = { 0.45, 0.10, 0.16, 0.95 },
        hover= { 0.65, 0.15, 0.22, 1.00 },
        text = { 1.00, 0.92, 0.85 },
        border = { 0.75, 0.30, 0.32, 1.0 },
    },
}

function UI.MakeButton(parent, label, opts)
    opts = opts or {}
    local v = VARIANT[opts.variant or "primary"]
    local b = CreateFrame("Button", nil, parent)
    b.__paThemeVariant = v
    THEMED_BUTTONS[b] = true
    b:SetSize(opts.w or 160, opts.h or 28)
    UI.AstralBackdrop(b, { thin = true, bg = v.idle, border = v.border })

    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    txt:SetPoint("CENTER")
    txt:SetText(label or "")
    txt:SetTextColor(unpack(v.text))
    b.text = txt

    b:SetScript("OnEnter", function(self)
        if self._disabled then return end
        self:SetBackdropColor(v.hover[1], v.hover[2], v.hover[3], v.hover[4])
        self:SetBackdropBorderColor(unpack(UI.Color.borderHot))
    end)
    b:SetScript("OnLeave", function(self)
        if self._disabled then return end
        self:SetBackdropColor(v.idle[1], v.idle[2], v.idle[3], v.idle[4])
        self:SetBackdropBorderColor(unpack(v.border))
    end)
    if opts.onClick then b:SetScript("OnClick", opts.onClick) end

    function b:SetDisabledLook(off)
        off = off and true or false
        -- periodic refreshes call this every tick; repainting would wipe the hover state
        if self._lookPainted and self._disabled == off then return end
        self._lookPainted = true
        self._disabled = off
        if off then
            self:SetBackdropColor(UI.Tint(0.043, 0.067, 0.188, 0.60))   -- dim navy, not black
            self:SetBackdropBorderColor(UI.Tint(0.165, 0.204, 0.400, 0.8))
            self.text:SetTextColor(0.45, 0.45, 0.50)
            self:Disable()
        else
            local hovered = GetMouseFocus() == self
            local bg = hovered and v.hover or v.idle
            self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
            if hovered then self:SetBackdropBorderColor(unpack(UI.Color.borderHot))
            else self:SetBackdropBorderColor(unpack(v.border)) end
            self.text:SetTextColor(unpack(v.text))
            self:Enable()
        end
    end

    function b:SetLabel(s) self.text:SetText(s) end

    return b
end

function UI.RefreshThemeButtons()
    for button in pairs(THEMED_BUTTONS) do
        local variant = button.__paThemeVariant
        if variant and button.SetBackdropColor then
            if button._disabled then
                button:SetDisabledLook(true)
            else
                button:SetBackdropColor(unpack(variant.idle))
                button:SetBackdropBorderColor(unpack(variant.border))
                button.text:SetTextColor(unpack(variant.text))
            end
        end
    end
end

-- VIBRANT: Keep text colors vivid even when theme changes
function UI.ApplyThemeColor(color)
    color = type(color) == "table" and color or UI.ASTRAL_THEME
    local r = math.max(0, math.min(1, tonumber(color[1]) or 0.233))
    local g = math.max(0, math.min(1, tonumber(color[2]) or 0.353))
    local b = math.max(0, math.min(1, tonumber(color[3]) or 1.0))

    local function Mix(base, amount)
        return {
            base[1] * (1 - amount) + r * amount,
            base[2] * (1 - amount) + g * amount,
            base[3] * (1 - amount) + b * amount,
        }
    end
    local function Lighten(amount)
        return { r + (1 - r) * amount, g + (1 - g) * amount,
                 b + (1 - b) * amount }
    end

    UI.Color.accent = { r, g, b }
    UI.Color.accentSoft = Lighten(0.28)
    UI.Color.textAccent = Lighten(0.42)
    UI.Color.borderDim = Mix({ 0.18, 0.18, 0.20 }, 0.28)
    UI.Color.borderMid = Mix({ 0.34, 0.34, 0.37 }, 0.48)
    UI.Color.borderHot = Lighten(0.52)
    UI.Color.bgDeep = { 0.010 + r * 0.009, 0.010 + g * 0.009,
                        0.012 + b * 0.009, 0.97 }
    UI.Color.bgPanel = { 0.035 + r * 0.018, 0.035 + g * 0.018,
                         0.040 + b * 0.018, 0.97 }
    UI.Color.bgRowAlt = { 0.075 + r * 0.018, 0.075 + g * 0.018,
                          0.080 + b * 0.018, 0.70 }
    UI.Color.bgHover = { 0.160 + r * 0.025, 0.160 + g * 0.025,
                         0.170 + b * 0.025, 0.95 }

    -- VIBRANT: Always keep text colors vivid
    UI.Color.textTitle   = { 1.00, 1.00, 1.00 }
    UI.Color.textPrimary = { 1.00, 1.00, 1.00 }
    UI.Color.textMuted   = { 0.80, 0.80, 0.85 }

    VARIANT.primary.idle = Mix({ 0.10, 0.20, 0.42 }, 0.62)
    VARIANT.primary.hover = Mix({ 0.20, 0.36, 0.68 }, 0.72)
    VARIANT.primary.border = UI.Color.borderMid
    VARIANT.secondary.idle = Mix({ 0.05, 0.09, 0.18 }, 0.22)
    VARIANT.secondary.hover = Mix({ 0.12, 0.22, 0.38 }, 0.30)
    VARIANT.secondary.border = UI.Color.borderDim

    for _, tab in ipairs(PA.HubTabs or {}) do
        tab.color = { r, g, b }
    end
    UI.RefreshThemeButtons()
    if PA.AstralGems and PA.AstralGems.RefreshTheme then
        PA.AstralGems.RefreshTheme()
    end
    if PA.mainFrame and PA.mainFrame.RefreshTheme then
        PA.mainFrame:RefreshTheme()
    end
end

function UI.PulseChip(chip, tint)
    if not chip then return end
    tint = tint or UI.Color.textHi

    if not chip.__paPulseGlow then
        local g = chip:CreateTexture(nil, "OVERLAY")
        g:SetTexture(SOLID8)
        g:SetBlendMode("ADD")
        g:SetAllPoints(chip)
        g:SetAlpha(0)
        chip.__paPulseGlow = g

        chip.__paPulseTicker = CreateFrame("Frame", nil, chip)
        chip.__paPulseTicker:Hide()
    end

    local glow = chip.__paPulseGlow
    glow:SetVertexColor(tint[1], tint[2], tint[3], 1)

    local t = chip.__paPulseTicker
    local acc = 0
    local dur = 0.55
    t:Show()
    t:SetScript("OnUpdate", function(self, dt)
        acc = acc + dt
        local p = math.min(1, acc / dur)
        local s = 1.0 + 0.12 * math.sin(p * math.pi)
        chip:SetScale(s)
        local a
        if p < 0.20 then
            a = (p / 0.20) * 0.55
        else
            local q = (p - 0.20) / 0.80
            a = 0.55 * (1 - q) * (1 - q)
        end
        glow:SetAlpha(a)
        if p >= 1 then
            chip:SetScale(1.0)
            glow:SetAlpha(0)
            self:Hide()
        end
    end)
end

function UI.MakeSearchBox(parent, opts)
    opts = opts or {}
    local w = opts.width  or 160
    local h = opts.height or 22

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(w, h)
    UI.AstralBackdrop(container, { thin = true })
    container:SetBackdropColor(UI.Color.bgDeep[1], UI.Color.bgDeep[2],
                               UI.Color.bgDeep[3], 0.85)
    container:SetBackdropBorderColor(UI.Color.borderDim[1], UI.Color.borderDim[2],
                                     UI.Color.borderDim[3], 1)

    local edit = CreateFrame("EditBox", nil, container)
    edit:SetPoint("LEFT",  container, "LEFT",   8, 0)
    edit:SetPoint("RIGHT", container, "RIGHT", -8, 0)
    edit:SetHeight(h - 6)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(48)
    local fontSize = tonumber(opts.fontSize)
    if fontSize then
        edit:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
    else
        edit:SetFontObject(GameFontHighlightSmall)
    end
    edit:SetTextColor(UI.Color.textPrimary[1], UI.Color.textPrimary[2],
                      UI.Color.textPrimary[3])
    edit:SetTextInsets(0, 0, 0, 0)

    local ghost = container:CreateFontString(nil, "OVERLAY",
                                             "GameFontDisableSmall")
    if fontSize then
        ghost:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, fontSize - 1), "OUTLINE")
    end
    ghost:SetPoint("LEFT", edit, "LEFT", 2, 0)
    ghost:SetText(opts.placeholder or "Search…")
    ghost:SetTextColor(0.45, 0.55, 0.68)

    local function refreshGhost()
        if edit:HasFocus() or (edit:GetText() or "") ~= "" then
            ghost:Hide()
        else
            ghost:Show()
        end
    end

    edit:SetScript("OnEditFocusGained", function(self)
        container:SetBackdropBorderColor(UI.Color.borderHot[1],
                                         UI.Color.borderHot[2],
                                         UI.Color.borderHot[3], 1)
        refreshGhost()
    end)
    edit:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(UI.Color.borderDim[1],
                                         UI.Color.borderDim[2],
                                         UI.Color.borderDim[3], 1)
        refreshGhost()
    end)
    edit:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
        refreshGhost()
        if opts.onChanged then opts.onChanged("") end
    end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnTextChanged", function(self)
        refreshGhost()
        if opts.onChanged then opts.onChanged(self:GetText() or "") end
    end)

    container:EnableMouse(true)
    container:SetScript("OnMouseUp", function() edit:SetFocus() end)

    container.edit = edit
    function container:GetText()  return edit:GetText() or "" end
    function container:SetText(s) edit:SetText(s or ""); refreshGhost() end
    function container:Clear()    edit:SetText(""); refreshGhost() end
    function container:ResetPlaceholder() refreshGhost() end

    return container
end

function UI.AddInnerGlow(frame, opts)
    opts = opts or {}
    local sides = opts.sides or "top"
    local col   = opts.color or UI.Color.accent
    local a     = opts.maxAlpha or 0.14
    local thick = opts.thickness or 20

    if sides == "top" or sides == "all" then
        local top = frame:CreateTexture(nil, "OVERLAY")
        top:SetTexture(SOLID8)
        top:SetVertexColor(col[1], col[2], col[3], a)
        top:SetBlendMode("ADD")
        top:SetHeight(thick)
        top:SetPoint("TOPLEFT",  frame, "TOPLEFT",   4, -4)
        top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        for k = 1, 3 do
            local dim = frame:CreateTexture(nil, "OVERLAY")
            dim:SetTexture(SOLID8)
            dim:SetVertexColor(col[1], col[2], col[3], a * (1 - k / 4))
            dim:SetBlendMode("ADD")
            dim:SetHeight(thick)
            dim:SetPoint("TOPLEFT",  frame, "TOPLEFT",   4, -4 - k * 4)
            dim:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4 - k * 4)
        end
    end
    if sides == "all" then
        for _, side in ipairs({ "BOTTOM", "LEFT", "RIGHT" }) do
            local tex = frame:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(SOLID8)
            tex:SetVertexColor(col[1], col[2], col[3], a * 0.5)
            tex:SetBlendMode("ADD")
            if side == "BOTTOM" then
                tex:SetHeight(thick)
                tex:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",   4, 4)
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
            elseif side == "LEFT" then
                tex:SetWidth(thick)
                tex:SetPoint("TOPLEFT",    frame, "TOPLEFT",     4, -4)
                tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",  4, 4)
            else
                tex:SetWidth(thick)
                tex:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    -4, -4)
                tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
            end
        end
    end
end

function UI.MakeSectionLabel(parent, text, opts)
    opts = opts or {}
    local host = CreateFrame("Frame", nil, parent)
    host:SetHeight(16)

    local label = host:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\MORPHEUS.TTF", 10, "OUTLINE")
    label:SetPoint("LEFT", host, "LEFT", 0, 1)
    label:SetText(string.upper(text or ""))
    label:SetTextColor(UI.Color.textAccent[1], UI.Color.textAccent[2],
                       UI.Color.textAccent[3])
    label:SetShadowColor(0.05, 0.10, 0.25, 0.9)
    label:SetShadowOffset(1, -1)
    host.label = label

    if opts.underline ~= false then
        local ac = opts.accentColor or UI.Color.accentSoft
        local line = host:CreateTexture(nil, "ARTWORK")
        line:SetTexture(SOLID8)
        line:SetVertexColor(ac[1], ac[2], ac[3], 0.55)
        line:SetHeight(1)
        line:SetPoint("LEFT",  label, "RIGHT", 10, 0)
        line:SetPoint("RIGHT", host,  "RIGHT",  0, 0)
        host.line = line
    end

    function host:SetText(s)
        self.label:SetText(string.upper(s or ""))
    end
    return host
end

function UI.MakeIconFrame(parent, opts)
    opts = opts or {}
    local size = opts.size or 26

    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)

    local ring = f:CreateTexture(nil, "BORDER")
    ring:SetTexture(SOLID8)
    ring:SetAllPoints(f)

    local mask = f:CreateTexture(nil, "ARTWORK")
    mask:SetTexture(SOLID8)
    mask:SetVertexColor(UI.Tint(0.02, 0.03, 0.06, 1))
    mask:SetPoint("TOPLEFT",     f, "TOPLEFT",      1, -1)
    mask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetPoint("TOPLEFT",     f, "TOPLEFT",      2, -2)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2,  2)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.ring = ring
    f.icon = icon

    local QC = {
        [0] = { 0.62, 0.62, 0.62 },
        [1] = { 1.00, 1.00, 1.00 },
        [2] = { 0.12, 1.00, 0.00 },
        [3] = { 0.00, 0.44, 0.87 },
        [4] = { 0.64, 0.21, 0.93 },
        [5] = { 1.00, 0.50, 0.00 },
        [6] = { 0.90, 0.80, 0.50 },
        [7] = { 0.90, 0.80, 0.50 },
    }

    function f:SetTexture(path)
        self.icon:SetTexture(path or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    function f:SetQuality(q)
        local c = QC[q or 1] or QC[1]
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end

    f:SetQuality(1)
    return f
end

local TIER_BADGE_TINT = {
    [1] = { 0.85, 0.85, 0.90 },
    [2] = { 0.30, 0.90, 0.20 },
    [3] = { 0.35, 0.60, 0.95 },
    [4] = { 0.75, 0.40, 0.95 },
    [5] = { 1.00, 0.55, 0.15 },
    [6] = { 0.95, 0.85, 0.55 },
    [7] = { 1.00, 0.45, 0.55 },
    [8] = { 1.00, 0.25, 0.25 },
}
function UI.MakeTierBadge(parent, opts)
    opts = opts or {}
    local w = opts.width or 34
    local h = opts.height or 18

    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(w, h)
    UI.AstralBackdrop(badge, { thin = true })
    badge:SetBackdropColor(UI.Tint(0.08, 0.10, 0.16, 0.85))

    local stripe = badge:CreateTexture(nil, "ARTWORK")
    stripe:SetTexture(SOLID8)
    stripe:SetPoint("TOPLEFT",    badge, "TOPLEFT",    2, -2)
    stripe:SetPoint("BOTTOMLEFT", badge, "BOTTOMLEFT", 2,  2)
    stripe:SetWidth(3)

    local text = badge:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\MORPHEUS.TTF", 10, "OUTLINE")
    text:SetPoint("LEFT", stripe, "RIGHT", 3, 0)
    text:SetPoint("RIGHT", badge, "RIGHT", -2, 0)
    text:SetJustifyH("CENTER")
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)

    badge.stripe = stripe
    badge.text   = text

    function badge:SetTier(n)
        local c = TIER_BADGE_TINT[n or 1] or TIER_BADGE_TINT[1]
        self.stripe:SetVertexColor(c[1], c[2], c[3], 1)
        self.text:SetTextColor(c[1], c[2], c[3])
        self.text:SetText("T" .. tostring(n or "?"))
        self:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
    end
    function badge:SetLabel(s)
        self.text:SetText(s or "?")
    end

    if opts.tier then badge:SetTier(opts.tier) end
    return badge
end

function UI.MakeRowChrome(row, opts)
    opts = opts or {}
    local ac = opts.accentColor or UI.Color.borderHot

    if opts.alt then
        local alt = row:CreateTexture(nil, "BACKGROUND")
        alt:SetTexture(SOLID8)
        alt:SetVertexColor(1, 1, 1, 0.025)
        alt:SetAllPoints(row)
    end

    local hoverBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    hoverBg:SetTexture(SOLID8)
    hoverBg:SetVertexColor(ac[1], ac[2], ac[3], 1)
    hoverBg:SetAllPoints(row)
    hoverBg:SetAlpha(0)

    local accent = row:CreateTexture(nil, "OVERLAY")
    accent:SetTexture(SOLID8)
    accent:SetVertexColor(ac[1], ac[2], ac[3], 1)
    accent:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:SetAlpha(0)

    row:HookScript("OnEnter", function() hoverBg:SetAlpha(0.12); accent:SetAlpha(1) end)
    row:HookScript("OnLeave", function() hoverBg:SetAlpha(0);    accent:SetAlpha(0) end)

    row.__paHoverBg = hoverBg
    row.__paAccent  = accent
    return row
end

function UI.MakeChip(parent, label, value, color, opts)
    opts = opts or {}
    local dot  = opts.dot
    local icon = opts.icon

    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(24)
    UI.AstralBackdrop(c, { thin = true,
                           bg = UI.Color.bgPanel,
                           border = UI.Color.borderDim })

    if dot then
        c:SetBackdropColor(UI.Tint(0.030, 0.045, 0.075, 0.92))
        c:SetBackdropBorderColor(dot[1] * 0.65, dot[2] * 0.65, dot[3] * 0.65, 1)
    end

    local dotTex
    if icon then
        local holder = c:CreateTexture(nil, "ARTWORK")
        holder:SetTexture(SOLID8)
        holder:SetVertexColor(0, 0, 0, 0.9)
        holder:SetSize(16, 16)
        holder:SetPoint("LEFT", c, "LEFT", 5, 0)
        dotTex = c:CreateTexture(nil, "OVERLAY")
        dotTex:SetTexture(icon)
        dotTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dotTex:SetSize(14, 14)
        dotTex:SetPoint("CENTER", holder, "CENTER", 0, 0)
    elseif dot then
        dotTex = c:CreateTexture(nil, "OVERLAY")
        dotTex:SetTexture(SOLID8)
        dotTex:SetVertexColor(dot[1], dot[2], dot[3], 1)
        dotTex:SetSize(6, 6)
        dotTex:SetPoint("LEFT", c, "LEFT", 7, 0)

        local glow = c:CreateTexture(nil, "OVERLAY")
        glow:SetTexture(SOLID8)
        glow:SetVertexColor(dot[1], dot[2], dot[3], 0.35)
        glow:SetBlendMode("ADD")
        glow:SetSize(12, 12)
        glow:SetPoint("CENTER", dotTex, "CENTER", 0, 0)
        c.dotGlow = glow
    end

    local txt = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if icon or dot then
        txt:SetPoint("LEFT",  c, "LEFT",  icon and 27 or 20, 0)
        txt:SetPoint("RIGHT", c, "RIGHT", -8, 0)
        txt:SetJustifyH("LEFT")
    else
        txt:SetPoint("CENTER")
    end
    if value ~= nil then
        txt:SetText(label .. "  " .. tostring(value))
    else
        txt:SetText(label)
    end
    if color then txt:SetTextColor(color[1], color[2], color[3]) end
    c.text = txt
    c.dot  = dotTex

    local minW = icon and 84 or (dot and 78 or 60)
    local pad  = icon and 37 or (dot and 30 or 22)
    c._minW, c._pad = minW, pad
    c:SetWidth(math.max(minW, txt:GetStringWidth() + pad))
    function c:SetText(s)
        self.text:SetText(s)
        self:SetWidth(math.max(minW, self.text:GetStringWidth() + pad))
    end
    return c
end

-- Chat-style text: an OUTLINE greys out small white glyphs, a plain black drop
-- shadow (what the chat frame uses) keeps them bright and readable.
function UI.SetTextFont(fs, size, font)
    fs:SetFont(font or "Fonts\\FRIZQT__.TTF", size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end

-- Toggleable filter pill (tier / trigger / "Owned"...). chip:SetActive(bool),
-- chip.text is the label FontString (use |c codes for coloured parts).
local function PaintFilterChip(chip, hover)
    if chip._active then
        chip:SetBackdropColor(UI.Tint(0.31, 0.76, 0.97, 0.22))
        chip:SetBackdropBorderColor(UI.Tint(0.44, 0.82, 1.00, 1))
    else
        chip:SetBackdropColor(UI.Tint(0.063, 0.090, 0.227, 0.95))
        if hover then chip:SetBackdropBorderColor(UI.Tint(0.30, 0.36, 0.62, 1))
        else          chip:SetBackdropBorderColor(UI.Tint(0.173, 0.216, 0.408, 1)) end
    end
end

function UI.MakeFilterChip(parent, w, label, onClick)
    local chip = CreateFrame("Button", nil, parent)
    chip:SetSize(w, 24)
    UI.AstralBackdrop(chip, { thin = true })
    chip.text = chip:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(chip.text, 11)
    chip.text:SetPoint("CENTER", chip, "CENTER", 0, 0)
    chip.text:SetText(label or "")
    function chip:SetActive(on) self._active = on; PaintFilterChip(self) end
    chip:SetScript("OnEnter", function(self) PaintFilterChip(self, true) end)
    chip:SetScript("OnLeave", function(self) PaintFilterChip(self); GameTooltip:Hide() end)
    chip:SetScript("OnClick", onClick)
    PaintFilterChip(chip)
    return chip
end

-- Search box in the filter-chip palette
function UI.StyleFilterSearch(box)
    box:SetBackdropColor(UI.Tint(0.039, 0.059, 0.157, 0.95))
    box:SetBackdropBorderColor(UI.Tint(0.173, 0.216, 0.408, 1))
end

function UI.MakeTabBar(parent, tabs, onSelect, opts)
    opts = opts or {}
    local bar = CreateFrame("Frame", nil, parent)
    bar.buttons = {}
    bar.activeId = nil

    local PADX = 16
    local ROW_H = 34

    for i, t in ipairs(tabs) do
        local row = CreateFrame("Button", nil, bar)
        row:SetHeight(ROW_H)
        if opts.bottomAnchor then
            row:SetPoint("BOTTOMLEFT",  bar, "BOTTOMLEFT",  0, (i - 1) * (ROW_H + 2))
            row:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, (i - 1) * (ROW_H + 2))
        else
            row:SetPoint("TOPLEFT",  bar, "TOPLEFT",  0, -((i - 1) * (ROW_H + 2)))
            row:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, -((i - 1) * (ROW_H + 2)))
        end

        local hl = UI.SolidFill(row, UI.Color.borderHot, "BACKGROUND")
        hl:SetAllPoints()
        hl:SetAlpha(0)
        row.hl = hl

        local active = UI.SolidFill(row, UI.Color.accent, "BACKGROUND")
        active:SetAllPoints()
        active:SetAlpha(0)
        row.active = active

        local marker = UI.SolidFill(row, UI.Color.accent, "OVERLAY")
        marker:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, -1)
        marker:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0,  1)
        marker:SetWidth(4)
        marker:SetAlpha(0)
        row.marker = marker

        row.markerGlow = nil

        local chevron = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        chevron:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        chevron:SetText(">")
        chevron:SetTextColor(UI.Color.accent[1], UI.Color.accent[2],
                             UI.Color.accent[3])
        chevron:SetAlpha(0)
        row.chevron = chevron

        local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", row, "LEFT", PADX, 0)
        lbl:SetText(t.label)
        lbl:SetTextColor(unpack(UI.Color.textPrimary))
        row.text = lbl
        row.id = t.id

        row:SetScript("OnEnter", function(self)
            if bar.activeId ~= self.id then self.hl:SetAlpha(0.14) end
            self.text:SetTextColor(unpack(UI.Color.textTitle))
        end)
        row:SetScript("OnLeave", function(self)
            self.hl:SetAlpha(0)
            if bar.activeId == self.id then
                self.text:SetTextColor(unpack(UI.Color.textTitle))
            else
                self.text:SetTextColor(unpack(UI.Color.textPrimary))
            end
        end)
        row:SetScript("OnClick", function(self)
            bar:SelectTab(self.id)
            if onSelect then onSelect(self.id) end
        end)

        bar.buttons[t.id] = row
    end

    local function fadeTo(tex, target, dur)
        dur = dur or 0.14
        tex.__tweenTicker = tex.__tweenTicker or CreateFrame("Frame")
        local t   = tex.__tweenTicker
        local from = tex:GetAlpha()
        local acc = 0
        t:Show()
        t:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt
            local p = math.min(1, acc / dur)
            local eased = 1 - (1 - p) * (1 - p) * (1 - p)
            tex:SetAlpha(from + (target - from) * eased)
            if p >= 1 then self:Hide(); self:SetScript("OnUpdate", nil) end
        end)
    end

    function bar:SelectTab(id)
        self.activeId = id
        for tid, b in pairs(self.buttons) do
            if tid == id then
                fadeTo(b.active,  0.18)
                fadeTo(b.marker,  1.0)
                fadeTo(b.chevron, 1.0)
                b.text:SetTextColor(unpack(UI.Color.textTitle))
            else
                fadeTo(b.active,  0)
                fadeTo(b.marker,  0)
                fadeTo(b.chevron, 0)
                b.text:SetTextColor(unpack(UI.Color.textPrimary))
            end
        end
    end

    return bar
end

function UI.MakeListRow(parent, opts)
    opts = opts or {}
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(opts.h or 28)
    if opts.alt then
        local fill = UI.SolidFill(r, UI.Color.bgRowAlt, "BACKGROUND")
        fill:SetAllPoints()
    end
    return r
end

function PA:RegisterModule(name, label, toggleFn, opts)
    for _, m in ipairs(self.modules) do
        if m.name == name then return end
    end
    table.insert(self.modules, {
        name   = name,
        label  = label,
        toggle = toggleFn,
        opts   = opts or {},
    })
end

function PA:Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

function PA.InsertChatLink(link)
    if not link then return false end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then return true end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
        return true
    end
    return false
end

function PA:ToggleMainMenu()
    if PA.mainFrame then
        if PA.mainFrame:IsShown() then
            if PA.mainFrame.AnimatedHide then
                PA.mainFrame:AnimatedHide()
            else
                PA.mainFrame:Hide()
            end
        else
            PA.mainFrame:Show()
        end
    end
end

SLASH_ASTRAL1 = "/astral"
SlashCmdList["ASTRAL"] = function() PA:ToggleMainMenu() end
