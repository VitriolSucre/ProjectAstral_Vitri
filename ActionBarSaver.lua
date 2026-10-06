local PA = ProjectAstral
if not PA then return end

PA.ActionBarSaver = PA.ActionBarSaver or {}
local ABS = PA.ActionBarSaver

local spellCache = {}
local playerClass

local MAX_ACTION_BUTTONS = 144
local POSSESSION_START   = 121
local POSSESSION_END     = 132
local BOOKTYPE_SPELL     = "spell"

local function strsplit(delimiter, text)
    local list = {}
    local pos = 1
    if string.find("", delimiter, 1) then return end
    while 1 do
        local first, last = string.find(text, delimiter, pos)
        if first then
            table.insert(list, string.sub(text, pos, first - 1))
            pos = last + 1
        else
            table.insert(list, string.sub(text, pos))
            break
        end
    end
    return unpack(list)
end

local timerFrame = CreateFrame("Frame")
timerFrame:Hide()
local timers = {}

timerFrame:SetScript("OnUpdate", function(self, elapsed)
    elapsed = math.min(elapsed, 0.1)
    local i = 1
    while i <= #timers do
        local t = timers[i]
        t.delay = t.delay - elapsed
        if t.delay <= 0 then
            table.remove(timers, i)
            if t.func then
                local ok, err = pcall(t.func)
                if not ok then geterrorhandler()(err) end
            end
        else
            i = i + 1
        end
    end
    if #timers == 0 then self:Hide() end
end)

local function TimerAfter(delay, func)
    table.insert(timers, { delay = delay, func = func })
    timerFrame:Show()
end

function ABS:CompressText(text)
    text = string.gsub(text, "\n", "/n")
    text = string.gsub(text, "/n$", "")
    text = string.gsub(text, "||", "/124")
    return string.trim(text)
end

function ABS:UncompressText(text)
    text = string.gsub(text, "/n", "\n")
    text = string.gsub(text, "/124", "|")
    return string.trim(text)
end

function ABS.Init()
    playerClass = select(2, UnitClass("player"))

    ProjectAstralActionBars = ProjectAstralActionBars or {}
    ProjectAstralActionBars.sets = ProjectAstralActionBars.sets or {}
    ProjectAstralActionBars.sets[playerClass] = ProjectAstralActionBars.sets[playerClass] or {}

    ABS.db = ProjectAstralActionBars

    TimerAfter(2, function() ABS:RestoreProfile("AutoSave", playerClass) end)
    ABS.StartPeriodicSaver()
end

function ABS.StartPeriodicSaver()
    if UnitLevel("player") > 1 then
        ABS:SaveProfile("AutoSave")
    end
    TimerAfter(5, ABS.StartPeriodicSaver)
end

function ABS:SaveProfile(name)
    if not ABS.db then return end

    self.db.sets[playerClass][name] = self.db.sets[playerClass][name] or {}
    local set = self.db.sets[playerClass][name]

    for actionID = 1, MAX_ACTION_BUTTONS do
        set[actionID] = nil

        local typ, id, subType, extraID = GetActionInfo(actionID)

        if typ and id and (actionID < POSSESSION_START or actionID > POSSESSION_END) then
            if typ == "companion" then
                set[actionID] = string.format("%s|%s|%s|%s|%s|%s",
                    typ, id, "", name, subType, extraID)
            elseif typ == "equipmentset" then
                set[actionID] = string.format("%s|%s|%s", typ, id, "")
            elseif typ == "item" then
                set[actionID] = string.format("%s|%d|%s|%s",
                    typ, id, "", (GetItemInfo(id)) or "")
            elseif typ == "spell" and id > 0 then
                local spell, rank = GetSpellName(id, BOOKTYPE_SPELL)
                if spell then
                    set[actionID] = string.format("%s|%d|%s|%s|%s|%s",
                        typ, id, "", spell, rank or "", extraID or "")
                end
            elseif typ == "macro" then
                local mname, icon, macro = GetMacroInfo(id)
                if mname and icon and macro then
                    set[actionID] = string.format("%s|%d|%s|%s|%s|%s",
                        typ, actionID, "",
                        self:CompressText(mname), icon, self:CompressText(macro))
                end
            end
        end
    end
end

function ABS:RestoreProfile(name, overrideClass)
    if not ABS.db then return end
    local set = self.db.sets[overrideClass or playerClass][name]
    if not set then return end
    if InCombatLockdown() then return end

    table.wipe(spellCache)

    for book = 1, MAX_SKILLLINE_TABS do
        local _, _, offset, numSpells = GetSpellTabInfo(book)
        for i = 1, numSpells do
            local index = offset + i
            local spell, rank = GetSpellName(index, BOOKTYPE_SPELL)
            spellCache[spell] = index
            spellCache[string.lower(spell)] = index
            if rank and rank ~= "" then
                spellCache[spell .. rank] = index
            end
        end
    end

    ClearCursor()

    for i = 1, MAX_ACTION_BUTTONS do
        if i < POSSESSION_START or i > POSSESSION_END then
            local typ, id = GetActionInfo(i)
            if not (id or typ) then
                if set[i] then
                    self:RestoreAction(i, strsplit("|", set[i]))
                end
            end
        end
    end
end

function ABS:RestoreAction(i, typ, actionID, binding, ...)
    if typ == "spell" then
        local spellName, spellRank = ...
        if spellRank ~= "" and spellCache[spellName .. spellRank] then
            PickupSpell(spellCache[spellName .. spellRank], BOOKTYPE_SPELL)
        elseif spellCache[spellName] then
            PickupSpell(spellCache[spellName], BOOKTYPE_SPELL)
        end
        if GetCursorInfo() == typ then PlaceAction(i) end
        ClearCursor()
    elseif typ == "item" then
        PickupItem(actionID)
        if GetCursorInfo() == typ then PlaceAction(i) end
        ClearCursor()
    elseif typ == "macro" then
        PickupMacro(actionID)
        if GetCursorInfo() == typ then PlaceAction(i) end
        ClearCursor()
    end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "ProjectAstral" then
        ABS.Init()
    elseif event == "PLAYER_LEVEL_UP"
        or event == "SPELLS_CHANGED"
        or event == "LEARNED_SPELL_IN_TAB" then
        TimerAfter(0.5, function() ABS:RestoreProfile("AutoSave", playerClass) end)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
