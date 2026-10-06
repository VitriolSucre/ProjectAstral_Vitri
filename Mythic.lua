-- Mythic Raid hub: status, lockouts, item upgrade.
-- Wire: FX| from mod-mythicraid, LR| lockouts, AT|PRESTIGE_TOKENS|.

local PA = ProjectAstral

local M = {}
M.armed       = false   -- group mythic-pending
M.inMythic    = false   -- inside a mythic instance
M.currentMap  = 0
M.lockouts    = {}      -- LR rows where diff == 5
M.items       = {}
M.nextStatsBySlot = {}  -- slot -> next-level stats
M.itemInfoByEntry = {}  -- entry -> {level,max} for tooltip
M.knownBags       = {}  -- bag entry -> {mapId, bagName}
M.receiving   = false
M.statusText  = ""
M.statusUntil = 0

local frame
local banner
local upgradeF

-- ── Stat-key → label map ────────────────────────────────────────────────────
-- 3.3.5a quirk: armor lives under RESISTANCE0_NAME in GetItemStats output.
local STAT_KEY_LABELS = {
    ITEM_MOD_AGILITY_SHORT                  = "Agility",
    ITEM_MOD_STRENGTH_SHORT                 = "Strength",
    ITEM_MOD_INTELLECT_SHORT                = "Intellect",
    ITEM_MOD_SPIRIT_SHORT                   = "Spirit",
    ITEM_MOD_STAMINA_SHORT                  = "Stamina",
    ITEM_MOD_HEALTH                         = "Health",
    ITEM_MOD_MANA                           = "Mana",
    ITEM_MOD_HIT_RATING_SHORT               = "Hit Rating",
    ITEM_MOD_HIT_MELEE_RATING_SHORT         = "Melee Hit",
    ITEM_MOD_HIT_RANGED_RATING_SHORT        = "Ranged Hit",
    ITEM_MOD_HIT_SPELL_RATING_SHORT         = "Spell Hit",
    ITEM_MOD_CRIT_RATING_SHORT              = "Critical Strike",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT        = "Melee Crit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT       = "Ranged Crit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT        = "Spell Crit",
    ITEM_MOD_HASTE_RATING_SHORT             = "Haste Rating",
    ITEM_MOD_EXPERTISE_RATING_SHORT         = "Expertise",
    ITEM_MOD_ATTACK_POWER_SHORT             = "Attack Power",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT      = "Ranged AP",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT       = "Feral AP",
    ITEM_MOD_SPELL_POWER_SHORT              = "Spell Power",
    ITEM_MOD_SPELL_PENETRATION_SHORT        = "Spell Penetration",
    ITEM_MOD_MANA_REGENERATION_SHORT        = "Mana Per 5",
    ITEM_MOD_HEALTH_REGEN_SHORT             = "Health Per 5",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT     = "Defense Rating",
    ITEM_MOD_DODGE_RATING_SHORT             = "Dodge Rating",
    ITEM_MOD_PARRY_RATING_SHORT             = "Parry Rating",
    ITEM_MOD_BLOCK_RATING_SHORT             = "Block Rating",
    ITEM_MOD_BLOCK_VALUE_SHORT              = "Block Value",
    ITEM_MOD_RESILIENCE_RATING_SHORT        = "Resilience",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "Armor Penetration",
    RESISTANCE0_NAME                        = "Armor",
    RESISTANCE1_NAME                        = "Holy Resistance",
    RESISTANCE2_NAME                        = "Fire Resistance",
    RESISTANCE3_NAME                        = "Nature Resistance",
    RESISTANCE4_NAME                        = "Frost Resistance",
    RESISTANCE5_NAME                        = "Shadow Resistance",
    RESISTANCE6_NAME                        = "Arcane Resistance",
}

-- render order: primaries, secondaries, resistances; rest at bottom
local STAT_KEY_ORDER = {
    "RESISTANCE0_NAME",
    "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_AGILITY_SHORT",
    "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_SPIRIT_SHORT",
    "ITEM_MOD_ATTACK_POWER_SHORT",
    "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_FERAL_ATTACK_POWER_SHORT",
    "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_HIT_RATING_SHORT",
    "ITEM_MOD_HIT_MELEE_RATING_SHORT",
    "ITEM_MOD_HIT_RANGED_RATING_SHORT",
    "ITEM_MOD_HIT_SPELL_RATING_SHORT",
    "ITEM_MOD_EXPERTISE_RATING_SHORT",
    "ITEM_MOD_CRIT_RATING_SHORT",
    "ITEM_MOD_CRIT_MELEE_RATING_SHORT",
    "ITEM_MOD_CRIT_RANGED_RATING_SHORT",
    "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
    "ITEM_MOD_HASTE_RATING_SHORT",
    "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    "ITEM_MOD_SPELL_PENETRATION_SHORT",
    "ITEM_MOD_MANA_REGENERATION_SHORT",
    "ITEM_MOD_HEALTH_REGEN_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    "ITEM_MOD_DODGE_RATING_SHORT",
    "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_BLOCK_RATING_SHORT",
    "ITEM_MOD_BLOCK_VALUE_SHORT",
    "ITEM_MOD_RESILIENCE_RATING_SHORT",
}
local STAT_KEY_RANK = {}
for i, k in ipairs(STAT_KEY_ORDER) do STAT_KEY_RANK[k] = i end

-- maps DB stat_type ids to UI ITEM_MOD_*_SHORT keys
local STAT_TYPE_TO_ITEM_MOD = {
    [3]  = "ITEM_MOD_AGILITY_SHORT",
    [4]  = "ITEM_MOD_STRENGTH_SHORT",
    [5]  = "ITEM_MOD_INTELLECT_SHORT",
    [6]  = "ITEM_MOD_SPIRIT_SHORT",
    [7]  = "ITEM_MOD_STAMINA_SHORT",
    [12] = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT",
    [13] = "ITEM_MOD_DODGE_RATING_SHORT",
    [14] = "ITEM_MOD_PARRY_RATING_SHORT",
    [15] = "ITEM_MOD_BLOCK_RATING_SHORT",
    [16] = "ITEM_MOD_HIT_MELEE_RATING_SHORT",
    [17] = "ITEM_MOD_HIT_RANGED_RATING_SHORT",
    [18] = "ITEM_MOD_HIT_SPELL_RATING_SHORT",
    [19] = "ITEM_MOD_CRIT_MELEE_RATING_SHORT",
    [20] = "ITEM_MOD_CRIT_RANGED_RATING_SHORT",
    [21] = "ITEM_MOD_CRIT_SPELL_RATING_SHORT",
    [31] = "ITEM_MOD_HIT_RATING_SHORT",
    [32] = "ITEM_MOD_CRIT_RATING_SHORT",
    [35] = "ITEM_MOD_RESILIENCE_RATING_SHORT",
    [36] = "ITEM_MOD_HASTE_RATING_SHORT",
    [37] = "ITEM_MOD_EXPERTISE_RATING_SHORT",
    [38] = "ITEM_MOD_ATTACK_POWER_SHORT",
    [39] = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    [41] = "ITEM_MOD_HEALING_DONE",
    [42] = "ITEM_MOD_DAMAGE_DONE",
    [43] = "ITEM_MOD_MANA_REGENERATION_SHORT",
    [44] = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
    [45] = "ITEM_MOD_SPELL_POWER_SHORT",
    [46] = "ITEM_MOD_HEALTH_REGEN_SHORT",
    [47] = "ITEM_MOD_SPELL_PENETRATION_SHORT",
    [48] = "ITEM_MOD_BLOCK_VALUE_SHORT",
}

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

local function Split(str, sep)
    local t, i = {}, 1
    while true do
        local j = str:find(sep, i, true)
        if j then t[#t+1] = str:sub(i, j-1); i = j+1
        else      t[#t+1] = str:sub(i); break end
    end
    return t
end

local function FormatNumber(n)
    n = tonumber(n) or 0
    local s = tostring(n)
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function FormatRelative(unixResetTs)
    local now  = time()
    local left = (tonumber(unixResetTs) or 0) - now
    if left <= 0 then return "expired" end
    local d = math.floor(left / 86400);  left = left - d * 86400
    local h = math.floor(left / 3600);   left = left - h * 3600
    local m = math.floor(left / 60)
    if d > 0 then return string.format("in %dd %dh", d, h) end
    if h > 0 then return string.format("in %dh %dm", h, m) end
    return string.format("in %dm", m)
end

local SLOT_NAMES = {
    [0]  = "Head",     [1]  = "Neck",     [2]  = "Shoulders", [3]  = "Shirt",
    [4]  = "Chest",    [5]  = "Waist",    [6]  = "Legs",      [7]  = "Feet",
    [8]  = "Wrists",   [9]  = "Hands",    [10] = "Ring 1",    [11] = "Ring 2",
    [12] = "Trinket 1",[13] = "Trinket 2",[14] = "Back",      [15] = "Main Hand",
    [16] = "Off Hand", [17] = "Ranged",   [18] = "Tabard",
}

local function SlotName(slot)
    return SLOT_NAMES[tonumber(slot) or -1] or ("Slot " .. tostring(slot))
end

local function FlashStatus(msg, color)
    M.statusText  = (color or "|cffffffff") .. msg .. "|r"
    M.statusUntil = time() + 5
    if frame and frame:IsShown() then frame:_refresh() end
end

-- ── Minimap banner ───────────────────────────────────────────────────────────
-- Replaces MiniMapInstanceDifficulty while in a Mythic instance.
local function CreateBanner()
    if banner then return banner end
    local b = CreateFrame("Frame", "PAMythicBanner", Minimap)
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -6, 0)
    b:SetFrameStrata("HIGH")
    b:Hide()

    b:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    PA.UI.CosmicCorners(b)
    b:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.95))
    b:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 1.0))

    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetTexture("Interface\\Cooldown\\star4")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(0.85, 0.40, 1.00, 0.55)
    b.glow:SetSize(32, 32)
    b.glow:SetPoint("CENTER", b, "CENTER", 0, 0)

    b.skull = b:CreateTexture(nil, "ARTWORK")
    b.skull:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    b.skull:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.skull:SetSize(13, 13)
    b.skull:SetPoint("TOP", b, "TOP", 0, -2)
    b.skull:SetVertexColor(1.00, 0.92, 0.65)

    b.size = b:CreateFontString(nil, "OVERLAY")
    b.size:SetFont("Fonts\\FRIZQT__.TTF", 8, "")
    b.size:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
    b.size:SetText("20")
    b.size:SetTextColor(1.00, 0.93, 0.50)

    b._pulse = 0
    b:SetScript("OnUpdate", function(self, elapsed)
        self._pulse = (self._pulse + elapsed) % 3.5
        local a = 0.40 + 0.20 * math.sin(self._pulse * math.pi / 1.75)
        self.glow:SetVertexColor(0.85, 0.40, 1.00, a)
    end)

    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffd070ffMythic Raid|r", 1, 1, 1)
        GameTooltip:AddLine("Scaled for 20 players.", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Use /astral to manage Mythic lockouts and gear.",
            0.60, 0.60, 0.60, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    banner = b
    return b
end

local function ShowBanner()
    CreateBanner():Show()
    if MiniMapInstanceDifficulty then
        MiniMapInstanceDifficulty:Hide()
        -- the game re-shows this on diff change; trap it
        if not MiniMapInstanceDifficulty._paHooked then
            MiniMapInstanceDifficulty:HookScript("OnShow", function(self)
                if M.inMythic then self:Hide() end
            end)
            MiniMapInstanceDifficulty._paHooked = true
        end
    end
end

local function HideBanner()
    if banner then banner:Hide() end
    -- let the game's own logic re-show MiniMapInstanceDifficulty
end

-- ── Item Upgrade window ────────────────────────────────────────────────────
-- Current vs next-level stat diff. Server re-emits FX|MYITEM after upgrade.

local function CollectStats(link)
    if not link then return {} end
    local raw = GetItemStats(link)
    if not raw then return {} end
    local out = {}
    for k, v in pairs(raw) do
        if v and v ~= 0 then
            out[k] = v
        end
    end
    return out
end

-- baseline=nil for the Current column, baseline=currentStats for the diff column
local function RenderStatColumn(col, stats, baseline)
    col._lines = col._lines or {}
    for _, l in ipairs(col._lines) do l:Hide() end

    -- stats only in baseline = spell-triggered (Atiesh-style) and not in
    -- FX|MYNEXT's stat_typeN diff. Render as unchanged, not as lost.
    local seen = {}
    local list = {}
    for k, v in pairs(stats) do
        seen[k] = true
        table.insert(list, { key = k, value = v, missing = false })
    end
    if baseline then
        for k, v in pairs(baseline) do
            if not seen[k] then
                table.insert(list, { key = k, value = v, missing = true })
            end
        end
    end
    table.sort(list, function(a, b)
        local ra = STAT_KEY_RANK[a.key] or 999
        local rb = STAT_KEY_RANK[b.key] or 999
        if ra ~= rb then return ra < rb end
        return (a.key or "") < (b.key or "")
    end)

    for i, s in ipairs(list) do
        local line = col._lines[i]
        if not line then
            line = col:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            line:SetPoint("TOPLEFT", col, "TOPLEFT", 12, -28 - (i - 1) * 16)
            line:SetJustifyH("LEFT")
            line:SetWidth(220)
            col._lines[i] = line
        end
        local label = STAT_KEY_LABELS[s.key]
                      or s.key:gsub("ITEM_MOD_", ""):gsub("_SHORT", "")
                              :gsub("_", " "):lower()
        if baseline then
            if s.missing then
                line:SetText(string.format("%d |cff808080(+0)|r %s", s.value, label))
            else
                local prev = baseline[s.key] or 0
                local diff = s.value - prev
                if diff == 0 then
                    line:SetText(string.format("%d |cff808080(+0)|r %s", s.value, label))
                else
                    local sign = diff > 0 and "+" or ""
                    local color = diff > 0 and "|cff1eff00" or "|cffff4040"
                    line:SetText(string.format("%d %s(%s%d)|r %s",
                        s.value, color, sign, diff, label))
                end
            end
        else
            line:SetText(string.format("%d %s", s.value, label))
        end
        line:Show()
    end
end

local UpdateItemUpgradeWindow  -- forward
local function CreateItemUpgradeWindow()
    if upgradeF then return upgradeF end
    local f = CreateFrame("Frame", "PAItemUpgradeFrame", UIParent)
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:SetSize(540, 480)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    -- unified window: navy, gold edge
    PA.UI.AstralBackdrop(f, { thin = true })
    f:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)

    f.title = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.title, 16)
    f.title:SetPoint("TOP", f, "TOP", 0, -16)
    f.title:SetText("Item Upgrade")
    f.title:SetTextColor(1, 1, 1)
    local titleBar = f:CreateTexture(nil, "OVERLAY"); titleBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBar:SetVertexColor(0.886, 0.753, 0.384, 1); titleBar:SetSize(3, 17)
    titleBar:SetPoint("RIGHT", f.title, "LEFT", -9, 0)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(closeBtn)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    f.iconHolder = CreateFrame("Frame", nil, f)
    f.iconHolder:SetSize(46, 46)
    f.iconHolder:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -54)
    f.iconHolder.tex = f.iconHolder:CreateTexture(nil, "ARTWORK")
    f.iconHolder.tex:SetAllPoints()
    f.iconHolder.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.itemName = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.itemName:SetPoint("TOPLEFT", f.iconHolder, "TOPRIGHT", 14, -2)
    f.itemName:SetTextColor(0.65, 0.45, 0.92)

    f.itemLevel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.itemLevel:SetPoint("TOPLEFT", f.itemName, "BOTTOMLEFT", 0, -4)
    f.itemLevel:SetTextColor(0.92, 0.65, 1.00)

    local function MakeColumn(label, anchorX)
        local col = CreateFrame("Frame", nil, f)
        col:SetSize(238, 280)
        col:SetPoint("TOPLEFT", f, "TOPLEFT", anchorX, -120)
        col:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        PA.UI.CosmicCorners(col)
        col:SetBackdropColor(PA.UI.Tint(0.043, 0.067, 0.188, 0.92))
        col:SetBackdropBorderColor(0.45, 0.32, 0.62, 1.0)

        col.label = col:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        col.label:SetPoint("TOPLEFT", col, "TOPLEFT", 10, -8)
        col.label:SetText(label)
        col.label:SetTextColor(0.65, 0.78, 1.00)
        return col
    end
    f.colCurrent = MakeColumn("Current:", 24)
    f.colNext    = MakeColumn("Upgrade:", 278)

    f.costLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.costLabel:SetPoint("BOTTOM", f, "BOTTOM", 0, 70)
    f.costLabel:SetText("")

    f.upgradeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    PA.UI.CosmicButton(f.upgradeBtn)
    f.upgradeBtn:SetSize(220, 30)
    f.upgradeBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 22)
    f.upgradeBtn:SetText("Upgrade")

    upgradeF = f
    return f
end

UpdateItemUpgradeWindow = function()
    local f = upgradeF
    if not f or not M.upgradeRow then return end

    -- re-locate by slot in case server resent
    local target = M.upgradeRow
    local fresh
    for _, x in ipairs(M.items) do
        if x.slot == target.slot then fresh = x; break end
    end
    if not fresh then
        -- unequipped while window open
        f:Hide()
        M.upgradeRow = nil
        return
    end
    M.upgradeRow = fresh
    local it = fresh

    local atMax = (it.level >= it.max) or (it.nextEntry == 0)

    local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(it.entry)
    f.iconHolder.tex:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    f.itemName:SetText(link or ("Item " .. it.entry))
    f.itemLevel:SetText(string.format("Mythic +%d of %d", it.level, it.max))

    -- equipped link is always cached
    local currentLink  = GetInventoryItemLink("player", it.slot + 1)
    local currentStats = CollectStats(currentLink)

    -- use server FX|MYNEXT cache; the next-level item is rarely in
    -- GetItemInfo's cache on first open
    local nextStats = {}
    if not atMax then
        local n = M.nextStatsBySlot[it.slot]
        if n then
            if n.armor and n.armor > 0 then
                nextStats.RESISTANCE0_NAME = n.armor
            end
            for t, v in pairs(n.stats or {}) do
                local key = STAT_TYPE_TO_ITEM_MOD[t]
                if key then nextStats[key] = v end
            end
        end
    end

    f.colCurrent.label:SetText("Current  (Mythic +" .. it.level .. ")")
    RenderStatColumn(f.colCurrent, currentStats, nil)

    if atMax then
        f.colNext.label:SetText("Upgrade  —  Maxed")
        RenderStatColumn(f.colNext, {}, nil)
        f.costLabel:SetText("|cff80e090Maxed — no further upgrades available.|r")
        f.upgradeBtn:Disable()
        f.upgradeBtn:SetText("Maxed")
        f.upgradeBtn:SetScript("OnClick", nil)
    else
        f.colNext.label:SetText("Upgrade  (Mythic +" .. (it.level + 1) .. ")")
        RenderStatColumn(f.colNext, nextStats, currentStats)

        local tokens     = PA.prestigeTokens or 0
        local affordable = it.cost <= tokens
        f.costLabel:SetText(string.format(
            "Total Cost: %s%s Tokens|r",
            affordable and "|cffffd700" or "|cffff6060",
            FormatNumber(it.cost)))
        local slot = it.slot
        if affordable then
            f.upgradeBtn:Enable()
            f.upgradeBtn:SetText("Upgrade")
            f.upgradeBtn:SetScript("OnClick", function()
                Send("mythic upgrade " .. slot)
                -- server re-emits FX|MYITEM; MYITEM_END refreshes us
            end)
        else
            f.upgradeBtn:Disable()
            f.upgradeBtn:SetText("Need " .. FormatNumber(it.cost - tokens) .. " more tokens")
            f.upgradeBtn:SetScript("OnClick", nil)
        end
    end
end

local function OpenItemUpgradeWindow(it)
    M.upgradeRow = it
    local f = CreateItemUpgradeWindow()
    f:Show()
    -- prime client cache for the +N+1 item
    if it.nextEntry and it.nextEntry > 0 then GetItemInfo(it.nextEntry) end
    UpdateItemUpgradeWindow()
end

-- ── Bag role-picker dialog ─────────────────────────────────────────────────
-- 6 roles match mythicraid_loot_pool.role enum.

local bagPickerF
local function CreateBagRolePicker()
    if bagPickerF then return bagPickerF end
    local f = CreateFrame("Frame", "PABagRolePickerFrame", UIParent)
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:SetSize(360, 240)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- unified window: navy, gold edge
    PA.UI.AstralBackdrop(f, { thin = true })
    f:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)

    f.title = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.title, 16)
    f.title:SetPoint("TOP", f, "TOP", 0, -16)
    f.title:SetText("Choose Your Reward Role")
    f.title:SetTextColor(1, 1, 1)
    local titleBar = f:CreateTexture(nil, "OVERLAY"); titleBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBar:SetVertexColor(0.886, 0.753, 0.384, 1); titleBar:SetSize(3, 17)
    titleBar:SetPoint("RIGHT", f.title, "LEFT", -9, 0)

    f.bagName = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.bagName:SetPoint("TOP", f.title, "BOTTOM", 0, -4)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOP", f.bagName, "BOTTOM", 0, -6)
    f.hint:SetText("Picks a random item from the role's loot pool that fits your class.")
    f.hint:SetWidth(320)
    f.hint:SetJustifyH("CENTER")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(closeBtn)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    local ROLES = { "tank", "healer", "melee", "caster", "misc", "profession" }
    local LABELS = {
        tank       = "Tank",
        healer     = "Healer",
        melee      = "Melee",
        caster     = "Caster",
        misc       = "Misc",
        profession = "Profession",
    }
    f.btns = {}
    for i, role in ipairs(ROLES) do
        local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        PA.UI.CosmicButton(btn)
        btn:SetSize(96, 26)
        local col = ((i - 1) % 3)
        local row = math.floor((i - 1) / 3)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT",
            18 + col * 110, -100 - row * 36)
        btn:SetText(LABELS[role])
        btn:SetScript("OnClick", function()
            if not f._bagEntry then return end
            Send("mythic openbag " .. f._bagEntry .. " " .. role)
            f:Hide()
        end)
        f.btns[role] = btn
    end

    bagPickerF = f
    return f
end

function OpenBagRolePicker(bagEntry, mapId, bagName)
    local f = CreateBagRolePicker()
    f._bagEntry = bagEntry
    f._mapId    = mapId
    f.bagName:SetText("|cffd070ff" .. (bagName or ("Bag " .. bagEntry)) .. "|r")
    f:Show()
end

-- ── FX| message handling ─────────────────────────────────────────────────────

local function OnFXMessage(raw)
    local p = Split(raw, "|")
    local cmd = p[2]

    if cmd == "MYTHIC_STATE" then
        local mapId = tonumber(p[3]) or 0
        local active = (p[4] == "1")
        M.currentMap = mapId
        M.inMythic   = active
        if active then ShowBanner() else HideBanner() end

    elseif cmd == "MYTHIC_ARMED" then
        M.armed = (p[3] == "1")
        if frame and frame:IsShown() then frame:_refresh() end

    elseif cmd == "MYITEM" then
        if not M.receiving then
            M.items = {}
            M.nextStatsBySlot = {}
            M.itemInfoByEntry = {}
            M.receiving = true
        end
        table.insert(M.items, {
            slot       = tonumber(p[3]) or 0,
            entry      = tonumber(p[4]) or 0,
            level      = tonumber(p[5]) or 0,
            max        = tonumber(p[6]) or 0,
            nextEntry  = tonumber(p[7]) or 0,
            cost       = tonumber(p[8]) or 0,
        })

    elseif cmd == "MYNEXT" then
        -- FX|MYNEXT|slot|entry|armor|dmg_min|dmg_max|delay|type:val,type:val,...
        local slot      = tonumber(p[3]) or 0
        local statsTbl  = {}
        local csv       = p[9] or ""
        if csv ~= "" then
            for pair in csv:gmatch("[^,]+") do
                local t, v = pair:match("(%d+):(%-?%d+)")
                if t and v then statsTbl[tonumber(t)] = tonumber(v) end
            end
        end
        M.nextStatsBySlot[slot] = {
            entry   = tonumber(p[4]) or 0,
            armor   = tonumber(p[5]) or 0,
            dmg_min = tonumber(p[6]) or 0,
            dmg_max = tonumber(p[7]) or 0,
            delay   = tonumber(p[8]) or 0,
            stats   = statsTbl,
        }

    elseif cmd == "MYINFO" then
        -- FX|MYINFO|entry|level|max — tooltip overlay for all owned items
        local entry = tonumber(p[3]) or 0
        if entry > 0 then
            M.itemInfoByEntry[entry] = {
                level = tonumber(p[4]) or 0,
                max   = tonumber(p[5]) or 0,
            }
        end

    elseif cmd == "MYITEM_END" then
        M.receiving = false
        if frame and frame:IsShown() then frame:_refresh() end
        -- post-upgrade refresh flips the Current column to the new level
        if upgradeF and upgradeF:IsShown() then UpdateItemUpgradeWindow() end

    elseif cmd == "MYBAG" then
        -- cache only; role picker is opened by the UseContainerItem hook
        local bagEntry = tonumber(p[3]) or 0
        local mapId    = tonumber(p[4]) or 0
        local bagName  = p[5] or ("Bag " .. bagEntry)
        if bagEntry > 0 then
            M.knownBags[bagEntry] = { mapId = mapId, bagName = bagName }
        end
    end
end

-- lockout module broadcasts all diffs; we keep a diff==5 copy
local function OnLRMessage(raw)
    local p = Split(raw, "|")
    local cmd = p[2]
    if cmd == "LOCKOUT" then
        if not M.lrReceiving then
            M.lockouts   = {}
            M.lrReceiving = true
        end
        local diff = tonumber(p[4]) or 0
        if diff == 5 then
            table.insert(M.lockouts, {
                mapId      = tonumber(p[3]) or 0,
                difficulty = diff,
                mapName    = p[5] or "Unknown",
                diffName   = p[6] or "Mythic",
                resetTime  = tonumber(p[7]) or 0,
            })
        end
    elseif cmd == "END" then
        M.lrReceiving = false
        if frame and frame:IsShown() then frame:_refresh() end
    end
end

-- ── Tab content (renders into the suite's content panel) ───────────────────

local function BuildMythicTab(panel)
    local UI = PA.UI
    local f = panel
    f.armed = M  -- alias for readability

    -- ── Stat boxes: status / tokens / lockouts ────────────────────────────
    local boxW, gap, boxH = 178, 14, 60
    local totalW = boxW * 3 + gap * 2
    -- GetWidth() is 0 pre-layout; suite content area is fixed at 568
    local panelW = 568
    local startX = math.max(0, (panelW - totalW) / 2)

    local function MakeStat(label, xOffset)
        local box = UI.MakeStatBox(f, boxW, boxH, label)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", f, "TOPLEFT", xOffset, 0)
        return box
    end

    f.statusBox  = MakeStat("MYTHIC MODE",    startX)
    f.tokenBox   = MakeStat("TOKENS", startX + (boxW + gap))
    f.lockoutBox = MakeStat("ACTIVE LOCKOUTS", startX + (boxW + gap) * 2)

    f.statusVal  = f.statusBox.value
    f.tokenVal   = f.tokenBox.value
    f.lockoutVal = f.lockoutBox.value

    -- toggle lives in vanilla Raid Difficulty submenu, not here

    -- ── Lockouts section ──────────────────────────────────────────────────
    f.lockoutHeader = UI.MakeSectionDivider(f, "MYTHIC LOCKOUTS (0)",
        { "TOPLEFT", f, "TOPLEFT", 0, -120 })

    f.lockoutList = CreateFrame("Frame", nil, f)
    f.lockoutList:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -140)
    f.lockoutList:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -140)
    f.lockoutList:SetHeight(96)
    UI.AstralBackdrop(f.lockoutList, { thin = true, cosmic = true })
    f.lockoutRows = {}

    f.lockoutEmpty = f.lockoutList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.lockoutEmpty:SetPoint("CENTER", f.lockoutList, "CENTER", 0, 0)
    f.lockoutEmpty:SetText("No active Mythic lockouts.")
    f.lockoutEmpty:SetTextColor(unpack(UI.Nav.muted))
    f.lockoutEmpty:Hide()

    -- ── Item upgrade section ──────────────────────────────────────────────
    f.itemHeader = UI.MakeSectionDivider(f, "MYTHIC ITEM UPGRADES (0)",
        { "TOPLEFT", f, "TOPLEFT", 0, -244 })

    f.itemScroll = CreateFrame("ScrollFrame", "PAMythicItemScroll", f,
                               "UIPanelScrollFrameTemplate")
    f.itemScroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     0,   -262)
    f.itemScroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 40)
    UI.AstralBackdrop(f.itemScroll, { thin = true, cosmic = true })

    f.itemList = CreateFrame("Frame", nil, f.itemScroll)
    f.itemList:SetSize(panelW - 36, 100)
    f.itemScroll:SetScrollChild(f.itemList)
    f.itemRows = {}

    f.itemEmpty = f.itemList:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.itemEmpty:SetPoint("CENTER", f.itemList, "CENTER", 0, 0)
    f.itemEmpty:SetText("No Mythic items equipped. Equip a Mythic drop and reopen.")
    f.itemEmpty:SetTextColor(unpack(UI.Nav.muted))
    f.itemEmpty:Hide()

    -- ── Bottom row: status + Refresh ──────────────────────────────────────
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 8)
    f.status:SetTextColor(unpack(UI.Color.textWarn))
    f.status:Hide()

    local refreshBtn = UI.MakeButton(f, "Refresh", {
        w = 100, h = 26,
        variant = "secondary",
        onClick = function()
            Send("mythic status")
            Send("mythic items")
            Send("lockout list")
            Send("astral tree")
        end,
    })
    refreshBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 6)

    -- ── Refresh logic ─────────────────────────────────────────────────────
    function f:_refresh()
        local n = #M.lockouts
        local m = #M.items

        if M.inMythic then
            self.statusVal:SetText("INSIDE")
            self.statusVal:SetTextColor(1.0, 0.84, 0.29)
        elseif M.armed then
            self.statusVal:SetText("ACTIVE")
            self.statusVal:SetTextColor(0.55, 1.00, 0.55)
        else
            self.statusVal:SetText("OFF")
            self.statusVal:SetTextColor(0.65, 0.65, 0.65)
        end
        self.tokenVal:SetText(FormatNumber(PA.prestigeTokens or 0))
        self.lockoutVal:SetText(tostring(n))

        -- lockouts
        self.lockoutHeader:SetText("MYTHIC LOCKOUTS (" .. n .. ")")
        for _, row in ipairs(self.lockoutRows) do row:Hide() end
        for i, l in ipairs(M.lockouts) do
            local row = self.lockoutRows[i]
            if not row then
                row = CreateFrame("Frame", nil, self.lockoutList)
                row:SetPoint("LEFT",  self.lockoutList, "LEFT",   2, 0)
                row:SetPoint("RIGHT", self.lockoutList, "RIGHT", -2, 0)
                row:SetHeight(22)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
                row.text:SetJustifyH("LEFT")
                row.timeLeft = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.timeLeft:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row.timeLeft:SetJustifyH("RIGHT")
                row.timeLeft:SetTextColor(unpack(PA.UI.Nav.muted))
                self.lockoutRows[i] = row
            end
            row:SetPoint("TOP", self.lockoutList, "TOP", 0, -((i - 1) * 22))
            if i % 2 == 0 then
                row.bg:SetVertexColor(PA.UI.Nav.row[1], PA.UI.Nav.row[2],
                                      PA.UI.Nav.row[3], 0.45)
            else
                row.bg:SetVertexColor(0, 0, 0, 0)
            end
            row.text:SetText(l.mapName .. "  |cffb89aff[" .. l.diffName .. "]|r")
            row.timeLeft:SetText(FormatRelative(l.resetTime))
            row:Show()
        end
        if n > 0 then self.lockoutEmpty:Hide() else self.lockoutEmpty:Show() end

        -- items
        self.itemHeader:SetText("MYTHIC ITEM UPGRADES (" .. m .. ")")
        for _, row in ipairs(self.itemRows) do row:Hide() end
        local tokens = PA.prestigeTokens or 0
        local rowW = self.itemList:GetWidth()
        if not rowW or rowW < 100 then rowW = panelW - 36 end
        for i, it in ipairs(M.items) do
            local row = self.itemRows[i]
            if not row then
                row = CreateFrame("Frame", nil, self.itemList)
                row:SetSize(rowW, 28)
                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(22, 22)
                row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWidth(280)
                row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.cost:SetPoint("RIGHT", row, "RIGHT", -114, 0)
                row.cost:SetJustifyH("RIGHT")
                row.btn = PA.UI.MakeButton(row, "Upgrade", { w = 100, h = 22, variant = "gold" })
                row.btn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
                self.itemRows[i] = row
            end
            row:SetPoint("TOPLEFT", self.itemList, "TOPLEFT", 0, -((i - 1) * 30))
            if i % 2 == 0 then
                row.bg:SetVertexColor(PA.UI.Nav.row[1], PA.UI.Nav.row[2],
                                      PA.UI.Nav.row[3], 0.4)
            else
                row.bg:SetVertexColor(0, 0, 0, 0)
            end

            local link = select(2, GetItemInfo(it.entry))
            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(it.entry)
            row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(string.format("%s — %s  |cffaf80df+%d / +%d|r",
                SlotName(it.slot), link or ("Item " .. it.entry), it.level, it.max))

            local atMax = (it.level >= it.max) or (it.nextEntry == 0)
            if atMax then
                row.cost:SetText("|cff80e090max|r")
                row.btn:SetLabel("Maxed")
                row.btn:SetDisabledLook(true)
            else
                local affordable = (it.cost <= tokens)
                row.cost:SetText((affordable and "|cffffd700" or "|cffff6060")
                    .. FormatNumber(it.cost) .. " tokens|r")
                row.btn:SetLabel("Upgrade")
                row.btn:SetScript("OnClick", function()
                    -- preview window's Upgrade btn does the actual send
                    OpenItemUpgradeWindow(it)
                end)
                row.btn:SetDisabledLook(not affordable)
            end
            row:Show()
        end
        if m > 0 then self.itemEmpty:Hide() else self.itemEmpty:Show() end

        -- min height keeps empty-state text centred
        local minH = self.itemScroll:GetHeight()
        local rowsH = math.max(m * 30 + 4, minH or 100)
        self.itemList:SetHeight(rowsH)

        if M.statusUntil and time() < M.statusUntil then
            self.status:SetText(M.statusText)
            self.status:Show()
        else
            self.status:Hide()
        end
    end

    f:SetScript("OnShow", function(self)
        Send("mythic status")
        Send("mythic items")
        Send("lockout list")
        Send("astral tree")
        self:_refresh()
    end)

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t > 1.0 then
            self._t = 0
            if M.statusUntil and time() >= M.statusUntil and self.status:IsShown() then
                self.status:Hide()
            end
        end
    end)

    -- module-scope ref; handlers check frame:IsShown() to skip work
    frame = f
end

-- ── Module toggle ────────────────────────────────────────────────────────────

local function ToggleFrame()
    if not PA.mainFrame then return end
    if PA.mainFrame:IsShown()
       and PA.mainFrame._activeTabId == "Mythic" then
        PA.mainFrame:Hide()
    else
        PA.mainFrame:Show()
        PA.mainFrame:SwitchTab("Mythic")
        if PA.mainFrame._tabBar then
            PA.mainFrame._tabBar:SelectTab("Mythic")
        end
    end
end

-- ── Suppress FX| spam from chat ──────────────────────────────────────────────

local function HookSuppression()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if msg and msg:sub(1, 3) == "FX|" then return true end
        return false
    end)
end

-- ── GameTooltip overlay ────────────────────────────────────────────────────
-- "Mythic +N of M" line under item name. Cache primed by FX|MYINFO.

local function MythicTooltipDecorator(self)
    local _, link = self:GetItem()
    if not link then return end
    local entry = tonumber(link:match("item:(%d+)"))
    if not entry then return end
    local info = M.itemInfoByEntry[entry]
    if not info then return end
    -- avoid double-add on tooltip refresh (e.g. socket changes)
    local needle = "Mythic +" .. info.level .. " of " .. info.max
    for i = 1, self:NumLines() do
        local fs = _G[self:GetName() .. "TextLeft" .. i]
        if fs and fs:GetText() and fs:GetText():find(needle, 1, true) then
            return
        end
    end
    self:AddLine("|cffd070ff" .. needle .. "|r")
    self:Show()
end

local function HookTooltips()
    GameTooltip:HookScript("OnTooltipSetItem",      MythicTooltipDecorator)
    ItemRefTooltip:HookScript("OnTooltipSetItem",   MythicTooltipDecorator)
    if ShoppingTooltip1 then
        ShoppingTooltip1:HookScript("OnTooltipSetItem", MythicTooltipDecorator)
    end
    if ShoppingTooltip2 then
        ShoppingTooltip2:HookScript("OnTooltipSetItem", MythicTooltipDecorator)
    end
end

-- BAG_UPDATE_DELAYED storms on loot; coalesce sends to one per 3s
local lastBagFetch = 0
local function MaybeFetchItems()
    local now = time()
    if now - lastBagFetch < 3 then return end
    lastBagFetch = now
    Send("mythic items")
end

-- ── Mythic-bag right-click intercept ───────────────────────────────────────
-- Bags use Colossal-Bag-of-Loot pattern (Flags=32772). Role picker opens
-- locally via UseContainerItem post-hook; LOOT_OPENED closes the empty loot.

local lastClickedBagEntry = 0   -- set by UseContainerItem, consumed by LOOT_OPENED

local function ExtractItemEntry(link)
    if not link then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- entry range for Mythic bags (toolkit reserves 200001+)
-- range check lets the picker work on cold sessions before FX|MYBAG arrives
local MYTHIC_BAG_ENTRY_FLOOR = 200001
local MYTHIC_BAG_ENTRY_TOP   = 299999

local function HookBagOpen()
    -- server validates the entry in `.mythic openbag`, so range check is fine
    hooksecurefunc("UseContainerItem", function(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        local entry = ExtractItemEntry(link)
        if not entry then return end
        if entry < MYTHIC_BAG_ENTRY_FLOOR or entry > MYTHIC_BAG_ENTRY_TOP then
            return
        end
        lastClickedBagEntry = entry
        local info     = M.knownBags[entry]
        local mapId    = info and info.mapId   or 0
        local bagName  = info and info.bagName or ("Mythic Bag #" .. entry)
        OpenBagRolePicker(entry, mapId, bagName)
    end)
end

-- ── Bootstrap ────────────────────────────────────────────────────────────────

local evt = CreateFrame("Frame")
evt:RegisterEvent("CHAT_MSG_SYSTEM")
evt:RegisterEvent("PLAYER_LOGIN")
evt:RegisterEvent("PLAYER_ENTERING_WORLD")
evt:RegisterEvent("PLAYER_LEAVING_WORLD")
evt:RegisterEvent("BAG_UPDATE_DELAYED")
evt:RegisterEvent("LOOT_OPENED")
evt:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_LOGIN" then
        HookSuppression()
        HookTooltips()
        HookBagOpen()
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        -- prime MYINFO + MYBAG caches
        MaybeFetchItems()
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        MaybeFetchItems()
        return
    end
    if event == "LOOT_OPENED" then
        -- placeholder row in item_loot_template keeps the bag alive until
        -- `.mythic openbag` destroys it server-side
        if lastClickedBagEntry > 0 then
            CloseLoot()
        end
        lastClickedBagEntry = 0
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        M.inMythic = false
        HideBanner()
        return
    end
    if event ~= "CHAT_MSG_SYSTEM" or not msg then return end

    if msg:sub(1, 3) == "FX|" then
        OnFXMessage(msg)
    elseif msg:sub(1, 3) == "LR|" then
        OnLRMessage(msg)
    elseif msg:sub(1, 19) == "AT|PRESTIGE_TOKENS|" then
        local n = tonumber(msg:sub(20))
        if n then
            PA.prestigeTokens = n
            if frame    and frame:IsShown()    then frame:_refresh()         end
            if upgradeF and upgradeF:IsShown() then UpdateItemUpgradeWindow() end
        end
    end
end)

PA:RegisterModule("Mythic", "Mythic Raid", ToggleFrame, {
    subtitle = "Activate Mythic mode, view weekly lockouts, and upgrade Mythic gear.",
})
PA:RegisterTabContent("Mythic", BuildMythicTab)

-- exposed for MainMenu
PA.Mythic = M
