
local PA = ProjectAstral
local UI = PA.UI

-- Astral Chat: Blizzard's chat windows in the Astral look, plus
--   * a resize grip in each window's bottom-right corner (works on locked windows too)
--   * mouse-wheel scrolling (Shift = a page, Ctrl = top/bottom) and a jump-to-newest arrow
--   * whisper tabs: Blizzard's "New Whispers: New Tab" mode (whisperMode CVar), so
--     sending or receiving a whisper opens a tab for that player
-- Channels, filters, fonts and message colours stay Blizzard's. The look is applied
-- once per window (temporary whisper windows included); turning it off needs /reload.

local SOLID      = "Interface\\Buttons\\WHITE8X8"
local MAX_UNPACK = 400
local ACCENT     = { 0.40, 0.78, 1.00 }
local BLACK      = { 0, 0, 0 }

local AC = {}
PA.AstralChat = AC

local skinned = {}              -- chat frame -> true
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local function Cfg()
    local c = PA.Settings and PA.Settings.chat
    return type(c) == "table" and c or {}
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff99b8ff[Project Astral]|r " .. msg)
end

local function BgAlpha()
    local a = tonumber(Cfg().bgAlpha) or 0.9
    return math.max(0, math.min(1, a))
end

local function TexPath(r)
    local p = r and r.GetTexture and r:GetTexture()
    return type(p) == "string" and p:lower() or ""
end

-- FCF fades Blizzard's chat art in and out (alpha + Show) but never sets the file
-- again, so clearing the file hides it for good
local function Blank(r)
    if r and r.GetObjectType and r:GetObjectType() == "Texture" then
        r:SetTexture(nil)
    end
end

-- buttons FCF keeps re-showing: a hidden parent keeps them off screen
local function Stash(frame)
    if frame and frame.SetParent then frame:SetParent(hiddenParent) end
end

local function BlankByPath(frame, patterns, skip)
    if not (frame and frame.GetNumRegions) or frame:GetNumRegions() > MAX_UNPACK then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r:GetObjectType() == "Texture" then
            local p = TexPath(r)
            if not (skip and p:find(skip, 1, true)) then
                for _, pat in ipairs(patterns) do
                    if p:find(pat, 1, true) then Blank(r); break end
                end
            end
        end
    end
end

local function Fill(owner, layer, c, a)
    local t = owner:CreateTexture(nil, layer)
    t:SetTexture(SOLID)
    t:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    return t
end

-- ── Window background ───────────────────────────────────────────────

local FRAME_TEX = { "Background", "TopLeftTexture", "TopRightTexture", "BottomLeftTexture",
    "BottomRightTexture", "TopTexture", "BottomTexture", "LeftTexture", "RightTexture" }

local function PaintFrame(cf)
    local a = BgAlpha()
    cf.__paBg:SetVertexColor(BLACK[1], BLACK[2], BLACK[3], a)
    -- a see-through background shouldn't leave a hard box behind
    local la = math.min(1, a * 2)
    for _, l in ipairs(cf.__paLines) do l:SetAlpha(la) end
    cf.__paAccent:SetAlpha(la * 0.7)
end

-- ── Tabs ────────────────────────────────────────────────────────────

local TAB_TEX = { "Left", "Middle", "Right", "SelectedLeft", "SelectedMiddle", "SelectedRight",
    "HighlightLeft", "HighlightMiddle", "HighlightRight" }

local TAB_ICON     = 8
local TAB_ICON_PAD = 0
local TAB_WIDTH    = 96

-- matched against the lower-case tab name, first hit wins
local TAB_ICONS = {
    { "combat",  "Interface\\Icons\\Ability_DualWield" },
    { "general", "Interface\\Icons\\INV_Misc_Book_09" },
    { "party",   "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
    { "group",   "Interface\\Icons\\Spell_Holy_PrayerOfHealing02" },
    { "raid",    "Interface\\Icons\\INV_Misc_Head_Dragon_01" },
    { "guild",   "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { "officer", "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    { "trade",   "Interface\\Icons\\INV_Misc_Coin_01" },
    { "loot",    "Interface\\Icons\\INV_Misc_Bag_10" },
    { "whisper", "Interface\\Icons\\INV_Letter_15" },
    { "world",   "Interface\\Icons\\Spell_Nature_Starfall" },
    { "pvp",     "Interface\\Icons\\INV_BannerPVP_02" },
    { "battle",  "Interface\\Icons\\INV_BannerPVP_02" },
}
local TAB_ICON_WHISPER = "Interface\\Icons\\INV_Letter_15"
local TAB_ICON_DEFAULT = "Interface\\Icons\\INV_Misc_Note_01"

local tabsWidened = false   -- a tab got wider: ask the dock to lay its tabs out again

local function TabIcon(tab, cf)
    if cf.isTemporary or cf.chatType == "WHISPER" or cf.chatType == "BN_WHISPER" then
        return TAB_ICON_WHISPER
    end
    local fs = tab:GetFontString()
    local name = ((fs and fs:GetText()) or tab:GetText() or ""):lower()
    for _, e in ipairs(TAB_ICONS) do
        if name:find(e[1], 1, true) then return e[2] end
    end
    return TAB_ICON_DEFAULT
end

local function TabOf(cf)
    return cf and cf.GetName and cf:GetName() and _G[cf:GetName() .. "Tab"]
end

local function CompactDockTabs()
    local dock = GENERAL_CHAT_DOCK
    local list
    if type(FCFDock_GetChatFrames) == "function" and dock then
        list = FCFDock_GetChatFrames(dock)
    else
        list = DOCKED_CHAT_FRAMES
    end
    if type(list) ~= "table" then return end

    local previous
    for _, cf in ipairs(list) do
        local tab = TabOf(cf)
        if tab and cf.isDocked then
            tab:ClearAllPoints()
            tab:SetWidth(TAB_WIDTH)
            if previous then
                tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
            else
                -- flush with the chat background's left edge (the 0.1s watcher re-checks it)
                local x = 0
                local bgLeft   = cf.__paBg and cf.__paBg:GetLeft()
                local dockLeft = GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK:GetLeft()
                if bgLeft and dockLeft then x = bgLeft - dockLeft end
                tab:SetPoint("LEFT", GENERAL_CHAT_DOCK, "LEFT", x, 0)
            end
            previous = tab
        end
    end
end

local function PaintTab(tab)
    local cf = tab and tab.__paFrame
    if not cf then return end

    -- only the selected window of a dock is shown; undocked windows always are
    local sel = cf:IsShown()
    local hot = tab.__paHover
    local ct  = tab.selectedColorTable          -- whisper tabs carry the whisper colour
    local r, g, b = ACCENT[1], ACCENT[2], ACCENT[3]
    if ct and ct.r then r, g, b = ct.r, ct.g, ct.b end

    local fs = tab:GetFontString() or _G[tab:GetName() .. "Text"]
    if fs then
        fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
        if sel then
            if ct and ct.r then fs:SetTextColor(r, g, b) else fs:SetTextColor(unpack(UI.Color.textTitle)) end
        elseif hot then
            fs:SetTextColor(unpack(UI.Color.textPrimary))
        else
            fs:SetTextColor(unpack(UI.Nav.muted))
        end
    end

    tab.__paLine:SetVertexColor(r, g, b, 1)
    if sel then tab.__paLine:Show() else tab.__paLine:Hide() end
    if hot and not sel then tab.__paFill:Show() else tab.__paFill:Hide() end
    if tab.__paGlow then tab.__paGlow:SetVertexColor(r, g, b, 0.35) end

    -- black backing and icon: full colour on the selected or hovered tab, dimmed otherwise
    tab.__paBack:SetVertexColor(BLACK[1], BLACK[2], BLACK[3], sel and 0.92 or 0.72)
    for _, l in ipairs(tab.__paLines) do
        if sel then l:SetVertexColor(r, g, b, 0.9)
        else l:SetVertexColor(unpack(UI.Nav.edge)) end
    end
    local close = tab.__paClose
    if not cf.isTemporary then
        close:Hide()
    elseif hot or close.__hover then
        close.__hideAt = nil
        close:Show()
    elseif close:IsShown() and not close.__hideAt then
        close.__hideAt = GetTime() + 0.35      -- time to move the mouse onto the x
    end
end

local function CloseWindow(cf)
    if cf and cf.isTemporary and type(FCF_Close) == "function" then FCF_Close(cf) end
end

local function SkinTab(cf)
    local tab = TabOf(cf)
    if not tab or tab.__paFrame then return end
    tab.__paFrame = cf

    local tname = tab:GetName()
    local glow  = tab.glow or _G[tname .. "Glow"]
    for _, s in ipairs(TAB_TEX) do Blank(_G[tname .. s]) end
    if tab.GetHighlightTexture then Blank(tab:GetHighlightTexture()) end
    BlankByPath(tab, { "chatframetab", "chatwindowtab" }, "newmessage")

    local fs = tab:GetFontString() or _G[tname .. "Text"]
    if fs then
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", tab, "CENTER", 0, 0)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "THICKOUTLINE")
        fs:SetWidth(TAB_WIDTH - 8)
        if fs.SetWordWrap then fs:SetWordWrap(false) end
        if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
        fs:SetTextColor(unpack(UI.Color.textPrimary))
    end

    -- Blizzard sizes a tab to its name (PanelTemplates_TabResize, hooked in EnableLook
    -- to keep this extra width), so widen it and nudge the name right for the icon
    tab.__paBaseWidth = TAB_WIDTH
    tab:SetWidth(TAB_WIDTH)
    tabsWidened = true

    local pill = CreateFrame("Frame", nil, tab)
    tab.__paPill = pill
    if fs then
        pill:SetPoint("TOPLEFT",     tab, "TOPLEFT",      0, 1)
        pill:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT",  0, -1)
    else
        pill:SetAllPoints(tab)
    end

    tab.__paBack = Fill(tab, "BACKGROUND", BLACK, 0.72)
    tab.__paBack:SetAllPoints(pill)
    tab.__paLines = UI.Outline(tab, pill, "BORDER", UI.Nav.edge, 1)

    tab.__paFill = Fill(tab, "BORDER", { 1, 1, 1 }, 0.07)
    tab.__paFill:SetAllPoints(pill)

    tab.__paLine = tab:CreateTexture(nil, "ARTWORK")
    tab.__paLine:SetTexture(SOLID)
    tab.__paLine:SetHeight(2)
    tab.__paLine:SetPoint("TOPLEFT",  pill, "BOTTOMLEFT",  0, -1)
    tab.__paLine:SetPoint("TOPRIGHT", pill, "BOTTOMRIGHT", 0, -1)

    -- new-message flash (FCF flashes this texture): a soft tint instead of the gold glow
    if glow and glow.SetTexture then
        glow:SetTexture(SOLID)
        glow:SetTexCoord(0, 1, 0, 1)
        glow:SetBlendMode("BLEND")
        if glow.SetDrawLayer then glow:SetDrawLayer("BORDER") end   -- above the black backing
        glow:ClearAllPoints()
        glow:SetAllPoints(pill)
        tab.__paGlow = glow
    end

    -- close button for whisper tabs (hover the tab), middle-click also closes
    local close = CreateFrame("Button", nil, tab)
    close:SetSize(13, 13)
    close:SetPoint("BOTTOMLEFT", pill, "TOPRIGHT", -8, -6)
    close:SetFrameLevel(tab:GetFrameLevel() + 3)
    local cbg = Fill(close, "BACKGROUND", UI.Nav.deep, 0.95)
    cbg:SetAllPoints()
    local clines = UI.Outline(close, close, "BORDER", UI.Nav.edgeMid, 1)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cx:SetPoint("CENTER", close, "CENTER", 1, 1)
    cx:SetText("x")
    close:SetScript("OnEnter", function(self)
        self.__hover = true
        cbg:SetVertexColor(0.55, 0.12, 0.16, 1)
        for _, l in ipairs(clines) do l:SetVertexColor(unpack(UI.Color.textBad)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Close whisper tab")
        GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function(self)
        self.__hover = false
        local c = UI.Nav.deep
        cbg:SetVertexColor(c[1], c[2], c[3], 0.95)
        for _, l in ipairs(clines) do l:SetVertexColor(unpack(UI.Nav.edgeMid)) end
        GameTooltip:Hide()
        tab.__paHover = MouseIsOver(tab) and true or false
        PaintTab(tab)
    end)
    close:SetScript("OnClick", function() CloseWindow(tab.__paFrame) end)
    close:SetScript("OnUpdate", function(self)
        if self.__hideAt and GetTime() >= self.__hideAt then
            self.__hideAt = nil
            if not (self.__hover or tab.__paHover) then self:Hide() end
        end
    end)
    close:Hide()
    tab.__paClose = close

    tab:HookScript("OnEnter", function(self) self.__paHover = true; PaintTab(self) end)
    tab:HookScript("OnLeave", function(self)
        self.__paHover = MouseIsOver(self) and true or false
        PaintTab(self)
    end)
    tab:HookScript("OnMouseUp", function(self, button)
        if button == "MiddleButton" then CloseWindow(self.__paFrame) end
    end)

    PaintTab(tab)
end

-- ── Message box ─────────────────────────────────────────────────────

local EDIT_TEX = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

local function PaintEditAccent(eb)
    if not eb.__paAccent then return end
    local t = eb:GetAttribute("chatType")
    local info = t and ChatTypeInfo and ChatTypeInfo[t]
    if t == "CHANNEL" and ChatTypeInfo then
        info = ChatTypeInfo["CHANNEL" .. tostring(eb:GetAttribute("channelTarget"))] or info
    end
    if info and info.r then
        eb.__paAccent:SetVertexColor(info.r, info.g, info.b, 1)
    else
        eb.__paAccent:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    end
end

local function SkinEditBox(cf)
    local eb = cf.editBox or _G[cf:GetName() .. "EditBox"]
    if not eb or eb.__paSkinned then return end
    eb.__paSkinned = true

    local en = eb:GetName()
    if en then
        for _, s in ipairs(EDIT_TEX) do Blank(_G[en .. s]) end
    end
    BlankByPath(eb, { "chatinputborder", "ui-chatinput" })
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")

    local bg = Fill(eb, "BACKGROUND", BLACK, 0.95)
    bg:SetPoint("TOPLEFT",     eb, "TOPLEFT",      3, -3)
    bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -3,  3)
    local lines = UI.Outline(eb, bg, "BORDER", UI.Nav.edgeMid, 1)

    -- end to end with the window's background (the box is inset 3px from the edit box)
    if cf.__paBg then
        eb:ClearAllPoints()
        eb:SetPoint("TOPLEFT",  cf.__paBg, "BOTTOMLEFT",  -3, 1)
        eb:SetPoint("TOPRIGHT", cf.__paBg, "BOTTOMRIGHT",  3, 1)
    end

    -- left bar in the colour of whatever you're about to send (say, party, whisper...)
    local acc = eb:CreateTexture(nil, "ARTWORK")
    acc:SetTexture(SOLID)
    acc:SetWidth(2)
    acc:SetPoint("TOPLEFT",    bg, "TOPLEFT",    1, -1)
    acc:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 1,  1)
    eb.__paAccent = acc
    PaintEditAccent(eb)

    eb:HookScript("OnEditFocusGained", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Color.accentSoft)) end
    end)
    eb:HookScript("OnEditFocusLost", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.edgeMid)) end
    end)
end

-- ── Resize grip + jump-to-newest ────────────────────────────────────

local function DockPrimary()
    return (GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.primary) or ChatFrame1
end

-- docked windows share the dock's size; keep any that don't follow it by anchors in step
local function SyncDocked(primary)
    local list
    if type(FCFDock_GetChatFrames) == "function" and GENERAL_CHAT_DOCK then
        list = FCFDock_GetChatFrames(GENERAL_CHAT_DOCK)
    else
        list = DOCKED_CHAT_FRAMES
    end
    if type(list) ~= "table" then return end
    local w, h = primary:GetWidth(), primary:GetHeight()
    for _, f in ipairs(list) do
        if f ~= primary and f.isDocked
           and (math.abs(f:GetWidth() - w) > 0.5 or math.abs(f:GetHeight() - h) > 0.5) then
            f:SetWidth(w)
            f:SetHeight(h)
        end
    end
end

local function MakeGrip(cf)
    local grip = CreateFrame("Button", nil, cf)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 5, -5)
    grip:SetFrameLevel(cf:GetFrameLevel() + 6)
    local dots = {}
    for i = 0, 2 do
        for j = 0, 2 - i do
            local d = grip:CreateTexture(nil, "OVERLAY")
            d:SetTexture(SOLID)
            d:SetSize(2, 2)
            d:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -3 - i * 4, 3 + j * 4)
            dots[#dots + 1] = d
        end
    end
    local function Paint(hot)
        local c = hot and UI.Color.textTitle or UI.Color.accentSoft
        for _, d in ipairs(dots) do d:SetVertexColor(c[1], c[2], c[3], hot and 1 or 0.8) end
    end
    Paint(false)
    grip:SetAlpha(0)
    grip:EnableMouse(false)

    local function Stop(self)
        local t = self.__sizing
        if not t then return end
        self.__sizing = nil
        t:StopMovingOrSizing()
        if t.isDocked or t == DockPrimary() then SyncDocked(t) end
        if type(FCF_SavePositionAndDimensions) == "function" then FCF_SavePositionAndDimensions(t) end
        Paint(MouseIsOver(self))
    end

    grip:SetScript("OnEnter", function(self)
        Paint(true)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Drag to resize chat")
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        if not self.__sizing then Paint(false) end
        GameTooltip:Hide()
    end)
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        -- a docked tab resizes the whole dock, like Blizzard's own grip
        local t = cf.isDocked and DockPrimary() or cf
        t:SetResizable(true)
        if t.SetMaxResize then t:SetMaxResize(UIParent:GetWidth(), UIParent:GetHeight()) end
        self.__sizing = t
        GameTooltip:Hide()
        t:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", Stop)
    grip:SetScript("OnHide", Stop)
    cf.__paGrip = grip
end

local function MakeJump(cf)
    local b = CreateFrame("Button", nil, cf)
    b:SetSize(18, 18)
    b:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", -14, -1)
    b:SetFrameLevel(cf:GetFrameLevel() + 6)
    local bg = Fill(b, "BACKGROUND", UI.Nav.deep, 0.9)
    bg:SetAllPoints()
    local lines = UI.Outline(b, b, "BORDER", UI.Nav.edgeMid, 1)

    -- ▼ with a bar under it, drawn from 1px rows
    local icon = CreateFrame("Frame", nil, b)
    icon:SetSize(9, 8)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    for i, w in ipairs({ 9, 7, 5, 3, 1 }) do
        local t = Fill(icon, "ARTWORK", UI.Color.textTitle, 0.9)
        t:SetSize(w, 1)
        t:SetPoint("TOP", icon, "TOP", 0, -(i - 1))
    end
    local base = Fill(icon, "ARTWORK", UI.Color.textTitle, 0.9)
    base:SetSize(9, 1)
    base:SetPoint("BOTTOM", icon, "BOTTOM", 0, 0)

    b:SetScript("OnEnter", function(self)
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.hot)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetText("Jump to newest messages")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.edgeMid)) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() cf:ScrollToBottom() end)
    b:Hide()
    cf.__paJump = b
end

local function OnWheel(self, delta)
    if delta > 0 then
        if IsControlKeyDown() then self:ScrollToTop()
        elseif IsShiftKeyDown() then self:PageUp()
        else self:ScrollUp() end
    else
        if IsControlKeyDown() then self:ScrollToBottom()
        elseif IsShiftKeyDown() then self:PageDown()
        else self:ScrollDown() end
    end
end

-- ── Social + chat menu buttons (replace Blizzard's, on the right of the tab row) ──

local dockButtons, friendsBtn

local function IconButton(parent, icon, onClick, tip, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(label and 78 or 18, 18)
    local bg = Fill(b, "BACKGROUND", UI.Nav.deep, 0.9)
    bg:SetAllPoints()
    local lines = UI.Outline(b, b, "BORDER", UI.Nav.edge, 1)
    local text = b:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    text:SetFont("Fonts\\FRIZQT__.TTF", 10, "THICKOUTLINE")
    text:SetText(label or "")
    text:SetTextColor(unpack(UI.Color.textPrimary))
    b:SetScript("OnEnter", function(self)
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.hot)) end
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(type(tip) == "function" and tip() or tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
        for _, l in ipairs(lines) do l:SetVertexColor(unpack(UI.Nav.edge)) end
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", onClick)
    b.label = text
    return b
end

local function OnlineFriends()
    local n = 0
    local ok, _, online = pcall(GetNumFriends)
    if ok and tonumber(online) then n = n + online end
    if type(BNGetNumFriends) == "function" then
        local ok2, _, bnOnline = pcall(BNGetNumFriends)
        if ok2 and tonumber(bnOnline) then n = n + bnOnline end
    end
    return n
end

local function UpdateFriends()
    if not friendsBtn then return end
    local count = OnlineFriends()
    friendsBtn.label:SetText("Friends (" .. count .. ")")
    friendsBtn:SetWidth(92)
end

local function MakeDockButtons()
    if dockButtons or not ChatFrame1 then return end
    local h = CreateFrame("Frame", "PAChatDockButtons", UIParent)
    h:SetSize(190, 18)
    h:SetFrameStrata(ChatFrame1:GetFrameStrata())
    h:SetFrameLevel(ChatFrame1:GetFrameLevel() + 10)
    h:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 18, 12)

    local menu
    menu = IconButton(h, "Interface\\Icons\\Ability_Warrior_BattleShout", function()
        if not ChatMenu then return end
        if ChatMenu:IsShown() then ChatMenu:Hide(); return end
        ChatMenu:ClearAllPoints()
        ChatMenu:SetPoint("BOTTOMRIGHT", menu, "TOPRIGHT", 0, 4)
        ChatMenu:Show()
    end, "Emotes, languages and voice", "Emotes")
    menu:SetPoint("RIGHT", h, "RIGHT", 0, 0)

    friendsBtn = IconButton(h, "Interface\\Icons\\Achievement_Reputation_01", function()
        if type(ToggleFriendsFrame) == "function" then ToggleFriendsFrame(1) end
    end, function() return "Friends online: " .. OnlineFriends() end, "Friends")
    friendsBtn:SetPoint("RIGHT", menu, "LEFT", -8, 0)
    for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE",
                          "BN_FRIEND_ACCOUNT_OFFLINE", "PLAYER_ENTERING_WORLD" }) do
        pcall(h.RegisterEvent, h, ev)
    end
    h:SetScript("OnEvent", UpdateFriends)
    UpdateFriends()
    dockButtons = h
end

local function SkinCombatLogBar()
    local qb = CombatLogQuickButtonFrame_Custom
    if not qb or qb.__paSkinned then return end
    qb.__paSkinned = true
    local tex = _G["CombatLogQuickButtonFrame_CustomTexture"]
    if tex and tex.SetTexture then
        tex:SetTexture(SOLID)
        local c = UI.Nav.deep
        tex:SetVertexColor(c[1], c[2], c[3], 0.9)
    end
end

-- ── Apply ───────────────────────────────────────────────────────────

local function SkinFrame(cf)
    if skinned[cf] or not (cf and cf.GetName and cf:GetName()) then return end
    if not TabOf(cf) then return end           -- not a chat window
    skinned[cf] = true
    local name = cf:GetName()

    for _, s in ipairs(FRAME_TEX) do Blank(_G[name .. s]) end
    if type(CHAT_FRAME_TEXTURES) == "table" then
        for _, s in ipairs(CHAT_FRAME_TEXTURES) do Blank(_G[name .. s]) end
    end
    Stash(cf.buttonFrame or _G[name .. "ButtonFrame"])
    Stash(cf.resizeButton or _G[name .. "ResizeButton"])

    local bg = cf:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(SOLID)
    bg:SetPoint("TOPLEFT",     cf, "TOPLEFT",     -5,  5)
    bg:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT",  5, -5)
    cf.__paBg = bg
    cf.__paLines = UI.Outline(cf, bg, "BORDER", UI.Nav.edge, 1)
    local accent = Fill(cf, "BORDER", ACCENT, 1)
    accent:SetHeight(1)
    accent:SetPoint("TOPLEFT",  bg, "TOPLEFT",   1, 0)
    accent:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -1, 0)
    cf.__paAccent = accent

    cf:EnableMouseWheel(true)
    cf:SetScript("OnMouseWheel", OnWheel)

    SkinTab(cf)
    SkinEditBox(cf)
    MakeGrip(cf)
    MakeJump(cf)

    cf:HookScript("OnShow", function(self) PaintTab(TabOf(self)) end)
    cf:HookScript("OnHide", function(self) PaintTab(TabOf(self)) end)
    PaintFrame(cf)
end

function AC.SkinAll()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then SkinFrame(cf) end
    end
    if type(CHAT_FRAMES) == "table" then          -- includes temporary whisper windows
        for _, n in ipairs(CHAT_FRAMES) do
            local cf = _G[n]
            if cf then SkinFrame(cf) end
        end
    end
    if type(FCF_GetCurrentChatFrame) == "function" then
        local ok, cf = pcall(FCF_GetCurrentChatFrame)
        if ok and cf then SkinFrame(cf) end
    end
    Stash(ChatFrameMenuButton)
    Stash(FriendsMicroButton)
    MakeDockButtons()
    SkinCombatLogBar()

    -- docked tabs sit next to each other: lay them out again for the wider tabs
    if tabsWidened then
        tabsWidened = false
        if type(FCF_DockUpdate) == "function" then
            pcall(FCF_DockUpdate)
        elseif type(FCFDock_UpdateTabs) == "function" and GENERAL_CHAT_DOCK then
            pcall(FCFDock_UpdateTabs, GENERAL_CHAT_DOCK, true)
        end
    end
    CompactDockTabs()
end

function AC.ApplyLook()
    for cf in pairs(skinned) do
        PaintFrame(cf)
        PaintTab(TabOf(cf))
    end
end

-- grips and dock buttons show while the mouse is over the chat; the jump arrow
-- shows whenever a window is scrolled up
local watcher = CreateFrame("Frame")
watcher:Hide()
local tick = 0
watcher:SetScript("OnUpdate", function(_, dt)
    tick = tick + dt
    if tick < 0.1 then return end
    tick = 0
    -- Blizzard can restore its default tab spacing during selection, docking,
    -- and message updates. Re-apply the zero-gap layout after those changes.
    CompactDockTabs()
    for cf in pairs(skinned) do
        if cf:IsVisible() and cf.__paGrip and cf.__paJump then
            local grip = cf.__paGrip
            local over = grip.__sizing or MouseIsOver(cf, 30, -8, -8, 8)
            if over then
                if grip:GetAlpha() < 1 then grip:SetAlpha(1); grip:EnableMouse(true) end
            elseif grip:GetAlpha() > 0 then
                grip:SetAlpha(0); grip:EnableMouse(false)
            end
            local jump = cf.__paJump
            if cf.AtBottom and not cf:AtBottom() then
                if not jump:IsShown() then jump:Show() end
            elseif jump:IsShown() then
                jump:Hide()
            end
        end
    end
    if dockButtons then
        local over = MouseIsOver(DockPrimary(), 30, -8, -8, 8) or MouseIsOver(dockButtons)
        dockButtons:SetAlpha(over and 1 or 0.25)
    end

    -- the dock's first tab (General) starts flush with the window's left edge; the
    -- other docked tabs are anchored to it and follow. Re-checked here because
    -- Blizzard re-anchors tabs when the dock changes.
    local primary = DockPrimary()
    local tab = TabOf(primary)
    if tab and tab.__paPill and primary.__paBg and tab:IsVisible()
       and tab:GetNumPoints() == 1 and not IsMouseButtonDown("LeftButton") then
        local pl, bl = tab.__paPill:GetLeft(), primary.__paBg:GetLeft()
        if pl and bl and math.abs(pl - bl) > 0.5 then
            local p, rel, rp, x, y = tab:GetPoint(1)
            tab:ClearAllPoints()
            tab:SetPoint(p, rel, rp, (x or 0) - (pl - bl), y or 0)
        end
    end
end)

local lookOn, hooked = false, false

function AC.EnableLook()
    if lookOn then return end
    lookOn = true
    if not hooked then
        hooked = true
        if type(FCF_OpenTemporaryWindow) == "function" then
            hooksecurefunc("FCF_OpenTemporaryWindow", function() AC.SkinAll() end)
        end
        if type(FCFTab_UpdateColors) == "function" then
            hooksecurefunc("FCFTab_UpdateColors", function(tab) PaintTab(tab) end)
        end
        if type(PanelTemplates_TabResize) == "function" then
            -- argument order differs between client builds; the tab is the table argument
            hooksecurefunc("PanelTemplates_TabResize", function(a, b)
                local tab = (type(a) == "table" and a) or (type(b) == "table" and b)
                if tab and tab.__paBaseWidth then
                    tab:SetWidth(tab.__paBaseWidth + TAB_ICON_PAD)
                end
            end)
        end
        if type(FCF_DockUpdate) == "function" then
            hooksecurefunc("FCF_DockUpdate", CompactDockTabs)
        elseif type(FCFDock_UpdateTabs) == "function" then
            hooksecurefunc("FCFDock_UpdateTabs", CompactDockTabs)
        end
        if type(ChatEdit_UpdateHeader) == "function" then
            hooksecurefunc("ChatEdit_UpdateHeader", function(eb)
                if eb and eb.__paSkinned then PaintEditAccent(eb) end
            end)
        end
    end
    AC.SkinAll()
    watcher:Show()
end

function AC.SetLookEnabled(on)
    Cfg().skin = on and true or false
    if on then
        AC.EnableLook()
    elseif lookOn then
        Print("Astral chat style turns off after you type |cffffffff/reload|r.")
    end
end

-- ── Whisper tabs (Blizzard's whisperMode CVar) ──────────────────────

local function GetWhisperMode()
    local ok, v = pcall(GetCVar, "whisperMode")
    if ok and type(v) == "string" and v ~= "" then return v end
end

function AC.WhisperTabsSupported()
    return GetWhisperMode() ~= nil
end

function AC.SetWhisperOptions(tabs, inline)
    local c = Cfg()
    c.whisperTabs   = tabs and true or false
    c.whisperInline = inline and true or false
    local cur = GetWhisperMode()
    if not cur then return false end
    local want = not c.whisperTabs and "inline"
        or (c.whisperInline and "popout_and_inline" or "popout")
    if cur ~= want then pcall(SetCVar, "whisperMode", want) end
    c.whisperModeSet = true
    return true
end

-- first login: turn whisper tabs on. After that the CVar is the truth, since
-- Interface Options > Social > New Whispers changes it too.
function AC.SyncWhisperMode()
    local c = Cfg()
    local cur = GetWhisperMode()
    if not cur then return end
    if not c.whisperModeSet then
        AC.SetWhisperOptions(c.whisperTabs ~= false, c.whisperInline ~= false)
    else
        c.whisperTabs   = cur ~= "inline"
        c.whisperInline = cur ~= "popout"
    end
end

-- Blizzard's chat manager opens the tab itself. Should a whisper (sent or received)
-- ever get through without one, open it a frame later, once that event has been
-- handed out to every window, and replay the message into the new tab.
if type(FCFManager_GetChatTarget) == "function"
   and type(FCFManager_GetNumDedicatedFrames) == "function"
   and type(FCF_OpenTemporaryWindow) == "function" then
    local pending = {}
    local backup = CreateFrame("Frame")
    backup:Hide()
    backup:RegisterEvent("CHAT_MSG_WHISPER")
    backup:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
    backup:SetScript("OnEvent", function(self, event, ...)
        local author = select(2, ...)
        if type(author) ~= "string" or author == "" then return end
        pending[#pending + 1] = { event = event, author = author, n = select("#", ...), args = { ... } }
        self:Show()
    end)
    backup:SetScript("OnUpdate", function(self)
        self:Hide()
        local list = pending
        pending = {}
        local mode = GetWhisperMode()
        if mode ~= "popout" and mode ~= "popout_and_inline" then return end
        for _, p in ipairs(list) do
            local okT, target = pcall(FCFManager_GetChatTarget, "WHISPER", p.author)
            local okN, count  = pcall(FCFManager_GetNumDedicatedFrames, "WHISPER", target)
            if okT and target and okN and count == 0 then
                local okW, cf = pcall(FCF_OpenTemporaryWindow, "WHISPER", target)
                local handler = okW and cf and cf.GetScript and cf:GetScript("OnEvent")
                if handler then pcall(handler, cf, p.event, unpack(p.args, 1, p.n)) end
            end
        end
    end)
end

-- ── Boot ────────────────────────────────────────────────────────────

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_CombatLog" and lookOn then SkinCombatLogBar() end
        return
    end
    -- Settings.lua loads saved settings on PLAYER_LOGIN first (it registered earlier)
    local c = Cfg()
    if PA.Settings and type(PA.Settings.chat) == "table" and not c.blackBg then
        c.bgAlpha = 0.9            -- first version saved a see-through 0.45; move to near-black once
        c.blackBg = true
    end
    AC.SyncWhisperMode()
    if Cfg().skin ~= false then AC.EnableLook() end
end)
