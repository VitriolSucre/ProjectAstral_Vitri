
local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral
if not PA then return end
local UI = PA.UI

local FRAME_W, FRAME_H = 560, 620
local PR_MAX_MOVE_SQR  = 0.0002
local WATCHDOG_TICK    = 0.4

local COL_GAIN   = "|cff33ff66"
local COL_KEEP   = "|cff33ccff"
local COL_LOSE   = "|cffff6b6b"
local COL_MUTED  = "|cff888888"
local COL_TOKEN  = "|cffffcc00"

local TIER_COLOR = {
    [0]  = {0.55, 0.55, 0.60},
    [1]  = {0.70, 0.70, 0.70},
    [3]  = {0.40, 0.80, 0.40},
    [5]  = {0.30, 0.60, 1.00},
    [8]  = {0.72, 0.35, 0.90},
    [10] = {1.00, 0.60, 0.20},
    [15] = {0.95, 0.20, 0.20},
}
local function GetTierColor(lvl)
    local best = TIER_COLOR[0]
    for k, c in pairs(TIER_COLOR) do
        if lvl >= k then best = c end
    end
    return best
end
local function TierHex(lvl)
    local c = GetTierColor(lvl)
    return ("ff%02x%02x%02x"):format(c[1]*255, c[2]*255, c[3]*255)
end

local frame
local statusLevelText, statusOrbsText, statusEligText
local previewText
local rewardsGrid
local prestigeBtn, refreshBtn, closeBtn
local lastConfirmText = "This resets your character to level 1. Are you sure?"

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
    if GetCurrentMapAreaID() ~= self.openMap then
        frame:Hide(); return
    end
    local x, y = GetPlayerMapPosition("player")
    if x == 0 and y == 0 then return end
    local dx, dy = x - self.openX, y - self.openY
    if (dx*dx + dy*dy) > PR_MAX_MOVE_SQR then
        frame:Hide()
    end
end)

gate:RegisterEvent("PLAYER_ENTERING_WORLD")
gate:RegisterEvent("PLAYER_DEAD")
gate:RegisterEvent("TAXIMAP_OPENED")
gate:SetScript("OnEvent", function()
    if frame and frame:IsShown() then frame:Hide() end
end)

StaticPopupDialogs["ASTRAL_PRESTIGE_CONFIRM"] = {
    text = "%s",
    button1 = "Yes — Prestige!",
    button2 = "Cancel",
    OnAccept = function()
        AIO.Handle("AstralPrestigeServer", "Execute")
    end,
    timeout = 0,
    whileDead = 0,
    hideOnEscape = 1,
    preferredIndex = 3,
}

local function MakeSubPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    if UI.AstralBackdrop then
        UI.AstralBackdrop(p, { thin = true,
                               bg = UI.Nav.panel,
                               border = UI.Nav.edge })
    end
    return p
end

local function BuildFrame()
    if frame then return frame end
    if not UI then return end

    frame = UI.MakePanel(UIParent, FRAME_W, FRAME_H, {
        name    = "PA_PrestigeFrame",
        movable = true,   -- MakePanel checks `movable`, not `draggable`
    })
    frame.__paUnified = true   -- unified look: Theme.lua keeps its navy
    if UI.FlatBackdrop then UI.FlatBackdrop(frame) end   -- no grey window border
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    tinsert(UISpecialFrames, "PA_PrestigeFrame")

    UI.MakeHeader(frame, "|cffff8000Chromie|r's Time-Travel",
                         "Prestige — reset to level 1 and gain Orbs of Destiny")

    local statusPanel = MakeSubPanel(frame)
    statusPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -70)
    statusPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -70)
    statusPanel:SetHeight(80)

    local plLabel = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plLabel:SetPoint("TOPLEFT", statusPanel, "TOPLEFT", 14, -10)
    plLabel:SetText("Current Prestige Level")
    plLabel:SetTextColor(0.7, 0.7, 0.75)

    statusLevelText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusLevelText:SetPoint("TOPLEFT", plLabel, "BOTTOMLEFT", 0, -2)
    statusLevelText:SetText("0")

    local orbLabel = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    orbLabel:SetPoint("TOPRIGHT", statusPanel, "TOPRIGHT", -14, -10)
    orbLabel:SetText("Orbs of Destiny")
    orbLabel:SetTextColor(0.7, 0.7, 0.75)
    orbLabel:SetJustifyH("RIGHT")

    statusOrbsText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statusOrbsText:SetPoint("TOPRIGHT", orbLabel, "BOTTOMRIGHT", 0, -2)
    statusOrbsText:SetText(COL_KEEP .. "0|r")
    statusOrbsText:SetJustifyH("RIGHT")

    statusEligText = statusPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusEligText:SetPoint("BOTTOM", statusPanel, "BOTTOM", 0, 8)
    statusEligText:SetText(COL_MUTED .. "Checking eligibility...|r")

    local previewStrip = CreateFrame("Frame", nil, frame)
    previewStrip:SetPoint("TOPLEFT", statusPanel, "BOTTOMLEFT", 0, -14)
    previewStrip:SetPoint("TOPRIGHT", statusPanel, "BOTTOMRIGHT", 0, -14)
    previewStrip:SetHeight(32)

    previewText = previewStrip:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewText:SetPoint("CENTER", previewStrip, "CENTER", 0, 0)
    previewText:SetJustifyH("CENTER")
    previewText:SetText("")

    UI.MakeSectionDivider(frame, "Rewards Summary",
        { "TOPLEFT", previewStrip, "BOTTOMLEFT", 0, -8 })

    local colGap = 8
    local colW = math.floor((FRAME_W - 32 - colGap * 2) / 3)
    local colH = 220
    rewardsGrid = {}

    local defs = {
        { title = COL_GAIN .. "You Gain|r",  key = "gain" },
        { title = COL_KEEP .. "You Keep|r",  key = "keep" },
        { title = COL_LOSE .. "You Lose|r",  key = "lose" },
    }
    for i, def in ipairs(defs) do
        local col = MakeSubPanel(frame)
        col:SetSize(colW, colH)
        if i == 1 then
            col:SetPoint("TOPLEFT", previewStrip, "BOTTOMLEFT", 0, -30)
        else
            col:SetPoint("LEFT", rewardsGrid[i-1].panel, "RIGHT", colGap, 0)
        end

        local title = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", col, "TOP", 0, -10)
        title:SetText(def.title)
        title:SetJustifyH("CENTER")

        local body = col:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT",     col, "TOPLEFT",     10, -34)
        body:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -10, 8)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        body:SetSpacing(5)
        body:SetText("")

        rewardsGrid[i] = { panel = col, title = title, body = body, key = def.key }
    end

    prestigeBtn = UI.MakeButton(frame, "Prestige Now",
        { w = 200, h = 34, variant = "gold",
          onClick = function()
              StaticPopup_Show("ASTRAL_PRESTIGE_CONFIRM", lastConfirmText)
          end })
    prestigeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 20)

    refreshBtn = UI.MakeButton(frame, "Refresh",
        { w = 100, h = 34, variant = "secondary",
          onClick = function()
              AIO.Handle("AstralPrestigeServer", "Refresh")
          end })
    refreshBtn:SetPoint("LEFT", prestigeBtn, "RIGHT", 8, 0)

    closeBtn = UI.MakeButton(frame, "Close",
        { w = 100, h = 34, variant = "secondary",
          onClick = function() frame:Hide() end })
    closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 20)

    frame:HookScript("OnHide", function() gate:Hide() end)

    return frame
end

local function Bullet(text) return "  • " .. text end

local function BuildRewardsBody(status)
    local orbsPer = tonumber(status.orbsPer) or 0
    local tokens  = tonumber(status.tokens)  or 0
    local maxLvl  = tonumber(status.maxLvl)  or 0
    local nextPl  = (tonumber(status.pl) or 0) + 1
    local capNote = (maxLvl > 0 and nextPl > maxLvl) and
        (" " .. COL_MUTED .. "(cap reached)|r") or ""

    local gain = {
        Bullet(("%s+%d|r %sOrbs of Destiny|r"):format(COL_GAIN, orbsPer, COL_KEEP)),
        Bullet(("%s+%d|r %sTokens|r"):format(COL_GAIN, tokens,  COL_TOKEN)),
        Bullet(("%s+1|r Prestige Level%s"):format(COL_GAIN, capNote)),
        Bullet(COL_MUTED .. "Great Vault credit|r"),
        Bullet(COL_MUTED .. "Leaderboard credit|r"),
    }

    local keep = {}
    if status.keepMounts then keep[#keep+1] = Bullet("Mounts") end
    if status.keepProfs  then keep[#keep+1] = Bullet("Professions") end
    if status.keepRiding then keep[#keep+1] = Bullet("Riding Skill") end
    keep[#keep+1] = Bullet("Astral Gems")
    keep[#keep+1] = Bullet("Glyphs")
    keep[#keep+1] = Bullet("Achievements")
    if #keep == 0 then keep[1] = COL_MUTED .. "  (nothing preserved)|r" end

    local lose = {
        Bullet("Character Level"),
    }
    if status.mailOldGear then
        lose[#lose+1] = Bullet("Equipped gear " .. COL_KEEP .. ">> mail|r")
    else
        lose[#lose+1] = Bullet(COL_LOSE .. "Equipped gear (destroyed)|r")
    end
    if status.resetTalents then lose[#lose+1] = Bullet("Talents") end
    if status.resetSpells  then lose[#lose+1] = Bullet("Learned spells")     end
    if status.resetQuests  then lose[#lose+1] = Bullet("Quest progress")     end

    return {
        gain = table.concat(gain, "\n"),
        keep = table.concat(keep, "\n"),
        lose = table.concat(lose, "\n"),
    }
end

local function ApplyStatus(status)
    if not statusLevelText or not status then return end
    local pl      = tonumber(status.pl)      or 0
    local orbs    = tonumber(status.orbs)    or 0
    local orbsPer = tonumber(status.orbsPer) or 0
    local maxLvl  = tonumber(status.maxLvl)  or 0

    local levelStr = ("|c%s%d|r"):format(TierHex(pl), pl)
    if maxLvl > 0 then
        levelStr = levelStr .. ("  %s/ %d|r"):format(COL_MUTED, maxLvl)
    end
    statusLevelText:SetText(levelStr)
    statusOrbsText:SetText(("%s%d|r  %s(+%d each)|r"):format(COL_KEEP, orbs, COL_MUTED, orbsPer))

    if status.elig then
        statusEligText:SetText("|cff33ff66Ready to prestige|r")
        if prestigeBtn and prestigeBtn.SetDisabledLook then
            prestigeBtn:SetDisabledLook(false)
        end
    else
        local reason = (status.err ~= "" and status.err) or "Not eligible"
        statusEligText:SetText(COL_LOSE .. reason .. "|r")
        if prestigeBtn and prestigeBtn.SetDisabledLook then
            prestigeBtn:SetDisabledLook(true)
        end
    end

    local nextPl = pl + 1
    if maxLvl > 0 and pl >= maxLvl then
        nextPl = pl
    end
    previewText:SetText(("|c%sPrestige %d|r  %s>>|r  |c%sPrestige %d|r")
        :format(TierHex(pl), pl, COL_TOKEN, TierHex(nextPl), nextPl))

    local body = BuildRewardsBody(status)
    if rewardsGrid then
        for _, col in ipairs(rewardsGrid) do
            col.body:SetText(body[col.key] or "")
        end
    end

    if status.confirm and status.confirm ~= "" then
        lastConfirmText = status.confirm
    end
end

local ClientHandler = AIO.AddHandlers("AstralPrestige", {})

ClientHandler.Show = function(_, status)
    BuildFrame()
    if not frame then return end
    ApplyStatus(status)
    if not frame:IsShown() then
        frame:Show()
        GateAnchor()
        gate:Show()
    end
end

ClientHandler.Status = function(_, status)
    if not frame or not frame:IsShown() then return end
    ApplyStatus(status)
end

ClientHandler.Result = function(_, ok, msg)
    if ok then
        if msg == "GO" then
            SendChatMessage(".prestige exec", "SAY")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff66[Prestige]|r " .. tostring(msg))
            if frame then frame:Hide() end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff6b6b[Prestige]|r " .. tostring(msg))
        AIO.Handle("AstralPrestigeServer", "Refresh")
    end
end

SLASH_ASTRALPRESTIGE1 = "/prestige"
SlashCmdList["ASTRALPRESTIGE"] = function()
    BuildFrame()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        AIO.Handle("AstralPrestigeServer", "Refresh")
        frame:Show()
    end
end
