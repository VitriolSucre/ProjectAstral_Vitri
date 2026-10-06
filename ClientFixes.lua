-- Small FrameXML overrides. 3.3.5 hides Dungeon/Raid Difficulty behind hardcoded

_G.AstralClientFixesLoaded = true

if type(UnitPopup_HideButtons) == "function" then
    hooksecurefunc("UnitPopup_HideButtons", function()
        local dropdown = UIDROPDOWNMENU_INIT_MENU
        if not dropdown then return end
        local which = dropdown.which
        if which ~= "SELF" and which ~= "PLAYER" then return end

        local menu = UnitPopupMenus and UnitPopupMenus[which]
        if not menu or not UnitPopupShown then return end

        for index, value in ipairs(menu) do
            if value == "DUNGEON_DIFFICULTY" or value == "RAID_DIFFICULTY" then
                for level = 1, 4 do
                    if UnitPopupShown[level] then
                        UnitPopupShown[level][index] = 1
                    end
                end
            end
        end
    end)
end
