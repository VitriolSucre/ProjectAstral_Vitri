local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

-- Mythic+ run HUD (server: lua_scripts/Server/astral_bridge/mythicplus/mythic_plus.lua).
-- The server sends the run state on every change and resyncs the timer every few
-- seconds; in between, the countdown and the timer run locally.

local STATE_GATHERING, STATE_COUNTDOWN, STATE_RUNNING = 0, 1, 2
local ICON_SIZE, ICON_STEP, ICONS_PER_ROW = 20, 22, 8
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Affix id (mythicraid_affixes) -> icon, also used by MythicPlusWarden.lua (loaded after this file).
-- The affix spells carry the same icons in Spell.dbc (world 2026_09_30_01).
PA.MythicPlusAffixIcons = {
    [1]  = "Interface\\Icons\\INV_Misc_Orb_05",                     -- Explosive Orb
    [2]  = "Interface\\Icons\\Ability_BackStab",                    -- Grievous
    [3]  = "Interface\\Icons\\Spell_Shadow_CorpseExplode",          -- Explosive Corpse
    [4]  = "Interface\\Icons\\Ability_Vehicle_ElectroCharge",       -- Electrified
    [5]  = "Interface\\Icons\\Spell_Holy_AshesToAshes",             -- Fortified
    [6]  = "Interface\\Icons\\Spell_Shadow_LifeDrain",              -- Blood Pool
    [7]  = "Interface\\Icons\\Spell_DeathKnight_IceBoundFortitude", -- Awaken
    [8]  = "Interface\\Icons\\INV_Stone_12",                        -- Shattered
    [9]  = "Interface\\Icons\\Spell_Fire_Immolation",               -- Molten Plague
    [10] = "Interface\\Icons\\Ability_Paladin_BlessedMending",      -- Shield Orb
}

local S = { data = nil, receivedAt = 0, tick = 0 }
local W = { icons = {} }

local function Clock(secs)
    secs = math.max(0, math.floor(secs))
    local h, m, s = math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end

local function Tint(fs, c)
    fs:SetTextColor(c[1], c[2], c[3])
end

local function Since()
    return GetTime() - S.receivedAt
end

local function UpdateClock()
    local d = S.data
    if not d then return end
    if d.state == STATE_COUNTDOWN then
        W.timer:SetText(tostring(math.max(0, math.ceil((d.countdown or 0) - Since()))))
    elseif d.state == STATE_RUNNING then
        W.timer:SetText(Clock((d.elapsed or 0) + Since()))
    end
end

local function Build()
    if W.frame then return end

    local f = CreateFrame("Frame", "ProjectAstralMythicPlusHUD", UIParent)
    f:SetSize(200, 78)
    f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -200, -210)
    f:SetFrameStrata("MEDIUM")
    UI.AstralBackdrop(f, { thin = true })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    W.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    W.title:SetPoint("TOPLEFT", 12, -11)
    Tint(W.title, UI.Color.textHi)

    W.timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    W.timer:SetPoint("TOPRIGHT", -12, -9)

    W.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.status:SetPoint("TOPLEFT", W.title, "BOTTOMLEFT", 0, -7)
    Tint(W.status, UI.Nav.muted)

    W.bosses = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.bosses:SetPoint("TOPLEFT", W.status, "BOTTOMLEFT", 0, -6)
    Tint(W.bosses, UI.Color.textPrimary)

    W.deaths = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.deaths:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -52)
    Tint(W.deaths, UI.Color.textPrimary)

    W.affixes = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.affixes:SetPoint("TOPLEFT", W.bosses, "BOTTOMLEFT", 0, -6)
    W.affixes:SetWidth(176)
    W.affixes:SetJustifyH("LEFT")
    Tint(W.affixes, UI.Color.textWarn)

    f:SetScript("OnUpdate", function(_, elapsed)
        S.tick = S.tick + elapsed
        if S.tick < 0.1 then return end
        S.tick = 0
        UpdateClock()
    end)

    W.frame = f
end

local function AffixTip(self)
    local a = self.affix
    if not a then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText(a.name or "", UI.Color.textHi[1], UI.Color.textHi[2], UI.Color.textHi[3])
    if a.description and a.description ~= "" then
        GameTooltip:AddLine(a.description, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

-- Icon i of the affix row (8 per row, wraps).
local function AffixIconFrame(i)
    local ic = W.icons[i]
    if ic then return ic end
    ic = UI.MakeIconFrame(W.frame, { size = ICON_SIZE })
    local row, col = math.floor((i - 1) / ICONS_PER_ROW), (i - 1) % ICONS_PER_ROW
    ic:SetPoint("TOPLEFT", W.bosses, "BOTTOMLEFT", col * ICON_STEP, -6 - row * ICON_STEP)
    ic:EnableMouse(true)
    ic:SetScript("OnEnter", AffixTip)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Dragging on an icon still moves the HUD.
    ic:RegisterForDrag("LeftButton")
    ic:SetScript("OnDragStart", function() W.frame:StartMoving() end)
    ic:SetScript("OnDragStop", function() W.frame:StopMovingOrSizing() end)
    W.icons[i] = ic
    return ic
end

local function RenderAffixes(d)
    for _, ic in ipairs(W.icons) do
        ic.affix = nil
        ic:Hide()
    end

    local list = d.affixList
    if type(list) == "table" and #list > 0 then
        W.affixes:SetText("")
        for i, a in ipairs(list) do
            local ic = AffixIconFrame(i)
            ic.affix = a
            ic:SetTexture(PA.MythicPlusAffixIcons[a.id] or UNKNOWN_ICON)
            ic:Show()
        end
        W.frame:SetHeight(84 + math.ceil(#list / ICONS_PER_ROW) * ICON_STEP)
        return
    end

    -- An older server sends the names as text only.
    local affixes = d.affixes or ""
    W.affixes:SetText(affixes)
    W.frame:SetHeight(affixes ~= "" and 84 + W.affixes:GetStringHeight() or 78)
end

local function Render()
    local d = S.data
    W.title:SetText(string.format("Mythic+ %d", d.level or 0))
    W.bosses:SetText(string.format("Bosses %d/%d", d.bosses or 0, d.bossesTotal or 0))
    W.deaths:SetText(string.format("Deaths %d", d.deaths or 0))
    Tint(W.timer, UI.Color.textTitle)
    RenderAffixes(d)

    if d.state == STATE_GATHERING then
        W.status:SetText("Waiting for your group...")
        W.timer:SetText("")
    elseif d.state == STATE_COUNTDOWN then
        W.status:SetText("Starting...")
        UpdateClock()
    elseif d.state == STATE_RUNNING then
        W.status:SetText("Defeat the final boss")
        UpdateClock()
    else
        W.status:SetText("Completed!")
        W.timer:SetText(Clock(d.elapsed or 0))
        Tint(W.timer, UI.Color.textGood)
    end
end

-- ---------------------------------------------------------------------
-- AIO handlers (server -> client)
-- ---------------------------------------------------------------------

local Client = AIO.AddHandlers("AstralMythicPlus", {})

Client.State = function(_, data)
    if type(data) ~= "table" then return end
    Build()
    S.data = data
    S.receivedAt = GetTime()
    Render()
    W.frame:Show()
end

Client.Hide = function()
    S.data = nil
    if W.frame then
        W.frame:Hide()
        for _, ic in ipairs(W.icons) do
            if GameTooltip:IsOwned(ic) then GameTooltip:Hide() end
        end
    end
end
