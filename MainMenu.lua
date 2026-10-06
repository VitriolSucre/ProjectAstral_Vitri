-- MainMenu.lua - MERGED VERSION
-- Combines live GitHub version + Cosmic purple theme improvements

local PA = ProjectAstral
local UI = PA.UI

-- Hub: modules grouped into tabs, each tab a scrolling page of cards.
local PANEL_W, PANEL_H = 560, 550
local PANEL_SIZE = {
    Settings      = { h = function(panelW) return panelW >= 900 and (PANEL_H + 60) or 1598 end },
}
-- MERGED: Added more modules to FILL table so they fill the window
local FILL = {
    astral_tree = true,
    astral_stats = true,
    paragon = true,
    Settings = true,
    loadouts = true,
    new_player_guide = true,
    
    GemStash = true,
    gem_builds = true,
    talent_builds = true,
    set_builds = true,
    LockoutReset = true,
    Leaderboard = true,
    reagent_bank = true,
    GemFusion = true,
    AstralGems = true,
    astral_disenchant = true,
    prestige_store = true,
    collections = true,
}

local TABS = {
    {
        id = "skills", label = "Astral Tree",
        icon = "Interface\\Icons\\Spell_Holy_MagicalSentry",
        -- MERGED: Changed from blue to cosmic purple
        color = UI.Tinted({ 0.55, 0.45, 0.95 }),
        subtitle = "The Astral Skill Tree, with your class talents built in.",
        rows = { { "astral_tree" } },
    },
    {
        id = "stats", label = "Stats",
        -- Account Overview and the old Home page were merged into this tab
        aliases = { "account_overview", "overview", "project_astral", "home" },
        icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        color = UI.Tinted({ 0.60, 0.52, 0.95 }),
        subtitle = "Your character, wallet and every bonus from the Astral Tree and Paragon.",
        rows = { { "astral_stats" } },
    },
    {
        id = "paragon", label = "Paragon",
        icon = "Interface\\Icons\\Achievement_Level_80",
        color = { 1.00, 0.78, 0.30 },
        subtitle = "Shape your character with permanent Paragon bonuses.",
        rows = { { "paragon" } },
    },
    {
        id = "astral_gems", label = "Astral Gems", aliases = { "gems" },
        icon = "Interface\\Icons\\INV_Misc_Gem_Diamond_02",
        color = UI.Tinted({ 0.75, 0.55, 0.95 }),
        subtitle = "Socket Astral Gems into your gear.",
        rows = { { "AstralGems" } },
    },
    {
        id = "gem_fusion", label = "Gem Fusion",
        icon = "Interface\\Icons\\Spell_Arcane_Arcane01",
        color = UI.Tinted({ 0.68, 0.45, 0.92 }),
        subtitle = "Fuse Astral Gems up through the tiers.",
        rows = { { "GemFusion" } },
    },
    {
        id = "gem_stash", label = "Gem Stash",
        aliases = { "stash", "gem_catalog", "catalog", "GemCatalog" },   -- Gem Catalog was merged in
        icon = "Interface\\Icons\\INV_Misc_Bag_08",
        color = UI.Tinted({ 0.62, 0.55, 0.95 }),
        subtitle = "Your stash and every Astral Gem in the game.",
        rows = { { "GemStash" } },
    },
    {
        id = "disenchant", label = "Disenchant",
        icon = "Interface\\Icons\\INV_Enchant_DustIllusion",
        color = UI.Tinted({ 0.70, 0.50, 0.95 }),
        subtitle = "Pick bag items to disenchant at a glance and send them in one click.",
        rows = { { "astral_disenchant" } },
    },
    {
        id = "gembuilds", label = "Gem Builds",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        color = UI.Tinted({ 0.70, 0.60, 0.95 }),
        subtitle = "Save your gem loadouts and load them on any of your characters.",
        rows = { { "gem_builds" } },
    },
    {
        id = "talent_builds", label = "Talent Builds",
        aliases = { "talents_builds", "talentbuilds" },
        icon = "Interface\\Icons\\Ability_Marksmanship",
        color = UI.Tinted({ 0.62, 0.55, 0.95 }),
        subtitle = "Save class talent builds, load them in one click, and level up with one.",
        rows = { { "talent_builds" } },
    },
    {
        id = "set_builds", label = "Set Builds",
        aliases = { "sets", "equipment_sets" },
        icon = "Interface\\Icons\\INV_Chest_Plate16",
        color = UI.Tinted({ 0.62, 0.55, 0.95 }),
        subtitle = "Save the gear you wear as sets and swap between them in one click.",
        rows = { { "set_builds" } },
    },
    {
        id = "loadouts", label = "Loadouts",
        aliases = { "boss_loadouts", "loadout" },   -- Boss Loadouts became Loadouts
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        color = { 0.95, 0.58, 0.38 },
        subtitle = "Combine an equipment set, a gem build and a talent build, and load them all at once.",
        rows = { { "loadouts" } },
    },
    {
        id = "store", label = "Store",
        icon = "Interface\\Icons\\INV_Misc_Coin_02",
        color = { 1.00, 0.80, 0.35 },
        subtitle = "Spend Tokens, and claim store mounts, heirlooms and rewards.",
        rows = { { "prestige_store" } },
    },
    {
        id = "collections", label = "Collections",
        icon = "Interface\\Icons\\INV_Box_01",
        color = { 0.55, 0.82, 0.78 },
        subtitle = "Browse mounts, heirlooms, and special-event rewards.",
        rows = { { "collections" } },
    },
    {
        id = "raid", label = "Raid",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
        color = { 0.90, 0.45, 0.55 },
        subtitle = "Spend Tokens to wipe your raid and dungeon lockouts.",
        rows = { { "LockoutReset" } },
    },
    {
        id = "leaderboards", label = "Leaderboards", aliases = { "progress" },
        icon = "Interface\\Icons\\INV_BannerPVP_02",
        color = { 0.95, 0.65, 0.30 },
        subtitle = "Top players by tokens, prestiges, speedruns and raid times.",
        rows = { { "Leaderboard" } },
    },
    {
        id = "reagents", label = "Reagent Bank", aliases = { "utility" },
        icon = "Interface\\Icons\\INV_Misc_Bag_10",
        color = { 0.45, 0.85, 0.65 },
        subtitle = "Account-wide storage for your crafting reagents.",
        rows = { { "reagent_bank" } },
    },
    {
        id = "settings", label = "Settings",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        color = UI.Tinted({ 0.65, 0.60, 0.85 }),
        subtitle = "Scale, opacity, start tab, gain popups and more.",
        rows = { { "Settings" } },
    },
    {
        id = "world_map", label = "World Map Layer",
        navLabel = "World Map",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
        color = UI.Tinted({ 0.36, 0.78, 0.92 }),
        subtitle = "Save custom locations and show them as pins on the world map.",
        rows = { { "world_map" } },
    },
    {
        id = "new_player_guide", label = "New Player Guide",
        navLabel = "Player Guide",
        icon = "Interface\\Icons\\INV_Misc_Book_11",
        color = { 0.50, 0.82, 0.72 },
        subtitle = "How the realm's custom systems fit together and where to start.",
        rows = { { "new_player_guide" } },
    },
}
PA.HubTabs = TABS

local NAV_GROUPS = {
    { label = "PROGRESSION", ids = { "skills", "stats", "paragon" } },
    { label = "GEMS", ids = { "astral_gems", "gem_fusion", "gem_stash", "disenchant" } },
    { label = "BUILDS", ids = { "gembuilds", "talent_builds", "set_builds", "loadouts" } },
    { label = "ACTIVITIES", ids = { "store", "collections", "raid", "leaderboards", "reagents" } },
    { label = "TOOLS", ids = { "world_map", "new_player_guide", "settings" } },
}
PA.HubNavGroups = NAV_GROUPS   -- the micro menu button's dropdown (MinimapButton.lua)

local CARD_PAD    = 10
local CARD_HEAD   = 30
local CARD_W      = PANEL_W + CARD_PAD * 2
local COL_GAP     = 12
local ROW_GAP     = 12
local EDGE        = 0
local BAR_W       = 12
local SIDEBAR_W   = 190
local SIDEBAR_GAP = 8
local TABBAR_TOP  = 0
local VIEW_TOP    = 40
local VIEW_BOTTOM = 12
local SCROLL_TOP_PAD, SCROLL_BOTTOM_GAP = 6, 50
local CULL_MARGIN = 60
local WHEEL_STEP  = 90
local SOLID       = "Interface\\Buttons\\WHITE8X8"
local LOGO        = "Interface\\AddOns\\ProjectAstral\\astralhub"

-- unified Astral look (same as the gem and build tabs): navy surfaces, 1px navy
-- borders, gold for the active item. Fixed colours, not re-tinted by the theme.
local NV = {
    deep  = UI.Tinted({ 0.031, 0.047, 0.133, 0.97 }),
    panel = UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }),
    edge  = UI.Tinted({ 0.165, 0.204, 0.400, 1 }),
    hover = UI.Tinted({ 0.100, 0.140, 0.320, 0.95 }),
    gold  = { 0.886, 0.753, 0.384 },
    txtGold  = { 1.00, 0.85, 0.44 },
    txtMuted = UI.Tinted({ 0.86, 0.87, 0.94 }),
    txtDim   = UI.Tinted({ 0.667, 0.690, 0.831 }),
}

function NV.Navy(f, bg, edge)
    f.__paBackdrop = true   -- Theme.lua greys navy backdrops otherwise
    f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end
local MIN_W, MIN_H = 660, 420

function PA.HubTabFor(id)
    if not id then return nil end
    for _, t in ipairs(TABS) do
        if t.id == id then return t end
        for _, alias in ipairs(t.aliases or {}) do
            if alias == id then return t end
        end
        for _, row in ipairs(t.rows) do
            for _, name in ipairs(row) do
                if name == id then return t end
            end
        end
    end
end

local function Mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t,
             a[2] + (b[2] - a[2]) * t,
             a[3] + (b[3] - a[3]) * t }
end

local function Driver(parent)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(1, 1)
    d:SetPoint("TOPLEFT")
    return d
end

local function DockTreeSummary(panel)
    local sum = _G.AT_SummaryFrame
    if not sum or sum.__paDocked then return end
    sum.__paDocked = true

    local levels = {}
    local function collect(fr)
        levels[#levels + 1] = { fr, fr:GetFrameLevel() }
        for _, c in ipairs({ fr:GetChildren() }) do collect(c) end
    end
    collect(sum)

    sum:SetParent(panel)
    sum:ClearAllPoints()
    sum:SetPoint("TOPRIGHT",    panel, "TOPRIGHT",    -6, -6)
    sum:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 250)

    local delta = 40 - levels[1][2]
    for _, e in ipairs(levels) do e[1]:SetFrameLevel(e[2] + delta) end
end

-- MERGED: Enhanced cosmic starfield with animated nebulas
local function CreateCosmicStarfield(frame)
    local baseTex = frame:CreateTexture(nil, "BACKGROUND")
    baseTex:SetTexture(SOLID)
    baseTex:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)          -- keep the 1px navy edge
    baseTex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    local verticalNebula = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    verticalNebula:SetTexture(SOLID)
    verticalNebula:SetAllPoints()

    local horizontalNebula = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    horizontalNebula:SetTexture(SOLID)
    horizontalNebula:SetAllPoints()

    -- unified navy ground with a faint haze, both in the Global UI color's hue
    frame.RefreshCosmicColors = function()
        baseTex:SetVertexColor(UI.Tint(0.024, 0.035, 0.105, 1))
        local vr, vg, vb = UI.Tint(0.20, 0.30, 0.65)
        verticalNebula:SetGradientAlpha("VERTICAL", vr, vg, vb, 0.05, vr, vg, vb, 0.16)
        local hr, hg, hb = UI.Tint(0.25, 0.35, 0.70)
        horizontalNebula:SetGradientAlpha("HORIZONTAL", hr, hg, hb, 0.08, hr, hg, hb, 0)
    end
    frame.RefreshCosmicColors()

    return baseTex
end

local function CreateSuite()
    local f = UI.MakePanel(UIParent, 1200, 720, {
        name     = "PAMainMenuFrame",
        movable  = true,
        strata   = "HIGH",
    })
    f:SetFrameLevel(1)
    NV.Navy(f, NV.deep, NV.edge)
    f:Hide()

    -- MERGED: Changed accent to cosmic purple
    local accent = { UI.Color.accent[1], UI.Color.accent[2], UI.Color.accent[3] }

    local anim = Driver(f)
    anim:Hide()
    local tracks = {}
    local function Animate(key, dur, step)
        tracks[key] = { t = 0, dur = dur, step = step }
        anim:Show()
    end
    anim:SetScript("OnUpdate", function(self, dt)
        local busy = false
        for key, tr in pairs(tracks) do
            tr.t = tr.t + dt
            local p = math.min(1, tr.t / tr.dur)
            local q = 1 - p
            tr.step(1 - q * q * q)
            if p >= 1 then tracks[key] = nil else busy = true end
        end
        if not busy then self:Hide() end
    end)

    -- MERGED: Using enhanced cosmic starfield
    CreateCosmicStarfield(f)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 42)
    UI.CosmicCloseButton(closeBtn)

    local fsBtn = CreateFrame("Button", nil, f)
    fsBtn:SetSize(closeBtn:GetWidth(), closeBtn:GetHeight())
    fsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    fsBtn:SetFrameLevel(closeBtn:GetFrameLevel())
    NV.Navy(fsBtn, NV.panel, NV.edge)
    local function FsIdle()
        fsBtn:SetBackdropColor(UI.Tint(0.055, 0.094, 0.220, 0.96))
        fsBtn:SetBackdropBorderColor(UI.Tint(0.184, 0.255, 0.440, 1))
    end
    FsIdle()

    local fsGlyph = {}
    local function GlyphBox(key, w, h, x, y)
        local set = {}
        local function line(pw, ph, px, py)
            local t = fsBtn:CreateTexture(nil, "OVERLAY")
            t:SetTexture(SOLID)
            t:SetVertexColor(1, 1, 1, 1)
            t:SetSize(pw, ph)
            t:SetPoint("CENTER", fsBtn, "CENTER", px, py)
            set[#set + 1] = t
        end
        local hw, hh = math.floor(w / 2), math.floor(h / 2)
        line(w, 2, x, y + hh)
        line(w, 1, x, y - hh)
        line(1, h, x - hw, y)
        line(1, h, x + hw, y)
        fsGlyph[key] = set
    end
    GlyphBox("max",   12, 10,  0,  0)
    GlyphBox("back",   9,  7,  2,  2)
    GlyphBox("front",  9,  7, -2, -2)

    local function PaintFsGlyph()
        local full = f._fullscreen
        for _, t in ipairs(fsGlyph.max) do if full then t:Hide() else t:Show() end end
        for _, key in ipairs({ "back", "front" }) do
            for _, t in ipairs(fsGlyph[key]) do if full then t:Show() else t:Hide() end end
        end
    end
    PaintFsGlyph()

    fsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(UI.Tint(0.100, 0.160, 0.320, 1))
        self:SetBackdropBorderColor(UI.Tint(0.44, 0.82, 1.00, 1))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(f._fullscreen and "Exit fullscreen" or "Fullscreen", 1, 1, 1)
        GameTooltip:Show()
    end)
    fsBtn:SetScript("OnLeave", function()
        FsIdle()
        GameTooltip:Hide()
    end)
    fsBtn:SetScript("OnClick", function() f:SetFullscreen(not f._fullscreen) end)

    -- wallet: compact chips in the top bar, right of the sidebar
    local WALLET_X = SIDEBAR_W + SIDEBAR_GAP + 2
    local walletBar = CreateFrame("Frame", nil, f)
    walletBar:SetPoint("TOPLEFT", f, "TOPLEFT", WALLET_X, -7)
    walletBar:SetHeight(26)
    walletBar:SetFrameLevel(f:GetFrameLevel() + 22)
    local walletChips = {}

    local function MakeCurrencyRow(label, iconPath, tint, index)
        local row = CreateFrame("Button", nil, walletBar)
        row:SetHeight(26)
        row.__paBackdrop = true   -- keep the navy (Theme.lua greys navy backdrops)
        row:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                          insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        row:SetBackdropColor(UI.Tint(0.063, 0.090, 0.227, 0.95))
        row:SetBackdropBorderColor(UI.Tint(0.173, 0.216, 0.408, 1))
        UI.MakeRowChrome(row, { accentColor = tint })

        local iconPanel = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        iconPanel:SetTexture(SOLID)
        iconPanel:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1)
        iconPanel:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
        iconPanel:SetWidth(28)
        iconPanel:SetVertexColor(tint[1], tint[2], tint[3], 0.18)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", iconPanel, "CENTER", 0, 0)
        icon:SetTexture(iconPath)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local name = row:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(name, 11)
        name:SetText(label)
        name:SetTextColor(0.86, 0.87, 0.94)
        name:SetJustifyH("LEFT")

        local value = row:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(value, 12)
        value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        value:SetText("0")
        value:SetTextColor(tint[1], tint[2], tint[3])
        name:SetPoint("LEFT", iconPanel, "RIGHT", 7, 0)
        name:SetPoint("RIGHT", value, "LEFT", -4, 0)
        name:SetWordWrap(false)
        row.text = value
        walletChips[index] = row
        return row
    end

    -- chips share the space between the sidebar and the fullscreen/close buttons
    local function LayoutWallet()
        local avail = (f:GetWidth() or 0) - WALLET_X - 74
        local gap = 6
        local w = math.max(96, math.min(150, math.floor((avail - gap * 3) / 4)))
        for i, row in ipairs(walletChips) do
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", walletBar, "TOPLEFT", (i - 1) * (w + gap), 0)
            row:SetWidth(w)
        end
        walletBar:SetWidth(4 * w + 3 * gap)
    end
    f:HookScript("OnSizeChanged", LayoutWallet)

    local tokenChip = MakeCurrencyRow("Tokens", UI.Icon.tokens,
        { 0.35, 0.90, 0.70 }, 1)
    f.tokenChip = tokenChip

    local orbChip = MakeCurrencyRow("Orbs", UI.Icon.orbs,
        { 0.55, 0.85, 1.00 }, 2)
    f.orbChip = orbChip

    local prestigeChip = MakeCurrencyRow("Prestiges", UI.Icon.prestige,
        { 1.00, 0.85, 0.35 }, 3)
    f.prestigeChip = prestigeChip

    local lockoutChip = MakeCurrencyRow("Lockouts", UI.Icon.lockouts,
        { 1.00, 0.48, 0.40 }, 4)
    f.lockoutChip = lockoutChip
    LayoutWallet()

    if UI.AnimatedNumber then
        f._tokenTween = UI.AnimatedNumber(tokenChip.text)
        f._orbTween = UI.AnimatedNumber(orbChip.text)
        f._prestigeTween = UI.AnimatedNumber(prestigeChip.text)
        f._lockoutTween = UI.AnimatedNumber(lockoutChip.text)
    end

    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  -TABBAR_TOP)
    tabBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 6)
    tabBar:SetWidth(SIDEBAR_W)
    tabBar:SetFrameLevel(f:GetFrameLevel() + 30)
    NV.Navy(tabBar, NV.panel, NV.edge)

    local navBrand = tabBar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(navBrand, 12)
    navBrand:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 10, -10)
    navBrand:SetText("PROJECT ASTRAL")
    navBrand:SetTextColor(unpack(NV.txtGold))

    local navScroll = CreateFrame("ScrollFrame", "PAHubNavigationScroll", tabBar,
                                  "UIPanelScrollFrameTemplate")
    navScroll:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 2, -30)
    navScroll:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -22, 4)
    navScroll:EnableMouseWheel(true)
    navScroll.scrollBarHideable = true   -- no scroll bar while every tab fits
    f.navScroll = navScroll

    local navContent = CreateFrame("Frame", nil, navScroll)
    navContent:SetSize(SIDEBAR_W - 30, 1)
    navScroll:SetScrollChild(navContent)
    f.navContent = navContent

    local baseline = UI.SolidFill(tabBar, UI.Nav.edge, "BACKGROUND")
    baseline:SetPoint("BOTTOMLEFT",  tabBar, "BOTTOMLEFT",  0, 0)
    baseline:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    baseline:SetHeight(1)

    local tabGlow = navContent:CreateTexture(nil, "BORDER")
    tabGlow:SetTexture(SOLID)
    tabGlow:SetBlendMode("ADD")
    tabGlow:SetWidth(2)
    tabGlow:SetAlpha(0.18)
    tabGlow:Hide()

    local tabLine = navContent:CreateTexture(nil, "OVERLAY")
    tabLine:SetTexture(SOLID)
    tabLine:SetWidth(2)
    tabLine:SetVertexColor(UI.Tint(0.65, 0.55, 0.95, 1))
    tabLine:Hide()

    local lineX, lineY, lineH = 0, 0, 0
    local function PlaceTabLine(x, y, h)
        lineX, lineY, lineH = x, y, h
        tabLine:ClearAllPoints()
        tabLine:SetPoint("TOPLEFT", navContent, "TOPLEFT", x, -y)
        tabLine:SetHeight(math.max(1, h))
        tabGlow:ClearAllPoints()
        tabGlow:SetPoint("TOPLEFT", navContent, "TOPLEFT", x, -y)
        tabGlow:SetHeight(math.max(1, h))
    end

    local PaintTabs
    local groupHeaders = {}
    local tabsById = {}
    local navEmpty = navContent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    navEmpty:SetPoint("TOPLEFT", navContent, "TOPLEFT", 8, -8)
    navEmpty:SetText("No matching sections")
    navEmpty:SetTextColor(unpack(UI.Nav.muted))
    navEmpty:Hide()
    f.tabButtons = {}
    for _, tab in ipairs(TABS) do tabsById[tab.id] = tab end
    for _, group in ipairs(NAV_GROUPS) do
        local heading = navContent:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(heading, 10)
        heading:SetText(group.label)
        heading:SetTextColor(unpack(NV.txtDim))
        groupHeaders[group.label] = heading
    end
    for _, t in ipairs(TABS) do
        local tab = t
        local b = CreateFrame("Button", nil, navContent)
        b:SetHeight(28)
        b:SetWidth(SIDEBAR_W - 36)
        b:SetFrameLevel(navContent:GetFrameLevel() + 1)
        b:SetBackdrop({
            bgFile = SOLID,
            tile = false,
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(0, 0, 0, 0)

        local iconLane = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        iconLane:SetTexture(SOLID)
        iconLane:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        iconLane:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        iconLane:SetWidth(30)
        iconLane:SetVertexColor(tab.color[1], tab.color[2], tab.color[3], 0)
        b.iconLane = iconLane

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(iconLane)
        icon:SetTexture(tab.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.icon = icon

        -- unified states: hover = navy wash, active = gold tint + 3px gold bar
        local hoverBg = b:CreateTexture(nil, "BACKGROUND")
        hoverBg:SetTexture(SOLID)
        hoverBg:SetAllPoints()
        hoverBg:SetVertexColor(NV.hover[1], NV.hover[2], NV.hover[3], 0.70)
        hoverBg:Hide()
        b.hoverBg = hoverBg
        local activeBg = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        activeBg:SetTexture(SOLID)
        activeBg:SetAllPoints()
        activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.16, 0.94, 0.82, 0.43, 0)
        activeBg:Hide()
        b.activeBg = activeBg
        local activeBar = b:CreateTexture(nil, "OVERLAY")
        activeBar:SetTexture(SOLID)
        activeBar:SetVertexColor(NV.gold[1], NV.gold[2], NV.gold[3], 1)
        activeBar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        activeBar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        activeBar:SetWidth(3)
        activeBar:Hide()
        b.activeBar = activeBar

        local label = b:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(label, 12)
        label:SetPoint("LEFT", iconLane, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", b, "RIGHT", -8, 0)
        label:SetText(tab.navLabel or tab.label)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        b.label = label

        local glowEdges = {}
        local function AddGlowBand(thickness, inset, alpha)
            local function MakeEdge(first, second, x1, y1, x2, y2, horizontal)
                local edge = b:CreateTexture(nil, "OVERLAY")
                edge:SetTexture(SOLID)
                edge:SetBlendMode("ADD")
                edge:SetPoint(first, b, first, x1, y1)
                edge:SetPoint(second, b, second, x2, y2)
                if horizontal then edge:SetHeight(thickness) else edge:SetWidth(thickness) end
                edge:SetVertexColor(tab.color[1], tab.color[2], tab.color[3], alpha)
                edge:Hide()
                glowEdges[#glowEdges + 1] = edge
            end
            MakeEdge("TOPLEFT", "TOPRIGHT", inset, -inset, -inset, -inset, true)
            MakeEdge("BOTTOMLEFT", "BOTTOMRIGHT", inset, inset, -inset, inset, true)
            MakeEdge("TOPLEFT", "BOTTOMLEFT", inset, -inset, inset, inset, false)
            MakeEdge("TOPRIGHT", "BOTTOMRIGHT", -inset, -inset, -inset, inset, false)
        end
        AddGlowBand(4, 0, 0.18)
        AddGlowBand(2, 1, 0.42)
        AddGlowBand(1, 2, 1.00)
        b.glowEdges = glowEdges

        local badge = b:CreateTexture(nil, "OVERLAY")
        badge:SetTexture(SOLID)
        badge:SetSize(6, 6)
        badge:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3, -5)
        badge:SetVertexColor(0.55, 0.90, 0.65, 1)
        badge:Hide()
        b.badge = badge

        b._labelW = label:GetStringWidth()

        b:SetScript("OnEnter", function(self)
            self.label:SetTextColor(1, 1, 1)
            if tab ~= f.activeTab then self.hoverBg:Show() end
            if tab.navLabel then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tab.label, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        b:SetScript("OnLeave", function()
            GameTooltip:Hide()
            PaintTabs()
        end)
        b:SetScript("OnClick", function() f:SelectTab(tab.id) end)
        f.tabButtons[tab.id] = b
    end

    function f:RefreshTabBadges() PaintTabs() end

    PaintTabs = function()
        for _, t in ipairs(TABS) do
            local b = f.tabButtons[t.id]
            if t.badge and t.badge() then b.badge:Show() else b.badge:Hide() end
            b:SetBackdropColor(0, 0, 0, 0)
            b:SetBackdropBorderColor(0, 0, 0, 0)
            b.iconLane:SetVertexColor(0, 0, 0, 0)
            b.label:SetShadowColor(0, 0, 0, 1)
            b.label:SetShadowOffset(1, -1)
            b.hoverBg:Hide()
            for _, edge in ipairs(b.glowEdges) do edge:Hide() end
            if t == f.activeTab then
                b.icon:SetDesaturated(false)
                b.icon:SetAlpha(1)
                b.label:SetTextColor(1, 1, 1)
                b.activeBg:Show()
                b.activeBar:Show()
            else
                b.icon:SetDesaturated(true)
                b.icon:SetAlpha(0.70)
                b.label:SetTextColor(unpack(NV.txtMuted))
                b.activeBg:Hide()
                b.activeBar:Hide()
            end
        end
    end

    local LayoutTabs
    local selecting = false
    local function MatchesNav(tab, query)
        if query == "" then return true end
        local text = ((tab.label or "") .. " " .. (tab.navLabel or "") .. " " ..
                  (tab.id or "")):lower()
        return text:find(query, 1, true) ~= nil
    end

    LayoutTabs = function()
        local query = ""
        local y = 4
        local matched = 0
        for _, tab in ipairs(TABS) do f.tabButtons[tab.id]:Hide() end
        for _, group in ipairs(NAV_GROUPS) do
            local visibleTabs = {}
            for _, id in ipairs(group.ids) do
                local tab = tabsById[id]
                if tab and MatchesNav(tab, query) then
                    visibleTabs[#visibleTabs + 1] = tab
                end
            end

            local heading = groupHeaders[group.label]
            if #visibleTabs > 0 then
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", navContent, "TOPLEFT", 8, -y)
                heading:Show()
                y = y + 15
                for _, tab in ipairs(visibleTabs) do
                    local button = f.tabButtons[tab.id]
                    button:ClearAllPoints()
                    button:SetPoint("TOPLEFT", navContent, "TOPLEFT", 2, -y)
                    button:SetWidth(math.max(100, navContent:GetWidth() - 8))
                    button:SetHeight(28)
                    button._y, button._h = y, 28
                    button:Show()
                    matched = matched + 1
                    y = y + 30
                end
                y = y + 5
            else
                heading:Hide()
            end
        end

        if query ~= "" and matched == 0 then
            navEmpty:Show()
            y = 24
        else
            navEmpty:Hide()
        end
        navContent:SetHeight(math.max(1, y))
        navScroll:UpdateScrollChildRect()
        local activeButton = f.activeTab and f.tabButtons[f.activeTab.id]
        if activeButton and activeButton:IsShown() and not selecting and not tracks.tab then
            PlaceTabLine(0, activeButton._y, activeButton._h)
        end
    end

    navScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, navContent:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll,
            self:GetVerticalScroll() - delta * 30)))
    end)

    local mainInset = CreateFrame("Frame", nil, f)
    mainInset:SetPoint("TOPLEFT", f, "TOPLEFT", SIDEBAR_W + SIDEBAR_GAP + 2, -VIEW_TOP)
    mainInset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(2 + BAR_W), VIEW_BOTTOM)
    mainInset:SetFrameLevel(f:GetFrameLevel() + 2)
    NV.Navy(mainInset, UI.Tinted({ 0.031, 0.047, 0.133, 0.55 }), NV.edge)

    local scrollFrame = CreateFrame("ScrollFrame", "PAMainMenuScroll", f)
    -- above mainInset: its 38% dark backdrop used to sit on top of every page and grey out the text
    scrollFrame:SetFrameLevel(mainInset:GetFrameLevel() + 1)
    scrollFrame:SetPoint("TOPLEFT",     mainInset, "TOPLEFT",     SCROLL_TOP_PAD, -SCROLL_TOP_PAD)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainInset, "BOTTOMRIGHT", -SCROLL_TOP_PAD, SCROLL_BOTTOM_GAP)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetBackdropColor(0, 0, 0, 0)
    f.scrollFrame = scrollFrame

    local page = CreateFrame("Frame", nil, scrollFrame)
    page:SetFrameLevel(scrollFrame:GetFrameLevel())
    page:SetSize(PANEL_W, 1)
    scrollFrame:SetScrollChild(page)
    f.page = page

        local homeView = CreateFrame("Frame", nil, mainInset)
        homeView:SetPoint("TOPLEFT", mainInset, "TOPLEFT", 6, -6)
        homeView:SetPoint("BOTTOMRIGHT", mainInset, "BOTTOMRIGHT", -6, 50)
        homeView:SetFrameLevel(mainInset:GetFrameLevel() + 3)
        homeView:Hide()

        local homeLogo = homeView:CreateTexture(nil, "ARTWORK")
        homeLogo:SetTexture(LOGO)
        homeLogo:SetSize(58, 58)
        homeLogo:SetPoint("TOPLEFT", homeView, "TOPLEFT", 28, -28)

        local homeTitle = homeView:CreateFontString(nil, "OVERLAY")
        homeTitle:SetFont("Fonts\\MORPHEUS.TTF", 24)
        homeTitle:SetPoint("LEFT", homeLogo, "RIGHT", 14, 8)
        homeTitle:SetText("Project Astral")
        homeTitle:SetTextColor(0.85, 0.80, 1.0)
        homeTitle:SetShadowColor(0.28, 0.20, 0.55, 0.8)
        homeTitle:SetShadowOffset(1, -1)

        local homeSubtitle = homeView:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(homeSubtitle, 12)
        homeSubtitle:SetPoint("TOPLEFT", homeTitle, "BOTTOMLEFT", 1, -4)
        homeSubtitle:SetText("Your hub for skills, gems, progression, and rewards.")
        homeSubtitle:SetTextColor(unpack(UI.Color.textAccent))

        local homeDivider = UI.SolidFill(homeView, UI.Nav.edge, "ARTWORK")
        homeDivider:SetPoint("TOPLEFT", homeView, "TOPLEFT", 24, -104)
        homeDivider:SetPoint("TOPRIGHT", homeView, "TOPRIGHT", -24, -104)
        homeDivider:SetHeight(1)

        local quickTitle = homeView:CreateFontString(nil, "OVERLAY")
        quickTitle:SetFont("Fonts\\MORPHEUS.TTF", 14)
        quickTitle:SetPoint("TOPLEFT", homeView, "TOPLEFT", 26, -124)
        quickTitle:SetText("Quick Access")
        quickTitle:SetTextColor(unpack(UI.Color.textTitle))

        local homeLinks = {}
        local QUICK_IDS = { "skills", "paragon", "astral_gems", "gem_fusion", "gem_stash", "gembuilds",
                            "collections", "raid", "reagents", "loadouts",
                            "world_map", "new_player_guide" }
        local quickTabs = {}
        for _, id in ipairs(QUICK_IDS) do
            local t = PA.HubTabFor(id)
            if t then quickTabs[#quickTabs + 1] = t end
        end
        for _, tab in ipairs(quickTabs) do
            local linkTab = tab
            local button = UI.MakeButton(homeView, linkTab.label, {
                w = 180, h = 38, variant = "secondary",
                onClick = function() f:SelectTab(linkTab.id) end,
            })
            local iconLane = button:CreateTexture(nil, "BACKGROUND", nil, 1)
            iconLane:SetTexture(SOLID)
            iconLane:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            iconLane:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
            iconLane:SetWidth(38)
            iconLane:SetVertexColor(linkTab.color[1], linkTab.color[2], linkTab.color[3], 0.24)
            button.iconLane = iconLane
            button.themeTab = linkTab

            local icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(iconLane)
            icon:SetTexture(linkTab.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            button.text:ClearAllPoints()
            button.text:SetPoint("LEFT", iconLane, "RIGHT", 8, 0)
            button.text:SetPoint("RIGHT", button, "RIGHT", -8, 0)
            button.text:SetJustifyH("LEFT")
            homeLinks[#homeLinks + 1] = button
        end

        local function LayoutHomeLinks()
            local buttonWidth = math.max(140, math.floor((homeView:GetWidth() - 60) / 2))
            for index, button in ipairs(homeLinks) do
                local column = (index - 1) % 2
                local row = math.floor((index - 1) / 2)
                button:SetWidth(buttonWidth)
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", homeView, "TOPLEFT",
                    24 + column * (buttonWidth + 12), -154 - row * 48)
            end
        end
        homeView:SetScript("OnSizeChanged", LayoutHomeLinks)
        LayoutHomeLinks()

        local rightFooter = CreateFrame("Frame", nil, mainInset)
        rightFooter:SetPoint("BOTTOMLEFT", mainInset, "BOTTOMLEFT", 6, 4)
        rightFooter:SetPoint("BOTTOMRIGHT", mainInset, "BOTTOMRIGHT", -6, 4)
        rightFooter:SetHeight(40)
        rightFooter:SetFrameLevel(mainInset:GetFrameLevel() + 4)

        local footerRule = UI.SolidFill(rightFooter, UI.Nav.edge, "ARTWORK")
        footerRule:SetPoint("TOPLEFT", rightFooter, "TOPLEFT", 8, 0)
        footerRule:SetPoint("TOPRIGHT", rightFooter, "TOPRIGHT", -8, 0)
        footerRule:SetHeight(1)
        footerRule:SetAlpha(0.75)

        local footerMessage = rightFooter:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(footerMessage, 11)
        footerMessage:SetPoint("TOPLEFT", rightFooter, "TOPLEFT", 12, -6)
        footerMessage:SetPoint("BOTTOMRIGHT", rightFooter, "BOTTOMRIGHT", -12, 0)
        footerMessage:SetJustifyH("CENTER")
        footerMessage:SetJustifyV("MIDDLE")
        footerMessage:SetWordWrap(true)
        footerMessage:SetText("A huge thank-you to Phrez for hosting this server and giving us a place to play <3")
        footerMessage:SetTextColor(unpack(NV.txtDim))

    local bar = CreateFrame("Slider", nil, f)
    bar:SetFrameLevel(scrollFrame:GetFrameLevel())
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    5, 0)
    bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 5, 0)
    local track = UI.SolidFill(bar, UI.Nav.edge, "BACKGROUND")
    track:SetAllPoints()
    track:SetAlpha(0.6)
    bar:SetThumbTexture(SOLID)
    local thumb = bar:GetThumbTexture()
    thumb:SetVertexColor(UI.Tint(0.30, 0.36, 0.62, 0.9))
    thumb:SetSize(6, 40)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnEnter", function() thumb:SetVertexColor(UI.Tint(0.44, 0.82, 1.00, 1)) end)
    bar:SetScript("OnLeave", function() thumb:SetVertexColor(UI.Tint(0.30, 0.36, 0.62, 0.9)) end)
    f.bar = bar

    f._scroll, f._target, f._range, f._viewH = 0, 0, 0, 400

    function f:ApplyScroll(v)
        self._scroll = v
        self.scrollFrame:SetVerticalScroll(v)
        self._syncingBar = true
        self.bar:SetValue(v)
        self._syncingBar = false
        self:UpdateVisibility()
    end

    local function clampScroll(v)
        return math.max(0, math.min(f._range or 0, v or 0))
    end

    local ticker = Driver(f)
    ticker:Hide()
    ticker:SetScript("OnUpdate", function(self, dt)
        local d = f._target - f._scroll
        if math.abs(d) < 0.5 then
            f:ApplyScroll(f._target)
            self:Hide()
        else
            f:ApplyScroll(f._scroll + d * math.min(1, dt * 12))
        end
    end)
    f.ticker = ticker

    function f:SetScrollInstant(v)
        v = clampScroll(v)
        self._target = v
        self.ticker:Hide()
        self:ApplyScroll(v)
    end

    function f:ScrollTo(v)
        self._target = clampScroll(v)
        self.ticker:Show()
    end

    function f:ScrollBy(delta)
        self._pinnedActive = nil
        self:ScrollTo((self._target or self._scroll) + delta)
    end

    scrollFrame:SetScript("OnMouseWheel", function(_, delta) f:ScrollBy(-delta * WHEEL_STEP) end)
    bar:SetScript("OnMouseWheel", function(_, delta) f:ScrollBy(-delta * WHEEL_STEP) end)
    bar:SetScript("OnValueChanged", function(_, v)
        if f._syncingBar then return end
        f._pinnedActive = nil
        f:SetScrollInstant(v)
    end)

    local deferred = Driver(f)
    deferred:Hide()
    deferred:SetScript("OnUpdate", function(self)
        self:Hide()
        f.scrollFrame:SetVerticalScroll(f._scroll)
    end)

    -- cards keep the unified navy + gold look whatever the theme colour
    local function PaintCard(s)
        s.card:SetBackdropColor(unpack(NV.panel))
        s.card:SetBackdropBorderColor(unpack(NV.edge))
        s.accentBar:SetVertexColor(NV.gold[1], NV.gold[2], NV.gold[3], 1)
        s.strip:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.12, 0.94, 0.82, 0.43, 0)
    end

    local function PaintAccent(c)
        accent = c
        for _, s in ipairs(f.visibleSections or {}) do PaintCard(s) end
    end

    function f:RefreshTheme()
        local c = UI.Color.accent
        accent = { c[1], c[2], c[3] }
        for _, tab in ipairs(TABS) do
            tab.color = { c[1], c[2], c[3] }
            local button = self.tabButtons[tab.id]
            if button then
                button.iconLane:SetVertexColor(c[1], c[2], c[3], 0)
                for _, edge in ipairs(button.glowEdges) do
                    local _, _, _, alpha = edge:GetVertexColor()
                    edge:SetVertexColor(c[1], c[2], c[3], alpha)
                end
            end
        end
        for _, button in ipairs(homeLinks) do
            local tab = button.themeTab
            button.iconLane:SetVertexColor(tab.color[1], tab.color[2], tab.color[3], 0.24)
        end
        self:SetBackdropColor(unpack(NV.deep))
        FsIdle()
        PaintTabs()
        if self.activeTab then PaintAccent(self.activeTab.color) else PaintAccent(accent) end
        if self.RefreshCosmicColors then self:RefreshCosmicColors() end
        if self.Relayout and self.sections then self:Relayout() end
    end

    local function MakeCard(mod)
        local card = CreateFrame("Frame", nil, page)
        card:SetFrameLevel(page:GetFrameLevel())
        card:Hide()
        NV.Navy(card, NV.panel, NV.edge)

        local strip = card:CreateTexture(nil, "BORDER")
        strip:SetTexture(SOLID)
        strip:SetPoint("TOPLEFT",  card, "TOPLEFT",  1, -1)
        strip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -1, -1)
        strip:SetHeight(CARD_HEAD - 8)

        local accentBar = card:CreateTexture(nil, "ARTWORK")
        accentBar:SetTexture(SOLID)
        accentBar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD - 2, -9)
        accentBar:SetSize(3, 15)

        local title = card:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(title, 14)
        title:SetPoint("LEFT", accentBar, "RIGHT", 8, 0)
        title:SetText(mod.label or mod.name)
        title:SetTextColor(1, 1, 1)
        title:SetShadowColor(0, 0, 0, 1)
        title:SetShadowOffset(1, -1)
        if title.SetWordWrap then title:SetWordWrap(false) end
        if title.SetMaxLines then title:SetMaxLines(1) end

        local sub = card:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(sub, 12)
        sub:SetPoint("LEFT",  title, "RIGHT", 10, -1)
        sub:SetPoint("RIGHT", card,  "RIGHT", -CARD_PAD, 0)
        sub:SetJustifyH("LEFT")
        local subText = (mod.opts and mod.opts.subtitle) or ""
        sub:SetText(subText ~= "" and ("|cffaab0d4" .. subText .. "|r") or "")
        sub:SetTextColor(unpack(NV.txtDim))
        if sub.SetWordWrap then sub:SetWordWrap(false) end

        local rule = UI.SolidFill(card, NV.edge, "ARTWORK")
        rule:SetPoint("TOPLEFT",  card, "TOPLEFT",  CARD_PAD, -(CARD_HEAD - 4))
        rule:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(CARD_HEAD - 4))
        rule:SetHeight(1)
        rule:SetAlpha(1)

        local panel = CreateFrame("Frame", nil, card)
        panel:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_HEAD)
        panel:SetSize(PANEL_W, PANEL_H)
        panel:Hide()

        return { name = mod.name, mod = mod, card = card, panel = panel,
             title = title, subtitle = sub,
                 strip = strip, accentBar = accentBar, built = false,
                 x = 0, y = 0, h = 0 }
    end

    local skinQueue = {}
    local skinDriver = Driver(f)
    skinDriver:Hide()
    skinDriver:SetScript("OnUpdate", function(self, dt)
        local pending = false
        for panel, t in pairs(skinQueue) do
            t = t - dt
            if t <= 0 then
                skinQueue[panel] = nil
                if panel:IsVisible() and UI.SkinTree then UI.SkinTree(panel) end
            else
                skinQueue[panel] = t
                pending = true
            end
        end
        if not pending then self:Hide() end
    end)
    local function SkinSoon(panel)
        if not UI.SkinTree then return end
        UI.SkinTree(panel)
        skinQueue[panel] = 1.5
        skinDriver:Show()
    end

    local function BuildSection(s)
        s.built = true
        local builder = PA._tabContent[s.name]
        s.panel.__paUnified = true   -- Theme.lua keeps the tab's unified navy
        local ok, err = pcall(builder, s.panel)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[ProjectAstral]|r "
                .. tostring(s.mod.label) .. " failed to build: " .. tostring(err))
        end
        if s.name == "astral_tree" then
            DockTreeSummary(s.panel)
            if _G.AT_ScrollFrame then _G.AT_ScrollFrame.__paNoSkin = true end
        end
        if UI.AnimatedShow then UI.AnimatedShow(s.panel) end
    end

    function f:BuildSections()
        self.sections, self.sectionsByName = {}, {}
        local assigned = {}
        for _, t in ipairs(TABS) do
            for _, row in ipairs(t.rows) do
                for _, name in ipairs(row) do assigned[name] = t end
            end
        end

        local extra = {}
        for _, mod in ipairs(PA.modules) do
                if mod.name ~= "mount_journal"
                    and PA._tabContent and PA._tabContent[mod.name] then
                local s = MakeCard(mod)
                s.tab = assigned[mod.name]
                if not s.tab then
                    s.tab = TABS[#TABS]
                    extra[#extra + 1] = mod.name
                end
                self.sections[#self.sections + 1] = s
                self.sectionsByName[mod.name] = s
            end
        end

        local last = TABS[#TABS]
        for i = 1, #extra, 2 do
            last.rows[#last.rows + 1] = { extra[i], extra[i + 1] }
        end
    end

    function f:UpdateVisibility()
        if not (self.visibleSections and self:IsShown()) then return end
        local top    = self._scroll or 0
        local bottom = top + self._viewH
        local active = self._pinnedActive
        for _, s in ipairs(self.visibleSections) do
            local visible = (s.y + s.h > top - CULL_MARGIN)
                        and (s.y < bottom + CULL_MARGIN)
            if visible then
                if not s.built then BuildSection(s) end
                if not s.panel:IsShown() then
                    s.panel:Show()
                    SkinSoon(s.panel)
                end
            elseif s.panel:IsShown() then
                s.panel:Hide()
            end
            if not active and s.y + s.h > top + 40 then active = s.name end
        end
        self._activeTabId = active
    end

    function f:Relayout()
        local tab = self.activeTab
        if not (self.sections and tab) then return end
        local scale   = self:GetScale() or 1
        local screenW = UIParent:GetWidth()  / scale
        local screenH = UIParent:GetHeight() / scale

        local winW, winH
        if self._fullscreen then
            winW, winH = screenW, screenH
        else
            local fitCols  = (screenW - 40 >= 2 * CARD_W + COL_GAP + EDGE * 2 + BAR_W) and 2 or 1
            local defaultW = fitCols * CARD_W + (fitCols - 1) * COL_GAP + EDGE * 2 + BAR_W
            local defaultH = math.min(920, screenH - 40)
            winW = math.max(MIN_W, math.min(screenW, self._reqW or defaultW))
            winH = math.max(MIN_H, math.min(screenH, self._reqH or defaultH))
        end
        winW, winH = math.floor(winW), math.floor(winH)
        self:SetSize(winW, winH)
        self._viewH = winH - VIEW_TOP - VIEW_BOTTOM
                 - SCROLL_TOP_PAD - SCROLL_BOTTOM_GAP
        LayoutTabs(winW - EDGE * 2)

        local viewW = winW - BAR_W - SIDEBAR_W - SIDEBAR_GAP - 8
        local cols  = (viewW >= 2 * CARD_W + COL_GAP) and 2 or 1
        local pageW = cols * CARD_W + (cols - 1) * COL_GAP
        local padX  = math.max(0, math.floor((viewW - pageW) / 2))

        local rows = {}
        for _, names in ipairs(tab.rows) do
            local row = {}
            for _, name in ipairs(names) do
                local s = self.sectionsByName[name]
                if s and s.tab == tab then row[#row + 1] = s end
            end
            if cols == 1 and not tab.fit then
                for _, s in ipairs(row) do rows[#rows + 1] = { s } end
            elseif #row > 0 then
                rows[#rows + 1] = row
            end
        end

        self.visibleSections = {}
        local y = 0
        for _, row in ipairs(rows) do
            local fixed, fills = (#row - 1) * COL_GAP, 0
            for _, s in ipairs(row) do
                if FILL[s.name] then
                    fills = fills + 1
                else
                    local size = PANEL_SIZE[s.name]
                    fixed = fixed + ((size and size.w) or PANEL_W) + CARD_PAD * 2
                end
            end
            local span  = (fills > 0) and viewW or pageW
            local fillW = (fills > 0) and ((span - fixed) / fills) or 0
            local rowW  = (fills > 0) and span or fixed
            local baseX = (fills > 0) and 0 or padX

            local rowScale = 1
            if tab.fit and fills == 0 then
                local sumPanelW, maxPanelH = 0, 0
                for _, s in ipairs(row) do
                    local size = PANEL_SIZE[s.name] or {}
                    local pw = size.w or PANEL_W
                    local ph = size.h or PANEL_H
                    if type(ph) == "function" then ph = ph(pw) end
                    sumPanelW = sumPanelW + pw
                    maxPanelH = math.max(maxPanelH, ph)
                end
                local chrome    = (#row - 1) * COL_GAP + CARD_PAD * 2 * #row
                local widthFit  = (viewW - chrome) / sumPanelW
                local heightFit = (self._viewH - CARD_HEAD - CARD_PAD) / maxPanelH
                rowScale = math.max(0.4, math.min(1, widthFit, heightFit))
                rowW  = math.floor(sumPanelW * rowScale + chrome)
                span, baseX = viewW, 0
            end

            local x, rowH = baseX + math.floor((span - rowW) / 2), 0
            for _, s in ipairs(row) do
                local size   = PANEL_SIZE[s.name] or {}
                local panelW = FILL[s.name] and (fillW - CARD_PAD * 2) or (size.w or PANEL_W)
                local panelH = size.h or PANEL_H
                if type(panelH) == "function" then panelH = panelH(panelW) end
                if FILL[s.name] and #rows == 1 then
                    panelH = math.max(panelH, self._viewH - CARD_HEAD - CARD_PAD)
                end
                local cardW = math.floor(panelW * rowScale + CARD_PAD * 2)
                local h     = math.floor(CARD_HEAD + panelH * rowScale + CARD_PAD)
                s.x, s.y, s.h = x, y, h
                s.card:ClearAllPoints()
                s.card:SetPoint("TOPLEFT", page, "TOPLEFT", x, -y)
                s.card:SetSize(cardW, h)
                local headerW = math.max(1, cardW - CARD_PAD * 2 - 8)
                local titleW = math.min(s.title:GetStringWidth(), headerW * 0.42)
                s.title:SetWidth(math.max(1, titleW))
                s.panel:SetScale(rowScale)
                s.panel:ClearAllPoints()
                s.panel:SetPoint("TOPLEFT", s.card, "TOPLEFT", CARD_PAD / rowScale, -CARD_HEAD / rowScale)
                s.panel:SetSize(panelW, panelH)
                PaintCard(s)
                self.visibleSections[#self.visibleSections + 1] = s
                x = x + cardW + COL_GAP
                rowH = math.max(rowH, h)
            end
            y = y + rowH + ROW_GAP
        end

        local contentH = math.max(1, y - ROW_GAP)
        page:SetSize(viewW, contentH)
        scrollFrame:UpdateScrollChildRect()

        self._range = math.max(0, contentH - self._viewH)
        self.bar:SetMinMaxValues(0, self._range)
        if self._range > 0 then
            thumb:SetHeight(math.max(28, self._viewH * self._viewH / contentH))
            self.bar:Show()
        else
            self.bar:Hide()
        end

        local ab = self.tabButtons[tab.id]
        if ab and not selecting and not tracks.tab then PlaceTabLine(0, ab._y, ab._h) end
        deferred:Show()
    end

    function f:SelectTab(id, instant)
        local tab = PA.HubTabFor(id) or TABS[1]
        if not self.sections then
            self.activeTab = tab
            return
        end
        local changed = tab ~= self.activeTab
        local fromX, fromY, fromH, fromC = lineX, lineY, lineH, accent
        self.activeTab = tab

        for _, s in ipairs(self.sections) do
            if s.tab ~= tab then
                if s.panel:IsShown() then s.panel:Hide() end
                s.card:Hide()
            else
                s.card:Show()
            end
        end

        if tab.id == "project_astral" then
            homeView:Show()
            scrollFrame:Hide()
            bar:Hide()
        else
            homeView:Hide()
            scrollFrame:Show()
        end
        self._pinnedActive = nil
        selecting = true
        self:Relayout()
        selecting = false
        self:SetScrollInstant(0)
        PaintTabs()

        local b = self.tabButtons[tab.id]
        local toC = tab.color
        local function step(p)
            PlaceTabLine(0, fromY + (b._y - fromY) * p, fromH + (b._h - fromH) * p)
            PaintAccent(Mix(fromC, toC, p))
        end
        if instant or not changed then
            tracks.tab, tracks.page = nil, nil
            step(1)
            page:SetAlpha(1)
        else
            Animate("tab", 0.25, step)
            page:SetAlpha(0)
            Animate("page", 0.22, function(p) page:SetAlpha(p) end)
        end
    end

    function f:JumpTo(name, instant)
        local s = self.sectionsByName and self.sectionsByName[name]
        if not s then return false end
        if s.tab ~= self.activeTab then
            self:SelectTab(s.tab.id, instant)
            instant = true
        end
        self._pinnedActive = name
        if instant then self:SetScrollInstant(s.y) else self:ScrollTo(s.y) end
        self._activeTabId = name
        deferred:Show()
        return true
    end

    function f:SwitchTab(id)
        if not self.sections then return end
        local instant = (self._openedAt == GetTime()) or not self:IsShown()
        for _, t in ipairs(TABS) do
            if t.id == id then
                self:SelectTab(id, instant)
                return
            end
        end
        self:JumpTo(id, instant)
    end

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 5)
    grip:SetFrameLevel(f:GetFrameLevel() + 30)
    local gripDots = {}
    for i = 0, 2 do
        for j = 0, 2 - i do
            local d = grip:CreateTexture(nil, "OVERLAY")
            d:SetTexture(SOLID)
            d:SetSize(2, 2)
            d:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - i * 4, 3 + j * 4)
            gripDots[#gripDots + 1] = d
        end
    end
    local function PaintGrip(hot)
        local c = hot and accent or UI.Color.accentSoft
        for _, d in ipairs(gripDots) do d:SetVertexColor(c[1], c[2], c[3], hot and 1 or 0.7) end
    end
    PaintGrip(false)

    local resizing
    grip:SetScript("OnEnter", function(self)
        PaintGrip(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Resize", 1, 1, 1)
        GameTooltip:AddLine("Drag to resize the window.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Shift + drag to scale everything.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        if not resizing then PaintGrip(false) end
        GameTooltip:Hide()
    end)

    local function SaveCenter()
        local s = f:GetScale()
        local cx, cy = f:GetCenter()
        if not cx then return end
        local x = cx - UIParent:GetWidth()  / (2 * s)
        local y = cy - UIParent:GetHeight() / (2 * s)
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
        if PA.SaveSetting then
            PA.SaveSetting("posX", x)
            PA.SaveSetting("posY", y)
        end
    end

    local function GripUpdate(_, dt)
        local r = resizing
        if not r then return end
        local cx, cy = GetCursorPosition()
        local es = UIParent:GetEffectiveScale()
        local dx, dy = (cx - r.x) / es, (r.y - cy) / es
        if r.shift then
            local ns = r.scale * (1 + dx / (r.w * r.scale))
            ns = math.floor(math.max(0.6, math.min(2.0, ns)) * 100 + 0.5) / 100
            if ns ~= f:GetScale() then
                f:SetScale(ns)
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r.left / ns, r.top / ns)
            end
        else
            f._reqW = r.w + dx / r.scale
            f._reqH = r.h + dy / r.scale
        end
        r.acc = r.acc + dt
        if r.acc >= 0.05 then
            r.acc = 0
            f:Relayout()
            f:SetScrollInstant(f._scroll or 0)
        end
    end

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or f._fullscreen then return end
        local s = f:GetScale()
        local left, top = f:GetLeft(), f:GetTop()
        if not left then return end
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        local cx, cy = GetCursorPosition()
        resizing = { x = cx, y = cy, w = f:GetWidth(), h = f:GetHeight(),
                     scale = s, left = left * s, top = top * s,
                     shift = IsShiftKeyDown(), acc = 0 }
        self:SetScript("OnUpdate", GripUpdate)
    end)

    grip:SetScript("OnMouseUp", function(self)
        local r = resizing
        if not r then return end
        resizing = nil
        self:SetScript("OnUpdate", nil)
        PaintGrip(MouseIsOver(self))
        f:Relayout()
        f:SetScrollInstant(f._scroll or 0)
        if r.shift then
            if PA.SaveSetting then PA.SaveSetting("scale", f:GetScale()) end
            if _G.PASettingScale then _G.PASettingScale:SetValue(f:GetScale()) end
        else
            f._reqW, f._reqH = f:GetWidth(), f:GetHeight()
            if PA.SaveSetting then
                PA.SaveSetting("winW", math.floor(f:GetWidth()))
                PA.SaveSetting("winH", math.floor(f:GetHeight()))
            end
        end
        SaveCenter()
    end)

    local function PaintWindowChrome()
        PaintFsGlyph()
        if f._fullscreen then grip:Hide() else grip:Show() end
    end

    function f:SetFullscreen(on)
        self._fullscreen = on and true or false
        if PA.SaveSetting then PA.SaveSetting("fullscreen", self._fullscreen) end
        self:ClearAllPoints()
        if self._fullscreen then
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        elseif PA.ApplyPosition then
            PA.ApplyPosition()
        else
            self:SetPoint("CENTER")
        end
        PaintWindowChrome()
        if self.sections and self:IsShown() then
            self:Relayout()
            self:SetScrollInstant(self._scroll or 0)
        end
    end

    local dragWatch = CreateFrame("Frame", nil, UIParent)
    dragWatch:Hide()
    local hiddenForDrag

    local function FinishDrag()
        if not f._dragging then return end
        f._dragging = nil
        dragWatch:Hide()
        f:StopMovingOrSizing()
        if hiddenForDrag then
            hiddenForDrag:Show()
            hiddenForDrag = nil
        end
        SaveCenter()
    end

    dragWatch:SetScript("OnUpdate", function()
        if not IsMouseButtonDown("LeftButton") then FinishDrag() end
    end)

    f:SetScript("OnDragStart", function(self)
        if self._fullscreen then return end
        local tree = _G.AT_ScrollFrame
        if tree and tree:IsVisible() then
            tree:Hide()
            hiddenForDrag = tree
        end
        self._dragging = true
        self:StartMoving()
        dragWatch:Show()
    end)
    f:SetScript("OnDragStop", FinishDrag)

    tinsert(UISpecialFrames, "PAMainMenuFrame")

    function f:RefreshChips()
        local tokens = PA.prestigeTokens or 0
        local orbs   = PA.orbs           or 0
        local prest  = PA.prestigeLevel  or 0
        local n = (PA.LockoutReset and #(PA.LockoutReset.lockouts or {})) or 0

        if self._tokenTween then
            local firstPaint = self._chipsPainted ~= true
            self._chipsPainted = true
            if firstPaint then
                self._tokenTween:SetInstant(tokens)
                self._orbTween:SetInstant(orbs)
                self._prestigeTween:SetInstant(prest)
                self._lockoutTween:SetInstant(n)
            else
                self._tokenTween:SetValue(tokens)
                self._orbTween:SetValue(orbs)
                self._prestigeTween:SetValue(prest)
                self._lockoutTween:SetValue(n)
            end
        else
            self.tokenChip.text:SetText(tostring(tokens))
            self.orbChip.text:SetText(tostring(orbs))
            self.prestigeChip.text:SetText(tostring(prest))
            self.lockoutChip.text:SetText(tostring(n))
        end
    end

    PA:OnTokensChanged(function() if f:IsShown() then f:RefreshChips() end end)

    f:HookScript("OnShow", function(self)
        self._openedAt = GetTime()

        local saved = PA.Settings or {}
        self._reqW, self._reqH = tonumber(saved.winW), tonumber(saved.winH)
        self._fullscreen = saved.fullscreen and true or false
        if self._fullscreen then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        PaintWindowChrome()

        if not self.sections then self:BuildSections() end

        local st = PA.Settings or {}
        local pick
        if st.rememberLastTab and st.lastTab then pick = st.lastTab else pick = st.defaultTab end
        self.activeTab = nil
        self:SelectTab((PA.HubTabFor(pick) or TABS[1]).id, true)

        self:RefreshChips()
    end)

    f:HookScript("OnHide", function(self)
        self.ticker:Hide()
        if self.activeTab and PA.SaveSetting then
            PA.SaveSetting("lastTab", self.activeTab.id)
        end
        for _, sec in ipairs(self.sections or {}) do
            if sec.panel:IsShown() then sec.panel:Hide() end
        end
    end)

    PA.mainFrame = f
end

function PA:RegisterTabContent(name, builderFn)
    PA._tabContent = PA._tabContent or {}
    PA._tabContent[name] = builderFn
end

local function WorldMapPinData()
    ProjectAstralWorldMapPins = ProjectAstralWorldMapPins or {}
    ProjectAstralWorldMapPins.locations = ProjectAstralWorldMapPins.locations or {}
    if ProjectAstralWorldMapPins.enabled == nil then
        ProjectAstralWorldMapPins.enabled = true
    end
    return ProjectAstralWorldMapPins
end

local mapToggleButton
local mapPinButtons = {}
local mapTicker = CreateFrame("Frame")
mapTicker:Hide()

local function PinIcon(name)
    local text = (name or ""):lower()
    if text:find("table", 1, true) then
        return "Interface\\Icons\\INV_Enchant_DustIllusion"
    elseif text:find("callboard", 1, true) then
        return "Interface\\Icons\\INV_Misc_Note_01"
    elseif text:find("vendor", 1, true) or text:find("shop", 1, true) then
        return "Interface\\Icons\\INV_Misc_Coin_02"
    end
    return "Interface\\Icons\\INV_Misc_Map_01"
end

local function HideMapPins()
    for _, button in ipairs(mapPinButtons) do button:Hide() end
end

local function RefreshWorldMapPins()
    if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapButton) then
        HideMapPins()
        return
    end

    local data = WorldMapPinData()
    if not data.enabled then
        HideMapPins()
        return
    end

    local mapId = GetCurrentMapAreaID and GetCurrentMapAreaID()
    local width, height = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    if not mapId or mapId == 0 or width <= 0 or height <= 0 then
        HideMapPins()
        return
    end

    for index, location in ipairs(data.locations) do
        local button = mapPinButtons[index]
        if not button then
            button = CreateFrame("Button", nil, WorldMapButton)
            button:SetSize(28, 28)
            button:SetFrameLevel(WorldMapButton:GetFrameLevel() + 10)
            button:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            button:SetBackdropColor(UI.Tint(0.03, 0.05, 0.08, 0.96))
            button:SetBackdropBorderColor(UI.Tint(0.35, 0.78, 0.92, 1))

            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
            button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            button:SetScript("OnEnter", function(self)
                if not self.location then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.location.name, 1, 1, 1)
                GameTooltip:AddLine(self.location.mapName or "Unknown zone", 0.65, 0.85, 0.92)
                GameTooltip:AddLine(string.format("%.1f, %.1f", self.location.x * 100,
                                                   self.location.y * 100),
                                    0.75, 0.75, 0.75)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            button:SetScript("OnClick", function(self)
                if not self.location then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.location.name, 1, 1, 1)
                GameTooltip:AddLine(self.location.mapName or "Unknown zone", 0.65, 0.85, 0.92)
                GameTooltip:Show()
            end)
            mapPinButtons[index] = button
        end

        button.location = location
        button.icon:SetTexture(PinIcon(location.name))
        button:ClearAllPoints()
        if tonumber(location.mapId) == mapId and tonumber(location.x) and tonumber(location.y)
            and location.x >= 0 and location.x <= 1 and location.y >= 0 and location.y <= 1 then
            button:SetPoint("CENTER", WorldMapButton, "TOPLEFT",
                location.x * width, -location.y * height)
            button:Show()
        else
            button:Hide()
        end
    end

    for index = #data.locations + 1, #mapPinButtons do
        mapPinButtons[index]:Hide()
    end
end

local function EnsureWorldMapLayer()
    if mapToggleButton or not (WorldMapFrame and WorldMapButton) then return end

    mapToggleButton = UI.MakeButton(WorldMapFrame, "Astral Pins: On", {
        w = 124, h = 28, variant = "secondary",
    })
    mapToggleButton:SetPoint("TOPRIGHT", WorldMapFrame, "TOPRIGHT", -72, -28)
    mapToggleButton:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 20)
    mapToggleButton:SetScript("OnClick", function(self)
        local data = WorldMapPinData()
        data.enabled = not data.enabled
        self:SetLabel(data.enabled and "Astral Pins: On" or "Astral Pins: Off")
        RefreshWorldMapPins()
    end)

    WorldMapFrame:HookScript("OnShow", function()
        mapToggleButton:SetLabel(WorldMapPinData().enabled
            and "Astral Pins: On" or "Astral Pins: Off")
        mapTicker:Show()
        RefreshWorldMapPins()
    end)
    WorldMapFrame:HookScript("OnHide", function()
        mapTicker:Hide()
        HideMapPins()
    end)
    WorldMapButton:HookScript("OnSizeChanged", RefreshWorldMapPins)
    if WorldMapFrame:IsShown() then
        mapToggleButton:SetLabel(WorldMapPinData().enabled
            and "Astral Pins: On" or "Astral Pins: Off")
        mapTicker:Show()
        RefreshWorldMapPins()
    end
end

mapTicker:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    RefreshWorldMapPins()
end)

local mapInit = CreateFrame("Frame")
mapInit:RegisterEvent("PLAYER_LOGIN")
mapInit:SetScript("OnEvent", function()
    EnsureWorldMapLayer()
end)

local function BuildWorldMapLayer(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -8)
    title:SetText("Custom World Map Layer")
    title:SetTextColor(unpack(UI.Color.textTitle))

    local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    subtitle:SetWidth(510)
    subtitle:SetText("Stand at a custom location, name it, and save it as a zone pin.")
    subtitle:SetTextColor(unpack(UI.Nav.muted))

    local nameBox = UI.MakeSearchBox(panel, {
        width = 350, height = 34, placeholder = "Location name (Callboard, Astral Table...)",
    })
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -52)

    local saveButton = UI.MakeButton(panel, "Save Current Position", {
        w = 180, h = 34, variant = "gold",
    })
    saveButton:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    local layerButton = UI.MakeButton(panel, "Pins: On", {
        w = 120, h = 30, variant = "secondary",
    })
    layerButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -96)
    layerButton:SetScript("OnClick", function(self)
        local data = WorldMapPinData()
        data.enabled = not data.enabled
        self:SetLabel(data.enabled and "Pins: On" or "Pins: Off")
        if mapToggleButton then
            mapToggleButton:SetLabel(data.enabled and "Astral Pins: On" or "Astral Pins: Off")
        end
        RefreshWorldMapPins()
    end)

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("LEFT", layerButton, "RIGHT", 12, 0)
    status:SetWidth(360)
    status:SetJustifyH("LEFT")
    status:SetTextColor(unpack(UI.Nav.muted))
    status:SetText("Pins appear when you view their saved zone on the world map.")

    local listHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listHeader:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -140)
    listHeader:SetText("SAVED LOCATIONS")
    listHeader:SetTextColor(unpack(UI.Color.textAccent))

    local scroll = CreateFrame("ScrollFrame", "PAWorldMapPinsScroll", panel,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -166)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 2)
    scroll:EnableMouseWheel(true)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(500, 1)
    scroll:SetScrollChild(list)

    local empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -10)
    empty:SetText("No locations saved yet.")
    empty:SetTextColor(unpack(UI.Nav.muted))

    local rows = {}
    local function RefreshLocations()
        local locations = WorldMapPinData().locations
        if #locations == 0 then empty:Show() else empty:Hide() end
        for index, location in ipairs(locations) do
            local row = rows[index]
            if not row then
                row = CreateFrame("Frame", nil, list)
                row:SetHeight(44)
                UI.AstralBackdrop(row, { thin = true, bg = UI.Nav.panel,
                                         border = UI.Nav.edge })
                row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
                row.name:SetWidth(360)
                row.name:SetJustifyH("LEFT")
                row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.detail:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 5)
                row.detail:SetWidth(360)
                row.detail:SetJustifyH("LEFT")
                row.remove = UI.MakeButton(row, "Remove", {
                    w = 72, h = 26, variant = "danger",
                })
                row.remove:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                rows[index] = row
            end

            local locationIndex = index
            row.name:SetText(location.name or "Unnamed location")
            row.detail:SetText(string.format("%s  |  %.1f, %.1f",
                location.mapName or "Unknown zone", (location.x or 0) * 100,
                (location.y or 0) * 100))
            row.remove:SetScript("OnClick", function()
                table.remove(WorldMapPinData().locations, locationIndex)
                status:SetText("Location removed.")
                RefreshLocations()
                RefreshWorldMapPins()
            end)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((index - 1) * 48))
            row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -((index - 1) * 48))
            row:Show()
        end
        for index = #locations + 1, #rows do rows[index]:Hide() end
        list:SetHeight(math.max(1, #locations * 48))
        scroll:UpdateScrollChildRect()
    end

    saveButton:SetScript("OnClick", function()
        local name = BossTrim(nameBox:GetText())
        if name == "" then
            status:SetText("Enter a name before saving this location.")
            return
        end
        if not (SetMapToCurrentZone and GetCurrentMapAreaID and GetPlayerMapPosition) then
            status:SetText("This client cannot read player map coordinates.")
            return
        end

        local previousMap = GetCurrentMapAreaID() or 0
        SetMapToCurrentZone()
        local mapId = GetCurrentMapAreaID() or 0
        local x, y = GetPlayerMapPosition("player")
        local mapName = GetRealZoneText and GetRealZoneText() or GetZoneText()
        if previousMap > 0 and previousMap ~= mapId and SetMapByID then
            SetMapByID(previousMap)
        end
        if mapId == 0 or not x or not y or (x == 0 and y == 0) then
            status:SetText("Could not read your current zone position. Move outdoors and try again.")
            return
        end

        local locations = WorldMapPinData().locations
        locations[#locations + 1] = {
            id = tostring(time()) .. "-" .. tostring(math.floor(GetTime() * 1000)),
            name = name,
            mapId = mapId,
            mapName = mapName or "Unknown zone",
            x = x,
            y = y,
        }
        nameBox:Clear()
        status:SetText("Saved " .. name .. " in " .. (mapName or "this zone") .. ".")
        RefreshLocations()
        RefreshWorldMapPins()
    end)

    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, list:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll,
            self:GetVerticalScroll() - delta * 48)))
    end)
    panel:HookScript("OnShow", function()
        EnsureWorldMapLayer()
        local data = WorldMapPinData()
        layerButton:SetLabel(data.enabled and "Pins: On" or "Pins: Off")
        RefreshLocations()
    end)
    RefreshLocations()
end

local GUIDE_ENTRIES = {
    {
        title = "Start with the Astral Tree",
        body = "Unlock nodes with Tokens. Paths can require earlier nodes, and some nodes unlock other systems such as the Reagent Bank and gem features.",
    },
    {
        title = "Paragon",
        body = "Spend available Paragon points on permanent character bonuses. Check Astral Stats to see the bonuses contributed by your tree and Paragon choices.",
    },
    {
        title = "Astral Gems",
        body = "Socket gems into eligible gear. Socket colors and active slots depend on the item's quality; hover a socket for its requirements.",
    },
    {
        title = "Gem Stash",
        body = "Your account-wide storage for Astral Gems and related drops. Stash contents are shared across your characters.",
    },
    {
        title = "Gem Fusion",
        body = "Fuse three gems of the same family and tier into one gem of the next tier. Fusion costs gold and higher tiers may require tree unlocks.",
    },
    {
        title = "Gem Builds",
        body = "Save the gems currently socketed as a named, account-wide build. Loading a build uses gems from your stash and can fall back to owned lower tiers.",
    },
    {
        title = "Loadouts",
        body = "Combine an equipment set, a gem build and a talent build under one name, then load all three at once (also from the character window's Sets button).",
    },
    {
        title = "Astral Disenchant Table",
        body = "Place up to nine eligible green, blue, or purple weapons and armor in the table, then disenchant the batch. Crafted items are rejected. Rewards may be mailed if your bags fill; auto-deposit can send gem rewards to the stash.",
    },
    {
        title = "Reagent Bank",
        body = "Unlock the Reagent Bank node in the Astral Tree to store crafting reagents account-wide. Select a stack to withdraw, or use Deposit All; auto-deposit is configurable in Settings.",
    },
    {
        title = "Daily Callboard",
        body = "Browse available daily quests, accept or turn them in, and abandon quests you no longer want. Some refresh actions are only available at the Callboard.",
    },
    {
        title = "Raid Lockouts",
        body = "View active raid and dungeon lockouts. Reset All spends the displayed Token cost and resets every active lockout.",
    },
    {
        title = "Great Vault",
        body = "Complete activities, defeat bosses, prestige, and clear dungeons to unlock reward choices in the vault.",
    },
    {
        title = "Token Store and Collections",
        body = "Spend Tokens on available cosmetic, utility, and gameplay rewards. Collections helps you browse mounts, heirlooms, and event rewards.",
    },
    {
        title = "Leaderboards",
        body = "Browse top players across the server's tracked token, prestige, speedrun, and raid-time categories.",
    },
    {
        title = "Stats",
        body = "Your character, playtime and wallet, your account-wide gem stash and builds, and every bonus from the Astral Tree and Paragon in one place.",
    },
    {
        title = "World Map Layer",
        body = "Save custom locations from where you are standing. Pins appear on the matching zone map and can be toggled from the Blizzard World Map.",
    },
    {
        title = "Settings",
        body = "Adjust hub scale, opacity, text size, theme color, minimap button, popups, and automation options.",
    },
}

local function BuildNewPlayerGuide(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    title:SetText("New Player Guide")
    title:SetTextColor(unpack(UI.Color.textTitle))

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    intro:SetText("A quick tour of this realm's custom systems and how they work.")
    intro:SetTextColor(unpack(UI.Nav.muted))

    local scroll = CreateFrame("ScrollFrame", "PANewPlayerGuideScroll", panel,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -36)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 2)
    scroll:EnableMouseWheel(true)

    local list = CreateFrame("Frame", nil, scroll)
    list:SetSize(500, 1)
    scroll:SetScrollChild(list)

    local ROW_H = 92
    for index, entry in ipairs(GUIDE_ENTRIES) do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -((index - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", -4, -((index - 1) * ROW_H))

        local heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -7)
        heading:SetWidth(480)
        heading:SetJustifyH("LEFT")
        heading:SetText(entry.title)
        heading:SetTextColor(unpack(UI.Color.textAccent))

        local body = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
        body:SetWidth(480)
        body:SetHeight(56)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetWordWrap(true)
        body:SetText(entry.body)
        body:SetTextColor(unpack(UI.Color.textPrimary))

        local divider = UI.SolidFill(row, UI.Nav.edge, "ARTWORK")
        divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 0)
        divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 0)
        divider:SetHeight(1)
        divider:SetAlpha(0.55)
    end

    list:SetHeight(math.max(1, #GUIDE_ENTRIES * ROW_H))
    scroll:UpdateScrollChildRect()
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, list:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(maxScroll,
            self:GetVerticalScroll() - delta * ROW_H)))
    end)
end

PA:RegisterModule("world_map", "World Map Layer", function() end, {
    subtitle = "Save custom locations and show them as pins on the world map.",
})
PA:RegisterTabContent("world_map", BuildWorldMapLayer)
PA:RegisterModule("new_player_guide", "New Player Guide", function() end, {
    subtitle = "Learn the realm's custom systems and where to start.",
})
PA:RegisterTabContent("new_player_guide", BuildNewPlayerGuide)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() CreateSuite() end)
