
local PA = ProjectAstral
local UI = PA.UI

local AT = PA.AT or {}

local FORMAT_PREFIX = "ATBUILD:1.0:"
local NUM_ROWS      = 7
local ROW_H         = 32
local PANEL_W       = 420
local PANEL_H       = NUM_ROWS * ROW_H + 130

local panel

-- unified Astral look (same as the gem and build tabs)
local SOLID = "Interface\\Buttons\\WHITE8X8"
local function Navy(f, bg, edge)
    f.__paBackdrop = true   -- Theme.lua greys navy backdrops otherwise
    f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end
-- navy window with a gold edge, gold top glow and a gold-barred title
local function NavyWindow(f, titleText, subText)
    UI.AstralBackdrop(f, { thin = true })
    f:SetBackdropColor(UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)
    f.__paBackdrop = true
    local glow = f:CreateTexture(nil, "ARTWORK"); glow:SetTexture(SOLID)
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    glow:SetHeight(40)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)
    local accent = f:CreateTexture(nil, "OVERLAY"); accent:SetTexture(SOLID)
    accent:SetVertexColor(0.886, 0.753, 0.384, 1); accent:SetSize(3, 18)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    local title = f:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(title, 15)
    title:SetPoint("LEFT", accent, "RIGHT", 9, 0)
    title:SetText(titleText or "")
    title:SetTextColor(1, 1, 1)
    local sub
    if subText and subText ~= "" then
        sub = f:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(sub, 12)
        sub:SetPoint("TOPLEFT", f, "TOPLEFT", 28, -38)
        sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        sub:SetJustifyH("LEFT")
        sub:SetText("|cffaab0d4" .. subText .. "|r")
        sub:SetTextColor(0.667, 0.690, 0.831)
    end
    return title, sub
end

local function ChatInfo(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffFFD700[Astral Tree]|r " .. msg)
end

local function GetBuilds()
    if not ProjectAstralBuilds then ProjectAstralBuilds = {} end
    return ProjectAstralBuilds
end

local function CurrentUnlockedIds()
    local out = {}
    if AT.unlocked then
        for id in pairs(AT.unlocked) do out[#out+1] = id end
    end
    table.sort(out)
    return out
end

local function EncodeBuild(build)
    if not (build and build.ids) then return FORMAT_PREFIX end
    return FORMAT_PREFIX .. table.concat(build.ids, ",")
end

local function DecodeBuild(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("%s+", "")
    if not text:find("^ATBUILD:") then return nil end
    local body = text:match("^ATBUILD:[%d%.]+:(.*)$")
    if not body or body == "" then return nil end
    local ids = {}
    for chunk in body:gmatch("[^,]+") do
        local id = tonumber(chunk)
        if id then ids[#ids+1] = id end
    end
    return #ids > 0 and ids or nil
end

local function ClosureWithParents(buildIds)
    local closure, stack = {}, {}
    if not AT.nodes then return closure end
    for i = 1, #buildIds do
        if AT.nodes[buildIds[i]] then stack[#stack+1] = buildIds[i] end
    end
    while #stack > 0 do
        local id = table.remove(stack)
        if not closure[id] then
            closure[id] = true
            local n = AT.nodes[id]
            if n and n.parents then
                for i = 1, #n.parents do
                    stack[#stack+1] = n.parents[i]
                end
            end
        end
    end
    return closure
end

local function ComputeRemoveOrder(toRemoveSet)
    local order, pending = {}, {}
    for id in pairs(toRemoveSet) do pending[id] = true end
    local changed = true
    while changed do
        changed = false
        for id in pairs(pending) do
            local blocked = false
            for oid in pairs(pending) do
                if oid ~= id then
                    local n = AT.nodes[oid]
                    if n and n.parents then
                        for i = 1, #n.parents do
                            if n.parents[i] == id then blocked = true; break end
                        end
                        if blocked then break end
                    end
                end
            end
            if not blocked then
                order[#order+1] = id; pending[id] = nil; changed = true
            end
        end
    end
    return order
end

local function ComputeAddOrder(toAddSet)
    local order, pending, placed = {}, {}, {}
    local pendingCount = 0
    for id in pairs(toAddSet) do
        pending[id] = true; pendingCount = pendingCount + 1
    end
    while pendingCount > 0 do
        local progress = false
        for id in pairs(pending) do
            local n = AT.nodes[id]
            local ready = true
            if n and n.parents then
                for i = 1, #n.parents do
                    local pid = n.parents[i]
                    if not (AT.unlocked[pid] or placed[pid]) then
                        ready = false; break
                    end
                end
            end
            if ready then
                order[#order+1] = id; placed[id] = true; pending[id] = nil
                pendingCount = pendingCount - 1
                progress = true
            end
        end
        if not progress then break end
    end
    return order
end

local function ComputeCost(ids)
    local total = 0
    for i = 1, #ids do
        local n = AT.nodes and AT.nodes[ids[i]]
        if n then total = total + (AT.costs and AT.costs[n.tier or 1] or 0) end
    end
    return total
end

local function PlanBuildLoad(build)
    if not (AT.unlocked and build and build.ids) then
        return {}, {}, 0
    end
    local closure  = ClosureWithParents(build.ids)
    local toRemove = {}
    for id in pairs(AT.unlocked) do
        if not closure[id] then toRemove[id] = true end
    end
    local toAdd = {}
    for id in pairs(closure) do
        if not AT.unlocked[id] then toAdd[id] = true end
    end
    local removeOrder = ComputeRemoveOrder(toRemove)
    local addOrder    = ComputeAddOrder(toAdd)
    return removeOrder, addOrder, ComputeCost(addOrder)
end

StaticPopupDialogs["AT_BUILD_SAVE_NAME"] = {
    text         = "Enter a name for this build:",
    button1      = SAVE or "Save",
    button2      = CANCEL or "Cancel",
    hasEditBox   = true,
    maxLetters   = 40,
    OnShow       = function(self)
        self.editBox:SetText("")
        self.editBox:SetFocus()
    end,
    OnAccept     = function(self)
        local name = self.editBox:GetText():gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then ChatInfo("Build name cannot be empty."); return end
        local ids = CurrentUnlockedIds()
        if #ids == 0 then
            ChatInfo("Nothing to save — no nodes unlocked.")
            return
        end
        local builds = GetBuilds()
        builds[#builds+1] = { name = name, ids = ids }
        ChatInfo(string.format("Saved build '%s' (%d nodes).", name, #ids))
        if panel and panel:IsShown() then panel:Refresh() end
    end,
    EditBoxOnEnterPressed = function(self)
        self:GetParent().button1:Click()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["AT_BUILD_DELETE"] = {
    text         = "Delete build '%s'?\n\nThis cannot be undone.",
    button1      = DELETE or "Delete",
    button2      = CANCEL or "Cancel",
    OnAccept     = function(self, data)
        if not data then return end
        local builds = GetBuilds()
        for i = 1, #builds do
            if builds[i] == data then
                table.remove(builds, i)
                ChatInfo("Deleted build.")
                if panel and panel:IsShown() then panel:Refresh() end
                return
            end
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["AT_BUILD_LOAD"] = {
    text         = "%s",
    button1      = "Load",
    button2      = CANCEL or "Cancel",
    OnAccept     = function(self, data)
        if not (data and AT.LoadBuild) then return end
        AT.LoadBuild(data.removeOrder or {}, data.addOrder or {},
                     "build '" .. (data.name or "?") .. "'")
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local _dialogCount = 0
local function MakeTextDialog(opts)
    _dialogCount = _dialogCount + 1
    local baseName = "AT_BuildTextDialog" .. _dialogCount

    local f = CreateFrame("Frame", baseName, UIParent)
    f:SetSize(520, 280)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:Hide()
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetClampedToScreen(true)
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:Hide() end
    end)
    NavyWindow(f, opts.title, opts.body)

    local scrollFrame = CreateFrame("ScrollFrame", baseName .. "Scroll", f,
                                    "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     16, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 44)

    local bg = CreateFrame("Frame", nil, scrollFrame)
    bg:SetPoint("TOPLEFT",     -2, 2)
    bg:SetPoint("BOTTOMRIGHT",  2, -2)
    Navy(bg, UI.Tinted({ 0.020, 0.030, 0.090, 0.95 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
    bg:SetFrameLevel(scrollFrame:GetFrameLevel() - 1)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetMaxLetters(0)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetAutoFocus(false)
    editBox:SetWidth(scrollFrame:GetWidth())
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)
    scrollFrame:SetScrollChild(editBox)
    f.editBox = editBox

    local btn1 = UI.MakeButton(f, opts.button1Label or "OK", {
        w = 100, h = 26, variant = "gold",
        onClick = function()
            if opts.onAccept then opts.onAccept(editBox:GetText()) end
            f:Hide()
        end,
    })
    btn1:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)

    local btn2 = UI.MakeButton(f, "Cancel", {
        w = 80, h = 26, variant = "secondary",
        onClick = function() f:Hide() end,
    })
    btn2:SetPoint("RIGHT", btn1, "LEFT", -8, 0)

    if UI.SkinTree then UI.SkinTree(f) end
    return f
end

local exportDialog, importDialog

local function ShowExport(text)
    if not exportDialog then
        exportDialog = MakeTextDialog({
            title         = "Export Build",
            body          = "Press Ctrl+A to select all, then Ctrl+C to copy.",
            button1Label  = "Close",
            onAccept      = function() end,
        })
    end
    exportDialog:Show()
    exportDialog.editBox:SetText(text or "")
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
end

local function ShowImport()
    if not importDialog then
        importDialog = MakeTextDialog({
            title         = "Import Build",
            body          = "Paste a build text (ATBUILD:1.0:...) then click Import.",
            button1Label  = "Import",
            onAccept      = function(text)
                local ids = DecodeBuild(text)
                if not ids then
                    ChatInfo("Invalid build text (expected 'ATBUILD:1.0:1,2,3,...').")
                    return
                end
                local builds = GetBuilds()
                local name = "Imported " .. (#builds + 1)
                builds[#builds+1] = { name = name, ids = ids }
                ChatInfo(string.format("Imported build '%s' (%d nodes).", name, #ids))
                if panel and panel:IsShown() then panel:Refresh() end
            end,
        })
    end
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
end

local function MakeRow(parent, i)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(PANEL_W - 32 - 26)
    row:SetHeight(ROW_H - 2)
    Navy(row, (i % 2 == 0) and UI.Tinted({ 0.063, 0.090, 0.227, 0.80 }) or UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }),
         UI.Tinted({ 0.165, 0.204, 0.400, 1 }))

    -- the build matching your tree right now: gold tint + gold bar + "Active"
    row.activeBg = row:CreateTexture(nil, "BORDER"); row.activeBg:SetTexture(SOLID)
    row.activeBg:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1); row.activeBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -1, 1)
    row.activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.24, 0.94, 0.82, 0.43, 0)
    row.activeBar = row:CreateTexture(nil, "ARTWORK"); row.activeBar:SetTexture(SOLID)
    row.activeBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    row.activeBar:SetPoint("TOPLEFT", row, "TOPLEFT", 1, -1); row.activeBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 1, 1)
    row.activeBar:SetWidth(3)

    row.name = row:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(row.name, 13)
    row.name:SetPoint("LEFT", row, "LEFT", 10, 0)
    row.name:SetWidth(130)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetTextColor(1, 1, 1)

    row.count = row:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(row.count, 11)
    row.count:SetPoint("LEFT", row.name, "RIGHT", 4, 0)
    row.count:SetWidth(50)
    row.count:SetJustifyH("LEFT")
    row.count:SetTextColor(0.667, 0.690, 0.831)

    row.loadBtn = UI.MakeButton(row, "Load", {
        w = 48, h = 20, variant = "gold",
        onClick = function()
            local b = row.build; if not b then return end
            local removeOrder, addOrder, addCost = PlanBuildLoad(b)
            local nr, na = #removeOrder, #addOrder
            if nr == 0 and na == 0 then
                ChatInfo("Build '" .. b.name .. "' already matches your tree.")
                return
            end
            local tokens = AT.prestigeTokens or 0
            if addCost > tokens and nr == 0 then
                ChatInfo(string.format(
                    "Loading '%s' needs %d tokens — you have %d.",
                    b.name, addCost, tokens))
                return
            end
            local lines = { string.format(
                "Load build '|cff1eff00%s|r'?", b.name) }
            if nr > 0 then
                lines[#lines+1] = string.format(
                    "|cffff8888Remove %d node(s)|r currently unlocked.", nr)
            end
            if na > 0 then
                lines[#lines+1] = string.format(
                    "|cff88ff88Unlock %d node(s)|r — cost: |cffFFD700%d Token%s|r",
                    na, addCost, addCost == 1 and "" or "s")
            end
            lines[#lines+1] = "You have: " .. tokens
            local msg = table.concat(lines, "\n")
            StaticPopup_Show("AT_BUILD_LOAD", msg, nil, {
                removeOrder = removeOrder,
                addOrder    = addOrder,
                name        = b.name,
            })
        end,
    })
    row.loadBtn:SetPoint("RIGHT", row, "RIGHT", -122, 0)

    row.exportBtn = UI.MakeButton(row, "Export", {
        w = 60, h = 20, variant = "secondary",
        onClick = function()
            local b = row.build; if not b then return end
            ShowExport(EncodeBuild(b))
        end,
    })
    row.exportBtn:SetPoint("RIGHT", row, "RIGHT", -58, 0)

    row.deleteBtn = UI.MakeButton(row, "X", {
        w = 26, h = 20, variant = "danger",
        onClick = function()
            local b = row.build; if not b then return end
            StaticPopup_Show("AT_BUILD_DELETE", b.name, nil, b)
        end,
    })
    row.deleteBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    return row
end

local function BuildPanel()
    if panel then return panel end

    panel = UI.MakePanel(UIParent, PANEL_W, PANEL_H, {
        title = "Astral Tree — Builds",
    })
    if not panel then return nil end
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(100)
    panel:Hide()
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    if not panel.GetScript or not panel:GetScript("OnKeyDown") then
        panel:EnableKeyboard(true)
        panel:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
        end)
    end

    NavyWindow(panel, "Astral Tree — Builds", "Save, load, import or export named builds")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
    UI.CosmicCloseButton(close)

    local listFrame = CreateFrame("Frame", nil, panel)
    listFrame:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -64)
    listFrame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -64)
    listFrame:SetHeight(NUM_ROWS * ROW_H + 4)

    local scroll = CreateFrame("ScrollFrame", "AT_BuildScroll", listFrame,
                                "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT")
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    panel.scroll = scroll

    local rows = {}
    for i = 1, NUM_ROWS do
        rows[i] = MakeRow(listFrame, i)
        if i == 1 then
            rows[i]:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, 0)
        else
            rows[i]:SetPoint("TOPLEFT", rows[i-1], "BOTTOMLEFT", 0, -2)
        end
    end

    local empty = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(empty, 12)
    empty:SetTextColor(0.667, 0.690, 0.831)
    empty:SetPoint("CENTER", listFrame, "CENTER", 0, 0)
    empty:SetText("|cffaab0d4No saved builds yet — use 'Save Current' below.|r")
    panel.empty = empty

    function panel:Refresh()
        local builds = GetBuilds()
        local count  = #builds
        local offset = FauxScrollFrame_GetOffset(scroll) or 0
        for i = 1, NUM_ROWS do
            local r  = rows[i]
            local b  = builds[offset + i]
            if b then
                r.build = b
                r.name:SetText(b.name)
                local active = AT.TreeBuilds and AT.TreeBuilds.IsActive(b)
                if active then r.activeBg:Show(); r.activeBar:Show() else r.activeBg:Hide(); r.activeBar:Hide() end
                r.count:SetText(active and "|cffffd970Active|r" or ("|cffaab0d4" .. #b.ids .. " nodes|r"))
                r:Show()
            else
                r.build = nil
                r:Hide()
            end
        end
        empty:SetShown_(count == 0)
        FauxScrollFrame_Update(scroll, count, NUM_ROWS, ROW_H)
    end
    -- 3.3.5 has no Frame:SetShown; local polyfill.
    empty.SetShown_ = function(self, b)
        if b then self:Show() else self:Hide() end
    end

    scroll:SetScript("OnVerticalScroll", function(self, off)
        FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, function()
            panel:Refresh()
        end)
    end)

    local saveBtn = UI.MakeButton(panel, "Save Current", {
        w = 112, h = 24, variant = "gold",
        onClick = function()
            StaticPopup_Show("AT_BUILD_SAVE_NAME")
        end,
    })
    saveBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 14, 14)

    local importBtn = UI.MakeButton(panel, "Import", {
        w = 84, h = 24, variant = "secondary",
        onClick = ShowImport,
    })
    importBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

    local closeBtn = UI.MakeButton(panel, "Close", {
        w = 84, h = 24, variant = "secondary",
        onClick = function() panel:Hide() end,
    })
    closeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -14, 14)

    return panel
end

-- ── API for Loadouts (Builds > Loadouts) ───────────────────────────
-- Planning needs the tree's nodes and the unlocked state from the server: without
-- them every unlocked node would look like it has to be removed.
local TB = {}
AT.TreeBuilds = TB

function TB.Ready()
    return AT.dataVersion ~= nil and AT.nodes ~= nil and next(AT.nodes) ~= nil
end

-- asks the server for the tree if it hasn't been loaded this session
function TB.EnsureData()
    if TB.Ready() then return true end
    -- ask again if an earlier request got no answer within 5 s
    if AT.RequestInitialStateAIO and (not TB._askedAt or GetTime() - TB._askedAt > 5) then
        TB._askedAt = GetTime()
        AT.RequestInitialStateAIO()
    end
    return false
end

function TB.List()
    local out = {}
    for _, b in ipairs(GetBuilds()) do
        if b.name and b.ids then out[#out + 1] = b end
    end
    return out
end

function TB.Find(name)
    for _, b in ipairs(GetBuilds()) do
        if b.name == name and b.ids then return b end
    end
end

function TB.Plan(b) return PlanBuildLoad(b) end

function TB.IsActive(b)
    if not TB.Ready() then return false end
    local removeOrder, addOrder = PlanBuildLoad(b)
    return #removeOrder == 0 and #addOrder == 0
end

-- a load is in flight until the server answers (AstralTree.lua clears it)
function TB.IsBusy()
    if AT.__lastLoadBuild and TB._sentAt and GetTime() - TB._sentAt > 30 then
        AT.__lastLoadBuild = nil   -- no answer: don't block forever
    end
    return AT.__lastLoadBuild ~= nil
end

-- loads the build without a confirmation; returns ok, reason
function TB.Load(b)
    if not TB.Ready() then return false, "Astral Tree not loaded yet" end
    local removeOrder, addOrder, addCost = PlanBuildLoad(b)
    if #removeOrder == 0 and #addOrder == 0 then return true end
    local tokens = AT.prestigeTokens or 0
    if addCost > tokens and #removeOrder == 0 then
        return false, string.format("needs %d tokens, you have %d", addCost, tokens)
    end
    TB._sentAt = GetTime()
    AT.LoadBuild(removeOrder, addOrder, "build '" .. (b.name or "?") .. "'")
    return true
end

function AT.ToggleBuildManager()
    local p = BuildPanel()
    if not p then return end
    if p:IsShown() then
        p:Hide()
    else
        p:Refresh()
        p:Show()
        if UI.SkinTree then UI.SkinTree(p) end
    end
end

-- the "Active" highlight follows unlocks, removals and loaded builds
if AT.OnStatsChanged then
    AT.OnStatsChanged(function() if panel and panel:IsShown() then panel:Refresh() end end)
end
