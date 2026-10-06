
local PA = ProjectAstral
local UI = PA.UI

-- Docks Blizzard's PlayerTalentFrame into a host frame inside the Astral Tree card
-- (Skilltree.lua BuildTreeTab) while that host is on screen, and hands it back to
-- UIParent exactly as it was when it isn't, so the N key / talent micro button
-- keep working normally everywhere else.

PA.ClassTalents = PA.ClassTalents or {}

local host
local docked = false
local saved
local Undock

local function CollectLevels(frame)
    local list = {}
    local function walk(fr)
        list[#list + 1] = { fr, fr:GetFrameLevel() }
        for _, c in ipairs({ fr:GetChildren() }) do walk(c) end
    end
    walk(frame)
    return list
end

local function ApplyLevels(list, delta)
    for _, e in ipairs(list) do
        e[1]:SetFrameLevel(math.max(0, e[2] + delta))
    end
end

local SOLID = "Interface\\Buttons\\WHITE8X8"
local EDGE  = "Interface\\Tooltips\\UI-Tooltip-Border"

local KEEP_PATHS        = { "talentbranches", "talentarrows" }
local HIDE_BUTTON_PATHS = { "spellbook-skilllinetab", "ui-panel-button" }

local fadedRegions   = {}
local fadedBackdrops = {}
local styledButtons  = {}
local treeTabs       = {}

local function PathOf(region)
    local p = region and region.GetTexture and region:GetTexture()
    return type(p) == "string" and p:lower() or ""
end

local function MatchesAny(path, list)
    for _, pat in ipairs(list) do
        if path:find(pat, 1, true) then return true end
    end
    return false
end

local function IsTreeTab(b)
    local name = b:GetName()
    return name ~= nil and name:find("^PlayerTalentFrameTab%d+$") ~= nil
end

local function Fade(region)
    if fadedRegions[region] == nil then fadedRegions[region] = region:GetAlpha() end
    region:SetAlpha(0)
end

local function StyleButton(b)
    if styledButtons[b] then return end
    styledButtons[b] = { font = b.GetNormalFontObject and b:GetNormalFontObject() }
    b:SetBackdrop({ bgFile = SOLID, edgeFile = EDGE, tile = false, edgeSize = 10,
                    insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    b:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.92))
    b:SetBackdropBorderColor(unpack(UI.Nav.edgeMid))
    if b.SetNormalFontObject then b:SetNormalFontObject(GameFontHighlight) end
    if not b.__paHoverHooked then
        b.__paHoverHooked = true
        b:HookScript("OnEnter", function(self)
            if styledButtons[self] then self:SetBackdropBorderColor(unpack(UI.Nav.hot)) end
        end)
        b:HookScript("OnLeave", function(self)
            if styledButtons[self] then self:SetBackdropBorderColor(unpack(UI.Nav.edgeMid)) end
        end)
    end
end

local function StyleTreeTab(b)
    local t = treeTabs[b]
    if not t then
        t = {}
        local line = b:CreateTexture(nil, "OVERLAY")
        line.__paOwn = true
        line:SetTexture(SOLID)
        line:SetVertexColor(unpack(UI.Color.textTitle))
        line:SetHeight(2)
        local fs = b:GetFontString()
        if fs then
            line:SetPoint("TOPLEFT",  fs, "BOTTOMLEFT",  -2, -3)
            line:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT",  2, -3)
        else
            line:SetPoint("BOTTOMLEFT",  b, "BOTTOMLEFT",   8, 6)
            line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 6)
        end
        line:Hide()
        t.line = line
        treeTabs[b] = t
    end
    if not t.fonts and b.GetNormalFontObject then
        t.fonts = { b:GetNormalFontObject(), b:GetHighlightFontObject(), b:GetDisabledFontObject() }
        b:SetNormalFontObject(GameFontDisableSmall)
        b:SetHighlightFontObject(GameFontHighlightSmall)
        b:SetDisabledFontObject(GameFontHighlightSmall)
    end
end

local function PaintTreeTabs()
    for b, t in pairs(treeTabs) do
        if docked and b:IsShown() and not b:IsEnabled() then t.line:Show() else t.line:Hide() end
    end
end

local function StripArt(frame, insideButton)
    if frame.__paOwn then return end
    local kind     = frame:GetObjectType()
    local isButton = kind == "Button" or kind == "CheckButton"
    local isTab    = isButton and IsTreeTab(frame)
    local keepArt  = insideButton or kind == "Slider" or (isButton and not isTab)

    for _, r in ipairs({ frame:GetRegions() }) do
        if r.GetTexture and not r.__paOwn then
            local path = PathOf(r)
            local keep
            if MatchesAny(path, KEEP_PATHS) then
                keep = true
            elseif isTab or (isButton and MatchesAny(path, HIDE_BUTTON_PATHS)) then
                keep = false
            else
                keep = keepArt
            end
            if not keep then Fade(r) end
        end
    end

    if isTab then
        StyleTreeTab(frame)
    elseif isButton and PathOf(frame:GetNormalTexture()):find("ui-panel-button", 1, true) then
        StyleButton(frame)
    end

    if not isButton and kind ~= "Slider" and frame.GetBackdrop and not fadedBackdrops[frame] then
        local ok, bd = pcall(frame.GetBackdrop, frame)
        if ok and type(bd) == "table" then
            fadedBackdrops[frame] = { bg   = { frame:GetBackdropColor() },
                                      edge = { frame:GetBackdropBorderColor() } }
            frame:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0))
            frame:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 0))
        end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        StripArt(child, insideButton or isButton)
    end
end

local function RestoreArt()
    for r, a in pairs(fadedRegions) do r:SetAlpha(a) end
    wipe(fadedRegions)
    for fr, s in pairs(fadedBackdrops) do
        fr:SetBackdropColor(unpack(s.bg))
        fr:SetBackdropBorderColor(unpack(s.edge))
    end
    wipe(fadedBackdrops)
    for b, s in pairs(styledButtons) do
        b:SetBackdrop(nil)
        if s.font and b.SetNormalFontObject then b:SetNormalFontObject(s.font) end
    end
    wipe(styledButtons)
    for b, t in pairs(treeTabs) do
        t.line:Hide()
        if t.fonts then
            if t.fonts[1] then b:SetNormalFontObject(t.fonts[1]) end
            if t.fonts[2] then b:SetHighlightFontObject(t.fonts[2]) end
            if t.fonts[3] then b:SetDisabledFontObject(t.fonts[3]) end
            t.fonts = nil
        end
    end
end

local function SetStatus(text, showButton)
    if not host then return end
    host.status:SetText(text or "")
    host.status:Show()
    if showButton then host.showBtn:Show() else host.showBtn:Hide() end
end

local function Dock()
    if docked or not (host and host:IsVisible()) then return end

    local minLevel = SHOW_TALENT_LEVEL or 10
    if UnitLevel("player") < minLevel then
        SetStatus("Class talents unlock at level " .. minLevel .. ".", false)
        return
    end

    if not PlayerTalentFrame then LoadAddOn("Blizzard_TalentUI") end
    local tf = PlayerTalentFrame
    if not tf then
        SetStatus("The Blizzard talent UI could not be loaded.", false)
        return
    end

    if tf:IsShown() then HideUIPanel(tf) end

    saved = {
        parent   = tf:GetParent(),
        strata   = tf:GetFrameStrata(),
        toplevel = tf.IsToplevel and tf:IsToplevel(),
        scale    = tf:GetScale(),
        levels   = CollectLevels(tf),
        points   = {},
    }
    for i = 1, tf:GetNumPoints() do saved.points[i] = { tf:GetPoint(i) } end

    if not tf.__paHideHooked then
        tf.__paHideHooked = true
        tf:HookScript("OnHide", function()
            if docked then Undock() end
        end)
    end

    docked = true
    tf.__paNoSkin = true
    tf:SetParent(host)
    tf:SetFrameStrata(host:GetFrameStrata())
    if tf.SetToplevel then tf:SetToplevel(false) end
    tf:SetScale(1)
    tf:ClearAllPoints()
    tf:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -16)
    ApplyLevels(saved.levels, (host:GetFrameLevel() + 1) - saved.levels[1][2])
    if PlayerTalentFrameCloseButton then PlayerTalentFrameCloseButton:Hide() end
    StripArt(tf)
    if PlayerTalentFrameTitleText then Fade(PlayerTalentFrameTitleText) end

    host.status:Hide()
    host.showBtn:Hide()
    tf:Show()
    PaintTreeTabs()
end

Undock = function()
    if not docked then return end
    docked = false
    local tf = PlayerTalentFrame
    if tf:IsShown() then tf:Hide() end

    tf:SetParent(saved.parent or UIParent)
    tf:SetFrameStrata(saved.strata)
    if tf.SetToplevel then tf:SetToplevel(saved.toplevel and true or false) end
    tf:SetScale(saved.scale or 1)
    tf:ClearAllPoints()
    for _, p in ipairs(saved.points) do tf:SetPoint(unpack(p)) end
    ApplyLevels(saved.levels, 0)
    if PlayerTalentFrameCloseButton then PlayerTalentFrameCloseButton:Show() end
    RestoreArt()

    SetStatus("Class talents were closed.", true)
end

function PA.ClassTalents.AttachHost(frame)
    host = frame
    local divider = frame:CreateTexture(nil, "BORDER")
    divider:SetTexture(SOLID)
    divider:SetVertexColor(UI.Nav.edge[1], UI.Nav.edge[2], UI.Nav.edge[3], 0.8)
    divider:SetWidth(1)
    divider:SetPoint("TOPRIGHT",    frame, "TOPRIGHT",    0, -8)
    divider:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 8)

    local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("CENTER", frame, "CENTER", 0, 20)
    status:SetWidth(320)
    status:SetTextColor(unpack(UI.Nav.muted))
    status:Hide()
    frame.status = status

    local showBtn = UI.MakeButton(frame, "Show class talents here", {
        w = 200, h = 26, variant = "gold",
        onClick = function() Dock() end,
    })
    showBtn:SetPoint("TOP", status, "BOTTOM", 0, -12)
    showBtn:Hide()
    frame.showBtn = showBtn

    frame:SetScript("OnShow", function() Dock() end)
    frame:SetScript("OnHide", function() Undock() end)
end

local function RestripIfDocked()
    if docked and PlayerTalentFrame then
        StripArt(PlayerTalentFrame)
        PaintTreeTabs()
    end
end

if PanelTemplates_UpdateTabs then
    hooksecurefunc("PanelTemplates_UpdateTabs", function(frame)
        if frame == PlayerTalentFrame then RestripIfDocked() end
    end)
end

local glyphHooked = false
local function HookGlyphFrame()
    if glyphHooked or not GlyphFrame then return end
    glyphHooked = true
    GlyphFrame:HookScript("OnShow", RestripIfDocked)
end

local glyphWatch = CreateFrame("Frame")
glyphWatch:RegisterEvent("ADDON_LOADED")
glyphWatch:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_GlyphUI" then HookGlyphFrame() end
end)
HookGlyphFrame()

-- ── FIXED: Talent key (N) now opens Blizzard talent tree normally ──
-- The override binding that redirected N to the Astral hub has been disabled.
-- Pressing N will now open the Blizzard talent tree as expected.
