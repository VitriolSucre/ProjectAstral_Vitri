local PA = ProjectAstral
local UI = PA.UI

-- Astral look for Blizzard's quest, gossip, loot and Dungeon Finder windows (flat black,
-- thin outline, Astral close button, Astral widgets), plus the auto-accept, auto-turn-in
-- and auto-loot options from Settings.

local SOLID        = "Interface\\Buttons\\WHITE8X8"
local ROLE_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local themed   = setmetatable({}, { __mode = "k" })
local surfaced = setmetatable({}, { __mode = "k" })

local WINDOWS = {
    "QuestFrame", "QuestLogFrame", "GossipFrame", "LootFrame",
    "LFDParentFrame", "LFDRoleCheckPopup", "LFDDungeonReadyDialog",
}
local CLOSE_BUTTON = { LootFrame = "LootCloseButton" }   -- otherwise <frame>CloseButton

local function TexturePath(region)
    local texture = region and region.GetTexture and region:GetTexture()
    return type(texture) == "string" and texture:lower() or ""
end

-- Blizzard frame art to fade out: parchment, stone borders, LFG backgrounds
local function IsDecorativeTexture(region)
    local path = TexturePath(region)
    if path == "" then return false end
    -- never content: item and spell icons ("inv_stone_..." matched "stone"), the role
    -- icons (they live under LFGFrame too) and button highlights
    if path:find("interface\\icons\\", 1, true)
       or path:find("icon-roles", 1, true) or path:find("portraitroles", 1, true)
       or path:find("highlight", 1, true) then
        return false
    end
    return path:find("questframe", 1, true)
        or path:find("lfgframe", 1, true)
        or path:find("lookingfordungeon", 1, true)
        or path:find("ui-panel-background", 1, true)
        or path:find("dialogbackground", 1, true)
        or path:find("parchment", 1, true)
        or path:find("stone", 1, true)
end

-- flat Astral black with no grey edge, set once per frame
local function BlackSurface(frame, alpha)
    if not (frame and frame.SetBackdrop) or surfaced[frame] then return end
    surfaced[frame] = true
    frame:SetBackdrop({ bgFile = SOLID, tile = false,
                        insets = { left = 0, right = 0, top = 0, bottom = 0 } })
    local c = UI.Nav.deep
    frame:SetBackdropColor(c[1], c[2], c[3], alpha or 0.96)
end

-- Astral look for a Blizzard close button. Its OnClick stays Blizzard's (HideUIPanel);
-- UI.CosmicCloseButton would replace it with a plain Hide.
local function StyleCloseButton(btn)
    if not btn or btn.__paCloseStyled then return end
    btn.__paCloseStyled = true
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = btn[getter] and btn[getter](btn)
        if t then t:SetAlpha(0) end
    end
    local box = btn:CreateTexture(nil, "BACKGROUND")
    box:SetTexture(SOLID)
    box:SetVertexColor(0.015, 0.015, 0.018, 0.96)
    box:SetSize(18, 18)
    box:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local lines = UI.Outline(btn, box, "BORDER", UI.Nav.edgeMid, 1)
    local x = btn:CreateFontString(nil, "OVERLAY")
    x:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
    x:SetPoint("CENTER", box, "CENTER", 0, 0)
    x:SetText("×")
    x:SetTextColor(unpack(UI.Color.textAccent))
    btn:HookScript("OnEnter", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.hot)) end
    end)
    btn:HookScript("OnLeave", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.edgeMid)) end
    end)
end

-- ── Dungeon Finder roles ────────────────────────────────────────────
-- Role cells on UI-LFG-ICON-ROLES (67px cells on a 256px texture), the same as
-- Blizzard's GetTexCoordsForRole, which is used whenever the client has it.
local ROLE_COORDS = {
    GUIDE   = { 0,      0.2617, 0,      0.2617 },
    TANK    = { 0,      0.2617, 0.2617, 0.5234 },
    HEALER  = { 0.2617, 0.5234, 0.2617, 0.5234 },
    DAMAGER = { 0.2617, 0.5234, 0,      0.2617 },
}

local function RoleCoords(role)
    if type(GetTexCoordsForRole) == "function" then
        local ok, l, r, t, b = pcall(GetTexCoordsForRole, role)
        if ok and l and r and t and b then return l, r, t, b end
    end
    local c = ROLE_COORDS[role] or ROLE_COORDS.DAMAGER
    return c[1], c[2], c[3], c[4]
end

local ROLE_BUTTONS = {
    { "LFDQueueFrameRoleButtonTank",       "TANK" },
    { "LFDQueueFrameRoleButtonHealer",     "HEALER" },
    { "LFDQueueFrameRoleButtonDPS",        "DAMAGER" },
    { "LFDQueueFrameRoleButtonLeader",     "GUIDE" },
    { "LFDRoleCheckPopupRoleButtonTank",   "TANK" },
    { "LFDRoleCheckPopupRoleButtonHealer", "HEALER" },
    { "LFDRoleCheckPopupRoleButtonDPS",    "DAMAGER" },
    { "LFRQueueFrameRoleButtonTank",       "TANK" },
    { "LFRQueueFrameRoleButtonHealer",     "HEALER" },
    { "LFRQueueFrameRoleButtonDPS",        "DAMAGER" },
}

local function StyleRoleButton(button, role)
    if not button then return end
    if not button.__paRoleStyle then
        button.__paRoleStyle = true
        local back = button:CreateTexture(nil, "BACKGROUND")   -- dark square behind the icon
        back:SetTexture(SOLID)
        back:SetVertexColor(0, 0, 0, 0.85)
        back:SetAllPoints(button)
        UI.Outline(button, button, "BORDER", UI.Nav.edge, 1)
        local ring = _G[(button:GetName() or "") .. "Background"]   -- Blizzard's round backing
        if ring then ring:SetAlpha(0) end
    end
    -- the right icon for the role, and visible (the old skin faded every LFGFrame texture)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
        local tex = button[getter] and button[getter](button)
        if tex then
            if not TexturePath(tex):find("icon-roles", 1, true) then tex:SetTexture(ROLE_TEXTURE) end
            tex:SetTexCoord(RoleCoords(role))
            tex:SetAlpha(1)
        end
    end
end

local function ConfigureDungeonFinder()
    for _, r in ipairs(ROLE_BUTTONS) do StyleRoleButton(_G[r[1]], r[2]) end
end

-- ── Generic window skin ─────────────────────────────────────────────
-- Unpacking a huge region or child list into a table fails with "memory allocation
-- error: block too big" (it flooded errors on LFDQueueFrame). Frames that big are
-- never Blizzard art or text worth restyling, so they're skipped, as in Theme.lua.
local MAX_UNPACK = 400

local function Regions(frame)
    local n = frame.GetNumRegions and frame:GetNumRegions() or MAX_UNPACK + 1
    if n > MAX_UNPACK then return {} end
    return { frame:GetRegions() }
end

local function Children(frame)
    local n = frame.GetNumChildren and frame:GetNumChildren() or MAX_UNPACK + 1
    if n > MAX_UNPACK then return {} end
    return { frame:GetChildren() }
end

-- Parchment text is dark brown and unreadable on black. Only dark text is lightened,
-- so quest difficulty, item quality and other coloured text keep their colour.
local function LightenDarkText(frame)
    if not frame then return end
    for _, region in ipairs(Regions(frame)) do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            local r, g, b = region:GetTextColor()
            if r and (r * 0.30 + g * 0.59 + b * 0.11) < 0.35 then
                region:SetTextColor(1, 1, 1, 1)
            end
        end
    end
    for _, child in ipairs(Children(frame)) do
        LightenDarkText(child)
    end
end

local function MakeBlizzardChromeTransparent(frame)
    if not frame then return end
    for _, region in ipairs(Regions(frame)) do
        if region.GetObjectType and region:GetObjectType() == "Texture"
           and IsDecorativeTexture(region) then
            region:SetAlpha(0)
        end
    end
    -- panel buttons get the Astral button from UI.SkinTree; other buttons (quest
    -- rewards, gossip options, dungeon list entries) keep their icons
    for _, child in ipairs(Children(frame)) do
        MakeBlizzardChromeTransparent(child)
    end
end

local function HidePortraitRegions(frame)
    if not frame then return end
    for _, region in ipairs(Regions(frame)) do
        local name = region.GetName and region:GetName()
        local key = name and name:lower() or ""
        if key:find("portrait", 1, true) or key:find("bookicon", 1, true) then
            region:Hide()
        end
    end
    for _, child in ipairs(Children(frame)) do
        HidePortraitRegions(child)
    end
end

local function ThemeFrame(frame)
    if not frame then return end
    if not themed[frame] then
        themed[frame] = true
        BlackSurface(frame, 0.96)
        if frame.SetFrameStrata then frame:SetFrameStrata("DIALOG") end
        UI.Outline(frame, frame, "BORDER", UI.Nav.edge, 1)
        local name = frame:GetName() or ""
        StyleCloseButton(_G[CLOSE_BUTTON[name] or (name .. "CloseButton")])
        HidePortraitRegions(frame)
    end
    MakeBlizzardChromeTransparent(frame)
    UI.SkinTree(frame)
    LightenDarkText(frame)
end

-- ── Auto quest / auto loot ──────────────────────────────────────────
local function AutoAcceptOrCompleteQuest()
    if not PA.Settings then return end
    if PA.Settings.autoAcceptQuests
       and GetNumAvailableQuests and GetNumAvailableQuests() > 0 then
        SelectAvailableQuest(1)
        return
    end
    if PA.Settings.autoTurnInQuests
       and GetNumActiveQuests and GetNumActiveQuests() > 0 then
        SelectActiveQuest(1)
    end
end

local function AutoGossipQuest()
    if not PA.Settings then return end
    if PA.Settings.autoAcceptQuests
       and GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() > 0 then
        SelectGossipAvailableQuest(1)
        return
    end
    if PA.Settings.autoTurnInQuests
       and GetNumGossipActiveQuests and GetNumGossipActiveQuests() > 0 then
        SelectGossipActiveQuest(1)
    end
end

local lastLootAttempt = 0
local function AutoLoot()
    if not PA.Settings or not PA.Settings.autoLoot then return end
    if GetTime() - lastLootAttempt < 0.05 then return end
    lastLootAttempt = GetTime()
    local count = GetNumLootItems and GetNumLootItems() or 0
    for slot = count, 1, -1 do
        LootSlot(slot)
    end
    -- CloseLoot closes the window the normal way (LOOT_CLOSED); hiding LootFrame
    -- directly skipped Blizzard's UI panel bookkeeping
    CloseLoot()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "QUEST_GREETING" then
        AutoAcceptOrCompleteQuest()
    elseif event == "QUEST_DETAIL" then
        if PA.Settings and PA.Settings.autoAcceptQuests then AcceptQuest() end
    elseif event == "QUEST_PROGRESS" then
        if PA.Settings and PA.Settings.autoTurnInQuests
           and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        if PA.Settings and PA.Settings.autoTurnInQuests then GetQuestReward(1) end
    elseif event == "GOSSIP_SHOW" then
        AutoGossipQuest()
    elseif event == "LOOT_OPENED" then
        AutoLoot()
    end
end)

-- 5 times a second: keep open windows themed as Blizzard adds rows. Quests are handled
-- by the events above; re-selecting them here as well used to send a request to the
-- server on every tick.
local watcher = CreateFrame("Frame")
watcher:SetSize(1, 1)
local elapsed = 0
watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    if PA.Settings and PA.Settings.autoLoot and LootFrame and LootFrame:IsShown() then
        AutoLoot()
    end
end)
