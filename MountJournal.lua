
local PA = ProjectAstral
local UI = PA.UI


local SOLID    = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local H        = 564
local TOP_H    = 26
local GAP      = 10
local LIST_W   = 300
local LIST_H   = H - TOP_H - GAP
local ROW_H    = 34
local TRACK_H  = LIST_H - 8
local VIS      = math.floor(TRACK_H / ROW_H)
local TINT     = { 1.00, 0.58, 0.78 }
local GOOD     = { 0.55, 1.00, 0.70 }

local MJ = {}
PA.MountJournal = MJ

local host, list, rows, track, thumb, emptyText, countText
local model, bigIcon, fsNote, nameText, stateText, summonBtn, linkBtn
local mounts, shown = {}, {}
local query, offset, selected = "", 0, nil
local needCollect, needActive = true, false
local dragBars = {}

local function ShowActionBarsForDrag()
    dragBars = {}
    local bars = {
        MainMenuBar,
        MultiBarBottomLeft,
        MultiBarBottomRight,
        MultiBarLeft,
        MultiBarRight,
    }
    for _, bar in ipairs(bars) do
        if bar and bar.IsShown and not bar:IsShown() then
            dragBars[#dragBars + 1] = bar
            bar:Show()
        end
    end
end

local function RestoreActionBarsAfterDrag()
    for _, bar in ipairs(dragBars) do
        if bar and bar.Hide then bar:Hide() end
    end
    dragBars = {}
end


local function Collect()
    mounts = {}
    local known = {}
    local n = (type(GetNumCompanions) == "function" and GetNumCompanions("MOUNT")) or 0
    for i = 1, n do
        local creatureID, name, spellID, icon, active = GetCompanionInfo("MOUNT", i)
        if spellID and not known[spellID] then
            known[spellID] = true
            mounts[#mounts + 1] = {
                index = i, creature = creatureID, spell = spellID, icon = icon,
                name = name or GetSpellInfo(spellID) or ("Mount " .. i),
                active = active and true or false,
            }
        end
    end

    local custom = PA.CustomMountIds
    if type(custom) == "table" and type(GetNumSpellTabs) == "function" then
        local set = {}
        for _, id in ipairs(custom) do set[id] = true end
        for t = 1, GetNumSpellTabs() do
            local _, _, off, num = GetSpellTabInfo(t)
            off, num = off or 0, num or 0
            for slot = off + 1, off + num do
                local link = GetSpellLink(slot, BOOKTYPE_SPELL)
                local id = link and tonumber(link:match("spell:(%d+)"))
                if id and set[id] and not known[id] then
                    known[id] = true
                    local name = GetSpellInfo(id) or ("Mount " .. id)
                    mounts[#mounts + 1] = {
                        slot = slot, spell = id, name = name,
                        icon = GetSpellTexture(slot, BOOKTYPE_SPELL),
                        active = UnitBuff("player", name) and true or false,
                    }
                end
            end
        end
    end

    table.sort(mounts, function(a, b) return a.name < b.name end)
end

local function UpdateActive()
    needActive = false
    for _, m in ipairs(mounts) do
        if m.index then
            local _, _, spellID, _, active = GetCompanionInfo("MOUNT", m.index)
            if spellID ~= m.spell then needCollect = true; return end
            m.active = active and true or false
        else
            m.active = UnitBuff("player", m.name) and true or false
        end
    end
end

local function ApplyFilter()
    shown = {}
    for _, m in ipairs(mounts) do
        if query == "" or m.name:lower():find(query, 1, true) then
            shown[#shown + 1] = m
        end
    end
end

local function MaxOffset() return math.max(0, #shown - VIS) end


local function Summon(m)
    if not m then return end
    if UnitAffectingCombat("player") then
        UIErrorsFrame:AddMessage(SPELL_FAILED_AFFECTING_COMBAT or "You are in combat.", 1.0, 0.1, 0.1, 1.0)
        return
    end
    if m.active then
        if type(Dismount) == "function" then Dismount() else DismissCompanion("MOUNT") end
    elseif m.index then
        CallCompanion("MOUNT", m.index)
    else
        SendChatMessage(".mount " .. m.spell, "SAY")
    end
end

local function Pickup(m)
    if not m then return end
    if m.index then
        PickupCompanion("MOUNT", m.index)
    elseif m.slot then
        PickupSpell(m.slot, BOOKTYPE_SPELL)
    end
end

local function LinkMount(m)
    local link = m and GetSpellLink(m.spell)
    if not link then return end
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) then
        ChatFrame_OpenChat(link)
    end
end


local lastFull

local function IsFullscreen()
    local mf = PA.mainFrame
    return (mf and mf._fullscreen) and true or false
end

local function PaintPreview()
    if not nameText then return end
    lastFull = IsFullscreen()
    local m = selected
    if not m then
        nameText:SetText("No mount selected")
        stateText:SetText("")
        model:Hide()
        bigIcon:Hide()
        fsNote:Hide()
        summonBtn:SetDisabledLook(true)
        linkBtn:SetDisabledLook(true)
        return
    end
    nameText:SetText(m.name)
    if m.creature and model.SetCreature and lastFull then
        if model._creature ~= m.creature then
            model._creature = m.creature
            model:SetCreature(m.creature)
        end
        model:Show()
        bigIcon:Hide()
        fsNote:Hide()
    else
        model:Hide()
        bigIcon:SetTexture(m.icon or QUESTION)
        bigIcon:Show()
        if m.creature and not lastFull then fsNote:Show() else fsNote:Hide() end
    end
    summonBtn:SetDisabledLook(false)
    linkBtn:SetDisabledLook(false)
    summonBtn:SetLabel(m.active and "Dismount" or "Summon")
    if m.active then
        stateText:SetText("Summoned")
        stateText:SetTextColor(unpack(GOOD))
    else
        stateText:SetText("Known")
        stateText:SetTextColor(unpack(UI.Nav.muted))
    end
end

function MJ.Render()
    if not list then return end
    local maxOff = MaxOffset()
    if offset > maxOff then offset = maxOff end

    for i = 1, VIS do
        local r = rows[i]
        local m = shown[offset + i]
        r.mount = m
        if m then
            r.icon:SetTexture(m.icon or QUESTION)
            r.name:SetText(m.name)
            r.tag:SetText(m.active and "Summoned" or "")
            if m == selected then
                r.bg:SetVertexColor(TINT[1], TINT[2], TINT[3], 0.16)
                r.bar:Show()
                r.name:SetTextColor(unpack(UI.Color.textTitle))
            else
                r.bg:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
                r.bar:Hide()
                r.name:SetTextColor(unpack(UI.Color.textPrimary))
            end
            r:Show()
        else
            r:Hide()
        end
    end

    if #shown > VIS then
        local h = math.max(18, math.floor(TRACK_H * VIS / #shown))
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -math.floor((TRACK_H - h) * offset / maxOff))
        track:Show()
        thumb:Show()
    else
        track:Hide()
        thumb:Hide()
    end

    countText:SetText(#mounts .. (#mounts == 1 and " mount" or " mounts"))
    if #shown == 0 then
        emptyText:SetText(#mounts == 0 and "This character doesn't know any mounts yet."
                                        or "No mounts match your search.")
        emptyText:Show()
    else
        emptyText:Hide()
    end
    PaintPreview()
end

function MJ.Refresh()
    if not (host and host:IsVisible()) then needCollect = true; return end
    needCollect, needActive = false, false
    local keep = selected and selected.spell
    Collect()
    selected = nil
    for _, m in ipairs(mounts) do
        if m.spell == keep then selected = m; break end
    end
    ApplyFilter()
    if not selected then selected = shown[1] or mounts[1] end
    MJ.Render()
end

local function ScrollBy(delta)
    local o = math.max(0, math.min(MaxOffset(), offset + delta))
    if o ~= offset then
        offset = o
        MJ.Render()
    end
end

local function SummonRandom()
    local pool = {}
    for _, m in ipairs(mounts) do
        if not m.active then pool[#pool + 1] = m end
    end
    if #pool == 0 then return end
    selected = pool[math.random(#pool)]
    Summon(selected)
    MJ.Render()
end


local function MakeRow(i)
    local r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H - 2)
    r:SetPoint("TOPLEFT",  list, "TOPLEFT",   4, -4 - (i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", -12, -4 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    r:RegisterForDrag("LeftButton")

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetTexture(SOLID)
    r.bg:SetAllPoints()

    local hover = r:CreateTexture(nil, "BORDER")
    hover:SetTexture(SOLID)
    hover:SetAllPoints()
    hover:SetVertexColor(1, 1, 1, 0.06)
    hover:Hide()

    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture(SOLID)
    r.bar:SetWidth(2)
    r.bar:SetPoint("TOPLEFT",    r, "TOPLEFT",    0, 0)
    r.bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.bar:SetVertexColor(TINT[1], TINT[2], TINT[3], 1)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.tag = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.tag:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.tag:SetTextColor(unpack(GOOD))

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT",  r.icon, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r,      "RIGHT", -66, 0)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end

    r:SetScript("OnEnter", function(self)
        hover:Show()
        if self.mount then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("spell:" .. self.mount.spell)
            GameTooltip:AddLine("Double-click to summon. Drag to an action bar.", 0.6, 0.8, 1.0)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function()
        hover:Hide()
        GameTooltip:Hide()
    end)
    r:SetScript("OnClick", function(self)
        local m = self.mount
        if not m then return end
        if IsShiftKeyDown() then LinkMount(m); return end
        selected = m
        MJ.Render()
    end)
    r:SetScript("OnDoubleClick", function(self)
        if self.mount and not IsShiftKeyDown() then Summon(self.mount) end
    end)
    r:SetScript("OnDragStart", function(self)
        ShowActionBarsForDrag()
        Pickup(self.mount)
    end)
    r:SetScript("OnDragStop", RestoreActionBarsAfterDrag)
    return r
end

local function BuildMountJournal(panel)
    host = panel

    list = CreateFrame("Frame", nil, panel)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(TOP_H + GAP))
    list:SetSize(LIST_W, LIST_H)
    UI.AstralBackdrop(list, { thin = true, bg = UI.Nav.deep, border = UI.Nav.edge })
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) ScrollBy(-delta * 3) end)

    rows = {}
    for i = 1, VIS do rows[i] = MakeRow(i) end

    track = list:CreateTexture(nil, "ARTWORK")
    track:SetTexture(SOLID)
    track:SetWidth(3)
    track:SetHeight(TRACK_H)
    track:SetPoint("TOPRIGHT", list, "TOPRIGHT", -5, -4)
    track:SetVertexColor(UI.Nav.edge[1], UI.Nav.edge[2], UI.Nav.edge[3], 0.8)

    thumb = list:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(SOLID)
    thumb:SetWidth(3)
    thumb:SetVertexColor(unpack(UI.Color.accentSoft))

    emptyText = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT",  list, "TOPLEFT",  14, -18)
    emptyText:SetPoint("TOPRIGHT", list, "TOPRIGHT", -14, -18)
    emptyText:SetJustifyH("LEFT")

    local search = UI.MakeSearchBox(panel, {
        width = 220, height = 24, placeholder = "Search mounts…",
        onChanged = function(text)
            query = (text or ""):lower()
            offset = 0
            ApplyFilter()
            MJ.Render()
        end,
    })
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)

    countText = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    countText:SetPoint("LEFT", search, "RIGHT", 10, 0)

    local randomBtn = UI.MakeButton(panel, "Random mount", {
        w = 130, h = 24, variant = "secondary", onClick = SummonRandom,
    })
    randomBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)

    local preview = CreateFrame("Frame", nil, panel)
    preview:SetPoint("TOPLEFT",     panel, "TOPLEFT",     LIST_W + GAP, -(TOP_H + GAP))
    preview:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    UI.AstralBackdrop(preview, { thin = true, bg = UI.Nav.deep, border = UI.Nav.edge })

    model = CreateFrame("PlayerModel", nil, preview)
    model:SetPoint("TOPLEFT",  preview, "TOPLEFT",   8, -8)
    model:SetPoint("TOPRIGHT", preview, "TOPRIGHT", -8, -8)
    model:SetHeight(300)
    model._facing = 0.5
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self)
        local x = GetCursorPosition()
        self._dragX, self._downX = x, x
    end)
    model:SetScript("OnMouseUp", function(self)
        local x = GetCursorPosition()
        local clicked = self._downX and math.abs(x - self._downX) < 4
        self._dragX, self._downX = nil, nil
        if clicked and selected and selected.creature and PA.MountViewer then
            PA.MountViewer.Show({ creature = selected.creature, name = selected.name })
        end
    end)
    model:SetScript("OnHide", function(self) self._dragX, self._downX = nil, nil end)
    model:SetScript("OnUpdate", function(self, dt)
        if self._dragX then
            local x = GetCursorPosition()
            self._facing = self._facing + (x - self._dragX) * 0.012
            self._dragX = x
        else
            self._facing = self._facing + dt * 0.35
        end
        self:SetFacing(self._facing)
    end)
    model:SetScript("OnShow", function(self)
        if self._creature then self:SetCreature(self._creature) end
    end)

    bigIcon = preview:CreateTexture(nil, "ARTWORK")
    bigIcon:SetSize(64, 64)
    bigIcon:SetPoint("CENTER", model, "CENTER", 0, 0)
    bigIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    bigIcon:Hide()

    fsNote = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fsNote:SetPoint("TOP",   bigIcon, "BOTTOM", 0, -12)
    fsNote:SetPoint("LEFT",  preview, "LEFT",   16, 0)
    fsNote:SetPoint("RIGHT", preview, "RIGHT", -16, 0)
    fsNote:SetJustifyH("CENTER")
    fsNote:SetTextColor(unpack(UI.Nav.muted))
    fsNote:SetText("Go full screen (the button next to the close X) to see the 3D model.")
    fsNote:Hide()

    nameText = preview:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 14, "")
    nameText:SetPoint("TOPLEFT",  model, "BOTTOMLEFT",  2, -10)
    nameText:SetPoint("TOPRIGHT", model, "BOTTOMRIGHT", -2, -10)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(unpack(UI.Color.textTitle))

    stateText = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    stateText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -6)

    summonBtn = UI.MakeButton(preview, "Summon", {
        w = 116, h = 26, variant = "gold",
        onClick = function() Summon(selected) end,
    })
    summonBtn:SetPoint("TOPLEFT", stateText, "BOTTOMLEFT", 0, -14)

    linkBtn = UI.MakeButton(preview, "Link in chat", {
        w = 116, h = 26, variant = "secondary",
        onClick = function() LinkMount(selected) end,
    })
    linkBtn:SetPoint("LEFT", summonBtn, "RIGHT", 8, 0)

    local hint = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT",  preview, "BOTTOMLEFT",  10, 10)
    hint:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT", -10, 10)
    hint:SetJustifyH("LEFT")
    hint:SetText("Double-click a mount to summon it, drag it onto an action bar, or Shift-click it to link it. In full screen, drag the model to turn it or click it to see just the mount.")

    panel:SetScript("OnShow", function() MJ.Refresh() end)
    local acc = 0
    panel:SetScript("OnUpdate", function(_, dt)
        if IsFullscreen() ~= lastFull then PaintPreview() end
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        if needCollect then
            MJ.Refresh()
        elseif needActive then
            UpdateActive()
            if not needCollect then MJ.Render() end
        end
    end)
    MJ.Refresh()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "COMPANION_LEARNED", "COMPANION_UNLEARNED", "COMPANION_UPDATE",
                     "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "UNIT_AURA" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if unit == "player" then needActive = true end
    elseif event == "COMPANION_UPDATE" then
        needActive = true
    else
        needCollect = true
    end
end)

local function ToggleMounts()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf.activeTab and mf.activeTab.id == "collections" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("collections")
        if mf._tabBar then mf._tabBar:SelectTab("collections") end
    end
end

SLASH_PAMOUNTS1 = "/mounts"
SLASH_PAMOUNTS2 = "/mountjournal"
SlashCmdList["PAMOUNTS"] = ToggleMounts

PA:RegisterModule("mount_journal", "Mount Journal", ToggleMounts, {
    subtitle = "Every mount you know. Double-click to summon, drag to your bars.",
})
PA:RegisterTabContent("mount_journal", BuildMountJournal)
