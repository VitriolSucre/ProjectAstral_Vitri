local PA = ProjectAstral
local UI = PA.UI

local styled
local registered
local stylePending

local function StyleCloseButton(button)
    button:SetNormalTexture("Interface\\Buttons\\UI-Panel-CloseButton-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-Panel-CloseButton-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Panel-CloseButton-Highlight")
    button:SetBackdrop(nil)
end

local function StyleBuildSaver()
    if styled or not _G.BuildSaver then return end
    local frame = _G.BuildSaverFrame
    if not frame then return end
    styled = true

    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(UI.Nav.deep[1], UI.Nav.deep[2],
                           UI.Nav.deep[3], 0.98)
    frame:SetBackdropBorderColor(unpack(UI.Nav.edgeMid))

    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType then
            local objectType = region:GetObjectType()
            if objectType == "Texture" then
                region:SetAlpha(0)
            elseif objectType == "FontString" then
                region:SetTextColor(unpack(UI.Color.textPrimary))
            end
        end
    end

    local function StyleText(fs, color)
        if fs and fs.SetTextColor then fs:SetTextColor(unpack(color or UI.Color.textPrimary)) end
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        local objectType = child.GetObjectType and child:GetObjectType()
        if objectType == "Button" then
            if child:GetWidth() <= 36 and child:GetHeight() <= 36 then
                StyleCloseButton(child)
            else
                UI.CosmicButton(child)
                for _, region in ipairs({ child:GetRegions() }) do
                    if region.GetObjectType and region:GetObjectType() == "FontString" then
                        region:SetTextColor(unpack(UI.Color.textTitle))
                    end
                end
            end
        elseif objectType == "CheckButton" then
            local text = _G[child:GetName() .. "Text"]
            StyleText(text)
        elseif objectType == "ScrollFrame" or objectType == "Frame" then
            if child.SetBackdrop and child ~= frame then
                child:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                                    tile = false, edgeSize = 12,
                                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
                child:SetBackdropColor(UI.Nav.panel[1], UI.Nav.panel[2],
                                       UI.Nav.panel[3], 0.82)
                child:SetBackdropBorderColor(unpack(UI.Nav.edge))
            end
        end
    end

    frame:HookScript("OnShow", function()
        frame:SetBackdropColor(UI.Nav.deep[1], UI.Nav.deep[2],
                               UI.Nav.deep[3], 0.98)
    end)
end

local function ScheduleStyle()
    if stylePending then return end
    stylePending = true
    local waiter = CreateFrame("Frame")
    local elapsed = 0
    local attempts = 0
    waiter:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed < 0.10 then return end
        elapsed = 0
        attempts = attempts + 1
        StyleBuildSaver()
        if styled or attempts >= 20 then
            stylePending = nil
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local function OpenBuildSaver()
    if _G.BuildSaver and _G.BuildSaver.UI and _G.BuildSaver.UI.Toggle then
        _G.BuildSaver.UI:Toggle()
        ScheduleStyle()
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4040[Project Astral]|r BuildSaver is not loaded.")
    end
end

local bridge = CreateFrame("Frame")
bridge:RegisterEvent("ADDON_LOADED")
bridge:RegisterEvent("PLAYER_LOGIN")
bridge:SetScript("OnEvent", function(_, _, addon)
    if addon == "BuildSaver" or not addon then
        ScheduleStyle()
        if _G.BuildSaver and not registered then
            registered = true
            if _G.BuildSaver.UI and _G.BuildSaver.UI.Toggle then
                hooksecurefunc(_G.BuildSaver.UI, "Toggle", function()
                    ScheduleStyle()
                end)
            end
            PA:RegisterModule("build_saver", "BuildSaver", OpenBuildSaver, {
                placement = "footer",
                subtitle = "Save and restore Blizzard talent builds with BuildSaver.",
            })
        end
    end
end)
