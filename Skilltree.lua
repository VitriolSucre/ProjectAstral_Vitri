local PA = ProjectAstral
local UI = PA.UI

local AT = {}
PA.AT = AT

-- unified Astral look (same as the gem and build tabs): navy surfaces, 1px navy
-- borders, gold highlight, chat-style text
local NV = {
    deep  = UI.Tinted({ 0.031, 0.047, 0.133, 0.97 }),
    panel = UI.Tinted({ 0.043, 0.067, 0.188, 0.95 }),
    edge  = UI.Tinted({ 0.165, 0.204, 0.400, 1 }),
    goldEdge = { 0.84, 0.71, 0.35, 0.95 },
    gold  = { 0.886, 0.753, 0.384 },
    txtGold  = { 1.00, 0.85, 0.44 },
    txtMuted = UI.Tinted({ 0.86, 0.87, 0.94 }),
    txtDim   = UI.Tinted({ 0.667, 0.690, 0.831 }),
    txtGood  = { 0.50, 0.88, 0.63 },
}
function NV.Navy(f, bg, edge)
    f.__paBackdrop = true   -- Theme.lua greys navy backdrops otherwise
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
end
-- gold tint + 3px gold bar on the left edge (the "selected" look of the build tabs)
function NV.GoldAccent(f)
    local tint = f:CreateTexture(nil, "BORDER")
    tint:SetTexture("Interface\\Buttons\\WHITE8X8")
    tint:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    tint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    tint:SetGradientAlpha("HORIZONTAL", 0.94, 0.82, 0.43, 0.14, 0.94, 0.82, 0.43, 0)
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetVertexColor(NV.gold[1], NV.gold[2], NV.gold[3], 1)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    bar:SetWidth(3)
    return tint, bar
end
-- section title: 3px gold bar + white chat-style text
function NV.Title(parent, text, size)
    local bar = parent:CreateTexture(nil, "OVERLAY")
    bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetVertexColor(NV.gold[1], NV.gold[2], NV.gold[3], 1)
    bar:SetSize(3, (size or 15) + 3)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(fs, size or 15)
    fs:SetPoint("LEFT", bar, "RIGHT", 9, 0)
    fs:SetText(text)
    fs:SetTextColor(1, 1, 1)
    return bar, fs
end

local SCALE      = 1
local ZOOM_MIN   = 0.03
local ZOOM_MAX   = 3.0
local FIT_ZOOM_MIN = 0.22
local ZOOM_STEP  = 0.12
local ZOOM_FACTOR = 1.10
local NODE_W_T   = { [1] = 36, [2] = 56, [3] = 72 }
local NODE_W     = NODE_W_T[2]
local PAD        = 60
local LINE_THICK = 2
local BORDER_INSET_BASE     = 4
local BORDER_THICKNESS_BASE = 4

local function BorderInset() return math.max(1, math.floor(BORDER_INSET_BASE     * AT.zoom)) end
local function BorderThick() return math.max(1, math.floor(BORDER_THICKNESS_BASE * AT.zoom)) end
local function LineThick()   return math.max(1, math.floor(LINE_THICK            * AT.zoom)) end

local function SetBorderColor(bf, r, g, b, a)
    local bt = bf and bf.borderTextures
    if not bt then return end
    bt.top:SetVertexColor(r, g, b, a)
    bt.bottom:SetVertexColor(r, g, b, a)
    bt.left:SetVertexColor(r, g, b, a)
    bt.right:SetVertexColor(r, g, b, a)
end

local C_TIER = {
    [1] = {0.20, 0.80, 0.20},
    [2] = {0.20, 0.55, 0.95},
    [3] = UI.Tinted({ 0.78, 0.22, 0.95 }),
}

local EFFECT_META = {
    STRENGTH_PCT      = { unit = "pct",    label = "Strength"      },
    AGILITY_PCT       = { unit = "pct",    label = "Agility"       },
    STAMINA_PCT       = { unit = "pct",    label = "Stamina"       },
    INTELLECT_PCT     = { unit = "pct",    label = "Intellect"     },
    SPIRIT_PCT        = { unit = "pct",    label = "Spirit"        },

    ATTACK_POWER_PCT  = { unit = "pct",    label = "Attack Power"  },
    ARMOR_PCT         = { unit = "pct",    label = "Armor"         },

    CRIT_RATING_PCT   = { unit = "pct",    label = "Crit Rating"   },
    HASTE_RATING_PCT  = { unit = "pct",    label = "Haste Rating"  },
    HIT_CHANCE_PCT    = { unit = "rating", label = "Hit Rating"    },
    EXPERTISE_PCT     = { unit = "rating", label = "Expertise"     },
    DODGE_RATING_PCT  = { unit = "pct",    label = "Dodge Rating"  },
    PARRY_RATING_PCT  = { unit = "pct",    label = "Parry Rating"  },
    BLOCK_RATING_PCT  = { unit = "pct",    label = "Block Rating"  },

    BONUS_SPELLPOWER_PCT = { unit = "pct",  label = "Spell Power"   },
    BONUS_DAMAGE_PCT     = { unit = "pct",  label = "Spell Power"   },
    BONUS_HEALING_PCT    = { unit = "pct",  label = "Spell Power"   },
    MP5_PCT              = { unit = "pct",  label = "Mana per 5"    },

    GROUND_MOVEMENT_SPEED_PCT  = { unit = "pct",  label = "Run Speed"     },
    MOUNTED_MOVEMENT_SPEED_PCT = { unit = "pct",  label = "Mounted Speed" },
    FLIGHT_SPEED_PCT           = { unit = "pct",  label = "Flight Speed"  },
    SWIM_SPEED_PCT             = { unit = "pct",  label = "Swim Speed"    },

    WATER_WALK         = { unit = "flag", label = "Water Walking"     },
    WATER_BREATHING    = { unit = "flag", label = "Underwater Breathing" },
    SAFE_FALL          = { unit = "flag", label = "No Fall Damage"    },

    EXPERIENCE_GAIN_PCT  = { unit = "pct", label = "Experience Gain"  },
    REPUTATION_GAIN_PCT  = { unit = "pct", label = "Reputation Gain"  },
    HONOR_GAIN_PCT       = { unit = "pct", label = "Honor Gain"       },

    THREAT_GENERATION_PCT = { unit = "pct",  label = "Increased Threat" },

    CC_DURATION_REDUCTION_PCT = { unit = "pct",  label = "Crowd-Control Duration", invert = true },

    HEARTHSTONE_COOLDOWN_PCT   = { unit = "pct",  label = "Hearthstone Cooldown",            invert = true },
    REZ_SICKNESS_DURATION_PCT  = { unit = "pct",  label = "Resurrection Sickness Duration",  invert = true },
    REZ_SICKNESS_DURATION_SEC  = { unit = "flat", label = "sec Resurrection Sickness Duration", invert = true },

    ALL_RESISTANCE_FLAT        = { unit = "flat", label = "All Resistances" },

    REAGENT_BANK_UNLOCKED      = { unit = "flag", label = "Reagent Bank" },
    AOE_LOOT_UNLOCKED          = { unit = "flag", label = "AoE Loot" },
    INSTANT_FLIGHT_UNLOCKED    = { unit = "flag", label = "Instant Flight Paths" },

    FLIGHT_COST_REDUCTION_PCT     = { unit = "pct", label = "Flight Path Cost", invert = true },
    INSTANT_FLIGHT_COST_MULT_PCT  = { unit = "pct", label = "Instant Flight Cost" },

    CRAFT_POINTS_BONUS_PCT    = { unit = "pct", label = "Crafting Points" },
    CRAFT_SPEED_PCT           = { unit = "pct", label = "Crafting Speed" },
    GATHER_POINTS_BONUS_PCT   = { unit = "pct", label = "Gathering Points" },
    DOUBLE_CRAFT_CHANCE_PCT   = { unit = "pct", label = "Double Craft Chance" },
    GATHER_MULTIPLIER_PCT     = { unit = "pct", label = "Gathering Yield" },
    GEM_NORMAL_DROP_ALLOWED   = { unit = "flag", label = "Gem Drops" },
    GEM_NORMAL_DROP_CHANCE_PCT = { unit = "pct", label = "Gem Drop Chance" },
    GEM_FUSION_T2_ALLOWED     = { unit = "flag", label = "Tier 2 Gem Fusion" },
    GEM_FUSION_T3_ALLOWED     = { unit = "flag", label = "Tier 3 Gem Fusion" },
    GEM_FUSION_T4_ALLOWED     = { unit = "flag", label = "Tier 4 Gem Fusion" },
    GEM_FUSION_T5_ALLOWED     = { unit = "flag", label = "Tier 5 Gem Fusion" },
    GEM_FUSION_T6_ALLOWED     = { unit = "flag", label = "Tier 6 Gem Fusion" },
}

local SUMMARY_GROUPS = {
    { name = "Offensive",
      types = { "STRENGTH_PCT", "AGILITY_PCT",
                "INTELLECT_PCT", "SPIRIT_PCT",
                "ATTACK_POWER_PCT",
                "BONUS_SPELLPOWER_PCT", "BONUS_DAMAGE_PCT", "BONUS_HEALING_PCT",
                "CRIT_RATING_PCT", "HASTE_RATING_PCT",
                "HIT_CHANCE_PCT", "EXPERTISE_PCT",
                "MP5_PCT" } },
    { name = "Defensive",
      types = { "ARMOR_PCT", "STAMINA_PCT",
                "DODGE_RATING_PCT", "PARRY_RATING_PCT", "BLOCK_RATING_PCT",
                "THREAT_GENERATION_PCT",
                "CC_DURATION_REDUCTION_PCT",
                "ALL_RESISTANCE_FLAT" } },
    { name = "Quality of Life",
      types = { "AOE_LOOT_UNLOCKED", "INSTANT_FLIGHT_UNLOCKED",
                "REAGENT_BANK_UNLOCKED",
                "WATER_WALK", "WATER_BREATHING", "SAFE_FALL",
                "GROUND_MOVEMENT_SPEED_PCT", "MOUNTED_MOVEMENT_SPEED_PCT",
                "FLIGHT_SPEED_PCT", "SWIM_SPEED_PCT",
                "EXPERIENCE_GAIN_PCT", "REPUTATION_GAIN_PCT", "HONOR_GAIN_PCT",
                "HEARTHSTONE_COOLDOWN_PCT",
                "REZ_SICKNESS_DURATION_PCT", "REZ_SICKNESS_DURATION_SEC" } },
}

local function FormatEffect(eff)
    local m = EFFECT_META[eff.type]
    if not m then return eff.type .. ": " .. tostring(eff.value) end
    local v = eff.value
    local sign
    if m.invert then
        sign = v > 0 and "-" or (v == 0 and "" or "+")
    else
        sign = v >= 0 and "+" or ""
    end
    if m.unit == "pct"    then return sign .. v .. "% " .. m.label end
    if m.unit == "rating" then return sign .. v .. " "  .. m.label end
    if m.unit == "flat"   then return sign .. v .. " "  .. m.label end
    if m.unit == "flag"   then return m.label end
    return m.label .. ": " .. v
end

local LC_BOTH    = {1.00, 0.60, 0.10, 0.90}
local LC_PARTIAL = {0.22, 0.72, 0.22, 0.70}
local LC_NONE    = UI.Tinted({ 0.26, 0.28, 0.42, 0.50 })

AT.nodes     = {}
AT.links     = {}
AT.unlocked  = {}
AT.receiving = false
AT.zoom      = SCALE
AT.offX           = 0
AT.offY           = 0
AT.costs          = {}
AT.prestigeTokens = 0
AT.prestigeLevel  = 0

if PA and PA.OnTokensChanged then
    AT.prestigeTokens = PA.prestigeTokens or 0
    AT.prestigeLevel  = PA.prestigeLevel  or 0
    PA:OnTokensChanged(function(tokens, level)
        AT.prestigeTokens = tokens or 0
        AT.prestigeLevel  = level  or 0
    end)
end

AT.serverVersion = nil
AT.usingBaked    = false
AT.awaitingFull  = false

local mainFrame, sf, canvas, infoName, infoDesc, infoIcon, unlockBtn, removeBtn
local summaryFrame, summaryBtn
AT.selectedId  = nil
AT.focusNeeded  = true

local SelectNode

local nodePool   = {}
local nodeFree   = {}
local activeBtns = {}
AT.nodeList      = {}
AT.rendered      = false

local dotPool     = {}
AT.lodActive      = false
local LOD_NODE_PX = 7

local treeExtentX, treeExtentY = 0, 0

local lastCullH, lastCullV, lastCullZoom = -1, -1, -1
local cullDirty   = true
local CULL_MARGIN = 160

local linesDirty    = false
local lineRedrawAt  = 0
local LINE_REDRAW_DELAY = 0.07

local isPanning            = false
local panSX, panSY         = 0, 0
local panStartH, panStartV = 0, 0

local lastClickId   = nil
local lastClickTime = 0
local DCLICK_DELAY  = 0.40

local removeQueue = {}
local unlockQueue = {}
local pendingUnlockChain = nil

local linePool    = {}
local linePoolIdx = 1
local lineData    = {}

local function ResetLinePool()
    for i = 1, linePoolIdx - 1 do
        linePool[i].ag:Stop()
        linePool[i].tex:Hide()
    end
    linePoolIdx = 1
    for k in pairs(lineData) do lineData[k] = nil end
end

local function DrawLine(x1, y1, x2, y2, fromId, toId)
    local dx   = x2 - x1
    local dy   = y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 2 then return end

    local angle = math.deg(math.atan2(-dy, dx))

    local entry = linePool[linePoolIdx]
    local tex, ag, rot

    if not entry then
        tex = canvas:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetBlendMode("BLEND")
        ag  = tex:CreateAnimationGroup()
        ag:SetLooping("NONE")
        rot = ag:CreateAnimation("Rotation")
        rot:SetOrder(1)
        rot:SetOrigin("CENTER", 0, 0)
        rot:SetEndDelay(99999)
        linePool[linePoolIdx] = { tex = tex, ag = ag, rot = rot }
    else
        tex = entry.tex ; ag = entry.ag ; rot = entry.rot
        ag:Stop()
        tex:ClearAllPoints()
        tex:Show()
    end

    tex:SetSize(dist, LineThick())
    tex:SetPoint("CENTER", canvas, "TOPLEFT", (x1+x2)*0.5, -((y1+y2)*0.5))
    rot:SetDegrees(angle)
    rot:SetDuration(0.001)
    ag:Play()

    lineData[linePoolIdx] = { tex = tex, fromId = fromId, toId = toId }
    linePoolIdx = linePoolIdx + 1
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

local function ChatInfo(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF88AAFF[AstralTree]|r " .. msg)
end

local function UpdatePrestigeDisplay()
    if PA.mainFrame and PA.mainFrame.RefreshChips then
        PA.mainFrame:RefreshChips()
    end
end

local function Send(cmd)
    SendChatMessage("." .. cmd, "SAY")
end

local function DrainRemoveQueue()
    if #removeQueue > 0 then
        Send("astral remove " .. table.remove(removeQueue, 1))
    end
end

local function DrainUnlockQueue()
    if #unlockQueue > 0 then
        Send("astral unlock " .. table.remove(unlockQueue, 1))
    end
end

local function CollectUnlockPath(targetId)
    if not AT.nodes or AT.unlocked[targetId] then return {} end
    local target = AT.nodes[targetId]
    if not target then return {} end

    local ordered, visiting, visited = {}, {}, {}
    local function visit(id)
        if AT.unlocked[id] or visited[id] then return end
        if visiting[id] then return end
        visiting[id] = true
        local n = AT.nodes[id]
        if n and n.parents then
            for i = 1, #n.parents do visit(n.parents[i]) end
        end
        visiting[id] = nil
        visited[id] = true
        ordered[#ordered + 1] = id
    end
    visit(targetId)
    return ordered
end

local function ComputePathCost(ids)
    local cost = 0
    for i = 1, #ids do
        local n = AT.nodes[ids[i]]
        if n then cost = cost + (AT.costs[n.tier or 1] or 0) end
    end
    return cost
end

local function LoadBakedData()
    local d = AstralTreeData
    if not d or not d.nodes then return false end

    AT.nodes, AT.links = {}, {}
    for i = 1, #d.nodes do
        local nd = d.nodes[i]
        AT.nodes[nd.id] = {
            id         = nd.id,
            name       = nd.name or "?",
            desc       = nd.desc or "",
            requiredId = 0,
            icon       = nd.icon or "",
            posX       = nd.x or 0,
            posY       = nd.y or 0,
            tier       = nd.tier or 1,
            parents    = {},
            effects    = {},
        }
    end
    if d.links then
        for i = 1, #d.links do
            local lk = d.links[i]
            AT.links[#AT.links + 1] = { from = lk[1], to = lk[2] }
        end
    end
    if d.effects then
        for nodeId, list in pairs(d.effects) do
            local n = AT.nodes[nodeId]
            if n then
                for j = 1, #list do
                    n.effects[#n.effects + 1] = { type = list[j][1], value = list[j][2] }
                end
            end
        end
    end
    for i = 1, #AT.links do
        local link   = AT.links[i]
        local target = AT.nodes[link.to]
        local source = AT.nodes[link.from]
        if target and source then
            target.parents[#target.parents + 1] = link.from
        end
    end
    return true
end

function AT.ApplyFullTree(payload)
    if type(payload) ~= "table" then return end
    AT.nodes = {}
    AT.links = {}
    for _, n in ipairs(payload.nodes or {}) do
        AT.nodes[n.id] = {
            id         = n.id,
            name       = n.name or "?",
            desc       = n.desc or "",
            requiredId = n.required or 0,
            icon       = n.icon or "",
            posX       = n.x or 0,
            posY       = n.y or 0,
            tier       = n.tier or 1,
            parents    = {},
            effects    = {},
        }
    end
    for nodeId, effs in pairs(payload.effects or {}) do
        local node = AT.nodes[tonumber(nodeId) or nodeId]
        if node then
            node.effects = {}
            for _, e in ipairs(effs) do
                node.effects[#node.effects + 1] = { type = e.type, value = e.value }
            end
        end
    end
    for _, link in ipairs(payload.links or {}) do
        AT.links[#AT.links + 1] = { from = link.from, to = link.to }
        local target = AT.nodes[link.to]
        if target then
            target.parents[#target.parents + 1] = link.from
        end
    end
    AT.usingBaked = false
    if mainFrame and mainFrame:IsShown() and not AT.rendered then
        AT.RenderTree()
    else
        AT.RefreshNodes()
    end
end

function AT.OnInitialStateApplied()
    AT.costs = AT.tierCost or AT.costs or {}
    local baked = AstralTreeData and AstralTreeData.version
    if baked and baked == AT.dataVersion and LoadBakedData() then
        AT.usingBaked = true
        if mainFrame and mainFrame:IsShown() and not AT.rendered then
            AT.RenderTree()
        else
            AT.RefreshNodes()
        end
    else
        AT.usingBaked = false
        if AT.RequestFullTreeAIO then AT.RequestFullTreeAIO() end
    end
end

local function ArePrereqsMet(n)
    local parents = n and n.parents
    if not parents or #parents == 0 then return true end
    for i = 1, #parents do
        if not AT.unlocked[parents[i]] then return false end
    end
    return true
end

local function GetMissingPrereqs(n)
    local missing = {}
    local parents = n and n.parents
    if not parents then return missing end
    for i = 1, #parents do
        local pid = parents[i]
        if not AT.unlocked[pid] then
            missing[#missing+1] = AT.nodes[pid] or { id = pid, name = tostring(pid) }
        end
    end
    return missing
end

local function FormatPrereqList(nodes)
    if #nodes == 0 then return "" end
    local names = {}
    for i = 1, #nodes do names[i] = nodes[i].name or tostring(nodes[i].id) end
    return table.concat(names, " + ")
end

local function FindDependents(id)
    local names = {}
    for _, n in pairs(AT.nodes) do
        if AT.unlocked[n.id] and n.parents then
            for i = 1, #n.parents do
                if n.parents[i] == id then
                    names[#names+1] = n.name
                    break
                end
            end
        end
    end
    return names
end

local function CollectRemovalChain(rootId)
    if not (AT.unlocked and AT.unlocked[rootId]) then return {} end
    local toRemove = { [rootId] = true }
    local changed = true
    while changed do
        changed = false
        for id in pairs(AT.unlocked) do
            if not toRemove[id] then
                local n = AT.nodes[id]
                if n and n.parents then
                    for i = 1, #n.parents do
                        if toRemove[n.parents[i]] then
                            toRemove[id] = true
                            changed = true
                            break
                        end
                    end
                end
            end
        end
    end
    local order, pending = {}, {}
    for id in pairs(toRemove) do pending[id] = true end
    local progress = true
    while progress do
        progress = false
        for id in pairs(pending) do
            local blocked = false
            for oid in pairs(pending) do
                if oid ~= id then
                    local n = AT.nodes[oid]
                    if n and n.parents then
                        for i = 1, #n.parents do
                            if n.parents[i] == id then blocked = true; break end
                        end
                        if blocked then break end
                    end
                end
            end
            if not blocked then
                order[#order+1] = id; pending[id] = nil; progress = true
            end
        end
    end
    return order
end

local function GetRemoveOrder()
    local order, pending = {}, {}
    for id in pairs(AT.unlocked) do pending[id] = true end
    local changed = true
    while changed do
        changed = false
        for id in pairs(pending) do
            local blocked = false
            for oid in pairs(pending) do
                if oid ~= id and AT.nodes[oid] and AT.nodes[oid].parents then
                    local op = AT.nodes[oid].parents
                    for i = 1, #op do
                        if op[i] == id then blocked = true; break end
                    end
                    if blocked then break end
                end
            end
            if not blocked then
                order[#order+1] = id; pending[id] = nil; changed = true
            end
        end
    end
    return order
end

local function NX(n) return (n.posX + AT.offX) * AT.zoom end
local function NY(n) return (n.posY + AT.offY) * AT.zoom end

local function CalcOffsets()
    local minX, minY = math.huge, math.huge
    for _, n in pairs(AT.nodes) do
        minX = math.min(minX, n.posX)
        minY = math.min(minY, n.posY)
    end
    if minX == math.huge then minX = 0 end
    if minY == math.huge then minY = 0 end
    AT.offX = (minX < PAD) and (PAD - minX) or 0
    AT.offY = (minY < PAD) and (PAD - minY) or 0
end

local function FitView()
    if not sf or not next(AT.nodes) then return end
    CalcOffsets()
    local maxNX, maxNY = 0, 0
    for _, n in pairs(AT.nodes) do
        maxNX = math.max(maxNX, n.posX + AT.offX)
        maxNY = math.max(maxNY, n.posY + AT.offY)
    end
    local sfW = sf:GetWidth();  if sfW < 10 then sfW = 700 end
    local sfH = sf:GetHeight(); if sfH < 10 then sfH = 400 end
    AT.zoom = math.max(FIT_ZOOM_MIN, math.min(
        sfW / (maxNX + NODE_W/2 + PAD),
        sfH / (maxNY + NODE_W/2 + PAD),
        ZOOM_MAX))
end

local function CenterOnOrigin()
    if not sf or not next(AT.nodes) then return end
    local originId
    for id, n in pairs(AT.nodes) do
        if n.name == "Astral Origin" then originId = id; break end
    end
    if not originId then
        for id, n in pairs(AT.nodes) do
            if not n.parents or #n.parents == 0 then originId = id; break end
        end
    end
    if not originId then sf:SetHorizontalScroll(0); sf:SetVerticalScroll(0); return end
    local n   = AT.nodes[originId]
    local sfW = sf:GetWidth();  if sfW < 10 then sfW = 700 end
    local sfH = sf:GetHeight(); if sfH < 10 then sfH = 400 end
    local hRange = math.max(0, canvas:GetWidth()  - sfW)
    local vRange = math.max(0, canvas:GetHeight() - sfH)
    sf:SetHorizontalScroll(math.max(0, math.min(NX(n) - sfW*0.5, hRange)))
    sf:SetVerticalScroll(  math.max(0, math.min(NY(n) - sfH*0.5, vRange)))
end

local function NodeSize(tier)
    local base = NODE_W_T[tier or 2] or NODE_W
    return math.max(1, math.floor(base * AT.zoom))
end

local function UpdateLineColors()
    for i = 1, linePoolIdx - 1 do
        local ld = lineData[i]
        if ld then
            if AT.unlocked[ld.fromId] and AT.unlocked[ld.toId] then
                ld.tex:SetVertexColor(unpack(LC_BOTH))
            elseif AT.unlocked[ld.fromId] or AT.unlocked[ld.toId] then
                ld.tex:SetVertexColor(unpack(LC_PARTIAL))
            else
                ld.tex:SetVertexColor(unpack(LC_NONE))
            end
        end
    end
end

local function StyleNodeButton(btn, n)
    local bf = btn.borderFrame
    local tc = C_TIER[n.tier or 1] or C_TIER[1]
    if AT.unlocked[n.id] then
        SetBorderColor(bf, tc[1], tc[2], tc[3], 1.0)
        btn.icon:SetDesaturated(false); btn.icon:SetAlpha(1.0)
    elseif ArePrereqsMet(n) then
        SetBorderColor(bf, tc[1] * 0.75, tc[2] * 0.75, tc[3] * 0.75, 0.85)
        btn.icon:SetDesaturated(false); btn.icon:SetAlpha(0.90)
    else
        SetBorderColor(bf, tc[1] * 0.40, tc[2] * 0.40, tc[3] * 0.40, 0.65)
        btn.icon:SetDesaturated(true);  btn.icon:SetAlpha(0.45)
    end
end

local function PlaceNodeButton(btn, n)
    local ns   = NodeSize(n.tier)
    local half = ns / 2
    btn:ClearAllPoints()
    btn:SetSize(ns, ns)
    btn:SetPoint("TOPLEFT", canvas, "TOPLEFT", NX(n)-half, -(NY(n)-half))
    local bf = btn.borderFrame
    if bf then
        local inset     = BorderInset()
        local thickness = BorderThick()
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -inset,  inset)
        bf:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  inset, -inset)
        local bt = bf.borderTextures
        if bt then
            bt.top:SetHeight(thickness)
            bt.bottom:SetHeight(thickness)
            bt.left:SetWidth(thickness)
            bt.right:SetWidth(thickness)
        end
    end
end

local function CreateNodeButton()
    local canvasLevel = canvas:GetFrameLevel()

    local btn = CreateFrame("Button", nil, canvas)
    btn:SetFrameLevel(canvasLevel + 3)

    local bf = CreateFrame("Frame", nil, canvas)
    bf:SetFrameLevel(canvasLevel + 2)
    local function MakeEdgeTex()
        local t = bf:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:SetVertexColor(UI.Tint(0.28, 0.28, 0.36, 1))
        return t
    end
    local top, bottom = MakeEdgeTex(), MakeEdgeTex()
    local left, right = MakeEdgeTex(), MakeEdgeTex()
    top:SetPoint("TOPLEFT",  bf, "TOPLEFT",  0, 0)
    top:SetPoint("TOPRIGHT", bf, "TOPRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMLEFT",  bf, "BOTTOMLEFT",  0, 0)
    bottom:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", 0, 0)
    left:SetPoint("TOPLEFT",    top,    "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT",    0, 0)
    right:SetPoint("TOPRIGHT",    top,    "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT",    0, 0)
    bf.borderTextures = { top = top, bottom = bottom, left = left, right = right }
    btn.borderFrame = bf

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(UI.Tint(0.04, 0.04, 0.08, 1.0))

    local ico = btn:CreateTexture(nil, "ARTWORK")
    ico:SetAllPoints()
    ico:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = ico

    btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetScript("OnEnter", function(self)
        local n = self.node; if not n then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(n.name, 1, 0.82, 0)
        if n.desc and n.desc ~= "" then
            GameTooltip:AddLine(n.desc, 0.88, 0.88, 0.88, true)
        end
        if n.effects and #n.effects > 0 then
            if n.desc and n.desc ~= "" then GameTooltip:AddLine(" ") end
            for i = 1, #n.effects do
                GameTooltip:AddLine(FormatEffect(n.effects[i]), 0.50, 1.00, 0.50)
            end
        end
        local tc = C_TIER[n.tier or 1] or C_TIER[1]
        GameTooltip:AddLine("Tier " .. (n.tier or 1), tc[1], tc[2], tc[3])
        if AT.unlocked[n.id] then
            GameTooltip:AddLine("|cFF55FF55Unlocked|r")
            GameTooltip:AddLine("|cFFAAAAAARight-click to remove|r")
        elseif not ArePrereqsMet(n) then
            local missing = GetMissingPrereqs(n)
            GameTooltip:AddLine("|cFFFF5555Requires: " .. FormatPrereqList(missing) .. "|r")
        else
            local cost = AT.costs[n.tier or 1] or 0
            GameTooltip:AddLine("|cFF88FF88Can be unlocked|r")
            if cost > 0 then
                GameTooltip:AddLine("|cFFFFD700Cost: " .. cost ..
                    " Token" .. (cost == 1 and "" or "s") .. "|r")
            end
            GameTooltip:AddLine("|cFFAAAAAADouble-click to unlock|r")
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self, button)
        local n = self.node; if not n then return end
        local id = n.id
        if button == "LeftButton" then
            local now = GetTime()
            if lastClickId == id and (now - lastClickTime) < DCLICK_DELAY then
                lastClickId = nil; lastClickTime = 0
                SelectNode(id)
                if AT.unlocked[id] then
                    ChatInfo(n.name .. " is already unlocked.")
                elseif not ArePrereqsMet(n) then
                    local ids = CollectUnlockPath(id)
                    if #ids == 0 then
                        local missing = GetMissingPrereqs(n)
                        ChatInfo("Prerequisite not met: " .. FormatPrereqList(missing))
                    else
                        local cost   = ComputePathCost(ids)
                        local tokens = AT.prestigeTokens or 0
                        if cost > tokens then
                            ChatInfo(string.format(
                                "Path to %s costs %d tokens — you have %d.",
                                n.name, cost, tokens))
                        else
                            local msg = string.format(
                                "Unlock %d node(s) along the path to |cff1eff00%s|r?\n\n" ..
                                "Total cost: |cffFFD700%d Token%s|r\n" ..
                                "You have: %d",
                                #ids, n.name, cost, cost == 1 and "" or "s", tokens)
                            StaticPopup_Show("AT_CONFIRM_AUTOPATH", msg, nil,
                                { ids = ids, cost = cost })
                        end
                    end
                else
                    if AT.SendUnlockAIO then AT.SendUnlockAIO(id)
                    else Send("astral unlock " .. id) end
                end
            else
                lastClickId = id; lastClickTime = now
                SelectNode(id)
            end
        elseif button == "RightButton" then
            SelectNode(id)
            if not AT.unlocked[id] then
                ChatInfo(n.name .. " is not unlocked."); return
            end
            local deps = FindDependents(id)
            if #deps == 0 then
                if AT.SendRemoveAIO then AT.SendRemoveAIO(id)
                else Send("astral remove " .. id) end
                return
            end
            local chain = CollectRemovalChain(id)
            if #chain <= 1 then
                if AT.SendRemoveAIO then AT.SendRemoveAIO(id)
                else Send("astral remove " .. id) end
                return
            end
            local msg = string.format(
                "Remove |cff1eff00%s|r and |cffff8888%d|r dependent node(s)?\n\n" ..
                "Dependents are removed leaf-first before this node.\n" ..
                "Direct dependents: %s",
                n.name, #chain - 1,
                table.concat(deps, ", "))
            StaticPopup_Show("AT_CONFIRM_AUTOREMOVE", msg, nil, { ids = chain })
        end
    end)

    return btn
end

local function BindNodeButton(n)
    local btn = table.remove(nodeFree)
    if not btn then
        nodePool[#nodePool + 1] = CreateNodeButton()
        btn = nodePool[#nodePool]
    end
    btn.node   = n
    btn.nodeId = n.id
    local ico  = btn.icon
    ico:SetTexture((n.icon and n.icon ~= "") and ("Interface\\Icons\\" .. n.icon)
                                              or  "Interface\\Icons\\INV_Misc_Rune_08")
    PlaceNodeButton(btn, n)
    StyleNodeButton(btn, n)
    btn.borderFrame:Show()
    btn:Show()
    activeBtns[n.id] = btn
    return btn
end

local function ReleaseNodeButton(btn)
    btn.node, btn.nodeId = nil, nil
    btn.borderFrame:Hide()
    btn:Hide()
    nodeFree[#nodeFree + 1] = btn
end

local function ReleaseAllNodeButtons()
    for id, btn in pairs(activeBtns) do
        ReleaseNodeButton(btn)
        activeBtns[id] = nil
    end
end

local function ViewRect()
    local hs   = sf:GetHorizontalScroll()
    local vs   = sf:GetVerticalScroll()
    local sfW  = sf:GetWidth();  if sfW < 10 then sfW = 700 end
    local sfH  = sf:GetHeight(); if sfH < 10 then sfH = 400 end
    return hs - CULL_MARGIN, hs + sfW + CULL_MARGIN,
           vs - CULL_MARGIN, vs + sfH + CULL_MARGIN, hs, vs
end

local function GetDot(i)
    local d = dotPool[i]
    if not d then
        local rim = canvas:CreateTexture(nil, "BORDER")
        rim:SetTexture("Interface\\Buttons\\WHITE8X8")
        local icon = canvas:CreateTexture(nil, "ARTWORK")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        d = { rim = rim, icon = icon, iconName = nil }
        dotPool[i] = d
    end
    return d
end

local function PlaceDots()
    local size = NodeSize(2)
    local rim  = math.floor(size * 0.18)
    local hasRim = rim >= 1
    local full = size + rim * 2
    for i = 1, #AT.nodeList do
        local n  = AT.nodeList[i]
        local d  = GetDot(i)
        local cx = NX(n)
        local cy = -NY(n)

        if hasRim then
            d.rim:ClearAllPoints()
            d.rim:SetSize(full, full)
            d.rim:SetPoint("CENTER", canvas, "TOPLEFT", cx, cy)
            d.rim:Show()
        else
            d.rim:Hide()
        end

        local iconPath = (n.icon and n.icon ~= "")
            and ("Interface\\Icons\\" .. n.icon) or "Interface\\Icons\\INV_Misc_Rune_08"
        if d.iconName ~= iconPath then
            d.icon:SetTexture(iconPath)
            d.iconName = iconPath
        end
        d.icon:ClearAllPoints()
        d.icon:SetSize(size, size)
        d.icon:SetPoint("CENTER", canvas, "TOPLEFT", cx, cy)
        d.icon:Show()
    end
    for j = #AT.nodeList + 1, #dotPool do
        dotPool[j].rim:Hide(); dotPool[j].icon:Hide()
    end
end

local function StyleDots()
    for i = 1, #AT.nodeList do
        local n  = AT.nodeList[i]
        local d  = dotPool[i]; if not d then break end
        local tc = C_TIER[n.tier or 1] or C_TIER[1]
        if AT.unlocked[n.id] then
            d.rim:SetVertexColor(tc[1], tc[2], tc[3], 1.0)
            d.icon:SetDesaturated(false); d.icon:SetAlpha(1.0)
        elseif ArePrereqsMet(n) then
            d.rim:SetVertexColor(tc[1]*0.75, tc[2]*0.75, tc[3]*0.75, 0.90)
            d.icon:SetDesaturated(false); d.icon:SetAlpha(0.92)
        else
            d.rim:SetVertexColor(tc[1]*0.40, tc[2]*0.40, tc[3]*0.40, 0.70)
            d.icon:SetDesaturated(true);  d.icon:SetAlpha(0.55)
        end
    end
end

local function HideDots()
    for j = 1, #dotPool do
        dotPool[j].rim:Hide(); dotPool[j].icon:Hide()
    end
end

local function RedrawAllLines()
    ResetLinePool()
    local links = AT.links
    for i = 1, #links do
        local lk = links[i]
        local a, b = AT.nodes[lk.from], AT.nodes[lk.to]
        if a and b then DrawLine(NX(a), NY(a), NX(b), NY(b), lk.from, lk.to) end
    end
    UpdateLineColors()
end

local function ScheduleLineRedraw()
    ResetLinePool()
    linesDirty   = true
    lineRedrawAt = GetTime() + LINE_REDRAW_DELAY
end

local function RelayoutTree(immediateLines)
    if not (canvas and sf) then return end
    local minX, maxX, minY, maxY, hs, vs = ViewRect()

    if NodeSize(2) <= LOD_NODE_PX then
        local enteringLod = not AT.lodActive
        ReleaseAllNodeButtons()
        PlaceDots()
        if enteringLod then StyleDots() end
        AT.lodActive = true
    else
        HideDots()
        AT.lodActive = false
        for id, btn in pairs(activeBtns) do
            local n  = btn.node
            local nx, ny = NX(n), NY(n)
            if nx < minX or nx > maxX or ny < minY or ny > maxY then
                ReleaseNodeButton(btn); activeBtns[id] = nil
            else
                PlaceNodeButton(btn, n)
            end
        end
        for i = 1, #AT.nodeList do
            local n  = AT.nodeList[i]
            local nx, ny = NX(n), NY(n)
            if nx >= minX and nx <= maxX and ny >= minY and ny <= maxY
               and not activeBtns[n.id] then
                BindNodeButton(n)
            end
        end
    end

    if immediateLines then
        linesDirty = false
        RedrawAllLines()
    else
        ScheduleLineRedraw()
    end
    lastCullH, lastCullV, lastCullZoom = hs, vs, AT.zoom
    cullDirty = false
end

local function CullNodes()
    if not (canvas and sf) then return end
    if AT.lodActive then
        lastCullH, lastCullV = sf:GetHorizontalScroll(), sf:GetVerticalScroll()
        return
    end
    local minX, maxX, minY, maxY, hs, vs = ViewRect()
    for id, btn in pairs(activeBtns) do
        local n  = btn.node
        local nx, ny = NX(n), NY(n)
        if nx < minX or nx > maxX or ny < minY or ny > maxY then
            ReleaseNodeButton(btn); activeBtns[id] = nil
        end
    end
    for i = 1, #AT.nodeList do
        local n  = AT.nodeList[i]
        local nx, ny = NX(n), NY(n)
        if nx >= minX and nx <= maxX and ny >= minY and ny <= maxY
           and not activeBtns[n.id] then
            BindNodeButton(n)
        end
    end
    lastCullH, lastCullV = hs, vs
end

local function UpdateVisible() RelayoutTree(true) end
AT.UpdateVisible = UpdateVisible

local function ResizeCanvas()
    local maxX = treeExtentX * AT.zoom + PAD + NodeSize(3)
    local maxY = treeExtentY * AT.zoom + PAD + NodeSize(3)
    canvas:SetSize(math.max(maxX, 200), math.max(maxY, 200))
    if sf then
        sf:SetHorizontalScroll(math.min(sf:GetHorizontalScroll(), sf:GetHorizontalScrollRange()))
        sf:SetVerticalScroll(  math.min(sf:GetVerticalScroll(),   sf:GetVerticalScrollRange()))
    end
end

local function ApplyZoom(newZoom)
    AT.zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, newZoom))
    ResizeCanvas()
    cullDirty = true
end

local function FormatNodeBody(n)
    local lines = {}
    if n.desc and n.desc ~= "" then
        lines[#lines + 1] = "|cFFE0E0E0" .. n.desc .. "|r"
    end
    if n.effects and #n.effects > 0 then
        if #lines > 0 then lines[#lines + 1] = " " end
        for i = 1, #n.effects do
            lines[#lines + 1] = "|cFF7FFF7F" .. FormatEffect(n.effects[i]) .. "|r"
        end
    end
    return #lines > 0 and table.concat(lines, "\n") or " "
end

function SelectNode(id)
    AT.selectedId = id
    local n = AT.nodes[id]; if not n then return end
    infoName:SetText(n.name)
    infoDesc:SetText(FormatNodeBody(n))
    if infoIcon then
        if n.icon and n.icon ~= "" then
            infoIcon:SetTexture("Interface\\Icons\\" .. n.icon)
            infoIcon:Show()
        else
            infoIcon:Hide()
        end
    end
    if AT.unlocked[id] then
        unlockBtn:Hide(); removeBtn:Show()
    else
        removeBtn:Hide(); unlockBtn:Show()
        if ArePrereqsMet(n) then
            local cost = AT.costs[n.tier or 1] or 0
            unlockBtn:SetText(cost > 0
                and ("Unlock  [" .. cost .. " Token" .. (cost == 1 and "]" or "s]"))
                or  "Unlock")
            unlockBtn:Enable()
        else
            local missing = GetMissingPrereqs(n)
            unlockBtn:SetText("Requires: " .. FormatPrereqList(missing))
            unlockBtn:Disable()
        end
    end
end

function AT.RefreshNodes()
    if AT.lodActive then
        StyleDots()
    else
        for _, btn in pairs(activeBtns) do
            if btn.node then StyleNodeButton(btn, btn.node) end
        end
    end
    UpdateLineColors()
    if AT.selectedId    then SelectNode(AT.selectedId)    end
    if AT.RefreshSummary then AT.RefreshSummary() end
end

function AT.RenderTree()
    if not canvas then return end

    ReleaseAllNodeButtons()
    ResetLinePool()
    AT.selectedId  = nil
    lastClickId    = nil
    lastClickTime  = 0
    infoName:SetText("Select a node")
    infoDesc:SetText("")
    if infoIcon then infoIcon:Hide() end
    unlockBtn:Hide(); removeBtn:Hide()

    AT.zoom = SCALE
    CalcOffsets()

    wipe(AT.nodeList)
    treeExtentX, treeExtentY = 0, 0
    for _, n in pairs(AT.nodes) do
        AT.nodeList[#AT.nodeList + 1] = n
        local ex = n.posX + AT.offX
        local ey = n.posY + AT.offY
        if ex > treeExtentX then treeExtentX = ex end
        if ey > treeExtentY then treeExtentY = ey end
    end

    ResizeCanvas()
    AT.rendered  = true
    cullDirty    = true
    AT.lodActive = false
    UpdateVisible()

    if mainFrame:IsShown() then AT.FocusView() end
end

local function RestoreSavedView()
    if not (sf and ProjectAstralAT_DB and ProjectAstralAT_DB.view) then return false end
    local v = ProjectAstralAT_DB.view
    if not v.zoom then return false end
    ApplyZoom(math.max(FIT_ZOOM_MIN, math.min(ZOOM_MAX, v.zoom)))
    CenterOnOrigin()
    return true
end

local function SaveCurrentView()
    if not (mainFrame and ProjectAstralAT_DB) then return end
    ProjectAstralAT_DB.view = { zoom = AT.zoom }
end
AT.SaveCurrentView = SaveCurrentView

function AT.FocusView()
    if not (sf and mainFrame) then return end
    AT.focusNeeded = false
    if RestoreSavedView() then
        UpdateVisible()
        return
    end
    FitView()
    ApplyZoom(AT.zoom)
    sf:SetHorizontalScroll(0)
    sf:SetVerticalScroll(0)
    CenterOnOrigin()
    UpdateVisible()
end

StaticPopupDialogs["AT_CONFIRM_RESET"] = {
    text         = "Remove ALL unlocked skill nodes?\n\nThis cannot be undone.",
    button1      = "Reset All",
    button2      = "Cancel",
    OnAccept     = function()
        AT.ResetAllNodes()
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

local BULK_CHUNK_SIZE = 30
local function SendBulkCsv(verb, ids)
    if type(ids) ~= "table" or #ids == 0 then return 0 end
    local sent = 0
    local i = 1
    while i <= #ids do
        local chunk = {}
        for j = i, math.min(i + BULK_CHUNK_SIZE - 1, #ids) do
            chunk[#chunk + 1] = tostring(ids[j])
        end
        Send("astral " .. verb .. " " .. table.concat(chunk, ","))
        sent = sent + 1
        i = i + BULK_CHUNK_SIZE
    end
    return sent
end

function AT.SendUnlockChain(ids, label)
    if type(ids) ~= "table" or #ids == 0 then return end
    for k in pairs(unlockQueue) do unlockQueue[k] = nil end
    if AT.SendUnlockBulkAIO then
        AT.SendUnlockBulkAIO(ids)
    else
        SendBulkCsv("unlockbulk", ids)
    end
    ChatInfo(string.format("Unlocking %d node(s)%s...", #ids,
        label and (" for " .. label) or ""))
end

function AT.LoadBuild(removeOrder, addOrder, label)
    for k in pairs(removeQueue) do removeQueue[k] = nil end
    for k in pairs(unlockQueue) do unlockQueue[k] = nil end
    pendingUnlockChain = nil

    local nr = removeOrder and #removeOrder or 0
    local na = addOrder    and #addOrder    or 0
    if nr == 0 and na == 0 then
        ChatInfo("Build already matches current state.")
        return
    end

    if AT.SendLoadBuildAIO then
        AT.__lastLoadBuild = { remove = removeOrder or {}, add = addOrder or {} }
        AT.SendLoadBuildAIO(removeOrder, addOrder, label)
        ChatInfo(string.format("Loading %s — %d remove / %d add...",
            label or "build", nr, na))
        return
    end

    if nr > 0 then
        if na > 0 then pendingUnlockChain = addOrder end
        SendBulkCsv("removebulk", removeOrder)
        local trailer = na > 0 and (" then unlock " .. na) or ""
        ChatInfo(string.format("Loading %s — remove %d%s node(s)...",
            label or "build", nr, trailer))
    else
        AT.SendUnlockChain(addOrder, label)
    end
end

StaticPopupDialogs["AT_CONFIRM_AUTOPATH"] = {
    text         = "%s",
    button1      = "Unlock Path",
    button2      = "Cancel",
    OnAccept     = function(self, data)
        if not data or not data.ids then return end
        AT.SendUnlockChain(data.ids, "the path")
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

function AT.SendRemoveChain(ids, label)
    if type(ids) ~= "table" or #ids == 0 then return end
    for k in pairs(removeQueue) do removeQueue[k] = nil end
    if AT.SendRemoveBulkAIO then
        AT.SendRemoveBulkAIO(ids)
    else
        SendBulkCsv("removebulk", ids)
    end
    ChatInfo(string.format("Removing %d node(s)%s...", #ids,
        label and (" for " .. label) or ""))
end

function AT.ResetAllNodes(label)
    if AT.SendResetAllAIO then
        AT.SendResetAllAIO()
    else
        Send("astral resetall")
    end
    ChatInfo(string.format("Resetting all unlocked nodes%s...",
        label and (" for " .. label) or ""))
end

StaticPopupDialogs["AT_CONFIRM_AUTOREMOVE"] = {
    text         = "%s",
    button1      = "Remove Chain",
    button2      = "Cancel",
    OnAccept     = function(self, data)
        if not data or not data.ids then return end
        AT.SendRemoveChain(data.ids, "the cascade")
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
}

local summaryRows = {}

local PARAGON_STAT_TO_EFFECT = {
    str  = "STRENGTH_PCT",
    agi  = "AGILITY_PCT",
    sta  = "STAMINA_PCT",
    intl = "INTELLECT_PCT",
    spi  = "SPIRIT_PCT",
    sp   = "BONUS_SPELLPOWER_PCT",
    ap   = "ATTACK_POWER_PCT",
}

local function NodeTotals()
    local totals, count = {}, 0
    for id in pairs(AT.unlocked) do
        local n = AT.nodes[id]
        if n and n.effects then
            count = count + 1
            for i = 1, #n.effects do
                local e = n.effects[i]
                totals[e.type] = (totals[e.type] or 0) + e.value
            end
        end
    end
    return totals, count
end

local function ParagonTotals()
    local totals = {}
    local pg = PA.Paragon and PA.Paragon.state
    if pg then
        for slot, etype in pairs(PARAGON_STAT_TO_EFFECT) do
            local pts = pg[slot] or 0
            local pctPerPt = (pg.pct and pg.pct[slot]) or 0
            if pts > 0 and pctPerPt > 0 then
                totals[etype] = (totals[etype] or 0) + pts * pctPerPt
            end
        end
    end
    return totals
end

local function ComputeTotals()
    local totals, count = NodeTotals()
    for etype, v in pairs(ParagonTotals()) do
        totals[etype] = (totals[etype] or 0) + v
    end
    return totals, count
end

local function RefreshSummary()
    if not summaryFrame then return end

    for i = 1, #summaryRows do summaryRows[i]:Hide() end

    local totals, count = ComputeTotals()
    summaryFrame.countText:SetText(
        count == 0
        and "|cFF888888No nodes unlocked yet.|r"
        or  ("|cFFAAAACC" .. count .. " unlocked node" ..
             (count == 1 and "" or "s") .. " contributing|r"))

    local child = summaryFrame.scrollChild
    if not child then return end

    if count == 0 or not next(totals) then
        child:SetHeight(1)
        return
    end

    local rowIdx, y = 0, -4
    local function pickRow()
        rowIdx = rowIdx + 1
        local r = summaryRows[rowIdx]
        if not r then
            r = child:CreateFontString(nil, "OVERLAY")
            UI.SetTextFont(r, 12)
            summaryRows[rowIdx] = r
        else
            r:SetParent(child)
        end
        return r
    end

    for _, group in ipairs(SUMMARY_GROUPS) do
        local has = false
        for _, etype in ipairs(group.types) do
            if totals[etype] then has = true; break end
        end
        if has then
            local hdr = pickRow()
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", child, "TOPLEFT", 0, y)
            hdr:SetText(group.name)
            hdr:SetTextColor(unpack(NV.txtGold))
            hdr:Show()
            y = y - 16

            for _, etype in ipairs(group.types) do
                local v = totals[etype]
                if v then
                    local row = pickRow()
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", child, "TOPLEFT", 10, y)
                    row:SetText(FormatEffect({ type = etype, value = v }))
                    row:SetTextColor(unpack(NV.txtGood))
                    row:Show()
                    y = y - 14
                end
            end
            y = y - 8
        end
    end

    child:SetHeight(math.max(1, -y + 4))
end

local function CreateSummaryUI()
    local hub = PA.mainFrame or UIParent
    summaryFrame = CreateFrame("Frame", "AT_SummaryFrame", hub)
    summaryFrame:SetWidth(280)
    summaryFrame:SetPoint("TOPLEFT",    hub, "TOPRIGHT", 8, 0)
    summaryFrame:SetPoint("BOTTOMLEFT", hub, "BOTTOMRIGHT", 8, 0)
    summaryFrame:SetFrameStrata(hub:GetFrameStrata() or "HIGH")
    summaryFrame:SetFrameLevel((hub:GetFrameLevel() or 0) + 1)
    summaryFrame:Hide()

    NV.Navy(summaryFrame, NV.panel, NV.edge)
    local glow = summaryFrame:CreateTexture(nil, "BORDER")
    glow:SetTexture("Interface\\Buttons\\WHITE8X8")
    glow:SetPoint("TOPLEFT", summaryFrame, "TOPLEFT", 1, -1)
    glow:SetPoint("TOPRIGHT", summaryFrame, "TOPRIGHT", -1, -1)
    glow:SetHeight(40)
    glow:SetGradientAlpha("VERTICAL", 0.94, 0.82, 0.43, 0, 0.94, 0.82, 0.43, 0.10)

    local titleBar = NV.Title(summaryFrame, "Total Bonuses", 15)
    titleBar:SetPoint("TOPLEFT", summaryFrame, "TOPLEFT", 14, -14)

    local close = CreateFrame("Button", nil, summaryFrame, "UIPanelCloseButton")
    PA.UI.CosmicCloseButton(close)
    close:SetPoint("TOPRIGHT", summaryFrame, "TOPRIGHT", -2, -2)
    close:HookScript("OnClick", function()
        if ProjectAstralAT_DB then ProjectAstralAT_DB.summaryOpen = false end
    end)

    summaryFrame.countText = summaryFrame:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(summaryFrame.countText, 11)
    summaryFrame.countText:SetPoint("TOPLEFT", summaryFrame, "TOPLEFT", 14, -38)
    local rule = summaryFrame:CreateTexture(nil, "ARTWORK")
    rule:SetTexture("Interface\\Buttons\\WHITE8X8")
    rule:SetVertexColor(NV.edge[1], NV.edge[2], NV.edge[3], 1)
    rule:SetPoint("TOPLEFT", summaryFrame, "TOPLEFT", 10, -50)
    rule:SetPoint("TOPRIGHT", summaryFrame, "TOPRIGHT", -10, -50)
    rule:SetHeight(1)
    local SCROLL_W = 280 - 14 - 32
    local scroll = CreateFrame("ScrollFrame", "AT_SummaryScroll", summaryFrame,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     summaryFrame, "TOPLEFT",     14, -54)
    scroll:SetPoint("BOTTOMRIGHT", summaryFrame, "BOTTOMRIGHT", -32, 14)

    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(SCROLL_W, 1)
    scroll:SetScrollChild(child)

    summaryFrame.scroll       = scroll
    summaryFrame.scrollChild  = child
    summaryFrame.scrollChildW = SCROLL_W

    summaryFrame:SetScript("OnShow", RefreshSummary)
end

AT.NodeTotals    = NodeTotals
AT.ParagonTotals = ParagonTotals
AT.EffectMeta    = EFFECT_META
AT.SummaryGroups = SUMMARY_GROUPS

local statsListeners = {}
function AT.OnStatsChanged(fn)
    statsListeners[#statsListeners + 1] = fn
end

AT.RefreshSummary = function()
    RefreshSummary()
    for _, fn in ipairs(statsListeners) do pcall(fn) end
end

local function CreateUI(embedParent)
    mainFrame = CreateFrame("Frame", "AT_MainFrame", embedParent or UIParent)
    if embedParent then
        mainFrame:SetAllPoints(embedParent)
        mainFrame:SetFrameLevel(embedParent:GetFrameLevel() + 1)
    else
        mainFrame:SetSize(780, 580)
        mainFrame:SetPoint("CENTER")
        mainFrame:SetMovable(true)
        mainFrame:EnableMouse(true)
        mainFrame:RegisterForDrag("LeftButton")
        mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
        mainFrame:SetScript("OnDragStop",  mainFrame.StopMovingOrSizing)
        mainFrame:SetFrameStrata("HIGH")
        mainFrame:SetFrameLevel(1)
        mainFrame:Hide()

        NV.Navy(mainFrame, NV.deep, NV.goldEdge)

        local star = mainFrame:CreateTexture(nil, "BACKGROUND")
        star:SetTexture("Interface\\TalentFrame\\TalentFrameBackground")
        star:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     14, -14)
        star:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -14,  14)
        star:SetAlpha(0.10)

        local titleBar = NV.Title(mainFrame, "Astral Skill Tree", 15)
        titleBar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 16, -14)

        MakeSep(mainFrame, 546)

        local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
        PA.UI.CosmicCloseButton(close)
        close:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -2, -2)
    end
    sf = CreateFrame("ScrollFrame", "AT_ScrollFrame", mainFrame)
    sf:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",      10, embedParent and -4 or -36)
    sf:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT",  -10, 144)
    sf:EnableMouse(true)
    sf:EnableMouseWheel(true)

    sf:SetScript("OnMouseWheel", function(self, delta)
        local oldZoom = AT.zoom
        local newZoom = (delta > 0) and (oldZoom * ZOOM_FACTOR)
                                     or (oldZoom / ZOOM_FACTOR)
        newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, newZoom))
        if newZoom == oldZoom then return end

        local scale = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        local viewportX = cx - self:GetLeft()
        local viewportY = self:GetTop() - cy

        local insideViewport =
            viewportX >= 0 and viewportY >= 0 and
            viewportX <= self:GetWidth() and viewportY <= self:GetHeight()

        if not insideViewport then
            ApplyZoom(newZoom)
            return
        end

        local hs = self:GetHorizontalScroll()
        local vs = self:GetVerticalScroll()
        local ratio = newZoom / oldZoom

        ApplyZoom(newZoom)

        local newHS = (hs + viewportX) * ratio - viewportX
        local newVS = (vs + viewportY) * ratio - viewportY
        newHS = math.max(0, math.min(newHS, self:GetHorizontalScrollRange()))
        newVS = math.max(0, math.min(newVS, self:GetVerticalScrollRange()))
        self:SetHorizontalScroll(newHS)
        self:SetVerticalScroll(newVS)
    end)

    sf:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        isPanning  = true
        panSX, panSY = GetCursorPosition()
        panStartH  = self:GetHorizontalScroll()
        panStartV  = self:GetVerticalScroll()
    end)

    sf:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then isPanning = false end
    end)

    sf:SetScript("OnUpdate", function(self)
        if isPanning then
            local cx, cy = GetCursorPosition()
            local sc = self:GetEffectiveScale()
            self:SetHorizontalScroll(math.max(0, math.min(
                panStartH - (cx - panSX)/sc, self:GetHorizontalScrollRange())))
            self:SetVerticalScroll(math.max(0, math.min(
                panStartV + (cy - panSY)/sc, self:GetVerticalScrollRange())))
        end
        if cullDirty or AT.zoom ~= lastCullZoom then
            RelayoutTree(false)
        elseif self:GetHorizontalScroll() ~= lastCullH
            or self:GetVerticalScroll()   ~= lastCullV then
            CullNodes()
        end
        if linesDirty and GetTime() >= lineRedrawAt then
            linesDirty = false
            RedrawAllLines()
        end
    end)

    canvas = CreateFrame("Frame", "AT_Canvas", sf)
    canvas:SetSize(800, 600)
    -- above the pan/zoom scroll frame (it takes the mouse), wherever the hub puts it
    canvas:SetFrameLevel(math.max(3, sf:GetFrameLevel() + 1))
    sf:SetScrollChild(canvas)

    local bottomDock = CreateFrame("Frame", nil, mainFrame)
    bottomDock:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
    bottomDock:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    bottomDock:SetHeight(152)
    bottomDock:SetFrameLevel(16)
    NV.Navy(bottomDock, NV.deep, NV.edge)
    local dockRule = PA.UI.SolidFill(bottomDock, NV.edge, "ARTWORK")
    dockRule:SetPoint("TOPLEFT", bottomDock, "TOPLEFT", 10, -1)
    dockRule:SetPoint("TOPRIGHT", bottomDock, "TOPRIGHT", -10, -1)
    dockRule:SetHeight(1)

    local toolbar = CreateFrame("Frame", nil, mainFrame)
    toolbar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  10, 118)
    toolbar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 118)
    toolbar:SetHeight(30)
    toolbar:SetFrameLevel(25)

    local function AddTip(b, title, body)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(title, 1, 1, 1)
            if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Zoom Out button
    local zoomOutBtn = UI.MakeButton(toolbar, "-", {
        w = 28, h = 22, variant = "secondary",
        onClick = function()
            local oldZoom = AT.zoom
            local newZoom = oldZoom / ZOOM_FACTOR
            newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, newZoom))
            if newZoom ~= oldZoom then
                ApplyZoom(newZoom)
                UpdateVisible()
            end
        end,
    })
    zoomOutBtn:SetPoint("LEFT", toolbar, "LEFT", 6, 1)
    UI.SetTextFont(zoomOutBtn.text, 14)
    zoomOutBtn:SetFrameLevel(26)
    AddTip(zoomOutBtn, "Zoom Out (-)",
                      "Zoom out to see more of the tree.\nYou can also use mouse wheel.")

    -- Zoom In button
    local zoomInBtn = UI.MakeButton(toolbar, "+", {
        w = 28, h = 22, variant = "secondary",
        onClick = function()
            local oldZoom = AT.zoom
            local newZoom = oldZoom * ZOOM_FACTOR
            newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, newZoom))
            if newZoom ~= oldZoom then
                ApplyZoom(newZoom)
                UpdateVisible()
            end
        end,
    })
    zoomInBtn:SetPoint("LEFT", zoomOutBtn, "RIGHT", 4, 0)
    UI.SetTextFont(zoomInBtn.text, 14)
    zoomInBtn:SetFrameLevel(26)
    AddTip(zoomInBtn, "Zoom In (+)",
                      "Zoom in to see more detail.\nYou can also use mouse wheel.")

    local buildsBtn = UI.MakeButton(toolbar, "Builds", {
        w = 78, h = 28, variant = "secondary",
        onClick = function()
            if AT.ToggleBuildManager then AT.ToggleBuildManager() end
        end,
    })
    buildsBtn:SetPoint("LEFT", zoomInBtn, "RIGHT", 8, 0)
    UI.SetTextFont(buildsBtn.text, 12)
    buildsBtn:SetFrameLevel(26)
    AddTip(buildsBtn, "Builds",
                      "Save, load, import/export named skill-tree builds.\n" ..
                      "Auto-path unlocks each missing node when loading.")

    local centerBtn = UI.MakeButton(toolbar, "Center", {
        w = 78, h = 28, variant = "secondary",
        onClick = function()
            if next(AT.nodes) then CenterOnOrigin() end
        end,
    })
    centerBtn:SetPoint("RIGHT", toolbar, "RIGHT", -6, 1)
    UI.SetTextFont(centerBtn.text, 12)
    centerBtn:SetFrameLevel(26)
    AddTip(centerBtn, "Center on Origin",
                      "Centers the view on the Astral Origin node.")

    local resetBtn = UI.MakeButton(toolbar, "Reset All", {
        w = 92, h = 28, variant = "danger",
        onClick = function()
            if not next(AT.unlocked) then ChatInfo("No nodes unlocked."); return end
            StaticPopup_Show("AT_CONFIRM_RESET")
        end,
    })
    resetBtn:SetPoint("RIGHT", centerBtn, "LEFT", -12, 0)
    UI.SetTextFont(resetBtn.text, 12)
    resetBtn:SetFrameLevel(26)
    AddTip(resetBtn, "|cFFFF5555Reset all nodes|r",
                     "Removes all unlocked nodes.\nThis cannot be undone.")

    summaryBtn = UI.MakeButton(toolbar, "Bonuses", {
        w = 84, h = 28, variant = "secondary",
        onClick = function()
            if not summaryFrame then return end
            local newState
            if summaryFrame:IsShown() then
                summaryFrame:Hide()
                newState = false
            else
                summaryFrame:Show()
                newState = true
            end
            if ProjectAstralAT_DB then ProjectAstralAT_DB.summaryOpen = newState end
        end,
    })
    summaryBtn:SetPoint("RIGHT", resetBtn, "LEFT", -12, 0)
    UI.SetTextFont(summaryBtn.text, 12)
    summaryBtn:SetFrameLevel(26)
    AddTip(summaryBtn, "Total Bonuses",
                       "Show / hide a summary of all stat bonuses your unlocked nodes give you.")

    local info = CreateFrame("Frame", nil, mainFrame)
    info:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  10, 10)
    info:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
    info:SetHeight(104)
    info:SetFrameLevel(18)
    -- selected-node card: navy panel, gold tint + bar, icon in a navy frame
    NV.Navy(info, NV.panel, NV.edge)
    NV.GoldAccent(info)

    local iconBox = CreateFrame("Frame", nil, info)
    iconBox:SetSize(38, 38)
    iconBox:SetPoint("TOPLEFT", info, "TOPLEFT", 12, -10)
    NV.Navy(iconBox, UI.Tinted({ 0.020, 0.030, 0.090, 1 }), NV.edge)
    infoIcon = iconBox:CreateTexture(nil, "ARTWORK")
    infoIcon:SetPoint("TOPLEFT", iconBox, "TOPLEFT", 2, -2)
    infoIcon:SetPoint("BOTTOMRIGHT", iconBox, "BOTTOMRIGHT", -2, 2)
    infoIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    infoIcon:Hide()

    infoName = info:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(infoName, 15)
    infoName:SetPoint("TOPLEFT", info, "TOPLEFT", 60, -12)
    infoName:SetText("Select a node")
    infoName:SetTextColor(unpack(NV.txtGold))

    infoDesc = info:CreateFontString(nil, "OVERLAY")
    UI.SetTextFont(infoDesc, 12)
    infoDesc:SetPoint("TOPLEFT",  info, "TOPLEFT",   60, -34)
    infoDesc:SetPoint("TOPRIGHT", info, "TOPRIGHT", -152, -34)
    infoDesc:SetJustifyH("LEFT")
    infoDesc:SetSpacing(2)
    infoDesc:SetTextColor(unpack(NV.txtMuted))

    unlockBtn = UI.MakeButton(info, "Unlock", {
        w = 134, h = 26, variant = "gold",
        onClick = function()
            if not AT.selectedId then return end
            if AT.SendUnlockAIO then AT.SendUnlockAIO(AT.selectedId)
            else Send("astral unlock " .. AT.selectedId) end
        end,
    })
    unlockBtn:SetPoint("TOPRIGHT", info, "TOPRIGHT", -8, -10)
    unlockBtn:SetFrameLevel(19)
    unlockBtn:Hide()

    removeBtn = UI.MakeButton(info, "Remove", {
        w = 134, h = 26, variant = "danger",
        onClick = function()
            if not AT.selectedId then return end
            local deps = FindDependents(AT.selectedId)
            if #deps > 0 then
                ChatInfo("Cannot remove: " .. table.concat(deps, ", ") .. " depends on this.")
                return
            end
            if AT.SendRemoveAIO then AT.SendRemoveAIO(AT.selectedId)
            else Send("astral remove " .. AT.selectedId) end
        end,
    })
    removeBtn:SetPoint("TOPRIGHT", info, "TOPRIGHT", -8, -42)
    removeBtn:SetFrameLevel(19)
    removeBtn:Hide()

    mainFrame:SetScript("OnShow", function()
        if AT.rendered then
            if AT.focusNeeded then AT.FocusView() end
        elseif next(AT.nodes) then
            AT.RenderTree()
        elseif AT.RequestInitialStateAIO then
            AT.RequestInitialStateAIO()
        end
    end)

    mainFrame:HookScript("OnHide", function()
        AT.focusNeeded = true
        if AT.SaveCurrentView then AT.SaveCurrentView() end
    end)
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", function(_, _, msg, author)
    return msg:sub(1, 7) == ".astral" and author == UnitName("player")
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        ProjectAstralAT_DB = ProjectAstralAT_DB or {}
        if ProjectAstralAT_DB.summaryOpen == nil then
            ProjectAstralAT_DB.summaryOpen = false
        end
        ProjectAstralAT_DB.view = ProjectAstralAT_DB.view or nil
        ProjectAstralAT_DB.summaryPos = nil
    end
end)

local function BuildTreeTab(panel)
    if not mainFrame then
        CreateUI(panel)
        CreateSummaryUI()
        if mainFrame and summaryFrame then
            mainFrame:HookScript("OnShow", function()
                if ProjectAstralAT_DB and ProjectAstralAT_DB.summaryOpen then
                    summaryFrame:Show()
                end
            end)
        end
    end

    panel:SetScript("OnShow", function()
        if mainFrame and not mainFrame:IsShown() then mainFrame:Show() end
        if AT.rendered then
            if AT.focusNeeded then AT.FocusView() end
        elseif next(AT.nodes) then
            AT.RenderTree()
        elseif AT.RequestInitialStateAIO then
            AT.RequestInitialStateAIO()
        end
    end)
    panel:HookScript("OnHide", function()
        AT.focusNeeded = true
        if mainFrame then mainFrame:Hide() end
    end)
end

local function ToggleTreeFrame()
    local mf = ProjectAstral.mainFrame
    if not mf then return end
    if mf:IsShown() and mf._activeTabId == "astral_tree" then
        mf:Hide()
    else
        mf:Show()
        mf:SwitchTab("astral_tree")
        if mf._tabBar then mf._tabBar:SelectTab("astral_tree") end
    end
end

SLASH_ASTRALTREE1 = "/astraltree"
SLASH_ASTRALTREE2 = "/at"
SlashCmdList["ASTRALTREE"] = ToggleTreeFrame

ProjectAstral:RegisterModule("astral_tree", "Astral Skill Tree", ToggleTreeFrame, {
    subtitle = "Spend Tokens on permanent passive bonuses for your character.",
})
ProjectAstral:RegisterTabContent("astral_tree", BuildTreeTab)
