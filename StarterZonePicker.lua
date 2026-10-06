local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local PA = ProjectAstral

local ClientHandler = AIO.AddHandlers("AstralStarterZone", {})

local ASTRAL_BLUE     = {0.30, 0.68, 1.00, 1.00}
local ASTRAL_BLUE_DIM = {0.30, 0.68, 1.00, 0.35}

local RACE_ICONS = {
    ["Human"]     = "Interface\\Icons\\Achievement_Character_Human_Male",
    ["Dwarf"]     = "Interface\\Icons\\Achievement_Character_Dwarf_Male",
    ["Gnome"]     = "Interface\\Icons\\Achievement_Character_Gnome_Male",
    ["Night Elf"] = "Interface\\Icons\\Achievement_Character_Nightelf_Male",
    ["Draenei"]   = "Interface\\Icons\\Achievement_Character_Draenei_Male",
    ["Orc"]       = "Interface\\Icons\\Achievement_Character_Orc_Male",
    ["Troll"]     = "Interface\\Icons\\Achievement_Character_Troll_Male",
    ["Undead"]    = "Interface\\Icons\\Achievement_Character_Undead_Male",
    ["Tauren"]    = "Interface\\Icons\\Achievement_Character_Tauren_Male",
    ["Blood Elf"] = "Interface\\Icons\\Achievement_Character_Bloodelf_Male",
}

local IMAGE_PATH = "Interface\\AddOns\\ProjectAstral\\textures\\StarterZones\\"

local frame

local function MakeBorder(parent, colour, thickness)
    local t = thickness or 1
    local borders = {}
    for _, edge in ipairs({
        {"TOPLEFT",    "TOPRIGHT",    nil, t},
        {"BOTTOMLEFT", "BOTTOMRIGHT", nil, t},
        {"TOPLEFT",    "BOTTOMLEFT",  t,   nil},
        {"TOPRIGHT",   "BOTTOMRIGHT", t,   nil},
    }) do
        local tex = parent:CreateTexture(nil, "BORDER")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(unpack(colour))
        tex:SetPoint(edge[1])
        tex:SetPoint(edge[2])
        if edge[3] then tex:SetWidth(edge[3]) end
        if edge[4] then tex:SetHeight(edge[4]) end
        table.insert(borders, tex)
    end
    return borders
end

local function TintBorder(borders, colour)
    for _, b in ipairs(borders) do
        b:SetVertexColor(unpack(colour))
    end
end

local function MakeCard(parent)
    local card = CreateFrame("Button", nil, parent)
    card:SetSize(400, 280)

    card.bg = card:CreateTexture(nil, "BACKGROUND")
    card.bg:SetAllPoints()
    card.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.bg:SetVertexColor(0.08, 0.10, 0.15, 0.95)

    card.borders = MakeBorder(card, ASTRAL_BLUE, 2)

    card.image = card:CreateTexture(nil, "ARTWORK")
    card.image:SetPoint("TOPLEFT",  3, -3)
    card.image:SetPoint("TOPRIGHT", -3, -3)
    card.image:SetHeight(220)
    -- source TGAs are 256x256 with art vertically centered — crop to keep art only
    card.image:SetTexCoord(0.0, 1.0, 0.28, 0.72)

    card.iconBG = card:CreateTexture(nil, "OVERLAY", nil, 1)
    card.iconBG:SetSize(52, 52)
    card.iconBG:SetPoint("TOPLEFT", 8, -8)
    card.iconBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.iconBG:SetVertexColor(0, 0, 0, 0.75)

    card.iconBorders = {}
    for _, edge in ipairs({
        {"TOPLEFT",    "TOPRIGHT",    nil, 1},
        {"BOTTOMLEFT", "BOTTOMRIGHT", nil, 1},
        {"TOPLEFT",    "BOTTOMLEFT",  1,   nil},
        {"TOPRIGHT",   "BOTTOMRIGHT", 1,   nil},
    }) do
        local tex = card:CreateTexture(nil, "OVERLAY", nil, 2)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetVertexColor(unpack(ASTRAL_BLUE))
        tex:SetPoint(edge[1], card.iconBG, edge[1])
        tex:SetPoint(edge[2], card.iconBG, edge[2])
        if edge[3] then tex:SetWidth(edge[3]) end
        if edge[4] then tex:SetHeight(edge[4]) end
        table.insert(card.iconBorders, tex)
    end

    card.icon = card:CreateTexture(nil, "OVERLAY", nil, 3)
    card.icon:SetSize(46, 46)
    card.icon:SetPoint("CENTER", card.iconBG, "CENTER", 0, 0)
    card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    card.zoneLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    card.zoneLabel:SetPoint("TOP", card.image, "BOTTOM", 0, -8)

    card.raceLabel = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.raceLabel:SetPoint("TOP", card.zoneLabel, "BOTTOM", 0, -4)

    card.badge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    card.badge:SetPoint("BOTTOMRIGHT", -12, 12)

    card.lockOverlay = card:CreateTexture(nil, "OVERLAY", nil, 4)
    card.lockOverlay:SetAllPoints(card.image)
    card.lockOverlay:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.lockOverlay:SetVertexColor(0, 0, 0, 0.6)
    card.lockOverlay:Hide()

    card.lockText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    card.lockText:SetPoint("CENTER", card.image)
    card.lockText:SetText("LOCKED")
    card.lockText:SetTextColor(1, 0.3, 0.3)
    card.lockText:Hide()

    card.hi = card:CreateTexture(nil, "HIGHLIGHT")
    card.hi:SetAllPoints()
    card.hi:SetTexture("Interface\\Buttons\\WHITE8X8")
    card.hi:SetVertexColor(unpack(ASTRAL_BLUE))
    card.hi:SetAlpha(0.15)

    card:SetScript("OnClick", function(self)
        if self.locked then return end
        AIO.Handle("AstralStarterZoneServer", "SelectZone", self.zoneKey)
        if frame then frame:Hide() end
    end)

    return card
end

local function CreatePickerFrame()
    local f = CreateFrame("Frame", "AstralStarterZoneFrame", UIParent)
    f.__paUnified = true   -- unified look: Theme.lua keeps its navy
    f:SetSize(860, 680)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.04, 0.05, 0.08, 0.97)

    MakeBorder(f, ASTRAL_BLUE, 2)

    local titleBar = f:CreateTexture(nil, "ARTWORK")
    titleBar:SetPoint("TOPLEFT",  2, -2)
    titleBar:SetPoint("TOPRIGHT", -2, -2)
    titleBar:SetHeight(50)
    titleBar:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBar:SetVertexColor(0.05, 0.10, 0.18, 1)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT",  2, -52)
    divider:SetPoint("TOPRIGHT", -2, -52)
    divider:SetHeight(2)
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(unpack(ASTRAL_BLUE))

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Choose Your Starter Zone")
    title:SetTextColor(unpack(ASTRAL_BLUE))

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    if PA and PA.UI and PA.UI.CosmicCloseButton then
        PA.UI.CosmicCloseButton(close)
    end
    close:SetPoint("TOPRIGHT", -4, -4)

    f.cards = {}
    for i = 1, 4 do
        local card = MakeCard(f)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        card:SetPoint("TOPLEFT", 20 + col*420, -70 - row*300)
        card:Hide()
        f.cards[i] = card
    end

    f:Hide()
    return f
end

ClientHandler.OpenPicker = function(player, zoneList)
    frame = frame or CreatePickerFrame()

    for i, z in ipairs(zoneList) do
        local c = frame.cards[i]
        if c then
            c.zoneKey = z.key
            c.locked  = z.locked

            c.image:SetTexture(IMAGE_PATH .. z.image)
            c.icon:SetTexture(RACE_ICONS[z.iconRace]
                              or "Interface\\Icons\\INV_Misc_QuestionMark")
            c.zoneLabel:SetText(z.zoneName)
            c.raceLabel:SetText(table.concat(z.races, " / "))

            if z.locked then
                c.image:SetDesaturated(true)
                c.icon:SetDesaturated(true)
                c.zoneLabel:SetTextColor(0.5, 0.5, 0.5)
                c.raceLabel:SetTextColor(0.4, 0.4, 0.4)
                c.badge:SetText("TBC")
                c.badge:SetTextColor(1, 0.3, 0.3)
                c.lockOverlay:Show()
                c.lockText:Show()
                TintBorder(c.borders, ASTRAL_BLUE_DIM)
                TintBorder(c.iconBorders, ASTRAL_BLUE_DIM)
            else
                c.image:SetDesaturated(false)
                c.icon:SetDesaturated(false)
                c.zoneLabel:SetTextColor(1.0, 0.85, 0.3)
                c.raceLabel:SetTextColor(0.85, 0.85, 0.85)
                c.lockOverlay:Hide()
                c.lockText:Hide()
                TintBorder(c.borders, ASTRAL_BLUE)
                TintBorder(c.iconBorders, ASTRAL_BLUE)
                if (z.exp or 0) > 0 then
                    c.badge:SetText("TBC")
                    c.badge:SetTextColor(unpack(ASTRAL_BLUE))
                else
                    c.badge:SetText("")
                end
            end

            c:Show()
        end
    end
    for i = #zoneList + 1, #frame.cards do
        frame.cards[i]:Hide()
    end

    frame:Show()
end
