local PA = ProjectAstral
local UI = PA.UI

ProjectAstralGemTrackerDB = ProjectAstralGemTrackerDB or {}
local db = ProjectAstralGemTrackerDB
db.procs = db.procs or {}
if type(db.procs) ~= "table" then db.procs = {} end

local SOLID = "Interface\\Buttons\\WHITE8X8"
local tracker = CreateFrame("Frame", "ProjectAstralGemTracker", UIParent)
tracker:SetSize(300, 190)
tracker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
tracker:SetFrameStrata("MEDIUM")   -- below the Astral hub (HIGH)
tracker:SetFrameLevel(60)
tracker:SetBackdrop({ bgFile = SOLID, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
tracker:SetBackdropColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.97))
tracker:SetBackdropBorderColor(unpack(UI.Nav.edgeMid))
tracker:SetMovable(true)
tracker:EnableMouse(true)
tracker:RegisterForDrag("LeftButton")
tracker:SetScript("OnDragStart", tracker.StartMoving)
tracker:SetScript("OnDragStop", tracker.StopMovingOrSizing)
tracker:Hide()

local title = tracker:CreateFontString(nil, "OVERLAY")
title:SetPoint("TOPLEFT", tracker, "TOPLEFT", 10, -8)
title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
title:SetText("Gem Proc Tracker")
title:SetTextColor(unpack(UI.Color.textTitle))

local rows = {}
for i = 1, 7 do
    local row = CreateFrame("Frame", nil, tracker)
    row:SetSize(276, 20)
    row:SetPoint("TOPLEFT", tracker, "TOPLEFT", 12, -30 - (i - 1) * 21)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = row:CreateFontString(nil, "OVERLAY")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    row.text:SetTextColor(1, 1, 1)
    rows[i] = row
end

local function IsGemSpell(name)
    name = tostring(name or ""):lower()
    if name:find("judgement", 1, true) or name:find("judgment", 1, true) then
        return false
    end

    return name:find("%f[%a]gem%f[%A]")
        or name:find("%f[%a]socket%f[%A]")
        or name:find("%f[%a]jewel%f[%A]")
        or name:find("%(%s*t%d%s*%)")
end

local function SpellTexture(spellId, spellName)
    local _, _, texture = GetSpellInfo(spellId or spellName)
    return texture or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02"
end

for name in pairs(db.procs) do
    if not IsGemSpell(name) then db.procs[name] = nil end
end

local function Refresh()
    local list = {}
    for name, data in pairs(db.procs) do
        if type(data) == "table" then
            list[#list + 1] = {
                name = tostring(name),
                count = tonumber(data.count) or 0,
                value = tonumber(data.value) or 0,
                icon = data.icon,
            }
        end
    end
    table.sort(list, function(a, b) return a.value > b.value end)
    for i = 1, #rows do
        local data = list[i]
        if data then
            rows[i].icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_Gem_Amethyst_02")
            rows[i].icon:Show()
            rows[i].text:SetText(string.format("%s  |  %d procs  |  %d damage",
                data.name, data.count, data.value))
            rows[i].text:Show()
        else
            rows[i].icon:Hide()
            rows[i].text:SetText("")
        end
    end
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combat:SetScript("OnEvent", function(_, _, ...)
    if not PA.Settings or not PA.Settings.gemTracker then return end
    local _, event, _, sourceName, _, _, _, _, spellId, spellName, _, amount = ...
    if not sourceName or sourceName ~= UnitName("player")
       or not IsGemSpell(spellName) then return end
    if event ~= "SPELL_DAMAGE" and event ~= "SPELL_PERIODIC_DAMAGE" then return end
    amount = tonumber(amount) or 0
    if amount <= 0 then return end
    local data = db.procs[spellName]
    if type(data) ~= "table" then
        data = { count = 0, value = 0, icon = SpellTexture(spellId, spellName) }
        db.procs[spellName] = data
    end
    data.icon = data.icon or SpellTexture(spellId, spellName)
    data.count = data.count + 1
    data.value = data.value + amount
    Refresh()
end)

function PA.SetGemTrackerEnabled(enabled)
    enabled = enabled and true or false
    if enabled then
        tracker:SetFrameStrata("MEDIUM")
        tracker:SetFrameLevel(60)
        tracker:Show()
        tracker:Raise()
        Refresh()
    else
        tracker:Hide()
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    PA.SetGemTrackerEnabled(PA.Settings and PA.Settings.gemTracker)
end)
