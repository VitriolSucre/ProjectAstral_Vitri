local AIO = AIO or (require and require("AIO"))
if AIO and AIO.AddAddon and AIO.AddAddon() then return end

local PA = ProjectAstral

local GF = {}
PA.GemFusion = GF
GF.info        = {}
GF.catalog     = {}
GF.scrolls     = {}
GF.bagsByEntry = {}
GF.receiving   = false
GF.statusText  = ""
GF.statusUntil = 0

local frame, FlashStatus

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

function GF.RequestInfo()
    if AIO and AIO.Handle then
        AIO.Handle("AstralgemServer", "RequestInfo")
    else
        Send("gem info")
    end
end

if AIO and AIO.AddHandlers then
    local ClientHandler = AIO.AddHandlers("Astralgem", {})

    ClientHandler.Info = function(_, payload)
        if type(payload) ~= "table" then return end
        GF.catalog = {}
        GF.scrolls = {}
        for k, v in pairs(payload.info or {}) do
            GF.info[k] = tostring(v)
        end
        local prefetchIds = {}
        for _, g in ipairs(payload.gems or {}) do
            if g.entry then
                GF.catalog[g.entry] = {
                    tier      = g.tier,
                    family    = g.family,
                    eventType = tonumber(g.eventType) or 6,
                    name      = g.name    or "",
                    quality   = g.quality or 0,
                    isMythic  = g.isMythic and true or nil,
                }
                prefetchIds[#prefetchIds + 1] = g.entry
            end
        end
        for _, s in ipairs(payload.scrolls or {}) do
            if s.entry then
                GF.scrolls[s.entry] = {
                    kind    = s.kind,
                    pool    = s.pool,
                    name    = s.name    or "",
                    quality = s.quality or 0,
                }
                prefetchIds[#prefetchIds + 1] = s.entry
            end
        end
        if PA.ItemCache and PA.ItemCache.RegisterMany then
            PA.ItemCache.RegisterMany(prefetchIds)
        else
            for _, e in ipairs(prefetchIds) do GetItemInfo(e) end
        end
        GF.receiving = false
        if GF.KickAutoFuse then GF.KickAutoFuse() end   -- catalog + unlocks just arrived
        if frame and frame:IsShown() then
            local hooks = GF._refresh_hooks or {}
            if hooks.ScanBags       then hooks.ScanBags() end
            if frame.gemListPanel and hooks.RefreshGemList then
                hooks.RefreshGemList(frame.gemListPanel)
            end
            if hooks.Refresh        then hooks.Refresh() end
        end
        if PA.GemStash and PA.GemStash.Refresh then   -- the catalog view lives in the Gem Stash tab
            PA.GemStash.Refresh()
        end
    end

    local FUSE_FAIL_MSG = {
        USAGE            = "Internal: missing item entry.",
        NOT_FOUND        = "You don't have 3 of that gem in the stash.",
        T1_ONLY_INPUTS   = "Only T1-T7 gems can be fused. T8 is the top of the chain.",
        NOT_SAME_FAMILY  = "This gem has no family — cannot fuse.",
        NOT_ENOUGH_GOLD  = "Not enough gold to fuse this tier.",
        NO_PERMISSION    = "This fusion tier is locked — unlock it in the Astral Tree first.",
        NO_RECIPE        = "No fusion output for this family/tier.",
        DISABLED         = "Fusion is disabled by the realm operator.",
    }
    ClientHandler.FuseResult = function(_, status, entry)
        if status == "OK" then
            SendChatMessage(".gem fuse " .. tostring(entry or 0), "SAY")

            local srcCat  = GF.catalog and GF.catalog[entry]
            local srcTier = srcCat and srcCat.tier or 0
            local family  = srcCat and srcCat.family or ""
            local outTier = srcTier > 0 and (srcTier + 1) or nil

            local outEntry, outLink, outName
            if GF.catalog and family ~= "" and outTier then
                for e, c in pairs(GF.catalog) do
                    if c.family == family and c.tier == outTier and not c.isMythic then
                        outEntry = e
                        break
                    end
                end
            end
            if outEntry then
                outLink = select(2, GetItemInfo(outEntry))
                outName = outLink or (select(1, GetItemInfo(outEntry)))
                          or ("T" .. tostring(outTier) .. " " .. family)
            else
                outName = outTier
                          and ("T" .. tostring(outTier) .. " " .. family)
                          or  ("item " .. tostring(entry))
            end

            FlashStatus("Added to Astral Gem Stash: " .. outName, "|cff80e090")

            -- Auto Fuse shows one summary popup at the end instead of one per fusion
            if PA.UI and PA.UI.GainPopup and not GF._autoFusing then
                PA.UI.GainPopup("Fusion complete: " .. outName,
                    "gems", { fontSize = 10 })
            end

            if GF.RequestInfo then GF.RequestInfo() end

            if PA.GemStash and PA.GemStash.DelayedRequestState then
                PA.GemStash.DelayedRequestState(400)
            end
        else
            local msg = FUSE_FAIL_MSG[status] or ("Fusion failed: " .. tostring(status))
            FlashStatus(msg, "|cffff6060")
        end
        if GF.OnAutoFuseResult then GF.OnAutoFuseResult(status, entry) end
    end
end

local function Split(str, sep)
    local t, i = {}, 1
    while true do
        local j = str:find(sep, i, true)
        if j then t[#t+1] = str:sub(i, j-1); i = j+1
        else      t[#t+1] = str:sub(i); break end
    end
    return t
end

local function FormatMoney(copper)
    copper = tonumber(copper) or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 and s == 0 and c == 0 then return string.format("%dg", g) end
    if g > 0 and c == 0              then return string.format("%dg %ds", g, s) end
    if g > 0                         then return string.format("%dg %ds %dc", g, s, c) end
    if s > 0 and c == 0              then return string.format("%ds", s) end
    if s > 0                         then return string.format("%ds %dc", s, c) end
    return string.format("%dc", c)
end

FlashStatus = function(text, color)
    GF.statusText = (color or "|cffffd000") .. text .. "|r"
    GF.statusUntil = time() + 4
    if frame and frame.status then
        frame.status:SetText(GF.statusText)
        frame.status:Show()
        if frame.summary then frame.summary:Hide() end   -- the status takes its place for 4s
    end
end

local function ScanBags()
    GF.bagsByEntry = {}
    if not (PA.GemStash and PA.GemStash.GetStock) then return end
    for entry, count in pairs(PA.GemStash.GetStock()) do
        if GF.catalog[entry] then
            GF.bagsByEntry[entry] = (GF.bagsByEntry[entry] or 0) + count
        end
    end
end

local function SubscribeToStashUpdates()
    if not (PA.GemStash and PA.GemStash.OnStockChanged) then return end
    PA.GemStash.OnStockChanged(function()
        ScanBags()
        if GF._RefreshGemList then GF._RefreshGemList() end
    end)
end

local PANEL_BORDER_COLOR = PA.UI.Tinted({ 0.165, 0.204, 0.400, 1 })

local W, H = 540, 720

local function FusionCostForTier(srcTier)
    if not srcTier or srcTier < 1 or srcTier > 7 then return 0 end
    local key = string.format("FUSION_COST_T%d_T%d_COPPER", srcTier, srcTier + 1)
    return tonumber(GF.info[key]) or 0
end

local function FuseEntry(entry)
    if AIO and AIO.Handle then
        AIO.Handle("AstralgemServer", "Fuse", entry)
    else
        Send("gem fuse " .. tostring(entry))
    end
    local cat = GF.catalog[entry]
    if cat then
        FlashStatus(string.format("Fusing 3× %s (T%d) for %s…",
            cat.family or "?", cat.tier or 0,
            FormatMoney(FusionCostForTier(cat.tier))), "|cffc8a951")
    end
end

-- ── Auto Fuse ───────────────────────────────────────────────────────
-- Optional: keeps fusing 3x same gem -> 1x next tier from the Gem Stash, lowest
-- tier first (so fresh results cascade upward), until nothing is left to fuse
-- without going past the chosen target tier. One request at a time: each waits
-- for FuseResult plus the stash refresh. Pauses in combat, pauses when gold runs
-- short, and skips tiers that aren't unlocked in the Astral Tree.

local AUTO_TIERS = {}
for t = 2, 8 do AUTO_TIERS[#AUTO_TIERS + 1] = { label = "T" .. t, tier = t } end

local auto = { busy = false, waiting = false, fused = 0, notFound = 0,
               wait = 0, acc = 0, noGold = false, blocked = {} }
local autoDriver = CreateFrame("Frame")
autoDriver:SetSize(1, 1)   -- sized so the 3.3.5 client ticks its OnUpdate
autoDriver:Hide()

local function AutoSettings()
    local s = PA.Settings or {}
    local maxTier = tonumber(s.autoFuseMaxTier) or 8
    return s.autoFuse == true, math.max(2, math.min(8, maxTier))
end

-- lowest-tier stack of 3+ whose fused result stays at or below maxTier
local function NextAutoFuse(maxTier)
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local best, bestTier
    for entry, count in pairs(stock) do
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        if tier and tier >= 1 and tier < maxTier and (count or 0) >= 3
           and cat.family and cat.family ~= ""
           and GF.info["GEM_FUSION_T" .. (tier + 1) .. "_ALLOWED"] == "1"
           and not auto.blocked[tier + 1]
           and (not bestTier or tier < bestTier or (tier == bestTier and entry < best)) then
            best, bestTier = entry, tier
        end
    end
    return best, bestTier
end

-- "Fuse all" runs through the same one-at-a-time loop, limited to the stacks that
-- were listed as ready when it was clicked; the gems it produces are not fused
-- further. nil when no Fuse all is running.
local batch

local function NextBatchFuse()
    local stock = (PA.GemStash and PA.GemStash.GetStock and PA.GemStash.GetStock()) or {}
    local best, bestTier
    for entry in pairs(batch) do
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        if tier and tier >= 1 and tier <= 7 and (stock[entry] or 0) >= 3
           and not auto.blocked[tier + 1]
           and (not bestTier or tier < bestTier or (tier == bestTier and entry < best)) then
            best, bestTier = entry, tier
        end
    end
    return best, bestTier
end

local function LoopName() return batch and "Fuse all" or "Auto Fuse" end

local function FinishAutoFuse(reason)
    local fused, name = auto.fused, LoopName()
    auto.busy, auto.waiting, auto.fused, auto.notFound = false, false, 0, 0
    batch = nil
    GF._autoFusing = false
    autoDriver:Hide()
    if fused > 0 and PA.UI and PA.UI.GainPopup then
        PA.UI.GainPopup(string.format("%s: %d fusion%s complete", name, fused,
            fused == 1 and "" or "s"), "gems")
    end
    if reason then FlashStatus(reason, "|cffffcc66") end
    if GF._RefreshGemList then GF._RefreshGemList() end
end

local function AutoFuseStep()
    local enabled, maxTier = AutoSettings()
    if not (enabled or batch) then
        FinishAutoFuse()
        return
    end
    if InCombatLockdown() then                   -- combat: PLAYER_REGEN_ENABLED restarts Auto Fuse
        FinishAutoFuse(batch and "Fuse all stopped: you are in combat." or nil)
        return
    end
    local entry, tier
    if batch then entry, tier = NextBatchFuse() else entry, tier = NextAutoFuse(maxTier) end
    if not entry then
        FinishAutoFuse()
        return
    end
    local cost = FusionCostForTier(tier)
    if cost > 0 and GetMoney() < cost then
        if not batch then auto.noGold = true end -- cleared by PLAYER_MONEY
        FinishAutoFuse(string.format("%s paused: T%d -> T%d needs %s.",
            LoopName(), tier, tier + 1, FormatMoney(cost)))
        return
    end
    auto.busy, auto.waiting = true, true
    GF._autoFusing = true
    auto.wait, auto.acc = 6.0, 0                 -- stop if the server never answers
    FuseEntry(entry)
    autoDriver:Show()
end

autoDriver:SetScript("OnUpdate", function(_, dt)
    auto.acc = auto.acc + dt
    if auto.acc < auto.wait then return end
    if auto.waiting then
        FinishAutoFuse(LoopName() .. " stopped: no reply from the server.")
        return
    end
    AutoFuseStep()
end)

function GF.OnAutoFuseResult(status, entry)
    if not auto.waiting then return end          -- a manual Fuse click
    auto.waiting = false
    if status == "OK" then
        auto.fused = auto.fused + 1
        auto.notFound = 0
        auto.wait, auto.acc = 1.2, 0             -- let the stash refresh land first
    elseif status == "NOT_FOUND" then
        -- stash counts were stale; refresh and retry once before giving up
        auto.notFound = auto.notFound + 1
        if auto.notFound >= 2 then FinishAutoFuse(); return end
        if PA.GemStash and PA.GemStash.RequestState then PA.GemStash.RequestState() end
        auto.wait, auto.acc = 2.0, 0
    elseif status == "NO_PERMISSION" then
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        if tier then auto.blocked[tier + 1] = true end
        auto.wait, auto.acc = 0.3, 0
    elseif status == "NOT_ENOUGH_GOLD" then
        if not batch then auto.noGold = true end
        FinishAutoFuse(LoopName() .. " paused: not enough gold.")
    else
        FinishAutoFuse(LoopName() .. " stopped: " .. tostring(status))
    end
end

function GF.FuseAll(entries)
    if auto.busy then
        FlashStatus("Fusions are already running. Wait for them to finish.", "|cffffcc66")
        return
    end
    batch = {}
    for _, entry in ipairs(entries or {}) do batch[entry] = true end
    if not next(batch) then batch = nil; return end
    wipe(auto.blocked)
    AutoFuseStep()
    if GF._RefreshGemList then GF._RefreshGemList() end
end

function GF.KickAutoFuse()
    local enabled = AutoSettings()
    if not enabled or auto.busy or auto.noGold or not next(GF.catalog) then return end
    AutoFuseStep()
end

local autoEvents = CreateFrame("Frame")
autoEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
autoEvents:RegisterEvent("PLAYER_MONEY")
autoEvents:RegisterEvent("CHAT_MSG_SYSTEM")
autoEvents:SetScript("OnEvent", function(_, event, msg)
    if event == "PLAYER_MONEY" then
        if not auto.busy then auto.noGold = false end
        GF.KickAutoFuse()
    elseif event == "PLAYER_REGEN_ENABLED" then
        GF.KickAutoFuse()
    elseif msg and msg:sub(1, 12) == "Astral Gem: " and (AutoSettings()) then
        -- a gem drop goes straight into the stash server-side: refresh counts,
        -- and the stock-changed callback below starts fusing
        if PA.GemStash and PA.GemStash.DelayedRequestState then
            PA.GemStash.DelayedRequestState(800)
        end
    end
end)

if PA.GemStash and PA.GemStash.OnStockChanged then
    PA.GemStash.OnStockChanged(function() GF.KickAutoFuse() end)
end

-- ── Fusion list ─────────────────────────────────────────────────────
-- Rows are grouped "Ready to fuse" → "In progress" → "Max tier". Only ready rows
-- get a button, and the button carries the gold cost. Colours that must survive
-- Theme.lua's vivid-text pass (it whitens every FontString without a |c code) are
-- written as inline colour codes.

local FONT  = "Fonts\\FRIZQT__.TTF"
local SOLID = "Interface\\Buttons\\WHITE8X8"

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_DIM   = "|cffaab0d4"
local HEX_BTN_GOLD = "|cffffe39a"   -- outline gold buttons (row Fuse)
local HEX_BAD   = "|cffff9a8f"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_BLUE  = "|cff4fc3f7"
local HEX_WARN  = "|cffffcc66"

local PIP_EMPTY    = PA.UI.Tinted({ 0.16, 0.20, 0.37 })
local PIP_PROGRESS = PA.UI.Tinted({ 0.31, 0.76, 0.97 })
local PIP_READY    = { 1.00, 0.85, 0.44 }

local TIER_HEX = {
    [1] = "|cffffffff", [2] = "|cff7cf26a", [3] = "|cff7fb4ff", [4] = "|cffd395ff",
    [5] = "|cffff8c26", [6] = "|cfff2d98c", [7] = "|cffff738c", [8] = "|cffff4040",
}

local TRIGGER_LABEL = {
    [0] = "Proc on Hit", [1] = "Proc on Cast", [2] = "Proc on Heal",
    [3] = "Proc on Struck", [4] = "Proc on Crit", [5] = "DoT/HoT",
}

local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return FormatMoney(copper)
end

-- An unknown flag counts as unlocked: the server still refuses with NO_PERMISSION.
local function FusionUnlocked(targetTier)
    local v = GF.info["GEM_FUSION_T" .. targetTier .. "_ALLOWED"]
    return v == nil or v == "1"
end

-- "[T1] Yellow Astral Gem of Adaptive Swarm" -> "Adaptive Swarm", "Yellow"
local function GemDisplayName(entry, cat)
    local raw = (select(1, GetItemInfo(entry))) or (cat and cat.name) or ""
    raw = PA.CleanGemTierMarker(raw)
    raw = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    raw = raw:gsub("^%[T%d%]%s*", "")
    local color, suffix = raw:match("^(%a+) Astral Gem of (.+)$")
    if suffix then return suffix, color end
    if raw ~= "" then return raw end
    return (cat and cat.family) or ("Gem " .. tostring(entry))
end
GF.GemDisplayName = GemDisplayName   -- shared with the Gem Stash tab

local function ShowFuseTooltip(owner, d)
    if not d or not d.cost then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(string.format("Fuse 3× T%d into 1× T%d", d.tier, d.tier + 1), 1, 1, 1)
    GameTooltip:AddLine(d.title, 0.94, 0.85, 0.42)
    GameTooltip:AddLine("Cost per fusion: " .. FormatMoney(d.cost), 1, 1, 1)
    if d.fusions > 1 then
        GameTooltip:AddLine(string.format("Enough copies for %d fusions. Fuse all runs them in a row.",
            d.fusions), 0.62, 0.64, 0.78, true)
    end
    if not d.unlocked then
        GameTooltip:AddLine(string.format("Fusion into T%d is locked. Unlock it in the Astral Tree.",
            d.tier + 1), 1, 0.45, 0.45, true)
    elseif not d.affordable then
        GameTooltip:AddLine("Not enough gold.", 1, 0.45, 0.45)
    elseif auto.busy then
        GameTooltip:AddLine("Wait for the current fusions to finish.", 1, 0.8, 0.4)
    end
    GameTooltip:Show()
end

-- Lazy row-pool: WoW 3.3.5 cannot destroy frames, so rows are recycled
local function GetGemRow(host, index)
    host._rowPool = host._rowPool or {}
    if host._rowPool[index] then return host._rowPool[index] end

    local row = CreateFrame("Button", nil, host)
    row:RegisterForClicks("LeftButtonUp")
    PA.UI.MakeRowChrome(row)

    local readyBg = row:CreateTexture(nil, "BACKGROUND")
    readyBg:SetTexture(SOLID)
    readyBg:SetAllPoints(row)
    readyBg:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    row.readyBg = readyBg

    local readyBar = row:CreateTexture(nil, "ARTWORK")
    readyBar:SetTexture(SOLID)
    readyBar:SetVertexColor(0.886, 0.753, 0.384, 1)
    readyBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    readyBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    readyBar:SetWidth(3)
    row.readyBar = readyBar

    local altBg = row:CreateTexture(nil, "BACKGROUND")
    altBg:SetTexture(SOLID)
    altBg:SetAllPoints(row)
    altBg:SetVertexColor(1, 1, 1, 0.022)
    row.altBg = altBg

    local divider = row:CreateTexture(nil, "BORDER")
    divider:SetTexture(SOLID)
    divider:SetVertexColor(PA.UI.Tint(0.47, 0.55, 0.86, 0.10))
    divider:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 1)
    divider:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 1)
    divider:SetHeight(1)
    row.divider = divider

    row.iconFrame = PA.UI.MakeIconFrame(row, { size = 30 })
    row.iconFrame:SetPoint("LEFT", row, "LEFT", 8, 0)

    row.btn = PA.UI.MakeButton(row, "", { w = 130, h = 26, variant = "gold" })
    row.btn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.btn:SetScript("OnClick", function()
        local d = row.data
        if d and d.canFuse and not auto.busy then FuseEntry(d.entry) end
    end)
    row.btn:HookScript("OnEnter", function(self) ShowFuseTooltip(self, row.data) end)
    row.btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- shown in the button's place when there is nothing to click
    row.note = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.note, 12)
    row.note:SetPoint("CENTER", row.btn, "CENTER", 0, 0)

    row.result = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.result, 12)
    row.result:SetPoint("RIGHT", row.btn, "LEFT", -14, 0)
    row.result:SetWidth(64)
    row.result:SetJustifyH("RIGHT")

    row.count = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.count, 12)
    row.count:SetPoint("RIGHT", row.result, "LEFT", -14, 0)
    row.count:SetWidth(40)
    row.count:SetJustifyH("LEFT")

    row.pips = {}
    local anchor = row.count
    for i = 3, 1, -1 do
        local pip = row:CreateTexture(nil, "ARTWORK")
        pip:SetTexture(SOLID)
        pip:SetSize(8, 8)
        pip:SetPoint("RIGHT", anchor, "LEFT", i == 3 and -6 or -3, 0)
        row.pips[i] = pip
        anchor = pip
    end

    row.title = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.title, 14)
    row.title:SetPoint("BOTTOMLEFT", row.iconFrame, "RIGHT", 10, 1)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(row.sub, 11)
    row.sub:SetPoint("TOPLEFT", row.iconFrame, "RIGHT", 10, -3)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row:HookScript("OnEnter", function(self)
        if not self.data then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. self.data.entry)
        GameTooltip:AddLine("Shift-click to link in chat", 0.62, 0.64, 0.78)
        GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.data and IsModifiedClick("CHATLINK") then
            PA.InsertChatLink(select(2, GetItemInfo(self.data.entry)))
        end
    end)

    host._rowPool[index] = row
    return row
end

local function GetGroupHeader(host, index)
    host._headerPool = host._headerPool or {}
    local h = host._headerPool[index]
    if not h then
        h = PA.UI.MakeSectionLabel(host, "")
        PA.UI.SetTextFont(h.label, 12)
        host._headerPool[index] = h
    end
    return h
end

local ROW_RESERVED_W = 48 + 316   -- icon column + pips/count/result/button columns

-- groupIndex: position inside its group (1 = first row under the header)
local function PaintGemRow(row, d, kind, rowW, groupIndex)
    row.data = d
    if groupIndex % 2 == 0 then row.altBg:Show() else row.altBg:Hide() end
    if groupIndex > 1 then row.divider:Show() else row.divider:Hide() end
    local _, _, quality, _, _, _, _, _, _, texture = GetItemInfo(d.entry)
    row.iconFrame:SetTexture(texture or "Interface\\Icons\\INV_Misc_Gem_Variety_01")
    row.iconFrame:SetQuality(quality or d.quality or 2)

    local textW = math.max(80, rowW - ROW_RESERVED_W)
    row.title:SetWidth(textW)
    row.sub:SetWidth(textW)
    row.title:SetText(d.title)
    local sub = (TIER_HEX[d.tier] or "|cffffffff") .. "T" .. d.tier .. "|r"
    local trigger = TRIGGER_LABEL[d.eventType]
    if trigger then sub = sub .. HEX_MUTED .. "  ·  " .. trigger .. "|r" end
    row.sub:SetText(sub)

    local isReady = kind == "ready"
    if isReady then row.readyBg:Show(); row.readyBar:Show()   -- no SetShown in 3.3.5
    else row.readyBg:Hide(); row.readyBar:Hide() end

    if kind == "max" then
        for i = 1, 3 do row.pips[i]:Hide() end
        row.count:SetText(HEX_MUTED .. "×" .. d.count .. "|r")
        row.result:SetText("")
    else
        local filled = math.min(3, d.count)
        local col = isReady and PIP_READY or PIP_PROGRESS
        for i = 1, 3 do
            local c = (i <= filled) and col or PIP_EMPTY
            row.pips[i]:SetVertexColor(c[1], c[2], c[3], 1)
            row.pips[i]:Show()
        end
        local nextHex = TIER_HEX[d.tier + 1] or "|cffffffff"
        if isReady then
            row.count:SetText(HEX_GOLD .. "×" .. d.count .. "|r")
            row.result:SetText(nextHex .. d.fusions .. "× T" .. (d.tier + 1) .. "|r")
        else
            row.count:SetText(HEX_MUTED .. d.count .. "/3|r")
            row.result:SetText(HEX_DIM .. "T" .. (d.tier + 1) .. "|r")
        end
    end

    if isReady then
        row.note:Hide()
        row.btn:Show()
        local costText = FormatMoney(d.cost)
        if not d.unlocked then
            row.btn:SetDisabledLook(true)
            row.btn:SetLabel(HEX_BAD .. "Locked|r")
        elseif not d.affordable then
            row.btn:SetDisabledLook(true)
            row.btn:SetLabel(HEX_BAD .. "Fuse · " .. costText .. "|r")
        elseif auto.busy then
            row.btn:SetDisabledLook(true)
            row.btn:SetLabel(HEX_DIM .. "Fuse · " .. costText .. "|r")
        else
            row.btn:SetDisabledLook(false)
            row.btn:SetLabel(HEX_BTN_GOLD .. "Fuse · " .. costText .. "|r")
        end
    else
        row.btn:Hide()
        row.note:Show()
        if kind == "max" then
            row.note:SetText(HEX_MUTED .. "Top tier|r")
        else
            row.note:SetText(HEX_MUTED .. (3 - d.count) .. " more needed|r")
        end
    end
    row:Show()
end

local TIER_FILTERS = {
    { label = "All", match = function(c) return true end },
    { label = "T1",  match = function(c) return c.tier == 1 end },
    { label = "T2",  match = function(c) return c.tier == 2 end },
    { label = "T3",  match = function(c) return c.tier == 3 end },
    { label = "T4",  match = function(c) return c.tier == 4 end },
    { label = "T5",  match = function(c) return c.tier == 5 end },
    { label = "T6",  match = function(c) return c.tier == 6 end },
    { label = "T7",  match = function(c) return c.tier == 7 end },
    { label = "T8",  match = function(c) return c.tier == 8 end },
}

local EVENT_FILTERS = {
    { label = "All",            match = function(c) return true end },
    { label = "Proc on Hit",    match = function(c) return c.eventType == 0 end },
    { label = "Proc on Cast",   match = function(c) return c.eventType == 1 end },
    { label = "Proc on Heal",   match = function(c) return c.eventType == 2 end },
    { label = "Proc on Struck", match = function(c) return c.eventType == 3 end },
}

local fuseTier  = 1      -- index into TIER_FILTERS
local fuseEvent = 1      -- index into EVENT_FILTERS
local fuseName  = ""
local fuseReadyOnly = false

local function PassesSideFilters(entry, cat)
    local ef = EVENT_FILTERS[fuseEvent]
    if ef and not ef.match(cat) then return false end
    if fuseName ~= "" then
        local raw = (cat.name ~= "" and cat.name) or (select(1, GetItemInfo(entry))) or ""
        raw = raw:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if not raw:lower():find(fuseName, 1, true) then return false end
    end
    return true
end

local function SortRows(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    local ta, tb = a.title:lower(), b.title:lower()
    if ta ~= tb then return ta < tb end
    return a.entry < b.entry
end

local function RefreshGemList(panel)
    panel = panel or (frame and frame.gemListPanel)
    if not panel then return end
    local host = panel.child or panel
    host._rowPool = host._rowPool or {}
    host._headerPool = host._headerPool or {}

    -- per-tier totals ignore the tier filter so every tier chip keeps its count
    local tierStats = {}
    for t = 1, 8 do tierStats[t] = { gems = 0, ready = 0 } end
    local ready, progress, maxed = {}, {}, {}
    local batchEntries, batchFusions, batchCost = {}, 0, 0
    local tf = TIER_FILTERS[fuseTier]
    local money = GetMoney()

    for entry, count in pairs(GF.bagsByEntry) do
        local cat  = GF.catalog[entry]
        local tier = cat and tonumber(cat.tier)
        count = count or 0
        if tier and tier >= 1 and tier <= 8 and count > 0 and PassesSideFilters(entry, cat) then
            local fusable = tier <= 7 and count >= 3
            local st = tierStats[tier]
            st.gems = st.gems + count
            if fusable then st.ready = st.ready + 1 end

            if not tf or tf.match(cat) then
                local title, color = GemDisplayName(entry, cat)
                local d = { entry = entry, count = count, tier = tier, title = title,
                            color = color, eventType = cat.eventType, quality = cat.quality }
                if tier >= 8 then
                    if not fuseReadyOnly then maxed[#maxed + 1] = d end
                elseif fusable then
                    d.cost       = FusionCostForTier(tier)
                    d.fusions    = math.floor(count / 3)
                    d.unlocked   = FusionUnlocked(tier + 1)
                    d.affordable = money >= d.cost
                    d.canFuse    = d.unlocked and d.affordable
                    ready[#ready + 1] = d
                    if d.unlocked then
                        batchEntries[#batchEntries + 1] = entry
                        batchFusions = batchFusions + d.fusions
                        batchCost    = batchCost + d.fusions * d.cost
                    end
                elseif not fuseReadyOnly then
                    progress[#progress + 1] = d
                end
            end
        end
    end
    table.sort(ready, SortRows)
    table.sort(progress, SortRows)
    table.sort(maxed, SortRows)

    if frame and frame.UpdateTierChips then frame:UpdateTierChips(tierStats) end
    if frame and frame.UpdateActionBar then frame:UpdateActionBar(batchEntries, batchFusions, batchCost) end

    if not host._emptyText then
        host._emptyText = host:CreateFontString(nil, "OVERLAY")
        PA.UI.SetTextFont(host._emptyText, 13)
        host._emptyText:SetPoint("TOPLEFT", host, "TOPLEFT", 12, -12)
        host._emptyText:SetPoint("RIGHT", host, "RIGHT", -12, 0)
        host._emptyText:SetJustifyH("LEFT")
    end

    local hostW = panel.scroll and panel.scroll:GetWidth() or host:GetWidth()
    if not hostW or hostW <= 0 then hostW = 520 end
    host:SetWidth(hostW)
    local rowW = hostW - 8

    local rowH, headerH = 40, 24
    local y, rowIdx, hdrIdx = -2, 0, 0

    local function AddHeader(text, n, gold)
        hdrIdx = hdrIdx + 1
        local h = GetGroupHeader(host, hdrIdx)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", host, "TOPLEFT", 6, y - 6)
        h:SetWidth(rowW - 4)
        h.label:SetText(text .. "  " .. HEX_MUTED .. n .. "|r")
        if h.line then
            if gold then h.line:SetVertexColor(0.84, 0.71, 0.35, 0.35)
            else         h.line:SetVertexColor(PA.UI.Tint(0.47, 0.55, 0.86, 0.30)) end
        end
        h:Show()
        y = y - headerH
    end
    local function AddRows(list, kind)
        for i, d in ipairs(list) do
            rowIdx = rowIdx + 1
            local row = GetGemRow(host, rowIdx)
            row:SetSize(rowW, rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", host, "TOPLEFT", 4, y)
            PaintGemRow(row, d, kind, rowW, i)
            y = y - (rowH + 2)
        end
    end

    if #ready + #progress + #maxed == 0 then
        if fuseReadyOnly then
            host._emptyText:SetText(HEX_MUTED .. "Nothing is ready to fuse with these filters. "
                .. "A fusion needs 3 copies of the same T1-T7 gem.|r")
        elseif next(GF.bagsByEntry) then
            host._emptyText:SetText(HEX_MUTED .. "No gems match these filters.|r")
        else
            host._emptyText:SetText(HEX_MUTED .. "Your Gem Stash is empty. Astral Gems drop from "
                .. "enemies and go straight into the stash.|r")
        end
        host._emptyText:Show()
    else
        host._emptyText:Hide()
        if #ready > 0 then
            AddHeader(HEX_GOLD .. "READY TO FUSE|r", #ready, true)
            AddRows(ready, "ready")
        end
        if #progress > 0 then
            AddHeader("IN PROGRESS", #progress)
            AddRows(progress, "progress")
        end
        if #maxed > 0 then
            AddHeader("MAX TIER", #maxed)
            AddRows(maxed, "max")
        end
    end

    for i = rowIdx + 1, #host._rowPool do
        host._rowPool[i].data = nil
        host._rowPool[i]:Hide()
    end
    for i = hdrIdx + 1, #host._headerPool do host._headerPool[i]:Hide() end

    host:SetHeight(math.max(60, -y + 8))
    if panel.ClipRowMouse then panel:ClipRowMouse() end
end

GF._RefreshGemList = function()
    if frame and frame.gemListPanel and frame:IsShown() then
        RefreshGemList(frame.gemListPanel)
    end
end

local function Refresh()
    if not frame or not frame:IsShown() then return end
    if frame.UpdateHeader then frame:UpdateHeader() end
end

local function InitDropdown(dropdown, list, getCurrentIdx, onChoose)
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local cur = getCurrentIdx()
        for i, item in ipairs(list) do
            local info   = UIDropDownMenu_CreateInfo()
            info.text    = item.label
            info.checked = (i == cur)
            info.func    = function()
                onChoose(i)
                UIDropDownMenu_SetSelectedID(dropdown, i)
                UIDropDownMenu_SetText(dropdown, list[i].label)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local cur = getCurrentIdx()
    UIDropDownMenu_SetSelectedID(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, list[cur].label)
end

local function CreateFusionFrame(embedParent)
    if not GF._stashSubscribed then
        GF._stashSubscribed = true
        SubscribeToStashUpdates()
    end

    local f = CreateFrame("Frame", "PAGemFusionFrame", embedParent or UIParent)
    if embedParent then
        f:SetAllPoints(embedParent)
        f:SetFrameLevel(embedParent:GetFrameLevel() + 1)
        -- navy ground so the chips and list read as layers above it
        local ground = f:CreateTexture(nil, "BACKGROUND")
        ground:SetTexture(SOLID)
        ground:SetAllPoints(f)
        ground:SetVertexColor(PA.UI.Tint(0.031, 0.047, 0.133, 0.85))
    else
        f:SetSize(W, H)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:SetClampedToScreen(true)
        f:SetFrameStrata("HIGH")
        f:Hide()

        PA.UI.AstralBackdrop(f, { thin = false })
        PA.UI.CosmicCorners(f)
        f:SetBackdropColor(PA.UI.Nav.deep[1], PA.UI.Nav.deep[2],
                           PA.UI.Nav.deep[3], 0.97)
        f:SetBackdropBorderColor(PA.UI.Nav.edgeMid[1], PA.UI.Nav.edgeMid[2],
                                 PA.UI.Nav.edgeMid[3], 1)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f.title:SetPoint("TOP", f, "TOP", 0, -16)
        f.title:SetText("Astral Gem Fusion")
        f.title:SetTextColor(PA.UI.Color.textTitle[1], PA.UI.Color.textTitle[2],
                             PA.UI.Color.textTitle[3])

        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sub:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
        sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
        sub:SetText("Combine 3x same-family same-tier gems into 1x of the next tier (T1->T8 chain).")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        PA.UI.CosmicCloseButton(closeBtn)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end

    local W = embedParent and math.max(568, embedParent:GetWidth() or 0) or W
    local top = embedParent and -8 or -58
    local SIDE = 10

    -- ── Header: Auto Fuse state on the left, gold and help on the right ──
    local autoCheck = CreateFrame("CheckButton", "PAGemAutoFuseCheck", f,
        "InterfaceOptionsCheckButtonTemplate")
    autoCheck:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE - 4, top + 2)
    local autoText = _G[autoCheck:GetName() .. "Text"]
    autoText:SetText("Auto Fuse")
    PA.UI.SetTextFont(autoText, 13)
    autoCheck.tooltipText = "Automatically fuse 3 of the same gem from your Gem Stash into the next tier, "
        .. "lowest tiers first, up to the tier chosen here. Each fusion costs gold; "
        .. "pauses in combat or when gold runs short."
    autoCheck:SetChecked(AutoSettings())
    autoCheck:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if PA.SaveSetting then PA.SaveSetting("autoFuse", on) end
        if on then
            wipe(auto.blocked)
            auto.noGold = false
            local _, maxTier = AutoSettings()
            FlashStatus("Auto Fuse on: fusing up to T" .. maxTier .. ".", "|cff80e090")
            GF.KickAutoFuse()
        else
            FlashStatus("Auto Fuse off.", HEX_WARN)
        end
        f:UpdateHeader()
    end)
    f.autoCheck = autoCheck

    local upToLbl = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(upToLbl, 12)
    upToLbl:SetPoint("LEFT", autoText, "RIGHT", 10, 0)
    upToLbl:SetText(HEX_MUTED .. "up to|r")

    local autoDd = CreateFrame("Frame", "PAGemAutoFuseTierDD", f, "UIDropDownMenuTemplate")
    autoDd:SetPoint("LEFT", upToLbl, "RIGHT", -12, -3)
    UIDropDownMenu_SetWidth(autoDd, 50)
    InitDropdown(autoDd, AUTO_TIERS,
        function() local _, maxTier = AutoSettings(); return maxTier - 1 end,   -- AUTO_TIERS[1] = T2
        function(i)
            if PA.SaveSetting then PA.SaveSetting("autoFuseMaxTier", AUTO_TIERS[i].tier) end
            wipe(auto.blocked)
            if AutoSettings() then
                FlashStatus("Auto Fuse: fusing up to T" .. AUTO_TIERS[i].tier .. ".", "|cff80e090")
            end
            GF.KickAutoFuse()
        end)
    f.autoTierDd = autoDd

    f.autoStatus = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.autoStatus, 12)
    f.autoStatus:SetPoint("LEFT", autoDd, "RIGHT", -6, 3)

    local helpBtn = PA.UI.MakeButton(f, "?", { w = 24, h = 24, variant = "secondary" })
    helpBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, top)
    helpBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText("Gem Fusion", 1, 1, 1)
        GameTooltip:AddLine("Three copies of the same gem fuse into one gem of the next tier.",
            0.8, 0.8, 0.85, true)
        GameTooltip:AddLine(" ")
        local pct = tonumber(GF.info.GEM_NORMAL_CHANCE_PCT or 0) or 0
        GameTooltip:AddDoubleLine("Gem drop chance (T1)", string.format("%.2f%%", pct),
            0.8, 0.8, 0.85, 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Fusion cost", 0.94, 0.85, 0.42)
        for t = 1, 7 do
            local unlocked = FusionUnlocked(t + 1)
            GameTooltip:AddDoubleLine(string.format("T%d to T%d", t, t + 1),
                unlocked and FormatMoney(FusionCostForTier(t)) or "Locked",
                0.8, 0.8, 0.85, 1, unlocked and 1 or 0.45, unlocked and 1 or 0.45)
        end
        GameTooltip:Show()
    end)
    helpBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    f.goldText = f:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.goldText, 13)
    f.goldText:SetPoint("RIGHT", helpBtn, "LEFT", -10, 0)

    function f:UpdateHeader()
        self.goldText:SetText(Money(GetMoney()))
        local enabled = AutoSettings()
        local text
        if auto.busy then
            text = HEX_BLUE .. (batch and "Fusing all ready gems..." or "Fusing...") .. "|r"
        elseif not enabled then
            text = HEX_MUTED .. "Off|r"
        elseif auto.noGold then
            text = HEX_BAD .. "Paused: not enough gold|r"
        elseif InCombatLockdown() then
            text = HEX_WARN .. "Paused: in combat|r"
        else
            text = HEX_GOOD .. "On, waiting for gems|r"
        end
        self.autoStatus:SetText(text)
    end

    -- ── Filter chips ──
    local MakeChip = PA.UI.MakeFilterChip

    local tierRowY = top - 34
    local chipGap = 4
    local tierChipW = math.floor((W - 2 * SIDE - chipGap * 8) / 9)
    f.tierChips = {}
    for i, tfil in ipairs(TIER_FILTERS) do
        local idx = i
        local chip = MakeChip(f, tierChipW, tfil.label, function()
            fuseTier = idx
            for j, c in ipairs(f.tierChips) do c:SetActive(j == idx) end
            GF._RefreshGemList()
        end)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE + (i - 1) * (tierChipW + chipGap), tierRowY)
        chip:HookScript("OnEnter", function(self)
            local st = self._stats
            if not st then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(idx == 1 and "All tiers" or ("Tier " .. (idx - 1)), 1, 1, 1)
            GameTooltip:AddLine(string.format("%d gems in the stash, %d stack%s ready to fuse",
                st.gems, st.ready, st.ready == 1 and "" or "s"), 0.8, 0.8, 0.85)
            local t = idx - 1
            if t >= 1 and t <= 7 then
                if FusionUnlocked(t + 1) then
                    GameTooltip:AddLine(string.format("Fusing into T%d costs %s.", t + 1,
                        FormatMoney(FusionCostForTier(t))), 0.94, 0.85, 0.42)
                else
                    GameTooltip:AddLine(string.format("Fusion into T%d is locked. Unlock it in the Astral Tree.",
                        t + 1), 1, 0.45, 0.45, true)
                end
            end
            GameTooltip:Show()
        end)
        chip:SetActive(i == fuseTier)
        f.tierChips[i] = chip
    end

    function f:UpdateTierChips(tierStats)
        local all = { gems = 0, ready = 0 }
        for t = 1, 8 do
            all.gems  = all.gems  + tierStats[t].gems
            all.ready = all.ready + tierStats[t].ready
        end
        for i, chip in ipairs(self.tierChips) do
            local t  = i - 1
            local st = (t == 0) and all or tierStats[t]
            chip._stats = st
            local name = TIER_FILTERS[i].label
            if t >= 2 and not FusionUnlocked(t) then name = HEX_BAD .. name .. "|r" end
            local text = name .. " " .. HEX_MUTED .. st.gems .. "|r"
            if st.ready > 0 then text = text .. " " .. HEX_GOLD .. "+" .. st.ready .. "|r" end
            chip.text:SetText(text)
        end
    end

    local trigRowY = tierRowY - 30
    local TRIGGER_CHIPS = { "Any trigger", "Hit", "Cast", "Heal", "Struck" }   -- same order as EVENT_FILTERS
    f.trigChips = {}
    local x = SIDE
    for i, label in ipairs(TRIGGER_CHIPS) do
        local idx = i
        local w = (i == 1) and 84 or 58
        local chip = MakeChip(f, w, label, function()
            fuseEvent = idx
            for j, c in ipairs(f.trigChips) do c:SetActive(j == idx) end
            GF._RefreshGemList()
        end)
        chip:SetPoint("TOPLEFT", f, "TOPLEFT", x, trigRowY)
        chip:SetActive(i == fuseEvent)
        f.trigChips[i] = chip
        x = x + w + chipGap
    end

    f.readyChip = MakeChip(f, 92, "Ready only", function(self)
        fuseReadyOnly = not fuseReadyOnly
        self:SetActive(fuseReadyOnly)
        GF._RefreshGemList()
    end)
    f.readyChip:SetPoint("TOPLEFT", f, "TOPLEFT", x + 8, trigRowY)
    f.readyChip:SetActive(fuseReadyOnly)

    f.fuseSearchBox = PA.UI.MakeSearchBox(f, {
        width       = 160,
        height      = 24,
        placeholder = "Search gems…",
        onChanged   = function(text)
            fuseName = (text or ""):lower()
            if GF._RefreshGemList then GF._RefreshGemList() end
        end,
    })
    PA.UI.SetTextFont(f.fuseSearchBox.edit, 12)
    PA.UI.StyleFilterSearch(f.fuseSearchBox)
    f.fuseSearchBox:SetPoint("LEFT", f.readyChip, "RIGHT", 8, 0)
    f.fuseSearchBox:SetPoint("RIGHT", f, "RIGHT", -SIDE, 0)

    -- ── Action bar: what "Fuse all" will do, and status messages ──
    local bar = CreateFrame("Frame", nil, f)
    bar:SetHeight(38)
    bar:SetPoint("TOPLEFT",  f, "TOPLEFT",  SIDE,  trigRowY - 32)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, trigRowY - 32)
    PA.UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
    bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    f.actionBar = bar

    f.fuseAllBtn = PA.UI.MakeButton(bar, "Fuse all", { w = 170, h = 26, variant = "gold" })
    f.fuseAllBtn:SetPoint("RIGHT", bar, "RIGHT", -7, 0)
    f.fuseAllBtn:SetScript("OnClick", function()
        if f._batch and #f._batch > 0 then GF.FuseAll(f._batch) end
    end)

    f.summary = bar:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.summary, 13)
    f.summary:SetPoint("LEFT", bar, "LEFT", 12, 0)
    f.summary:SetPoint("RIGHT", f.fuseAllBtn, "LEFT", -10, 0)
    f.summary:SetJustifyH("LEFT")
    f.summary:SetWordWrap(false)

    f.status = bar:CreateFontString(nil, "OVERLAY")
    PA.UI.SetTextFont(f.status, 13)
    f.status:SetAllPoints(f.summary)
    f.status:SetJustifyH("LEFT")
    f.status:SetWordWrap(false)
    f.status:Hide()

    function f:UpdateActionBar(entries, fusions, cost)
        self._batch = entries
        local btn = self.fuseAllBtn
        if auto.busy then
            self.summary:SetText(HEX_BLUE .. (batch and "Fusing all ready gems..." or "Auto Fuse is running...") .. "|r")
            btn:SetLabel("Fusing...")
            btn:SetDisabledLook(true)
        elseif fusions == 0 then
            self.summary:SetText(HEX_MUTED .. "Nothing to fuse yet. A fusion needs 3 copies of the same gem.|r")
            btn:SetLabel("Fuse all")
            btn:SetDisabledLook(true)
        else
            local text = HEX_GOLD .. fusions .. (fusions == 1 and " fusion" or " fusions") .. " ready|r"
                .. HEX_MUTED .. "  ·  total|r " .. FormatMoney(cost)
            local money = GetMoney()
            if money < cost then
                text = text .. HEX_BAD .. "  ·  you have " .. FormatMoney(money) .. "|r"
            end
            self.summary:SetText(text)
            btn:SetLabel(HEX_BTN_GOLD .. "Fuse all · " .. FormatMoney(cost) .. "|r")
            btn:SetDisabledLook(false)
        end
    end

    -- ── Gem list ──
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT",     bar, "BOTTOMLEFT",  0, -8)
    panel:SetPoint("BOTTOMRIGHT", f,   "BOTTOMRIGHT", -SIDE, 10)
    PA.UI.AstralBackdrop(panel, { thin = true })
    -- dark grey list (the gold rows read warm on it), whatever the Global UI color
    panel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)
    panel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    panel.__paBackdrop = true

    panel.scroll = CreateFrame("ScrollFrame", "PAGemFusionListScroll", panel,
                               "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT",     panel, "TOPLEFT",     4, -4)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)

    panel.child = CreateFrame("Frame", nil, panel.scroll)
    panel.child:SetSize(panel.scroll:GetWidth() > 0 and panel.scroll:GetWidth() or 520, 100)
    panel.scroll:SetScrollChild(panel.child)

    -- A 3.3.5 ScrollFrame clips drawing but not the mouse: rows scrolled out of
    -- view still catch hover and clicks over the chips and the action bar. Only
    -- rows fully inside the visible area take the mouse.
    function panel:ClipRowMouse()
        local viewTop, viewBottom = self.scroll:GetTop(), self.scroll:GetBottom()
        if not (viewTop and viewBottom) then return end
        for _, row in ipairs(self.child._rowPool or {}) do
            local rt, rb = row:GetTop(), row:GetBottom()
            local inside = row:IsShown() and rt and rb and rt <= viewTop + 1 and rb >= viewBottom - 1
            row:EnableMouse(inside and true or false)
            row.btn:EnableMouse(inside and true or false)
        end
    end
    panel.scroll:HookScript("OnVerticalScroll", function() panel:ClipRowMouse() end)
    panel.scroll:HookScript("OnSizeChanged",    function() panel:ClipRowMouse() end)

    f.gemListPanel = panel

    f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._t > 0.5 then
            self._t = 0
            if GF.statusUntil and time() >= GF.statusUntil and self.status:IsShown() then
                self.status:Hide()
                self.summary:Show()
            end
            self:UpdateHeader()
            -- Auto Fuse can start from outside this frame; repaint buttons when it does
            if self._lastBusy ~= auto.busy then
                self._lastBusy = auto.busy
                RefreshGemList(self.gemListPanel)
            end
        end
        self._pollT = (self._pollT or 0) + elapsed
        if self._pollT >= 0.5 then
            self._pollT = 0
            if PA.GemStash and PA.GemStash.RequestState then
                PA.GemStash.RequestState()
            end
        end
    end)

    f:SetScript("OnShow", function()
        GF.RequestInfo()
        Refresh()
    end)

    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_MONEY")
    f:HookScript("OnEvent", function(self, event)
        if not self:IsShown() then return end
        if event == "BAG_UPDATE_DELAYED" then
            ScanBags()
            RefreshGemList(self.gemListPanel)
            Refresh()
        elseif event == "PLAYER_MONEY" then
            RefreshGemList(self.gemListPanel)   -- affordability on every Fuse button
            Refresh()
        end
    end)

    frame = f
end

local function BuildGemFusionTab(panel)
    if not frame then CreateFusionFrame(panel) end
    panel:SetScript("OnShow", function()
        GF.RequestInfo()
        ScanBags()
        if frame and frame.gemListPanel then
            RefreshGemList(frame.gemListPanel)
        end
        Refresh()
    end)
end

local function ToggleFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "GemFusion" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("GemFusion")
        if mf._tabBar then mf._tabBar:SelectTab("GemFusion") end
    end
end

GF._refresh_hooks = {
    ScanBags       = ScanBags,
    RefreshGemList = RefreshGemList,
    Refresh        = Refresh,
}

local infoEvt = CreateFrame("Frame")
infoEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
infoEvt:SetScript("OnEvent", function()
    if GF._refresh_hooks and GF._refresh_hooks.RefreshGemList then
        pcall(GF._refresh_hooks.RefreshGemList)
    end
end)

PA:RegisterModule("GemFusion", "Gem Fusion", ToggleFrame, {
    subtitle = "Combine 3× same-family same-tier gems into 1× of the next tier.",
})
PA:RegisterTabContent("GemFusion", BuildGemFusionTab)

do
    local mods = PA.modules
    if type(mods) == "table" and #mods > 0 then
        local gIdx, anchorIdx
        for i, m in ipairs(mods) do
            if m.name == "GemFusion" then gIdx = i end
            if m.name == "AstralGems" or m.name == "gems" or m.name == "astralgems" then
                anchorIdx = i
            end
        end
        if gIdx and anchorIdx and gIdx ~= anchorIdx + 1 then
            local entry = table.remove(mods, gIdx)
            local insertAt = anchorIdx + (gIdx < anchorIdx and 0 or 1)
            table.insert(mods, insertAt, entry)
        end
    end
end
