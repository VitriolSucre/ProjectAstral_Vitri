local PA = ProjectAstral
if not PA then return end
local UI = PA.UI
local D = PA.disenchant
if not D then return end

-- Disenchant tab (Gems section): every bag item the Astral Table would take, as a
-- grid you click to select, then one button sends them all (9 per batch, the
-- server's limit; the next batch goes when the previous one ends). Items saved in
-- an equipment set are listed apart and can't be picked. Eligibility is the same
-- check as the table's Auto Import (D.Classify in AstralDisenchant.lua). A max
-- vendor price (gold + silver) moves anything worth more to a "To sell" line,
-- which the Sell button sells while a merchant window is open.
-- Colours that must survive Theme.lua's vivid-text pass are inline |c codes.

local SOLID = "Interface\\Buttons\\WHITE8X8"
local BTN, GAP = 40, 6
local BATCH_MAX = 9
local SIDE = 10

local HEX_GOLD  = "|cffffd970"
local HEX_MUTED = "|cffdcdff0"
local HEX_GOOD  = "|cff7fe0a0"
local HEX_WARN  = "|cffffcc66"
local HEX_BAD   = "|cffff9a8f"
local HEX_BTN   = "|cffffe39a"

local QUALITY = { [2] = { 0.12, 1.00, 0.00 }, [3] = { 0.00, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 } }
local GOLD    = { 1.00, 0.85, 0.30 }

local host
local pool = {}        -- item buttons, reused across refreshes
local eligible = {}    -- last scan: items that can be picked
local toSell = {}      -- last scan: items over the max price, or refused by the server
local selected = {}    -- ["bag:slot"] = itemID
local refused = {}     -- ["bag:slot"] = { itemID =, reason = }: the server wouldn't disenchant it
local queue            -- batches still to send, while sending
local current          -- the batch the server is working on
local tally            -- results of the current send
local dirty
local atMerchant       -- a merchant window is open (MERCHANT_SHOW .. MERCHANT_CLOSED)
local Refresh

local function Settings()
    ProjectAstralSettings = ProjectAstralSettings or {}
    return ProjectAstralSettings
end
-- max vendor price in copper, from the saved gold + silver boxes; nil = no limit
local function MaxPrice()
    local s = Settings()
    local g, sv = tonumber(s.disenchantMaxVendorPriceGold), tonumber(s.disenchantMaxVendorPriceSilver)
    if not (g or sv) then return nil end
    return (g or 0) * 10000 + math.min(sv or 0, 99) * 100
end

local function TooExpensive(e)
    local max = MaxPrice()
    return max and (e.price or 0) > max
end

local function Show(region, on) if on then region:Show() else region:Hide() end end

local function SetStatus(text) if host then host.status:SetText(text) end end

-- per-item refusals: the item goes to the To sell line and the rest of its batch is sent again
local REFUSED = { CRAFTED_ITEM = "crafted item", BAD_QUALITY = "wrong quality", NOT_EQUIPPABLE = "not equippable" }

-- ── bag scan ────────────────────────────────────────────────────────
local function Scan()
    local ok, sell, sets = {}, {}, {}
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local kind, setName, itemID, link, quality = D.Classify(bag, slot)
            if kind then
                local key = bag .. ":" .. slot
                local r = refused[key]
                if r and r.itemID ~= itemID then refused[key] = nil; r = nil end   -- another item now
                local _, _, _, ilvl, _, _, _, _, _, texture, price = GetItemInfo(itemID)
                local e = { bag = bag, slot = slot, key = key, itemID = itemID, link = link,
                            quality = quality, ilvl = ilvl or 0, texture = texture, price = price,
                            setName = setName,
                            refusedFor = r and r.reason or (kind == "crafted" and REFUSED.CRAFTED_ITEM) }
                if kind == "set" then
                    sets[#sets + 1] = e
                elseif e.refusedFor or TooExpensive(e) then
                    e.toSell = true
                    sell[#sell + 1] = e
                else
                    ok[#ok + 1] = e
                end
            end
        end
    end
    local function order(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.ilvl > b.ilvl
    end
    table.sort(ok, order)
    table.sort(sell, order)
    table.sort(sets, order)
    return ok, sell, sets
end

local function CountSelected()
    local n = 0
    for _ in pairs(selected) do n = n + 1 end
    return n
end

-- ── item buttons ───────────────────────────────────────────────────
local function Paint(b)
    local e = b.e
    local locked = e.setName ~= nil
    local on = selected[e.key] ~= nil
    b.icon:SetDesaturated(locked and 1 or nil)
    b.icon:SetAlpha(locked and 0.40 or 1)
    local c = on and GOLD or (locked and UI.Nav.edge) or QUALITY[e.quality] or UI.Nav.edge
    for _, line in ipairs(b.lines) do line:SetVertexColor(c[1], c[2], c[3], 1) end
    Show(b.tint, on)
    Show(b.check, on)
end

local function UpdateSendButton()
    if not host then return end
    local n = CountSelected()
    if queue then
        host.sendBtn:SetLabel(HEX_BTN .. "Disenchanting...|r")
        host.sendBtn:SetDisabledLook(true)
    elseif n > 0 then
        host.sendBtn:SetLabel(HEX_BTN .. "Disenchant (" .. n .. ")|r")
        host.sendBtn:SetDisabledLook(false)
    else
        host.sendBtn:SetLabel("Disenchant")
        host.sendBtn:SetDisabledLook(true)
    end
    host.sellBtn:SetLabel(#toSell > 0 and (HEX_BTN .. "Sell (" .. #toSell .. ")|r") or "Sell")
    host.sellBtn:SetDisabledLook(queue ~= nil or #toSell == 0)
end

local function SummaryLine()
    host.count:SetText(string.format("%s%d|r %seligible  ·  |r%s%d|r %sselected|r",
        HEX_GOLD, #eligible, HEX_MUTED, HEX_GOLD, CountSelected(), HEX_MUTED))
end

local function ItemButton(i)
    local b = pool[i]
    if b then return b end
    b = CreateFrame("Button", nil, host.child)
    b:SetSize(BTN, BTN)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(SOLID); bg:SetAllPoints(b)
    bg:SetVertexColor(UI.Nav.panel[1], UI.Nav.panel[2], UI.Nav.panel[3], 0.95)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.icon:SetPoint("TOPLEFT", 2, -2); b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.tint = b:CreateTexture(nil, "OVERLAY")
    b.tint:SetTexture(SOLID); b.tint:SetAllPoints(b.icon)
    b.tint:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.22)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.check:SetSize(20, 20)
    b.check:SetPoint("TOPRIGHT", b, "TOPRIGHT", 4, 4)
    b.lines = UI.Outline(b, b, "BORDER", UI.Nav.edge, 1)
    b:SetScript("OnClick", function(self)
        local e = self.e
        if queue or e.setName or e.toSell then return end
        selected[e.key] = (not selected[e.key]) and e.itemID or nil
        Paint(self)
        UpdateSendButton()
        SummaryLine()
    end)
    b:SetScript("OnEnter", function(self)
        local e = self.e
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(e.bag, e.slot)
        if e.price and e.price > 0 then
            GameTooltip:AddLine("Vendor price: " .. GetCoinTextureString(e.price), 1, 1, 1)
        end
        if e.setName then
            GameTooltip:AddLine("Saved in your equipment set '" .. e.setName .. "': it can't be disenchanted.",
                1.00, 0.60, 0.56, true)
        elseif e.refusedFor then
            GameTooltip:AddLine("Refused by the Astral Table (" .. e.refusedFor
                .. "): sell it with the Sell button at a vendor.", 1.00, 0.60, 0.56, true)
        elseif e.toSell then
            GameTooltip:AddLine("Worth more than your max price: sell it with the Sell button at a vendor.",
                1.00, 0.80, 0.40, true)
        else
            GameTooltip:AddLine(selected[e.key] and "Click to unselect." or "Click to select.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pool[i] = b
    return b
end

-- lays the items out from the top of the scroll child; returns the y after the grid
local function Grid(list, first, y, cols)
    for i, e in ipairs(list) do
        local b = ItemButton(first + i - 1)
        b.e = e
        b.icon:SetTexture(e.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", host.child, "TOPLEFT", col * (BTN + GAP), -(y + row * (BTN + GAP)))
        Paint(b)
        b:Show()
    end
    return y + math.ceil(#list / cols) * (BTN + GAP)
end

Refresh = function()
    if not host then return end
    dirty = false
    local ok, sell, sets = Scan()
    eligible, toSell = ok, sell

    -- keep only selections still in the bags, on the same item, and under the price limit
    local present = {}
    for _, e in ipairs(ok) do present[e.key] = e end
    for key, itemID in pairs(selected) do
        local e = present[key]
        if not e or e.itemID ~= itemID then selected[key] = nil end
    end

    local width = host.scroll:GetWidth()
    if not width or width <= 0 then return end
    host.child:SetWidth(width)
    local cols = math.max(1, math.floor((width + GAP) / (BTN + GAP)))

    for _, b in ipairs(pool) do b:Hide() end
    local y = 0
    host.okHead:ClearAllPoints()
    host.okHead:SetPoint("TOPLEFT", host.child, "TOPLEFT", 0, -y)
    host.okHead:SetText(HEX_GOLD .. "Can be disenchanted|r  " .. HEX_MUTED .. "(" .. #ok .. ")|r")
    y = y + 22
    Show(host.okEmpty, #ok == 0)
    host.okEmpty:ClearAllPoints()
    host.okEmpty:SetPoint("TOPLEFT", host.child, "TOPLEFT", 0, -y)
    y = (#ok == 0) and (y + 24) or Grid(ok, 1, y, cols)

    -- the other two lines only show when they have items
    local function Section(head, list, first, text)
        Show(head, #list > 0)
        if #list == 0 then return end
        y = y + 12
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", host.child, "TOPLEFT", 0, -y)
        head:SetText(text)
        y = Grid(list, first, y + 22, cols)
    end
    Section(host.sellHead, sell, #ok + 1, HEX_GOLD .. "To sell|r  " .. HEX_MUTED .. "(" .. #sell
        .. ") — " .. (MaxPrice() and ("worth more than " .. GetCoinTextureString(MaxPrice()) .. " or ") or "")
        .. "refused by the table, use Sell at a vendor|r")
    Section(host.setHead, sets, #ok + #sell + 1, HEX_GOLD .. "In your equipment sets|r  " .. HEX_MUTED
        .. "(" .. #sets .. ") — kept, unsave them from the set to disenchant|r")
    host.child:SetHeight(math.max(1, y))

    SummaryLine()
    UpdateSendButton()
end

-- ── sending ────────────────────────────────────────────────────────
local function Finish(text)
    queue = nil
    SetStatus(text)
    Refresh()
end

local function SendNext()
    local batch = table.remove(queue, 1)
    current = batch
    if not batch then
        local t = tally
        local parts = {}
        if t.GEM > 0 then parts[#parts + 1] = t.GEM .. " gem" .. (t.GEM == 1 and "" or "s") end
        if t.SCROLL_1 > 0 then parts[#parts + 1] = t.SCROLL_1 .. " socket scroll" .. (t.SCROLL_1 == 1 and "" or "s") end
        if t.SCROLL_2 > 0 then parts[#parts + 1] = t.SCROLL_2 .. " removal scroll" .. (t.SCROLL_2 == 1 and "" or "s") end
        if t.LOST > 0 then parts[#parts + 1] = t.LOST .. " lost" end
        local text = HEX_GOOD .. "Done:|r " .. (#parts > 0 and table.concat(parts, ", ") or "no rewards") .. "."
        if t.mailed > 0 then text = text .. " " .. HEX_WARN .. t.mailed .. " sent to your mail (bags full).|r" end
        if t.refused > 0 then text = text .. " " .. HEX_WARN .. t.refused .. " refused, moved to To sell.|r" end
        Finish(text)
        return
    end
    if not D.Submit(batch) then
        Finish(HEX_BAD .. "Connection not ready. Try /reload.|r")
    end
end

local function SendSelected()
    if queue then return end
    local list = {}
    for _, e in ipairs(eligible) do
        if selected[e.key] then list[#list + 1] = { bag = e.bag, slot = e.slot } end
    end
    if #list == 0 then return end
    queue = {}
    for i = 1, #list, BATCH_MAX do
        local batch = {}
        for j = i, math.min(i + BATCH_MAX - 1, #list) do batch[#batch + 1] = list[j] end
        queue[#queue + 1] = batch
    end
    tally = { GEM = 0, SCROLL_1 = 0, SCROLL_2 = 0, LOST = 0, mailed = 0, refused = 0 }
    selected = {}
    SetStatus(HEX_MUTED .. "Disenchanting " .. #list .. " item" .. (#list == 1 and "" or "s") .. "...|r")
    UpdateSendButton()
    SendNext()
end

D.OnServer = function(event, a1, a2)
    if not queue then return end   -- a batch sent from the Astral Table window
    if event == "Result" then
        tally[a2] = (tally[a2] or 0) + 1
    elseif event == "Batch_end" then
        tally.mailed = tally.mailed + (tonumber(a1) or 0)
        SendNext()
    elseif event == "Batch_fail" then
        -- one refused item rejects the whole batch: move it to To sell, send the rest again
        local key = tostring(a1 or "")
        local bag, slot = key:match("^(%d+):(%d+)$")
        local itemID = bag and GetContainerItemID(tonumber(bag), tonumber(slot))
        if REFUSED[a2] and itemID and current then
            refused[key] = { itemID = itemID, reason = REFUSED[a2] }
            if a2 == "CRAFTED_ITEM" then D.crafted[itemID] = true end   -- every copy of it is crafted
            tally.refused = tally.refused + 1
            local rest = {}
            for _, it in ipairs(current) do
                if it.bag .. ":" .. it.slot ~= key then rest[#rest + 1] = it end
            end
            if #rest > 0 then table.insert(queue, 1, rest) end
            dirty = true
            SendNext()
        else
            Finish(HEX_BAD .. "Stopped: the server refused a batch (" .. tostring(a2) .. ").|r")
        end
    end
end

-- ── selling ────────────────────────────────────────────────────────
-- UseContainerItem sells only while a merchant window is open; without one it
-- would equip the item instead, so nothing is touched unless a merchant is open.
local function SellAll()
    if queue or #toSell == 0 then return end
    if not atMerchant then
        SetStatus(HEX_BAD .. "Talk to a vendor first: selling only works while a merchant window is open.|r")
        UIErrorsFrame:AddMessage("Talk to a vendor first to sell these items.", 1.0, 0.42, 0.42, 1.0)
        return
    end
    local sold, copper = 0, 0
    for _, e in ipairs(toSell) do
        if GetContainerItemID(e.bag, e.slot) == e.itemID then   -- still the same item in that slot
            UseContainerItem(e.bag, e.slot)
            sold = sold + 1
            copper = copper + (e.price or 0)
        end
    end
    SetStatus(HEX_GOOD .. "Sold " .. sold .. " item" .. (sold == 1 and "" or "s") .. " for|r "
        .. GetCoinTextureString(copper) .. HEX_MUTED .. " (buy back at the vendor if needed).|r")
    dirty = true
end

-- ── tab ────────────────────────────────────────────────────────────
local function AddTip(btn, title, body)
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(body, 0.8, 0.8, 0.85, true)
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function BuildDisenchantTab(panel)
    host = panel
    local top = -8

    local ground = panel:CreateTexture(nil, "BACKGROUND")
    ground:SetTexture(SOLID)
    ground:SetAllPoints(panel)
    ground:SetVertexColor(UI.Tint(0.031, 0.047, 0.133, 0.85))

    -- ── Header: Disenchant, Select all, Clear, Sell | max price ──
    local sendBtn = UI.MakeButton(panel, "Disenchant", { w = 140, h = 26, variant = "gold",
        onClick = SendSelected })
    sendBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDE, top)
    AddTip(sendBtn, "Disenchant selected",
        "Sends the selected items to the Astral Table, 9 at a time. They are destroyed for gems and scrolls.")
    panel.sendBtn = sendBtn

    local allBtn = UI.MakeButton(panel, "Select all", { w = 96, h = 26, variant = "secondary",
        onClick = function()
            if queue then return end
            for _, e in ipairs(eligible) do selected[e.key] = e.itemID end
            Refresh()
        end })
    allBtn:SetPoint("LEFT", sendBtn, "RIGHT", 6, 0)
    AddTip(allBtn, "Select all", "Selects every item that can be disenchanted (not the ones to sell).")

    local clearBtn = UI.MakeButton(panel, "Clear", { w = 64, h = 26, variant = "secondary",
        onClick = function() selected = {}; Refresh() end })
    clearBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)

    local sellBtn = UI.MakeButton(panel, "Sell", { w = 90, h = 26, variant = "gold", onClick = SellAll })
    sellBtn:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
    AddTip(sellBtn, "Sell to a vendor",
        "Sells every item in the To sell line. Talk to a vendor first: it only works while a merchant window is open.")
    panel.sellBtn = sellBtn

    -- max price: gold + silver boxes, each value saved as typed
    local function PriceBox(w, letters)
        local box = UI.MakeSearchBox(panel, { width = w, height = 26, placeholder = "" })
        UI.StyleFilterSearch(box); box.__paBackdrop = true
        box.edit:SetNumeric(true)
        box.edit:SetMaxLetters(letters)
        AddTip(box, "Max vendor price",
            "Items that sell to a vendor for more than this go to the To sell line. Both empty = no limit.")
        return box
    end
    local silverBox = PriceBox(40, 2)
    silverBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE - 14, top)
    local goldBox = PriceBox(60, 6)
    goldBox:SetPoint("RIGHT", silverBox, "LEFT", -18, 0)
    local function Unit(box, tex)
        local fs = panel:CreateFontString(nil, "OVERLAY")
        UI.SetTextFont(fs, 12)
        fs:SetPoint("LEFT", box, "RIGHT", 3, 0)
        fs:SetText("|T" .. tex .. ":12:12|t")
    end
    Unit(goldBox, "Interface\\MoneyFrame\\UI-GoldIcon")
    Unit(silverBox, "Interface\\MoneyFrame\\UI-SilverIcon")

    local saved = Settings()
    goldBox:SetText(saved.disenchantMaxVendorPriceGold and tostring(saved.disenchantMaxVendorPriceGold) or "")
    silverBox:SetText(saved.disenchantMaxVendorPriceSilver and tostring(saved.disenchantMaxVendorPriceSilver) or "")
    local function OnPrice()
        saved = Settings()
        saved.disenchantMaxVendorPriceGold = tonumber(goldBox:GetText())
        saved.disenchantMaxVendorPriceSilver = tonumber(silverBox:GetText())
        if host.child then Refresh() end
    end
    goldBox.edit:HookScript("OnTextChanged", OnPrice)
    silverBox.edit:HookScript("OnTextChanged", OnPrice)

    local priceLabel = panel:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(priceLabel, 12)
    priceLabel:SetPoint("RIGHT", goldBox, "LEFT", -8, 0)
    priceLabel:SetText(HEX_MUTED .. "Max price|r")

    -- ── Status bar: counts, then the result of the last send ──
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetHeight(30)
    bar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  SIDE,  top - 34)
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -SIDE, top - 34)
    UI.AstralBackdrop(bar, { thin = true })
    bar:SetBackdropColor(0.20, 0.16, 0.07, 0.92)
    bar:SetBackdropBorderColor(0.84, 0.71, 0.35, 0.85)
    bar.__paBackdrop = true

    panel.count = bar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.count, 12)
    panel.count:SetPoint("RIGHT", bar, "RIGHT", -12, 0)

    panel.status = bar:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.status, 12)
    panel.status:SetPoint("LEFT", bar, "LEFT", 12, 0)
    panel.status:SetPoint("RIGHT", panel.count, "LEFT", -10, 0)
    panel.status:SetJustifyH("LEFT")
    panel.status:SetWordWrap(false)
    SetStatus(HEX_MUTED .. "Click items to select them, then Disenchant.|r")

    -- ── Item grid ──
    local listPanel = CreateFrame("Frame", nil, panel)
    listPanel:SetPoint("TOPLEFT",     bar,   "BOTTOMLEFT",  0, -8)
    listPanel:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -SIDE, 10)
    UI.AstralBackdrop(listPanel, { thin = true })
    listPanel:SetBackdropColor(0.099, 0.099, 0.099, 0.95)
    listPanel:SetBackdropBorderColor(0.256, 0.256, 0.256, 1)
    listPanel.__paBackdrop = true

    local scroll = CreateFrame("ScrollFrame", "PADisenchantTabScroll", listPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",      10, -10)
    scroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -30, 10)
    panel.scroll = scroll

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    panel.child = child

    panel.okHead = child:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.okHead, 13)
    panel.okEmpty = child:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.okEmpty, 12)
    panel.okEmpty:SetText(HEX_MUTED .. "Nothing in your bags can be disenchanted.|r")
    panel.sellHead = child:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.sellHead, 13)
    panel.setHead = child:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(panel.setHead, 13)

    panel:SetScript("OnShow", Refresh)
    panel:SetScript("OnSizeChanged", function() if panel:IsVisible() then Refresh() end end)
    -- bag changes come in bursts: redraw once, on the next frame
    panel:SetScript("OnUpdate", function() if dirty then Refresh() end end)
    if UI.SkinTree then UI.SkinTree(panel) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then atMerchant = true
    elseif event == "MERCHANT_CLOSED" then atMerchant = false end
    dirty = true
end)

local function ToggleDisenchant()
    local mf = PA.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "astral_disenchant" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("astral_disenchant")
    end
end

PA:RegisterModule("astral_disenchant", "Disenchant", ToggleDisenchant, {
    subtitle = "Pick bag items to disenchant at a glance and send them in one click.",
})
PA:RegisterTabContent("astral_disenchant", BuildDisenchantTab)
