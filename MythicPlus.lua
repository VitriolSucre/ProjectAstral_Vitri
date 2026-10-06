-- ---------------------------------------------------------------------
-- ProjectAstral — Mythic+ Tracker (retail-style)
-- Wire: MA| from lua_scripts/Mythicaffix/_00_shared.lua
--   MA|AFFIX|<level>|<csv-of-affix-names>|<stacking-pct>
--   MA|BOSSLIST|<name1>|<name2>|...
--   MA|BOSSKILL|<idx1>[|<idx2>...]
--   MA|PROG|<deaths>|<trashKilled>|<trashTotal>|<forcesPct>
--   MA|CLEAR
--
-- Renders a retail-style objective tracker frame anchored to the top-
-- right of the screen (below the minimap by default, draggable):
--   * Header:      dungeon name  +  [X] close
--   * Level row:   "Level N"  +  affix icons
--   * Deaths row:  orb icons + count
--   * Boss list:   checkmark + name per boss
--   * Enemy Forces: labeled progress bar %
--
-- Also keeps the per-target overlay from v1: when the player targets a
-- non-friendly unit, small icon row above TargetFrame shows which
-- affixes apply to that target.
-- ---------------------------------------------------------------------

local PA = ProjectAstral
local UI = PA.UI

local MP = {}
PA.MythicPlus = MP

-- ---------------------------------------------------------------------
-- Affix registry - icon path + display name + tooltip + who does it hit
-- ---------------------------------------------------------------------
-- Custom BLP icons shipped in Interface\AddOns\ProjectAstral\Icons.
-- Fallback (Teeming, Explosive Orb) uses vanilla Interface\Icons.
local ICONS = "Interface\\AddOns\\ProjectAstral\\Icons\\"
MP.Affixes = {
    fortified = {
        display   = "Fortified",
        icon      = ICONS .. "affixFortified",
        tooltip   = "Every enemy gains +5% HP, mana, and damage per Mythic+ level (stacking).",
        appliesTo = "all",
    },
    tyrannical = {
        display   = "Tyrannical",
        icon      = ICONS .. "affixtyranical",
        tooltip   = "Bosses have +25% HP. Bosses and their minions deal +15% damage.",
        appliesTo = "boss",
    },
    grievous = {
        display   = "Grievous",
        icon      = ICONS .. "Grievous",
        tooltip   = "Injured players suffer 3% max-HP bleed damage every 2 seconds until healed to full.",
        appliesTo = "all",
    },
    raging = {
        display   = "Raging",
        icon      = ICONS .. "raging",
        tooltip   = "Non-boss enemies enrage at 30% HP: immune to crowd control and deal +50% damage.",
        appliesTo = "trash",
    },
    inspiring = {
        display   = "Inspiring",
        icon      = ICONS .. "Inspiring",
        tooltip   = "Some non-boss enemies emit an aura that grants +25% damage to their allies. Kill the inspiring mob to remove.",
        appliesTo = "trash",
    },
    explosive_orb = {
        display   = "Explosive Ogre",
        icon      = "Interface\\Icons\\achievement_reputation_ogre",
        tooltip   = "Every 15 s a 1000-HP Explosive Ogre spawns near a combat player. Kill it before it detonates or eat 15% max HP.",
        appliesTo = "all",
    },
    explosive_corpse = {
        display   = "Explosive Corpse",
        icon      = ICONS .. "Explosive Corpse",
        tooltip   = "Every corpse (trash + boss) explodes on death for 10% of each nearby player's max HP within 10 yards.",
        appliesTo = "all",
    },
    teeming = {
        display   = "Teeming",
        icon      = "Interface\\Icons\\achievement_bg_killingblow_berserker",
        tooltip   = "Additional non-boss enemies are present throughout the dungeon (roughly +2 per 10 mobs).",
        appliesTo = "trash",
    },
    -- Display-only pseudo-affix: renders the ogre countdown aura so
    -- hovering it reads as "Explode" instead of "Fel Detonation".
    -- Not in the affix pool - only used by the tooltip / icon overrides.
    explode = {
        display   = "Explode",
        icon      = "Interface\\Icons\\achievement_reputation_ogre",
        tooltip   = "The Ogre is charging up a detonation. Kill it before the timer hits zero or take 15% max HP AoE damage.",
        appliesTo = "all",
    },
}

-- ---------------------------------------------------------------------
-- Local state (mirrors wire)
-- ---------------------------------------------------------------------
MP.state = {
    active    = false,
    level     = 0,
    affixes   = {},
    stackPct  = 0,
    -- progress
    deaths      = 0,
    trashKilled = 0,
    trashTotal  = 0,
    forcesPct   = 0,
    -- boss list
    bosses      = {},   -- { { name = "...", killed = false }, ... }
}

-- ---------------------------------------------------------------------
-- Frame globals
-- ---------------------------------------------------------------------
local FRAME_W        = 260
local HEADER_H       = 26
local LEVEL_ROW_H    = 36
local DEATH_ROW_H    = 24
local BOSS_ROW_H     = 18
local FORCES_H       = 38
local PAD            = 10
local AFFIX_ICON     = 22
local AFFIX_SPACING  = 3
local DEATH_ICON     = 16
local DEATH_SPACING  = 2
local MAX_DEATH_ORBS = 8      -- after that, just show the number

local tracker        -- main frame
local headerTitle
local closeBtn
local levelText
local affixIconBar   -- container frame for icons
local affixIcons = {}
local deathIcons = {}
local deathCountText
local bossFrames = {}       -- rows created on-demand
local forcesLabel
local forcesBar
local forcesText

-- Target-frame overlay (from v1)
local targetOverlay
local targetIcons = {}
local TARGET_ICON_SIZE     = 22
local TARGET_ICON_SPACING  = 3

-- ---------------------------------------------------------------------
-- Icon pool helper
-- ---------------------------------------------------------------------
local function AcquireIcon(pool, parent, size, borderColor)
    for _, ic in ipairs(pool) do
        if not ic:IsShown() then return ic end
    end
    local ic = CreateFrame("Frame", nil, parent)
    ic:SetSize(size, size)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetAllPoints()
    -- Full-size render. The old code trimmed (0.08, 0.92) which is the
    -- correct crop for Interface\Icons\* (Blizzard sprites have a 4 px
    -- pad); custom BLPs shipped in Icons\ are already tightly cropped
    -- so trimming them cuts off content. We render the full texture
    -- and drop the extra astral-purple border overlay entirely - the
    -- icon art is designed to stand on its own.
    ic.tex:SetDrawLayer("ARTWORK", 1)
    ic:EnableMouse(true)
    ic:SetScript("OnEnter", function(self)
        if not self.tipText then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.tipTitle or "?", 1, 1, 1)
        GameTooltip:AddLine(self.tipText, 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[#pool + 1] = ic
    return ic
end

local function ReleaseAllIcons(pool)
    for _, ic in ipairs(pool) do
        ic:Hide()
        ic:ClearAllPoints()
    end
end

-- ---------------------------------------------------------------------
-- Build the tracker frame (lazy)
-- ---------------------------------------------------------------------
local function BuildTracker()
    if tracker then return end

    tracker = CreateFrame("Frame", "AstralMythicTracker", UIParent)
    tracker.__paUnified = true   -- unified look: Theme.lua keeps its navy
    tracker:SetSize(FRAME_W, 400)  -- height gets adjusted in Refresh
    tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -160)
    tracker:SetFrameStrata("MEDIUM")
    tracker:SetMovable(true)
    tracker:EnableMouse(true)
    tracker:RegisterForDrag("LeftButton")
    tracker:SetScript("OnDragStart", tracker.StartMoving)
    tracker:SetScript("OnDragStop", tracker.StopMovingOrSizing)
    tracker:SetClampedToScreen(true)

    UI.AstralBackdrop(tracker, { thin = true })
    UI.AddStarfield(tracker, 0.05)

    -- Header bar background (slightly darker)
    local header = tracker:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\Buttons\\WHITE8X8")
    header:SetVertexColor(0.10, 0.08, 0.22, 0.9)
    header:SetPoint("TOPLEFT",  tracker, "TOPLEFT",  8, -8)
    header:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -8, -8)
    header:SetHeight(HEADER_H)

    headerTitle = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerTitle:SetPoint("LEFT", header, "LEFT", 8, 0)
    headerTitle:SetTextColor(unpack(UI.Color.textTitle))
    headerTitle:SetText("Mythic+")

    closeBtn = CreateFrame("Button", nil, tracker, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(closeBtn)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", 4, 0)
    closeBtn:SetScript("OnClick", function() tracker:Hide() end)

    -- Level text (large) - top row, centered
    levelText = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    levelText:SetPoint("TOP", tracker, "TOP", 0, -(HEADER_H + PAD + 4))
    levelText:SetTextColor(unpack(UI.Color.textHi))
    levelText:SetText("Level 0")

    -- Affix icons on a dedicated row BELOW the level text (retail-style
    -- layout: level headline, then affix icons underneath). Anchored
    -- to CENTER so the icon strip is nicely balanced.
    local AFFIX_ROW_Y = -(HEADER_H + PAD + LEVEL_ROW_H)
    affixIconBar = CreateFrame("Frame", nil, tracker)
    affixIconBar:SetPoint("TOP", tracker, "TOP", 0, AFFIX_ROW_Y)
    affixIconBar:SetSize(200, AFFIX_ICON)
    tracker.affixRowY = AFFIX_ROW_Y

    -- Death row - "Deaths:" label + orbs + count, sits below the affix icons
    local DEATH_ROW_Y = AFFIX_ROW_Y - AFFIX_ICON - PAD
    local deathLabel = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    deathLabel:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD, DEATH_ROW_Y)
    deathLabel:SetTextColor(unpack(UI.Nav.muted))
    deathLabel:SetText("Deaths:")
    tracker.deathLabel = deathLabel

    deathCountText = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deathCountText:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -PAD, DEATH_ROW_Y - 3)
    deathCountText:SetTextColor(unpack(UI.Color.textTitle))
    deathCountText:SetText("0")

    -- Boss list anchor (rows created lazily)
    tracker.bossAnchorY = DEATH_ROW_Y - DEATH_ROW_H - PAD

    -- Forces label + bar (placed at bottom, positioned in Refresh)
    forcesLabel = tracker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    forcesLabel:SetTextColor(unpack(UI.Color.textAccent))
    forcesLabel:SetText("Enemy Forces")

    forcesBar = CreateFrame("StatusBar", nil, tracker)
    forcesBar:SetHeight(14)
    forcesBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    forcesBar:SetStatusBarColor(0.35, 0.60, 1.00)
    forcesBar:SetMinMaxValues(0, 100)
    forcesBar:SetValue(0)

    local barBg = forcesBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    barBg:SetVertexColor(0.10, 0.08, 0.22, 0.9)

    forcesText = forcesBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    forcesText:SetPoint("CENTER", forcesBar, "CENTER", 0, 0)
    forcesText:SetTextColor(unpack(UI.Color.textTitle))
    forcesText:SetText("0.00%")
end

-- ---------------------------------------------------------------------
-- Boss row factory (create-on-demand, reused across dungeon changes)
-- ---------------------------------------------------------------------
local function GetBossRow(index)
    if bossFrames[index] then return bossFrames[index] end
    local row = CreateFrame("Frame", nil, tracker)
    row:SetSize(FRAME_W - 2 * PAD, BOSS_ROW_H)

    row.check = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.check:SetWidth(16)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.label:SetJustifyH("LEFT")

    bossFrames[index] = row
    return row
end

-- ---------------------------------------------------------------------
-- Refresh the tracker with current state
-- ---------------------------------------------------------------------
local function RefreshTracker()
    if not MP.state.active then
        if tracker then tracker:Hide() end
        return
    end
    BuildTracker()

    -- Header: dungeon name via client API
    local mapName = GetRealZoneText() or "Mythic+"
    local inInst, kind = IsInInstance()
    if inInst then
        mapName = GetInstanceInfo() or mapName
    end
    headerTitle:SetText(mapName)

    -- Level text
    levelText:SetText(string.format("Level %d  |cffb8a8ff+%d%%|r",
        MP.state.level, MP.state.stackPct))

    -- Affix icons (top-right of level row)
    ReleaseAllIcons(affixIcons)
    local names = { "fortified" }
    for _, n in ipairs(MP.state.affixes) do
        names[#names + 1] = n
    end
    local rowW = #names * AFFIX_ICON + (#names - 1) * AFFIX_SPACING
    affixIconBar:SetWidth(rowW)
    for i, name in ipairs(names) do
        local spec = MP.Affixes[name]
        if spec then
            local ic = AcquireIcon(affixIcons, affixIconBar, AFFIX_ICON)
            ic.tex:SetTexture(spec.icon)
            ic.tipTitle = spec.display
            ic.tipText  = spec.tooltip
            ic:ClearAllPoints()
            ic:SetPoint("LEFT", affixIconBar, "LEFT",
                        (i - 1) * (AFFIX_ICON + AFFIX_SPACING), 0)
            ic:Show()
        end
    end

    -- Death orbs
    ReleaseAllIcons(deathIcons)
    local orbsToShow = math.min(MP.state.deaths, MAX_DEATH_ORBS)
    for i = 1, orbsToShow do
        local ic = AcquireIcon(deathIcons, tracker, DEATH_ICON, {1.0, 0.35, 0.35, 0.9})
        ic.tex:SetTexture("Interface\\Icons\\ability_rogue_deadliness")  -- red skull
        ic.tipTitle = "Party Death"
        ic.tipText  = "A player was killed by an enemy."
        ic:ClearAllPoints()
        ic:SetPoint("LEFT", tracker.deathLabel, "RIGHT",
                    8 + (i - 1) * (DEATH_ICON + DEATH_SPACING), 0)
        ic:Show()
    end
    deathCountText:SetText(tostring(MP.state.deaths))

    -- Boss list
    local yCursor = tracker.bossAnchorY
    for i, boss in ipairs(MP.state.bosses) do
        local row = GetBossRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD, yCursor)
        row:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -PAD, yCursor)
        if boss.killed then
            row.check:SetText("|cff55ff55✓|r")
            row.label:SetTextColor(0.55, 0.55, 0.55)
        else
            row.check:SetText("|cff888888○|r")
            row.label:SetTextColor(unpack(UI.Color.textPrimary))
        end
        row.label:SetText(boss.name)
        row:Show()
        yCursor = yCursor - BOSS_ROW_H
    end
    -- Hide leftover rows from a previous longer dungeon
    for i = #MP.state.bosses + 1, #bossFrames do
        bossFrames[i]:Hide()
    end

    -- Forces bar at the bottom
    yCursor = yCursor - PAD
    forcesLabel:ClearAllPoints()
    forcesLabel:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD, yCursor)
    forcesBar:ClearAllPoints()
    forcesBar:SetPoint("TOPLEFT", tracker, "TOPLEFT", PAD, yCursor - 18)
    forcesBar:SetPoint("TOPRIGHT", tracker, "TOPRIGHT", -PAD, yCursor - 18)
    forcesBar:SetValue(MP.state.forcesPct)
    forcesText:SetText(string.format("%.2f%%", MP.state.forcesPct))

    -- Resize tracker to fit contents
    local totalH = math.abs(yCursor - 18) + 14 + PAD
    tracker:SetHeight(totalH)

    tracker:Show()
end

-- ---------------------------------------------------------------------
-- Target-frame overlay (kept from v1)
-- ---------------------------------------------------------------------
local function IsBossTarget()
    local class = UnitClassification("target") or ""
    if class == "worldboss" or class == "boss" then return true end
    if class == "elite" or class == "rareelite" then
        local inInstance, kind = IsInInstance()
        if inInstance and (kind == "party" or kind == "raid") then
            return true
        end
    end
    return false
end

local function RefreshTargetOverlay()
    if not MP.state.active then
        if targetOverlay then targetOverlay:Hide() end
        return
    end
    if not UnitExists("target") or UnitIsPlayer("target") or UnitIsFriend("player", "target") then
        if targetOverlay then targetOverlay:Hide() end
        return
    end

    if not targetOverlay then
        targetOverlay = CreateFrame("Frame", "AstralMythicTargetIcons", UIParent)
        targetOverlay.__paUnified = true   -- unified look: Theme.lua keeps its navy
        targetOverlay:SetSize(200, TARGET_ICON_SIZE)
        targetOverlay:SetFrameStrata("MEDIUM")
    end
    ReleaseAllIcons(targetIcons)

    local isBoss = IsBossTarget()
    local applied = {}
    if not isBoss then applied[#applied + 1] = "fortified" end
    for _, name in ipairs(MP.state.affixes) do
        local spec = MP.Affixes[name]
        if spec then
            if spec.appliesTo == "all"
               or (spec.appliesTo == "boss" and isBoss)
               or (spec.appliesTo == "trash" and not isBoss) then
                applied[#applied + 1] = name
            end
        end
    end
    if #applied == 0 then targetOverlay:Hide() return end

    targetOverlay:ClearAllPoints()
    targetOverlay:SetPoint("BOTTOM", TargetFrame or UIParent, "TOP", 0, 6)
    local rowW = #applied * TARGET_ICON_SIZE + (#applied - 1) * TARGET_ICON_SPACING
    targetOverlay:SetWidth(rowW)

    for i, name in ipairs(applied) do
        local spec = MP.Affixes[name]
        local ic = AcquireIcon(targetIcons, targetOverlay, TARGET_ICON_SIZE)
        ic.tex:SetTexture(spec.icon)
        ic.tipTitle = spec.display
        ic.tipText  = spec.tooltip
        ic:ClearAllPoints()
        ic:SetPoint("LEFT", targetOverlay, "LEFT",
                    (i - 1) * (TARGET_ICON_SIZE + TARGET_ICON_SPACING), 0)
        ic:Show()
    end
    targetOverlay:Show()
end

MP.Refresh = function()
    RefreshTracker()
    RefreshTargetOverlay()
end

-- ---------------------------------------------------------------------
-- Wire parsing
-- ---------------------------------------------------------------------
local function ParseAffix(msg)
    local level, csv, stackPct = msg:match("^MA|AFFIX|(%-?%d+)|([^|]*)|(%-?%d+)$")
    if not level then return end
    MP.state.level    = tonumber(level) or 0
    MP.state.stackPct = tonumber(stackPct) or 0
    MP.state.active   = MP.state.level > 0
    MP.state.affixes  = {}
    if csv and csv ~= "" and csv ~= "none" then
        for name in string.gmatch(csv, "([^,]+)") do
            MP.state.affixes[#MP.state.affixes + 1] = name
        end
    end
end

local function ParseBossList(msg)
    -- MA|BOSSLIST|name1|name2|...
    MP.state.bosses = {}
    local names = {}
    for name in string.gmatch(msg, "|([^|]+)") do
        names[#names + 1] = name
    end
    -- First split gets "BOSSLIST" - discard
    for i = 2, #names do
        MP.state.bosses[#MP.state.bosses + 1] = { name = names[i], killed = false }
    end
end

local function ParseBossKill(msg)
    -- MA|BOSSKILL|idx1[|idx2...]
    for idx in string.gmatch(msg, "|(%d+)") do
        local n = tonumber(idx)
        if n and MP.state.bosses[n] then
            MP.state.bosses[n].killed = true
        end
    end
end

local function ParseProgress(msg)
    -- MA|PROG|deaths|trashKilled|trashTotal|forcesPct
    local d, k, t, p = msg:match("^MA|PROG|(%d+)|(%d+)|(%d+)|([%d%.]+)$")
    if not d then return end
    MP.state.deaths      = tonumber(d) or 0
    MP.state.trashKilled = tonumber(k) or 0
    MP.state.trashTotal  = tonumber(t) or 0
    MP.state.forcesPct   = tonumber(p) or 0
end

local function ParseWire(msg)
    if not msg or msg:sub(1, 3) ~= "MA|" then return end

    if msg == "MA|CLEAR" then
        MP.state.active    = false
        MP.state.level     = 0
        MP.state.affixes   = {}
        MP.state.stackPct  = 0
        MP.state.deaths    = 0
        MP.state.trashKilled = 0
        MP.state.forcesPct = 0
        MP.state.bosses    = {}
    elseif msg:sub(1, 9) == "MA|AFFIX|" then
        ParseAffix(msg)
    elseif msg:sub(1, 12) == "MA|BOSSLIST|" then
        ParseBossList(msg)
    elseif msg:sub(1, 12) == "MA|BOSSKILL|" then
        ParseBossKill(msg)
    elseif msg:sub(1, 8) == "MA|PROG|" then
        ParseProgress(msg)
    end
    MP.Refresh()
    return true
end

-- ---------------------------------------------------------------------
-- Suppress MA| lines from chat
-- ---------------------------------------------------------------------
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
    if msg and msg:sub(1, 3) == "MA|" then return true end
end)

-- ---------------------------------------------------------------------
-- Aura tooltip override
--
-- Server casts existing WoW spells as "markers" on affix-affected mobs
-- (Prayer of Fortitude on Fortified mobs, Rip on Tyrannical bosses,
-- Rend on Grievous players, etc). Without this hook, hovering the aura
-- shows the vanilla spell tooltip - "Prayer of Fortitude: +79 Stamina" -
-- which is nonsense in an M+ context.
--
-- We intercept the Blizzard aura-tooltip setters (SetUnitBuff /
-- SetUnitDebuff / SetUnitAura) with hooksecurefunc. Those fire AFTER
-- the default tooltip content is populated; we then read the aura via
-- UnitAura by name and, if it matches one of our marker spells, we
-- clear the tooltip and rewrite it with the affix content.
--
-- Name-lookup via GetSpellInfo so we stay locale-safe (client's own
-- localized spell name is the same key we get from UnitAura).
--
-- False-positive guard:
--   * Grievous marker (Rend) only overrides on the player self.
--   * Every other affix marker only overrides on hostile units.
--   * If a party member casts real Prayer of Fortitude the friendly-
--     unit filter drops the override.
-- ---------------------------------------------------------------------
-- v6 - reverted to working baseline. Only 3 markers:
--   * 8599  Raging (Enrage on trash below 30% HP - works, thematic)
--   * 6673  Inspiring source (Battle Shout on the ONE per pack)
--   * 30167 Ogre countdown (Fel Detonation on the 15s explode-timer)
-- All Fortified/Tyrannical/Corpse/Grievous per-mob visuals removed
-- pending custom spell_dbc + client Spell.dbc patch (see plan below).
local MARKER_SPELL_IDS = {
    [8599]  = "raging",
    [6673]  = "inspiring",
    [30167] = "explode",
}

-- Resolve to localized spell names once so lookups in the hook are O(1)
local MARKER_NAME_TO_AFFIX = {}
for id, key in pairs(MARKER_SPELL_IDS) do
    local nm = GetSpellInfo(id)
    if nm then MARKER_NAME_TO_AFFIX[nm] = key end
end

local function AuraNameAt(unit, index, filter)
    if filter == "HARMFUL" then
        return (UnitDebuff(unit, index))
    else
        return (UnitBuff(unit, index))
    end
end

local function OverrideAuraTooltip(tt, unit, index, filter)
    if not MP.state.active then return end
    if not unit then return end
    local name = AuraNameAt(unit, index, filter)
    if not name then return end
    local key = MARKER_NAME_TO_AFFIX[name]
    if not key then return end
    local spec = MP.Affixes[key]
    if not spec then return end

    -- Ownership filter
    if key == "grievous" then
        if not UnitIsUnit("player", unit) then return end
    else
        -- Skip friendly units so real party buffs (Battle Shout, Prayer
        -- of Fortitude, Mark of the Wild) keep their vanilla tooltip.
        if UnitIsFriend("player", unit) then return end
    end

    tt:ClearLines()
    tt:AddLine("|cff9edbff" .. spec.display .. "|r", 1, 1, 1)
    tt:AddLine(spec.tooltip, 0.9, 0.9, 0.9, true)
    tt:AddLine(" ")
    tt:AddLine("|cff888888Astral Mythic+|r", 0.6, 0.6, 0.6)
    tt:Show()
end

if GameTooltip then
    -- Cover every codepath a target-frame / player-frame aura button
    -- might use to populate the tooltip.
    hooksecurefunc(GameTooltip, "SetUnitBuff", function(tt, unit, index)
        OverrideAuraTooltip(tt, unit, index, "HELPFUL")
    end)
    hooksecurefunc(GameTooltip, "SetUnitDebuff", function(tt, unit, index)
        OverrideAuraTooltip(tt, unit, index, "HARMFUL")
    end)
    if GameTooltip.SetUnitAura then
        hooksecurefunc(GameTooltip, "SetUnitAura", function(tt, unit, index, filter)
            OverrideAuraTooltip(tt, unit, index, filter or "HELPFUL")
        end)
    end
end

-- ---------------------------------------------------------------------
-- Aura icon override on target/player frames
--
-- Blizzard's aura buttons use SetTexture on their Icon child with the
-- default Interface\Icons\<spellName> path for the marker spell. This
-- replaces those textures with our custom BLPs from the affix registry
-- so hovering "Rip" on a boss shows the affixtyranical.blp instead of
-- Rip's default druid-claw icon.
--
-- Fires:
--   * UNIT_AURA event for player and target
--   * hooksecurefunc on TargetFrame_UpdateAuras (Blizzard runs it on
--     every aura change; our hook re-swaps textures after Blizzard's
--     reset)
-- ---------------------------------------------------------------------
local SPELL_NAME_TO_CUSTOM_ICON = {}
for id, key in pairs(MARKER_SPELL_IDS) do
    local nm = GetSpellInfo(id)
    if nm and MP.Affixes[key] and MP.Affixes[key].icon then
        SPELL_NAME_TO_CUSTOM_ICON[nm] = MP.Affixes[key].icon
    end
end

-- Blizzard's aura buttons in 3.3.5 don't all expose the icon under a
-- single naming convention. Different variants seen in practice:
--   1. Named child texture: _G[buttonName .. "Icon"]
--   2. Field on the button table: button.icon or button.Icon
--   3. The button itself is a Button with the icon as its Normal
--      Texture (SetNormalTexture on the button)
--   4. The icon is the first Texture region of the button
-- We try all four so a texture swap lands regardless of which frame
-- template Blizzard used.
local function SwapButtonIcon(button, path)
    if not button then return false end
    local swapped = false

    local btnName = button:GetName()
    if btnName then
        local named = _G[btnName .. "Icon"]
        if named and named.SetTexture then
            named:SetTexture(path); swapped = true
        end
    end

    if button.icon and button.icon.SetTexture then
        button.icon:SetTexture(path); swapped = true
    end
    if button.Icon and button.Icon.SetTexture then
        button.Icon:SetTexture(path); swapped = true
    end

    if button.SetNormalTexture then
        button:SetNormalTexture(path)
        swapped = true
    end

    -- Region-scan fallback: find any Texture child whose current
    -- texture path contains "Icons\" (i.e. Blizzard's default spell
    -- icon) and swap it.
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            local cur = region:GetTexture()
            if cur and type(cur) == "string" and cur:find("[Ii]cons\\") then
                region:SetTexture(path)
                swapped = true
            end
        end
    end

    return swapped
end

local function TryOverrideIconOnButton(button, unit, index, isBuff)
    if not button or not button:IsShown() then return end
    local name = isBuff and UnitBuff(unit, index) or UnitDebuff(unit, index)
    if not name then return end
    local customIcon = SPELL_NAME_TO_CUSTOM_ICON[name]
    if not customIcon then return end

    -- Ownership filter to prevent overriding real party buffs. Same
    -- shape as the tooltip-override filter:
    --   * Grievous marker (Corruption) only overrides on player self.
    --   * Every other affix marker only overrides on hostile units.
    -- Without this, a friendly Druid casting real Mark of the Wild on
    -- the party would have his buff swapped to the Teeming icon on
    -- everyone's target frame.
    local key = MARKER_NAME_TO_AFFIX[name]
    if key == "grievous" then
        if not UnitIsUnit("player", unit) then return end
    else
        if UnitIsFriend("player", unit) then return end
    end

    SwapButtonIcon(button, customIcon)
end

-- Prefixes for aura-button globals across different 3.3.5 UI variants
-- and custom addon replacements. We scan up to slot 40 for each so a
-- mob with many stacked auras still has its markers reached.
local TARGET_BUFF_PREFIXES   = { "TargetFrameBuff",   "TargetBuff"   }
local TARGET_DEBUFF_PREFIXES = { "TargetFrameDebuff", "TargetDebuff" }
local PLAYER_BUFF_PREFIXES   = { "BuffButton", "PlayerBuffButton" }
local PLAYER_DEBUFF_PREFIXES = { "DebuffButton", "PlayerDebuff", "TempEnchant" }

local function ScanPrefix(prefix, unit, isBuff, maxSlot)
    for i = 1, maxSlot do
        TryOverrideIconOnButton(_G[prefix .. i], unit, i, isBuff)
    end
end

local function RefreshAuraIcons()
    if not MP.state.active then return end
    for _, p in ipairs(TARGET_BUFF_PREFIXES)   do ScanPrefix(p, "target", true,  40) end
    for _, p in ipairs(TARGET_DEBUFF_PREFIXES) do ScanPrefix(p, "target", false, 40) end
    for _, p in ipairs(PLAYER_BUFF_PREFIXES)   do ScanPrefix(p, "player", true,  40) end
    for _, p in ipairs(PLAYER_DEBUFF_PREFIXES) do ScanPrefix(p, "player", false, 40) end
end

if type(TargetFrame_UpdateAuras) == "function" then
    hooksecurefunc("TargetFrame_UpdateAuras", RefreshAuraIcons)
end
if type(BuffFrame_Update) == "function" then
    hooksecurefunc("BuffFrame_Update", RefreshAuraIcons)
end

-- Defensive OnUpdate ticker. Blizzard's TargetFrame_UpdateAuras may not
-- fire on some edge paths (target frame recreated after a boss dies
-- and respawns, focus frame variants, etc). Ticker runs every 0.4 s and
-- re-swaps our marker textures. Cheap because RefreshAuraIcons no-ops
-- when MP.state.active is false or the aura name isn't in our map.
local iconRefreshTicker = CreateFrame("Frame")
local iconRefreshAcc = 0
iconRefreshTicker:SetScript("OnUpdate", function(self, dt)
    iconRefreshAcc = iconRefreshAcc + dt
    if iconRefreshAcc < 0.4 then return end
    iconRefreshAcc = 0
    RefreshAuraIcons()
end)

-- ---------------------------------------------------------------------
-- Event pump
-- ---------------------------------------------------------------------
local evt = CreateFrame("Frame")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:RegisterEvent("PLAYER_TARGET_CHANGED")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("UNIT_AURA")
-- Ask the server to re-push affix + boss list + progress. Fires on
-- login, /reload, portal transit - anywhere that resets the client
-- state without triggering the server's own MAP_CHANGE push.
local function RequestSync()
    -- Small delay so the session finishes wiring up before the round-
    -- trip. Timers via C_Timer are Cata+ only; we use OnUpdate.
    local f = CreateFrame("Frame")
    local t = 0
    f:SetScript("OnUpdate", function(self, dt)
        t = t + dt
        if t < 1.5 then return end
        self:SetScript("OnUpdate", nil)
        SendChatMessage(".mplus sync", "SAY")
    end)
end

evt:SetScript("OnEvent", function(self, event, arg1)
    if event == "CHAT_MSG_SYSTEM" then
        ParseWire(arg1)
    elseif event == "PLAYER_TARGET_CHANGED" then
        RefreshTargetOverlay()
        RefreshAuraIcons()
    elseif event == "UNIT_AURA" then
        if arg1 == "target" or arg1 == "player" then
            RefreshAuraIcons()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        MP.Refresh()
        RequestSync()
    end
end)
