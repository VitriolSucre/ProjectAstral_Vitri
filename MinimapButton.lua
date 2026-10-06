
local RADIUS = 80

local angle  = 225

local function LoadAngleFromSettings()
    if ProjectAstralSettings and type(ProjectAstralSettings.minimapAngle) == "number" then
        angle = ProjectAstralSettings.minimapAngle
        return
    end
    local sv = ProjectAstral and ProjectAstral.Settings
    if sv and type(sv.minimapAngle) == "number" then
        angle = sv.minimapAngle
    end
end

local function SaveAngle(a)
    angle = a
    ProjectAstralSettings = ProjectAstralSettings or {}
    ProjectAstralSettings.minimapAngle = a
    if ProjectAstral and ProjectAstral.SaveSetting then
        ProjectAstral.SaveSetting("minimapAngle", a)
    elseif ProjectAstral and ProjectAstral.Settings then
        ProjectAstral.Settings.minimapAngle = a
    end
end

local function UpdatePosition(btn)
    local rad = math.rad(angle)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER",
        RADIUS * math.cos(rad),
        RADIUS * math.sin(rad))
end

local function CreateMinimapButton()
    local btn = CreateFrame("Button", "PAMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameLevel(100)
    btn:SetFrameStrata("MEDIUM")
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints(btn)
    icon:SetTexture("Interface\\AddOns\\ProjectAstral\\astralhub")

    btn:SetHighlightTexture(
        "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    LoadAngleFromSettings()
    UpdatePosition(btn)

    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s      = Minimap:GetEffectiveScale()
            angle = math.deg(math.atan2((cy / s) - my, (cx / s) - mx)) % 360
            UpdatePosition(self)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
        SaveAngle(angle)
    end)

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ProjectAstral:ToggleMainMenu()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Project Astral", 1, 0.82, 0, true)
        GameTooltip:AddLine("Open Astral systems menu.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Menu of the hub's sidebar groups, each with its tabs as a submenu, in the hub's
-- navy look (same colours as the MainMenu.lua sidebar). Opens above `anchor`;
-- submenus grow upward from their row, on whichever side has room. Hides on Escape,
-- on picking a tab, or a moment after the mouse leaves it.
local SOLID = "Interface\\Buttons\\WHITE8X8"
local MENU_W, SUB_W, ROW_H = 170, 190, 24
local NV_DEEP  = { 0.031, 0.047, 0.133, 0.97 }
local NV_EDGE  = { 0.165, 0.204, 0.400, 1 }
local NV_HOVER = { 0.100, 0.140, 0.320, 0.95 }
local GOLD     = { 0.886, 0.753, 0.384 }
local TXT_GOLD, TXT_MUTED, TXT_DIM = { 1.00, 0.85, 0.44 }, { 0.86, 0.87, 0.94 }, { 0.667, 0.690, 0.831 }

local function Tint(c)
    local UI = ProjectAstral.UI
    if UI and UI.Tint then local r, g, b = UI.Tint(c[1], c[2], c[3]); return { r, g, b, c[4] } end
    return c
end

local function NavyPanel(name)
    local f = CreateFrame("Frame", name, UIParent)
    f.__paBackdrop = true   -- Theme.lua greys navy backdrops otherwise
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    local bg, edge = Tint(NV_DEEP), Tint(NV_EDGE)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    f:Hide()
    return f
end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH("LEFT")
    return fs
end

local function MenuRow(parent, width, label)
    local r = CreateFrame("Button", nil, parent)
    r:SetSize(width, ROW_H)
    local hover = r:CreateTexture(nil, "BACKGROUND")
    hover:SetTexture(SOLID)
    hover:SetAllPoints()
    local h = Tint(NV_HOVER)
    hover:SetVertexColor(h[1], h[2], h[3], 0.70)
    hover:Hide()
    r.hover = hover
    local bar = r:CreateTexture(nil, "OVERLAY")
    bar:SetTexture(SOLID)
    bar:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
    bar:SetWidth(3)
    bar:Hide()
    r.bar = bar
    r.label = Text(r, 12, TXT_MUTED)
    r.label:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.label:SetText(label)
    return r
end

local function CreateHubMenu(anchor)
    local menu = NavyPanel("PAHubMicroMenu")
    tinsert(UISpecialFrames, "PAHubMicroMenu")
    local sub = NavyPanel(nil)
    sub:SetFrameLevel(menu:GetFrameLevel() + 5)

    local tabsById = {}
    for _, t in ipairs(ProjectAstral.HubTabs or {}) do tabsById[t.id] = t end

    local title = Text(menu, 11, TXT_GOLD)
    title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -9)
    title:SetText("PROJECT ASTRAL")

    local subRows, openRow = {}, nil
    local function OpenTab(id)
        menu:Hide()
        local hub = ProjectAstral.mainFrame
        if not hub then return end
        hub:Show()
        hub:SwitchTab(id)
    end
    local function ShowSub(row, group)
        if openRow then openRow.hover:Hide(); openRow.bar:Hide() end
        openRow = row
        row.hover:Show(); row.bar:Show()
        for _, r in ipairs(subRows) do r:Hide() end
        local n = 0
        for _, id in ipairs(group.ids) do
            local t = tabsById[id]
            if t then
                n = n + 1
                local r = subRows[n]
                if not r then
                    r = MenuRow(sub, SUB_W - 2, "")
                    r.icon = r:CreateTexture(nil, "ARTWORK")
                    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    r.icon:SetSize(18, 18)
                    r.icon:SetPoint("LEFT", r, "LEFT", 8, 0)
                    r.label:SetPoint("LEFT", r, "LEFT", 32, 0)
                    r:SetScript("OnEnter", function(self) self.hover:Show() end)
                    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
                    r:SetScript("OnClick", function(self) OpenTab(self.id) end)
                    subRows[n] = r
                end
                r.id = id
                r.icon:SetTexture(t.icon)
                r.label:SetText(t.navLabel or t.label)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", sub, "TOPLEFT", 1, -(4 + (n - 1) * ROW_H))
                r:Show()
            end
        end
        sub:SetSize(SUB_W, n * ROW_H + 8)
        sub:ClearAllPoints()
        -- right of the menu when it fits, otherwise left; bottom-aligned so it grows upward
        if (menu:GetRight() or 0) + SUB_W < UIParent:GetRight() then
            sub:SetPoint("BOTTOMLEFT", row, "BOTTOMRIGHT", 2, -4)
        else
            sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", -2, -4)
        end
        sub:Show()
    end

    local y = -26
    for _, group in ipairs(ProjectAstral.HubNavGroups or {}) do
        local g = group
        local row = MenuRow(menu, MENU_W - 2, g.label:sub(1, 1) .. g.label:sub(2):lower())
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, y)
        local arrow = Text(row, 12, TXT_DIM)
        arrow:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        arrow:SetText(">")
        row:SetScript("OnEnter", function(self) ShowSub(self, g) end)
        row:SetScript("OnClick", function(self) ShowSub(self, g) end)
        y = y - ROW_H
    end
    menu:SetSize(MENU_W, -y + 6)
    menu:SetPoint("BOTTOM", anchor, "TOP", 0, 2)

    -- hide a moment after the mouse leaves the button, the menu and its submenu
    local away = 0
    menu:SetScript("OnShow", function() away = 0 end)
    menu:SetScript("OnHide", function()
        sub:Hide()
        if openRow then openRow.hover:Hide(); openRow.bar:Hide(); openRow = nil end
    end)
    menu:SetScript("OnUpdate", function(_, elapsed)
        if MouseIsOver(menu) or MouseIsOver(anchor) or (sub:IsShown() and MouseIsOver(sub)) then
            away = 0
        else
            away = away + elapsed
            if away > 0.8 then menu:Hide() end
        end
    end)
    return menu
end

-- Hub button in the micro menu bar, between Dungeon Finder and the Game Menu.
-- Same frame as the Character button, with the minimap button's icon inside it.
-- ponytail: the bar is one button wider, so it can touch the bag slots at small UI scales.
local function CreateMicroButton()
    if not (LFDMicroButton and MainMenuMicroButton) then return end
    -- same parent as the other micro buttons (MainMenuBarArtFrame): under MainMenuBar the bar art covers it
    local btn = CreateFrame("Button", "PAHubMicroButton", LFDMicroButton:GetParent(), "MainMenuBarMicroButton")
    -- Character button's frame (blank inside) with the minimap icon where the portrait goes
    btn:SetNormalTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Up")
    btn:SetPushedTexture("Interface\\Buttons\\UI-MicroButtonCharacter-Down")
    btn:SetHighlightTexture("Interface\\Buttons\\UI-MicroButton-Hilight")
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\AddOns\\ProjectAstral\\astralhub")
    icon:SetSize(18, 25)
    icon:SetTexCoord(0.14, 0.86, 0, 1)   -- square icon cropped to the portrait's 18x25
    icon:SetPoint("TOP", btn, "TOP", 0, -28)
    btn:HookScript("OnMouseDown", function() icon:SetPoint("TOP", btn, "TOP", -1, -29); icon:SetAlpha(0.6) end)
    btn:HookScript("OnMouseUp", function() icon:SetPoint("TOP", btn, "TOP", 0, -28); icon:SetAlpha(1) end)

    btn:SetPoint("BOTTOMLEFT", LFDMicroButton, "BOTTOMRIGHT", -3, 0)
    MainMenuMicroButton:ClearAllPoints()
    MainMenuMicroButton:SetPoint("BOTTOMLEFT", btn, "BOTTOMRIGHT", -3, 0)

    local menu = CreateHubMenu(btn)
    btn:SetScript("OnClick", function()
        GameTooltip:Hide()
        if menu:IsShown() then menu:Hide() else menu:Show() end
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Project Astral", 1, 1, 1)
        GameTooltip:AddLine("Pick a section of the Astral hub.", NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- stays pressed while the hub is open, like the other micro buttons
    local hub = ProjectAstral.mainFrame
    if hub then
        hub:HookScript("OnShow", function() btn:SetButtonState("PUSHED", 1) end)
        hub:HookScript("OnHide", function() btn:SetButtonState("NORMAL") end)
    end
end

local evt = CreateFrame("Frame")
evt:RegisterEvent("PLAYER_LOGIN")
evt:SetScript("OnEvent", function()
    CreateMinimapButton()
    CreateMicroButton()
end)

ProjectAstral.MinimapButton = ProjectAstral.MinimapButton or {}
function ProjectAstral.MinimapButton.SetVisible(visible)
    if PAMinimapButton then
        if visible then PAMinimapButton:Show() else PAMinimapButton:Hide() end
    end
end
