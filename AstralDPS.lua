local addonName = ...
-- unified look: blues follow Settings > Global UI color (no-op if the hub is not loaded)
local Tint = (ProjectAstral and ProjectAstral.UI and ProjectAstral.UI.Tint) or function(r, g, b, a) return r, g, b, a or 1 end
-- Own global names: the standalone "DPS TRACKER" addon this came from also uses DPS and
-- DPSDB, and with both loaded every hit was counted twice into one shared table.
ProjectAstralDPS = ProjectAstralDPS or {}
local DPS = ProjectAstralDPS

ProjectAstralDPSDB = ProjectAstralDPSDB or {
    players = {},
    startTime = nil,
    lastDamageTime = nil,
}

local currentMode = "dps" -- "dps", "heals", "tank", "pet"

-- 10-second rolling window for "Current DPS"
local ROLLING_WINDOW = 10

-- Add to a recent-events list and drop what's older than the window. The combat log
-- keeps recording while the meter is hidden, when GetStats (which also prunes) never
-- runs, so without this the lists grow for the whole session.
local function PushRecent(list, now, v)
    list[#list + 1] = { t = now, v = v }
    while list[1] and now - list[1].t > ROLLING_WINDOW do
        table.remove(list, 1)
    end
end

-- Keep track of who is in our group and their class colors
local groupMembers = {}
local classColors = {}

-- Bit flags for 3.3.5a Combat Log to reliably detect Pets and Guardians
local OBJECT_TYPE_PET = 0x00001000
local OBJECT_TYPE_GUARDIAN = 0x00002000
local OBJECT_TYPE_PLAYER = 0x00000400
local REACTION_FRIENDLY = 0x00000010
local PET_OR_GUARDIAN = OBJECT_TYPE_PET + OBJECT_TYPE_GUARDIAN

local function InitPlayer(name)
    if not ProjectAstralDPSDB.players[name] then
        ProjectAstralDPSDB.players[name] = { 
            damage = 0, heals = 0, taken = 0, spells = {}, isPet = false, 
            recentDmg = {}, recentHeals = {}, recentTaken = {} 
        }
    end
end

-- Helper to robustly get spell icons in 3.3.5a
local function GetSpellIcon(spellId, spellName)
    if spellId and spellId > 0 then
        local _, _, tex = GetSpellInfo(spellId)
        if tex then return tex end
    end
    if spellName then
        local _, _, tex = GetSpellInfo(spellName)
        if tex then return tex end
    end
    if spellName == "Melee" then return "Interface\\Icons\\Ability_MeleeDamage" end
    if spellName == "Environment" then return "Interface\\Icons\\Spell_Fire_SelfDestruct" end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function UpdateGroupMembers()
    groupMembers = {}
    classColors = {}

    local name, class, _
    
    name = UnitName("player")
    if name then
        groupMembers[name] = true
        _, class = UnitClass("player")
        if class and RAID_CLASS_COLORS[class] then classColors[name] = RAID_CLASS_COLORS[class] end
    end

    for i = 1, GetNumPartyMembers() do
        name = UnitName("party"..i)
        if name then
            groupMembers[name] = true
            _, class = UnitClass("party"..i)
            if class and RAID_CLASS_COLORS[class] then classColors[name] = RAID_CLASS_COLORS[class] end
        end
    end

    for i = 1, GetNumRaidMembers() do
        -- name, rank, subgroup, level, class, fileName (the class token), zone, online, isDead, role
        name, _, _, _, _, class = GetRaidRosterInfo(i)
        if name then
            groupMembers[name] = true
            if class and RAID_CLASS_COLORS[class] then classColors[name] = RAID_CLASS_COLORS[class] end
        end
    end
end

local gr = CreateFrame("Frame")
gr:RegisterEvent("PARTY_MEMBERS_CHANGED")
gr:RegisterEvent("RAID_ROSTER_UPDATE")
gr:RegisterEvent("PLAYER_ENTERING_WORLD")
gr:RegisterEvent("UNIT_PET")
gr:SetScript("OnEvent", UpdateGroupMembers)

-- Combat Log Parser
local cl = CreateFrame("Frame")
cl:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
cl:SetScript("OnEvent", function(self, event, ...)
    if not self.enabled then return end
    -- Wrath 3.3.5 does not include the modern hideCaster/raid-flag fields.
    -- Keep the legacy header aligned or every damage/heal field is shifted.
    local _, cleu, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags,
          p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13 = ...
    if not cleu or not srcName then return end

    srcFlags = tonumber(srcFlags) or 0
    dstFlags = tonumber(dstFlags) or 0
    
    local isFriendlySrc = bit.band(srcFlags, REACTION_FRIENDLY) > 0
    local isPlayerSrc = bit.band(srcFlags, OBJECT_TYPE_PLAYER) > 0
    local isPetSrc = bit.band(srcFlags, PET_OR_GUARDIAN) > 0
    
    local amount = 0
    local spellName = "Unknown"
    local spellId = nil
    local isHeal = false
    local isDamage = false

    if cleu == "SWING_DAMAGE" then
        amount = p1
        spellName = "Melee"
        isDamage = true
    elseif cleu == "RANGE_DAMAGE" then
        spellId, spellName, amount = p1, p2, p4
        isDamage = true
    elseif cleu == "ENVIRONMENTAL_DAMAGE" then
        spellName, amount = p1 or "Environment", p2
        isDamage = true
    elseif cleu == "SPELL_DAMAGE" or cleu == "SPELL_PERIODIC_DAMAGE"
           or cleu == "SPELL_BUILDING_DAMAGE" or cleu == "DAMAGE_SHIELD"
           or cleu == "DAMAGE_SPLIT" then
        spellId, spellName, amount = p1, p2, p4
        isDamage = true
    elseif cleu == "SPELL_HEAL" or cleu == "SPELL_PERIODIC_HEAL" then
        spellId, spellName = p1, p2
        -- Count effective healing, not overhealing. On this client the
        -- overheal amount is the field immediately after the heal amount.
        amount = (tonumber(p4) or 0) - (tonumber(p5) or 0)
        isHeal = true
    end

    spellName = spellName or (isHeal and "Heal" or "Spell")
    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    local now = GetTime()
    local trackSrc = false
    if isFriendlySrc and isPlayerSrc and groupMembers[srcName] then
        trackSrc = true
    elseif isFriendlySrc and isPetSrc then
        trackSrc = true
    end

    if trackSrc and (isDamage or isHeal) then
        if not ProjectAstralDPSDB.startTime then ProjectAstralDPSDB.startTime = now end
        ProjectAstralDPSDB.lastDamageTime = now

        InitPlayer(srcName)
        ProjectAstralDPSDB.players[srcName].isPet = isPetSrc

        local data = ProjectAstralDPSDB.players[srcName]
        if isHeal then
            data.heals = data.heals + amount
            PushRecent(data.recentHeals, now, amount)
        else
            data.damage = data.damage + amount
            PushRecent(data.recentDmg, now, amount)
        end

        if not data.spells[spellName] then
            data.spells[spellName] = {
                val = 0, icon = GetSpellIcon(spellId, spellName)
            }
        end
        data.spells[spellName].val = data.spells[spellName].val + amount
    end

    -- Incoming damage can come from hostile sources, so it must not be
    -- nested under the friendly-source check used for outgoing damage.
    if isDamage and dstName then
        local isPlayerDst = bit.band(dstFlags, OBJECT_TYPE_PLAYER) > 0
        local isFriendlyDst = bit.band(dstFlags, REACTION_FRIENDLY) > 0
        if isPlayerDst and isFriendlyDst and groupMembers[dstName] then
            InitPlayer(dstName)
            local data = ProjectAstralDPSDB.players[dstName]
            data.taken = data.taken + amount
            PushRecent(data.recentTaken, now, amount)
            if not ProjectAstralDPSDB.startTime then ProjectAstralDPSDB.startTime = now end
            ProjectAstralDPSDB.lastDamageTime = now
        end
    end
end)

local function FormatNumber(num)
    if num >= 1000000 then return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then return string.format("%.1fk", num / 1000)
    else return tostring(math.floor(num)) end
end

local function GetStats(name)
    local pData = ProjectAstralDPSDB.players[name]
    if not pData then return 0, 0 end
    
    local currentTime = GetTime()
    local sum = 0
    local events, total
    
    if currentMode == "heals" then
        if pData.isPet then return 0, 0 end
        events = pData.recentHeals; total = pData.heals
    elseif currentMode == "tank" then
        if pData.isPet then return 0, 0 end
        events = pData.recentTaken; total = pData.taken
    else -- "dps" and "pet" use damage
        if (currentMode == "pet" and not pData.isPet) or (currentMode == "dps" and pData.isPet) then return 0, 0 end
        events = pData.recentDmg; total = pData.damage
    end
    
    -- Prune old events and calculate 10s sum
    local j = 1
    for i = 1, #events do
        if currentTime - events[i].t <= ROLLING_WINDOW then
            events[j] = events[i]
            sum = sum + events[i].v
            j = j + 1
        end
    end
    -- Clear leftover old events
    for i = j, #events do events[i] = nil end
    
    -- Use the actual active age of the rolling sample. Dividing every sample
    -- by ten made fresh casts and gem procs report artificially low DPS/HPS.
    local duration = ROLLING_WINDOW
    if events[1] then
        duration = math.min(ROLLING_WINDOW, math.max(1, currentTime - events[1].t))
    end
    local val = sum / duration
    return val, total
end

local function GetSortedPlayers()
    local list = {}
    for name, data in pairs(ProjectAstralDPSDB.players) do
        local val, total = GetStats(name)
        -- Show players if they have done ANY damage in the last 10 seconds, OR if their total > 0 (so they don't disappear instantly when combat ends)
        if val > 0 or total > 0 then
            table.insert(list, {name = name, val = val, total = total})
        end
    end
    -- Sort by Current DPS primarily, then Total Damage
    table.sort(list, function(a, b) 
        if a.val == b.val then return a.total > b.total end
        return a.val > b.val 
    end)
    return list
end

local function ResetMeter()
    ProjectAstralDPSDB = { players = {}, startTime = nil, lastDamageTime = nil }
end

-- REPORT FUNCTION
local function SendReport()
    local channel = "SAY"
    if GetNumRaidMembers() > 0 then channel = "RAID"
    elseif GetNumPartyMembers() > 0 then channel = "PARTY" end

    local sorted = GetSortedPlayers()
    if #sorted == 0 then return end

    local modeText = "DPS"
    if currentMode == "heals" then modeText = "HPS" 
    elseif currentMode == "tank" then modeText = "TPS" 
    elseif currentMode == "pet" then modeText = "Pet DPS" end

    SendChatMessage("--- Tracker Report (" .. modeText .. ") ---", channel)
    for i = 1, math.min(5, #sorted) do
        local data = sorted[i]
        SendChatMessage(string.format("%d. %s - %s %s (%s)", i, data.name, FormatNumber(data.val), modeText, FormatNumber(data.total)), channel)
    end
end

-- MAIN UI FRAME
local frame = CreateFrame("Frame", "DPSCounterMainFrame", UIParent)
frame:SetSize(320, 250)
frame:SetPoint("CENTER", UIParent, "CENTER")
-- Match the hub: the tracker must stay above action bars and regular addons.
frame:SetFrameStrata("MEDIUM")   -- below the Astral hub (HIGH)
frame:SetFrameLevel(20)
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 18,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.97))
frame:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetResizable(true)
frame:SetMinResize(240, 100)
frame:SetMaxResize(500, 800)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()

local header = CreateFrame("Frame", nil, frame)
header:SetHeight(42)
header:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
header:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", tile = true })
header:SetBackdropColor(Tint(0.031, 0.047, 0.133, 1))
header:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))

local headerAccent = header:CreateTexture(nil, "ARTWORK")
headerAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
headerAccent:SetVertexColor(0.40, 0.78, 1.00, 0.9)
headerAccent:SetPoint("TOPLEFT", header, "TOPLEFT", 1, 0)
headerAccent:SetPoint("TOPRIGHT", header, "TOPRIGHT", -1, 0)
headerAccent:SetHeight(2)

local headerTitle = header:CreateFontString(nil, "OVERLAY")
headerTitle:SetPoint("TOPLEFT", header, "TOPLEFT", 8, -3)
headerTitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
headerTitle:SetText("Project Astral DPS")
headerTitle:SetTextColor(1, 0.88, 0.42)

-- Text Button Factory
local function CreateTextButton(parent, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(20)
    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "THICKOUTLINE")
    btn.text:SetText(text)
    btn.text:SetTextColor(0.72, 0.72, 0.76)
    btn:SetWidth(btn.text:GetStringWidth() + 10)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.96))
    btn:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))
    btn:SetScript("OnEnter", function()
        btn.text:SetTextColor(1, 1, 1)
        btn:SetBackdropColor(Tint(0.063, 0.090, 0.227, 1))
        btn:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
    end)
    btn:SetScript("OnLeave", function()
        btn.text:SetTextColor(0.72, 0.72, 0.76)
        btn:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.96))
        btn:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))
    end)
    return btn
end

-- Reset Button
local btnReset = CreateTextButton(header, "Reset")
btnReset:SetPoint("RIGHT", header, "RIGHT", -6, 0)
btnReset:SetScript("OnClick", function() ResetMeter() end)

-- Report Button
local btnReport = CreateTextButton(header, "Report")
btnReport:SetPoint("RIGHT", btnReset, "LEFT", -6, 0)
btnReport:SetScript("OnClick", SendReport)

-- Lock Button
local btnLock = CreateTextButton(header, "Lock")
btnLock:SetPoint("RIGHT", btnReport, "LEFT", -6, 0)
btnLock:SetScript("OnClick", function()
    if frame:IsMovable() then
        frame:SetMovable(false)
        frame:EnableMouse(false)
        btnLock.text:SetTextColor(1, 0.2, 0.2)
        btnLock.text:SetText("Locked")
        btnLock:SetWidth(btnLock.text:GetStringWidth() + 10)
    else
        frame:SetMovable(true)
        frame:EnableMouse(true)
        btnLock.text:SetTextColor(0.8, 0.8, 0.8)
        btnLock.text:SetText("Lock")
        btnLock:SetWidth(btnLock.text:GetStringWidth() + 10)
    end
end)

-- TAB BUTTONS
local tabs = {}
local function CreateTabButton(text, mode)
    local tab = CreateFrame("Button", nil, header)
    tab:SetHeight(20)
    tab.text = tab:CreateFontString(nil, "OVERLAY")
    tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "THICKOUTLINE")
    tab.text:SetText(text)
    tab.text:SetTextColor(0.52, 0.52, 0.56)
    tab:SetWidth(tab.text:GetStringWidth() + 16)
    tab:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    tab:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.96))
    tab:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))
    
    tab:SetScript("OnClick", function()
        currentMode = mode
        for _, t in pairs(tabs) do
            t.text:SetTextColor(0.52, 0.52, 0.56)
            t:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.96))
            t:SetBackdropBorderColor(Tint(0.165, 0.204, 0.400, 1))
        end
        tab.text:SetTextColor(1, 1, 1)
        tab:SetBackdropColor(Tint(0.063, 0.090, 0.227, 1))
        tab:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
    end)
    
    tabs[mode] = tab
    return tab
end

local tabDPS = CreateTabButton("DPS", "dps")
tabDPS:SetPoint("LEFT", header, "LEFT", 8, -15)
local tabHeals = CreateTabButton("HPS", "heals")
tabHeals:SetPoint("LEFT", tabDPS, "RIGHT", 2, 0)
local tabTank = CreateTabButton("Tank", "tank")
tabTank:SetPoint("LEFT", tabHeals, "RIGHT", 2, 0)
local tabPet = CreateTabButton("Pet", "pet")
tabPet:SetPoint("LEFT", tabTank, "RIGHT", 2, 0)

tabDPS:SetBackdropColor(Tint(0.063, 0.090, 0.227, 1))
tabDPS:SetBackdropBorderColor(0.95, 0.95, 0.95, 1)
tabDPS.text:SetTextColor(1, 1, 1)

-- SCROLL FRAME FOR RAIDS
local scrollFrame = CreateFrame("ScrollFrame", "DPSCounterScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -4)
scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 4)

-- Transparent Scrollbar
local scrollBarName = scrollFrame:GetName().."ScrollBar"
local scrollBar = _G[scrollBarName]
if scrollBar then
    scrollBar:SetAlpha(0.0)
    scrollBar:HookScript("OnEnter", function() scrollBar:SetAlpha(0.5) end)
    scrollBar:HookScript("OnLeave", function() scrollBar:SetAlpha(0.0) end)
    _G[scrollBarName.."ScrollUpButton"]:SetAlpha(0.0)
    _G[scrollBarName.."ScrollDownButton"]:SetAlpha(0.0)
end

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetHeight(40 * 18)
scrollFrame:SetScrollChild(scrollChild)

-- RESIZER GRIP
local resizer = CreateFrame("Button", nil, frame)
resizer:SetSize(16, 16)
resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight", "ADD")
resizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resizer:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

-- FIX RESIZING: Update ScrollChild width dynamically
frame:SetScript("OnSizeChanged", function(self, width, height)
    scrollChild:SetWidth(scrollFrame:GetWidth())
end)

-- ROWS
local rows = {}
local rowHeight = 18
for i = 1, 40 do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i-1)*rowHeight))
    row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
    row:EnableMouse(true)
    
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.bg:SetAllPoints(row)
    row.bg:SetVertexColor(i % 2 == 0 and 0.035 or 0.055,
        i % 2 == 0 and 0.035 or 0.055,
        i % 2 == 0 and 0.04 or 0.08, 0.92)

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.hover:SetAllPoints(row)
    row.hover:SetVertexColor(0.40, 0.78, 1.00, 0.10)
    
    row.bar = row:CreateTexture(nil, "BORDER")
    row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.bar:SetPoint("TOP", row, "TOP", 0, 0)
    row.bar:SetPoint("BOTTOM", row, "BOTTOM", 0, 0)
    row.bar:SetVertexColor(0.40, 0.78, 1.00, 0.42)
    
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    row.name:SetTextColor(0.90, 0.90, 0.92)
    
    row.dps = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.dps:SetPoint("CENTER", row, "CENTER", 0, 0)
    row.dps:SetJustifyH("CENTER")
    row.dps:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    row.dps:SetTextColor(1, 0.88, 0.42)
    
    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.total:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    row.total:SetTextColor(0.72, 0.72, 0.76)
    
    rows[i] = row
end

-- CUSTOM TOOLTIP (Dark Theme)
local tooltip = CreateFrame("Frame", "DPSCounterTooltip", UIParent)
tooltip:SetSize(230, 116)
tooltip:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
})
tooltip:SetBackdropColor(Tint(0.031, 0.047, 0.133, 0.98))
tooltip:SetBackdropBorderColor(0.40, 0.78, 1.00, 1)
tooltip:SetFrameStrata("TOOLTIP")
tooltip:Hide()

local tooltipAccent = tooltip:CreateTexture(nil, "ARTWORK")
tooltipAccent:SetTexture("Interface\\Buttons\\WHITE8X8")
tooltipAccent:SetVertexColor(0.40, 0.78, 1.00, 0.95)
tooltipAccent:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 3, -3)
tooltipAccent:SetPoint("TOPRIGHT", tooltip, "TOPRIGHT", -3, -3)
tooltipAccent:SetHeight(2)

tooltip.title = tooltip:CreateFontString(nil, "OVERLAY")
tooltip.title:SetPoint("TOPLEFT", tooltip, "TOPLEFT", 10, -8)
tooltip.title:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
tooltip.title:SetTextColor(1, 0.88, 0.42)

tooltip.lines = {}
for i = 1, 5 do
    local line = CreateFrame("Frame", nil, tooltip)
    line:SetSize(210, 16)
    line:SetPoint("TOPLEFT", tooltip.title, "BOTTOMLEFT", 0, -((i-1)*16) - 5)
    
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetSize(14, 14)
    line.icon:SetPoint("LEFT", line, "LEFT", 0, 0)
    line.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("LEFT", line.icon, "RIGHT", 5, 0)
    line.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    line.text:SetTextColor(0.90, 0.90, 0.92)
    
    tooltip.lines[i] = line
end

local function GetSortedSpells(name)
    local pData = ProjectAstralDPSDB.players[name]
    if not pData then return {} end
    local list = {}
    for sName, sData in pairs(pData.spells) do
        table.insert(list, {name = sName, val = sData.val, icon = sData.icon})
    end
    table.sort(list, function(a, b) return a.val > b.val end)
    return list
end

-- UPDATE LOOP (frequent enough to reflect fast casts and gem procs)
local updateTimer = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer < 0.25 then return end
    updateTimer = 0

    local sorted = GetSortedPlayers()
    local modeText = "DPS"
    if currentMode == "heals" then modeText = "HPS" 
    elseif currentMode == "tank" then modeText = "TPS" 
    elseif currentMode == "pet" then modeText = "Pet DPS" end

    local maxVal = 1
    if sorted[1] then maxVal = sorted[1].val end
    if maxVal == 0 then maxVal = 1 end

    for i = 1, 40 do
        local row = rows[i]
        if sorted[i] then
            local data = sorted[i]
            
            local dispName = data.name
            -- cut by characters, not bytes: a byte cut split accented names mid-letter
            if dispName:gsub("[\128-\191]", ""):len() > 10 then
                local n, cut = 0, #dispName
                for pos in dispName:gmatch("()[^\128-\191]") do
                    n = n + 1
                    if n == 10 then cut = pos - 1; break end
                end
                dispName = dispName:sub(1, cut) .. ".."
            end
            
            local pct = data.val / maxVal
            if pct > 1 then pct = 1 end
            -- the rows hang off scrollChild, whose width was only set when the meter was
            -- resized; before that every row (and bar) was 0 wide
            if scrollChild:GetWidth() ~= scrollFrame:GetWidth() then
                scrollChild:SetWidth(scrollFrame:GetWidth())
            end
            local barW = row:GetWidth() * pct
            if barW >= 1 then
                row.bar:SetWidth(barW)
                row.bar:Show()
            else
                row.bar:Hide()   -- a texture width of 0 doesn't mean "no bar"
            end
            
            local c = classColors[data.name]
            local pData = ProjectAstralDPSDB.players[data.name]
            if pData and pData.isPet then
                row.bar:SetVertexColor(0.8, 0.5, 0.1, 0.8)
            elseif c then
                row.bar:SetVertexColor(c.r * 0.6, c.g * 0.6, c.b * 0.6, 0.8)
            else
                row.bar:SetVertexColor(0.3, 0.3, 0.3, 0.8)
            end
            
            row.name:SetText(dispName)
            row.dps:SetText(FormatNumber(data.val) .. " " .. modeText)
            row.total:SetText(FormatNumber(data.total))
            row:Show()
            
            row:SetScript("OnEnter", function()
                tooltip.title:SetText(data.name)
                local spells = GetSortedSpells(data.name)
                for j=1, 5 do
                    if spells[j] then
                        local sData = spells[j]
                        tooltip.lines[j].icon:SetTexture(sData.icon)
                        tooltip.lines[j].icon:Show()
                        tooltip.lines[j].text:SetText(string.format("%s: %s (%.1f%%)", sData.name, FormatNumber(sData.val), (sData.val/data.total)*100))
                        tooltip.lines[j].text:Show()
                    else
                        tooltip.lines[j].icon:Hide()
                        tooltip.lines[j].text:Hide()
                    end
                end
                
                tooltip:ClearAllPoints()
                local uiRight = UIParent:GetRight()
                local uiLeft = UIParent:GetLeft()
                local uiBottom = UIParent:GetBottom()
                local rowRight = row:GetRight()
                local rowLeft = row:GetLeft()
                local rowBottom = row:GetBottom()
                
                if (uiRight - rowRight) > 220 then
                    tooltip:SetPoint("LEFT", row, "RIGHT", 20, 0)
                elseif (rowLeft - uiLeft) > 220 then
                    tooltip:SetPoint("RIGHT", row, "LEFT", -20, 0)
                else
                    if (rowBottom - uiBottom) > 120 then
                        tooltip:SetPoint("BOTTOM", row, "TOP", 0, 5)
                    else
                        tooltip:SetPoint("TOP", row, "BOTTOM", 0, -5)
                    end
                end
                tooltip:Show()
            end)
            row:SetScript("OnLeave", function() tooltip:Hide() end)
        else
            row:Hide()
        end
    end
end)

-- MINIMAP BUTTON
local mmBtn = CreateFrame("Button", "DPSCounterMinimapButton", Minimap)
mmBtn:SetSize(33, 33)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:SetFrameLevel(8)

local mmBorder = mmBtn:CreateTexture(nil, "OVERLAY")
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmBorder:SetSize(56, 56)
mmBorder:SetPoint("CENTER", mmBtn, "CENTER", 11, -11)

local mmIcon = mmBtn:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\Ability_MeleeDamage")
mmIcon:SetSize(22, 22)
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
mmIcon:SetPoint("CENTER", mmBtn, "CENTER", 0, 0)

local defaultAngle = math.rad(-45)
local currentAngle = defaultAngle
mmBtn:SetPoint("CENTER", Minimap, "CENTER", math.cos(currentAngle) * 80, math.sin(currentAngle) * 80)

mmBtn:SetMovable(true)
mmBtn:RegisterForDrag("LeftButton")
mmBtn:RegisterForClicks("AnyUp")

mmBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local xpos, ypos = GetCursorPosition()
        local umx, umy = Minimap:GetCenter()
        xpos = xpos / UIParent:GetScale() - umx
        ypos = ypos / UIParent:GetScale() - umy
        local angle = math.atan2(ypos, xpos)
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
    end)
end)

mmBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

mmBtn:SetScript("OnClick", function(self)
    if frame:IsShown() then frame:Hide() else frame:Show() end
end)

mmBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("|cFFFFFFFFDPS Tracker|r")
    GameTooltip:AddLine("|cffFFFFFFLeft-Click|r to open/close UI.", 1, 1, 1)
    GameTooltip:AddLine("|cff888888Drag corner to resize.", 0.6, 0.6, 0.7)
    GameTooltip:Show()
end)

mmBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

function DPS.SetEnabled(on)
    on = on and true or false
    DPS.enabled = on
    cl.enabled = on
    if on then
        cl:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        frame:Show()
        mmBtn:Hide()
        mmBtn:EnableMouse(false)
    else
        cl:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        frame:Hide()
        mmBtn:Hide()
        mmBtn:EnableMouse(false)
    end
end

SLASH_DPSCOUNTER1 = "/dps"
SlashCmdList["DPSCOUNTER"] = function(msg)
    if msg and string.lower(msg) == "report" then
        SendReport()
    elseif not DPS.enabled then
        print("|cff99b8ffProject Astral DPS|r is turned off. Turn it on in the Astral hub's Settings (Chat section).")
    else
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == "ProjectAstral" then
        -- GetTime() restarts with the client, so last session's recent-hit stamps would
        -- count as current damage: keep only the totals
        local db = ProjectAstralDPSDB
        if type(db) ~= "table" or type(db.players) ~= "table" then
            ProjectAstralDPSDB = { players = {}, startTime = nil, lastDamageTime = nil }
        else
            db.startTime, db.lastDamageTime = nil, nil
            for _, p in pairs(db.players) do
                if type(p) == "table" then
                    p.recentDmg, p.recentHeals, p.recentTaken = {}, {}, {}
                    p.spells = type(p.spells) == "table" and p.spells or {}
                    p.damage = tonumber(p.damage) or 0
                    p.heals  = tonumber(p.heals)  or 0
                    p.taken  = tonumber(p.taken)  or 0
                end
            end
        end
        UpdateGroupMembers()
        local enabled = true
        if ProjectAstral and ProjectAstral.Settings
           and ProjectAstral.Settings.dpsTracker then
            enabled = ProjectAstral.Settings.dpsTracker.enabled ~= false
        end
        DPS.SetEnabled(enabled)
        print("|cff99b8ffProject Astral DPS|r loaded. Type |cffffffff/dps|r to show or hide the meter.")
    end
end)