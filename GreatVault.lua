
local PA = ProjectAstral
if not PA then return end

local floor, max, pi, sin = math.floor, math.max, math.pi, math.sin

local ROOT = "Interface\\AddOns\\ProjectAstral\\textures\\vault\\"

local function ApplyTex(tex, info)
    tex:SetTexture(info.file)
    tex:SetTexCoord(0, info.u, 0, info.v)
end

local function NewTex(parent, layer, info)
    local t = parent:CreateTexture(nil, layer)
    ApplyTex(t, info)
    return t
end

local function NewFlipbook(tex, sheet, opts)
    opts = opts or {}
    local self = { tex = tex, sheet = sheet }
    self.total   = sheet.cols * sheet.rows
    self.step    = 1 / (opts.fps or 30)
    self.loop    = opts.loop
    self.frame   = 0
    self.elapsed = 0
    self.driver  = CreateFrame("Frame", nil, tex:GetParent())
    self.driver:Hide()

    local function setFrame(idx)
        local col = idx % sheet.cols
        local row = floor(idx / sheet.cols)
        local fw, size = sheet.frame, sheet.sheet
        tex:SetTexCoord(col * fw / size, (col + 1) * fw / size,
                        row * fw / size, (row + 1) * fw / size)
    end
    setFrame(0)

    self.driver:SetScript("OnUpdate", function(_, dt)
        self.elapsed = self.elapsed + dt
        while self.elapsed >= self.step do
            self.elapsed = self.elapsed - self.step
            self.frame = self.frame + 1
            if self.frame >= self.total then
                if not self.loop then
                    self.tex:Hide()
                    self.driver:Hide()
                    return
                end
                self.frame = 0
            end
            setFrame(self.frame)
        end
    end)

    function self:Play()
        self.frame = 0
        self.elapsed = 0
        setFrame(0)
        self.tex:Show()
        self.driver:Show()
    end
    function self:Stop()
        self.tex:Hide()
        self.driver:Hide()
    end
    return self
end

local function NewCrossfade(textures, opts)
    opts = opts or {}
    local self = {
        textures = textures,
        total    = #textures,
        cycle    = opts.cycle or 1.8,
        peak     = opts.peak or 1,
        time     = opts.offset or 0,
    }
    self.driver = CreateFrame("Frame", nil, textures[1]:GetParent())
    self.driver:Hide()
    self.driver:SetScript("OnUpdate", function(_, dt)
        self.time = self.time + dt
        local base = self.time / self.cycle
        for i = 1, self.total do
            local frac = (base - (i - 1) / self.total) % 1
            self.textures[i]:SetAlpha(sin(pi * frac) * self.peak)
        end
    end)
    function self:SetPlaying(on)
        if on then
            self.driver:Show()
        else
            self.driver:Hide()
            for i = 1, self.total do self.textures[i]:SetAlpha(0) end
        end
    end
    return self
end

local M = {
    bg           = { file = ROOT .. "bg",            u = 1.0,     v = 1.0     },
    crest        = { file = ROOT .. "crest",         u = 0.83594, v = 0.80469 },
    divider      = { file = ROOT .. "divider",       u = 1.0,     v = 1.0     },
    close        = { file = ROOT .. "close",         u = 0.75,    v = 0.75    },
    slotLocked   = { file = ROOT .. "slot_locked",   u = 0.57031, v = 0.65625 },
    slotUnlocked = { file = ROOT .. "slot_unlocked", u = 0.57031, v = 0.65234 },
    lock         = { file = ROOT .. "lock_gold",     u = 0.53906, v = 0.95312 },
    sparkle1     = { file = ROOT .. "sparkle1",      u = 0.50781, v = 0.52344 },
    sparkle2     = { file = ROOT .. "sparkle2",      u = 0.48438, v = 0.51562 },
    sparkle3     = { file = ROOT .. "sparkle3",      u = 0.48438, v = 0.53906 },
    flipbook     = { file = ROOT .. "flipbook",  cols = 6, rows = 4, frame = 152, sheet = 1024 },
    catRaid      = { file = ROOT .. "cat_raid",      u = 0.90234, v = 0.76562 },
    catDungeon   = { file = ROOT .. "cat_dungeon",   u = 0.90234, v = 0.75781 },
    catWorld     = { file = ROOT .. "cat_world",     u = 0.90234, v = 0.74609 },
}

-- Display only: the server pays from great_vault.conf (GreatVault.* keys, LIVE = DEV md5 49f4ad8a, 2026-10-01).
-- Keep these in step with it.
local WEEKLY_RBK_TIERS   = { { th = 10, tokens = 1250 }, { th = 20, tokens = 2500 }, { th = 30, tokens = 7500 } }
local WEEKLY_PREST_TIERS = { { th = 2,  tokens = 1250 }, { th = 5,  tokens = 2500 }, { th = 10, tokens = 7500 } }
local DAILY_RBK_THRESHOLD, DAILY_RBK_TOKENS = 10, 1000
local DAILY_LFG_THRESHOLD, DAILY_LFG_TOKENS =  5, 1000
local DAILY_LOGIN_TOKENS = 125

-- Weekly rewards pay last week's progress after the weekly reset; daily ones can be claimed as soon as they are done.
local WEEKLY_NOTE = "Claim after the weekly reset"
local DAILY_NOTE  = "Claim anytime before the daily reset"

local WIN_W, WIN_H = 1000, 570
local PAD          = 24
local ART_W, ART_H = 220, 100
local SLOT_W, SLOT_H = 206, 112
local SLOT_GAP, ART_GAP, ROW_GAP = 16, 20, 14
local ROW_W = ART_W + ART_GAP + 3 * SLOT_W + 2 * SLOT_GAP

local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }

local State = {
    dailyResetTs   = 0,   weeklyResetTs  = 0,
    cur_rbk_w   = 0,      clm_rbk_w   = 0,
    cur_prest_w = 0,      clm_prest_w = 0,
    cur_rbk_d   = 0,      clm_rbk_d   = 0,
    cur_lfg_d   = 0,      clm_lfg_d   = 0,
    cur_login_d = 0,      clm_login_d = 0,
    received       = false,
    claimedSet     = {},
    anchorMap   = nil,
    anchorX     = 0,
    anchorY     = 0,
}
local RANGE_CLOSE_NORM = 0.012

local WEEKLY_KEYS = { "weekly_rbk", "weekly_prest" }
local DAILY_KEYS  = { "daily_rbk", "daily_lfg", "daily_login" }

local function EnsureVaultSV()
    if type(ProjectAstralVault) ~= "table" then
        ProjectAstralVault = { dailyResetTs = 0, weeklyResetTs = 0, claimed = {} }
    end
    if type(ProjectAstralVault.claimed) ~= "table" then
        ProjectAstralVault.claimed = {}
    end
end

local function RolloverIfStale()
    EnsureVaultSV()
    if State.dailyResetTs ~= (ProjectAstralVault.dailyResetTs or 0) then
        for _, k in ipairs(DAILY_KEYS) do ProjectAstralVault.claimed[k] = nil end
        ProjectAstralVault.dailyResetTs = State.dailyResetTs
    end
    if State.weeklyResetTs ~= (ProjectAstralVault.weeklyResetTs or 0) then
        for _, k in ipairs(WEEKLY_KEYS) do ProjectAstralVault.claimed[k] = nil end
        ProjectAstralVault.weeklyResetTs = State.weeklyResetTs
    end
end

local function IsClaimed(slotDef)
    if slotDef.period == "daily" then
        return (slotDef.getClm() or 0) == 1
    end
    EnsureVaultSV()
    return ProjectAstralVault.claimed[slotDef.claimKey] == true
end

local function fmtWeeklyDesc(count, tokens)
    return ("Kill %d raid bosses = %d Tokens"):format(count, tokens)
end
local function fmtPrestigeDesc(count, tokens)
    return ("Complete %d Prestiges = %d Tokens"):format(count, tokens)
end

local ROWS = {
    {
        art       = M.catRaid,
        claimKey  = "weekly_rbk",
        slots     = {
            {
                desc     = fmtWeeklyDesc(WEEKLY_RBK_TIERS[1].th, WEEKLY_RBK_TIERS[1].tokens),
                max      = WEEKLY_RBK_TIERS[1].th,
                tokens   = WEEKLY_RBK_TIERS[1].tokens,
                getCur   = function() return State.cur_rbk_w end,
                getClm   = function() return State.clm_rbk_w end,
                unlocked = function() return State.clm_rbk_w >= WEEKLY_RBK_TIERS[1].th end,
                claimKey = "weekly_rbk",
                period   = "weekly",
            },
            {
                desc     = fmtWeeklyDesc(WEEKLY_RBK_TIERS[2].th, WEEKLY_RBK_TIERS[2].tokens),
                max      = WEEKLY_RBK_TIERS[2].th,
                tokens   = WEEKLY_RBK_TIERS[2].tokens,
                getCur   = function() return State.cur_rbk_w end,
                getClm   = function() return State.clm_rbk_w end,
                unlocked = function() return State.clm_rbk_w >= WEEKLY_RBK_TIERS[2].th end,
                claimKey = "weekly_rbk",
                period   = "weekly",
            },
            {
                desc     = fmtWeeklyDesc(WEEKLY_RBK_TIERS[3].th, WEEKLY_RBK_TIERS[3].tokens),
                max      = WEEKLY_RBK_TIERS[3].th,
                tokens   = WEEKLY_RBK_TIERS[3].tokens,
                getCur   = function() return State.cur_rbk_w end,
                getClm   = function() return State.clm_rbk_w end,
                unlocked = function() return State.clm_rbk_w >= WEEKLY_RBK_TIERS[3].th end,
                claimKey = "weekly_rbk",
                period   = "weekly",
            },
        },
    },
    {
        art       = M.catDungeon,
        claimKey  = "weekly_prest",
        slots     = {
            {
                desc     = fmtPrestigeDesc(WEEKLY_PREST_TIERS[1].th, WEEKLY_PREST_TIERS[1].tokens),
                max      = WEEKLY_PREST_TIERS[1].th,
                tokens   = WEEKLY_PREST_TIERS[1].tokens,
                getCur   = function() return State.cur_prest_w end,
                getClm   = function() return State.clm_prest_w end,
                unlocked = function() return State.clm_prest_w >= WEEKLY_PREST_TIERS[1].th end,
                claimKey = "weekly_prest",
                period   = "weekly",
            },
            {
                desc     = fmtPrestigeDesc(WEEKLY_PREST_TIERS[2].th, WEEKLY_PREST_TIERS[2].tokens),
                max      = WEEKLY_PREST_TIERS[2].th,
                tokens   = WEEKLY_PREST_TIERS[2].tokens,
                getCur   = function() return State.cur_prest_w end,
                getClm   = function() return State.clm_prest_w end,
                unlocked = function() return State.clm_prest_w >= WEEKLY_PREST_TIERS[2].th end,
                claimKey = "weekly_prest",
                period   = "weekly",
            },
            {
                desc     = fmtPrestigeDesc(WEEKLY_PREST_TIERS[3].th, WEEKLY_PREST_TIERS[3].tokens),
                max      = WEEKLY_PREST_TIERS[3].th,
                tokens   = WEEKLY_PREST_TIERS[3].tokens,
                getCur   = function() return State.cur_prest_w end,
                getClm   = function() return State.clm_prest_w end,
                unlocked = function() return State.clm_prest_w >= WEEKLY_PREST_TIERS[3].th end,
                claimKey = "weekly_prest",
                period   = "weekly",
            },
        },
    },
    {
        art       = M.catWorld,
        slots     = {
            {
                desc     = ("Kill %d raid bosses today = %d Tokens"):format(DAILY_RBK_THRESHOLD, DAILY_RBK_TOKENS),
                max      = DAILY_RBK_THRESHOLD,
                tokens   = DAILY_RBK_TOKENS,
                getCur   = function() return State.cur_rbk_d end,
                getClm   = function() return State.clm_rbk_d end,
                unlocked = function()
                    return State.cur_rbk_d >= DAILY_RBK_THRESHOLD
                       and (State.clm_rbk_d or 0) == 0
                end,
                claimKey = "daily_rbk",
                period   = "daily",
            },
            {
                desc     = ("Clear %d LFG dungeons today = %d Tokens"):format(DAILY_LFG_THRESHOLD, DAILY_LFG_TOKENS),
                max      = DAILY_LFG_THRESHOLD,
                tokens   = DAILY_LFG_TOKENS,
                getCur   = function() return State.cur_lfg_d end,
                getClm   = function() return State.clm_lfg_d end,
                unlocked = function()
                    return State.cur_lfg_d >= DAILY_LFG_THRESHOLD
                       and (State.clm_lfg_d or 0) == 0
                end,
                claimKey = "daily_lfg",
                period   = "daily",
            },
            {
                desc     = ("Log in today = %d Tokens"):format(DAILY_LOGIN_TOKENS),
                max      = 1,
                tokens   = DAILY_LOGIN_TOKENS,
                getCur   = function() return State.cur_login_d end,
                getClm   = function() return State.clm_login_d end,
                unlocked = function()
                    return State.cur_login_d > 0
                       and (State.clm_login_d or 0) == 0
                end,
                claimKey = "daily_login",
                period   = "daily",
            },
        },
    },
}

local slotFrames = {}
local stagger    = 0

local function makeSlot(parent, slotDef)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(SLOT_W, SLOT_H)

    local panel = NewTex(f, "BACKGROUND", M.slotLocked)
    panel:SetAllPoints(f)

    local lock = NewTex(f, "ARTWORK", M.lock)
    lock:SetSize(92, 81)
    lock:SetPoint("LEFT", f, "LEFT", 12, -16)

    local sparkleTex = {}
    for i, info in ipairs({ M.sparkle1, M.sparkle2, M.sparkle3 }) do
        local s = NewTex(f, "ARTWORK", info)
        s:SetDrawLayer("ARTWORK", 3)
        s:SetBlendMode("ADD")
        s:SetSize(120, 112)
        s:SetPoint("CENTER", lock, "CENTER", 0, 0)
        s:SetAlpha(0)
        sparkleTex[i] = s
    end
    stagger = stagger + 0.4
    local sparkle = NewCrossfade(sparkleTex, { cycle = 1.8, peak = 0.9, offset = stagger })

    local burst = f:CreateTexture(nil, "OVERLAY")
    burst:SetDrawLayer("OVERLAY", 4)
    burst:SetBlendMode("ADD")
    burst:SetAllPoints(f)
    burst:SetTexture(M.flipbook.file)
    burst:Hide()
    local lightning = NewFlipbook(burst, M.flipbook, { fps = 30 })

    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    desc:SetWidth(SLOT_W - 24)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetText(slotDef.desc)

    local count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 9)
    count:SetTextColor(0.9, 0.9, 0.9)

    -- right of the 92 px lock art, between the description and the counter
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -42)
    note:SetWidth(SLOT_W - 12 - 92 - 4 - 12)
    note:SetJustifyH("RIGHT")
    note:SetJustifyV("TOP")
    note:SetText(slotDef.period == "weekly" and WEEKLY_NOTE or DAILY_NOTE)

    f:SetScript("OnClick", function()
        if slotDef.unlocked() and not State.claimedSet[slotDef.claimKey] then
            lightning:Play()
            if _G.AIO and _G.AIO.Handle then
                _G.AIO.Handle("AstralGreatVaultServer", "Claim", slotDef.claimKey)
            end
        end
    end)

    function f:Refresh()
        local claimed   = IsClaimed(slotDef)
        local claimable = slotDef.unlocked() and not claimed
        local liveCount = slotDef.getCur() or 0
        local shown = liveCount > slotDef.max and slotDef.max or liveCount
        count:SetText(shown .. "/" .. slotDef.max)

        ApplyTex(panel, M.slotUnlocked)
        lock:Show()

        if claimed then
            panel:SetVertexColor(0.45, 0.45, 0.45, 1)
            lock:SetVertexColor (0.45, 0.45, 0.45, 1)
            desc:SetTextColor(0.55, 0.50, 0.40)
            count:SetTextColor(0.55, 0.55, 0.55)
            note:SetTextColor(0.45, 0.45, 0.45)
        else
            panel:SetVertexColor(1, 1, 1, 1)
            lock:SetVertexColor (1, 1, 1, 1)
            desc:SetTextColor(unpack(GOLD))
            count:SetTextColor(0.9, 0.9, 0.9)
            note:SetTextColor(0.78, 0.76, 0.70)
        end

        sparkle:SetPlaying(claimable)
    end
    f:Refresh()

    slotFrames[#slotFrames + 1] = f
    return f
end

local function makeRow(parent, rowDef)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_W, max(ART_H, SLOT_H))

    local art = NewTex(row, "ARTWORK", rowDef.art)
    art:SetSize(ART_W, ART_H)
    art:SetPoint("LEFT", row, "LEFT", 0, 0)

    for i, slotDef in ipairs(rowDef.slots) do
        local s = makeSlot(row, slotDef)
        s:SetPoint("LEFT", row, "LEFT",
                   ART_W + ART_GAP + (i - 1) * (SLOT_W + SLOT_GAP), 0)
    end
    return row
end

local function formatTime(sec)
    sec = max(0, floor(sec))
    local d = floor(sec / 86400); sec = sec % 86400
    local h = floor(sec / 3600);  sec = sec % 3600
    local m = floor(sec / 60)
    if d > 0 then
        return string.format("%dd %dh %dm %ds", d, h, m, sec % 60)
    end
    return string.format("%dh %dm %ds", h, m, sec % 60)
end

local vaultFrame

local function Build()
    if vaultFrame then return end

    local f = CreateFrame("Frame", "ProjectAstralGreatVault", UIParent)
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "ProjectAstralGreatVault")

    local bg = NewTex(f, "BACKGROUND", M.bg)
    bg:SetAllPoints(f)

    local border = CreateFrame("Frame", nil, f)
    border:SetAllPoints(f)
    border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16 })
    PA.UI.CosmicCorners(border)
    border:SetBackdropBorderColor(PA.UI.Tint(0.165, 0.204, 0.400, 0.9))

    local crestHolder = CreateFrame("Frame", nil, f)
    crestHolder:SetAllPoints(f)
    crestHolder:SetFrameLevel(border:GetFrameLevel() + 5)
    local crest = NewTex(crestHolder, "OVERLAY", M.crest)
    crest:SetSize(140, 67)
    crest:SetPoint("CENTER", f, "TOP", 0, -14)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -10)
    local closeTex = NewTex(close, "ARTWORK", M.close)
    closeTex:SetAllPoints(close)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() closeTex:SetVertexColor(1, 0.7, 0.7) end)
    close:SetScript("OnLeave", function() closeTex:SetVertexColor(1, 1, 1) end)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", crest, "BOTTOM", 0, -6)
    subtitle:SetWidth(WIN_W - 180)
    subtitle:SetJustifyH("CENTER")
    subtitle:SetText("Finish activities, kill bosses, prestige and clear dungeons to unlock rewards in the vault")
    subtitle:SetTextColor(0.88, 0.86, 0.8)

    local headDivider = NewTex(f, "ARTWORK", M.divider)
    headDivider:SetSize(WIN_W - 2 * PAD, 14)
    headDivider:SetPoint("TOP", subtitle, "BOTTOM", 0, -8)

    local startY  = -116
    local xOffset = (WIN_W - 2 * PAD - ROW_W) / 2
    for i, rowDef in ipairs(ROWS) do
        local row = makeRow(f, rowDef)
        row:SetPoint("TOPLEFT", f, "TOPLEFT",
                     PAD + xOffset,
                     startY - (i - 1) * (SLOT_H + ROW_GAP))
    end

    local footDivider = NewTex(f, "ARTWORK", M.divider)
    footDivider:SetSize(WIN_W - 2 * PAD, 14)
    footDivider:SetPoint("BOTTOM", f, "BOTTOM", 0, 44)

    local dailyText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dailyText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 6, 22)
    dailyText:SetTextColor(0.85, 0.83, 0.78)

    local weeklyText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weeklyText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 6, 22)
    weeklyText:SetTextColor(0.85, 0.83, 0.78)

    local proxAcc, timerAcc = 0, 0
    f:SetScript("OnUpdate", function(_, dt)
        proxAcc  = proxAcc  + dt
        timerAcc = timerAcc + dt

        if proxAcc >= 0.5 then
            proxAcc = 0
            if State.anchorMap then
                SetMapToCurrentZone()
                local px, py = GetPlayerMapPosition("player")
                local mapNow = GetCurrentMapAreaID()
                if mapNow ~= State.anchorMap then
                    f:Hide()
                    return
                end
                if px and py and px > 0 and py > 0 then
                    local dx = px - State.anchorX
                    local dy = py - State.anchorY
                    if dx * dx + dy * dy
                       > RANGE_CLOSE_NORM * RANGE_CLOSE_NORM then
                        f:Hide()
                        return
                    end
                end
            end
        end

        if timerAcc >= 1 then
            timerAcc = 0
            if not State.received then
                dailyText:SetText("Daily resets in --")
                weeklyText:SetText("Weekly resets in --")
                return
            end
            local now = time()
            dailyText:SetText("Daily resets in "  .. formatTime(State.dailyResetTs  - now))
            weeklyText:SetText("Weekly resets in " .. formatTime(State.weeklyResetTs - now))
        end
    end)

    if PA and PA.UI and PA.UI.MakeLoadingOverlay then
        f.loadingOverlay = PA.UI.MakeLoadingOverlay(f,
            { text = "Loading vault" .. string.char(0xE2, 0x80, 0xA6) })
    end

    f:Hide()
    vaultFrame = f
end

local function Refresh()
    if not vaultFrame then return end
    for _, s in ipairs(slotFrames) do s:Refresh() end
end

local function ApplyState(payload)
    if type(payload) ~= "table" then return end
    State.dailyResetTs  = tonumber(payload.dailyResetTs)  or 0
    State.weeklyResetTs = tonumber(payload.weeklyResetTs) or 0
    State.cur_rbk_w     = tonumber(payload.cur_rbk_w)     or 0
    State.clm_rbk_w     = tonumber(payload.clm_rbk_w)     or 0
    State.cur_prest_w   = tonumber(payload.cur_prest_w)   or 0
    State.clm_prest_w   = tonumber(payload.clm_prest_w)   or 0
    State.cur_rbk_d     = tonumber(payload.cur_rbk_d)     or 0
    State.clm_rbk_d     = tonumber(payload.clm_rbk_d)     or 0
    State.cur_lfg_d     = tonumber(payload.cur_lfg_d)     or 0
    State.clm_lfg_d     = tonumber(payload.clm_lfg_d)     or 0
    State.cur_login_d   = tonumber(payload.cur_login_d)   or 0
    State.clm_login_d   = tonumber(payload.clm_login_d)   or 0
    State.received      = true
    State.claimedSet    = {}    -- unused now but kept for API compat
    RolloverIfStale()

    Build()
    Refresh()
    SetMapToCurrentZone()
    local px, py = GetPlayerMapPosition("player")
    if px and py and px > 0 and py > 0 then
        State.anchorMap = GetCurrentMapAreaID()
        State.anchorX   = px
        State.anchorY   = py
    else
        State.anchorMap = nil
    end
    if vaultFrame then
        vaultFrame:Show()
        if vaultFrame.loadingOverlay then vaultFrame.loadingOverlay:Show() end
    end
end

local pendingClaims = {}   -- [track] = pre-claim state snapshot

local function SnapshotForTrack(track)
    if     track == "weekly_rbk"   then return State.clm_rbk_w
    elseif track == "weekly_prest" then return State.clm_prest_w
    elseif track == "daily_rbk"    then return State.clm_rbk_d
    elseif track == "daily_lfg"    then return State.clm_lfg_d
    elseif track == "daily_login"  then return State.clm_login_d
    end
    return 0
end

local function TokensForClaim(track, preValue)
    if track == "weekly_rbk" then
        local hit = 0
        for _, t in ipairs(WEEKLY_RBK_TIERS) do if preValue >= t.th then hit = t.tokens end end
        return hit
    elseif track == "weekly_prest" then
        local hit = 0
        for _, t in ipairs(WEEKLY_PREST_TIERS) do if preValue >= t.th then hit = t.tokens end end
        return hit
    elseif track == "daily_rbk"   then return DAILY_RBK_TOKENS
    elseif track == "daily_lfg"   then return DAILY_LFG_TOKENS
    elseif track == "daily_login" then return DAILY_LOGIN_TOKENS
    end
    return 0
end

local function SchedulePollAfterClaim(track, expectedTokens)
    local t = 0
    local frame = CreateFrame("Frame")
    frame:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        if t < 0.4 then return end
        self:SetScript("OnUpdate", nil)
        if _G.AIO and _G.AIO.Handle then
            _G.AIO.Handle("AstralGreatVaultServer", "RequestState")
        end
        pendingClaims[track] = { expected = expectedTokens }
    end)
end

local function OnClaimExec(track)
    local pre = SnapshotForTrack(track)
    local expected = TokensForClaim(track, pre)
    -- overwrite if by some race the mutation failed.
    if     track == "weekly_rbk"   then State.clm_rbk_w   = 0
    elseif track == "weekly_prest" then State.clm_prest_w = 0
    elseif track == "daily_rbk"    then State.clm_rbk_d   = 1
    elseif track == "daily_lfg"    then State.clm_lfg_d   = 1
    elseif track == "daily_login"  then State.clm_login_d = 1
    end
    EnsureVaultSV()
    ProjectAstralVault.claimed[track] = true
    State.claimedSet[track] = true
    Refresh()

    SendChatMessage(".greatvault claim " .. track, "SAY")
    UIErrorsFrame:AddMessage("Claimed " .. expected .. " Tokens",
        0.55, 1.0, 0.55, 1.0)
    SchedulePollAfterClaim(track, expected)
end

local function RegisterGreatVaultHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralGreatVault", {})

    ClientHandler.State = function(_, payload)
        ApplyState(payload)
        for track, _ in pairs(pendingClaims) do
            pendingClaims[track] = nil
        end
        if vaultFrame and vaultFrame.loadingOverlay then
            vaultFrame.loadingOverlay:Hide()
        end
    end

    ClientHandler.Result = function(_, kind, track)
        if kind == "exec" then
            OnClaimExec(track)
        elseif kind == "empty" then
            UIErrorsFrame:AddMessage("Nothing to claim there.",
                1.0, 0.80, 0.30, 1.0)
        elseif kind == "disabled" then
            UIErrorsFrame:AddMessage("Great Vault is disabled by the server.",
                1.0, 0.42, 0.42, 1.0)
        end
    end

    return true
end

-- CommandScript is silent post-Phase-5 but the client's own SAY echo
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    return msg:sub(1, 11) == ".greatvault" and author == UnitName("player")
end)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    if RegisterGreatVaultHandlers() then
        self:UnregisterAllEvents()
    end
end)

