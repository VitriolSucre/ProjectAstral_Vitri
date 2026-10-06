
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local FRAME_W, FRAME_H  = 940, 820
local HEADER_H          = 62
local STATUS_H          = 68
local FOOTER_H          = 62
local SCROLLBAR_H       = 26
local HERO_CARD_W       = 300
local HERO_CARD_H       = 500
local HERO_CARD_GAP     = 16
local VARIANT_CARD_W    = 340
local VARIANT_CARD_H    = 490
local VARIANT_CARD_GAP  = 16
local WATCHDOG_TICK     = 0.4
local WATCHDOG_MOVE_SQR = 0.0002

local SMOOTH_SCROLL_DURATION = 0.18
local FRAME_FADEIN_DURATION  = 0.22
local CARD_STAGGER_STEP      = 0.04
local CARD_ENTRANCE_DURATION = 0.22
local BUTTON_HOVER_BRIGHTEN  = 0.18
local THUMB_HOVER_BRIGHTEN   = 0.20

local COL_TOKEN = { 1.00, 0.85, 0.28 }
local COL_ORB   = { 0.42, 0.75, 1.00 }
local COL_EXTRA = { 0.72, 0.42, 1.00 }

local function hex(c) return ("|cff%02x%02x%02x"):format(c[1]*255, c[2]*255, c[3]*255) end
local COL_TOKEN_TX  = hex(COL_TOKEN)
local COL_ORB_TX    = hex(COL_ORB)
local COL_EXTRA_TX  = hex(COL_EXTRA)
local COL_MUTED_TX  = hex(UI.Nav.muted)
local COL_GOOD_TX   = hex(UI.Color.textGood)
local COL_WARN_TX   = hex(UI.Color.textWarn)
local COL_BAD_TX    = hex(UI.Color.textBad)
local COL_ACCENT_TX = hex(UI.Color.accent)
local COL_TITLE_TX  = hex(UI.Color.textTitle)

local SHARED_RESTRICTIONS =
    "All challenges: gear cap = level+7 · Callboard off · RDF off · Heirlooms off · Grouping same-mode ±5 levels"

local CATEGORIES = {
    { key = "Hardcore",          kind = "classic", modeKey = "Hardcore",
      label = "Hardcore",
      tint  = { 1.00, 0.36, 0.36 },
      icon  = "Interface\\Icons\\Ability_FiegnDead",
      tagline = "One life. Death resets you.",
      rules = {
          "One life — death resets character to level 1",
          "No battle-res / ritual / in-combat res",
          "Character respawns in the starter zone",
      } },

    { key = "Nightmare",         kind = "classic", modeKey = "Nightmare",
      label = "Nightmare",
      tint  = { 0.72, 0.42, 1.00 },
      icon  = "Interface\\Icons\\Spell_Deathknight_Vendetta",
      tagline = "+500% damage taken.",
      rules = {
          "You take 500% additional damage",
          "Debuff persists until level cap reached",
          "Deaths allowed — no character reset",
      } },

    { key = "HardcoreNightmare", kind = "classic", modeKey = "HardcoreNightmare",
      label = "Hardcore Nightmare",
      tint  = { 1.00, 0.55, 0.15 },
      icon  = "Interface\\Icons\\Spell_Holy_HarmUndeadAura",
      tagline = "One life + 500% damage taken.",
      rules = {
          "You take 500% additional damage",
          "One life — death resets character to level 1",
          "No battle-res / ritual / in-combat res",
      } },

    { key = "MakeLove", kind = "family", familyKey = "MakeLove",
      label = "Make Love not Warcraft",
      subtitle = "Creator: Eric Theodore Cartman",
      tint  = { 1.00, 0.55, 0.75 },
      icon  = "Interface\\Icons\\Spell_BrokenHeart",
      tagline = "XP only from creature kills.",
      rules = {
          "Quests grant zero XP",
          "Exploration + battlegrounds grant zero XP",
      } },

    { key = "Taskman",  kind = "family", familyKey = "Taskman",
      label = "Taskman",
      subtitle = "Quest text reader's final boss.",
      tint  = { 0.90, 0.80, 0.35 },
      icon  = "Interface\\Icons\\Achievement_Quests_Completed_08",
      tagline = "XP only from quest turn-ins.",
      rules = {
          "Kills grant zero XP",
          "Exploration + battlegrounds grant zero XP",
      } },

    { key = "Ironman",  kind = "family", familyKey = "Ironman",
      label = "Ironman",
      subtitle = "Zero epics. Maximum regret.",
      tint  = { 0.70, 0.72, 0.78 },
      icon  = "Interface\\Icons\\INV_Misc_Bag_10_Black",
      tagline = "Only grey + white gear.",
      rules = {
          "Green+ gear cannot be equipped",
          "Green+ loot stripped from mobs & chests",
          "Higher-quality gear auto-unequipped on Accept",
      } },

    { key = "Greenman", kind = "family", familyKey = "Greenman",
      label = "Greenman",
      subtitle = "Ironman, but with a recycling budget.",
      tint  = { 0.45, 0.85, 0.45 },
      icon  = "Interface\\Icons\\INV_Misc_Bag_10_Green",
      tagline = "Only grey, white + green gear.",
      rules = {
          "Blue+ gear cannot be equipped",
          "Blue+ loot stripped from mobs & chests",
          "Higher-quality gear auto-unequipped on Accept",
      } },

    { key = "Pacifist", kind = "family", familyKey = "Pacifist",
      label = "Pacifist",
      subtitle = "Born to be a gardener & miner, forced to level.",
      tint  = { 0.60, 0.90, 0.90 },
      icon  = "Interface\\Icons\\Ability_Seal",
      tagline = "XP only from herbs + ores.",
      rules = {
          "Each herb/ore node grants 2% XP to next level",
          "Kills, quests, exploration grant zero XP",
          "Accept grants Mining Pick + Mining + Herbalism",
          "Solo only — grouping fully disabled",
      } },
}
local CATEGORY_BY_KEY = {}
for _, c in ipairs(CATEGORIES) do CATEGORY_BY_KEY[c.key] = c end

local MODIFIERS = {
    { key = "Normal",     label = "Normal",
      icon = "Interface\\Icons\\Achievement_Character_Human_Male",
      desc  = "Base mode only.",
      rules = { "No extra restrictions" } },
    { key = "Gemless",    label = "Gemless",
      icon = "Interface\\Icons\\INV_Misc_Gem_Lionseye_01",
      desc  = "Base mode + gems off.",
      rules = { "All Astral Gem procs disabled" } },
    { key = "Nodeless",   label = "Nodeless",
      icon = "Interface\\Icons\\Ability_Mage_TormentOfTheWeak",
      desc  = "Base mode + tree off.",
      rules = { "All AstralTree node effects disabled" } },
    { key = "Astralless", label = "Astralless",
      icon = "Interface\\Icons\\Spell_Shadow_ShadowFury",
      desc  = "Base mode + gems + tree off.",
      rules = {
          "All Astral Gem procs disabled",
          "All AstralTree node effects disabled",
      } },
}

local FAMILY_VARIANTS = {
    { key = "Normal",     mode = "None", modifier = "Normal",
      label   = "Normal",
      icon    = "Interface\\Icons\\Achievement_Character_Human_Male",
      tagline = "Family restriction only.",
      rules   = { "No extra restrictions" },
      tint    = { 0.75, 0.85, 1.00 } },

    { key = "Gemless",    mode = "None", modifier = "Gemless",
      label   = "Gemless",
      icon    = "Interface\\Icons\\INV_Misc_Gem_Lionseye_01",
      tagline = "Family + gems off.",
      rules   = { "All Astral Gem procs disabled" },
      tint    = { 0.65, 0.85, 0.55 } },

    { key = "Nodeless",   mode = "None", modifier = "Nodeless",
      label   = "Nodeless",
      icon    = "Interface\\Icons\\Ability_Mage_TormentOfTheWeak",
      tagline = "Family + tree off.",
      rules   = { "All AstralTree node effects disabled" },
      tint    = { 0.65, 0.60, 0.90 } },

    { key = "Astralless", mode = "None", modifier = "Astralless",
      label   = "Astralless",
      icon    = "Interface\\Icons\\Spell_Shadow_ShadowFury",
      tagline = "Family + gems + tree off.",
      rules   = {
          "All Astral Gem procs disabled",
          "All AstralTree node effects disabled",
      },
      tint    = { 0.55, 0.90, 0.85 } },

    { key = "Nightmare",  mode = "Nightmare", modifier = "Normal",
      label   = "Nightmare",
      icon    = "Interface\\Icons\\Spell_Deathknight_Vendetta",
      tagline = "Family + 500% damage taken.",
      rules   = {
          "You take 500% additional damage",
          "Deaths allowed — no character reset",
      },
      tint    = { 0.72, 0.42, 1.00 } },

    { key = "Hardcore",   mode = "Hardcore", modifier = "Normal",
      label   = "Hardcore",
      icon    = "Interface\\Icons\\Ability_FiegnDead",
      tagline = "Family + one life.",
      rules   = {
          "One life — death resets character to level 1",
          "No battle-res / ritual / in-combat res",
      },
      tint    = { 1.00, 0.36, 0.36 } },

    { key = "NightmareHardcore", mode = "HardcoreNightmare", modifier = "Normal",
      label   = "Nightmare + Hardcore",
      icon    = "Interface\\Icons\\Spell_Holy_HarmUndeadAura",
      tagline = "Family + one life + 500% damage.",
      rules   = {
          "You take 500% additional damage",
          "One life — death resets character to level 1",
      },
      tint    = { 1.00, 0.55, 0.15 } },

    { key = "NightmareHardcoreAstralless", mode = "HardcoreNightmare", modifier = "Astralless",
      label   = "The Full Nightmare",
      icon    = "Interface\\Icons\\Achievement_Boss_Lichking",
      tagline = "Everything on. Bragging rights only.",
      rules   = {
          "One life + 500% damage taken",
          "All Astral Gem procs disabled",
          "All AstralTree node effects disabled",
      },
      tint    = { 1.00, 0.30, 0.30 } },
}

local ApplyOffer
local ShowDetailFor        -- fn(categoryKey) — switches to page 2

-- Grouped into tables to stay under Lua 5.1's 60-upvalue-per-function limit.
local frame
local pagePicker, pageDetail
local pickerScroll  = {}   -- { frame, child, thumb }
local familyScroll  = {}
local classicScroll = {}
local statusBox     = {}   -- { level, cap, active } — the ".value" FontStrings
local abandonBtn, refreshBtn, closeBtn, backBtn, resetBtn
local detailHead    = {}   -- { iconHolder, icon, title, tagline }
local detailHero    = { titleGlow = {} }
                            -- { panel, tint, tintTop, iconHalo, titleGlow }
local categoryCards      = {}    -- picker cards keyed by category key
local modifierCardByKey  = {}    -- Classic detail cards keyed by "MODE_MODIFIER"
local variantCardByKey   = {}    -- Family detail cards keyed by "FAMILY_VARIANT"
local currentCategory    = nil   -- category key currently on the detail page
local lastOffer

local gate = CreateFrame("Frame")
gate:Hide()
gate.acc = 0
local function GateAnchor()
    SetMapToCurrentZone()
    gate.openX, gate.openY = GetPlayerMapPosition("player")
    gate.openMap = GetCurrentMapAreaID()
end
gate:SetScript("OnUpdate", function(self, elapsed)
    self.acc = self.acc + elapsed
    if self.acc < WATCHDOG_TICK then return end
    self.acc = 0
    if not frame or not frame:IsShown() then self:Hide(); return end
    SetMapToCurrentZone()
    if GetCurrentMapAreaID() ~= self.openMap then frame:Hide(); return end
    local x, y = GetPlayerMapPosition("player")
    if x == 0 and y == 0 then return end
    local dx, dy = x - self.openX, y - self.openY
    if (dx*dx + dy*dy) > WATCHDOG_MOVE_SQR then frame:Hide() end
end)
gate:RegisterEvent("PLAYER_ENTERING_WORLD")
gate:RegisterEvent("PLAYER_DEAD")
gate:RegisterEvent("TAXIMAP_OPENED")
gate:SetScript("OnEvent", function()
    if frame and frame:IsShown() then frame:Hide() end
end)

StaticPopupDialogs["ASTRAL_CHALLENGE_ACCEPT"] = {
    text = "%s",
    button1 = "Yes - Start Challenge",
    button2 = "Cancel",
    OnAccept = function(self, data)
        if not data then return end
        AIO.Handle("AstralChallengesServer", "Accept",
                   data.family or "Classic", data.mode, data.modifier)
    end,
    timeout = 0, whileDead = 0, hideOnEscape = 1, preferredIndex = 3,
}
StaticPopupDialogs["ASTRAL_CHALLENGE_ABANDON"] = {
    text = "Abandon your active challenge?\n" .. COL_BAD_TX .. "No reward will be granted.|r",
    button1 = "Yes - Abandon",
    button2 = "Cancel",
    OnAccept = function() AIO.Handle("AstralChallengesServer", "Abandon") end,
    timeout = 0, whileDead = 0, hideOnEscape = 1, preferredIndex = 3,
}
StaticPopupDialogs["ASTRAL_CHALLENGE_RESET_SELF"] = {
    text = "Reset your character back to level 1?\n"
        .. COL_BAD_TX .. "Talents and spells will be reset. You will be logged out.|r",
    button1 = "Yes - Reset",
    button2 = "Cancel",
    OnAccept = function() SendChatMessage(".challenge reset", "SAY") end,
    timeout = 0, whileDead = 0, hideOnEscape = 1, preferredIndex = 3,
}

local function MakeIconHolder(parent, size, iconPath)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    UI.AstralBackdrop(holder, {
        thin = true, bg = { 0.03, 0.05, 0.10, 1.0 }, border = UI.Nav.edgeMid,
    })
    UI.CosmicCorners(holder, math.max(10, math.floor(size * 0.28)))
    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(iconPath)
    tex:SetPoint("TOPLEFT",     holder, "TOPLEFT",     4, -4)
    tex:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -4,  4)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    holder.icon = tex
    return holder
end

local function SmoothScroll(sf, target, onStep)
    if not sf then return end
    if sf.__scrollTicker then sf.__scrollTicker:SetScript("OnUpdate", nil) end
    local start   = sf:GetHorizontalScroll() or 0
    local delta   = target - start
    if math.abs(delta) < 0.5 then
        sf:SetHorizontalScroll(target)
        if onStep then onStep() end
        return
    end
    local tick = sf.__scrollTicker or CreateFrame("Frame")
    sf.__scrollTicker = tick
    tick.acc = 0
    tick:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        local t = self.acc / SMOOTH_SCROLL_DURATION
        if t >= 1 then
            sf:SetHorizontalScroll(target)
            self:SetScript("OnUpdate", nil)
            if onStep then onStep() end
            return
        end
        sf:SetHorizontalScroll(start + delta * t)
        if onStep then onStep() end
    end)
end

local function FadeInFrame(frame, duration)
    if not frame then return end
    duration = duration or FRAME_FADEIN_DURATION
    frame:SetAlpha(0)
    local tick = frame.__fadeTicker or CreateFrame("Frame")
    frame.__fadeTicker = tick
    tick.acc = 0
    tick:SetScript("OnUpdate", function(self, elapsed)
        if not frame:IsShown() then self:SetScript("OnUpdate", nil); return end
        self.acc = self.acc + elapsed
        local t = self.acc / duration
        if t >= 1 then
            frame:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        frame:SetAlpha(t)
    end)
end

local function MakeSectionDivider(parent, tint, alpha)
    local d = parent:CreateTexture(nil, "ARTWORK")
    d:SetTexture("Interface\\Buttons\\WHITE8X8")
    d:SetHeight(1)
    local t = tint or UI.Nav.edge
    d:SetVertexColor(t[1], t[2], t[3], alpha or 0.35)
    local accent = parent:CreateTexture(nil, "OVERLAY")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetSize(2, 2)
    accent:SetPoint("CENTER", d, "CENTER", 0, 0)
    accent:SetVertexColor(t[1], t[2], t[3], math.min(0.85, (alpha or 0.35) * 1.6))
    return d
end

local function AddIconHalo(iconHolder, tint)
    if not iconHolder then return end
    local parent = iconHolder:GetParent()
    if not parent then return end
    local outer = parent:CreateTexture(nil, "BACKGROUND")
    outer:SetTexture("Interface\\Buttons\\WHITE8X8")
    outer:SetPoint("TOPLEFT",     iconHolder, "TOPLEFT",     -14,  14)
    outer:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT",  14, -14)
    outer:SetVertexColor(tint[1], tint[2], tint[3], 0.10)
    local mid = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    mid:SetTexture("Interface\\Buttons\\WHITE8X8")
    mid:SetPoint("TOPLEFT",     iconHolder, "TOPLEFT",     -7,  7)
    mid:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT",  7, -7)
    mid:SetVertexColor(tint[1], tint[2], tint[3], 0.22)
    return { outer = outer, mid = mid }
end

local function MakeCurrencyBadge(parent, tint, letter, size)
    size = size or 18
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(size, size)

    local bg = badge:CreateTexture(nil, "ARTWORK")
    bg:SetAllPoints(badge)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(tint[1] * 0.28, tint[2] * 0.28, tint[3] * 0.28, 0.95)

    local top = badge:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT",  badge, "TOPLEFT",  0, 0)
    top:SetPoint("TOPRIGHT", badge, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetTexture("Interface\\Buttons\\WHITE8X8")
    top:SetVertexColor(tint[1], tint[2], tint[3], 1.0)

    local bot = badge:CreateTexture(nil, "OVERLAY")
    bot:SetPoint("BOTTOMLEFT",  badge, "BOTTOMLEFT",  0, 0)
    bot:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", 0, 0)
    bot:SetHeight(1)
    bot:SetTexture("Interface\\Buttons\\WHITE8X8")
    bot:SetVertexColor(tint[1], tint[2], tint[3], 1.0)

    local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", badge, "CENTER", 0, 0)
    text:SetText(letter)
    text:SetTextColor(1, 1, 1, 1)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)

    return badge
end

local function MakeRewardRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)

    row.tokenBadge = MakeCurrencyBadge(row, COL_TOKEN, "T")
    row.tokenBadge:SetPoint("LEFT", row, "LEFT", 0, 0)

    row.tokenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.tokenText:SetPoint("LEFT", row.tokenBadge, "RIGHT", 6, 0)
    row.tokenText:SetTextColor(COL_TOKEN[1], COL_TOKEN[2], COL_TOKEN[3], 1)
    row.tokenText:SetShadowColor(0, 0, 0, 0.9)
    row.tokenText:SetShadowOffset(1, -1)
    row.tokenText:SetText("0")

    row.orbBadge = MakeCurrencyBadge(row, COL_ORB, "O")
    row.orbBadge:SetPoint("LEFT", row.tokenText, "RIGHT", 14, 0)

    row.orbText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.orbText:SetPoint("LEFT", row.orbBadge, "RIGHT", 6, 0)
    row.orbText:SetTextColor(COL_ORB[1], COL_ORB[2], COL_ORB[3], 1)
    row.orbText:SetShadowColor(0, 0, 0, 0.9)
    row.orbText:SetShadowOffset(1, -1)
    row.orbText:SetText("0")

    function row:Set(tokens, orbs)
        self.tokenText:SetText(tostring(tokens or 0))
        self.orbText:SetText(tostring(orbs or 0))
    end

    return row
end

local function MakeActivePill(parent, tint)
    local pill = CreateFrame("Frame", nil, parent)
    pill:SetSize(64, 18)
    UI.AstralBackdrop(pill, {
        thin = true, bg = { tint[1] * 0.25, tint[2] * 0.25, tint[3] * 0.25, 0.95 },
        border = tint,
    })
    UI.CosmicCorners(pill, 6)
    local text = pill:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", pill, "CENTER", 0, 0)
    text:SetText("ACTIVE")
    text:SetTextColor(tint[1], tint[2], tint[3], 1.0)
    text:SetShadowColor(0, 0, 0, 0.9)
    text:SetShadowOffset(1, -1)
    return pill
end

local function PulseAlpha(frame, minA, maxA, period)
    if not frame then return end
    if frame.__pulseTicker then frame.__pulseTicker:SetScript("OnUpdate", nil) end
    local tick = frame.__pulseTicker or CreateFrame("Frame")
    frame.__pulseTicker = tick
    tick.acc = 0
    tick:SetScript("OnUpdate", function(self, elapsed)
        self.acc = self.acc + elapsed
        local phase = (self.acc % period) / period          -- 0..1
        local wave  = 0.5 * (1 - math.cos(phase * 2 * math.pi)) -- 0..1 smooth
        frame:SetAlpha(minA + (maxA - minA) * wave)
    end)
end

local function AddStarfield(parent, count, seed, wOverride, hOverride)
    if not parent then return end
    count = count or 24
    local state = (seed or 137) * 1103515245 + 12345
    local function rand01()
        state = (state * 1103515245 + 12345) % 2147483648
        return state / 2147483648
    end
    local w = wOverride or parent:GetWidth()  or 900
    local h = hOverride or parent:GetHeight() or 800
    for i = 1, count do
        local star = parent:CreateTexture(nil, "BACKGROUND", nil, 3)
        star:SetTexture("Interface\\Buttons\\WHITE8X8")
        local size = (rand01() < 0.75) and 2 or 3
        star:SetSize(size, size)
        local coolTint = rand01() < 0.35
        local a = 0.20 + rand01() * 0.35
        if coolTint then
            star:SetVertexColor(0.55, 0.80, 1.0, a)
        else
            star:SetVertexColor(1, 1, 1, a * 0.75)
        end
        star:SetPoint("TOPLEFT", parent, "TOPLEFT",
            math.floor(rand01() * (w - 6)) + 3,
            -math.floor(rand01() * (h - 6)) - 3)
    end
end

local function StaggerCardsIn(cards)
    for i, card in ipairs(cards) do
        if card and card.__staggerTicker then
            card.__staggerTicker:SetScript("OnUpdate", nil)
        end
    end
    for i, card in ipairs(cards) do
        if card then
            card:SetAlpha(0)
            local tick = card.__staggerTicker or CreateFrame("Frame")
            card.__staggerTicker = tick
            tick.acc = 0
            local delayStart = (i - 1) * CARD_STAGGER_STEP
            local total      = delayStart + CARD_ENTRANCE_DURATION
            tick:SetScript("OnUpdate", function(self, elapsed)
                self.acc = self.acc + elapsed
                if self.acc < delayStart then return end
                local localT = (self.acc - delayStart) / CARD_ENTRANCE_DURATION
                if localT >= 1 then
                    card:SetAlpha(1)
                    self:SetScript("OnUpdate", nil)
                    return
                end
                card:SetAlpha(localT)
            end)
        end
    end
end

local function EnhanceButton(btn)
    if not btn or btn.__enhanced then return end
    btn.__enhanced = true

    local baseR, baseG, baseB, baseA
    btn:HookScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        local text = self:GetFontString()
        if text then
            if not baseR then baseR, baseG, baseB, baseA = text:GetTextColor() end
            text:SetTextColor(
                math.min(1, (baseR or 1) + BUTTON_HOVER_BRIGHTEN),
                math.min(1, (baseG or 1) + BUTTON_HOVER_BRIGHTEN),
                math.min(1, (baseB or 1) + BUTTON_HOVER_BRIGHTEN),
                baseA or 1)
        end
    end)
    btn:HookScript("OnLeave", function(self)
        local text = self:GetFontString()
        if text and baseR then
            text:SetTextColor(baseR, baseG, baseB, baseA or 1)
        end
    end)
    btn:HookScript("OnMouseDown", function(self)
        if not self:IsEnabled() then return end
        self:SetAlpha(0.75)
    end)
    btn:HookScript("OnMouseUp", function(self)
        self:SetAlpha(1.0)
    end)
end
local function MakeCosmicButton(parent, w, h, label, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(label)
    UI.CosmicButton(b)
    if onClick then b:SetScript("OnClick", onClick) end
    EnhanceButton(b)
    return b
end

local function MakeHorizontalScroller(parent, contentW, contentH, topOffset)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    sf:SetPoint("TOPLEFT",     parent, "TOPLEFT",     0, topOffset)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, SCROLLBAR_H)
    sf:EnableMouseWheel(true)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(contentW, contentH)
    sf:SetScrollChild(child)
    local track = CreateFrame("Frame", nil, parent)
    track:SetHeight(14)
    track:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  8, 4)
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 4)
    UI.AstralBackdrop(track, {
        thin = true, bg = { 0.02, 0.03, 0.06, 0.95 }, border = UI.Nav.edgeMid,
    })
    track:EnableMouse(true)

    local trackShade = track:CreateTexture(nil, "BORDER")
    trackShade:SetTexture("Interface\\Buttons\\WHITE8X8")
    trackShade:SetPoint("TOPLEFT",     track, "TOPLEFT",      2, -2)
    trackShade:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", -2,  2)
    trackShade:SetVertexColor(0.00, 0.01, 0.03, 0.55)

    local trackAccent = track:CreateTexture(nil, "ARTWORK")
    trackAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
    trackAccent:SetPoint("TOPLEFT",  track, "TOPLEFT",   4, -3)
    trackAccent:SetPoint("TOPRIGHT", track, "TOPRIGHT", -4, -3)
    trackAccent:SetHeight(1)
    trackAccent:SetVertexColor(UI.Color.accentSoft[1], UI.Color.accentSoft[2],
                               UI.Color.accentSoft[3], 0.30)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetHeight(10)
    thumb:EnableMouse(true)
    thumb:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    thumb:SetMovable(true)

    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetAllPoints(thumb)
    thumbTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    local baseR, baseG, baseB, baseA =
        UI.Color.accent[1], UI.Color.accent[2], UI.Color.accent[3], 0.92
    thumbTex:SetVertexColor(baseR, baseG, baseB, baseA)

    local thumbShine = thumb:CreateTexture(nil, "OVERLAY")
    thumbShine:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbShine:SetPoint("TOPLEFT",  thumb, "TOPLEFT",  0, 0)
    thumbShine:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", 0, 0)
    thumbShine:SetHeight(1)
    thumbShine:SetVertexColor(1, 1, 1, 0.80)

    local thumbUpper = thumb:CreateTexture(nil, "ARTWORK", nil, 1)
    thumbUpper:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbUpper:SetPoint("TOPLEFT",  thumb, "TOPLEFT",  0, -1)
    thumbUpper:SetPoint("TOPRIGHT", thumb, "TOPRIGHT", 0, -1)
    thumbUpper:SetHeight(3)
    thumbUpper:SetVertexColor(1, 1, 1, 0.20)

    local thumbShadow = thumb:CreateTexture(nil, "OVERLAY")
    thumbShadow:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumbShadow:SetPoint("BOTTOMLEFT",  thumb, "BOTTOMLEFT",  0, 0)
    thumbShadow:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
    thumbShadow:SetHeight(1)
    thumbShadow:SetVertexColor(0, 0, 0, 0.65)

    for _, dx in ipairs({ -3, 0, 3 }) do
        local grip = thumb:CreateTexture(nil, "OVERLAY", nil, 1)
        grip:SetTexture("Interface\\Buttons\\WHITE8X8")
        grip:SetSize(1, 4)
        grip:SetPoint("CENTER", thumb, "CENTER", dx, 0)
        grip:SetVertexColor(0, 0.05, 0.10, 0.75)
    end

    thumb:SetScript("OnEnter", function(self)
        thumbTex:SetVertexColor(
            math.min(1, baseR + THUMB_HOVER_BRIGHTEN),
            math.min(1, baseG + THUMB_HOVER_BRIGHTEN),
            math.min(1, baseB + THUMB_HOVER_BRIGHTEN),
            1.0)
        thumbShine:SetVertexColor(1, 1, 1, 1.0)
    end)
    thumb:SetScript("OnLeave", function(self)
        thumbTex:SetVertexColor(baseR, baseG, baseB, baseA)
        thumbShine:SetVertexColor(1, 1, 1, 0.80)
    end)

    local function GetGeometry()
        local trackW    = (track:GetWidth() or 0) - 4
        local visibleW  = sf:GetWidth() or 0
        local contentW2 = child:GetWidth() or 0
        local maxScroll = math.max(0, contentW2 - visibleW)
        local ratio     = contentW2 > 0 and math.min(1, visibleW / contentW2) or 1
        local thumbW    = math.max(28, math.floor(trackW * ratio))
        local travel    = math.max(0, trackW - thumbW)
        return trackW, maxScroll, thumbW, travel
    end

    local function UpdateThumbFromScroll()
        local trackW, maxScroll, thumbW, travel = GetGeometry()
        thumb:SetWidth(thumbW)
        local pos = sf:GetHorizontalScroll() or 0
        local thumbX = maxScroll > 0 and (travel * (pos / maxScroll)) or 0
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", 2 + thumbX, 0)
        if maxScroll <= 0 then track:Hide() else track:Show() end
    end

    local function ScrollTo(pos)
        local _, maxScroll = GetGeometry()
        if pos < 0        then pos = 0        end
        if pos > maxScroll then pos = maxScroll end
        sf:SetHorizontalScroll(pos)
        UpdateThumbFromScroll()
    end

    thumb:SetScript("OnMouseDown", function(self)
        self.__dragging = true
        self:SetScript("OnUpdate", function()
            local trackW, maxScroll, thumbW, travel = GetGeometry()
            local mouseX = GetCursorPosition() / self:GetEffectiveScale()
            local trackLeft = track:GetLeft() + 2
            local desiredThumbX = mouseX - trackLeft - (thumbW / 2)
            if desiredThumbX < 0      then desiredThumbX = 0      end
            if desiredThumbX > travel then desiredThumbX = travel end
            local newScroll = travel > 0 and (maxScroll * (desiredThumbX / travel)) or 0
            sf:SetHorizontalScroll(newScroll)
            thumb:ClearAllPoints()
            thumb:SetPoint("LEFT", track, "LEFT", 2 + desiredThumbX, 0)
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self.__dragging = false
        self:SetScript("OnUpdate", nil)
    end)

    track:SetScript("OnMouseDown", function(self)
        if thumb.__dragging then return end
        local _, maxScroll, thumbW, travel = GetGeometry()
        local mouseX = GetCursorPosition() / self:GetEffectiveScale()
        local trackLeft = track:GetLeft() + 2
        local desiredThumbX = mouseX - trackLeft - (thumbW / 2)
        if desiredThumbX < 0      then desiredThumbX = 0      end
        if desiredThumbX > travel then desiredThumbX = travel end
        local newScroll = travel > 0 and (maxScroll * (desiredThumbX / travel)) or 0
        SmoothScroll(sf, newScroll, UpdateThumbFromScroll)
    end)

    sf:SetScript("OnMouseWheel", function(self, delta)
        local _, maxScroll = GetGeometry()
        local step = math.max(60, math.floor((sf:GetWidth() or 300) / 3))
        local cur = self:GetHorizontalScroll() or 0
        local target = cur - delta * step
        if target < 0         then target = 0         end
        if target > maxScroll then target = maxScroll end
        SmoothScroll(self, target, UpdateThumbFromScroll)
    end)

    sf:SetScript("OnSizeChanged", UpdateThumbFromScroll)
    sf.__recalc = UpdateThumbFromScroll
    sf.__track = track

    sf:HookScript("OnShow", function() track:Show() end)
    sf:HookScript("OnHide", function() track:Hide() end)
    track:Hide()

    -- OnUpdate ticker (3.3.5 has no C_Timer.After).
    do
        local tick = CreateFrame("Frame")
        tick.acc = 0
        tick:SetScript("OnUpdate", function(self, elapsed)
            self.acc = self.acc + elapsed
            if self.acc >= 0.05 then
                self:SetScript("OnUpdate", nil)
                UpdateThumbFromScroll()
            end
        end)
    end

    return sf, child, thumb
end

local function MakeCategoryCard(parent, category)
    local card = CreateFrame("Frame", nil, parent)
    UI.AstralBackdrop(card, {
        thin = true, bg = UI.Nav.panel, border = UI.Nav.edge,
    })
    UI.CosmicCorners(card, 18)

    local strip = UI.SolidFill(card, category.tint, "ARTWORK")
    strip:SetPoint("TOPLEFT",  card, "TOPLEFT",  6,  -6)
    strip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
    strip:SetHeight(3)
    strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 0.85)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function()
        strip:SetHeight(5)
        strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 1.0)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(category.tint[1], category.tint[2], category.tint[3], 1.0)
        end
    end)
    card:SetScript("OnLeave", function()
        strip:SetHeight(3)
        strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 0.85)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(UI.Nav.edge[1], UI.Nav.edge[2],
                                        UI.Nav.edge[3], 1.0)
        end
    end)

    local icon = MakeIconHolder(card, 84, category.icon)
    icon:SetPoint("TOP", card, "TOP", 0, -22)
    AddIconHalo(icon, category.tint)

    for _, off in ipairs({ {-1,0}, {1,0}, {0,-1}, {0,1} }) do
        local glow = card:CreateFontString(nil, "ARTWORK")
        glow:SetFont("Fonts\\MORPHEUS.TTF", 20)
        glow:SetPoint("TOPLEFT",  card, "TOPLEFT",  10 + off[1], -114 + off[2])
        glow:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10 + off[1], -114 + off[2])
        glow:SetHeight(24)
        glow:SetJustifyH("CENTER")
        glow:SetText(category.label)
        glow:SetTextColor(category.tint[1], category.tint[2], category.tint[3], 0.35)
    end

    local name = card:CreateFontString(nil, "OVERLAY")
    name:SetFont("Fonts\\MORPHEUS.TTF", 20)
    name:SetPoint("TOPLEFT",  card, "TOPLEFT",  10, -114)
    name:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -114)
    name:SetHeight(24)
    name:SetJustifyH("CENTER")
    name:SetText(category.label)
    name:SetTextColor(category.tint[1], category.tint[2], category.tint[3])
    name:SetShadowColor(0.02, 0.04, 0.08, 0.9)
    name:SetShadowOffset(1, -1)

    if category.subtitle and category.subtitle ~= "" then
        local sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sub:SetPoint("TOPLEFT",  card, "TOPLEFT",  12, -142)
        sub:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -142)
        sub:SetHeight(30)
        sub:SetJustifyH("CENTER")
        sub:SetJustifyV("TOP")
        sub:SetSpacing(2)
        sub:SetText(category.subtitle)
        sub:SetTextColor(unpack(UI.Nav.muted))
    end

    local tagline = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -178)
    tagline:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -178)
    tagline:SetHeight(46)
    tagline:SetJustifyH("CENTER")
    tagline:SetJustifyV("TOP")
    tagline:SetSpacing(2)
    tagline:SetText(category.tagline)
    tagline:SetTextColor(unpack(UI.Color.textPrimary))

    local divPen = MakeSectionDivider(card, category.tint, 0.55)
    divPen:SetPoint("TOPLEFT",  card, "TOPLEFT",  16, -226)
    divPen:SetPoint("TOPRIGHT", card, "TOPRIGHT", -16, -226)

    local activePill = MakeActivePill(card, category.tint)
    activePill:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -8)
    activePill:Hide()
    PulseAlpha(activePill, 0.55, 1.0, 1.6)
    card.activePill = activePill

    local pHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pHdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -232)
    pHdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -232)
    pHdr:SetJustifyH("LEFT")
    pHdr:SetText(COL_BAD_TX .. "Challenge Rules|r")

    local ruleLines = {}
    for i, line in ipairs(category.rules or {}) do ruleLines[i] = "  - " .. line end
    local pList = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pList:SetPoint("TOPLEFT",     card, "TOPLEFT",     14, -250)
    pList:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 82)
    pList:SetJustifyH("LEFT")
    pList:SetJustifyV("TOP")
    pList:SetSpacing(2)
    pList:SetText(table.concat(ruleLines, "\n"))
    pList:SetTextColor(unpack(UI.Nav.muted))

    local cta = MakeCosmicButton(card, 240, 32, "Choose Variant  >")
    cta:SetPoint("BOTTOM", card, "BOTTOM", 0, 40)
    cta:SetScript("OnClick", function()
        if ShowDetailFor then ShowDetailFor(category.key) end
    end)
    card.cta = cta

    local footer = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    footer:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  14, 8)
    footer:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 8)
    footer:SetJustifyH("CENTER")
    footer:SetJustifyV("BOTTOM")
    footer:SetHeight(24)
    footer:SetText(SHARED_RESTRICTIONS)

    return card
end

local function MakeModifierCard(parent, mode, modifier, category)
    local card = CreateFrame("Frame", nil, parent)
    UI.AstralBackdrop(card, {
        thin = true, bg = UI.Nav.panel, border = UI.Nav.edge,
    })
    UI.CosmicCorners(card, 16)

    local strip = UI.SolidFill(card, category.tint, "ARTWORK")
    strip:SetPoint("TOPLEFT",  card, "TOPLEFT",  6, -6)
    strip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
    strip:SetHeight(4)
    strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 0.9)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function()
        strip:SetHeight(6)
        strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 1.0)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(category.tint[1], category.tint[2], category.tint[3], 1.0)
        end
    end)
    card:SetScript("OnLeave", function()
        strip:SetHeight(4)
        strip:SetVertexColor(category.tint[1], category.tint[2], category.tint[3], 0.9)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(UI.Nav.edge[1], UI.Nav.edge[2],
                                        UI.Nav.edge[3], 1.0)
        end
    end)

    local icon = MakeIconHolder(card, 40, modifier.icon)
    icon:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
    AddIconHalo(icon, category.tint)

    local title = card:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 15)
    title:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 18, -2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -14)
    title:SetHeight(42)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetSpacing(1)
    title:SetText(modifier.label)
    title:SetTextColor(category.tint[1], category.tint[2], category.tint[3])
    title:SetShadowColor(0.02, 0.04, 0.08, 0.9)
    title:SetShadowOffset(1, -1)

    local tagline = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -70)
    tagline:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -70)
    tagline:SetJustifyH("LEFT")
    tagline:SetJustifyV("TOP")
    tagline:SetHeight(34)
    tagline:SetSpacing(2)
    tagline:SetText(modifier.desc or "")
    tagline:SetTextColor(unpack(UI.Color.textPrimary))

    local penHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    penHdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -114)
    penHdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -114)
    penHdr:SetJustifyH("LEFT")
    penHdr:SetText(COL_BAD_TX .. "Challenge Rules|r")

    local penParts = {}
    if modifier.rules then
        for _, line in ipairs(modifier.rules) do
            table.insert(penParts, "  - " .. line)
        end
    end
    if category.rules and #category.rules > 0 then
        table.insert(penParts, "")
        table.insert(penParts, COL_MUTED_TX .. "Base " .. (category.label or "mode") .. " rules:|r")
        for _, line in ipairs(category.rules) do
            table.insert(penParts, "  - " .. line)
        end
    end
    local penText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    penText:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -132)
    penText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -132)
    penText:SetJustifyH("LEFT")
    penText:SetJustifyV("TOP")
    penText:SetHeight(180)
    penText:SetSpacing(2)
    penText:SetText(table.concat(penParts, "\n"))
    penText:SetTextColor(unpack(UI.Nav.muted))

    local divRew = MakeSectionDivider(card, category.tint, 0.45)
    divRew:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -318)
    divRew:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -318)

    local rewHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rewHdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -324)
    rewHdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -324)
    rewHdr:SetJustifyH("LEFT")
    rewHdr:SetText(COL_ACCENT_TX .. "Reward|r")

    local rewardRow = MakeRewardRow(card)
    rewardRow:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -344)
    rewardRow:SetWidth(VARIANT_CARD_W - 28)

    local extraIconHolder = CreateFrame("Frame", nil, card)
    extraIconHolder:SetSize(20, 20)
    extraIconHolder:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -378)
    UI.AstralBackdrop(extraIconHolder, {
        thin = true, bg = { 0.03, 0.05, 0.10, 1.0 }, border = UI.Nav.edge,
    })
    local extraIcon = extraIconHolder:CreateTexture(nil, "ARTWORK")
    extraIcon:SetPoint("TOPLEFT",     extraIconHolder, "TOPLEFT",     2, -2)
    extraIcon:SetPoint("BOTTOMRIGHT", extraIconHolder, "BOTTOMRIGHT", -2, 2)
    extraIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    extraIconHolder:Hide()

    local extraText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    extraText:SetPoint("LEFT",  extraIconHolder, "RIGHT", 6, 0)
    extraText:SetPoint("RIGHT", card,            "RIGHT", -14, 0)
    extraText:SetJustifyH("LEFT")
    extraText:SetText("")

    local endHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    endHint:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  14, 46)
    endHint:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 46)
    endHint:SetJustifyH("LEFT")
    endHint:SetText("")

    local acceptBtn = MakeCosmicButton(card, 0, 30, "Accept")
    acceptBtn:ClearAllPoints()
    acceptBtn:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  14, 12)
    acceptBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12)
    acceptBtn:SetScript("OnClick", function()
        local modRuleLine = (modifier.rules and modifier.rules[1]) or ""
        local dlg = StaticPopup_Show("ASTRAL_CHALLENGE_ACCEPT",
            ("Start " .. hex(category.tint) .. "%s %s|r?\n\n%s\n\n%s%s|r"):format(
                category.label, modifier.label, category.tagline, COL_BAD_TX, modRuleLine))
        if dlg then dlg.data = { family = "Classic", mode = mode, modifier = modifier.key } end
    end)

    return {
        root           = card,
        rewardRow      = rewardRow,
        extraIcon      = extraIcon,
        extraIconHolder= extraIconHolder,
        extraText      = extraText,
        endHint        = endHint,
        acceptBtn      = acceptBtn,
    }
end

local function MakeVariantCard(parent, category, variant)
    local card = CreateFrame("Frame", nil, parent)
    UI.AstralBackdrop(card, {
        thin = true, bg = UI.Nav.panel, border = UI.Nav.edge,
    })
    UI.CosmicCorners(card, 16)

    local strip = UI.SolidFill(card, variant.tint, "ARTWORK")
    strip:SetPoint("TOPLEFT",  card, "TOPLEFT",  6, -6)
    strip:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
    strip:SetHeight(4)
    strip:SetVertexColor(variant.tint[1], variant.tint[2], variant.tint[3], 0.9)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function()
        strip:SetHeight(6)
        strip:SetVertexColor(variant.tint[1], variant.tint[2], variant.tint[3], 1.0)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(variant.tint[1], variant.tint[2], variant.tint[3], 1.0)
        end
    end)
    card:SetScript("OnLeave", function()
        strip:SetHeight(4)
        strip:SetVertexColor(variant.tint[1], variant.tint[2], variant.tint[3], 0.9)
        if card.SetBackdropBorderColor then
            card:SetBackdropBorderColor(UI.Nav.edge[1], UI.Nav.edge[2],
                                        UI.Nav.edge[3], 1.0)
        end
    end)

    local icon = MakeIconHolder(card, 40, variant.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    icon:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -14)
    AddIconHalo(icon, variant.tint)

    local title = card:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\MORPHEUS.TTF", 15)
    title:SetPoint("TOPLEFT",  icon, "TOPRIGHT", 18, -2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -14)
    title:SetHeight(42)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetSpacing(1)
    title:SetText(variant.label)
    title:SetTextColor(variant.tint[1], variant.tint[2], variant.tint[3])
    title:SetShadowColor(0.02, 0.04, 0.08, 0.9)
    title:SetShadowOffset(1, -1)

    local tagline = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tagline:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -70)
    tagline:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -70)
    tagline:SetJustifyH("LEFT")
    tagline:SetJustifyV("TOP")
    tagline:SetHeight(34)
    tagline:SetSpacing(2)
    tagline:SetText(variant.tagline)
    tagline:SetTextColor(unpack(UI.Color.textPrimary))

    local penHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    penHdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -114)
    penHdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -114)
    penHdr:SetJustifyH("LEFT")
    penHdr:SetText(COL_BAD_TX .. "Challenge Rules|r")

    local ruleLines = {}
    if variant.rules then
        for _, line in ipairs(variant.rules) do
            ruleLines[#ruleLines + 1] = "  - " .. line
        end
    end
    local penText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    penText:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -132)
    penText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -132)
    penText:SetJustifyH("LEFT")
    penText:SetJustifyV("TOP")
    penText:SetHeight(180)
    penText:SetSpacing(2)
    penText:SetText(table.concat(ruleLines, "\n"))
    penText:SetTextColor(unpack(UI.Nav.muted))

    local divRew = MakeSectionDivider(card, variant.tint, 0.45)
    divRew:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -318)
    divRew:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -318)

    local rewHdr = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rewHdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  14, -324)
    rewHdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -324)
    rewHdr:SetJustifyH("LEFT")
    rewHdr:SetText(COL_ACCENT_TX .. "Reward|r")

    local rewardRow = MakeRewardRow(card)
    rewardRow:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -344)
    rewardRow:SetWidth(VARIANT_CARD_W - 28)

    local extraIconHolder = CreateFrame("Frame", nil, card)
    extraIconHolder:SetSize(20, 20)
    extraIconHolder:SetPoint("TOPLEFT", card, "TOPLEFT", 14, -378)
    UI.AstralBackdrop(extraIconHolder, {
        thin = true, bg = { 0.03, 0.05, 0.10, 1.0 }, border = UI.Nav.edge,
    })
    local extraIcon = extraIconHolder:CreateTexture(nil, "ARTWORK")
    extraIcon:SetPoint("TOPLEFT",     extraIconHolder, "TOPLEFT",     2, -2)
    extraIcon:SetPoint("BOTTOMRIGHT", extraIconHolder, "BOTTOMRIGHT", -2, 2)
    extraIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    extraIconHolder:Hide()

    local extraText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    extraText:SetPoint("LEFT",  extraIconHolder, "RIGHT", 6, 0)
    extraText:SetPoint("RIGHT", card,            "RIGHT", -14, 0)
    extraText:SetJustifyH("LEFT")
    extraText:SetText("")

    local endHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    endHint:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  14, 46)
    endHint:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 46)
    endHint:SetJustifyH("LEFT")
    endHint:SetText("")

    local acceptBtn = MakeCosmicButton(card, 0, 30, "Accept")
    acceptBtn:ClearAllPoints()
    acceptBtn:SetPoint("BOTTOMLEFT",  card, "BOTTOMLEFT",  14, 12)
    acceptBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 12)
    acceptBtn:SetScript("OnClick", function()
        local firstRule = (variant.rules and variant.rules[1]) or ""
        local dlg = StaticPopup_Show("ASTRAL_CHALLENGE_ACCEPT",
            ("Start " .. hex(category.tint) .. "%s|r " .. hex(variant.tint) .. "%s|r?\n\n%s\n\n%s%s|r"):format(
                category.label, variant.label, category.tagline, COL_BAD_TX, firstRule))
        if dlg then
            dlg.data = { family = category.familyKey, mode = variant.mode, modifier = variant.modifier }
        end
    end)

    return {
        root            = card,
        rewardRow       = rewardRow,
        extraIcon       = extraIcon,
        extraIconHolder = extraIconHolder,
        extraText       = extraText,
        endHint         = endHint,
        acceptBtn       = acceptBtn,
    }
end

function ShowDetailFor(categoryKey)
    currentCategory = categoryKey
    local cat = CATEGORY_BY_KEY[categoryKey]
    if not cat then return end

    detailHead.icon:SetTexture(cat.icon)
    detailHead.title:SetText(cat.label)
    detailHead.title:SetTextColor(cat.tint[1], cat.tint[2], cat.tint[3])
    detailHead.tagline:SetText(cat.tagline)
    for _, g in ipairs(detailHero.titleGlow) do
        g:SetText(cat.label)
        g:SetTextColor(cat.tint[1], cat.tint[2], cat.tint[3], 0.35)
    end

    if detailHero.tint then
        detailHero.tint:SetVertexColor(cat.tint[1], cat.tint[2], cat.tint[3], 0.12)
    end
    if detailHero.tintTop then
        detailHero.tintTop:SetVertexColor(cat.tint[1], cat.tint[2], cat.tint[3], 0.9)
    end
    if detailHero.iconHalo then
        if detailHero.iconHalo.outer then
            detailHero.iconHalo.outer:SetVertexColor(cat.tint[1], cat.tint[2], cat.tint[3], 0.10)
        end
        if detailHero.iconHalo.mid then
            detailHero.iconHalo.mid:SetVertexColor(cat.tint[1], cat.tint[2], cat.tint[3], 0.22)
        end
    end

    if cat.kind == "classic" then
        for key, card in pairs(modifierCardByKey) do
            local matches = key:sub(1, #cat.modeKey + 1) == (cat.modeKey .. "_")
            if matches then card.root:Show() else card.root:Hide() end
        end
        for _, card in pairs(variantCardByKey) do card.root:Hide() end
        if familyScroll.frame then
            familyScroll.frame:Hide()
            if familyScroll.frame.__track then familyScroll.frame.__track:Hide() end
        end
        if classicScroll.frame then
            classicScroll.frame:Show()
            if classicScroll.frame.__track then classicScroll.frame.__track:Show() end
            classicScroll.frame:SetHorizontalScroll(0)
            if classicScroll.frame.__recalc then classicScroll.frame.__recalc() end
        end
    else
        for _, card in pairs(modifierCardByKey) do card.root:Hide() end
        for key, card in pairs(variantCardByKey) do
            local matches = key:sub(1, #cat.familyKey + 1) == (cat.familyKey .. "_")
            if matches then card.root:Show() else card.root:Hide() end
        end
        if classicScroll.frame then
            classicScroll.frame:Hide()
            if classicScroll.frame.__track then classicScroll.frame.__track:Hide() end
        end
        if familyScroll.frame then
            familyScroll.frame:Show()
            if familyScroll.frame.__track then familyScroll.frame.__track:Show() end
            familyScroll.frame:SetHorizontalScroll(0)
            if familyScroll.frame.__recalc then familyScroll.frame.__recalc() end
        end
    end

    pagePicker:Hide()
    pageDetail:Show()

    if ApplyOffer then ApplyOffer(lastOffer) end

    local shown = {}
    if cat.kind == "classic" then
        for key, card in pairs(modifierCardByKey) do
            if key:sub(1, #cat.modeKey + 1) == (cat.modeKey .. "_") then
                shown[#shown + 1] = card.root
            end
        end
    else
        for key, card in pairs(variantCardByKey) do
            if key:sub(1, #cat.familyKey + 1) == (cat.familyKey .. "_") then
                shown[#shown + 1] = card.root
            end
        end
    end
    if StaggerCardsIn and #shown > 0 then StaggerCardsIn(shown) end
end

local function BuildFrame()
    if frame then return frame end
    if not UI then return end

    frame = UI.MakePanel(UIParent, FRAME_W, FRAME_H, {
        name    = "PA_ChallengesFrame",
        movable = true,
    })
    frame.__paUnified = true   -- unified look: Theme.lua keeps its navy
    if UI.FlatBackdrop then UI.FlatBackdrop(frame) end   -- no grey window border
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "PA_ChallengesFrame")

    AddStarfield(frame, 40, 271, FRAME_W, FRAME_H)

    UI.MakeHeader(frame,
        COL_ACCENT_TX .. "Astral Challenger|r",
        "Level 1 opt-in challenges - earn Tokens, Orbs of Destiny, and bonus rewards.")

    local tileW = math.floor((FRAME_W - 32 - 16) / 3)
    local sbLevel  = UI.MakeStatBox(frame, tileW, 60, "Character Level")
    local sbCap    = UI.MakeStatBox(frame, tileW, 60, "Reward Level Cap")
    local sbActive = UI.MakeStatBox(frame, tileW, 60, "Active Challenge")
    UI.CosmicCorners(sbLevel, 12); UI.CosmicCorners(sbCap, 12); UI.CosmicCorners(sbActive, 12)
    sbLevel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -HEADER_H - 8)
    sbCap:SetPoint("LEFT", sbLevel, "RIGHT", 8, 0)
    sbActive:SetPoint("LEFT", sbCap, "RIGHT", 8, 0)
    statusBox.level  = sbLevel.value
    statusBox.cap    = sbCap.value
    statusBox.active = sbActive.value

    local bodyTop    = -HEADER_H - STATUS_H - 6
    local bodyLeft   = 16
    local bodyRight  = -16
    local bodyBottom = FOOTER_H
    pagePicker = CreateFrame("Frame", nil, frame)
    pagePicker:SetPoint("TOPLEFT",     frame, "TOPLEFT",     bodyLeft,  bodyTop)
    pagePicker:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bodyRight, bodyBottom)

    local pickerLabel = pagePicker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pickerLabel:SetPoint("TOPLEFT", pagePicker, "TOPLEFT", 0, -4)
    pickerLabel:SetText(COL_TITLE_TX .. "Choose your challenge|r")

    local pickerSub = pagePicker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pickerSub:SetPoint("TOPLEFT", pickerLabel, "BOTTOMLEFT", 0, -2)
    pickerSub:SetText(COL_MUTED_TX .. "Scroll horizontally or drag the bar to see all categories. Click a card to choose a variant.|r")

    local totalHeroW = (#CATEGORIES * HERO_CARD_W) + ((#CATEGORIES - 1) * HERO_CARD_GAP)
    pickerScroll.frame, pickerScroll.child, pickerScroll.thumb =
        MakeHorizontalScroller(pagePicker, totalHeroW, HERO_CARD_H, -40)

    for i, cat in ipairs(CATEGORIES) do
        local card = MakeCategoryCard(pickerScroll.child, cat)
        card:SetSize(HERO_CARD_W, HERO_CARD_H)
        card:SetPoint("TOPLEFT", pickerScroll.child, "TOPLEFT",
            (i - 1) * (HERO_CARD_W + HERO_CARD_GAP), 0)
        categoryCards[cat.key] = card
    end
    pageDetail = CreateFrame("Frame", nil, frame)
    pageDetail:SetPoint("TOPLEFT",     frame, "TOPLEFT",     bodyLeft,  bodyTop)
    pageDetail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", bodyRight, bodyBottom)
    pageDetail:Hide()

    detailHero.panel = CreateFrame("Frame", nil, pageDetail)
    detailHero.panel:SetPoint("TOPLEFT",  pageDetail, "TOPLEFT",   0, 0)
    detailHero.panel:SetPoint("TOPRIGHT", pageDetail, "TOPRIGHT",  0, 0)
    detailHero.panel:SetHeight(60)
    UI.AstralBackdrop(detailHero.panel, {
        thin = true, bg = { 0.04, 0.06, 0.11, 0.85 }, border = UI.Nav.edge,
    })
    UI.CosmicCorners(detailHero.panel, 12)

    detailHero.tint = detailHero.panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    detailHero.tint:SetTexture("Interface\\Buttons\\WHITE8X8")
    detailHero.tint:SetPoint("TOPLEFT",     detailHero.panel, "TOPLEFT",     4, -4)
    detailHero.tint:SetPoint("BOTTOMRIGHT", detailHero.panel, "BOTTOMRIGHT", -4, 4)
    detailHero.tint:SetVertexColor(0.40, 0.75, 1.00, 0.10)

    detailHero.tintTop = detailHero.panel:CreateTexture(nil, "ARTWORK")
    detailHero.tintTop:SetTexture("Interface\\Buttons\\WHITE8X8")
    detailHero.tintTop:SetPoint("TOPLEFT",  detailHero.panel, "TOPLEFT",  6, -6)
    detailHero.tintTop:SetPoint("TOPRIGHT", detailHero.panel, "TOPRIGHT", -6, -6)
    detailHero.tintTop:SetHeight(3)
    detailHero.tintTop:SetVertexColor(0.40, 0.75, 1.00, 0.9)

    detailHead.iconHolder = MakeIconHolder(pageDetail, 48, CATEGORIES[1].icon)
    detailHead.iconHolder:SetPoint("TOPLEFT", pageDetail, "TOPLEFT", 8, -8)
    detailHead.icon = detailHead.iconHolder.icon

    detailHero.iconHalo = AddIconHalo(detailHead.iconHolder, { 0.40, 0.75, 1.00 })

    detailHero.titleGlow = {}
    for _, off in ipairs({ {-1,0}, {1,0}, {0,-1}, {0,1} }) do
        local g = pageDetail:CreateFontString(nil, "ARTWORK")
        g:SetFont("Fonts\\MORPHEUS.TTF", 22)
        g:SetPoint("TOPLEFT", detailHead.iconHolder, "TOPRIGHT", 14 + off[1], -2 + off[2])
        g:SetText("")
        table.insert(detailHero.titleGlow, g)
    end

    detailHead.title = pageDetail:CreateFontString(nil, "OVERLAY")
    detailHead.title:SetFont("Fonts\\MORPHEUS.TTF", 22)
    detailHead.title:SetPoint("TOPLEFT", detailHead.iconHolder, "TOPRIGHT", 14, -2)
    detailHead.title:SetText("")
    detailHead.title:SetShadowColor(0.02, 0.04, 0.08, 0.9)
    detailHead.title:SetShadowOffset(1, -1)

    detailHead.tagline = pageDetail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detailHead.tagline:SetPoint("TOPLEFT",  detailHead.title, "BOTTOMLEFT",  0, -2)
    detailHead.tagline:SetPoint("TOPRIGHT", pageDetail,        "TOPRIGHT",  -140, 0)
    detailHead.tagline:SetJustifyH("LEFT")
    detailHead.tagline:SetTextColor(unpack(UI.Nav.muted))
    detailHead.tagline:SetText("")

    backBtn = MakeCosmicButton(pageDetail, 130, 28, "< Back",
        function()
            currentCategory = nil
            pageDetail:Hide()
            pagePicker:Show()
        end)
    backBtn:SetPoint("TOPRIGHT", pageDetail, "TOPRIGHT", 0, -8)

    local detailBody = CreateFrame("Frame", nil, pageDetail)
    detailBody:SetPoint("TOPLEFT",     pageDetail, "TOPLEFT",     0, -62)
    detailBody:SetPoint("BOTTOMRIGHT", pageDetail, "BOTTOMRIGHT", 0, 0)

    local totalClassicW = (#MODIFIERS * VARIANT_CARD_W)
                        + ((#MODIFIERS - 1) * VARIANT_CARD_GAP)
    classicScroll.frame, classicScroll.child, classicScroll.thumb =
        MakeHorizontalScroller(detailBody, totalClassicW, VARIANT_CARD_H, 0)
    classicScroll.frame:Hide()

    for _, cat in ipairs(CATEGORIES) do
        if cat.kind == "classic" then
            for c, modifier in ipairs(MODIFIERS) do
                local card = MakeModifierCard(classicScroll.child, cat.modeKey, modifier, cat)
                card.root:SetSize(VARIANT_CARD_W, VARIANT_CARD_H)
                card.root:SetPoint("TOPLEFT", classicScroll.child, "TOPLEFT",
                    (c - 1) * (VARIANT_CARD_W + VARIANT_CARD_GAP), 0)
                card.root:Hide()
                modifierCardByKey[cat.modeKey .. "_" .. modifier.key] = card
            end
        end
    end

    local totalVarW = (#FAMILY_VARIANTS * VARIANT_CARD_W)
                    + ((#FAMILY_VARIANTS - 1) * VARIANT_CARD_GAP)

    familyScroll.frame, familyScroll.child, familyScroll.thumb =
        MakeHorizontalScroller(detailBody, totalVarW, VARIANT_CARD_H, 0)
    familyScroll.frame:Hide()  -- only shown on family detail

    for _, cat in ipairs(CATEGORIES) do
        if cat.kind == "family" then
            for i, variant in ipairs(FAMILY_VARIANTS) do
                local card = MakeVariantCard(familyScroll.child, cat, variant)
                card.root:SetSize(VARIANT_CARD_W, VARIANT_CARD_H)
                card.root:SetPoint("TOPLEFT", familyScroll.child, "TOPLEFT",
                    (i - 1) * (VARIANT_CARD_W + VARIANT_CARD_GAP), 0)
                card.root:Hide()
                variantCardByKey[cat.familyKey .. "_" .. variant.key] = card
            end
        end
    end

    refreshBtn = MakeCosmicButton(frame, 110, 30, "Refresh",
        function() AIO.Handle("AstralChallengesServer", "RefreshOffer") end)
    refreshBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)

    closeBtn = MakeCosmicButton(frame, 110, 30, "Close",
        function() frame:Hide() end)
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 18)

    abandonBtn = MakeCosmicButton(frame, 180, 30, "Abandon Challenge",
        function() StaticPopup_Show("ASTRAL_CHALLENGE_ABANDON") end)
    abandonBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    if abandonBtn.text then abandonBtn.text:SetTextColor(1.0, 0.45, 0.45) end
    abandonBtn:Hide()

    resetBtn = MakeCosmicButton(frame, 200, 30, "Reset to Level 1",
        function() StaticPopup_Show("ASTRAL_CHALLENGE_RESET_SELF") end)
    resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    if resetBtn.text then resetBtn.text:SetTextColor(1.0, 0.55, 0.20) end
    resetBtn:Hide()

    frame:HookScript("OnHide", function() gate:Hide() end)

    return frame
end

function ApplyOffer(offer)
    if not offer or not frame then return end
    lastOffer = offer

    local pl = UnitLevel("player") or 0
    local maxLevel = offer.maxLevel or 80
    statusBox.level:SetText(tostring(pl))
    statusBox.level:SetTextColor(unpack(pl == 1 and UI.Color.textGood or UI.Color.textBad))
    statusBox.cap:SetText(tostring(maxLevel))
    statusBox.cap:SetTextColor(unpack(UI.Color.textAccent))

    if statusBox.active then
        statusBox.active:SetHeight(30)
        statusBox.active:SetJustifyV("MIDDLE")
        statusBox.active:SetSpacing(1)
    end

    if offer.activeFamily or offer.activeMode then
        local famLabel = (offer.activeFamily and offer.activeFamily ~= "Classic")
            and offer.activeFamily or ""
        local modeLabel
        if     offer.activeMode == "HardcoreNightmare" then modeLabel = "HC+Nightmare"
        elseif offer.activeMode == "Hardcore"          then modeLabel = "Hardcore"
        elseif offer.activeMode == "Nightmare"         then modeLabel = "Nightmare"
        else                                                modeLabel = "" end
        local modLabel = (offer.activeMod and offer.activeMod ~= "Normal") and offer.activeMod or ""
        local parts = {}
        if famLabel  ~= "" then table.insert(parts, famLabel)  end
        if modeLabel ~= "" then table.insert(parts, modeLabel) end
        if modLabel  ~= "" then table.insert(parts, modLabel)  end
        statusBox.active:SetText(table.concat(parts, " "))
        statusBox.active:SetTextColor(1.00, 0.55, 0.15)
        abandonBtn:Show()
        if resetBtn then resetBtn:Hide() end
    else
        statusBox.active:SetText(offer.canAccept and "None" or "Not eligible")
        statusBox.active:SetTextColor(unpack(offer.canAccept and UI.Color.textGood or UI.Color.textBad))
        abandonBtn:Hide()
        if resetBtn then
            if offer.canReset then resetBtn:Show() else resetBtn:Hide() end
        end
    end

    local activeFam  = offer.activeFamily
    local activeMode = offer.activeMode
    for _, cat in ipairs(CATEGORIES) do
        local card = categoryCards[cat.key]
        if card and card.cta then card.cta:Enable() end
        if card and card.activePill then
            local isActive = false
            if cat.kind == "family" then
                isActive = (activeFam == cat.familyKey)
            elseif cat.kind == "classic" then
                isActive = (activeFam == nil or activeFam == "" or activeFam == "Classic")
                    and (activeMode == cat.modeKey)
            end
            if isActive then card.activePill:Show() else card.activePill:Hide() end
        end
    end

    local endHintText = ("Ends at level %d or on abortion of challenge"):format(maxLevel)

    for _, entry in ipairs(offer.challenges or {}) do
        local card = modifierCardByKey[entry.mode .. "_" .. entry.modifier]
        if card then
            local tokens = entry.tokens    or 0
            local orbs   = entry.orbs      or 0
            local extra  = entry.extraItem or 0
            card.rewardRow:Set(tokens, orbs)
            if extra > 0 then
                local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(extra)
                if itemName then
                    card.extraIcon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                    card.extraText:SetText(COL_EXTRA_TX .. itemName .. "|r")
                else
                    card.extraIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    card.extraText:SetText(COL_EXTRA_TX .. "Bonus reward|r " .. COL_MUTED_TX .. "(loading...)|r")
                end
                card.extraIconHolder:Show()
            else
                card.extraIconHolder:Hide()
                card.extraText:SetText("")
            end
            card.endHint:SetText(COL_MUTED_TX .. endHintText .. "|r")
            if offer.canAccept then card.acceptBtn:Enable() else card.acceptBtn:Disable() end
        end
    end

    for _, family in ipairs(offer.families or {}) do
        for _, entry in ipairs(family.variants or {}) do
            if family.name == "Classic" then
                local card = modifierCardByKey[entry.mode .. "_" .. entry.modifier]
                if card then
                    local tokens = entry.tokens    or 0
                    local orbs   = entry.orbs      or 0
                    local extra  = entry.extraItem or 0
                    card.rewardRow:Set(tokens, orbs)
                    if extra > 0 then
                        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(extra)
                        if itemName then
                            card.extraIcon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                            card.extraText:SetText(COL_EXTRA_TX .. itemName .. "|r")
                        else
                            card.extraIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                            card.extraText:SetText(COL_EXTRA_TX .. "Bonus reward|r " .. COL_MUTED_TX .. "(loading...)|r")
                        end
                        card.extraIconHolder:Show()
                    else
                        card.extraIconHolder:Hide()
                        card.extraText:SetText("")
                    end
                    card.endHint:SetText(COL_MUTED_TX .. endHintText .. "|r")
                    if offer.canAccept then card.acceptBtn:Enable() else card.acceptBtn:Disable() end
                end
            else
                local key = family.name .. "_" .. (entry.variantName or "")
                local card = variantCardByKey[key]
                if card then
                    local tokens = entry.tokens    or 0
                    local orbs   = entry.orbs      or 0
                    local extra  = entry.extraItem or 0
                    card.rewardRow:Set(tokens, orbs)
                    if extra > 0 then
                        local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(extra)
                        if itemName then
                            card.extraIcon:SetTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
                            card.extraText:SetText(COL_EXTRA_TX .. itemName .. "|r")
                        else
                            card.extraIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                            card.extraText:SetText(COL_EXTRA_TX .. "Bonus reward|r " .. COL_MUTED_TX .. "(loading...)|r")
                        end
                        card.extraIconHolder:Show()
                    else
                        card.extraIconHolder:Hide()
                        card.extraText:SetText("")
                    end
                    if card.endHint then
                        card.endHint:SetText(COL_MUTED_TX .. endHintText .. "|r")
                    end
                    if offer.canAccept then card.acceptBtn:Enable() else card.acceptBtn:Disable() end
                end
            end
        end
    end
end

local ClientHandler = AIO.AddHandlers("AstralChallenges", {})

ClientHandler.Show = function(_, offer)
    BuildFrame()
    if not frame then return end
    currentCategory = nil
    if pageDetail then pageDetail:Hide() end
    if pagePicker then pagePicker:Show() end
    if pickerScroll.frame then
        pickerScroll.frame:SetHorizontalScroll(0)
        if pickerScroll.frame.__recalc then pickerScroll.frame.__recalc() end
    end
    ApplyOffer(offer)
    if not frame:IsShown() then
        GateAnchor()
        gate:Show()
        frame:Show()
        FadeInFrame(frame)
    end
    local cards = {}
    for _, cat in ipairs(CATEGORIES) do
        local c = categoryCards[cat.key]
        if c then cards[#cards + 1] = c end
    end
    if StaggerCardsIn and #cards > 0 then StaggerCardsIn(cards) end
end

ClientHandler.Result = function(_, status, a, b, c)
    if status == "OK" then
        local msg
        if c then
            msg = ("Challenge started: %s %s %s"):format(a or "?", b or "?", c or "?")
        else
            msg = ("Challenge started: %s %s"):format(a or "?", b or "?")
        end
        UIErrorsFrame:AddMessage(msg,
            UI.Color.textGood[1], UI.Color.textGood[2], UI.Color.textGood[3], 1.0)
    elseif status == "ABANDONED" then
        UIErrorsFrame:AddMessage("Challenge abandoned.",
            UI.Color.textWarn[1], UI.Color.textWarn[2], UI.Color.textWarn[3], 1.0)
    elseif status == "ERR" then
        local reason = a or "UNKNOWN"
        local msg
        if     reason == "DISABLED"          then msg = "Challenges are disabled."
        elseif reason == "INVALID_COMBO"     then msg = "Invalid challenge selection."
        elseif reason == "NOT_LEVEL_1"       then msg = "Only level 1 characters can accept a challenge."
        elseif reason == "ALREADY_ACTIVE"    then msg = "You already have an active challenge."
        elseif reason == "HEIRLOOM_EQUIPPED" then msg = "Unequip all heirlooms before accepting this challenge."
        elseif reason == "NONE_ACTIVE"       then msg = "You have no active challenge."
        else                                       msg = "Challenge error: " .. reason end
        UIErrorsFrame:AddMessage(msg,
            UI.Color.textBad[1], UI.Color.textBad[2], UI.Color.textBad[3], 1.0)
    end
end

local warmer = CreateFrame("Frame")
warmer:RegisterEvent("GET_ITEM_INFO_RECEIVED")
warmer:SetScript("OnEvent", function()
    if frame and frame:IsShown() and lastOffer then
        ApplyOffer(lastOffer)
    end
end)
