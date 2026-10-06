-- OVERRIDE_FONTS.lua
-- Override Blizzard's default FontObjects to use vibrant colors
-- This MUST load after all other files

print("|cff00ff00[OVERRIDE_FONTS]|r Loading...")

-- List of FontObjects to override
local FONTS_TO_FIX = {
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontNormalLarge",
    "GameFontHighlight",
    "GameFontHighlightSmall",
    "GameFontHighlightLarge",
    "GameFontDisable",
    "GameFontDisableSmall",
    "GameFontGreen",
    "GameFontRed",
    "NumberFontNormal",
    "NumberFontNormalSmall",
    "NumberFontNormalLarge",
    "DialogButtonNormalText",
    "DialogButtonHighlightText",
    "ZoneTextFont",
    "SubZoneTextFont",
    "PVPInfoTextFont",
}

-- Override each FontObject
local fixedCount = 0
for _, fontName in ipairs(FONTS_TO_FIX) do
    local font = _G[fontName]
    if font then
        -- Get current font info
        local fontFile, fontSize, fontFlags = font:GetFont()

        -- Set vibrant colors based on font type
        if fontName:find("Disable") then
            -- Disabled text: bright gray
            font:SetTextColor(0.80, 0.80, 0.85)
        elseif fontName:find("Green") then
            -- Green text: vivid green
            font:SetTextColor(0.50, 1.00, 0.65)
        elseif fontName:find("Red") then
            -- Red text: vivid red
            font:SetTextColor(1.00, 0.40, 0.40)
        else
            -- All other text: pure white
            font:SetTextColor(1.00, 1.00, 1.00)
        end

        fixedCount = fixedCount + 1
    end
end

print("|cff00ff00[OVERRIDE_FONTS]|r Fixed " .. fixedCount .. " FontObjects!")

-- Also fix UI.Color just in case
local PA = ProjectAstral
if PA and PA.UI and PA.UI.Color then
    PA.UI.Color.textPrimary = {1.0, 1.0, 1.0}
    PA.UI.Nav.muted = {0.8, 0.8, 0.85}
    PA.UI.Color.textAccent = {1.0, 1.0, 1.0}
    PA.UI.Color.textTitle = {1.0, 1.0, 1.0}
    print("|cff00ff00[OVERRIDE_FONTS]|r Also fixed UI.Color!")
end

-- Slash command to test
SLASH_OVERRIDEFONTS1 = "/of"
SlashCmdList["OVERRIDEFONTS"] = function()
    print("|cff00ff00[OVERRIDE_FONTS]|r Checking FontObject colors:")

    for _, fontName in ipairs({"GameFontNormal", "GameFontHighlight", "GameFontDisable"}) do
        local font = _G[fontName]
        if font then
            local r, g, b = font:GetTextColor()
            print("  " .. fontName .. ": " .. string.format("%.2f, %.2f, %.2f", r, g, b))
        end
    end

    print("|cff00ff00[OVERRIDE_FONTS]|r Type /reload to see changes!")
end

print("|cff00ff00[OVERRIDE_FONTS]|r Loaded! Type /of to check, /reload to apply.")
