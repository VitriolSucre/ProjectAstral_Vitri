
local PA = ProjectAstral
local UI = PA.UI

-- Gem Builds tab: save gem loadouts by name, update them, and load them again later
-- on any character on the account (ProjectAstralGemBuilds is account-wide). Loading
-- uses the same one-click import as Astral Gems (AG.ApplyLoadoutText): gems come from
-- the Gem Stash (lower tiers if needed) and gems in the way are unsocketed first. The
-- action bar shows each step while a build loads (AG.OnApplyProgress).
-- Colours that must survive Theme.lua's vivid-text pass are inline |c codes.

local ROW_H    = 56
local NUM_ROWS = 10
local CONFIRM_WINDOW = 3   -- seconds to click Delete / Update a second time
local DONE_HOLD      = 8   -- seconds the "loaded" result stays in the bar

local SOLID = "Interface\\Buttons\\WHITE8X8"

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"
local HEX_BAD   = "|cffff9a8f"
local HEX_BTN_GOLD = "|cffffe39a"

local host
local rows = {}
local RefreshList
local exportDialog, importDialog
local loadingName          -- build being loaded, for the progress bar

local function DB()
    ProjectAstralGemBuilds = ProjectAstralGemBuilds or {}
    ProjectAstralGemBuilds.builds = ProjectAstralGemBuilds.builds or {}
    return ProjectAstralGemBuilds.builds
end

local function Gems() return PA.AstralGems end

local function Trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function SortedBuilds()
    local list = {}
    for _, b in ipairs(DB()) do list[#list + 1] = b end
    table.sort(list, function(a, b) return (a.savedAt or 0) > (b.savedAt or 0) end)
    return list
end

local function FindBuild(name)
    local lower = name:lower()
    for i, b in ipairs(DB()) do
        if (b.name or ""):lower() == lower then return b, i end
    end
end

local function IsApplying()
    local G = Gems()
    return G and G.IsApplyingLoadout and G.IsApplyingLoadout()
end

-- ── Action bar: status messages, and the loading progress ──
local function SetStatus(text, hex)
    if not host then return end
    host.bar.fill:Hide()
    host.bar.counter:SetText("")
    host.bar.text:SetText((hex or HEX_MUTED) .. text .. "|r")
    host.bar._holdUntil = nil
end

local function SetProgress(state)
    if not host then return end
    local bar = host.bar
    local total = math.max(1, state.total or 1)
    local frac
    if state.finished then
        frac = 1
        local ok = (state.failed or 0) == 0
        bar.fill:SetVertexColor(ok and 0.50 or 1.00, ok and 0.88 or 0.80, ok and 0.63 or 0.40, 0.55)
        local parts = { (state.done or 0) .. " socketed" }
        if (state.removed or 0) > 0 then parts[#parts + 1] = state.removed .. " removed" end
        if (state.failed or 0) > 0 then parts[#parts + 1] = state.failed .. " failed" end
        bar.text:SetText((ok and HEX_GOOD or HEX_WARN) .. "Build '" .. (loadingName or "?") .. "' loaded: "
            .. table.concat(parts, ", ") .. ".|r")
        bar.counter:SetText(HEX_MUTED .. total .. " / " .. total .. "|r")
        bar._holdUntil = GetTime() + DONE_HOLD
        loadingName = nil
    else
        frac = ((state.step or 1) - 1) / total
        bar.fill:SetVertexColor(0.886, 0.753, 0.384, 0.45)
        bar.text:SetText(HEX_GOLD .. "Loading '" .. (loadingName or "build") .. "'|r"
            .. HEX_MUTED .. "  ·  " .. (state.text or "") .. "…|r")
        bar.counter:SetText(HEX_MUTED .. (state.step or 1) .. " / " .. total .. "|r")
    end
    local w = math.max(1, (bar:GetWidth() - 8) * frac)
    bar.fill:SetWidth(w)
    bar.fill:Show()
    if RefreshList then RefreshList() end   -- Load buttons follow the busy state
end

-- ── Do you have the gems? ───────────────────────────────────────────
local function GemStatus(b)
    local G = Gems()
    return G and G.LoadoutGemStatus and b and G.LoadoutGemStatus(b.text)
end

local function ShortAvailability(st, count)
    if not st or st.total == 0 then
        return string.format("%s%d gem%s|r", HEX_MUTED, count or 0, (count == 1) and "" or "s")
    end
    if st.missing > 0 then
        return string.format("%s%d/%d gems, %d missing|r", HEX_BAD, st.exact + st.lower, st.total, st.missing)
    elseif st.lower > 0 then
        return string.format("%s%d/%d gems, %d at a lower tier|r", HEX_WARN, st.total, st.total, st.lower)
    end
    return string.format("%sAll %d gems owned|r", HEX_GOOD, st.total)
end

local function LongAvailability(st)
    if not st or st.total == 0 then return nil end
    if st.missing == 0 and st.lower == 0 then
        return string.format("%sYou have all %d gems for this build.|r", HEX_GOOD, st.total)
    end
    local extra = {}
    if st.lower > 0 then extra[#extra + 1] = st.lower .. " more only at a lower tier" end
    if st.missing > 0 then extra[#extra + 1] = st.missing .. " missing" end
    return string.format("%sYou have %d of the %d gems (%s).|r",
        st.missing > 0 and HEX_BAD or HEX_WARN, st.exact, st.total, table.concat(extra, ", "))
end

-- the build matches the gems socketed right now (same gem in every socket)
local function IsEquipped(b)
    local G = Gems()
    if not (G and G.EncodeLoadout and G.DecodeLoadout) then return false end
    local current, count = G.EncodeLoadout()
    if count == 0 then return false end
    local function Key(text)
        local set = {}
        for _, w in ipairs(G.DecodeLoadout(text) or {}) do
            set[#set + 1] = w.ord .. "." .. w.idx .. "=" .. w.entry
        end
        table.sort(set)
        return table.concat(set, ",")
    end
    return Key(b.text) == Key(current)
end

local function StampBuild(build, text, count)
    local className, classFile = UnitClass("player")
    build.text, build.count = text, count
    build.savedBy, build.class, build.classFile = UnitName("player"), className, classFile
    build.savedAt, build.date = time(), date("%Y-%m-%d")
end

local function SaveCurrent()
    local G = Gems()
    if not (host and G and G.EncodeLoadout) then return end
    local name = Trim(host.nameBox:GetText())
    if name == "" then
        SetStatus("Type a name for this build first.", HEX_WARN)
        host.nameBox.edit:SetFocus()
        return
    end
    local text, count = G.EncodeLoadout()
    if count == 0 then
        SetStatus("No gems are socketed, so there's nothing to save.", HEX_WARN)
        return
    end

    local existing = FindBuild(name)
    local build = existing or { name = name }
    StampBuild(build, text, count)
    if not existing then table.insert(DB(), build) end

    host.nameBox:Clear()
    host.nameBox.edit:ClearFocus()
    SetStatus(string.format("%s build '%s' (%d gem%s).", existing and "Updated" or "Saved",
        name, count, count == 1 and "" or "s"), HEX_GOOD)
    RefreshList()
end

local function UpdateBuild(b)
    local G = Gems()
    if not (G and G.EncodeLoadout) then return end
    local text, count = G.EncodeLoadout()
    if count == 0 then
        SetStatus("No gems are socketed, so there's nothing to update the build with.", HEX_WARN)
        return
    end
    StampBuild(b, text, count)
    SetStatus(string.format("Updated '%s' with the %d gem%s socketed now.", b.name or "?",
        count, count == 1 and "" or "s"), HEX_GOOD)
    RefreshList()
end

-- ── Higher tiers you own ────────────────────────────────────────────
-- For each gem in the build, the best non-mythic tier of the same family that
-- you own (stash + socketed), when it is higher than the build's tier.
local function FindUpgrades(b)
    local G = Gems()
    local catalog = PA.GemFusion and PA.GemFusion.catalog
    if not (G and G.DecodeLoadout and catalog and next(catalog)) then return {} end

    local owned = {}
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    for entry, n in pairs(stock) do owned[entry] = n end
    for _, slot in pairs(G.loadout or {}) do
        for _, data in pairs(slot) do
            if data.gemId and data.gemId > 0 then owned[data.gemId] = (owned[data.gemId] or 0) + 1 end
        end
    end

    local best = {}
    for entry, cat in pairs(catalog) do
        local family, tier = cat.family, tonumber(cat.tier)
        if family and family ~= "" and tier and not cat.isMythic and (owned[entry] or 0) > 0 then
            if not best[family] or tier > best[family].tier then
                best[family] = { entry = entry, tier = tier }
            end
        end
    end

    local ups = {}
    for i, w in ipairs(G.DecodeLoadout(b.text) or {}) do
        local cat  = catalog[w.entry]
        local tier = cat and tonumber(cat.tier)
        local top  = cat and not cat.isMythic and best[cat.family or ""]
        if tier and top and top.tier > tier then
            ups[#ups + 1] = { index = i, ord = w.ord, from = w.entry, to = top.entry,
                              fromTier = tier, toTier = top.tier }
        end
    end
    return ups
end

-- build text with the chosen upgrades swapped in
local function UpgradedText(b, ups)
    local G = Gems()
    local wanted = G.DecodeLoadout(b.text) or {}
    for _, u in ipairs(ups) do
        if wanted[u.index] then wanted[u.index].entry = u.to end
    end
    local parts = {}
    for _, w in ipairs(wanted) do
        parts[#parts + 1] = string.format("%d.%d=%d", w.ord, w.idx, w.entry)
    end
    return "AGEMS:1:" .. table.concat(parts, ",")
end

local LoadBuild

-- ── "Higher tier gems available" dialog ──
-- One row per gem with a check box (all ticked), "Also save them in the build"
-- (ticked), then Cancel / Load as saved / Upgrade and load. Strata
-- FULLSCREEN_DIALOG with a low frame level: very high levels (130) made the
-- 3.3.5 client draw the buttons under the dialog's own background.
local UP_ROW_H = 36
local upgradeDialog

local function PaintCheck(box, on)
    if on then
        box.mark:Show()
        box:SetBackdropBorderColor(0.84, 0.71, 0.35, 1)
    else
        box.mark:Hide()
        box:SetBackdropBorderColor(UI.Tint(0.30, 0.36, 0.62, 1))
    end
end

local function MakeCheck(parent)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(16, 16)
    box:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1,
                      insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    box:SetBackdropColor(UI.Tint(0.031, 0.047, 0.133, 1))
    box.__paBackdrop = true
    box.mark = box:CreateTexture(nil, "OVERLAY")
    box.mark:SetTexture(SOLID)
    box.mark:SetVertexColor(1.00, 0.85, 0.44, 1)
    box.mark:SetPoint("TOPLEFT", box, "TOPLEFT", 4, -4)
    box.mark:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 4)
    return box
end

local function CreateUpgradeDialog()
    local d = CreateFrame("Frame", "PAGemBuildUpgradeDialog", UIParent)
    d:SetSize(500, 260)
    d:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
    d:SetFrameLevel(20)
    d:EnableMouse(true)
    d:SetMovable(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    d:SetClampedToScreen(true)
    UI.AstralBackdrop(d, { thin = true })
    d:SetBackdropColor(UI.Tint(0.043, 0.067, 0.188, 0.98))
    d:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.95)
    d.__paBackdrop = true
    d:Hide()
    tinsert(UISpecialFrames, "PAGemBuildUpgradeDialog")
    if UI.AnimatedShow then UI.AnimatedShow(d, { duration = 0.15 }) end

    local glow = d:CreateTexture(nil, "ARTWORK")
    glow:SetTexture(SOLID)
    glow:SetPoint("TOPLEFT", d, "TOPLEFT", 4, -4)
    glow:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -4)
    glow:SetHeight(40)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.12)

    local accent = d:CreateTexture(nil, "OVERLAY")
    accent:SetTexture(SOLID)
    accent:SetVertexColor(0.886, 0.753, 0.384, 1)
    accent:SetSize(3, 18)
    accent:SetPoint("TOPLEFT", d, "TOPLEFT", 18, -18)

    d.title = d:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(d.title, 15)
    d.title:SetPoint("LEFT", accent, "RIGHT", 9, 0)
    d.title:SetText("Higher tier gems available")

    local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -4)
    UI.CosmicCloseButton(close)

    d.intro = d:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(d.intro, 12)
    d.intro:SetPoint("TOPLEFT", d, "TOPLEFT", 20, -48)
    d.intro:SetPoint("RIGHT", d, "RIGHT", -20, 0)
    d.intro:SetJustifyH("LEFT")

    d.list = CreateFrame("Frame", nil, d)
    d.list:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -72)
    d.list:SetPoint("RIGHT", d, "RIGHT", -16, 0)
    UI.AstralBackdrop(d.list, { thin = true })
    d.list:SetBackdropColor(UI.Tint(0.031, 0.047, 0.133, 0.95))
    d.list:SetBackdropBorderColor(UI.Tint(0.165, 0.204, 0.400, 1))
    d.list.__paBackdrop = true
    d.rows = {}

    -- "Also save them in the build"
    d.saveRow = CreateFrame("Button", nil, d)
    d.saveRow:SetHeight(20)
    d.saveRow:SetPoint("TOPLEFT", d.list, "BOTTOMLEFT", 4, -10)
    d.saveRow:SetPoint("RIGHT", d, "RIGHT", -20, 0)
    d.saveRow.box = MakeCheck(d.saveRow)
    d.saveRow.box:SetPoint("LEFT", d.saveRow, "LEFT", 0, 0)
    d.saveRow.text = d.saveRow:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(d.saveRow.text, 12)
    d.saveRow.text:SetPoint("LEFT", d.saveRow.box, "RIGHT", 8, 0)
    d.saveRow.text:SetText(HEX_MUTED .. "Also save the higher tiers in this build|r")
    d.saveRow:SetScript("OnClick", function(self)
        d.saveChecked = not d.saveChecked
        PaintCheck(self.box, d.saveChecked)
    end)

    d.upgradeBtn = UI.MakeButton(d, "Upgrade and load", { w = 180, h = 30, variant = "gold" })
    d.upgradeBtn:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -16, 16)
    d.keepBtn = UI.MakeButton(d, "Load as saved", { w = 130, h = 30, variant = "secondary" })
    d.keepBtn:SetPoint("RIGHT", d.upgradeBtn, "LEFT", -8, 0)
    d.cancelBtn = UI.MakeButton(d, "Cancel", { w = 90, h = 30, variant = "secondary",
        onClick = function() d:AnimatedHide() end })
    d.cancelBtn:SetPoint("RIGHT", d.keepBtn, "LEFT", -8, 0)
    d.keepBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Load the build with the tiers it was saved with.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    d.keepBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    function d:SelectedUpgrades()
        local sel = {}
        for i, u in ipairs(self.ups or {}) do
            if self.rows[i] and self.rows[i].checked then sel[#sel + 1] = u end
        end
        return sel
    end

    function d:RefreshButtons()
        local n = #self:SelectedUpgrades()
        if n == 0 then
            self.upgradeBtn:SetDisabledLook(true)
            self.upgradeBtn:SetLabel("Upgrade and load")
        else
            self.upgradeBtn:SetDisabledLook(false)
            self.upgradeBtn:SetLabel(HEX_BTN_GOLD .. (n == 1 and "Upgrade 1 gem and load"
                or ("Upgrade " .. n .. " gems and load")) .. "|r")
        end
    end
    return d
end

local function GetUpgradeRow(d, i)
    local r = d.rows[i]
    if r then return r end
    r = CreateFrame("Button", nil, d.list)
    r:SetHeight(UP_ROW_H)
    UI.MakeRowChrome(r)
    if i > 1 then
        local divider = r:CreateTexture(nil, "BORDER")
        divider:SetTexture(SOLID)
        divider:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        divider:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1)
        divider:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1)
        divider:SetHeight(1)
    end
    r.box = MakeCheck(r)
    r.box:SetPoint("LEFT", r, "LEFT", 10, 0)
    r.icon = UI.MakeIconFrame(r, { size = 26 })
    r.icon:SetPoint("LEFT", r.box, "RIGHT", 10, 0)
    r.tiers = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.tiers, 13)
    r.tiers:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.name = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.name, 13)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 10, 0)
    r.name:SetPoint("RIGHT", r.tiers, "LEFT", -10, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
        self.checked = not self.checked
        PaintCheck(self.box, self.checked)
        d:RefreshButtons()
    end)
    r:HookScript("OnEnter", function(self)
        if not self.to then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.to .. ":0:0:0:0:0:0:0:0")
        GameTooltip:Show()
    end)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)
    d.rows[i] = r
    return r
end

local TIER_HEX = {
    [1] = "|cffffffff", [2] = "|cff7cf26a", [3] = "|cff7fb4ff", [4] = "|cffd395ff",
    [5] = "|cffff8c26", [6] = "|cfff2d98c", [7] = "|cffff738c", [8] = "|cffff4040",
}

local function ShowUpgradeDialog(b, ups)
    upgradeDialog = upgradeDialog or CreateUpgradeDialog()
    local d = upgradeDialog
    local G = Gems()
    local schema  = (G and G.SLOT_SCHEMA) or {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    d.build, d.ups = b, ups

    d.intro:SetText(string.format("%sYou own better versions of %s%d gem%s|r%s in %s'%s'|r%s.|r",
        HEX_MUTED, HEX_GOLD, #ups, #ups == 1 and "" or "s", HEX_MUTED, "|cffffffff", b.name or "?", HEX_MUTED))

    for i, u in ipairs(ups) do
        local r = GetUpgradeRow(d, i)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", d.list, "TOPLEFT", 4, -4 - (i - 1) * UP_ROW_H)
        r:SetPoint("TOPRIGHT", d.list, "TOPRIGHT", -4, -4 - (i - 1) * UP_ROW_H)
        r.to = u.to
        r.checked = true
        PaintCheck(r.box, true)
        local texture = select(10, GetItemInfo(u.to))
        r.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
        r.icon:SetQuality(select(3, GetItemInfo(u.to)) or 4)
        local slot = schema[u.ord + 1]
        local name = (PA.GemFusion and PA.GemFusion.GemDisplayName and PA.GemFusion.GemDisplayName(u.from, catalog[u.from]))
                  or ("Gem " .. u.from)
        r.name:SetText(name .. "  " .. HEX_DIM .. (slot and slot.label or "?") .. "|r")
        r.tiers:SetText(HEX_DIM .. "T" .. u.fromTier .. "  »  |r"
            .. (TIER_HEX[u.toTier] or "|cffffffff") .. "T" .. u.toTier .. "|r")
        r:Show()
    end
    for i = #ups + 1, #d.rows do d.rows[i]:Hide() end
    d.list:SetHeight(8 + #ups * UP_ROW_H)

    d.saveChecked = true
    PaintCheck(d.saveRow.box, true)
    d:RefreshButtons()

    d.upgradeBtn:SetScript("OnClick", function()
        local sel = d:SelectedUpgrades()
        if #sel == 0 then return end
        d:AnimatedHide()
        local text = UpgradedText(b, sel)
        if d.saveChecked then
            b.text, b.savedAt, b.date = text, time(), date("%Y-%m-%d")
            RefreshList()
            LoadBuild(b, true)
        else
            LoadBuild(b, true, text)
        end
    end)
    d.keepBtn:SetScript("OnClick", function()
        d:AnimatedHide()
        LoadBuild(b, true)
    end)

    d:SetHeight(72 + 8 + #ups * UP_ROW_H + 40 + 58)
    d:Show()
end

-- text: load this loadout instead of the saved one (upgrades not saved)
LoadBuild = function(b, skipUpgradeCheck, text)
    local G = Gems()
    if not (G and G.ApplyLoadoutText and G.DescribeLoadoutText) then return end
    if IsApplying() then
        SetStatus("A gem build is already being loaded. Wait for it to finish.", HEX_WARN)
        return
    end
    if not skipUpgradeCheck then
        local ups = FindUpgrades(b)
        if #ups > 0 then
            ShowUpgradeDialog(b, ups)
            return
        end
    end
    text = text or b.text
    local desc, fillCount = G.DescribeLoadoutText(text)
    if not desc then
        SetStatus("That build's data is damaged and can't be loaded.", HEX_BAD)
        return
    end
    if (fillCount or 0) == 0 then
        if IsEquipped(b) then
            SetStatus("'" .. b.name .. "' is already equipped.", HEX_GOOD)
        else
            SetStatus(desc)   -- nothing to socket: say why
        end
        return
    end
    loadingName = b.name
    G.ApplyLoadoutText(text)
end

local function DeleteBuild(b)
    for i, other in ipairs(DB()) do
        if other == b then
            table.remove(DB(), i)
            SetStatus("Deleted build '" .. (b.name or "?") .. "'.", HEX_WARN)
            RefreshList()
            return
        end
    end
end

local function ShowExport(b)
    if not UI.MakeTextDialog then return end
    if not exportDialog then
        exportDialog = UI.MakeTextDialog({
            name         = "PAGemBuildExportDialog",
            title        = "Export Gem Build",
            subtitle     = "Ctrl+A to select all, Ctrl+C to copy, then share it.",
            button1Label = "Close",
        })
    end
    exportDialog.header.title:SetText("Export: " .. (b.name or "?"))
    exportDialog:Show()
    exportDialog.editBox:SetText(b.text or "")
    exportDialog.editBox:HighlightText()
    exportDialog.editBox:SetFocus()
    exportDialog.status:SetText(string.format("%d gem%s, saved by %s on %s.",
        b.count or 0, (b.count == 1) and "" or "s", b.savedBy or "?", b.date or "?"))
end

local function ShowImport()
    if not UI.MakeTextDialog then return end
    if not importDialog then
        importDialog = UI.MakeTextDialog({
            name         = "PAGemBuildImportDialog",
            title        = "Import Gem Build",
            subtitle     = "Paste a gem loadout (AGEMS:1:...) to save it as a build.",
            button1Label = "Save Build",
            onAccept     = function(text, dlg)
                local G = Gems()
                local wanted = G and G.DecodeLoadout and G.DecodeLoadout(text)
                if not wanted or #wanted == 0 then
                    dlg.status:SetText(HEX_BAD .. "That isn't a gem loadout (it should start with AGEMS:1:).|r")
                    return true
                end
                -- use the name typed in the tab, if any; never overwrite an existing build
                local base = Trim(host and host.nameBox:GetText() or "")
                if base == "" then base = "Imported build" end
                local name, n = base, 2
                while FindBuild(name) do
                    name = base .. " (" .. n .. ")"
                    n = n + 1
                end
                table.insert(DB(), {
                    name = name, text = (text:gsub("%s+", "")), count = #wanted,
                    savedBy = "Imported", savedAt = time(), date = date("%Y-%m-%d"),
                })
                if host then host.nameBox:Clear() end
                SetStatus("Imported build '" .. name .. "'.", HEX_GOOD)
                RefreshList()
                return false
            end,
        })
    end
    importDialog.status:SetText("Tip: type a name in the Gem Builds tab first to name the imported build.")
    importDialog.editBox:SetText("")
    importDialog:Show()
    importDialog.editBox:SetFocus()
end

local STATUS_COLOR = {
    exact   = { 1.00, 1.00, 1.00 },
    lower   = { 1.00, 0.80, 0.40 },
    missing = { 1.00, 0.60, 0.56 },
}
local STATUS_SUFFIX = { lower = "  (lower tier)", missing = "  (missing)" }

local function ShowPreview(row)
    local b = row.build
    if not b then return end
    local G = Gems()
    local schema  = (G and G.SLOT_SCHEMA) or {}
    local catalog = (PA.GemFusion and PA.GemFusion.catalog) or {}
    local st = GemStatus(b)

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(b.name or "?", 1, 1, 1)
    GameTooltip:AddLine(string.format("Saved by %s%s on %s", b.savedBy or "?",
        b.class and (" (" .. b.class .. ")") or "", b.date or "?"), 0.75, 0.77, 0.88)
    local avail = LongAvailability(st)
    if avail then GameTooltip:AddLine(avail, 1, 1, 1, true) end
    GameTooltip:AddLine(" ")
    for i, w in ipairs((G and G.DecodeLoadout and G.DecodeLoadout(b.text)) or {}) do
        if PA.ItemCache then PA.ItemCache.Register(w.entry) end
        local slot = schema[w.ord + 1]
        local cat  = catalog[w.entry]
        local name = (PA.GemFusion and PA.GemFusion.GemDisplayName and PA.GemFusion.GemDisplayName(w.entry, cat))
                  or GetItemInfo(w.entry) or ("Gem " .. w.entry)
        local state = st and st.byIndex[i]
        local c = STATUS_COLOR[state] or STATUS_COLOR.exact
        GameTooltip:AddDoubleLine(slot and slot.label or "?",
            name .. ((cat and cat.tier) and ("  T" .. cat.tier) or "") .. (STATUS_SUFFIX[state] or ""),
            0.80, 0.82, 0.92, c[1], c[2], c[3])
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Load swaps this build's gems in from your Gem Stash (removing gems that are in the way), using a lower tier of a gem when you don't have the exact one.",
        0.55, 0.88, 0.63, true)
    GameTooltip:Show()
end

-- two-click confirm for Delete and Update
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

local function CreateRow(parent, i)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -((i - 1) * ROW_H))
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -((i - 1) * ROW_H))
    UI.MakeRowChrome(r)
    r:HookScript("OnEnter", ShowPreview)
    r:HookScript("OnLeave", function() GameTooltip:Hide() end)

    if i % 2 == 0 then
        local alt = r:CreateTexture(nil, "BACKGROUND")
        alt:SetTexture(SOLID)
        alt:SetAllPoints(r)
        alt:SetVertexColor(1, 1, 1, 0.022)
    end
    if i > 1 then
        local divider = r:CreateTexture(nil, "BORDER")
        divider:SetTexture(SOLID)
        divider:SetVertexColor(UI.Tint(0.47, 0.55, 0.86, 0.10))
        divider:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 1)
        divider:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 1)
        divider:SetHeight(1)
    end

    -- equipped build: same warm tint and bar as Gem Fusion's ready rows
    r.equippedBg = r:CreateTexture(nil, "BACKGROUND")
    r.equippedBg:SetTexture(SOLID)
    r.equippedBg:SetAllPoints(r)
    r.equippedBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    r.equippedBar = r:CreateTexture(nil, "ARTWORK")
    r.equippedBar:SetTexture(SOLID)
    r.equippedBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    r.equippedBar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.equippedBar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.equippedBar:SetWidth(3)

    r.iconFrame = UI.MakeIconFrame(r, { size = 36 })
    r.iconFrame:SetPoint("LEFT", r, "LEFT", 10, 0)

    r.del = UI.MakeButton(r, "Delete", { w = 70, h = 24, variant = "danger" })
    r.del:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    ConfirmButton(r, r.del, "Delete", "Click Sure? to delete '%s'.", DeleteBuild)

    r.export = UI.MakeButton(r, "Export", { w = 70, h = 24, variant = "secondary",
        onClick = function() if r.build then ShowExport(r.build) end end })
    r.export:SetPoint("RIGHT", r.del, "LEFT", -5, 0)

    r.update = UI.MakeButton(r, "Update", { w = 70, h = 24, variant = "secondary" })
    r.update:SetPoint("RIGHT", r.export, "LEFT", -5, 0)
    ConfirmButton(r, r.update, "Update",
        "Click Sure? to replace '%s' with the gems socketed right now.", UpdateBuild)
    r.update:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Update build", 1, 1, 1)
        GameTooltip:AddLine("Replace this build's gems with the ones socketed right now. Click twice to confirm.",
            0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    r.update:HookScript("OnLeave", function() GameTooltip:Hide() end)

    r.load = UI.MakeButton(r, "Load", { w = 78, h = 24, variant = "gold",
        onClick = function() if r.build then LoadBuild(r.build) end end })
    r.load:SetPoint("RIGHT", r.update, "LEFT", -10, 0)

    r.name = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.name, 14)
    r.name:SetPoint("BOTTOMLEFT", r.iconFrame, "RIGHT", 10, 2)
    r.name:SetPoint("RIGHT", r.load, "LEFT", -10, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.sub = r:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(r.sub, 11)
    r.sub:SetPoint("TOPLEFT", r.iconFrame, "RIGHT", 10, -3)
    r.sub:SetPoint("RIGHT", r.load, "LEFT", -10, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)

    r:Hide()
    return r
end

local function ResetConfirm(btn)
    if btn._confirmAt and GetTime() - btn._confirmAt <= CONFIRM_WINDOW then return end
    btn._confirmAt = nil
    btn:SetLabel(btn._idleLabel)
end

RefreshList = function()
    if not host then return end
    local G = Gems()
    local list = SortedBuilds()
    local offset = FauxScrollFrame_GetOffset(host.scroll)
    local busy = IsApplying()

    for i = 1, NUM_ROWS do
        local r = rows[i]
        local b = list[i + offset]
        if r.build ~= b then
            r.del._confirmAt, r.update._confirmAt = nil, nil
        end
        r.build = b
        ResetConfirm(r.del)
        ResetConfirm(r.update)
        if b then
            local equipped = IsEquipped(b)
            -- every row has Gem Stash's gold look; the equipped one a stronger tint
            r.equippedBg:Show(); r.equippedBar:Show()
            r.equippedBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, equipped and 0.30 or 0.14, 0.94, 0.82, 0.43, 0)
            r.name:SetText(b.name or "?")
            local who = (b.savedBy or "?") .. (b.class and (" (" .. b.class .. ")") or "")
            r.sub:SetText((equipped and (HEX_GOLD .. "Equipped|r" .. HEX_DIM .. "  ·  |r") or "")
                .. ShortAvailability(GemStatus(b), b.count)
                .. HEX_DIM .. "  ·  " .. who .. "  ·  " .. (b.date or "") .. "|r")
            local first = G and G.DecodeLoadout and (G.DecodeLoadout(b.text) or {})[1]
            local texture = first and select(10, GetItemInfo(first.entry))
            r.iconFrame:SetTexture(texture or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
            r.iconFrame:SetQuality(4)
            if busy then
                r.load:SetDisabledLook(true)
                r.load:SetLabel(HEX_DIM .. "Load|r")
            else
                r.load:SetDisabledLook(false)
                r.load:SetLabel(HEX_BTN_GOLD .. "Load|r")
            end
            r:Show()
        else
            r:Hide()
        end
    end

    FauxScrollFrame_Update(host.scroll, #list, NUM_ROWS, ROW_H)
    host.countText:SetText(HEX_GOLD .. #list .. "|r" .. HEX_MUTED .. (#list == 1 and " saved build" or " saved builds") .. "|r")
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

local function BuildGemBuildsTab(panel)
    host = panel
    local SIDE = 10
    local top = -8

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID)
    ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    -- ── Header: name, Save current, Import, count ──
    local nameBox = UI.MakeSearchBox(panel, { width = 300, height = 26, placeholder = "Name this build…" })
    UI.SetTextFont(nameBox.edit, 13)
    UI.StyleFilterSearch(nameBox); nameBox.__paBackdrop = true
    nameBox:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top)
    nameBox.edit:SetScript("OnEnterPressed", function() SaveCurrent() end)
    panel.nameBox = nameBox

    local saveBtn = UI.MakeButton(panel, "Save current", { w = 140, h = 26, variant = "gold",
        onClick = function() SaveCurrent() end })
    saveBtn:SetLabel(HEX_BTN_GOLD .. "Save current|r")
    saveBtn:SetPoint("LEFT", nameBox, "RIGHT", 8, 0)
    AddTip(saveBtn, "Save current gems",
        "Saves the gems socketed right now under the name you typed. Saving with an existing name updates that build.")

    local importBtn = UI.MakeButton(panel, "Import", { w = 90, h = 26, variant = "secondary",
        onClick = function() ShowImport() end })
    importBtn:SetPoint("LEFT", saveBtn, "RIGHT", 6, 0)
    AddTip(importBtn, "Import gem build",
        "Paste a gem loadout someone shared (AGEMS:1:...) and save it as a build.")

    panel.countText = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.countText, 13)
    panel.countText:SetPoint("RIGHT", panel, "TOPRIGHT", -SIDE - 2, top - 13)

    -- ── Action bar: status, or the loading progress ──
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(38)
    bar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  SIDE,  top - 34)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, top - 34)
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
    bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true
    panel.bar = bar

    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetTexture(SOLID)
    bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 4, -4)
    bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 4, 4)
    bar.fill:SetWidth(1)
    bar.fill:Hide()

    bar.counter = bar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(bar.counter, 12)
    bar.counter:SetPoint("RIGHT", bar, "RIGHT", -12, 0)

    bar.text = bar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(bar.text, 12)
    bar.text:SetPoint("LEFT", bar, "LEFT", 12, 0)
    bar.text:SetPoint("RIGHT", bar.counter, "LEFT", -10, 0)
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)

    local IDLE_TEXT = "Socket your gems, name the build and click Save current. "
        .. "Builds are shared by every character on your account."
    SetStatus(IDLE_TEXT)

    -- the finished result stays a few seconds, then the bar goes back to its hint
    bar:SetScript("OnUpdate", function(self)
        if self._holdUntil and GetTime() > self._holdUntil and not IsApplying() then
            SetStatus(IDLE_TEXT)
        end
    end)

    -- ── List ──
    local listPanel = CreateFrame("Frame", nil, panel)
    listPanel:SetPoint("TOPLEFT",     bar,   "BOTTOMLEFT",  0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, 10)
    UI.AstralBackdrop(listPanel, { thin = true })
    listPanel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)   -- same dark grey as the Gem Stash list
    listPanel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    listPanel.__paBackdrop = true   -- Theme.lua greys navy backdrops otherwise

    local scroll = CreateFrame("ScrollFrame", "PAGemBuildsScroll", listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",      6, -6)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, RefreshList)
    end)
    panel.scroll = scroll

    local listFrame = CreateFrame("Frame", nil, listPanel)
    listFrame:SetPoint("TOPLEFT",     scroll, "TOPLEFT",     0, 0)
    listFrame:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    for i = 1, NUM_ROWS do rows[i] = CreateRow(listFrame, i) end

    panel.empty = listFrame:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.empty, 13)
    panel.empty:SetPoint("TOP", listFrame, "TOP", 0, -30)
    panel.empty:SetText(HEX_MUTED .. "No gem builds saved yet.|r")

    panel:SetScript("OnShow", function()
        -- the stash may not have arrived yet; ask for it so "owned" counts are current
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        RefreshList()
    end)

    -- owned counts follow the stash, "Equipped" follows the socketed gems
    if PA.GemStash and PA.GemStash.OnStockChanged then
        PA.GemStash.OnStockChanged(function()
            if host and host:IsVisible() then RefreshList() end
        end)
    end
    local G = Gems()
    if G and G.Render then
        hooksecurefunc(G, "Render", function()
            if host and host:IsVisible() then RefreshList() end
        end)
    end
    if G and G.OnApplyProgress then
        G.OnApplyProgress(SetProgress)
    end
end

local function ToggleGemBuilds()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "gem_builds" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("gem_builds")
    end
end

PA:RegisterModule("gem_builds", "Gem Builds", ToggleGemBuilds, {
    subtitle = "Save gem loadouts and load them on any of your characters.",
})
PA:RegisterTabContent("gem_builds", BuildGemBuildsTab)
