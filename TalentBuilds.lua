
local PA = ProjectAstral
local UI = PA.UI

-- Talent Builds tab (Builds section): save the class talents you have spent under a
-- name, load them again (the game's talent reset, then one point at a time, each
-- waiting for the client to accept it), share them as text, and pick one build per
-- character that gets one point on every level-up. Ported from the standalone
-- TalentBuildManager addon; builds are now account-wide (ProjectAstralTalentBuilds)
-- and the list shows the ones for your class. The "Builds" button in the Blizzard
-- talent window opens this tab.
-- Colours that must survive Theme.lua's vivid-text pass are inline |c codes.

local ROW_H    = 56
local NUM_ROWS = 10
local CONFIRM_WINDOW = 3
local DONE_HOLD      = 8
local UPDATE_INTERVAL = 0.15
local TALENT_TIMEOUT  = 8
local EXPORT_PREFIX   = "TBUILD:1:"

local SOLID = "Interface\\Buttons\\WHITE8X8"
local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"
local HEX_BAD   = "|cffff9a8f"
local HEX_BTN   = "|cffffe39a"

local host
local rows = {}
local RefreshList
local exportDialog, importDialog
local loadState
local runner = CreateFrame("Frame")
local autoRunner = CreateFrame("Frame")
local autoLevelRequests = {}

local function ChatInfo(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd970[Talent Builds]|r " .. msg)
end

-- ── saved data ──────────────────────────────────────────────────────
local function Store()
    ProjectAstralTalentBuilds = ProjectAstralTalentBuilds or {}
    local s = ProjectAstralTalentBuilds
    s.builds   = s.builds or {}
    s.leveling = s.leveling or {}    -- [character key] = build name (that character's class)
    return s
end
local function Builds() return Store().builds end

local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function ClassToken() local _, token = UnitClass("player"); return token end

local function FindBuild(name, class)
    local lower = name:lower()
    for i, b in ipairs(Builds()) do
        if (b.name or ""):lower() == lower and b.class == class then return b, i end
    end
end

local function ClassBuilds()
    local class, list, others = ClassToken(), {}, 0
    for _, b in ipairs(Builds()) do
        if b.class == class then list[#list + 1] = b else others = others + 1 end
    end
    table.sort(list, function(a, b) return (a.savedAt or 0) > (b.savedAt or 0) end)
    return list, others
end

local function LevelingBuild()
    local name = Store().leveling[CharKey()]
    return name and FindBuild(name, ClassToken())
end

-- ── talent helpers (from TalentBuildManager) ───────────────────────
local function GetActiveGroup() return GetActiveTalentGroup and GetActiveTalentGroup() or nil end
local function GetRank(tab, index) local _, _, _, _, rank = GetTalentInfo(tab, index); return tonumber(rank) or 0 end

local function GetTalentTotal()
    local total = 0
    for tab = 1, GetNumTalentTabs() do
        for index = 1, GetNumTalents(tab) do total = total + GetRank(tab, index) end
    end
    return total
end

local function CaptureBuild(name, ranks)   -- ranks: optional [tab][index] = rank (import)
    local class = ClassToken()
    if not class or not GetNumTalentTabs or not GetNumTalents or not GetTalentInfo then
        return nil, "Talent information is not available yet."
    end
    local snapshot = { version = 1, name = name, class = class, trees = {} }
    for tab = 1, GetNumTalentTabs() do
        local tree = { name = (GetTalentTabInfo(tab)) or tostring(tab), talents = {} }
        for index = 1, GetNumTalents(tab) do
            local talentName, _, tier, column, rank, maxRank = GetTalentInfo(tab, index)
            if ranks then rank = ranks[tab] and ranks[tab][index] or 0 end
            tree.talents[index] = {
                name = talentName or "", tier = tonumber(tier) or 0, column = tonumber(column) or 0,
                rank = tonumber(rank) or 0, maxRank = tonumber(maxRank) or 0,
            }
        end
        snapshot.trees[tab] = tree
    end
    return snapshot
end

local function ValidateBuild(build)
    if type(build) ~= "table" or build.version ~= 1 or type(build.trees) ~= "table" then
        return false, "This saved build has an unsupported format."
    end
    if build.class ~= ClassToken() then return false, "This build belongs to another class." end
    if #build.trees ~= GetNumTalentTabs() then
        return false, "The talent tree layout has changed; this build cannot be loaded."
    end
    for tab = 1, GetNumTalentTabs() do
        local tree = build.trees[tab]
        if type(tree) ~= "table" or type(tree.talents) ~= "table" or #tree.talents ~= GetNumTalents(tab) then
            return false, "The talent tree layout has changed; this build cannot be loaded."
        end
        for index = 1, GetNumTalents(tab) do
            local name, _, tier, column, _, maxRank = GetTalentInfo(tab, index)
            local saved = tree.talents[index]
            if type(saved) ~= "table" or saved.name ~= name then
                return false, "Talent data no longer matches this saved build."
            end
            if type(saved.rank) ~= "number" or saved.rank < 0 or saved.rank > (tonumber(maxRank) or 0) then
                return false, "This saved build contains an invalid talent rank."
            end
            saved.tier = tonumber(tier) or saved.tier or 0
            saved.column = tonumber(column) or saved.column or 0
        end
    end
    return true
end

local function BuildMatchesCurrent(build)
    if build.class ~= ClassToken() or #build.trees ~= GetNumTalentTabs() then return false end
    for tab, tree in ipairs(build.trees) do
        for index, talent in ipairs(tree.talents) do
            if GetRank(tab, index) ~= talent.rank then return false end
        end
    end
    return true
end

local function MakeLoadQueue(build)
    local queue = {}
    for tab, tree in ipairs(build.trees) do
        for index, talent in ipairs(tree.talents) do
            for rank = 1, talent.rank do
                queue[#queue + 1] = { tab = tab, index = index, tier = talent.tier or 0,
                                      column = talent.column or 0, rank = rank, name = talent.name }
            end
        end
    end
    table.sort(queue, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.tab ~= b.tab then return a.tab < b.tab end
        if a.column ~= b.column then return a.column < b.column end
        if a.index ~= b.index then return a.index < b.index end
        return a.rank < b.rank
    end)
    return queue
end

local function FindNextBuildPoint(build)
    for _, point in ipairs(MakeLoadQueue(build)) do
        if GetRank(point.tab, point.index) < point.rank then return point end
    end
end

local function TreePoints(build)
    local parts, total = {}, 0
    for tab, tree in ipairs(build.trees or {}) do
        local n = 0
        for _, t in ipairs(tree.talents or {}) do n = n + (tonumber(t.rank) or 0) end
        parts[tab] = n
        total = total + n
    end
    return parts, total
end

local function MainTree(build)
    local parts, best = TreePoints(build), 1
    for tab, n in ipairs(parts) do if n > (parts[best] or 0) then best = tab end end
    return best
end

-- ── action bar: status and loading progress ────────────────────────
local function SetStatus(text, hex)
    if not (host and host.bar) then return end
    host.bar.fill:Hide()
    host.bar.counter:SetText("")
    host.bar.text:SetText((hex or HEX_MUTED) .. text .. "|r")
    host.bar._holdUntil = nil
end

local function ShowProgress(state, text, done)
    if not (host and host.bar) then return end
    local bar = host.bar
    local total = math.max(state.total or 1, 1)
    local completed = done and total or (state.completed or 0)
    bar.fill:SetWidth(math.max(1, (bar:GetWidth() - 8) * completed / total))
    if done then
        local ok = done == "ok"
        bar.fill:SetVertexColor(ok and 0.50 or 1.00, ok and 0.88 or 0.80, ok and 0.63 or 0.40, 0.55)
        bar._holdUntil = GetTime() + DONE_HOLD
    else
        bar.fill:SetVertexColor(0.886, 0.753, 0.384, 0.45)
        bar._holdUntil = nil
    end
    bar.fill:Show()
    bar.text:SetText(text)
    bar.counter:SetText(HEX_MUTED .. completed .. " / " .. total .. "|r")
end

local function FinishLoad(message, ok)
    local state = loadState
    loadState = nil
    runner:SetScript("OnUpdate", nil)
    if state then
        ShowProgress(state, (ok and HEX_GOOD or HEX_WARN) .. message .. "|r", ok and "ok" or "fail")
    end
    ChatInfo(message)
    if RefreshList then RefreshList() end
end

local function StartAllocations(build, group)
    local queue = MakeLoadQueue(build)
    loadState = { build = build, queue = queue, position = 1, nextUpdate = 0, group = group,
                  total = #queue, completed = 0 }
    if #queue == 0 then
        FinishLoad("Build '" .. build.name .. "' loaded; no talent points were needed.", true)
        return
    end
    runner:SetScript("OnUpdate", function(_, elapsed)
        local state = loadState
        if not state then return end
        state.nextUpdate = state.nextUpdate - elapsed
        if state.nextUpdate > 0 then return end
        state.nextUpdate = UPDATE_INTERVAL

        if UnitAffectingCombat("player") then
            FinishLoad("Stopped because you entered combat. Some talents may have been applied.")
            return
        end
        if state.group and GetActiveGroup() ~= state.group then
            FinishLoad("Stopped because the active talent group changed.")
            return
        end
        if state.waiting then
            local pending = state.waiting
            if GetRank(pending.tab, pending.index) >= pending.rank then
                state.completed = state.completed + 1
                state.waiting = nil
                state.position = state.position + 1
            elseif GetTime() >= pending.deadline then
                FinishLoad("A talent was not accepted by the client. The build stopped here.")
                return
            else
                return
            end
        end
        local point = state.queue[state.position]
        if not point then
            FinishLoad("Build '" .. state.build.name .. "' loaded.", true)
            return
        end
        if GetRank(point.tab, point.index) >= point.rank then
            state.completed = state.completed + 1
            state.position = state.position + 1
            return
        end
        ShowProgress(state, HEX_GOLD .. "Loading '" .. state.build.name .. "'|r" .. HEX_MUTED .. "  ·  Learning "
            .. (point.name or "talent") .. " (rank " .. point.rank .. ")…|r")
        local ok, result = pcall(LearnTalent, point.tab, point.index)
        if not ok or result == false then
            FinishLoad("The client rejected a talent allocation. The build stopped here.")
            return
        end
        state.waiting = { tab = point.tab, index = point.index, rank = point.rank,
                          deadline = GetTime() + TALENT_TIMEOUT }
    end)
end

local function LoadBuild(build)
    if loadState then SetStatus("A build is already being loaded. Wait for it to finish.", HEX_WARN); return end
    if UnitAffectingCombat("player") then SetStatus("Leave combat before loading a talent build.", HEX_WARN); return end
    if not LearnTalent then SetStatus("This client does not expose the talent allocation API.", HEX_BAD); return end
    local valid, reason = ValidateBuild(build)
    if not valid then SetStatus(reason, HEX_BAD); return end
    if BuildMatchesCurrent(build) then SetStatus("'" .. build.name .. "' is already active.", HEX_GOOD); return end

    local group = GetActiveGroup()
    if GetTalentTotal() == 0 then StartAllocations(build, group); RefreshList(); return end
    -- talents already spent: ask first, then reset them for free with the server's
    -- command (the same one as the talent window's Reset Talents button)
    StaticPopup_Show("PA_TALENT_BUILD_LOAD", build.name, nil, build)
end

local function ResetAndLoad(build)
    if loadState or UnitAffectingCombat("player") then return end
    local group = GetActiveGroup()
    loadState = { phase = "reset", build = build, group = group, deadline = GetTime() + 15,
                  nextUpdate = 0, total = #MakeLoadQueue(build), completed = 0 }
    ShowProgress(loadState, HEX_GOLD .. "Loading '" .. build.name .. "'|r" .. HEX_MUTED .. "  ·  Resetting your talents…|r")
    if ResetTalentPoints then
        if not pcall(ResetTalentPoints) then
            FinishLoad("The talent reset could not be started.")
            return
        end
    else
        SendChatMessage(".talents reset", "SAY")
    end
    runner:SetScript("OnUpdate", function(_, elapsed)
        local state = loadState
        if not state then return end
        state.nextUpdate = state.nextUpdate - elapsed
        if state.nextUpdate > 0 then return end
        state.nextUpdate = UPDATE_INTERVAL
        if UnitAffectingCombat("player") then
            FinishLoad("Loading canceled because you entered combat.")
        elseif state.group and GetActiveGroup() ~= state.group then
            FinishLoad("Loading canceled because the active talent group changed.")
        elseif GetTalentTotal() == 0 then
            StartAllocations(state.build, state.group)
        elseif GetTime() >= state.deadline then
            FinishLoad("Your talents were not reset; the build was not loaded.")
        end
    end)
    RefreshList()
end

StaticPopupDialogs["PA_TALENT_BUILD_LOAD"] = {
    text         = "Load talent build '%s'?\n\nYour talents are reset (free of charge), then the build's points are spent one by one.",
    button1      = "Load",
    button2      = "Cancel",
    OnAccept     = function(_, build) if build then ResetAndLoad(build) end end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
}

-- ── one point per level-up for the character's leveling build ──────
local function FinishAutoLevelRequest(message)
    table.remove(autoLevelRequests, 1)
    if message then ChatInfo(message) end
    if #autoLevelRequests == 0 then autoRunner:SetScript("OnUpdate", nil) end
end

local function RunAutoLevelRequest()
    local request = autoLevelRequests[1]
    if not request then autoRunner:SetScript("OnUpdate", nil); return end
    if loadState then return end
    if request.group and GetActiveGroup() ~= request.group then
        FinishAutoLevelRequest("Automatic allocation canceled because the active talent group changed.")
        return
    end
    if request.waiting then
        local pending = request.waiting
        if GetRank(pending.tab, pending.index) >= pending.rank then
            FinishAutoLevelRequest("Applied one leveling point from your leveling build.")
        elseif GetTime() >= pending.deadline then
            FinishAutoLevelRequest("Automatic talent allocation timed out; this level's point was not applied.")
        end
        return
    end
    if GetTime() < request.readyAt then return end
    local build = LevelingBuild()
    if not build then wipe(autoLevelRequests); autoRunner:SetScript("OnUpdate", nil); return end
    local valid, reason = ValidateBuild(build)
    if not valid then FinishAutoLevelRequest("Automatic allocation stopped: " .. reason); return end
    if not GetUnspentTalentPoints or (GetUnspentTalentPoints() or 0) < 1 then
        if GetTime() >= request.deadline then
            FinishAutoLevelRequest("No talent point became available for automatic allocation.")
        end
        return
    end
    local point = FindNextBuildPoint(build)
    if not point then
        wipe(autoLevelRequests); autoRunner:SetScript("OnUpdate", nil)
        ChatInfo("Your leveling build is complete. It stays selected in case you reset your talents.")
        return
    end
    local ok, result = pcall(LearnTalent, point.tab, point.index)
    if not ok or result == false then
        FinishAutoLevelRequest("The client could not queue the automatic talent point.")
        return
    end
    request.waiting = { tab = point.tab, index = point.index, rank = point.rank, deadline = GetTime() + TALENT_TIMEOUT }
end

local function QueueAutoLevelPoint(level)
    if not LevelingBuild() then return end
    if (tonumber(level) or UnitLevel("player")) < 10 then return end
    local now = GetTime()
    autoLevelRequests[#autoLevelRequests + 1] = { group = GetActiveGroup(), readyAt = now + 0.5, deadline = now + 20 }
    autoRunner:SetScript("OnUpdate", RunAutoLevelRequest)
end

-- ── save / delete / leveling / export / import ─────────────────────
local function Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function SaveCurrent()
    if not host then return end
    local name = Trim(host.nameBox:GetText())
    if name == "" then
        SetStatus("Type a name for this build first.", HEX_WARN)
        host.nameBox.edit:SetFocus()
        return
    end
    local snapshot, reason = CaptureBuild(name)
    if not snapshot then SetStatus(reason, HEX_BAD); return end
    local existing = FindBuild(name, snapshot.class)
    local build = existing or {}
    build.version, build.name, build.class, build.trees = 1, name, snapshot.class, snapshot.trees
    local className = UnitClass("player")
    build.className, build.savedBy = className, UnitName("player")
    build.savedAt, build.date = time(), date("%Y-%m-%d")
    if not existing then table.insert(Builds(), build) end
    host.nameBox:Clear()
    host.nameBox.edit:ClearFocus()
    local _, total = TreePoints(build)
    SetStatus(string.format("%s build '%s' (%d points).", existing and "Updated" or "Saved", name, total), HEX_GOOD)
    RefreshList()
end

local function DeleteBuild(b)
    for i, other in ipairs(Builds()) do
        if other == b then
            table.remove(Builds(), i)
            local lv = Store().leveling
            for key, name in pairs(lv) do
                if name == b.name and not FindBuild(name, b.class) then lv[key] = nil end
            end
            SetStatus("Deleted build '" .. (b.name or "?") .. "'.", HEX_WARN)
            RefreshList()
            return
        end
    end
end

local function ToggleLeveling(b)
    local lv = Store().leveling
    local key = CharKey()
    if lv[key] == b.name then
        lv[key] = nil
        SetStatus("Automatic leveling allocation is off for this character.", HEX_MUTED)
    else
        lv[key] = b.name
        SetStatus("'" .. b.name .. "' will get one talent point on each future level-up.", HEX_GOOD)
    end
    wipe(autoLevelRequests)
    RefreshList()
end

local function EncodeBuild(b)
    local trees = {}
    for tab, tree in ipairs(b.trees or {}) do
        local digits = {}
        for i, t in ipairs(tree.talents or {}) do digits[i] = tostring(math.min(9, tonumber(t.rank) or 0)) end
        trees[tab] = table.concat(digits)
    end
    return EXPORT_PREFIX .. (b.class or "?") .. ":" .. table.concat(trees, "/")
end

local function DecodeBuild(text)
    text = (text or ""):gsub("%s+", "")
    local class, body = text:match("^TBUILD:1:(%u+):([%d/]+)$")
    if not class then return nil, "That isn't a talent build (it should start with TBUILD:1:)." end
    if class ~= ClassToken() then return nil, "That build is for another class (" .. class .. ")." end
    local ranks, tab = {}, 0
    for part in (body .. "/"):gmatch("([^/]*)/") do
        tab = tab + 1
        ranks[tab] = {}
        for i = 1, #part do ranks[tab][i] = tonumber(part:sub(i, i)) end
    end
    if tab ~= GetNumTalentTabs() then return nil, "That build doesn't match your talent trees." end
    for t = 1, tab do
        if #ranks[t] ~= GetNumTalents(t) then return nil, "That build doesn't match your talent trees." end
    end
    return ranks
end

local function ShowExport(b)
    if not UI.MakeTextDialog then return end
    if not exportDialog then
        exportDialog = UI.MakeTextDialog({
            name = "PATalentBuildExportDialog", title = "Export Talent Build",
            subtitle = "Ctrl+A to select all, Ctrl+C to copy, then share it.", button1Label = "Close",
        })
    end
    exportDialog.header.title:SetText("Export: " .. (b.name or "?"))
    exportDialog:Show()
    exportDialog.editBox:SetText(EncodeBuild(b))
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
    local parts = TreePoints(b)
    exportDialog.status:SetText(table.concat(parts, "/") .. " talent points, saved by "
        .. (b.savedBy or "?") .. " on " .. (b.date or "?") .. ".")
end

local function ShowImport()
    if not UI.MakeTextDialog then return end
    if not importDialog then
        importDialog = UI.MakeTextDialog({
            name = "PATalentBuildImportDialog", title = "Import Talent Build",
            subtitle = "Paste a talent build (TBUILD:1:...) for your class to save it.",
            button1Label = "Save Build",
            onAccept = function(text, dlg)
                local ranks, reason = DecodeBuild(text)
                if not ranks then
                    dlg.status:SetText(HEX_BAD .. reason .. "|r")
                    return true
                end
                local base = Trim(host and host.nameBox:GetText() or "")
                if base == "" then base = "Imported build" end
                local name, n = base, 2
                while FindBuild(name, ClassToken()) do name = base .. " (" .. n .. ")"; n = n + 1 end
                local snapshot = CaptureBuild(name, ranks)
                if not snapshot then return true end
                snapshot.className = UnitClass("player")
                snapshot.savedBy, snapshot.savedAt, snapshot.date = "Imported", time(), date("%Y-%m-%d")
                table.insert(Builds(), snapshot)
                if host then host.nameBox:Clear() end
                SetStatus("Imported build '" .. name .. "'.", HEX_GOOD)
                RefreshList()
                return false
            end,
        })
    end
    importDialog.status:SetText("Tip: type a name in the Talent Builds tab first to name the imported build.")
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
end

-- ── rows ───────────────────────────────────────────────────────────
local function ConfirmButton(r, btn, label, prompt, action)
    btn:SetScript("OnClick", function()
        local b = r.build
        if not b then return end
        if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then
            btn._confirmAt = nil
            action(b)
        else
            btn._confirmAt = GetTime()
            btn:SetLabel("Sure?")
            SetStatus(string.format(prompt, b.name or "?"), HEX_WARN)
        end
    end)
    btn._idleLabel = label
end

local function ResetConfirm(btn)
    if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then return end
    btn._confirmAt = nil
    btn:SetLabel(btn._idleLabel)
end

local function ShowPreview(r)
    local b = r.build
    if not b then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name or "?", 1, 1, 1)
    GameTooltip:AddLine("Saved by " .. (b.savedBy or "?") .. " on " .. (b.date or "?"), 0.75, 0.77, 0.88)
    GameTooltip:AddLine(" ")
    local parts = TreePoints(b)
    for tab, tree in ipairs(b.trees or {}) do
        GameTooltip:AddDoubleLine(tree.name or ("Tree " .. tab), parts[tab] .. " points", 0.86, 0.87, 0.94, 1, 0.85, 0.44)
        for _, t in ipairs(tree.talents or {}) do
            if (t.rank or 0) > 0 then
                GameTooltip:AddDoubleLine("   " .. (t.name or "?"), t.rank .. "/" .. (t.maxRank or "?"), 0.80, 0.82, 0.92, 1, 1, 1)
            end
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Load resets your talents (free, after a confirmation) and spends the points one by one.",
        0.55, 0.88, 0.63, true)
    GameTooltip:Show()
end

local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -((i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((i - 1) * ROW_H))
    UI.MakeRowChrome(r)
    r:HookScript("OnEnter", ShowPreview)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)

    if i % 2 == 0 then
        local alt = r:CreateTexture(nil, "BACKGROUND"); alt:SetTexture(SOLID); alt:SetAllPoints(r)
        alt:SetVertexColor(1, 1, 1, 0.022)
    end
    if i > 1 then
        local d = r:CreateTexture(nil, "BORDER"); d:SetTexture(SOLID)
        d:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        d:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1); d:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1); d:SetHeight(1)
    end
    -- active build: the same warm tint and bar as Gem Builds' equipped build
    r.activeBg = r:CreateTexture(nil, "BACKGROUND"); r.activeBg:SetTexture(SOLID); r.activeBg:SetAllPoints(r)
    r.activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    r.activeBar = r:CreateTexture(nil, "ARTWORK"); r.activeBar:SetTexture(SOLID)
    r.activeBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    r.activeBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.activeBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.activeBar:SetWidth(3)

    r.iconFrame = UI.MakeIconFrame(r, { size = 36 })
    r.iconFrame:SetPoint("LEFT", r, "LEFT", 10, 0)

    r.del = UI.MakeButton(r, "Delete", { w = 70, h = 24, variant = "danger" })
    r.del:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    ConfirmButton(r, r.del, "Delete", "Click Sure? to delete '%s'.", DeleteBuild)

    r.export = UI.MakeButton(r, "Export", { w = 70, h = 24, variant = "secondary",
        onClick = function() if r.build then ShowExport(r.build) end end })
    r.export:SetPoint("RIGHT", r.del, "LEFT", -5, 0)

    r.load = UI.MakeButton(r, "Load", { w = 78, h = 24, variant = "gold",
        onClick = function() if r.build then LoadBuild(r.build) end end })
    r.load:SetPoint("RIGHT", r.export, "LEFT", -10, 0)

    r.level = UI.MakeFilterChip(r, 84, "Leveling", function() if r.build then ToggleLeveling(r.build) end end)
    r.level:SetPoint("RIGHT", r.load, "LEFT", -10, 0)
    r.level:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Leveling build", 1, 1, 1)
        GameTooltip:AddLine("When on, this character spends one point of this build on every level-up. One leveling build per character.",
            0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)

    r.name = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.name, 14)
    r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 10, 2)
    r.name:SetPoint("RIGHT", r.level, "LEFT", -10, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)

    r.sub = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.sub, 11)
    r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 10, -3)
    r.sub:SetPoint("RIGHT", r.level, "LEFT", -10, 0)
    r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)

    r:Hide()
    return r
end

RefreshList = function()
    if not host then return end
    local list, others = ClassBuilds()
    local offset = FauxScrollFrame_GetOffset(host.scroll)
    local busy = loadState ~= nil
    local leveling = Store().leveling[CharKey()]

    for i = 1, NUM_ROWS do
        local r = rows[i]
        local b = list[i + offset]
        if r.build ~= b then r.del._confirmAt = nil end
        r.build = b
        ResetConfirm(r.del)
        if b then
            local active = BuildMatchesCurrent(b)
            -- every row has Gem Stash's gold look; the active one a stronger tint
            r.activeBg:Show(); r.activeBar:Show()
            r.activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, active and 0.30 or 0.14, 0.94, 0.82, 0.43, 0)
            r.name:SetText(b.name or "?")
            local parts = TreePoints(b)
            local main = MainTree(b)
            local spread = {}
            for tab, n in ipairs(parts) do spread[tab] = (tab == main) and (HEX_GOLD .. n .. "|r") or tostring(n) end
            local mainName = b.trees[main] and b.trees[main].name or ""
            r.sub:SetText((active and (HEX_GOLD .. "Active|r" .. HEX_DIM .. "  ·  |r") or "")
                .. HEX_MUTED .. table.concat(spread, HEX_DIM .. "/|r" .. HEX_MUTED) .. "  " .. mainName .. "|r"
                .. HEX_DIM .. "  ·  " .. (b.savedBy or "?") .. "  ·  " .. (b.date or "") .. "|r")
            local _, icon = GetTalentTabInfo(main)
            r.iconFrame:SetTexture(icon or "Interface\\Icons\\INV_Misc_Book_09")
            r.iconFrame:SetQuality(4)
            r.level:SetActive(leveling == b.name)
            if busy then r.load:SetDisabledLook(true); r.load:SetLabel(HEX_DIM .. "Load|r")
            else r.load:SetDisabledLook(false); r.load:SetLabel(HEX_BTN .. "Load|r") end
            r:Show()
        else
            r:Hide()
        end
    end

    FauxScrollFrame_Update(host.scroll, #list, NUM_ROWS, ROW_H)
    local className = UnitClass("player") or ""
    host.countText:SetText(HEX_GOLD .. #list .. "|r" .. HEX_MUTED .. " " .. className .. (#list == 1 and " build" or " builds")
        .. (others > 0 and (HEX_DIM .. "  ·  " .. others .. " for other classes") or "") .. "|r")
    if #list == 0 then host.empty:Show() else host.empty:Hide() end
end

local function AddTip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildTalentBuildsTab(panel)
    host = panel
    local SIDE, top = 10, -8

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID); ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    local nameBox = UI.MakeSearchBox(panel, { width = 300, height = 26, placeholder = "Name this build…" })
    UI.SetTextFont(nameBox.edit, 13)
    UI.StyleFilterSearch(nameBox)
    nameBox.__paBackdrop = true
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top)
    nameBox.edit:SetScript("OnEnterPressed", function() SaveCurrent() end)
    panel.nameBox = nameBox

    local saveBtn = UI.MakeButton(panel, "Save current", { w = 140, h = 26, variant = "gold",
        onClick = function() SaveCurrent() end })
    saveBtn:SetLabel(HEX_BTN .. "Save current|r")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    AddTip(saveBtn, "Save current talents",
        "Saves the talents spent right now under the name you typed. Saving with an existing name updates that build.")

    local importBtn = UI.MakeButton(panel, "Import", { w = 90, h = 26, variant = "secondary",
        onClick = function() ShowImport() end })
    importBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    AddTip(importBtn, "Import talent build", "Paste a talent build someone shared (TBUILD:1:...) for your class.")

    panel.countText = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.countText, 13)
    panel.countText:SetPoint("RIGHT", panel, "TOPRIGHT", -SIDE - 2, top - 13)
    panel.countText:Hide()   -- build count removed from the header (kept for the refresh code)

    -- opens the Blizzard talent window; the hub closes so it isn't hidden behind it
    -- (the window's Builds button comes back here)
    local talentsBtn = UI.MakeButton(panel, "Open Talent Menu", { w = 150, h = 26, variant = "secondary",
        onClick = function()
            if not IsAddOnLoaded("Blizzard_TalentUI") then LoadAddOn("Blizzard_TalentUI") end
            if PlayerTalentFrame and not PlayerTalentFrame:IsShown() then
                if ToggleTalentFrame then ToggleTalentFrame() else ShowUIPanel(PlayerTalentFrame) end
            end
            local mf = PA.mainFrame
            if mf and mf:IsShown() then
                if mf.AnimatedHide then mf:AnimatedHide() else mf:Hide() end
            end
        end })
    talentsBtn:SetPoint("LEFT", importBtn, "RIGHT", 6, 0)   -- after Import: a long build count can't push it over
    AddTip(talentsBtn, "Open Talent Menu", "Opens the game's talent window. Its Builds button brings you back here.")

    -- action bar: status, or the loading progress
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(38)
    bar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  SIDE,  top - 34)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, top - 34)
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
    bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true
    panel.bar = bar
    bar.fill = bar:CreateTexture(nil, "ARTWORK"); bar.fill:SetTexture(SOLID)
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4); bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 4)
    bar.fill:SetWidth(1); bar.fill:Hide()
    bar.counter = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.counter, 12)
    bar.counter:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    bar.text = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.text, 12)
    bar.text:SetPoint("LEFT", bar, "LEFT", 12, 0)
    bar.text:SetPoint("RIGHT", bar.counter, "LEFT", -10, 0)
    bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)

    local IDLE = "Spend your talents, name the build and click Save current. "
        .. "Turn on Leveling to spend one point of a build on every level-up."
    SetStatus(IDLE)
    bar:SetScript("OnUpdate", function(self)
        if self._holdUntil and GetTime() > self._holdUntil and not loadState then SetStatus(IDLE) end
    end)

    -- list
    local listPanel = CreateFrame("Frame", nil, panel)
    listPanel:SetPoint("TOPLEFT",     bar,   "BOTTOMLEFT",  0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, 10)
    UI.AstralBackdrop(listPanel, { thin = true })
    listPanel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)   -- same dark grey as the Gem Stash list
    listPanel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    listPanel.__paBackdrop = true

    local scroll = CreateFrame("ScrollFrame", "PATalentBuildsScroll", listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)
    panel.scroll = scroll

    local listFrame = CreateFrame("Frame", nil, listPanel)
    listFrame:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    for i = 1, NUM_ROWS do rows[i] = CreateRow(listFrame, i) end

    panel.empty = listFrame:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.empty, 13)
    panel.empty:SetPoint("TOP", listFrame, "TOP", 0, -30)
    panel.empty:SetText(HEX_MUTED .. "No talent builds saved for your class yet.|r")

    panel:SetScript("OnShow", RefreshList)
    RefreshList()
end

-- ── the Builds button in the Blizzard talent window ────────────────
local talentButton
local function OpenTab()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf.activeTab and mf.activeTab.id == "talent_builds" then
        if mf.AnimatedHide then mf:AnimatedHide() else mf:Hide() end
    else
        mf:Show()
        mf:SwitchTab("talent_builds")
    end
end

local function UpdateTalentButton()
    if not talentButton then return end
    local hidden = not (PlayerTalentFrame and PlayerTalentFrame:IsShown())
        or (GlyphFrame and GlyphFrame:IsShown())
        or (PetTalentFrame and PetTalentFrame:IsShown())
        or (PlayerTalentFrameActivateButton and PlayerTalentFrameActivateButton:IsShown())
    if hidden then talentButton:Hide() else talentButton:Show() end
    -- the standalone addon's button and panel, if it is still enabled: keep them hidden
    for _, name in ipairs({ "TalentBuildManagerButton", "TalentBuildManagerPanel" }) do
        local old = _G[name]
        if old then
            if not old.__paHidden then
                old.__paHidden = true
                old:HookScript("OnShow", function(self) self:Hide() end)
            end
            old:Hide()
        end
    end
end

local function InitTalentButton()
    if talentButton or not PlayerTalentFrame then return end
    -- same look as Reset Talents (TalentReset.lua); the two sit side by side, centred
    talentButton = CreateFrame("Button", "PATalentBuildsButton", PlayerTalentFrame, "UIPanelButtonTemplate")
    if UI.CosmicButton then UI.CosmicButton(talentButton) end
    talentButton:SetSize(92, 22)
    talentButton:SetText("Builds")
    talentButton:SetPoint("TOP", PlayerTalentFrame, "TOP", -68, -38)
    talentButton:SetFrameLevel((PlayerTalentFrame:GetFrameLevel() or 1) + 5)
    talentButton:SetScript("OnClick", OpenTab)
    AddTip(talentButton, "Talent Builds", "Save, load and share class talent builds in the Astral hub.")
    PlayerTalentFrame:HookScript("OnShow", UpdateTalentButton)
    PlayerTalentFrame:HookScript("OnHide", UpdateTalentButton)
    if PlayerTalentFrame_Refresh then hooksecurefunc("PlayerTalentFrame_Refresh", UpdateTalentButton) end
    for _, f in ipairs({ GlyphFrame, PetTalentFrame }) do
        if f then f:HookScript("OnShow", UpdateTalentButton); f:HookScript("OnHide", UpdateTalentButton) end
    end
    UpdateTalentButton()
end

-- ── one-time import from the standalone TalentBuildManager addon ───
-- Its builds were saved per character: each character brings its own builds
-- the first time it logs in with both addons enabled. Its own leveling flag is
-- cleared afterwards so only this module spends points on level-up.
local function MigrateStandalone()
    local old = _G.TalentBuildManagerBuilds
    if type(old) ~= "table" then return end
    local store = Store()
    local moved = 0
    for _, b in ipairs(old) do
        if type(b) == "table" and b.version == 1 and b.class and b.name and type(b.trees) == "table" then
            if not FindBuild(b.name, b.class) then
                local copy = { version = 1, name = b.name, class = b.class, trees = {} }
                for tab, tree in ipairs(b.trees) do
                    local t = { name = tree.name, talents = {} }
                    for i, tal in ipairs(tree.talents or {}) do
                        t.talents[i] = { name = tal.name, tier = tal.tier, column = tal.column,
                                         rank = tal.rank, maxRank = tal.maxRank }
                    end
                    copy.trees[tab] = t
                end
                copy.savedBy, copy.className = UnitName("player"), UnitClass("player")
                copy.savedAt, copy.date = time(), date("%Y-%m-%d")
                table.insert(store.builds, copy)
                moved = moved + 1
            end
            if b.applyForLeveling and b.class == ClassToken() then store.leveling[CharKey()] = b.name end
            b.applyForLeveling = false
        end
    end
    if moved > 0 then
        ChatInfo(moved .. " build" .. (moved == 1 and "" or "s") .. " imported from TalentBuildManager. "
            .. "Once every character has logged in once, you can disable that addon.")
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "Blizzard_TalentUI" then
        InitTalentButton()
    elseif event == "PLAYER_LOGIN" then
        MigrateStandalone()
        if IsAddOnLoaded("Blizzard_TalentUI") then InitTalentButton() end
    elseif event == "PLAYER_LEVEL_UP" then
        QueueAutoLevelPoint(arg1)
    else
        UpdateTalentButton()
        if host and host:IsVisible() then RefreshList() end
    end
end)

local function ToggleTalentBuilds() OpenTab() end

PA:RegisterModule("talent_builds", "Talent Builds", ToggleTalentBuilds, {
    subtitle = "Save class talent builds, load them in one click, and level up with one.",
})
PA:RegisterTabContent("talent_builds", BuildTalentBuildsTab)

-- used by Loadouts.lua (a loadout can include one of these builds)
PA.TalentBuilds = {
    List     = function() return (ClassBuilds()) end,
    Find     = function(name) return name and FindBuild(name, ClassToken()) or nil end,
    IsActive = function(b) return b and BuildMatchesCurrent(b) or false end,
    -- the build needs the free talent reset first (points spent that aren't this build)
    NeedsReset = function(b) return b and GetTalentTotal() > 0 and not BuildMatchesCurrent(b) or false end,
    Icon     = function(b) local _, icon = GetTalentTabInfo(MainTree(b)); return icon end,
    IsBusy   = function() return loadState ~= nil end,
    -- confirmed: the loadout already asked about the talent reset
    Load     = function(b, confirmed)
        if confirmed and GetTalentTotal() > 0 and not BuildMatchesCurrent(b) then
            local valid, reason = ValidateBuild(b)
            if not valid then return false, reason end
            ResetAndLoad(b)
            return true
        end
        LoadBuild(b)
        return true
    end,
}
