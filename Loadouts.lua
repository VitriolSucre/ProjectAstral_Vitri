
local PA = ProjectAstral
local UI = PA.UI

-- Loadouts (Builds section): a named combination of an equipment set, a gem build and
-- a talent build, loaded all at once: set first, then talents, then gems, each step
-- waiting for the previous one to finish. Replaces the old Boss Loadouts tab; its
-- presets (saved in ProjectAstralBossLoadouts) are converted on first use.
-- The parts are referenced by name: equipment sets belong to a character and talent
-- builds to a class, so a loadout shows which parts this character can't use.
-- The character window's Sets window has a Loadouts view built on PA.Loadouts.
-- Colours that must survive Theme.lua's vivid-text pass are inline |c codes.

local L = {}
PA.Loadouts = L

local SOLID = "Interface\\Buttons\\WHITE8X8"
local ROW_H, NUM_ROWS = 56, 9
local CONFIRM_WINDOW = 3

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"
local HEX_BAD   = "|cffff9a8f"
local HEX_BTN   = "|cffffe39a"

local function Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- ── storage (one saved table; each loadout belongs to the character that saved it, see Mine) ──
local function Loadouts()
    ProjectAstralBossLoadouts = ProjectAstralBossLoadouts or {}
    local db = ProjectAstralBossLoadouts
    db.presets = db.presets or {}
    for _, p in ipairs(db.presets) do
        if not p.v2 then
            -- Boss Loadouts preset: "Boss · Name", its gem build kept by name
            if p.boss and p.boss ~= "" then p.name = p.boss .. " · " .. (p.name or "Preset") end
            p.gemBuild = p.gemBuild or p.buildName
            p.boss, p.buildName, p.macro = nil, nil, nil
            p.v2 = true
        end
    end
    return db.presets
end

-- Loadouts belong to the character that saved them (p.savedBy). Old Boss Loadouts
-- presets have no owner: the first character to log in claims them.
local function Mine(p)
    local me = UnitName("player")
    if not p.savedBy then p.savedBy = me end
    return p.savedBy == me
end

local function Find(name)
    local lower = name:lower()
    for _, p in ipairs(Loadouts()) do
        if Mine(p) and (p.name or ""):lower() == lower then return p end
    end
end

function L.List()
    local list = {}
    for _, p in ipairs(Loadouts()) do if Mine(p) then list[#list + 1] = p end end
    table.sort(list, function(a, b) return (a.updatedAt or 0) > (b.updatedAt or 0) end)
    return list
end

-- ── the parts ──────────────────────────────────────────────────────
local function GemBuild(name)
    for _, b in ipairs((ProjectAstralGemBuilds and ProjectAstralGemBuilds.builds) or {}) do
        if b.name == name then return b end
    end
end

local function GemText(p)
    local b = p.gemBuild and GemBuild(p.gemBuild)
    return (b and b.text) or p.gemText
end

local function GemsEquipped(text)
    local G = PA.AstralGems
    if not (text and G and G.EncodeLoadout and G.DecodeLoadout) then return false end
    local function Key(t)
        local set = {}
        for _, w in ipairs(G.DecodeLoadout(t) or {}) do set[#set + 1] = w.ord .. "." .. w.idx .. "=" .. w.entry end
        table.sort(set)
        return table.concat(set, ",")
    end
    local current, count = G.EncodeLoadout()
    return count > 0 and Key(text) == Key(current)
end

-- each part: { kind, label, name, ok, why, active }
local function Parts(p)
    local out = {}
    local ES, TB = PA.EquipmentSets, PA.TalentBuilds
    if p.set then
        local ok = ES and ES.Exists(p.set)
        out[#out + 1] = { kind = "set", label = "Set", name = p.set, ok = ok and true or false,
            why = "not saved on this character", active = ok and ES.IsWorn(p.set) }
    end
    if p.talentBuild then
        local b = TB and TB.Find(p.talentBuild)
        out[#out + 1] = { kind = "talents", label = "Talents", name = p.talentBuild, build = b, ok = b and true or false,
            why = (p.talentClass and select(2, UnitClass("player")) ~= p.talentClass) and "another class" or "not found",
            active = b and TB.IsActive(b) }
    end
    if p.gemBuild or p.gemText then
        local text = GemText(p)
        out[#out + 1] = { kind = "gems", label = "Gems", name = p.gemBuild or "saved gems", text = text,
            ok = text and true or false, why = "gem build deleted", active = text and GemsEquipped(text) }
    end
    if p.treeBuild then
        local T = PA.AT and PA.AT.TreeBuilds
        local b = T and T.Find(p.treeBuild)
        local ready = T and T.Ready()
        out[#out + 1] = { kind = "tree", label = "Tree", name = p.treeBuild, build = b,
            ok = (b and ready) and true or false,
            why = (b and not ready) and "Astral Tree not loaded yet" or "tree build deleted",
            notReady = b and not ready,
            active = b and ready and T.IsActive(b) }
    end
    return out
end

function L.Describe(p)
    local bits = {}
    for _, part in ipairs(Parts(p)) do
        if part.ok then
            bits[#bits + 1] = HEX_DIM .. part.label .. "|r " .. (part.active and HEX_GOLD or HEX_MUTED) .. part.name .. "|r"
        else
            bits[#bits + 1] = HEX_DIM .. part.label .. "|r " .. HEX_BAD .. part.name .. " (" .. part.why .. ")|r"
        end
    end
    if #bits == 0 then return HEX_DIM .. "Empty loadout|r" end
    return table.concat(bits, HEX_DIM .. "  ·  |r")
end

function L.IsActive(p)
    local parts = Parts(p)
    if #parts == 0 then return false end
    for _, part in ipairs(parts) do
        if not (part.ok and part.active) then return false end
    end
    return true
end

function L.Icon(p)
    local ES, TB = PA.EquipmentSets, PA.TalentBuilds
    if p.set and ES and ES.Exists(p.set) then
        local icon = ES.Icon(p.set)
        if icon then return icon end
    end
    local b = p.talentBuild and TB and TB.Find(p.talentBuild)
    if b then return TB.Icon(b) end
    if p.treeBuild and not (p.gemBuild or p.gemText) then return "Interface\\Icons\\Spell_Nature_Starfall" end
    return "Interface\\Icons\\INV_Misc_Gem_Variety_01"
end

-- ── status listeners (hub tab and Sets window) ─────────────────────
local statusFns, changedFns = {}, {}
function L.OnStatus(fn) statusFns[#statusFns + 1] = fn end
function L.OnChanged(fn) changedFns[#changedFns + 1] = fn end
local function Say(text, hex) for _, fn in ipairs(statusFns) do pcall(fn, (hex or HEX_MUTED) .. text .. "|r") end end
local function Changed() for _, fn in ipairs(changedFns) do pcall(fn) end end

-- ── loading everything ─────────────────────────────────────────────
-- steps run in order; each waits until its module is idle again (or times out)
local run
local driver = CreateFrame("Frame")
driver:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
driver:Hide()

local STEP_TIMEOUT = { set = 12, talents = 180, tree = 35, gems = 180 }

local function Busy(kind)
    if kind == "set" then return PA.EquipmentSets and PA.EquipmentSets.IsBusy() end
    if kind == "talents" then return PA.TalentBuilds and PA.TalentBuilds.IsBusy() end
    if kind == "tree" then return PA.AT and PA.AT.TreeBuilds and PA.AT.TreeBuilds.IsBusy() end
    if kind == "gems" then return PA.AstralGems and PA.AstralGems.IsApplyingLoadout and PA.AstralGems.IsApplyingLoadout() end
end

-- ── progress (the loading bars of the hub tab and the Sets window) ──
-- state = { active = true, frac, step, total, text } while loading,
--         { finished = true, ok, total } at the end (the result text goes through Say)
local progressFns = {}
function L.OnProgress(fn) progressFns[#progressFns + 1] = fn end
local function Progress(state) for _, fn in ipairs(progressFns) do pcall(fn, state) end end

-- Turns a status bar (a frame with a text FontString) into a loading bar: a gold
-- fill that grows with each step and a "2 / 4" counter on the right. When loading
-- ends the fill turns green (or amber if something was skipped) and fades after a
-- few seconds, leaving the result text.
local DONE_HOLD = 4
function L.AttachProgressBar(bar, text)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(SOLID)
    fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 4)
    fill:SetWidth(1)
    fill:Hide()
    local counter = bar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(counter, 12)
    counter:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    text:SetPoint("RIGHT", counter, "LEFT", -10, 0)

    local shown, target, holdUntil = 0, 0, nil
    local function Paint()
        fill:SetWidth(math.max(1, ((bar:GetWidth() or 0) - 8) * shown))
    end
    L.OnProgress(function(s)
        if s.finished then
            target, shown = 1, 1
            local ok = s.ok
            fill:SetVertexColor(ok and 0.50 or 1.00, ok and 0.88 or 0.80, ok and 0.63 or 0.40, 0.50)
            counter:SetText(HEX_MUTED .. (s.total or 1) .. " / " .. (s.total or 1) .. "|r")
            holdUntil = GetTime() + DONE_HOLD
        else
            if not fill:IsShown() or holdUntil then shown = 0 end   -- a new load starts empty
            holdUntil = nil
            target = s.frac or 0
            fill:SetVertexColor(0.886, 0.753, 0.384, 0.45)
            counter:SetText(HEX_MUTED .. (s.step or 1) .. " / " .. (s.total or 1) .. "|r")
            if s.text then text:SetText(s.text) end
        end
        fill:Show()
        Paint()
    end)
    -- glide the fill toward its target, and clear it once the result has been read
    bar:HookScript("OnUpdate", function(_, dt)
        if not fill:IsShown() then return end
        if shown < target then
            shown = math.min(target, shown + math.max(0.004, (target - shown) * math.min(1, dt * 8)))
            Paint()
        end
        if holdUntil and GetTime() > holdUntil then
            holdUntil = nil
            fill:Hide()
            counter:SetText("")
        end
    end)
end

-- rough duration of each step, for the fill between two steps (gems report their own)
local STEP_EXPECT = { set = 2, talents = 10, tree = 4, gems = 20 }

local function EmitProgress()
    local part = run and run.steps[run.i]
    if not part then return end
    local n, inStep, detail = #run.steps, nil, nil
    local g = run.gem
    if part.kind == "gems" and g and g.total and g.total > 0 then
        inStep = math.min(0.95, ((g.step or 1) - 1) / g.total)
        detail = g.text and g.text ~= "" and g.text or nil
    else
        inStep = math.min(0.9, run.elapsed / (STEP_EXPECT[part.kind] or 5))
    end
    Progress({
        active = true, step = run.i, total = n,
        frac   = (run.i - 1 + inStep) / n,
        text   = HEX_GOLD .. "Loading '" .. run.p.name .. "'|r" .. HEX_MUTED .. "  ·  " .. part.label .. ": "
            .. part.name .. (detail and (HEX_DIM .. "  ·  " .. detail .. "|r" .. HEX_MUTED) or "") .. "…|r",
    })
end

-- the gem step's own progress (socket 3 of 12...)
if PA.AstralGems and PA.AstralGems.OnApplyProgress then
    PA.AstralGems.OnApplyProgress(function(state)
        if run and run.wait == "gems" then run.gem = state end
    end)
end

local function Finish()
    local r = run
    run = nil
    driver:Hide()
    local missing = {}
    for _, part in ipairs(Parts(r.p)) do
        if part.ok and not part.active then missing[#missing + 1] = part.label:lower() end
    end
    if #r.skipped > 0 then
        Say("Loaded '" .. r.p.name .. "' without " .. table.concat(r.skipped, ", ") .. ".", HEX_WARN)
    elseif #missing > 0 then
        Say("Loaded '" .. r.p.name .. "', but the " .. table.concat(missing, " and ") .. " didn't fully apply. Check the other tabs.", HEX_WARN)
    else
        Say("Loadout '" .. r.p.name .. "' loaded.", HEX_GOOD)
    end
    Progress({ finished = true, ok = (#r.skipped == 0 and #missing == 0), total = #r.steps })
    Changed()
end

local function NextStep()
    run.i = run.i + 1
    local part = run.steps[run.i]
    if not part then Finish(); return end
    run.wait, run.elapsed, run.gem = part.kind, 0, nil
    EmitProgress()
    if part.kind == "set" then
        PA.EquipmentSets.Equip(part.name)
    elseif part.kind == "talents" then
        local ok, why = PA.TalentBuilds.Load(part.build, true)
        if not ok then run.skipped[#run.skipped + 1] = "its talents (" .. (why or "?") .. ")" end
    elseif part.kind == "tree" then
        local ok, why = PA.AT.TreeBuilds.Load(part.build)
        if not ok then run.skipped[#run.skipped + 1] = "its Astral Tree build (" .. (why or "?") .. ")" end
    elseif part.kind == "gems" then
        local G = PA.AstralGems
        local _, fill = G.DescribeLoadoutText(part.text)
        if (fill or 0) > 0 then G.ApplyLoadoutText(part.text) end
    end
end

driver:SetScript("OnUpdate", function(_, dt)
    if not run then driver:Hide(); return end
    run.elapsed = run.elapsed + dt
    EmitProgress()
    if run.elapsed < 0.6 then return end          -- let the step start
    if Busy(run.wait) and run.elapsed < (STEP_TIMEOUT[run.wait] or 60) then return end
    NextStep()
end)

local function Start(p)
    local steps, skipped = {}, {}
    for _, part in ipairs(Parts(p)) do
        if part.ok then
            if not part.active then steps[#steps + 1] = part end
        else
            skipped[#skipped + 1] = part.label:lower() .. " " .. part.name .. " (" .. part.why .. ")"
        end
    end
    if #steps == 0 then
        if #skipped > 0 then Say("Nothing of '" .. p.name .. "' can be loaded here: " .. table.concat(skipped, ", ") .. ".", HEX_WARN)
        else Say("'" .. p.name .. "' is already active.", HEX_GOOD) end
        return
    end
    -- set first (the rest doesn't care about gear), talents, Astral Tree, then gems
    local order = { set = 1, talents = 2, tree = 3, gems = 4 }
    table.sort(steps, function(a, b) return order[a.kind] < order[b.kind] end)
    run = { p = p, steps = steps, skipped = skipped, i = 0, elapsed = 0 }
    driver:Show()
    NextStep()
end

StaticPopupDialogs["PA_LOADOUT_LOAD"] = {
    text = "%s",
    button1 = "Load",
    button2 = "Cancel",
    OnAccept = function(_, p) if p then Start(p) end end,
    timeout = 0, whileDead = false, hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
}

function L.IsBusy() return run ~= nil end

-- A Load that needs the Astral Tree from the server waits here and goes on by
-- itself once it arrives (up to 15 s, asking again every 5 s)
local TREE_WAIT = 15
L._treeWaiter = CreateFrame("Frame")
L._treeWaiter:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
L._treeWaiter:Hide()
L._treeWaiter:SetScript("OnUpdate", function(self)
    local p = L._waitTree
    local T = PA.AT and PA.AT.TreeBuilds
    if not (p and T) then self:Hide(); return end
    if T.Ready() then
        self:Hide()
        L._waitTree = nil
        L.Load(p)
    elseif GetTime() - (L._waitTreeAt or 0) > TREE_WAIT then
        self:Hide()
        L._waitTree = nil
        Say("The server didn't send the Astral Tree in time. Click Load to try again.", HEX_WARN)
    else
        T.EnsureData()
    end
end)

-- fetch the tree a few seconds after login, so the first Load rarely has to wait
do
    local warm = CreateFrame("Frame")
    warm:SetSize(1, 1)
    warm:RegisterEvent("PLAYER_ENTERING_WORLD")
    warm:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        local t = 0
        self:SetScript("OnUpdate", function(f, dt)
            t = t + dt
            if t < 4 then return end
            f:SetScript("OnUpdate", nil)
            local T = PA.AT and PA.AT.TreeBuilds
            local hasTreePart = false
            for _, p in ipairs(L.List()) do if p.treeBuild then hasTreePart = true; break end end
            if T and hasTreePart then T.EnsureData() end
        end)
    end)
end

function L.Load(p)
    if run then Say("A loadout is already being loaded.", HEX_WARN); return end
    if InCombatLockdown() or UnitAffectingCombat("player") then Say("Leave combat to load a loadout.", HEX_WARN); return end
    for _, kind in ipairs({ "set", "talents", "tree", "gems" }) do
        if Busy(kind) then
            Say("Wait for the current " .. (kind == "tree" and "Astral Tree" or kind) .. " change to finish.", HEX_WARN)
            return
        end
    end
    -- the tree build needs the tree from the server: fetch it instead of skipping it
    for _, part in ipairs(Parts(p)) do
        if part.kind == "tree" and part.notReady then
            -- fetch it, then carry on with this same Load by itself
            PA.AT.TreeBuilds.EnsureData()
            L._waitTree, L._waitTreeAt = p, GetTime()
            L._treeWaiter:Show()
            Say("Getting the Astral Tree from the server… '" .. p.name .. "' loads as soon as it arrives.", HEX_GOLD)
            return
        end
    end
    -- resetting talents or changing the Astral Tree (removing nodes, spending
    -- tokens): ask once for the whole loadout, saying what will happen
    local notes = {}
    for _, part in ipairs(Parts(p)) do
        if part.kind == "talents" and part.ok and PA.TalentBuilds.NeedsReset(part.build) then
            notes[#notes + 1] = "Your talents are reset (free of charge)."
        elseif part.kind == "tree" and part.ok and not part.active then
            local removeOrder, addOrder, cost = PA.AT.TreeBuilds.Plan(part.build)
            local bits = {}
            if #removeOrder > 0 then bits[#bits + 1] = "|cffff8888remove " .. #removeOrder .. " node(s)|r" end
            if #addOrder > 0 then
                bits[#bits + 1] = "|cff88ff88unlock " .. #addOrder .. " node(s)|r for |cffffd700" .. cost
                    .. " token" .. (cost == 1 and "" or "s") .. "|r (you have " .. (PA.AT.prestigeTokens or 0) .. ")"
            end
            notes[#notes + 1] = "Astral Tree '" .. part.name .. "': " .. table.concat(bits, " and ") .. "."
        end
    end
    if #notes > 0 then
        StaticPopup_Show("PA_LOADOUT_LOAD", "Load loadout '" .. p.name .. "'?\n\n" .. table.concat(notes, "\n"), nil, p)
        return
    end
    Start(p)
end

-- ── hub tab: Builds > Loadouts ─────────────────────────────────────
local host
local rows = {}
local editing                    -- name of the loadout loaded into the editor

local function Pickers() return host and host.pickers end

local function ResetConfirm(btn)
    if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then return end
    btn._confirmAt = nil
    btn:SetLabel(btn._idleLabel)
end

-- Part selector: a navy field like the filter chips, its label on the left
-- ("Set", "Gems"...), the chosen name on the right and a small arrow; a click
-- opens the list ("None" + names) as a menu under it. sel.value = name or nil.
local function PaintPicker(sel, hover)
    if sel.value then
        sel:SetBackdropBorderColor(0.79, 0.66, 0.31, hover and 1 or 0.85)   -- gold edge: part picked
    else
        sel:SetBackdropBorderColor(hover and 0.30 or 0.173, hover and 0.36 or 0.216, hover and 0.62 or 0.408, 1)
    end
    sel:SetBackdropColor(hover and 0.100 or 0.063, hover and 0.140 or 0.090, hover and 0.320 or 0.227, 0.95)
end

-- is this set / build applied right now? (picker fields and lists mark it)
local function PartActive(kind, n)
    if not n then return false end
    if kind == "set" then return PA.EquipmentSets and PA.EquipmentSets.Exists(n) and PA.EquipmentSets.IsWorn(n) or false end
    if kind == "talents" then
        local TB = PA.TalentBuilds; local b = TB and TB.Find(n)
        return b and TB.IsActive(b) or false
    end
    if kind == "gems" then
        local b = GemBuild(n)
        return b and b.text and GemsEquipped(b.text) or false
    end
    if kind == "tree" then
        local T = PA.AT and PA.AT.TreeBuilds; local b = T and T.Find(n)
        return b and T.Ready() and T.IsActive(b) or false
    end
    return false
end

local function MakePicker(parent, name, label, listFn, kind)
    local sel = CreateFrame("Button", nil, parent)
    sel:SetHeight(28)
    sel.__paBackdrop, sel.__paSkinned = true, true    -- keep Theme.lua off it
    sel:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })

    sel.caption = sel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(sel.caption, 11)
    sel.caption:SetPoint("LEFT", sel, "LEFT", 10, 0)
    sel.caption:SetText(HEX_DIM .. label .. "|r")

    sel.arrow = sel:CreateTexture(nil, "OVERLAY")
    sel.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    sel.arrow:SetSize(12, 12)
    sel.arrow:SetPoint("RIGHT", sel, "RIGHT", -8, -2)
    sel.arrow:SetVertexColor(UI.Tint(0.67, 0.69, 0.83))

    sel.text = sel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(sel.text, 13)
    sel.text:SetPoint("LEFT", sel.caption, "RIGHT", 8, 0)
    sel.text:SetPoint("RIGHT", sel.arrow, "LEFT", -6, 0)
    sel.text:SetJustifyH("RIGHT"); sel.text:SetWordWrap(false)

    -- the list itself: Blizzard's menu (tooltip-style), anchored under the field
    local menu = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    menu:Hide()
    UIDropDownMenu_Initialize(menu, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.checked = "None", sel.value == nil
        info.func = function() sel:SetValue(nil) end
        UIDropDownMenu_AddButton(info, level)
        for _, n in ipairs(listFn()) do
            local opt = UIDropDownMenu_CreateInfo()
            opt.text, opt.checked = PartActive(kind, n) and (HEX_GOLD .. n .. "|r" .. HEX_DIM .. "  ·  active|r") or n, sel.value == n
            opt.func = function() sel:SetValue(n) end
            UIDropDownMenu_AddButton(opt, level)
        end
    end, "MENU")

    function sel:SetValue(v)
        self.value = v
        -- the part you have on right now reads gold, with "active"
        if v and PartActive(kind, v) then self.text:SetText(HEX_GOLD .. v .. "  |r" .. HEX_GOOD .. "active|r")
        else self.text:SetText(v and ("|cffffffff" .. v .. "|r") or (HEX_DIM .. "None|r")) end
        PaintPicker(self, self:IsMouseOver())
    end
    sel:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, menu, self, 0, 0)
    end)
    sel:SetScript("OnEnter", function(self) PaintPicker(self, true) end)
    sel:SetScript("OnLeave", function(self) PaintPicker(self, false) end)
    sel:SetValue(nil)
    return sel
end

local function SetNames()
    local out = {}
    for _, s in ipairs((PA.EquipmentSets and PA.EquipmentSets.List()) or {}) do out[#out + 1] = s.name end
    return out
end
local function GemNames()
    local out = {}
    for _, b in ipairs((ProjectAstralGemBuilds and ProjectAstralGemBuilds.builds) or {}) do
        if b.name then out[#out + 1] = b.name end
    end
    table.sort(out)
    return out
end
local function TalentNames()
    local out = {}
    for _, b in ipairs((PA.TalentBuilds and PA.TalentBuilds.List()) or {}) do out[#out + 1] = b.name end
    return out
end
local function TreeNames()
    local out = {}
    local T = PA.AT and PA.AT.TreeBuilds
    for _, b in ipairs((T and T.List()) or {}) do out[#out + 1] = b.name end
    table.sort(out)
    return out
end

local Refresh

local function SaveLoadout()
    local pk = Pickers()
    local name = Trim(host.nameBox:GetText())
    if name == "" then Say("Type a name for the loadout first.", HEX_WARN); host.nameBox.edit:SetFocus(); return end
    if not (pk.set.value or pk.gems.value or pk.talents.value or pk.tree.value) then
        Say("Pick at least one part: an equipment set, a gem build, a talent build or an Astral Tree build.", HEX_WARN)
        return
    end
    local p = Find(name)
    local isNew = not p
    if isNew then
        p = { id = tostring(time()) .. "-" .. tostring(math.floor(GetTime() * 1000)), v2 = true }
        table.insert(Loadouts(), p)
    end
    p.name, p.set, p.gemBuild, p.talentBuild = name, pk.set.value, pk.gems.value, pk.talents.value
    p.treeBuild = pk.tree.value
    p.talentClass = pk.talents.value and select(2, UnitClass("player")) or nil
    p.gemText = nil
    p.savedBy, p.updatedAt, p.date = UnitName("player"), time(), date("%Y-%m-%d")
    editing = nil
    host.nameBox:Clear()
    pk.set:SetValue(nil); pk.gems:SetValue(nil); pk.talents:SetValue(nil); pk.tree:SetValue(nil)
    Say((isNew and "Saved" or "Updated") .. " loadout '" .. name .. "'.", HEX_GOOD)
    Changed()
end

local function EditLoadout(p)
    local pk = Pickers()
    editing = p.name
    host.nameBox:SetText(p.name)
    pk.set:SetValue(p.set); pk.gems:SetValue(p.gemBuild); pk.talents:SetValue(p.talentBuild)
    pk.tree:SetValue(p.treeBuild)
    Say("Editing '" .. p.name .. "': change its parts and click Save loadout.", HEX_GOLD)
end

local function DeleteLoadout(p)
    for i, other in ipairs(Loadouts()) do
        if other == p then table.remove(Loadouts(), i); break end
    end
    Say("Deleted loadout '" .. (p.name or "?") .. "'.", HEX_WARN)
    Changed()
end

local function ShowPreview(r)
    local p = r.loadout
    if not p then return end
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine(p.name, 1, 1, 1)
    if p.savedBy then GameTooltip:AddLine("Saved by " .. p.savedBy .. (p.date and (" on " .. p.date) or ""), 0.75, 0.77, 0.88) end
    GameTooltip:AddLine(" ")
    for _, part in ipairs(Parts(p)) do
        local state = not part.ok and ("(" .. part.why .. ")") or (part.active and "active" or "")
        local cr, cg, cb = 1, 1, 1
        if not part.ok then cr, cg, cb = 1, 0.6, 0.56 elseif part.active then cr, cg, cb = 1, 0.85, 0.44 end
        GameTooltip:AddDoubleLine(part.label .. ": " .. part.name, state, 0.86, 0.87, 0.94, cr, cg, cb)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Load puts on the set, then the talents (free reset), the Astral Tree build, then the gems.", 0.55, 0.88, 0.63, true)
    GameTooltip:Show()
end

local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    UI.MakeRowChrome(r)
    r:HookScript("OnEnter", ShowPreview)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnDoubleClick", function(self) if self.loadout then L.Load(self.loadout) end end)
    if i % 2 == 0 then
        local alt = r:CreateTexture(nil, "BACKGROUND"); alt:SetTexture(SOLID); alt:SetAllPoints(r)
        alt:SetVertexColor(1, 1, 1, 0.022)
    end
    if i > 1 then
        local d = r:CreateTexture(nil, "BORDER"); d:SetTexture(SOLID); d:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        d:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1); d:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1); d:SetHeight(1)
    end
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
    r.del._idleLabel = "Delete"
    r.del:SetScript("OnClick", function()
        local p = r.loadout
        if not p then return end
        if r.del._confirmAt and GetTime() - r.del._confirmAt <= CONFIRM_WINDOW then
            r.del._confirmAt = nil
            DeleteLoadout(p)
        else
            r.del._confirmAt = GetTime()
            r.del:SetLabel("Sure?")
            Say("Click Sure? to delete '" .. p.name .. "'.", HEX_WARN)
        end
    end)
    r.edit = UI.MakeButton(r, "Edit", { w = 70, h = 24, variant = "secondary",
        onClick = function() if r.loadout then EditLoadout(r.loadout) end end })
    r.edit:SetPoint("RIGHT", r.del, "LEFT", -5, 0)
    r.load = UI.MakeButton(r, "Load", { w = 78, h = 24, variant = "gold",
        onClick = function() if r.loadout then L.Load(r.loadout) end end })
    r.load:SetPoint("RIGHT", r.edit, "LEFT", -10, 0)

    r.name = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.name, 14)
    r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 10, 2)
    r.name:SetPoint("RIGHT", r.load, "LEFT", -10, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.sub, 11)
    r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 10, -3)
    r.sub:SetPoint("RIGHT", r.load, "LEFT", -10, 0)
    r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
    r:Hide()
    return r
end

Refresh = function()
    if not (host and host:IsVisible()) then return end
    local list = L.List()
    local offset = FauxScrollFrame_GetOffset(host.scroll)
    local busy = run ~= nil
    for i = 1, NUM_ROWS do
        local r, p = rows[i], list[i + offset]
        if r.loadout ~= p then r.del._confirmAt = nil end
        r.loadout = p
        ResetConfirm(r.del)
        if p then
            local active = L.IsActive(p)
            -- every row has Gem Stash's gold look; the active one a stronger tint
            r.activeBg:Show(); r.activeBar:Show()
            r.activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, active and 0.30 or 0.14, 0.94, 0.82, 0.43, 0)
            r.iconFrame:SetTexture(L.Icon(p))
            r.iconFrame:SetQuality(4)
            r.name:SetText(p.name .. (active and ("  " .. HEX_GOLD .. "Active|r") or ""))
            r.sub:SetText(L.Describe(p))
            if busy then r.load:SetDisabledLook(true); r.load:SetLabel(HEX_DIM .. "Load|r")
            else r.load:SetDisabledLook(false); r.load:SetLabel(HEX_BTN .. "Load|r") end
            r:Show()
        else
            r:Hide()
        end
    end
    FauxScrollFrame_Update(host.scroll, #list, NUM_ROWS, ROW_H)
    host.countText:SetText(HEX_GOLD .. #list .. "|r" .. HEX_MUTED .. (#list == 1 and " loadout" or " loadouts") .. "|r")
    if #list == 0 then host.empty:Show() else host.empty:Hide() end
end

local function BuildLoadoutsTab(panel)
    host = panel
    local SIDE, top = 10, -8

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID); ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    local nameBox = UI.MakeSearchBox(panel, { width = 260, height = 26, placeholder = "Name this loadout…" })
    UI.SetTextFont(nameBox.edit, 13); UI.StyleFilterSearch(nameBox); nameBox.__paBackdrop = true
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top)
    nameBox.edit:SetScript("OnEnterPressed", SaveLoadout)
    panel.nameBox = nameBox

    local saveBtn = UI.MakeButton(panel, "Save loadout", { w = 140, h = 26, variant = "gold", onClick = SaveLoadout })
    saveBtn:SetLabel(HEX_BTN .. "Save loadout|r")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    saveBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Save loadout", 1, 1, 1)
        GameTooltip:AddLine("Saves the name with the set, gem build, talent build and Astral Tree build picked below. An existing name is updated.",
            0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    saveBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    panel.countText = panel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.countText, 13)
    panel.countText:SetPoint("RIGHT", panel, "TOPRIGHT", -SIDE - 2, top - 13)

    -- the four parts
    panel.pickers = {
        set     = MakePicker(panel, "PALoadoutSetDD", "Set", SetNames, "set"),
        gems    = MakePicker(panel, "PALoadoutGemsDD", "Gems", GemNames, "gems"),
        talents = MakePicker(panel, "PALoadoutTalentsDD", "Talents", TalentNames, "talents"),
        tree    = MakePicker(panel, "PALoadoutTreeDD", "Astral Tree", TreeNames, "tree"),
    }

    -- status / progress bar
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(38)

    -- the four fields share the row equally (two rows of two if they'd get too narrow)
    local PICK_GAP, PICK_MIN = 8, 170
    local function LayoutPickers()
        local pk = panel.pickers
        local order = { pk.set, pk.gems, pk.talents, pk.tree }
        local avail = (panel:GetWidth() or 0) - SIDE * 2
        local perRow = (avail >= PICK_MIN * 4 + PICK_GAP * 3) and 4 or 2
        local w = math.floor((avail - PICK_GAP * (perRow - 1)) / perRow)
        for i, sel in ipairs(order) do
            local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
            sel:ClearAllPoints()
            sel:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE + col * (w + PICK_GAP), top - 36 - row * 34)
            sel:SetWidth(w)
        end
        local barTop = top - 72 - ((perRow == 4) and 0 or 34)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, barTop)
        bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, barTop)
    end
    panel:HookScript("OnSizeChanged", LayoutPickers)
    -- "active" marks follow gear, talents, gems and the Astral Tree
    L.OnChanged(function()
        for _, sel in pairs(panel.pickers) do sel:SetValue(sel.value) end
    end)
    LayoutPickers()
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92); bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true
    bar.text = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.text, 12)
    bar.text:SetPoint("LEFT", bar, "LEFT", 12, 0); bar.text:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
    bar.text:SetText(HEX_MUTED .. "Name a loadout, pick its set, gem build, talent build and Astral Tree build, then Save loadout. Load puts everything on at once.|r")
    L.OnStatus(function(text) bar.text:SetText(text) end)
    L.AttachProgressBar(bar, bar.text)

    -- list
    local listPanel = CreateFrame("Frame", nil, panel)
    listPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, 10)
    UI.AstralBackdrop(listPanel, { thin = true })
    listPanel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)   -- same dark grey as the Gem Stash list
    listPanel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    listPanel.__paBackdrop = true

    local scroll = CreateFrame("ScrollFrame", "PALoadoutsScroll", listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Refresh)
    end)
    panel.scroll = scroll
    local listFrame = CreateFrame("Frame", nil, listPanel)
    listFrame:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    for i = 1, NUM_ROWS do rows[i] = CreateRow(listFrame, i) end
    panel.empty = listFrame:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.empty, 13)
    panel.empty:SetPoint("TOP", listFrame, "TOP", 0, -30)
    panel.empty:SetText(HEX_MUTED .. "No loadouts yet.|r")

    panel:SetScript("OnShow", function()
        -- loadouts with a tree build need the tree from the server to show and load
        if PA.AT and PA.AT.TreeBuilds then PA.AT.TreeBuilds.EnsureData() end
        Refresh()
    end)
    if PA.AT and PA.AT.TreeBuilds then PA.AT.TreeBuilds.EnsureData() end
    Refresh()
end

L.OnChanged(function() if Refresh then Refresh() end end)

-- active markers follow gear, talents and gems
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("PLAYER_TALENT_UPDATE")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:SetScript("OnEvent", function() Changed() end)
if PA.AstralGems and PA.AstralGems.Render then
    hooksecurefunc(PA.AstralGems, "Render", function() Changed() end)
end
-- Astral Tree: data arrived, or nodes unlocked/removed (Skilltree.lua loads first)
if PA.AT and PA.AT.OnStatsChanged then PA.AT.OnStatsChanged(function() Changed() end) end

local function OpenTab()
    local mf = PA.mainFrame
    if not mf then return end
    mf:Show()
    mf:SwitchTab("loadouts")
end
L.OpenTab = OpenTab

PA:RegisterModule("loadouts", "Loadouts", OpenTab, {
    subtitle = "Combine an equipment set, gem, talent and Astral Tree builds, and load them all at once.",
})
PA:RegisterTabContent("loadouts", BuildLoadoutsTab)
