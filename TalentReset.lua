
local PA = ProjectAstral

local function UpdateResetBtnVisibility()
    local btn = _G.PAResetTalentsBtn
    if not btn or not PlayerTalentFrame or not PlayerTalentFrame:IsShown() then
        if btn then btn:Hide() end
        return
    end

    -- 3.3.5 tree tabs reuse PlayerTalentFrameTabN so tab index is unreliable — check frames directly
    if GlyphFrame and GlyphFrame:IsShown() then
        btn:Hide()
        return
    end
    if PetTalentFrame and PetTalentFrame:IsShown() then
        btn:Hide()
        return
    end

    if PlayerTalentFrameActivateButton
       and PlayerTalentFrameActivateButton:IsShown() then
        btn:Hide()
        return
    end

    btn:Show()
end

local function CreateResetButton()
    if not PlayerTalentFrame or _G.PAResetTalentsBtn then return end

    local btn = CreateFrame("Button", "PAResetTalentsBtn", PlayerTalentFrame, "UIPanelButtonTemplate")
    if PA and PA.UI and PA.UI.CosmicButton then
        PA.UI.CosmicButton(btn)
    end
    btn:SetSize(130, 22)
    btn:SetPoint("TOP", PlayerTalentFrame, "TOP", 49, -38)   -- right of the Builds button (TalentBuilds.lua), both centred
    btn:SetText("Reset Talents")
    btn:SetFrameLevel((PlayerTalentFrame:GetFrameLevel() or 1) + 5)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Refund every spent talent point for free.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        StaticPopup_Show("PA_RESET_TALENTS_CONFIRM")
    end)

    PlayerTalentFrame:HookScript("OnShow", UpdateResetBtnVisibility)
    if PlayerTalentFrame_Refresh then
        hooksecurefunc("PlayerTalentFrame_Refresh", UpdateResetBtnVisibility)
    end
    for i = 1, 2 do
        local s = _G["PlayerSpecTab" .. i]
        if s then s:HookScript("OnClick", UpdateResetBtnVisibility) end
    end
    if PlayerTalentFrameActivateButton then
        PlayerTalentFrameActivateButton:HookScript("OnShow", UpdateResetBtnVisibility)
        PlayerTalentFrameActivateButton:HookScript("OnHide", UpdateResetBtnVisibility)
    end
    if GlyphFrame then
        GlyphFrame:HookScript("OnShow", UpdateResetBtnVisibility)
        GlyphFrame:HookScript("OnHide", UpdateResetBtnVisibility)
    end
    if PetTalentFrame then
        PetTalentFrame:HookScript("OnShow", UpdateResetBtnVisibility)
        PetTalentFrame:HookScript("OnHide", UpdateResetBtnVisibility)
    end

    UpdateResetBtnVisibility()
end

StaticPopupDialogs["PA_RESET_TALENTS_CONFIRM"] = {
    text         = "Reset all talents?\n\nThis refunds every spent talent point. Free of charge.",
    button1      = "Reset",
    button2      = "Cancel",
    OnAccept     = function() SendChatMessage(".talents reset", "SAY") end,
    timeout      = 0,
    whileDead    = false,
    hideOnEscape = true,
    showAlert    = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
}

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == "Blizzard_TalentUI" then
        CreateResetButton()
    elseif event == "PLAYER_LOGIN" then
        if IsAddOnLoaded("Blizzard_TalentUI") then
            CreateResetButton()
        end
    elseif event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        UpdateResetBtnVisibility()
    end
end)
