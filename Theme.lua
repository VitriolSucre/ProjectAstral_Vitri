
local PA = ProjectAstral
local UI = PA.UI

-- Astral theme skinner. Restyles Blizzard template widgets (scroll bars, dropdowns,
-- sliders, check boxes, input boxes, panel buttons, default gold text, navy
-- backdrops) inside Astral frames so every module matches the hub instead of the
-- stock WoW look. Visual only: scripts and widget behaviour are untouched, and each
-- widget is skinned once, so UI.SkinTree can be called as often as needed.

local SOLID = "Interface\\Buttons\\WHITE8X8"
local EDGE  = "Interface\\Tooltips\\UI-Tooltip-Border"

local roots = setmetatable({}, { __mode = "k" })

-- Unpacking a huge container's regions/children into a table ({ f:GetRegions() })
-- overflows the C stack (the skill tree canvas holds thousands of line textures).
-- Containers that big are custom-drawn and never hold Blizzard template widgets.
local MAX_UNPACK = 400

local function TexPath(region)
    local p = region and region.GetTexture and region:GetTexture()
    return type(p) == "string" and p:lower() or ""
end

local function Fill(owner, layer, c, a)
    local t = owner:CreateTexture(nil, layer)
    t:SetTexture(SOLID)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end

-- 1px outline around `anchor` (backdrop edges are too thick for small widgets)
local function Outline(owner, anchor, layer, c, a)
    local lines = {}
    local function line()
        local t = owner:CreateTexture(nil, layer)
        t:SetTexture(SOLID)
        t:SetVertexColor(c[1], c[2], c[3], a or 1)
        lines[#lines + 1] = t
        return t
    end
    local top = line()
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT"); top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT"); top:SetHeight(1)
    local bottom = line()
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT"); bottom:SetHeight(1)
    local left = line()
    left:SetPoint("TOPLEFT", anchor, "TOPLEFT"); left:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT"); left:SetWidth(1)
    local right = line()
    right:SetPoint("TOPRIGHT", anchor, "TOPRIGHT"); right:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT"); right:SetWidth(1)
    return lines
end
UI.Outline = Outline

-- Flat, borderless Astral window background (no thick grey UI.MakePanel frame).
-- VIBRANT: Make backgrounds more solid and dark
function UI.FlatBackdrop(frame, alpha)
    frame:SetBackdrop({ bgFile = SOLID, tile = false,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    local c = UI.Nav and UI.Nav.deep or UI.Color.bgDeep   -- unified navy
    frame:SetBackdropColor(c[1], c[2], c[3], alpha or 0.98)  -- More opaque
end

-- ── Individual widget skins ─────────────────────────────────────────

local function SkinScrollBar(bar)
    if bar.__paSkinned then return end
    bar.__paSkinned = true
    local name  = bar:GetName()
    local thumb = bar:GetThumbTexture()

    for _, suffix in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local b = name and _G[name .. suffix]
        if b then b:SetAlpha(0); b:EnableMouse(false) end   -- wheel + thumb still scroll
    end
    for _, r in ipairs({ bar:GetRegions() }) do            -- template track art, if any
        if r ~= thumb and r.GetTexture then r:SetAlpha(0) end
    end

    local track = Fill(bar, "BACKGROUND", UI.Nav.edge, 0.55)
    track:SetWidth(4)
    track:SetPoint("TOP",    bar, "TOP",    0, 0)
    track:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

    if thumb then
        thumb:SetTexture(SOLID)
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetVertexColor(unpack(UI.Color.accentSoft))
        thumb:SetWidth(6)
    end
end

local function SkinSlider(s)
    if s.__paSkinned then return end
    local thumb = s:GetThumbTexture()
    if not (thumb and TexPath(thumb):find("sliderbar", 1, true)) then return end
    s.__paSkinned = true

    s:SetBackdrop(nil)
    local track = Fill(s, "BACKGROUND", UI.Nav.deep, 0.95)
    if s.GetOrientation and s:GetOrientation() == "VERTICAL" then
        track:SetWidth(6)
        track:SetPoint("TOP", s, "TOP", 0, -4)
        track:SetPoint("BOTTOM", s, "BOTTOM", 0, 4)
    else
        track:SetHeight(6)
        track:SetPoint("LEFT", s, "LEFT", 4, 0)
        track:SetPoint("RIGHT", s, "RIGHT", -4, 0)
    end
    Outline(s, track, "BORDER", UI.Nav.edgeMid, 1)

    thumb:SetTexture(SOLID)
    thumb:SetTexCoord(0, 1, 0, 1)
    thumb:SetSize(8, 16)
    thumb:SetVertexColor(unpack(UI.Color.textTitle))
end

local function SkinCheck(cb)
    if cb.__paSkinned then return end
    local normal = cb:GetNormalTexture()
    if not (normal and TexPath(normal):find("checkbox", 1, true)) then return end
    cb.__paSkinned = true

    local inset = math.floor((cb:GetWidth() or 26) * 0.24)
    local function Box(tex, extra, c, a)
        if not tex then return end
        tex:SetTexture(SOLID)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT",     cb, "TOPLEFT",      inset + extra, -(inset + extra))
        tex:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -(inset + extra),  inset + extra)
        tex:SetVertexColor(c[1], c[2], c[3], a)
    end
    Box(normal, 0, UI.Nav.deep, 0.95)
    Box(cb:GetPushedTexture(), 0, UI.Nav.hover, 1)
    Box(cb:GetHighlightTexture(), 0, UI.Nav.hot, 0.12)
    Box(cb:GetCheckedTexture(), 3, UI.Color.textTitle, 1)
    Box(cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture(), 3, UI.Color.textMuted, 1)
    Outline(cb, normal, "OVERLAY", UI.Nav.edgeMid, 1)
end

local function SkinEditBox(eb)
    if eb.__paSkinned then return end
    local found = false
    for _, r in ipairs({ eb:GetRegions() }) do
        if r.GetTexture and TexPath(r):find("common-input-border", 1, true) then
            r:SetAlpha(0)
            found = true
        end
    end
    if not found then return end
    eb.__paSkinned = true

    local bg = Fill(eb, "BACKGROUND", UI.Nav.deep, 0.9)
    bg:SetPoint("TOPLEFT",     eb, "TOPLEFT",    -5, 0)
    bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 0)
    Outline(eb, bg, "BORDER", UI.Nav.edge, 1)
end

local function SkinDropDown(dd)
    if dd.__paSkinned then return end
    local name = dd:GetName()
    if not name then return end
    local left, mid, right = _G[name .. "Left"], _G[name .. "Middle"], _G[name .. "Right"]
    if not (left and mid and right and left.GetTexture) then return end
    dd.__paSkinned = true

    left:SetAlpha(0); mid:SetAlpha(0); right:SetAlpha(0)
    -- the template art is 64px tall with the visible box in its middle ~28px
    local bg = Fill(dd, "BACKGROUND", UI.Nav.deep, 0.9)
    bg:SetPoint("TOPLEFT",     left,  "TOPLEFT",     17, -18)
    bg:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -17, 18)
    Outline(dd, bg, "BORDER", UI.Nav.edge, 1)

    local btn = _G[name .. "Button"]
    if btn then
        for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
            local t = btn[getter] and btn[getter](btn)
            if t then
                t:SetDesaturated(true)
                t:SetVertexColor(0.85, 0.85, 0.90)
            end
        end
    end
end

local function SkinButton(b)
    if b.__paSkinned or b.__paGlow then return end   -- __paGlow: already UI.CosmicButton
    local normal = b:GetNormalTexture()
    if normal and TexPath(normal):find("ui-panel-button", 1, true) then
        b.__paSkinned = true
        UI.CosmicButton(b)
        return
    end
    -- Blizzard list highlights (gold bars) → soft white wash
    local hl = b:GetHighlightTexture()
    local p = TexPath(hl)
    if p:find("listbox-highlight", 1, true) or p:find("questtitlehighlight", 1, true) then
        b.__paSkinned = true
        hl:SetTexture(SOLID)
        hl:SetTexCoord(0, 1, 0, 1)
        hl:SetVertexColor(1, 1, 1, 0.08)
    end
end

-- VIBRANT: Make ALL text vivid white/gray, not just gold text
-- This runs on EVERY frame that gets skinned, so it catches everything
local function RecolorGoldText(frame)
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            local text = r:GetText() or ""
            -- Skip color-coded text (|cffXXXXXX format)
            if not text:find("|c%x%x%x%x%x%x%x%x") then
                local font, size, flags = r:GetFont()
                local fontPath = (font or ""):upper()

                -- Make all text vivid based on font type
                if fontPath:find("MORPHEUS") then
                    r:SetTextColor(1.0, 1.0, 1.0)  -- Titles: pure white
                elseif fontPath:find("DISABLE") then
                    r:SetTextColor(0.75, 0.75, 0.80)  -- Disabled: bright gray
                elseif fontPath:find("HIGHLIGHT") then
                    r:SetTextColor(0.98, 0.98, 1.0)  -- Highlights: near-white
                else
                    r:SetTextColor(1.0, 1.0, 1.0)  -- Body: pure white (was 0.96)
                end

                -- Add shadow for readability
                r:SetShadowColor(0, 0, 0, 1.0)
                r:SetShadowOffset(1, -1)
            end
        end
    end
end

-- Navy-tinted dark backdrops → neutral Astral greys of the same brightness.
-- Saturated borders (tier colours, currency dots) are left alone.
-- windows and tabs restyled in the unified look mark their root __paUnified:
-- their navy surfaces are kept as they are
local function InUnified(f)
    local depth = 0
    while f and depth < 16 do
        if f.__paUnified then return true end
        f = f.GetParent and f:GetParent()
        depth = depth + 1
    end
    return false
end

local function NormalizeBackdrop(f)
    if f.__paBackdrop or not f.GetBackdrop or InUnified(f) then return end
    f.__paBackdrop = true
    local ok, bd = pcall(f.GetBackdrop, f)
    if not (ok and type(bd) == "table") then return end

    if type(bd.edgeFile) == "string" and bd.edgeFile:lower():find("dialogbox", 1, true) then
        UI.AstralBackdrop(f, { thin = true })
        return
    end

    local r, g, b, a = f:GetBackdropColor()
    if r and math.max(r, g, b) < 0.22 and (b - r) > 0.015 then
        local v = (r + g + b) / 3
        f:SetBackdropColor(v, v, v, a)
    end
    local er, eg, eb, ea = f:GetBackdropBorderColor()
    if er and (eb - er) > 0.04 and (math.max(er, eg, eb) - math.min(er, eg, eb)) < 0.3 then
        local v = (er + eg + eb) / 3
        f:SetBackdropBorderColor(v, v, v, ea)
    end
end

-- ── Public entry point ──────────────────────────────────────────────

function UI.SkinTree(root)
    if not root then return end
    roots[root] = true
    local function walk(f)
        if f.__paNoSkin then return end   -- e.g. Blizzard's docked talent frame
        local kind = f:GetObjectType()
        if kind == "Slider" then
            local name   = f:GetName()
            local parent = f:GetParent()
            if (name and name:find("ScrollBar$"))
               or (parent and parent.GetObjectType and parent:GetObjectType() == "ScrollFrame") then
                SkinScrollBar(f)
            else
                SkinSlider(f)
            end
        elseif kind == "CheckButton" then
            SkinCheck(f)
        elseif kind == "Button" then
            SkinButton(f)
        elseif kind == "EditBox" then
            SkinEditBox(f)
        elseif kind == "Frame" then
            SkinDropDown(f)
        end
        if kind ~= "Button" and kind ~= "CheckButton" then NormalizeBackdrop(f) end
        local numRegions  = f.GetNumRegions  and f:GetNumRegions()  or MAX_UNPACK + 1
        local numChildren = f.GetNumChildren and f:GetNumChildren() or MAX_UNPACK + 1
        if numRegions <= MAX_UNPACK then RecolorGoldText(f) end
        if numChildren <= MAX_UNPACK then
            for _, child in ipairs({ f:GetChildren() }) do walk(child) end
        end
    end
    walk(root)
end

function UI.IsAstralFrame(frame)
    local depth = 0
    while frame and depth < 40 do
        if roots[frame] then return true end
        frame = frame.GetParent and frame:GetParent()
        depth = depth + 1
    end
    return false
end

-- ── Dropdown lists opened from Astral frames ───────────────────────
-- DropDownList1/2 are shared by every addon and Blizzard menu, so they are only
-- themed while one of ours is open and restored for everyone else.
local savedLists = {}
local function ThemeDropDownList(level, themed)
    for _, suffix in ipairs({ "Backdrop", "MenuBackdrop" }) do
        local bd  = _G["DropDownList" .. level .. suffix]
        local key = level .. suffix
        if bd and bd.GetBackdrop then
            if themed then
                if not savedLists[key] then
                    local ok, orig = pcall(bd.GetBackdrop, bd)
                    if ok and type(orig) == "table" then
                        savedLists[key] = {
                            backdrop = orig,
                            bg   = { bd:GetBackdropColor() },
                            edge = { bd:GetBackdropBorderColor() },
                        }
                    end
                end
                if savedLists[key] then
                    bd:SetBackdrop({ bgFile = SOLID, edgeFile = EDGE, edgeSize = 12,
                                     insets = { left = 3, right = 3, top = 3, bottom = 3 } })
                    bd:SetBackdropColor(unpack(UI.Nav.deep))
                    bd:SetBackdropBorderColor(unpack(UI.Nav.edgeMid))
                end
            elseif savedLists[key] then
                local s = savedLists[key]
                savedLists[key] = nil
                bd:SetBackdrop(s.backdrop)
                bd:SetBackdropColor(unpack(s.bg))
                bd:SetBackdropBorderColor(unpack(s.edge))
            end
        end
    end
end

if ToggleDropDownMenu then
    hooksecurefunc("ToggleDropDownMenu", function(level, _, dropDownFrame)
        level = level or 1
        local owner = dropDownFrame or UIDROPDOWNMENU_OPEN_MENU
        if type(owner) == "string" then owner = _G[owner] end
        ThemeDropDownList(level, owner and UI.IsAstralFrame(owner) or false)
    end)
end

-- ── Themed multi-line text dialog (export / import) ─────────────────
local dialogCount = 0
function UI.MakeTextDialog(opts)
    opts = opts or {}
    dialogCount = dialogCount + 1
    local name = opts.name or ("PATextDialog" .. dialogCount)
    local w, h = opts.width or 540, opts.height or 320

    local f = UI.MakePanel(UIParent, w, h, { name = name, movable = true, strata = "DIALOG" })
    f:SetFrameLevel(120)
    f:Hide()
    tinsert(UISpecialFrames, name)

    f.header = UI.MakeHeader(f, opts.title or "", opts.subtitle)

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT",     f, "TOPLEFT",     18, -80)
    box:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 74)
    UI.AstralBackdrop(box, { thin = true, bg = UI.Nav.deep, border = UI.Nav.edge })

    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     box, "TOPLEFT",     8, -8)
    scroll:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -28, 8)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetMaxLetters(0)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(unpack(UI.Color.textPrimary))
    edit:SetWidth(w - 72)
    edit:SetHeight(h - 170)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    scroll:SetScrollChild(edit)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.editBox = edit

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT",  box, "BOTTOMLEFT",  2, -6)
    status:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", -2, -6)
    status:SetHeight(28)
    status:SetJustifyH("LEFT")
    status:SetJustifyV("TOP")
    status:SetTextColor(unpack(UI.Color.textMuted))
    f.status = status

    local btn1 = UI.MakeButton(f, opts.button1Label or "OK", {
        w = 150, h = 26, variant = "primary",
        onClick = function()
            -- onAccept returns true to keep the dialog open (e.g. a check step)
            local keepOpen = opts.onAccept and opts.onAccept(edit:GetText(), f)
            if not keepOpen then f:Hide() end
        end,
    })
    btn1:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14)
    f.button1 = btn1

    local btn2 = UI.MakeButton(f, "Cancel", {
        w = 90, h = 26, variant = "secondary",
        onClick = function() f:Hide() end,
    })
    btn2:SetPoint("RIGHT", btn1, "LEFT", -8, 0)

    UI.SkinTree(f)
    return f
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- VIBRANT PATCH: Override colors and add vivid text enforcement
-- ═══════════════════════════════════════════════════════════════════════════════

-- Override UI.Color with MORE vivid values
UI.Color.bgDeep      = { 0.02, 0.02, 0.03, 0.98 }  -- Darker, more solid
UI.Color.bgPanel     = { 0.04, 0.04, 0.06, 0.98 }  -- Darker, more solid
UI.Color.bgRowAlt    = { 0.08, 0.08, 0.10, 0.60 }
UI.Color.bgHover     = { 0.15, 0.15, 0.18, 0.95 }

UI.Color.borderDim   = { 0.25, 0.25, 0.30, 1.0 }
UI.Color.borderMid   = { 0.40, 0.40, 0.45, 1.0 }
UI.Color.borderHot   = { 1.00, 1.00, 1.00, 1.0 }

-- VIVID TEXT - Pure white everywhere
UI.Color.textTitle   = { 1.00, 1.00, 1.00 }  -- Pure white
UI.Color.textPrimary = { 1.00, 1.00, 1.00 }  -- Pure white (was 0.96)
UI.Color.textMuted   = { 0.80, 0.80, 0.85 }  -- Bright gray (was 0.72)
UI.Color.textAccent  = { 1.00, 1.00, 1.00 }  -- Pure white (was 0.97)
UI.Color.textHi      = { 1.00, 0.95, 0.50 }  -- Bright gold
UI.Color.textGood    = { 0.50, 1.00, 0.65 }  -- Vivid green
UI.Color.textBad     = { 1.00, 0.40, 0.40 }  -- Vivid red
UI.Color.textWarn    = { 1.00, 0.85, 0.35 }  -- Vivid amber

UI.Color.accent      = { 1.00, 1.00, 1.00 }
UI.Color.accentSoft  = { 0.90, 0.90, 0.95 }  -- Brighter (was 0.84)

-- Function to fix a FontString to be vivid
local function FixFontString(fs)
    if not fs or not fs.GetObjectType then return end
    if fs:GetObjectType() ~= "FontString" then return end

    local text = fs:GetText() or ""
    if text:find("|c%x%x%x%x%x%x%x%x") then return end

    local font = fs:GetFont()
    local fontPath = (font or ""):upper()

    -- VIBRANT: Pure white for all text
    if fontPath:find("MORPHEUS") then
        fs:SetTextColor(1.0, 1.0, 1.0)  -- Titles: pure white
    elseif fontPath:find("DISABLE") then
        fs:SetTextColor(0.80, 0.80, 0.85)  -- Disabled: bright gray
    else
        fs:SetTextColor(1.0, 1.0, 1.0)  -- Body: pure white
    end

    -- Strong shadow for readability
    fs:SetShadowColor(0, 0, 0, 1.0)
    fs:SetShadowOffset(1, -1)
end

-- Recursively fix all FontStrings in a frame
local function FixFrame(frame, depth)
    if not frame or depth > 20 then return end

    local ok, regions = pcall(frame.GetRegions, frame)
    if ok and regions then
        for i = 1, #regions do
            FixFontString(regions[i])
        end
    end

    local ok2, children = pcall(frame.GetChildren, frame)
    if ok2 and children then
        for i = 1, #children do
            FixFrame(children[i], depth + 1)
        end
    end
end

-- Public function to make a panel vibrant
function UI.MakeVivid(panel)
    if not panel then return end
    FixFrame(panel, 0)
end

-- Apply to hub content
local function ApplyToHub()
    if not PA.mainFrame then return end

    if PA.mainFrame.page then
        UI.MakeVivid(PA.mainFrame.page)
    end

    if PA.mainFrame.visibleSections then
        for _, section in ipairs(PA.mainFrame.visibleSections) do
            if section.card then UI.MakeVivid(section.card) end
            if section.panel then UI.MakeVivid(section.panel) end
        end
    end
end

-- Hook hub tab switching
local waiter = CreateFrame("Frame")
local elapsed = 0
waiter:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 1.0 then return end
    elapsed = 0

    if PA.mainFrame and PA.mainFrame.SwitchTab and not PA.mainFrame.__vibrantHooked then
        local origSwitch = PA.mainFrame.SwitchTab
        PA.mainFrame.SwitchTab = function(self, tabId)
            origSwitch(self, tabId)
            C_Timer.After(0.1, ApplyToHub)
        end
        PA.mainFrame.__vibrantHooked = true

        PA.mainFrame:HookScript("OnShow", function()
            C_Timer.After(0.2, ApplyToHub)
        end)

        self:SetScript("OnUpdate", nil)
    end
end)

-- Slash command
SLASH_VIBRANT1 = "/vibrant"
SlashCmdList["VIBRANT"] = function()
    ApplyToHub()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[Vibrant]|r Applied!")
end
