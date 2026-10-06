
local PA = ProjectAstral
if not PA then return end

local LR = {}
LR.lockouts    = {}
LR.resetCount  = 0
LR.nextCost    = 0
LR.statusText  = ""
LR.statusUntil = 0

PA.lockoutReset = LR

local frame
local ROW_H = 38

local function ShowLoading()
    if frame and frame.loadingOverlay then frame.loadingOverlay:Show() end
end

local function SendServer(method, ...)
    if _G.AIO and _G.AIO.Handle then
        _G.AIO.Handle("AstralLockoutResetServer", method, ...)
    end
end

local function NormalizeInstanceName(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function BlizzardResetSeconds(lockout)
    if not (GetNumSavedInstances and GetSavedInstanceInfo) then return nil end

    local wantedId = tonumber(lockout.instanceId or lockout.lockoutId or lockout.id)
    local wantedName = NormalizeInstanceName(lockout.mapName)
    local wantedDiff = NormalizeInstanceName(lockout.diffName)
    local wantedDiffNum = tonumber(lockout.difficulty)
    local nameMatch, nameMatchCount, sameReset = nil, 0, true

    for index = 1, GetNumSavedInstances() do
        local name, lockoutId, reset, difficulty, locked, _, _, _, _, difficultyName =
            GetSavedInstanceInfo(index)
        reset = tonumber(reset)
        if locked and reset and reset > 0 then
            if wantedId and tonumber(lockoutId) == wantedId then
                return reset
            end

            if NormalizeInstanceName(name) == wantedName then
                local savedDiff = NormalizeInstanceName(difficultyName)
                if wantedDiff ~= "" and savedDiff == wantedDiff then
                    return reset
                end
                -- GetSavedInstanceInfo's difficulty is 1-based (server difficulty + 1)
                if wantedDiffNum and tonumber(difficulty) == wantedDiffNum + 1 then
                    return reset
                end
                if nameMatch and math.abs(nameMatch - reset) > 60 then sameReset = false end
                nameMatch = nameMatch or reset
                nameMatchCount = nameMatchCount + 1
            end
        end
    end

    -- Several binds on one raid (Normal + Mythic MC) share its weekly reset.
    if nameMatchCount == 1 or (nameMatchCount > 1 and sameReset) then return nameMatch end
end

local function FormatRelative(lockout)
    local left = BlizzardResetSeconds(lockout)
    if left == nil then
        left = (tonumber(lockout.resetTime) or 0) - time()
    end
    if left <= 0 then return "expired" end
    local d = math.floor(left / 86400);  left = left - d * 86400
    local h = math.floor(left / 3600);   left = left - h * 3600
    local m = math.floor(left / 60)
    if d > 0 then return string.format("in %dd %dh", d, h) end
    if h > 0 then return string.format("in %dh %dm", h, m) end
    return string.format("in %dm", m)
end

-- server runs Etc/UTC — client must compute against UTC to match.
-- Friday 04:00 = AstralLockoutReset.WeeklyResetDay 5 / WeeklyResetHour 4, same as the raid reset.
local RESET_LUA_WDAY = 6   -- Fri (Sun=1)
local RESET_HOUR     = 4

local function SecondsUntilWeeklyReset()
    local now = time()
    local tU  = date("!*t", now)

    local daysUntil = (RESET_LUA_WDAY - tU.wday) % 7
    if daysUntil == 0 and (tU.hour > RESET_HOUR or (tU.hour == RESET_HOUR and (tU.min > 0 or tU.sec > 0))) then
        daysUntil = 7
    end
    local secsIntoDayUTC = tU.hour * 3600 + tU.min * 60 + tU.sec
    return daysUntil * 86400 + (RESET_HOUR * 3600 - secsIntoDayUTC)
end

local function FormatTimerDHM(secondsLeft)
    if secondsLeft <= 0 then return "now" end
    local d = math.floor(secondsLeft / 86400);  secondsLeft = secondsLeft - d * 86400
    local h = math.floor(secondsLeft / 3600);   secondsLeft = secondsLeft - h * 3600
    local m = math.floor(secondsLeft / 60)
    if d > 0 then return string.format("in %dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("in %dh %dm", h, m) end
    return string.format("in %dm", m)
end

-- The server only names raid difficulties 0-3 and sends 4 / 5 as plain numbers.
local MYTHIC_DIFF_LABEL = { [4] = "Mythic", [5] = "Mythic+" }

local function DifficultyText(lockout)
    local difficulty = tonumber(lockout.difficulty) or tonumber(lockout.diffName)
    return MYTHIC_DIFF_LABEL[difficulty] or tostring(lockout.diffName or "")
end

local function FormatNumber(n)
    n = tonumber(n) or 0
    local s = tostring(n)
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function Refresh()
    if not frame then return end

    local tokens     = PA.prestigeTokens or 0
    local cost       = LR.nextCost or 0
    local count      = LR.resetCount or 0
    local nLockouts  = #LR.lockouts
    local affordable = cost <= tokens
    local hasLO      = nLockouts > 0

    frame.tokenAmount:SetText(FormatNumber(tokens))
    frame.resetsAmount:SetText(tostring(count))
    frame.costAmount:SetText(FormatNumber(cost))
    frame.costAmount:SetTextColor(affordable and 1.0 or 1.0, affordable and 0.84 or 0.42, affordable and 0.29 or 0.42)
    if frame.costTimer then
        frame.costTimer:SetText("resets " .. FormatTimerDHM(SecondsUntilWeeklyReset()))
    end

    frame.listHeader:SetText("ACTIVE LOCKOUTS (" .. nLockouts .. ")")

    for _, row in ipairs(frame.rows) do row:Hide() end
    for i, l in ipairs(LR.lockouts) do
        local row = frame.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, frame.scroll)
            row:SetPoint("LEFT",  frame.scroll, "LEFT",   2, 0)
            row:SetPoint("RIGHT", frame.scroll, "RIGHT", -2, 0)
            row:SetHeight(ROW_H)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
            row.text:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.text:SetPoint("RIGHT", row, "RIGHT", -250, 0)
            row.text:SetJustifyH("LEFT")
            row.diffTag = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.diffTag:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
            row.diffTag:SetWidth(150)
            row.diffTag:SetPoint("RIGHT", row, "RIGHT", -100, 0)
            row.diffTag:SetJustifyH("RIGHT")
            row.diffTag:SetTextColor(unpack(PA.UI.Color.textAccent))
            row.timeLeft = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            row.timeLeft:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
            row.timeLeft:SetWidth(90)
            row.timeLeft:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            row.timeLeft:SetJustifyH("RIGHT")
            row.timeLeft:SetTextColor(unpack(PA.UI.Nav.muted))
            frame.rows[i] = row
        end
        row:SetPoint("TOP", frame.scroll, "TOP", 0, -((i - 1) * ROW_H))
        if i % 2 == 0 then
            row.bg:SetVertexColor(PA.UI.Nav.row[1], PA.UI.Nav.row[2],
                                  PA.UI.Nav.row[3], 0.45)
        else
            row.bg:SetVertexColor(0, 0, 0, 0)
        end
        row.text:SetText(l.mapName)
        row.diffTag:SetText("[" .. DifficultyText(l) .. "]")
        row.timeLeft:SetText(FormatRelative(l))
        row:Show()
    end
    if hasLO then frame.empty:Hide() else frame.empty:Show() end

    if not hasLO then
        frame.resetBtn:SetLabel("Reset All")
        frame.resetBtn:SetDisabledLook(true)
    elseif not affordable then
        frame.resetBtn:SetLabel("Need " .. FormatNumber(cost - tokens) .. " more")
        frame.resetBtn:SetDisabledLook(true)
    else
        frame.resetBtn:SetLabel("Reset All  (" .. FormatNumber(cost) .. " tokens)")
        frame.resetBtn:SetDisabledLook(false)
    end
    frame.refreshBtn:Show()
    frame.resetBtn:Show()

    if LR.statusUntil and time() < LR.statusUntil then
        frame.status:SetText(LR.statusText)
        frame.status:Show()
    else
        frame.status:Hide()
    end
end

local function FlashStatus(msg, color)
    LR.statusText  = (color or "|cffffffff") .. msg .. "|r"
    LR.statusUntil = time() + 5
    Refresh()
end

local function MakeStatBoxLR(parent, w, h, label, withTimer)
    local UI = PA.UI
    local box = UI.MakeStatBox(parent, w, h, label)
    box.label:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    box.value:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    box.value:SetTextColor(unpack(UI.Color.textHi))
    if withTimer then
        box.value:ClearAllPoints()
        box.value:SetPoint("BOTTOM", box, "BOTTOM", 0, 22)
        local timer = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        timer:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        timer:SetPoint("BOTTOM", box, "BOTTOM", 0, 6)
        timer:SetTextColor(unpack(UI.Color.textAccent))
        return box, box.value, timer
    end
    return box, box.value
end

local function BuildLockoutTab(panel)
    local UI = PA.UI
    local f = panel
    local boxH, gap = 76, 12
    local boxW = math.max(110, ((f:GetWidth() or 568) - gap * 2) / 3)

    f.tokenBox, f.tokenAmount =
        MakeStatBoxLR(f, boxW, boxH, "TOKENS")

    f.resetsBox, f.resetsAmount =
        MakeStatBoxLR(f, boxW, boxH, "RESETS THIS WEEK")

    f.costBox, f.costAmount, f.costTimer =
        MakeStatBoxLR(f, boxW, boxH, "NEXT RESET COST", true)
    local function LayoutStatBoxes()
        local width = f:GetWidth() or 568
        boxW = math.max(110, (width - gap * 2) / 3)
        local boxes = { f.tokenBox, f.resetsBox, f.costBox }
        for i, box in ipairs(boxes) do
            box:SetSize(boxW, boxH)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", f, "TOPLEFT", (i - 1) * (boxW + gap), -4)
        end
    end
    LayoutStatBoxes()
    f:HookScript("OnSizeChanged", LayoutStatBoxes)

    f.listHeader = UI.MakeSectionDivider(f, "ACTIVE LOCKOUTS (0)",
        { "TOPLEFT", f, "TOPLEFT", 0, -132 })
    f.listHeader:SetFont("Fonts\\FRIZQT__.TTF", 15, "")

    local refreshBtn = UI.MakeButton(f, "Refresh", {
        w = 130, h = 34, variant = "secondary",
        onClick = function() ShowLoading(); SendServer("RequestState") end,
    })
    refreshBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    refreshBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -88)
    refreshBtn:SetFrameLevel(f:GetFrameLevel() + 30)
    refreshBtn:SetFrameStrata("HIGH")
    f.refreshBtn = refreshBtn

    f.resetBtn = UI.MakeButton(f, "Reset All", {
        w = 260, h = 34, variant = "gold",
        onClick = function()
            if not StaticPopupDialogs["PA_LR_CONFIRM"] then
                StaticPopupDialogs["PA_LR_CONFIRM"] = {
                    text = "Spend %d Tokens to reset EVERY active lockout?",
                    button1 = YES, button2 = NO,
                    OnAccept = function() SendServer("Reset") end,
                    timeout = 0, whileDead = 1, hideOnEscape = 1,
                }
            end
            StaticPopup_Show("PA_LR_CONFIRM", LR.nextCost)
        end,
    })
    f.resetBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    f.resetBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -88)
    f.resetBtn:SetFrameLevel(f:GetFrameLevel() + 30)
    f.resetBtn:SetFrameStrata("HIGH")

    f.scroll = CreateFrame("Frame", nil, f)
    f.scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     0,  -160)
    f.scroll:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 14)
    f.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 14)
    UI.AstralBackdrop(f.scroll, { thin = true, cosmic = true })
    f.rows = {}

    f.empty = f.scroll:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.empty:SetFont("Fonts\\FRIZQT__.TTF", 15, "")
    f.empty:SetPoint("CENTER", f.scroll, "CENTER", 0, 0)
    f.empty:SetText("No active lockouts.")
    f.empty:SetTextColor(unpack(UI.Nav.muted))
    f.empty:Hide()

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 142, 12)
    f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 12)
    f.status:SetTextColor(unpack(UI.Color.textWarn))
    f.status:Hide()
    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t > 1.0 then
            self._t = 0
            if self.costTimer then
                self.costTimer:SetText("resets " .. FormatTimerDHM(SecondsUntilWeeklyReset()))
            end
            if LR.statusUntil and time() >= LR.statusUntil and self.status:IsShown() then
                self.status:Hide()
            end
        end
    end)

    if UI.MakeLoadingOverlay then
        f.loadingOverlay = UI.MakeLoadingOverlay(f.scroll,
            { text = "Loading lockouts" .. string.char(0xE2, 0x80, 0xA6) })
    end

    f:SetScript("OnShow", function()
        if RequestRaidInfo then RequestRaidInfo() end
        SendServer("RequestState")
        if f.loadingOverlay then f.loadingOverlay:Show() end
        Refresh()
    end)

    frame = f
end

local instanceInfoEvents = CreateFrame("Frame")
instanceInfoEvents:RegisterEvent("UPDATE_INSTANCE_INFO")
instanceInfoEvents:SetScript("OnEvent", function()
    if frame and frame:IsShown() then Refresh() end
end)

local function ToggleFrame()
    if not PA.mainFrame then return end
    if PA.mainFrame:IsShown()
       and PA.mainFrame._activeTabId == "LockoutReset" then
        PA.mainFrame:Hide()
    else
        PA.mainFrame:Show()
        PA.mainFrame:SwitchTab("LockoutReset")
        if PA.mainFrame._tabBar then
            PA.mainFrame._tabBar:SelectTab("LockoutReset")
        end
    end
end

local function RegisterLockoutResetHandlers()
    if not (_G.AIO and _G.AIO.AddHandlers) then return false end
    local ClientHandler = _G.AIO.AddHandlers("AstralLockoutReset", {})

    ClientHandler.State = function(_, payload)
        if type(payload) ~= "table" then return end
        LR.lockouts   = (type(payload.lockouts) == "table") and payload.lockouts or {}
        LR.resetCount = tonumber(payload.resetCount) or 0
        LR.nextCost   = tonumber(payload.nextCost)   or 0
        if frame and frame:IsShown() then Refresh() end
        if frame and frame.loadingOverlay then frame.loadingOverlay:Hide() end
    end

    ClientHandler.Result = function(_, kind, a, b)
        if kind == "ok" then
            local newBalance = tonumber(a) or PA.prestigeTokens or 0
            local newCount   = tonumber(b) or (LR.resetCount + 1)
            PA.prestigeTokens = newBalance    -- optimistic; wallet poll confirms
            LR.resetCount     = newCount
            LR.lockouts       = {}
            FlashStatus("Lockouts reset.", "|cff80e090")
        elseif kind == "insufficient" then
            local need = tonumber(a) or 0
            FlashStatus("Not enough Tokens (need " .. FormatNumber(need) .. ")", "|cffff6060")
        elseif kind == "no_lockouts" then
            FlashStatus("No active lockouts to reset.", "|cffff6060")
        elseif kind == "disabled" then
            FlashStatus("Reset is currently disabled by the server.", "|cffff6060")
        else
            FlashStatus("Reset failed: " .. tostring(kind), "|cffff6060")
        end
    end

    return true
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    if RegisterLockoutResetHandlers() then
        self:UnregisterAllEvents()
        SendServer("RequestState")
    end
end)

if PA.OnTokensChanged then
    PA:OnTokensChanged(function()
        if frame and frame:IsShown() then Refresh() end
    end)
end

PA:RegisterModule("LockoutReset", "Raid Lockouts", ToggleFrame, {
    subtitle = "Spend Tokens to wipe every active raid + dungeon lockout.",
})
PA:RegisterTabContent("LockoutReset", BuildLockoutTab)

PA.LockoutReset = LR
