
local PA = ProjectAstral
local UI = PA.UI

-- Equipment Sets: save what you're wearing as a named set, update or delete it,
-- and put it back on in one click. Uses the client's built-in equipment manager
-- (SaveEquipmentSet / UseEquipmentSet), so sets are stored by the server for this
-- character (up to 10) and swapping takes items from your bags.
-- A "Sets" button in the character window opens the window, next to it.
-- Colours that must survive Theme.lua's vivid-text pass are inline |c codes.

local SOLID = "Interface\\Buttons\\WHITE8X8"
local ROW_H, NUM_ROWS = 40, 10
local CONFIRM_WINDOW = 3
local MAX_SETS = MAX_EQUIPMENT_SETS_PER_PLAYER or 10
local W, H = 440, 672

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"
local HEX_BAD   = "|cffff9a8f"
local HEX_BTN   = "|cffffe39a"

-- inventory slots shown in the item preview, in character-window order
local SLOTS = { 1, 2, 3, 15, 5, 4, 19, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }

local win
local tab               -- the Builds > Set Builds hub tab (same sets, row layout)
local selected          -- name of the selected set in the window
local equipping         -- set being equipped, until EQUIPMENT_SWAP_FINISHED

local function HasAPI()
    return GetNumEquipmentSets and GetEquipmentSetInfo and SaveEquipmentSet
       and UseEquipmentSet and DeleteEquipmentSet and GetEquipmentSetItemIDs
end

local function Trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function SetItems(name)
    local ids = GetEquipmentSetItemIDs(name) or {}
    local n = 0
    for _, slot in ipairs(SLOTS) do
        if (ids[slot] or 0) > 1 then n = n + 1 end   -- 0 = empty, 1 = slot ignored
    end
    return ids, n
end

-- per slot: an item id, EMPTY_SLOT (saved with nothing there: the set takes it off)
-- or IGNORED_SLOT / nil (the set leaves that slot alone)
local EMPTY_SLOT = EQUIPMENT_SET_EMPTY_SLOT or 0

local function IsWorn(name)
    local ids = GetEquipmentSetItemIDs(name)
    if not ids then return false end
    for _, slot in ipairs(SLOTS) do
        local want = ids[slot]
        local has = GetInventoryItemID("player", slot)
        if want and want > 1 and has ~= want then return false end
        if want == EMPTY_SLOT and has then return false end
    end
    return true
end

-- slots the set leaves empty that hold an item right now
local function SlotsToEmpty(name)
    local ids, out = GetEquipmentSetItemIDs(name) or {}, {}
    for _, slot in ipairs(SLOTS) do
        if ids[slot] == EMPTY_SLOT and GetInventoryItemID("player", slot) then out[#out + 1] = slot end
    end
    return out
end

local function AllSets()
    local list = {}
    for i = 1, GetNumEquipmentSets() do
        local name, icon = GetEquipmentSetInfo(i)
        if name then list[#list + 1] = { name = name, icon = icon } end
    end
    return list
end

local function SetExists(name)
    local lower = name:lower()
    for _, s in ipairs(AllSets()) do
        if s.name:lower() == lower then return s.name end
    end
end

-- icon: the one of the weapon you're holding (falls back to the first icon)
local function IconIndex()
    if RefreshEquipmentSetIconInfo then RefreshEquipmentSetIconInfo() end
    if not (GetNumEquipmentSetIcons and GetEquipmentSetIconInfo) then return 1 end
    for _, slot in ipairs({ 16, 5, 1 }) do
        local tex = GetInventoryItemTexture("player", slot)
        if tex then
            for i = 1, GetNumEquipmentSetIcons() do
                if GetEquipmentSetIconInfo(i) == tex then return i end
            end
        end
    end
    return 1
end

-- ── window helpers ─────────────────────────────────────────────────
local function Navy(f, bg, edge)
    f.__paBackdrop = true
    f:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                    insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end

-- status messages go to both the window and the hub tab
local function SetStatus(text, hex)
    local s = (hex or HEX_MUTED) .. text .. "|r"
    if win then win.status:SetText(s) end
    if tab and tab.bar then tab.bar.text:SetText(s) end
end

local function ConfirmButton(btn, label, prompt, action)
    btn:SetScript("OnClick", function()
        if not selected then return end
        if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then
            btn._confirmAt = nil
            btn:SetLabel(label)
            action(selected)
        else
            btn._confirmAt = GetTime()
            btn:SetLabel("Sure?")
            SetStatus(string.format(prompt, selected), HEX_WARN)
        end
    end)
    btn._idleLabel = label
end

local function ResetConfirm(btn)
    if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then return end
    btn._confirmAt = nil
    btn:SetLabel(btn._idleLabel)
end

-- ── actions ────────────────────────────────────────────────────────
local Refresh, RefreshTab

-- When the game's Equipment Manager option is off, the client answers a set action
-- with a red "The Equipment Manager is disabled." error: that message is caught
-- (see the UI_ERROR_MESSAGE handler) and a popup says where to turn it on.
StaticPopupDialogs["PA_EQUIPMENT_MANAGER_OFF"] = {
    text = "The Equipment Manager is turned off.\n\nTurn it on in Game Menu > Interface > Features, then try again.",
    button1 = OKAY or "OK",
    button2 = "Open Interface",
    OnCancel = function(_, _, reason)
        if reason ~= "clicked" then return end
        if InterfaceOptionsFrame_OpenToCategory and InterfaceOptionsFeaturesPanel then
            InterfaceOptionsFrame_OpenToCategory(InterfaceOptionsFeaturesPanel)
        elseif InterfaceOptionsFrame then
            InterfaceOptionsFrame:Show()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
}

local function SaveNew(box)
    box = box or win.nameBox
    local name = Trim(box:GetText())
    if name == "" then SetStatus("Type a name for the new set first.", HEX_WARN); box.edit:SetFocus(); return end
    local existing = SetExists(name)
    if existing then
        selected = existing
        SetStatus("A set named '" .. existing .. "' already exists. It's selected: click Update to replace it.", HEX_WARN)
        Refresh()
        return
    end
    if #AllSets() >= MAX_SETS then SetStatus("You already have " .. MAX_SETS .. " sets. Delete one first.", HEX_BAD); return end
    SaveEquipmentSet(name, IconIndex())
    selected = name
    box:Clear()
    box.edit:ClearFocus()
    SetStatus("Saved '" .. name .. "' with the gear you're wearing.", HEX_GOOD)
end

local function UpdateSet(name)
    SaveEquipmentSet(name, IconIndex())
    SetStatus("Updated '" .. name .. "' with the gear you're wearing.", HEX_GOOD)
end

local function DeleteSet(name)
    DeleteEquipmentSet(name)
    if selected == name then selected = nil end
    SetStatus("Deleted '" .. name .. "'.", HEX_WARN)
end

-- The client's UseEquipmentSet puts the set's items on but leaves the slots the set
-- saved as empty alone, so those are taken off here, one per tick, into free bag
-- space. Runs a moment after the swap (or right away when only those slots differ).
local emptyRunner = CreateFrame("Frame")
emptyRunner:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
emptyRunner:Hide()
local emptying = { name = nil, wait = 0 }

local function FreeBag()
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local free, bagType = GetContainerNumFreeSlots(bag)
        if free and free > 0 and (bagType == nil or bagType == 0) then return bag end
    end
end

local function FinishEquip(name, problem)
    emptyRunner:Hide()
    emptying.name = nil
    equipping = nil
    if problem then
        SetStatus(problem, HEX_WARN)
    elseif IsWorn(name) then
        SetStatus("Equipped '" .. name .. "'.", HEX_GOOD)
    else
        SetStatus("Some items of '" .. name .. "' couldn't be equipped (missing from your bags?).", HEX_WARN)
    end
    if Refresh then Refresh() end
end

emptyRunner:SetScript("OnUpdate", function(self, elapsed)
    emptying.wait = emptying.wait - elapsed
    if emptying.wait > 0 then return end
    emptying.wait = 0.25
    local name = emptying.name
    if not name then self:Hide(); return end
    if CursorHasItem() then return end                  -- the previous item is still moving
    local slot = SlotsToEmpty(name)[1]
    if not slot then FinishEquip(name); return end
    local bag = FreeBag()
    if not bag then
        FinishEquip(name, "No bag space to take off the items '" .. name .. "' leaves empty.")
        return
    end
    PickupInventoryItem(slot)
    if bag == 0 then PutItemInBackpack() else PutItemInBag(ContainerIDToInventoryID(bag)) end
end)

local function StartEmptying(name, delay)
    emptying.name, emptying.wait = name, delay or 0
    emptyRunner:Show()
end

local function EquipSet(name)
    if InCombatLockdown() or UnitAffectingCombat("player") then
        SetStatus("Leave combat to change your equipment.", HEX_WARN)
        return
    end
    if IsWorn(name) then SetStatus("You're already wearing '" .. name .. "'.", HEX_GOOD); return end
    equipping = name
    SetStatus("Equipping '" .. name .. "'…", HEX_GOLD)
    UseEquipmentSet(name)
    -- if nothing but the emptied slots differ, no swap event comes: start anyway
    StartEmptying(name, 1.0)
end

-- ── rows ───────────────────────────────────────────────────────────
local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    UI.MakeRowChrome(r)
    if i % 2 == 0 then
        local alt = r:CreateTexture(nil, "BACKGROUND"); alt:SetTexture(SOLID); alt:SetAllPoints(r)
        alt:SetVertexColor(1, 1, 1, 0.022)
    end
    if i > 1 then
        local d = r:CreateTexture(nil, "BORDER"); d:SetTexture(SOLID); d:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        d:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1); d:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1); d:SetHeight(1)
    end
    -- worn set: warm tint and gold bar, like the equipped gem build
    r.wornBg = r:CreateTexture(nil, "BACKGROUND"); r.wornBg:SetTexture(SOLID); r.wornBg:SetAllPoints(r)
    r.wornBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    r.wornBar = r:CreateTexture(nil, "ARTWORK"); r.wornBar:SetTexture(SOLID)
    r.wornBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    r.wornBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.wornBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.wornBar:SetWidth(3)
    -- selection: blue outline
    r.sel = {}
    for k = 1, 4 do r.sel[k] = r:CreateTexture(nil, "OVERLAY"); r.sel[k]:SetTexture(SOLID); r.sel[k]:SetVertexColor(UI.Tint(0.44, 0.82, 1, 1)) end
    r.sel[1]:SetPoint("TOPLEFT"); r.sel[1]:SetPoint("TOPRIGHT"); r.sel[1]:SetHeight(1)
    r.sel[2]:SetPoint("BOTTOMLEFT"); r.sel[2]:SetPoint("BOTTOMRIGHT"); r.sel[2]:SetHeight(1)
    r.sel[3]:SetPoint("TOPLEFT"); r.sel[3]:SetPoint("BOTTOMLEFT"); r.sel[3]:SetWidth(1)
    r.sel[4]:SetPoint("TOPRIGHT"); r.sel[4]:SetPoint("BOTTOMRIGHT"); r.sel[4]:SetWidth(1)

    r.iconFrame = UI.MakeIconFrame(r, { size = 28 })
    r.iconFrame:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.name = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.name, 14)
    r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 10, 1)
    r.name:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.sub, 11)
    r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 10, -3)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -10, 0)
    r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)

    r:SetScript("OnClick", function(self)
        if not self.set then return end
        selected = self.set
        Refresh()
    end)
    r:SetScript("OnDoubleClick", function(self) if self.set then EquipSet(self.set) end end)
    r:HookScript("OnEnter", function(self)
        if not self.set then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.set, 1, 1, 1)
        GameTooltip:AddLine("Click to select  ·  Double-click to equip", 0.62, 0.64, 0.78)
        GameTooltip:Show()
    end)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    return r
end

-- ── the window ─────────────────────────────────────────────────────
local function BuildWindow()
    local f = CreateFrame("Frame", "PAEquipmentSetsFrame", UIParent)
    f:SetSize(W, H)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    UI.AstralBackdrop(f, { thin = true })
    f:SetBackdropColor(UI.Tint(0.031, 0.047, 0.133, 0.97))
    f:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)
    f.__paBackdrop = true
    f:Hide()
    tinsert(UISpecialFrames, "PAEquipmentSetsFrame")
    if UI.AnimatedShow then UI.AnimatedShow(f, { duration = 0.15 }) end

    local glow = f:CreateTexture(nil, "ARTWORK"); glow:SetTexture(SOLID)
    glow:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4); glow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4); glow:SetHeight(40)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)
    local accent = f:CreateTexture(nil, "OVERLAY"); accent:SetTexture(SOLID)
    accent:SetVertexColor(0.886, 0.753, 0.384, 1); accent:SetSize(3, 18)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    local title = f:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(title, 15)
    title:SetPoint("LEFT", accent, "RIGHT", 9, 0); title:SetText("Equipment Sets")
    f.count = f:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(f.count, 12)
    f.count:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -19)
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    UI.CosmicCloseButton(close)

    -- save as new
    local nameBox = UI.MakeSearchBox(f, { width = W - 32 - 130, height = 26, placeholder = "Name a new set…" })
    UI.SetTextFont(nameBox.edit, 13); UI.StyleFilterSearch(nameBox); nameBox.__paBackdrop = true
    nameBox:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -78)
    nameBox.edit:SetMaxLetters(16)
    nameBox.edit:SetScript("OnEnterPressed", function() SaveNew(nameBox) end)
    f.nameBox = nameBox
    local saveBtn = UI.MakeButton(f, "Save as new", { w = 122, h = 26, variant = "gold", onClick = function() SaveNew(nameBox) end })
    saveBtn:SetLabel(HEX_BTN .. "Save as new|r")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    -- status bar
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(32)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -112); bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -112)
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92); bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true
    f.status = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(f.status, 12)
    f.status:SetPoint("LEFT", bar, "LEFT", 12, 0); f.status:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    f.status:SetJustifyH("LEFT"); f.status:SetWordWrap(false)

    -- set list
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8); list:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -8)
    list:SetHeight(NUM_ROWS * ROW_H + 8)
    Navy(list, UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
    local inner = CreateFrame("Frame", nil, list)
    inner:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4); inner:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, 4)
    f.rows = {}
    for i = 1, NUM_ROWS do f.rows[i] = CreateRow(inner, i) end
    f.empty = inner:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(f.empty, 13)
    f.empty:SetPoint("TOP", inner, "TOP", 0, -24)
    f.empty:SetText(HEX_MUTED .. "No sets yet. Name one above and click Save as new.|r")

    -- selected set: its items and the actions
    local sel = CreateFrame("Frame", nil, f)
    sel:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8); sel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
    Navy(sel, UI.Tinted({ 0.063, 0.090, 0.227, 0.95 }), UI.Tinted({ 0.173, 0.216, 0.408, 1 }))
    f.selTitle = sel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(f.selTitle, 13)
    f.selTitle:SetPoint("TOPLEFT", sel, "TOPLEFT", 10, -9)
    f.slots = {}
    for k = 1, #SLOTS do
        local t = CreateFrame("Button", nil, sel)
        t:SetSize(18, 18)
        t:SetPoint("TOPLEFT", sel, "TOPLEFT", 10 + (k - 1) * 20, -30)
        t.icon = t:CreateTexture(nil, "ARTWORK"); t.icon:SetAllPoints(t); t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t:SetScript("OnEnter", function(self)
            if not self.item then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetHyperlink("item:" .. self.item)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.slots[k] = t
    end
    f.del = UI.MakeButton(sel, "Delete", { w = 80, h = 26, variant = "danger" })
    f.del:SetPoint("BOTTOMRIGHT", sel, "BOTTOMRIGHT", -8, 8)
    ConfirmButton(f.del, "Delete", "Click Sure? to delete '%s'.", DeleteSet)
    f.update = UI.MakeButton(sel, "Update", { w = 80, h = 26, variant = "secondary" })
    f.update:SetPoint("RIGHT", f.del, "LEFT", -6, 0)
    ConfirmButton(f.update, "Update", "Click Sure? to replace '%s' with the gear you're wearing.", UpdateSet)
    f.update:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Replace this set with the gear you're wearing now. Click twice to confirm.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.update:HookScript("OnLeave", function() GameTooltip:Hide() end)
    f.equip = UI.MakeButton(sel, "Equip", { w = 96, h = 26, variant = "gold",
        onClick = function() if selected then EquipSet(selected) end end })
    f.equip:SetPoint("RIGHT", f.update, "LEFT", -10, 0)
    f.selNote = sel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(f.selNote, 11)
    f.selNote:SetPoint("LEFT", sel, "BOTTOMLEFT", 10, 21)
    f.selNote:SetPoint("RIGHT", f.equip, "LEFT", -8, 0)
    f.selNote:SetJustifyH("LEFT"); f.selNote:SetWordWrap(false)

    -- ── second view: Loadouts (load a set + gems + talents combination) ──
    local LROW_H, LROWS = 44, 11
    local lv = CreateFrame("Frame", nil, f)
    lv:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -76)
    lv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    lv:SetFrameLevel(f:GetFrameLevel() + 20)
    lv:EnableMouse(true)                               -- covers the sets view below the tabs
    local lvBg = lv:CreateTexture(nil, "BACKGROUND"); lvBg:SetTexture(SOLID); lvBg:SetAllPoints(lv)
    lvBg:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 1))
    lv:Hide()
    f.loadView = lv

    local lbar = CreateFrame("Frame", nil, lv)
    lbar:SetHeight(32)
    lbar:SetPoint("TOPLEFT", lv, "TOPLEFT", 4, -2); lbar:SetPoint("TOPRIGHT", lv, "TOPRIGHT", -4, -2)
    UI.AstralBackdrop(lbar, { thin = true })
    lbar:SetBackdropColor(0.20, 0.16, 0.07, 0.92); lbar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    lbar.__paBackdrop = true
    lv.status = lbar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(lv.status, 12)
    lv.status:SetPoint("LEFT", lbar, "LEFT", 12, 0); lv.status:SetPoint("RIGHT", lbar, "RIGHT", -12, 0)
    lv.status:SetJustifyH("LEFT"); lv.status:SetWordWrap(false)
    lv.status:SetText(HEX_MUTED .. "Load a loadout: its set, talents, Astral Tree build and gems are put on at once.|r")

    local hubBtn = UI.MakeButton(lv, "Edit loadouts in the hub", { w = 200, h = 24, variant = "secondary",
        onClick = function() if PA.Loadouts and PA.Loadouts.OpenTab then PA.Loadouts.OpenTab() end end })
    hubBtn:SetPoint("BOTTOMRIGHT", lv, "BOTTOMRIGHT", -4, 2)
    local hubNote = lv:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(hubNote, 11)
    hubNote:SetPoint("RIGHT", hubBtn, "LEFT", -8, 0); hubNote:SetPoint("LEFT", lv, "LEFT", 6, 0)
    hubNote:SetJustifyH("LEFT"); hubNote:SetWordWrap(false)
    hubNote:SetText(HEX_DIM .. "Double-click to load|r")

    local llist = CreateFrame("Frame", nil, lv)
    llist:SetPoint("TOPLEFT", lbar, "BOTTOMLEFT", 0, -6)
    llist:SetPoint("BOTTOMRIGHT", lv, "BOTTOMRIGHT", -4, 32)
    Navy(llist, UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }), UI.Tinted({ 0.165, 0.204, 0.400, 1 }))
    local lscroll = CreateFrame("ScrollFrame", "PAEquipLoadoutsScroll", llist, "FauxScrollFrameTemplate")
    lscroll:SetPoint("TOPLEFT", llist, "TOPLEFT", 4, -4)
    lscroll:SetPoint("BOTTOMRIGHT", llist, "BOTTOMRIGHT", -26, 4)
    local lrowsHost = CreateFrame("Frame", nil, llist)
    lrowsHost:SetPoint("TOPLEFT", lscroll, "TOPLEFT"); lrowsHost:SetPoint("BOTTOMRIGHT", lscroll, "BOTTOMRIGHT")
    lv.empty = lrowsHost:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(lv.empty, 12)
    lv.empty:SetPoint("TOP", lrowsHost, "TOP", 0, -24)
    lv.empty:SetText(HEX_MUTED .. "No loadouts yet. Create them in the hub: Builds > Loadouts.|r")

    local RefreshLoadView
    lv.rows = {}
    for i = 1, LROWS do
        local r = CreateFrame("Button", nil, lrowsHost)
        r:SetHeight(LROW_H)
        r:SetPoint("TOPLEFT", lrowsHost, "TOPLEFT", 0, -(i - 1) * LROW_H)
        r:SetPoint("TOPRIGHT", lrowsHost, "TOPRIGHT", 0, -(i - 1) * LROW_H)
        r:RegisterForClicks("LeftButtonUp")
        UI.MakeRowChrome(r)
        if i % 2 == 0 then
            local alt = r:CreateTexture(nil, "BACKGROUND"); alt:SetTexture(SOLID); alt:SetAllPoints(r)
            alt:SetVertexColor(1, 1, 1, 0.022)
        end
        r.activeBg = r:CreateTexture(nil, "BACKGROUND"); r.activeBg:SetTexture(SOLID); r.activeBg:SetAllPoints(r)
        r.activeBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
        r.activeBar = r:CreateTexture(nil, "ARTWORK"); r.activeBar:SetTexture(SOLID)
        r.activeBar:SetVertexColor(0.886, 0.753, 0.384, 1)
        r.activeBar:SetPoint("TOPLEFT", r, "TOPLEFT"); r.activeBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT"); r.activeBar:SetWidth(3)
        r.iconFrame = UI.MakeIconFrame(r, { size = 28 })
        r.iconFrame:SetPoint("LEFT", r, "LEFT", 8, 0)
        r.load = UI.MakeButton(r, "Load", { w = 64, h = 22, variant = "gold",
            onClick = function() if r.loadout then PA.Loadouts.Load(r.loadout) end end })
        r.load:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        r.name = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.name, 13)
        r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 8, 1)
        r.name:SetPoint("RIGHT", r.load, "LEFT", -8, 0)
        r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.sub = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.sub, 10)
        r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 8, -2)
        r.sub:SetPoint("RIGHT", r.load, "LEFT", -8, 0)
        r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
        r:SetScript("OnDoubleClick", function(self) if self.loadout then PA.Loadouts.Load(self.loadout) end end)
        r:HookScript("OnEnter", function(self)
            if not self.loadout then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.loadout.name, 1, 1, 1)
            GameTooltip:AddLine(PA.Loadouts.Describe(self.loadout), 1, 1, 1, true)
            GameTooltip:AddLine("Double-click or Load: set, then talents, then gems.", 0.55, 0.88, 0.63, true)
            GameTooltip:Show()
        end)
        r:HookScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        lv.rows[i] = r
    end
    lscroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, LROW_H, RefreshLoadView)
    end)

    RefreshLoadView = function()
        if not lv:IsShown() then return end
        local Lo = PA.Loadouts
        if not Lo then return end
        local list = Lo.List()
        local offset = FauxScrollFrame_GetOffset(lscroll)
        for i = 1, LROWS do
            local r, p = lv.rows[i], list[i + offset]
            r.loadout = p
            if p then
                local active = Lo.IsActive(p)
                if active then r.activeBg:Show(); r.activeBar:Show() else r.activeBg:Hide(); r.activeBar:Hide() end
                r.iconFrame:SetTexture(Lo.Icon(p)); r.iconFrame:SetQuality(4)
                r.name:SetText(p.name .. (active and ("  " .. HEX_GOLD .. "Active|r") or ""))
                r.sub:SetText(Lo.Describe(p))
                if Lo.IsBusy() then r.load:SetDisabledLook(true); r.load:SetLabel(HEX_DIM .. "Load|r")
                else r.load:SetDisabledLook(false); r.load:SetLabel(HEX_BTN .. "Load|r") end
                r:Show()
            else
                r:Hide()
            end
        end
        FauxScrollFrame_Update(lscroll, #list, LROWS, LROW_H)
        if #list == 0 then lv.empty:Show() else lv.empty:Hide() end
    end
    lv:SetScript("OnShow", RefreshLoadView)
    if PA.Loadouts then
        PA.Loadouts.OnStatus(function(text) lv.status:SetText(text) end)
        PA.Loadouts.OnChanged(function() RefreshLoadView() end)
        if PA.Loadouts.AttachProgressBar then PA.Loadouts.AttachProgressBar(lbar, lv.status) end
    end

    -- view switch under the title: Equipment Sets | Loadouts
    local function ShowView(which)
        f.tabSets:SetActive(which == "sets")
        f.tabLoad:SetActive(which == "loadouts")
        if which == "loadouts" then lv:Show() else lv:Hide() end
    end
    f.tabSets = UI.MakeFilterChip(f, 130, "Equipment Sets", function() ShowView("sets") end)
    f.tabSets:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
    f.tabLoad = UI.MakeFilterChip(f, 100, "Loadouts", function() ShowView("loadouts") end)
    f.tabLoad:SetPoint("LEFT", f.tabSets, "RIGHT", 6, 0)
    ShowView("sets")

    f:SetScript("OnShow", function() Refresh() end)
    return f
end

Refresh = function()
    if RefreshTab then RefreshTab() end
    if not (win and win:IsShown()) then return end
    if not HasAPI() then
        SetStatus("This client has no equipment manager, so sets can't be saved here.", HEX_BAD)
        return
    end
    local sets = AllSets()
    if selected and not SetExists(selected) then selected = nil end
    win.count:SetText(HEX_GOLD .. #sets .. "|r" .. HEX_DIM .. " / " .. MAX_SETS .. " sets|r")
    for i = 1, NUM_ROWS do
        local r, s = win.rows[i], sets[i]
        r.set = s and s.name
        if s then
            local _, n = SetItems(s.name)
            local worn = IsWorn(s.name)
            if worn then r.wornBg:Show(); r.wornBar:Show() else r.wornBg:Hide(); r.wornBar:Hide() end
            for _, t in ipairs(r.sel) do if s.name == selected then t:Show() else t:Hide() end end
            -- the client often stores "?" as the set icon: show the set's weapon (or chest) instead
            local icon = s.icon
            if not icon or icon:lower():find("questionmark", 1, true) then
                local ids = GetEquipmentSetItemIDs(s.name) or {}
                for _, slot in ipairs({ 16, 5, 1, 17, 18 }) do
                    local id = ids[slot] or 0
                    if id > 1 and GetItemIcon then icon = GetItemIcon(id); break end
                end
            end
            r.iconFrame:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.iconFrame:SetQuality(4)
            r.name:SetText(s.name == selected and (HEX_GOLD .. s.name .. "|r") or s.name)
            r.sub:SetText((worn and (HEX_GOLD .. "Equipped|r" .. HEX_DIM .. "  ·  |r") or "")
                .. HEX_MUTED .. n .. (n == 1 and " item" or " items") .. "|r")
            r:Show()
        else
            r:Hide()
        end
    end
    if #sets == 0 then win.empty:Show() else win.empty:Hide() end

    ResetConfirm(win.del); ResetConfirm(win.update)
    if selected then
        local ids, n = SetItems(selected)
        win.selTitle:SetText(selected .. HEX_DIM .. "  ·  " .. n .. (n == 1 and " item" or " items") .. "|r")
        for k, slot in ipairs(SLOTS) do
            local t, id = win.slots[k], ids[slot] or 0
            if id > 1 then
                t.item = id
                t.icon:SetTexture(GetItemIcon and GetItemIcon(id) or select(10, GetItemInfo(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
                t.icon:SetAlpha(GetInventoryItemID("player", slot) == id and 1 or 0.45)
            else
                t.item = nil
                t.icon:SetTexture(SOLID); t.icon:SetVertexColor(UI.Tint(0.10, 0.13, 0.28, 1)); t.icon:SetAlpha(1)
            end
            if id > 1 then t.icon:SetVertexColor(1, 1, 1, 1) end
            t:Show()
        end
        local worn = IsWorn(selected)
        win.selNote:SetText(worn and (HEX_GOOD .. "You're wearing this set.|r")
            or (HEX_DIM .. "Faded items aren't equipped right now.|r"))
        win.equip:SetLabel(HEX_BTN .. "Equip|r"); win.equip:SetDisabledLook(false)
        win.update:SetDisabledLook(false); win.del:SetDisabledLook(false)
    else
        win.selTitle:SetText(HEX_DIM .. "Select a set to see its items, equip, update or delete it.|r")
        for _, t in ipairs(win.slots) do t:Hide() end
        win.selNote:SetText("")
        win.equip:SetLabel("Equip"); win.equip:SetDisabledLook(true)
        win.update:SetDisabledLook(true); win.del:SetDisabledLook(true)
    end
end

-- ── Builds > Set Builds (hub tab) ──────────────────────────────────
-- The same sets as the character window's Sets window, in the Talent Builds
-- layout: one row per set with Equip, Update and Delete.
local TAB_ROW_H, TAB_ROWS = 50, 10
local tabSelected      -- set shown in the tab's bottom panel
local SLOT_NAME = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [4] = "Shirt",
    [19] = "Tabard", [9] = "Wrist", [10] = "Hands", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
    [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

local function SetIcon(s)
    local icon = s.icon
    if not icon or icon:lower():find("questionmark", 1, true) then
        local ids = GetEquipmentSetItemIDs(s.name) or {}
        for _, slot in ipairs({ 16, 5, 1, 17, 18 }) do
            local id = ids[slot] or 0
            if id > 1 and GetItemIcon then return GetItemIcon(id) end
        end
    end
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function RowConfirm(r, btn, label, prompt, action)
    btn:SetScript("OnClick", function()
        local name = r.set
        if not name then return end
        if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then
            btn._confirmAt = nil
            btn:SetLabel(label)
            action(name)
        else
            btn._confirmAt = GetTime()
            btn:SetLabel("Sure?")
            SetStatus(string.format(prompt, name), HEX_WARN)
        end
    end)
    btn._idleLabel = label
end

local function SetPreview(r)
    if not r.set then return end
    local ids, n = SetItems(r.set)
    GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.set, 1, 1, 1)
    GameTooltip:AddLine(n .. (n == 1 and " item" or " items") .. (IsWorn(r.set) and "  ·  equipped" or ""), 0.75, 0.77, 0.88)
    GameTooltip:AddLine(" ")
    for _, slot in ipairs(SLOTS) do
        local id = ids[slot] or 0
        if id > 1 then
            local itemName, _, quality = GetItemInfo(id)
            local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
            local worn = GetInventoryItemID("player", slot) == id
            GameTooltip:AddDoubleLine(SLOT_NAME[slot] or "?", (itemName or ("item " .. id)) .. (worn and "" or "  (not worn)"),
                0.80, 0.82, 0.92, c and c.r or 1, c and c.g or 1, c and c.b or 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Equip takes the set's items from your bags.", 0.55, 0.88, 0.63, true)
    GameTooltip:Show()
end

local function CreateTabRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(TAB_ROW_H)
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(i - 1) * TAB_ROW_H)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(i - 1) * TAB_ROW_H)
    UI.MakeRowChrome(r)
    r:HookScript("OnEnter", SetPreview)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if i % 2 == 0 then
        local alt = r:CreateTexture(nil, "BACKGROUND"); alt:SetTexture(SOLID); alt:SetAllPoints(r)
        alt:SetVertexColor(1, 1, 1, 0.022)
    end
    if i > 1 then
        local d = r:CreateTexture(nil, "BORDER"); d:SetTexture(SOLID); d:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        d:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1); d:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1); d:SetHeight(1)
    end
    r.wornBg = r:CreateTexture(nil, "BACKGROUND"); r.wornBg:SetTexture(SOLID); r.wornBg:SetAllPoints(r)
    r.wornBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    r.wornBar = r:CreateTexture(nil, "ARTWORK"); r.wornBar:SetTexture(SOLID)
    r.wornBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    r.wornBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.wornBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.wornBar:SetWidth(3)
    -- selection: blue outline
    r.sel = {}
    for k = 1, 4 do r.sel[k] = r:CreateTexture(nil, "OVERLAY"); r.sel[k]:SetTexture(SOLID); r.sel[k]:SetVertexColor(UI.Tint(0.44, 0.82, 1, 1)) end
    r.sel[1]:SetPoint("TOPLEFT"); r.sel[1]:SetPoint("TOPRIGHT"); r.sel[1]:SetHeight(1)
    r.sel[2]:SetPoint("BOTTOMLEFT"); r.sel[2]:SetPoint("BOTTOMRIGHT"); r.sel[2]:SetHeight(1)
    r.sel[3]:SetPoint("TOPLEFT"); r.sel[3]:SetPoint("BOTTOMLEFT"); r.sel[3]:SetWidth(1)
    r.sel[4]:SetPoint("TOPRIGHT"); r.sel[4]:SetPoint("BOTTOMRIGHT"); r.sel[4]:SetWidth(1)
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnClick", function(self) if self.set then tabSelected = self.set; RefreshTab() end end)
    r:SetScript("OnDoubleClick", function(self) if self.set then EquipSet(self.set) end end)

    r.iconFrame = UI.MakeIconFrame(r, { size = 36 })
    r.iconFrame:SetPoint("LEFT", r, "LEFT", 10, 0)

    r.del = UI.MakeButton(r, "Delete", { w = 70, h = 24, variant = "danger" })
    r.del:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    RowConfirm(r, r.del, "Delete", "Click Sure? to delete '%s'.", DeleteSet)
    r.update = UI.MakeButton(r, "Update", { w = 70, h = 24, variant = "secondary" })
    r.update:SetPoint("RIGHT", r.del, "LEFT", -5, 0)
    RowConfirm(r, r.update, "Update", "Click Sure? to replace '%s' with the gear you're wearing.", UpdateSet)
    r.equip = UI.MakeButton(r, "Equip", { w = 78, h = 24, variant = "gold",
        onClick = function() if r.set then EquipSet(r.set) end end })
    r.equip:SetPoint("RIGHT", r.update, "LEFT", -10, 0)

    r.name = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.name, 14)
    r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 10, 2)
    r.name:SetPoint("RIGHT", r.equip, "LEFT", -10, 0)
    r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.sub = r:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(r.sub, 11)
    r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 10, -3)
    r.sub:SetPoint("RIGHT", r.equip, "LEFT", -10, 0)
    r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
    r:Hide()
    return r
end

RefreshTab = function()
    if not (tab and tab:IsVisible()) then return end
    if not HasAPI() then
        SetStatus("This client has no equipment manager, so sets can't be saved here.", HEX_BAD)
        return
    end
    local sets = AllSets()
    -- keep the selection if it still exists, else the worn set, else the first one
    if not (tabSelected and SetExists(tabSelected)) then
        tabSelected = nil
        for _, s in ipairs(sets) do if IsWorn(s.name) then tabSelected = s.name; break end end
        tabSelected = tabSelected or (sets[1] and sets[1].name)
    end
    for i = 1, TAB_ROWS do
        local r, s = tab.rows[i], sets[i]
        for _, t in ipairs(r.sel) do if s and s.name == tabSelected then t:Show() else t:Hide() end end
        if r.set ~= (s and s.name) then r.del._confirmAt, r.update._confirmAt = nil, nil end
        r.set = s and s.name
        ResetConfirm(r.del); ResetConfirm(r.update)
        if s then
            local _, n = SetItems(s.name)
            local worn = IsWorn(s.name)
            -- every row has Gem Stash's gold look; the worn one a stronger tint
            r.wornBg:Show(); r.wornBar:Show()
            r.wornBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, worn and 0.30 or 0.14, 0.94, 0.82, 0.43, 0)
            r.iconFrame:SetTexture(SetIcon(s))
            r.iconFrame:SetQuality(4)
            r.name:SetText(s.name)
            r.sub:SetText((worn and (HEX_GOLD .. "Equipped|r" .. HEX_DIM .. "  ·  |r") or "")
                .. HEX_MUTED .. n .. (n == 1 and " item" or " items") .. "|r")
            r.equip:SetLabel(HEX_BTN .. "Equip|r")
            r:Show()
        else
            r:Hide()
        end
    end
    tab.countText:SetText(HEX_GOLD .. #sets .. "|r" .. HEX_DIM .. " / " .. MAX_SETS .. " sets|r")
    if #sets == 0 then tab.empty:Show() else tab.empty:Hide() end

    -- bottom panel: the selected set's items
    if tabSelected then
        local ids, n = SetItems(tabSelected)
        local worn = IsWorn(tabSelected)
        tab.selTitle:SetText(HEX_GOLD .. tabSelected .. "|r" .. HEX_DIM .. "  ·  " .. n .. (n == 1 and " item" or " items") .. "|r")
        tab.selNote:SetText(worn and (HEX_GOOD .. "You're wearing this set.|r")
            or (HEX_DIM .. "Faded items aren't equipped right now.|r"))
        for _, t in ipairs(tab.slots) do
            local id = ids[t.slot] or 0
            if id > 1 then
                t.item = id
                t.empty = nil; t.mark:Hide()
                t.icon:SetTexture((GetItemIcon and GetItemIcon(id)) or select(10, GetItemInfo(id)) or "Interface\\Icons\\INV_Misc_QuestionMark")
                t.icon:SetAlpha(GetInventoryItemID("player", t.slot) == id and 1 or 0.4)
                t.icon:Show()
            else
                t.item = nil
                t.icon:Hide()
                t.empty = (ids[t.slot] == EMPTY_SLOT) or nil
                if t.empty then t.mark:Show() else t.mark:Hide() end
            end
            t:Show()
        end
    else
        tab.selTitle:SetText(HEX_DIM .. "Select a set to see its items.|r")
        tab.selNote:SetText("")
        for _, t in ipairs(tab.slots) do t:Hide() end
    end
end

local function BuildSetBuildsTab(panel)
    tab = panel
    local SIDE, top = 10, -8

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID); ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    local nameBox = UI.MakeSearchBox(panel, { width = 300, height = 26, placeholder = "Name a new set…" })
    UI.SetTextFont(nameBox.edit, 13); UI.StyleFilterSearch(nameBox); nameBox.__paBackdrop = true
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top)
    nameBox.edit:SetMaxLetters(16)
    nameBox.edit:SetScript("OnEnterPressed", function() SaveNew(nameBox) end)
    panel.nameBox = nameBox

    local saveBtn = UI.MakeButton(panel, "Save current", { w = 140, h = 26, variant = "gold",
        onClick = function() SaveNew(nameBox) end })
    saveBtn:SetLabel(HEX_BTN .. "Save current|r")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)

    panel.countText = panel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.countText, 13)
    panel.countText:SetPoint("RIGHT", panel, "TOPRIGHT", -SIDE - 2, top - 13)

    -- opens the character window; the hub closes so it isn't hidden behind it
    local charBtn = UI.MakeButton(panel, "Open Character", { w = 140, h = 26, variant = "secondary",
        onClick = function()
            if CharacterFrame and not CharacterFrame:IsShown() and ToggleCharacter then ToggleCharacter("PaperDollFrame") end
            local mf = PA.mainFrame
            if mf and mf:IsShown() then if mf.AnimatedHide then mf:AnimatedHide() else mf:Hide() end end
        end })
    charBtn:SetPoint("RIGHT", panel.countText, "LEFT", -16, 0)

    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(38)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top - 34); bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, top - 34)
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92); bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true
    bar.text = bar:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(bar.text, 12)
    bar.text:SetPoint("LEFT", bar, "LEFT", 12, 0); bar.text:SetPoint("RIGHT", bar, "RIGHT", -12, 0)
    bar.text:SetJustifyH("LEFT"); bar.text:SetWordWrap(false)
    panel.bar = bar

    -- selected set: every item, hover for its tooltip
    local selPanel = CreateFrame("Frame", nil, panel)
    selPanel:SetHeight(84)
    selPanel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", SIDE, 10)
    selPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, 10)
    Navy(selPanel, UI.Tinted({ 0.063, 0.090, 0.227, 0.95 }), UI.Tinted({ 0.173, 0.216, 0.408, 1 }))
    panel.selTitle = selPanel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.selTitle, 13)
    panel.selTitle:SetPoint("TOPLEFT", selPanel, "TOPLEFT", 12, -10)
    panel.selNote = selPanel:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.selNote, 11)
    panel.selNote:SetPoint("TOPRIGHT", selPanel, "TOPRIGHT", -12, -11)
    panel.slots = {}
    for k = 1, #SLOTS do
        local t = CreateFrame("Button", nil, selPanel)
        t:SetSize(34, 34)
        t:SetPoint("TOPLEFT", selPanel, "TOPLEFT", 12 + (k - 1) * 38, -34)
        t.bg = t:CreateTexture(nil, "BACKGROUND"); t.bg:SetTexture(SOLID); t.bg:SetAllPoints(t)
        t.bg:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 1))
        t.icon = t:CreateTexture(nil, "ARTWORK")
        t.icon:SetPoint("TOPLEFT", t, "TOPLEFT", 1, -1); t.icon:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -1, 1)
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.slot = SLOTS[k]
        -- slots the set saved as empty: it takes off what you wear there
        t.mark = t:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(t.mark, 16)
        t.mark:SetPoint("CENTER", t, "CENTER", 0, 1)
        t.mark:SetText("|cffff9a8f×|r"); t.mark:Hide()
        t:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.item then
                GameTooltip:SetHyperlink("item:" .. self.item)
                if GetInventoryItemID("player", self.slot) ~= self.item then
                    GameTooltip:AddLine("Not worn right now", 1, 0.6, 0.56)
                end
            elseif self.empty then
                GameTooltip:SetText((SLOT_NAME[self.slot] or "Slot") .. ": left empty by this set", 1, 0.6, 0.56)
                if GetInventoryItemID("player", self.slot) then
                    GameTooltip:AddLine("What you wear here is taken off when you equip the set.", 0.8, 0.8, 0.85, true)
                end
            else
                GameTooltip:SetText((SLOT_NAME[self.slot] or "Slot") .. ": not part of this set", 0.8, 0.8, 0.85)
            end
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t:SetScript("OnClick", function(self)
            if self.item and IsModifiedClick("CHATLINK") and PA.InsertChatLink then
                PA.InsertChatLink(select(2, GetItemInfo(self.item)))
            end
        end)
        panel.slots[k] = t
    end

    local listPanel = CreateFrame("Frame", nil, panel)
    listPanel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", selPanel, "TOPRIGHT", 0, 8)
    Navy(listPanel, { 0.099, 0.099, 0.099, 0.95 }, { 0.256, 0.256, 0.256, 1 })   -- same dark grey as the Gem Stash list
    local inner = CreateFrame("Frame", nil, listPanel)
    inner:SetPoint("TOPLEFT", listPanel, "TOPLEFT", 6, -6); inner:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -6, 6)
    panel.rows = {}
    for i = 1, TAB_ROWS do panel.rows[i] = CreateTabRow(inner, i) end
    panel.empty = inner:CreateFontString(nil, "OVERLAY"); UI.SetTextFont(panel.empty, 13)
    panel.empty:SetPoint("TOP", inner, "TOP", 0, -30)
    panel.empty:SetText(HEX_MUTED .. "No sets yet. Name one above and click Save current.|r")

    panel:SetScript("OnShow", function()
        SetStatus("Save the gear you're wearing as a set, then equip it from here or from the character window's Sets button.")
        RefreshTab()
    end)
    SetStatus("Save the gear you're wearing as a set, then equip it from here or from the character window's Sets button.")
    RefreshTab()
end

local function OpenSetBuildsTab()
    local mf = PA.mainFrame
    if not mf then return end
    mf:Show()
    mf:SwitchTab("set_builds")
end

PA:RegisterModule("set_builds", "Set Builds", OpenSetBuildsTab, {
    subtitle = "Save the gear you wear as sets and swap between them in one click.",
})
PA:RegisterTabContent("set_builds", BuildSetBuildsTab)

-- opening the Project Astral hub closes the Sets window
local hubHooked
local function HookHub()
    if hubHooked or not PA.mainFrame then return end
    hubHooked = true
    PA.mainFrame:HookScript("OnShow", function()
        if win and win:IsShown() then win:Hide() end
    end)
end

local function Toggle()
    HookHub()
    win = win or BuildWindow()
    if win:IsShown() then
        win:AnimatedHide()
        return
    end
    win:ClearAllPoints()
    if CharacterFrame and CharacterFrame:IsShown() then
        win:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -30, -12)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    SetStatus("Save what you're wearing as a new set, or select one to equip, update or delete it.")
    win:Show()
end
PA.ToggleEquipmentSets = Toggle

-- ── the Sets button in the character window ────────────────────────
local function InitButton()
    if _G.PAEquipmentSetsButton or not PaperDollFrame then return end
    local b = CreateFrame("Button", "PAEquipmentSetsButton", PaperDollFrame, "UIPanelButtonTemplate")
    if UI.CosmicButton then UI.CosmicButton(b) end
    b:SetSize(62, 22)
    b:SetText("Sets")
    if CharacterFrameCloseButton then
        b:SetPoint("TOPRIGHT", CharacterFrameCloseButton, "BOTTOMRIGHT", -6, -6)
    else
        b:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -40, -40)
    end
    b:SetFrameLevel((PaperDollFrame:GetFrameLevel() or 1) + 5)
    b:SetScript("OnClick", Toggle)
    b:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Equipment Sets", 1, 1, 1)
        GameTooltip:AddLine("Save your gear as named sets and swap between them.", 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Blizzard's own equipment manager button sits in the same corner: keep it (and
    -- its window) hidden, the Sets window replaces them
    for _, name in ipairs({ "GearManagerToggleButton", "GearManagerDialog" }) do
        local native = _G[name]
        if native then
            native:HookScript("OnShow", function(self) self:Hide() end)
            native:Hide()
        end
    end
    -- the window follows the character window
    if CharacterFrame then
        CharacterFrame:HookScript("OnHide", function() if win and win:IsShown() then win:Hide() end end)
    end
end

-- the "Equipment Manager is disabled" error: replace it with the info popup
local function CatchManagerOff(msg)
    msg = type(msg) == "string" and msg:lower() or ""
    local open = (win and win:IsShown()) or (tab and tab:IsVisible())
    if not (open and msg:find("equipment manager", 1, true) and msg:find("disabled", 1, true)) then return end
    if UIErrorsFrame then UIErrorsFrame:Clear() end
    equipping = nil
    emptying.name = nil; emptyRunner:Hide()   -- the set wasn't put on: don't take anything off
    SetStatus("The Equipment Manager is turned off: Game Menu > Interface > Features.", HEX_WARN)
    if not StaticPopup_Visible or not StaticPopup_Visible("PA_EQUIPMENT_MANAGER_OFF") then
        StaticPopup_Show("PA_EQUIPMENT_MANAGER_OFF")
    end
end
-- the client may print it straight into the error frame rather than through the event
if UIErrorsFrame then
    hooksecurefunc(UIErrorsFrame, "AddMessage", function(_, msg) CatchManagerOff(msg) end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
events:RegisterEvent("UI_ERROR_MESSAGE")
events:SetScript("OnEvent", function(_, event, a1, a2)
    if event == "UI_ERROR_MESSAGE" then
        CatchManagerOff(a1)
        return
    end
    if event == "PLAYER_LOGIN" then
        InitButton()
        HookHub()
        return
    end
    if event == "EQUIPMENT_SWAP_FINISHED" and equipping then
        -- the set's items are on: now take off what it leaves empty (then report)
        StartEmptying(a2 or equipping, 0.2)
    end
    Refresh()
end)

SLASH_PAEQUIPSETS1 = "/sets"
SlashCmdList["PAEQUIPSETS"] = Toggle

-- Saved sets that include the item in this bag slot. The equipment manager keeps
-- where each set's items are, so only that exact item matches (a second copy of the
-- same item elsewhere in the bags doesn't); without location info, item ids decide.
local function SetsWithBagItem(bag, slot)
    local out = {}
    if not (HasAPI() and bag and slot) then return out end
    local itemID = GetContainerItemID and GetContainerItemID(bag, slot)
    if not itemID then return out end
    for _, s in ipairs(AllSets()) do
        local found = false
        local locs = GetEquipmentSetLocations and GetEquipmentSetLocations(s.name)
        if locs and EquipmentManager_UnpackLocation then
            for _, loc in pairs(locs) do
                if type(loc) == "number" and loc > 1 then   -- -1 missing, 0 empty, 1 ignored
                    local _, bank, bags, lslot, lbag = EquipmentManager_UnpackLocation(loc)
                    if bags and not bank and lbag == bag and lslot == slot then found = true; break end
                end
            end
        else
            for _, id in pairs(GetEquipmentSetItemIDs(s.name) or {}) do
                if id == itemID then found = true; break end
            end
        end
        if found then out[#out + 1] = s.name end
    end
    return out
end

-- used by Loadouts.lua (a loadout can include one of these sets) and by
-- AstralDisenchant.lua (items saved in a set can't go in the Disenchant table)
PA.EquipmentSets = {
    SetsWithBagItem = SetsWithBagItem,
    Available = function() return HasAPI() and true or false end,
    List      = function() return HasAPI() and AllSets() or {} end,
    Exists    = function(name) return name and HasAPI() and SetExists(name) or nil end,
    IsWorn    = function(name) return HasAPI() and IsWorn(name) or false end,
    Icon      = function(name)
        for _, s in ipairs(HasAPI() and AllSets() or {}) do
            if s.name == name then return SetIcon(s) end
        end
    end,
    Equip     = EquipSet,
    IsBusy    = function() return equipping ~= nil or emptying.name ~= nil end,
}
